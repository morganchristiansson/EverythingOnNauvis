# Noise sandbox handoff

## Current architecture

- Numerical source of truth: the FactorioMapWebUI fork under
  `vendor/FactorioMapWebUI`.
- Fork remotes:
  - `origin`: `morganchristiansson/FactorioMapWebUI`
  - `upstream`: `FactoryGameFan/FactorioMapWebUI`
- Local branch: `eon-oracle`.
- Do not push or open PRs without Morgan's explicit approval.
- The main repository's Ruby implementation has been removed: it was the first
  evaluator, it is referenced by nothing, and no gate ran it.
- Active tooling is Python plus the Rust `fmw-oracle` binary in the fork.

## Fork commits

```text
2dd7dce Group territory index components in the oracle
161fd39 Expose f32 spot cone evaluation through the oracle
140fd4a Expose spot candidate operations through the oracle
26bb3fe Document the fmw oracle protocol
626d91c Add generic JSONL noise oracle binary
```

Build:

```sh
cargo build \
  --manifest-path tools/noise-sandbox/vendor/FactorioMapWebUI/Cargo.toml \
  -p fmw-oracle
```

Python client and simulator:

```text
tools/noise-sandbox/python/eon_noise_oracle.py
tools/noise-sandbox/python/eon_expression.py
tools/noise-sandbox/python/simulate_territory.py
tools/noise-sandbox/python/compare_territory_reports.py
tools/noise-sandbox/python/calibrate_territory_grouping.py
tools/noise-sandbox/python/analyze_splits.py
```

## Important results

The default seed-12345 claim fixture is an exact 13,085-chunk match:

```text
expected claims: 485
predicted claims: 485
TP=485 FP=0 FN=0 TN=12600
```

The 600%-volcanism raw claim mask also matches exactly:

```text
3546 / 3546
```

The remaining problem is final territory identity. The grouping probe was fixed
to generate missing `LuaTerritory:get_chunks()` members and now reports zero
ungenerated members. The current Rust grouping model matches the eligible
140 generated shapes with 4-connectivity in the latest calibration, but the
full final object count still needs an exact explanation for the remaining
small/disconnected LuaTerritory objects.

Fast candidate evaluation from an existing raw report:

```sh
PYTHONPATH=tools/noise-sandbox/python \
python3 tools/noise-sandbox/python/simulate_vertical_cell.py \
  /tmp/sim-high-raw-c4.json \
  --settings tests/map-gen-settings-high-volcanism.json \
  --seed 12345 --output /tmp/sim-vcell.json
```

This evaluates only the extra cell/size fields and runs the corrected vertical
cell split in about a second; it is an experiment, not the current expression.

Offline split experiment on the Rust-grouped high-volcanism simulation
(components size 3–100, bounding-box fill >= 0.65 as compact/isolated
candidates):

```text
93 candidate components
safe vertical bbox split: 169 territories, 0 sub-3 pieces
safe vertical centroid split: 173 territories, 0 sub-3 pieces
safe 4-way pie split: 243 territories, 0 sub-3 pieces
```

This favors a guarded vertical split over pie wedges. It remains an offline
target layout, not a production expression.

## Probe fixes

`tests/eon-probe-grouping/control.lua` now:

- generates an outer margin;
- requests missing territory-member chunks;
- repeats generation passes;
- filters ungenerated members;
- reports generation diagnostics.

Do not compare reports from different settings or different probe formats.
Keep the actual grouping report and the minimum-size-0 simulated report from
the same seed/settings.

## Handoff probes

Run the expression graph probe:

```sh
PYTHONPATH=tools/noise-sandbox/python \
python3 tools/noise-sandbox/python/probe_expressions.py \
  --output /tmp/eon-expression-probe.json
```

Run the territory simulator (the report includes each component's centroid and
bounding box, which are the candidate vertical/pie anchors):

```sh
PYTHONPATH=tools/noise-sandbox/python \
python3 tools/noise-sandbox/python/simulate_territory.py \
  --settings tests/map-gen-settings-high-volcanism.json \
  --seed 12345 \
  --center-x=-3 --center-y=-26 --radius=64 \
  --minimum-size 3 --workers 1
```

Compare an actual report with a simulated report:

```sh
python3 tools/noise-sandbox/python/compare_territory_reports.py \
  actual-grouping.json simulated.json
```

Calibrate grouping rules offline:

```sh
python3 tools/noise-sandbox/python/calibrate_territory_grouping.py \
  simulated-min0.json actual-grouping.json --minimum-size 3
```

## Do not do

- Do not use aggregate counts as proof of identical territories.
- Do not use numeric territory IDs as stable IDs.
- Do not compare a default-settings claim fixture with a 600% report.
- Do not commit generated reports, heatmaps, Rust target directories, or
  Python caches.
- Do not change the EoN production territory expression until the Rust
  coordinate-set comparison is exact.
