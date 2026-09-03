
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
-- Exception: explosions. Their surface conditions select which "nuke-effects-*" variant applies
-- per planet (nuclear-ground on Nauvis, ammoniacal-ocean on Aquilo, lava on Vulcanus). Removing
-- them would make all variants trigger on Nauvis, letting the atomic bomb create impassable
-- ammoniacal-ocean/lava tiles that disrupt biter pathing.
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
                        end
                    end
                end
            end
        end
    end
end
