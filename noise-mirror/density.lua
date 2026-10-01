-- Does this spot's cone become a VOLCANO? The engine's own answer, in Lua.
--
-- A `spot_noise` with `candidate_spot_count = 1` places at most one cone per
-- region, and it places it only if the candidate's DENSITY is positive. That
-- density is the biome-noise chain, and it is the one thing the mirror used to
-- delegate to the rendered tiles -- which cannot work: chunks arrive one at a
-- time, so a tile test can never see the whole volcano, and every consequence
-- followed from that (a claim made on four chunks of evidence, retraction when
-- more arrived, a real volcano left unclaimed while its rim was revealed first).
--
-- So it is ported. The expression, from the shipped prototypes:
--
--   density = volcano_area / volcanism^2 * eon_volcano_spawn_gate
--   volcano_area = lerp(vulcanus_mountains_biome_full_pre_volcano, 0, vulcanus_starting_area)
--
-- and the 32 nodes behind that collapse to three primitives: multioctave_noise
-- (which the mirror already had), the starting-area spots, and clamp/lerp/max.
-- Nothing here reads the game, and nothing depends on what has been revealed:
-- one number per cone, fixed for the life of the map.
--
-- tests/spot_mirror_parity.py checks this against the SHIPPED expression graph
-- (evaluated by the Python reference implementation, i.e. the prototype text)
-- at every candidate point of every region in the test windows, on four
-- seed/frequency/size settings. If the transcription drifts from the data, that
-- gate fails -- it is the same gate that proves cone centres and widths.
local multioctave = require("noise-mirror.noise-primitives")

local sqrt, min, max, abs = math.sqrt, math.min, math.max, math.abs
local sin, cos, pi = math.sin, math.cos, math.pi

local M = {}

--- slider_rescale{slider_value, n}: the game's exponential rescale, written with
--- its log2/2^ so it is exact rather than algebraic.
local function slider_rescale(value, n)
  if value <= 0 then return 0 end
  return 2 ^ (math.log(value, 2) / math.log(6, 2) * math.log(n, 2))
end

local function lerp(a, b, alpha) return a + (b - a) * alpha end

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

--- The biome noise chain, for one map. Built once per context: the multiscale
--- noises are five-octave, and a cone is asked once per region.
function M.new(seed, frequency, starting_x, starting_y)
  local self = {
    seed = seed or 0,
    starting_x = starting_x or 0,
    starting_y = starting_y or 0,
    -- vulcanus_scale_multiplier = slider_rescale(frequency, 3)
    scale_multiplier = slider_rescale(frequency or 1, 3),
    -- map_seed_normalized * 3600, and -1 + 2 * (map_seed_small & 1)
    ashlands_angle = (seed or 0) / 4294967296.0 * 3600,
    starting_direction = -1 + 2 * ((math.floor((seed or 0) % 65536)) % 2),
    -- vulcanus_starting_area_radius = 0.7 * 0.75 (vanilla, same file as above)
    starting_area_radius = 0.7 * 0.75,
  }
  -- VANILLA's biome chain, transcribed. Source of every number in this block:
  -- /factorio/data/space-age/prototypes/planet/planet-vulcanus-map-gen.lua
  -- (prototype `vulcanus`, its local_expressions vulcanus_mountains_biome* /
  -- vulcanus_starting_area, and the `vulcanus_detail_noise` noise-function).
  -- These are Factorio's, not ours, so they are NOT in volcano-constants.lua --
  -- there is no second copy of ours to reconcile, only a transcription to keep
  -- honest. What catches a Factorio change is tests/density_parity.py, which
  -- compares this against the SHIPPED expression graph; what a reader needs is
  -- the citation above. Do not retune these: change the EoN expressions.
  --
  -- The three biomes, near and far (a different volcanoes past the starting area),
  -- each a 5-octave multioctave at persistence 0.65. A table and a loop, because
  -- six near-identical calls is six places to fat-finger a seed.
  -- {volcanoes, near seed1, far seed1}
  for _, biome in ipairs{ { "mountains", 342, 1342 }, { "basalts", 42416, 43416 },
                          { "ashlands", 12416, 13416 } } do
    self[biome[1]] = multioctave.get{ seed0 = self.seed, seed1 = biome[2], octaves = 5,
      persistence = 0.65, input_scale = 1, output_scale = 1 }
    self[biome[1] .. "_far"] = multioctave.get{ seed0 = self.seed, seed1 = biome[3],
      octaves = 5, persistence = 0.65, input_scale = 1, output_scale = 1 }
  end
  -- vulcanus_detail_noise: multioctave with seed1 + 12243, persistence 0.6,
  -- input_scale = 1 / 50 / scale, output_scale = magnitude. Six of them (the
  -- wobbles), each asked twice per point -- {seed1, scale, magnitude}, also
  -- vanilla's.
  self.wobble = {}
  for _, spec in ipairs({ { 10, 1 / 8, 4 }, { 20, 1 / 2, 50 }, { 30, 2, 800 },
                          { 1010, 1 / 8, 4 }, { 1020, 1 / 2, 50 }, { 1030, 2, 800 } }) do
    self.wobble[#self.wobble + 1] = multioctave.get{
      seed0 = self.seed, seed1 = spec[1] + 12243, octaves = 2, persistence = 0.6,
      input_scale = 1 / 50 / spec[2], output_scale = spec[3],
    }
  end
  -- One method on the context, so callers write `biome:density(x, y, ...)`. The
  -- leading `_` is the context the colon syntax passes. `starting_area` and
  -- `volcano_area` are called directly by the functions that use them rather
  -- than re-wrapped as methods for one caller each.
  self.density = function(_, x, y, volcanism, spawn_gate)
    return M.density(self, x, y, volcanism, spawn_gate)
  end
  return self
