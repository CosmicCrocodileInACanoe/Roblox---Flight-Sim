--!strict
-- Simple, original block models for the emergency services (client only, visual only):
-- fire truck, ambulance, police car, rescue boat, ferry, helicopter and life raft.
--
-- Every model has an anchored, invisible Root at road/water level (helicopter: at the
-- cabin), facing -Z like any Roblox CFrame. All other parts are unanchored, massless,
-- non-colliding and welded to the Root, so moving the Root moves the whole vehicle in
-- one write. Neon parts tagged with a "Flash" attribute ("red", "blue", "white", "amber")
-- are the warning lights; EmergencyController flashes them. Sizes are in studs
-- (1 stud = 0.28 m).

local ResponderModels = {}

local RED = Color3.fromRGB(196, 32, 30)
local WHITE = Color3.fromRGB(236, 238, 240)
local DARK = Color3.fromRGB(28, 30, 34)
local GLASS = Color3.fromRGB(40, 58, 74)
local TYRE = Color3.fromRGB(24, 24, 26)
local ORANGE = Color3.fromRGB(240, 110, 24)
local NAVY = Color3.fromRGB(24, 44, 96)
local YELLOW = Color3.fromRGB(240, 200, 40)
local STEEL = Color3.fromRGB(150, 154, 160)

local function newRoot(name: string): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Transparency = 1
	root.Size = Vector3.new(1, 1, 1)
	root.CFrame = CFrame.new()
	root.Parent = m
	m.PrimaryPart = root
	return m, root
end

-- One part welded to `to` (the Root unless given) at `offset` from the Root.
local function part(m: Model, root: BasePart, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, kind: string?, to: BasePart?): BasePart
	local p: BasePart
	if kind == "wedge" then
		p = Instance.new("WedgePart")
	else
		local pp = Instance.new("Part")
		if kind == "cylinder" then
			pp.Shape = Enum.PartType.Cylinder
		elseif kind == "ball" then
			pp.Shape = Enum.PartType.Ball
		end
		p = pp
	end
	p.Size = size
	p.CFrame = root.CFrame * offset
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = size.Magnitude > 6
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local w = Instance.new("WeldConstraint")
	w.Part0 = to or root
	w.Part1 = p
	w.Parent = p
	p.Parent = m
	return p
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function lightBar(m: Model, root: BasePart, y: number, z: number, width: number, colorA: string, colorB: string)
	for i, c in { colorA, colorB } do
		local x = (if i == 1 then -1 else 1) * width * 0.25
		local p = part(m, root, Vector3.new(width * 0.45, 0.8, 1.2), at(x, y, z), Color3.new(0.2, 0.2, 0.2), Enum.Material.Neon)
		p:SetAttribute("Flash", c)
		p:SetAttribute("Phase", i)
		local l = Instance.new("PointLight")
		l.Range = 22
		l.Brightness = 3
		l.Enabled = false
		l.Parent = p
	end
end

-- Wheels on both sides at each z, radius r (cylinder axis along X).
local function wheels(m: Model, root: BasePart, halfTrack: number, r: number, zs: { number })
	for _, z in zs do
		for _, side in { -1, 1 } do
			part(m, root, Vector3.new(1.6, r * 2, r * 2), at(side * halfTrack, r, z), TYRE, Enum.Material.Rubber, "cylinder")
			part(m, root, Vector3.new(1.7, r * 1.1, r * 1.1), at(side * halfTrack, r, z), STEEL, Enum.Material.Metal, "cylinder")
		end
	end
end

