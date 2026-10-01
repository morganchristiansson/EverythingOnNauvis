#!/usr/bin/env python3
"""Compare two Factorio grouping reports by canonical territory shape."""
from __future__ import annotations

import hashlib
import json
import sys
from collections import Counter, defaultdict


def load(path: str) -> dict:
    with open(path, encoding="utf-8") as stream:
        return json.load(stream)


def chunk_map(report: dict) -> dict[tuple[int, int], dict]:
    return {(c["x"], c["y"]): c for c in report["chunks"]}


def volcano(chunk: dict) -> bool:
    return "s" in chunk and any(int(v) & 1 for row in chunk["s"].split("/") for v in row)


def lava(chunk: dict) -> bool:
    return "s" in chunk and any(int(v) & 2 for row in chunk["s"].split("/") for v in row)


def claimed(chunk: dict) -> bool:
    return int(chunk.get("t", 0)) > 0


def components(chunks: dict[tuple[int, int], dict], only_claimed: bool = True) -> int:
    remaining = {
        key for key, chunk in chunks.items()
        if not only_claimed or claimed(chunk)
    }
    count = 0
    while remaining:
        count += 1
        first = remaining.pop()
        territory = int(chunks[first]["t"])
        queue = [first]
        while queue:
            x, y = queue.pop()
            for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if neighbor in remaining and int(chunks[neighbor]["t"]) == territory:
                    remaining.remove(neighbor)
                    queue.append(neighbor)
    return count


def edges(chunks: dict[tuple[int, int], dict]) -> dict[str, int]:
    same = different = 0
    for (x, y), chunk in chunks.items():
        if not claimed(chunk):
            continue
        for neighbor in ((x + 1, y), (x, y + 1)):
            other = chunks.get(neighbor)
            if other and claimed(other):
                if int(chunk["t"]) == int(other["t"]):
                    same += 1
                else:
                    different += 1
    return {"same_territory_edges": same, "different_territory_edges": different}


def shapes(chunks: dict[tuple[int, int], dict]) -> dict[int, dict]:
    grouped: dict[int, list[tuple[int, int]]] = defaultdict(list)
    for key, chunk in chunks.items():
        if claimed(chunk):
            grouped[int(chunk["t"])].append(key)
    result = {}
    for territory, coordinates in grouped.items():
        coordinates.sort()
        digest = hashlib.sha256(json.dumps(coordinates, separators=(",", ":")).encode()).hexdigest()
        result[territory] = {
            "count": len(coordinates),
            "digest": digest,
            "bbox": [
                [min(x for x, _ in coordinates), max(x for x, _ in coordinates)],
                [min(y for _, y in coordinates), max(y for _, y in coordinates)],
            ],
        }
    return result


def shape_comparison(base: dict, candidate: dict) -> dict:
    b = shapes(base)
    c = shapes(candidate)
    b_by_digest = defaultdict(list)
    c_by_digest = defaultdict(list)
    for value in b.values():
        b_by_digest[value["digest"]].append(value)
    for value in c.values():
        c_by_digest[value["digest"]].append(value)
    common = set(b_by_digest) & set(c_by_digest)
    baseline_only = set(b_by_digest) - set(c_by_digest)
    candidate_only = set(c_by_digest) - set(b_by_digest)
    exact = sum(min(len(b_by_digest[d]), len(c_by_digest[d])) for d in common)
    return {
        "exact_shape_count": exact,
        "baseline_territory_count": len(b),
        "candidate_territory_count": len(c),
        "baseline_only_shape_count": len(baseline_only),
        "candidate_only_shape_count": len(candidate_only),
        "exact_shape_fraction": exact / max(len(b), len(c), 1),
        "baseline_only_examples": [b_by_digest[d][0]["bbox"] for d in sorted(baseline_only)[:5]],
        "candidate_only_examples": [c_by_digest[d][0]["bbox"] for d in sorted(candidate_only)[:5]],
    }


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: compare_territory_reports.py BASELINE.json CANDIDATE.json", file=sys.stderr)
        return 2
    baseline = load(sys.argv[1])
    candidate = load(sys.argv[2])
    b = chunk_map(baseline)
    c = chunk_map(candidate)
    if set(b) != set(c):
        raise SystemExit("reports cover different chunk sets")
    report = {
        "chunks": len(b),
        "baseline": {
            "territories": baseline["territory_count"],
            "claimed_chunks": sum(claimed(v) for v in b.values()),
            "components": components(b),
            **edges(b),
        },
        "candidate": {
            "territories": candidate["territory_count"],
            "claimed_chunks": sum(claimed(v) for v in c.values()),
            "components": components(c),
            **edges(c),
        },
        "territory_shapes": shape_comparison(b, c),
        "differences": {
            "changed_guarded_chunks": sum(claimed(b[k]) != claimed(c[k]) for k in b),
            "baseline_only_guarded": sum(claimed(b[k]) and not claimed(c[k]) for k in b),
            "candidate_only_guarded": sum(not claimed(b[k]) and claimed(c[k]) for k in b),
            "changed_volcanic_tile_masks": sum(volcano(b[k]) != volcano(c[k]) for k in b),
            "baseline_lava_chunks": sum(lava(v) for v in b.values()),
            "candidate_lava_chunks": sum(lava(v) for v in c.values()),
        },
    }
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
