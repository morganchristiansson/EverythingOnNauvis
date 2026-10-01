# Feature: noise-dedup — make the map-reset reveal cheaper by compiling less noise

Status: in-progress (measurement shipped and the metric corrected to the REAL
surface; the mod's own expressions are already clean against every documented rule, and
the program size is the merged map's field generators)
Owner: `tests/noise_real_report.py` (the metric), `tests/noise_budget.py` (the gate),
`tests/noise_engine_report.py` (fast preview loop), `tests/noise_ablation.py`,
`tests/probe_noise_cost.py` (wall clock), `tests/eon-probe-noise/`,
`tools/noise-sandbox/python/noise_complexity.py` (explains the number)
Config: seed 12345, `tests/map-gen-settings-deathworld.json` (the Legendary Deathworld
server's map-gen settings; the `scrap` control is dropped — 2.0.77 rejects it,
`Error: "scrap" is not a valid autoplace control name`), reveal box 39x39 chunks (the
scenario's `REVEAL_MAX_RADIUS = 19`).

## Why

The Legendary Deathworld scenario rerolls the seed on every map reset, which recompiles
the noise program, and then force-generates a 39x39 chunk box around spawn in batches
(`reset.lua:change_seed` + `on_tick_reveal`). That reveal is the KPI: it is the few
seconds where the server does not respond. The mod's noise expressions are 14% of it, so
this feature is about making that share smaller — and about knowing, with a number,
whether the usual suspect (the compiler not deduplicating the same expression written
two ways) is the reason. **Measured: it is not.**

## What the engine does, and what that means here

Per <https://lua-api.factorio.com/latest/auxiliary/noise-expressions.html>
(Performance tips):

- nodes are deduplicated when they are **identical**; re-association, distributing a
  constant factor, `x/2` vs `x*0.5` are all distinct operations;
- `if()` has **no short-circuit**, so a `-inf` mask does not make the branch it guards
  cheaper — the whole subtree is evaluated for every tile anyway;
- per-tile cost is therefore the number of **unique operations** in the program, and
  the engine prints its own estimate under `--verbose`.

## The metric: the real surface, on the reset path

The API docs say the report is printed "after creating a surface or **changing
MapGenSettings**", and a map reset changes MapGenSettings -- so it is reachable in a
running game, through rcon, in about a second
(`tests/noise_real_report.py`, ~5 s per side including the server start):

```
/c local s = game.surfaces[1] local m = s.map_gen_settings m.seed = m.seed + 1
   s.map_gen_settings = m
```

**A map preview is a different program.** Same mod, same seed:

| program | real surface | `--generate-map-preview` |
| --- | --- | --- |
| Entity | 5833 unique / 47405 complexity | 3349 / 33732 |
| Tile | 2484 / 30612 | 2479 / 30547 |
| Cliff | 1433 / 1566 | 1428 / 1561 |

The real Entity program is **74% larger**, because the preview surface never carries the
planet's autoplace settings. The first version of this file measured every subsystem
against the preview; those numbers were of the wrong program and are superseded.

Real surface, seed 12345, both sides:

| program | vanilla | with EoN | |
| --- | --- | --- | --- |
| Cliff | 287 | 1566 | 5.5x |
| Entity | 12440 | 47405 | 3.8x |
| Tile | 10068 | 30612 | 3.0x |
| total | 22795 | 79630 | 3.5x |

## The measurement trap (read this before trusting any A/B here)

Factorio **enables every mod it finds in `--mod-directory`** and rewrites
`mod-list.json`. A `mod-list.json` that leaves the mod out does nothing, so a
"with vs without" comparison run in one directory comes out **byte-identical** — the
mod is quietly enabled in both runs. That is exactly how the first version of this
feature concluded "the engine's report never sees a mod surface"; it was wrong, and the
correct reading is below. A baseline must be a mod directory that does not *contain*
the mod (`tests/noise_engine_report.py` builds one per side and prints the enabled mod
list it was actually given, so the trap cannot hide twice).

## Acceptance criteria

- [x] AC-1 The reset reveal is measured by one command, repeated, and reported as
      seconds for the 39x39 box and ms per chunk — and the comparison is interleaved
      so machine drift cannot fake it. `python3 tests/probe_noise_cost.py --repeat 3`.
      Measured (seed 12345, LDW settings, interleaved best of 4): vanilla **5.11 s /
      3.36 ms per chunk**, with the mod **5.85 s / 3.85 ms per chunk**. The
      distributions do not overlap, so the +0.74 s is not measurement error.
- [x] AC-2 The mod's contribution is attributed, not guessed: a data-stage-only build
      (no `control.lua`) measures the same as the full mod (5.72 s vs 5.68 s, inside
      the run-to-run spread), so the runtime spot mirror is not the cost and the
      compiled noise program is. `python3 tests/probe_noise_cost.py --mods eon-data-only`.
- [x] AC-3 The engine's own complexity report is the primary metric, on the **real
      surface via the reset path**: `python3 tests/noise_real_report.py --baseline`
      (~5 s per side). Measured Cliff 287 → 1566 (5.5x), Entity 12440 → 47405 (3.8x),
      Tile 10068 → 30612 (3.0x), total 22795 → 79630 (3.5x). The preview-based
      loop (`noise_engine_report.py`, ~2 s) is for relative comparisons only.
- [x] AC-4 Every subsystem is priced against that metric by ablation — one map preview
      per ablation, whole survey in 25 s: `python3 tests/noise_ablation.py`.
- [x] AC-5 Deduplication that the engine misses is measured separately, with the price
      of fixing it: ~0.5% of the program even after unifying `min`/`max` with `if`,
      `clamp` with `min`/`max`, `a + a` with `2 * a`, `if(c, e, e)` with `e`, and a
      constant factor with its distributed form.
- [x] AC-9 The mod's own expressions are checked against **every** documented rule in
      the API performance tips, over all 1260 compiled expressions: zero `1 + 2 + x`
      constant-first misses, zero `x + 0`, `x - 0`, `0 - x`, `x * 1`, `x / 1`,
      `x * (-1)`, `x ^ 2`, `x ^ 0`, `x ^ 1`. The only hits in the program are in
      vanilla expressions the merged map pulls in (6 x `size ^ 0.5` in
      `gleba_*_richness`, which the engine already rewrites to `sqrt`, and 18 x
      `c * (a + b)` in `vulcanus_*`, the distributable case from the docs) -- upstream
      candidates, not mod work.
- [x] AC-6 The program cannot silently grow: `python3 tests/noise_budget.py` fails when
      any program's complexity, or the total, exceeds `tests/noise_budget.json`.
- [ ] AC-7 A reduction in complexity shows up as wall-clock time on the reveal box.
      *Unproven so far, because nothing has been reduced yet — every candidate that
      would move the number changes the map (see residuals).*
- [x] AC-8 Every *regression-free* class of rewrite is measured, so "there is no free
      win" is a number rather than an opinion. See "What cannot be won without changing
      the map" below: missed dedup 4.1 of 65887 complexity units (0.006%), the one
      cheaper-but-identical primitive in the mod (2 `multioctave_noise{octaves = 1}`
      call sites) worth ~3 units, and zero dead expressions
      (`tests/dead_expressions.py`: 910 of 910 reachable).

## Verification

```sh
# KPI: the reveal box (interleave the two sides to cancel machine drift)
python3 tests/probe_noise_cost.py --mods eon    --settings tests/map-gen-settings-deathworld.json --repeat 3
python3 tests/probe_noise_cost.py --mods vanilla --settings tests/map-gen-settings-deathworld.json --repeat 3

# attribution: same data stage, no control stage
python3 tests/probe_noise_cost.py --mods eon-data-only --settings tests/map-gen-settings-deathworld.json --repeat 3

# the engine's metric, with the vanilla ratio
python3 tests/noise_engine_report.py --baseline

# gate (~4 s) and the per-subsystem price survey (~25 s)
python3 tests/noise_budget.py
python3 tests/noise_budget.py --ablate
```

| configuration | box | ms/chunk | Entity | Tile | total complexity |
| --- | --- | --- | --- | --- | --- |
| base + space-age (no mod) | 5.11 s | 3.36 | 9054 | 10068 | 19409 |
| + EoN data stage only | 5.72 s | 3.76 | 33732 | 30547 | 65887 |
| + EoN (full) | 5.85 s | 3.85 | 33732 | 30547 | 65887 |

## The map preview's penalty (a third, cheaper KPI)

`--generate-map-preview` prints the engine's own wall clock for the preview area, and
that is the cleanest per-tile signal available: it is pure expression evaluation, with
no chunk bookkeeping, no autoplace placement and no biters. Measured, seed 12345,
planet nauvis, best of 3:

| preview | with EoN | vanilla | penalty |
| --- | --- | --- | --- |
| 1024x1024 (default) | 1.39-1.45 s | 0.494 s | **2.9x, +0.90 s** |
| 2048x2048 | 5.48-5.59 s | 1.77-1.87 s | **3.1x, +3.70 s** |
| MapGenSettings compile | 14.0 ms | 3.7 ms | 3.8x |

At 4.19M pixels that is 1.31 us per pixel with the mod against 0.43 us without.

The preview is *not* a proxy for the reveal box, and the reason is worth recording: a
preview places no decoratives, ores or entities, so it never pays the autoplace work
that dominates chunk generation. It does still *evaluate* the entity program — the
decorative-probability ablation moves preview time by 0.112 s — so it is a faithful
measure of expression cost and a poor measure of chunk cost. That is exactly why the
preview shows 3x where the reveal box shows 1.14x: the mod inflates the expressions,
not the things the chunk generator does around them.

## Why the box says 1.14x and the complexity says 3.4x

Two independent reasons, both measured.

**1. Complexity is a weighted operation count, not a time, and the two programs that
hold most of EoN's complexity are the cheapest per evaluation.** The Entity program is
51% of the total (33732 of 65887) but only ~5% of the preview's time: the
decorative-probability ablation moves preview time by 0.066 s of 1.37 s. The Tile
program is 46% of the complexity and ~57% of the time: the mask ablation (Tile
complexity 30547 -> 1126) moves it by 0.776 s. Ore and decorative autoplace is evaluated
at candidate positions, not per tile, so its expensive primitives are paid far less
often than its operation count suggests. Complexity is still the right thing to
*budget* (it is a stable, per-commit number), but it ranks badly against time.

**2. The box is mostly not expression evaluation at all.** Scaling the preview's
per-pixel rate onto the box's 1.557M tiles:

| | expression-equivalent | other work | box |
| --- | --- | --- | --- |
| vanilla (0.471 us/px) | 0.73 s | 4.38 s | 5.11 s |
| with EoN (1.330 us/px) | 2.07 s scaled | — | 5.85 s |

So ~4.4 s of the box is chunk work the mod does not touch, which is what floors the
ratio at 1.14x. And the box pays only **55%** of the preview's per-pixel expression
rate: the missing 45% is exactly the Entity program, again because it is evaluated at
candidate positions rather than per tile.

The consequence is the ceiling on this whole feature: the *entire* expression part of
the box is about 1.4 s of 5.85 s, and it is already deduplicated down to one shared
operation per field. Halving it — impossible without changing the map — would be 12%.

## Why the box says 1.14x and the preview says 3x

The mod adds 0.88 us per preview pixel (4.19M pixels -> +3.70 s) but only 0.47 us per
generated tile (1.56M tiles -> +0.74 s) — a factor of 0.53, and the whole reason the two
KPIs disagree. A preview evaluates all four programs at every pixel; chunk generation
evaluates the Tile program per tile, the Entity program only at autoplace candidate
positions (a sparse subset), and the Cliff program only on cliffs. Complexity therefore
translates only partially: ablating the volcano (-10% of the program's complexity) moved
the box by **0.00 s**, while ablating the blended biome fields (-60%) moved it by
-0.48 s. Anyone optimising against the box alone would have measured the volcano as
free; anyone optimising against complexity alone would have measured it as the problem.

## What the merged map actually costs, by part (the design, not the summary)

The first version of this feature reported one number called "biome blend". That
number was misleading: the ablation behind it zeroed the *terrain substrate*, not the
boundary fades. Split into the parts the design actually has (median of 3 previews,
`python3 tests/noise_ablation.py --repeat 3`):

The subsystem numbers below all overlap heavily, because every one of them removes a
whole cluster (the region field plus everything hanging off it) and the clusters share
fields. The **per-field** prices, which do not overlap, are the ones to act on:

| field | complexity | preview | octaves |
| --- | --- | --- | --- |
| `eon_gleba_blend` (the crossfade itself) | **-0.1%** | 0.000 s | a smoothstep: `t * t * (3 - 2 * t)` |
| `eon_gleba_moisture_vanilla` | -0.1% | +0.022 s | |
| `eon_aquilo_persistance` | -1.0% | -0.009 s | 5 |
| `eon_aquilo_macro` | -0.6% | -0.042 s | 2 + 1 |
| `eon_gleba_elevation_vanilla` | -2.1% | +0.006 s | |
| `eon_aquilo_detail` | -2.0% | -0.063 s | 5 (variable persistence) |
| **the crossfade, total** | **~0.1%** | ~0 | |

**The crossfade is not the cost — the fields it reads are, and they are paid on every
tile of the whole map.** `eon_moisture_blended` is `lerp(moisture_nauvis,
eon_gleba_moisture_vanilla, eon_gleba_blend)`: one lerp against a smoothstep. What it
costs is that the crossfade puts vanilla Gleba's *whole elevation/moisture generator*
into a per-tile program — and because `if()` has no short-circuit, being inside a lerp
is no different from being outside it: those octaves run for every tile, including the
volcano in the far south.

The first version of this table said "blended elevation/aux/moisture: -30.6%", and that
number is wrong. `eon_elevation_blended` is the surface's `elevation`
(`property_expression_names.elevation`), so zeroing it does not remove a crossfade, it
removes the map's elevation field — vanilla's pipeline, `slope`, the cliff ladder, and
every tile autoplace input that reads elevation. Same for the "-13.4% Aquilo region"
and "-9.8% Gleba region" rows: those are "this cluster stops existing", not a lever.

**On the cache-hit intuition, which is right and irrelevant.** Each Aquilo field *is* one
operation shared by every user — the deduplication is working perfectly. But one
operation of a five-octave noise is still five octaves per tile, and
`eon_aquilo_land -> eon_aquilo_base` pulls `eon_aquilo_macro` + `eon_aquilo_detail` +
`eon_aquilo_persistance` + the ammonia depth into the per-tile program for the whole
map, not just the north. Sharing decides *how many times an expression is compiled*;
it says nothing about *how often it is evaluated*, and evaluation frequency is the cost.

So the per-boundary user counts — which are what the design actually varies — are:

| helper | users | what crosses |
| --- | --- | --- |
| `eon_mask_gleba_fade` | 13 tiles + 9 trees | the hard Gleba line (tiles/trees, not decoratives) |
| `eon_mask_nauvis_deep` | 19 tiles | Nauvis tiles allowed south into the mixing band |
| `eon_mask_volcano_fade` | 18 decoratives | volcano-gleba / volcano-aquilo |
| `eon_mask_aquilo_land_fade` | 6 decoratives + 2 entities | north |
| `eon_mask_gleba_territory_fade` | 7 decoratives | the Gleba flora leaders |
| `eon_mask_nauvis_territory_fade` | 2 decoratives | |
| `eon_mask_aquilo_water_fade` | 2 decoratives | |

which is exactly the inconsistency worth fixing: the Gleba line is carried by
`eon_mask_gleba_fade` (tiles and trees) *and* `eon_mask_gleba_territory_fade`
(decoratives) and `eon_mask_nauvis_deep` (Nauvis tiles), i.e. three helpers for one
boundary, while every other boundary has one. Unifying them costs nothing in program
size — the region fields are shared already — and it is a map change, so it is a
playtest decision, not an optimization.

## Potential gains if the map may change

Projection factor: the box pays 0.475 us per generated tile against the preview's
0.88 us per pixel for the same delta, so **1 s of preview time is 0.20 s of the box**
(0.74 s of measured box gap against 3.7 s of preview gap at 2048x2048). Preview deltas
below are the median of 5 runs -- a single run has ~+/-0.1 s of noise, which is the size
of the whole gain of the smaller levers.

| lever (measured by ablation) | preview | box (est.) | % of the 5.85 s box | what it costs the map |
| --- | --- | --- | --- | --- |
| the whole mod | -1.0 s | **-0.74 s** | **12.6%** | not EoN any more |
| the merged biome blend | -0.78 s | -0.16 s | 2.7% | removes the merged Gleba/Aquilo terrain -- the feature itself |
| the volcano fields | -0.17 s | -0.03 s | 0.6% | no volcanic ground, no demolisher territories |
| halve the mod's own octave counts | -0.06 s | -0.012 s | 0.2% | smoother Aquilo and volcano detail |
| drop the Aquilo detail field | -0.06 s | -0.013 s | 0.2% | Aquilo elevation detail |
| drop the spot-deployment warp | -0.04 s | -0.008 s | 0.15% | 0.8-3% of chunks change owner |
| the four small levers together | -0.19 s | -0.04 s | 0.6% | a compounding but visible softening |

Two things this table says that a complexity number does not:

- **The merged biome blend is the whole game.** It is 78% of the mod's preview cost and
  2.7% of the box; every other lever is under 1% and they mostly overlap. Keeping the
  blend (which the playtest wants) means the ceiling for noise work is ~0.6%.
- **Roughly 0.5 s of the 0.74 s box gap is not expression evaluation at all.** The
  ablations above account for ~0.22 s of it; the rest is content: the merged map places
  more tiles, more decoratives and more autoplace candidates, and no expression change
  touches that. (The mask ablation cannot be used to check -- making the masks identity
  changes the map so much that the box takes 65 s.)

## What cannot be won without changing the map

Measured, per class of rewrite, in complexity units out of 65887:

| rewrite | map-identical? | worth |
| --- | --- | --- |
| `0.8 * multioctave_noise{...}` -> `output_scale = 0.8` (7 calls, in vanilla's `gleba_*` expressions) | yes | 7 ops — an upstream PR, not mod work |
| merge the forms the compiler cannot see (missed dedup) | yes | 4.1 (0.006%) |
| `multioctave_noise{octaves = 1}` -> `basis_noise` (2 call sites) | yes | ~3 |
| delete dead expressions | yes | 0 — 910 of 910 expressions are reachable |
| turn off autoplace controls | no (no ore) | **0** — the program does not shrink |
| share the mask chain as one 0/1 signal and multiply | yes | **0** — conditions already shared |
| drop the blended biome fields | no | -60% |
| drop the volcano fields | no | -10% |
| drop every decorated probability expression | no | -8% |
| drop the spot-deployment warp | no (0.8-3% of chunks change owner) | -1.3% |

The dedup figure above is the *strong* version of the claim: the analyser unifies
`min`/`max` with `if`, `clamp` with `min`/`max`, `a + a` with `2 * a`, `if(c, e, e)` with
`e`, and a constant factor with its distributed form, on top of everything the engine
itself folds. With all of that the mod's missed dedup is 3.9 of ~760 cost units (0.5%).

The structural reason is that the mod's own heavy primitives are **ten call sites, not
hundreds**: one `spot_noise` (`eon_volcano_spots_at`), six `multioctave_noise` (one with
`octaves = 1`), one `variable_persistence_multioctave_noise`, two `basis_noise`. Each is
a named expression, so each is one operation shared by every prototype that references
it — 339 mask `if()`s sit on 25 shared conditions. The rest of the program is vanilla's
own expressions for Gleba/Fulgora/Aquilo content that only the merged map makes
reachable, shared just as well. The only map-identical primitive substitution that
exists at all is `eon_aquilo_macro`'s `multioctave_noise{octaves = 1}` -> `basis_noise`
(provably the same value, ~3 cost units); `eon_volcano_coverage` is referenced by nothing
and is not compiled at all.

So the answer to "can we simplify without regressions" is: the provably safe
rewrites are worth about 0.5% of the program by the analyser's weighting, which is
below the measurement floor of both KPIs (box +/-0.1 s, preview +/-0.03 s). The classes that would move the
number are exactly the ones that change what the map is, so they are playtest
decisions. The one worth a playtest on its own merits is the spot-deployment warp
(1.3% of the program, `-0.062 s` of preview time): a detail effect with a
per-tile cost, already measured once and kept.

## The last documented rule set (seed, scale, offsets, quick-multioctave)

Scanned over all 1260 compiled expressions:

| documented rule | violations | fixable map-identically? |
| --- | --- | --- |
| `x = x * c` should be `input_scale = c` | 0 in the mod, 2 in vanilla's Fulgora voronoi (`y = y * 0.8`, asymmetric) | no — asymmetric, and nothing to factor out |
| `x = x + c` should be `offset_x = c` | 0 | the 9 hand-written offsets in vanilla's gleba noise are all **noise-dependent** (`x = x + wobble_noise_x * 15`), and `offset_x` is a constant parameter, so they are not violations |
| `c * noise{...}` should be `output_scale = c` | 7, all in vanilla's `gleba_temperature_normalised` / `gleba_decal_noise` / `gleba_bush_noise` | yes, but it is vanilla's code: 7 operations, an upstream PR |
| prefer `multioctave_noise` over `quick_multioctave_noise` | 6, all in vanilla's temperature/moisture/aux | **no** — they are not the same value, so this changes every map |
| `seed0` should be `map_seed` | 4, all the mod's Aquilo fields (`map_seed + 1`) | **no** — a different seed0 is a different noise. The docs call it confusing, not slow |
| `seed1` should be sequential or a string | 0 | |
| **the `x = x, y = y` fast path ("around 5x faster")** | **8 of the mod's 9 own noise calls are already on it** | the one exception is the spot-deployment warp, which is sampled at warped coordinates |

The warp is therefore the only thing in the mod on the documented slow path, and it was
measured on the KPI rather than projected: with it neutralised the reveal box is
5.71-5.97 s against a baseline of 5.78-6.08 s (2 runs each) — indistinguishable, with
the same result for halving the mod's own octaves (5.84-6.03 s). The rule that the docs
flag as 5x matters, and it changes nothing here, because the slow path is six octaves of
warp that the program has to evaluate anyway.

## Known residuals / accepted exceptions

- **The 3.4x is the merged map, and it is intrinsic.** Priced by ablation: the mask
  functions are 63% of the program's cost, the blended biome fields 60% (they overlap
  the masks), the volcano 10%, every decorated probability expression 8%, the
  spot-deployment warp 1.3%. A tile on the merged map has to know its biome, so every
  probability expression pulls in the volcano and gleba fields, and `if()` has no
  short-circuit so the guarded branch is evaluated anyway. Every way of removing that
  changes what the map is — a playtest decision, not an optimization.
- **Disabling an autoplace control does not shrink the program** (measured: 0 change
  for calcite/tungsten/geysers/holmium at frequency 0). The compiled program is a
  property of the prototypes' expressions, not of which controls are on, so "turn the
  ores off for speed" is not a lever.
- **The analyser's root set is an over-approximation of the engine's.** It walks every
  prototype with an `autoplace` block, including planets that are not on the merged
  map, so its absolute counts are wrong (2841 vs the engine's 928 on the vanilla
  Entity program). It is used to *explain* the engine's number — missed dedup, mask
  sharing, per-primitive tally — never to replace it. Everything authoritative comes
  from the engine report.
- **A mask is at the floor.** One `if()` per (prototype, boundary) is the minimum: the
  cheapest alternative spelling costs the same, and the condition is already one shared
  operation (25 conditions carry 339 mask `if()`s in Entity, 18 carry 156 in Tile). The
  only way to reduce the masking layer is to have fewer boundaries per prototype, which
  is a design decision, not an optimization.
- **`mask_gleba_shared` is cheap**: re-registering Gleba's formula for the 14 base
  prototypes vanilla Gleba also grows costs 789 complexity units of the real program,
  1.1%.
- **Vanilla has a few real (tiny) misses**: 3.5 of 432 in Entity, 1.0 of 250 in Tile —
  the same arithmetic spelled two ways in Fulgora's, Gleba's and Nauvis' tile
  expressions (a sum in two orders, `pi * r` against `r * pi`). Not worth a mod-side
  rewrite; the analyser records the number so a change that *adds* more of them is
  visible. (A dedicated vanilla-side patch would belong in its own file, easy to drop
  again, and would be worth contributing upstream separately.)
- Per-tile cost during play is a non-issue and was not optimized: the box is generated
  in one burst on reset, and 3.4x of it is invisible in normal play.

## Rejected alternatives

- **"Rewrite the territory masks as one shared 0/1 signal and multiply, so the mask
  chain is compiled once instead of once per decorated prototype."** The obvious cache
  win, and worth nothing: the Entity program has 339 mask `if()`s over only **25
  distinct conditions**, and every node inside those conditions is already shared
  (analyser's `territory masks:` line). Only the one `if()` per prototype is per-use,
  and replacing it with one multiply per prototype moves the cost instead of removing
  it — while trading the mod's sign-safety rule (`-inf` replaces the probability; never
  multiply a signed snapshot by something that can be `-inf`) for that nothing.
- **Believing the engine's report is blind to mod surfaces.** It is not; the
  measurement setup was. See "The measurement trap" above.
- **Trusting a mod setting to select an ablation headlessly.** It cannot be forced
  (`--create`/`--start-server` read the profile, not the prototype), so the ablation
  mod's `data-final-fixes.lua` has its `local ABLATION = "..."` line rewritten by the
  driver before each run.
- **Reading the reset's wall clock from inside the control stage.** There is no clock
  there: no `os`, and `LuaProfiler` refuses raw values ("these objects don't allow
  reading the raw time values from Lua"). The harness times the probe's stage files'
  mtimes instead (`tests/eon-probe-noise/control.lua`).
- **Waiting out a fixed timeout to stop the headless server.** The probe writes its
  report as the last act of `on_init`, so the file appearing is the completion signal;
  `subprocess.run(timeout=…)` paid the full timeout every run.
- **Benchmarking the whole headless run.** Mod load (~1.1 s) and save creation swamp a
  5 s measurement and drift with the mod list; the staged mtime difference is ~5.1 s of
  engine time and repeats to ±0.1 s.
- **Benchmarking in-game during play.** The KPI is the reset reveal; in-game
  generation is fast enough that the difference is not observable.
