-- The patrol path: where a guard walks, and how far the ground reaches.
--
-- This is OURS, not a port, which is why it is here at the root rather than in
-- noise-mirror/. That directory mirrors Factorio's noise -- its basis functions,
-- its candidate stream, its cone placement -- and knows nothing about territories,
-- demolishers or patrol paths. The patrol path is a construction of ours that CONSUMES the
-- mirror's volcanoes, exactly as volcano-demolisher.lua does, and it changes for its
-- own reasons: this moves when the boundary constants move, where the claim in
-- volcano-cones.lua moves when the split moves.
--
-- It takes the volcanoes rather than holding a reference, for the same reason
-- volcano-demolisher.lua does: a constructor parameter a caller passes is not
-- state, and it keeps every claim about the mirror's own ownership out of here.

local cones = require("noise-mirror.volcano-cones")
local VC = require("volcano-constants")

local M = {}

-- The patrol path's own two numbers, and they live HERE rather than in noise-mirror/,
-- which mirrors Factorio's noise and has no opinion about patrols.
--
-- PATROL_DIRECTIONS is PUBLISHED because the demolisher samples the same number of
-- directions to lay its body along, and the patrol path's closure snaps an angle to the
-- nearest direction: if the two counts disagree, the builder visits some directions
-- twice and never visits others, and the only symptom is a patrol path that looks
-- slightly wrong -- four coincident points on every path.
M.PATROL_DIRECTIONS = 32
local PATROL_DIRECTIONS = M.PATROL_DIRECTIONS
-- The patrol loop sits at this fraction of the core radius, unless a rival cone is
-- nearer (see M.patrol_circle).
local PATROL_RADIUS_FRACTION = 0.78
-- The chunk grid, in tiles.
local CHUNK = 32

-- The packed key a world position maps to its chunk. PUBLISHED because the cut
-- (volcano-split.lua) asks the same question of a chunk list -- "is this chunk one
-- of yours" -- and two copies of this packing is two places for it to be wrong.
local function chunk_key(x, y)
  return (math.floor(x / CHUNK) + 0x200000) * 0x400000 + (math.floor(y / CHUNK) + 0x200000)
end
M.chunk_key = chunk_key

--- A chunk list as a membership SET keyed the way chunks are -- "is this chunk one of
--- yours" -- which is the one question every loop builder asks of a list. PUBLISHED
--- because the cut (volcano-split.lua) and its probes build the same set from the
--- same lists.
function M.set_for(chunks)
  local set = {}
  for _, chunk in ipairs(chunks) do
    set[chunk_key(chunk.x * CHUNK, chunk.y * CHUNK)] = true
  end
  return set
end

--- The LAST radius from a point along a direction that still lands in a claimed
--- chunk, or 0 when nothing does. PUBLISHED because the cut's arcs are the same
--- march, limited by the analytic ground radius instead of unlimited.
---
--- Marched outwards two tiles at a time and taking the LAST hit: the claim is
--- chunk-quantised, so a march that stopped at the FIRST miss would treat one chunk
--- of a ragged edge as the whole edge and pull a loop in to nothing. Missing ground
--- NEAR THE ORIGIN is tolerated for the same reason -- a squashed claim can fail to
--- contain the point the march was reached from (a neighbour can win the cone's own
--- centre chunk), so the first hits may not start until the ray clears the bite --
--- and only there: past half the core radius a miss is the rim of a clipping
--- neighbour and stopping is the point. The break needs a hit first (`last > 0`)
--- for the same cold-start reason: a ray that only reaches ground beyond the grace
--- radius is finding the claim, not the rim of a neighbour.
function M.edge_radius(inside, cone, x, y, ux, uy, limit)
  local grace, last = cone.core_radius * 0.5, 0
  for step = 1, 300 do
    local radius = step * 2
    if limit and radius > limit + 2 then break end
    if inside[chunk_key(x + ux * radius, y + uy * radius)] then
      last = radius
    elseif last > 0 and radius > grace then
      break
    end
  end
  return last
end

