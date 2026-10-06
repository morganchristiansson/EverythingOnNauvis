#!/usr/bin/env python3
"""Ask a RUNNING factorio server what its solar system looks like.

For the eon-restore-space-locations feature: which destinations exist, whether
they are planets or space-locations, and the space-connection graph.

Usage: python3 tests/rcon_solarsystem.py [--port 27500] [--password eon]

Note the two-attempt dance per command: a fresh rcon session's first `/c`
bounces on the "Using Lua console commands will disable achievements" gate and
the client would otherwise report an empty response (the repo's standard
empty-response gotcha).
"""
import argparse
import textwrap

from rcon.source import Client

CMDS = [
    ("planets (only landable worlds)",
     "local n={} for _,p in pairs(game.planets) do n[#n+1]=p.name end "
     'rcon.print("PLANETS="..table.concat(n,","))'),
    ("space-location prototypes",
     "local n={} for _,l in pairs(prototypes.space_location) do n[#n+1]=l.name end "
     'rcon.print("LOCATIONS="..table.concat(n,","))'),
    ("space-connection graph",
     "local n={} for _,c in pairs(prototypes.space_connection) do "
     'n[#n+1]=c.name.."="..c.from.name..">"..c.to.name end '
     'rcon.print("CONNECTIONS="..table.concat(n,","))'),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=27500)
    ap.add_argument("--password", default="eon")
    args = ap.parse_args()

    with Client("127.0.0.1", args.port, passwd=args.password, timeout=30) as client:
        for label, lua in CMDS:
            response = client.run("/c " + lua)
            gated = response.strip() in (
                "",
                "Using Lua console commands will disable achievements. "
                "Please repeat the command to proceed.",
            )
            if gated:
                response = client.run("/c " + lua)
            print(f"{label}\n  {response.strip() or '(empty)'}")


if __name__ == "__main__":
    main()