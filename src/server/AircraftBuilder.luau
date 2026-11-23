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
local TriMath = require(Shared.TriMath)

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
local FORWARD = Vector3.new(0, 0, -1)

local function darker(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), k)
end

-- A smooth triangle from two WedgeParts (body metres). `opts.weldTo` welds the wedges to
-- that part (used for moving control surfaces); otherwise they weld to the component root.
local function tri(ctx: Ctx, comp: string, name: string, a: Vector3, b: Vector3, c: Vector3, thickness: number, color: Color3, opts: any?)
	local o = opts or {}
	local sol = TriMath.solve(a, b, c)
	if not sol then
		return
	end
	for _, w in sol do
		local cf = CFrame.fromMatrix(w.pos, w.right, w.up, w.back)
		local p = add(ctx, comp, name, "wedge", Vector3.new(thickness, w.height, w.length), cf, color, {
			hull = o.hull, material = o.material, transparency = o.transparency, tag = o.tag, noWeld = o.weldTo ~= nil,
		})
		if o.weldTo then
			weld(o.weldTo, p)
		end
	end
end

local function quad(ctx: Ctx, comp: string, name: string, p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3, thickness: number, color: Color3, opts: any?)
	tri(ctx, comp, name, p1, p2, p3, thickness, color, opts)
	tri(ctx, comp, name, p1, p3, p4, thickness, color, opts)
end

-- A cylinder from p0 to p1 (body metres).
local function rod(ctx: Ctx, comp: string, name: string, p0: Vector3, p1: Vector3, diameter: number, color: Color3, opts: any?): BasePart?
	local d = p1 - p0
	if d.Magnitude < 0.02 then
		return nil
	end
	local cf = CFrame.lookAt((p0 + p1) / 2, p1) * ALONG_Z
	return add(ctx, comp, name, "cylinder", Vector3.new(d.Magnitude, diameter, diameter), cf, color, opts)
end

