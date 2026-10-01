#!/usr/bin/env python3
"""Rank offline territory-grouping rules against one actual Factorio report.

The predicted report must be produced with --minimum-size 0 so it retains the
raw index for every claimed chunk. This tool changes only the grouping rule; it
does not change the noise evaluation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import defaultdict


def load(path: str) -> dict:
    with open(path, encoding="utf-8") as stream:
        return json.load(stream)


def coordinates(report: dict) -> dict[tuple[int, int], dict]:
    return {(int(c["x"]), int(c["y"])): c for c in report["chunks"]}


def digest(values: list[tuple[int, int]]) -> str:
    return hashlib.sha256(repr(sorted(values)).encode()).hexdigest()


def grouped_shape_digests(values: dict[tuple[int, int], float], connectivity: int,
                          quantizer: str, minimum: int) -> set[str]:
    groups: dict[object, set[tuple[int, int]]] = defaultdict(set)
    for key, value in values.items():
        if value is None or not math.isfinite(value) or value < 0:
            continue
        if quantizer == "floor":
            group = math.floor(value)
        elif quantizer == "round":
            group = round(value)
        elif quantizer == "floor10":
            group = math.floor(value * 10)
        elif quantizer == "floor100":
            group = math.floor(value * 100)
        else:
            group = value
        groups[group].add(key)
    offsets = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    if connectivity == 8:
        offsets += [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    result = set()
    for keys in groups.values():
        while keys:
            queue = [next(iter(keys))]
            component = []
            while queue:
                current = queue.pop()
                if current not in keys:
                    continue
                keys.remove(current)
                x, y = current
                component.append((x, y))
                for dx, dy in offsets:
                    neighbor = (x + dx, y + dy)
                    if neighbor in keys:
                        queue.append(neighbor)
            if len(component) >= minimum:
                result.add(digest(component))
    return result


def actual_shape_digests(report: dict, minimum: int) -> set[str]:
    values = coordinates(report)
    return grouped_shape_digests(
        {key: float(chunk["t"]) for key, chunk in values.items() if int(chunk["t"]) > 0},
        4, "exact", minimum,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("predicted", help="simulate_territory.py report with minimum-size 0")
    parser.add_argument("actual", help="eon-probe-grouping report")
    parser.add_argument("--minimum-size", type=int, default=3)
    args = parser.parse_args()
    predicted = load(args.predicted)
    actual = load(args.actual)
    target = actual_shape_digests(actual, args.minimum_size)
    predicted_values = {
        (int(c["x"]), int(c["y"])): c.get("index")
        for c in predicted["chunks"]
        if c.get("index") is not None
    }
    rows = []
    for connectivity in (4, 8):
        for quantizer in ("exact", "floor", "round", "floor10", "floor100"):
            shapes = grouped_shape_digests(predicted_values, connectivity, quantizer, args.minimum_size)
            rows.append({
                "connectivity": connectivity,
                "quantizer": quantizer,
                "predicted_shapes": len(shapes),
                "actual_shapes": len(target),
                "exact_shapes": len(shapes & target),
                "actual_only": len(target - shapes),
                "predicted_only": len(shapes - target),
                "exact_fraction": len(shapes & target) / max(len(target), 1),
            })
    rows.sort(key=lambda row: (row["exact_shapes"], -row["actual_only"], -row["predicted_only"]), reverse=True)
    print(json.dumps({"minimum_size": args.minimum_size, "ranking": rows}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
