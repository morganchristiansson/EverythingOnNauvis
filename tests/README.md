# tests/ — probes, verifiers & dev mods

All probes share one headless flow (see "How every probe runs" below). Most
probes are paired: a driver (`probe_*.py`) + a dev-only mod (`eon-*-probe/`)
whose `control.lua` runs in `on_init` and writes a JSON report into
`write/script-output/`.

## Active probes (use these)

| tool | mod | question it answers | run |
|---|---|---|---|
| `probe_split_grouping.py` | `eon-probe-grouping` | **Dedicated demolisher-territory E2E**: leaks, unguarded-lava quota, split layout / sizes / islands via LuaTerritory `get_chunks()/get_segmented_units()` | `python3 tests/probe_split_grouping.py [seed] [settings.json]` |
| `verify_territory.py` | `eon-verify-territory` | ground truth: per-chunk territory + 4px volcano/lava/water mask, patrol points, demolishers | `python3 tests/verify_territory.py [seed] [settings.json]` |
| `probe_calcite.py` | `eon-probe-calcite` | calcite e2e (this also houses the older territory-size guard) | `python3 tests/probe_calcite.py [seed] [settings.json] [radius]` |
| `verify_tungsten.py` | `eon-verify-tungsten` | tungsten coverage vs territory | `python3 tests/verify_tungsten.py [seed] [settings.json]` |
| `probe_geometry.py` | `eon-probe-geometry` | territory index sampling geometry (chunk-corner lattice) | `python3 tests/probe_geometry.py <probe-name>` |
| `probe_baseline.py` | `eon-probe-baseline` | merged-map vs vanilla baselines (for EON/GLEBA modes) | `python3 tests/probe_baseline.py` |
| `probe_decoratives.py` | `eon-probe-decoratives` | decorative boundaries by transition, not tile names | `python3 tests/probe_decoratives.py` |
| `probe_fruit.py` | `eon-probe-fruit` | gleba fruit placement | `python3 tests/probe_fruit.py` |
| `run_tests.py` | — | `--dump-data` data.raw assertions (fast, CI-able) | `python3 tests/run_tests.py` |

## Evidence / scratch (archived, not shipped)

Session probes that produced the numbers behind the shipped features (the
field-gradient split mechanism, the lattice-anchor negative result, merge
statistics) are NOT committed — they live only in the session that ran them.
The shipped E2Es reproduce the claims: `probe_split_grouping.py` asserts the
layout, `probe_geometry.py` the sampling geometry.

## Map-gen settings fixtures

- `map-gen-settings-user.json` — user's playtest map (volcanism 200%): the *shipped-config* probe input.
- `map-gen-settings-high-volcanism.json` — stress map (600%): used across probes.
- `map-gen-settings-geyser-high.json` / `-no-volcanism.json` — feature-specific probes.

## How every probe runs (headless, verified 2.0.77)

1. `--create save.zip` does NOT run control scripts; the save then ships a
   `script.dat` marking storage initialised → **strip `script.dat`** (zipfile:
   rezip all entries except it) so `on_init` fires on load.
2. Load with `--benchmark save.zip`; `on_init` does everything:
   `surface.request_to_generate_chunks(pos_tiles, radius_chunks)` +
   `surface.force_generate_chunk_requests()` (blocks synchronously), scan,
   `helpers.write_file` → `<write>/script-output/<probe>.json`.
3. Coord gotcha: `request_to_generate_chunks` takes Tiles+chunk radius;
   `is_chunk_generated`/`get_territory_for_chunk` take ChunkPositions.

See `features/` for the requirement contracts these probes verify.