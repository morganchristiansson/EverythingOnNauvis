-- Runtime volcano territories: turn the spot mirror's answer into
-- surface.create_territory calls.
--
-- control.lua requires this; the mirror itself (noise-mirror/) never touches
-- Factorio and is tested without it.
--
-- FOUR RULES, and no state beyond one marker table:
--
--   * WHO OWNS A CHUNK is decided from two or three cones, every time it is
--     asked: the nearest centre among those whose disc covers the chunk, measured
--     at the DISPLACED point because that is where the engine reads the field.
--     Nothing is materialised to answer it and nothing is kept.
--   * A cone is decided when a chunk of ITS OWN is generated -- never earlier,
--     never on a guess about the world. A cone cut in two (volcano-split.lua) is
--     decided slice by slice, each by a chunk of its OWN, because each is its own
--     territory and the engine's one precondition is per territory.
--   * A cone's share is enumerated once, at the moment its territory is made,
--     because create_territory takes a list.
--   * Existence is COMPUTED, not discovered: a spot_noise places a cone only
--     where the candidate's density is positive, and that expression
--     (volcano_area / volcanism^2 * spawn gate) is ported in
--     noise-mirror/density.lua. So nothing here asks the engine a question about
--     the map -- including whether a chunk exists.
--
-- Two of those are load-bearing in a way worth stating:
--   * Ownership being a PURE function of position is what makes the split
--     stable. Two overlapping cones yield disjoint chunk sets decided up front, so
--     whichever is created second cannot take ground from the first, and
--     generation order cannot change the answer.
--   * create_territory does NOT spawn the demolisher. It is the map generator
--     that gives a territory its segmented units; a Lua-built territory is empty
--     and "a territory with no units will not appear on player's maps", so the
--     volcano is claimed and nothing walks on it. Builder:create places the units
--     itself (create_segmented_unit), which is also what makes the SIZE ours to
--     choose instead of the engine's per-territory sample.
--
-- Ungenerated chunks go into the territory anyway -- create_territory accepts them
-- and they join on arrival -- so a claim is never held back for a frontier.
--
-- FIVE RULES, and no state beyond one marker table:

local cones = require("noise-mirror.volcano-cones")
local Demolisher = require("volcano-demolisher")
local Split = require("volcano-split")

--- Every question about the ground a chunk stands on is asked at its MIDDLE. A
--- corner sample is a biased view of a 32x32 chunk, and the engine's own index does
--- sample the corner -- which is why a claim made on corners sits about half a chunk
--- down-right of the volcano it is meant to cover.
local Builder = {}
Builder.__index = Builder

--- Record a BUG, in the log.
---
--- Logged, never raised: this runs per chunk, and an error() here would take a long
--- game down the moment a new chunk revealed one awkward cone. The harness greps the
--- stream for this marker and fails on one.
function Builder:defect(message)
  log("[eon] DEFECT " .. message)
end

function Builder.new(surface, options)
  options = options or {}
  -- The mirror context comes from the CALLER as plain values
  -- (options.map_gen_settings), never by reading the surface: everything the
  -- builder READS is ordinary Lua tables, and only its writes (create_territory,
  -- create_segmented_unit) touch the surface -- so a test or bench can stand the
  -- decision path up with a plain settings table and nothing that looks like an
  -- engine object.
  local settings = options.map_gen_settings or {}
  local controls = (settings.autoplace_controls or {})["vulcanus_volcanism"] or {}
  local volcanoes = cones.new_volcanoes(cones.new_context{
    seed = settings.seed or 1,
    volcanism_size = controls.size or 1,
    volcanism_frequency = controls.frequency or 1,
    starting_x = 0, starting_y = 0,
  })
  local builder = setmetatable({
    surface = surface,
    volcanoes = volcanoes,
    created = options.created or {},
    -- The plan of a cone that is not fully claimed yet (volcano-split.lua). It is a
    -- pure function of the map, so it cannot go stale; it is here because a slice
    -- waiting for its own chunk is asked again on the next event that carries one,
    -- and re-cutting the claim for that is a couple of patrol circles each time.
    plans = {},
  }, Builder)
  -- The ladder, once per game, and a hard failure if a prototype cannot support a
  -- guard. It is a property of the PROTOTYPES, so it does not vary by surface.
  Demolisher.discover()
  return builder
end

--- Is this cone's answer final? `true` and `"empty"` are; nil and `"unseen"` are
--- not, and a cone in either of those is asked again by the next chunk event that
--- carries one of its own. A cone cut in two carries one marker per slice, and it
--- is decided when BOTH are.
function Builder:decided(cone)
  local state = self.created[cone.id]
  if type(state) == "table" then
    for _, slice in ipairs(state) do
      if slice == nil or slice == "unseen" then return false end
    end
    return true
  end
  return state ~= nil and state ~= "unseen"
end

