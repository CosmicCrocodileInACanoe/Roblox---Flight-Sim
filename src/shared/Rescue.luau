--!strict
-- Emergency response and sinking (pure: no Roblox APIs, so tests/test_rescue.luau can
-- check it offline).
--
-- Three situations:
--   land_crash   the airframe was destroyed on land: fire trucks, ambulances and police
--                drive to the wreck.
--   water_crash  the airframe was destroyed in the sea: it floats for a moment, then
--                sinks over 60 s. Rescue boats and helicopters come.
--   ditch        an aircraft that can't float (no floats or boat hull) put down on the
--                water in one piece: half under after 20 s, gone after 60 s. Rescue boats
--                and a ferry come and take the passengers off in life rafts.
-- Seaplanes and amphibians (cfg.water) that are on the water in one piece are fine.
--
-- Sinking works by lowering the water surface the flight model sees (env.hullDepth) by
-- `sinkOffset` metres, so the aircraft settles that much lower and keeps the same
-- buoyancy and water drag. A destroyed aircraft gets no flight model forces, so
-- Rescue.waterForces gives it the same buoyancy on its own.

local function req(name: string): any
	if script then
		return (require :: any)((script :: any).Parent[name])
	end
	return (require :: any)("./" .. name)
end
local Units = req("Units")

local Rescue = {}

Rescue.LAND_CRASH = "land_crash"
Rescue.WATER_CRASH = "water_crash"
Rescue.DITCH = "ditch"
Rescue.SITUATIONS = { land_crash = true, water_crash = true, ditch = true }

Rescue.SINK = {
	crashFloatS = 8, -- a wreck floats this long before it starts to go down
	crashFullS = 60, -- and is under by this time
	ditchHalfS = 20, -- a ditched landplane is half under by this time
	ditchFullS = 60, -- and completely under by this time
	afterMps = 0.8, -- then it keeps sinking at this rate (m/s) until it finds the bottom
	maxOffsetM = 150,
	wetToStartS = 1.5, -- a landplane must stay in the water this long to count as ditched
}

-- Buoyancy of a non-float hull point (the same numbers FlightModel uses for a ditching):
-- each point in the water gives mass*g/(n*1.3) per metre of depth, capped at 2.5 m.
local DEPTH_CAP = 2.5
local DEPTH_SHARE = 1.3

function Rescue.isWaterCapable(cfg: any): boolean
	return cfg ~= nil and cfg.water ~= nil
end

-- Life-raft passengers (crew included): the type's seat count, else a guess from mass.
local SEATS = { kestrel72 = 70, meridian200 = 180, atlas400 = 410, celestia800 = 550 }
function Rescue.passengers(cfg: any): number
	local n = cfg.seats or SEATS[cfg.id]
	if not n then
		n = math.clamp(math.floor(cfg.mass / 350 + 0.5), 1, 300)
	end
	return math.max(1, n)
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Height (m) of the centre of mass above the water surface when a level aircraft floats
-- on its hull points with the ditching buoyancy above.
function Rescue.floatHeight(cfg: any): number
	local hull = cfg.hullPoints
	local n = #hull
	local need = n * DEPTH_SHARE -- sum of clamped depths that holds the weight up
	local function sum(h: number): number
		local s = 0
		for _, hp in hull do
			s += math.clamp(-(h + hp[2]), 0, DEPTH_CAP)
		end
		return s
	end
	local lo, hi = -50, 50 -- sum(lo) is large, sum(hi) is 0
	for _ = 1, 60 do
		local mid = (lo + hi) / 2
		if sum(mid) > need then
			lo = mid
		else
			hi = mid
		end
	end
	return (lo + hi) / 2
end

-- Height (m) of the centre of mass above the water when a seaplane or amphibian floats
-- level on its floats or hull (cfg.water.restDepth deep). Used to spawn on the water.
function Rescue.waterRestHeight(cfg: any): number
	local low = math.huge
	for _, hp in cfg.hullPoints do
		if hp[5] == "float" then
			low = math.min(low, hp[2])
		end
	end
	if low == math.huge then
		return Rescue.floatHeight(cfg)
	end
	local rest = (cfg.water and cfg.water.restDepth) or 0.35
	return -low - rest
end

