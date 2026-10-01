# Noise sandbox

> **The Ruby implementation is gone.** It was the first evaluator for Factorio
> 2.0 noise-expression graphs (importing the `--dump-data` JSON rather than
> running Lua) and it did its job: it is what established that the recovered
> noise behaviour matched the committed seed-12345 territory fixture exactly.
> Nothing referenced it any more, it was not part of any gate, and keeping it
> invited reading an evaluator that no test ran. Its two Lua prototypes went with
> it: one was a generic mirror of the spot-selection phase that the shipped
> design deliberately does not port (see `AGENTS.md`, "The runtime spot mirror"),
> and it loaded a `territory-controller` module that was never written in any
> commit.

**The active tooling is [`python/`](python/README.md)** — Python over the Rust
`fmw-oracle` binary from the pinned FactorioMapWebUI fork in `vendor/` (which is
ignored, not vendored). Read that README for the current split of ownership:
the Rust fork owns Factorio's numerical primitives, Python owns the EoN graph,
candidate orchestration and probe reports.

```text
fixtures/data-raw-noise-2.0.77.json   the committed --dump-data catalog (python reads it)
python/                               the active tooling
vendor/FactorioMapWebUI/              the oracle, ignored, see "Calibration oracle"
```

## Fixtures are evidence, not a gate

The committed fixtures under `fixtures/` are the record of what the map
generated; four of the Python tools default to `data-raw-noise-2.0.77.json`. They
are evidence, not a release gate. Existing Factorio probes under `tests/`
remain authoritative for anything that places map entities.

When two real grouping reports exist, `python/compare_territory_reports.py`
compares their per-chunk shapes exactly, without generating an image. Reports
must come from the same probe mod and settings; do not mix them with the older
claim fixture, which has a different membership representation.

## What a simulation can and cannot settle

The sandbox can shortlist an expression before a Factorio run, and the
per-chunk territory geometry is exact. Two limits came from the Ruby era and
still apply to every offline simulation here:

- It **cannot** establish Factorio's runtime territory *grouping*. Whether
  same-id chunks merge into one territory is not observable headless.
- Its territory **minimum-size** result is a topology proxy, not a claim about
  the engine's final grouping.

Anything that changes placement still has to pass the probes under `tests/`
(`probe_split_grouping.py`, `probe_runtime_territory.py`), and grouping needs a
real-game check.

## References

The Factorio API pages used for the expression language and function meanings:

- <https://lua-api.factorio.com/latest/auxiliary/noise-expressions.html>
- <https://lua-api.factorio.com/latest/types/NoiseExpression.html>
- <https://www.factorio.com/blog/post/fff-207>

## Calibration oracle

The [FactorioMapWebUI noise implementation](https://github.com/FactoryGameFan/FactorioMapWebUI)
is an important external reference. Its `fmw-noise` crate documents and tests
recovered implementations of Factorio's `taus88`, basis noise, multioctave
noise, Voronoi noise, spot candidates, and expression evaluator, with oracle
fixtures. It is the right reference for recovered noise behavior and
calibration. The checkout is under `vendor/` and is intentionally ignored.

That project is AGPL-3.0 licensed, so its source and recovered tables must not
be copied into this repository without a deliberate license decision. For now
the sandbox treats it as an external development oracle/reference and keeps
its own implementation and fixtures separate. Any adopted algorithm must still
be checked against Factorio 2.0.77 probes here; the upstream implementation
currently documents validation primarily against Factorio 2.1.x.
