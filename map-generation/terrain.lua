--------------------------------------------------------------------------------
-- Fixes map generation for terrain
--------------------------------------------------------------------------------
local data_util = require("data-util")

local terrain = {}

function terrain.mask_nauvis_territory(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_nauvis_territory(" .. data_util.generate_eon_name(decorative) .. ")"
end

function terrain.mask_off_nauvis_territory(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_off_nauvis_territory(" .. data_util.generate_eon_name(decorative) .. ")"
end

function terrain.mask_resource_territory(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_off_vulcano_terrain(eon_mask_resource_territory(" .. data_util.generate_eon_name(decorative) .. "))"
end

function terrain.mask_aquilo_territory(decorative, decorative_type)
  data.raw[decorative_type][decorative].autoplace.probability_expression = "eon_mask_aquilo_territory(" .. data_util.generate_eon_name(decorative) .. ")"
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
data.raw.tile["water"].autoplace.probability_expression = "eon_updated_water + if(eon_gleba_region(-10), -inf, 0)"
data.raw.tile["deepwater"].autoplace.probability_expression = "eon_updated_deepwater + if(eon_gleba_region(-100), -inf, 0)"

-- START: Mask nauvis territory on all autoplace settings
-- Remove nauvis trees from eon_vulcanus_terrain
-- data.raw["noise-expression"]["trees_forest_path_cutout"].expression = "mask_off_vulcano_terrain(min(nauvis_bridge_paths, nauvis_hills_paths, forest_paths))"
data.raw["noise-expression"]["trees_forest_path_cutout_faded"].expression = "eon_mask_nauvis_territory(trees_forest_path_cutout * 0.3 + tree_small_noise * 0.1)"

-- Dead trees only grow on nauvis territory (same fix as EverythingOnNauvis-Patches).
-- Masked at expression level like trees_forest_path_cutout_faded: tree_dead_grey_trunk
-- is only used by dead-grey-trunk, which does not reference the faded expression.
data.raw["noise-expression"]["tree_dead_grey_trunk"].expression = "eon_mask_nauvis_territory(" .. data.raw["noise-expression"]["tree_dead_grey_trunk"].expression .. ")"

-- Remove nauvis decoratives from eon_vulcano_coverage
terrain.mask_nauvis_territory("cracked-mud-decal", "optimized-decorative")
terrain.mask_nauvis_territory("dark-mud-decal", "optimized-decorative")
terrain.mask_nauvis_territory("lichen-decal", "optimized-decorative")
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
terrain.mask_nauvis_territory("green-carpet-grass", "optimized-decorative")
terrain.mask_nauvis_territory("green-croton", "optimized-decorative")
terrain.mask_nauvis_territory("green-desert-bush", "optimized-decorative")
terrain.mask_nauvis_territory("green-hairy-grass", "optimized-decorative")
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

-- Remove nauvis tiles from gleba territory
terrain.mask_nauvis_territory("grass-1", "tile")
terrain.mask_nauvis_territory("grass-2", "tile")
terrain.mask_nauvis_territory("grass-3", "tile")
terrain.mask_nauvis_territory("grass-4", "tile")
terrain.mask_nauvis_territory("dry-dirt", "tile")
terrain.mask_nauvis_territory("dirt-1", "tile")
terrain.mask_nauvis_territory("dirt-2", "tile")
terrain.mask_nauvis_territory("dirt-3", "tile")
terrain.mask_nauvis_territory("dirt-4", "tile")
terrain.mask_nauvis_territory("dirt-5", "tile")
terrain.mask_nauvis_territory("dirt-6", "tile")
terrain.mask_nauvis_territory("dirt-7", "tile")
terrain.mask_nauvis_territory("sand-1", "tile")
terrain.mask_nauvis_territory("sand-2", "tile")
terrain.mask_nauvis_territory("sand-3", "tile")
terrain.mask_nauvis_territory("red-desert-0", "tile")
terrain.mask_nauvis_territory("red-desert-1", "tile")
terrain.mask_nauvis_territory("red-desert-2", "tile")
terrain.mask_nauvis_territory("red-desert-3", "tile")
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

-- mask aquilo tiles
-- terrain.mask_aquilo_territory("snow-flat", "tile")
terrain.mask_aquilo_territory("snow-crests", "tile")
terrain.mask_aquilo_territory("snow-lumpy", "tile")
terrain.mask_aquilo_territory("snow-patchy", "tile")
-- terrain.mask_aquilo_territory("ice-rough", "tile")
-- terrain.mask_aquilo_territory("ice-smooth", "tile")
-- terrain.mask_aquilo_territory("brash-ice", "tile")

-- mask aquilo decoratives
terrain.mask_aquilo_territory("lithium-iceberg-medium", "optimized-decorative")
terrain.mask_aquilo_territory("lithium-iceberg-small", "optimized-decorative")
terrain.mask_aquilo_territory("lithium-iceberg-tiny", "optimized-decorative")
terrain.mask_aquilo_territory("floating-iceberg-large", "optimized-decorative")
terrain.mask_aquilo_territory("floating-iceberg-small", "optimized-decorative")
terrain.mask_aquilo_territory("aqulio-ice-decal-blue", "optimized-decorative")
terrain.mask_aquilo_territory("aqulio-snowy-decal", "optimized-decorative")
terrain.mask_aquilo_territory("snow-drift-decal", "optimized-decorative")

-- mask aquilo entities
terrain.mask_aquilo_territory("lithium-iceberg-huge", "simple-entity")
terrain.mask_aquilo_territory("lithium-iceberg-big", "simple-entity")
-- END: Mask aquilo territory on all autoplace settings

-- START: Update noise expressions
data.raw.tile["ammoniacal-ocean"].autoplace.probability_expression = "eon_mask_aquilo_territory(eon_aquilo_ammonia + 0.01 * (aux - 0.5))"
data.raw.tile["ammoniacal-ocean-2"].autoplace.probability_expression = "eon_mask_aquilo_territory(eon_aquilo_ammonia - 0.01 * (aux - 0.5))"

data.raw.tile["snow-flat"].autoplace.probability_expression = "eon_mask_aquilo_territory(eon_aquilo_land)"
-- data.raw.tile["snow-crests"].autoplace.probability_expression = "eon_mask_aquilo_territory(eon_aquilo_land)"
-- data.raw.tile["snow-lumpy"].autoplace.probability_expression = "eon_mask_aquilo_territory(eon_aquilo_land)"
-- data.raw.tile["snow-patchy"].autoplace.probability_expression = "eon_mask_aquilo_territory(eon_aquilo_land)"
data.raw.tile["ice-rough"].autoplace.probability_expression = "eon_mask_aquilo_territory(eon_aquilo_base(eon_aquilo_ammonia_depth + 1.5, 200))"
data.raw.tile["ice-smooth"].autoplace.probability_expression = "eon_mask_aquilo_territory(eon_aquilo_base(eon_aquilo_ammonia_depth + 1, 200))"
data.raw.tile["brash-ice"].autoplace.probability_expression = "eon_mask_aquilo_territory(eon_aquilo_base(eon_aquilo_ammonia_depth + 0.5, 200))"
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
})

--------------------------------------------------------------------------------
-- MARK: Fix Gleba related map gen settings
--------------------------------------------------------------------------------

-- START: Update map gen settings
-- autoplace_controls
data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["gleba_plants"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["gleba_water"] = {}

-- tile settings
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["natural-yumako-soil"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["natural-jellynut-soil"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-yumako"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-jellynut"] = {}
-- data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-blue-slime"] = {}  -- gleba water
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-light-green-slime"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-green-slime"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-light-dead-skin"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-dead-skin"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-pink-tentacle"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-red-tentacle"] = {}
-- data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["gleba-deep-lake"] = {}  -- gleba water
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
terrain.mask_gleba_territory("wetland-blue-slime", "tile")
terrain.mask_gleba_territory("wetland-light-green-slime", "tile")
terrain.mask_gleba_territory("wetland-green-slime", "tile")
terrain.mask_gleba_territory("wetland-light-dead-skin", "tile")
terrain.mask_gleba_territory("wetland-dead-skin", "tile")
terrain.mask_gleba_territory("wetland-pink-tentacle", "tile")
terrain.mask_gleba_territory("wetland-red-tentacle", "tile")
terrain.mask_gleba_territory("gleba-deep-lake", "tile")
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
terrain.mask_gleba_territory("midland-turquoise-bark", "tile")
terrain.mask_gleba_territory("midland-turquoise-bark-2", "tile")
terrain.mask_gleba_territory("midland-cracked-lichen", "tile")
terrain.mask_gleba_territory("midland-cracked-lichen-dull", "tile")
terrain.mask_gleba_territory("midland-cracked-lichen-dark", "tile")
terrain.mask_gleba_territory("midland-yellow-crust", "tile")
terrain.mask_gleba_territory("midland-yellow-crust-2", "tile")
terrain.mask_gleba_territory("midland-yellow-crust-3", "tile")
terrain.mask_gleba_territory("midland-yellow-crust-4", "tile")
terrain.mask_gleba_territory("highland-dark-rock", "tile")
terrain.mask_gleba_territory("highland-dark-rock-2", "tile")
terrain.mask_gleba_territory("highland-yellow-rock", "tile")
terrain.mask_gleba_territory("pit-rock", "tile")

-- mask gleba decoratives
terrain.mask_gleba_territory("yellow-lettuce-lichen-1x1", "optimized-decorative")
terrain.mask_gleba_territory("yellow-lettuce-lichen-3x3", "optimized-decorative")
terrain.mask_gleba_territory("yellow-lettuce-lichen-6x6", "optimized-decorative")
terrain.mask_gleba_territory("yellow-lettuce-lichen-cups-1x1", "optimized-decorative")
terrain.mask_gleba_territory("yellow-lettuce-lichen-cups-3x3", "optimized-decorative")
terrain.mask_gleba_territory("yellow-lettuce-lichen-cups-6x6", "optimized-decorative")
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
terrain.mask_gleba_territory("coral-water", "optimized-decorative")
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
terrain.mask_gleba_territory("white-carpet-grass", "optimized-decorative")
terrain.mask_gleba_territory("green-carpet-grass", "optimized-decorative")
terrain.mask_gleba_territory("green-hairy-grass", "optimized-decorative")
terrain.mask_gleba_territory("light-mud-decal", "optimized-decorative")
terrain.mask_gleba_territory("dark-mud-decal", "optimized-decorative")
terrain.mask_gleba_territory("cracked-mud-decal", "optimized-decorative")
terrain.mask_gleba_territory("red-desert-bush", "optimized-decorative")
terrain.mask_gleba_territory("white-desert-bush", "optimized-decorative")
terrain.mask_gleba_territory("red-pita", "optimized-decorative")
terrain.mask_gleba_territory("green-bush-mini", "optimized-decorative")
terrain.mask_gleba_territory("green-croton", "optimized-decorative")
terrain.mask_gleba_territory("green-pita", "optimized-decorative")
terrain.mask_gleba_territory("green-pita-mini", "optimized-decorative")
terrain.mask_gleba_territory("lichen-decal", "optimized-decorative")
terrain.mask_gleba_territory("shroom-decal", "optimized-decorative")

-- mask gleba entities
terrain.mask_gleba_territory("iron-stromatolite", "simple-entity")
terrain.mask_gleba_territory("copper-stromatolite", "simple-entity")

-- Gleba trees
terrain.mask_gleba_territory("cuttlepop", "tree")
terrain.mask_gleba_territory("slipstack", "tree")
terrain.mask_gleba_territory("funneltrunk", "tree")
terrain.mask_gleba_territory("hairyclubnub", "tree")
terrain.mask_gleba_territory("teflilly", "tree")
terrain.mask_gleba_territory("lickmaw", "tree")
terrain.mask_gleba_territory("stingfrond", "tree")
terrain.mask_gleba_territory("boompuff", "tree")
terrain.mask_gleba_territory("sunnycomb", "tree")
terrain.mask_gleba_territory("water-cane", "tree")

if not mods["Spaghetorio"] then
  terrain.mask_gleba_territory("honeycomb-fungus", "optimized-decorative")
  terrain.mask_gleba_territory("honeycomb-fungus-1x1", "optimized-decorative")
  terrain.mask_gleba_territory("honeycomb-fungus-decayed", "optimized-decorative")
end
-- END: Mask gleba territory on all autoplace settings

-- Update autoplace controls
data.raw["autoplace-control"]["gleba_plants"].can_be_disabled = true
data.raw["autoplace-control"]["gleba_water"].can_be_disabled = true

-- Scalar tuning knobs, overridable per map via property_expression_names
-- (e.g. map exchange string or console) without a mod restart.
data.raw.planet["nauvis"].map_gen_settings.property_expression_names["eon_gleba_south_offset"] = "eon_gleba_south_offset"
data.raw.planet["nauvis"].map_gen_settings.property_expression_names["eon_gleba_deep_south_cap"] = "eon_gleba_deep_south_cap"

-- START: Update noise expressions
-- Mask gleba plants to gleba terrain
data.raw["noise-expression"]["gleba_plants_noise"].expression = "eon_mask_gleba_territory(abs(multioctave_noise{x = x,\z
                                                                                                                y = y,\z
                                                                                                                persistence = 0.8,\z
                                                                                                                seed0 = map_seed,\z
                                                                                                                seed1 = 700000,\z
                                                                                                                octaves = 3,\z
                                                                                                                input_scale = 1/20 }\z
                                                                                            * multioctave_noise{x = x,\z
                                                                                                                y = y,\z
                                                                                                                persistence = 0.8,\z
                                                                                                                seed0 = map_seed,\z
                                                                                                                seed1 = 200000,\z
                                                                                                                octaves = 3,\z
                                                                                                                input_scale = 1/6 * control:gleba_plants:frequency }))"
