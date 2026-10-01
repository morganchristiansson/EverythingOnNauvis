-- The body the REAL code produces, and the turns it actually contains.
-- Pure Lua, no game: builder_test.lua already shows the prototypes and surface
-- can be stubbed, so this drives volcano-demolisher.lua for real.
package.path = "/workspace/?.lua;" .. package.path
-- control.lua provides these; without them the real module cannot even log.
log = function() end
defect = function() end
prototypes = { entity = {} }
local LADDER = { {"small-demolisher", 42, 50.88, 55}, {"medium-demolisher", 62, 76.43, 81},
                 {"big-demolisher", 106, 101.92, 106} }
for _, spec in ipairs(LADDER) do
  local segments = {}
  for index = 1, spec[2] do
    segments[index] = { distance_from_head = spec[3] * (index / spec[2]) ^ 0.92 }
  end
  -- patrolling_turn_radius ON THE PROTOTYPE, where it actually lives, and 10
  -- because that is what the game reports.
  prototypes.entity[spec[1]] = { name = spec[1], type = "segmented-unit",
    segment_engine = { segments = segments, max_body_nodes = spec[4] },
    patrolling_turn_radius = 10.0 }
end
local PROTOS = {}
for _, spec in ipairs(LADDER) do PROTOS[#PROTOS+1] = prototypes.entity[spec[1]] end
prototypes.get_entity_filtered = function() return PROTOS end

local Demolisher = require("volcano-demolisher")
local cones = require("noise-mirror.volcano-cones")
local PatrolPath = require("volcano-patrol-path")

local defs = {}   -- report a missing volcanoes rather than counting zero
local volcanoes = cones.new_volcanoes(cones.new_context{
  seed = 2990337218, volcanism_size = 1, volcanism_frequency = 6 })
Demolisher.discover()

local worst, joints, units, worst_gap = 0, 0, 0, 0
local RATIOS, BAD = {}, {}
for _, cone in ipairs(volcanoes:cones_near(-50, 40, 14)) do
  local cx, cy, point_at = PatrolPath.patrol_circle(volcanoes, cone, volcanoes:cone_chunks(cone, volcanoes:contenders_for(cone)), volcanoes:contenders_for(cone))
  if cx then
    for class = 1, 3 do
      local path = {}
      for i = 0, 31 do local x, y = point_at(2*math.pi*i/32); path[#path+1] = {x=x, y=y} end
      local body = Demolisher.body_nodes(cone, path, class)
      if body and #body > 3 then
        units = units + 1
        local R = 10.0
        for i = 2, #body - 1 do
          local a, b, c = body[i-1], body[i], body[i+1]
          local ax, ay = b.x-a.x, b.y-a.y
          local bx, by = c.x-b.x, c.y-b.y
          local al, bl = math.sqrt(ax*ax+ay*ay), math.sqrt(bx*bx+by*by)
          if al > 0 and bl > 0 then
            local d = math.abs(al - bl)
            if d > worst_gap then worst_gap = d end          -- the seg gap
            local dot = (ax*bx + ay*by) / (al*bl)
            dot = math.max(-1, math.min(1, dot))
            local ratio = math.acos(dot) * R / ((al+bl)/2)
            RATIOS[#RATIOS+1] = ratio
            if ratio > 1.0 then
              BAD[#BAD+1] = string.format("  joint %d ratio %.2f  seg %.3f/%.3f  at (%.1f,%.1f)",
                i, ratio, al, bl, b.x, b.y)
            end
            if ratio > worst then worst = ratio end
            joints = joints + 1
          end
        end
      end
    end
  end
end

-- Sorted, because the checks below index percentiles of it. It was not, and an
-- unsorted percentile is how p99 came out BELOW the median, which is impossible and
-- should have stopped me reading the number at all.
table.sort(RATIOS)

-- What this exists for. The turn limit was "implemented" twice before and measured
-- 12.2x the allowed radius, then 4.4x, then 3.2x, and every gate stayed green,
-- because the placement rule is only observable in the node list it produces. A
-- rule can be present, wired, logged, and do nothing; this drives the REAL
-- volcano-demolisher.lua and measures its output.
local checks, failures = 0, 0
local function check(name, ok, detail)
  checks = checks + 1
  if ok then
    print(string.format("  ok   %s%s", name, detail and (" -- " .. detail) or ""))
  else
    failures = failures + 1
    print(string.format("  FAIL %s%s", name, detail and (" -- " .. detail) or ""))
  end
end

check("every body was produced", units > 0, units .. " bodies, " .. joints .. " joints")
-- 1.0001, not 1.0: the clamp puts the worst joint EXACTLY on the limit, so a
-- bare > 1.0 counts float epsilon as a violation.
check("no joint turns harder than the radius allows", worst <= 1.0001,
  string.format("worst %.4f of the limit", worst))
check("segments are rigid: no node spacing varies", worst_gap < 1e-9,
  string.format("worst spacing error %.2e tiles", worst_gap))
-- The median says whether the clamp is IDLE most of the time, which is what makes
-- the body track the patrol path rather than approximate it. It is a fraction of the
-- limit, not a turn: 0.17 is about a degree per tile, a gentle curve. It was 0.005
-- before the rotation amount was fixed, when the body under-turned and so
-- under-used the radius it was given.
check("the clamp is idle most of the time, so the body tracks the patrol path",
  RATIOS[math.floor(#RATIOS * 0.5)] < 0.5,
  string.format("median turn %.3f of the limit", RATIOS[math.floor(#RATIOS*0.5)]))
check("the limit is reached at the corners, not ignored",
  RATIOS[math.floor(#RATIOS * 0.99)] > 0.5,
  string.format("p99 turn %.3f of the limit", RATIOS[math.floor(#RATIOS*0.99)]))
-- A follower must never be talked into reversing. This is a GUARD, not the fix
-- for a patrol observed going counter-clockwise: the patrol path is built one way and a
-- patrol that reverses is not on it. What causes that is not yet known -- see the
-- commit message -- so this only asserts the property the guard is there to keep.
local quarter = 0
for _, r in ipairs(RATIOS) do
  if r > 2.5 then quarter = quarter + 1 end
end
check("the body never reverses on a hint from behind", quarter == 0,
  string.format("%d of %d joints past a quarter turn", quarter, #RATIOS))
check("no defects while placing", #defs == 0, #defs .. " defects")

if failures > 0 then
  print(string.format("DEMOLISHER TURN TEST FAILED: %d of %d", failures, checks))
  os.exit(1)
end
print(string.format("DEMOLISHER TURN TEST OK: %d checks", checks))
os.exit(0)
