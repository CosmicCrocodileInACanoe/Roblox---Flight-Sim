--!strict
-- Runs the failures and weather hazards picked from the HUD's Events button (J):
--   failures      break parts at once through FlightController:applyHazard
--   tornado       a funnel touches down ahead and drifts across your path; its swirl,
--                 inflow and updraft feed the flight model's wind, the core spins the
--                 airframe and flying debris breaks parts
--   lightning     a bolt and a flash, then a strike on a wing or the tail (sometimes an
--                 engine flames out; I relights it)
--   birds         a flock flies into the nose; an engine swallows some
--   strong winds  45 s of 40-55 kt crosswind with gusts, turbulence and a downburst
-- Everything visual is local to this player. Damage reaches the server through the
-- normal crash remotes, so torn-off parts are real debris for everyone.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Units = require(Shared.Units)
local Hazards = require(Shared.Hazards)
local Damage = require(Shared.Damage)
local Crash = require(Shared.Crash)
local WorldGen = require(Shared.WorldGen)
local Effects = require(script.Parent.Effects)

local MPS = Units.METERS_PER_STUD
local SPM = Units.STUDS_PER_METER

local HazardController = {}
HazardController.__index = HazardController

local function rng(): number
	return math.random()
end

local function folder(): Folder
	local f = Workspace:FindFirstChild("HazardEffects")
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "HazardEffects"
	nf.Parent = Workspace
	return nf
end