--- How far this cone's ground reaches along one direction, in world tiles.
---
--- Where the ground ends: the radius whose world point, pushed through the wobble,
--- lands on the cone's ground circle.
---
--- The engine evaluates the spot volcanoes at the DISPLACED position: world point q is
--- cone ground when |q + w(q) - C| is inside the ground circle (see
--- Volcanoes:cone_value). So the edge is the PREIMAGE of a circle under a
--- position-dependent displacement, and a preimage is not a circle: the radial
--- component of w swings about +/-16 tiles over a 175-tile radius, so the edge
--- wanders in and out of the circle along every direction. Any construction of it
--- is therefore an approximation, and the only question is which one.
---
--- This is the first-order inverse, and it is ONE wobble evaluation per direction:
--- take the nominal circle point p, read the displacement there, and step back by
--- its RADIAL component, r = radius - (w . u). Then p - w(p) maps back onto p to
--- first order, so the node sits on the ground circle to first order.
---
--- The tangential part of w is dropped. It moves the node sideways rather than in or
--- out, so it turns the node by at most asin(w_t / radius) -- under 6 degrees on
--- the smallest cone, and the neighbouring direction's own node covers that.
---
--- The claim (0.4361) is the right disc to bound a patrol path by, not the folds
--- score (0.3502). Measured on the small cone the playtest found, seed 2990337218
--- at -1573,1298, width 159: the wobbled CLAIM runs 48 to 84 tiles over 32
--- directions and the game's own rendered tiles measured 53 to 87, while the
--- wobbled folds bound runs 36 to 72 -- seventeen tiles inside the rock for no
--- benefit. The claim is within about four tiles of the truth and always on the
--- safe side of it, and the claim is already what the territory holds.
function M.wobbled_radius(volcanoes, cone, ux, uy, fraction)
  local radius = fraction * cone.width
  local wx, wy = cones.wobble(volcanoes.context, cone.x + ux * radius, cone.y + uy * radius)
  return radius - (wx * ux + wy * uy)
end

--- The patrol path for this claim: a circle, DENTED where a neighbour crowds it.
---
--- This is the WHOLE claim's route. A cut claim (volcano-split.lua) builds its own
--- loop per slice, because this shape is polar about the CONE's centre and half a
--- volcano is not the middle of a volcano.
---
--- The shape, in one sentence: a circle of PATROL_RADIUS_FRACTION of the core
--- radius, shortened in every direction where a neighbouring cone takes the ground
--- away to PATROL_RADIUS_FRACTION of the distance to that neighbour's border. So an
--- untouched volcano gets a plain circle, and one squashed against a neighbour gets
--- a circle with a dent on the crowded side that deepens as the neighbour comes
--- closer (measured on the playtest's 3-series: radius 104 on the open side, 68 on
--- the squashed one, where the border is at 87).
---
--- Why per direction rather than one smaller radius or a fitted ellipse: a single
--- radius has to be small enough for the worst direction and is therefore small
--- everywhere (17% of the claim on a merged volcano), and an ellipse describes the
--- claim's outline rather than the space left for the unit. The dent keeps the full
--- circle wherever there is room and gives up ground only where there is not.
---
--- The border with a neighbour is the bisector between the two centres, so along a
--- direction pointing at it the border is crossed at |d|^2 / (2 * (u . d)); a direction that
--- points away from a neighbour never crosses it and is left alone. Directions
--- whose point still lands outside the claim (the claim is quantised, the path is
--- not) are tightened individually, so the shape stays the same shape.
--- @return centre x, centre y, and a function from an angle to a point on the path
-- `share` and `contenders` are both passed in: they are the most expensive things
-- the mirror computes (8.5 ms for a 145-chunk share) and the caller has them.
-- The claim as a SET, keyed by a packed integer rather than "x,y": the marches
-- below do ~3,500 lookups per patrol path, and building a two-number string for
-- each one cost 2.55 ms against 0.80 ms for the arithmetic (measured on a
-- 145-chunk claim, 32 directions). The packing is exact -- both halves are integers and
-- the whole key is under 2^53 -- and it covers +/-2^21 chunks, which is +/-67M
-- tiles, far past anything the engine will generate.
local chunk_key = M.chunk_key

-- The rivals that dent this cone's route, as offsets from its centre. PUBLISHED
-- because a cut claim follows the SAME radius shape over its own arc
-- (volcano-split.lua), and the rivals should be read once rather than searched twice.
function M.rivals_of(cone, contenders)
  local rivals = {}
  for i = 1, contenders.n do
    local other = contenders[i]
    if other.id ~= cone.id then
      rivals[#rivals + 1] = {
        x = other.x - cone.x,
        y = other.y - cone.y,
      }
    end
  end
  return rivals
end

