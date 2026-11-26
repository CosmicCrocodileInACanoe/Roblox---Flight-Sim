--!strict
-- Crash physics: the engine-independent half of the "soft-body feel" system.
--
-- Roblox has no soft bodies, so crashes are faked with three tricks that stack:
--   1. Crumpling: parts near the contact point are pushed inward along the impact
--      direction and twisted a little, scaled by impact energy (dents that accumulate).
--   2. Break points: components can lose a *section* (outer wing, a stabiliser tip, the
--      top of the fin) before the whole component lets go. Planes in body space decide
--      which parts belong to the torn-off section, so any builder's parts work.
--   3. Secondary breakup: torn-off debris keeps its momentum and splits again when it
--      hits something hard enough, down to a per-piece integrity budget.
--
-- Everything is data-driven. Each component gets a profile from its *kind*
-- (wing/engine/fuselage/tail/gear, inferred from its name like Damage.wearKind), merged
-- with an optional `crash = { ... }` table on the component config. New aircraft plug in
-- with no code changes: name components LeftWing/RightWing/HorizontalStab/VerticalStab,
-- give `geometry.wing/hstab/vstab` like Meridian 200, or list `crash.sections` by hand.
--
-- Body axes and SI units as everywhere else (x right, y up, z aft, metres).

local Crash = {}

export type Vec = { number } -- { x, y, z }

export type Section = {
	id: string,
	normal: Vec, -- unit vector in body axes pointing *into* the section
	offset: number, -- the plane: dot(p, normal) = offset
	lost: number, -- fraction of the component's lift/mass lost with the section (0..1)
}

export type Profile = {
	kind: string,
	dentThreshold: number, -- local dv (m/s) where dents start
	dentScale: number, -- m/s for the dent to reach ~63% of maxDent
	maxDent: number, -- metres, deepest single dent
	maxTotalDent: number, -- metres, cap on accumulated dent per part
	dentRadius: number, -- metres, falloff radius around the contact point
	maxTwistDeg: number, -- crumple twist at the contact point
	maxParts: number, -- parts moved per dent (performance cap)
	sectionBreakDv: number, -- local dv (m/s) that tears off a section
	secondaryBreakDv: number, -- dv (m/s) at which a debris piece splits again
	integrity: number, -- how many more times a debris piece may split
	shards: number, -- client shard count at a hard hit (scaled by energy)
	sparkScale: number,
	sections: { Section },
}

local DEFAULTS: { [string]: any } = {
	wing = {
		dentThreshold = 5, dentScale = 12, maxDent = 0.8, maxTotalDent = 1.6, dentRadius = 4.5,
		maxTwistDeg = 10, maxParts = 8, sectionBreakDv = 13, secondaryBreakDv = 11, integrity = 2,
		shards = 8, sparkScale = 1.0,
	},
	engine = {
		dentThreshold = 3, dentScale = 10, maxDent = 0.6, maxTotalDent = 1.1, dentRadius = 2.2,
		maxTwistDeg = 14, maxParts = 6, sectionBreakDv = math.huge, secondaryBreakDv = 9, integrity = 1,
		shards = 6, sparkScale = 1.4,
	},
	fuselage = {
		dentThreshold = 6, dentScale = 14, maxDent = 1.2, maxTotalDent = 2.2, dentRadius = 5,
		maxTwistDeg = 6, maxParts = 10, sectionBreakDv = math.huge, secondaryBreakDv = 13, integrity = 3,
		shards = 10, sparkScale = 1.2,
	},
	tail = {
		dentThreshold = 4, dentScale = 10, maxDent = 0.5, maxTotalDent = 1.0, dentRadius = 2.5,
		maxTwistDeg = 12, maxParts = 6, sectionBreakDv = 10, secondaryBreakDv = 9, integrity = 1,
		shards = 5, sparkScale = 0.8,
	},
	gear = {
		dentThreshold = 4, dentScale = 8, maxDent = 0.45, maxTotalDent = 0.8, dentRadius = 1.6,
		maxTwistDeg = 18, maxParts = 4, sectionBreakDv = math.huge, secondaryBreakDv = 8, integrity = 1,
		shards = 4, sparkScale = 1.5,
	},
}
Crash.DEFAULTS = DEFAULTS

-- Same name rules as Damage.wearKind, duplicated so this module has no requires.
function Crash.kind(name: string): string
	-- Gear first: "LeftWingGear" is landing gear, not a wing.
	if string.find(name, "Gear") then
		return "gear"
	elseif string.find(name, "Engine") or string.find(name, "Prop") then
		return "engine"
	elseif string.find(name, "Wing") then
		return "wing"
	elseif string.find(name, "Stab") or string.find(name, "Fin") or string.find(name, "Tail") then
		return "tail"
	end
	return "fuselage"
