--!strict
-- Client-side flight controller for the locally owned aircraft.
--
-- Every frame (RunService.PreSimulation, i.e. before the physics step):
--   1. read the assembly's velocity/orientation and convert studs -> SI body axes,
--   2. ray-cast each landing-gear strut and sample water depth at hull points,
--   3. run Assist + FlightModel (pure modules shared with the offline tests),
--   4. convert the resulting SI force/moment to Roblox units and write them to the
--      aircraft's VectorForce/Torque (world-relative),
--   5. detect impacts (unexplained velocity changes + Touched contacts) and report
--      damage to the server, animate control surfaces/gear/fans, update telemetry.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Units = require(Shared.Units)
local FlightModel = require(Shared.FlightModel)
local Assist = require(Shared.Assist)
local Damage = require(Shared.Damage)
local Crash = require(Shared.Crash)
local GameConfig = require(Shared.GameConfig)
local Registry = require(Shared.AircraftRegistry)
local WorldGen = require(Shared.WorldGen)
local Stunts = require(Shared.Stunts)
local Airports = require(Shared.Airports)
local Wildfire = require(Shared.Wildfire)
local Hazards = require(Shared.Hazards)
local Effects = require(script.Parent.Effects)

local MPS = Units.METERS_PER_STUD
local SPM = Units.STUDS_PER_METER

local FlightController = {}
FlightController.__index = FlightController

local function finite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e15 and math.abs(v.Y) < 1e15 and math.abs(v.Z) < 1e15
end

