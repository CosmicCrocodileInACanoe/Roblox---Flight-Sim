local Sim = require("../SimHarness")
local U = require("../../src/shared/Units")
local Registry = require("../../src/shared/AircraftRegistry")
local function land(cfg)
	local dist = 3000
	local gsA = math.rad(3)
	local rest = Sim.restHeight(cfg)
	local vapp = cfg.speeds.vref + 5
	local s = Sim.new(cfg, { enginesRunning = true, flaps = 5, gearDown = true, x = 0, z = dist, y = rest + dist * math.tan(gsA), speed = vapp * U.MPS_PER_KT, headingDeg = 0 })
	s.ctl.flaps = 5
	local trim, thr = 0.5, 0.4
	local tdz, stopz, td
	for _ = 1, 60 * 200 do
		s:prepareEnv()
		local r = s.model.result
		local h = s.py - rest
		local target = math.max(0, s.pz * math.tan(gsA))
		local kts = r.ias * U.KTS_PER_MPS
		if not tdz then
			local vsT
			if h > 14 then
				vsT = -s:groundSpeed() * math.tan(gsA) + (target - h) * 0.12
				thr = math.clamp(thr + (vapp - kts) * 0.02 / 60 * 10, 0, 1)
				s.ctl.throttle = math.clamp(thr + (vapp - kts) * 0.04, 0, 1)
			else
				vsT = -0.6 - h * 0.05
				s.ctl.throttle = math.clamp(thr + (vapp - 6 - kts) * 0.04, 0, 1) * math.clamp((h - 5) / 8, 0, 1)
			end
			-- two loops: vertical-speed error -> pitch target, pitch error -> elevator
			local p = s:attitude()
			local pitchT = math.clamp(2 + (vsT - s.vy) * 0.8, -6, 12)
			local cmd = math.clamp((pitchT - p) * 0.1 - s.env.wx * 2.0, -1, 1)
			trim = math.clamp(trim + cmd * 0.4 / 60, -1, 1)
			s.ctl.trim = trim
			s.ctl.pitch = cmd
		else
			s.ctl.throttle = 0
			s.ctl.reverse = kts > 60
			s.ctl.brake = 1
			s.ctl.speedbrake = 1
			s.ctl.trim = 0
			s.ctl.pitch = math.clamp(-0.2 - s.env.wx, -1, 0.2)
		end
		local vyBefore = s.vy
		if math.floor(s.time*60) % 120 == 0 then local p=s:attitude() print(string.format("t%.0f z%.0f h%.1f vy%.1f kt%.0f p%.1f thr%.2f trim%.2f cmd%.2f", s.time, s.pz, h, s.vy, kts, p, s.ctl.throttle, s.ctl.trim, s.ctl.pitch)) end
		local r2 = s:frame()
		if not tdz and r2.wheelsOnGround > 0 then
			tdz = s.pz
			td = vyBefore * U.FPM_PER_MPS
		end
		if tdz and s:groundSpeed() < 0.5 then
			stopz = s.pz
			break
		end
	end
	return s, tdz, td, stopz
end


land(Registry.get("atlas400"))
