--!nonstrict
-- A small stand-in for the parts of the Roblox API that the aircraft builder uses
-- (Vector3, CFrame, Color3, Instance, Enum, ...), so server code that only builds
-- instances can run under the plain `luau` CLI. It checks structure and maths, not
-- rendering or physics. Only what the builder needs is implemented.

local M = {}

-- Vector3 -----------------------------------------------------------------------------
local V = {}
V.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return V.new(0 / 0, 0 / 0, 0 / 0)
		end
		return V.new(v.X / m, v.Y / m, v.Z / m)
	end
	return rawget(V, k)
end
function V.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __vec = true }, V)
end
V.__add = function(a, b) return V.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return V.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__unm = function(a) return V.new(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then
		return V.new(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return V.new(a.X * b, a.Y * b, a.Z * b)
	end
	return V.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b)
	if type(b) == "number" then
		return V.new(a.X / b, a.Y / b, a.Z / b)
	end
	return V.new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V.__tostring = function(v) return string.format("(%.3f, %.3f, %.3f)", v.X, v.Y, v.Z) end
function V.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V.Cross(a, b)
	return V.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V.Lerp(a, b, t) return a + (b - a) * t end
M.Vector3 = { new = V.new, zero = V.new(0, 0, 0), one = V.new(1, 1, 1),
	xAxis = V.new(1, 0, 0), yAxis = V.new(0, 1, 0), zAxis = V.new(0, 0, 1) }

-- CFrame: position + rotation columns (right, up, back) ---------------------------------
local C = {}
local function cf(p, r, u, b)
	return setmetatable({ p = p, r = r, u = u, b = b, __cf = true }, C)
end
local function rotate(c, v) -- R * v
	return c.r * v.X + c.u * v.Y + c.b * v.Z
end
local function rotateT(c, v) -- R^T * v
	return V.new(c.r:Dot(v), c.u:Dot(v), c.b:Dot(v))
end
C.__index = function(c, k)
	if k == "Position" then
		return c.p
	elseif k == "Rotation" then
		return cf(V.new(0, 0, 0), c.r, c.u, c.b)
	elseif k == "LookVector" then
		return -c.b
	elseif k == "RightVector" then
		return c.r
	elseif k == "UpVector" then
		return c.u
	elseif k == "X" then
		return c.p.X
	elseif k == "Y" then
		return c.p.Y
	elseif k == "Z" then
		return c.p.Z
	end
	return rawget(C, k)
end
C.__mul = function(a, b)
	if b.__vec then
		return a.p + rotate(a, b)
	end
	return cf(a.p + rotate(a, b.p), rotate(a, b.r), rotate(a, b.u), rotate(a, b.b))
end
C.__add = function(a, v) return cf(a.p + v, a.r, a.u, a.b) end
C.__sub = function(a, v) return cf(a.p - v, a.r, a.u, a.b) end
function C.Inverse(c)
	-- inverse rotation is the transpose
	local r = V.new(c.r.X, c.u.X, c.b.X)
	local u = V.new(c.r.Y, c.u.Y, c.b.Y)
	local b = V.new(c.r.Z, c.u.Z, c.b.Z)
	local inv = cf(V.new(0, 0, 0), r, u, b)
	return cf(-rotate(inv, c.p), r, u, b)
end
function C.ToObjectSpace(a, b) return C.Inverse(a) * b end
function C.ToWorldSpace(a, b) return a * b end
function C.PointToWorldSpace(a, v) return a * v end
function C.PointToObjectSpace(a, v) return rotateT(a, v - a.p) end
function C.VectorToWorldSpace(a, v) return rotate(a, v) end
function C.VectorToObjectSpace(a, v) return rotateT(a, v) end

local X, Y, Z = V.new(1, 0, 0), V.new(0, 1, 0), V.new(0, 0, 1)
local function rx(t) local c, s = math.cos(t), math.sin(t) return cf(V.new(0, 0, 0), X, V.new(0, c, s), V.new(0, -s, c)) end
local function ry(t) local c, s = math.cos(t), math.sin(t) return cf(V.new(0, 0, 0), V.new(c, 0, -s), Y, V.new(s, 0, c)) end
local function rz(t) local c, s = math.cos(t), math.sin(t) return cf(V.new(0, 0, 0), V.new(c, s, 0), V.new(-s, c, 0), Z) end

M.CFrame = {
	new = function(a, b, c)
		if a == nil then
			return cf(V.new(0, 0, 0), X, Y, Z)
		elseif type(a) == "table" then
			return cf(a, X, Y, Z)
		end
		return cf(V.new(a, b, c), X, Y, Z)
	end,
	-- Roblox: CFrame.Angles(rx, ry, rz) = Rx * Ry * Rz
	Angles = function(a, b, c)
		return rx(a) * ry(b) * rz(c)
	end,
	fromMatrix = function(p, vx, vy, vz)
		return cf(p, vx, vy, vz or vx:Cross(vy))
	end,
	lookAt = function(at, target, up)
		up = up or Y
		local look = (target - at).Unit
		local right = look:Cross(up).Unit
		local up2 = right:Cross(look)
		return cf(at, right, up2, -look)
	end,
}
M.CFrame.identity = M.CFrame.new()

-- Small value types ------------------------------------------------------------------
local Col = {}
Col.__index = Col
function Col.Lerp(a, b, t)
	return setmetatable({ R = a.R + (b.R - a.R) * t, G = a.G + (b.G - a.G) * t, B = a.B + (b.B - a.B) * t }, Col)
end
M.Color3 = {
	new = function(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Col) end,
	fromRGB = function(r, g, b) return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, Col) end,
}
local function record(kind)
	return { new = function(...) return { __kind = kind, ... } end }
