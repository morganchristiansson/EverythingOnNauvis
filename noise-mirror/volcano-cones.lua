-- Which EoN volcano cone owns a chunk, and how wide is that cone?
--
-- This is the whole runtime answer, and it is small on purpose: a territory is
-- built from chunk POSITIONS, so the only things worth reproducing are the
-- cone's identity, its centre and its effective width. Everything else about
-- the engine's `spot_noise` is either the identity on EoN's configuration or
-- is not needed to place chunks.
--
--   1. Centre. eon_volcano_spots_at is a `spot_noise` with
--      candidate_spot_count = 1, so each region holds at most one cone and its
--      centre is the first candidate of that region's taus88 stream -- pure
--      integer arithmetic, no noise, exact.
--   2. Existence. The engine suppresses a region whose spot density is not
--      positive, which is a chain of 5-octave biome noises. Re-deriving that
--      chain buys nothing: the game has ALREADY rendered the answer as tiles
--      (a cone that exists is a cone whose ground is volcanic), so the caller
--      injects a gate -- one tile read at the cone's centre. That keeps
--      territories on real volcano ground, which is the point, without porting
--      the biome noise. See new_volcanoes.
--   3. Width. The engine's effective radius, min(maximum_spot_basement_radius,
--      spot_radius_expression), which is a constant times eon_volcano_size_dist
--      evaluated at the centre -- ONE small multioctave per cone, and only once
--      per region because the result is cached.
--
-- Ownership is the engine's own rule for overlapping cones: the volcanoes is
-- MAX-of-cones over a zero basement, and EoN keeps quantity = radius-squared,
-- so every cone peaks at 3/pi and the winner is simply the cone with the
-- smallest normalised distance d/width. A cone owns a position exactly while
-- d <= width, which makes the owned chunk set CLOSED by construction: it can be
-- handed to surface.create_territory in one call, with no waiting for further
-- chunks and no re-creation.
--
-- Deliberately not mirrored, and why:
--   * the per-tile volcanoes rendering, including the spot-deployment warp
--     (eon_detail_noise_at on the query, up to ~25 tiles). A territory is a
--     chunk-quantised disc, and tests/spot_mirror_parity.py measures what
--     dropping it costs: ~1-3% of chunks change owner, always within one
--     chunk of a cone's rim.
--   * the biome noise, starting spots, lava/tile ranges, resource placement.
--   * the spot-selection phases that are the identity at count = 1 (skip sets,
--     the favorability sort, the trim, the hard-target cone shrink).
local candidates = require("noise-mirror.spot-candidates")
local multioctave = require("noise-mirror.noise-primitives")
local density = require("noise-mirror.density")
-- The volcano expressions' numbers, shared with the data stage that builds the
-- same expressions (map-generation/terrain.lua) -- one edit instead of two.
local VC = require("volcano-constants")

local sqrt, min, floor = math.sqrt, math.min, math.floor
-- math.log2 exists in Factorio's Lua 5.2 but not in 5.3+, so it is spelled out.
local function log2(value) return math.log(value, 2) end

local M = {}

-- The single spot system of eon_mountain_volcano_spots.
--
-- It used to be two streams merged with max() -- a dense small-seed one
-- (spacing 1.0, size 0.75) and a sparse big-seed one (spacing 1.8, size 1.25) --
-- to "merge into varied volcano sizes". Two streams cannot do that safely: each
-- has its own candidate placement and its own
-- suggested_minimum_candidate_point_spacing, and nothing coordinates them, so a
-- big and a small cone land on the same spot. Measured on the user's map (seed
-- 1096463296, frequency 6, 113 cones): the closest pair sat 64 tiles apart with
-- radii of 192 and 134, and 11 of 6328 pairs were closer than half their
-- combined reach -- almost all of them one small and one big, which is the
-- signature of two independent streams colliding.
--
-- Size does not need the second stream. volcano_spot_size is already
-- radius * size_mult * eon_volcano_size_dist, and size_dist varies continuously
-- per candidate, so ONE stream already places cones of different sizes. What the
-- pair bought was two discrete classes, at the price of a collision class that
-- the mirror had to split at runtime.
--
-- seed1 still discriminates the stream, so a cone identity is
-- (system, region_x, region_y) -- stable for a map seed.
local SYSTEMS = {
  { seed1 = 1, spacing_mult = 1.0, size_mult = 1.3, name = "volcano" },
}
M.SYSTEMS = SYSTEMS
--- PUBLISHED because callers need to enumerate candidates themselves:
--- tests/density_parity.py walks every region's first accepted draw, to ask the gate
--- about every centre the map could place one. There is ONE stream (see above); the
--- loops over `systems` are what would carry a second.

