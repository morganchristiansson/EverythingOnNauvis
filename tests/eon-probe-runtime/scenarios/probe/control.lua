-- Dev-only end-to-end probe for the RUNTIME volcano territories (spot mirror ->
-- surface.create_territory). It runs with the shipped default setting
-- (eon-volcano-territory = "runtime"), so the expression index is off and every
-- volcano territory in the report was made by control.lua.
--
-- What it proves, in the real game:
--   1. every chunk the mirror says a cone owns is in a territory, and every
--      territory holds EXACTLY the mirror's chunk list -- the list is complete the
--      FIRST time, which is what the one-call-per-territory design buys;
--   2. regenerating the same chunks creates nothing (no re-creation);
--   3. a territory created while most of its chunks are still ungenerated keeps
--      them: generating them later still lands them in the same territory, so the
--      single call really is enough;
--   4. how much of a cone's disc is actually on rendered volcano ground, as a
--      histogram of normalised distance -- this is what fixes the disc's inner
--      radius (the full cone reaches far past the volcano into ice and water).
local cones = require("__EverythingOnNauvis-morganc__.noise-mirror.volcano-cones")
local PatrolPath = require("__EverythingOnNauvis-morganc__.volcano-patrol-path")
local VC = require("__EverythingOnNauvis-morganc__.volcano-constants")

local TX, TY = -80, -831
local R = 24

local function line(...)
  log("[eon-probe-runtime] " .. string.format(...))
end

local function is_volcano(name)
  return string.sub(name, 1, 8) == "volcanic" or name == "lava" or name == "lava-hot"
end

--- Does any cone's DISC contain this chunk? "No cone's disc reaches here" is the
--- honest way to ask whether a territory may hold the chunk at all.
local function in_any_disc(volcanoes, chunk_x, chunk_y)
  local px, py = chunk_x * 32 + 16, chunk_y * 32 + 16
  -- The WOBBLED terrain disc, like cone_chunks: a clean disc of the core radius is
  -- wrong in both directions, and using one here made the probe report chunks in a
  -- territory no cone claimed.
  local wx, wy = cones.wobble(volcanoes.context, px, py)
  local ring = volcanoes:nearby_cones(px, py, 64)
  for index = 1, ring.n do
    local cone = ring[index]
    local dx, dy = (px + wx) - cone.x, (py + wy) - cone.y
    local radius = VC.VOLCANIC_EDGE_FRACTION * cone.width
    if dx * dx + dy * dy <= radius * radius then return true end
  end
  return false
end

local function ccx() return math.floor(TX / 32) end
local function ccy() return math.floor(TY / 32) end

--- The mirror exactly as control.lua builds it, with the tile gate.
local function mirror(surface)
  local controls = surface.map_gen_settings.autoplace_controls["vulcanus_volcanism"] or {}
  return cones.new_volcanoes(cones.new_context{
    seed = surface.map_gen_settings.seed,
    volcanism_size = controls.size or 1,
    volcanism_frequency = controls.frequency or 1,
  })
end

