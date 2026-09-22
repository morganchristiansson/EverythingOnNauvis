#!/usr/bin/env python3
"""Probe the translated Gleba starting area: run headless on a seed and summarize
what fruit soils/trees render around the start anchor (y ~= eon_gleba_start_y).
Manual dev tool. Set EON_PROBE_SEED to test other seeds.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MOD_DIR = os.environ.get("MOD_DIR",
                         os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MOD_NAME = "EverythingOnNauvis-morganc"
PROBE_NAME = "eon-probe-fruit"
SEED = os.environ.get("EON_PROBE_SEED", "12345")
SETTINGS = os.path.join(MOD_DIR, "tests", "map-gen-settings-high-volcanism.json")


def main():
    base_dir = tempfile.mkdtemp(prefix="eon-fruit.")
    mods_dir = os.path.join(base_dir, "mods")
    write_dir = os.path.join(base_dir, "write")
    os.makedirs(mods_dir)
    os.makedirs(write_dir)
    os.symlink(MOD_DIR, os.path.join(mods_dir, MOD_NAME))
    shutil.copytree(os.path.join(MOD_DIR, "tests", PROBE_NAME),
                    os.path.join(mods_dir, PROBE_NAME))
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
    save = os.path.join(base_dir, "probe.zip")
    cmd = [FACTORIO_BIN, "--create", save, "--config", config,
           "--mod-directory", mods_dir, "--map-gen-seed", SEED, "--map-gen-settings", SETTINGS]
    r = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=900)
    if r.returncode != 0:
        print(r.stdout[-2000:])
        print(r.stderr[-2000:])
        sys.exit("create failed")

    import zipfile
    tmp_save = save + ".stripped"
    with zipfile.ZipFile(save) as zin, zipfile.ZipFile(tmp_save, "w") as zout:
        for name in zin.namelist():
            if name != "script.dat":
                zout.writestr(name, zin.read(name))
    os.replace(tmp_save, save)

    r = subprocess.run(
        [FACTORIO_BIN, "--benchmark", save, "--benchmark-ticks", "60000",
         "--benchmark-runs", "1", "--config", config,
         "--mod-directory", mods_dir],
        env=env, capture_output=True, text=True, timeout=3600)
    report = os.path.join(write_dir, "script-output", "eon-fruit-report.json")
    started = os.path.join(write_dir, "script-output", "eon-fruit-started.txt")
    if not os.path.exists(started):
        print(r.stdout[-3000:])
        print(r.stderr[-3000:])
        sys.exit("on_init never ran")
    data = json.load(open(report))
    print("=== soil counts (sampled every 16 tiles over x -1056..1056, y 1040..2200)")
    print(json.dumps(data["soil_counts"], indent=1))
    print("northernmost soil sample:", json.dumps(data["soil_northernmost"]))
    cells = data.get("soil_sorted", [])
    from collections import Counter
    yk = Counter((c["x"] // 128, c["y"] // 128) for c in cells if c["n"] == "yumako")
    jl = Counter((c["x"] // 128, c["y"] // 128) for c in cells if c["n"] == "jelly")
    print("yumako soil sample buckets (128px):", sorted(yk.items()))
    print("jelly soil sample buckets (128px):", sorted(jl.items())[:40])
    ents = data["entities"]
    print("=== glowstone-like entity counts in box:", json.dumps({k: v for k, v in ents.items()}))
    trees = data.get("trees", [])
    print(f"=== fruit trees found: {len(trees)}")
    from collections import Counter
    c = Counter(t["n"] for t in trees)
    print("by type:", dict(c))
    tc = Counter(t["t"] for t in trees)
    print("by tile:", dict(tc))
    for t in trees[:20]:
        print("   ", t)
    if len(trees) > 20:
        print("    ... (showing first 20)")
    report_path = report
    print(f"report: {report_path}")


if __name__ == "__main__":
    main()