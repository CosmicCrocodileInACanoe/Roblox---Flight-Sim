--!strict
-- Low-poly terrain mesh, seabed and sea surface built from the shared height field.
-- Using anchored parts (instead of voxel Terrain) keeps memory predictable over a
-- 73 x 47 km area and gives the stylised faceted look. The 36 x 18 km core around the
-- airports uses the fine grid; the outer ring uses cells twice the size. The sea is a
-- handful of mesh-scaled tiles that run on past the land to the horizon.

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

local function terrainProps(color: Color3, mat: Enum.Material, shadow: boolean?): { [string]: any }
	return { Name = "Tri", Color = color, Material = mat, CastShadow = shadow ~= false }
end

-- Skip land below this: the opaque sea surface hides it.
local HIDDEN_BELOW = -6

local function buildFine(folder: Instance): number
	local b, cell = WorldGen.INNER, WorldGen.CELL
	local g, nx, nz = WorldGen.grid()
	local count = 0
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local x0, z0 = b.minX + i * cell, b.minZ + j * cell
			local h00, h10, h01, h11 = g[i][j], g[i + 1][j], g[i][j + 1], g[i + 1][j + 1]
			local hmax = math.max(h00, h10, h01, h11)
			local hmin = math.min(h00, h10, h01, h11)
			local cx, cz = x0 + cell / 2, z0 + cell / 2
			if hmax < HIDDEN_BELOW then
				-- Under water: an invisible floor so a ditched aircraft still finds the bottom.
				Geometry.part({
					Name = "Seabed",
					Size = Vector3.new(cell + 0.05, 20, cell + 0.05),
					CFrame = CFrame.new(cx, math.min(hmax, -60) - 10, cz),
					Transparency = 1,
					CastShadow = false,
					Parent = folder,
				})
				count += 1
			elseif hmax - hmin < 0.01 then
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
					count += Geometry.triangle(t[1], t[2], t[3], THICKNESS, terrainProps(color, mat), folder)
				end
			end
			if count % 400 < 4 then
				task.wait()
			end
		end
	end
	return count
end

local function buildCoarse(folder: Instance): number
	local b, cell = WorldGen.BOUNDS, WorldGen.COARSE
	local cg = WorldGen.coarseGrid()
	local g, c = cg.g, cg.c
	local count = 0
	for i = 0, cg.nx - 1 do
		for j = 0, cg.nz - 1 do
			if WorldGen.coarseCellIsInner(i, j) then
				continue
			end
			local x0, z0 = b.minX + i * cell, b.minZ + j * cell
			local h00, h10, h01, h11, hc = g[i][j], g[i + 1][j], g[i][j + 1], g[i + 1][j + 1], c[i][j]
			if math.max(h00, h10, h01, h11, hc) < HIDDEN_BELOW then
				continue -- open water: the sea surface covers it
			end
			local p00 = Vector3.new(x0, h00, z0)
			local p10 = Vector3.new(x0 + cell, h10, z0)
			local p01 = Vector3.new(x0, h01, z0 + cell)
			local p11 = Vector3.new(x0 + cell, h11, z0 + cell)
			local pc = Vector3.new(x0 + cell / 2, hc, z0 + cell / 2)
			-- Four triangles fanned from the centre (matches WorldGen.meshHeight).
			local tris = { { p00, p10, pc }, { p10, p11, pc }, { p11, p01, pc }, { p01, p00, pc } }
			for k, t in tris do
				local avgH = (t[1].Y + t[2].Y + t[3].Y) / 3
				if math.max(t[1].Y, t[2].Y, t[3].Y) < HIDDEN_BELOW then
					continue
				end
				local n = (t[2] - t[1]):Cross(t[3] - t[1]).Unit
				local slope = 1 - math.abs(n.Y)
				local color, mat = pickColor(avgH, slope, pc.X + i * 4 + k, pc.Z + j)
				-- Outer ring: no shadows, which saves render time on far-away hills.
				count += Geometry.triangle(t[1], t[2], t[3], THICKNESS, terrainProps(color, mat, false), folder)
			end
			if count % 400 < 8 then
				task.wait()
			end
		end
	end
	return count
end

-- Sea surface: 2048-stud parts whose block meshes are scaled up, laid as a grid so the
-- ocean reaches the horizon in every direction for a few dozen parts. Non-colliding;
-- water contact comes from WorldGen.meshHeight in the flight model.
local SEA_TILE = 2048
local SEA_SCALE = 40 -- each tile shows as about 82 x 82 km
local SEA_TILES = 5 -- 5 x 5 tiles: about 410 km across
local function buildSea(folder: Instance): number
	local span = SEA_TILE * SEA_SCALE
	local count = 0
	for i = 0, SEA_TILES - 1 do
		for j = 0, SEA_TILES - 1 do
			local cx = (i - (SEA_TILES - 1) / 2) * span
			local cz = (j - (SEA_TILES - 1) / 2) * span
			local p = Geometry.decal({
				Name = "Water",
				Size = Vector3.new(SEA_TILE, 1, SEA_TILE),
				CFrame = CFrame.new(cx, WorldGen.SEA_LEVEL - 0.5, cz),
				Color = Color3.fromRGB(38, 100, 146),
				Material = Enum.Material.SmoothPlastic,
				Reflectance = 0.18,
				Parent = folder,
			})
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Brick
			mesh.Scale = Vector3.new(SEA_SCALE, 1, SEA_SCALE)
			mesh.Parent = p
			count += 1
		end
	end
	return count
end

-- Two stages so players can fly sooner: the detailed land around the airports and
-- cities first, then the far ring and the open sea (built while people already fly).
function TerrainBuilder.buildNear(parent: Instance): number
	local folder = parent:FindFirstChild("Terrain") or Instance.new("Folder")
	folder.Name = "Terrain"
	folder.Parent = parent
	return buildFine(folder)
end

function TerrainBuilder.buildFar(parent: Instance): number
	local folder = parent:FindFirstChild("Terrain") or Instance.new("Folder")
	folder.Name = "Terrain"
	folder.Parent = parent
	local count = buildCoarse(folder)
	local sea = Instance.new("Folder")
	sea.Name = "Sea"
	sea.Parent = parent
	count += buildSea(sea)
	return count
end

function TerrainBuilder.build(parent: Instance): number
	return TerrainBuilder.buildNear(parent) + TerrainBuilder.buildFar(parent)
end

return TerrainBuilder
