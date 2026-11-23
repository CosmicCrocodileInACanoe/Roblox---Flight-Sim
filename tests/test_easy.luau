--!nonstrict
-- Easy mode (the default, aimed at 8-12 year olds): a careless pilot who holds the
-- stick hard over, pulls all the way back or comes in too steep should still be safe.
local Sim = require("./SimHarness")
local U = require("../src/shared/Units")
local Assist = require("../src/shared/Assist")
local FM = require("../src/shared/FlightModel")
local Registry = require("../src/shared/AircraftRegistry")

local function cruiseSim(cfg)
	local s = Sim.new(cfg, { enginesRunning = true, flaps = 1, gearDown = false, y = 1500,
		speed = cfg.speeds.cruise * U.MPS_PER_KT * 0.9, toughness = Assist.toughness("easy") })
	s.ctl.gearDown = false
	local a = Assist.new("easy")
	a.autoTrim = 0.1
	local raw = FM.newControls()
	raw.throttle, raw.gearDown, raw.flaps = 0.55, false, 1
	return s, a, raw
end

local function fly(s, a, raw, seconds, each)
	for _ = 1, math.floor(60 * seconds) do
		s:prepareEnv()
		Assist.apply(a, raw, s.ctl, s.env, s.model, 1 / 60)
		s:frame()
		if each then
			each()
		end
	end
end

return { name = "Easy mode", run = function(T)
	T.test("easy is the default assist mode and cycles through all three", function()
		T.check(Assist.new().mode == "easy")
		T.check(Assist.nextMode("easy") == "assisted")
		T.check(Assist.nextMode("assisted") == "simulation")
		T.check(Assist.nextMode("simulation") == "easy")
		T.check(Assist.toughness("easy") > 1 and Assist.toughness("simulation") == 1)
	end)

	for _, id in Registry.order do
		local cfg = Registry.get(id)
		local name = cfg.displayName
		local lim = Assist.limits(cfg)
		local bankMax, pitchMax, diveMax = math.deg(lim.bank) + 5, math.deg(lim.pitchUp) + 7, math.deg(lim.pitchDown) - 5

		T.test(name .. `: easy, stick held hard over stays under {bankMax} deg bank, then levels itself`, function()
			local s, a, raw = cruiseSim(cfg)
			local maxBank = 0
			local y0 = s.py
			raw.roll = 1
			fly(s, a, raw, 15, function()
				local _, b = s:attitude()
				maxBank = math.max(maxBank, math.abs(b))
			end)
			T.check(maxBank < bankMax, string.format("bank reached %.1f", maxBank))
			raw.roll = 0
			fly(s, a, raw, 14) -- gentle self-levelling: the jumbo takes a while
			local _, b = s:attitude()
			T.check(math.abs(b) < 5, string.format("still banked %.1f after release", b))
			T.check(y0 - s.py < 150, string.format("lost %.0f m in the turn", y0 - s.py))
			T.check(s:isFinite())
		end)

		T.test(name .. ": easy, full back stick for 30 s never stalls", function()
			local s, a, raw = cruiseSim(cfg)
			raw.throttle = 0.3
			raw.pitch = 1
			local maxPitch, stalled = -90, false
			fly(s, a, raw, 30, function()
				local p = s:attitude()
				maxPitch = math.max(maxPitch, p)
				local r = s.model.result
				if (r.wingAlpha or 0) > (r.stallAlpha or 1) then
					stalled = true
				end
			end)
			T.check(not stalled, "wing went past the stall angle")
			T.check(maxPitch < pitchMax, string.format("pitch reached %.1f", maxPitch))
			local kt = s.model.result.ias * U.KTS_PER_MPS
			T.check(kt > cfg.speeds.vref * 0.9, string.format("speed decayed to %.0f kt", kt))
		end)

		T.test(name .. `: easy, full forward stick holds the dive under {-diveMax} deg`, function()
			local s, a, raw = cruiseSim(cfg)
			raw.pitch = -1
			local minPitch, maxKt = 90, 0
			fly(s, a, raw, 12, function()
				local p = s:attitude()
				minPitch = math.min(minPitch, p)
				maxKt = math.max(maxKt, s.model.result.ias * U.KTS_PER_MPS)
			end)
			T.check(minPitch > diveMax, string.format("pitch reached %.1f", minPitch))
			T.check(maxKt < cfg.speeds.vmo * 1.12, string.format("speed reached %.0f kt", maxKt))
			for cname, c in s.model.damage.components do
				T.check(c.state == "normal", cname .. " damaged by the dive")
			end
		end)

		T.test(name .. ": easy, a steep hands-off arrival still lands without damage", function()
			-- Gear and flaps down, coming down too steeply (about 1,000 fpm) with the
			-- stick released: the flare helper and tougher airframe should save it.
			local flaps = #cfg.aero.flaps.labels
			local spd = cfg.speeds.approach * U.MPS_PER_KT
			local s = Sim.new(cfg, { enginesRunning = true, flaps = flaps, gearDown = true, y = 80, pitchDeg = -1,
				speed = spd, toughness = Assist.toughness("easy") })
			s.vy = -5.2
			s.ctl.flaps = flaps
			local a = Assist.new("easy")
			a.autoTrim = 0.6
			local raw = FM.newControls()
			raw.throttle, raw.gearDown, raw.flaps = 0.35, true, flaps
			local td
			for _ = 1, 60 * 90 do
				s:prepareEnv()
				Assist.apply(a, raw, s.ctl, s.env, s.model, 1 / 60)
				local vyBefore = s.vy
				local r2 = s:frame()
				if not td and r2.wheelsOnGround > 0 then
					td = vyBefore * U.FPM_PER_MPS
					raw.throttle = 0
				end
				if td and s:groundSpeed() < 20 then
					break
				end
			end
			T.check(td ~= nil, "never touched down")
			for cname, c in s.model.damage.components do
				T.check(c.state == "normal", string.format("%s %s on touchdown at %.0f fpm", cname, c.state, td or 0))
			end
			T.check(s:isFinite())
		end)
	end
end }
