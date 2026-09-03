
local data_util = require("data-util")

local holmium_ore = settings.startup["eon-holmium-ore"].value


-- Fix tech tree

-- Add new technology for traveling to solar system edge
data:extend({
  {
    type = "technology",
    name = "solar-system-edge-discovery",
    icon = "__space-age__/graphics/icons/solar-system-edge.png",
    icon_size = 64,
    essential = true,
    effects =
    {
      {
        type = "unlock-space-location",
        space_location = "solar-system-edge",
        use_icon_overlay_constant = true
      },
      {
        type = "unlock-recipe",
        recipe = "ammoniacal-solution-separation",
      },
      {
        type = "unlock-recipe",
        recipe = "solid-fuel-from-ammonia"
      },
      {
        type = "unlock-recipe",
        recipe = "ammonia-rocket-fuel"
      },
      {
        type = "unlock-recipe",
        recipe = "ice-platform",
      },
      {
        type = "unlock-recipe",
        recipe = "lightning-rod",
      },
    },
    prerequisites = {"space-platform-thruster"},
    unit =
    {
      count = 500,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"space-science-pack", 1}
      },
      time = 60
    }
  },
})

-- Add prerequisite to promethium-science-pack
table.insert(data.raw.technology["promethium-science-pack"].prerequisites, "solar-system-edge-discovery")

-- Aquilo
data.raw.technology["lithium-processing"].prerequisites = {"rocket-turret", "advanced-asteroid-processing", "heating-tower", "asteroid-reprocessing", "electromagnetic-science-pack"}

-- Gleba
data.raw.technology["agriculture"].prerequisites = {"landfill", "steel-processing"}
data.raw.technology["heating-tower"].prerequisites = {"concrete"}

-- Fulgora
data.raw.technology["lightning-collector"].hidden = true
if holmium_ore then
  -- Scrap is gone, so holmium-processing must be triggered by mining holmium ore directly
  data.raw.technology["holmium-processing"].research_trigger = {type = "mine-entity", entity = "holmium-ore"}
end
data.raw.technology["recycling"].prerequisites = {"processing-unit", "production-science-pack"}
data.raw.technology["recycling"].research_trigger = nil
data.raw.technology["recycling"].unit = {
  count = 100,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"chemical-science-pack", 1},
    {"production-science-pack", 1}
  },
  time = 5
}

-- Useless technology
data_util.hide_prototype("technology", "rail-support-foundations")

-- Vulcanus
data.raw.technology["calcite-processing"].prerequisites = {"production-science-pack"}
data.raw.technology["calcite-processing"].research_trigger = nil
data.raw.technology["calcite-processing"].unit = {
  count = 100,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"chemical-science-pack", 1},
    {"production-science-pack", 1}
  },
  time = 5
}
data.raw.technology["tungsten-carbide"].prerequisites = {"production-science-pack"}
data.raw.technology["tungsten-carbide"].research_trigger = nil
data.raw.technology["tungsten-carbide"].unit = {
  count = 100,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"chemical-science-pack", 1},
    {"production-science-pack", 1}
  },
  time = 5
}
