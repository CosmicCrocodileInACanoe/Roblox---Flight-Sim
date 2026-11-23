--!strict
-- Soft-body look for rigid Roblox aircraft (engine-independent maths).
--
-- BeamNG simulates a node-beam mesh. Roblox can't, so this module gives two
-- approximations that read as "metal bending" on screen:
--
--   1. Beam bending (server, everyone sees it). Wings, tailplanes, the fin and the nose/tail
--      fuselage sections are treated as a beam of many small parts. A hit bends the beam
--      at a hinge a little inboard of the contact: parts in the bend zone rotate by a
--      growing angle and parts past it follow rigidly, so the structure takes a smooth
--      curve instead of a sharp break. Hits along the beam (a nose-first crash) crush it
--      like an accordion instead. Bends add up to a per-component cap.
--   2. Mesh skins (client, needs EditableMesh). A dented part can be swapped on screen for
--      a subdivided mesh of the same shape whose vertices are pushed in around the impact.
--      `grid` builds that mesh for Roblox's part shapes; `dentVertices` moves vertices.
--
-- Units: body metres and radians for bending; part-local studs for mesh skins (the
-- functions are unit-agnostic, callers keep one unit per call).

local SoftBody = {}

export type Vec = { number }

export type BendProfile = {
	bendThreshold: number, -- local dv (m/s) where bending starts
	bendPerMps: number, -- degrees of bend per m/s above the threshold
	maxBendDeg: number, -- cumulative cap per component
	bendZone: number, -- metres over which the bend angle builds up
	crushPerMps: number, -- metres of crush per m/s above threshold (axial hits)
	maxCrush: number, -- cumulative cap, metres
	maxParts: number, -- skip bending if the beam has more parts than this
}

local BEND_DEFAULTS: { [string]: BendProfile? } = {
	wing = { bendThreshold = 5, bendPerMps = 1.3, maxBendDeg = 28, bendZone = 4.5, crushPerMps = 0.03, maxCrush = 0.8, maxParts = 220 },
	tail = { bendThreshold = 4, bendPerMps = 1.6, maxBendDeg = 32, bendZone = 2.2, crushPerMps = 0.02, maxCrush = 0.5, maxParts = 160 },
	fuselage = { bendThreshold = 6, bendPerMps = 0.55, maxBendDeg = 14, bendZone = 5, crushPerMps = 0.09, maxCrush = 3.0, maxParts = 260 },
}
SoftBody.BEND_DEFAULTS = BEND_DEFAULTS

local function dot(a: Vec, b: Vec): number
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end
local function cross(a: Vec, b: Vec): Vec
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function scale(a: Vec, k: number): Vec
	return { a[1] * k, a[2] * k, a[3] * k }
end
local function sub(a: Vec, b: Vec): Vec
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
local function len(a: Vec): number
	return math.sqrt(dot(a, a))
end
local function unit(a: Vec): Vec
	local m = len(a)
	if m < 1e-9 then
		return { 0, 0, 0 }
	end
	return scale(a, 1 / m)
end
SoftBody.unit = unit
SoftBody.cross = cross

-- Bend profile for a component, or nil if it doesn't bend (engines, gear, the centre
-- fuselage). `kind` is Crash.kind(name). Override with `crash = { bend = {...} }` or
-- `crash = { bend = false }`.
function SoftBody.bendProfile(cfg: any, name: string, kind: string): BendProfile?
	local compCfg = cfg.components and cfg.components[name] or {}
	local over = compCfg.crash and compCfg.crash.bend
	if over == false then
		return nil
	end
	local base = BEND_DEFAULTS[kind]
	if not base or (kind == "fuselage" and compCfg.parent == nil) then
		if type(over) ~= "table" then
			return nil
		end
		base = BEND_DEFAULTS.fuselage
	end
	local p: any = table.clone(base :: any)
	if type(over) == "table" then
		for k, v in over do
			p[k] = v
		end
	end
	return p :: BendProfile
end

