#!/usr/bin/env python3
"""One command that runs every gate of the runtime volcano territories.

  1. lua tests/noise-mirror/selftest.lua -- the mirror against GAME-captured vectors and
     its own invariants (closed footprints, disjoint cones, existence by density).
  1a. tests/builder_test.lua -- the CLAIM path driven against a fake surface:
      one event claims a cone, the whole disc goes in, a demolisher is placed with
      a body, a second event creates nothing, and every cone in a generated area is
      claimed. The "every cone is unseen" defect took a game restart and a pasted
      log to localise because there was nowhere smaller to look; this is that place.
  1a. tests/demolisher_turn_test.lua -- the REAL body layout, measured: no
     joint turns harder than the engine's patrolling_turn_radius allows, segment
     spacing is rigid (no gaps), and the limit is reached at the corners rather
     than ignored. Added because the turn rule was "implemented" three times and
     measured 12.2x, then 4.4x, then 3.2x over the limit while every other gate
     stayed green: a placement rule is only observable in the output it produces.
  1b. tests/density_parity.py -- the cone-EXISTENCE gate (noise-mirror/density.lua)
     against the shipped density expression, at the candidate centres the gate is
     actually asked about. Existence is a pure function of position now, so this is
     the whole "is this a volcano" question, and it is answered without tiles.
  1c. tests/field_parity.py -- the spot FIELD against the shipped expression: the
     six WOBBLE octaves that displace the query point, and the cone value at a
     point, which is (3/pi) * (1 - d/width) over the winning cone taken at the
     DISPLACED position. The route solves its radius against that field, so this
     is its contract. The wobble reference is read out of the expression's own
     `x` kwarg rather than transcribed.
  2. tests/spot_mirror_parity.py -- the mirror against the ENGINE's own spot
     selection, through the Rust oracle and the shipped noise-expression
     prototypes, on several seed/frequency/size configurations.
  3. tests/probe_runtime_territory.py -- the wiring end to end in a real headless
     Factorio, at 100% and 600% volcanism: one create_territory per cone, the
     mirror's exact chunk list, tile truth, no re-creation.
  4. tests/lint_duplicate_functions.py -- no Lua file defines a name twice
  5. tests/dead_expressions.py -- nothing the data stage defines is unreachable
     from a prototype, so no dead expression lingers in a runtime dump.

Usage: python3 tests/run_spot_mirror_tests.py [--quick]
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
def _lua_binary() -> str:
    """The mirror is written for Factorio's Lua, 5.2.1 -- one dialect, no shims.

    Prefer `lua5.2` when it is installed, because the plain `lua` name is an
    alternatives symlink and may point at 5.3/5.4 (which have no `bit32`, so the
    mirror would refuse to load with a clear error rather than run).
    """
    import shutil
    return os.environ.get("LUA") or shutil.which("lua5.2") or "lua"

LUA = _lua_binary()
MOD_NAME = "EverythingOnNauvis-morganc"

PARITY_RUNS = [
    ["--radius", "14"],
    ["--frequency", "6", "--radius", "16"],
    ["--seed", "379334167", "--frequency", "4", "--radius", "12"],
    ["--frequency", "6", "--size", "0.6", "--radius", "12"],
]
E2E_RUNS = ["tests/map-gen-settings-user.json", "tests/map-gen-settings-high-volcanism.json"]


def run(label, command, cwd=ROOT):
    print(f"\n=== {label}\n$ {' '.join(str(c) for c in command)}", flush=True)
    result = subprocess.run([str(c) for c in command], cwd=str(cwd))
    return result.returncode == 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--quick", action="store_true",
                        help="one parity run and one end-to-end run")
    args = parser.parse_args()
    results = []

    results.append(("selftest", run("mirror self test (game-captured vectors)",
                                    [LUA, "tests/noise-mirror/selftest.lua"])))
    results.append(("builder unit test",
                    run("the claim path against a fake surface, no Factorio",
                        [LUA, "tests/builder_test.lua"])))
    results.append(("demolisher turn radius",
                    run("the real body layout honours the engine's patrolling_turn_radius",
                        ["lua5.2", "tests/demolisher_turn_test.lua"])))
    results.append(("no duplicate functions",
                    run("a Lua file that defines a name twice keeps the LATER one",
                        ["python3", "tests/lint_duplicate_functions.py",
                         "noise-mirror", "tests"])))
    results.append(("dead expressions",
                    run("nothing unreachable left in the data stage",
                        ["python3", "tests/dead_expressions.py"])))
    results.append(("density parity",
                    run("the mirror's cone-existence gate vs the shipped density expression",
                        ["python3", "tests/density_parity.py", "--points", "400"])))
    results.append(("field parity",
                    run("the mirror's spot field and query-point displacement vs the shipped expression",
                        ["python3", "tests/field_parity.py", "--points", "200"])))
    for extra in (PARITY_RUNS[:1] if args.quick else PARITY_RUNS):
        results.append((f"parity {' '.join(extra)}",
                        run("mirror vs the engine's own spot selection",
                            ["python3", "tests/spot_mirror_parity.py"] + extra)))
    for settings_file in (E2E_RUNS[:1] if args.quick else E2E_RUNS):
        results.append((f"e2e {settings_file}",
                        run("runtime territories in a real Factorio",
                            ["python3", "tests/probe_runtime_territory.py", settings_file])))
    print("\n================ summary")
    for name, ok in results:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
    failed = [name for name, ok in results if not ok]
    print("SPOT MIRROR OK" if not failed else f"SPOT MIRROR FAILED: {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
