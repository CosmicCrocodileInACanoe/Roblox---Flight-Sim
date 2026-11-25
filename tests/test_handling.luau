--!nonstrict
-- Handling: Q/E rudder behaviour in the assisted modes, and the Free handling mode
-- (bank and pitch where you leave them, faster roll and pitch, few limits).
local Sim = require("./SimHarness")
local U = require("../src/shared/Units")
local Assist = require("../src/shared/Assist")
local FM = require("../src/shared/FlightModel")
local Registry = require("../src/shared/AircraftRegistry")
local MathUtil = require("../src/shared/MathUtil")

local function cruiseSim(cfg, mode)
	local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = 1500,
		speed = cfg.speeds.cruise * U.MPS_PER_KT * 0.9, toughness = Assist.toughness(mode) })
	s.ctl.gearDown = false
	local a = Assist.new(mode)
	a.autoTrim = 0.1
	local raw = FM.newControls()
	raw.throttle, raw.gearDown, raw.flaps = 0.6, false, 1
	return s, a, raw
end

local function step(s, a, raw)
	s:prepareEnv()
	Assist.apply(a, raw, s.ctl, s.env, s.model, 1 / 60)
	s:frame()
end

-- signed smallest difference b - a in degrees
local function hdiff(a, b)
	return (b - a + 540) % 360 - 180
end