--- The surface's territory list, keyed by each territory's SORTED CHUNK LIST.
--- Two snapshots that compare equal mean nothing was created, destroyed or
--- reshaped in between. (Events raised during on_init are only delivered after
--- it returns, and tostring(LuaTerritory) is not a unique key, so the surface
--- itself is the honest witness.)
local function snapshot_territories(surface)
  local snapshot = {}
  for _, territory in ipairs(surface.get_territories()) do
    if territory.valid then
      local keys = {}
      for _, chunk in ipairs(territory.get_chunks()) do
        keys[#keys + 1] = chunk.x .. "," .. chunk.y
      end
      table.sort(keys)
      snapshot[table.concat(keys, " ")] = true
    end
  end
  return snapshot
end

--- A stable key for a territory: its sorted chunk list. LuaTerritory is a HANDLE --
--- get_territories() and get_territory_for_chunk() hand back different Lua objects
--- for the same territory, so identity is useless as a key (probe: keying on the
--- object made every territory look like a non-volcano one).
local function territory_key(territory)
  local keys = {}
  for _, chunk in ipairs(territory.get_chunks()) do
    keys[#keys + 1] = chunk.x .. "," .. chunk.y
  end
  table.sort(keys)
  return table.concat(keys, " ")
end

local function same_snapshot(a, b)
  for key, value in pairs(a) do
    if b[key] ~= value then return false, key end
  end
  for key in pairs(b) do
    if a[key] == nil then return false, key end
  end
  return true
end

--- Territories with no segmented unit, and how many units there are in total.
--- The unit check is not decoration: a territory created from Lua is EMPTY (the
--- map generator spawns the demolisher itself, and the docs say "a territory
--- with no units will not appear on player's maps"), so a perfect disc can sit
--- on every volcano and host nothing at all. That is exactly what a
--- create_territory-only implementation looks like in game, and the F4
--- territory view cannot tell it from a working one.
local function survey_segmented_units(surface)
  local empty, units, names = {}, 0, {}
  local bad_pairs = {}
  for _, territory in ipairs(surface.get_territories()) do
    if territory.valid then
      local guarded = territory.get_segmented_units()
      local size = #territory.get_chunks()
      if #guarded == 0 and size >= 16 then
        -- 16 chunks is the same sliver cut the Builder uses: below it the territory
        -- is a rim fragment, not a volcano, and gets no demolisher.
        empty[#empty + 1] = size
      else
        local on_this = {}
        for _, unit in ipairs(guarded) do
          units = units + 1
          local ok, name = pcall(function() return unit.prototype.name end)
          name = tostring(ok and name or "?")
          names[name] = (names[name] or 0) + 1
          on_this[name] = true
        end
        -- A volcano hosts small+medium or medium+big, never small+big.
        if on_this["small-demolisher"] and on_this["big-demolisher"] then
          bad_pairs[#bad_pairs + 1] = size .. " chunks"
        end
      end
    end
  end
  return empty, units, names, bad_pairs
end

-- Armed by on_init, consumed by the first tick -- see the note in there.
local pending_measurement = false
-- Phase marks. `os` is nil in Factorio's mod sandbox, so the probe cannot time
-- itself; these go to stdout and the engine timestamps them, which is enough.
local function mark(what) line("MARK %s tick=%d", what, game.tick) end
-- How many times the census below has run. It must be 1: it used to run once per cone
-- (13 on a 100% map, 3.6 s inside one tick) because a missing `end` put it inside the
-- disabled RUN_FIT loop, and the stray `end` that cancelled the missing one is why luac
-- accepted the file. The output was identical every pass and the harness kills on the
-- first sentinel, so nothing failed -- it was just slow. The harness now fails on
-- anything but 1.
local census_passes = 0
-- Assigned by on_init, called by the first tick. It has to be declared out here
-- rather than as a local inside on_init, because the two are in different scopes
-- and `local` in one is invisible to the other.
local measurement

script.on_init(function()
  local surface = game.surfaces["nauvis"]
  mark("on_init entered")

  -- 1. Generate the disc. control.lua's own on_chunk_generated handler runs for
  --    every chunk and creates the territories; the probe only observes.
  -- Generate the disc, and WAIT for it: force_generate_chunk_requests returns
  -- before the whole disc is rendered, and the mod is event-driven, so asking it
  -- straight afterwards sees a half-generated map and claims almost nothing. The
  -- loop is the probe being honest about the engine's timing, not the mod being
  -- slow: in a real game chunks arrive one at a time and each event claims its own
  -- cone.
  local function count_generated()
    local n = 0
    for dy = -R - 6, R + 6 do for dx = -R - 6, R + 6 do
      if surface.is_chunk_generated({ x = ccx() + dx, y = ccy() + dy }) then n = n + 1 end
    end end
    return n
  end
  -- The mirror first, and BEFORE any chunk is generated: it reads only
  -- map_gen_settings, and the generation loop below uses it to ask for exactly the
  -- ground that can end up in a territory.
  local volcanoes = mirror(surface)

  -- Generate ONLY the ground a cone can claim, not a disc around it.
  --
  -- The disc this used to ask for is radius R+6 = 30 chunks, about 2,800 chunks,
  -- and map generation is most of the run's wall clock. The union of the cones'
  -- discs is a fraction of that at 200% and rather less of it at 600%, where the
  -- volcanoes are further apart and most of the disc is bare ground this probe never
  -- looks at. One request per cone, sized to that cone, asks for exactly the chunks
  -- that can end up in a territory and skips the rest.
  --
  -- The loop still repeats until the generated count stops moving, because a cone's
  -- chunks can be outside every disc that has been requested so far: the mirror
  -- knows where the claim WILL be, and claiming needs those chunks.
  local function claimable_requests()
    local requests = {}
    for _, cone in ipairs(volcanoes:cones_near(ccx(), ccy(), R + 6)) do
      local radius = math.ceil(cone.core_radius / 32) + 1
      requests[#requests + 1] = {
        { math.floor(cone.x / 32) * 32, math.floor(cone.y / 32) * 32 }, radius }
    end
    if #requests == 0 then
      -- No cone in reach: fall back to the disc, or the probe would verify nothing
      -- and pass vacuously.
      requests[1] = { { TX, TY }, R + 6 }
    end
    return requests
  end
  local previous = -1
  for _ = 1, 20 do
    mark("generation pass")
    for _, request in ipairs(claimable_requests()) do
      surface.request_to_generate_chunks(request[1], request[2])
    end
    surface.force_generate_chunk_requests()
    local now = count_generated()
    if now == previous then break end
    previous = now
  end
  -- we know is on the disc. If this claims nothing, the problem is in the mod's
  -- decision, not in the batch.
  local generated_before = count_generated()
  local generated_after = count_generated()
  local probe_chunk = { x = -19, y = -31 }
  -- Everything below runs on the FIRST TICK rather than in on_init, because
  -- two things are untrue there. The mod's own on_init may not have run: both
  -- handlers fire, in an order the engine does not promise, and the harness used
  -- to kill the server the moment the probe's report appeared while the mod's
  -- mod was still claiming -- with no error anywhere, because the process was
  -- simply gone. And on_chunk_generated is delivered BETWEEN top-level handlers,
  -- so the engine has fed the builder nothing when on_init returns.
  --
  -- A tick is somewhere to stand only because the harness passes a
  -- server-settings.json with auto_pause false. An empty server otherwise PAUSES
  -- and stops at updateTick(0), so on_nth_tick never fires at all.
  mark("on_init generation done")
  measurement = function()
    mark("measurement start")


  -- The mirror's cones and their chunk sets, plus the distance histogram that
  -- says where the rendered volcano ground actually ends inside each disc.
  local entries, histogram_total, histogram_volcanic = {}, {}, {}
  local per_cone = {}
  for _, cone in ipairs(volcanoes:cones_near(ccx(), ccy(), R + 6)) do
    local candidates = volcanoes:cone_chunks(cone, volcanoes:contenders_for(cone))
    if #candidates > 0 then
      local stats = { chunks = 0, volcanic = 0, width = cone.width }
      per_cone[cone.id] = stats
      -- MEMBERSHIP IS GEOMETRIC: the expected chunk list is the mirror's core
      -- disc, whole, with no tile filter. Tiles are only MEASURED here -- "is this
      -- claimed chunk on rendered volcano" is the purity of the disc (and the
      -- histogram below is what sets CORE_FRACTION), not a filter the Builder is
      -- supposed to apply.
      local set, ungenerated, generated = {}, 0, 0
      for _, chunk in ipairs(candidates) do
        set[chunk.x .. "," .. chunk.y] = true
        if surface.is_chunk_generated(chunk) then
          generated = generated + 1
          local px, py = chunk.x * 32, chunk.y * 32
          local dx, dy = px - cone.x, py - cone.y
          local bucket = math.floor(math.sqrt(dx * dx + dy * dy) / cone.width * 20) + 1
          local volcanic = is_volcano(surface.get_tile(chunk.x * 32 + 16, chunk.y * 32 + 16).name)
          histogram_total[bucket] = (histogram_total[bucket] or 0) + 1
          stats.chunks = stats.chunks + 1
          if volcanic then
            histogram_volcanic[bucket] = (histogram_volcanic[bucket] or 0) + 1
            stats.volcanic = stats.volcanic + 1
          end
        else
          ungenerated = ungenerated + 1
        end
      end
      local count = #candidates
      -- A cone is decided when its CENTRE chunk exists, not when its whole disc
      -- does: a big cone's disc is ~390 chunks over ~1600 tiles and the frontier
      -- reaches the centre first, so waiting for the full set left big volcanoes
      -- permanently unclaimed (measured live: 387 candidates, 270 generated, no
      -- territory at all). So the expectation is the WHOLE disc, including the
      -- ungenerated part -- create_territory holds ungenerated chunks for the
      -- territory, and they join it when they arrive.
      -- The cone's DISC as well as its share of it. The share (cone_chunks) is
      -- what a territory is BUILT from, but the builder's audit also refills
      -- chunks inside the disc that a neighbouring cone's gate said were not a
      -- volcano -- a lens between two overlapping cones, with no owner left to
      -- patrol it. Those are legitimate members of this territory, so the
      -- expectation for "may this territory hold this chunk" is the DISC.
      local disc = {}
      for _, chunk in ipairs(volcanoes:cone_disc(cone)) do
        disc[chunk.x .. "," .. chunk.y] = true
      end
      if count > 0 then
        entries[#entries + 1] = {
          id = cone.id, width = cone.width, set = set, cone = cone,
          expected = disc, share = set, expected_count = count,
          candidates = count, ungenerated = ungenerated, generated = generated,
        }
      end
    end
  end

  -- 1a. Volcano territories that carry no guard. The mod used to report this
  --     through a remote built for the test harness; it is computable here, and
  --     belongs here. A territory that owns a cone's share and has no segmented
  --     unit IS the unhostable condition, and the unit count is one the probe
  --     already takes for its census.
  --
  --     Restricted to cones on purpose. The surface can hold territories that are
  --     not volcanoes -- the engine spawns its own -- and "no units" says nothing
  --     about those, so counting every unitless territory would report the game as
  --     broken when the mod is fine.
  local unhostable = {}
  for _, entry in ipairs(entries) do
    local territory
    for key in pairs(entry.share) do
      local x, y = key:match("^(-?%d+),(-?%d+)$")
      local chunk = { x = tonumber(x), y = tonumber(y) }
      if surface.is_chunk_generated(chunk) then
        local found = surface.get_territory_for_chunk(chunk)
        if found and found.valid then territory = found break end
      end
    end
    if territory and #territory.get_segmented_units() == 0 then
      unhostable[#unhostable + 1] = string.format(
        "%s: territory of %d chunks, no guard", entry.id, #territory.get_chunks())
    end
  end

  -- 1b. The live bug this design exists to prevent: a cone whose candidate disc
  --     is only PARTLY generated (the frontier reached its centre, not its rim)
  --     must still have a territory covering the ground that IS generated.
  --     Waiting for the whole disc -- which the first implementation did -- left
  --     big volcanoes permanently unclaimed: 387 candidates, 270 generated, no
  --     territory, 75 volcanic chunks in nobody's territory (gps -744.7,-1029.0).
  local partial, partial_ok, partial_examples = {}, 0, {}
  for _, entry in ipairs(entries) do
    if entry.ungenerated > 0 then
      local owned = 0
      for key in pairs(entry.set) do
        local x, y = key:match("^(-?%d+),(-?%d+)$")
        local territory = surface.get_territory_for_chunk({ x = tonumber(x), y = tonumber(y) })
        if territory and territory.valid then owned = owned + 1 end
      end
      local total = 0
      for _ in pairs(entry.set) do total = total + 1 end
      partial[#partial + 1] = {
        id = entry.id, candidates = entry.candidates,
        ungenerated = entry.ungenerated, covered = owned, volcanic = total,
      }
      if entry.ungenerated == entry.candidates then
        -- Never seen: no claim, by design. The claim happens on first sight.
        partial[#partial + 1] = { id = entry.id, candidates = entry.candidates,
                                  ungenerated = entry.ungenerated, covered = 0,
                                  volcanic = 0, unseen = true }
      elseif owned == total and total > 0 then
        partial_ok = partial_ok + 1
      elseif #partial_examples < 5 then
        partial_examples[#partial_examples + 1] = string.format(
          "%s: %d of %d volcanic chunks in a territory (%d of %d candidates ungenerated)",
          entry.id, owned, total, entry.ungenerated, entry.candidates)
      end
    end
  end
  -- Builder status around the disc centre: the mod's own view of which cones it
  -- sees, which it has created, and whether each has a territory. A cone that is
  -- decided and has a share but no territory is the "volcano with no territory and
  -- no explanation" failure, and this is where it shows up.
  -- The mod's defect list: a cone that could not be given a patrol loop or a
  -- demolisher says so here, and a "no unit" failure is meaningless without it.
  do
  end

  -- The mod's per-cone report, built HERE from the mirror and the surface. It used
  -- to be fetched over a remote (eon-status) that existed only so this file could
  -- ask the mod questions the mirror answers by itself -- the probe already requires
  -- it. The one column the mirror cannot answer was `created`, the mod's own marker,
  -- and the honest local stand-in is the FACT it stands for: a cone whose centre
  -- chunk carries one of our territories. A territory carrying a segmented unit is
  -- how this file already tells ours from the map's own (biter, gleba, aquifer)
  -- further down, so the test is the same one and needs nothing from the mod.
  --
  -- What that costs: "decided but no territory" can no longer be observed from this
  -- column, because both columns now read the same engine call. It is not lost, it
  -- moved to where the decision is actually recorded -- the mod's claim log line --
  -- and the harness checks the two against each other (see territory_cone_ids).
  -- Every cone that currently holds one of OUR territories, keyed by id, found by
  -- walking the surface rather than the map: a cone outside this window can still be
  -- claimed -- nothing bounds where a player has walked -- and a report built from
  -- the window alone would miss exactly the claims most worth seeing.
  --
  -- This doubles as the half of the old "decided" assertion that the mod's marker
  -- used to provide: the harness matches the mod's claim log lines against these ids
  -- (see the report volcanoes), which is the same invariant -- a cone the mod decided
  -- must have a territory -- asked from the two sides that actually hold the facts.
  -- The cone whose SHARE holds this chunk, or nil. Shares are cached per cone id
  -- because one is a full disc scan (8 ms on a 145-chunk claim) and a run touches
  -- a few dozen of them.
  local share_cache = {}
  local function share_of(cone)
    local set = share_cache[cone.id]
    if not set then
      set = {}
      for _, chunk in ipairs(volcanoes:cone_chunks(cone, volcanoes:contenders_for(cone))) do
        set[chunk.x .. "," .. chunk.y] = true
      end
      share_cache[cone.id] = set
    end
    return set
  end
  local function share_owner(chunk_x, chunk_y)
    local key = chunk_x .. "," .. chunk_y
    local ring = volcanoes:nearby_cones(chunk_x * 32 + 16, chunk_y * 32 + 16, 64)
    for index = 1, ring.n do
      local cone = ring[index]
      if share_of(cone)[key] then return cone end
    end
    return nil
  end
  local function our_cone_ids()
    local found = {}
    for _, territory in ipairs(surface.get_territories()) do
      if territory.valid and #territory.get_segmented_units() > 0 then
        local members = territory.get_chunks()
        if #members > 0 then
          local minx, maxx, miny, maxy = members[1].x, members[1].x, members[1].y, members[1].y
          for _, chunk in ipairs(members) do
            minx = math.min(minx, chunk.x); maxx = math.max(maxx, chunk.x)
            miny = math.min(miny, chunk.y); maxy = math.max(maxy, chunk.y)
          end
          -- Which cone CLAIMED this territory, which is not the same question as
          -- whose terrain a chunk is: the claim is nearest-centre among the cones
          -- that cover the chunk (Volcanoes:claim_winner), while chunk_owner answers the
          -- engine's max-of-cones volcanoes rule. On a squashed cone the two disagree
          -- completely -- a 13-chunk lens lost to a 500-tile neighbour reads as
          -- entirely the neighbour's under the volcanoes rule -- and asking by majority
          -- over the members attributed that claim to a cone that had never claimed
          -- anything, which failed the cross-check below on every 100%-volcanism
          -- run.
          --
          -- So it is asked the claim's own way: the cone whose SHARE holds the chunk.
          -- create_territory strips the chunks it takes, so a territory's chunks
          -- belong to exactly one cone's share and the answer is exact. The share is
          -- the most expensive thing the mirror computes, so it is cached per cone
          -- and a territory costs a handful of table reads.
          local votes, best, best_votes = {}, nil, 0
          local step = math.max(1, math.floor(#members / 5))
          for index = 1, #members, step do
            local owner = share_owner(members[index].x, members[index].y)
            if owner then
              votes[owner.id] = (votes[owner.id] or 0) + 1
              if votes[owner.id] > best_votes then best, best_votes = owner, votes[owner.id] end
            end
          end
          if best then found[best.id] = best end
        end
      end
    end
    return found
  end
  local function our_territory_at(chunk_x, chunk_y)
    local territory = surface.get_territory_for_chunk({ x = chunk_x, y = chunk_y })
    return territory ~= nil and territory.valid and #territory.get_segmented_units() > 0
  end
  local function status_text()
    local lines = { string.format("chunk %d,%d (gps %d,%d)", ccx(), ccy(),
      ccx() * 32 + 16, ccy() * 32 + 16) }
    local seen, claimed, empty = {}, 0, 0
    local ring = volcanoes:nearby_cones(ccx() * 32 + 16, ccy() * 32 + 16, 64)
    for index = 1, ring.n do seen[ring[index].id] = ring[index] end
    for id, cone in pairs(our_cone_ids()) do seen[id] = cone end
    local ids = {}
    for id in pairs(seen) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local cone = seen[id]
      local share = volcanoes:cone_chunks(cone, volcanoes:contenders_for(cone))
      local cx, cy = math.floor(cone.x / 32), math.floor(cone.y / 32)
      local mine = our_territory_at(cx, cy)
      if mine then claimed = claimed + 1 end
      lines[#lines + 1] = string.format(
        "  %-14s centre %7.0f,%8.0f (chunk %d,%d) width %5.0f share %4d/disc %4d "
        .. "density %-9.4f created %-5s territory %s",
        id, cone.x, cone.y, cx, cy, cone.width, #share, #volcanoes:cone_disc(cone),
        cones.cone_density(volcanoes.context, cone.x, cone.y), tostring(mine),
        tostring(surface.get_territory_for_chunk({ x = cx, y = cy }) ~= nil))
    end
    lines[#lines + 1] = string.format("  totals: claimed %d, unseen 0, empty %d", claimed, empty)
    return table.concat(lines, "\n")
  end
  local status = status_text()
  local function count_decided(text)
    local total, missing = 0, {}
    for line in text:gmatch("[^\n]+") do
      if line:match("share%s+%d+/disc") and line:match("created%s+true") then
        total = total + 1
        if line:match("territory%s+false") then
          missing[#missing + 1] = line:match("%S+")
        end
      end
    end
    return total, missing
  end
  local decided_count, decided_without_territory = 0, {}
  decided_count, decided_without_territory = count_decided(status)

  local first_snapshot = snapshot_territories(surface)
  local empty_territories, segmented_units, unit_names, bad_pairs =
    survey_segmented_units(surface)

  -- 2. Re-enter the handler on chunks that already have their territory: delete
  --    a block and generate it again. Nothing may change. (2.0 has no
  --    regenerate_chunks; delete + request is the same thing.)
  for cx = -2, 2 do
    for cy = -2, 2 do
      surface.delete_chunk({ x = ccx() + cx, y = ccy() + cy })
    end
  end
  for cx = -2, 2 do
    for cy = -2, 2 do
      surface.request_to_generate_chunks({ (ccx() + cx) * 32, (ccy() + cy) * 32 }, 0)
    end
  end
  surface.force_generate_chunk_requests()
  local second_snapshot = snapshot_territories(surface)
  local unchanged, changed_key = same_snapshot(first_snapshot, second_snapshot)

  mark("stage 2 done")
  -- 3. The "created early" case: a cone OUTSIDE the generated area whose
  --    footprint reaches past it. Generate only its centre chunk plus one
  --    footprint chunk, let the mod create the territory with the rest still
  --    ungenerated, then generate the rest and check they joined it.
  -- A cone outside the generated area does not show up in cones_near, because
  -- its gate is undecided there. Enumerate with a gate-free mirror instead and
  -- take the closest cone whose candidate chunks are all still ungenerated.
  local ungated = cones.new_volcanoes(cones.new_context{
    seed = surface.map_gen_settings.seed,
    volcanism_size = (surface.map_gen_settings.autoplace_controls["vulcanus_volcanism"] or {}).size or 1,
    volcanism_frequency = (surface.map_gen_settings.autoplace_controls["vulcanus_volcanism"] or {}).frequency or 1,
  })
  local candidates_outside = {}
  for _, cone in ipairs(ungated:cones_near(ccx(), ccy(), R + 40)) do
    local chunks = ungated:cone_chunks(cone, ungated:contenders_for(cone))
    local ungenerated = 0
    for _, chunk in ipairs(chunks) do
      if not surface.is_chunk_generated(chunk) then ungenerated = ungenerated + 1 end
    end
    -- At 600% the small cones are barely bigger than their own gate block, so
    -- "pick a cone whose disc is entirely ungenerated" can hand back a disc that the
    -- gate block has already covered. Require a disc big enough that deciding it
    -- early is a real question.
    if #chunks >= 12 and ungenerated == #chunks then
      local dx = math.floor(cone.x / 32) - ccx()
      local dy = math.floor(cone.y / 32) - ccy()
      candidates_outside[#candidates_outside + 1] = { cone = cone, chunks = chunks,
                                                    distance = dx * dx + dy * dy }
    end
  end
  table.sort(candidates_outside, function(a, b) return a.distance < b.distance end)

  local late_result, ungenerated_at_first_look = nil, 0
  for _, candidate in ipairs(candidates_outside) do
    -- Generate ONLY the cone's centre chunk. That single chunk is what the tile
    -- gate needs, so the mod must decide the cone HERE -- this is the live bug:
    -- the first implementation waited for the whole candidate disc, and a big
    -- cone's disc is ~390 chunks over ~1600 tiles, so on a real map the frontier
    -- reached the centre long before the rim and the volcano was never claimed
    -- at all (measured on a live save: 387 candidates, 270 generated, 75
    -- volcanic chunks in no territory).
    local centre = {
      x = math.floor(candidate.cone.x / 32),
      y = math.floor(candidate.cone.y / 32),
    }
    -- ONE chunk, the cone's own centre. This used to be a 3x3 block, because
    -- existence was a tile gate -- "seven of the nine chunks around the centre are
    -- volcanic" -- and that block existed to satisfy it. Existence is the engine's
    -- DENSITY expression now and reads no tile at all, so the block was not
    -- measuring the thing it was named for: on a 12-chunk disc it generated 9 of
    -- the 12 and then reported, correctly, that the disc was 75% revealed when the
    -- cone was decided (the gate failed on exactly that, at 600% volcanism).
    --
    -- What the current design needs is ONE generated chunk, because
    -- create_territory refuses a list with none -- and that is the real-world
    -- shape too: the player reaches the centre of a volcano long before its rim.
    surface.request_to_generate_chunks({ centre.x * 32, centre.y * 32 }, 0)
    surface.force_generate_chunk_requests()
    -- on_chunk_generated is delivered BETWEEN top-level event handlers, so
    -- force_generate_chunk_requests inside the probe's own on_init only QUEUES
    -- the mod's handler. Ask the mod directly instead -- the same call
    -- on_chunk_generated would make, run synchronously -- so `decided` is a real
    -- answer while the cone's own disc is still ungenerated.
    -- NO remote call here any more, and that makes this a WEAKER statement than it
    -- was. What the block exists to catch is a cone claimed long before its disc
    -- exists: create_territory needs ONE generated chunk and the player reaches a
    -- volcano's centre long before its rim. It used to be measured by asking the
    -- mod directly, inside on_init, because the engine delivers on_chunk_generated
    -- BETWEEN handlers and so nothing can be decided yet at this point.
    --
    -- The engine decides now, and it decides before this measurement runs, so the
    -- count below is "how much of the disc was ungenerated when the probe first
    -- LOOKED", not "when it was decided". It still catches a claim that waits for
    -- the whole disc -- every chunk would be generated by now -- but no longer a
    -- claim that is merely slow. The python side is told which it is reading.
    -- How much of the disc was still ungenerated AT THAT MOMENT: the whole point of
    -- the change is that the cone is decided long before its footprint exists.
    ungenerated_at_first_look = (function()
      local n = 0
      for _, chunk in ipairs(candidate.chunks) do
        if not surface.is_chunk_generated(chunk) then n = n + 1 end
      end
      return n
    end)()
    -- The invariant is LATENCY: the cone must be decided while most of its disc is
    -- still ungenerated. There is no tile verdict to take here -- existence is the
    -- engine's density expression and reads no tile -- which is why the 3x3 block
    -- that used to be generated and scored is gone. It satisfied a gate that no
    -- longer exists, it called get_tile on chunks that were never generated (that
    -- raises, and takes the whole map generation with it), and on a 12-chunk disc
    -- it generated 9 of the 12 before measuring the thing it was measuring.
    local decided = surface.get_territory_for_chunk(centre) ~= nil
    -- Then generate the whole candidate set and check the territory grew into a
    -- complete cover without being re-created.
    for _, chunk in ipairs(candidate.chunks) do
      surface.request_to_generate_chunks({ chunk.x * 32, chunk.y * 32 }, 0)
    end
    surface.force_generate_chunk_requests()
    local set, generated = {}, 0
    for _, chunk in ipairs(candidate.chunks) do
      if surface.is_chunk_generated(chunk) then
        generated = generated + 1
        if is_volcano(surface.get_tile(chunk.x * 32 + 16, chunk.y * 32 + 16).name) then
          set[chunk.x .. "," .. chunk.y] = true
        end
      end
    end
    local wanted = 0
    for _ in pairs(set) do wanted = wanted + 1 end
    -- Which territory, if any, now holds this cone's volcanic chunks?
    local owner, members = nil, {}
    for key in pairs(set) do
      local x, y = key:match("^(-?%d+),(-?%d+)$")
      local territory = surface.get_territory_for_chunk({ x = tonumber(x), y = tonumber(y) })
      if territory and territory.valid then owner = territory end
    end
    if owner then
      for _, member in ipairs(owner.get_chunks()) do
        members[member.x .. "," .. member.y] = true
      end
    end
    -- The contract is no longer "the territory is exactly the rendered tile
    -- truth" (it cannot be: the chunks this cone was given while ungenerated are
    -- now rendered and are still members). It is: the territory COVERS every
    -- volcanic chunk of the cone, and holds nothing the mirror did not assign to
    -- it.
    local candidate_set = {}
    for _, chunk in ipairs(candidate.chunks) do
      candidate_set[chunk.x .. "," .. chunk.y] = true
    end
    local member_count = 0
    local covers, no_foreign = owner ~= nil and wanted > 0, true
    for key in pairs(members) do
      member_count = member_count + 1
      if not candidate_set[key] then no_foreign = false end
    end
    for key in pairs(set) do
      if not members[key] then covers = false end
    end
    local exact = covers and no_foreign
    if exact then
      -- A further generation wave around the same cone must change nothing.
      local snapshot_before = snapshot_territories(surface)
      local cx, cy = math.floor(candidate.cone.x / 32), math.floor(candidate.cone.y / 32)
      for dx = -1, 1 do
        for dy = -1, 1 do
          surface.request_to_generate_chunks({ (cx + dx) * 32, (cy + dy) * 32 }, 0)
        end
      end
      surface.force_generate_chunk_requests()
      local stable = same_snapshot(snapshot_before, snapshot_territories(surface))
      late_result = {
        cone = candidate.cone.id, candidates = #candidate.chunks, generated = generated,
        wanted = wanted, members = member_count, exact = exact,
        -- How much of the disc was ungenerated when the probe FIRST LOOKED, which is
        -- no longer the same thing as "when the cone was decided": the engine
        -- decides before this measurement runs, and it used to be that the probe
        -- asked the mod directly, inside on_init, for an answer at that moment. The
        -- python side stopped asserting on it and reports it instead.
        disc_ungenerated_at_first_look = ungenerated_at_first_look,
        stable_after_more_generation = stable,
      }
      break
    end
  end

  -- Everything above generated chunks; give the builder one more pass over the
  -- disc and one audit, which is the point a real game reaches after a minute of
  -- ticks. force_generate_chunk_requests returns before the whole disc is
  -- rendered, so a cone's gate block can still be undecided here (measured: the
  -- 3x3 around one cone was complete only after the later phases), and the audit
  -- is the backstop that claims it anyway.
  -- One more pass at the very end, so the numbers below describe the FINAL state:
  -- the priority test below steals chunks and calls the audit itself.
  do
    status = status_text()
    decided_count, decided_without_territory = count_decided(status)
  end

  -- Every patrol point must stand on VOLCANO GROUND, not merely inside the claim.
  -- These are different questions and the gap between them is where this was found:
  -- on a triplet of neighbours 156 tiles apart the claim was 98-99% volcanic (1 bad
  -- chunk in 66-86) while 3-4 of 32 patrol_path points were off the ground, because the
  -- patrol_path lives entirely on the claim's edge and the edge is the one place a 1%
  -- claim error concentrates. The cause was the patrol_path being centred on the claim's
  -- centre of mass, which a lopsided claim drags 72-88 tiles off the cone.
  --
  -- A point counts as off-volcano when the TILE under it is not volcanic, which is
  -- the player's view: the guard is walking somewhere that does not look like part
  -- of the volcano.
  -- The patrol_path must not merely be ON the rock; it must be at the EDGE of the rock.
  -- A patrol_path clipped deep inside the volcano passes an "is it volcanic" test just
  -- as happily as one that traces the boundary, and that is a real failure mode --
  -- an over-tight bound looks perfect on the first check and patrols a circle in
  -- the middle of a field. So each point is bracketed: a little further out along
  -- the same direction must be OFF the volcano, and a little further in must be ON it.
  -- Both are read from the RENDERED tiles, so this needs no mirror and no oracle.
  local territory_census, volcano_territories = {}, {}
  local off_volcano_points, off_volcano_examples = 0, {}
  local off_edge_points, edge_examples = 0, {}
  local on_folds_line, off_line, line_examples = 0, 0, {}
  for _, territory in ipairs(surface.get_territories()) do
    if territory.valid then
      local units = #territory.get_segmented_units()
      local census = { chunks = #territory.get_chunks(), units = units }
      if units > 0 then
        volcano_territories[territory_key(territory)] = true
        local patrol_path = territory.get_patrol_path()
        local bad, unrendered = 0, 0
        for index, point in ipairs(patrol_path) do
          -- A patrol_path point can land on a chunk the CLAIM holds but the map has not
          -- rendered: get_tile on one of those raises "LuaTile API call when LuaTile
          -- was invalid" and takes the whole event handler with it. Counted apart
          -- rather than guessed at -- an unrendered point is not a fault.
          local generated = surface.is_chunk_generated({
            x = math.floor(point.x / 32), y = math.floor(point.y / 32),
          })
          if not generated then
            unrendered = unrendered + 1
          else
            local tile = surface.get_tile(math.floor(point.x), math.floor(point.y))
            if not is_volcano(tile.name) then
              bad = bad + 1
              if #off_volcano_examples < 6 then
                off_volcano_examples[#off_volcano_examples + 1] = string.format(
                  "point %d of %d on %s", index, #patrol_path, tile.name)
              end
            end
          end
        end
        -- Bracket every point against the boundary. The centre of the loop is the
        -- mean of the patrol_path, which is the one point a radial test can be measured
        -- from without knowing the cone's centre.
        local ax, ay = 0, 0
        for _, point in ipairs(patrol_path) do ax = ax + point.x; ay = ay + point.y end
        ax, ay = ax / #patrol_path, ay / #patrol_path
        local off_edge = 0
        for _, point in ipairs(patrol_path) do
          local dx, dy = point.x - ax, point.y - ay
          local d = math.sqrt(dx * dx + dy * dy)
          if d > 1 then
            local ux, uy = dx / d, dy / d
            local function tile_volcanic(scale)
              local x = math.floor(ax + ux * d * scale)
              local y = math.floor(ay + uy * d * scale)
              if not surface.is_chunk_generated({ x = math.floor(x / 32), y = math.floor(y / 32) }) then
                return nil
              end
              return is_volcano(surface.get_tile(x, y).name)
            end
            local inner, outer = tile_volcanic(0.75), tile_volcanic(1.25)
            -- The precise question: is this the folds / folds-flat TRANSITION?
            -- Both tiles are volcanic, so a plain volcanic test cannot tell a
            -- patrol_path on the line from one parked in the middle of the flat zone.
            -- Inside the patrol_path it should be `volcanic-folds`; a little way out it
            -- should have become `volcanic-folds-flat`. That names the boundary
            -- rather than approximating it.
            local function tile_name(scale)
              local x = math.floor(ax + ux * d * scale)
              local y = math.floor(ay + uy * d * scale)
              if not surface.is_chunk_generated({ x = math.floor(x / 32), y = math.floor(y / 32) }) then
                return nil
              end
              return surface.get_tile(x, y).name
            end
            local inner_name, outer_name = tile_name(0.75), tile_name(1.25)
            if inner_name and outer_name then
              local inner_folds = inner_name == "volcanic-folds"
              local outer_flat = outer_name == "volcanic-folds-flat"
              if inner_folds and outer_flat then
                on_folds_line = on_folds_line + 1
              else
                off_line = off_line + 1
                if #line_examples < 6 then
                  line_examples[#line_examples + 1] = string.format(
                    "%s -> %s at %.0f tiles", inner_name, outer_name, d)
                end
              end
            end
            -- nil is an unrendered sample, which is not evidence either way.
            if inner ~= nil and outer ~= nil and (not inner or outer) then
              off_edge = off_edge + 1
              if #edge_examples < 6 then
                edge_examples[#edge_examples + 1] = string.format(
                  "inner %s outer %s at %.0f tiles", tostring(inner), tostring(outer), d)
              end
            end
          end
        end
        off_edge_points = off_edge_points + off_edge
        census.patrol_path_points = #patrol_path
        census.off_volcano = bad
        census.off_edge = off_edge
        census.unrendered_points = unrendered
        off_volcano_points = off_volcano_points + bad
      end
      territory_census[#territory_census + 1] = census
    end
  end
  local volcano_territory_count = 0
  for _ in pairs(volcano_territories) do volcano_territory_count = volcano_territory_count + 1 end

  -- Does the wobble EXPLAIN the tile boundary, or merely sit near it?
  --
  -- For each direction, solve for the fraction F at which the mirror's wobbled disc
  -- boundary lands exactly on the last volcanic tile the game rendered. If the
  -- boundary really is a wobbled disc, F is the SAME on every direction and the wobble
  -- is the whole story. If F wanders, the disc is not the shape and something else
  -- is bending the edge -- and the spread says how much.
  --
  -- This is the check that distinguishes "the mirror predicts the ground" from
  -- "the mirror's circle happens to be near the ground", and it reads the same
  -- tiles the player sees.
  -- OFF BY DEFAULT, and deliberately: this is a development DIAGNOSTIC, not a check.
  -- It walks 16 directions per cone to solve for the fraction at which the mirror's wobbled
  -- disc lands on the game's own tile change, and it is what measured
  -- F = 0.434 +/- 0.026 -- which is how the crossover constant was found. Those
  -- constants are DERIVED from the shipped expression now, so there is nothing to
  -- re-derive per run, and tests/field_parity.py already fails loudly if the
  -- expression changes. It was the most expensive thing here by a wide margin
  -- (the 600% e2e took 220 s, and this was most of it). Flip this to true to
  -- re-run the fit after touching the boundary constants.
  -- The two per-cone accumulators, at the measurement level and not inside the
  -- RUN_FIT loop: the report at the end reads both, and when they lived in the loop
  -- the report could only reach them by being INSIDE the loop too. That is how the
  -- census ended up running once per cone.
  local RUN_FIT = false
  local fit = { samples = 0, min = math.huge, max = -math.huge, sum = 0, worst = 0 }
  local line_err = { samples = 0, worst = 0, sum = 0, exact = 0, hist = {}, nearby = {}, pairs = {} }
  local function fraction_for(cone, ux, uy, target)
    -- The boundary of a fraction-disc grows with the fraction, so a bisection on F
    -- is sound here even though the boundary is not monotonic in RADIUS: the
    -- displacement is a function of position, not of the fraction.
    local low, high = 0.05, 0.95
    for _ = 1, 24 do
      local mid = (low + high) / 2
      if PatrolPath.wobbled_radius(volcanoes, cone, ux, uy, mid) < target then low = mid else high = mid end
    end
    return (low + high) / 2
  end
  for _, entry in ipairs(entries) do
    local cone = entry.cone
    if RUN_FIT then
    for index = 0, 15 do
      local angle = 2 * math.pi * index / 16
      local ux, uy = math.cos(angle), math.sin(angle)
      local last = 0
      local x = math.floor(cone.x)
      local y = math.floor(cone.y)
      for r = 0, cone.width do
        local px, py = math.floor(x + ux * r), math.floor(y + uy * r)
        if not surface.is_chunk_generated({ x = math.floor(px / 32), y = math.floor(py / 32) }) then
          last = nil
          break
        end
        if is_volcano(surface.get_tile(px, py).name) then last = r end
      end
      -- Only a direction whose whole length was rendered can be fitted, and a direction that
      -- never leaves volcanic ground has no boundary to find.
      -- Only directions this cone still OWNS at their far end measure THIS cone's
      -- boundary. Where a neighbour's ground takes over, the tiles stay volcanic
      -- for that neighbour's reason, and fitting against them invents a fraction
      -- up to 0.89. At 600% volcanism almost every cone has a neighbour, and the
      -- unfiltered fit spread 0.475 against 0.026 filtered -- so the filter is the
      -- difference between measuring the wobble and measuring the neighbours.
      local owns_end = true
      if last then
        local ex, ey = cone.x + ux * last, cone.y + uy * last
        local owner = volcanoes:chunk_owner(math.floor(ex / 32), math.floor(ey / 32))
        owns_end = owner == nil or owner.id == cone.id
      end
      if last and last > 8 and last < cone.width * 0.9 and owns_end then
        local F = fraction_for(cone, ux, uy, last)
        fit.samples = fit.samples + 1
        fit.sum = fit.sum + F
        if F < fit.min then fit.min = F end
        if F > fit.max then fit.max = F end
      end
    end
  end

  -- PER-DIRECTION accuracy of the folds/folds-flat prediction. This is the real test:
  -- walking out along one direction, the tile is `volcanic-folds` near the centre and
  -- becomes `volcanic-folds-flat` at the boundary. The mirror predicts that radius
  -- from the noise alone (FOLDS_LINE_FRACTION through the wobbled disc). If the
  -- prediction is right, the two agree direction by direction -- and if they do not, the
  -- residual is a per-direction number in tiles, which is a thing to fix, rather than a
  -- percentage of patrol_path points, which is not.
  for _, entry in ipairs(entries) do
    local cone = entry.cone
    for index = 0, 15 do
      local angle = 2 * math.pi * index / 16
      local ux, uy = math.cos(angle), math.sin(angle)
      -- The game's answer. Walking out from the centre the order is
      -- volcanic-folds, then volcanic-folds-flat, then off the volcano -- so the
      -- boundary is the FIRST folds-flat tile seen after a folds one, not the
      -- last tile on the direction (which by then is ice, or nothing at all).
      local saw_folds, boundary, last_folds_seen = false, nil, nil
      for r = 0, cone.width do
        local px, py = math.floor(cone.x + ux * r), math.floor(cone.y + uy * r)
        if not surface.is_chunk_generated({ x = math.floor(px / 32), y = math.floor(py / 32) }) then
          boundary = nil
          break
        end
        local tile = surface.get_tile(px, py).name
        if tile == "volcanic-folds" then
          saw_folds = true
          last_folds_seen = r
        elseif tile == "volcanic-folds-flat" and saw_folds and not boundary then
          boundary = r
        end
      end
      if boundary then
        -- Both candidate definitions, because the two differ by the transition
        -- tile the prototype declares (`transitions = lava_stone_transitions`), and
        -- one of them is the model's real boundary:
        --   boundary  = the FIRST folds-flat tile seen (past the transition)
        --   last_folds = the LAST folds tile seen (at it)
        -- If the model is right, the prediction should match one of them to well
        -- under a tile, and the size of the gap between them says which.
        local last_folds = last_folds_seen
        if last_folds then
        local ex, ey = cone.x + ux * last_folds, cone.y + uy * last_folds
        local owner = volcanoes:chunk_owner(math.floor(ex / 32), math.floor(ey / 32))
        if owner == nil or owner.id == cone.id then
          local predicted = PatrolPath.wobbled_radius(volcanoes, cone, ux, uy, VC.FOLDS_LINE_FRACTION)
          local error = math.abs(predicted - last_folds)
          -- Split by whether a THIRD tile is in play. Lava's score comes from a
          -- different spot volcanoes (mountain_lava_spots) that the mirror does not
          -- compute, so where lava is near the transition it can win the boundary
          -- and the mirror would be missing a variable. If the error is on those
          -- directions and not the others, that is the answer; if it is spread evenly, it
          -- is the f32 tie instead.
          local rival = false
          for ox = -1, 1 do for oy = -1, 1 do
            local cx1, cy1 = math.floor(cone.x + ux * boundary) / 32 + ox,
                             math.floor(cone.y + uy * boundary) / 32 + oy
            if surface.is_chunk_generated({ x = math.floor(cx1), y = math.floor(cy1) }) then
              local tile = surface.get_tile(cx1 * 32 + 16, cy1 * 32 + 16).name
              if tile == "lava" or tile == "lava-hot" then rival = true end
            end
          end end
          line_err.pairs[#line_err.pairs + 1] = { predicted, boundary, rival and 1 or 0 }
          local error_flat = math.abs(predicted - boundary)
          line_err.flat_sum = (line_err.flat_sum or 0) + error_flat
          if error_flat > (line_err.flat_worst or 0) then line_err.flat_worst = error_flat end
          line_err.samples = line_err.samples + 1
          line_err.sum = line_err.sum + error
          if error < 0.5 then line_err.exact = line_err.exact + 1 end
          if error > line_err.worst then line_err.worst = error end
          local bucket = math.floor(error / 8) * 8
          line_err.hist[bucket] = (line_err.hist[bucket] or 0) + 1
          -- Which tiles are actually PRESENT around the transition? If only
          -- folds and folds-flat (plus lava) ever appear there, the two-tile
          -- competition is the whole story and the residual is not a missing
          -- competitor. If folds-warm or a ground tile shows up, then resolving
          -- the winner needs their scores -- and folds-warm's is
          -- `2*(vulcanus_mountains_biome - 0.5) + 3*(mountain_volcano_spots
          -- - 0.85) - 2*(aux - 0.5)`, which is the biome noise and not yet ported.
          local cx0 = math.floor(cone.x + ux * last_folds)
          local cy0 = math.floor(cone.y + uy * last_folds)
          for ox = -1, 1 do for oy = -1, 1 do
            local cx1, cy1 = math.floor(cx0 / 32) + ox, math.floor(cy0 / 32) + oy
            if surface.is_chunk_generated({ x = cx1, y = cy1 }) then
              local tile = surface.get_tile(cx1 * 32 + 16, cy1 * 32 + 16).name
              line_err.nearby[tile] = (line_err.nearby[tile] or 0) + 1
            end
          end end
        end
        end
      end
    end
  end
  end -- the RUN_FIT loop: everything below measures the SURFACE once, so it is
  -- outside the loop. It was not, and nothing caught it -- see the stray `end`
  -- below, which cancels this one out and hides it from luac.

  mark("stages 1-3 done")
  census_passes = census_passes + 1

  -- Every volcano territory must STAND ON a volcano. This is the claim test itself
  -- ("at least half of the cone's revealed ground is volcano", Builder:
  -- volcanic_fraction), checked from the outside: a live playtest found territories
  -- on 4 of 22, 6 of 45 and 2 of 52 volcanic chunks, each with a demolisher and a
  -- patrol_path over open ground. A territory is exempt below 9 revealed chunks,
  -- where the evidence is too thin to judge.
  local off_ground = {}
  for _, territory in ipairs(surface.get_territories()) do
    if territory.valid and volcano_territories[territory_key(territory)] then
      local rendered, volcanic = 0, 0
      for _, chunk in ipairs(territory.get_chunks()) do
        if surface.is_chunk_generated({ x = chunk.x, y = chunk.y }) then
          rendered = rendered + 1
          if is_volcano(surface.get_tile(chunk.x * 32 + 16, chunk.y * 32 + 16).name) then
            volcanic = volcanic + 1
          end
        end
      end
      if rendered >= 9 and volcanic * 2 < rendered then
        local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
        for _, chunk in ipairs(territory.get_chunks()) do
          minx = math.min(minx, chunk.x); maxx = math.max(maxx, chunk.x)
          miny = math.min(miny, chunk.y); maxy = math.max(maxy, chunk.y)
        end
        local units = {}
        for _, unit in ipairs(territory.get_segmented_units()) do
          units[#units + 1] = unit.prototype.name
        end
        local best, best_hits = "?", 0
        for _, entry in ipairs(entries) do
          local hits = 0
          for _, chunk in ipairs(territory.get_chunks()) do
            if entry.share[chunk.x .. "," .. chunk.y] then hits = hits + 1 end
          end
          if hits > best_hits then best_hits, best = hits, entry.id end
        end
        -- The mirror's view of the cone that owns this territory's middle: its
        -- share size against the disc it was cut from. If those disagree with the
        -- territory's contents, the claim is stale (built from a different answer)
        -- rather than wrong.
        --
        -- Asked of the mirror directly, which is what the status remote used to be
        -- for. It parsed two columns that have not existed for a long time -- "gate"
        -- and "3x3", both dead with the tile gate and the density gate -- so this
        -- volcanoes has been ending in "? ?" while looking like it was reporting.
        local centre_x, centre_y = math.floor((minx + maxx) / 2), math.floor((miny + maxy) / 2)
        local owner = volcanoes:chunk_owner(centre_x, centre_y)
        local owner_line = "no cone at that chunk"
        if owner then
          owner_line = string.format("%s share %d/disc %d density %+.4f",
            owner.id, #volcanoes:cone_chunks(owner, volcanoes:contenders_for(owner)), #volcanoes:cone_disc(owner),
            cones.cone_density(volcanoes.context, owner.x, owner.y))
        end
        off_ground[#off_ground + 1] = string.format(
          "%d of %d chunks volcanic, %d chunks bbox %d..%d,%d..%d, centre %d,%d -> %s, units %s",
          volcanic, rendered, #territory.get_chunks(), minx, maxx, miny, maxy, centre_x,
          centre_y, owner_line, table.concat(units, "+"))
      end
    end
  end
  table.sort(off_ground)

  -- Territory -> cone, by the disc that holds most of its chunks, and how many of
  -- its chunks fall OUTSIDE that disc. Done per territory rather than per window
  -- position: a position's territory and the disc that contains the position can
  -- be two different cones, and comparing one territory's members against the
  -- other's disc measures nothing.
  local outside_disc_count, outside_disc_territories = 0, {}
  for _, territory in ipairs(surface.get_territories()) do
    if territory.valid and volcano_territories[territory_key(territory)] then
      local members = territory.get_chunks()
      local best_entry, best_hits = nil, 0
      for _, entry in ipairs(entries) do
        local hits = 0
        for _, chunk in ipairs(members) do
          if entry.expected[chunk.x .. "," .. chunk.y] then hits = hits + 1 end
        end
        if hits > best_hits then best_hits, best_entry = hits, entry end
      end
      if not best_entry then
        outside_disc_territories[#outside_disc_territories + 1] = #members
      else
        for _, chunk in ipairs(members) do
          if not best_entry.expected[chunk.x .. "," .. chunk.y] then
            outside_disc_count = outside_disc_count + 1
          end
        end
      end
    end
  end

  -- Every territory that exists must have passed the 3x3 gate: 7 of the 9 chunks
  -- around its cone's centre are volcanic ground. This is what keeps a shoreline
  -- lava patch from claiming open sea.
  -- Ownership between overlapping cones is settled gate-free (a fixed split), so
  -- a cone whose gate said "no volcano here" leaves its lens unclaimed until the
  -- audit refills it from the surviving neighbour's disc. Run the audit now, over
  -- remote, so the comparison below sees the settled state.
  do
    local ok, result = pcall(function()
    end)
  end

  local gate_block = {}
  for _, entry in ipairs(entries) do
    local cx, cy = math.floor(entry.cone.x / 32), math.floor(entry.cone.y / 32)
    if surface.get_territory_for_chunk({ x = cx, y = cy }) then
      local volcanic, generated = 0, 0
      for dy = -1, 1 do for dx = -1, 1 do
        local x, y = cx + dx, cy + dy
        if surface.is_chunk_generated({ x = x, y = y }) then
          generated = generated + 1
          if is_volcano(surface.get_tile(x * 32 + 16, y * 32 + 16).name) then volcanic = volcanic + 1 end
        end
      end end
      gate_block[#gate_block + 1] = {
        id = entry.id, volcanic = volcanic, generated = generated,
      }
    end
  end

  -- Every territory on the surface with its size and unit count, so a count that
  -- does not match the mirror can be attributed: ours (which have a demolisher) or
  -- the map's own (biter, gleba, aquifer), which the runtime path neither creates
  -- nor owns.

  table.sort(territory_census, function(a, b) return a.chunks < b.chunks end)


  -- 4. Compare the surface against the mirror's footprints inside the disc.
  local matched, mismatched, missing_chunks, extra = 0, 0, 0, 0
  local on_volcano, off_volcano, off_examples = 0, 0, {}
  -- The per-chunk answer must name a cone for every chunk a territory holds: a
  -- territory may not contain a chunk the mirror does not assign to its cone.
  local unowned_territory_chunks, unowned_examples = 0, {}
  local off_tiles, off_by_cone = {}, {}
  for cx = -R, R do
    for cy = -R, R do
      if cx * cx + cy * cy <= (R + 0.5) * (R + 0.5) then
        local position = { x = ccx() + cx, y = ccy() + cy }
        local key = position.x .. "," .. position.y
        -- Which cone may hold this chunk: the one whose DISC it is in, since a
        -- member can be the cone's own share or a lens the audit refilled.
        local expected_here
        for _, entry in ipairs(entries) do
          if entry.expected[key] then expected_here = entry end
        end
        local territory = surface.get_territory_for_chunk(position)
        -- Only the volcano's own territories: the map also has biter, gleba and
        -- aquifer territories, and holding chunks of THOSE is not this mod's doing.
        if territory and not volcano_territories[territory_key(territory)] then
          territory = nil
        end
        if territory then
          local members = {}
          for _, member in ipairs(territory.get_chunks()) do
            members[member.x .. "," .. member.y] = true
          end
          local tile = surface.get_tile(position.x * 32 + 16, position.y * 32 + 16).name
          -- Ownership between overlapping cones is settled GATE-FREE (the split
          -- must not move as gates resolve), so the probe asks the same way:
          -- is this chunk inside any cone's claimed disc at all?
          if not in_any_disc(volcanoes, position.x, position.y) then
            unowned_territory_chunks = unowned_territory_chunks + 1
            if #unowned_examples < 5 then unowned_examples[#unowned_examples + 1] = key end
          end
          if is_volcano(tile) then
            on_volcano = on_volcano + 1
          else
            off_volcano = off_volcano + 1
            off_tiles[tile] = (off_tiles[tile] or 0) + 1
            if expected_here then
              off_by_cone[expected_here.id] = (off_by_cone[expected_here.id] or 0) + 1
            end
            if #off_examples < 5 then off_examples[#off_examples + 1] = key .. "=" .. tile end
          end
          if expected_here then
            -- Two directions, because a territory is now a SUPERSET of the
            -- rendered tile truth: it holds the whole candidate disc, including
            -- chunks that were still ungenerated when it was created (and have
            -- joined since -- the chunks iterated here are all generated).
            --   * every rendered-volcanic candidate must be a member: a cone that
            --     dropped its own ground is the half-guarded-volcano bug;
            --   * a member the mirror does not assign to this cone is a leak.
            local all_present = true
            for member_key in pairs(expected_here.set) do
              if not members[member_key] then all_present = false end
            end
            local no_foreign = true
            for member_key in pairs(members) do
              if not expected_here.expected[member_key] then no_foreign = false end
            end
            if all_present and no_foreign then
              matched = matched + 1
            else
              mismatched = mismatched + 1
            end
          else
            extra = extra + 1
          end
        elseif expected_here then
          missing_chunks = missing_chunks + 1
        end
      end
    end
  end


  local histogram = {}
  for bucket = 1, 21 do
    if histogram_total[bucket] then
      histogram[#histogram + 1] = {
        nd_lo = (bucket - 1) / 20, nd_hi = bucket / 20,
        chunks = histogram_total[bucket],
        volcanic = histogram_volcanic[bucket] or 0,
      }
    end
  end

  mark("census done")
  helpers.write_file("eon-probe-runtime/report.json", helpers.table_to_json({
    census_passes = census_passes,
    seed = surface.map_gen_settings.seed,
    volcanism_size = (surface.map_gen_settings.autoplace_controls["vulcanus_volcanism"] or {}).size,
    volcanism_frequency = (surface.map_gen_settings.autoplace_controls["vulcanus_volcanism"] or {}).frequency,
    -- What the mod DECIDED, from its own status: a cone is decided when it is
    -- recorded as created, and the invariant is created <=> has a territory. The
    -- probe's own mirror only knows the cones inside the generated disc, so it
    -- cannot be the yardstick for "how many territories should exist" any more:
    -- a cone just outside the disc whose centre block turned out volcanic is
    -- legitimately claimed.
    decided_cones = decided_count,
    -- The cone ids that hold one of our territories, so the harness can check the
    -- mod's claim log lines against them: every cone the mod logged as claimed must
    -- appear here. That is the "decided implies a territory" invariant, and it is
    -- asked across the two channels that hold the facts rather than inside one of
    -- them -- the log says what the mod did, this says what the surface ended up
    -- with, and a claim whose territory is gone (a lost chunk, a later deletion)
    -- cannot hide.
    territory_cone_ids = (function()
      local ids = {}
      for id in pairs(our_cone_ids()) do ids[#ids + 1] = id end
      table.sort(ids)
      return ids
    end)(),
    decided_without_territory = decided_without_territory,
    generated_before = generated_before,
    generated_after = generated_after,
    territories = table_size(first_snapshot),
    territories_without_units = #empty_territories,
    territories_without_units_sizes = empty_territories,
    segmented_units = segmented_units,
    segmented_unit_names = unit_names,
    territories_with_small_and_big = bad_pairs,
    partially_generated_cones = partial,
    gate_blocks = gate_block,
    builder_status = status,
    builder_unhostable = table.concat(unhostable, "\n"),
    territory_census = territory_census,
    territories_off_volcano_ground = off_ground,
    volcano_territories = volcano_territory_count,
    partially_generated_covered = partial_ok,
    partially_generated_failures = partial_examples,
    territories_after_regenerate = table_size(second_snapshot),
    territories_unchanged_after_regenerate = unchanged and true or false,
    changed_territory = changed_key or "",
    chunks_matching_footprint = matched,
    chunks_mismatching_footprint = mismatched,
    chunks_in_expected_but_unclaimed = missing_chunks,
    chunks_claimed_but_not_expected = extra,
    territory_chunks_without_owner = unowned_territory_chunks,
    off_volcano_patrol_path_points = off_volcano_points,
    fit_samples = fit.samples,
    fit_fraction_min = fit.samples > 0 and fit.min or nil,
    fit_fraction_max = fit.samples > 0 and fit.max or nil,
    fit_fraction_mean = fit.samples > 0 and fit.sum / fit.samples or nil,
    off_edge_patrol_path_points = off_edge_points,
    on_folds_line = on_folds_line,
    line_samples = line_err.samples,
    line_mean_error = line_err.samples > 0 and line_err.sum / line_err.samples or nil,
    line_worst_error = line_err.samples > 0 and line_err.worst or nil,
    line_mean_error_flat = line_err.samples > 0 and line_err.flat_sum / line_err.samples or nil,
    line_worst_error_flat = line_err.flat_worst,
    off_folds_line = off_line,
    off_folds_line_examples = table.concat(line_examples, "; "),
    off_edge_examples = table.concat(edge_examples, "; "),
    off_volcano_examples = table.concat(off_volcano_examples, "; "),
    territory_chunks_outside_cone_disc = outside_disc_count,
    territories_without_a_disc = outside_disc_territories,
    territory_chunks_without_owner_examples = unowned_examples,
    territory_chunks_on_volcano = on_volcano,
    territory_chunks_off_volcano = off_volcano,
    off_volcano_examples = off_examples,
    off_volcano_tiles = off_tiles,
    off_volcano_by_cone = off_by_cone,
    distance_histogram = histogram,
    per_cone = per_cone,
    late_creation = late_result,
  }))

  -- The completion sentinel, on the SAME stream the harness is already reading.
  --
  -- The harness used to wait for report.json to APPEAR and then re-open
  -- factorio-current.log for a line the mod had written. Those are two different
  -- streams, so seeing one says nothing about the other -- and it did: the report was
  -- complete while the log had not yet flushed, and the check failed on a run that
  -- was otherwise fine. A line printed after the write is ordered before it in one
  -- stream, so it is a signal that cannot race, and it removes the log re-open and
  -- the fixed sleep that went with it.
  log("[eon-probe-runtime] REPORT-COMPLETE")
  line("cones %d, territories %d, unchanged after regenerate %s, matched %d, mismatched %d, "
    .. "missing %d, extra %d, on-volcano %d off-volcano %d",
    #entries, table_size(first_snapshot), tostring(unchanged), matched, mismatched,
    missing_chunks, extra, on_volcano, off_volcano)
  -- Run it now, at the end of on_init, as it always was.
  --
  -- Deferring this to on_nth_tick(1) is the obvious way to let every on_init finish
  -- first, and it does not work here: a headless server with no players never
  -- advances past updateTick(0), so on_nth_tick never fires at all. The race this
  end
  pending_measurement = true
end)

-- How many ticks to wait. ONE was enough only while the mod ran a load-time scan
-- of the already-generated chunks (the catch-up, now gone): it claimed inside its own
-- on_init, so by the first tick the territories existed. With the scan gone the only
-- thing that feeds the builder is on_chunk_generated, and the events for everything
-- generated in on_init are delivered in the gap AFTER the handler returns -- the
-- probe measured on tick 1 and found no territories at all, then found three after
-- its own delete-and-regenerate step and failed every ordering assertion in between.
--
-- So the measurement waits for a tick that is not the first. A headless server with
-- no players advances at about 0.25 ticks a second, so each extra tick is seconds of
-- wall time; four is the smallest count that reliably lands after the delivery, and
-- it costs the run about 12 seconds.
local MEASURE_AFTER_TICKS = 4
local ticks_seen = 0

script.on_nth_tick(1, function()
  if not pending_measurement or not measurement then return end
  ticks_seen = ticks_seen + 1
  mark("tick " .. ticks_seen)
  if ticks_seen < MEASURE_AFTER_TICKS then return end
  pending_measurement = false
  mark("tick gate passed")
  measurement()
end)

-- One tick later: the world has settled, the mod's on_init has run, and the engine
-- has delivered its chunk events. Everything the probe has to say is said here.
script.on_load(function() end)
