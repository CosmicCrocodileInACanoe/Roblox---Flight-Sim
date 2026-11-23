--!strict
-- Puffin: original, unbranded single-engine floatplane (high wing, two floats with
-- retractable wheels, so it lands on runways and on the sea). Rugged and slow.
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
	id = "puffin",
	displayName = "Puffin",
	class = "Floatplane (amphibian)",
	description = "Bush plane on floats with wheels inside. Take off from a runway, land on the sea and take off again.",
	unlocked = true,
	seats = 6,
	difficulty = 2,
	minRunwayM = 700,
	handling = "light",
	soundProfile = "prop",

	mass = 2300,
	inertia = { roll = 5400, pitch = 6500, yaw = 10500 },
	fuel = { capacity = 300, initial = 200 },

	speeds = {
		rotate = 58, v2 = 66, approach = 70, vref = 64, cruise = 115, vmo = 155,
		flapLimits = { 999, 110, 90, 80 }, gearLimit = 120,
	},

	aero = {
		wingSpan = 14.6,
		wingArea = 23.2,
		meanChord = 1.6,
		panels = Kit.panels(
			{ area = 23.2, x = 3.7, y = 1.2, z = 0.08, dihedralDeg = 1.5, aspect = 9.2, clAlpha = 5.1, cl0 = 0.32, incidenceDeg = 2.0, stallDeg = 15, cd0 = 0.012, chord = 1.6 },
			{ area = 5.0, pos = { 0, 0.32, 5.75 }, clAlpha = 3.9, incidenceDeg = -2.5, chord = 1.15 },
			{ area = 2.8, pos = { 0, 1.5, 5.6 }, aspect = 1.4, clAlpha = 2.6, chord = 1.4 }
		),
		bodyDrag = { x = 15, y = 18, z = 0.78 },
		bodyDragPos = { 0, -0.4, -0.3 },
		gearDragArea = 0.2,
		extraDamping = { roll = 2, pitch = 6, yaw = 8 },
		elevator = { maxDeflection = rad(28), clPerRad = 2.3 },
		aileron = { maxDeflection = rad(22), clPerRad = 0.45 },
		rudder = { maxDeflection = rad(30), clPerRad = 1.5 },
		trim = { maxDeflection = rad(13) },
		flaps = {
			labels = { "UP", "10", "20", "35" },
			deflectionDeg = { 0, 10, 20, 35 },
			dCl = { 0, 0.25, 0.5, 0.75 },
			dCd = { 0, 0.008, 0.022, 0.05 },
			dStallDeg = { 0, -1, -1.5, -2.5 },
			dCm = { 0, -0.02, -0.04, -0.06 },
			travelTime = 2.0,
		},
		speedbrake = { dCl = 0, dCd = 0.02 },
		groundEffect = true,
	},

	engines = {
		{
			name = "Engine", component = "Engine",
			pos = { 0, 0.05, -3.75 }, axis = { 0, 0, -1 },
			maxThrust = 8500, idleN1 = 25, spoolUpTau = 0.9, spoolDownTau = 0.7,
			startTime = 4, reverseFraction = 0, lapseSpeed = 260,
			fuelFlowIdle = 0.006, fuelFlowMax = 0.03,
		},
	},

	-- Floats on the water (see FlightModel): hull points tagged "float" below.
	water = { restDepth = 0.3, keelDrag = 0.03, sideDrag = 1.2, heaveDamping = 0.8, humpSpeed = 9, safeSink = 2.5 },

	gear = {
		retractTime = 4,
		units = {
			Kit.gear("LeftNoseGear", "LeftNoseGear", { -1.35, -2.35, -2.6 }, { nose = true, strut = 0.25, wheel = 0.2, travel = 0.1, steerDeg = 25, door = false, light = false, leg = 0.08 }),
			Kit.gear("LeftMainGear", "LeftMainGear", { -1.35, -2.25, 0.5 }, { strut = 0.3, wheel = 0.25, travel = 0.12, door = false, leg = 0.1 }),
			Kit.gear("RightMainGear", "RightMainGear", { 1.35, -2.25, 0.5 }, { strut = 0.3, wheel = 0.25, travel = 0.12, door = false, leg = 0.1 }),
			Kit.gear("RightNoseGear", "RightNoseGear", { 1.35, -2.35, -2.6 }, { nose = true, strut = 0.25, wheel = 0.2, travel = 0.1, steerDeg = 25, door = false, leg = 0.08 }),
		},
		friction = { rolling = 0.025, brake = 0.5, lateral = 0.8 },
	},

	components = {
		Fuselage = Kit.comp(nil, 0, 8, 32, { 0, -0.5, 0 }),
		ForwardFuselage = Kit.comp("Fuselage", 220, 7, 27, { 0, -0.3, -2.2 }),
		AftFuselage = Kit.comp("Fuselage", 120, 6, 25, { 0, -0.2, 4.0 }),
		LeftWing = Kit.comp("Fuselage", 140, 6, 21, { -4.0, 1.2, 0.3 }),
		RightWing = Kit.comp("Fuselage", 140, 6, 21, { 4.0, 1.2, 0.3 }),
		Engine = Kit.comp("ForwardFuselage", 300, 5, 18, { 0, 0.05, -3.3 }),
		VerticalStab = Kit.comp("AftFuselage", 25, 5, 17, { 0, 1.5, 5.6 }),
		HorizontalStab = Kit.comp("AftFuselage", 30, 5, 17, { 0, 0.32, 5.75 }),
		LeftFloat = Kit.comp("Fuselage", 120, 8, 28, { -1.35, -2.05, 0.3 }),
		RightFloat = Kit.comp("Fuselage", 120, 8, 28, { 1.35, -2.05, 0.3 }),
		LeftNoseGear = Kit.comp("LeftFloat", 10, 6, 17, { -1.35, -2.6, -2.6 }, { gear = true }),
		RightNoseGear = Kit.comp("RightFloat", 10, 6, 17, { 1.35, -2.6, -2.6 }, { gear = true }),
		LeftMainGear = Kit.comp("LeftFloat", 20, 6, 19, { -1.35, -2.6, 0.5 }, { gear = true }),
		RightMainGear = Kit.comp("RightFloat", 20, 6, 19, { 1.35, -2.6, 0.5 }, { gear = true }),
	},
	gearLimits = { sinkDegrade = 3.3, sinkFail = 4.8, sinkDetach = 6.5, sideSpeedFail = 7 },
	gLimit = 3.8,

	hullPoints = {
		-- float bottoms (planing surfaces) and bows
		{ -1.35, -2.43, -1.9, "LeftFloat", "float" }, { -1.35, -2.43, 1.9, "LeftFloat", "float" },
		{ 1.35, -2.43, -1.9, "RightFloat", "float" }, { 1.35, -2.43, 1.9, "RightFloat", "float" },
		{ -1.35, -2.2, -3.2, "LeftFloat", "float" }, { 1.35, -2.2, -3.2, "RightFloat", "float" },
		-- fuselage, wings, engine (a ditching if these get wet)
		{ 0, -0.95, -2.0, "ForwardFuselage" }, { 0, -0.95, 1.0, "Fuselage" }, { 0, -0.5, 5.0, "AftFuselage" },
		{ -7.3, 1.3, 0.3, "LeftWing" }, { 7.3, 1.3, 0.3, "RightWing" },
		{ 0, -0.4, -3.4, "Engine" },
	},

	cameras = {
		cockpit = { -0.32, 0.55, -0.05 },
		chaseDistance = 20,
		chaseHeight = 4.5,
	},

	geometry = {
		fuselage = {
			radius = 0.68, deck = 0.55,
			noseZ = -3.6, cabinStartZ = -1.0, forwardSplitZ = -0.3, aftSplitZ = 1.8,
			cabinEndZ = 2.6, tailEndZ = 6.8, tailUpsweep = 0.45, noseDrop = 0.15, tailTipFraction = 0.22,
			windowRows = {}, doors = {}, apu = false, bellyFairing = false,
			windscreen = { yLow = 0.4, yHigh = 0.88, panes = { 2, 32, 62 } },
			cabin = {
				sideWindows = { { -0.55, 0.45, 0.05, 0.6 }, { 0.6, 1.5, 0.05, 0.6 }, { 1.65, 2.35, 0.1, 0.55 } },
			},
		},
		wing = {
			mount = "high",
			rootLE = { 0.6, 1.15, -0.45 }, rootChord = 1.65, tipChord = 1.5, span = 6.7,
			sweepDeg = 0, dihedralDeg = 1.5, rootThickness = 0.22, tipThickness = 0.15,
			aileronStart = 0.62, flapEnd = 0.56, controlChord = 0.26, spoilers = false,
			wingletHeight = 0,
			strut = { at = 0.5, base = { 0.5, -0.75, -0.1 }, diameter = 0.09 },
		},
		engine = { kind = "piston", spinnerRadius = 0.22, spinnerLength = 0.38, propRadius = 1.3, blades = 3, exhaustZ = 1.8, bladeChord = 0.2 },
		hstab = {
			rootLE = { 0.3, 0.3, 5.35 }, rootChord = 1.35, tipChord = 0.95, span = 2.3,
			sweepDeg = 5, dihedralDeg = 0, thickness = 0.12, controlChord = 0.4,
		},
		vstab = {
			rootLE = { 0, 0.75, 4.95 }, rootChord = 1.8, tipChord = 0.9, height = 1.75,
			sweepDeg = 30, thickness = 0.14, controlChord = 0.35,
		},
		floats = {
			x = 1.35, y = -2.05, z0 = -3.5, z1 = 4.0, halfWidth = 0.36, halfHeight = 0.38,
			struts = { { z = -1.4, x = 0.45, y = -0.85 }, { z = 1.2, x = 0.45, y = -0.85 } },
			color = { 240, 240, 236 },
		},
		cockpit = { style = "cabin", halfWidth = 0.6, seats = 2, panel = "gauges", screens = 6, panelDistance = 0.95 },
		seat = { -0.32, -0.25, 0.05 },
		livery = {
			body = { 250, 196, 40 },
			belly = { 60, 70, 90 },
			stripe = { 30, 60, 120 },
			accent = { 30, 60, 120 },
			tail = { 250, 196, 40 },
			wing = { 250, 196, 40 },
			engine = { 40, 44, 52 },
			code = "OS-PFN",
		},
	},
}

return config
