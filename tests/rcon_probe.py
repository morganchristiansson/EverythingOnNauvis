#!/usr/bin/env python3
"""Ask a RUNNING Factorio, over rcon, what the runtime volcano territories are
doing -- the instant version of tests/probe_runtime_territory.py.

The probe needs a fresh 20 s headless process; a playtest game is already up and
is the state you actually want to look at. Nothing here is restarted: the game
answers about its own mod code, save, startup settings and generated chunks, so
this separates the failure modes the headless probe cannot:

  setting=...        which branch the data stage and the builder agreed on
  cones_decided=...  how many cones the builder has ever decided (storage)
  territories=...     how many create_territory calls actually landed
  window ...         generated vs volcanic-corner vs in-a-territory chunk counts

Everything the Lua side needs is wrapped in pcall and reported through
`rcon.print`, because a Lua error over rcon comes back as an EMPTY response --
without pcall the probe would report "no data" for what is really a crash.

Usage (on the host running the game, or here with host networking):
  python3 tests/rcon_probe.py
  python3 tests/rcon_probe.py --port 27015 --password 12345 --radius 32
  python3 tests/rcon_probe.py --centre 0,0 --radius 64
"""
from __future__ import annotations

import argparse
import sys

try:
    from rcon.source import Client
except ImportError:  # pragma: no cover
    sys.exit("this probe needs the 'rcon' package (apt install python3-rcon, "
             "or pip install rcon) -- it is listed in the Dockerfile")

