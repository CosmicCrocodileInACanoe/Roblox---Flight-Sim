--!strict
-- Airport database and pure layout geometry (studs, world space; y up, compass
-- heading 0 = north = -Z, 90 = east = +X). The world builder, spawn system, mission
-- tracker and HUD all derive positions from these same functions, so a runway, its
-- gates and its approach path can never disagree.

local function req(name: string): any
	if script then
		return (require :: any)((script :: any).Parent[name])
	end
	return (require :: any)("./" .. name)
end
local Units = req("Units")

local SPM = Units.STUDS_PER_METER

local Airports = {}

-- Airport definitions. Lengths in metres, positions in studs.
-- `side` is which side of the runway (relative to `heading`) the terminal is on:
-- +1 = right of the heading direction, -1 = left.
Airports.list = {
	HBR = {
		id = "HBR",
		name = "Harbor City International",
		city = "Harbor City",
		elevation = 12, -- studs above sea level (top of pavement)
		runway = { center = { -44000, 2500 }, heading = 90, lengthM = 3000, widthM = 45, idents = { "09", "27" } },
		side = -1,
		gates = 6,
		gateSpacingM = 95,
		order = 1,
	},
	RDV = {
		id = "RDV",
		name = "Ridgeview Regional",
		city = "Ridgeview",
		elevation = 640,
		runway = { center = { 44000, -1500 }, heading = 80, lengthM = 2600, widthM = 45, idents = { "08", "26" } },
		side = 1,
		gates = 5,
		gateSpacingM = 95,
		order = 2,
	},
}

Airports.order = { "HBR", "RDV" }

-- Routes available for Airline mode (both directions).
Airports.routes = {
	{ from = "HBR", to = "RDV" },
	{ from = "RDV", to = "HBR" },
}

export type Layout = {
	id: string,
	cx: number, cz: number, y: number,
	ax: number, az: number, -- unit along runway heading
	rx: number, rz: number, -- unit to the right of the heading
	side: number,
	halfLen: number, halfWidth: number, -- studs
	lengthM: number,
	taxiOffset: number, -- studs (signed, toward terminal)
	apronNear: number, apronFar: number, apronHalfLen: number,
	terminalNear: number, terminalFar: number, terminalHalfLen: number,
	connectors: { number }, -- along-positions (studs) of runway-apron connectors
	gates: { { id: string, x: number, z: number, heading: number, along: number } },
	ends: { { ident: string, heading: number, thx: number, thz: number, dx: number, dz: number } },
}

local cache: { [string]: Layout } = {}

function Airports.layout(id: string): Layout
	local c = cache[id]
	if c then
		return c
	end
	local ap = Airports.list[id]
	assert(ap, "unknown airport " .. tostring(id))
	local rw = ap.runway
	local ax, az = Units.xzFromHeading(rw.heading)
	local rx, rz = Units.xzFromHeading(rw.heading + 90)
	local halfLen = rw.lengthM * 0.5 * SPM
	local side = ap.side
	local l: any = {
		id = id,
		cx = rw.center[1], cz = rw.center[2], y = ap.elevation,
		ax = ax, az = az, rx = rx, rz = rz, side = side,
		halfLen = halfLen, halfWidth = rw.widthM * 0.5 * SPM, lengthM = rw.lengthM,
		taxiOffset = side * 180 * SPM,
		apronNear = side * 225 * SPM, apronFar = side * 420 * SPM, apronHalfLen = 380 * SPM,
		terminalNear = side * 430 * SPM, terminalFar = side * 480 * SPM, terminalHalfLen = 320 * SPM,
		connectors = { -halfLen + 60 * SPM, -halfLen * 0.35, 0, halfLen * 0.35, halfLen - 60 * SPM },
		gates = {},
		ends = {},
	}
	-- Gates sit on the apron, noses pointing toward the taxiway (ready to taxi out).
	local n = ap.gates
	local spacing = ap.gateSpacingM * SPM
	local gateLateral = side * 340 * SPM
	local faceX, faceZ = -side * rx, -side * rz
	local gateHeading = Units.headingFromXZ(faceX, faceZ)
	for i = 1, n do
		local along = (i - (n + 1) / 2) * spacing
		table.insert(l.gates, {
			id = `{id}-G{i}`,
			x = l.cx + ax * along + rx * gateLateral,
			z = l.cz + az * along + rz * gateLateral,
			heading = gateHeading,
			along = along,
		})
	end
	-- Runway ends: landing threshold and landing direction for each ident.
	for k, ident in rw.idents do
		local heading = if k == 1 then rw.heading else (rw.heading + 180) % 360
		local dx, dz = Units.xzFromHeading(heading)
		table.insert(l.ends, {
			ident = ident,
			heading = heading,
			thx = l.cx - dx * halfLen,
			thz = l.cz - dz * halfLen,
			dx = dx,
			dz = dz,
		})
	end
	cache[id] = l
	return l
