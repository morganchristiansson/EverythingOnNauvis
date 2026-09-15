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

-- Demolisher territory follows an eroded volcano mask (see eon_demolisher_territory):
-- territory is sampled per 32x32 chunk at chunk corners, so an uneroded mask pokes
-- outside the volcano to the bottom/right. The shifted eroded mask keeps territory
-- centered and inside while still covering all lava. Territories exist only on volcano
-- terrain, so demolishers stay at volcanoes.
-- Smaller voronoi territories than vanilla (384): more territories per volcano,
-- so multi-size volcanoes are the norm rather than luck, with a few guardians
-- each. Both the territory index (vanilla) and the parity mix below reference
-- demolisher_territory_radius by name, so they stay in sync automatically.
data.raw["noise-expression"]["demolisher_territory_radius"].expression = 288

-- Per-territory mix (0/2 by voronoi cell parity) for varied demolisher sizes
-- within one volcano. It must reach 2, not 1: variation buckets below 2 as
-- small, so a 0/1 mix would stay invisible (every volcano uniform small).
-- Floor-based parity, not bitwise: cell ids are floats.
data:extend({
  {
    type = "noise-expression",
    name = "eon_demolisher_mix",
    expression = "2 * (cell - 2 * floor(cell / 2))",
    local_expressions =
    {
      cell = "voronoi_cell_id{x = x + 1000 * demolisher_territory_radius, y = y + 1000 * demolisher_territory_radius, seed0 = map_seed, seed1 = 0, grid_size = demolisher_territory_radius, distance_type = 'manhattan', jitter = 1}"
    }
  },
})
data.raw["noise-expression"]["demolisher_starting_area"].expression = "if(eon_demolisher_territory, 0, -inf)"
local demolisher_territory = data.raw["noise-expression"]["demolisher_territory_expression"].expression
data.raw["noise-expression"]["demolisher_territory_expression"].expression = "if(eon_demolisher_territory, " .. demolisher_territory .. ", -inf)"

-- Demolisher size (yoinked from EverythingOnNauvis-Patches' slowed progression).
-- Size selection indexes the territory units list {small, medium, big}, so mods
-- adding sizes (colossal, gargantuan, ...) extend the reachable range
-- naturally; negative variation means no demolisher.
-- Progression is slowed vs vanilla and normalized by packing density: distance
-- divided by volcanism, so the Nth volcano out is roughly the same size class
-- at any frequency/size setting (dense maps progress earlier, sparse maps
-- later). Discrete per-volcano counting is impossible -- noise expressions are
-- pure per-pixel functions -- so this gradient is the closest expressible form.
-- Each voronoi territory flips a parity bit, so multi-territory volcanoes mix
-- sizes (small+medium near, medium+big far) by luck of the draw; single-size
-- volcanoes stay uniform. Small-only volcano ground is capped to medium so
-- big demolishers never sit on small volcanoes.
data.raw["noise-expression"]["demolisher_variation_expression"].expression = "if(eon_volcano_small_cap > 1, min(4, eon_demolisher_mix + floor(clamp(distance / ((30 * 32) * eon_volcanism) - 0.25, 0, 4))), min(1, eon_demolisher_mix + floor(clamp(distance / ((30 * 32) * eon_volcanism) - 0.25, 0, 4)))) + (-99 * no_enemies_mode)"

--------------------------------------------------------------------------------
-- MARK: Add Gleba enemies aka strafer, stompers and wriggler pentapods
--------------------------------------------------------------------------------

data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["gleba_enemy_base"] = {}

-- Normal spawning
data.raw["noise-expression"]["gleba_spawner"].expression = "eon_mask_gleba_territory(max(0.01 * gleba_starting_enemies, max(min(0.02, enemy_autoplace_base(0, 8)), min(0.001, gleba_fertile_spots_coastal * 5000 - gleba_biome_mask_green * 25000)) * (distance > 500 * gleba_starting_area_multiplier)) * gleba_above_deep_water_mask)"
data.raw["noise-expression"]["gleba_spawner_small"].expression = "eon_mask_gleba_territory(max(0.02 * gleba_starting_enemies, 0.02 * gleba_starting_enemies_safe, min(0.02, enemy_autoplace_base(0, 8)), min(0.001, gleba_fertile_spots_coastal * 5000 - gleba_biome_mask_green * 25000)) * gleba_above_deep_water_mask)"
