--------------------------------------------------------------------------------
-- Add enemies from other planets
--------------------------------------------------------------------------------

local terrain = require("map-generation.terrain")
local space_enemy_autoplace = require ("__space-age__.prototypes.entity.space-enemy-autoplace-utils")

--------------------------------------------------------------------------------
-- MARK: Remove Nauvis enemies aka biters, spitters and spawners from surface that does not belong to nauvis
--------------------------------------------------------------------------------

data:extend({
  -- Default noise expressions for nauvis enemies
  {
    type = "noise-expression",
    name = "biter_spawner",
    expression = data.raw["unit-spawner"]["biter-spawner"].autoplace.probability_expression
  },
  {
    type = "noise-expression",
    name = "spitter_spawner",
    expression = data.raw["unit-spawner"]["spitter-spawner"].autoplace.probability_expression
  },
  {
    type = "noise-expression",
    name = "small_worm_turret",
    expression = data.raw["turret"]["small-worm-turret"].autoplace.probability_expression
  },
  {
    type = "noise-expression",
    name = "medium_worm_turret",
    expression = data.raw["turret"]["medium-worm-turret"].autoplace.probability_expression
  },
  {
    type = "noise-expression",
    name = "big_worm_turret",
    expression = data.raw["turret"]["big-worm-turret"].autoplace.probability_expression
  },
  {
    type = "noise-expression",
    name = "behemoth_worm_turret",
    expression = data.raw["turret"]["behemoth-worm-turret"].autoplace.probability_expression
  },
})

data.raw["unit-spawner"]["biter-spawner"].autoplace.probability_expression = "eon_mask_nauvis_territory(biter_spawner)"
data.raw["unit-spawner"]["spitter-spawner"].autoplace.probability_expression = "eon_mask_nauvis_territory(spitter_spawner)"
data.raw["turret"]["small-worm-turret"].autoplace.probability_expression = "eon_mask_nauvis_territory(small_worm_turret)"
data.raw["turret"]["medium-worm-turret"].autoplace.probability_expression = "eon_mask_nauvis_territory(medium_worm_turret)"
data.raw["turret"]["big-worm-turret"].autoplace.probability_expression = "eon_mask_nauvis_territory(big_worm_turret)"
data.raw["turret"]["behemoth-worm-turret"].autoplace.probability_expression = "eon_mask_nauvis_territory(behemoth_worm_turret)"

--------------------------------------------------------------------------------
-- MARK: Add Vulcanus enemies aka demolishers
--------------------------------------------------------------------------------

data.raw.planet["nauvis"].map_gen_settings.territory_settings = data.raw.planet["vulcanus"].map_gen_settings.territory_settings

-- The engine's own minimum_territory_size (10) is a trap for this map: a volcano
-- that fragments into sub-10-chunk islands is discarded wholesale, which is how
-- whole flanks ended up unguarded. The runtime mirror claims one closed disc per
-- cone, so the floor only has to catch leftovers, and 3 does that while keeping
-- small volcano cores.
--
-- The floor MUST stay low: raising it turns tiny cones into unguarded territory,
-- and unguarded lava is free mining.
data.raw.planet["nauvis"].map_gen_settings.territory_settings.minimum_territory_size = 3

-- VOLCANO TERRITORIES ARE BUILT AT RUNTIME, by the spot mirror in control.lua
-- (see volcano-territory.lua and features/lua-territory.feature). This file's job is
-- only to keep the engine's own index out of the way: the mirror names each cone and
-- hands create_territory the whole closed chunk list once, and
-- create_territory strips chunks from any other territory, so two systems claiming at
-- once would fight over every volcano.
--
-- So both of the engine's entry points are switched off unconditionally -- the
-- territory index and the starting area it is combined with. There is no setting and
-- no alternative path: the expression index that used to live here (a voronoi cell id
-- per volcano, split left/right by the field gradient, with a per-territory size
-- nudge) could not name a volcano at all, which is why it is gone rather than kept
-- behind a switch. The record of what it did and why it was not enough is in
-- features/demolisher-territory.feature.
data.raw["noise-expression"]["demolisher_territory_expression"].expression = "-inf"
data.raw["noise-expression"]["demolisher_starting_area"].expression = "-inf"

--------------------------------------------------------------------------------
-- MARK: Noise expressions our changes did NOT make dead
--------------------------------------------------------------------------------
--
-- Recorded because the opposite looks true and is not: EoN wraps the vanilla
-- resource probability expressions rather than replacing them
-- ("eon_mask_off_aquilo_territory(eon_mask_off_ammonia_ocean(" .. current .. "))"
-- in map-generation/resources-updates.lua), so every `default-<ore>-patches`
-- expression is still live, inside the resource autoplaces. Deleting them is a
-- load-time error ("Unknown variable: default-coal-patches"), which is the only
-- reason this note exists.
