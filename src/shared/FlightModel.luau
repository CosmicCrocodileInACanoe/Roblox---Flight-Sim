--!strict
-- FlightModel: the complete aircraft force/moment model, independent of Roblox.
--
-- Inputs (per frame, all body axes, SI):
--   env.vax,vay,vaz   velocity of the CoM through the AIR (ground velocity minus wind)
--   env.vgx,vgy,vgz   velocity of the CoM relative to the GROUND
--   env.wx,wy,wz      angular velocity (rad/s)
--   env.ux,uy,uz      world "up" expressed in body axes (for buoyancy and attitude)
--   env.altitude      metres above sea level; env.agl metres of CoM above ground
--   env.gearHits[i]   { hit, dist, nx, ny, nz } from a ray cast down each strut
--   env.hullDepth[i]  metres each hull point is below the water surface (<= 0: dry)
-- Output: model.result.fx..fz (N) and mx..mz (N m) about the CoM, in body axes,
-- excluding gravity (the physics engine applies gravity itself).

local function req(name: string): any
	if script then
		return (require :: any)((script :: any).Parent[name])
	end
	return (require :: any)("./" .. name)
end

local Units = req("Units")
local Aero = req("Aero")
local Engine = req("Engine")
local Gear = req("Gear")
local Damage = req("Damage")

local FlightModel = {}
FlightModel.__index = FlightModel

local sqrt, abs, clamp = math.sqrt, math.abs, math.clamp

