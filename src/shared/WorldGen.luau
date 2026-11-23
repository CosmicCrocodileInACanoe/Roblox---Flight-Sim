--!strict
-- Deterministic world height field and land-use rules (pure; studs).
-- Used by the server world builder and by tests that check, for example, that every
-- runway sits on flat ground above the sea.

local function req(name: string): any
	if script then
		return (require :: any)((script :: any).Parent[name])
	end
	return (require :: any)("./" .. name)
end
local Airports = req("Airports")

local WorldGen = {}

WorldGen.SEED = 1337
-- The whole land area (about 73 x 47 km). Past it the ocean carries on to the horizon.
WorldGen.BOUNDS = { minX = -130500, maxX = 130500, minZ = -99000, maxZ = 69000 }
-- The original core around both airports keeps the fine grid; the ring outside it uses
-- cells twice the size. Both grids line up on the core's edge.
WorldGen.INNER = { minX = -64500, maxX = 64500, minZ = -33000, maxZ = 33000 }
WorldGen.CELL = 1500 -- fine terrain grid spacing (studs)
WorldGen.COARSE = 3000 -- outer ring grid spacing (studs); must be 2 x CELL
WorldGen.SEA_LEVEL = 0
WorldGen.OPEN_SEA_DEPTH = -200 -- reported by meshHeight past the land bounds

-- Visibility: thin enough to see mountains and city skylines 20+ km away.
WorldGen.atmosphere = { density = 0.1, offset = 0.25, haze = 0.8, glare = 0.2 }

-- Cities (studs). Radius is the downtown radius; suburbs extend ~2x.
WorldGen.cities = {
	{ id = "harbor", name = "Harbor City", x = -40500, z = -6500, radius = 3600, maxHeight = 1050, base = 8, style = "metro" },
	{ id = "ridgeview", name = "Ridgeview", x = 47000, z = 8500, radius = 2400, maxHeight = 360, base = 640, style = "town" },
	-- Towns in the outer ring, so there is something to fly to past the two airports.
	-- `flat` widens the levelled area so the coarse grid's bigger cells come out flat.
	{ id = "pinecrest", name = "Pinecrest", x = -14000, z = -42000, flat = 6500, radius = 1500, maxHeight = 180, base = 150, style = "town" },
	{ id = "lakeview", name = "Lakeview", x = 80000, z = 36000, flat = 6500, radius = 1700, maxHeight = 240, base = 720, style = "town" },
	{ id = "westhaven", name = "Westhaven", x = -96000, z = -16000, flat = 6500, radius = 1500, maxHeight = 160, base = 120, style = "town" },
}

-- Value noise -----------------------------------------------------------------
local function hash(ix: number, iz: number, seed: number): number
	-- 2D lattice hash -> [0, 1). Classic sine hash; good enough for terrain.
	local v = math.sin(ix * 127.1 + iz * 311.7 + seed * 74.7) * 43758.5453
	return v - math.floor(v)
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

function WorldGen.valueNoise(x: number, z: number, seed: number): number
	local ix, iz = math.floor(x), math.floor(z)
	local fx, fz = smooth(x - ix), smooth(z - iz)
	local a = hash(ix, iz, seed)
	local b = hash(ix + 1, iz, seed)
	local c = hash(ix, iz + 1, seed)
	local d = hash(ix + 1, iz + 1, seed)
	local ab = a + (b - a) * fx
	local cd = c + (d - c) * fx
	return (ab + (cd - ab) * fz) * 2 - 1 -- [-1, 1]
end

function WorldGen.fbm(x: number, z: number, octaves: number, seed: number): number
	local sum, amp, freq, norm = 0, 1, 1, 0
	for i = 1, octaves do
		sum += WorldGen.valueNoise(x * freq, z * freq, seed + i * 31) * amp
		norm += amp
		amp *= 0.5
		freq *= 2.03
	end
	return sum / norm