function ResponderModels.fireTruck(): Model
	local m, root = newRoot("FireTruck")
	part(m, root, Vector3.new(9, 2, 36), at(0, 3.2, 0), DARK, Enum.Material.Metal)
	part(m, root, Vector3.new(9, 8, 24), at(0, 8, 5), RED, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(9, 8, 10), at(0, 8, -12), RED, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(8.4, 3.2, 0.3), at(0, 9.6, -17.05), GLASS, Enum.Material.Glass)
	for _, side in { -1, 1 } do
		part(m, root, Vector3.new(0.3, 3, 4.5), at(side * 4.55, 9.6, -13), GLASS, Enum.Material.Glass)
		-- locker doors
		for k = 0, 2 do
			part(m, root, Vector3.new(0.2, 5, 6.6), at(side * 4.55, 7.6, -1.5 + k * 7.4), Color3.fromRGB(176, 28, 26), Enum.Material.Metal)
		end
	end
	part(m, root, Vector3.new(9.15, 0.9, 35), at(0, 5.6, 0), WHITE, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(9.2, 1.4, 0.4), at(0, 4.2, -17.1), STEEL, Enum.Material.Metal) -- bumper
	-- ladder and water cannon on the roof
	part(m, root, Vector3.new(0.5, 0.8, 26), at(-1.4, 12.6, 4), STEEL, Enum.Material.Metal)
	part(m, root, Vector3.new(0.5, 0.8, 26), at(1.4, 12.6, 4), STEEL, Enum.Material.Metal)
	for k = 0, 8 do
		part(m, root, Vector3.new(2.4, 0.3, 0.3), at(0, 12.6, -8 + k * 3), STEEL, Enum.Material.Metal)
	end
	part(m, root, Vector3.new(1.6, 1.6, 1.6), at(0, 12.9, -5), STEEL, Enum.Material.Metal, "ball")
	local nozzle = part(m, root, Vector3.new(0.8, 0.8, 3.4), at(0, 13.4, -6.8), STEEL, Enum.Material.Metal)
	nozzle.Name = "Nozzle"
	lightBar(m, root, 12.4, -12, 8, "red", "white")
	wheels(m, root, 4.2, 2.2, { -11, 6, 11 })
	return m
end

function ResponderModels.ambulance(): Model
	local m, root = newRoot("Ambulance")
	part(m, root, Vector3.new(8, 1.6, 24), at(0, 2.4, 0), DARK, Enum.Material.Metal)
	part(m, root, Vector3.new(8, 5.5, 7), at(0, 5.6, -8.5), WHITE, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(7.4, 2.4, 0.3), at(0, 7, -12.05), GLASS, Enum.Material.Glass)
	part(m, root, Vector3.new(8, 8.6, 17), at(0, 7.3, 3.5), WHITE, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(8.1, 1, 24), at(0, 5, 0), RED, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(8.1, 0.5, 17), at(0, 9.4, 3.5), Color3.fromRGB(240, 200, 30), Enum.Material.SmoothPlastic)
	-- a red cross on each side and the back
	for _, side in { -1, 1 } do
		part(m, root, Vector3.new(0.2, 3.6, 1.1), at(side * 4.05, 7.6, 4), RED)
		part(m, root, Vector3.new(0.2, 1.1, 3.6), at(side * 4.05, 7.6, 4), RED)
	end
	part(m, root, Vector3.new(1.1, 3.6, 0.2), at(0, 7.6, 12.05), RED)
	part(m, root, Vector3.new(3.6, 1.1, 0.2), at(0, 7.6, 12.05), RED)
	lightBar(m, root, 12, -4.5, 7, "red", "blue")
	wheels(m, root, 3.7, 1.8, { -8, 7 })
	return m
end

function ResponderModels.police(): Model
	local m, root = newRoot("PoliceCar")
	part(m, root, Vector3.new(6.5, 2.4, 17), at(0, 2.6, 0), NAVY, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(6.55, 1.2, 7), at(0, 2.9, 0.5), WHITE, Enum.Material.SmoothPlastic) -- doors
	part(m, root, Vector3.new(6, 2.2, 8), at(0, 4.9, 1), GLASS, Enum.Material.Glass)
	part(m, root, Vector3.new(6.1, 0.4, 7.4), at(0, 6.1, 1), NAVY, Enum.Material.SmoothPlastic)
	lightBar(m, root, 6.7, 1, 5, "red", "blue")
	wheels(m, root, 3.1, 1.5, { -5.5, 5.5 })
	return m
