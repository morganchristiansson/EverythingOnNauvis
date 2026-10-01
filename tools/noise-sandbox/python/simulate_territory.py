#!/usr/bin/env python3
"""Evaluate an EoN territory index over chunk-corner samples."""
from __future__ import annotations

import argparse
import json
import math
import os
from concurrent.futures import ProcessPoolExecutor
from eon_expression import Catalog, Evaluator, Parser, Settings
from eon_noise_oracle import RustNoiseOracle


_WORKER_CATALOG = None
_WORKER_SETTINGS = None
_WORKER_AST = None
_WORKER_EVALUATOR = None
_WORKER_ORACLE = None
_WORKER_EXPRESSION = None
_WORKER_MASK = None


def _init_worker(catalog_path, settings_path, seed, expression, expression_source, mask_expression):
    global _WORKER_CATALOG, _WORKER_SETTINGS, _WORKER_AST, _WORKER_EVALUATOR, _WORKER_ORACLE
    global _WORKER_EXPRESSION, _WORKER_MASK
    _WORKER_CATALOG = Catalog.load(catalog_path)
    _WORKER_SETTINGS = Settings.load(settings_path)
    _WORKER_AST = Parser(expression_source).parse() if expression_source else None
    _WORKER_ORACLE = RustNoiseOracle()
    _WORKER_EVALUATOR = Evaluator(_WORKER_CATALOG, _WORKER_SETTINGS, seed, _WORKER_ORACLE)
    _WORKER_EXPRESSION = expression
    _WORKER_MASK = mask_expression


def _evaluate_chunk(xy):
    x, y = xy
    index = (_WORKER_EVALUATOR.evaluate_ast(_WORKER_AST, x=x * 32, y=y * 32)
             if _WORKER_AST is not None else
             _WORKER_EVALUATOR.evaluate(_WORKER_EXPRESSION, x * 32, y * 32))
    return x, y, index, _WORKER_EVALUATOR.evaluate(_WORKER_MASK, x * 32, y * 32) > 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", default="tools/noise-sandbox/fixtures/data-raw-noise-2.0.77.json")
    parser.add_argument("--settings", default="map-gen-settings-eon-defaults.json")
    parser.add_argument("--expression", default="demolisher_territory_expression")
    parser.add_argument("--expression-source", help="evaluate this expression source instead of a named expression")
    parser.add_argument("--mask-expression", default="eon_demolisher_territory")
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--center-x", type=int, default=-3)
    parser.add_argument("--center-y", type=int, default=-26)
    parser.add_argument("--radius", type=int, default=64)
    # Factorio's observed grouping is closer to edge-connected components for
    # the current production index; keep 8 available for A/B experiments.
    parser.add_argument("--connectivity", type=int, choices=(4, 8), default=4)
    parser.add_argument("--minimum-size", type=int, default=3)
    parser.add_argument("--workers", type=int, default=min(4, max(1, (os.cpu_count() or 2) // 2)))
    args = parser.parse_args()

    work = []
    for oy in range(-args.radius, args.radius + 1):
        for ox in range(-args.radius, args.radius + 1):
            if ox * ox + oy * oy <= (args.radius + 0.5) ** 2:
                work.append((args.center_x + ox, args.center_y + oy))
    indexes = {}
    masks = {}
    initargs = (args.catalog, args.settings, args.seed, args.expression,
                args.expression_source, args.mask_expression)
    if args.workers > 1:
        with ProcessPoolExecutor(max_workers=args.workers, initializer=_init_worker, initargs=initargs) as pool:
            results = pool.map(_evaluate_chunk, work, chunksize=32)
    else:
        _init_worker(*initargs)
        results = map(_evaluate_chunk, work)
    for x, y, index, mask in results:
        indexes[(x, y)] = index if mask else -math.inf
        masks[(x, y)] = mask

    with RustNoiseOracle() as oracle:
        points = [[x, y, indexes[(x, y)] ] for (x, y), present in masks.items() if present]
        grouped = oracle.request({
            "op": "territory_group",
            "points": points,
            "connectivity": args.connectivity,
            "minimum_size": args.minimum_size,
        })
        territory_id = {(entry["x"], entry["y"]): entry["id"] for entry in grouped}
        component_rows = []
        by_id = {}
        for entry in grouped:
            by_id.setdefault(entry["id"], []).append((entry["x"], entry["y"]))
        for ident, keys in sorted(by_id.items()):
            component_rows.append((indexes[keys[0]], keys))

    output = {
        "seed": args.seed,
        "center_chunk": [args.center_x, args.center_y],
        "radius_chunks": args.radius,
        "connectivity": args.connectivity,
        "minimum_size": args.minimum_size,
        "expression": args.expression,
        "mask_expression": args.mask_expression,
        "claim_chunks": sum(masks.values()),
        "guarded_chunks": len(territory_id),
        "territory_count": len(component_rows),
        "chunks": [
            {"x": x, "y": y, "t": territory_id.get((x, y), 0), "index": indexes[(x, y)] if masks[(x, y)] else None}
            for x, y in sorted(masks)
        ],
        "territories": [
            {
                "t": ident,
                "size": len(keys),
                "index": index,
                "centroid": [sum(x for x, _ in keys) / len(keys), sum(y for _, y in keys) / len(keys)],
                "bbox": [min(x for x, _ in keys), max(x for x, _ in keys),
                         min(y for _, y in keys), max(y for _, y in keys)],
            }
            for ident, (index, keys) in enumerate(component_rows, 1)
        ],
    }
    print(json.dumps(output, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
