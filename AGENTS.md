# AGENTS.md — EverythingOnNauvis-morganc

Source of the "Everything on Nauvis (morganc fork)" mod. All terrain/map-gen logic lives in
`map-generation/`. Load order: `data.lua` → `data-updates.lua` (requires `map-generation.*`) →
`data-final-fixes.lua`.

## Dev loop

- `/factorio/mods/EverythingOnNauvis-morganc` is a symlink to this repo, so edits are live in the
  game's mod folder. No packaging needed for local testing.
- Release zips are built with `python/create_zip.py` into `versions/` (gitignored).
- `changelog.txt` top section is the in-progress version; its `Date:` stays `2026-09-XX` until release.
- Tests: `python3 tests/run_tests.py` — runs the factorio binary with `--dump-data` (twice, per
  settings state) and asserts on `data.raw` JSON. Defaults:
  `FACTORIO_BIN=/factorio/bin/x64/factorio`, mod source = repo root.
- Runtime volcano territories: `python3 tests/run_spot_mirror_tests.py` — the standalone
  spot mirror's self test + parity against the engine's own spot selection + two headless
  end-to-end runs (100% and 600% volcanism) + the setting switch. The mirror itself needs
  only `lua`: `lua tests/noise-mirror/selftest.lua`, `lua tests/noise-mirror/bench.lua`.

## Map-gen cost: what the reset reveal actually pays (measured 2026-09-28)

The Legendary Deathworld scenario (`/factorio-legendary-deathworld`) force-generates a
39x39 chunk box around spawn on every map reset, and that burst is the KPI. Interleaved
best-of-4 runs (`tests/probe_noise_cost.py`, seed 12345, the server's own map-gen
settings): **vanilla 5.11 s, with the mod 5.85 s** -- the mod's program is +0.74 s,
14% of the box. The distributions do not overlap, so it is not measurement noise. A
data-stage-only build (no `control.lua`) measures the same as the full mod, so the
runtime spot mirror costs nothing here and the compiled noise program is the whole
difference.

**The engine's complexity report IS available on the reset path, and it is the metric
the API docs tell you to target** ("the smallest possible complexity"). A map reset
changes MapGenSettings, and the report appears then:
`tests/noise_real_report.py` starts a headless server, bumps the seed through rcon, and
reads the log (~5 s per side). Measured on the REAL surface, seed 12345:

| program | vanilla | with the mod | |
| --- | --- | --- | --- |
| Cliff | 287 | 1566 | 5.5x |
| Entity | 12440 | **47405** | 3.8x |
| Tile | 10068 | 30612 | 3.0x |
| total | 22795 | 79630 | 3.5x |

**The real surface is NOT the preview surface, and the gap is large:** same mod, same
seed, `--generate-map-preview` reports Entity 3349 unique / 33732 complexity where the
real surface reports 5833 / 47405 -- **74% bigger**, because the preview never carries
the planet's autoplace settings. Every per-subsystem number measured against a preview
(this file, until 2026-09-28, and the first version of `features/noise-dedup.feature`)
is therefore measured on the wrong program. `tests/noise_engine_report.py` is the fast
preview-based loop (~2 s) and is still useful for relative comparisons; the gate and any
optimisation claim use the real surface.

**The trap that made this look impossible, recorded so nobody repeats it:** Factorio
ENABLES EVERY MOD IT FINDS in `--mod-directory` and rewrites `mod-list.json`. A
mod-list.json that leaves the mod out does nothing, so a "with vs without" A/B run in
one directory comes out byte-identical -- the mod is quietly enabled in both runs. A
baseline must be a mod directory that does not CONTAIN the mod; every tool here builds
one per side and `live_server.py` had to be fixed for it. Gate: `tests/noise_budget.py`
against `tests/noise_budget.json` (~10 s, both sides).

**The mod's own expressions are already clean against every documented rule.** Scanning
all 1260 compiled expressions for the anti-patterns in the API docs' performance tips:
zero `1 + 2 + x` constant-first misses, zero `x + 0`, `x - 0`, `0 - x`, `x * 1`, `x / 1`,
`x * (-1)`, `x ^ 2`, `x ^ 0`, `x ^ 1`. The only hits in the whole program are in VANILLA
expressions the merged map pulls into the per-tile programs: 6 x `size ^ 0.5` in
`gleba_*_richness` (the engine turns those into `sqrt` anyway) and 18 x
`c * (a + b)` in `vulcanus_*` (the distributable case from the docs). Those are the
upstream-contribution candidates, not mod work.

**What the 3.5x is, priced by ablation.** The masks are the design's cost and each one
is already at the floor: a mask is one `if()` per (prototype, boundary), and the
expensive half -- the condition -- is one shared operation (25 conditions carry 339 mask
`if()`s in Entity, 18 carry 156 in Tile). Cheaper alternative spellings cost the same,
and the whole missed-deduplication total is 0.5% of the program even after unifying
`min`/`max` with `if`, `clamp` with `min`/`max`, `a + a` with `2 * a`, `if(c, e, e)`
with `e`, and a constant factor with its distributed form. What the mod really adds is
the other planet's field generators, and because `if()` has no short-circuit those run
for every tile of the whole map: being inside a lerp is no different from being outside
it. Per-field prices (no overlap): `eon_gleba_blend` (the crossfade, a smoothstep)
0.1%, `eon_gleba_moisture_vanilla` 0.1%, `eon_aquilo_persistance` (5 octaves) 1.0%,
`eon_aquilo_macro` (2+1) 0.6%, `eon_gleba_elevation_vanilla` 2.1%, `eon_aquilo_detail`
(5 octaves, variable persistence) 2.0%, and `mask_gleba_shared` (Gleba's formula
re-registered for 14 base decoratives) 1.1% of the real program. Sharing decides how
many times an expression is COMPILED; cost is decided by how often it is EVALUATED --
so "the mask is only 0/1" and "the field is shared" are both the wrong question.

Two rules for anyone touching this area: a new expression is a per-tile cost for the
whole map, so it belongs in `tests/noise_budget.py`'s budget before it lands; and a
claimed win is a `probe_noise_cost.py` or `noise_real_report.py` number, never an
operation or complexity count on its own.

## Headless factorio gotchas (verified on 2.0.77)

- **`--create save.zip` does NOT run control scripts** (`script.on_init` never fires). To run
  `on_init` headless, create the save first, then `--start-server save.zip` (works server-side,
  `on_init` fires, run for a few seconds). The game is in `/factorio/bin/x64/factorio`.
