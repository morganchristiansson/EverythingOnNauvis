-- The noise primitives the mirror stands on: Factorio's `basis_noise` and the
-- `multioctave_noise` built from it.
--
-- Two ports, one file, because they are one concern in a strictly linear chain:
-- multioctave calls basis, and nothing calls multioctave except the modules that
-- want noise at all. The boundary bought nothing -- the only direct consumer of
-- basis was this mirror's own self test, checking the port against game-captured
-- vectors.
--
-- Each port keeps its own header below, because they are two different primitives
-- recovered two different ways and there is no reason to pretend otherwise.

-- `basis_noise`: Factorio's square-lattice gradient noise, mirrored in Lua.
--
-- Ported from the reverse-engineered Rust oracle
-- (tools/noise-sandbox/vendor/FactorioMapWebUI/crates/fmw-noise/src/basis_noise.rs)
-- and measured against the game; see that crate's module docs and
-- docs/noise/basis-noise-NOTES.md for the derivation and the evidence.
--
--   basis_noise(x, y) = sum over the 4 cell corners of (1 - d)^3 * (D . G[h(i,j)])
--     D       = (x, y) - corner        (noise space: world coords * input_scale)
--     d       = |D|^2                  (corners with d >= 1 contribute nothing)
--     G[h]    = 4.2 * (cos(2*pi*h/256), sin(2*pi*h/256)), magnitude folded in
--     h(i, j) = a[i & 255] XOR b[j & 255]
--
-- The game evaluates this in f32 after every operation. Lua doubles cannot, so
-- this port is f64 throughout: values land within ~1e-7 relative of the game's,
-- which is far below anything the territory decisions compare against (see
-- noise-mirror/README.md for the measured agreement).
local gradient = require("noise-mirror.basis-gradient-table")

-- Factorio's control stage is Lua 5.2.1: no `&`, no `~`, no `<<`, and `bit32`
-- is present. That is the only dialect that matters and the only one this runs
-- in -- the mirror executes inside the game, or standalone under the same 5.2 the
-- Dockerfile installs -- so `bit32` is called directly and there is no second
-- path. A 5.3+ native-operator branch used to live here, reached through load()
-- so the file would parse under 5.2; it was dead, and dead arithmetic in the
-- noise chain is the worst kind of dead code: no test executes it, so it drifts
-- and is found only when the noise is subtly wrong.
--
-- `bit32` returns UNSIGNED 32-bit results on this Lua (measured in-game:
-- lshift(0xfffffffe, 12) = 4294959104, rshift(0x80000000, 19) = 4096, and
-- band(-3, 255) = 253), so every shift here is already mod 2^32 and needs no
-- wrapper. That was worth measuring rather than assuming: the taus88 chain
-- below is 32-bit by construction, and if a host's bit32 ever returned signed
-- values, `7 * rshift(seed1, 8)` and the candidate `V mod region_size` would go
-- negative. tests/noise-mirror/selftest.lua pins the three behaviours this depends on.
local band, bxor = bit32.band, bit32.bxor
local lshift, rshift = bit32.lshift, bit32.rshift
local floor = math.floor

local M = {}

local TABLE_SIZE = 256
local MASK = 255
-- taus88's all-zero state is a fixed point, so the seed word is clamped from
-- below. This is why every seed in 0..341 produces the same field.
local MIN_SEED_WORD = 0x155

local GX, GY = gradient.X, gradient.Y

--- One L'Ecuyer taus88 step; the output is taken AFTER the update.
local function taus88_next(state)
  local s1, s2, s3 = state[1], state[2], state[3]
  s1 = bxor(lshift(band(s1, 0xfffffffe), 12), rshift(bxor(lshift(s1, 13), s1), 19))
  s2 = bxor(lshift(band(s2, 0xfffffff8), 4), rshift(bxor(lshift(s2, 2), s2), 25))
  s3 = bxor(lshift(band(s3, 0xfffffff0), 17), rshift(bxor(lshift(s3, 3), s3), 11))
  state[1], state[2], state[3] = s1, s2, s3
  return bxor(bxor(s1, s2), s3)
end
M.taus88_next = taus88_next