--- The fraction of a cone's effective width that a territory claims: the cone's
--- own inner disc, which is where the volcano's ground is.
---
--- Measured on real maps, by the tile at each chunk's CENTRE against the distance
--- from the cone centre, over 1197 chunks at 200% volcanism and 1337 at 600%
--- (noise-mirror histograms over live servers, both at the edge to the same
--- hundredth):
---
---     d/width          200%          600%
---     0.125 - 0.400    100%          100%
---     0.400 - 0.425     98%           87%
---     0.425 - 0.450     36%           32%
---     0.450 - 0.475      8%            4%
---     0.475 and over     0%            0%
---
--- The ground ends at d/width ~= 0.42 AT EVERY DENSITY, so this is one constant
--- and not a function of the volcanism slider. An earlier version shrank it with
--- density (0.30 at 600%), on the strength of a measurement taken while the claim
--- path still had the tile gate and a corner-sample bias in it; it was wrong, and
--- it left a ring of real volcano ground unpatrolled at high volcanism -- the
--- "incomplete territory" that started this.
---
--- 0.42 is the middle of the last band that is still (almost) all volcano, so the
--- claim is the volcano with the ragged edge included and nothing beyond it.
local CORE_FRACTION = 0.42
M.CORE_FRACTION = CORE_FRACTION

--- `slider_rescale{slider_value, n}` -- the game's own exponential rescale,
--- written with its log2/2^ so it is exact rather than algebraic.
local function slider_rescale(value, n)
  if value <= 0 then return 0 end
  return 2 ^ (log2(value) / log2(6) * log2(n))
end

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

--- The map-level inputs. options:
---   seed, volcanism_size, volcanism_frequency, starting_x, starting_y
function M.new_context(options)
  local seed = options.seed or 0
  local size = options.volcanism_size or 1
  local frequency = options.volcanism_frequency or 1
  local ctx = {
    seed = seed,
    size = size,
    frequency = frequency,
    starting_x = options.starting_x or 0,
    starting_y = options.starting_y or 0,
    -- EoN's starting radius: eon_starting_radius = 0.7 * 0.75.
    starting_radius = options.starting_radius
      or (VC.starting_radius.base * VC.starting_radius.size),
  }
  -- eon_volcanism: cone SIZE only. The frequency slider drives cone DENSITY
  -- alone (see region_size) -- the EoN changelog's "decoupled" fix.
  ctx.volcanism = VC.volcanism.base
    + VC.volcanism.span * slider_rescale(size, VC.volcanism.slider_base)
  -- volcano_spot_radius = 300 * volcanism * sqrt(1 + size slider)
  ctx.spot_radius = VC.spot_radius.scale * ctx.volcanism * sqrt(1 + size)
  -- density -> region size: 256 * 3.5 / sqrt(frequency). The game truncates the
  -- region size to an integer, so the mirror does too.
  ctx.region_size = floor(VC.density.region_edge * VC.density.divisor / sqrt(frequency))
  -- The claim radius, on the context so it is visible in a status line.
  ctx.core_fraction = CORE_FRACTION
  -- eon_volcano_size_dist's size noise (3 octaves), prepared once: building a
  -- prepared instance runs four 256-entry shuffles, so this is the difference
  -- between microseconds and milliseconds per cone.
  -- The wobble octaves, PREPARED once like everything else that costs a region
  -- walk: three multioctave instances whose only job is to displace a query point.
  -- See VC.wobble for why the input scales are 0.16/0.04/0.01 and not 8/2/0.5.
  ctx.wobble_octaves = {}
  for _, octave in ipairs(VC.wobble.octaves_list) do
    -- Two per row: the x and y terms are separate seeds, so separate streams.
    ctx.wobble_octaves[#ctx.wobble_octaves + 1] = multioctave.get({
      seed0 = seed, seed1 = octave.seed1_x + 12243, octaves = VC.wobble.octaves,
      persistence = VC.wobble.persistence,
      input_scale = octave.input_scale, output_scale = octave.output_scale,
    })
    ctx.wobble_octaves[#ctx.wobble_octaves + 1] = multioctave.get({
      seed0 = seed, seed1 = octave.seed1_y + 12243, octaves = VC.wobble.octaves,
      persistence = VC.wobble.persistence,
      input_scale = octave.input_scale, output_scale = octave.output_scale,
    })
  end
  ctx.size_noise = multioctave.get({
    seed0 = seed, seed1 = VC.size_dist.noise.seed1, octaves = VC.size_dist.noise.octaves,
    persistence = VC.size_dist.noise.persistence,
    input_scale = 1 / VC.size_dist.noise.input_scale_divisor,
    output_scale = VC.size_dist.noise.output_scale,
  })
  -- Existence is the ENGINE's density at the cone's centre, not a question asked
  -- of the rendered tiles: a spot_noise places a cone only where the candidate's
  -- density is positive, and that expression (volcano_area / volcanism^2 * spawn
  -- gate) is ported in noise-mirror/density.lua. Chunks are generated ONE AT A TIME,
  -- so no per-chunk or per-tile test can answer "is this a volcano" -- that is why
  -- the territory used to appear late, disappear when more ground was revealed, and
  -- then need an audit to be taken back.
  ctx.biome = density.new(seed, frequency, ctx.starting_x, ctx.starting_y)
  return ctx