return { name = "Handling", run = function(T)
	T.test("four assist modes; T cycles forward and the menu can step back", function()
		T.check(#Assist.MODES == 4 and table.find(Assist.MODES, "free") ~= nil)
		local m = "easy"
		for _ = 1, #Assist.MODES do
			T.check(Assist.prevMode(Assist.nextMode(m)) == m)
			m = Assist.nextMode(m)
		end
		T.check(m == "easy")
		T.check(Assist.LABELS.free ~= nil)
		T.check(Assist.toughness("free") >= 1)
	end)

	T.test("camera stays where the pilot left it for 10 s, then eases back the short way", function()
		local yaw = math.rad(150)
		T.check(MathUtil.recenter(yaw, 0, 9.9, 10, 1 / 60) == yaw, "moved before 10 s")
		local idle = 10
		local first = MathUtil.recenter(yaw, 0, idle, 10, 1 / 60)
		T.check(first < yaw and first > yaw - math.rad(3), "jumped instead of easing")
		local y = yaw
		for _ = 1, 60 * 8 do
			idle += 1 / 60
			y = MathUtil.recenter(y, 0, idle, 10, 1 / 60)
		end
		T.check(math.abs(y) < math.rad(1), string.format("still %.1f deg off after 8 s", math.deg(y)))
		-- a look angle past half a turn comes back the short way, not all the way round
		local wrapped = MathUtil.recenter(math.rad(350), 0, 11, 10, 1 / 60)
		T.check(math.abs(MathUtil.wrapPi(wrapped)) < math.rad(10.1), "went the long way round")
		-- pitch eases to its own resting angle, not zero
		local p = math.rad(40)
		for _ = 1, 60 * 10 do
			p = MathUtil.recenter(p, math.rad(-8), 20, 10, 1 / 60)
		end
		T.near(p, math.rad(-8), math.rad(0.5), "pitch rest")
	end)

	T.test("free mode passes flaps, gear, throttle and brakes through untouched", function()
		local cfg = Registry.get("meridian200")
		local s, a, raw = cruiseSim(cfg, "free")
		raw.flaps, raw.gearDown, raw.throttle, raw.speedbrake, raw.brake = 3, true, 0.42, 0.5, 0
		s:prepareEnv()
		Assist.apply(a, raw, s.ctl, s.env, s.model, 1 / 60)
		T.check(s.ctl.flaps == 3 and s.ctl.gearDown == true and s.ctl.speedbrake == 0.5)
		T.near(s.ctl.throttle, 0.42, 1e-9, "throttle")
	end)

	for _, id in Registry.order do
		local cfg = Registry.get(id)
		local name = cfg.displayName
		for _, mode in { "easy", "free", "assisted" } do
			T.test(`{name}: {mode}, holding Q yaws steadily left and releasing it settles without swinging`, function()
				local s, a, raw = cruiseSim(cfg, mode)
				local _, _, h0 = s:attitude()
				local last = h0
				local reversal = 0
				for f = 1, 60 * 4 do
					raw.yaw = math.max(-1, raw.yaw - 3 / 60)
					step(s, a, raw)
					local _, _, h = s:attitude()
					if f > 30 then
						reversal += math.max(0, hdiff(last, h)) -- any swing back to the right
					end
					last = h
				end
				local _, _, hHeld = s:attitude()
				T.check(hdiff(h0, hHeld) < -0.8, string.format("only yawed %.1f deg", hdiff(h0, hHeld)))
				T.check(reversal < 0.6, string.format("swung back %.1f deg while Q was held", reversal))
				-- release: the yaw rate may change sign once (the nose easing back), not keep swinging
				local signChanges, lastSign = 0, 0
				for f = 1, 60 * 8 do
					raw.yaw = math.min(0, raw.yaw + 4.5 / 60)
					step(s, a, raw)
					local wy = s.env.wy
					if f > 20 and math.abs(wy) > math.rad(0.4) then
						local sg = math.sign(wy)
						if lastSign ~= 0 and sg ~= lastSign then
							signChanges += 1
						end
						lastSign = sg
					end
				end
				T.check(signChanges <= 1, string.format("nose swung back and forth %d times after release", signChanges))
				T.check(math.abs(math.deg(s.model.result.beta)) < 1.0, string.format("still %.1f deg of sideslip", math.deg(s.model.result.beta)))
				local _, b = s:attitude()
				if mode == "easy" then
					T.check(math.abs(b) < 8, string.format("still banked %.1f deg", b))
				end
				T.check(s:isFinite())
			end)
		end

		local lim = Assist.limits(cfg)
		T.test(`{name}: free mode rolls faster than easy, then holds the bank it is left in`, function()
			local function rollFor(mode, seconds)
				local s, a, raw = cruiseSim(cfg, mode)
				raw.roll = 1
				for _ = 1, math.floor(60 * seconds) do
					step(s, a, raw)
				end
				return s, a, raw
			end
			local se = rollFor("easy", 1.5)
			local s, a, raw = rollFor("free", 1.5)
			local _, be = se:attitude()
			local _, bf = s:attitude()
			T.check(bf > be + 1, string.format("free %.1f vs easy %.1f deg after 1.5 s", bf, be))
			raw.roll = 0
			for _ = 1, 60 * 2 do
				step(s, a, raw)
			end
			local _, b1 = s:attitude()
			for _ = 1, 60 * 6 do
				step(s, a, raw)
			end
			local _, b2 = s:attitude()
			if not lim.aerobatic then
				T.check(b1 > 8, string.format("bank only %.1f", b1))
				T.check(math.abs(b2 - b1) < 6, string.format("bank drifted from %.1f to %.1f", b1, b2))
			end
			T.check(s:isFinite())
		end)

		if not lim.aerobatic then
			T.test(`{name}: free mode banks past the easy limit but stops short of 85 deg`, function()
				local s, a, raw = cruiseSim(cfg, "free")
				raw.roll = 1
				local maxB = 0
				for _ = 1, 60 * 14 do
					step(s, a, raw)
					local _, b = s:attitude()
					maxB = math.max(maxB, b)
				end
				T.check(maxB > math.deg(lim.bank) + 5 or maxB > 70, string.format("only reached %.1f deg", maxB))
				T.check(maxB < 85, string.format("reached %.1f deg", maxB))
			end)
		end

		T.test(`{name}: free mode holds the pitch it is left at, without stalling`, function()
			local s, a, raw = cruiseSim(cfg, "free")
			raw.throttle = 0.9
			raw.pitch = 1
			local stalled = false
			for _ = 1, 60 * 1.5 do
				step(s, a, raw)
			end
			raw.pitch = 0
			for _ = 1, 60 * 1 do
				step(s, a, raw)
			end
			local p1 = s:attitude()
			for _ = 1, 60 * 4 do
				step(s, a, raw)
				local r = s.model.result
				if (r.wingAlpha or 0) > (r.stallAlpha or 1) then
					stalled = true
				end
			end
			local p2 = s:attitude()
			T.check(p1 > 5, string.format("pitch only %.1f", p1))
			T.check(math.abs(p2 - p1) < 5, string.format("pitch drifted from %.1f to %.1f", p1, p2))
			T.check(not stalled, "stalled")
		end)
	end
end }