--- Seed a taus88 state with all three words equal (the game's shape).
function M.seeded_state(word)
  return { word, word, word }
end

--- A backward Fisher-Yates shuffle of identity[0..255] off the stream: for pos
--- from 255 down to 1, swap slot pos with next() % (pos + 1). The game applies
--- exactly this to each of its four tables, all off one continuous stream.
local function shuffle_identity(next)
  local t = {}
  for i = 1, TABLE_SIZE do t[i] = i - 1 end
  for pos = TABLE_SIZE - 1, 1, -1 do
    local j = next() % (pos + 1)
    t[pos + 1], t[j + 1] = t[j + 1], t[pos + 1]
  end
  return t
end

-- Unsigned 32-bit add (the game's seed word addition wraps).
local function u32_add(a, b)
  return (a + b) % 4294967296
end

--- Build the per-seed hash tables (x permutation, y permutation, and the hash
--- -> direction map) directly from (seed0, seed1).
--
-- The game's wiring: the effective taus88 seed word is max(seed0 + 7*(seed1>>8),
-- 0x155) -- seed1's LOW byte is not in the word -- and one continuous stream
-- drives four identity shuffles in order: a scratch table (whose byte
-- scratch[seed1 & 0xff] is a salt), the Y table, the X table and the gradient
-- permutation. Evaluation hashes as gradPerm[xTable[i] ^ yTable[j] ^ salt];
-- folding the salt into sigma reproduces that as a plain a[i] ^ b[j].
function M.tables_from_seed(seed0, seed1)
  local word = u32_add(seed0, 7 * rshift(seed1, 8))
  if word < MIN_SEED_WORD then word = MIN_SEED_WORD end
  local salt_index = band(seed1, MASK) + 1

  local state = M.seeded_state(word)
  local scratch = shuffle_identity(function() return taus88_next(state) end)
  local salt = scratch[salt_index]
  local y_table = shuffle_identity(function() return taus88_next(state) end)
  local x_table = shuffle_identity(function() return taus88_next(state) end)
  local grad_perm = shuffle_identity(function() return taus88_next(state) end)

  -- sigma maps a hash to a gradient DIRECTION, and direction 0 is a real slot,
  -- so the stored value is the 1-based Lua index of that direction.
  local sigma = {}
  for h = 0, TABLE_SIZE - 1 do
    sigma[h + 1] = grad_perm[bxor(h, salt) + 1] + 1
  end
  return { a = x_table, b = y_table, sigma = sigma }
end

--- One cell corner's contribution, given the already-hashed sigma offset. The
--- hash indices are hoisted into the caller so no closure is allocated and no
--- table is re-indexed per evaluation (this runs millions of times).
local function corner(dx, dy, sigma_offset)
  local d = dx * dx + dy * dy
  -- Phrased as `not (d < 1)` so a NaN takes this branch, matching the game's
  -- `!(d < 1)` character for character: past d = 1 the falloff would go
  -- negative and SUBTRACT a contribution.
  if not (d < 1) then return 0.0 end
  local t = 1.0 - d
  local falloff = t * (t * t)
  return (dx * GX[sigma_offset] + dy * GY[sigma_offset]) * falloff
end

--- Evaluate basis_noise at a point in noise space. Returns 0 at integer lattice
--- points, which is the game's documented quirk and falls out of the kernel.
function M.eval(x, y, tables)
  local ix, iy = floor(x), floor(y)
  local fx, fy = x - ix, y - iy
  local a, b, sigma = tables.a, tables.b, tables.sigma
  local ax0, ax1 = a[band(ix, MASK) + 1], a[band(ix + 1, MASK) + 1]
  local by0, by1 = b[band(iy, MASK) + 1], b[band(iy + 1, MASK) + 1]
  local h00, h10 = sigma[bxor(ax0, by0) + 1], sigma[bxor(ax1, by0) + 1]
  local h01, h11 = sigma[bxor(ax0, by1) + 1], sigma[bxor(ax1, by1) + 1]
  -- Pairwise fold, corners sharing a corner_y first: that is the order the game
  -- adds them in (measured, not inferred from the disassembly).
  local row0 = corner(fx, fy, h00) + corner(fx - 1, fy, h10)
  local row1 = corner(fx, fy - 1, h01) + corner(fx - 1, fy - 1, h11)
  return row0 + row1
end

--------------------------------------------------------------------------

-- `multioctave_noise`: N octaves of basis_noise sharing one (seed0, seed1), with
-- the whole sum RMS-normalised. Mirrors the oracle's
-- crates/fmw-noise/src/multioctave_noise.rs (see its module docs and
-- docs/noise/multioctave-noise-NOTES.md for the evidence).
--
-- The one caller-visible trap, and the reason this module exists at all:
-- building the per-seed hash tables runs four 256-entry shuffles, so a
-- multioctave_noise call that rebuilds them is ~50x slower than one that does
-- not. EoN's volcano spot volcanoes evaluates six of them per queried point, so
-- every instance here is PREPARED once and cached by its parameters; the hot
-- loop only calls `eval`.


local floor, sqrt, ceil = math.floor, math.sqrt, math.ceil

-- Each octave halves the input scale (doubles the wavelength).
local LACUNARITY = 0.5
-- Per-octave x shift in noise space, exactly 17.17 in the game's binary. The
-- lattice has period 256 per axis and 17.17 - 1774.83 == -7 * 256, so the two
-- are indistinguishable in f64 -- and this port is f64.
local OCTAVE_OFFSET_X = 17.17

--- A prepared multioctave_noise: hash tables plus per-octave scale/amplitude.
local Prepared = {}
Prepared.__index = Prepared

--- @param params table { seed0, seed1, octaves, persistence, input_scale, output_scale }
local function prepare(params)
  local octaves = params.octaves or 3
  local persistence = params.persistence or 0.5
  local output_scale = params.output_scale or 1
  local n = ceil(octaves) -- the game takes ceil(octaves)
  local inv_p = 1 / persistence
  -- RMS normalisation of the octave chain, as the game computes it:
  -- sqrt((inv_p^2 - 1) / (inv_p^(2n) - 1)), then multiplied by output_scale.
  -- The game also special-cases persistence = 1 (flat) and persistence = 0
  -- (infinite amplitude); no caller passes either -- the six biome noises use
  -- 0.65, the wobbles and the size noise 0.6 -- and persistence = 0 divides by
  -- zero here, so it is a rejected input rather than a silently wrong one.
  local pow = inv_p ^ (2 * n)
  local amp = sqrt((inv_p * inv_p - 1) / (pow - 1)) * output_scale
  -- A fractional octave count boosts the base frequency; exactly 1 when integral,
  -- and ceil() bounds the result to [1, 2) for any octaves, so the game clamps
  -- here for an input this port never takes.
  local frac = 2 ^ (n - octaves)
  local scale = (params.input_scale or 1) * frac
  local scales, amps = {}, {}
  for k = 1, n do
    scales[k] = scale
    amps[k] = amp
    scale = scale * LACUNARITY
    amp = amp * inv_p
  end
  return setmetatable({
    tables = M.tables_from_seed(params.seed0 or 0, params.seed1 or 0),
    scales = scales,
    amps = amps,
  }, Prepared)
end

--- Evaluate at world coordinates (x, y).
function Prepared:eval(x, y)
  local tables, scales, amps = self.tables, self.scales, self.amps
  local out = 0
  for k = 1, #scales do
    local scale, amp = scales[k], amps[k]
    out = out + amp * M.eval((k - 1) * OCTAVE_OFFSET_X + x * scale, y * scale, tables)
  end
  return out
end



--- Process-wide cache of prepared instances, keyed by the full parameter set.
-- Two parameters are compile-time constants in EoN's spot expression (seed1 and
-- the scale), so the working set is tiny and the cache never grows per tile.
local cache = {}

function M.get(params)
  local key = table.concat({
    params.seed0 or 0, params.seed1 or 0, params.octaves or 3,
    params.persistence or 0.5, params.input_scale or 1, params.output_scale or 1,
  }, ":")
  local prepared = cache[key]
  if not prepared then
    prepared = prepare(params)
    cache[key] = prepared
  end
  return prepared
end

return M
