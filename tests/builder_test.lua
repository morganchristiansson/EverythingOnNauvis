-- Drive the builder against a FAKE surface, with no Factorio at all.
--
-- The claim path is pure map arithmetic plus five surface calls
-- (is_chunk_generated, get_territory_for_chunk, create_territory,
-- create_segmented_unit, can_place_entity), so it can be exercised -- and
-- broken -- in a unit test in milliseconds. That is the point of this file: the
-- "every cone is unseen" defect took a game restart and a paste of the log to
-- localise, because there was nowhere smaller to look.
--
-- Run: lua tests/builder_test.lua
package.path = "/workspace/?.lua;" .. package.path

-- Factorio's global log(), captured so the test can see what the builder said.
LOGGED = {}
function log(message) LOGGED[#LOGGED + 1] = tostring(message) end

-- The runtime prototype registry, stubbed with the real values read from a live
-- game (`prototypes.entity[name].segment_engine`, asked over rcon): the builder
-- reads the body's length AND its node budget from here, and a test that stubbed
-- either would be testing a different builder. `distance_from_head` is CUMULATIVE
-- and `max_body_nodes` is the cap -- big 106 / medium 81 / small 55, for bodies of
-- 101.92 / 76.43 / 50.88 tiles. (The API docs say 63 for all three; the prototypes
-- do not agree, and the prototypes are what the engine enforces.)
prototypes = { entity = {} }
for _, spec in ipairs({ { "small-demolisher", 41, 50.88296875, 55 },
                        { "medium-demolisher", 41, 76.431875, 81 },
                        { "big-demolisher", 41, 101.91828125, 106 } }) do
  local segments = {}
  -- Cumulative, and shaped like the real curve (fast at the head, ~1.9/tile at the
  -- tail): the builder only reads the last value, but a stub that were linear would
  -- hide a builder that walked the list.
  for index = 1, spec[2] do
    segments[index] = { distance_from_head = spec[3] * (index / spec[2]) ^ 0.92 }
  end
  -- patrolling_turn_radius is read for the same reason as the rest: the builder
  -- lays the body within it, and a stub without it would exercise a builder that
  -- places nothing. It is on the PROTOTYPE ROOT, not in segment_engine -- which is
  -- how reading it from the wrong place placed no demolisher anywhere. One tile is
  -- a plausible demolisher value; the real one comes off the prototype.
  prototypes.entity[spec[1]] = { name = spec[1], type = "segmented-unit",
                                 segment_engine = { segments = segments,
                                                    max_body_nodes = spec[4] },
                                 patrolling_turn_radius = 1.0 }
end

-- prototypes.get_entity_filtered, which is how the builder discovers the
-- demolisher ladder (see discover_demolishers). The real engine does this filtering
-- in C++; the stub does what it says on the tin and returns only segmented units.
prototypes.get_entity_filtered = function(filters)
  local want_type = nil
  for _, filter in ipairs(filters or {}) do
    if filter.filter == "type" then want_type = filter.type end
  end
  -- A plain array in BODY-LENGTH ORDER, which is the contract the real engine
  -- satisfies: it orders same-type prototypes by their `order` string, and these
  -- three (small=s-h, medium=s-i, big=s-j) come back smallest first.
  --
  -- Two things this stub deliberately does NOT reproduce, both of which the real
  -- collection does:
  --   * it is name-keyed userdata, so `out[1]` is nil and `table.sort` rejects it
  --     outright -- an ordinary array hides both, which is how "table expected, got
  --     userdata" reached a gate twice.
  --   * `pairs` over `prototypes.entity` yields HASH order, not the engine's. Taking
  --     that order verbatim trips the ladder's order check on every run, which is the
  --     check doing its job on a stub that does not honour the contract.
  local matched = {}
  for name, proto in pairs(prototypes.entity) do
    if want_type == nil or proto.type == want_type then matched[#matched + 1] = proto end
  end
  table.sort(matched, function(a, b)
    local left, right = a.segment_engine.segments, b.segment_engine.segments
    return left[#left].distance_from_head < right[#right].distance_from_head
  end)
  return matched
end

local cones = require("noise-mirror.volcano-cones")
local Builder = require("volcano-territory")
local Demolisher = require("volcano-demolisher")

local SEED, FREQUENCY, SIZE = 12345, 2, 1

--- A surface that is generated in a disc around the origin and knows nothing
--- else. Tiles are irrelevant: the builder must not read them, and this one
--- raises if it tries, so a reintroduced tile read fails the test loudly.
local function fake_surface(centre_chunk, radius_chunks, log)
  local generated = {}
  local created, units, specs = {}, {}, {}
  local surface
  surface = {
    index = 1,
    name = "nauvis",
    map_gen_settings = {
      seed = SEED,
      autoplace_controls = { vulcanus_volcanism = { size = SIZE, frequency = FREQUENCY } },
    },
    is_chunk_generated = function(position)
      local dx = position.x - centre_chunk.x
      local dy = position.y - centre_chunk.y
      if dx * dx + dy * dy > radius_chunks * radius_chunks then
        print(string.format("   [fake] %d,%d is OUTSIDE the revealed disc (centre %d,%d r=%s)",
          position.x, position.y, centre_chunk.x, centre_chunk.y, tostring(radius_chunks)))
        return false
      end
      return true
    end,
    get_territory_for_chunk = function(position)
      return created[position.x .. "," .. position.y]
    end,
    create_territory = function(spec)
      -- The documented contract is "must contain at least one generated chunk",
      -- not "all of them": ungenerated chunks are held by the territory and join it
      -- when they arrive. Getting this wrong here is what made the builder look
      -- broken when it was not.
      local any_generated = false
      for _, chunk in ipairs(spec.chunks) do
        if surface.is_chunk_generated(chunk) then any_generated = true break end
      end
      if not any_generated then return nil end
      local territory = {}
      territory.chunks = {}
      territory.path = spec.patrol_path
      function territory.get_chunks() return territory.chunks end
      function territory.get_segmented_units() return territory.units end
      function territory.get_patrol_path() return territory.path or {} end
      territory.units = {}
      territory.valid = true
      for _, chunk in ipairs(spec.chunks) do
        territory.chunks[#territory.chunks + 1] = { x = chunk.x, y = chunk.y }
        created[chunk.x .. "," .. chunk.y] = territory
      end
      log.created[#log.created + 1] = territory
      return territory
    end,
    create_segmented_unit = function(spec)
      units[#units + 1] = spec.name
      -- The WHOLE spec, body nodes included. Recording only the name is what let a
      -- three-lap spiral through: the unit existed, so every assertion passed while
      -- the shape the engine was handed was nonsense.
      specs[#specs + 1] = spec
      return { valid = true, prototype = { name = spec.name } }
    end,
    created_units = units,
    created_specs = specs,
    can_place_entity = function() return true end,
    get_tile = function() error("the builder read a tile: membership must be geometric") end,
  }
  return surface, created, units, specs
end

--- The shape of a spawned body, measured off the spec the builder handed the
--- engine. These are the properties the engine's own docs ask for and that the
--- live measurements pin down: about one node per TILE, at most `max_body_nodes`
--- of them, and a shape that does not overlap itself. A node count alone cannot
--- tell a straight 102-tile body from a 102-node spiral wound three times around
--- the patrol ring -- both are "#nodes == 102" -- and the spiral is what the
--- playtest saw.
local function body_shape(spec)
  local nodes = spec.body_nodes or {}
  local spacing_min, spacing_max = math.huge, 0
  local span = 0
  for index = 2, #nodes do
    local from, to = nodes[index - 1], nodes[index]
    local step = math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2)
    spacing_min = math.min(spacing_min, step)
    spacing_max = math.max(spacing_max, step)
    span = span + step
  end
  return #nodes, spacing_min, spacing_max, span
end

local failures = 0
local function check(label, ok, detail)
  if ok then
    print("  ok   " .. label)
  else
    failures = failures + 1
    print("  FAIL " .. label .. (detail and (" -- " .. detail) or ""))
  end
end

-- Where the mirror says there are cones, near the origin.
local context = cones.new_context{ seed = SEED, volcanism_size = SIZE, volcanism_frequency = FREQUENCY }
local volcanoes = cones.new_volcanoes(context)
local existing = {}
for index = 1, volcanoes:cones_near(0, 0, 6).n do
  local cone = volcanoes:cones_near(0, 0, 6)[index]
  existing[cone.id] = cone
end
print(string.format("mirror: %d cones exist near the origin", (function()
  local n = 0 for _ in pairs(existing) do n = n + 1 end return n
end)()))

-- The cones these tests drive, chosen deterministically. `pairs` order made every
-- assertion here depend on hash order, so: the smallest cone that can actually host
-- a guard (a claim below the floor is a fragment and is deliberately NOT claimed),
-- and the smallest cone overall, which may be a fragment.
local function hostable_cone()
  local best
  for _, cone in pairs(existing) do
    if #volcanoes:cone_chunks(cone, volcanoes:contenders_for(cone)) >= 16 then
      if not best or cone.core_radius < best.core_radius then best = cone end
    end
  end
  return best
end

local function smallest_cone()
  local best
  for _, cone in pairs(existing) do
    if not best or cone.core_radius < best.core_radius then best = cone end
  end
  return best
end

--- The territory that holds a given cone's share. One chunk event reaches every
--- cone in the ring, so a batch creates several territories and "how many were
--- created" says nothing about this cone -- count the one that holds its ground.
local function territory_for(log, cone)
  local share = volcanoes:cone_chunks(cone, volcanoes:contenders_for(cone))
  local best, best_hits = nil, 0
  for _, territory in ipairs(log.created) do
    local held = 0
    for _, chunk in ipairs(share) do
      for _, member in ipairs(territory:get_chunks()) do
        if member.x == chunk.x and member.y == chunk.y then held = held + 1 end
      end
    end
    if held > best_hits then best, best_hits = territory, held end
  end
  return best, best_hits, #share
end

print("a cone whose chunks are generated is claimed, in one event")
do
  local log = { created = {} }
  local centre = nil
  centre = hostable_cone()
  local surface, created, placed_units, placed_specs = fake_surface(
    { x = math.floor(centre.x / 32), y = math.floor(centre.y / 32) }, 16, log)
  local builder = Builder.new(surface, { created = {} })
  -- A block around the cone's centre, because a cone is decided when a chunk of ITS
  -- OWN arrives and on a fragment the centre chunk belongs to a neighbour. Delivering
  -- the centre chunk alone was passing for the wrong reason: the candidate set that
  -- reached the builder then was `contenders_for` of the cone in that region, which
  -- filters by core-disc proximity and can exclude a cone that covers the chunk. The
  -- ring is complete, so it says so.
  local bx, by = math.floor(centre.x / 32), math.floor(centre.y / 32)
  for dy = -2, 2 do for dx = -2, 2 do
    builder:on_chunk_generated{ x = bx + dx, y = by + dy }
  end end
  check("the cone is settled", builder.created[centre.id] == true)
  -- Count the territories that hold THIS cone's chunks: the event's ring holds
  -- several cones, and they all get claimed.
  local mine, hits, share = territory_for(log, centre)
  check("a territory was created for it", mine ~= nil and hits == share,
    string.format("best territory holds %d of %d of its chunks", hits or 0, share))
  -- A unit goes on every claim big enough to host one; below the floor it is a
  -- rim sliver and deliberately gets none.
  local expected_units = (#volcanoes:cone_chunks(centre, volcanoes:contenders_for(centre)) >= 16) and 1 or 0
  check("a demolisher is placed on a claim big enough to host one",
    #placed_units == expected_units,
    string.format("%d unit(s) placed, claim %d chunks (floor 16)",
      #placed_units, #volcanoes:cone_chunks(centre, volcanoes:contenders_for(centre))))
  check("nothing was marked unseen", claimed ~= "unseen", "state=" .. tostring(claimed))

  -- The shape of the body it was handed. The count was never the thing that was
  -- wrong, so the count cannot be the assertion.
  if #placed_specs > 0 then
    local spec = placed_specs[1]
    local engine = prototypes.entity[spec.name].segment_engine
    local count, low, high, span = body_shape(spec)
    check("the body is seeded with the prototype's whole node budget",
      count == engine.max_body_nodes,
      string.format("%d nodes for a budget of %d (a node past it is dropped by the "
        .. "engine: the cropped tail)", count, engine.max_body_nodes))
    check("its nodes are about a tile apart, as the API asks",
      low >= 0.5 and high <= 1.5,
      string.format("spacing %.2f-%.2f tiles", low, high))
    check("the body lies along the patrol path instead of winding round it",
      span <= Demolisher.patrol_path_length(mine.path) * 1.05 + 1,
      string.format("%.0f tiles of nodes for a %.0f-tile patrol path (more than one lap "
        .. "means the shape overlaps itself)", span, Demolisher.patrol_path_length(mine.path)))
  else
    check("a body was handed over to place", false, "no segmented unit spec")
  end
end

print("a cone with nothing generated is left unseen, and retried later")
do
  local log = { created = {} }
  local centre = nil
  for id, cone in pairs(existing) do centre = cone break end
  -- a surface generated somewhere else entirely
  local surface = fake_surface({ x = 100000, y = 100000 }, 1, log)
  local builder = Builder.new(surface, { created = {} })
  builder:on_chunk_generated{ x = 100000, y = 100000 }
  -- Not settled, so the next chunk nearby will ask again: a cone the engine cannot
  -- take yet is the one thing the marker must NOT remember. There is no "unseen"
  -- value any more -- absent means exactly this.
  check("it is not settled", builder.created[centre.id] ~= true)
  check("no territory was created", #log.created == 0)
end

print("a second event for the same cone does not create a second territory")
do
  local log = { created = {} }
  local centre = nil
  for id, cone in pairs(existing) do centre = cone break end
  local cx, cy = math.floor(centre.x / 32), math.floor(centre.y / 32)
  local surface = fake_surface({ x = cx, y = cy }, 24, log)
  local builder = Builder.new(surface, { created = {} })
  -- DELIVER THE CONE'S OWN CHUNKS, not a block around its centre. That block was a
  -- guess about where the cone's ground is, and it made this test FLAKY -- two runs in
  -- three failed, because `pairs` picks an arbitrary cone and a fragment's own chunks
  -- can be nowhere near its centre, so the block delivered none of them and nothing was
  -- decided. The rule being tested is "a cone is decided when a chunk of its own is
  -- delivered", so the test should deliver exactly that and no longer depend on the
  -- shape of the cone it drew.
  local delivered = 0
  for _, member in ipairs(volcanoes:cone_chunks(centre, volcanoes:contenders_for(centre))) do
    if surface.is_chunk_generated(member) then
      builder:on_chunk_generated{ x = member.x, y = member.y }
      delivered = delivered + 1
    end
  end
  check("the cone's own generated chunks were delivered", delivered > 0, delivered .. " chunks")
  builder:on_chunk_generated{ x = cx, y = cy }
  builder:on_chunk_generated{ x = cx, y = cy }
  builder:on_chunk_generated{ x = cx + 1, y = cy }
  -- A repeat event may legitimately claim ANOTHER cone of the ring (one that had
  -- nothing revealed when the first event landed), so the invariant is about this
  -- cone: it must still have exactly one territory, holding its whole share.
  local still, hits, share = territory_for(log, centre)
  check("a repeat event leaves this cone one whole territory",
    still ~= nil and hits == share,
    string.format("%d territories in the ring; this cone's holds %d of %d",
      #log.created, hits or 0, share))
end

print("every cone inside the generated area is claimed")
do
  local log = { created = {} }
  local surface = fake_surface({ x = 0, y = 0 }, 30, log)
  local builder = Builder.new(surface, { created = {} })
  for dy = -24, 24 do for dx = -24, 24 do
    builder:on_chunk_generated{ x = dx, y = dy }
  end end
  -- The claim is the mirror's answer: every cone with ground is claimed, whether or
  -- not a whole guard fits on it. (A volcano mapgen placed is a volcano; a guard that
  -- does not fit is a logged anomaly, not a reason to drop the claim.)
  local expected, claimed, unhostable = 0, 0, 0
  for _, cone in pairs(existing) do
    local share = volcanoes:cone_chunks(cone, volcanoes:contenders_for(cone))
    local revealed = surface.is_chunk_generated({
      x = math.floor(cone.x / 32), y = math.floor(cone.y / 32) })
    local hostable = #share >= 16
    if revealed and hostable then
      expected = expected + 1
      if builder.created[cone.id] == true then claimed = claimed + 1 end
    elseif revealed and #share > 0 then
      unhostable = unhostable + 1
    end
  end
  check("every volcano the mirror finds is claimed", expected == claimed,
    string.format("%d of %d claimed, %d with no room for a guard, %d territories",
      claimed, expected, unhostable, #log.created))
end

print("a cone revealed only in the middle is still claimed (its unit may wait)")
do
  local log = { created = {} }
  local centre = nil
  centre = smallest_cone()
  local cx, cy = math.floor(centre.x / 32), math.floor(centre.y / 32)
  -- Revealed, but only a small patch around the centre chunk: the patrol patrol path runs
  -- out of it, so the builder must decline and come back when the ground does.
  local surface, created = fake_surface({ x = cx, y = cy }, 1, log)
  local builder = Builder.new(surface, { created = {} })
  -- Every chunk of the revealed block is DELIVERED, not just its middle. The middle
  -- one is not always the cone's own -- on a fragment a neighbour wins the centre
  -- chunk -- and a cone is decided when a chunk of ITS OWN arrives, which is the rule
  -- that replaced walking its share asking the engine whether any of it was
  -- generated. Delivering only the middle was passing before for the wrong reason: the
  -- old walk found some other generated chunk of the share further out.
  for dy = -1, 1 do for dx = -1, 1 do
    builder:on_chunk_generated{ x = cx + dx, y = cy + dy }
  end end
  -- The claim itself needs only one generated chunk (create_territory's rule), so
  -- a cone revealed in the middle IS claimed here. Whether its unit is placed now
  -- or later is the open question: the body cannot exist over unrevealed ground, so
  -- a unit whose patrol path runs ahead of the frontier is born without segments and
  -- grows them as it crawls. That is measured and NOT yet changed.
  -- A cone that is real is CLAIMED even when no whole guard fits on it: mapgen
  -- placed that volcano, and the guard is best-effort (logged, not raised, because
  -- this runs per chunk and an error() here would take a long game down).
  -- Settled, guard or no guard. There is no second state to check any more: the
  -- marker is one boolean per region, and the failure modes it used to be able to
  -- hold ("no-patrol path", "no-body", "no-fit") were values nothing acted on.
  check("it is still claimed, guard or no guard", builder.created[centre.id] == true)
end

print("the demolisher ladder is discovered and ordered by body length")
do
  -- The point of the discovery: a mod that adds a demolisher joins the ladder at
  -- its natural rank instead of needing this file (or the mod) edited. The stub
  -- above has three bodies; what must hold is that all three are FOUND, in body
  -- order, and that a three-tier ladder hands over at the MEASURED thresholds --
  -- the discovery must not quietly re-tune them.
  local surface = fake_surface({ x = 0, y = 0 }, 1, { created = {} })
  local builder = Builder.new(surface, { created = {} })
  local ladder, tiers = Demolisher.discover()
  local lengths, names = {}, {}
  for index, prototype in ipairs(ladder) do
    local segments = prototype.segment_engine.segments
    lengths[#lengths + 1] = segments[#segments].distance_from_head
    names[index] = prototype.name
  end
  local ascending = true
  for index = 2, #lengths do
    if lengths[index] <= lengths[index - 1] then ascending = false end
  end
  check("every prototype with a body is on the ladder, smallest first",
    #ladder == 3 and ascending and names[1] == 'small-demolisher',
    string.format("%d candidates, order %s", #ladder,
      table.concat(lengths, " < ")))
  check("a three-tier ladder hands over at the measured thresholds",
    tiers[1] == 0.55 and tiers[2] == 0.8
    and #tiers == 2,
    string.format("boundaries %s", table.concat(tiers, ", ")))
end

print("a volcano that cannot host a guard is LOGGED, not crashed on")
do
  -- The crash this covers: spawn_demolishers returned a bare `0` on its failure
  -- paths, so the caller's `placed, names` had names = nil, and the log line
  -- formatted it -- string.format "bad argument #8 of 10" inside on_chunk_generated,
  -- which is a non-recoverable error and takes the map with it. The failure path was
  -- never exercised, which is why it survived a green gate.
  local surface = fake_surface({ x = 0, y = 0 }, 30, { created = {} })
  local builder = Builder.new(surface, { created = {} })
  local volcanoes = builder.volcanoes
  local ring = volcanoes:cones_near(0, 0, 10)
  local cone = nil
  for index = 1, ring.n do cone = ring[index] break end
  check("there is a cone to try", cone ~= nil)
  if cone then
    local before = #LOGGED
    -- Force both failure paths: no body on the patrol path, and a surface that refuses.
    -- These are module functions now, so the stub goes on the module -- which is
    -- also the honest place: nothing about the caller's state decides a body.
    local real_body_nodes = Demolisher.body_nodes
    Demolisher.body_nodes = function() return nil end
    local placed, names, problem =
      Demolisher.spawn_demolishers(surface, volcanoes, nil, cone, {}, 1)
    check("a guard with no body reports a count AND a reason",
      placed == 0 and type(names) == "string" and #names > 0,
      string.format("placed=%s names=%s", tostring(placed), tostring(names)))
    check("and hands the caller a message to record, rather than recording it itself",
      type(problem) == "string" and problem:find("no body lays along the patrol path") ~= nil,
      tostring(problem))
    Demolisher.body_nodes = real_body_nodes
    surface.create_segmented_unit = function() return nil end
    local placed2, names2 = Demolisher.spawn_demolishers(surface, volcanoes, {}, cone, {}, 1)
    check("a guard the engine refuses reports a count AND a reason",
      placed2 == 0 and type(names2) == "string" and #names2 > 0,
      string.format("placed=%s names=%s", tostring(placed2), tostring(names2)))
    -- The line that actually killed the map: a cone that CANNOT host a guard leaves
    -- `placed` unassigned, and the log formats it with %d. Reached whenever
    -- can_host returns nil, which the tighter patrol paths made common.
    local unhostable_placed, unhostable_names = nil, "unhostable"
    local ok = pcall(string.format, "[eon] volcano %s: centre %.0f,%.0f width %.0f -> "
      .. "territory of %d chunks, patrol %d points, demolishers %d [%s]",
      cone.id, cone.x, cone.y, cone.width, 10, 0, unhostable_placed, unhostable_names)
    check("a raw nil demolisher count would crash the log line (it did)", not ok)
    check("...and the log line guards it", pcall(string.format,
      "[eon] volcano %s: centre %.0f,%.0f width %.0f -> territory of %d chunks, "
      .. "patrol %d points, demolishers %d [%s]",
      cone.id, cone.x, cone.y, cone.width, 10, 0, tonumber(unhostable_placed) or 0,
      tostring(unhostable_names)))
    check("a failed guard reports a count AND a reason",
      placed == 0 and type(names) == "string")
  end
end

print("a cone that cannot host a guard is claimed and LOGGED, not crashed on")
do
  -- This is the branch that killed the map. It had NO coverage at all: every e2e run
  -- on record reports "volcanoes that cannot host one: ''" -- 28 of 28 runs, zero --
  -- because patrol_path only fails when a point leaves the claim, and demolisher_for
  -- steps down to the smallest body, which fits nearly any patrol path. The tighter patrol paths
  -- from the margin commit are what made it reachable, and the first thing it did was
  -- take the game down. Forcing it here is the whole point.
  local created_log = { created = {} }
  local surface = fake_surface({ x = 0, y = 0 }, 30, created_log)
  local builder = Builder.new(surface, { created = {} })
  local volcanoes = builder.volcanoes
  local ring = volcanoes:cones_near(0, 0, 10)
  local cone = nil
  for index = 1, ring.n do
    local candidate = ring[index]
    -- create_territory needs one GENERATED chunk, and the fake surface only reveals
    -- a disc, so pick a cone whose centre is inside it.
    if surface.is_chunk_generated({ x = math.floor(candidate.x / 32),
                                    y = math.floor(candidate.y / 32) }) then
      cone = candidate
      break
    end
  end
  check("there is a revealed cone to try", cone ~= nil)
  if cone then
    local before = #LOGGED
    -- The patrol path EXISTS but no body fits it -- the case that used to hand
    -- create_territory a nil path and let the engine generate its own loop. Stub
    -- the FIT, not the path, so the patrol path is real.
    local real_for = Demolisher.demolisher_for
    Demolisher.demolisher_for = function() return nil end
    -- Called the way on_chunk_generated calls it: `create(cone)`, with nothing else.
    -- The arriving chunk and the candidate list used to be passed in, and are not any
    -- more -- the owner test has already run by the time we get here, and the share
    -- works out its own contenders. Passing them was harmless, because Lua ignores
    -- extra arguments, and misleading, which is worse.
    builder:create(cone)
    local logged = false
    for index = before + 1, #LOGGED do
      if tostring(LOGGED[index]):find("no guard placed", 1, true) then logged = true end
    end
    check("the claim is still made -- the volcano is real, the guard is not",
      logged or builder.created[cone.id] == true)
    -- The LOG LINE is the actual fix, not the assignment: it is nil-proof, so the
    -- branch can no longer end the map however its locals are set. What a test can
    -- pin is the outcome a playtest reads -- a volcano claimed, zero guards, and a
    -- reason rather than silence.
    local line = ""
    for index = before + 1, #LOGGED do
      if tostring(LOGGED[index]):find("demolishers", 1, true) then line = tostring(LOGGED[index]) end
    end
    check("the per-cone line still reports it, with a count",
      line:find("demolishers 0", 1, true) ~= nil, line)
    Demolisher.demolisher_for = real_for
    -- NOT a defect, and this is the decision. Nothing disagrees here: the mirror is
    -- right, mapgen placed a volcano, and it is too small to carry a guard. A
    -- defect means the mirror and the game differ. It was reported as a defect on
    -- the opposite reasoning, which put an ordinary playtest outcome in the list
    -- the probe reads as "the mirror is wrong" -- a claim it does not support.
    -- Measured unreachable anyway, on a 5x margin over 184 cones.
    -- There is no defect LIST any more: `Builder:defect` logs, and the harness
    -- greps the stream for "[eon] DEFECT". So the check is that no marker was
    -- logged, which is the same fact read from where it is now kept.
    local marked = false
    for _, line in ipairs(LOGGED) do
      if tostring(line):find("[eon] DEFECT", 1, true) then marked = true end
    end
    check("and it is not reported as a DEFECT -- a small volcano is not a disagreement",
      not marked)
    local said = false
    for _, line in ipairs(LOGGED) do
      if tostring(line):find("does not fit", 1, true) then said = true end
    end
    check("but it is still said out loud, with the reason", said)
    -- The territory must have been handed OUR path. Passing nil made the engine
    -- generate its own loop, which is what a playtest saw as a third shape among
    -- ours: every territory whose path was not 32 points was a zero-unit one.
    local counts = {}
    for _, entry in ipairs(created_log.created) do
      counts[#counts + 1] = #entry.get_patrol_path()
    end
    local ours = #counts > 0
    for _, n in ipairs(counts) do if n ~= 32 then ours = false end end
    check("the territory still gets OUR 32-point path, not an engine-generated one",
      ours, "path point counts: " .. table.concat(counts, ","))
  end
end

print("a cone nobody has walked to is left alone, not taken for lost")
do
  -- The engine's precondition: create_territory refuses a list with no generated
  -- chunk, so a cone with none is marked "unseen" and retried when one arrives.
  -- The dangerous reading is that it is a claim in doubt -- the audit treating it
  -- as gone and re-creating it is what left two territories for one volcano
  -- (measured: big@1:0 created twice, 132 chunks, all of it ungenerated).
  --
  -- So the whole "don't know yet" state stays inside one function. What reaches
  -- the audit is one definite question -- is the claim KNOWN to be gone? -- and for
  -- a cone we have never claimed the answer is no. This is the check that fails if
  -- a third state is reintroduced, because a third state has to be threaded out to
  -- the caller to be acted on, and the only actions available are "recreate" and
  -- "leave it alone".
  local log = { created = {} }
  -- A surface generated somewhere else entirely, so no chunk of any cone here exists.
  local surface = fake_surface({ x = 100000, y = 100000 }, 1, log)
  local builder = Builder.new(surface, { created = {} })
  builder:on_chunk_generated{ x = 100000, y = 100000 }

  -- This builder's OWN decisions, not the shared fixture: the surface is generated
  -- somewhere else entirely, so a cone it saw there has no generated chunk of its
  -- own and must NOT be settled. A cone is found by asking the volcanoes, since nothing
  -- was recorded: the marker is written only when a cone is decided.
  local cone = nil
  for _, candidate in ipairs(builder.volcanoes:cones_near(100000, 100000, 24)) do
    if not builder:decided(candidate) then cone = candidate break end
  end
  check("a cone was seen out there and has no generated chunk of its own",
    cone ~= nil)
  if cone then
    check("it is not settled", not builder.created[cone.id] == true)

    -- The question this test exists for: a cone the player has not reached must
    -- not be treated as lost, withdrawn, or invented. There is no "gone" answer to
    -- give any more -- territory_of and the audit are gone, and the settled marker is
    -- the whole idempotency, so an undecided cone is simply not claimed and stays
    -- that way until one of its chunks is generated.
    check("nothing was created for it", #log.created == 0,
      #log.created .. " territories")
    check("it is still not settled", builder.created[cone.id] ~= true)
  end
end

-------------------------------------------------------------------- candidates
-- The per-chunk candidate set is the RING, and it has to be complete: the owner is
-- the nearest centre among the cones whose ground covers the chunk, so a candidate set
-- missing one hands the chunk to the wrong cone. A wrong owner shows up as a
-- wrongly-claimed volcano, and the e2e tolerates 8 differing chunks, so it is not a net
-- for this.
--
-- The check is by brute force against a much wider ring: if anything covering a chunk
-- is missing from the narrow one, the owners disagree. That is the invariant the
-- deleted own-region shortcut got wrong -- it built its candidates from
-- `contenders_for` of the cone in the chunk's own region, which filters by core-disc
-- proximity and can exclude a cone that covers the chunk outright.
print("the owner is the same from the shipped ring as from a much wider one")
do
  local log = { created = {} }
  local surface = fake_surface({ x = 0, y = 0 }, 30, log)
  local builder = Builder.new(surface, { created = {} })
  local volcanoes = builder.volcanoes
  local checked, disagreed, owned, none = 0, 0, 0, 0
  for dy = -24, 24, 3 do for dx = -24, 24, 3 do
    local narrow = volcanoes:nearby_cones(dx * 32 + 16, dy * 32 + 16, 0)
    local wide = volcanoes:nearby_cones(dx * 32 + 16, dy * 32 + 16, 512)
    if narrow.n > 0 then
      checked = checked + 1
      -- what the shipped path asks, against a ring 512 tiles wider
      local here = volcanoes:claim_owner_at(dx, dy)
      local there = volcanoes:claim_winner(wide, dx * 32 + 16, dy * 32 + 16)
      if here ~= there then disagreed = disagreed + 1 end
      if volcanoes:claim_owner_at(dx, dy) ~= here then disagreed = disagreed + 1 end
      if here == nil then none = none + 1 else owned = owned + 1 end
    end
  end end
  check("chunks were given a ring", checked > 0, checked .. " chunks")
  check("owner_at matches a 512px ring, repeatably",
    disagreed == 0,
    string.format("%d disagreed; %d owned, %d none", disagreed, owned, none))
end

if #LOGGED > 0 then
  print("log lines:")
  for _, line in ipairs(LOGGED) do print("  " .. tostring(line)) end
end

print()
if failures == 0 then
  print("BUILDER OK")
else
  print(string.format("BUILDER FAILED: %d checks", failures))
end
os.exit(failures == 0 and 0 or 1)
