
local data_util = require("data-util")


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
data.raw.technology['promethium-science-pack'].unit.count_formula = nil
data.raw.technology['promethium-science-pack'].unit.count = 10

-- Useless technology
data_util.hide_prototype("technology", "rail-support-foundations")

-- Nauvis
data.raw.technology["destroyer"].prerequisites = {"distractor"}
data_util.remove_packs('destroyer', {'utility-science-pack'})
data_util.remove_packs('electric-weapons-damage-1', {'utility-science-pack'})
data_util.remove_packs('electric-weapons-damage-2', {'utility-science-pack', 'space-science-pack'})
data_util.remove_packs('electric-weapons-damage-3', {'utility-science-pack', 'space-science-pack'})
data_util.remove_packs('electric-weapons-damage-4', {'utility-science-pack', 'space-science-pack'})
data.raw.technology["uranium-ammo"].prerequisites = {"military-4", "uranium-processing"}
data.raw.technology["epic-quality"].prerequisites = {"quality-module", "space-science-pack"}
data.raw.technology["epic-quality"].unit = {
  count = 100,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"chemical-science-pack", 1},
    {"space-science-pack", 1}
  },
  time = 60
}
data.raw.technology["legendary-quality"].prerequisites = {"epic-quality","agricultural-science-pack"}
data.raw.technology["legendary-quality"].unit = {
  count = 250,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"chemical-science-pack", 1},
    {"space-science-pack", 1},
    {"agricultural-science-pack", 1},
  },
  time = 60
}
data.raw.technology["kovarex-enrichment-process"].prerequisites = {"uranium-processing"}
data_util.remove_packs("kovarex-enrichment-process", {'space-science-pack'})

-- Gleba
data.raw.technology["landfill"].prerequisites = nil
data.raw.technology["landfill"].unit = nil
data.raw.technology["landfill"].research_trigger = {
  type = "mine-entity",
  entity = "stone"
}
data.raw.technology["steel-processing"].prerequisites = nil
data.raw.technology["steel-processing"].unit = nil
data.raw.technology["steel-processing"].research_trigger = {
  type = "craft-item",
  item = "iron-plate",
  count = 200
}
data.raw.technology["agriculture"].prerequisites = {"landfill", "steel-processing"}
data.raw.technology['heating-tower'].prerequisites = {"concrete"}
data.raw.technology['heating-tower'].research_trigger = nil
data.raw.technology['heating-tower'].unit = {
  count = 500,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1}
  },
  time = 30
}
data.raw.technology["carbon-fiber"].prerequisites = {"agricultural-science-pack", "logistic-science-pack"}
data_util.remove_packs("carbon-fiber", {"chemical-science-pack", "space-science-pack"})
data_util.remove_packs("toolbelt-equipment", {"space-science-pack"})
data.raw.technology["stack-inserter"].prerequisites = {"carbon-fiber", "production-science-pack", "bulk-inserter"}
data_util.remove_packs("stack-inserter", {"space-science-pack","utility-science-pack"})
data.raw.technology['stack-inserter'].unit.count = 100
data.raw.technology["advanced-asteroid-processing"].prerequisites = {"agricultural-science-pack", "space-science-pack"}
data_util.remove_packs("advanced-asteroid-processing", {"utility-science-pack", "production-science-pack"})
data_util.remove_packs("transport-belt-capacity-1", {"space-science-pack","utility-science-pack"})
data.raw.technology['transport-belt-capacity-1'].unit.count = 200
data_util.remove_packs("transport-belt-capacity-2", {"space-science-pack","utility-science-pack"})
data.raw.technology['transport-belt-capacity-2'].unit.count = 300
data_util.remove_packs("rocket-turret", {"chemical-science-pack", "space-science-pack"})
data.raw.technology['captivity'].prerequisites = {"agricultural-science-pack","rocketry"}
data.raw.technology['captivity'].unit = {
  count = 150,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"agricultural-science-pack", 1}
  },
  time = 10
}
data.raw.technology['biolab'].prerequisites = {"biter-egg-handling","kovarex-enrichment-process"}
data.raw.technology['biolab'].unit = {
  count = 200,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"chemical-science-pack", 1},
    {"agricultural-science-pack", 1}
  },
  time = 30
}
data.raw.technology['overgrowth-soil'].prerequisites = {"biter-egg-handling"}
data.raw.technology['overgrowth-soil'].unit = {
  count = 75,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"agricultural-science-pack", 1}
  },
  time = 5
}