local function ghost(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
end

local function groundY(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { folder() }
	for _, name in { "Aircraft", "Debris", "LocalEffects" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(Vector3.new(x, 9000, z), Vector3.new(0, -12000, 0), params)
	if hit then
		return math.max(hit.Position.Y, WorldGen.SEA_LEVEL)
	end
	return math.max(WorldGen.meshHeight(x, z), WorldGen.SEA_LEVEL)
end

function HazardController.new(callbacks: { notify: (string) -> () })
	local self = setmetatable({}, HazardController) :: any
	self.notify = callbacks.notify
	self.fc = nil
	self.tornado = nil :: any
	self.wind = nil :: any
	self.flocks = {} :: { any }
	self.fires = {} :: { [string]: Instance }
	self.time = 0
	return self
end

-- keepWeather (Fix all): the aircraft is rebuilt but a tornado, wind or birds carry on.
function HazardController:attach(fc: any, keepWeather: boolean?)
	if keepWeather then
		for _, fire in self.fires do
			fire:Destroy()
		end
		self.fires = {}
	else
		self:clear()
	end
	self.fc = fc
	if fc then
		fc.spinProvider = function(cf: CFrame, t: number): Vector3?
			return self:spin(cf, t)
		end
	end
end

-- Remove every active weather event (failures stay until R resets the aircraft).
function HazardController:clear()
	if self.tornado then
		self.tornado.model:Destroy()
		self.tornado = nil
	end
	self.wind = nil
	for _, f in self.flocks do
		for _, b in f.birds do
			b.part:Destroy()
		end
	end
	self.flocks = {}
	for _, fire in self.fires do
		fire:Destroy()
	end
	self.fires = {}
end

-- Extra wind from active hazards (m/s, world axes) at a world position (studs).
function HazardController:windAt(pos: Vector3, t: number): Vector3
	local w = Vector3.zero
	local tor = self.tornado
	if tor then
		local d = pos - tor.base
		local k = Hazards.envelope(tor.age, Hazards.TORNADO.durationS, 6)
		local x, y, z = Hazards.tornadoWind(d.X * MPS, d.Y * MPS, d.Z * MPS, k)
		w += Vector3.new(x, y, z)
	end
	local sw = self.wind
	if sw then
		local n1 = math.noise(sw.age * 0.35, 4.2, 0.7) * 2
		local n2 = math.noise(sw.age * 0.9, 8.1, pos.X / 300)
		local n3 = math.noise(sw.age * 0.8, pos.Z / 300, 2.6)
		local x, y, z = Hazards.strongWind(sw.age, sw.dir.X, sw.dir.Z, sw.kts, n1, n2, n3)
		w += Vector3.new(x, y, z)
	end
	return w
end

-- Angular acceleration (rad/s^2, world) from the tornado's swirl near its core.
function HazardController:spin(cf: CFrame, t: number): Vector3?
	local tor = self.tornado
	if not tor then
		return nil
	end
	local d = cf.Position - tor.base
	local r = Vector3.new(d.X, 0, d.Z).Magnitude * MPS
	local rc = Hazards.TORNADO.coreRadiusM
	local k = math.clamp(1 - r / (rc * 2.5), 0, 1) * Hazards.envelope(tor.age, Hazards.TORNADO.durationS, 6)
	if k <= 0 or d.Y * MPS > Hazards.TORNADO.topM then
		return nil
	end
	local roll = math.noise(t * 1.3, 2.2, 9.4) * 2.4
	return (Vector3.yAxis * 0.9 + cf.LookVector * roll) * k * k
end

-- Called by the Events panel. Returns the text to show.
function HazardController:trigger(id: string): string
	local fc = self.fc
	if not fc or not fc.alive then
		return "Start a flight first"
	end
	if fc.crashed then
		return "The aircraft has crashed. Press R to reset"
	end
	if id == "clear" then
		local any = self.tornado ~= nil or self.wind ~= nil or #self.flocks > 0
		self:clear()
		return if any then "Weather cleared. Damage stays until you reset (R)" else "No weather events to clear"
	elseif id == "random" then
		local plan, why = Hazards.randomFailure(fc.fm, rng)
		return if plan then fc:applyHazard(plan) else why or "Nothing left to fail"
	elseif id == "tornado" then
		return self:spawnTornado()
	elseif id == "strongWind" then
		return self:startWind()
	elseif id == "lightning" then
		return self:lightning()
	elseif id == "birds" then
		return self:birds()
	end
	local plan, why = Hazards.plan(id, fc.fm, rng)
	if not plan then
		return why or "Nothing happened"
	end
	return fc:applyHazard(plan)
end

-- Tornado ----------------------------------------------------------------------------
local FUNNEL_SEGMENTS = 12

local function buildTornado(): (Model, { BasePart })
	local T = Hazards.TORNADO
	local m = Instance.new("Model")
	m.Name = "Tornado"
	local segs = {}
	local height = T.topM * SPM
	local segLen = height / FUNNEL_SEGMENTS
	for i = 1, FUNNEL_SEGMENTS do
		local f = (i - 0.5) / FUNNEL_SEGMENTS
		local radiusM = 14 + 230 * f ^ 2.2
		local p = Instance.new("Part")
		p.Name = "Funnel" .. i
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(segLen * 1.05, math.min(radiusM * 2 * SPM, 2000), math.min(radiusM * 2 * SPM, 2000))
		p.Material = Enum.Material.SmoothPlastic
		p.Color = Color3.fromRGB(96 - i * 2, 98 - i * 2, 104 - i * 2)
		p.Transparency = 0.3 + 0.35 * f
		ghost(p)
		p:SetAttribute("Y", (i - 0.5) * segLen)
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(120, 118, 115), Color3.fromRGB(80, 80, 84))
		e.Size = NumberSequence.new(radiusM * SPM * 0.7, radiusM * SPM * 1.1)
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(1.5, 2.5)
		e.Rate = 6
		e.Speed = NumberRange.new(radiusM * SPM * 0.4)
		e.RotSpeed = NumberRange.new(80, 160)
		e.Rotation = NumberRange.new(0, 360)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Parent = p
		p.Parent = m
		table.insert(segs, p)
	end
	-- wall cloud on top
	local cloud = Instance.new("Part")
	cloud.Name = "WallCloud"
	cloud.Shape = Enum.PartType.Cylinder
	cloud.Size = Vector3.new(160, 2000, 2000)
	cloud.Material = Enum.Material.SmoothPlastic
	cloud.Color = Color3.fromRGB(58, 60, 66)
	cloud.Transparency = 0.15
	ghost(cloud)
	cloud:SetAttribute("Y", height + 60)
	cloud.Parent = m
	table.insert(segs, cloud)
	-- debris cloud and dust at the base
	local base = Instance.new("Part")
	base.Name = "DebrisCloud"
	base.Size = Vector3.new(4, 4, 4)
	base.Transparency = 1
	ghost(base)
	base:SetAttribute("Y", 20)
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(122, 104, 82))
	dust.Size = NumberSequence.new(80, 260)
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(2, 4)
	dust.Rate = 18
	dust.Speed = NumberRange.new(60, 160)
	dust.SpreadAngle = Vector2.new(180, 30)
	dust.Acceleration = Vector3.new(0, 60, 0)
	dust.RotSpeed = NumberRange.new(-120, 120)
	dust.Parent = base
	local chunks = Instance.new("ParticleEmitter")
	chunks.Color = ColorSequence.new(Color3.fromRGB(70, 56, 44))
	chunks.Size = NumberSequence.new(4, 2)
	chunks.Lifetime = NumberRange.new(3, 5)
	chunks.Rate = 40
	chunks.Speed = NumberRange.new(120, 260)
	chunks.SpreadAngle = Vector2.new(60, 180)
	chunks.Acceleration = Vector3.new(0, 30, 0)
	chunks.RotSpeed = NumberRange.new(-400, 400)
	chunks.Parent = base
	base.Parent = m
	table.insert(segs, base)
	m.Parent = folder()
	return m, segs
end

function HazardController:spawnTornado(): string
	local fc = self.fc
	if self.tornado then
		self.tornado.model:Destroy()
		self.tornado = nil
	end
	local cf = fc.core.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	look = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-look.Z, 0, look.X)
	local side = if rng() < 0.5 then -1 else 1
	local T = Hazards.TORNADO
	local p = cf.Position + look * (T.spawnAheadM * SPM) + right * side * ((120 + rng() * 180) * SPM)
	local base = Vector3.new(p.X, groundY(p.X, p.Z), p.Z)
	local model, segs = buildTornado()
	self.tornado = {
		base = base,
		vel = -right * side * (T.driftMps * SPM), -- drifts across your path
		age = 0,
		model = model,
		segs = segs,
		spinAngle = 0,
		hitTimer = 0,
		warned = false,
	}
	self:placeTornado()
	local dir = if side > 0 then "right" else "left"
	return `TORNADO ahead and to the {dir}, drifting across your path. Steer clear!`
