-- Gleba natives react to pollution (behaviour yoinked from EverythingOnNauvis-Patches).
-- There are no other planets with this mod, so spores are dead: on vanilla Gleba,
-- pentapods/spawners key off the "spores" pollutant, but on Nauvis there is no
-- spore cloud, only pollution, so pentapods would otherwise ignore your factory.
-- Every "spores" absorption/emission is therefore moved to "pollution".
-- Note: these are all attributes on other prototypes, not standalone entries, so
-- there is nothing to delete except the pollutant type itself (see below).

local function move_key_spores_to_pollution(absorptions)
  if not absorptions then return end
  if absorptions.spores == nil then return end

  if absorptions.pollution == nil then
    absorptions.pollution = absorptions.spores
  end

  absorptions.spores = nil
end

for _, tile in pairs(data.raw["tile"] or {}) do
  move_key_spores_to_pollution(tile.absorptions_per_second)
end

for _, proto in pairs(data.raw["unit"] or {}) do
  move_key_spores_to_pollution(proto.absorptions_to_join_attack)
end

for _, proto in pairs(data.raw["spider-unit"] or {}) do
  move_key_spores_to_pollution(proto.absorptions_to_join_attack)
end

for _, proto in pairs(data.raw["unit-spawner"] or {}) do
  move_key_spores_to_pollution(proto.absorptions_per_second)
end

-- Harvesting yumako/jellynut releases a pollution puff that attracts natives,
-- mirroring the vanilla spore puff.
for _, proto in pairs(data.raw["plant"] or {}) do
  move_key_spores_to_pollution(proto.harvest_emissions)
end

-- Agricultural towers emit a small pollution trickle so attack groups find them,
-- mirroring the vanilla "spores = 4" beacon.
for _, proto in pairs(data.raw["agricultural-tower"] or {}) do
  if proto.energy_source and proto.energy_source.emissions_per_minute then
    move_key_spores_to_pollution(proto.energy_source.emissions_per_minute)
  end
end

-- The "spores" airborne-pollutant prototype itself is now unused, but it is kept:
-- the hidden Gleba planet still declares pollutant_type = "spores", and other
-- mods may reference the pollutant. Deleting it risks data-stage validation
-- errors for zero benefit (it is one tiny definition with no runtime cost when
-- nothing emits or absorbs it).