-- Fulgora
data.raw.technology.recycling.prerequisites = {}
data.raw.technology.recycling.research_trigger = {
  type = "mine-entity",
  entity = "scrap"
}
data.raw.technology['holmium-processing'].prerequisites = {'recycling', 'oil-processing'}
data.raw.technology['electromagnetic-plant'].prerequisites = {'holmium-processing'}
data.raw.technology['tesla-weapons'].prerequisites = {"electromagnetic-science-pack", "military-3"}
data_util.remove_packs("tesla-weapons", {"space-science-pack", "utility-science-pack"})

-- Vulcanus
data.raw.technology['calcite-processing'].prerequisites = {}
table.insert(data.raw.technology['calcite-processing'].effects, { type="unlock-recipe", recipe="oil-refinery" })
table.insert(data.raw.technology['calcite-processing'].effects, { type="unlock-recipe", recipe="chemical-plant" })
table.insert(data.raw.technology['calcite-processing'].effects, { type="unlock-recipe", recipe="lubricant" })
data.raw.technology['tungsten-carbide'].prerequisites = {}
data.raw.technology['big-mining-drill'].prerequisites = {'foundry', 'electric-mining-drill', 'electric-engine'}

-- Aquilo
data.raw.technology['lithium-processing'].prerequisites = {'holmium-processing'}
data.raw.technology['cryogenic-plant'].prerequisites = {'lithium-processing'}
table.insert(data.raw.technology['cryogenic-plant'].effects, { type="unlock-recipe", recipe="ammoniacal-solution-separation" })
table.insert(data.raw.technology['cryogenic-plant'].effects, { type="unlock-recipe", recipe="solid-fuel-from-ammonia" })
table.insert(data.raw.technology['cryogenic-plant'].effects, { type="unlock-recipe", recipe="ammonia-rocket-fuel" })
table.insert(data.raw.technology['cryogenic-plant'].effects, { type="unlock-recipe", recipe="ice-platform" })
data.raw.technology['quantum-processor'].prerequisites = {'cryogenic-plant', 'electromagnetic-plant', 'carbon-fiber','tungsten-carbide'}
data.raw.technology['railgun'].prerequisites = {"quantum-processor", "military-3"}
data.raw.technology['captive-biter-spawner'].prerequisites = {"biter-egg-handling","kovarex-enrichment-process"}
data_util.remove_packs("quantum-processor", {'cryogenic-science-pack', "utility-science-pack", 'production-science-pack', 'space-science-pack', 'agricultural-science-pack'})
data_util.remove_packs("railgun", {'space-science-pack', 'cryogenic-science-pack', 'utility-science-pack', 'agricultural-science-pack'})
data_util.remove_packs("captive-biter-spawner", {'space-science-pack', 'cryogenic-science-pack'})
data_util.remove_packs("fusion-reactor", {'cryogenic-science-pack', 'utility-science-pack', 'space-science-pack', 'agricultural-science-pack'})
data_util.remove_packs("fusion-reactor-equipment", {'cryogenic-science-pack', 'space-science-pack', 'agricultural-science-pack'})

--end
data.raw.technology['research-productivity'].prerequisites = {"biolab"}
data.raw.technology['research-productivity'].unit = {
  count_formula = "100 + 100 * L",
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"chemical-science-pack", 1},
    {"agricultural-science-pack", 1}
  },
  time = 120
}

