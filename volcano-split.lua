-- One volcano, two guards.
--
-- A claim is a cone's core disc, and one guard patrols it. This cuts the disc in
-- two with a single straight cut THROUGH THE CONE'S CENTRE -- a wedge of the circle
-- and the rest of it -- and gives each piece its own territory, patrol loop and
-- demolisher, so a big volcano carries a big guard and a medium one at the same
-- time. Why a centre cut, why one cut, and how the sizes come from the ladder are
-- the measured story, told in AGENTS.md ("Demolisher territory design") and
-- measured by tests/split_probe.lua (what a seed splits into) and
-- tests/split_shape.lua (what the two loops look like).
--
-- It is a construction of OURS, like the patrol path (volcano-patrol-path.lua),
-- not in noise-mirror/: everything it reads is a pure function of position, so the
-- same volcano is cut the same way on every machine and every load, in either chunk
-- generation order.

local Demolisher = require("volcano-demolisher")
local PatrolPath = require("volcano-patrol-path")

local abs = math.abs
local cos, sin, pi = math.cos, math.sin, math.pi
local CHUNK = 32

local M = {}

-- The wedge is clamped to between a tenth and a half of the circle: wider than a
-- half-disc is not a slice of a pie, and below 0.17 the RIM's ends -- a chunk clear
-- of the cuts, in TILES on a small radius -- have no span left to walk (the old
-- quarter floor was about the sliver's guard, which the rim's own arithmetic now
-- answers directly).
local MIN_FRACTION = 0.17
local MAX_FRACTION = 0.5
-- How finely the cut is scanned below -- arithmetic rather than search (two ladder
-- lookups each), and it is what lets the cut be taken from the middle of a range of
-- cuts instead of off one edge of it.
local CUT_STEPS = 20

-- The distance the two loops may not come within, which is the two clearances plus the
-- chunk-quantisation slack a walked point can spend. Measured over three seeds x three
-- frequencies, and a cut that cannot hold it is refused rather than made.
local LOOP_SEPARATION = 32
-- A claim below this is a rim sliver whatever the arithmetic says.
local MIN_SHARE = 16

--- The demolisher tier a cone this wide carries. `size_fraction` reads nothing but
--- the width, so the whole cone is not needed -- and the ladder is what decides the
--- sizes, so it is asked here rather than a threshold being invented.
local function class_for(volcanoes, width)
  return Demolisher.demolisher_class(volcanoes, { width = width })
end

--- Which way this cut runs. A plain integer hash of the cone's id: no noise, no
--- state, and the same cut on every machine and every load. Two neighbouring cones
-- do not all get the same bearing.
function M.angle_for(cone)
  local hash = 0
  for index = 1, #cone.id do
    hash = (hash * 31 + cone.id:byte(index)) % 1000003
  end
  return hash / 1000003 * 2 * pi
end

--- The claim of one slice as a SET of chunks, keyed the way PatrolPath keys them.
--- PATROL-PATH publishes the same builder (M.set_for), and a second copy of that
--- packing is a second place for the two loop builders to disagree -- so this is
--- that one, taken from the module that owns the key.
local set_for = PatrolPath.set_for

--- The claim of one slice as a SET of chunks, keyed the way PatrolPath keys them.
--- PATROL-PATH publishes the same builder (M.set_for), and a second copy of that
--- packing is a second place for the two loop builders to disagree -- so this is
--- that one, taken from the module that owns the key.
local set_for = PatrolPath.set_for