end

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Coastline: sea is south of this z (larger z) in the western half of the map.
function WorldGen.coastZ(x: number): number
	return 6800 + 1600 * math.sin(x / 7800) + math.max(0, x + 16000) * 1.25
end

-- Flatten masks for airports and cities: returns (weight 0..1, targetHeight).
local function flattenMask(x: number, z: number): (number, number)
	local bestW, bestH = 0, 0
	for _, id in Airports.order do
		local l = Airports.layout(id)
		local along, cross = Airports.toRunway(l, x, z)
		local lat = cross * l.side
		-- airport rectangle: runway length + margins, from far side of runway to past the terminal
		local da = math.max(0, math.abs(along) - (l.halfLen + 3200))
		local dlo = math.max(0, -(l.halfWidth + 3000) - lat)
		local dhi = math.max(0, lat - (math.abs(l.terminalFar) + 3000))
		local dist = math.sqrt(da * da + (dlo + dhi) ^ 2)
		local w = 1 - smoothstep(0, 3500, dist)
		if w > bestW then
			bestW, bestH = w, l.y - 4 -- just under the airport ground slab
		end
	end
	for _, c in WorldGen.cities do
		local d = math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2)
		local flat = c.flat or c.radius * 1.6
		local w = 1 - smoothstep(flat, flat + c.radius, d)
		if w > bestW then
			bestW, bestH = w, c.base
		end
	end
	return bestW, bestH
end
WorldGen.flattenMask = flattenMask

-- Distance (studs) from (x, z) to the nearest edge of the land bounds; negative outside.
function WorldGen.edgeDistance(x: number, z: number): number
	local b = WorldGen.BOUNDS
	return math.min(x - b.minX, b.maxX - x, z - b.minZ, b.maxZ - z)
end

-- Natural terrain height before flattening.
function WorldGen.naturalHeight(x: number, z: number): number
	local s = WorldGen.SEED
	-- Gentle plateau rising from the coast toward Ridgeview.
	local plateau = smoothstep(-22000, 26000, x) * 600
	-- Rolling hills
	local hills = WorldGen.fbm(x / 9000, z / 9000, 4, s) * 260 + 120
	-- Mountains: the range north-east of Ridgeview, a tall northern range, eastern
	-- highlands and western fells. They give big silhouettes on the horizon.
	local ridge = 1 - math.abs(WorldGen.fbm(x / 7000, z / 7000, 4, s + 99))
	local northEast = smoothstep(-6000, -16000, z) * smoothstep(8000, 30000, x) * (1 - smoothstep(-40000, -52000, z))
	local north = smoothstep(-48000, -62000, z)
	local east = smoothstep(94000, 108000, x)
	local west = smoothstep(-100000, -112000, x) * (1 - smoothstep(4000, 12000, z))
	local mountains = math.clamp(northEast, 0, 1) * (ridge * ridge * 3800 + 400)
		+ math.clamp(north + east + west, 0, 1) * (ridge * ridge * 3400 + 450)
	local h = plateau + hills + mountains
	-- Coast: blend down below sea level south of the coastline.
	local coast = WorldGen.coastZ(x)
	local seaBlend = smoothstep(coast - 900, coast + 700, z)
	h = h * (1 - seaBlend) + (-60 - (z - coast) * 0.02) * seaBlend
	-- Map edge: the land runs down into the sea on every side, with a wobbly shoreline,
	-- so the world ends at a coast instead of a cliff into nothing.
	local edge = WorldGen.edgeDistance(x, z) + WorldGen.fbm(x / 11000, z / 11000, 3, s + 7) * 4500
	local edgeBlend = smoothstep(15000, 4000, edge)
	h = h * (1 - edgeBlend) - 180 * edgeBlend
	return h
end

