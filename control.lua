-- EverythingOnNauvis-morganc runtime: re-skin cliffs.
--
-- The engine generates exactly one cliff type per surface from elevation contours, so
-- volcano rings generate as "cliff" first (see eon_cliff_elevation in
-- map-generation/terrain.lua) and are converted here to "cliff-vulcanus", keeping
-- position and orientation. Same for Gleba territory, converted to "cliff-gleba".
-- Nauvis cliffs elsewhere are untouched.

local function is_volcanic_tile(tile_name)
  return string.sub(tile_name, 1, 8) == "volcanic"
end

local gleba_tile_prefixes = { "wetland-", "lowland-", "midland-", "highland-", "pit-rock", "gleba-dee", "natural-" }

local function is_gleba_tile(tile_name)
  for _, prefix in pairs(gleba_tile_prefixes) do
    if string.sub(tile_name, 1, string.len(prefix)) == prefix then
      return true
    end
  end
  return false
end

script.on_event(defines.events.on_chunk_generated, function(event)
  local surface = event.surface
  if surface.name ~= "nauvis" then return end
  local cliffs = surface.find_entities_filtered{area = event.area, name = "cliff"}
  if #cliffs == 0 then return end
  for _, cliff in pairs(cliffs) do
    if cliff.valid then
      local position = cliff.position
      local tile_name = surface.get_tile(position.x, position.y).name
      local replacement = nil
      if is_volcanic_tile(tile_name) then
        replacement = "cliff-vulcanus"
      elseif is_gleba_tile(tile_name) then
        replacement = "cliff-gleba"
      end
      if replacement then
        local orientation = cliff.cliff_orientation
        cliff.destroy()
        surface.create_entity{name = replacement, position = position, cliff_orientation = orientation}
      end
    end
  end
end)
