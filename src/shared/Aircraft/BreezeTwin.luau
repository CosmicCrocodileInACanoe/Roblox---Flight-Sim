--!strict
-- Breeze Twin: original, unbranded six-seat light twin (low wing, two wing-mounted
-- propeller engines, retractable gear, cabin windows). Steady, with a spare engine.
-- Body axes: x = right wing, y = up, z = toward the tail (nose -z), origin at the CoM.

local function req(name: string): any
	if script then
		return (require :: any)((script :: any).Parent[name])
	end
	return (require :: any)("./" .. name)
end
local Kit = req("Kit")
local rad = math.rad

local function engine(side: number): any
	return {
		name = if side < 0 then "LeftEngine" else "RightEngine",
		component = if side < 0 then "LeftEngine" else "RightEngine",
		pos = { side * 2.15, -0.15, -1.1 }, axis = { 0, 0, -1 },
		maxThrust = 3600, idleN1 = 25, spoolUpTau = 0.9, spoolDownTau = 0.7,
		startTime = 4, reverseFraction = 0, lapseSpeed = 280,
		fuelFlowIdle = 0.004, fuelFlowMax = 0.016,
	}
end

local config = {
	id = "breezetwin",
	displayName = "Breeze Twin",
	class = "Light twin",
	description = "Six-seat plane with two propellers, one on each wing. Smooth, quick and safe.",
	unlocked = true,
	seats = 6,
	difficulty = 2,
	minRunwayM = 800,
	handling = "light",
	soundProfile = "prop",

	mass = 2300,
	inertia = { roll = 5500, pitch = 6500, yaw = 11000 },
	fuel = { capacity = 400, initial = 260 },

	speeds = {
		rotate = 75, v2 = 85, approach = 90, vref = 82, cruise = 170, vmo = 210,
		flapLimits = { 999, 150, 130 }, gearLimit = 150,
	},

	aero = {
		wingSpan = 12.0,
		wingArea = 18.5,
		meanChord = 1.6,
		panels = Kit.panels(
			{ area = 18.5, x = 3.0, y = -0.45, z = 0.12, dihedralDeg = 5, aspect = 7.8, clAlpha = 4.9, cl0 = 0.25, incidenceDeg = 1.5, stallDeg = 15, cd0 = 0.011, chord = 1.6 },
			{ area = 4.6, pos = { 0, 0.1, 5.3 }, clAlpha = 3.8, incidenceDeg = -2.0, chord = 1.1 },
			{ area = 2.6, pos = { 0, 1.0, 5.2 }, aspect = 1.5, clAlpha = 2.6, chord = 1.3 }
		),
		bodyDrag = { x = 8, y = 10, z = 0.38 },
		bodyDragPos = { 0, 0, -0.4 },
		gearDragArea = 0.2,
		extraDamping = { roll = 0.6, pitch = 2.5, yaw = 3 },
		elevator = { maxDeflection = rad(25), clPerRad = 2.4 },
		aileron = { maxDeflection = rad(20), clPerRad = 0.5 },
		rudder = { maxDeflection = rad(28), clPerRad = 1.5 },
		trim = { maxDeflection = rad(12) },
		flaps = {
			labels = { "UP", "APP", "DOWN" },
			deflectionDeg = { 0, 15, 30 },
			dCl = { 0, 0.3, 0.6 },
			dCd = { 0, 0.01, 0.035 },
			dStallDeg = { 0, -1, -2 },
			dCm = { 0, -0.02, -0.04 },
			travelTime = 2.0,
		},
		speedbrake = { dCl = 0, dCd = 0.02 },
		groundEffect = true,
	},

	engines = { engine(-1), engine(1) },

	gear = {
		retractTime = 4,
		units = {
			Kit.gear("NoseGear", "NoseGear", { 0, -0.8, -2.9 }, { nose = true, strut = 0.55, wheel = 0.2, travel = 0.15, steerDeg = 35, leg = 0.08 }),
			Kit.gear("LeftMainGear", "LeftMainGear", { -2.15, -0.75, 0.4 }, { strut = 0.6, wheel = 0.25, travel = 0.16, leg = 0.09 }),
			Kit.gear("RightMainGear", "RightMainGear", { 2.15, -0.75, 0.4 }, { strut = 0.6, wheel = 0.25, travel = 0.16, leg = 0.09 }),
		},
		friction = { rolling = 0.02, brake = 0.5, lateral = 0.8 },
	},

	components = {
		Fuselage = Kit.comp(nil, 0, 8, 32, { 0, -0.2, 0 }),
		ForwardFuselage = Kit.comp("Fuselage", 120, 7, 27, { 0, -0.1, -2.6 }),
		AftFuselage = Kit.comp("Fuselage", 90, 6, 25, { 0, 0, 3.6 }),
		LeftWing = Kit.comp("Fuselage", 150, 6, 21, { -3.2, -0.45, 0.2 }),
		RightWing = Kit.comp("Fuselage", 150, 6, 21, { 3.2, -0.45, 0.2 }),
		LeftEngine = Kit.comp("LeftWing", 190, 5, 18, { -2.15, -0.15, -0.9 }),
		RightEngine = Kit.comp("RightWing", 190, 5, 18, { 2.15, -0.15, -0.9 }),
		VerticalStab = Kit.comp("AftFuselage", 18, 5, 17, { 0, 1.0, 5.2 }),
		HorizontalStab = Kit.comp("AftFuselage", 22, 5, 17, { 0, 0.1, 5.3 }),
		NoseGear = Kit.comp("ForwardFuselage", 15, 6, 17, { 0, -1.3, -2.9 }, { gear = true }),
		LeftMainGear = Kit.comp("LeftWing", 25, 6, 19, { -2.15, -1.3, 0.4 }, { gear = true }),
		RightMainGear = Kit.comp("RightWing", 25, 6, 19, { 2.15, -1.3, 0.4 }, { gear = true }),
	},
	gearLimits = { sinkDegrade = 3.3, sinkFail = 4.8, sinkDetach = 6.5, sideSpeedFail = 7 },
	gLimit = 3.8,

	hullPoints = {
		{ 0, -0.75, -2.8, "ForwardFuselage" }, { 0, -0.75, 0, "Fuselage" }, { 0, -0.5, 3.4, "AftFuselage" },
		{ 0, -0.15, 6.0, "AftFuselage" },
		{ -6.0, -0.2, 0.4, "LeftWing" }, { 6.0, -0.2, 0.4, "RightWing" },
		{ -2.15, -0.55, -1.6, "LeftEngine" }, { 2.15, -0.55, -1.6, "RightEngine" },
	},

	cameras = {
		cockpit = { -0.3, 0.42, -1.4 },
		chaseDistance = 17,
		chaseHeight = 4,
	},

	geometry = {
		fuselage = {
			radius = 0.66, deck = 0.3,
			noseZ = -4.9, cabinStartZ = -2.5, forwardSplitZ = -1.6, aftSplitZ = 1.8,
			cabinEndZ = 2.4, tailEndZ = 6.4, tailUpsweep = 0.35, noseDrop = 0.2, tailTipFraction = 0.22,
			windowRows = {}, doors = {}, apu = false, bellyFairing = false,
			windscreen = { yLow = 0.32, yHigh = 0.7, panes = { 2, 34, 64 } },
			cabin = {
				sideWindows = { { -1.95, -1.25, 0.08, 0.5 }, { -0.95, -0.25, 0.08, 0.5 }, { 0.05, 0.75, 0.08, 0.5 }, { 1.05, 1.6, 0.1, 0.45 } },
			},
		},
		wing = {
			mount = "low",
			rootLE = { 0.6, -0.5, -0.7 }, rootChord = 1.9, tipChord = 1.1, span = 5.4,
			sweepDeg = 2, dihedralDeg = 5, rootThickness = 0.24, tipThickness = 0.12,
			aileronStart = 0.68, flapEnd = 0.6, controlChord = 0.26, spoilers = false,
			wingletHeight = 0,
		},
		engine = { kind = "turboprop", length = 2.2, radius = 0.36, propRadius = 0.95, blades = 3 },
		hstab = {
			rootLE = { 0.25, 0.08, 4.85 }, rootChord = 1.25, tipChord = 0.8, span = 2.0,
			sweepDeg = 6, dihedralDeg = 6, thickness = 0.1, controlChord = 0.38,
		},
		vstab = {
			rootLE = { 0, 0.55, 4.3 }, rootChord = 1.7, tipChord = 0.85, height = 1.5,
			sweepDeg = 38, thickness = 0.13, controlChord = 0.36,
		},
		cockpit = { style = "cabin", halfWidth = 0.6, seats = 2, panel = "gauges", screens = 6, panelDistance = 0.95 },
		seat = { -0.3, -0.38, -1.3 },
		livery = {
			body = { 248, 248, 246 },
			belly = { 30, 60, 110 },
			stripe = { 30, 60, 110 },
			accent = { 90, 170, 220 },
			tail = { 30, 60, 110 },
			hstab = { 248, 248, 246 },
			wing = { 244, 244, 242 },
			engine = { 248, 248, 246 },
			code = "BZ-TWN",
		},
	},
}

return config
