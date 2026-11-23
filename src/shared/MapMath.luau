--!strict
-- Pure maths for the minimap (no Roblox API), so it can be tested offline.
--
-- Map space: screen x = world +X (east), screen y = world +Z (south), so north (-Z) is
-- "up" on an unrotated map. Compass heading h (0 = north, 90 = east, clockwise) maps
-- straight onto GUI Rotation (degrees, clockwise on screen): an arrow drawn pointing up
-- with Rotation = h points along heading h.

local MapMath = {}

-- View radius (studs from the centre of the map to its edge) for each zoom step.
MapMath.ZOOMS = { 2500, 5000, 10000, 20000, 40000, 80000 }
MapMath.DEFAULT_ZOOM = 3

export type Bounds = { minX: number, maxX: number, minZ: number, maxZ: number }
export type View = { cx: number, cz: number, scale: number, rotation: number }

-- World rectangle the base map covers: the terrain bounds, grown if needed so that every
-- airport and city (plus a margin) is inside. Reads the data, so a bigger world just works.
function MapMath.worldBounds(base: Bounds, points: { { x: number, z: number, r: number? } }?, margin: number?): Bounds
	local m = margin or 0
	local b = { minX = base.minX, maxX = base.maxX, minZ = base.minZ, maxZ = base.maxZ }
	for _, p in points or {} do
		local r = (p.r or 0) + m
		b.minX = math.min(b.minX, p.x - r)
		b.maxX = math.max(b.maxX, p.x + r)
		b.minZ = math.min(b.minZ, p.z - r)
		b.maxZ = math.max(b.maxZ, p.z + r)
	end
	return b
end

-- Base image size in pixels: keeps the world's aspect ratio, longest side = maxSide.
function MapMath.imageSize(b: Bounds, maxSide: number): (number, number)
	local w, h = b.maxX - b.minX, b.maxZ - b.minZ
	if w >= h then
		return maxSide, math.max(1, math.floor(maxSide * h / w + 0.5))
	end
	return math.max(1, math.floor(maxSide * w / h + 0.5)), maxSide
end

-- World position of the centre of pixel (i, j) (0-based) of a w x h base image.
function MapMath.pixelToWorld(b: Bounds, w: number, h: number, i: number, j: number): (number, number)
	return b.minX + (i + 0.5) / w * (b.maxX - b.minX), b.minZ + (j + 0.5) / h * (b.maxZ - b.minZ)
end

function MapMath.clampZoom(index: number): number
	return math.clamp(math.floor(index), 1, #MapMath.ZOOMS)
end

-- Pixels per stud for a map window `windowPx` wide showing `radiusStuds` to each edge.
function MapMath.scale(windowPx: number, radiusStuds: number): number
	return windowPx * 0.5 / radiusStuds
end

-- Map rotation (GUI degrees) for a mode: "north" keeps north up, "heading" turns the map
-- so the aircraft's nose points up.
function MapMath.mapRotation(mode: string, heading: number): number
	if mode == "heading" then
		return -heading
	end
	return 0
end

-- Rotate a screen vector clockwise by `deg` (screen y points down).
function MapMath.rotate(dx: number, dy: number, deg: number): (number, number)
	local r = math.rad(deg)
	local c, s = math.cos(r), math.sin(r)
	return dx * c - dy * s, dx * s + dy * c
end

-- Pixel position of a world point inside the (unrotated) world layer, whose top-left is
-- the bounds' (minX, minZ) corner.
function MapMath.toLayer(b: Bounds, scale: number, x: number, z: number): (number, number)
	return (x - b.minX) * scale, (z - b.minZ) * scale
end

-- Offset of the world layer's top-left corner inside a window of `windowPx` so that the
-- view centre sits in the middle of the window.
function MapMath.layerOffset(b: Bounds, v: View, windowPx: number): (number, number)
	local px, py = MapMath.toLayer(b, v.scale, v.cx, v.cz)
	return windowPx * 0.5 - px, windowPx * 0.5 - py
end

-- Screen offset (pixels, from the window centre) of a world point, rotation included.
-- This is what the GUI shows when the layer is placed with layerOffset() inside a
-- window-sized pivot frame whose Rotation is v.rotation.
function MapMath.toScreen(v: View, x: number, z: number): (number, number)
	return MapMath.rotate((x - v.cx) * v.scale, (z - v.cz) * v.scale, v.rotation)
end

-- Screen rotation for an arrow of an aircraft with compass heading `heading`.
function MapMath.markerRotation(heading: number, mapRot: number): number
	return (heading + mapRot) % 360
end

-- For a point at screen offset (sx, sy) from the centre of a round map of radius `radius`:
-- whether it is on the map, and where to draw an edge pointer (clamped to the rim) with the
-- rotation that makes an up-pointing arrow point at it.
function MapMath.edgePointer(sx: number, sy: number, radius: number): (boolean, number, number, number)
	local d = math.sqrt(sx * sx + sy * sy)
	local angle = math.deg(math.atan2(sx, -sy)) % 360
	if d <= radius then
		return true, sx, sy, angle
	end
	local k = radius / d
	return false, sx * k, sy * k, angle
end

-- Runway as a rectangle on the map: centre, length and width (studs) and the GUI Rotation
-- for a frame whose long side runs along screen x.
function MapMath.runwayRect(l: { cx: number, cz: number, halfLen: number, halfWidth: number, ax: number, az: number }): (number, number, number, number, number)
	local heading = math.deg(math.atan2(l.ax, -l.az))
	return l.cx, l.cz, l.halfLen * 2, l.halfWidth * 2, (heading - 90) % 180
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function mix(c1: { number }, c2: { number }, t: number): (number, number, number)
	t = math.clamp(t, 0, 1)
	return lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t), lerp(c1[3], c2[3], t)
end

-- Friendly, bright palette (RGB 0-255).
local DEEP = { 38, 92, 168 }
local SHALLOW = { 92, 170, 222 }
local SAND = { 232, 214, 150 }
local LOW = { 112, 186, 92 }
local MID = { 150, 176, 84 }
local HIGH = { 166, 132, 92 }
local ROCK = { 150, 140, 132 }
local SNOW = { 248, 250, 252 }

MapMath.WATER_RGB = DEEP

-- Colour band for a height (studs). `seaLevel` defaults to 0.
function MapMath.heightColor(h: number, seaLevel: number?): (number, number, number)
	local sl = seaLevel or 0
	local a = h - sl
	if a < 0 then
		return mix(SHALLOW, DEEP, -a / 140)
	elseif a < 5 then
		return SAND[1], SAND[2], SAND[3]
	elseif a < 700 then
		return mix(LOW, MID, (a - 5) / 695)
	elseif a < 1800 then
		return mix(MID, HIGH, (a - 700) / 1100)
	elseif a < 3000 then
		return mix(HIGH, ROCK, (a - 1800) / 1200)
	end
	return mix(ROCK, SNOW, (a - 3000) / 400)
end

-- Height colour with simple hill shading: light comes from the north-west, so slopes
-- facing it are brighter. `dhdx`, `dhdz` are the height gradient (studs per stud).
function MapMath.terrainColor(h: number, dhdx: number, dhdz: number, seaLevel: number?): (number, number, number)
	local r, g, b = MapMath.heightColor(h, seaLevel)
	if h < (seaLevel or 0) then
		return r, g, b
	end
	local shade = math.clamp(1 + (dhdx + dhdz) * 1.6, 0.62, 1.3)
	return math.clamp(r * shade, 0, 255), math.clamp(g * shade, 0, 255), math.clamp(b * shade, 0, 255)
end

return MapMath
