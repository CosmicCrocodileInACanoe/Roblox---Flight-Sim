--!nonstrict
local Damage = require("../src/shared/Damage")
local cfg = require("../src/shared/Aircraft/Meridian200")

return { name = "Damage model", run = function(T)
	T.test("below threshold: no damage", function()
		local d = Damage.new(cfg.components)
		Damage.applyImpact(d, "LeftWing", 5)
		T.check(d.components.LeftWing.health == 1)
	end)
	T.test("wingtip strike damages that wing, not the other one", function()
		local d = Damage.new(cfg.components)
		Damage.applyImpact(d, "LeftWing", 15)
		T.check(d.components.LeftWing.health < 0.7, "left wing hurt")
		T.check(d.components.RightWing.health == 1, "right wing untouched")
		T.check(d.components.Fuselage.health > 0.85, "only a little propagates to the fuselage")
	end)
	T.test("severe wing strike detaches the wing and its engine and main gear", function()
		local d = Damage.new(cfg.components)
		Damage.applyImpact(d, "RightWing", 25)
		T.check(Damage.state(d, "RightWing") == "detached")
		T.check(Damage.state(d, "RightEngine") == "detached", "engine goes with the wing")
		T.check(Damage.state(d, "RightMainGear") == "detached", "gear goes with the wing")
		T.check(d.components.RightEngine.detachedWithParent == true)
		T.check(Damage.state(d, "LeftWing") == "normal")
	end)
	T.test("same aircraft and obstacle: faster impact means more damage", function()
		local results = {}
		for _, dv in { 8, 14, 20, 30, 45 } do
			local d = Damage.new(cfg.components)
			Damage.applyImpact(d, "ForwardFuselage", dv)
			table.insert(results, d.components.ForwardFuselage.health)
		end
		for i = 2, #results do
			T.check(results[i] <= results[i - 1], "monotonic")
		end
		T.check(results[1] > 0.95 and results[#results] == 0)
	end)
	T.test("slow belly slide degrades but does not destroy; nose-in crash breaks the aircraft", function()
		-- Belly landing: ~2 m/s vertical hit at touchdown then 25 s of sliding from 70 m/s.
		local d = Damage.new(cfg.components)
		Damage.applyImpact(d, "Fuselage", 2)
		local speed = 70
		for _ = 1, 25 * 30 do
			Damage.applyScrape(d, "Fuselage", speed, 1 / 30)
			speed = math.max(0, speed - 2.8 / 30 * 1.0)
		end
		T.check(not d.destroyed, "belly landing survivable")
		T.check(d.components.Fuselage.health < 0.9, "but it should hurt")
		-- High-energy nose-first impact
		local d2 = Damage.new(cfg.components)
		Damage.applyImpact(d2, "ForwardFuselage", 60)
		Damage.applyImpact(d2, "Fuselage", 45)
		T.check(d2.destroyed, "catastrophic")
		T.check(Damage.state(d2, "LeftWing") == "detached" and Damage.state(d2, "AftFuselage") == "detached", "break-up")
	end)
	T.test("gear: 400 fpm fine, 750 fpm degraded, 1100 fpm failed, 1400 fpm collapse", function()
		local L = cfg.gearLimits
		local function landing(fpm)
			local d = Damage.new(cfg.components)
			Damage.applyGearTouchdown(d, "LeftMainGear", fpm / 196.85, 0, L)
			return Damage.state(d, "LeftMainGear")
		end
		T.check(landing(400) == "normal")
		T.check(landing(750) == "degraded", landing(750))
		T.check(landing(1100) == "failed", landing(1100))
		T.check(landing(1400) == "detached", landing(1400))
	end)
	T.test("engine scraping kills the engine in seconds", function()
		local d = Damage.new(cfg.components)
		for _ = 1, 60 * 4 do
			Damage.applyScrape(d, "LeftEngine", 60, 1 / 60)
		end
		T.check(Damage.state(d, "LeftEngine") == "detached" or Damage.state(d, "LeftEngine") == "failed")
	end)
	T.test("states never improve", function()
		local d = Damage.new(cfg.components)
		Damage.applyImpact(d, "VerticalStab", 16)
		local s = Damage.state(d, "VerticalStab")
		Damage.hurt(d, "VerticalStab", 0)
		T.check(Damage.state(d, "VerticalStab") == s)
	end)
end }
