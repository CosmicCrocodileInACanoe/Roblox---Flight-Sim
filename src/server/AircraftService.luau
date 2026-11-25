--!strict
-- Server authority for aircraft: spawn/reset, seating and network ownership, validation
-- of client reports (damage, systems), detachment into physical debris with budgets,
-- and motion sanity checks. The owning client simulates its own aircraft's physics
-- (smooth, responsive flight); the server never trusts client-reported rewards.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared.AircraftRegistry)
local Airports = require(Shared.Airports)
local GameConfig = require(Shared.GameConfig)
local Units = require(Shared.Units)
local Assist = require(Shared.Assist)
local Selection = require(Shared.Selection)
local Stunts = require(Shared.Stunts)
local AircraftBuilder = require(script.Parent.AircraftBuilder)
local CrashService = require(script.Parent.CrashService)
local CraterService = require(script.Parent.CraterService)
local Crash = require(Shared.Crash)

local AircraftService = {}

local remotes: Folder
local aircraftFolder: Folder
local debrisFolder: Folder
local onTelemetry: ((Player, any, any) -> ())? = nil
local onSpawned: ((Player, any, any) -> ())? = nil

type PlayerState = {
	pendingSpawn: any?,
	aircraft: Model?,
	options: any?,
	lastSpawn: number,
	lastRepair: number?,
	debris: { { model: Model, t: number } },
	samples: { { t: number, pos: Vector3, vel: Vector3 } },
	damageBudget: number,
	systemsBudget: number,
	systems: any,
	protectedUntil: number,
	exited: boolean,
}

local states: { [Player]: PlayerState } = {}
local allDebris: { { model: Model, t: number, owner: Player? } } = {}

local VALID_STATES = { normal = true, degraded = true, failed = true, detached = true }

local function getState(p: Player): PlayerState
	local s = states[p]
	if not s then
		s = {
			aircraft = nil, options = nil, lastSpawn = -math.huge, debris = {}, samples = {},
			damageBudget = 0, systemsBudget = 0, systems = {}, protectedUntil = 0, exited = false,
		}
		states[p] = s
	end
	return s
end

local function notify(p: Player, text: string)
	(remotes:FindFirstChild("Notify") :: RemoteEvent):FireClient(p, text)
end
AircraftService.notify = notify

-- Gear height: CoM height above ground when resting on the gear (metres).
local function restHeight(cfg: any): number
	local u = cfg.gear.units[2] -- fallback
	for _, g in cfg.gear.units do
		if g.brakes then -- the first main gear leg
			u = g
			break
		end
	end
	return -(u.pos[2] - u.strutLength - u.wheelRadius) - u.staticCompression * u.travel
end

local function setCollisionGroup(model: Instance, group: string)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

local function destroyDebrisOf(p: Player)
	local s = getState(p)
	for _, d in s.debris do
		if d.model.Parent then
			d.model:Destroy()
		end
	end
	s.debris = {}
end

local function destroyAircraft(p: Player)
	local s = getState(p)
	if s.aircraft then
		s.aircraft:Destroy()
		s.aircraft = nil
	end
	if p.Parent then
		p.ReplicationFocus = nil
	end
	s.samples = {}
	s.systems = {}
end

-- Options validation --------------------------------------------------------------
-- The default aircraft if the request names none (or a locked/unknown one).
local function defaultAircraftId(): string
	local cfg = Registry.get("kestrel72")
	if cfg and cfg.unlocked then
		return "kestrel72"
	end
	return Selection.flyableAircraft(Registry)[1]
end

