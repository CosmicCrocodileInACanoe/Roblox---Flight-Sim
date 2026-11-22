--!nonstrict
local Aero = require("../src/shared/Aero")
local Units = require("../src/shared/Units")
local FlightModel = require("../src/shared/FlightModel")
local cfg = require("../src/shared/Aircraft/Meridian200")

return { name = "Aerodynamics", run = function(T)
	local wing = cfg.aero.panels[1]
	T.test("lift coefficient is linear below stall", function()
		local cl1 = Aero.liftCoefficient(math.rad(2), 0.25, 5.19, math.rad(14.5), math.rad(4))
		local cl2 = Aero.liftCoefficient(math.rad(4), 0.25, 5.19, math.rad(14.5), math.rad(4))
		T.near(cl2 - cl1, 5.19 * math.rad(2), 1e-6, "slope")
	end)
	T.test("lift breaks down past the stall angle but stays non-zero (recoverable)", function()
		local atStall = Aero.liftCoefficient(math.rad(14.5), 0.25, 5.19, math.rad(14.5), math.rad(4))
		local deep = Aero.liftCoefficient(math.rad(22), 0.25, 5.19, math.rad(14.5), math.rad(4))
		T.check(deep < atStall * 0.75, "post-stall lift should drop clearly")
		T.check(deep > 0.4, "post-stall lift should not vanish")
	end)
	T.test("post-stall drag is far higher than attached-flow drag", function()
		local _, lin1, s1 = Aero.liftCoefficient(math.rad(4), 0.25, 5.19, math.rad(14.5), math.rad(4))
		local _, lin2, s2 = Aero.liftCoefficient(math.rad(25), 0.25, 5.19, math.rad(14.5), math.rad(4))
		local cd1 = Aero.dragCoefficient(math.rad(4), lin1, s1, 0.0085, 9.5, 0.8, 1)
		local cd2 = Aero.dragCoefficient(math.rad(25), lin2, s2, 0.0085, 9.5, 0.8, 1)
		T.check(cd2 > cd1 * 5, "drag ratio")
	end)
	T.test("panel force is zero at zero airspeed (no rotation authority at rest)", function()
		local out = Aero.newPanelResult()
		Aero.panel(wing, 0, 0, 0, 1.225, 0, 0, 0.3, 0, 0, 1, 1, out)
		T.check(out.fx == 0 and out.fy == 0 and out.fz == 0)
	end)
	T.test("panel force scales with airspeed squared (control authority)", function()
		local a, b = Aero.newPanelResult(), Aero.newPanelResult()
		Aero.panel(wing, 0, 0, -50, 1.225, 0, 0, 0, 0, 0, 1, 1, a)
		Aero.panel(wing, 0, 0, -100, 1.225, 0, 0, 0, 0, 0, 1, 1, b)
		T.near(b.lift / a.lift, 4, 0.01, "lift ratio")
	end)
	T.test("lift points up and drag points aft in level flight", function()
		local out = Aero.newPanelResult()
		local tail = cfg.aero.panels[3]
		Aero.panel(tail, 0, 0, -100, 1.225, 0, 0, 0.5, 0, 0, 1, 1, out)
		T.check(out.fy > 0, "lift up")
		T.check(out.fz > 0, "drag aft (+z)")
	end)
	T.test("ground effect reduces induced drag near the ground only", function()
		local f1 = Aero.groundEffect(2, 34)
		local f2 = Aero.groundEffect(40, 34)
		T.check(f1 < 0.9 and f2 == 1)
	end)
	T.test("ISA density decreases with altitude", function()
		T.near(Units.airDensity(0), 1.225, 1e-6)
		T.near(Units.airDensity(3000), 0.909, 0.005)
	end)
	T.test("heading conventions: 0 = -Z north, 90 = +X east", function()
		T.near(Units.headingFromXZ(0, -1), 0, 1e-9)
		T.near(Units.headingFromXZ(1, 0), 90, 1e-9)
		local x, z = Units.xzFromHeading(180)
		T.near(x, 0, 1e-9)
		T.near(z, 1, 1e-9)
	end)
	T.test("flight model output is finite for extreme/garbage states", function()
		local fm = FlightModel.new(cfg, { enginesRunning = true })
		local env = FlightModel.newEnv(cfg)
		local ctl = FlightModel.newControls()
		local cases = { { 0, 0, 0 }, { 300, -300, 300 }, { 0, -250, 0 }, { 1e-9, 1e-9, -1e-9 }, { 0, 0, 400 } }
		for _, c in cases do
			env.vax, env.vay, env.vaz = c[1], c[2], c[3]
			env.vgx, env.vgy, env.vgz = c[1], c[2], c[3]
			env.wx, env.wy, env.wz = 3, -2, 5
			local r = fm:step(env, ctl, 1 / 60)
			for _, v in { r.fx, r.fy, r.fz, r.mx, r.my, r.mz } do
				T.check(v == v and math.abs(v) < 1e12, "non-finite output")
			end
		end
		env.vax = 0 / 0
		local r = fm:step(env, ctl, 1 / 60)
		T.check(r.fault == true and r.fx == 0, "NaN input should be caught and zeroed")
	end)
	T.test("ailerons roll right, elevator pitches up, rudder yaws right (sign conventions)", function()
		local function moments(pitch, roll, yaw)
			local fm = FlightModel.new(cfg, { enginesRunning = true, gearDown = false })
			local env = FlightModel.newEnv(cfg)
			local ctl = FlightModel.newControls()
			ctl.gearDown = false
			env.vax, env.vay, env.vaz = 0, 0, -120
			env.vgx, env.vgy, env.vgz = 0, 0, -120
			env.altitude = 1000
			ctl.pitch, ctl.roll, ctl.yaw = pitch, roll, yaw
			local r
			for _ = 1, 60 do
				r = fm:step(env, ctl, 1 / 60)
			end
			return r.mx, r.my, r.mz
		end
		local mx0, my0, mz0 = moments(0, 0, 0)
		local mxP = moments(1, 0, 0)
		local _, _, mzR = moments(0, 1, 0)
		local _, myY = moments(0, 0, 1)
		T.check(mxP > mx0, "pitch up should increase +x moment (nose up)")
		T.check(mzR < mz0, "roll right should give negative z moment (right wing down)")
		T.check(myY < my0, "yaw right should give negative y moment")
	end)
end }
