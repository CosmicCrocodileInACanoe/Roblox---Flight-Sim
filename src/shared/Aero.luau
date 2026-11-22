--!strict
-- Aerodynamic coefficient curves and per-panel force evaluation (pure, allocation-free).
--
-- A "panel" is one lifting surface (a half-wing, the tailplane, the fin). Each panel sees
-- its own local airflow (CoM velocity + omega x r), so roll/pitch/yaw damping, weathervane
-- stability, dihedral effect and asymmetric damage all fall out of the same equations:
--
--   L = 0.5 * rho * V^2 * S * Cl(alpha, flaps, controls)
--   D = 0.5 * rho * V^2 * S * Cd(alpha, configuration)
--
-- Lift acts perpendicular to the local airflow inside the panel's chord/normal plane,
-- drag acts along the airflow. Everything is in body axes (x right, y up, z aft), SI units.

local Aero = {}

local sin, cos, atan2, sqrt, abs, pi = math.sin, math.cos, math.atan2, math.sqrt, math.abs, math.pi

local function smoothstep(e0: number, e1: number, x: number): number
	local t = (x - e0) / (e1 - e0)
	if t < 0 then
		t = 0
	elseif t > 1 then
		t = 1
	end
	return t * t * (3 - 2 * t)
end

local function wrapPi(a: number): number
	a = a % (2 * pi)
	if a > pi then
		a -= 2 * pi
	end
	return a
end
Aero.wrapPi = wrapPi

-- Post-stall model: a flat plate keeps producing some lift with very high drag, which is
-- what makes a stall a mushing, recoverable descent rather than an instant fall.
local POST_STALL_CL = 1.15
local POST_STALL_CD = 1.9

-- Lift coefficient.
-- Returns (cl, linearCl, stallBlend) where stallBlend is 0 in attached flow and 1 when
-- fully separated. Negative stall happens at 80% of the positive stall angle.
function Aero.liftCoefficient(alpha: number, cl0: number, clAlpha: number, alphaStall: number, stallWidth: number): (number, number, number)
	alpha = wrapPi(alpha)
	local linear = cl0 + clAlpha * alpha
	local sigma
	if alpha >= 0 then
		sigma = smoothstep(alphaStall, alphaStall + stallWidth, alpha)
	else
		local negStall = alphaStall * 0.8
		sigma = smoothstep(negStall, negStall + stallWidth, -alpha)
	end
	local plate = POST_STALL_CL * sin(2 * alpha)
	return linear * (1 - sigma) + plate * sigma, linear, sigma
end

-- Drag coefficient for a panel.
function Aero.dragCoefficient(alpha: number, linearCl: number, sigma: number, cd0: number, aspect: number, oswald: number, inducedFactor: number): number
	alpha = wrapPi(alpha)
	local induced = (linearCl * linearCl) / (pi * oswald * aspect) * inducedFactor
	local s = sin(alpha)
	return cd0 + induced * (1 - sigma) + POST_STALL_CD * s * s * sigma
end

-- Ground effect: induced drag factor (Hoerner/McCormick approximation) and a small lift
-- bonus when the wing is within one span of the ground.
function Aero.groundEffect(heightM: number, span: number): (number, number)
	if heightM >= span or heightM ~= heightM then
		return 1, 1
	end
	local h = math.max(heightM, 0.05)
	local r = 16 * h / span
	local inducedFactor = (r * r) / (1 + r * r)
	local liftBonus = 1 + 0.08 * (1 - h / span)
	return inducedFactor, liftBonus
end

export type PanelResult = {
	fx: number,
	fy: number,
	fz: number,
	mx: number, -- pure aerodynamic pitching moment (cm0) about the panel, body x
	alpha: number,
	sigma: number,
	cl: number,
	q: number,
	lift: number,
	drag: number,
}

-- Evaluate one panel.
--   p: panel config (normal, area, aspect, oswald, clAlpha, alphaStall, stallWidth, cd0, cm0, chord, incidence)
--   vx, vy, vz: velocity of the panel THROUGH the air, body axes (m/s)
--   rho: air density
--   cl0Add, stallAdd, dCl, dCd, dCm: configuration increments (flaps, controls, spoilers)
--   liftScale: 0..1 structural effectiveness (damage)
--   inducedFactor: ground-effect induced drag factor
--   out: result table, overwritten in place
function Aero.panel(
	p: any,
	vx: number,
	vy: number,
	vz: number,
	rho: number,
	cl0Add: number,
	stallAdd: number,
	dCl: number,
	dCd: number,
	dCm: number,
	liftScale: number,
	inducedFactor: number,
	out: PanelResult
): PanelResult
	local n = p.normal
	local nx, ny, nz = n[1], n[2], n[3]
	-- Chord direction is body forward (0, 0, -1).
	local u = -vz
	local vn = vx * nx + vy * ny + vz * nz
	local v2 = u * u + vn * vn
	out.fx, out.fy, out.fz, out.mx = 0, 0, 0, 0
	out.alpha, out.sigma, out.cl, out.q, out.lift, out.drag = 0, 0, 0, 0, 0, 0
	if v2 < 0.04 then
		return out
	end
	local v = sqrt(v2)
	local alpha = atan2(-vn, u) + p.incidence
	local cl, linear, sigma = Aero.liftCoefficient(alpha, p.cl0 + cl0Add, p.clAlpha, p.alphaStall + stallAdd, p.stallWidth)
	-- Control surfaces lose some authority in separated flow.
	cl = (cl + dCl * (1 - 0.5 * sigma)) * liftScale
	local cd = Aero.dragCoefficient(alpha, linear * liftScale, sigma, p.cd0 + dCd, p.aspect, p.oswald, inducedFactor)
	local q = 0.5 * rho * v2
	local qs = q * p.area
	local lift = qs * cl
	local drag = qs * cd
	local invV = 1 / v
	-- lift direction: (u*n + vn*(0,0,1)) / V ; motion direction: (vn*n + u*(0,0,-1)) / V
	local lx, ly, lz = u * nx * invV, u * ny * invV, (u * nz + vn) * invV
	local mx, my, mz = vn * nx * invV, vn * ny * invV, (vn * nz - u) * invV
	out.fx = lift * lx - drag * mx
	out.fy = lift * ly - drag * my
	out.fz = lift * lz - drag * mz
	out.mx = qs * p.chord * (p.cm0 + dCm) * liftScale
	out.alpha = wrapPi(alpha)
	out.sigma = sigma
	out.cl = cl
	out.q = q
	out.lift = lift
	out.drag = drag
	return out
end

function Aero.newPanelResult(): PanelResult
	return { fx = 0, fy = 0, fz = 0, mx = 0, alpha = 0, sigma = 0, cl = 0, q = 0, lift = 0, drag = 0 }
end

-- Quadratic drag on a body axis: F = -0.5 rho |v| v CdA
function Aero.bodyDrag(v: number, rho: number, cdA: number): number
	return -0.5 * rho * abs(v) * v * cdA
end

return Aero