data.raw["noise-expression"]["gleba_plants_noise_b"].expression = "eon_mask_gleba_territory(abs(multioctave_noise{x = x,\z
                                                                                                                  y = y,\z
                                                                                                                  persistence = 0.8,\z
                                                                                                                  seed0 = map_seed,\z
                                                                                                                  seed1 = 750000,\z
                                                                                                                  octaves = 3,\z
                                                                                                                  input_scale = 1/20 * control:gleba_plants:frequency }\z
                                                                                              * multioctave_noise{x = x,\z
                                                                                                                  y = y,\z
                                                                                                                  persistence = 0.8,\z
                                                                                                                  seed0 = map_seed,\z
                                                                                                                  seed1 = 250000,\z
                                                                                                                  octaves = 3,\z
                                                                                                                  input_scale = 1/6 * control:gleba_plants:frequency }))"
-- END: Update noise expressions

-- New noise expressions and noise functions
data.raw.tile["wetland-jellynut"].autoplace.probability_expression = "eon_jellynut_spots"
data.raw.tile["wetland-yumako"].autoplace.probability_expression = "eon_yumako_spots"
data.raw.tile["natural-jellynut-soil"].autoplace.probability_expression = "eon_jellynut_soil"
data.raw.tile["natural-yumako-soil"].autoplace.probability_expression = "eon_yumako_soil"

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
    -- Caps how strongly the south pushes toward Gleba once past the transition zone.
    -- Deep-south Gleba condition becomes "noise_sum > -cap": higher values = more Gleba,
    -- lower/negative values = more Nauvis gaps (and thus more biter territory) deep south.
    -- Overridable per map via Nauvis map-gen settings property_expression_names.
    type = "noise-expression",
    name = "eon_gleba_deep_south_cap",
    expression = "1"
  },
  {
    type = "noise-expression",
    name = "eon_gleba_mask",
    expression = "eon_gleba_region(0)"
  },
  {
    type = "noise-expression",
    name = "eon_jellynut_spots",
    expression = "clamp(eon_gleba_agriculture_spots(1, 64) * 5000, -inf, 2)"
  },
  {
    type = "noise-expression",
    name = "eon_yumako_spots",
    expression = "clamp(eon_gleba_agriculture_spots(2, 64) * 5000, -inf, 2)"
  },
  {
    type = "noise-expression",
    name = "eon_jellynut_soil",
    expression = "eon_gleba_agriculture_spots(1, 32) * 6"
  },
  {
    type = "noise-expression",
    name = "eon_yumako_soil",
    expression = "eon_gleba_agriculture_spots(2, 32) * 6"
  },

  -- Noise functions
  {
    type = "noise-function",
    name = "eon_gleba_region",
    parameters = {"threshold"},
    expression = "eon_mask_off_vulcano_coverage(if(gleba_noise + gleba_intermediate_noise + gleba_small_noise + moisture_nauvis + south_offset > threshold, 1, 0))",
    local_expressions = {
      gleba_noise = "quick_multioctave_noise{x = x,\z
                                             y = y,\z
                                             seed0 = map_seed,\z
                                             seed1 = 5,\z
                                             octaves = 4,\z
                                             input_scale = var('control:gleba_plants:frequency') / 32,\z
                                             output_scale = 1/2,\z
                                             octave_output_scale_multiplier = 3,\z
                                             octave_input_scale_multiplier = 1/3}",
      gleba_intermediate_noise = "quick_multioctave_noise{x = x,\z
                                                          y = y,\z
                                                          seed0 = map_seed,\z
                                                          seed1 = 6,\z
                                                          octaves = 4,\z
                                                          input_scale = var('control:gleba_plants:frequency') / 32,\z
                                                          output_scale = 2,\z
                                                          octave_output_scale_multiplier = 3,\z
                                                          octave_input_scale_multiplier = 1/3}",
      gleba_small_noise = "quick_multioctave_noise{x = x,\z
                                                          y = y,\z
                                                          seed0 = map_seed,\z
                                                          seed1 = 7,\z
                                                          octaves = 4,\z
                                                          input_scale = var('control:gleba_plants:frequency') / 4,\z
                                                          output_scale = 1,\z
                                                          octave_output_scale_multiplier = 3,\z
                                                          octave_input_scale_multiplier = 1/3}",
      y_offset = "y - eon_gleba_south_offset",  -- gleba starts around eon_gleba_south_offset tiles to the south
      -- The linear term originally grew forever, making far-south tiles pure Gleba (no Nauvis
      -- pockets, no biter nests). The cap keeps mostly Gleba with regular Nauvis gaps.
      south_offset = "min(y_offset / (1 + pow(2, 0.01 * y_offset)) + 0.1 * y_offset - 60, eon_gleba_deep_south_cap)"
    }
  },
  {
    type = "noise-function",
    name = "eon_gleba_agriculture_spots",
    -- WHY THE FUCK IS spot_radius_expression NOT DOING ANYTHING HERE???
    parameters = {"seed", "spot_radius_expression"},
    expression = "eon_mask_gleba_territory(spot_noise{x = x + wobble_noise_x * 15,\z
                                                      y = y + wobble_noise_y * 15,\z
                                                      seed0 = map_seed,\z
                                                      seed1 = seed,\z
                                                      candidate_spot_count = 4,\z
                                                      suggested_minimum_candidate_point_spacing = 128,\z
                                                      skip_span = 1,\z
                                                      skip_offset = 0,\z
                                                      region_size = 1024,\z
                                                      density_expression = 80,\z
                                                      spot_quantity_expression = 1000,\z
                                                      spot_radius_expression = spot_radius_expression,\z
                                                      hard_region_target_quantity = 0,\z
                                                      spot_favorability_expression = 60,\z
                                                      basement_value = -0.5,\z
                                                      maximum_spot_basement_radius = 128})",
    local_expressions =
    {
      wobble_noise_x = "multioctave_noise{x = x, y = y, persistence = 0.5, seed0 = map_seed, seed1 = 3000000, octaves = 2, input_scale = 1/20}",
      wobble_noise_y = "multioctave_noise{x = x, y = y, persistence = 0.5, seed0 = map_seed, seed1 = 4000000, octaves = 2, input_scale = 1/20}"
    }
  },
  {
    -- Mask all gleba territory
    type = "noise-function",
    name = "eon_mask_gleba_territory",
    parameters = {"expression"},
    expression = "if(eon_gleba_mask, expression, -inf)"
  },
  {
    -- Mask off all gleba territory
    type = "noise-function",
    name = "eon_mask_off_gleba_territory",
    parameters = {"expression"},
    expression = "if(eon_gleba_mask, -inf, expression)"
  },
})

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
data.raw.tile["lava"].autoplace.probability_expression = "eon_lava_mountains_range"
data.raw.tile["lava-hot"].autoplace.probability_expression = "eon_lava_hot_mountains_range"

