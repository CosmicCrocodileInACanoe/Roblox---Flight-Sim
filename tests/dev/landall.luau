local Sim = require("../SimHarness")
local U = require("../../src/shared/Units")
local Registry = require("../../src/shared/AircraftRegistry")
local FLARE = 3
local function land(cfg)
	local dist = 3000
	local gsA = math.rad(3)
	local rest = Sim.restHeight(cfg)
	local vapp = cfg.speeds.vref + 5
	local s = Sim.new(cfg, { enginesRunning = true, flaps = 5, gearDown = true, x = 0, z = dist, y = rest + dist * math.tan(gsA), speed = vapp * U.MPS_PER_KT, headingDeg = 0 })
	s.ctl.flaps = 5
	local trim, thr = 0.5, 0.4
	local tdz, stopz, td
	local appPitch, flareP, bias = 0, nil, 0
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
				-- flare like a pilot: power to idle, raise the nose a few degrees, hold it
				vsT = nil
				s.ctl.throttle = 0
			end
			-- two loops: vertical-speed error -> pitch target, pitch error -> elevator
			local p = s:attitude()
			local pitchT
			if vsT then
				-- PI: the bias learns the pitch this aircraft needs on the glide path
				bias = math.clamp(bias + (vsT - s.vy) * 0.25 / 60, -8, 8)
				pitchT = math.clamp(bias + (vsT - s.vy) * 0.8, -8, 12)
				appPitch = p
			else
				flareP = flareP or (appPitch + FLARE)
				pitchT = flareP
			end
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


for _, id in Registry.order do
	local s, tdz, td, stopz = land(Registry.get(id))
	print(id, string.format("td %.0f fpm at %.0f m past thr, stop %.0f m", td or 0, 300 - (tdz or 0), 300 - (stopz or 0)))
end