- **`--dump-data` aborts (crash via `enterMinimalMode`, "terminate called without an active
  exception") whenever dependencies can't be resolved.** It also doesn't run control scripts. The
  real dependency error goes to `factorio-current.log` in the write-data dir, not stdout — grep it
  for `depend|conflict|incompat|requires`.
- Minimal headless setup per test dir:
  - `mods/mod-list.json` (pick enabled mods; at least `base` + `space-age`),
  - symlink/copy mods you need into `mods/`,
  - `config.ini`: `[path] read-data=/factorio/data write-data=<dir>/write`,
  - run with `HOME=<dir> factorio --dump-data --config ... --mod-directory ...`.
- Dump output: `<write-data>/script-output/data-raw-dump.json` (prototype table incl. planet
  `map_gen_settings`). `game.write_file("x.txt", ...)` lands in the same `script-output/`.
- Test mod `info.json` must include `author` and matching `factorio_version` or the load fails.
- Lua API: `surface.get_tiles` does **not** exist in 2.0 — use `surface.get_tile(x, y)` (singular).
  `game.shutdown()` also doesn't exist; use `timeout` to kill headless runs.

## Map-gen probing headless (verified 2.0.77 on seed 12345, volcanism freq 600%)

Decoratives: `surface.find_entities_filtered` does NOT return optimized-decoratives — use
`surface.find_decoratives_filtered({area = …})` (result: `{position, decorative, amount}`, name
via `dec.decorative.name`). `tests/probe_decoratives.py` + `tests/eon-probe-decoratives/` count
what actually renders in six regions (nauvis plains, nauvis volcano, deep gleba, gleba volcano,
aquilo north, the gleba line) and classify offenders by the transition under them (never by tile
name — see tile-name trap above).

Tooling (dev-only mods in `tests/`):
- `tests/eon-verify-territory/` + `tests/verify_territory.py` — ground truth: writes per-chunk
  territory membership (`surface.get_territory_for_chunk`, LuaTerritory exists!), per-4px
  volcano/lava/water masks, and chunk corner/center tile names for a disc. Keep the run dir with
  `EON_KEEP_DIR=1`.
- `tests/eon-probe-geometry/` + `tests/probe_geometry.py` — override the territory index
  expression with lattice probes to find the sampling geometry.

The reliable headless flow (everything else stalls):
- `--create` does not run control scripts, and the save then ships a `script.dat` that marks
  storage as initialised — so `--benchmark save.zip` also skips `on_init`. **Strip `script.dat`
  from the save zip first** (zipfile: copy all entries except `script.dat`) so `on_init` fires on
  load.
- Do ALL work inside `on_init`: `surface.request_to_generate_chunks(pos, radius)` then
  `surface.force_generate_chunk_requests()` (blocks synchronously) then scan and
  `helpers.write_file`. Requests made later, from `on_nth_tick`, are silently ignored headless;
  `--start-server` never advances a tick (no `on_nth_tick`, no background chunk gen); chunk
  generation requested during load uses the fast initial-map-gen path.
- **`--start-server` never exits**: a headless run must be stopped by the harness. Never
  `subprocess.run(..., timeout=N)` and swallow `TimeoutExpired` — that pays the FULL N
  every run (this is what made the runtime-territory probe take 10 min for ~20 s of work).
  `Popen` the server, poll for the probe's `report.json` (written as on_init's last act),
  then `terminate()`. `tests/probe_runtime_territory.py` does this; the full gate suite is
  now ~1.5 min (selftest 0.06 s, parity ~5 s each, e2e ~20 s each, `--create` ~2.6 s).
- **`force_generate_chunk_requests` does not finish before it returns.** Asked from
  inside a startup event or an rcon call, the chunk is still ungenerated when the
  call returns and only appears once control goes back to the game loop (measured:
  a reveal reported `is_chunk_generated = true` at the end of the call, and the
  builder, called again three seconds later, saw it for the first time). So
  "generate, then ask" has to be two calls -- which is exactly what the engine
  does by delivering `on_chunk_generated` later. A headless server with no players
  also ticks at ~0.25/s, so "later" is later in wall-clock terms too.
- **When editing a guard, check the edit landed.** A one-word mismatch in a
  `pending` filter ("waiting" instead of "unseen") silently made every cone
  permanently unclaimable: cones were marked "unseen", nothing ever
  retried them, and the game had no territories at all -- with no error anywhere.
  Two of the same day's patches were lost the same way, because the anchor text
  had already changed and the replacement silently matched nothing. Use an `assert
  old in s` before replacing, and re-read the function after editing it.
- **A runtime-created territory has NO demolisher until you ask for one.**
  `surface.create_territory` returns an *empty* territory: the segmented units (the
  demolisher and its segments) are spawned by the MAP GENERATOR when it creates a
  territory, and `LuaTerritory` docs are explicit that "a territory with no units will
  not appear on player's maps". So the mirror can be perfect — right chunks, right
  disc, patrol path present (`get_patrol_path()` returns points) — and the volcano
  hosts nothing, with nothing in the log. The fix is one call per territory,
  `territory.regenerate_segmented_units()`, called WITHOUT a colon: probe-verified
  live on 2.0.77, `t:regenerate_segmented_units()` raises "Expected 0 arguments but 1
  were given". The F4 territory view cannot distinguish empty from patrolled, so
  `tests/eon-probe-runtime` now asserts every created territory has a segmented unit.
- A headless server answers `rcon`, and `rcon.print(text)` in Lua is what puts text in
  the rcon RESPONSE (`game.print` comes back empty, and a Lua error comes back empty
  too, so wrap probes in `pcall` and report the error). `tests/rcon_probe.py` needs no
  server restart, so it is the fast loop for a running game; `require` does NOT work
  from `/c`, so the mirror cannot be loaded there.
