-- Dev-only verifier for calcite ore: charts a square around spawn, generates
-- all chunks synchronously in on_init (the reliable headless flow), counts
-- calcite entities, clusters them into patches, clusters volcano-terrain tiles
-- into volcanoes, and reports per-patch distance-to-volcano + tile category.
-- Writes tests/eon-probe-calcite report via helpers.write_file.
local RADIUS = 1600
local AREA = { { -RADIUS, -RADIUS }, { RADIUS, RADIUS } }

local function is_volcano_tile(name)
  return string.sub(name, 1, 8) == "volcanic" or name == "lava" or name == "lava-hot"
end

local function is_lava_tile(name)
  return name == "lava" or name == "lava-hot"
end

-- Core = the demolisher-territory signals (folds + lava ring, the unshifted
-- per-tile form); skirt/outer = folds-flat and the rest of the volcano tiles.
-- Sulfur acid stuff (geysers AND their puddles/stains) must sit on core tiles
-- only.
local function is_core_tile(name)
  return name == "volcanic-folds" or name == "volcanic-folds-warm"
      or is_lava_tile(name)
end

script.on_init(function()
  helpers.write_file("eon-calcite-started.txt", "on_init fired at tick " .. game.tick)
  local surface = game.surfaces["nauvis"]
  game.forces.player.chart(surface, AREA)
  surface.request_to_generate_chunks({ 0, 0 }, math.ceil(RADIUS / 32) + 2)
  surface.force_generate_chunk_requests()

  -- Calcite entities -> 64px-cell patches + a strict per-entity tile audit.
  local ores = surface.find_entities_filtered({ area = AREA, name = "calcite" })
  local off_terrain_entities, off_terrain_tiles, off_terrain_positions = 0, {}, {}
  local cells = {}
  for _, ore in pairs(ores) do
    local p = ore.position
    local tile = surface.get_tile(math.floor(p.x), math.floor(p.y)).name
    if not is_volcano_tile(tile) then
      off_terrain_entities = off_terrain_entities + 1
      if not off_terrain_tiles[tile] then off_terrain_tiles[tile] = 0 end
      off_terrain_tiles[tile] = off_terrain_tiles[tile] + 1
      off_terrain_positions[#off_terrain_positions + 1] = { x = math.floor(p.x), y = math.floor(p.y), t = tile }
    end
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
      entities = cell.n, richness = math.floor(cell.rich),
      center_tile = tile,
      on_volcano_terrain = is_volcano_tile(tile),
    }
  end

  -- Volcano-terrain tiles -> volcanoes (32px samples, 300px merge).
  local terr_pts, lava_n = {}, 0
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
      found.lava = found.lava + (is_lava_tile(surface.get_tile(pt.x, pt.y).name) and 1 or 0)
    else
      volcanoes[#volcanoes + 1] = { x = pt.x, y = pt.y, n = 1, lava = is_lava_tile(surface.get_tile(pt.x, pt.y).name) and 1 or 0 }
    end
  end

  local function nearest_volcano(x, y)
    local best = nil
    for _, v in pairs(volcanoes) do
      local dx, dy = x - v.x, y - v.y
      local d = dx * dx + dy * dy
      if not best or d < best then best = d end
    end
    return best and math.sqrt(best) or -1
  end

  local function nearest_patch(x, y)
    local best = nil
    for _, p in pairs(patches) do
      local dx, dy = x - p.x, y - p.y
      local d = dx * dx + dy * dy
      if not best or d < best then best = d end
    end
    return best and math.sqrt(best) or -1
  end

  -- Per-patch and per-volcano distance metrics.
  local dists, on_volc, off_volc = {}, 0, 0
  for _, p in pairs(patches) do
    local d = nearest_volcano(p.x, p.y)
    p.dist_to_volcano = math.floor(d)
    dists[#dists + 1] = d
    if p.on_volcano_terrain then on_volc = on_volc + 1 else off_volc = off_volc + 1 end
  end
  table.sort(dists)
  local function pct(q)
    if #dists == 0 then return -1 end
    return math.floor(dists[math.min(#dists, math.max(1, math.floor(#dists * q) + 1))])
  end
  for _, v in pairs(volcanoes) do
    local best = nearest_patch(v.x, v.y)
    v.nearest_patch = best >= 0 and math.floor(best) or -1
    v.x = math.floor(v.x)
    v.y = math.floor(v.y)
  end

  -- Per-volcano patch census: patches within 450px of the volcano center, their
  -- on/off-terrain split and total richness; plus stain and geyser censuses in
  -- the same radius (on vs off volcano ground).
  do
    local stains = surface.find_decoratives_filtered({ area = AREA, name = "calcite-stain-small" })
    local geysers = surface.find_entities_filtered({ area = AREA, name = "sulfuric-acid-geyser" })
    local pdls = surface.find_decoratives_filtered({ area = AREA, name = "sulfuric-acid-puddle" })
    for _, v in pairs(volcanoes) do
      local n_on, n_off, rich_on, rich_off = 0, 0, 0, 0
      for _, p in pairs(patches) do
        local dx, dy = p.x - v.x, p.y - v.y
        if dx * dx + dy * dy < 450 * 450 then
          if p.on_volcano_terrain then
            n_on = n_on + 1; rich_on = rich_on + p.richness
          else
            n_off = n_off + 1; rich_off = rich_off + p.richness
          end
        end
      end
      v.patches_within_450 = n_on + n_off
      v.patches_on_volcano_450 = n_on
      v.patches_off_volcano_450 = n_off
      v.richness_volcano_450 = rich_on + rich_off
      local stain_near, stain_on = 0, 0
      for _, s in pairs(stains) do
        local p = s.position
        local dx, dy = p.x - v.x, p.y - v.y
        if dx * dx + dy * dy < 450 * 450 then
          stain_near = stain_near + 1
          if is_volcano_tile(surface.get_tile(math.floor(p.x), math.floor(p.y)).name) then
            stain_on = stain_on + 1
          end
        end
      end
      v.stains_near_450 = stain_near
      v.stains_on_volcano_450 = stain_on
      local geyser_near, geyser_amt = 0, 0
      for _, g in pairs(geysers) do
        local p = g.position
        local dx, dy = p.x - v.x, p.y - v.y
        if dx * dx + dy * dy < 450 * 450 then
          geyser_near = geyser_near + 1
          geyser_amt = geyser_amt + (g.amount or 0)
        end
      end
      v.geysers_near_450 = geyser_near
      v.geyser_amount_450 = geyser_amt
      local puddle_near = 0
      for _, s in pairs(pdls) do
        local p = s.position
        local dx, dy = p.x - v.x, p.y - v.y
        if dx * dx + dy * dy < 450 * 450 then
          puddle_near = puddle_near + 1
        end
      end
      v.puddles_near_450 = puddle_near
    end
  end

  -- Closest volcano terrain to spawn (spawn-gate check).
  local min_terr_dist = -1
  for _, pt in pairs(terr_pts) do
    local d = math.sqrt(pt.x * pt.x + pt.y * pt.y)
    if min_terr_dist < 0 or d < min_terr_dist then min_terr_dist = d end
  end
  -- Closest calcite ore to spawn.
  local min_calcite_dist = -1
  for _, ore in pairs(ores) do
    local p = ore.position
    local d = math.sqrt(p.x * p.x + p.y * p.y)
    if min_calcite_dist < 0 or d < min_calcite_dist then min_calcite_dist = d end
  end

  -- Calcite stains should still hug the volcano-anchored ore (they follow the
  -- same region; the small stain is the live one, the large is vestigial in
  -- vanilla too). Sample the small stain and record distance to nearest patch.
  local stain_dists = {}
  do
    local found = surface.find_decoratives_filtered({ area = AREA, name = "calcite-stain-small", limit = 40000 })
    for i, dec in pairs(found) do
      if i % 5 == 0 then
        local p = dec.position
        local best = nil
        for _, q in pairs(patches) do
          local dx, dy = p.x - q.x, p.y - q.y
          local d = dx * dx + dy * dy
          if not best or d < best then best = d end
        end
        stain_dists[#stain_dists + 1] = best and math.floor(math.sqrt(best)) or -1
      end
    end
    table.sort(stain_dists)
  end

  -- Sulfuric acid puddles/geysers must be 100% on volcano terrain (tight mask,
  -- no feather band) AND on inner-core tiles (demolisher territory signals),
  -- and follow the per-volcano geyser gate. Count off-core samples.
  local acid = {}
  do
    for _, kind in pairs({ "sulfuric-acid-puddle", "sulfuric-acid-puddle-small", "sulfur-stain", "sulfur-stain-small" }) do
      local on, off, core, noncore, total = 0, 0, 0, 0, 0
      local tiles = {}
      local found = surface.find_decoratives_filtered({ area = AREA, name = kind, limit = 200000 })
      for _, dec in pairs(found) do
        total = total + 1
        local p = dec.position
        local t = surface.get_tile(math.floor(p.x), math.floor(p.y)).name
        if is_volcano_tile(t) then on = on + 1 else off = off + 1 end
        if is_core_tile(t) then core = core + 1 else noncore = noncore + 1 end
        tiles[t] = (tiles[t] or 0) + 1
      end
      acid[kind] = { total = total, on_volcano = on, off_volcano = off, core = core, noncore = noncore, tiles = tiles }
    end
    local on, off, total, amount, core, noncore = 0, 0, 0, 0, 0, 0
    for _, g in pairs(surface.find_entities_filtered({ area = AREA, name = "sulfuric-acid-geyser" })) do
      total = total + 1
      amount = amount + (g.amount or 0)
      local p = g.position
      local t = surface.get_tile(math.floor(p.x), math.floor(p.y)).name
      if is_volcano_tile(t) then on = on + 1 else off = off + 1 end
      if is_core_tile(t) then core = core + 1 else noncore = noncore + 1 end
    end
    acid["sulfuric-acid-geyser"] = { total = total, on_volcano = on, off_volcano = off, core = core, noncore = noncore, total_amount = amount }
    -- Crude-oil wells as the reference scale (geyser baseline should sit near it).
    local oil_n, oil_amt = 0, 0
    for _, g in pairs(surface.find_entities_filtered({ area = AREA, name = "crude-oil" })) do
      oil_n = oil_n + 1
      oil_amt = oil_amt + (g.amount or 0)
    end
    acid["crude-oil"] = { total = oil_n, total_amount = oil_amt }
  end

  -- Calcite <-> geyser overlap: with different skip-offset sub-grids their
  -- spot candidates should rarely coincide; measure nearest-geyser distance
  -- per calcite patch (64px cells).
  local geyser_positions = {}
  do
    for _, g in pairs(surface.find_entities_filtered({ area = AREA, name = "sulfuric-acid-geyser" })) do
      local p = g.position
      geyser_positions[#geyser_positions + 1] = { x = p.x, y = p.y }
    end
  end
  local calcite_geyser_dists = {}
  local calcite_close_to_geyser = 0
  for _, p in pairs(patches) do
    local best = nil
    for _, g in pairs(geyser_positions) do
      local dx, dy = p.x - g.x, p.y - g.y
      local d = dx * dx + dy * dy
      if not best or d < best then best = d end
    end
    if best then
      local b = math.sqrt(best)
      calcite_geyser_dists[#calcite_geyser_dists + 1] = math.floor(b)
      if b < 30 then calcite_close_to_geyser = calcite_close_to_geyser + 1 end
    end
  end
  table.sort(calcite_geyser_dists)
  local function pct2(t, q)
    if #t == 0 then return -1 end
    return t[math.min(#t, math.max(1, math.floor(#t * q) + 1))]
  end

  -- Scrap / iron placement sanity: nauvis-only ores must stay OFF volcano
  -- ground (scrap only exists in the holmium-off config) and their spots use
  -- the patch-set grid so they don't stack on each other.
  do
    for _, name in pairs({ "scrap", "iron-ore" }) do
      local on, off, total = 0, 0, 0
      for _, e in pairs(surface.find_entities_filtered({ area = AREA, name = name })) do
        total = total + 1
        local p = e.position
        if is_volcano_tile(surface.get_tile(math.floor(p.x), math.floor(p.y)).name) then
          on = on + 1
        else
          off = off + 1
        end
      end
      acid[name] = { total = total, on_volcano = on, off_volcano = off }
    end
    -- All resource names in area (debug: what actually renders).
    local res_tally = {}
    for _, e in pairs(surface.find_entities_filtered({ area = AREA, type = "resource" })) do
      res_tally[e.name] = (res_tally[e.name] or 0) + 1
    end
    acid["all_resources"] = res_tally
    -- scrap <-> iron proximity (patch-set de-overlap check).
    local scrapv, ironv = {}, {}
    for _, e in pairs(surface.find_entities_filtered({ area = AREA, name = "scrap" })) do
      local p = e.position
      scrapv[#scrapv + 1] = { x = p.x, y = p.y }
    end
    for _, e in pairs(surface.find_entities_filtered({ area = AREA, name = "iron-ore" })) do
      local p = e.position
      ironv[#ironv + 1] = { x = p.x, y = p.y }
    end
    local scrap_iron_close = 0
    for _, s in pairs(scrapv) do
      for _, i in pairs(ironv) do
        local dx, dy = s.x - i.x, s.y - i.y
        if dx * dx + dy * dy < 25 * 25 then
          scrap_iron_close = scrap_iron_close + 1
          break
        end
      end
    end
    acid["scrap_iron_close_25px"] = { total = scrap_iron_close }
  end
  -- Volcano cliff census: ring spacing per volcano (the rings are the
  -- eon_volcano_cliff_spike contours in eon_cliff_elevation) and the GAP
  -- between the top-most ring and the lava edge (crest-ring measurement).
  do
    local cliffs = surface.find_entities_filtered({ area = AREA, type = "cliff" })
    -- Sample lava tiles on a 8px grid for nearest-lava distances.
    local lava_pts = {}
    local y = -RADIUS
    while y <= RADIUS do
      local x = -RADIUS
      while x <= RADIUS do
        if is_lava_tile(surface.get_tile(x, y).name) then
          lava_pts[#lava_pts + 1] = { x = x, y = y }
        end
        x = x + 8
      end
      y = y + 8
    end
    local function nearest_lava(x, y)
      local best = nil
      for _, p in pairs(lava_pts) do
        local dx, dy = x - p.x, y - p.y
        local d = dx * dx + dy * dy
        if not best or d < best then best = d end
      end
      return best and math.sqrt(best) or -1
    end
    for _, v in pairs(volcanoes) do
      local min_gap, n = nil, 0
      local max_r = 0
      for _, c in pairs(cliffs) do
        local p = c.position
        local dx, dy = p.x - v.x, p.y - v.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < 500 then
          n = n + 1
          if d > max_r then max_r = d end
          local g = nearest_lava(p.x, p.y)
          if not min_gap or g < min_gap then min_gap = g end
        end
      end
      v.cliff_total = n
      v.cliff_max_r = math.floor(max_r)
      v.cliff_min_gap_to_lava = min_gap and math.floor(min_gap) or -1
    end
  end
  -- Demolisher census per volcano (mama+ring vs split vs single + babies).
  local demos = surface.find_entities_filtered({ area = AREA, type = "segmented-unit" })
  local demo_tally = {}
  for _, d in pairs(demos) do
    demo_tally[d.name] = (demo_tally[d.name] or 0) + 1
  end
  acid["demolishers"] = demo_tally
  for _, v in pairs(volcanoes) do
    local near = {}
    for _, d in pairs(demos) do
      local p = d.position
      local dx, dy = p.x - v.x, p.y - v.y
      if dx * dx + dy * dy < 600 * 600 then
        near[d.name] = (near[d.name] or 0) + 1
      end
    end
    v.demolishers_600 = near
    local minp = nil
    for _, d in pairs(demos) do
      local p = d.position
      local dx, dy = p.x - v.x, p.y - v.y
      local dist = dx * dx + dy * dy
      if not minp or dist < minp then minp = dist end
    end
    v.nearest_demolisher = minp and math.floor(math.sqrt(minp)) or -1
  end
  -- Territory introspection: map every generated chunk to its territory, record
  -- territory sizes (chunk counts) and per-volcano territory census, plus the
  -- specific problem coordinates the user reported.
  do
    local terr_by_chunk = {}
    local terr_sizes = {}
    local terr_units = {}
    for cx = -math.ceil(RADIUS / 32), math.ceil(RADIUS / 32) do
      for cy = -math.ceil(RADIUS / 32), math.ceil(RADIUS / 32) do
        local t = surface.get_territory_for_chunk({ cx, cy })
        if t and t.valid then
          -- tostring(t) is the class name for every territory; key by the
          -- territory's first chunk instead (a chunk belongs to one territory).
          local chunks = t.get_chunks()
          local c0 = chunks[1]
          local key = c0.x .. "," .. c0.y
          terr_by_chunk[cx .. "," .. cy] = key
          if not terr_sizes[key] then
            terr_sizes[key] = #chunks
            local units = t.get_segmented_units()
            local unic = 0
            for _ in pairs(units) do unic = unic + 1 end
            terr_units[key] = unic
          end
        end
      end
    end
    acid["territory_total"] = (function()
      local n = 0
      for _ in pairs(terr_sizes) do n = n + 1 end
      return n
    end)()
    acid["terr_size_hist"] = (function()
      local h = {}
      for _, s in pairs(terr_sizes) do
        local b = s < 4 and "lt4" or (s < 8 and "4-7" or (s < 15 and "8-14" or (s < 25 and "15-24" or "25+")))
        h[b] = (h[b] or 0) + 1
      end
      return h
    end)()
    for _, v in pairs(volcanoes) do
      local seen = {}
      local list = {}
      for dx = -16, 16 do
        for dy = -16, 16 do
          local key = terr_by_chunk[(math.floor(v.x / 32) + dx) .. "," .. (math.floor(v.y / 32) + dy)]
          if key and not seen[key] then
            seen[key] = true
            list[#list + 1] = { size = terr_sizes[key], units = terr_units[key] }
          end
        end
      end
      table.sort(list, function(a, b) return a.size > b.size end)
      v.territories = list
    end
    -- Exact dumps at user-reported coords.
    local points = {
      { name = "m_too_many", x = -608, y = 29 },
      { name = "m_L", x = -366, y = 922 },
      { name = "m_3chunk", x = -169, y = 826 },
      { name = "m_2x3chunk", x = 594, y = -528 },
      { name = "m_cramped2", x = 1313, y = -768 },
      { name = "m_merge2", x = -273, y = 837 },
      { name = "m_sliver", x = -690, y = 19 },
      { name = "m_mother2", x = 617, y = -503 },
      { name = "m_corner2", x = 672, y = -504 },
      { name = "m_fine_a", x = -610, y = 29 },
      { name = "m_fine_b", x = 442, y = 135 },
      { name = "m_big_no_mama", x = -137, y = 730 },
      { name = "m_3chunk2", x = -688, y = 58 },
    }
    local pd = {}
    for _, p in pairs(points) do
      local t = surface.get_territory_for_chunk({ math.floor(p.x / 32), math.floor(p.y / 32) })
      if t and t.valid then
        local chunks = t.get_chunks()
        local minx, maxx, miny, maxy = 9e9, -9e9, 9e9, -9e9
        local pts = {}
        for _, c in pairs(chunks) do
          minx = math.min(minx, c.x); maxx = math.max(maxx, c.x)
          miny = math.min(miny, c.y); maxy = math.max(maxy, c.y)
          pts[#pts + 1] = { x = c.x, y = c.y }
        end
        local grid = {}
        for _, c in pairs(pts) do
          local row = c.y - miny
          local col = c.x - minx
          grid[row] = grid[row] or {}
          grid[row][col] = 1
        end
        local rows = {}
        for r = 0, maxy - miny do
          local s = ""
          for cc = 0, maxx - minx do
            s = s .. ((grid[r] and grid[r][cc]) and "#" or ".")
          end
          rows[#rows + 1] = s
        end
        local units = t.get_segmented_units()
        local unic = 0
        for _ in pairs(units) do unic = unic + 1 end
        pd[p.name] = { size = #chunks, bbox = (maxx - minx + 1) .. "x" .. (maxy - miny + 1), units = unic, shape = rows }
      else
        pd[p.name] = { size = 0, shape = { "(no territory)" } }
      end
    end
    acid["territory_points"] = pd
  end
  helpers.write_file("eon-calcite-report.json", helpers.table_to_json({
    seed = game.default_map_gen_settings.seed,
    radius = RADIUS,
    ore_entities = #ores,
    off_terrain_entities = off_terrain_entities,
    off_terrain_tiles = off_terrain_tiles,
    off_terrain_positions = off_terrain_positions,
    acid = acid,
    calcite_geyser_dist_p50 = pct2(calcite_geyser_dists, 0.5),
    calcite_geyser_dist_p90 = pct2(calcite_geyser_dists, 0.9),
    calcite_close_to_geyser_30px = calcite_close_to_geyser,
    patch_count = #patches,
    patches_on_volcano_terrain = on_volc,
    patches_off_volcano_terrain = off_volc,
    dist_p25 = pct(0.25), dist_p50 = pct(0.5), dist_p75 = pct(0.75), dist_p90 = pct(0.9),
    volcano_count = #volcanoes,
    volcano_terrain_samples = #terr_pts,
    lava_samples = lava_n,
    patches_near_volcano_250 = (function()
      local n = 0
      for _, d in pairs(dists) do if d <= 250 then n = n + 1 end end
      return n
    end)(),
    patches_near_volcano_600 = (function()
      local n = 0
      for _, d in pairs(dists) do if d <= 600 then n = n + 1 end end
      return n
    end)(),
    volcanoes_with_patch_within_450 = (function()
      local n = 0
      for _, v in pairs(volcanoes) do
        if v.nearest_patch >= 0 and v.nearest_patch <= 450 then n = n + 1 end
      end
      return n
    end)(),
    volcanoes_with_patch_within_250 = (function()
      local n = 0
      for _, v in pairs(volcanoes) do
        if v.nearest_patch >= 0 and v.nearest_patch <= 250 then n = n + 1 end
      end
      return n
    end)(),
    min_volcano_terrain_dist_to_spawn = math.floor(min_terr_dist),
    min_calcite_dist_to_spawn = math.floor(min_calcite_dist),
    total_richness = (function()
      local s = 0
      for _, p in pairs(patches) do s = s + p.richness end
      return s
    end)(),
    stain_total = #stain_dists,
    stain_dist_p50 = #stain_dists > 0 and stain_dists[math.max(1, math.floor(#stain_dists * 0.5 + 1))] or -1,
    stain_dist_p90 = #stain_dists > 0 and stain_dists[math.max(1, math.floor(#stain_dists * 0.9 + 1))] or -1,
    stain_dist_max = #stain_dists > 0 and stain_dists[#stain_dists] or -1,
    rich_on_volcano = (function()
      local s = 0
      for _, p in pairs(patches) do if p.on_volcano_terrain then s = s + p.richness end end
      return s
    end)(),
    volcanoes = volcanoes,
    patches = patches,
  }))
end)