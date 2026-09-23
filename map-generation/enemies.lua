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
--
-- The floor MUST stay low: raising it turns cell-straddle nibbles and tiny
-- cones into unguarded territory (free access to lava/tungsten/acid geysers).
-- Nibbles that survive as 3-4-chunk territories are the accepted cost of no
-- unguarded gaps (playtested at 200% volcanism: at most one per map, and it
-- keeps its volcanoes guarded).
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
-- Territory = ONE voronoi cell per volcano (1100px grid), medium+ volcanoes
-- SPLIT left/right into two territories, small volcanoes kept whole.
--
-- The split cut is anchored by the volcano FIELD GRADIENT, not any world
-- lattice: evaluating the merged volcano field at x+-32px and comparing signs
-- tells which side of THIS volcano's peak the chunk is on. The sign crosses
-- exactly at the deployed peak column (probe-verified: lossless partition of
-- the territory mask, cut within ~1 column of the lava centroid, immune to
-- the spot-deployment jitter that kills lattice-anchored cuts). The gradient
-- also SPLITS MERGED volcanoes: a fused pair in one cell no longer shares one
-- id -- each half gets its own id, so the blob becomes 2 territories instead
-- of 1 (west halves + east halves; islands across member volcanoes stay, judge
-- grouping in the real game). Small volcanoes (eon_volcano_size_dist < 0.55)
-- stay whole so tiny halves never drop under the territory floor (unguarded
-- seams are free mining, not acceptable).
-- Territory id per cell: 1 = whole (small), 2 = west half, 3 = east half.
data:extend({
  {
    -- The territory cell grid (fixed 1100px; voronoi_cell_id needs a constant
    -- grid). Ids are per-cell floats; abs() keeps them positive.
    type = "noise-expression",
    name = "eon_demolisher_cell",
    expression = "abs(voronoi_cell_id{x = x + 1000 * demolisher_territory_radius, y = y + 1000 * demolisher_territory_radius, seed0 = map_seed, seed1 = 47, grid_size = 1100, distance_type = 'manhattan', jitter = 1})"
  },
  {
    -- Field gradient at the chunk corner: merged volcano field sampled 32px
    -- east minus 32px west (inline arithmetic offsets of eon_volcano_spots_at
    -- -- named-function position args DON'T move, inline x +- offset DOES).
    -- dir > 0 <=> the field rises toward the east <=> the peak is east of me
    -- <=> I am on the WEST side of the peak.
    type = "noise-expression",
    name = "eon_demolisher_dir",
    expression = "(max(eon_volcano_spots_at{x_offset = 32, y_offset = 0, seed = 1, spacing_mult = 1, size_mult = 0.75}, eon_volcano_spots_at{x_offset = 32, y_offset = 0, seed = 2, spacing_mult = 1.8, size_mult = 1.25}) - max(eon_volcano_spots_at{x_offset = -32, y_offset = 0, seed = 1, spacing_mult = 1, size_mult = 0.75}, eon_volcano_spots_at{x_offset = -32, y_offset = 0, seed = 2, spacing_mult = 1.8, size_mult = 1.25}))"
  },
  {
    -- Zone: 1 = whole (small volcano, exempt from the split), 2 = west half,
    -- 3 = east half.
    type = "noise-expression",
    name = "eon_demolisher_zone",
    expression = "if(eon_volcano_size_dist < 0.55, 1, if(eon_demolisher_dir < 0, 3, 2))"
  },
  {
    -- Per-territory size nudge (0 or 1): the variation expression samples it
    -- once per territory, so the two halves of a split cone roll independently
    -- and stay within one class of each other (small+medium / medium+big,
    -- never small+big).
    type = "noise-expression",
    name = "eon_demolisher_nudge",
    expression = "floor(random_penalty_between(0, 1.99999, 479))"
  },
})

data.raw["noise-expression"]["demolisher_starting_area"].expression = "if(eon_demolisher_territory, 0, -inf)"
data.raw["noise-expression"]["demolisher_territory_expression"].expression =
    "if(eon_demolisher_territory, 1e6 + 1000 * eon_demolisher_cell + eon_demolisher_zone, -inf)"

-- Sizes: tier by volcano size (eon_volcano_size_dist -- the same smooth roll
-- that scales the cone): small (<0.55) -> small (class 0), medium (0.55..0.8)
-- -> medium (1), large+ (>=0.8) -> big (2). No distance ramp: a cone's class
-- never depends on map radius. A per-territory nudge (eon_demolisher_nudge,
-- 0 or 1, sampled once per territory) pushes each half one class up, so a
-- split cone gets two demolishers within one class of each other (never
-- small+big on the same volcano). Small-only ground (strong small spot
-- system, no big field) caps the class at medium so small-system cones never
-- host a big demolisher; the <0.55 tier already yields smalls.
local tier = "if(eon_volcano_size_dist < 0.55, 0, if(eon_volcano_size_dist < 0.8, 1, 2))"
local class = "min(2, " .. tier .. " + eon_demolisher_nudge)"
data.raw["noise-expression"]["demolisher_variation_expression"].expression =
    "if(eon_volcano_small_cap > 1, " .. class .. ", min(" .. class .. ", 1)) + (-99 * no_enemies_mode)"


--------------------------------------------------------------------------------
-- MARK: Add Gleba enemies aka strafer, stompers and wriggler pentapods
--------------------------------------------------------------------------------

data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["gleba_enemy_base"] = {}

-- Normal spawning (wrap the vanilla spawner expressions by variable: mask
-- only, no re-typed copy text).
data.raw["noise-expression"]["gleba_spawner"].expression = "eon_mask_gleba_territory(" .. data.raw["noise-expression"]["gleba_spawner"].expression .. ")"
data.raw["noise-expression"]["gleba_spawner_small"].expression = "eon_mask_gleba_territory(" .. data.raw["noise-expression"]["gleba_spawner_small"].expression .. ")"