function FlightController.new(model: Model, options: any, spawnPoint: any, remotes: Folder, input: any)
	local self = setmetatable({}, FlightController) :: any
	local cfg = Registry.get(model:GetAttribute("AircraftId") :: string)
	if options.mode == Stunts.MODE then
		-- racing: steeper banks and quicker pulls in Easy (a copy; the registry is untouched)
		cfg = Stunts.raceTune(cfg)
	end
	self.cfg = cfg
	self.model = model
	self.remotes = remotes
	self.input = input
	self.options = options
	self.spawn = spawnPoint
	self.core = model.PrimaryPart :: BasePart
	self.force = self.core:WaitForChild("AeroForce") :: VectorForce
	self.torque = self.core:WaitForChild("AeroTorque") :: Torque
	self.started = false
	self.alive = true
	self.time = 0
	self.crashed = false

	local enginesRunning = model:GetAttribute("EnginesRunning") == true
	local gearDown = model:GetAttribute("GearDown") ~= false
	local flaps = (model:GetAttribute("Flaps") :: number?) or 1
	self.fm = FlightModel.new(cfg, { enginesRunning = enginesRunning, gearDown = gearDown, flaps = flaps, toughness = Assist.toughness(options.assist), breakApart = GameConfig.crash.breakApart })
	self.toughness = Assist.toughness(options.assist)
	self.env = FlightModel.newEnv(cfg)
	self.ctl = FlightModel.newControls()
	self.assist = Assist.new(options.assist)

	-- Initialise pilot controls to match the spawn state.
	local raw = input.raw
	raw.throttle = (model:GetAttribute("Throttle") :: number?) or 0
	raw.flaps = flaps
	raw.gearDown = gearDown
	raw.parkingBrake = spawnPoint.kind == "gate"
	raw.speedbrake = 0
	raw.trim = 0
	raw.pitch, raw.roll, raw.yaw = 0, 0, 0
	input.maxFlaps = #cfg.aero.flaps.labels
	if spawnPoint.kind == "approach" then
		self.assist.autoTrim = 0.75
	elseif spawnPoint.kind == "air" then
		self.assist.autoTrim = 0.1
	end
	if options.assist == "simulation" then
		raw.trim = self.assist.autoTrim
	end

	-- Sandbox failures
	local ok, failures = pcall(function()
		return HttpService:JSONDecode((model:GetAttribute("Failures") :: string?) or "{}")
	end)
	if ok and type(failures) == "table" then
		for k, v in failures do
			if v == true then
				self.fm:setFailure(k, true)
			end
		end
	end

	-- Collect animated joints and hull parts.
	self.surfaces = {}
	self.gearMotors = {}
	self.fans = {}
	self.smoke = {}
	self.hullParts = {}
	self.afterburners = {}
	self.landingLight = nil :: SpotLight?
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			if d:GetAttribute("Surface") then
				table.insert(self.surfaces, d)
			elseif d:GetAttribute("GearName") then
				self.gearMotors[d:GetAttribute("GearName") :: string] = d
			elseif d:GetAttribute("EngineIndex") then
				self.fans[d:GetAttribute("EngineIndex") :: number] = { motor = d, angle = 0 }
			end
		elseif d:IsA("ParticleEmitter") and d.Name == "FailureSmoke" then
			local comp = (d:FindFirstAncestorWhichIsA("Model") :: Model).Name
			self.smoke[comp] = d
		elseif d:IsA("BasePart") and d:GetAttribute("AfterburnerIndex") then
			table.insert(self.afterburners, { part = d, index = d:GetAttribute("AfterburnerIndex") :: number, light = d:FindFirstChild("AfterburnerLight") :: PointLight? })
		elseif d:IsA("SpotLight") and d.Name == "LandingLight" then
			self.landingLight = d
		elseif d:IsA("BasePart") and d.CanTouch and d:GetAttribute("Component") then
			table.insert(self.hullParts, d)
		end
	end
	self.gearCfg = {}
	for i, u in cfg.gear.units do
		self.gearCfg[u.name] = { index = i, cfg = u }
	end

	-- Contact tracking for impact localisation.
	self.lastTouch = {} :: { [string]: number }
	self.lastContactPoint = {} :: { [string]: Vector3 } -- body metres
	self.lastImpactReport = {} :: { [string]: number }
	self.touchCount = {} :: { [string]: number }
	self.connections = {}
	local character = Players.LocalPlayer.Character
	local function isForeign(hit: BasePart): boolean
		if hit:IsDescendantOf(model) then
			return false
		end
		if character and hit:IsDescendantOf(character) then
			return false
		end
		if hit:GetAttribute("DebrisOwner") == Players.LocalPlayer.UserId then
			return false
		end
		local fx = Workspace:FindFirstChild("LocalEffects")
		if fx and hit:IsDescendantOf(fx) then
			return false
		end
		local parentModel = hit:FindFirstAncestorWhichIsA("Model")
		if parentModel and parentModel:FindFirstChildOfClass("Humanoid") then
			return false
		end
		return true
	end
	for _, p in self.hullParts do
		local comp = p:GetAttribute("Component") :: string
		table.insert(self.connections, p.Touched:Connect(function(hit)
			-- Torn-off sections keep this connection; they are debris now, not the aircraft.
			if isForeign(hit) and p:IsDescendantOf(model) then
				self.lastTouch[comp] = self.time
				local core = self.core
				if core and core.Parent then
					self.lastContactPoint[comp] = core.CFrame:PointToObjectSpace(p.Position) * MPS
				end
				self.touchCount[comp] = (self.touchCount[comp] or 0) + 1
				self.lastContactPart = p
			end
		end))
		table.insert(self.connections, p.TouchEnded:Connect(function(hit)
			if isForeign(hit) then
				self.touchCount[comp] = math.max(0, (self.touchCount[comp] or 0) - 1)
			end
		end))
	end

	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { model }
	if character then
		table.insert(ignore, character)
	end
	local debrisFolder = Workspace:FindFirstChild("Debris")
	if debrisFolder then
		table.insert(ignore, debrisFolder)
	end
	local fx = Workspace:FindFirstChild("LocalEffects")
	if fx then
		table.insert(ignore, fx)
	end
	self.rayParams.FilterDescendantsInstances = ignore

	-- Impact detector state
	self.prevV = nil :: Vector3?
	self.prevW = nil :: Vector3?
	self.prevAccel = Vector3.zero
	self.compRefs = {}
	for name, c in cfg.components do
		self.compRefs[name] = Vector3.new(c.ref[1], c.ref[2], c.ref[3])
	end
	self.lastImpact = {} :: { [string]: number }
	self.impactCount = 0 -- read by SoundController
	self.impactDv = 0
	self.lastTouchdownIndex = 0
	self.systemsTimer = 0
	self.lastSystems = ""
	self.touchdownFlash = nil :: any
	self.telemetry = {}
	self.nav = { destination = options.destination }
	-- water bomber: drops are batched and reported a few times a second
	self.dropKg = 0
	self.dropTimer = 0
	self.fxTimer = 0
	self.airportTimer = 0
	self.groundY = 0

	remotes.ControllerReady:FireServer(model)
	return self
