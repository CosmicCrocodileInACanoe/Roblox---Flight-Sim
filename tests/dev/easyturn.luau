local Sim = require("../SimHarness")
local U = require("../../src/shared/Units")
local Assist = require("../../src/shared/Assist")
local FM = require("../../src/shared/FlightModel")
local Registry = require("../../src/shared/AircraftRegistry")
for _, id in Registry.order do
	local cfg = Registry.get(id)
	for _, roll in { 0, 1 } do
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = 1500, speed = cfg.speeds.cruise * U.MPS_PER_KT * 0.9 })
		s.ctl.gearDown = false
		local a = Assist.new("easy"); a.autoTrim = 0.1
		local raw = FM.newControls(); raw.throttle, raw.gearDown, raw.flaps = 0.55, false, 1
		raw.roll = roll
		local out = {}
		for i = 1, 60 * 25 do
			if i == 60 * 15 then raw.roll = 0 end
			s:prepareEnv(); Assist.apply(a, raw, s.ctl, s.env, s.model, 1 / 60); s:frame()
			if i % 300 == 0 then local p, b = s:attitude(); table.insert(out, string.format("t%d y%.0f p%.1f b%.1f vy%.1f kt%.0f", i/60, s.py, p, b, s.vy, s.model.result.ias*U.KTS_PER_MPS)) end
		end
		print(id, roll, table.concat(out, " | "))
	end
end
