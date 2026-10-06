-- What the split costs, judged against the 16.66 ms tick. Drives the REAL shipped
-- path -- Builder:on_chunk_generated over the share chunks of every cone in the
-- window -- with a surface faked down to its two writes (create_territory,
-- create_segmented_unit); the mirror context is handed in as plain values, which
-- is exactly how the shipped builder is driven.
--
-- Three numbers matter:
--   * plan_once -- the wedge outlines + walks + fit, paid ONCE per cone, cached in
--     Builder.plans. Amortised over the cone's chunks, it is a fixed first-touch cost.
--   * first touch -- a chunk event that decides/claims something: mirror + plan
--     (once) + create_territory. This is the worst-case single-event cost.
--   * steady state -- a chunk event for an already-decided cone: mirror + marker
--     checks. This is what every chunk after the frontier costs.
--
--   lua tests/split_bench.lua [seed] [frequency] [regions-span]
package.path = "/workspace/tests/?.lua;/workspace/?.lua;" .. package.path
require("proto_stub")

local Split = require("volcano-split")
local Builder = require("volcano-territory")

local seed = tonumber(arg[1]) or 12345
local frequency = tonumber(arg[2]) or 2
local span = tonumber(arg[3]) or 4

-- The two writes the builder makes, and nothing else -- no settings, no chunk
-- queries: those are what the builder must NOT read.
local function minimal_surface()
  local created = {}
  local surface = {
    create_territory = function(spec)
      local territory = { chunks = {}, path = spec.patrol_path, units = {} }
      for _, chunk in ipairs(spec.chunks) do
        territory.chunks[#territory.chunks + 1] = { x = chunk.x, y = chunk.y }
        created[chunk.x .. "," .. chunk.y] = territory
      end
      function territory.get_chunks() return territory.chunks end
      function territory.get_patrol_path() return territory.path or {} end
      function territory.get_segmented_units() return territory.units end
      return territory
    end,
    create_segmented_unit = function() end,
    get_territory_for_chunk = function(position)
      return created[position.x .. "," .. position.y]
    end,
  }
  return surface
end

local settings = { seed = seed,
  autoplace_controls = { vulcanus_volcanism = { size = 1, frequency = frequency } } }
local builder = Builder.new(minimal_surface(), { map_gen_settings = settings })
local volcanoes = builder.volcanoes

-- Every cone in the window and the chunks of its shares (deduplicated: one chunk
-- event per chunk, wherever its cone's share sits).
local cones, chunks, seen = {}, {}, {}
for region_x = -span, span do
  for region_y = -span, span do
    local cone = volcanoes:region_cone(volcanoes.systems[1], region_x, region_y)
    if cone then
      cones[#cones + 1] = cone
      local contenders = volcanoes:contenders_for(cone)
      for _, chunk in ipairs(volcanoes:cone_chunks(cone, contenders)) do
        local key = chunk.x .. "," .. chunk.y
        if not seen[key] then
          seen[key] = true
          chunks[#chunks + 1] = chunk
        end
      end
    end
  end
end

local function ms() return os.clock() * 1e3 end

-- 1. plan_once, isolated: the full split decision per cone.
local plan_total, plan_worst, splits = 0, 0, 0
for _, cone in ipairs(cones) do
  local t = ms()
  local slices = Split.slices(volcanoes, cone, volcanoes:cone_chunks(cone,
    volcanoes:contenders_for(cone)), volcanoes:contenders_for(cone))
  local dt = ms() - t
  plan_total = plan_total + dt
  if dt > plan_worst then plan_worst = dt end
  if #slices > 1 then splits = splits + 1 end
end

-- 2. First touch: the burst a player's reveal pays, worst event included.
local touch_total, touch_worst, events = 0, 0, 0
for _, chunk in ipairs(chunks) do
  local t = ms()
  builder:on_chunk_generated{ x = chunk.x, y = chunk.y }
  local dt = ms() - t
  events = events + 1
  touch_total = touch_total + dt
  if dt > touch_worst then touch_worst = dt end
end

-- 3. Steady state: the same chunks again, all cones decided.
local steady_total = 0
for _, chunk in ipairs(chunks) do
  local t = ms()
  builder:on_chunk_generated{ x = chunk.x, y = chunk.y }
  steady_total = steady_total + ms() - t
end

local territories = 0
for _, state in pairs(builder.created) do
  if type(state) == "table" then territories = territories + #state
  elseif state == true then territories = territories + 1 end
end

print(string.format("seed %d, volcanism %d%%, %d cones, %d chunk events:",
  seed, frequency * 100, #cones, events))
print(string.format("  plan_once:     %.1f ms total, %.2f ms per cone (worst %.2f ms = %.1f%% of a tick), %d split",
  plan_total, plan_total / #cones, plan_worst, plan_worst / 16.66 * 100, splits))
print(string.format("  first touch:   %.1f ms total, %.1f us per chunk event, worst single %.2f ms (%.1f%% of a tick)",
  touch_total, touch_total / events * 1e3, touch_worst, touch_worst / 16.66 * 100))
print(string.format("  steady state:  %.1f us per chunk event", steady_total / events * 1e3))
print(string.format("  territories:   %d", territories))