data.raw.cliff["crater-cliff"].autoplace.probability_expression = "eon_lava_hot_mountains_range"


-- START: Mask vulcanus territory on all autoplace settings
-- Mask decoratives close to vulcano
terrain.mask_vulcano_coverage("vulcanus-chimney", "simple-entity")
terrain.mask_vulcano_coverage("vulcanus-chimney-faded", "simple-entity")
terrain.mask_vulcano_coverage("vulcanus-chimney-cold", "simple-entity")
terrain.mask_vulcano_coverage("vulcanus-chimney-short", "simple-entity")
terrain.mask_vulcano_coverage("vulcanus-chimney-truncated", "simple-entity")
terrain.mask_vulcano_coverage("huge-volcanic-rock", "simple-entity")
terrain.mask_vulcano_coverage("big-volcanic-rock", "simple-entity")

-- Mask decoratives close to vulcano terrain
terrain.mask_vulcano_terrain("vulcanus-rock-decal-large", "optimized-decorative")
terrain.mask_vulcano_terrain("vulcanus-crack-decal", "optimized-decorative")
terrain.mask_vulcano_terrain("vulcanus-crack-decal-large", "optimized-decorative")
terrain.mask_vulcano_terrain("vulcanus-crack-decal-huge-warm", "optimized-decorative")
terrain.mask_vulcano_terrain("vulcanus-crack-decal-warm", "optimized-decorative")
terrain.mask_vulcano_terrain("calcite-stain", "optimized-decorative")
terrain.mask_vulcano_terrain("calcite-stain-small", "optimized-decorative")
terrain.mask_vulcano_terrain("sulfur-stain", "optimized-decorative")
terrain.mask_vulcano_terrain("sulfur-stain-small", "optimized-decorative")
terrain.mask_vulcano_terrain("sulfuric-acid-puddle", "optimized-decorative")
terrain.mask_vulcano_terrain("sulfuric-acid-puddle-small", "optimized-decorative")
terrain.mask_vulcano_terrain("crater-small", "optimized-decorative")
terrain.mask_vulcano_terrain("crater-large", "optimized-decorative")
terrain.mask_vulcano_terrain("pumice-relief-decal", "optimized-decorative")
terrain.mask_vulcano_terrain("vulcanus-sand-decal", "optimized-decorative")
terrain.mask_vulcano_terrain("vulcanus-dune-decal", "optimized-decorative")
terrain.mask_vulcano_terrain("waves-decal", "optimized-decorative")
terrain.mask_vulcano_terrain("medium-volcanic-rock", "optimized-decorative")
terrain.mask_vulcano_terrain("small-volcanic-rock", "optimized-decorative")
terrain.mask_vulcano_terrain("tiny-volcanic-rock", "optimized-decorative")
terrain.mask_vulcano_terrain("tiny-rock-cluster", "optimized-decorative")
terrain.mask_vulcano_terrain("small-sulfur-rock", "optimized-decorative")
terrain.mask_vulcano_terrain("tiny-sulfur-rock", "optimized-decorative")
terrain.mask_vulcano_terrain("sulfur-rock-cluster", "optimized-decorative")
terrain.mask_vulcano_terrain("vulcanus-lava-fire", "optimized-decorative")
-- END: Mask vulcanus territory on all autoplace settings

