-- Dev-only probe: does a territory OUTLIVE its demolisher?
--
-- Creates a runtime territory over a generated disc, spawns ONE segmented unit on
-- it (the way the EoN builder does), destroys that unit, then asks three
-- questions, the ones the short-circuit in on_chunk_generated depends on:
--   1. is the LuaTerritory still valid after its last unit dies?
--   2. does surface.get_territory_for_chunk still answer for its chunks?
--   3. does regenerate_segmented_units work on it (i.e. does the engine itself
--      treat it as a live-but-empty territory)?
-- The answers are written to report.json; the runner terminates the server.
--
-- Script the mod IS NOT loaded beside this probe on purpose: the questions are
-- engine facts, not mod facts, and the mod's own territory handling would just
-- claim the disc first. The lifecycle that matters is the one the conquest loop
-- exercises: territory created, guard dies, chunk events keep coming.
script.on_init(function()
  local surface = game.surfaces[1]
  surface.request_to_generate_chunks({ x = 0, y = 0 }, 2)
  surface.force_generate_chunk_requests()

  -- A disc of generated chunks to own (chunk coords; 1 chunk = 32 tiles, and the
  -- request above is in tile coords with radius in chunks).
  local chunks = {}
  for dx = -2, 2 do for dy = -2, 2 do
    chunks[#chunks + 1] = { x = dx, y = dy }
  end end

  local report = {}
  local function ask(question)
    -- territory is a HANDLE: get_territory_for_chunk and get_territories return
    -- different objects for the same territory, so the checks use .valid and the
    -- chunk keyed lookup, never identity.
    local t = surface.create_territory{ chunks = chunks }
    report.created = t ~= nil
    if not t then report[question] = "create_territory returned nil" return end
    local unit = surface.create_segmented_unit{
      name = "small-demolisher", force = "enemy", territory = t,
      position = { x = 16, y = 16 },
    }
    report.unit_spawned = unit ~= nil
    if not unit then report[question] = "create_segmented_unit returned nil" return end
    unit.destroy()
    -- After the destroy: the unit is gone, the territory may or may not be.
    report.territory_valid_after_guard_death = t.valid
    report.territory_units_after_guard_death = #t.get_segmented_units()
    local held_after, nil_after = 0, 0
    for _, chunk in ipairs(chunks) do
      if surface.get_territory_for_chunk(chunk) then held_after = held_after + 1
      else nil_after = nil_after + 1 end
    end
    report.held_after_guard_death = held_after
    report.nil_after_guard_death = nil_after
    -- And the engine's own respawn path, which only makes sense on a territory
    -- that still exists: if the territory is dead this raises.
    local ok, err = pcall(function() t.regenerate_segmented_units() end)
    report.regen_ok = ok
    report.regen_error = tostring(err)
    report.regen_units = ok and #t.get_segmented_units() or -1
  end
  ask("lifecycle")

  helpers.write_file("eon-probe-territory-lifecycle/report.json",
    helpers.table_to_json(report))
  log("[eon-probe-territory-lifecycle] REPORT-COMPLETE")
end)