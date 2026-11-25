--!nonstrict
local Crash = require("../src/shared/Crash")
local Mock = require("./RobloxMock")
local Damage = require("../src/shared/Damage")
local FlightModel = require("../src/shared/FlightModel")
local cfg = require("../src/shared/Aircraft/Meridian200")
local fleet = {
	require("../src/shared/Aircraft/Kestrel72"),
	cfg,
	require("../src/shared/Aircraft/Atlas400"),
	require("../src/shared/Aircraft/Celestia800"),
}

-- A made-up four-engine aircraft with no geometry block and its own names, to prove
-- new models plug in without code changes.
local function jumboCfg()
	return {
		id = "testjumbo",
		components = {
			Fuselage = { mass = 0, impactThreshold = 10, impactDestroy = 40, detachable = false, ref = { 0, 0, 0 } },
			LeftWing = { parent = "Fuselage", mass = 20000, impactThreshold = 7, impactDestroy = 26, detachable = true, ref = { -14, -1, 2 },
				crash = { sections = { { id = "Tip", normal = { -1, 0, 0 }, offset = 22, lost = 0.3 } } } },
			RightWing = { parent = "Fuselage", mass = 20000, impactThreshold = 7, impactDestroy = 26, detachable = true, ref = { 14, -1, 2 } },
			LeftInnerEngine = { parent = "LeftWing", mass = 4000, impactThreshold = 4, impactDestroy = 16, detachable = true, ref = { -10, -3, -2 } },
			LeftOuterEngine = { parent = "LeftWing", mass = 4000, impactThreshold = 4, impactDestroy = 16, detachable = true, ref = { -18, -2.5, 1 },
				crash = { maxDent = 0.9, sections = false } },
			UpperDeck = { parent = "Fuselage", mass = 8000, impactThreshold = 8, impactDestroy = 32, detachable = true, ref = { 0, 3, -20 } },
		},
	}
end

local function partsAlong(n, axis, from, to)
	local out = {}
	for i = 1, n do
		local t = from + (to - from) * (i - 1) / (n - 1)
		local pos = { 0, 0, 0 }
		pos[axis] = t
		table.insert(out, { id = i, pos = pos, dent = 0 })
	end
	return out
end

