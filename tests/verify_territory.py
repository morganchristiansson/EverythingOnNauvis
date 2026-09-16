#!/usr/bin/env python3
"""Ground-truth demolisher-territory check: create a save with EoN + verifier
mod, run it headless, and summarize the JSON report (territory polygons vs
volcano tiles around the volcano near (-80, -831) on seed 12345).

Usage: python3 tests/verify_territory.py [map-gen-settings.json]
"""
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MOD_DIR = os.environ.get("MOD_DIR",
                         os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MOD_NAME = "EverythingOnNauvis-morganc"
VERIFY_NAME = "eon-verify-territory"


def main():
    seed = sys.argv[1] if len(sys.argv) > 1 else "12345"
    settings = sys.argv[2] if len(sys.argv) > 2 else None
    base_dir = tempfile.mkdtemp(prefix="eon-verify.")
    mods_dir = os.path.join(base_dir, "mods")
    write_dir = os.path.join(base_dir, "write")
    os.makedirs(mods_dir)
    os.makedirs(write_dir)
    os.symlink(MOD_DIR, os.path.join(mods_dir, MOD_NAME))
    shutil.copytree(os.path.join(MOD_DIR, "tests", VERIFY_NAME),
                    os.path.join(mods_dir, VERIFY_NAME))
    with open(os.path.join(mods_dir, "mod-list.json"), "w") as f:
        json.dump({"mods": [
            {"name": "base", "enabled": True},
            {"name": "elevated-rails", "enabled": True},
            {"name": "quality", "enabled": True},
            {"name": "space-age", "enabled": True},
            {"name": MOD_NAME, "enabled": True},
            {"name": VERIFY_NAME, "enabled": True},
        ]}, f)
    config = os.path.join(base_dir, "config.ini")
    with open(config, "w") as f:
        f.write(f"[path]\nread-data=/factorio/data\nwrite-data={write_dir}\n")
    env = {**os.environ, "HOME": base_dir}
    save = os.path.join(base_dir, "verify.zip")
    cmd = [FACTORIO_BIN, "--create", save, "--config", config,
           "--mod-directory", mods_dir, "--map-gen-seed", str(seed)]
    if settings:
        cmd += ["--map-gen-settings", settings]
    r = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=900)
    if r.returncode != 0:
        print(r.stdout[-2000:])
        print(r.stderr[-2000:])
        sys.exit("create failed")

    # --create does not run control scripts: with no control script ever run,
    # the save ships a script.dat that marks storage as initialised, so on_init
    # would not fire on load. Strip it so the engine re-runs on_init.
    import zipfile

    tmp_save = save + ".stripped"
    with zipfile.ZipFile(save) as zin, zipfile.ZipFile(tmp_save, "w") as zout:
        for name in zin.namelist():
            if name != "script.dat":
                zout.writestr(name, zin.read(name))
    os.replace(tmp_save, save)

    # --benchmark advances ticks fast; the verifier force-generates its disc
    # synchronously and writes the report, then the benchmark runs out the
    # remaining ticks (120k updates take ~1 minute wall time).
    r = subprocess.run(
        [FACTORIO_BIN, "--benchmark", save, "--benchmark-ticks", "120000",
         "--benchmark-runs", "1", "--config", config,
         "--mod-directory", mods_dir],
        env=env, capture_output=True, text=True, timeout=3600)
    report = os.path.join(write_dir, "script-output", "eon-territory-report.json")
    started = os.path.join(write_dir, "script-output", "eon-verify-started.txt")
    if not os.path.exists(started):
        print(r.stdout[-3000:])
        print(r.stderr[-3000:])
        sys.exit("on_init never fired")
    if not os.path.exists(report):
        print(r.stdout[-3000:])
        print(r.stderr[-3000:])
        sys.exit("no report written (chunks not generated in time?)")
    d = json.load(open(report))
    summarize(d)
    if os.environ.get("EON_KEEP_DIR"):
        print(f"report dir kept: {base_dir}")
    else:
        shutil.rmtree(base_dir, ignore_errors=True)


def summarize(d):
    chunks = d["chunks"]
    center = d["center_chunk"]
    print(f"seed={d['seed']} chunks={d['chunk_count']} territories={d['territory_count']}")
    print(f"demolishers={len(d.get('demolishers', []))}")

    # volcano chunk mask: any 4px sample is volcano terrain
    volc = {f"{c['x']},{c['y']}" for c in chunks if any(int(ch) % 2 == 1 for m in c["s"].split("/") for ch in m)}
    terr = {f"{c['x']},{c['y']}" for c in chunks if c["t"] > 0}
    leak = sorted(terr - volc)
    print(f"chunks with volcano tiles={len(volc)}  with territory={len(terr)}")
    print(f"territory-only chunks (leak, no volcano tile): {len(leak)}")
    for k in leak[:15]:
        print("   leak chunk", k)

    # Remaining gaps are the corner quantization: sorted by how much of the
    # chunk is volcano so rim/water-pocket chunks separate from real misses.
    def vfrac(c):
        n = sum(int(ch) % 2 == 1 for m in c["s"].split("/") for ch in m)
        return n / 64.0

    gap = [c for c in chunks if f"{c['x']},{c['y']}" in (volc - terr)]
    print(f"volcano-only chunks (gap, no territory): {len(gap)}")
    for c in sorted(gap, key=lambda c: -vfrac(c))[:20]:
        print(f"   gap ({c['x']},{c['y']}) volcano={vfrac(c):.2f} "
              f"corners=[{', '.join(p[:10] for p in c['p'])}]")
    fully = [c for c in gap if vfrac(c) == 1.0]
    if fully:
        print(f"!! {len(fully)} gap chunks are 100% volcano:",
              [(c['x'], c['y']) for c in fully])
    print(f"demolisher sizes: {len(d.get('demolishers', []))} total")
    from collections import Counter
    print("  " + dict(Counter(x["name"] for x in d.get("demolishers", []))).__repr__())


if __name__ == "__main__":
    main()