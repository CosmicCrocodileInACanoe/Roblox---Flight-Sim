--!strict
-- Autopilot: flies the aircraft by writing its controls (the same FlightModel controls
-- the pilot's input ends up as), so it works for every aircraft without special cases.
-- Pure and deterministic (no Roblox); the client and the offline tests share it.
--
-- Two jobs:
--   Autoland ("land"): line up with a runway, fly a 3 degree glide path at the approach
--     speed with the gear and flaps out, flare, touch down, brake and reverse to a stop.
--   Water refill ("scoop", water bombers): fly to a stretch of open sea, land on the
--     hull, skim at scooping speed until the tank is full, take off and climb away.
--
-- World frame for everything here: metres, x east, z south (north is -z), y up.
-- Each step takes a snapshot `st`:
--   x, y, z      CoM position (m);  vx, vy, vz  ground velocity (m/s)
--   heading      nose heading (deg, 0 = north)
-- plus the FlightModel `env` (body velocities, attitude, agl) and the model itself.
--
-- A target "strip" (a runway end, or the scoop line on the sea):
--   x, z         threshold / touchdown start (m);  heading (deg, direction of landing)
--   surfaceY     height of the surface (m);  lengthM  usable length
--   water        true for the sea (land on the hull, gear up)

local function req(name: string): any
	if script then
		return (require :: any)((script :: any).Parent[name])
	end
	return (require :: any)("./" .. name)
end

local Units = req("Units")

local Autopilot = {}

local clamp, abs, rad, deg = math.clamp, math.abs, math.rad, math.deg
local KT = Units.KTS_PER_MPS

local GLIDE = rad(3)
local GATE_M = 9000 -- start of the final approach, metres before the threshold
local FLARE_M = 14 -- flare height (wheels or hull above the surface)

-- CoM height above the surface when sitting on the wheels / afloat on the hull.
function Autopilot.restHeight(cfg: any, water: boolean?): number
	if water then
		local lowest = math.huge
		for _, hp in cfg.hullPoints do
			if hp[5] == "float" then
				lowest = math.min(lowest, hp[2])
			end
		end
		return -lowest - 0.3
	end
	-- the lowest wheels touch first
	local h = 0
	for _, u in cfg.gear.units do
		h = math.max(h, -(u.pos[2] - u.strutLength - u.wheelRadius) - 0.02)
	end
	return h
end

local function wrap180(a: number): number
	return ((a + 540) % 360) - 180
end

local function bearingTo(x: number, z: number, tx: number, tz: number): number
	return Units.headingFromXZ(tx - x, tz - z)
end

-- Along/cross distances of (x, z) relative to a strip: `before` > 0 short of the
-- threshold, `cross` > 0 right of the centreline (looking in the landing direction).
function Autopilot.stripCoords(strip: any, x: number, z: number): (number, number)
	local ux, uz = Units.xzFromHeading(strip.heading)
	local rx, rz = Units.xzFromHeading(strip.heading + 90)
	local dx, dz = x - strip.x, z - strip.z
	return -(dx * ux + dz * uz), dx * rx + dz * rz
end

export type State = {
	mode: string, -- "land" | "scoop"
	phase: string,
	strip: any,
	cfg: any,
	trim: number,
	thr: number,
	bias: number,
	appPitch: number,
	flareP: number?,
	flareTime: number,
	done: boolean,
	message: string,
	climbTo: number,
	holdHeading: number?,
	side: number,
}

local function new(cfg: any, mode: string, strip: any): State
	return {
		mode = mode, phase = "intercept", strip = strip, cfg = cfg,
		trim = 0.3, thr = 0.5, bias = 0, appPitch = 0, flareP = nil, flareTime = 0,
		done = false, message = "", climbTo = 0, holdHeading = nil, side = 0,
	}
end

function Autopilot.newLand(cfg: any, strip: any, trim: number?): State
	local s = new(cfg, "land", strip)
	s.trim = trim or s.trim
	return s
end

function Autopilot.newScoop(cfg: any, strip: any, trim: number?): State
	local s = new(cfg, "scoop", strip)
	s.trim = trim or s.trim
	strip.water = true
	return s
end

-- Best flap notch for a speed: the highest notch whose limit clears the speed (up to max).
local function flapsFor(cfg: any, kts: number, maxNotch: number): number
	local lim = cfg.speeds.flapLimits
	local best = 1
	for n = 2, math.min(maxNotch, #cfg.aero.flaps.labels) do
		if (lim[n] or 999) > kts + 6 then
			best = n
		end
	end
	return best
end

-- Inner loops ------------------------------------------------------------------------
-- Bank to hold a ground track; pitch to hold a vertical speed; throttle for an airspeed.
local function lateral(ap: State, ctl: any, env: any, st: any, trackT: number, maxBank: number, forceDir: number?)
	local gs = math.sqrt(st.vx * st.vx + st.vz * st.vz)
	local track = if gs > 5 then Units.headingFromXZ(st.vx, st.vz) else st.heading
	local err = wrap180(trackT - track)
	if forceDir and forceDir ~= 0 and abs(err) > 90 then
		err = forceDir * abs(err)
	end
	local bankT = clamp(err * 1.2, -maxBank, maxBank)
	local bank = deg(math.atan2(-env.ux, env.uy))
	-- roll right is +1; roll rate to the right shows as -wz
	ctl.roll = clamp((bankT - bank) * 0.04 + env.wz * 1.2, -1, 1)
	-- coordinated: rudder against sideslip
	local tas = math.sqrt(env.vax * env.vax + env.vay * env.vay + env.vaz * env.vaz)
	local beta = if tas > 1 then math.asin(clamp(env.vax / tas, -1, 1)) else 0
	ctl.yaw = clamp(beta * 4, -1, 1)
end

local function pitchFor(ap: State, ctl: any, env: any, pitchT: number, dt: number)
	local pitch = deg(math.asin(clamp(-env.uz, -1, 1)))
	local cmd = clamp((pitchT - pitch) * 0.1 - env.wx * 2.0, -1, 1)
	ap.trim = clamp(ap.trim + cmd * 0.4 * dt, -1, 1)
	ctl.trim = ap.trim
	ctl.pitch = cmd
	return pitch
end

local function verticalSpeed(ap: State, ctl: any, env: any, st: any, vsT: number, dt: number)
	-- PI: the bias learns the pitch this aircraft needs for the requested path
	ap.bias = clamp(ap.bias + (vsT - st.vy) * 0.25 * dt, -8, 10)
	local pitchT = clamp(ap.bias + (vsT - st.vy) * 0.8, -8, 12)
	ap.appPitch = pitchFor(ap, ctl, env, pitchT, dt)
end

local function speed(ap: State, ctl: any, kts: number, ktsT: number, dt: number)
	ap.thr = clamp(ap.thr + (ktsT - kts) * 0.2 * dt, 0, 1)
	ctl.throttle = clamp(ap.thr + (ktsT - kts) * 0.04, 0, 1)
end

-- One step. Writes `ctl` (a FlightModel controls table) in place.
function Autopilot.step(ap: State, ctl: any, st: any, env: any, model: any, dt: number)
	local cfg = ap.cfg
	local strip = ap.strip
	local r = model.result
	local sp = cfg.speeds
	local kts = r.ias * KT
	local gs = math.sqrt(st.vx * st.vx + st.vz * st.vz)
	local water = strip.water == true
	local rest = Autopilot.restHeight(cfg, water)
	local before, cross = Autopilot.stripCoords(strip, st.x, st.z)
	local h = st.y - strip.surfaceY - rest -- wheels / hull above the surface
	local nFlaps = #cfg.aero.flaps.labels
	local landFlaps = if water then math.min(3, nFlaps) else nFlaps
	local vapp = sp.vref + (if water then 8 else 5)
	ctl.reverse = false
	ctl.brake = 0
	ctl.speedbrake = 0
	ctl.parkingBrake = false
	ctl.waterDrop = false

	-- ground / water contact changes the phase whatever we planned
	if ap.phase == "flare" or ap.phase == "final" then
		if water and r.onFloats then
			ap.phase = "skim"
		elseif not water and r.onGround then
			ap.phase = "rollout"
		end
	end

	if ap.phase == "intercept" or ap.phase == "turnin" or ap.phase == "final" then
		-- Lateral: direct to the gate until established, then track the centreline with
		-- an intercept angle that shrinks as we get closer.
		local established = before > 2500 and abs(cross) < math.max(400, before * 0.25)
			and abs(wrap180(st.heading - strip.heading)) < 70
		if ap.phase == "intercept" and established then
			ap.phase = "final"
		end
		local trackT
		local forceDir = 0
		local ux, uz = Units.xzFromHeading(strip.heading)
		if ap.phase == "intercept" then
			local gx, gz = strip.x - ux * GATE_M, strip.z - uz * GATE_M
			if before > GATE_M + 1000 then
				-- out beyond the gate: straight to it
				trackT = bearingTo(st.x, st.z, gx, gz)
				if math.sqrt((gx - st.x) ^ 2 + (gz - st.z) ^ 2) < 1500 then
					ap.phase = "turnin"
				end
			else
				-- inside the gate (or past the runway): fly out to a point beside the
				-- centreline, one turn's width to our side, then turn back in toward it
				local turnR = (gs * gs) / (9.81 * math.tan(rad(25)))
				ap.side = if ap.side ~= 0 then ap.side elseif cross >= 0 then 1 else -1
				local rx, rz = Units.xzFromHeading(strip.heading + 90)
				local outM = math.max(GATE_M, before + 1500) + turnR
				local wx = strip.x - ux * outM + rx * ap.side * 2 * turnR
				local wz = strip.z - uz * outM + rz * ap.side * 2 * turnR
				trackT = bearingTo(st.x, st.z, wx, wz)
				if math.sqrt((wx - st.x) ^ 2 + (wz - st.z) ^ 2) < 1200 then
					ap.phase = "turnin"
				end
			end
		end
		if ap.phase == "turnin" then
			-- turn toward the centreline (the long way round is never wanted here)
			trackT = strip.heading
			forceDir = if cross >= 0 then 1 else -1
			if abs(wrap180(st.heading - strip.heading)) < 60 then
				ap.phase = "final"
			end
		end
		if ap.phase == "final" then
			local intercept = deg(math.atan2(cross, math.max(before * 0.3, 900)))
			trackT = strip.heading - clamp(intercept, -40, 40)
		end
		lateral(ap, ctl, env, st, trackT :: number, if ap.phase == "final" and before < 3000 then 12 else 25, forceDir)

		-- Vertical: on the glide path in final; hold (or climb to) the gate height before.
		local gateAlt = strip.surfaceY + rest + GATE_M * math.tan(GLIDE)
		local targetAlt
		if ap.phase == "final" then
			targetAlt = strip.surfaceY + rest + math.max(before, 0) * math.tan(GLIDE)
			-- never climb back up to a glide path we are below by a lot; just level off
			targetAlt = math.min(targetAlt, math.max(st.y, strip.surfaceY + rest + 60))
		else
			targetAlt = math.max(gateAlt, math.min(st.y, gateAlt + 600))
		end
		local vsT = if ap.phase == "final" then -gs * math.tan(GLIDE) + (targetAlt - st.y) * 0.12 else (targetAlt - st.y) * 0.06
		verticalSpeed(ap, ctl, env, st, clamp(vsT, -9, 6), dt)

		-- Speed and configuration
		local ktsT
		if ap.phase == "final" and before < 7000 then
			ktsT = vapp
		elseif ap.phase == "final" then
			ktsT = math.min(sp.cruise, vapp + 40)
		else
			ktsT = math.min(sp.cruise * 0.85, sp.vmo - 30, vapp + 60)
		end
		speed(ap, ctl, kts, ktsT, dt)
		if ap.phase == "final" and before < 8000 then
			ctl.flaps = flapsFor(cfg, kts, landFlaps)
			ctl.gearDown = not water and kts < (sp.gearLimit or 999) + 5
			-- too fast to put the flaps out: speedbrake
			if kts > ktsT + 15 then
				ctl.speedbrake = 1
			end
		else
			ctl.flaps = flapsFor(cfg, kts, math.min(2, nFlaps))
			ctl.gearDown = false
		end

		-- Not lined up close in: go around
		if ap.phase == "final" and before < 900 and (abs(cross) > 60 or h > 120) then
			ap.phase = "goaround"
			ap.climbTo = strip.surfaceY + rest + 450
		elseif ap.phase == "final" and h < FLARE_M and before < 1500 then
			ap.phase = "flare"
			ap.flareP = ap.appPitch + 1
			ap.flareTime = 0
		end
		ap.message = if ap.phase == "intercept" then "lining up" else string.format("final %.1f km", before / 1000)
	elseif ap.phase == "flare" then
		-- ease the sink rate off as the wheels get close, power coming back to idle
		ap.flareTime += dt
		-- floating along in ground effect: let it settle on
		local vsT = clamp(-0.5 - h * 0.12, -2.5, -0.5) - clamp((ap.flareTime - 6) * 0.15, 0, 1)
		local base = ap.flareP or ap.appPitch
		local pitchT = clamp(base + (vsT - st.vy) * 1.5, ap.appPitch - 1, ap.appPitch + 6)
		ap.flareP = base + clamp((vsT - st.vy) * 0.4, -1, 1) * dt
		pitchFor(ap, ctl, env, pitchT, dt)
		ctl.throttle = if ap.flareTime > 4 then 0 else clamp(ap.thr * clamp((h - 3) / (FLARE_M - 3), 0, 1), 0, 1)
		lateral(ap, ctl, env, st, strip.heading - clamp(deg(math.atan2(cross, 400)), -10, 10), 5)
		ctl.gearDown = not water
		ctl.flaps = landFlaps
		ap.message = "flare"
	elseif ap.phase == "rollout" then
		ctl.throttle = 0
		ctl.reverse = kts > 60
		ctl.brake = 1
		ctl.speedbrake = 1
		ctl.trim = 0
		ctl.roll = 0
		ctl.pitch = clamp(-0.2 - env.wx, -1, 0.2)
		ctl.gearDown = true
		local hdgErr = wrap180(st.heading - strip.heading)
		ctl.yaw = clamp(-hdgErr * 0.3 - cross * 0.05, -1, 1)
		ap.message = "rollout"
		if gs < 1 then
			ctl.parkingBrake = true
			ctl.reverse = false
			ap.phase = "stopped"
			ap.done = true
			ap.message = "stopped"
		end
	elseif ap.phase == "stopped" then
		ctl.throttle = 0
		ctl.brake = 1
		ctl.parkingBrake = true
		ap.done = true
	elseif ap.phase == "skim" then
		-- On the hull: nose a little up, wings level, steady scooping speed.
		local tank = cfg.waterTank
		local full = (not tank) or model.water >= tank.capacity - 1
		ctl.gearDown = false
		ctl.flaps = landFlaps
		lateral(ap, ctl, env, st, strip.heading, 2)
		pitchFor(ap, ctl, env, 1.5, dt)
		speed(ap, ctl, kts, math.max(tank and tank.scoopMinKt + 15 or 0, vapp - 10), dt)
		ap.message = "scooping"
		if full then
			ap.phase = "takeoff"
			ap.climbTo = strip.surfaceY + rest + 250
			ap.holdHeading = strip.heading
		elseif gs < 10 then
			-- slowed right down (a short sea): power up and keep going
			ctl.throttle = 1
		end
	elseif ap.phase == "takeoff" then
		ctl.throttle = 1
		ap.thr = 1
		ctl.gearDown = false
		ctl.flaps = math.min(3, nFlaps)
		lateral(ap, ctl, env, st, ap.holdHeading or strip.heading, if r.onFloats or r.onGround then 0 else 10)
		local onSurface = r.onFloats or r.onGround
		local pitchT = if kts > sp.rotate + 3 then 8 elseif onSurface then 3 else 6
		pitchFor(ap, ctl, env, pitchT, dt)
		ap.bias = pitchT
		ap.message = "taking off"
		if not onSurface and h > 30 then
			ap.phase = "climb"
		end
	elseif ap.phase == "goaround" or ap.phase == "climb" then
		ctl.gearDown = false
		ctl.flaps = flapsFor(cfg, kts, if kts > sp.v2 + 25 then 1 else 2)
		local hdg = ap.holdHeading or strip.heading
		lateral(ap, ctl, env, st, hdg, 20)
		local vsT = clamp((ap.climbTo - st.y) * 0.08, -3, 7)
		verticalSpeed(ap, ctl, env, st, vsT, dt)
		speed(ap, ctl, kts, math.max(sp.v2 + 25, sp.vref * 1.4), dt)
		if (ap.climbTo - st.y) > 30 then
			ctl.throttle = math.max(ctl.throttle, 0.9)
		end
		ap.message = if ap.phase == "climb" then "climbing out" else "go-around"
		if st.y > ap.climbTo - 25 then
			if ap.phase == "goaround" then
				ap.phase = "intercept"
				ap.side = 0
			else
				ap.phase = "done"
				ap.done = true
				ap.message = "done"
			end
		end
	else -- "done": wings level, hold height
		lateral(ap, ctl, env, st, ap.holdHeading or strip.heading, 15)
		verticalSpeed(ap, ctl, env, st, clamp((ap.climbTo - st.y) * 0.05, -3, 3), dt)
		speed(ap, ctl, kts, math.max(sp.v2 + 25, sp.vref * 1.4), dt)
		ap.done = true
	end
	return ctl
end

-- Strip choice ------------------------------------------------------------------------
-- runways: list of { x, z, heading, surfaceY, lengthM, id } (metres).
-- The end to land on: close, and needing the least turning to join its approach.
function Autopilot.pickRunway(runways: { any }, x: number, z: number, heading: number): any?
	local best, bestScore = nil, math.huge
	for _, rw in runways do
		local ux, uz = Units.xzFromHeading(rw.heading)
		local gx, gz = rw.x - ux * GATE_M, rw.z - uz * GATE_M
		local d = math.sqrt((gx - x) ^ 2 + (gz - z) ^ 2)
		local turn = abs(wrap180(bearingTo(x, z, gx, gz) - heading)) + abs(wrap180(rw.heading - bearingTo(x, z, gx, gz))) * 0.5
		local score = d + turn * 40
		if score < bestScore then
			best, bestScore = rw, score
		end
	end
	return best
end

-- A straight stretch of open sea for a scoop run, near (x, z) (metres). isSea(x, z) is
-- true where the water is deep enough. Returns a strip, or nil if no sea is near.
function Autopilot.findScoopStrip(isSea: (number, number) -> boolean, x: number, z: number, heading: number, maxRangeM: number?): any?
	local runM = 3500 -- landing, scooping and the take-off run
	local range = maxRangeM or 60000
	local best, bestScore = nil, math.huge
	local r = 1500
	while r <= range do
		for k = 0, 23 do
			local brg = k * 15
			local bx, bz = Units.xzFromHeading(brg)
			local px, pz = x + bx * r, z + bz * r
			if isSea(px, pz) then
				for hk = 0, 7 do
					local hdg = (heading + hk * 45) % 360
					local ux, uz = Units.xzFromHeading(hdg)
					local ok = true
					local s = 0
					while s <= runM do
						if not isSea(px + ux * s, pz + uz * s) then
							ok = false
							break
						end
						s += 250
					end
					if ok then
						-- prefer close, and runs that don't need a big turn to join
						local score = r + abs(wrap180(hdg - brg)) * 15
						if score < bestScore then
							bestScore = score
							best = { x = px, z = pz, heading = hdg, surfaceY = 0, lengthM = runM, water = true }
						end
					end
				end
			end
		end
		if best then
			return best
		end
		r += if r < 8000 then 1500 else 4000
	end
	return best
end

return Autopilot
