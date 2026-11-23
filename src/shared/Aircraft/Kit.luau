--!strict
-- Small helpers shared by the aircraft configs, so a new type is mostly numbers.
-- Not an aircraft itself (the registry lists aircraft by name).
--
-- Body axes as everywhere: x = right wing, y = up, z = toward the tail, origin at the CoM.

local rad = math.rad

local Kit = {}

-- The four aero panels every aircraft uses: one per half-wing, the tailplane and the fin.
--   w = { area (both halves), x, y, z, dihedralDeg, aspect, oswald, clAlpha, cl0,
--         incidenceDeg, stallDeg, stallWidthDeg, cd0, cm0, chord }
--   t = { area, pos, aspect, clAlpha, incidenceDeg, chord, downwash (lift-slope factor) }
--   f = { area, pos, aspect, clAlpha, chord }
function Kit.panels(w: any, t: any, f: any): { any }
	local function wing(side: number): any
		local d = rad(w.dihedralDeg or 0)
		return {
			name = if side < 0 then "LeftWing" else "RightWing",
			component = if side < 0 then "LeftWing" else "RightWing",
			role = "wing", side = side,
			pos = { side * w.x, w.y, w.z }, normal = { -side * math.sin(d), math.cos(d), 0 },
			area = w.area / 2, aspect = w.aspect, oswald = w.oswald or 0.8,
			clAlpha = w.clAlpha, cl0 = w.cl0, incidence = rad(w.incidenceDeg or 1.5),
			alphaStall = rad(w.stallDeg), stallWidth = rad(w.stallWidthDeg or 4),
			cd0 = w.cd0 or 0.01, cm0 = w.cm0 or -0.04, chord = w.chord,
		}
	end
	return {
		wing(-1),
		wing(1),
		{
			name = "Tailplane", component = "HorizontalStab", role = "hstab", side = 0,
			pos = t.pos, normal = { 0, 1, 0 },
			area = t.area, aspect = t.aspect or 4.5, oswald = 0.75,
			clAlpha = t.clAlpha * (t.downwash or 0.7), cl0 = 0.0, incidence = rad(t.incidenceDeg or -2.5),
			alphaStall = rad(17), stallWidth = rad(5),
			cd0 = 0.008, cm0 = 0, chord = t.chord,
		},
		{
			name = "Fin", component = "VerticalStab", role = "vstab", side = 0,
			pos = f.pos, normal = { 1, 0, 0 },
			area = f.area, aspect = f.aspect or 1.6, oswald = 0.7,
			clAlpha = f.clAlpha or 2.8, cl0 = 0.0, incidence = 0,
			alphaStall = rad(20), stallWidth = rad(6),
			cd0 = 0.008, cm0 = 0, chord = f.chord,
		},
	}
end

-- One landing-gear unit. Nose units steer; main units brake.
function Kit.gear(name: string, component: string, pos: { number }, o: any): any
	local nose = o.nose == true
	return {
		name = name, component = component,
		pos = pos, strutLength = o.strut, wheelRadius = o.wheel, travel = o.travel or o.strut * 0.3,
		staticCompression = o.staticCompression or 0.35, dampingRatio = o.damping or 0.7,
		steerMaxDeg = if nose then (o.steerDeg or 45) else 0, steerHighSpeedDeg = if nose then 6 else 0,
		brakes = not nose,
		retractAxis = o.retractAxis or "x", retractAngleDeg = o.retractDeg or (if nose then 95 else -85),
		wheels = o.wheels or 1, wheelSpacing = o.wheelSpacing or 0.3,
		fairing = o.fairing, legDiameter = o.leg, door = o.door, light = o.light, brace = o.brace,
	}
end

-- Damage component entry.
function Kit.comp(parent: string?, mass: number, threshold: number, destroy: number, ref: { number }, extra: any?): any
	local c: any = { parent = parent, mass = mass, impactThreshold = threshold, impactDestroy = destroy, detachable = parent ~= nil, ref = ref }
	if extra then
		for k, v in extra do
			c[k] = v
		end
	end
	return c
end

return Kit
