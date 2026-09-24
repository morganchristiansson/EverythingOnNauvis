# Feature: noise-sandbox — statistical noise-expression simulator

Status: proposed — design request; pick up in a dedicated session.
Owner: `tools/noise-sandbox/` (new). Language: Ruby (preferred).

## Why

Factorio runtime Lua **cannot evaluate a noise expression**: `game.evaluate_expression`
does not exist in 2.0.77 (pcall-verified live via RCON on the LDW server). Fields
are only observable through what they render (tiles/entities), and the only way to
observe that is a headless probe (`--create` + stripped `script.dat` + `--benchmark`)
taking minutes per data point and returning a handful of aggregate numbers. The
"noise tools" mod renders fields as map-preview RGB colors only — no numeric
results, hacky to drive.

We keep needing numeric, field-level questions ("what is scrap land-coverage at
`control:scrap:frequency` 1/2/6?", "do ore patch fields overlap under this
expression change?", "how wide is this mask band in tiles?") that the probes can
answer only one slow aggregate at a time. A Ruby sandbox evaluates the expression
graphs directly: every metric is one evaluation sweep, seconds per grid.

## Approach

- **Lua = extraction only.** `--dump-data` already serializes every
  `noise-expression` and `noise-function` as strings
  (`<write-data>/script-output/data-raw-dump.json`): 336 `eon_*` expressions plus
  their transitive references (vulcanus/fulgora machinery the mod reuses). Import
  that JSON directly; do NOT run Lua inside Ruby.
- **Pipeline:** dump JSON → expression parser (LISP-ish `name{a=1, b="expr"}` plus
  arithmetic/comparison precedence) → name resolution (expression + function +
  `local_expressions`/`local_functions`, with the "parameters do NOT propagate into
  named references" semantic) → evaluator with per-cell memoization → statistical
  reporters (coverage, threshold crossings, band widths, cluster sizes).
- **Target: statistical equivalence to the engine, never bit-exact maps.**
  `basis_noise`/`spot_noise`/`random_penalty*` hashes are internal; matching them
  byte-for-byte is out of scope. Equivalence is verified against probe outputs
  (coverage %, patch size quantiles, per-tile placement ratios) across seeds.

## Primitive surface (evidence from the dump: what the eon_* trees actually touch)

- value noise: `basis_noise`, `multioctave_noise`, `quick_multioctave_noise`,
  `variable_persistence_multioctave_noise`, `amplitude_corrected_multioctave_noise`
- voronoi: `voronoi_cell_id`, `voronoi_pyramid_noise`, `voronoi_facet_noise`,
  `voronoi_spot_noise`
- spots: `spot_noise` — **defer to last**: candidate lattice, `region_size`,
  `hard_region_target_quantity`, `basement_value`, `maximum_spot_basement_radius`,
  `skip_span`/`skip_offset` partitioning, params must be compile-time constants
- helpers: `random_penalty`, `random_penalty_between`, `starting_spot_at_angle`,
  `range_select`/`range_select_base`, `slider_to_linear`, `slider_rescale`
- math/semantics: `clamp`, `lerp`, `min`, `max`, `if`, `abs`, `pow`, `log2`, `mod`,
  `-inf`/NaN rules — **must match the mod's sign-safety contract** (masks are
  `if(mask, -inf, expr)` replacements; `-inf * 0 = NaN`; never multiply a signed
  expression by something that can be `-inf`).
- local functions: `eon_aquilo_base`, `eon_fade`, `water_base`-style parameterized
  helpers (per-expression `local_functions`), and the at16/at{N,M} shift pattern.

## Acceptance criteria

- [ ] AC-1 **Parser:** resolves the full expression graph from a live
      `data-raw-dump.json` (all 336 `eon_*` + transitive refs incl.
      vulcanus/fulgora fields) without hand transcription.
- [ ] AC-2 **Primitives:** value-noise + voronoi + helpers evaluate with sane
      statistical output (mean/variance/correlation sanity checks per primitive).
- [ ] AC-3 **Calibration harness:** predicted placements (threshold crossings)
      vs probe-measured placements across ≥ 3 seeds; pinned tolerances. Baseline
      datum: scrap at seed 12345 radius 1600 — 17,795 entities @ freq 1 (1.23%
      land coverage), 49,980 @ freq 6 (3.46%); 0 scrap on top of ores; 0 deep-
      south-gleba/aquilo/water.
- [ ] AC-4 **Sweeps:** produces coverage-vs-`control:` curves (e.g. scrap
      frequency 1→6) that track the probe numbers within tolerance.
- [ ] AC-5 **Gate unchanged:** sandbox output never gates a release; the repo
      probe suite stays the only release gate for anything map-placing.

## Verification

```
# fixtures pinned from real generation (probe reports committed next to tool)
tools/noise-sandbox/spec/  (parser, semantics, -inf/NaN, primitive stats)
python3 tests/probe_scrap.py 12345 - 1600      # default-frequency baseline
python3 tests/probe_scrap.py 12345 tests/map-gen-settings-scrap-high.json 1600
```

## Known residuals / deliberate non-goals

- **No bit-exact maps** (hash-exactness out of scope; statistical equivalence is
  the contract).
- **No engine sampling semantics:** chunk-corner territory sampling, 2×2 entity
  grids vs per-tile rendering, tile-truth vs field offsets, the rim-quantization
  class (18 scrap on one volcano rim blip, 0.04%) — these live only in probes.
  The sandbox will happily compute things the real generator places differently.
- **No compile-time rules:** `spotNoise "expected a constant"`, params not
  propagating into named references — the sandbox may accept graphs the engine
  refuses to compile; anything that will be *placed* must pass the probes.
- **Noise "verbosity" and perf:** the engine's octave/persistence behavior is
  mostly hidden; multioctave variance MUST be calibrated, "looks right" is not
  enough.
## Session one plan (pick up here)

Goal: spine validation — reproduce the demolisher **claims** (per-chunk boolean:
`demolisher_territory_expression >= 0` sampled at each chunk's top-left corner
world point `(cx*32, cy*32)`) for one seed and score agreement against the
engine's ground truth (`tests/eon-verify-territory` + `verify_territory.py`
dump). Definition of done: ≥95% agree on claimed/unclaimed per chunk, and a
disagreement heatmap that localizes any remaining divergence (off-by-N-chunk =
lattice offset; random scatter = hash/seed; region bias = region_size/density).

