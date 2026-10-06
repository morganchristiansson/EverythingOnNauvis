# Feature: Lua volcano territories, patrol paths and demolishers

Status: in-progress (runtime path shipped, playtest-verified)
Owner: `noise-mirror/`, `volcano-territory.lua`, `control.lua`, `tests/`
Config: the merged nauvis map; playtested at `vulcanus_volcanism` 200% and 600%
frequency, size 1, on seed 3526581861.

## Why

Every volcano gets a territory, a patrol path and a guard, all computed from the
cone's own geometry rather than from the tiles that happen to be revealed: a
volcano is claimed the moment any of its own ground is seen, with its whole disc,
and it stays claimed. A guard walks the volcano it belongs to, sized to that
volcano, and its whole body exists from the first frame. Nothing about a claim
depends on how much of the map the player has walked over or on the order the
chunks arrived in.

Replaces the expression-index path, which is **deleted** — not switched off
behind a setting. It claimed ground by voronoi cell id and field threshold and so
could not name a volcano at all; the engine's own index is now disabled
unconditionally (`-inf`, see `map-generation/enemies.lua`) and the mirror is the
only claimant. The record of what that path did, and why it was not enough, is in
`features/demolisher-territory.feature`.

## Vocabulary

- **cone** — one `spot_noise` candidate the engine placed, with a centre and an
  effective width. The unit of everything below.
- **claim** — the chunks a cone owns: its core disc, minus whatever a
  nearer-centred cone wins. Pure function of the map.
- **guard** — the demolisher: a segmented unit that patrols a cone's claim.
- **route** — the closed path the guard walks, a circle dented where a
  neighbouring cone crowds the claim.

## Acceptance criteria — claiming

- [ ] AC-1 **A cone exists exactly where the engine's spot density is positive.**
      Density is the `density_expression` of `eon_volcano_spots_at`, ported to
      `noise-mirror/density.lua`. Not a tile test: chunks arrive one at a time, so
      no per-chunk question can see a whole volcano.
      (probe: `python3 tests/density_parity.py` — 100% sign agreement against the
      shipped expression at the candidate centres the gate is asked at, over four
      seed/frequency configurations; worst relative error 3.8e-4.)
- [ ] AC-2 **The claim is the mirror's answer and nothing else.** A cone's claim is
      its core disc, whole. It is never reduced, trimmed or dropped because a
      guard would not fit, because the ground looks wrong, or because a
      neighbouring cone is close.
      (probe: `tests/runner` e2e — every decided cone has exactly one territory,
      and that territory is exactly `Field:cone_chunks` for the cone.)
- [ ] AC-3 **A cone is claimed the first time any of its own ground is revealed**,
      with its whole disc, generated or not: `create_territory` accepts
      ungenerated chunks and they join when they arrive.
      (probe: `tests/eon-probe-runtime` "late cone" case — a cone is claimed while
      the rest of its disc is still ungenerated, and the disc is complete and
      unchanged afterwards.)
- [ ] AC-4 **The claim does not move.** Two overlapping cones are split at the
      perpendicular bisector between their centres, so each claim contains its own
      centre. The split considers only cones that exist (AC-1), because a cone the
      engine does not place would hold ground no territory ever guards.
      (probe: mirror self test — overlapping cones yield disjoint chunk sets, and a
      chunk is owned by the cone that wins it, stably across repeated lookups and
      across two independently built fields.)
- [ ] AC-5 **The claim radius is one constant, 0.42 of a cone's width**, and does
      not vary with volcanism. Measured by tile truth on live maps: 100% volcanic out
      to 0.40, ~90% to 0.425, 36%/32% at 0.425–0.45, nothing beyond 0.475 — at 200%
      and at 600% alike.
      (probe: `tests/spot_mirror_parity.py` density sweep; regression: the
      self test asserts the fraction is the same at every frequency.)
- [ ] AC-6 **Sampling is at a chunk's centre, not its corner.** The engine samples a
      territory index at the top-left corner, which biases the claimed area half a
      chunk down-right; the runtime claims by geometry instead. Nothing in the
      shipped path reads a tile.
      (proof: `grep -n get_tile volcano-territory.lua noise-mirror/*.lua` — no hits
      outside comments.)

## Acceptance criteria — patrol and guard

