-- Dev-only: dump which chunks of a disc are claimed by a probe territory
-- expression. The expression itself is injected by the driver into
-- data-final-fixes.lua (rebuilt per probe).
local TX, TY = -80, -831
local R = 20

script.on_init(function()
  local surface = game.surfaces["nauvis"]
  surface.request_to_generate_chunks({ TX, TY }, R)
  surface.force_generate_chunk_requests()

  local ccx, ccy = math.floor(TX / 32), math.floor(TY / 32)
  local out = {}
  local missing = 0
  for cx = -R, R do
    for cy = -R, R do
      if cx * cx + cy * cy <= (R + 0.5) * (R + 0.5) then
        if not surface.is_chunk_generated({ ccx + cx, ccy + cy }) then
          missing = missing + 1
        else
          local t = surface.get_territory_for_chunk({ ccx + cx, ccy + cy })
          out[#out + 1] = { cx = ccx + cx, cy = ccy + cy, t = t ~= nil and 1 or 0 }
        end
      end
    end
  end
  helpers.write_file("eon-probe-report.json", helpers.table_to_json({
    chunks = out,
    missing = missing,
    claimed = (function()
      local n = 0
      for _, c in ipairs(out) do if c.t == 1 then n = n + 1 end end
      return n
    end)(),
    total = #out,
    expr = storage.eon_probe_expr,
  }))
end)