end

function FlightController:destroy()
	self.alive = false
	for _, c in self.connections do
		c:Disconnect()
	end
	self.connections = {}
	if self.force.Parent then
		self.force.Force = Vector3.zero
		self.torque.Torque = Vector3.zero
	end
end

function FlightController:command(name: string)
	local fm = self.fm
	if name == "engines" then
		if fm:enginesRunning() or fm.engines[1].starting then
			fm:stopEngines()
		else
			fm:startEngines()
		end
	elseif name == "assist" then
		local was = self.assist.mode
		self.assist.mode = Assist.nextMode(was)
		if self.assist.mode == "simulation" then
			self.input.raw.trim = self.assist.autoTrim -- hand the auto-trim to the pilot
		elseif was == "simulation" then
			self.assist.autoTrim = self.input.raw.trim
			self.input.raw.trim = 0
		end
	end
end

function FlightController:setFailure(kind: string, on: boolean)
	self.fm:setFailure(kind, on)
end

-- Failures and weather hazards (HUD Events button): break things through the normal
-- damage model, so the server tears the real parts off as in a crash. Returns the plan's
-- message (or why nothing happened).
function FlightController:applyHazard(plan: any): string
	if self.crashed then
		return "The aircraft has already crashed. Press R to reset"
	end
	self.eventUntil = self.time + 1.5
	local dents = Hazards.apply(self.fm, plan)
	local cf = self.core.CFrame
	for _, d in dents do
		local ref = self.compRefs[d.component]
		if ref then
			local dir = Vector3.new(math.random() - 0.5, -0.6, math.random() - 0.5).Unit
			self.lastImpact[d.component] = d.dv
			self.remotes.ReportImpact:FireServer(self.model, d.component, ref, dir, d.dv)
			local pos = cf:PointToWorldSpace(ref * SPM)
			Effects.debrisPuff(pos, 1.5)
			Effects.sparks(pos, 2)
		end
	end
	self.impactCount += 1 -- impact sound
	self.impactDv = 16
	Effects.shake(0.9)
	return plan.message
end

local function reportDamage(self: any, ev: any)
	local remotes = self.remotes
	local comp = ev.component
	local c = self.fm.damage.components[comp]
	remotes.ReportDamage:FireServer(self.model, comp, ev.state, ev.health, self.lastImpact[comp] or 0, c and c.detachedWithParent or false)
end

