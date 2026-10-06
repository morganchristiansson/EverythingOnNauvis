local data_util = require("data-util")

-- The four non-Nauvis planets.
--
-- Setting eon-restore-space-locations ON (default): they come back as SPACE
-- LOCATIONS -- the same prototype as solar-system-edge and shattered-planet, which
-- is the engine's native "you can travel here but never land". Starmap position,
-- asteroid fields and the vanilla trip graph (nauvis -> vulcanus/gleba/fulgora ->
-- aquilo -> solar-system-edge) are all restored; only surfaces are not: nothing
-- exists to land on but Nauvis. The planet prototypes are deleted outright (less
-- data, and nothing but the deleted technologies referenced them).
--
-- Setting OFF: the old behavior -- planets hidden, map_gen_settings nilled, every
-- interplanetary connection deleted, the one trip being straight from Nauvis to
-- the solar-system edge.
local OTHER_PLANETS = { "vulcanus", "gleba", "fulgora", "aquilo" }
local restore_locations = settings.startup["eon-restore-space-locations"].value

if restore_locations then
  -- Re-add each planet as a space-location carrying its starmap/asteroid fields.
  local locations = {}
  for _, name in ipairs(OTHER_PLANETS) do
    local p = data.raw.planet[name]
    if p then
      locations[#locations + 1] = {
        type = "space-location",
        name = name,
        icon = p.icon,
        starmap_icon = p.starmap_icon,
        starmap_icon_size = p.starmap_icon_size,
        order = p.order,
        subgroup = p.subgroup,
        gravity_pull = p.gravity_pull,
        distance = p.distance,
        orientation = p.orientation,
        magnitude = p.magnitude,
        label_orientation = p.label_orientation,
        asteroid_spawn_influence = p.asteroid_spawn_influence,
        asteroid_spawn_definitions = p.asteroid_spawn_definitions,
      }
      data_util.delete_prototype("planet", name)
    end
  end
  data:extend(locations)

  -- The vanilla trip graph, kept (the 7 interplanetary connections below are
  -- only deleted in the off branch), and the edge again only reachable from
  -- Aquilo: the first voyage is the normal easy nauvis->vulcanus/gleba/fulgora
  -- kind, and the nasty edge trip stays a late-game, Aquilo-gated one.
  data.raw["space-connection"]["aquilo-solar-system-edge"].from = "aquilo"
else
  for _, name in ipairs(OTHER_PLANETS) do
    if data.raw.planet[name] then
      data.raw.planet[name].map_gen_settings = nil
      data.raw.planet[name].hidden = true
    end
  end

  -- delete space connections
  data_util.delete_prototype("space-connection", "nauvis-vulcanus")
  data_util.delete_prototype("space-connection", "nauvis-gleba")
  data_util.delete_prototype("space-connection", "nauvis-fulgora")
  data_util.delete_prototype("space-connection", "vulcanus-gleba")
  data_util.delete_prototype("space-connection", "gleba-fulgora")
  data_util.delete_prototype("space-connection", "gleba-aquilo")
  data_util.delete_prototype("space-connection", "fulgora-aquilo")
  data.raw["space-connection"]["aquilo-solar-system-edge"].from = "nauvis"
  -- data_util.delete_prototype("space-connection", "aquilo-solar-system-edge")
end

-- Every space-platform request defaults to the planet of its item's
-- default_import_location, and all of those point at planets that no longer
-- exist (e.g. railgun-turret defaults to aquilo). Only Nauvis is left.
for _, types in pairs(data.raw) do
  if type(types) == "table" then
    for _, proto in pairs(types) do
      if type(proto) == "table" and proto.default_import_location then
        proto.default_import_location = "nauvis"
      end
    end
  end
end

-- remove space age menu simulations that break
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_solar_power_construction = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_lab = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_burner_city = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_mining_defense = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_forest_fire = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_oil_pumpjacks = nil  -- Safe simulations
data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_oil_refinery = nil
data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_early_smelting = nil  -- This one crashes after it finishes
data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_train_station = nil
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_logistic_robots = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_nuclear_power = nil  -- Safe simulations
data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_train_junction = nil
data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_artillery = nil
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_biter_base_spidertron = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_biter_base_artillery = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_biter_base_laser_defense = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_biter_base_player_attack = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_biter_base_steamrolled = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_chase_player = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_big_defense = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_brutal_defeat = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_spider_ponds = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_uranium_processing = nil  -- Safe simulations

-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_ship_rails = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_river_bridge = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_t_section = nil  -- Safe simulations

