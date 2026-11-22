--!nonstrict
-- Offline 6-DOF flights using the game's FlightModel.
local Sim = require("./SimHarness")
local U = require("../src/shared/Units")
local Assist = require("../src/shared/Assist")
local FM = require("../src/shared/FlightModel")

local function freshCfg()
	-- reload a private copy so tests can tweak mass without leaking
	local c = require("../src/shared/Aircraft/Meridian200")
	return c
end

local function takeoff(cfg, opts)
	opts = opts or {}
	local s = Sim.new(cfg, { enginesRunning = true, flaps = opts.flaps or 3, wind = opts.wind })
	s:settleOnGround()
	s.ctl.flaps = opts.flaps or 3
	for _ = 1, 120 do
		s:frame()
	end
	s.ctl.throttle = 1
	local x0 = s.px
	local z0 = s.pz
	local lift = nil
	local maxLat = 0
	for _ = 1, 60 * 90 do
		local r = s.model.result
		local p, b, h = s:attitude()
		local kts = r.ias * U.KTS_PER_MPS
		if kts > (opts.vr or 140) then
			local target = 10
			s.ctl.pitch = math.clamp((target - p) * 0.15 - s.env.wx * 1.5, -1, 1)
		end
		-- keep the centreline with rudder/nosewheel (heading 0 = -z)
		if r.onGround then
			local hdgErr = ((h + 540) % 360) - 180
			s.ctl.yaw = math.clamp(-hdgErr * 0.3 - (s.px - x0) * 0.02, -1, 1)
			maxLat = math.max(maxLat, math.abs(s.px - x0))
		else
			s.ctl.yaw = 0
			s.ctl.roll = math.clamp(-b * 0.05, -1, 1)
		end
		s:frame()
		if not lift and s.model.result.wheelsOnGround == 0 and s.py > 5 then
			lift = { dist = math.abs(s.pz - z0), kts = kts, t = s.time }
		end
		if lift and s.time > lift.t + 20 then
			break
		end
	end
	return s, lift, maxLat
end

