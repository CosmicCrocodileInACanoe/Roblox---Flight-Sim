--!strict
-- Grid of detail tiles (pure). The server files up-close detail (houses, trees, windows,
-- rooftop clutter) into tiles; the client shows only the tiles near the camera.

local DetailTiles = {}

DetailTiles.TILE = 4000 -- studs per tile side
DetailTiles.LOAD_RADIUS = 9000 -- ~2.5 km: tiles closer than this are shown
DetailTiles.UNLOAD_RADIUS = 11000 -- hysteresis so tiles don't flicker at the edge
DetailTiles.MAX_PER_TICK = 2

function DetailTiles.tileIndex(x: number, z: number): (number, number)
	return math.floor(x / DetailTiles.TILE), math.floor(z / DetailTiles.TILE)
end

function DetailTiles.tileKey(x: number, z: number): string
	local i, j = DetailTiles.tileIndex(x, z)
	return i .. "," .. j
end

function DetailTiles.parseKey(key: string): (number, number)
	local a, b = string.match(key, "^(-?%d+),(-?%d+)$")
	assert(a and b, "bad tile key " .. key)
	return tonumber(a) :: number, tonumber(b) :: number
end

function DetailTiles.tileCenter(key: string): (number, number)
	local i, j = DetailTiles.parseKey(key)
	local t = DetailTiles.TILE
	return (i + 0.5) * t, (j + 0.5) * t
end

-- Distance from the camera to the nearest point of the tile's footprint, counting the
-- camera's height above the tile's ground (so climbing away unloads detail too).
function DetailTiles.distance(key: string, camX: number, camY: number, camZ: number, groundY: number?): number
	local i, j = DetailTiles.parseKey(key)
	local t = DetailTiles.TILE
	local nx = math.clamp(camX, i * t, (i + 1) * t)
	local nz = math.clamp(camZ, j * t, (j + 1) * t)
	local dy = math.max(0, camY - (groundY or 0))
	return math.sqrt((camX - nx) ^ 2 + (camZ - nz) ^ 2 + dy * dy)
end

export type TileInfo = { key: string, groundY: number }

-- Decide which tiles to show and hide. `tiles` lists every tile that has detail;
-- `loaded` is the set currently shown. Returns (toLoad nearest-first, toUnload farthest-first),
-- each capped at maxPerTick.
function DetailTiles.plan(
	tiles: { TileInfo },
	loaded: { [string]: boolean },
	camX: number,
	camY: number,
	camZ: number,
	maxPerTick: number?
): ({ string }, { string })
	local cap = maxPerTick or DetailTiles.MAX_PER_TICK
	type Entry = { key: string, d: number }
	local load: { Entry } = {}
	local unload: { Entry } = {}
	for _, tinfo in tiles do
		local d = DetailTiles.distance(tinfo.key, camX, camY, camZ, tinfo.groundY)
		if loaded[tinfo.key] then
			if d > DetailTiles.UNLOAD_RADIUS then
				table.insert(unload, { key = tinfo.key, d = d })
			end
		elseif d < DetailTiles.LOAD_RADIUS then
			table.insert(load, { key = tinfo.key, d = d })
		end
	end
	table.sort(load, function(a: Entry, b: Entry)
		return a.d < b.d
	end)
	table.sort(unload, function(a: Entry, b: Entry)
		return a.d > b.d
	end)
	local outL, outU = {}, {}
	for k = 1, math.min(cap, #load) do
		outL[k] = load[k].key
	end
	for k = 1, math.min(cap, #unload) do
		outU[k] = unload[k].key
	end
	return outL, outU
end

return DetailTiles