local function isFinite(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

-- Interpolate a per-notch table at a continuous flap position (1-based).
local function notchLerp(t: { number }, pos: number): number
	local i = math.floor(pos)
	if i < 1 then
		return t[1]
	elseif i >= #t then
		return t[#t]
	end
	local f = pos - i
	return t[i] + (t[i + 1] - t[i]) * f
end
FlightModel.notchLerp = notchLerp

export type Controls = {
	pitch: number, -- -1..1, +1 nose up
	roll: number, -- -1..1, +1 roll right
	yaw: number, -- -1..1, +1 nose right
	throttle: number, -- 0..1
	flaps: number, -- notch index 1..N
	gearDown: boolean,
	brake: number, -- 0..1
	parkingBrake: boolean,
	speedbrake: number, -- 0..1
	reverse: boolean,
	trim: number, -- -1..1
}

function FlightModel.newControls(): Controls
	return {
		pitch = 0, roll = 0, yaw = 0, throttle = 0, flaps = 1, gearDown = true,
		brake = 0, parkingBrake = false, speedbrake = 0, reverse = false, trim = 0,
	}
end

function FlightModel.newEnv(cfg: any): any
	local hits = {}
	for i = 1, #cfg.gear.units do
		hits[i] = { hit = false, dist = 0, nx = 0, ny = 1, nz = 0 }
	end
	local depths = {}
	for i = 1, #cfg.hullPoints do
		depths[i] = -1
	end
	return {
		vax = 0, vay = 0, vaz = 0,
		vgx = 0, vgy = 0, vgz = 0,
		wx = 0, wy = 0, wz = 0,
		ux = 0, uy = 1, uz = 0,
		altitude = 0, agl = 1000,
		gearHits = hits,
		hullDepth = depths,
	}
end

-- opts: { enginesRunning, gearDown, flaps, fuel }
function FlightModel.new(cfg: any, opts: any?)
	local o = opts or {}
	local self = setmetatable({}, FlightModel) :: any
	self.cfg = cfg
	self.fuel = o.fuel or cfg.fuel.initial
	self.engines = {}
	for i, e in cfg.engines do
		self.engines[i] = Engine.new(e, o.enginesRunning == true)
	end
	self.gears = Gear.derive(cfg.gear.units, cfg.mass, Units.G)
	local gearDown = if o.gearDown == nil then true else o.gearDown
	self.gearExtension = if gearDown then 1 else 0
	self.gearCommand = gearDown
	self.flapPos = o.flaps or 1
	self.speedbrakePos = 0
	self.elevator = 0
	self.aileron = 0
	self.rudder = 0
	-- toughness > 1 (easy mode) raises every damage limit without touching the shared config
	local tough = o.toughness or 1
	local comps = cfg.components
	self.gearLimits, self.gLimit = cfg.gearLimits, cfg.gLimit
	if tough ~= 1 then
		comps = {}
		for name, c in cfg.components do
			local copy = table.clone(c)
			copy.impactThreshold = c.impactThreshold * tough
			copy.impactDestroy = c.impactDestroy * (1 + (tough - 1) * 0.6)
			comps[name] = copy
		end
		local gl = cfg.gearLimits
		self.gearLimits = {
			sinkDegrade = gl.sinkDegrade * tough, sinkFail = gl.sinkFail * tough,
			sinkDetach = gl.sinkDetach * tough, sideSpeedFail = gl.sideSpeedFail * tough,
		}
		self.gLimit = cfg.gLimit * (1 + (tough - 1) * 0.5)
	end
	self.damage = Damage.new(comps, { breakApart = o.breakApart == true })
	self.failures = {} :: { [string]: any }
	self.mass = cfg.mass
	self.airborneTime = 0
	self.groundTime = 0
	self.touchdownCount = 0
	self.lastTouchdown = nil :: any
	self.wasInWater = {}
	for i = 1, #cfg.hullPoints do
		self.wasInWater[i] = false
	end
	self.panelResults = {}
	for i = 1, #cfg.aero.panels do
		self.panelResults[i] = Aero.newPanelResult()
	end
	self.result = {
		fx = 0, fy = 0, fz = 0, mx = 0, my = 0, mz = 0,
		alpha = 0, beta = 0, tas = 0, ias = 0, rho = 1.225,
		lift = 0, drag = 0, thrust = 0, gLoad = 1,
		stall = false, stallWarning = false, wheelsOnGround = 0, onGround = false,
		inWater = false, fault = false, waterImpact = 0,
	}
	return self
end

-- Mark a failure. kind: "engine1", "engine2", "elevatorJam", "aileronJam", "rudderJam",
-- "gearStuck", "flapsJam", "fuelLeak", "leftWingDamage"
function FlightModel:setFailure(kind: string, on: boolean)
	local f = self.failures
	if not on then
		f[kind] = nil
		return
	end
	if kind == "engine1" or kind == "engine2" then
		-- engine1 = the left-most engine, engine2 = the right-most (works for 2 or 4 engines)
		local best, bestX = nil, nil
		for i, ec in self.cfg.engines do
			local x = ec.pos[1]
			if bestX == nil or (kind == "engine1" and x < bestX) or (kind == "engine2" and x > bestX) then
				best, bestX = i, x
			end
		end
		if best and self.engines[best] then
			Engine.fail(self.engines[best], false)
		end
	elseif kind == "elevatorJam" then
		f.elevatorJam = self.elevator
		return
	elseif kind == "aileronJam" then
		f.aileronJam = self.aileron
		return
	elseif kind == "rudderJam" then
		f.rudderJam = self.rudder
		return
	elseif kind == "leftWingDamage" then
		Damage.hurt(self.damage, "LeftWing", 0.45, false)
	end
	f[kind] = true
end

function FlightModel:startEngines()
	for i, e in self.engines do
		if Damage.isAttached(self.damage, self.cfg.engines[i].component) and not e.failed then
			Engine.start(e)
		end
	end
end

function FlightModel:stopEngines()
	for _, e in self.engines do
		Engine.stop(e)
	end
end

function FlightModel:enginesRunning(): boolean
	for _, e in self.engines do
		if e.running then
			return true
		end
	end
	return false
end

function FlightModel:currentMass(): number
	local cfg = self.cfg
	local m = cfg.mass - (cfg.fuel.initial - self.fuel)
	for name, c in self.damage.components do
		if c.state == "detached" then
			m -= c.cfg.mass
		else
			m -= (c.cfg.mass or 0) * (c.lostFraction or 0)
		end
	end
	return math.max(m, cfg.mass * 0.3)
end

-- Advance systems and compute forces. Returns self.result.
function FlightModel:step(env: any, ctl: Controls, dt: number)
	local cfg = self.cfg
	local aero = cfg.aero
	local dmg = self.damage
	local r = self.result
	local fails = self.failures

	if dt <= 0 or dt ~= dt then
		dt = 1 / 60
	end
	dt = math.min(dt, 0.1)

	local altitude = env.altitude
	local rho = Units.airDensity(altitude)
	local sigmaRho = rho / 1.225
	local vax, vay, vaz = env.vax, env.vay, env.vaz
	local wx, wy, wz = env.wx, env.wy, env.wz
	local tas = sqrt(vax * vax + vay * vay + vaz * vaz)
	local ias = tas * sqrt(sigmaRho)
	r.rho, r.tas, r.ias = rho, tas, ias
	r.alpha = math.atan2(-vay, math.max(-vaz, 0.1))
	r.beta = if tas > 1 then math.asin(clamp(vax / tas, -1, 1)) else 0

	local anyGround = false
	for _, g in self.gears do
		if g.onGround then
			anyGround = true
			break
		end
	end

	-- Systems ---------------------------------------------------------------
	-- Flaps
	local flapLabels = aero.flaps.labels
	local flapCmd = clamp(ctl.flaps, 1, #flapLabels)
	if not fails.flapsJam then
		local rate = dt / aero.flaps.travelTime
		self.flapPos += clamp(flapCmd - self.flapPos, -rate, rate)
	end
	-- Gear (weight-on-wheels interlock prevents retraction on the ground)
	local gearCmd = ctl.gearDown
	if anyGround or cfg.gear.fixed then
		-- weight on wheels, or fixed (non-retracting) gear
		gearCmd = true
	end
	self.gearCommand = gearCmd
	if not fails.gearStuck then
		local rate = dt / cfg.gear.retractTime
		self.gearExtension = clamp(self.gearExtension + (if gearCmd then rate else -rate), 0, 1)
	end
	-- Speedbrake
	self.speedbrakePos += clamp(ctl.speedbrake - self.speedbrakePos, -dt, dt)
	-- Control surfaces (rate limited; jammed surfaces stay put)
	local surfRate = math.rad(70) * dt
	local elevTarget = clamp(ctl.pitch, -1, 1) * aero.elevator.maxDeflection
	local ailTarget = clamp(ctl.roll, -1, 1) * aero.aileron.maxDeflection
	local rudTarget = clamp(ctl.yaw, -1, 1) * aero.rudder.maxDeflection
	if fails.elevatorJam then
		elevTarget = fails.elevatorJam
	end
	if fails.aileronJam then
		ailTarget = fails.aileronJam
	end
	if fails.rudderJam then
		rudTarget = fails.rudderJam
	end
	self.elevator += clamp(elevTarget - self.elevator, -surfRate, surfRate)
	self.aileron += clamp(ailTarget - self.aileron, -surfRate, surfRate)
	self.rudder += clamp(rudTarget - self.rudder, -surfRate, surfRate)
	local elevTotal = self.elevator + clamp(ctl.trim, -1, 1) * aero.trim.maxDeflection

	-- Accumulators
	local fx, fy, fz, mx, my, mz = 0, 0, 0, 0, 0, 0

	-- Engines ---------------------------------------------------------------
	local totalThrust, fuelFlow = 0, 0
	-- afterburners light for the take-off run and with the gear up, never on an approach
	local reheatAllowed = anyGround or not ctl.gearDown
	local hasFuel = self.fuel > 0
	for i, e in self.engines do
		local ecfg = cfg.engines[i]
		local compState = Damage.state(dmg, ecfg.component)
		if (compState == "failed" or compState == "detached") and not e.failed then
			Engine.fail(e, compState == "failed")
		end
		local thrust = 0
		if compState ~= "detached" then
			thrust = Engine.update(e, ctl.throttle, ctl.reverse, anyGround, sigmaRho, tas, hasFuel, dt, reheatAllowed, tas / Units.speedOfSound(altitude))
			if compState == "degraded" then
				thrust *= 0.7
			end
		end
		fuelFlow += e.fuelFlow
		totalThrust += thrust
		local ax, ay, az = ecfg.axis[1], ecfg.axis[2], ecfg.axis[3]
		local tx, ty, tz = ax * thrust, ay * thrust, az * thrust
		local px, py, pz = ecfg.pos[1], ecfg.pos[2], ecfg.pos[3]
		fx += tx
		fy += ty
		fz += tz
		mx += py * tz - pz * ty
		my += pz * tx - px * tz
		mz += px * ty - py * tx
	end
	if fails.fuelLeak then
		fuelFlow += 12
	end
	self.fuel = math.max(0, self.fuel - fuelFlow * dt)
	r.thrust = totalThrust

	-- Aerodynamic panels ------------------------------------------------------
	local inducedFactor, liftBonus = 1, 1
	if aero.groundEffect then
		inducedFactor, liftBonus = Aero.groundEffect(env.agl, aero.wingSpan)
	end
	local flapCl = notchLerp(aero.flaps.dCl, self.flapPos)
	local flapCd = notchLerp(aero.flaps.dCd, self.flapPos)
	local flapStall = math.rad(notchLerp(aero.flaps.dStallDeg, self.flapPos))
	local flapCm = notchLerp(aero.flaps.dCm, self.flapPos)
	local sb = self.speedbrakePos
	local totalLift, totalDrag = 0, 0
	local maxSigma, wingAlphaMax, stallAlpha = 0, -math.huge, 0
	for i, p in aero.panels do
		local pr = self.panelResults[i]
		local eff = Damage.effectiveness(dmg, p.component)
		if eff <= 0 then
			pr.fx, pr.fy, pr.fz, pr.mx, pr.lift, pr.drag, pr.alpha, pr.sigma = 0, 0, 0, 0, 0, 0, 0, 0
			continue
		end
		local rx, ry, rz = p.pos[1], p.pos[2], p.pos[3]
		-- local air velocity = v_air + omega x r
		local lvx = vax + (wy * rz - wz * ry)
		local lvy = vay + (wz * rx - wx * rz)
		local lvz = vaz + (wx * ry - wy * rx)
		local cl0Add, stallAdd, dCl, dCd, dCm, ind, scale = 0, 0, 0, 0, 0, 1, eff
		if p.role == "wing" then
			cl0Add = flapCl + sb * aero.speedbrake.dCl
			stallAdd = flapStall
			dCd = flapCd + sb * aero.speedbrake.dCd
			dCm = flapCm
			-- side -1 = left wing. Roll right (+aileron) raises left-wing lift.
			dCl = -p.side * self.aileron * aero.aileron.clPerRad
			ind = inducedFactor
			scale = eff * liftBonus
		elseif p.role == "hstab" then
			dCl = -elevTotal * aero.elevator.clPerRad
		elseif p.role == "vstab" then
			dCl = -self.rudder * aero.rudder.clPerRad
		end
		Aero.panel(p, lvx, lvy, lvz, rho, cl0Add, stallAdd, dCl, dCd, dCm, scale, ind, pr)
		-- Damaged panels also produce extra drag.
		local extraDrag = 0
		if eff < 1 then
			extraDrag = pr.q * p.area * 0.04 * (1 - eff)
			local v = sqrt(lvx * lvx + lvy * lvy + lvz * lvz)
			if v > 0.1 then
				pr.fx -= extraDrag * lvx / v
				pr.fy -= extraDrag * lvy / v
				pr.fz -= extraDrag * lvz / v
			end
		end
		fx += pr.fx
		fy += pr.fy
		fz += pr.fz
		mx += ry * pr.fz - rz * pr.fy + pr.mx
		my += rz * pr.fx - rx * pr.fz
		mz += rx * pr.fy - ry * pr.fx
		totalLift += pr.lift
		totalDrag += pr.drag + extraDrag
		if p.role == "wing" then
			if pr.sigma > maxSigma then
				maxSigma = pr.sigma
			end
			if pr.alpha > wingAlphaMax then
				wingAlphaMax = pr.alpha
				stallAlpha = p.alphaStall + stallAdd
			end
		end
	end

	-- Fuselage / gear / damage drag ---------------------------------------------
	local bd = aero.bodyDrag
	local dfx = Aero.bodyDrag(vax, rho, bd.x)
	local dfy = Aero.bodyDrag(vay, rho, bd.y)
	local dfz = Aero.bodyDrag(vaz, rho, bd.z)
	if tas > 0.1 and self.gearExtension > 0 then
		local gq = 0.5 * rho * tas * aero.gearDragArea * self.gearExtension
		dfx -= gq * vax
		dfy -= gq * vay
		dfz -= gq * vaz
	end
	local bpx, bpy, bpz = aero.bodyDragPos[1], aero.bodyDragPos[2], aero.bodyDragPos[3]
	fx += dfx
	fy += dfy
	fz += dfz
	mx += bpy * dfz - bpz * dfy
	my += bpz * dfx - bpx * dfz
	mz += bpx * dfy - bpy * dfx
	totalDrag += sqrt(dfx * dfx + dfy * dfy + dfz * dfz)

	-- Compressibility (wave) drag: past the critical Mach number drag climbs steeply up
	-- to the sound barrier, then eases off a little once supersonic. Only aircraft built
	-- for it (a low aero.waveDrag.peak) get through; everything else hits a wall.
	local mach = tas / Units.speedOfSound(altitude)
	r.mach = mach
	local wd = aero.waveDrag
	local mcrit = (wd and wd.mcrit) or 0.8
	if mach > mcrit and tas > 0.1 then
		local peak = (wd and wd.peak) or 0.06
		local cdw
		if mach < 1.05 then
			local t = (mach - mcrit) / (1.05 - mcrit)
			cdw = peak * t * t
		else
			cdw = peak * math.max(0.55, 1.05 / mach)
		end
		local dq = 0.5 * rho * tas * aero.wingArea * cdw
		local wfx, wfy, wfz = -dq * vax, -dq * vay, -dq * vaz
		fx += wfx
		fy += wfy
		fz += wfz
		totalDrag += dq * tas
	end

	-- Small extra aerodynamic rotational damping
	local ed = aero.extraDamping
	local dampScale = rho * tas
	mx -= ed.pitch * dampScale * wx
	my -= ed.yaw * dampScale * wy
	mz -= ed.roll * dampScale * wz

	-- Landing gear -------------------------------------------------------------
	local friction = cfg.gear.friction
	local gs = sqrt(env.vgx * env.vgx + env.vgz * env.vgz)
	local wheelsOnGround = 0
	local brake = if ctl.parkingBrake then 1 else clamp(ctl.brake, 0, 1)
	local gearActive = self.gearExtension > 0.98
	local touchdownNow = false
	for i, g in self.gears do
		local u = g.cfg
		local st = Damage.state(dmg, u.component)
		local active = gearActive and st ~= "detached" and st ~= "failed"
		local stiff = if st == "degraded" then 0.8 else 1
		local brakeScale = if st == "degraded" then 0.5 else 1
		local hit = env.gearHits[i]
		local px, py, pz = u.pos[1], u.pos[2], u.pos[3]
		local pvx = env.vgx + (wy * pz - wz * py)
		local pvy = env.vgy + (wz * px - wx * pz)
		local pvz = env.vgz + (wx * py - wy * px)
		local steer = 0
		if u.steerMaxDeg > 0 then
			local t = clamp(gs / 35, 0, 1)
			steer = clamp(ctl.yaw, -1, 1) * math.rad(u.steerMaxDeg + (u.steerHighSpeedDeg - u.steerMaxDeg) * t)
		end
		Gear.step(g, active, hit.hit, hit.dist, hit.nx, hit.ny, hit.nz, pvx, pvy, pvz, steer, if u.brakes then brake else 0, friction, stiff, brakeScale, dt)
		if g.onGround then
			wheelsOnGround += 1
			fx += g.fx
			fy += g.fy
			fz += g.fz
			mx += g.cpy * g.fz - g.cpz * g.fy
			my += g.cpz * g.fx - g.cpx * g.fz
			mz += g.cpx * g.fy - g.cpy * g.fx
			if not g.wasOnGround then
				local outcome = Damage.applyGearTouchdown(dmg, u.component, g.touchdownSink, g.touchdownSide, self.gearLimits)
				if self.airborneTime > 1.0 then
					touchdownNow = true
				end
				if outcome then
					r.lastGearOutcome = outcome
				end
			elseif g.bottomed and g.compressionRate > 1.5 then
				Damage.applyImpact(dmg, u.component, g.compressionRate * 3)
			end
		end
	end
	r.wheelsOnGround = wheelsOnGround
	r.onGround = wheelsOnGround > 0

	if touchdownNow then
		local sink, side = 0, 0
		for _, g in self.gears do
			if g.onGround then
				sink = math.max(sink, g.touchdownSink)
				side = math.max(side, g.touchdownSide)
			end
		end
		self.touchdownCount += 1
		self.lastTouchdown = { sink = sink, side = side, airborneTime = self.airborneTime, index = self.touchdownCount }
	end
	if wheelsOnGround > 0 then
		self.groundTime += dt
		self.airborneTime = 0
	else
		self.airborneTime += dt
		self.groundTime = 0
	end

	-- Water (ditching, or floats on a seaplane) ----------------------------------------
	-- Hull points marked "float" (5th field) are planing float bottoms: strong buoyancy,
	-- little drag along the keel (less as the floats rise onto the step), firm sideways
	-- grip, and only a hard vertical arrival hurts. Any other point in the water is a
	-- ditching.
	local inWater, onFloats = false, false
	local hull = cfg.hullPoints
	local mass = self:currentMass()
	local buoyPerMetre = mass * Units.G / (#hull * 1.3)
	local wf = cfg.water
	local nFloat = 0
	for _, hp in hull do
		if hp[5] == "float" then
			nFloat += 1
		end
	end
	local floatBuoy = if nFloat > 0 then mass * Units.G / (nFloat * ((wf and wf.restDepth) or 0.35)) else 0
	r.waterImpact = 0
	for i, hp in hull do
		local depth = env.hullDepth[i]
		local px, py, pz = hp[1], hp[2], hp[3]
		local isFloat = hp[5] == "float"
		if depth and depth > 0 and isFloat then
			onFloats = true
			local pvx = env.vgx + (wy * pz - wz * py)
			local pvy = env.vgy + (wz * px - wx * pz)
			local pvz = env.vgz + (wx * py - wy * px)
			local d = math.min(depth, 1.5)
			-- planing lift: moving floats ride higher than floating ones
			local hump = (wf and wf.humpSpeed) or 9
			local b = floatBuoy * d * (1 + 0.8 * math.min(1, (abs(env.vgz) / hump) ^ 2))
			local bx, by, bz = env.ux * b, env.uy * b, env.uz * b
			local keel = (wf and wf.keelDrag) or 0.03
			local side = (wf and wf.sideDrag) or 1.2
			local heave = (wf and wf.heaveDamping) or 0.8
			local speed = sqrt(pvx * pvx + pvy * pvy + pvz * pvz)
			-- planing: past the hump speed the floats ride on the step and drag falls away
			local plane = 1 / (1 + (abs(pvz) / hump) ^ 2)
			local q = 0.5 * 1000 * speed * math.min(d, 1)
			bx -= q * side * pvx
			by -= q * heave * pvy
			bz -= q * keel * (0.15 + plane) * pvz
			fx += bx
			fy += by
			fz += bz
			mx += py * bz - pz * by
			my += pz * bx - px * bz
			mz += px * by - py * bx
			if not self.wasInWater[i] then
				local vDown = -(pvx * env.ux + pvy * env.uy + pvz * env.uz)
				local severity = math.max(0, vDown - ((wf and wf.safeSink) or 2.5)) * 1.6
				r.waterImpact = math.max(r.waterImpact, math.max(0, vDown) * 0.6)
				if hp[4] and severity > 0 then
					Damage.applyImpact(dmg, hp[4], severity)
				end
			end
			self.wasInWater[i] = true
		elseif depth and depth > 0 then
			inWater = true
			local pvx = env.vgx + (wy * pz - wz * py)
			local pvy = env.vgy + (wz * px - wx * pz)
			local pvz = env.vgz + (wx * py - wy * px)
			local d = math.min(depth, 2.5)
			local b = buoyPerMetre * d
			local bx, by, bz = env.ux * b, env.uy * b, env.uz * b
			local speed = sqrt(pvx * pvx + pvy * pvy + pvz * pvz)
			local dragK = 0.5 * 1000 * speed * 0.9 * math.min(d, 1)
			bx -= dragK * pvx
			by -= dragK * pvy
			bz -= dragK * pvz
			fx += bx
			fy += by
			fz += bz
			mx += py * bz - pz * by
			my += pz * bx - px * bz
			mz += px * by - py * bx
			if not self.wasInWater[i] then
				-- Water entry: vertical component hurts most.
				local vDown = -(pvx * env.ux + pvy * env.uy + pvz * env.uz)
				local hv = sqrt(math.max(0, speed * speed - vDown * vDown))
				local severity = math.max(0, vDown) * 1.6 + hv * 0.18
				r.waterImpact = math.max(r.waterImpact, severity)
				if hp[4] then
					Damage.applyImpact(dmg, hp[4], severity)
				end
			end
			if hp[4] and string.find(hp[4], "Engine") then
				for ei, ecfg in cfg.engines do
					if ecfg.component == hp[4] and self.engines[ei].running then
						Engine.fail(self.engines[ei], false)
					end
				end
			end
			self.wasInWater[i] = true
		else
			self.wasInWater[i] = false
		end
	end
	r.inWater = inWater
	r.onFloats = onFloats

	-- Load factor along body up (aero + thrust + gear, i.e. what the airframe feels)
	local gLoad = fy / (mass * Units.G)
	r.gLoad = gLoad
	if not r.onGround then
		Damage.applyOverG(dmg, abs(gLoad), self.gLimit, dt)
	end

	r.lift, r.drag = totalLift, totalDrag
	r.stall = maxSigma > 0.25
	r.stallWarning = (not r.onGround) and wingAlphaMax > stallAlpha - math.rad(2.5)
	r.wingAlpha = if wingAlphaMax == -math.huge then 0 else wingAlphaMax
	r.stallAlpha = stallAlpha
	r.fuelFlow = fuelFlow

	-- Numerical safety -------------------------------------------------------------
	if isFinite(fx) and isFinite(fy) and isFinite(fz) and isFinite(mx) and isFinite(my) and isFinite(mz) then
		-- Clamp to physically justified limits: 40 g linear, generous angular.
		local maxF = mass * Units.G * 40
		local fm = sqrt(fx * fx + fy * fy + fz * fz)
		if fm > maxF then
			local s = maxF / fm
			fx, fy, fz = fx * s, fy * s, fz * s
		end
		local maxM = mass * Units.G * 40 * 30
		local mm = sqrt(mx * mx + my * my + mz * mz)
		if mm > maxM then
			local s = maxM / mm
			mx, my, mz = mx * s, my * s, mz * s
		end
		r.fx, r.fy, r.fz, r.mx, r.my, r.mz = fx, fy, fz, mx, my, mz
		r.fault = false
	else
		r.fx, r.fy, r.fz, r.mx, r.my, r.mz = 0, 0, 0, 0, 0, 0
		r.fault = true
	end
	return r
end

return FlightModel