local function sanitizeOptions(raw: any): any?
	if type(raw) ~= "table" then
		return nil
	end
	-- Any unlocked registry aircraft; anything else falls back to the default type.
	local aircraftId = defaultAircraftId()
	if type(raw.aircraftId) == "string" then
		local c = Registry.get(raw.aircraftId)
		if c and c.unlocked then
			aircraftId = raw.aircraftId
		end
	end
	local cfg = Registry.get(aircraftId)
	if not cfg then
		return nil
	end
	local mode = "free"
	for _, m in GameConfig.modes do
		if raw.mode == m.id then
			mode = m.id
		end
	end
	-- Stunts always flies the stunt plane, whatever the aircraft picker says.
	if mode == Stunts.MODE then
		local stuntCfg = Registry.get(Registry.stuntAircraftId)
		if stuntCfg then
			aircraftId = Registry.stuntAircraftId
			cfg = stuntCfg
		end
	end
	local assist = "easy"
	for _, m in Assist.MODES do
		if raw.assist == m then
			assist = m
		end
	end
	-- Departure airport: as asked, else the requested spawn's airport, else the first.
	local requested = if type(raw.spawnId) == "string" then Airports.getSpawn(raw.spawnId) else nil
	local airport = Airports.order[1]
	if type(raw.airport) == "string" and Airports.list[raw.airport] then
		airport = raw.airport
	elseif requested and requested.kind ~= "air" and Airports.list[requested.airport] then
		airport = requested.airport
	end
	local destination = nil
	if type(raw.destination) == "string" and Airports.list[raw.destination] then
		destination = raw.destination
	end
	-- The spawn must be one the menu offers for this airport, aircraft and mode (so a big
	-- aircraft never gets a stand or runway it doesn't fit); otherwise the first runway.
	local sp = Selection.resolveSpawn(raw.spawnId, airport, cfg, mode, destination)
	if not sp then
		return nil
	end
	local failures = {}
	if mode == "sandbox" and type(raw.failures) == "table" then
		for _, f in GameConfig.failures do
			if raw.failures[f.id] == true then
				failures[f.id] = true
			end
		end
	end
	return {
		aircraftId = aircraftId,
		airport = airport,
		spawnId = sp.id,
		mode = mode,
		assist = assist,
		destination = destination,
		failures = failures,
	}
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundBelow(x: number, z: number, fromY: number): number?
	rayParams.FilterDescendantsInstances = { aircraftFolder, debrisFolder }
	local r = Workspace:Raycast(Vector3.new(x, fromY + 200, z), Vector3.new(0, -2000, 0), rayParams)
	return if r then r.Position.Y else nil
end

-- Wingspan (metres) of a spawned aircraft model, for spacing checks.
local function modelSpanM(model: Model): number
	local id = model:GetAttribute("AircraftId")
	local cfg = if type(id) == "string" then Registry.get(id) else nil
	if not cfg then
		return 40
	end
	return (Selection.dimensions(cfg))
end

-- Is another player's aircraft parked close enough to this spot that an aircraft with
-- wingspan `spanM` would overlap it? The radius grows with both aircraft's size.
local function spotOccupied(x: number, z: number, spanM: number, except: Player): boolean
	for p, s in states do
		if p ~= except and s.aircraft and s.aircraft.PrimaryPart then
			local pos = s.aircraft.PrimaryPart.Position
			local needM = (spanM + modelSpanM(s.aircraft)) * 0.5 + 5
			local radius = math.max(160, needM * Units.STUDS_PER_METER)
			if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(x, 0, z)).Magnitude < radius then
				return true
			end
		end
	end
	return false
end

-- Choose the spawn, moving to a free slot when the requested one is taken. A taken
-- runway start tries the other runway end before falling back to a free gate; only
-- spots that fit this aircraft (Selection.spawnList) are considered.
local function resolveSpawn(p: Player, options: any, cfg: any): any
	local sp = (Airports.getSpawn(options.spawnId) or Stunts.getSpawn(options.spawnId)) :: any
	if sp.kind ~= "gate" and sp.kind ~= "runway" then
		return sp
	end
	local spanM = (Selection.dimensions(cfg))
	if not spotOccupied(sp.x, sp.z, spanM, p) then
		return sp
	end
	local list = Selection.spawnList(options.airport, cfg, options.mode, options.destination)
	local order = if sp.kind == "runway" then { "runway", "gate" } else { "gate", "runway" }
	for _, kind in order do
		for _, alt in list do
			if alt.kind == kind and alt.id ~= sp.id and not spotOccupied(alt.x, alt.z, spanM, p) then
				if kind ~= sp.kind then
					notify(p, if kind == "gate" then "Runways are busy, starting at a gate instead." else "Gates are full, starting on the runway instead.")
				end
				return alt
			end
		end
	end
	return sp
