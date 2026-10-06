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
  -- Space travel's destination at the edge of the solar system must point at the
  -- LIVE planet, not at the dummy (remove-planets.lua pointed it at nauvis).
  data.raw["space-connection"]["aquilo-solar-system-edge"].from = "nauvis2"
  -- The original nauvis is the dummy now: hide it from the starmap exactly like
  -- every other removed planet. Its map_gen_settings must NOT be nilled -- the
  -- primary surface (index 1) is generated from them at save creation, and a
  -- scenario may still stand players on it while a surface swap is in flight.
  data.raw.planet["nauvis"].hidden = true
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