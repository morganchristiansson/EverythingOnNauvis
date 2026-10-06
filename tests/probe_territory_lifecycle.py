#!/usr/bin/env python3
"""Does a territory outlive its demolisher? Engine-fact probe.

Starts a headless server running tests/eon-probe-territory-lifecycle (with the
EoN mod NOT loaded, so the questions are about the engine), waits for the
probe's REPORT-COMPLETE sentinel, terminates, prints the report.

Usage: python3 tests/probe_territory_lifecycle.py
"""
import json, os, shutil, subprocess, tempfile, threading
from pathlib import Path

FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MOD_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROBE_NAME = "eon-probe-territory-lifecycle"
SENTINEL = "[eon-probe-territory-lifecycle] REPORT-COMPLETE"

base = tempfile.mkdtemp(prefix="eon-probe-lifecycle.")
mods_dir = os.path.join(base, "mods")
write_dir = os.path.join(base, "write")
os.makedirs(mods_dir); os.makedirs(write_dir)
shutil.copytree(os.path.join(MOD_DIR, "tests", PROBE_NAME),
                os.path.join(mods_dir, PROBE_NAME))
with open(os.path.join(mods_dir, "mod-list.json"), "w") as f:
    json.dump({"mods": [
        {"name": "base", "enabled": True},
        {"name": "space-age", "enabled": True},
        {"name": PROBE_NAME, "enabled": True},
    ]}, f)
config = os.path.join(base, "config.ini")
with open(config, "w") as f:
    f.write(f"[path]\nread-data=/factorio/data\nwrite-data={write_dir}\n")
settings_json = os.path.join(base, "server-settings.json")
with open("/factorio/data/server-settings.example.json") as f:
    server_settings = json.load(f)
server_settings["auto_pause"] = False
with open(settings_json, "w") as f:
    json.dump(server_settings, f)

report_path = os.path.join(write_dir, "script-output", PROBE_NAME, "report.json")
server = subprocess.Popen(
    [FACTORIO_BIN, "--start-server-load-scenario", f"{PROBE_NAME}/probe",
     "--config", config, "--mod-directory", mods_dir, "--port", "0",
     "--map-gen-seed", "1", "--map-gen-settings",
     os.path.join(MOD_DIR, "tests", "map-gen-settings-user.json"),
     "--server-settings", settings_json],
    env={**os.environ, "HOME": base},
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
done = threading.Event()
captured = []
def reader():
    for line in server.stdout:
        captured.append(line)
        if SENTINEL in line:
            done.set()
pump = threading.Thread(target=reader, daemon=True)
pump.start()
ok = done.wait(timeout=300)
if server.poll() is None:
    server.terminate()
    try: server.wait(timeout=30)
    except subprocess.TimeoutExpired: server.kill()
pump.join(timeout=10)
out = "".join(captured)
if not ok:
    print("no sentinel; server output tail:")
    print(out[-2000:])
    raise SystemExit(1)
report = json.load(open(report_path))
print(json.dumps(report, indent=2))
for line in out.splitlines():
    if "Error while running event" in line:
        print("ERROR:", line)
        break