end
M.PhysicalProperties = record("PhysicalProperties")
M.NumberRange = record("NumberRange")
M.NumberSequence = record("NumberSequence")
M.NumberSequenceKeypoint = record("NumberSequenceKeypoint")
M.ColorSequence = record("ColorSequence")
M.UDim = record("UDim")
M.UDim2 = { new = function(...) return { __kind = "UDim2", ... } end, fromScale = function(...) return { __kind = "UDim2", ... } end, fromOffset = function(...) return { __kind = "UDim2", ... } end }
M.Vector2 = { new = function(x, y) return { X = x, Y = y } end }

-- Enum: Enum.A.B is a unique token with Name and Value ---------------------------------
M.Enum = setmetatable({}, { __index = function(_, group)
	return setmetatable({}, { __index = function(_, item)
		return { Name = item, EnumType = group, Value = 0, __enum = group .. "." .. item }
	end })
end })

-- Instance ---------------------------------------------------------------------------
local BASE = {
	Part = { "BasePart", "PVInstance" }, WedgePart = { "BasePart", "PVInstance" }, Seat = { "BasePart", "PVInstance", "Part" },
	Model = { "PVInstance" }, Motor6D = { "JointInstance" }, Weld = { "JointInstance" },
	WeldConstraint = {}, SurfaceGui = { "LayerCollector", "GuiBase" }, TextLabel = { "GuiObject" }, Frame = { "GuiObject" },
	UICorner = {}, UIStroke = {}, Attachment = {}, VectorForce = { "Constraint" }, Torque = { "Constraint" },
	SpecialMesh = {}, ParticleEmitter = {}, SpotLight = { "Light" }, PointLight = { "Light" }, Fire = {},
}
local Inst = {}
local instMeta = {}
instMeta.__index = function(self, k)
	local m = rawget(Inst, k)
	if m then
		return m
	end
	local props = rawget(self, "__props")
	local v = props[k]
	if v ~= nil then
		return v
	end
	-- a child by name (Roblox lets you index children by name)
	for _, c in rawget(self, "__children") do
		if c.Name == k then
			return c
		end
	end
	return nil
end
instMeta.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = self.__props.Parent
		if old then
			local list = old.__children
			for i, c in list do
				if c == self then
					table.remove(list, i)
					break
				end
			end
		end
		if v then
			table.insert(v.__children, self)
		end
	end
	self.__props[k] = v
