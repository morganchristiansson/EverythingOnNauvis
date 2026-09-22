--------------------------------------------------------------------------------
-- Fixes map generation for terrain
--------------------------------------------------------------------------------
local data_util = require("data-util")

local terrain = {}

log("[EoN-morganc] build marker: fades-v7-signsafe")

function terrain.mask_nauvis_territory(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_nauvis_territory(" .. data_util.generate_eon_name(decorative) .. ")"
end

-- Nauvis tile allowed southward into the mixing band: alive while the
-- transition value stays below threshold (higher = dies further south).
-- Keeps the aquilo/volcano exclusions of the plain territory mask.
function terrain.mask_nauvis_deep(decorative, decorative_type, threshold)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_nauvis_deep(" .. data_util.generate_eon_name(decorative) .. ", " .. threshold .. ")"
end

-- Nauvis native that blends into neighbouring biomes instead of hard-
-- cutting: one evaluation of the vanilla pattern times per-boundary fades
-- (eon_mask_nauvis_territory_fade). threshold = where the gleba blend ends
-- (0 = full on nauvis, fading across the first 10 transition into gleba).
function terrain.mask_nauvis_territory_fade(decorative, decorative_type, threshold)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_nauvis_territory_fade(" .. data_util.generate_eon_name(decorative) .. ", " .. (threshold or 0) .. ")"
end

-- Gleba native that blends north into the mixing band instead of the hard
-- mask_gleba_early switch (eon_mask_gleba_territory_fade). threshold = where
-- the north blend ends (-40 for the transition flora leaders).
function terrain.mask_gleba_territory_fade(decorative, decorative_type, threshold)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_gleba_territory_fade(" .. data_util.generate_eon_name(decorative) .. ", " .. (threshold or 0) .. ")"
end

function terrain.mask_off_nauvis_territory(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_off_nauvis_territory(" .. data_util.generate_eon_name(decorative) .. ")"
end

function terrain.mask_resource_territory(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_off_vulcano_terrain(eon_mask_resource_territory(" .. data_util.generate_eon_name(decorative) .. "))"
end

-- Same as above but also off Gleba territory (vanilla Gleba has none of the
-- Nauvis ores; stone is handled separately with vanilla Gleba stone instead).
function terrain.mask_resource_territory_off_gleba(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_off_gleba_territory(eon_mask_off_vulcano_terrain(eon_mask_resource_territory(" .. data_util.generate_eon_name(decorative) .. ")))"
end

function terrain.mask_aquilo_territory(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_aquilo_territory(" .. data_util.generate_eon_name(decorative) .. ")"
end

-- Aquilo feathering: land decoratives (bergs, drifts, ice decals) reach past
-- the territory edge onto northern land; water-bound floaters reach onto
-- Nauvis water. Reach is in elevation units; verified empirically.
function terrain.mask_aquilo_land_early(decorative, decorative_type, reach)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_aquilo_land_early(" .. data_util.generate_eon_name(decorative) .. ", " .. reach .. ")"
end

function terrain.mask_aquilo_water_early(decorative, decorative_type, reach)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_aquilo_water_early(" .. data_util.generate_eon_name(decorative) .. ", " .. reach .. ")"
end

function terrain.mask_off_aquilo_territory(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_off_aquilo_territory(" .. data_util.generate_eon_name(decorative) .. ")"
end

function terrain.mask_ammonia_ocean(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_ammonia_ocean(" .. data_util.generate_eon_name(decorative) .. ")"
end

function terrain.mask_off_ammonia_ocean(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_off_ammonia_ocean(" .. data_util.generate_eon_name(decorative) .. ")"
end

function terrain.mask_gleba_territory(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_gleba_territory(" .. data_util.generate_eon_name(decorative) .. ")"
end

-- Gleba tile allowed northward into the mixing band: alive once the transition
-- value passes threshold (lower/negative = starts further north).
function terrain.mask_gleba_early(decorative, decorative_type, threshold)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_gleba_early(" .. data_util.generate_eon_name(decorative) .. ", " .. threshold .. ")"
end

-- Gleba water may start at the Nauvis water cut line (region -10) so southern
-- oceans continue water-to-water instead of going dry at the border.
function terrain.mask_gleba_water(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_gleba_water(" .. data_util.generate_eon_name(decorative) .. ")"
end

function terrain.mask_off_gleba_territory(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_off_gleba_territory(" .. data_util.generate_eon_name(decorative) .. ")"
end

function terrain.mask_vulcano_coverage(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_vulcano_coverage(" .. data_util.generate_eon_name(decorative) .. ")"
end

function terrain.mask_off_vulcano_coverage(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_off_vulcano_coverage(" .. data_util.generate_eon_name(decorative) .. ")"
end

function terrain.mask_vulcano_terrain(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_vulcano_terrain(" .. data_util.generate_eon_name(decorative) .. ")"
end

-- Volcano decoratives feather past the terrain edge, like Gleba decoratives
-- feather past the border with eon_mask_gleba_early: volcano terrain sits at
-- eon_mountain_volcano_spots above ~0.46, so a lower threshold widens the
-- band (higher/wider = further out, capped by the spots' basement radius).
function terrain.mask_volcano_early(decorative, decorative_type, threshold)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_volcano_early(" .. data_util.generate_eon_name(decorative) .. ", " .. threshold .. ")"
end


function terrain.mask_off_vulcano_terrain(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_off_vulcano_terrain(" .. data_util.generate_eon_name(decorative) .. ")"
end

function terrain.mask_resource_territory_allow_volcano(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_resource_territory(" .. data_util.generate_eon_name(decorative) .. ")"
end

data:extend({
  -- Noise expressions
  {
    -- Define starting radius
    type = "noise-expression",
    name = "eon_starting_radius",
    expression = "0.7 * 0.75"
  },
})

--------------------------------------------------------------------------------
-- MARK: Fix Nauvis related map gen settings
--------------------------------------------------------------------------------

-- Remove water where at vulcano spots
data.raw.tile["water"].autoplace.probability_expression = "eon_updated_water + if(eon_gleba_region_deep(-10), -inf, 0)"
data.raw.tile["deepwater"].autoplace.probability_expression = "eon_updated_deepwater + if(eon_gleba_region_deep(-10), -inf, 0)"

-- START: Mask nauvis territory on all autoplace settings
-- Remove nauvis trees from eon_vulcanus_terrain
-- data.raw["noise-expression"]["trees_forest_path_cutout"].expression = "mask_off_vulcano_terrain(min(nauvis_bridge_paths, nauvis_hills_paths, forest_paths))"
data.raw["noise-expression"]["trees_forest_path_cutout_faded"].expression = "eon_mask_nauvis_territory(" .. data.raw["noise-expression"]["trees_forest_path_cutout_faded"].expression .. ")"

-- Dead trees only grow on nauvis territory (same fix as EverythingOnNauvis-Patches).
-- Masked at expression level like trees_forest_path_cutout_faded: tree_dead_grey_trunk
-- is only used by dead-grey-trunk, which does not reference the faded expression.
data.raw["noise-expression"]["tree_dead_grey_trunk"].expression = "eon_mask_nauvis_deep(" .. data.raw["noise-expression"]["tree_dead_grey_trunk"].expression .. ", 10)"

-- Fish only spawn in nauvis territory (same fix as EverythingOnNauvis-Patches, which
-- masks off aquilo territory + vulcanus terrain; the nauvis territory mask also
-- covers gleba, so fish stay out of the wetlands/marshes too). Fish are restricted
-- to liquid tiles, so this only affects lakes/oceans on the combined map.
-- base expression is the literal 0.01 (gets string-coerced); eon_mask_nauvis_territory
-- is off-aquilo(off-gleba(off-vulcanus(expression)))
data.raw["fish"]["fish"].autoplace.probability_expression = "eon_mask_nauvis_territory(" .. data.raw["fish"]["fish"].autoplace.probability_expression .. ")"

-- Remove nauvis decoratives from eon_vulcano_coverage
terrain.mask_nauvis_territory("cracked-mud-decal", "optimized-decorative")
terrain.mask_nauvis_territory("dark-mud-decal", "optimized-decorative")
terrain.mask_nauvis_territory("lichen-decal", "optimized-decorative")
terrain.mask_nauvis_territory("shroom-decal", "optimized-decorative")
terrain.mask_nauvis_territory("light-mud-decal", "optimized-decorative")
terrain.mask_nauvis_territory("small-rock", "optimized-decorative")
terrain.mask_nauvis_territory("small-sand-rock", "optimized-decorative")
terrain.mask_nauvis_territory("tiny-rock", "optimized-decorative")

-- Remove nauvis decoratives from eon_vulcanus_terrain
terrain.mask_nauvis_territory("big-rock", "simple-entity")
terrain.mask_nauvis_territory("big-sand-rock", "simple-entity")
terrain.mask_nauvis_territory("brown-asterisk", "optimized-decorative")
terrain.mask_nauvis_territory("brown-asterisk-mini", "optimized-decorative")
terrain.mask_nauvis_territory("brown-carpet-grass", "optimized-decorative")
terrain.mask_nauvis_territory("brown-fluff", "optimized-decorative")
terrain.mask_nauvis_territory("brown-fluff-dry", "optimized-decorative")
terrain.mask_nauvis_territory("brown-hairy-grass", "optimized-decorative")
terrain.mask_nauvis_territory("garballo", "optimized-decorative")
terrain.mask_nauvis_territory("garballo-mini-dry", "optimized-decorative")
terrain.mask_nauvis_territory("green-asterisk", "optimized-decorative")
terrain.mask_nauvis_territory("green-asterisk-mini", "optimized-decorative")
terrain.mask_nauvis_territory("green-bush-mini", "optimized-decorative")
-- Grass tufts feather across the mixing band like the grass tiles they sit
-- on (same +10 threshold): full strength on Nauvis, fading into the Gleba
-- transition — not hard-cut at the line, never carpeting deep Gleba.
terrain.mask_nauvis_territory_fade("green-carpet-grass", "optimized-decorative", 0)
terrain.mask_nauvis_territory("green-croton", "optimized-decorative")
terrain.mask_nauvis_territory("green-desert-bush", "optimized-decorative")
terrain.mask_nauvis_territory_fade("green-hairy-grass", "optimized-decorative", 0)
terrain.mask_nauvis_territory("green-pita", "optimized-decorative")
terrain.mask_nauvis_territory("green-pita-mini", "optimized-decorative")
terrain.mask_nauvis_territory("green-small-grass", "optimized-decorative")
terrain.mask_nauvis_territory("huge-rock", "simple-entity")
terrain.mask_nauvis_territory("medium-rock", "optimized-decorative")
terrain.mask_nauvis_territory("medium-sand-rock", "optimized-decorative")
terrain.mask_nauvis_territory("red-asterisk", "optimized-decorative")
terrain.mask_nauvis_territory("red-croton", "optimized-decorative")
terrain.mask_nauvis_territory("red-desert-bush", "optimized-decorative")
terrain.mask_nauvis_territory("red-desert-decal", "optimized-decorative")
terrain.mask_nauvis_territory("red-pita", "optimized-decorative")
terrain.mask_nauvis_territory("sand-decal", "optimized-decorative")
terrain.mask_nauvis_territory("sand-dune-decal", "optimized-decorative")
terrain.mask_nauvis_territory("white-desert-bush", "optimized-decorative")

-- Remove nauvis tiles across the mixing band: dry sand dies first (north),
-- dirt in the middle; grass ends with the rest at the water line — no deep
-- wet fringe interleave with Gleba wetlands (twice-complained overlap).
terrain.mask_nauvis_deep("grass-1", "tile", 10)
terrain.mask_nauvis_deep("grass-2", "tile", 10)
terrain.mask_nauvis_deep("grass-3", "tile", 10)
terrain.mask_nauvis_deep("grass-4", "tile", 10)
-- Mesic dirt ends where wetlands begin (clean handoff, no dirt-on-swamp).
terrain.mask_nauvis_deep("dry-dirt", "tile", 10)
terrain.mask_nauvis_deep("dirt-1", "tile", 10)
terrain.mask_nauvis_deep("dirt-2", "tile", 10)
terrain.mask_nauvis_deep("dirt-3", "tile", 10)
terrain.mask_nauvis_deep("dirt-4", "tile", 10)
terrain.mask_nauvis_deep("dirt-5", "tile", 10)
terrain.mask_nauvis_deep("dirt-6", "tile", 10)
terrain.mask_nauvis_deep("dirt-7", "tile", 10)
terrain.mask_nauvis_deep("sand-1", "tile", -20)
terrain.mask_nauvis_deep("sand-2", "tile", -20)
terrain.mask_nauvis_deep("sand-3", "tile", -20)
terrain.mask_nauvis_deep("red-desert-0", "tile", -20)
terrain.mask_nauvis_deep("red-desert-1", "tile", -20)
terrain.mask_nauvis_deep("red-desert-2", "tile", -20)
terrain.mask_nauvis_deep("red-desert-3", "tile", -20)
-- terrain.mask_nauvis_territory("water", "tile")
-- terrain.mask_nauvis_territory("deepwater", "tile")
-- END: Mask nauvis territory on all autoplace settings

-- Remove nauvis cliffs from eon_vulcanus_terrain
data.raw["noise-expression"]["cliffiness_nauvis"].expression = "eon_mask_off_aquilo_territory(eon_mask_off_vulcano_terrain((main_cliffiness >= cliff_cutoff) * 10))"

data:extend({
  -- Noise expressions
  {
    -- Fix water coverage
    type = "noise-expression",
    name = "eon_updated_water",
    expression = "eon_mask_nauvis_territory(eon_water_base(0, 100) + eon_gleba_region(-100))"
  },
  {
    -- Fix deepwater coverage
    type = "noise-expression",
    name = "eon_updated_deepwater",
    expression = "eon_mask_nauvis_territory(eon_water_base(-2, 200))"
  },
  {
    -- region for nauvis resources to spawn
    type = "noise-expression",
    name = "eon_resource_territory",
    expression = "eon_aquilo_base(eon_aquilo_ammonia_depth + 2, 200)"
  },

  -- Noise functions
  {
    -- Mask all nauvis territory
    type = "noise-function",
    name = "eon_mask_nauvis_territory",
    parameters = {"expression"},
    expression = "eon_mask_off_aquilo_territory(eon_mask_off_gleba_territory(eon_mask_off_vulcano_terrain(expression)))"
  },
  {
    -- Mask all nauvis territory
    type = "noise-function",
    name = "eon_mask_off_nauvis_territory",
    parameters = {"expression"},
    expression = "if(eon_mask_nauvis_territory(expression) < 0, expression, -inf)"
  },
  {
    -- Mask resource territory
    type = "noise-function",
    name = "eon_mask_resource_territory",
    parameters = {"expression"},
    expression = "if(eon_resource_territory <= 0, expression, -inf)"
  },
})

--------------------------------------------------------------------------------
-- MARK: Fix Aquilo related map gen settings
--------------------------------------------------------------------------------

-- START: Update map gen settings
-- autoplace_controls
data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["lithium_brine"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["fluorine_vent"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["ammonia_ocean"] = {}

-- tile settings
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["snow-flat"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["snow-crests"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["snow-lumpy"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["snow-patchy"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["ice-rough"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["ice-smooth"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["brash-ice"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["ammoniacal-ocean"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["ammoniacal-ocean-2"] = {}

-- decorative settings
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["lithium-iceberg-medium"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["lithium-iceberg-small"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["lithium-iceberg-tiny"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["floating-iceberg-large"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["floating-iceberg-small"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["aqulio-ice-decal-blue"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["aqulio-snowy-decal"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["snow-drift-decal"] = {}

-- entity settings
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["lithium-brine"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["fluorine-vent"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["lithium-iceberg-huge"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["lithium-iceberg-big"] = {}
-- END: Update map gen settings

-- START: Mask aquilo territory on all autoplace settings
-- mask aquilo resources
terrain.mask_aquilo_territory("lithium-brine", "resource")
terrain.mask_aquilo_territory("fluorine-vent", "resource")

-- mask aquilo tiles (all guarded off volcanoes further down, in
-- "Update noise expressions": snow-flat and the ice/ammonia variants use the
-- custom land/ocean fields there, the snow variants their vanilla snapshots)
-- terrain.mask_aquilo_territory("snow-flat", "tile")
-- terrain.mask_aquilo_territory("ice-rough", "tile")
-- terrain.mask_aquilo_territory("ice-smooth", "tile")
-- terrain.mask_aquilo_territory("brash-ice", "tile")

-- mask aquilo decoratives (feathered past the territory edge: bergs and drifts
-- onto northern land, floaters onto Nauvis water; narrow bands with falloff)
terrain.mask_aquilo_land_early("lithium-iceberg-medium", "optimized-decorative", 1.5)
terrain.mask_aquilo_land_early("lithium-iceberg-small", "optimized-decorative", 1.5)
terrain.mask_aquilo_land_early("lithium-iceberg-tiny", "optimized-decorative", 1.5)
terrain.mask_aquilo_water_early("floating-iceberg-large", "optimized-decorative", 2)
terrain.mask_aquilo_water_early("floating-iceberg-small", "optimized-decorative", 2)
terrain.mask_aquilo_land_early("aqulio-ice-decal-blue", "optimized-decorative", 1.5)
terrain.mask_aquilo_land_early("aqulio-snowy-decal", "optimized-decorative", 1.5)
terrain.mask_aquilo_land_early("snow-drift-decal", "optimized-decorative", 1.5)

-- mask aquilo entities (never onto volcanoes: the land_early guard handles it)
terrain.mask_aquilo_land_early("lithium-iceberg-huge", "simple-entity", 1.5)
terrain.mask_aquilo_land_early("lithium-iceberg-big", "simple-entity", 1.5)

-- Aquilo decoratives feather onto volcano rims, but only on the aquilo side:
-- gated by the same territory mask the tiles use (eon_aquilo_mask), so ice and
-- bergs stay off volcano rims everywhere south of the boundary (Gleba, Vulcanus,
-- Nauvis mid-band) and ornament only northern rims. Band-gated on spots 0.2-0.55
-- with depth falloff, so the volcano edge on the aquilo side reads as progression.
for _, name in pairs({
  "lithium-iceberg-medium", "lithium-iceberg-small", "lithium-iceberg-tiny",
  "floating-iceberg-large", "floating-iceberg-small",
  "aqulio-ice-decal-blue", "aqulio-snowy-decal", "snow-drift-decal",
}) do
  local current = data.raw["optimized-decorative"][name].autoplace.probability_expression
  local snap = data_util.generate_eon_name(name)
  data.raw["optimized-decorative"][name].autoplace.probability_expression =
      "if(eon_mountain_volcano_spots > 0.55, -inf, max((" .. current .. "), if(eon_mountain_volcano_spots > 0.2, 4 * eon_mask_aquilo_territory(" .. snap .. " * clamp((0.55 - eon_mountain_volcano_spots) / 0.35, 0.25, 1)), -inf)))"
end
-- END: Mask aquilo territory on all autoplace settings

-- START: Update noise expressions
-- Volcano guard: no ice/snow/ammonia on ANY volcanic ground. Guards the whole
-- volcano mask (coverage + folds ring + their soft-edged rims) instead of a
-- spot threshold, so the outermost rim — where volcanic-folds-flat goes faint
-- but is still positive — stays volcanic too. Volcano beats Aquilo, full stop.
local eon_aquilo_volcano_guard = "if(eon_vulcanus_terrain, -inf, "
data.raw.tile["ammoniacal-ocean"].autoplace.probability_expression = eon_aquilo_volcano_guard .. "eon_mask_aquilo_territory(eon_aquilo_ammonia + 0.01 * (aux - 0.5)))"
data.raw.tile["ammoniacal-ocean-2"].autoplace.probability_expression = eon_aquilo_volcano_guard .. "eon_mask_aquilo_territory(eon_aquilo_ammonia - 0.01 * (aux - 0.5)))"

data.raw.tile["snow-flat"].autoplace.probability_expression = eon_aquilo_volcano_guard .. "eon_mask_aquilo_territory(eon_aquilo_land))"
data.raw.tile["snow-crests"].autoplace.probability_expression = eon_aquilo_volcano_guard .. "eon_mask_aquilo_territory(eon_snow_crests))"
data.raw.tile["snow-lumpy"].autoplace.probability_expression = eon_aquilo_volcano_guard .. "eon_mask_aquilo_territory(eon_snow_lumpy))"
data.raw.tile["snow-patchy"].autoplace.probability_expression = eon_aquilo_volcano_guard .. "eon_mask_aquilo_territory(eon_snow_patchy))"
data.raw.tile["ice-rough"].autoplace.probability_expression = eon_aquilo_volcano_guard .. "eon_mask_aquilo_territory(eon_aquilo_base(eon_aquilo_ammonia_depth + 1.5, 200)))"
data.raw.tile["ice-smooth"].autoplace.probability_expression = eon_aquilo_volcano_guard .. "eon_mask_aquilo_territory(eon_aquilo_base(eon_aquilo_ammonia_depth + 1, 200)))"
data.raw.tile["brash-ice"].autoplace.probability_expression = eon_aquilo_volcano_guard .. "eon_mask_aquilo_territory(eon_aquilo_base(eon_aquilo_ammonia_depth + 0.5, 200)))"
-- END: Update noise expressions

data:extend({
  {
    type = "autoplace-control",
    name = "ammonia_ocean",
    localised_description = {"autoplace-control-names.ammonia_ocean_description"},
    order = "z-ammonia",
    category = "resource",
    can_be_disabled = false
  },
})

-- New noise expressions and noise functions
data:extend({
  {
    -- Create mask for aquilo territory
    type = "noise-expression",
    name = "eon_aquilo_mask",
    expression = "eon_aquilo_land > -1",
  },
  {
    -- Create mask for aquilo territory
    type = "noise-expression",
    name = "eon_ammonia_mask",
    expression = "eon_aquilo_ammonia > -1",
  },
  {
    type = "noise-expression",
    name = "eon_aquilo_land",
    expression = "eon_mask_off_vulcano_coverage(eon_aquilo_base(eon_aquilo_max_elevation, 100))"
  },
  {
    type = "noise-expression",
    name = "eon_aquilo_max_elevation",
    expression = "-1"
  },
  {
    type = "noise-expression",
    name = "eon_aquilo_ammonia",
    expression = "eon_mask_off_vulcano_coverage(eon_aquilo_base(eon_aquilo_ammonia_depth, 200))"
  },
  {
    type = "noise-expression",
    name = "eon_aquilo_ammonia_depth",
    expression = "eon_aquilo_max_elevation - 4"
  },
  {
    type = "noise-expression",
    name = "eon_elevation_aquilo",
    expression = "if(wlc_elevation > eon_factorio_base_aquilo_elevation, wlc_elevation, min(eon_factorio_base_aquilo_elevation, -1.1))",
    local_expressions =
    {
      elevation_magnitude = 20,
      wlc_amplitude = 2,
      ammonia_level = "10 * log2(control:ammonia_ocean:size)",
      wlc_elevation = "max(aquilo_main - ammonia_level * wlc_amplitude, starting_island, north_bias)",
      aquilo_main = "elevation_magnitude * (0.25 * eon_aquilo_detail + 3 * eon_aquilo_macro * starting_macro_multiplier)",
      -- if most of the world is flooded make sure starting areas still have land
      starting_island = "aquilo_main + elevation_magnitude * (2.5 - distance * segmentation_multiplier / 200)",
      starting_macro_multiplier = "clamp(distance * eon_aquilo_segmentation_multiplier / 2000, 0, 1)",
      north_bias = "aquilo_main + elevation_magnitude * (2 + y * segmentation_multiplier / 500)",
    }
  },
  {
    type = "noise-expression",
    name = "eon_factorio_base_aquilo_elevation",
    --intended_property = "elevation",
    expression = "lerp(blended, maxed, 0.4)",
    local_expressions = {
      maxed = "max(formation_clumped, formation_broken)",
      blended = "lerp(formation_clumped, formation_broken, 0.4)",
      formation_clumped = "-25\z
                          + 12 * max(aquilo_island_peaks, random_island_peaks)\z
                          + 15 * tri_crack",
      formation_broken  = "-20\z
                          + 8 * max(aquilo_island_peaks * 1.1, min(0., random_island_peaks - 0.2))\z
                          + 13 * (pow(voronoi_large * max(0, voronoi_large_cell * 1.2 - 0.2) + 0.5 * voronoi_small * max(0, aux + 0.1), 0.5))",
      random_island_peaks = "abs(amplitude_corrected_multioctave_noise{x = x,\z
                                                                  y = y,\z
                                                                  seed0 = map_seed,\z
                                                                  seed1 = 1000,\z
                                                                  input_scale = segmentation_mult / 1.2,\z
                                                                  offset_x = -10000,\z
                                                                  octaves = 6,\z
                                                                  persistence = 0.8,\z
                                                                  amplitude = 1})",
      voronoi_large = "voronoi_facet_noise{   x = x + aquilo_wobble_x * 2,\z
                                              y = y + aquilo_wobble_y * 2,\z
                                              seed0 = map_seed,\z
                                              seed1 = 'aquilo-cracks',\z
                                              grid_size = 24,\z
                                              distance_type = 'euclidean',\z
                                              jitter = 1}",
      voronoi_large_cell = "voronoi_cell_id{  x = x + aquilo_wobble_x * 2,\z
                                              y = y + aquilo_wobble_y * 2,\z
                                              seed0 = map_seed,\z
                                              seed1 = 'aquilo-cracks',\z
                                              grid_size = 24,\z
                                              distance_type = 'euclidean',\z
                                              jitter = 1}",
      voronoi_small  = "voronoi_facet_noise{   x = x + aquilo_wobble_x * 2,\z
                                              y = y + aquilo_wobble_y * 2,\z
                                              seed0 = map_seed,\z
                                              seed1 = 'aquilo-cracks',\z
                                              grid_size = 10,\z
                                              distance_type = 'euclidean',\z
                                              jitter = 1}",
      tri_crack = "min(aquilo_simple_billows{seed1 = 2000, octaves = 3, input_scale = segmentation_mult / 1.5},\z
                       aquilo_simple_billows{seed1 = 3000, octaves = 3, input_scale = segmentation_mult / 1.2},\z
                       aquilo_simple_billows{seed1 = 4000, octaves = 3, input_scale = segmentation_mult})",
      segmentation_mult = "eon_aquilo_segmentation_multiplier / 25",
    }
  },
  {
    type = "noise-expression",
    name = "eon_aquilo_detail", -- the small scale details with variable persistance for a mix of smooth and jagged coastline
    expression = "variable_persistence_multioctave_noise{x = x,\z
                                                         y = y,\z
                                                         seed0 = map_seed + 1,\z
                                                         seed1 = 600,\z
                                                         input_scale = eon_aquilo_segmentation_multiplier / 14,\z
                                                         output_scale = 0.03,\z
                                                         offset_x = 10000 / eon_aquilo_segmentation_multiplier,\z
                                                         octaves = 5,\z
                                                         persistence = eon_aquilo_persistance}"
  },
  {
    type = "noise-expression",
    name = "eon_aquilo_segmentation_multiplier",
    expression = "0.5 * control:ammonia_ocean:frequency"
  },
  {
    type = "noise-expression",
    name = "eon_aquilo_persistance",
    expression = "clamp(amplitude_corrected_multioctave_noise{x = x,\z
                                                              y = y,\z
                                                              seed0 = map_seed + 1,\z
                                                              seed1 = 500,\z
                                                              octaves = 5,\z
                                                              input_scale = eon_aquilo_segmentation_multiplier / 2,\z
                                                              offset_x = 10000 / eon_aquilo_segmentation_multiplier,\z
                                                              persistence = 0.7,\z
                                                              amplitude = 0.5} + 0.55,\z
                        0.5, 0.65)"
  },
  {
    type = "noise-expression",
    name = "eon_aquilo_macro",
    expression = "multioctave_noise{x = x,\z
                                    y = y,\z
                                    persistence = 0.6,\z
                                    seed0 = map_seed + 1,\z
                                    seed1 = 1000,\z
                                    octaves = 2,\z
                                    input_scale = eon_aquilo_segmentation_multiplier / 1600}\z
                  * max(0, multioctave_noise{x = x,\z
                                    y = y,\z
                                    persistence = 0.6,\z
                                    seed0 = map_seed + 1,\z
                                    seed1 = 1100,\z
                                    octaves = 1,\z
                                    input_scale = eon_aquilo_segmentation_multiplier / 1600})",
  },

  -- Noise functions
  {
    -- aquilo lakes
    type = "noise-function",
    name = "eon_aquilo_base",
    parameters = {"max_elevation", "influence"},
    expression = "if(max_elevation >= eon_elevation_aquilo, influence * min(max_elevation - eon_elevation_aquilo, 1), -inf)"
  },
  {
    -- Mask all aquilo territory
    type = "noise-function",
    name = "eon_mask_aquilo_territory",
    parameters = {"expression"},
    expression = "if(eon_aquilo_mask, expression, -inf)"
  },
  {
    -- Mask off all aquilo territory
    type = "noise-function",
    name = "eon_mask_off_aquilo_territory",
    parameters = {"expression"},
    expression = "if(eon_aquilo_mask, -inf, expression)"
  },
  {
    -- Mask all ammonia ocean territory
    type = "noise-function",
    name = "eon_mask_ammonia_ocean",
    parameters = {"expression"},
    expression = "if(eon_ammonia_mask, expression, -inf)"
  },
  {
    -- Mask off all ammonia ocean territory
    type = "noise-function",
    name = "eon_mask_off_ammonia_ocean",
    parameters = {"expression"},
    expression = "if(eon_ammonia_mask, -inf, expression)"
  },
  {
    -- Aquilo natives blend onto northern land: same eon_fade over the
    -- raised-ceiling base field (negated so it grows INTO the shore band),
    -- floored at 0.3, off-gleba/off-volcano guards keep them out of
    -- southern wetlands and off volcanoes.
    type = "noise-function",
    name = "eon_mask_aquilo_land_early",
    parameters = {"expression", "reach"},
    expression = "eon_mask_off_vulcano_terrain(eon_mask_off_gleba_territory(eon_fade(expression, -eon_aquilo_base(eon_aquilo_max_elevation + reach, 100), -30, 0, 0.3)))"
  },
  {
    type = "noise-function",
    name = "eon_mask_aquilo_water_early",
    parameters = {"expression", "reach"},
    expression = "eon_mask_off_vulcano_terrain(eon_mask_off_gleba_territory(eon_fade(expression, -eon_aquilo_base(eon_aquilo_ammonia_depth + reach, 200), -60, 0, 0.3)))"
  },
})

--------------------------------------------------------------------------------
-- MARK: Fix Gleba related map gen settings
--------------------------------------------------------------------------------

-- START: Update map gen settings
-- autoplace_controls
-- Explicit 1/1/1: an empty table leaves frequency/size to resolve as 0 on
-- Nauvis, which flattens every gleba_water-frequency-driven field to a
-- constant (tri_ridge, peaks terraces) and erases all basins/oceans.
data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["gleba_plants"] = { frequency = 1, size = 1, richness = 1 }
data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["gleba_water"] = { frequency = 1, size = 1, richness = 1 }

-- tile settings
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["natural-yumako-soil"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["natural-jellynut-soil"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-yumako"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-jellynut"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-blue-slime"] = {}  -- gleba water (unlisted tiles never place)
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-light-green-slime"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-green-slime"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-light-dead-skin"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-dead-skin"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-pink-tentacle"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-red-tentacle"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["gleba-deep-lake"] = {}  -- gleba water (unlisted tiles never place)
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-brown-blubber"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-olive-blubber"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-olive-blubber-2"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-olive-blubber-2"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-pale-green"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-cream-cauliflower"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-cream-cauliflower-2"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-dead-skin"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-dead-skin-2"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-cream-red"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-red-vein"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-red-vein-2"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-red-vein-3"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-red-vein-4"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-red-vein-dead"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lowland-red-infection"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["midland-turquoise-bark"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["midland-turquoise-bark-2"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["midland-cracked-lichen"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["midland-cracked-lichen-dull"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["midland-cracked-lichen-dark"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["midland-yellow-crust"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["midland-yellow-crust-2"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["midland-yellow-crust-3"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["midland-yellow-crust-4"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["highland-dark-rock"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["highland-dark-rock-2"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["highland-yellow-rock"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["pit-rock"] = {}

-- decorative settings
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["yellow-lettuce-lichen-1x1"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["yellow-lettuce-lichen-3x3"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["yellow-lettuce-lichen-6x6"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["yellow-lettuce-lichen-cups-1x1"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["yellow-lettuce-lichen-cups-3x3"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["yellow-lettuce-lichen-cups-6x6"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["green-lettuce-lichen-1x1"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["green-lettuce-lichen-3x3"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["green-lettuce-lichen-6x6"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["green-lettuce-lichen-water-1x1"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["green-lettuce-lichen-water-3x3"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["green-lettuce-lichen-water-6x6"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["split-gill-1x1"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["split-gill-2x2"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["split-gill-dying-1x1"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["split-gill-dying-2x2"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["split-gill-red-1x1"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["split-gill-red-2x2"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["veins"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["veins-small"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["mycelium"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["coral-water"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["coral-land"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["black-sceptre"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["pink-phalanges"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["pink-lichen-decal"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["red-lichen-decal"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["green-cup"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["brown-cup"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["blood-grape"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["blood-grape-vibrant"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["brambles"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["polycephalum-slime"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["polycephalum-balloon"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["fuchsia-pita"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["wispy-lichen"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["grey-cracked-mud-decal"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["barnacles-decal"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["coral-stunted"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["coral-stunted-grey"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["nerve-roots-dense"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["nerve-roots-sparse"] = {}
-- data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["nerve-roots-veins-dense"] = {}
-- data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["nerve-roots-veins-sparse"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["yellow-coral"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["solo-barnacle"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["curly-roots-orange"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["knobbly-roots"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["knobbly-roots-orange"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["matches-small"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["pale-lettuce-lichen-cups-1x1"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["pale-lettuce-lichen-cups-3x3"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["pale-lettuce-lichen-cups-6x6"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["pale-lettuce-lichen-1x1"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["pale-lettuce-lichen-3x3"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["pale-lettuce-lichen-6x6"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["pale-lettuce-lichen-water-1x1"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["pale-lettuce-lichen-water-3x3"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["pale-lettuce-lichen-water-6x6"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["white-carpet-grass"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["green-carpet-grass"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["green-hairy-grass"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["light-mud-decal"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["dark-mud-decal"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["cracked-mud-decal"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["red-desert-bush"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["white-desert-bush"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["red-pita"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["green-bush-mini"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["green-croton"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["green-pita"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["green-pita-mini"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["lichen-decal"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["shroom-decal"] = {}

if not mods["Spaghetorio"] then
  data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["honeycomb-fungus"] = {}
  data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["honeycomb-fungus-1x1"] = {}
  data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["honeycomb-fungus-decayed"] = {}
end

-- entity settings
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["iron-stromatolite"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["copper-stromatolite"] = {}
-- END: Update map gen settings

-- START: Mask gleba territory on all autoplace settings
-- mask gleba tiles
terrain.mask_gleba_territory("natural-yumako-soil", "tile")
terrain.mask_gleba_territory("natural-jellynut-soil", "tile")
terrain.mask_gleba_territory("wetland-yumako", "tile")
terrain.mask_gleba_territory("wetland-jellynut", "tile")
terrain.mask_gleba_water("wetland-blue-slime", "tile")
terrain.mask_gleba_water("gleba-deep-lake", "tile")
-- Non-fruit wetlands stay vanilla verbatim (territory mask only): the
-- elevation gate thinned exactly the rockpool-driven wetlands vanilla is
-- supposed to have, leaving midland stranded inside marshes.
terrain.mask_gleba_territory("wetland-light-green-slime", "tile")
terrain.mask_gleba_territory("wetland-green-slime", "tile")
terrain.mask_gleba_territory("wetland-light-dead-skin", "tile")
terrain.mask_gleba_territory("wetland-dead-skin", "tile")
terrain.mask_gleba_territory("wetland-pink-tentacle", "tile")
terrain.mask_gleba_territory("wetland-red-tentacle", "tile")
terrain.mask_gleba_territory("lowland-brown-blubber", "tile")
terrain.mask_gleba_territory("lowland-olive-blubber", "tile")
terrain.mask_gleba_territory("lowland-olive-blubber-2", "tile")
terrain.mask_gleba_territory("lowland-olive-blubber-2", "tile")
terrain.mask_gleba_territory("lowland-pale-green", "tile")
terrain.mask_gleba_territory("lowland-cream-cauliflower", "tile")
terrain.mask_gleba_territory("lowland-cream-cauliflower-2", "tile")
terrain.mask_gleba_territory("lowland-dead-skin", "tile")
terrain.mask_gleba_territory("lowland-dead-skin-2", "tile")
terrain.mask_gleba_territory("lowland-cream-red", "tile")
terrain.mask_gleba_territory("lowland-red-vein", "tile")
terrain.mask_gleba_territory("lowland-red-vein-2", "tile")
terrain.mask_gleba_territory("lowland-red-vein-3", "tile")
terrain.mask_gleba_territory("lowland-red-vein-4", "tile")
terrain.mask_gleba_territory("lowland-red-vein-dead", "tile")
terrain.mask_gleba_territory("lowland-red-infection", "tile")
-- Dry high ground fingers furthest north into Nauvis; wet lowland and
-- wetlands start at the line; water leads it (see water mask, -10).
terrain.mask_gleba_early("midland-turquoise-bark", "tile", -35)
terrain.mask_gleba_early("midland-turquoise-bark-2", "tile", -35)
terrain.mask_gleba_early("midland-cracked-lichen", "tile", -35)
terrain.mask_gleba_early("midland-cracked-lichen-dull", "tile", -35)
terrain.mask_gleba_early("midland-cracked-lichen-dark", "tile", -35)
terrain.mask_gleba_early("midland-yellow-crust", "tile", -35)
terrain.mask_gleba_early("midland-yellow-crust-2", "tile", -35)
terrain.mask_gleba_early("midland-yellow-crust-3", "tile", -35)
terrain.mask_gleba_early("midland-yellow-crust-4", "tile", -35)
terrain.mask_gleba_early("highland-dark-rock", "tile", -70)
terrain.mask_gleba_early("highland-dark-rock-2", "tile", -70)
terrain.mask_gleba_early("highland-yellow-rock", "tile", -70)
terrain.mask_gleba_early("pit-rock", "tile", -35)

-- Decor-first transition: these water plants lead the tile line by ~50
-- tiles so shores feather instead of cutting, using the gleba _fade helper
-- (smooth northward blend, see the leaders loop at the end of this file).
-- None are collision-blocked on deepwater (only green/brown-cup are, and
-- those stay put).
terrain.mask_gleba_territory("yellow-lettuce-lichen-1x1", "optimized-decorative")
terrain.mask_gleba_territory("yellow-lettuce-lichen-3x3", "optimized-decorative")
terrain.mask_gleba_territory("yellow-lettuce-lichen-6x6", "optimized-decorative")
terrain.mask_gleba_territory("green-lettuce-lichen-1x1", "optimized-decorative")
terrain.mask_gleba_territory("green-lettuce-lichen-3x3", "optimized-decorative")
terrain.mask_gleba_territory("green-lettuce-lichen-6x6", "optimized-decorative")
terrain.mask_gleba_territory("green-lettuce-lichen-water-1x1", "optimized-decorative")
terrain.mask_gleba_territory("green-lettuce-lichen-water-3x3", "optimized-decorative")
terrain.mask_gleba_territory("green-lettuce-lichen-water-6x6", "optimized-decorative")
terrain.mask_gleba_territory("split-gill-1x1", "optimized-decorative")
terrain.mask_gleba_territory("split-gill-2x2", "optimized-decorative")
terrain.mask_gleba_territory("split-gill-dying-1x1", "optimized-decorative")
terrain.mask_gleba_territory("split-gill-dying-2x2", "optimized-decorative")
terrain.mask_gleba_territory("split-gill-red-1x1", "optimized-decorative")
terrain.mask_gleba_territory("split-gill-red-2x2", "optimized-decorative")
terrain.mask_gleba_territory("veins", "optimized-decorative")
terrain.mask_gleba_territory("veins-small", "optimized-decorative")
terrain.mask_gleba_territory("mycelium", "optimized-decorative")
terrain.mask_gleba_territory("coral-land", "optimized-decorative")
terrain.mask_gleba_territory("black-sceptre", "optimized-decorative")
terrain.mask_gleba_territory("pink-phalanges", "optimized-decorative")
terrain.mask_gleba_territory("pink-lichen-decal", "optimized-decorative")
terrain.mask_gleba_territory("red-lichen-decal", "optimized-decorative")
terrain.mask_gleba_territory("green-cup", "optimized-decorative")
terrain.mask_gleba_territory("brown-cup", "optimized-decorative")
terrain.mask_gleba_territory("blood-grape", "optimized-decorative")
terrain.mask_gleba_territory("blood-grape-vibrant", "optimized-decorative")
terrain.mask_gleba_territory("brambles", "optimized-decorative")
terrain.mask_gleba_territory("polycephalum-slime", "optimized-decorative")
terrain.mask_gleba_territory("polycephalum-balloon", "optimized-decorative")
terrain.mask_gleba_territory("fuchsia-pita", "optimized-decorative")
terrain.mask_gleba_territory("wispy-lichen", "optimized-decorative")
terrain.mask_gleba_territory("grey-cracked-mud-decal", "optimized-decorative")
terrain.mask_gleba_territory("barnacles-decal", "optimized-decorative")
terrain.mask_gleba_territory("coral-stunted", "optimized-decorative")
terrain.mask_gleba_territory("coral-stunted-grey", "optimized-decorative")
terrain.mask_gleba_territory("nerve-roots-dense", "optimized-decorative")
terrain.mask_gleba_territory("nerve-roots-sparse", "optimized-decorative")
-- terrain.mask_gleba_territory("nerve-roots-veins-dense", "optimized-decorative")
-- terrain.mask_gleba_territory("nerve-roots-veins-sparse", "optimized-decorative")
terrain.mask_gleba_territory("yellow-coral", "optimized-decorative")
terrain.mask_gleba_territory("solo-barnacle", "optimized-decorative")
terrain.mask_gleba_territory("curly-roots-orange", "optimized-decorative")
terrain.mask_gleba_territory("knobbly-roots", "optimized-decorative")
terrain.mask_gleba_territory("knobbly-roots-orange", "optimized-decorative")
terrain.mask_gleba_territory("matches-small", "optimized-decorative")
terrain.mask_gleba_territory("pale-lettuce-lichen-cups-1x1", "optimized-decorative")
terrain.mask_gleba_territory("pale-lettuce-lichen-cups-3x3", "optimized-decorative")
terrain.mask_gleba_territory("pale-lettuce-lichen-cups-6x6", "optimized-decorative")
terrain.mask_gleba_territory("pale-lettuce-lichen-1x1", "optimized-decorative")
terrain.mask_gleba_territory("pale-lettuce-lichen-3x3", "optimized-decorative")
terrain.mask_gleba_territory("pale-lettuce-lichen-6x6", "optimized-decorative")
terrain.mask_gleba_territory("pale-lettuce-lichen-water-1x1", "optimized-decorative")
terrain.mask_gleba_territory("pale-lettuce-lichen-water-3x3", "optimized-decorative")
terrain.mask_gleba_territory("pale-lettuce-lichen-water-6x6", "optimized-decorative")
-- white-carpet-grass is a native Gleba decorative; the green carpet/hairy
-- grasses are Nauvis-native and ride the mixing-band fade in the Nauvis
-- section above. They used to be gleba-confined here, which carpeted all of
-- Gleba territory with Nauvis grass (not native, reported bug).
-- white-carpet-grass is a native Gleba decorative (so is fuchsia-pita; the
-- green/red pitas, crotons, bushes, desert bushes and mud/lichen/shroom
-- decals were also gleba-confined here but are Nauvis natives — same bug
-- class as the grass: copied tiers of Nauvis flora carpeting Gleba).
-- Natives stay gleba-masked; non-natives keep the mask_nauvis_territory they
-- got in the Nauvis section above (upstream-style hard masks, no rim loop).
terrain.mask_gleba_territory("white-carpet-grass", "optimized-decorative")

-- mask gleba entities
terrain.mask_gleba_territory("iron-stromatolite", "simple-entity")
terrain.mask_gleba_territory("copper-stromatolite", "simple-entity")

-- Gleba trees reach north with the midland shelf.
terrain.mask_gleba_early("cuttlepop", "tree", -35)
terrain.mask_gleba_early("slipstack", "tree", -35)
terrain.mask_gleba_early("funneltrunk", "tree", -35)
terrain.mask_gleba_early("hairyclubnub", "tree", -35)
terrain.mask_gleba_early("teflilly", "tree", -35)
terrain.mask_gleba_early("lickmaw", "tree", -35)
terrain.mask_gleba_early("stingfrond", "tree", -35)
terrain.mask_gleba_early("boompuff", "tree", -35)
terrain.mask_gleba_early("sunnycomb", "tree", -35)
-- Water-cane feathers instead of banding: density scales up across the
-- handoff (present thinly in Nauvis deepwater north of the line, full in
-- Gleba shallows south), so no abrupt start/stop. Explicitly off volcano
-- terrain: vanilla keeps it out of lava on Gleba, but Nauvis lava sits in
-- mineable flank blobs where cane would otherwise strand.
data.raw["tree"]["water-cane"].autoplace.probability_expression = "eon_mask_off_vulcano_terrain(eon_water_cane) * clamp((eon_gleba_transition + 60) / 100, 0, 1)"

if not mods["Spaghetorio"] then
  terrain.mask_gleba_territory("honeycomb-fungus", "optimized-decorative")
  terrain.mask_gleba_territory("honeycomb-fungus-1x1", "optimized-decorative")
  terrain.mask_gleba_territory("honeycomb-fungus-decayed", "optimized-decorative")
end

-- Let named transition flora grow on deepwater: their doodad collision locks
-- them off water tiles in vanilla, so drop doodad (keep cliff, keep
-- no-self-collision) for just these. Tile-side opening put rocks and land
-- decor on every Nauvis lake, so this stays scoped to transition plants.
-- Masks still keep them out of volcanoes; probability still decides shores.
data.raw["optimized-decorative"]["red-pita"].collision_mask = {
  layers = {cliff = true},
  not_colliding_with_itself = true
}
if not mods["Spaghetorio"] then
  for _, name in pairs({"honeycomb-fungus", "honeycomb-fungus-1x1", "honeycomb-fungus-decayed"}) do
    data.raw["optimized-decorative"][name].collision_mask = {
      layers = {cliff = true},
      not_colliding_with_itself = true
    }
  end
end
-- END: Mask gleba territory on all autoplace settings

-- Update autoplace controls
data.raw["autoplace-control"]["gleba_plants"].can_be_disabled = true
data.raw["autoplace-control"]["gleba_water"].can_be_disabled = true

-- Scalar tuning knobs, overridable per map via property_expression_names
-- (e.g. map exchange string or console) without a mod restart.
data.raw.planet["nauvis"].map_gen_settings.property_expression_names["eon_gleba_south_offset"] = "eon_gleba_south_offset"

-- START: Update noise expressions
-- Mask gleba plants to gleba terrain (wrap the vanilla expressions by
-- variable: diverts from vanilla automatically, no re-typed copy text).
data.raw["noise-expression"]["gleba_plants_noise"].expression = "eon_mask_gleba_territory(" .. data.raw["noise-expression"]["gleba_plants_noise"].expression .. ")"
data.raw["noise-expression"]["gleba_plants_noise_b"].expression = "eon_mask_gleba_territory(" .. data.raw["noise-expression"]["gleba_plants_noise_b"].expression .. ")"
-- END: Update noise expressions

-- New noise expressions and noise functions
-- (The four fruit-tile probabilities are gleba-masked in the gleba section
-- above via mask_gleba_territory, which references the eon_* snapshots — no
-- re-typing of the vanilla text needed here or anywhere.)

-- Frontier "starting area": mirror vanilla's guaranteed yumako/jellynut
-- patches onto the land just below the transition (players arrive down the
-- x = 0 axis). Angles are degrees, 180 = south. Everything downstream
-- (wetlands, soils, even pentapod nesting via fertile spots) then behaves
-- exactly like vanilla's spawn: engineered pair up front, raw vanilla
-- provinces everywhere else, deep south regular Gleba, untouched.
data:extend({
  {
    type = "noise-expression",
    name = "eon_yumako_frontier",
    expression = "starting_spot_at_angle{angle = 180 + 12 * gleba_starting_direction,\z
                                             distance = eon_gleba_south_offset + 1100,\z
                                             radius = 30,\z
                                             x_distortion = gleba_wobble_x * 15,\z
                                             y_distortion = gleba_wobble_y * 15}"
  },
  {
    type = "noise-expression",
    name = "eon_jellynut_frontier",
    expression = "starting_spot_at_angle{angle = 180 - 12 * gleba_starting_direction,\z
                                             distance = eon_gleba_south_offset + 1100,\z
                                             radius = 30,\z
                                             x_distortion = gleba_wobble_x * 15,\z
                                             y_distortion = gleba_wobble_y * 15}"
  },
})
data.raw["noise-expression"]["gleba_starting_fertile"].expression = "max(eon_yumako_frontier, eon_jellynut_frontier) * gleba_above_deep_water_mask"

-- Frontier lowland bowls: vanilla sinks engineered lowland terrain under its
-- starting patches; vanilla's own lowland blend only reaches near origin, so
-- these twin bowls (same sites as the fertile patches, vanilla lowland radii)
-- sink the terrain in OUR elevation blend instead. Fruit sits in wet
-- clearings, never forced uphill; outside the bowls the elevation penalties
-- apply again, which keeps sprawl contained.
data:extend({
  {
    type = "noise-expression",
    name = "eon_yumako_bowl",
    expression = "starting_spot_at_angle{angle = 180 + 12 * gleba_starting_direction,\z
                                             distance = eon_gleba_south_offset + 1100,\z
                                             radius = 98,\z
                                             x_distortion = gleba_wobble_x * 15,\z
                                             y_distortion = gleba_wobble_y * 15}"
  },
  {
    type = "noise-expression",
    name = "eon_jellynut_bowl",
    expression = "starting_spot_at_angle{angle = 180 - 12 * gleba_starting_direction,\z
                                             distance = eon_gleba_south_offset + 1100,\z
                                             radius = 70,\z
                                             x_distortion = gleba_wobble_x * 15,\z
                                             y_distortion = gleba_wobble_y * 15}"
  },
})
-- (gleba_starting_lowlands itself stays vanilla: its blend weight is zero
-- out here, the bowls above do the shaping instead).

-- Correlate Gleba fields with Nauvis fields by shared meaning (see blend below).
-- `elevation` on Nauvis is NOT `gleba_elevation`: the property resolves per
-- planet, both expressions coexist globally. Deep south keeps pure vanilla
-- Gleba fields; across the band both tile systems read blended fields.
local function eon_copy_vanilla_field(name, copy_name)
  local src = data.raw["noise-expression"][name]
  local copy = {
    type = "noise-expression",
    name = copy_name,
    expression = src.expression
  }
  if src.local_expressions then copy.local_expressions = table.deepcopy(src.local_expressions) end
  if src.local_functions then copy.local_functions = table.deepcopy(src.local_functions) end
  return copy
end

data:extend({
  -- Noise functions
  {
    -- How many tiles south of the map center Gleba terrain starts.
    -- Overridable per map via Nauvis map-gen settings property_expression_names,
    -- so no mod restart is needed and it applies to newly generated chunks.
    type = "noise-expression",
    name = "eon_gleba_south_offset",
    expression = "1000"
  },
  {
    type = "noise-expression",
    name = "eon_gleba_mask",
    expression = "eon_gleba_region(0)"
  },

  -- Continuous transition value for the line (region) and backstop masks.
  -- The shape reads ONLY static Nauvis fields plus slow wobbles; it must not
  -- read the blended properties below, or the blend would feed into itself.
  {
    type = "noise-expression",
    name = "eon_gleba_wobble_large",
    -- Small on purpose: the line should follow real terrain (moisture/aux
    -- contours), free sine curves read as artificial wobbles.
    expression = "basis_noise{x = x,\z
                                   y = y,\z
                                   seed0 = map_seed,\z
                                   seed1 = 5,\z
                                   input_scale = var('control:gleba_plants:frequency') / 400,\z
                                   output_scale = 6}"
  },
  {
    type = "noise-expression",
    name = "eon_gleba_wobble_medium",
    expression = "basis_noise{x = x,\z
                                      y = y,\z
                                      seed0 = map_seed,\z
                                      seed1 = 6,\z
                                      input_scale = var('control:gleba_plants:frequency') / 150,\z
                                      output_scale = 3}"
  },
  {
    type = "noise-expression",
    name = "eon_gleba_transition",
    expression = "gleba_shape + south_offset",
    local_expressions = {
      gleba_shape = "eon_gleba_wobble_large + eon_gleba_wobble_medium + 30 * (moisture_nauvis - 0.5) + 15 * (aux_nauvis - 0.5)",
      y_offset = "y - eon_gleba_south_offset",  -- gleba starts around eon_gleba_south_offset tiles to the south
      -- Uncapped: grows ~0.1/tile forever south, so deep south is pure Gleba.
      -- (No Nauvis/biter gaps; deep-south enemies are a separate task and will
      -- come from Gleba-native spawners, which need no Nauvis ground.)
      south_offset = "y_offset / (1 + pow(2, 0.01 * y_offset)) + 0.1 * y_offset - 30"
    }
  },
  {
    -- Blend driver. Same curves as the line with the same uncapped ramp, so it
    -- saturates to 1: deep-south fields stay pure vanilla Gleba.
    type = "noise-expression",
    name = "eon_gleba_blend_input",
    expression = "gleba_shape + south_uncapped",
    local_expressions = {
      gleba_shape = "eon_gleba_wobble_large + eon_gleba_wobble_medium + 30 * (moisture_nauvis - 0.5) + 15 * (aux_nauvis - 0.5)",
      y_offset = "y - eon_gleba_south_offset",
      south_uncapped = "y_offset / (1 + pow(2, 0.01 * y_offset)) + 0.1 * y_offset - 30"
    }
  },
  {
    -- 0 north of the line, 1 deep south. Both tile systems read blended
    -- fields through this, so vanilla's own soft selects draw the boundary.
    type = "noise-expression",
    name = "eon_gleba_blend",
    expression = "t * t * (3 - 2 * t)",
    local_expressions = {
      t = "clamp(eon_gleba_blend_input / 120, 0, 1)"
    }
  },
  {
    -- Fast moisture twin for shoreline signals only: vanilla's water-plant
    -- ramp is steep because moisture tracks elevation steeply at shores; our
    -- slow morph flattened it into a plateau and grew dense bands instead of
    -- fringes. Same formula, sharper field. Plain moisture keeps the slow
    -- morph for the wide mixing.
    type = "noise-expression",
    name = "eon_moisture_fast",
    expression = "lerp(moisture_nauvis, eon_gleba_moisture_vanilla, eon_gleba_blend_fast)"
  },
  {
    -- Fast twin for elevation: water/shore/highland bands need crisp
    -- elevation (pit-rock lives above 20, wetlands below ~10 — a slow morph
    -- parks both in the middle and they end up side by side, which vanilla
    -- never does).
    type = "noise-expression",
    name = "eon_gleba_blend_fast",
    expression = "t * t * (3 - 2 * t)",
    local_expressions = {
      t = "clamp(eon_gleba_blend_input / 30, 0, 1)"
    }
  },
  eon_copy_vanilla_field("gleba_moisture", "eon_gleba_moisture_vanilla"),
  eon_copy_vanilla_field("gleba_aux", "eon_gleba_aux_vanilla"),
  eon_copy_vanilla_field("gleba_elevation", "eon_gleba_elevation_vanilla"),
  {
    -- Same 0..1 meaning both sides: wet north stays wet south.
    type = "noise-expression",
    name = "eon_moisture_blended",
    expression = "lerp(moisture_nauvis, eon_gleba_moisture_vanilla, eon_gleba_blend)"
  },
  {
    type = "noise-expression",
    name = "eon_aux_blended",
    expression = "lerp(lerp(base_blend_fast, 0.35, yumako_halo), 0.65, jelly_halo)",
    local_expressions =
    {
      base_blend_fast = "lerp(aux_nauvis, eon_gleba_aux_vanilla, eon_gleba_blend_fast)",
      -- Engineered aux near the frontier patches (vanilla does the same with
      -- starting_aux near spawn): guarantees the west patch grows yumako /
      -- copper and the east patch jellynut / iron instead of gambling on the
      -- province lottery. Stromatolites and decor follow automatically.
      yumako_halo = "clamp(eon_yumako_frontier * 1.1, 0, 1)",
      jelly_halo = "clamp(eon_jellynut_frontier * 1.1, 0, 1)"
    }
  },
  {
    -- One elevation morph for both readers: north is Nauvis ground (lakes and
    -- all), deep south is vanilla Gleba. Mid-band is the average, so a lake on
    -- either side stays a lake through the band instead of hitting a wall.
    -- Frontier bowls sink engineered lowland under the fruit patches (mirror
    -- of vanilla starting_lowlands, which only blends near origin and can't
    -- reach the frontier): fruit sits in wet clearings, never forced uphill.
    type = "noise-expression",
    name = "eon_elevation_blended",
    expression = "lerp(lerp(elevation_nauvis, eon_gleba_elevation_vanilla, eon_gleba_blend_fast), 5, bowl_mask)",
    local_expressions =
    {
      bowl_mask = "clamp(max(eon_yumako_bowl, eon_jellynut_bowl), 0, 1)"
    }
  },
  {
    type = "noise-function",
    name = "eon_gleba_region",
    parameters = {"threshold"},
    -- Full volcano terrain (including the outer folds-flat ring) takes
    -- precedence: Gleba never covers any volcano ground (aquilo > vulcanus
    -- > gleba > nauvis). Demolishers keep their whole volcano.
    expression = "eon_mask_off_vulcano_terrain(if(eon_gleba_transition > threshold, 1, 0))"
  },
  {
    -- Uncapped twin of the region: same curves, ramp grows forever south.
    -- Water uses this so southern lakes can never become Nauvis pockets.
    -- Like eon_gleba_region above, full volcano terrain (not just coverage)
    -- takes precedence, so volcanoes punch through southern oceans.
    type = "noise-function",
    name = "eon_gleba_region_deep",
    parameters = {"threshold"},
    expression = "eon_mask_off_vulcano_terrain(if(eon_gleba_blend_input > threshold, 1, 0))"
  },
  {
    -- Nauvis side of the mixing band: alive while transition < threshold.
    type = "noise-function",
    name = "eon_mask_nauvis_deep",
    parameters = {"expression", "threshold"},
    expression = "eon_mask_off_aquilo_territory(eon_mask_off_vulcano_terrain(if(eon_gleba_region(threshold), -inf, expression)))"
  },
  {
    -- Gleba side of the mixing band: alive once transition > threshold.
    type = "noise-function",
    name = "eon_mask_gleba_early",
    parameters = {"expression", "threshold"},
    expression = "if(eon_gleba_region(threshold), expression, -inf)"
  },
  {
    -- Mask all gleba territory
    type = "noise-function",
    name = "eon_mask_gleba_territory",
    parameters = {"expression"},
    expression = "if(eon_gleba_mask, expression, -inf)"
  },
  {
    -- Same water line the Nauvis tiles are cut at (region_deep(-10)), so
    -- oceans continue water-to-water instead of going dry at the border.
    -- Volcano priority over Gleba water comes from eon_gleba_region_deep,
    -- which masks off all volcano terrain like eon_gleba_region does.
    type = "noise-function",
    name = "eon_mask_gleba_water",
    parameters = {"expression"},
    expression = "if(eon_gleba_region_deep(-10), expression, -inf)"
  },
  {
    -- Mask off all gleba territory
    type = "noise-function",
    name = "eon_mask_off_gleba_territory",
    parameters = {"expression"},
    expression = "if(eon_gleba_mask, -inf, expression)"
  },
})

-- Point both tile systems at the blended fields. North of the band everything
-- resolves to pure Nauvis, deep south to pure vanilla Gleba; inside the band
-- one continuous landscape draws both, so vanilla's soft selects (not our
-- binary mask) shape the visible transition. Hard masks stay as backstop.
data.raw["noise-expression"]["gleba_moisture"].expression = "eon_moisture_blended"
-- Shoreline signal for the whole water-plant family (cane, shore plants,
-- lettuce, corals): identical formula, sharper field, so fringes stay
-- fringes on both sides of the handoff instead of banding.
data.raw["noise-expression"]["gleba_water_plant_ramp"].expression = "clamp((0.8 - eon_moisture_fast) * 20, 0, 1)"
data.raw["noise-expression"]["gleba_aux"].expression = "eon_aux_blended"
data.raw["noise-expression"]["gleba_aux"].local_expressions = nil
data.raw["noise-expression"]["gleba_elevation"].expression = "eon_elevation_blended"
data.raw["noise-expression"]["gleba_elevation"].local_expressions = nil
-- Southern oceans come from vanilla basins only (see tile allow-list fix).
-- An earlier workaround also keyed water to Nauvis elevation; that painted
-- slime on dry highland near shores and is removed.
data.raw.planet["nauvis"].map_gen_settings.property_expression_names["moisture"] = "eon_moisture_blended"
data.raw.planet["nauvis"].map_gen_settings.property_expression_names["aux"] = "eon_aux_blended"
data.raw.planet["nauvis"].map_gen_settings.property_expression_names["elevation"] = "eon_elevation_blended"

--------------------------------------------------------------------------------
-- MARK: Fix Vulcanus related map gen settings
--------------------------------------------------------------------------------

-- START: Update map gen settings
-- autoplace_controls
data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["vulcanus_volcanism"] = {}

-- tile settings
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["volcanic-folds"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["volcanic-folds-flat"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lava"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["lava-hot"] = {}

-- decorative settings
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["vulcanus-rock-decal-large"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["vulcanus-crack-decal"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["vulcanus-crack-decal-large"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["vulcanus-crack-decal-huge-warm"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["vulcanus-crack-decal-warm"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["calcite-stain"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["calcite-stain-small"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["sulfur-stain"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["sulfur-stain-small"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["sulfuric-acid-puddle"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["sulfuric-acid-puddle-small"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["crater-small"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["crater-large"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["pumice-relief-decal"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["vulcanus-sand-decal"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["vulcanus-dune-decal"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["waves-decal"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["medium-volcanic-rock"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["small-volcanic-rock"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["tiny-volcanic-rock"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["tiny-rock-cluster"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["small-sulfur-rock"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["tiny-sulfur-rock"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["sulfur-rock-cluster"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["vulcanus-lava-fire"] = {}

-- entity settings
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["crater-cliff"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["vulcanus-chimney"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["vulcanus-chimney-faded"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["vulcanus-chimney-cold"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["vulcanus-chimney-short"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["vulcanus-chimney-truncated"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["huge-volcanic-rock"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["big-volcanic-rock"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["ashland-lichen-tree"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["ashland-lichen-tree-flaming"] = {}
-- END: Update map gen settings

-- Fix probability expressions for tiles and cliffs
terrain.mask_vulcano_coverage("volcanic-ash-flats", "tile")
terrain.mask_vulcano_coverage("volcanic-ash-light", "tile")
terrain.mask_vulcano_coverage("volcanic-ash-dark", "tile")
terrain.mask_vulcano_coverage("volcanic-cracks", "tile")
terrain.mask_vulcano_coverage("volcanic-cracks-warm", "tile")
terrain.mask_vulcano_coverage("volcanic-folds-warm", "tile")
terrain.mask_vulcano_coverage("volcanic-pumice-stones", "tile")
terrain.mask_vulcano_coverage("volcanic-cracks-hot", "tile")
terrain.mask_vulcano_coverage("volcanic-jagged-ground", "tile")
terrain.mask_vulcano_coverage("volcanic-smooth-stone", "tile")
terrain.mask_vulcano_coverage("volcanic-smooth-stone-warm", "tile")
terrain.mask_vulcano_coverage("volcanic-ash-cracks", "tile")

data.raw.tile["volcanic-folds"].autoplace.probability_expression = "eon_updated_volcanic_folds" -- Removes all lava spots except vulkane
data.raw.tile["volcanic-folds-flat"].autoplace.probability_expression = "eon_updated_volcanic_folds_flat" -- Adds big ring around vulcano
-- Lava was the only volcano feature without a terrain mask, relying on vanilla
-- biome math that inverts on Nauvis (lava lakes where the mountains biome
-- dips, with no folds around them -- including on Aquilo ice). Masked to
-- volcano terrain like everything else; legitimate cores are always deep
-- inside terrain, so they are unaffected. This also covers Aquilo: terrain
-- is never ice or ocean.
data.raw.tile["lava"].autoplace.probability_expression = "eon_mask_vulcano_terrain(eon_lava_mountains_range)"
data.raw.tile["lava-hot"].autoplace.probability_expression = "eon_mask_vulcano_terrain(eon_lava_hot_mountains_range)"

data.raw.cliff["crater-cliff"].autoplace.probability_expression = "eon_mask_vulcano_terrain(eon_lava_hot_mountains_range)"

-- Cliff contours ring volcanoes like space-age (see eon_cliff_elevation): the engine places
-- cliff segments along elevation contours with native orientations and connections.
data.raw.planet["nauvis"].map_gen_settings.property_expression_names["cliff_elevation"] = "eon_cliff_elevation"
data.raw.planet["nauvis"].map_gen_settings.property_expression_names["cliffiness"] = "eon_cliffiness"


-- START: Mask vulcanus territory on all autoplace settings
-- Mask decoratives close to vulcano
terrain.mask_vulcano_coverage("vulcanus-chimney", "simple-entity")
terrain.mask_vulcano_coverage("vulcanus-chimney-faded", "simple-entity")
terrain.mask_vulcano_coverage("vulcanus-chimney-cold", "simple-entity")
terrain.mask_vulcano_coverage("vulcanus-chimney-short", "simple-entity")
terrain.mask_vulcano_coverage("vulcanus-chimney-truncated", "simple-entity")
terrain.mask_vulcano_coverage("huge-volcanic-rock", "simple-entity")
terrain.mask_vulcano_coverage("big-volcanic-rock", "simple-entity")

-- Volcano decoratives feather past the terrain edge in two bands (outer debris
-- wider than mid details), mirroring the staggered Gleba transition. Chimneys
-- and big rocks stay on tight coverage above; lava fire stays on terrain.
-- Outer debris band
terrain.mask_volcano_early("medium-volcanic-rock", "optimized-decorative", 0.40)
terrain.mask_volcano_early("small-volcanic-rock", "optimized-decorative", 0.40)
terrain.mask_volcano_early("tiny-volcanic-rock", "optimized-decorative", 0.40)
terrain.mask_volcano_early("tiny-rock-cluster", "optimized-decorative", 0.40)
terrain.mask_volcano_early("vulcanus-sand-decal", "optimized-decorative", 0.40)
terrain.mask_volcano_early("vulcanus-dune-decal", "optimized-decorative", 0.40)
terrain.mask_volcano_early("waves-decal", "optimized-decorative", 0.40)
-- Mid detail band
terrain.mask_volcano_early("vulcanus-rock-decal-large", "optimized-decorative", 0.43)
terrain.mask_volcano_early("vulcanus-crack-decal", "optimized-decorative", 0.43)
terrain.mask_volcano_early("vulcanus-crack-decal-large", "optimized-decorative", 0.43)
terrain.mask_volcano_early("vulcanus-crack-decal-huge-warm", "optimized-decorative", 0.43)
terrain.mask_volcano_early("vulcanus-crack-decal-warm", "optimized-decorative", 0.43)
terrain.mask_volcano_early("sulfur-stain", "optimized-decorative", 0.43)
terrain.mask_volcano_early("sulfur-stain-small", "optimized-decorative", 0.43)
terrain.mask_volcano_early("sulfuric-acid-puddle", "optimized-decorative", 0.43)
terrain.mask_volcano_early("sulfuric-acid-puddle-small", "optimized-decorative", 0.43)
terrain.mask_volcano_early("crater-small", "optimized-decorative", 0.43)
terrain.mask_volcano_early("crater-large", "optimized-decorative", 0.43)
terrain.mask_volcano_early("pumice-relief-decal", "optimized-decorative", 0.43)
terrain.mask_volcano_early("small-sulfur-rock", "optimized-decorative", 0.43)
terrain.mask_volcano_early("tiny-sulfur-rock", "optimized-decorative", 0.43)
terrain.mask_volcano_early("sulfur-rock-cluster", "optimized-decorative", 0.43)
-- Lava fire stays on volcano terrain
terrain.mask_vulcano_terrain("vulcanus-lava-fire", "optimized-decorative")
-- Calcite stains pair with calcite ore wherever it grows (inside or outside
-- volcanoes), shaped like vanilla Vulcanus: transplants of vanilla's
-- vulcanus_calcite_stain(_small), identical formulas with only the region
-- input swapped (vanilla tracks ashlands ore; ours tracks nauvis ore).
-- eon_calcite is 0..1 nauvis scatter; eon_calcite_region maps it onto the
-- -1..1 region scale the vanilla formulas expect.
data:extend({
  {
    type = "noise-expression",
    name = "eon_calcite_region",
    expression = "eon_calcite * 2 - 1"
  },
  {
    type = "noise-expression",
    name = "eon_calcite_stain",
    expression = "min(0.2, min(0.5, 3 * (eon_calcite_region + 0.1)) - 0.8 - 0.6 * vulcanus_decorative_knockout)"
  },
  {
    type = "noise-expression",
    name = "eon_calcite_stain_small",
    expression = "min(0.2, min(0.5, 3 * (eon_calcite_region + 0.2)) - 0.4 + 0.6 * vulcanus_decorative_knockout)"
  },
})
data.raw["optimized-decorative"]["calcite-stain"].autoplace.probability_expression = "eon_mask_resource_territory(eon_calcite_stain)"
data.raw["optimized-decorative"]["calcite-stain-small"].autoplace.probability_expression = "eon_mask_resource_territory(eon_calcite_stain_small)"
-- END: Mask vulcanus territory on all autoplace settings

-- Ashland trees on volcano terrain (ported from EverythingOnNauvis-Patches)
data.raw["tree"]["ashland-lichen-tree"].autoplace.probability_expression = "eon_mask_vulcano_terrain(0.05 * eon_vulcano_ashland_tree_density)"
-- Flaming variant stays deep inside (coverage only, not the outer flat ring).
data.raw["tree"]["ashland-lichen-tree-flaming"].autoplace.probability_expression = "eon_mask_vulcano_coverage(0.02 * eon_vulcano_ashland_tree_density)"

-- Fewer chimneys and rocks on volcano terrain (ported from EverythingOnNauvis-Patches)
data.raw["simple-entity"]["vulcanus-chimney"].autoplace.probability_expression = "0.2 * (" .. data.raw["simple-entity"]["vulcanus-chimney"].autoplace.probability_expression .. ")"
data.raw["simple-entity"]["vulcanus-chimney-faded"].autoplace.probability_expression = "0.2 * (" .. data.raw["simple-entity"]["vulcanus-chimney-faded"].autoplace.probability_expression .. ")"
data.raw["simple-entity"]["vulcanus-chimney-cold"].autoplace.probability_expression = "0.2 * (" .. data.raw["simple-entity"]["vulcanus-chimney-cold"].autoplace.probability_expression .. ")"
data.raw["simple-entity"]["vulcanus-chimney-short"].autoplace.probability_expression = "0.2 * (" .. data.raw["simple-entity"]["vulcanus-chimney-short"].autoplace.probability_expression .. ")"
data.raw["simple-entity"]["vulcanus-chimney-truncated"].autoplace.probability_expression = "0.2 * (" .. data.raw["simple-entity"]["vulcanus-chimney-truncated"].autoplace.probability_expression .. ")"
data.raw["simple-entity"]["huge-volcanic-rock"].autoplace.probability_expression = "0.4 * (" .. data.raw["simple-entity"]["huge-volcanic-rock"].autoplace.probability_expression .. ")"
data.raw["simple-entity"]["big-volcanic-rock"].autoplace.probability_expression = "0.4 * (" .. data.raw["simple-entity"]["big-volcanic-rock"].autoplace.probability_expression .. ")"

-- New noise expressions and noise functions
data:extend({
  -- Noise expressions
  {
    -- Ashland tree density on volcano terrain: baseline chance plus patchiness.
    type = "noise-expression",
    name = "eon_vulcano_ashland_tree_density",
    expression = "clamp(0.02 + 0.8 * tree_small_noise, 0, 1)"
  },
  {
    -- Influences volcanic-folds-flat tile - distance and radius are increased to match mountain_volcano_spots, also removes remains of starter spot
    type = "noise-expression",
    name = "eon_vulcanus_ashlands_start",
    expression = "4 * starting_spot_at_angle{angle = vulcanus_ashlands_angle,\z
                                             distance = 170 * eon_starting_radius,\z
                                             radius = 740 * eon_starting_radius,\z
                                             x_distortion = 0.1 * eon_starting_radius * (vulcanus_wobble_x + vulcanus_wobble_large_x + vulcanus_wobble_huge_x),\z
                                             y_distortion = 0.1 * eon_starting_radius * (vulcanus_wobble_y + vulcanus_wobble_large_y + vulcanus_wobble_huge_y)}"
  },
  {
    -- Influences volcanic-folds-flat tile - distance and radius are increased to match mountain_volcano_spots, also removes remains of starter spot
    type = "noise-expression",
    name = "eon_vulcanus_basalts_start",
    expression = "2 * starting_spot_at_angle{angle = vulcanus_basalts_angle,\z
                                             distance = 180 * eon_starting_radius,\z
                                             radius = 760 * eon_starting_radius,\z
                                             x_distortion = 0.1 * eon_starting_radius * (vulcanus_wobble_x + vulcanus_wobble_large_x + vulcanus_wobble_huge_x),\z
                                             y_distortion = 0.1 * eon_starting_radius * (vulcanus_wobble_y + vulcanus_wobble_large_y + vulcanus_wobble_huge_y)}"
  },
  {
    -- Influences volcanic-folds-flat tile - distance and radius are increased to match mountain_volcano_spots, also removes remains of starter spot
    type = "noise-expression",
    name = "eon_vulcanus_mountains_start",
    expression = "2 * starting_spot_at_angle{angle = vulcanus_mountains_angle,\z
                                             distance = 190 * eon_starting_radius,\z
                                             radius = 780 * eon_starting_radius,\z
                                             x_distortion = 0.05 * eon_starting_radius * (vulcanus_wobble_x + vulcanus_wobble_large_x + vulcanus_wobble_huge_x),\z
                                             y_distortion = 0.05 * eon_starting_radius * (vulcanus_wobble_y + vulcanus_wobble_large_y + vulcanus_wobble_huge_y)}"
  },
  {
    type = "noise-expression",
    -- Spawn gate for volcanoes: smooth 0 near spawn to 1 further out. It
    -- throttles candidate DENSITY (fewer/no volcanoes near spawn) but never
    -- touches field values, so volcanoes that do form are always whole -- the
    -- old starting-spot subtraction cropped overlapping volcanoes (missing
    -- lava, clipped demolisher territory). Favorability is deliberately NOT
    -- gated: gated fields would make weak, lava-less volcanoes in the ramp.
    name = "eon_volcano_spawn_gate",
    expression = "clamp((distance - 850 * eon_starting_radius) / (850 * eon_starting_radius), 0, 1)"
  },
  {
    -- Volcanoes grow bigger further from spawn.
    type = "noise-expression",
    name = "eon_volcano_size_dist",
    expression = "0.8 + 0.4 * min(distance / 5000, 1)"
  },
  {
    -- Effective volcanism (vanilla formula): couples the size and frequency
    -- sliders into volcano packing density. Shared here so the demolisher
    -- size progression can normalize distance by it (see enemies.lua).
    type = "noise-expression",
    name = "eon_volcanism",
    expression = "0.3 + 0.7 * slider_rescale(control:vulcanus_volcanism:size, 3) / slider_rescale(vulcanus_scale_multiplier, 3)"
  },
  {
    -- Detail noise with an explicit position offset (base vulcanus_detail_noise has none).
    type = "noise-function",
    name = "eon_detail_noise_at",
    parameters = {"seed1", "scale", "octaves", "magnitude", "x_offset", "y_offset"},
    expression = "multioctave_noise{x = x + x_offset, y = y + y_offset, seed0 = map_seed, seed1 = seed1 + 12243, octaves = octaves, persistence = 0.6, input_scale = 1 / 50 / scale, output_scale = magnitude}"
  },
  {
    -- Volcano spots evaluated at an offset position. Tiles use (0, 0); the
    -- territory-adjacent fields below sample the same spot field 16px up-left so
    -- the roaming spots look the same on both grids. Two spot systems
    -- (small/dense + big/sparse, different seeds) merge into varied volcano
    -- sizes; quantity stays radius-squared so field peaks behave the same at
    -- every size.
    type = "noise-function",
    name = "eon_volcano_spots_at",
    parameters = {"x_offset", "y_offset", "seed", "spacing_mult", "size_mult"},
    expression = "spot_noise{x = x + x_offset + eon_detail_noise_at{seed1 = 10, scale = 1/8, octaves = 2, magnitude = 4, x_offset = x_offset, y_offset = y_offset}/2 + eon_detail_noise_at{seed1 = 20, scale = 1/2, octaves = 2, magnitude = 50, x_offset = x_offset, y_offset = y_offset}/12 + eon_detail_noise_at{seed1 = 30, scale = 2, octaves = 2, magnitude = 800, x_offset = x_offset, y_offset = y_offset}/80,\z
                             y = y + y_offset + eon_detail_noise_at{seed1 = 1010, scale = 1/8, octaves = 2, magnitude = 4, x_offset = x_offset, y_offset = y_offset}/2 + eon_detail_noise_at{seed1 = 1020, scale = 1/2, octaves = 2, magnitude = 50, x_offset = x_offset, y_offset = y_offset}/12 + eon_detail_noise_at{seed1 = 1030, scale = 2, octaves = 2, magnitude = 800, x_offset = x_offset, y_offset = y_offset}/80,\z
                             seed0 = map_seed,\z
                             seed1 = seed,\z
                             candidate_spot_count = 1,\z
                             suggested_minimum_candidate_point_spacing = volcano_spot_spacing * spacing_mult,\z
                             skip_span = 1,\z
                             skip_offset = 0,\z
                             region_size = 256*density_multiplier,\z
                             density_expression = volcano_area / volcanism_sq * eon_volcano_spawn_gate,\z
                             spot_quantity_expression = volcano_spot_size * volcano_spot_size,\z
                             spot_radius_expression = volcano_spot_size,\z
                             hard_region_target_quantity = 0,\z
                             spot_favorability_expression = volcano_area,\z
                             basement_value = 0,\z
                             maximum_spot_basement_radius = volcano_spot_radius * size_mult}",
    local_expressions =
    {
      volcano_area = "lerp(vulcanus_mountains_biome_full_pre_volcano, 0, vulcanus_starting_area)",
      volcanism = "eon_volcanism",
      volcanism_sq = "volcanism * volcanism",
      volcano_spot_radius = "300 * volcanism * sqrt(1 + control:vulcanus_volcanism:size)",
      volcano_spot_size = "volcano_spot_radius * size_mult * eon_volcano_size_dist",
      volcano_spot_spacing = "1500 * volcanism",
      density_multiplier = "5 / sqrt(control:vulcanus_volcanism:frequency)"
    }
  },
  {
    type = "noise-expression",
    name = "eon_mountain_volcano_spots",
    -- Whole volcanoes everywhere: spawn protection lives in candidate density
    -- (eon_volcano_spawn_gate), never as field subtraction, so nothing here
    -- can crop a volcano.
    expression = "max(eon_volcano_spots_at{x_offset = 0, y_offset = 0, seed = 1, spacing_mult = 1, size_mult = 0.75}, eon_volcano_spots_at{x_offset = 0, y_offset = 0, seed = 2, spacing_mult = 1.8, size_mult = 1.25})"
  },
  {
    -- Same spot field as the tiles, sampled 16px up-left so size-cap areas stay
    -- aligned with the tile rendering. No spawn gate here either: with no spots
    -- near spawn there is no territory there, and rims may legitimately overlap
    -- the gate zone. Small and big systems are named separately (not just merged)
    -- so the demolisher size logic can tell small-only ground apart from big
    -- ground. These fields feed only demolisher size caps -- territory MEMBERSHIP
    -- comes from the tile-truth eon_vulcanus_terrain mask (see eon_demolisher_territory).
    type = "noise-expression",
    name = "eon_terr_volcano_small",
    expression = "eon_volcano_spots_at{x_offset = 16, y_offset = 16, seed = 1, spacing_mult = 1, size_mult = 0.75}"
  },
  {
    type = "noise-expression",
    name = "eon_terr_volcano_big",
    expression = "eon_volcano_spots_at{x_offset = 16, y_offset = 16, seed = 2, spacing_mult = 1.8, size_mult = 1.25}"
  },
  {
    type = "noise-expression",
    name = "eon_terr_volcano_spots",
    expression = "max(eon_terr_volcano_small, eon_terr_volcano_big)"
  },
  {
    -- Size cap for demolishers: small-only volcano ground (strong small field,
    -- weak big field) grows at most medium demolishers, so big ones never sit
    -- on small volcanoes. Anywhere big ground is strong, distance decides.
    type = "noise-expression",
    name = "eon_volcano_small_cap",
    expression = "if(eon_terr_volcano_small > 0.5, if(eon_terr_volcano_big > 0.5, 4, 1), 4)"
  },
  {
    -- Territory follows the volcano CORE plus the inner half of the folds-flat skirt
    -- (eon_demolisher_mask_at16: tile-truth, never off-volcano), evaluated at the
    -- engine's per-chunk sample point. The probe (see AGENTS.md) showed the territory
    -- index expression is sampled at ONE fixed world-aligned corner per 32x32 chunk,
    -- claimed iff expression >= 0 there. The 16px field shift cancels the half-chunk
    -- SE bias the corner anchoring introduces (measured +15/+16px un-shifted); the
    -- outer half of the skirt stays a buffer so patrol anchors remain inside volcano
    -- ground.
    type = "noise-expression",
    name = "eon_demolisher_territory",
    expression = "eon_demolisher_mask_at16"
  },
  {
    -- Seed: 3329457809 south east
    type = "noise-expression",
    name = "eon_mountain_lava_spots",
    expression = "clamp(vulcanus_threshold(eon_mountain_volcano_spots * 1.95 - 0.95, 0.4 * vulcanus_threshold(clamp(vulcanus_plasma(17453, 0.2, 0.4, 10, 20) / 20, 0, 1), 3.5)), 0, 1)"
  },
  {
    -- Removes all lava spots except vulkane
    type = "noise-expression",
    name = "eon_lava_mountains_range",
    expression = "1100 * range_select_base(eon_mountain_lava_spots, 0.3, 10, 1, 0, 1) - eon_offset_vulcano"
  },
  {
    -- Removes all lava spots except vulkane
    type = "noise-expression",
    name = "eon_lava_hot_mountains_range",
    expression = "1000 * range_select_base(eon_mountain_lava_spots, 0.15, 0.35, 1, 0, 1) - eon_offset_vulcano"
  },
  {
    -- Mask vulcanus decoratives
    type = "noise-expression",
    name = "eon_crater_cliff",
    expression = "eon_mask_vulcano_coverage(0.5 * (vulcanus_rock_noise + 0.5 * aux - 0.5 * moisture) * (1 - max(vulcanus_basalts_biome,vulcanus_ashlands_biome)) * place_every_n(21,21,0,0))"
  },
  {
    -- To remove the small random lava puddles
    type = "noise-expression",
    name = "eon_offset_vulcano",
    expression = "1.5"
  },
  {
    -- Noise expression for ring around lava spots
    type = "noise-expression",
    name = "eon_updated_volcanic_folds",
    expression = "10 * range_select_base(eon_mountain_volcano_spots * 1.95 - 0.9, 0.16, 10, 1, 0, 1) - eon_offset_vulcano"  --  Creates ring around eon_lava_hot_mountains_range
  },
  {
    -- Noise expression for surroundings of eon_updated_volcanic_folds
    type = "noise-expression",
    name = "eon_updated_volcanic_folds_flat",
    expression = "10 * range_select_base(eon_mountain_volcano_spots * 1.95 - 0.9, 0, 0.5, 1, 0, 1) - eon_offset_vulcano"  --  Creates ring around updated_volcanic_folds
  },
  {
    -- Noise expression for vulcano spot and close surround as mask
    type = "noise-expression",
    name = "eon_vulcano_coverage",
    expression = "max(eon_updated_volcanic_folds, eon_lava_mountains_range, eon_lava_hot_mountains_range) > 0"
  },
  {
    -- Noise expression for all vulcanus terrain as mask
    type = "noise-expression",
    name = "eon_vulcanus_terrain",
    expression = "max(eon_vulcano_coverage, eon_updated_volcanic_folds_flat) > 0"
  },
  -- Territory mask chain: the volcano CORE signals (folds + lava rings) evaluated on
  -- the 16px-shifted spot field (eon_terr_volcano_spots = eon_volcano_spots_at{16,16}).
  -- The engine samples the territory index at each chunk's top-left corner, so an
  -- un-shifted mask makes the claimed union sit ~half a chunk SE of the terrain
  -- (measured +15/+16px on seed 12345); shifting the underlying field 16px NW recenters
  -- it. Using the core signals (not the outer folds-flat skirt) leaves the rim as a
  -- buffer: rim/water fringe chunks whose corner only just samples interior no longer
  -- get claimed, and demolisher patrol anchors stay well inside volcano ground.
  {
    type = "noise-expression",
    name = "eon_mountain_lava_spots_at16",
    expression = "clamp(vulcanus_threshold(eon_terr_volcano_spots * 1.95 - 0.95, 0.4 * vulcanus_threshold(clamp(vulcanus_plasma(17453, 0.2, 0.4, 10, 20) / 20, 0, 1), 3.5)), 0, 1)"
  },
  {
    type = "noise-expression",
    name = "eon_lava_mountains_range_at16",
    expression = "1100 * range_select_base(eon_mountain_lava_spots_at16, 0.3, 10, 1, 0, 1) - eon_offset_vulcano"
  },
  {
    type = "noise-expression",
    name = "eon_lava_hot_mountains_range_at16",
    expression = "1000 * range_select_base(eon_mountain_lava_spots_at16, 0.15, 0.35, 1, 0, 1) - eon_offset_vulcano"
  },
  {
    type = "noise-expression",
    name = "eon_updated_volcanic_folds_at16",
    expression = "10 * range_select_base(eon_terr_volcano_spots * 1.95 - 0.9, 0.16, 10, 1, 0, 1) - eon_offset_vulcano"
  },
  {
    type = "noise-expression",
    name = "eon_updated_volcanic_folds_flat_at16",
    expression = "10 * range_select_base(eon_terr_volcano_spots * 1.95 - 0.9, 0, 0.5, 1, 0, 1) - eon_offset_vulcano"
  },
  {
    -- Core-only territory mask: folds + lava rings on the 16px-shifted field, WITHOUT
    -- the outer folds-flat skirt. The flat skirt is 0.5-1.5 chunks of gentle rim that
    -- (a) grabbed rim/water fringe chunks whose corner sampled interior, and (b) put
    -- patrol anchors on the volcano edge (demolishers circling or starting over water).
    -- Excluding it leaves the rim as a buffer zone so patrol points stay well inside
    -- volcano ground, while every lava/folds tile stays covered.
    type = "noise-expression",
    name = "eon_vulcanus_core_at16",
    expression = "max(eon_updated_volcanic_folds_at16, eon_lava_mountains_range_at16, eon_lava_hot_mountains_range_at16) > 0"
  },
  {
    -- Territory mask: the core, plus the INNER edge of the folds-flat skirt (flat
    -- tiles whose spot field is still above 0.55 -- the sliver nearest the core, a
    -- small nudge for the rim-edge grains). The skirt add is tile-truth by
    -- construction ((flat_at16 > 0) is a real tile signal), so it can never claim
    -- off-volcano ground; keeping it thin means the water-corner rim chunks (whose
    -- patrol anchors would sit on their deepwater parts) stay unclaimed.
    type = "noise-expression",
    name = "eon_demolisher_mask_at16",
    expression = "max(eon_vulcanus_core_at16, (eon_updated_volcanic_folds_flat_at16 > 0) * (eon_terr_volcano_spots > 0.6))"
  },
  {
    -- Steeper slope crowding terrace rings near the lava for cliff contours
    -- (see eon_cliff_elevation). Closed rims are intended: kite the demolisher
    -- to blast access.
    type = "noise-expression",
    name = "eon_volcano_cliff_spike",
    expression = "300 * clamp((eon_mountain_volcano_spots - 0.60) / 0.25, 0, 1)"
  },
  {
    -- Cliff elevation follows the same blend as the tiles: Nauvis contours
    -- north, Gleba elevation contours deep south (vanilla Gleba uses the
    -- elevation property directly). Volcano spikes still ring volcanoes. Compensate
    -- for non-default cliff_elevation_0 so the contour grid keeps the same offsets.
    type = "noise-expression",
    name = "eon_cliff_elevation",
    expression = "lerp(cliff_elevation_nauvis, eon_elevation_blended, eon_gleba_blend_fast) + eon_volcano_cliff_spike + (cliff_elevation_0 - 10)"
  },
  {
    -- Cliffiness with volcanoes enabled, blending to vanilla Gleba density
    -- (gleba_cliffiness) deep south.
    type = "noise-expression",
    name = "eon_cliffiness",
    expression = "if(eon_vulcanus_terrain, 1.5, lerp(cliffiness_nauvis, gleba_cliffiness, eon_gleba_blend))"
  },
  -- Noise functions
  {
    -- Mask close surroundings of vulcano
    type = "noise-function",
    name = "eon_mask_vulcano_coverage",
    parameters = {"expression"},
    expression = "if(eon_vulcano_coverage, expression, -inf)"
  },
  {
    -- Mask all vulcanus terrain
    type = "noise-function",
    name = "eon_mask_vulcano_terrain",
    parameters = {"expression"},
    expression = "if(eon_vulcanus_terrain, expression, -inf)"
  },
  {
    -- Volcano natives blend off their own terrain edge (see
    -- terrain.mask_volcano_early): the same eon_fade with the spot field
    -- inverted — 0.46 - spots grows outward from the terrain edge (~0.46),
    -- full inside, fading to a 0.25 floor at the outer reach (threshold).
    type = "noise-function",
    name = "eon_mask_volcano_early",
    parameters = {"expression", "threshold"},
    expression = "eon_fade(expression, 0.46 - eon_mountain_volcano_spots, 0, 0.46 - threshold, 0.25)"
  },
  {
    -- Mask off close surroundings of vulcano
    type = "noise-function",
    name = "eon_mask_off_vulcano_coverage",
    parameters = {"expression"},
    expression = "if(eon_vulcano_coverage, -inf, expression)"
  },
  {
    -- Generic boundary fade, the ONE fade primitive for every biome boundary
    -- (see AGENTS.md "Boundary feathering rules"): `field` measures distance
    -- INTO the neighbouring biome (0 = home side). Full strength while
    -- field <= lo, linear fade to `floor` by field = hi, -inf past hi.
    -- Home-side gates and hard exclusions are separate fades combined with
    -- min(). No boost: the old x4 rim boost was a playtest patch that made
    -- flora carpet volcano flanks and is gone.
    type = "noise-function",
    name = "eon_fade",
    parameters = {"expression", "field", "lo", "hi", "floor"},
    expression = "if(field > hi, -inf, if(field > lo, expression * clamp((hi - field) / (hi - lo), floor, 1), expression))"
  },
  {
    -- Nauvis native that blends into its neighbours: ONE evaluation of the
    -- vanilla pattern times the min of per-boundary fades. Plain ground: full
    -- on nauvis, feathering out over the last ~1 transition (~5-10 tiles)
    -- BEFORE the gleba line and zero south of it — grass tufts must never
    -- sit on gleba tiles (reported repeatedly). Volcano: a short edge ring
    -- (spots 0.46-0.52 = the terrain edge to the mid-flank) on the nauvis
    -- side only (transition <= 0 — a volcano in gleba territory gets no
    -- nauvis flora). Aquilo/ammonia: hard.
    type = "noise-function",
    name = "eon_mask_nauvis_territory_fade",
    parameters = {"expression", "threshold"},
    expression = "if(eon_gleba_transition > threshold, -inf, if(eon_aquilo_mask, -inf, if(eon_ammonia_mask, -inf, if(eon_vulcanus_terrain, -inf, expression * clamp(threshold - eon_gleba_transition, 0, 1)))))"
  },
  {
    -- Gleba native that blends north instead of the hard mask_gleba_early
    -- switch: full in gleba, fading across the first ~3 transition (≈10-30
    -- tiles) north of the line, plus a short volcano edge ring on the gleba
    -- side only (transition >= 0, spots 0.46-0.52). The old -40 threshold
    -- was ~400 tiles of flora in nauvis — the units got confused with tiles.
    -- Aquilo: hard.
    type = "noise-function",
    name = "eon_mask_gleba_territory_fade",
    parameters = {"expression", "threshold"},
    expression = "if(eon_gleba_transition < threshold, -inf, if(eon_aquilo_mask, -inf, if(eon_vulcanus_terrain, -inf, expression * clamp(eon_gleba_transition - threshold, 0, 1))))"
  },
  {
    -- Mask off all vulcanus terrain
    type = "noise-function",
    name = "eon_mask_off_vulcano_terrain",
    parameters = {"expression"},
    expression = "if(eon_vulcanus_terrain, -inf, expression)"
  },
})
-- END: Update noise expressions

--------------------------------------------------------------------------------
-- MARK: Nauvis decoratives: hard masks, upstream-style
--------------------------------------------------------------------------------
-- Nauvis natives are hard-masked to nauvis territory (the mask block in the
-- Nauvis section above); only decoratives that explicitly blend into
-- neighbour biomes use the _fade helper (currently the grass tufts). No
-- volcano-rim allowance, no aquilo fringe: those were the source of every
-- "nauvis flora around volcanoes / in gleba" leak and are gone (see
-- AGENTS.md "Boundary feathering rules").

-- Gleba transition flora (leaders that blend north into the mixing band
-- instead of popping in hard at -40): the gleba _fade helper gives them a
-- smooth 0..-40 blend on plain ground and a short volcano edge ring on the
-- gleba side only (transition >= 0). Overrides the hard mask_gleba_territory
-- calls above.
for _, name in pairs({
  "honeycomb-fungus", "honeycomb-fungus-1x1", "honeycomb-fungus-decayed",
  "yellow-lettuce-lichen-cups-1x1", "yellow-lettuce-lichen-cups-3x3",
  "yellow-lettuce-lichen-cups-6x6", "coral-water",
}) do
  terrain.mask_gleba_territory_fade(name, "optimized-decorative", -1)
end

return terrain
