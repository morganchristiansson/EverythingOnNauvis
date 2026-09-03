
if settings.startup["eon-asteroid-chunk-stack-50"].value then
  data.raw.item["metallic-asteroid-chunk"].stack_size = 50
  data.raw.item["carbonic-asteroid-chunk"].stack_size = 50
  data.raw.item["oxide-asteroid-chunk"].stack_size = 50
  data.raw.item["promethium-asteroid-chunk"].stack_size = 50
end

data.raw.item["lightning-rod"].hidden = true
data.raw.item["lightning-collector"].hidden = true

data.raw["lightning-attractor"]["lightning-rod"].hidden = true
data.raw["lightning-attractor"]["lightning-collector"].hidden = true
