--!nonstrict
-- Minimap maths: world -> map transform, bounds, rotation of markers and runways.
local MapMath = require("../src/shared/MapMath")
local Airports = require("../src/shared/Airports")
local WorldGen = require("../src/shared/WorldGen")
local Units = require("../src/shared/Units")

local function points()
	local pts = {}
	for _, id in Airports.order do
		local l = Airports.layout(id)
		table.insert(pts, { x = l.cx, z = l.cz, r = l.halfLen })
	end
	for _, c in WorldGen.cities do
		table.insert(pts, { x = c.x, z = c.z, r = c.radius * 2 })
	end
	return pts
end

return {
	name = "Minimap",
	run = function(T)
		T.test("map bounds contain the terrain, every airport and every city", function()
			local b = MapMath.worldBounds(WorldGen.BOUNDS, points(), 1000)
			T.check(b.minX <= WorldGen.BOUNDS.minX and b.maxX >= WorldGen.BOUNDS.maxX)
			T.check(b.minZ <= WorldGen.BOUNDS.minZ and b.maxZ >= WorldGen.BOUNDS.maxZ)
			for _, p in points() do
				T.check(p.x - p.r >= b.minX and p.x + p.r <= b.maxX, "x outside")
				T.check(p.z - p.r >= b.minZ and p.z + p.r <= b.maxZ, "z outside")
			end
			-- a point far outside the terrain grows the bounds (a bigger world adapts)
			local big = MapMath.worldBounds(WorldGen.BOUNDS, { { x = 200000, z = -90000, r = 500 } }, 0)
			T.check(big.maxX == 200500 and big.minZ == -90500)
		end)
		T.test("base image keeps the world's aspect ratio", function()
			local b = { minX = 0, maxX = 1000, minZ = 0, maxZ = 500 }
			local w, h = MapMath.imageSize(b, 512)
			T.check(w == 512 and h == 256, w .. "x" .. h)
			local w2, h2 = MapMath.imageSize({ minX = 0, maxX = 500, minZ = 0, maxZ = 1000 }, 512)
			T.check(w2 == 256 and h2 == 512)
			local x, z = MapMath.pixelToWorld(b, w, h, 0, 0)
			T.near(x, 1000 / 512 * 0.5, 1e-9)
			T.near(z, 500 / 256 * 0.5, 1e-9)
		end)
		T.test("north-up: east is right, south is down, centre is the player", function()
			local v = { cx = 1000, cz = 2000, scale = 0.01, rotation = MapMath.mapRotation("north", 137) }
			local sx, sy = MapMath.toScreen(v, 1000, 2000)
			T.near(sx, 0, 1e-9)
			T.near(sy, 0, 1e-9)
			sx, sy = MapMath.toScreen(v, 3000, 2000) -- 2000 studs east
			T.near(sx, 20, 1e-9)
			T.near(sy, 0, 1e-9)
			sx, sy = MapMath.toScreen(v, 1000, 0) -- 2000 studs north
			T.near(sx, 0, 1e-9)
			T.near(sy, -20, 1e-9)
			T.near(MapMath.markerRotation(137, v.rotation), 137, 1e-9)
		end)
		T.test("heading-up: whatever is ahead of the nose is straight up the map", function()
			for _, hdg in { 0, 45, 90, 170, 260, 333 } do
				local v = { cx = -500, cz = 800, scale = 0.02, rotation = MapMath.mapRotation("heading", hdg) }
				local dx, dz = Units.xzFromHeading(hdg)
				local sx, sy = MapMath.toScreen(v, -500 + dx * 1000, 800 + dz * 1000)
				T.near(sx, 0, 1e-6, "ahead x at " .. hdg)
				T.near(sy, -20, 1e-6, "ahead y at " .. hdg)
				-- own arrow points up, and a plane flying the same way does too
				T.near(MapMath.markerRotation(hdg, v.rotation), 0, 1e-6)
				-- something to the right of the nose is to the right on the map
				local rx, rz = Units.xzFromHeading(hdg + 90)
				sx, sy = MapMath.toScreen(v, -500 + rx * 1000, 800 + rz * 1000)
				T.near(sx, 20, 1e-6)
				T.near(sy, 0, 1e-6)
			end
		end)
		T.test("layer offset puts the view centre in the middle of the window", function()
			local b = MapMath.worldBounds(WorldGen.BOUNDS, points(), 1000)
			local v = { cx = 12345, cz = -6789, scale = MapMath.scale(200, MapMath.ZOOMS[2]), rotation = 0 }
			local ox, oy = MapMath.layerOffset(b, v, 200)
			local px, py = MapMath.toLayer(b, v.scale, v.cx, v.cz)
			T.near(ox + px, 100, 1e-6)
			T.near(oy + py, 100, 1e-6)
			-- toLayer and toScreen agree for an unrotated map
			local qx, qy = MapMath.toLayer(b, v.scale, v.cx + 900, v.cz - 300)
			local sx, sy = MapMath.toScreen(v, v.cx + 900, v.cz - 300)
			T.near(ox + qx - 100, sx, 1e-6)
			T.near(oy + qy - 100, sy, 1e-6)
		end)
		T.test("zoom steps are ordered and clamp at both ends", function()
			for i = 2, #MapMath.ZOOMS do
				T.check(MapMath.ZOOMS[i] > MapMath.ZOOMS[i - 1])
			end
			T.check(MapMath.clampZoom(0) == 1)
			T.check(MapMath.clampZoom(99) == #MapMath.ZOOMS)
			T.check(MapMath.clampZoom(MapMath.DEFAULT_ZOOM) == MapMath.DEFAULT_ZOOM)
			T.near(MapMath.scale(200, 5000), 0.02, 1e-12)
		end)
		T.test("runways are drawn along their real heading", function()
			local hbr = Airports.layout("HBR") -- runway 09/27, heading 90 = east-west
			local _, _, len, wid, rot = MapMath.runwayRect(hbr)
			T.near(rot, 0, 1e-6, "HBR rotation")
			T.near(len, 3000 * Units.STUDS_PER_METER, 1e-6)
			T.near(wid, 45 * Units.STUDS_PER_METER, 1e-6)
			local rdv = Airports.layout("RDV") -- heading 80: the east end is a little north
			local _, _, _, _, r2 = MapMath.runwayRect(rdv)
			T.near(r2, 170, 1e-6, "RDV rotation")
			-- a frame rotated by r2 has its long axis along the runway direction on screen
			local ex, ey = MapMath.rotate(1, 0, r2)
			local cross = ex * rdv.az - ey * rdv.ax -- screen (x, y) == world (x, z)
			T.near(cross, 0, 1e-6)
		end)
		T.test("edge pointer clamps off-map targets to the rim and points at them", function()
			local inside, x, y = MapMath.edgePointer(30, -40, 100)
			T.check(inside and x == 30 and y == -40)
			local ok, ex, ey, ang = MapMath.edgePointer(0, -500, 100)
			T.check(not ok)
			T.near(ex, 0, 1e-9)
			T.near(ey, -100, 1e-9)
			T.near(ang, 0, 1e-9)
			_, ex, ey, ang = MapMath.edgePointer(300, 0, 100)
			T.near(ex, 100, 1e-9)
			T.near(ang, 90, 1e-9)
			_, _, _, ang = MapMath.edgePointer(0, 300, 100)
			T.near(ang, 180, 1e-9)
		end)
		T.test("terrain colours: water is blue, land is not, airports are on land", function()
			local r, g, b = MapMath.heightColor(-50)
			T.check(b > r and b > g, "sea should be blue")
			r, g, b = MapMath.heightColor(300)
			T.check(g > b and g > r, "lowland should be green")
			r, g, b = MapMath.heightColor(5000)
			T.check(r > 230 and g > 230 and b > 230, "peaks should be snowy")
			for _, id in Airports.order do
				local l = Airports.layout(id)
				local _, _, bb = MapMath.heightColor(WorldGen.meshHeight(l.cx, l.cz))
				local rr = MapMath.heightColor(WorldGen.meshHeight(l.cx, l.cz))
				T.check(rr > 100, id .. " airport drawn as water")
				T.check(bb < 200)
			end
			local sr, sg, sb = MapMath.terrainColor(300, 0.5, 0.5)
			local fr = MapMath.terrainColor(300, 0, 0)
			T.check(sr > fr, "slope facing the light is brighter")
			for _, c in { sr, sg, sb } do
				T.between(c, 0, 255)
			end
		end)
	end,
}
