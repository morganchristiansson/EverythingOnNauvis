# Feature: Demolisher territory layout on volcanoes

Status: shipped (0.1.10) Owner: `map-generation/enemies.lua`, `map-generation/terrain.lua`
Config: the merged nauvis map; playtested at `vulcanus_volcanism` 200%/600% freq, size 1.

## Why

Every volcano is guarded by demolishers whose territory matches the volcano:
medium+ cones get two territory halves (west/east) instead of one, small cones
stay whole, overlapping ("merged") volcanoes no longer collapse into a single
territory, and the demolisher size scales with the volcano's own size (plus a
per-territory nudge so a split cone's two demolishers are adjacent classes).
No volcano chunk is ever left unguarded for free mining.

## Acceptance criteria

- [ ] AC-1 **Split anchors on the volcano, not a world grid.** A medium+ cone's
      two territories are cut at its own peak column; the cut never misplaces
      because of spot-deployment jitter. (probe: cut within ~1 column of the
      lava centroid on every cone; lossless partition, overlap 0.)
- [ ] AC-2 **Small cones stay whole.** Cones with `eon_volcano_size_dist < 0.55`
      get a single territory (their halves would be too small to patrol).
- [ ] AC-3 **Merged/overlapping volcanoes are un-fused.** Two cones sharing a
      voronoi cell no longer share one territory id: each half gets its own, so
      a fused pair becomes two territories (west halves + east halves) instead
      of one. A big cone spanning two cells keeps its piece-count there
      (accepted residual, see below).
- [ ] AC-4 **No unguarded lava.** Unguarded lava chunks stay rare: `≤ 10` per
      ~13k-chunk probe disc (measured 1 at 200% volcanism, 4 at 600%). Lava
      is not mineable itself, but the chunks sit in resource-bearing regions.
- [ ] AC-5 **No leaks.** No claimed chunk is off volcano ground. (probe: 0.)
- [ ] AC-6 **Sizes scale with the volcano.** Class by `eon_volcano_size_dist`:
      < 0.55 → small, 0.55–0.8 → medium, ≥ 0.8 → big. No distance ramp: a
      cone's class never depends on map radius.
- [ ] AC-7 **Adjacent classes only.** Each territory rolls a nudge (0/1) on its
      class; the two halves of a split cone are never small+big — except a
      cone straddling the 0.55 tier contour (rare, accepted).
- [ ] AC-8 **Small-only cones cap at medium.** Ground with a strong small-spot
      system and no big field never hosts a big demolisher.

## Verification

Dedicated territory E2E (hard guards: leaks, unguarded-lava quota; report:
splits, islands, sizes):

```
python3 tests/probe_split_grouping.py 620294650 tests/map-gen-settings-user.json
python3 tests/probe_split_grouping.py 12345 tests/map-gen-settings-high-volcanism.json
```

Measured (2026): 200% volcanism, seed 620294650 → 79 territories, unguarded
lava 1, leaks 0, cramped <4ch 4. 600% volcanism, seed 12345 → 145 territories,
unguarded lava 4, leaks 0, cramped 3. Both PASS the quota.

(Mechanism evidence for the gradient cut — lossless east/west partition, cut
within ~1 column of the lava centroid — was gathered with session probes that
are not shipped; the numbers above reproduce the layout through the E2E.)

## Known residuals / accepted exceptions

- **Rim-quantization holes**: a chunk whose top-left corner sample misses the
  (16px-recentered) mask can carry lava while unclaimed. Isolated (≤ 4 per
  ~13k chunks at 600%, 1 at 200%), surrounded by claimed chunks on all sides.
  Root cause: the territory index is one sample per 32×32 chunk; the mask is
  built on the 16px-shifted field to recenter the corner sampling, and the
  shift trades NW-rim for SE-rim coverage.
- **Cell-straddle nibbles**: a big cone whose corner pokes into the
  neighbouring voronoi cell keeps that corner as its own small territory (~1–2
  per map, guarded-but-cramped). The alternative is an unguarded gap (free
  mining) — rejected. Same for giant cones: 2 cells × 2 halves = up to 4
  territories; the diamond cell seam can read as a diagonal/horizontal cut.
- **Big-system cones near the exemption**: a big-system cone (size_mult 1.25)
  at size_dist 0.45–0.55 renders medium-large yet stays whole (exempt). Halves
  would be safe (~13/13); lowering the exemption to 0.45 starts splitting
  small-system cones of ~8–15 claimed chunks into cramped 4–7-chunk halves.
  Accepted: the cone keeps its single (small/medium) demolisher.
- **Cramped territories (< 4 chunks) with demolishers**: the flip side of
  "no unguarded gaps" — tiny nibbles survive as guarded territories. Probed
  count is 3–4 per map; tail-chasing is limited by the demolisher being small
  on genuinely tiny cones.

## Rejected alternatives

- **Pie / wedge splits**: radial boundaries around the peak shred into
  1-chunk slivers near the center under the 32px corner sampling; min-size
  drops them → unguarded seams.
- **Lattice-anchored left/right** (cuts at world-grid cells): volcano spots
  deploy off any recoverable coarse lattice (jitter measured 5–22 columns off
  every candidate grid); a fixed lattice cut lands ±23 columns from the real
  middle → most cones unsplit or with a die-sized half.
- **Lua runtime territory fixup** (create/merge/delete territories via
  LuaTerritory after mapgen): would need to run against a playable surface
  (not `--dump-data`), touch save-state, and fight the engine's own territory
  bookkeeping; the probe shows exceptions are already rare without it.
- **Higher `minimum_territory_size`** (3 → 5): turns nibbles and tiny cones
  into unguarded gaps — free mining of lava/tungsten/acid geysers. Explicitly
  rejected by playtest ("they will mock me").
- **Named noise-function position args** to sample "the field at the volcano
  center": the engine ignores x/y args on named functions (probe-verified);
  only inline arithmetic offsets (`x ± 32`) move the evaluation.