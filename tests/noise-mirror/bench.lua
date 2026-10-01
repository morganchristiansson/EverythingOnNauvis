-- Standalone benchmark for the spot mirror.
--
--   lua tests/noise-mirror/bench.lua [seed] [chunks_x] [chunks_y] [frequency]
--
-- The workload that matters is a map reset: on_chunk_generated fires for
-- thousands of chunks, and each one asks "which cone owns this chunk, and how
-- wide is it". This measures that path end to end, cold and warm, and prints
-- the numbers a regression would show up in.
--
-- Chunks are streamed row by row, the way generation delivers them, so the
-- region cache is exercised the way it is in game (each row walks into fresh
-- regions; the rows above it are cache hits).
-- Runnable from anywhere: make the mod root requireable by dotted path, the
-- same way control.lua does it inside Factorio.
local script = (arg and arg[0]) or ""
local here = script:match("^(.*)[/\\][^/\\]+$") or "."
-- tests/noise-mirror -> tests -> the mod root, two levels up (these are tools,
-- not shipped mirror code, so they live under tests/ where create_zip.py
-- already excludes them).
local root = here:match("^(.*)[/\\][^/\\]+$") or here
root = root:match("^(.*)[/\\][^/\\]+$") or root
package.path = root .. "/?.lua;" .. package.path

local cones = require("noise-mirror.volcano-cones")

local seed = tonumber(arg[1]) or 12345
local width = tonumber(arg[2]) or 200
local height = tonumber(arg[3]) or 200
local frequency = tonumber(arg[4]) or 2

local function clock() return os.clock() end

local started = clock()
local volcanoes = cones.new_volcanoes(cones.new_context{
  seed = seed, volcanism_size = 1, volcanism_frequency = frequency,
})
local ready = clock() - started

-- Cold pass: every chunk asks for its owner, streaming row by row.
local owned, sum_width = 0, 0
started = clock()
for cy = 0, height - 1 do
  for cx = 0, width - 1 do
    local owner, cone_width = volcanoes:chunk_owner(cx, cy)
    if owner then
      owned = owned + 1
      sum_width = sum_width + cone_width
    end
  end
end
local cold = clock() - started
local total = width * height

-- Warm pass: the same chunks again, which is what a re-generation or a second
-- event over the same area costs.
started = clock()
for cy = 0, height - 1 do
  for cx = 0, width - 1 do
    volcanoes:chunk_owner(cx, cy)
  end
end
local warm = clock() - started

-- The path control.lua actually walks: for every generated chunk, list the cones
-- it can see (that is what feeds the pending set), not just the owning one.
started = clock()
for cy = 0, height - 1 do
  for cx = 0, width - 1 do
    volcanoes:cones_near(cx, cy, 2)
  end
end
local seen = clock() - started

-- Footprint pass: the per-territory work -- one closed chunk set per cone.
local cone_list = select(1, volcanoes:cones_near(width / 2, height / 2, math.max(width, height)))
started = clock()
local chunks_total = 0
for _, cone in ipairs(cone_list) do
  chunks_total = chunks_total + #volcanoes:cone_chunks(cone)
end
local footprint = clock() - started

print(string.format("seed %d, %d x %d chunks (%d), volcanism frequency %g",
  seed, width, height, total, frequency))
print(string.format("  volcanoes setup          %8.1f ms", ready * 1000))
print(string.format("  chunk owners (cold)  %8.1f ms  (%.2f us/chunk, %.0f chunks/s)",
  cold * 1000, cold / total * 1e6, total / cold))
print(string.format("  chunk owners (warm)  %8.1f ms  (%.2f us/chunk, %.0f chunks/s)",
  warm * 1000, warm / total * 1e6, total / warm))
print(string.format("  cone scan per chunk  %8.1f ms  (%.2f us/chunk, the control.lua path)",
  seen * 1000, seen / total * 1e6))
print(string.format("  cone footprints      %8.1f ms  (%d cones, %d chunks)",
  footprint * 1000, #cone_list, chunks_total))
local cache = require("noise-mirror.cache_census")(volcanoes)

print(string.format("  region cache         %8d entries (raw %d, rings %d)",
  cache.regions, cache.raw_regions, cache.rings))
print(string.format("  owned chunks         %8d (%.1f%%), mean cone width %.1f tiles",
  owned, 100.0 * owned / total, owned > 0 and sum_width / owned or 0))