end
function Inst.IsA(self, cls)
	if self.ClassName == cls or cls == "Instance" then
		return true
	end
	for _, b in BASE[self.ClassName] or {} do
		if b == cls then
			return true
		end
	end
	return false
end
function Inst.GetChildren(self)
	return table.clone(self.__children)
end
function Inst.GetDescendants(self)
	local out = {}
	local function walk(n)
		for _, c in n.__children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function Inst.FindFirstChild(self, name, recursive)
	for _, c in (if recursive then Inst.GetDescendants(self) else self.__children) do
		if c.Name == name then
			return c
		end
	end
	return nil
end
function Inst.FindFirstChildOfClass(self, cls)
	for _, c in self.__children do
		if c.ClassName == cls then
			return c
		end
	end
	return nil
end
function Inst.FindFirstAncestorWhichIsA(self, cls)
	local p = self.Parent
	while p do
		if Inst.IsA(p, cls) then
			return p
		end
		p = p.Parent
	end
	return nil
end
function Inst.IsDescendantOf(self, other)
	local p = self.Parent
	while p do
		if p == other then
			return true
		end
		p = p.Parent
	end
	return false
end
function Inst.SetAttribute(self, k, v)
	self.__attrs[k] = v
end
function Inst.GetAttribute(self, k)
	return self.__attrs[k]
end
function Inst.Destroy(self)
	self.Parent = nil
end
function Inst.WaitForChild(self, name)
	return Inst.FindFirstChild(self, name)
end

M.Instance = {
	new = function(cls, parent)
		local o = setmetatable({ __props = { ClassName = cls, Name = cls }, __children = {}, __attrs = {} }, instMeta)
		if cls == "Part" or cls == "WedgePart" or cls == "Seat" then
			o.Size = V.new(4, 1, 2)
			o.CFrame = M.CFrame.new()
			o.Transparency = 0
			o.Massless = false
		end
		if parent then
			o.Parent = parent
		end
		return o
	end,
}

-- Deterministic stand-ins for Roblox's Random and task libraries.
M.Random = { new = function(seed: number?)
	local x = math.floor((seed or 1) * 7919) % 2147483646 + 1
	return { NextNumber = function(_, a: number?, b: number?)
		x = (x * 16807) % 2147483647
		local u = x / 2147483647
		return (a or 0) + ((b or 1) - (a or 0)) * u
	end }
end }
M.task = { delay = function(_t, _f) end, spawn = function(f, ...) f(...) end, wait = function() return 0 end }

-- Loads a Roblox ModuleScript source file with these globals and a `require` that maps
-- Instance-style module references (`Shared.Units`) to real files.
-- `src` is the module's source text (see tests/run.sh, which embeds it).
function M.loadModule(src: string, chunkName: string, sharedDir: string, realRequire)
	local chunk = assert(loadstring(src, "=" .. chunkName))
	local shared = setmetatable({}, { __index = function(_, name)
		return { __module = sharedDir .. name }
	end })
	shared.WaitForChild = function(_, name)
		return { __module = sharedDir .. name }
	end
	local services = {
		ReplicatedStorage = { WaitForChild = function(_, n) assert(n == "Shared") return shared end },
	}
	local env = setmetatable({
		game = { GetService = function(_, n) return services[n] or {} end },
		require = function(m)
			if type(m) == "table" and m.__module then
				return realRequire(m.__module)
			end
			return realRequire(m)
		end,
		Vector3 = M.Vector3, CFrame = M.CFrame, Color3 = M.Color3, Instance = M.Instance, Enum = M.Enum,
		PhysicalProperties = M.PhysicalProperties, NumberRange = M.NumberRange, NumberSequence = M.NumberSequence,
		NumberSequenceKeypoint = M.NumberSequenceKeypoint, ColorSequence = M.ColorSequence,
		UDim = M.UDim, UDim2 = M.UDim2, Vector2 = M.Vector2, Random = M.Random, task = M.task,
	}, { __index = _G })
	setfenv(chunk, env)
	return chunk()
end

return M
