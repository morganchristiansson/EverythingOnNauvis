#!/usr/bin/env python3
"""Scrap placement probe: create a fresh save with EoN (holmium replaced by
scrap via a settings.lua patch in a temporary COPY of the mod), generate the
spawn disc synchronously via on_init, and summarize eon-scrap-report.json.

Values under test (vanilla-Fulgora-transplant placement):
  - scrap spawns (nonzero count) at any frequency
  - 0 scrap on volcano/gleba/aquilo/water tiles
  - 0 scrap on top of other ores (nearest-ore distance >= 2)
  - coverage follows the vanilla frequency curve (~5% land at 100%,
    ~17% at 600%)

Usage: python3 tests/probe_scrap.py [seed] [map-gen-settings.json] [radius]
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
PROBE_NAME = "eon-probe-scrap"


def main():
    seed = sys.argv[1] if len(sys.argv) > 1 else "12345"
    settings = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != "-" else None
    radius = sys.argv[3] if len(sys.argv) > 3 else "1600"
    keep = os.environ.get("EON_KEEP_DIR")
    base_dir = tempfile.mkdtemp(prefix="eon-scrap.")
    mods_dir = os.path.join(base_dir, "mods")
    write_dir = os.path.join(base_dir, "write")
    os.makedirs(mods_dir)
    os.makedirs(write_dir)

    # Copy the mod (NOT symlink) so settings.lua can be patched in the copy:
    # the probe needs eon-holmium-ore=false (scrap active).
    mod_copy = os.path.join(mods_dir, MOD_NAME)
    shutil.copytree(MOD_DIR, mod_copy,
                    ignore=shutil.ignore_patterns(".git", "tests", "versions", "screenshots"))
    _settings = os.path.join(mod_copy, "settings.lua")
    with open(_settings) as f:
        content = f.read()
    if "default_value = true" in content:
        content = content.replace("default_value = true", "default_value = false")
        with open(_settings, "w") as f:
            f.write(content)

    shutil.copytree(os.path.join(MOD_DIR, "tests", PROBE_NAME),
                    os.path.join(mods_dir, PROBE_NAME))
    _ctl = os.path.join(mods_dir, PROBE_NAME, "control.lua")
    with open(_ctl) as f:
        _src = f.read()
    with open(_ctl, "w") as f:
        f.write(_src.replace("local RADIUS = 1600", f"local RADIUS = {radius}", 1))
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
           "--mod-directory", mods_dir, "--map-gen-seed", seed]
    if settings:
        cmd += ["--map-gen-settings", os.path.join(MOD_DIR, settings)]
    r = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=900)
    if r.returncode != 0:
        print(r.stdout[-2000:])
        print(r.stderr[-2000:])
        sys.exit("create failed")

    # Strip script.dat so on_init fires on load (see AGENTS.md).
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
    report = os.path.join(write_dir, "script-output", "eon-scrap-report.json")
    started = os.path.join(write_dir, "script-output", "eon-scrap-started.txt")
    if not os.path.exists(started):
        print(r.stdout[-3000:])
        print(r.stderr[-3000:])
        sys.exit("on_init never fired (script.dat not stripped?)")
    if not os.path.exists(report):
        print(r.stdout[-3000:])
        print(r.stderr[-3000:])
        sys.exit("no report written")
    d = json.load(open(report))
    print(f"seed={d['seed']} radius={d['radius']}")
    print(f"scrap entities={d['scrap_entities']}  (richness total={d['scrap_total_richness']})")
    print(f"scrap tile histogram: {d['scrap_tile_hist']}  (land entities={d['scrap_on_land_entities']})")
    print(f"nearest-other-ore dist: p50={d['scrap_nearest_ore_dist_p50']} "
          f"p90={d['scrap_nearest_ore_dist_p90']} max={d['scrap_nearest_ore_dist_max']}")
    print(f"dist buckets: {d['scrap_nearest_ore_buckets']}")
    print(f"land samples={d['land_samples']} water={d['water_samples']} "
          f"other-biomes={d['other_biome_samples']}")
    print(f"approx scrap coverage of land = {d['scrap_coverage_pct_approx']}%")
    print(f"64px cells={d['scrap_64px_cells']} cell size p50/p90/max = "
          f"{d['scrap_cell_size_p50']}/{d['scrap_cell_size_p90']}/{d['scrap_cell_size_max']}")
    print("resources:", d["all_resources"])
    if keep:
        print(f"(keeping run dir: {base_dir})")
    else:
        shutil.rmtree(base_dir, ignore_errors=True)


if __name__ == "__main__":
    main()