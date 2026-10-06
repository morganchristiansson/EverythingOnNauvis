-- The surface-swap planet (optional, off by default).
--
-- The primary surface (index 1, "nauvis") can never be deleted -- LuaSurface.deletable
-- is false for it, hardcoded in the engine -- so the planet can never lose its
-- surface and LuaPlanet::associate_surface can never move the nauvis planet onto a
-- runtime-created surface. The one legal way to "swap the map" is to leave the
-- original nauvis planet/surface as a dummy and run the game on a CLONE planet,
-- whose surface the scenario creates and deletes at will (LuaPlanet::create_surface
-- re-materialises it; a created surface is deletable).
--
-- The clone is deep-copied from nauvis HERE, in data-final-fixes, AFTER the whole
-- map merge (map-generation/* run in data-updates.lua), so it carries identical
-- merged map_gen_settings -- including the vulcanus_volcanism autoplace control the
-- runtime identity (control.lua is_merged_map) keys off. No runtime changes are
-- needed: whatever surface the clone is materialised on, the mod claims it exactly
-- like the real one.
--
-- Off by default: a vanilla freeplay game keeps a single Nauvis and this planet
-- does not exist. A scenario host turns eon-nauvis2-clone on to get the swap planet.
if settings.startup["eon-nauvis2-clone"].value then
  local nauvis2 = table.deepcopy(data.raw.planet["nauvis"])
  nauvis2.name = "nauvis2"
  data:extend{ nauvis2 }
  -- Space travel's destination at the edge of the solar system: point it at the
  -- LIVE planet (nauvis2), not the dummy -- unless eon-restore-space-locations
  -- brought back the normal trip graph, in which case the edge is reached from the
  -- aquilo space-location (remove-planets.lua sets .from = "aquilo") and a rewiring
  -- of the edge's origin would break that progression.
  if not settings.startup["eon-restore-space-locations"].value then
    data.raw["space-connection"]["aquilo-solar-system-edge"].from = "nauvis2"
  end
  -- The original nauvis is the dummy now: hide it from the starmap exactly like
  -- every other removed planet, and nil its map_gen_settings. The settings ARE
  -- the merged map, and the primary surface only exists as a staging area while a
  -- surface swap is in flight, so a plain engine-default (vanilla) map there is
  -- cheaper, faster and lighter than generating the full merged program for a
  -- surface nobody plays on. Safe: world creation falls back to the default map
  -- when the settings are absent (probe-verified 2.0.77: --create succeeds,
  -- surface 1 tile = grass-1, planet still associated). MUST come after the
  -- deepcopy above -- the clone's merged settings come out of it.
  data.raw.planet["nauvis"].hidden = true
  data.raw.planet["nauvis"].map_gen_settings = nil
  -- remove-planets.lua swept every default_import_location to "nauvis"; with the
  -- clone live, platform import requests must land on the planet that exists.
  for _, types in pairs(data.raw) do
    if type(types) == "table" then
      for _, proto in pairs(types) do
        if type(proto) == "table" and proto.default_import_location then
          proto.default_import_location = "nauvis2"
        end
      end
    end
  end
end