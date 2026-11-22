--!nonstrict
-- Geometry maths used for wings, tails and terrain (two-wedge triangles).
local TriMath = require("../src/shared/TriMath")

local Vec3 = {}
Vec3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	elseif k == "Unit" then
		local m = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
		return Vec3.new(v.x / m, v.y / m, v.z / m)
	end
	return Vec3[k]
end
function Vec3.new(x, y, z)
	return setmetatable({ x = x, y = y, z = z }, Vec3)
end
Vec3.__add = function(a, b) return Vec3.new(a.x + b.x, a.y + b.y, a.z + b.z) end
Vec3.__sub = function(a, b) return Vec3.new(a.x - b.x, a.y - b.y, a.z - b.z) end
Vec3.__mul = function(a, s) return Vec3.new(a.x * s, a.y * s, a.z * s) end
function Vec3.Dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
function Vec3.Cross(a, b)
	return Vec3.new(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

local function area(a, b, c)
	return (b - a):Cross(c - a).Magnitude / 2
end

local function onSegment(p, a, b)
	local ab = b - a
	local t = (p - a):Dot(ab) / ab:Dot(ab)
	return t >= -1e-6 and t <= 1 + 1e-6 and (a + ab * t - p).Magnitude < 1e-6
end

local function rnd(seed)
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648 * 20 - 10
	end
end

return {
	name = "Geometry",
	run = function(T)
		T.test("two wedges exactly tile any triangle (500 random triangles)", function()
			local r = rnd(7)
			for _ = 1, 500 do
				local a, b, c = Vec3.new(r(), r(), r()), Vec3.new(r(), r(), r()), Vec3.new(r(), r(), r())
				local tri = TriMath.solve(a, b, c)
				if area(a, b, c) < 1e-3 then
					continue
				end
				T.check(tri ~= nil, "degenerate result for a real triangle")
				local verts = { a, b, c }
				local total = 0
				for _, w in tri do
					-- frame is orthonormal
					T.near(w.right:Dot(w.up), 0, 1e-6, "right.up")
					T.near(w.up:Dot(w.back), 0, 1e-6, "up.back")
					T.near((w.right:Cross(w.up) - w.back).Magnitude, 0, 1e-6, "right-handed")
					local k = TriMath.corners(w)
					total += area(k[1], k[2], k[3])
					-- the two sharp corners are triangle vertices; the right-angle corner
					-- (bottom back) lies on the triangle's longest edge
					local matched = 0
					for _, i in { 1, 3 } do
						for _, v in verts do
							if (k[i] - v).Magnitude < 1e-6 then
								matched += 1
								break
							end
						end
					end
					T.check(matched == 2, "wedge sharp corners are not triangle vertices")
					local onEdge = onSegment(k[2], a, b) or onSegment(k[2], b, c) or onSegment(k[2], a, c)
					T.check(onEdge, "right-angle corner is not on an edge")
				end
				T.near(total, area(a, b, c), 1e-6, "areas")
			end
		end)
		T.test("degenerate triangles are skipped", function()
			T.check(TriMath.solve(Vec3.new(0, 0, 0), Vec3.new(1, 0, 0), Vec3.new(2, 0, 0)) == nil)
		end)
	end,
}
