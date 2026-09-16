#!/usr/bin/env python3
"""Territory geometry prober: override the demolisher territory index expression
with a lattice probe, generate a disc, and report which chunks are claimed.

Usage: python3 tests/probe_geometry.py <probe-name> [expression]
Probes:
  all     = 1                                            (every chunk claimable)
  centers = (x-32*floor(x/32)==16)*(y-32*floor(y/32)==16)
  corners = (x-32*floor(x/32)==0)*(y-32*floor(y/32)==0)
  centerlines = (x-32*floor(x/32)==16)+(y-32*floor(y/32)==16)
  raw expression can also be passed as argv[2]
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MOD_DIR = os.environ.get("MOD_DIR",
                         os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MOD_NAME = "EverythingOnNauvis-morganc"
PROBE_NAME = "eon-probe-geometry"

PROBES = {
    # Every probe gates on a lattice/mask and emits a unique per-chunk id
    # (1 + abs(x) + 1000000*abs(y)) instead of a constant, otherwise one giant territory
    # polygon forms and map gen blows up to ~5 GB headless.
    "all": "1 + abs(x) + 1000000*abs(y)",
    "centers": "if((x - 32*floor(x/32) == 16) * (y - 32*floor(y/32) == 16), 1 + abs(x) + 1000000*abs(y), -inf)",
    "centerhalf": "if((x - 32*floor(x/32) == 8) * (y - 32*floor(y/32) == 8), 1 + abs(x) + 1000000*abs(y), -inf)",
    "xcenter": "if(x - 32*floor(x/32) == 16, 1 + abs(x) + 1000000*abs(y), -inf)",
    "ycenter": "if(y - 32*floor(y/32) == 16, 1 + abs(x) + 1000000*abs(y), -inf)",
    "corners": "if((x - 32*floor(x/32) == 0) * (y - 32*floor(y/32) == 0), 1 + abs(x) + 1000000*abs(y), -inf)",
    "xcorner": "if(x - 32*floor(x/32) == 0, 1 + abs(x) + 1000000*abs(y), -inf)",
    "ycorner": "if(y - 32*floor(y/32) == 0, 1 + abs(x) + 1000000*abs(y), -inf)",
    # x-lines every 64px: claims chunks whose sample point is on even-x grid lines
    "x64lines": "if((x - 64*floor(x/64) == 0) * (y - 32*floor(y/32) == 0), 1 + abs(x) + 1000000*abs(y), -inf)",
    # checkerboard of world corners: claims chunks with an even-sum corner
    "checker": "if((x - 32*floor(x/32) == 0) * (y - 32*floor(y/32) == 0) * (floor(x/32) + floor(y/32) - 2*floor((floor(x/32) + floor(y/32))/2) == 0), 1 + abs(x) + 1000000*abs(y), -inf)",
}


def main():
    probe = sys.argv[1] if len(sys.argv) > 1 else "all"
    expr = sys.argv[2] if len(sys.argv) > 2 else PROBES[probe]
    base_dir = tempfile.mkdtemp(prefix="eon-probe.")
    mods_dir = os.path.join(base_dir, "mods")
    write_dir = os.path.join(base_dir, "write")
    os.makedirs(mods_dir)
    os.makedirs(write_dir)
    os.symlink(MOD_DIR, os.path.join(mods_dir, MOD_NAME))
    shutil.copytree(os.path.join(MOD_DIR, "tests", PROBE_NAME),
                    os.path.join(mods_dir, PROBE_NAME))
    with open(os.path.join(mods_dir, PROBE_NAME, "data-final-fixes.lua"), "w") as f:
        f.write(
            f'data.raw["noise-expression"]["demolisher_territory_expression"].expression = "{expr}"\n'
            'data.raw.planet["nauvis"].map_gen_settings.territory_settings.minimum_territory_size = 0\n'
        )
    with open(os.path.join(mods_dir, "mod-list.json"), "w") as f:
        json.dump({"mods": [
            {"name": "base", "enabled": True},
            {"name": "elevated-rails", "enabled": True},
            {"name": "quality", "enabled": True},
            {"name": "space-age", "enabled": True},
            {"name": MOD_NAME, "enabled": True},
            {"name": PROBE_NAME, "enabled": True},
        ]}, f)
    config = os.path.join(base_dir, "config.ini")
    with open(config, "w") as f:
        f.write(f"[path]\nread-data=/factorio/data\nwrite-data={write_dir}\n")
    env = {**os.environ, "HOME": base_dir}
    save = os.path.join(base_dir, "verify.zip")
    subprocess.run(
        [FACTORIO_BIN, "--create", save, "--config", config,
         "--mod-directory", mods_dir, "--map-gen-seed", "12345",
         "--map-gen-settings", os.path.join(MOD_DIR, "tests", "map-gen-settings-high-volcanism.json")],
        env=env, capture_output=True, text=True, timeout=900)
    tmp = save + ".t"
    with zipfile.ZipFile(save) as zin, zipfile.ZipFile(tmp, "w") as zout:
        for name in zin.namelist():
            if name != "script.dat":
                zout.writestr(name, zin.read(name))
    os.replace(tmp, save)
    subprocess.run(
        [FACTORIO_BIN, "--benchmark", save, "--benchmark-ticks", "12000",
         "--benchmark-runs", "1", "--config", config, "--mod-directory", mods_dir],
        env=env, capture_output=True, text=True, timeout=900)
    report = os.path.join(write_dir, "script-output", "eon-probe-report.json")
    if not os.path.exists(report):
        sys.exit("no probe report")
    d = json.load(open(report))
    chunks = d["chunks"]
    n, claimed = d["total"], d["claimed"]
    print(f"probe {probe:12s} expr={expr}")
    print(f"  chunks={n} claimed={claimed} ({100.0*claimed/n:.0f}%) missing={d.get('missing')}")
    # row pattern of claimed chunks across the disc (dy rows, '#' claimed)
    R = 20
    ccx, ccy = -3, -26
    lines = []
    for dy in range(R, -R - 1, -1):
        row = []
        for dx in range(-R, R + 1):
            if dx * dx + dy * dy <= (R + 0.5) * (R + 0.5):
                hit = any(c["cx"] == ccx + dx and c["cy"] == ccy + dy and c["t"] == 1 for c in chunks)
                row.append("#" if hit else ".")
            else:
                row.append(" ")
        lines.append("".join(row))
    print("\n".join(lines))
    if not os.environ.get("EON_KEEP_DIR"):
        shutil.rmtree(base_dir, ignore_errors=True)


if __name__ == "__main__":
    main()