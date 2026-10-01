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

## What this feature is not

- **Not a tile system.** Nothing here samples the rendered ground. Every question
  about a volcano is answered from the cone's own geometry and the engine's spot
  density; tiles appear only in probes, as validation.
- **Not a second prediction mechanism.** The mirror is the only source of cone
  identity. There is no "and also look at the terrain" path, and no component that
  exists only to patch a mirror limitation.
- **Not order-dependent.** A claim, a route and a guard are pure functions of the
  map, so they are identical on every machine, every load, and in either chunk
  generation order.

## Known limits

- At 600% volcanism two cone centres can be 55 tiles apart; a claim that thin
  cannot host a body, and is reported as such rather than fixed.
- A claim whose shape pinches (a crescent) gets a route that follows its outline in
  radius but not in angle, so a deeply split cone patrols a slightly smaller
  circle than its ground.
- The spot-deployment warp (~25 tiles) is not mirrored, so a claim can differ from
  the rendered cone edge by that much on a rim chunk. Measured cost: 0.8–3% of
  chunks change owner, always within one chunk of a cone's rim.
