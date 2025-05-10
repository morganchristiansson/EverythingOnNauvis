local util = require("data-util")
local config = require("config")

return function(terrain)
    local gleba = {
        import_to_nauvis = function()
            -- Autoplace_controls
            data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["gleba_plants"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["gleba_water"] = {}

            -- Tile settings
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["natural-yumako-soil"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["natural-jellynut-soil"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-yumako"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-jellynut"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-light-green-slime"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-green-slime"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-light-dead-skin"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-dead-skin"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-pink-tentacle"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.tile.settings["wetland-red-tentacle"] = {}
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
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["honeycomb-fungus"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["honeycomb-fungus-1x1"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["honeycomb-fungus-decayed"] = {}
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
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["nerve-roots-veins-dense"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.decorative.settings["nerve-roots-veins-sparse"] = {}
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
            data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["gleba_enemy_base"] = {}
            data.raw["autoplace-control"]["gleba_plants"].localised_description = {
                "autoplace-control-names.gleba_plants_description" }

            -- entity settings
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["iron-stromatolite"] = {}
            data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["copper-stromatolite"] = {}
            -- END: Update map gen settings


            -- Gleba yumako / jellynut ribbons
            data.raw["noise-expression"]["gleba_biome_mask_green"].expression = "floor(abs_y / 80) % 2 == 0"
            data.raw["noise-expression"]["gleba_biome_mask_red"].expression = "floor(abs_y / 80) % 2 == 1"
        end,

        generate = function()
            data.raw["noise-expression"]["gleba_spawner"].expression = "0"
            data.raw["noise-expression"]["gleba_spawner_small"].expression = "mask_prevent_fixed(mask_prevent_aquilo(mask_prevent_vulcanus(mask_allow_gleba(0.005))))"
            -- New noise expressions and noise functions
            data:extend({
                -- Create mask for gleba territory
                {
                    type = "noise-expression",
                    name = "gleba_mask",
                    expression = "mask_prevent_fixed(raw_spots) * if(distance < " .. config.starting_radius * 10 .. ", 0, 1)",
                    local_expressions =
                    {
                        raw_spots = "if(abs(y+1) < 22, 0,\z
                                spot_noise{x = x + gleba_wobble_small_x + gleba_wobble_x/2,\z
                                y = abs_y + gleba_wobble_small_y + gleba_wobble_y/2,\z
                                seed0 = map_seed,\z
                                seed1 = 1,\z
                                candidate_spot_count = 1,\z
                                suggested_minimum_candidate_point_spacing = 200,\z
                                skip_span = 2,\z
                                skip_offset = 0,\z
                                region_size = 300,\z
                                density_expression = volcano_area / volcanism_sq,\z
                                spot_quantity_expression = volcano_spot_radius * volcano_spot_radius,\z
                                spot_radius_expression = volcano_spot_radius,\z
                                hard_region_target_quantity = 0,\z
                                spot_favorability_expression = volcano_area,\z
                                basement_value = 0,\z
                                maximum_spot_basement_radius = volcano_spot_radius})",

                        volcano_area = "lerp(vulcanus_mountains_biome_full_pre_volcano, 0, vulcanus_starting_area)",
                        volcano_spot_radius = "100",
                        volcanism =
                        "0.3 + 0.7 * slider_rescale(control:gleba_water:size, 3) / slider_rescale(control:gleba_water:frequency, 3)",
                        volcanism_sq = "volcanism * volcanism",
                        --density_multiplier = "5 / sqrt(control:vulcanus_volcanism:frequency)"
                        density_multiplier = "1"
                    }
                },
                --- Fertile mud / growing spots
                {
                    type = "noise-expression",
                    name = "gleba_fertile_spots_coastal",
                    expression = "mask_prevent_fixed(raw_spots)",
                    local_expressions =
                    {
                        raw_spots = "spot_noise{ x = x + wobble_noise_x * 15,\z
                                y = abs_y + wobble_noise_y * 15,\z
                                seed0 = map_seed,\z
                                seed1 = 1,\z
                                candidate_spot_count = 80,\z
                                suggested_minimum_candidate_point_spacing = 32,\z
                                skip_span = 1,\z
                                skip_offset = 0,\z
                                region_size = 600,\z
                                density_expression = 80,\z
                                spot_quantity_expression = 1000,\z
                                spot_radius_expression = 32,\z
                                hard_region_target_quantity = 0,\z
                                spot_favorability_expression = 60,\z
                                basement_value = -0.5,\z
                                maximum_spot_basement_radius = 128}",
                        wobble_noise_x =
                        "multioctave_noise{x = x, y = abs_y, persistence = 0.5, seed0 = map_seed, seed1 = 3000000, octaves = 2, input_scale = 1/20}",
                        wobble_noise_y =
                        "multioctave_noise{x = x, y = abs_y, persistence = 0.5, seed0 = map_seed, seed1 = 4000000, octaves = 2, input_scale = 1/20}"
                    }
                }
            })
        end
    }
    return gleba
end
