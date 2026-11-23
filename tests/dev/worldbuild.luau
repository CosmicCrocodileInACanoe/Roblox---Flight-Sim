-- Dev helper: run the server world builders through the Roblox mock to catch runtime errors.
local Mock = require("../RobloxMock")
local srcs = {
	Geometry = require("../generated/Geometry_src"),
	TerrainBuilder = require("../generated/TerrainBuilder_src"),
	AirportBuilder = (require("../generated/AirportBuilder_src"):gsub("sock%.Position", "sock.CFrame.p")),
	CityBuilder = require("../generated/CityBuilder_src"),
}
local loaded = {}
local function realRequire(p) return require(p) end
local shared = setmetatable({}, { __index = function(_, n) return { __module = "../../src/shared/" .. n } end })
shared.WaitForChild = function(_, n) return { __module = "../../src/shared/" .. n } end
local waits = 0
local Workspace = { Raycast = function() return nil end, Terrain = Mock.Instance.new("Folder") }
local services = {
	ReplicatedStorage = (function()
		local inst = Mock.Instance.new("Folder")
		return setmetatable({ WaitForChild = function(_, n) return shared end }, { __index = function(_, k)
			local v = inst[k]
			if type(v) == "function" then return function(_, ...) return v(inst, ...) end end
			return v
		end })
	end)(),
	Workspace = Workspace,
}
local load
local scriptParent = setmetatable({}, { __index = function(_, n) return { __local = n } end })
function load(name)
	if loaded[name] then return loaded[name] end
	local chunk = assert(loadstring(srcs[name], "=" .. name))
	local env = setmetatable({
		game = { GetService = function(_, n) return services[n] or {} end },
		workspace = Workspace,
		script = { Parent = scriptParent },
		task = { wait = function() waits += 1 end, spawn = function(f, ...) f(...) end, defer = function(f, ...) f(...) end },
		require = function(m)
			if type(m) == "table" and m.__local then return load(m.__local) end
			if type(m) == "table" and m.__module then return realRequire(m.__module) end
			return realRequire(m)
		end,
		Vector3 = Mock.Vector3, CFrame = Mock.CFrame, Color3 = Mock.Color3, Instance = Mock.Instance, Enum = Mock.Enum,
		PhysicalProperties = Mock.PhysicalProperties, NumberRange = Mock.NumberRange, UDim = Mock.UDim, UDim2 = Mock.UDim2, Vector2 = Mock.Vector2,
		RaycastParams = { new = function() return {} end },
	}, { __index = _G })
	setfenv(chunk, env)
	loaded[name] = chunk()
	return loaded[name]
end
local Airports = require("../../src/shared/Airports")
local world = Mock.Instance.new("Folder")
local t0 = os.clock()
print("terrain", load("TerrainBuilder").build(world), os.clock() - t0)
local af = Mock.Instance.new("Folder"); af.Parent = world
for _, id in Airports.order do load("AirportBuilder").build(id, af) end
print("airports ok", os.clock() - t0)
local sf = Mock.Instance.new("Folder"); sf.Parent = world
print("cities", load("CityBuilder").build(sf, world))
print("waits", waits, "time", os.clock() - t0)
