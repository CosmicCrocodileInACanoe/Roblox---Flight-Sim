--!strict
-- Geometry helpers for anchored world construction.

local Geometry = {}

local MAX = 2000 -- stay under Roblox's 2048-stud part size limit

function Geometry.part(props: { [string]: any }): BasePart
	local className = props.ClassName or "Part"
	local p = Instance.new(className) :: any
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		if k ~= "ClassName" and k ~= "Parent" then
			p[k] = v
		end
	end
	if props.Parent then
		p.Parent = props.Parent
	end
	return p
end

-- Decorative (non-colliding, not hit by gear rays) part.
function Geometry.decal(props: { [string]: any }): BasePart
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	props.CastShadow = false
	return Geometry.part(props)
end

-- Tile a rectangle given in a local frame `frame` (CFrame at the rectangle's reference
-- point, X = "along", Z = "lateral") from (a0, l0) to (a1, l1), top surface at frame Y + top.
function Geometry.tiledRect(frame: CFrame, a0: number, a1: number, l0: number, l1: number, top: number, thickness: number, props: { [string]: any }, parent: Instance)
	if a1 < a0 then
		a0, a1 = a1, a0
	end
	if l1 < l0 then
		l0, l1 = l1, l0
	end
	local na = math.max(1, math.ceil((a1 - a0) / MAX))
	local nl = math.max(1, math.ceil((l1 - l0) / MAX))
	local da, dl = (a1 - a0) / na, (l1 - l0) / nl
	local parts = {}
	for i = 0, na - 1 do
		for j = 0, nl - 1 do
			local ca = a0 + da * (i + 0.5)
			local cl = l0 + dl * (j + 0.5)
			local p = table.clone(props)
			p.Size = Vector3.new(da + 0.02, thickness, dl + 0.02)
			p.CFrame = frame * CFrame.new(ca, top - thickness / 2, cl)
			p.Parent = parent
			table.insert(parts, Geometry.part(p))
		end
	end
	return parts
end

local WEDGE_MAX = 2040 -- Roblox clamps parts at 2048 studs per axis

-- Draw a 3D triangle with two WedgeParts (well-known technique), extruded `thickness`
-- studs downward (away from the side whose normal points up). A triangle too big for
-- one pair of wedges is split into four at its edge midpoints (same plane, no cracks).
-- Returns the number of parts made.
function Geometry.triangle(a: Vector3, b: Vector3, c: Vector3, thickness: number, props: { [string]: any }, parent: Instance): number
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- Make bc the longest edge (opposite a).
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 0.05 or right ~= right then
		return 0
	end
	if math.max(height, math.abs(ab:Dot(back)), math.abs(ac:Dot(back))) > WEDGE_MAX then
		local mab, mbc, mca = (a + b) / 2, (b + c) / 2, (c + a) / 2
		return Geometry.triangle(a, mab, mca, thickness, props, parent)
			+ Geometry.triangle(mab, b, mbc, thickness, props, parent)
			+ Geometry.triangle(mca, mbc, c, thickness, props, parent)
			+ Geometry.triangle(mab, mbc, mca, thickness, props, parent)
	end
	local normalUp = if right.Y >= 0 then right else -right
	local offset = -normalUp * (thickness / 2)

	local p1 = table.clone(props)
	p1.ClassName = "WedgePart"
	p1.Size = Vector3.new(thickness, height, math.abs(ab:Dot(back)))
	p1.CFrame = CFrame.fromMatrix((a + b) / 2 + offset, right, up, back)
	p1.Parent = parent
	Geometry.part(p1)

	local p2 = table.clone(props)
	p2.ClassName = "WedgePart"
	p2.Size = Vector3.new(thickness, height, math.abs(ac:Dot(back)))
	p2.CFrame = CFrame.fromMatrix((a + c) / 2 + offset, -right, up, -back)
	p2.Parent = parent
	Geometry.part(p2)
	return 2
end

-- A beam-like part from p0 to p1 with the given width/height.
function Geometry.segment(p0: Vector3, p1: Vector3, width: number, height: number, props: { [string]: any }, parent: Instance): BasePart?
	local d = p1 - p0
	local len = d.Magnitude
	if len < 0.1 then
		return nil
	end
	local p = table.clone(props)
	p.Size = Vector3.new(width, height, len)
	p.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
	p.Parent = parent
	return Geometry.part(p)
end

-- Text on the top face of a flat part.
function Geometry.groundText(cf: CFrame, sizeX: number, sizeZ: number, text: string, color: Color3, parent: Instance): BasePart
	local p = Geometry.decal({
		Name = "Text_" .. text,
		Size = Vector3.new(sizeX, 0.1, sizeZ),
		CFrame = cf,
		Transparency = 1,
		Parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 4
	gui.LightInfluence = 1
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	gui.Parent = p
	return p
end

-- Text on a vertical face (signs).
function Geometry.signText(part: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 12
	gui.LightInfluence = 0.6
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if bg then 0 else 1
	label.BackgroundColor3 = bg or Color3.new()
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	gui.Parent = part
end

return Geometry