end

--- eon_volcano_spawn_gate: 0 near spawn, 1 beyond 425 * starting radius. It
--- throttles candidate DENSITY upstream, so with a tile gate it never has to be
--- applied to a cone that exists.
function M.spawn_gate(ctx, x, y)
  local radius = VC.spawn_gate.radius_starts * ctx.starting_radius
  local dx, dy = x - ctx.starting_x, y - ctx.starting_y
  return clamp((sqrt(dx * dx + dy * dy) - radius) / radius, 0, 1)
end

--- eon_volcano_size_dist at a position: the distance ramp, the smooth size
--- noise, and the spawn gate, capped at 1.
function M.size_dist(ctx, x, y)
  local dx, dy = x - ctx.starting_x, y - ctx.starting_y
  local distance = sqrt(dx * dx + dy * dy)
  local ramp = VC.size_dist.ramp_near
    + VC.size_dist.ramp_slope * min(distance / VC.size_dist.ramp_distance, 1)
  local noise = clamp(0.5 + 0.5 * ctx.size_noise:eval(x, y), 0, 1)
  return min(ramp
    * (VC.size_dist.noise_near + VC.size_dist.noise_span * noise)
    * (VC.size_dist.gate_near + VC.size_dist.gate_span * M.spawn_gate(ctx, x, y)),
    VC.size_dist.cap)
end

--- The wobble: where the engine thinks this point's coordinates really are.
---
--- spot_noise is evaluated at (x + wobble_x, y + wobble_y), so the volcanoes at a
--- world position is the UNDISPLACED cone evaluated at the displaced one. The
--- cone's own profile is a plain linear falloff with no noise in it -- every bit
--- of the roughness at a volcano's edge comes from here, and that is the whole
--- reason a ground edge measured 53 to 87 tiles from the centre of a cone whose
--- claim radius was 67.
---
--- This is what the patrol route and, eventually, the claim need: a point is on
--- volcanic ground when the ground expression is positive at its DISPLACED
--- position, so a route radius has to be solved against the displaced volcanoes
--- rather than the clean one.
function M.wobble(context, x, y)
  local dx, dy = 0, 0
  for index, octave in ipairs(VC.wobble.octaves_list) do
    -- Interleaved x, y: the y stream is not the x stream, so this is two
    -- independent accumulators over the SAME point.
    dx = dx + context.wobble_octaves[index * 2 - 1]:eval(x, y) / octave.divisor
    dy = dy + context.wobble_octaves[index * 2]:eval(x, y) / octave.divisor
  end
  return dx, dy
end

--- THE VOLCANOES of one surface: every cone mapgen would place here, and the
--- answers about them.
---
--- It is the CONTEXT (the map's numbers -- seed, volcanism, the spot radius, the region
--- grid, the prepared noise) plus the resolved per-stream geometry plus a memo of what
--- has been derived. It holds no answer about the world the engine has not already
--- given it: existence is the engine's own density expression, ported, so every
--- question here is a pure function of position and a seed.
---
--- What it is FOR, and why it is not a cache of anything else:
---   * which cones can reach a chunk         nearby_cones, memoised per region
---   * which of them owns it                 claim_owner_at -- the nearest centre among
---                                            those whose ground covers the chunk
---   * which of them must agree with each other contenders_for
---   * what one cone's share is               cone_chunks
---

local Volcanoes = {}
Volcanoes.__index = Volcanoes

function M.new_volcanoes(context)
  local self = setmetatable({ context = context, regions = {}, rings = {} },
    Volcanoes)
  for _, system in ipairs(SYSTEMS) do
    system.region_size = context.region_size
    system.spacing = VC.spot_spacing.scale * context.volcanism * system.spacing_mult
    -- maximum_spot_basement_radius = volcano_spot_radius * size_mult
    system.basement = context.spot_radius * system.size_mult
  end
  self.systems = SYSTEMS
  return self
end

--- How many regions around a point a cone of this system can reach: a cone's
--- disc is at most `basement` wide, and regions are centred, so
--- floor(basement / region_size) + 1 rings is exact.

