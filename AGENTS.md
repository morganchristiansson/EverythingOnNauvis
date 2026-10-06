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

**The mod's own expressions are already clean**: zero of the documented
anti-patterns (`1 + 2 + x`, `x + 0`, `x * 1`, `x ^ 2`, ...) across all 1260
compiled expressions; the only hits are VANILLA expressions the merged map pulls
in (6 x `size ^ 0.5` in gleba richness, 18 x `c * (a + b)` in vulcanus) -- the
upstream-contribution candidates, not mod work.

**What the 3.5x is, priced by ablation**: the masks are one shared `if()`
condition per (prototype, boundary), already at the floor; the real add is the
other planets' field generators, which run for EVERY tile (no short-circuit in
`if()`). Per-field prices (no overlap): `eon_gleba_blend` 0.1%, `eon_gleba_
moisture_vanilla` 0.1%, `eon_aquilo_persistance` 1.0%, `eon_aquilo_macro` 0.6%,
`eon_gleba_elevation_vanilla` 2.1%, `eon_aquilo_detail` 2.0%, `mask_gleba_shared`
1.1% of the real program. Sharing decides how many times an expression is
COMPILED; cost is how often it is EVALUATED -- both "the mask is only 0/1" and
"the field is shared" are the wrong question.

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
  map_gen_settings onto nauvis so the same surface generates vanilla gleba — that works).
  `game.create_surface(name, settings)` DOES honor map_gen_settings, with two measured
  requirements (probe-verified 0.1.13, 2.0.77, seed 12345; see `tests/eon-probe-clone/`
  + `tests/probe_clone_surface.py`): the settings must be passed AS the flat
  MapGenSettings table, NOT wrapped in a `{map_gen_settings = ...}` key (the wrapped
  shape reads as an empty settings table and explodes); and
  `default_enable_all_autoplace_controls` must be explicitly `false` — with it true
  or unset, the game autoplaces EVERY decorative and dies compiling
  `decorative:fulgoran-gravewort:probability` (its default references
  `control:fulgora_islands:frequency`, which a non-fulgora surface does not define).
  A clone made this way renders byte-identical volcanic terrain to the real map
  (319 volcanic chunk centres of 794) and the mod claims it while it is still
  UNASSOCIATED (`planet == nil`) — the identity gate is the surface's own settings,
  never the planet.
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
territories. The design narrative and measured history behind everything in this
section: `features/lua-territory.feature`, "Design appendix".

Contracts that must hold (each probe-verified; the narrative says why, and what
failed before):

- **The mirror answers and only that**: cone centres (the taus88 integer stream —
  exact, no noise) and widths (`eon_volcano_size_dist`, one 3-octave multioctave
  per cone); existence is COMPUTED from the engine's spot density (feature AC-1).
  Do not port the biome noise, the starting-spot weights, the tile ranges or the
  spot-selection phases. It asks the game about the map NOWHERE; the shipped path
  has no `get_tile`, no `is_chunk_generated`, no per-chunk tile read.
- **Decisions**: a cone is decided when a chunk of ITS OWN arrives (that chunk is
  generated by definition, satisfying create_territory's one precondition); the
  claim is the mirror's chunk list, one `create_territory` per slice of the cut;
  markers persist (`true` / `"empty"` / `"unseen"` / per-slice table) and are the
  ONLY persistent state — correctness does not depend on them (a stale index costs
  work, never a wrong claim). The load path is empty on purpose. The markers live
  PER SURFACE: `storage["eon_volcano_territory_runtime"]` is keyed by `surface.name`
  (the only identity that survives a save/load; indices are session-local), because
  a reset can replace the map either by clearing the current surface in place or by
  running the next round on a NEW surface created alongside it — a new surface starts
  with no state and the old surface's markers go with it. (The primary surface, index
  1 "nauvis", is NEVER deletable: `LuaSurface.deletable` is false for it, hardcoded
  in the engine — probe-verified 2.0.77, and no prototype attribute exists anywhere —
  so the planet can never lose its surface and `LuaPlanet::associate_surface` can
  never move it to a runtime surface; "swap by re-associating the nauvis planet" is
  not something the engine allows. `on_pre_surface_deleted` still matters for every
  CREATED surface, which are all deletable.) Which surface is "the" map
  is decided by the surface's OWN settings — the `vulcanus_volcanism` autoplace
  control in its map_gen_settings must be present — never by the planet association
  or the literal name: the reset scenario pre-generates the next map on a SECOND,
  unassociated surface (a planet can only hold one surface), and the clone must be
  claimed while it is still unattached, because a pre-generated chunk never re-fires
  on_chunk_generated and a map that waited for association would arrive unclaimed.
  The control is the merged map's fingerprint (terrain.lua adds it to nauvis at the
  data stage; no vanilla surface has it) and the mirror keys off the same control.
  Both on_surface_cleared
  and on_pre_surface_deleted drop just that surface's markers and cached builder; a
  0.1.13-and-earlier save's single shared marker table is hoisted under the surface
  name on first use.
