--!nonstrict
local DetailTiles = require("../src/shared/DetailTiles")

return { name = "Detail tiles (up-close LOD)", run = function(T)
	local S = DetailTiles.TILE
	T.test("tile keys round-trip through their centre", function()
		for _, p in { { 0, 0 }, { -1, -1 }, { 12345, -67890 }, { -130000, 68000 }, { S, -S } } do
			local key = DetailTiles.tileKey(p[1], p[2])
			local cx, cz = DetailTiles.tileCenter(key)
			T.check(DetailTiles.tileKey(cx, cz) == key, key)
			T.check(math.abs(cx - p[1]) <= S / 2 and math.abs(cz - p[2]) <= S / 2, "centre within half a tile")
		end
		T.check(DetailTiles.tileKey(-1, 0) ~= DetailTiles.tileKey(1, 0), "negative side is its own tile")
	end)
	T.test("distance is zero inside a tile at ground level and grows with height", function()
		local key = DetailTiles.tileKey(100, 100)
		T.near(DetailTiles.distance(key, 100, 50, 100, 50), 0, 1e-6)
		T.near(DetailTiles.distance(key, 100, 3050, 100, 50), 3000, 1e-6)
	end)
	T.test("plan loads near tiles nearest-first, respects the per-tick cap", function()
		local tiles = {}
		for i = -5, 5 do
			for j = -5, 5 do
				table.insert(tiles, { key = i .. "," .. j, groundY = 0 })
			end
		end
		local load = DetailTiles.plan(tiles, {}, 10, 20, 10, 100)
		T.check(#load > 0)
		T.check(load[1] == "0,0", "nearest first: " .. tostring(load[1]))
		for k = 2, #load do
			T.check(DetailTiles.distance(load[k - 1], 10, 20, 10, 0) <= DetailTiles.distance(load[k], 10, 20, 10, 0))
		end
		for _, key in load do
			T.check(DetailTiles.distance(key, 10, 20, 10, 0) < DetailTiles.LOAD_RADIUS)
		end
		local capped = DetailTiles.plan(tiles, {}, 10, 20, 10, 2)
		T.check(#capped == 2)
	end)
	T.test("hysteresis: a tile between the radii stays as it is", function()
		local d = (DetailTiles.LOAD_RADIUS + DetailTiles.UNLOAD_RADIUS) / 2
		local tiles = { { key = "0,0", groundY = 0 } }
		local camX = S + d
		local l1, u1 = DetailTiles.plan(tiles, {}, camX, 0, S / 2)
		T.check(#l1 == 0 and #u1 == 0, "not loaded")
		local l2, u2 = DetailTiles.plan(tiles, { ["0,0"] = true }, camX, 0, S / 2)
		T.check(#l2 == 0 and #u2 == 0, "not unloaded")
		local _, u3 = DetailTiles.plan(tiles, { ["0,0"] = true }, S + DetailTiles.UNLOAD_RADIUS + 10, 0, S / 2)
		T.check(#u3 == 1, "far tile unloads")
	end)
	T.test("climbing high unloads detail under the aircraft", function()
		local tiles = { { key = "0,0", groundY = 100 } }
		local _, u = DetailTiles.plan(tiles, { ["0,0"] = true }, 10, 100 + DetailTiles.UNLOAD_RADIUS + 1, 10)
		T.check(#u == 1)
	end)
end }
