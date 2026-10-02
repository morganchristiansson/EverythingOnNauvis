
local remove_space_restrictions = settings.startup["eon-remove-space-platform-restrictions"].value

-- Surface properties relevant here (Factorio 2.0.77):
--   space-platform reports 0 for pressure/gravity/magnetic-field,
--   Nauvis resolves engine defaults: pressure = 1000, gravity ~= 10, magnetic-field = 90.
-- Any requirement greater than 0 but at most 1 therefore passes on Nauvis but fails on
-- space platforms.
-- (The lowest planetary value of all is Fulgora's gravity at 8, so 1 keeps entries working
-- on other planets too. Original properties are preserved, e.g. chests keep gravity >= 0.1.)
local SAFE_PLANETARY_REQUIREMENT = 1

-- Handle the surface conditions of every prototype that has them (buildings, recipes, ...):
--   setting on : remove them entirely, so anything from any planet works on Nauvis and space platforms.
--   setting off: keep restrictions against space platforms (see SAFE_PLANETARY_REQUIREMENT).
-- Exception: explosions. The remaining "nuke-effects-space" variant is gated to pressure 0
-- (space platforms) by its surface conditions; stripping them would make its tile damage
-- trigger on Nauvis too. (The Aquilo/Vulcanus nuke variants are deleted outright in
-- remove-planets.lua since those planets no longer exist, so the bomb always leaves
-- nuclear ground on Nauvis.)
for _, type in pairs(data.raw) do
    if type ~= data.raw["explosion"] then
        for _, name in pairs(type) do
            local conditions = name.surface_conditions
            if conditions then
                if remove_space_restrictions then
                    name.surface_conditions = nil
                else
                    -- Leave platform-exclusive conditions alone (their minimums are all 0,
                    -- e.g. the crusher's gravity = 0). Everything else gets its minimums
                    -- clamped and its maximums dropped, so Nauvis qualifies while space
                    -- platforms (which report 0 for every property) do not.
                    for _, condition in pairs(conditions) do
                        if (condition.min or 0) > 0 then
                            condition.min = math.min(condition.min, SAFE_PLANETARY_REQUIREMENT)
                            condition.max = nil
                        elseif not condition.min then
                            -- No minimum at all, only a maximum: a ceiling, i.e. "low pressure or
                            -- none" (quantum-processor caps pressure at 600, Aquilo's value, while
                            -- Nauvis is 1000). Keep it off space platforms only if the ceiling is
                            -- 0 (nothing like that exists), so drop it and let Nauvis in.
                            condition.max = nil
                        end
                    end
                end
            end
        end
    end
end
