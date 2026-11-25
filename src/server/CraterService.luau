--!strict
-- Explosions and ground craters for destroyed aircraft.
--
-- When an owning client's airframe is destroyed it sends ReportCrash(model, pos, dv).
-- The server checks it, sets off a cartoon explosion (it pushes nothing and breaks no
-- joints) and, if the wreck is on land, leaves a crater everyone can see: a scorched
-- patch, a dark pit and a ring of thrown-up earth, sized by the impact energy.
--
-- The ground is made of large anchored parts, which can't be dug into, so the crater
-- is built on top: a raised rim around a dark centre reads as a hole. Craters are
-- visual only (no collisions, no raycast hits) and capped so they can't pile up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crash = require(Shared.Crash)
local GameConfig = require(Shared.GameConfig)
local Registry = require(Shared.AircraftRegistry)
local Units = require(Shared.Units)
local WorldGen = require(Shared.WorldGen)

local S = Units.STUDS_PER_METER
local CC = GameConfig.crash.crater

local CraterService = {}

export type Hooks = {
	remotes: Folder,
	getAircraft: (Player) -> Model?,
	maxRecentSpeed: (Player, number) -> number, -- m/s
	ignore: () -> { Instance }, -- aircraft, debris, characters...
}

local hooks: Hooks
local folder: Folder
local craters: { Model } = {}

local function visualPart(className: string?): BasePart
	local p = Instance.new((className or "Part") :: any) :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- A flat disc lying on the surface with normal `n`.
local function disc(parent: Instance, center: Vector3, n: Vector3, diameter: number, thick: number, color: Color3, material: Enum.Material)
	local p = visualPart()
	;(p :: Part).Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(thick, diameter, diameter)
	-- cylinder axis is X: point it along the normal
	p.CFrame = CFrame.lookAt(center, center + n) * CFrame.Angles(0, math.rad(90), 0)
	p.Color = color
	p.Material = material
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Build a crater at a ground point. radius and rim height in metres.
function CraterService.build(pos: Vector3, normal: Vector3, radiusM: number, rimM: number, seed: number?): Model
	local rng = Random.new(seed or os.clock() * 1000)
	local n = if normal.Magnitude > 0.1 then normal.Unit else Vector3.yAxis
	local R = radiusM * S
	local rim = rimM * S
	local m = Instance.new("Model")
	m.Name = "Crater"
	-- surface frame: n up, t1/t2 along the ground
	local t1 = n:Cross(if math.abs(n.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	local t2 = n:Cross(t1).Unit
	local up = pos + n * 0.05
	disc(m, up, n, R * 2.6, 0.2, Color3.fromRGB(58, 50, 42), Enum.Material.Ground) -- scorched patch
	disc(m, up + n * 0.08, n, R * 1.5, 0.2, Color3.fromRGB(40, 34, 30), Enum.Material.Slate) -- blast mark
	disc(m, up + n * 0.16, n, R * 1.05, 0.2, Color3.fromRGB(22, 18, 16), Enum.Material.Basalt) -- the pit
	-- Rim: chunks of earth around the edge, leaning outward.
	local count = math.clamp(math.floor(R / 2.2), 10, 22)
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local radial = t1 * math.cos(a) + t2 * math.sin(a)
		local tangent = n:Cross(radial)
		local h = rim * rng:NextNumber(0.75, 1.25)
		local w = (2 * math.pi * R / count) * 1.35
		local d = R * 0.32
		local c = pos + radial * (R * 0.98) + n * (h * 0.3)
		local p = visualPart()
		p.Size = Vector3.new(w, h, d)
		p.CFrame = CFrame.fromMatrix(c, tangent, n, -radial) * CFrame.Angles(math.rad(rng:NextNumber(18, 32)), 0, 0)
		p.Color = Color3.fromRGB(102, 80, 58):Lerp(Color3.fromRGB(70, 58, 46), rng:NextNumber())
		p.Material = Enum.Material.Ground
		p.Parent = m
	end
	-- Thrown clods.
	for _ = 1, math.clamp(math.floor(R / 3), 6, 16) do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = R * rng:NextNumber(1.1, 1.9)
		local s = rng:NextNumber(0.6, 1.6) * math.max(1, rim * 0.35)
		local p = visualPart()
		p.Size = Vector3.new(s, s * 0.7, s * 1.1)
		p.CFrame = CFrame.new(pos + (t1 * math.cos(a) + t2 * math.sin(a)) * r + n * (s * 0.25))
			* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
		p.Color = Color3.fromRGB(92, 74, 56)
		p.Material = Enum.Material.Ground
		p.Parent = m
	end
	-- Smoke drifting out of the hole for a while.
	local emitterPart = visualPart()
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(R, 1, R)
	emitterPart.CFrame = CFrame.new(up + n)
	emitterPart.Parent = m
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 66, 62), Color3.fromRGB(150, 146, 140))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, R * 0.25), NumberSequenceKeypoint.new(1, R * 0.8) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(5, 9)
	smoke.Speed = NumberRange.new(4, 9)
	smoke.Rate = 6
	smoke.SpreadAngle = Vector2.new(20, 20)
	smoke.Acceleration = Vector3.new(1.5, 2, 0)
	smoke.Parent = emitterPart
	task.delay(30, function()
		smoke.Enabled = false
	end)
	m.Parent = folder
	table.insert(craters, m)
	while #craters > CC.maxCraters do
		local old = table.remove(craters, 1) :: Model
		old:Destroy()
	end
	task.delay(CC.lifetime, function()
		if m.Parent then
			m:Destroy()
		end
	end)
	return m
