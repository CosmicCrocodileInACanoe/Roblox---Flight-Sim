--!strict
-- Lightweight client-side effects: sparks, dust/tyre smoke, water spray, camera shake.
-- Purely visual; nothing here affects physics. Pooled emitters keep allocations low.

local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local Effects = {}

Effects.shakeAmount = 0

local folder: Folder? = nil
local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "LocalEffects"
	f.Parent = Workspace
	folder = f
	return f
end

local function burst(pos: Vector3, color: Color3, count: number, size: number, speed: number, lifetime: number, light: boolean?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = CFrame.new(pos)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = if light then 1 else 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * (if light then 0.2 else 3)) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, if light then 0 else 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(70, 70)
	e.Lifetime = NumberRange.new(lifetime * 0.5, lifetime)
	e.Acceleration = if light then Vector3.new(0, -35, 0) else Vector3.new(0, 4, 0)
	e.Rate = 0
	e.Parent = p
	p.Parent = getFolder()
	e:Emit(count)
	Debris:AddItem(p, lifetime + 0.5)
end

function Effects.sparks(pos: Vector3, intensity: number)
	burst(pos, Color3.fromRGB(255, 190, 90), math.clamp(math.floor(8 * intensity), 3, 40), 0.6, 40, 0.6, true)
end

function Effects.dust(pos: Vector3, intensity: number)
	burst(pos, Color3.fromRGB(200, 196, 186), math.clamp(math.floor(6 * intensity), 2, 30), 3, 10, 1.6)
end

function Effects.tyreSmoke(pos: Vector3)
	burst(pos, Color3.fromRGB(225, 225, 225), 10, 2.5, 8, 1.4)
end

function Effects.spray(pos: Vector3, intensity: number)
	burst(pos, Color3.fromRGB(220, 235, 245), math.clamp(math.floor(10 * intensity), 4, 50), 4, 30, 1.5)
end

function Effects.debrisPuff(pos: Vector3, intensity: number)
	burst(pos, Color3.fromRGB(90, 86, 80), math.clamp(math.floor(10 * intensity), 4, 40), 5, 20, 2.2)
end

-- Directional spark shower: a long bright spray along `dir` plus a brief light flash.
function Effects.sparkShower(pos: Vector3, dir: Vector3, intensity: number)
	local d = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.yAxis
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	-- ParticleEmitters emit along the part's +Y (Top) face.
	p.CFrame = CFrame.lookAt(pos, pos + d) * CFrame.Angles(-math.pi / 2, 0, 0)
	local e = Instance.new("ParticleEmitter")
	e.EmissionDirection = Enum.NormalId.Top
	e.Color = ColorSequence.new(Color3.fromRGB(255, 236, 160), Color3.fromRGB(255, 150, 50))
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.05) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Speed = NumberRange.new(30, 70 + 10 * intensity)
	e.SpreadAngle = Vector2.new(28, 28)
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Acceleration = Vector3.new(0, -35, 0)
	e.Drag = 1.5
	e.Rate = 0
	e.Parent = p
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Range = math.clamp(8 + intensity * 4, 8, 30)
	light.Brightness = math.clamp(1 + intensity, 1, 5)
	light.Parent = p
	p.Parent = getFolder()
	e:Emit(math.clamp(math.floor(12 * intensity), 5, 60))
	task.delay(0.12, function()
		light.Enabled = false
	end)
	Debris:AddItem(p, 1.6)
end

-- Cosmetic metal shards, simulated locally only. Capped FIFO so crashes stay cheap.
local liveShards: { BasePart } = {}
local SHARD_COLORS = {
	Color3.fromRGB(176, 180, 188),
	Color3.fromRGB(140, 144, 152),
	Color3.fromRGB(210, 212, 218),
}
function Effects.shards(pos: Vector3, vel: Vector3, count: number, color: Color3?)
	local n = math.clamp(math.floor(count), 0, 20)
	local cap = GameConfig.crash.clientMaxShards
	local life = GameConfig.crash.shardLifetime
	local f = getFolder()
	for _ = 1, n do
		local p: BasePart = if math.random() < 0.5 then Instance.new("WedgePart") else Instance.new("Part")
		p.Size = Vector3.new(0.4 + math.random() * 1.0, 0.1 + math.random() * 0.3, 0.4 + math.random() * 1.0)
		p.Color = color or SHARD_COLORS[math.random(1, #SHARD_COLORS)]
		p.Material = Enum.Material.Metal
		p.Anchored = false
		p.CanCollide = true
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = false
		p.CollisionGroup = GameConfig.CollisionGroups.Debris
		p.CFrame = CFrame.new(pos + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2)
			* CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
		p.Parent = f
		local spread = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5) * 50
		p.AssemblyLinearVelocity = vel + spread
		p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 30
		table.insert(liveShards, p)
		Debris:AddItem(p, life)
	end
	while #liveShards > cap do
		local old = table.remove(liveShards, 1) :: BasePart
		if old.Parent then
			old:Destroy()
		end
	end
	for i = #liveShards, 1, -1 do
		if not liveShards[i].Parent then
			table.remove(liveShards, i)
		end
	end
end

-- Entry point for server-broadcast crash effects (debris breaking up, torn sections).
function Effects.crashFx(kind: string, pos: Vector3, intensity: number, vel: Vector3?)
	local v = vel or Vector3.zero
	intensity = math.clamp(intensity, 0, 10)
	if kind == "sparks" then
		if v.Magnitude > 1 then
			Effects.sparkShower(pos, -v, intensity)
		else
			Effects.sparks(pos, intensity)
		end
	elseif kind == "shards" then
		Effects.shards(pos, v, intensity * 2)
	elseif kind == "dust" then
		Effects.dust(pos, intensity)
	end
end

function Effects.shake(amount: number)
	Effects.shakeAmount = math.min(3, Effects.shakeAmount + amount)
end

return Effects