end

local function sideOf(name: string, compCfg: any): number
	if string.find(name, "Left") then
		return -1
	elseif string.find(name, "Right") then
		return 1
	end
	local ref = compCfg and compCfg.ref
	if ref and ref[1] ~= 0 then
		return if ref[1] < 0 then -1 else 1
	end
	return 0
end

-- Break planes derived from the parametric geometry (if the aircraft has it).
local WING_BREAK_AT = 0.55 -- fraction of semispan
local STAB_BREAK_AT = 0.5
local FIN_BREAK_AT = 0.55
local CHILD_CLEARANCE = 2.5 -- metres a break plane keeps clear of a child component

function Crash.deriveSections(cfg: any, name: string): { Section }
	local geo = cfg.geometry
	local kind = Crash.kind(name)
	local compCfg = cfg.components and cfg.components[name]
	local out: { Section } = {}
	if not geo then
		return out
	end
	if kind == "wing" and geo.wing then
		local s = sideOf(name, compCfg)
		if s ~= 0 then
			local w = geo.wing
			table.insert(out, {
				id = "Outer", normal = { s, 0, 0 },
				offset = w.rootLE[1] + w.span * WING_BREAK_AT, lost = 1 - WING_BREAK_AT * 0.85,
				-- may slide outboard past an outer engine, up to here (the wing end)
				maxOffset = w.rootLE[1] + w.span * 0.85, endOffset = w.rootLE[1] + w.span,
			})
		end
	elseif kind == "tail" and (string.find(name, "Horizontal") or string.find(name, "HStab")) and geo.hstab then
		local h = geo.hstab
		local at = h.rootLE[1] + h.span * STAB_BREAK_AT
		table.insert(out, { id = "LeftTip", normal = { -1, 0, 0 }, offset = at, lost = 0.25 })
		table.insert(out, { id = "RightTip", normal = { 1, 0, 0 }, offset = at, lost = 0.25 })
	elseif kind == "tail" and (string.find(name, "Vertical") or string.find(name, "Fin")) and geo.vstab then
		local v = geo.vstab
		table.insert(out, { id = "Top", normal = { 0, 1, 0 }, offset = v.rootLE[2] + v.height * FIN_BREAK_AT, lost = 0.4 })
	end
	return out
end

local function normalized(v: Vec): Vec
	local m = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
	if m < 1e-9 then
		return { 0, 0, 0 }
	end
	return { v[1] / m, v[2] / m, v[3] / m }
end

