--!nonstrict
local Engine = require("../src/shared/Engine")
local Gear = require("../src/shared/Gear")
local Grading = require("../src/shared/Grading")
local Assist = require("../src/shared/Assist")
local cfg = require("../src/shared/Aircraft/Meridian200")

return { name = "Engines, gear, grading", run = function(T)
	local ecfg = cfg.engines[1]
	T.test("engine start takes startTime and ends at idle", function()
		local e = Engine.new(ecfg, false)
		Engine.start(e)
		local t = 0
		while not e.running and t < 60 do
			Engine.update(e, 0, false, false, 1, 0, true, 0.1)
			t += 0.1
		end
		T.between(t, ecfg.startTime - 0.2, ecfg.startTime + 0.3, "start time")
		T.near(e.n1, ecfg.idleN1, 1.5, "idle N1")
	end)
	T.test("spool-up lag: 3 s after slamming the throttle thrust is not yet maximal", function()
		local e = Engine.new(ecfg, true)
		for _ = 1, 30 do
			Engine.update(e, 1, false, false, 1, 0, true, 0.1)
		end
		T.check(e.thrust < ecfg.maxThrust * 0.92, "should still be spooling")
		for _ = 1, 150 do
			Engine.update(e, 1, false, false, 1, 0, true, 0.1)
		end
		T.near(e.thrust, ecfg.maxThrust, ecfg.maxThrust * 0.03, "full thrust")
	end)
	T.test("reverse thrust only on the ground and is negative", function()
		local e = Engine.new(ecfg, true)
		for _ = 1, 100 do
			Engine.update(e, 1, true, false, 1, 30, true, 0.1)
		end
		T.check(e.thrust > 0, "reverser must not deploy in the air")
		for _ = 1, 100 do
			Engine.update(e, 1, true, true, 1, 30, true, 0.1)
		end
		T.check(e.thrust < 0, "reverse on ground")
	end)
	T.test("no fuel -> engine runs down", function()
		local e = Engine.new(ecfg, true)
		for _ = 1, 100 do
			Engine.update(e, 0.8, false, false, 1, 100, false, 0.1)
		end
		T.check(not e.running and e.thrust == 0)
	end)
	T.test("gear springs hold the static weight at the configured compression", function()
		local gs = Gear.derive(cfg.gear.units, cfg.mass, 9.80665)
		local total = 0
		for _, g in gs do
			local u = g.cfg
			local x = u.staticCompression * u.travel
			total += g.k * x * (1 + 3 * u.staticCompression ^ 2)
		end
		T.near(total, cfg.mass * 9.80665, cfg.mass * 9.80665 * 0.01, "static support")
	end)
	T.test("grading: smooth centreline landing in the zone scores A", function()
		local g = Grading.grade({ verticalSpeedFpm = -150, centerlineOffsetM = 1, distanceFromThresholdM = 400, bankDeg = 0.5, pitchDeg = 4, bounces = 0, runwayLengthM = 3000, crashed = false, damagedComponents = 0 })
		T.check(g.letter == "A", "got " .. g.letter)
	end)
	T.test("grading: hard landing with bounce scores poorly", function()
		local g = Grading.grade({ verticalSpeedFpm = -820, centerlineOffsetM = 8, distanceFromThresholdM = 1100, bankDeg = 4, pitchDeg = 3, bounces = 1, runwayLengthM = 3000, crashed = false, damagedComponents = 2 })
		T.check(g.score < 55, "score " .. g.score)
	end)
	T.test("grading: tail strike penalised; crash = 0", function()
		local base = { verticalSpeedFpm = -150, centerlineOffsetM = 1, distanceFromThresholdM = 400, bankDeg = 0, pitchDeg = 12, bounces = 0, runwayLengthM = 3000, crashed = false, damagedComponents = 0 }
		local g = Grading.grade(base)
		T.check(g.score < 75)
		base.crashed = true
		T.check(Grading.grade(base).score == 0)
	end)
	T.test("assist attitude helper: right bank positive, nose up positive", function()
		local p, b = Assist.attitude(-math.sin(math.rad(20)), math.cos(math.rad(20)), 0)
		T.near(math.deg(b), 20, 1e-6)
		local p2 = Assist.attitude(0, math.cos(math.rad(5)), -math.sin(math.rad(5)))
		T.near(math.deg(p2), 5, 1e-6)
		local _ = p
	end)
end }
