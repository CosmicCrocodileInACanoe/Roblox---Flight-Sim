--!strict
-- Procedural cities, suburbs, the highway between them, and forests.
-- Everything is deterministic (seeded) so every server builds the same world.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldGen = require(Shared.WorldGen)
local Airports = require(Shared.Airports)
local Geometry = require(script.Parent.Geometry)

local CityBuilder = {}

local TOWER_COLORS = {
	Color3.fromRGB(120, 150, 175), Color3.fromRGB(90, 110, 130), Color3.fromRGB(160, 170, 180),
	Color3.fromRGB(70, 90, 110), Color3.fromRGB(180, 190, 200), Color3.fromRGB(110, 130, 150),
}
local LOW_COLORS = {
	Color3.fromRGB(196, 186, 168), Color3.fromRGB(170, 160, 150), Color3.fromRGB(210, 205, 195),
	Color3.fromRGB(150, 140, 130), Color3.fromRGB(184, 150, 120), Color3.fromRGB(205, 190, 160),
}
local ROOF_COLORS = { Color3.fromRGB(150, 70, 60), Color3.fromRGB(90, 90, 96), Color3.fromRGB(120, 90, 70) }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function groundY(x: number, z: number, worldFolder: Instance): number?
	rayParams.FilterDescendantsInstances = { worldFolder }
	local r = Workspace:Raycast(Vector3.new(x, 6000, z), Vector3.new(0, -7000, 0), rayParams)
	return if r then r.Position.Y else nil
end

local function inAirport(x: number, z: number, margin: number): boolean
	for _, id in Airports.order do
		local l = Airports.layout(id)
		local along, cross = Airports.toRunway(l, x, z)
		local latv = cross * l.side
		if math.abs(along) < l.halfLen + 3500 + margin and latv > -(l.halfWidth + 900 + margin) and latv < math.abs(l.terminalFar) + 900 + margin then
			return true
		end
		-- keep approach paths clear (6 km each way)
		if math.abs(cross) < 600 + margin and math.abs(along) < l.halfLen + 21000 then
			return true
		end
	end
	return false
end
CityBuilder.inAirport = inAirport