end

function ResponderModels.rescueBoat(): Model
	local m, root = newRoot("RescueBoat")
	part(m, root, Vector3.new(10, 3, 24), at(0, 0.6, 3), ORANGE, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(10, 3, 8), at(0, 0.6, -13) * CFrame.Angles(0, 0, math.rad(180)), ORANGE, Enum.Material.SmoothPlastic, "wedge")
	part(m, root, Vector3.new(10.2, 0.8, 32), at(0, 2.4, -1), DARK, Enum.Material.Rubber) -- fender
	part(m, root, Vector3.new(7, 5, 9), at(0, 4.5, 3), WHITE, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(6.6, 2, 0.3), at(0, 5.2, -1.55), GLASS, Enum.Material.Glass)
	part(m, root, Vector3.new(0.4, 5, 0.4), at(0, 9, 5), STEEL, Enum.Material.Metal) -- mast
	lightBar(m, root, 7.4, 1, 5, "blue", "amber")
	return m
end

function ResponderModels.ferry(): Model
	local m, root = newRoot("Ferry")
	part(m, root, Vector3.new(34, 10, 116), at(0, 1, 8), NAVY, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(34, 10, 24), at(0, 1, -62) * CFrame.Angles(0, 0, math.rad(180)), NAVY, Enum.Material.SmoothPlastic, "wedge")
	part(m, root, Vector3.new(34.2, 1.2, 116), at(0, 5.5, 8), WHITE, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(30, 8, 96), at(0, 10, 10), WHITE, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(30.2, 2, 92), at(0, 10.5, 10), GLASS, Enum.Material.Glass) -- windows
	part(m, root, Vector3.new(26, 7, 66), at(0, 17.5, 14), WHITE, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(26.2, 1.8, 62), at(0, 18, 14), GLASS, Enum.Material.Glass)
	part(m, root, Vector3.new(28, 5, 12), at(0, 23.5, -14), WHITE, Enum.Material.SmoothPlastic) -- bridge
	part(m, root, Vector3.new(28.2, 1.6, 0.3), at(0, 24, -20.1), GLASS, Enum.Material.Glass)
	part(m, root, Vector3.new(8, 10, 10), at(0, 26, 28), YELLOW, Enum.Material.SmoothPlastic) -- funnel
	part(m, root, Vector3.new(8.1, 2, 10.1), at(0, 30, 28), DARK, Enum.Material.SmoothPlastic)
	-- lifeboats along the sides
	for _, side in { -1, 1 } do
		for k = 0, 2 do
			part(m, root, Vector3.new(3, 2.4, 10), at(side * 15.6, 16, -6 + k * 22), ORANGE, Enum.Material.SmoothPlastic)
		end
	end
	lightBar(m, root, 26.6, -14, 8, "amber", "amber")
	return m
end

