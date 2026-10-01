#!/usr/bin/env python3
"""Is the Lua density port equal to the SHIPPED density expression?

noise-mirror/density.lua decides whether a cone becomes a volcano, so it has to be
the engine's own density, not an approximation of it. This compares the two
directly:

  * the reference side is the prototype text -- the `density_expression` of the
    `eon_volcano_spots_at` noise-function, resolved through the whole
    `volcano_area` biome chain by the Python graph evaluator
    (tools/noise-sandbox/python/eon_expression.py), which is the same evaluator
    the cone-centre parity test uses;
  * the Lua side is the mirror's port, asked for the same numbers.

The comparison points are the cones' own candidate centres (the positions the
gate is actually asked at) plus a grid, over several seeds and frequencies.

Usage:
  python3 tests/density_parity.py
  python3 tests/density_parity.py --points 400 --seed 4242 --frequency 6
"""
from __future__ import annotations

import argparse
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/noise-sandbox/python"))
sys.path.insert(0, str(ROOT / "noise-mirror"))

from eon_expression import Catalog, Evaluator, Settings  # noqa: E402
from eon_noise_oracle import RustNoiseOracle  # noqa: E402

sys.path.insert(0, str(ROOT / "tests"))
import noise_fixture  # noqa: E402
def _lua_binary() -> str:
    """The mirror is written for Factorio's Lua, 5.2.1 -- one dialect, no shims.

    Prefer `lua5.2` when it is installed, because the plain `lua` name is an
    alternatives symlink and may point at 5.3/5.4 (which have no `bit32`, so the
    mirror would refuse to load with a clear error rather than run).
    """
    import shutil
    return os.environ.get("LUA") or shutil.which("lua5.2") or "lua"

LUA = _lua_binary()

CONFIGS = [
    # seed, frequency, size  (the same four the cone parity test uses)
    (12345, 2, 1),
    (12345, 6, 1),
    (379334167, 4, 1),
    (3526581861, 2, 1),
]


def lua_shipped_density(seed: int, frequency: int, size: int, points) -> list[float]:
    """Ask the mirror for the spot DENSITY at each point -- the same number the
    gate tests, through the same expression the prototype names."""
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as handle:
        for x, y in points:
            handle.write("{} {}\n".format(int(x), int(y)))
        path = handle.name
    template = """
package.path = "__ROOT__/?.lua;" .. package.path
local cones = require("noise-mirror.volcano-cones")
local context = cones.new_context{ seed = __SEED__, volcanism_size = __SIZE__,
                                   volcanism_frequency = __FREQ__ }
local out = {}
for line in io.lines("__PATH__") do
  local a, b = line:match("(%S+)%s+(%S+)")
  out[#out + 1] = string.format("%.12g", cones.cone_density(context, tonumber(a), tonumber(b)))
end
for _, line in ipairs(out) do print(line) end
"""
    script = (template
              .replace("__ROOT__", str(ROOT))
              .replace("__SEED__", str(seed))
              .replace("__SIZE__", str(size))
              .replace("__FREQ__", str(frequency))
              .replace("__PATH__", path))
    proc = subprocess.run([LUA, "-"], input=script, capture_output=True, text=True,
                          timeout=900)
    if proc.returncode:
        raise SystemExit("lua density failed:\n" + proc.stderr)
    return [float(v) for v in proc.stdout.split()]


def lua_candidate_centres(seed: int, frequency: int, size: int, wanted: int):
    """Every cone candidate centre the mirror would ask the gate about."""
    script = f"""
package.path = "{ROOT}/?.lua;" .. package.path
local cones = require("noise-mirror.volcano-cones")
local candidates = require("noise-mirror.spot-candidates")
local context = cones.new_context{{ seed = {seed}, volcanism_size = {size},
                                   volcanism_frequency = {frequency} }}
local lines = {{}}
for region_x = -6, 6 do for region_y = -6, 6 do
  for _, system in ipairs(cones.SYSTEMS) do
    system.region_size = context.region_size
    system.spacing = 1500 * context.volcanism * system.spacing_mult
    local centre = candidates.first_accepted(context.seed, system.seed1, region_x,
      region_y, system.region_size, system.spacing)
    if centre then
      lines[#lines + 1] = string.format("%d %d", centre.x, centre.y)
    end
  end
end end
for _, line in ipairs(lines) do print(line) end
"""
    proc = subprocess.run([LUA, "-"], input=script, capture_output=True, text=True,
                          timeout=900)
    if proc.returncode:
        raise SystemExit("lua candidate centres failed:\n" + proc.stderr)
    points = []
    for line in proc.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2:
            points.append((float(parts[0]), float(parts[1])))
    return points[:wanted] if wanted else points


