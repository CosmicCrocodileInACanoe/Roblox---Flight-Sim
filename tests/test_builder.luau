--!nonstrict
-- Runs the real server-side AircraftBuilder against a small mock of the Roblox API and
-- checks the model it produces for every aircraft: structure, joints, sizes and shape.
-- This catches runtime errors and gross geometry mistakes; it cannot check rendering.
local Mock = require("./RobloxMock")
local Registry = require("../src/shared/AircraftRegistry")

local function realRequire(path)
	return require(path)
end

-- tests/run.sh embeds the builder source (the luau CLI cannot read files)
local hasSrc, src = pcall(require, "./generated/AircraftBuilder_src")
local ok, Builder
if hasSrc then
	ok, Builder = pcall(Mock.loadModule, src, "AircraftBuilder", "../src/shared/", realRequire)
else
	ok, Builder = false, "run tests/run.sh (it embeds the builder source first)"
end

local function finite(v)
	return v == v and v ~= math.huge and v ~= -math.huge
end

return { name = "Aircraft builder (mock Roblox)", run = function(T)
	T.test("the builder module loads", function()
		T.check(ok, tostring(Builder))
	end)
	if not ok then
		return
	end
	for _, id in Registry.order do
		local cfg = Registry.get(id)
		local name = cfg.displayName
		local built, model = pcall(Builder.build, cfg, Mock.CFrame.new(0, 100, 0))
		T.test(name .. ": builds without errors", function()
			T.check(built, tostring(model))
		end)
		if not built then
			continue
		end
		local parts, motors, welds, guis = {}, {}, {}, 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			elseif d.ClassName == "Motor6D" then
				table.insert(motors, d)
			elseif d.ClassName == "WeldConstraint" then
				table.insert(welds, d)
			elseif d.ClassName == "SurfaceGui" then
				guis += 1
			end
		end
		T.test(name .. ": part budget and valid sizes", function()
			T.check(#parts < 700, "parts " .. #parts)
			for _, p in parts do
				local s = p.Size
				T.check(finite(s.X) and finite(s.Y) and finite(s.Z), p.Name .. " size not finite")
				T.check(s.X >= 0.05 and s.Y >= 0.05 and s.Z >= 0.05, p.Name .. " too thin " .. tostring(s))
				T.check(s.X <= 2048 and s.Y <= 2048 and s.Z <= 2048, p.Name .. " too big")
				local c = p.CFrame
				T.check(finite(c.Position.X) and finite(c.Position.Y) and finite(c.Position.Z), p.Name .. " position not finite")
				-- rotation must be orthonormal
				T.check(math.abs(c.RightVector:Dot(c.UpVector)) < 1e-4, p.Name .. " skewed frame")
				T.check(math.abs(c.RightVector.Magnitude - 1) < 1e-4, p.Name .. " frame not unit")
			end
		end)
		T.test(name .. ": only the core has mass; every part belongs to a component", function()
			for _, p in parts do
				if p.Name == "Core" then
					T.check(p.Massless == false)
				else
					T.check(p.Massless == true, p.Name .. " has mass")
					T.check(p:GetAttribute("Component") ~= nil, p.Name .. " has no component")
				end
			end
			for comp in cfg.components do
				T.check(model:FindFirstChild(comp) ~= nil, "missing component model " .. comp)
			end
		end)
		T.test(name .. ": joints are complete", function()
			for _, m in motors do
				T.check(m.Part0 and m.Part1, m.Name .. " missing a part")
				T.check(m.Part0:IsDescendantOf(model) and m.Part1:IsDescendantOf(model), m.Name .. " part outside the model")
			end
			for _, w in welds do
				T.check(w.Part0 and w.Part1, "weld missing a part")
			end
			-- every non-core part is held by a weld or motor
			local held = {}
			for _, w in welds do
				held[w.Part1] = true
				held[w.Part0] = true
			end
			for _, m in motors do
				held[m.Part1] = true
				held[m.Part0] = true
			end
			for _, p in parts do
				if p.Name ~= "Core" then
					T.check(held[p], p.Name .. " in " .. tostring(p:GetAttribute("Component")) .. " is not attached")
				end
			end
		end)
		T.test(name .. ": moving parts: control surfaces, fans/props and gear", function()
			local counts = {}
			for _, m in motors do
				local k = m:GetAttribute("Surface") or (if m:GetAttribute("GearName") then "Gear" elseif m:GetAttribute("EngineIndex") then "Fan" else "other")
				counts[k] = (counts[k] or 0) + 1
			end
			local geo = cfg.geometry
			local spoilers = if geo.wing.spoilers == false then nil else 2
			local rudders = geo.vstab.count or 1
			T.check(counts.Flap == 2 and counts.Aileron == 2 and counts.Elevator == 2 and counts.Rudder == rudders and counts.Spoiler == spoilers,
				string.format("surfaces F%s A%s E%s R%s S%s", tostring(counts.Flap), tostring(counts.Aileron), tostring(counts.Elevator), tostring(counts.Rudder), tostring(counts.Spoiler)))
			T.check(counts.Fan == #cfg.engines, "fans " .. tostring(counts.Fan))
			T.check(counts.Gear == #cfg.gear.units, "gear " .. tostring(counts.Gear))
			T.check(guis >= (if cfg.geometry.livery.airline then 4 else 1), "windows/titles " .. guis)
		end)
		T.test(name .. ": every engine faces forward: intake and fan at the front, exhaust behind", function()
			-- body forward is -z. The spinning fan/propeller hub and the intake lip must sit
			-- ahead of the exhaust, and the widest front ring ahead of the tapering tail.
			local core = model.PrimaryPart.CFrame
			local function bodyZ(part)
				return core:PointToObjectSpace(part.CFrame.Position).Z
			end
			for _, e in cfg.engines do
				local comp = model:FindFirstChild(e.component)
				T.check(comp ~= nil, "no engine component " .. e.component)
				local hubZ, exhaustZ, lipZ, aftZ
				for _, d in comp:GetDescendants() do
					if d:IsA("BasePart") then
						local z = bodyZ(d)
						if d.Name == "FanHub" then
							hubZ = z
						elseif d.Name == "Exhaust" then
							exhaustZ = math.max(exhaustZ or -math.huge, z)
						elseif d.Name == "IntakeLip" then
							lipZ = math.min(lipZ or math.huge, z)
						elseif d.Name == "NacelleAft" or d.Name == "ExhaustCone" then
							aftZ = math.max(aftZ or -math.huge, z)
						end
					end
				end
				T.check(hubZ and exhaustZ, e.component .. ": fan hub and exhaust both exist")
				T.check(hubZ < exhaustZ, string.format("%s: fan/prop (z %.1f) must be ahead of the exhaust (z %.1f)", e.component, hubZ, exhaustZ))
				if lipZ and aftZ then
					T.check(lipZ < aftZ, e.component .. ": intake lip must be at the front of the nacelle")
				end
				-- the engine's thrust axis points forward too
				T.check(e.axis[3] < 0, e.component .. ": thrust must point forward (-z)")
			end
		end)

		T.test(name .. ": overall shape matches the configured size", function()
			local S = 1 / 0.28
			local core = model.PrimaryPart.CFrame
			local minX, maxX, minZ, maxZ, maxY = math.huge, -math.huge, math.huge, -math.huge, -math.huge
			for _, p in parts do
				if p.Transparency < 1 then
					-- centre for x/y (wing tips, fin top), true box extent for the nose/tail z
					local lp = core:PointToObjectSpace(p.CFrame.Position) / S
					minX, maxX = math.min(minX, lp.X), math.max(maxX, lp.X)
					maxY = math.max(maxY, lp.Y)
					local c = p.CFrame
					local ez = (math.abs(c.RightVector.Z) * p.Size.X + math.abs(c.UpVector.Z) * p.Size.Y + math.abs(c.LookVector.Z) * p.Size.Z) / 2 / S
					minZ, maxZ = math.min(minZ, lp.Z - ez), math.max(maxZ, lp.Z + ez)
				end
			end
			local half = cfg.aero.wingSpan / 2
			T.between(maxX, half * 0.9, half * 1.08, "right wingtip x")
			T.between(-minX, half * 0.9, half * 1.08, "left wingtip x")
			local g = cfg.geometry.fuselage
			T.between(minZ, g.noseZ - 1, g.noseZ + 1, "nose z")
			T.check(maxZ > g.tailEndZ - 1 and maxZ < g.tailEndZ + 10, "tail z " .. maxZ)
			local finTop = cfg.geometry.vstab.rootLE[2] + cfg.geometry.vstab.height
			T.check(maxY < finTop + 1.5, "something sticks up above the fin: " .. maxY)
		end)
	end
end }