--- THE patrol radius along one direction, which is the whole shape a patrol path is:
--- the GROUND rather than the claim, dented where a neighbouring cone takes it away.
---
--- PUBLISHED for the same reason as rivals_of: a cut claim's arc is this same curve
--- restricted to its wedge, so the two halves of a volcano trace the edge the whole
--- volcano would have traced.
---
--- The GROUND, not the claim. The claim is a disc of core_radius; the ground is a disc
--- of GROUND_FRACTION * width, which is SMALLER, and the wobble moves that smaller disc
--- about by more than the margin between the two. So a patrol path sized off the claim
--- walks off the rock, and it does so on the small cones (margin 3.6 tiles) and not the
--- large ones (10.6) -- which is what the playtest showed. The ground is found per
--- direction, so the patrol path follows the wobbled edge rather than a padded circle.
---
--- The FOLDS LINE is the radius, not a ceiling on one. Taking the minimum with `base`
--- (0.78 * the claim, i.e. 0.328 * width) left the patrol path permanently inside the
--- folds zone, because the line sits at 0.350: the line only bit where the wobble
--- dipped under it, and 13% of points came out on the folds tile with folds-flat
--- still further out. The boundary IS the radius, with nothing under it.
---
--- The border with a neighbour is the bisector between the two centres, so along a
--- direction pointing at it the border is crossed at |d|^2 / (2 * (u . d)); a direction
--- that points away from a rival never crosses it. The dent keeps the same fraction of
--- the ground between here and the border, so it deepens as the rival comes closer and
--- vanishes when it goes away.
function M.ground_radius(volcanoes, cone, theta, rivals)
  local ux, uy = math.cos(theta), math.sin(theta)
  local radius = M.wobbled_radius(volcanoes, cone, ux, uy, VC.FOLDS_LINE_FRACTION)
  for _, d in ipairs(rivals or {}) do
    local along = ux * d.x + uy * d.y
    if along > 0 then
      local border = (d.x * d.x + d.y * d.y) / (2 * along)
      radius = math.min(radius, border * PATROL_RADIUS_FRACTION)
    end
  end
  return radius
end