- **The legal swap: a cloned planet.** Since the primary can never be dissociated (see
  above), a scenario "swaps the map" by running the game on `nauvis2` — an exact clone
  of the merged planet enabled by the startup setting `eon-nauvis2-clone` (off by
  default, so vanilla freeplay keeps one Nauvis). `LuaPlanet::create_surface`
  materialises the clone's surface from the planet prototype (which the deepcopy
  inherits, so NO settings-table juggling and no gravewort compile problem — verified
  live: surface carries the merged vulcanus_volcanism control, `deletable = true`,
  planet = nauvis2, and the mod claims its volcanoes through the same is_merged_map
  gate). Deletion of that surface is legal, so the reset is: delete →
  create_surface → teleport players; on_pre_surface_deleted clears the surface's
  state, and `prototypes/nauvis2.lua` (required from data-final-fixes) rewires
  `aquilo-solar-system-edge.from` to nauvis2 — unless `eon-restore-space-locations`
  is on (default since 0.1.13), in which case the edge stays at aquilo — hides the
  original nauvis planet and NILS its map_gen_settings: the dummy primary surface
  only stages a swap, so a vanilla engine-default map there is cheaper than the
  merged program (world creation falls back to vanilla when the settings are
  absent — probe-verified 2.0.77: --create succeeds, surface 1 tile grass-1, planet
  still associated — and the deepcopy that made nauvis2 has already taken the
  merged settings), and re-sweeps every `default_import_location`
  onto the clone (remove-planets.lua had pointed them all at nauvis). There is NO
  data-stage flag to hide a SURFACE — only the planet: hiding the dummy surface
  from the per-force list is the scenario's job at runtime, and the calls are
  `force.get_surface_hidden("nauvis")` / `force.set_surface_hidden("nauvis", true)`
  with a DOT, not a colon (plain function values: the colon form raises "Expected
  1 argument but 2 were given", probe-verified 2.0.77 — the same class as
  `regenerate_segmented_units`). The scenario should re-assert it after any load. Probe-verified live (`tests/eon-probe-clone/` + rcon, 2.0.77):
  claims land on the planet-created surface.