-- mid and late game science cost reductions
data.raw.technology['tesla-weapons'].unit.count = 250
data.raw.technology['uranium-ammo'].unit.count = 50
data.raw.technology['kovarex-enrichment-process'].unit.count = 75
data.raw.technology['spidertron'].unit.count = 500
data.raw.technology['nuclear-power'].unit.count = 250
data.raw.technology['asteroid-reprocessing'].unit.count = 100
data.raw.technology['advanced-asteroid-processing'].unit.count = 200
data.raw.technology['rocket-turret'].unit.count = 200
data.raw.technology['low-density-structure'].unit.count = 75
data.raw.technology['processing-unit'].unit.count = 75
data.raw.technology['rocket-fuel'].unit.count = 75
data.raw.technology['rocket-silo'].unit.count = 225
data.raw.technology['captive-biter-spawner'].unit.count = 500
data.raw.technology['railgun'].unit.count = 300
data.raw.technology['quantum-processor'].unit.count = 200
data.raw.technology['fusion-reactor'].unit.count = 800
data.raw.technology['fusion-reactor-equipment'].unit.count = 200
data.raw.technology['quality-module'].unit.count = 50
data.raw.technology['quality-module-2'].unit.count = 200
data.raw.technology['quality-module-3'].unit.count = 300
data.raw.technology['speed-module-3'].unit.count = 300
data.raw.technology['carbon-fiber'].unit.count = 50
data.raw.technology['stack-inserter'].unit.count = 200
data.raw.technology['transport-belt-capacity-1'].unit.count = 250
data.raw.technology['transport-belt-capacity-2'].unit.count = 500
data.raw.technology['military-4'].unit.count = 50
data.raw.technology['distractor'].unit.count = 100
data.raw.technology['destroyer'].unit.count = 200
data.raw.technology['electric-weapons-damage-1'].unit.count = 100
data.raw.technology['electric-weapons-damage-2'].unit.count = 200
data.raw.technology['electric-weapons-damage-3'].unit.count = 300
data.raw.technology['electric-weapons-damage-4'].unit.count_formula = "500 * (L - 3)"


-- change triggers for planetary science packs into research to stall them a little compared to walls
table.insert(data.raw.technology['agricultural-science-pack'].prerequisites, "logistic-science-pack")
data.raw.technology["agricultural-science-pack"].research_trigger = nil
data.raw.technology['agricultural-science-pack'].unit = {
  count = 50,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1}
  },
  time = 10
}
table.insert(data.raw.technology['metallurgic-science-pack'].prerequisites, "chemical-science-pack")
data.raw.technology["metallurgic-science-pack"].research_trigger = nil
data.raw.technology['metallurgic-science-pack'].unit = {
  count = 50,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"chemical-science-pack", 1}
  },
  time = 30
}
table.insert(data.raw.technology['electromagnetic-science-pack'].prerequisites, "chemical-science-pack")
data.raw.technology["electromagnetic-science-pack"].research_trigger = nil
data.raw.technology['electromagnetic-science-pack'].unit = {
  count = 50,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"chemical-science-pack", 1}
  },
  time = 30
}
table.insert(data.raw.technology['cryogenic-science-pack'].prerequisites, "agricultural-science-pack")
data.raw.technology["cryogenic-science-pack"].research_trigger = nil
data.raw.technology['cryogenic-science-pack'].unit = {
  count = 100,
  ingredients = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"agricultural-science-pack", 1}
  },
  time = 15
}


