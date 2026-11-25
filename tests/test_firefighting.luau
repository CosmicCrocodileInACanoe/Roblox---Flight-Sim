--!nonstrict
-- The Rainmaker water bomber (scooping, dropping, refilling, flying heavy), wildfires
-- (sites, where water lands, putting them out), and the Arrowstar's Mach 2 top speed.
local Sim = require("./SimHarness")
local U = require("../src/shared/Units")
local Assist = require("../src/shared/Assist")
local FM = require("../src/shared/FlightModel")
local Registry = require("../src/shared/AircraftRegistry")
local Wildfire = require("../src/shared/Wildfire")
local WorldGen = require("../src/shared/WorldGen")
local Airports = require("../src/shared/Airports")
local Controls = require("../src/shared/Controls")
local GameConfig = require("../src/shared/GameConfig")

local function floatY(cfg)
	local y = math.huge
	for _, hp in cfg.hullPoints do
		if hp[5] == "float" then
			y = math.min(y, hp[2])
		end
	end
	return y
end

-- Level flight at `alt` metres, full throttle, for `seconds`. Returns the sim.
local function fullPower(cfg, alt, seconds)
	local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = alt, speed = cfg.speeds.cruise * U.MPS_PER_KT / math.sqrt(U.densityRatio(alt)) })
	local a = Assist.new("assisted")
	a.autoTrim = 0.1
	local raw = FM.newControls()
	raw.throttle, raw.gearDown, raw.flaps = 1, false, 1
	for _ = 1, 60 * seconds do
		s:prepareEnv()
		local p = s:attitude()
		local tgt = math.clamp((alt - s.py) * 0.02 - s.vy * 0.3, -5, 12)
		raw.pitch = math.clamp((tgt - p) * 0.15, -1, 1)
		Assist.apply(a, raw, s.ctl, s.env, s.model, 1 / 60)
		s:frame()
	end
	return s
end

