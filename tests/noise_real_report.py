#!/usr/bin/env python3
"""The noise-program complexity report for the REAL surface, on the reset path.

The API docs say the engine prints its per-program complexity report "after
creating a surface or CHANGING MapGenSettings" -- and changing MapGenSettings is
exactly what a map reset does (`reset.lua:change_seed`). So the report is
reachable in a running game:

    /c local s = game.surfaces[1] local m = s.map_gen_settings m.seed = m.seed + 1
       s.map_gen_settings = m

and under --verbose the log then carries

    Entity noise program processed 13255 expressions (5833 unique) and has 4565
    operations and 470 registers; estimated complexity: 47405.

**This is not the same program as a map preview's.** Measured, same mod, same
seed: the preview reports Entity 3349 unique / 33732 complexity, the real
surface 5833 / 47405 -- the real Entity program is 74% larger, because the
preview surface never carries the planet's autoplace settings. Anything
optimised against the preview is optimising the wrong program.

Cost: one headless server start per side (~8 s) and then one rcon call per
measurement, so this is the fast loop for expression work.

Usage:
    python3 tests/noise_real_report.py --baseline     # mod and vanilla
    python3 tests/noise_real_report.py --seed 999
    python3 tests/noise_real_report.py --json out.json
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MOD_NAME = "EverythingOnNauvis-morganc"
BASE_MODS = ["base", "elevated-rails", "quality", "space-age"]
SETTINGS = os.path.join(REPO, "tests", "map-gen-settings-user.json")

REPORT_RE = re.compile(
    r'(?P<program>\w+) noise program processed (?P<processed>\d+) expressions '
    r'\((?P<unique>\d+) unique\) and has (?P<operations>\d+) operations and '
    r'(?P<registers>\d+) registers; estimated complexity: (?P<complexity>\d+)')

BUMP_SEED = ("local s = game.surfaces[1] local m = s.map_gen_settings "
             "m.seed = m.seed + 1 s.map_gen_settings = m "
             "rcon.print('recompiled ' .. s.map_gen_settings.seed)")


def run_lua(port, password, lua):
    sys.path.insert(0, os.path.join(REPO, "tests"))
    from rcon_probe import run_lua as _run
    return _run("127.0.0.1", port, password, lua)


def measure(mods, seed=12345, port=27019, game_port=29019, password="eon",
            settings=SETTINGS, keep=False, probe=None, probe_src=None):
    """One headless server, one rcon seed bump, the engine's own report."""
    run = tempfile.mkdtemp(prefix="eon-real-report.")
    mods_dir = os.path.join(run, "mods")
    write_dir = os.path.join(run, "write")
    os.makedirs(mods_dir)
    os.makedirs(write_dir)
    if probe:
        import shutil as _sh
        _sh.copytree(os.path.join(REPO, "tests", probe), os.path.join(mods_dir, probe))
        control = os.path.join(mods_dir, probe, "data-final-fixes.lua")
        with open(control) as f:
            source = f.read()
        marker = 'local ABLATION = "none"'
        assert marker in source, "the ablation template lost its ABLATION line"
        with open(control, "w") as f:
            f.write(source.replace(marker, f'local ABLATION = "{probe_src}"'))
    for name in mods:
        if name == MOD_NAME:
            os.symlink(REPO, os.path.join(mods_dir, name))
        else:
            source = os.path.join("/factorio/mods", name)
            if os.path.isdir(source):
                os.symlink(source, os.path.join(mods_dir, name))
    # NOTE: no mod-list.json gamesmanship. Factorio enables every mod it FINDS in
    # the mod directory, so a baseline is a mod list without the mod.
    config = os.path.join(run, "config.ini")
    with open(config, "w") as f:
        f.write(f"[path]\nread-data=/factorio/data\nwrite-data={write_dir}\n")
    save = os.path.join(run, "live.zip")
    subprocess.run([FACTORIO_BIN, "--create", save, "--config", config,
                    "--mod-directory", mods_dir, "--map-gen-seed", str(seed),
                    "--map-gen-settings", settings],
                   env={**os.environ, "HOME": run}, check=True, capture_output=True,
                   timeout=900)
    # strip script.dat so on_init fires (AGENTS.md)
    tmp = save + ".t"
    import zipfile
    with zipfile.ZipFile(save) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for name in zin.namelist():
            if name != "script.dat":
                zout.writestr(name, zin.read(name))
    os.replace(tmp, save)

    log_path = os.path.join(run, "server.log")
    with open(log_path, "w") as log:
        server = subprocess.Popen(
            [FACTORIO_BIN, "--start-server", save, "--config", config,
             "--mod-directory", mods_dir, f"--port={game_port}",
             f"--rcon-port={port}", f"--rcon-password={password}", "--verbose"],
            env={**os.environ, "HOME": run}, stdout=log, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            try:
                run_lua(port, password, "rcon.print('up')")
                break
            except Exception:
                time.sleep(1)
        else:
            raise SystemExit("the server never answered rcon")
        before = read_report(log_path)
        run_lua(port, password, BUMP_SEED)
        deadline = time.monotonic() + 60
        report = {}
        while time.monotonic() < deadline:
            report = read_report(log_path)
            if report != before:
                break
            time.sleep(0.5)
        if not report:
            raise SystemExit("the engine printed no report after changing MapGenSettings")
        return {"mods": mods, "programs": report}
    finally:
        server.terminate()
        try:
            server.wait(timeout=30)
        except subprocess.TimeoutExpired:
            server.kill()
        if not keep:
            shutil.rmtree(run, ignore_errors=True)
        else:
            print(f"kept {run}")


def read_report(log_path):
    if not os.path.exists(log_path):
        return {}
    report = {}
    for line in open(log_path, errors="replace"):
        match = REPORT_RE.search(line)
        if match:
            entry = {k: (v if k == "program" else int(v))
                     for k, v in match.groupdict().items()}
            report[entry["program"]] = entry
    return report


def total(report):
    return sum(entry["complexity"] for entry in report.values())


def print_side(label, report, baseline=None):
    print(f"{label}:")
    for program, entry in sorted(report.items()):
        line = (f"  {program:<10} processed={entry['processed']:<6} unique={entry['unique']:<6}"
                f" operations={entry['operations']:<5} registers={entry['registers']:<4}"
                f" complexity={entry['complexity']}")
        if baseline and program in baseline:
            was = baseline[program]["complexity"]
            line += f"   (vanilla {was}, {entry['complexity'] / max(1, was):.2f}x)"
        print(line)
    print(f"  total complexity {total(report)}"
          + (f" vs vanilla {total(baseline)}" if baseline else ""))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", action="store_true", help="also measure without the mod")
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--settings", default=SETTINGS)
    parser.add_argument("--json")
    parser.add_argument("--probe", help="a dev probe mod to load (e.g. eon-probe-ablation)")
    parser.add_argument("--ablation", help="the ablation to select in that probe")
    args = parser.parse_args()

    with_mod = measure(BASE_MODS + [MOD_NAME], args.seed, settings=args.settings,
                       probe=args.probe, probe_src=args.ablation)
    if args.baseline:
        vanilla = measure(BASE_MODS, args.seed, port=27020, game_port=29020,
                          settings=args.settings)
        print_side("with mod", with_mod["programs"], vanilla["programs"])
        print()
        print_side("vanilla", vanilla["programs"])
    else:
        print_side("with mod", with_mod["programs"])
    if args.json:
        payload = {"with_mod": with_mod["programs"]}
        if args.baseline:
            payload["vanilla"] = vanilla["programs"]
        with open(args.json, "w") as f:
            json.dump(payload, f, indent=2, sort_keys=True)
        print(f"\nwrote {args.json}")


if __name__ == "__main__":
    main()