end

-- Cartoon explosion: flash and fireball only, it pushes and breaks nothing.
function CraterService.explode(pos: Vector3, radiusStuds: number)
	local e = Instance.new("Explosion")
	e.Position = pos
	e.BlastRadius = math.clamp(radiusStuds, 8, 80)
	e.BlastPressure = 0
	e.DestroyJointRadiusPercent = 0
	e.ExplosionType = Enum.ExplosionType.NoCraters
	e.Parent = Workspace
end

local function isWater(inst: Instance): boolean
	if inst:IsA("BasePart") and inst.Material == Enum.Material.Water then
		return true
	end
	local name = string.lower(inst.Name)
	return string.find(name, "sea") ~= nil or string.find(name, "water") ~= nil or string.find(name, "ocean") ~= nil
end

local function onReportCrash(p: Player, model: any, pos: any, dv: any)
	if typeof(model) ~= "Instance" or model ~= hooks.getAircraft(p) or typeof(pos) ~= "Vector3" or type(dv) ~= "number" then
		return
	end
	local m = model :: Model
	if m:GetAttribute("Exploded") then
		return -- once per aircraft
	end
	local core = m.PrimaryPart
	if not core or dv ~= dv or (pos - core.Position).Magnitude > 250 then
		return
	end
	m:SetAttribute("Exploded", true)
	local cfg = Registry.get(m:GetAttribute("AircraftId") :: string)
	local mass = if cfg then cfg.mass else 30000
	local seen = hooks.maxRecentSpeed(p, 3)
	local d = math.clamp(dv, 0, seen * 1.3 + 10)
	local radiusM, rimM = Crash.craterSize(mass, d, CC.minDv)
	CraterService.explode(pos, (radiusM or 6) * S * 0.8)
	if not radiusM or not rimM then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = hooks.ignore()
	local hit = Workspace:Raycast(pos + Vector3.new(0, 30, 0), Vector3.new(0, -30 - 40 * S, 0), params)
	if not hit or isWater(hit.Instance) or hit.Position.Y < WorldGen.SEA_LEVEL then
		-- in the air, on a building far above ground, or in the sea (including shallow
		-- water, where the ground under the surface would hide the crater): no crater
		return
	end
	CraterService.build(hit.Position, hit.Normal, radiusM, rimM, p.UserId + math.floor(os.clock()))
end

function CraterService.init(h: Hooks)
	hooks = h
	folder = Instance.new("Folder")
	folder.Name = "Craters"
	folder.Parent = Workspace
	;(h.remotes:FindFirstChild("ReportCrash") :: RemoteEvent).OnServerEvent:Connect(onReportCrash)
	local _ = Players
end

function CraterService.folder(): Folder
	return folder
end

return CraterService
