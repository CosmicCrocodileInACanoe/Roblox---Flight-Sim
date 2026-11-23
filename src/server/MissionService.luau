--!strict
-- Authoritative flight tracking and landing grades, computed from the server's own
-- view of the replicated aircraft. Client touchdown reports are only accepted when
-- they agree with what the server measured.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Airports = require(Shared.Airports)
local Mission = require(Shared.Mission)
local Grading = require(Shared.Grading)
local Units = require(Shared.Units)
local Registry = require(Shared.AircraftRegistry)
local Stunts = require(Shared.Stunts)

local MissionService = {}

local remotes: Folder
local progress: any

type Track = {
	mode: string,
	mission: any?,
	airborneSince: number?,
	airborne: boolean,
	vyHistory: { { t: number, vy: number } },
	clientTouchdown: any?,
	pendingGrade: any?,
	lastPhase: string?,
	gradedTouchdown: number?,
	stunts: any?, -- Stunts.Run while racing the ring course
}

local tracks: { [Player]: Track } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function sendMission(p: Player, t: Track)
	local m = t.mission
	;(remotes:FindFirstChild("MissionUpdate") :: RemoteEvent):FireClient(p, {
		mode = t.mode,
		phase = if m then m.phase else nil,
		text = if m then Mission.phaseText(m.phase) else nil,
		origin = if m then m.origin else nil,
		destination = if m then m.destination else nil,
	})
end

-- Stunts: tell the client where the race stands (and what just happened).
local function sendStunts(p: Player, t: Track, events: { any }, now: number, extra: any?)
	local run = t.stunts
	if not run then
		return
	end
	local data: any = {
		state = run.state,
		nextRing = run.nextRing,
		total = run.total,
		elapsed = Stunts.elapsed(run, now),
		penalties = run.penalties,
		hit = run.hit,
		missed = run.missed,
		events = events,
		best = if progress then progress.bestStunts(p) else nil,
	}
	if extra then
		for k, v in extra do
			data[k] = v
		end
	end
	;(remotes:FindFirstChild("StuntsUpdate") :: RemoteEvent):FireClient(p, data)
end

local function countDamaged(model: Model): (number, boolean)
	local n, crashed = 0, false
	for k, v in model:GetAttributes() do
		if string.sub(k, 1, 4) == "Dmg_" and v ~= "normal" then
			n += 1
			if k == "Dmg_Fuselage" and (v == "failed" or v == "detached") then
				crashed = true
			end
		end
	end
	return n, crashed
end

function MissionService.onSpawned(p: Player, options: any, sp: any)
	local t: Track = {
		mode = options.mode,
		mission = nil,
		airborneSince = nil,
		airborne = sp.kind == "air" or sp.kind == "approach",
		vyHistory = {},
		clientTouchdown = nil,
		pendingGrade = nil,
		lastPhase = nil,
		gradedTouchdown = nil,
	}
	if sp.kind == "air" or sp.kind == "approach" then
		t.airborneSince = os.clock()
	end
	if options.mode == "airline" then
		local origin = sp.airport
		local dest = options.destination
		if not dest or dest == origin then
			dest = if origin == "HBR" then "RDV" else "HBR"
		end
		local start = "preflight"
		if sp.kind == "runway" then
			start = "takeoff"
		elseif sp.kind == "approach" then
			start = "landing"
			origin = if sp.airport == "HBR" then "RDV" else "HBR"
			dest = sp.airport
		elseif sp.kind == "air" then
			start = "cruise"
		end
		t.mission = Mission.new(origin, dest, Airports, start)
		if sp.kind == "approach" or sp.kind == "air" then
			t.mission.airborneAt = os.clock()
		end
	end
	if options.mode == Stunts.MODE then
		t.stunts = Stunts.newRun()
	end
	tracks[p] = t
	sendMission(p, t)
	if t.stunts then
		sendStunts(p, t, { { kind = "ready" } }, os.clock())
	end
end

local function finishGrade(p: Player, t: Track, model: Model)
	local g = t.pendingGrade
	t.pendingGrade = nil
	if not g then
		return
	end
	local damaged, crashed = countDamaged(model)
	local _, pitchY, _ = 0, 0, 0
	local result = Grading.grade({
		verticalSpeedFpm = g.vsFpm,
		centerlineOffsetM = g.centerlineOffsetM,
		distanceFromThresholdM = g.distanceFromThresholdM,
		bankDeg = g.bankDeg,
		pitchDeg = g.pitchDeg,
		bounces = g.bounces,
		runwayLengthM = g.runwayLengthM,
		crashed = crashed,
		damagedComponents = damaged,
	})
	result.airport = g.airport
	result.vsFpm = math.floor(g.vsFpm)
	result.vsSource = g.vsSource
	result.mode = t.mode
	;(remotes:FindFirstChild("LandingResult") :: RemoteEvent):FireClient(p, result)
	if progress and t.mode ~= "sandbox" then
		progress.recordLanding(p, result.score)
	end
end

