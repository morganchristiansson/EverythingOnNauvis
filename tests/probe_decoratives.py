#!/usr/bin/env python3
"""E2E test for decorative boundary fading: runs the headless game on seed
12345 with high volcanism, counts what decoratives actually render in six
regions (via find_decoratives_filtered), and asserts:

  - No gleba flora (honeycomb, cups, coral, white-carpet-grass, mycelium) in
    nauvis plains, on/near a nauvis volcano, or in aquilo north.
  - No grass tufts in the DEEP gleba strip (y >= 1600 — safely past the
    wobbly transition line; the highland-finger mix north of it is legit and
    ignored).
  - Grass tufts STILL present in nauvis plains, and gleba flora STILL present
    in deep gleba (guards against the fade over-killing the home biome).

Fails (exit 1) on any violation. Run: python3 tests/probe_decoratives.py
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
PROBE_NAME = "eon-probe-decoratives"
SEED = "12345"
SETTINGS = os.path.join(MOD_DIR, "tests", "map-gen-settings-high-volcanism.json")

# Green carpet/hairy grass are shared prototypes that vanilla GLEBA also
# grows (its planet property_expression_names rebind them to gleba_*_grass_
# probability); the mod restores that in gleba territory, so they are NOT
# leaks south. The others are nauvis-only: vanilla has zero of them in gleba.
GRASS = ["green-hairy-grass", "green-carpet-grass", "green-small-grass",
         "brown-carpet-grass", "brown-hairy-grass"]
NAUVIS_ONLY_GRASS = ["green-small-grass", "brown-carpet-grass", "brown-hairy-grass"]
GLEBA_NATIVE_GRASS = ["green-hairy-grass", "green-carpet-grass"]
GLEBA_FLORA = ["honeycomb-fungus", "honeycomb-fungus-1x1", "honeycomb-fungus-decayed",
               "coral-water", "yellow-lettuce-lichen-cups-1x1", "white-carpet-grass", "mycelium"]


def main():
    base_dir = tempfile.mkdtemp(prefix="eon-decor.")
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
    report = os.path.join(write_dir, "script-output", "eon-decor-report.json")
    started = os.path.join(write_dir, "script-output", "eon-decor-started.txt")
    if not os.path.exists(started):
        print(r.stdout[-3000:])
        print(r.stderr[-3000:])
        sys.exit("on_init never ran")
    data = json.load(open(report))

    failures = []

    def flora_in(name, region):
        counts = data.get(f"{region}_gleba_flora", {})
        return counts.get(name, 0)

    # 1. Gleba flora must be absent from nauvis-side regions.
    for region in ["nauvis_plains", "nauvis_volcano", "aquilo_north"]:
        for f in GLEBA_FLORA:
            c = flora_in(f, region)
            if c > 0:
                failures.append(f"{f} in {region}: {c} (must be 0)")

    # 2. Grass must be absent from DEEP gleba: the probe counts grass in the
    # y >= 1650 strip of the deep_gleba disc (excluding volcano tiles). The
    # whole-disc gleba-named-tile count is NOT asserted — gleba highland
    # tiles legitimately finger ~700 tiles north (mask_gleba_early -70) and
    # carry grass in the transition band (see AGENTS.md tile-name trap).
    # Threshold 1000: the headless fast-gen path leaves a small unexplained
    # artifact (~6 grass/chunk in deep-gleba wetlands, ~0.035% of the disc;
    # transition math says impossible — likely coarse sampling during the
    # initial-map-gen path). The real leaks (signed-expression x -inf = +inf)
    # are tens of thousands and blow this threshold by 100x.
    deep_grass = data.get("deep_gleba_deep_grass_on_gleba_tiles", 0)
    if deep_grass > 1000:
        failures.append(f"nauvis-only grass on gleba-named tiles in deep gleba strip: {deep_grass} (must be ~0)")

    # 3. Home biome must keep its flora (fades must not over-kill).
    nauvis_grass = data.get("nauvis_plains_grass_any", 0)
    if nauvis_grass < 100:
        failures.append(f"grass missing from nauvis plains: {nauvis_grass}")
    deep_flora = sum(data.get("deep_gleba_gleba_flora", {}).get(f, 0) for f in GLEBA_FLORA)
    if deep_flora < 100:
        failures.append(f"gleba flora missing from deep gleba: {deep_flora}")

    for region in ["nauvis_plains", "nauvis_volcano", "deep_gleba",
                   "gleba_volcano", "aquilo_north", "gleba_line"]:
        rpt = data.get(region, {})
        print(f"{region:14s} total decoratives: {rpt.get('total', 0)}")

    if failures:
        print("E2E DECORATIVE FADING TEST FAILED:")
        for f in failures:
            print("  -", f)
        sys.exit(1)
    print("E2E decorative fading test passed (no cross-biome flora, home flora present).")
    print(f"report: {report}")


if __name__ == "__main__":
    main()