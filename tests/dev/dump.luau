local Mock = require("../RobloxMock")
local Enum = Mock.Enum
local Registry = require("../../src/shared/AircraftRegistry")
local src = require("../generated/AircraftBuilder_src")
local B = Mock.loadModule(src, "AircraftBuilder", "../../src/shared/", function(p) return require(p) end)
for _, id in Registry.order do
	local m = B.build(Registry.get(id), Mock.CFrame.new(0, 0, 0))
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and (d.Transparency or 0) < 1 then
			local c, s = d.CFrame, d.Size
			local mesh = d:FindFirstChildOfClass("SpecialMesh")
			local shape = if mesh and tostring(mesh.MeshType.Name or mesh.MeshType):find("Cylinder") then "ecyl" elseif mesh then "ellipsoid" elseif d.ClassName == "WedgePart" then "wedge" else (d.Shape and d.Shape.Name or "block")
			local col = d.Color or { R = 0.5, G = 0.5, B = 0.5 }
			print(string.format("%s %s %s %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.3f %.3f %.3f", id, shape, d.Name,
				c.p.X, c.p.Y, c.p.Z, c.r.X, c.r.Y, c.r.Z, c.u.X, c.u.Y, c.u.Z, c.b.X, c.b.Y, c.b.Z, s.X, s.Y, s.Z, col.R, col.G, col.B))
		end
	end
end
