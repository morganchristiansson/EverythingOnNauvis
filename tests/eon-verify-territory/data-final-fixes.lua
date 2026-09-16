-- Headless verifier only: the benchmark never merges territory objects (every
-- claimed chunk gets its own), so the shipped minimum_territory_size filtering
-- would drop ALL chunks headless and hide the mask's real membership. Force
-- min size 0 here; sizes/merging are judged in the real game, membership isn't.
data.raw.planet["nauvis"].map_gen_settings.territory_settings.minimum_territory_size = 0