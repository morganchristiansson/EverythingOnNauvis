-- Dev-only e2e test: decorative fading must keep flora in its home biome and
-- out of every other. Uses surface.find_decoratives_filtered (find_entities_
-- filtered does NOT return optimized-decoratives). Regions: nauvis plains,
-- a nauvis volcano, deep gleba (southern strip = safely past the wobbly
-- line), a gleba volcano, aquilo north, and the gleba line. The driver
-- (tests/probe_decoratives.py) asserts on the counts.
local DISCS = {
  { name = "nauvis_plains", x = 0, y = -500 },
  { name = "nauvis_volcano", x = -80, y = -831 },
  { name = "deep_gleba", x = 0, y = 1500 },
  { name = "gleba_volcano", x = -560, y = 1994 },
  { name = "aquilo_north", x = 0, y = -1500 },
  { name = "gleba_line", x = 0, y = 1050 },
}
local R = 24

-- Gleba natives that must never appear outside gleba territory.
local GLEBA_FLORA = {
  "honeycomb-fungus", "honeycomb-fungus-1x1", "honeycomb-fungus-decayed",
  "coral-water", "yellow-lettuce-lichen-cups-1x1", "white-carpet-grass", "mycelium",
}
-- Nauvis grass tufts that must never appear in deep gleba or on volcano
-- ground. Green carpet/hairy grass are shared prototypes that vanilla GLEBA
-- also grows (the mod restores that), so only the others are hard leaks.
local GRASS = {
  "green-hairy-grass", "green-carpet-grass",
}
local NAUVIS_ONLY_GRASS = {
  "green-small-grass", "brown-carpet-grass", "brown-hairy-grass",
}

surface = nil

local function is_gleba_tile(name)
  return string.find(name, "gleba") ~= nil or string.find(name, "lowland") ~= nil
      or string.find(name, "wetland") ~= nil or string.find(name, "midland") ~= nil
      or string.find(name, "highland") ~= nil or string.find(name, "natural-") ~= nil
      or name == "pit-rock"
end

local function is_volcano_tile(name)
  return string.sub(name, 1, 8) == "volcanic" or name == "lava" or name == "lava-hot"
end

local function is_aquilo_tile(name)
  return string.find(name, "snow") ~= nil or string.find(name, "ice") ~= nil
      or string.find(name, "ammonia") ~= nil or string.find(name, "brash") ~= nil
end

local function runtime_expr(name)
  local ok, p = pcall(function() return prototypes["optimized-decorative"][name] end)
  if not ok or not p then return "no-prototype-access" end
  local ok2, ap = pcall(function() return p.autoplace end)
  if not ok2 or not ap then return "no-autoplace" end
  return ap.probability_expression or "no-probability"
end

script.on_init(function()
  helpers.write_file("eon-decor-started.txt", "on_init fired at tick " .. game.tick)
  surface = game.surfaces["nauvis"]
  report_runtime = { grass = runtime_expr("green-hairy-grass"), flora = runtime_expr("honeycomb-fungus") }
  helpers.write_file("eon-runtime-expr.json", helpers.table_to_json(report_runtime))
  local report = {}
  for _, d in ipairs(DISCS) do
    surface.request_to_generate_chunks({ d.x, d.y }, R)
    surface.force_generate_chunk_requests()
    local area = { left_top = { d.x - 700, d.y - 700 }, right_bottom = { d.x + 700, d.y + 700 } }
    local decos = surface.find_decoratives_filtered({ area = area })
    local h, flora = {}, {}
    for _, dec in ipairs(decos) do
      local n = dec.decorative.name
      h[n] = (h[n] or 0) + 1
      local pos = dec.position
      local tile = surface.get_tile(math.floor(pos.x), math.floor(pos.y)).name
      if is_gleba_tile(tile) then
        for _, g in ipairs(GRASS) do
          if n == g then flora["grass_on_gleba_named_tiles"] = (flora["grass_on_gleba_named_tiles"] or 0) + 1 end
        end
      end
      for _, f in ipairs(GLEBA_FLORA) do
        if n == f then flora[f] = (flora[f] or 0) + 1 end
      end
    end
    local out = {}
    for n, c in pairs(h) do out[#out + 1] = { n = n, c = c } end
    table.sort(out, function(a, b) return a.c > b.c end)
    local top = {}
    for i = 1, math.min(40, #out) do top[#top + 1] = out[i] end
    report[d.name] = { total = #decos, top = top }
    report[d.name .. "_gleba_flora"] = flora
    if d.name == "nauvis_plains" then
      local grass_any = 0
      for _, dec in ipairs(decos) do
        local n = dec.decorative.name
        for _, g in ipairs(GRASS) do
          if n == g then grass_any = grass_any + 1 end
        end
      end
      report.nauvis_plains_grass_any = grass_any
    end
    -- Deep-gleba strip: grass anywhere in y >= 1650 (safely past the wobbly
    -- transition line; the highland-finger mix is north of ~1100 and legit).
    if d.name == "deep_gleba" then
      local deep_grass, deep_grass_on_gleba = 0, 0
      for _, dec in ipairs(decos) do
        local pos = dec.position
        if pos.y >= 1650 then
          local n = dec.decorative.name
          for _, g in ipairs(NAUVIS_ONLY_GRASS) do
            if n == g then
              local tile = surface.get_tile(math.floor(pos.x), math.floor(pos.y)).name
              if not is_volcano_tile(tile) then
                deep_grass = deep_grass + 1
                -- grass on a nauvis-pocket tile south of the line is legit
                -- (the transition wobbles); only gleba-named tiles are leaks.
                if is_gleba_tile(tile) then deep_grass_on_gleba = deep_grass_on_gleba + 1 end
              end
            end
          end
        end
      end
      report.deep_gleba_deep_grass = deep_grass
      report.deep_gleba_deep_grass_on_gleba_tiles = deep_grass_on_gleba
      local db = {}
      for _, dec in ipairs(decos) do
        local pos = dec.position
        if pos.y >= 1650 then
          local n = dec.decorative.name
          for _, g in ipairs(NAUVIS_ONLY_GRASS) do
            if n == g then
              local tile = surface.get_tile(math.floor(pos.x), math.floor(pos.y)).name
              if is_gleba_tile(tile) then
                db[#db + 1] = { n = n, x = math.floor(pos.x), y = math.floor(pos.y), t = tile }
              end
            end
          end
        end
      end
      report.deep_strip_breakdown = db
      if d.name == "deep_gleba" and #db > 0 then
        local s = db[1]
        local around = {}
        for dx = -3, 3 do
          local row = {}
          for dy = -3, 3 do
            row[#row + 1] = surface.get_tile(s.x + dx, s.y + dy).name
          end
          around[#around + 1] = table.concat(row, "|")
        end
        report.wetland_tile_check = { name = s.t, x = s.x, y = s.y, around = around }
      end
    end
  end
  helpers.write_file("eon-decor-report.json", helpers.table_to_json(report))
end)