--- Build a cone object around a candidate centre.
--- The engine's effective radius is min(maximum_spot_basement_radius,
--- spot_radius_expression). EoN's radius expression is volcano_spot_radius *
--- size_mult * eon_volcano_size_dist and eon_volcano_size_dist <= 1, so the cap
--- never binds and the effective WIDTH is the radius expression itself.
local function make_cone(volcanoes, system, centre, region_x, region_y)
  local width = system.basement * M.size_dist(volcanoes.context, centre.x, centre.y)
  return {
    -- The prefix is the STREAM, not the display label: `system.name` is a label
    -- each side picks for itself (the parity harness used to call this one "small"
    -- or "big"), and two independently chosen labels made every cone look like a
    -- different cone. seed1 is the thing that actually identifies a stream, so
    -- the id is seed1@region:region and the label stays a label.
    id = "seed" .. system.seed1 .. "@" .. region_x .. ":" .. region_y,
    system = system.name,
    seed1 = system.seed1,
    region_x = region_x,
    region_y = region_y,
    x = centre.x,
    y = centre.y,
    -- The cone's effective WIDTH, which is the engine's own effective radius:
    -- this is the quantity that says how big the volcano is.
    width = width,
    -- The radius of the part of the cone that is actually volcano ground (see
    -- CORE_FRACTION): what a territory covers.
    core_radius = width * (volcanoes.context.core_fraction or CORE_FRACTION),
    quantity = width * width,
    peak = 3 / math.pi,
  }
end

--- The cone of a region, or nil where the density gate rejects the candidate.
--- Cached on first sight, including the rejection: a region with no cone is as
--- fixed as one with, because existence is a pure function of position.
function Volcanoes:region_cone(system, region_x, region_y)
  local key = system.seed1 .. "/" .. region_x .. ":" .. region_y
  local cached = self.regions[key]
  if cached ~= nil then return cached or nil end
  local ctx = self.context
  local centre = candidates.first_accepted(ctx.seed, system.seed1, region_x, region_y,
    system.region_size)
  local cone = nil
  if centre and M.cone_density(self.context, centre.x, centre.y) > 0 then
    cone = make_cone(self, system, centre, region_x, region_y)
  end
  self.regions[key] = cone or false
  return cone
end

--- The engine's spot density at a position: volcano_area / volcanism^2 * spawn
--- gate. Positive means a cone here is really placed. Pure function of position --
--- no surface, no tiles, no revealed chunks.
function M.cone_density(context, x, y)
  local volcanism = context.volcanism
  return density.density(context.biome, x, y, volcanism, M.spawn_gate(context, x, y))
end

--- The cone of one region of one system, or nil when the region holds none.
--- Cached, including the "no cone here" answer, so a chunk lookup costs a table
--- hit per neighbouring region.
--- Every cone whose disc can reach a world position. `margin` widens the search
--- for callers that test a whole AREA rather than a point (a cone footprint):
--- a cone that reaches any point of a disc of radius `margin` around (x, y) is
--- within `basement + margin` of it.
--- `raw` settles the cone-versus-cone split WITHOUT the gate, and that is the
--- point: a gate answers "does this cone exist", and that answer arrives at a
--- different time for every cone, so a split computed against the decided cones
--- would CHANGE as more of them resolve -- two volcanoes trading chunks back and
--- forth, and a territory that no longer matches the mirror that built it
--- (measured at 600% volcanism: 199 chunks in a territory the mirror does not
--- predict, 38 mirror-owned chunks in no territory, both from this).
--- The split is therefore computed over the cones the map WOULD have, gate or
--- not: it is fixed from the first call, disjoint, and never re-litigated. The
--- gate then only decides who gets to CREATE a territory; a cone that turns out
--- not to exist leaves a small unclaimed lens between its discs, which the
--- builder's audit refills from the surviving neighbour's disc.
function Volcanoes:nearby_cones(x, y, margin)
  -- Every chunk of a region gets the same ring of regions, and generation walks
  -- chunks next to each other, so the ring scan is cached per (region, margin).
  -- Existence is a pure function of position, so a ring never changes and is
  -- cached for the life of the field.
  local region_x = candidates.region_index(x, self.systems[1].region_size)
  local region_y = candidates.region_index(y, self.systems[1].region_size)
  local key = region_x .. ":" .. region_y .. ":" .. (margin or 0)
  local cached = self.rings[key]
  if cached then return cached end
  local found, count = {}, 0
  for _, system in ipairs(self.systems) do
    local base_x = candidates.region_index(x, system.region_size)
    local base_y = candidates.region_index(y, system.region_size)
    local rings = floor((system.basement + (margin or 0)) / system.region_size) + 1
    for dy = -rings, rings do
      for dx = -rings, rings do
        local cone = self:region_cone(system, base_x + dx, base_y + dy)
        if cone then
          count = count + 1
          found[count] = cone
        end
      end
    end
  end
  found.n = count
  self.rings[key] = found
  return found
end

