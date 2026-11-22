--!nonstrict
-- Offline 6-DOF rigid-body harness for the FlightModel (runs in the standalone `luau` CLI).
-- It mimics how the game uses the model inside Roblox: forces/moments are recomputed once
-- per "frame" (60 Hz) and held constant across 4 physics sub-steps (240 Hz), gravity is
-- applied by the "engine" (this harness), and the ground is a flat plane at y = 0.
-- World axes: x east, y up, z south (Roblox convention). Body axes: x right, y up, z aft.

local FlightModel = require("../src/shared/FlightModel")
local Units = require("../src/shared/Units")

local Sim = {}
Sim.__index = Sim

local sqrt = math.sqrt

-- 3x3 matrices stored row-major as {a,b,c,d,e,f,g,h,i}; R maps body -> world.
local function mulMV(m, x, y, z)
	return m[1] * x + m[2] * y + m[3] * z, m[4] * x + m[5] * y + m[6] * z, m[7] * x + m[8] * y + m[9] * z
end
local function mulMtV(m, x, y, z) -- transpose(m) * v : world -> body
	return m[1] * x + m[4] * y + m[7] * z, m[2] * x + m[5] * y + m[8] * z, m[3] * x + m[6] * y + m[9] * z
end
local function mulMM(a, b)
	return {
		a[1] * b[1] + a[2] * b[4] + a[3] * b[7], a[1] * b[2] + a[2] * b[5] + a[3] * b[8], a[1] * b[3] + a[2] * b[6] + a[3] * b[9],
		a[4] * b[1] + a[5] * b[4] + a[6] * b[7], a[4] * b[2] + a[5] * b[5] + a[6] * b[8], a[4] * b[3] + a[5] * b[6] + a[6] * b[9],
		a[7] * b[1] + a[8] * b[4] + a[9] * b[7], a[7] * b[2] + a[8] * b[5] + a[9] * b[8], a[7] * b[3] + a[8] * b[6] + a[9] * b[9],
	}
