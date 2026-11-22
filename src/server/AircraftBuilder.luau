--!strict
-- Parametric airliner builder. Turns an aircraft config's `geometry` block into a
-- physical Roblox Model made of original primitive parts:
--
--   Model (PrimaryPart = Core)
--     Core            invisible mass/inertia box at the CoM (the only massive part)
--     <Component> Models (Fuselage, ForwardFuselage, LeftWing, LeftEngine, ...)
--       Root          invisible joint part; welded to its parent component's Root
--       visual/hull parts welded to Root (Massless, collidable hull)
--       control surfaces / gear legs / fans driven by Motor6D (client animates Transform)
--
-- Detaching a component = destroying its Root's "Joint" weld; it then falls away as
-- one rigid debris assembly together with any child components.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Units = require(Shared.Units)
local GameConfig = require(Shared.GameConfig)

local S = Units.STUDS_PER_METER

local AircraftBuilder = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

type Ctx = {
	model: Model,
	core: BasePart,
	coreCF: CFrame,
	comps: { [string]: Model },
	roots: { [string]: BasePart },
	cfg: any,
	hull: PhysicalProperties,
}

local function newPart(className: string?): BasePart
	local p = Instance.new((className or "Part") :: any) :: BasePart
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CollisionGroup = GameConfig.CollisionGroups.Aircraft
	return p
end

-- Local body-frame (metres) CFrame -> world CFrame.
local function worldCF(ctx: Ctx, localCF: CFrame): CFrame
	return ctx.coreCF * (CFrame.new(localCF.Position * S) * localCF.Rotation)
end

local function weld(a: BasePart, b: BasePart, name: string?)
	local w = Instance.new("WeldConstraint")
	w.Name = name or "Weld"
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
	return w
end

local function getComponent(ctx: Ctx, name: string): Model
	local m = ctx.comps[name]
	if m then
		return m
	end
	local compCfg = ctx.cfg.components[name]
	assert(compCfg, "component not in config: " .. name)
	m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("Component", name)
	local root = newPart()
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	local ref = compCfg.ref or { 0, 0, 0 }
	root.CFrame = worldCF(ctx, CFrame.new(v3(ref)))
	root:SetAttribute("Component", name)
	root.Parent = m
	m.PrimaryPart = root
	local parentRoot = if compCfg.parent then ctx.roots[compCfg.parent] else ctx.core
	if not parentRoot then
		getComponent(ctx, compCfg.parent)
		parentRoot = ctx.roots[compCfg.parent]
	end
	weld(parentRoot, root, "Joint")
	m.Parent = ctx.model
	ctx.comps[name] = m
	ctx.roots[name] = root
	return m
end

-- Add a part to a component. size in metres, localCF in body metres.
local function add(ctx: Ctx, comp: string, name: string, shape: string, sizeM: Vector3, localCF: CFrame, color: Color3, opts: any?): BasePart
	local o = opts or {}
	local p: BasePart
	if shape == "wedge" then
		p = newPart("WedgePart")
	else
		p = newPart()
		if shape == "cylinder" then
			(p :: Part).Shape = Enum.PartType.Cylinder
		elseif shape == "ball" then
			(p :: Part).Shape = Enum.PartType.Ball
		end
	end
	p.Name = name
	p.Size = Vector3.new(math.max(0.05, sizeM.X * S), math.max(0.05, sizeM.Y * S), math.max(0.05, sizeM.Z * S))
	p.CFrame = worldCF(ctx, localCF)
	p.Color = color
	if o.material then
		p.Material = o.material
	end
	if o.transparency then
		p.Transparency = o.transparency
	end
	if o.reflectance then
		p.Reflectance = o.reflectance
	end
	if o.hull then
		p.CanCollide = true
		p.CanTouch = true
		p.CanQuery = true
		p.CustomPhysicalProperties = ctx.hull
	end
	p:SetAttribute("Component", comp)
	if o.tag then
		p:SetAttribute(o.tag, true)
	end
	local m = getComponent(ctx, comp)
	p.Parent = m
	if not o.noWeld then
		weld(ctx.roots[comp], p)
	end
	return p
end

local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis (X) -> body Z

