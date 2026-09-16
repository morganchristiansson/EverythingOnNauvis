-- Dev-only verifier: charts a disc around a given volcano tile position, force-
-- generates it synchronously, then dumps per-chunk territory ids plus a 4px
-- volcano/lava subsample mask, so the exact territory polygons the engine
-- produced can be compared against the volcano tiles.
--
-- Headless run flow (see tests/verify_territory.py): create the save with
-- --create (which does NOT run control scripts, so script.dat in the save marks
-- storage as initialised), strip script.dat from the zip, then load with
-- --benchmark. With storage absent, on_init fires during load. Everything --
-- request, force_generate_chunk_requests() and the scan -- happens inside
-- on_init: chunk generation requested during load uses the fast initial-map-gen
-- path and force_generate blocks until the whole disc exists. Requests made
-- from on_nth_tick (after game start) are silently ignored headless.
local TX, TY = -80, -831        -- reported volcano gps, tile coords
local RADIUS_CHUNKS = 64
local CENTER_CHUNK_X, CENTER_CHUNK_Y = math.floor(TX / 32), math.floor(TY / 32)

local function is_volcano_tile(name)
  return string.sub(name, 1, 8) == "volcanic" or name == "lava" or name == "lava-hot"
end

local function is_lava_tile(name)
  return name == "lava" or name == "lava-hot"
end

local function is_water_tile(name)
  return name == "water" or name == "deepwater"
end

script.on_init(function()
  helpers.write_file("eon-verify-started.txt", "on_init fired at tick " .. game.tick)
  local surface = game.surfaces["nauvis"]
  local R = RADIUS_CHUNKS

  -- Generate the whole disc synchronously (fast initial-map-gen path).
  surface.request_to_generate_chunks({ TX, TY }, R)
  surface.force_generate_chunk_requests()

  -- Per-chunk: territory id + 8x8 subsample (4px) mask, bit values:
  -- 0 = no volcano, 1 = volcano terrain, 2 = lava (territory-adjacent).
  local chunks = {}
  local terr_of = {}        -- territory ref -> index
  local next_tidx = 0
  for cx = -R, R do
    for cy = -R, R do
      if cx * cx + cy * cy <= (R + 0.5) * (R + 0.5) then
        local x0 = (CENTER_CHUNK_X + cx) * 32
        local y0 = (CENTER_CHUNK_Y + cy) * 32
        local terr = surface.get_territory_for_chunk({ CENTER_CHUNK_X + cx, CENTER_CHUNK_Y + cy })
        local tidx = 0
        local patrol = nil
        if terr then
          local known = terr_of[terr]
          if not known then
            next_tidx = next_tidx + 1
            terr_of[terr] = next_tidx
            tidx = next_tidx
          else
            tidx = known
          end
          local path = nil
          local okp, res = pcall(function() return terr.get_patrol_path() end)
          if okp then path = res end
          if path and path[1] then
            patrol = { x = path[1][1], y = path[1][2] }
          end
        end
        -- 4px subsample, bit per sample: 1 = volcano terrain, 2 = lava, 4 = water/deepwater.
        local rows = {}
        for i = 1, 8 do
          local row = {}
          for j = 1, 8 do
            local name = surface.get_tile(x0 + (j - 1) * 4, y0 + (i - 1) * 4).name
            local b = 0
            if is_volcano_tile(name) then b = b + 1 end
            if is_lava_tile(name) then b = b + 2 end
            if is_water_tile(name) then b = b + 4 end
            row[j] = b
          end
          rows[i] = table.concat(row, "")
        end
        -- Full resolution at the five diagnostic points (chunk corners + center).
        local points = {}
        for _, p in ipairs({ { 0, 0 }, { 31, 0 }, { 0, 31 }, { 31, 31 }, { 16, 16 } }) do
          points[#points + 1] = surface.get_tile(x0 + p[1], y0 + p[2]).name
        end
        chunks[#chunks + 1] = {
          x = CENTER_CHUNK_X + cx, y = CENTER_CHUNK_Y + cy,
          t = tidx,
          s = table.concat(rows, "/"),
          p = points,
          pat = patrol,
        }
      end
    end
  end

  helpers.write_file("eon-territory-report.json", helpers.table_to_json({
    seed = game.default_map_gen_settings.seed,
    center_chunk = { CENTER_CHUNK_X, CENTER_CHUNK_Y },
    radius_chunks = R,
    chunk_count = #chunks,
    territory_count = next_tidx,
    chunks = chunks,
    demolishers = (function()
      local demos = {}
      for _, d in pairs(surface.find_entities_filtered({
        area = { { TX - (R + 1) * 32, TY - (R + 1) * 32 }, { TX + (R + 1) * 32, TY + (R + 1) * 32 } },
        type = "segmented-unit",
      })) do
        demos[#demos + 1] = { x = math.floor(d.position.x), y = math.floor(d.position.y), name = d.name }
      end
      return demos
    end)(),
    tungsten = (function()
      local out = {}
      for _, d in pairs(surface.find_entities_filtered({
        area = { { TX - (R + 1) * 32, TY - (R + 1) * 32 }, { TX + (R + 1) * 32, TY + (R + 1) * 32 } },
        name = "tungsten-ore",
        limit = 20000,
      })) do
        out[#out + 1] = { x = math.floor(d.position.x), y = math.floor(d.position.y) }
      end
      return out
    end)(),
  }))
end)