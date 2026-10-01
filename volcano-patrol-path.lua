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

--- The patrol path for this cone: a circle, DENTED where a neighbour crowds it.
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
local function chunk_key(x, y)
  return (math.floor(x / CHUNK) + 0x200000) * 0x400000 + (math.floor(y / CHUNK) + 0x200000)
end

--- `share` is the cone's own chunks (the hard limit) and `contenders` the cones it
--- overlaps (the rivals that dent the route). Both are passed in, so the rivals are
--- read rather than searched for.
function M.patrol_circle(volcanoes, cone, share, contenders)
  if #share < 4 then return nil end
  local inside = {}
  for _, chunk in ipairs(share) do
    inside[chunk_key(chunk.x * CHUNK, chunk.y * CHUNK)] = true
  end
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

  -- The rivals, and where each of them cuts us off. The claim is the bisector
  -- between our centre and theirs, so along a direction pointing at a rival the boundary
  -- is crossed at |d|^2 / (2 * (u . d)) for d = rival - us and u the direction's unit
  -- vector; a direction that points away from a rival never crosses it.
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

  -- The analytic cap, as a fraction of the CLAIM rather than of the width, so it
  -- can be swept against the folds line. The line alone overshoots into the flat
  -- zone (57% of points on the transition); the cap alone undershoots into the
  -- folds zone. The fraction that lands on it is measured, not derived.
  local function radius_at(theta)
    local ux, uy = math.cos(theta), math.sin(theta)
    -- The GROUND, not the claim. The claim is a disc of core_radius; the ground is
    -- a disc of GROUND_FRACTION * width, which is SMALLER, and the wobble moves
    -- that smaller disc about by more than the margin between the two. So a patrol path
    -- sized off the claim walks off the rock, and it does so on the small cones
    -- (margin 3.6 tiles) and not the large ones (10.6) -- which is what the
    -- playtest showed. The ground is found per direction, so the patrol path follows the
    -- wobbled edge rather than a padded circle.
    -- The FOLDS LINE is the radius, not a ceiling on one. Taking the minimum with
    -- `base` (0.78 * the claim, i.e. 0.328 * width) left the patrol path permanently
    -- inside the folds zone, because the line sits at 0.350: the line only bit
    -- where the wobble dipped under it, and 13% of points came out on the folds
    -- tile with folds-flat still further out.
    -- The boundary IS the radius, with nothing under it. A cap binds wherever the
    -- boundary is further out than the cap, which parks the patrol path inside the
    -- volcano and leaves `volcanic-folds` visible beyond it.
    local radius = M.wobbled_radius(volcanoes, cone, ux, uy, VC.FOLDS_LINE_FRACTION)
    for _, d in ipairs(rivals) do
      local along = ux * d.x + uy * d.y
      if along > 0 then
        -- The same fraction of the way to the border with that neighbour as the
        -- circle takes of the core radius when the neighbour is not there, so the
        -- dent is a shortening of the same radius rather than a second rule: it
        -- deepens as the rival comes closer and vanishes when it goes away, and it
        -- always keeps that fraction of the ground between here and the border.
        local border = (d.x * d.x + d.y * d.y) / (2 * along)
        radius = math.min(radius, border * PATROL_RADIUS_FRACTION)
      end
    end
    return radius
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
    -- The LAST radius that lands in the claim, not the first that misses. A squashed
    -- claim often does NOT contain its own centre (a neighbour won the centre chunk),
    -- and a march that stops at the first miss begins already outside and collapses
    -- the patrol path to a stub. Missing ground NEAR THE ORIGIN is tolerated for that
    -- reason and only there: past the middle of the volcano, a miss is the rim of a
    -- clipping neighbour and stopping is the point.
    local last, grace = 0, cone.core_radius * 0.5
    local theta = 2 * math.pi * index / directions
    local cos_t, sin_t = math.cos(theta), math.sin(theta)
    for step = 1, 150 do
      local candidate = step * 2
      local x, y = origin_x + candidate * cos_t, origin_y + candidate * sin_t
      if inside[chunk_key(x, y)] then
        last = candidate
      elseif candidate > grace then
        break
      end
    end
    return last
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
return M
