--!strict
-- In-flight failures and weather hazards, triggered from the HUD's Events button (J).
--
-- Pure and deterministic given an rng, so the offline tests run exactly what the game
-- runs. This module decides WHAT breaks and computes the hazard wind fields; the
-- client's HazardController draws the tornado / lightning / birds and calls
-- Hazards.apply on the live FlightModel. Breaks go through the normal Damage model, so
-- the existing crash system (ReportDamage / ReportSection -> CrashService) tears the
-- real parts off on the server, exactly as in a crash.

local function req(name: string): any
	if script then
		return (require :: any)((script :: any).Parent[name])
	end
	return (require :: any)("./" .. name)
end

local Damage = req("Damage")
local Engine = req("Engine")
local Crash = req("Crash")

local Hazards = {}

export type Rng = () -> number -- uniform [0, 1)

export type Action = {
	op: string, -- "engineFail" | "engineFlameout" | "detach" | "section" | "hurt" | "failure"
	index: number?, -- engine index
	fire: boolean?,
	component: string?,
	section: string?,
	lost: number?,
	amount: number?, -- health removed (hurt) / damage with a section
	kind: string?, -- FlightModel failure kind
	dent: number?, -- dv (m/s) for a visual dent at the component, 0 = none
}

export type Plan = {
	id: string,
	actions: { Action },
	message: string,
}

Hazards.FAILURES = {
	{ id = "engineFire", label = "Engine fire", hint = "An engine catches fire and shuts down" },
	{ id = "engineSeparation", label = "Engine falls off", hint = "An engine tears off its pylon" },
	{ id = "wingTip", label = "Wing snaps", hint = "The outer part of a wing breaks away" },
	{ id = "tailDamage", label = "Tail damage", hint = "Part of the fin or tailplane breaks off" },
	{ id = "controlJam", label = "Controls jam", hint = "Ailerons, elevator or rudder stick where they are" },
	{ id = "hydraulics", label = "Hydraulics", hint = "Gear and flaps stop moving" },
	{ id = "fuelLeak", label = "Fuel leak", hint = "Fuel drains fast" },
	{ id = "gearCollapse", label = "Gear collapse", hint = "One landing-gear leg folds" },
}

Hazards.WEATHER = {
	{ id = "tornado", label = "Tornado", hint = "A twister touches down ahead. Fly around it or get thrown about" },
	{ id = "lightning", label = "Lightning", hint = "A strike can flame out an engine (press I to relight)" },
	{ id = "birds", label = "Bird strike", hint = "A flock hits the nose and engines" },
	{ id = "strongWind", label = "Strong winds", hint = "A 40-55 kt crosswind with gusts and a downburst" },
}

Hazards.TORNADO = {
	coreRadiusM = 70, -- Rankine core: wind peaks here
	maxWindMps = 75, -- peak swirl (~145 kt)
	updraftMps = 28, -- peak updraft in the core
	inflow = 0.35, -- radial inflow as a fraction of the swirl
	topM = 1600, -- the funnel reaches the cloud base here
	influenceRadii = 7, -- no effect beyond this many core radii
	durationS = 75,
	spawnAheadM = 1300,
	driftMps = 14,
	debrisHitsPerS = 2.2, -- inside 1.5 core radii
}

Hazards.WIND = {
	minKts = 40,
	maxKts = 55,
	gustKts = 15,
	durationS = 45,
	rampS = 5,
	downburstMps = 11, -- peak sink in the downburst halfway through
	turbulenceMps = 5,
}