-- The beam axis (unit, body) pointing from the component's root toward its free end,
-- or nil. `point` breaks the tie for a one-piece tailplane (which half got hit).
function SoftBody.beamAxis(cfg: any, name: string, kind: string, point: Vec): Vec?
	local compCfg = cfg.components and cfg.components[name] or {}
	local over = compCfg.crash and compCfg.crash.bend
	if type(over) == "table" and over.axis then
		return unit(over.axis)
	end
	if kind == "wing" then
		if string.find(name, "Left") then
			return { -1, 0, 0 }
		elseif string.find(name, "Right") then
			return { 1, 0, 0 }
		end
		local ref = compCfg.ref
		return if ref and ref[1] ~= 0 then { if ref[1] < 0 then -1 else 1, 0, 0 } else nil
	elseif kind == "tail" then
		if string.find(name, "Vertical") or string.find(name, "Fin") then
			return { 0, 1, 0 }
		end
		return { if point[1] < 0 then -1 else 1, 0, 0 }
	elseif kind == "fuselage" then
		local ref = compCfg.ref
		if ref and math.abs(ref[3]) > 0.5 then
			return { 0, 0, if ref[3] < 0 then -1 else 1 }
		end
	end
	return nil
end

export type BendPart = { id: any, pos: Vec }
export type BendMove = {
	id: any,
	pivot: Vec, -- body metres
	rotation: Vec, -- axis-angle (radians), body axes, applied about pivot
	translate: Vec, -- body metres, applied after the rotation
}
export type BendResult = { moves: { BendMove }, bentDeg: number, crushed: number }

