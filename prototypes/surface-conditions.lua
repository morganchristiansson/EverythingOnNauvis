

-- Remove surface conditions for every entry that has surface condition (like buildings, recipes, etc...)
-- Exception: explosions. Their surface conditions exist to pick which "nuke-effects-*" variant
-- applies on each planet (nuclear-ground on Nauvis, ammoniacal-ocean on Aquilo, lava on Vulcanus).
-- Without them all variants would trigger on Nauvis, letting the atomic bomb create
-- impassable ammoniacal-ocean/lava tiles that disrupt biter pathing.
for _, type in pairs(data.raw) do
    if type ~= data.raw["explosion"] then
        for _, name in pairs(type) do
            if name.surface_conditions then
                name.surface_conditions = nil
            end
        end
    end
end