--- The furthest radius along a direction that still lands on THIS slice's claimed
--- chunks -- the arc point, not the analytic one, because the claim is what a patrol
--- path may stand on. The march itself is PatrolPath.edge_radius (last-radius, not
--- first-miss -- same chunk-quantised-claim logic the whole claim's loop uses); this
--- shells out to it with the cone centre as the start and the analytic ground radius
--- as the limit.

--- The claim, cut in two, or nil with the reason it was not. A LOCAL: the only
--- caller is `slices` below, and the module's public face is the one-or-two list.
local function plan(volcanoes, cone, share, contenders)
  if #share < MIN_SHARE then return nil, "a claim of " .. #share .. " chunks is a sliver" end
  local whole = volcanoes:size_fraction(cone)
  local class = class_for(volcanoes, cone.width)
  if class < 2 then
    return nil, "it already carries the smallest guard"
  end

  -- How much of the disc the small slice takes, so the two sides land on ADJACENT
  -- rungs, the highest pair this cone can carry. A slice with a fraction `f` of the
  -- area reads a size fraction of `whole * sqrt(f)` (width scales with sqrt of the
  -- area), so the cut is CHOSEN by scanning the ladder over the whole range and
  -- taking the MIDDLE of the cuts that read as an adjacent pair -- an edge cut sits
  -- on a tier boundary, one float from reading the rung above it. A cone just above
  -- a boundary often has no adjacent pair at all (halving drops it two rungs, and
  -- the pair below does not exist): that is the feature's real limit, and mostly
  -- small+medium with medium+big only on the very largest cones is what a three-rung
  -- ladder gives.
  local qualifying, cuts = {}, 0
  for step = 0, CUT_STEPS do
    local cut = MIN_FRACTION + (MAX_FRACTION - MIN_FRACTION) * step / CUT_STEPS
    local small_class = class_for(volcanoes, cone.width * math.sqrt(cut))
    local large_class = class_for(volcanoes, cone.width * math.sqrt(1 - cut))
    if large_class == small_class + 1 then
      cuts = cuts + 1
      qualifying[cuts] = cut
    end
  end
  local fraction = cuts > 0 and qualifying[math.ceil(cuts / 2)] or nil
  if not fraction then
    return nil, string.format("no cut of a cone this size lands two guards one rung apart "
      .. "(it is at %.2f of the largest)", whole)
  end

  local angle = M.angle_for(cone)
  local half_angle = pi * fraction
  local cos_a, sin_a = cos(angle), sin(angle)
  local tan_half = math.tan(half_angle)

  -- The two pieces, cut at the CHUNK's centre: the cut is ours, so it does not need
  -- the wobble the claim is measured with, and a sign is a sign either way. The
  -- pieces are DISJOINT because the test is TOTAL: every chunk takes one side or the
  -- other and there is no third outcome, so the engine's "a chunk belongs to one
  -- territory" rule can never be asked to settle an overlap -- the engine settles
  -- overlaps SILENTLY by taking the chunk from whoever held it, which would make the
  -- pieces depend on build order. Total test, no third outcome, so the only possible
  -- outcomes are the two slices; proved (not assumed) by tests/builder_test.lua's
  -- "the cut is the same whichever slice is built first".
  local small, large = {}, {}
  for _, chunk in ipairs(share) do
    local px = chunk.x * CHUNK + CHUNK / 2 - cone.x
    local py = chunk.y * CHUNK + CHUNK / 2 - cone.y
    local along = px * cos_a + py * sin_a
    local across = -px * sin_a + py * cos_a
    -- `along * tan_half` is negative behind the apex, so every chunk there is the
    -- large side's without a second test -- and a chunk whose centre lands exactly
    -- where the cone centre does reads as the small side, which is the side that was
    -- asked for. Either way: one owner, every time.
    if abs(across) <= along * tan_half then
      small[#small + 1] = chunk
    else
      large[#large + 1] = chunk
    end
  end

  local slices = {}
  for _, side_of_cut in ipairs{ { small, false }, { large, true } } do
    local chunks, keep_large = side_of_cut[1], side_of_cut[2]
    local side = #slices + 1
    local part = fraction
    if keep_large then part = 1 - fraction end
    -- The slice is a cone of the same centre and a smaller width: everything the
    -- claim asks a cone for (its size, its ground radius, its identity in a log
    -- line) is the cone's own, scaled by how much of it this piece is.
    local piece = {
      -- The cone's OWN id: the claim's rival filter (patrol_circle) drops a rival
      -- by comparing ids, and a slice of this cone is not a rival of itself. The
      -- piece is named in the log by the builder, which knows which side it is.
      id = cone.id,
      x = cone.x, y = cone.y,
      width = cone.width * math.sqrt(part),
    }
    -- Each side's own wedge: the large one is the SAME cut read from the other side,
    -- so its axis is opposite and its half-angle is the rest of the circle. (Building
    -- both on the small side's axis gave the large slice a 126 degree arc and a loop
    -- half the length it should have -- measured, on a 234 degree slice.)
    local side_angle = keep_large and angle + pi or angle
    local side_half = keep_large and pi - half_angle or half_angle
    local path = PatrolPath.wedge_outline(volcanoes, cone, chunks, side_angle, side_half, contenders)
    slices[side] = { cone = piece, share = chunks, set = set_for(chunks),
                     patrol_path = path, fraction = part, large = keep_large,
                     rim = RIM_FRACTION }
  end

  -- Both guards must FIT, each at the rung its own area gives it, and the pair must
  -- stay one rung apart. `demolisher_for` steps a size DOWN until the body fits the
  -- loop, so a slice that came back stepped is a slice whose loop is too short -- and
  -- two guards that both stepped down to the same size is a split that bought nothing
  -- but two territories instead of one. Both are reasons to leave the cone whole.
  for _, slice in ipairs(slices) do
    if not slice.patrol_path then
      return nil, "a " .. (slice.large and "large" or "small") .. " slice has no loop on its own ground"
    end
    local wanted = class_for(volcanoes, slice.cone.width)
    local got = Demolisher.demolisher_for(volcanoes, slice.cone, slice.patrol_path)
    if not got then
      return nil, "a " .. (slice.large and "large" or "small") .. " slice cannot carry "
        .. "even the smallest guard (" .. math.floor(
          Demolisher.patrol_path_length(slice.patrol_path)) .. " tiles of loop)"
    end
    slice.class = got
    if got ~= wanted then
      return nil, "a " .. (slice.large and "large" or "small") .. " slice carries a "
        .. "smaller guard than its own ground suggests"
    end
  end
  -- The two loops must not come near each other (playtest: "must not overlap or get
  -- too close to the neighbour's patrol path"). The arcs are a chunk clear of the cut
  -- on each side by construction, so the only way to fail is a point the WALK moved --
  -- hence the measurement, and a cut refused for it.
  local closest = math.huge
  for _, a in ipairs(slices[1].patrol_path) do
    for _, b in ipairs(slices[2].patrol_path) do
      local dx, dy = a.x - b.x, a.y - b.y
      local d = dx * dx + dy * dy
      if d < closest then closest = d end
    end
  end
  if math.sqrt(closest) < LOOP_SEPARATION then
    return nil, string.format("the two loops would come within %.0f tiles of each other",
      math.sqrt(closest))
  end
  if slices[2].class - slices[1].class ~= 1 then
    return nil, string.format("the two slices would carry rungs %d and %d",
      slices[1].class, slices[2].class)
  end
  return slices
end

--- The claim as ONE OR TWO slices, and a membership test over either of them.
---
--- Always a list: one slice is the cone whole, which is the path this file did not
--- take and the one every rejection above lands on. The caller does not branch on
--- how many there are, because "a volcano is claimed as one or two territories" is
--- the whole contract and the number is an answer, not a decision.
function M.slices(volcanoes, cone, share, contenders)
  local slices, reason = plan(volcanoes, cone, share, contenders)
  if not slices then
    slices = {
      { cone = cone, share = share, fraction = 1,
        patrol_path = Demolisher.patrol_path(volcanoes, cone, share, contenders) },
    }
  end
  for _, slice in ipairs(slices) do
    slice.set = slice.set or set_for(slice.share)
  end
  slices.unsplit_reason = reason
  return slices
end

--- Is this chunk one of this slice's? The engine's one precondition on
--- create_territory is a GENERATED chunk in the list, and the chunk that woke us is
--- generated -- so the question is not "is this chunk revealed" but "is it mine",
--- and that is this. No question is asked of the engine either way.
function M.holds(slice, chunk_x, chunk_y)
  return slice.set[PatrolPath.chunk_key(chunk_x * CHUNK, chunk_y * CHUNK)] == true
end

return M