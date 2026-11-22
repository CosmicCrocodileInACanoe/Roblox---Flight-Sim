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
WorldGen.BOUNDS = { minX = -64500, maxX = 64500, minZ = -33000, maxZ = 33000 }
WorldGen.CELL = 1500 -- terrain triangle grid spacing (studs)
WorldGen.SEA_LEVEL = 0

-- Cities (studs). Radius is the downtown radius; suburbs extend ~2x.
WorldGen.cities = {
	{ id = "harbor", name = "Harbor City", x = -40500, z = -6500, radius = 3600, maxHeight = 1050, base = 8, style = "metro" },
	{ id = "ridgeview", name = "Ridgeview", x = 47000, z = 8500, radius = 2400, maxHeight = 360, base = 640, style = "town" },
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
		local w = 1 - smoothstep(c.radius * 1.6, c.radius * 2.6, d)
		if w > bestW then
			bestW, bestH = w, c.base
		end
	end
	return bestW, bestH
end
WorldGen.flattenMask = flattenMask

-- Natural terrain height before flattening.
function WorldGen.naturalHeight(x: number, z: number): number
	local s = WorldGen.SEED
	-- Gentle plateau rising from the coast toward Ridgeview.
	local plateau = smoothstep(-22000, 26000, x) * 600
	-- Rolling hills
	local hills = WorldGen.fbm(x / 9000, z / 9000, 4, s) * 260 + 120
	-- Mountains: north-east range and map-edge ranges that close the world visually.
	local ridge = 1 - math.abs(WorldGen.fbm(x / 7000, z / 7000, 4, s + 99))
	local northEast = smoothstep(-6000, -16000, z) * smoothstep(8000, 30000, x)
	local east = smoothstep(56000, 63000, x)
	local north = smoothstep(-24000, -32000, z)
	local west = smoothstep(-56000, -63000, x) * (1 - smoothstep(4000, 12000, z))
	local mountainMask = math.clamp(northEast + east + north + west, 0, 1)
	local mountains = mountainMask * (ridge * ridge * 3800 + 400)
	local h = plateau + hills + mountains
	-- Coast: blend down below sea level south of the coastline.
	local coast = WorldGen.coastZ(x)
	local seaBlend = smoothstep(coast - 900, coast + 700, z)
	h = h * (1 - seaBlend) + (-60 - (z - coast) * 0.02) * seaBlend
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
local grid: { [number]: { [number]: number } }? = nil
local function buildGrid()
	local b, cell = WorldGen.BOUNDS, WorldGen.CELL
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
	grid = g
	return g, nx, nz
end

function WorldGen.grid()
	local b, cell = WorldGen.BOUNDS, WorldGen.CELL
	local nx = math.ceil((b.maxX - b.minX) / cell)
	local nz = math.ceil((b.maxZ - b.minZ) / cell)
	local g = grid or buildGrid()
	return g, nx, nz
end

-- Height of the triangulated mesh at (x, z), matching what the builder generates.
-- Each cell (i, j) is split along the diagonal from (i, j) to (i+1, j+1).
function WorldGen.meshHeight(x: number, z: number): number
	local b, cell = WorldGen.BOUNDS, WorldGen.CELL
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

-- Deterministic pseudo-random in [0,1) for placement decisions.
function WorldGen.rand(a: number, b: number, salt: number): number
	return hash(math.floor(a), math.floor(b), WorldGen.SEED + salt)
end

return WorldGen
