--!strict
-- Arrowstar: original, unbranded supersonic-style airliner (long needle nose, big delta
-- wing with elevons on the trailing edge, four engines under the wing, tall fin, no
-- tailplane). The fastest aircraft in the game; lands nose-high and fast.
-- Body axes: x = right wing, y = up, z = toward the tail (nose -z), origin at the CoM.

local function req(name: string): any
	if script then
		return (require :: any)((script :: any).Parent[name])
	end
	return (require :: any)("./" .. name)
end
local Kit = req("Kit")
local rad = math.rad

local function engine(name: string, x: number): any
	return {
		name = name, component = name,
		pos = { x, -1.55, 6.5 }, axis = { 0, 0, -1 },
		maxThrust = 125000, idleN1 = 22, spoolUpTau = 2.2, spoolDownTau = 1.4,
		startTime = 12, reverseFraction = 0.3, lapseSpeed = 900,
		-- supersonic intakes: thrust grows with speed; full throttle lights the afterburners
		ramGain = 2.0, ramDensitySpan = 0.035, afterburner = { above = 0.95, thrustMul = 1.35, fuelMul = 3 },
		fuelFlowIdle = 0.15, fuelFlowMax = 2.6,
	}
end

local config = {
	id = "arrowstar",
	displayName = "Arrowstar",
	class = "Supersonic airliner",
	description = "Super-fast delta-wing airliner with a needle nose. Full throttle lights the afterburners; climb above 1,200 ft and it passes Mach 2.",
	unlocked = true,
	seats = 100,
	difficulty = 4,
	minRunwayM = 2400,
	soundProfile = "jet",
	-- big and fast: Easy mode keeps the turns shallower than on the other aircraft
	assist = { easyBankDeg = 40, easyRollLead = 2.0 },

	mass = 110000,
	inertia = { roll = 8e6, pitch = 1.6e7, yaw = 1.7e7 },
	fuel = { capacity = 60000, initial = 30000 },

	speeds = {
		rotate = 170, v2 = 195, approach = 165, vref = 155, cruise = 340, vmo = 1400,
		flapLimits = { 999, 230 }, gearLimit = 270,
	},

	aero = {
		wingSpan = 24.0,
		wingArea = 330,
		meanChord = 15,
		panels = Kit.panels(
			{ area = 330, x = 4.2, y = -0.6, z = 1.2, dihedralDeg = 3, aspect = 1.9, oswald = 0.75, clAlpha = 4.2, cl0 = 0.2, incidenceDeg = 2.0, stallDeg = 17, stallWidthDeg = 6, cd0 = 0.006, cm0 = 0, chord = 15 },
			{ area = 40, pos = { 0, -0.6, 12.5 }, aspect = 3, clAlpha = 3.0, incidenceDeg = -1.5, chord = 2.4, downwash = 0.6 },
			{ area = 40, pos = { 0, 4.0, 17.0 }, aspect = 1.3, clAlpha = 2.6, chord = 6.0 }
		),
		bodyDrag = { x = 120, y = 150, z = 1.1 },
		bodyDragPos = { 0, 0, -2.0 },
		gearDragArea = 3.0,
		extraDamping = { roll = 12000, pitch = 25000, yaw = 8000 },
		elevator = { maxDeflection = rad(25), clPerRad = 4.0 },
		aileron = { maxDeflection = rad(20), clPerRad = 0.15 },
		rudder = { maxDeflection = rad(30), clPerRad = 1.4 },
		trim = { maxDeflection = rad(13) },
		flaps = {
			-- a delta has no real flaps: "LAND" droops the inboard elevons a little
			labels = { "UP", "LAND" },
			deflectionDeg = { 0, 8 },
			dCl = { 0, 0.12 },
			dCd = { 0, 0.012 },
			dStallDeg = { 0, 0 },
			dCm = { 0, 0 },
			travelTime = 3.0,
		},
		speedbrake = { dCl = -0.1, dCd = 0.03 },
		groundEffect = true,
		-- a thin, sharp delta built for Mach 2: little drag rise through the sound barrier
		waveDrag = { mcrit = 0.95, peak = 0.012 },
	},

	engines = {
		engine("LeftOuterEngine", -4.4),
		engine("LeftInnerEngine", -2.8),
		engine("RightInnerEngine", 2.8),
		engine("RightOuterEngine", 4.4),
	},

	gear = {
		retractTime = 8,
		units = {
			Kit.gear("NoseGear", "NoseGear", { 0, -1.3, -16.0 }, { nose = true, strut = 2.3, wheel = 0.42, travel = 0.5, damping = 0.9, steerDeg = 60, wheels = 2, wheelSpacing = 0.5 }),
			Kit.gear("LeftMainGear", "LeftMainGear", { -3.6, -1.1, 2.4 }, { strut = 2.3, wheel = 0.55, travel = 0.35, wheels = 2, wheelSpacing = 0.7 }),
			Kit.gear("RightMainGear", "RightMainGear", { 3.6, -1.1, 2.4 }, { strut = 2.3, wheel = 0.55, travel = 0.35, wheels = 2, wheelSpacing = 0.7 }),
		},
		friction = { rolling = 0.02, brake = 0.55, lateral = 0.75 },
	},

	components = {
		Fuselage = Kit.comp(nil, 0, 8, 32, { 0, -1.0, 0 }),
		ForwardFuselage = Kit.comp("Fuselage", 9000, 7, 27, { 0, -0.8, -15 }),
		AftFuselage = Kit.comp("Fuselage", 6000, 6, 25, { 0, -0.3, 14 }),
		LeftWing = Kit.comp("Fuselage", 9000, 6, 21, { -5, -0.6, 3 }),
		RightWing = Kit.comp("Fuselage", 9000, 6, 21, { 5, -0.6, 3 }),
		LeftOuterEngine = Kit.comp("LeftWing", 3200, 4, 15, { -4.4, -1.55, 4.0 }),
		LeftInnerEngine = Kit.comp("LeftWing", 3200, 4, 15, { -2.8, -1.55, 4.0 }),
		RightInnerEngine = Kit.comp("RightWing", 3200, 4, 15, { 2.8, -1.55, 4.0 }),
		RightOuterEngine = Kit.comp("RightWing", 3200, 4, 15, { 4.4, -1.55, 4.0 }),
		VerticalStab = Kit.comp("AftFuselage", 900, 5, 17, { 0, 4.0, 17.0 }),
		HorizontalStab = Kit.comp("Fuselage", 600, 5, 17, { 0, -0.6, 12.5 }),
		NoseGear = Kit.comp("ForwardFuselage", 400, 6, 17, { 0, -3.2, -16.0 }, { gear = true }),
		LeftMainGear = Kit.comp("LeftWing", 1500, 6, 19, { -3.6, -3.2, 2.4 }, { gear = true }),
		RightMainGear = Kit.comp("RightWing", 1500, 6, 19, { 3.6, -3.2, 2.4 }, { gear = true }),
	},
	gearLimits = { sinkDegrade = 4.2, sinkFail = 5.6, sinkDetach = 7.2, sideSpeedFail = 8 },
	gLimit = 2.8,

	hullPoints = {
		{ 0, -1.45, -24, "ForwardFuselage" }, { 0, -1.45, -12, "ForwardFuselage" }, { 0, -1.45, 0, "Fuselage" },
		{ 0, -1.2, 10, "AftFuselage" }, { 0, -0.3, 21, "AftFuselage" },
		{ -12.0, -0.6, 10.4, "LeftWing" }, { 12.0, -0.6, 10.4, "RightWing" },
		{ -4.4, -2.1, 4.0, "LeftOuterEngine" }, { -2.8, -2.1, 4.0, "LeftInnerEngine" },
		{ 2.8, -2.1, 4.0, "RightInnerEngine" }, { 4.4, -2.1, 4.0, "RightOuterEngine" },
	},

	cameras = {
		cockpit = { -0.45, 0.45, -21.2 },
		chaseDistance = 75,
		chaseHeight = 14,
	},

	geometry = {
		fuselage = {
			radius = 1.45,
			noseZ = -29.0, cabinStartZ = -21.5, forwardSplitZ = -8.0, aftSplitZ = 8.0,
			cabinEndZ = 12.0, tailEndZ = 22.5, tailUpsweep = 0.9, noseDrop = 0.0, tailTipFraction = 0.2,
			windowRows = { 0.3 }, windowPitch = 0.9, windowWidth = 0.22, windowHeight = 0.34,
			windowStartZ = -18.5, windowEndZ = 10.5, doors = { -19.8, 9.5 }, apu = false, bellyFairing = false,
			windscreen = { yLow = 0.3, yHigh = 0.85, panes = { 2, 24, 44 } },
			pitot = 0.7,
		},
		wing = {
			mount = "low",
			rootLE = { 1.3, -0.6, -12.0 }, rootChord = 21.3, tipChord = 1.6, span = 10.7,
			sweepDeg = 62, dihedralDeg = 0, rootThickness = 0.7, tipThickness = 0.14,
			aileronStart = 0.8, flapEnd = 0.25, controlChord = 0.1, spoilers = false,
			wingletHeight = 0,
		},
		engine = { length = 5.4, radius = 0.56, mount = "wing", fanBlades = 14 },
		-- the "tailplane" is the inboard elevons along the wing's trailing edge
		hstab = {
			rootLE = { 1.35, -0.6, 9.3 }, rootChord = 1.9, tipChord = 1.6, span = 7.0,
			sweepDeg = 2.2, dihedralDeg = 0, thickness = 0.2, controlChord = 0.75,
		},
		vstab = {
			rootLE = { 0, 1.1, 11.5 }, rootChord = 9.5, tipChord = 2.4, height = 6.6,
			sweepDeg = 55, thickness = 0.4, controlChord = 0.3,
		},
		seat = { -0.45, -0.35, -21.0 },
		livery = {
			body = { 250, 250, 252 },
			belly = { 235, 236, 240 },
			stripe = { 30, 40, 120 },
			accent = { 220, 30, 50 },
			tail = { 30, 40, 120 },
			wing = { 238, 240, 244 },
			engine = { 225, 228, 232 },
			code = "AS-01",
		},
	},
}

return config
