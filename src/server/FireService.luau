--!strict
-- Wildfires for the Rainmaker water bomber. A few fires burn at once at sites from
-- Wildfire.sites(); each is a cluster of flames, smoke and a glow on scorched ground,
-- with a label you can see from far away. Water bombers report their drops
-- (WaterDrop remote: aircraft model, impact x, z in studs, kg, drop height in m); the
-- server checks them and puts water on the fires it reaches. A fire that goes out
-- relights somewhere else after a while.
--
-- Clients see the fires as Workspace.Wildfires/<Fire_n> models with attributes:
--   Strength (0..1), Burning (bool), SiteId. The minimap reads those.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Units = require(Shared.Units)
local Wildfire = require(Shared.Wildfire)
local Registry = require(Shared.AircraftRegistry)

local S = Units.STUDS_PER_METER

local FireService = {}

type Fire = {
	state: any,
	model: Model,
	emitters: { Instance },
	lights: { PointLight },
	label: TextLabel,
	outAt: number?,
}

local fires: { Fire } = {}
local folder: Folder
local remotes: Folder
local dropBudget: { [Player]: { kg: number, t: number } } = {}

local function anchoredPart(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function flameEmitter(parent: Instance, scale: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Flames"
	e.Texture = "rbxasset://textures/particles/fire_main.dds"
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 120)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 30)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 40, 10)),
	})
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 18 * scale), NumberSequenceKeypoint.new(1, 6 * scale) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.8, 1.6)
	e.Speed = NumberRange.new(14, 30)
	e.SpreadAngle = Vector2.new(20, 20)
	e.Acceleration = Vector3.new(0, 20, 0)
	e.Rate = 22
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = parent
	return e
end

local function smokeEmitter(parent: Instance): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "SmokeColumn"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(70, 66, 62), Color3.fromRGB(150, 146, 140))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 60), NumberSequenceKeypoint.new(1, 260) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(10, 16)
	e.Speed = NumberRange.new(40, 70)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Acceleration = Vector3.new(18, 6, 0) -- drifts with the breeze
	e.Rate = 6
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = parent
	return e
end

local function steamPuff(pos: Vector3)
	local p = anchoredPart("Steam", Vector3.one, CFrame.new(pos), Color3.new(1, 1, 1))
	p.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(235, 238, 240))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 50), NumberSequenceKeypoint.new(1, 180) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(5, 8)
	e.Speed = NumberRange.new(20, 45)
	e.SpreadAngle = Vector2.new(60, 60)
	e.Rate = 0
	e.Parent = p
	p.Parent = folder
	e:Emit(40)
	task.delay(10, function()
		p:Destroy()
	end)
end

local function buildFire(site: any, index: number): Fire
	local model = Instance.new("Model")
	model.Name = "Fire_" .. index
	model:SetAttribute("SiteId", site.id)
	local radius = Wildfire.RADIUS_M * S
	local centre = Vector3.new(site.x, site.y, site.z)
	-- scorched ground
	local scorch = anchoredPart("Scorch", Vector3.new(1.2, radius * 2.3, radius * 2.3), CFrame.new(centre + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(38, 30, 26), Enum.Material.Slate)
	scorch.Shape = Enum.PartType.Cylinder
	scorch.Parent = model
	model.PrimaryPart = scorch

	local emitters, lights = {}, {}
	local rng = Random.new(site.id * 7919)
	for k = 1, 7 do
		local a = (k / 7) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local d = if k == 7 then 0 else radius * rng:NextNumber(0.3, 0.85)
		local pos = centre + Vector3.new(math.cos(a) * d, 2, math.sin(a) * d)
		local base = anchoredPart("Flame", Vector3.new(20, 2, 20), CFrame.new(pos), Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
		base.Transparency = 0.4
		base.CastShadow = false
		base.Parent = model
		table.insert(emitters, flameEmitter(base, rng:NextNumber(0.8, 1.3)))
		local fire = Instance.new("Fire")
		fire.Size = 25
		fire.Heat = 20
		fire.Parent = base
		table.insert(emitters, fire)
		if k % 2 == 1 then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 140, 60)
			light.Range = 60
			light.Brightness = 3
			light.Parent = base
			table.insert(lights, light)
		end
	end
	local smokeBase = anchoredPart("SmokeSource", Vector3.one, CFrame.new(centre + Vector3.new(0, 20, 0)), Color3.new(0, 0, 0))
	smokeBase.Transparency = 1
	smokeBase.Parent = model
	table.insert(emitters, smokeEmitter(smokeBase))

	-- a label that shows from far away, so pilots can find the fire
	local gui = Instance.new("BillboardGui")
	gui.Name = "FireLabel"
	gui.Size = UDim2.fromOffset(170, 62)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 260, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60000
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.62)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 140, 50)
	label.TextStrokeTransparency = 0.3
	label.Text = "WILDFIRE"
	label.Parent = gui
	-- distance line under the title: each client fills it in for its own position
	local dist = Instance.new("TextLabel")
	dist.Name = "Distance"
	dist.BackgroundTransparency = 1
	dist.Position = UDim2.fromScale(0, 0.62)
	dist.Size = UDim2.fromScale(1, 0.38)
	dist.Font = Enum.Font.GothamBold
	dist.TextScaled = true
	dist.TextColor3 = Color3.fromRGB(255, 235, 200)
	dist.TextStrokeTransparency = 0.3
	dist.Text = ""
	dist.Parent = gui
	gui.Parent = smokeBase

	model.Parent = folder
	local f: Fire = { state = Wildfire.newFire(site), model = model, emitters = emitters, lights = lights, label = label, outAt = nil }
	return f
