-- Dev-only baseline probe: counts cliffs and the tile-name mix in the EoN
-- "gleba south" box (x -1056..1056, y 1040..2200) on the nauvis surface.
-- Runs in three configurations, driven by which mods the driver loads:
--   * plain vanilla nauvis               -> nauvis terrain (sanity)
--   * + eon-probe-glebanauvis mod        -> vanilla gleba terrain on nauvis
--   * + EverythingOnNauvis-morganc       -> the merged EoN map south
-- Driver: create save, strip script.dat, --benchmark. Manual dev tool.
local GLEBA_DECOR = {
  "barnacles-decal", "black-sceptre", "blood-grape", "blood-grape-vibrant", "brambles",
  "brown-cup", "coral-land", "coral-stunted", "coral-stunted-grey", "coral-water",
  "cream-nerve-roots-veins-dense", "cream-nerve-roots-veins-sparse", "curly-roots-grey",
  "curly-roots-orange", "fuchsia-pita", "green-cup", "green-lettuce-lichen-1x1",
  "green-lettuce-lichen-3x3", "green-lettuce-lichen-6x6", "green-lettuce-lichen-water-1x1",
  "green-lettuce-lichen-water-3x3", "green-lettuce-lichen-water-6x6", "grey-cracked-mud-decal",
  "honeycomb-fungus", "honeycomb-fungus-1x1", "honeycomb-fungus-decayed", "knobbly-roots",
  "knobbly-roots-orange", "matches-small", "mycelium", "nerve-roots-dense", "nerve-roots-sparse",
  "pale-lettuce-lichen-1x1", "pale-lettuce-lichen-3x3", "pale-lettuce-lichen-6x6",
  "pale-lettuce-lichen-cups-1x1", "pale-lettuce-lichen-cups-3x3", "pale-lettuce-lichen-cups-6x6",
  "pale-lettuce-lichen-water-1x1", "pale-lettuce-lichen-water-3x3",
  "pale-lettuce-lichen-water-6x6", "pink-phalanges", "polycephalum-balloon",
  "polycephalum-slime", "purple-nerve-roots-veins-dense", "purple-nerve-roots-veins-sparse",
  "red-lichen-decal", "red-nerve-roots-veins-dense", "red-nerve-roots-veins-sparse",
  "solo-barnacle", "split-gill-1x1", "split-gill-2x2", "split-gill-dying-1x1",
  "split-gill-dying-2x2", "split-gill-red-1x1", "split-gill-red-2x2", "stone", "veins",
  "veins-small", "white-carpet-grass", "wispy-lichen", "yellow-coral",
  "yellow-lettuce-lichen-1x1", "yellow-lettuce-lichen-3x3", "yellow-lettuce-lichen-6x6",
  "yellow-lettuce-lichen-cups-1x1", "yellow-lettuce-lichen-cups-3x3",
  "yellow-lettuce-lichen-cups-6x6",
  "copper-bacteria", "iron-bacteria", "gleba-spawner-slime",
}
local NAUVIS_DECOR = {
  "big-rock", "big-sand-rock", "brown-asterisk", "brown-asterisk-mini", "brown-carpet-grass",
  "brown-fluff", "brown-fluff-dry", "brown-hairy-grass", "cracked-mud-decal", "dark-mud-decal",
  "garballo", "garballo-mini-dry", "green-asterisk", "green-asterisk-mini", "green-bush-mini",
  "green-carpet-grass", "green-croton", "green-desert-bush", "green-hairy-grass", "green-pita",
  "green-pita-mini", "green-small-grass", "huge-rock", "light-mud-decal", "medium-rock",
  "medium-sand-rock", "muddy-stump", "red-asterisk", "red-croton", "red-desert-bush",
  "red-desert-decal", "red-pita", "sand-decal", "sand-dune-decal", "small-rock",
  "small-sand-rock", "tiny-rock", "white-desert-bush", "worms-decal",
}
local VULCANUS_DECOR = {
  "vulcanus-rock-decal-large", "vulcanus-crack-decal", "vulcanus-crack-decal-large",
  "vulcanus-crack-decal-huge-warm", "vulcanus-crack-decal-warm", "calcite-stain",
  "calcite-stain-small", "sulfur-stain", "sulfur-stain-small", "sulfuric-acid-puddle",
  "sulfuric-acid-puddle-small", "crater-small", "crater-large", "pumice-relief-decal",
  "vulcanus-sand-decal", "vulcanus-dune-decal", "waves-decal", "medium-volcanic-rock",
  "small-volcanic-rock", "tiny-volcanic-rock", "tiny-rock-cluster", "small-sulfur-rock",
  "tiny-sulfur-rock", "sulfur-rock-cluster",
}
local AQUILO_DECOR = {
  "iceberg", "iceberg-small", "iceberg-big", "iceberg-huge", "iceberg-rock", "snow-drift",
  "snow-drift-small", "ice-snow-decal", "ice-snow-decal-small", "snow-decal", "snow-decal-1",
  "ice-decal", "dense-ice-decal", "snowy-step-decal",
}
local GLEBA_TREES = {
  "yumako-tree", "jellystem", "funneltrunk", "boompuff", "teflilly", "stingfrond",
  "cuttlepop", "slipstack", "sunnycomb", "hairyclubnub", "lickmaw", "water-cane",
}
local NAUVIS_TREES = {
  "tree-01", "tree-02", "tree-03", "tree-04", "tree-05", "tree-06", "tree-07", "tree-08",
  "tree-09", "tree-01-brown", "tree-02-brown", "tree-03-brown", "tree-04-brown",
  "tree-05-brown", "dry-hairy-tree", "dead-dry-hairy-tree", "dead-grey-trunk",
  "dead-tree-desert",
}
local function decor_class(name)
  for _, n in ipairs(GLEBA_DECOR) do if n == name then return "gleba" end end
  for _, n in ipairs(NAUVIS_DECOR) do if n == name then return "nauvis" end end
  for _, n in ipairs(VULCANUS_DECOR) do if n == name then return "vulcanus" end end
  for _, n in ipairs(AQUILO_DECOR) do if n == name then return "aquilo" end end
  return "other"