-- Fuselage -------------------------------------------------------------------------
local function buildFuselage(ctx: Ctx)
	local g = ctx.cfg.geometry.fuselage
	local liv = ctx.cfg.geometry.livery
	local body, belly, stripe = rgb(liv.body), rgb(liv.belly), rgb(liv.stripe)
	local R = g.radius
	local D = R * 2

	-- Cabin barrel in three structural sections.
	local sections = {
		{ "ForwardFuselage", g.cabinStartZ, g.forwardSplitZ },
		{ "Fuselage", g.forwardSplitZ, g.aftSplitZ },
		{ "AftFuselage", g.aftSplitZ, g.cabinEndZ },
	}
	for _, s in sections do
		local comp, z0, z1 = s[1], s[2], s[3]
		local len = z1 - z0
		local mid = (z0 + z1) / 2
		local hide = if comp == "ForwardFuselage" then "HideInCockpit" else nil
		add(ctx, comp, "Barrel", "cylinder", Vector3.new(len + 0.02, D, D), CFrame.new(0, 0, mid) * ALONG_Z, body, { hull = true, tag = hide })
		-- belly fairing
		add(ctx, comp, "Belly", "cylinder", Vector3.new(len, D * 0.92, D * 0.96), CFrame.new(0, -0.14, mid) * ALONG_Z, belly, { tag = hide })
		-- window band and cheatline stripe on both sides
		for _, sx in { -1, 1 } do
			add(ctx, comp, "Windows", "block", Vector3.new(0.04, 0.3, len * 0.96), CFrame.new(sx * (R - 0.005), 0.55, mid), Color3.fromRGB(40, 48, 60), { tag = hide })
			add(ctx, comp, "Stripe", "block", Vector3.new(0.04, 0.22, len), CFrame.new(sx * (R - 0.12), -0.05, mid) * CFrame.Angles(0, 0, sx * math.rad(-8)), stripe, { tag = hide })
		end
	end

	-- Nose: tapering stack + cockpit windows.
	local noseLen = g.cabinStartZ - g.noseZ
	local steps = 5
	for i = 1, steps do
		local t0, t1 = (i - 1) / steps, i / steps
		local z0 = g.cabinStartZ - noseLen * t0
		local z1 = g.cabinStartZ - noseLen * t1
		local f = math.cos(t1 * math.pi * 0.42) -- radius profile
		local r = R * math.max(0.18, f)
		local dropY = -0.35 * t1 * t1
		add(ctx, "ForwardFuselage", "Nose" .. i, "cylinder", Vector3.new(math.abs(z1 - z0) + 0.05, r * 2, r * 2), CFrame.new(0, dropY, (z0 + z1) / 2) * ALONG_Z, body, { hull = true, tag = "HideInCockpit" })
	end
	add(ctx, "ForwardFuselage", "NoseTip", "ball", Vector3.new(R * 0.42, R * 0.42, R * 0.42), CFrame.new(0, -0.35, g.noseZ + 0.15), body, { hull = true, tag = "HideInCockpit" })
	-- cockpit windscreen panels
	for _, sx in { -1, 1 } do
		add(ctx, "ForwardFuselage", "Windscreen", "block", Vector3.new(0.9, 0.42, 0.05), CFrame.new(sx * 0.55, 0.95, g.cabinStartZ - noseLen * 0.38) * CFrame.Angles(math.rad(-38), sx * math.rad(-22), 0), Color3.fromRGB(25, 30, 40), { material = Enum.Material.Glass, reflectance = 0.3, tag = "HideInCockpit" })
	end

	-- Tail cone: tapering and sweeping upward.
	local tailLen = g.tailEndZ - g.cabinEndZ
	steps = 6
	for i = 1, steps do
		local t0, t1 = (i - 1) / steps, i / steps
		local z0 = g.cabinEndZ + tailLen * t0
		local z1 = g.cabinEndZ + tailLen * t1
		local r = R * (1 - 0.78 * ((t0 + t1) / 2) ^ 1.2)
		local y = g.tailUpsweep * ((t0 + t1) / 2) ^ 1.4
		add(ctx, "AftFuselage", "TailCone" .. i, "cylinder", Vector3.new(z1 - z0 + 0.05, r * 2, r * 2), CFrame.new(0, y, (z0 + z1) / 2) * ALONG_Z, body, { hull = true })
	end
	add(ctx, "AftFuselage", "APU", "cylinder", Vector3.new(0.6, 0.45, 0.45), CFrame.new(0, g.tailUpsweep, g.tailEndZ + 0.2) * ALONG_Z, Color3.fromRGB(90, 90, 95))

	-- Airline name (fictional) on both sides, via SurfaceGui on thin transparent panels.
	for _, sx in { -1, 1 } do
		local p = add(ctx, "Fuselage", "Titles", "block", Vector3.new(0.02, 0.9, 9), CFrame.new(sx * (R + 0.01), 1.0, -1.5), body, { transparency = 1 })
		local gui = Instance.new("SurfaceGui")
		gui.Face = if sx > 0 then Enum.NormalId.Right else Enum.NormalId.Left
		gui.PixelsPerStud = 20
		gui.LightInfluence = 1
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = liv.airline
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = stripe
		label.Parent = gui
		gui.Parent = p
	end
