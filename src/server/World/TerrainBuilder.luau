--!strict
-- Low-poly terrain mesh, seabed and sea surface built from the shared height field.
-- Using anchored parts (instead of voxel Terrain) keeps memory predictable over a
-- 36 x 18 km area and gives the stylised faceted look.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldGen = require(Shared.WorldGen)
local Geometry = require(script.Parent.Geometry)

local TerrainBuilder = {}

local THICKNESS = 30

local GRASS = {
	Color3.fromRGB(104, 146, 74),
	Color3.fromRGB(118, 156, 80),
	Color3.fromRGB(96, 134, 66),
	Color3.fromRGB(140, 160, 86), -- dry field
	Color3.fromRGB(124, 150, 70),
}
local FOREST = Color3.fromRGB(70, 104, 56)
local ROCK = Color3.fromRGB(118, 112, 104)
local SNOW = Color3.fromRGB(238, 241, 245)
local SAND = Color3.fromRGB(214, 200, 150)
local SEABED = Color3.fromRGB(84, 110, 120)

local function pickColor(h: number, slope: number, x: number, z: number): (Color3, Enum.Material)
	if h < 6 then
		return if h < -8 then SEABED else SAND, Enum.Material.Sand
	end
	if h > 3000 + WorldGen.rand(x / 900, z / 900, 7) * 500 then
		return SNOW, Enum.Material.Snow
	end
	if slope > 0.55 or h > 2300 then
		return ROCK:Lerp(Color3.fromRGB(100, 96, 90), WorldGen.rand(x, z, 3)), Enum.Material.Slate
	end
	local n = WorldGen.fbm(x / 5000, z / 5000, 2, 77)
	if n > 0.25 then
		return FOREST, Enum.Material.Grass
	end
	local idx = 1 + math.floor(WorldGen.rand(x / 1500, z / 1500, 11) * #GRASS)
	return GRASS[math.clamp(idx, 1, #GRASS)], Enum.Material.Grass
end

function TerrainBuilder.build(parent: Instance): number
	local folder = Instance.new("Folder")
	folder.Name = "Terrain"
	folder.Parent = parent
	local b, cell = WorldGen.BOUNDS, WorldGen.CELL
	local g, nx, nz = WorldGen.grid()
	local count = 0
	local yieldEvery = 400

	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local x0, z0 = b.minX + i * cell, b.minZ + j * cell
			local h00, h10, h01, h11 = g[i][j], g[i + 1][j], g[i][j + 1], g[i + 1][j + 1]
			local hmax = math.max(h00, h10, h01, h11)
			local hmin = math.min(h00, h10, h01, h11)
			if hmax < -110 then
				continue -- deep sea: covered by the seabed slab
			end
			local cx, cz = x0 + cell / 2, z0 + cell / 2
			if hmax - hmin < 0.01 then
				local color, mat = pickColor(h00, 0, cx, cz)
				Geometry.part({
					Name = "Flat",
					Size = Vector3.new(cell + 0.05, THICKNESS, cell + 0.05),
					CFrame = CFrame.new(cx, h00 - THICKNESS / 2, cz),
					Color = color,
					Material = mat,
					Parent = folder,
				})
				count += 1
			else
				local p00 = Vector3.new(x0, h00, z0)
				local p10 = Vector3.new(x0 + cell, h10, z0)
				local p01 = Vector3.new(x0, h01, z0 + cell)
				local p11 = Vector3.new(x0 + cell, h11, z0 + cell)
				-- Two triangles split along 00-11 (matches WorldGen.meshHeight).
				local tris = { { p00, p10, p11 }, { p00, p11, p01 } }
				for _, t in tris do
					local n = (t[2] - t[1]):Cross(t[3] - t[1]).Unit
					local slope = 1 - math.abs(n.Y)
					local avgH = (t[1].Y + t[2].Y + t[3].Y) / 3
					local color, mat = pickColor(avgH, slope, cx + i, cz + j)
					Geometry.triangle(t[1], t[2], t[3], THICKNESS, { Name = "Tri", Color = color, Material = mat }, folder)
					count += 2
				end
			end
			if count % yieldEvery < 4 then
				task.wait()
			end
		end
	end

	-- Seabed and sea surface.
	local sea = Instance.new("Folder")
	sea.Name = "Sea"
	sea.Parent = parent
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local h00, h10, h01, h11 = g[i][j], g[i + 1][j], g[i][j + 1], g[i + 1][j + 1]
			if math.min(h00, h10, h01, h11) < 0.5 then
				local cx, cz = b.minX + (i + 0.5) * cell, b.minZ + (j + 0.5) * cell
				Geometry.part({
					Name = "Water",
					Size = Vector3.new(cell + 0.05, 2, cell + 0.05),
					CFrame = CFrame.new(cx, WorldGen.SEA_LEVEL - 1, cz),
					Color = Color3.fromRGB(40, 104, 150),
					Material = Enum.Material.Glass,
					Transparency = 0.25,
					Reflectance = 0.12,
					CanCollide = false,
					CanQuery = false,
					CanTouch = false,
					CastShadow = false,
					Parent = sea,
				})
				count += 1
				if math.max(h00, h10, h01, h11) < -110 then
					Geometry.part({
						Name = "Seabed",
						Size = Vector3.new(cell + 0.05, 20, cell + 0.05),
						CFrame = CFrame.new(cx, -120, cz),
						Color = SEABED,
						Material = Enum.Material.Sand,
						Parent = sea,
					})
					count += 1
				end
			end
		end
	end
	return count
end

return TerrainBuilder