--- `share` is the cone's own chunks (the hard limit) and `contenders` the cones it
--- overlaps (the rivals that dent the route). Both are passed in, so the rivals are
--- read rather than searched for.
function M.patrol_circle(volcanoes, cone, share, contenders)
  if #share < 4 then return nil end
  local inside = M.set_for(share)
  -- The patrol path is centred on the CONE, which is a known point, and never on the
  -- claim's centre of mass. A disc with two bites out of one side is lopsided, and the
  -- average of what is left sits away from the bites -- measured 72, 75 and 88 tiles
  -- off the cone on a triplet of 156-tile-apart neighbours.
  --
  -- The fallback below is the one case that needs a claimed chunk: a crescent whose
  -- cone centre was taken by a neighbour, where there is no in-claim point near it.
  local cx, cy = cone.x, cone.y
  local origin_x, origin_y = cx, cy
  if not inside[chunk_key(cx, cy)] then
    local best
    for _, chunk in ipairs(share) do
      local d = (chunk.x * CHUNK + CHUNK / 2 - cx) ^ 2 + (chunk.y * CHUNK + CHUNK / 2 - cy) ^ 2
      if not best or d < best.d then best = { chunk = chunk, d = d } end
    end
    origin_x = best.chunk.x * CHUNK + CHUNK / 2
    origin_y = best.chunk.y * CHUNK + CHUNK / 2
  end

  -- The rivals, and where each of them cuts us off (M.rivals_of, published so a cut
  -- claim dents its own arc with the same list rather than searching again).
  local rivals = M.rivals_of(cone, contenders)

  -- The analytic cap, as a fraction of the CLAIM rather than of the width, so it
  -- can be swept against the folds line. The line alone overshoots into the flat
  -- zone (57% of points on the transition); the cap alone undershoots into the
  -- folds zone. The fraction that lands on it is measured, not derived. All of it is
  -- M.ground_radius, PUBLISHED because a cut claim's arc is this same curve taken
  -- over its own wedge.
  local function radius_at(theta)
    return M.ground_radius(volcanoes, cone, theta, rivals)
  end
  local function point_at(theta, scale)
    local radius = radius_at(theta)
    if scale then radius = radius * scale end
    return origin_x + radius * math.cos(theta), origin_y + radius * math.sin(theta)
  end
  local directions = PATROL_DIRECTIONS
  -- Per-direction radius, clamped to the claim rather than assumed from the shape.
  --
  -- The analytic radius is a bad estimate of where this cone's claim ENDS, because
  -- the claim rule and the shape's own bisector disagree on a squashed cone.
  -- Measured at 600% volcanism: on the crowded side the patrol path walked 9-23
  -- tiles while the cone's OWN chunks reached 36-76, so the guard patrolled a thin
  -- arc and abandoned ground the claim still held -- the opposite of what this
  -- shape is documented to do ("gives up ground only where there is not [room]").
  --
  -- So the analytic shape is a TARGET and the claim is the limit. A direction whose
  -- target lands in the claim takes it, which is what keeps an untouched volcano a
  -- clean circle. A direction whose target was given away takes the furthest radius
  -- that still lands in a claimed chunk instead (edge_at below, then a bisection
  -- between the origin and that radius).
  --
  -- That is why both halves are needed. Searching only upward -- scale the whole
  -- shape until it fits -- returned no patrol path at all for 7 of the squashed
  -- cones at 600%, every one a volcano the engine had actually placed. A
  -- cone the map put there does not get to be unhostable because our shape was a
  -- circle.
  --
  -- Inside the claim BY CONSTRUCTION, per direction: the radius is the furthest one
  -- that still lands in a claimed chunk, so every node is on claimed ground and the
  -- check at the end of this function has nothing left to find.
  local function fits_radius(index, radius)
    local theta = 2 * math.pi * index / directions
    local x = origin_x + radius * math.cos(theta)
    local y = origin_y + radius * math.sin(theta)
    return inside[chunk_key(x, y)] == true
  end
  local function edge_at(index)
    -- The march is M.edge_radius (the LAST radius that lands in the claim, never the
    -- first -- see the shared function for why). The origin is always a claimed
    -- chunk's centre (the cone's own, or the nearest one when a neighbour won the
    -- centre), so the first step hits and the limit is unlimited.
    local theta = 2 * math.pi * index / directions
    return M.edge_radius(inside, cone, origin_x, origin_y, math.cos(theta),
      math.sin(theta), nil)
  end
  local function point_in_direction(index)
    local seed = radius_at(2 * math.pi * index / directions)
    local found = edge_at(index)
    if found == 0 then
      -- No claimed ground on this direction at all. Take the analytic radius if it is
      -- inside, and the centre otherwise, so the patrol path is always a closed loop
      -- rather than a gap -- and Builder:patrol_path reports the claim as a defect.
      if fits_radius(index, seed) then
        return origin_x + seed * math.cos(2 * math.pi * index / directions),
          origin_y + seed * math.sin(2 * math.pi * index / directions)
      end
      return origin_x, origin_y
    end
    -- The analytic radius is the TARGET, and the search only CLAMPS: if it already
    -- lands in the claim the patrol path is the smooth circle, and only where a squashed
    -- claim rejects it does the direction pull inward. Searching up to the claim rim
    -- instead overshot the shape and made even round cones wobble.
    if fits_radius(index, seed) then
      local t = 2 * math.pi * index / directions
      return origin_x + seed * math.cos(t), origin_y + seed * math.sin(t)
    end
    local low, high = 0, found
    for _ = 1, 12 do
      local mid = (low + high) / 2
      if fits_radius(index, mid) then low = mid else high = mid end
    end
    local theta = 2 * math.pi * index / directions
    return origin_x + low * math.cos(theta), origin_y + low * math.sin(theta)
  end
  for index = 0, directions - 1 do
    local x, y = point_in_direction(index)
    if not inside[chunk_key(x, y)] then return nil end
  end
  return origin_x, origin_y, function(theta)
    -- Snap to the nearest direction, not the one below. The caller samples at exactly
    -- 2*pi*index/directions, and `theta / 2*pi * directions` lands a hair UNDER the integer for
    -- four of the 32 (float error), so floor sent each of them back to the previous
    -- direction: four duplicated points, four directions never visited, and the whole shape
    -- sitting half a direction clockwise of where it was sampled. Measured on the
    -- 307,-680 volcano, where four path points were exactly coincident.
    local index = math.floor((theta % (2 * math.pi)) / (2 * math.pi) * directions + 0.5) % directions
    return point_in_direction(index)
  end
end

