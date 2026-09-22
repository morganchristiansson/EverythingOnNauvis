-- Dev-only probe: what fruit actually renders at the translated Gleba
-- starting area (anchor y = eon_gleba_start_y ~= 1340, patches at +/-186 x).
-- Counts soil tiles, tree entities (fruit), and the surrounding tile mix.
-- Driver: run manually headless (follow tests/eon-probe-decoratives flow).
local GEO = {
  { name = "start", x = 0, y = 1340 },
  { name = "south_rim", x = 0, y = 1900 },
}
local R = 30  -- chunks radius

local SOIL = {
  yumako = "natural-yumako-soil", jelly = "natural-jellynut-soil",
  wyumako = "wetland-yumako", jellystemwater = "wetland-jellynut",
}

local function is_gleba_tile(name)
  return string.find(name, "gleba") ~= nil or string.find(name, "lowland") ~= nil
      or string.find(name, "wetland") ~= nil or string.find(name, "midland") ~= nil
      or string.find(name, "highland") ~= nil or string.find(name, "natural-") ~= nil
      or name == "pit-rock"
end

script.on_init(function()
  helpers.write_file("eon-fruit-started.txt", "on_init fired at tick " .. game.tick)
  local surface = game.surfaces["nauvis"]
  local report = {}
  for _, geo in ipairs(GEO) do
    surface.request_to_generate_chunks({ geo.x, geo.y }, R)
  end
  surface.force_generate_chunk_requests()

  -- Coarse scan: sample every 16 tiles for soil tiles around the start.
  local step = 16
  local counts = {}
  local lo = {}
  local cells = {}
  local total_tiles = 0
  local x0, x1, y0, y1 = -1056, 1056, 1040, 2200
  local y = y1
  while y >= y0 do
    local x = x0
    while x <= x1 do
      if surface.is_chunk_generated{ math.floor(x / 32), math.floor(y / 32) } then
        local t = surface.get_tile(x, y).name
        if is_gleba_tile(t) then total_tiles = total_tiles + 1 end
        if t == SOIL.yumako then
          counts.yumako = (counts.yumako or 0) + 1
          if not lo.yumako or y < lo.yumako then lo.yumako = y end
          cells[#cells + 1] = { n = "yumako", x = x, y = y }
        elseif t == SOIL.jelly then
          counts.jelly = (counts.jelly or 0) + 1
          if not lo.jelly or y < lo.jelly then lo.jelly = y end
          cells[#cells + 1] = { n = "jelly", x = x, y = y }
        end
      end
      x = x + step
    end
    y = y - step
  end
  report.grid_sample_count = total_tiles
  report.soil_counts = counts
  report.soil_northernmost = lo
  report.soil_sorted = cells
  -- Entity counts (trees, plus the whole box for context)
  local ents = surface.find_entities_filtered({ area = { left_top = { -1056, 1040 }, right_bottom = { 1056, 2200 } } })
  local et = {}
  for _, e in ipairs(ents) do
    if et[e.name] then et[e.name] = et[e.name] + 1 else et[e.name] = 1 end
  end
  report.entities = et
  local trees = {}
  for _, e in ipairs(ents) do
    if e.name == "yumako-tree" or e.name == "jellystem" then
      trees[#trees + 1] = { n = e.name, x = math.floor(e.position.x), y = math.floor(e.position.y),
                                  t = surface.get_tile(math.floor(e.position.x), math.floor(e.position.y)).name }
    end
  end
  report.trees = trees
  helpers.write_file("eon-fruit-report.json", helpers.table_to_json(report))
end)