--!strict
-- Bumble: original, unbranded vintage-style two-seat biplane (two wings joined by
-- struts and wires, open cockpit behind a small windscreen, two-blade propeller).
-- Slow, draggy and very forgiving.
-- Body axes: x = right wing, y = up, z = toward the tail (nose -z), origin at the CoM.

local function req(name: string): any
	if script then
		return (require :: any)((script :: any).Parent[name])
	end
	return (require :: any)("./" .. name)
end
local Kit = req("Kit")
local rad = math.rad

local config = {
	id = "bumble",
	displayName = "Bumble",
	class = "Vintage biplane",
	description = "Old-time biplane with two wings and an open cockpit. Slow, wobbly fun.",
	unlocked = true,
	seats = 2,
	difficulty = 1,
	minRunwayM = 400,
	handling = "light",
	soundProfile = "prop",
	assist = { easyBankDeg = 50, easyPitchUpDeg = 18, easyPitchDownDeg = -16, easyPitchRateDeg = 9 },

	mass = 780,
	inertia = { roll = 900, pitch = 1300, yaw = 2000 },
	fuel = { capacity = 90, initial = 70 },

	speeds = {
		rotate = 42, v2 = 48, approach = 52, vref = 47, cruise = 85, vmo = 120,
		flapLimits = { 999, 70 }, gearLimit = 999,
	},

	aero = {
		wingSpan = 8.6,
		wingArea = 19,
		meanChord = 1.3,
		panels = Kit.panels(
			{ area = 19, x = 2.0, y = 0.35, z = 0.08, dihedralDeg = 1.5, aspect = 5, oswald = 0.7, clAlpha = 4.2, cl0 = 0.3, incidenceDeg = 2, stallDeg = 15, cd0 = 0.03, chord = 1.3 },
			{ area = 2.8, pos = { 0, 0.2, 4.2 }, clAlpha = 3.6, incidenceDeg = -2.0, chord = 0.9 },
			{ area = 1.5, pos = { 0, 0.8, 4.35 }, aspect = 1.3, clAlpha = 2.6, chord = 1.0 }
		),
		bodyDrag = { x = 5, y = 6, z = 0.6 },
		bodyDragPos = { 0, 0.2, -0.3 },
		gearDragArea = 0.15,
		extraDamping = { roll = 0.5, pitch = 2, yaw = 2.5 },
		elevator = { maxDeflection = rad(28), clPerRad = 2.4 },
		aileron = { maxDeflection = rad(20), clPerRad = 0.5 },
		rudder = { maxDeflection = rad(30), clPerRad = 1.4 },
		trim = { maxDeflection = rad(12) },
		flaps = {
			labels = { "UP", "DOWN" },
			deflectionDeg = { 0, 15 },
			dCl = { 0, 0.2 },
			dCd = { 0, 0.02 },
			dStallDeg = { 0, -1 },
			dCm = { 0, -0.02 },
			travelTime = 1.5,
		},
		speedbrake = { dCl = 0, dCd = 0.02 },
		groundEffect = true,
	},

	engines = {
		{
			name = "Engine", component = "Engine",
			pos = { 0, 0.05, -2.55 }, axis = { 0, 0, -1 },
			maxThrust = 3400, idleN1 = 25, spoolUpTau = 0.8, spoolDownTau = 0.6,
			startTime = 3, reverseFraction = 0, lapseSpeed = 220,
			fuelFlowIdle = 0.003, fuelFlowMax = 0.012,
		},
	},

	gear = {
		fixed = true,
		retractTime = 1,
		units = {
			Kit.gear("NoseGear", "NoseGear", { 0, -0.74, -1.85 }, { nose = true, strut = 0.45, wheel = 0.2, travel = 0.13, steerDeg = 30, leg = 0.06 }),
			Kit.gear("LeftMainGear", "LeftMainGear", { -0.85, -0.6, 0.4 }, { brace = { -0.3, -0.45, 0.4 }, strut = 0.5, wheel = 0.28, travel = 0.13, leg = 0.06 }),
			Kit.gear("RightMainGear", "RightMainGear", { 0.85, -0.6, 0.4 }, { brace = { 0.3, -0.45, 0.4 }, strut = 0.5, wheel = 0.28, travel = 0.13, leg = 0.06 }),
		},
		friction = { rolling = 0.03, brake = 0.45, lateral = 0.8 },
	},

	components = {
		Fuselage = Kit.comp(nil, 0, 8, 32, { 0, -0.2, 0 }),
		ForwardFuselage = Kit.comp("Fuselage", 90, 7, 27, { 0, -0.1, -1.4 }),
		AftFuselage = Kit.comp("Fuselage", 40, 6, 25, { 0, 0, 3.0 }),
		LeftWing = Kit.comp("Fuselage", 70, 6, 21, { -2.4, 0.35, 0 }),
		RightWing = Kit.comp("Fuselage", 70, 6, 21, { 2.4, 0.35, 0 }),
		Engine = Kit.comp("ForwardFuselage", 140, 5, 18, { 0, 0.05, -2.2 }),
		VerticalStab = Kit.comp("AftFuselage", 8, 5, 17, { 0, 0.8, 4.35 }),
		HorizontalStab = Kit.comp("AftFuselage", 10, 5, 17, { 0, 0.2, 4.2 }),
		NoseGear = Kit.comp("ForwardFuselage", 8, 6, 17, { 0, -0.95, -1.85 }, { gear = true }),
		LeftMainGear = Kit.comp("Fuselage", 12, 6, 19, { -0.85, -1.0, 0.4 }, { gear = true }),
		RightMainGear = Kit.comp("Fuselage", 12, 6, 19, { 0.85, -1.0, 0.4 }, { gear = true }),
	},
	gearLimits = { sinkDegrade = 3.3, sinkFail = 4.8, sinkDetach = 6.5, sideSpeedFail = 7 },
	gLimit = 5,

	hullPoints = {
		{ 0, -0.55, -1.8, "ForwardFuselage" }, { 0, -0.55, 0, "Fuselage" }, { 0, -0.35, 2.8, "AftFuselage" },
		{ 0, 0.0, 4.9, "AftFuselage" },
		{ -4.0, -0.25, 0.0, "LeftWing" }, { 4.0, -0.25, 0.0, "RightWing" },
		{ -4.3, 1.15, -0.2, "LeftWing" }, { 4.3, 1.15, -0.2, "RightWing" },
		{ 0, -0.3, -2.4, "Engine" },
	},

	cameras = {
		cockpit = { 0, 0.62, 0.45 },
		chaseDistance = 13,
		chaseHeight = 3,
	},

	geometry = {
		fuselage = {
			radius = 0.5, halfWidth = 0.46,
			noseZ = -2.5, cabinStartZ = -1.4, forwardSplitZ = -0.3, aftSplitZ = 1.3,
			cabinEndZ = 1.7, tailEndZ = 5.0, tailUpsweep = 0.25, noseDrop = 0.0, tailTipFraction = 0.22,
			windowRows = {}, doors = {}, windscreen = false, apu = false, bellyFairing = false,
			-- open cockpit: a low glass windscreen with a brass frame and the pilot's head behind it
			canopy = { z0 = -0.25, z1 = 0.2, y = 0.42, halfWidth = 0.3, height = 0.24, frames = {}, frameColor = { 200, 160, 60 }, pilots = { { 0, 0.62, 0.45 } } },
		},
		wing = {
			mount = "low",
			rootLE = { 0.42, -0.3, -0.55 }, rootChord = 1.3, tipChord = 1.3, span = 3.6,
			sweepDeg = 0, dihedralDeg = 2, rootThickness = 0.13, tipThickness = 0.11,
			aileronStart = 0.6, flapEnd = 0.35, controlChord = 0.25, spoilers = false,
			wingletHeight = 0,
			upper = { rootLE = { 0.35, 1.05, -0.85 }, rootChord = 1.3, tipChord = 1.3, span = 3.95, sweepDeg = 4, dihedralDeg = 0, thickness = 0.13, strutAt = 0.78 },
		},
		engine = { kind = "piston", spinnerRadius = 0.15, spinnerLength = 0.24, propRadius = 1.0, blades = 2, exhaustZ = 0.9, bladeChord = 0.15, spinnerColor = { 200, 160, 60 } },
		hstab = {
			rootLE = { 0.2, 0.15, 3.85 }, rootChord = 0.95, tipChord = 0.7, span = 1.4,
			sweepDeg = 5, dihedralDeg = 0, thickness = 0.08, controlChord = 0.45,
		},
		vstab = {
			rootLE = { 0, 0.35, 3.75 }, rootChord = 1.1, tipChord = 0.65, height = 1.05,
			sweepDeg = 28, thickness = 0.09, controlChord = 0.5,
		},
		cockpit = { style = "canopy", panel = "gauges", screens = 4, halfWidth = 0.4, panelDistance = 0.6 },
		seat = { 0, -0.13, 0.55 },
		livery = {
			body = { 245, 196, 40 },
			belly = { 245, 196, 40 },
			stripe = { 40, 40, 44 },
			accent = { 40, 40, 44 },
			tail = { 40, 40, 44 },
			hstab = { 245, 196, 40 },
			wing = { 245, 196, 40 },
			wingStripe = { 40, 40, 44 },
			strut = { 110, 70, 40 },
			engine = { 190, 192, 196 },
			code = "BUMBLE",
		},
	},
}

return config
