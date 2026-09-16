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
  field (eon_vulcanus_terrain_at16) to recenter — after the shift the per-blob deltas are
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
  mask (eon_vulcanus_core_at16) so ore basically cannot render outside demolisher
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

- Fish: vanilla prototype `fish.autoplace.probability_expression = 0.01` (a literal number) and
  fish only materialize on liquid tiles; per-planet enablement is
  `planet.map_gen_settings.autoplace_settings.entity.settings["fish"] = {}`.
- `eon_mask_nauvis_territory(e)` is exactly
  `eon_mask_off_aquilo_territory(eon_mask_off_gleba_territory(eon_mask_off_vulcano_terrain(e)))`;
  the `off_*` masks yield `-inf` inside their territory. It is the "nauvis only" mask — used to
  keep fish/dead trees out of non-Nauvis liquids (lava, ammonia ocean, Gleba wetlands), while
  leaving the inner probability expression (usually a literal, gets string-coerced) unchanged.

## Bash tool hygiene

- Do **not** nest heredocs inside a `bash` tool call that is itself wrapped in a heredoc — the
  outer one terminates at the first inner terminator, silently truncating the script. Write
  multi-file test scripts with the `write` tool instead.