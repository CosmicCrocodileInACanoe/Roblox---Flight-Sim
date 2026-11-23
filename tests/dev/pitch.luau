local Sim = require("../SimHarness")
local U = require("../../src/shared/Units")
local Registry = require("../../src/shared/AircraftRegistry")
for _, id in Registry.order do
	local cfg = Registry.get(id)
	local s = Sim.new(cfg, { enginesRunning = true, flaps = 5, gearDown = true, y = 1000, speed = (cfg.speeds.vref + 5) * U.MPS_PER_KT })
	s.ctl.flaps = 5
	s.ctl.throttle = 0.4
	local out = {}
	for i = 1, 60 * 8 do
		s.ctl.pitch = if s.time > 1 and s.time < 3 then -0.3 else 0
		s:frame()
		if i % 30 == 0 then
			local p = s:attitude()
			table.insert(out, string.format("%.1f", p))
		end
	end
	print(id, table.concat(out, " "))
end