--set damage modifiers (previously Functions.combat_balance in scenario)
local technology_names = {
  'physical-projectile-damage-1',
  'physical-projectile-damage-2',
  'physical-projectile-damage-3',
  'physical-projectile-damage-4',
  'physical-projectile-damage-5',
  'physical-projectile-damage-6',
  'physical-projectile-damage-7'
}
for _,technology in pairs(technology_names) do
  --  local effect_to_remove
  for i,effect in pairs(data.raw.technology[technology].effects) do
    if effect.type == 'turret-attack' and effect.turret_id == 'gun-turret' then
      if technology == 'physical-projectile-damage-1' then effect.modifier = 0.2
      elseif technology == 'physical-projectile-damage-2' then effect.modifier = 0.3
      else effect.modifier = 0.5
      end
    elseif effect.type == 'ammo-damage' and effect.ammo_category == 'bullet' then
      if technology == 'physical-projectile-damage-1' then effect.modifier = 0.2
      elseif technology == 'physical-projectile-damage-2' then effect.modifier = 0.3
      elseif technology == 'physical-projectile-damage-3' then effect.modifier = 0.4
      else effect.modifier = 0.1
      end
    elseif effect.type == 'ammo-damage' and effect.ammo_category == 'shotgun-shell' then
      effect.modifier = 0.6
    end
  end
  --  if effect_to_remove ~= nil then table.remove(data.raw.technology[technology].effects, effect_to_remove) end
end

local technology_names = {
  'refined-flammables-1',
  'refined-flammables-2',
  'refined-flammables-3',
  'refined-flammables-4',
  'refined-flammables-5',
  'refined-flammables-6',
  'refined-flammables-7'
}
for _,technology in pairs(technology_names) do
  for i,effect in pairs(data.raw.technology[technology].effects) do
    if effect.type == 'turret-attack' then
      effect.modifier = 0.02
    end
    if effect.type == 'ammo-damage' then
      if technology == 'refined-flammables-1' then effect.modifier = 0.2
      elseif technology == 'refined-flammables-2' then effect.modifier = 0.3
      else effect.modifier = 0.5
      end
    end
  end
end

local technology_names = {
  'stronger-explosives-1',
  'stronger-explosives-2',
  'stronger-explosives-3',
  'stronger-explosives-4',
  'stronger-explosives-5',
  'stronger-explosives-6',
  'stronger-explosives-7'
}
for _,technology in pairs(technology_names) do
  for i,effect in pairs(data.raw.technology[technology].effects) do
    if effect.type == 'ammo-damage' and effect.ammo_category == 'grenade' then
      effect.modifier = 0.5
    end
  end
  if technology == 'stronger-explosives-3' then table.insert(data.raw.technology[technology].effects, {type="turret-attack",turret_id="rocket-turret",modifier=0.5}) end
  if technology == 'stronger-explosives-4' then table.insert(data.raw.technology[technology].effects, {type="turret-attack",turret_id="rocket-turret",modifier=0.5}) end
  if technology == 'stronger-explosives-5' then table.insert(data.raw.technology[technology].effects, {type="turret-attack",turret_id="rocket-turret",modifier=0.5}) end
  if technology == 'stronger-explosives-6' then table.insert(data.raw.technology[technology].effects, {type="turret-attack",turret_id="rocket-turret",modifier=0.5}) end
  if technology == 'stronger-explosives-7' then table.insert(data.raw.technology[technology].effects, {type="turret-attack",turret_id="rocket-turret",modifier=0.5}) end
end

local technology_names = {
  'laser-weapons-damage-1',
  'laser-weapons-damage-2',
  'laser-weapons-damage-3',
  'laser-weapons-damage-4',
  'laser-weapons-damage-5',
  'laser-weapons-damage-6',
  'laser-weapons-damage-7'
}
local laser_turret_modifier = 0.1
for _,technology in pairs(technology_names) do
  table.insert(data.raw.technology[technology].effects, {type="turret-attack",turret_id="laser-turret",modifier=laser_turret_modifier})
  laser_turret_modifier = laser_turret_modifier + 0.1
end

local technology_names = {
  'electric-weapons-damage-3',
  'electric-weapons-damage-4'
}
for _,technology in pairs(technology_names) do
  for i,effect in pairs(data.raw.technology[technology].effects) do
    if effect.type == 'ammo-damage' and effect.ammo_category == 'tesla' then
      effect.modifier = 1.2
    end
  end
  table.insert(data.raw.technology[technology].effects, {type="turret-attack",turret_id="tesla-turret",modifier=0.75})
