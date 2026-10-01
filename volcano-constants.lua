-- The numbers behind the volcano's noise expressions, defined ONCE.
--
-- These used to exist twice: once inside the expression strings in
-- map-generation/terrain.lua, and once hand-copied into noise-mirror/ (which
-- evaluates the same functions at runtime, because the mirror cannot read
-- data.raw). A tune meant editing both files, and the only thing that noticed
-- when they disagreed was tests/density_parity.py -- which compares the DENSITY
-- function, and the density function takes volcanism and the spawn gate as
-- PARAMETERS. So the two expressions the mirror computes itself
-- (eon_volcano_spawn_gate, eon_volcano_size_dist) had no gate at all, and a
-- change to either would have failed silently until a playtest noticed.
--
-- This module is requireable from BOTH stages (it is what data-util.lua already
-- does for map-generation/terrain.lua): it holds numbers and nothing else, so
-- each stage loads its own copy and neither can reach for `data` or `prototypes`.
--
-- It does NOT hold vanilla's biome-chain numbers (the multioctave seeds,
-- persistence and octave counts behind vulcanus_mountains_biome_full_pre_volcano
-- and vulcanus_starting_area). Those are Factorio's, defined in
-- /factorio/data/space-age/prototypes/planet/planet-vulcanus-map-gen.lua, so
-- there is no second copy of ours to reconcile -- noise-mirror/density.lua
-- transcribes them and anchors each one to its source in a comment. What this
-- buys is that OUR numbers have one home, and vanilla's have a citation.

local M = {}

--------------------------------------------------------------------------------
-- A number as an expression-source literal.
--
-- The shortest string that reads back as the same double, so the expression
-- text stays readable ("0.3", not "0.29999999999999999") and nothing is
-- silently rounded on the way into the compiled program -- a truncated literal
-- would be a real behaviour change, which is the opposite of what this module
-- is for.
function M.num(n)
  for digits = 6, 17 do
    local text = string.format("%." .. digits .. "g", n)
    if tonumber(text) == n then return text end
  end
  error("volcano-constants: cannot format " .. tostring(n) .. " exactly")
end

--------------------------------------------------------------------------------
-- EoN's starting radius, `eon_starting_radius` (terrain.lua).
M.starting_radius = { base = 0.7, size = 0.75 }

-- `eon_volcanism`: cone SIZE only. Vanilla divides by the frequency slider here
-- too, so cranking frequency shrank every volcano; EoN decoupled it and the
-- frequency slider drives density alone (see density.divisor).
M.volcanism = { base = 0.3, span = 0.7, slider_base = 3 }

-- `volcano_spot_radius = 300 * volcanism * sqrt(1 + size slider)`
M.spot_radius = { scale = 300 }

-- `volcano_spot_spacing = 1500 * volcanism`
M.spot_spacing = { scale = 1500 }

-- `density_multiplier = 3.5 / sqrt(frequency)`, applied to a 256-tile region
-- edge: smaller candidate cells mean more volcanoes. Rescaled from vanilla's
-- 5/sqrt(freq) so the highest slider setting yields a little over twice the
-- volcanoes it used to (measured ~11 per 3.2km square at 100%, vs 5).
M.density = { region_edge = 256, divisor = 3.5 }

-- `eon_volcano_spawn_gate = clamp((distance - R) / R, 0, 1)` with R = 425 *
-- starting radius: it throttles candidate density near spawn rather than
-- subtracting fields, so a cone that is never placed never has to be excluded.
M.spawn_gate = { radius_starts = 425 }

