-- What the cut's patrol loops actually look like, in numbers: how far apart the two
-- guards walk, how far each stays from the middle of its volcano, how sharp the worst
-- corner is, and how close a point comes to the edge of the territory it stands on.
--
--   lua tests/split_shape.lua [seed] [volcanism frequency]
--
-- Not a gate: this is the measurement the cut is tuned against, the way
-- tests/split_probe.lua is the census of what a seed splits into. The gate is
-- tests/builder_test.lua's two assertions on the same quantities.
package.path = "/workspace/tests/?.lua;/workspace/?.lua;" .. package.path

-- The prototype registry and log() stub (tests/proto_stub.lua) -- one home for the
-- measured demolisher ladder, shared with builder_test.lua and split_probe.lua.
require("proto_stub")

local cones = require("noise-mirror.volcano-cones")
local Demolisher = require("volcano-demolisher")
local PatrolPath = require("volcano-patrol-path")
local Split = require("volcano-split")

-- 180/pi, and NOT math.acos(0) * 2 -- which is pi, and which made every angle in this
-- file a number that looked like degrees and was not. A 90 degree corner was reported as
-- 4.9 and a spike as 9.9.
local RADIANS_TO_DEGREES = 180 / math.pi

--- How many times the loop turns back on itself, counted on the BEARING from the
--- volcano's centre: a ring walked once goes round one way and its bearing only ever
--- increases, so the signed changes never flip.
---
--- This is the check for a U-turn and backtrack, which is what a stray point in the
--- outline does: the path walks the outer arc out, comes in along the rim, and goes out
--- along the same arc again, and both of its "legs" then join the same end of it. The
--- playtest saw the guard do exactly that; nothing else here would have -- every point
--- was on claimed ground, the loop length fitted, and the corner angle was fine.
local function reversals(cone, path)
  local flips, direction = 0, 0
  local previous
  for index = 1, #path do
    local point = path[index]
    local bearing = math.atan2(point.y - cone.y, point.x - cone.x)
    if previous then
      local step = bearing - previous
      while step > math.pi do step = step - 2 * math.pi end
      while step < -math.pi do step = step + 2 * math.pi end
      -- Sub-degree wobble is the wobble, not a change of heart.
      if math.abs(step) > 0.02 then
        if direction ~= 0 and (step > 0) ~= (direction > 0) then flips = flips + 1 end
        direction = step
      end
    end
    previous = bearing
  end
  return flips
end

