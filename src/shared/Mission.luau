--!strict
-- Airline-flight objective tracker. Pure state machine driven by telemetry that the
-- SERVER measures from the replicated aircraft (clients only display the result).

local Mission = {}

export type Telemetry = {
	x: number, z: number, -- studs
	altitudeM: number, -- MSL
	aglM: number,
	groundSpeed: number, -- m/s
	verticalSpeed: number, -- m/s
	onGround: boolean,
	headingDeg: number,
	enginesRunning: boolean,
	parkingBrake: boolean,
	crashed: boolean,
	time: number, -- server clock
}

Mission.PHASES = {
	{ id = "preflight", text = "Start engines (I), then release the parking brake (P)" },
	{ id = "taxi", text = "Taxi to the runway (rudder keys steer the nose wheel)" },
	{ id = "takeoff", text = "Line up, full throttle (Shift), rotate at 140 kt (S)" },
	{ id = "climb", text = "Gear up (G), flaps up (V) above 190 kt, climb to 4,000 ft" },
	{ id = "cruise", text = "Fly toward the destination (follow the nav arrow)" },
	{ id = "approach", text = "Descend to 2,500 ft, flaps down (F), gear down (G), line up" },
	{ id = "landing", text = "Follow the glide path, flare at 30 ft, touch down gently" },
	{ id = "rollout", text = "Brake (B) and reverse (Z), slow to taxi speed" },
	{ id = "taxiToGate", text = "Taxi to a gate and set the parking brake (P)" },
	{ id = "complete", text = "Flight complete!" },
	{ id = "failed", text = "Flight failed: press R to reset" },
}

local PHASE_INDEX = {}
for i, p in Mission.PHASES do
	PHASE_INDEX[p.id] = i
end
Mission.PHASE_INDEX = PHASE_INDEX

function Mission.phaseText(id: string): string
	local i = PHASE_INDEX[id]
	return if i then Mission.PHASES[i].text else ""
end

-- Airports module is injected so this stays pure and easily testable.
function Mission.new(origin: string, destination: string, airports: any, startPhase: string?)
	return {
		origin = origin,
		destination = destination,
		airports = airports,
		phase = startPhase or "preflight",
		startedAt = nil :: number?,
		airborneAt = nil :: number?,
		touchdown = nil :: any,
		bounces = 0,
		lastAirborne = false,
		airborneSince = nil :: number?,
		completedAt = nil :: number?,
		landedAt = nil :: string?,
		maxAltitudeM = 0,
		log = {} :: { string },
	}
end

local function setPhase(m: any, id: string, t: number)
	if m.phase ~= id then
		m.phase = id
		table.insert(m.log, `{math.floor(t)}:{id}`)
	end
end

-- Returns an event string when something notable happens ("touchdown", "complete", ...)
function Mission.update(m: any, tel: Telemetry): string?
	local A = m.airports
	local destL = A.layout(m.destination)
	local event: string? = nil
	if m.phase == "complete" or m.phase == "failed" then
		return nil
	end
	if tel.crashed then
		setPhase(m, "failed", tel.time)
		return "failed"
	end
	m.startedAt = m.startedAt or tel.time
	m.maxAltitudeM = math.max(m.maxAltitudeM, tel.altitudeM)

	-- Bounce tracking: airborne again for >0.4 s after the first touchdown.
	if m.touchdown and not tel.onGround then
		m.airborneSince = m.airborneSince or tel.time
		if tel.time - (m.airborneSince :: number) > 0.4 and not m.lastAirborne then
			m.bounces += 1
			m.lastAirborne = true
		end
	elseif tel.onGround then
		m.airborneSince = nil
		m.lastAirborne = false
	end

	local p = m.phase
	if p == "preflight" then
		if tel.enginesRunning and not tel.parkingBrake then
			setPhase(m, "taxi", tel.time)
		end
	elseif p == "taxi" then
		local originL = A.layout(m.origin)
		if A.isOnRunway(originL, tel.x, tel.z) and tel.groundSpeed > 25 then
			setPhase(m, "takeoff", tel.time)
		elseif not tel.onGround and tel.aglM > 15 then
			-- took off from somewhere other than the runway (a taxiway, the water)
			m.airborneAt = tel.time
			setPhase(m, "climb", tel.time)
			event = "takeoff"
		end
	elseif p == "takeoff" then
		if not tel.onGround and tel.aglM > 15 then
			m.airborneAt = tel.time
			setPhase(m, "climb", tel.time)
			event = "takeoff"
		end
	elseif p == "climb" then
		if tel.altitudeM - destL.y * 0.28 > 900 or tel.altitudeM > 1150 then
			setPhase(m, "cruise", tel.time)
		end
		local d = math.sqrt((tel.x - destL.cx) ^ 2 + (tel.z - destL.cz) ^ 2) * 0.28
		if d < 16000 then
			setPhase(m, "approach", tel.time)
		end
	elseif p == "cruise" then
		local d = math.sqrt((tel.x - destL.cx) ^ 2 + (tel.z - destL.cz) ^ 2) * 0.28
		if d < 16000 then
			setPhase(m, "approach", tel.time)
		end
	elseif p == "approach" then
		local d = math.sqrt((tel.x - destL.cx) ^ 2 + (tel.z - destL.cz) ^ 2) * 0.28
		if d < 6500 and tel.aglM < 700 then
			setPhase(m, "landing", tel.time)
		end
	end

	-- Touchdown detection works from approach/landing at either airport (diversions allowed).
	if (m.phase == "approach" or m.phase == "landing" or m.phase == "cruise" or m.phase == "climb") and tel.onGround and m.airborneAt ~= nil then
		local nearId = A.nearest(tel.x, tel.z)
		local l = A.layout(nearId)
		if A.isOnRunway(l, tel.x, tel.z, 40) or A.isInsideAirport(l, tel.x, tel.z) then
			local info = A.landingInfo(l, tel.x, tel.z, tel.headingDeg)
			m.touchdown = {
				airport = nearId,
				time = tel.time,
				distanceFromThresholdM = info.distanceFromThresholdM,
				centerlineOffsetM = info.centerlineOffsetM,
				ident = info.ident,
				onRunway = A.isOnRunway(l, tel.x, tel.z, 10),
			}
			m.landedAt = nearId
			setPhase(m, "rollout", tel.time)
			event = "touchdown"
		else
			m.touchdown = { airport = nil, time = tel.time, offAirport = true }
			setPhase(m, "failed", tel.time)
			return "offAirport"
		end
	elseif m.phase == "rollout" then
		if tel.groundSpeed < 15 then
			setPhase(m, "taxiToGate", tel.time)
		end
	elseif m.phase == "taxiToGate" then
		local l = A.layout(m.landedAt or m.destination)
		local _, gd = A.nearestGate(l, tel.x, tel.z)
		if gd * 0.28 < 45 and tel.groundSpeed < 1 and tel.parkingBrake then
			m.completedAt = tel.time
			setPhase(m, "complete", tel.time)
			event = "complete"
		end
	end
	return event
end

return Mission