-- Returns the model and its rotor hub (anchored; EmergencyController spins it).
function ResponderModels.helicopter(): (Model, BasePart)
	local m, root = newRoot("RescueHelicopter")
	part(m, root, Vector3.new(7, 7, 15), at(0, 0, 0), RED, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(7, 7, 7), at(0, 0, -7.4), RED, Enum.Material.SmoothPlastic, "ball")
	part(m, root, Vector3.new(4.4, 2.6, 0.3), at(0, 1.2, -10.4), GLASS, Enum.Material.Glass)
	for _, side in { -1, 1 } do
		part(m, root, Vector3.new(0.3, 3, 6), at(side * 3.55, 1.2, -3), GLASS, Enum.Material.Glass)
		part(m, root, Vector3.new(0.6, 0.6, 16), at(side * 3.2, -5.4, -1), STEEL, Enum.Material.Metal) -- skids
		part(m, root, Vector3.new(0.5, 2.4, 0.5), at(side * 3.2, -4.4, -5), STEEL, Enum.Material.Metal)
		part(m, root, Vector3.new(0.5, 2.4, 0.5), at(side * 3.2, -4.4, 4), STEEL, Enum.Material.Metal)
	end
	part(m, root, Vector3.new(7.05, 1.2, 15.05), at(0, -1.5, 0), WHITE, Enum.Material.SmoothPlastic)
	part(m, root, Vector3.new(2, 2.2, 20), at(0, 1.6, 16), RED, Enum.Material.SmoothPlastic) -- tail boom
	part(m, root, Vector3.new(0.6, 6, 3), at(0, 4.2, 25), RED, Enum.Material.SmoothPlastic) -- fin
	part(m, root, Vector3.new(0.3, 4.5, 0.6), at(0.6, 4, 25.5), DARK, Enum.Material.Metal) -- tail rotor
	part(m, root, Vector3.new(2.4, 1.4, 4), at(0, 4.2, 0), DARK, Enum.Material.Metal) -- engine
	lightBar(m, root, -3.8, -6, 3, "red", "white")
	local spot = part(m, root, Vector3.new(1.4, 1.4, 1.4), at(0, -3.2, -7), WHITE, Enum.Material.Neon, "ball")
	local sl = Instance.new("SpotLight")
	sl.Name = "Searchlight"
	sl.Range = 60
	sl.Angle = 40
	sl.Brightness = 4
	sl.Face = Enum.NormalId.Bottom
	sl.Parent = spot
	-- rotor: an anchored hub moved every frame, blades welded to it
	local hub = Instance.new("Part")
	hub.Name = "RotorHub"
	hub.Anchored = true
	hub.CanCollide = false
	hub.CanQuery = false
	hub.CanTouch = false
	hub.Size = Vector3.new(1.4, 1.2, 1.4)
	hub.Color = DARK
	hub.Material = Enum.Material.Metal
	hub.CFrame = root.CFrame * at(0, 5.6, 0)
	hub.Parent = m
	part(m, root, Vector3.new(1.4, 0.25, 40), at(0, 5.8, 0), DARK, Enum.Material.Metal, nil, hub)
	part(m, root, Vector3.new(40, 0.25, 1.4), at(0, 5.8, 0), DARK, Enum.Material.Metal, nil, hub)
	return m, hub
end

-- An orange life raft with a canopy and a few people in it (root at the waterline).
function ResponderModels.lifeRaft(): Model
	local m, root = newRoot("LifeRaft")
	part(m, root, Vector3.new(2.2, 11, 11), at(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), ORANGE, Enum.Material.Rubber, "cylinder")
	part(m, root, Vector3.new(0.4, 8, 8), at(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 70, 76), Enum.Material.Fabric, "cylinder")
	local skin = { Color3.fromRGB(234, 192, 150), Color3.fromRGB(176, 120, 80), Color3.fromRGB(110, 72, 48) }
	local coats = { YELLOW, Color3.fromRGB(60, 110, 200), WHITE, Color3.fromRGB(60, 150, 90) }
	for k = 1, 4 do
		local a = k * math.pi / 2 + 0.4
		local x, z = math.cos(a) * 2.6, math.sin(a) * 2.6
		part(m, root, Vector3.new(1.4, 2, 1), at(x, 2.8, z), coats[k], Enum.Material.SmoothPlastic)
		part(m, root, Vector3.new(1, 1, 1), at(x, 4.3, z), skin[(k % 3) + 1], Enum.Material.SmoothPlastic, "ball")
	end
	-- canopy arch
	part(m, root, Vector3.new(0.4, 4.4, 9), at(0, 4, 0), ORANGE, Enum.Material.Fabric)
	return m
end

return ResponderModels