--- The winning cone among `cones` for a position: the engine's MAX-of-cones
--- rule. EoN keeps quantity = radius-squared, so every cone peaks at 3/pi and
--- the winner is the cone with the smallest normalised distance d/width.
--- Strict `<` keeps the FIRST cone on a tie: the order the engine walks its spot
--- list in within a region, and the order the systems are declared in (small
--- before big).
--- The cone that owns a point, by the engine's rule: the highest value, which is
--- the smallest d/width. Called with DISPLACEMENT ALREADY APPLIED (owner_at does
--- it), so x, y here are FIELD coordinates, not world ones.
---
--- `fraction` is the radius, as a fraction of the cone's width, and the two
--- callers want DIFFERENT ones, which is why it is a parameter and not baked in:
---
---   owner_at   VOLCANIC_EDGE_FRACTION   who owns this chunk -- the terrain disc,
---                                        the same radius cone_chunks tests, so the
---                                        two cannot disagree
---   cone_value 1.0                      the volcanoes itself, which is positive out to
---                                        the cone's full width. Using the terrain
---                                        radius here returned 0 everywhere outside
---                                        it, and the volcanoes parity caught it.
local function best_cone(cones, x, y, fraction)
  local best, best_normalised = nil, nil
  for i = 1, cones.n do
    local cone = cones[i]
    local dx, dy = x - cone.x, y - cone.y
    local distance = sqrt(dx * dx + dy * dy)
    if distance <= fraction * cone.width then
      local normalised = distance / cone.width
      if best == nil or normalised < best_normalised then
        best, best_normalised = cone, normalised
      end
    end
  end
  if not best then return nil end
  return best, best_normalised
end

--- The cone that owns a world position, its effective width, and the volcanoes value
--- there (0 outside every cone, 3/pi at a centre).
function Volcanoes:owner_at(x, y)
  -- Read the volcanoes where the engine reads it: at the displaced point.
  local wx, wy = M.wobble(self.context, x, y)
  local cone, normalised = best_cone(self:nearby_cones(x, y), x + wx, y + wy,
    VC.VOLCANIC_EDGE_FRACTION)
  if not cone then return nil, 0, 0 end
  return cone, cone.width, cone.peak * (1 - normalised)
end

--- The engine's cone volcanoes at a world point: the value spot_noise returns.
---
--- The arithmetic collapses. The engine renders each cone as a linear falloff:
---     peak  = 3 * quantity / (pi * radius^2)
---     slope = peak / radius
---     cone  = peak - d * slope
--- and the quantity expression is `volcano_spot_size^2` -- deliberately, so that
--- the peak is the SAME for every cone size and the volcanoes does not change height
--- with the size slider. So quantity/radius^2 cancels and the whole cone is
---     (3/pi) * (1 - d / width)
--- over the cone's width, which is the engine's own effective radius
--- (minimum_spot_basement_radius, spot_radius_expression).
---
--- Spot_noise takes the MAX over the spots in range, not the sum, so a point
--- between two cones reads as the nearer one. The displacement is applied to the
--- QUERY (see M.wobble), not to the cone, which is why the wobble has to be here
--- rather than folded into the width: the volcanoes at p is the clean cone at p + w.
--- NOT called by the runtime either, and for the same reason: this is the engine's
--- volcanoes, kept in the mirror because FOLDS_LINE_FRACTION and
--- VOLCANIC_EDGE_FRACTION are derived from exactly the formula below, so the
--- constant and its justification sit in one file. tests/field_parity.py gates it
--- against the shipped expression to 1.4e-6.
function Volcanoes:cone_value(x, y)
  local wx, wy = M.wobble(self.context, x, y)
  local sx, sy = x + wx, y + wy
  -- best_cone picks the smallest d/width, which IS the max of (1 - d/width), so
  -- this is the engine's "max over the spots in range" without a second loop.
  local cone, normalised = best_cone(self:nearby_cones(sx, sy), sx, sy, 1.0)
  if not cone or normalised >= 1 then return 0 end
  return cone.peak * (1 - normalised)
end


--- The chunk-grid sample point, and the one deliberate departure from the
--- engine's own convention.
---
--- The engine samples a territory index at each chunk's top-left CORNER. The
--- runtime claim does not, and this is the reason: a chunk whose CORNER is
--- inside the disc is a chunk whose AREE lies up to a full chunk SE of it, so
--- the claimed union sits about half a chunk (+16/+16px) down-right of the
--- volcano it is supposed to cover -- still true after the "_at16" compensation
--- fields were deleted, because no volcanoes shift can fix a quantisation bias (a
--- shifted mask just moves the bias to a different constant). Testing the
-- chunk's CENTRE makes the claimed area coincide with the disc, and it is also
--- the more honest question: "is this chunk on the volcano" is a question about
--- the middle of the chunk, not about one corner tile of it.
--
--- The world position the mirror samples a chunk at: its CENTRE. Every caller
--- wants the centre, so this carries no parameter -- the corner convention the
--- parity harness needs is the caller's own `chunk * 32`.
local function chunk_point(chunk_x, chunk_y)
  return chunk_x * 32 + 16, chunk_y * 32 + 16
