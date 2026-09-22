#!/usr/bin/env python3
"""Ground-truth calcite check: create a save with EoN + probe mod, generate the
spawn disc synchronously via on_init, and summarize the JSON report.

Usage: python3 tests/probe_calcite.py [seed] [map-gen-settings.json] [radius]
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
PROBE_NAME = "eon-probe-calcite"


def main():
    seed = sys.argv[1] if len(sys.argv) > 1 else "12345"
    settings = sys.argv[2] if len(sys.argv) > 2 else None
    radius = sys.argv[3] if len(sys.argv) > 3 else "1600"
    keep = os.environ.get("EON_KEEP_DIR")
    base_dir = tempfile.mkdtemp(prefix="eon-calcite.")
    mods_dir = os.path.join(base_dir, "mods")
    write_dir = os.path.join(base_dir, "write")
    os.makedirs(mods_dir)
    os.makedirs(write_dir)
    os.symlink(MOD_DIR, os.path.join(mods_dir, MOD_NAME))
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
        cmd += ["--map-gen-settings", settings]
    r = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=900)
    if r.returncode != 0:
        print(r.stdout[-2000:])
        print(r.stderr[-2000:])
        sys.exit("create failed")

    # The save ships a script.dat marking storage initialised, so on_init would
    # be skipped on load; copy all entries except it.
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
    report = os.path.join(write_dir, "script-output", "eon-calcite-report.json")
    started = os.path.join(write_dir, "script-output", "eon-calcite-started.txt")
    if not os.path.exists(started):
        print(r.stdout[-3000:])
        print(r.stderr[-3000:])
        sys.exit("on_init never fired (script.dat not stripped?)")
    if not os.path.exists(report):
        print(r.stdout[-3000:])
        print(r.stderr[-3000:])
        sys.exit("no report written (chunks not generated in time?)")
    d = json.load(open(report))
    print(f"seed={d['seed']} radius={d['radius']} entities={d['ore_entities']}")
    print(f"off_terrain_entities={d['off_terrain_entities']} ({d['off_terrain_tiles']})")
    for e in d['off_terrain_positions']:
        print(f"  off-terrain entity at ({e['x']},{e['y']}) on {e['t']}")
    print(f"patches={d['patch_count']} on_volc_terrain={d['patches_on_volcano_terrain']} "
          f"off_volc_terrain={d['patches_off_volcano_terrain']}")
    print(f"richness total={d['total_richness']} on_volc={d['rich_on_volcano']}")
    print(f"dist-to-volcano p25/p50/p75/p90 = "
          f"{d['dist_p25']}/{d['dist_p50']}/{d['dist_p75']}/{d['dist_p90']}")
    print(f"patches within 250px of a volcano={d['patches_near_volcano_250']} / "
          f"600px={d['patches_near_volcano_600']}")
    print(f"volcanoes={d['volcano_count']} ({d['volcano_terrain_samples']} samples, "
          f"{d['lava_samples']} lava)")
    print(f"volcanoes with patch within 450={d['volcanoes_with_patch_within_450']} / "
          f"250={d['volcanoes_with_patch_within_250']}")
    print(f"min volcano terrain dist to spawn={d['min_volcano_terrain_dist_to_spawn']} "
          f"min calcite dist to spawn={d['min_calcite_dist_to_spawn']}")
    print(f"stains-small sampled={d['stain_total']} dist-to-calcite p50/p90/max = "
          f"{d['stain_dist_p50']}/{d['stain_dist_p90']}/{d['stain_dist_max']}")
    for kind, a in d["acid"].items():
        if kind in ("all_resources", "demolishers"):
            continue
        amt = f" amount={a['total_amount']}" if "total_amount" in a else ""
        tiles = f" tiles={a.get('tiles')}" if 'tiles' in a else ""
        onoff = f" on_volcano={a.get('on_volcano', '-')}/off={a.get('off_volcano', '-')}"
        print(f"  {kind}: total={a['total']} {onoff} "
              f"core={a.get('core', '-')}/noncore={a.get('noncore', '-')}{amt}{tiles}")
    print(f"calcite<->geyser dist p50/p90 = {d.get('calcite_geyser_dist_p50')}/{d.get('calcite_geyser_dist_p90')} "
          f"patches within 30px of a geyser={d.get('calcite_close_to_geyser_30px')}")
    if 'all_resources' in d['acid']:
        print(f"  all resources: {dict(sorted(d['acid']['all_resources'].items(), key=lambda kv: -kv[1]))}")
    from collections import Counter
    print("patch center tiles:", dict(Counter(p["center_tile"] for p in d["patches"])))
    print("volcanoes:")
    for v in sorted(d["volcanoes"], key=lambda v: v["nearest_patch"]):
        bins = v.get('cliff_bins', [])
        nb = sum(bins)
        print(f"  ({v['x']},{v['y']}) samples={v['n']} lava={v['lava']} cliffs={nb} "
              f"bins={bins} geysers={v.get('geysers_near_450')}")
    print(f"demolishers: {dict(sorted(d['acid'].get('demolishers', {}).items()))}")
    for v in sorted(d["volcanoes"], key=lambda v: -v["n"]):
        dms = "+".join(f"{k}:{c}" for k, c in sorted(v.get('demolishers_600', {}).items(), key=lambda kv: -kv[1]))
        print(f"  volc ({v['x']},{v['y']}) samples={v['n']} lava={v['lava']} demos=[{dms or 'none'}] nearest={v.get('nearest_demolisher')}")
    print("largest patches:")
    for p in sorted(d["patches"], key=lambda p: -p["richness"])[:12]:
        print(f"  ({p['x']},{p['y']}) n={p['entities']} rich={p['richness']} "
              f"tile={p['center_tile']} dist_volc={p['dist_to_volcano']}")
    if keep:
        print(f"kept dir: {base_dir}")
    else:
        shutil.rmtree(base_dir, ignore_errors=True)


if __name__ == "__main__":
    main()