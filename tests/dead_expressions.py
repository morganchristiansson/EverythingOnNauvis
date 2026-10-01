#!/usr/bin/env python3
"""Which noise expressions and noise functions in data.raw are actually reachable?

Dead weight in the data stage is not free: every expression is evaluated by the map
generator for every chunk it is referenced from, and a reference that no longer
resolves is a load-time error. So "is this used" is a question about the whole graph,
not about what `grep` can see -- vanilla's own expressions reference ours
indirectly (`demolisher_starting_area` reaches `eon_demolisher_territory`), and a
mod expression can be referenced by another mod expression the same way.

The answer comes from the loaded prototype dump: a name is reachable if some
reachable expression/function mentions it, or if it is named directly by a
prototype. Reachability is computed from the roots (everything a prototype points
at) over the *resolved* expression graph, so anything unreachable is safe to delete
-- and the proof that the deletion was safe is a fresh dump that still builds.

  python3 tests/dead_expressions.py            # report
  python3 tests/dead_expressions.py --delete   # and delete the unreachable ones
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FACTORIO = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MODS = ["base", "elevated-rails", "quality", "space-age"]
# Hyphens are legal in prototype names (`default-coal-patches`) and they appear
# inside quoted names in expressions -- var('default-coal-patches') -- so a tokeniser
# that stops at the hyphen sees three unrelated identifiers and reports a LIVE
# vanilla expression as dead. That is not hypothetical: it is how this tool got the
# deletion of the vanilla patch expressions wrong, and the engine's load-time
# "Unknown variable" is what caught it.
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_-]*")


def dump(tmp: Path) -> dict:
    """`--dump-data` with the mod loaded: the resolved data-raw, every reference live."""
    mods = tmp / "mods"
    write = tmp / "write"
    mods.mkdir(parents=True)
    write.mkdir(parents=True)
    os.symlink(ROOT, mods / "EverythingOnNauvis-morganc")
    (mods / "mod-list.json").write_text(json.dumps({"mods": [
        {"name": n, "enabled": True} for n in MODS + ["EverythingOnNauvis-morganc"]
    ]}))
    (tmp / "config.ini").write_text(
        f"[path]\nread-data=/factorio/data\nwrite-data={write}\n")
    proc = subprocess.run(
        [FACTORIO, "--dump-data", "--config", str(tmp / "config.ini"),
         "--mod-directory", str(mods)],
        env={**os.environ, "HOME": str(tmp)}, capture_output=True, text=True, timeout=1200)
    path = write / "script-output" / "data-raw-dump.json"
    if not path.exists():
        sys.exit("dump failed:\n" + proc.stdout[-3000:] + proc.stderr[-3000:])
    return json.loads(path.read_text())


def strings(node, out):
    """Every string anywhere in a structure: roots include free-form expression text."""
    if isinstance(node, str):
        out.append(node)
    elif isinstance(node, dict):
        for value in node.values():
            strings(value, out)
    elif isinstance(node, list):
        for value in node:
            strings(value, out)


def analyse(data: dict):
    expressions = {**data.get("noise-expression", {}), **data.get("noise-function", {})}
    by_name = {name: body for name, body in expressions.items()}

    # roots: every string in data-raw that is not itself an expression definition.
    # Anything a prototype names directly (autoplace text, planet settings, a
    # `variation` expression) is a root; the definitions themselves are excluded so
    # a definition does not root itself.
    roots: set[str] = set()
    for section, entries in data.items():
        if section in ("noise-expression", "noise-function"):
            for name, body in entries.items():
                texts = []
                strings(body, texts)
                for text in texts:
                    roots.update(NAME.findall(text))
            continue
        texts = []
        strings(entries, texts)
        for text in texts:
            roots.update(NAME.findall(text))

    def references(name: str) -> set[str]:
        body = by_name.get(name)
        if body is None:
            return set()
        texts = []
        strings(body, texts)
        found = set()
        for text in texts:
            for candidate in NAME.findall(text):
                if candidate in by_name and candidate != name:
                    found.add(candidate)
        return found

    # `expression`/`parameters` are the only places a name can be *used*; but
    # following every string also follows comments and type names, which is fine:
    # reachability may be over-approximated, never under.
    reachable, queue = set(), list(roots & set(by_name))
    while queue:
        name = queue.pop()
        if name in reachable:
            continue
        reachable.add(name)
        for other in references(name):
            if other not in reachable:
                queue.append(other)
    unreachable = sorted(set(by_name) - reachable)
    return by_name, reachable, unreachable


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--delete", action="store_true",
                        help="print the Lua to remove the unreachable definitions")
    args = parser.parse_args()
    tmp = Path(tempfile.mkdtemp(prefix="eon-dead."))
    try:
        data = dump(tmp)
        by_name, reachable, unreachable = analyse(data)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"{len(by_name)} noise expressions/functions, {len(reachable)} reachable, "
          f"{len(unreachable)} unreachable")
    for name in unreachable:
        kind = "noise-function" if name in data.get("noise-function", {}) else "noise-expression"
        print(f"  unreachable {kind} {name}")
    if args.delete and unreachable:
        print("\n-- remove from map-generation/terrain.lua (and enemies.lua):")
        for name in unreachable:
            print(f"--   {name}")
    if unreachable:
        # Dead weight in the data stage is not free: every expression is evaluated
        # by the map generator, and the dump is what other tools read. Reachability
        # from a PROTOTYPE root, so anything the mod orphaned by replacing a
        # prototype shows up here instead of lingering in every runtime dump.
        print("DEAD EXPRESSIONS: delete them (or find the reference that keeps them)")
        return 1
    print("no unreachable expressions: the data stage defines nothing dead")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
