--!strict
-- Stunts mode: an air-race ring course just east of Harbor City International, plus the
-- pure race rules (ring passes, misses, penalties, finish, crash). No Roblox APIs, so the
-- server (authoritative timing), the client (HUD, ring colours) and tests/test_stunts.luau
-- all share it.
--
-- World axes as everywhere else: studs, x east, y up, z south.

local function req(name: string): any
	if script then
		return (require :: any)((script :: any).Parent[name])
	end
	return (require :: any)("./" .. name)
end
local Units = req("Units")
local WorldGen = req("WorldGen")

local SPM = Units.STUDS_PER_METER

local Stunts = {}

Stunts.MODE = "stunts"
Stunts.RING_RADIUS_M = 15 -- inner radius of every ring (a 30 m hole: big, for young pilots)
Stunts.PASS_SLACK_M = 1.5 -- a wingtip clipping the rim still counts
Stunts.MISS_RADIUS_M = 110 -- crossing a ring's plane closer than this (but outside it) is a miss
Stunts.MISS_PENALTY_S = 3
-- Medal times (seconds, penalties included). Measured against the offline autopilot
-- (tests/test_stunts.luau).
Stunts.MEDALS = { gold = 36, silver = 45, bronze = 60 }

-- Course centre: open, gently rising farmland 1 to 2 km east of Harbor City's runway 09
-- end, south of the runway 27 approach path and north of the coast.
Stunts.CENTER = { x = -35000, z = 5200 }
Stunts.HALF_SIZE_M = 500 -- the course fits in a 1 km x 1 km square

-- Rings in course metres (x east, z south of the centre) and height above the ground
-- (m, ring centre). A stadium-shaped lap: a low slalom along the north straight, a
-- climbing turn round the east end, a high pass back west that dives to skim the ground,
-- and a swing round the west end to the finish. The ends are 265 m radius turns.
Stunts.RINGS_M = {
	{ x = -210, z = -265, h = 35 }, -- 1: start gate, eastbound
	{ x = -70, z = -245, h = 20 }, -- 2: slalom, low
	{ x = 70, z = -285, h = 22 },
	{ x = 210, z = -260, h = 35 },
	{ x = 397, z = -187, h = 60 }, -- 5: climbing turn round the east end
	{ x = 475, z = 0, h = 90 },
	{ x = 397, z = 187, h = 105 },
	{ x = 165, z = 265, h = 100 }, -- 8: high, westbound
	{ x = -5, z = 265, h = 62 }, -- diving
	{ x = -175, z = 265, h = 25 }, -- 10: skim the ground
	{ x = -397, z = 187, h = 35 }, -- round the west end
	{ x = -459, z = -91, h = 50 }, -- 12: finish
}

export type Ring = {
	index: number,
	x: number, y: number, z: number, -- centre, studs
	nx: number, ny: number, nz: number, -- unit normal: the direction to fly through
	groundY: number, -- ground under the centre (studs)
}

local function ground(x: number, z: number): number
	return math.max(WorldGen.meshHeight(x, z), WorldGen.SEA_LEVEL)
end

function Stunts.toWorld(xm: number, zm: number): (number, number)
	return Stunts.CENTER.x + xm * SPM, Stunts.CENTER.z + zm * SPM
end

local courseCache: { Ring }? = nil

