--------------------------------------------------------------------------------
-- Fixes map generation for resources
--------------------------------------------------------------------------------
local terrain = require("map-generation.terrain")
local holmium_ore = settings.startup["eon-holmium-ore"].value

local data_util =
{
  table = {}
}

function data_util.spritesheets_to_pictures(spritesheets)
  local pictures = {}
  for _, spritesheet in pairs(spritesheets) do
    for i = 1, spritesheet.frame_count or 1, 1 do
      table.insert(pictures, data_util.sprite_load(spritesheet.path,
        {
          frame_index = i - 1,
          scale = spritesheet.scale or 0.5,
          dice_y = spritesheet.dice_y
        })
      )
    end
  end
  return pictures
end

--------------------------------------------------------------------------------
-- MARK: Fix Nauvis resources
--------------------------------------------------------------------------------

-- Remove resources spawning on ammonia ocean
-- Nauvis resources stay off volcano terrain and off Gleba territory entirely
-- (vanilla Gleba has none of these; stone is handled separately below).
-- Aquilo keeps only crude oil, lithium brine and fluorine vents: everything
-- else stays off aquilo land and ammonia ocean too. Crude oil is the
-- exception and keeps its aquilo presence.
terrain.mask_resource_territory_off_gleba("iron-ore", "resource")
terrain.mask_resource_territory_off_gleba("copper-ore", "resource")
terrain.mask_resource_territory_off_gleba("coal", "resource")
terrain.mask_resource_territory_off_gleba("uranium-ore", "resource")
terrain.mask_resource_territory_off_gleba("crude-oil", "resource")
for _, name in pairs({ "iron-ore", "copper-ore", "coal", "uranium-ore" }) do
  local current = data.raw.resource[name].autoplace.probability_expression
  data.raw.resource[name].autoplace.probability_expression =
      "eon_mask_off_aquilo_territory(eon_mask_off_ammonia_ocean(" .. current .. "))"
end

--------------------------------------------------------------------------------
-- MARK: Remove Aquilo resources to from Aquilo -- Dunno why i have to do this only for this planet...
--------------------------------------------------------------------------------

data.raw["noise-expression"]["aquilo_crude_oil_spots"].expression = "0"  --  This removes aquilo islands for crude oil
data.raw.planet["aquilo"].map_gen_settings.autoplace_controls = {nil}

--------------------------------------------------------------------------------
-- MARK: Add Fulgora resources to Nauvis
--------------------------------------------------------------------------------

if holmium_ore then
  -- Add holmium as ore
  data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["holmium-ore"] = {}
  data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["holmium-ore"] = {}
  terrain.mask_resource_territory_off_gleba("holmium-ore", "resource")
  do
    local current = data.raw.resource["holmium-ore"].autoplace.probability_expression
    data.raw.resource["holmium-ore"].autoplace.probability_expression =
        "eon_mask_off_aquilo_territory(eon_mask_off_ammonia_ocean(" .. current .. "))"
  end
else
  -- Keep scrap
  data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["scrap"] = {}
  data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["scrap"] = {}
  data.raw.resource["scrap"].autoplace.has_starting_area_placement = false  -- no scrap in the Nauvis starting area
  terrain.mask_resource_territory_off_gleba("scrap", "resource")
  do
    local current = data.raw.resource["scrap"].autoplace.probability_expression
    data.raw.resource["scrap"].autoplace.probability_expression =
        "eon_mask_off_aquilo_territory(eon_mask_off_ammonia_ocean(" .. current .. "))"
  end
end

--------------------------------------------------------------------------------
-- MARK: Gleba
--------------------------------------------------------------------------------