-- Highest point of the airframe above the centre of mass (m): the fin tip or the top of
-- the fuselage.
function Rescue.topHeight(cfg: any): number
	local top = 1
	local fus = cfg.geometry and cfg.geometry.fuselage
	if fus and fus.radius then
		top = math.max(top, fus.radius)
	end
	for _, p in cfg.aero.panels do
		if p.role == "vstab" then
			top = math.max(top, p.pos[2] * 1.6)
		end
	end
	for _, hp in cfg.hullPoints do
		top = math.max(top, hp[2])
	end
	return top
end

-- How far (m) to lower the water surface for "half under" (the waterline at the centre
-- of the fuselage) and "completely under" (the fin tip a metre below the waves).
function Rescue.sinkDepths(cfg: any): (number, number)
	local h0 = Rescue.floatHeight(cfg)
	local half = math.max(0.3, h0)
	local full = math.max(half + 1, h0 + Rescue.topHeight(cfg) + 1)
	return half, full
end

-- Water surface offset (m) `t` seconds into sinking.
function Rescue.sinkOffset(kind: string, t: number, half: number, full: number): number
	local S = Rescue.SINK
	local endS = if kind == Rescue.DITCH then S.ditchFullS else S.crashFullS
	local off
	if t >= endS then
		off = full + (t - endS) * S.afterMps
	elseif kind == Rescue.DITCH then
		if t <= S.ditchHalfS then
			off = half * smooth(t / S.ditchHalfS)
		else
			off = half + (full - half) * smooth((t - S.ditchHalfS) / (S.ditchFullS - S.ditchHalfS))
		end
	else
		off = full * smooth((t - S.crashFloatS) / (S.crashFullS - S.crashFloatS))
	end
	return math.min(off, S.maxOffsetM)
end

-- "SINKING 42 S" style countdown for the HUD: seconds until completely under (0 after).
function Rescue.secondsLeft(kind: string, t: number): number
	local endS = if kind == Rescue.DITCH then Rescue.SINK.ditchFullS else Rescue.SINK.crashFullS
	return math.max(0, math.ceil(endS - t))
end

