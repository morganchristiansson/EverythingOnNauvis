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
-- of each other (small+medium near spawn, medium+big further out) -- never
-- small+big next to each other. Baby volcanoes get small demolishers only.
--
-- Territory layout adapts to the volcano:
--   * Large volcanoes (eon_volcano_multi, size factor >= 0.85, room for
--     several demolishers): the inner core (spots > 0.88) is ONE merged
--     territory (id 1) holding the MAMA (big-sized) demolisher; the rest of
--     the core maps to fine 260px voronoi cells -- small ring territories
--     looping around the mama, sized by the normal class+nudge.
--   * Smaller volcanoes: the whole core is id 1 -> a single territory with one
--     normally-sized demolisher.
-- Replaces the old voronoi-cell-id parity mix, which correlated with the
-- volcano cells and left whole neighborhoods (and everything within ~1000
-- tiles of spawn) one uniform size.
data:extend({
  {
    type = "noise-expression",
    name = "eon_demolisher_nudge",
    expression = "floor(random_penalty_between(0, 2, 479))"
  },
  {
    -- Inner-core marker for the mama territory (on the at16 field like the
    -- mask, so chunk sampling aligns). Only consulted on multi volcanoes.
    type = "noise-expression",
    name = "eon_demolisher_center",
    expression = "eon_terr_volcano_spots > 0.88"
  },
  {
    -- Fine voronoi cells for the ring territories (slivers looping around the
    -- mama). Ids are floats, offset so they never collide with the center's 1.
    type = "noise-expression",
    name = "eon_demolisher_ring_cell",
    expression = "voronoi_cell_id{x = x + 1000 * demolisher_territory_radius, y = y + 1000 * demolisher_territory_radius, seed0 = map_seed, seed1 = 31, grid_size = 260, distance_type = 'manhattan', jitter = 1}"
  },
  {
    -- Coarse voronoi cells for LARGE volcanoes: split through the middle into
    -- 2-3 chunky territories (grid ~550px; a ~1100px diameter cone spans 2-3
    -- cells), no mama.
    type = "noise-expression",
    name = "eon_demolisher_split_cell",
    expression = "voronoi_cell_id{x = x + 1000 * demolisher_territory_radius, y = y + 1000 * demolisher_territory_radius, seed0 = map_seed, seed1 = 47, grid_size = 550, distance_type = 'manhattan', jitter = 1}"
  },
  {
    -- Medium volcanoes: room for mama + ring (size factor 0.62-0.90).
    type = "noise-expression",
    name = "eon_volcano_multi",
    expression = "eon_volcano_size_dist >= 0.62"
  },
  {
    -- Large volcanoes: split-through-the-middle layout.
    type = "noise-expression",
    name = "eon_volcano_large",
    expression = "eon_volcano_size_dist >= 0.90"
  },
  {
    -- Coarse voronoi cell, ~one volcano per cell (grid 2200): a per-VOLCANO
    -- territory id base so touching/merged volcanoes never merge their
    -- territories (the old shared id-1 merged any adjacent volcanoes).
    type = "noise-expression",
    name = "eon_demolisher_volcano_cell",
    expression = "voronoi_cell_id{x = x + 1000 * demolisher_territory_radius, y = y + 1000 * demolisher_territory_radius, seed0 = map_seed, seed1 = 13, grid_size = 2200, distance_type = 'manhattan', jitter = 1}"
  },
  {
    -- Baby volcanoes (small size roll): only small demolishers fit.
    type = "noise-expression",
    name = "eon_volcano_baby",
    expression = "eon_volcano_size_dist < 0.62"
  },
})

data.raw["noise-expression"]["demolisher_starting_area"].expression = "if(eon_demolisher_territory, 0, -inf)"
-- Layout per volcano (per-volcano id base + local sub-id): large -> split
-- cells; medium -> mama (sub 0) + ring; small -> one territory (sub 0).
local volcano_base = "1000 * floor(eon_demolisher_volcano_cell)"
local sub = function(name, off)
  return off .. " + (floor(" .. name .. ") - 100 * floor(" .. name .. " / 100))"
end
local ring_sub = sub("eon_demolisher_ring_cell", "100")
local split_sub = sub("eon_demolisher_split_cell", "200")
data.raw["noise-expression"]["demolisher_territory_expression"].expression =
    "if(eon_demolisher_territory, " .. volcano_base .. " + if(eon_volcano_large, " .. split_sub .. ", if(eon_volcano_multi, if(eon_demolisher_center, 0, " .. ring_sub .. "), 0)), -inf)"

-- Sizes: mama = 2 (big; medium max on small-cap ground); ring/split/single
-- territories get the distance class + random nudge. Babies: 0 (small) only.
local rampt = "((30 * 32) * eon_volcanism * sqrt(control:vulcanus_volcanism:frequency))"
local sized = "eon_demolisher_nudge + floor(clamp(distance / " .. rampt .. " - 0.25, 0, 4))"
local norm = "min(4, " .. sized .. ")"
local cap = "min(1, " .. sized .. ")"
local norm_branch = "if(eon_volcano_large, " .. norm .. ", if(eon_volcano_multi, if(eon_demolisher_center, 2, " .. norm .. "), " .. norm .. "))"
local cap_branch = "if(eon_volcano_large, " .. cap .. ", if(eon_volcano_multi, if(eon_demolisher_center, min(1, 2), " .. cap .. "), " .. cap .. "))"
data.raw["noise-expression"]["demolisher_variation_expression"].expression =
    "if(eon_volcano_baby, 0, if(eon_volcano_small_cap > 1, " .. norm_branch .. ", " .. cap_branch .. ")) + (-99 * no_enemies_mode)"


--------------------------------------------------------------------------------
-- MARK: Add Gleba enemies aka strafer, stompers and wriggler pentapods
--------------------------------------------------------------------------------

data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["gleba_enemy_base"] = {}

-- Normal spawning (wrap the vanilla spawner expressions by variable: mask
-- only, no re-typed copy text).
data.raw["noise-expression"]["gleba_spawner"].expression = "eon_mask_gleba_territory(" .. data.raw["noise-expression"]["gleba_spawner"].expression .. ")"
data.raw["noise-expression"]["gleba_spawner_small"].expression = "eon_mask_gleba_territory(" .. data.raw["noise-expression"]["gleba_spawner_small"].expression .. ")"
