--!strict
-- Nightjar T2: original, unbranded twin-engine air-superiority fighter (side intakes,
-- two canted fins, wide body with root strakes). Very agile; in Easy mode it still
-- levels itself when you let go.
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
	id = "nightjart2",
	displayName = "Nightjar T2",
	class = "Twin-engine fighter",
	description = "Big twin-jet fighter with two tail fins. Huge power, tight turns, rolls in a flash.",
	unlocked = true,
	seats = 1,
	difficulty = 4,
	minRunwayM = 1200,
	handling = "fighter",
	soundProfile = "jet",
	assist = { easyBankDeg = 60, easyPitchUpDeg = 30, easyPitchDownDeg = -20, easyPitchRateDeg = 14, aerobatic = true },

	mass = 11000,
	inertia = { roll = 16000, pitch = 110000, yaw = 125000 },
	fuel = { capacity = 5000, initial = 3500 },

	speeds = {
		rotate = 105, v2 = 120, approach = 128, vref = 118, cruise = 250, vmo = 380,
		flapLimits = { 999, 220, 190 }, gearLimit = 220,
	},

	aero = {
		wingSpan = 12.6,
		wingArea = 46,
		meanChord = 4.0,
		panels = Kit.panels(
			{ area = 46, x = 3.0, y = -0.1, z = 0.25, dihedralDeg = -1, aspect = 3.6, oswald = 0.75, clAlpha = 3.8, cl0 = 0.15, incidenceDeg = 2.0, stallDeg = 22, stallWidthDeg = 6, cd0 = 0.011, cm0 = 0, chord = 4.0 },
			{ area = 11, pos = { 0, 0.05, 6.6 }, aspect = 3.2, clAlpha = 3.4, incidenceDeg = -1.0, chord = 1.5, downwash = 0.65 },
			{ area = 7.5, pos = { 0, 1.7, 5.6 }, aspect = 1.4, clAlpha = 2.6, chord = 2.2 }
		),
		bodyDrag = { x = 20, y = 30, z = 1.6 },
		bodyDragPos = { 0, 0, -0.5 },
		gearDragArea = 0.45,
		extraDamping = { roll = 1, pitch = 4, yaw = 4 },
		elevator = { maxDeflection = rad(25), clPerRad = 2.2 },
		aileron = { maxDeflection = rad(20), clPerRad = 0.55 },
		rudder = { maxDeflection = rad(30), clPerRad = 1.3 },
		trim = { maxDeflection = rad(10) },
		flaps = {
			labels = { "UP", "HALF", "FULL" },
			deflectionDeg = { 0, 15, 30 },
			dCl = { 0, 0.2, 0.4 },
			dCd = { 0, 0.012, 0.035 },
			dStallDeg = { 0, -1, -2 },
			dCm = { 0, -0.01, -0.02 },
			travelTime = 2.0,
		},
		speedbrake = { dCl = 0, dCd = 0.06 },
		groundEffect = true,
	},

	engines = {
		{
			name = "LeftEngine", component = "LeftEngine",
			pos = { -0.6, -0.05, 7.4 }, axis = { 0, 0, -1 },
			maxThrust = 55000, idleN1 = 24, spoolUpTau = 1.2, spoolDownTau = 0.9,
			startTime = 6, reverseFraction = 0,
			fuelFlowIdle = 0.07, fuelFlowMax = 1.2,
		},
		{
			name = "RightEngine", component = "RightEngine",
			pos = { 0.6, -0.05, 7.4 }, axis = { 0, 0, -1 },
			maxThrust = 55000, idleN1 = 24, spoolUpTau = 1.2, spoolDownTau = 0.9,
			startTime = 6, reverseFraction = 0,
			fuelFlowIdle = 0.07, fuelFlowMax = 1.2,
		},
	},

	gear = {
		retractTime = 3,
		units = {
			Kit.gear("NoseGear", "NoseGear", { 0, -0.95, -4.4 }, { nose = true, strut = 0.95, wheel = 0.28, travel = 0.22, steerDeg = 40, leg = 0.1 }),
			Kit.gear("LeftMainGear", "LeftMainGear", { -1.6, -0.75, 0.9 }, { strut = 1.05, wheel = 0.36, travel = 0.25, leg = 0.12 }),
			Kit.gear("RightMainGear", "RightMainGear", { 1.6, -0.75, 0.9 }, { strut = 1.05, wheel = 0.36, travel = 0.25, leg = 0.12 }),
		},
		friction = { rolling = 0.02, brake = 0.55, lateral = 0.75 },
	},

	components = {
		Fuselage = Kit.comp(nil, 0, 9, 34, { 0, -0.2, 0 }),
		ForwardFuselage = Kit.comp("Fuselage", 600, 8, 28, { 0, -0.1, -4.5 }),
		AftFuselage = Kit.comp("Fuselage", 500, 7, 26, { 0, 0, 4.5 }),
		LeftWing = Kit.comp("Fuselage", 450, 7, 24, { -2.8, -0.1, 0.8 }),
		RightWing = Kit.comp("Fuselage", 450, 7, 24, { 2.8, -0.1, 0.8 }),
		LeftEngine = Kit.comp("AftFuselage", 1300, 7, 24, { -0.6, 0, 6.0 }),
		RightEngine = Kit.comp("AftFuselage", 1300, 7, 24, { 0.6, 0, 6.0 }),
		VerticalStab = Kit.comp("AftFuselage", 90, 6, 20, { 0, 1.9, 5.4 }),
		HorizontalStab = Kit.comp("AftFuselage", 120, 6, 20, { 0, 0, 6.2 }),
		NoseGear = Kit.comp("ForwardFuselage", 60, 6, 17, { 0, -1.5, -4.4 }, { gear = true }),
		LeftMainGear = Kit.comp("Fuselage", 110, 6, 19, { -1.6, -1.4, 0.9 }, { gear = true }),
		RightMainGear = Kit.comp("Fuselage", 110, 6, 19, { 1.6, -1.4, 0.9 }, { gear = true }),
	},
	gearLimits = { sinkDegrade = 3.6, sinkFail = 5.2, sinkDetach = 7, sideSpeedFail = 7 },
	gLimit = 9,

	hullPoints = {
		{ 0, -0.95, -4.5, "ForwardFuselage" }, { 0, -1.05, 0, "Fuselage" }, { 0, -0.7, 4.0, "AftFuselage" },
		{ -0.6, -0.55, 7.2, "LeftEngine" }, { 0.6, -0.55, 7.2, "RightEngine" },
		{ -6.2, -0.15, 3.6, "LeftWing" }, { 6.2, -0.15, 3.6, "RightWing" },
		{ 0, -0.6, -7.4, "ForwardFuselage" },
	},

	cameras = {
		cockpit = { 0, 0.88, -3.4 },
		chaseDistance = 20,
		chaseHeight = 4,
	},

	geometry = {
		fuselage = {
			radius = 0.76, halfWidth = 1.2,
			noseZ = -7.8, cabinStartZ = -4.9, forwardSplitZ = -2.6, aftSplitZ = 2.6,
			cabinEndZ = 3.5, tailEndZ = 6.6, tailUpsweep = 0.0, noseDrop = 0.12, tailTipFraction = 0.62,
			windowRows = {}, doors = {}, windscreen = false, apu = false, bellyFairing = false, stripe = false,
			noseColor = { 70, 74, 80 }, pitot = 1.0,
			canopy = { z0 = -4.4, z1 = -1.6, y = 0.62, halfWidth = 0.44, height = 0.62, frames = { 0.2 }, frameColor = { 40, 44, 50 }, pilots = { { 0, 0.88, -3.4 } } },
			intakes = { { x = 1.25, y = -0.25, z0 = -2.4, z1 = 2.0, w = 0.62, h = 0.8 } },
			spine = { z0 = -2.2, z1 = 4.6, y = 0.6, halfWidth = 0.5, height = 0.3 },
		},
		wing = {
			mount = "mid",
			rootLE = { 1.2, -0.1, -2.2 }, rootChord = 5.2, tipChord = 1.5, span = 5.1,
			sweepDeg = 38, dihedralDeg = -1, rootThickness = 0.22, tipThickness = 0.08,
			aileronStart = 0.55, flapEnd = 0.5, controlChord = 0.24, spoilers = false,
			wingletHeight = 0,
			strake = { x = 1.1, z0 = -4.6, reach = 0.7 },
		},
		engine = { kind = "jet", nozzleRadius = 0.44 },
		hstab = {
			rootLE = { 1.15, -0.05, 5.4 }, rootChord = 2.4, tipChord = 0.9, span = 2.6,
			sweepDeg = 40, dihedralDeg = 0, thickness = 0.1, controlChord = 0.4,
		},
		vstab = {
			rootLE = { 0, 0.6, 4.1 }, rootChord = 2.8, tipChord = 1.0, height = 2.3,
			sweepDeg = 42, thickness = 0.12, controlChord = 0.3, count = 2, spacing = 2.2, cantDeg = 20,
		},
		cockpit = { style = "canopy", panel = "screens", screens = 3, halfWidth = 0.45, panelDistance = 0.75, hud = true },
		seat = { 0, 0.13, -3.25 },
		livery = {
			body = { 78, 84, 94 },
			belly = { 150, 156, 164 },
			stripe = { 245, 120, 30 },
			accent = { 245, 120, 30 },
			tail = { 78, 84, 94 },
			hstab = { 78, 84, 94 },
			wing = { 78, 84, 94 },
			wingStripe = { 245, 120, 30 },
			engine = { 60, 64, 70 },
			code = "NJ-02",
		},
	},
}

return config