-- Approach corridors: beyond each runway end the terrain is held under a 2.5% surface
-- (rising from the field elevation) so a 3 degree final keeps real obstacle clearance.
local APPROACH_SLOPE = 0.025
local function approachCap(x: number, z: number, h: number): number
	for _, id in Airports.order do
		local l = Airports.layout(id)
		local along, cross = Airports.toRunway(l, x, z)
		local beyond = math.abs(along) - l.halfLen
		if beyond > 0 and beyond < 40000 then
			local halfW = l.halfWidth + 900 + beyond * 0.15
			local lw = 1 - smoothstep(halfW, halfW + 1500, math.abs(cross))
			if lw > 0 then
				local cap = l.y - 4 + beyond * APPROACH_SLOPE
				if h > cap then
					h = h + (cap - h) * lw
				end
			end
		end
	end
	return h
end

function WorldGen.height(x: number, z: number): number
	local h = WorldGen.naturalHeight(x, z)
	local w, target = flattenMask(x, z)
	if w > 0.85 then
		h = target
	elseif w > 0 then
		h = h + (target - h) * w
	end
	return approachCap(x, z, h)
end

function WorldGen.isSea(x: number, z: number): boolean
	return WorldGen.height(x, z) < WorldGen.SEA_LEVEL
end

-- Grid vertex heights (cached) used by both the mesh builder and meshHeight().
-- Fine grid: CELL spacing over INNER. Vertices on INNER's edge with an odd index are
-- set to the average of their neighbours so they lie on the coarse cells' edges, which
-- keeps the seam between the two grids free of cracks.
local grid: { [number]: { [number]: number } }? = nil
local function buildGrid()
	local b, cell = WorldGen.INNER, WorldGen.CELL
	local g = {}
	local nx = math.ceil((b.maxX - b.minX) / cell)
	local nz = math.ceil((b.maxZ - b.minZ) / cell)
	for i = 0, nx do
		local col = {}
		for j = 0, nz do
			col[j] = WorldGen.height(b.minX + i * cell, b.minZ + j * cell)
		end
		g[i] = col
	end
	for i = 1, nx - 1, 2 do
		for _, j in { 0, nz } do
			g[i][j] = (g[i - 1][j] + g[i + 1][j]) / 2
		end
	end
	for j = 1, nz - 1, 2 do
		for _, i in { 0, nx } do
			g[i][j] = (g[i][j - 1] + g[i][j + 1]) / 2
		end
	end
	grid = g
	return g, nx, nz
end

function WorldGen.grid()
	local b, cell = WorldGen.INNER, WorldGen.CELL
	local nx = math.ceil((b.maxX - b.minX) / cell)
	local nz = math.ceil((b.maxZ - b.minZ) / cell)
	local g = grid or buildGrid()
	return g, nx, nz
end

-- Coarse grid over BOUNDS: corner heights g[i][j] and cell-centre heights c[i][j].
-- Each coarse cell is drawn as four triangles fanned from its centre, which keeps every
-- wedge part under Roblox's 2048-stud size limit. Cells inside INNER are not drawn.
local coarse: any = nil
local function buildCoarse()
	local b, cell = WorldGen.BOUNDS, WorldGen.COARSE
	local nx = math.ceil((b.maxX - b.minX) / cell)
	local nz = math.ceil((b.maxZ - b.minZ) / cell)
	local fine, fnx, fnz = WorldGen.grid()
	local inner, fcell = WorldGen.INNER, WorldGen.CELL
	local g, c = {}, {}
	for i = 0, nx do
		local col, cen = {}, {}
		for j = 0, nz do
			local x, z = b.minX + i * cell, b.minZ + j * cell
			-- Share the exact fine-grid height on the INNER edge.
			local fi, fj = (x - inner.minX) / fcell, (z - inner.minZ) / fcell
			if fi >= 0 and fi <= fnx and fj >= 0 and fj <= fnz and fi % 1 == 0 and fj % 1 == 0 then
				col[j] = fine[fi][fj]
			else
				col[j] = WorldGen.height(x, z)
			end
			if i < nx and j < nz then
				cen[j] = WorldGen.height(x + cell / 2, z + cell / 2)
			end
		end
		g[i], c[i] = col, cen
	end
	coarse = { g = g, c = c, nx = nx, nz = nz }
	return coarse
