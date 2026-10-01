#!/usr/bin/env python3
"""Price every subsystem of the mod's noise expressions, using the engine's own
complexity report.

One ablation = one map preview = ~2 s, so the whole survey costs less than a
single run of the reveal benchmark. The metric is the engine's
("Entity noise program ... estimated complexity: C"), which is what Factorio's
cost model uses; the reveal box time is then measured only for the ablations
that look like a real win, because it only moves in whole percent.

The ablation lives in `tests/eon-probe-ablation/data-final-fixes.lua`, which
this driver rewrites (the `local ABLATION = "..."` line) before every run: a
mod setting cannot be forced headlessly, so the code is injected instead.

Usage:
    python3 tests/noise_ablation.py                 # full survey (complexity)
    python3 tests/noise_ablation.py --only volcano masks
    python3 tests/noise_ablation.py --box volcano   # + wall-clock box time
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MOD_NAME = "EverythingOnNauvis-morganc"
PROBE = "eon-probe-ablation"
FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
BASE_MODS = ["base", "elevated-rails", "quality", "space-age"]
SETTINGS = os.path.join(REPO, "tests", "map-gen-settings-deathworld.json")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from noise_engine_report import REPORT_RE  # noqa: E402

# "Map preview generation time: 5.572 seconds" -- the engine's own wall clock
# for evaluating the program over the preview area. Unlike the complexity number
# this is a real time, and unlike the reveal box it is pure expression
# evaluation: a preview places no decoratives, entities or ores.
TIME_RE = re.compile(r"Map preview generation time: (?P<seconds>[0-9.]+) seconds")
COMPILE_RE = re.compile(r"MapGenSettings compilation took (?P<seconds>[0-9.]+) seconds")

ABLATIONS = ["none", "masks", "volcano", "biome-blend", "decorative-probability",
             "extra-resources", "detail-noise", "octaves", "aquilo-detail", "detail-warp",
             "blended-fields", "cliff-fields", "gleba-region", "aquilo-region", "fades",
             "aquilo-macro", "aquilo-persistance", "gleba-elevation", "gleba-moisture",
             "gleba-blend",
             "gleba-shared", "volcano-rim",
             "volcano+masks", "all"]


def with_probe(ablation):
    """A copy of the mod directory plus the ablation probe, set to `ablation`."""
    base = tempfile.mkdtemp(prefix=f"eon-ablation-{ablation}.")
    mods_dir = os.path.join(base, "mods")
    write_dir = os.path.join(base, "write")
    os.makedirs(mods_dir)
    os.makedirs(write_dir)
    for name in BASE_MODS + [MOD_NAME, PROBE]:
        if name == MOD_NAME:
            os.symlink(REPO, os.path.join(mods_dir, name))
        elif name == PROBE:
            shutil.copytree(os.path.join(REPO, "tests", PROBE), os.path.join(mods_dir, name))
        else:
            source = os.path.join("/factorio/mods", name)
            if os.path.isdir(source):
                os.symlink(source, os.path.join(mods_dir, name))
    control = os.path.join(mods_dir, PROBE, "data-final-fixes.lua")
    with open(control) as f:
        source = f.read()
    marker = 'local ABLATION = "none"'
    assert marker in source, "the ablation template lost its ABLATION line"
    with open(control, "w") as f:
        f.write(source.replace(marker, f'local ABLATION = "{ablation}"'))
    config = os.path.join(base, "config.ini")
    with open(config, "w") as f:
        f.write(f"[path]\nread-data=/factorio/data\nwrite-data={write_dir}\n")
    command = [FACTORIO_BIN, "--generate-map-preview", os.path.join(base, "preview.png"),
               "--map-preview-planet", "nauvis", "--config", config,
               "--mod-directory", mods_dir, "--map-gen-seed", "12345", "--verbose"]
    result = subprocess.run(command, env={**os.environ, "HOME": base},
                            capture_output=True, text=True, timeout=600)
    if not os.path.exists(os.path.join(base, "preview.png")):
        print(result.stdout[-3000:], result.stderr[-2000:])
        raise SystemExit(f"ablation {ablation}: map preview failed")
    programs, timing = {}, {}
    for line in result.stdout.splitlines():
        match = REPORT_RE.search(line)
        if match:
            entry = {k: (v if k == "program" else int(v)) for k, v in match.groupdict().items()}
            programs[entry["program"]] = entry
        match = TIME_RE.search(line)
        if match:
            timing["preview_seconds"] = float(match.group("seconds"))
        match = COMPILE_RE.search(line)
        if match:
            timing["compile_seconds"] = float(match.group("seconds"))
    shutil.rmtree(base, ignore_errors=True)
    return programs, timing


def complexity(programs):
    return sum(entry["complexity"] for entry in programs.values())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", nargs="*", choices=ABLATIONS)
    parser.add_argument("--box", action="store_true",
                        help="also measure the reveal box (slow: ~8 s per ablation)")
    parser.add_argument("--repeat", type=int, default=1,
                        help="preview runs per ablation; the median time is reported. "
                             "A single preview run has ~+/-0.1 s of noise, which is the "
                             "same size as the whole gain of the small levers.")
    args = parser.parse_args()
    ablations = args.only or ABLATIONS

    baseline = None
    rows = []
    for ablation in ablations:
        programs, timing = with_probe(ablation)
        if args.repeat > 1:
            times = [timing.get("preview_seconds", 0.0)]
            for _ in range(args.repeat - 1):
                _, extra = with_probe(ablation)
                if extra.get("preview_seconds"):
                    times.append(extra["preview_seconds"])
            times.sort()
            timing["preview_seconds"] = times[len(times) // 2]
            timing["preview_runs"] = times
        if baseline is None:
            baseline = programs
        total = complexity(programs)
        base_total = complexity(baseline)
        row = {"ablation": ablation, "total": total, "delta": total - base_total,
               "preview_seconds": timing.get("preview_seconds"),
               "compile_seconds": timing.get("compile_seconds"),
               "programs": {name: entry["complexity"] for name, entry in programs.items()}}
        if args.box:
            # The wall clock the KPI is actually about. The probe mod lives in
            # the mod directory, so the ablation has to ride along with it.
            from probe_noise_cost import strip_script_dat, stage_times
            base = tempfile.mkdtemp(prefix="eon-ablation-box.")
            mods_dir = os.path.join(base, "mods")
            write_dir = os.path.join(base, "write")
            os.makedirs(mods_dir)
            os.makedirs(write_dir)
            for name in BASE_MODS + [MOD_NAME, "eon-probe-noise", PROBE]:
                if name == MOD_NAME:
                    os.symlink(REPO, os.path.join(mods_dir, name))
                elif name in ("eon-probe-noise", PROBE):
                    shutil.copytree(os.path.join(REPO, "tests", name), os.path.join(mods_dir, name))
                elif os.path.isdir(os.path.join("/factorio/mods", name)):
                    os.symlink(os.path.join("/factorio/mods", name), os.path.join(mods_dir, name))
            with open(os.path.join(mods_dir, PROBE, "data-final-fixes.lua")) as f:
                source = f.read()
            with open(os.path.join(mods_dir, PROBE, "data-final-fixes.lua"), "w") as f:
                f.write(source.replace('local ABLATION = "none"', f'local ABLATION = "{ablation}"'))
            config = os.path.join(base, "config.ini")
            with open(config, "w") as f:
                f.write(f"[path]\nread-data=/factorio/data\nwrite-data={write_dir}\n")
            save = os.path.join(base, "probe.zip")
            subprocess.run([FACTORIO_BIN, "--create", save, "--config", config,
                            "--mod-directory", mods_dir, "--map-gen-seed", "12345",
                            "--map-gen-settings", SETTINGS],
                           env={**os.environ, "HOME": base}, capture_output=True, timeout=900)
            if os.path.exists(save):
                strip_script_dat(save)
                import time as _time
                server = subprocess.Popen(
                    [FACTORIO_BIN, "--start-server", save, "--config", config,
                     "--mod-directory", mods_dir, "--port", "0"],
                    env={**os.environ, "HOME": base}, stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL)
                report = os.path.join(write_dir, "script-output", "eon-probe-noise", "box.json")
                deadline = _time.monotonic() + 300
                while _time.monotonic() < deadline and not os.path.exists(report):
                    if server.poll() is not None:
                        break
                    _time.sleep(0.05)
                server.terminate()
                try:
                    server.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    server.kill()
                if os.path.exists(report):
                    stages = stage_times(write_dir)
                    row["box_seconds"] = (stages["box"] - stages["compiled"]) / 1e9
            shutil.rmtree(base, ignore_errors=True)
        rows.append(row)
        delta = f"{row['delta']:+6d} ({100.0 * row['delta'] / base_total:+5.1f}%)"
        line = f"  {ablation:<24} total {total:<7} {delta}"
        if row.get("preview_seconds"):
            line += (f"   preview {row['preview_seconds']:.3f}s"
                     f" ({row['preview_seconds'] - rows[0]['preview_seconds']:+.3f})"
                     + (f" of {row['preview_runs']}" if "preview_runs" in row else ""))
        if "box_seconds" in row:
            line += f"   box {row['box_seconds']:.3f}s"
        print(line)
    print()
    print("per program (complexity):")
    names = sorted({name for row in rows for name in row["programs"]})
    print("  " + "ablation".ljust(24) + "".join(name.ljust(11) for name in names))
    for row in rows:
        print("  " + row["ablation"].ljust(24)
              + "".join(str(row["programs"].get(name, 0)).ljust(11) for name in names))
    with open("/tmp/eon-ablation.json", "w") as f:
        json.dump(rows, f, indent=2)
    print("\nwrote /tmp/eon-ablation.json")


if __name__ == "__main__":
    main()
