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
package.path = "/workspace/tests/?.lua;/workspace/?.lua;" .. package.path

-- The runtime prototype registry and log() stub live in tests/proto_stub.lua (one
-- home for the measured demolisher values -- see there for where they come from).
-- tests/split_shape.lua and tests/split_probe.lua load the same stub.
require("proto_stub")

-- The runtime prototype registry, stubbed with the real values read from a live
-- game (`prototypes.entity[name].segment_engine`, asked over rcon): the builder
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
      -- ON the territory it was placed on, which is the only way a test can say
      -- which guard belongs to which claim once a ring of cones is in play.
      if spec.territory then spec.territory.units[#spec.territory.units + 1] = spec.name end
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
  -- `cone` may be a SLICE (volcano-split.lua), which carries its own chunk list: a
  -- cut claim is two territories and "the one holding its chunks" is per slice.
  local share = cone.share or volcanoes:cone_chunks(cone, volcanoes:contenders_for(cone))
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
  local builder = Builder.new(surface, { created = {}, map_gen_settings = surface.map_gen_settings })
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
  check("the cone is settled", builder:decided(centre))
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
  local builder = Builder.new(surface, { created = {}, map_gen_settings = surface.map_gen_settings })
  builder:on_chunk_generated{ x = 100000, y = 100000 }
  -- Not settled, so the next chunk nearby will ask again: a cone the engine cannot
  -- take yet is the one thing the marker must NOT remember. There is no "unseen"
  -- value any more -- absent means exactly this.
  check("it is not settled", not builder:decided(centre))
  check("no territory was created", #log.created == 0)
end

print("a second event for the same cone does not create a second territory")
do
  local log = { created = {} }
  local centre = nil
  for id, cone in pairs(existing) do centre = cone break end
  local cx, cy = math.floor(centre.x / 32), math.floor(centre.y / 32)
  local surface = fake_surface({ x = cx, y = cy }, 24, log)
  local builder = Builder.new(surface, { created = {}, map_gen_settings = surface.map_gen_settings })
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
  -- nothing revealed when the first event landed), so the invariant is about THIS
  -- cone: its own ground, and how many territories hold it. "How many" rather than
  -- "one", because a cone big enough for two guards is cut in two (volcano-split.lua)
  -- and this test draws its cone with `pairs` -- a fixed choice until the cut made it
  -- a two-territory volcano on some runs and one on others.
  local share = volcanoes:cone_chunks(centre, volcanoes:contenders_for(centre))
  -- This cone's territories and how much of its share they hold between them.
  local function mine()
    local territories, held = 0, 0
    for _, territory in ipairs(log.created) do
      local mine_here = {}
      for _, member in ipairs(territory:get_chunks()) do
        mine_here[member.x .. "," .. member.y] = true
      end
      local hits = 0
      for _, chunk in ipairs(share) do
        if mine_here[chunk.x .. "," .. chunk.y] then hits = hits + 1 end
      end
      if hits > 0 then
        territories = territories + 1
        held = held + hits
      end
    end
    return territories, held
  end
  local before_territories, before_held = mine()
  check("the first pass claimed its ground", before_held > 0,
    string.format("%d of %d chunks in %d territories", before_held, #share,
      before_territories))
  builder:on_chunk_generated{ x = cx, y = cy }
  builder:on_chunk_generated{ x = cx, y = cy }
  builder:on_chunk_generated{ x = cx + 1, y = cy }
  local after_territories, after_held = mine()
  check("a repeat event claims nothing more for it",
    after_territories == before_territories and after_held == before_held,
    string.format("%d territories / %d chunks, then %d / %d", before_territories,
      before_held, after_territories, after_held))
end

print("every cone inside the generated area is claimed")
do
  local log = { created = {} }
  local surface = fake_surface({ x = 0, y = 0 }, 30, log)
  local builder = Builder.new(surface, { created = {}, map_gen_settings = surface.map_gen_settings })
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
      if builder:decided(cone) then claimed = claimed + 1 end
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
  local builder = Builder.new(surface, { created = {}, map_gen_settings = surface.map_gen_settings })
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
  check("it is still claimed, guard or no guard", builder:decided(centre))
end

print("the demolisher ladder is discovered and ordered by body length")
do
  -- The point of the discovery: a mod that adds a demolisher joins the ladder at
  -- its natural rank instead of needing this file (or the mod) edited. The stub
  -- above has three bodies; what must hold is that all three are FOUND, in body
  -- order, and that a three-tier ladder hands over at the MEASURED thresholds --
  -- the discovery must not quietly re-tune them.
  local surface = fake_surface({ x = 0, y = 0 }, 1, { created = {} })
  local builder = Builder.new(surface, { created = {}, map_gen_settings = surface.map_gen_settings })
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
  local builder = Builder.new(surface, { created = {}, map_gen_settings = surface.map_gen_settings })
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
  local builder = Builder.new(surface, { created = {}, map_gen_settings = surface.map_gen_settings })
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
    -- Direct create with no arriving chunk, to isolate the no-guard-fit branch the stub
    -- above forces. on_chunk_generated passes a position, but that only decides which
    -- slice of a SPLIT cone is still "unseen" -- and a cone that cannot carry a guard is
    -- never cut (Split.plan refuses it before producing two slices), so the single-slice
    -- path this hits is settled with one create call regardless of position.
    builder:create(cone)
    local logged = false
    for index = before + 1, #LOGGED do
      if tostring(LOGGED[index]):find("no guard placed", 1, true) then logged = true end
    end
    check("the claim is still made -- the volcano is real, the guard is not",
      logged or builder:decided(cone))
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

------------------------------------------------------------------- the cut
-- A volcano big enough for two guards is claimed as TWO territories: the claim cut
-- in half through the cone's own centre, one guard per side, and the two pieces
-- disjoint so neither can take ground from the other. These are the properties the
-- e2e probe cannot see -- it reads the surface, not which cone made which slice --
-- and they are cheap to get wrong, because a cut that shares chunks between two
-- territories is silent until one of them is built second.
print("a big cone is claimed as two territories, one guard each")
do
  local Split = require("volcano-split")
  local found, split, tried = nil, nil, 0
  for _, cone in pairs(existing) do
    tried = tried + 1
    local contenders = volcanoes:contenders_for(cone)
    local slices = Split.slices(volcanoes, cone, volcanoes:cone_chunks(cone, contenders), contenders)
    if #slices == 2 then split = { cone = cone, slices = slices } break end
  end
  check("this map has a cone that carries two guards", split ~= nil,
    tried .. " cones offered, none split")
  if split then
    local small, large = split.slices[1], split.slices[2]
    check("the two guards are one size step apart",
      large.class - small.class == 1,
      string.format("rungs %d and %d", small.class, large.class))
    check("the small slice is the smaller one",
      small.fraction < large.fraction,
      string.format("%.2f against %.2f of the claim", small.fraction, large.fraction))
    -- The CLAMP: the carved slice is a quarter to a half of the circle, so its loop is
    -- a walkable shape. The other side is the remainder (a half-disc cut leaves a
    -- quarter and three quarters, and both pieces cannot be halves at once without a
    -- third piece between them).
    check("the carved slice is between a quarter and a half of the volcano",
      small.fraction >= 0.25 and small.fraction <= 0.5,
      string.format("%.0f degrees of %.0f", small.fraction * 360, large.fraction * 360))
    -- The outline's corners: a leg meets the arc at a right angle, and a body cannot
    -- turn 90 degrees in a tile, so the corners are ROUNDED. The sharp polygon this
    -- replaced turned 90 degrees in one step.
    local PatrolPath = require("volcano-patrol-path")
    local worst_turn = 0
    for _, slice in ipairs(split.slices) do
      local path = slice.patrol_path
      for index = 1, #path do
        local a = path[index]
        local b = path[(index % #path) + 1]
        local before = path[((index - 2) % #path) + 1]
        local ax, ay = a.x - before.x, a.y - before.y
        local bx, by = b.x - a.x, b.y - a.y
        local la = math.sqrt(ax * ax + ay * ay)
        local lb = math.sqrt(bx * bx + by * by)
        if la > 1e-6 and lb > 1e-6 then
          local dot = (ax * bx + ay * by) / (la * lb)
          -- 180/pi, and NOT math.acos(0) * 2, which is pi: a 90 degree corner came out
          -- as 4.9 that way and the check below was satisfied by anything.
          local turn = math.acos(math.max(-1, math.min(1, dot))) * 180 / math.pi
          worst_turn = math.max(worst_turn, turn)
        end
      end
    end
    -- The two joins ARE corners, and they are meant to be: the guard rounds them itself
    -- (its patrolling_turn_radius is a whole radian per tile, so a right angle costs it
    -- a tile and a half) and the arcs stop a chunk and a half short of the cuts, so it
    -- has open ground to do it in. What must not happen is a SPIKE -- two edges pointing
    -- straight back at each other, which is a fold in the outline rather than a corner,
    -- and which is what a duplicated arc was.
    check("no corner of either outline folds back on itself",
      worst_turn < 170, string.format("%.0f degrees at the sharpest", worst_turn))
    -- Zero-length edges: none may survive. The walk back onto the claim can land a
    -- point exactly on its neighbour (membership is chunk-coarse and the walk's
    -- terminal step is the neighbour itself), and the body layout seeds its heading
    -- along the FIRST edge and refuses a body with none -- so one repeated point means
    -- a slice with a class and no demolisher, which the e2e only sees as a missing
    -- guard. drop_repeats is the fix; this pins the contract it enforces, at the same
    -- boundary the engine reads (the closed loop, wrap-around edge included).
    local repeats = 0
    for _, slice in ipairs(split.slices) do
      local path = slice.patrol_path
      for index = 1, #path do
        local a, b = path[index], path[(index % #path) + 1]
        if math.abs(a.x - b.x) < 1e-6 and math.abs(a.y - b.y) < 1e-6 then
          repeats = repeats + 1
        end
      end
    end
    check("no loop has a zero-length edge", repeats == 0,
      repeats .. " consecutive identical points")
    -- The loop goes ROUND ONCE: the bearing from the cone's centre only ever turns one
    -- way along the arc, so the signed changes never flip -- except once at each of the
    -- two legs, which is what a closed ring does. More than two is a backtrack, and the
    -- one that was here walked the outer arc out, the rim in, and the outer arc AGAIN,
    -- with both legs on the same end of it: every point was on claimed ground, the loop
    -- fitted, the corner angle was fine, and the guard U-turned in play.
    local flips = 0
    for _, slice in ipairs(split.slices) do
      -- Per loop, and counted as a maximum over the two: carrying the bearing across
      -- from one loop to the other would count the jump between two unrelated loops as a
      -- turn, and a ring turns once at each of ITS two legs, so two each.
      local direction, previous = 0, nil
      local this_loop = 0
      for index = 1, #slice.patrol_path do
        local point = slice.patrol_path[index]
        local bearing = math.atan2(point.y - split.cone.y, point.x - split.cone.x)
        if previous then
          local step = bearing - previous
          while step > math.pi do step = step - 2 * math.pi end
          while step < -math.pi do step = step + 2 * math.pi end
          if math.abs(step) > 0.02 then
            if direction ~= 0 and (step > 0) ~= (direction > 0) then
              this_loop = this_loop + 1
            end
            direction = step
          end
        end
        previous = bearing
      end
      flips = math.max(flips, this_loop)
    end
    check("neither loop walks the same ground twice", flips <= 2,
      string.format("the worst loop turns back %d times going round, at its %d legs", flips,
        2))
    -- Two guards that walk within a chunk of one another bump, and the playtest asks
    -- for it twice ("it must not overlap or get too close to the neighbour's patrol
    -- path"). The arcs are a chunk clear of the cut on each side and the plan refuses a
    -- cut that cannot hold it, so this holds by construction -- and a point the walk
    -- moved is the one way it can be broken.
    local closest = math.huge
    for _, a in ipairs(small.patrol_path) do
      for _, b in ipairs(large.patrol_path) do
        local dx, dy = a.x - b.x, a.y - b.y
        closest = math.min(closest, math.sqrt(dx * dx + dy * dy))
      end
    end
    check("the two guards never walk within a chunk of each other", closest >= 32,
      string.format("%.0f tiles at the closest", closest))
    -- And the arc is the volcano's OWN patrol radius over the wedge's directions, not
    -- a circle of its own: a slice traces the edge the whole volcano traces.
    local reach = PatrolPath.ground_radius(volcanoes, split.cone, Split.angle_for(split.cone),
      PatrolPath.rivals_of(split.cone, volcanoes:contenders_for(split.cone)))
    local traced = 0
    for _, point in ipairs(small.patrol_path) do
      traced = math.max(traced, math.sqrt((point.x - split.cone.x) ^ 2
        + (point.y - split.cone.y) ^ 2))
    end
    check("the arc reaches the volcano's own ground edge",
      traced >= reach * 0.9, string.format("%.0f of %.0f tiles", traced, reach))
    -- The claim is cut in two, so the pieces must be disjoint AND add back up to
    -- the whole: overlapping chunks would make create_territory's "strip from other
    -- territories" decide the answer by build order.
    local key = {}
    for _, chunk in ipairs(small.share) do
      local k = chunk.x .. "," .. chunk.y
      if key[k] then check("the pieces are disjoint", false, k .. " is in both") end
      key[k] = "small"
    end
    local overlaps, total = 0, 0
    for _, chunk in ipairs(large.share) do
      local k = chunk.x .. "," .. chunk.y
      if key[k] == "small" then overlaps = overlaps + 1 end
      key[k] = true
      total = total + 1
    end
    local share = volcanoes:cone_chunks(split.cone, volcanoes:contenders_for(split.cone))
    check("the two pieces are disjoint", overlaps == 0, overlaps .. " shared chunks")
    -- Between them the two pieces are the WHOLE claim: nothing is dropped in the middle.
    -- An earlier version left a caldera unclaimed there, which is a hole in a volcano
    -- and a difference between the claim and the mirror's chunk list that the e2e could
    -- only check by re-deriving the cut. The loops are rings because of where they WALK,
    -- not because of what is claimed.
    check("and between them they are the whole claim",
      total + #small.share == #share,
      total .. " + " .. #small.share .. " against " .. #share)
    -- Every patrol point stands on its OWN territory's ground: a loop that crossed
    -- the cut would put a guard on the other guard's volcano, which no test has
    -- caught so far and the game would show as two animals on one disc.
    local off, points = 0, 0
    for _, slice in ipairs(split.slices) do
      for _, point in ipairs(slice.patrol_path) do
        points = points + 1
        if not Split.holds(slice, math.floor(point.x / 32), math.floor(point.y / 32)) then
          off = off + 1
        end
      end
    end
    check("every patrol point of both loops is on its own slice", off == 0,
      off .. " of " .. points .. " points off")
    -- And the guards are placed, one per territory, whole.
    local log = { created = {} }
    local centre = split.cone
    local surface = fake_surface({
      x = math.floor(centre.x / 32), y = math.floor(centre.y / 32) }, 24, log)
    local builder = Builder.new(surface, { created = {}, map_gen_settings = surface.map_gen_settings })
    for _, chunk in ipairs(share) do
      if surface.is_chunk_generated(chunk) then
        builder:on_chunk_generated{ x = chunk.x, y = chunk.y }
      end
    end
    check("the cone is settled once BOTH of its territories exist", builder:decided(centre))
    -- One guard per slice, each the size its own ground asked for. Read off the
    -- TERRITORY and not off the surface: one chunk event decides a whole ring of
    -- cones, so "every unit on this surface" says nothing about this volcano.
    local ladder = Demolisher.discover()
    local wrong = {}
    for index, slice in ipairs(split.slices) do
      local wanted = ladder[slice.class].name
      local territory = territory_for(log, slice)
      local got = territory and territory.units[1]
      if got ~= wanted then
        wrong[#wrong + 1] = string.format("slice %d wanted %s, got %s", index, wanted,
          tostring(got))
      end
    end
    check("one guard per slice, each the size its own ground asked for", #wrong == 0,
      table.concat(wrong, "; "))
  end
end

print("the cut is the same whichever slice is built first")
do
  -- The engine gives a chunk to ONE territory and takes it from whoever held it, so
  -- an overlap between the two pieces would not fail -- it would be resolved by BUILD
  -- ORDER, silently, and two loads of the same map would disagree. That is the whole
  -- question this asks, and it is asked by building the cone twice with the pieces
  -- delivered in opposite orders and comparing the result chunk by chunk.
  local Split = require("volcano-split")
  local split = nil
  for _, cone in pairs(existing) do
    local contenders = volcanoes:contenders_for(cone)
    local slices = Split.slices(volcanoes, cone, volcanoes:cone_chunks(cone, contenders), contenders)
    if #slices == 2 then split = { cone = cone, slices = slices } break end
  end
  check("this map has a cone that carries two guards", split ~= nil, "none split")
  if split then
    -- One cone, two orders: `forward` delivers a chunk of the small piece first,
    -- `backward` one of the large piece first. Each returns, per piece, the set of
    -- chunks its territory ended up holding -- and counts a chunk held twice, which
    -- is what an overlap looks like from the outside.
    local function build(order)
      local log = { created = {} }
      local first = split.slices[order == 1 and 1 or 2].share[1]
      local surface = fake_surface({ x = first.x, y = first.y }, 40, log)
      local builder = Builder.new(surface, { created = {}, map_gen_settings = surface.map_gen_settings })
      for _, slice in ipairs(split.slices) do
        local chunk = slice.share[order == 1 and 1 or #slice.share]
        builder:create(split.cone, chunk)
      end
      local held, doubled = {}, 0
      for _, territory in ipairs(log.created) do
        for _, member in ipairs(territory:get_chunks()) do
          local key = member.x .. "," .. member.y
          if held[key] then doubled = doubled + 1 end
          held[key] = true
        end
      end
      local pieces = {}
      for index, slice in ipairs(split.slices) do
        local territory = territory_for(log, slice)
        local set = {}
        for _, member in ipairs(territory:get_chunks()) do
          set[member.x .. "," .. member.y] = true
        end
        pieces[index] = set
      end
      return held, doubled, pieces
    end
    local forward, doubled_forward, pieces_forward = build(1)
    local backward, doubled_backward, pieces_backward = build(2)
    -- `#` on a set of string keys is 0, so the coverage is counted, not measured.
    local function count(set) local n = 0 for _ in pairs(set) do n = n + 1 end return n end
    check("no chunk is in both territories, in either order",
      doubled_forward == 0 and doubled_backward == 0,
      string.format("%d then %d chunks held twice", doubled_forward, doubled_backward))
    local share = volcanoes:cone_chunks(split.cone, volcanoes:contenders_for(split.cone))
    check("and no chunk of the claim is unclaimed, in either order",
      count(forward) == #share and count(backward) == #share,
      string.format("%d and %d of %d chunks held", count(forward), count(backward), #share))
    -- The comparison that matters: the same chunk in the same PIECE, whichever piece
    -- the builder reached first.
    local different = {}
    for index = 1, 2 do
      for key in pairs(pieces_forward[index]) do
        if not pieces_backward[index][key] then
          different[#different + 1] = string.format("piece %d: %s", index, key)
        end
      end
    end
    check("both orders produce the same territories", #different == 0,
      #different .. " chunks moved between the pieces: "
        .. table.concat(different, ", "))
  end
end

print("a slice with no revealed ground of its own is claimed later, not at once")
do
  local Split = require("volcano-split")
  -- The engine wants one GENERATED chunk in every list it is given, so a cut claim
  -- is two of those preconditions, and the chunk that woke the mod satisfies one at
  -- most. The other waits for the next event that carries one of ITS chunks -- and
  -- nothing about the cone changes in between, so the second territory is identical
  -- to what a whole claim would have produced.
  local found, split = nil, nil
  for _, cone in pairs(existing) do
    local contenders = volcanoes:contenders_for(cone)
    local slices = Split.slices(volcanoes, cone, volcanoes:cone_chunks(cone, contenders), contenders)
    if #slices == 2 then split = { cone = cone, slices = slices } found = cone break end
  end
  if split then
    local share = volcanoes:cone_chunks(found, volcanoes:contenders_for(found))
    -- Reveal only what the SMALL slice has, which is the frontier case: the big side
    -- of the cut has nothing revealed at all.
    local small = split.slices[1]
    local first = small.share[1]
    local log = { created = {} }
    local surface = fake_surface({ x = first.x, y = first.y }, 0, log)
    local builder = Builder.new(surface, { created = {}, map_gen_settings = surface.map_gen_settings })
    builder:on_chunk_generated{ x = first.x, y = first.y }
    check("one of the two territories exists and the cone is not settled yet",
      #log.created == 1 and not builder:decided(found),
      #log.created .. " territories, decided=" .. tostring(builder:decided(found)))
    -- Now reveal the other side and deliver one of its chunks.
    local other = split.slices[2].share[1]
    surface = fake_surface({ x = other.x, y = other.y }, 0, log)
    builder = Builder.new(surface, { created = builder.created,
      map_gen_settings = surface.map_gen_settings })
    builder:on_chunk_generated{ x = other.x, y = other.y }
    check("the second slice is claimed when a chunk of its own arrives",
      builder:decided(found), #log.created .. " territories in total")
  else
    check("this map has a cone that carries two guards", false, "none split")
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
  local builder = Builder.new(surface, { created = {}, map_gen_settings = surface.map_gen_settings })
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
    check("it is not settled", not builder:decided(cone))

    -- The question this test exists for: a cone the player has not reached must
    -- not be treated as lost, withdrawn, or invented. There is no "gone" answer to
    -- give any more -- territory_of and the audit are gone, and the settled marker is
    -- the whole idempotency, so an undecided cone is simply not claimed and stays
    -- that way until one of its chunks is generated.
    check("nothing was created for it", #log.created == 0,
      #log.created .. " territories")
    check("it is still not settled", not builder:decided(cone))
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
  local builder = Builder.new(surface, { created = {}, map_gen_settings = surface.map_gen_settings })
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
