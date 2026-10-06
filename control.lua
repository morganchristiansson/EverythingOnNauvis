-- EverythingOnNauvis-morganc runtime: re-skin cliffs, and build the volcano
-- (demolisher) territories from the spot mirror.
--
-- Cliffs: the engine generates exactly one cliff type per surface from elevation
-- contours, so volcano rings generate as "cliff" first (see eon_cliff_elevation in
-- map-generation/terrain.lua) and are converted here to "cliff-vulcanus", keeping
-- position and orientation. Same for Gleba territory, converted to "cliff-gleba".
-- Nauvis cliffs elsewhere are untouched.
--
-- Volcano territories: the spot mirror owns them outright --
-- expression index is switched off (see map-generation/enemies.lua) and the
-- territories are built here from noise-mirror/: for every generated chunk the
-- mirror says which volcano cone owns it and how wide that cone is, and each cone
-- is turned into one surface.create_territory call per SLICE of its claim carrying
-- that slice's complete chunk list -- one call, or two when the volcano is big enough
-- to carry two guards (volcano-split.lua cuts the claim through its centre). The mirror itself never touches Factorio, so it is testable and
-- benchmarkable on its own (tests/noise-mirror/selftest.lua, tests/noise-mirror/bench.lua).
local VolcanoTerritory = require("volcano-territory")

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

local function re_skin_cliffs(surface, area)
  local cliffs = surface.find_entities_filtered{area = area, name = "cliff"}
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
end

-- ---------------------------------------------------------------------------
-- Runtime volcano territories
-- ---------------------------------------------------------------------------
-- The builder itself is NOT in global: it holds the mirror (with a closure gate
-- and a region cache) and Factorio cannot serialise any of that. Only the
-- "already created" set is persisted, so a cone that already has its territory
-- never gets a second one; the cache is derived data and is simply rebuilt.
--
-- The persisted set lives PER SURFACE, keyed by surface.name -- the only identity
-- that survives a save/load (indices are session-local and reused after a delete).
-- The markers describe a MAP, not the mod: the scenario's reset throws the map
-- away by creating a NEW surface and re-associating the nauvis planet with it, so
-- each surface carries its own markers and a new surface starts empty without a
-- global wipe. storage[STATE_KEY] is therefore
-- { [surface.name] = { [cone.id] = marker } }, one marker table per surface.
local builders = {}
local STATE_KEY = "eon_volcano_territory_runtime"

-- Which surface is ours is decided by ITS OWN MAP GEN SETTINGS, not by the
-- planet. The reset scenario pre-generates the next map on a SECOND surface while
-- the planet still points at the old one (a planet can only be associated with one
-- surface at a time), so a surface must be claimable BEFORE it is ever associated
-- -- and a pre-generated chunk never re-fires on_chunk_generated, so a surface that
-- waits for association arrives with nothing claimed. The merged map is the only
-- one carrying a vulcanus_volcanism autoplace control (terrain.lua adds it to
-- nauvis at the data stage; no vanilla surface has it), and a clone MUST copy the
-- merged map's settings to have volcano terrain at all, so presence of the control
-- is exactly the fingerprint. A vanilla-like surface (no control) is skipped
-- outright, and the mirror keys off the same control, so the identity and the map
-- model agree.
local function is_merged_map(surface)
  local controls = surface.map_gen_settings.autoplace_controls
  return controls ~= nil and controls["vulcanus_volcanism"] ~= nil
end

--- The created markers of this surface, created on first use.
local function state_for(surface)
  -- `storage` is the script-scope persistent table (Factorio 2.0; `settings.global`
  -- is the mod-setting table and `global` no longer exists). Anything kept here
  -- must be serialisable.
  local states = storage[STATE_KEY]
  if states == nil then
    states = {}
    storage[STATE_KEY] = states
  end
  -- 0.1.13 and earlier kept ONE shared marker table for every surface under the
  -- literal key "created". Hoist it to this surface under its real name: a
  -- forgotten claim would rebuild the territory and strip the chunks out of the
  -- live one, and the old mod only ever processed a single surface.
  local legacy = states.created
  if legacy ~= nil then
    states[surface.name] = legacy
    states.created = nil
  end
  local created = states[surface.name]
  if created == nil then
    created = {}
    states[surface.name] = created
  end
  return created
