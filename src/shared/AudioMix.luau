--!strict
-- Pure audio mixing: turns a snapshot of the aircraft's state into loop levels and
-- one-shot events. No Roblox instances here, so the offline tests can run it.
--
-- A snapshot (built by the client's SoundController from the flight model) has:
--   n1 (average engine N1, percent), anyStarting, reverser (0..1), throttle (0..1),
--   ias, gs (knots), onGround, gearExt (0..1), flapPos (notch, 1 = up), speedbrake (0..1),
--   stallWarning, raFt, vsFpm, crashed, touchdownCount, touchdownVsFpm,
--   impactCount, impactDv (m/s), detachedCount, time (s),
--   stall (wing actually stalled), terrainAheadSec (seconds until the flight path meets
--   the ground, math.huge when clear), altFt, rotateKts, bank (degrees),
--   fire, overspeed, warnCount and cautionCount (master warning / caution items)
--
-- loops() returns, per looping slot, { level = 0..1, effect = 0..1 }: level scales the
-- slot's volume and effect picks the pitch between pitchMin and pitchMax.
-- events() returns a list of { slot = name, gain = 0..1 } one-shots to play this frame.

local AudioMix = {}

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

-- "1234", 1234 or "rbxassetid://1234" -> "rbxassetid://1234"; anything else -> nil.
function AudioMix.assetUrl(id: any): string?
	if type(id) == "number" then
		if id > 0 and id == math.floor(id) then
			return "rbxassetid://" .. string.format("%d", id)
		end
		return nil
	end
	if type(id) ~= "string" then
		return nil
	end
	local s = string.gsub(id, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	if string.match(s, "^rbxasset://sounds/[%w%s_%-%.]+$") then
		return s -- a sound that ships with the Roblox client
	end
	local digits = string.match(s, "^rbxassetid://(%d+)$") or string.match(s, "^(%d+)$")
	if digits and tonumber(digits) and (tonumber(digits) :: number) > 0 then
		return "rbxassetid://" .. digits
	end
	return nil
end

-- A slot's id can be one ID or a list of candidates (first one that loads wins).
function AudioMix.assetUrls(id: any): { string }
	local out = {}
	if type(id) == "table" then
		for _, v in id do
			local u = AudioMix.assetUrl(v)
			if u and not table.find(out, u) then
				table.insert(out, u)
			end
		end
	else
		local u = AudioMix.assetUrl(id)
		if u then
			table.insert(out, u)
		end
	end
	return out
end

function AudioMix.profileFor(audioCfg: any, aircraftId: string?, aircraftCfg: any?): any
	local name = (aircraftCfg and aircraftCfg.soundProfile)
		or (aircraftId and audioCfg.aircraftProfile[aircraftId])
		or audioCfg.defaultProfile
	return audioCfg.profiles[name] or audioCfg.profiles[audioCfg.defaultProfile]
end

function AudioMix.loops(snap: any, prev: any?, dt: number, profile: any, mix: any): { [string]: { level: number, effect: number } }
	local out: { [string]: { level: number, effect: number } } = {}
	local function set(slot: string, level: number, effect: number)
		out[slot] = { level = clamp01(level), effect = clamp01(effect) }
	end
	-- Silence every loop once the aircraft is destroyed; one-shots carry the crash.
	if snap.crashed then
		for _, slot in { profile.whine, profile.rumble, "wind", "runwayRoll", "gearMotor", "flapMotor", "stallWarning", "stickShaker", "gearWarning", "cockpitAmbience", "fireBell", "overspeedClacker" } do
			set(slot, 0, 0)
		end
		return out
	end

	-- Engines: the whine follows N1 (pitch and level), the rumble follows thrust, so the
	-- engines are quiet at idle and loud at full power.
	local n = clamp01(snap.n1 / 100)
	local fadeIn = clamp01(n / 0.15) -- spooling up from zero fades in
	set(profile.whine, fadeIn * (0.15 + 0.85 * n ^ 1.3), n)
	local thrust = clamp01((n - 0.2) / 0.8)
	local rumble = 0.1 * clamp01(n / 0.2) + 0.9 * thrust ^ 1.5 + 0.4 * snap.reverser * fadeIn
	set(profile.rumble, rumble, thrust)

	-- Wind grows with the square of airspeed; gear and speedbrake add buffet.
	local s = math.max(0, snap.ias) / mix.windFullKts
	local buffet = 1 + 0.3 * snap.gearExt + 0.3 * snap.speedbrake
	set("wind", math.min(1.2, s) ^ 2 * buffet, s)

	-- Runway roll while the wheels are on the ground.
	local g = if snap.onGround then clamp01(snap.gs / mix.rollFullKts) else 0
	set("runwayRoll", if snap.onGround and snap.gs > 2 then 0.2 + 0.8 * g else 0, g)

	-- Gear and flap motors run while their positions are moving.
	local gearMoving = prev ~= nil and dt > 0 and math.abs(snap.gearExt - prev.gearExt) / dt > 1e-3
	local flapMoving = prev ~= nil and dt > 0 and math.abs(snap.flapPos - prev.flapPos) / dt > 1e-3
	set("gearMotor", if gearMoving then 1 else 0, 0.5)
	set("flapMotor", if flapMoving then 1 else 0, 0.5)

	-- Warnings
	local airborne = not snap.onGround
	set("stallWarning", if airborne and (snap.stallWarning or snap.stall) then 1 else 0, 0.5)
	set("stickShaker", if airborne and snap.stall then 1 else 0, 0.5)
	local lowAndSlow = airborne
		and snap.raFt < mix.gearWarningFt
		and snap.gearExt < 0.99
		and (snap.throttle < mix.gearWarningThrottle or snap.flapPos >= mix.gearWarningFlap - 0.05)
	set("gearWarning", if lowAndSlow then 1 else 0, 0.5)
	set("cockpitAmbience", 1, 0.5)
	set("fireBell", if snap.fire then 1 else 0, 0.5)
	set("overspeedClacker", if snap.overspeed then 1 else 0, 0.5)
	return out
end

-- Ground proximity warning: the most urgent callout for this moment, or nil.
-- Order of priority: pull up, terrain, stall, sink rate, too low gear, bank angle.
function AudioMix.gpws(snap: any, mix: any): string?
	if snap.crashed or snap.onGround then
		return nil
	end
	local ra = snap.raFt
	local sink = math.max(0, -snap.vsFpm)
	local landingConfig = snap.gearExt >= 0.99 and snap.flapPos >= mix.gearWarningFlap - 0.05
	local ahead = snap.terrainAheadSec or math.huge
	local inBand = ra >= mix.gpwsMinFt
	-- Time until the ground below at the current sink rate.
	local belowSec = if sink > 1 then ra / sink * 60 else math.huge
	local limit = mix.sinkRateBaseFpm + mix.sinkRatePerFt * ra
	local excessiveSink = inBand and ra <= mix.gpwsMaxFt and sink > limit
	-- A normal approach in landing configuration flies at the runway on purpose, so the
	-- look-ahead check only counts when the aircraft is not set up to land.
	local aheadCounts = inBand and not landingConfig

	if (excessiveSink and (sink > limit * mix.pullUpSinkFactor or belowSec < mix.pullUpBelowSec))
		or (aheadCounts and ahead < mix.pullUpAheadSec)
	then
		return "calloutPullUp"
	end
	if aheadCounts and ahead < mix.terrainAheadSec then
		return "calloutTerrain"
	end
	if snap.stall then
		return "calloutStall"
	end
	if excessiveSink then
		return "calloutSinkRate"
	end
	if inBand and ra < mix.tooLowGearFt and snap.gearExt < 0.99 and snap.vsFpm < 0 then
		return "calloutTooLowGear"
	end
	if ra >= 30 and math.abs(snap.bank or 0) > mix.bankAngleDeg then
		return "calloutBankAngle"
	end
	return nil
end

-- `memo` keeps cooldowns between frames; pass the same table every call.
-- `sounds` (AudioConfig.sounds) supplies each callout's repeatEvery; optional.
function AudioMix.events(snap: any, prev: any?, mix: any, memo: any, sounds: any?): { { slot: string, gain: number } }
	local out = {}
	if not prev then
		return out
	end
	local function play(slot: string, gain: number)
		table.insert(out, { slot = slot, gain = clamp01(gain) })
	end

	if snap.anyStarting and not prev.anyStarting then
		play("engineStart", 1)
	end

	-- Gear locks when it reaches fully up or fully down.
	if (snap.gearExt >= 1 and prev.gearExt < 1) or (snap.gearExt <= 0 and prev.gearExt > 0) then
		play("gearLock", 1)
	end

	if snap.touchdownCount > prev.touchdownCount then
		local sink = math.max(0, -snap.touchdownVsFpm)
		play("touchdown", 0.3 + 0.7 * clamp01(sink / mix.firmLandingFpm))
		if snap.gs >= mix.squealMinKts then
			play("tyreSqueal", 0.5 + 0.5 * clamp01(snap.gs / 160))
		end
	end

	local lastImpact = memo.lastImpactTime or -math.huge
	if snap.impactCount > prev.impactCount and snap.time - lastImpact >= mix.impactCooldown then
		local dv = snap.impactDv
		if dv >= mix.impactHeavyDv then
			memo.lastImpactTime = snap.time
			play("impactHeavy", 0.6 + 0.4 * clamp01((dv - mix.impactHeavyDv) / mix.impactHeavyDv))
		elseif dv >= mix.impactLightDv then
			memo.lastImpactTime = snap.time
			play("impactLight", 0.4 + 0.6 * clamp01((dv - mix.impactLightDv) / (mix.impactHeavyDv - mix.impactLightDv)))
		end
	end

	if snap.detachedCount > prev.detachedCount and not snap.crashed then
		play("impactHeavy", 1)
	end
	if snap.crashed and not prev.crashed then
		play("crash", 1)
	end

	-- Master warning / caution chimes when something new goes wrong.
	if not snap.crashed then
		if (snap.warnCount or 0) > (prev.warnCount or 0) then
			play("masterWarning", 1)
		elseif (snap.cautionCount or 0) > (prev.cautionCount or 0) then
			play("masterCaution", 1)
		end
	end

	-- Voice callouts repeat while their condition lasts; a change of callout plays at once.
	local callout = AudioMix.gpws(snap, mix)
	if callout then
		local every = (sounds and sounds[callout] and sounds[callout].repeatEvery) or 2.5
		local since = snap.time - (memo.lastCalloutTime or -math.huge)
		-- A new callout waits at least 1 s so flickering conditions don't stutter.
		if (callout ~= memo.lastCallout and since >= 1) or since >= every then
			memo.lastCallout = callout
			memo.lastCalloutTime = snap.time
			play(callout, 1)
		end
	else
		memo.lastCallout = nil
	end

	-- Normal callouts give way to a warning this frame.
	if not callout then
		local airborne = not snap.onGround
		-- Takeoff roll
		if snap.onGround and prev.onGround and snap.throttle >= mix.takeoffMinThrottle then
			if prev.ias < 80 and snap.ias >= 80 then
				play("calloutEightyKnots", 1)
			elseif snap.rotateKts and prev.ias < snap.rotateKts and snap.ias >= snap.rotateKts then
				play("calloutRotate", 1)
			end
		end
		-- Radio altitude on approach: the lowest height crossed this frame.
		if airborne and snap.gearExt >= 0.99 and snap.vsFpm < 0 then
			local crossed = nil
			for _, h in mix.altitudeCallouts do
				if prev.raFt > h and snap.raFt <= h then
					crossed = h
				end
			end
			if crossed then
				play("calloutAlt" .. tostring(crossed), 1)
			end
		end
	end

	-- Cabin chime through 10,000 ft either way.
	if snap.altFt and prev.altFt and not snap.onGround then
		local c = mix.chimeAltFt
		if (prev.altFt < c and snap.altFt >= c) or (prev.altFt > c and snap.altFt <= c) then
			play("cabinChime", 1)
		end
	end
	return out
end

-- Background ATC ----------------------------------------------------------------------
-- Seconds of quiet after one exchange before the next (rand01: a 0..1 random number).
function AudioMix.atcDelay(rand01: number, mix: any): number
	return mix.atcMinGap + (mix.atcMaxGap - mix.atcMinGap) * clamp01(rand01)
end

local AIRLINES = { "Skyline", "Coastal", "Northwind", "Bluejay", "Summit", "Harbor", "Redtail", "Polar", "Meadow", "Falcon" }
local NUMBERS = { "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine" }
local FACILITIES = { "Approach", "Center", "Tower", "Departure" }

-- A short made-up exchange between a controller and another aircraft. Returns
-- { callsign, lines = { { who = "atc" | "pilot", text } x2 } }, well under 15 s of
-- speech. Some calls start with the pilot, some with the controller.
-- randInt(a, b) returns a whole number in a..b.
function AudioMix.atcExchange(randInt: (number, number) -> number): any
	local function digits(n: number): string
		local out = {}
		for i = 1, n do
			out[i] = NUMBERS[randInt(if i == 1 then 2 else 1, 10)]
		end
		return table.concat(out, " ")
	end
	local cs = AIRLINES[randInt(1, #AIRLINES)] .. " " .. digits(randInt(2, 3))
	if randInt(1, 4) == 1 then
		cs ..= " heavy"
	end
	local fac = FACILITIES[randInt(1, #FACILITIES)]
	local fl = NUMBERS[randInt(2, 4)] .. " " .. NUMBERS[randInt(1, 10)] .. " zero"
	local hdg = NUMBERS[randInt(1, 4)] .. " " .. NUMBERS[randInt(1, 10)] .. " zero"
	local alt = NUMBERS[randInt(4, 9)]
	local freq = "one two " .. NUMBERS[randInt(1, 10)] .. " point " .. NUMBERS[randInt(1, 10)]
	local rwy = NUMBERS[randInt(1, 4)] .. " " .. NUMBERS[randInt(1, 10)]
	local A, P = "atc", "pilot"
	local templates = {
		{ { A, cs .. ", climb and maintain flight level " .. fl .. "." }, { P, "Up to flight level " .. fl .. ", " .. cs .. "." } },
		{ { A, cs .. ", turn left heading " .. hdg .. "." }, { P, "Left heading " .. hdg .. ", " .. cs .. "." } },
		{ { A, cs .. ", turn right heading " .. hdg .. ", vectors for the approach." }, { P, "Right " .. hdg .. ", " .. cs .. "." } },
		{ { A, cs .. ", descend and maintain " .. alt .. " thousand." }, { P, "Down to " .. alt .. " thousand, " .. cs .. "." } },
		{ { A, cs .. ", contact " .. fac .. " " .. freq .. ". Good day." }, { P, freq .. ", " .. cs .. ", good day." } },
		{ { A, cs .. ", traffic two o'clock, five miles, opposite direction." }, { P, "Looking for the traffic, " .. cs .. "." } },
		{ { A, cs .. ", runway " .. rwy .. ", cleared to land, wind calm." }, { P, "Cleared to land " .. rwy .. ", " .. cs .. "." } },
		{ { A, cs .. ", reduce speed to two one zero knots." }, { P, "Two one zero knots, " .. cs .. "." } },
		{ { P, fac .. ", " .. cs .. ", with you at flight level " .. fl .. "." }, { A, cs .. ", " .. fac .. ", roger." } },
		{ { P, fac .. ", " .. cs .. ", request higher." }, { A, cs .. ", climb and maintain flight level " .. fl .. "." } },
		{ { P, "Tower, " .. cs .. ", holding short runway " .. rwy .. ", ready." }, { A, cs .. ", runway " .. rwy .. ", cleared for takeoff." } },
		{ { P, fac .. ", " .. cs .. ", request direct to the field." }, { A, cs .. ", proceed direct, descend at your discretion." } },
		{ { P, fac .. ", " .. cs .. ", we're getting some light chop up here." }, { A, cs .. ", roger, smoother rides reported lower." } },
	}
	local t = templates[randInt(1, #templates)]
	return {
		callsign = cs,
		lines = { { who = t[1][1], text = t[1][2] }, { who = t[2][1], text = t[2][2] } },
	}
end

-- Stable pick for a callsign, so the same flight keeps the same voice.
function AudioMix.voiceFor(name: string, choices: { string }): (string, number)
	local h = 0
	for i = 1, #name do
		h = (h * 31 + string.byte(name, i)) % 1000003
	end
	return choices[(h % #choices) + 1], (h % 7) / 6 -- voice, 0..1 for pitch
end

-- Pitch for a looping slot from its 0..1 effect.
function AudioMix.pitch(slotCfg: any, effect: number): number
	local lo = slotCfg.pitchMin or 1
	local hi = slotCfg.pitchMax or lo
	return lo + (hi - lo) * clamp01(effect)
end

return AudioMix