end

local placeAircraft: (Player, PlayerState, any, any, any, CFrame, boolean) -> ()

function AircraftService.spawn(p: Player, rawOptions: any)
	local s = getState(p)
	local now = os.clock()
	if now - s.lastSpawn < GameConfig.rateLimits.spawnSeconds then
		return
	end
	if ReplicatedStorage:GetAttribute("WorldReady") ~= true then
		-- hold the latest request and serve it as soon as the world is ready
		local first = s.pendingSpawn == nil
		s.pendingSpawn = rawOptions
		notify(p, "The world is still being built. Your flight starts as soon as it is ready...")
		if first then
			task.spawn(function()
				while ReplicatedStorage:GetAttribute("WorldReady") ~= true do
					ReplicatedStorage:GetAttributeChangedSignal("WorldReady"):Wait()
				end
				local o = s.pendingSpawn
				s.pendingSpawn = nil
				if o ~= nil and p.Parent then
					s.lastSpawn = -math.huge
					AircraftService.spawn(p, o)
				end
			end)
		end
		return
	end
	local options = sanitizeOptions(rawOptions)
	if not options then
		notify(p, "Spawn request rejected.")
		return
	end
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		notify(p, "Waiting for your character to load...")
		return
	end
	s.lastSpawn = now
	s.options = options
	s.exited = false

	destroyAircraft(p)
	destroyDebrisOf(p)

	local cfg = Registry.get(options.aircraftId)
	local sp = resolveSpawn(p, options, cfg)
	local y = sp.y
	if sp.kind == "gate" or sp.kind == "runway" then
		local gy = groundBelow(sp.x, sp.z, sp.y)
		y = (gy or sp.y) + restHeight(cfg) * Units.STUDS_PER_METER + 0.3
	end
	local cf = CFrame.new(sp.x, y, sp.z) * CFrame.Angles(0, -math.rad(sp.heading), 0) * CFrame.Angles(math.rad(sp.pitchDeg or 0), 0, 0)
	placeAircraft(p, s, options, cfg, sp, cf, false)
end

-- Build the aircraft at `cf`, seat the pilot and hand it to the client. `repaired`
-- (Fix all) keeps the current mission/race going instead of starting a new one.
placeAircraft = function(p: Player, s: PlayerState, options: any, cfg: any, sp: any, cf: CFrame, repaired: boolean)
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local model = AircraftBuilder.build(cfg, cf)
	model.Name = `{cfg.displayName} ({p.Name})`
	model:SetAttribute("OwnerUserId", p.UserId)
	model:SetAttribute("SpawnId", sp.id)
	model:SetAttribute("SpawnSpeed", sp.speed)
	model:SetAttribute("SpawnKind", sp.kind)
	model:SetAttribute("EnginesRunning", sp.enginesRunning)
	model:SetAttribute("GearDown", sp.gearDown)
	model:SetAttribute("Flaps", sp.flaps)
	model:SetAttribute("Throttle", sp.throttle)
	model:SetAttribute("Mode", options.mode)
	model:SetAttribute("Assist", options.assist)
	model:SetAttribute("Toughness", Assist.toughness(options.assist))
	model:SetAttribute("Failures", HttpService:JSONEncode(options.failures))
	model:SetAttribute("Destination", options.destination or "")
	setCollisionGroup(model, "AircraftProtected")
	s.protectedUntil = os.clock() + GameConfig.spawnProtectionSeconds
	model.Parent = aircraftFolder
	s.aircraft = model

	local seat = model:FindFirstChild("PilotSeat", true) :: Seat
	-- Move the character next to the seat first so Sit() never drags it across the map.
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.CFrame = seat.CFrame + Vector3.new(0, 3, 0)
	end
	seat:Sit(humanoid)
	-- stream the world around the aircraft, not wherever the character started
	p.ReplicationFocus = model.PrimaryPart

	;(remotes:FindFirstChild("AircraftAssigned") :: RemoteEvent):FireClient(p, model, options, sp, repaired)
	if onSpawned and not repaired then
		onSpawned(p, options, sp)
	end