end
-- Rodrigues rotation matrix for axis-angle vector (x,y,z)
local function rotation(x, y, z)
	local th = sqrt(x * x + y * y + z * z)
	if th < 1e-12 then
		return { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	end
	local kx, ky, kz = x / th, y / th, z / th
	local c, s = math.cos(th), math.sin(th)
	local v = 1 - c
	return {
		c + kx * kx * v, kx * ky * v - kz * s, kx * kz * v + ky * s,
		ky * kx * v + kz * s, c + ky * ky * v, ky * kz * v - kx * s,
		kz * kx * v - ky * s, kz * ky * v + kx * s, c + kz * kz * v,
	}
end
local function orthonormalize(m)
	-- Gram-Schmidt on columns
	local c1x, c1y, c1z = m[1], m[4], m[7]
	local l = sqrt(c1x * c1x + c1y * c1y + c1z * c1z)
	c1x, c1y, c1z = c1x / l, c1y / l, c1z / l
	local c2x, c2y, c2z = m[2], m[5], m[8]
	local d = c1x * c2x + c1y * c2y + c1z * c2z
	c2x, c2y, c2z = c2x - d * c1x, c2y - d * c1y, c2z - d * c1z
	l = sqrt(c2x * c2x + c2y * c2y + c2z * c2z)
	c2x, c2y, c2z = c2x / l, c2y / l, c2z / l
	local c3x, c3y, c3z = c1y * c2z - c1z * c2y, c1z * c2x - c1x * c2z, c1x * c2y - c1y * c2x
	return { c1x, c2x, c3x, c1y, c2y, c3y, c1z, c2z, c3z }
end

Sim.rotation = rotation
Sim.mulMV = mulMV
Sim.mulMtV = mulMtV

-- opts: { x, y, z, headingDeg, pitchDeg, speed (m/s along nose), enginesRunning, gearDown, flaps, wind={x,y,z} }
function Sim.new(cfg, opts)
	local self = setmetatable({}, Sim)
	self.cfg = cfg
	self.model = FlightModel.new(cfg, { enginesRunning = opts.enginesRunning, gearDown = opts.gearDown, flaps = opts.flaps })
	self.env = FlightModel.newEnv(cfg)
	self.ctl = FlightModel.newControls()
	self.ctl.flaps = opts.flaps or 1
	self.ctl.gearDown = if opts.gearDown == nil then true else opts.gearDown
	self.px, self.py, self.pz = opts.x or 0, opts.y or 10, opts.z or 0
	-- heading about world y, then pitch about body x
	local h = math.rad(opts.headingDeg or 0)
	local p = math.rad(opts.pitchDeg or 0)
	-- body forward is -z; heading 0 = world -z. Rotating by -h about y turns -z toward +x.
	self.R = mulMM(rotation(0, -h, 0), rotation(p, 0, 0))
	local spd = opts.speed or 0
	local fxw, fyw, fzw = mulMV(self.R, 0, 0, -1)
	self.vx, self.vy, self.vz = fxw * spd, fyw * spd, fzw * spd
	self.wx, self.wy, self.wz = 0, 0, 0 -- world angular velocity
	self.time = 0
	self.wind = opts.wind or { x = 0, y = 0, z = 0 }
	self.groundY = 0
	local m = cfg.mass
	self.I = { cfg.inertia.pitch, cfg.inertia.yaw, cfg.inertia.roll } -- about body x, y, z
	self.maxG = 0
	return self
end

-- Place the aircraft so its main wheels just touch the ground at rest.
function Sim:settleOnGround()
	local u = self.cfg.gear.units[2]
	local h = -(u.pos[2] - u.strutLength - u.wheelRadius) - 0.02
	self.py = self.groundY + h
end

function Sim:prepareEnv()
	local env, R, cfg = self.env, self.R, self.cfg
	env.vgx, env.vgy, env.vgz = mulMtV(R, self.vx, self.vy, self.vz)
	env.vax, env.vay, env.vaz = mulMtV(R, self.vx - self.wind.x, self.vy - self.wind.y, self.vz - self.wind.z)
	env.wx, env.wy, env.wz = mulMtV(R, self.wx, self.wy, self.wz)
	env.ux, env.uy, env.uz = mulMtV(R, 0, 1, 0)
	env.altitude = self.py
	-- height of the wheels above ground, approximated as CoM height minus static gear height
	env.agl = self.py - self.groundY - 3.9
	local dxw, dyw, dzw = mulMV(R, 0, -1, 0)
	local nbx, nby, nbz = mulMtV(R, 0, 1, 0)
	for i, u in cfg.gear.units do
		local h = env.gearHits[i]
		local ox, oy, oz = mulMV(R, u.pos[1], u.pos[2], u.pos[3])
		oy += self.py
		if dyw < -0.05 then
			local d = (oy - self.groundY) / -dyw
			local maxLen = u.strutLength + u.wheelRadius + 1
			if d > 0 and d < maxLen then
				h.hit, h.dist, h.nx, h.ny, h.nz = true, d, nbx, nby, nbz
			else
				h.hit = false
			end
		else
			h.hit = false
		end
	end
end

-- Advance one 60 Hz frame (4 x 240 Hz substeps).
function Sim:frame()
	local dtFrame = 1 / 60
	self:prepareEnv()
	local r = self.model:step(self.env, self.ctl, dtFrame)
	local mass = self.model:currentMass()
	-- body forces -> world
	local fwx, fwy, fwz = mulMV(self.R, r.fx, r.fy, r.fz)
	local mbx, mby, mbz = r.mx, r.my, r.mz
	local sub = 4
	local h = dtFrame / sub
	for _ = 1, sub do
		local ax, ay, az = fwx / mass, fwy / mass - Units.G, fwz / mass
		self.vx += ax * h
		self.vy += ay * h
		self.vz += az * h
		self.px += self.vx * h
		self.py += self.vy * h
		self.pz += self.vz * h
		-- angular: body frame Euler equations, diagonal inertia
		local bx, by, bz = mulMtV(self.R, self.wx, self.wy, self.wz)
		local I = self.I
		local Ix, Iy, Iz = I[1], I[2], I[3]
		local hx, hy, hz = Ix * bx, Iy * by, Iz * bz
		-- gyroscopic term omega x (I omega)
		local gx = by * hz - bz * hy
		local gy = bz * hx - bx * hz
		local gz = bx * hy - by * hx
		bx += (mbx - gx) / Ix * h
		by += (mby - gy) / Iy * h
		bz += (mbz - gz) / Iz * h
		self.R = orthonormalize(mulMM(self.R, rotation(bx * h, by * h, bz * h)))
		self.wx, self.wy, self.wz = mulMV(self.R, bx, by, bz)
	end
	-- crude hard ground for the fuselage so a collapsed gear doesn't fall through
	if self.py < self.groundY + 1.9 then
		self.py = self.groundY + 1.9
		if self.vy < 0 then
			self.vy = 0
		end
	end
	self.time += dtFrame
	self.maxG = math.max(self.maxG, math.abs(r.gLoad))
	return r
end

function Sim:attitude()
	local ux, uy, uz = mulMtV(self.R, 0, 1, 0)
	local pitch = math.asin(math.clamp(-uz, -1, 1))
	local bank = math.atan2(-ux, uy)
	local fx, _, fz = mulMV(self.R, 0, 0, -1)
	local heading = Units.headingFromXZ(fx, fz)
	return math.deg(pitch), math.deg(bank), heading
end

function Sim:groundSpeed()
	return sqrt(self.vx * self.vx + self.vz * self.vz)
end

function Sim:isFinite()
	local vals = { self.px, self.py, self.pz, self.vx, self.vy, self.vz, self.wx, self.wy, self.wz }
	for _, v in vals do
		if v ~= v or v == math.huge or v == -math.huge then
			return false
		end
	end
	return true
end

return Sim
