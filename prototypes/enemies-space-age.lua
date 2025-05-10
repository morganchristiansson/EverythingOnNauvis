local space_age_sounds = require("__space-age__.prototypes.entity.sounds")
local simulations = require("__space-age__.prototypes.factoriopedia-simulations")

local function lerp_color(a, b, amount)
  return
  {
    a[1] + amount * (b[1] - a[1]),
    a[2] + amount * (b[2] - a[2]),
    a[3] + amount * (b[3] - a[3]),
    a[4] + amount * (b[4] - a[4]),
  }
end

local function fade(tint, amount) -- fades to minimal opacity grey. Low opacity is good for the mask to let the base layer show htough (instead of having a grey mask)
  return lerp_color(tint, {1, 1, 1, 2}, amount)
end

local function grey_overlay(tint, amount) -- fades to opaque grey. Full opacity is required for body.
  return lerp_color(tint, {127, 127, 127, 255}, amount)
end

local gleba_behemoth_mask_tint  = {216,0,35,255}
local gleba_behemoth_mask2_tint  = {216,100,35,255}
local gleba_behemoth_body_tint = {117,116,104,255}
local gleba_behemoth_scale = 1.2

local gleba_titan_mask_tint  = {216,0,35,255}
local gleba_titan_mask2_tint  = {216,100,35,255}
local gleba_titan_body_tint = {117,116,104,255}
local gleba_titan_scale = 1.7

local gleba_gargantuan_mask_tint  = {216,0,35,255}
local gleba_gargantuan_mask2_tint  = {216,100,35,255}
local gleba_gargantuan_body_tint = {117,116,104,255}
local gleba_gargantuan_scale = 2

make_wriggler("behemoth-", gleba_behemoth_scale, 4500, 2.8,
  {
    mask = fade(gleba_behemoth_mask_tint, 0.5),
    body = gleba_behemoth_body_tint
  }, simulations.factoriopedia_gleba_enemy_big_wriggler, simulations.factoriopedia_gleba_enemy_big_wriggler_premature, space_age_sounds.wriggler_pentapod.big)
make_wriggler("titan-", gleba_titan_scale, 45000, 4,
  {
    mask = fade(gleba_titan_mask_tint, 0.5),
    body = gleba_titan_body_tint
  }, simulations.factoriopedia_gleba_enemy_big_wriggler, simulations.factoriopedia_gleba_enemy_big_wriggler_premature, space_age_sounds.wriggler_pentapod.big)
make_wriggler("gargantuan-", gleba_gargantuan_scale, 450000, 6,
  {
    mask = fade(gleba_gargantuan_mask_tint, 0.5),
    body = gleba_gargantuan_body_tint
  }, simulations.factoriopedia_gleba_enemy_big_wriggler, simulations.factoriopedia_gleba_enemy_big_wriggler_premature, space_age_sounds.wriggler_pentapod.big)


make_strafer("behemoth-", gleba_titan_scale, 20000, 2, 6.5, 27, 32, 37,
  {
    mask = fade(gleba_behemoth_mask_tint, 0.4),
    mask_thigh = fade(gleba_behemoth_mask2_tint, 0.2),
    body = grey_overlay(gleba_behemoth_body_tint, 0.1),
    projectile_mask = big_wriggler_mask_tint, -- same as wriggler mask tint
    projectile = big_wriggler_body_tint  -- same as wriggler body tint
  }, simulations.factoriopedia_gleba_enemy_big_strafer, space_age_sounds.strafer_pentapod.big)
make_strafer("titan-", gleba_gargantuan_scale, 200000, 2.4, 7.5, 28, 33, 38,
  {
    mask = fade(gleba_titan_mask_tint, 0.4),
    mask_thigh = fade(gleba_titan_mask2_tint, 0.2),
    body = grey_overlay(gleba_titan_body_tint, 0.1),
    projectile_mask = big_wriggler_mask_tint, -- same as wriggler mask tint
    projectile = big_wriggler_body_tint  -- same as wriggler body tint
  }, simulations.factoriopedia_gleba_enemy_big_strafer, space_age_sounds.strafer_pentapod.big)