-- New noise expressions and noise functions
data:extend({
  -- Noise expressions
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
    name = "eon_volcano_starting_protector",
    expression = "clamp(starting_spot_at_angle{ angle = vulcanus_mountains_angle + 180 * vulcanus_starting_direction,\z
                                                distance = (400 * vulcanus_starting_area_radius) / 2,\z
                                                radius = 800 * vulcanus_starting_area_radius,\z
                                                x_distortion = vulcanus_wobble_x/2 + vulcanus_wobble_large_x/12 + vulcanus_wobble_huge_x/80,\z
                                                y_distortion = vulcanus_wobble_y/2 + vulcanus_wobble_large_y/12 + vulcanus_wobble_huge_y/80}, 0, 1)"
  },
  {
    -- Detail noise with an explicit position offset (base vulcanus_detail_noise has none).
    type = "noise-function",
    name = "eon_detail_noise_at",
    parameters = {"seed1", "scale", "octaves", "magnitude", "x_offset", "y_offset"},
    expression = "multioctave_noise{x = x + x_offset, y = y + y_offset, seed0 = map_seed, seed1 = seed1 + 12243, octaves = octaves, persistence = 0.6, input_scale = 1 / 50 / scale, output_scale = magnitude}"
  },
  {
    -- Volcano spots evaluated at an offset position, so tiles and territory share one
    -- definition: (0, 0) for tiles, (16, 16) to compensate chunk-aligned territory sampling.
    type = "noise-function",
    name = "eon_volcano_spots_at",
    parameters = {"x_offset", "y_offset"},
    expression = "spot_noise{x = x + x_offset + eon_detail_noise_at{seed1 = 10, scale = 1/8, octaves = 2, magnitude = 4, x_offset = x_offset, y_offset = y_offset}/2 + eon_detail_noise_at{seed1 = 20, scale = 1/2, octaves = 2, magnitude = 50, x_offset = x_offset, y_offset = y_offset}/12 + eon_detail_noise_at{seed1 = 30, scale = 2, octaves = 2, magnitude = 800, x_offset = x_offset, y_offset = y_offset}/80,\z
                             y = y + y_offset + eon_detail_noise_at{seed1 = 1010, scale = 1/8, octaves = 2, magnitude = 4, x_offset = x_offset, y_offset = y_offset}/2 + eon_detail_noise_at{seed1 = 1020, scale = 1/2, octaves = 2, magnitude = 50, x_offset = x_offset, y_offset = y_offset}/12 + eon_detail_noise_at{seed1 = 1030, scale = 2, octaves = 2, magnitude = 800, x_offset = x_offset, y_offset = y_offset}/80,\z
                             seed0 = map_seed,\z
                             seed1 = 1,\z
                             candidate_spot_count = 1,\z
                             suggested_minimum_candidate_point_spacing = volcano_spot_spacing,\z
                             skip_span = 1,\z
                             skip_offset = 0,\z
                             region_size = 256*density_multiplier,\z
                             density_expression = volcano_area / volcanism_sq,\z
                             spot_quantity_expression = volcano_spot_radius * volcano_spot_radius,\z
                             spot_radius_expression = volcano_spot_radius,\z
                             hard_region_target_quantity = 0,\z
                             spot_favorability_expression = volcano_area,\z
                             basement_value = 0,\z
                             maximum_spot_basement_radius = volcano_spot_radius}",
    local_expressions =
    {
      volcano_area = "lerp(vulcanus_mountains_biome_full_pre_volcano, 0, vulcanus_starting_area)",
      volcanism = "0.3 + 0.7 * slider_rescale(control:vulcanus_volcanism:size, 3) / slider_rescale(vulcanus_scale_multiplier, 3)",
      volcanism_sq = "volcanism * volcanism",
      volcano_spot_radius = "300 * volcanism * sqrt(1 + control:vulcanus_volcanism:size)",
      volcano_spot_spacing = "1500 * volcanism",
      density_multiplier = "5 / sqrt(control:vulcanus_volcanism:frequency)"
    }
  },
  {
    type = "noise-expression",
    name = "eon_mountain_volcano_spots",
    -- Removes starter spot from vulcanus
    expression = "eon_volcano_spots_at{x_offset = 0, y_offset = 0} - eon_volcano_starting_protector"
  },
  {
    -- Territory sampling is chunk-aligned (biased down/right half a chunk); the 16px
    -- offset above moves the mask up-left to compensate (see eon_volcano_spots_at).
    type = "noise-expression",
    name = "eon_terr_volcano_spots",
    expression = "if(eon_volcano_starting_protector > 0.03, 0, eon_volcano_spots_at{x_offset = 16, y_offset = 16})"
  },
  {
    -- Eroded volcano mask for demolisher territory: territory is sampled per 32x32 chunk
    -- and includes any chunk whose corner touches the mask, so the mask is eroded by about
    -- one chunk to keep territory visually inside the volcano while still covering all lava.
    -- Nauvis water/deepwater and ammonia ocean are excluded so territory never spills onto
    -- water at coastal volcanoes. Evaluated on the shifted field above.
    type = "noise-expression",
    name = "eon_demolisher_territory",
    expression = "(eon_terr_volcano_spots > 0.55) * (eon_updated_water <= 0) * (eon_updated_deepwater <= 0) * (eon_aquilo_ammonia <= -1)"
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
    expression = "1100 * range_select_base(eon_mountain_lava_spots, 0.3, 1, 1, 0, 1) - eon_offset_vulcano"
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
    -- Mask off close surroundings of vulcano
    type = "noise-function",
    name = "eon_mask_off_vulcano_coverage",
    parameters = {"expression"},
    expression = "if(eon_vulcano_coverage, -inf, expression)"
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

return terrain
