--!strict
-- Parametric aircraft builder. Turns an aircraft config's `geometry` block into a
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
--
-- Everything is driven by data in the config, so a new aircraft needs no code here:
--   fuselage.halfWidth   elliptical body (fighters); otherwise round (or stadium with deck)
--   fuselage.windscreen  airliner flight-deck glazing on the nose (or hump) surface
--   fuselage.canopy      bubble canopy (fighters, aerobatic) with frame bows and a pilot
--   fuselage.cabin       light-aircraft glazing: sloped windscreen and side windows
--   fuselage.intakes     fighter air intakes on the body sides
--   engine.kind          "turbofan" | "turboprop" | "piston" (nose propeller) | "jet" (buried)
--   engine.mount         "wing" (default) | "fuselage" (rear-mounted, bizjet)
--   wing.spoilers/strut/strake, vstab.count/spacing/cantDeg, floats, cockpit.style
--   fuselage.boatHull    flying-boat V bottom, step, spray rails, tank doors, scoop probes
-- Parts tagged HideInCockpit vanish in the cockpit view; CockpitOnly parts appear there,
-- at their CockpitTransparency attribute (glass) or fully opaque.

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
	if o.noShadow then
		p.CastShadow = false
	end
	if o.tag then
		p:SetAttribute(o.tag, true)
	end
	if o.attrs then
		for k, v in o.attrs do
			p:SetAttribute(k, v)
		end
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
			hull = o.hull, material = o.material, transparency = o.transparency, reflectance = o.reflectance,
			tag = o.tag, attrs = o.attrs, noShadow = o.noShadow, noWeld = o.weldTo ~= nil,
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
	-- (a vertical rod needs another "up" hint, or lookAt has no defined roll)
	local upHint = if math.abs(d.Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	local cf = CFrame.lookAt((p0 + p1) / 2, p1, upHint) * ALONG_Z
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
local function windowStrip(ctx: Ctx, comp: string, sx: number, z0: number, z1: number, x: number, y: number, pitch: number, doorsAt: { number }, tag: string?, winWidth: number?, winHeight: number?)
	local len = z1 - z0
	if len < 1 then
		return
	end
	local h = winHeight or 0.62
	local p = add(ctx, comp, "WindowStrip", "block", Vector3.new(0.02, h, len), CFrame.new(sx * x, y, (z0 + z1) / 2), Color3.new(1, 1, 1), { transparency = 1, tag = tag })
	local gui = Instance.new("SurfaceGui")
	gui.Face = if sx > 0 then Enum.NormalId.Right else Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 1
	gui.Parent = p
	local n = math.floor(len / pitch)
	local winW = (winWidth or 0.26) / len
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

-- Shared looks ------------------------------------------------------------------------
local GLASS = Color3.fromRGB(64, 92, 118)
local FRAME_BLACK = Color3.fromRGB(26, 28, 32)
local METAL = Color3.fromRGB(196, 199, 205)
local DARK_METAL = Color3.fromRGB(78, 80, 88)
local HOT_METAL = Color3.fromRGB(122, 108, 96)
local FAN = Color3.fromRGB(112, 116, 126)
local INTAKE_DARK = Color3.fromRGB(30, 32, 36)

-- Outside glass: tinted, reflective and see-through. Hidden from the cockpit camera,
-- where the CockpitOnly copies take over.
local function glassOpts(extra: any?): any
	local o = { material = Enum.Material.Glass, transparency = 0.3, reflectance = 0.22, tag = "HideInCockpit", noShadow = true }
	if extra then
		for k, v in extra do
			o[k] = v
		end
	end
	return o
end

-- Inside glass: only shown in the cockpit view, mostly clear (CameraController reads
-- CockpitTransparency instead of making CockpitOnly parts opaque).
local function cockpitGlassOpts(): any
	return { material = Enum.Material.Glass, transparency = 1, reflectance = 0.08, tag = "CockpitOnly", noShadow = true, attrs = { CockpitTransparency = 0.86 } }
end


-- A point on an ellipsoid (centred at `cf`, semi-axes `semi` along cf's axes), `lift` metres
-- outward, at local height `y`, going around the horizontal ring at
-- that height: `psi` 0 is straight ahead (-Z), 90 deg is the +X side.
local function ellRingPoint(cf: CFrame, semi: Vector3, y: number, psi: number, lift: number): Vector3
	local m = math.sqrt(math.max(0.0025, 1 - (y / semi.Y) ^ 2))
	local l = Vector3.new(semi.X * m * math.sin(psi), y, -semi.Z * m * math.cos(psi))
	local n = Vector3.new(l.X / (semi.X * semi.X), l.Y / (semi.Y * semi.Y), l.Z / (semi.Z * semi.Z))
	return cf * (l + n.Unit * lift)
end

-- A rounded arch of rods over an ellipse cross-section (canopy frame bows).
local function arch(ctx: Ctx, comp: string, name: string, centre: Vector3, halfW: number, halfH: number, fromDeg: number, toDeg: number, n: number, d: number, color: Color3, opts: any?)
	local prev: Vector3? = nil
	for i = 0, n do
		local a = math.rad(fromDeg + (toDeg - fromDeg) * i / n)
		local pt = centre + Vector3.new(halfW * math.sin(a), halfH * math.cos(a), 0)
		if prev then
			rod(ctx, comp, name, prev, pt, d, color, opts)
		end
		prev = pt
	end
end

-- Body cross-section half-width / half-height (elliptical bodies for fighters).
local function bodyHalf(g: any): (number, number)
	return g.halfWidth or g.radius, g.radius + (g.deck or 0) / 2
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
	local HW, H = bodyHalf(g)
	local cockpitStyle = (ctx.cfg.geometry.cockpit or {}).style or "airliner"
	-- the nose barrel is hidden from the cockpit camera unless the pilot sits up in a canopy
	local hideFwd = if g.canopy then nil else "HideInCockpit"

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

	-- Cabin barrel in three structural sections.
	local sections = {
		{ "ForwardFuselage", g.cabinStartZ, g.forwardSplitZ },
		{ "Fuselage", g.forwardSplitZ, g.aftSplitZ },
		{ "AftFuselage", g.aftSplitZ, g.cabinEndZ },
	}
	for _, s in sections do
		local comp, z0, z1 = s[1], s[2], s[3]
		local hide = if comp == "ForwardFuselage" then hideFwd else nil
		if g.halfWidth then
			ecylinder(ctx, comp, "Barrel", Vector3.new(0, 0, (z0 + z1) / 2), math.abs(z1 - z0) + 0.04, HW, H, body, { hull = true, tag = hide })
		else
			station(ctx, comp, "Barrel", z0, z1, R, 0, deck, body, { hull = true, tag = hide })
		end
		-- cheatline stripe
		if g.stripe ~= false then
			local len = z1 - z0
			local mid = (z0 + z1) / 2
			local lowY = -deck / 2
			for _, sx in { -1, 1 } do
				add(ctx, comp, "Stripe", "block", Vector3.new(0.03, math.min(0.2, R * 0.12), len), CFrame.new(sx * (HW + 0.005) * math.cos(math.rad(12)), lowY - R * math.sin(math.rad(12)), mid) * CFrame.Angles(0, 0, sx * math.rad(12)), stripe, { tag = hide })
			end
		end
	end

	-- Windows (one row per deck) and doors.
	local rows = g.windowRows or { 0.55 }
	local doors = g.doors or { g.cabinStartZ + 1.2, g.cabinEndZ - 1.0 }
	for ri, y in rows do
		local yc = y + (if deck > 0 and ri == 2 then deck / 2 elseif deck > 0 then -deck / 2 else 0)
		local x = math.sqrt(math.max(0.01, R * R - (y * y))) + 0.005
		local z0 = if ri == 1 then (g.windowStartZ or g.cabinStartZ + 0.6) else (g.upperDeckStartZ or g.cabinStartZ + 0.6)
		local z1 = g.windowEndZ or g.cabinEndZ - 0.4
		for _, sx in { -1, 1 } do
			-- split at the structural joints so each strip belongs to one component
			local cuts = { z0, g.forwardSplitZ, g.aftSplitZ, z1 }
			local comps = { "ForwardFuselage", "Fuselage", "AftFuselage" }
			for k = 1, 3 do
				local a, b = math.max(z0, cuts[k]), math.min(z1, cuts[k + 1])
				if b - a > 1 then
					windowStrip(ctx, comps[k], sx, a, b, x, yc, g.windowPitch or 0.53, if ri == 1 then doors else {}, if k == 1 then hideFwd else nil, g.windowWidth, g.windowHeight)
				end
			end
		end
	end

	-- Nose: one smooth half-ellipsoid, tipped down slightly so the chin sits lower than
	-- the crown. Its rear half hides inside the cabin barrel.
	local noseLen = g.cabinStartZ - g.noseZ
	local noseTilt = math.atan2(noseDrop, noseLen)
	local noseCF = CFrame.new(0, 0, g.cabinStartZ) * CFrame.Angles(noseTilt, 0, 0)
	local noseSemi = Vector3.new(HW, H, noseLen)
	ellipsoid(ctx, "ForwardFuselage", "Nose", noseCF, noseSemi, body, { hull = true, tag = hideFwd })
	if g.noseColor then
		-- radome / spinner-coloured tip
		local rz = noseLen * 0.45
		ellipsoid(ctx, "ForwardFuselage", "Radome", noseCF * CFrame.new(0, 0, -noseLen + rz), Vector3.new(HW * 0.7, H * 0.7, rz), rgb(g.noseColor), { hull = true, tag = hideFwd })
	end
	if g.pitot then
		local tip = noseCF * Vector3.new(0, 0, -noseLen)
		rod(ctx, "ForwardFuselage", "Pitot", tip + Vector3.new(0, 0, 0.1), tip + Vector3.new(0, 0, -g.pitot), 0.05, DARK_METAL, { material = Enum.Material.Metal, tag = hideFwd })
	end

	-- Flight-deck glazing (airliners): a black surround with separate tinted panes that
	-- follow the curved nose (or the front of a jumbo's hump). Pane edges sit at fixed
	-- heights (ws.yLow / ws.yHigh, in the surface's own frame), so every pane meets the
	-- surface at the right place whatever the nose shape.
	local ws = g.windscreen
	if ws ~= false and not g.canopy and not (g.cabin and g.cabin.windscreen) then
		ws = ws or {}
		local cf, semi = noseCF, noseSemi
		if ws.surface == "hump" and g.hump then
			local h = g.hump
			local baseY = h.baseY or R * 0.45
			local hw = h.halfWidth or math.sqrt(R * R - baseY * baseY) * 0.93
			cf = CFrame.new(0, baseY, h.startZ + h.frontTaper)
			semi = Vector3.new(hw, h.top - baseY, h.frontTaper)
		end
		local eye = v3(ctx.cfg.cameras.cockpit)
		local eyeLocal = cf:PointToObjectSpace(eye)
		local yLow = ws.yLow or (eyeLocal.Y - 0.05)
		local yHigh = math.min(ws.yHigh or (eyeLocal.Y + 0.55), semi.Y * 0.93)
		-- pane boundaries around from the top, degrees: front, side, rear side
		-- pane boundaries around the nose (degrees from straight ahead): front, side, rear side
		local edges = ws.panes or { 2, 30, 56, 78 }
		local function pt(psiDeg: number, y: number, lift: number): Vector3
			return ellRingPoint(cf, semi, y, math.rad(psiDeg), lift)
		end
		local yF0, yF1 = yLow - 0.1, yHigh + 0.08
		for _, sx in { -1, 1 } do
			-- black surround, slightly bigger than the glass
			local n = 6
			local e0, e1 = 0, edges[#edges] + 3
			local yM = (yF0 + yF1) / 2
			for i = 0, n - 1 do
				local a = sx * (e0 + (e1 - e0) * i / n)
				local b = sx * (e0 + (e1 - e0) * (i + 1) / n)
				for _, band in { { yF0, yM }, { yM, yF1 } } do
					quad(ctx, "ForwardFuselage", "WindscreenFrame", pt(a, band[1], 0.05), pt(b, band[1], 0.05), pt(b, band[2], 0.05), pt(a, band[2], 0.05), 0.05, FRAME_BLACK, { tag = "HideInCockpit" })
				end
			end
			-- panes, each split in two so they hug the curve; the rear side pane is shorter
			for k = 1, #edges - 1 do
				local a0, a1 = edges[k] + 1.5, edges[k + 1] - 1.5
				local top = if k == #edges - 1 then yHigh - (yHigh - yLow) * 0.3 else yHigh
				for j = 0, 1 do
					local a = sx * (a0 + (a1 - a0) * j / 2)
					local b = sx * (a0 + (a1 - a0) * (j + 1) / 2)
					quad(ctx, "ForwardFuselage", "Windscreen", pt(a, yLow, 0.088), pt(b, yLow, 0.088), pt(b, top, 0.088), pt(a, top, 0.088), 0.03, GLASS, glassOpts())
				end
			end
			-- wiper on the front pane
			rod(ctx, "ForwardFuselage", "Wiper", pt(sx * (edges[1] + 8), yLow + 0.03, 0.09), pt(sx * (edges[1] + 16), yLow + (yHigh - yLow) * 0.6, 0.09), 0.035, FRAME_BLACK, { tag = "HideInCockpit" })
		end
	end

	-- Bubble canopy (fighters, aerobatic): tinted glass shell, frame bows, sill rails and
	-- a pilot inside. The pilot and outer glass vanish in the cockpit view.
	if g.canopy then
		local c = g.canopy
		local zc = (c.z0 + c.z1) / 2
		local comp = compAt(zc)
		local semi = Vector3.new(c.halfWidth, c.height, (c.z1 - c.z0) / 2)
		local ccf = CFrame.new(0, c.y, zc)
		ellipsoid(ctx, comp, "Canopy", ccf, semi, if c.tint then rgb(c.tint) else GLASS, glassOpts({ transparency = c.transparency or 0.35 }))
		local inner = cockpitGlassOpts()
		ellipsoid(ctx, comp, "CanopyInner", ccf, semi * 0.985, GLASS, inner)
		local frameColor = if c.frameColor then rgb(c.frameColor) else FRAME_BLACK
		for _, fz in c.frames or {} do
			local u = (zc - fz) / semi.Z
			local k = math.sqrt(math.max(0.02, 1 - u * u))
			arch(ctx, comp, "CanopyFrame", Vector3.new(0, c.y, fz), semi.X * k + 0.02, semi.Y * k + 0.02, -88, 88, 8, 0.07, frameColor, {})
		end
		-- sill rails along the canopy base
		for _, sx in { -1, 1 } do
			rod(ctx, comp, "CanopyRail", Vector3.new(sx * semi.X * 0.97, c.y + 0.02, c.z0 + semi.Z * 0.25), Vector3.new(sx * semi.X * 0.97, c.y + 0.02, c.z1 - semi.Z * 0.25), 0.07, frameColor, {})
		end
		-- pilot(s): helmet, visor and shoulders at each seat
		for _, seat in c.pilots or { ctx.cfg.cameras.cockpit } do
			local e = v3(seat)
			local helmetColor = if c.helmet then rgb(c.helmet) else Color3.fromRGB(240, 240, 244)
			add(ctx, comp, "PilotHelmet", "ball", Vector3.one * 0.3, CFrame.new(e + Vector3.new(0, 0.02, 0.05)), helmetColor, { tag = "HideInCockpit" })
			add(ctx, comp, "PilotVisor", "block", Vector3.new(0.22, 0.09, 0.05), CFrame.new(e + Vector3.new(0, 0.0, -0.1)), FRAME_BLACK, { tag = "HideInCockpit", material = Enum.Material.Glass, reflectance = 0.4 })
			ellipsoid(ctx, comp, "PilotBody", CFrame.new(e + Vector3.new(0, -0.38, 0.1)), Vector3.new(0.22, 0.25, 0.14), Color3.fromRGB(60, 90, 70), { tag = "HideInCockpit" })
			add(ctx, comp, "Headrest", "block", Vector3.new(0.3, 0.32, 0.1), CFrame.new(e + Vector3.new(0, -0.05, 0.3)), FRAME_BLACK, { tag = "HideInCockpit" })
		end
	end

	-- Light-aircraft cabin glazing: a sloped windscreen and flat side windows over the
	-- solid cabin. The cockpit view swaps them for the interior glass.
	if g.cabin then
		local cb = g.cabin
		local w = cb.windscreen or false
		if w then
		local hwB, hwT = w.halfWidth, w.topHalfWidth or w.halfWidth * 0.85
		local b0, b1 = Vector3.new(-hwB, w.yBottom, w.zBottom), Vector3.new(hwB, w.yBottom, w.zBottom)
		local t0, t1 = Vector3.new(-hwT, w.yTop, w.zTop), Vector3.new(hwT, w.yTop, w.zTop)
		quad(ctx, "ForwardFuselage", "WindscreenFrame", b0 + Vector3.new(-0.04, -0.05, -0.02), b1 + Vector3.new(0.04, -0.05, -0.02), t1 + Vector3.new(0.04, 0.02, 0), t0 + Vector3.new(-0.04, 0.02, 0), 0.05, FRAME_BLACK, { tag = "HideInCockpit" })
		local mid0, mid1 = (b0 + b1) / 2, (t0 + t1) / 2
		local off = (t0 - b0):Cross(b1 - b0).Unit
		if off.Y < 0 then
			off = -off
		end
		for _, side in { { b0, mid0, mid1, t0 }, { mid0, b1, t1, mid1 } } do
			quad(ctx, "ForwardFuselage", "Windscreen", side[1] + off * 0.04, side[2] + off * 0.04, side[3] + off * 0.04, side[4] + off * 0.04, 0.03, GLASS, glassOpts())
		end
		rod(ctx, "ForwardFuselage", "WindscreenPost", mid0 + off * 0.06, mid1 + off * 0.06, 0.05, FRAME_BLACK, { tag = "HideInCockpit" })
		end
		for _, sw in cb.sideWindows or {} do
			for _, sx in { -1, 1 } do
				local z0, z1, y0, y1 = sw[1], sw[2], sw[3], sw[4]
				local x = HW + 0.03
				local comp = compAt((z0 + z1) / 2)
				add(ctx, comp, "SideWindowFrame", "block", Vector3.new(0.03, y1 - y0 + 0.1, z1 - z0 + 0.1), CFrame.new(sx * (x - 0.005), (y0 + y1) / 2, (z0 + z1) / 2), FRAME_BLACK, { tag = "HideInCockpit" })
				add(ctx, comp, "SideWindow", "block", Vector3.new(0.03, y1 - y0, z1 - z0), CFrame.new(sx * (x + 0.02), (y0 + y1) / 2, (z0 + z1) / 2), GLASS, glassOpts())
			end
		end
	end

	-- Fighter air intakes: a box on each side (or one under the chin) with a dark duct
	-- face, a lip and a splitter plate standing off the fuselage.
	for _, it in g.intakes or {} do
		local sides = if (it.x or 0) == 0 then { 0 } else { -1, 1 }
		for _, sx in sides do
			local x = if sx == 0 then 0 else sx * it.x
			local len = it.z1 - it.z0
			local zc = (it.z0 + it.z1) / 2
			local comp = compAt(zc)
			ellipsoid(ctx, comp, "IntakeDuct", CFrame.new(x, it.y, zc + len * 0.1), Vector3.new(it.w / 2, it.h / 2, len * 0.62), body, { hull = true })
			add(ctx, comp, "Intake", "block", Vector3.new(it.w, it.h, len * 0.45), CFrame.new(x, it.y, it.z0 + len * 0.225), body, { hull = true })
			add(ctx, comp, "IntakeLip", "block", Vector3.new(it.w + 0.06, it.h + 0.06, 0.08), CFrame.new(x, it.y, it.z0 + 0.02), darker(body, 0.25), { material = Enum.Material.Metal })
			add(ctx, comp, "IntakeMouth", "block", Vector3.new(it.w * 0.84, it.h * 0.8, 0.06), CFrame.new(x, it.y, it.z0 - 0.02), INTAKE_DARK)
			if sx ~= 0 then
				add(ctx, comp, "Splitter", "block", Vector3.new(0.04, it.h * 0.9, len * 0.3), CFrame.new(x - sx * (it.w / 2 + 0.06), it.y, it.z0 + len * 0.12), darker(body, 0.1))
			end
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
	local tipY = g.tailUpsweep
	local tipR = R * (g.tailTipFraction or 0.12)
	chain("TailCone", g.cabinEndZ, g.tailEndZ, 10, function(s: number)
		local top = H - (H - (tipY + tipR)) * s ^ 1.8
		local bot = -H + (H + tipY - tipR) * s ^ 1.25
		local hw = HW - (HW - tipR) * s ^ 1.5
		return (top + bot) / 2, hw, (top - bot) / 2
	end, { hull = true })
	if g.apu ~= false and cockpitStyle == "airliner" then
		add(ctx, "AftFuselage", "APU", "cylinder", Vector3.new(0.5, tipR * 1.3, tipR * 1.3), CFrame.new(0, tipY, g.tailEndZ - 0.15) * ALONG_Z, Color3.fromRGB(110, 112, 118), { material = Enum.Material.Metal })
	end
	-- Belly fairing under the wing root (a long, shallow bulge).
	local w = ctx.cfg.geometry.wing
	local mount = w.mount or "low"
	if mount == "low" and g.bellyFairing ~= false then
		local fz0, fz1 = w.rootLE[3] - 1.5, w.rootLE[3] + w.rootChord + 2.5
		local zc = (fz0 + fz1) / 2
		ellipsoid(ctx, compAt(zc), "BellyFairing", CFrame.new(0, -deck / 2 - R * 0.72, zc), Vector3.new(R * 0.8, R * 0.42, (fz1 - fz0) / 2), belly, { hull = true })
	end

	-- High wing: a centre-section fairing over the cabin roof joining the two wing roots.
	if mount == "high" then
		local wl = w.rootLE
		local th = w.rootThickness or w.thickness or 0.4
		add(ctx, "Fuselage", "WingCentreSection", "block", Vector3.new(wl[1] * 2 + 0.1, th + 0.35 * math.min(1, R), w.rootChord), CFrame.new(0, wl[2] - 0.17 * math.min(1, R), wl[3] + w.rootChord / 2), rgb(liv.wing), { hull = true })
	end

	-- Boat hull (flying boats): a V bottom from the bow to the planing step, a flatter
	-- afterbody rising to the tail, spray rails on the chines, tank doors and scoop probes.
	if g.boatHull then
		local bh = g.boatHull
		local hullColor = belly
		local function keelAt(z: number): number
			if z <= bh.stepZ then
				local t = math.clamp((z - bh.bowZ) / 2.8, 0, 1)
				return bh.keelY + (bh.chineY - bh.keelY) * (1 - t) ^ 2 * 0.85
			end
			local t = math.clamp((z - bh.stepZ) / (bh.tailZ - bh.stepZ), 0, 1)
			return bh.keelY + 0.18 + (bh.chineY - bh.keelY - 0.25) * t
		end
		local function chineXAt(z: number): number
			local t = math.clamp((z - bh.bowZ) / 3.2, 0, 1)
			local tailT = math.clamp((z - bh.stepZ) / (bh.tailZ - bh.stepZ), 0, 1)
			return bh.chineX * (0.35 + 0.65 * math.sqrt(t)) * (1 - 0.55 * tailT)
		end
		local function chineYAt(z: number): number
			local tailT = math.clamp((z - bh.stepZ) / (bh.tailZ - bh.stepZ), 0, 1)
			return bh.chineY + tailT * 0.25
		end
		-- stations: dense near the bow, split at the structural joints and the step
		local zs = { bh.bowZ, bh.bowZ + 0.6, bh.bowZ + 1.3, bh.bowZ + 2.2, bh.bowZ + 3.2 }
		for _, z in { g.forwardSplitZ, bh.stepZ - 0.001, bh.stepZ + 0.001, g.aftSplitZ, (g.aftSplitZ + bh.tailZ) / 2, bh.tailZ } do
			if z > zs[#zs] + 0.05 then
				table.insert(zs, z)
			end
		end
		for k = 1, #zs - 1 do
			local za, zb = zs[k], zs[k + 1]
			if zb - za < 0.01 then
				continue
			end
			local comp = compAt((za + zb) / 2)
			local ka, kb = Vector3.new(0, keelAt(za), za), Vector3.new(0, keelAt(zb), zb)
			for _, sx in { -1, 1 } do
				local ca = Vector3.new(sx * chineXAt(za), chineYAt(za), za)
				local cb = Vector3.new(sx * chineXAt(zb), chineYAt(zb), zb)
				quad(ctx, comp, "HullBottom", ca, ka, kb, cb, 0.06, hullColor, { hull = true })
			end
		end
		-- the step: a squared-off drop in the bottom just behind the tank
		local cx = chineXAt(bh.stepZ)
		add(ctx, "Fuselage", "HullStep", "block", Vector3.new(cx * 2, 0.2, 0.1), CFrame.new(0, keelAt(bh.stepZ + 0.01) - 0.05, bh.stepZ), darker(hullColor, 0.3))
		-- spray rails along the forward chines
		for _, sx in { -1, 1 } do
			local z0, z1 = bh.bowZ + 0.8, g.forwardSplitZ - 0.05
			rod(ctx, "ForwardFuselage", "SprayRail", Vector3.new(sx * (chineXAt(z0) + 0.04), chineYAt(z0), z0), Vector3.new(sx * (chineXAt(z1) + 0.04), chineYAt(z1), z1), 0.09, darker(hullColor, 0.2))
			rod(ctx, "Fuselage", "SprayRail", Vector3.new(sx * (chineXAt(g.forwardSplitZ) + 0.04), chineYAt(g.forwardSplitZ), g.forwardSplitZ), Vector3.new(sx * (chineXAt(bh.stepZ) + 0.04), chineYAt(bh.stepZ), bh.stepZ), 0.09, darker(hullColor, 0.2))
		end
		-- water tank doors (one each side of the keel) and the two scoop probes
		if bh.doors then
			local z0, z1 = bh.doors[1], bh.doors[2]
			local zc = (z0 + z1) / 2
			local kY = keelAt(zc)
			local slope = math.atan2(chineYAt(zc) - kY, chineXAt(zc))
			for _, sx in { -1, 1 } do
				local w = chineXAt(zc) * 0.55
				add(ctx, "Fuselage", "TankDoor", "block", Vector3.new(w, 0.03, z1 - z0), CFrame.new(sx * w * 0.6, kY + math.tan(slope) * w * 0.6 - 0.02, zc) * CFrame.Angles(0, 0, sx * slope), DARK_METAL, { attrs = { TankDoorSide = sx } })
			end
		end
		if bh.probesZ then
			for _, sx in { -1, 1 } do
				local top = Vector3.new(sx * 0.35, keelAt(bh.probesZ) + 0.25, bh.probesZ)
				rod(ctx, "Fuselage", "ScoopProbe", top, top + Vector3.new(0, -0.45, 0.25), 0.12, DARK_METAL)
			end
		end
	end

	-- Main-gear sponsons (high-wing aircraft keep the main gear in fuselage side pods).
	if g.sponsons then
		local sp = g.sponsons
		for _, sx in { -1, 1 } do
			ellipsoid(ctx, "Fuselage", "Sponson", CFrame.new(sx * sp.x, sp.y, (sp.z0 + sp.z1) / 2), Vector3.new(sp.r, sp.r, (sp.z1 - sp.z0) / 2 + sp.r), belly, { hull = true })
			add(ctx, "Fuselage", "SponsonFairing", "block", Vector3.new(sp.x - g.radius * 0.6, sp.r * 1.2, sp.z1 - sp.z0), CFrame.new(sx * (sp.x + g.radius * 0.6) / 2, sp.y + sp.r * 0.2, (sp.z0 + sp.z1) / 2), belly)
		end
	end

	-- Dorsal spine (fighters): a long low ridge from the canopy to the fin.
	if g.spine then
		local sp = g.spine
		ellipsoid(ctx, compAt((sp.z0 + sp.z1) / 2), "Spine", CFrame.new(0, sp.y, (sp.z0 + sp.z1) / 2), Vector3.new(sp.halfWidth, sp.height, (sp.z1 - sp.z0) / 2), body, { hull = true })
	end

	-- Airline name (fictional) on both sides, via SurfaceGui on thin transparent panels.
	if liv.airline then
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
	-- Registration-style code on small aircraft (fictional).
	if liv.code then
		for _, sx in { -1, 1 } do
			local zc = (g.aftSplitZ + g.cabinEndZ) / 2
			local p = add(ctx, compAt(zc), "Code", "block", Vector3.new(0.02, H * 0.6, math.max(1.2, H * 2.6)), CFrame.new(sx * (HW + 0.02), 0, zc), body, { transparency = 1 })
			local gui = Instance.new("SurfaceGui")
			gui.Face = if sx > 0 then Enum.NormalId.Right else Enum.NormalId.Left
			gui.PixelsPerStud = 30
			gui.LightInfluence = 1
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Text = liv.code
			label.TextScaled = true
			label.Font = Enum.Font.GothamBold
			label.TextColor3 = stripe
			label.Parent = gui
			gui.Parent = p
		end
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
		if surfaceKind == "wing" and k == 1 and spec.spoilers ~= false then
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
		-- decorative stripe across the upper wing near the tip (aerobatic / trainer colours)
		if liv.wingStripe then
			local s0, s1 = w.span * 0.72, w.span * 0.86
			local up = Vector3.new(0, thick(s0) / 2 + 0.02, 0)
			quad(ctx, comp, "WingStripe", le(s0) + up, le(s1) + up, le(s1) + Vector3.new(0, 0, chord(s1) * 0.7) + up, le(s0) + Vector3.new(0, 0, chord(s0) * 0.7) + up, 0.03, rgb(liv.wingStripe))
		end
		-- wing strut (light high-wing aircraft): from the lower fuselage to the wing underside
		if w.strut then
			local st = w.strut
			local s = w.span * st.at
			local wingPt = le(s) + Vector3.new(0, -thick(s) / 2, chord(s) * 0.3)
			local base = Vector3.new(sx * st.base[1], st.base[2], st.base[3])
			rod(ctx, comp, "Strut", base, wingPt, st.diameter or 0.09, wingColor, { hull = true })
			-- jury strut
			local mid = base:Lerp(wingPt, 0.55)
			rod(ctx, comp, "Strut", mid, Vector3.new(mid.X, le(math.abs(mid.X) - w.rootLE[1]).Y - thick(s) / 2, mid.Z), 0.05, wingColor)
		end
		-- upper wing (biplanes): a plain surface with a tip cap, and interplane struts
		-- (an N pair) tying it to the lower wing
		if w.upper then
			local uw = w.upper
			local spec = {
				rootLE = uw.rootLE, rootChord = uw.rootChord, tipChord = uw.tipChord, span = uw.span,
				sweepDeg = uw.sweepDeg or 0, dihedralDeg = uw.dihedralDeg or 0, thickness = uw.thickness or 0.14,
			}
			local ule, uchord, uthick = buildHalfSurface(ctx, comp, spec, sx, wingColor, "upper")
			local ut = ule(uw.span)
			quad(ctx, comp, "Skin", ule(uw.span * 0.97), ut, ut + Vector3.new(0, 0, uchord(uw.span)), ule(uw.span * 0.97) + Vector3.new(0, 0, uchord(uw.span * 0.97)), uthick(uw.span), wingColor, { hull = true })
			local at = uw.strutAt or 0.75
			local us = uw.span * at
			local ls = math.clamp(math.abs(ule(us).X) - w.rootLE[1], 0, w.span)
			local lTop = le(ls) + Vector3.new(0, thick(ls) / 2, 0)
			local uBot = ule(us) - Vector3.new(0, uthick(us) / 2, 0)
			local strutColor = if liv.strut then rgb(liv.strut) else wingColor
			for _, f in { 0.2, 0.75 } do
				rod(ctx, comp, "InterplaneStrut", lTop + Vector3.new(0, 0, chord(ls) * f), uBot + Vector3.new(0, 0, uchord(us) * f), 0.06, strutColor, { hull = true })
			end
			-- bracing wires (thin dark rods crossing the bay)
			rod(ctx, comp, "Wire", lTop + Vector3.new(0, 0, chord(ls) * 0.2), Vector3.new(sx * (uw.rootLE[1] + 0.05), ule(0).Y - uthick(0) / 2, ule(0).Z + uchord(0) * 0.2), 0.02, DARK_METAL)
			if sx > 0 then
				-- centre section over the fuselage, on cabane struts
				local x0 = uw.rootLE[1]
				local c0 = uchord(0)
				local A = Vector3.new(-x0 - 0.02, uw.rootLE[2], uw.rootLE[3])
				local B = Vector3.new(x0 + 0.02, uw.rootLE[2], uw.rootLE[3])
				quad(ctx, "Fuselage", "UpperCentre", A, B, B + Vector3.new(0, 0, c0), A + Vector3.new(0, 0, c0), uthick(0), wingColor, { hull = true })
				local _, H = bodyHalf(geo.fuselage)
				for _, cx in { -1, 1 } do
					for _, f in { 0.15, 0.7 } do
						local top = Vector3.new(cx * x0 * 0.8, uw.rootLE[2] - uthick(0) / 2, uw.rootLE[3] + c0 * f)
						rod(ctx, "Fuselage", "CabaneStrut", Vector3.new(cx * x0 * 0.55, H * 0.7, top.Z + 0.1), top, 0.05, strutColor)
					end
				end
			end
		end
		-- leading-edge root extension (fighters): a thin swept strake ahead of the wing root
		if w.strake then
			local st = w.strake
			local A = Vector3.new(sx * st.x, le(0).Y, st.z0)
			local B = le(st.reach)
			local C = Vector3.new(sx * st.x, le(0).Y, le(0).Z + chord(0) * 0.3)
			tri(ctx, comp, "Strake", A, B, C, thick(0) * 0.5, wingColor, { hull = true })
		end
		-- navigation lights: red left, green right
		add(ctx, comp, "NavLight", "ball", Vector3.one * math.clamp(w.span / 40, 0.12, 0.25), CFrame.new(tipEnd + Vector3.new(0, 0.05, 0.25)), if sx < 0 then Color3.fromRGB(255, 40, 40) else Color3.fromRGB(40, 255, 80), { material = Enum.Material.Neon })
	end
end

local function buildTail(ctx: Ctx)
	local geo = ctx.cfg.geometry
	local liv = geo.livery
	local tailColor = rgb(liv.tail)
	for _, sx in { -1, 1 } do
		buildHalfSurface(ctx, "HorizontalStab", geo.hstab, sx, rgb(liv.hstab or liv.wing), "hstab")
	end
	-- Fin(s): tapered, swept trapezoids with the rudder on a hinge. Twin fins sit at
	-- +-spacing/2 and can lean outward (cantDeg).
	local v = geo.vstab
	local count = v.count or 1
	local tanSweep = math.tan(math.rad(v.sweepDeg))
	local fins = if count == 2 then { -1, 1 } else { 0 }
	local accent = rgb(liv.accent)
	for _, fs in fins do
		local x0 = fs * (v.spacing or 0) / 2
		local cant = math.rad(v.cantDeg or 0) * fs
		-- "up" along the fin span, leaning outward by the cant angle
		local upDir = Vector3.new(math.sin(cant), math.cos(cant), 0)
		local function le(h: number): Vector3
			return Vector3.new(x0, v.rootLE[2], v.rootLE[3]) + upDir * h + Vector3.new(0, 0, h * tanSweep)
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
		quad(ctx, "VerticalStab", "Fin", fil0, le(v.height * 0.18), L0 + aft * (c0 * 0.3), L0, v.thickness * 0.8, tailColor, { hull = true })
		-- hinge frame: X up the hinge line, Y the fin's side normal (pointing -x)
		local n = (H1 - H0):Cross(aft).Unit
		if n.X > 0 then
			n = -n
		end
		local hp = hinge(ctx, "VerticalStab", "Rudder", H0, H1, n, nil)
		quad(ctx, "VerticalStab", "Rudder", H0, H1, T1, T0, v.thickness * 0.65, darker(tailColor, 0.1), { weldTo = hp })
		-- tail logo: a fictional accent swoosh (two triangles), on both faces
		local side = Vector3.new(math.cos(cant), -math.sin(cant), 0)
		for _, sx in { -1, 1 } do
			local off = side * (sx * (v.thickness / 2 + 0.02))
			local a = le(v.height * 0.35) + aft * (chord(v.height * 0.35) * 0.15) + off
			local b = le(v.height * 0.75) + aft * (chord(v.height * 0.75) * 0.1) + off
			local c = le(v.height * 0.55) + aft * (chord(v.height * 0.55) * 0.6) + off
			tri(ctx, "VerticalStab", "TailLogo", a, b, c, 0.03, accent)
		end
	end
	-- tail light and beacon
	add(ctx, "AftFuselage", "TailLight", "ball", Vector3.new(0.22, 0.22, 0.22), CFrame.new(0, geo.fuselage.tailUpsweep + 0.2 * math.min(1, geo.fuselage.radius), geo.fuselage.tailEndZ + 0.1), Color3.new(1, 1, 1), { material = Enum.Material.Neon })
	local _, H = bodyHalf(geo.fuselage)
	local topY = if geo.fuselage.hump then geo.fuselage.hump.top else H
	local bz = if geo.fuselage.canopy then geo.fuselage.canopy.z1 + 1 else 2
	add(ctx, "Fuselage", "Beacon", "ball", Vector3.one * math.clamp(geo.fuselage.radius * 0.2, 0.12, 0.3), CFrame.new(0, topY + 0.1, bz), Color3.fromRGB(255, 30, 30), { material = Enum.Material.Neon, tag = "Beacon" })
end

-- Engines ----------------------------------------------------------------------------
-- Every engine has one spinning assembly (fan, propeller or turbine) on a Motor6D named
-- FanMotor with an EngineIndex attribute; FlightController spins it with N1. Both motor
-- frames have local +X pointing forward (body -Z).

-- Invisible mount + spinning hub at `hubPos`. Returns the hub (blades weld to it).
local function spinAssembly(ctx: Ctx, comp: string, index: number, hubPos: Vector3, hubSemi: Vector3, hubColor: Color3, hubOpts: any?): BasePart
	local cf = CFrame.new(hubPos) * ALONG_Z
	local mount = add(ctx, comp, "SpinMount", "block", Vector3.new(0.1, 0.1, 0.1), cf, Color3.new(), { transparency = 1 })
	local o = { noWeld = true }
	if hubOpts then
		for k, v in hubOpts do
			o[k] = v
		end
	end
	local hub = ellipsoid(ctx, comp, "FanHub", cf, hubSemi, hubColor, o)
	local m = Instance.new("Motor6D")
	m.Name = "FanMotor"
	m.Part0 = mount
	m.Part1 = hub
	m.C0 = CFrame.new()
	m.C1 = CFrame.new()
	m:SetAttribute("EngineIndex", index)
	m.Parent = mount
	return hub
end

-- Propeller: `n` tapered, twisted blades (two wedges each) with coloured tips.
local function propeller(ctx: Ctx, comp: string, hub: BasePart, centre: Vector3, n: number, rootR: number, tipR: number, rootChord: number, tipChord: number, pitchDeg: number, color: Color3, tipColor: Color3?)
	local pitch = math.rad(pitchDeg)
	for b = 0, n - 1 do
		local a = b * 2 * math.pi / n + math.rad(15)
		local radial = Vector3.new(math.cos(a), math.sin(a), 0)
		local tangent = Vector3.new(-math.sin(a), math.cos(a), 0)
		local chordDir = tangent * math.cos(pitch) + Vector3.new(0, 0, 1) * math.sin(pitch)
		local function corner(r: number, c: number, along: number): Vector3
			return centre + radial * r + chordDir * (c * along)
		end
		local tipStart = tipR - (tipR - rootR) * 0.12
		local cMid = rootChord + (tipChord - rootChord) * 0.88
		quad(ctx, comp, "PropBlade", corner(rootR, rootChord, -0.35), corner(tipStart, cMid, -0.35), corner(tipStart, cMid, 0.65), corner(rootR, rootChord, 0.65), 0.05, color, { weldTo = hub })
		quad(ctx, comp, "PropTip", corner(tipStart, cMid, -0.35), corner(tipR, tipChord, -0.3), corner(tipR, tipChord, 0.55), corner(tipStart, cMid, 0.65), 0.05, tipColor or color, { weldTo = hub })
	end
end

-- Ring of `n` short rods around the Z axis: a smooth torus (intake lips, nozzle rims).
local function torus(ctx: Ctx, comp: string, name: string, centre: Vector3, ringR: number, tubeD: number, n: number, color: Color3, opts: any?)
	for k = 0, n - 1 do
		local a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
		local q0 = centre + Vector3.new(ringR * math.cos(a0), ringR * math.sin(a0), 0)
		local q1 = centre + Vector3.new(ringR * math.cos(a1), ringR * math.sin(a1), 0)
		local mid, half = (q0 + q1) / 2, (q1 - q0) * 0.56
		rod(ctx, comp, name, mid - half, mid + half, tubeD, color, opts)
	end
end

-- Ring of `n` curved panels forming an open tube (so the fan inside stays visible).
local function tube(ctx: Ctx, comp: string, name: string, centre: Vector3, r: number, wall: number, len: number, n: number, color: Color3, opts: any?)
	local w = 2 * math.pi * r / n * 1.08
	for k = 0, n - 1 do
		local a = 2 * math.pi * (k + 0.5) / n
		local radial = Vector3.new(math.cos(a), math.sin(a), 0)
		local tangent = Vector3.new(-math.sin(a), math.cos(a), 0)
		add(ctx, comp, name, "block", Vector3.new(wall, w, len), CFrame.fromMatrix(centre + radial * r, radial, tangent), color, opts)
	end
end

-- Wing surface (LE point, chord, thickness) at a body x, for pylons.
local function wingAt(w: any, x: number): (Vector3, number, number)
	local s = math.clamp(math.abs(x) - w.rootLE[1], 0, w.span)
	local sx = if x < 0 then -1 else 1
	local le = Vector3.new(x, w.rootLE[2] + s * math.tan(math.rad(w.dihedralDeg)), w.rootLE[3] + s * math.tan(math.rad(w.sweepDeg)))
	local chord = w.rootChord + (w.tipChord - w.rootChord) * s / w.span
	local t0 = w.rootThickness or w.thickness
	local t1 = w.tipThickness or (w.thickness or t0) * 0.6
	local _ = sx
	return le, chord, t0 + (t1 - t0) * s / w.span
end

local function failureSmoke(ctx: Ctx, comp: string)
	local exhaust = (ctx.comps[comp] :: any):FindFirstChild("Exhaust")
	if not exhaust then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "SmokeAttachment"
	att.Parent = exhaust
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

-- Turbofan: rounded metal intake lip, open inlet with a spinner and fan blades, a
-- fan cowl that tapers to the fan nozzle, the core cowl and a pointed exhaust plug.
local function buildTurbofan(ctx: Ctx, comp: string, index: number, p: Vector3, eg: any, nac: Color3)
	local L, R = eg.length, eg.radius
	local zf = p.Z - L / 2
	local function at(z: number): Vector3
		return Vector3.new(p.X, p.Y, z)
	end
	local lipZ = zf + R * 0.08
	local inletLen = L * 0.26
	torus(ctx, comp, "IntakeLip", at(lipZ), R * 0.925, R * 0.15, 12, METAL, { material = Enum.Material.Metal, reflectance = 0.15, hull = true })
	tube(ctx, comp, "Inlet", at(lipZ + inletLen / 2), R * 0.95, R * 0.07, inletLen, 12, nac, { hull = true })
	-- fan face: dark case, spinner and blades
	local fanZ = lipZ + inletLen * 0.72
	add(ctx, comp, "FanCase", "cylinder", Vector3.new(0.04, R * 1.86, R * 1.86), CFrame.new(at(fanZ + 0.06)) * ALONG_Z, INTAKE_DARK)
	local hub = spinAssembly(ctx, comp, index, at(fanZ - R * 0.1), Vector3.new(R * 0.42, R * 0.27, R * 0.27), Color3.fromRGB(235, 236, 240), { material = Enum.Material.Metal })
	local nb = eg.fanBlades or 14
	for b = 0, nb - 1 do
		local a = 2 * math.pi * b / nb
		local radial = Vector3.new(math.cos(a), math.sin(a), 0)
		local tangent = Vector3.new(-math.sin(a), math.cos(a), 0)
		local cf = CFrame.fromMatrix(at(fanZ) + radial * (R * 0.58), radial, tangent) * CFrame.Angles(math.rad(40), 0, 0)
		local blade = add(ctx, comp, "FanBlade", "block", Vector3.new(R * 0.62, R * 0.24, 0.03), cf, FAN, { noWeld = true, material = Enum.Material.Metal })
		weld(hub, blade)
	end
	-- fan cowl
	local bodyStart, bodyEnd = lipZ + inletLen - 0.02, zf + L * 0.55
	add(ctx, comp, "Nacelle", "cylinder", Vector3.new(bodyEnd - bodyStart, R * 2, R * 2), CFrame.new(at((bodyStart + bodyEnd) / 2)) * ALONG_Z, nac, { hull = true })
	ellipsoid(ctx, comp, "NacelleAft", CFrame.new(at(bodyEnd)), Vector3.new(R, R, L * 0.3), nac, { hull = true })
	-- fan nozzle exit line, core cowl, core nozzle and plug
	add(ctx, comp, "FanNozzle", "cylinder", Vector3.new(0.05, R * 1.56, R * 1.56), CFrame.new(at(zf + L * 0.745)) * ALONG_Z, INTAKE_DARK)
	add(ctx, comp, "Exhaust", "cylinder", Vector3.new(L * 0.22, R * 1.0, R * 1.0), CFrame.new(at(zf + L * 0.81)) * ALONG_Z, Color3.fromRGB(150, 152, 160), { material = Enum.Material.Metal })
	add(ctx, comp, "CoreNozzle", "cylinder", Vector3.new(0.04, R * 0.94, R * 0.94), CFrame.new(at(zf + L * 0.925)) * ALONG_Z, INTAKE_DARK)
	ellipsoid(ctx, comp, "ExhaustCone", CFrame.new(at(zf + L * 0.92)), Vector3.new(R * 0.34, R * 0.34, L * 0.16), DARK_METAL, { material = Enum.Material.Metal })

	local geo = ctx.cfg.geometry
	local w = geo.wing
	if eg.mount == "fuselage" then
		-- rear-mounted (bizjet): a short horizontal pylon into the fuselage side
		local sx = if p.X < 0 then -1 else 1
		local HW = bodyHalf(geo.fuselage)
		local xIn, xOut = p.X - sx * R * 0.8, sx * HW * 0.6
		local z0, z1 = zf + L * 0.28, zf + L * 0.75
		quad(ctx, comp, "Pylon", Vector3.new(xIn, p.Y, z0 + 0.2), Vector3.new(xIn, p.Y, z1), Vector3.new(xOut, p.Y - 0.05, z1 + 0.3), Vector3.new(xOut, p.Y - 0.05, z0 - 0.2), R * 0.3, nac, { hull = true })
		rod(ctx, comp, "PylonEdge", Vector3.new(xIn, p.Y, z0 + 0.2 + R * 0.12), Vector3.new(xOut, p.Y - 0.05, z0 - 0.2 + R * 0.12), R * 0.3, nac)
	else
		-- under-wing pylon: a swept blade from the fan cowl up into the wing underside,
		-- reaching forward of the leading edge, with a fairing under the wing behind it
		local le, chord, th = wingAt(w, p.X)
		local wingBot = le.Y - th / 2 + 0.08
		local top = p.Y + R * 0.9
		if wingBot - top < 0.15 then
			wingBot = top + 0.15
		end
		local A = Vector3.new(p.X, top, zf + L * 0.22)
		local B = Vector3.new(p.X, top, zf + L * 0.78)
		local C = Vector3.new(p.X, wingBot, le.Z + chord * 0.55)
		local D = Vector3.new(p.X, wingBot, math.min(le.Z - 0.1, zf + L * 0.38))
		local pw = math.max(0.18, R * 0.24)
		quad(ctx, comp, "Pylon", A, B, C, D, pw, nac, { hull = true })
		rod(ctx, comp, "PylonEdge", A + Vector3.new(0, 0, pw * 0.4), D + Vector3.new(0, 0, pw * 0.4), pw, nac)
		local E = Vector3.new(p.X, wingBot, le.Z + chord * 0.85)
		local F = Vector3.new(p.X, wingBot - R * 0.35, le.Z + chord * 0.6)
		tri(ctx, comp, "PylonFairing", C, E, F, pw * 0.9, nac)
		tri(ctx, comp, "PylonFairing", B, C, F, pw * 0.9, nac)
	end
end

-- Turboprop under a high wing: an oval nacelle with a pointed spinner, a chin intake,
-- side exhaust stubs and a nacelle that runs back under the wing.
local function buildTurboprop(ctx: Ctx, comp: string, index: number, p: Vector3, eg: any, nac: Color3)
	local L, R = eg.length, eg.radius
	local zf = p.Z - L / 2
	local function at(z: number, dy: number?): Vector3
		return Vector3.new(p.X, p.Y + (dy or 0), z)
	end
	local hub = spinAssembly(ctx, comp, index, at(zf - R * 0.15), Vector3.new(R * 0.9, R * 0.46, R * 0.46), nac, {})
	local tipColor = Color3.fromRGB(250, 200, 40)
	propeller(ctx, comp, hub, at(zf - R * 0.15), eg.blades or 6, R * 0.35, eg.propRadius or 1.9, 0.36, 0.16, 24, Color3.fromRGB(38, 38, 42), tipColor)
	-- cowling: rounded front ring, then the oval body
	ellipsoid(ctx, comp, "Cowl", CFrame.new(at(zf + L * 0.18)), Vector3.new(R, R * 1.05, L * 0.2), nac, { hull = true })
	ecylinder(ctx, comp, "Nacelle", at(zf + L * 0.42, R * 0.08), L * 0.5, R, R * 1.12, nac, { hull = true })
	ellipsoid(ctx, comp, "NacelleAft", CFrame.new(at(zf + L * 0.68, R * 0.15)), Vector3.new(R * 0.9, R * 1.0, L * 0.42), nac, { hull = true })
	-- chin intake
	ellipsoid(ctx, comp, "IntakeLip", CFrame.new(at(zf + L * 0.2, -R * 0.78)), Vector3.new(R * 0.42, R * 0.3, L * 0.14), nac, { hull = true })
	add(ctx, comp, "IntakeMouth", "block", Vector3.new(R * 0.5, R * 0.3, 0.04), CFrame.new(at(zf + L * 0.065, -R * 0.8)), INTAKE_DARK)
	-- exhaust stubs on both sides, angled out and back
	for _, sx in { -1, 1 } do
		local base = Vector3.new(p.X + sx * R * 0.82, p.Y + R * 0.25, zf + L * 0.5)
		rod(ctx, comp, if sx > 0 then "Exhaust" else "ExhaustStub", base, base + Vector3.new(sx * R * 0.25, 0.04, L * 0.14), R * 0.36, DARK_METAL, { material = Enum.Material.Metal })
	end
	-- fairing up into the wing
	local w = ctx.cfg.geometry.wing
	local le, chord, th = wingAt(w, p.X)
	local wingBot = le.Y - th / 2
	local top = p.Y + R * 0.9
	if wingBot > top - 0.1 then
		local hgt = math.max(0.2, wingBot - top + 0.15)
		add(ctx, comp, "Pylon", "block", Vector3.new(R * 1.5, hgt, chord * 0.9), CFrame.new(p.X, top + hgt / 2 - 0.05, le.Z + chord * 0.45), nac, { hull = true })
	end
end

-- Piston engine in the nose: spinner and propeller ahead of the fuselage cowling, two
-- cooling inlets beside the spinner and an exhaust stack under the cowl.
local function buildPiston(ctx: Ctx, comp: string, index: number, p: Vector3, eg: any, nac: Color3)
	local sr = eg.spinnerRadius or 0.18
	local sl = eg.spinnerLength or sr * 1.8
	local spinnerColor = if eg.spinnerColor then rgb(eg.spinnerColor) else nac
	local hub = spinAssembly(ctx, comp, index, p, Vector3.new(sl, sr, sr), spinnerColor, { hull = true })
	propeller(ctx, comp, hub, p + Vector3.new(0, 0, sl * 0.25), eg.blades or 2, sr * 0.7, eg.propRadius or 0.95, eg.bladeChord or 0.17, (eg.bladeChord or 0.17) * 0.55, 18, Color3.fromRGB(34, 34, 38), Color3.fromRGB(250, 250, 250))
	local g = ctx.cfg.geometry.fuselage
	local HW, H = bodyHalf(g)
	for _, sx in { -1, 1 } do
		ellipsoid(ctx, comp, "CoolingInlet", CFrame.new(p + Vector3.new(sx * sr * 1.6, -sr * 0.4, sl * 0.9)), Vector3.new(math.min(HW * 0.28, 0.16), math.min(H * 0.22, 0.12), 0.08), INTAKE_DARK)
	end
	local ex = p + Vector3.new(HW * 0.45, -H * 0.85, (eg.exhaustZ or 1.1))
	rod(ctx, comp, "Exhaust", ex, ex + Vector3.new(0.02, -0.08, 0.28), 0.09, DARK_METAL, { material = Enum.Material.Metal })
end

-- Jet buried in the fuselage (fighters): a metal nozzle with a dark inside, a turbine
-- face that spins and a faint hot glow.
local function buildJet(ctx: Ctx, comp: string, index: number, p: Vector3, eg: any, nac: Color3)
	local rn = eg.nozzleRadius or 0.45
	local function at(dz: number): Vector3
		return p + Vector3.new(0, 0, dz)
	end
	local body = rgb(ctx.cfg.geometry.livery.body)
	add(ctx, comp, "NozzleFairing", "cylinder", Vector3.new(1.0, rn * 2.2, rn * 2.2), CFrame.new(at(-1.05)) * ALONG_Z, body, { hull = true })
	-- open nozzle (a ring of panels) so the turbine and glow inside show
	tube(ctx, comp, "Exhaust", at(-0.3), rn * 0.94, 0.08, 0.75, 14, HOT_METAL, { material = Enum.Material.Metal, hull = true })
	torus(ctx, comp, "NozzleRim", at(0.06), rn * 0.96, 0.08, 14, DARK_METAL, { material = Enum.Material.Metal })
	add(ctx, comp, "NozzleInside", "cylinder", Vector3.new(0.04, rn * 1.8, rn * 1.8), CFrame.new(at(-0.6)) * ALONG_Z, INTAKE_DARK)
	add(ctx, comp, "Glow", "cylinder", Vector3.new(0.03, rn * 1.3, rn * 1.3), CFrame.new(at(-0.57)) * ALONG_Z, Color3.fromRGB(255, 120, 40), { material = Enum.Material.Neon, transparency = 0.5, noShadow = true })
	local hub = spinAssembly(ctx, comp, index, at(-0.45), Vector3.new(0.12, rn * 0.28, rn * 0.28), DARK_METAL, { material = Enum.Material.Metal })
	for b = 0, 9 do
		local a = 2 * math.pi * b / 10
		local radial = Vector3.new(math.cos(a), math.sin(a), 0)
		local tangent = Vector3.new(-math.sin(a), math.cos(a), 0)
		local cf = CFrame.fromMatrix(at(-0.47) + radial * (rn * 0.55), radial, tangent) * CFrame.Angles(math.rad(35), 0, 0)
		local blade = add(ctx, comp, "TurbineBlade", "block", Vector3.new(rn * 0.55, rn * 0.2, 0.03), cf, Color3.fromRGB(90, 86, 82), { noWeld = true, material = Enum.Material.Metal })
		weld(hub, blade)
	end
	local _ = nac
end

local function buildEngines(ctx: Ctx)
	local geo = ctx.cfg.geometry
	local liv = geo.livery
	local eg = geo.engine
	local nac = rgb(liv.engine)
	for i, e in ctx.cfg.engines do
		local comp = e.component
		local p = v3(e.pos)
		local kind = eg.kind or "turbofan"
		if kind == "turboprop" then
			buildTurboprop(ctx, comp, i, p, eg, nac)
		elseif kind == "piston" then
			buildPiston(ctx, comp, i, p, eg, nac)
		elseif kind == "jet" then
			buildJet(ctx, comp, i, p, eg, nac)
		else
			buildTurbofan(ctx, comp, i, p, eg, nac)
		end
		-- afterburner flame behind the nozzle (hidden; the client fades it in with reheat)
		if e.afterburner and kind == "turbofan" then
			local L, R = eg.length, eg.radius
			local flameLen = L * 0.9
			local z = p.Z + L * 0.42 + flameLen / 2
			local outer = ellipsoid(ctx, comp, "AfterburnerFlame", CFrame.new(p.X, p.Y, z), Vector3.new(R * 0.5, R * 0.5, flameLen / 2), Color3.fromRGB(255, 140, 50), { material = Enum.Material.Neon, transparency = 1, noShadow = true, attrs = { AfterburnerIndex = i } })
			ellipsoid(ctx, comp, "AfterburnerCore", CFrame.new(p.X, p.Y, z - flameLen * 0.2), Vector3.new(R * 0.3, R * 0.3, flameLen * 0.3), Color3.fromRGB(255, 230, 170), { material = Enum.Material.Neon, transparency = 1, noShadow = true, attrs = { AfterburnerIndex = i } })
			local light = Instance.new("PointLight")
			light.Name = "AfterburnerLight"
			light.Color = Color3.fromRGB(255, 150, 70)
			light.Range = 30
			light.Brightness = 0
			light.Parent = outer
		end
		-- smoke emitter (enabled by the client when the engine is failed/on fire)
		failureSmoke(ctx, comp)
	end
end

local function buildGear(ctx: Ctx)
	local tire = Color3.fromRGB(28, 28, 30)
	local strutColor = Color3.fromRGB(170, 172, 178)
	local fixed = ctx.cfg.gear.fixed == true
	local liv = ctx.cfg.geometry.livery
	for _, u in ctx.cfg.gear.units do
		local comp = u.component
		local model = getComponent(ctx, comp)
		local root = model.PrimaryPart :: BasePart
		local attach = v3(u.pos)
		local L = u.strutLength
		local wr = u.wheelRadius
		local legD = u.legDiameter or math.clamp(wr * 0.6, 0.07, 0.26)
		-- leg: centred L/2 below the attach point
		local leg = add(ctx, comp, "Leg", "cylinder", Vector3.new(L, legD, legD), CFrame.new(attach - Vector3.new(0, L / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), strutColor, { noWeld = true, material = Enum.Material.Metal })
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
		-- spring-steel leg / brace from the fuselage out to the attach point (light aircraft)
		if u.brace then
			local br = rod(ctx, comp, "GearBrace", v3(u.brace), attach, legD * 1.3, strutColor, { noWeld = true, material = Enum.Material.Metal })
			if br then
				weld(leg, br)
			end
		end
		-- wheels: rows x across, axis along body X, on a bogie beam when there are two rows
		local n = u.wheels or 2
		local rows = u.rows or 1
		local rowSpacing = u.rowSpacing or 1.4
		for row = 1, rows do
			local dz = (row - (rows + 1) / 2) * rowSpacing
			for w = 1, n do
				local off = (w - (n + 1) / 2) * (u.wheelSpacing or 0.6)
				local c = attach + Vector3.new(off, -L, dz)
				local wheel = add(ctx, comp, "Wheel", "cylinder", Vector3.new(wr * 0.62, wr * 2, wr * 2), CFrame.new(c), tire, { noWeld = true })
				weld(leg, wheel)
				local hubcap = add(ctx, comp, "Hub", "cylinder", Vector3.new(wr * 0.66, wr * 1.05, wr * 1.05), CFrame.new(c), strutColor, { noWeld = true, material = Enum.Material.Metal })
				weld(leg, hubcap)
				if u.fairing then
					-- streamlined wheel spat (light aircraft)
					local spat = ellipsoid(ctx, comp, "WheelSpat", CFrame.new(c + Vector3.new(0, wr * 0.15, wr * 0.15)), Vector3.new(wr * 0.55, wr * 0.85, wr * 1.75), rgb(liv.accent), { noWeld = true })
					weld(leg, spat)
				end
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
		-- gear door (retracting gear only)
		if not fixed and u.door ~= false then
			local door = add(ctx, comp, "GearDoor", "block", Vector3.new(0.05, L * 0.6, wr * 1.6), CFrame.new(attach + Vector3.new(if attach.X < 0 then -0.25 elseif attach.X > 0 then 0.25 else 0.3, -L * 0.35, 0)), rgb(liv.belly), { noWeld = true })
			weld(leg, door)
		end
		if u.steerMaxDeg > 0 and u.light ~= false then
			-- taxi/landing light on the nose gear
			local lamp = add(ctx, comp, "LandingLamp", "block", Vector3.new(0.3, 0.2, 0.1) * math.clamp(wr / 0.35, 0.5, 1), CFrame.new(attach + Vector3.new(0, -L * 0.45, -legD)), Color3.new(1, 1, 0.9), { noWeld = true, material = Enum.Material.Neon })
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

-- Floats (seaplane): two long hulls with an upturned bow, a stepped planing bottom and
-- struts up to the fuselage. Each float is its own component (it can be torn off).
local function buildFloats(ctx: Ctx)
	local f = ctx.cfg.geometry.floats
	if not f then
		return
	end
	local liv = ctx.cfg.geometry.livery
	local color = rgb(f.color or liv.belly)
	local top = rgb(liv.stripe)
	for _, sx in { -1, 1 } do
		local comp = if sx < 0 then "LeftFloat" else "RightFloat"
		local x = sx * f.x
		local len = f.z1 - f.z0
		local hw, hh = f.halfWidth, f.halfHeight
		local bowZ, midEnd = f.z0 + len * 0.22, f.z0 + len * 0.62
		ellipsoid(ctx, comp, "FloatBow", CFrame.new(x, f.y + hh * 0.18, bowZ) * CFrame.Angles(math.rad(-6), 0, 0), Vector3.new(hw, hh, len * 0.22), color, { hull = true })
		ecylinder(ctx, comp, "Float", Vector3.new(x, f.y, (bowZ + midEnd) / 2), midEnd - bowZ + 0.04, hw, hh, color, { hull = true })
		ellipsoid(ctx, comp, "FloatStern", CFrame.new(x, f.y + hh * 0.2, midEnd) * CFrame.Angles(math.rad(4), 0, 0), Vector3.new(hw * 0.95, hh * 0.8, len * 0.38), color, { hull = true })
		-- deck stripe and the planing step
		add(ctx, comp, "FloatDeck", "block", Vector3.new(hw * 0.9, 0.04, midEnd - bowZ), CFrame.new(x, f.y + hh - 0.01, (bowZ + midEnd) / 2), top)
		if f.step ~= false then
			add(ctx, comp, "FloatStep", "block", Vector3.new(hw * 1.6, hh * 0.35, 0.12), CFrame.new(x, f.y - hh * 0.7, midEnd), darker(color, 0.25))
		end
		-- struts: front and rear pairs up to the fuselage, plus a cross brace
		for _, st in f.struts do
			local foot = Vector3.new(x, f.y + hh * 0.9, st.z)
			local head = Vector3.new(sx * st.x, st.y, st.z + (st.lean or 0))
			rod(ctx, comp, "FloatStrut", foot, head, 0.08, rgb(liv.wing), { hull = true })
			if f.brace ~= false then
				rod(ctx, comp, "FloatStrut", foot, Vector3.new(sx * 0.1, st.y, st.z + 0.4), 0.05, rgb(liv.wing))
			end
		end
		-- water rudder at the stern
		if f.waterRudder ~= false then
			add(ctx, comp, "WaterRudder", "block", Vector3.new(0.03, hh * 0.9, 0.25), CFrame.new(x, f.y, f.z1 - 0.05), DARK_METAL)
		end
	end
end

-- Flight deck / cockpit interior, shown only from the cockpit camera (the outer nose
-- shell is hidden then). Airliner and cabin styles get walls with side windows and
-- clear glass; the canopy style (fighters, aerobatic) gets a tub, consoles and a stick.
local function cockpitPanel(ctx: Ctx, comp: string, size: Vector3, cf: CFrame, color: Color3, style: string, n: number, o: any)
	local panel = add(ctx, comp, "Panel", "block", size, cf, color, o)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back -- faces the pilots (+z)
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.Parent = panel
	if style == "gauges" then
		-- round steam gauges in two rows
		local cols = math.ceil(n / 2)
		for i = 1, n do
			local row = if i <= cols then 0 else 1
			local col = if i <= cols then i else i - cols
			local f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale((col - 0.5) / cols, 0.3 + row * 0.42)
			f.Size = UDim2.fromScale(0.75 / cols, 0.36)
			f.BackgroundColor3 = Color3.fromRGB(14, 15, 18)
			f.BorderSizePixel = 0
			local ar = Instance.new("UIAspectRatioConstraint")
			ar.AspectRatio = 1
			ar.Parent = f
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = f
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(200, 200, 205)
			stroke.Thickness = 2
			stroke.Parent = f
			local needle = Instance.new("Frame")
			needle.AnchorPoint = Vector2.new(0.5, 1)
			needle.Position = UDim2.fromScale(0.5, 0.5)
			needle.Size = UDim2.fromScale(0.05, 0.4)
			needle.Rotation = (i * 47) % 300 - 150
			needle.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
			needle.BorderSizePixel = 0
			needle.Parent = f
			f.Parent = sg
		end
		return panel
	end
	for i = 1, n do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale((i - 0.5) / n, 0.45)
		f.Size = UDim2.fromScale(0.8 / n, 0.7)
		f.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
		f.BorderSizePixel = 0
		f.Parent = sg
		local top = Instance.new("Frame")
		top.Size = UDim2.fromScale(1, if i % 2 == 1 then 0.5 else 0.3)
		top.BackgroundColor3 = if i % 2 == 1 then Color3.fromRGB(40, 110, 200) else Color3.fromRGB(20, 60, 40)
		top.BorderSizePixel = 0
		top.Parent = f
		if i % 2 == 1 then
			local ground = Instance.new("Frame")
			ground.Position = UDim2.fromScale(0, 0.5)
			ground.Size = UDim2.fromScale(1, 0.5)
			ground.BackgroundColor3 = Color3.fromRGB(130, 85, 45)
			ground.BorderSizePixel = 0
			ground.Parent = f
		end
	end
	return panel
end

local function buildCanopyCockpit(ctx: Ctx)
	local g = ctx.cfg.geometry
	local fz = g.fuselage
	local cp = g.cockpit or {}
	local eye = v3(ctx.cfg.cameras.cockpit)
	local comp = if eye.Z < fz.forwardSplitZ then "ForwardFuselage" else "Fuselage"
	local dark = Color3.fromRGB(44, 46, 52)
	local black = Color3.fromRGB(22, 23, 26)
	local o = { tag = "CockpitOnly", transparency = 1 }
	local hw = cp.halfWidth or (fz.canopy.halfWidth * 0.95)
	local front = eye.Z - (cp.panelDistance or 0.75)
	-- tub sides and floor
	for _, sx in { -1, 1 } do
		add(ctx, comp, "Console", "block", Vector3.new(0.18, 0.12, 1.3), CFrame.new(sx * (hw - 0.1), eye.Y - 0.55, eye.Z - 0.05), dark, o)
		add(ctx, comp, "TubSide", "block", Vector3.new(0.05, 0.5, 1.9), CFrame.new(sx * hw, eye.Y - 0.85, eye.Z - 0.2), dark, o)
	end
	add(ctx, comp, "DeckFloor", "block", Vector3.new(hw * 2, 0.05, 1.9), CFrame.new(0, eye.Y - 1.1, eye.Z - 0.2), black, o)
	-- glareshield and panel
	add(ctx, comp, "Glareshield", "block", Vector3.new(hw * 1.7, 0.08, 0.3), CFrame.new(0, eye.Y - 0.3, front + 0.05), black, o)
	cockpitPanel(ctx, comp, Vector3.new(hw * 1.6, 0.42, 0.06), CFrame.new(0, eye.Y - 0.55, front + 0.12) * CFrame.Angles(math.rad(-15), 0, 0), dark, cp.panel or "screens", cp.screens or 3, o)
	-- head-up display combiner (fighters)
	if cp.hud then
		add(ctx, comp, "HudFrame", "block", Vector3.new(0.2, 0.04, 0.12), CFrame.new(0, eye.Y - 0.24, front + 0.1), black, o)
		add(ctx, comp, "HudGlass", "block", Vector3.new(0.18, 0.16, 0.02), CFrame.new(0, eye.Y - 0.14, front + 0.08) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(110, 220, 140), { material = Enum.Material.Glass, transparency = 1, tag = "CockpitOnly", noShadow = true, attrs = { CockpitTransparency = 0.7 } })
	end
	-- control stick and throttle
	add(ctx, comp, "Stick", "block", Vector3.new(0.05, 0.4, 0.05), CFrame.new(0, eye.Y - 0.82, eye.Z - 0.35), black, o)
	add(ctx, comp, "StickGrip", "block", Vector3.new(0.07, 0.12, 0.08), CFrame.new(0, eye.Y - 0.6, eye.Z - 0.36), black, o)
	add(ctx, comp, "ThrustLever", "block", Vector3.new(0.05, 0.14, 0.08), CFrame.new(-hw + 0.12, eye.Y - 0.44, eye.Z - 0.15), Color3.fromRGB(220, 220, 225), o)
	add(ctx, comp, "SeatBack", "block", Vector3.new(0.5, 0.8, 0.12), CFrame.new(0, eye.Y - 0.55, eye.Z + 0.35), black, o)
	-- canopy frame bows seen from inside
	local c = fz.canopy
	local zc = (c.z0 + c.z1) / 2
	for _, fzz in c.frames or {} do
		local semiZ = (c.z1 - c.z0) / 2
		local u = (zc - fzz) / semiZ
		local k = math.sqrt(math.max(0.02, 1 - u * u))
		arch(ctx, comp, "CanopyFrameInner", Vector3.new(0, c.y, fzz), c.halfWidth * k * 0.97, c.height * k * 0.97, -88, 88, 8, 0.05, black, o)
	end
end

local function buildCockpit(ctx: Ctx)
	local g = ctx.cfg.geometry
	local fz = g.fuselage
	local cp = g.cockpit or {}
	if fz.canopy then
		buildCanopyCockpit(ctx)
	else
		local eye = v3(ctx.cfg.cameras.cockpit)
		local wall = Color3.fromRGB(196, 198, 202)
		local dark = Color3.fromRGB(44, 46, 52)
		local black = Color3.fromRGB(22, 23, 26)
		local o = { tag = "CockpitOnly", transparency = 1 }
		-- inner half-width at the eye station (narrower towards the nose; jumbo hump if any)
		local noseLen = fz.cabinStartZ - fz.noseZ
		local t = math.clamp((fz.cabinStartZ - eye.Z) / noseLen, 0, 0.95)
		local outer = if fz.hump then (fz.hump.halfWidth or fz.radius * 0.8) else fz.radius
		local hw = cp.halfWidth or math.clamp(outer * math.sqrt(1 - t * t) * 0.9, 1.1, 2.4)
		local scale = math.clamp(hw / 1.1, 0.55, 1)
		local front, back = eye.Z - (cp.panelDistance or 1.25), eye.Z + 1.9 * scale
		local floorY, sill, winTop, roofY = eye.Y - 1.3 * scale, eye.Y - 0.22, eye.Y + 0.42 * scale, eye.Y + 0.7 * scale
		local len = back - front
		local zc = (front + back) / 2
		local seats = cp.seats or 2
		add(ctx, "ForwardFuselage", "DeckFloor", "block", Vector3.new(hw * 2, 0.08, len), CFrame.new(0, floorY, zc), dark, o)
		add(ctx, "ForwardFuselage", "DeckRoof", "block", Vector3.new(hw * 2, 0.08, len), CFrame.new(0, roofY, zc), wall, o)
		if seats == 2 and scale > 0.8 then
			add(ctx, "ForwardFuselage", "Overhead", "block", Vector3.new(hw * 1.1, 0.16, 1.2), CFrame.new(0, roofY - 0.1, eye.Z - 0.4) * CFrame.Angles(math.rad(-12), 0, 0), dark, o)
		end
		add(ctx, "ForwardFuselage", "Bulkhead", "block", Vector3.new(hw * 2, roofY - floorY, 0.08), CFrame.new(0, (roofY + floorY) / 2, back), wall, o)
		if scale > 0.8 then
			add(ctx, "ForwardFuselage", "Door", "block", Vector3.new(0.7, 1.7, 0.1), CFrame.new(0, floorY + 0.9, back - 0.03), Color3.fromRGB(150, 152, 158), o)
		end
		local sideOpenEnd = eye.Z + 1.05 * scale
		for _, sx in { -1, 1 } do
			local x = sx * hw
			-- side wall below and above the side windows, and a window post
			add(ctx, "ForwardFuselage", "SideWall", "block", Vector3.new(0.08, sill - floorY, len), CFrame.new(x, (sill + floorY) / 2, zc), wall, o)
			add(ctx, "ForwardFuselage", "SideWall", "block", Vector3.new(0.08, roofY - winTop, len), CFrame.new(x, (roofY + winTop) / 2, zc), wall, o)
			add(ctx, "ForwardFuselage", "SidePost", "block", Vector3.new(0.1, winTop - sill, 0.14), CFrame.new(x, (winTop + sill) / 2, eye.Z + 0.35 * scale), dark, o)
			add(ctx, "ForwardFuselage", "SideWall", "block", Vector3.new(0.08, winTop - sill, back - sideOpenEnd), CFrame.new(x, (winTop + sill) / 2, (back + sideOpenEnd) / 2), wall, o)
			-- side window glass
			add(ctx, "ForwardFuselage", "SideGlass", "block", Vector3.new(0.03, winTop - sill, sideOpenEnd - front), CFrame.new(x * 1.01, (winTop + sill) / 2, (front + sideOpenEnd) / 2), GLASS, cockpitGlassOpts())
			-- windscreen corner post
			add(ctx, "ForwardFuselage", "Post", "block", Vector3.new(0.12, 0.85 * scale, 0.12), CFrame.new(sx * hw * 0.78, eye.Y + 0.1, front + 0.05) * CFrame.Angles(math.rad(-28), 0, 0), black, o)
		end
		for si = 1, seats do
			local seatX = if seats == 1 then 0 else (if si == 1 then -1 else 1) * math.abs(eye.X)
			add(ctx, "ForwardFuselage", "SeatBack", "block", Vector3.new(0.5, 0.9 * scale, 0.14), CFrame.new(seatX, floorY + 0.95 * scale, eye.Z + 0.45), black, o)
			add(ctx, "ForwardFuselage", "SeatPan", "block", Vector3.new(0.5, 0.12, 0.5), CFrame.new(seatX, floorY + 0.5 * scale, eye.Z + 0.15), black, o)
			-- control yoke in front of each seat
			local yz = front + 0.75 * scale
			add(ctx, "ForwardFuselage", "YokeColumn", "block", Vector3.new(0.08, 0.6 * scale, 0.08), CFrame.new(seatX, eye.Y - 0.85 * scale, yz), dark, o)
			add(ctx, "ForwardFuselage", "Yoke", "block", Vector3.new(0.36, 0.06, 0.06), CFrame.new(seatX, eye.Y - 0.52 * scale, yz - 0.03), black, o)
			for _, hx in { -1, 1 } do
				add(ctx, "ForwardFuselage", "Yoke", "block", Vector3.new(0.06, 0.16, 0.06), CFrame.new(seatX + hx * 0.18, eye.Y - 0.45 * scale, yz - 0.03), black, o)
			end
		end
		add(ctx, "ForwardFuselage", "Post", "block", Vector3.new(0.1, 0.85 * scale, 0.1), CFrame.new(0, eye.Y + 0.1, front - 0.05) * CFrame.Angles(math.rad(-28), 0, 0), black, o)
		add(ctx, "ForwardFuselage", "WindscreenFrame", "block", Vector3.new(hw * 1.7, 0.12, 0.12), CFrame.new(0, winTop + 0.05, front + 0.2), black, o)
		-- the windscreen itself, seen from inside: clear, lightly tinted glass
		local gy0, gy1 = eye.Y - 0.25, winTop + 0.05
		add(ctx, "ForwardFuselage", "WindscreenGlass", "block", Vector3.new(hw * 1.7, (gy1 - gy0) / math.cos(math.rad(28)), 0.03), CFrame.new(0, (gy0 + gy1) / 2, front + 0.05) * CFrame.Angles(math.rad(-28), 0, 0), GLASS, cockpitGlassOpts())
		-- glareshield and instrument panel
		add(ctx, "ForwardFuselage", "Glareshield", "block", Vector3.new(hw * 1.7, 0.14, 0.45 * scale), CFrame.new(0, eye.Y - 0.3, front + 0.25 * scale), black, o)
		cockpitPanel(ctx, "ForwardFuselage", Vector3.new(hw * 1.7, 0.75 * scale, 0.08), CFrame.new(0, eye.Y - 0.72 * scale, front + 0.42 * scale) * CFrame.Angles(math.rad(-12), 0, 0), dark, cp.panel or "screens", cp.screens or 4, o)
		-- centre pedestal with one thrust lever per engine
		add(ctx, "ForwardFuselage", "Pedestal", "block", Vector3.new(0.5 * scale, eye.Y - 0.85 * scale - floorY, 1.1 * scale), CFrame.new(0, (eye.Y - 0.85 * scale + floorY) / 2, front + 1.05 * scale), dark, o)
		local n = #ctx.cfg.engines
		for i = 1, n do
			local x = (i - (n + 1) / 2) * 0.09
			add(ctx, "ForwardFuselage", "ThrustLever", "block", Vector3.new(0.04, 0.22 * scale, 0.04), CFrame.new(x, eye.Y - 0.74 * scale, front + 0.8 * scale), Color3.fromRGB(220, 220, 225), o)
		end
	end

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
	buildFloats(ctx)
	buildCockpit(ctx)

	return model
end

return AircraftBuilder
