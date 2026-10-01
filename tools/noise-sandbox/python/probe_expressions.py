#!/usr/bin/env python3
"""Probe every dumped EoN noise expression through the Rust oracle.

This is intentionally a diagnostic probe, not a release gate. It records which
expressions evaluate, which fail because the active Python graph evaluator is
incomplete, and basic finite-value statistics for the points that do evaluate.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time

from eon_expression import Catalog, Evaluator, Settings
from eon_noise_oracle import RustNoiseOracle


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", default="tools/noise-sandbox/fixtures/data-raw-noise-2.0.77.json")
    parser.add_argument("--settings", default="map-gen-settings-eon-defaults.json")
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--center-x", type=int, default=-3)
    parser.add_argument("--center-y", type=int, default=-26)
    parser.add_argument("--radius", type=int, default=2)
    parser.add_argument("--output", default="-")
    args = parser.parse_args()

    catalog = Catalog.load(args.catalog)
    settings = Settings.load(args.settings)
    points = [
        (x, y)
        for oy in range(-args.radius, args.radius + 1)
        for ox in range(-args.radius, args.radius + 1)
        if ox * ox + oy * oy <= (args.radius + 0.5) ** 2
        for x, y in [(args.center_x + ox, args.center_y + oy)]
    ]
    results = []
    started = time.monotonic()
    with RustNoiseOracle() as oracle:
        evaluator = Evaluator(catalog, settings, args.seed, oracle)
        for name in sorted(catalog.expressions):
            values = []
            error = None
            try:
                for x, y in points:
                    value = evaluator.evaluate(name, x * 32, y * 32)
                    if isinstance(value, (int, float)) and math.isfinite(value):
                        values.append(float(value))
            except Exception as exc:  # diagnostic probe records unsupported graphs
                error = f"{type(exc).__name__}: {exc}"
            results.append({
                "name": name,
                "point_count": len(points),
                "finite_count": len(values),
                "min": min(values) if values else None,
                "max": max(values) if values else None,
                "mean": sum(values) / len(values) if values else None,
                "error": error,
            })
    report = {
        "catalog": args.catalog,
        "settings": args.settings,
        "seed": args.seed,
        "center_chunk": [args.center_x, args.center_y],
        "radius_chunks": args.radius,
        "expression_count": len(catalog.expressions),
        "function_count": len(catalog.functions),
        "elapsed_seconds": time.monotonic() - started,
        "results": results,
    }
    text = json.dumps(report, indent=2)
    if args.output == "-":
        print(text)
    else:
        with open(args.output, "w", encoding="utf-8") as stream:
            stream.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
