--!strict
-- Kestrel 72: original, unbranded high-wing regional twin turboprop (about 70 seats).
-- Slow, light and forgiving: the easiest aircraft to land. T-tail, main gear in
-- fuselage sponsons, six-blade propellers. Same body axes and units as Meridian200.luau:
--   x = right wing, y = up, z = toward the tail (nose -z), origin at the centre of mass.

local rad = math.rad

local config = {
	id = "kestrel72",
	displayName = "Kestrel 72",
	class = "Regional turboprop",
	description = "High-wing turboprop. Slow and forgiving; short take-offs and the easiest landings.",
	unlocked = true,

	mass = 20000, -- kg, including initial fuel
	inertia = { roll = 3.2e5, pitch = 6.0e5, yaw = 8.6e5 },

	fuel = { capacity = 5000, initial = 2000 },

	speeds = {
		rotate = 105,
		v2 = 112,
		approach = 115,
		vref = 108,
		cruise = 220,
		vmo = 250,
		flapLimits = { 999, 185, 175, 160, 150 },
		gearLimit = 180,
	},

	aero = {
		wingSpan = 27.0,
		wingArea = 61.0,
		meanChord = 2.3,
		panels = {
			{
				name = "LeftWing", component = "LeftWing", role = "wing", side = -1,
				pos = { -6.6, 1.3, 0.15 }, normal = { 0, 1, 0 },
				area = 30.5, aspect = 12.0, oswald = 0.82,
				clAlpha = 5.39, cl0 = 0.30, incidence = rad(2.0),
				alphaStall = rad(15.0), stallWidth = rad(4.0),
				cd0 = 0.0100, cm0 = -0.05, chord = 2.3,
			},
			{
				name = "RightWing", component = "RightWing", role = "wing", side = 1,
				pos = { 6.6, 1.3, 0.15 }, normal = { 0, 1, 0 },
				area = 30.5, aspect = 12.0, oswald = 0.82,
				clAlpha = 5.39, cl0 = 0.30, incidence = rad(2.0),
				alphaStall = rad(15.0), stallWidth = rad(4.0),
				cd0 = 0.0100, cm0 = -0.05, chord = 2.3,
			},
			{
				-- T-tail: clear of the wing wake, so less downwash loss than a low tail
				name = "Tailplane", component = "HorizontalStab", role = "hstab", side = 0,
				pos = { 0, 6.3, 13.4 }, normal = { 0, 1, 0 },
				area = 11.7, aspect = 4.5, oswald = 0.75,
				clAlpha = 4.0 * 0.7, cl0 = 0.0, incidence = rad(-2.5),
				alphaStall = rad(17), stallWidth = rad(5),
				cd0 = 0.008, cm0 = 0, chord = 1.6,
			},
			{
				name = "Fin", component = "VerticalStab", role = "vstab", side = 0,
				pos = { 0, 3.6, 12.2 }, normal = { 1, 0, 0 },
				area = 12.5, aspect = 1.6, oswald = 0.70,
				clAlpha = 2.8, cl0 = 0.0, incidence = 0,
				alphaStall = rad(20), stallWidth = rad(6),
				cd0 = 0.008, cm0 = 0, chord = 2.8,
			},
		},
		bodyDrag = { x = 40, y = 38, z = 0.85 },
		bodyDragPos = { 0, 0, -0.5 },
		gearDragArea = 1.6,
		extraDamping = { roll = 150, pitch = 600, yaw = 800 },
		elevator = { maxDeflection = rad(25), clPerRad = 1.7 },
		aileron = { maxDeflection = rad(20), clPerRad = 0.36 },
		rudder = { maxDeflection = rad(30), clPerRad = 1.4 },
		trim = { maxDeflection = rad(13) },
		flaps = {
			labels = { "UP", "10", "15", "25", "30" },
			deflectionDeg = { 0, 10, 15, 25, 30 },
			dCl = { 0, 0.25, 0.42, 0.62, 0.78 },
			dCd = { 0, 0.006, 0.014, 0.030, 0.050 },
			dStallDeg = { 0, -1.0, -1.5, -2.0, -2.5 }, -- no slats
			dCm = { 0, -0.02, -0.035, -0.05, -0.065 },
			travelTime = 2.0,
		},
		speedbrake = { dCl = -0.20, dCd = 0.030 },
		groundEffect = true,
	},

	engines = {
		{
			name = "LeftEngine", component = "LeftEngine",
			pos = { -4.1, 0.55, -2.1 }, axis = { 0, 0, -1 },
			maxThrust = 36000, idleN1 = 25, spoolUpTau = 1.5, spoolDownTau = 1.0,
			startTime = 9, reverseFraction = 0.35, lapseSpeed = 280,
			fuelFlowIdle = 0.04, fuelFlowMax = 0.32,
		},
		{
			name = "RightEngine", component = "RightEngine",
			pos = { 4.1, 0.55, -2.1 }, axis = { 0, 0, -1 },
			maxThrust = 36000, idleN1 = 25, spoolUpTau = 1.5, spoolDownTau = 1.0,
			startTime = 9, reverseFraction = 0.35, lapseSpeed = 280,
			fuelFlowIdle = 0.04, fuelFlowMax = 0.32,
		},
	},

	gear = {
		retractTime = 6,
		units = {
			{
				name = "NoseGear", component = "NoseGear",
				pos = { 0, -0.9, -9.0 }, strutLength = 1.12, wheelRadius = 0.33, travel = 0.3,
				staticCompression = 0.33, dampingRatio = 0.65,
				steerMaxDeg = 60, steerHighSpeedDeg = 6, brakes = false,
				retractAxis = "x", retractAngleDeg = 95, wheels = 2, wheelSpacing = 0.4,
			},
			{
				name = "LeftMainGear", component = "LeftMainGear",
				pos = { -2.0, -0.9, 0.9 }, strutLength = 1.0, wheelRadius = 0.42, travel = 0.35,
				staticCompression = 0.36, dampingRatio = 0.65,
				steerMaxDeg = 0, steerHighSpeedDeg = 0, brakes = true,
				retractAxis = "x", retractAngleDeg = -85, wheels = 2, wheelSpacing = 0.5,
			},
			{
				name = "RightMainGear", component = "RightMainGear",
				pos = { 2.0, -0.9, 0.9 }, strutLength = 1.0, wheelRadius = 0.42, travel = 0.35,
				staticCompression = 0.36, dampingRatio = 0.65,
				steerMaxDeg = 0, steerHighSpeedDeg = 0, brakes = true,
				retractAxis = "x", retractAngleDeg = -85, wheels = 2, wheelSpacing = 0.5,
			},
		},
		friction = { rolling = 0.02, brake = 0.55, lateral = 0.75 },
	},

	components = {
		Fuselage = { parent = nil, mass = 0, impactThreshold = 8, impactDestroy = 32, detachable = false, ref = { 0, -1.0, 0 } },
		ForwardFuselage = { parent = "Fuselage", mass = 2000, impactThreshold = 7, impactDestroy = 27, detachable = true, ref = { 0, -0.8, -8.5 } },
		AftFuselage = { parent = "Fuselage", mass = 1600, impactThreshold = 6, impactDestroy = 25, detachable = true, ref = { 0, -0.3, 9.5 } },
		LeftWing = { parent = "Fuselage", mass = 1500, impactThreshold = 6, impactDestroy = 21, detachable = true, ref = { -7, 1.3, 0.5 } },
		RightWing = { parent = "Fuselage", mass = 1500, impactThreshold = 6, impactDestroy = 21, detachable = true, ref = { 7, 1.3, 0.5 } },
		LeftEngine = { parent = "LeftWing", mass = 700, impactThreshold = 4, impactDestroy = 15, detachable = true, ref = { -4.1, 0.55, -2.1 } },
		RightEngine = { parent = "RightWing", mass = 700, impactThreshold = 4, impactDestroy = 15, detachable = true, ref = { 4.1, 0.55, -2.1 } },
		VerticalStab = { parent = "AftFuselage", mass = 300, impactThreshold = 5, impactDestroy = 17, detachable = true, ref = { 0, 3.6, 12.2 } },
		HorizontalStab = { parent = "VerticalStab", mass = 250, impactThreshold = 5, impactDestroy = 17, detachable = true, ref = { 0, 6.3, 13.4 } },
		NoseGear = { parent = "ForwardFuselage", mass = 150, impactThreshold = 6, impactDestroy = 17, detachable = true, ref = { 0, -2.0, -9.0 }, gear = true },
		LeftMainGear = { parent = "Fuselage", mass = 400, impactThreshold = 6, impactDestroy = 19, detachable = true, ref = { -2.0, -2.0, 0.9 }, gear = true },
		RightMainGear = { parent = "Fuselage", mass = 400, impactThreshold = 6, impactDestroy = 19, detachable = true, ref = { 2.0, -2.0, 0.9 }, gear = true },
	},
	gearLimits = { sinkDegrade = 3.3, sinkFail = 4.8, sinkDetach = 6.5, sideSpeedFail = 8 },
	gLimit = 3.5,

	hullPoints = {
		{ 0, -1.35, -10.5, "ForwardFuselage" }, { 0, -1.35, -5, "ForwardFuselage" }, { 0, -1.35, 0, "Fuselage" },
		{ 0, -1.35, 5, "AftFuselage" }, { 0, -0.5, 12, "AftFuselage" },
		{ -13.4, 1.4, 1.0, "LeftWing" }, { 13.4, 1.4, 1.0, "RightWing" },
		{ -4.1, -0.05, -2.1, "LeftEngine" }, { 4.1, -0.05, -2.1, "RightEngine" },
	},

	cameras = {
		cockpit = { -0.45, 0.55, -10.4 },
		chaseDistance = 44,
		chaseHeight = 9,
	},

	geometry = {
		fuselage = {
			radius = 1.4,
			noseZ = -12.6, cabinStartZ = -9.6, forwardSplitZ = -4.0, aftSplitZ = 4.5,
			cabinEndZ = 6.5, tailEndZ = 14.6, tailUpsweep = 0.95, noseDrop = 0.25,
			windowRows = { 0.35 }, windowPitch = 0.62,
			doors = { -8.6, 5.6 },
			-- main gear sponsons on the lower fuselage sides
			sponsons = { x = 1.55, y = -0.75, z0 = -1.4, z1 = 3.4, r = 0.62 },
		},
		wing = {
			mount = "high",
			rootLE = { 1.2, 1.3, -0.5 }, rootChord = 2.7, tipChord = 1.55, span = 12.3,
			sweepDeg = 2, dihedralDeg = 0, rootThickness = 0.45, tipThickness = 0.2,
			aileronStart = 0.72, flapEnd = 0.62, controlChord = 0.28,
			wingletHeight = 0,
		},
		engine = { length = 4.2, radius = 0.55, kind = "turboprop", propRadius = 1.95, blades = 6 },
		hstab = {
			rootLE = { 0.12, 6.25, 12.9 }, rootChord = 2.0, tipChord = 1.2, span = 3.6,
			sweepDeg = 8, dihedralDeg = 0, thickness = 0.22, controlChord = 0.34,
		},
		vstab = {
			rootLE = { 0, 1.15, 10.0 }, rootChord = 3.8, tipChord = 2.2, height = 5.1,
			sweepDeg = 32, thickness = 0.28, controlChord = 0.32,
		},
		seat = { -0.45, -0.2, -10.2 },
		livery = {
			body = { 246, 246, 244 },
			belly = { 200, 204, 210 },
			stripe = { 20, 140, 120 },
			accent = { 250, 200, 60 },
			tail = { 20, 140, 120 },
			wing = { 210, 212, 216 },
			engine = { 236, 236, 238 },
			airline = "BAYLINK",
		},
	},
}

return config