PROBE = """
local out = {}
local function say(...) local p = {} for i = 1, select('#', ...) do
  p[#p + 1] = tostring((select(i, ...))) end out[#out + 1] = table.concat(p, ' ') end
local function try(label, fn)
  local ok, value = pcall(fn)
  say('[eon] ' .. label .. ' = ' .. (ok and tostring(value) or ('ERROR: ' .. tostring(value))))
  return ok, value
end

try('version', function() return game.product_version end)
try('surfaces', function()
  local names = {} for _, s in ipairs(game.surfaces) do names[#names + 1] = s.name end
  return table.concat(names, ',') end)
try('setting', function()
  local s = settings.startup['eon-volcano-territory']
  return s and s.value or 'MISSING' end)
try('players', function() return #game.players end)

local s = game.surfaces['nauvis']
if not s then say('[eon] no nauvis surface') else
  try('territories', function() return #s.get_territories() end)
  try('territory_sizes', function()
    local sizes = {} for _, t in ipairs(s.get_territories()) do
      sizes[#sizes + 1] = #t.chunk_list end
    table.sort(sizes) return table.concat(sizes, ',') end)
  try('storage_keys', function()
    local keys = {} for k in pairs(storage) do keys[#keys + 1] = k end
    table.sort(keys) return table.concat(keys, ',') end)
  try('cones_decided', function()
    local st = storage['eon_volcano_territory_runtime']
    return st and st.created and table_size(st.created) or -1 end)
  try('demolishers_placed', function()
    local n = 0
    for _, e in pairs(s.find_entities_filtered{ type = 'unit', force = 'enemy' }) do
      if e.unit_nickname == 'small-demolisher' or e.unit_nickname == 'medium-demolisher'
        or e.unit_nickname == 'big-demolisher' then n = n + 1 end
    end return n end)

  local R = %(radius)d
  local c = %(centre)s
  try('window', function()
    local gen, vol, terr, vol_terr, err = 0, 0, 0, 0, 0
    for dy = -R, R do for dx = -R, R do
      local cx, cy = c[1] + dx, c[2] + dy
      local ok, generated = pcall(function() return s.is_chunk_generated{ x = cx, y = cy } end)
      if not ok then err = err + 1
      elseif generated then
        gen = gen + 1
        local _, t = pcall(function() return s.get_tile(cx * 32, cy * 32) end)
        local isvol = t and string.sub(t.name, 1, 8) == 'volcanic'
        local _, tr = pcall(function() return s.get_territory_for_chunk{ x = cx, y = cy } end)
        if tr then terr = terr + 1 end
        if isvol then vol = vol + 1; if tr then vol_terr = vol_terr + 1 end end
      end
    end end
    return ('R=%%d generated=%%d volcanic_corners=%%d in_any_territory=%%d '
          .. 'volcanic_in_territory=%%d api_errors=%%d')
      :format(R, gen, vol, terr, vol_terr, err) end)
end
for _, line in ipairs(out) do rcon.print(line) end
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=27015)
    parser.add_argument("--password", default="12345")
    parser.add_argument("--radius", type=int, default=32,
                        help="window radius in CHUNKS around the centre")
    parser.add_argument("--centre", default="player",
                        help="'player' (follows player 1) or a chunk position 'x,y'")
    args = parser.parse_args()

    if args.centre == "player":
        centre = ("(function() if game.players[1] then local p = game.players[1].position "
                  "return { math.floor(p.x / 32), math.floor(p.y / 32) } end "
                  "return { 0, 0 } end)()")
    else:
        x, _, y = args.centre.partition(",")
        centre = "{ %s, %s }" % (x.strip() or 0, y.strip() or 0)

    lua = PROBE % {"radius": args.radius, "centre": centre}
    # The console has a line-length budget, so send the probe in one command; if
    # the shell ever complains, --radius is the only thing worth shrinking.
    client = Client(args.host, args.port, timeout=30)
    client.connect()
    if not client.login(args.password):
        sys.exit("rcon login failed (wrong --password?)")
    reply = client.run("/c " + " ".join(lua.split()))
    client.close()
    print(reply or "(empty rcon response: the probe crashed before its first rcon.print)")
    return 0 if "[eon]" in (reply or "") else 1


if __name__ == "__main__":
    raise SystemExit(main())


# ---------------------------------------------------------------------------
# The coverage map (tests/rcon_coverage.py). One character per chunk.
#
# Sent as MANY small commands rather than one big one: a long single /c payload
# intermittently comes back as an EMPTY rcon response (verified repeatedly on
# 2.0.77 -- no error text, just nothing, while every fragment of the same script
# answers fine), and an empty response is indistinguishable from a crashed probe.
# Small commands have never failed, and one row each also keeps the output
# readable if the game is busy.
# ---------------------------------------------------------------------------

MAP_LEGEND = """  #  claimed, and the chunk's centre is volcano ground      (what you want)
  o  claimed, but the centre is not volcano                (spill onto the rim)
  .  volcano ground, but not claimed                      (a hole: unguarded)
  ,  neither (ordinary ground)                             ?  not generated yet"""


def lua_map_header(chunk_x: int, chunk_y: int, radius: int) -> str:
    return (
        "local cx, cy, R = %d, %d, %d\n"
        "rcon.print(string.format('[eon] coverage map: chunk %%d,%%d  radius %%d  "
        "(row label = chunk y, leftmost column = chunk %%d)', cx, cy, R, cx - R))\n"
        "rcon.print(string.format('[eon] centre is chunk %%d,%%d = gps %%.0f,%%.0f', cx, cy, cx * 32 + 16, cy * 32 + 16))"
        % (chunk_x, chunk_y, radius)
    )


def lua_map_row(chunk_x: int, row_y: int, radius: int) -> str:
    return (
        "local s = game.surfaces['nauvis'] local row = {}\n"
        "for dx = -%d, %d do\n"
        "  local cxx, cyy = %d + dx, %d\n"
        "  if s.is_chunk_generated{ x = cxx, y = cyy } then\n"
        "    local t = s.get_tile(cxx * 32 + 16, cyy * 32 + 16).name\n"
        "    local vol = (string.sub(t, 1, 8) == 'volcanic' or t == 'lava' or t == 'lava-hot')\n"
        "    local claimed = s.get_territory_for_chunk{ x = cxx, y = cyy } ~= nil\n"
        "    if claimed and vol then row[#row + 1] = '#'\n"
        "    elseif claimed then row[#row + 1] = 'o'\n"
        "    elseif vol then row[#row + 1] = '.'\n"
        "    else row[#row + 1] = ',' end\n"
        "  else row[#row + 1] = '?' end\n"
        "end\n"
        "rcon.print(string.format('[eon] %%5d %%s', %d, table.concat(row)))"
        % (radius, radius, chunk_x, row_y, row_y)
    )


def lua_map_totals(chunk_x: int, chunk_y: int, radius: int) -> str:
    return (
        "local s = game.surfaces['nauvis'] local good, spill, hole, plain, missing = 0, 0, 0, 0, 0\n"
        "for dy = -%d, %d do for dx = -%d, %d do\n"
        "  local cxx, cyy = %d + dx, %d + dy\n"
        "  if s.is_chunk_generated{ x = cxx, y = cyy } then\n"
        "    local t = s.get_tile(cxx * 32 + 16, cyy * 32 + 16).name\n"
        "    local vol = (string.sub(t, 1, 8) == 'volcanic' or t == 'lava' or t == 'lava-hot')\n"
        "    local claimed = s.get_territory_for_chunk{ x = cxx, y = cyy } ~= nil\n"
        "    if claimed and vol then good = good + 1 elseif claimed then spill = spill + 1\n"
        "    elseif vol then hole = hole + 1 else plain = plain + 1 end\n"
        "  else missing = missing + 1 end\n"
        "end end\n"
        "rcon.print(string.format('[eon] claimed+volcano=%%d  spill=%%d  HOLE=%%d  plain=%%d  ungenerated=%%d', good, spill, hole, plain, missing))"
        % (radius, radius, radius, radius, chunk_x, chunk_y)
    )


def lua_units() -> str:
    return (
        "local s = game.surfaces['nauvis']\n"
        "for _, t in ipairs(s.get_territories()) do\n"
        "  local units = t.get_segmented_units()\n"
        "  if #units > 0 then\n"
        "    local names = {}\n"
        "    for i, u in ipairs(units) do names[i] = u.prototype.name end\n"
        "    local chunks, bx, by = t.get_chunks(), 0, 0\n"
        "    for i, c in ipairs(chunks) do bx = bx + c.x; by = by + c.y end\n"
        "    rcon.print(string.format('[eon] territory %d chunks, centre chunk %.0f,%.0f -> %s',\n"
        "      #chunks, bx / #chunks, by / #chunks, table.concat(names, '+')))\n"
        "  end\n"
        "end"
    )


def run_lua(host: str, port: int, password: str, lua: str) -> str:
    client = Client(host, port, timeout=60)
    client.connect()
    if not client.login(password):
        raise SystemExit("rcon login failed")
    try:
        return client.run("/c " + " ".join(lua.split())) or ""
    finally:
        client.close()
