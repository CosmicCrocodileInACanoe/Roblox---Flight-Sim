local Sim = require("../SimHarness")
local U = require("../../src/shared/Units")
local Registry = require("../../src/shared/AircraftRegistry")
local cfg = Registry.get("atlas400")
local alt = 2500
local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = alt, speed = cfg.speeds.vref * 0.85 * U.MPS_PER_KT * 1.3 })
s.ctl.gearDown = false
s.ctl.throttle = 0
for i = 1, 60 * 80 do
	if s.time < 25 then s.ctl.pitch = 1 else
		local p = s:attitude()
		s.ctl.throttle = 1
		local target = if s.time < 34 then -3 else 5
		s.ctl.pitch = math.clamp((target - p) * 0.08 - s.env.wx * 1.2, -1, 1)
	end
	local r = s:frame()
	if i % 120 == 0 then local p,b = s:attitude() print(string.format("t%.0f y%.0f vy%.1f kt%.0f p%.1f b%.1f a%.1f stall%s", s.time, s.py, s.vy, r.ias*U.KTS_PER_MPS, p, b, math.deg(r.alpha), tostring(r.stall))) end
end
