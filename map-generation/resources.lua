
local holmium_ore = settings.startup["eon-holmium-ore"].value

local resource_autoplace = require("resource-autoplace")
local base_sounds = require("__base__.prototypes.entity.sounds")
local simulations = require("__space-age__.prototypes.factoriopedia-simulations")


local stone_driving_sound = {
  sound = {
    filename = "__base__/sound/driving/vehicle-surface-stone.ogg", volume = 0.8,
    advanced_volume_control = {fades = {fade_in = {curve_type = "cosine", from = {control = 0.5, volume_percentage = 0.0}, to = {1.5, 100.0 }}}}
  },
  fade_ticks = 6
}


data.raw["autoplace-control"]["calcite"] = nil
data.raw["resource"]["calcite"] = nil
data.raw["autoplace-control"]["tungsten_ore"] = nil
data.raw["resource"]["tungsten-ore"] = nil


data:extend({
  {
    type = "autoplace-control",
    name = "calcite",
    localised_name = {"", "[entity=calcite] ", {"entity-name.calcite"}},
    richness = true,
    order = "b-c",
    category = "resource"
  },
  {
    type = "resource",
    name = "calcite",
    icon = "__space-age__/graphics/icons/calcite.png",
    flags = {"placeable-neutral"},
    order = "b",
    tree_removal_probability = 0.7,
    tree_removal_max_distance = 32 * 32,
    walking_sound = base_sounds.ore,
    driving_sound = stone_driving_sound,
    minable = {
      mining_particle = "stone-particle",  -- TODO: Add particle - There is an actual calcite-particle-1.png in space-age\graphics\particle\calcite-particle
      mining_time = 1,
      result = "calcite",
    },
    category = "hard-solid",
    collision_box = {{-0.1, -0.1}, {0.1, 0.1}},
    selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
    autoplace = resource_autoplace.resource_autoplace_settings {
      name = "calcite",
      order = "c-calcite",
      base_density = 0.8,
      base_spots_per_km2 = 1.5,
      has_starting_area_placement = false,
      random_spot_size_minimum = 2,
      random_spot_size_maximum = 4,
      regular_rq_factor_multiplier = 1
    },
    stage_counts = {15000, 9500, 5500, 2900, 1300, 400, 150, 80},
    stages = {
      sheet =
      {
        filename = "__space-age__/graphics/entity/calcite/calcite.png",
        priority = "extra-high",
        width = 128,
        height = 128,
        frame_count = 8,
        variation_count = 8,
        scale = 0.5
        }
    },
    effect_animation_period = 5,
    effect_animation_period_deviation = 1,
    effect_darkness_multiplier = 3.6,
    min_effect_alpha = 0.2,
    max_effect_alpha = 0.3,
    mining_visualisation_tint = {r = 0.99, g = 1.0, b = 0.92, a = 1.000},
    map_color = {0.8, 0.7, 0.7},
    factoriopedia_simulation = simulations.factoriopedia_calcite,
  },
  {
    type = "autoplace-control",
    name = "tungsten_ore",  -- This needs to have an underscore since the base game has it like that. This autoplace control replaces the existing in the game
    localised_name = {"", "[entity=tungsten-ore] ", {"entity-name.tungsten-ore"}},
    richness = true,
    order = "b-c",
    category = "resource"
  },
  {
    type = "resource",
    name = "tungsten-ore",
    icon = "__space-age__/graphics/icons/tungsten-ore.png",
    flags = {"placeable-neutral"},
    order = "b",
    tree_removal_probability = 0.7,
    tree_removal_max_distance = 32 * 32,
    walking_sound = base_sounds.ore,
    driving_sound = stone_driving_sound,
    minable = {
      mining_particle = "stone-particle",  -- TODO: Add particle - There is an actual tungsten-ore-particle-1.png in space-age\graphics\particle\tungsten-ore-particle
      mining_time = 5,
      result = "tungsten-ore",
    },
    category = "hard-solid",
    collision_box = {{-0.1, -0.1}, {0.1, 0.1}},
    selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
    autoplace = resource_autoplace.resource_autoplace_settings {
      name = "tungsten_ore",
      order = "c-tungsten",
      base_density = 0.4,
      base_spots_per_km2 = 1.25,
      has_starting_area_placement = false,
      random_spot_size_minimum = 2,
      random_spot_size_maximum = 4,
      regular_rq_factor_multiplier = 1
    },
    stage_counts = {15000, 9500, 5500, 2900, 1300, 400, 150, 80},
    stages = {
      sheet =
      {
        filename = "__space-age__/graphics/entity/tungsten-ore/tungsten-ore.png",
        priority = "extra-high",
        width = 128,
        height = 128,
        frame_count = 8,
        variation_count = 8,
        scale = 0.5
      }
    },
    effect_animation_period = 5,
    effect_animation_period_deviation = 1,
    effect_darkness_multiplier = 3.6,
    min_effect_alpha = 0.2,
    max_effect_alpha = 0.3,
    mining_visualisation_tint = {r = 150/256, g = 150/256, b = 180/256, a = 1.000},
    map_color = {r = 98/256, g = 86/256, b = 150/256, a = 1.000},
    factoriopedia_simulation = simulations.factoriopedia_tungsten_ore,
  },
})

-- Replace scrap with holmium-ore when enabled (default)
if holmium_ore then
  data:extend({
    {
      type = "autoplace-control",
      name = "holmium-ore",
      localised_name = {"", "[entity=holmium-ore] ", {"entity-name.holmium-ore"}},
      richness = true,
      order = "b-c",
      category = "resource"
    },
    {
      type = "resource",
      name = "holmium-ore",
      icon = "__space-age__/graphics/icons/holmium-ore.png",
      flags = {"placeable-neutral"},
      order = "a-b-e",
      tree_removal_probability = 0.7,
      tree_removal_max_distance = 32 * 32,
      walking_sound = base_sounds.ore,
      driving_sound = stone_driving_sound,
      minable = {
        mining_particle = "stone-particle",  -- TODO: Add particle - There is an actual holmium-ore-particle-1.png in space-age\graphics\particle\holmium-ore-particle
        mining_time = 2,
        result = "holmium-ore",
      },
      category = "hard-solid",
      collision_box = {{-0.1, -0.1}, {0.1, 0.1}},
      selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
      autoplace = resource_autoplace.resource_autoplace_settings {
        name = "holmium-ore",
        order = "c-holmium",
        base_density = 0.4,
        base_spots_per_km2 = 1.25,
        has_starting_area_placement = false,
        random_spot_size_minimum = 2,
        random_spot_size_maximum = 4,
        regular_rq_factor_multiplier = 1
      },
      stage_counts = {15000, 9500, 5500, 2900, 1300, 400, 150, 80},
      stages =
      {
        sheet =
        {
          filename = "__EverythingOnNauvis__/graphics/holmium-ore-patches.png",
          priority = "extra-high",
          width = 128,
          height = 128,
          frame_count = 8,
          variation_count = 8,
          scale = 0.5
        }
      },
      effect_animation_period = 5,
      effect_animation_period_deviation = 1,
      effect_darkness_multiplier = 3.6,
      min_effect_alpha = 0.2,
      max_effect_alpha = 0.3,
      mining_visualisation_tint = {r = 1, g = 0, b = 0.9, a = 1},
      map_color = {1, 0, 0.9}
    },
  })
end


data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["calcite"] = {}
data.raw.planet["nauvis"].map_gen_settings.autoplace_controls["tungsten_ore"] = {}