end

local function setVisuals(f: Fire)
	local st = f.state
	local k = if st.burning then math.max(0.15, st.strength) else 0
	for _, e in f.emitters do
		if e:IsA("ParticleEmitter") then
			e.Enabled = k > 0
			if e.Name == "Flames" then
				e.Rate = 22 * k
			end
		elseif e:IsA("Fire") then
			e.Enabled = k > 0
			e.Size = math.max(2, 25 * k)
		end
		local base = e.Parent
		if base and base:IsA("BasePart") and base.Name == "Flame" then
			base.Transparency = if k > 0 then 1 - 0.6 * k else 1
		end
	end
	for _, l in f.lights do
		l.Brightness = 3 * k
	end
	f.label.Text = if st.burning then string.format("WILDFIRE %d%%", math.floor(st.strength * 100 + 0.5)) else "FIRE OUT"
	f.label.TextColor3 = if st.burning then Color3.fromRGB(255, 140, 50) else Color3.fromRGB(140, 220, 255)
	f.model:SetAttribute("Strength", st.strength)
	f.model:SetAttribute("Burning", st.burning)
end

-- A site not in use by another fire, picked at random.
local function freeSite(): any?
	local used = {}
	for _, f in fires do
		used[f.state.site.id] = true
	end
	local free = {}
	for _, s in Wildfire.sites() do
		if not used[s.id] then
			table.insert(free, s)
		end
	end
	if #free == 0 then
		return nil
	end
	return free[math.random(1, #free)]
end

local function relight(f: Fire)
	local site = freeSite()
	if not site then
		return
	end
	local index = table.find(fires, f) or 1
	f.model:Destroy()
	fires[index] = buildFire(site, index)
	setVisuals(fires[index])
end

local function onDrop(p: Player, model: any, x: any, z: any, kg: any, heightM: any)
	if typeof(model) ~= "Instance" or not (model :: Instance):IsA("Model") then
		return
	end
	if type(x) ~= "number" or type(z) ~= "number" or type(kg) ~= "number" or type(heightM) ~= "number" then
		return
	end
	if x ~= x or z ~= z or kg ~= kg or heightM ~= heightM or kg <= 0 then
		return
	end
	local m = model :: Model
	if m:GetAttribute("OwnerUserId") ~= p.UserId or not m.Parent then
		return
	end
	local cfg = Registry.get(m:GetAttribute("AircraftId") :: string)
	if not cfg or not cfg.waterTank then
		return
	end
	-- no more water than the tank can pour out (with slack for network bunching)
	local now = os.clock()
	-- a new player starts with a full tank's worth, so their first drop counts in full
	local b = dropBudget[p] or { kg = cfg.waterTank.capacity, t = now }
	b.kg = math.min(cfg.waterTank.capacity, b.kg + (now - b.t) * cfg.waterTank.dropRate * 1.5)
	b.t = now
	dropBudget[p] = b
	kg = math.min(kg, b.kg)
	b.kg -= kg
	-- the impact point must be close to the aircraft
	local core = m.PrimaryPart
	if not core then
		return
	end
	local pos = core.Position
	if (Vector3.new(pos.X - x, 0, pos.Z - z)).Magnitude > 2500 then
		return
	end
	heightM = math.clamp(heightM, 0, 3000)
	for _, f in fires do
		local st = f.state
		if st.burning then
			local d = Vector3.new(st.site.x - x, 0, st.site.z - z).Magnitude / S
			local onFire = Wildfire.waterOnFire(kg, d, heightM)
			if onFire > 0 then
				local wasStrength = st.strength
				local out = Wildfire.douse(st, onFire)
				setVisuals(f)
				if out then
					f.outAt = os.clock()
					steamPuff(Vector3.new(st.site.x, st.site.y + 40, st.site.z))
					;(remotes:FindFirstChild("Notify") :: RemoteEvent):FireAllClients(string.format("%s put out a wildfire!", p.DisplayName))
				elseif math.floor(wasStrength * 4) ~= math.floor(st.strength * 4) then
					(remotes:FindFirstChild("Notify") :: RemoteEvent):FireClient(p, string.format("Direct hit! Fire at %d%%", math.floor(st.strength * 100 + 0.5)))
				end
			end
		end
	end
end

function FireService.init(remoteFolder: Folder)
	remotes = remoteFolder
	folder = Instance.new("Folder")
	folder.Name = "Wildfires"
	folder.Parent = Workspace
	local sites = table.clone(Wildfire.sites())
	-- start at a shuffled few of the sites
	for i = #sites, 2, -1 do
		local j = math.random(1, i)
		sites[i], sites[j] = sites[j], sites[i]
	end
	for i = 1, math.min(Wildfire.ACTIVE, #sites) do
		local f = buildFire(sites[i], i)
		fires[i] = f
		setVisuals(f)
	end
	;(remotes:FindFirstChild("WaterDrop") :: RemoteEvent).OnServerEvent:Connect(onDrop)
	Players.PlayerRemoving:Connect(function(p)
		dropBudget[p] = nil
	end)
	-- slow tick: damped fires flare up again, put-out fires relight elsewhere
	task.spawn(function()
		while true do
			task.wait(2)
			for _, f in table.clone(fires) do
				local st = f.state
				if st.burning then
					local before = st.strength
					Wildfire.regrow(st, 2)
					if math.abs(st.strength - before) > 1e-6 then
						setVisuals(f)
					end
				elseif f.outAt and os.clock() - f.outAt > Wildfire.RELIGHT_SECONDS then
					relight(f)
				end
			end
		end
	end)
end

return FireService