local function buildCity(c: any, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "City_" .. c.id
	model.Parent = parent
	local block, street = 300, 56
	local pitch = block + street
	local r = c.radius
	local n = math.ceil(r / pitch)
	-- street grid ground
	local frame = CFrame.new(c.x, c.base, c.z)
	Geometry.tiledRect(frame, -n * pitch - street, n * pitch + street, -n * pitch - street, n * pitch + street, 0.6, 2, {
		Name = "Streets", Color = Color3.fromRGB(70, 72, 76), Material = Enum.Material.Asphalt,
	}, model)
	local count = 0
	for i = -n, n do
		for j = -n, n do
			local bx, bz = c.x + i * pitch, c.z + j * pitch
			local d = math.sqrt((bx - c.x) ^ 2 + (bz - c.z) ^ 2)
			if d > r then
				continue
			end
			local rnd = WorldGen.rand(bx, bz, 21)
			-- sidewalk / plot
			Geometry.part({
				Name = "Plot", Size = Vector3.new(block, 1, block), CFrame = CFrame.new(bx, c.base + 1.1, bz),
				Color = Color3.fromRGB(150, 150, 146), Material = Enum.Material.Concrete, CastShadow = false, Parent = model,
			})
			if rnd < 0.08 and d > r * 0.25 then
				-- park
				Geometry.part({
					Name = "Park", Size = Vector3.new(block - 20, 1, block - 20), CFrame = CFrame.new(bx, c.base + 1.6, bz),
					Color = Color3.fromRGB(96, 150, 80), Material = Enum.Material.Grass, CastShadow = false, Parent = model,
				})
				continue
			end
			local falloff = math.exp(-((d / r) ^ 2) * 2.8)
			local h = math.max(40, c.maxHeight * falloff * (0.35 + 0.65 * WorldGen.rand(bx, bz, 22)))
			if c.style == "town" then
				h = math.max(30, h * 0.8)
			end
			local fw = 150 + 110 * WorldGen.rand(bx, bz, 23)
			local fd = 150 + 110 * WorldGen.rand(bx, bz, 24)
			local tall = h > 260
			local colors = if tall then TOWER_COLORS else LOW_COLORS
			local color = colors[1 + math.floor(WorldGen.rand(bx, bz, 25) * #colors) % #colors]
			local y0 = c.base + 1.6
			Geometry.part({
				Name = "Building", Size = Vector3.new(fw, h, fd), CFrame = CFrame.new(bx, y0 + h / 2, bz),
				Color = color, Material = if tall then Enum.Material.Glass else Enum.Material.Concrete,
				Reflectance = if tall then 0.12 else 0, Parent = model,
			})
			count += 1
			if tall and WorldGen.rand(bx, bz, 26) > 0.4 then
				-- setback crown
				local h2 = h * (0.12 + 0.18 * WorldGen.rand(bx, bz, 27))
				Geometry.part({
					Name = "Crown", Size = Vector3.new(fw * 0.62, h2, fd * 0.62), CFrame = CFrame.new(bx, y0 + h + h2 / 2, bz),
					Color = color:Lerp(Color3.new(1, 1, 1), 0.15), Material = Enum.Material.Glass, Reflectance = 0.12, Parent = model,
				})
				h += h2
				count += 1
			end
			if h > 400 then
				-- aviation obstruction light
				Geometry.decal({
					Name = "ObstructionLight", Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(bx, y0 + h + 2, bz),
					Color = Color3.fromRGB(255, 30, 30), Material = Enum.Material.Neon, Parent = model,
				})
			elseif not tall and WorldGen.rand(bx, bz, 28) > 0.5 then
				Geometry.part({
					Name = "RoofUnit", Size = Vector3.new(30, 12, 24), CFrame = CFrame.new(bx + 20, y0 + h + 6, bz - 15),
					Color = Color3.fromRGB(120, 120, 124), Material = Enum.Material.Metal, Parent = model,
				})
			end
		end
	end
	if c.style == "metro" then
		-- Landmark: the Harbor Spire.
		local y0 = c.base + 1.6
		Geometry.part({
			Name = "SpireBase", Size = Vector3.new(220, 900, 220), CFrame = CFrame.new(c.x, y0 + 450, c.z),
			Color = Color3.fromRGB(150, 175, 195), Material = Enum.Material.Glass, Reflectance = 0.2, Parent = model,
		})
		Geometry.part({
			Name = "SpireTop", Size = Vector3.new(120, 260, 120), CFrame = CFrame.new(c.x, y0 + 900 + 130, c.z),
			Color = Color3.fromRGB(200, 215, 230), Material = Enum.Material.Glass, Reflectance = 0.2, Parent = model,
		})
		Geometry.part({
			Name = "SpireMast", Size = Vector3.new(10, 220, 10), CFrame = CFrame.new(c.x, y0 + 1160 + 110, c.z),
			Color = Color3.fromRGB(220, 220, 220), Material = Enum.Material.Metal, Parent = model,
		})
		Geometry.decal({
			Name = "ObstructionLight", Size = Vector3.new(6, 6, 6), CFrame = CFrame.new(c.x, y0 + 1385, c.z),
			Color = Color3.fromRGB(255, 30, 30), Material = Enum.Material.Neon, Parent = model,
		})
	end
	return model, count
end

local function buildSuburbs(c: any, parent: Instance, worldFolder: Instance)
	local model = Instance.new("Model")
	model.Name = "Suburbs_" .. c.id
	model.Parent = parent
	local inner, outer = c.radius * 1.15, c.radius * 2.3
	local stepSize = 170
	local count = 0
	local x = c.x - outer
	while x <= c.x + outer do
		local z = c.z - outer
		while z <= c.z + outer do
			local d = math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2)
			local jx = x + (WorldGen.rand(x, z, 31) - 0.5) * 80
			local jz = z + (WorldGen.rand(x, z, 32) - 0.5) * 80
			if d > inner and d < outer and WorldGen.rand(x, z, 33) < 0.55 * (1 - (d - inner) / (outer - inner)) + 0.15 and not inAirport(jx, jz, 200) then
				local gy = groundY(jx, jz, worldFolder)
				if gy and gy > 4 then
					local w = 34 + 20 * WorldGen.rand(x, z, 34)
					local dpt = 28 + 16 * WorldGen.rand(x, z, 35)
					local h = 18 + 10 * WorldGen.rand(x, z, 36)
					local rot = CFrame.Angles(0, math.floor(WorldGen.rand(x, z, 37) * 4) * math.pi / 2, 0)
					local base = CFrame.new(jx, gy, jz) * rot
					Geometry.part({
						Name = "House", Size = Vector3.new(w, h, dpt), CFrame = base * CFrame.new(0, h / 2, 0),
						Color = LOW_COLORS[1 + math.floor(WorldGen.rand(x, z, 38) * #LOW_COLORS) % #LOW_COLORS],
						Material = Enum.Material.SmoothPlastic, Parent = model,
					})
					-- pitched roof from two wedges
					local roofColor = ROOF_COLORS[1 + math.floor(WorldGen.rand(x, z, 39) * #ROOF_COLORS) % #ROOF_COLORS]
					local rh = 10
					for _, s in { -1, 1 } do
						Geometry.part({
							ClassName = "WedgePart", Name = "Roof", Size = Vector3.new(w + 2, rh, dpt / 2 + 1),
							CFrame = base * CFrame.new(0, h + rh / 2, s * (dpt / 4)) * CFrame.Angles(0, if s > 0 then 0 else math.pi, 0),
							Color = roofColor, Parent = model,
						})
					end
					count += 3
				end
			end
			z += stepSize
		end
		x += stepSize
		task.wait()
	end
	return model, count
end

local HIGHWAY = {
	Vector3.new(-37000, 0, -4200),
	Vector3.new(-30000, 0, -3600),
	Vector3.new(-20000, 0, -2400),
	Vector3.new(-9000, 0, -3600),
	Vector3.new(2000, 0, -4400),
	Vector3.new(14000, 0, -2600),
	Vector3.new(26000, 0, 1800),
	Vector3.new(36000, 0, 5200),
	Vector3.new(44500, 0, 7600),
}

local function buildHighway(parent: Instance, worldFolder: Instance)
	local model = Instance.new("Model")
	model.Name = "Highway"
	model.Parent = parent
	local pts = {}
	for i = 1, #HIGHWAY - 1 do
		local a, b = HIGHWAY[i], HIGHWAY[i + 1]
		local d = (b - a).Magnitude
		local n = math.ceil(d / 260)
		for k = 0, n - 1 do
			local p = a:Lerp(b, k / n)
			table.insert(pts, p)
		end
	end
	table.insert(pts, HIGHWAY[#HIGHWAY])
	local count = 0
	local prev: Vector3? = nil
	for _, p in pts do
		local gy = groundY(p.X, p.Z, worldFolder)
		if gy then
			local q = Vector3.new(p.X, math.max(gy, 2) + 1.2, p.Z)
			if prev then
				Geometry.segment(prev, q, 64, 2.4, { Name = "Road", Color = Color3.fromRGB(60, 62, 66), Material = Enum.Material.Asphalt, CastShadow = false }, model)
				local mid = (prev + q) / 2 + Vector3.new(0, 1.25, 0)
				Geometry.segment(mid - (q - prev) * 0.2, mid + (q - prev) * 0.2, 1.4, 0.1, { Name = "Dash", Color = Color3.fromRGB(235, 235, 235), CanCollide = false, CanQuery = false, CastShadow = false }, model)
				count += 2
			end
			prev = q
		end
	end
	return model, count
end

local function buildForests(parent: Instance, worldFolder: Instance)
	local model = Instance.new("Model")
	model.Name = "Forests"
	model.Parent = parent
	local b = WorldGen.BOUNDS
	local count = 0
	local maxTrees = 1200
	local spacing = 1800
	local x = b.minX + 2000
	while x < b.maxX - 2000 and count < maxTrees * 2 do
		local z = b.minZ + 2000
		while z < b.maxZ - 2000 do
			local forest = WorldGen.fbm(x / 5000, z / 5000, 2, 77)
			if forest > 0.18 then
				-- a small clump of 3 trees
				for t = 1, 3 do
					local tx = x + (WorldGen.rand(x, z, 40 + t) - 0.5) * 700
					local tz = z + (WorldGen.rand(x, z, 50 + t) - 0.5) * 700
					if inAirport(tx, tz, 0) then
						continue
					end
					local near = false
					for _, c in WorldGen.cities do
						if (tx - c.x) ^ 2 + (tz - c.z) ^ 2 < (c.radius * 2.4) ^ 2 then
							near = true
						end
					end
					if near then
						continue
					end
					local h = WorldGen.height(tx, tz)
					if h < 10 or h > 2300 then
						continue
					end
					local gy = groundY(tx, tz, worldFolder)
					if not gy then
						continue
					end
					local scale = 0.8 + WorldGen.rand(tx, tz, 60) * 0.8
					local trunkH = 16 * scale
					Geometry.part({
						ClassName = "Part", Name = "Trunk", Shape = Enum.PartType.Cylinder,
						Size = Vector3.new(trunkH, 3 * scale, 3 * scale),
						CFrame = CFrame.new(tx, gy + trunkH / 2, tz) * CFrame.Angles(0, 0, math.rad(90)),
						Color = Color3.fromRGB(96, 70, 50), Material = Enum.Material.Wood, Parent = model,
					})
					Geometry.part({
						ClassName = "Part", Name = "Canopy", Shape = Enum.PartType.Ball,
						Size = Vector3.one * (26 * scale),
						CFrame = CFrame.new(tx, gy + trunkH + 9 * scale, tz),
						Color = Color3.fromRGB(56 + math.floor(30 * WorldGen.rand(tx, tz, 61)), 100, 50),
						Material = Enum.Material.Grass, Parent = model,
					})
					count += 2
				end
			end
			z += spacing
		end
		x += spacing
		task.wait()
	end
	return model, count
end

function CityBuilder.build(parent: Instance, worldFolder: Instance): number
	local total = 0
	for _, c in WorldGen.cities do
		local _, n = buildCity(c, parent)
		total += n
		local _, s = buildSuburbs(c, parent, worldFolder)
		total += s
	end
	local _, hw = buildHighway(parent, worldFolder)
	total += hw
	local _, f = buildForests(parent, worldFolder)
	total += f
	return total
end

return CityBuilder
