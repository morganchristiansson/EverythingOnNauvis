# Active Python/Rust noise tooling

The archived Ruby sandbox is not the active engine.

The active split is:

- `../vendor/FactorioMapWebUI/crates/fmw-oracle/`: the generic JSONL process
  backed by the fork's `fmw-noise` implementation.
- `eon_noise_oracle.py`: Python batch client using newline-delimited JSON.
- `compare_territory_reports.py`: exact per-chunk and canonical territory-shape
  comparison for real probe reports.
- Factorio probe drivers and report orchestration: Python.

Build the local oracle from the repository root:

```sh
cargo build --manifest-path tools/noise-sandbox/vendor/FactorioMapWebUI/Cargo.toml -p fmw-oracle
```

The current primitive protocol supports:

- `basis_noise`
- `multioctave_noise`
- `variable_persistence_multioctave_noise`
- `voronoi_cell_id`
- `random_penalty`
- `spot_candidates`
- `spot_select`

Example:

```python
from eon_noise_oracle import RustNoiseOracle

with RustNoiseOracle() as oracle:
    value = oracle.basis_noise(0.125, 0.125, 12345, 342)
```

The Rust fork is the sole owner of Factorio numerical primitives; Python owns
the EoN graph, candidate-point orchestration, probe reports, and exact
per-chunk comparisons. Python must not duplicate the noise algorithms.

Simulate the shipped territory index over chunk-corner samples with:

```sh
PYTHONPATH=tools/noise-sandbox/python \
python3 tools/noise-sandbox/python/simulate_territory.py \
  --seed 12345 --center-x=-3 --center-y=-26 --radius=64
```

The result is a coordinate-addressable report with one simulated territory ID
per connected index component. Grouping is performed by the Rust oracle, not
Python. The current production-index comparison uses 4-neighbour components by
default because that matched the high-volcanism probe; `--connectivity 8`
remains available for A/B experiments. It is the input to the shape comparator
below.

Probe every dumped named expression through the Rust-backed evaluator:

```sh
PYTHONPATH=tools/noise-sandbox/python \
python3 tools/noise-sandbox/python/probe_expressions.py \
  --radius 1 --output /tmp/eon-expression-probe.json
```

The report records finite-value statistics and unsupported graph paths; it is
a migration diagnostic, not a release gate.

Rank grouping rules offline against one actual report:

```sh
python3 tools/noise-sandbox/python/calibrate_territory_grouping.py \
  predicted-min0.json actual-grouping.json
```

This compares 4/8-connectivity and several index-quantization hypotheses
without starting Factorio again. It is the next calibration step before
changing the territory expression.

Compare two reports from the same probe mod/settings with:

```sh
python3 tools/noise-sandbox/python/compare_territory_reports.py \
  baseline.json candidate.json
```

The comparison canonicalizes each territory by its sorted chunk-coordinate set;
numeric territory IDs are never assumed to be stable across runs.
