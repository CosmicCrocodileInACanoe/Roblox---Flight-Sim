--!nonstrict
-- Builds every emergency vehicle (src/client/ResponderModels.luau) against the Roblox
-- mock: each has an anchored invisible Root, everything else is welded to it (or to the
-- helicopter's rotor hub), nothing collides, and the warning lights are tagged.
local Mock = require("./RobloxMock")

local hasSrc, src = pcall(require, "./generated/ResponderModels_src")
local ok, Models
if hasSrc then
	ok, Models = pcall(Mock.loadModule, src, "ResponderModels", "../src/shared/", function(p)
		return require(p)
	end)
else
	ok, Models = false, "run tests/run.sh (it embeds the source first)"
end

return { name = "Emergency vehicles (mock Roblox)", run = function(T)
	T.test("the vehicle models module loads", function()
		T.check(ok, tostring(Models))
	end)
	if not ok then
		return
	end
	for _, name in { "fireTruck", "ambulance", "police", "rescueBoat", "ferry", "helicopter", "lifeRaft" } do
		T.test("builds a " .. name, function()
			local m, hub = Models[name]()
			T.check(m and m.PrimaryPart and m.PrimaryPart.Name == "Root", "has a Root")
			T.check(m.PrimaryPart.Anchored == true, "Root anchored")
			local parts, lights = 0, 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
					T.check(d.CanCollide == false, name .. ": nothing collides")
					if d ~= m.PrimaryPart and d ~= hub then
						T.check(d.Anchored == false, name .. ": welded parts are unanchored")
						local welded = false
						for _, c in d:GetChildren() do
							if c.ClassName == "WeldConstraint" and c.Part1 == d and (c.Part0 == m.PrimaryPart or c.Part0 == hub) then
								welded = true
							end
						end
						T.check(welded, name .. ": every part is welded to the Root")
						local s = d.Size
						T.check(s.X > 0 and s.Y > 0 and s.Z > 0 and s.X == s.X, name .. ": sane sizes")
					end
					if d:GetAttribute("Flash") then
						lights += 1
					end
				end
			end
			T.check(parts >= 5, name .. ": has some shape")
			if name ~= "lifeRaft" then
				T.check(lights >= 2, name .. ": has warning lights")
			end
			if name == "helicopter" then
				T.check(hub and hub.Anchored, "the rotor hub is driven separately")
			end
			if name == "fireTruck" then
				T.check(m:FindFirstChild("Nozzle") ~= nil, "a water cannon")
			end
		end)
	end
end }