end

--change base damage
for _,effect in pairs(data.raw.ammo['uranium-rounds-magazine'].ammo_type.action.action_delivery.target_effects) do
  if effect.type == 'damage' then effect.damage.amount = 48 end
end
data.raw.projectile['piercing-shotgun-pellet'].action.action_delivery.target_effects.damage.amount = 12

--change quality modules
data.raw.module['speed-module'].effect = { speed = 0.2, consumption = 0.5, quality = -0.5 }
data.raw.module['speed-module-2'].effect = { speed = 0.3, consumption = 0.6, quality = -1.5 }
data.raw.module['speed-module-3'].effect = { speed = 0.5, consumption = 0.7, quality = -2.5 }
data.raw.module['quality-module'].effect = { quality = 0.4, speed = -0.05 }
data.raw.module['quality-module-2'].effect = { quality = 0.6, speed = -0.1 }
data.raw.module['quality-module-3'].effect = { quality = 1, speed = -0.2 }




data:extend({
    {
		type = "item",
        name = "concrete-wall",
		place_result = "concrete-wall",
		icon = "__space-age-biter-battles__/graphics/icons/concrete-wall.png",
		icon_size = 64,
		icon_mipmaps = 4,
		subgroup = "defensive-structure",
		order = "a[stone-wall]-b[concrete]",
		stack_size = 100,
	}
})

data:extend({
	{
		type = "recipe",
		name = "concrete-wall",
		enabled = false,
		energy_required = 0.5,
		ingredients = {
		    {type = "item", name = "concrete", amount = 20}
		},
		results = { { type = "item", name = "concrete-wall", amount_min = 1, amount_max = 1 } }
	}
})

