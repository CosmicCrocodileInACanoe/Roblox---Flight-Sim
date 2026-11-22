--!strict
-- Turbofan engine model: start/stop, N1 spool lag, thrust lapse, reverse, fuel flow.
-- Pure and deterministic; one state table per engine.

local Engine = {}

export type EngineState = {
	cfg: any,
	n1: number, -- percent
	running: boolean,
	starting: boolean,
	startProgress: number, -- seconds into the start sequence
	failed: boolean,
	reverser: number, -- 0 stowed .. 1 deployed
	thrust: number, -- N, last computed (negative when reversing)
	fuelFlow: number, -- kg/s, last computed
	fire: boolean,
}

function Engine.new(cfg: any, running: boolean): EngineState
	return {
		cfg = cfg,
		n1 = if running then cfg.idleN1 else 0,
		running = running,
		starting = false,
		startProgress = 0,
		failed = false,
		reverser = 0,
		thrust = 0,
		fuelFlow = 0,
		fire = false,
	}
end

function Engine.start(e: EngineState)
	if e.failed or e.running or e.starting then
		return
	end
	e.starting = true
	e.startProgress = 0
end

function Engine.stop(e: EngineState)
	e.running = false
	e.starting = false
end

function Engine.fail(e: EngineState, fire: boolean?)
	e.failed = true
	e.running = false
	e.starting = false
	if fire then
		e.fire = true
	end
end

-- Thrust fraction of max for a given N1 (convex: idle gives ~6%, 100% N1 gives 100%).
function Engine.thrustFraction(n1: number, idleN1: number): number
	if n1 <= 0 then
		return 0
	end
	if n1 < idleN1 then
		local t = n1 / idleN1
		return 0.06 * t * t
	end
	local t = (n1 - idleN1) / (100 - idleN1)
	return 0.06 + 0.94 * t ^ 1.6
end

-- Advance one engine.
--   throttle: 0..1 lever, reverseCmd: reverser requested (only honoured when allowed)
--   densityRatio: rho/rho0, airspeed: true airspeed m/s, hasFuel: fuel available
function Engine.update(e: EngineState, throttle: number, reverseCmd: boolean, reverseAllowed: boolean, densityRatio: number, airspeed: number, hasFuel: boolean, dt: number): number
	local cfg = e.cfg
	local idle = cfg.idleN1

	if not hasFuel and (e.running or e.starting) then
		e.running = false
		e.starting = false
	end

	-- Start sequence: N1 climbs to idle over startTime, then the engine is running.
	if e.starting then
		e.startProgress += dt
		local target = idle * math.min(1, e.startProgress / cfg.startTime)
		e.n1 = math.max(e.n1, target)
		if e.startProgress >= cfg.startTime then
			e.starting = false
			e.running = true
		end
	end

	-- Reverser deploys over ~1.5 s and only on the ground.
	local wantReverse = reverseCmd and reverseAllowed and e.running
	local revRate = dt / 1.5
	if wantReverse then
		e.reverser = math.min(1, e.reverser + revRate)
	else
		e.reverser = math.max(0, e.reverser - revRate)
	end

	local target: number
	if e.running then
		target = idle + (100 - idle) * math.clamp(throttle, 0, 1)
		if e.reverser > 0 and e.reverser < 1 then
			target = idle -- hold idle while the reverser is moving
		end
	elseif e.starting then
		target = e.n1
	else
		-- Spooling down or windmilling with airflow.
		target = math.min(12, airspeed * 0.08)
	end

	if e.n1 < target then
		-- Slower to accelerate from low N1, like a real turbofan.
		local tau = cfg.spoolUpTau * (1 + 1.2 * (1 - e.n1 / 100))
		e.n1 += (target - e.n1) * (1 - math.exp(-dt / tau))
	else
		e.n1 += (target - e.n1) * (1 - math.exp(-dt / cfg.spoolDownTau))
	end

	local frac = 0
	if e.running then
		frac = Engine.thrustFraction(e.n1, idle)
	end
	-- Thrust lapse with density and speed (high-bypass turbofan approximation).
	local lapse = densityRatio ^ 0.75 * math.max(0.45, 1 - airspeed / 600)
	local thrust = cfg.maxThrust * frac * lapse
	if e.reverser > 0 then
		thrust = thrust * (1 - e.reverser) - thrust * e.reverser * cfg.reverseFraction
	end
	e.thrust = thrust

	if e.running then
		e.fuelFlow = cfg.fuelFlowIdle + (cfg.fuelFlowMax - cfg.fuelFlowIdle) * math.max(0, frac - 0.06) / 0.94
	elseif e.starting then
		e.fuelFlow = cfg.fuelFlowIdle * 0.5
	else
		e.fuelFlow = 0
	end
	return thrust
end

return Engine