- **Data-stage settings lookup uses the SHORT name.** `settings.startup["eon-nauvis2-clone"]`
  works in data-final-fixes; the mod-prefixed `"EverythingOnNauvis-morganc.…"` form is
  nil and aborts data loading ("./prototypes/nauvis2.lua: attempt to index field …
  (a nil value)", probe-verified). Same convention as the control stage.
- **The four non-Nauvis planets and `eon-restore-space-locations` (default ON, 0.1.13):**
  ON deletes the `planet` prototypes (vulcanus/gleba/fulgora/aquilo) in
  data-final-fixes and re-adds them as `space-location` prototypes — the same
  prototype as solar-system-edge and shattered-planet, the engine's native
  "travel here, never land" — restores every vanilla space-connection and the SSE
  edge's `from = "aquilo"`. OFF is the old behavior: planets hidden with
  map_gen_settings nilled, all interplanetary connections deleted, the only trip
  nauvis->solar-system-edge. The engine's asteroid fields follow the location
  (`asteroid_spawn_definitions` copied from the planet); every
  `default_import_location` stays swept to nauvis/nauvis2 either way because the
  destinations have no surface to import from. Data-updates (map-generation/*)
  reads the four planets' map_gen_settings to build the merged nauvis — deletion
  happens AFTER, in data-final-fixes, so the merge is unaffected. Probe
  (`tests/rcon_solarsystem.py`, 2.0.77): `game.planets` = nauvis only, the four
  destinations are `space_location` prototypes, 9 connections, and
  `aquilo-solar-system-edge = aquilo>solar-system-edge`.
- **The short-circuit**: `on_chunk_generated` asks `get_territory_for_chunk` first
  and skips when a territory holds the chunk — safe because the surface here only
  holds territories the mod created and a created territory always carries the
  marker, so a non-nil answer can only mean "already claimed". The marker is the
  memory the surface cannot hold: unseen/empty cones, and territories removed via
  `destroy` / `delete_chunk` / `clear_territory_for_chunks` / map reset. Conquest
  needs no marker: probe-verified, a territory outlives its last demolisher
  (valid, still answers, regenerates — the engine never auto-destroys an
  unguarded territory, it just stops showing it).
- **Ownership**: `volcano-patrol-path.lua` owns every patrol loop (whole-claim
  circle, wedge outer arc, rim) and the shared primitives (`ground_radius`,
  `edge_radius`, `set_for`, `rivals_of`, `chunk_key`, `start_north`); the mirror
  owns the territory edge (`disc_chunks`); `volcano-split.lua` is the cut
  DECISION only (fraction bounds, angle hash, chunk split, class fitting,
  separation, slices/holds); the Builder owns when-to-decide.
- **Pruned, do not rebuild**: the spot-deployment warp (`eon_detail_noise_at`, up
  to 25 tiles), the audit / priority / 60 s re-assertion passes, the load-time
  catch-up scan, the region index of overlapping cones (cost more than it saved),
  the tile-witness existence gates.
- **Cost, measured** (`tests/split_bench.lua`): steady state ~1.5 µs per chunk
  event (surface short-circuit + died mirror lookup); the once-per-cone plan is
  cached in `Builder.plans` and the cache is checked FIRST in `create` (the retry
  path for a waiting slice must not re-enumerate the share); worst decision ~3 ms
  (share ~1.7-2.1 ms at its floor, wedge internal ~1.0-1.2 ms) — see the table
  below. Every past cost finding in the feature appendix is history; the lesson is
  one sentence: a question the mirror already answered, or the engine already
  answered, must not be recomputed or re-asked per chunk.

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
| `tests/builder_test.lua` | the claim path with no Factorio at all: one cone decided per event, a demolisher with a body, a second event creating nothing, a cone with no chunk of its own left alone, and the per-chunk candidate set: CLOSED (nothing that overlaps a candidate is outside it, or a chunk could go to the wrong cone), one owner repeatably, and a cone reachable from its own region's coordinates -- plus the CUT: two disjoint pieces that are the whole claim, guards one rung apart, every patrol point on its own piece, and a second piece claimed when a chunk of its own arrives. That block exists because a wrong candidate set shows up as a wrongly-claimed volcano, and the e2e tolerates 8 differing chunks, so it is not a net for this. |
| `tests/split_probe.lua` | not a gate: the census of what a seed WOULD split (`lua tests/split_probe.lua <seed> <volcanism frequency>` prints the pairs and the reason every uncut cone was left alone). The tuning record for the cut. |

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

**Cost history**: the per-chunk cost findings that got this section here are in the
feature appendix; the current numbers are the split-cost table below, and the
lesson is one sentence — a question the mirror already answered, or the engine
already answered, is never recomputed or re-asked per chunk.

**What the split costs, measured the same way** (`tests/split_bench.lua`, seed
12345, ±4 regions, fake surface limited to the two writes):

| | 100% | 200% | 600% |
| --- | --- | --- | --- |
| steady state, per chunk event | ~2 µs | ~1 µs | ~1 µs |
| first touch, per chunk event (avg) | 92 µs | 98 µs | 108 µs |
| worst single event (cone's first contact) | 10.8 ms | 9.5 ms | 9.6 ms |
| plan once per cone (avg / worst) | 4.1 / 8.5 ms | 3.6 / 6.7 ms | 3.7 / 7.4 ms |

Clean decomposition (min-of-5 on the worst cone, `tests/split_bench.lua`):
share ~1.7-2.1 ms, wedge/fit internal ~1.0-1.2 ms, worst decision ~3.0 ms --
about 18% of a 16.66 ms tick (the colder one-shot numbers above include
GC/first-call in the standalone interpreter). Both halves are at measured
floors: the share is a pure function of the cone, pruned by an un-wobbled
bound and wobble-shared between the disc and ownership tests (disc_chunks),
and the two slices of a cut sweep a full circle of UNIQUE directions at 2x
density (the playtest's dent measure), so no wobble is evaluated twice. The
class scan over CUT_STEPS is 42 trivial size_fraction calls. The only
structural lever left is cross-event deferral (drain plans on a tick) --
refused because the headless gates cannot tick, and the spike is inside the
budget with 5x margin, paid once per cone. The plan is cached in `Builder.plans`
and the cache is checked FIRST in `create` -- the retry path for a partially-claimed
slice does NOT re-enumerate the share (that re-enumeration, on every event in
reach until the cone settles, was the 362 µs first-touch average; the cache-first
reorder made it 92 µs: the share is a pure function of the cone, so it is computed
once, and the chunk that woke the mod is generated, so nothing about generation is
ever asked). The enum reorder and the surface short-circuit are the two measured
wins this section records; their rationale lives in the feature appendix. The steady-state number is a surface short-circuit, not a mirror win:
`on_chunk_generated` now asks `get_territory_for_chunk` FIRST and skips when a
territory already holds the chunk -- safe because the surface here only holds
territories this mod created (engine expression index is off) and a created
territory always carries the decided marker, so a non-nil answer can only mean
"already claimed, nothing to do". The marker stays for the states the surface
cannot hold: "unseen" and "empty" cones (nothing on the surface to show), and
territories REMOVED by documented API paths (`LuaTerritory::destroy`,
`delete_chunk` / `set_territory_for_chunks` / `clear_territory_for_chunks`
mutate chunk ownership, and the e2e itself deletes chunks), plus
on_surface_cleared resets. The conquest case needs NO marker, and it is
probe-verified (tests/eon-probe-territory-lifecycle, 2.0.77): a territory
whose last segmented unit is destroyed stays valid, all its chunks keep
answering `get_territory_for_chunk`, and `regenerate_segmented_units` still
works -- the engine never auto-destroys an unguarded territory; it just stops
showing it on maps. So a conquered cone is a still-existing, empty territory
that keeps answering the short-circuit, and demolishers never respawn in
vanilla. The worst single event, a big cone's first contact, fits inside one
16.66 ms tick; the split itself adds only the ~1.5-2 ms wedge work to the
pre-existing once-per-cone share+patrol cost.

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