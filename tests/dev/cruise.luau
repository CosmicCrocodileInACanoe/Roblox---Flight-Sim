local Sim = require("../SimHarness")
local U = require("../../src/shared/Units")
local Assist = require("../../src/shared/Assist")
local FM = require("../../src/shared/FlightModel")
local Registry = require("../../src/shared/AircraftRegistry")
for _, id in Registry.order do
	local cfg = Registry.get(id)
	local cruise = cfg.speeds.cruise * U.MPS_PER_KT
	local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = 1500, speed = cruise })
	local a = Assist.new("assisted")
	a.autoTrim = 0.1
	local raw = FM.newControls()
	raw.throttle, raw.gearDown, raw.flaps = 0.55, false, 1
	s.ctl.gearDown = false
	local line = {}
	for i = 1, 60 * 180 do
		s:prepareEnv()
		local kts = s.model.result.ias * U.KTS_PER_MPS
		
		Assist.apply(a, raw, s.ctl, s.env, s.model, 1 / 60)
		s:frame()
		if i % 600 == 0 then
			local p = s:attitude()
			table.insert(line, string.format("t%d y%.0f vy%.1f kt%.0f thr%.2f p%.1f trim%.2f", s.time, s.py, s.vy, kts, raw.throttle, p, s.ctl.trim))
		end
	end
	print(id) for _, l in line do print("  " .. l) end
end