--- The one or two pieces this cone's claim is made of, cut once and kept until
--- every slice is claimed (see Builder.new on `plans`).
function Builder:plan(cone, share, contenders)
  local cached = self.plans[cone.id]
  if cached then return cached end
  local slices = Split.slices(self.volcanoes, cone, share, contenders)
  if slices.unsplit_reason then
    log(string.format("[eon] volcano %s: one territory, %s", cone.id, slices.unsplit_reason))
  end
  self.plans[cone.id] = slices
  return slices
end

--- ONE demolisher per territory, deliberately. Every unit in a territory follows the
--- SAME patrol path, so two of them walk into each other -- observed live on a big
--- cone, three demolishers stacked on one path. LuaTerritory::set_patrol_path is per
--- territory, so a second unit would have to be a second territory. Which is what
--- the cut is FOR: two territories, two paths, two guards.
---
--- @return true if a territory was created
function Builder:create(cone, position)
  if self:decided(cone) then return false end
  -- The plan cache first: the share and contender list are a PURE function of the
  -- cone, and the slices inside the cache carry them -- so a cone that was cut but
  -- is still waiting for its other slice must not re-enumerate its share on every
  -- chunk event in reach (the share is the expensive part: cone_chunks is ~3-8 ms on
  -- big cones). Only a cone never seen before pays the enumeration, once.
  local slices = self.plans[cone.id]
  if not slices then
    -- The owner test has already run, so create_territory's "at least one generated
    -- chunk" is satisfied by construction: the chunk that woke us is generated, and
    -- it is one of this cone's. Nothing is re-tested here.
    --
    -- These candidates are for the SHARE, not for the owner: the split must see
    -- every cone that overlaps this one, not only those that reach this chunk.
    local contenders = self.volcanoes:contenders_for(cone)
    local share = self.volcanoes:cone_chunks(cone, contenders)
    if #share == 0 then
      -- An EMPTY share: a cone whose whole disc is won by neighbours. Recording it is
      -- correct -- the split is a pure function of the map, so it can never gain a
      -- chunk later -- but it must never be SILENT, because a bug in the split looks
      -- exactly like this from the outside.
      self.created[cone.id] = "empty"
      log(string.format("[eon] volcano %s: no chunks of its own (every chunk of its disc "
        .. "is won by a neighbouring cone) -- centre %.0f,%.0f width %.0f",
        cone.id, cone.x, cone.y, cone.width))
      return
    end
    slices = self:plan(cone, share, contenders)
  end

  -- The CLAIM is the mirror's answer and nothing else. We do not second-guess it by
  -- asking whether a guard would fit: mapgen placed this volcano, and a volcano with
  -- no patrol path yet is still a volcano.
  --
  -- ONE OR TWO slices (volcano-split.lua), and the cut does not change any of that:
  -- the same disc, the same answer about who owns what, and the same log line
  -- whether it ends up as one territory or two.
  local previous, states, made = self.created[cone.id], {}, 0
  for index, slice in ipairs(slices) do
    -- The marker this slice already has, if the cone has been here before: a cone is
    -- asked again for the slice that was still waiting, and the one that was already
    -- claimed must not be re-decided (which would claim nothing, and lose its state).
    local settled
    if type(previous) == "table" then settled = previous[index]
    elseif index == 1 then settled = previous end
    if settled ~= nil and settled ~= "unseen" then
      states[index] = settled
    -- The engine's ONE precondition on create_territory is a generated chunk in the
    -- list, and the chunk that woke us is generated -- so a slice holding it can be
    -- created now, and one that does not is asked again by the next event that
    -- carries a chunk of its own. Which slice a chunk belongs to is a question about
    -- the MAP and about the cut, and both are ours: no is_chunk_generated anywhere.
    elseif position and not Split.holds(slice, position.x, position.y) then
      states[index] = "unseen"
    else
      self:claim(cone, slice, index, #slices)
      states[index] = true
      made = made + 1
    end
  end
  -- What goes into the persistent set is a marker, not a LuaTerritory (which is not
  -- serialisable): "true" = claimed, "empty" = every chunk of its disc belongs to a
  -- neighbour, "unseen" = none of its own chunks has arrived yet, and a LIST of
  -- those when the cone was cut in two. After a load this is all that is needed to
  -- avoid creating or re-creating anything: the markers persist in storage.
  self.created[cone.id] = #slices == 1 and states[1] or states
  if self:decided(cone) then self.plans[cone.id] = nil end
  return made > 0
end

--- Build the territory of ONE slice: its chunks, its patrol path and its guard.
---
--- Everything here is per slice, because everything here is per territory -- one
--- path, one unit, one claim line -- and a split volcano has two of each.
function Builder:claim(cone, slice, index, total)
  local surface = self.surface
  -- The patrol path is ours, from the cone geometry -- see Demolisher.patrol_path.
  -- ONE name, and it is the engine's: the same list is what create_territory takes,
  -- what the guard's body is laid along (body_nodes) and what the unit then walks. It
  -- is NOT what the class is, below: a cone can have a patrol path and no body that
  -- fits it.
  local share, patrol_path = slice.share, slice.patrol_path
  local territory = surface.create_territory{ chunks = share, patrol_path = patrol_path }
  if territory == nil then
    -- A generated chunk is in the list by construction, so this is not the usual
    -- refusal: it is a defect, not a "not yet".
    self:defect(string.format(
      "%s: create_territory returned nil although a chunk is generated", cone.id))
    return
  end
  -- The patrol path and the CLASS are independent. The path still belongs to the
  -- territory -- create_territory was given it above -- and what is missing is the
  -- guard.
  local class, reason = slice.class, nil
  if patrol_path and not class then
    class = Demolisher.demolisher_for(self.volcanoes, slice.cone, patrol_path)
    if not class then
      reason = string.format("even the smallest demolisher does not fit its %d-tile patrol path",
        math.floor(Demolisher.patrol_path_length(patrol_path)))
    end
  elseif not patrol_path then
    reason = "no patrol path fits inside its " .. #share .. " claimed chunks"
  end
  local placed, names, problem = 0, "none", nil
  if patrol_path and class then
    placed, names, problem =
      Demolisher.spawn_demolishers(surface, self.volcanoes, territory, slice.cone, patrol_path, class)
  else
    -- A LOG LINE, not a defect: nothing disagrees. The mirror is right, mapgen placed a
    -- volcano, and it is too small to carry a guard -- and a defect means the mirror
    -- and the game differ. Measured unreachable on a 5x margin: the shortest patrol
    -- path anywhere across 184 cones was 340 tiles against a 59-tile need.
    --
    -- The claim stands either way: the territory was given the patrol path above, so
    -- it has our shape even with no guard on it.
    log(string.format("[eon] volcano %s: %s", cone.id, reason))
  end

  -- The guard module reports a fact; this decides what it means.
  if problem then self:defect(problem) end

  -- One line per slice, and it is the WHOLE record of the claim -- the only channel a
  -- test has, and the log a playtest is read from rather than guessed at. The silent
  -- version of this path is indistinguishable from a broken one.
  --
  -- Nothing it prints can be nil: it runs per chunk, where one bad argument is a
  -- non-recoverable error rather than a missing log line. The density is the engine's
  -- own existence verdict (positive = the map really placed this cone), 0.05 ms.
  --
  -- The split is in the line because it is the one thing a playtest cannot see from
  -- the map: a volcano carrying two guards is the point of the feature, and the log
  -- is where "this one was left whole, and why" is answered.
  local placed_count = tonumber(placed) or 0
  local placed_names = tostring(names or "none")
  if total > 1 then
    log(string.format("[eon] volcano %s: centre %.0f,%.0f width %.0f slice %d/%d (%.2f of "
      .. "the claim) -> territory of %d chunks, patrol %d points, demolishers %d [%s] "
      .. "density %+.4f", cone.id, cone.x, cone.y, cone.width, index, total, slice.fraction,
      #share, patrol_path and #patrol_path or 0, placed_count, placed_names,
      cones.cone_density(self.volcanoes.context, cone.x, cone.y)))
  else
    log(string.format("[eon] volcano %s: centre %.0f,%.0f width %.0f -> territory of %d "
      .. "chunks, patrol %d points, demolishers %d [%s] density %+.4f", cone.id, cone.x,
      cone.y, cone.width, #share, patrol_path and #patrol_path or 0, placed_count,
      placed_names, cones.cone_density(self.volcanoes.context, cone.x, cone.y)))
  end
end


--- A chunk arrived. Give it to the cone that owns it, if that cone is still waiting
--- for one.
---
--- One hash hit for the candidate ring (`Volcanoes.rings`, memoised per region), then
--- ONE wobble evaluation and a distance test per cone. Nothing is cached beyond that
--- memo and nothing is stored about the answer: the owner is recomputed every time,
--- because it is two or three distance tests and there is nothing to keep. The share
--- is enumerated separately, once, when the territory is made.
function Builder:on_chunk_generated(position)
  -- Short-circuit first: a chunk already held by one of OUR territories needs
  -- nothing from the mirror. Safe because the surface here only holds territories
  -- this mod created (the engine's expression index is off on the merged map), and
  -- a created territory always carries the decided marker -- so a non-nil answer is
  -- "this cone is decided", which is exactly what the mirror lookup and the marker
  -- check below would conclude at ~13 us of cost. A nil answer falls through to the
  -- mirror, so the worst case is today's behaviour: this can only skip, never act
  -- wrongly.
  if self.surface.get_territory_for_chunk(position) then return 0 end
  local owner = self.volcanoes:claim_owner_at(position.x, position.y)
  if owner == nil then return 0 end
  return self:create(owner, position) and 1 or 0
end

return Builder
