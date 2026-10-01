#!/usr/bin/env python3
"""Measure what a map reset pays: noise-program complexity + reveal-box time.

The Legendary Deathworld scenario rerolls the seed on every reset
(`reset.lua:change_seed` re-assigns `surface.map_gen_settings`), which makes the
engine recompile the whole noise program, and then force-generates a 39x39-chunk
box around spawn in batches. Both costs are measured here:

  * `tests/eon-probe-noise` re-assigns map_gen_settings in on_init (the same
    compile) and force-generates the same box, writing a report.json;
  * the engine's own per-program complexity report ("... processed N
    expressions (M unique) ... estimated complexity: C") is read from the log,
    which requires --verbose.

Usage:
    python3 tests/probe_noise_cost.py                     # EoN, repo settings
    python3 tests/probe_noise_cost.py --mods vanilla      # base+space-age only
    python3 tests/probe_noise_cost.py --settings tests/map-gen-settings-user.json
    python3 tests/probe_noise_cost.py --seed 999 --json /tmp/eon-noise.json

The run is a headless server, which never exits on its own: the probe writes
report.json as the last act of on_init, so the harness polls for that file and
stops the server (see AGENTS.md).
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import zipfile

FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MOD_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD_NAME = "EverythingOnNauvis-morganc"
PROBE_NAME = "eon-probe-noise"
DEFAULT_SETTINGS = os.path.join(MOD_DIR, "tests", "map-gen-settings-user.json")
SERVER_TIMEOUT = float(os.environ.get("EON_SERVER_TIMEOUT", "600"))

COMPLEXITY_RE = re.compile(
    r'(?P<program>\w+) noise program processed (?P<processed>\d+) expressions '
    r'\((?P<unique>\d+) unique\) and has (?P<operations>\d+) operations and '
    r'(?P<registers>\d+) registers; estimated complexity: (?P<complexity>\d+)')
COMPILE_TIME_RE = re.compile(r"MapGenSettings compilation took (?P<seconds>[\d.]+) seconds")

MOD_SETS = {
    "eon": ["base", "elevated-rails", "quality", "space-age", MOD_NAME],
    "vanilla": ["base", "elevated-rails", "quality", "space-age"],
    # Same data stage, no control.lua: separates the noise program's cost from
    # the runtime script cost (spot mirror) over the same box.
    "eon-data-only": ["base", "elevated-rails", "quality", "space-age", MOD_NAME],
}


def build_run_dir(mods, probe=True):
    base_dir = tempfile.mkdtemp(prefix="eon-probe-noise.")
    mods_dir = os.path.join(base_dir, "mods")
    write_dir = os.path.join(base_dir, "write")
    os.makedirs(mods_dir)
    os.makedirs(write_dir)
    for name in mods:
        if name == MOD_NAME:
            source = MOD_DIR
            if mods == MOD_SETS["eon-data-only"]:
                source = os.path.join(base_dir, "eon-data-only")
                shutil.copytree(MOD_DIR, source,
                                ignore=shutil.ignore_patterns(".git", "versions", "tools", "tests"))
                os.rename(os.path.join(source, "control.lua"),
                          os.path.join(source, "control.lua.disabled"))
            os.symlink(source, os.path.join(mods_dir, name))
        elif os.path.isdir(os.path.join("/factorio/mods", name)):
            # base/quality/space-age ship inside the read-data dir and need no
            # mod-directory entry; anything else has to be in the game folder.
            os.symlink(os.path.join("/factorio/mods", name), os.path.join(mods_dir, name))
    if probe:
        shutil.copytree(os.path.join(MOD_DIR, "tests", PROBE_NAME),
                        os.path.join(mods_dir, PROBE_NAME))
    with open(os.path.join(mods_dir, "mod-list.json"), "w") as f:
        json.dump({"mods": [{"name": n, "enabled": True} for n in mods + ([PROBE_NAME] if probe else [])]}, f)
    config = os.path.join(base_dir, "config.ini")
    with open(config, "w") as f:
        f.write(f"[path]\nread-data=/factorio/data\nwrite-data={write_dir}\n")
    return base_dir, mods_dir, write_dir, config


def stage_times(write_dir):
    """mtime_ns of each stage file the probe wrote, in write order."""
    out = os.path.join(write_dir, "script-output", PROBE_NAME)
    stages = {}
    for name in os.listdir(out):
        if name.endswith(".json"):
            stages[name[:-5]] = os.stat(os.path.join(out, name)).st_mtime_ns
    return stages


def strip_script_dat(save):
    """`--create` marks storage as initialised; on_init must fire on load."""
    tmp = save + ".t"
    with zipfile.ZipFile(save) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for name in zin.namelist():
            if name != "script.dat":
                zout.writestr(name, zin.read(name))
    os.replace(tmp, save)


def run_once(mods, settings, seed, log_lines, ablation=None, ablation_mod="eon-probe-ablation"):
    base_dir, mods_dir, write_dir, config = build_run_dir(mods, probe=True)
    if ablation:
        # A dev mod that neutralises one subsystem, so the KPI can be attributed
        # to it. The ABLATION line is rewritten rather than configured: a mod
        # setting cannot be forced headlessly.
        shutil.copytree(os.path.join(MOD_DIR, "tests", ablation_mod),
                        os.path.join(mods_dir, ablation_mod))
        control = os.path.join(mods_dir, ablation_mod, "data-final-fixes.lua")
        with open(control) as f:
            source = f.read()
        marker = 'local ABLATION = "none"'
        assert marker in source, "the ablation template lost its ABLATION line"
        with open(control, "w") as f:
            f.write(source.replace(marker, f'local ABLATION = "{ablation}"'))
    env = {**os.environ, "HOME": base_dir}
    save = os.path.join(base_dir, "probe.zip")
    created = subprocess.run(
        [FACTORIO_BIN, "--create", save, "--config", config, "--mod-directory", mods_dir,
         "--map-gen-seed", str(seed), "--map-gen-settings", settings],
        env=env, capture_output=True, text=True, timeout=900)
    if not os.path.exists(save):
        print("create failed", created.returncode)
        print(created.stdout[-2000:], created.stderr[-2000:])
        raise SystemExit(1)
    strip_script_dat(save)
    report_path = os.path.join(write_dir, "script-output", PROBE_NAME, "box.json")
    server = subprocess.Popen(
        [FACTORIO_BIN, "--start-server", save, "--config", config,
         "--mod-directory", mods_dir, "--port", "0", "--verbose"],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    deadline = time.monotonic() + SERVER_TIMEOUT
    while time.monotonic() < deadline and not os.path.exists(report_path):
        if server.poll() is not None:
            break
        time.sleep(0.25)
    running = server.poll() is None
    if running:
        server.terminate()
        try:
            server.wait(timeout=30)
        except subprocess.TimeoutExpired:
            server.kill()
    output = server.stdout.read()

    report = None
    if os.path.exists(report_path):
        with open(report_path) as f:
            report = json.load(f)
    else:
        print("no report.json; server output:", output[-3000:])
        raise SystemExit(1)

    stages = stage_times(write_dir)
    # The control stage has no clock, so durations come from the stage files'
    # mtimes (see tests/eon-probe-noise/control.lua).
    report["compile_seconds"] = ((stages["compiled"] - stages["started"]) / 1e9
                                 if "started" in stages else None)
    report["box_seconds"] = (stages["box"] - stages["compiled"]) / 1e9
    report["ms_per_chunk"] = 1000 * report["box_seconds"] / max(1, report["box_chunks_generated"])

    log_path = os.path.join(write_dir, "factorio-current.log")
    complexity, compile_seconds = [], []
    log_text = output  # a headless server logs Verbose lines to stdout, not the file
    if os.path.exists(log_path):
        log_text += open(log_path, errors="replace").read()
    for line in log_text.splitlines():
        match = COMPLEXITY_RE.search(line)
        if match:
            entry = {k: int(v) for k, v in match.groupdict().items()}
            # The last report per program is the one for the reset-time
            # compile; earlier ones are the initial surface creation.
            complexity = [c for c in complexity if c["program"] != entry["program"]]
            complexity.append(entry)
        match = COMPILE_TIME_RE.search(line)
        if match:
            compile_seconds.append(float(match.group("seconds")))
    result = {"mods": mods, "seed": seed, "settings": os.path.abspath(settings),
              "probe": report, "noise_programs": sorted(complexity, key=lambda c: c["program"]),
              "compile_seconds": compile_seconds}
    if log_lines:
        print("--- verbose engine lines")
        for line in log_text.splitlines():
            if COMPLEXITY_RE.search(line) or COMPILE_TIME_RE.search(line):
                print("   ", line.split("] ", 1)[-1].rstrip())
    shutil.rmtree(base_dir, ignore_errors=True) if not os.environ.get("EON_KEEP_DIR") else None
    return result


def print_report(result):
    probe = result["probe"]
    print(f"mods: {', '.join(result['mods'])}  seed: {result['seed']}")
    print(f"reveal box: {probe['radius_chunks'] * 2 + 1}x{probe['radius_chunks'] * 2 + 1} chunks"
          f" = {probe['box_chunks_generated']} generated in {probe['box_seconds']:.3f}s"
          f" ({probe['ms_per_chunk']:.2f} ms/chunk, {probe['box_passes']} force passes)")
    if probe.get("compile_seconds") is not None:
        print(f"  recompile {probe['compiled_surfaces']}: {probe['compile_seconds'] * 1000:.1f} ms")
    for seconds in result["compile_seconds"]:
        print(f"  engine MapGenSettings compilation: {seconds * 1000:.1f} ms")
    print("noise programs (engine report, last compile):")
    for entry in result["noise_programs"]:
        print(f"  {entry['program']:<10} processed={entry['processed']:<6} unique={entry['unique']:<6}"
              f" ops={entry['operations']:<5} regs={entry['registers']:<4}"
              f" complexity={entry['complexity']:<7}"
              f" dedup={entry['unique'] / entry['processed']:.2f}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mods", default="eon", choices=sorted(MOD_SETS))
    parser.add_argument("--settings", default=DEFAULT_SETTINGS)
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--repeat", type=int, default=1,
                        help="runs; the best (lowest) box time is reported, median kept")
    parser.add_argument("--log-lines", action="store_true", help="echo the verbose log lines")
    parser.add_argument("--json", help="write the full result here")
    parser.add_argument("--ablation", help="neutralise one subsystem (see tests/eon-probe-ablation)")
    parser.add_argument("--repeats-of-ablations", type=int, default=1,
                        help="unused; kept for symmetry with --repeat")
    args = parser.parse_args()

    results = [run_once(MOD_SETS[args.mods], args.settings, args.seed, args.log_lines,
                        args.ablation)
               for _ in range(args.repeat)]
    best = min(results, key=lambda r: r["probe"]["box_seconds"])
    for result in results:
        print_report(result)
    if len(results) > 1:
        print(f"best box time over {len(results)} runs: {best['probe']['box_seconds']:.3f}s"
              f" ({best['probe']['ms_per_chunk']:.2f} ms/chunk)")
    if args.json:
        with open(args.json, "w") as f:
            json.dump({"runs": results, "best": best}, f, indent=2)
        print(f"wrote {args.json}")


if __name__ == "__main__":
    main()
