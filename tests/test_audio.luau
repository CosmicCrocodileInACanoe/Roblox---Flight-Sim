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
			T.check(type(sc.id) == "string" or type(sc.id) == "number", slot .. " id type")
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
	end)
	T.test("profiles: the jet uses turbine sounds, a turboprop uses prop sounds", function()
		T.check(jet.whine == "jetWhine", "jet")
		T.check(AudioMix.profileFor(AudioConfig, "turboprop", nil).whine == "propDrone", "prop")
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
	T.test("pitch mapping stays within the slot's range", function()
		local sc = AudioConfig.sounds.jetWhine
		T.near(AudioMix.pitch(sc, 0), sc.pitchMin, 1e-9, "min")
		T.near(AudioMix.pitch(sc, 1), sc.pitchMax, 1e-9, "max")
		T.near(AudioMix.pitch(sc, 5), sc.pitchMax, 1e-9, "clamped")
	end)
end }
