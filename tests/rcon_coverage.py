#!/usr/bin/env python3
"""Territory coverage at a point, as a MAP you can look at.

The runtime claim is geometric (a cone's core disc), so "is that right?" is a
visual question: does the disc cover the whole volcano, does it stop short, does
it spill onto the rim. This prints one character per chunk around a gps point --
the same view F4 gives, as text, with the terrain underneath:

    #  claimed, and the chunk's centre is volcano ground   (the good case)
    o  claimed, but the centre is NOT volcano              (spill: rim, beach)
    .  volcano ground, but NOT claimed                     (a hole: unguarded)
    ,  neither (ordinary ground)                           ?  not generated yet

A good territory is a solid blob of # with a thin o fringe and no . holes.

Nothing here restarts or reloads anything: it asks the running game over rcon.

Usage (on the host running the game, or here with host networking):
  python3 tests/rcon_coverage.py --at=-744.7,-1029.0
  python3 tests/rcon_coverage.py --at=238,-334 --radius 24 --units
"""
from __future__ import annotations

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rcon_probe import (  # noqa: E402
    MAP_LEGEND, lua_map_header, lua_map_row, lua_map_totals, lua_units, run_lua,
)


def clean(reply: str) -> str:
    return "\n".join(re.sub(r"^.*\[eon\] ?", "", line) for line in reply.splitlines())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=27015)
    parser.add_argument("--password", default="12345")
    parser.add_argument("--at", required=True,
                        help='gps position "x,y" in TILES, e.g. --at=-744.7,-1029.0')
    parser.add_argument("--radius", type=int, default=20, help="window radius in CHUNKS")
    parser.add_argument("--units", action="store_true", help="also list territories and units")
    args = parser.parse_args()

    x, _, y = args.at.partition(",")
    chunk_x, chunk_y = int(float(x or 0) // 32), int(float(y or 0) // 32)

    def ask(lua: str) -> str:
        return clean(run_lua(args.host, args.port, args.password, lua))

    print(ask(lua_map_header(chunk_x, chunk_y, args.radius)))
    # Top row first: north at the top, the way the map is drawn.
    for row_y in range(chunk_y + args.radius, chunk_y - args.radius - 1, -1):
        print(ask(lua_map_row(chunk_x, row_y, args.radius)))
    print(ask(lua_map_totals(chunk_x, chunk_y, args.radius)))
    print(MAP_LEGEND)
    if args.units:
        print(ask(lua_units()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