end

-- Fix all: rebuild the aircraft where it is with every part back on, all damage,
-- dents, bends and failures gone. Flying: same position, heading and speed. Wrecked or
-- slow: upright on the ground below, engines kept running, ready to go again.
function AircraftService.repair(p: Player)
	local s = getState(p)
	local old = s.aircraft
	local options = s.options
	local core = old and old.PrimaryPart
	if not old or not options or not core then
		return
	end
	local now = os.clock()
	if now - (s.lastRepair or -math.huge) < GameConfig.crash.repairCooldown then
		return
	end
	s.lastRepair = now
	local cfg = Registry.get(old:GetAttribute("AircraftId") :: string)
	if not cfg then
		return
	end
	local cf = core.CFrame
	local v = core.AssemblyLinearVelocity * Units.METERS_PER_STUD
	local sys = s.systems or {}
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local heading = -math.deg(math.atan2(-flat.Unit.X, -flat.Unit.Z))
	local crashed = sys.Crashed == true or old:GetAttribute("Exploded") == true
	local forward = v:Dot(look)
	local gy = groundBelow(cf.Position.X, cf.Position.Z, cf.Position.Y)
	local agl = if gy then (cf.Position.Y - gy) * Units.METERS_PER_STUD else math.huge
	local sp: any
	if crashed or forward < 25 or agl < 8 then
		local y = (gy or cf.Position.Y) + restHeight(cfg) * Units.STUDS_PER_METER + 0.3
		sp = {
			id = "repair", kind = "runway", x = cf.Position.X, y = y, z = cf.Position.Z, heading = heading,
			pitchDeg = 0, speed = 0, enginesRunning = sys.EnginesRunning ~= false, gearDown = true, flaps = 1, throttle = 0,
		}
		cf = CFrame.new(sp.x, y, sp.z) * CFrame.Angles(0, -math.rad(heading), 0)
	else
		local n1 = ((sys.N1_1 or 0) + (sys.N1_2 or sys.N1_1 or 0)) / 2
		sp = {
			id = "repair", kind = "air", x = cf.Position.X, y = cf.Position.Y, z = cf.Position.Z, heading = heading,
			pitchDeg = 0, speed = forward, enginesRunning = sys.EnginesRunning ~= false,
			gearDown = sys.GearDown == true, flaps = if type(sys.Flaps) == "number" then sys.Flaps else 1,
			throttle = math.clamp(n1 / 100, 0.3, 1),
		}
	end
	-- Menu failures are fixed too, for this flight and for R resets after it.
	options = table.clone(options)
	options.failures = {}
	s.options = options
	s.exited = false
	destroyAircraft(p)
	destroyDebrisOf(p)
	placeAircraft(p, s, options, cfg, sp, cf, true)
	notify(p, "Fixed! Every part is back on.")
end

function AircraftService.reset(p: Player)
	local s = getState(p)
	if s.options then
		s.lastSpawn = -math.huge
		AircraftService.spawn(p, s.options)
	end
end

-- Client says its flight controller is running: release the aircraft to its physics.
local function onControllerReady(p: Player, model: any)
	local s = getState(p)
	if typeof(model) ~= "Instance" or model ~= s.aircraft then
		return
	end
	local core = (model :: Model).PrimaryPart
	if core and core.Anchored then
		core.Anchored = false
		core:SetNetworkOwner(p)
	end
end

-- Detachment ---------------------------------------------------------------------
local function trimDebris()
	-- global and per-player caps, oldest first
	table.sort(allDebris, function(a, b)
		return a.t < b.t
	end)
	local totalPieces = 0
	for _, d in allDebris do
		if d.model.Parent then
			totalPieces += 1
		end
	end
	while totalPieces > GameConfig.debris.maxPiecesTotal and #allDebris > 0 do
		local d = table.remove(allDebris, 1) :: any
		if d.model.Parent then
			d.model:Destroy()
			totalPieces -= 1
		end
	end