-- Called ~10 Hz by AircraftService with the server's sample of the aircraft.
function MissionService.onTelemetry(p: Player, s: any, model: Model)
	local t = tracks[p]
	if not t then
		return
	end
	local core = model.PrimaryPart :: BasePart
	local cf = core.CFrame
	local pos, vel = cf.Position, core.AssemblyLinearVelocity
	local now = os.clock()
	local cfg = Registry.get(model:GetAttribute("AircraftId") :: string)
	local u = cfg.gear.units[2]
	local restH = -(u.pos[2] - u.strutLength - u.wheelRadius)

	rayParams.FilterDescendantsInstances = { Workspace:FindFirstChild("Aircraft") :: Instance, Workspace:FindFirstChild("Debris") :: Instance }
	local hit = Workspace:Raycast(pos, Vector3.new(0, -3000, 0), rayParams)
	local aglM = if hit then (pos.Y - hit.Position.Y) * Units.METERS_PER_STUD - restH else 1e4
	local onGround = aglM < 0.45
	local vy = vel.Y * Units.METERS_PER_STUD
	table.insert(t.vyHistory, { t = now, vy = vy })
	while #t.vyHistory > 20 do
		table.remove(t.vyHistory, 1)
	end
	local look = cf.LookVector
	local heading = Units.headingFromXZ(look.X, look.Z)
	local _, crashed = countDamaged(model)

	-- Free-flight / sandbox landing detection (airline mode uses the Mission machine).
	if not onGround then
		if not t.airborne and aglM > 8 then
			t.airborne = true
			t.airborneSince = now
		end
	end
	local touchdown = false
	if onGround and t.airborne and t.airborneSince and now - t.airborneSince > 6 then
		touchdown = true
		t.airborne = false
	elseif onGround then
		t.airborne = false
	end

	-- Stunts: ring passes, misses and the finish, timed by the server. Touching the
	-- ground or breaking up ends the run.
	local run = t.stunts
	if run and (run.state == "ready" or run.state == "racing") then
		local events = Stunts.update(run, pos.X, pos.Y, pos.Z, now, crashed or onGround)
		if #events > 0 then
			local extra = nil
			if run.state == "finished" then
				local total = Stunts.totalTime(run, now)
				local best, isNew = total, true
				if progress then
					best, isNew = progress.recordStunts(p, total)
				end
				extra = { totalTime = total, best = best, newBest = isNew, medal = Stunts.medal(total) }
			elseif run.state == "crashed" then
				extra = { crashReason = if crashed then "broken" else "ground" }
			end
			sendStunts(p, t, events, now, extra)
		end
	end

	local mission = t.mission
	if mission then
		local tel = {
			x = pos.X, z = pos.Z,
			altitudeM = pos.Y * Units.METERS_PER_STUD,
			aglM = aglM,
			groundSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude * Units.METERS_PER_STUD,
			verticalSpeed = vy,
			onGround = onGround,
			headingDeg = heading,
			enginesRunning = s.systems.EnginesRunning == true,
			parkingBrake = s.systems.ParkingBrake == true,
			crashed = crashed,
			time = now,
		}
		local event = Mission.update(mission, tel)
		if mission.phase ~= t.lastPhase then
			t.lastPhase = mission.phase
			sendMission(p, t)
		end
		if event == "complete" and progress then
			progress.recordFlight(p, mission)
		end
	end

	if touchdown and not run then
		local nearId = Airports.nearest(pos.X, pos.Z)
		local l = Airports.layout(nearId)
		if Airports.isOnRunway(l, pos.X, pos.Z, 60) then
			-- Server-measured sink rate: most negative vertical speed in the last 0.8 s.
			local minVy = 0
			for _, h in t.vyHistory do
				if now - h.t <= 0.8 then
					minVy = math.min(minVy, h.vy)
				end
			end
			local serverFpm = minVy * Units.FPM_PER_MPS
			local vsFpm, source = serverFpm, "server"
			local ct = t.clientTouchdown
			if ct and now - ct.t < 2 and math.abs(ct.vsFpm - serverFpm) < 250 then
				vsFpm, source = ct.vsFpm, "client (verified)"
			end
			local info = Airports.landingInfo(l, pos.X, pos.Z, heading)
			local up = cf.UpVector
			local right = cf.RightVector
			t.pendingGrade = {
				airport = nearId,
				vsFpm = vsFpm,
				vsSource = source,
				centerlineOffsetM = info.centerlineOffsetM,
				distanceFromThresholdM = info.distanceFromThresholdM,
				bankDeg = math.deg(math.asin(math.clamp(-right.Y, -1, 1))),
				pitchDeg = math.deg(math.asin(math.clamp(look.Y, -1, 1))),
				bounces = 0,
				runwayLengthM = l.lengthM,
				time = now,
			}
			t.gradedTouchdown = now
			local _ = up
		end
	end
	-- Count bounces for a few seconds, then publish the grade.
	if t.pendingGrade then
		if not onGround and aglM > 1.5 then
			t.pendingGrade.bounced = true
		elseif onGround and t.pendingGrade.bounced then
			t.pendingGrade.bounced = false
			t.pendingGrade.bounces += 1
		end
		if now - t.pendingGrade.time > 5 then
			finishGrade(p, t, model)
		end
	end
end

local function onClientTouchdown(p: Player, data: any)
	local t = tracks[p]
	if not t or type(data) ~= "table" or type(data.vsFpm) ~= "number" or data.vsFpm ~= data.vsFpm then
		return
	end
	t.clientTouchdown = { vsFpm = math.clamp(data.vsFpm, -5000, 500), t = os.clock() }
end

function MissionService.init(remoteFolder: Folder, progressService: any)
	remotes = remoteFolder
	progress = progressService
	;(remotes:FindFirstChild("ReportTouchdown") :: RemoteEvent).OnServerEvent:Connect(onClientTouchdown)
	Players.PlayerRemoving:Connect(function(p)
		tracks[p] = nil
	end)
end

return MissionService
