-- The demolisher: the ladder of them, the patrol path it walks, the body that fits
-- that patrol path, and putting it on the map.
--
-- Split out of volcano-territory.lua, which is the CLAIM: existence, membership,
-- the audit. They are one-way -- the claim asks for a patrol path and for a guard, and
-- the demolisher never asks the claim anything. The ladder and its tier boundaries are
-- read here and nowhere else: `Builder:create` names a size and does not know how it
-- was measured. So this is a state move, not a file shuffle, and the two halves have
-- independent reasons to change: this one changes when a mod adds a demolisher
-- prototype or the body API changes shape, the claim changes when the map model does.
--
-- It holds three things it was given and nothing of the claim's: the surface it
-- places on, the field for cone geometry, and the one way to report an anomaly.
-- There is no `defects` table here on purpose -- a defect means the mirror and
-- the game disagree, and there is one list of those for the probe to read.

local cones = require("noise-mirror.volcano-cones")
local PatrolPath = require("volcano-patrol-path")

--- The demolisher ladder: DISCOVERED, and WEIGHTED BY BODY LENGTH.
---
--- Discovered because a hardcoded list has to be edited by hand the moment another mod
--- adds one. The one that does, behemoth-enemies 0.0.8, registers a single extra
--- tier (behemoth-demolisher, 1.5x scale) -- colossal-enemies 1.7.6 adds no
--- segmented-unit prototype at all. The weight is the body's own length, which is the
--- SAME number the fit test uses, so the ranking cannot disagree with the constraint
--- that consults it.
---
--- This is the apex-spitter shape from the deathworld scenario
--- (scenarios/Legendary Deathworld/freeplay.lua): pick the best candidate by a number
--- instead of naming the candidates. What does not transplant is where its candidate
--- list comes from -- spitters are listed by their spawner's `result_units`, and there
--- is no parent prototype that lists demolishers -- so the list here is the engine's
--- own filter over the entity prototypes.
---
--- The engine's answer is a LuaCustomTable KEYED BY NAME, and that is what forces the
--- sort. Measured on a live server:
---   * integer indexing does not work: out[1] is nil, #out is 3, out.n is nil. So
---     `ipairs` and any sequence read fail, and `table.sort` rejects the table outright
---     ("table expected, got userdata"). `pairs` is the only iteration. The two test
---     stubs return ordinary arrays, which is how that reached a gate twice.
---   * the order it yields IS a sort -- the prototype `order` string, lexicographically,
---     falling back to the name. That is what Order is for: "when the game needs to
---     sort prototypes of the same type it looks at their order properties".
---     Measured here: small=s-h, medium=s-i, big=s-j.
---
--- And that is why the ranking is still computed rather than read. `order` is a LISTING
--- key the author picks, and mods that add a demolisher choose it well -- behemoth's
--- is "s-k", right past vanilla big's "s-j", because it IS bigger -- but it is still a
--- convention, not a size: the vanilla three only ascend with length by coincidence
--- (s-h < s-i < s-j against 50.88 < 76.43 < 101.92), and an author who picks "a" for a
--- colossal lands ahead of the small one. Reading the engine's order is free; it is not
--- a size ranking, and measured length is what the ladder has to agree with.
---
--- Nothing here validates the prototypes. Factorio validates prototype definitions
--- before a mod loads, so a segmented-unit that loaded has segment_engine.segments.
---
--- Measured with base + space-age: exactly the three vanilla ones, 50.88 / 76.43 /
--- 101.92 tiles. So this changes nothing on a vanilla map and only adds tiers when a
--- mod brings them, at their natural rank.

--- Where one tier hands over to the next, as size_fraction.
---
--- These two numbers are MEASURED thresholds (see AGENTS.md: a tuned number only
--- moves against a new measurement), so they are the endpoints of the ladder and
--- a longer ladder INTERPOLATES between them rather than inventing new ones: at
--- three tiers the boundaries are exactly 0.55 and 0.8, which is what the
--- hardcoded ladder produced, and a fourth tier takes 0.675, so a modded colossal
--- only gets the biggest claims (measured with behemoth-enemies 0.0.8 loaded).
local TIER_LOW, TIER_HIGH = 0.55, 0.8

local M = {}

