#!/usr/bin/env python3
"""Vanilla baseline for the gleba south comparison: creates a base+space-age
only save with a forced gleba seed and counts cliffs/tile-groups at the EoN
south box. Manual dev tool."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MOD_DIR = os.environ.get("MOD_DIR",
                         os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROBE_NAME = "eon-probe-baseline"
MOD_NAME = "EverythingOnNauvis-morganc"
SEED = os.environ.get("EON_PROBE_SEED", "12345")


def main():
    base_dir = tempfile.mkdtemp(prefix="eon-base.")
    mods_dir = os.path.join(base_dir, "mods")
    write_dir = os.path.join(base_dir, "write")
    os.makedirs(mods_dir)
    os.makedirs(write_dir)
    shutil.copytree(os.path.join(MOD_DIR, "tests", PROBE_NAME),
                    os.path.join(mods_dir, PROBE_NAME))
    mods = [
        {"name": "base", "enabled": True},
        {"name": "elevated-rails", "enabled": True},
        {"name": "quality", "enabled": True},
        {"name": "space-age", "enabled": True},
        {"name": PROBE_NAME, "enabled": True},
    ]
    # EON=1 -> the merged mod; GLEBA=1 -> vanilla gleba map-gen on nauvis
    if os.environ.get("EON"):
        mods.insert(4, {"name": MOD_NAME, "enabled": True})
        os.symlink(MOD_DIR, os.path.join(mods_dir, MOD_NAME))
    elif os.environ.get("GLEBA"):
        mods.insert(4, {"name": "eon-probe-glebanauvis", "enabled": True})
        shutil.copytree(os.path.join(MOD_DIR, "tests", "eon-probe-glebanauvis"),
                        os.path.join(mods_dir, "eon-probe-glebanauvis"))
    with open(os.path.join(mods_dir, "mod-list.json"), "w") as f:
        json.dump({"mods": mods}, f)
    config = os.path.join(base_dir, "config.ini")
    with open(config, "w") as f:
        f.write(f"[path]\nread-data=/factorio/data\nwrite-data={write_dir}\n")
    env = {**os.environ, "HOME": base_dir}
    settings = os.path.join(base_dir, "mgs.json")
    save = os.path.join(base_dir, "probe.zip")
    base_settings = {"gleba": {"seed": int(SEED)}}
    if os.environ.get("EON_LOW_VOLCANISM"):
        low = json.load(open(os.path.join(MOD_DIR, "tests", "map-gen-settings-no-volcanism.json")))
        ac = dict(base_settings.get("autoplace_controls") or {})
        ac.update(low.get("autoplace_controls") or {})
        base_settings["autoplace_controls"] = ac
        for k, v in low.items():
            if k != "autoplace_controls" and k != "_comment":
                base_settings[k] = v
    with open(settings, "w") as f:
        json.dump(base_settings, f)
    cmd = [FACTORIO_BIN, "--create", save, "--config", config,
           "--mod-directory", mods_dir, "--map-gen-seed", SEED, "--map-gen-settings", settings]
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
    report = os.path.join(write_dir, "script-output", "eon-baseline-report.json")
    started = os.path.join(write_dir, "script-output", "eon-base-started.txt")
    if not os.path.exists(started):
        print(r.stdout[-3000:])
        print(r.stderr[-3000:])
        sys.exit("on_init never ran")
    data = json.load(open(report))
    g = data.get("gleba", {})
    print("=== cliffs =", json.dumps(g.get("cliffs")))
    print("=== tiles by band:")
    for b, v in sorted((g.get("bands") or {}).items()):
        n = sum(v.values())
        print("   ", b, {k: round(100 * val / n, 1) for k, val in v.items()})
    print("=== decoratives total:", g.get("decor_total"))
    print("    decor by biome & band (counts, top 8 names per band):")
    for b, v in sorted((g.get("decor_bands") or {}).items()):
        top = sorted((g.get("decor_top_band") or {}).get(b, {}).items(), key=lambda kv: -kv[1])[:8]
        print("   ", b, v, "top:", dict(top))
    print("=== trees:", json.dumps(g.get("trees")))
    print("    tree classes by band:", json.dumps(g.get("tree_bands")))
    print(f"report: {report}")


if __name__ == "__main__":
    main()