--- The sharpest corner in a closed polyline, in degrees. A leg meets an arc at a right
--- angle by construction, so this is the number that says whether the outline's corners
--- were actually rounded.
local function sharpest_corner(path)
  local worst = 0
  for index = 1, #path do
    local here, next_, before = path[index], path[(index % #path) + 1],
      path[((index - 2) % #path) + 1]
    local ax, ay = here.x - before.x, here.y - before.y
    local bx, by = next_.x - here.x, next_.y - here.y
    local a = math.sqrt(ax * ax + ay * ay)
    local b = math.sqrt(bx * bx + by * by)
    if a > 1e-6 and b > 1e-6 then
      local dot = (ax * bx + ay * by) / (a * b)
      local turn = math.acos(math.max(-1, math.min(1, dot))) * RADIANS_TO_DEGREES
      if turn > worst then worst = turn end
    end
  end
  return worst
end

local function reach(volcanoes, cone, contenders)
  return PatrolPath.ground_radius(volcanoes, cone, Split.angle_for(cone),
    PatrolPath.rivals_of(cone, contenders))
end

--- How far a point stands from BOTH edges of the ground it may walk on, in tiles,
--- measured along its own radius: the first unclaimed sample outwards, and the first
--- unclaimed sample inwards.
---
--- This replaced a probe that stepped eight compass directions out of the point and
--- reported the first miss -- which reads the CHUNK GRID, not the claim: any point two
--- tiles from a claimed/unclaimed chunk boundary reports two, hugging or not. The
--- playtest's "the territory around it is hugging it too closely" is the INWARD number
--- being small, and "jitter in the inner path" is it being small and different on every
--- neighbouring direction.
local function margins(inside, x, y, ux, uy)
  local function claimed(offset)
    return inside[PatrolPath.chunk_key(x + ux * offset, y + uy * offset)] == true
  end
  local outward, inward = math.huge, math.huge
  for step = 1, 400 do
    local offset = step
    if not claimed(offset) then outward = offset break end
  end
  for step = 1, 400 do
    local offset = step
    if not claimed(-offset) then inward = offset break end
  end
  return inward, outward
end

local seed = tonumber(arg[1]) or 12345
local frequency = tonumber(arg[2]) or 2
local volcanoes = cones.new_volcanoes(cones.new_context{
  seed = seed, volcanism_size = 1, volcanism_frequency = frequency })
Demolisher.discover()

local split, tightest, deepest, corner, standoff, shared = 0, math.huge, math.huge, 0,
  math.huge, 0
local zero_edges = 0
local shown = 0
local backtracks, worst_turn_around = 0, 0
local points_per_loop = 0
local pairs_by_class, loops = {}, 0
for region_x = -6, 6 do
  for region_y = -6, 6 do
    local cone = volcanoes:region_cone(volcanoes.systems[1], region_x, region_y)
    if cone then
      local contenders = volcanoes:contenders_for(cone)
      local share = volcanoes:cone_chunks(cone, contenders)
      local slices = Split.slices(volcanoes, cone, share, contenders)
      if #slices == 2 then
        split = split + 1
        local label = string.format("%d+%d", slices[1].class, slices[2].class)
        pairs_by_class[label] = (pairs_by_class[label] or 0) + 1
        for _, slice in ipairs(slices) do
          loops = loops + 1
          local inside = PatrolPath.set_for(slice.share)
          local this_corner = sharpest_corner(slice.patrol_path)
          corner = math.max(corner, this_corner)
          points_per_loop = points_per_loop + #slice.patrol_path
          if _G.EON_VERBOSE and shown < 2 then
            print(string.format("     slice %d: %d points, sharpest corner %.0f deg, "
              .. "loop %.0f tiles", slice.large and 2 or 1, #slice.patrol_path, this_corner,
              (function() local t = 0 for i = 1, #slice.patrol_path do
                local a = slice.patrol_path[i]
                local b = slice.patrol_path[(i % #slice.patrol_path) + 1]
                t = t + math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2) end return t end)()))
          end
          local flips = reversals(cone, slice.patrol_path)
          backtracks = backtracks + flips
          worst_turn_around = math.max(worst_turn_around, flips)
          -- Zero-length edges, counted rather than skipped: the corner measurement
          -- above epsilon-skips them, and they only fail a GATE at the first-edge-<1e-6
          -- heading contract -- so the census reports them on their own.
          for index = 1, #slice.patrol_path do
            local a, b = slice.patrol_path[index],
              slice.patrol_path[(index % #slice.patrol_path) + 1]
            if math.abs(a.x - b.x) < 1e-6 and math.abs(a.y - b.y) < 1e-6 then
              zero_edges = zero_edges + 1
            end
          end
          for _, point in ipairs(slice.patrol_path) do
            local dx, dy = point.x - cone.x, point.y - cone.y
            local radius = math.sqrt(dx * dx + dy * dy)
            deepest = math.min(deepest, radius)
            -- How much ground is under and around this point, which is the room the
            -- guard has to make the turn a corner asks of it. The arcs stop a chunk and
            -- a half clear of the cuts, so the tightest point in a loop is one of the
            -- arcs', where the ground runs out -- not a corner.
            local room = select(1, margins(inside, point.x, point.y, dx / radius, dy / radius))
            if room < standoff then
              standoff = room
              if _G.EON_VERBOSE then
                print(string.format("     tightest point: %s slice %d at r=%.0f of a %.0f "
                  .. "reach, %.0f tiles of claim around it", cone.id,
                  slice.large and 2 or 1, radius, reach(volcanoes, cone, contenders), room))
              end
            end
          end
        end
        -- The property that matters and is not a distance: no point of one loop stands
        -- on the other slice's ground, which is what "the loops do not cross" means.
        for index, slice in ipairs(slices) do
          local other = slices[index == 1 and 2 or 1]
          for _, point in ipairs(slice.patrol_path) do
            if Split.holds(other, math.floor(point.x / 32), math.floor(point.y / 32)) then
              shared = shared + 1
            end
          end
        end
        local a, b = slices[1].patrol_path, slices[2].patrol_path
        local at
        for _, p in ipairs(a) do
          for _, q in ipairs(b) do
            local d = math.sqrt((p.x - q.x) ^ 2 + (p.y - q.y) ^ 2)
            if d < tightest then
              tightest = d
              at = string.format("r %.0f / %.0f of a %.0f reach", (function()
                return math.sqrt((p.x - cone.x) ^ 2 + (p.y - cone.y) ^ 2) end)(),
                math.sqrt((q.x - cone.x) ^ 2 + (q.y - cone.y) ^ 2), reach(volcanoes, cone, contenders))
            end
          end
        end
        if _G.EON_VERBOSE and tightest < 32 then
          print(string.format("     %s: closest %.0f tiles, at %s", cone.id, tightest, at or "?"))
        end
        if _G.EON_VERBOSE and at and tightest < 16 then
          print(string.format("     %s: loops %.0f tiles apart, at %s", cone.id, tightest, at))
        end
      end
    end
  end
end

print(string.format("seed %d, volcanism %d%%: %d volcanoes cut into %d loops", seed,
  frequency * 100, split, loops))
local labels = {}
for label in pairs(pairs_by_class) do labels[#labels + 1] = label end
table.sort(labels)
local mix = {}
for _, label in ipairs(labels) do mix[#mix + 1] = label .. " x" .. pairs_by_class[label] end
print("  guard pairs: " .. table.concat(mix, ", "))
print(string.format("  the two loops never come closer than %.0f tiles, and %d of their "
  .. "points stand on the other slice's ground", tightest, shared))
print(string.format("  the innermost point of any loop is %.0f tiles from the volcano's centre",
  deepest))
print(string.format("  the sharpest corner anywhere is %.1f degrees, over %.0f points a loop",
  corner, loops > 0 and points_per_loop / loops or 0))
print(string.format("  the worst loop changes its mind %d time(s) going round (%d in total, "
  .. "over %d loops -- one per leg, which is what a ring does)", worst_turn_around, backtracks,
  loops))
print(string.format("  every loop point stands at least %.0f tiles inside its own ground's "
  .. "edge, which is the room the corner turns get", standoff))
print(string.format("  zero-length edges: %d (the body layout refuses a body seeded on one)",
  zero_edges))
-- # ponytail: loop-shape measurement for the split. Deletion safe; upgrade when the shape needs a different check.