-- Every ring in world studs, each facing along the course (central difference, so it is
-- square to the flight path through it, climbs and dives included).
function Stunts.course(): { Ring }
	if courseCache then
		return courseCache
	end
	local pts = {}
	for i, r in Stunts.RINGS_M do
		local x, z = Stunts.toWorld(r.x, r.z)
		local gy = ground(x, z)
		pts[i] = { x = x, z = z, y = gy + r.h * SPM, groundY = gy }
	end
	local out: { Ring } = {}
	for i, p in pts do
		local a = pts[math.max(1, i - 1)]
		local b = pts[math.min(#pts, i + 1)]
		local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
		local len = math.sqrt(dx * dx + dy * dy + dz * dz)
		out[i] = {
			index = i,
			x = p.x, y = p.y, z = p.z,
			nx = dx / len, ny = dy / len, nz = dz / len,
			groundY = p.groundY,
		}
	end
	courseCache = out
	return out
end

-- A smooth racing line through every ring centre (Catmull-Rom), starting at the spawn
-- point: points every `stepM` metres or so, in studs. Used by the tests to check the
-- course is flyable, and handy for a future ghost or minimap line.
function Stunts.racingLine(stepM: number?): { { x: number, y: number, z: number } }
	local course = Stunts.course()
	local sp = Stunts.spawn()
	local pts = { { x = sp.x, y = sp.y, z = sp.z } }
	for _, r in course do
		table.insert(pts, { x = r.x, y = r.y, z = r.z })
	end
	-- carry on straight past the finish
	local last = course[#course]
	local ext = 200 * SPM
	table.insert(pts, { x = last.x + last.nx * ext, y = last.y + last.ny * ext, z = last.z + last.nz * ext })
	local out = {}
	local step = (stepM or 5) * SPM
	for i = 1, #pts - 1 do
		local p0, p1, p2 = pts[math.max(1, i - 1)], pts[i], pts[i + 1]
		local p3 = pts[math.min(#pts, i + 2)]
		local len = math.sqrt((p2.x - p1.x) ^ 2 + (p2.y - p1.y) ^ 2 + (p2.z - p1.z) ^ 2)
		local n = math.max(1, math.ceil(len / step))
		for k = 0, n - 1 do
			local t = k / n
			local t2, t3 = t * t, t * t * t
			local function cr(a: number, b: number, c: number, d: number): number
				return 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
			end
			table.insert(out, { x = cr(p0.x, p1.x, p2.x, p3.x), y = cr(p0.y, p1.y, p2.y, p3.y), z = cr(p0.z, p1.z, p2.z, p3.z) })
		end
	end
	table.insert(out, pts[#pts])
	return out
end

-- Is (x, z) inside the course square (plus a margin in metres)? Used to keep trees out.
function Stunts.inCourseArea(x: number, z: number, marginM: number?): boolean
	local half = (Stunts.HALF_SIZE_M + (marginM or 0)) * SPM
	return math.abs(x - Stunts.CENTER.x) <= half and math.abs(z - Stunts.CENTER.z) <= half
end

-- The one spawn point: in the air over the runway end, lined up with ring 1.
Stunts.SPAWN_ID = "stunts-start"
local spawnCache: any = nil
function Stunts.spawn(): any
	if spawnCache then
		return spawnCache
	end
	local r1 = Stunts.course()[1]
	local hx, hz = r1.nx, r1.nz
	local hl = math.sqrt(hx * hx + hz * hz)
	hx, hz = hx / hl, hz / hl
	local back = 420 * SPM
	local x, z = r1.x - hx * back, r1.z - hz * back
	spawnCache = {
		id = Stunts.SPAWN_ID,
		label = "In the air: lined up with ring 1",
		airport = "HBR",
		kind = "air",
		x = x, y = math.max(r1.y, ground(x, z) + 35 * SPM), z = z,
		heading = Units.headingFromXZ(hx, hz),
		speed = 70, -- m/s
		enginesRunning = true, gearDown = false, flaps = 1, throttle = 0.75, pitchDeg = 0,
	}
	return spawnCache
end

function Stunts.getSpawn(id: any): any
	if id == Stunts.SPAWN_ID then
		return Stunts.spawn()
	end
	return nil
end

-- Stunts tunes the Easy assist for racing, whatever the plane: steep banks and quick
-- pulls, so the course's tight turns are possible with the stick held over.
Stunts.RACE_ASSIST = { easyBankDeg = 70, easyPitchUpDeg = 45, easyPitchDownDeg = -35, easyPitchRateDeg = 24, aerobatic = true }
local tuned: { [any]: any } = {}
function Stunts.raceTune(cfg: any): any
	-- one copy per aircraft config, so caches keyed by the config (Crash.profiles) stay small
	local c = tuned[cfg]
	if not c then
		c = table.clone(cfg)
		c.assist = table.clone(Stunts.RACE_ASSIST)
		tuned[cfg] = c
	end
	return c
end

-- Race state ---------------------------------------------------------------------
-- state: "ready" (before the start gate) -> "racing" -> "finished" | "crashed"
export type Run = {
	state: string,
	nextRing: number, -- index of the ring to fly through next
	total: number,
	startTime: number?, -- clock when ring 1 was passed
	finishTime: number?,
	penalties: number, -- seconds
	missed: number,
	hit: number,
	results: { string }, -- per ring: "hit" | "miss" | nil
	lastX: number?, lastY: number?, lastZ: number?, lastT: number?,
}

function Stunts.newRun(): Run
	return {
		state = "ready",
		nextRing = 1,
		total = #Stunts.course(),
		startTime = nil,
		finishTime = nil,
		penalties = 0,
		missed = 0,
		hit = 0,
		results = {},
		lastX = nil, lastY = nil, lastZ = nil, lastT = nil,
	}
end

-- Where the segment a -> b crosses ring r's plane going forward: (fraction along the
-- segment, distance from the ring centre in metres), or nil if it doesn't cross forward.
function Stunts.crossing(r: Ring, ax: number, ay: number, az: number, bx: number, by: number, bz: number): (number?, number?)
	local da = (ax - r.x) * r.nx + (ay - r.y) * r.ny + (az - r.z) * r.nz
	local db = (bx - r.x) * r.nx + (by - r.y) * r.ny + (bz - r.z) * r.nz
	if not (da < 0 and db >= 0) then
		return nil, nil
	end
	local f = da / (da - db)
	local px, py, pz = ax + (bx - ax) * f, ay + (by - ay) * f, az + (bz - az) * f
	local d = math.sqrt((px - r.x) ^ 2 + (py - r.y) ^ 2 + (pz - r.z) ^ 2) * Units.METERS_PER_STUD
	return f, d
end

-- Elapsed race time (s) at clock `now`, penalties not included.
function Stunts.elapsed(run: Run, now: number): number
	if not run.startTime then
		return 0
	end
	return (run.finishTime or now) - run.startTime
end

-- Total time with penalties (the score: lower is better).
function Stunts.totalTime(run: Run, now: number): number
	return Stunts.elapsed(run, now) + run.penalties
end

function Stunts.medal(totalSeconds: number): string?
	local m = Stunts.MEDALS
	if totalSeconds <= m.gold then
		return "gold"
	elseif totalSeconds <= m.silver then
		return "silver"
	elseif totalSeconds <= m.bronze then
		return "bronze"
	end
	return nil
end

local function passRing(run: Run, i: number, t: number, events: { any })
	run.results[i] = "hit"
	run.hit += 1
	if i == 1 then
		run.state = "racing"
		run.startTime = t
		table.insert(events, { kind = "start", ring = i })
	elseif i == run.total then
		run.state = "finished"
		run.finishTime = t
		table.insert(events, { kind = "finish", ring = i })
	else
		table.insert(events, { kind = "pass", ring = i })
	end
	run.nextRing = i + 1
end

local function missRing(run: Run, i: number, t: number, events: { any }, byM: number?)
	run.results[i] = "miss"
	run.missed += 1
	run.penalties += Stunts.MISS_PENALTY_S
	table.insert(events, { kind = "miss", ring = i, byM = byM })
	run.nextRing = i + 1
	if i == run.total then
		-- flying past the finish ring still ends the race (with the penalty)
		run.state = "finished"
		run.finishTime = t
		table.insert(events, { kind = "finish", ring = i })
	end
end

-- Advance the race with a new aircraft position (studs) at clock time t. `crashed` is
-- true once the aircraft has hit the ground or broken up. Returns the events (in order)
-- that this sample caused: start, pass, miss, finish, crash.
function Stunts.update(run: Run, x: number, y: number, z: number, t: number, crashed: boolean): { any }
	local events = {}
	if run.state == "finished" or run.state == "crashed" then
		return events
	end
	local ax, ay, az, at = run.lastX, run.lastY, run.lastZ, run.lastT
	run.lastX, run.lastY, run.lastZ, run.lastT = x, y, z, t
	if ax and ay and az and at then
		local course = Stunts.course()
		local passR = Stunts.RING_RADIUS_M + Stunts.PASS_SLACK_M
		-- Check the next ring, then (so a skipped ring doesn't stall the race) the one after.
		local i = run.nextRing
		local r = course[i]
		local f, d = Stunts.crossing(r, ax, ay, az, x, y, z)
		local handled = false
		if f and d then
			local ct = at + (t - at) * f
			if d <= passR then
				passRing(run, i, ct, events)
				handled = true
			elseif d <= Stunts.MISS_RADIUS_M and i > 1 then
				missRing(run, i, ct, events, d - Stunts.RING_RADIUS_M)
				handled = true
			end
		end
		if not handled and i > 1 and i < run.total then
			local r2 = course[i + 1]
			local f2, d2 = Stunts.crossing(r2, ax, ay, az, x, y, z)
			if f2 and d2 and d2 <= passR then
				missRing(run, i, at + (t - at) * f2, events)
				passRing(run, i + 1, at + (t - at) * f2, events)
			end
		end
	end
	if crashed and run.state ~= "finished" then
		run.state = "crashed"
		table.insert(events, { kind = "crash" })
	end
	return events
end

-- Format seconds as m:ss.t for the HUD and results.
function Stunts.formatTime(seconds: number): string
	local s = math.max(0, seconds)
	local m = math.floor(s / 60)
	local rest = s - m * 60
	local tenths = math.floor(rest * 10 + 1e-6)
	return string.format("%d:%02d.%d", m, math.floor(tenths / 10), tenths % 10)
end

return Stunts
