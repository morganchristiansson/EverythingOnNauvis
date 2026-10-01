#!/usr/bin/env python3
"""Noise-program budget: the engine's own complexity report, gated.

The API docs say the engine prints this report "after creating a surface or
CHANGING MapGenSettings" -- and changing MapGenSettings is what a map reset does,
so the report is reachable on the real surface through rcon
(`tests/noise_real_report.py`, ~5 s per side). That is the metric this gates.

**The real surface is not the preview surface, and the difference is large:**
same mod, same seed, the preview reports Entity 3349 unique / 33732 complexity
and the real surface 5833 / 47405 -- 74% bigger, because the preview never
carries the planet's autoplace settings. Optimise against the real one.

What the budget protects is the Legendary Deathworld reset reveal: the
scenario force-generates a 39x39 chunk box on every reset, and interleaved
best-of-4 measurements (seed 12345, its own map-gen settings) give

    vanilla base+space-age   5.11 s
    with EverythingOnNauvis  5.85 s      (+0.74 s, +14%)

so the mod's program is ~14% of the box. A new noise expression is a per-tile
cost for the whole map, which is why this file exists: it fails when the
program grows, in the unit the engine itself uses.

Usage:
    python3 tests/noise_budget.py            # check against the committed budget
    python3 tests/noise_budget.py --print    # the numbers, no gate
    python3 tests/noise_budget.py --update   # re-measure and rewrite the budget
    python3 tests/noise_budget.py --ablate   # the per-subsystem price survey
"""
import argparse
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUDGET = os.path.join(REPO, "tests", "noise_budget.json")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from noise_real_report import BASE_MODS, MOD_NAME, measure  # noqa: E402

# The programs the engine reports. Cliff and Territory are small; Entity and
# Tile carry the merged map and are the ones that move.
PROGRAMS = ("Cliff", "Entity", "Tile", "Territory")


def snapshot():
    """{'with mod': {...}, 'vanilla': {...}} measured on the REAL surface."""
    with_mod = measure(BASE_MODS + [MOD_NAME])
    without = measure(BASE_MODS, port=27020, game_port=29020)
    return {
        "with_mod": {name: with_mod["programs"][name]["complexity"]
                     for name in PROGRAMS if name in with_mod["programs"]},
        "vanilla": {name: without["programs"][name]["complexity"]
                    for name in PROGRAMS if name in without["programs"]},
    }


def print_snapshot(current, budget=None):
    for label in ("with_mod", "vanilla"):
        entries = current[label]
        print(f"{label}: total complexity {sum(entries.values())}")
        for program in PROGRAMS:
            if program not in entries:
                continue
            line = f"  {program:<10} {entries[program]:<7}"
            if budget and label == "with_mod":
                limit = budget["with_mod"].get(program)
                if limit is not None:
                    line += f"budget {limit} ({'ok' if entries[program] <= limit else 'OVER'})"
            if label == "with_mod" and current["vanilla"].get(program):
                line += f"   {entries[program] / current['vanilla'][program]:.2f}x vanilla"
            print(line)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", action="store_true")
    parser.add_argument("--print", dest="print_only", action="store_true")
    parser.add_argument("--ablate", action="store_true",
                        help="run the per-subsystem price survey instead of the gate; "
                             "further arguments go to noise_ablation.py")
    # Arguments after --ablate belong to the survey tool.
    args, extra = parser.parse_known_args()

    if args.ablate:
        # hand the rest of the command line to the survey tool
        import noise_ablation
        sys.argv = [sys.argv[0]] + (extra or ["--only", "none"])
        raise SystemExit(noise_ablation.main())

    current = snapshot()
    if args.update:
        # The total is gated as well: two programs could each stay under budget
        # while the reset gets slower.
        current["with_mod_total"] = sum(current["with_mod"].values())
        current["vanilla_total"] = sum(current["vanilla"].values())
        with open(BUDGET, "w", encoding="utf-8") as f:
            json.dump(current, f, indent=2, sort_keys=True)
            f.write("\n")
        print(f"wrote {BUDGET}")
        return
    print_snapshot(current)
    if args.print_only:
        return

    with open(BUDGET, encoding="utf-8") as f:
        budget = json.load(f)
    failures = []
    for program in PROGRAMS:
        limit = budget["with_mod"].get(program)
        actual = current["with_mod"].get(program)
        if limit is None or actual is None:
            continue
        status = "PASS" if actual <= limit else "FAIL"
        print(f"  [{status}] {program} complexity {actual} <= budget {limit}")
        if actual > limit:
            failures.append(f"{program}: complexity {actual} exceeds budget {limit}")
    total_limit = budget.get("with_mod_total")
    total = sum(current["with_mod"].values())
    if total_limit is not None:
        status = "PASS" if total <= total_limit else "FAIL"
        print(f"  [{status}] total complexity {total} <= budget {total_limit}")
        if total > total_limit:
            failures.append(f"total complexity {total} exceeds budget {total_limit}")
    print()
    if failures:
        for failure in failures:
            print("FAILURE:", failure)
        raise SystemExit(1)
    print("Noise program is within budget.")


if __name__ == "__main__":
    main()
