--!nonstrict
local SoftBody = require("../src/shared/SoftBody")
local Crash = require("../src/shared/Crash")
local GameConfig = require("../src/shared/GameConfig")
local cfg = require("../src/shared/Aircraft/Meridian200")
local fleet = {
	require("../src/shared/Aircraft/Kestrel72"),
	cfg,
	require("../src/shared/Aircraft/Atlas400"),
	require("../src/shared/Aircraft/Celestia800"),
}

local Mock = require("./RobloxMock")
local Registry = require("../src/shared/AircraftRegistry")
local hasSrc, builderSrc = pcall(require, "./generated/AircraftBuilder_src")

local function prof(ac, name)
	return SoftBody.bendProfile(ac, name, Crash.kind(name))
end

-- Parts strung along a wing from root to tip (body metres), like the builder's panels.
local function wingParts(ac, side)
	local w = ac.geometry.wing
	local out = {}
	local n = 16
	for k = 0, n - 1 do
		local s = w.span * (k + 0.5) / n
		table.insert(out, { id = k + 1, pos = { side * (w.rootLE[1] + s), w.rootLE[2], w.rootLE[3] + s * 0.4 } })
	end
	return out, w.rootLE[1] + w.span
end

return { name = "Soft-body look (beam bending, mesh skins)", run = function(T)
	T.test("what bends: wings, tails, nose and tail sections; not engines, gear or the centre", function()
		T.check(prof(cfg, "LeftWing") ~= nil and prof(cfg, "VerticalStab") ~= nil)
		T.check(prof(cfg, "ForwardFuselage") ~= nil and prof(cfg, "AftFuselage") ~= nil)
		T.check(prof(cfg, "LeftEngine") == nil and prof(cfg, "NoseGear") == nil)
		T.check(prof(cfg, "Fuselage") == nil, "the centre section is the reference frame")
		local custom = { components = {
			LeftWing = { parent = "Fuselage", ref = { -5, 0, 0 }, crash = { bend = false } },
			UpperDeck = { parent = "Fuselage", ref = { 0, 3, -20 }, crash = { bend = { maxBendDeg = 5 } } },
		} }
		T.check(prof(custom, "LeftWing") == nil, "bend = false")
		T.check(prof(custom, "UpperDeck").maxBendDeg == 5, "override")
	end)

	T.test("beam axes point from root to free end", function()
		local function ax(name, pt)
			return SoftBody.beamAxis(cfg, name, Crash.kind(name), pt or { 0, 0, 0 })
		end
		T.check(ax("LeftWing")[1] == -1 and ax("RightWing")[1] == 1)
		T.check(ax("VerticalStab")[2] == 1)
		T.check(ax("HorizontalStab", { -3, 0, 16 })[1] == -1 and ax("HorizontalStab", { 3, 0, 16 })[1] == 1)
		T.check(ax("ForwardFuselage")[3] == -1 and ax("AftFuselage")[3] == 1)
	end)

	T.test("rotate: 90 degrees about z takes x to y", function()
		local r = SoftBody.rotate({ 1, 0, 0 }, { 0, 0, math.pi / 2 })
		T.near(r[1], 0, 1e-9)
		T.near(r[2], 1, 1e-9)
	end)

	T.test("tip pushed up: the wing curves up, root stays put, bend builds smoothly", function()
		local p = prof(cfg, "RightWing")
		local parts, tipX = wingParts(cfg, 1)
		local point = { tipX - 1, -0.5, 6 }
		local res = SoftBody.bend(p, parts, { 1, 0, 0 }, point, { 0, 1, 0 }, 20)
		T.check(#res.moves > 0 and #res.moves < #parts, "only the outer part bends")
		T.between(res.bentDeg, 1, p.maxBendDeg, "bend angle")
		local byId = {}
		for _, m in res.moves do
			byId[m.id] = m
		end
		T.check(byId[1] == nil, "root part untouched")
		local prevAngle, prevRise = -1, -1
		for _, part in parts do
			local m = byId[part.id]
			if m then
				local angle = math.sqrt(m.rotation[1] ^ 2 + m.rotation[2] ^ 2 + m.rotation[3] ^ 2)
				local np = SoftBody.applyMove(part.pos, m)
				local rise = np[2] - part.pos[2]
				T.check(angle >= prevAngle - 1e-9, "angle grows outboard")
				T.check(rise >= prevRise - 1e-6, "outer parts rise more")
				T.check(rise > -1e-6, "pushed the right way")
				-- smooth: no jump between neighbours bigger than the zone allows
				if prevAngle >= 0 then
					T.check(angle - prevAngle <= math.rad(res.bentDeg) * 0.5 + 1e-9, "no kink")
				end
				prevAngle, prevRise = angle, rise
			end
		end
		T.check(prevRise > 0.3, "the tip visibly moves")
	end)

	T.test("bend scales with the hit, stops at the cap, nothing below the threshold", function()
		local p = prof(cfg, "LeftWing")
		local parts, tipX = wingParts(cfg, -1)
		local pt = { -tipX + 1, -0.5, 6 }
		T.check(#SoftBody.bend(p, parts, { -1, 0, 0 }, pt, { 0, -1, 0 }, p.bendThreshold - 0.5).moves == 0)
		local a = SoftBody.bend(p, parts, { -1, 0, 0 }, pt, { 0, -1, 0 }, 9).bentDeg
		local b = SoftBody.bend(p, parts, { -1, 0, 0 }, pt, { 0, -1, 0 }, 14).bentDeg
		T.check(b > a, "harder hit, bigger bend")
		local capped = SoftBody.bend(p, parts, { -1, 0, 0 }, pt, { 0, -1, 0 }, 80, { bentDeg = p.maxBendDeg - 2, crushed = 0 })
		T.near(capped.bentDeg, 2, 1e-9, "only up to the cap")
		local full = SoftBody.bend(p, parts, { -1, 0, 0 }, pt, { 0, -1, 0 }, 80, { bentDeg = p.maxBendDeg, crushed = 0 })
		T.check(#full.moves == 0, "fully bent")
		T.check(#SoftBody.bend(p, parts, { -1, 0, 0 }, pt, { 0, -1, 0 }, 0 / 0).moves == 0, "NaN safe")
	end)

	T.test("nose-first hit crushes the nose back like an accordion instead of bending it", function()
		local p = prof(cfg, "ForwardFuselage")
		local parts = {}
		for k = 1, 12 do
			table.insert(parts, { id = k, pos = { 0, 0, -6 - k } })
		end
		local res = SoftBody.bend(p, parts, { 0, 0, -1 }, { 0, 0, -17.5 }, { 0, 0, 1 }, 30)
		T.check(res.bentDeg == 0 and res.crushed > 0.5, "crushed, not bent")
		T.check(res.crushed <= p.maxCrush)
		for _, m in res.moves do
			T.check(m.translate[3] > 0, "pushed aft")
		end
	end)

	T.test("too many parts: skip rather than stall a kid's PC", function()
		local p = prof(cfg, "LeftWing")
		local parts = {}
		for k = 1, p.maxParts + 1 do
			table.insert(parts, { id = k, pos = { -k * 0.05, 0, 0 } })
		end
		T.check(#SoftBody.bend(p, parts, { -1, 0, 0 }, { -10, 0, 0 }, { 0, 1, 0 }, 30).moves == 0)
	end)

	T.test("every aircraft's wings bend from their own geometry", function()
		for _, ac in fleet do
			for _, side in { -1, 1 } do
				local name = if side < 0 then "LeftWing" else "RightWing"
				local p = prof(ac, name)
				local axis = SoftBody.beamAxis(ac, name, "wing", { 0, 0, 0 })
				local parts, tipX = wingParts(ac, side)
				local res = SoftBody.bend(p, parts, axis, { side * (tipX - 0.5), 0, 5 }, { 0, 1, 0 }, 18)
				T.check(#res.moves > 0, ac.id .. " " .. name)
			end
		end
	end)

	T.test("mesh grids: right counts, valid triangles, stay within the part", function()
		local n = GameConfig.crash.meshSkins.grid
		for _, shape in { "box", "wedge", "cylinderX", "ellipsoid" } do
			local g = SoftBody.grid(shape, { 4, 2, 6 }, n)
			T.check(#g.verts == 6 * (n + 1) ^ 2, shape .. " verts")
			T.check(#g.tris == 12 * n * n, shape .. " tris")
			T.check(#g.verts < 60000 and #g.tris < 20000, "under EditableMesh limits")
			for _, t in g.tris do
				for _, i in t do
					T.check(g.verts[i] ~= nil, "index in range")
				end
			end
			for _, v in g.verts do
				T.check(math.abs(v[1]) <= 2 + 1e-9 and math.abs(v[2]) <= 1 + 1e-9 and math.abs(v[3]) <= 3 + 1e-9, shape .. " in bounds")
			end
		end
		for _, v in SoftBody.grid("ellipsoid", { 4, 2, 6 }, n).verts do
			T.near((v[1] / 2) ^ 2 + v[2] ^ 2 + (v[3] / 3) ^ 2, 1, 1e-9, "on the ellipsoid")
		end
		for _, v in SoftBody.grid("cylinderX", { 4, 2, 2 }, n).verts do
			T.check(v[2] ^ 2 + v[3] ^ 2 <= 1 + 1e-9, "inside the round section")
		end
		for _, v in SoftBody.grid("wedge", { 1, 2, 2 }, n).verts do
			T.check(v[2] <= v[3] + 1e-9, "under the wedge slope")
		end
	end)

	T.test("box triangles face outward", function()
		local g = SoftBody.grid("box", { 2, 2, 2 }, 2)
		for _, t in g.tris do
			local a, b, c = g.verts[t[1]], g.verts[t[2]], g.verts[t[3]]
			local e1 = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
			local e2 = { c[1] - a[1], c[2] - a[2], c[3] - a[3] }
			local nrm = SoftBody.cross(e1, e2)
			local cen = { (a[1] + b[1] + c[1]) / 3, (a[2] + b[2] + c[2]) / 3, (a[3] + b[3] + c[3]) / 3 }
			T.check(nrm[1] * cen[1] + nrm[2] * cen[2] + nrm[3] * cen[3] > 0, "outward")
		end
	end)

	T.test("vertex dents: local, along the push, capped, deterministic", function()
		local g = SoftBody.grid("box", { 4, 4, 4 }, 4)
		local rest = {}
		for i, v in g.verts do
			rest[i] = { v[1], v[2], v[3] }
		end
		local moved = SoftBody.dentVertices(g.verts, rest, { 0, 2, 0 }, { 0, -1, 0 }, 0.8, 2.5, 0.6, 3)
		local count, deepest = 0, 0
		for i, nv in moved do
			count += 1
			T.check(nv[2] < g.verts[i][2], "pushed down")
			local off = math.sqrt((nv[1] - rest[i][1]) ^ 2 + (nv[2] - rest[i][2]) ^ 2 + (nv[3] - rest[i][3]) ^ 2)
			T.check(off <= 0.6 + 1e-9, "capped")
			deepest = math.max(deepest, off)
		end
		T.check(count > 0 and count < #g.verts / 2, "only near the hit")
		T.check(deepest > 0.5, "visible")
		local again = SoftBody.dentVertices(g.verts, rest, { 0, 2, 0 }, { 0, -1, 0 }, 0.8, 2.5, 0.6, 3)
		for i, nv in moved do
			T.check(again[i][2] == nv[2], "deterministic")
		end
		T.check(next(SoftBody.dentVertices(g.verts, rest, { 0, 2, 0 }, { 0, -1, 0 }, 0, 2.5, 0.6)) == nil, "zero depth")
		-- repeated dents stop at the cap measured from the rest shape
		local verts = g.verts
		for _ = 1, 10 do
			for i, nv in SoftBody.dentVertices(verts, rest, { 0, 2, 0 }, { 0, -1, 0 }, 0.8, 2.5, 0.6, 1) do
				verts[i] = nv
			end
		end
		for i, v in verts do
			local off = math.sqrt((v[1] - rest[i][1]) ^ 2 + (v[2] - rest[i][2]) ^ 2 + (v[3] - rest[i][3]) ^ 2)
			T.check(off <= 0.6 + 1e-6, "never caves past the cap")
		end
	end)

	T.test("skin budget stays small", function()
		local c = GameConfig.crash.meshSkins
		T.check(c.maxSkins <= 8, "under the reported per-client EditableMesh cap")
		T.check(c.maxSkins * 6 * (c.grid + 1) ^ 2 <= 2000, "a few thousand vertices at most")
	end)
	T.test("built aircraft: every bendable beam is small enough to bend", function()
		T.check(hasSrc, "run tests/run.sh")
		local ok, Builder = pcall(Mock.loadModule, builderSrc, "AircraftBuilder", "../src/shared/", function(path)
			return require(path)
		end)
		T.check(ok, tostring(Builder))
		for _, id in Registry.order do
			local ac = Registry.get(id)
			local model = Builder.build(ac, Mock.CFrame.new(0, 100, 0))
			for name in ac.components do
				local p = prof(ac, name)
				local comp = model:FindFirstChild(name)
				if p and comp then
					local n = 0
					for _, d in comp:GetDescendants() do
						if d:IsA("BasePart") then
							n += 1
						end
					end
					T.check(n > 0 and n <= p.maxParts, string.format("%s.%s has %d parts (max %d)", id, name, n, p.maxParts))
				end
			end
		end
	end)
end }
