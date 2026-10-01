-- Game-captured vectors for the mirror's self test. Extracted once from
-- tools/noise-sandbox/vendor/FactorioMapWebUI/test/fixtures:
--   spot-candidates.game.json  -- candidate points trilaterated from the game
--   basis-noise.seed123456.json -- a basis_noise field, map seed 123456, seed1 0
-- These are the ENGINE's values. The mirror has to reproduce them from the
-- algorithms, not from this table; tests/spot_mirror_parity.py goes further and
-- compares the whole cone layer against the engine's own selection.
local M = {}

M.candidates = {
  { seed0 = 3735928559, seed1 = 3405691582, region_x = -7, region_y = 11, region_size = 1024,
    points = { {-7320, 10999}, {-7316, 10902}, {-7289, 10840}, {-7233, 11053}, {-7057, 10919}, {-6915, 11249} } },
  { seed0 = 123456, seed1 = 42, region_x = 3, region_y = -2, region_size = 1024,
    points = { {2636, -1652}, {2711, -2016}, {2862, -1833}, {2896, -1867}, {3190, -2504}, {3452, -1886} } },
  { seed0 = 999999999, seed1 = 271828182, region_x = 100, region_y = -100, region_size = 2048,
    points = { {204441, -204892}, {204694, -204983}, {205253, -203806}, {205449, -203870}, {205507, -205601}, {205705, -205322} } },
}

M.basis_noise = { seed0 = 123456, seed1 = 0, input_scale = 0.125, points = {
  { -13763.35546875, -6886.4921875, 0.21834702789783478 },
  { 225.984375, 71.328125, -0.30179572105407715 },
  { -14847.2109375, 7967.62109375, -0.3905912935733795 },
  { 1016.06640625, -13199.62109375, -0.19136527180671692 },
  { -12181.1875, -3429.390625, -0.3936527371406555 },
  { 5557.0234375, 7278.30859375, 0.13863453269004822 },
  { -5765.29296875, -11075.52734375, 0.038134440779685974 },
  { 13848.859375, 1507.109375, 0.07908704876899719 },
  { 4400.4765625, -14972.78515625, -0.9209784865379333 },
  { -4110.43359375, -514.21484375, -0.5457650423049927 },
  { -11683.87890625, 14881.828125, 0.949164092540741 },
  { 11680.1484375, 1214.3359375, -0.46047574281692505 },
} }

return M