-- Profile for one component. `cfg.components[name].crash` overrides any field;
-- `crash.sections = false` disables break points, a list replaces the derived ones.
function Crash.profile(cfg: any, name: string, toughness: number?): Profile
	local compCfg = cfg.components and cfg.components[name] or {}
	local kind = Crash.kind(name)
	local base = DEFAULTS[kind]
	local over = compCfg.crash or {}
	local p: any = { kind = kind }
	for k, v in base do
		p[k] = v
	end
	for k, v in over do
		if k ~= "sections" then
			p[k] = v
		end
	end
	if over.sections == false then
		p.sections = {}
	elseif type(over.sections) == "table" then
		p.sections = {}
		for _, s in over.sections do
			table.insert(p.sections, {
				id = s.id, normal = normalized(s.normal), offset = s.offset, lost = s.lost or 0.3,
			})
		end
	else
		-- Derived planes must not cut through a child component (a T-tail's stabiliser
		-- sits on top of the fin, so the fin can't lose its top on its own).
		p.sections = {}
		-- Wing planes slide outboard past an outer engine if there's room for a tip.
		for _, sec in Crash.deriveSections(cfg, name) do
			local s2: any = sec
			local furthest = -math.huge
			for _, other in cfg.components or {} do
				if other.parent == name and other.ref and Crash.inSection(sec, other.ref) then
					local n = sec.normal
					furthest = math.max(furthest, other.ref[1] * n[1] + other.ref[2] * n[2] + other.ref[3] * n[3])
				end
			end
			if furthest > -math.huge then
				local moved = furthest + CHILD_CLEARANCE
				if s2.maxOffset and moved <= s2.maxOffset then
					local span = s2.endOffset - sec.offset
					sec.lost *= (s2.endOffset - moved) / span
					sec.offset = moved
				else
					continue
				end
			end
			table.insert(p.sections, { id = sec.id, normal = sec.normal, offset = sec.offset, lost = sec.lost })
		end
	end
	-- Easy mode (toughness > 1) makes dents and tears need harder hits.
	local tough = toughness or 1
	if tough ~= 1 then
		p.dentThreshold *= tough
		p.sectionBreakDv *= tough
		p.secondaryBreakDv *= tough
	end
	return p :: Profile
end

-- Profiles for every component, cached per config table.
-- `toughness` is FlightModel's easy-mode multiplier (Assist.toughness); default 1.
local cache: { [any]: { [number]: { [string]: Profile } } } = setmetatable({}, { __mode = "k" }) :: any
function Crash.profiles(cfg: any, toughness: number?): { [string]: Profile }
	local tough = toughness or 1
	local byTough = cache[cfg]
	if not byTough then
		byTough = {}
		cache[cfg] = byTough
	end
	local c = byTough[tough]
	if c then
		return c
	end
	c = {}
	for name in cfg.components do
		c[name] = Crash.profile(cfg, name, tough)
	end
	byTough[tough] = c
	return c
end

function Crash.findSection(profile: Profile, id: string): Section?
	for _, s in profile.sections do
		if s.id == id then
			return s
		end
	end
	return nil
end

-- Kinetic energy (J) of a mass with velocity change dv. Used to scale effects.
function Crash.impactEnergy(massKg: number, dv: number): number
	return 0.5 * massKg * dv * dv
end

-- Depth of a single dent (m). Zero below the threshold, saturating at maxDent.
function Crash.dentDepth(profile: Profile, dv: number): number
	if dv ~= dv or dv <= profile.dentThreshold then
		return 0
	end
	return profile.maxDent * (1 - math.exp(-(dv - profile.dentThreshold) / profile.dentScale))
end

-- Deterministic small pseudo-random number in [-1, 1] from an integer seed.
local function hash(seed: number): number
	local x = math.floor(seed) % 2147483647
	x = (x * 16807) % 2147483647
	x = (x * 16807) % 2147483647
	return (x / 2147483647) * 2 - 1
end
Crash.hash = hash

export type CrumplePart = { id: any, pos: Vec, dent: number? }
export type CrumpleResult = { id: any, offset: Vec, twist: Vec, weight: number }

-- Which parts move and by how much for one dent.
--   parts:  { id, pos (body m), dent = accumulated dent so far }
--   point:  contact point (body m)
--   dir:    impact direction (body), the way the structure gets pushed
--   depth:  Crash.dentDepth(...)
-- Returns up to profile.maxParts results, nearest first. Offsets are in body metres and
-- never push a part past profile.maxTotalDent of accumulated dent.
function Crash.crumple(profile: Profile, parts: { CrumplePart }, point: Vec, dir: Vec, depth: number, seed: number?): { CrumpleResult }
	local out: { CrumpleResult } = {}
	if depth <= 0 then
		return out
	end
	local n = normalized(dir)
	if n[1] == 0 and n[2] == 0 and n[3] == 0 then
		-- No direction: push toward the centre of mass.
		n = normalized({ -point[1], -point[2], -point[3] })
	end
	local r = profile.dentRadius
	local cand: { { p: CrumplePart, d: number } } = {}
	for _, p in parts do
		local dx, dy, dz = p.pos[1] - point[1], p.pos[2] - point[2], p.pos[3] - point[3]
		local d = math.sqrt(dx * dx + dy * dy + dz * dz)
		if d < r then
			table.insert(cand, { p = p, d = d })
		end
	end
	table.sort(cand, function(a: { p: CrumplePart, d: number }, b: { p: CrumplePart, d: number }): boolean
		return a.d < b.d
	end)
	local s0 = seed or 1
	local maxTwist = math.rad(profile.maxTwistDeg)
	for i = 1, math.min(#cand, profile.maxParts) do
		local c = cand[i]
		local q = c.d / r
		local w = (1 - q * q) ^ 2 -- smooth falloff, 1 at the contact, 0 at the radius
		local already = c.p.dent or 0
		local amount = math.min(depth * w, math.max(0, profile.maxTotalDent - already))
		if amount <= 1e-4 then
			continue
		end
		local k = amount / math.max(depth, 1e-6) -- 0..1, how hard this part got hit
		local tw = maxTwist * k
		table.insert(out, {
			id = c.p.id,
			offset = { n[1] * amount, n[2] * amount, n[3] * amount },
			twist = { hash(s0 * 3 + i) * tw, hash(s0 * 5 + i * 7) * tw, hash(s0 * 11 + i * 13) * tw },
			weight = w,
		})
	end
	return out
end

-- True if body-space point `p` lies inside a section (beyond its plane, with margin).
function Crash.inSection(section: Section, p: Vec, margin: number?): boolean
	local n = section.normal
	return p[1] * n[1] + p[2] * n[2] + p[3] * n[3] > section.offset - (margin or 0)
end

-- Split part positions by a section plane. Returns (inside ids, remaining ids).
function Crash.partition(section: Section, parts: { CrumplePart }): ({ any }, { any })
	local inside, rest = {}, {}
	for _, p in parts do
		if Crash.inSection(section, p.pos) then
			table.insert(inside, p.id)
		else
			table.insert(rest, p.id)
		end
	end
	return inside, rest
end

-- Section (if any) that an impact at `point` with local dv should tear off.
-- `broken` is a set of section ids already gone.
function Crash.sectionToBreak(profile: Profile, point: Vec?, dv: number, broken: { [string]: boolean }?): Section?
	if not point or dv ~= dv or dv < profile.sectionBreakDv then
		return nil
	end
	for _, s in profile.sections do
		if not (broken and broken[s.id]) and Crash.inSection(s, point, 0.5) then
			return s
		end
	end
	return nil
end

-- Plane for splitting a loose debris piece in two: across its longest extent, at the
-- median so both halves get parts. Positions are in any common frame (the server uses
-- the piece's own frame). Returns (normal, offset) or nil if it can't be split.
function Crash.splitPlane(parts: { CrumplePart }): (Vec?, number?)
	if #parts < 2 then
		return nil, nil
	end
	local lo = { math.huge, math.huge, math.huge }
	local hi = { -math.huge, -math.huge, -math.huge }
	for _, p in parts do
		for a = 1, 3 do
			lo[a] = math.min(lo[a], p.pos[a])
			hi[a] = math.max(hi[a], p.pos[a])
		end
	end
	local axis, best = 1, -1
	for a = 1, 3 do
		if hi[a] - lo[a] > best then
			axis, best = a, hi[a] - lo[a]
		end
	end
	if best < 1e-3 then
		return nil, nil
	end
	local vals = {}
	for _, p in parts do
		table.insert(vals, p.pos[axis])
	end
	table.sort(vals)
	local m = #vals // 2
	local offset = (vals[m] + vals[m + 1]) / 2
	if vals[m] == vals[m + 1] then
		offset = (lo[axis] + hi[axis]) / 2
	end
	local n = { 0, 0, 0 }
	n[axis] = 1
	return n, offset
end

-- Debris breakup bookkeeping. Returns true if the piece should split now, and spends
-- one unit of integrity. Pieces with fewer than two parts never split.
export type PieceState = { integrity: number, parts: number }
function Crash.secondaryBreak(profile: Profile, piece: PieceState, dv: number): boolean
	if dv ~= dv or piece.integrity <= 0 or piece.parts < 2 then
		return false
	end
	if dv < profile.secondaryBreakDv then
		return false
	end
	piece.integrity -= 1
	return true
end

-- Velocity a newly separated piece should keep (m/s, any consistent units): the
-- parent's velocity at that point (v + w x r) plus a small push away from the break.
function Crash.inheritVelocity(v: Vec, w: Vec, r: Vec, away: Vec, push: number): Vec
	local cx = w[2] * r[3] - w[3] * r[2]
	local cy = w[3] * r[1] - w[1] * r[3]
	local cz = w[1] * r[2] - w[2] * r[1]
	local a = normalized(away)
	return { v[1] + cx + a[1] * push, v[2] + cy + a[2] * push, v[3] + cz + a[3] * push }
end

-- Fix all swaps every part of the aircraft for a new one. Damage reports already on
-- their way about the old parts are dropped for this long (seconds) afterwards.
Crash.REPAIR_GRACE = 0.75
function Crash.justRepaired(repairedAt: any, now: number): boolean
	return type(repairedAt) == "number" and now - repairedAt >= 0 and now - repairedAt < Crash.REPAIR_GRACE
end

-- Crater for a destroyed aircraft hitting the ground at `dv` (m/s): radius and rim
-- height in metres, scaled by the cube root of the impact energy so a small plane
-- leaves a small crater and a jumbo a big one. Returns nil for gentle wrecks.
function Crash.craterSize(massKg: number, dv: number, minDv: number?): (number?, number?)
	if dv ~= dv or massKg ~= massKg or dv < (minDv or 10) or massKg <= 0 then
		return nil, nil
	end
	local e = Crash.impactEnergy(massKg, dv)
	local radius = math.clamp(2.5 + e ^ (1 / 3) * 0.025, 3, 30)
	return radius, radius * 0.18
end

-- Shards to spawn on the client for a hit (kept small; Effects also caps the total).
function Crash.shardCount(profile: Profile, dv: number): number
	if dv <= profile.dentThreshold * 1.5 then
		return 0
	end
	return math.clamp(math.floor(profile.shards * (dv - profile.dentThreshold * 1.5) / 20 + 0.5), 0, profile.shards)
end

return Crash
