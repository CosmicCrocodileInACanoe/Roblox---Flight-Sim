--!strict
-- Two-wedge triangle construction (the well-known WedgePart technique), as pure math so
-- it can be unit tested outside Roblox. Works with any vector type that supports + - *,
-- :Dot, :Cross, .Unit and .Magnitude (Roblox Vector3, or the test harness's Vec3).
--
-- A Roblox WedgePart, in its own object space with Size (sx, sy, sz), has a full bottom
-- face (y = -sy/2) and a full back face (z = +sz/2). The slope runs from the top back
-- edge to the bottom front edge. Its cross-section is the right triangle
--   (y, z) = (-sy/2, -sz/2), (-sy/2, +sz/2), (+sy/2, +sz/2), right angle at bottom back.
--
-- solve(a, b, c) returns two wedges { pos, right, up, back, height, length } whose
-- cross-sections together cover triangle abc exactly. Use
--   CFrame.fromMatrix(pos, right, up, back) and Size = (thickness, height, length).
-- Returns nil for degenerate triangles.

local TriMath = {}

function TriMath.solve(a: any, b: any, c: any): { any }?
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- Make bc the longest edge (opposite a).
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local n = ac:Cross(ab)
	if n.Magnitude < 1e-9 then
		return nil
	end
	local right = n.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 1e-6 then
		return nil
	end
	return {
		{ pos = (a + b) * 0.5, right = right, up = up, back = back, height = height, length = math.abs(ab:Dot(back)) },
		{ pos = (a + c) * 0.5, right = right * -1, up = up, back = back * -1, height = height, length = math.abs(ac:Dot(back)) },
	}
end

-- The three corners of a wedge's mid-plane cross-section in world space (for tests).
function TriMath.corners(w: any): { any }
	local h, l = w.height / 2, w.length / 2
	local function at(y: number, z: number)
		return w.pos + w.up * y + w.back * z
	end
	return { at(-h, -l), at(-h, l), at(h, l) }
end

return TriMath
