# Feature: no dead noise expressions in the data stage

Status: shipped (standing gate) Owner: `map-generation/*.lua`, `tests/dead_expressions.py`
Config: none — this is about the data stage itself, not a map.

## Why

Every noise expression the data stage defines is a promise: the map generator will
evaluate it wherever a prototype points at it, and `--dump-data` publishes it as
part of the mod's public surface, which is what other tools (the noise sandbox, the
Rust oracle harness, this repo's own probes) read. An expression nothing can reach
is dead weight in both senses: it is evaluated if anything ever points at it again,
and it is in every runtime dump, so downstream tools reason about a graph larger
than the mod actually uses.

This is its own requirement because it has its own failure mode. A change that
replaces a prototype's expression orphans the old one, and nothing warns: the mod
still loads, the map still generates, and the dead field simply sits there.

## Acceptance criteria

- [ ] AC-1 **Nothing the data stage defines is unreachable from a prototype.**
      Reachability is computed over the resolved graph in the loaded
      `--dump-data` output: a name is live if some reachable expression or
      function mentions it, or if a prototype names it directly. Chain through
      expressions (a definition referenced only by another definition is live only
      if that one is).
      (gate: `python3 tests/dead_expressions.py` — "0 unreachable", run inside
      `run_spot_mirror_tests.py`; it exits non-zero on any unreachable name.)
- [ ] AC-2 **A deletion is proven by a dump, not by a scan.** `--dump-data` with
      the mod loaded is the authority: every reference resolves at load, so a
      surviving reference is a load-time error, not a silent survivor. The scan
      decides *what* to delete; the dump decides whether the deletion was safe.
      (proof: the suite's `run_tests.py` dump-data test plus both e2e runs.)
- [ ] AC-3 **Vanilla expressions this mod wraps are NOT dead.** EoN wraps the
      vanilla resource probability expressions rather than replacing them
      (`eon_mask_off_aquilo_territory(eon_mask_off_ammonia_ocean(" .. current ..
      "))` in `map-generation/resources-updates.lua`), so every
      `default-<ore>-patches` expression is live inside a resource autoplace.
      (proof: deleting them fails the load with `Unknown variable:
      default-coal-patches`; `map-generation/enemies.lua` records this so the next
      person does not try it.)

## Known residuals

None. The data stage currently defines nothing unreachable — including the
pre-existing weight this feature was written for, which turned out not to exist:
an earlier report of ~14 orphaned expressions was an artefact of the tool's own
tokeniser (below), not of the mod.

## Rejected alternatives

- **Delete what `grep` cannot find.** Not viable and actively harmful: vanilla's
  `default-<ore>-patches` look unreferenced by grep and are live, and deleting them
  is a load error.
- **Trust a reachability scan as the authority.** The scan is for *choosing* what to
  delete; the dump is for *knowing* it was safe. An earlier version of the tool
  tokenised with `[A-Za-z0-9_]`, so any name with a hyphen — read from inside
  `var('default-coal-patches')` — was invisible to it, and it reported live vanilla
  expressions as dead. The engine caught it; the lesson is in the tool's docstring.
- **Keep orphaned expressions "in case something points at them later".** That is the
  failure mode this feature exists to prevent: a name nothing can reach is a name
  that will quietly come back to life the moment an expression is edited, with no
  test noticing. If an expression is worth keeping, a prototype should point at it.
