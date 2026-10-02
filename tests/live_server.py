#!/usr/bin/env python3
"""Run a real Factorio server in the BACKGROUND, with rcon, and keep it alive.

Why this exists: the end-to-end probe drives a server to completion and kills it,
which is the right shape for a gate but the wrong shape for debugging -- every
question ("what does the builder think of this chunk?", "what happens if I reveal
this one?") costs a full 20-50 s run and a log-file hunt. With a server that stays
up, the same questions are one rcon call each, in a second, against the real game.

The probe pattern is the opposite on purpose: this is an INTERACTIVE tool, and the
gate (`probe_runtime_territory.py`) is what runs unattended.

  # start a server on the default test map, seed 12345, rcon on 27016
  python3 tests/live_server.py start

  # poke it
  python3 tests/rcon_probe.py --port 27016
  python3 tests/rcon_coverage.py --port 27016 --at=-744.7,-1029.0

  # read what the mod said
  python3 tests/live_server.py log

  # stop it
  python3 tests/live_server.py stop
"""
from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FACTORIO = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
RUN = Path(os.environ.get("EON_LIVE_DIR", "/tmp/eon-live"))
PORT = int(os.environ.get("EON_LIVE_PORT", "27016"))
# The GAME port has to be distinct per instance too, or the second server refuses
# to start with "Host address is already in use".
GAME_PORT = int(os.environ.get("EON_LIVE_GAME_PORT", str(PORT + 1000)))
PASSWORD = os.environ.get("EON_LIVE_PASSWORD", "eon")
PID_FILE = RUN / "server.pid"
MODS = ["base", "elevated-rails", "quality", "space-age", "EverythingOnNauvis-morganc"]
# Extra mods to load beside the mod above, so a compatibility question about
# somebody else's mod is one env var away (e.g. EON_LIVE_EXTRA=behemoth-enemies
# _0.0.8.zip). Each entry is symlinked into the run's mod directory.
EXTRA = [n for n in os.environ.get("EON_LIVE_EXTRA", "").split(",") if n]


def mod_list() -> list[dict]:
    return [{"name": name, "enabled": True} for name in MODS]


def prepare(settings: str, seed: str) -> None:
    if RUN.exists():
        shutil.rmtree(RUN, ignore_errors=True)
    mods = RUN / "mods"
    write = RUN / "write"
    mods.mkdir(parents=True)
    write.mkdir(parents=True)
    os.symlink(ROOT, mods / "EverythingOnNauvis-morganc")
    for name in EXTRA:
        name = name.split("_")[0]
        source = next((p for p in sorted(Path("/factorio/mods").glob(name + "*"))
                       if not p.is_dir() and p.exists()), None)
        if source is None:
            source = ROOT / "tests" / name  # a dev probe mod in this repo
        os.symlink(source, mods / source.name)  # the .zip name: Factorio only scans those
        MODS.append(name)
    (mods / "mod-list.json").write_text(json.dumps({"mods": mod_list()}, indent=2))
    (RUN / "config.ini").write_text(
        f"[path]\nread-data=/factorio/data\nwrite-data={write}\n")
    save = RUN / "live.zip"
    subprocess.run(
        [FACTORIO, "--create", str(save), "--config", str(RUN / "config.ini"),
         "--mod-directory", str(mods), "--map-gen-seed", seed,
         "--map-gen-settings", settings],
        env={**os.environ, "HOME": str(RUN)}, check=True, capture_output=True, timeout=900)
    # A save created with --create ships a script.dat that marks storage as
    # initialised, so on_init never fires on load (see AGENTS.md).
    stripped = save.with_suffix(".tmp.zip")
    import zipfile
    with zipfile.ZipFile(save) as source, zipfile.ZipFile(stripped, "w",
                                                         zipfile.ZIP_DEFLATED) as target:
        for name in source.namelist():
            if name != "script.dat":
                target.writestr(name, source.read(name))
    stripped.replace(save)


def start(settings: str, seed: str) -> None:
    prepare(settings, seed)
    save = RUN / "live.zip"
    log = (RUN / "server.log").open("w")
    process = subprocess.Popen(
        [FACTORIO, "--start-server", str(save), "--config", str(RUN / "config.ini"),
         "--mod-directory", str(RUN / "mods"),
         f"--port={GAME_PORT}",
         f"--rcon-port={PORT}", f"--rcon-password={PASSWORD}"],
        env={**os.environ, "HOME": str(RUN)}, stdout=log, stderr=subprocess.STDOUT,
        start_new_session=True)
    PID_FILE.write_text(str(process.pid))
    # Wait for rcon to answer rather than sleeping a fixed amount.
    sys.path.insert(0, str(ROOT / "tests"))
    from rcon_probe import run_lua
    for _ in range(120):
        if process.poll() is not None:
            print("the server exited while starting up:")
            print(tail_log(30))
            raise SystemExit(1)
        try:
            run_lua("127.0.0.1", PORT, PASSWORD, "rcon.print('[eon] live')")
            print(f"server up: pid {process.pid}, rcon 127.0.0.1:{PORT} (password {PASSWORD})")
            print(f"  state dir {RUN}")
            print(f"  ask it:   python3 tests/rcon_probe.py --port {PORT} --password {PASSWORD}")
            return
        except Exception:
            time.sleep(1)
    print("rcon did not come up:")
    print(tail_log(30))
    raise SystemExit(1)


def stop() -> None:
    if not PID_FILE.exists():
        print("no server recorded")
        return
    pid = int(PID_FILE.read_text())
    try:
        os.killpg(os.getpgid(pid), signal.SIGTERM)
    except ProcessLookupError:
        pass
    PID_FILE.unlink(missing_ok=True)
    print(f"stopped pid {pid}")


def tail_log(lines: int) -> str:
    path = RUN / "server.log"
    if not path.exists():
        return "(no log)"
    return "".join(path.read_text(errors="replace").splitlines(keepends=True)[-lines:])


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else "start"
    settings = sys.argv[2] if len(sys.argv) > 2 else str(ROOT / "tests/map-gen-settings-user.json")
    seed = os.environ.get("EON_LIVE_SEED", "12345")
    if command == "start":
        start(settings, seed)
    elif command == "stop":
        stop()
    elif command == "log":
        print(tail_log(int(os.environ.get("EON_LIVE_TAIL", "60"))))
    elif command == "restart":
        stop()
        time.sleep(2)
        start(settings, seed)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
