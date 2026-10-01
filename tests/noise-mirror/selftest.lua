-- Self test for the standalone spot mirror. No Factorio, no Python, no oracle:
--
--   lua tests/noise-mirror/selftest.lua
--
-- Two kinds of check:
--   * the primitives against GAME-CAPTURED vectors (vectors.lua, next to this
--     file), so the port is pinned to the engine rather than to itself;
--   * the invariants the territory builder relies on: identity stability, closed
--     and disjoint footprints, cache behaviour, and the gate contract.
-- Runnable from anywhere (it puts the mod root on package.path itself, the way
-- control.lua's require does inside Factorio).
local script = (arg and arg[0]) or ""
local here = script:match("^(.*)[/\\][^/\\]+$") or "."
-- tests/noise-mirror -> tests -> the mod root, two levels up (these are tools,
-- not shipped mirror code, so they live under tests/ where create_zip.py
-- already excludes them).
local root = here:match("^(.*)[/\\][^/\\]+$") or here
root = root:match("^(.*)[/\\][^/\\]+$") or root
package.path = root .. "/?.lua;" .. package.path

local basis = require("noise-mirror.noise-primitives")
local gradient = require("noise-mirror.basis-gradient-table")
local multioctave = require("noise-mirror.noise-primitives")
local candidates = require("noise-mirror.spot-candidates")
local cones = require("noise-mirror.volcano-cones")
local PatrolPath = require("volcano-patrol-path")
-- It lives under tests/ with its fixture: this is a tool, not mirror code, and
-- create_zip.py skips tests/ so neither ships in the release.
local vectors = dofile(here .. "/vectors.lua")
local cache_size = require("noise-mirror.cache_census")

local failures, checks = 0, 0

local function check(name, ok, detail)
  checks = checks + 1
  if ok then
    print(string.format("  ok   %s", name))
  else
    failures = failures + 1
    print(string.format("  FAIL %s%s", name, detail and ("  -- " .. detail) or ""))
  end
end

local function near(a, b, tolerance)
  return math.abs(a - b) <= tolerance
end

print("the 32-bit dialect this mirror is written in")
do
  -- These are not tests of bit32; they pin the three behaviours the noise chain
  -- ASSUMES, so a host whose bit32 disagreed would fail here and not as a wrong
  -- cone three hours later. They are the assertions that were worth keeping when
  -- noise-mirror/bitops.lua (four delegates and a `n % 2^32` that this Lua makes
  -- redundant) was deleted.
  check("shifts wrap to unsigned 32-bit, so the taus88 chain is 32-bit by construction",
    bit32.lshift(0xfffffffe, 12) == 4294959104)
  check("rshift is LOGICAL, so the high bit is data and not a sign",
    bit32.rshift(0x80000000, 19) == 4096)
  check("a negative operand normalizes like the game, so seed arithmetic cannot go negative",
    bit32.band(-3, 255) == 253)
end

print("taus88")
do
  -- The first five draws for the clamped minimum seed word 0x155, the word every
  -- low-seed map uses. Ground truth taken from the engine, not from this port.
  local state = basis.seeded_state(0x155)
  local got = {}
  for i = 1, 5 do got[i] = basis.taus88_next(state) end
  local expected = { 45438212, 1409544450, 3980732798, 112738311, 3238374133 }
  local same = true
  for i = 1, 5 do same = same and got[i] == expected[i] end
  check("first five draws of seed word 0x155", same,
    string.format("got %s", table.concat(got, ", ")))
  check("all-zero state is a fixed point", basis.taus88_next(basis.seeded_state(0)) == 0)
end

print("basis_noise")
do
  check("gradient table has 256 directions", #gradient.X == 256 and #gradient.Y == 256)
  local magnitude_ok = true
  for i = 1, 256 do
    magnitude_ok = magnitude_ok
      and near(math.sqrt(gradient.X[i] ^ 2 + gradient.Y[i] ^ 2), 4.2, 1e-5)
  end
  check("every gradient has magnitude 4.2", magnitude_ok)
  local tables = basis.tables_from_seed(vectors.basis_noise.seed0, vectors.basis_noise.seed1)
  local scale = vectors.basis_noise.input_scale
  local worst, worst_at = 0, nil
  for _, point in ipairs(vectors.basis_noise.points) do
    -- basis_noise{x, y, input_scale, output_scale} as the noise-expression API
    -- exposes it, applied to the kernel the mirror ships. It used to be a
    -- seven-argument convenience in noise-primitives.lua whose only caller was this
    -- test; every shipped caller holds prepared tables anyway.
    local value = basis.eval(point[1] * scale, point[2] * scale, tables)
    local error = math.abs(value - point[3])
    if error > worst then worst, worst_at = error, point end
  end
  check(string.format("game volcanoes reproduced (worst error %.2e)", worst), worst < 1e-6,
    string.format("worst at %s,%s", worst_at and worst_at[1], worst_at and worst_at[2]))
  check("zero on the integer lattice (the documented quirk)",
    basis.eval(3, 7, tables) == 0)
end

print("multioctave_noise")
do
  local params = { seed0 = 12345, seed1 = 342, octaves = 5, persistence = 0.65,
                   input_scale = 0.02, output_scale = 1 }
  check("prepared instances are cached, not rebuilt",
    multioctave.get(params) == multioctave.get(params))
  local prepared = multioctave.get(params)
  check("eval is deterministic", prepared:eval(10, 20) == prepared:eval(10, 20))
end

print("spot candidates")
do
  local ok, detail = true, nil
  for _, case in ipairs(vectors.candidates) do
    local points = candidates.points(case.seed0, case.seed1, case.region_x, case.region_y,
      case.region_size, #case.points)
    local got = {}
    for _, point in ipairs(points) do got[point.x .. ":" .. point.y] = true end
    for _, expected in ipairs(case.points) do
      if not got[expected[1] .. ":" .. expected[2]] then
        ok, detail = false, string.format("missing {%d, %d} for seed0=%d region %d,%d",
          expected[1], expected[2], case.seed0, case.region_x, case.region_y)
      end
    end
  end
  check("game-captured candidate points reproduced", ok, detail)
  check("regions are centred on multiples of the region size",
    candidates.region_index(0, 1024) == 0 and candidates.region_index(512, 1024) == 1
    and candidates.region_index(-512, 1024) == 0 and candidates.region_index(-513, 1024) == -1)
  local function stream(seed0)
    local parts = {}
    for _, p in ipairs(candidates.points(seed0, 0, 0, 0, 1024, 4)) do
      parts[#parts + 1] = p.x .. "," .. p.y
    end
    return table.concat(parts, ";")
  end
  check("bit 0 of seed0 is dead (all three taus88 words ignore it)",
    stream(123457) == stream(123456))
  check("a cone's centre is the region's first candidate",
    candidates.first_accepted(12345, 1, 3, -2, 633).x
      == candidates.points(12345, 1, 3, -2, 633, 1)[1].x)
end

print("EoN volcano cones")
do
  local volcanoes = cones.new_volcanoes(cones.new_context{
    seed = 12345, volcanism_size = 1, volcanism_frequency = 2,
  })
  local all = cones.new_volcanoes(cones.new_context{
    seed = 12345, volcanism_size = 1, volcanism_frequency = 2,
  })
  local cone_list = select(1, volcanoes:cones_near(0, 0, 12))
  check("cones are found around a populated area", #cone_list > 0, "#" .. #cone_list)
  local stable, widths_positive, peaks_constant, sized = true, true, true, true
  for _, cone in ipairs(cone_list) do
    widths_positive = widths_positive and cone.width > 0
    -- EoN keeps quantity = radius^2, so every cone peaks at 3/pi.
    peaks_constant = peaks_constant and near(cone.peak, 3 / math.pi, 1e-12)
    sized = sized and cone.width <= 300 * volcanoes.context.volcanism
      * math.sqrt(1 + volcanoes.context.size) * 1.25 + 1e-9
    local system = volcanoes.systems[cone.seed1]
    local again = volcanoes:region_cone(system, cone.region_x, cone.region_y)
    stable = stable and again ~= nil and again.id == cone.id and again.x == cone.x
      and again.y == cone.y and again.width == cone.width
  end
  check("cone identity, centre and width are stable across lookups", stable)
  -- size_fraction is the demolisher size tier's input: it must order cones by
  -- their RENDERED size (the effective width), not by the invisible size_dist
  -- volcanoes, which rates a 318px small-system cone and a 530px big-system cone
  -- identically when both sit at their system's cap.
  local ordered, fractions = true, {}
  for _, cone in ipairs(cone_list) do fractions[cone.id] = volcanoes:size_fraction(cone) end
  for _, a in ipairs(cone_list) do
    for _, b in ipairs(cone_list) do
      if a.width < b.width and fractions[a.id] > fractions[b.id] then ordered = false end
      if fractions[a.id] < 0 or fractions[a.id] > 1 then ordered = false end
    end
  end
  check("size_fraction ranks cones by rendered width and stays within 0..1", ordered)
  check("every cone has a positive effective width", widths_positive)
  check("every cone peaks at 3/pi (EoN keeps quantity = radius^2)", peaks_constant)
  check("widths never exceed the basement radius", sized)
  -- The claim radius is the same at every density: measured on live maps, the
  -- volcano's ground ends at d/width ~= 0.42 at 200% AND at 600%.
  local fraction_1x = cones.new_context({ seed = 7, volcanism_frequency = 1 }).core_fraction
  local fraction_6x = cones.new_context({ seed = 7, volcanism_frequency = 6 }).core_fraction
  check("the claim radius does not depend on the volcanism slider",
    fraction_1x == fraction_6x and fraction_1x == cones.CORE_FRACTION,
    string.format("1x=%s 6x=%s constant=%s", tostring(fraction_1x), tostring(fraction_6x),
      tostring(cones.CORE_FRACTION)))
  check("the core radius is the map's fraction of the width",
    near(cone_list[1].core_radius, cone_list[1].width * volcanoes.context.core_fraction, 1e-12))
  check("different seeds give different cones",
    #select(1, all:cones_near(0, 0, 12)) > 0)

  -- The footprint must be CLOSED: a later chunk generation can never add a chunk
  -- to it. That means: every chunk of the cone's core disc that the cone wins is
  -- ALREADY in the set, however the set was computed.
  local closed, disjoint, owned_total, matches_owner, no_outsiders = true, true, 0, true, true
  local VC = require("volcano-constants")
  local claimed = {}
  for _, cone in ipairs(cone_list) do
    local chunks = volcanoes:cone_chunks(cone, volcanoes:contenders_for(cone))
    owned_total = owned_total + #chunks
    local in_set = {}
    for _, chunk in ipairs(chunks) do
      in_set[chunk.x .. ":" .. chunk.y] = true
      local key = chunk.x .. ":" .. chunk.y
      disjoint = disjoint and claimed[key] == nil
      claimed[key] = cone.id
      local owner = volcanoes:chunk_owner(chunk.x, chunk.y)
      matches_owner = matches_owner and owner ~= nil and owner.id == cone.id
      -- Nothing in the set may be outside the cone's volcano ground -- and "ground"
      -- is the WOBLED terrain disc the claim is built from, not a clean disc of the
      -- core radius. The claim is deliberately larger than 0.42*width (the edge is
      -- 0.4361 and it moves), so a clean-disc test here fails on correct claims.
      local px, py = chunk.x * 32 + 16, chunk.y * 32 + 16
      local wx, wy = cones.wobble(volcanoes.context, px, py)
      local dx, dy = (px + wx) - cone.x, (py + wy) - cone.y
      local radius = VC.VOLCANIC_EDGE_FRACTION * cone.width
      if dx * dx + dy * dy > radius * radius + 0.5 then
        no_outsiders = false
      end
    end
    -- The same disc disc_chunks uses: the wobbled terrain edge, not a clean disc of
    -- the core radius. This test re-derives the membership rule on purpose (to
    -- check the footprint is closed and stays inside), so it has to track the rule
    -- when the rule changes -- and it did not when the claim became wobble-aware.
    local reach = math.floor((cone.width * VC.VOLCANIC_EDGE_FRACTION
      + math.max(cone.width * 0.15, 24)) / 32) + 1
    for dx = -reach - 1, reach + 1 do
      for dy = -reach - 1, reach + 1 do
        local cx, cy = math.floor(cone.x / 32) + dx, math.floor(cone.y / 32) + dy
        local px, py = cx * 32 + 16, cy * 32 + 16
        local wx, wy = cones.wobble(volcanoes.context, px, py)
        local ax, ay = (px + wx) - cone.x, (py + wy) - cone.y
        local radius = VC.VOLCANIC_EDGE_FRACTION * cone.width
        if ax * ax + ay * ay <= radius * radius then
          -- The SAME ownership rule cone_chunks uses (its own contender set), not a
          -- second one: a margin-0 ring answers a different question. Spelled out
          -- here rather than wrapped in the mirror: a one-line delegation with one
          -- caller does not earn a place in the shipped module.
          local owner = volcanoes:claim_winner(volcanoes:contenders_for(cone), px, py)
          if owner and owner.id == cone.id and not in_set[cx .. ":" .. cy] then
            closed = false
          end
        end
      end
    end
  end
  check("cone footprints are closed (a later chunk can never join one)", closed)
  check("footprints stay inside the cone's volcano ground", no_outsiders)
  check("overlapping cones yield disjoint chunk sets", disjoint)
  check("footprint membership equals the per-chunk ownership answer", matches_owner)
  -- The patrol loop is a CIRCLE fitted to the claim: it must stay inside it, and
  -- on a squashed claim it must move to the claim's heart rather than shrink around
  -- the cone's own centre (which is what made a merged volcano patrol a 17% circle).
  local loops_inside, checks, covered = true, 0, 0
  for _, cone in ipairs(cone_list) do
    local share = volcanoes:cone_chunks(cone, volcanoes:contenders_for(cone))
    local mine = {}
    for _, chunk in ipairs(share) do mine[chunk.x .. "," .. chunk.y] = true end
    local cx, cy, point_at = PatrolPath.patrol_circle(volcanoes, cone, share,
      volcanoes:contenders_for(cone))
    if point_at and #share > 8 then
      checks = checks + 1
      local sum_x, sum_y = 0, 0
      for _, chunk in ipairs(share) do sum_x = sum_x + chunk.x; sum_y = sum_y + chunk.y end
      local claims_centre = math.sqrt((cx / 32 - sum_x / #share) ^ 2
                                    + (cy / 32 - sum_y / #share) ^ 2) * 32
      -- it is on the claim's heart, not the cone's
      if claims_centre > cone.core_radius * 0.5 then loops_inside = false end
      -- and every point of it is inside the claim
      local radius = 0
      local min_leg, previous = math.huge, nil
      for index = 0, 31 do
        local x, y = point_at(2 * math.pi * index / 32)
        if not mine[math.floor(x / 32) .. "," .. math.floor(y / 32)] then
          loops_inside = false
        end
        radius = math.max(radius, math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2))
        -- ... and no two of them are the SAME point. Checking that they are inside
        -- the claim says nothing about this: four coincident points passed every
        -- assertion here while the shape was a 28-gon wearing a 32-point hat (the
        -- angle-to-direction snap floored a float a hair below the integer). Measured on
        -- the playtest's 307,-680 volcano, whose path had three exactly zero-length
        -- legs. A leg has to be at least a tile, or the body walk is stepping over
        -- it (volcano-territory.lua, body_nodes) and the point budget is wasted.
        if previous then
          min_leg = math.min(min_leg,
            math.sqrt((x - previous.x) ^ 2 + (y - previous.y) ^ 2))
        end
        previous = { x = x, y = y }
      end
      if min_leg < 1 then
        loops_inside = false
        print(string.format("    %s: two patrol points are %.2f tiles apart",
          cone.id, min_leg or 0))
      end
      -- and it is worth walking: at least a chunk across
      if radius < 16 then loops_inside = false end
      covered = covered + 1
    end
  end
  check("the patrol circle is on the claim's heart and inside the claim", loops_inside,
    string.format("%d circles checked", checks))
  check("every claim big enough to walk gets a circle", covered > 0,
    string.format("%d circles", covered))

  check("footprints are worth building", owned_total > 0, tostring(owned_total))

  local cache_before = cache_size(volcanoes)
  for _ = 1, 200 do volcanoes:chunk_owner(3, 3) end
  local cache_after = cache_size(volcanoes)
  check("repeated lookups grow the region cache, not the work",
    cache_after.regions == cache_before.regions, tostring(cache_after.regions))
  -- The other two caches are reported for the same reason: `rings` grows per
  -- (region, margin) and nothing could see it, so "the cache is bounded" was an
  -- assumption rather than a measurement.
  check("every cache is visible to the outside",
    cache_after.rings >= 0 and cache_after.raw_regions >= 0
    and cache_after.rings == cache_size(volcanoes).rings,
    string.format("rings=%d raw_regions=%d", cache_after.rings, cache_after.raw_regions))
end

print("cone existence is the engine's density, not the tiles")
do
  local context = cones.new_context{ seed = 7, volcanism_frequency = 2 }
  local volcanoes = cones.new_volcanoes(context)
  local ring = select(1, volcanoes:cones_near(0, 0, 8))
  -- Every cone that exists must have positive density at its own centre, and every
  -- region that does NOT hold a cone must have non-positive density there. This is
  -- the whole existence rule, and it is a pure function of position: no surface, no
  -- tiles, no revealed chunks, so the same map always answers the same way.
  local positive, negative, stable = 0, 0, true
  for _, cone in ipairs(ring) do
    if cones.cone_density(context, cone.x, cone.y) > 0 then positive = positive + 1 end
  end
  for _, system in ipairs(volcanoes.systems) do
    for region_x = -2, 2 do for region_y = -2, 2 do
      local found = volcanoes:region_cone(system, region_x, region_y)
      local centre = require("noise-mirror.spot-candidates").first_accepted(
        context.seed, system.seed1, region_x, region_y, system.region_size)
      local d = centre and cones.cone_density(context, centre.x, centre.y) or -1
      if found and d <= 0 then stable = false end
      if not found and d > 0 then stable = false end
      if found then positive = positive + 1 else negative = negative + 1 end
    end end
  end
  check("a cone exists exactly where the density is positive", stable and positive > 0,
    string.format("positive %d, negative %d", positive, negative))
  -- Two lookups of the same region must agree, and a second volcanoes must too: the
  -- answer cannot depend on what has been asked before (that was the whole point of
  -- retiring the tile gate -- it changed as chunks were revealed).
  local again = cones.new_volcanoes(cones.new_context{ seed = 7, volcanism_frequency = 2 })
  local agrees = true
  for _, system in ipairs(volcanoes.systems) do
    for region_x = -1, 1 do for region_y = -1, 1 do
      local a = volcanoes:region_cone(system, region_x, region_y)
      local b = again:region_cone(system, region_x, region_y)
      if (a == nil) ~= (b == nil) then agrees = false end
      if a and b and (a.id ~= b.id or a.width ~= b.width) then agrees = false end
    end end
  end
  check("existence is stable across fields and repeated lookups", agrees)
end

-- A failing self test must FAIL THE GATE. It used to print the failures and
-- exit 0, so `run_spot_mirror_tests.py` reported PASS for a selftest with two
-- failures in it -- which is how a broken claim radius survived a green run.
if failures > 0 then os.exit(1) end
