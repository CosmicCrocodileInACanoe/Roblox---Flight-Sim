--!strict
-- Small allocation-free numeric helpers shared by the physics modules.

local MathUtil = {}

function MathUtil.isFinite(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

function MathUtil.finiteOr(x: number, fallback: number): number
	if x == x and x ~= math.huge and x ~= -math.huge then
		return x
	end
	return fallback
end

function MathUtil.clamp(x: number, lo: number, hi: number): number
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

-- Saturating linear function: x/scale clamped to [-1, 1].
function MathUtil.sat(x: number, scale: number): number
	local v = x / scale
	if v > 1 then
		return 1
	elseif v < -1 then
		return -1
	end
	return v
end

function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function MathUtil.smoothstep(e0: number, e1: number, x: number): number
	local t = (x - e0) / (e1 - e0)
	if t < 0 then
		t = 0
	elseif t > 1 then
		t = 1
	end
	return t * t * (3 - 2 * t)
end

-- Move `current` toward `target` by at most `maxDelta`.
function MathUtil.approach(current: number, target: number, maxDelta: number): number
	if current < target then
		return math.min(current + maxDelta, target)
	end
	return math.max(current - maxDelta, target)
end

-- First-order low-pass, frame-rate independent.
function MathUtil.expSmooth(current: number, target: number, timeConstant: number, dt: number): number
	if timeConstant <= 0 then
		return target
	end
	return target + (current - target) * math.exp(-dt / timeConstant)
end

-- Wrap an angle in radians to (-pi, pi].
function MathUtil.wrapPi(a: number): number
	local twoPi = 2 * math.pi
	a = a % twoPi
	if a > math.pi then
		a -= twoPi
	end
	return a
end

-- Wrap degrees to (-180, 180].
function MathUtil.wrap180(a: number): number
	a = a % 360
	if a > 180 then
		a -= 360
	end
	return a
end

-- Camera auto re-centre: after `delay` seconds without the pilot looking around, ease
-- the look angle (radians) back toward `target` with a ~1.2 s time constant, taking the
-- short way round. Returns the new angle.
function MathUtil.recenter(angle: number, target: number, idle: number, delay: number, dt: number): number
	if idle < delay then
		return angle
	end
	local d = MathUtil.wrapPi(angle - target)
	d *= math.exp(-dt / 1.2)
	if math.abs(d) < 1e-3 then
		d = 0
	end
	return target + d
end

return MathUtil
