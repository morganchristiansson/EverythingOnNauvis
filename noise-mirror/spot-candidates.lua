-- Factorio's `spot_noise` candidate stream and its minimum-spacing dart throw:
-- everything the EoN volcano cones need to know WHERE a cone is.
--
-- Mirrors the oracle's crates/fmw-noise/src/{taus88,spot_candidates,spot_selection}.rs;
-- see docs/noise/spot-noise-NOTES.md ("Candidate RNG - SOLVED", "Spot selection -
-- SOLVED") for the derivation and the evidence.
--
--   W    = (0x3FBE2C + 7927*seed1 + 7919*region_x + 7907*region_y) mod 2^32
--   word = max(W XOR seed0, 0x155)
--   s1 = s2 = s3 = word                    -- canonical L'Ecuyer taus88 state
--   V[k] = taus88 output k (taken AFTER the state update)
--   candidate i = (V[2i], V[2i+1])         -- x then y, two draws per candidate
--   world coord = region_index * region_size + (V mod region_size) - region_size/2
--
-- Regions are CENTRED on multiples of region_size, so
--   region_index = floor((x + region_size/2) / region_size)
-- and a cone can reach into the neighbouring regions -- which is why callers ask
-- for the regions AROUND a point, not just the one containing it.
--
-- EoN's volcano systems use candidate_spot_count = 1, skip_span = 1,
-- skip_offset = 0 and hard_region_target_quantity = 0, which collapses the
-- engine's selection phase to exactly one thing: the FIRST dart-throw-accepted
-- candidate of the region. Everything else the engine does there (the skip
-- sets, the favorability sort, the trim, the hard-target cone shrink) is the
-- identity on a set of one, so it is not re-implemented; new_volcanoes() asserts
-- the configuration rather than pretending to support the general case.
-- bit32 directly: Factorio's control stage is Lua 5.2.1, where `&`/`~`/`<<` do
-- not exist and bit32 returns UNSIGNED 32-bit results (measured in-game, and
-- pinned by tests/noise-mirror/selftest.lua). No wrapper, no second dialect -- see the
-- note in noise-mirror/noise-primitives.lua, which is the same arithmetic.
local band, bxor = bit32.band, bit32.bxor
local lshift, rshift = bit32.lshift, bit32.rshift
local floor = math.floor

local M = {}

local SEED_BASE = 0x3fbe2c
local SEED1_PRIME = 7927
local RX_PRIME = 7919
local RY_PRIME = 7907
-- The taus88 all-zero state is a fixed point; the game clamps the seed word.
local MIN_SEED_WORD = 0x155

--- The effective seed word for a region, wrapped to 32 bits. A local rather
--- than an export: M.points is its only caller, and in the same file.
local function seed_word(seed0, seed1, region_x, region_y)
  local sum = SEED_BASE + SEED1_PRIME * (seed1 % 2 ^ 32)
    + RX_PRIME * region_x + RY_PRIME * region_y
  local word = bxor(sum % 4294967296, seed0 % 4294967296)
  if word < MIN_SEED_WORD then word = MIN_SEED_WORD end
  return word
end

--- The region index a world coordinate falls in (regions are centred).
function M.region_index(coord, region_size)
  return floor((coord + floor(region_size / 2)) / region_size)
end

--- Candidate points of a region as a plain table of {x, y}, first `count` in
--- generation order.
function M.points(seed0, seed1, region_x, region_y, region_size, count)
  local word = seed_word(seed0, seed1, region_x, region_y)
  local s1, s2, s3 = word, word, word
  local next_value = function()
    s1 = bxor(lshift(band(s1, 0xfffffffe), 12), rshift(bxor(lshift(s1, 13), s1), 19))
    s2 = bxor(lshift(band(s2, 0xfffffff8), 4), rshift(bxor(lshift(s2, 2), s2), 25))
    s3 = bxor(lshift(band(s3, 0xfffffff0), 17), rshift(bxor(lshift(s3, 3), s3), 11))
    return bxor(bxor(s1, s2), s3)
  end
  local half = floor(region_size / 2)
  local origin_x, origin_y = region_x * region_size, region_y * region_size
  local points = {}
  for i = 1, count do
    local vx, vy = next_value(), next_value()
    points[i] = {
      x = origin_x + (vx % region_size) - half,
      y = origin_y + (vy % region_size) - half,
    }
  end
  return points
end

--- The first dart-throw-accepted candidate of a region: the cone's CENTRE.
---
--- Dart throw over the candidate stream in generation order: a candidate is
--- accepted when its squared distance to every previously accepted spot is at
--- least a threshold that starts at spacing^2 and is multiplied by 15/16 on
--- every rejection. `suggested_minimum_candidate_point_spacing` consumes no
--- draws -- spacing is enforced here, not in the stream.
---
--- With `candidate_spot_count = 1` there is nothing for the first candidate to
--- be too close to, so the dart throw accepts it immediately and the cone's
--- centre is simply the first draw of the region's stream.
---
--- The `spacing` argument this used to take is GONE, and so is the comment that
--- justified it ("kept because that is the parameter the engine reads here, and
--- new_volcanoes() refuses any configuration where the simplification would not
--- hold"). new_volcanoes() never refused anything: it passes system.spacing and
--- nothing ever read it. So the parameter was dead and the claim about a guard
--- was false.
---
--- That leaves a real gap, stated here rather than papered over: this function is
--- only correct while the shipped prototype says `candidate_spot_count = 1`
--- (map-generation/terrain.lua, eon_volcano_spots_at). At 2 the engine would
--- reject a candidate too close to the first and this would return it anyway. A
--- second caller of points() and a distance test is all it would take -- and
--- AGENTS.md's rule is that a broken invariant is a guard or a dropped claim, not
--- a comment.
function M.first_accepted(seed0, seed1, region_x, region_y, region_size)
  local points = M.points(seed0, seed1, region_x, region_y, region_size, 1)
  return points[1]
end

return M
