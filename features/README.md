# Feature specs — how this repo writes requirements

One Markdown feature file per player-visible feature, under `features/`.
Gherkin-flavored but human-first: every acceptance criterion must be *testable*,
and every criterion carries the probe/command that proves it. The file is the
contract: if a probe contradicts a criterion, either fix the code or (with a
conscious decision) amend the criterion.

## File layout

```markdown
# Feature: <name>

Status: <shipped | in-progress | rejected>   Owner: <path(s)>
Config: <map-gen settings / sliders the feature assumes>

## Why
What the player gets and why it matters (2-4 sentences, no internals).

## Acceptance criteria
- [ ] AC-1 ... (behavior, testable, one line each)

## Verification
- command + expected PASS / measured numbers (seed, settings → metrics)

## Known residuals / accepted exceptions
- every imperfect case, with measured rarity. If it's not listed here it's a bug.

## Rejected alternatives
- what was tried and why it cannot work (one line of "why" each, so the
  knowledge survives and nobody re-attempts it).
```

## Rules

- **Measure, don't assert faith**: every criterion tied to a probe with a
  number (e.g. "unclaimed lava ≤ 10 per disc").
- **Residuals are part of the contract**: a documented residual with measured
  rarity is *not* a bug; anything else falling outside the criteria is.
- **Rejected alternatives get a WHY** — the map-gen wall findings cost real
  time; a one-line "impossible because ..." prevents rediscovery.
- Update the spec when the design changes (and when a playtest changes the
  acceptance — playtests are the source of truth for "good enough").
- **The working agreements are in AGENTS.md, "How we work"** — no behaviour-changing
  fallbacks, no swallowed errors, no `error()` on per-chunk paths, one Lua dialect,
  measure-don't-assume, and the two loops (hermetic gate vs live rcon) kept
  deliberately different. A feature file says *what*; that section says *how*.