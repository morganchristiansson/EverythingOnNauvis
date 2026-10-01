-- A census of the mirror's three caches: how many entries each holds.
--
-- This was Volcanoes:cache_size, in the SHIPPED mirror, with zero runtime callers. It
-- is a diagnostic for exactly two dev-only files -- the selftest, which asserts
-- the caches are bounded, and the bench, which prints them -- so it does not belong
-- among the code the game loads.
--
-- It lives here rather than being copied into each caller, for the same reason the
-- membership rule came to have four copies: a duplicated answer drifts from the
-- thing it answers, and nobody notices until the check is wrong.
--
-- Counting the tables needs nothing the mirror does not already expose.
return function(volcanoes)
  local counts = {}
  for _, name in ipairs{ "regions", "raw_regions", "rings" } do
    local n = 0
    for _ in pairs(volcanoes[name] or {}) do n = n + 1 end
    counts[name] = n
  end
  return counts
end