-- Vanilla Gleba has no iron-ore/copper-ore/coal/uranium-ore/crude-oil/scrap
-- (metals come from stromatolites); stone exists but small and sparse via the
-- gleba_stone control, which this mod deletes with the other planets.
-- Duplicate those expressions driven by the regular stone control instead, so
-- southern stone keeps vanilla Gleba's pattern at default settings with no
-- extra map-gen slider. Nauvis stone stays off Gleba, Gleba stone on it.
local eon_gleba_stone_richness = table.deepcopy(data.raw["noise-expression"]["gleba_stone_richness"])
eon_gleba_stone_richness.name = "eon_gleba_stone_richness"
eon_gleba_stone_richness.local_expressions.richness = "control:stone:richness"
eon_gleba_stone_richness.local_expressions.frequency = "control:stone:frequency"
eon_gleba_stone_richness.local_expressions.size = "control:stone:size"
data:extend({
  eon_gleba_stone_richness,
  {
    type = "noise-expression",
    name = "eon_gleba_stone_probability",
    expression = "(control:stone:size > 0) * (eon_gleba_stone_richness > 1)"
  },
})
local nauvis_stone_richness = data.raw.resource["stone"].autoplace.richness_expression
data.raw.resource["stone"].autoplace.probability_expression = "eon_mask_off_aquilo_territory(eon_mask_off_ammonia_ocean(if(eon_gleba_mask, eon_gleba_stone_probability, eon_mask_off_vulcano_terrain(eon_mask_resource_territory(eon_stone)))))"
data.raw.resource["stone"].autoplace.richness_expression = "if(eon_gleba_mask, eon_gleba_stone_richness, (" .. nauvis_stone_richness .. "))"

data.raw["autoplace-control"]["gleba_plants"].localised_description = {"autoplace-control-names.gleba_plants_description"}

--------------------------------------------------------------------------------
-- MARK: Add Vulcanus resources to Nauvis
--------------------------------------------------------------------------------

-- property_expression_names
data.raw.planet["nauvis"].map_gen_settings.property_expression_names["entity:sulfuric-acid-geyser:probability"] = "vulcanus_sulfuric_acid_geyser_probability"
data.raw.planet["nauvis"].map_gen_settings.property_expression_names["entity:sulfuric-acid-geyser:richness"] = "vulcanus_sulfuric_acid_geyser_richness"

-- Add calcite to volcanic rocks
table.insert(data.raw["simple-entity"]["big-volcanic-rock"].minable.results, {type = "item", name = "calcite", amount_min = 2, amount_max = 8})
table.insert(data.raw["simple-entity"]["huge-volcanic-rock"].minable.results, {type = "item", name = "calcite", amount_min = 3, amount_max = 15})

-- Set vulcane as resource
data.raw["autoplace-control"]["vulcanus_volcanism"].order = "z-volcanism"
data.raw["autoplace-control"]["vulcanus_volcanism"].localised_description = {"autoplace-control-names.vulcanus_volcanism_description"}
data.raw["autoplace-control"]["vulcanus_volcanism"].category = "resource"

-- reorder autoplace controls
data.raw["autoplace-control"]["sulfuric_acid_geyser"].order = "b-z"