end

-- Lifting surfaces --------------------------------------------------------------------
-- Builds one half-wing (or half-tailplane) as swept, tapered, dihedral segments.
local function buildHalfSurface(ctx: Ctx, comp: string, spec: any, sx: number, color: Color3, surfaceKind: string)
	local rl = spec.rootLE
	local tanSweep = math.tan(math.rad(spec.sweepDeg))
	local tanDih = math.tan(math.rad(spec.dihedralDeg))
	local segs = spec.segments or 2
	local function le(s: number): Vector3
		return Vector3.new(sx * (rl[1] + s), rl[2] + s * tanDih, rl[3] + s * tanSweep)
	end
	local function chord(s: number): number
		return spec.rootChord + (spec.tipChord - spec.rootChord) * s / spec.span
	end
	local function thick(s: number): number
		local t0 = spec.rootThickness or spec.thickness
		local t1 = spec.tipThickness or spec.thickness * 0.6
		return t0 + (t1 - t0) * s / spec.span
	end
	local aft = Vector3.new(0, 0, 1)
	local segParts = {}
	for k = 1, segs do
		local s0, s1 = spec.span * (k - 1) / segs, spec.span * k / segs
		local m0 = le(s0) + Vector3.new(0, 0, chord(s0) / 2)
		local m1 = le(s1) + Vector3.new(0, 0, chord(s1) / 2)
		local d = m1 - m0
		local dir = d.Unit
		if dir.X < 0 then
			dir = -dir
		end
		local up = aft:Cross(dir).Unit
		if up.Y < 0 then
			up = -up
		end
		local cosL = math.abs(dir.X) / math.sqrt(dir.X * dir.X + dir.Z * dir.Z)
		local c = (chord(s0) + chord(s1)) / 2
		local width = c * cosL
		local len = d.Magnitude + 0.08
		local th = (thick(s0) + thick(s1)) / 2
		local center = (m0 + m1) / 2
		local cf = CFrame.fromMatrix(center, dir, up)
		local seg = add(ctx, comp, "Panel" .. k, "block", Vector3.new(len, th, width), cf, color, { hull = true })
		segParts[k] = seg

		-- Control surface on this segment?
		local sMid = (s0 + s1) / 2 / spec.span
		local ctlKind: string? = nil
		if surfaceKind == "wing" then
			if sMid >= spec.aileronStart then
				ctlKind = "Aileron"
			elseif sMid <= spec.flapEnd then
				ctlKind = "Flap"
			end
		elseif surfaceKind == "hstab" then
			ctlKind = "Elevator"
		end
		if ctlKind then
			local cw = width * spec.controlChord
			local surf = add(ctx, comp, ctlKind, "block", Vector3.new(len * 0.94, th * 0.8, cw), cf * CFrame.new(0, 0, width / 2 - cw / 2), color:Lerp(Color3.new(0, 0, 0), 0.12), { noWeld = true })
			local m = Instance.new("Motor6D")
			m.Name = ctlKind .. "Hinge"
			m.Part0 = seg
			m.Part1 = surf
			m.C0 = CFrame.new(0, 0, (width / 2 - cw) * S)
			m.C1 = CFrame.new(0, 0, -cw / 2 * S)
			m:SetAttribute("Surface", ctlKind)
			m:SetAttribute("Side", sx)
			m.Parent = seg
		end
		if surfaceKind == "wing" and k == 2 then
			-- spoiler panel on top of the second segment
			local sp = add(ctx, comp, "Spoiler", "block", Vector3.new(len * 0.8, 0.05, width * 0.18), cf * CFrame.new(0, th / 2 + 0.02, width * 0.18), color:Lerp(Color3.new(0, 0, 0), 0.2), { noWeld = true })
			local m = Instance.new("Motor6D")
			m.Name = "SpoilerHinge"
			m.Part0 = seg
			m.Part1 = sp
			m.C0 = CFrame.new(0, (th / 2 + 0.02) * S, (width * 0.09) * S)
			m.C1 = CFrame.new(0, 0, -(width * 0.09) * S)
			m:SetAttribute("Surface", "Spoiler")
			m:SetAttribute("Side", sx)
			m.Parent = seg
		end
	end
	return le, chord, segParts