-- =====================================================================
-- The cut's loops. volcano-split.lua decides WHETHER a big claim is cut
-- in two; the SHAPE of a slice's loop -- an annular sector on the same
-- wobble-derived curves every loop here uses -- lives in this module,
-- beside the whole-claim circle, so every patrol arc is in one file and
-- the shared primitives (ground_radius, edge_radius, set_for, rivals_of,
-- start_north) need no cross-module hop. The TERRITORY edge (which chunks
-- are the volcano) is not here at all: that is the mirror's disc
-- (disc_chunks, VOLCANIC_EDGE_FRACTION), and a patrol loop walks INSIDE
-- it on the folds line (FOLDS_LINE_FRACTION) -- see AGENTS.md.
-- Tiles each loop keeps off the cut: membership is decided by the CHUNK CENTRE, so
-- a leg on the line is as likely as not in a chunk whose centre is on the other
-- side -- a chunk and a half clears it, and it also keeps the two guards apart (the
-- legs are the loops' closest points: at a margin of 4 they measured 5 tiles, at 8
-- touching).
-- CAPPED at a quarter of the cone's reach: a fixed 48-tile margin on a small cone
-- eats the wedge (measured: the cuts went from 26 to 4 per map).
local CUT_MARGIN = 48
-- RIM_FRACTION of the ground radius. NOT the inner edge of the claim: that is
-- chunk-quantised, which was the playtest's "hugging too closely" + "jitter in the
-- inner path" together. It is also the whole of "the two guards must not meet in
-- the middle": a wedge closed at the apex puts both legs through the same point
-- (measured closest approach 0), so each loop closes on this rim instead of on a
-- tip -- and the claim itself is NOT cut back (AGENTS.md).
--
-- 0.33 of the ground radius is 0.115 of the width, which is where the LAVA is, not
-- where it looked like lava should be. The chain (map-generation/terrain.lua:
-- eon_mountain_lava_spots -> range_select lava / lava-hot) solves, off the spot
-- field (3/pi)(1 - d/width), to a pool at d < 0.060*width, hot out to 0.083,
-- nothing past 0.106 -- a tenth of the cone, inside the folds line (0.350) the
-- outer arc walks. At 0.45 of the ground radius the rim sat at 0.158*width, outside
-- the lava entirely ("inner arc doesn't follow the lava", fair); now just past it,
-- and the lava comes from the SAME spot field, so the same wobble roughens both,
-- for free.
local RIM_FRACTION = 0.33
-- ...and never nearer the centre than this, in TILES, because the fraction is of the
-- ground radius along EACH DIRECTION and a cone a neighbour has dented hard on one
-- side has a much shorter reach there.
local RIM_FLOOR = 24
-- Tiles each arc's ends keep from the cut lines: half the distance between the two
-- slices' loops, and a chunk at least -- see the clearance arithmetic in wedge_outline.
local RIM_CLEARANCE = 16
-- Tiles of claim every point of a loop must have under it, in each of the four
-- directions, before the loop is walked. A quarter of a chunk: the guard is a tile wide
-- and the line between two of its points is not the claim.
local ROOM_TILES = 8
--- Zero-length edges dropped. Not cosmetic: the body layout seeds its heading along
--- the FIRST edge and refuses to lay a body that has none, so one repeated point is a
--- slice with a class and no demolisher. The one live producer is the WALK
--- (pull_inside): it steps a point onto its on-claim neighbour, so the two coincide
--- exactly -- which is why this runs after it. (In the pre-rim design, which closed
--- the wedge at the apex, a repeated centre point also came from every direction
--- outside the wedge; the annular sector has no apex, so the walk is the only source.)
local function drop_repeats(points)
  local kept = {}
  for _, point in ipairs(points) do
    local last = kept[#kept]
    if not last or math.abs(last.x - point.x) > 1e-6 or math.abs(last.y - point.y) > 1e-6 then
      kept[#kept + 1] = point
    end
  end
  -- Closed loop: the last point must not repeat the first either, or the closing edge
  -- is the zero-length one and the rotation can start on it. Consecutive duplicates
  -- were already dropped above, so at most the closing point can repeat the first.
  if #kept > 2 and math.abs(kept[1].x - kept[#kept].x) < 1e-6
    and math.abs(kept[1].y - kept[#kept].y) < 1e-6 then
    kept[#kept] = nil
  end
  return kept
end





--- Every point of the loop stands on this slice's OWN ground, and rounding the
--- outline is what puts a few off it: corner cutting bulges a hair outside the sharp
--- polygon it replaces, and an arc's edge IS the claim's edge.
---
--- A bulge is fixed by MOVING THE POINT TOWARD ITS OWN NEIGHBOURS -- the points
--- either side of it are on the claim, so the walk ends on ground by definition (the
--- first attempt walked toward the neighbours' MIDPOINT, and a several-tile bulge's
--- midpoint is a third chunk again: measured, every cut refused). Marching along the
--- radius instead -- which predates that -- lands on the claim's CHUNK-QUANTISED lips
--- (the playtest's "hugging" and "jitter", a loop point measured 0 tiles from the
--- cone centre), so it is gone. A point with no on-claim neighbour within PULL_REACH
--- is not a bulge but somewhere the loop cannot stand, and the cut is refused rather
--- than drawn there; the same for a walk longer than PULL_MAX (a tile or two of corner
--- cutting is a bulge, a hundred tiles is a loop drawn in the wrong place).
local PULL_REACH = 4
local PULL_MAX = 48
local function pull_inside(points, inside, cone, angle, half_angle)
  local on_claim = {}
  for index, point in ipairs(points) do
    on_claim[index] = inside[chunk_key(point.x, point.y)] == true
  end
  for index, point in ipairs(points) do
    if not on_claim[index] then
      local before, after
      for step = 1, PULL_REACH do
        local left = ((index - 1 - step) % #points) + 1
        if on_claim[left] then before = points[left] break end
      end
      for step = 1, PULL_REACH do
        local right = ((index - 1 + step) % #points) + 1
        if on_claim[right] then after = points[right] break end
      end
      if not before or not after then
        return nil
      end
      -- Toward the NEARER of the two, walked a tile at a time, and the walk ends on that
      -- neighbour -- which is on the claim by definition, so there is nowhere for it to
      -- fail. Halfway between the two was the first attempt and it is not enough: a
      -- bulge can be several tiles deep and the two neighbours can be two chunks away,
      -- so their midpoint is a third chunk again (measured: every cut refused).
      local target = before
      if (after.x - point.x) ^ 2 + (after.y - point.y) ^ 2
        < (before.x - point.x) ^ 2 + (before.y - point.y) ^ 2 then target = after end
      local span = math.sqrt((target.x - point.x) ^ 2 + (target.y - point.y) ^ 2)
      -- A bulge is a tile or two of corner cutting. A point a hundred tiles from any
      -- ground is not a bulge, it is a loop drawn in the wrong place, and walking it
      -- across to its neighbour would make the two guards' loops cross on that side.
      if span > PULL_MAX then return nil end
      local steps = math.max(1, math.ceil(span))
      for step = 1, steps do
        point.x = point.x + (target.x - point.x) / (steps - step + 1)
        point.y = point.y + (target.y - point.y) / (steps - step + 1)
        on_claim[index] = inside[chunk_key(point.x, point.y)] == true
        if on_claim[index] then break end
      end
      if not on_claim[index] then
        return nil
      end
    end
  end
  return points
end

--- Where this side's loop stands: an ANNULAR SECTOR of the claim. ONE shape, four
--- parts, all the volcano's own: the OUTER ARC is the ground edge
--- (`PatrolPath.ground_radius`) over the wedge's directions, the two LEGS run in
--- along the cuts, and the INNER ARC closes it on the inside (RIM_FRACTION) -- a half
--- slice is a half circle with a diameter, a quarter slice a quarter pie, and both are
--- RINGS so the two guards walk either side of the same middle instead of converging
--- on it.
---
--- The joins are right angles on the un-wobbled edge (an arc's tangent is
--- perpendicular to its radius) -- ~90-140 with the wobble -- and the body carries
--- them in body_nodes rather than the path being filleted: a fillet is short edges,
--- each demanding a turn the body cannot make.
--- A slice's loop: an ANNULAR SECTOR on the shared curves, built for the wedges
--- volcano-split.lua asks for after it cuts the claim (one call per slice, both
--- halves of the cut).
function M.wedge_outline(volcanoes, cone, chunks, angle, half_angle, contenders)
  local inside = M.set_for(chunks)
  local rivals = M.rivals_of(cone, contenders)
  -- The wedge turned in by an angle worth CUT_MARGIN tiles, so each leg walks just
  -- INSIDE the cut rather than along it: a leg on the line passes through whichever
  -- chunk the line happens to fall in, which is the other slice's about as often.
  -- ONE span, for both arcs, and it is set by what the INNER arc needs: the rim's ends
  -- are the points that come closest to a cut line, and a point `c` tiles from the line
  -- is only on this side of it if c > a chunk's half-diagonal, so the rim's angular
  -- half-span is its own clearance converted to an angle.
  --
  -- Both arcs sharing the span is what makes the two joins RIGHT ANGLES. The leg
  -- between them is then a radial line, and a circle's tangent is perpendicular to its
  -- radius -- so the corner is 90 degrees, which the guard can actually make: its
  -- patrolling_turn_radius is a whole radian per tile, so a right angle costs it a tile
  -- and a half, and the arcs stop well short of the cuts, so it has open ground to do
  -- it in. Narrowing the rim's span independently (which is what this did) makes the leg
  -- run across and slightly back, and the join came out at 134-177 degrees: a hairpin
  -- the body cannot follow at all.
  --
  -- It is also why the outer arc ends so much further from the cut than the rim does:
  -- the same angle at a radius 1/0.45 the size is more than twice as many tiles.
  local reach = M.ground_radius(volcanoes, cone, angle, rivals)
  local rim_target = M.rim_radius(volcanoes, cone, angle, rivals)
  -- How far each arc's ends stand from the cut lines, which is half the distance
  -- between the two slices' loops: they are the closest the loops come, and a guard on
  -- one must not be close enough to touch the other (the playtest: "it must not
  -- overlap or get too close to the neighbour's patrol path"). A CHUNK is the floor,
  -- so the two loops are in different chunks as well as different territories.
  --
  -- And it is capped at a fraction of the rim's radius, because that is how much the
  -- rim can stand away from the centre and still be the middle of the ring. A cone whose
  -- rim cannot give a chunk is a cone with no room for two loops, and no cut is the
  -- honest answer rather than two guards a few tiles apart.
  local clearance = math.max(RIM_CLEARANCE, math.min(CUT_MARGIN, rim_target * 0.4))
  if clearance > rim_target * 0.55 then return nil end
  local wedge = math.max(0.05, half_angle
    - math.asin(math.min(0.9, clearance / rim_target)))
  -- Sampled along the arc rather than around the circle, so a quarter slice is not
  -- carrying the points a whole one would, at the whole claim's OWN density: a denser
  -- arc is not smoother here, it is a longer list for the guard to be handed, and every
  -- point on it is a place it has to be pointed at (the playtest: "we can't add many
  -- patrol path points that require turns it cannot make"). The 2x density of the
  -- whole claim's is because a slice's arc crosses a neighbour's dent and the dent is
  -- a secant (measured: 24-33 tile bulges at the old density, every one a chord
  -- straddling a dent).
  local steps = math.max(4, math.floor(M.PATROL_DIRECTIONS * wedge / math.pi))
  -- The RIM gets its own, smaller count: the same tile spacing on a ring RIM_FRACTION
  -- of the radius needs about RIM_FRACTION the points, and the same angular density on
  -- a third the circumference is three times the waypoints per tile walked -- every
  -- one a place the guard has to be pointed at. (Same count was an artifact of the two
  -- arcs sharing one loop; the dent argument that set the outer density scales with
  -- radius too, so the rim tolerates the sparser sample.) Both arcs still span exactly
  -- [angle-wedge, angle+wedge], so the legs stay radial and the joins stay right
  -- angles -- only the middle of the rim is sparser.
  local rim_steps = math.max(4, math.floor(steps * RIM_FRACTION))
  local outer, inner = {}, {}
  -- Two passes, deliberately: the outer arc is at the claim's own density and the rim
  -- at RIM_FRACTION of it (same tile spacing, see above).
  for index = 0, steps do
    local theta = angle - wedge + 2 * wedge * index / steps
    local ux, uy = math.cos(theta), math.sin(theta)
    local limit = M.ground_radius(volcanoes, cone, theta, rivals)
    -- The outer edge of this slice's ring along this direction, or -- where there is no
    -- outer edge to be found (a direction with no ground out there) -- its inner edge,
    -- which is ground too. A direction with neither means this slice is not a ring at
    -- all, and the cut is refused rather than drawn across unclaimed lava.
    local radius = M.edge_radius(inside, cone, cone.x, cone.y, ux, uy, limit)
    if radius <= 0 then
      return nil
    end
    outer[#outer + 1] = { x = cone.x + radius * ux, y = cone.y + radius * uy }
  end
  -- The rim: the same ground curve scaled in, over the SAME span, so the leg
  -- between the arcs is radial and the joins right angles; where a point of it lands
  -- off this slice's ground -- a neighbour has bitten that far -- pull_inside walks
  -- it back, and a point it cannot place refuses the cut.
  --
  -- Appended to `inner` and NOTHING else may be: a stray line added the OUTER radius
  -- here once, and the outline came out outer-out, rim-in, outer-AGAIN -- a U-turn
  -- and backtrack the playtest saw; tests/split_shape.lua's bearing check catches it.
  for index = 0, rim_steps do
    local theta = angle - wedge + 2 * wedge * index / rim_steps
    local ux, uy = math.cos(theta), math.sin(theta)
    local rim = M.rim_radius(volcanoes, cone, theta, rivals)
    inner[#inner + 1] = { x = cone.x + rim * ux, y = cone.y + rim * uy }
  end
  -- Outer arc out, rim arc back: the two legs are the joins at either end of the two
  -- arcs, and they are the corners that get rounded.
  local points = {}
  for _, point in ipairs(outer) do points[#points + 1] = point end
  for index = #inner, 1, -1 do points[#points + 1] = inner[index] end
  -- The walk LAST, and the repeats after it: a point walked back onto its own
  -- neighbour is a zero-length edge, and the body layout seeds its heading along the
  -- first edge and refuses to lay a body that has none (measured: a 41-chunk slice
  -- with a class and no unit, which the e2e correctly fails -- "a territory with no
  -- units does not exist on the map").
  local walked = pull_inside(points, inside, cone, angle, half_angle)
  if not walked then return nil end
  -- Room to STAND, not room to stand ON. A point is inside the claim, and a demolisher
  -- is a tile wide walking along a line, and the line between two points is not the
  -- claim: on a cone a neighbour has trimmed, a rim point can end up a tile or two from
  -- its edge with the body half over the border. So every point gets a quarter-chunk of
  -- claim under it in all four directions, or the cut is refused -- the same "measure it,
  -- do not hope for it" the separation gets.
  for _, point in ipairs(walked) do
    for _, offset in ipairs{ { ROOM_TILES, 0 }, { -ROOM_TILES, 0 }, { 0, ROOM_TILES },
        { 0, -ROOM_TILES } } do
      if not inside[chunk_key(point.x + offset[1], point.y + offset[2])] then
        return nil
      end
    end
  end
  walked = drop_repeats(walked)
  if #walked < 4 then return nil end
  return M.start_north(walked)
end




--- Where a slice's inner arc stands, in tiles from the cone's centre, along one
--- direction. PUBLISHED so a test can measure the loop rather than the mirror against
--- itself -- it is a shape, and the shape is what the playtest reads.
---
--- `rivals` is the list PatrolPath.rivals_of gives, not the contenders it came from:
--- every caller here has already built it for the outer arc.
function M.rim_radius(volcanoes, cone, theta, rivals)
  return math.max(M.ground_radius(volcanoes, cone, theta, rivals) * RIM_FRACTION,
    RIM_FLOOR)
end

--- The claim, cut in two
--- Rotate the loop so the guard's first move goes NORTH.
---
--- With `body_nodes` the engine ignores `direction` and always starts the head facing
--- north, so the route has to be STARTED there or the guard walks into its own tail on
--- the first step.
---
--- The NORTHWARD leg has to be the one the head sets off along, and the head no
--- longer starts at path[1]: body_nodes is reversed before create_segmented_unit
--- (get_body_nodes is front-to-back, so the head walks toward DECREASING index), so
--- the head begins at the far end of the laid body and its first move is the patrol
--- path's LAST leg. Rotating so the FIRST leg points north therefore aimed the spawn
--- the wrong way -- and by how much depended on where arc = body-length falls, which
--- is why the playtest saw it on the small demolishers (51 tiles) and not the big
--- ones (102). So the most-northward leg is rotated into the LAST position, and the
--- wrap-around leg (last -> first) is the one it takes.
function M.start_north(patrol_path)
  local best_index, best_north = 1, -math.huge
  for index = 1, #patrol_path do
    local from, to = patrol_path[index], patrol_path[(index % #patrol_path) + 1]
    local leg = (to.y - from.y) / math.max(1, math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2))
    if leg > best_north then best_north, best_index = leg, index end
  end
  local start = best_index % #patrol_path + 1
  local rotated = {}
  for step = 0, #patrol_path - 1 do
    rotated[#rotated + 1] = patrol_path[((start - 1 + step) % #patrol_path) + 1]
  end
  return rotated
end

return M
