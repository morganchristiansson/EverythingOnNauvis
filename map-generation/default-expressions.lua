--- This file creates "default" noise expressions for most entities in the game. The purpose of these expressions
--- which are name, for example "default_grass-1", etc, is to be used in masking functions further on.
--- We create default_grass-1 as a copied expression and then we will later mask it and replace the autoplace for the entity on
--- nauvis.
--- After this is done the "real" grass-1 tile will have the probability_expression that looks like mask(mask(mask(mask(default_grass-1))))

local util = require("data-util")

function noise_expression(name, dataType)
    local expression = {
        type = "noise-expression",
        name = util.generate_default_name(name),
        expression = data.raw[dataType][name].autoplace.probability_expression
    }
    if data.raw[dataType][name].autoplace.local_expressions then
        expression.local_expressions = data.raw[dataType][name].autoplace.local_expressions
    end
    return expression
end

data:extend({ -- START: Nauvis
    -- Nauvis resources
    noise_expression("iron-ore", "resource"), noise_expression("copper-ore", "resource"),
    noise_expression("stone", "resource"), noise_expression("coal", "resource"),
    noise_expression("uranium-ore", "resource"), noise_expression("crude-oil", "resource"), -- Nauvis tiles
    noise_expression("grass-1", "tile"), noise_expression("grass-2", "tile"), noise_expression("grass-3", "tile"),
    noise_expression("grass-4", "tile"), noise_expression("dry-dirt", "tile"), noise_expression("dirt-1", "tile"),
    noise_expression("dirt-2", "tile"), noise_expression("dirt-3", "tile"), noise_expression("dirt-4", "tile"),
    noise_expression("dirt-5", "tile"), noise_expression("dirt-6", "tile"), noise_expression("dirt-7", "tile"),
    noise_expression("sand-1", "tile"), noise_expression("sand-2", "tile"), noise_expression("sand-3", "tile"),
    noise_expression("red-desert-0", "tile"), noise_expression("red-desert-1", "tile"),
    noise_expression("red-desert-2", "tile"), noise_expression("red-desert-3", "tile"), noise_expression("water", "tile"),
    noise_expression("deepwater", "tile"), -- Nauvis decoratives
    noise_expression("big-rock", "simple-entity"), noise_expression("big-sand-rock", "simple-entity"),
    noise_expression("brown-asterisk", "optimized-decorative"),
    noise_expression("brown-asterisk-mini", "optimized-decorative"),
    noise_expression("brown-carpet-grass", "optimized-decorative"), noise_expression("brown-fluff",
    "optimized-decorative"),
    noise_expression("brown-fluff-dry", "optimized-decorative"),
    noise_expression("brown-hairy-grass", "optimized-decorative"),
    noise_expression("cracked-mud-decal", "optimized-decorative"),
    noise_expression("dark-mud-decal", "optimized-decorative"),
    --   noise_expression("enemy-decal", "optimized-decorative"),
    noise_expression("garballo", "optimized-decorative"), noise_expression("garballo-mini-dry", "optimized-decorative"),
    noise_expression("green-asterisk", "optimized-decorative"),
    noise_expression("green-asterisk-mini", "optimized-decorative"),
    noise_expression("green-bush-mini", "optimized-decorative"),
    noise_expression("green-carpet-grass", "optimized-decorative"),
    noise_expression("green-croton", "optimized-decorative"), noise_expression("green-desert-bush",
    "optimized-decorative"),
    noise_expression("green-hairy-grass", "optimized-decorative"), noise_expression("green-pita", "optimized-decorative"),
    noise_expression("green-pita-mini", "optimized-decorative"),
    noise_expression("green-small-grass", "optimized-decorative"), noise_expression("huge-rock", "simple-entity"),
    noise_expression("lichen-decal", "optimized-decorative"), noise_expression("light-mud-decal", "optimized-decorative"),
    noise_expression("medium-rock", "optimized-decorative"), noise_expression("medium-sand-rock", "optimized-decorative"),
    --   noise_expression("muddy-stump", "optimized-decorative"),
    --   noise_expression("nuclear-ground-patch", "optimized-decorative"),
    noise_expression("red-asterisk", "optimized-decorative"), noise_expression("red-croton", "optimized-decorative"),
    noise_expression("red-desert-bush", "optimized-decorative"),
    noise_expression("red-desert-decal", "optimized-decorative"), noise_expression("red-pita", "optimized-decorative"),
    noise_expression("sand-decal", "optimized-decorative"), noise_expression("sand-dune-decal", "optimized-decorative"),
    noise_expression("shroom-decal", "optimized-decorative"), noise_expression("small-rock", "optimized-decorative"),
    noise_expression("small-sand-rock", "optimized-decorative"), noise_expression("tiny-rock", "optimized-decorative"),
    noise_expression("white-desert-bush", "optimized-decorative"),
    --   noise_expression("worms-decal", "optimized-decorative"),
    -- END: Nauvis

    -- START: Aquilo
    -- Aquilo tiles
    noise_expression("snow-flat", "tile"), noise_expression("snow-crests", "tile"), noise_expression("snow-lumpy", "tile"),
    noise_expression("snow-patchy", "tile"), noise_expression("ice-rough", "tile"), noise_expression("ice-smooth", "tile"),
    noise_expression("brash-ice", "tile"), -- Aquilo decoratives
    noise_expression("lithium-iceberg-medium", "optimized-decorative"),
    noise_expression("lithium-iceberg-small", "optimized-decorative"),
    noise_expression("lithium-iceberg-tiny", "optimized-decorative"),
    noise_expression("floating-iceberg-large", "optimized-decorative"),
    noise_expression("floating-iceberg-small", "optimized-decorative"),
    noise_expression("aqulio-ice-decal-blue", "optimized-decorative"),
    noise_expression("aqulio-snowy-decal", "optimized-decorative"),
    noise_expression("snow-drift-decal", "optimized-decorative"), -- Aquilo entities
    noise_expression("lithium-brine", "resource"), noise_expression("fluorine-vent", "resource"),
    noise_expression("lithium-iceberg-huge", "simple-entity"), noise_expression("lithium-iceberg-big", "simple-entity"),
    -- END: Aquilo

    -- START: Gleba
    -- Gleba tiles
    noise_expression("natural-yumako-soil", "tile"), noise_expression("natural-jellynut-soil", "tile"),
    noise_expression("wetland-yumako", "tile"), noise_expression("wetland-jellynut", "tile"),
    noise_expression("wetland-blue-slime", "tile"), noise_expression("wetland-light-green-slime", "tile"),
    noise_expression("wetland-green-slime", "tile"), noise_expression("wetland-light-dead-skin", "tile"),
    noise_expression("wetland-dead-skin", "tile"), noise_expression("wetland-pink-tentacle", "tile"),
    noise_expression("wetland-red-tentacle", "tile"), noise_expression("gleba-deep-lake", "tile"),
    noise_expression("lowland-brown-blubber", "tile"), noise_expression("lowland-olive-blubber", "tile"),
    noise_expression("lowland-olive-blubber-2", "tile"), noise_expression("lowland-olive-blubber-2", "tile"),
    noise_expression("lowland-pale-green", "tile"), noise_expression("lowland-cream-cauliflower", "tile"),
    noise_expression("lowland-cream-cauliflower-2", "tile"), noise_expression("lowland-dead-skin", "tile"),
    noise_expression("lowland-dead-skin-2", "tile"), noise_expression("lowland-cream-red", "tile"),
    noise_expression("lowland-red-vein", "tile"), noise_expression("lowland-red-vein-2", "tile"),
    noise_expression("lowland-red-vein-3", "tile"), noise_expression("lowland-red-vein-4", "tile"),
    noise_expression("lowland-red-vein-dead", "tile"), noise_expression("lowland-red-infection", "tile"),
    noise_expression("midland-turquoise-bark", "tile"), noise_expression("midland-turquoise-bark-2", "tile"),
    noise_expression("midland-cracked-lichen", "tile"), noise_expression("midland-cracked-lichen-dull", "tile"),
    noise_expression("midland-cracked-lichen-dark", "tile"), noise_expression("midland-yellow-crust", "tile"),
    noise_expression("midland-yellow-crust-2", "tile"), noise_expression("midland-yellow-crust-3", "tile"),
    noise_expression("midland-yellow-crust-4", "tile"), noise_expression("highland-dark-rock", "tile"),
    noise_expression("highland-dark-rock-2", "tile"), noise_expression("highland-yellow-rock", "tile"),
    noise_expression("pit-rock", "tile"), -- Gleba decoratives
    noise_expression("yellow-lettuce-lichen-1x1", "optimized-decorative"),
    noise_expression("yellow-lettuce-lichen-3x3", "optimized-decorative"),
    noise_expression("yellow-lettuce-lichen-6x6", "optimized-decorative"),
    noise_expression("yellow-lettuce-lichen-cups-1x1", "optimized-decorative"),
    noise_expression("yellow-lettuce-lichen-cups-3x3", "optimized-decorative"),
    noise_expression("yellow-lettuce-lichen-cups-6x6", "optimized-decorative"),
    noise_expression("green-lettuce-lichen-1x1", "optimized-decorative"),
    noise_expression("green-lettuce-lichen-3x3", "optimized-decorative"),
    noise_expression("green-lettuce-lichen-6x6", "optimized-decorative"),
    noise_expression("green-lettuce-lichen-water-1x1", "optimized-decorative"),
    noise_expression("green-lettuce-lichen-water-3x3", "optimized-decorative"),
    noise_expression("green-lettuce-lichen-water-6x6", "optimized-decorative"),
    noise_expression("honeycomb-fungus", "optimized-decorative"),
    noise_expression("honeycomb-fungus-1x1", "optimized-decorative"),
    noise_expression("honeycomb-fungus-decayed", "optimized-decorative"),
    noise_expression("split-gill-1x1", "optimized-decorative"), noise_expression("split-gill-2x2", "optimized-decorative"),
    noise_expression("split-gill-dying-1x1", "optimized-decorative"),
    noise_expression("split-gill-dying-2x2", "optimized-decorative"),
    noise_expression("split-gill-red-1x1", "optimized-decorative"),
    noise_expression("split-gill-red-2x2", "optimized-decorative"), noise_expression("veins", "optimized-decorative"),
    noise_expression("veins-small", "optimized-decorative"), noise_expression("mycelium", "optimized-decorative"),
    noise_expression("coral-water", "optimized-decorative"), noise_expression("coral-land", "optimized-decorative"),
    noise_expression("black-sceptre", "optimized-decorative"), noise_expression("pink-phalanges", "optimized-decorative"),
    noise_expression("pink-lichen-decal", "optimized-decorative"),
    noise_expression("red-lichen-decal", "optimized-decorative"), noise_expression("green-cup", "optimized-decorative"),
    noise_expression("brown-cup", "optimized-decorative"), noise_expression("blood-grape", "optimized-decorative"),
    noise_expression("blood-grape-vibrant", "optimized-decorative"), noise_expression("brambles", "optimized-decorative"),
    noise_expression("polycephalum-slime", "optimized-decorative"),
    noise_expression("polycephalum-balloon", "optimized-decorative"),
    noise_expression("fuchsia-pita", "optimized-decorative"), noise_expression("wispy-lichen", "optimized-decorative"),
    noise_expression("grey-cracked-mud-decal", "optimized-decorative"),
    noise_expression("barnacles-decal", "optimized-decorative"), noise_expression("coral-stunted", "optimized-decorative"),
    noise_expression("coral-stunted-grey", "optimized-decorative"),
    noise_expression("red-nerve-roots-veins-dense", "optimized-decorative"),
    noise_expression("red-nerve-roots-veins-sparse", "optimized-decorative"),
    noise_expression("purple-nerve-roots-veins-dense", "optimized-decorative"),
    noise_expression("purple-nerve-roots-veins-sparse", "optimized-decorative"),
    noise_expression("cream-nerve-roots-veins-sparse", "optimized-decorative"),
    noise_expression("cream-nerve-roots-veins-dense", "optimized-decorative"),
    noise_expression("yellow-coral", "optimized-decorative"), noise_expression("solo-barnacle", "optimized-decorative"),
    noise_expression("curly-roots-orange", "optimized-decorative"),
    noise_expression("knobbly-roots", "optimized-decorative"),
    noise_expression("knobbly-roots-orange", "optimized-decorative"),
    noise_expression("matches-small", "optimized-decorative"),
    noise_expression("pale-lettuce-lichen-cups-1x1", "optimized-decorative"),
    noise_expression("pale-lettuce-lichen-cups-3x3", "optimized-decorative"),
    noise_expression("pale-lettuce-lichen-cups-6x6", "optimized-decorative"),
    noise_expression("pale-lettuce-lichen-1x1", "optimized-decorative"),
    noise_expression("pale-lettuce-lichen-3x3", "optimized-decorative"),
    noise_expression("pale-lettuce-lichen-6x6", "optimized-decorative"),
    noise_expression("pale-lettuce-lichen-water-1x1", "optimized-decorative"),
    noise_expression("pale-lettuce-lichen-water-3x3", "optimized-decorative"),
    noise_expression("pale-lettuce-lichen-water-6x6", "optimized-decorative"),
    noise_expression("white-carpet-grass", "optimized-decorative"),
    noise_expression("green-carpet-grass", "optimized-decorative"),
    noise_expression("green-hairy-grass", "optimized-decorative"),
    noise_expression("light-mud-decal", "optimized-decorative"), noise_expression("dark-mud-decal",
    "optimized-decorative"),
    noise_expression("cracked-mud-decal", "optimized-decorative"),
    noise_expression("red-desert-bush", "optimized-decorative"),
    noise_expression("white-desert-bush", "optimized-decorative"), noise_expression("red-pita", "optimized-decorative"),
    noise_expression("green-bush-mini", "optimized-decorative"), noise_expression("green-croton", "optimized-decorative"),
    noise_expression("green-pita", "optimized-decorative"), noise_expression("green-pita-mini", "optimized-decorative"),
    noise_expression("lichen-decal", "optimized-decorative"), noise_expression("shroom-decal", "optimized-decorative"),

    -- Gleba entities
    noise_expression("iron-stromatolite", "simple-entity"), noise_expression("copper-stromatolite", "simple-entity"),

    -- Gleba trees
    noise_expression("cuttlepop", "tree"), noise_expression("slipstack", "tree"), noise_expression("funneltrunk", "tree"),
    noise_expression("hairyclubnub", "tree"), noise_expression("teflilly", "tree"), noise_expression("lickmaw", "tree"),
    noise_expression("stingfrond", "tree"), noise_expression("boompuff", "tree"), noise_expression("sunnycomb", "tree"),
    noise_expression("water-cane", "tree"), -- END: Gleba
    -- START: Vulcanus
    -- Vulcanus tiles
    noise_expression("volcanic-ash-flats", "tile"), noise_expression("volcanic-ash-light", "tile"),
    noise_expression("volcanic-ash-dark", "tile"), noise_expression("volcanic-cracks", "tile"),
    noise_expression("volcanic-cracks-warm", "tile"), noise_expression("volcanic-folds-warm", "tile"),
    noise_expression("volcanic-pumice-stones", "tile"), noise_expression("volcanic-cracks-hot", "tile"),
    noise_expression("volcanic-jagged-ground", "tile"), noise_expression("volcanic-smooth-stone", "tile"),
    noise_expression("volcanic-smooth-stone-warm", "tile"), noise_expression("volcanic-ash-cracks", "tile"),

    -- Vulcanus decoratives - Note, most already exist as noise layer under some other name
    noise_expression("vulcanus-chimney", "simple-entity"), noise_expression("vulcanus-chimney-faded", "simple-entity"),
    noise_expression("vulcanus-chimney-cold", "simple-entity"), noise_expression("vulcanus-chimney-short",
    "simple-entity"),
    noise_expression("vulcanus-chimney-truncated", "simple-entity"),
    noise_expression("huge-volcanic-rock", "simple-entity"), noise_expression("big-volcanic-rock", "simple-entity"),
    noise_expression("vulcanus-rock-decal-large", "optimized-decorative"),
    noise_expression("vulcanus-crack-decal", "optimized-decorative"),
    noise_expression("vulcanus-crack-decal-large", "optimized-decorative"),
    noise_expression("vulcanus-crack-decal-huge-warm", "optimized-decorative"),
    noise_expression("vulcanus-crack-decal-warm", "optimized-decorative"),
    noise_expression("calcite-stain", "optimized-decorative"),
    noise_expression("calcite-stain-small", "optimized-decorative"),
    noise_expression("sulfur-stain", "optimized-decorative"),
    noise_expression("sulfur-stain-small", "optimized-decorative"),
    noise_expression("sulfuric-acid-puddle", "optimized-decorative"),
    noise_expression("sulfuric-acid-puddle-small", "optimized-decorative"),
    noise_expression("crater-small", "optimized-decorative"), noise_expression("crater-large", "optimized-decorative"),
    noise_expression("pumice-relief-decal", "optimized-decorative"),
    noise_expression("vulcanus-sand-decal", "optimized-decorative"),
    noise_expression("vulcanus-dune-decal", "optimized-decorative"),
    noise_expression("waves-decal", "optimized-decorative"),
    noise_expression("medium-volcanic-rock", "optimized-decorative"),
    noise_expression("small-volcanic-rock", "optimized-decorative"),
    noise_expression("tiny-volcanic-rock", "optimized-decorative"),
    noise_expression("tiny-rock-cluster", "optimized-decorative"),
    noise_expression("small-sulfur-rock", "optimized-decorative"),
    noise_expression("tiny-sulfur-rock", "optimized-decorative"),
    noise_expression("sulfur-rock-cluster", "optimized-decorative"),
    noise_expression("vulcanus-lava-fire", "optimized-decorative"), -- END: Vulcanus
    noise_expression("lava", "tile"),
    noise_expression("lava-hot", "tile"),
    noise_expression("volcanic-folds", "tile"),
    noise_expression("volcanic-folds-flat", "tile"),
    -- START: Custom
    noise_expression("calcite", "resource"), noise_expression("tungsten-ore", "resource"),
    noise_expression("scrap", "resource"), noise_expression("sulfuric-acid-geyser", "resource") })
