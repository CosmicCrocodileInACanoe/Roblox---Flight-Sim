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
--   the ground, math.huge when clear)
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
	local digits = string.match(s, "^rbxassetid://(%d+)$") or string.match(s, "^(%d+)$")
	if digits and tonumber(digits) and (tonumber(digits) :: number) > 0 then
		return "rbxassetid://" .. digits
	end
	return nil
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
		for _, slot in { profile.whine, profile.rumble, "wind", "runwayRoll", "gearMotor", "flapMotor", "stallWarning", "stickShaker", "gearWarning" } do
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
	return out
end

-- Ground proximity warning: the most urgent callout for this moment, or nil.
-- Order of priority: pull up, terrain, stall, sink rate, too low gear.
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
	return out
end

-- Pitch for a looping slot from its 0..1 effect.
function AudioMix.pitch(slotCfg: any, effect: number): number
	local lo = slotCfg.pitchMin or 1
	local hi = slotCfg.pitchMax or lo
	return lo + (hi - lo) * clamp01(effect)
end

return AudioMix
