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

-- Demolisher SIZES and TERRITORY LAYOUT.
--
-- Size = size-class (0..4 by distance; the ramp scales with volcano frequency
-- so 600% keeps smalls/mediums much further out) + a per-territory random bit
-- (eon_demolisher_nudge), so adjacent territories are always within one class
-- of each other. Baby volcanoes get small demolishers only.
--
-- Territory id = ONE voronoi cell alone (1100px): no mama, no rings, no
-- per-volcano tiers. The mother/ring experiments never produced consistent
-- results -- the mother disc's area depends on the spot-field peak (which
-- varies per cone), so identical-looking cones came out with 3-chunk mothers
-- or none; and any second dimension (rings, arcs, sub-ids) multiplied the
-- pieces. One grid keeps it predictable: most cones land in a single cell
-- (whole cone, one demolisher), the biggest straddle into 2-3 big pieces.
-- Residuals (irreducible with position-only noise): two touching cones inside
-- one cell still fuse; a cone can lose a small edge piece to a cell cut.
-- Dropping small pieces is not an option (unguarded gaps are free mining).
data:extend({
  {
    type = "noise-expression",
    name = "eon_demolisher_nudge",
    expression = "floor(random_penalty_between(0, 2, 479))"
  },
  {
    -- The territory cell grid (fixed 1100px; voronoi_cell_id needs a constant
    -- grid). Ids are per-cell floats; abs() keeps them positive.
    type = "noise-expression",
    name = "eon_demolisher_cell",
    expression = "abs(voronoi_cell_id{x = x + 1000 * demolisher_territory_radius, y = y + 1000 * demolisher_territory_radius, seed0 = map_seed, seed1 = 47, grid_size = 1100, distance_type = 'manhattan', jitter = 1})"
  },
  {
    -- Baby volcanoes (small size roll): only small demolishers fit.
    type = "noise-expression",
    name = "eon_volcano_baby",
    expression = "eon_volcano_size_dist < 0.62"
  },
})

data.raw["noise-expression"]["demolisher_starting_area"].expression = "if(eon_demolisher_territory, 0, -inf)"
data.raw["noise-expression"]["demolisher_territory_expression"].expression =
    "if(eon_demolisher_territory, 1e6 + eon_demolisher_cell, -inf)"

-- Sizes: distance class + random nudge (medium max on small-cap ground); babies:
-- 0 (small) only.
local rampt = "((30 * 32) * eon_volcanism * sqrt(control:vulcanus_volcanism:frequency))"
local sized = "eon_demolisher_nudge + floor(clamp(distance / " .. rampt .. " - 0.25, 0, 4))"
local norm = "min(4, " .. sized .. ")"
local cap = "min(1, " .. sized .. ")"
data.raw["noise-expression"]["demolisher_variation_expression"].expression =
    "if(eon_volcano_baby, 0, if(eon_volcano_small_cap > 1, " .. norm .. ", " .. cap .. ")) + (-99 * no_enemies_mode)"


--------------------------------------------------------------------------------
-- MARK: Add Gleba enemies aka strafer, stompers and wriggler pentapods
--------------------------------------------------------------------------------

data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["gleba_enemy_base"] = {}

-- Normal spawning (wrap the vanilla spawner expressions by variable: mask
-- only, no re-typed copy text).
data.raw["noise-expression"]["gleba_spawner"].expression = "eon_mask_gleba_territory(" .. data.raw["noise-expression"]["gleba_spawner"].expression .. ")"
data.raw["noise-expression"]["gleba_spawner_small"].expression = "eon_mask_gleba_territory(" .. data.raw["noise-expression"]["gleba_spawner_small"].expression .. ")"
