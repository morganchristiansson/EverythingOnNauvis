-- Dev-only prober for an EXISTING save: dump what the built surface carries in
-- its stored map_gen_settings vs what it places (cliff census), then force-
-- generate a fresh patch of chunks at an ungenerated spot next to a found
-- volcano and count what the current mod produces there (incl. the runtime
-- "cliff"->"cliff-vulcanus" re-skin in control.lua).
--
-- Works in on_load (read-only dump) and in on_init (dump + generation; ship a
-- script.dat-stripped save so on_init fires).

local function line(f, ...)
  f:write(string.format(...), "\n")
end

local function dump_readonly()
  local s = game.surfaces["nauvis"] or game.surfaces[1]
  local out = {}
  local function add(k, v) table.insert(out, k .. " = " .. tostring(v)) end
  add("surface_name", s.name)
  add("seed", s.map_gen_settings.seed)
  local cs = s.map_gen_settings.cliff_settings or {}
  for _, k in ipairs({ "name", "control", "cliff_elevation_0", "cliff_elevation_interval", "richness", "cliff_smoothing" }) do
    add("cliff_settings." .. k, cs[k])
  end
  local ac = s.map_gen_settings.autoplace_controls or {}
  local nc = ac["nauvis_cliff"]
  add("nauvis_cliff", nc and ("freq=" .. tostring(nc.frequency) .. " size=" .. tostring(nc.size) .. " rich=" .. tostring(nc.richness)) or "MISSING")
  local pn = s.map_gen_settings.property_expression_names or {}
  for _, k in ipairs({ "elevation", "cliff_elevation", "cliffiness" }) do
    add("prop." .. k, pn[k])
  end
  local keys = {}
  for k in pairs(pn) do table.insert(keys, tostring(k)) end
  table.sort(keys)
  add("prop_keys(" .. #keys .. ")", table.concat(keys, ","))
  local ent = ((s.map_gen_settings.autoplace_settings or {}).entity or {}).settings or {}
  keys = {}
  for k in pairs(ent) do table.insert(keys, tostring(k)) end
  table.sort(keys)
  add("entity_settings(" .. #keys .. ")", table.concat(keys, ","))
  local tile = ((s.map_gen_settings.autoplace_settings or {}).tile or {}).settings or {}
  keys = {}
  for k in pairs(tile) do table.insert(keys, tostring(k)) end
  table.sort(keys)
  add("tile_settings(" .. #keys .. ")", table.concat(keys, ","))
  for _, name in ipairs({ "cliff", "cliff-vulcanus", "cliff-gleba", "crater-cliff" }) do
    add("count." .. name, s.count_entities_filtered{ name = name })
  end
  helpers.write_file("eon-probe-save/readonly.txt", table.concat(out, "\n"))
  log("PROBE-SAVE readonly dump done")
end

local V = {}
local function is_volatile_prefix(name, prefixes)
  for _, p in ipairs(prefixes) do
    if string.sub(name, 1, #p) == p then return true end
  end
  return false
end

script.on_load(function()
  dump_readonly()
end)

script.on_init(function()
  dump_readonly()
  local surface = game.surfaces["nauvis"]

  -- 1. Scan a bounded window for volcano chunks (corner tile belongs to the
  --    volcanic family OR lava), record first hit per quadrant.
  local hits = {}
  local chunk_count = 0
  for cx = -192, 192 do
    for cy = -192, 192 do
      chunk_count = chunk_count + 1
      local t = surface.get_tile(cx * 32, cy * 32).name
      if string.sub(t, 1, 8) == "volcanic" or t == "lava" or t == "lava-hot" then
        table.insert(hits, { cx, cy, t })
        if #hits >= 200 then break end
      end
    end
    if #hits >= 200 then break end
  end
  local out = {}
  table.insert(out, "chunks_scanned=" .. chunk_count)
  table.insert(out, "volcano_chunks_found=" .. #hits)

  -- 2. Pick a volcano chunk that has an UNGENERATED neighbour (frontier).
  local chosen = nil
  for _, h in ipairs(hits) do
    local hx, hy = h[1], h[2]
    for _, d in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
      local nx, ny = hx + d[1], hy + d[2]
      if not surface.is_chunk_generated({ nx, ny }) then
        chosen = { hx, hy, nx, ny }
        break
      end
    end
    if chosen then break end
  end
  if chosen then
    local hx, hy, nx, ny = chosen[1], chosen[2], chosen[3], chosen[4]
    table.insert(out, string.format("volcano_chunk=%d,%d frontier_neighbour=%d,%d", hx, hy, nx, ny))
    log(string.format("PROBE-SAVE volcano chunk %d,%d frontier %d,%d ; requesting", hx, hy, nx, ny))
    local tx, ty = hx * 32 + 16, hy * 32 + 16
    surface.request_to_generate_chunks({ tx, ty }, 8)
    surface.force_generate_chunk_requests()
    local before = surface.count_entities_filtered{ name = "cliff-vulcanus" }
    local area = { left_top = { tx - 8 * 32, ty - 8 * 32 }, right_bottom = { tx + 8 * 32, ty + 8 * 32 } }
    local c_cliff = surface.count_entities_filtered{ area = area, name = "cliff" }
    local c_vulc = surface.count_entities_filtered{ area = area, name = "cliff-vulcanus" }
    local c_gleb = surface.count_entities_filtered{ area = area, name = "cliff-gleba" }
    local c_crat = surface.count_entities_filtered{ area = area, name = "crater-cliff" }
    table.insert(out, string.format("new_patch: cliff=%d vulcanus=%d gleba=%d crater=%d (vulcanus_delta=%d)",
      c_cliff, c_vulc, c_gleb, c_crat, c_vulc - before))
    -- sample a few volcanic tiles in the patch
    local tcount = 0
    for px = tx - 8 * 32, tx + 8 * 32, 32 do
      for py = ty - 8 * 32, ty + 8 * 32, 32 do
        local t = surface.get_tile(px, py).name
        if string.sub(t, 1, 8) == "volcanic" then tcount = tcount + 1 end
      end
    end
    table.insert(out, "patch_volcanic_samples=" .. tcount)
  else
    log("PROBE-SAVE no frontier volcano chunk found in window")
    table.insert(out, "no_frontier_volcano")
  end
  helpers.write_file("eon-probe-save/dump.txt", table.concat(out, "\n"))
  log("PROBE-SAVE done")
end)