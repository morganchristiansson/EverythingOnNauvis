-- Dev-only verifier for scrap (holmium-off config): charts a square around
-- spawn, generates all chunks synchronously in on_init, then reports:
--   - scrap entity census + per-tile audit (must be 0 on volcano/gleba/aquilo
--     water tiles, off every other ore's patch -> nearest-ore distance)
--   - nearest-non-scrap-resource distance distribution per scrap entity
--     (overlap = distance < 2 tiles of a 2x2 ore box)
--   - coverage % of nauvis-plains land tiles (frequency-behavior anchor;
--     vanilla: cells < min(0.1*6, 0.05+0.05*6)=0.35 at 600%, tile prob 0.5 ->
--     ~17% of land; at default ~5%).
-- Writes tests/eon-probe-scrap report via helpers.write_file.
local RADIUS = 1600
local AREA = { { -RADIUS, -RADIUS }, { RADIUS, RADIUS } }

local function tile_class(name)
  if string.sub(name, 1, 8) == "volcanic" or name == "lava" or name == "lava-hot" then
    return "volcano"
  end
  for _, p in pairs({ "wetland-", "lowland-", "midland-", "highland-", "pit-rock", "gleba-dee", "natural-" }) do
    if string.sub(name, 1, string.len(p)) == p then return "gleba" end
  end
  if string.sub(name, 1, 4) == "snow" or string.sub(name, 1, 3) == "ice-"
     or string.sub(name, 1, 4) == "brash" or name == "ammoniacal-ocean" or name == "ammoniacal-ocean-2" then
    return "aquilo"
  end
  if name == "water" or name == "deepwater" then return "water" end
  return "land"
end

script.on_init(function()
  helpers.write_file("eon-scrap-started.txt", "on_init fired at tick " .. game.tick)
  local surface = game.surfaces["nauvis"]
  game.forces.player.chart(surface, AREA)
  surface.request_to_generate_chunks({ 0, 0 }, math.ceil(RADIUS / 32) + 2)
  surface.force_generate_chunk_requests()

  local out = { seed = game.surfaces["nauvis"].map_gen_settings.seed, radius = RADIUS }

  -- Cell-indexed non-scrap resources (64px cells, 3x3 ring lookup).
  local others_by_cell = {}
  local res_tally = {}
  for _, e in pairs(surface.find_entities_filtered({ area = AREA, type = "resource" })) do
    res_tally[e.name] = (res_tally[e.name] or 0) + 1
    if e.name ~= "scrap" then
      local c = math.floor(e.position.x / 64) .. "," .. math.floor(e.position.y / 64)
      local cell = others_by_cell[c]
      if not cell then cell = {}; others_by_cell[c] = cell end
      cell[#cell + 1] = { x = e.position.x, y = e.position.y }
    end
  end
  out["all_resources"] = res_tally

  -- Scrap census + tile audit + nearest-other-ore distance.
  local scrap_entities, scrap_land_entities, scrap_rich = 0, 0, 0
  local tile_hist = {}
  local dist_buckets = { ["lt2"] = 0, ["2-4"] = 0, ["5-9"] = 0, ["10-24"] = 0, ["25plus"] = 0 }
  local dists = {}
  local leak_samples = {}
  local gleba_y = {}
  for _, e in pairs(surface.find_entities_filtered({ area = AREA, name = "scrap" })) do
    scrap_entities = scrap_entities + 1
    scrap_rich = scrap_rich + (e.amount or 0)
    local p = e.position
    local t = surface.get_tile(math.floor(p.x), math.floor(p.y)).name
    local cls = tile_class(t)
    if cls == "land" then scrap_land_entities = scrap_land_entities + 1 end
    tile_hist[cls] = (tile_hist[cls] or 0) + 1
    if (cls == "volcano" or cls == "gleba" or cls == "water" or cls == "aquilo") and #leak_samples < 200 then
      leak_samples[#leak_samples + 1] = { x = math.floor(p.x), y = math.floor(p.y), t = t, cls = cls }
    end
    if cls == "gleba" then
      local yb = "y<900"
      if p.y >= 900 and p.y < 1000 then yb = "900-999"
      elseif p.y >= 1000 and p.y < 1100 then yb = "1000-1099"
      elseif p.y >= 1100 and p.y < 1300 then yb = "1100-1299"
      elseif p.y >= 1300 then yb = "1300+" end
      gleba_y[yb] = (gleba_y[yb] or 0) + 1
    end

    local best = nil
    local cx, cy = math.floor(p.x / 64), math.floor(p.y / 64)
    for dx = -1, 1 do
      for dy = -1, 1 do
        local cell = others_by_cell[(cx + dx) .. "," .. (cy + dy)]
        if cell then
          for _, o in pairs(cell) do
            local d2 = (o.x - p.x) * (o.x - p.x) + (o.y - p.y) * (o.y - p.y)
            if not best or d2 < best then best = d2 end
          end
        end
      end
    end
    local d = best and math.sqrt(best) or 9999
    dists[#dists + 1] = d
    if d < 2 then dist_buckets["lt2"] = dist_buckets["lt2"] + 1
    elseif d < 5 then dist_buckets["2-4"] = dist_buckets["2-4"] + 1
    elseif d < 10 then dist_buckets["5-9"] = dist_buckets["5-9"] + 1
    elseif d < 25 then dist_buckets["10-24"] = dist_buckets["10-24"] + 1
    else dist_buckets["25plus"] = dist_buckets["25plus"] + 1 end
  end
  table.sort(dists)
  local function pct(q)
    if #dists == 0 then return -1 end
    return math.floor(dists[math.min(#dists, math.max(1, math.floor(#dists * q) + 1))])
  end
  out["scrap_entities"] = scrap_entities
  out["scrap_on_land_entities"] = scrap_land_entities
  out["scrap_tile_hist"] = tile_hist
  out["scrap_total_richness"] = scrap_rich
  out["scrap_nearest_ore_dist_p50"] = pct(0.5)
  out["scrap_nearest_ore_dist_p90"] = pct(0.9)
  out["scrap_nearest_ore_dist_max"] = dists[#dists] and math.floor(dists[#dists]) or -1
  out["scrap_nearest_ore_buckets"] = dist_buckets
  if #leak_samples > 0 then
    table.sort(leak_samples, function(a, b) return (a.cls == b.cls and a.y == b.y and a.x < b.x) or (a.cls == b.cls and a.y < b.y) or a.cls < b.cls end)
  end
  out["gleba_scrap_by_y"] = gleba_y
  out["leak_samples"] = leak_samples

  -- Land census on an 8px grid over the area: nauvis-plains land tiles are
  -- the region scrap is allowed to use (excludes water + other biomes).
  local land_n, water_n, other_biomes = 0, 0, 0
  local y = -RADIUS
  while y <= RADIUS do
    local x = -RADIUS
    while x <= RADIUS do
      local cls = tile_class(surface.get_tile(x, y).name)
      if cls == "land" then land_n = land_n + 1
      elseif cls == "water" then water_n = water_n + 1
      else other_biomes = other_biomes + 1 end
      x = x + 8
    end
    y = y + 8
  end
  out["land_samples"] = land_n
  out["water_samples"] = water_n
  out["other_biome_samples"] = other_biomes
  -- Coverage: each scrap entity is 2x2 tiles; approx fraction of allowed land.
  out["scrap_coverage_pct_approx"] = land_n == 0 and -1 or
      math.floor(10000 * (4 * scrap_entities) / (land_n * 64)) / 100

  -- Scrap patches (64px cells) for the shape: count + size quantiles.
  local cells = {}
  for _, e in pairs(surface.find_entities_filtered({ area = AREA, name = "scrap" })) do
    local p = e.position
    local key = math.floor(p.x / 64) .. "," .. math.floor(p.y / 64)
    cells[key] = (cells[key] or 0) + 1
  end
  local sizes = {}
  for _, n in pairs(cells) do sizes[#sizes + 1] = n end
  table.sort(sizes)
  local function spct(q)
    if #sizes == 0 then return -1 end
    return sizes[math.min(#sizes, math.max(1, math.floor(#sizes * q) + 1))]
  end
  out["scrap_64px_cells"] = #sizes
  out["scrap_cell_size_p50"] = spct(0.5)
  out["scrap_cell_size_p90"] = spct(0.9)
  out["scrap_cell_size_max"] = sizes[#sizes] or -1

  helpers.write_file("eon-scrap-report.json", helpers.table_to_json(out))
end)