end

--- The cone that owns this chunk, sampled at its centre (see chunk_point).
--- Which cone's FIELD is highest at a point, out to the cone's full width.
---
--- NOT called by the runtime, and deliberately so: this answers the engine's
--- question (the volcanoes), not the claim's (the terrain). It exists so
--- tests/spot_mirror_parity.py can compare against the engine's own volcanoes answer
--- rather than against the claim, which is a narrower thing.
--- The cone whose FIELD this point is in, out to its whole width -- not its terrain
--- disc, which is what owner_at stops at. The two are different questions and
--- `cone_value` is neither: it returns the field's VALUE (a number), not the cone.
function Volcanoes:field_owner_at(x, y)
  local wx, wy = M.wobble(self.context, x, y)
  return best_cone(self:nearby_cones(x, y), x + wx, y + wy, 1.0)
end

function Volcanoes:chunk_owner(chunk_x, chunk_y)
  return self:owner_at(chunk_point(chunk_x, chunk_y))
end

--- The chunks this cone OWNS: every chunk whose sample corner this cone wins and
--- that lies inside its core radius (not the full cone width -- see
--- CORE_FRACTION).
---
--- This is the membership rule, whole. It is geometric: no tile is read, nothing
--- depends on what has been generated, and the set is CLOSED by construction --
--- the same distance test decides both membership and ownership, and neither
--- depends on generation order. Overlapping cones yield DISJOINT sets, which is
--- what create_territory needs -- it strips the chunks it takes from any other
--- territory.
--- The cones that can contend for a chunk of THIS cone's disc, and the winner
--- among them. One implementation on purpose: `cone_chunks` and the self test
--- used to answer "who owns this chunk" with two different contender sets (a
--- margin-0 ring here, the disc's own ring there), and the self test then failed
--- on a disagreement that was never a disagreement about the claim.
--- The cones whose CLAIM (its core disc) can reach this cone's claim. Core radii,
--- not full widths: the claim is the core, and a full width here would let a cone
--- that claims nothing near us into the argument.
---
--- The DENSITY ring, not the raw one. The raw ring lists every cone the map could
--- place, and a cone the engine does not place must not hold ground in the split:
--- it will never create a territory, so the ground it won is claimed by nobody and
--- a real volcano goes unpatrolled. Measured live (seed 3526581861, 200%): a cone
--- with density -0.39 was taking 60 chunks of genuine volcano away from its
--- neighbour, and the player's tungsten ore sat in the hole. The ring is still
--- STABLE, which is why the split can be density-decided here: existence is a pure
--- function of position, so unlike the old tile gate it cannot change later.
function Volcanoes:contenders_for(cone)
  return self:contenders_from(self:nearby_cones(cone.x, cone.y, cone.core_radius), cone)
end

--- The cones of `members` that must agree on this cone's ground: those whose core
--- disc can reach its own. The filter Volcanoes:contenders_for applies, over a list the
--- caller already has -- so the rule is written once and a caller passing its own list
--- cannot get a different answer than one that searched for it.
function Volcanoes:contenders_from(members, cone)
  local contenders, count = {}, 0
  for index = 1, #members do
    local other = members[index]
    local dx, dy = other.x - cone.x, other.y - cone.y
    if sqrt(dx * dx + dy * dy) <= other.core_radius + cone.core_radius then
      count = count + 1
      contenders[count] = other
    end
  end
  contenders.n = count
  return contenders
end

--- WHO OWNS THIS CHUNK, for a CLAIM. The whole runtime asks one question, and this is
--- it -- and it is NOT `owner_at`, which answers the engine's question instead: whose
--- TERRAIN is this world point, the field's MAX(basement 0, cone values). The two
--- disagree on purpose. The field rule is right about lava and wrong about territory,
--- because a small cone beside a big one wins a huge bite out of the middle of the big
--- one's disc (measured on a 3-series, seed 3526581861 at 200%: the big cone came out a
--- 31%-wide crescent and the middle cone got no territory at all). So the field's answer
--- is `owner_at` and the claim's is this one, and a reader who wants to know which is
--- which should not have to open both.
---
--- The ring is the candidate set and the answer is the nearest centre among the cones
--- whose ground covers the chunk. Nothing is built to answer it and nothing is kept: the
--- test is a distance and one wobble, recomputed every time, and the only memo involved
--- is the ring's own (per region), which is a cache of the candidate LIST, not of the
--- answer.
---
--- The margin is zero and was 64 for most of this file's life. It made no difference:
--- the ring's extent comes from `basement` -- a cone that covers a chunk has its centre
--- within basement + 16 tiles, comfortably inside one ring of regions -- and measured
--- over 1,681 positions at 1x and 6x volcanism, margins 0 and 64 return identical rings
--- at every one. It was belt-and-braces from when the ring also had to serve a reach
--- test.
function Volcanoes:claim_owner_at(chunk_x, chunk_y)
  -- Through LOCALS, never inlined. `chunk_point` returns two values, and Lua drops
  -- all but the first when the call is not the LAST argument -- so
  -- `nearby_cones(chunk_point(x, y), 0)` reads the ring at (x, y) with the margin in
  -- the y slot, which is a position on the other side of the map. It is in the
  -- argument list twice, and it was wrong once: the owner came back nil for chunks
  -- that demonstrably had one, and the builder test failed on two runs in five
  -- depending on which cone `pairs` handed it.
  local px, py = chunk_point(chunk_x, chunk_y)
  local ring = self:nearby_cones(px, py, 0)
  return self:claim_winner(ring, px, py)