make_stomper("behemoth-", gleba_titan_scale, 120000, 2, 3,
  {
    mask = fade(gleba_behemoth_mask_tint, 0.4),
    mask_thigh = fade(gleba_behemoth_mask2_tint, 0.3),
    body = grey_overlay(gleba_behemoth_body_tint, 0.1),
    body_thigh = lerp_color(gleba_behemoth_body_tint, grey_overlay({250,108,0,255}, 0.7), 0.1) -- more orange/yellow
  }, simulations.factoriopedia_gleba_enemy_big_stomper, space_age_sounds.stomper_pentapod.big)
make_stomper("titan-", gleba_gargantuan_scale, 1000000, 2.4, 3.2,
  {
    mask = fade(gleba_titan_mask_tint, 0.4),
    mask_thigh = fade(gleba_titan_mask2_tint, 0.3),
    body = grey_overlay(gleba_titan_body_tint, 0.1),
    body_thigh = lerp_color(gleba_titan_body_tint, grey_overlay({250,108,0,255}, 0.7), 0.1) -- more orange/yellow
  }, simulations.factoriopedia_gleba_enemy_big_stomper, space_age_sounds.stomper_pentapod.big)


-- data.raw["segmented-unit"]["titan-demolisher"].icon = "__space-age__/graphics/icons/big-demolisher.png"
-- data.raw["segmented-unit"]["titan-demolisher"].vision_distance = math.min(100, data.raw["segmented-unit"]["titan-demolisher"].vision_distance)

data.raw["spider-unit"]["behemoth-strafer-pentapod"].icon = "__space-age__/graphics/icons/big-strafer.png"
data.raw["spider-unit"]["behemoth-stomper-pentapod"].icon = "__space-age__/graphics/icons/big-stomper.png"
data.raw["simple-entity"]["behemoth-stomper-shell"].icon = "__space-age__/graphics/icons/big-stomper.png"
data.raw["unit"]["behemoth-wriggler-pentapod-premature"].icon = "__space-age__/graphics/icons/big-wriggler.png"
data.raw["unit"]["behemoth-wriggler-pentapod"].icon = "__space-age__/graphics/icons/big-wriggler.png"
data.raw["corpse"]["behemoth-wriggler-pentapod-corpse"].icon = "__space-age__/graphics/icons/big-wriggler-corpse.png"
data.raw["corpse"]["behemoth-stomper-corpse"].icon = "__space-age__/graphics/icons/big-stomper.png"
data.raw["corpse"]["behemoth-strafer-corpse"].icon = "__space-age__/graphics/icons/big-strafer.png"
data.raw["spider-leg"]["behemoth-stomper-pentapod-leg"].icon = "__space-age__/graphics/icons/big-stomper.png"
data.raw["spider-leg"]["behemoth-strafer-pentapod-leg"].icon = "__space-age__/graphics/icons/big-strafer.png"

data.raw["spider-unit"]["titan-strafer-pentapod"].icon = "__space-age__/graphics/icons/big-strafer.png"
data.raw["spider-unit"]["titan-stomper-pentapod"].icon = "__space-age__/graphics/icons/big-stomper.png"
data.raw["simple-entity"]["titan-stomper-shell"].icon = "__space-age__/graphics/icons/big-stomper.png"
data.raw["unit"]["titan-wriggler-pentapod-premature"].icon = "__space-age__/graphics/icons/big-wriggler.png"
data.raw["unit"]["titan-wriggler-pentapod"].icon = "__space-age__/graphics/icons/big-wriggler.png"
data.raw["corpse"]["titan-wriggler-pentapod-corpse"].icon = "__space-age__/graphics/icons/big-wriggler-corpse.png"
data.raw["corpse"]["titan-stomper-corpse"].icon = "__space-age__/graphics/icons/big-stomper.png"
data.raw["corpse"]["titan-strafer-corpse"].icon = "__space-age__/graphics/icons/big-strafer.png"
data.raw["spider-leg"]["titan-stomper-pentapod-leg"].icon = "__space-age__/graphics/icons/big-stomper.png"
data.raw["spider-leg"]["titan-strafer-pentapod-leg"].icon = "__space-age__/graphics/icons/big-strafer.png"

data.raw["unit"]["gargantuan-wriggler-pentapod-premature"].icon = "__space-age__/graphics/icons/big-wriggler.png"
data.raw["unit"]["gargantuan-wriggler-pentapod"].icon = "__space-age__/graphics/icons/big-wriggler.png"
data.raw["corpse"]["gargantuan-wriggler-pentapod-corpse"].icon = "__space-age__/graphics/icons/big-wriggler-corpse.png"