return { name = "Crash physics (dents, break points, breakup)", run = function(T)
	T.test("every Meridian component gets a profile of the right kind", function()
		local P = Crash.profiles(cfg)
		for name in cfg.components do
			T.check(P[name] ~= nil, name)
		end
		T.check(P.LeftWing.kind == "wing" and P.RightEngine.kind == "engine")
		T.check(P.VerticalStab.kind == "tail" and P.NoseGear.kind == "gear")
		T.check(P.ForwardFuselage.kind == "fuselage")
		T.check(Crash.profiles(cfg) == P, "cached per config")
	end)

	T.test("break points come from the geometry: outer wings, stab tips, fin top", function()
		local P = Crash.profiles(cfg)
		local lw, rw = P.LeftWing.sections[1], P.RightWing.sections[1]
		T.check(lw and lw.id == "Outer" and lw.normal[1] == -1, "left outer wing points left")
		T.check(rw and rw.normal[1] == 1, "right outer wing points right")
		local w = cfg.geometry.wing
		T.between(lw.offset, w.rootLE[1] + 0.3 * w.span, w.rootLE[1] + 0.8 * w.span, "break plane mid-span")
		T.check(#P.HorizontalStab.sections == 2, "two stab tips")
		T.check(#P.VerticalStab.sections == 1 and P.VerticalStab.sections[1].normal[2] == 1, "fin top")
		T.check(#P.LeftEngine.sections == 0 and #P.Fuselage.sections == 0, "engines and fuselage don't half-break")
	end)

	T.test("a new aircraft plugs in by data: names, overrides, hand-placed break points", function()
		local j = jumboCfg()
		local P = Crash.profiles(j)
		T.check(P.LeftInnerEngine.kind == "engine" and P.LeftOuterEngine.kind == "engine")
		T.check(P.UpperDeck.kind == "fuselage")
		T.check(P.LeftOuterEngine.maxDent == 0.9, "override wins")
		T.check(P.LeftOuterEngine.dentRadius == Crash.DEFAULTS.engine.dentRadius, "rest from defaults")
		T.check(#P.LeftOuterEngine.sections == 0)
		T.check(P.LeftWing.sections[1].id == "Tip", "hand-placed section")
		T.check(#P.RightWing.sections == 0, "no geometry, no derived sections")
		-- and the damage model still works with it
		local d = Damage.new(j.components)
		T.check(Damage.breakSection(d, "LeftWing", "Tip", 0.3))
		T.near(Damage.effectiveness(d, "LeftWing"), 0.7, 1e-6, "30% of the lift gone")
	end)

	T.test("dent depth: zero below threshold, grows with impact, saturates", function()
		local p = Crash.profiles(cfg).ForwardFuselage
		T.check(Crash.dentDepth(p, p.dentThreshold - 1) == 0)
		local prev = 0
		for _, dv in { 8, 12, 20, 35, 60, 120 } do
			local dep = Crash.dentDepth(p, dv)
			T.check(dep >= prev, "monotonic")
			T.check(dep <= p.maxDent, "capped")
			prev = dep
		end
		T.check(prev > p.maxDent * 0.95, "big hits approach the max")
		T.check(Crash.dentDepth(p, 0 / 0) == 0, "NaN safe")
	end)

	T.test("crumple: nearest parts move most, along the impact, nothing outside the radius", function()
		local p = Crash.profiles(cfg).ForwardFuselage
		local parts = partsAlong(12, 3, -16, 6) -- along the fuselage
		local depth = Crash.dentDepth(p, 30)
		local res = Crash.crumple(p, parts, { 0, 0, -16 }, { 0, 0, 1 }, depth, 7)
		T.check(#res > 0 and #res <= p.maxParts)
		T.check(res[1].id == 1, "contact part first")
		for i = 2, #res do
			T.check(res[i].offset[3] <= res[i - 1].offset[3] + 1e-9, "falloff")
		end
		for _, r in res do
			T.check(math.abs(r.offset[1]) < 1e-9 and r.offset[3] > 0, "pushed aft, not sideways")
			local part = parts[r.id]
			T.check(math.abs(part.pos[3] + 16) < p.dentRadius, "inside radius")
		end
		T.near(res[1].offset[3], depth, 1e-6, "full depth at contact")
	end)

	T.test("crumple: repeated hits stop at the accumulated dent cap; deterministic by seed", function()
		local p = Crash.profiles(cfg).LeftEngine
		local parts = { { id = 1, pos = { 0, 0, 0 }, dent = p.maxTotalDent - 0.05 } }
		local res = Crash.crumple(p, parts, { 0, 0, 0 }, { 1, 0, 0 }, p.maxDent, 3)
		T.near(res[1].offset[1], 0.05, 1e-6, "only the remaining headroom")
		parts[1].dent = p.maxTotalDent
		T.check(#Crash.crumple(p, parts, { 0, 0, 0 }, { 1, 0, 0 }, p.maxDent, 3) == 0, "fully crumpled")
		local a = Crash.crumple(p, { { id = 1, pos = { 0, 0, 0 } } }, { 0, 0, 0 }, { 0, 1, 0 }, 0.3, 42)
		local b = Crash.crumple(p, { { id = 1, pos = { 0, 0, 0 } } }, { 0, 0, 0 }, { 0, 1, 0 }, 0.3, 42)
		T.check(a[1].twist[1] == b[1].twist[1] and a[1].twist[3] == b[1].twist[3])
		T.check(math.abs(a[1].twist[2]) <= math.rad(p.maxTwistDeg) + 1e-9)
	end)

	T.test("crumple with no direction pushes toward the centre of mass", function()
		local p = Crash.profiles(cfg).RightWing
		local res = Crash.crumple(p, { { id = 1, pos = { 10, 0, 0 } } }, { 10, 0, 0 }, { 0, 0, 0 }, 0.4, 1)
		T.check(res[1].offset[1] < 0)
	end)

	T.test("wing tip strike tears off the outer wing; inboard or soft hits don't", function()
		local p = Crash.profiles(cfg).LeftWing
		local tip = { -15, 0, 8 }
		local root = { -3, -1, 0 }
		T.check(Crash.sectionToBreak(p, tip, p.sectionBreakDv + 1) ~= nil, "hard tip hit")
		T.check(Crash.sectionToBreak(p, tip, p.sectionBreakDv - 2) == nil, "soft tip hit")
		T.check(Crash.sectionToBreak(p, root, 40) == nil, "root hit tears nothing off")
		T.check(Crash.sectionToBreak(p, tip, 40, { Outer = true }) == nil, "only once")
		T.check(Crash.sectionToBreak(p, nil, 40) == nil, "no point, no tear")
		T.check(p.sectionBreakDv < cfg.components.LeftWing.impactDestroy, "tears before the whole wing goes")
	end)

	T.test("losing the outer wing: wing stays on, lift and mass drop, event emitted", function()
		local d = Damage.new(cfg.components)
		local sec = Crash.profiles(cfg).LeftWing.sections[1]
		T.check(Damage.breakSection(d, "LeftWing", sec.id, sec.lost))
		T.check(Damage.isAttached(d, "LeftWing"))
		T.check(Damage.effectiveness(d, "LeftWing") < 0.7, "much less lift")
		T.check(Damage.effectiveness(d, "RightWing") == 1)
		T.check(not Damage.breakSection(d, "LeftWing", sec.id, sec.lost), "can't lose it twice")
		local sawSection = false
		for _, ev in Damage.drainEvents(d) do
			if ev.state == "section" and ev.section == "Outer" then
				sawSection = true
			end
		end
		T.check(sawSection)
		T.check(Damage.sectionMassLost(d, "LeftWing") > 0)
		local fm = FlightModel.new(cfg)
		local m0 = fm:currentMass()
		Damage.breakSection(fm.damage, "LeftWing", sec.id, sec.lost)
		T.check(fm:currentMass() < m0, "lighter")
	end)

	T.test("break plane splits real wing geometry into two non-empty halves", function()
		local w = cfg.geometry.wing
		local parts = {}
		for k = 1, w.segments do
			local s = w.span * (k - 0.5) / w.segments
			table.insert(parts, { id = k, pos = { -(w.rootLE[1] + s), w.rootLE[2], w.rootLE[3] + s * 0.5 } })
		end
		local inside, rest = Crash.partition(Crash.profiles(cfg).LeftWing.sections[1], parts)
		T.check(#inside >= 1 and #rest >= 1)
		for _, id in inside do
			T.check(parts[id].pos[1] < -(w.rootLE[1] + w.span * 0.5), "outboard only")
		end
	end)

	T.test("debris splits across its longest axis at the median", function()
		local parts = partsAlong(6, 1, 0, 10)
		local n, off = Crash.splitPlane(parts)
		T.check(n[1] == 1 and n[2] == 0)
		local a, b = Crash.partition({ id = "x", normal = n, offset = off, lost = 0 }, parts)
		T.check(#a == 3 and #b == 3)
		T.check(Crash.splitPlane({ { id = 1, pos = { 0, 0, 0 } } }) == nil, "one part can't split")
		T.check(Crash.splitPlane({ { id = 1, pos = { 1, 1, 1 } }, { id = 2, pos = { 1, 1, 1 } } }) == nil, "coincident parts")
	end)

	T.test("secondary breakup spends integrity and needs a hard hit", function()
		local p = Crash.profiles(cfg).RightWing
		local piece = { integrity = 2, parts = 10 }
		T.check(not Crash.secondaryBreak(p, piece, p.secondaryBreakDv - 1))
		T.check(Crash.secondaryBreak(p, piece, p.secondaryBreakDv + 1))
		T.check(Crash.secondaryBreak(p, piece, 50))
		T.check(not Crash.secondaryBreak(p, piece, 50), "out of integrity")
		T.check(not Crash.secondaryBreak(p, { integrity = 5, parts = 1 }, 50), "single part")
		T.check(not Crash.secondaryBreak(p, { integrity = 5, parts = 4 }, 0 / 0), "NaN")
	end)

	T.test("torn pieces keep the parent's momentum (v + w x r) plus a push", function()
		local v = Crash.inheritVelocity({ 50, 0, 0 }, { 0, 1, 0 }, { 0, 0, 10 }, { 0, 1, 0 }, 2)
		-- w x r = (0,1,0) x (0,0,10) = (10, 0, 0)
		T.near(v[1], 60, 1e-9)
		T.near(v[2], 2, 1e-9)
		T.near(v[3], 0, 1e-9)
		local still = Crash.inheritVelocity({ 1, 2, 3 }, { 0, 0, 0 }, { 5, 5, 5 }, { 0, 0, 0 }, 9)
		T.check(still[1] == 1 and still[2] == 2 and still[3] == 3, "zero push direction is safe")
	end)

	T.test("shards scale with the hit and stay within the profile cap", function()
		local p = Crash.profiles(cfg).Fuselage
		T.check(Crash.shardCount(p, p.dentThreshold) == 0)
		local prev = 0
		for _, dv in { 12, 20, 30, 60, 200 } do
			local n = Crash.shardCount(p, dv)
			T.check(n >= prev and n <= p.shards)
			prev = n
		end
		T.check(prev == p.shards)
	end)

	T.test("end to end: tip strike leaves a lopsided aircraft, a big hit still detaches", function()
		local d = Damage.new(cfg.components)
		local p = Crash.profiles(cfg).RightWing
		local dv = 16
		Damage.applyImpact(d, "RightWing", dv)
		local sec = Crash.sectionToBreak(p, { 15, 0, 8 }, dv, d.components.RightWing.sectionsLost)
		T.check(sec ~= nil)
		Damage.breakSection(d, "RightWing", sec.id, sec.lost)
		T.check(Damage.isAttached(d, "RightWing"), "still on")
		T.check(Damage.effectiveness(d, "RightWing") < Damage.effectiveness(d, "LeftWing") * 0.7, "lopsided lift")
		Damage.applyImpact(d, "RightWing", 30)
		T.check(Damage.isCollapsed(d, "RightWing"), "big hit crushes the rest, still on by default")
		T.check(Damage.effectiveness(d, "RightWing") < 0.1)
		local d2 = Damage.new(cfg.components, { breakApart = true })
		Damage.applyImpact(d2, "RightWing", 30)
		T.check(Damage.state(d2, "RightWing") == "detached", "break-apart on: big hit takes it")
		T.check(Damage.effectiveness(d2, "RightWing") == 0)
	end)
	T.test("whole fleet: every component profiled, gear is gear, wings tear outboard", function()
		for _, ac in fleet do
			local P = Crash.profiles(ac)
			for name in ac.components do
				local p = P[name]
				T.check(p ~= nil, ac.id .. "." .. name)
				if string.find(name, "Gear") then
					T.check(p.kind == "gear" and #p.sections == 0, ac.id .. "." .. name .. " is gear")
				end
				if string.find(name, "Engine") then
					T.check(p.kind == "engine", ac.id .. "." .. name)
				end
				if p.kind == "gear" or p.kind == "wing" or p.kind == "engine" then
					T.check(Damage.wearKind(name) == p.kind, ac.id .. "." .. name .. " wear kind agrees")
				end
			end
			for _, wname in { "LeftWing", "RightWing" } do
				local sec = P[wname].sections[1]
				T.check(sec and sec.id == "Outer", ac.id .. " " .. wname .. " has a break point")
				-- the plane never cuts through an engine or gear hanging off this wing
				for _, other in ac.components do
					if other.parent == wname then
						T.check(not Crash.inSection(sec, other.ref), ac.id .. " " .. wname .. " plane clears children")
					end
				end
				local d = Damage.new(ac.components)
				T.check(Damage.breakSection(d, wname, sec.id, sec.lost))
				T.check(Damage.isAttached(d, wname) and Damage.effectiveness(d, wname) < 0.75, ac.id .. " lift drops")
			end
		end
	end)

	T.test("T-tail: the fin can't lose its top when the tailplane sits on it", function()
		local k = fleet[1]
		T.check(k.components.HorizontalStab.parent == "VerticalStab", "Kestrel is a T-tail")
		T.check(#Crash.profiles(k).VerticalStab.sections == 0)
		T.check(#Crash.profiles(cfg).VerticalStab.sections == 1, "low tail keeps its fin break point")
	end)

	T.test("easy mode toughness: harder hits needed to dent, tear and split", function()
		local base = Crash.profiles(cfg).LeftWing
		local easy = Crash.profiles(cfg, 1.6).LeftWing
		T.check(easy ~= base and Crash.profiles(cfg, 1.6) == Crash.profiles(cfg, 1.6), "cached per toughness")
		T.near(easy.dentThreshold, base.dentThreshold * 1.6, 1e-9)
		T.check(easy.sectionBreakDv > base.sectionBreakDv and easy.secondaryBreakDv > base.secondaryBreakDv)
		local tip = { -15, 0, 8 }
		local dv = base.sectionBreakDv + 2
		T.check(Crash.sectionToBreak(base, tip, dv) ~= nil and Crash.sectionToBreak(easy, tip, dv) == nil)
	end)
	T.test("craters: none for gentle wrecks, bigger for heavier and faster crashes, capped", function()
		T.check(Crash.craterSize(20000, 5) == nil, "slow: no crater")
		T.check(Crash.craterSize(20000, 0 / 0) == nil, "NaN safe")
		local small = Crash.craterSize(2000, 40)
		local mid = Crash.craterSize(20000, 40)
		local fast = Crash.craterSize(20000, 80)
		local jumbo, rim = Crash.craterSize(300000, 80)
		T.check(small < mid and mid < fast and fast < jumbo, "scales with energy")
		T.between(mid, 4, 14, "small airliner crater radius (m)")
		T.check(jumbo <= 30 and rim > 0 and rim < jumbo, "capped, rim lower than radius")
	end)
	T.test("crater model builds (mock Roblox): pit, rim and clods, all visual-only", function()
		local hasSrc, src = pcall(require, "./generated/CraterService_src")
		T.check(hasSrc, "run tests/run.sh")
		local ok, Craters = pcall(Mock.loadModule, src, "CraterService", "../src/shared/", function(path)
			return require(path)
		end)
		T.check(ok, tostring(Craters))
		local radius, rim = Crash.craterSize(20000, 50)
		local built, m = pcall(Craters.build, Mock.Vector3.new(0, 10, 0), Mock.Vector3.new(0, 1, 0), radius, rim, 7)
		T.check(built, tostring(m))
		local parts = 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				T.check(d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch, d.Name .. " is visual only")
			end
		end
		T.check(parts >= 20 and parts <= 50, "a few dozen parts, not hundreds: " .. parts)
	end)
end }
