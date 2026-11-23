--!nonstrict
-- The same offline flight checks for every aircraft in the registry, with limits taken
-- from each aircraft's own speeds. A new aircraft must pass all of these.
local Sim = require("./SimHarness")
local U = require("../src/shared/Units")
local Assist = require("../src/shared/Assist")
local FM = require("../src/shared/FlightModel")
local Registry = require("../src/shared/AircraftRegistry")

local RUNWAY_M = 2600 -- the shorter of the two runways (Ridgeview)

local function takeoff(cfg, opts)
	opts = opts or {}
	local s = Sim.new(cfg, { enginesRunning = true, flaps = 3 })
	s:settleOnGround()
	s.ctl.flaps = 3
	for _ = 1, 120 do
		s:frame()
	end
	s.ctl.throttle = 1
	local x0, z0 = s.px, s.pz
	local lift, maxGroundPitch = nil, 0
	local vr = opts.vr or cfg.speeds.rotate
	for _ = 1, 60 * 120 do
		local r = s.model.result
		local p, b, h = s:attitude()
		local kts = r.ias * U.KTS_PER_MPS
		if kts > vr then
			s.ctl.pitch = math.clamp((9 - p) * 0.15 - s.env.wx * 1.5, -1, 1)
		end
		if r.onGround then
			local hdgErr = ((h + 540) % 360) - 180
			s.ctl.yaw = math.clamp(-hdgErr * 0.3 - (s.px - x0) * 0.02, -1, 1)
			maxGroundPitch = math.max(maxGroundPitch, p)
		else
			s.ctl.yaw = 0
			s.ctl.roll = math.clamp(-b * 0.05, -1, 1)
		end
		s:frame()
		if not lift and s.model.result.wheelsOnGround == 0 and s.py > Sim.restHeight(cfg) + 3 then
			lift = { dist = math.abs(s.pz - z0), kts = kts, t = s.time }
		end
		if lift and s.time > lift.t + 20 then
			break
		end
	end
	return s, lift, maxGroundPitch
end

-- Pitch at which the tail touches the runway, rotating about the main wheels.
local function tailStrikePitch(cfg)
	local rest = Sim.restHeight(cfg)
	local mainZ = -math.huge
	for _, u in cfg.gear.units do
		if u.brakes then
			mainZ = math.max(mainZ, u.pos[3])
		end
	end
	local best = 90
	for _, hp in cfg.hullPoints do
		if hp[1] == 0 and hp[3] > mainZ + 1 then
			best = math.min(best, math.deg(math.atan((rest + hp[2]) / (hp[3] - mainZ))))
		end
	end
	return best
end

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