-- Main per-frame step.
function FlightController:step(dt: number)
	if not self.alive then
		return
	end
	local core = self.core
	if not core.Parent or not self.model.Parent then
		self:destroy()
		return
	end
	dt = math.clamp(dt, 1 / 240, 1 / 20)
	self.time += dt
	local raw = self.input:update(dt)

	if not self.started then
		if not core.Anchored then
			self.started = true
			self.startTime = self.time
			local spd = (self.model:GetAttribute("SpawnSpeed") :: number?) or 0
			core.AssemblyLinearVelocity = core.CFrame.LookVector * (spd * SPM)
			core.AssemblyAngularVelocity = Vector3.zero
		else
			self:updateVisuals(dt)
			return
		end
	end

	local cf = core.CFrame
	local fm, env, cfg = self.fm, self.env, self.cfg
	local vWorld = core.AssemblyLinearVelocity * MPS -- m/s
	local wWorld = core.AssemblyAngularVelocity
	local wind = self.windProvider and self.windProvider(cf.Position, self.time) or Vector3.zero
	self.lastWind = wind
	local vb = cf:VectorToObjectSpace(vWorld)
	local vab = cf:VectorToObjectSpace(vWorld - wind)
	local wb = cf:VectorToObjectSpace(wWorld)
	local ub = cf:VectorToObjectSpace(Vector3.yAxis)
	env.vgx, env.vgy, env.vgz = vb.X, vb.Y, vb.Z
	env.vax, env.vay, env.vaz = vab.X, vab.Y, vab.Z
	env.wx, env.wy, env.wz = wb.X, wb.Y, wb.Z
	env.ux, env.uy, env.uz = ub.X, ub.Y, ub.Z
	env.altitude = cf.Position.Y * MPS

	-- Height above ground
	local down = -Vector3.yAxis * 6000
	local hit = Workspace:Raycast(cf.Position, down, self.rayParams)
	-- CoM height above the wheels' contact points at rest (the main gear)
	local mainGear = cfg.gear.units[2] or cfg.gear.units[1]
	local restH = -(mainGear.pos[2] - mainGear.strutLength - mainGear.wheelRadius)
	env.agl = if hit then (cf.Position.Y - hit.Position.Y) * MPS - restH else 1e4
	self.groundY = if hit then hit.Position.Y else WorldGen.SEA_LEVEL
	-- over the sea the water surface counts as the ground (seaplanes, ditching)
	env.agl = math.min(env.agl, (cf.Position.Y - WorldGen.SEA_LEVEL) * MPS - restH)

	-- Gear struts
	local strutDir = -cf.UpVector
	for i, u in cfg.gear.units do
		local h = env.gearHits[i]
		local origin = cf:PointToWorldSpace(Vector3.new(u.pos[1], u.pos[2], u.pos[3]) * SPM)
		local len = (u.strutLength + u.wheelRadius + 0.6) * SPM
		local r = Workspace:Raycast(origin, strutDir * len, self.rayParams)
		if r and r.Instance.CanCollide then
			local n = cf:VectorToObjectSpace(r.Normal)
			h.hit = true
			h.dist = (r.Position - origin).Magnitude * MPS
			h.nx, h.ny, h.nz = n.X, n.Y, n.Z
		else
			h.hit = false
		end
	end

	-- Water depth at hull points (only near sea level, only over the sea).
	local nearWater = cf.Position.Y < 120
	for i, hp in cfg.hullPoints do
		local d = -1
		if nearWater then
			local wp = cf:PointToWorldSpace(Vector3.new(hp[1], hp[2], hp[3]) * SPM)
			if wp.Y < WorldGen.SEA_LEVEL and WorldGen.meshHeight(wp.X, wp.Z) < WorldGen.SEA_LEVEL - 1 then
				d = (WorldGen.SEA_LEVEL - wp.Y) * MPS
			end
		end
		env.hullDepth[i] = d
	end

	-- water bombers refill from a hose when parked at an airport
	if cfg.waterTank then
		self.airportTimer -= dt
		if self.airportTimer <= 0 then
			self.airportTimer = 0.5
			local inside = false
			for _, id in Airports.order do
				if Airports.isInsideAirport(Airports.layout(id), cf.Position.X, cf.Position.Z) then
					inside = true
				end
			end
			env.refillAllowed = inside
		end
	end

	Assist.apply(self.assist, raw, self.ctl, env, fm, dt)
	local r = fm:step(env, self.ctl, dt)
	if cfg.waterTank then
		self:waterBomber(dt, cf, r)
	end

	-- Apply forces (SI body -> Roblox world units)
	local mass = fm:currentMass()
	local assemblyMass = core.AssemblyMass
	local coreMass = core.Mass
	local kF = assemblyMass / (mass * MPS)
	local kT = coreMass / (cfg.mass * MPS * MPS)
	local fWorld = cf:VectorToWorldSpace(Vector3.new(r.fx, r.fy, r.fz))
	local mWorld = cf:VectorToWorldSpace(Vector3.new(r.mx, r.my, r.mz))
	if self.crashed then
		fWorld, mWorld = Vector3.zero, Vector3.zero
	end
	if finite(fWorld) and finite(mWorld) then
		self.force.Force = fWorld * kF
		self.torque.Torque = mWorld * kT
	else
		self.force.Force = Vector3.zero
		self.torque.Torque = Vector3.zero
	end
	-- Hazards (tornado swirl) spin the airframe directly: the wind field is sampled at
	-- the centre of mass only, so a vortex's roll across the wings is added here.
	if self.spinProvider and not self.crashed then
		local spin = self.spinProvider(cf, self.time)
		if spin and finite(spin) and spin.Magnitude > 0 then
			core.AssemblyAngularVelocity += spin * dt
		end
	end

	self:detectImpacts(dt, cf, vWorld, wWorld, fWorld, mass)

	-- Damage events -> server
	for _, ev in Damage.drainEvents(fm.damage) do
		if ev.state == "section" then
			local cause = if self.time < (self.eventUntil or 0) then "event" else nil
			self.remotes.ReportSection:FireServer(self.model, ev.component, ev.section, self.lastImpact[ev.component] or 0, cause)
			local lp = self.lastContactPoint[ev.component] or self.compRefs[ev.component]
			if lp then
				local pos = cf:PointToWorldSpace(lp * SPM)
				Effects.debrisPuff(pos, 1.5)
				Effects.sparks(pos, 3)
			end
			Effects.shake(0.6)
			continue
		end
		reportDamage(self, ev)
		if ev.state == "detached" then
			local ref = self.compRefs[ev.component]
			if ref then
				local pos = cf:PointToWorldSpace(ref * SPM)
				Effects.debrisPuff(pos, 2)
				Effects.sparks(pos, 3)
			end
			Effects.shake(0.8)
		end
	end
	if fm.damage.destroyed and not self.crashed then
		self.crashed = true
		Effects.shake(2)
		-- Boom: the server sets off the explosion and digs a crater if we're on land.
		local dv = if self.time - (self.peakDvTime or -math.huge) < 1.5 then self.peakDv or 0 else vWorld.Magnitude
		self.remotes.ReportCrash:FireServer(self.model, cf.Position, math.max(dv, 0))
	end

	-- Touchdown report
	if fm.touchdownCount > self.lastTouchdownIndex then
		self.lastTouchdownIndex = fm.touchdownCount
		local vsFpm = (self.prevV and self.prevV.Y or vWorld.Y) * Units.FPM_PER_MPS
		self.remotes.ReportTouchdown:FireServer({ vsFpm = vsFpm })
		self.touchdownFlash = { vsFpm = vsFpm, t = self.time, g = r.gLoad }
		for _, g in fm.gears do
			if g.onGround then
				local p = cf:PointToWorldSpace(Vector3.new(g.cpx, g.cpy, g.cpz) * SPM)
				Effects.tyreSmoke(p)
			end
		end
		if vsFpm < -500 then
			Effects.shake(math.clamp(-vsFpm / 900, 0.2, 1.5))
		end
	end

	self:updateTelemetry(cf, vWorld, r, raw)
	self:reportSystems(dt)
	self:updateVisuals(dt)
	self.prevV = vWorld
	self.prevW = wWorld
