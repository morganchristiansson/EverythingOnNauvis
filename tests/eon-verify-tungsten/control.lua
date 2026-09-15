-- Dev-only verifier: charts a square around spawn, waits until its chunks are
-- generated, then clusters tungsten-ore entities into patches and lava tiles
-- into volcanoes, and writes a JSON report via game.write_file.
local RADIUS = 1600
local AREA = { { -RADIUS, -RADIUS }, { RADIUS, RADIUS } }

local function is_volcano_tile(name)
  return string.sub(name, 1, 8) == "volcanic" or name == "lava" or name == "lava-hot"
end

local function is_lava_tile(name)
  return name == "lava" or name == "lava-hot"
end

script.on_init(function()
  local surface = game.surfaces["nauvis"]
  game.forces.player.chart(surface, AREA)
  surface.request_to_generate_chunks({ 0, 0 }, math.ceil(RADIUS / 32) + 2)
  storage.eon_verify_done = false
end)

script.on_nth_tick(60, function()
  if storage.eon_verify_done then return end
  local surface = game.surfaces["nauvis"]

  -- Wait until every chunk in the area exists.
  for cx = -RADIUS / 32, RADIUS / 32 do
    for cy = -RADIUS / 32, RADIUS / 32 do
      if not surface.is_chunk_generated({ math.floor(cx), math.floor(cy) }) then
        return
      end
    end
  end

  -- Cluster tungsten entities into patches (64px cells merged by adjacency).
  local ores = surface.find_entities_filtered({ area = AREA, name = "tungsten-ore" })
  local cells = {}
  for _, ore in pairs(ores) do
    local p = ore.position
    local key = math.floor(p.x / 64) .. "," .. math.floor(p.y / 64)
    local cell = cells[key]
    if not cell then
      cell = { n = 0, sx = 0, sy = 0, rich = 0 }
      cells[key] = cell
    end
    cell.n = cell.n + 1
    cell.sx = cell.sx + p.x
    cell.sy = cell.sy + p.y
    cell.rich = cell.rich + (ore.amount or 0)
  end
  local patches = {}
  for _, cell in pairs(cells) do
    local cx, cy = cell.sx / cell.n, cell.sy / cell.n
    local tile = surface.get_tile(cx, cy).name
    patches[#patches + 1] = {
      x = math.floor(cx), y = math.floor(cy),
      entities = cell.n, richness = cell.rich,
      center_tile = tile,
      on_volcano_terrain = is_volcano_tile(tile),
    }
  end

  -- Cluster volcano-terrain tiles into volcanoes (32px samples, 300px merge).
  -- Any volcanic tile counts: some volcanoes have folds but little lava.
  local terr_pts = {}
  local lava_n = 0
  local y = -RADIUS
  while y <= RADIUS do
    local x = -RADIUS
    while x <= RADIUS do
      local name = surface.get_tile(x, y).name
      if is_volcano_tile(name) then
        terr_pts[#terr_pts + 1] = { x = x, y = y }
        if is_lava_tile(name) then lava_n = lava_n + 1 end
      end
      x = x + 32
    end
    y = y + 32
  end
  local volcanoes = {}
  for _, pt in pairs(terr_pts) do
    local found = nil
    for _, v in pairs(volcanoes) do
      local dx, dy = pt.x - v.x, pt.y - v.y
      if dx * dx + dy * dy < 300 * 300 then
        found = v
        break
      end
    end
    if found then
      found.n = found.n + 1
      found.x = found.x + (pt.x - found.x) / found.n
      found.y = found.y + (pt.y - found.y) / found.n
    else
      volcanoes[#volcanoes + 1] = { x = pt.x, y = pt.y, n = 1 }
    end
  end

  local function nearest_volcano(x, y)
    local best, best_v = nil, nil
    for _, v in pairs(volcanoes) do
      local dx, dy = x - v.x, y - v.y
      local d = dx * dx + dy * dy
      if not best or d < best then
        best, best_v = d, v
      end
    end
    return best and math.sqrt(best) or -1, best_v
  end

  local on_terrain, far_fallback = 0, 0
  for _, p in pairs(patches) do
    if p.on_volcano_terrain then on_terrain = on_terrain + 1 end
    local d = nearest_volcano(p.x, p.y)
    p.dist_to_volcano = math.floor(d)
    if d > 600 then far_fallback = far_fallback + 1 end
  end
  local guarded = 0
  for _, v in pairs(volcanoes) do
    local best = nil
    for _, p in pairs(patches) do
      local dx, dy = p.x - v.x, p.y - v.y
      local d = math.sqrt(dx * dx + dy * dy)
      if not best or d < best then best = d end
    end
    v.x = math.floor(v.x)
    v.y = math.floor(v.y)
    v.nearest_patch = best and math.floor(best) or -1
    if best and best <= 450 then guarded = guarded + 1 end
  end

  -- Demolishers per volcano (fit check for small/varied sizes).
  local demos = surface.find_entities_filtered({ area = AREA, type = "segmented-unit" })
  local demo_count = 0
  for _, v in pairs(volcanoes) do
    local best, best_name = nil, nil
    for _, d in pairs(demos) do
      local p = d.position
      local dx, dy = p.x - v.x, p.y - v.y
      local dist = math.sqrt(dx * dx + dy * dy)
      if not best or dist < best then
        best, best_name = dist, d.name
      end
    end
    v.nearest_demolisher = best and math.floor(best) or -1
    v.nearest_demolisher_name = best_name
    if best and best <= 600 then demo_count = demo_count + 1 end
    local sizes = {}
    for _, d in pairs(demos) do
      local p = d.position
      local dx, dy = p.x - v.x, p.y - v.y
      if dx * dx + dy * dy < 600 * 600 then sizes[d.name] = true end
    end
    local list = {}
    local n_demo = 0
    for name in pairs(sizes) do list[#list + 1] = name end
    for _, d in pairs(demos) do
      local p = d.position
      local dx, dy = p.x - v.x, p.y - v.y
      if dx * dx + dy * dy < 600 * 600 then n_demo = n_demo + 1 end
    end
    table.sort(list)
    v.demolisher_sizes = list
    v.demolisher_count = n_demo
  end

  -- Closest volcano terrain to spawn (spawn-gate check).
  local min_terr_dist = -1
  for _, pt in pairs(terr_pts) do
    local d = math.sqrt(pt.x * pt.x + pt.y * pt.y)
    if min_terr_dist < 0 or d < min_terr_dist then min_terr_dist = d end
  end

  -- Calcite ore patches (same 64px cells) for stain pairing checks.
  local calcite_patches = {}
  do
    local cells = {}
    for _, ore in pairs(surface.find_entities_filtered({ area = AREA, name = "calcite" })) do
      local p = ore.position
      local key = math.floor(p.x / 64) .. "," .. math.floor(p.y / 64)
      local cell = cells[key]
      if not cell then
        cell = { n = 0, sx = 0, sy = 0 }
        cells[key] = cell
      end
      cell.n = cell.n + 1
      cell.sx = cell.sx + p.x
      cell.sy = cell.sy + p.y
    end
    for _, cell in pairs(cells) do
      calcite_patches[#calcite_patches + 1] = { x = cell.sx / cell.n, y = cell.sy / cell.n, n = cell.n }
    end
  end

  -- Unguarded lava: lava samples far from any demolisher (territory gaps).
  local lava_far, lava_total = 0, 0
  do
    local y = -RADIUS
    while y <= RADIUS do
      local x = -RADIUS
      while x <= RADIUS do
        local name = surface.get_tile(x, y).name
        if is_lava_tile(name) then
          lava_total = lava_total + 1
          local best = nil
          for _, d in pairs(demos) do
            local p = d.position
            local dx, dy = x - p.x, y - p.y
            local dist = dx * dx + dy * dy
            if not best or dist < best then best = dist end
          end
          if not best or best > 300 * 300 then lava_far = lava_far + 1 end
        end
        x = x + 48
      end
      y = y + 48
    end
  end

  local function nearest_calcite(x, y)
    local best = nil
    for _, p in pairs(calcite_patches) do
      local dx, dy = x - p.x, y - p.y
      local d = dx * dx + dy * dy
      if not best or d < best then best = d end
    end
    return best and math.sqrt(best) or -1
  end

  -- Decorative spot checks: feathered volcano decals should hug volcanoes;
  -- calcite stains should hug calcite ore wherever it grows.
  local decor = {}
  for _, name in pairs({ "vulcanus-sand-decal", "vulcanus-crack-decal", "calcite-stain-small", "green-hairy-grass", "small-rock", "brown-asterisk" }) do
    local found = surface.find_decoratives_filtered({ area = AREA, name = name, limit = 60000 })
    local to_volc, to_calc, on_volc = {}, {}, 0
    local tile_kinds = { volcanic = 0, snowice = 0, other = 0 }
    local sampled = 0
    for i, dec in pairs(found) do
      if i % 7 ~= 0 then goto continue end
      if sampled >= 400 then break end
      sampled = sampled + 1
      local p = dec.position
      local dv = nearest_volcano(p.x, p.y)
      to_volc[#to_volc + 1] = math.floor(dv)
      local tile_name = surface.get_tile(p.x, p.y).name
      if is_volcano_tile(tile_name) then
        on_volc = on_volc + 1
        tile_kinds.volcanic = tile_kinds.volcanic + 1
      elseif string.sub(tile_name, 1, 4) == "snow" or string.sub(tile_name, 1, 3) == "ice" or string.sub(tile_name, 1, 5) == "brash" then
        tile_kinds.snowice = tile_kinds.snowice + 1
      else
        tile_kinds.other = tile_kinds.other + 1
      end
      if name == "calcite-stain-small" then
        to_calc[#to_calc + 1] = math.floor(nearest_calcite(p.x, p.y))
      end
      ::continue::
    end
    table.sort(to_volc)
    table.sort(to_calc)
    local function pct(t, q)
      if #t == 0 then return -1 end
      return t[math.min(#t, math.max(1, math.floor(#t * q) + 1))]
    end
    decor[name] = {
      total = #found,
      sampled = #to_volc,
      volcano_p50 = pct(to_volc, 0.5),
      volcano_p90 = pct(to_volc, 0.9),
      volcano_max = #to_volc > 0 and to_volc[#to_volc] or -1,
      on_volcano_terrain = on_volc,
      tiles_volcanic = tile_kinds.volcanic,
      tiles_snowice = tile_kinds.snowice,
      tiles_other = tile_kinds.other,
      calcite_p50 = pct(to_calc, 0.5),
      calcite_p90 = pct(to_calc, 0.9),
    }
  end

  helpers.write_file("eon-tungsten-report.json", helpers.table_to_json({
    seed = game.default_map_gen_settings.seed,
    radius = RADIUS,
    volcano_terrain_samples = #terr_pts,
    lava_samples = lava_n,
    ore_entities = #ores,
    volcanoes = volcanoes,
    volcano_count = #volcanoes,
    volcanoes_with_patch_within_450 = guarded,
    patches = patches,
    patch_count = #patches,
    patches_on_volcano_terrain = on_terrain,
    fallback_patches_beyond_600 = far_fallback,
    calcite_patch_count = #calcite_patches,
    decor = decor,
    demolisher_count = #demos,
    volcanoes_with_demolisher_within_600 = demo_count,
    demolishers_off_volcano_terrain = (function()
      local n = 0
      for _, d in pairs(demos) do
        local p = d.position
        if not is_volcano_tile(surface.get_tile(p.x, p.y).name) then n = n + 1 end
      end
      return n
    end)(),
    demolisher_tiles = (function()
      local t = {}
      for _, d in pairs(demos) do
        local p = d.position
        t[#t + 1] = { x = math.floor(p.x), y = math.floor(p.y),
                      tile = surface.get_tile(p.x, p.y).name, name = d.name }
      end
      return t
    end)(),
    lava_samples = lava_total,
    unguarded_lava_samples = lava_far,
    min_volcano_terrain_dist_to_spawn = math.floor(min_terr_dist),
  }))
  storage.eon_verify_done = true
end)