local function pick<T>(list: { T }, rng: Rng): T?
	if #list == 0 then
		return nil
	end
	return list[math.clamp(math.floor(rng() * #list) + 1, 1, #list)]
end

local function attached(fm: any, name: string?): boolean
	return name ~= nil and Damage.isAttached(fm.damage, name)
end

-- Engines that are still on the airframe; `running` = only ones that are turning.
function Hazards.engines(fm: any, running: boolean?): { number }
	local out = {}
	for i, e in fm.engines do
		local comp = fm.cfg.engines[i].component
		if attached(fm, comp) and not e.failed and (not running or e.running or e.starting) then
			table.insert(out, i)
		end
	end
	return out
end

-- Attached components of one Crash.kind ("wing", "tail", "gear", "engine", "fuselage").
function Hazards.componentsOfKind(fm: any, kind: string): { string }
	local out = {}
	for _, name in fm.damage.order do
		if Crash.kind(name) == kind and attached(fm, name) then
			table.insert(out, name)
		end
	end
	return out
end

-- Break points still intact on these components: { {component, section} }.
local function freeSections(fm: any, names: { string }): { { component: string, section: any } }
	local out = {}
	local profiles = Crash.profiles(fm.cfg)
	for _, name in names do
		local prof = profiles[name]
		local c = fm.damage.components[name]
		if prof and c then
			for _, s in prof.sections do
				if not c.sectionsLost[s.id] then
					table.insert(out, { component = name, section = s })
				end
			end
		end
	end
	return out
end

local function sideWord(name: string): string
	if string.find(name, "Left") then
		return "left "
	elseif string.find(name, "Right") then
		return "right "
	end
	return ""
end

local function engineName(fm: any, i: number): string
	local comp = fm.cfg.engines[i].component
	local n = #fm.cfg.engines
	if n == 1 then
		return "the engine"
	end
	local s = sideWord(comp)
	if string.find(comp, "Outer") then
		s ..= "outer "
	elseif string.find(comp, "Inner") then
		s ..= "inner "
	end
	return s .. "engine"
end

local function capital(s: string): string
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

-- Health to remove so the component ends at `target` (never negative).
local function downTo(fm: any, name: string, target: number): number
	local c = fm.damage.components[name]
	return if c then math.max(0, c.health - target) else 0
end

-- Decide what a failure or hazard breaks on this aircraft right now.
-- Returns nil plus a reason when there is nothing left that it could break.
function Hazards.plan(id: string, fm: any, rng: Rng): (Plan?, string?)
	local actions: { Action } = {}
	local msg = ""
	if id == "engineFire" then
		local i = pick(Hazards.engines(fm), rng)
		if not i then
			return nil, "No working engine left to fail"
		end
		local comp = fm.cfg.engines[i].component
		table.insert(actions, { op = "engineFail", index = i, fire = true })
		table.insert(actions, { op = "hurt", component = comp, amount = downTo(fm, comp, 0.2) })
		msg = `FIRE: {engineName(fm, i)} is on fire and has shut down`
	elseif id == "engineSeparation" then
		local list = {}
		for i, ec in fm.cfg.engines do
			if attached(fm, ec.component) then
				table.insert(list, i)
			end
		end
		local i = pick(list, rng)
		if not i then
			return nil, "No engines left to lose"
		end
		table.insert(actions, { op = "detach", component = fm.cfg.engines[i].component })
		msg = `{capital(engineName(fm, i))} has torn off the aircraft`
	elseif id == "wingTip" then
		local free = freeSections(fm, Hazards.componentsOfKind(fm, "wing"))
		local s = pick(free, rng)
		if s then
			table.insert(actions, { op = "section", component = s.component, section = s.section.id, lost = s.section.lost, amount = 0.25, dent = 14 })
			msg = `The {sideWord(s.component)}wing has snapped. Expect a strong roll`
		else
			local w = pick(Hazards.componentsOfKind(fm, "wing"), rng)
			if not w then
				return nil, "No wing left to break"
			end
			table.insert(actions, { op = "hurt", component = w, amount = 0.4, dent = 14 })
			msg = `The {sideWord(w)}wing is badly damaged`
		end
	elseif id == "tailDamage" then
		local tails = Hazards.componentsOfKind(fm, "tail")
		local s = pick(freeSections(fm, tails), rng)
		if s then
			table.insert(actions, { op = "section", component = s.component, section = s.section.id, lost = s.section.lost, amount = 0.3, dent = 12 })
			msg = "Part of the tail has broken off. Pitch and yaw are weaker"
		else
			local t = pick(tails, rng)
			if not t then
				return nil, "No tail left to break"
			end
			table.insert(actions, { op = "hurt", component = t, amount = 0.45, dent = 12 })
			msg = "The tail is badly damaged. Pitch and yaw are weaker"
		end
	elseif id == "controlJam" then
		local free = {}
		for _, k in { "aileronJam", "elevatorJam", "rudderJam" } do
			if not fm.failures[k] then
				table.insert(free, k)
			end
		end
		local k = pick(free, rng)
		if not k then
			return nil, "Every control is already jammed"
		end
		table.insert(actions, { op = "failure", kind = k })
		local names = { aileronJam = "Ailerons", elevatorJam = "Elevator", rudderJam = "Rudder" }
		msg = `{names[k]} jammed. Steer with what still works`
	elseif id == "hydraulics" then
		if fm.failures.gearStuck and fm.failures.flapsJam then
			return nil, "Hydraulics have already failed"
		end
		table.insert(actions, { op = "failure", kind = "gearStuck" })
		table.insert(actions, { op = "failure", kind = "flapsJam" })
		msg = "Hydraulic failure: gear and flaps are stuck where they are"
	elseif id == "fuelLeak" then
		if fm.failures.fuelLeak then
			return nil, "Fuel is already leaking"
		end
		table.insert(actions, { op = "failure", kind = "fuelLeak" })
		msg = "Fuel leak! Land soon"
	elseif id == "gearCollapse" then
		local legs = {}
		for _, g in Hazards.componentsOfKind(fm, "gear") do
			if Damage.state(fm.damage, g) ~= "failed" then
				table.insert(legs, g)
			end
		end
		local g = pick(legs, rng)
		if not g then
			return nil, "No landing gear left to collapse"
		end
		table.insert(actions, { op = "hurt", component = g, amount = downTo(fm, g, 0.05) })
		local where = if string.find(g, "Nose") then "nose" elseif string.find(g, "Tail") then "tail" else sideWord(g) .. "main"
		msg = `The {where} gear leg has collapsed`
	elseif id == "lightning" then
		local struck = pick(Hazards.componentsOfKind(fm, "wing"), rng) or pick(Hazards.componentsOfKind(fm, "tail"), rng)
		if struck then
			table.insert(actions, { op = "hurt", component = struck, amount = 0.1 + 0.08 * rng(), dent = 8 })
		end
		msg = "Lightning strike!"
		local running = Hazards.engines(fm, true)
		if #running > 0 and rng() < 0.6 then
			local i = pick(running, rng) :: number
			table.insert(actions, { op = "engineFlameout", index = i })
			msg ..= ` The {engineName(fm, i)} flamed out (press I to relight)`
		end
	elseif id == "birds" then
		local i = pick(Hazards.engines(fm), rng)
		local nose = if attached(fm, "ForwardFuselage") then "ForwardFuselage" elseif attached(fm, "Fuselage") then "Fuselage" else nil
		if nose then
			table.insert(actions, { op = "hurt", component = nose, amount = 0.06, dent = 9 })
		end
		if i then
			local comp = fm.cfg.engines[i].component
			if rng() < 0.4 then
				table.insert(actions, { op = "engineFail", index = i, fire = rng() < 0.5 })
				table.insert(actions, { op = "hurt", component = comp, amount = downTo(fm, comp, 0.2) })
				msg = `Bird strike! The {engineName(fm, i)} swallowed birds and failed`
			else
				table.insert(actions, { op = "hurt", component = comp, amount = downTo(fm, comp, 0.55) })
				msg = `Bird strike! The {engineName(fm, i)} is damaged and down on power`
			end
		else
			msg = "Bird strike!"
		end
		if #actions == 0 then
			return nil, "Nothing left for the birds to hit"
		end
	else
		return nil, "Unknown event"
	end
	return { id = id, actions = actions, message = msg }, nil
end

-- Apply a plan to a FlightModel. Damage events for the server are queued in
-- fm.damage.events as usual. Returns the components that should get a visual dent:
-- { {component, dv} }.
function Hazards.apply(fm: any, plan: Plan): { { component: string, dv: number } }
	local dents = {}
	for _, a in plan.actions do
		if a.op == "engineFail" then
			local e = fm.engines[a.index :: number]
			if e then
				Engine.fail(e, a.fire == true)
			end
		elseif a.op == "engineFlameout" then
			local e = fm.engines[a.index :: number]
			if e then
				Engine.stop(e)
			end
		elseif a.op == "detach" then
			Damage.forceDetach(fm.damage, a.component :: string)
		elseif a.op == "section" then
			Damage.breakSection(fm.damage, a.component :: string, a.section :: string, a.lost or 0.3, a.amount)
		elseif a.op == "hurt" then
			Damage.hurt(fm.damage, a.component :: string, a.amount or 0, false)
		elseif a.op == "failure" then
			fm:setFailure(a.kind :: string, true)
		end
		if a.dent and a.dent > 0 and a.component then
			table.insert(dents, { component = a.component, dv = a.dent })
		end
	end
	return dents
end

-- A random failure from the list that can still happen on this aircraft.
function Hazards.randomFailure(fm: any, rng: Rng): (Plan?, string?)
	local ids = {}
	for _, f in Hazards.FAILURES do
		table.insert(ids, f.id)
	end
	-- shuffle, then take the first that applies
	for i = #ids, 2, -1 do
		local j = math.clamp(math.floor(rng() * i) + 1, 1, i)
		ids[i], ids[j] = ids[j], ids[i]
	end
	for _, id in ids do
		local p = Hazards.plan(id, fm, rng)
		if p then
			return p, nil
		end
	end
	return nil, "Nothing left to fail"
end

-- Tornado wind (m/s, world axes) at offset (dx, dz) metres from the funnel axis and
-- height `h` metres above the ground it stands on. Counter-clockwise from above
-- (northern hemisphere), Rankine swirl with radial inflow and a core updraft.
function Hazards.tornadoWind(dx: number, h: number, dz: number, strength: number?): (number, number, number)
	local T = Hazards.TORNADO
	local k = strength or 1
	local r = math.sqrt(dx * dx + dz * dz)
	local rc = T.coreRadiusM
	local maxR = rc * T.influenceRadii
	if r >= maxR or h > T.topM * 1.3 or k <= 0 then
		return 0, 0, 0
	end
	local vt = if r < rc then T.maxWindMps * r / rc else T.maxWindMps * rc / r
	-- fade smoothly to zero at the edge of the influence radius and above the cloud base
	local edge = 1 - (r / maxR) ^ 2
	local top = math.clamp(1 - (h - T.topM) / (T.topM * 0.3), 0, 1)
	vt *= edge * top * k
	if r < 1e-3 then
		return 0, T.updraftMps * top * k, 0
	end
	local ux, uz = dx / r, dz / r
	-- tangential direction for counter-clockwise rotation seen from above (+Y up):
	-- (x, z) -> (z, -x) turns left in Roblox's right-handed X/Z plane
	local tx, tz = uz, -ux
	local vr = -T.inflow * vt
	local up = T.updraftMps * math.exp(-(r / (rc * 1.6)) ^ 2) * top * k
	return tx * vt + ux * vr, up, tz * vt + uz * vr
end

-- Debris hits per second at `r` metres from the funnel axis (0 outside the debris cloud).
function Hazards.tornadoHitRate(r: number): number
	local rc = Hazards.TORNADO.coreRadiusM
	if r > rc * 1.5 then
		return 0
	end
	return Hazards.TORNADO.debrisHitsPerS * (1 - r / (rc * 1.5)) + 0.3
end

-- 0..1 envelope for an event of `duration` seconds with `ramp`-second ramps.
function Hazards.envelope(t: number, duration: number, ramp: number): number
	if t <= 0 or t >= duration then
		return 0
	end
	local up = math.clamp(t / ramp, 0, 1)
	local down = math.clamp((duration - t) / ramp, 0, 1)
	local e = math.min(up, down)
	return e * e * (3 - 2 * e) -- smoothstep
end

-- Strong-wind episode: wind (m/s, world) at time t into the event.
--   dirX, dirZ: unit vector the wind blows TOWARD; speedKts: mean speed;
--   n1, n2, n3: noise samples in [-1, 1] for gusts and turbulence.
function Hazards.strongWind(t: number, dirX: number, dirZ: number, speedKts: number, n1: number, n2: number, n3: number): (number, number, number)
	local W = Hazards.WIND
	local env = Hazards.envelope(t, W.durationS, W.rampS)
	if env <= 0 then
		return 0, 0, 0
	end
	local kt = 0.514444
	local mean = speedKts * kt
	local gust = W.gustKts * kt * math.max(0, n1)
	local s = (mean + gust) * env
	-- downburst: a sink pulse centred halfway through
	local mid = W.durationS * 0.5
	local burst = math.exp(-((t - mid) / 4) ^ 2)
	local wy = -W.downburstMps * burst * env + n3 * W.turbulenceMps * 0.6 * env
	-- turbulence across the mean flow
	local px, pz = -dirZ, dirX
	local side = n2 * W.turbulenceMps * env
	return dirX * s + px * side, wy, dirZ * s + pz * side
end

return Hazards
