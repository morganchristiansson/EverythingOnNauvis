#!/usr/bin/env python3
"""Run the control-stage Lua capability prober (tests/eon-probe-lua).

Creates a save, strips script.dat so on_init fires, loads it headless and prints
the capability report. This decides which 32-bit arithmetic primitives the
runtime spot-noise mirror may use inside Factorio's Lua.

Usage: python3 tests/probe_lua_capabilities.py [--keep]
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MOD_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD_NAME = "EverythingOnNauvis-morganc"
PROBE_NAME = "eon-probe-lua"


def main():
    base_dir = tempfile.mkdtemp(prefix="eon-probe-lua.")
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
    created = subprocess.run(
        [FACTORIO_BIN, "--create", save, "--config", config,
         "--mod-directory", mods_dir, "--map-gen-seed", "12345",
         "--map-gen-settings", os.path.join(MOD_DIR, "tests", "map-gen-settings-user.json")],
        env=env, capture_output=True, text=True, timeout=900)
    if not os.path.exists(save):
        print("create failed", created.returncode)
        print(created.stdout[-3000:], created.stderr[-3000:])
        log = os.path.join(write_dir, "factorio-current.log")
        if os.path.exists(log):
            print(open(log).read()[-3000:])
        raise SystemExit(1)
    tmp = save + ".t"
    with zipfile.ZipFile(save) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for name in zin.namelist():
            if name != "script.dat":
                zout.writestr(name, zin.read(name))
    os.replace(tmp, save)
    try:
        subprocess.run(
            [FACTORIO_BIN, "--start-server", save, "--config", config, "--mod-directory", mods_dir,
             "--port", "0"],
            env=env, capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        pass  # --start-server never exits; on_init already did the work
    out_dir = os.path.join(write_dir, "script-output", PROBE_NAME)
    if not os.path.isdir(out_dir):
        print("no probe output in", out_dir)

        log = os.path.join(write_dir, "factorio-current.log")
        if os.path.exists(log):
            print(open(log).read()[-3000:])
        raise SystemExit(1)
    for name in sorted(os.listdir(out_dir)):
        print(f"===== {name} =====")
        print(open(os.path.join(out_dir, name)).read())
    print("staged in", base_dir)
    if not os.environ.get("EON_KEEP_DIR"):
        shutil.rmtree(base_dir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