- `/c` runs in BASE's script scope, so `storage` there is base's — a mod's own
  `storage` keys are invisible to an rcon probe (that cost us a false "the control
  stage never ran").
- Coordinates: `request_to_generate_chunks(position, radius)` takes a **MapPosition (tile
  coords)** + radius in **chunks**; `is_chunk_generated(position)` takes a **ChunkPosition
  (chunk coords)**. Mixing them up silently misplaces/truncates the request.

Territory engine mechanics (probe-verified, matters for any territory-feeding mod):
- The territory index expression (`demolisher_territory_expression`) is sampled at **one fixed
  world-aligned lattice point per 32x32 chunk** (every probe lattice hits mod-32 world points;
  correlating tiles vs territory pins it as the chunk's TOP-LEFT corner: every gap chunk has
  non-volcano ground at its top-left while the volcano hugs its bottom edge, and claimed chunks
  have volcano at top-left). A chunk is claimed iff the sampled value is `>= 0`;
  `-inf`/negative = no territory for that chunk.
- There is no "any corner" union: a 50%-checkerboard probe claims ~50% of chunks. The old
  comment "territory includes any chunk whose corner touches the mask" is wrong.
- `minimum_territory_size` (vanilla 10, see `territory_settings`) drops claimed chunks that end
  up in sub-10-chunk territories. On ragged EoN volcanoes (voronoi radius 288 slices the
  footprint, coastlines fragment it) that silently deletes whole volcano tops — set it to 1.
- Headless is not trustworthy for territory GROUPING: with a clean uniform 2x2-chunk
  block id (`1 + floor((x+3200)/64) + 1000*floor((y+3200)/64)`, verified uniform over the
  chunk pair), every chunk still gets its own territory object headless (1885 territories of
  size 1). Whether same-id chunks merge in the real game can't be verified here — the
  real-game screenshots show multi-chunk territories, so merging likely happens there; judge
  grouping in the real game only. Per-chunk membership IS trustworthy.
- Measuring the claimed-vs-terrain offset headless: cluster the 4px volcano samples and the
  claimed chunk centers independently (300px merge), then compare centroids per blob. With
  the un-shifted terrain mask the claimed centroids sat +15/+16px SE of the volcano
  (top-left-corner anchoring); the tile-truth mask must be built on the 16px-shifted spot
  field (the since-deleted `eon_vulcanus_terrain_at16`) to recenter — after the shift the per-blob deltas are
  ~0.
- Single-chunk territories are voronoi-cell slivers: with grid_size smaller than the
  volcano, manhattan-diamond cell borders cut coastal volcanoes diagonally into 1-chunk
  pieces (that is the "small demolisher turning in circles" pattern). Make
  demolisher_territory_radius larger than the typical volcano footprint (512 works at
  600% volcanism) so a volcano fits in one cell; the biggest volcanoes still span cells and
  pick up mixed sizes via the cell-parity mix. The mix expression references
  demolisher_territory_radius by name, so it stays in sync automatically.
- Final mask recipe (0.1.10, measured on seed 12345/600%): the territory mask is the volcano
  CORE signals (folds + lava rings) on the 16px-shifted spot field plus the flat-skirt inner
  edge (spots > 0.6), NOT the full terrain (that recreates patrol points on the skirt /
  water-rim chunks). With the core mask: last 2x1/1x1 voronoi slivers sit on the skirt and
  drop out on their own, every lava-bearing chunk stays covered, leaks stay 0, centroids
  stay ~0, and the rim is a free buffer for chunk-quantization error.
  minimum_territory_size = 3 then only needs to catch stragglers. Headless verification must
  pin the verifier's own minimum_territory_size to 0 (data-final-fixes.lua), else the
  benchmark's per-chunk territories all get filtered and the mask's membership becomes
  invisible.
- Tungsten placement (final): favor band = flanks at spots > 0.65 (outside the lava core,
  which already blocks placement), candidate frequency x3 (control:tungsten_ore:frequency
  multiplied in eon_tungsten_volcano_region), and the RENDER GATE is the territory core
  mask (the since-deleted `eon_vulcanus_core_at16`, now the unshifted
  `eon_vulcano_coverage`) so ore basically cannot render outside demolisher
  territory. Measured residual 0.3%: tiles on volcano ground inside chunks whose corner
  sample is one tile off-core (NW-rim chunk class). This class is NOT fixable from noise
  expressions: territory membership is evaluated chunk-wise at the corner, ore renders per
  tile, and noise-function x/y parameters DO NOT propagate into named expression
  references (probe-verified: eon_probe_at{x=x+1000,y=y} == plain mask, claimed sets
  identical), so "evaluate the mask at the chunk corner for this tile" is impossible.
  Raising the band further just trades empties (roughly one in five volcanoes has no ore
  at 0.65; accepted by design).
- Memory: a territory expression that is positive over a whole map region (constant, or
  high-coverage ids) blows map gen up to ~5GB and the OOM killer SIGKILLs factorio (RC -9,
  `VmRSS ~5GB`, no log entry). Keep probe expressions masked to the region of interest and
  emit unique ids (`1 + abs(x) + 1000000*abs(y)` style) rather than a constant.
- Do not put `-inf` and arithmetic in the wrong order: inside the mask the id is
  `voronoi - demolisher_starting_area` where the mod set `demolisher_starting_area =
  if(mask, 0, -inf)` — keep that wrapper shape or territory math goes infinite.

Demolisher territory design (what the current code does, why):
- Membership mask = `eon_vulcanus_terrain` (the exact 0/1 signal the volcanic tiles place on).
  Per-chunk corner sampling then can't disagree with the rendered terrain: no territory off the
  volcano, no whole flanks lost to an eroded+shifted field on gentle slopes (the old
  `spots > 0.5` at a 16,16-shifted position was what cut the top half off the gps -79.4,-831.2
  volcano on seed 12345). The remaining artifact is the one-chunk corner quantization: a chunk
  whose top-left corner is a water pocket/rim is not claimed even if mostly volcano.
- Demolisher size selection still keys off the (16,16)-shifted spot fields
  (`eon_terr_volcano_small/big` + `eon_volcano_small_cap`) — those are for sizing only.

## Dependency semantics (verified empirically)

- Version ranges are honored only on positive/optional deps: `"X >= 1.2"`, `"? X >= 1.2"`.
- On incompatibilities the version is **ignored**: `"! X <= v"` acts as a full `! X` block
  (tested: `! X >= 999` still blocked stub 0.1.0). The parenthesized form `"! (X <= v)"` is a
  parse error/load abort. There is no way to express "block only old versions".
- Use transitive blocks instead: e.g. `EverythingOnNauvis-Patches` (all shipped versions) hard-
  requires the original `EverythingOnNauvis`, which the fork already conflicts with
  (`! EverythingOnNauvis`), so old Patches stays blocked without a versioned entry, while a
  future Patches that drops the original dep loads freely.

## Map-gen / territory masks

- Cliffs: one cliff ladder per surface (`cliff_settings` on the planet: interval 40 /
  first band 10 / richness 1.0 engine defaults for nauvis; vanilla gleba is interval 60 /
  40 / 0.8). The merged map keeps the nauvis ladder but emulates gleba's contour
  PLACEMENT through `eon_cliff_elevation`: the south arm feeds `(2*gleba_elevation-50)/3`,
  mapping every 40-unit ladder step onto a 60-unit gleba step anchored at 40+60k. Before
  that, EoN south had 2.9x vanilla's cliff count with cliffs in wetland/lowland ground;
  after, ~1.2x (residual = richness 1.0 vs 0.8 + volcano terrace rings). Segment density
  per contour can't be split per-region; only placement can, via the property. Baseline
  probe: `tests/probe_baseline.py` + `tests/eon-probe-baseline/` (EON=1 scans the merged
  map; GLEBA=1 loads `tests/eon-probe-glebanauvis/`, which copies vanilla gleba's
  map_gen_settings onto nauvis so the same surface generates vanilla gleba — that works;
  `game.create_surface(name, settings)` does NOT honor map_gen_settings tables and makes
  junk terrain with random-other-planet tiles).
- Fish: vanilla prototype `fish.autoplace.probability_expression = 0.01` (a literal number) and
  fish only materialize on liquid tiles; per-planet enablement is
  `planet.map_gen_settings.autoplace_settings.entity.settings["fish"] = {}`.
- `eon_mask_nauvis_territory(e)` is exactly
  `eon_mask_off_aquilo_territory(eon_mask_off_gleba_territory(eon_mask_off_vulcano_terrain(e)))`;
  the `off_*` masks yield `-inf` inside their territory. It is the "nauvis only" mask — used to
  keep fish/dead trees out of non-Nauvis liquids (lava, ammonia ocean, Gleba wetlands), while
  leaving the inner probability expression (usually a literal, gets string-coerced) unchanged.
- `eon_mask_gleba_territory(e)` / `eon_mask_off_gleba_territory(e)` gate on
  `eon_gleba_mask` (= `eon_gleba_region(0)`). `eon_mask_nauvis_deep(e, t)` is the nauvis-side
  version: `off_aquilo(off_vulcano(if(eon_gleba_region(t), -inf, e)))` — alive while the
  transition stays below threshold `t`. Grass tiles, grass tufts and trees all use `t = 10`,
  so they fade across the mixing band and die at the same line.

### Decoratives: which biome owns what (truth source: `/factorio/data` prototypes)

- **Nauvis natives**: `data/base/prototypes/decorative/decoratives.lua` (green-/brown-\* grass,
  asterisks, fluffs, pitas, crotons, bushes, mud/sand/lichen/shroom decals, rocks, desert
  bushes, garballo). Trees: `data/base/prototypes/entity/trees.lua`, driven by
  `trees_forest_path_cutout_faded`.
- **Gleba natives**: `data/space-age/prototypes/decorative/decoratives-gleba.lua` (lettuce
  lichens, split-gills, veins, mycelium, corals, barnacles, nerve roots, white-carpet-grass,
  black-sceptre, …). Trees: cuttlepop/slipstack/… + water-cane.
- **Aquilo**: `decoratives-aquilo.lua` (icebergs, drifts, decals) · **Vulcanus**:
  `decoratives-vulcanus.lua` (volcanic rocks, cracks, stains, pumice) · **Fulgora**:
  `decoratives-fulgora.lua` (not on the merged map).
- Rule of thumb: a decorative whose prototype lives in base is Nauvis-native; anything in
  space-age belongs to its namesake biome. `map-generation/terrain.lua` then applies the
  masks: Nauvis natives get `mask_nauvis_territory`/`mask_nauvis_deep` (+ the volcano-rim
  feather loop), Gleba natives get `mask_gleba_territory`/`mask_gleba_fade`, etc. Never
  gleba-confine a Nauvis native (`mask_gleba_territory("green-*-grass", …)` was the bug that
  carpeted all of Gleba with Nauvis grass).
- **Exception — shared prototypes**: vanilla Gleba itself rebinds ~15 base prototypes to
  gleba-specific expressions via its planet `property_expression_names`
  (`decorative:<name>:probability` → `gleba_<name>_probability`) and grows them as its own
  desert-province flora: desert bushes (red/white), pitas (red/green/green-mini), green
  croton, green-bush-mini, the five mud/lichen/shroom decals, and green-carpet/hairy grass.
  EoN restores those via `terrain.mask_gleba_shared(name, type, "gleba_…_probability")` —
  the nauvis-side mask is applied first, then the whole thing becomes
  `if(eon_gleba_mask, <vanilla gleba formula>, <nauvis expr>)`. The gleba formulas read
  `gleba_aux`/`gleba_moisture`/`gleba_elevation`, which the mod has re-pointed to the
  blended fields, so deep south evaluates byte-identical to vanilla. Consequences:
  green-carpet/hairy grass are NOT leaks in gleba anymore (vanilla grows them) — the decor
  e2e probe only asserts the nauvis-only tufts (green-small/brown-carpet/hairy) stay out.
  Vanilla gleba also registers the red/purple/cream `*-nerve-roots-veins-*` decoratives;
  the original mod referenced non-existent unprefixed names and they silently never placed —
  they are (re)registered and masked like the other gleba natives.

### Gotcha: gleba-region masks are volcano-excluded, territory masks can't gate volcano ground

- `eon_gleba_region(t)` = `eon_mask_off_vulcano_terrain(if(transition > t, 1, 0))` — **on volcano
  ground it returns -inf, not 0**, because volcano > gleba in the priority stack. So
  `eon_mask_off_gleba_territory(e)` reads as "alive" on a deep-south volcano, and wrapping a
  volcano-rim allowance in it does nothing where it matters.
- To gate something *on volcano ground* by map side, compare the raw field instead:
  `if(eon_gleba_transition > 0, -inf, …)` for the Nauvis side, `< -40` for the gleba side
  (never the territory mask). The volcano-rim feather (`eon_feather_volcano_rim`) and the
  `trees_forest_path_cutout_faded` rim branch both gate this way — a volcano deep in Gleba
  territory gets no Nauvis decoratives/trees on its rim, and deep-nauvis volcanoes get no
  Gleba transition flora on theirs.
- `eon_aquilo_mask` is *not* volcano-excluded (pure elevation `eon_aquilo_land > -1`), so
  `eon_mask_off_aquilo_territory` gates fine on volcano ground (used inside the rim feather).

## Boundary feathering rules (the ONE method for every boundary)

**The sign rule — the edge case behind every "decoratives covering everything" leak:**
probability snapshots are SIGNED (negative = no spawn). `-inf` must REPLACE the probability via
`if(mask, -inf, expression)` — it must NEVER be multiplied by the signed expression:
`negative_snapshot × -inf = +inf = spawn at MAX density in the very region being excluded`.
The hard masks (`mask_nauvis_territory` etc.) never leaked because they are `if()`-replacement;
every "fade" iteration that multiplied leaked (both `min()` and product compositions of
`expression * <fade-that-can-be--inf>`). Safe forms: `if()` branches; and multiplying a
`-inf`-returning function by a non-negative constant (`4 * off_ammonia(snap)` is safe — on
ammonia it is `-inf`, elsewhere the signed snapshot alone, no product of two). Unsafe:
`signed_expr * <anything that can be -inf>`. The `_fade` functions are
`if(eon_gleba_transition > t, -inf, ... if(mask, -inf, ... expression * clamp(..., 0, 1)))` —
exclusions replace, only the 0..1 feather multiplies.

**Tile-name trap:** gleba highland tiles reach ~700 tiles NORTH into nauvis (`mask_gleba_fade
(-70)` — the wide mixing band by design). A grass tuft on a `highland-dark-rock` tile in that
band is NOT a leak (transition ≤ 0 there = functionally nauvis). Judge a position's biome by
`eon_gleba_transition` / territory, never by the tile name — the probe classifies by transition
for this reason.

**The design (v7):** every decorative gets ONE helper call — hard mask (`mask_X_territory`) or
`_fade`. `eon_mask_nauvis_territory_fade(e, t)` (grass, t = 0): full on nauvis, feathering out
over the last ~1 transition (~10 tiles) before the gleba line, zero south of it, zero on
volcano ground (volcanoes are harsh), zero on aquilo/ammonia. `eon_mask_gleba_territory_fade(e, t)`
(transition flora leaders, t = -1): the mirror. No volcano rings, no boost, no floors — every
attempt at those read as "covered" in live tests. `eon_fade(expression, field, lo, hi, floor)`
is the generic primitive for the aquilo/volcano-native blends (`eon_mask_volcano_fade`,
`eon_mask_aquilo_*_fade`) — full while field ≤ lo, linear fade to floor by field = hi, `-inf`
past hi (the expression is passed INSIDE, so its `-inf` replaces — sign-safe).

**Units gotcha:** `eon_gleba_transition` grows ~0.1-0.5 per tile, so a fade band of N transition
units is roughly 10×N tiles. The old gleba-flora threshold `-40` was ~400 tiles of flora into
nauvis. Short fades use single digits (1 = ~10 tiles).

## How we work (agreements, not feature details)

The feature's requirements live in `features/lua-territory.feature`. This section is
the other half: how the code is written and verified, learned the hard way in one
session and worth not learning twice.

- **No fallbacks that change behaviour.** A chain of "if that fails, do something
  lesser" is where defects go to hide: every one of them was added to keep a symptom
  away, and each masked the thing it was standing in for. A unit that spawns with no
  body, a path cropped to a fragment, a territory claimed and then left unguarded —
  all read as "good enough" in a log and none of them are. One path per outcome; if
  the good path is impossible, the claim is wrong and gets dropped, not degraded.
- **An anomaly is a log line and a counter, never an `error()`.** This code runs per
  chunk event; raising there takes a long game down the moment a new chunk reveals
  one awkward cone. There is no `error()` in the shipped path at all: the mirror
  calls `bit32` directly (Factorio's Lua 5.2.1 has it, and so does the lua5.2 the
  Dockerfile installs), and a Lua without it fails at the first use naming
  `bit32` itself, which is the same answer with no code to maintain.
- **Never swallow an error to carry on with a default.** A `pcall` around a lookup
  that then falls back to a constant turns a hard error into a plausible-looking
  number: the prototype read failed with "LuaGameScript doesn't contain key
  entity_prototypes" and every log line said "63 nodes" as if the prototype had been
  asked. If reading something can fail, the failure must be visible; if it cannot
  fail, the `pcall` is cargo cult and should go.
- **Assert that an edit landed.** `str.replace` with an anchor that no longer
  matches changes nothing and says nothing. Twice in one session a guard edit was
  lost this way, and once the lost word ("waiting" for "unseen") silently made
  every cone permanently unclaimable. Use `assert old in s` before replacing, and
  re-read the function you edited.
- **Measure, don't assume — including about the API.** `distance_from_head` is
  cumulative, not per-segment; `body_nodes` is capped at 63 in the docs and the
  engine takes 106; `get_territory_for_chunk` answers nil for ungenerated chunks;
  `direction` is ignored when `body_nodes` is used. Every one of those was
  "obvious" and wrong. The measurement is usually one rcon call away.
- **One prediction mechanism.** The mirror is the only thing that decides anything
  about a volcano. No component may exist solely to patch a mirror limitation, and
  a feature never gets a second opinion from the terrain.
- **Push decisions to the boundary, but keep the interior honest.** *What* the
  player gets (claim a volcano; guard it; patrol it) is the user's call and the
  playtest's arbiter. *How* it is computed is ours, and the numbers behind it
  belong in the spec or a commit message.
- **One dialect: Factorio's Lua 5.2.1.** No compatibility shims, no second
  implementation "for the standalone runs" — the mirror runs in-game or under the
  same 5.2 the Dockerfile installs. Dead arithmetic in a noise chain is the worst
  kind of dead code: no test executes it, so it drifts and is found only when the
  noise is subtly wrong.
- **Two loops, deliberately different shapes.** The gate
  (`run_spot_mirror_tests.py`) is hermetic and unattended: own save, own headless
  server, assertions. The live loop (`live_server.py` + `rcon_probe.py` /
  `rcon_coverage.py` / the mod's `eon-*` remotes) is a *running* game for questions
  a gate cannot answer. Do not merge them, and do not use one to substitute for
  the other: a gate that only passes because someone walked around a map is not a
  gate.
- **Ask before changing what a number is tuned to do.** `CORE_FRACTION`, the body
  margin, the 3x3 gate: each was measured against a specific complaint. When a
  playtest contradicts one, bring the measurement and the new observation; do not
  quietly re-tune.
- **Report judgement calls as judgement calls.** Purity, unguarded chunks, lens
  chunks, volcanoes that cannot host a guard: the gates print them and the user
  decides. Turning a number the user is still choosing into a hard assertion is
  taking their decision away.

## The runtime spot mirror (noise-mirror/, volcano-territory.lua, control.lua)

The volcano (demolisher) territories are built at RUNTIME from `noise-mirror/`, a
standalone Lua mirror of the engine's `spot_noise` cone placement, wired through
`volcano-territory.lua` + `control.lua`. Setting `eon-volcano-territory`:
`runtime` (default) or `expression` (the old noise-expression index). Only one may
claim chunks — `create_territory` strips the chunks it takes from existing
territories.

**What the mirror answers, and why it is small.** EoN's cones come from two
`spot_noise` systems with `candidate_spot_count = 1`, so per region there is at
most one cone: its centre is the FIRST dart-throw-accepted candidate of that
region's taus88 stream (integer RNG — exact, no noise), and its effective width
is `min(maximum_spot_basement_radius, spot_radius_expression)` = a constant times
`eon_volcano_size_dist(centre)` (ONE 3-octave multioctave per cone). Everything
else the engine does there is the identity at count = 1 or is not needed to place
chunks. **Do not port the biome noise, the starting-spot weights, the tile
ranges or the spot-selection phases** — the game has already rendered the answer,
so the wiring asks the game one question per cone instead (the existence gate).

**Existence is COMPUTED: the engine's own spot density** (feature AC-1).
`noise-mirror/density.lua` ports the `density_expression` of `eon_volcano_spots_at`
(`volcano_area / volcanism^2 * eon_volcano_spawn_gate` — 32 nodes behind it, three
primitives, and the mirror already had `multioctave_noise`). A cone exists where
that is positive, so the whole "is this a volcano" question is a pure function of
position again.

This is the requirement, and the reason is mechanical: **chunks are generated one
at a time, so no per-chunk or per-tile test can see a whole volcano.** Every
tile-based version of the gate was therefore a function of what the player had
revealed, and that is where the whole family of bugs came from — a claim made on
four chunks of evidence and then wrong (4 of 22 volcanic), a real volcano with no
claim because its rim was revealed first, a claim that had to be retracted, an
audit invented to catch up, an evidence floor, a density *fraction*... **The
shipped path asks the game about the map nowhere**: no `get_tile` and no
`is_chunk_generated` in `volcano-territory.lua`. Both went the same way. A cone is
decided when a chunk of ITS OWN arrives, and the chunk that woke the mod is
generated by definition, so the one engine precondition (`create_territory` wants
a generated chunk in the list) is satisfied by construction rather than by asking.
That is the general form of the rule: a question about the world is a question the
mirror answers, and a question about what the engine has already told us does not
need asking at all.

Gates for the port:
- `tests/density_parity.py` — against the SHIPPED expression at the candidate
  centres the gate is actually asked at (a grid sample said 100% while the game
  disagreed on whole volcanoes, so the sample points matter): **100% sign
  agreement over 1352 centres, worst relative error 3.8e-4**. The gate is a sign
  test, so sign agreement is the correctness criterion and tracking is the accuracy
  one.
- Cross-checked against the engine's own spot selection through the Rust oracle:
  **240 of 240 region decisions agree** in a probe window. So a territory standing
  on non-volcano ground is the ENGINE placing a cone over ocean or ice, not the
  mirror inventing one — a playtest question, not a contract.

**The tile gate that this replaced, for the record.** It asked whether 5 of the 9
chunks around a cone's centre were volcanic. That was strictly better than one
centre tile — a single tile calls a two-chunk lava patch on a shoreline a volcano,
and such a cone claimed 17 chunks of deepwater with a demolisher patrolling the sea
(measured live, seed 3526581861 at 200%: its centre chunk was volcanic, only 7 of
its 17 claimed chunks were). But it was still a tile witness, so it was a function
of what the player had revealed, and everything downstream had to be built to
survive that. The spot density answers the same question with no witness at all.

**A claim needs no evidence beyond the map** (feature AC-2, AC-3). This was the
longest wrong turn of the session and is kept as a warning: for a while a claim was
gated on "at least half the REVEALED share is volcano, and at least nine chunks are
revealed", with the same test run backwards to retract. Both halves existed because
existence came from tiles, and a tile witness is a function of what the player has
walked over -- a 22-chunk disc was claimed on the strength of its first four
rendered chunks (all volcanic: a perfect score and no information), the other
eighteen then revealed as beach, and the same logic had to be undone on retraction.
With existence computed from the spot density, the claim is the cone's disc and
nothing else, and every one of those mechanisms became dead code.


**Membership is geometric — no per-chunk tile read at all.** The claim is the
cone's core disc, `CORE_FRACTION` of its width, tested at each chunk's CENTRE.
Three reasons, all measured:
- A point sample of a 32x32 chunk is a bad description of it, and WHICH point
  matters: at the engine's top-left corner 100% of the chunks out to `d/width`
  0.40 read volcanic, at the chunk centre only 75% of the 0.35–0.40 band does.
  The tiles sit ~16px NW of the cone field, so a corner sample reads the FIELD,
  not the ground. The whole `_at16` noise family existed to compensate for that
  and is deleted.
- The claim radius is DENSITY-AWARE, not one constant: `core_fraction_for` gives
  0.45 at 1x volcanism down to 0.30 at 6x. One constant does not fit every density
  (measured purity of the claimed disc: 99% at 200% and 67% at 600% with 0.45, 84%
  at 600% with 0.40) — not because the volcano is smaller, but because at 6x the
  discs interleave three deep with each other and with the ground the other cones
  leave behind.
- Sampling made the claim depend on GENERATION ORDER (the same volcano got a
  different chunk list depending on which chunks were rendered when the cone was
  decided, and later chunks needed a correction pass). A geometric list is a
  pure function of the map: the same territory everywhere, every load, either
  order. `CORE_FRACTION` (0.40) is the only knob, and it is a measurement: 93% of
  the claimed disc is genuine volcano ground by the centre test, 0.35 is the last
  100% band.
- The claimed AREA is then the disc, not "a chunk whose corner is in the disc" —
  which is what left the claim sitting about half a chunk (+16/+16px) down-right
  of the volcano. No field shift can fix a quantisation bias, and no sampling is
  the way to avoid having one.

**How a chunk finds its cone: one question, asked of the mirror.** `Volcanoes:owner_at(x, y)`
returns the **nearest centre** among the cones whose ground covers the chunk, measured
at the displaced point because that is where the engine reads the field. The candidate
ring is assembled inside that call and is memoised per region, so the whole per-chunk
cost is a hash hit, ONE wobble evaluation and a distance test per cone — **12.7
microseconds** — and nothing about the answer is stored.

- The ring is never inspected by the runtime: every caller passes it straight to another
  method. It is an argument, not an answer, which is why `owner_at` hides it and the
  Builder does not know a radius. The margin is ZERO and was 64 for most of this file's
  life, making no difference: the ring's extent comes from `basement` (a cone covering a
  chunk has its centre within basement + 16 tiles, inside one ring of regions), and over
  1,681 positions at 1x and 6x volcanism, margins 0 and 64 return identical rings at
  every one. `Volcanoes.rings` memoises the ring per (region, margin), which is a cache
  of the candidate LIST and cannot go stale, because existence is a pure function of
  position.
- The ring's cones are tested for coverage with a **plain distance test before any
  wobble**: the displacement is bounded (36.7 tiles measured over 3M samples on three
  seeds), so a point further than `radius + 40` from a centre cannot be pulled inside
  the disc however the noise behaves. Without it the frontier cost 87 us a chunk — one
  wobble evaluation per ring cone, ~25 of them — instead of 3 us.
- A NEIGHBOURHOOD INDEX was built to remove that search and then deleted, because
  keeping it meant enumerating every discovered cone's share to know which regions to
  register: 1.76 ms a cone, in order to save 9 us a chunk, over a reveal with ~18
  chunks per cone. It also brought region registration, tombstones, a merge path, and
  the invariant that a region must never be written before it has been asked about —
  150 lines and four questions (what is a group, when may it be dropped, how do two
  groups merge, may a region hold a cone we never asked about) for a cache that was
  losing on its own terms. Do not rebuild it.

**When a cone is decided** — when a chunk of **its own** is generated. The chunk that
woke the mod IS generated (that is the only way the handler is reached), so if it is
one of the cone's, `create_territory`'s "at least one generated chunk" is satisfied by
construction; if it is not, the answer is "not yet". This replaced walking the whole
share calling `surface.is_chunk_generated` on every chunk event for every waiting
cone: 0.48 µs a call, 241,840 calls over a 1681-chunk reveal at 100% volcanism,
611,762 at 600%. **The claim path now asks the engine about generation nowhere.**
Waiting for the whole DISC is what left big volcanoes half-guarded (live: 387
candidates, 270 generated, no territory); `create_territory` ACCEPTS ungenerated
chunks and they join on arrival, so one call with the complete list is final.

**The created-set is a marker table**: `true` claimed, `"empty"` every chunk of its
disc belongs to a neighbour, `"unseen"` none of its own chunks has arrived yet (asked
again by the next chunk event that carries one, and by nothing else). It is the ONLY
persistent state, and correctness does not depend on the index: a cone that turns up
again is recognised by its marker and skipped, so a stale or wrong index can cost
work but cannot produce a wrong claim.

**The split between overlapping cones is gate-free.** MAX-of-cones (smallest
`d/width`) over the cones the map *would* have, gate or not. A gate answers "does
this cone exist" and every cone answers at a different time, so a split computed
against the decided cones MOVES as more of them resolve: two volcanoes trading
chunks, and a territory that no longer matches the mirror that built it (at 600%
volcanism: 199 chunks in a territory the mirror did not predict, 38 unguarded).
The gate now only decides who gets to CREATE a territory; a cone that turns out
not to exist leaves a small unclaimed lens, which `Builder:audit` refills from the
surviving neighbour's disc.

**The withdrawal only concludes what it can see.** `territory_of` returns
(territory, answerable): `get_territory_for_chunk` answers nil for an UNGENERATED
chunk, and a cone whose centre is still unrevealed has no visible territory, so
"no territory" and "cannot see one" must not be confused. Two bugs came out of that
distinction: the audit "rebuilding" healthy territories it could not see, and the
withdrawal marking a cone dead without destroying the territory it pointed at,
leaving a live territory with a marker pointing at nothing.

`cone_by_id` takes a `raw` flag for the same reason: the rejected cone's GEOMETRY
(its centre and disc) is still worth having, and the gated lookup returns nil for
exactly those.

**Priority, and the audit that used to defend it, is gone.** A volcano territory
used to be re-asserted every 60 s: it rebuilt a territory the game destroyed with a
deleted chunk, and refilled holes inside a created cone's disc. Both jobs rested on
premises that no longer hold. Rebuilding a deleted territory is a dev or script
action, and the only other case was a save from a build with a different claim
shape — migration, and 0.1.13 is unreleased. Refilling holes was not a no-op but
actively wrong: ownership between overlapping cones is decided UP FRONT and the
claims are disjoint (`overlapping cones yield disjoint chunk sets`), and the fill
tested only CLAIMED neighbours, so it took ground from a cone that had not claimed
yet and handed it back when that cone did. Measured, it re-claimed 5 chunks at
600%. The claim is now correct by construction and nothing re-asserts it.

**Patrol path and units are ours** (feature AC-7..AC-12). `create_territory{chunks, patrol_path}` takes
a path, so the mirror builds one: a ring inside the claimed disc, 32 points (16
made the corners visible), radii 0.78 → 0.58 → 0.38 of the core radius until a full
loop survives, clipped to the cone's own chunks (a split volcano must not patrol
across the border into its neighbour's ground) and skipping water.

The demolisher goes in with `create_segmented_unit` in the SAME pass that creates
the territory, with `body_nodes` = the patrol path resampled at one tile, so the
WHOLE animal exists at once, lying along the route it is about to walk — the
default spawn is the head only, and the body grows behind it as it crawls. The
node count is the prototype's own (`entity_prototypes[name].segment_engine.segments`,
≤63) and it fills `body_nodes`, then `extended = true`, then a bare position.
ONE unit per territory (two share the single patrol path and walk into each other,
observed live), sized by `Volcanoes:size_fraction(cone)` (the cone's width over the
largest basement, NOT `eon_volcano_size_dist`: the two spot systems differ only by
`size_mult`, so at size_dist 1.0 a 318px cone and a 530px cone both read as "big" —
measured 0/4/14 by size_dist versus 2/9/7 by width). A territory below 10 chunks is
a rim sliver and gets no unit.

