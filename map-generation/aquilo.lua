local util = require("data-util")

return function(terrain)
    local aquilo = {
        import_to_nauvis = function()
            data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["lithium_brine"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["fluorine_vent"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["ammonia_ocean"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["snow-flat"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["snow-crests"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["snow-lumpy"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["snow-patchy"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["ice-rough"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["ice-smooth"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["brash-ice"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["ammoniacal-ocean"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["ammoniacal-ocean-2"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["lithium-iceberg-medium"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["lithium-iceberg-small"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["lithium-iceberg-tiny"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["floating-iceberg-large"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["floating-iceberg-small"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["aqulio-ice-decal-blue"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["aqulio-snowy-decal"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["snow-drift-decal"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["lithium-brine"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["fluorine-vent"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["lithium-iceberg-huge"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["lithium-iceberg-big"] = {}
        end,

        generate = function()
            data:extend({
                {
                    type = "autoplace-control",
                    name = "ammonia_ocean",
                    localised_description = { "autoplace-control-names.ammonia_ocean_description" },
                    order = "z-ammonia",
                    category = "resource",
                    can_be_disabled = false
                },
            })

            data:extend({
                {
                    type = "noise-expression",
                    name = "aquilo_mask",
                    expression = "mask_prevent_fixed(aquilo_land > -1)",
                },
                {
                    type = "noise-expression",
                    name = "ammonia_mask",
                    expression = "mask_prevent_fixed(aquilo_ammonia > -1)",
                },
                {
                    type = "noise-expression",
                    name = "aquilo_land",
                    expression = "aquilo_base(aquilo_max_elevation, 100)"
                },
                {
                    type = "noise-expression",
                    name = "aquilo_max_elevation",
                    expression = "-1"
                },
                {
                    type = "noise-expression",
                    name = "aquilo_ammonia",
                    expression = "aquilo_base(aquilo_ammonia_depth, 200)"
                },
                {
                    type = "noise-expression",
                    name = "aquilo_ammonia_depth",
                    expression = "aquilo_max_elevation - 5"
                },
                {
                    type = "noise-expression",
                    name = "elevation_aquilo",
                    expression =
                    "if(wlc_elevation > factorio_base_aquilo_elevation, wlc_elevation, min(factorio_base_aquilo_elevation, -1.1))",
                    local_expressions =
                    {
                        elevation_magnitude = 20,
                        wlc_amplitude = 2,
                        ammonia_level = "10 * log2(control:ammonia_ocean:size)",
                        wlc_elevation = "max(aquilo_main - ammonia_level * wlc_amplitude, starting_island, west_bias)",
                        aquilo_main =
                        "elevation_magnitude * (0.25 * aquilo_detail + 3 * aquilo_macro * starting_macro_multiplier)",
                        -- if most of the world is flooded make sure starting areas still have land
                        starting_island =
                        "aquilo_main + elevation_magnitude * (5 - distance * segmentation_multiplier / 200)",
                        starting_macro_multiplier = "clamp(distance * aquilo_segmentation_multiplier / 2000, 0, 1)",
                        west_bias = "aquilo_main + elevation_magnitude * (5 + x * segmentation_multiplier / 500)",
                    }
                },
                {
                    type = "noise-expression",
                    name = "factorio_base_aquilo_elevation",
                    --intended_property = "elevation",
                    expression = "lerp(blended, maxed, 0.4)",
                    local_expressions = {
                        maxed               = "max(formation_clumped, formation_broken)",
                        blended             = "lerp(formation_clumped, formation_broken, 0.4)",
                        formation_clumped   = "-25\z
                          + 12 * max(aquilo_island_peaks, random_island_peaks)\z
                          + 15 * tri_crack",
                        formation_broken    = "-20\z
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
                        voronoi_large       = "voronoi_facet_noise{   x = x + aquilo_wobble_x * 2,\z
                                              y = y + aquilo_wobble_y * 2,\z
                                              seed0 = map_seed,\z
                                              seed1 = 'aquilo-cracks',\z
                                              grid_size = 24,\z
                                              distance_type = 'euclidean',\z
                                              jitter = 1}",
                        voronoi_large_cell  = "voronoi_cell_id{  x = x + aquilo_wobble_x * 2,\z
                                              y = y + aquilo_wobble_y * 2,\z
                                              seed0 = map_seed,\z
                                              seed1 = 'aquilo-cracks',\z
                                              grid_size = 24,\z
                                              distance_type = 'euclidean',\z
                                              jitter = 1}",
                        voronoi_small       = "voronoi_facet_noise{   x = x + aquilo_wobble_x * 2,\z
                                              y = y + aquilo_wobble_y * 2,\z
                                              seed0 = map_seed,\z
                                              seed1 = 'aquilo-cracks',\z
                                              grid_size = 10,\z
                                              distance_type = 'euclidean',\z
                                              jitter = 1}",
                        tri_crack           =
                        "min(aquilo_simple_billows{seed1 = 2000, octaves = 3, input_scale = segmentation_mult / 1.5},\z
                       aquilo_simple_billows{seed1 = 3000, octaves = 3, input_scale = segmentation_mult / 1.2},\z
                       aquilo_simple_billows{seed1 = 4000, octaves = 3, input_scale = segmentation_mult})",
                        segmentation_mult   = "aquilo_segmentation_multiplier / 25",
                    }
                },
                {
                    type = "noise-expression",
                    name = "aquilo_detail", -- the small scale details with variable persistance for a mix of smooth and jagged coastline
                    expression = "variable_persistence_multioctave_noise{x = x,\z
                                                         y = y,\z
                                                         seed0 = map_seed + 1,\z
                                                         seed1 = 600,\z
                                                         input_scale = aquilo_segmentation_multiplier / 14,\z
                                                         output_scale = 0.03,\z
                                                         offset_x = 10000 / aquilo_segmentation_multiplier,\z
                                                         octaves = 5,\z
                                                         persistence = aquilo_persistance}"
                },
                {
                    type = "noise-expression",
                    name = "aquilo_segmentation_multiplier",
                    expression = "0.5 * control:ammonia_ocean:frequency"
                },
                {
                    type = "noise-expression",
                    name = "aquilo_persistance",
                    expression = "clamp(amplitude_corrected_multioctave_noise{x = x,\z
                                                              y = y,\z
                                                              seed0 = map_seed + 1,\z
                                                              seed1 = 500,\z
                                                              octaves = 5,\z
                                                              input_scale = aquilo_segmentation_multiplier / 2,\z
                                                              offset_x = 10000 / aquilo_segmentation_multiplier,\z
                                                              persistence = 0.7,\z
                                                              amplitude = 0.5} + 0.55,\z
                        0.5, 0.65)"
                },
                {
                    type = "noise-expression",
                    name = "aquilo_macro",
                    expression = "multioctave_noise{x = x,\z
                                    y = y,\z
                                    persistence = 0.6,\z
                                    seed0 = map_seed + 1,\z
                                    seed1 = 1000,\z
                                    octaves = 2,\z
                                    input_scale = aquilo_segmentation_multiplier / 1600}\z
                  * max(0, multioctave_noise{x = x,\z
                                    y = y,\z
                                    persistence = 0.6,\z
                                    seed0 = map_seed + 1,\z
                                    seed1 = 1100,\z
                                    octaves = 1,\z
                                    input_scale = aquilo_segmentation_multiplier / 1600})",
                },
                {
                    -- aquilo lakes
                    type = "noise-function",
                    name = "aquilo_base",
                    parameters = { "max_elevation", "influence" },
                    expression =
                    "if(max_elevation >= elevation_aquilo, influence * min(max_elevation - elevation_aquilo, 1), -inf)"
                },
            })
        end
    }
    return aquilo
end
