"""The spot FIELD, against the shipped expression -- the wobble and the cone.

spot_noise is evaluated at a DISPLACED query point, so the field at a world
position is the undisplaced cone evaluated at (x + wobble_x, y + wobble_y). The
cone's own profile is a plain linear falloff with no noise in it, so the wobble is
the entire source of a volcano's edge roughness -- and a ground edge was measured
running 53 to 87 tiles from the centre of a cone whose claim radius was 67.

This gate exists because the mirror cannot infer any of this from its own code: the
route and, later, the claim have to be solved against the DISPLACED field, and
getting the displacement wrong moves the ground under every guard.

The reference is read out of the shipped expression rather than transcribed. The
spot_noise node's `x` kwarg IS `x + x_offset + <the three octaves>`, so evaluating
that at a point and subtracting x gives the reference displacement, straight from
the expression the mod ships. There is nothing here to keep in sync by hand.

    python3 tests/field_parity.py

Two checks, because they are two questions and both are needed before anything
solves a route radius against this field:

  * the WOBBLE -- the six octaves that displace the query point;
  * the CONE -- the field value at a point, which is (3/pi) * (1 - d/width) over
    the winning cone, taken at the DISPLACED position.
"""

import argparse
import math
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA = "lua5.2"
sys.path.insert(0, os.path.join(ROOT, "tests"))
sys.path.insert(0, os.path.join(ROOT, "tools/noise-sandbox/python"))

import noise_fixture  # noqa: E402
from eon_expression import Catalog, Evaluator, Settings  # noqa: E402
from eon_noise_oracle import RustNoiseOracle  # noqa: E402

CONFIGS = [(1096463296, 6, 1.0), (3526581861, 2, 1.0), (12345, 6, 0.6)]

LUA_WOBBLE = """
local cones = require("noise-mirror.volcano-cones")
local field = cones.new_volcanoes(cones.new_context{{
  seed = {seed}, volcanism_size = {size}, volcanism_frequency = {frequency} }})
for index, point in ipairs(POINTS) do
  local dx, dy = cones.wobble(field.context, point[1], point[2])
  print(string.format("%.9f %.9f", dx, dy))
end
"""

LUA_FIELD = """
local cones = require("noise-mirror.volcano-cones")
local field = cones.new_volcanoes(cones.new_context{{
  seed = {seed}, volcanism_size = {size}, volcanism_frequency = {frequency} }})
for index, point in ipairs(POINTS) do
  print(string.format("%.9f", field:cone_value(point[1], point[2])))
end
"""


def sample_points(count, seed):
    """Points on a wide ring, so the three octaves are all sampled at their own
    scales -- a cluster near one spot would not distinguish a 6-tile feature from
    a 100-tile one."""
    points = []
    golden = 2.399963229728653
    for index in range(count):
        angle = index * golden
        radius = 40 + 900 * math.sqrt((index + 0.5) / count)
        points.append((round(radius * math.cos(angle) + seed % 97, 1),
                       round(radius * math.sin(angle) - seed % 89, 1)))
    return points


def lua_sample(template, points, seed, frequency, size, arity):
    script = ("POINTS = {\n" + "".join(
        "  {%.4f, %.4f},\n" % point for point in points) + "}\n"
        + template.format(seed=seed, frequency=frequency, size=size))
    proc = subprocess.run([LUA, "-"], input=script, capture_output=True, text=True,
                          timeout=900)
    if proc.returncode:
        raise SystemExit("lua sample failed:\n" + proc.stderr)
    out = []
    for line in proc.stdout.splitlines():
        parts = line.split()
        if len(parts) == arity:
            out.append(tuple(float(part) for part in parts))
    return out


def lua_wobble(points, seed, frequency, size):
    return lua_sample(LUA_WOBBLE, points, seed, frequency, size, 2)


def lua_field(points, seed, frequency, size):
    return lua_sample(LUA_FIELD, points, seed, frequency, size, 1)


def field_reference(points, seed, frequency, size):
    """eon_mountain_volcano_spots evaluated as an expression: that is the field.

    It is a single spot_noise call, so evaluating the expression at a point gives
    the engine's own field there -- no reconstruction of the cone, and nothing to
    keep in sync but the expression's name.
    """
    catalog = Catalog.load(noise_fixture.ensure())
    oracle = RustNoiseOracle()
    settings = Settings({"autoplace_controls": {
        "vulcanus_volcanism": {"frequency": float(frequency), "size": float(size)},
    }})
    evaluator = Evaluator(catalog, settings, int(seed), oracle)
    node = catalog.parsed["eon_mountain_volcano_spots"]
    record = catalog.expressions.get("eon_mountain_volcano_spots") or {}
    out = []
    for x, y in points:
        env = {
            "x": x, "y": y, "map_seed": float(seed),
            "map_seed_small": seed & 0xFFFF,
            "map_seed_normalized": seed / 4_294_967_296.0,
            "starting_positions": [[0.0, 0.0]],
            "pi": math.pi, "e": math.e, "inf": math.inf,
            "owner": "eon_mountain_volcano_spots",
            "local_functions": record.get("local_functions", {}),
        }
        for local_name in record.get("local_expressions", {}):
            env[f"local:{local_name}"] = True
        out.append(float(evaluator.eval_node(node, env)))
    return out


