-- The runtime prototype registry and the two globals the builder talks to a live
-- game through, stubbed for tests that run with no Factorio. The registry is the
-- real demolisher ladder: the values below were read from a live game
-- (`prototypes.entity[name].segment_engine`, asked over rcon) -- `distance_from_head`
-- is CUMULATIVE and `max_body_nodes` is the cap -- big 106 / medium 81 / small 55,
-- for bodies of 101.92 / 76.43 / 50.88 tiles. (The API docs say 63 for all three;
-- the prototypes do not agree, and the prototypes are what the engine enforces.)
--
-- Shared by tests/builder_test.lua, tests/split_probe.lua and tests/split_shape.lua
-- so the measured constants have ONE home, and loaded the same way everywhere:
--
--   package.path = "/workspace/tests/?.lua;/workspace/?.lua;" .. package.path
--   require("proto_stub")

-- Factorio's global log(), captured so a test can see what the builder said.
LOGGED = {}
function log(message) LOGGED[#LOGGED + 1] = tostring(message) end

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
  -- patrolling_turn_radius is read for the same reason as the rest: the builder lays
  -- the body within it, and a stub without it would exercise a builder that places
  -- nothing. It is on the PROTOTYPE ROOT, not in segment_engine -- which is how
  -- reading it from the wrong place placed no demolisher anywhere. One tile is a
  -- plausible demolisher value; the real one comes off the prototype.
  prototypes.entity[spec[1]] = { name = spec[1], type = "segmented-unit",
                                 segment_engine = { segments = segments,
                                                    max_body_nodes = spec[4] },
                                 patrolling_turn_radius = 1.0 }
end

-- prototypes.get_entity_filtered, which is how the builder discovers the demolisher
-- ladder (see discover_demolishers in volcano-demolisher.lua). The real engine does
-- this filtering in C++; the stub does what it says on the tin and returns only
-- segmented units, in BODY-LENGTH ORDER (the real collection sorts same-type
-- prototypes by their `order` string, and these three -- small=s-h, medium=s-i,
-- big=s-j -- come back smallest first).
--
-- Two things this stub deliberately does NOT reproduce, both of which the real
-- collection does:
--   * it is name-keyed userdata, so `out[1]` is nil and `table.sort` rejects it
--     outright -- an ordinary array hides both, which is how "table expected, got
--     userdata" reached a gate twice.
--   * `pairs` over `prototypes.entity` yields HASH order, not the engine's. Taking
--     that order verbatim trips the ladder's order check on every run, which is the
--     check doing its job on a stub that does not honour the contract.
prototypes.get_entity_filtered = function(filters)
  local want_type = nil
  for _, filter in ipairs(filters or {}) do
    if filter.filter == "type" then want_type = filter.type end
  end
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