end

local function builder_for(surface)
  if not builders[surface.index] then
    -- The mirror context is handed in as VALUES (map_gen_settings is a plain
    -- table; the builder reads nothing else from the surface).
    builders[surface.index] = VolcanoTerritory.new(surface, {
      created = state_for(surface), map_gen_settings = surface.map_gen_settings,
    })
  end
  return builders[surface.index]
end

--- The map a surface used to carry is gone: drop the cached builder (the mirror is
--- not serialisable and its cones describe the old map) and the markers (a cone id
--- is "seed<stream>@<region>:<region>" and carries no map seed, so the next map's
--- cones come back under the SAME ids while pointing at different places -- every
--- new volcano would be skipped as "already decided").
local function forget_surface(surface)
  builders[surface.index] = nil
  local states = storage[STATE_KEY]
  if states ~= nil then states[surface.name] = nil end
end

script.on_init(function()
  storage[STATE_KEY] = {}
end)

script.on_load(function()
  -- The builder is not persisted (it holds the mirror and its cone cache); the
  -- "already created" set is, so nothing is ever created twice. Dropping the cached
  -- builder is the whole of the load path: the next chunk rebuilds it from the
  -- surface's own map_gen_settings, which is also how a new seed is picked up.
  --
  -- on_load may NOT touch storage: it is checked for save/load stability and a
  -- write here aborts the load outright ("Detected modifications to the 'storage'
  -- table ... on_load() should never change the storage table", probe-verified).
  builders = {}
end)

script.on_event(defines.events.on_chunk_generated, function(event)
  local surface = event.surface
  -- Cached verdict first: a surface that already has a builder was accepted once,
  -- and the settings read is then free (that is the steady-state path).
  if builders[surface.index] == nil and not is_merged_map(surface) then return end
  re_skin_cliffs(surface, event.area)
  -- on_chunk_generated fires per chunk in 2.0 and carries its ChunkPosition.
  builder_for(surface):on_chunk_generated(event.position)
end)

-- surface.clear() -- the Legendary Deathworld scenario resets the map this way
-- (reset.lua Public.perform_reset), and then sets a NEW seed on the surface's
-- map_gen_settings. Everything we hold describes the map that just went away.
--
-- The seed is never cached in storage: builder_for reads
-- surface.map_gen_settings and hands it to Builder.new as plain values, and the
-- builder itself is not persisted, so dropping the cached builder is all it takes
-- to pick the new seed up. The marker table is the part that has to be thrown
-- away explicitly, and it is not obvious: a cone id is "seed<stream>@<region>:<region>"
-- and does NOT contain the map seed, so the new map's cones come back under the
-- SAME ids while pointing at completely different places -- every new volcano would
-- be skipped as "already decided" and the whole reset map would go unclaimed.
--
-- The swap scenario takes the other road: it DELETES the old surface rather than
-- clearing it, and associates a brand-new one with the planet (on_pre_surface_deleted
-- below is the same cleanup for it). Both paths end at forget_surface, and both are
-- scoped to the one surface -- nobody else's markers are touched. The clone is
-- claimed WHILE IT IS STILL UNASSOCIATED (is_merged_map keys off the settings, not
-- the planet), so by swap time its map is already fully guarded.
script.on_event(defines.events.on_surface_cleared, function(event)
  local surface = game.get_surface(event.surface_index)
  if surface == nil then return end
  forget_surface(surface)
  log("[eon] map reset: " .. surface.name .. " territory state cleared")
end)

script.on_event(defines.events.on_pre_surface_deleted, function(event)
  local surface = game.get_surface(event.surface_index)
  if surface == nil then return end
  forget_surface(surface)
  log("[eon] surface deleted: " .. surface.name .. " territory state cleared")
end)