end

function WorldGen.coarseGrid(): any
	return coarse or buildCoarse()
end

-- True when the coarse cell (i, j) lies inside INNER (drawn by the fine grid instead).
function WorldGen.coarseCellIsInner(i: number, j: number): boolean
	local b, inner, cell = WorldGen.BOUNDS, WorldGen.INNER, WorldGen.COARSE
	local x0, z0 = b.minX + i * cell, b.minZ + j * cell
	return x0 >= inner.minX and x0 + cell <= inner.maxX and z0 >= inner.minZ and z0 + cell <= inner.maxZ
end

local function inRect(r: any, x: number, z: number): boolean
	return x >= r.minX and x <= r.maxX and z >= r.minZ and z <= r.maxZ
end

-- Height of the triangulated mesh at (x, z), matching what the builder generates.
-- Fine cells (i, j) are split along the diagonal from (i, j) to (i+1, j+1); coarse cells
-- are fanned from their centre. Past the land bounds this is open sea.
function WorldGen.meshHeight(x: number, z: number): number
	if inRect(WorldGen.INNER, x, z) then
		local b, cell = WorldGen.INNER, WorldGen.CELL
		local g, nx, nz = WorldGen.grid()
		local fx = (x - b.minX) / cell
		local fz = (z - b.minZ) / cell
		local i = math.clamp(math.floor(fx), 0, nx - 1)
		local j = math.clamp(math.floor(fz), 0, nz - 1)
		local u, v = fx - i, fz - j
		local h00, h10, h01, h11 = g[i][j], g[i + 1][j], g[i][j + 1], g[i + 1][j + 1]
		if u >= v then
			-- triangle (00, 10, 11)
			return h00 + (h10 - h00) * u + (h11 - h10) * v
		else
			-- triangle (00, 11, 01)
			return h00 + (h11 - h01) * u + (h01 - h00) * v
		end
	end
	if not inRect(WorldGen.BOUNDS, x, z) then
		return WorldGen.OPEN_SEA_DEPTH
	end
	local b, cell = WorldGen.BOUNDS, WorldGen.COARSE
	local cg = WorldGen.coarseGrid()
	local fx = (x - b.minX) / cell
	local fz = (z - b.minZ) / cell
	local i = math.clamp(math.floor(fx), 0, cg.nx - 1)
	local j = math.clamp(math.floor(fz), 0, cg.nz - 1)
	local u, v = fx - i, fz - j
	local g = cg.g
	local hc = cg.c[i][j]
	-- Pick the fan triangle (centre plus one cell edge) and interpolate barycentrically.
	local du, dv = u - 0.5, v - 0.5
	local ax, az, ah, bx, bz, bh
	if math.abs(du) >= math.abs(dv) then
		local ii = if du >= 0 then 1 else 0
		ax, az, ah = ii, 0, g[i + ii][j]
		bx, bz, bh = ii, 1, g[i + ii][j + 1]
	else
		local jj = if dv >= 0 then 1 else 0
		ax, az, ah = 0, jj, g[i][j + jj]
		bx, bz, bh = 1, jj, g[i + 1][j + jj]
	end
	-- Solve p = c + s (a - c) + t (b - c) with c = (0.5, 0.5).
	local e1x, e1z = ax - 0.5, az - 0.5
	local e2x, e2z = bx - 0.5, bz - 0.5
	local det = e1x * e2z - e2x * e1z
	local s = (du * e2z - e2x * dv) / det
	local t = (e1x * dv - du * e1z) / det
	return hc + s * (ah - hc) + t * (bh - hc)
end

-- Deterministic pseudo-random in [0,1) for placement decisions.
function WorldGen.rand(a: number, b: number, salt: number): number
	return hash(math.floor(a), math.floor(b), WorldGen.SEED + salt)
end

return WorldGen
