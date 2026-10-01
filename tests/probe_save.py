#!/usr/bin/env python3
"""Probe an EXISTING save (legdeath.zip) for stored map_gen_settings + cliff state.

Strips script.dat so on_init fires, symlinks the real local mods, and loads the
save headless with a dev probe mod that dumps:

  - stored surface map_gen_settings (cliff_settings, nauvis_cliff control,
    property_expression_names, entity/tile settings lists)
  - cliff entity counts by name (cliff, cliff-vulcanus, cliff-gleba, crater-cliff)
  - a forced fresh-chunk patch next to a found volcano + what it produced

Usage: python3 tests/probe_save.py [save.zip]
"""
import json
import os
import subprocess
import sys
import time
import zipfile

FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
SAVE = sys.argv[1] if len(sys.argv) > 1 else "/factorio/saves/legdeath.zip"
PROBE_NAME = "eon-probe-save"
REAL_MODS = "/factorio/mods"
BASE = "/workspace/tests/.saveprobe"


def strip_script_dat(src, dst):
    """Copy save zip without script.dat so on_init fires on load."""
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            if item.filename.endswith("chip.dat") or item.filename.endswith("script.dat"):
                continue
            zout.writestr(item, zin.read(item.filename))


def stage_mods(mods_dir, write_dir):
    """Symlink real mods + probe and write mod-list.json. Returns (mods_dir, write_dir)."""
    os.makedirs(mods_dir)
    os.makedirs(write_dir)
    for entry in os.listdir(REAL_MODS):
        if entry.endswith(".tmp") or entry == "mod-list.json":
            continue
        os.symlink(os.path.join(REAL_MODS, entry), os.path.join(mods_dir, entry))
    for name in {"EverythingOnNauvis-morganc", "EverythingOnNauvis-Patches"}:
        d = os.path.join(mods_dir, name)
        z = os.path.join(mods_dir, name + "_0.1.11.zip")
        if os.path.islink(d) and os.path.exists(z):
            os.unlink(d)
    modlist = json.load(open(os.path.join(REAL_MODS, "mod-list.json")))
    mods = [m for m in modlist["mods"] if m.get("enabled")]
    mods.append({"name": PROBE_NAME, "enabled": True})
    with open(os.path.join(mods_dir, "mod-list.json"), "w") as f:
        json.dump({"mods": mods}, f)
    probe_src = os.path.join(os.path.dirname(os.path.abspath(__file__)), PROBE_NAME)
    os.symlink(probe_src, os.path.join(mods_dir, PROBE_NAME))


def main():
    fresh = "--fresh" in sys.argv
    base_dir = os.path.join(BASE, time.strftime("%H%M%S"))
    os.makedirs(base_dir)
    mods_dir = os.path.join(base_dir, "mods")
    write_dir = os.path.join(base_dir, "write")
    stage_mods(mods_dir, write_dir)

    with open(os.path.join(base_dir, "config.ini"), "w") as f:
        f.write(f"[path]\nread-data=/factorio/data\nwrite-data={write_dir}\n")

    env = {**os.environ, "HOME": base_dir}
    if fresh:
        # brand-new world from the planet prototype (no scenario)
        fresh_zip = os.path.join(base_dir, "fresh.zip")
        subprocess.run([FACTORIO_BIN, "--create", fresh_zip,
                        "--mod-directory", mods_dir,
                        "--config", os.path.join(base_dir, "config.ini"),
                        "--disable-audio"], env=env, timeout=180,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        save_to_run = fresh_zip
    else:
        save_to_run = os.path.join(base_dir, "probe.zip")
        strip_script_dat(SAVE, save_to_run)

    cmd = [
        FACTORIO_BIN, "--start-server", save_to_run,
        "--mod-directory", mods_dir,
        "--config", os.path.join(base_dir, "config.ini"),
        "--disable-audio",
    ]
    print("staged in", base_dir)
    print("running:", " ".join(cmd))
    try:
        subprocess.run(cmd, env=env, timeout=420, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        print("timed out (expected for --start-server, on_init work done by then)")

    log = os.path.join(write_dir, "factorio-current.log")
    if os.path.exists(log):
        print("\n===== log tail =====")
        with open(log) as f:
            lines = f.readlines()
        print("".join(lines[-120:]))
    else:
        print("no log at", log)

    out_dir = os.path.join(write_dir, "script-output", "eon-probe-save")
    if os.path.isdir(out_dir):
        for fn in sorted(os.listdir(out_dir)):
            print(f"\n===== {fn} =====")
            print(open(os.path.join(out_dir, fn)).read())
    print("\ndone, staged in", base_dir)


if __name__ == "__main__":
    main()