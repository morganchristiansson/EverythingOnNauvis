#!/usr/bin/env python3
"""The engine's OWN noise-program report, for a surface that carries the mod.

The engine prints per-program complexity ("N expressions (M unique) ... estimated
complexity: C") under --verbose, and the command that reaches it in ~2 s is
`--generate-map-preview`. It is the authoritative metric -- it is the number
Factorio's own cost model uses -- and it does see the mod, provided the mod
directory is right.

**The trap that cost this feature an afternoon:** Factorio ENABLES EVERY MOD IT
FINDS in `--mod-directory` and rewrites `mod-list.json` accordingly. Writing a
mod-list.json that leaves the mod out does nothing, and the resulting A/B comes
out "byte identical" -- the mod is quietly enabled in both runs. A baseline must
be a mod directory that does not CONTAIN the mod, which is what this script
builds.

Usage:
    python3 tests/noise_engine_report.py                    # mod + vanilla baseline
    python3 tests/noise_engine_report.py --mods vanilla
    python3 tests/noise_engine_report.py --json /tmp/report.json
    python3 tests/noise_engine_report.py --compare /tmp/before.json
"""
import argparse
import json
import os
import re
import subprocess
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MOD_NAME = "EverythingOnNauvis-morganc"
BASE_MODS = ["base", "elevated-rails", "quality", "space-age"]

REPORT_RE = re.compile(
    r'(?P<program>\w+) noise program processed (?P<processed>\d+) expressions '
    r'\((?P<unique>\d+) unique\) and has (?P<operations>\d+) operations and '
    r'(?P<registers>\d+) registers; estimated complexity: (?P<complexity>\d+)')


def measure(mods, planet="nauvis", seed=12345, settings=None, base_dir=None):
    """Run one map preview and return the engine's report."""
    own_dir = base_dir or tempfile.mkdtemp(prefix="eon-noise-report.")
    mods_dir = os.path.join(own_dir, "mods")
    write_dir = os.path.join(own_dir, "write")
    os.makedirs(mods_dir, exist_ok=True)
    os.makedirs(write_dir, exist_ok=True)
    for name in mods:
        # base/quality/space-age live in the read-data dir; anything else is
        # symlinked in. The directory CONTENT is what selects the mod set.
        if name == MOD_NAME:
            os.symlink(REPO, os.path.join(mods_dir, name))
        else:
            source = os.path.join("/factorio/mods", name)
            if os.path.isdir(source):
                os.symlink(source, os.path.join(mods_dir, name))
    config = os.path.join(own_dir, "config.ini")
    with open(config, "w") as f:
        f.write(f"[path]\nread-data=/factorio/data\nwrite-data={write_dir}\n")
    command = [FACTORIO_BIN, "--generate-map-preview", os.path.join(own_dir, "preview.png"),
               "--map-preview-planet", planet, "--config", config,
               "--mod-directory", mods_dir, "--map-gen-seed", str(seed), "--verbose"]
    if settings:
        command += ["--map-gen-settings", settings]
    result = subprocess.run(command, env={**os.environ, "HOME": own_dir},
                            capture_output=True, text=True, timeout=600)
    if not os.path.exists(os.path.join(own_dir, "preview.png")):
        print(result.stdout[-3000:], result.stderr[-3000:])
        raise SystemExit("map preview failed")
    programs = {}
    for line in result.stdout.splitlines():
        match = REPORT_RE.search(line)
        if match:
            entry = {k: (v if k == "program" else int(v))
                     for k, v in match.groupdict().items()}
            programs[entry["program"]] = entry
    if not programs:
        raise SystemExit("the engine printed no noise program report -- "
                         "was the mod actually loaded? (grep the log for "
                         "'Loading mod EverythingOnNauvis-morganc')")
    return {"mods": mods, "programs": programs, "mod_list": read_mod_list(mods_dir)}


def read_mod_list(mods_dir):
    path = os.path.join(mods_dir, "mod-list.json")
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return sorted(entry["name"] for entry in json.load(f)["mods"] if entry.get("enabled"))


def totals(report):
    """Per-program complexity, keyed by program name."""
    return {name: entry["complexity"] for name, entry in sorted(report["programs"].items())}


def complexity_sum(entries):
    """Total complexity of a {program: complexity} mapping, or of the full
    per-program report (the engine's own dicts carry one "complexity" each)."""
    total = 0
    for value in entries.values():
        total += value["complexity"] if isinstance(value, dict) else value
    return total


def print_report(label, report, baseline=None):
    print(f"{label}: enabled mods = {', '.join(report['mod_list'])}")
    for program, entry in sorted(report["programs"].items()):
        line = (f"  {program:<10} expressions={entry['processed']:<6} unique={entry['unique']:<6}"
                f" operations={entry['operations']:<5} complexity={entry['complexity']}")
        if baseline and program in baseline:
            before = baseline[program]["complexity"]
            line += f"  (vanilla {before}, {entry['complexity'] / max(1, before):.2f}x)"
        print(line)
    print(f"  total complexity: {complexity_sum(report['programs'])}"
          + (f" vs vanilla {complexity_sum(baseline)}"
             if baseline else ""))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mods", nargs="*", default=BASE_MODS + [MOD_NAME],
                        help="the mod set; the mod must be absent from the directory for a baseline")
    parser.add_argument("--planet", default="nauvis")
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--settings")
    parser.add_argument("--baseline", action="store_true",
                        help="also measure the same set without the mod and print the ratio")
    parser.add_argument("--json", help="write this run's report here")
    parser.add_argument("--compare", help="a report JSON to compare against")
    args = parser.parse_args()

    report = measure(args.mods, args.planet, args.seed, args.settings)
    baseline = None
    if args.baseline:
        without = [m for m in args.mods if m != MOD_NAME]
        vanilla = measure(without, args.planet, args.seed, args.settings)
        baseline = vanilla["programs"]
        print_report("with mod", report, baseline)
        print_report("without mod", vanilla)
    else:
        print_report("run", report)
    if args.compare:
        with open(args.compare, encoding="utf-8") as f:
            before = json.load(f)
        print(f"compare against {args.compare}:")
        for program, entry in sorted(report["programs"].items()):
            was = before["programs"].get(program)
            if was:
                delta = entry["complexity"] - was["complexity"]
                print(f"  {program:<10} complexity {was['complexity']} -> {entry['complexity']}"
                      f" ({delta:+d}, {100.0 * delta / max(1, was['complexity']):+.1f}%)")
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, sort_keys=True)
        print(f"wrote {args.json}")


if __name__ == "__main__":
    main()
