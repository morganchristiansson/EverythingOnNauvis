#!/usr/bin/env python3
"""Dev probe: does the mod claim volcanoes on a RUNTIME-CREATED, UNASSOCIATED
clone of the merged map?

The multiplayer reset scenario pre-generates the next map on a second surface
(created with game.create_surface from the read-back of nauvis's
map_gen_settings) while the planet still points at the old one, then swaps by
re-associating the planet and teleporting players. The mod must have claimed the
clone BEFORE it is ever associated -- a pre-generated chunk never re-fires
on_chunk_generated -- so its identity gate is the surface's OWN settings, never
the planet. This probe asserts exactly that, in a real headless game:

  * the clone was created (and therefore docs the create_surface recipe work);
  * the clone's planet is nil (still unassociated when claimed);
  * the clone carries the vulcanus_volcanism control (the merged map's fingerprint);
  * rendered chunk centres are volcanic ground (the clone is really the merged map);
  * the clone has territories, and every one has a demolisher (the mod claimed
    while unassociated, and guarded).

Usage: python3 tests/probe_clone_surface.py [settings.json]
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MOD_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD_NAME = "EverythingOnNauvis-morganc"
PROBE_NAME = "eon-probe-clone"


def main() -> int:
    argv = [a for a in sys.argv[1:] if not a.startswith("--")]
    settings = argv[0] if argv else os.path.join(MOD_DIR, "tests", "map-gen-settings-user.json")
    seed = "12345"
    for arg in sys.argv[1:]:
        if arg.startswith("--seed="):
            seed = arg.split("=", 1)[1]

    base_dir = tempfile.mkdtemp(prefix="eon-probe-clone.")
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
    config_path = os.path.join(base_dir, "config.ini")
    with open(config_path, "w") as f:
        f.write(f"[path]\nread-data=/factorio/data\nwrite-data={write_dir}\n")
    # auto_pause: false, or the empty server stops at updateTick(0) and on_nth_tick
    # never fires (measured; recorded in probe_runtime_territory.py).
    with open(os.path.join("/factorio/data", "server-settings.example.json")) as f:
        server_settings = json.load(f)
    server_settings["auto_pause"] = False
    settings_json = os.path.join(base_dir, "server-settings.json")
    with open(settings_json, "w") as f:
        json.dump(server_settings, f)
    env = {**os.environ, "HOME": base_dir}
    report_path = os.path.join(write_dir, "script-output", "eon-probe-clone", "report.json")
    server = subprocess.Popen(
        [FACTORIO_BIN, "--start-server-load-scenario", f"{PROBE_NAME}/clone",
         "--config", config_path, "--mod-directory", mods_dir, "--port", "0",
         "--map-gen-seed", seed, "--map-gen-settings", settings,
         "--server-settings", settings_json],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    SENTINEL = "[eon-probe-clone] REPORT-COMPLETE"
    captured = []
    done = threading.Event()

    def reader():
        for line in server.stdout:
            captured.append(line)
            if SENTINEL in line:
                done.set()

    pump = threading.Thread(target=reader, daemon=True)
    pump.start()
    timeout = float(os.environ.get("EON_SERVER_TIMEOUT", "300"))
    if not done.wait(timeout=timeout):
        print("timed out waiting for the probe sentinel")
        print("".join(captured)[-3000:])
        if server.poll() is None:
            server.terminate()
        return 1
    if server.poll() is None:
        server.terminate()
        try:
            server.wait(timeout=30)
        except subprocess.TimeoutExpired:
            server.kill()
    pump.join(timeout=10)
    output = "".join(captured)
    if "Error while running event" in output:
        print("event error in server output:")
        for line in output.splitlines():
            if "Error while running event" in line:
                print(" ", line)
        return 1
    if not os.path.exists(report_path):
        print("no report written; stream tail:")
        print(output[-3000:])
        return 1
    report = json.load(open(report_path))
    failures = []
    if not report.get("surface_created"):
        failures.append("clone was not created: " + str(report.get("create_error")))
    if report.get("clone_planet") != "nil":
        failures.append("clone is already associated with a planet: " + str(report.get("clone_planet")))
    if not report.get("control_present"):
        failures.append("clone lacks the vulcanus_volcanism control (not the merged map)")
    if report.get("volcanic_chunk_centres", 0) == 0:
        failures.append("no volcanic ground rendered on the clone")
    territories = report.get("territories") or []
    if not territories:
        failures.append("the mod claimed NOTHING on the unassociated clone")
    for t in territories:
        if t.get("units", 0) == 0:
            failures.append("a territory on the clone has no demolisher")
    print("probe report:")
    print(json.dumps(report, indent=1))
    if failures:
        print("FAIL:")
        for f in failures:
            print("  -", f)
        return 1
    print("CLONE SURFACE OK: %d territories (all guarded) on an unassociated clone, "
          "%d volcanic chunk centres, %d chunks generated"
          % (len(territories), report["volcanic_chunk_centres"], report["generated_chunks"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())