"""The noise catalog the Python gates read, generated on demand.

spot_mirror_parity.py and density_parity.py do not load the mod. They read a
slice of a factorio --dump-data run:

    tools/noise-sandbox/fixtures/data-raw-noise-2.0.77.json

so editing map-generation/terrain.lua does not reach them. That is how
density_parity came to print "sign agreement: 480/480 (100.00%)" for the
expression it had just been changed away from -- a green that says nothing, which
is the most expensive kind of wrong. And the drift was not one commit: the stale
catalog still carried ten noise expressions deleted long ago.

So the catalog is a build artifact, not source, and it is NOT committed. It is
regenerated whenever any mod source file is newer than it, which makes a stale
read impossible rather than something to remember:

    import noise_fixture; noise_fixture.ensure()

Run it by hand to see what changed:

    python3 tests/noise_fixture.py
"""

import json
import os
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURE = os.path.join(ROOT, "tools", "noise-sandbox", "fixtures",
                       "data-raw-noise-2.0.77.json")
# Only the noise tables: the tools evaluate expression TEXT, and the rest of
# data.raw is megabytes they never read.
TABLES = ("noise-expression", "noise-function")
VERSION = "2.0.77"
SOURCE = ("--dump-data with EverythingOnNauvis-morganc + space-age; noise tables only")

# Directories that are not the mod: the dev-only tests and the archived sandbox
# contain .lua files that do not reach data.raw.
SKIP_DIRS = {"tests", "tools", ".git", "versions", ".pi"}


def mod_sources():
    """Every source file that can change what the mod compiles to."""
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if name.endswith((".lua", ".json")):
                yield os.path.join(base, name)


def is_stale():
    if not os.path.exists(FIXTURE):
        return True
    written = os.path.getmtime(FIXTURE)
    return any(os.path.getmtime(path) > written for path in mod_sources())


def refresh(report=True):
    """Dump the data stage with the mod enabled and rewrite the catalog.

    Reports every difference, so a gate result can be read against a catalog
    whose contents are known rather than assumed.
    """
    from run_tests import run_dump_data

    old = None
    if os.path.exists(FIXTURE):
        with open(FIXTURE) as f:
            old = json.load(f)

    if report:
        print("dumping data.raw with the mod enabled ...")
    with tempfile.TemporaryDirectory() as base:
        dump = run_dump_data(base)

    missing = [table for table in TABLES if table not in dump]
    if missing:
        raise RuntimeError("the dump has no %s -- is the mod loaded?"
                           % ", ".join(missing))

    if report and old is not None:
        for label, names in (("REMOVED", _diff(old, dump, lambda a, b: (a or False) and not b)),
                             ("CHANGED", _diff(old, dump, lambda a, b: a and b and a != b)),
                             ("ADDED", _diff(old, dump, lambda a, b: b and not a))):
            for name in names:
                print("  %-8s %s" % (label, name))

    catalog = {"factorio_version": VERSION, "source": SOURCE}
    catalog.update({table: dump[table] for table in TABLES})
    os.makedirs(os.path.dirname(FIXTURE), exist_ok=True)
    with open(FIXTURE, "w") as f:
        json.dump(catalog, f)
    return catalog


def _diff(old, new, keep):
    names = []
    for table in TABLES:
        before, after = old.get(table) or {}, new[table]
        for name in set(before) | set(after):
            a, b = before.get(name), after.get(name)
            entry = a if isinstance(a, dict) else a
            other = b if isinstance(b, dict) else b
            if keep(entry, other):
                names.append("%s:%s" % (table, name))
    return sorted(names)


def ensure():
    """Regenerate the catalog if it is missing or older than the mod source."""
    if is_stale():
        stamp = time.strftime("%H:%M:%S")
        print("[noise_fixture] regenerating (%s) -- the catalog is older than the "
              "mod source, or absent" % stamp)
        catalog = refresh(report=False)
        print("[noise_fixture] %d expressions, %d functions"
              % (len(catalog["noise-expression"]), len(catalog["noise-function"])))
    return FIXTURE


if __name__ == "__main__":
    catalog = refresh()
    print("wrote %s (%d expressions, %d functions)"
          % (os.path.relpath(FIXTURE, ROOT), len(catalog["noise-expression"]),
             len(catalog["noise-function"])))
    print("now run: python3 tests/density_parity.py && "
          "python3 tests/spot_mirror_parity.py --radius 12")