end

local function buildWings(ctx: Ctx)
	local geo = ctx.cfg.geometry
	local liv = geo.livery
	local wingColor = rgb(liv.wing)
	for _, sx in { -1, 1 } do
		local comp = if sx < 0 then "LeftWing" else "RightWing"
		local le, chord = buildHalfSurface(ctx, comp, geo.wing, sx, wingColor, "wing")
		local w = geo.wing
		-- winglet
		local tip = le(w.span)
		local tc = chord(w.span)
		add(ctx, comp, "Winglet", "block", Vector3.new(0.12, w.wingletHeight, tc * 0.9), CFrame.new(tip + Vector3.new(0, w.wingletHeight / 2, tc * 0.6)) * CFrame.Angles(math.rad(-25), 0, sx * math.rad(-12)), rgb(liv.tail), { hull = true })
		-- navigation lights: red left, green right
		add(ctx, comp, "NavLight", "ball", Vector3.new(0.25, 0.25, 0.25), CFrame.new(tip + Vector3.new(0, 0.05, 0.25)), if sx < 0 then Color3.fromRGB(255, 40, 40) else Color3.fromRGB(40, 255, 80), { material = Enum.Material.Neon })
		-- wing root fairing
		add(ctx, comp, "RootFairing", "block", Vector3.new(1.6, 0.9, 7.2), CFrame.new(sx * 1.6, -1.35, w.rootLE[3] + 3.4), rgb(liv.belly), { hull = true })
	end
end

local function buildTail(ctx: Ctx)
	local geo = ctx.cfg.geometry
	local liv = geo.livery
	local tailColor = rgb(liv.tail)
	for _, sx in { -1, 1 } do
		local hs = table.clone(geo.hstab)
		hs.segments = 2
		buildHalfSurface(ctx, "HorizontalStab", hs, sx, rgb(liv.wing), "hstab")
	end
	-- Fin: segments up the height, rudder on each.
	local v = geo.vstab
	local tanSweep = math.tan(math.rad(v.sweepDeg))
	local segs = 3
	local function le(h: number): Vector3
		return Vector3.new(0, v.rootLE[2] + h, v.rootLE[3] + h * tanSweep)
	end
	local function chord(h: number): number
		return v.rootChord + (v.tipChord - v.rootChord) * h / v.height
	end
	for k = 1, segs do
		local h0, h1 = v.height * (k - 1) / segs, v.height * k / segs
		local m0 = le(h0) + Vector3.new(0, 0, chord(h0) / 2)
		local m1 = le(h1) + Vector3.new(0, 0, chord(h1) / 2)
		local d = m1 - m0
		local dir = d.Unit
		local left = Vector3.new(-1, 0, 0)
		local c = (chord(h0) + chord(h1)) / 2
		local width = c * math.abs(dir.Y)
		local cf = CFrame.fromMatrix((m0 + m1) / 2, dir, left)
		local seg = add(ctx, "VerticalStab", "Fin" .. k, "block", Vector3.new(d.Magnitude + 0.06, v.thickness, width), cf, tailColor, { hull = true })
		local cw = width * v.controlChord
		local surf = add(ctx, "VerticalStab", "Rudder", "block", Vector3.new(d.Magnitude * 0.94, v.thickness * 0.8, cw), cf * CFrame.new(0, 0, width / 2 - cw / 2), tailColor:Lerp(Color3.new(0, 0, 0), 0.12), { noWeld = true })
		local m = Instance.new("Motor6D")
		m.Name = "RudderHinge"
		m.Part0 = seg
		m.Part1 = surf
		m.C0 = CFrame.new(0, 0, (width / 2 - cw) * S)
		m.C1 = CFrame.new(0, 0, -cw / 2 * S)
		m:SetAttribute("Surface", "Rudder")
		m.Parent = seg
		if k == 2 then
			-- accent band (fictional airline logo stand-in)
			add(ctx, "VerticalStab", "TailLogo", "block", Vector3.new(d.Magnitude * 0.7, v.thickness + 0.04, width * 0.25), cf * CFrame.new(0, 0, -width * 0.1), rgb(liv.accent))
		end
	end
	-- tail light
	add(ctx, "AftFuselage", "TailLight", "ball", Vector3.new(0.22, 0.22, 0.22), CFrame.new(0, geo.fuselage.tailUpsweep + 0.2, geo.fuselage.tailEndZ + 0.3), Color3.new(1, 1, 1), { material = Enum.Material.Neon })
	-- beacon
	add(ctx, "Fuselage", "Beacon", "ball", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, geo.fuselage.radius + 0.1, 2), Color3.fromRGB(255, 30, 30), { material = Enum.Material.Neon, tag = "Beacon" })