-- Add resources to nauvis
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["calcite"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["sulfuric-acid-geyser"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_settings.entity.settings["tungsten-ore"] = {}

-- autoplace_controls
data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["sulfuric_acid_geyser"] = {}

-- Mask resources from ammonia ocean (and off aquilo land / gleba: calcite is a
-- volcano resource, not an aquilo/gleba one).
terrain.mask_resource_territory_allow_volcano("calcite", "resource")
do
  local current = data.raw.resource["calcite"].autoplace.probability_expression
  data.raw.resource["calcite"].autoplace.probability_expression =
      "eon_mask_off_aquilo_territory(eon_mask_off_ammonia_ocean(eon_mask_off_gleba_territory(" .. current .. ")))"
end
-- Tungsten is wired to volcano flanks below (not masked here).

-- START: Fix Resource spawning
data.raw.resource["calcite"].autoplace.has_starting_area_placement = false -- Does nothing but noise expression vulcanus_starting_calcite removes starter spot
data.raw["noise-expression"]["vulcanus_starting_calcite"].expression = "-inf"
data.raw["noise-expression"]["vulcanus_calcite_probability"].expression = "eon_mask_off_ammonia_ocean((control:calcite:size > 0) * (1000 * ((0.5 + vulcanus_calcite_region) * random_penalty_between(0.9, 1, 1) - 1)))"

data.raw.resource["sulfuric-acid-geyser"].autoplace.has_starting_area_placement = false -- Does nothing but noise expression vulcanus_starting_sulfur removes starter spot
data.raw["noise-expression"]["vulcanus_sulfuric_acid_geyser_probability"].expression = "(control:sulfuric_acid_geyser:size > 0) * (0.005 * ((vulcanus_sulfuric_acid_region_patchy > 0) + 2 * eon_updated_volcanic_folds))"
data.raw["noise-expression"]["vulcanus_starting_sulfur"].expression = "-inf"

data.raw.resource["tungsten-ore"].autoplace.has_starting_area_placement = false -- Does nothing but noise expression vulcanus_starting_tungsten removes starter spot
data.raw["noise-expression"]["vulcanus_starting_tungsten"].expression = "-inf"

-- Tungsten grows on inner volcano flanks, guarded by demolishers (vanilla
-- Vulcanus behavior): spots favor mineable ground inside volcano coverage
-- (folds ring, minus lava core and water -- not the outer folds-flat, so
-- patches stay inside demolisher territory). Ore never places on lava tiles
-- anyway, so no lava exclusion is needed. Patches are smaller and more
-- numerous than vanilla (half size, more candidates) so they fit the flanks.
-- Spot blobs centered near edges may spill onto neighboring tiles; that is
-- fine. There is no fallback: volcanism cannot be disabled, so every map
-- has volcanoes and therefore tungsten.
data:extend({
  {
    type = "noise-expression",
    name = "eon_volcano_lava_core",
    expression = "max(eon_lava_mountains_range, eon_lava_hot_mountains_range) > 0"
  },
  {
    type = "noise-expression",
    name = "eon_tungsten_volcano_favorability",
    expression = "if(eon_vulcano_coverage, if(eon_volcano_lava_core, 0, if(eon_updated_water <= 0, if(eon_updated_deepwater <= 0, 1, 0), 0)), 0)"
  },
  {
    -- Vanilla vulcanus_place_metal_spots directly: max() floors the favorability
    -- input at 0.25 so candidate density never starves thin volcano flanks
    -- (vanilla scales density by favor_biome, tuned for continent-sized basalt
    -- fields). The favorability gate (favor > 0.9) is unaffected by the floor
    -- (0.25 never passes it), so only flank spots survive, exactly as before --
    -- with no forked spot function to maintain.
    type = "noise-expression",
    name = "eon_tungsten_volcano_region",
    expression = "max(vulcanus_starting_tungsten, min(1 - vulcanus_starting_circle, vulcanus_place_metal_spots(789, 24, 2, vulcanus_tungsten_ore_size * (1 + 0.5 * min(distance / (1500 * eon_volcanism), 1)) * 12, control:tungsten_ore:frequency, max(eon_tungsten_volcano_favorability, 0.25))))"
  },
  {
    type = "noise-expression",
    name = "eon_tungsten_ore_region",
    expression = "eon_tungsten_volcano_region"
  },
})
-- NOTE: this replaces the dead vulcanus_tungsten_ore_probability override that
-- nothing referenced (tungsten spawned as plain Nauvis scatter). The vanilla
-- vulcanus expression is left untouched.
-- Richness must derive from the SAME region as probability (vanilla
-- Vulcanus does this too): entities only spawn where richness > 0, so the
-- old nauvis-style richness (default-patches pattern) silently vetoed every
-- volcano patch. Mirror vanilla vulcanus richness with our region.
-- Richness gradients with distance (exploration reward): near-spawn values match
-- the old formula, far volcanoes pay out more per tile; richness stays
-- region-wide since probability gates.
data.raw.resource["tungsten-ore"].autoplace.richness_expression = "eon_tungsten_ore_region * random_penalty_between(0.9, 1, 1) * 3500 * control:tungsten_ore:richness * (1 + min(distance / (1500 * eon_volcanism), 1)) / vulcanus_tungsten_ore_size"
data.raw.resource["tungsten-ore"].autoplace.probability_expression = "eon_mask_off_aquilo_territory(eon_mask_resource_territory(eon_mask_off_ammonia_ocean((control:tungsten_ore:size > 0) * (1000 * ((0.7 + eon_tungsten_ore_region) * random_penalty_between(0.9, 1, 1) - 1)))))"
-- END: Fix Resource spawning
