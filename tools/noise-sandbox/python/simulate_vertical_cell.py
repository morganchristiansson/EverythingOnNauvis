#!/usr/bin/env python3
"""Evaluate the corrected vertical-cell split from an existing raw simulation.

This avoids reevaluating the full territory expression: the raw report already
identifies claimed chunks; only eon_demolisher_cell and eon_volcano_size_dist
are needed to construct the candidate index.
"""
from __future__ import annotations

import argparse
import json
import math

from eon_expression import Catalog, Evaluator, Settings
from eon_noise_oracle import RustNoiseOracle


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("raw_report")
    p.add_argument("--catalog", default="tools/noise-sandbox/fixtures/data-raw-noise-2.0.77.json")
    p.add_argument("--settings", default="map-gen-settings-eon-defaults.json")
    p.add_argument("--seed", type=int, default=12345)
    p.add_argument("--minimum-size", type=int, default=3)
    p.add_argument("--connectivity", type=int, choices=(4, 8), default=4)
    p.add_argument("--output", default="-")
    args = p.parse_args()
    raw = json.load(open(args.raw_report, encoding="utf-8"))
    points = [(c["x"], c["y"]) for c in raw["chunks"] if c.get("index") is not None]
    catalog = Catalog.load(args.catalog)
    settings = Settings.load(args.settings)
    with RustNoiseOracle() as oracle:
        evaluator = Evaluator(catalog, settings, args.seed, oracle)
        values = {}
        for x, y in points:
            wx, wy = x * 32, y * 32
            cell = evaluator.evaluate("eon_demolisher_cell", wx, wy)
            size = evaluator.evaluate("eon_volcano_size_dist", wx, wy)
            local_x = wx + 512000
            local_x -= 1100 * math.floor(local_x / 1100)
            zone = 1 if size < 0.55 else (3 if local_x < 550 else 2)
            values[(x, y)] = 1_000_000 + 1000 * cell + zone
        grouped = oracle.request({
            "op": "territory_group",
            "points": [[x, y, values[(x, y)]] for x, y in points],
            "connectivity": args.connectivity,
            "minimum_size": args.minimum_size,
        })
    territory_id = {(e["x"], e["y"]): e["id"] for e in grouped}
    out = dict(raw)
    out["expression"] = "vertical-cell-candidate"
    out["territory_count"] = len({e["id"] for e in grouped})
    out["chunks"] = [{**c, "t": territory_id.get((c["x"], c["y"]), 0)} for c in raw["chunks"]]
    text = json.dumps(out, separators=(",", ":"))
    if args.output == "-": print(text)
    else: open(args.output, "w", encoding="utf-8").write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
