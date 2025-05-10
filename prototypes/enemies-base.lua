local titan_biter_scale = 1.7
local titan_biter_tint1 = {0.2, 0.25, 0.2, 1}
local titan_biter_tint2 = {0.82, 0.45, 0.1, 0.7}

local titan_biter = table.deepcopy(data.raw.unit['behemoth-biter'])
titan_biter.name = 'titan-biter'
titan_biter.max_health = 30000
titan_biter.attack_parameters.animation = biterattackanimation(titan_biter_scale, titan_biter_tint1, titan_biter_tint2)
titan_biter.run_animation = biterrunanimation(titan_biter_scale, titan_biter_tint1, titan_biter_tint2)
titan_biter.water_reflection = biter_water_reflection(titan_biter_scale)
titan_biter.resistances =
{
  {
    type = "physical",
    decrease = 16,
    percent = 10
  },
  {
    type = "explosion",
    decrease = 16,
    percent = 10
  }
}


local gargantuan_biter_scale = 2
local gargantuan_biter_tint1 = {0.2, 0.25, 0.2, 1}
local gargantuan_biter_tint2 = {0.82, 0.45, 0.1, 0.7}

local gargantuan_biter = table.deepcopy(data.raw.unit['behemoth-biter'])
gargantuan_biter.name = 'gargantuan-biter'
gargantuan_biter.max_health = 300000
gargantuan_biter.attack_parameters.animation = biterattackanimation(gargantuan_biter_scale, gargantuan_biter_tint1, gargantuan_biter_tint2)
gargantuan_biter.run_animation = biterrunanimation(gargantuan_biter_scale, gargantuan_biter_tint1, gargantuan_biter_tint2)
gargantuan_biter.water_reflection = biter_water_reflection(gargantuan_biter_scale)
gargantuan_biter.resistances =
{
  {
    type = "physical",
    decrease = 20,
    percent = 10
  },
  {
    type = "explosion",
    decrease = 20,
    percent = 10
  }
}


local scale_spitter_titan = 1.7
local tint_1_spitter_titan = {0.3, 0.2, 0.06, 1}
local tint_2_spitter_titan = {0.7, 0.45, 0.12, 0.75}

local titan_spitter = table.deepcopy(data.raw.unit['behemoth-spitter'])
titan_spitter.name = 'titan-spitter'
titan_spitter.max_health = 15000
titan_spitter.run_animation = spitterrunanimation(scale_spitter_titan, tint_1_spitter_titan, tint_2_spitter_titan)
titan_spitter.water_reflection = spitter_water_reflection(scale_spitter_titan)



local scale_spitter_gargantuan = 2
local tint_1_spitter_gargantuan = {0.3, 0.2, 0.06, 1}
local tint_2_spitter_gargantuan = {0.7, 0.45, 0.12, 0.75}

local gargantuan_spitter = table.deepcopy(data.raw.unit['behemoth-spitter'])
gargantuan_spitter.name = 'gargantuan-spitter'
gargantuan_spitter.max_health = 150000
gargantuan_spitter.run_animation = spitterrunanimation(scale_spitter_gargantuan, tint_1_spitter_gargantuan, tint_2_spitter_gargantuan)
gargantuan_spitter.water_reflection = spitter_water_reflection(scale_spitter_gargantuan)



data:extend{ titan_biter, gargantuan_biter, titan_spitter, gargantuan_spitter }
