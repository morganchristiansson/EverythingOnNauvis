#!/usr/bin/env python3
"""Offline volcano-territory split geometry lab.

Input is a simulate_territory.py report with minimum-size 0. Each claimed
component is treated as one candidate territory. This measures geometry only;
it does not claim that a connected-component center is available to a Factorio
noise expression.
"""
from __future__ import annotations

import argparse
import json
import math
from collections import Counter, defaultdict


def load(path: str) -> dict:
    with open(path, encoding="utf-8") as stream:
        return json.load(stream)


def components(report: dict) -> list[list[tuple[int, int]]]:
    groups: dict[int, list[tuple[int, int]]] = defaultdict(list)
    for chunk in report["chunks"]:
        if int(chunk.get("t", 0)) > 0:
            groups[int(chunk["t"])].append((int(chunk["x"]), int(chunk["y"])))
    return list(groups.values())


def split_stats(parts: list[list[tuple[int, int]]], minimum: int) -> dict:
    sizes = sorted(len(part) for part in parts if part)
    return {
        "territories": len(parts),
        "minimum_part_size": min(sizes) if sizes else 0,
        "median_part_size": sizes[len(sizes) // 2] if sizes else 0,
        "parts_below_minimum": sum(size < minimum for size in sizes),
        "chunks_below_minimum": sum(size for size in sizes if size < minimum),
        "empty_parts": sum(not part for part in parts),
    }


def safe_vertical(parts: list[list[tuple[int, int]]], minimum: int) -> list[list[tuple[int, int]]]:
    return parts if all(not part or len(part) >= minimum for part in parts) else [sum(parts, [])]


def safe_pie(parts: list[list[tuple[int, int]]], minimum: int) -> list[list[tuple[int, int]]]:
    return parts if all(not part or len(part) >= minimum for part in parts) else [sum(parts, [])]


def vertical(component: list[tuple[int, int]], mode: str) -> list[list[tuple[int, int]]]:
    if mode == "bbox":
        center = (min(x for x, _ in component) + max(x for x, _ in component)) / 2
    else:
        center = sum(x for x, _ in component) / len(component)
    return [
        [point for point in component if point[0] <= center],
        [point for point in component if point[0] > center],
    ]


def pie(component: list[tuple[int, int]], wedges: int) -> list[list[tuple[int, int]]]:
    center_x = sum(x for x, _ in component) / len(component)
    center_y = sum(y for _, y in component) / len(component)
    parts = [[] for _ in range(wedges)]
    for point in component:
        angle = (math.atan2(point[1] - center_y, point[0] - center_x) + math.tau) % math.tau
        parts[min(wedges - 1, int(angle / math.tau * wedges))].append(point)
    return parts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report")
    parser.add_argument("--minimum-size", type=int, default=3)
    args = parser.parse_args()
    groups = components(load(args.report))
    results = {}
    for mode in ("bbox", "centroid"):
        layouts = [vertical(group, mode) for group in groups]
        results[f"vertical_{mode}"] = split_stats([part for layout in layouts for part in layout], args.minimum_size)
        safe = [safe_vertical(layout, args.minimum_size) for layout in layouts]
        results[f"vertical_{mode}_safe"] = split_stats([part for layout in safe for part in layout], args.minimum_size)
    for wedges in (2, 4, 8):
        layouts = [pie(group, wedges) for group in groups]
        results[f"pie_{wedges}"] = split_stats([part for layout in layouts for part in layout], args.minimum_size)
        safe = [safe_pie(layout, args.minimum_size) for layout in layouts]
        results[f"pie_{wedges}_safe"] = split_stats([part for layout in safe for part in layout], args.minimum_size)
    compact = []
    for group in groups:
        xs = [x for x, _ in group]
        ys = [y for _, y in group]
        area = (max(xs) - min(xs) + 1) * (max(ys) - min(ys) + 1)
        fill = len(group) / area if area else 1.0
        if len(group) <= 150 and fill >= 0.45:
            compact.append((group, fill))
    results["input"] = {
        "components": len(groups),
        "component_size_histogram": dict(sorted(Counter(len(group) for group in groups).items())),
        "compact_candidates": len(compact),
    }
    results["compact_candidate_details"] = []
    for group, fill in sorted(compact, key=lambda item: len(item[0])):
        xs = [x for x, _ in group]
        ys = [y for _, y in group]
        details = {"chunks": len(group), "fill": round(fill, 3),
                   "bbox": [min(xs), max(xs), min(ys), max(ys)]}
        for mode in ("bbox", "centroid"):
            parts = vertical(group, mode)
            details[f"vertical_{mode}"] = split_stats(parts, args.minimum_size)
            details[f"vertical_{mode}_safe"] = split_stats([safe_vertical(parts, args.minimum_size)], args.minimum_size)
        details["pie_4_safe"] = split_stats([safe_pie(pie(group, 4), args.minimum_size)], args.minimum_size)
        results["compact_candidate_details"].append(details)
    print(json.dumps(results, indent=2, default=dict))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