return { name = "Firefighting and the Mach 2 jet", run = function(T)
	local cfg = Registry.get("rainmaker")

	T.test("water bomber: registered, in the menu, with a tank, a hull and wingtip floats", function()
		T.check(cfg ~= nil and cfg.unlocked, "registered and unlocked")
		T.check(table.find(Registry.order, "rainmaker") ~= nil, "in the menu order")
		T.check(cfg.waterTank and cfg.waterTank.capacity >= 5000, "carries at least 5 tonnes")
		T.check(cfg.water ~= nil and cfg.geometry.fuselage.boatHull ~= nil, "boat hull")
		local tips = 0
		for _, hp in cfg.hullPoints do
			if hp[5] == "float" and (hp[4] == "LeftFloat" or hp[4] == "RightFloat") then
				tips += 1
			end
		end
		T.check(tips == 2, "two wingtip floats")
		T.check(cfg.gear.fixed ~= true, "retractable wheels for runways")
	end)

	T.test("water bomber: a drop key is bound, and the assist passes it through", function()
		local found = false
		for _, b in Controls.KEYMAP do
			if b.action == "waterDrop" then
				found = b.kind == "hold" and #b.keys > 0
			end
		end
		T.check(found, "waterDrop is a hold binding")
		local raw, out = FM.newControls(), FM.newControls()
		raw.waterDrop = true
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = 300, speed = 60 })
		s:prepareEnv()
		Assist.apply(Assist.new("easy"), raw, out, s.env, s.model, 1 / 60)
		T.check(out.waterDrop == true, "Easy mode keeps the drop command")
	end)

	T.test("water bomber: skimming the sea fills the tank in under 20 s, then it climbs away loaded", function()
		local fy = floatY(cfg)
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 2, gearDown = false, y = -fy + 0.05, water = true })
		s.ctl.gearDown, s.ctl.flaps = false, 2
		for _ = 1, 60 * 6 do
			s:frame()
		end
		T.check(s.model.water == 0, "starts empty")
		local m0 = s.model:currentMass()
		s.ctl.throttle = 1
		-- a scoop run: hold the hull on the water at 60-80 kt with the nose level
		local fullAt, scoopStart
		for _ = 1, 60 * 90 do
			s:prepareEnv()
			local p, b = s:attitude()
			local kts = s.model.result.ias * U.KTS_PER_MPS
			local full = s.model.water >= cfg.waterTank.capacity
			local target = if full and kts > cfg.speeds.rotate + 5 then 8 elseif full then 3 else 1.5
			if not full then
				s.ctl.throttle = if kts > 75 then 0.55 else 1
			else
				s.ctl.throttle = 1
			end
			s.ctl.pitch = math.clamp((target - p) * 0.12 - s.env.wx * 1.5, -1, 1)
			s.ctl.roll = math.clamp(-b * 0.05, -1, 1)
			s:frame()
			if s.model.result.scooping and not scoopStart then
				scoopStart = s.time
			end
			if full and not fullAt then
				fullAt = s.time
			end
			if fullAt and s.time > fullAt + 40 then
				break
			end
		end
		T.check(scoopStart ~= nil, "never scooped")
		T.check(fullAt ~= nil, "tank never filled")
		T.check(fullAt - scoopStart < 20, string.format("scooping took %.1f s", fullAt - scoopStart))
		T.near(s.model:currentMass() - m0, cfg.waterTank.capacity, 60, "the water adds its weight")
		T.check(s.py > -fy + 20, string.format("climbed away with the load (height %.0f m)", s.py + fy))
		T.check(s.vy > 0.5, "still climbing " .. s.vy)
		for cname, c in s.model.damage.components do
			T.check(c.state == "normal", cname .. " damaged on the scoop run")
		end
	end)

	T.test("water bomber: no scooping when slow, and none while the doors are open", function()
		local fy = floatY(cfg)
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 2, gearDown = false, y = -fy + 0.05, water = true })
		s.ctl.gearDown = false
		s.ctl.throttle = 0.2
		for _ = 1, 60 * 10 do
			s:frame()
		end
		T.check(s.model.water == 0, "taxiing on the water does not fill the tank")
		T.check(not s.model.result.scooping)
	end)

	T.test("water bomber: holding drop empties a full tank in about 3 s, only in the air", function()
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 2, gearDown = false, y = 400, speed = 50 })
		s.model.water = cfg.waterTank.capacity
		local heavy = s.model:currentMass()
		s.ctl.throttle = 0.8
		s.ctl.waterDrop = true
		local emptyAt
		for _ = 1, 60 * 6 do
			s:frame()
			if s.model.water <= 0 and not emptyAt then
				emptyAt = s.time
			end
		end
		T.check(emptyAt ~= nil, "tank never emptied")
		T.between(emptyAt, 2, 4.5, "drop time")
		T.near(heavy - s.model:currentMass(), cfg.waterTank.capacity, 50, "lighter by the load")
		-- parked: the doors stay shut
		local g = Sim.new(cfg, { enginesRunning = false, gearDown = true, y = Sim.restHeight(cfg) })
		g:settleOnGround()
		g.model.water = 3000
		g.ctl.waterDrop = true
		g.env.refillAllowed = false
		for _ = 1, 60 * 2 do
			g:frame()
		end
		T.near(g.model.water, 3000, 1, "no drop on the ground")
	end)

	T.test("water bomber: parked at an airport the tank refills; elsewhere it does not", function()
		local g = Sim.new(cfg, { enginesRunning = false, gearDown = true, y = Sim.restHeight(cfg) })
		g:settleOnGround()
		g.env.refillAllowed = true
		for _ = 1, 60 * 5 do
			g:frame()
		end
		T.check(g.model.water > 1000, "refilling " .. g.model.water)
		T.check(g.model.result.refilling, "reports refilling")
		local h = Sim.new(cfg, { enginesRunning = false, gearDown = true, y = Sim.restHeight(cfg) })
		h:settleOnGround()
		h.env.refillAllowed = false
		for _ = 1, 60 * 5 do
			h:frame()
		end
		T.check(h.model.water == 0, "no refill away from an airport")
	end)

	T.test("water bomber: fully loaded it still holds height and speed in a hands-off cruise", function()
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = 600, speed = 140 * U.MPS_PER_KT })
		s.model.water = cfg.waterTank.capacity
		local a = Assist.new("assisted")
		a.autoTrim = 0.2
		local raw = FM.newControls()
		raw.throttle, raw.gearDown, raw.flaps = 0.5, false, 1
		local y0 = s.py
		for _ = 1, 60 * 60 do
			s:prepareEnv()
			Assist.apply(a, raw, s.ctl, s.env, s.model, 1 / 60)
			s:frame()
		end
		T.check(s.py > y0 - 50, string.format("holds height loaded (%.0f m)", s.py - y0))
		T.check(math.abs(s.vy) < 3, "steady " .. s.vy)
		T.check(s.model.result.ias * U.KTS_PER_MPS > 110, "keeps flying speed loaded")
		T.check(s:isFinite())
	end)

	-- Wildfires ------------------------------------------------------------------------
	T.test("wildfires: spread-out sites on wooded land, clear of airports and towns", function()
		local sites = Wildfire.sites()
		T.check(#sites >= Wildfire.ACTIVE + 2, "enough sites to move between: " .. #sites)
		for i, s in sites do
			T.check(WorldGen.height(s.x, s.z) > 20, "site " .. i .. " on dry land")
			T.near(s.y, WorldGen.meshHeight(s.x, s.z), 0.01, "site on the ground mesh")
			for _, id in Airports.order do
				local l = Airports.layout(id)
				T.check(not Airports.isInsideAirport(l, s.x, s.z), "site " .. i .. " inside " .. id)
			end
			for j, o in sites do
				if j ~= i then
					T.check((o.x - s.x) ^ 2 + (o.z - s.z) ^ 2 >= Wildfire.MIN_SPACING ^ 2, "sites too close")
				end
			end
			-- not too far from the sea, so a scoop-and-drop circuit is a few minutes
			local coastDist = math.abs(WorldGen.coastZ(s.x) - s.z) * U.METERS_PER_STUD
			T.check(coastDist < 40000, string.format("site %d is %.0f km from the coast", i, coastDist / 1000))
		end
		T.check(Wildfire.sites() == sites, "cached and deterministic")
	end)

	T.test("wildfires: dropped water lands ahead, short of a bomb's path, and low drops work best", function()
		local S = U.STUDS_PER_METER
		-- 40 m up at 60 m/s heading north (-z)
		local x, z = Wildfire.impactPoint(0, 40 * S, 0, 0, -60 * S, 0)
		local aheadM = -z / S
		T.near(x, 0, 1e-6, "no sideways drift")
		local bombM = 60 * math.sqrt(2 * 40 / U.G)
		T.check(aheadM > 20 and aheadM < bombM, string.format("lands %.0f m ahead (bomb %.0f m)", aheadM, bombM))
		T.check(Wildfire.dropEfficiency(30) == 1, "low drop: all of it counts")
		T.check(Wildfire.dropEfficiency(400) < 0.3, "from high up most of it blows away")
		T.check(Wildfire.footprintRadius(150) > Wildfire.footprintRadius(30), "higher drops spread wider")
		T.near(Wildfire.waterOnFire(1000, 0, 30), 1000, 1e-6, "a direct hit")
		T.check(Wildfire.waterOnFire(1000, Wildfire.RADIUS_M + 10, 30) > 0, "a near miss still helps")
		T.check(Wildfire.waterOnFire(1000, 500, 30) == 0, "a miss does nothing")
	end)

	T.test("wildfires: about one full load on target puts a fire out; left alone it flares up", function()
		local fire = Wildfire.newFire(Wildfire.sites()[1])
		T.check(not Wildfire.douse(fire, cfg.waterTank.capacity * 0.6), "one partial load is not enough")
		T.check(fire.burning and fire.strength < 0.6, "but it knocks it down")
		Wildfire.regrow(fire, 30)
		T.check(fire.strength > 0.5 and fire.strength <= 1, "grows back slowly")
		local out = Wildfire.douse(fire, cfg.waterTank.capacity)
		T.check(out and not fire.burning, "put out")
		T.check(not Wildfire.douse(fire, 1000), "an out fire stays out")
		local loads = Wildfire.WATER_TO_PUT_OUT / cfg.waterTank.capacity
		T.between(loads, 0.8, 2, "loads per fire")
	end)

	-- The Concorde-style jet ----------------------------------------------------------------
	T.test("Arrowstar: passes Mach 2 high up with the afterburners lit", function()
		local a = Registry.get("arrowstar")
		local s = fullPower(a, 11000, 240)
		local mach = s.model.result.mach
		T.check(mach > 1.9 and mach < 2.4, string.format("Mach %.2f at 11 km", mach))
		T.check(s.model.engines[1].afterburner > 0.9, "afterburner lit")
		T.check(s.model.fuel > 0, "fuel left")
		-- the server's speed sanity check must not reset it at Mach 2 (plus a 60 kt tailwind)
		local v = math.sqrt(s.vx * s.vx + s.vy * s.vy + s.vz * s.vz)
		T.check(v + 31 < GameConfig.limits.maxSpeed * 0.9, string.format("%.0f m/s vs the server limit %.0f", v, GameConfig.limits.maxSpeed))
	end)

	T.test("Arrowstar: passes Mach 2 from about 1,200 ft up", function()
		local a = Registry.get("arrowstar")
		local s = fullPower(a, 1200 * 0.3048, 240)
		local mach = s.model.result.mach
		T.check(mach > 1.9 and mach < 2.4, string.format("Mach %.2f at 1,200 ft", mach))
	end)

	T.test("airliners hit the sound barrier: an airliner tops out below Mach 0.95", function()
		local s = fullPower(Registry.get("meridian200"), 10000, 180)
		T.check(s.model.result.mach < 0.95, string.format("Mach %.2f", s.model.result.mach))
		T.check(s.model.engines[1].afterburner == 0, "no afterburner")
	end)

	T.test("afterburners stay off on an approach with the gear down", function()
		local a = Registry.get("arrowstar")
		local s = Sim.new(a, { enginesRunning = true, flaps = 2, gearDown = true, y = 500, speed = 85 })
		s.ctl.gearDown, s.ctl.throttle = true, 1
		for _ = 1, 60 * 5 do
			s:frame()
		end
		T.check(s.model.engines[1].afterburner == 0, "unlit on approach")
	end)
end }