end

-- Impacts: velocity changes the aerodynamic/gear forces cannot explain came from a
-- collision. Attribute them to components that were in contact, at those points.
function FlightController:detectImpacts(dt: number, cf: CFrame, v: Vector3, w: Vector3, fWorld: Vector3, mass: number)
	local fm = self.fm
	local prevV, prevW = self.prevV, self.prevW
	local expectedAccel = self.prevAccel
	self.prevAccel = fWorld / mass + Vector3.new(0, -Units.G, 0)
	if not prevV or not prevW then
		return
	end
	if self.time - (self.startTime or 0) < 1.0 then
		return -- let the aircraft settle after spawning
	end
	local dvUnexpected = (v - prevV) - expectedAccel * dt
	local dw = w - prevW
	local now = self.time
	local hitSomething = false
	local maxDv = 0
	for comp, ref in self.compRefs do
		local last = self.lastTouch[comp]
		if last and now - last < 0.15 and Damage.isAttached(fm.damage, comp) then
			local rWorld = cf:VectorToWorldSpace(ref)
			local dvp = (dvUnexpected + dw:Cross(rWorld)).Magnitude
			if dvp > 1.5 then
				self.lastImpact[comp] = dvp
				Damage.applyImpact(fm.damage, comp, dvp)
				hitSomething = true
				maxDv = math.max(maxDv, dvp)
				local point = self.lastContactPoint[comp] or ref
				local dvWorld = dvUnexpected + dw:Cross(rWorld)
				self:crashResponse(comp, point, dvWorld, dvp, cf, v, w, true)
				if dvp > 4 then
					local pos = cf:PointToWorldSpace(point * SPM)
					Effects.sparks(pos, dvp / 4)
					Effects.dust(pos, dvp / 5)
				end
			end
		end
		-- Sliding contact wear (belly landings, engine pods on the runway, ...)
		if (self.touchCount[comp] or 0) > 0 and last and now - last < 1.5 then
			local rWorld = cf:VectorToWorldSpace(ref)
			local speed = (v + w:Cross(rWorld)).Magnitude
			if speed > 3 then
				Damage.applyScrape(fm.damage, comp, speed, dt)
				if math.random() < dt * 12 then
					local pos = cf:PointToWorldSpace((self.lastContactPoint[comp] or ref) * SPM) + Vector3.new(0, -2, 0)
					if speed > 20 then
						local vp = v + w:Cross(rWorld)
						Effects.sparkShower(pos, -vp, speed / 25)
					else
						Effects.sparks(pos, speed / 20)
					end
				end
			end
		end
	end
	-- Hard hit without a reported contact (very fast impacts): blame the leading side.
	local mag = dvUnexpected.Magnitude
	if not hitSomething and mag > 7 then
		local dir = -dvUnexpected.Unit
		local best, bestDot = nil, -math.huge
		for comp, ref in self.compRefs do
			if Damage.isAttached(fm.damage, comp) then
				local d = cf:VectorToWorldSpace(ref):Dot(dir)
				if d > bestDot then
					best, bestDot = comp, d
				end
			end
		end
		if best then
			self.lastImpact[best] = mag
			Damage.applyImpact(fm.damage, best, mag)
			maxDv = mag
			self:crashResponse(best, self.compRefs[best], dvUnexpected, mag, cf, v, w, false)
		end
	end
	if maxDv > 0 then
		self.impactCount += 1
		self.impactDv = maxDv
		-- hardest hit in the last moment, for the crash explosion/crater size
		if maxDv >= (self.peakDv or 0) or self.time - (self.peakDvTime or -math.huge) > 1.5 then
			self.peakDv, self.peakDvTime = maxDv, self.time
		end
	end
	if maxDv > 5 then
		Effects.shake(math.clamp(maxDv / 25, 0.1, 1.5))
	end
	-- Water spray
	if fm.result.waterImpact > 2 then
		Effects.spray(cf.Position + Vector3.new(0, -4, 0), fm.result.waterImpact / 3)
	end