end


--- Who owns a position, for the CLAIM rather than for the field.
---
--- The engine's volcanoes is MAX-of-cones -- smallest d/width -- and that is the right
--- answer to "which cone's lava is rendered here". It is the wrong answer to "which
--- volcano is this chunk part of", because a small cone sitting near a big cone's
--- rim wins a huge bite out of the middle of the big one's disc: MAX-of-cones
--- compares d/width, so the small cone's own centre is very close to zero while
--- the big cone's is not, and the split runs straight through the big cone.
--- Measured on a 3-series merge (seed 3526581861, 200%): the big cone came out as a
--- crescent with a 31%-wide patrol loop on it, and a middle cone came out with no
--- territory at all.
---
--- The claim is NEAREST CENTRE among the cones whose claim covers the chunk. That is
--- the perpendicular bisector between two cone centres, so:
---   * every claim still contains its own centre, and
---   * a circle of half the distance to the nearest rival centre fits inside it BY
---     CONSTRUCTION -- which is what makes a patrol loop possible at all
---     (Volcanoes:patrol_circle), with no searching and no fallback.
--- The largest the wobble can move a point, in tiles. Measured over 3,000,000 samples
--- on three seeds (12345, 987654321, 3526581861) at 1x and 6x volcanism: the largest
--- displacement was 36.7 tiles, the mean 9.8. 40 has a 9% margin, and a seed that
--- exceeded it would read a cone as not grazing a chunk it does -- a claim a tile
--- smaller at the rim, never a lost volcano.
local WOBBLE_BOUND_TILES = 40

function Volcanoes:claim_winner(contenders, x, y)
  local best, best_distance = nil, nil
  -- The split has to be decided where the FIELD is read, which is the displaced
  -- point. The wobble is a property of the position, not of the cone, so applying it
  -- here keeps every contender judged on the same ground -- and it is the same test
  -- disc_chunks uses, or a cone could win a chunk its own terrain does not reach.
  -- ONE wobble evaluation for the whole set, and a cheap distance test in front of it.
  -- The displacement cannot exceed the bound, so a contender further than `its radius +
  -- bound` cannot reach the point however the noise behaves there. That matters
  -- because the set is the ring's cones -- seven of them at 600% volcanism -- and a
  -- wobble evaluation is twelve basis_noise samples: evaluating each of them cost 87 us
  -- a chunk, and this costs 3.
  local wx, wy = M.wobble(self.context, x, y)
  local sx, sy = x + wx, y + wy
  for i = 1, contenders.n do
    local other = contenders[i]
    local radius = VC.VOLCANIC_EDGE_FRACTION * other.width
    local ax, ay = x - other.x, y - other.y
    local reach = radius + WOBBLE_BOUND_TILES
    if ax * ax + ay * ay <= reach * reach then
    local dx, dy = sx - other.x, sy - other.y
    local distance = sqrt(dx * dx + dy * dy)
    if distance <= radius then
      -- Smallest d/width, not smallest d: the cones are different sizes, and the
      -- engine's spot_noise takes the highest value, which is the smallest d/width.
      local normalised = distance / other.width
      if best_distance == nil or normalised < best_distance then
        best, best_distance = other, normalised
      end
    end
    end
  end
  return best
end