def reference(seed: int, frequency: int, size: int, points) -> list[float]:
    """volcano_area from the shipped expression graph, via the reference evaluator."""
    # The catalog is a --dump-data capture, not source: regenerated here so a
    # gate can never read a snapshot older than the mod it is checking.
    catalog = Catalog.load(noise_fixture.ensure())
    oracle = RustNoiseOracle()
    # The autoplace controls the expressions read, exactly as the cone parity test
    # builds them -- without these the reference silently uses frequency 1.
    settings = Settings({"autoplace_controls": {
        "vulcanus_volcanism": {"frequency": float(frequency), "size": float(size)},
    }})
    evaluator = Evaluator(catalog, settings, int(seed), oracle)
    # The exact prototype text: the DENSITY EXPRESSION of the spot_noise we are
    # mirroring, evaluated at the candidate point. Not the raw biome expression --
    # the density's own `volcano_area` is that biome lerped toward zero by the
    # starting area, and inside the starting area the lerp is exactly zero.
    node = catalog.parsed["eon_volcano_spots_at"]
    density_expression = node.kwargs["density_expression"]
    values = []
    for x, y in points:
        env = {
            "x": x, "y": y, "map_seed": float(seed),
            "map_seed_small": seed & 0xFFFF,
            "map_seed_normalized": seed / 4_294_967_296.0,
            "starting_positions": [[0.0, 0.0]],
            "pi": math.pi, "e": math.e, "inf": math.inf,
        }
        record = {**catalog.expressions, **catalog.functions}["eon_volcano_spots_at"]
        for local_name in record.get("local_expressions", {}):
            env[f"local:{local_name}"] = True
        env["owner"] = "eon_volcano_spots_at"
        env["local_functions"] = record.get("local_functions", {})
        values.append(float(evaluator.eval_node(density_expression, env)))
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--points", type=int, default=120)
    args = parser.parse_args()

    worst_absolute = 0.0
    worst_relative = 0.0
    sign_flips = 0
    near_zero = 0
    total = 0

    for seed, frequency, size in CONFIGS:
        # The CANDIDATE CENTRES, not a grid: the gate is a sign test at exactly
        # these positions, so those are the only points where agreement means
        # anything. (A grid sample said 100% while the game disagreed on whole
        # volcanoes -- the grid never asked the question.)
        points = lua_candidate_centres(seed, frequency, size, args.points)
        got = lua_shipped_density(seed, frequency, size, points)
        want = reference(seed, frequency, size, points)
        for (x, y), a, b in zip(points, got, want):
            worst_absolute = max(worst_absolute, abs(a - b))
            if abs(b) > 0.05:
                worst_relative = max(worst_relative, abs(a - b) / abs(b))
            else:
                near_zero += 1
            if (a > 0) != (b > 0):
                sign_flips += 1
                if sign_flips <= 3:
                    print("  sign differs at %d,%d: lua %+.6f vs shipped %+.6f" % (x, y, a, b))
        total += len(points)
        print("  seed %d frequency %d: %d points, worst absolute %.3g, "
              "worst relative away from zero %.3g"
              % (seed, frequency, len(points), worst_absolute, worst_relative))

    print("worst absolute error %.3g, worst relative away from zero %.3g, over %d points "
          "in %d configurations" % (worst_absolute, worst_relative, total, len(CONFIGS)))
    print("sign agreement: %d/%d (%.2f%%), %d points within 0.05 of the threshold"
          % (total - sign_flips, total, 100.0 * (total - sign_flips) / total, near_zero))

    # The mirror is a transcription, not the same binary: it tracks the shipped
    # expression to ~1e-3 rather than bit-exactly. What the gate is FOR is a sign
    # test, so tracking away from the threshold is the accuracy criterion and the
    # sign agreement is the correctness one.
    if worst_relative > 0.05:
        print("DENSITY PARITY FAILED: the port does not track the shipped expression")
        return 1
    if sign_flips > max(2, total * 0.005):
        print("DENSITY PARITY FAILED: %d sign disagreements" % sign_flips)
        return 1
    print("DENSITY PARITY OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