end

-- Dents (server), break points and shards for one localised impact.
--   point: body metres; dvWorld: world-frame velocity change (m/s) at the contact.
--   v, w: world velocity (m/s) and angular velocity (rad/s) of the aircraft.
function FlightController:crashResponse(comp: string, point: Vector3, dvWorld: Vector3, dv: number, cf: CFrame, v: Vector3, w: Vector3, allowSection: boolean)
	local fm = self.fm
	local prof = Crash.profiles(self.cfg, self.toughness)[comp]
	if not prof then
		return
	end
	local dirBody = cf:VectorToObjectSpace(dvWorld)
	if dirBody.Magnitude > 1e-6 then
		dirBody = dirBody.Unit
	else
		dirBody = Vector3.zero
	end
	if dv > prof.dentThreshold then
		local last = self.lastImpactReport[comp]
		if not last or self.time - last >= GameConfig.crash.impactReportMinInterval then
			self.lastImpactReport[comp] = self.time
			self.remotes.ReportImpact:FireServer(self.model, comp, point, dirBody, dv)
		end
	end
	local c = fm.damage.components[comp]
	if allowSection and c then
		-- With break-apart off (default), sections only tear off in truly extreme hits.
		local tearDv = if GameConfig.crash.breakApart then dv else dv / GameConfig.crash.extremeSectionFactor
		local sec = Crash.sectionToBreak(prof, { point.X, point.Y, point.Z }, tearDv, c.sectionsLost)
		if sec then
			Damage.breakSection(fm.damage, comp, sec.id, sec.lost)
			self.lastImpact[comp] = dv
		end
	end
	local rWorld = cf:VectorToWorldSpace(point)
	local pos = cf:PointToWorldSpace(point * SPM)
	local velStuds = (v + w:Cross(rWorld)) * SPM
	local n = Crash.shardCount(prof, dv)
	if n > 0 then
		Effects.shards(pos, velStuds, n)
	end
	if dv > 6 then
		Effects.sparkShower(pos, dvWorld, dv / 6 * prof.sparkScale) -- sprays back off the obstacle
	end
end