-- Buoyancy and water drag on a destroyed aircraft (the flight model's forces are off
-- once it is wrecked). Same formula as FlightModel's ditching branch, for every hull
-- point (floats included: a wreck doesn't plane). env as in FlightModel; returns the
-- body-axis force (N) and moment (N m).
function Rescue.waterForces(cfg: any, mass: number, env: any): (number, number, number, number, number, number)
	local hull = cfg.hullPoints
	local buoyPerMetre = mass * Units.G / (#hull * DEPTH_SHARE)
	local fx, fy, fz, mx, my, mz = 0, 0, 0, 0, 0, 0
	local wx, wy, wz = env.wx, env.wy, env.wz
	for i, hp in hull do
		local depth = env.hullDepth[i]
		if depth and depth > 0 then
			local px, py, pz = hp[1], hp[2], hp[3]
			local pvx = env.vgx + (wy * pz - wz * py)
			local pvy = env.vgy + (wz * px - wx * pz)
			local pvz = env.vgz + (wx * py - wy * px)
			local d = math.min(depth, DEPTH_CAP)
			local b = buoyPerMetre * d
			local bx, by, bz = env.ux * b, env.uy * b, env.uz * b
			local speed = math.sqrt(pvx * pvx + pvy * pvy + pvz * pvz)
			local dragK = 0.5 * 1000 * speed * 0.9 * math.min(d, 1)
			-- a wreck is waterlogged: more damping than a floating hull so it settles
			dragK += mass / #hull * 0.6
			bx -= dragK * pvx
			by -= dragK * pvy
			bz -= dragK * pvz
			fx += bx
			fy += by
			fz += bz
			mx += py * bz - pz * by
			my += pz * bx - px * bz
			mz += px * by - py * bx
		end
	end
	return fx, fy, fz, mx, my, mz
end

-- Who comes. speed m/s; delay s before setting off; distM how far away they start
-- (for vehicles that don't come from a fire station or harbour of their own).
export type Unit = { role: string, count: number, speed: number, delay: number, distM: number }
function Rescue.plan(situation: string): { Unit }
	if situation == Rescue.LAND_CRASH then
		return {
			{ role = "police", count = 2, speed = 30, delay = 0, distM = 500 },
			{ role = "fireTruck", count = 2, speed = 24, delay = 1.5, distM = 500 },
			{ role = "ambulance", count = 2, speed = 26, delay = 3, distM = 500 },
		}
	elseif situation == Rescue.WATER_CRASH then
		return {
			{ role = "rescueBoat", count = 2, speed = 20, delay = 0, distM = 420 },
			{ role = "helicopter", count = 2, speed = 55, delay = 1, distM = 1100 },
		}
	elseif situation == Rescue.DITCH then
		return {
			{ role = "rescueBoat", count = 2, speed = 20, delay = 0, distM = 380 },
			{ role = "ferry", count = 1, speed = 14, delay = 0, distM = 380 },
			{ role = "helicopter", count = 1, speed = 55, delay = 1, distM = 1100 },
		}
	end
	return {}
end

-- Seconds from the call until a unit is at the scene.
function Rescue.arrivalTime(u: Unit, distM: number?): number
	return u.delay + (distM or u.distM) / u.speed
end

-- Parking spot `i` of `n` round the wreck (studs, relative to it), facing it. The ring
-- opens on the side the vehicles come from so nobody drives through the wreck.
function Rescue.slot(i: number, n: number, radius: number, fromAngle: number): (number, number)
	local spread = math.rad(150)
	local a = fromAngle + (if n <= 1 then 0 else (i - 1) / (n - 1) - 0.5) * spread
	return math.cos(a) * radius, math.sin(a) * radius
end

-- A start point `dist` studs from (x, z) from which a straight drive (or sail) to (x, z)
-- stays on good ground (`ok(x, z)`), trying `preferAngle` first and then turning further
-- and further away from it. Returns x, z, angle (from the site to the start), or nil.
function Rescue.findStart(ok: (number, number) -> boolean, x: number, z: number, dist: number, preferAngle: number, skipNear: number?): (number?, number?, number?)
	local step = math.rad(20)
	local skip = skipNear or 0
	for _, scale in { 1, 0.6, 0.35 } do
		local d = dist * scale
		for k = 0, 17 do
			local turn = math.ceil(k / 2) * step * (if k % 2 == 0 then 1 else -1)
			local a = preferAngle + turn
			local ux, uz = math.cos(a), math.sin(a)
			local good = true
			local s = math.max(skip, 0)
			while s <= d do
				if not ok(x + ux * s, z + uz * s) then
					good = false
					break
				end
				s += 40
			end
			if good then
				return x + ux * d, z + uz * d, a
			end
		end
	end
	return nil, nil, nil
end

-- Life rafts for a ditching: up to 4, with the passengers shared out.
function Rescue.rafts(passengers: number): { number }
	local n = math.clamp(math.ceil(passengers / 12), 1, 4)
	local out = {}
	local left = passengers
	for i = 1, n do
		local share = math.ceil(left / (n - i + 1))
		out[i] = share
		left -= share
	end
	return out
end

-- When the rafts go out (s after the ditching) and how long a raft takes to reach a boat.
Rescue.RAFT_OUT_S = 4
Rescue.RAFT_TRANSFER_S = 6

-- Seconds after the call when every passenger is aboard (the slowest boat's arrival plus
-- the raft transfer), for the given plan.
function Rescue.allAboardTime(units: { Unit }): number
	local latest = 0
	for _, u in units do
		if u.role == "rescueBoat" or u.role == "ferry" then
			latest = math.max(latest, Rescue.arrivalTime(u))
		end
	end
	return math.max(latest, Rescue.RAFT_OUT_S) + Rescue.RAFT_TRANSFER_S
end

-- One-line messages for the pilot.
function Rescue.callMessage(situation: string): string
	if situation == Rescue.LAND_CRASH then
		return "Mayday! Fire trucks, ambulances and police are on their way to the crash site."
	elseif situation == Rescue.WATER_CRASH then
		return "Crashed into the sea! The wreck will sink within a minute. Rescue boats and helicopters are on their way."
	end
	return "Ditched! This aircraft can't float: half under in 20 s, gone in 60 s. Rescue boats and a ferry are coming for the passengers."
end

return Rescue