end
local function tree_class(name)
  for _, n in ipairs(GLEBA_TREES) do if n == name then return "gleba" end end
  for _, n in ipairs(NAUVIS_TREES) do if n == name then return "nauvis" end end
  return nil
end
local function band_of(y)
  if y < 1400 then return "y1040-1400"
  elseif y < 1800 then return "y1400-1800"
  else return "y1800-2200" end
end

script.on_init(function()
  helpers.write_file("eon-base-started.txt", "on_init fired at tick " .. game.tick)
  local report = { surfaces = {} }
  for name in pairs(game.surfaces) do report.surfaces[#report.surfaces + 1] = name end
  local surface = game.surfaces["nauvis"]
  local out = {}
  for _, p in ipairs({ { 0, 1340 }, { 0, 2400 } }) do
    surface.request_to_generate_chunks(p, 34)
  end
  surface.force_generate_chunk_requests()
  local area = { left_top = { -1056, 1040 }, right_bottom = { 1056, 2200 } }
  -- tile histogram (sample every 4 tiles for a real inventory)
  local tiles = {}
  local bands = {}
  local n = 0
  local function grp_of(name)
    if string.find(name, "wetland") then return "wetland" end
    if string.find(name, "midland") then return "midland" end
    if string.find(name, "highland") then return "highland" end
    if string.find(name, "lowland") then return "lowland" end
    if string.find(name, "deep") then return "deep_lake" end
    if name == "water" or name == "deepwater" then return "water" end
    if string.find(name, "natural-") then return "fertile" end
    return "other"
  end
  for y = 1040, 2200, 4 do
    for x = -1056, 1056, 4 do
      if surface.is_chunk_generated{ math.floor(x / 32), math.floor(y / 32) } then
        local t = surface.get_tile(x, y).name
        tiles[t] = (tiles[t] or 0) + 1
        local b = bands[band_of(y)] or {}
        local g = grp_of(t)
        b[g] = (b[g] or 0) + 1
        bands[band_of(y)] = b
        n = n + 1
      end
    end
  end
  local ents = surface.find_entities_filtered({ area = area })
  local cliffs = {}
  for _, e in ipairs(ents) do
    if e.type == "cliff" then cliffs[e.name] = (cliffs[e.name] or 0) + 1 end
  end
  -- Decoratives: exhaustive via find_decoratives_filtered (optimized-decoratives
  -- never show up in find_entities_filtered), histogram + per-band biome classes.
  local deco = {}       -- name -> count (whole box)
  local deco_bands = {} -- band -> {class -> count}
  local deco_top = {}   -- band -> {name -> count}
  local n_deco = 0
  for _, dec in ipairs(surface.find_decoratives_filtered({ area = area })) do
    local name = dec.decorative.name
    deco[name] = (deco[name] or 0) + 1
    local band = band_of(dec.position.y)
    local db = deco_bands[band] or {}
    db[decor_class(name)] = (db[decor_class(name)] or 0) + 1
    deco_bands[band] = db
    local tb = deco_top[band] or {}
    tb[name] = (tb[name] or 0) + 1
    deco_top[band] = tb
    n_deco = n_deco + 1
  end
  -- Trees/plants: entity scan over known names, per band.
  local trees = {}
  local tree_bands = {}
  for _, e in ipairs(ents) do
    local cls = tree_class(e.name)
    if cls then
      trees[e.name] = (trees[e.name] or 0) + 1
      local band = band_of(e.position.y)
      local tb = tree_bands[band] or {}
      tb[cls] = (tb[cls] or 0) + 1
      tree_bands[band] = tb
    end
  end
  out.tiles_total_samples = n
  out.cliffs = cliffs
  out.decor_total = n_deco
  out.decor = deco
  out.decor_bands = deco_bands
  out.decor_top_band = deco_top
  out.trees = trees
  out.tree_bands = tree_bands
  out.tile_groups = {}
  for name, c in pairs(tiles) do
    local g = grp_of(name)
    out.tile_groups[g] = (out.tile_groups[g] or 0) + c
  end
  out.bands = bands
  out.top_tiles = tiles
  report.gleba = out
  helpers.write_file("eon-baseline-report.json", helpers.table_to_json(report))
end)