--!strict
-- Raycast landing-gear model: progressive spring-damper strut + tyre friction.
-- Wheels themselves never collide; the caller supplies a ground hit per gear leg
-- (distance along the strut and the ground normal, in body axes). If a strut is
-- over-compressed or collapsed, the airframe's real collision parts take over.

local Gear = {}

local sqrt = math.sqrt

export type GearState = {
	cfg: any,
	k: number,
	c: number,
	compression: number,
	compressionRate: number,
	load: number,
	onGround: boolean,
	wasOnGround: boolean,
	contactTime: number,
	touchdownSink: number, -- sink rate (m/s) captured at first contact
	touchdownSide: number,
	bottomed: boolean,
	steer: number, -- radians, current wheel angle
	slip: number, -- lateral speed at contact
	longSpeed: number,
	-- contact point (body) and force (body), for diagnostics/effects
	cpx: number, cpy: number, cpz: number,
	fx: number, fy: number, fz: number,
}

-- Derive spring and damper rates from aircraft mass and gear geometry.
function Gear.derive(units: { any }, mass: number, g: number): { GearState }
	-- Static load split from fore/aft positions relative to the CoM (z = 0).
	local noseZ, mainZ, mains, noses = 0, 0, 0, 0
	for _, u in units do
		if u.steerMaxDeg > 0 then
			noseZ = u.pos[3]
			noses += 1
		else
			mainZ += u.pos[3]
			mains += 1
		end
	end
	mainZ = if mains > 0 then mainZ / mains else 1
	local noseFraction = mainZ / (mainZ - noseZ)
	local weight = mass * g

	local states = {}
	for i, u in units do
		local share = if u.steerMaxDeg > 0 then noseFraction / math.max(1, noses) else (1 - noseFraction) / math.max(1, mains)
		local load = weight * share
		local sc = u.staticCompression
		local x = sc * u.travel
		local k = load / (x * (1 + 3 * sc * sc))
		local mEff = mass * share
		local c = 2 * u.dampingRatio * sqrt(k * mEff)
		states[i] = {
			cfg = u,
			k = k,
			c = c,
			compression = 0,
			compressionRate = 0,
			load = 0,
			onGround = false,
			wasOnGround = false,
			contactTime = 0,
			touchdownSink = 0,
			touchdownSide = 0,
			bottomed = false,
			steer = 0,
			slip = 0,
			longSpeed = 0,
			cpx = u.pos[1], cpy = u.pos[2] - u.strutLength - u.wheelRadius, cpz = u.pos[3],
			fx = 0, fy = 0, fz = 0,
		}
	end
	return states
end

local function sat(x: number, s: number): number
	local v = x / s
	if v > 1 then
		return 1
	elseif v < -1 then
		return -1
	end
	return v
end

-- Compute one gear leg.
--   hit: whether the ray found ground; dist: metres from strut attach point along -y body
--   nx,ny,nz: ground normal in body axes
--   pvx,pvy,pvz: velocity of the contact point relative to the ground, body axes
--   steerTarget: radians; brake: 0..1; friction: {rolling, brake, lateral}
--   stiffnessScale, brakeScale: from damage
function Gear.step(
	gs: GearState,
	active: boolean,
	hit: boolean,
	dist: number,
	nx: number,
	ny: number,
	nz: number,
	pvx: number,
	pvy: number,
	pvz: number,
	steerTarget: number,
	brake: number,
	friction: any,
	stiffnessScale: number,
	brakeScale: number,
	dt: number
)
	local u = gs.cfg
	gs.wasOnGround = gs.onGround
	gs.fx, gs.fy, gs.fz = 0, 0, 0
	gs.bottomed = false
	gs.load = 0

	-- Steering responds at a finite rate.
	local steerRate = math.rad(60) * dt
	gs.steer += math.clamp(steerTarget - gs.steer, -steerRate, steerRate)

	local restLength = u.strutLength + u.wheelRadius
	if not active or not hit or dist >= restLength then
		gs.onGround = false
		gs.compression = 0
		gs.compressionRate = 0
		gs.contactTime = 0
		gs.cpx, gs.cpy, gs.cpz = u.pos[1], u.pos[2] - restLength, u.pos[3]
		return
	end

	local x = restLength - dist
	local ny2 = if ny < 0.3 then 0.3 else ny
	-- Rate of compression: point velocity into the ground, projected along the strut.
	local xdot = -(pvx * nx + pvy * ny + pvz * nz) / ny2

	if not gs.wasOnGround then
		gs.touchdownSink = math.max(0, xdot)
		gs.contactTime = 0
	end
	gs.contactTime += dt

	local travel = u.travel
	local xr = x / travel
	local k = gs.k * stiffnessScale
	local spring = k * x * (1 + 3 * xr * xr)
	local damper = gs.c * stiffnessScale * xdot
	local force = spring + damper
	if force < 0 then
		force = 0
	end
	local maxForce = gs.k * travel * 25
	if force > maxForce then
		force = maxForce
	end
	if x > travel then
		gs.bottomed = true
	end

	gs.onGround = true
	gs.compression = x
	gs.compressionRate = xdot
	gs.load = force

	-- Contact point (bottom of the wheel).
	local cpx, cpy, cpz = u.pos[1], u.pos[2] - dist, u.pos[3]
	gs.cpx, gs.cpy, gs.cpz = cpx, cpy, cpz

	-- Wheel heading: body forward rotated by the steering angle about body y,
	-- projected onto the ground plane.
	local s, c = math.sin(gs.steer), math.cos(gs.steer)
	local fx0, fy0, fz0 = s, 0, -c
	local dn = fx0 * nx + fy0 * ny + fz0 * nz
	local fwx, fwy, fwz = fx0 - dn * nx, fy0 - dn * ny, fz0 - dn * nz
	local fl = sqrt(fwx * fwx + fwy * fwy + fwz * fwz)
	if fl < 1e-6 then
		fwx, fwy, fwz, fl = 0, 0, -1, 1
	end
	fwx, fwy, fwz = fwx / fl, fwy / fl, fwz / fl
	-- right = forward x normal
	local rx = fwy * nz - fwz * ny
	local ry = fwz * nx - fwx * nz
	local rz = fwx * ny - fwy * nx

	local vLong = pvx * fwx + pvy * fwy + pvz * fwz
	local vLat = pvx * rx + pvy * ry + pvz * rz
	gs.longSpeed = vLong
	gs.slip = vLat
	if not gs.wasOnGround then
		gs.touchdownSide = math.abs(vLat)
	end

	local n = force * ny2
	local fLong = -friction.rolling * n * sat(vLong, 0.3) - friction.brake * brake * brakeScale * n * sat(vLong, 0.4)
	local fLat = -friction.lateral * n * sat(vLat, 0.4)

	gs.fx = fwx * fLong + rx * fLat
	gs.fy = force + fwy * fLong + ry * fLat
	gs.fz = fwz * fLong + rz * fLat
end

return Gear