end

local function buildEngines(ctx: Ctx)
	local geo = ctx.cfg.geometry
	local liv = geo.livery
	local eg = geo.engine
	for i, e in ctx.cfg.engines do
		local comp = e.component
		local p = v3(e.pos)
		local L, R = eg.length, eg.radius
		add(ctx, comp, "Nacelle", "cylinder", Vector3.new(L, R * 2, R * 2), CFrame.new(p) * ALONG_Z, rgb(liv.engine), { hull = true })
		add(ctx, comp, "Intake", "cylinder", Vector3.new(0.35, R * 2.06, R * 2.06), CFrame.new(p + Vector3.new(0, 0, -L / 2 + 0.1)) * ALONG_Z, Color3.fromRGB(190, 192, 198))
		add(ctx, comp, "FanFace", "cylinder", Vector3.new(0.05, R * 1.8, R * 1.8), CFrame.new(p + Vector3.new(0, 0, -L / 2 + 0.06)) * ALONG_Z, Color3.fromRGB(30, 32, 36))
		-- spinning fan: hub + blades on a Motor6D
		local hub = add(ctx, comp, "FanHub", "cylinder", Vector3.new(0.3, R * 0.5, R * 0.5), CFrame.new(p + Vector3.new(0, 0, -L / 2 + 0.02)) * ALONG_Z, Color3.fromRGB(200, 200, 205), { noWeld = true })
		for b = 0, 2 do
			local blade = add(ctx, comp, "FanBlade", "block", Vector3.new(0.12, R * 1.7, 0.04), CFrame.new(p + Vector3.new(0, 0, -L / 2 + 0.0)) * CFrame.Angles(0, 0, b * math.pi / 3), Color3.fromRGB(70, 72, 80), { noWeld = true })
			weld(hub, blade)
		end
		local nacelle = (ctx.comps[comp] :: any).Nacelle :: BasePart
		local m = Instance.new("Motor6D")
		m.Name = "FanMotor"
		m.Part0 = nacelle
		m.Part1 = hub
		m.C0 = CFrame.new((L / 2 - 0.02) * S, 0, 0) -- nacelle local +X points forward (body -Z)
		m.C1 = CFrame.new()
		m:SetAttribute("EngineIndex", i)
		m.Parent = nacelle
		-- exhaust and pylon
		add(ctx, comp, "Exhaust", "cylinder", Vector3.new(1.0, R * 1.2, R * 1.2), CFrame.new(p + Vector3.new(0, 0, L / 2 + 0.4)) * ALONG_Z, Color3.fromRGB(120, 120, 128), { material = Enum.Material.Metal })
		add(ctx, comp, "Pylon", "block", Vector3.new(0.35, 1.1, L * 0.9), CFrame.new(p + Vector3.new(0, R * 0.9, 0.6)), rgb(liv.engine), { hull = true })
		-- smoke emitter (enabled by the client when the engine is failed/on fire)
		local att = Instance.new("Attachment")
		att.Name = "SmokeAttachment"
		att.Position = Vector3.new(0, 0, 0)
		att.Parent = (ctx.comps[comp] :: any).Exhaust
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "FailureSmoke"
		smoke.Enabled = false
		smoke.Rate = 25
		smoke.Lifetime = NumberRange.new(2, 4)
		smoke.Speed = NumberRange.new(2, 6)
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 18) })
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		smoke.Color = ColorSequence.new(Color3.fromRGB(60, 60, 60))
		smoke.Parent = att
	end
