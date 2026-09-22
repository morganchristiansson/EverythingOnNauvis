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

-- Volcano patches fragment into <10-chunk islands (voronoi cells of 9x9 chunks
-- sliced by ragged coastlines and water pockets), and vanilla's
-- minimum_territory_size = 10 drops those islands entirely -- the "missing top
-- half" demolisher territory: whole volcano flanks were claimed by the engine
-- and then discarded. With the 512px cells and core-only mask the volcano
-- interior lands in one multi-chunk territory, so the floor only needs to catch
-- the leftover 1x1/2x1 cell slivers that strand a demolisher on a single patrol
-- point (tail-chasing). 3 drops those while keeping small volcano cores.
data.raw.planet["nauvis"].map_gen_settings.territory_settings.minimum_territory_size = 3

-- Demolisher territory follows the volcano-terrain tile mask (eon_vulcanus_terrain),
-- which the engine samples at one fixed world-aligned corner per 32x32 chunk and
-- claims if the expression is >= 0 there. Because the mask is the same signal the
-- volcano tiles place on, territory can't drift off the volcano; the only remaining
-- artifact is the one-chunk corner quantization at the rim (probe-verified, see
-- AGENTS.md). Territories exist only on volcano terrain, so demolishers stay at
-- volcanoes.
-- Smaller voronoi territories than vanilla was wrong for EoN: manhattan-diamond
-- cell borders cut ragged coastal volcanoes into single-chunk slivers (the
-- "medium demolisher patrolling a single chunk" pattern). Radius ~512 (16 chunks)
-- is larger than the typical volcano footprint here, so a volcano lands inside one
-- cell and gets one multi-chunk territory; the biggest volcanoes still span cells
-- and pick up the mixed-size parity below. Both the territory index (vanilla) and
-- the parity mix below reference demolisher_territory_radius by name, so they stay
-- in sync automatically.
data.raw["noise-expression"]["demolisher_territory_radius"].expression = 512

-- Per-territory mix (0/1 by voronoi cell parity) for varied demolisher sizes
-- within one volcano: adjacent cells flip class, so small+medium (or
-- medium+big) is the norm on multi-cell volcanoes instead of small+big. It
-- must reach 1, not 2: parity 0/2 made every other cell thumb big from spawn,
-- which is why smalls were rare. Floor-based parity, not bitwise: cell ids are
-- floats.
data:extend({
  {
    type = "noise-expression",
    name = "eon_demolisher_mix",
    expression = "cell - 2 * floor(cell / 2)",
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
-- Progression: distance divided by the ramp, and the ramp scales with volcano
-- frequency (sqrt slider) on top of volcanism, so at 600% frequency smalls and
-- mediums last much further out instead of flipping to big near spawn. Discrete
-- per-volcano counting is impossible -- noise expressions are pure per-pixel
-- functions -- so this distance gradient is the closest expressible form.
-- Each voronoi territory flips a parity bit (eon_demolisher_mix: 0/1), so
-- multi-territory volcanoes mix adjacent size classes (small+medium near,
-- medium+big far) by luck of the draw; single-territory volcanoes stay uniform.
-- Small-only volcano ground is capped to medium so big demolishers never sit on
-- small volcanoes.
data.raw["noise-expression"]["demolisher_variation_expression"].expression = "if(eon_volcano_small_cap > 1, min(4, eon_demolisher_mix + floor(clamp(distance / ((30 * 32) * eon_volcanism * sqrt(control:vulcanus_volcanism:frequency)) - 0.25, 0, 4))), min(1, eon_demolisher_mix + floor(clamp(distance / ((30 * 32) * eon_volcanism * sqrt(control:vulcanus_volcanism:frequency)) - 0.25, 0, 4)))) + (-99 * no_enemies_mode)"

--------------------------------------------------------------------------------
-- MARK: Add Gleba enemies aka strafer, stompers and wriggler pentapods
--------------------------------------------------------------------------------

data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["gleba_enemy_base"] = {}

-- Normal spawning (wrap the vanilla spawner expressions by variable: mask
-- only, no re-typed copy text).
data.raw["noise-expression"]["gleba_spawner"].expression = "eon_mask_gleba_territory(" .. data.raw["noise-expression"]["gleba_spawner"].expression .. ")"
data.raw["noise-expression"]["gleba_spawner_small"].expression = "eon_mask_gleba_territory(" .. data.raw["noise-expression"]["gleba_spawner_small"].expression .. ")"