end

-- World (x, z) -> runway coordinates (along, cross) in studs.
function Airports.toRunway(l: Layout, x: number, z: number): (number, number)
	local px, pz = x - l.cx, z - l.cz
	return px * l.ax + pz * l.az, px * l.rx + pz * l.rz
end

function Airports.fromRunway(l: Layout, along: number, cross: number): (number, number)
	return l.cx + l.ax * along + l.rx * cross, l.cz + l.az * along + l.rz * cross
end

function Airports.isOnRunway(l: Layout, x: number, z: number, marginStuds: number?): boolean
	local along, cross = Airports.toRunway(l, x, z)
	local m = marginStuds or 0
	return math.abs(along) <= l.halfLen + m and math.abs(cross) <= l.halfWidth + m
end

-- Which runway end a landing aircraft with this heading is using, and how far past
-- its threshold (metres) the point (x, z) is, plus the centreline offset (metres).
function Airports.landingInfo(l: Layout, x: number, z: number, headingDeg: number)
	local best, bestDiff = l.ends[1], math.huge
	for _, e in l.ends do
		local diff = math.abs(((headingDeg - e.heading + 540) % 360) - 180)
		if diff < bestDiff then
			best, bestDiff = e, diff
		end
	end
	local px, pz = x - best.thx, z - best.thz
	local along = (px * best.dx + pz * best.dz) / SPM
	local _, cross = Airports.toRunway(l, x, z)
	return {
		ident = best.ident,
		distanceFromThresholdM = along,
		centerlineOffsetM = math.abs(cross) / SPM,
		headingError = bestDiff,
	}
end

function Airports.isInsideAirport(l: Layout, x: number, z: number): boolean
	local along, cross = Airports.toRunway(l, x, z)
	local side = l.side
	local lateral = cross * side
	return math.abs(along) <= l.halfLen + 400 and lateral >= -(l.halfWidth + 400) and lateral <= math.abs(l.terminalFar) + 400
end

function Airports.nearestGate(l: Layout, x: number, z: number)
	local best, bestD = nil, math.huge
	for _, g in l.gates do
		local d = math.sqrt((g.x - x) ^ 2 + (g.z - z) ^ 2)
		if d < bestD then
			best, bestD = g, d
		end
	end
	return best, bestD
end

-- Nearest airport to a world point, with distance (studs).
function Airports.nearest(x: number, z: number): (string, number)
	local bestId, bestD = "HBR", math.huge
	for id in Airports.list do
		local l = Airports.layout(id)
		local d = math.sqrt((l.cx - x) ^ 2 + (l.cz - z) ^ 2)
		if d < bestD then
			bestId, bestD = id, d
		end
	end
	return bestId, bestD
end

