local util = require("data-util")
return {
    declare_masks = function()
        data:extend({
            {
                type = "noise-function",
                name = "mask_prevent_biter",
                parameters = { "expression" },
                expression = "if(is_roughly_biter_area(x, abs_y) , -inf, expression)"
            },
            {
                type = "noise-function",
                name = "mask_prevent_fixed",
                parameters = { "expression" },
                expression = "if(moat + is_roughly_biter_area(x, abs_y) , -inf, expression)"
            },
            {
                type = "noise-function",
                name = "mask_allow_aquilo",
                parameters = { "expression" },
                expression = "if(aquilo_mask, expression, -inf)"
            },
            {
                type = "noise-function",
                name = "mask_prevent_aquilo",
                parameters = { "expression" },
                expression = "if(aquilo_mask + ammonia_mask, -inf, expression)"
            },
            {
                type = "noise-function",
                name = "mask_allow_ammonia_ocean",
                parameters = { "expression" },
                expression = "if(ammonia_mask, expression, -inf)"
            },
            {
                type = "noise-function",
                name = "mask_prevent_ammonia_ocean",
                parameters = { "expression" },
                expression = "if(ammonia_mask, -inf, expression)"
            },
            {
                type = "noise-function",
                name = "mask_allow_volcano",
                parameters = { "expression" },
                expression = "if(mask_volcano, expression, -inf)"
            },
            {
                type = "noise-function",
                name = "mask_prevent_volcano",
                parameters = { "expression" },
                expression = "if(mask_volcano, -inf, expression)"
            },
            {
                type = "noise-function",
                name = "mask_allow_vulcanus",
                parameters = { "expression" },
                expression = "if(vulcanus_mask, expression, -inf)"
            },
            {
                type = "noise-function",
                name = "mask_prevent_vulcanus",
                parameters = { "expression" },
                expression = "if(vulcanus_mask, -inf, expression)"
            },
            {
                type = "noise-function",
                name = "mask_allow_volcano",
                parameters = { "expression" },
                expression = "if(volcano_mask, expression, -inf)"
            },
            {
                type = "noise-function",
                name = "mask_prevent_volcano",
                parameters = { "expression" },
                expression = "if(volcano_mask, -inf, expression)"
            },
            {
                type = "noise-function",
                name = "mask_allow_gleba",
                parameters = { "expression" },
                expression = "if(gleba_mask, expression, -inf)"
            },
            {
                type = "noise-function",
                name = "mask_prevent_gleba",
                parameters = { "expression" },
                expression = "if(gleba_mask, -inf, expression)"
            },
            {
                type = "noise-function",
                name = "mask_allow_nauvis",
                parameters = { "expression" },
                expression =
                "mask_prevent_fixed(mask_prevent_aquilo(mask_prevent_vulcanus(mask_prevent_gleba(expression))))"
            },
            {
                type = "noise-function",
                name = "mask_allow_nauvis_and_moat",
                parameters = { "expression" },
                expression =
                "mask_prevent_biter(mask_prevent_aquilo(mask_prevent_vulcanus(mask_prevent_gleba(expression))))"
            },
            {
                type = "noise-expression",
                name = "updated_water",
                expression = "mask_allow_nauvis_and_moat(water_base(0, 100))"
            },
            {
                type = "noise-expression",
                name = "updated_deepwater",
                expression = "mask_allow_nauvis_and_moat(water_base(-2, 200))"
            },
        })
    end,

    apply_masks = function(terrain)
        function terrain.mask_allow_nauvis(entity, entity_type)
            data.raw[entity_type][entity].autoplace.probability_expression = "mask_allow_nauvis(" ..
                util.generate_default_name(entity) .. ")"
        end

        function terrain.mask_allow_nauvis_and_biter(entity, entity_type)
            data.raw[entity_type][entity].autoplace.probability_expression =
                "mask_prevent_aquilo(mask_prevent_vulcanus(mask_prevent_gleba(" ..
                util.generate_default_name(entity) .. ")))"
        end

        function terrain.mask_allow_nauvis_and_aquilo(entity, entity_type)
            data.raw[entity_type][entity].autoplace.probability_expression =
                "mask_prevent_fixed(mask_prevent_vulcanus(mask_prevent_gleba(" ..
                util.generate_default_name(entity) .. ")))"
        end

        function terrain.mask_allow_nauvis_and_gleba(entity, entity_type)
            data.raw[entity_type][entity].autoplace.probability_expression =
                "mask_prevent_fixed(mask_prevent_aquilo(mask_prevent_vulcanus(" ..
                util.generate_default_name(entity) .. ")))"
        end

        function terrain.mask_allow_gleba(entity, entity_type)
            data.raw[entity_type][entity].autoplace.probability_expression =
                "mask_prevent_fixed(mask_prevent_aquilo(mask_prevent_vulcanus(mask_allow_gleba(" ..
                util.generate_default_name(entity) .. "))))"
        end

        function terrain.mask_allow_gleba_specific(entity, entity_type, expression)
            data.raw[entity_type][entity].autoplace.probability_expression =
                "mask_prevent_fixed(mask_prevent_aquilo(mask_prevent_vulcanus(mask_allow_gleba(" ..
                expression .. "))))"
        end

        function terrain.mask_allow_aquilo(entity, entity_type)
            data.raw[entity_type][entity].autoplace.probability_expression =
                "mask_prevent_fixed(mask_allow_aquilo(" ..
                util.generate_default_name(entity) .. "))"
        end

        function terrain.mask_allow_volcano(entity, entity_type)
            data.raw[entity_type][entity].autoplace.probability_expression =
                "mask_prevent_fixed(mask_prevent_aquilo(mask_allow_vulcanus(mask_allow_volcano(" ..
                util.generate_default_name(entity) .. "))))"
        end

        function terrain.mask_allow_vulcanus(entity, entity_type)
            data.raw[entity_type][entity].autoplace.probability_expression =
                "mask_prevent_fixed(mask_prevent_aquilo(mask_allow_vulcanus(" ..
                util.generate_default_name(entity) .. ")))"
        end
        
        data.raw.tile["water"].autoplace = {
            probability_expression = "updated_water"
        }
        data.raw.tile["deepwater"].autoplace = {
            probability_expression = "updated_deepwater"
        }

        terrain.mask_allow_nauvis("cracked-mud-decal", "optimized-decorative")
        terrain.mask_allow_nauvis("dark-mud-decal", "optimized-decorative")
        terrain.mask_allow_nauvis("lichen-decal", "optimized-decorative")
        terrain.mask_allow_nauvis("light-mud-decal", "optimized-decorative")
        terrain.mask_allow_nauvis("small-rock", "optimized-decorative")
        terrain.mask_allow_nauvis("small-sand-rock", "optimized-decorative")
        terrain.mask_allow_nauvis("tiny-rock", "optimized-decorative")
        terrain.mask_allow_nauvis("big-rock", "simple-entity")
        terrain.mask_allow_nauvis("big-sand-rock", "simple-entity")
        terrain.mask_allow_nauvis("brown-asterisk", "optimized-decorative")
        terrain.mask_allow_nauvis("brown-asterisk-mini", "optimized-decorative")
        terrain.mask_allow_nauvis("brown-carpet-grass", "optimized-decorative")
        terrain.mask_allow_nauvis("brown-fluff", "optimized-decorative")
        terrain.mask_allow_nauvis("brown-fluff-dry", "optimized-decorative")
        terrain.mask_allow_nauvis("brown-hairy-grass", "optimized-decorative")
        terrain.mask_allow_nauvis("garballo", "optimized-decorative")
        terrain.mask_allow_nauvis("garballo-mini-dry", "optimized-decorative")
        terrain.mask_allow_nauvis("green-asterisk", "optimized-decorative")
        terrain.mask_allow_nauvis("green-asterisk-mini", "optimized-decorative")
        terrain.mask_allow_nauvis("green-bush-mini", "optimized-decorative")
        terrain.mask_allow_nauvis("green-carpet-grass", "optimized-decorative")
        terrain.mask_allow_nauvis("green-croton", "optimized-decorative")
        terrain.mask_allow_nauvis("green-desert-bush", "optimized-decorative")
        terrain.mask_allow_nauvis("green-hairy-grass", "optimized-decorative")
        terrain.mask_allow_nauvis("green-pita", "optimized-decorative")
        terrain.mask_allow_nauvis("green-pita-mini", "optimized-decorative")
        terrain.mask_allow_nauvis("green-small-grass", "optimized-decorative")
        terrain.mask_allow_nauvis("huge-rock", "simple-entity")
        terrain.mask_allow_nauvis("medium-rock", "optimized-decorative")
        terrain.mask_allow_nauvis("medium-sand-rock", "optimized-decorative")
        terrain.mask_allow_nauvis("red-asterisk", "optimized-decorative")
        terrain.mask_allow_nauvis("red-croton", "optimized-decorative")
        terrain.mask_allow_nauvis("red-desert-bush", "optimized-decorative")
        terrain.mask_allow_nauvis("red-desert-decal", "optimized-decorative")
        terrain.mask_allow_nauvis("red-pita", "optimized-decorative")
        terrain.mask_allow_nauvis("sand-decal", "optimized-decorative")
        terrain.mask_allow_nauvis("sand-dune-decal", "optimized-decorative")
        terrain.mask_allow_nauvis("white-desert-bush", "optimized-decorative")

        terrain.mask_allow_nauvis("grass-1", "tile")
        terrain.mask_allow_nauvis("grass-2", "tile")
        terrain.mask_allow_nauvis("grass-3", "tile")
        terrain.mask_allow_nauvis("grass-4", "tile")
        terrain.mask_allow_nauvis("dry-dirt", "tile")
        terrain.mask_allow_nauvis("dirt-1", "tile")
        terrain.mask_allow_nauvis("dirt-2", "tile")
        terrain.mask_allow_nauvis("dirt-3", "tile")
        terrain.mask_allow_nauvis("dirt-4", "tile")
        terrain.mask_allow_nauvis("dirt-5", "tile")
        terrain.mask_allow_nauvis("dirt-6", "tile")
        terrain.mask_allow_nauvis("dirt-7", "tile")
        terrain.mask_allow_nauvis("sand-1", "tile")
        terrain.mask_allow_nauvis("sand-2", "tile")
        terrain.mask_allow_nauvis("sand-3", "tile")
        terrain.mask_allow_nauvis_and_biter("red-desert-0", "tile")
        terrain.mask_allow_nauvis_and_biter("red-desert-1", "tile")
        terrain.mask_allow_nauvis_and_biter("red-desert-2", "tile")
        terrain.mask_allow_nauvis_and_biter("red-desert-3", "tile")
        terrain.mask_allow_nauvis_and_aquilo("crude-oil", "resource")
        terrain.mask_allow_nauvis("iron-ore", "resource")
        terrain.mask_allow_nauvis("copper-ore", "resource")
        terrain.mask_allow_nauvis("coal", "resource")
        terrain.mask_allow_nauvis("uranium-ore", "resource")
        terrain.mask_allow_nauvis("scrap", "resource")
        terrain.mask_allow_nauvis_and_gleba("stone", "resource")
        data.raw["noise-expression"]["trees_forest_path_cutout_faded"].expression =
        "mask_allow_nauvis(trees_forest_path_cutout * 0.3 + tree_small_noise * 0.1)"
        data.raw["noise-expression"]["cliffiness_nauvis"].expression =
        "mask_allow_nauvis((main_cliffiness >= cliff_cutoff) * 10)"

        terrain.mask_allow_gleba("natural-yumako-soil", "tile")
        terrain.mask_allow_gleba("natural-jellynut-soil", "tile")
        terrain.mask_allow_gleba("wetland-yumako", "tile")
        terrain.mask_allow_gleba("wetland-jellynut", "tile")
        terrain.mask_allow_gleba("wetland-blue-slime", "tile")
        terrain.mask_allow_gleba("wetland-light-green-slime", "tile")
        terrain.mask_allow_gleba("wetland-green-slime", "tile")
        terrain.mask_allow_gleba("wetland-light-dead-skin", "tile")
        terrain.mask_allow_gleba("wetland-dead-skin", "tile")
        terrain.mask_allow_gleba("wetland-pink-tentacle", "tile")
        terrain.mask_allow_gleba("wetland-red-tentacle", "tile")
        terrain.mask_allow_gleba("gleba-deep-lake", "tile")
        terrain.mask_allow_gleba("lowland-brown-blubber", "tile")
        terrain.mask_allow_gleba("lowland-olive-blubber", "tile")
        terrain.mask_allow_gleba("lowland-olive-blubber-2", "tile")
        terrain.mask_allow_gleba("lowland-olive-blubber-2", "tile")
        terrain.mask_allow_gleba("lowland-pale-green", "tile")
        terrain.mask_allow_gleba("lowland-cream-cauliflower", "tile")
        terrain.mask_allow_gleba("lowland-cream-cauliflower-2", "tile")
        terrain.mask_allow_gleba("lowland-dead-skin", "tile")
        terrain.mask_allow_gleba("lowland-dead-skin-2", "tile")
        terrain.mask_allow_gleba("lowland-cream-red", "tile")
        terrain.mask_allow_gleba("lowland-red-vein", "tile")
        terrain.mask_allow_gleba("lowland-red-vein-2", "tile")
        terrain.mask_allow_gleba("lowland-red-vein-3", "tile")
        terrain.mask_allow_gleba("lowland-red-vein-4", "tile")
        terrain.mask_allow_gleba("lowland-red-vein-dead", "tile")
        terrain.mask_allow_gleba("lowland-red-infection", "tile")
        terrain.mask_allow_gleba("midland-turquoise-bark", "tile")
        terrain.mask_allow_gleba("midland-turquoise-bark-2", "tile")
        terrain.mask_allow_gleba("midland-cracked-lichen", "tile")
        terrain.mask_allow_gleba("midland-cracked-lichen-dull", "tile")
        terrain.mask_allow_gleba("midland-cracked-lichen-dark", "tile")
        terrain.mask_allow_gleba("midland-yellow-crust", "tile")
        terrain.mask_allow_gleba("midland-yellow-crust-2", "tile")
        terrain.mask_allow_gleba("midland-yellow-crust-3", "tile")
        terrain.mask_allow_gleba("midland-yellow-crust-4", "tile")
        terrain.mask_allow_gleba("highland-dark-rock", "tile")
        terrain.mask_allow_gleba("highland-dark-rock-2", "tile")
        terrain.mask_allow_gleba("highland-yellow-rock", "tile")
        terrain.mask_allow_gleba("pit-rock", "tile")
        terrain.mask_allow_gleba("yellow-lettuce-lichen-1x1", "optimized-decorative")
        terrain.mask_allow_gleba("yellow-lettuce-lichen-3x3", "optimized-decorative")
        terrain.mask_allow_gleba("yellow-lettuce-lichen-6x6", "optimized-decorative")
        terrain.mask_allow_gleba("yellow-lettuce-lichen-cups-1x1", "optimized-decorative")
        terrain.mask_allow_gleba("yellow-lettuce-lichen-cups-3x3", "optimized-decorative")
        terrain.mask_allow_gleba("yellow-lettuce-lichen-cups-6x6", "optimized-decorative")
        terrain.mask_allow_gleba("green-lettuce-lichen-1x1", "optimized-decorative")
        terrain.mask_allow_gleba("green-lettuce-lichen-3x3", "optimized-decorative")
        terrain.mask_allow_gleba("green-lettuce-lichen-6x6", "optimized-decorative")
        terrain.mask_allow_gleba("green-lettuce-lichen-water-1x1", "optimized-decorative")
        terrain.mask_allow_gleba("green-lettuce-lichen-water-3x3", "optimized-decorative")
        terrain.mask_allow_gleba("green-lettuce-lichen-water-6x6", "optimized-decorative")
        terrain.mask_allow_gleba("honeycomb-fungus", "optimized-decorative")
        terrain.mask_allow_gleba("honeycomb-fungus-1x1", "optimized-decorative")
        terrain.mask_allow_gleba("honeycomb-fungus-decayed", "optimized-decorative")
        terrain.mask_allow_gleba("split-gill-1x1", "optimized-decorative")
        terrain.mask_allow_gleba("split-gill-2x2", "optimized-decorative")
        terrain.mask_allow_gleba("split-gill-dying-1x1", "optimized-decorative")
        terrain.mask_allow_gleba("split-gill-dying-2x2", "optimized-decorative")
        terrain.mask_allow_gleba("split-gill-red-1x1", "optimized-decorative")
        terrain.mask_allow_gleba("split-gill-red-2x2", "optimized-decorative")
        terrain.mask_allow_gleba("veins", "optimized-decorative")
        terrain.mask_allow_gleba("veins-small", "optimized-decorative")
        terrain.mask_allow_gleba("mycelium", "optimized-decorative")
        terrain.mask_allow_gleba("coral-water", "optimized-decorative")
        terrain.mask_allow_gleba("coral-land", "optimized-decorative")
        terrain.mask_allow_gleba("black-sceptre", "optimized-decorative")
        terrain.mask_allow_gleba("pink-phalanges", "optimized-decorative")
        terrain.mask_allow_gleba("pink-lichen-decal", "optimized-decorative")
        terrain.mask_allow_gleba("red-lichen-decal", "optimized-decorative")
        terrain.mask_allow_gleba("green-cup", "optimized-decorative")
        terrain.mask_allow_gleba("brown-cup", "optimized-decorative")
        terrain.mask_allow_gleba("blood-grape", "optimized-decorative")
        terrain.mask_allow_gleba("blood-grape-vibrant", "optimized-decorative")
        terrain.mask_allow_gleba("brambles", "optimized-decorative")
        terrain.mask_allow_gleba("polycephalum-slime", "optimized-decorative")
        terrain.mask_allow_gleba("polycephalum-balloon", "optimized-decorative")
        terrain.mask_allow_gleba("fuchsia-pita", "optimized-decorative")
        terrain.mask_allow_gleba("wispy-lichen", "optimized-decorative")
        terrain.mask_allow_gleba("grey-cracked-mud-decal", "optimized-decorative")
        terrain.mask_allow_gleba("barnacles-decal", "optimized-decorative")
        terrain.mask_allow_gleba("coral-stunted", "optimized-decorative")
        terrain.mask_allow_gleba("coral-stunted-grey", "optimized-decorative")
        terrain.mask_allow_gleba("red-nerve-roots-veins-dense", "optimized-decorative")
        terrain.mask_allow_gleba("red-nerve-roots-veins-sparse", "optimized-decorative")
        terrain.mask_allow_gleba("purple-nerve-roots-veins-dense", "optimized-decorative")
        terrain.mask_allow_gleba("purple-nerve-roots-veins-sparse", "optimized-decorative")
        terrain.mask_allow_gleba("cream-nerve-roots-veins-sparse", "optimized-decorative")
        terrain.mask_allow_gleba("cream-nerve-roots-veins-dense", "optimized-decorative")
        terrain.mask_allow_gleba("yellow-coral", "optimized-decorative")
        terrain.mask_allow_gleba("solo-barnacle", "optimized-decorative")
        terrain.mask_allow_gleba("curly-roots-orange", "optimized-decorative")
        terrain.mask_allow_gleba("knobbly-roots", "optimized-decorative")
        terrain.mask_allow_gleba("knobbly-roots-orange", "optimized-decorative")
        terrain.mask_allow_gleba("matches-small", "optimized-decorative")
        terrain.mask_allow_gleba("pale-lettuce-lichen-cups-1x1", "optimized-decorative")
        terrain.mask_allow_gleba("pale-lettuce-lichen-cups-3x3", "optimized-decorative")
        terrain.mask_allow_gleba("pale-lettuce-lichen-cups-6x6", "optimized-decorative")
        terrain.mask_allow_gleba("pale-lettuce-lichen-1x1", "optimized-decorative")
        terrain.mask_allow_gleba("pale-lettuce-lichen-3x3", "optimized-decorative")
        terrain.mask_allow_gleba("pale-lettuce-lichen-6x6", "optimized-decorative")
        terrain.mask_allow_gleba("pale-lettuce-lichen-water-1x1", "optimized-decorative")
        terrain.mask_allow_gleba("pale-lettuce-lichen-water-3x3", "optimized-decorative")
        terrain.mask_allow_gleba("pale-lettuce-lichen-water-6x6", "optimized-decorative")
        terrain.mask_allow_gleba("white-carpet-grass", "optimized-decorative")
        terrain.mask_allow_gleba("green-carpet-grass", "optimized-decorative")
        terrain.mask_allow_gleba("green-hairy-grass", "optimized-decorative")
        terrain.mask_allow_gleba("light-mud-decal", "optimized-decorative")
        terrain.mask_allow_gleba("dark-mud-decal", "optimized-decorative")
        terrain.mask_allow_gleba("cracked-mud-decal", "optimized-decorative")
        terrain.mask_allow_gleba("red-desert-bush", "optimized-decorative")
        terrain.mask_allow_gleba("white-desert-bush", "optimized-decorative")
        terrain.mask_allow_gleba("red-pita", "optimized-decorative")
        terrain.mask_allow_gleba("green-bush-mini", "optimized-decorative")
        terrain.mask_allow_gleba("green-croton", "optimized-decorative")
        terrain.mask_allow_gleba("green-pita", "optimized-decorative")
        terrain.mask_allow_gleba("green-pita-mini", "optimized-decorative")
        terrain.mask_allow_gleba("lichen-decal", "optimized-decorative")
        terrain.mask_allow_gleba("shroom-decal", "optimized-decorative")
        terrain.mask_allow_gleba("iron-stromatolite", "simple-entity")
        terrain.mask_allow_gleba("copper-stromatolite", "simple-entity")
        terrain.mask_allow_gleba("cuttlepop", "tree")
        terrain.mask_allow_gleba("slipstack", "tree")
        terrain.mask_allow_gleba("funneltrunk", "tree")
        terrain.mask_allow_gleba("hairyclubnub", "tree")
        terrain.mask_allow_gleba("teflilly", "tree")
        terrain.mask_allow_gleba("lickmaw", "tree")
        terrain.mask_allow_gleba("stingfrond", "tree")
        terrain.mask_allow_gleba("boompuff", "tree")
        terrain.mask_allow_gleba("sunnycomb", "tree")
        terrain.mask_allow_gleba("water-cane", "tree")

        data.raw["autoplace-control"]["gleba_plants"].can_be_disabled = true
        data.raw["autoplace-control"]["gleba_water"].can_be_disabled = true
        data.raw["noise-expression"]["gleba_plants_noise"].expression =
        "mask_allow_gleba(abs(multioctave_noise{x = x, y = abs_y, persistence = 0.8, seed0 = map_seed, seed1 = 700000, octaves = 3, input_scale = 1/20 }\z
                                                                                                * multioctave_noise{x = x, y = abs_y, persistence = 0.8, seed0 = map_seed, seed1 = 200000, octaves = 3, input_scale = 1/6 * control:gleba_plants:frequency }))"
        data.raw["noise-expression"]["gleba_plants_noise_b"].expression =
        "mask_allow_gleba(abs(multioctave_noise{x = x, y = abs_y, persistence = 0.8, seed0 = map_seed, seed1 = 750000, octaves = 3, input_scale = 1/20 * control:gleba_plants:frequency }\z
                                                                                                    * multioctave_noise{x = x, y = abs_y, persistence = 0.8, seed0 = map_seed, seed1 = 250000, octaves = 3, input_scale = 1/6 * control:gleba_plants:frequency }))"

        terrain.mask_allow_aquilo("lithium-brine", "resource")
        terrain.mask_allow_aquilo("fluorine-vent", "resource")
        terrain.mask_allow_aquilo("snow-crests", "tile")
        terrain.mask_allow_aquilo("snow-lumpy", "tile")
        terrain.mask_allow_aquilo("snow-patchy", "tile")
        terrain.mask_allow_aquilo("lithium-iceberg-medium", "optimized-decorative")
        terrain.mask_allow_aquilo("lithium-iceberg-small", "optimized-decorative")
        terrain.mask_allow_aquilo("lithium-iceberg-tiny", "optimized-decorative")
        terrain.mask_allow_aquilo("floating-iceberg-large", "optimized-decorative")
        terrain.mask_allow_aquilo("floating-iceberg-small", "optimized-decorative")
        terrain.mask_allow_aquilo("aqulio-ice-decal-blue", "optimized-decorative")
        terrain.mask_allow_aquilo("aqulio-snowy-decal", "optimized-decorative")
        terrain.mask_allow_aquilo("snow-drift-decal", "optimized-decorative")
        terrain.mask_allow_aquilo("lithium-iceberg-huge", "simple-entity")
        terrain.mask_allow_aquilo("lithium-iceberg-big", "simple-entity")
        data.raw.tile["snow-flat"].autoplace.probability_expression =
        "mask_prevent_fixed(mask_allow_aquilo(aquilo_land))"
        data.raw.tile["ice-rough"].autoplace.probability_expression =
        "mask_allow_aquilo(aquilo_base(aquilo_ammonia_depth + 1.5, 200))"
        data.raw.tile["ice-smooth"].autoplace.probability_expression =
        "mask_allow_aquilo(aquilo_base(aquilo_ammonia_depth + 1, 200))"
        data.raw.tile["brash-ice"].autoplace.probability_expression =
        "mask_allow_aquilo(aquilo_base(aquilo_ammonia_depth + 0.5, 200))"
        data.raw.tile["ammoniacal-ocean"].autoplace.probability_expression =
        "mask_allow_aquilo(aquilo_ammonia + 0.01 * (aux - 0.5))"
        data.raw.tile["ammoniacal-ocean-2"].autoplace.probability_expression =
        "mask_allow_aquilo(aquilo_ammonia - 0.01 * (aux - 0.5))"

        terrain.mask_allow_volcano("volcanic-ash-flats", "tile")
        terrain.mask_allow_volcano("volcanic-ash-light", "tile")
        terrain.mask_allow_volcano("volcanic-ash-dark", "tile")
        terrain.mask_allow_volcano("volcanic-cracks", "tile")
        terrain.mask_allow_volcano("volcanic-cracks-warm", "tile")
        terrain.mask_allow_volcano("volcanic-folds-warm", "tile")
        terrain.mask_allow_volcano("volcanic-pumice-stones", "tile")
        terrain.mask_allow_volcano("volcanic-cracks-hot", "tile")
        terrain.mask_allow_volcano("volcanic-jagged-ground", "tile")
        terrain.mask_allow_volcano("volcanic-smooth-stone", "tile")
        terrain.mask_allow_volcano("volcanic-smooth-stone-warm", "tile")
        terrain.mask_allow_volcano("volcanic-ash-cracks", "tile")
        terrain.mask_allow_volcano("vulcanus-chimney", "simple-entity")
        terrain.mask_allow_volcano("vulcanus-chimney-faded", "simple-entity")
        terrain.mask_allow_volcano("vulcanus-chimney-cold", "simple-entity")
        terrain.mask_allow_volcano("vulcanus-chimney-short", "simple-entity")
        terrain.mask_allow_volcano("vulcanus-chimney-truncated", "simple-entity")
        terrain.mask_allow_volcano("huge-volcanic-rock", "simple-entity")
        terrain.mask_allow_volcano("big-volcanic-rock", "simple-entity")

        data.raw.tile["volcanic-folds"].autoplace.probability_expression =
        "updated_volcanic_folds"      -- Removes all lava spots except vulkane
        data.raw.tile["volcanic-folds-flat"].autoplace.probability_expression =
        "updated_volcanic_folds_flat" -- Adds big ring around vulcano
        terrain.mask_allow_vulcanus("volcanic-folds", "tile")
        terrain.mask_allow_volcano("volcanic-folds-flat", "tile")
        data.raw.tile["lava"].autoplace.probability_expression = "lava_mountains_range"
        data.raw.tile["lava-hot"].autoplace.probability_expression = "lava_hot_mountains_range"
        terrain.mask_allow_volcano("lava", "tile")
        terrain.mask_allow_volcano("lava-hot", "tile")

        terrain.mask_allow_vulcanus("vulcanus-rock-decal-large", "optimized-decorative")
        terrain.mask_allow_vulcanus("vulcanus-crack-decal", "optimized-decorative")
        terrain.mask_allow_vulcanus("vulcanus-crack-decal-large", "optimized-decorative")
        terrain.mask_allow_vulcanus("vulcanus-crack-decal-huge-warm", "optimized-decorative")
        terrain.mask_allow_vulcanus("vulcanus-crack-decal-warm", "optimized-decorative")
        terrain.mask_allow_vulcanus("calcite-stain", "optimized-decorative")
        terrain.mask_allow_vulcanus("calcite-stain-small", "optimized-decorative")
        terrain.mask_allow_vulcanus("sulfur-stain", "optimized-decorative")
        terrain.mask_allow_vulcanus("sulfur-stain-small", "optimized-decorative")
        terrain.mask_allow_vulcanus("sulfuric-acid-puddle", "optimized-decorative")
        terrain.mask_allow_vulcanus("sulfuric-acid-puddle-small", "optimized-decorative")
        terrain.mask_allow_vulcanus("crater-small", "optimized-decorative")
        terrain.mask_allow_vulcanus("crater-large", "optimized-decorative")
        terrain.mask_allow_vulcanus("pumice-relief-decal", "optimized-decorative")
        terrain.mask_allow_vulcanus("vulcanus-sand-decal", "optimized-decorative")
        terrain.mask_allow_vulcanus("vulcanus-dune-decal", "optimized-decorative")
        terrain.mask_allow_vulcanus("waves-decal", "optimized-decorative")
        terrain.mask_allow_vulcanus("medium-volcanic-rock", "optimized-decorative")
        terrain.mask_allow_vulcanus("small-volcanic-rock", "optimized-decorative")
        terrain.mask_allow_vulcanus("tiny-volcanic-rock", "optimized-decorative")
        terrain.mask_allow_vulcanus("tiny-rock-cluster", "optimized-decorative")
        terrain.mask_allow_vulcanus("small-sulfur-rock", "optimized-decorative")
        terrain.mask_allow_vulcanus("tiny-sulfur-rock", "optimized-decorative")
        terrain.mask_allow_vulcanus("sulfur-rock-cluster", "optimized-decorative")
        terrain.mask_allow_vulcanus("vulcanus-lava-fire", "optimized-decorative")
        terrain.mask_allow_vulcanus("calcite", "resource")
        terrain.mask_allow_vulcanus("tungsten-ore", "resource")
        terrain.mask_allow_volcano("sulfuric-acid-geyser", "resource")

        data.raw["noise-expression"]["demolisher_starting_area"].expression = "mask_allow_vulcanus(if(volcano_mask > 0.2, 0, 1))"
        data.raw["noise-expression"]["demolisher_territory_expression"].expression = "mask_allow_vulcanus(" .. data.raw["noise-expression"]["demolisher_territory_expression"].expression .. ")" 
    end
}