return { name = "Offline 6-DOF flight tests", run = function(T)
	local cfg = freshCfg()

	T.test("parked with parking brake: settles, no creep, no NaN", function()
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 1 })
		s:settleOnGround()
		s.ctl.parkingBrake = true
		for _ = 1, 600 do
			s:frame()
		end
		local p = s:attitude()
		T.check(s:isFinite())
		T.check(s:groundSpeed() < 0.1, "creep " .. s:groundSpeed())
		T.between(p, -1.5, 1.5, "pitch on gear")
		for _, g in s.model.gears do
			T.check(g.onGround and g.compression < g.cfg.travel, "gear within travel")
		end
	end)

	T.test("takeoff: rotates naturally, lifts off 135-165 kt within 700-1900 m", function()
		local s, lift = takeoff(cfg)
		T.check(lift ~= nil, "never lifted off")
		T.between(lift.kts, 135, 165, "liftoff speed")
		T.between(lift.dist, 700, 1900, "takeoff roll (m)")
		T.check(s.vy > 5, "climbing")
		T.check(s:isFinite())
	end)

	T.test("flaps matter: flaps-up takeoff needs a faster liftoff", function()
		local _, liftF = takeoff(cfg, { flaps = 3 })
		local _, lift0 = takeoff(cfg, { flaps = 1, vr = 160 })
		T.check(lift0 and liftF and lift0.kts > liftF.kts + 8, string.format("flaps2 %.0f vs flaps0 %.0f", liftF.kts, lift0 and lift0.kts or -1))
	end)

	T.test("mass matters: +25% mass gives a longer takeoff roll", function()
		local _, l1 = takeoff(cfg)
		local m0 = cfg.mass
		cfg.mass = m0 * 1.25
		local _, l2 = takeoff(cfg)
		cfg.mass = m0
		T.check(l2 and l1 and l2.dist > l1.dist * 1.15, string.format("%.0f vs %.0f", l1.dist, l2 and l2.dist or -1))
	end)

	T.test("crosswind 15 kt: aircraft can still be held on the centreline", function()
		local _, lift, maxLat = takeoff(cfg, { wind = { x = 7.7, y = 0, z = 0 } })
		T.check(lift ~= nil)
		-- 45 m runway: under 18 m keeps the main gear (track ~7 m) on the paved surface
		T.check(maxLat < 18, "lateral drift " .. maxLat)
	end)

	T.test("assisted hands-off cruise is stable for 3 minutes", function()
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = 1500 / U.METERS_PER_STUD * U.METERS_PER_STUD, speed = 128 })
		s.py = 1500
		local a = Assist.new("assisted")
		a.autoTrim = 0.1
		local raw = FM.newControls()
		raw.throttle, raw.gearDown, raw.flaps = 0.3, false, 1
		s.ctl.gearDown = false
		local minY, maxY, maxBank = 1e9, -1e9, 0
		for i = 1, 60 * 180 do
			s:prepareEnv()
			Assist.apply(a, raw, s.ctl, s.env, s.model, 1 / 60)
			s:frame()
			if s.time > 30 then
				minY = math.min(minY, s.py)
				maxY = math.max(maxY, s.py)
			end
			local _, b = s:attitude()
			maxBank = math.max(maxBank, math.abs(b))
		end
		T.check(s:isFinite())
		T.check(maxY - minY < 400, "altitude band " .. (maxY - minY))
		T.check(maxBank < 5, "bank wander " .. maxBank)
		local kts = s.model.result.ias * U.KTS_PER_MPS
		T.between(kts, 180, 330, "speed")
	end)

	T.test("roll rate at 250 kt is airliner-like (10-28 deg/s)", function()
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = 1500, speed = 128 })
		s.ctl.gearDown = false
		s.ctl.throttle = 0.55
		local maxp = 0
		for _ = 1, 60 * 4 do
			s.ctl.roll = 1
			s:frame()
			local _, _, bz = Sim.mulMtV(s.R, s.wx, s.wy, s.wz)
			maxp = math.max(maxp, -bz)
		end
		T.between(math.deg(maxp), 10, 28, "roll rate")
	end)

	T.test("control authority fades with speed: same aileron, half the speed, much less roll", function()
		local function rate(speed)
			local s = Sim.new(cfg, { enginesRunning = true, flaps = 3, gearDown = false, y = 1500, speed = speed })
			s.ctl.gearDown = false
			for _ = 1, 30 do
				s.ctl.roll = 1
				s:frame()
			end
			local _, _, bz = Sim.mulMtV(s.R, s.wx, s.wy, s.wz)
			return -bz
		end
		T.check(rate(60) < rate(120) * 0.7)
	end)

	T.test("stall: full back stick at idle stalls; releasing recovers with bounded height loss", function()
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = 2000, speed = 105 })
		s.ctl.gearDown = false
		s.ctl.throttle = 0
		local stalled, minAlt = false, 1e9
		for _ = 1, 60 * 70 do
			if s.time < 25 then
				s.ctl.pitch = 1
			else
				-- recovery: lower the nose to 0 deg pitch, full power, then hold 5 deg
				local p = s:attitude()
				s.ctl.throttle = 1
				local target = if s.time < 32 then -2 else 5
				s.ctl.pitch = math.clamp((target - p) * 0.08 - s.env.wx * 1.2, -1, 1)
			end
			local r = s:frame()
			if r.stall then
				stalled = true
			end
			minAlt = math.min(minAlt, s.py)
		end
		local r = s.model.result
		T.check(stalled, "should stall")
		T.check(not r.stall, "should be recovered")
		T.check((2000 - minAlt) < 700, "height loss " .. (2000 - minAlt))
		T.check(r.ias * U.KTS_PER_MPS > 150, "speed regained")
		T.check(s:isFinite())
	end)

	T.test("approach and landing: touchdown under 600 fpm, stops on a 3 km runway", function()
		local dist = 3000
		local gsA = math.rad(3)
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 5, gearDown = true, x = 0, z = dist, y = 3.9 + dist * math.tan(gsA), speed = 140 * U.MPS_PER_KT, headingDeg = 0 })
		s.ctl.flaps = 5
		local trim = 0.5
		local tdz, stopz, td
		for _ = 1, 60 * 150 do
			s:prepareEnv()
			local r = s.model.result
			local h = s.py - 3.9
			local target = math.max(0, s.pz * math.tan(gsA))
			local kts = r.ias * U.KTS_PER_MPS
			if not tdz then
				local vsT
				if h > 14 then
					vsT = -s:groundSpeed() * math.tan(gsA) + (target - h) * 0.12
					s.ctl.throttle = math.clamp(0.42 + (138 - kts) * 0.04, 0, 1)
				else
					vsT = -0.6 - h * 0.05
					s.ctl.throttle = math.clamp(0.42 + (132 - kts) * 0.04, 0, 1) * math.clamp((h - 5) / 8, 0, 1)
				end
				local cmd = math.clamp((vsT - s.vy) * 0.12 - s.env.wx * 1.5, -1, 1)
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
		T.check(tdz ~= nil, "never touched down")
		T.check(td > -600, "touchdown " .. td .. " fpm")
		T.check(stopz ~= nil, "never stopped")
		T.check((tdz - stopz) < 1800, "rollout " .. (tdz - stopz) .. " m")
		for name, c in s.model.damage.components do
			T.check(c.state == "normal", name .. " damaged on a normal landing")
		end
	end)

	T.test("hard landing (~1100 fpm) breaks landing gear", function()
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 5, gearDown = true, y = 3.9 + 8, speed = 70 })
		s.vy = -5.8
		for _ = 1, 120 do
			s:frame()
		end
		local broken = 0
		for _, name in { "LeftMainGear", "RightMainGear", "NoseGear" } do
			if s.model.damage.components[name].state ~= "normal" then
				broken += 1
			end
		end
		T.check(broken >= 2, "gear should be damaged")
	end)

	T.test("engine failure on climb-out is controllable with rudder", function()
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 3, gearDown = false, y = 400, speed = 80 })
		s.ctl.gearDown = false
		s.ctl.throttle = 1
		s.model:setFailure("engine1", true)
		local maxBank = 0
		for _ = 1, 60 * 40 do
			s:prepareEnv()
			local p, b = s:attitude()
			s.ctl.yaw = math.clamp(s.model.result.beta * 6 + s.env.wy * 2, -1, 1)
			s.ctl.roll = math.clamp(-b * 0.08 + s.env.wz * 0.5, -1, 1)
			s.ctl.pitch = math.clamp((6 - p) * 0.1 - s.env.wx, -1, 1)
			s:frame()
			maxBank = math.max(maxBank, math.abs(b))
		end
		T.check(maxBank < 20, "bank excursion " .. maxBank)
		T.check(s.py > 400, "still climbing on one engine")
	end)

	T.test("losing the left wing rolls the aircraft left (asymmetric lift)", function()
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = 1500, speed = 120 })
		s.ctl.gearDown = false
		s.ctl.throttle = 0.5
		local Damage = require("../src/shared/Damage")
		Damage.applyImpact(s.model.damage, "LeftWing", 40)
		for _ = 1, 90 do
			s:frame()
		end
		local _, b = s:attitude()
		T.check(b < -20, "bank " .. b)
	end)
end }