-- Glide path: altitude (studs, world Y) of a 3-degree path to the threshold of `endIndex`
-- at distance `distM` metres before the threshold (aiming 300 m past it).
function Airports.glidePathY(l: Layout, distBeforeThresholdM: number, angleDeg: number?): number
	local a = math.rad(angleDeg or 3)
	return l.y + (distBeforeThresholdM + 300) * math.tan(a) * SPM
end

export type SpawnPoint = {
	id: string,
	label: string,
	airport: string,
	kind: string, -- "gate" | "runway" | "approach" | "air"
	x: number, y: number, z: number,
	heading: number,
	speed: number, -- m/s
	enginesRunning: boolean,
	gearDown: boolean,
	flaps: number,
	throttle: number,
	pitchDeg: number,
}

-- All spawn points for an airport. Ground spawns give the CoM position at ground level;
-- the spawner adds the gear height.
function Airports.spawnPoints(id: string): { SpawnPoint }
	local l = Airports.layout(id)
	local ap = Airports.list[id]
	local out = {}
	for i, g in l.gates do
		table.insert(out, {
			id = `{id}-gate{i}`, label = `{ap.name}: Gate {i}`, airport = id, kind = "gate",
			x = g.x, y = l.y, z = g.z, heading = g.heading, speed = 0,
			enginesRunning = false, gearDown = true, flaps = 1, throttle = 0, pitchDeg = 0,
		})
	end
	for _, e in l.ends do
		local start = 90 * SPM -- metres past the threshold
		table.insert(out, {
			id = `{id}-rwy{e.ident}`, label = `{ap.name}: Runway {e.ident}`, airport = id, kind = "runway",
			x = e.thx + e.dx * start, y = l.y, z = e.thz + e.dz * start, heading = e.heading, speed = 0,
			enginesRunning = true, gearDown = true, flaps = 3, throttle = 0, pitchDeg = 0,
		})
	end
	for _, e in l.ends do
		local distM = 7500
		local d = distM * SPM
		table.insert(out, {
			id = `{id}-final{e.ident}`, label = `{ap.name}: 4 nm final, runway {e.ident}`, airport = id, kind = "approach",
			x = e.thx - e.dx * d, y = Airports.glidePathY(l, distM), z = e.thz - e.dz * d,
			heading = e.heading, speed = 145 * Units.MPS_PER_KT,
			enginesRunning = true, gearDown = true, flaps = 4, throttle = 0.45, pitchDeg = 2,
		})
	end
	return out
end

function Airports.findSpawn(spawnId: string): SpawnPoint?
	for id in Airports.list do
		for _, s in Airports.spawnPoints(id) do
			if s.id == spawnId then
				return s
			end
		end
	end
	return nil
end

-- Extra sandbox spawns not tied to a runway.
function Airports.sandboxSpawns(): { SpawnPoint }
	local l = Airports.layout("HBR")
	return {
		{
			id = "air-cruise", label = "In flight: cruise between the cities", airport = "HBR", kind = "air",
			x = l.cx + 12000, y = 2200 * SPM, z = l.cz - 2000, heading = 85, speed = 125,
			enginesRunning = true, gearDown = false, flaps = 1, throttle = 0.55, pitchDeg = 1,
		},
		{
			id = "air-crashtest", label = "Crash test: low pass over Harbor City", airport = "HBR", kind = "air",
			x = l.cx - 6000, y = 300 * SPM, z = l.cz - 9000, heading = 90, speed = 110,
			enginesRunning = true, gearDown = false, flaps = 1, throttle = 0.5, pitchDeg = 0,
		},
	}
end

function Airports.allSpawns(): { SpawnPoint }
	local out = {}
	for _, id in Airports.order do
		for _, s in Airports.spawnPoints(id) do
			table.insert(out, s)
		end
	end
	for _, s in Airports.sandboxSpawns() do
		table.insert(out, s)
	end
	return out
end

function Airports.getSpawn(spawnId: string): SpawnPoint?
	for _, s in Airports.allSpawns() do
		if s.id == spawnId then
			return s
		end
	end
	return nil
end

return Airports
