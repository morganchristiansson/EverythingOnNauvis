-- Dev-only: generate the vanilla gleba terrain ON the nauvis surface (used to
-- establish what vanilla gleba at EoN south coordinates looks like). Copies
-- the gleba planet's map_gen_settings wholesale onto nauvis. Only loaded with
-- base + space-age (no EoN).
local gleba_mgs = table.deepcopy(data.raw.planet["gleba"].map_gen_settings)
data.raw.planet["nauvis"].map_gen_settings = gleba_mgs