Placement CAN fail even so, and the reason is timing, not effort: the claim lands
when the first volcanic chunk of a cone is revealed, which is often a single rim
chunk of beach with nothing standable on it. So the unit is placed on the next
chunk event that brings ground (`place_pending_units`), with the audit as backstop.
The same reasoning applies to the claim itself: an `"unseen"` cone is retried by
the next chunk event that carries one of its own chunks, so nothing depends on
event timing.

**The audit, the priority pass and the lens refill are all gone**, and so is the
60 s re-assertion. Each existed because the split was once computed against cones
that had not resolved yet, so a claim had to be re-asserted, holes refilled and
lenses re-attributed. Existence is computed (the density is a pure function of
position), the split is settled up front from geometry, and a placed cone is
recognised by its marker — so there is nothing left to re-assert.

**The load path is empty, on purpose.** `on_load` may not touch `storage` (it is
CRC-checked and a write aborts the load) and has no `game` object at all, so all it
does is drop the cached builder. There is no catch-up, no `caught_up` flag and no
load-time scan of the generated chunks: `on_chunk_generated` is the only thing that
feeds the builder, and a save that already has its chunks generated already had its
events. The scan existed for saves explored before this path existed, and 0.1.13 is
unreleased, so it was migration with nothing to migrate.

It was, however, holding the GATE's timing in place, and that is the part worth
knowing if it ever comes back: the e2e probe measured on the first tick, and the
scan claimed inside the mod's own `on_init`, so by then the territories existed.
Without it, the events for everything generated in `on_init` are delivered in the gap
AFTER that handler returns, and the probe measured an empty map -- no territories at
all, then three after its own delete-and-regenerate step, failing every ordering
assertion in between. The probe now waits four ticks (`MEASURE_AFTER_TICKS`; a
headless server with no players advances at ~0.25 ticks/s, so that is ~12 s per
run). That cost is the price of the deletion, paid in the harness where it belongs:
the game itself never paid it.

