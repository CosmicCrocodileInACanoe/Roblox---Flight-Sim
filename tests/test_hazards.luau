--!nonstrict
-- Failures and weather hazards from the HUD's Events button.
local Hazards = require("../src/shared/Hazards")
local Damage = require("../src/shared/Damage")
local FlightModel = require("../src/shared/FlightModel")
local Registry = require("../src/shared/AircraftRegistry")
local Sim = require("./SimHarness")
local U = require("../src/shared/Units")

local function rngFrom(seed)
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

local function fresh(cfg)
	return FlightModel.new(cfg, { enginesRunning = true, breakApart = true })
end

local function allIds()
	local ids = {}
	for _, f in Hazards.FAILURES do
		table.insert(ids, f.id)
	end
	for _, w in Hazards.WEATHER do
		if w.id == "lightning" or w.id == "birds" then
			table.insert(ids, w.id)
		end
	end
	return ids
end

return { name = "Failures and hazards", run = function(T)
	local meridian = Registry.get("meridian200")

	T.test("every failure and strike applies to every aircraft without errors", function()
		for id, cfg in Registry.types do
			for _, hid in allIds() do
				local fm = fresh(cfg)
				local plan, why = Hazards.plan(hid, fm, rngFrom(7))
				T.check(plan ~= nil, `{id} {hid}: {why}`)
				T.check(type(plan.message) == "string" and #plan.message > 0, `{id} {hid}: message`)
				Hazards.apply(fm, plan)
			end
		end
	end)

	T.test("engine fire: the engine stops, burns and its pod is failed (smoke)", function()
		local fm = fresh(meridian)
		local plan = Hazards.plan("engineFire", fm, rngFrom(3))
		Hazards.apply(fm, plan)
		local failed = 0
		for i, e in fm.engines do
			if e.failed then
				failed += 1
				T.check(e.fire, "on fire")
				T.check(Damage.state(fm.damage, meridian.engines[i].component) == "failed", "pod failed")
			end
		end
		T.check(failed == 1, "exactly one engine")
	end)

	T.test("engine falls off: the component detaches and the server is told", function()
		local fm = fresh(meridian)
		Hazards.apply(fm, Hazards.plan("engineSeparation", fm, rngFrom(5)))
		local gone = 0
		for _, ec in meridian.engines do
			if Damage.state(fm.damage, ec.component) == "detached" then
				gone += 1
			end
		end
		T.check(gone == 1, "one engine detached")
		local sawDetach = false
		for _, ev in Damage.drainEvents(fm.damage) do
			if ev.state == "detached" then
				sawDetach = true
			end
		end
		T.check(sawDetach, "detach event queued for ReportDamage")
		T.check(fm:currentMass() < meridian.mass, "lighter without it")
	end)

	T.test("engine falls off even with break-apart off", function()
		local fm = FlightModel.new(meridian, { enginesRunning = true, breakApart = false })
		T.check(Damage.forceDetach(fm.damage, "LeftEngine"), "detached")
		T.check(Damage.state(fm.damage, "LeftEngine") == "detached")
		T.check(not Damage.forceDetach(fm.damage, "Fuselage"), "centre fuselage cannot come off")
	end)

	T.test("wing snaps: a break point section is lost and a section event is queued", function()
		local fm = fresh(meridian)
		Hazards.apply(fm, Hazards.plan("wingTip", fm, rngFrom(11)))
		local lost = fm.damage.components.LeftWing.lostFraction + fm.damage.components.RightWing.lostFraction
		T.check(lost > 0.2, "a big piece of wing gone")
		local section = false
		for _, ev in Damage.drainEvents(fm.damage) do
			if ev.state == "section" then
				section = true
			end
		end
		T.check(section, "section event for ReportSection")
	end)

	T.test("repeating a failure runs out gracefully", function()
		local fm = fresh(meridian)
		local rng = rngFrom(13)
		local applied = 0
		for _ = 1, 10 do
			local plan = Hazards.plan("engineSeparation", fm, rng)
			if plan then
				Hazards.apply(fm, plan)
				applied += 1
			end
		end
		T.check(applied == #meridian.engines, "one per engine")
		local plan, why = Hazards.plan("engineSeparation", fm, rng)
		T.check(plan == nil and type(why) == "string", "then a reason, not an error")
		for _ = 1, 5 do
			local p = Hazards.plan("controlJam", fm, rng)
			if p then
				Hazards.apply(fm, p)
			end
		end
		T.check(fm.failures.aileronJam ~= nil and fm.failures.elevatorJam ~= nil and fm.failures.rudderJam ~= nil, "all three jam")
		T.check(Hazards.plan("controlJam", fm, rng) == nil)
	end)

	T.test("random failure always finds something on a fresh aircraft", function()
		for seed = 1, 20 do
			local fm = fresh(meridian)
			local plan = Hazards.randomFailure(fm, rngFrom(seed))
			T.check(plan ~= nil, "seed " .. seed)
		end
	end)

	T.test("lightning flameout can be relit", function()
		local fm = fresh(meridian)
		local flamed = false
		for seed = 1, 20 do
			fm = fresh(meridian)
			local plan = Hazards.plan("lightning", fm, rngFrom(seed))
			for _, a in plan.actions do
				if a.op == "engineFlameout" then
					flamed = true
				end
			end
			if flamed then
				Hazards.apply(fm, plan)
				break
			end
		end
		T.check(flamed, "some strikes flame out an engine")
		T.check(not fm:enginesRunning() or fm.engines[1].running ~= fm.engines[2].running, "one engine out")
		fm:startEngines()
		local starting = false
		for _, e in fm.engines do
			starting = starting or e.starting or e.running
		end
		T.check(starting, "relight works")
	end)

	T.test("tornado wind: calm at the axis edge, peaks at the core, swirls counter-clockwise", function()
		local rc = Hazards.TORNADO.coreRadiusM
		local x1, _, z1 = Hazards.tornadoWind(rc, 100, 0)
		local x2, _, z2 = Hazards.tornadoWind(rc * 3, 100, 0)
		local x3, y3, z3 = Hazards.tornadoWind(rc * Hazards.TORNADO.influenceRadii + 1, 100, 0)
		local s1 = math.sqrt(x1 * x1 + z1 * z1)
		local s2 = math.sqrt(x2 * x2 + z2 * z2)
		T.check(s1 > 50, "strong at the core")
		T.check(s2 < s1 and s2 > 5, "weaker further out")
		T.check(x3 == 0 and y3 == 0 and z3 == 0, "nothing outside the influence radius")
		-- east of the axis (+x), counter-clockwise from above blows toward -z (north)
		T.check(z1 < 0, "counter-clockwise")
		T.check(x1 < 0, "inflow toward the axis")
		local _, up = Hazards.tornadoWind(5, 100, 0)
		T.check(up > 20, "updraft in the core")
		local _, upHigh = Hazards.tornadoWind(5, Hazards.TORNADO.topM * 1.4, 0)
		T.check(upHigh == 0, "nothing above the cloud base")
	end)

	T.test("strong wind ramps in and out, with a downburst halfway", function()
		local W = Hazards.WIND
		local x0 = Hazards.strongWind(0, 1, 0, 50, 0, 0, 0)
		local xm, ym = Hazards.strongWind(W.durationS / 2, 1, 0, 50, 0, 0, 0)
		local xe = Hazards.strongWind(W.durationS, 1, 0, 50, 0, 0, 0)
		T.check(x0 == 0 and xe == 0, "zero at the ends")
		T.near(xm, 50 * 0.514444, 0.5, "full speed in the middle")
		T.check(ym < -8, "sinking air in the downburst")
	end)

	T.test("tornado debris only hits inside the debris cloud", function()
		T.check(Hazards.tornadoHitRate(0) > 2)
		T.check(Hazards.tornadoHitRate(Hazards.TORNADO.coreRadiusM * 2) == 0)
	end)

	T.test("cruise with a snapped wing rolls toward the damaged side", function()
		local cfg = meridian
		local s = Sim.new(cfg, { y = 1500, speed = 140, gearDown = false, enginesRunning = true })
		s.ctl.throttle = 0.6
		s.ctl.gearDown = false
		for _ = 1, 60 do
			s:frame()
		end
		local plan = { id = "test", message = "", actions = { { op = "section", component = "LeftWing", section = "Outer", lost = 0.5, amount = 0.25 } } }
		Hazards.apply(s.model, plan)
		for _ = 1, 120 do
			s:frame()
		end
		local _, bank = s:attitude()
		T.check(s:isFinite(), "finite")
		T.check(bank < -5, string.format("rolls left (bank %.1f)", bank))
	end)

	T.test("flying through a tornado's core gets thrown about but stays finite", function()
		local cfg = meridian
		local s = Sim.new(cfg, { x = -600, y = 300, speed = 110, headingDeg = 90, gearDown = false, enginesRunning = true })
		s.ctl.throttle = 0.6
		s.ctl.gearDown = false
		local maxWind, maxVs = 0, 0
		for _ = 1, 60 * 12 do
			local wx, wy, wz = Hazards.tornadoWind(s.px, s.py, s.pz)
			s.wind = { x = wx, y = wy, z = wz }
			maxWind = math.max(maxWind, math.sqrt(wx * wx + wz * wz))
			maxVs = math.max(maxVs, math.abs(s.vy))
			s:frame()
		end
		T.check(s:isFinite(), "finite")
		T.check(maxWind > 40, "passed near the core")
		T.check(maxVs * U.FPM_PER_MPS > 1000, "big vertical speed swings")
	end)
end }
