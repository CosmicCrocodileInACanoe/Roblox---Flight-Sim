--!nonstrict
-- Autopilot: autoland for every aircraft (from awkward starts too), and the water
-- bomber's automatic scoop run (fly to the sea, land on the hull, fill up, climb out).
local Sim = require("./SimHarness")
local U = require("../src/shared/Units")
local AP = require("../src/shared/Autopilot")
local Registry = require("../src/shared/AircraftRegistry")

local RUNWAY = { id = "TEST 36", x = 0, z = 0, heading = 0, surfaceY = 0, lengthM = 2600 }

local function snapshot(s)
	local _, _, hdg = s:attitude()
	return { x = s.px, y = s.py, z = s.pz, vx = s.vx, vy = s.vy, vz = s.vz, heading = hdg }
end

-- Fly an autopilot job to the end. Returns the sim, the state and the touchdown record.
local function fly(cfg, ap, s, seconds)
	local td
	for _ = 1, 60 * seconds do
		s:prepareEnv()
		AP.step(ap, s.ctl, snapshot(s), s.env, s.model, 1 / 60)
		local vyb = s.vy
		local r = s:frame()
		if not td and r.wheelsOnGround > 0 then
			td = { fpm = vyb * U.FPM_PER_MPS, x = s.px, z = s.pz }
		end
		if ap.done or not s:isFinite() then
			break
		end
	end
	return td
end

local function checkLanded(T, cfg, s, ap, td, label)
	T.check(ap.phase == "stopped", string.format("%s: ended in phase %s", label, ap.phase))
	T.check(td ~= nil, label .. ": never touched down")
	T.check(td.fpm > -800, string.format("%s: touchdown %.0f fpm", label, td.fpm))
	-- on the runway: past the threshold, before the far end, on the centreline
	T.check(td.z < 50 and -s.pz < RUNWAY.lengthM, string.format("%s: touched down %.0f m, stopped %.0f m down the runway", label, -td.z, -s.pz))
	T.check(math.abs(s.px) < 15, string.format("%s: %.1f m off the centreline", label, s.px))
	T.check(s.ctl.parkingBrake, label .. ": parking brake set")
	for cname, c in s.model.damage.components do
		T.check(c.state == "normal", label .. ": " .. cname .. " " .. c.state)
	end
end

return { name = "Autopilot: autoland and auto refill", run = function(T)
	for _, id in Registry.order do
		local cfg = Registry.get(id)
		T.test(cfg.displayName .. ": autoland from 14 km out, off to the side and heading the wrong way", function()
			local spd = math.min(cfg.speeds.cruise, 250) * 0.8 * U.MPS_PER_KT
			local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, x = 2000, y = 700, z = 14000, headingDeg = 320, speed = spd })
			s.ctl.gearDown = false
			local ap = AP.newLand(cfg, RUNWAY, 0.2)
			local td = fly(cfg, ap, s, 900)
			checkLanded(T, cfg, s, ap, td, cfg.displayName)
		end)
	end

	for _, start in { { x = 3000, z = -6000, h = 0, name = "past the runway, flying away" }, { x = -8000, z = 2000, h = 90, name = "abeam, crossing" }, { x = 500, z = 4000, h = 180, name = "close in, facing away" } } do
		for _, id in { "meadowlark4", "celestia800", "arrowstar" } do
			local cfg = Registry.get(id)
			T.test(string.format("%s: autoland from %s", cfg.displayName, start.name), function()
				local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, x = start.x, y = 600, z = start.z, headingDeg = start.h, speed = math.min(cfg.speeds.cruise, 250) * 0.8 * U.MPS_PER_KT })
				s.ctl.gearDown = false
				local ap = AP.newLand(cfg, RUNWAY, 0.2)
				local td = fly(cfg, ap, s, 900)
				checkLanded(T, cfg, s, ap, td, cfg.displayName)
			end)
		end
	end

	T.test("autoland picks a close runway end it can reach without a big turn", function()
		local runways = {
			{ id = "A 36", x = 0, z = 0, heading = 0, surfaceY = 0, lengthM = 2600 },
			{ id = "A 18", x = 0, z = -2600, heading = 180, surfaceY = 0, lengthM = 2600 },
			{ id = "B 09", x = 60000, z = 0, heading = 90, surfaceY = 0, lengthM = 2600 },
		}
		-- south of A heading north: the north-bound end (its approach is right ahead)
		T.check(AP.pickRunway(runways, 0, 20000, 0).id == "A 36")
		-- north of A heading south: the south-bound end
		T.check(AP.pickRunway(runways, 0, -22000, 180).id == "A 18")
		-- near B: B
		T.check(AP.pickRunway(runways, 45000, 0, 90).id == "B 09")
	end)

	T.test("auto refill finds a long enough stretch of sea, and none when there is none", function()
		-- sea south of z = 5000 m only
		local function isSea(x, z)
			return z > 5000
		end
		local strip = AP.findScoopStrip(isSea, 0, 0, 0)
		T.check(strip ~= nil, "found the sea")
		local ux, uz = U.xzFromHeading(strip.heading)
		for d = 0, strip.lengthM, 100 do
			T.check(isSea(strip.x + ux * d, strip.z + uz * d), "the whole run is over water")
		end
		T.check(strip.z < 20000, "close by")
		T.check(AP.findScoopStrip(function() return false end, 0, 0, 0, 20000) == nil, "no sea, no strip")
	end)

	local cfg = Registry.get("rainmaker")
	for _, start in { { x = 2000, z = 14000, h = 320, name = "lined up from far out" }, { x = 500, z = 4000, h = 180, name = "close in, facing away" } } do
		T.test("Rainmaker auto refill: lands on the sea, fills up and climbs away (" .. start.name .. ")", function()
			local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, x = start.x, y = 500, z = start.z, headingDeg = start.h, speed = 130 * U.MPS_PER_KT, water = true })
			s.ctl.gearDown = false
			local ap = AP.newScoop(cfg, { x = 0, z = 0, heading = 0, surfaceY = 0, lengthM = 3500 }, 0.2)
			local skimmed = false
			for _ = 1, 60 * 900 do
				s:prepareEnv()
				AP.step(ap, s.ctl, snapshot(s), s.env, s.model, 1 / 60)
				s:frame()
				skimmed = skimmed or ap.phase == "skim"
				if ap.done or not s:isFinite() then
					break
				end
			end
			T.check(skimmed, "never landed on the water")
			T.check(ap.done, "did not finish: " .. ap.phase)
			T.near(s.model.water, cfg.waterTank.capacity, 1, "tank full")
			T.check(s.py > 150, string.format("climbed away (%.0f m)", s.py))
			T.check(s.ctl.gearDown == false, "gear stayed up on the water")
			T.check(not s.model.result.inWater, "hull never flooded")
			for cname, c in s.model.damage.components do
				T.check(c.state == "normal", cname .. " " .. c.state)
			end
		end)
	end
end }