--- The chunks of a cone's core disc, optionally filtered to the ones this cone
--- WINS. One loop for both, because they differ by exactly one test and a second
--- copy of it is a second place for the disc and the ownership rule to drift --
--- and cone_chunks' own comment says the two must not disagree (it samples at the
--- same point as chunk_owner).
local function disc_chunks(self, cone, contenders, owned)
  -- The scan has to reach past the nominal disc, because the wobble can push the
  -- boundary out by ~16 tiles. A PROPORTION alone is not enough: 0.15 * width falls
  -- below 16 once width drops under ~110, so small cones would have the wobble
  -- clipped off and quietly reproduce the bug this replaced. Hence the floor.
  local reach = floor((cone.width * VC.VOLCANIC_EDGE_FRACTION
    + math.max(cone.width * 0.15, 24)) / 32) + 1
  local centre_x, centre_y = floor(cone.x / 32), floor(cone.y / 32)
  -- One cone list for the whole disc (any cone that can reach a chunk of the disc
  -- is within `basement + core_radius` of the cone's centre), then a distance test
  -- per chunk. Scanning the neighbouring regions per chunk instead costs a 25x
  -- region sweep per chunk, which is most of a territory's cost.
  local chunks = {}
  for dx = -reach, reach do
    for dy = -reach, reach do
      local cx, cy = centre_x + dx, centre_y + dy
      -- CENTRE of the chunk, like chunk_owner: the disc test and the ownership
      -- test must ask about the same point, or a cone could claim a chunk it
      -- does not own.
      local px, py = chunk_point(cx, cy)
      -- The claim is the volcano TERRAIN, in the frame the spot volcanoes is
      -- evaluated in -- which is the wobbled one. A clean disc is wrong in both
      -- directions, and the data stage's own mask
      -- (`eon_vulcanus_terrain > 0`) is a wobbled disc of the same fraction.
      local wx, wy = M.wobble(self.context, px, py)
      local ddx, ddy = (px + wx) - cone.x, (py + wy) - cone.y
      local radius = VC.VOLCANIC_EDGE_FRACTION * cone.width
      if ddx * ddx + ddy * ddy <= radius * radius then
        local keep = not owned
        if owned then
          local owner = self:claim_winner(contenders, px, py)
          keep = owner and owner.id == cone.id
        end
        if keep then
          chunks[#chunks + 1] = { x = cx, y = cy }
        end
      end
    end
  end
  return chunks
end

--- The chunks this cone OWNS: its core disc, minus everything a nearer cone won.
---
--- `contenders` is an INPUT. It used to be a ring walk inside this function, which
--- meant two independent answers to "who are my neighbours" -- this and
--- contenders_for. Callers pass a list now, through the same filter, so the rule is
--- written once.
---
--- NOT memoised: the share is enumerated once per cone, when its territory is made,
--- because create_territory takes a list. It used to be recomputed for every cone still
--- waiting, on every chunk event in reach -- 8.4 ms per chunk at 100% volcanism, 20.7
--- at 600% -- and then memoised, which the owner test made unnecessary: a cone is now
--- decided by asking whether the arriving chunk is one of its own.
function Volcanoes:cone_chunks(cone, contenders)
  return disc_chunks(self, cone, contenders, true)
end

--- Every chunk of the cone's DISC, ignoring who wins it. The territory is the
--- disc MINUS whatever a neighbour won, so this is the disc the audit refills
--- from: a chunk inside it that is generated, volcanic and in no territory is a
--- hole, whether it lost its neighbour to a gate that later said no or was simply
--- never created.
function Volcanoes:cone_disc(cone)
  return disc_chunks(self, cone, self:contenders_for(cone), false)
end

--- How big this cone is, as a fraction of the largest cone the map can hold.
---
--- The tiers downstream are the ones `eon_volcano_size_dist` was tiered with
--- (< 0.55, < 0.8), but applied to the cone's EFFECTIVE WIDTH instead of to
--- `size_dist` itself. `size_dist` is a volcanoes the player cannot see, and it says
--- nothing about the two spot systems: they differ only by `size_mult`, so at
--- size_dist 1.0 the small system is a 318px cone and the big system a 530px one
--- and BOTH read as tier "big". Measured on seed 3526581861 at 200% volcanism
--- (18 cones, widths 191..530): tiering by size_dist gives 0 small / 4 medium /
--- 14 big -- every volcano on the map gets a big demolisher -- while tiering by
--- width gives 2 small / 9 medium / 7 big, which is what the map actually looks
--- like. Normalising by the biggest basement keeps the rule meaningful when the
--- volcanism size slider changes (widths scale with it).
function Volcanoes:size_fraction(cone)
  local largest = 0
  for _, system in ipairs(self.systems) do
    if system.basement > largest then largest = system.basement end
  end
  if largest <= 0 then return 1 end
  return cone.width / largest
end

--- Every cone that could cover a chunk, seen from a chunk position.
--- A thin wrapper over nearby_cones (which caches the region ring): the margin is
--- how far outside the chunk a cone's reach may start counting.
function Volcanoes:cones_near(chunk_x, chunk_y, chunk_radius)
  return self:nearby_cones(chunk_x * 32, chunk_y * 32, (chunk_radius or 0) * 32)
end

return M