def reference(points, seed, frequency, size):
    """The displacement the shipped expression applies, read out of its own text."""
    catalog = Catalog.load(noise_fixture.ensure())
    oracle = RustNoiseOracle()
    settings = Settings({"autoplace_controls": {
        "vulcanus_volcanism": {"frequency": float(frequency), "size": float(size)},
    }})
    evaluator = Evaluator(catalog, settings, int(seed), oracle)
    node = catalog.parsed["eon_volcano_spots_at"]
    x_expression, y_expression = node.kwargs["x"], node.kwargs["y"]
    record = catalog.expressions.get("eon_volcano_spots_at") or {}
    out = []
    for x, y in points:
        env = {
            "x": x, "y": y, "map_seed": float(seed),
            "map_seed_small": seed & 0xFFFF,
            "map_seed_normalized": seed / 4_294_967_296.0,
            "starting_positions": [[0.0, 0.0]],
            "x_offset": 0.0, "y_offset": 0.0,
            "pi": math.pi, "e": math.e, "inf": math.inf,
            "owner": "eon_volcano_spots_at",
            "local_functions": record.get("local_functions", {}),
        }
        for local_name in record.get("local_expressions", {}):
            env[f"local:{local_name}"] = True
        dx = float(evaluator.eval_node(x_expression, env)) - x
        dy = float(evaluator.eval_node(y_expression, env)) - y
        out.append((dx, dy))
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--points", type=int, default=96)
    args = parser.parse_args()

    worst_absolute = 0.0
    worst_relative = 0.0
    worst_at = None
    total = 0

    worst_field = 0.0
    worst_field_at = None
    for seed, frequency, size in CONFIGS:
        points = sample_points(args.points, seed)

        # 1. the field, at the points -- the wobbled cone the route will follow
        got_field = lua_field(points, seed, frequency, size)
        want_field = field_reference(points, seed, frequency, size)
        if len(got_field) != len(want_field):
            raise SystemExit("lua returned %d field values, reference %d"
                             % (len(got_field), len(want_field)))
        for (mine,), theirs, point in zip(got_field, want_field, points):
            error = abs(mine - theirs)
            if error > worst_field:
                worst_field = error
                worst_field_at = (point, mine, theirs)
        print("  seed %d frequency %d size %s: %d field values, worst %.3e"
              % (seed, frequency, size, len(points), worst_field))

        # 2. the wobble that displaces it
        got = lua_wobble(points, seed, frequency, size)
        want = reference(points, seed, frequency, size)
        if len(got) != len(want):
            raise SystemExit("lua returned %d points, reference %d"
                             % (len(got), len(want)))
        for (gx, gy), (wx, wy), point in zip(got, want, points):
            for mine, theirs in ((gx, wx), (gy, wy)):
                error = abs(mine - theirs)
                total += 1
                if error > worst_absolute:
                    worst_absolute = error
                    worst_at = (point, mine, theirs)
                scale = abs(theirs)
                if scale > 1e-9:
                    worst_relative = max(worst_relative, error / scale)
        print("  seed %d frequency %d size %s: %d wobble pairs" % (
            seed, frequency, size, len(points)))

    print("worst absolute error %.3e, worst relative %.3e, over %d values in %d "
          "configurations" % (worst_absolute, worst_relative, total, len(CONFIGS)))
    if worst_at:
        point, mine, theirs = worst_at
        print("worst at %s: mirror %.9f, reference %.9f"
              % (point, mine, theirs))
    # The wobble is a displacement of order 10 tiles; anything under a thousandth
    # of a tile is not a disagreement worth failing over.
    if worst_field > 1e-4:
        print("FIELD PARITY FAILED: worst %.3e at %s (mirror %.9f, reference %.9f)"
              % (worst_field, worst_field_at[0], worst_field_at[1], worst_field_at[2]))
        return 1
    print("field worst error %.3e, wobble worst error %.3e" % (worst_field, worst_absolute))
    if worst_absolute > 1e-3:
        print("WOBBLE PARITY FAILED")
        return 1
    print("FIELD PARITY OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