- [ ] AC-7 **The route is a circle, dented where a neighbour crowds it.** A circle
      of 78% of the core radius, shortened in each direction to 78% of the way to
      a neighbouring cone's border. An untouched volcano gets a plain circle; a
      squashed one gets a circle with a dent on the crowded side.
      (probe: self test — every route point is a claimed chunk, and an unshared
      cone's route is the full circle.)
- [ ] AC-8 **The route's every point is a claimed chunk**, verified rather than
      assumed, and the route begins where the unit is already looking: with
      `body_nodes` the engine ignores `direction` and always starts the head facing
      north, so the route is started at the point whose outgoing leg heads north.
      (probe: self test; playtest: no U-turn on spawn.)
- [ ] AC-9 **The guard is the biggest demolisher the volcano can carry** — the size
      the cone's scale suggests, stepped down until the body's length fits the
      route with 15% margin, so the tail cannot wrap onto the head's end.
      (probe: self test; playtest: a 200% map gives a mix of sizes.)
- [ ] AC-10 **The whole body exists at spawn.** `body_nodes` is a body-*length*
      measurement, not a segment count: a big demolisher's body is 101.9 tiles, its
      prototype carries 41 cumulative `distance_from_head` entries, and the engine
      seats a segment per ~2.5 tiles of body, so the node list is one node per tile
      of body — 102 of them. Measured on a volcano:
      63 nodes at 1.00 tiles → 22 of 42 segments placed; 63 at 1.62 → 22 of 42;
      106 at 1.00 → 42 of 42. The documented `max_body_nodes` of 63 is advisory
      and the engine accepts the overage, so the count comes from the prototype and
      the overage is logged.
      (probe: live measurement of segments placed; self test: node count equals the
      prototype's body length.)
- [ ] AC-11 **The body lies along the route**, one node per tile of body, walked
      from the head backwards. Two samples may coincide where the shape pinches;
      that is stepped over, never a reason to stop laying the body.
- [ ] AC-12 **A volcano is claimed whether or not a guard fits.** The claim is
      mapgen's statement; the guard is ours. A volcano that cannot host a whole
      guard keeps its territory and reports the reason (log, `eon-unhostable`, and
      the e2e output). Nothing is dropped, nothing is retried, nothing is
      degraded to a smaller or head-only unit.

## Acceptance criteria — durability

- [ ] AC-13 **A volcano territory has priority and is never given up.** The audit
      re-asserts claims every 5 s: it rebuilds a territory the game destroyed with
      a deleted chunk, and refills holes — chunks of the cone's disc that no
      territory holds. It never takes a chunk back from another volcano.
      (probe: e2e priority case — a stolen slice is restored; self test — the audit
      does not fight a neighbour for shared ground.)
- [ ] AC-14 **A save is picked up after the fact.** On load, the generated chunks
      around each player are fed to the builder, so a world explored before this
      path existed gets its volcanoes on the next load.
      (probe: e2e second-load case.)
- [ ] AC-15 **Nothing on the per-chunk path raises.** `error()` there would take a
      long game down when a new chunk revealed one awkward cone. Every anomaly is
      logged and counted; the only `error()` is at load time, when `bit32` is
      missing, which cannot happen mid-game.
      (proof: no `error(` in `volcano-territory.lua` or the mirror.)

## Acceptance criteria — the cut

A cone big enough for two guards is claimed as TWO territories: one straight cut
through the cone's centre, a wedge of some fraction of the disc and the rest of it,
each piece with its own patrol loop and its own demolisher. The sizes come from the
existing ladder and the decision of whether to cut at all is `volcano-split.lua`'s.

- [ ] AC-16 **The claim is cut, not shrunk.** Both pieces are together exactly the
      cone's share, and they are DISJOINT, decided from one TOTAL test per chunk —
      every chunk takes a side, there is no third outcome. `create_territory` settles an
      overlap silently, by taking the chunk from whoever held it, so an overlap would
      not fail: it would make the two pieces depend on which was built first.
      (probe: `tests/builder_test.lua` — the pieces are disjoint and add back up to the
      whole claim, and the same cone built with the pieces delivered in OPPOSITE
      orders gives byte-identical territories.)
- [ ] AC-17 **The two guards are ONE size step apart** — small+medium, medium+big,
      big+behemoth — never small+big or medium+behemoth. A slice's size is its cone's
      scaled by the square root of the area it keeps, and the cut is the one that
      lands the pair on adjacent rungs.
      (probe: `tests/builder_test.lua` — `large.class - small.class == 1`;
      `tests/split_probe.lua` prints the census of pairs a seed produces, and the
      e2e probe fails a territory hosting both a small and a big demolisher.)
- [ ] AC-18 **A cone is only cut when BOTH pieces can carry a whole guard.** Each
      side's loop is the largest circle that fits that side's own ground; a side with
      no loop, a side that cannot carry even the smallest body, or a side the ladder
      steps DOWN from what its own area asked for (two guards that both stepped down
      to the same size is a split that bought two territories instead of one) all
      leave the cone whole.
      (probe: `tests/builder_test.lua` — one guard per slice, each the size its own
      ground asked for, read off the TERRITORY; the e2e fails any territory with no
      unit.)
- [ ] AC-19 **Each piece patrols its own ground, as a RING around the middle of its
      piece.** The outer arc is the volcano's own patrol radius over the wedge's
      directions -- so both halves trace the edge the whole volcano traces -- the two legs
      run in along the cuts, and the inner arc (that same ground curve, scaled in, so it
      runs around the lava roughly where the lava is) closes it. Every patrol point is a
      chunk of that slice's own territory: an off-claim point is walked back toward its
      own neighbours, and the cut is refused if it cannot be placed.
      (probe: `tests/builder_test.lua` -- every patrol point of both loops is on its own
      slice, and the arc reaches 90% of the volcano's own ground radius.)
- [ ] AC-27 **The inner arc walks around the LAVA.** Not around the middle of the claim:
      the lava expressions (map-generation/terrain.lua) resolve to a pool at 0.060 of a
      cone's width, a lava-hot ring out to 0.083 and nothing beyond 0.106, so the arc sits
      at 0.115 -- just past the lava -- and follows the pool's rough outline because the
      lava comes from the same spot field the outer arc does. Every point of a loop must
      also have a quarter-chunk of claim under it in all four directions: a point being
      inside the claim is not enough when the guard is a tile wide and the line between
      two of its points is not the claim.
      (probe: `tests/split_shape.lua` prints the innermost point of any loop against the
      lava radius and the room every point has inside its own claim; a cone that cannot
      hold both is left whole, with the reason in the log.)
- [ ] AC-25 **The two joins are right angles, and the guard is handed nothing it cannot
      follow.** Both arcs share ONE span, so the leg between them is radial and a circle's
      tangent is perpendicular to its radius: the corner is 90 degrees, which the guard
      makes with its own patrolling turning radius (a whole radian per tile, so a right
      angle costs it a tile and a half), and the arcs stop a chunk clear of the cuts, so
      it has open ground to do it in. Nothing is corner-cut: a fillet is a list of short
      edges each demanding a turn the body cannot make, which is worse than the corner it
      smooths. Giving the inner arc its own narrower span instead makes the leg run back
      across the arc and the join came out at 134-177 degrees -- a hairpin.
      (probe: `tests/builder_test.lua` -- no corner of either outline folds back on
      itself; `tests/split_shape.lua` prints the sharpest corner anywhere over three
      seeds x three frequencies, and the room every point has inside its own claim.)
- [ ] AC-26 **The two guards of one volcano never walk within a chunk of each other.**
      The arcs' ends are a chunk clear of the cut lines, which makes it true by
      construction, and the plan re-measures the closest approach between the two
      finished loops and refuses the cut if it is under a chunk -- the one way it can
      fail is a patrol point the walk moved, which is how 19-tile passes were found. A
      cone whose rim cannot spare a chunk is left whole: there is no room for two loops
      on it.
      (probe: `tests/builder_test.lua` -- the two loops never come within 32 tiles;
      `tests/split_shape.lua` prints the closest approach and how many of either loop's
      points stand on the other slice's ground, which is 0 in every configuration.)
- [ ] AC-24 **The two loops are RINGS around the same middle, and the claim is not cut
      back.** Each loop closes on an inner arc -- the volcano's own ground curve scaled
      in -- rather than on the wedge's apex, which is where the two used to meet:
      measured at 0 tiles of separation. The claim itself is the mirror's chunk list,
      whole and undivided; a caldera of unclaimed ground in the middle was tried and
      dropped, because it is a hole in a volcano and it made the claim something the e2e
      could only check by re-deriving the cut.
      (probe: `tests/builder_test.lua` -- the two pieces are the whole claim, every patrol
      point of both loops is on its own slice, and NEITHER LOOP WALKS THE SAME GROUND
      TWICE: the bearing from the cone's centre turns one way all the way round except
      once at each of the two legs, so a U-turn and backtrack shows up as four.
      `tests/split_shape.lua` prints the separation, the sharpest corner, the backtrack
      count, and how many of either loop's points stand on the other slice's ground.)
- [ ] AC-22 **The carved slice is between a quarter and a half of the circle** -- a 90
      to 180 degree wedge, which is what a guard can walk; below a quarter the outline's
      tip is a pin rather than a corner. The other side is the remainder: two pieces of
      a disc cut through its centre cannot both be halves without a third piece between
      them.
      (probe: `tests/builder_test.lua`; `tests/split_probe.lua` prints the census.)
- [ ] AC-23 **The outline's corners are ROUNDED.** A leg meets the arc at a right
      angle and a body cannot turn 90 degrees in one tile, so the outline is corner-cut
      twice; the sharpest corner anywhere over every split cone on three seeds is 10
      degrees.
      (probe: `tests/builder_test.lua` — no corner of either outline turns harder than
      20 degrees; `tests/demolisher_turn_test.lua` still measures the body's own turns
      against the prototype's `patrolling_turn_radius`.)
- [ ] AC-20 **A cut is decided slice by slice, by a chunk of that slice's own.**
      `create_territory` needs one GENERATED chunk per list, the chunk that woke the
      mod satisfies one of them at most, and the other piece waits for the next chunk
      event carrying one of ITS chunks. Nothing asks the engine about generation.
      (probe: `tests/builder_test.lua` — the second block: one territory exists and
      the cone is not settled, then the second piece is claimed when one of its own
      chunks arrives.)
- [ ] AC-21 **The cut is a pure function of the map.** The bearing is a hash of the
      cone's own id, so two neighbouring volcanoes do not all cut the same way, and
      the same volcano is cut the same way on every machine and every load, in either
      chunk generation order.
      (probe: `tests/builder_test.lua` and the e2e — regenerating the same chunks
      changes nothing.)

## What this feature is not

- **Not a tile system.** Nothing here samples the rendered ground. Every question
  about a volcano is answered from the cone's own geometry and the engine's spot
  density; tiles appear only in probes, as validation. That includes the cut: which
  side of a line a chunk falls on is arithmetic, not a question about the ground.
- **Not a second patrol shape.** Both routes come from ONE radius curve,
  `PatrolPath.ground_radius`: the whole claim's route is it over 360 degrees and a
  slice's is the same curve over its wedge, closed by the legs. Nothing about the ground
  is worked out twice.
- **Not a size rule of its own.** `volcano-split.lua` never names a demolisher. It
  asks the ladder which rung a slice's area is and refuses a cut that does not land an
  adjacent pair; TIER_LOW/TIER_HIGH are the measured numbers and this file does not
  move them.
- **Not more than two.** A third piece is a ~120 degree sector, whose inscribed
  circle is a third the radius of a quadrant's: the angles stop carrying a body.
- **Not a second prediction mechanism.** The mirror is the only source of cone
  identity. There is no "and also look at the terrain" path, and no component that
  exists only to patch a mirror limitation.
- **Not order-dependent.** A claim, a route and a guard are pure functions of the
  map, so they are identical on every machine, every load, and in either chunk
  generation order.

## Known limits

- The apex — the one chunk the two cut lines meet in — belongs to one side, decided by
  the same test as every other chunk. Excluding it from both would guarantee the two
  territories never touch at the meeting point, but it costs an unclaimed 32x32 hole in
  the middle of every cut volcano, and it would mean the claim is no longer exactly the
  mirror's chunk list (the e2e checks that, and could only check it by re-deriving the
  cut). Measured, neither side's loop comes within 23 tiles of it, so no guard is ever
  near the chunk either way.

- The pairs a cut can produce are bounded by the tier ladder's own thresholds. On the
  vanilla three rungs that is mostly small+medium, with medium+big only on cones
  within a few percent of the largest: a cone just above a boundary is already one
  rung from the one below, so halving it drops it two, and no cut gives an adjacent
  pair. `big+behemoth` needs a fourth rung whose top boundary is not 0.8 of the
  largest cone, which is a change to a measured number and not this feature's call.
  `lua tests/split_probe.lua <seed> <frequency>` prints the census for a map.
- The clamp costs the size ladder something: with the cut confined to 25-50%, the
  medium+big pair is only reachable on cones near the top of the scale (measured: 2 of 29
  splits at 200% volcanism on seed 12345, 8 of 41 at 100%, none at 600%), where before
  the clamp it was a little more common. The 6% sliver slices are gone, which was the
  point.
- The path BETWEEN two points is a straight line the engine paths along, so a guard can
  cut a corner of its own claim by a tile or two, and across a dent in the ground it can
  cross a few tiles of its own ground diagonally. Every POINT is inside the claim and
  the two loops never come within a chunk of each other, but the line between them is not
  itself a claim.
- Splitting costs some volcanoes. The legs and the inner arc both need a chunk and a
  half of clearance from the cut line to stand on their own ground, and where that
  clearance does not fit -- a cone a neighbour has dented short -- the cut is refused
  and the volcano is left whole with the reason in the log.
- At 600% volcanism two cone centres can be 55 tiles apart; a claim that thin
  cannot host a body, and is reported as such rather than fixed.
- A claim whose shape pinches (a crescent) gets a route that follows its outline in
  radius but not in angle, so a deeply split cone patrols a slightly smaller
  circle than its ground.
- The spot-deployment warp (~25 tiles) is not mirrored, so a claim can differ from
  the rendered cone edge by that much on a rim chunk. Measured cost: 0.8–3% of
  chunks change owner, always within one chunk of a cone's rim.

## Design appendix: measured history and rationale

Kept from AGENTS.md on 2026-10-06 (the file was >1000 lines and this narrative is
not needed in every session's context; the ACs above are the contract, this is the
"why" behind them, verbatim). The per-chunk cost findings at the end are HISTORY --
the current numbers live in AGENTS.md "What the split costs".

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

**A cut volcano: two territories, two guards** (`volcano-split.lua`). One straight
cut THROUGH THE CONE'S CENTRE — a wedge of some fraction of the disc and the rest of
it — and each piece becomes its own `create_territory` with its own loop and its own
demolisher. Each piece contains the apex, so both guards stand on the volcano's
middle rather than one patrolling a rim fragment. Three pieces is one too many: three
sectors of a circle are ~120 degrees each, whose inscribed circle is 0.16 of the disc
against 0.41 for a quadrant, and the angles stop carrying a body.

- **The sizes are the ladder's, never a number here.** A slice with fraction `f` of
  the area has a size fraction `sqrt(f)` times the cone's, so the cut is chosen by
  SCANNING the ladder and taking the middle of the cuts that read as an adjacent pair
  (`large_class == small_class + 1`), not by a threshold invented in this file. On the
  vanilla three rungs that means mostly small+medium, medium+big only near the top of
  the scale, and no big+behemoth: a cone just above a tier boundary is already one
  rung from the one below, so halving it drops it two. `lua tests/split_probe.lua
  <seed> <frequency>` is the census. Moving TIER_LOW/TIER_HIGH would change which
  pairs exist, and those are measured numbers.
- **A cut happens only if BOTH pieces carry a whole guard**, each at the rung its own
  area asks for. A side with no loop, or one the ladder has to step DOWN, and the cone
  stays whole with the reason in the log (`[eon] volcano <id>: one territory, <why>`).
  Two guards that both stepped down to the same size is a split that bought two
  territories instead of one.
- **A slice's loop is an ANNULAR SECTOR, and the claim is NOT cut back in the middle.**
  Two wedges closed at the apex put both loops' legs through the same point -- the two
  guards converge on the middle of the volcano and walk each other's ground (measured:
  the two loops' closest approach was 0 tiles) -- so each loop closes on an INNER ARC
  instead of on a tip and the two of them are two rings around the same middle. The
  loop is one shape in four parts: the OUTER ARC is the volcano's own patrol radius
  (`PatrolPath.ground_radius`, published for exactly this) over the wedge's directions,
  so both halves of a volcano trace the edge the whole volcano traces; the two LEGS run
  in along the cuts; and the INNER ARC closes it on the inside.
  - The middle was a CALDERA first -- a disc of the claim given to neither slice -- and
    that is gone. It cost a hole in the middle of every big volcano, and it made the
    claim no longer the mirror's chunk list, which the e2e could only check by
    re-deriving the cut. The playtest: "whether there's 1 territory or no territory
    claiming it is irrelevant." The loops are rings because of where they WALK.
  - The rim is `RIM_FRACTION` of the same wobble-derived ground curve, so it runs around
    the lava roughly where the lava is. It was the claim's own inner edge first, and
    that is the playtest's "the territory around it is hugging it too closely" and "some
    jitter in the inner path" together: the claim's edge is CHUNK-QUANTISED, so a rim that
    follows it steps 32 tiles between neighbouring directions and every step is a corner
    the body has to turn through.
  - **WHERE THE LAVA IS, and it is not where the rim used to be.** The chain
    (map-generation/terrain.lua: `eon_mountain_lava_spots` -> `eon_lava_mountains_range`
    and `eon_lava_hot_mountains_range` -> the two tile autoplaces) resolves, with
    `vulcanus_threshold(v,t) = (v - (1-t))/t` and the spot field `(3/pi)(1 - d/width)`,
    to a lava POOL at `d < 0.060 * width`, a lava-hot ring out to `0.083`, and nothing
    at all beyond `0.106` -- the whole lava complex is inside a TENTH of the cone's
    width, while the folds line the outer arc walks is at `0.350` and the claim at
    `0.436`. The rim was at `0.45` of the ground radius, i.e. `0.158 * width`, which is
    OUTSIDE the lava entirely; the playtest's "inner arc doesn't follow the lava" was
    exactly right. It is now `0.33` of the ground radius (`0.115 * width`), just past
    the lava, and because the lava is placed from the SAME spot field the outer arc uses,
    the wobble that roughens the volcano's outline roughens this ring too, for free.
  - That put the rim near the centre, and a chunk's clearance from the cut is a fixed
    number of TILES, so the wedge shrank with it: `MIN_FRACTION` is 0.17 (a 60 degree
    wedge) and the rim's own ends are the binding constraint -- `wedge_outline` does that
    arithmetic, and a cone whose rim cannot spare the clearance is left whole.
  - **Room to STAND, not room to stand on.** Every point of a loop needs a quarter-chunk
    of claim under it in all four directions, or the cut is refused. A point being inside
    the claim is not enough: a demolisher is a tile wide walking along a line, and the
    line between two of its points is not the claim. Measured: on cones a neighbour has
    trimmed, a rim point ended up one or two tiles from the edge with the body half over
    the border. This is also where the guards' turn TIMING lands: the demolisher starts
    turning BEFORE the path point, following a look-ahead along the path, so what matters
    is the room around a corner, not the angle at its vertex.
- **The walk happens BEFORE the repeats are dropped, not after.** A point walked back
  onto its own neighbour is a zero-length edge, and the body layout seeds its heading
  along the FIRST edge and refuses to lay a body that has none -- so one repeated point
  is a slice with a class and no demolisher on it, which is a territory that does not
  exist on the map (measured: a 41-chunk slice, caught by the e2e).
- **A point off its own claim is walked back to its neighbours, never to the nearest
  claim.** Rounding the outline bulges a point a tile or two past an arc, and a bulge is
  fixed by moving it toward the points either side of it, which are on the claim. What
  it was first: marching along the radius to the furthest claimed ground on that line,
  which lands the point on a LIP -- and the claim's lips are chunk-quantised, so that is
  the hugging and the jitter again, with a point whose neighbours are off the claim as
  well walking onto the middle of the volcano (measured: a loop point 0 tiles from the
  cone centre). A walk longer than PULL_MAX is not a bulge and refuses the cut; the OUTER
  arc is sampled at twice the whole claim's density, because a slice's arc crosses a
  neighbour's dent and the dent is a secant that changes tens of tiles over twenty
  degrees (measured: 24-33 tile bulges along the arc at the old density, every one a
  chord straddling a dent). The RIM is sampled at RIM_FRACTION of that (same tile
  spacing on a ring a third of the radius -- the dent argument scales with radius too,
  and same-count was an artifact of the shared loop; measured: no cut refused, corners
  and separation unchanged, 25 to 18 points a loop).
- **The wedge is clamped to 25-50% of the circle** (90-180 degrees) for the CARVED
  slice; the other side is the remainder, because two pieces of a disc cut through its
  centre cannot both be halves without a third piece between them.
- **ONE span for both arcs, and NO corner cutting.** The leg between the two arcs is
  then a RADIAL line, and a circle's tangent is perpendicular to its radius, so the two
  joins are RIGHT ANGLES -- which the guard can make, because its
  `patrolling_turn_radius` is a whole radian per tile, so a right angle costs it a tile
  and a half, and the arcs stop well short of the cuts, so it has open ground to do it
  in. That is the whole answer to "the demolisher will make the turn itself smoothly":
  hand it fewer, gentler points and room around the corner.
  - Giving the rim its OWN narrower span (which is what this did first) makes the leg
    run across and slightly back, and the join came out at 134-177 degrees: a hairpin no
    body can follow at all. Both arcs share `wedge` now.
  - Corner cutting (Chaikin, four points an edge on a fillet one or two tiles wide) is
    worse than the corner it smooths: a list of short edges each demanding a turn the
    guard cannot make. It is gone, and with it the rounding that used to need its own
    stand-off and its own walk-back.
- **The clearance from the cut lines is a chunk, and it is measured, not hoped for.**
  The arcs' ends are half the distance between the two loops, so two guards a chunk apart
  cannot bump ("it must not overlap or get too close to the neighbour's patrol path"), and
  the plan RE-MEASURES the closest approach between the two finished loops and refuses
  the cut if it is under a chunk -- which it can only be because a point the WALK moved
  (measured: 19 tiles, two rim points walked toward each other). The clearance is capped
  at a fraction of the rim's radius, and a cone whose rim cannot spare a chunk is left
  whole: there is no room for two loops there.
- **Three things the patrol path must be, and where each is enforced:** every POINT is
  on its own slice's claimed chunks (pull_inside walks an off-claim point back and
  refuses the cut if it cannot); the two loops never come within a chunk of each other
  (the plan refuses the cut); and no corner folds back on itself (a spike is two edges
  pointing the same way -- the bearing check, at two flips per loop). The path BETWEEN
  points can lead the guard off the claim, which is the engine's own pathing between
  sparse points and is accepted: some corner cutting is fine, a guard that walks a
  straight line between two of its own points is the thing being avoided.
- **A degrees conversion cost this file two gates.** `math.acos(0) * 2` is pi, not 180,
  and it was written as a degrees factor in both the shape tool and the builder test: a
  right angle was reported as 4.9 and a spike as 9.9, and "no corner turns harder than 20
  degrees" was satisfied by anything at all. Both now use `180 / math.pi`.
- **Two traps this shape has, both measured:** the LARGE slice must be built on the
  OPPOSITE axis with half-angle `pi - h` (built on the small side's axis it got a 126
  degree arc, a 253-tile loop and no demolisher at all), and a walked point can land on
  its own neighbour, which is a zero-length edge -- the body layout seeds its heading
  along the first edge and refuses to lay a body when it has no length. Drop the repeats
  AFTER the walk.
- **A slice needs a generated chunk of its OWN**, which the chunk that woke the mod
  satisfies at most once: so the cone is decided slice by slice, each marker a separate
  entry, and the piece that has nothing revealed is asked again by the next event
  carrying one of its chunks. Which side a chunk is on is arithmetic, so no
  `is_chunk_generated` came back — and an already-claimed slice's marker must NOT be
  reset while waiting for its partner (`local settled = ... and previous[index] or
  ...` yields `false`, not `nil`, for index 2, which settles the whole cone early).
- The pieces are DISJOINT because the cut test is TOTAL -- every chunk takes one side
  or the other, no third outcome -- and their bearing is a hash of the cone's id, so
  the cut is a pure function of the map: same on every load, either generation order.
  That has to be proved rather than assumed, because the engine settles an overlap
  SILENTLY (it takes the chunk from whoever held it), which would make the pieces
  depend on which was built first with nothing in the log. `tests/builder_test.lua`'s
  "the cut is the same whichever slice is built first" builds the same cone twice with
  the pieces delivered in opposite orders and compares chunk by chunk. The apex chunk
  (the one the two cut lines meet in) is NOT excluded: it goes to one side by the same
  test, both loops stay 23+ tiles from it (measured), and dropping it would put an
  unclaimed hole in the middle of a volcano -- and would force the e2e to compare the
  surface against our own plan instead of the mirror's chunk list.

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