-- A smooth ellipsoid: a block part with a SpecialMesh sphere, which Roblox stretches to
-- the part's size. `semi` holds the semi-axes in metres along the CFrame's own axes.
-- Collisions use the part's box, which is fine for the hull's purposes.
local function ellipsoid(ctx: Ctx, comp: string, name: string, cf: CFrame, semi: Vector3, color: Color3, opts: any?): BasePart
	local p = add(ctx, comp, name, "block", semi * 2, cf, color, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Elliptical cylinder along body Z: a block with a stretched SpecialMesh cylinder.
-- semi = (halfWidth, halfHeight); len is the full length.
local function ecylinder(ctx: Ctx, comp: string, name: string, pos: Vector3, len: number, halfW: number, halfH: number, color: Color3, opts: any?): BasePart
	local p = add(ctx, comp, name, "block", Vector3.new(len, halfH * 2, halfW * 2), CFrame.new(pos) * ALONG_Z, color, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Parent = p
	return p
end

-- Fuselage cross-section: a "stadium" (two circles of radius r whose centres are `deck`
-- apart vertically, joined by a block). deck = 0 is a plain circular barrel.
local function station(ctx: Ctx, comp: string, name: string, z0: number, z1: number, r: number, yc: number, deck: number, color: Color3, opts: any?)
	local len = math.abs(z1 - z0) + 0.04
	local zm = (z0 + z1) / 2
	if deck < 0.05 then
		add(ctx, comp, name, "cylinder", Vector3.new(len, r * 2, r * 2), CFrame.new(0, yc, zm) * ALONG_Z, color, opts)
		return
	end
	add(ctx, comp, name, "cylinder", Vector3.new(len, r * 2, r * 2), CFrame.new(0, yc - deck / 2, zm) * ALONG_Z, color, opts)
	add(ctx, comp, name, "cylinder", Vector3.new(len, r * 2, r * 2), CFrame.new(0, yc + deck / 2, zm) * ALONG_Z, color, opts)
	add(ctx, comp, name, "block", Vector3.new(r * 2 - 0.01, deck, len), CFrame.new(0, yc, zm), color, opts)
end

-- Row(s) of cabin windows and door outlines as a SurfaceGui on a transparent panel.
local function windowStrip(ctx: Ctx, comp: string, sx: number, z0: number, z1: number, x: number, y: number, pitch: number, doorsAt: { number }, tag: string?)
	local len = z1 - z0
	if len < 1 then
		return
	end
	local h = 0.62
	local p = add(ctx, comp, "WindowStrip", "block", Vector3.new(0.02, h, len), CFrame.new(sx * x, y, (z0 + z1) / 2), Color3.new(1, 1, 1), { transparency = 1, tag = tag })
	local gui = Instance.new("SurfaceGui")
	gui.Face = if sx > 0 then Enum.NormalId.Right else Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 1
	gui.Parent = p
	local n = math.floor(len / pitch)
	local winW = 0.26 / len
	for i = 0, n - 1 do
		local u = (i + 0.5) / n
		local zHere = z0 + u * len
		local skip = false
		for _, dz in doorsAt do
			if math.abs(zHere - dz) < 0.75 then
				skip = true
			end
		end
		if not skip then
			local f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			-- seen from outside, the gui's x axis runs tail->nose on the right face, nose->tail on the left
			f.Position = UDim2.fromScale(if sx > 0 then 1 - u else u, 0.42)
			f.Size = UDim2.fromScale(winW, 0.5)
			f.BackgroundColor3 = Color3.fromRGB(36, 44, 58)
			f.BorderSizePixel = 0
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = f
			f.Parent = gui
		end
	end
	for _, dz in doorsAt do
		local u = (dz - z0) / len
		if u > 0 and u < 1 then
			local f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale(if sx > 0 then 1 - u else u, 0.5)
			f.Size = UDim2.fromScale(0.95 / len, 1)
			f.BackgroundTransparency = 1
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(150, 156, 166)
			stroke.Thickness = 2
			stroke.Parent = f
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.15, 0)
			c.Parent = f
			f.Parent = gui
		end
	end
end

-- Fuselage -------------------------------------------------------------------------
local function buildFuselage(ctx: Ctx)
	local g = ctx.cfg.geometry.fuselage
	local liv = ctx.cfg.geometry.livery
	local body, stripe = rgb(liv.body), rgb(liv.stripe)
	local belly = rgb(liv.belly)
	local R = g.radius
	local deck = g.deck or 0
	local noseDrop = g.noseDrop or 0.35

	-- Cabin barrel in three structural sections.
	local sections = {
		{ "ForwardFuselage", g.cabinStartZ, g.forwardSplitZ },
		{ "Fuselage", g.forwardSplitZ, g.aftSplitZ },
		{ "AftFuselage", g.aftSplitZ, g.cabinEndZ },
	}
	for _, s in sections do
		local comp, z0, z1 = s[1], s[2], s[3]
		local hide = if comp == "ForwardFuselage" then "HideInCockpit" else nil
		station(ctx, comp, "Barrel", z0, z1, R, 0, deck, body, { hull = true, tag = hide })
		-- cheatline stripe and lower-body colour band
		local len = z1 - z0
		local mid = (z0 + z1) / 2
		local lowY = -deck / 2
		for _, sx in { -1, 1 } do
			add(ctx, comp, "Stripe", "block", Vector3.new(0.03, 0.2, len), CFrame.new(sx * (R + 0.005) * math.cos(math.rad(12)), lowY - R * math.sin(math.rad(12)), mid) * CFrame.Angles(0, 0, sx * math.rad(12)), stripe, { tag = hide })
		end
	end

	-- Windows (one row per deck) and doors.
	local rows = g.windowRows or { 0.55 }
	local doors = g.doors or { g.cabinStartZ + 1.2, g.cabinEndZ - 1.0 }
	for ri, y in rows do
		local yc = y + (if deck > 0 and ri == 2 then deck / 2 elseif deck > 0 then -deck / 2 else 0)
		local x = math.sqrt(math.max(0.01, R * R - (y * y))) + 0.005
		local z0 = if ri == 1 then g.cabinStartZ + 0.6 else (g.upperDeckStartZ or g.cabinStartZ + 0.6)
		local z1 = g.cabinEndZ - 0.4
		for _, sx in { -1, 1 } do
			-- split at the structural joints so each strip belongs to one component
			local cuts = { z0, g.forwardSplitZ, g.aftSplitZ, z1 }
			local comps = { "ForwardFuselage", "Fuselage", "AftFuselage" }
			for k = 1, 3 do
				local a, b = math.max(z0, cuts[k]), math.min(z1, cuts[k + 1])
				if b - a > 1 then
					windowStrip(ctx, comps[k], sx, a, b, x, yc, g.windowPitch or 0.53, if ri == 1 then doors else {}, if k == 1 then "HideInCockpit" else nil)
				end
			end
		end
	end

	-- Nose: one smooth half-ellipsoid, tipped down slightly so the chin sits lower than
	-- the crown. Its rear half hides inside the cabin barrel.
	local noseLen = g.cabinStartZ - g.noseZ
	local noseTilt = math.atan2(noseDrop, noseLen)
	ellipsoid(ctx, "ForwardFuselage", "Nose", CFrame.new(0, 0, g.cabinStartZ) * CFrame.Angles(noseTilt, 0, 0),
		Vector3.new(R, R + deck / 2, noseLen), body, { hull = true, tag = "HideInCockpit" })

	-- Cockpit windscreen: four panes sitting on the nose surface, tilted back.
	-- Default: on the main nose at fraction `at` of its length. `windscreen = { z, cy, r }`
	-- places them on another circle (for example the front of a jumbo's hump).
	local ws = g.windscreen or {}
	local wz, cy, wr
	if ws.z then
		wz, cy, wr = ws.z, ws.cy, ws.r
	else
		-- on the nose ellipsoid at fraction `at` of its length
		local tm = ws.at or 0.55
		wz = g.cabinStartZ - noseLen * tm
		local k = math.sqrt(1 - tm * tm)
		wr = R * k
		cy = -noseDrop * tm + (R + deck / 2) * k - wr
	end
	for _, sx in { -1, 1 } do
		for k = 1, 2 do
			local x = sx * (0.3 + (k - 1) * 0.58)
			local yRel = math.sqrt(math.max(0.01, wr * wr - x * x))
			local radial = Vector3.new(x, yRel, 0).Unit
			local n = (radial * math.cos(math.rad(38)) + FORWARD * math.sin(math.rad(38))).Unit
			local pos = Vector3.new(x, cy + yRel * 0.93, wz + (k - 1) * 0.3) + n * 0.02
			add(ctx, "ForwardFuselage", "Windscreen", "block", Vector3.new(0.52, 0.34, 0.04), CFrame.lookAt(pos, pos + n),
				Color3.fromRGB(22, 28, 38), { material = Enum.Material.Glass, reflectance = 0.25, tag = "HideInCockpit" })
		end
	end

	local function compAt(z: number): string
		return if z < g.forwardSplitZ then "ForwardFuselage" elseif z < g.aftSplitZ then "Fuselage" else "AftFuselage"
	end

	-- A smooth body of revolution-ish shape built from a chain of overlapping ellipsoids.
	-- prof(s) gives (centreY, halfWidth, halfHeight) at fraction s of [z0, z1]; each
	-- ellipsoid is two steps long so neighbours overlap and the seams barely show.
	local function chain(name: string, z0: number, z1: number, n: number, prof: (number) -> (number, number, number), opts: any?)
		local d = (z1 - z0) / (n + 3)
		for i = 1, n do
			local z = z0 + i * d
			local cyc, hw, hh = prof((z - z0) / (z1 - z0))
			ellipsoid(ctx, compAt(z), name, CFrame.new(0, cyc, z), Vector3.new(hw, hh, d * 3), body, opts)
		end
	end

	-- Upper-deck hump (jumbo style): an elliptical section sitting low in the barrel so it
	-- blends into the cabin sides, rounding into the nose at the front and the roof behind.
	if g.hump then
		local h = g.hump
		local topY = h.top
		local baseY = h.baseY or R * 0.45
		local hw = h.halfWidth or math.sqrt(R * R - baseY * baseY) * 0.93
		local hh = topY - baseY
		local flat0, flat1 = h.startZ + h.frontTaper, h.endZ - h.rearTaper
		ellipsoid(ctx, compAt(flat0), "HumpFront", CFrame.new(0, baseY, flat0), Vector3.new(hw, hh, h.frontTaper), body, { hull = true, tag = "HideInCockpit" })
		ellipsoid(ctx, compAt(flat1), "HumpRear", CFrame.new(0, baseY, flat1), Vector3.new(hw, hh, h.rearTaper), body, { hull = true })
		-- straight middle, split at the structural joints
		local cuts = { flat0, g.forwardSplitZ, g.aftSplitZ, flat1 }
		for k = 1, 3 do
			local a, b = math.max(flat0, cuts[k]), math.min(flat1, cuts[k + 1])
			if b - a > 0.2 then
				ecylinder(ctx, compAt(a + 0.01), "Hump", Vector3.new(0, baseY, (a + b) / 2), b - a + 0.04, hw, hh, body, { hull = true, tag = if a < g.forwardSplitZ then "HideInCockpit" else nil })
			end
		end
		-- upper-deck windows, on the flat part of the hump
		local wy = topY - hh * 0.32
		local wx = hw * math.sqrt(1 - ((wy - baseY) / hh) ^ 2) + 0.02
		for _, sx in { -1, 1 } do
			local cuts2 = { flat0 + 0.5, g.forwardSplitZ, g.aftSplitZ, flat1 }
			local comps = { "ForwardFuselage", "Fuselage", "AftFuselage" }
			for k = 1, 3 do
				local a, b = math.max(flat0 + 0.5, cuts2[k]), math.min(flat1, cuts2[k + 1])
				if b - a > 1 then
					windowStrip(ctx, comps[k], sx, a, b, wx, wy, g.windowPitch or 0.53, {}, if k == 1 then "HideInCockpit" else nil)
				end
			end
		end
	end

	-- Tail cone: the crown stays nearly level while the belly sweeps up to the tail tip.
	local H = R + deck / 2
	local tipY = g.tailUpsweep
	local tipR = R * 0.12
	chain("TailCone", g.cabinEndZ, g.tailEndZ, 10, function(s: number)
		local top = H - (H - (tipY + tipR)) * s ^ 1.8
		local bot = -H + (H + tipY - tipR) * s ^ 1.25
		local hw = R - (R - tipR) * s ^ 1.5
		return (top + bot) / 2, hw, (top - bot) / 2
	end, { hull = true })
	add(ctx, "AftFuselage", "APU", "cylinder", Vector3.new(0.5, tipR * 1.3, tipR * 1.3), CFrame.new(0, tipY, g.tailEndZ - 0.15) * ALONG_Z, Color3.fromRGB(110, 112, 118), { material = Enum.Material.Metal })
	-- Belly fairing under the wing root (a long, shallow bulge).
	local w = ctx.cfg.geometry.wing
	if (w.mount or "low") == "low" then
		local fz0, fz1 = w.rootLE[3] - 1.5, w.rootLE[3] + w.rootChord + 2.5
		local zc = (fz0 + fz1) / 2
		local comp = if zc < g.forwardSplitZ then "ForwardFuselage" elseif zc > g.aftSplitZ then "AftFuselage" else "Fuselage"
		ellipsoid(ctx, comp, "BellyFairing", CFrame.new(0, -deck / 2 - R * 0.72, zc), Vector3.new(R * 0.8, R * 0.42, (fz1 - fz0) / 2), belly, { hull = true })
	end

	-- High wing: a centre-section fairing over the cabin roof joining the two wing roots.
	if (w.mount or "low") == "high" then
		local wl = w.rootLE
		local th = w.rootThickness or w.thickness or 0.4
		add(ctx, "Fuselage", "WingCentreSection", "block", Vector3.new(wl[1] * 2 + 0.1, th + 0.35, w.rootChord), CFrame.new(0, wl[2] - 0.17, wl[3] + w.rootChord / 2), rgb(liv.wing), { hull = true })
	end

	-- Main-gear sponsons (high-wing aircraft keep the main gear in fuselage side pods).
	if g.sponsons then
		local sp = g.sponsons
		for _, sx in { -1, 1 } do
			ellipsoid(ctx, "Fuselage", "Sponson", CFrame.new(sx * sp.x, sp.y, (sp.z0 + sp.z1) / 2), Vector3.new(sp.r, sp.r, (sp.z1 - sp.z0) / 2 + sp.r), belly, { hull = true })
			add(ctx, "Fuselage", "SponsonFairing", "block", Vector3.new(sp.x - g.radius * 0.6, sp.r * 1.2, sp.z1 - sp.z0), CFrame.new(sx * (sp.x + g.radius * 0.6) / 2, sp.y + sp.r * 0.2, (sp.z0 + sp.z1) / 2), belly)
		end
	end

	-- Airline name (fictional) on both sides, via SurfaceGui on thin transparent panels.
	local titleY = R * 0.62 + deck / 2
	for _, sx in { -1, 1 } do
		local tx = math.sqrt(math.max(0.01, R * R - (R * 0.62) ^ 2)) + 0.02
		local p = add(ctx, "Fuselage", "Titles", "block", Vector3.new(0.02, R * 0.42, math.min(10, (g.aftSplitZ - g.forwardSplitZ) * 0.8)), CFrame.new(sx * tx, titleY, (g.forwardSplitZ + g.aftSplitZ) / 2 - 1), body, { transparency = 1 })
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
-- A moving control surface: an invisible hinge part on a Motor6D at the hinge line,
-- with the surface's wedges welded to it. The hinge frame keeps the old conventions:
-- X along the hinge (pointing to body +x, or up for the fin), Z aft, rotation about X.
local function hinge(ctx: Ctx, comp: string, kind: string, h0: Vector3, h1: Vector3, yAxis: Vector3?, side: number?): BasePart
	local mid = (h0 + h1) / 2
	local dir = (h1 - h0).Unit
	local up: Vector3
	if yAxis then
		up = yAxis
	else
		if dir.X < 0 then
			dir = -dir
		end
		up = dir:Cross(FORWARD).Unit
	end
	local cf = CFrame.fromMatrix(mid, dir, up)
	local anchor = add(ctx, comp, kind .. "Mount", "block", Vector3.new(0.1, 0.1, 0.1), cf, Color3.new(), { transparency = 1 })
	local moving = add(ctx, comp, kind .. "Hinge", "block", Vector3.new(0.1, 0.1, 0.1), cf, Color3.new(), { transparency = 1, noWeld = true })
	local m = Instance.new("Motor6D")
	m.Name = kind .. "Hinge"
	m.Part0 = anchor
	m.Part1 = moving
	m.C0 = CFrame.new()
	m.C1 = CFrame.new()
	m:SetAttribute("Surface", kind)
	if side then
		m:SetAttribute("Side", side)
	end
	m.Parent = anchor
	return moving
end

-- One half-wing or half-tailplane as true tapered, swept, dihedral trapezoids, split
-- spanwise at the flap/aileron breaks, with the control surfaces on hinges.
local function buildHalfSurface(ctx: Ctx, comp: string, spec: any, sx: number, color: Color3, surfaceKind: string)
	local rl = spec.rootLE
	local tanSweep = math.tan(math.rad(spec.sweepDeg))
	local tanDih = math.tan(math.rad(spec.dihedralDeg))
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
	local breaks: { number }
	if surfaceKind == "wing" then
		breaks = { 0, spec.flapEnd, spec.aileronStart, 0.97 }
	else
		breaks = { 0, 1 }
	end
	local cc = spec.controlChord
	local ctlColor = darker(color, 0.1)
	for k = 1, #breaks - 1 do
		local f0, f1 = breaks[k], breaks[k + 1]
		if f1 - f0 < 0.01 then
			continue
		end
		local s0, s1 = f0 * spec.span, f1 * spec.span
		local L0, L1 = le(s0), le(s1)
		local c0, c1 = chord(s0), chord(s1)
		local th = (thick(s0) + thick(s1)) / 2
		local aft = Vector3.new(0, 0, 1)
		local ctlKind: string? = nil
		if surfaceKind == "wing" then
			if k == 1 then
				ctlKind = "Flap"
			elseif k == 3 then
				ctlKind = "Aileron"
			end
		elseif surfaceKind == "hstab" then
			ctlKind = "Elevator"
		end
		local fixedFrac = if ctlKind then 1 - cc else 1
		local H0, H1 = L0 + aft * (c0 * fixedFrac), L1 + aft * (c1 * fixedFrac)
		quad(ctx, comp, "Skin", L0, L1, H1, H0, th, color, { hull = true })
		-- rounded leading edge
		rod(ctx, comp, "LeadingEdge", L0 + aft * (th * 0.45), L1 + aft * (th * 0.45), th * 0.95, color, { hull = true })
		if ctlKind then
			local T0, T1 = L0 + aft * c0, L1 + aft * c1
			local hp = hinge(ctx, comp, ctlKind, H0, H1, nil, sx)
			quad(ctx, comp, ctlKind, H0, H1, T1, T0, th * 0.6, ctlColor, { weldTo = hp })
		end
		if surfaceKind == "wing" and k == 1 then
			-- spoiler panels on the upper surface ahead of the flap
			local sa, sb = 0.55, 0.7
			local up = (L1 - L0):Cross(FORWARD).Unit * (if sx > 0 then 1 else -1)
			if up.Y < 0 then
				up = -up
			end
			local lift = up * (th / 2 + 0.03)
			local S0a, S1a = L0 + aft * (c0 * sa) + lift, L1 + aft * (c1 * sa) + lift
			local S0b, S1b = L0 + aft * (c0 * sb) + lift, L1 + aft * (c1 * sb) + lift
			local hp = hinge(ctx, comp, "Spoiler", S0a, S1a, nil, sx)
			quad(ctx, comp, "Spoiler", S0a, S1a, S1b, S0b, 0.05, darker(color, 0.2), { weldTo = hp })
		end
	end
	return le, chord, thick
end

local function buildWings(ctx: Ctx)
	local geo = ctx.cfg.geometry
	local liv = geo.livery
	local wingColor = rgb(liv.wing)
	for _, sx in { -1, 1 } do
		local comp = if sx < 0 then "LeftWing" else "RightWing"
		local w = geo.wing
		local le, chord, thick = buildHalfSurface(ctx, comp, w, sx, wingColor, "wing")
		local tip = le(w.span * 0.97)
		local tc = chord(w.span * 0.97)
		local tipEnd = le(w.span)
		-- tip cap
		quad(ctx, comp, "Skin", tip, tipEnd, tipEnd + Vector3.new(0, 0, chord(w.span)), tip + Vector3.new(0, 0, tc), thick(w.span), wingColor, { hull = true })
		-- winglet: a swept, tapered vertical trapezoid
		local wh = w.wingletHeight or 0
		if wh > 0.1 then
			local tcw = chord(w.span)
			local base0 = tipEnd + Vector3.new(0, 0, tcw * 0.15)
			local base1 = tipEnd + Vector3.new(0, 0, tcw * 0.95)
			local top1 = base1 + Vector3.new(sx * wh * 0.25, wh, wh * 0.3)
			local top0 = top1 - Vector3.new(0, 0, tcw * 0.4)
			quad(ctx, comp, "Winglet", base0, base1, top1, top0, 0.1, rgb(liv.tail), { hull = true })
		end
		-- navigation lights: red left, green right
		add(ctx, comp, "NavLight", "ball", Vector3.new(0.25, 0.25, 0.25), CFrame.new(tipEnd + Vector3.new(0, 0.05, 0.25)), if sx < 0 then Color3.fromRGB(255, 40, 40) else Color3.fromRGB(40, 255, 80), { material = Enum.Material.Neon })
	end
end

local function buildTail(ctx: Ctx)
	local geo = ctx.cfg.geometry
	local liv = geo.livery
	local tailColor = rgb(liv.tail)
	for _, sx in { -1, 1 } do
		buildHalfSurface(ctx, "HorizontalStab", geo.hstab, sx, rgb(liv.wing), "hstab")
	end
	-- Fin: one tapered, swept trapezoid with the rudder on a hinge.
	local v = geo.vstab
	local tanSweep = math.tan(math.rad(v.sweepDeg))
	local function le(h: number): Vector3
		return Vector3.new(0, v.rootLE[2] + h, v.rootLE[3] + h * tanSweep)
	end
	local function chord(h: number): number
		return v.rootChord + (v.tipChord - v.rootChord) * h / v.height
	end
	local aft = Vector3.new(0, 0, 1)
	local cc = v.controlChord
	local L0, L1 = le(0), le(v.height)
	local c0, c1 = chord(0), chord(v.height)
	local H0, H1 = L0 + aft * (c0 * (1 - cc)), L1 + aft * (c1 * (1 - cc))
	local T0, T1 = L0 + aft * c0, L1 + aft * c1
	quad(ctx, "VerticalStab", "Fin", L0, L1, H1, H0, v.thickness, tailColor, { hull = true })
	rod(ctx, "VerticalStab", "FinLeadingEdge", L0 + aft * (v.thickness * 0.45), L1 + aft * (v.thickness * 0.45), v.thickness * 0.95, tailColor, { hull = true })
	-- dorsal fillet blending the fin into the fuselage
	local fil0 = L0 + Vector3.new(0, -0.1, -c0 * 0.45)
	quad(ctx, "VerticalStab", "Fin", fil0, L0 + Vector3.new(0, v.height * 0.18, v.height * 0.18 * tanSweep), L0 + aft * (c0 * 0.3), L0, v.thickness * 0.8, tailColor, { hull = true })
	local hp = hinge(ctx, "VerticalStab", "Rudder", H0, H1, Vector3.new(-1, 0, 0), nil)
	quad(ctx, "VerticalStab", "Rudder", H0, H1, T1, T0, v.thickness * 0.65, darker(tailColor, 0.1), { weldTo = hp })
	-- tail logo: a fictional accent swoosh (two triangles)
	local accent = rgb(liv.accent)
	for _, sx in { -1, 1 } do
		local off = Vector3.new(sx * (v.thickness / 2 + 0.02), 0, 0)
		local a = le(v.height * 0.35) + aft * (chord(v.height * 0.35) * 0.15) + off
		local b = le(v.height * 0.75) + aft * (chord(v.height * 0.75) * 0.1) + off
		local c = le(v.height * 0.55) + aft * (chord(v.height * 0.55) * 0.6) + off
		tri(ctx, "VerticalStab", "TailLogo", a, b, c, 0.03, accent)
	end
	-- tail light and beacon
	add(ctx, "AftFuselage", "TailLight", "ball", Vector3.new(0.22, 0.22, 0.22), CFrame.new(0, geo.fuselage.tailUpsweep + 0.2, geo.fuselage.tailEndZ + 0.3), Color3.new(1, 1, 1), { material = Enum.Material.Neon })
	local topY = if geo.fuselage.hump then geo.fuselage.hump.top else geo.fuselage.radius + (geo.fuselage.deck or 0) / 2
	add(ctx, "Fuselage", "Beacon", "ball", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, topY + 0.1, 2), Color3.fromRGB(255, 30, 30), { material = Enum.Material.Neon, tag = "Beacon" })
end

local function buildEngines(ctx: Ctx)
	local geo = ctx.cfg.geometry
	local liv = geo.livery
	local eg = geo.engine
	local metal = Color3.fromRGB(190, 192, 198)
	for i, e in ctx.cfg.engines do
		local comp = e.component
		local p = v3(e.pos)
		local L, R = eg.length, eg.radius
		local front = p + Vector3.new(0, 0, -L / 2)
		local nac = rgb(liv.engine)
		local prop = eg.kind == "turboprop"
		-- nacelle body: lip, barrel, two tapering aft stations, exhaust
		local nacelle = add(ctx, comp, "Nacelle", "cylinder", Vector3.new(L * 0.55, R * 2, R * 2), CFrame.new(p + Vector3.new(0, 0, -L * 0.1)) * ALONG_Z, nac, { hull = true })
		if not prop then
			add(ctx, comp, "Intake", "cylinder", Vector3.new(0.3, R * 2.04, R * 2.04), CFrame.new(front + Vector3.new(0, 0, 0.15)) * ALONG_Z, metal, { material = Enum.Material.Metal })
			add(ctx, comp, "FanFace", "cylinder", Vector3.new(0.05, R * 1.75, R * 1.75), CFrame.new(front + Vector3.new(0, 0, 0.32)) * ALONG_Z, Color3.fromRGB(26, 28, 32))
		end
		ellipsoid(ctx, comp, "NacelleAft", CFrame.new(p + Vector3.new(0, 0, L * 0.17)), Vector3.new(R * 0.98, R * 0.98, L * 0.36), nac, { hull = true })
		add(ctx, comp, "Exhaust", "cylinder", Vector3.new(L * 0.14, R * 0.95, R * 0.95), CFrame.new(p + Vector3.new(0, 0, L * 0.52)) * ALONG_Z, Color3.fromRGB(110, 110, 118), { material = Enum.Material.Metal })
		add(ctx, comp, "ExhaustCone", "ball", Vector3.one * R * 0.7, CFrame.new(p + Vector3.new(0, 0, L * 0.6)), Color3.fromRGB(80, 80, 86), { material = Enum.Material.Metal })
		-- rotating fan or propeller: hub + blades on a Motor6D
		local hubZ = if prop then -0.35 else 0.36
		local hub = add(ctx, comp, "FanHub", "ball", Vector3.one * R * (if prop then 0.9 else 0.55), CFrame.new(front + Vector3.new(0, 0, hubZ)) * ALONG_Z, if prop then nac else metal, { noWeld = true })
		-- each blade part runs through the hub, so it makes two tips
		local bars = math.max(1, math.floor((if prop then (eg.blades or 6) else 8) / 2))
		local bladeLen = if prop then (eg.propRadius or 1.9) * 2 else R * 1.65
		for b = 0, bars - 1 do
			local ang = b * math.pi / bars
			local blade = add(ctx, comp, "FanBlade", "block", Vector3.new(if prop then 0.22 else 0.1, bladeLen, 0.04),
				CFrame.new(front + Vector3.new(0, 0, hubZ + 0.05)) * CFrame.Angles(0, 0, ang) * CFrame.Angles(0, math.rad(if prop then 18 else 30), 0),
				if prop then Color3.fromRGB(40, 40, 44) else Color3.fromRGB(70, 72, 80), { noWeld = true })
			weld(hub, blade)
		end
		local m = Instance.new("Motor6D")
		m.Name = "FanMotor"
		m.Part0 = nacelle
		m.Part1 = hub
		-- both frames have local +X pointing forward (body -Z); C0 is the hub position
		m.C0 = CFrame.new((L * 0.4 - hubZ) * S, 0, 0)
		m.C1 = CFrame.new()
		m:SetAttribute("EngineIndex", i)
		m.Parent = nacelle
		-- pylon: a swept, thin trapezoid up to the wing
		local w = geo.wing
		if (w.mount or "low") == "low" then
			local top = p + Vector3.new(0, R + 0.5, 0)
			quad(ctx, comp, "Pylon", p + Vector3.new(0, R * 0.7, -L * 0.15), p + Vector3.new(0, R * 0.7, L * 0.42), top + Vector3.new(0, 0, L * 0.55), top + Vector3.new(0, 0, L * 0.05), 0.3, nac, { hull = true })
		else
			-- high wing: the nacelle hangs under the wing on a short fairing
			add(ctx, comp, "Pylon", "block", Vector3.new(R * 1.2, 0.6, L * 0.6), CFrame.new(p + Vector3.new(0, R * 0.85, L * 0.05)), nac, { hull = true })
		end
		-- smoke emitter (enabled by the client when the engine is failed/on fire)
		local att = Instance.new("Attachment")
		att.Name = "SmokeAttachment"
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
		local leg = add(ctx, comp, "Leg", "cylinder", Vector3.new(L, 0.26, 0.26), CFrame.new(attach - Vector3.new(0, L / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), strutColor, { noWeld = true, material = Enum.Material.Metal })
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
		-- wheels: rows x across, axis along body X, on a bogie beam when there are two rows
		local n = u.wheels or 2
		local rows = u.rows or 1
		local rowSpacing = u.rowSpacing or 1.4
		local wr = u.wheelRadius
		for row = 1, rows do
			local dz = (row - (rows + 1) / 2) * rowSpacing
			for w = 1, n do
				local off = (w - (n + 1) / 2) * (u.wheelSpacing or 0.6)
				local c = attach + Vector3.new(off, -L, dz)
				local wheel = add(ctx, comp, "Wheel", "cylinder", Vector3.new(wr * 0.62, wr * 2, wr * 2), CFrame.new(c), tire, { noWeld = true })
				weld(leg, wheel)
				local hubcap = add(ctx, comp, "Hub", "cylinder", Vector3.new(wr * 0.66, wr * 1.05, wr * 1.05), CFrame.new(c), strutColor, { noWeld = true, material = Enum.Material.Metal })
				weld(leg, hubcap)
			end
			if n > 1 then
				local axle = add(ctx, comp, "Axle", "cylinder", Vector3.new((n - 1) * (u.wheelSpacing or 0.6), 0.14, 0.14), CFrame.new(attach + Vector3.new(0, -L, dz)), strutColor, { noWeld = true })
				weld(leg, axle)
			end
		end
		if rows > 1 then
			local beam = add(ctx, comp, "Bogie", "block", Vector3.new(0.22, 0.22, rowSpacing * (rows - 1) + 0.3), CFrame.new(attach + Vector3.new(0, -L, 0)), strutColor, { noWeld = true, material = Enum.Material.Metal })
			weld(leg, beam)
		end
		-- gear door
		local door = add(ctx, comp, "GearDoor", "block", Vector3.new(0.05, L * 0.6, wr * 1.6), CFrame.new(attach + Vector3.new(if attach.X < 0 then -0.25 elseif attach.X > 0 then 0.25 else 0.3, -L * 0.35, 0)), rgb(ctx.cfg.geometry.livery.belly), { noWeld = true })
		weld(leg, door)
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
	-- (getComponent creates a component's parent first, so any order works; sort for
	-- a deterministic model tree.)
	local names = {}
	for name in cfg.components do
		if name ~= "Fuselage" then
			table.insert(names, name)
		end
	end
	table.sort(names)
	for _, name in names do
		getComponent(ctx, name)
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
