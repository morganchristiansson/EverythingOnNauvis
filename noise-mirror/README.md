# noise-mirror — a runtime mirror of EoN's volcano cones

A standalone Lua implementation of one question:

> for this chunk, **which EoN volcano cone owns it, and how wide is that cone?**

It is the runtime stand-in for something the noise-expression API cannot answer.
`spot_noise` returns a cone HEIGHT; it never returns which of its selected spots
produced that height, so the shipped `demolisher_territory_expression` can only
claim chunks with a cell id and a field threshold. The mirror recovers the
missing identity and then hands whole territories to
`surface.create_territory`.

Nothing in this directory touches Factorio. It is plain Lua, and this directory
is exactly the closure the game loads: `control.lua` requires
`volcano-territory.lua`, which requires `noise-mirror.volcano-cones`, and nothing
else here is reachable from that. A file only belongs here if the game requires
it; the tests, the benchmark and the dump tool live in `../tests/noise-mirror/`
and are excluded from the release zip by `python/create_zip.py`. Run them with
any `lua` binary:

```sh
lua tests/noise-mirror/selftest.lua          # 35 assertions, no dependencies
lua tests/noise-mirror/bench.lua             # the map-reset workload
lua tests/noise-mirror/dump.lua 12345 2 1 -3 -26 8   # per-chunk owner/width/value
```

`../volcano-territory.lua` is the only Factorio-facing part; `../control.lua`
wires it to `on_chunk_generated`.

## What is reproduced, and what is deliberately not

EoN's cones come from two `spot_noise` systems (`eon_volcano_spots_at` with
seed1 1 and 2, merged by `eon_mountain_volcano_spots`) with
`candidate_spot_count = 1`, `skip_span = 1`, `skip_offset = 0` and
`hard_region_target_quantity = 0`. On that configuration the engine's spot
selection collapses to three things:

| question | answer | cost |
| --- | --- | --- |
| where is the cone? | the first dart-throw-accepted candidate of the region's taus88 stream | integer RNG, no noise |
| how wide is it? | `min(maximum_spot_basement_radius, spot_radius_expression)` = `300 * volcanism * sqrt(1 + size) * size_mult * eon_volcano_size_dist(centre)` | one 3-octave `multioctave_noise` per cone |
| does it exist? | the engine's own spot density at the candidate, ported in `density.lua` | one evaluation per region, once |

**The claim is NOT the engine's field rule.** The field is `MAX(basement 0, cone
values)` and, because EoN keeps `quantity = radius²`, the winner is the cone with the
smallest normalised distance `d/width`. That is the wrong answer for a CLAIM: a small
cone beside a big one wins a huge bite out of the middle of the big one's disc, since
its own centre is very near zero and the big one's is not. Measured on a 3-series
(seed 3526581861, 200%): the big cone came out a crescent with a 31%-wide patrol loop
and the middle cone got no territory at all.

So a chunk is owned by the **nearest centre** among the cones whose ground covers it —
the perpendicular bisector between two cone centres. That keeps every claim containing
its own centre, and puts a circle of half the distance to the nearest rival *inside* the
claim by construction, which is what makes a patrol loop possible without a search. The
owned chunk set is **closed**: it is computed once, from geometry alone, and handed to
`create_territory` in a single call with no waiting and no re-creation.

Not mirrored, on purpose:

* **the per-tile field rendering, including the spot-deployment warp**
  (`eon_detail_noise_at` on the query, up to ~25 tiles). A territory is a
  chunk-quantised disc; `tests/spot_mirror_parity.py` measures what dropping it
  costs — 0.8–3% of chunks change owner, always within one chunk of a cone's rim.
* **the biome noise, starting spots, lava and tile ranges.** They decide which
  ground is volcano ground, and the game has already rendered that: the wiring
  reads the tiles instead of re-deriving a 5-octave biome noise per cone.
* **the spot-selection phases that are the identity at count = 1** (skip sets,
  the favorability sort, the trim, the hard-target cone shrink). The
  configuration is asserted in `new_volcanoes`, not assumed silently.

## Files

| file | what it is |
| --- | --- |
| `basis-gradient-table.lua` | the 256 game-recovered gradient directions, copied once from the oracle and checked by `tests/noise-mirror/selftest.lua` against game-captured vectors |
| `noise-primitives.lua` | `basis_noise` (the Better-Gradient-Noise kernel and its per-seed tables) and the `multioctave_noise` built on it, with prepared, cached instances — building one runs four 256-entry shuffles, ~50x the cost of reusing it |
| `spot-candidates.lua` | the per-region taus88 candidate stream (centres are integers: exact) |
| `volcano-cones.lua` | **the answer**: cone identity, centre, effective width, per-chunk ownership, closed footprints, the injected existence gate |

Nothing else belongs here: everything listed above is reachable from
`control.lua`, and a file that is not has no business shipping. The self test
(`../tests/noise-mirror/selftest.lua`, with its game-captured `vectors.lua`), the
benchmark and the dump tool are the dev-only remainder.

## Precision

The game evaluates the noise chain in f32 after every operation; Lua has only
doubles, so this port is f64 throughout. Measured against the engine's own
selection through the oracle (`tests/spot_mirror_parity.py`, four
seed/frequency/size configurations, ~2 500 chunks):

* cone identity: **0 unexplained mismatches**;
* effective width: worst relative error **2.8e-06**;
* field value at the chunk corner: worst error **2.7e-06**.

## Performance

`lua tests/noise-mirror/bench.lua` — 40 000 chunks, streamed row by row the way
generation delivers them:

| pass | cost |
| --- | --- |
| volcano setup (all prepared noise) | ~2 ms |
| chunk owner, cold | ~2.4 µs/chunk |
| owner of a chunk, cold (the `control.lua` path) | ~0.6 µs/chunk |
| one cone's closed chunk set | ~0.1 ms |

The caches are what make this flat: prepared noise instances, a per-region cone
cache, and a per-region ring cache for "which cones can reach here" (dropped
whenever a region is still undecided, so a late cone is never missed).

## Verifying it

```sh
# 1. the mirror against GAME-captured vectors and its own invariants (no deps)
lua tests/noise-mirror/selftest.lua

# 2. the mirror against the ENGINE's own selection, via the Rust oracle and the
#    shipped noise-expression prototypes
python3 tests/spot_mirror_parity.py --radius 14
python3 tests/spot_mirror_parity.py --frequency 6 --radius 16
python3 tests/spot_mirror_parity.py --seed 379334167 --frequency 4 --radius 12

# 3. the wiring end to end in a real headless Factorio: one create_territory per
#    cone, the mirror's exact chunk list, no re-creation, tile truth
python3 tests/probe_runtime_territory.py tests/map-gen-settings-user.json
python3 tests/probe_runtime_territory.py tests/map-gen-settings-high-volcanism.json
```
