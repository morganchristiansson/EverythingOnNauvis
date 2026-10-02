-- Dev-only: what does volcano-demolisher.lua's discover() see on THIS map?
--
-- It mirrors the discovery loop exactly (same filter, same order as the engine
-- yields it, same body length, same boundary arithmetic), so the numbers here are
-- the numbers the ladder uses. Run it beside a mod that adds a segmented unit.

local TIER_LOW, TIER_HIGH = 0.55, 0.8

local function body_length(prototype)
  local segments = prototype.segment_engine.segments
  return segments[#segments].distance_from_head
end

script.on_init(function()
  local out = {}
  local ladder = {}
  for _, prototype in pairs(prototypes.get_entity_filtered{
      { filter = "type", type = "segmented-unit" } }) do
    ladder[#ladder + 1] = prototype
  end
  for index, prototype in ipairs(ladder) do
    out[#out + 1] = string.format("%d %-24s order=%-6s segments=%3d body=%8.2f",
      index, prototype.name, prototype.order,
      #prototype.segment_engine.segments, body_length(prototype))
  end
  local count = #ladder
  local span = count > 2 and (TIER_HIGH - TIER_LOW) / (count - 2) or 0
  out[#out + 1] = string.format("boundaries (%d tiers):", count)
  for tier = 1, count - 1 do
    out[#out + 1] = string.format("  tier %d takes size_fraction >= %.4f", tier + 1,
      TIER_LOW + span * (tier - 1))
  end
  -- The contract discover() enforces: engine order ascends by body length.
  for tier = 2, count do
    local shorter, longer = ladder[tier - 1], ladder[tier]
    out[#out + 1] = string.format("order check %d: %s", tier,
      body_length(longer) > body_length(shorter) and "OK" or "VIOLATION")
  end
  helpers.write_file("eon-probe-ladder/ladder.txt", table.concat(out, "\n"))
  log("PROBE-LADDER done")
end)

script.on_load(function() end)
