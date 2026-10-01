-- Dev-only: report the control-stage Lua dialect so the runtime spot-noise
-- mirror can use portable 32-bit arithmetic instead of assuming 5.3 operators.
-- 5.3-only syntax is probed through load() so this file itself stays parseable
-- by Factorio's 5.2 dialect.

local function line(out, key, fn)
  local ok, value = pcall(fn)
  out[#out + 1] = string.format("%-38s %s", key, ok and tostring(value) or ("ERROR: " .. tostring(value)))
end

local function try_compile(source)
  local chunk, err = load(source, "=probe")
  if not chunk then return "compile error: " .. tostring(err) end
  local ok, value = pcall(chunk)
  if not ok then return "runtime error: " .. tostring(value) end
  return tostring(value)
end

local function report(tag)
  local out = {}
  out[#out + 1] = "== " .. tag .. " =="
  line(out, "_VERSION", function() return _VERSION end)
  line(out, "jit", function() return tostring(jit) end)
  line(out, "bit32 type", function() return type(bit32) end)
  line(out, "bit type", function() return type(bit) end)
  line(out, "select('#')", function() return select("#", 1, 2, 3) end)
  line(out, "7 // 2", function() return try_compile("return 7 // 2") end)
  line(out, "1 << 3", function() return try_compile("return 1 << 3") end)
  line(out, "0xff & 0x0f", function() return try_compile("return 0xff & 0x0f") end)
  line(out, "256 >> 4", function() return try_compile("return 256 >> 4") end)
  line(out, "bit32.bxor", function() return bit32 and bit32.bxor(0xff, 0x0f) or "no bit32" end)
  line(out, "math.cbrt", function() return tostring(math.cbrt) end)
  line(out, "math.frexp", function() return tostring(math.frexp) end)
  line(out, "math.ult", function() return tostring(math.ult) end)
  line(out, "math.fmod", function() return math.fmod(7.5, 2) end)
  line(out, "string.pack", function() return tostring(string.pack) end)
  line(out, "math.type", function() return tostring(math.type) end)
  line(out, "math.tointeger", function() return tostring(math.tointeger) end)
  line(out, "math.maxinteger", function() return tostring(math.maxinteger) end)
  line(out, "2^53 exact", function() return tostring(2 ^ 53) end)
  line(out, "1e308*10", function() return tostring(1e308 * 10) end)
  line(out, "require nested", function() return tostring(require("map-generation.terrain")) end)
  line(out, "surface.get_territory_for_chunk", function() return tostring(game.surfaces[1].get_territory_for_chunk) end)
  line(out, "create_territory", function() return tostring(game.surfaces[1].create_territory) end)
  line(out, "map_gen_settings.seed", function() return game.surfaces[1].map_gen_settings.seed end)
  line(out, "autoplace vulcanus_volcanism", function()
    local c = game.surfaces[1].map_gen_settings.autoplace_controls["vulcanus_volcanism"]
    return c and (c.size .. "/" .. c.frequency) or "nil"
  end)
  line(out, "territory_settings", function()
    local t = game.surfaces[1].map_gen_settings.territory_settings
    return tostring(t)
  end)
  helpers.write_file("eon-probe-lua/" .. tag .. ".txt", table.concat(out, "\n"))
  log("PROBE-LUA " .. tag .. " done")
end

script.on_init(function() report("on_init") end)
script.on_load(function() end)
