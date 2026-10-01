#!/usr/bin/env python3
"""Refuse a Lua file that defines the same function name twice.

Three bugs in one session were a SECOND definition of a function silently shadowing
the one just written: a second `cone_disc`, a second `radius_at`, a second
`point_on_ray`. In Lua the later definition wins, so the new code simply never ran
-- and every gate stayed green, because a duplicate local is invisible to a test
that only exercises behaviour. Each one cost a round of "the fix did nothing".

In every case the second definition was a leftover of an edit that replaced a
function but not its neighbour, so the shape of the mistake is always the same:
`function M:name` / `local function name` / `function name(` appearing twice in one
file. That is cheap to detect and impossible to see by reading, so it is a check.

Deliberately narrow: it reads file text, not Lua, so it needs no interpreter and no
Factorio. It is not a style linter -- it looks only for a repeated definition.

Usage:
    python3 tests/lint_duplicate_functions.py [path ...]
"""
from __future__ import annotations

import os
import re
import sys

# `function M:name(` and `function name(` and `local function name(`. The receiver
# form matters: two of the three shadowing bugs were `function Field:cone_disc` and
# a first pass of this regex that stopped at the colon would have missed them.
DEFINITION = re.compile(
    r"^\s*(?:local\s+)?function\s+([A-Za-z_][A-Za-z0-9_.]*)(?::([A-Za-z_][A-Za-z0-9_]*))?\s*\(",
    re.M)
# `M:name = function(` is a definition too.
ASSIGNED = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_.]*)\s*=\s*function\s*\(", re.M)

DEFAULT_PATHS = ("noise-mirror", "tests", ".")
SKIP_DIRS = {".git", ".pi", "versions", "vendor", "tools"}


def lua_files(paths: list[str]) -> list[str]:
    found: list[str] = []
    for path in paths:
        if os.path.isfile(path) and path.endswith(".lua"):
            found.append(path)
            continue
        for root, dirs, files in os.walk(path):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for name in files:
                if name.endswith(".lua"):
                    found.append(os.path.join(root, name))
    return sorted(set(found))


def duplicates(path: str) -> list[tuple[str, int]]:
    """Names defined more than once, with the line of the second definition."""
    text = open(path, encoding="utf-8", errors="replace").read()
    # Commented-out code is not code.
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    text = re.sub(r"--[^\n]*", "", text)
    seen: dict[str, int] = {}
    found: list[tuple[str, int]] = []
    hits: list[tuple[str, int]] = []
    for match in DEFINITION.finditer(text):
        receiver, member = match.group(1), match.group(2)
        hits.append((f"{receiver}:{member}" if member else receiver, match.start()))
    for match in ASSIGNED.finditer(text):
        hits.append((match.group(1), match.start()))
    for name, offset in hits:
        line = text[:offset].count("\n") + 1
        if name in seen:
            found.append((name, line))
        else:
            seen[name] = line
    return found


def main() -> int:
    paths = sys.argv[1:] or list(DEFAULT_PATHS)
    files = lua_files(paths)
    failures = 0
    for path in files:
        for name, line in duplicates(path):
            failures += 1
            print(f"  [FAIL] {path}:{line} defines {name} again -- Lua keeps the "
                  f"LATER one, so whatever was written above is dead")
    if failures:
        print(f"\n{failures} duplicate function definition(s)")
        return 1
    print(f"  [PASS] no duplicate function definitions in {len(files)} Lua files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
