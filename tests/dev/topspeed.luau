local SIGN = 1
local Sim = require("../SimHarness")
local U = require("../../src/shared/Units")
local Assist = require("../../src/shared/Assist")
local FM = require("../../src/shared/FlightModel")
local Registry = require("../../src/shared/AircraftRegistry")
local ids = string.split(os.getenv and "" or "", ",")
ids = { "arrowstar" }
for _, id in ids do
	local cfg = Registry.get(id)
	for _, alt in { 1500, 6000, 9000, 11000 } do
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = alt, speed = cfg.speeds.cruise * U.MPS_PER_KT / math.sqrt(U.densityRatio(alt)) })
		local a = Assist.new("assisted")
		a.autoTrim = 0.1
		local raw = FM.newControls()
		raw.throttle, raw.gearDown, raw.flaps = 1, false, 1
		s.ctl.gearDown = false
		local kts, tas = 0, 0
		for i = 1, 60 * 300 do
			if i % 3600 == 0 then print(string.format('   t%d kt %.0f y %.0f p %.2f', i/60, s.model.result.ias * U.KTS_PER_MPS, s.py, raw.pitch)) end
			s:prepareEnv()
			kts = s.model.result.ias * U.KTS_PER_MPS
			tas = s.model.result.tas * U.KTS_PER_MPS
			-- crude altitude hold
			local pd = s:attitude(); local tgt = math.clamp((alt - s.py) * 0.02 - s.vy * 0.3, -5, 12); raw.pitch = math.clamp((tgt - pd) * SIGN * 0.15, -1, 1)
			Assist.apply(a, raw, s.ctl, s.env, s.model, 1 / 60)
			s:frame()
		end
		print(string.format("%s alt %d: IAS %.0f TAS %.0f kt (Mach %.2f) y %.0f", id, alt, kts, tas, tas / 1.943844 / U.speedOfSound(s.py * 1), s.py))
	end
end
