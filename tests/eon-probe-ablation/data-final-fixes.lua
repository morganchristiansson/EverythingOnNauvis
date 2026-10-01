-- Ablation probe: neutralise one subsystem of the mod's noise expressions and
-- let the engine price it.
--
-- The engine's own report (`--generate-map-preview --verbose`, "Entity noise
-- program ... estimated complexity: C") is the metric this measures against:
-- it is fast (~2 s) and it is the number Factorio's cost model uses, so an
-- ablation that drops complexity is a real per-tile saving, not an estimate.
--
-- The driver (tests/noise_ablation.py) rewrites the ABLATION line below before
-- the run, so this file is a template, not a configurable mod: a data-stage
-- setting cannot be forced from the command line (AGENTS.md, "headless cannot
-- force a mod setting").
--
-- An ablation deliberately breaks the map. That is the point: it is a
-- measurement of what a subsystem costs, never a shipped configuration.

local ABLATION = "none"

-- Every eon_* noise function becomes the identity: masks stop masking, fades
-- stop fading. The inner expression of every decorated prototype survives, so
-- what disappears from the report is exactly the masking layer.
local function ablate_masks()
    for name, record in pairs(data.raw["noise-function"]) do
        if name:match("^eon_mask") then
            record.expression = "e"
        end
    end
end

-- The volcano: cones, lava core, coverage, the detail noise, the territories'
-- fields. Everything that names a volcano, by expression name and by the
-- functions that build the cones.
local VOLCANO_EXPRESSIONS = {
    "eon_volcano_cone", "eon_volcano_lava_core", "eon_volcano_cliff_spike",
    "eon_volcano_coverage", "eon_updated_volcanic_folds", "eon_updated_volcanic_folds_flat",
    "eon_vulcanus_terrain", "eon_volcanus_ashlands_start", "eon_vulcanus_basalts_start",
    "eon_vulcanus_chimney", "eon_tungsten_ore_region", "eon_tungsten_volcano_favorability",
    "eon_calcite_region", "eon_volcanism", "eon_offset_vulcano",
    "eon_terr_volcano_small", "eon_terr_volcano_big", "eon_volcano_small_cap",
}
local function ablate_volcano()
    for _, name in ipairs(VOLCANO_EXPRESSIONS) do
        local record = data.raw["noise-expression"][name]
        if record then
            record.expression = "0"
        end
    end
    for name, record in pairs(data.raw["noise-function"]) do
        if name:match("volcano") or name:match("vulcanus") or name == "eon_volcano_spots_at" then
            record.expression = "0"
        end
    end
end

-- The merged biomes: the blended elevation/aux/moisture fields and the gleba
-- region machinery every mask is built on.
local function ablate_biome_blend()
    for _, name in ipairs({
        "eon_elevation_blended", "eon_aux_blended", "eon_moisture_blended",
        "eon_gleba_blend", "eon_gleba_region", "eon_gleba_transition",
        "eon_cliff_elevation", "eon_cliffiness", "eon_aquilo_mask",
    }) do
        local record = data.raw["noise-expression"][name]
        if record then
            record.expression = "0"
        end
    end
    for name, record in pairs(data.raw["noise-function"]) do
        if name:match("^eon_gleba") or name:match("^eon_aquilo")
            or name == "vulcanus_biome_blend" or name == "vulcanus_biome_multiscale" then
            record.expression = "0"
        end
    end
end

-- The whole decorative layer: every decorated prototype keeps its prototype
-- name but loses the probability expression the mod wrote for it.
local function ablate_decorative_probability()
    for _, prototype_type in ipairs({"optimized-decorative", "tree", "simple-entity", "fish", "plant"}) do
        for name, prototype in pairs(data.raw[prototype_type] or {}) do
            local autoplace = prototype.autoplace
            -- A few vanilla prototypes carry a literal probability, not an
            -- expression; only strings can be searched.
            if autoplace and type(autoplace.probability_expression) == "string"
                and autoplace.probability_expression:find("eon_", 1, true) then
                autoplace.probability_expression = "0"
            end
        end
    end
end

-- The extra resources the merged map adds (calcite, tungsten, geysers).
local function ablate_extra_resources()
    for _, name in ipairs({
        "calcite", "tungsten-ore", "sulfuric-acid-geyser", "holmium-ore",
        "fluorine-vent", "lithium-brine", "ammonia_ocean", "gleba_plants", "gleba_water",
    }) do
        local control = data.raw["autoplace-control"][name]
        if control then
            control.frequency = 0
        end
    end
end

-- The spot-deployment warp: `eon_detail_noise_at` displaces the volcano volcanoes
-- by up to ~25 tiles. A per-tile noise volcanoes for a detail effect.
local function ablate_detail_noise()
    local record = data.raw["noise-function"]["eon_detail_noise_at"]
    if record then
        record.expression = "0"
    end
end

-- The Gleba-flavoured formula EoN evaluates for the ~15 base prototypes vanilla
-- Gleba also grows (mask_gleba_shared). Unwrap them back to the Nauvis side.
--
-- The second argument of the `if` is what we want, and it is itself a call, so
-- this splits the argument list at paren depth 1 rather than looking for a
-- closing paren (which finds the wrong one, and then the unwrap rewrites nothing
-- -- the log line below is the assertion that it landed).
local function if_second_argument(expression)
    local args, depth, start = {}, 0, 4
    for index = 4, #expression do
        local char = expression:sub(index, index)
        if char == "(" then
            depth = depth + 1
        elseif char == ")" then
            if depth == 0 then break end
            depth = depth - 1
        elseif char == "," and depth == 0 then
            args[#args + 1] = expression:sub(start, index - 1)
            start = index + 2
        end
    end
    return args[2]
end

local function ablate_gleba_shared()
    local unwrapped, seen = 0, 0
    for _, prototype_type in ipairs({"optimized-decorative", "tree", "simple-entity", "plant"}) do
        for _, prototype in pairs(data.raw[prototype_type] or {}) do
            local autoplace = prototype.autoplace
            local expression = autoplace and autoplace.probability_expression
            if type(expression) == "string" and expression:sub(1, 17) == "if(eon_gleba_mask" then
                seen = seen + 1
                local nauvis = if_second_argument(expression)
                if nauvis and nauvis ~= "" then
                    autoplace.probability_expression = nauvis
                    unwrapped = unwrapped + 1
                end
            end
        end
    end
    log("[eon-probe-ablation] unwrapped " .. unwrapped .. " of " .. seen
        .. " mask_gleba_shared prototypes")
end

-- The volcano rim feather (trees and decoratives that grow on the volcano rim).
local function ablate_volcano_rim()
    for name, record in pairs(data.raw["noise-function"]) do
        if name:match("volcano_fade") or name:match("volcano_rim") then
            record.expression = "e"
        end
    end
end

-- Halve the octave count of the mod's OWN noise calls. Cheaper per evaluation,
-- and the map keeps its shapes but loses high-frequency detail.
local function ablate_octaves()
    for _, name in ipairs({
        "eon_aquilo_persistance", "eon_aquilo_detail", "eon_volcano_size_dist",
        "eon_sulfur_volcano_gate", "eon_aquilo_macro", "eon_detail_noise_at",
    }) do
        local record = data.raw["noise-expression"][name]
        if record and type(record.expression) == "string" then
            record.expression = record.expression:gsub("octaves%s*=%s*([0-9%.]+)", function(n)
                return "octaves = " .. math.max(1, math.floor(tonumber(n) / 2))
            end)
        end
    end
end

-- The Aquilo detail volcanoes: one variable_persistence_multioctave_noise with five
-- octaves, feeding the aquilo elevation mask.
local function ablate_aquilo_detail()
    local record = data.raw["noise-expression"]["eon_aquilo_detail"]
    if record then
        record.expression = "0"
    end
end

-- The whole spot-deployment warp (eon_detail_noise_at), the mod's own detail
-- effect on the volcano field.
local function ablate_detail_warp()
    local record = data.raw["noise-function"]["eon_detail_noise_at"]
    if record then
        record.expression = "0"
    end
end

-- The design under test is a set of BOUNDARY FADES: one per biome pair, with a
-- fade length and a set of decoratives allowed to cross. These ablations price
-- the parts of that design separately, because "the biome blend" is three
-- different things with three different costs.

-- 1. The blended terrain substrate every mask and tile probability reads.
local function ablate_blended_fields()
    for _, name in ipairs({"eon_elevation_blended", "eon_aux_blended", "eon_moisture_blended"}) do
        local record = data.raw["noise-expression"][name]
        if record then
            record.expression = "0"
        end
    end
end

-- 2. The cliff ladder on the blended elevation.
local function ablate_cliff_fields()
    for _, name in ipairs({"eon_cliff_elevation", "eon_cliffiness"}) do
        local record = data.raw["noise-expression"][name]
        if record then
            record.expression = "0"
        end
    end
end

-- 3. The Gleba boundary (region + transition + the masks derived from them).
local function ablate_gleba_region()
    for _, name in ipairs({"eon_gleba_region", "eon_gleba_transition", "eon_gleba_blend"}) do
        local record = data.raw["noise-expression"][name]
        if record then
            record.expression = "0"
        end
    end
    for name, record in pairs(data.raw["noise-function"]) do
        if name:match("^eon_gleba") then
            record.expression = "0"
        end
    end
end

-- 4. The Aquilo boundary.
local function ablate_aquilo_region()
    for _, name in ipairs({"eon_aquilo_mask", "eon_ammonia_mask"}) do
        local record = data.raw["noise-expression"][name]
        if record then
            record.expression = "0"
        end
    end
    for name, record in pairs(data.raw["noise-function"]) do
        if name:match("^eon_aquilo") then
            record.expression = "0"
        end
    end
end

-- 5. The FADES themselves: every feather helper becomes the identity, so each
--    decorated prototype loses its per-boundary fade and keeps its hard mask.
--    This is the price of the crossing design, isolated from the boundaries.
local FADE_FUNCTIONS = {
    "eon_mask_nauvis_deep", "eon_mask_nauvis_territory_fade",
    "eon_mask_gleba_territory_fade", "eon_mask_volcano_fade",
    "eon_mask_aquilo_land_fade", "eon_mask_aquilo_water_fade",
    "eon_fade", "eon_mask_gleba_fade",
}
local function ablate_fades()
    for _, name in ipairs(FADE_FUNCTIONS) do
        local record = data.raw["noise-function"][name]
        if record then
            record.expression = "e"
        end
    end
end

-- Per-volcanoes prices. Because `if()` has no short-circuit, a volcanoes referenced by
-- ANY per-tile expression is evaluated on every tile of the map, so the cost of
-- a boundary is really the cost of the noise it drags in.
local function ablate_field(name, replacement)
    return function()
        local record = data.raw["noise-expression"][name]
        if record then
            record.expression = replacement
        end
    end
end

local ABLATIONS = {
    ["none"] = function() end,
    ["masks"] = ablate_masks,
    ["volcano"] = ablate_volcano,
    ["biome-blend"] = ablate_biome_blend,
    ["decorative-probability"] = ablate_decorative_probability,
    ["extra-resources"] = ablate_extra_resources,
    ["detail-noise"] = ablate_detail_noise,
    ["octaves"] = ablate_octaves,
    ["blended-fields"] = ablate_blended_fields,
    ["cliff-fields"] = ablate_cliff_fields,
    ["gleba-region"] = ablate_gleba_region,
    ["aquilo-region"] = ablate_aquilo_region,
    ["fades"] = ablate_fades,
    ["aquilo-macro"] = ablate_field("eon_aquilo_macro", "0"),
    ["aquilo-persistance"] = ablate_field("eon_aquilo_persistance", "0"),
    ["gleba-elevation"] = ablate_field("eon_gleba_elevation_vanilla", "0"),
    ["gleba-moisture"] = ablate_field("eon_gleba_moisture_vanilla", "0"),
    ["gleba-blend"] = ablate_field("eon_gleba_blend", "0"),
    ["aquilo-detail"] = ablate_aquilo_detail,
    ["detail-warp"] = ablate_detail_warp,
    ["gleba-shared"] = ablate_gleba_shared,
    ["volcano-rim"] = ablate_volcano_rim,
    ["volcano+masks"] = function()
        ablate_volcano()
        ablate_masks()
    end,
    ["all"] = function()
        ablate_masks()
        ablate_volcano()
        ablate_biome_blend()
        ablate_decorative_probability()
        ablate_extra_resources()
    end,
}

local apply = ABLATIONS[ABLATION]
assert(apply, "unknown ablation: " .. tostring(ABLATION))
apply()
log("[eon-probe-ablation] applied: " .. ABLATION)
