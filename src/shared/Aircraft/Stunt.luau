--!strict
-- Zephyr R1: original, unbranded single-seat aerobatic racer for Stunts mode (placeholder
-- until the fleet's own aerobatic aircraft lands; see Registry.stuntAircraftId).
-- Small, light, very quick to roll and pull, with a big nose propeller. Low wing,
-- symmetric airfoil, conventional tail. Same body axes and units as Meridian200.luau:
--   x = right wing, y = up, z = toward the tail (nose -z), origin at the centre of mass.
-- Not in Registry.order: the airliner fleet checks (engine-out climb, roll rate bands)
-- don't apply to it; tests/test_stunts.luau has its own checks.

local rad = math.rad

local config = {
	id = "stunt",
	displayName = "Zephyr R1",
	class = "Aerobatic racer",
	description = "Tiny single-seat stunt plane. Rolls in a blink and turns on a coin: built for ring racing.",
	unlocked = true,
	stuntsOnly = true,
	minRunwayM = 500,

	mass = 760, -- kg, pilot and fuel included
	inertia = { roll = 900, pitch = 1500, yaw = 2200 },

	fuel = { capacity = 120, initial = 80 },

	speeds = {
		rotate = 62,
		v2 = 68,
		approach = 80,
		vref = 72,
		cruise = 160,
		vmo = 205,
		flapLimits = { 999, 110 },
		gearLimit = 999, -- fixed gear
	},

	-- Per-aircraft Easy-assist limits (Assist.limits): an aerobatic plane may bank and
	-- pull much harder than an airliner, so kids can make the tight ring-course turns.
	assist = { easyBankDeg = 60, easyPitchUpDeg = 28, easyPitchDownDeg = -20, easyPitchRateDeg = 16, aerobatic = true },

	aero = {
		wingSpan = 7.5,
		wingArea = 10.0,
		meanChord = 1.35,
		panels = {
			{
				name = "LeftWing", component = "LeftWing", role = "wing", side = -1,
				pos = { -1.9, -0.35, 0.05 }, normal = { 0, 1, 0 },
				area = 5.0, aspect = 5.6, oswald = 0.80,
				clAlpha = 4.6, cl0 = 0.0, incidence = rad(1.5),
				alphaStall = rad(16.0), stallWidth = rad(5.0),
				cd0 = 0.0110, cm0 = 0.0, chord = 1.35,
			},
			{
				name = "RightWing", component = "RightWing", role = "wing", side = 1,
				pos = { 1.9, -0.35, 0.05 }, normal = { 0, 1, 0 },
				area = 5.0, aspect = 5.6, oswald = 0.80,
				clAlpha = 4.6, cl0 = 0.0, incidence = rad(1.5),
				alphaStall = rad(16.0), stallWidth = rad(5.0),
				cd0 = 0.0110, cm0 = 0.0, chord = 1.35,
			},
			{
				name = "Tailplane", component = "HorizontalStab", role = "hstab", side = 0,
				pos = { 0, 0.15, 3.9 }, normal = { 0, 1, 0 },
				area = 2.0, aspect = 3.6, oswald = 0.75,
				clAlpha = 3.4 * 0.8, cl0 = 0.0, incidence = rad(-1.0),
				alphaStall = rad(18), stallWidth = rad(5),
				cd0 = 0.009, cm0 = 0, chord = 0.75,
			},
			{
				name = "Fin", component = "VerticalStab", role = "vstab", side = 0,
				pos = { 0, 0.75, 4.0 }, normal = { 1, 0, 0 },
				area = 1.1, aspect = 1.4, oswald = 0.70,
				clAlpha = 2.6, cl0 = 0.0, incidence = 0,
				alphaStall = rad(22), stallWidth = rad(6),
				cd0 = 0.009, cm0 = 0, chord = 0.9,
			},
		},
		bodyDrag = { x = 1.6, y = 1.8, z = 0.28 },
		bodyDragPos = { 0, 0, -0.2 },
		gearDragArea = 0.12,
		extraDamping = { roll = 0.6, pitch = 1.5, yaw = 2.0 },
		elevator = { maxDeflection = rad(28), clPerRad = 2.2 },
		aileron = { maxDeflection = rad(24), clPerRad = 1.1 },
		rudder = { maxDeflection = rad(30), clPerRad = 1.6 },
		trim = { maxDeflection = rad(8) },
		flaps = {
			labels = { "UP", "DN" },
			deflectionDeg = { 0, 15 },
			dCl = { 0, 0.20 },
			dCd = { 0, 0.012 },
			dStallDeg = { 0, -1.0 },
			dCm = { 0, -0.02 },
			travelTime = 1.0,
		},
		speedbrake = { dCl = -0.05, dCd = 0.02 },
		groundEffect = true,
	},

	engines = {
		{
			name = "Engine", component = "Engine",
			pos = { 0, 0.05, -2.45 }, axis = { 0, 0, -1 },
			maxThrust = 5000, idleN1 = 25, spoolUpTau = 0.35, spoolDownTau = 0.35,
			startTime = 3, reverseFraction = 0, lapseSpeed = 230,
			fuelFlowIdle = 0.003, fuelFlowMax = 0.025,
		},
	},

	gear = {
		retractTime = 1.5,
		units = {
			{
				name = "NoseGear", component = "NoseGear",
				pos = { 0, -0.55, -1.9 }, strutLength = 0.55, wheelRadius = 0.18, travel = 0.15,
				staticCompression = 0.33, dampingRatio = 0.65,
				steerMaxDeg = 40, steerHighSpeedDeg = 6, brakes = false,
				retractAxis = "x", retractAngleDeg = 95, wheels = 1, wheelSpacing = 0,
			},
			{
				name = "LeftMainGear", component = "LeftMainGear",
				pos = { -0.9, -0.55, 0.35 }, strutLength = 0.55, wheelRadius = 0.22, travel = 0.18,
				staticCompression = 0.36, dampingRatio = 0.65,
				steerMaxDeg = 0, steerHighSpeedDeg = 0, brakes = true,
				retractAxis = "z", retractAngleDeg = -85, wheels = 1, wheelSpacing = 0,
			},
			{
				name = "RightMainGear", component = "RightMainGear",
				pos = { 0.9, -0.55, 0.35 }, strutLength = 0.55, wheelRadius = 0.22, travel = 0.18,
				staticCompression = 0.36, dampingRatio = 0.65,
				steerMaxDeg = 0, steerHighSpeedDeg = 0, brakes = true,
				retractAxis = "z", retractAngleDeg = 85, wheels = 1, wheelSpacing = 0,
			},
		},
		friction = { rolling = 0.03, brake = 0.5, lateral = 0.75 },
	},

	components = {
		Fuselage = { parent = nil, mass = 0, impactThreshold = 7, impactDestroy = 26, detachable = false, ref = { 0, -0.4, 0 } },
		ForwardFuselage = { parent = "Fuselage", mass = 90, impactThreshold = 6, impactDestroy = 22, detachable = true, ref = { 0, -0.3, -1.8 } },
		AftFuselage = { parent = "Fuselage", mass = 40, impactThreshold = 5, impactDestroy = 20, detachable = true, ref = { 0, -0.1, 3.0 } },
		LeftWing = { parent = "Fuselage", mass = 60, impactThreshold = 5, impactDestroy = 18, detachable = true, ref = { -2.2, -0.35, 0.1 } },
		RightWing = { parent = "Fuselage", mass = 60, impactThreshold = 5, impactDestroy = 18, detachable = true, ref = { 2.2, -0.35, 0.1 } },
		Engine = { parent = "ForwardFuselage", mass = 180, impactThreshold = 4, impactDestroy = 14, detachable = true, ref = { 0, 0.05, -2.45 } },
		HorizontalStab = { parent = "AftFuselage", mass = 15, impactThreshold = 4, impactDestroy = 15, detachable = true, ref = { 0, 0.15, 3.9 } },
		VerticalStab = { parent = "AftFuselage", mass = 10, impactThreshold = 4, impactDestroy = 15, detachable = true, ref = { 0, 0.8, 3.9 } },
		NoseGear = { parent = "ForwardFuselage", mass = 8, impactThreshold = 5, impactDestroy = 15, detachable = true, ref = { 0, -1.1, -1.9 }, gear = true },
		LeftMainGear = { parent = "Fuselage", mass = 12, impactThreshold = 5, impactDestroy = 16, detachable = true, ref = { -0.9, -1.1, 0.35 }, gear = true },
		RightMainGear = { parent = "Fuselage", mass = 12, impactThreshold = 5, impactDestroy = 16, detachable = true, ref = { 0.9, -1.1, 0.35 }, gear = true },
	},
	gearLimits = { sinkDegrade = 3.0, sinkFail = 4.5, sinkDetach = 6.0, sideSpeedFail = 7 },
	gLimit = 9.0, -- aerobatic airframe

	hullPoints = {
		{ 0, -0.6, -2.4, "ForwardFuselage" }, { 0, -0.6, -1.0, "ForwardFuselage" }, { 0, -0.55, 0.5, "Fuselage" },
		{ 0, -0.35, 2.5, "AftFuselage" }, { 0, -0.1, 4.4, "AftFuselage" },
		{ -3.7, -0.3, 0.3, "LeftWing" }, { 3.7, -0.3, 0.3, "RightWing" },
	},

	cameras = {
		cockpit = { 0, 0.55, 0.2 },
		chaseDistance = 16,
		chaseHeight = 3.5,
	},

	geometry = {
		fuselage = {
			radius = 0.5,
			noseZ = -2.6, cabinStartZ = -1.6, forwardSplitZ = -0.9, aftSplitZ = 1.6,
			cabinEndZ = 0.9, tailEndZ = 4.6, tailUpsweep = 0.25, noseDrop = 0.05,
			windowRows = {}, windowPitch = 0.6,
			doors = {},
		},
		wing = {
			mount = "low",
			rootLE = { 0.4, -0.35, -0.55 }, rootChord = 1.7, tipChord = 1.0, span = 3.35,
			sweepDeg = 3, dihedralDeg = 1, rootThickness = 0.22, tipThickness = 0.1,
			aileronStart = 0.15, flapEnd = 0.14, controlChord = 0.3,
			wingletHeight = 0,
		},
		engine = { length = 1.0, radius = 0.42, kind = "turboprop", propRadius = 0.95, blades = 2 },
		hstab = {
			rootLE = { 0.1, 0.15, 3.55 }, rootChord = 0.9, tipChord = 0.6, span = 1.35,
			sweepDeg = 6, dihedralDeg = 0, thickness = 0.1, controlChord = 0.45,
		},
		vstab = {
			rootLE = { 0, 0.4, 3.4 }, rootChord = 1.1, tipChord = 0.6, height = 1.0,
			sweepDeg = 25, thickness = 0.1, controlChord = 0.45,
		},
		seat = { 0, -0.05, 0.25 },
		livery = {
			body = { 250, 250, 252 },
			belly = { 230, 40, 60 },
			stripe = { 230, 40, 60 },
			accent = { 255, 200, 30 },
			tail = { 230, 40, 60 },
			wing = { 250, 250, 252 },
			engine = { 230, 40, 60 },
			airline = "",
		},
	},
}

return config
