--!nonstrict
local AudioConfig = require("../src/shared/AudioConfig")
local AudioMix = require("../src/shared/AudioMix")

local mix = AudioConfig.mix
local jet = AudioMix.profileFor(AudioConfig, "meridian200", nil)

local function snap(o)
	local s = {
		n1 = 0, anyStarting = false, reverser = 0, throttle = 0, ias = 0, gs = 0, onGround = true,
		gearExt = 1, flapPos = 1, speedbrake = 0, stallWarning = false, raFt = 0, vsFpm = 0,
		crashed = false, touchdownCount = 0, touchdownVsFpm = 0, impactCount = 0, impactDv = 0,
		detachedCount = 0, time = 0,
	}
	for k, v in o or {} do
		s[k] = v
	end
	return s
end

local function slots(events)
	local set = {}
	for _, e in events do
		set[e.slot] = e.gain
	end
	return set
end

return { name = "Audio", run = function(T)
	T.test("every sound slot has a valid shape", function()
		for slot, sc in AudioConfig.sounds do
			T.check(type(sc.id) == "string" or type(sc.id) == "number" or type(sc.id) == "table", slot .. " id type")
			if type(sc.id) == "table" then
				T.check(#AudioMix.assetUrls(sc.id) == #sc.id, slot .. ": every candidate id is valid")
			end
			T.check(type(sc.volume) == "number" and sc.volume >= 0, slot .. " volume")
			T.check(sc.group == "exterior" or sc.group == "cockpit", slot .. " group")
			if sc.looped then
				T.check(type(sc.pitchMin) == "number" and type(sc.pitchMax) == "number", slot .. " pitch range")
			end
		end
		for name, p in AudioConfig.profiles do
			T.check(AudioConfig.sounds[p.whine] and AudioConfig.sounds[p.rumble], name .. " profile slots exist")
		end
	end)
	T.test("asset ids: empty and junk are rejected, numbers are accepted", function()
		T.check(AudioMix.assetUrl("") == nil, "empty")
		T.check(AudioMix.assetUrl("   ") == nil, "blank")
		T.check(AudioMix.assetUrl("abc") == nil, "junk")
		T.check(AudioMix.assetUrl(0) == nil, "zero")
		T.check(AudioMix.assetUrl(nil) == nil, "nil")
		T.check(AudioMix.assetUrl("123") == "rbxassetid://123", "digits")
		T.check(AudioMix.assetUrl(" 123 ") == "rbxassetid://123", "padded")
		T.check(AudioMix.assetUrl(123) == "rbxassetid://123", "number")
		T.check(AudioMix.assetUrl("rbxassetid://456") == "rbxassetid://456", "full url")
		T.check(AudioMix.assetUrl("rbxasset://sounds/electronicpingshort.wav") ~= nil, "built-in sound")
		local list = AudioMix.assetUrls({ "1", "", "junk", 2, "1" })
		T.check(#list == 2 and list[1] == "rbxassetid://1" and list[2] == "rbxassetid://2", "candidate list")
		T.check(#AudioMix.assetUrls("") == 0, "empty list")
	end)
	T.test("profiles: the jet uses turbine sounds, a turboprop uses prop sounds", function()
		T.check(jet.whine == "jetWhine", "jet")
		T.check(AudioMix.profileFor(AudioConfig, "kestrel72", nil).whine == "propDrone", "Kestrel 72 is a turboprop")
		local Registry = require("../src/shared/AircraftRegistry")
		for id in Registry.types do
			T.check(AudioConfig.aircraftProfile[id] ~= nil, id .. " has a sound profile")
		end
		T.check(AudioMix.profileFor(AudioConfig, "unknown", nil).whine == "jetWhine", "default")
	end)
	T.test("engine whine rises in pitch and level with N1; silent when off", function()
		local off = AudioMix.loops(snap({ n1 = 0 }), nil, 0.1, jet, mix)
		local idle = AudioMix.loops(snap({ n1 = 22 }), nil, 0.1, jet, mix)
		local full = AudioMix.loops(snap({ n1 = 100 }), nil, 0.1, jet, mix)
		T.near(off.jetWhine.level, 0, 1e-6, "off")
		T.check(idle.jetWhine.level > 0.2, "idle audible")
		T.check(full.jetWhine.level > idle.jetWhine.level, "louder at full")
		T.check(full.jetWhine.effect > idle.jetWhine.effect, "higher pitch at full")
		T.check(full.jetRumble.level > 3 * idle.jetRumble.level, "rumble follows thrust")
	end)
	T.test("wind grows with airspeed, runway roll only on the ground", function()
		local slow = AudioMix.loops(snap({ ias = 60, onGround = false }), nil, 0.1, jet, mix)
		local fast = AudioMix.loops(snap({ ias = 250, onGround = false }), nil, 0.1, jet, mix)
		T.check(fast.wind.level > 4 * slow.wind.level, "wind")
		T.near(fast.runwayRoll.level, 0, 1e-6, "no roll in the air")
		local roll = AudioMix.loops(snap({ gs = 120, onGround = true }), nil, 0.1, jet, mix)
		T.check(roll.runwayRoll.level > 0.5, "roll on runway")
	end)
	T.test("gear and flap motors run only while moving", function()
		local a = snap({ gearExt = 0.5, flapPos = 2 })
		local moving = AudioMix.loops(snap({ gearExt = 0.52, flapPos = 2.02 }), a, 0.1, jet, mix)
		local still = AudioMix.loops(a, a, 0.1, jet, mix)
		T.check(moving.gearMotor.level == 1 and moving.flapMotor.level == 1, "moving")
		T.check(still.gearMotor.level == 0 and still.flapMotor.level == 0, "still")
	end)
	T.test("warnings: stall horn in the air, gear horn low with gear up", function()
		local stall = AudioMix.loops(snap({ onGround = false, stallWarning = true, raFt = 3000 }), nil, 0.1, jet, mix)
		T.check(stall.stallWarning.level == 1, "stall")
		local gnd = AudioMix.loops(snap({ onGround = true, stallWarning = true }), nil, 0.1, jet, mix)
		T.check(gnd.stallWarning.level == 0, "no stall horn on the ground")
		local gearUp = AudioMix.loops(snap({ onGround = false, gearExt = 0, raFt = 600, throttle = 0.1 }), nil, 0.1, jet, mix)
		T.check(gearUp.gearWarning.level == 1, "gear horn")
		local gearDown = AudioMix.loops(snap({ onGround = false, gearExt = 1, raFt = 600, throttle = 0.1 }), nil, 0.1, jet, mix)
		T.check(gearDown.gearWarning.level == 0, "gear down: quiet")
		local climbing = AudioMix.loops(snap({ onGround = false, gearExt = 0, raFt = 600, throttle = 0.9 }), nil, 0.1, jet, mix)
		T.check(climbing.gearWarning.level == 0, "climb power: quiet")
	end)
	T.test("touchdown: thump scales with sink rate, squeal needs speed", function()
		local prev = snap({ onGround = false })
		local soft = slots(AudioMix.events(snap({ touchdownCount = 1, touchdownVsFpm = -100, gs = 135 }), prev, mix, {}))
		local hard = slots(AudioMix.events(snap({ touchdownCount = 1, touchdownVsFpm = -900, gs = 135 }), prev, mix, {}))
		T.check(soft.touchdown and hard.touchdown and hard.touchdown > soft.touchdown, "thump")
		T.check(soft.tyreSqueal ~= nil, "squeal at speed")
		local taxi = slots(AudioMix.events(snap({ touchdownCount = 1, gs = 10 }), prev, mix, {}))
		T.check(taxi.tyreSqueal == nil, "no squeal when slow")
	end)
	T.test("impacts, part loss and crash produce one-shots with a cooldown", function()
		local memo = {}
		local prev = snap({ time = 1 })
		local light = slots(AudioMix.events(snap({ impactCount = 1, impactDv = 7, time = 1 }), prev, mix, memo))
		T.check(light.impactLight ~= nil, "light")
		local again = slots(AudioMix.events(snap({ impactCount = 2, impactDv = 30, time = 1.1 }), snap({ impactCount = 1, time = 1 }), mix, memo))
		T.check(again.impactHeavy == nil, "cooldown")
		local heavy = slots(AudioMix.events(snap({ impactCount = 3, impactDv = 30, time = 2 }), snap({ impactCount = 2, time = 1.9 }), mix, memo))
		T.check(heavy.impactHeavy ~= nil, "heavy")
		local crash = slots(AudioMix.events(snap({ crashed = true, detachedCount = 3 }), snap(), mix, {}))
		T.check(crash.crash ~= nil, "crash")
		local loops = AudioMix.loops(snap({ crashed = true, n1 = 90, ias = 200 }), nil, 0.1, jet, mix)
		T.check(loops.jetWhine.level == 0 and loops.wind.level == 0, "loops silent after crash")
	end)
	T.test("engine start and gear lock one-shots", function()
		local ev = slots(AudioMix.events(snap({ anyStarting = true }), snap(), mix, {}))
		T.check(ev.engineStart ~= nil, "start")
		local up = slots(AudioMix.events(snap({ gearExt = 0 }), snap({ gearExt = 0.05 }), mix, {}))
		T.check(up.gearLock ~= nil, "locked up")
		local none = slots(AudioMix.events(snap(), nil, mix, {}))
		T.check(next(none) == nil, "no events on the first frame")
	end)
	T.test("stall: horn when about to stall, horn + stick shaker + voice when stalled", function()
		local near = AudioMix.loops(snap({ onGround = false, raFt = 3000, stallWarning = true }), nil, 0.1, jet, mix)
		T.check(near.stallWarning.level == 1 and near.stickShaker.level == 0, "about to stall")
		local stalled = AudioMix.loops(snap({ onGround = false, raFt = 3000, stallWarning = true, stall = true }), nil, 0.1, jet, mix)
		T.check(stalled.stallWarning.level == 1 and stalled.stickShaker.level == 1, "stalled")
		T.check(AudioMix.gpws(snap({ onGround = false, raFt = 3000, stall = true }), mix) == "calloutStall", "stall callout")
		T.check(AudioMix.gpws(snap({ onGround = false, raFt = 3000, stallWarning = true }), mix) == nil, "no voice before the stall")
	end)
	T.test("GPWS: quiet in normal flight, on the ground and on a normal approach", function()
		T.check(AudioMix.gpws(snap({ onGround = false, raFt = 8000, vsFpm = 0, gearExt = 0 }), mix) == nil, "cruise")
		T.check(AudioMix.gpws(snap({ onGround = true, raFt = 0, vsFpm = -3000 }), mix) == nil, "ground")
		-- 3 degree approach, gear down, landing flaps, runway straight ahead in 15 s
		local approach = snap({ onGround = false, raFt = 400, vsFpm = -750, gearExt = 1, flapPos = 5, terrainAheadSec = 15 })
		T.check(AudioMix.gpws(approach, mix) == nil, "approach")
		T.check(AudioMix.gpws(snap({ onGround = false, raFt = 30, vsFpm = -600, gearExt = 0, terrainAheadSec = 1 }), mix) == nil, "below the minimum height")
	end)
	T.test("GPWS: terrain ahead, pull up, sink rate and too low gear", function()
		local base = { onGround = false, gearExt = 0, flapPos = 1, throttle = 0.8 }
		local function g(o)
			local t = table.clone(base)
			for k, v in o do
				t[k] = v
			end
			return AudioMix.gpws(snap(t), mix)
		end
		T.check(g({ raFt = 1500, vsFpm = 0, terrainAheadSec = 20 }) == "calloutTerrain", "terrain ahead")
		T.check(g({ raFt = 1500, vsFpm = 0, terrainAheadSec = 8 }) == "calloutPullUp", "pull up ahead")
		T.check(g({ raFt = 2000, vsFpm = -2400, gearExt = 1 }) == "calloutSinkRate", "sink rate")
		T.check(g({ raFt = 1000, vsFpm = -6000, gearExt = 1 }) == "calloutPullUp", "pull up, diving")
		T.check(g({ raFt = 400, vsFpm = -500 }) == "calloutTooLowGear", "too low gear")
		T.check(g({ raFt = 400, vsFpm = -500, gearExt = 1 }) == nil, "gear down")
	end)
	T.test("callouts repeat at their interval and switch when the danger changes", function()
		local memo = {}
		local sounds = AudioConfig.sounds
		local function at(time, o)
			local t = { onGround = false, gearExt = 0, raFt = 1500, vsFpm = 0, time = time }
			for k, v in o do
				t[k] = v
			end
			return slots(AudioMix.events(snap(t), snap({ time = time - 0.1, onGround = false, gearExt = 0 }), mix, memo, sounds))
		end
		T.check(at(10, { terrainAheadSec = 20 }).calloutTerrain ~= nil, "first")
		T.check(at(10.5, { terrainAheadSec = 18 }).calloutTerrain == nil, "not yet")
		T.check(at(10 + sounds.calloutTerrain.repeatEvery, { terrainAheadSec = 15 }).calloutTerrain ~= nil, "repeat")
		T.check(at(13.6, { terrainAheadSec = 6 }).calloutPullUp ~= nil, "switches to pull up")
		T.check(next(at(20, {})) == nil, "clear: silent")
	end)
	T.test("every callout slot has text for text-to-speech", function()
		for slot, sc in AudioConfig.sounds do
			if string.sub(slot, 1, 7) == "callout" then
				T.check(type(sc.text) == "string" and #sc.text > 0, slot)
				T.check(sc.looped == false and sc.group == "cockpit", slot .. " shape")
			end
		end
	end)
	T.test("takeoff callouts: eighty knots, then rotate", function()
		local function ev(prevIas, ias)
			return slots(AudioMix.events(
				snap({ onGround = true, throttle = 0.9, ias = ias, rotateKts = 140 }),
				snap({ onGround = true, throttle = 0.9, ias = prevIas, rotateKts = 140 }), mix, {}, AudioConfig.sounds))
		end
		T.check(ev(79, 81).calloutEightyKnots ~= nil, "eighty")
		T.check(ev(139, 141).calloutRotate ~= nil, "rotate")
		T.check(next(ev(100, 102)) == nil, "nothing in between")
		local landing = slots(AudioMix.events(snap({ onGround = true, throttle = 0, ias = 79 }), snap({ onGround = true, throttle = 0, ias = 81 }), mix, {}))
		T.check(landing.calloutEightyKnots == nil, "not when slowing after landing")
	end)
	T.test("altitude callouts on approach, lowest height crossed only", function()
		local function ev(prevRa, ra, gear)
			return slots(AudioMix.events(
				snap({ onGround = false, raFt = ra, vsFpm = -700, gearExt = gear or 1, flapPos = 5 }),
				snap({ onGround = false, raFt = prevRa, vsFpm = -700, gearExt = gear or 1, flapPos = 5 }), mix, {}, AudioConfig.sounds))
		end
		T.check(ev(1010, 990).calloutAlt1000 ~= nil, "1000")
		T.check(ev(52, 38).calloutAlt40 ~= nil and ev(52, 38).calloutAlt50 == nil, "lowest only")
		T.check(next(ev(800, 780)) == nil, "between callouts")
		for _, h in mix.altitudeCallouts do
			T.check(AudioConfig.sounds["calloutAlt" .. h] ~= nil, "slot for " .. h)
		end
	end)
	T.test("cabin chime through 10,000 ft", function()
		local up = slots(AudioMix.events(snap({ onGround = false, raFt = 9000, altFt = 10010 }), snap({ onGround = false, raFt = 9000, altFt = 9990 }), mix, {}))
		local down = slots(AudioMix.events(snap({ onGround = false, raFt = 9000, altFt = 9990 }), snap({ onGround = false, raFt = 9000, altFt = 10010 }), mix, {}))
		T.check(up.cabinChime and down.cabinChime, "both ways")
	end)
	T.test("ATC chatter: frequent but not constant, two-voice exchanges", function()
		T.check(AudioMix.atcDelay(0, mix) >= 3 and AudioMix.atcDelay(1, mix) <= 30, "gap after each exchange")
		T.check(mix.atcMaxSeconds <= 15, "length cap")
		T.check(#AudioConfig.atcControllerVoices > 0 and #AudioConfig.atcPilotVoices > 1, "voice lists")
		for _, v in AudioConfig.atcControllerVoices do
			T.check(table.find(AudioConfig.atcPilotVoices, v) == nil, "controllers and pilots use different voices: " .. v)
		end
		local pilotFirst, atcFirst = 0, 0
		for _ = 1, 300 do
			local ex = AudioMix.atcExchange(math.random)
			T.check(#ex.lines == 2, "call and reply")
			T.check(ex.lines[1].who ~= ex.lines[2].who, "two different speakers")
			if ex.lines[1].who == "pilot" then
				pilotFirst += 1
			else
				atcFirst += 1
			end
			for _, line in ex.lines do
				local words = 0
				for _ in string.gmatch(line.text, "%S+") do
					words += 1
				end
				T.check(words >= 3 and words <= 20 and #line.text <= 300, "line length: " .. line.text)
			end
		end
		T.check(pilotFirst > 20 and atcFirst > 20, "both orders happen")
		local v1 = AudioMix.voiceFor("Skyline four two", AudioConfig.atcPilotVoices)
		local v2 = AudioMix.voiceFor("Skyline four two", AudioConfig.atcPilotVoices)
		T.check(v1 == v2, "same callsign keeps its voice")
	end)
	T.test("real alarms: fire bell, overspeed clacker, master warning and caution", function()
		local air = { onGround = false, raFt = 5000 }
		local function sn(o)
			local t = table.clone(air)
			for k, v in o do
				t[k] = v
			end
			return snap(t)
		end
		local l = AudioMix.loops(sn({ fire = true, overspeed = true }), nil, 0.1, jet, mix)
		T.check(l.fireBell.level == 1 and l.overspeedClacker.level == 1, "bell and clacker")
		local quiet = AudioMix.loops(sn({}), nil, 0.1, jet, mix)
		T.check(quiet.fireBell.level == 0 and quiet.overspeedClacker.level == 0, "quiet")
		local warn = slots(AudioMix.events(sn({ warnCount = 1 }), sn({ warnCount = 0 }), mix, {}))
		T.check(warn.masterWarning ~= nil and warn.masterCaution == nil, "master warning")
		local caution = slots(AudioMix.events(sn({ cautionCount = 2 }), sn({ cautionCount = 1 }), mix, {}))
		T.check(caution.masterCaution ~= nil, "master caution")
		local same = slots(AudioMix.events(sn({ cautionCount = 2 }), sn({ cautionCount = 2 }), mix, {}))
		T.check(same.masterCaution == nil, "only when something new goes wrong")
		T.check(AudioMix.gpws(sn({ bank = 50 }), mix) == "calloutBankAngle", "bank angle")
		T.check(AudioMix.gpws(sn({ bank = 20 }), mix) == nil, "normal turn")
	end)
	T.test("pull up: a recorded GPWS clip first, whoop siren + spoken fallback", function()
		local p = AudioConfig.sounds.calloutPullUp
		T.check(type(p.id) == "table" and #p.id > 0, "recorded clip candidates")
		T.check(not string.find(string.lower(p.text), "whoop"), "the whoop is a sound, not words")
		T.check(AudioConfig.sounds.gpwsWhoop and AudioConfig.sounds.gpwsWhoop.maxSeconds, "whoop siren slot")
	end)
	T.test("pitch mapping stays within the slot's range", function()
		local sc = AudioConfig.sounds.jetWhine
		T.near(AudioMix.pitch(sc, 0), sc.pitchMin, 1e-9, "min")
		T.near(AudioMix.pitch(sc, 1), sc.pitchMax, 1e-9, "max")
		T.near(AudioMix.pitch(sc, 5), sc.pitchMax, 1e-9, "clamped")
	end)
end }