-- Water bomber: show the curtain or the scoop spray, and tell the server where the
-- water lands (it decides which fires that reaches).
function FlightController:waterBomber(dt: number, cf: CFrame, r: any)
	local core = self.core
	local vel = core.AssemblyLinearVelocity
	self.fxTimer -= dt
	local bh = self.cfg.geometry.fuselage.boatHull
	local belly = cf:PointToWorldSpace(Vector3.new(0, (bh and bh.keelY or -1.5) - 0.3, 0) * SPM)
	if r.dropping then
		self.dropKg += r.dropRate * dt
		if self.fxTimer <= 0 then
			self.fxTimer = 0.08
			Effects.waterCurtain(belly, vel, r.dropRate / self.cfg.waterTank.dropRate)
		end
	elseif r.scooping and self.fxTimer <= 0 then
		self.fxTimer = 0.12
		local probes = cf:PointToWorldSpace(Vector3.new(0, bh and bh.keelY or -1.5, (bh and bh.probesZ) or 2) * SPM)
		Effects.spray(probes, 1.2)
	end
	self.dropTimer += dt
	if self.dropKg > 0 and (self.dropTimer >= 0.25 or not r.dropping) then
		self.dropTimer = 0
		local x, z = Wildfire.impactPoint(belly.X, belly.Y, belly.Z, vel.X, vel.Z, self.groundY)
		local heightM = math.max(0, (belly.Y - self.groundY) * MPS)
		self.remotes.WaterDrop:FireServer(self.model, x, z, self.dropKg, heightM)
		self.dropKg = 0
	end
end

local SYS_RATE = 0.25
function FlightController:reportSystems(dt: number)
	self.systemsTimer += dt
	if self.systemsTimer < SYS_RATE then
		return
	end
	self.systemsTimer = 0
	local fm = self.fm
	local data = {
		GearDown = fm.gearCommand,
		Flaps = math.floor(fm.flapPos * 10 + 0.5) / 10,
		Speedbrake = math.floor(fm.speedbrakePos * 10 + 0.5) / 10,
		ParkingBrake = self.ctl.parkingBrake,
		EnginesRunning = fm:enginesRunning(),
		N1_1 = math.floor(fm.engines[1] and fm.engines[1].n1 or 0),
		N1_2 = math.floor(fm.engines[2] and fm.engines[2].n1 or 0),
		Reverse = (fm.engines[1] and fm.engines[1].reverser or 0) > 0.5,
		Crashed = self.crashed,
	}
	local key = HttpService:JSONEncode(data)
	if key ~= self.lastSystems then
		self.lastSystems = key
		self.remotes.ReportSystems:FireServer(self.model, data)
	end
end

