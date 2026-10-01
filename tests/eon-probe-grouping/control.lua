-- Dev-only: territory GROUPING probe. Uses LuaTerritory.get_chunks() /
-- get_segmented_units() to dump, per generated chunk, its territory object id,
-- plus the size (chunk count) and demolisher names of every territory. The
-- demolisher_territory_expression and minimum_territory_size are the SHIPPED
-- ones (this mod overrides nothing) so grouping is the real layout.
local TX, TY = -80, -831
local R = 64
local CCX, CCY = math.floor(TX / 32), math.floor(TY / 32)

local function is_volcano_tile(n)
  return string.sub(n, 1, 8) == "volcanic" or n == "lava" or n == "lava-hot"
end

local function is_lava_tile(n)
  return n == "lava" or n == "lava-hot"
end

script.on_init(function()
  local surface = game.surfaces["nauvis"]
  -- Generate a generous margin outside the measured disc. get_chunks() may
  -- include territory members that are not yet generated; four extra rings
  -- keeps the finite volcano territory objects and their cardinal connections
  -- available while the report itself remains exactly radius R.
  surface.request_to_generate_chunks({ TX, TY }, R + 4)
  surface.force_generate_chunk_requests()

  -- LuaTerritory:get_chunks() can include members outside the generated area.
  -- Pull those members into the generated set before measuring the territory.
  -- Headless generation is allowed to make later requests during on_init; the
  -- bounded loop also makes a refused request visible in the final report.
  local generation_passes = 0
  local requested_members = 0
  for pass = 1, 4 do
    local requested = 0
    for cx = -R, R do
      for cy = -R, R do
        if cx * cx + cy * cy <= (R + 0.5) * (R + 0.5) then
          local chunk_position = { CCX + cx, CCY + cy }
          if surface.is_chunk_generated(chunk_position) then
            local t = surface.get_territory_for_chunk(chunk_position)
            if t and t.valid then
              for _, c in ipairs(t.get_chunks()) do
                if not surface.is_chunk_generated(c) then
                  surface.request_to_generate_chunks({ c.x * 32, c.y * 32 }, 0)
                  requested = requested + 1
                end
              end
            end
          end
        end
      end
    end
    requested_members = requested_members + requested
    generation_passes = pass
    if requested == 0 then break end
    surface.force_generate_chunk_requests()
  end

  local terr_id = {}     -- first-generated-chunk key -> territory id
  local terr_size = {}   -- id -> generated chunk count
  local terr_units = {}  -- id -> {unit names}
  local next = 0
  local chunks = {}
  local ungenerated_scanned = 0
  local ungenerated_members = 0

  local function generated_members(territory)
    local out = {}
    for _, c in ipairs(territory.get_chunks()) do
      if surface.is_chunk_generated(c) then
        out[#out + 1] = c
      else
        ungenerated_members = ungenerated_members + 1
      end
    end
    return out
  end
  for cx = -R, R do
    for cy = -R, R do
      if cx * cx + cy * cy <= (R + 0.5) * (R + 0.5) then
        local wx = (CCX + cx) * 32
        local wy = (CCY + cy) * 32
        local generated = surface.is_chunk_generated({ CCX + cx, CCY + cy })
        if not generated then ungenerated_scanned = ungenerated_scanned + 1 end
        local t = generated and surface.get_territory_for_chunk({ CCX + cx, CCY + cy }) or nil
        local tid = 0
        if t and t.valid then
          local cs = generated_members(t)
          local c0 = cs[1]
          if c0 then
            local k = c0.x .. "," .. c0.y
            tid = terr_id[k]
            if not tid then
              next = next + 1
              tid = next
              terr_id[k] = tid
              terr_size[tid] = #cs
              local us = {}
              for _, u in pairs(t.get_segmented_units()) do
                us[#us + 1] = u.prototype and u.prototype.name or u.type
              end
              terr_units[tid] = us
            end
          end
        end
        local rows = {}
        for i = 1, 8 do
          local row = {}
          for j = 1, 8 do
            local nm = surface.get_tile(wx + (j - 1) * 4, wy + (i - 1) * 4).name
            local b = 0
            if is_volcano_tile(nm) then b = b + 1 end
            if is_lava_tile(nm) then b = b + 2 end
            row[j] = b
          end
          rows[i] = table.concat(row, "")
        end
        chunks[#chunks + 1] = { x = CCX + cx, y = CCY + cy, t = tid, s = table.concat(rows, "/") }
      end
    end
  end

  local territories = {}
  for tid = 1, next do
    territories[#territories + 1] = { t = tid, size = terr_size[tid], units = terr_units[tid] or {} }
  end
  table.sort(territories, function(a, b) return a.size > b.size end)

  helpers.write_file("eon-grouping-report.json", helpers.table_to_json({
    seed = game.default_map_gen_settings.seed,
    center_chunk = { CCX, CCY },
    radius_chunks = R,
    territory_count = next,
    chunk_count = #chunks,
    generation_passes = generation_passes,
    generation_members_requested = requested_members,
    ungenerated_scanned_chunks = ungenerated_scanned,
    ungenerated_territory_members_skipped = ungenerated_members,
    chunks = chunks,
    territories = territories,
    demolishers = (function()
      local out = {}
      for _, d in pairs(surface.find_entities_filtered({
        area = { { TX - (R + 1) * 32, TY - (R + 1) * 32 }, { TX + (R + 1) * 32, TY + (R + 1) * 32 } },
        type = "segmented-unit",
      })) do
        out[#out + 1] = { x = math.floor(d.position.x), y = math.floor(d.position.y), name = d.name }
      end
      return out
    end)(),
  }))
end)