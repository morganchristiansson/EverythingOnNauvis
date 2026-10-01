-- Noise-cost probe: measures what a map reset actually pays.
--
-- 1. Re-assigning map_gen_settings recompiles the noise program, which is what
--    the scenario's change_seed() does on every reset. The engine's own
--    per-program complexity report lands in the log under --verbose.
-- 2. Force-generating the reveal box around spawn measures what the compiled
--    program then has to pay per tile.
--
-- The control stage has no clock (no `os`, and LuaProfiler refuses to report
-- raw values), so TIMING is measured by the harness from the stage files'
-- mtimes: this writes a marker per stage, in order, from a single on_init.
--
-- Everything is done in on_init (see AGENTS.md: a headless server with no
-- players never ticks, and force_generate_chunk_requests only finishes once
-- control returns to the game loop -- so generation is spread over a few
-- consecutive force calls and the report is the last act).

local RADIUS = 19 -- chunks; the scenario's REVEAL_MAX_RADIUS (39x39 chunks)
local FORCE_PASSES = 6
local OUT = "eon-probe-noise/"

local function write(stage, data)
    data.stage = stage
    helpers.write_file(OUT .. stage .. ".json", helpers.table_to_json(data))
end

local function compile_surfaces()
    local report = {}
    for _, name in ipairs({"nauvis", "vulcanus", "gleba", "fulgora", "aquilo"}) do
        local surface = game.surfaces[name]
        if surface then
            local mgs = surface.map_gen_settings
            -- A no-op assignment is optimised away (the engine compares the
            -- table), so reroll the seed first: this is what the scenario's
            -- change_seed() does on every reset, and it is what makes the
            -- engine recompile the noise program and print its complexity.
            mgs.seed = mgs.seed + 1
            surface.map_gen_settings = mgs
            report[#report + 1] = name
        end
    end
    return report
end

local function count_generated(surface, radius)
    local generated = 0
    for cx = -radius, radius do
        for cy = -radius, radius do
            if surface.is_chunk_generated({cx, cy}) then
                generated = generated + 1
            end
        end
    end
    return generated
end

script.on_init(function()
    local surface = game.surfaces[1]
    local report = {
        radius_chunks = RADIUS,
        seed = surface.map_gen_settings.seed,
    }
    write("started", report)

    report.compiled_surfaces = compile_surfaces()
    write("compiled", report)

    surface.request_to_generate_chunks({0, 0}, RADIUS)
    for _ = 1, FORCE_PASSES do
        surface.force_generate_chunk_requests()
    end

    report.box_passes = FORCE_PASSES
    report.box_chunks_generated = count_generated(surface, RADIUS)
    report.finished = true
    write("box", report)
end)
