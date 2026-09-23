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
  surface.request_to_generate_chunks({ TX, TY }, R)
  surface.force_generate_chunk_requests()

  local terr_id = {}     -- first-chunk key -> territory id
  local terr_size = {}   -- id -> chunk count
  local terr_units = {}  -- id -> {unit names}
  local next = 0
  local chunks = {}
  for cx = -R, R do
    for cy = -R, R do
      if cx * cx + cy * cy <= (R + 0.5) * (R + 0.5) then
        local wx = (CCX + cx) * 32
        local wy = (CCY + cy) * 32
        local t = surface.get_territory_for_chunk({ CCX + cx, CCY + cy })
        local tid = 0
        if t and t.valid then
          local cs = t.get_chunks()
          local c0 = cs[1]
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