local stronger_wall = util.table.deepcopy(data.raw.wall["stone-wall"])
    stronger_wall.name = "concrete-wall"
    stronger_wall.icon = "__space-age-biter-battles__/graphics/icons/concrete-wall.png"
    stronger_wall.minable.result = "concrete-wall"
    stronger_wall.max_health = 550
    stronger_wall.resistances = {
      {
        type = "physical",
        decrease = 7,
        percent = 40
      },
      {
        type = "impact",
        decrease = 90,
        percent = 80
      },
      {
        type = "explosion",
        percent = 100
      },
      {
        type = "fire",
        percent = 100
      },
      {
        type = "acid",
		decrease = 0,
        percent = 90
      },
      {
        type = "laser",
        percent = 80
      }
    }
    stronger_wall.pictures.single.layers[1].filename = "__space-age-biter-battles__/graphics/concrete-wall/wall-single.png"
    stronger_wall.pictures.single.layers[1].width = 32
    stronger_wall.pictures.single.layers[1].height = 46
    stronger_wall.pictures.single.layers[1].scale = 1
    stronger_wall.pictures.single.layers[1].shift = {0, -6 / 32}
    stronger_wall.pictures.straight_vertical.layers[1].filename = "__space-age-biter-battles__/graphics/concrete-wall/wall-vertical.png"
    stronger_wall.pictures.straight_vertical.layers[1].width = 32
    stronger_wall.pictures.straight_vertical.layers[1].height = 68
    stronger_wall.pictures.straight_vertical.layers[1].scale = 1
    stronger_wall.pictures.straight_vertical.layers[1].shift = {0, 9 / 32}
    stronger_wall.pictures.straight_horizontal.layers[1].filename = "__space-age-biter-battles__/graphics/concrete-wall/wall-horizontal.png"
    stronger_wall.pictures.straight_horizontal.layers[1].width = 32
    stronger_wall.pictures.straight_horizontal.layers[1].height = 50
    stronger_wall.pictures.straight_horizontal.layers[1].scale = 1
    stronger_wall.pictures.straight_horizontal.layers[1].shift = {0, -4 / 32}
    stronger_wall.pictures.corner_right_down.layers[1].filename = "__space-age-biter-battles__/graphics/concrete-wall/wall-corner-right.png"
    stronger_wall.pictures.corner_right_down.layers[1].width = 32
    stronger_wall.pictures.corner_right_down.layers[1].height = 64
    stronger_wall.pictures.corner_right_down.layers[1].scale = 1
    stronger_wall.pictures.corner_right_down.layers[1].shift = {0, 6 / 32}
    stronger_wall.pictures.corner_left_down.layers[1].filename = "__space-age-biter-battles__/graphics/concrete-wall/wall-corner-left.png"
    stronger_wall.pictures.corner_left_down.layers[1].width = 32
    stronger_wall.pictures.corner_left_down.layers[1].height = 68
    stronger_wall.pictures.corner_left_down.layers[1].scale = 1
    stronger_wall.pictures.corner_left_down.layers[1].shift = {0, 6 / 32}
    stronger_wall.pictures.t_up.layers[1].filename = "__space-age-biter-battles__/graphics/concrete-wall/wall-t.png"
    stronger_wall.pictures.t_up.layers[1].width = 32
    stronger_wall.pictures.t_up.layers[1].height = 64
    stronger_wall.pictures.t_up.layers[1].scale = 1
    stronger_wall.pictures.t_up.layers[1].shift = {0, 4 / 32}
    stronger_wall.pictures.ending_right.layers[1].filename = "__space-age-biter-battles__/graphics/concrete-wall/wall-ending-right.png"
    stronger_wall.pictures.ending_right.layers[1].width = 32
    stronger_wall.pictures.ending_right.layers[1].height = 48
    stronger_wall.pictures.ending_right.layers[1].scale = 1
    stronger_wall.pictures.ending_right.layers[1].shift = {0, -4 / 32}
    stronger_wall.pictures.ending_left.layers[1].filename = "__space-age-biter-battles__/graphics/concrete-wall/wall-ending-left.png"
    stronger_wall.pictures.ending_left.layers[1].width = 32
    stronger_wall.pictures.ending_left.layers[1].height = 48
    stronger_wall.pictures.ending_left.layers[1].scale = 1
    stronger_wall.pictures.ending_left.layers[1].shift = {0, -4 / 32}
    stronger_wall.pictures.water_connection_patch.sheets[1].filename = "__space-age-biter-battles__/graphics/concrete-wall/wall-patch.png"
    stronger_wall.pictures.water_connection_patch.sheets[1].width = 58
    stronger_wall.pictures.water_connection_patch.sheets[1].height = 64
    stronger_wall.pictures.water_connection_patch.sheets[1].scale = 1
    stronger_wall.pictures.water_connection_patch.sheets[1].shift = {0, -2 / 32}
    stronger_wall.pictures.filling.filename = "__space-age-biter-battles__/graphics/concrete-wall/wall-filling.png"
    stronger_wall.pictures.filling.width = 24
    stronger_wall.pictures.filling.height = 28
    stronger_wall.pictures.filling.scale = 1
    stronger_wall.pictures.filling.shift = {0, -3 / 32}

data:extend({stronger_wall})

local tech_stronger_wall = util.table.deepcopy(data.raw["technology"]["stone-wall"])
tech_stronger_wall.name = "concrete-wall"
tech_stronger_wall.icon = "__space-age-biter-battles__/graphics/technology/concrete-wall.png"
tech_stronger_wall.effects = {{type = "unlock-recipe", recipe = "concrete-wall"}}
tech_stronger_wall.prerequisites = {"stone-wall", "concrete","metallurgic-science-pack"}
tech_stronger_wall.unit = {
    count = 50, 
    time = 15, 
    ingredients = {
        {"automation-science-pack", 1}, 
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"metallurgic-science-pack", 1}
    }
}
tech_stronger_wall.order = "a-k-a-b"

data:extend({tech_stronger_wall})

data.raw["wall"]['stone-wall'].next_upgrade = "concrete-wall"