**Pruned on purpose: the spot-deployment warp** (`eon_detail_noise_at` on the
query, up to ~25 tiles). Measured cost of dropping it (`tests/spot_mirror_parity.py`):
0.8–3% of chunks change owner, always within one chunk of a cone's rim.

**Gates** (`python3 tests/run_spot_mirror_tests.py`, ~2.5 min):

| gate | what it proves |
| --- | --- |
| `lua tests/noise-mirror/selftest.lua` | 35 assertions vs GAME-captured vectors + closed/disjoint footprints + the gate contract + id→cone lookup + size_fraction ordering |
| `tests/spot_mirror_parity.py` (4 configs) | 0 unexplained owner mismatches vs the engine's own selection through the Rust oracle; width to 2.8e-06 relative, field to 2.7e-06 |
| `tests/density_parity.py` | the existence gate vs the shipped density expression at the candidate centres: 100% sign agreement, 3.8e-4 worst relative |
| `tests/noise-mirror/` | where the mirror's dev-only files live: `selftest.lua` (no Factorio, no Python, no oracle), `bench.lua` (the map-reset workload), `dump.lua` (per-chunk owner/width, also `spot_mirror_parity.py`'s data source) and `vectors.lua` (the game-captured fixture). Kept out of `noise-mirror/` so that directory is exactly the closure the game loads, and out of the release zip, which skips `tests/` |
| `tests/live_server.py` | a real server in the BACKGROUND with rcon, for questions that need a game: `start`/`log`/`stop`/`restart`, then `rcon_probe.py` / `rcon_coverage.py`. `EON_LIVE_EXTRA=behemoth-enemies_0.0.8.zip` loads a mod beside ours (a dev probe in `tests/` is found by its bare name), which is how a compatibility question is asked without a second mod directory; `EON_PROBE_EXTRA` is the same one-liner for `probe_runtime_territory.py`. Both are off unless set, so no gate pays for them. | A session with a process tool should `prepare` once and run `command` under it instead: the tool owns the process, watches its stdout and notifies on exit, which a script cannot do for a session that is not running. factorio writes `server.log` ITSELF (`--console-log`), so the file is identical either way -- and that flag is what makes it work, since a `\| tee` pipeline puts a shell between the tool and the game (measured: the shutdown line is lost) and a plain `> server.log` leaves the tool nothing to watch |
| `tests/probe_runtime_territory.py` (100% + 600% volcanism) | one territory per cone and that territory is exactly the mirror's chunk list; every volcano territory has a whole guard; a cone decided while most of its disc is still unrevealed; regenerating the same chunks changes nothing; every claim line cross-checks against a territory on the surface; plus REPORTED purity / unguarded / no-guard counts |
| `features/lua-territory.feature` | the acceptance criteria themselves (AC-1..AC-15), each with the probe that proves it — the contract, not a summary |
| `tests/builder_test.lua` | the claim path with no Factorio at all: one cone decided per event, a demolisher with a body, a second event creating nothing, a cone with no chunk of its own left alone -- and the per-chunk candidate set: CLOSED (nothing that overlaps a candidate is outside it, or a chunk could go to the wrong cone), one owner repeatably, and a cone reachable from its own region's coordinates. That block exists because a wrong candidate set shows up as a wrongly-claimed volcano, and the e2e tolerates 8 differing chunks, so it is not a net for this. |