-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_biolab = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_tank_building = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_power_up = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_bus = nil  -- Safe simulations
-- data.raw["utility-constants"]["default"].main_menu_simulations.platform_science = nil  -- Safe simulations
data.raw["utility-constants"]["default"].main_menu_simulations.platform_moving = nil
data.raw["utility-constants"]["default"].main_menu_simulations.platform_messy_nuclear = nil
data.raw["utility-constants"]["default"].main_menu_simulations.vulcanus_lava_forge = nil
data.raw["utility-constants"]["default"].main_menu_simulations.vulcanus_crossing = nil
data.raw["utility-constants"]["default"].main_menu_simulations.vulcanus_punishmnent = nil
data.raw["utility-constants"]["default"].main_menu_simulations.vulcanus_sulfur_drop = nil
data.raw["utility-constants"]["default"].main_menu_simulations.gleba_agri_towers = nil
data.raw["utility-constants"]["default"].main_menu_simulations.gleba_pentapod_ponds = nil
data.raw["utility-constants"]["default"].main_menu_simulations.gleba_egg_escape = nil
data.raw["utility-constants"]["default"].main_menu_simulations.gleba_farm_attack = nil
data.raw["utility-constants"]["default"].main_menu_simulations.gleba_grotto = nil
data.raw["utility-constants"]["default"].main_menu_simulations.fulgora_city_crossing = nil
data.raw["utility-constants"]["default"].main_menu_simulations.fulgora_recycling_hell = nil
data.raw["utility-constants"]["default"].main_menu_simulations.fulgora_nightfall = nil
data.raw["utility-constants"]["default"].main_menu_simulations.fulgora_race = nil
data.raw["utility-constants"]["default"].main_menu_simulations.aquilo_send_help = nil
data.raw["utility-constants"]["default"].main_menu_simulations.aquilo_starter = nil
data.raw["utility-constants"]["default"].main_menu_simulations.nauvis_rocket_factory = nil

-- Delete atomic-bomb ground effects for deleted planets (yoinked from
-- EverythingOnNauvis-Patches, which filters them out of atomic-rocket instead).
-- Aquilo and Vulcanus no longer exist as surfaces (deleted planets, or unlandable
-- space-locations with eon-restore-space-locations), so nuke-effects-aquilo
-- (ammoniacal-ocean) and nuke-effects-vulcanus (lava) can never legally trigger.
-- Deleting them is
-- better than gating them behind surface conditions: the bomb then always
-- leaves nuclear ground on Nauvis. nuke-effects-space (space platforms) and
-- nuke-effects-nauvis are kept.
local atomic_rocket = data.raw["projectile"] and data.raw["projectile"]["atomic-rocket"]
if atomic_rocket
    and atomic_rocket.action
    and atomic_rocket.action.action_delivery
    and atomic_rocket.action.action_delivery.target_effects
then
    local remove = {
        ["nuke-effects-vulcanus"] = true,
        ["nuke-effects-aquilo"] = true,
    }

    local filtered = {}
    for _, effect in ipairs(atomic_rocket.action.action_delivery.target_effects) do
        if not (effect.type == "create-entity" and remove[effect.entity_name]) then
            table.insert(filtered, effect)
        end
    end

    atomic_rocket.action.action_delivery.target_effects = filtered
end
data_util.delete_prototype("explosion", "nuke-effects-aquilo")
data_util.delete_prototype("explosion", "nuke-effects-vulcanus")

-- delete technologies
data_util.hide_prototype("technology", "planet-discovery-aquilo")
data_util.hide_prototype("technology", "planet-discovery-fulgora")
data_util.hide_prototype("technology", "planet-discovery-gleba")
data_util.hide_prototype("technology", "planet-discovery-vulcanus")

data.raw["autoplace-control"]["aquilo_crude_oil"] = nil
if settings.startup["eon-holmium-ore"].value then
  data.raw["resource"]["scrap"].autoplace = nil  -- why is this needed? who knows... moving on...
  data.raw["autoplace-control"]["scrap"] = nil
  -- scrap's probability expression (via fulgora_starting_mask -> fulgora_grid) needs
  -- control:fulgora_islands:frequency, so only delete it when scrap is gone too
  data.raw["autoplace-control"]["fulgora_islands"] = nil
end
data.raw["autoplace-control"]["fulgora_cliff"] = nil
data.raw["autoplace-control"]["gleba_stone"] = nil
data.raw["autoplace-control"]["gleba_cliff"] = nil
data.raw["autoplace-control"]["vulcanus_coal"] = nil