function FlightController:updateTelemetry(cf: CFrame, v: Vector3, r: any, raw: any)
	local t = self.telemetry
	local fm = self.fm
	local look = cf.LookVector
	local pitch, bank = Assist.attitude(self.env.ux, self.env.uy, self.env.uz)
	t.ias = r.ias * Units.KTS_PER_MPS
	t.mach = r.mach or 0
	t.tas = r.tas * Units.KTS_PER_MPS
	t.gs = Vector3.new(v.X, 0, v.Z).Magnitude * Units.KTS_PER_MPS
	t.altFt = cf.Position.Y * MPS * Units.FT_PER_M
	t.raFt = math.max(0, self.env.agl) * Units.FT_PER_M
	t.vsFpm = v.Y * Units.FPM_PER_MPS
	t.heading = Units.headingFromXZ(look.X, look.Z)
	t.track = if t.gs > 5 then Units.headingFromXZ(v.X, v.Z) else t.heading
	t.pitch = math.deg(pitch)
	t.bank = math.deg(bank)
	t.aoa = math.deg(r.alpha)
	t.beta = math.deg(r.beta)
	t.wingAlpha = math.deg(r.wingAlpha or 0)
	t.stallAlpha = math.deg(r.stallAlpha or 0)
	t.gLoad = r.gLoad
	t.lift, t.drag, t.thrust = r.lift, r.drag, r.thrust
	t.stall, t.stallWarning = r.stall, r.stallWarning
	t.onGround = r.onGround
	t.inWater = r.inWater
	t.throttle = raw.throttle
	t.n1 = {}
	for i, e in fm.engines do
		t.n1[i] = { n1 = e.n1, running = e.running, starting = e.starting, failed = e.failed, reverser = e.reverser, afterburner = e.afterburner }
	end
	t.flapLabel = self.cfg.aero.flaps.labels[math.clamp(math.floor(fm.flapPos + 0.5), 1, #self.cfg.aero.flaps.labels)]
	t.flapCmd = self.cfg.aero.flaps.labels[self.ctl.flaps]
	t.flapPos = fm.flapPos
	t.gearExt = fm.gearExtension
	t.gearCmd = fm.gearCommand
	t.brake = self.ctl.brake
	t.parkingBrake = self.ctl.parkingBrake
	t.speedbrake = fm.speedbrakePos
	t.trim = self.ctl.trim
	t.assist = self.assist.mode
	t.fuel = fm.fuel
	t.fuelFlow = r.fuelFlow
	t.waterTank = self.cfg.waterTank
	t.water = fm.water
	t.scooping, t.dropping, t.refilling = r.scooping, r.dropping, r.refilling
	t.crashed = self.crashed
	t.fault = r.fault
	t.ownership = if self.core.ReceiveAge == 0 then "client (local)" else "server/other"
	t.wheels = r.wheelsOnGround
	t.gears = fm.gears
	t.damage = fm.damage
	t.failures = fm.failures
	t.wind = self.lastWind
	t.position = cf.Position
	t.touchdownFlash = self.touchdownFlash
	t.time = self.time
	t.speeds = self.cfg.speeds
end

function FlightController:updateVisuals(dt: number)
	local fm, cfg = self.fm, self.cfg
	local flapDeg = FlightModel.notchLerp(cfg.aero.flaps.deflectionDeg, fm.flapPos)
	for _, m in self.surfaces do
		if not m.Parent or not m:IsDescendantOf(self.model) then
			continue
		end
		local kind = m:GetAttribute("Surface")
		local side = (m:GetAttribute("Side") :: number?) or 1
		local angle = 0
		if kind == "Aileron" then
			angle = -side * fm.aileron
		elseif kind == "Flap" then
			angle = math.rad(flapDeg)
		elseif kind == "Elevator" then
			angle = -(fm.elevator + self.ctl.trim * cfg.aero.trim.maxDeflection)
		elseif kind == "Rudder" then
			angle = fm.rudder
		elseif kind == "Spoiler" then
			angle = -math.rad(50) * fm.speedbrakePos
		end
		m.Transform = CFrame.Angles(angle, 0, 0)
	end
	-- Gear: retraction rotation + strut compression
	for name, m in self.gearMotors do
		if not m.Parent or not m:IsDescendantOf(self.model) then
			continue
		end
		local gc = self.gearCfg[name]
		local u = gc.cfg
		local gs = fm.gears[gc.index]
		local a = math.rad(u.retractAngleDeg) * (1 - fm.gearExtension)
		if Damage.state(fm.damage, u.component) == "failed" then
			-- Collapsed leg: buckled most of the way up and squashed to the stop.
			a = math.max(a, math.rad(u.retractAngleDeg) * 0.6)
			gs = { compression = u.travel, steer = gs.steer }
		end
		local rot = if u.retractAxis == "x" then CFrame.Angles(a, 0, 0) else CFrame.Angles(0, 0, a)
		local comp = math.min(gs.compression, u.travel) * SPM
		local steer = CFrame.Angles(0, -gs.steer, 0)
		m.Transform = rot * CFrame.new(0, comp, 0) * steer
	end
	-- Fans
	for i, f in self.fans do
		local e = fm.engines[i]
		if e and f.motor.Parent and f.motor:IsDescendantOf(self.model) then
			f.angle = (f.angle + e.n1 / 100 * 9 * dt) % (math.pi * 2)
			f.motor.Transform = CFrame.Angles(f.angle, 0, 0)
		end
	end
	-- Failure smoke
	for i, e in fm.engines do
		local comp = cfg.engines[i].component
		local sm = self.smoke[comp]
		if sm then
			sm.Enabled = e.failed and Damage.isAttached(fm.damage, comp)
		end
	end
	if self.landingLight then
		self.landingLight.Enabled = fm.gearExtension > 0.9
	end
	-- Afterburner flames: fade in with reheat, with a little flicker
	for _, ab in self.afterburners do
		local e = fm.engines[ab.index]
		if ab.part.Parent and ab.part:IsDescendantOf(self.model) then
			local k = if e then e.afterburner else 0
			ab.part.Transparency = if k < 0.02 then 1 else 1 - k * (0.55 + 0.15 * math.random())
			if ab.light then
				ab.light.Brightness = k * 4
			end
		end
	end
end

return FlightController