end

-- Count a debris model against the per-player and global caps, and schedule cleanup.
local function registerDebris(p: Player, debris: Model)
	local s = getState(p)
	local entry = { model = debris, t = os.clock(), owner = p }
	table.insert(s.debris, entry)
	table.insert(allDebris, entry)
	while #s.debris > GameConfig.debris.maxPiecesPerPlayer do
		local old = table.remove(s.debris, 1) :: any
		if old.model.Parent then
			old.model:Destroy()
		end
	end
	trimDebris()
	task.delay(GameConfig.debris.lifetime, function()
		if debris.Parent and not debris:FindFirstChild("PilotSeat", true) then
			debris:Destroy()
		end
	end)
end

local function detachComponent(p: Player, model: Model, compName: string, cfg: any)
	local comp = model:FindFirstChild(compName)
	if not comp or not comp:IsA("Model") then
		return
	end
	local root = comp.PrimaryPart
	if not root then
		return
	end
	-- Momentum: remember how the aircraft was moving so the piece keeps it.
	local core = model.PrimaryPart
	local v = if core then core.AssemblyLinearVelocity else Vector3.zero
	local w = if core then core.AssemblyAngularVelocity else Vector3.zero
	local origin = if core then core.Position else root.Position
	local joint = root:FindFirstChild("Joint")
	if joint then
		joint:Destroy()
	end
	local debris = Instance.new("Model")
	debris.Name = `Debris_{p.UserId}_{compName}`
	debris:SetAttribute("DebrisOwner", p.UserId)
	-- Collect this component and every descendant component (they stay welded to it).
	local names = { compName }
	local i = 1
	while i <= #names do
		for name, c in cfg.components do
			if c.parent == names[i] then
				table.insert(names, name)
			end
		end
		i += 1
	end
	for _, n in names do
		local m = model:FindFirstChild(n)
		if m then
			m.Parent = debris
		end
	end
	local seat = debris:FindFirstChild("PilotSeat", true)
	for _, d in debris:GetDescendants() do
		if d:IsA("BasePart") then
			if d.CanCollide then
				d.Massless = false
			end
			d.CollisionGroup = GameConfig.CollisionGroups.Debris
			d:SetAttribute("DebrisOwner", p.UserId)
		end
	end
	debris.PrimaryPart = root
	debris.Parent = debrisFolder
	-- The pilot rides along if the cockpit section separates; otherwise debris is
	-- simulated by the server so it can't be used to fling other players.
	if not seat then
		if not root.Anchored then
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
		end
	end
	if core and not root.Anchored then
		local away = root.Position - origin
		CrashService.inherit(root, v, w, origin, if away.Magnitude > 1e-3 then away.Unit else Vector3.zero, 1.5)
	end
	registerDebris(p, debris)
	CrashService.track(p, debris, Crash.profiles(cfg)[compName])
	CrashService.fx("shards", root.Position, 2, root.AssemblyLinearVelocity, p)
end

local function maxRecentSpeed(s: PlayerState, window: number): number
	local now = os.clock()
	local best = 0
	for i = #s.samples, 1, -1 do
		local smp = s.samples[i]
		if now - smp.t > window then
			break
		end
		best = math.max(best, smp.vel.Magnitude * Units.METERS_PER_STUD)
	end
	return best
end

