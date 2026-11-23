--!nonstrict
-- Stunts mode: the ring course (placement, clearance, flyability), the race rules, the
-- stunt plane, and the course builder against the Roblox mock.
local Sim = require("./SimHarness")
local U = require("../src/shared/Units")
local Assist = require("../src/shared/Assist")
local FM = require("../src/shared/FlightModel")
local Registry = require("../src/shared/AircraftRegistry")
local Stunts = require("../src/shared/Stunts")
local WorldGen = require("../src/shared/WorldGen")
local Airports = require("../src/shared/Airports")
local Selection = require("../src/shared/Selection")
local GameConfig = require("../src/shared/GameConfig")
local Mock = require("./RobloxMock")

local SPM = U.STUDS_PER_METER
local MPS = U.METERS_PER_STUD

-- Fly the course with Easy assist (race-tuned), steering only with stick inputs the way a
-- player would. Positions in the sim are world studs * 0.28 (metres); the real terrain
-- height comes from WorldGen. Returns the run, the minimum height above the terrain (m),
-- and the max load factor.
local function autopilot(cfg, opts)
	opts = opts or {}
	local tuned = Stunts.raceTune(cfg)
	local sp = Stunts.spawn()
	local s = Sim.new(tuned, {
		enginesRunning = true, flaps = 1, gearDown = false,
		x = sp.x * MPS, y = sp.y * MPS, z = sp.z * MPS, headingDeg = sp.heading, speed = sp.speed,
		toughness = Assist.toughness("easy"),
	})
	s.groundY = -1e6 -- the sim's flat ground is replaced by the real terrain check below
	s.ctl.gearDown = false
	local a = Assist.new("easy")
	local raw = FM.newControls()
	raw.throttle, raw.gearDown, raw.flaps = opts.throttle or 0.9, false, 1
	local run = Stunts.newRun()
	local course = Stunts.course()
	local minAgl = 1e9
	local events = {}
	local path = Stunts.racingLine(5) -- metres? no: studs; converted below
	for k, q in path do
		path[k] = { x = q.x * MPS, y = q.y * MPS, z = q.z * MPS }
	end
	local cursor = 1
	for _ = 1, 60 * 180 do
		-- pure pursuit of a carrot point ~110 m ahead on a smooth spline through the rings
		local best, bestD = 1, math.huge
		local from = math.max(1, cursor - 5)
		for k = from, math.min(#path, cursor + 60) do
			local q = path[k]
			local d = (q.x - s.px) ^ 2 + (q.y - s.py) ^ 2 + (q.z - s.pz) ^ 2
			if d < bestD then
				best, bestD = k, d
			end
		end
		cursor = best
		local carrot = path[math.min(#path, cursor + 20)]
		local dx, dy, dz = carrot.x - s.px, carrot.y - s.py, carrot.z - s.pz
		local hd = math.sqrt(dx * dx + dz * dz)
		local p, b, h = s:attitude()
		local want = U.headingFromXZ(dx, dz)
		local herr = ((want - h + 540) % 360) - 180
		-- L1 guidance for the lateral acceleration, a flight-path-angle loop for the
		-- vertical one; together they give the bank and the load factor to pull, which go
		-- in as stick inputs through the Easy assist (roll stick -> bank, pitch stick ->
		-- extra pitch rate on top of the assist's own level-turn pull).
		local v = math.sqrt(s.vx * s.vx + s.vy * s.vy + s.vz * s.vz)
		local l1 = math.max(30, math.sqrt(dx * dx + dz * dz))
		local aLat = 2 * v * v * math.sin(math.rad(math.clamp(herr, -90, 90))) / l1
		local gamma = math.atan2(s.vy, math.sqrt(s.vx * s.vx + s.vz * s.vz))
		local gammaCmd = math.clamp(math.atan2(dy, math.max(hd, 1)), math.rad(-35), math.rad(35))
		local aVert = math.clamp(v * (gammaCmd - gamma) * 2.0, -20, 25)
		local g = 9.81
		local up = aVert + g * math.cos(gamma)
		local bankCmd = math.clamp(math.deg(math.atan2(aLat, math.max(up, 0.6 * g))), -69, 69)
		local rollIn = math.clamp((bankCmd - b) * 0.05 + (s.env.wz or 0) * 0.6, -1, 1)
		if math.abs(rollIn) < 0.06 and math.abs(bankCmd) > 3 then
			rollIn = 0.06 * math.sign(bankCmd - b + 1e-9)
		end
		raw.roll = rollIn
		local n = math.sqrt(math.max(up, 0) ^ 2 + aLat * aLat) / g
		local br = math.rad(b)
		local qDes = (n - math.cos(br) * math.cos(gamma)) * g / v
		local qTurn = if math.abs(math.cos(br)) > 0.2 then g / v * math.sin(br) * math.tan(br) else 0
		raw.pitch = math.clamp((qDes - qTurn) / Assist.limits(tuned).pitchRate, -1, 1)
		-- race pace: fast on the straights, slow enough to make the turns
		local kt = s.model.result.ias * U.KTS_PER_MPS
		local pace = opts.paceKt or 120
		raw.throttle = math.clamp(0.6 + (pace - kt) * 0.05, 0, 1)
		s:prepareEnv()
		Assist.apply(a, raw, s.ctl, s.env, s.model, 1 / 60)
		s:frame()
		local gy = math.max(WorldGen.meshHeight(s.px * SPM, s.pz * SPM), 0) * MPS
		local agl = s.py - gy
		minAgl = math.min(minAgl, agl)
		local evs = Stunts.update(run, s.px * SPM, s.py * SPM, s.pz * SPM, s.time, agl < 1)
		for _, e in evs do
			table.insert(events, e)
		end
		if run.state == "finished" or run.state == "crashed" then
			break
		end
	end
	return run, minAgl, s.maxG, s, events
end

return { name = "Stunts ring course", run = function(T)
	local course = Stunts.course()

	T.test("course: 10+ rings inside a 1 km square near Harbor City, all over land", function()
		T.check(#course >= 10, "rings " .. #course)
		local half = Stunts.HALF_SIZE_M * SPM
		for _, r in course do
			T.check(math.abs(r.x - Stunts.CENTER.x) <= half and math.abs(r.z - Stunts.CENTER.z) <= half, `ring {r.index} outside the square`)
			T.check(not WorldGen.isSea(r.x, r.z), `ring {r.index} over the sea`)
			T.near(r.nx * r.nx + r.ny * r.ny + r.nz * r.nz, 1, 1e-6, "unit normal")
		end
		local l = Airports.layout("HBR")
		local d = math.sqrt((Stunts.CENTER.x - l.cx) ^ 2 + (Stunts.CENTER.z - l.cz) ^ 2) / SPM
		T.check(d < 5000, string.format("course %.0f m from HBR", d))
	end)

	T.test("course: high and low rings, every ring clear of the ground and the approach path", function()
		local low, high = 0, 0
		local l = Airports.layout("HBR")
		for _, r in course do
			local agl = (r.y - r.groundY) * MPS
			if agl <= 30 then
				low += 1
			end
			if agl >= 90 then
				high += 1
			end
			-- lowest rim point vs the highest ground under the ring's width
			local rim = Stunts.RING_RADIUS_M * SPM
			local maxG = -1e9
			for k = -4, 4 do
				local f = k / 4
				-- horizontal direction across the ring
				local hx, hz = -r.nz, r.nx
				local hl = math.sqrt(hx * hx + hz * hz)
				local x, z = r.x + hx / hl * rim * f, r.z + hz / hl * rim * f
				maxG = math.max(maxG, WorldGen.meshHeight(x, z))
			end
			local bottom = (r.y - rim - maxG) * MPS
			T.check(bottom >= 4, string.format("ring %d bottom only %.1f m above the ground", r.index, bottom))
			T.check(agl <= 200, "ring too high " .. r.index)
			local _, cross = Airports.toRunway(l, r.x, r.z)
			T.check(math.abs(cross) > 900, `ring {r.index} sits in the runway 27 approach`)
		end
		T.check(low >= 3, "low rings " .. low)
		T.check(high >= 3, "high rings " .. high)
	end)

	T.test("course: rings are spaced out, and no tree is planted inside the course", function()
		for i = 2, #course do
			local a, b = course[i - 1], course[i]
			local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) * MPS
			T.between(d, 120, 450, `gap {i - 1}->{i}`)
		end
		for _, r in course do
			T.check(Stunts.inCourseArea(r.x, r.z, 0))
		end
		T.check(not Stunts.inCourseArea(Stunts.CENTER.x + 700 * SPM, Stunts.CENTER.z, 50))
	end)

	T.test("spawn: in the air before ring 1, heading through it, offered only in Stunts mode", function()
		local sp = Stunts.spawn()
		local r1 = course[1]
		T.check(sp.kind == "air" and sp.gearDown == false and sp.enginesRunning)
		local dx, dz = r1.x - sp.x, r1.z - sp.z
		local d = math.sqrt(dx * dx + dz * dz) * MPS
		T.between(d, 300, 600, "distance to ring 1")
		local diff = math.abs(((U.headingFromXZ(dx, dz) - sp.heading + 540) % 360) - 180)
		T.check(diff < 2, "heading at ring 1")
		T.check((sp.y - WorldGen.meshHeight(sp.x, sp.z)) * MPS > 25, "spawn height")
		local cfg = Registry.get(Registry.stuntAircraftId)
		local list = Selection.spawnList("HBR", cfg, "stunts", nil)
		T.check(#list == 1 and list[1].id == Stunts.SPAWN_ID, "stunts spawn list")
		T.check(Selection.resolveSpawn("HBR-rwy09", "HBR", cfg, "stunts", nil).id == Stunts.SPAWN_ID)
		T.check(Selection.destinations("HBR", "stunts")[1] == false)
		for _, s in Selection.spawnList("HBR", Registry.get("kestrel72"), "free", nil) do
			T.check(s.id ~= Stunts.SPAWN_ID, "stunts start leaked into free flight")
		end
		local found = false
		for _, m in GameConfig.modes do
			found = found or m.id == "stunts"
		end
		T.check(found, "Stunts in the mode list")
	end)

	T.test("race rules: start gate, passes, a miss costs 3 s, skipping a ring, finish", function()
		local run = Stunts.newRun()
		local function through(i, offsetM, t)
			local r = course[i]
			-- a short segment through the ring plane, offset sideways by offsetM
			local hx, hz = -r.nz, r.nx
			local hl = math.sqrt(hx * hx + hz * hz)
			local ox, oz = hx / hl * offsetM * SPM, hz / hl * offsetM * SPM
			local step = 5 * SPM
			Stunts.update(run, r.x - r.nx * step + ox, r.y - r.ny * step, r.z - r.nz * step + oz, t - 0.05, false)
			return Stunts.update(run, r.x + r.nx * step + ox, r.y + r.ny * step, r.z + r.nz * step + oz, t + 0.05, false)
		end
		-- missing the start gate does nothing: the clock has not started
		through(1, 40, 1)
		T.check(run.state == "ready" and run.nextRing == 1 and run.penalties == 0)
		run.lastX = nil
		local e = through(1, 0, 10)
		T.check(e[1].kind == "start" and run.state == "racing" and run.nextRing == 2)
		T.near(run.startTime, 10, 1e-6, "start time")
		run.lastX = nil
		e = through(2, 3, 15)
		T.check(e[1].kind == "pass" and run.nextRing == 3)
		run.lastX = nil
		e = through(3, 40, 20)
		T.check(e[1].kind == "miss" and run.penalties == 3 and run.nextRing == 4, "miss")
		-- flying the wrong way through a ring is not a pass
		run.lastX = nil
		local r4 = course[4]
		Stunts.update(run, r4.x + r4.nx * 20, r4.y + r4.ny * 20, r4.z + r4.nz * 20, 24, false)
		e = Stunts.update(run, r4.x - r4.nx * 20, r4.y - r4.ny * 20, r4.z - r4.nz * 20, 24.1, false)
		T.check(#e == 0 and run.nextRing == 4, "backwards pass ignored")
		-- skipping ring 4 and flying through ring 5: 4 is a miss, 5 counts
		run.lastX = nil
		e = through(5, 0, 30)
		T.check(#e == 2 and e[1].kind == "miss" and e[1].ring == 4 and e[2].kind == "pass" and e[2].ring == 5, "skip")
		T.check(run.penalties == 6 and run.nextRing == 6)
		for i = 6, #course do
			run.lastX = nil
			e = through(i, 0, 30 + i * 4)
		end
		T.check(run.state == "finished" and e[#e].kind == "finish", "finished")
		T.near(Stunts.elapsed(run, 999), 30 + #course * 4 - 10, 1e-6, "elapsed")
		T.near(Stunts.totalTime(run, 999), 30 + #course * 4 - 10 + 6, 1e-6, "total")
		T.check(run.hit == #course - 2 and run.missed == 2)
		-- nothing changes after the finish
		T.check(#Stunts.update(run, 0, 0, 0, 1000, true) == 0 and run.state == "finished")
	end)

	T.test("race rules: crashing ends the run; formatting and medals", function()
		local run = Stunts.newRun()
		local e = Stunts.update(run, 0, 0, 0, 1, true)
		T.check(run.state == "crashed" and e[1].kind == "crash")
		T.check(Stunts.formatTime(0) == "0:00.0")
		T.check(Stunts.formatTime(65.47) == "1:05.4", Stunts.formatTime(65.47))
		T.check(Stunts.medal(Stunts.MEDALS.gold - 1) == "gold")
		T.check(Stunts.medal(Stunts.MEDALS.silver - 0.5) == "silver")
		T.check(Stunts.medal(Stunts.MEDALS.bronze) == "bronze")
		T.check(Stunts.medal(Stunts.MEDALS.bronze + 1) == nil)
	end)

	T.test("stunt plane: registered, unlocked, not in the airliner menu order, race-tuned", function()
		local id = Registry.stuntAircraftId
		local cfg = Registry.get(id)
		T.check(cfg ~= nil and cfg.unlocked, "stunt aircraft " .. tostring(id))
		local tuned = Stunts.raceTune(cfg)
		local lim = Assist.limits(tuned)
		T.check(math.deg(lim.bank) >= 65 and math.deg(lim.pitchRate) >= 20, "race tune")
		T.check(cfg.assist == nil or cfg.assist ~= tuned.assist, "the registry config is not modified")
		T.check(tuned.aero == cfg.aero, "shallow copy")
		T.check(cfg.gLimit >= 6, "aerobatic airframe")
	end)

	T.test("stunt plane: very nimble (fast roll, tight easy turns) and quick", function()
		local cfg = Stunts.raceTune(Registry.get(Registry.stuntAircraftId))
		local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = 600, speed = 70 })
		s.ctl.gearDown = false
		s.ctl.throttle = 0.7
		local maxp = 0
		for _ = 1, 90 do
			s.ctl.roll = 1
			s:frame()
			local _, _, bz = Sim.mulMtV(s.R, s.wx, s.wy, s.wz)
			maxp = math.max(maxp, -bz)
		end
		T.check(math.deg(maxp) > 150, string.format("roll rate %.0f deg/s", math.deg(maxp)))
		-- easy, full stick over: tight, level turn
		local e = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = 600, speed = 70, toughness = 1.6 })
		e.ctl.gearDown = false
		local a = Assist.new("easy")
		local raw = FM.newControls()
		raw.throttle, raw.gearDown, raw.flaps, raw.roll = 0.9, false, 1, 1
		local function fly(sec)
			for _ = 1, math.floor(sec * 60) do
				e:prepareEnv()
				Assist.apply(a, raw, e.ctl, e.env, e.model, 1 / 60)
				e:frame()
			end
		end
		fly(3)
		local _, _, h0 = e:attitude()
		local y0 = e.py
		fly(5)
		local _, b, h1 = e:attitude()
		local turned = ((h1 - h0) % 360)
		local radius = e.model.result.tas / math.rad(turned / 5)
		T.check(radius < 260, string.format("easy turn radius %.0f m (bank %.0f)", radius, b))
		T.check(math.abs(e.py - y0) < 40, string.format("turn holds height: %+.0f m", e.py - y0))
		T.check(e:isFinite())
	end)

	T.test("course: the stunt plane flies it end to end in Easy without touching the ground", function()
		local run, minAgl, maxG, s, events = autopilot(Registry.get(Registry.stuntAircraftId))
		local misses = {}
		for _, e in events do
			if e.kind == "miss" then
				table.insert(misses, e.ring)
			end
		end
		T.check(run.state == "finished", string.format("state %s at ring %d (min agl %.1f m)", run.state, run.nextRing, minAgl))
		T.check(#misses == 0, "missed rings " .. table.concat(misses, ","))
		T.check(minAgl > 3, string.format("min height %.1f m", minAgl))
		T.check(s.model.damage.destroyed ~= true, "airframe")
		local t = Stunts.totalTime(run, s.time)
		print(string.format("       autopilot: %s, max %.1f g, min %.1f m AGL", Stunts.formatTime(t), maxG, minAgl))
		T.check(Stunts.medal(t) == "gold", "an expert run earns gold: " .. Stunts.formatTime(t))
		T.check(t > Stunts.MEDALS.gold * 0.7, "gold should still be a challenge")
	end)

	-- Course builder against the Roblox mock
	local hasSrc, src = pcall(require, "./generated/StuntCourseBuilder_src")
	T.test("course builder: builds every ring with no collisions or raycast hits", function()
		T.check(hasSrc, "run tests/run.sh (it embeds the builder source first)")
		local Builder = Mock.loadModule(src, "StuntCourseBuilder", "../src/shared/", function(p)
			return require(p)
		end)
		local root = Mock.Instance.new("Folder")
		local folder, count = Builder.build(root)
		T.check(folder.Parent == root and folder.Name == "StuntCourse")
		T.check(#folder:GetChildren() == #course, "ring models")
		T.check(count < 400, "parts " .. count)
		for _, ringModel in folder:GetChildren() do
			local idx = ringModel:GetAttribute("RingIndex")
			local r = course[idx]
			T.check(r ~= nil, "ring index")
			local c = Mock.Vector3.new(r.x, r.y, r.z)
			for _, p in ringModel:GetChildren() do
				T.check(p.CanCollide == false and p.CanTouch == false and p.CanQuery == false and p.Anchored == true, p.Name)
				if p.Name == "Segment" then
					local off = p.CFrame.Position - c
					local n = Mock.Vector3.new(r.nx, r.ny, r.nz)
					T.check(math.abs(off:Dot(n)) < 0.01, "segment in the ring plane")
					local rad = off.Magnitude * MPS
					T.between(rad, Stunts.RING_RADIUS_M, Stunts.RING_RADIUS_M + 2.5, "segment radius")
					-- the segment's long axis runs around the ring
					T.check(math.abs(p.CFrame.UpVector:Dot(off.Unit)) < 1e-3, "tangent")
				end
			end
		end
	end)
end }