end

--- vulcanus_biome_multiscale{seed1, scale, bias} = bias + lerp(noise(seed1,
--- scale*0.5), noise(seed1 + 1000, scale), clamp(distance / 10000, 0, 1)), where the
--- two noises share an input_scale of scale_multiplier / scale and `distance` is
--- the distance to the nearest starting position.
local function biome_multiscale(self, near, far, scale, x, y)
  local distance = sqrt((x - self.starting_x) ^ 2 + (y - self.starting_y) ^ 2)
  local alpha = clamp(distance / 10000, 0, 1)
  local a = near:eval(x * self.scale_multiplier / (scale * 0.5),
                      y * self.scale_multiplier / (scale * 0.5))
  local b = far:eval(x * self.scale_multiplier / scale, y * self.scale_multiplier / scale)
  return lerp(a, b, alpha)
end

--- starting_spot_at_angle{angle, distance, radius, x_distortion, y_distortion}
local function starting_spot_at_angle(self, angle, distance, radius, x_distortion, y_distortion, x, y)
  local angle_rad = angle / 180 * pi
  local x_from_start = x - self.starting_x
  local y_from_start = y - self.starting_y
  local delta_x = distance * sin(angle_rad) - x_from_start + x_distortion
  local delta_y = -distance * cos(angle_rad) - y_from_start + y_distortion
  return 1 - sqrt(delta_x * delta_x + delta_y * delta_y) / radius
end

--- The three starting-area spot fields, and with them vulcanus_starting_area.
local function starting_area(self, x, y)
  local r = self.starting_area_radius
  local wobble_x = self.wobble[1]:eval(x, y) + self.wobble[2]:eval(x, y) + self.wobble[3]:eval(x, y)
  local wobble_y = self.wobble[4]:eval(x, y) + self.wobble[5]:eval(x, y) + self.wobble[6]:eval(x, y)
  local mountains = 2 * starting_spot_at_angle(self,
    self.ashlands_angle + 120 * self.starting_direction, 250 * r, 500 * r,
    0.05 * r * wobble_x, 0.05 * r * wobble_y, x, y)
  local basalts = 2 * starting_spot_at_angle(self,
    self.ashlands_angle + 240 * self.starting_direction, 250, 550 * r,
    0.1 * r * wobble_x, 0.1 * r * wobble_y, x, y)
  local ashlands = 4 * starting_spot_at_angle(self,
    self.ashlands_angle, 170 * r, 350 * r,
    0.1 * r * wobble_x, 0.1 * r * wobble_y, x, y)
  return mountains, basalts, ashlands,
    clamp(max(basalts, mountains, ashlands), 0, 1)
end

--- volcano_area: the mountains biome with the starting area lerped out of it.
local function volcano_area(self, x, y)
  local mountains_noise = biome_multiscale(self, self.mountains, self.mountains_far, 60, x, y)
  local basalts_noise = biome_multiscale(self, self.basalts, self.basalts_far, 80, x, y)
  local ashlands_noise = biome_multiscale(self, self.ashlands, self.ashlands_far, 40, x, y)
  local mountains_start, basalts_start, ashlands_start, starting_area =
    starting_area(self, x, y)
  -- The three "raw" biomes lerp toward their own starting weights over the
  -- starting area, then mountains has the other two subtracted (that subtraction
  -- is what carves the mountains out of the ash/basalt plains).
  local alpha = clamp(2 * starting_area, 0, 1)
  local mountains = lerp(mountains_noise,
    mountains_start - ashlands_start - basalts_start, alpha)
  local basalts = lerp(basalts_noise,
    -mountains_start - ashlands_start + basalts_start, alpha)
  local ashlands = lerp(ashlands_noise,
    -mountains_start + ashlands_start - basalts_start, alpha)
  return lerp(mountains - max(ashlands, basalts), 0, starting_area)
end

--- The spot density at a position: volcano_area / volcanism^2 * spawn_gate.
--- `volcanism` is EoN's own density scalar (noise-mirror/volcano-cones.lua
--- computes the same thing), and the spawn gate throttles candidates near the
--- start. Sign is all the mirror needs -- "is it positive" -- but the value is
--- returned because it is what the reference implementation compares.
function M.density(self, x, y, volcanism, spawn_gate)
  return volcano_area(self, x, y) / (volcanism * volcanism) * (spawn_gate or 1)
end

return M
