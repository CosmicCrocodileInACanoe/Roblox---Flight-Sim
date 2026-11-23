--!strict
-- Atlas 400: original, unbranded four-engine wide-body jumbo with an upper-deck hump
-- (the classic "jumbo jet" layout). Heavy, slow to respond, very stable; needs long
-- runways and early planning. Same body axes and units as Meridian200.luau.

local rad = math.rad

local DIH = rad(7)

local config = {
	id = "atlas400",
	displayName = "Atlas 400",
	class = "Four-engine jumbo",
	description = "Four-engine jumbo with the upper-deck hump. Heavy and stable; plan descents early.",
	unlocked = true,

	mass = 280000, -- kg, a light game weight including initial fuel
	inertia = { roll = 2.5e7, pitch = 5.8e7, yaw = 8.0e7 },

	fuel = { capacity = 160000, initial = 40000 },

	speeds = {
		rotate = 155,
		v2 = 165,
		approach = 155,
		vref = 148,
		cruise = 290,
		vmo = 365,
		flapLimits = { 999, 250, 230, 200, 180 },
		gearLimit = 270,
	},

	aero = {
		wingSpan = 64.4,
		wingArea = 520,
		meanChord = 8.3,
		panels = {
			{
				name = "LeftWing", component = "LeftWing", role = "wing", side = -1,
				pos = { -14.4, -0.2, 1.1 }, normal = { math.sin(DIH), math.cos(DIH), 0 },
				area = 260, aspect = 7.9, oswald = 0.80,
				clAlpha = 5.01, cl0 = 0.22, incidence = rad(2.0),
				alphaStall = rad(14.0), stallWidth = rad(4.0),
				cd0 = 0.0080, cm0 = -0.05, chord = 8.3,
			},
			{
				name = "RightWing", component = "RightWing", role = "wing", side = 1,
				pos = { 14.4, -0.2, 1.1 }, normal = { -math.sin(DIH), math.cos(DIH), 0 },
				area = 260, aspect = 7.9, oswald = 0.80,
				clAlpha = 5.01, cl0 = 0.22, incidence = rad(2.0),
				alphaStall = rad(14.0), stallWidth = rad(4.0),
				cd0 = 0.0080, cm0 = -0.05, chord = 8.3,
			},
			{
				name = "Tailplane", component = "HorizontalStab", role = "hstab", side = 0,
				pos = { 0, 1.6, 30.5 }, normal = { 0, 1, 0 },
				area = 136, aspect = 3.6, oswald = 0.75,
				clAlpha = 3.9 * 0.6, cl0 = 0.0, incidence = rad(-3.0),
				alphaStall = rad(17), stallWidth = rad(5),
				cd0 = 0.008, cm0 = 0, chord = 6.2,
			},
			{
				name = "Fin", component = "VerticalStab", role = "vstab", side = 0,
				pos = { 0, 8.0, 28.5 }, normal = { 1, 0, 0 },
				area = 77, aspect = 1.6, oswald = 0.70,
				clAlpha = 2.8, cl0 = 0.0, incidence = 0,
				alphaStall = rad(20), stallWidth = rad(6),
				cd0 = 0.008, cm0 = 0, chord = 8.5,
			},
		},
		bodyDrag = { x = 240, y = 225, z = 3.6 },
		bodyDragPos = { 0, 0, -2.0 },
		gearDragArea = 12,
		extraDamping = { roll = 6000, pitch = 30000, yaw = 38000 },
		elevator = { maxDeflection = rad(25), clPerRad = 1.7 },
		aileron = { maxDeflection = rad(20), clPerRad = 0.33 },
		rudder = { maxDeflection = rad(30), clPerRad = 1.4 },
		trim = { maxDeflection = rad(13) },
		flaps = {
			labels = { "UP", "5", "10", "20", "30" },
			deflectionDeg = { 0, 5, 10, 20, 30 },
			dCl = { 0, 0.30, 0.55, 0.85, 1.10 },
			dCd = { 0, 0.004, 0.012, 0.028, 0.050 },
			dStallDeg = { 0, 0.5, 0.5, 0, -0.5 },
			dCm = { 0, -0.02, -0.035, -0.05, -0.07 },
			travelTime = 3.5,
		},
		speedbrake = { dCl = -0.30, dCd = 0.035 },
		groundEffect = true,
	},

	engines = {
		{
			name = "LeftOuterEngine", component = "LeftOuterEngine",
			pos = { -21.0, -2.0, 0.9 }, axis = { 0, 0, -1 },
			maxThrust = 250000, idleN1 = 22, spoolUpTau = 2.8, spoolDownTau = 1.8,
			startTime = 14, reverseFraction = 0.4,
			fuelFlowIdle = 0.3, fuelFlowMax = 2.6,
		},
		{
			name = "LeftInnerEngine", component = "LeftInnerEngine",
			pos = { -12.0, -3.3, -6.2 }, axis = { 0, 0, -1 },
			maxThrust = 250000, idleN1 = 22, spoolUpTau = 2.8, spoolDownTau = 1.8,
			startTime = 14, reverseFraction = 0.4,
			fuelFlowIdle = 0.3, fuelFlowMax = 2.6,
		},
		{
			name = "RightInnerEngine", component = "RightInnerEngine",
			pos = { 12.0, -3.3, -6.2 }, axis = { 0, 0, -1 },
			maxThrust = 250000, idleN1 = 22, spoolUpTau = 2.8, spoolDownTau = 1.8,
			startTime = 14, reverseFraction = 0.4,
			fuelFlowIdle = 0.3, fuelFlowMax = 2.6,
		},
		{
			name = "RightOuterEngine", component = "RightOuterEngine",
			pos = { 21.0, -2.0, 0.9 }, axis = { 0, 0, -1 },
			maxThrust = 250000, idleN1 = 22, spoolUpTau = 2.8, spoolDownTau = 1.8,
			startTime = 14, reverseFraction = 0.4,
			fuelFlowIdle = 0.3, fuelFlowMax = 2.6,
		},
	},

	gear = {
		retractTime = 9,
		units = {
			{
				name = "NoseGear", component = "NoseGear",
				pos = { 0, -2.6, -26.0 }, strutLength = 2.62, wheelRadius = 0.6, travel = 0.45,
				staticCompression = 0.33, dampingRatio = 0.65,
				steerMaxDeg = 65, steerHighSpeedDeg = 6, brakes = false,
				retractAxis = "x", retractAngleDeg = 95, wheels = 2, wheelSpacing = 0.8,
			},
			{
				name = "LeftWingGear", component = "LeftWingGear",
				pos = { -5.8, -2.4, 1.6 }, strutLength = 2.85, wheelRadius = 0.62, travel = 0.55,
				staticCompression = 0.36, dampingRatio = 0.65,
				steerMaxDeg = 0, steerHighSpeedDeg = 0, brakes = true,
				retractAxis = "z", retractAngleDeg = 88, wheels = 2, wheelSpacing = 1.1, rows = 2, rowSpacing = 1.5,
			},
			{
				name = "RightWingGear", component = "RightWingGear",
				pos = { 5.8, -2.4, 1.6 }, strutLength = 2.85, wheelRadius = 0.62, travel = 0.55,
				staticCompression = 0.36, dampingRatio = 0.65,
				steerMaxDeg = 0, steerHighSpeedDeg = 0, brakes = true,
				retractAxis = "z", retractAngleDeg = -88, wheels = 2, wheelSpacing = 1.1, rows = 2, rowSpacing = 1.5,
			},
			{
				name = "LeftBodyGear", component = "LeftBodyGear",
				pos = { -1.9, -2.4, 4.6 }, strutLength = 2.85, wheelRadius = 0.62, travel = 0.55,
				staticCompression = 0.36, dampingRatio = 0.65,
				steerMaxDeg = 0, steerHighSpeedDeg = 0, brakes = true,
				retractAxis = "x", retractAngleDeg = -90, wheels = 2, wheelSpacing = 1.1, rows = 2, rowSpacing = 1.5,
			},
			{
				name = "RightBodyGear", component = "RightBodyGear",
				pos = { 1.9, -2.4, 4.6 }, strutLength = 2.85, wheelRadius = 0.62, travel = 0.55,
				staticCompression = 0.36, dampingRatio = 0.65,
				steerMaxDeg = 0, steerHighSpeedDeg = 0, brakes = true,
				retractAxis = "x", retractAngleDeg = -90, wheels = 2, wheelSpacing = 1.1, rows = 2, rowSpacing = 1.5,
			},
		},
		friction = { rolling = 0.02, brake = 0.55, lateral = 0.75 },
	},

	components = {
		Fuselage = { parent = nil, mass = 0, impactThreshold = 9, impactDestroy = 36, detachable = false, ref = { 0, -2.5, 0 } },
		ForwardFuselage = { parent = "Fuselage", mass = 26000, impactThreshold = 8, impactDestroy = 30, detachable = true, ref = { 0, -1.5, -22 } },
		AftFuselage = { parent = "Fuselage", mass = 20000, impactThreshold = 7, impactDestroy = 28, detachable = true, ref = { 0, -1.0, 22 } },
		LeftWing = { parent = "Fuselage", mass = 22000, impactThreshold = 6, impactDestroy = 22, detachable = true, ref = { -17, -0.5, 4 } },
		RightWing = { parent = "Fuselage", mass = 22000, impactThreshold = 6, impactDestroy = 22, detachable = true, ref = { 17, -0.5, 4 } },
		LeftInnerEngine = { parent = "LeftWing", mass = 5000, impactThreshold = 4, impactDestroy = 16, detachable = true, ref = { -12.0, -3.3, -6.2 } },
		LeftOuterEngine = { parent = "LeftWing", mass = 5000, impactThreshold = 4, impactDestroy = 16, detachable = true, ref = { -21.0, -2.0, 0.9 } },
		RightInnerEngine = { parent = "RightWing", mass = 5000, impactThreshold = 4, impactDestroy = 16, detachable = true, ref = { 12.0, -3.3, -6.2 } },
		RightOuterEngine = { parent = "RightWing", mass = 5000, impactThreshold = 4, impactDestroy = 16, detachable = true, ref = { 21.0, -2.0, 0.9 } },
		HorizontalStab = { parent = "AftFuselage", mass = 3500, impactThreshold = 5, impactDestroy = 18, detachable = true, ref = { 0, 1.6, 30.5 } },
		VerticalStab = { parent = "AftFuselage", mass = 3000, impactThreshold = 5, impactDestroy = 18, detachable = true, ref = { 0, 8.0, 28.5 } },
		NoseGear = { parent = "ForwardFuselage", mass = 1500, impactThreshold = 6, impactDestroy = 18, detachable = true, ref = { 0, -5.0, -26.0 }, gear = true },
		LeftWingGear = { parent = "LeftWing", mass = 3500, impactThreshold = 6, impactDestroy = 20, detachable = true, ref = { -5.8, -5.0, 1.6 }, gear = true },
		RightWingGear = { parent = "RightWing", mass = 3500, impactThreshold = 6, impactDestroy = 20, detachable = true, ref = { 5.8, -5.0, 1.6 }, gear = true },
		LeftBodyGear = { parent = "Fuselage", mass = 3500, impactThreshold = 6, impactDestroy = 20, detachable = true, ref = { -1.9, -5.0, 4.6 }, gear = true },
		RightBodyGear = { parent = "Fuselage", mass = 3500, impactThreshold = 6, impactDestroy = 20, detachable = true, ref = { 1.9, -5.0, 4.6 }, gear = true },
	},
	gearLimits = { sinkDegrade = 3.3, sinkFail = 4.8, sinkDetach = 6.5, sideSpeedFail = 9 },
	gLimit = 3.0,

	hullPoints = {
		{ 0, -3.2, -32, "ForwardFuselage" }, { 0, -3.2, -18, "ForwardFuselage" }, { 0, -3.2, 0, "Fuselage" },
		{ 0, -3.2, 14, "AftFuselage" }, { 0, -1.5, 30, "AftFuselage" },
		{ -31.5, 1.8, 14, "LeftWing" }, { 31.5, 1.8, 14, "RightWing" },
		{ -12.0, -4.6, -6.2, "LeftInnerEngine" }, { 12.0, -4.6, -6.2, "RightInnerEngine" },
		{ -21.0, -3.3, 0.9, "LeftOuterEngine" }, { 21.0, -3.3, 0.9, "RightOuterEngine" },
	},

	cameras = {
		cockpit = { -0.6, 4.05, -31.4 },
		chaseDistance = 115,
		chaseHeight = 24,
	},

	geometry = {
		fuselage = {
			radius = 3.25,
			noseZ = -36.0, cabinStartZ = -29.0, forwardSplitZ = -12.0, aftSplitZ = 12.0,
			cabinEndZ = 17.0, tailEndZ = 34.5, tailUpsweep = 2.3, noseDrop = 0.6,
			windowRows = { 0.9 }, windowPitch = 0.55,
			doors = { -27.0, -16.0, -2.0, 9.0, 15.5 },
			hump = { startZ = -34.5, endZ = -6.0, radius = 2.3, top = 4.95, frontTaper = 4.0, rearTaper = 6.0 },
			windscreen = { z = -32.7, cy = 2.75, r = 2.0 },
		},
		wing = {
			rootLE = { 3.2, -1.8, -10.4 }, rootChord = 14.5, tipChord = 4.0, span = 29.0,
			sweepDeg = 37.5, dihedralDeg = 7, rootThickness = 1.6, tipThickness = 0.4,
			aileronStart = 0.7, flapEnd = 0.6, controlChord = 0.22,
			wingletHeight = 1.8,
		},
		engine = { length = 6.5, radius = 1.35, kind = "turbofan" },
		hstab = {
			rootLE = { 1.6, 1.4, 26.6 }, rootChord = 9.0, tipChord = 3.2, span = 9.6,
			sweepDeg = 37, dihedralDeg = 7, thickness = 0.6, controlChord = 0.3,
		},
		vstab = {
			rootLE = { 0, 3.0, 22.5 }, rootChord = 12.5, tipChord = 4.0, height = 10.0,
			sweepDeg = 45, thickness = 0.65, controlChord = 0.3,
		},
		seat = { -0.6, 3.3, -31.2 },
		livery = {
			body = { 244, 244, 246 },
			belly = { 190, 196, 204 },
			stripe = { 150, 30, 40 },
			accent = { 240, 190, 70 },
			tail = { 150, 30, 40 },
			wing = { 200, 204, 210 },
			engine = { 232, 232, 236 },
			airline = "NORTHSTAR",
		},
	},
}

return config