1. Skeleton `tools/noise-sandbox/` (Ruby): JSON import + LISP-ish parser +
   resolver (expression/function/local tables) + evaluator + per-chunk claims
   for seed X.
2. Implement the territory spine primitives in order: value noise family
   (`basis_noise`, `multioctave_noise`, `eon_detail_noise_at`-style
   parameterized calls, `quick_`/`variable_persistence_` variants) → voronoi
   (`voronoi_cell_id`, `voronoi_pyramid_noise`, `voronoi_facet_noise`,
   `voronoi_spot_noise`) → `spot_noise` (engine builtin, implement natively;
   territory uses the SIMPLE config below).
3. Cross-check the claims grid against the fixture; publish the heatmap.
4. Only then: grouping algebra (`minimum_territory_size` drops, merge) as pure
   set math — this part is otherwise untestable headless (AGENTS.md).

### Territory spine facts (verified during the scrap session, seed 12345)

- `data.raw["noise-expression"]["demolisher_territory_expression"]` lives in
  `map-generation/enemies.lua` (line ~147); it wraps
  `eon_demolisher_mask_at16` + variation/lattice machinery in `terrain.lua`.
- `eon_terr_volcano_small/big` (terrain.lua ~1623/1628) =
  `eon_volcano_spots_at{x_offset=16, y_offset=16, seed=1|2, spacing_mult=1|1.8,
  size_mult=0.75|1.25}`. NOTE: the ±16 offsets compensate the chunk-corner
  territory sampling (NOT tile placement — do not reuse for tile-truth gates).
- `eon_volcano_spots_at` (terrain.lua 1571) is a noise-FUNCTION whose
  expression IS a `spot_noise` call: `candidate_spot_count = 1`,
  `suggested_minimum_candidate_point_spacing = volcano_spot_spacing *
  spacing_mult`, `skip_span = 1`, `skip_offset = 0`, `region_size =
  256 * density_multiplier`, density/quantity from locals (volcano_area,
  volcanism_sq, volcano_spot_size...), plus three `eon_detail_noise_at`
  wobble layers distorting x/y. The simplest realistic spot config — ideal
  first spot_noise calibration target.
- The mask chain `eon_vulcanus_core_at16` / `eon_updated_volcanic_folds_at16`
  etc. are plain expression arithmetic over the spot field.

### Data sources / fixtures (committed)

- `tools/noise-sandbox/fixtures/data-raw-noise-2.0.77.json` — the two noise
  tables (expression + function, incl. `local_expressions`/`local_functions`)
  extracted from a `--dump-data` run (factorio 2.0.77, EoN 0.1.12). 270KB.
  Gotchas: entries may have NUMERIC `expression` literals (not just strings);
  `spot_noise` and the raw noise/voronoi ops are ENGINE BUILTINS and appear
  only as callees, never in the tables.
- Control values: expressions read `var('control:...')` — the sandbox takes a
  map-gen-settings JSON as input (`map-gen-settings-eon-defaults.json`,
  `tests/map-gen-settings-scrap-high.json`).
- Claims ground truth: run `python3 tests/verify_territory.py <seed>` and
  consume its per-chunk membership output; pin one fixture per seed.

### Known calibration unknowns (deliberately not pre-solved)

- string `seed1` hashing (`basis_noise`, `voronoi_*`: `seed1 = 'name'`).
- `basis_noise` value-noise hash + interpolation.
- `spot_noise` candidate selection/quantity math for the count=1 config.
- All four are pinned by the claim-set agreement loop; do not hand-fit to make
  maps pretty — fit to the per-chunk booleans.

### Claims fixture (committed)

- `tools/noise-sandbox/fixtures/territory-claims-12345.json` — per-chunk
  territory index for seed 12345, generated with `tests/eon-verify-territory`
  (factorio 2.0.77, EoN 0.1.12). **Claim = `t > 0`** (t=0 = no territory).
  485 claimed / 13,085 chunks. The report also carries per-chunk 4px volcano
  masks (`s`) and corner/center tile names (`p`) — useful secondary signals.
- Caveat: the claim BOOLEANS are trustworthy; territory GROUPING is not
  (headless gives each claimed chunk its own territory object). Compare the
  sandbox against claims only; validate grouping algebra against real-game
  observations (screenshots) later.
