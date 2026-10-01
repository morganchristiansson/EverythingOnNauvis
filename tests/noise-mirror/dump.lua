-- Standalone CLI: dump the per-chunk cone owner and effective width of a
-- chunk-radius window, for the parity test and for eyeballing a map.
--
--   lua tests/noise-mirror/dump.lua <seed> <frequency> <size> <cx> <cy> <radius> [gate.txt] [corner]
--
-- "corner" as the last argument samples each chunk at its top-left corner (the
-- engine's territory-index convention) instead of its centre (the runtime
-- convention). The parity harness passes it, because it compares against the
-- engine's own spot selection on the engine's lattice.
--
-- One line per chunk: "cx cy owner width value" (owner "-" = no cone). The owner
-- is the cone whose FIELD is highest there, out to its full width -- not
-- owner_at, which answers the narrower question of whose terrain it is. An
-- optional gate file lists the cone centres that exist, one "x y" per line --
-- the standalone stand-in for the tile gate the control wiring injects.
-- Runs outside Factorio on purpose: the mirror must be verifiable without the
-- game.
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
local frequency = tonumber(arg[2]) or 2
local size = tonumber(arg[3]) or 1
local cx, cy = tonumber(arg[4]) or 0, tonumber(arg[5]) or 0
local radius = tonumber(arg[6]) or 8

local sample_corner = arg[8] == "corner"
local gate
if arg[7] then
  local allowed = {}
  for line in io.lines(arg[7]) do
    allowed[line] = true
  end
  gate = function(x, y) return allowed[x .. " " .. y] and true or false end
end

local volcanoes = cones.new_volcanoes(cones.new_context{
  seed = seed, volcanism_size = size, volcanism_frequency = frequency,
}, gate)

local out = {}
for dy = -radius, radius do
  for dx = -radius, radius do
    if dx * dx + dy * dy <= (radius + 0.5) * (radius + 0.5) then
      local owner, width, value
      -- The engine samples a territory index at each chunk's top-left CORNER, and
      -- this harness compares against the engine's own spot selection on that
      -- lattice -- so `corner` is a different QUESTION, asked at a different point,
      -- and it lives here rather than in the mirror. Without it the sample is at the
      -- chunk centre, which is what the runtime claim uses.
      local px, py = (cx + dx) * 32 + 16, (cy + dy) * 32 + 16
      if sample_corner then px, py = (cx + dx) * 32, (cy + dy) * 32 end
      -- One call for both: cone_value's first return is the owner and its second is
      -- the value at the DISPLACED point. Hand-rolling the value here computed the
      -- clean field, which showed up as a 5e-2 error and looked like a wobble bug.
      owner = volcanoes:field_owner_at(px, py)
      value = volcanoes:cone_value(px, py)
      width = owner and owner.width or 0
      out[#out + 1] = string.format("%d %d %s %.9f %.9f",
        cx + dx, cy + dy, owner and owner.id or "-", width, value)
    end
  end
end
io.write(table.concat(out, "\n"), "\n")