-- How one impact bends a beam.
--   parts:   every part of the component (id + body position)
--   axis:    SoftBody.beamAxis
--   point:   contact point (body m); dir: impact direction (body, the way it's pushed)
--   already: { bentDeg, crushed } accumulated so far on this component
function SoftBody.bend(profile: BendProfile, parts: { BendPart }, axis: Vec, point: Vec, dir: Vec, dv: number, already: { bentDeg: number, crushed: number }?): BendResult
	local none: BendResult = { moves = {}, bentDeg = 0, crushed = 0 }
	if dv ~= dv or dv <= profile.bendThreshold or #parts == 0 or #parts > profile.maxParts then
		return none
	end
	local a = unit(axis)
	if len(a) == 0 then
		return none
	end
	local d = unit(dir)
	local prev = already or { bentDeg = 0, crushed = 0 }
	local severity = dv - profile.bendThreshold
	-- Split the push into a sideways part (bends) and an along-the-beam part (crushes).
	local along = dot(d, a)
	local perp = sub(d, scale(a, along))
	local perpMag = len(perp)
	local angleDeg = 0
	if perpMag > 0.15 then
		angleDeg = math.min(profile.bendPerMps * severity * perpMag, math.max(0, profile.maxBendDeg - prev.bentDeg))
	end
	local crush = 0
	if along < -0.3 then -- pushed back toward the root
		crush = math.min(profile.crushPerMps * severity * -along, math.max(0, profile.maxCrush - prev.crushed))
	end
	if angleDeg < 0.05 and crush < 0.005 then
		return none
	end
	-- Hinge a bend-zone length inboard of the hit, but never inboard of the root.
	local sMin = math.huge
	for _, p in parts do
		sMin = math.min(sMin, dot(p.pos, a))
	end
	local sHit = dot(point, a)
	local s0 = math.max(sHit - profile.bendZone, sMin + 0.25)
	if sHit <= s0 then
		s0 = sMin
	end
	local pivot = sub(point, scale(a, sHit - s0))
	local rotAxis = unit(cross(a, perp))
	local angle = math.rad(angleDeg)
	local zone = math.max(profile.bendZone, 0.5)
	local moves: { BendMove } = {}
	for _, p in parts do
		local u = dot(p.pos, a) - s0
		if u > 0 then
			local f = math.min(1, u / zone)
			table.insert(moves, {
				id = p.id,
				pivot = pivot,
				rotation = scale(rotAxis, angle * f),
				translate = scale(a, -crush * f),
			})
		end
	end
	return { moves = moves, bentDeg = angleDeg, crushed = crush }
end

-- Rodrigues: rotate vector v by axis-angle w. Used by tests and by callers without CFrame.
function SoftBody.rotate(v: Vec, w: Vec): Vec
	local th = len(w)
	if th < 1e-12 then
		return { v[1], v[2], v[3] }
	end
	local k = scale(w, 1 / th)
	local c, s = math.cos(th), math.sin(th)
	local kv = cross(k, v)
	local kd = dot(k, v)
	return {
		v[1] * c + kv[1] * s + k[1] * kd * (1 - c),
		v[2] * c + kv[2] * s + k[2] * kd * (1 - c),
		v[3] * c + kv[3] * s + k[3] * kd * (1 - c),
	}
end

-- Where a part's centre ends up after a move.
function SoftBody.applyMove(pos: Vec, m: BendMove): Vec
	local r = SoftBody.rotate(sub(pos, m.pivot), m.rotation)
	return { m.pivot[1] + r[1] + m.translate[1], m.pivot[2] + r[2] + m.translate[2], m.pivot[3] + r[3] + m.translate[3] }
end

-- Mesh skins ------------------------------------------------------------------------------
-- Shapes: "box", "wedge" (Roblox WedgePart), "cylinderX" (Roblox cylinder, axis X),
-- "ellipsoid". Built from a subdivided cube so every shape has the same topology:
-- 6 faces x (n+1)^2 vertices, 6 x n^2 x 2 triangles. Face vertices are not shared, so
-- edges stay crisp; dents depend only on position, so shared edges never crack open.
export type Grid = { verts: { Vec }, tris: { { number } } }

local FACES = {
	-- normal axis, sign, u axis, v axis
	{ 1, 1, 2, 3 }, { 1, -1, 3, 2 },
	{ 2, 1, 3, 1 }, { 2, -1, 1, 3 },
	{ 3, 1, 1, 2 }, { 3, -1, 2, 1 },
}

local function shapePoint(shape: string, c: Vec, half: Vec): Vec
	local x, y, z = c[1], c[2], c[3]
	if shape == "ellipsoid" then
		local u = unit({ x, y, z })
		return { u[1] * half[1], u[2] * half[2], u[3] * half[3] }
	elseif shape == "cylinderX" then
		local r = math.sqrt(y * y + z * z)
		if r > 1e-9 then
			local k = math.max(math.abs(y), math.abs(z)) / r
			y, z = y * k, z * k
		end
		return { x * half[1], y * half[2], z * half[3] }
	elseif shape == "wedge" then
		-- cross-section (y, z): (-1,-1), (-1,1), (1,1); the slope is y = z
		local yy = -1 + (y + 1) * (z + 1) / 2
		return { x * half[1], yy * half[2], z * half[3] }
	end
	return { x * half[1], y * half[2], z * half[3] }
end

function SoftBody.grid(shape: string, size: Vec, n: number): Grid
	local half = scale(size, 0.5)
	local verts: { Vec } = {}
	local tris: { { number } } = {}
	for _, f in FACES do
		local na, sign, ua, va = f[1], f[2], f[3], f[4]
		local base = #verts
		for i = 0, n do
			for j = 0, n do
				local c = { 0, 0, 0 }
				c[na] = sign
				c[ua] = -1 + 2 * i / n
				c[va] = -1 + 2 * j / n
				table.insert(verts, shapePoint(shape, c, half))
			end
		end
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				local v00 = base + i * (n + 1) + j + 1
				local v10 = v00 + (n + 1)
				local v01 = v00 + 1
				local v11 = v10 + 1
				table.insert(tris, { v00, v10, v11 })
				table.insert(tris, { v00, v11, v01 })
			end
		end
	end
	return { verts = verts, tris = tris }
end

-- Push vertices in around a contact. Returns { [index] = newPos } for moved vertices.
--   point/dir in the mesh's frame, depth and radius in the same unit.
--   maxOffset: no vertex ends up further than this from its rest position.
-- A small deterministic ripple makes creases instead of a perfect bowl.
function SoftBody.dentVertices(verts: { Vec }, rest: { Vec }, point: Vec, dir: Vec, depth: number, radius: number, maxOffset: number, seed: number?): { [number]: Vec }
	local out: { [number]: Vec } = {}
	if depth <= 0 or radius <= 0 or depth ~= depth then
		return out
	end
	local d = unit(dir)
	if len(d) == 0 then
		d = unit(scale(point, -1))
	end
	local s = seed or 1
	for i, v in verts do
		local dist = len(sub(v, point))
		if dist < radius then
			local q = dist / radius
			local w = (1 - q * q) ^ 2
			local ripple = 1 + 0.25 * math.sin(i * 1.7 + s) * (1 - w)
			local amt = depth * w * ripple
			local nv = { v[1] + d[1] * amt, v[2] + d[2] * amt, v[3] + d[3] * amt }
			local r0 = rest[i] or v
			local off = sub(nv, r0)
			local m = len(off)
			if m > maxOffset then
				nv = { r0[1] + off[1] / m * maxOffset, r0[2] + off[2] / m * maxOffset, r0[3] + off[3] / m * maxOffset }
			end
			if len(sub(nv, v)) > 1e-5 then
				out[i] = nv
			end
		end
	end
	return out
end

return SoftBody
