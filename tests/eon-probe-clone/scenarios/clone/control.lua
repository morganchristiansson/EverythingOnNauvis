-- Dev-only probe: the multiplayer reset scenario pre-generates the next map on a
-- SECOND surface created at runtime, long before the nauvis planet is re-associated
-- with it (a planet can only hold one surface at a time). Two things are asked of
-- the real game:
--
--   1. does game.create_surface reproduce the merged map from the read-back of
--      nauvis's map_gen_settings? Measured live (and recorded here): YES, provided
--      the settings are passed AS the flat MapGenSettings table (not wrapped in a
--      {map_gen_settings = ...} key) and default_enable_all_autoplace_controls is
--      explicitly false. With it true -- or unset -- the game autoplaces EVERY
--      decorative prototype, including fulgoran-gravewort, whose default
--      probability references control:fulgora_islands:frequency, which this surface
--      does not define, and the compile dies. That is the real mechanism behind the
--      old AGENTS.md note that create_surface "does not honour map_gen_settings
--      tables": the call shape made the settings table empty, and the decorative
--      autoplace exploded on the way to the gravewort error.
--
--   2. does the MOD claim territories on that surface while it is still
--      UNASSOCIATED (planet == nil)? The mod gates on the surface's own settings
--      (the vulcanus_volcanism autoplace control must be present -- is_merged_map
--      in control.lua), never on the planet, deliberately: the swap-in map must be
--      fully guarded BEFORE it is associated, because a pre-generated chunk never
--      re-fires on_chunk_generated.
local cones = require("__EverythingOnNauvis-morganc__.noise-mirror.volcano-cones")
local CLONE = "eon-clone-probe"
-- Same region the e2e probe uses (seed 12345, 200% volcanism).
local CCX, CCY = -3, -26
local note = {}


local function volcanic_tile(name)
  return string.sub(name, 1, 8) == "volcanic" or name == "lava" or name == "lava-hot"
end


--- The mirror EXACTLY as control.lua builds it, from the CLONE's own settings: the
--- probe must ask for ground the mod can actually claim, and only the mirror knows
--- where that is (the plain disc around the region centre covers most of it).
local function mirror(surface)
  local controls = (surface.map_gen_settings.autoplace_controls or {})["vulcanus_volcanism"] or {}
  return cones.new_volcanoes(cones.new_context{
    seed = surface.map_gen_settings.seed,
    volcanism_size = controls.size or 1,
    volcanism_frequency = controls.frequency or 1,
  })
end


script.on_init(function()
  local ok, err = pcall(function()
    local nauvis = game.surfaces["nauvis"]
    local settings = nauvis.map_gen_settings
    -- Measured requirement -- see the header. The read-back is a plain table, and
    -- create_surface wants it as-is.
    settings.default_enable_all_autoplace_controls = false
    local clone = game.create_surface(CLONE, settings)
    note.clone_planet = tostring(clone.planet)
    note.control_present =
      (clone.map_gen_settings.autoplace_controls or {})["vulcanus_volcanism"] ~= nil
    note.cloned_seed = clone.map_gen_settings.seed
    -- Generate the CLAIMABLE ground: one request per cone the mirror predicts in
    -- reach, sized to that cone's core (the e2e pattern -- the plain disc leaves
    -- volcano-free gaps and asks for a lot of ground that can never be claimed).
    local volcanoes = mirror(clone)
    note.predicted_cones = #volcanoes:cones_near(CCX, CCY, 14)
    for _, cone in ipairs(volcanoes:cones_near(CCX, CCY, 14)) do
      local radius = math.ceil(cone.core_radius / 32) + 1
      clone.request_to_generate_chunks(
        { x = math.floor(cone.x / 32) * 32, y = math.floor(cone.y / 32) * 32 }, radius)
    end
    clone.force_generate_chunk_requests()
  end)
  if ok then
    note.surface_created = true
  else
    note.surface_created = false
    note.create_error = tostring(err):sub(1, 300)
  end
end)

-- The events for everything generated in on_init are delivered in the gaps AFTER
-- the handler returns, so the measurement waits a few ticks (auto_pause is off;
-- ~0.25 ticks/s headless, so this costs ~10 s of wall time).
local ticks = 0
script.on_nth_tick(1, function()
  ticks = ticks + 1
  if ticks < 4 then return end
  local clone = game.surfaces[CLONE]
  if clone == nil then
    note.generated_chunks = 0
  else
    -- Census over the generated chunks (chunk coords, guarded: an ungenerated
    -- chunk's get_tile raises).
    local generated, volcanic, seen = 0, 0, {}
    for _, cone in ipairs(mirror(clone):cones_near(CCX, CCY, 14)) do
      local r = math.ceil(cone.core_radius / 32) + 2
      local cx, cy = math.floor(cone.x / 32), math.floor(cone.y / 32)
      for dy = -r, r do for dx = -r, r do
        local key = (cx + dx) .. "," .. (cy + dy)
        if not seen[key] then
          seen[key] = true
          if clone.is_chunk_generated({ x = cx + dx, y = cy + dy }) then
            generated = generated + 1
            local tile = clone.get_tile((cx + dx) * 32 + 16, (cy + dy) * 32 + 16)
            if volcanic_tile(tile.name) then volcanic = volcanic + 1 end
          end
        end
      end end
    end
    note.generated_chunks = generated
    note.volcanic_chunk_centres = volcanic
    note.territories = {}
    note.sample_tiles = {}
    for _, t in ipairs(clone.get_territories()) do
      note.territories[#note.territories + 1] = {
        chunks = #t.get_chunks(), units = #t.get_segmented_units(),
      }
      -- A territory chunk can be UNGENERATED (create_territory accepts them and
      -- they join on arrival), so the tile read is guarded like the census above.
      local chunks = t.get_chunks()
      if #chunks >= 1 and clone.is_chunk_generated(chunks[1]) then
        local c = chunks[1]
        local px, py = c.x * 32 + 16, c.y * 32 + 16
        local nauvis_tile = "?"
        local nok, ne = pcall(function()
          return game.surfaces["nauvis"].get_tile(px, py).name end)
        nauvis_tile = nok and ne or "ungenerated"
        note.sample_tiles[#note.sample_tiles + 1] = {
          chunk = c.x .. "," .. c.y,
          clone = clone.get_tile(px, py).name,
          nauvis = nauvis_tile,
        }
      end
    end
  end
  helpers.write_file("eon-probe-clone/report.json", helpers.table_to_json(note))
  log("[eon-probe-clone] REPORT-COMPLETE territories=" .. #(note.territories or {}))
end)