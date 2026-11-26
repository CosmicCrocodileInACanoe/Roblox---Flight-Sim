--!nonstrict
local Airports = require("../src/shared/Airports")
local WorldGen = require("../src/shared/WorldGen")
local Mission = require("../src/shared/Mission")
local Units = require("../src/shared/Units")

return { name = "World, airports, missions", run = function(T)
	T.test("airport ground is flat under every runway, taxiway, apron and gate", function()
		for _, id in Airports.order do
			local l = Airports.layout(id)
			local worst = 0
			for a = -1, 1, 0.02 do
				for c = -1, 1, 0.05 do
					local x, z = Airports.fromRunway(l, a * (l.halfLen + 600), c * (math.abs(l.terminalFar) + 500))
					worst = math.max(worst, WorldGen.meshHeight(x, z) - (l.y - 4))
				end
			end
			T.check(worst <= 0.01, id .. " terrain pokes through by " .. worst)
		end
	end)
	T.test("runways are above sea level", function()
		for _, id in Airports.order do
			local l = Airports.layout(id)
			T.check(l.y > 5)
			for _, e in l.ends do
				T.check(WorldGen.height(e.thx, e.thz) > 0, id .. " threshold over water")
			end
		end
	end)
	T.test("cities are distinct and airports are 20-30 km apart", function()
		local a, b = Airports.layout("HBR"), Airports.layout("RDV")
		local dKm = math.sqrt((a.cx - b.cx) ^ 2 + (a.cz - b.cz) ^ 2) * Units.METERS_PER_STUD / 1000
		T.between(dKm, 20, 30, "distance")
		T.check(#WorldGen.cities >= 2)
	end)
	T.test("final approach paths (7.5 km, 3 deg) clear the terrain", function()
		for _, id in Airports.order do
			local l = Airports.layout(id)
			for _, e in l.ends do
				for dM = 500, 7500, 250 do
					local d = dM * Units.STUDS_PER_METER
					local x, z = e.thx - e.dx * d, e.thz - e.dz * d
					local pathY = Airports.glidePathY(l, dM)
					local clearance = (pathY - WorldGen.meshHeight(x, z)) * Units.METERS_PER_STUD
					-- 60 m far out; closer in, at least half the path's own height above the field
					local need = math.min(60, 0.5 * dM * math.tan(math.rad(3)))
					T.check(clearance > need, string.format("%s rwy %s at %d m: clearance %.0f m", id, e.ident, dM, clearance))
				end
			end
		end
	end)
	T.test("gates are on the apron side and face the taxiway", function()
		for _, id in Airports.order do
			local l = Airports.layout(id)
			for _, g in l.gates do
				local _, cross = Airports.toRunway(l, g.x, g.z)
				T.check(cross * l.side > 0, "gate on terminal side")
				local fx, fz = Units.xzFromHeading(g.heading)
				T.check(fx * l.rx * -l.side + fz * l.rz * -l.side > 0.99, "faces the runway")
			end
		end
	end)
	T.test("landing info: threshold distance and centreline offset", function()
		local l = Airports.layout("HBR")
		local e = l.ends[1]
		local x = e.thx + e.dx * 400 * Units.STUDS_PER_METER + l.rx * 5 * Units.STUDS_PER_METER
		local z = e.thz + e.dz * 400 * Units.STUDS_PER_METER + l.rz * 5 * Units.STUDS_PER_METER
		local info = Airports.landingInfo(l, x, z, e.heading)
		T.near(info.distanceFromThresholdM, 400, 0.5)
		T.near(info.centerlineOffsetM, 5, 0.5)
		T.check(info.ident == e.ident)
	end)
	T.test("mission state machine: gate to gate", function()
		local m = Mission.new("HBR", "RDV", Airports, "preflight")
		local o, d = Airports.layout("HBR"), Airports.layout("RDV")
		local tel = { x = o.gates[1].x, z = o.gates[1].z, altitudeM = 4, aglM = 0, groundSpeed = 0, verticalSpeed = 0, onGround = true, headingDeg = 180, enginesRunning = true, parkingBrake = false, crashed = false, time = 0 }
		Mission.update(m, tel)
		T.check(m.phase == "taxi", m.phase)
		local th = o.ends[1]
		tel.x, tel.z, tel.groundSpeed, tel.time = th.thx + th.dx * 600, th.thz, 40, 60
		Mission.update(m, tel)
		T.check(m.phase == "takeoff", m.phase)
		tel.onGround, tel.aglM, tel.time = false, 50, 90
		T.check(Mission.update(m, tel) == "takeoff")
		tel.altitudeM, tel.aglM, tel.x, tel.time = 1300, 1200, -30000, 200
		Mission.update(m, tel)
		T.check(m.phase == "cruise", m.phase)
		tel.x, tel.z, tel.time = d.cx - 40000, d.cz, 300
		Mission.update(m, tel)
		T.check(m.phase == "approach", m.phase)
		local e = d.ends[1]
		tel.x, tel.z, tel.aglM, tel.altitudeM, tel.time = e.thx - e.dx * 5000, e.thz - e.dz * 5000, 300, 480, 400
		Mission.update(m, tel)
		T.check(m.phase == "landing", m.phase)
		tel.x, tel.z, tel.onGround, tel.aglM, tel.headingDeg, tel.groundSpeed, tel.time = e.thx + e.dx * 1400, e.thz + e.dz * 1400, true, 0, e.heading, 65, 450
		T.check(Mission.update(m, tel) == "touchdown")
		T.check(m.touchdown.onRunway)
		T.near(m.touchdown.distanceFromThresholdM, 1400 * Units.METERS_PER_STUD, 1)
		tel.groundSpeed, tel.time = 8, 480
		Mission.update(m, tel)
		T.check(m.phase == "taxiToGate", m.phase)
		local g = d.gates[2]
		tel.x, tel.z, tel.groundSpeed, tel.parkingBrake, tel.time = g.x, g.z, 0, true, 600
		T.check(Mission.update(m, tel) == "complete")
	end)
	T.test("mission: leaving the ground from taxi still counts as a takeoff", function()
		local m = Mission.new("HBR", "RDV", Airports, "taxi")
		local tel = { x = 0, z = 0, altitudeM = 40, aglM = 30, groundSpeed = 50, verticalSpeed = 5, onGround = false, headingDeg = 90, enginesRunning = true, parkingBrake = false, crashed = false, time = 10 }
		T.check(Mission.update(m, tel) == "takeoff")
		T.check(m.phase == "climb", m.phase)
		T.check(m.airborneAt == 10, "airborneAt must be set so a touchdown can be detected")
	end)
	T.test("mission fails on a crash and on an off-airport landing", function()
		local m = Mission.new("HBR", "RDV", Airports, "cruise")
		m.airborneAt = 0
		local tel = { x = 0, z = 0, altitudeM = 300, aglM = 0, groundSpeed = 70, verticalSpeed = -5, onGround = true, headingDeg = 90, enginesRunning = true, parkingBrake = false, crashed = false, time = 10 }
		T.check(Mission.update(m, tel) == "offAirport")
		local m2 = Mission.new("HBR", "RDV", Airports, "cruise")
		tel.crashed = true
		T.check(Mission.update(m2, tel) == "failed")
	end)
	T.test("the map is about 70 x 45 km and every edge runs down into the sea", function()
		local b = WorldGen.BOUNDS
		local wKm = (b.maxX - b.minX) * Units.METERS_PER_STUD / 1000
		local dKm = (b.maxZ - b.minZ) * Units.METERS_PER_STUD / 1000
		T.check(wKm > 65 and dKm > 40, string.format("map is %.0f x %.0f km", wKm, dKm))
		for t = 0, 1, 0.01 do
			local x = b.minX + (b.maxX - b.minX) * t
			local z = b.minZ + (b.maxZ - b.minZ) * t
			for _, p in { { x, b.minZ }, { x, b.maxZ }, { b.minX, z }, { b.maxX, z } } do
				T.check(WorldGen.meshHeight(p[1], p[2]) < -5, string.format("land at the map edge (%d, %d)", p[1], p[2]))
			end
		end
		T.check(WorldGen.meshHeight(b.maxX + 50000, 0) < 0, "open sea past the edge")
	end)
	T.test("no cracks where the fine core meets the coarse outer ring", function()
		local inner = WorldGen.INNER
		local worst = 0
		local e = 0.001
		for x = inner.minX, inner.maxX, 53 do
			worst = math.max(worst, math.abs(WorldGen.meshHeight(x, inner.minZ + e) - WorldGen.meshHeight(x, inner.minZ - e)))
			worst = math.max(worst, math.abs(WorldGen.meshHeight(x, inner.maxZ - e) - WorldGen.meshHeight(x, inner.maxZ + e)))
		end
		for z = inner.minZ, inner.maxZ, 53 do
			worst = math.max(worst, math.abs(WorldGen.meshHeight(inner.minX + e, z) - WorldGen.meshHeight(inner.minX - e, z)))
			worst = math.max(worst, math.abs(WorldGen.meshHeight(inner.maxX - e, z) - WorldGen.meshHeight(inner.maxX + e, z)))
		end
		T.check(worst < 0.1, "seam step " .. worst)
	end)
	T.test("coarse mesh is continuous across its own cells", function()
		local b, cell = WorldGen.BOUNDS, WorldGen.COARSE
		local worst = 0
		for k = 1, 400 do
			local x = b.minX + cell * (1 + (k * 7) % 80)
			local z = b.minZ + cell * 3 + (k * 977) % (cell * 10)
			worst = math.max(worst, math.abs(WorldGen.meshHeight(x - 0.001, z) - WorldGen.meshHeight(x + 0.001, z)))
		end
		T.check(worst < 0.1, "cell step " .. worst)
	end)
	T.test("every town sits on flat ground above the sea", function()
		for _, c in WorldGen.cities do
			T.check(c.base > 5, c.id .. " base below sea")
			for _, o in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } } do
				local h = WorldGen.meshHeight(c.x + o[1] * c.radius, c.z + o[2] * c.radius)
				T.near(h, c.base, 1, c.id .. " ground")
			end
		end
	end)
	T.test("spawn points exist for every airport and kind", function()
		for _, id in Airports.order do
			local kinds = {}
			for _, s in Airports.spawnPoints(id) do
				kinds[s.kind] = true
				T.check(Airports.getSpawn(s.id) ~= nil)
			end
			T.check(kinds.gate and kinds.runway and kinds.approach)
			T.check(Airports.spawnPoints(id)[1].kind == "runway", id .. ": default start is not a runway")
		end
	end)
end }