local function onReportDamage(p: Player, model: any, compName: any, state: any, health: any, impactSpeed: any, withParent: any)
	local s = getState(p)
	if typeof(model) ~= "Instance" or model ~= s.aircraft then
		return
	end
	if type(compName) ~= "string" or type(state) ~= "string" or not VALID_STATES[state] then
		return
	end
	if type(health) ~= "number" or health ~= health or type(impactSpeed) ~= "number" or impactSpeed ~= impactSpeed then
		return
	end
	s.damageBudget += 1
	if s.damageBudget > GameConfig.rateLimits.damageReportsPerSecond then
		return
	end
	local cfg = Registry.get((model :: Model):GetAttribute("AircraftId") :: string)
	if not cfg or not cfg.components[compName] then
		return
	end
	-- Collapse (break-apart off): may arrive while the component is already "failed".
	if state == "failed" and health <= 0.001 then
		CrashService.collapse(model :: Model, cfg, compName)
	end
	-- States only get worse.
	local prev = (model :: Model):GetAttribute("Dmg_" .. compName) :: string?
	local rank = { normal = 0, degraded = 1, failed = 2, detached = 3 }
	if prev and rank[prev] >= rank[state] then
		return
	end
	-- Plausibility: a claimed big impact must match motion the server actually saw.
	-- (Damage only ever affects the reporting player's own aircraft.)
	if state == "detached" and impactSpeed > 0 then
		local seen = maxRecentSpeed(s, 3)
		if impactSpeed > seen * 1.6 + 12 then
			return
		end
	end
	;(model :: Model):SetAttribute("Dmg_" .. compName, state)
	;(model :: Model):SetAttribute("Health_" .. compName, math.clamp(health, 0, 1))
	if state == "detached" and withParent ~= true then
		detachComponent(p, model :: Model, compName, cfg)
	end

end

local SYSTEM_KEYS = {
	GearDown = "boolean", Flaps = "number", Speedbrake = "number", ParkingBrake = "boolean",
	EnginesRunning = "boolean", N1_1 = "number", N1_2 = "number", Reverse = "boolean",
	Elevator = "number", Aileron = "number", Rudder = "number", Lights = "boolean", Crashed = "boolean",
}

local function onReportSystems(p: Player, model: any, data: any)
	local s = getState(p)
	if typeof(model) ~= "Instance" or model ~= s.aircraft or type(data) ~= "table" then
		return
	end
	s.systemsBudget += 1
	if s.systemsBudget > GameConfig.rateLimits.systemsReportsPerSecond then
		return
	end
	for k, t in SYSTEM_KEYS do
		local v = data[k]
		if type(v) == t then
			if t == "number" then
				if v ~= v then
					continue
				end
				v = math.clamp(v, -200, 200)
			end
			s.systems[k] = v
			;(model :: Model):SetAttribute("Sys_" .. k, v)
		end
	end
end

-- Monitoring ----------------------------------------------------------------------
local monitorAccum = 0
local function monitor(dt: number)
	monitorAccum += dt
	if monitorAccum < 0.1 then
		return
	end
	local step = monitorAccum
	monitorAccum = 0
	local now = os.clock()
	for p, s in states do
		s.damageBudget = math.max(0, s.damageBudget - GameConfig.rateLimits.damageReportsPerSecond * step)
		s.systemsBudget = math.max(0, s.systemsBudget - GameConfig.rateLimits.systemsReportsPerSecond * step)
		local model = s.aircraft
		if not model or not model.Parent then
			continue
		end
		local core = model.PrimaryPart
		if not core then
			continue
		end
		if s.protectedUntil > 0 and now > s.protectedUntil then
			s.protectedUntil = 0
			-- Stunts racers stay ghosts to each other: everyone starts at the same gate.
			local racing = s.options ~= nil and s.options.mode == Stunts.MODE
			setCollisionGroup(model, if GameConfig.aircraftCollide and not racing then GameConfig.CollisionGroups.Aircraft else "AircraftProtected")
		end
		if core.Anchored then
			continue
		end
		local pos, vel = core.Position, core.AssemblyLinearVelocity
		local last = s.samples[#s.samples]
		-- Sanity: impossible speed or teleport -> reset.
		local speedMps = vel.Magnitude * Units.METERS_PER_STUD
		if speedMps ~= speedMps or speedMps > GameConfig.limits.maxSpeed then
			notify(p, "Aircraft reset: impossible speed detected.")
			AircraftService.reset(p)
			continue
		end
		if last and (pos - last.pos).Magnitude > GameConfig.limits.maxTeleportStudsPerSample * math.max(1, (now - last.t) / 0.1) then
			notify(p, "Aircraft reset: invalid position change.")
			AircraftService.reset(p)
			continue
		end
		if pos.Y < -600 then
			destroyAircraft(p)
			notify(p, "Aircraft lost. Press R to reset.")
			continue
		end
		table.insert(s.samples, { t = now, pos = pos, vel = vel })
		while #s.samples > 60 do
			table.remove(s.samples, 1)
		end
		-- Pilot left the seat: park the aircraft if it is slow.
		local character = p.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local seat = model:FindFirstChild("PilotSeat", true) :: Seat?
		if humanoid and seat and seat.Occupant ~= humanoid and not s.exited then
			s.exited = true
			if speedMps < 5 then
				core.Anchored = true
			end
		end
		if onTelemetry then
			onTelemetry(p, s, model)
		end
	end
	-- Expire debris records
	for i = #allDebris, 1, -1 do
		if not allDebris[i].model.Parent then
			table.remove(allDebris, i)
		end
	end
end

function AircraftService.getState(p: Player): PlayerState
	return getState(p)
end

function AircraftService.setTelemetryHandler(fn: (Player, any, any) -> ())
	onTelemetry = fn
end

function AircraftService.setSpawnHandler(fn: (Player, any, any) -> ())
	onSpawned = fn
end

function AircraftService.init(remoteFolder: Folder)
	remotes = remoteFolder
	aircraftFolder = Instance.new("Folder")
	aircraftFolder.Name = "Aircraft"
	aircraftFolder.Parent = Workspace
	debrisFolder = Instance.new("Folder")
	debrisFolder.Name = "Debris"
	debrisFolder.Parent = Workspace

	;(remotes:FindFirstChild("RequestSpawn") :: RemoteEvent).OnServerEvent:Connect(function(p: Player, raw: any)
		local ok, err = xpcall(AircraftService.spawn, debug.traceback, p, raw)
		if not ok then
			warn("[Spawn] failed for " .. p.Name .. ": " .. tostring(err))
			notify(p, "Could not create the aircraft (see Output, F9): " .. tostring(err):split("\n")[1])
		end
	end)
	;(remotes:FindFirstChild("RequestReset") :: RemoteEvent).OnServerEvent:Connect(AircraftService.reset)
	;(remotes:FindFirstChild("RequestRepair") :: RemoteEvent).OnServerEvent:Connect(AircraftService.repair)
	;(remotes:FindFirstChild("ControllerReady") :: RemoteEvent).OnServerEvent:Connect(onControllerReady)
	;(remotes:FindFirstChild("ReportDamage") :: RemoteEvent).OnServerEvent:Connect(onReportDamage)
	;(remotes:FindFirstChild("ReportSystems") :: RemoteEvent).OnServerEvent:Connect(onReportSystems)

	Players.PlayerRemoving:Connect(function(p)
		destroyAircraft(p)
		destroyDebrisOf(p)
		states[p] = nil
	end)
	Players.PlayerAdded:Connect(function(p)
		p.CharacterRemoving:Connect(function()
			destroyAircraft(p)
		end)
	end)
	for _, p in Players:GetPlayers() do
		p.CharacterRemoving:Connect(function()
			destroyAircraft(p)
		end)
	end
	CraterService.init({
		remotes = remotes,
		getAircraft = function(p: Player): Model?
			return getState(p).aircraft
		end,
		maxRecentSpeed = function(p: Player, window: number): number
			return maxRecentSpeed(getState(p), window)
		end,
		ignore = function(): { Instance }
			local list: { Instance } = { aircraftFolder, debrisFolder }
			for _, pl in Players:GetPlayers() do
				if pl.Character then
					table.insert(list, pl.Character)
				end
			end
			local fires = Workspace:FindFirstChild("Wildfires")
			if fires then
				table.insert(list, fires)
			end
			return list
		end,
	})
	CrashService.init({
		remotes = remotes,
		debrisFolder = debrisFolder,
		getAircraft = function(p: Player): Model?
			return getState(p).aircraft
		end,
		registerDebris = registerDebris,
		maxRecentSpeed = function(p: Player, window: number): number
			return maxRecentSpeed(getState(p), window)
		end,
	})
	RunService.Heartbeat:Connect(monitor)
end

return AircraftService
