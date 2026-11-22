--!strict
-- Lightweight client-side effects: sparks, dust/tyre smoke, water spray, camera shake.
-- Purely visual; nothing here affects physics. Pooled emitters keep allocations low.

local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

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

function Effects.shake(amount: number)
	Effects.shakeAmount = math.min(3, Effects.shakeAmount + amount)
end

return Effects
