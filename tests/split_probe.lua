-- How many cones a split would actually take, and what they would carry.
--   lua tests/split_probe.lua [seed] [frequency]
package.path = "/workspace/tests/?.lua;/workspace/?.lua;" .. package.path

-- The prototype registry and log() stub (tests/proto_stub.lua) -- one home for the
-- measured demolisher ladder, shared with builder_test.lua and split_shape.lua.
require("proto_stub")

local cones = require("noise-mirror.volcano-cones")
local Demolisher = require("volcano-demolisher")
local Split = require("volcano-split")

local seed = tonumber(arg[1]) or 12345
local frequency = tonumber(arg[2]) or 2
local volcanoes = cones.new_volcanoes(cones.new_context{
  seed = seed, volcanism_size = 1, volcanism_frequency = frequency,
})
Demolisher.discover()

local tally, reasons, total = {}, {}, 0
for region_x = -6, 6 do
  for region_y = -6, 6 do
    local cone = volcanoes:region_cone(volcanoes.systems[1], region_x, region_y)
    if cone then
      total = total + 1
      local contenders = volcanoes:contenders_for(cone)
      local share = volcanoes:cone_chunks(cone, contenders)
      local slices = Split.slices(volcanoes, cone, share, contenders)
      local label
      if #slices == 2 then
        label = string.format("%d+%d", slices[1].class, slices[2].class)
      else
        label = "one"
      end
      tally[label] = (tally[label] or 0) + 1
      reasons[slices.unsplit_reason or "split"] =
        (reasons[slices.unsplit_reason or "split"] or 0) + 1
    end
  end
end
print(string.format("seed %d frequency %d: %d cones", seed, frequency, total))
local keys = {}
for k in pairs(tally) do keys[#keys + 1] = k end
table.sort(keys)
for _, k in ipairs(keys) do print(string.format("  %-8s %d", k, tally[k])) end
print("reasons:")
keys = {}
for k in pairs(reasons) do keys[#keys + 1] = k end
table.sort(keys)
for _, k in ipairs(keys) do print(string.format("  %-70s %d", k, reasons[k])) end
-- # ponytail: census tool for the split. Deletion safe; upgrade when a second split mechanism arrives.