end

function HazardController:placeTornado()
	local tor = self.tornado
	local wobbleT = tor.age
	for i, p in tor.segs do
		local y = p:GetAttribute("Y") :: number
		-- the funnel leans and snakes a little with height
		local f = y / (Hazards.TORNADO.topM * SPM)
		local off = Vector3.new(math.noise(wobbleT * 0.2, f * 2, 1) * 160 * f, 0, math.noise(wobbleT * 0.2, f * 2, 7) * 160 * f)
		local pos = tor.base + Vector3.new(0, y, 0) + off
		if p.Shape == Enum.PartType.Cylinder then
			p.CFrame = CFrame.new(pos) * CFrame.Angles(0, tor.spinAngle * (1 + i * 0.05), 0) * CFrame.Angles(0, 0, math.pi / 2)
		else
			p.CFrame = CFrame.new(pos)
		end
	end
end

function HazardController:updateTornado(dt: number)
	local tor = self.tornado
	local fc = self.fc
	tor.age += dt
	local T = Hazards.TORNADO
	if tor.age >= T.durationS then
		tor.model:Destroy()
		self.tornado = nil
		self.notify("The tornado has lifted")
		return
	end
	tor.base += tor.vel * dt
	tor.base = Vector3.new(tor.base.X, groundY(tor.base.X, tor.base.Z), tor.base.Z)
	tor.spinAngle = (tor.spinAngle + dt * 2.5) % (math.pi * 2)
	-- fade in and out
	local k = Hazards.envelope(tor.age, T.durationS, 6)
	for _, p in tor.segs do
		local e = p:FindFirstChildOfClass("ParticleEmitter")
		if e then
			e.Enabled = k > 0.2
		end
	end
	self:placeTornado()
	if not fc or not fc.alive or fc.crashed then
		return
	end
	local pos = fc.core.Position
	local d = pos - tor.base
	local r = Vector3.new(d.X, 0, d.Z).Magnitude * MPS
	if r > 12000 then
		tor.model:Destroy()
		self.tornado = nil
		return
	end
	if d.Y * MPS > T.topM then
		return
	end
	if not tor.warned and r < T.coreRadiusM * 4 then
		tor.warned = true
		self.notify("You're in the tornado's winds! Hold on")
	end
	-- debris strikes inside the debris cloud
	local rate = Hazards.tornadoHitRate(r) * k
	if rate > 0 then
		Effects.shake(dt * 6)
		tor.hitTimer -= dt
		if tor.hitTimer <= 0 then
			tor.hitTimer = (0.5 + rng()) / rate
			self:debrisHit()
		end
	end