return { name = "Fleet: every aircraft", run = function(T)
	for _, id in Registry.order do
		local cfg = Registry.get(id)
		local name = cfg.displayName

		T.test(name .. ": parked, settles level on its gear", function()
			local s = Sim.new(cfg, { enginesRunning = true, flaps = 1 })
			s:settleOnGround()
			s.ctl.parkingBrake = true
			for _ = 1, 600 do
				s:frame()
			end
			local p = s:attitude()
			T.check(s:isFinite())
			T.check(s:groundSpeed() < 0.1, "creep " .. s:groundSpeed())
			T.between(p, -1.5, 2.0, "pitch on gear")
			for _, g in s.model.gears do
				T.check(g.onGround and g.compression < g.cfg.travel, g.cfg.name .. " within travel")
			end
		end)

		T.test(name .. ": takeoff near Vr, fits the 2,600 m runway, no tail strike", function()
			local s, lift, maxP = takeoff(cfg)
			T.check(lift ~= nil, "never lifted off")
			T.between(lift.kts, cfg.speeds.rotate - 5, cfg.speeds.rotate + 30, "liftoff kt")
			T.check(lift.dist < RUNWAY_M * 0.85, string.format("takeoff roll %.0f m", lift.dist))
			T.check(maxP < tailStrikePitch(cfg), string.format("pitch on ground %.1f vs tail strike %.1f", maxP, tailStrikePitch(cfg)))
			T.check(s.vy > 4, "climbing " .. s.vy)
			T.check(s:isFinite())
		end)

		T.test(name .. ": approach and landing at Vref, gentle touchdown, stops on the runway", function()
			local s, tdz, td, stopz = land(cfg)
			T.check(tdz ~= nil, "never touched down")
			T.check(td > -600, string.format("touchdown %.0f fpm", td))
			T.check(stopz ~= nil, "never stopped")
			-- the glide path aims 300 m past the threshold, which is at z = 300
			T.check(300 - stopz < RUNWAY_M, string.format("stopped %.0f m past the threshold (touchdown %.0f m)", 300 - stopz, 300 - tdz))
			for cname, c in s.model.damage.components do
				T.check(c.state == "normal", cname .. " damaged on a normal landing")
			end
		end)

		T.test(name .. ": assisted hands-off cruise is steady for 3 minutes", function()
			-- Fixed power, hands off: auto-trim must settle into a steady path (no phugoid
			-- growth, no spiral). A steady gentle climb or descent is fine.
			local cruise = cfg.speeds.cruise * U.MPS_PER_KT
			local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = 1500, speed = cruise })
			local a = Assist.new("assisted")
			a.autoTrim = 0.1
			local raw = FM.newControls()
			raw.throttle, raw.gearDown, raw.flaps = 0.55, false, 1
			s.ctl.gearDown = false
			local minVy, maxVy, maxBank = 1e9, -1e9, 0
			for _ = 1, 60 * 180 do
				s:prepareEnv()
				Assist.apply(a, raw, s.ctl, s.env, s.model, 1 / 60)
				s:frame()
				if s.time > 60 then
					minVy = math.min(minVy, s.vy)
					maxVy = math.max(maxVy, s.vy)
				end
				local _, b = s:attitude()
				maxBank = math.max(maxBank, math.abs(b))
			end
			T.check(s:isFinite())
			T.check(maxVy - minVy < 3, string.format("vertical speed wanders %.1f m/s", maxVy - minVy))
			T.check(math.abs(maxVy) < 10 and math.abs(minVy) < 10, "steep path")
			T.check(maxBank < 5, "bank wander " .. maxBank)
		end)

		T.test(name .. ": roll rate fits its size", function()
			local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = 1500, speed = cfg.speeds.cruise * U.MPS_PER_KT })
			s.ctl.gearDown = false
			s.ctl.throttle = 0.55
			local maxp = 0
			for _ = 1, 60 * 4 do
				s.ctl.roll = 1
				s:frame()
				local _, _, bz = Sim.mulMtV(s.R, s.wx, s.wy, s.wz)
				maxp = math.max(maxp, -bz)
			end
			local big = cfg.mass > 150000
			T.between(math.deg(maxp), if big then 6 else 10, if big then 22 else 32, "roll rate deg/s")
		end)

		T.test(name .. ": stalls with full back stick and recovers", function()
			local alt = 2500
			local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = alt, speed = cfg.speeds.vref * 0.85 * U.MPS_PER_KT * 1.3 })
			s.ctl.gearDown = false
			s.ctl.throttle = 0
			local stalled, minAlt, releaseAlt = false, 1e9, nil
			for _ = 1, 60 * 80 do
				if s.time < 25 then
					s.ctl.pitch = 1
				else
					releaseAlt = releaseAlt or s.py
					local p = s:attitude()
					s.ctl.throttle = 1
					local target = if s.time < 34 then -3 else 5
					s.ctl.pitch = math.clamp((target - p) * 0.08 - s.env.wx * 1.2, -1, 1)
				end
				local r = s:frame()
				if r.stall then
					stalled = true
				end
				if releaseAlt then
					minAlt = math.min(minAlt, s.py)
				end
			end
			T.check(stalled, "should stall")
			T.check(not s.model.result.stall, "should be recovered")
			-- height lost after the pilot releases the stick and adds power
			T.check((releaseAlt - minAlt) < 700, "recovery height loss " .. (releaseAlt - minAlt))
			T.check(s:isFinite())
		end)

		T.test(name .. ": an outboard engine failure on climb-out is controllable", function()
			local s = Sim.new(cfg, { enginesRunning = true, flaps = 3, gearDown = false, y = 400, speed = (cfg.speeds.v2 + 10) * U.MPS_PER_KT })
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
			T.check(s.py > 400, "still climbing")
		end)
	end
end }
