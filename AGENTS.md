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