Judgement calls the gates deliberately do NOT make: disc purity (the
`core_fraction_for` trade-off) and share-level split bookkeeping between
overlapping volcanoes, and a 16+ chunk territory with no demolisher (lava-heavy ground at 6x can
leave nowhere to stand one). All are reported, and the playtest decides —
`tests/rcon_coverage.py` prints the same thing as a per-chunk map. With the density gate in
place and no tile reads at all: at 200% (a normal playtest map) 115 of 115 claimed
chunks match the mirror exactly, 99% of them stand on rendered volcano, 0
unguarded, 0 unpredicted, 0 outside their own disc, every 16+ chunk territory
patrolled; at 600%, 327 of 327 exact and 100% on volcano. So the density gate is
not a compromise -- the engine's own placement answer lands on the volcano.

**What the whole thing costs per chunk**, measured rather than assumed, and the
findings that got it there — each one a question about the world that the mirror
answers, asked over and over:
- the cone's share was recomputed for every cone still waiting, on every chunk
  event in reach: 8.42 ms per chunk at 100% volcanism, 20.7 at 600%. It is a pure
  function of the cone, so it is enumerated once, when the territory is made.
- the share was then walked calling `surface.is_chunk_generated` to satisfy one
  engine precondition: 0.48 µs a call, 241,840 calls over a 1681-chunk reveal at
  100% and 611,762 at 600%. The chunk that woke the mod IS generated, so the
  precondition is met by construction whenever it is one of the cone's own.