-- `eon_volcano_size_dist`: distance ramp x smooth size noise x spawn gate,
-- capped at 1. The noise is a 3-octave multioctave sampled once per candidate.
-- The three octaves Factorio calls vulcanus_wobble_{,large_,huge_}{x,y}, which
-- eon_volcano_spots_at re-declares as eon_detail_noise_at. They DISPLACE the
-- spot_noise's query point, so the field at a world position is the undisplaced
-- cone evaluated at (x + wobble_x, y + wobble_y). That is why the cone itself is a
-- plain linear falloff and the whole wobble lives here.
--
-- There are TWO divisors per term and they are easy to merge into one wrong
-- number. eon_detail_noise_at is a wrapper:
--     multioctave_noise{..., input_scale = 1 / 50 / scale, output_scale = magnitude}
-- and the call site then divides the RESULT again, by 2, 12 and 80. So
-- input_scale = 1 / (50 * scale) -- 0.16, 0.04, 0.01 for the three -- and the
-- divisor is separate.
--
-- Reading input_scale as 1/scale instead puts the 800-magnitude term at a
-- half-tile wavelength, which is wrong by 50x in feature size and suggests this is
-- tile-scale roughness that 1-tile sampling would alias. It is not: the features
-- are roughly 6, 25 and 100 tiles, so this is a smooth displacement of about 16
-- tiles per axis, which is the whole reason a measured ground edge ran 53 to 87
-- tiles on a cone whose claim radius was 67.
-- The ground threshold, derived rather than measured, because it is arithmetic.
--
-- eon_updated_volcanic_folds is
--   10 * range_select_base(field * 1.95 - 0.9, 0.16, 10, 1, 0, 1) - 1.5
-- and range_select_base(input, from, to, slope, lo, hi) is
--   clamp(min(input - from, to - input) / slope, lo, hi)
-- so with input = field * 1.95 - 0.9 the score is positive exactly when
--   min(input - 0.16, 10 - input) > 0.15   <=>   input > 0.31
--   <=>  field * 1.95 - 0.9 > 0.31          <=>   field > 1.21 / 1.95
-- The -0.9 is load-bearing: dropping it puts the threshold at 0.159 and the ground
-- at 0.83 * width, which is outside the claim and would have said the patrol path can
-- never leave the ground -- the opposite of what the playtest shows.
--
-- And since the field is (3/pi) * (1 - d/width) (see Volcanoes:cone_value), ground is
-- a disc of GROUND_FRACTION * width in the UNDISPLACED frame:
--
--   width 296: ground 104 | claim 124 | patrol path  97 | margin 6.7 tiles
--   width 471: ground 165 | claim 198 | patrol path 154 | margin 10.6 tiles
--   width 159: ground  56 | claim  67 | patrol path  52 | margin 3.6 tiles
--
-- The margin is 3.6 to 10.6 tiles and the wobble displaces by about 16 per axis.
-- That is the entire bug: the patrol path is inside the ground by less than the wobble
-- moves it, so a big cone clears and a small one does not.
-- TWO boundaries, not one, and conflating them is what made this take three goes.
--
-- Both tiles are placed by a range_select_base on the same spot field, differing
-- only in `from` (0.16 for folds, 0 for folds-flat), and folds has the lower order
-- so it wins ties. So walking outward from a cone's centre:
--
--   field <= 1.05/1.95   neither tile's score is positive      not volcanic
--   field <= 1.21/1.19..  folds-flat only                      volcanic-folds-flat
--   field >  1.21/1.95   both positive, folds wins the tie     volcanic-folds
--
-- Which gives two radii, and they are 8.6% of a width apart:
--
--   FOLDS_LINE_FRACTION   0.3502   the folds / folds-flat boundary
--   VOLCANIC_EDGE_FRACTION 0.4361   where the ground stops being volcanic at all
--
-- The patrol path follows the FOLDS LINE, which is a line the player can see -- the tile
-- changes under the patrol. It is not the outer edge: measured over 121 directions at
-- 600% volcanism the outer edge fits F = 0.434 +/- 0.042, which is
-- VOLCANIC_EDGE_FRACTION to within 0.002, so the arithmetic and the tiles agree
-- and the two constants are both real.
-- The crossover is where the folds score OVERTAKES flat, not where folds becomes
-- positive. Those are different numbers and using the wrong one is a 1.7 tile
-- error, which is most of the residual:
--
--   folds = 10 * clamp(input - 0.16) - 1.5                 (from = 0.16, to = 10)
--   flat  = 10 * clamp(min(input, 0.5 - input)) - 1.5      (from = 0,    to = 0.5)
--
-- flat wins outright below input = 0.25, where its min() is just `input` and it
-- leads by 1.6. Above that its term is 0.5 - input and the two meet where
-- 0.5 - input == input - 0.16, i.e. input = 0.33. With input = field*1.95 - 0.9
-- that is field = 1.23/1.95, and the tile autoplace is a strict `>` argmax in
-- tile-ORDER (a-i before a-j), so the switch is there.
--
-- Measured per direction, prediction minus game: 37 of 39 directions were too far OUT and the
-- error grew at 2% of the radius -- which is the size of the gap between this and
-- the 0.3502 that folds' positivity gives.
-- The VOLCANO TERRAIN's outer boundary, which is what a TERRITORY claims.
--
-- The data stage already defines this, and the claim should be the same shape as
-- the mask the mod ships:
--     eon_vulcanus_terrain = max(eon_volcano_coverage, eon_updated_volcanic_folds_flat) > 0
--     eon_volcano_coverage = max(eon_updated_volcanic_folds, lava...) > 0
-- Unioned, that is `field > 1.05/1.95` -- the folds score covers the core, the
-- flat score the band either side of it, and between them they cover everything
-- above 0.5385. So the terrain is a disc of VOLCANIC_EDGE_FRACTION * width, in the
-- frame the spot field itself is evaluated in, which is the WOBBLED one.
--
-- The claim used to be a clean disc of 0.42 * width, which is wrong in both
-- directions: too large where the wobble pulls the ground in and too small where
-- it pushes the ground out. Confirmed against the game: fitting the rendered
-- volcanic tiles over 121 directions at 600% volcanism gives 0.434 +/- 0.042, and this
-- is 0.4361.
M.VOLCANIC_EDGE_FRACTION = 1 - (1.05 / 1.95) / (3 / math.pi)

