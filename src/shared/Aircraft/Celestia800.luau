--!strict
-- Celestia 800: original, unbranded four-engine full double-deck superjumbo. The biggest
-- aircraft in the game: enormous wing, gentle handling, long take-off roll. The fuselage
-- cross-section is a tall "stadium" (two circles joined by straight sides).
-- Same body axes and units as Meridian200.luau.

local rad = math.rad

local DIH = rad(5.6)

local config = {
	id = "celestia800",
	displayName = "Celestia 800",
	class = "Double-deck superjumbo",
	description = "Full double-deck superjumbo. The biggest wing in the game; long, gentle and stately.",
	unlocked = true,

	mass = 390000, -- kg, a light game weight including initial fuel
	inertia = { roll = 5.5e7, pitch = 8.8e7, yaw = 1.5e8 },

	fuel = { capacity = 250000, initial = 60000 },

	speeds = {
		rotate = 150,
		v2 = 160,
		approach = 145,
		vref = 140,
		cruise = 290,
		vmo = 340,
		flapLimits = { 999, 263, 222, 196, 182 },
		gearLimit = 250,
	},

	aero = {
		wingSpan = 79.8,
		wingArea = 845,
		meanChord = 11.0,
		panels = {
			{
				name = "LeftWing", component = "LeftWing", role = "wing", side = -1,
				pos = { -20.1, -1.0, 1.4 }, normal = { math.sin(DIH), math.cos(DIH), 0 },
				area = 422.5, aspect = 7.5, oswald = 0.82,
				clAlpha = 4.96, cl0 = 0.24, incidence = rad(2.0),
				alphaStall = rad(14.0), stallWidth = rad(4.0),
				cd0 = 0.0080, cm0 = -0.05, chord = 11.0,
			},
			{
				name = "RightWing", component = "RightWing", role = "wing", side = 1,
				pos = { 20.1, -1.0, 1.4 }, normal = { -math.sin(DIH), math.cos(DIH), 0 },
				area = 422.5, aspect = 7.5, oswald = 0.82,
				clAlpha = 4.96, cl0 = 0.24, incidence = rad(2.0),
				alphaStall = rad(14.0), stallWidth = rad(4.0),
				cd0 = 0.0080, cm0 = -0.05, chord = 11.0,
			},
			{
				name = "Tailplane", component = "HorizontalStab", role = "hstab", side = 0,
				pos = { 0, 2.0, 32.5 }, normal = { 0, 1, 0 },
				area = 230, aspect = 4.4, oswald = 0.75,
				clAlpha = 4.1 * 0.6, cl0 = 0.0, incidence = rad(-3.0),
				alphaStall = rad(17), stallWidth = rad(5),
				cd0 = 0.008, cm0 = 0, chord = 7.3,
			},
			{
				name = "Fin", component = "VerticalStab", role = "vstab", side = 0,
				pos = { 0, 10.0, 30.5 }, normal = { 1, 0, 0 },
				area = 123, aspect = 1.7, oswald = 0.70,
				clAlpha = 2.9, cl0 = 0.0, incidence = 0,
				alphaStall = rad(20), stallWidth = rad(6),
				cd0 = 0.008, cm0 = 0, chord = 10.0,
			},
		},
		bodyDrag = { x = 330, y = 280, z = 5.3 },
		bodyDragPos = { 0, 0, -2.0 },
		gearDragArea = 16,
		extraDamping = { roll = 10000, pitch = 50000, yaw = 62000 },
		elevator = { maxDeflection = rad(25), clPerRad = 1.7 },
		aileron = { maxDeflection = rad(20), clPerRad = 0.33 },
		rudder = { maxDeflection = rad(30), clPerRad = 1.4 },
		trim = { maxDeflection = rad(13) },
		flaps = {
			labels = { "UP", "1", "2", "3", "FULL" },
			deflectionDeg = { 0, 8, 17, 26, 33 },
			dCl = { 0, 0.30, 0.55, 0.82, 1.05 },
			dCd = { 0, 0.004, 0.012, 0.026, 0.046 },
			dStallDeg = { 0, 0.5, 0.5, 0, 0 },
			dCm = { 0, -0.02, -0.035, -0.05, -0.07 },
			travelTime = 3.5,
		},
		speedbrake = { dCl = -0.30, dCd = 0.035 },
		groundEffect = true,
	},

	engines = {
		{
			name = "LeftOuterEngine", component = "LeftOuterEngine",
			pos = { -26.0, -3.1, 0.6 }, axis = { 0, 0, -1 },
			maxThrust = 310000, idleN1 = 22, spoolUpTau = 3.0, spoolDownTau = 2.0,
			startTime = 15, reverseFraction = 0.35,
			fuelFlowIdle = 0.35, fuelFlowMax = 3.0,
		},
		{
			name = "LeftInnerEngine", component = "LeftInnerEngine",
			pos = { -15.0, -4.4, -6.6 }, axis = { 0, 0, -1 },
			maxThrust = 310000, idleN1 = 22, spoolUpTau = 3.0, spoolDownTau = 2.0,
			startTime = 15, reverseFraction = 0.35,
			fuelFlowIdle = 0.35, fuelFlowMax = 3.0,
		},
		{
			name = "RightInnerEngine", component = "RightInnerEngine",
			pos = { 15.0, -4.4, -6.6 }, axis = { 0, 0, -1 },
			maxThrust = 310000, idleN1 = 22, spoolUpTau = 3.0, spoolDownTau = 2.0,
			startTime = 15, reverseFraction = 0.35,
			fuelFlowIdle = 0.35, fuelFlowMax = 3.0,
		},
		{
			name = "RightOuterEngine", component = "RightOuterEngine",
			pos = { 26.0, -3.1, 0.6 }, axis = { 0, 0, -1 },
			maxThrust = 310000, idleN1 = 22, spoolUpTau = 3.0, spoolDownTau = 2.0,
			startTime = 15, reverseFraction = 0.35,
			fuelFlowIdle = 0.35, fuelFlowMax = 3.0,
		},
	},

	gear = {
		retractTime = 10,
		units = {
			{
				name = "NoseGear", component = "NoseGear",
				pos = { 0, -3.6, -28.0 }, strutLength = 2.62, wheelRadius = 0.62, travel = 0.45,
				staticCompression = 0.33, dampingRatio = 0.65,
				steerMaxDeg = 65, steerHighSpeedDeg = 6, brakes = false,
				retractAxis = "x", retractAngleDeg = 95, wheels = 2, wheelSpacing = 0.85,
			},
			{
				name = "LeftWingGear", component = "LeftWingGear",
				pos = { -6.1, -3.4, 1.8 }, strutLength = 2.75, wheelRadius = 0.7, travel = 0.55,
				staticCompression = 0.36, dampingRatio = 0.65,
				steerMaxDeg = 0, steerHighSpeedDeg = 0, brakes = true,
				retractAxis = "z", retractAngleDeg = 88, wheels = 2, wheelSpacing = 1.2, rows = 2, rowSpacing = 1.6,
			},
			{
				name = "RightWingGear", component = "RightWingGear",
				pos = { 6.1, -3.4, 1.8 }, strutLength = 2.75, wheelRadius = 0.7, travel = 0.55,
				staticCompression = 0.36, dampingRatio = 0.65,
				steerMaxDeg = 0, steerHighSpeedDeg = 0, brakes = true,
				retractAxis = "z", retractAngleDeg = -88, wheels = 2, wheelSpacing = 1.2, rows = 2, rowSpacing = 1.6,
			},
			{
				name = "LeftBodyGear", component = "LeftBodyGear",
				pos = { -2.0, -3.4, 5.0 }, strutLength = 2.75, wheelRadius = 0.7, travel = 0.55,
				staticCompression = 0.36, dampingRatio = 0.65,
				steerMaxDeg = 0, steerHighSpeedDeg = 0, brakes = true,
				retractAxis = "x", retractAngleDeg = -90, wheels = 2, wheelSpacing = 1.2, rows = 3, rowSpacing = 1.6,
			},
			{
				name = "RightBodyGear", component = "RightBodyGear",
				pos = { 2.0, -3.4, 5.0 }, strutLength = 2.75, wheelRadius = 0.7, travel = 0.55,
				staticCompression = 0.36, dampingRatio = 0.65,
				steerMaxDeg = 0, steerHighSpeedDeg = 0, brakes = true,
				retractAxis = "x", retractAngleDeg = -90, wheels = 2, wheelSpacing = 1.2, rows = 3, rowSpacing = 1.6,
			},
		},
		friction = { rolling = 0.02, brake = 0.55, lateral = 0.75 },
	},

	components = {
		Fuselage = { parent = nil, mass = 0, impactThreshold = 9, impactDestroy = 36, detachable = false, ref = { 0, -3.5, 0 } },
		ForwardFuselage = { parent = "Fuselage", mass = 36000, impactThreshold = 8, impactDestroy = 30, detachable = true, ref = { 0, -2.0, -23 } },
		AftFuselage = { parent = "Fuselage", mass = 28000, impactThreshold = 7, impactDestroy = 28, detachable = true, ref = { 0, -1.5, 24 } },
		LeftWing = { parent = "Fuselage", mass = 32000, impactThreshold = 6, impactDestroy = 22, detachable = true, ref = { -21, -1.0, 4 } },
		RightWing = { parent = "Fuselage", mass = 32000, impactThreshold = 6, impactDestroy = 22, detachable = true, ref = { 21, -1.0, 4 } },
		LeftInnerEngine = { parent = "LeftWing", mass = 6500, impactThreshold = 4, impactDestroy = 16, detachable = true, ref = { -15.0, -4.4, -6.6 } },
		LeftOuterEngine = { parent = "LeftWing", mass = 6500, impactThreshold = 4, impactDestroy = 16, detachable = true, ref = { -26.0, -3.1, 0.6 } },
		RightInnerEngine = { parent = "RightWing", mass = 6500, impactThreshold = 4, impactDestroy = 16, detachable = true, ref = { 15.0, -4.4, -6.6 } },
		RightOuterEngine = { parent = "RightWing", mass = 6500, impactThreshold = 4, impactDestroy = 16, detachable = true, ref = { 26.0, -3.1, 0.6 } },
		HorizontalStab = { parent = "AftFuselage", mass = 5000, impactThreshold = 5, impactDestroy = 18, detachable = true, ref = { 0, 2.0, 32.5 } },
		VerticalStab = { parent = "AftFuselage", mass = 4000, impactThreshold = 5, impactDestroy = 18, detachable = true, ref = { 0, 10.0, 30.5 } },
		NoseGear = { parent = "ForwardFuselage", mass = 1800, impactThreshold = 6, impactDestroy = 18, detachable = true, ref = { 0, -6.0, -28.0 }, gear = true },
		LeftWingGear = { parent = "LeftWing", mass = 4500, impactThreshold = 6, impactDestroy = 20, detachable = true, ref = { -6.1, -6.0, 1.8 }, gear = true },
		RightWingGear = { parent = "RightWing", mass = 4500, impactThreshold = 6, impactDestroy = 20, detachable = true, ref = { 6.1, -6.0, 1.8 }, gear = true },
		LeftBodyGear = { parent = "Fuselage", mass = 5500, impactThreshold = 6, impactDestroy = 20, detachable = true, ref = { -2.0, -6.0, 5.0 }, gear = true },
		RightBodyGear = { parent = "Fuselage", mass = 5500, impactThreshold = 6, impactDestroy = 20, detachable = true, ref = { 2.0, -6.0, 5.0 }, gear = true },
	},
	gearLimits = { sinkDegrade = 3.3, sinkFail = 4.8, sinkDetach = 6.5, sideSpeedFail = 9 },
	gLimit = 3.0,

	hullPoints = {
		{ 0, -4.2, -33, "ForwardFuselage" }, { 0, -4.2, -18, "ForwardFuselage" }, { 0, -4.2, 0, "Fuselage" },
		{ 0, -4.2, 14, "AftFuselage" }, { 0, -1.5, 32, "AftFuselage" },
		{ -39.5, 2.5, 17, "LeftWing" }, { 39.5, 2.5, 17, "RightWing" },
		{ -15.0, -5.9, -6.6, "LeftInnerEngine" }, { 15.0, -5.9, -6.6, "RightInnerEngine" },
		{ -26.0, -4.6, 0.6, "LeftOuterEngine" }, { 26.0, -4.6, 0.6, "RightOuterEngine" },
	},

	cameras = {
		cockpit = { -0.6, 1.0, -32.6 },
		chaseDistance = 135,
		chaseHeight = 28,
	},

	geometry = {
		fuselage = {
			radius = 3.55, deck = 1.3,
			noseZ = -36.5, cabinStartZ = -29.0, forwardSplitZ = -12.0, aftSplitZ = 12.0,
			cabinEndZ = 17.0, tailEndZ = 36.0, tailUpsweep = 3.0, noseDrop = 0.9,
			-- main deck (relative to the lower circle's centre), upper deck (upper circle's)
			windowRows = { -0.35, 1.6 }, windowPitch = 0.55, upperDeckStartZ = -27.0,
			doors = { -27.0, -16.0, -3.0, 8.5, 15.5 },
			windscreen = { at = 0.55 },
		},
		wing = {
			rootLE = { 3.8, -2.6, -11.2 }, rootChord = 17.5, tipChord = 4.0, span = 36.1,
			sweepDeg = 33.5, dihedralDeg = 5.6, rootThickness = 2.0, tipThickness = 0.45,
			aileronStart = 0.7, flapEnd = 0.58, controlChord = 0.22,
			wingletHeight = 1.4,
		},
		engine = { length = 7.2, radius = 1.5, kind = "turbofan" },
		hstab = {
			rootLE = { 1.8, 1.8, 27.8 }, rootChord = 11.0, tipChord = 3.6, span = 13.6,
			sweepDeg = 35, dihedralDeg = 6, thickness = 0.7, controlChord = 0.3,
		},
		vstab = {
			rootLE = { 0, 4.0, 23.5 }, rootChord = 14.0, tipChord = 4.5, height = 11.5,
			sweepDeg = 40, thickness = 0.7, controlChord = 0.3,
		},
		seat = { -0.6, 0.25, -32.3 },
		livery = {
			body = { 246, 247, 250 },
			belly = { 70, 80, 120 },
			stripe = { 70, 80, 160 },
			accent = { 120, 200, 255 },
			tail = { 40, 50, 120 },
			wing = { 205, 210, 218 },
			engine = { 236, 238, 244 },
			airline = "AURORA",
		},
	},
}

return config