end

local function buildGear(ctx: Ctx)
	local tire = Color3.fromRGB(28, 28, 30)
	local strutColor = Color3.fromRGB(170, 172, 178)
	for _, u in ctx.cfg.gear.units do
		local comp = u.component
		local model = getComponent(ctx, comp)
		local root = model.PrimaryPart :: BasePart
		local attach = v3(u.pos)
		local L = u.strutLength
		-- leg: centred L/2 below the attach point
		local leg = add(ctx, comp, "Leg", "cylinder", Vector3.new(L, 0.28, 0.28), CFrame.new(attach - Vector3.new(0, L / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), strutColor, { noWeld = true, material = Enum.Material.Metal })
		local m = Instance.new("Motor6D")
		m.Name = "GearMotor"
		m.Part0 = root
		m.Part1 = leg
		-- C0: attach point in root space (root is at the component ref point, unrotated)
		local rootLocal = ctx.coreCF:ToObjectSpace(root.CFrame).Position / S
		m.C0 = CFrame.new((attach - rootLocal) * S)
		-- C1: attach point in leg space. Leg is rotated 90 deg about Z (cylinder axis X -> Y).
		m.C1 = CFrame.new(L / 2 * S, 0, 0) * CFrame.Angles(0, 0, -math.rad(90))
		m:SetAttribute("GearName", u.name)
		m.Parent = root
		-- wheels: cylinders with axis along body X, welded to the leg
		local n = u.wheels or 2
		for w = 1, n do
			local off = (w - (n + 1) / 2) * (u.wheelSpacing or 0.6)
			local wheel = add(ctx, comp, "Wheel", "cylinder", Vector3.new(0.38, u.wheelRadius * 2, u.wheelRadius * 2), CFrame.new(attach + Vector3.new(off, -L, 0)), tire, { noWeld = true })
			weld(leg, wheel)
			local hubcap = add(ctx, comp, "Hub", "cylinder", Vector3.new(0.4, u.wheelRadius * 0.9, u.wheelRadius * 0.9), CFrame.new(attach + Vector3.new(off, -L, 0)), strutColor, { noWeld = true })
			weld(leg, hubcap)
		end
		if u.steerMaxDeg > 0 then
			-- taxi/landing light on the nose gear
			local lamp = add(ctx, comp, "LandingLamp", "block", Vector3.new(0.3, 0.2, 0.1), CFrame.new(attach + Vector3.new(0, -L * 0.45, -0.25)), Color3.new(1, 1, 0.9), { noWeld = true, material = Enum.Material.Neon })
			weld(leg, lamp)
			local spot = Instance.new("SpotLight")
			spot.Name = "LandingLight"
			spot.Face = Enum.NormalId.Front
			spot.Angle = 50
			spot.Range = 60
			spot.Brightness = 6
			spot.Enabled = false
			spot.Parent = lamp
		end
	end
end

local function buildCockpit(ctx: Ctx)
	-- Minimal interior seen only from the cockpit camera.
	local g = ctx.cfg.geometry
	local eye = v3(ctx.cfg.cameras.cockpit)
	local dark = Color3.fromRGB(38, 40, 46)
	local z = eye.Z - 1.15
	add(ctx, "ForwardFuselage", "Glareshield", "block", Vector3.new(2.4, 0.18, 0.7), CFrame.new(0.55, eye.Y - 0.35, z), dark, { tag = "CockpitOnly", transparency = 1 })
	add(ctx, "ForwardFuselage", "Panel", "block", Vector3.new(2.4, 0.8, 0.1), CFrame.new(0.55, eye.Y - 0.8, z + 0.25) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(28, 30, 34), { tag = "CockpitOnly", transparency = 1 })
	for _, x in { -1.2, 0.55, 2.3 } do
		add(ctx, "ForwardFuselage", "Post", "block", Vector3.new(0.09, 0.9, 0.09), CFrame.new(x, eye.Y + 0.05, z - 0.1) * CFrame.Angles(math.rad(-30), 0, 0), dark, { tag = "CockpitOnly", transparency = 1 })
	end
	add(ctx, "ForwardFuselage", "Roof", "block", Vector3.new(3.4, 0.08, 1.4), CFrame.new(0.55, eye.Y + 0.55, z + 0.4), dark, { tag = "CockpitOnly", transparency = 1 })
	-- pilot seat
	local seat = Instance.new("Seat")
	seat.Name = "PilotSeat"
	seat.Size = Vector3.new(2.0, 0.6, 2.0)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.Massless = true
	seat.CollisionGroup = GameConfig.CollisionGroups.Aircraft
	seat.CFrame = worldCF(ctx, CFrame.new(v3(g.seat)))
	seat:SetAttribute("Component", "ForwardFuselage")
	local comp = getComponent(ctx, "ForwardFuselage")
	seat.Parent = comp
	weld(comp.PrimaryPart :: BasePart, seat)
end

-- Core: invisible box whose size reproduces the configured principal inertias.
function AircraftBuilder.inertiaBox(cfg: any): Vector3
	local m = cfg.mass
	local I = cfg.inertia
	-- body x = pitch axis, y = yaw axis, z = roll axis
	local lx2 = 6 * (I.yaw + I.roll - I.pitch) / m
	local ly2 = 6 * (I.pitch + I.roll - I.yaw) / m
	local lz2 = 6 * (I.pitch + I.yaw - I.roll) / m
	return Vector3.new(math.sqrt(math.max(lx2, 1)), math.sqrt(math.max(ly2, 1)), math.sqrt(math.max(lz2, 1))) * S
end

-- Build the aircraft at `cf` (CoM position and orientation, studs). Returns the Model.
function AircraftBuilder.build(cfg: any, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = cfg.displayName
	model:SetAttribute("AircraftId", cfg.id)

	local core = newPart()
	core.Name = "Core"
	core.Size = AircraftBuilder.inertiaBox(cfg)
	core.Transparency = 1
	core.Massless = false
	core.RootPriority = 127
	core.CustomPhysicalProperties = PhysicalProperties.new(1.0, 0.3, 0, 1, 1)
	core.CFrame = cf
	core.Anchored = true
	core.Parent = model
	model.PrimaryPart = core

	local att = Instance.new("Attachment")
	att.Name = "ForceAttachment"
	att.Parent = core
	local vf = Instance.new("VectorForce")
	vf.Name = "AeroForce"
	vf.Attachment0 = att
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Force = Vector3.zero
	vf.Parent = core
	local tq = Instance.new("Torque")
	tq.Name = "AeroTorque"
	tq.Attachment0 = att
	tq.RelativeTo = Enum.ActuatorRelativeTo.World
	tq.Torque = Vector3.zero
	tq.Parent = core

	local ctx: Ctx = {
		model = model,
		core = core,
		coreCF = cf,
		comps = {},
		roots = { Fuselage = core },
		cfg = cfg,
		hull = PhysicalProperties.new(0.7, 0.35, 0.05, 1, 1),
	}
	-- The centre fuselage's parts weld straight to the core.
	local fus = Instance.new("Model")
	fus.Name = "Fuselage"
	fus:SetAttribute("Component", "Fuselage")
	fus.Parent = model
	ctx.comps.Fuselage = fus
	-- Ensure components exist in parent-first order.
	for _, name in { "ForwardFuselage", "AftFuselage", "LeftWing", "RightWing", "HorizontalStab", "VerticalStab", "LeftEngine", "RightEngine", "NoseGear", "LeftMainGear", "RightMainGear" } do
		if cfg.components[name] then
			getComponent(ctx, name)
		end
	end

	buildFuselage(ctx)
	buildWings(ctx)
	buildTail(ctx)
	buildEngines(ctx)
	buildGear(ctx)
	buildCockpit(ctx)

	return model
end

return AircraftBuilder
