--!strict
-- Silverline 8: original, unbranded eight-seat business jet. Two engines on the rear
-- fuselage, T-tail, swept wing with winglets and a row of oval windows.
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
	id = "silverline8",
	displayName = "Silverline 8",
	class = "Business jet",
	description = "Sleek private jet with engines at the back. Fast, quiet and smooth.",
	unlocked = true,
	seats = 8,
	difficulty = 2,
	minRunwayM = 1400,
	handling = "light",
	soundProfile = "jet",

	mass = 9000,
	inertia = { roll = 3.5e4, pitch = 7.0e4, yaw = 1.0e5 },
	fuel = { capacity = 2400, initial = 1400 },

	speeds = {
		rotate = 110, v2 = 120, approach = 122, vref = 114, cruise = 290, vmo = 340,
		flapLimits = { 999, 200, 180, 160 }, gearLimit = 200,
	},

	aero = {
		wingSpan = 15.5,
		wingArea = 30,
		meanChord = 2.0,
		panels = Kit.panels(
			{ area = 30, x = 3.4, y = -0.45, z = 0.08, dihedralDeg = 3, aspect = 8, clAlpha = 5.0, cl0 = 0.22, incidenceDeg = 2.0, stallDeg = 15, cd0 = 0.009, chord = 2.0 },
			{ area = 6.4, pos = { 0, 3.0, 7.95 }, clAlpha = 4.3, incidenceDeg = -2.5, chord = 1.25, downwash = 0.75 },
			{ area = 4.6, pos = { 0, 1.9, 6.9 }, aspect = 1.5, clAlpha = 2.8, chord = 2.0 }
		),
		bodyDrag = { x = 25, y = 30, z = 0.55 },
		bodyDragPos = { 0, 0, -0.3 },
		gearDragArea = 0.8,
		extraDamping = { roll = 9, pitch = 37, yaw = 48 },
		elevator = { maxDeflection = rad(25), clPerRad = 1.8 },
		aileron = { maxDeflection = rad(20), clPerRad = 0.25 },
		rudder = { maxDeflection = rad(30), clPerRad = 1.4 },
		trim = { maxDeflection = rad(13) },
		flaps = {
			labels = { "UP", "8", "20", "40" },
			deflectionDeg = { 0, 8, 20, 40 },
			dCl = { 0, 0.2, 0.42, 0.65 },
			dCd = { 0, 0.005, 0.016, 0.04 },
			dStallDeg = { 0, 0, -0.5, -1.5 },
			dCm = { 0, -0.02, -0.035, -0.06 },
			travelTime = 2.0,
		},
		speedbrake = { dCl = -0.2, dCd = 0.03 },
		groundEffect = true,
	},

	engines = {
		{
			name = "LeftEngine", component = "LeftEngine",
			pos = { -1.6, 0.45, 4.4 }, axis = { 0, 0, -1 },
			maxThrust = 20000, idleN1 = 22, spoolUpTau = 1.8, spoolDownTau = 1.2,
			startTime = 8, reverseFraction = 0.35,
			fuelFlowIdle = 0.03, fuelFlowMax = 0.25,
		},
		{
			name = "RightEngine", component = "RightEngine",
			pos = { 1.6, 0.45, 4.4 }, axis = { 0, 0, -1 },
			maxThrust = 20000, idleN1 = 22, spoolUpTau = 1.8, spoolDownTau = 1.2,
			startTime = 8, reverseFraction = 0.35,
			fuelFlowIdle = 0.03, fuelFlowMax = 0.25,
		},
	},

	gear = {
		retractTime = 5,
		units = {
			Kit.gear("NoseGear", "NoseGear", { 0, -0.7, -5.0 }, { nose = true, strut = 0.85, wheel = 0.25, travel = 0.22, steerDeg = 55, wheels = 2, wheelSpacing = 0.3 }),
			Kit.gear("LeftMainGear", "LeftMainGear", { -1.6, -0.7, 0.45 }, { strut = 0.8, wheel = 0.3, travel = 0.25 }),
			Kit.gear("RightMainGear", "RightMainGear", { 1.6, -0.7, 0.45 }, { strut = 0.8, wheel = 0.3, travel = 0.25 }),
		},
		friction = { rolling = 0.02, brake = 0.55, lateral = 0.75 },
	},

	components = {
		Fuselage = Kit.comp(nil, 0, 8, 32, { 0, -0.6, 0 }),
		ForwardFuselage = Kit.comp("Fuselage", 900, 7, 27, { 0, -0.5, -5 }),
		AftFuselage = Kit.comp("Fuselage", 700, 6, 25, { 0, -0.2, 6 }),
		LeftWing = Kit.comp("Fuselage", 700, 6, 21, { -4, -0.45, 0.5 }),
		RightWing = Kit.comp("Fuselage", 700, 6, 21, { 4, -0.45, 0.5 }),
		LeftEngine = Kit.comp("AftFuselage", 400, 4, 15, { -1.6, 0.45, 4.4 }),
		RightEngine = Kit.comp("AftFuselage", 400, 4, 15, { 1.6, 0.45, 4.4 }),
		VerticalStab = Kit.comp("AftFuselage", 120, 5, 17, { 0, 1.9, 6.9 }),
		HorizontalStab = Kit.comp("VerticalStab", 100, 5, 17, { 0, 3.0, 7.95 }),
		NoseGear = Kit.comp("ForwardFuselage", 60, 6, 17, { 0, -1.5, -5.0 }, { gear = true }),
		LeftMainGear = Kit.comp("LeftWing", 150, 6, 19, { -1.6, -1.6, 0.45 }, { gear = true }),
		RightMainGear = Kit.comp("RightWing", 150, 6, 19, { 1.6, -1.6, 0.45 }, { gear = true }),
	},
	gearLimits = { sinkDegrade = 3.3, sinkFail = 4.8, sinkDetach = 6.5, sideSpeedFail = 8 },
	gLimit = 3.8,

	hullPoints = {
		{ 0, -0.85, -6.0, "ForwardFuselage" }, { 0, -0.85, -2.0, "ForwardFuselage" }, { 0, -0.85, 1.0, "Fuselage" },
		{ 0, -0.6, 4.0, "AftFuselage" }, { 0, 0.1, 8.2, "AftFuselage" },
		{ -7.75, -0.1, 1.5, "LeftWing" }, { 7.75, -0.1, 1.5, "RightWing" },
		{ -1.6, -0.03, 4.4, "LeftEngine" }, { 1.6, -0.03, 4.4, "RightEngine" },
	},

	cameras = {
		cockpit = { -0.4, 0.32, -5.9 },
		chaseDistance = 30,
		chaseHeight = 6,
	},

	geometry = {
		fuselage = {
			radius = 0.88,
			noseZ = -7.8, cabinStartZ = -5.5, forwardSplitZ = -3.0, aftSplitZ = 3.0,
			cabinEndZ = 4.2, tailEndZ = 8.6, tailUpsweep = 0.45, noseDrop = 0.25, tailTipFraction = 0.2,
			windowRows = { 0.12 }, windowPitch = 0.85, windowWidth = 0.32, windowHeight = 0.5,
			windowStartZ = -3.0, windowEndZ = 2.6, doors = { -4.4 },
			windscreen = { yLow = 0.22, yHigh = 0.66 },
			apu = false,
		},
		wing = {
			mount = "low",
			rootLE = { 0.75, -0.55, -1.4 }, rootChord = 2.8, tipChord = 1.05, span = 7.0,
			sweepDeg = 15, dihedralDeg = 3, rootThickness = 0.32, tipThickness = 0.12,
			aileronStart = 0.68, flapEnd = 0.6, controlChord = 0.25,
			wingletHeight = 1.0,
		},
		engine = { kind = "turbofan", mount = "fuselage", length = 2.6, radius = 0.48, fanBlades = 12 },
		hstab = {
			rootLE = { 0.15, 3.0, 7.35 }, rootChord = 1.6, tipChord = 0.9, span = 2.9,
			sweepDeg = 25, dihedralDeg = 0, thickness = 0.14, controlChord = 0.32,
		},
		vstab = {
			rootLE = { 0, 0.75, 5.5 }, rootChord = 2.4, tipChord = 1.6, height = 2.3,
			sweepDeg = 40, thickness = 0.18, controlChord = 0.3,
		},
		cockpit = { seats = 2, halfWidth = 0.75, panelDistance = 1.0 },
		seat = { -0.4, -0.4, -5.8 },
		livery = {
			body = { 250, 250, 252 },
			belly = { 70, 74, 84 },
			stripe = { 150, 154, 164 },
			accent = { 200, 170, 90 },
			tail = { 60, 64, 76 },
			wing = { 214, 216, 222 },
			engine = { 240, 240, 244 },
			code = "SILVERLINE",
		},
	},
}

return config