M.FOLDS_LINE_FRACTION = 1 - (1.23 / 1.95) / (3 / math.pi)
-- The folds score itself, kept because Volcanoes:is_ground is the exact predicate.

M.wobble = {
  persistence = 0.6,
  octaves = 2,
  -- SIX octaves, not three: the x and y terms use DIFFERENT seeds (10/20/30 and
  -- 1010/1020/1030), so they are independent draws. Summing one value into both
  -- axes -- which is the obvious first implementation -- was caught by
  -- tests/wobble_parity.py at 19.5 tiles worst error.
  octaves_list = {
    -- seed1_x, seed1_y, input_scale = 1/(50*scale), output_scale = magnitude,
    -- then the call site divides the result by `divisor`.
    { seed1_x = 10,  seed1_y = 1010, input_scale = 1 / 6.25, output_scale = 4,   divisor = 2  },
    { seed1_x = 20,  seed1_y = 1020, input_scale = 1 / 25,   output_scale = 50,  divisor = 12 },
    { seed1_x = 30,  seed1_y = 1030, input_scale = 1 / 100,  output_scale = 800, divisor = 80 },
  },
}

M.size_dist = {
  ramp_near = 0.70,
  ramp_slope = 0.25,
  ramp_distance = 5000,
  noise_near = 0.45,
  noise_span = 0.85,
  gate_near = 0.40,
  gate_span = 0.40,
  cap = 1.0,
  noise = { seed1 = 1977, octaves = 3, persistence = 0.6,
            -- Held as a DIVISOR, not a quotient, because the source expression
            -- says `input_scale = 1/350` and formatting the double would print
            -- 0.002857142857142857 instead. Same number, but the expression text
            -- lands in data.raw and is read by people comparing dumps.
            input_scale_divisor = 350, output_scale = 1.6 },
}

return M