end

-- One piece of flying debris hits a random part of the aircraft.
function HazardController:debrisHit()
	local fc = self.fc
	local fm = fc.fm
	local names = {}
	for _, n in fm.damage.order do
		if n ~= "Fuselage" and Damage.isAttached(fm.damage, n) then
			table.insert(names, n)
		end
	end
	if #names == 0 then
		return
	end
	local comp = names[math.random(1, #names)]
	local actions: { any } = { { op = "hurt", component = comp, amount = 0.05 + 0.1 * rng(), dent = 10 } }
	-- now and then a whole section goes
	if rng() < 0.18 then
		local prof = Crash.profiles(fm.cfg)[comp]
		local c = fm.damage.components[comp]
		if prof and c then
			for _, s in prof.sections do
				if not c.sectionsLost[s.id] then
					table.insert(actions, { op = "section", component = comp, section = s.id, lost = s.lost, amount = 0.2 })
					break
				end
			end
		end
	end
	fc:applyHazard({ id = "tornadoDebris", actions = actions, message = "" })
end

-- Strong winds -------------------------------------------------------------------------
function HazardController:startWind(): string
	local cf = self.fc.core.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	look = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)
	local side = if rng() < 0.5 then -1 else 1
	-- mostly across your heading, up to 35 degrees off the beam
	local a = math.rad(90 * side + (rng() - 0.5) * 70)
	local dir = (CFrame.Angles(0, a, 0) * CFrame.lookAt(Vector3.zero, look)).LookVector
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	local W = Hazards.WIND
	local kts = W.minKts + rng() * (W.maxKts - W.minKts)
	self.wind = { dir = dir, kts = kts, age = 0 }
	local from = math.floor(Units.headingFromXZ(-dir.X, -dir.Z) + 0.5) % 360
	return string.format("STRONG WINDS: %d kt from %03d with gusts. Watch for a downburst!", math.floor(kts + 0.5), from)
end

-- Lightning ----------------------------------------------------------------------------
local function flash()
	local cc = Lighting:FindFirstChild("LightningFlash") :: ColorCorrectionEffect?
	if not cc then
		local n = Instance.new("ColorCorrectionEffect")
		n.Name = "LightningFlash"
		n.Parent = Lighting
		cc = n
	end
	local c = cc :: ColorCorrectionEffect
	task.spawn(function()
		for _, b in { 0.9, 0.2, 0.7, 0.35, 0.15, 0.05, 0 } do
			c.Brightness = b
			c.Contrast = b * 0.3
			task.wait(0.05)
		end
	end)
end

local function bolt(from: Vector3, to: Vector3)
	local m = Instance.new("Model")
	m.Name = "Lightning"
	local n = 12
	local prev = from
	local dir = to - from
	local perp1 = dir:Cross(Vector3.xAxis)
	perp1 = if perp1.Magnitude > 1e-3 then perp1.Unit else Vector3.zAxis
	local perp2 = dir.Unit:Cross(perp1)
	for i = 1, n do
		local f = i / n
		local jitter = if i < n then (perp1 * (rng() - 0.5) + perp2 * (rng() - 0.5)) * dir.Magnitude * 0.12 * (1 - f * 0.6) else Vector3.zero
		local nextP = from + dir * f + jitter
		local seg = Instance.new("Part")
		seg.Material = Enum.Material.Neon
		seg.Color = Color3.fromRGB(205, 220, 255)
		local len = (nextP - prev).Magnitude
		seg.Size = Vector3.new(1.6, 1.6, len)
		seg.CFrame = CFrame.lookAt((prev + nextP) / 2, nextP)
		ghost(seg)
		seg.Parent = m
		prev = nextP
	end
	local glow = Instance.new("Part")
	glow.Transparency = 1
	glow.Size = Vector3.one
	glow.CFrame = CFrame.new(to)
	ghost(glow)
	local light = Instance.new("PointLight")
	light.Brightness = 12
	light.Range = 60
	light.Color = Color3.fromRGB(200, 215, 255)
	light.Parent = glow
	glow.Parent = m
	m.Parent = folder()
	Debris:AddItem(m, 0.25)
end

function HazardController:lightning(): string
	local fc = self.fc
	local plan, why = Hazards.plan("lightning", fc.fm, rng)
	if not plan then
		return why or "Nothing to strike"
	end
	-- strike the part the plan hurts (a wing or the tail), or the middle
	local target = fc.core.Position
	for _, a in plan.actions do
		if a.op == "hurt" and a.component and fc.compRefs[a.component] then
			target = fc.core.CFrame:PointToWorldSpace(fc.compRefs[a.component] * SPM)
		end
	end
	local from = target + Vector3.new((rng() - 0.5) * 600, 1100, (rng() - 0.5) * 600)
	bolt(from, target)
	-- and on through to the ground below
	local gy = groundY(target.X, target.Z)
	if target.Y - gy > 20 then
		bolt(target, Vector3.new(target.X + (rng() - 0.5) * 300, gy, target.Z + (rng() - 0.5) * 300))
	end
	flash()
	Effects.sparks(target, 4)
	Effects.shake(1.2)
	return fc:applyHazard(plan)
end

-- Birds --------------------------------------------------------------------------------
function HazardController:birds(): string
	local fc = self.fc
	local cf = fc.core.CFrame
	local speed = fc.core.AssemblyLinearVelocity.Magnitude * MPS
	-- the flock appears about two seconds ahead
	local leadM = math.clamp(speed * 2, 60, 400)
	local centre = cf.Position + cf.LookVector * leadM * SPM
	local birds = {}
	for i = 1, 22 do
		local p = Instance.new("Part")
		p.Name = "Bird"
		p.Size = Vector3.new(2.6, 0.4, 1.2)
		p.Color = if i % 3 == 0 then Color3.fromRGB(235, 235, 230) else Color3.fromRGB(46, 44, 42)
		p.Material = Enum.Material.SmoothPlastic
		ghost(p)
		local off = cf.RightVector * (rng() - 0.5) * 30 * SPM + cf.UpVector * (rng() - 0.5) * 14 * SPM + cf.LookVector * (rng() - 0.5) * 20 * SPM
		local start = centre + off
		p.CFrame = CFrame.new(start)
		p.Parent = folder()
		table.insert(birds, { part = p, start = start, off = off * 0.15, phase = rng() * 6 })
	end
	table.insert(self.flocks, { birds = birds, age = 0, duration = math.clamp(leadM / math.max(speed, 1), 0.8, 2.5) })
	return "Birds ahead!"
end

function HazardController:updateFlocks(dt: number)
	local fc = self.fc
	for i = #self.flocks, 1, -1 do
		local flock = self.flocks[i]
		flock.age += dt
		local k = math.clamp(flock.age / flock.duration, 0, 1)
		local nose = if fc and fc.alive then fc.core.CFrame:PointToWorldSpace(Vector3.new(0, 0, -6 * SPM)) else nil
		for _, b in flock.birds do
			if nose and k < 1 then
				local pos = b.start:Lerp(nose + b.off, k)
				local flap = math.sin(flock.age * 18 + b.phase) * 0.6
				b.part.CFrame = CFrame.lookAt(pos, nose) * CFrame.Angles(0, 0, flap)
			end
		end
		if k >= 1 then
			for _, b in flock.birds do
				b.part:Destroy()
			end
			table.remove(self.flocks, i)
			if fc and fc.alive and not fc.crashed and nose then
				local plan, why = Hazards.plan("birds", fc.fm, rng)
				Effects.debrisPuff(nose, 2)
				Effects.shards(nose, fc.core.AssemblyLinearVelocity * 0.6, 10, Color3.fromRGB(240, 240, 235))
				self.notify(if plan then fc:applyHazard(plan) else why or "Bird strike!")
			end
		end
	end
end

-- Engine fires: real flames on any engine that caught fire.
function HazardController:updateFires()
	local fc = self.fc
	if not fc or not fc.alive then
		return
	end
	for i, e in fc.fm.engines do
		local comp = fc.cfg.engines[i].component
		local key = tostring(i)
		local burning = e.fire == true and Damage.isAttached(fc.fm.damage, comp)
		local existing = self.fires[key]
		if burning and not existing then
			local compModel = fc.model:FindFirstChild(comp)
			local part = compModel and (compModel :: Model).PrimaryPart
			if part then
				local fire = Instance.new("Fire")
				fire.Name = "EngineFire"
				fire.Size = 10
				fire.Heat = 14
				fire.Color = Color3.fromRGB(255, 120, 30)
				fire.SecondaryColor = Color3.fromRGB(255, 220, 90)
				fire.Parent = part
				self.fires[key] = fire
			end
		elseif not burning and existing and Damage.isAttached(fc.fm.damage, comp) then
			existing:Destroy()
			self.fires[key] = nil
		end
	end
end

function HazardController:update(dt: number)
	self.time += dt
	if self.tornado then
		self:updateTornado(dt)
	end
	if self.wind then
		self.wind.age += dt
		if self.wind.age >= Hazards.WIND.durationS then
			self.wind = nil
			self.notify("The strong winds have died down")
		end
	end
	if #self.flocks > 0 then
		self:updateFlocks(dt)
	end
	self:updateFires()
end

-- One-line status for the Events panel.
function HazardController:status(): string
	local out = {}
	if self.tornado then
		local fc = self.fc
		local dist = ""
		if fc and fc.alive then
			local d = fc.core.Position - self.tornado.base
			dist = string.format(", %.1f km away", Vector3.new(d.X, 0, d.Z).Magnitude * MPS / 1000)
		end
		table.insert(out, string.format("Tornado %ds%s", math.ceil(Hazards.TORNADO.durationS - self.tornado.age), dist))
	end
	if self.wind then
		table.insert(out, string.format("Strong winds %ds", math.ceil(Hazards.WIND.durationS - self.wind.age)))
	end
	if #self.flocks > 0 then
		table.insert(out, "Birds incoming")
	end
	return if #out > 0 then table.concat(out, "  ·  ") else "No weather events active"
end

return HazardController