local function body_length(prototype)
  local segments = prototype.segment_engine.segments
  return segments[#segments].distance_from_head
end

--- Memoised: the ladder cannot change within a session, and it is the same whatever
--- surface we are on. Returns it, because a caller that wants to reason about the
--- tiers should not have to reach inside for them.
function M.discover()
  if LADDER then return LADDER, TIER_BOUNDARIES end
  -- The ladder IS the engine's own order, in an array we can index by tier. The
  -- collection itself cannot serve as the ladder: it is name-keyed userdata, so `#`
  -- works (3) but `out[1]` is nil and `LADDER[tier]` would be nothing.
  --
  -- NOT sorted here, because the engine already orders same-type prototypes by
  -- their `order` string, and the mods that add a demolisher choose it correctly --
  -- behemoth-enemies registers one at "s-k", deliberately past vanilla big's "s-j",
  -- because it IS bigger. So the order is a CONTRACT between the prototypes and the
  -- ladder, and it is verified rather than imposed.
  LADDER = {}
  for _, prototype in pairs(prototypes.get_entity_filtered{
      { filter = "type", type = "segmented-unit" } }) do
    LADDER[#LADDER + 1] = prototype
  end
  -- The contract, checked once and here, where a violation is a fact about the
  -- PROTOTYPES and not about any volcano: it aborts the load naming the two that
  -- are out of order. Sorting instead would hide the same fact -- a prototype whose
  -- `order` says one thing and whose body says another -- behind a ladder that
  -- silently disagrees with the engine about where its own prototypes sit.
  for tier = 2, #LADDER do
    local shorter, longer = LADDER[tier - 1], LADDER[tier]
    if body_length(longer) <= body_length(shorter) then
      error(string.format(
        "EverythingOnNauvis: the engine orders '%s' (%d-tile body) before '%s' "
        .. "(%d-tile body), but this ladder's rank IS body length. A prototype's "
        .. "`order` string decides its position among same-type prototypes, so "
        .. "whichever of the two is wrong is the one to fix.",
        shorter.name, body_length(shorter), longer.name, body_length(longer)))
    end
  end
  -- Boundaries BETWEEN tiers, evenly spaced between the two measured numbers -- so
  -- a longer ladder interpolates rather than inventing thresholds. At three tiers they
  -- are exactly 0.55 and 0.8, which is what the hardcoded ladder produced, and a
  -- fourth tier takes 0.675, so a modded colossal only gets the biggest claims. A
  -- two-tier ladder has one boundary, and the zero span gives it the low one.
  local count = #LADDER
  local span = count > 2 and (TIER_HIGH - TIER_LOW) / (count - 2) or 0
  TIER_BOUNDARIES = {}
  for tier = 1, count - 1 do
    TIER_BOUNDARIES[tier] = TIER_LOW + span * (tier - 1)
  end
  return LADDER, TIER_BOUNDARIES
end

function M.demolisher_class(volcanoes, cone)
  local size = volcanoes:size_fraction(cone)
  for tier = #LADDER, 2, -1 do
    if size >= TIER_BOUNDARIES[tier - 1] then return tier end
  end
  return 1
end

--- The patrol path for this volcano, from the cone's own geometry AND its
--- claimed chunks.
---
--- Left to itself the game interpolates a path from the territory's CHUNKS --
--- "a loop around the chunk squares", a chunk-quantised guess at a shape we
--- already know exactly. create_territory takes a path, so the mirror's answer is
--- used instead: a ring inside the claimed disc, walked as a closed loop so the
--- unit crosses its own ground instead of orbiting the boundary.
---
--- The ring is CLIPPED TO THE CONE'S OWN CHUNKS, which matters wherever two
--- volcanoes overlap. Ownership there is the mirror's MAX-of-cones rule, so a
--- losing cone's disc is cut by a boundary that can pass very close to its
--- centre: a ring drawn from the disc alone would patrol across the border into
--- chunks the neighbour owns, i.e. outside this territory. Radii are tried
--- largest first and the first one that yields a real loop wins, so a heavily
--- split cone automatically patrols a smaller circle of its own ground. Points on
--- water or void are dropped too (a patrol point in the ocean is a demolisher
--- drowning); if too little of a loop survives anywhere, the engine's own path is
--- used instead (nil).
-- Radii as a fraction of the cone's CORE radius, widest first: the first radius
-- that yields a full loop wins, so a heavily split volcano automatically patrols a
-- smaller circle of its own ground. The rings sit at 0.78 / 0.58 / 0.38 -- wide
-- enough to cross the volcano rather than circle its middle, and the clip to the
-- cone's own chunks is what keeps the path on the volcano.
-- Radii as a fraction of the core radius, widest first, and a POINT BUDGET that
-- shrinks with them: a 32-point ring needs a circumference to put 32 points on, and
-- a 19-chunk cone does not have one, and asking for it anyway returns nil -- the
-- unit then falls back to a straight body. So the loop is sized to the ground:
-- about one point every 6 tiles, from 8 to 32.
--- How many directions the patrol path is sampled in -- the mirror's own count, not
-- a second copy of it -- but from the patrol path, which owns the number, not from
-- mirror, which mirrors Factorio and has no opinion about patrols.
local PATROL_MAX_POINTS = PatrolPath.PATROL_DIRECTIONS

-- `members` is passed in for the same reason as PatrolPath.patrol_circle's: the
-- share scan is the mirror's most expensive call and every caller already has it.
--- `share` is the cone's own chunks and `contenders` the cones it overlaps. Both are
--- inputs: the rivals that dent the route are read from the contender list rather
--- than searched for again.
function M.patrol_path(volcanoes, cone, share, contenders)
  -- A circle that WARPS with the volcano: a round claim gets a circle, one squashed
  -- against a neighbour gets that circle dented on the crowded side, following the
  -- claim's own outline rather than a circle shrunk to whatever fitted (which on a
  -- merged volcano was a small circle in the middle of it). PatrolPath.patrol_circle
  -- builds the shape; this samples it and starts the guard facing the right way.
  --
  -- No membership check here, and that is not an omission: patrol_circle returns nil
  -- unless every one of its 32 sampled nodes lands in a claimed chunk, and the
  -- closure it hands back snaps to the nearest direction, so the nodes read here ARE
  -- the nodes it checked.
  local _, _, point_at = PatrolPath.patrol_circle(volcanoes, cone, share, contenders)
  if not point_at then return nil end
  local patrol_path = {}
  for index = 0, PATROL_MAX_POINTS - 1 do
    local x, y = point_at(2 * math.pi * index / PATROL_MAX_POINTS)
    patrol_path[#patrol_path + 1] = { x = x, y = y }
  end
  -- The patrol path is returned as sampled; where the unit STARTS is spawn_pose's job,
  -- because the spawn form it uses (position + direction) is the one that honours
  -- `direction` -- with body_nodes the engine ignored it and always faced north,
  -- which is what produced a U-turn on spawn.
  -- The NORTHWARD leg has to be the one the head sets off along, and the head no
  -- longer starts at path[1]: body_nodes is reversed before create_segmented_unit
  -- (get_body_nodes is front-to-back, so the head walks toward DECREASING index), so
  -- the head begins at the far end of the laid body and its first move is the
  -- patrol path's LAST leg. Rotating so the FIRST leg points north therefore aimed the
  -- spawn the wrong way -- and by how much depended on where arc = body-length
  -- falls, which is why the playtest saw it on the small demolishers (51 tiles) and
  -- not the big ones (102). So the most-northward leg is rotated into the LAST
  -- position, and the wrap-around leg (last -> first) is the one it takes.
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

--- The body length of a demolisher prototype, in tiles behind the head.
---
--- Read at runtime: `prototypes.entity[name].segment_engine.segments`, each entry
--- carrying a cumulative `distance_from_head`. A big demolisher: 41 entries, the
--- last at 101.9183 tiles -- that is the body. Used to size the body we are about to
--- spawn, and to check it fits the patrol path.
--- Also read: `max_body_nodes`, the node budget the engine gives a unit of this
--- prototype. Measured on the running game: 106 / 81 / 55 for big / medium / small
--- (bodies 101.92 / 76.43 / 50.88 tiles), so it is the body plus a few tiles of
--- tail slack. The API docs say 63 for all of them, which is stale and wrong for
--- every one of these -- so we ask the prototype, not the docs.
--- Everything the body needs: its length, how many segments make it, the engine's own
--- node budget, and the turn radius it can hold. Straight through, no nil-guards --
--- these are the fields the sort above already read, from the same objects.
local function body_shape(prototype)
  local engine = prototype.segment_engine
  local segments = engine.segments
  return segments[#segments].distance_from_head, #segments,
    engine.max_body_nodes, prototype.patrolling_turn_radius
end

--- The body nodes: the patrol path walked at one-tile spacing for as long as the body is.
---
--- NODE COUNT is what seats segments, not coverage. Measured live on a volcano,
--- beside a unit that is itself half-bodied (22 of 42 segments alive):
---   63 nodes at 1.00 tiles -> 22 of 42 segments placed (covers  63 tiles)
---   63 nodes at 1.62 tiles -> 22 of 42 segments placed (covers 102 tiles)
---  106 nodes at 1.00 tiles -> 42 of 42 segments placed (covers 106 tiles)
--- So the engine wants about one node per TILE of body -- a big demolisher's is 101.9
--- tiles -- and describing that body with 63 nodes leaves the tail with nothing to
--- sit on, which is the body the playtest reported as cropped.
---
--- What the prototype DOCUMENTS for body_nodes (SegmentEngineSpecification::
--- max_body_nodes) is 63, which is stale: the same field read at runtime says 106
--- for a big demolisher, 81 for a medium and 55 for a small -- the body plus a few
--- tiles of tail slack. So the count is the prototype's own `max_body_nodes`, which
--- is also the cap, and the nodes go on at one tile apart because that is what the
--- API asks for ("adjacent nodes should be approximately 1.0 tile apart") and what
--- seats the body: 106 nodes at 1.00 tile seats 42 of 42 segments, measured live.
--- How much longer a patrol path must be than the body it carries, so the tail does not
--- wrap onto the head's end of the loop.
local PATROL_PATH_MARGIN = 1.15

function M.body_nodes(cone, patrol_path, class)
  if not patrol_path or #patrol_path < 4 then return nil end
  local prototype = LADDER[class]
  local length, segments, budget, turn_radius = body_shape(prototype)
  -- Seed the engine's own node budget, one node per tile: the whole body, plus the
  -- tail slack the prototype allows. The budget IS the cap, so asking for exactly
  -- that cannot truncate the array -- and a truncated array is the cropped body.
  -- The fallback is a missing OPTIONAL field (a mod's prototype need not declare
  -- max_body_nodes), not a missing segment: those are guaranteed by the engine.
  local wanted = budget or (math.floor(length) + 1)
  -- One node per tile of body. A short patrol path cannot carry a long body (the tail
  -- would wrap onto itself), so say no rather than hand over a knot.
  local loop = M.patrol_path_length(patrol_path)
  if loop < length or loop < wanted then
    log(string.format("[eon] volcano %s: its %d-tile patrol path cannot carry a %d-tile body "
      .. "of %d segments -- no unit placed", cone.id, math.floor(loop), math.floor(length),
      segments))
    return nil
  end

  -- A FOLLOWER, not a placement on the path and not a clamp of one.
  --
  -- Two things were tried and both were wrong. Placing nodes ON the path's vertices
  -- went straight across every corner. Clamping a node that would turn too hard was
  -- worse than useless: it displaced the kink by ONE NODE -- small turn at the
  -- clamped node, large turn at the next one back on the path -- and measured 12.2x
  -- the allowed radius, a 70 degree joint where 5.7 was the limit.
  --
  -- What a constant turn radius actually is: the body keeps going the way it is
  -- already going, one tile per node, turning by at most 1/R. A point AHEAD on the
  -- path is a hint about which way to go, never a place to be -- so the body lags
  -- round a corner and converges back onto the patrol path as it straightens, with no
  -- alternation to produce a kink somewhere else.
  local arcs, total = { 0.0 }, 0.0
  for index = 1, #patrol_path do
    local a, b = patrol_path[index], patrol_path[index % #patrol_path + 1]
    local ex, ey = b.x - a.x, b.y - a.y
    total = total + math.sqrt(ex * ex + ey * ey)
    arcs[index + 1] = total
  end
  if total <= 0 then return nil end
  -- The point `distance` tiles further along the (closed) path.
  local function path_ahead(distance)
    local target = (distance % total)
    local low, high = 1, #patrol_path
    while low < high do
      local mid = math.floor((low + high + 1) / 2)
      if arcs[mid] <= target then low = mid else high = mid - 1 end
    end
    local a, b = patrol_path[low], patrol_path[low % #patrol_path + 1]
    local span = arcs[low + 1] - arcs[low]
    local t = span > 0 and (target - arcs[low]) / span or 0
    return a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t
  end

  -- Two tiles of look-ahead: one converges too tightly to smooth anything, and
  -- much more cuts the corner the patrol path was traced to follow.
  local LOOK_AHEAD = 2
  local limit = 1 / turn_radius
  local nodes, lagged = {}, 0
  local x, y = patrol_path[1].x, patrol_path[1].y
  -- Seed the heading along the first edge: the first node has no predecessor, and
  -- the body should start pointing the way the patrol path starts going.
  local seed_x, seed_y = patrol_path[2].x - x, patrol_path[2].y - y
  local seed_len = math.sqrt(seed_x * seed_x + seed_y * seed_y)
  if seed_len <= 0 then return nil end
  local heading_x, heading_y = seed_x / seed_len, seed_y / seed_len
  nodes[1] = { x = x, y = y }
  while #nodes < wanted do
    local hint_x, hint_y = path_ahead(#nodes + LOOK_AHEAD)
    local vx, vy = hint_x - x, hint_y - y
    local reach = math.sqrt(vx * vx + vy * vy)
    local ux, uy = vx / reach, vy / reach
    local dot = ux * heading_x + uy * heading_y
    dot = math.max(-1, math.min(1, dot))
    local turn = math.acos(dot)
    if turn > limit then
      -- Rotate TOWARD the heading by `turn - limit`, not by `limit`. Turning by
      -- `limit` leaves the new direction at `turn - limit` from the heading, which
      -- is still over the limit whenever turn exceeds twice it -- so the bound was
      -- not a bound. Rotating by the difference puts the new direction exactly ON
      -- the limit, which is the biggest turn the radius allows and the one that
      -- tracks the patrol path most closely.
      local rotate = turn - limit
      -- Rotate the wanted direction back toward the current heading by EXACTLY the
      -- limit. cross(u, h) is the signed angle from `u` to the heading: positive
      -- means the heading is ANTICLOCKWISE of u, so rotating u anticlockwise by
      -- `limit` moves it TOWARD the heading. The sign was the other way round, which
      -- rotated away from the heading and made the turn worse instead of bounded --
      -- 4.4x the limit with the sign fixed, 12.2x with it wrong.
      local sign = (ux * heading_y - uy * heading_x) >= 0 and 1 or -1
      local c, sn = math.cos(rotate), math.sin(rotate) * sign
      ux, uy = ux * c - uy * sn, ux * sn + uy * c
      lagged = lagged + 1
    end
    heading_x, heading_y = ux, uy
    -- One tile per node, always. A segmented unit has RIGID segment lengths, so a
    -- node that lands further away is a stretched segment and a visible gap.
    x, y = x + ux, y + uy
    nodes[#nodes + 1] = { x = x, y = y }
  end
  if #nodes < 4 then return nil end
  if lagged > 0 then
    -- Not a defect: the turn limit doing its job, and the difference between the two
    -- polylines. Logged because a number that suddenly grows is worth seeing.
    log(string.format("[eon] volcano %s: the body lags the patrol path on %d of %d "
      .. "nodes (turn radius %.1f tiles)", cone.id, lagged, #nodes, turn_radius))
  end
  return nodes
end

--- Which demolisher goes on this volcano: the biggest one whose BODY fits its patrol path.
---
--- The size the cone's own scale suggests is the starting point, and we step DOWN
--- until the body fits, because the body is what has to lie on the ground: a big
--- demolisher is 101.9 tiles long (41 segments), and a 53-chunk claim at 6x
--- volcanism has a patrol path shorter than that, so the rule produced a territory with a
--- demolisher that could not stand on it -- a territory with no units does not
--- appear on the player's map at all, which is a claim that does not exist.
--- This is a search over the three sizes against a stated condition, not a
--- degraded unit: the animal is always whole, and it is always the biggest one the
--- volcano can carry.

function M.patrol_path_length(patrol_path)
  local total = 0
  for index = 1, #patrol_path do
    local from, to = patrol_path[index], patrol_path[(index % #patrol_path) + 1]
    total = total + math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2)
  end
  return total
end

function M.demolisher_for(volcanoes, cone, patrol_path)
  local available = M.patrol_path_length(patrol_path)
  local preferred = M.demolisher_class(volcanoes, cone)
  for class = preferred, 1, -1 do
    local prototype = LADDER[class]
    local name = prototype.name
    local length = body_length(prototype)
    -- A margin over 1: the body has to fit with room to spare, or its tail wraps
    -- onto the head's own end of the loop.
    if available >= length * PATROL_PATH_MARGIN then
      if class ~= preferred then
        log(string.format("[eon] volcano %s: a %s is %.0f tiles long and this volcano's "
          .. "patrol path is %.0f, so it gets a %s instead", cone.id, name, length, available,
          LADDER[class]))
      end
      return class, name, length
    end
  end
  return nil
end

--- Put the volcano's demolishers on it.
---
--- create_territory does NOT do this: the map generator spawns a territory's
--- segmented units itself, and LuaTerritory's docs are blunt -- "a territory with
--- no units will not appear on player's maps". So a territory built from Lua is
--- an empty claim: right disc, patrol path and all, and nothing walking on it.
--- (regenerate_segmented_units() would add ONE unit, sized by the engine's
--- variation expression, i.e. no choice and no second demolisher; create_
--- segmented_unit takes the size, so the size mix is ours.)
--- Put the volcano's guard on it. The patrol path and the size were decided by
--
-- decided on the ground, so this is one path: a whole animal, along its own patrol path,
-- or a DEFECT.
--- There is no smaller fallback, no head-only version and no retry -- a half
--- demolisher reads as a bug, and nothing about it gets better on its own.
function M.spawn_demolishers(surface, volcanoes, territory, cone, patrol_path, class)
  local body = M.body_nodes(cone, patrol_path, class)
  if not body then
    -- TWO values on every path, always: the caller logs the name straight into a
    -- format, and a bare `return 0` left it nil there -- which crashed
    -- on_chunk_generated (string.format, bad argument #8) and took the map with it.
    -- The third is a message for the CALLER to record: this function has no defect
    -- list of its own, and neither should it. It reports a fact and the Builder,
    -- which owns `defects`, decides what that fact means.
    return 0, "no body on the patrol path", string.format(
      "%s: a class was chosen but no body lays along the patrol path", cone.id)
  end
  -- The node list is FRONT TO BACK (get_body_nodes: "from front to back"), so the
  -- head is placed at index 1 with the body trailing behind it, and it walks AWAY
  -- from its own body -- toward DECREASING index. Measured on the running game:
  -- spawned with nodes marching east along x = 0..20, the head came back at
  -- node1.x = -2 with nodeN.x = 20, i.e. at the west end facing away from the rope.
  --
  -- body_nodes() lays them along path[1] -> path[n], so handing that list over
  -- unchanged makes the guard walk the patrol path BACKWARDS -- clockwise authored,
  -- counter-clockwise walked, with a U-turn on its first step. Reversing it puts the
  -- head at the far end of the body with the tail back at path[1], so walking away
  -- from the body means walking FORWARD along the patrol path.
  for index = 1, #body / 2 do
    body[index], body[#body + 1 - index] = body[#body + 1 - index], body[index]
  end
  -- The name comes from the class, not from the caller: it is not passed in
  -- AND looked up again inside, which is two sources for one fact.
  local name = LADDER[class].name
  local ok, unit = pcall(function()
    return surface.create_segmented_unit{
      name = name, body_nodes = body, force = "enemy", territory = territory,
    }
  end)
  if ok and unit and unit.valid then
    return 1, string.format("%s(%d nodes, whole body)", name, #body), nil
  end
  return 0, string.format("%s NOT placed (%d body nodes)", name, #body),
    string.format("%s: could not place a %s with %d body nodes", cone.id, name, #body)
end

--- Create the territory of one cone, in ONE call with its whole chunk list, and
--- put its demolisher on it.
---
--- The chunk list is the cone's disc, complete and final from the first moment:
--- existence is the engine's density expression and membership is the disc, both
--- pure functions of the map, so the same list comes out on every load in either
--- generation order. There is nothing to gather and nothing to add later.
---
--- The ONE thing that is waited for is the engine's own precondition:
--- create_territory refuses a list with no generated chunk in it ("Must contain at
--- least one generated chunk"). A cone nobody has walked to is therefore marked
--- "unseen" and asked again when one of its chunks arrives -- that is a
--- precondition being unmet, not a claim in doubt, and the marker is a fact about
--- the engine rather than a maybe about the map. Everything else about the cone
--- is already known when we are asked.
---
--- The demolisher goes on in the SAME pass, and again from the audit if the ground
--- was not standable yet.

return M