- the ring's cones were then tested for coverage with a wobble evaluation each: 87 µs
  on the 62% of chunks whose own region holds no cone, because 25 ring cones is 25
  noise evaluations. A plain distance test first — the wobble can only pull a point in
  by its measured 40-tile bound — makes it 3 µs.
- with those gone, the per-chunk cost is **0.13 ms at 600% volcanism** against
  0.42-0.48, from two hash lookups and a handful of distance tests.

The lesson worth keeping: **every one of those was a recomputation of something the
mirror had already decided, and two of them were answering a question the engine had
already answered** (the chunk that woke us is generated). None of them needed a cache;
they needed the question to be asked once, of the thing that could answer it. And the
one cache built to fix the last of them — a region index of overlapping-cone
"neighbourhoods" — cost more than the thing it replaced (1.76 ms per discovered cone to
save 9 µs per chunk) and brought 150 lines with it. Measure a cache against the
alternative of not caching, on the quantity that actually varies, before building it.

**A server of our own** (`tests/live_server.py`) -- the loop that made this
debuggable. `start` builds a save, starts a headless server detached in the
background with rcon on 27016, and waits for rcon to answer; then every question
is one call (`rcon_probe.py`, `rcon_coverage.py`, or the mod's own log), and
`log` / `stop` / `restart` manage it. The end-to-end probe is the opposite on
purpose: it runs to completion unattended, and that is what it is for.

"Why is there no territory here" is answered from the log, by hand: the claim line
carries each cone's density and share, a `no chunks of its own` line marks a cone
whose whole disc went to a neighbour, and an absent line means the cone was never
decided. Every cone the mod has decided is in the claim lines, so a volcano with no
territory and no line was never a candidate -- which the density in the surrounding
candidates' lines explains (negative = the map put no volcano there). That answer was
a remote once (`eon-why`) and is arithmetic plus a log now.

**Talking to a RUNNING game** (the fast loop; no restart, no 20 s probe):

| tool | what it does |
| --- | --- |
| `python3 tests/rcon_probe.py` | summary: setting, territories, decided cones, generated/volcanic/territory window counts |
| `python3 tests/rcon_coverage.py --at=X,Y [--radius N] [--units]` | one character per chunk around a gps point: `#` claimed+volcanic, `o` spill, `.` HOLE (unguarded volcano), `,` plain |
There are NO remotes and no commands: the questions above are asked of the log, or computed by the caller. Everything the old `eon-status` reported is either mirror arithmetic (the probe requires `noise-mirror/` and can do all of it) or a fact the surface answers directly (`get_territory_for_chunk`), and the one column that was mod-private -- the `created` marker -- is what the claim log line records. The cross-check the gate does with it is the invariant stated from the two sides that hold the facts: every `[eon] volcano <id>: centre …` line up to the first `REPORT-COMPLETE` sentinel must have a territory holding that cone on the surface. A remote is a request/response channel and a log line is a broadcast, so anything a *test* needs to be told is asked across those two.

**Headless gotchas hit while building this** (all verified on 2.0.77):

- The control stage is **Lua 5.2**: no `&`, `<<`, `>>`, `//`, no `math.cbrt`, no
  `math.log2` in 5.3+ — but `bit32` exists, and `storage` (not `global`) is the
  persistent table (`settings.global` is the MOD SETTING table, and a missing-key
  read on it raises). `tests/eon-probe-lua` reports the dialect; `require()` only
  works while `control.lua` is being parsed; a listener registered inside
  `on_init` misses the events that same `on_init` raises, and `on_territory_created`
  is not delivered until `on_init` returns — measure `surface.get_territories()`
  instead of counting events.
- `on_chunk_generated` is delivered only BETWEEN top-level event handlers, so
  anything that must observe the mod's reaction mid-`on_init` cannot generate chunks
  and look — the handler has not run yet. That is why the mod used to expose
  `eon-decide-at` / `eon-decide-area` to be asked directly, and why the probe stopped
  doing so: the delivery order turned out not to be the variable, and asking the mod
  made the probe test its own request rather than the game. The probe reads the
  mod's log lines and the surface instead.
- `force_generate_chunk_requests` returns before the whole disc is RENDERED, so
  anything that must observe settled ground has to ask again a moment later (the
  probes do). Note what this does and does not affect: the CLAIM is unaffected —
  it is a pure function of the map and `create_territory` holds ungenerated chunks —
  but a guard can only be placed on ground that exists.
- `LuaTerritory` is a HANDLE: `get_territories()` and `get_territory_for_chunk()`
  return different Lua objects for the same territory, so it cannot be used as a
  table key — key on its sorted chunk list.
- `on_load` has no `game` and must not write `storage`; `on_nth_tick` is the first
  moment both are available.
- `game.players` / `game.surfaces` are custom tables: `ipairs`/`pairs` on them
  raises "table expected, got userdata". Walk them by index with `game.get_player`
  / `game.get_surface`.
- `remote.call`'s first argument is the INTERFACE name (`eon-volcano-territory`),
  not the mod name; a wrong name fails with "Unknown interface: …".
- `create_segmented_unit` needs a `position` (the doc listing omits it) and takes
  `territory =` to attach the unit to one. `regenerate_segmented_units` is a plain
  function value: `t:regenerate_segmented_units()` raises "Expected 0 arguments
  but 1 were given" — but it only ever adds ONE unit, sized by the engine's
  variation expression, so it is not used any more.
- Reading a field of an INVALID `LuaTile` (what `get_tile` returns for an
  ungenerated chunk) raises "LuaTile API call when LuaTile was invalid". It must be
  inside the same `pcall` as the `get_tile` call, or it aborts the event handler
  and with it a whole map generation.
- `on_chunk_generated` carries `position` (one ChunkPosition in 2.0); its `area`
  is not indexable the way a BoundingBox literal is.
- `surface.create_territory` ACCEPTS ungenerated chunks in the list (probed: a
  territory created with 37 of 41 chunks ungenerated kept all 41, and they joined
  once generated). `get_territory_for_chunk` returns nil for a chunk whose
  territory has not been generated — so count through the territory object, not
  through per-chunk lookups.
- `regenerate_chunks` does not exist in 2.0; `delete_chunk` + request is the
  equivalent way to re-fire `on_chunk_generated`.
- Headless cannot force a mod setting for a save run: `--create`/`--start-server`
  read the PROFILE, not the prototype, so a probe's `data.lua` override makes the
  data stage and the control stage disagree. Test the switch at the data stage
  (`--dump-data`), where the decision lives.
- Mod settings live in the write-data dir as `{mod: {setting: {value: …}}}` — but
  a fresh temporary write-data dir is not read either; do not spend time on it.
- **rcon** (`rcon_probe.py`, `rcon_coverage.py`): a Lua error over rcon comes back
  as an EMPTY response, so wrap probes in `pcall` and report the error through
  `rcon.print` (NOT `game.print`, which does not reach the rcon response). A long
  single `/c` payload (or any shape the server dislikes) can come back empty while
  every fragment of it works — send many small commands instead. `/c` runs in
  BASE's script scope, so `storage` there is base's, and `require` does not work
  there, so the mirror cannot be loaded from the console.

## Bash tool hygiene

- Do **not** nest heredocs inside a `bash` tool call that is itself wrapped in a heredoc — the
  outer one terminates at the first inner terminator, silently truncating the script. Write
  multi-file test scripts with the `write` tool instead.