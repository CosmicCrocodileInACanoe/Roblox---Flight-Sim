--!nonstrict
-- Emergency response and sinking (src/shared/Rescue.luau): who comes to a crash, how a
-- wreck or a ditched landplane sinks, the life rafts, and the water starts offered to
-- seaplanes and amphibians. The sinking runs through the same FlightModel the game uses.
local Rescue = require("../src/shared/Rescue")
local Registry = require("../src/shared/AircraftRegistry")
local Selection = require("../src/shared/Selection")
local Airports = require("../src/shared/Airports")
local WorldGen = require("../src/shared/WorldGen")
local Sim = require("./SimHarness")
local Units = require("../src/shared/Units")

local function roles(plan)
	local out = {}
	for _, u in plan do
		out[u.role] = (out[u.role] or 0) + u.count
	end
	return out
end

-- Run a level aircraft floating at rest through `seconds` of sinking; returns the CoM
-- height (m above the real surface) sampled at each whole second.
local function sinkRun(cfg, kind, seconds, wreck)
	local h0 = Rescue.floatHeight(cfg)
	local half, full = Rescue.sinkDepths(cfg)
	local s = Sim.new(cfg, { enginesRunning = false, flaps = 1, gearDown = false, y = h0, water = true })
	s.wreck = wreck
	local heights = {}
	local frames = math.floor(seconds * 60)
	local maxTilt = 0
	for f = 1, frames do
		s.sinkOffset = Rescue.sinkOffset(kind, s.time, half, full)
		s:frame()
		local pitch, bank = s:attitude()
		maxTilt = math.max(maxTilt, math.abs(pitch), math.abs(bank))
		if f % 60 == 0 then
			heights[f // 60] = s.py
		end
	end
	return heights, h0, half, full, maxTilt
end

return { name = "Emergency response and sinking", run = function(T)
	T.test("land crashes bring fire trucks, ambulances and police; the sea brings boats and helicopters", function()
		local land = roles(Rescue.plan(Rescue.LAND_CRASH))
		T.check(land.fireTruck >= 1 and land.ambulance >= 1 and land.police >= 1, "fire, ambulance, police")
		T.check(not land.rescueBoat and not land.helicopter, "no boats on land")
		local sea = roles(Rescue.plan(Rescue.WATER_CRASH))
		T.check(sea.rescueBoat >= 1 and sea.helicopter >= 1, "boats and helicopters")
		T.check(not sea.fireTruck, "no trucks at sea")
		local ditch = roles(Rescue.plan(Rescue.DITCH))
		T.check(ditch.rescueBoat >= 1 and ditch.ferry >= 1, "rescue boats and a ferry for the passengers")
	end)

	T.test("every passenger is off a ditched aircraft before it goes under", function()
		local t = Rescue.allAboardTime(Rescue.plan(Rescue.DITCH))
		T.check(t < Rescue.SINK.ditchFullS - 5, string.format("all aboard at %.0f s", t))
		for _, n in { 1, 2, 6, 70, 180, 550 } do
			local sum = 0
			local rafts = Rescue.rafts(n)
			T.check(#rafts >= 1 and #rafts <= 4, "1 to 4 rafts")
			for _, share in rafts do
				T.check(share >= 0)
				sum += share
			end
			T.check(sum == n, `{n} passengers shared out`)
		end
		for _, id in Registry.order do
			T.check(Rescue.passengers(Registry.get(id)) >= 1, id)
		end
	end)

	T.test("sink timeline: ditching half under at 20 s, gone at 60 s; a wreck floats first", function()
		local half, full = 2, 10
		T.near(Rescue.sinkOffset("ditch", 0, half, full), 0, 1e-9)
		T.near(Rescue.sinkOffset("ditch", 20, half, full), half, 1e-9)
		T.near(Rescue.sinkOffset("ditch", 60, half, full), full, 1e-9)
		T.near(Rescue.sinkOffset("water_crash", 5, half, full), 0, 1e-9, "a wreck floats for a moment")
		T.near(Rescue.sinkOffset("water_crash", 60, half, full), full, 1e-9)
		for _, kind in { "ditch", "water_crash" } do
			local last = -1
			for t = 0, 120, 0.5 do
				local o = Rescue.sinkOffset(kind, t, half, full)
				T.check(o >= last - 1e-9, kind .. " never rises")
				last = o
			end
			T.check(last > full, kind .. " keeps going down to the bottom")
		end
		T.check(Rescue.secondsLeft("ditch", 0) == 60 and Rescue.secondsLeft("ditch", 61) == 0)
	end)

	T.test("sink depths make sense for every aircraft; seaplanes float on their floats", function()
		for _, id in Registry.order do
			local cfg = Registry.get(id)
			local half, full = Rescue.sinkDepths(cfg)
			T.check(half > 0 and full > half, id)
			T.check(full - Rescue.floatHeight(cfg) >= Rescue.topHeight(cfg), id .. ": fully under means the fin too")
			if Rescue.isWaterCapable(cfg) then
				T.check(Rescue.waterRestHeight(cfg) > 0, id .. " floats with its CoM above the water")
			end
		end
		T.check(Rescue.isWaterCapable(Registry.get("puffin")) and Rescue.isWaterCapable(Registry.get("rainmaker")))
		T.check(not Rescue.isWaterCapable(Registry.get("meridian200")))
	end)

	T.test("a ditched airliner settles half under by 20 s and is completely under by 60 s", function()
		for _, id in { "meridian200", "kestrel72", "meadowlark4" } do
			local cfg = Registry.get(id)
			local hs, h0, half, full, tilt = sinkRun(cfg, "ditch", 62, false)
			local top = Rescue.topHeight(cfg)
			T.between(hs[20], h0 - half - 1.2, h0 - half + 1.2, id .. " at 20 s follows the half-way surface")
			T.check(hs[20] + top > 0, id .. " still partly above the water at 20 s")
			T.check(hs[62] + top < 0.5, string.format("%s completely under after 60 s (top %.1f m)", id, hs[62] + top))
			T.check(tilt < 35, id .. " sinks roughly level (degrees)")
			for t = 1, 62 do
				T.check(hs[t] == hs[t], id .. " stays finite")
			end
		end
	end)

	T.test("a wreck in the sea floats for a while, then sinks within 60 s", function()
		local cfg = Registry.get("meridian200")
		local hs, h0, _, full = sinkRun(cfg, "water_crash", 62, true)
		T.between(hs[6], h0 - 1.2, h0 + 1.2, "floating at 6 s")
		T.check(hs[62] + Rescue.topHeight(cfg) < 0.5, "under by 60 s")
		T.between(hs[62], h0 - full - 2, h0 - full + 2, "following the surface down")
		-- the amphibian too, once it is wrecked
		local am = Registry.get("rainmaker")
		local ha = sinkRun(am, "water_crash", 62, true)
		T.check(ha[62] + Rescue.topHeight(am) < 0.5, "a wrecked amphibian sinks too")
	end)

	T.test("start points keep the drive (or sail) on good ground", function()
		-- land east of x = 0, sea west of it
		local function land(x, _z)
			return x > 0
		end
		local sx, sz, a = Rescue.findStart(land, 500, 0, 2000, math.pi, 100)
		T.check(sx ~= nil and sz ~= nil and a ~= nil, "found one")
		for f = 0, 1, 0.05 do
			T.check(land(500 + (sx - 500) * f, sz * f), "every point of the drive is on land")
		end
		local none = Rescue.findStart(function()
			return false
		end, 0, 0, 1000, 0)
		T.check(none == nil, "nowhere to come from")
		for i = 1, 6 do
			local dx, dz = Rescue.slot(i, 6, 100, 0)
			T.near(math.sqrt(dx * dx + dz * dz), 100, 1e-6, "slots on the ring")
			T.check(dx > -1, "slots face the way the crews come in")
		end
	end)

	T.test("seaplanes and amphibians can start on the water; landplanes can't", function()
		for _, id in Registry.order do
			local cfg = Registry.get(id)
			for _, ap in Airports.order do
				local found
				for _, s in Selection.spawnList(ap, cfg, "free") do
					if s.kind == "water" then
						found = s
					end
				end
				if Rescue.isWaterCapable(cfg) then
					T.check(found ~= nil, `{id} offered a water start at {ap}`)
					T.check(WorldGen.meshHeight(found.x, found.z) < WorldGen.SEA_LEVEL - 25, "in deep water")
					T.check(Selection.findWaterSpawn(found.id) == found, "the server finds it by id")
					T.check(Selection.resolveSpawn(found.id, ap, cfg, "free").id == found.id, "and accepts it")
					T.check(string.find(Selection.spawnLabel(found), "water") ~= nil)
				else
					T.check(found == nil, `{id} has no water start`)
					T.check(Selection.resolveSpawn(ap .. "-water", ap, cfg, "free").kind == "runway", "asked anyway: a runway")
				end
			end
		end
	end)

	T.test("a seaplane spawned on the water floats there with no ditching", function()
		for _, id in { "puffin", "rainmaker" } do
			local cfg = Registry.get(id)
			local s = Sim.new(cfg, { enginesRunning = true, flaps = 2, gearDown = false, y = Rescue.waterRestHeight(cfg), water = true })
			local wet = 0
			for _ = 1, 600 do
				local r = s:frame()
				if r.inWater then
					wet += 1
				end
			end
			T.check(wet == 0, id .. " floats on its floats, not its fuselage")
			T.between(s.py, Rescue.waterRestHeight(cfg) - 0.6, Rescue.waterRestHeight(cfg) + 0.6, id .. " at rest height")
			local _ = Units
		end
	end)
end }
