#!/usr/bin/env python3
"""Ground-truth tungsten check: create a save with EoN + verifier mod, run it
headless, and summarize the JSON report.

Usage: python3 tests/verify_tungsten.py [seed] [map-gen-settings.json]
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
VERIFY_NAME = "eon-verify-tungsten"


def main():
    seed = sys.argv[1] if len(sys.argv) > 1 else "12345"
    settings = sys.argv[2] if len(sys.argv) > 2 else None
    radius = sys.argv[3] if len(sys.argv) > 3 else "1600"
    base_dir = tempfile.mkdtemp(prefix="eon-verify.")
    mods_dir = os.path.join(base_dir, "mods")
    write_dir = os.path.join(base_dir, "write")
    os.makedirs(mods_dir)
    os.makedirs(write_dir)
    os.symlink(MOD_DIR, os.path.join(mods_dir, MOD_NAME))
    # Temp copy (not symlink) so the scan radius can be substituted per run.
    import shutil as _shutil
    _shutil.copytree(os.path.join(MOD_DIR, "tests", VERIFY_NAME),
                      os.path.join(mods_dir, VERIFY_NAME))
    _ctl = os.path.join(mods_dir, VERIFY_NAME, "control.lua")
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
    r = subprocess.run(
        [FACTORIO_BIN, "--benchmark", save, "--benchmark-ticks",
         str(max(12000, int((int(radius) / 1600) ** 2 * 60000))),
         "--benchmark-runs", "1", "--config", config,
         "--mod-directory", mods_dir],
        env=env, capture_output=True, text=True, timeout=3600)
    report = os.path.join(write_dir, "script-output", "eon-tungsten-report.json")
    if not os.path.exists(report):
        print(r.stdout[-3000:])
        print(r.stderr[-3000:])
        sys.exit("no report written (chunks not generated in time?)")
    d = json.load(open(report))
    print(f"seed={d['seed']} radius={d['radius']} ore_entities={d['ore_entities']}")
    print(f"volcanoes={d['volcano_count']} "
          f"with_patch_within_450={d['volcanoes_with_patch_within_450']}")
    print(f"patches={d['patch_count']} on_volcano_terrain={d['patches_on_volcano_terrain']} "
          f"fallback_beyond_600={d['fallback_patches_beyond_600']}")
    for v in sorted(d["volcanoes"], key=lambda v: v["nearest_patch"]):
        print(f"  volcano ({v['x']},{v['y']}) lava_samples={v['n']} "
              f"nearest_patch={v['nearest_patch']} "
              f"nearest_demo={v.get('nearest_demolisher')} "
              f"({v.get('nearest_demolisher_name')}) n_demo={v.get('demolisher_count')} "
              f"sizes={v.get('demolisher_sizes')} terrain_n={v['n']}")
    print(f"lava_samples={d.get('lava_samples')} unguarded_lava={d.get('unguarded_lava_samples')}")
    print(f"demos_off_terrain={d.get('demolishers_off_volcano_terrain')}")
    for t in (d.get("demolisher_tiles") or []):
        print(f"  demo {t['name']} at ({t['x']},{t['y']}) on {t['tile']}")
    print(f"demolishers={d.get('demolisher_count')} "
          f"volcanoes_with_demo={d.get('volcanoes_with_demolisher_within_600')} "
          f"min_terrain_dist_to_spawn={d.get('min_volcano_terrain_dist_to_spawn')}")
    on = [p for p in d["patches"] if p["on_volcano_terrain"]]
    off = [p for p in d["patches"] if not p["on_volcano_terrain"]]
    print(f"patches ON volcano terrain: {len(on)}:")
    for p in sorted(on, key=lambda p: -p["entities"]):
        print(f"  ({p['x']},{p['y']}) n={p['entities']} rich={p['richness']} "
              f"tile={p['center_tile']} dist_volc={p['dist_to_volcano']}")
    print(f"patches NOT on volcano terrain: {len(off)}:")
    for p in sorted(off, key=lambda p: -p["entities"])[:15]:
        print(f"  ({p['x']},{p['y']}) n={p['entities']} rich={p['richness']} "
              f"tile={p['center_tile']} dist_volc={p['dist_to_volcano']}")
    print(f"total richness on-terrain={sum(p['richness'] for p in on)} "
          f"off-terrain={sum(p['richness'] for p in off)}")
    from collections import Counter
    print("center tiles:", dict(Counter(p['center_tile'] for p in d['patches'])))
    print(f"calcite patches={d.get('calcite_patch_count')}")
    for name, s in (d.get("decor") or {}).items():
        print(f"  {name}: total={s.get('total')} n={s.get('sampled')} volc_p50={s.get('volcano_p50')} "
              f"p90={s.get('volcano_p90')} max={s.get('volcano_max')} "
              f"calc_p50={s.get('calcite_p50')} p90={s.get('calcite_p90')} "
              f"on_terr={s.get('on_volcano_terrain')} "
              f"tiles={s.get('tiles_volcanic')}/{s.get('tiles_snowice')}/{s.get('tiles_other')}")
    shutil.rmtree(base_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
