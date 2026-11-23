--!strict
-- Swiftlet J3: original, unbranded two-seat (tandem) jet trainer with side intakes, a
-- long canopy and a gently swept wing. Agile but forgiving; the first jet to learn on.
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
	id = "swiftletj3",
	displayName = "Swiftlet J3",
	class = "Jet trainer",
	description = "Two-seat jet trainer. Zippy and agile, but gentle enough for your first jet.",
	unlocked = true,
	seats = 2,
	difficulty = 2,
	minRunwayM = 1000,
	handling = "fighter",
	soundProfile = "jet",
	assist = { easyBankDeg = 60, easyPitchUpDeg = 28, easyPitchDownDeg = -20, easyPitchRateDeg = 12, aerobatic = true },

	mass = 4700,
	inertia = { roll = 7000, pitch = 38000, yaw = 44000 },
	fuel = { capacity = 1800, initial = 1200 },

	speeds = {
		rotate = 95, v2 = 110, approach = 115, vref = 106, cruise = 230, vmo = 340,
		flapLimits = { 999, 220, 190 }, gearLimit = 220,
	},

	aero = {
		wingSpan = 10.0,
		wingArea = 24,
		meanChord = 2.3,
		panels = Kit.panels(
			{ area = 24, x = 2.4, y = -0.35, z = 0.2, dihedralDeg = 3, aspect = 4.5, oswald = 0.75, clAlpha = 3.8, cl0 = 0.15, incidenceDeg = 2.0, stallDeg = 18, stallWidthDeg = 6, cd0 = 0.011, cm0 = 0, chord = 2.3 },
			{ area = 5.5, pos = { 0, 0.2, 5.6 }, aspect = 3.2, clAlpha = 3.4, incidenceDeg = -1.0, chord = 1.5, downwash = 0.65 },
			{ area = 3.8, pos = { 0, 1.6, 5.0 }, aspect = 1.4, clAlpha = 2.6, chord = 2.0 }
		),
		bodyDrag = { x = 12, y = 16, z = 0.8 },
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
			name = "Engine", component = "Engine",
			pos = { 0, 0, 6.6 }, axis = { 0, 0, -1 },
			maxThrust = 36000, idleN1 = 24, spoolUpTau = 1.2, spoolDownTau = 0.9,
			startTime = 6, reverseFraction = 0,
			fuelFlowIdle = 0.05, fuelFlowMax = 0.7,
		},
	},

	gear = {
		retractTime = 3,
		units = {
			Kit.gear("NoseGear", "NoseGear", { 0, -0.9, -4.0 }, { nose = true, strut = 0.95, wheel = 0.28, travel = 0.22, steerDeg = 40, leg = 0.1 }),
			Kit.gear("LeftMainGear", "LeftMainGear", { -1.5, -0.8, 0.7 }, { strut = 1.05, wheel = 0.36, travel = 0.25, leg = 0.12 }),
			Kit.gear("RightMainGear", "RightMainGear", { 1.5, -0.8, 0.7 }, { strut = 1.05, wheel = 0.36, travel = 0.25, leg = 0.12 }),
		},
		friction = { rolling = 0.02, brake = 0.55, lateral = 0.75 },
	},

	components = {
		Fuselage = Kit.comp(nil, 0, 9, 34, { 0, -0.2, 0 }),
		ForwardFuselage = Kit.comp("Fuselage", 600, 8, 28, { 0, -0.1, -4.5 }),
		AftFuselage = Kit.comp("Fuselage", 500, 7, 26, { 0, 0, 4.5 }),
		LeftWing = Kit.comp("Fuselage", 450, 7, 24, { -2.8, -0.1, 0.8 }),
		RightWing = Kit.comp("Fuselage", 450, 7, 24, { 2.8, -0.1, 0.8 }),
		Engine = Kit.comp("AftFuselage", 900, 7, 24, { 0, 0, 5.4 }),
		VerticalStab = Kit.comp("AftFuselage", 90, 6, 20, { 0, 1.9, 5.4 }),
		HorizontalStab = Kit.comp("AftFuselage", 120, 6, 20, { 0, 0, 6.2 }),
		NoseGear = Kit.comp("ForwardFuselage", 60, 6, 17, { 0, -1.5, -4.0 }, { gear = true }),
		LeftMainGear = Kit.comp("Fuselage", 110, 6, 19, { -1.5, -1.4, 0.7 }, { gear = true }),
		RightMainGear = Kit.comp("Fuselage", 110, 6, 19, { 1.5, -1.4, 0.7 }, { gear = true }),
	},
	gearLimits = { sinkDegrade = 3.6, sinkFail = 5.2, sinkDetach = 7, sideSpeedFail = 7 },
	gLimit = 9,

	hullPoints = {
		{ 0, -0.95, -4.5, "ForwardFuselage" }, { 0, -1.05, 0, "Fuselage" }, { 0, -0.7, 4.0, "AftFuselage" },
		{ 0, -0.45, 6.4, "Engine" },
		{ -5.0, -0.25, 1.0, "LeftWing" }, { 5.0, -0.25, 1.0, "RightWing" },
		{ 0, -0.5, -6.6, "ForwardFuselage" },
	},

	cameras = {
		cockpit = { 0, 0.86, -3.6 },
		chaseDistance = 20,
		chaseHeight = 4,
	},

	geometry = {
		fuselage = {
			radius = 0.72, halfWidth = 0.6,
			noseZ = -6.9, cabinStartZ = -4.6, forwardSplitZ = -2.6, aftSplitZ = 2.6,
			cabinEndZ = 3.5, tailEndZ = 6.0, tailUpsweep = 0.0, noseDrop = 0.12, tailTipFraction = 0.62,
			windowRows = {}, doors = {}, windscreen = false, apu = false, bellyFairing = false, 
			noseColor = { 210, 30, 40 }, pitot = 0.6,
			canopy = { z0 = -4.5, z1 = -0.6, y = 0.6, halfWidth = 0.44, height = 0.62, frames = { 0.12, 0.5, 0.85 }, frameColor = { 230, 230, 230 }, pilots = { { 0, 0.86, -3.6 }, { 0, 0.98, -2.0 } } },
			intakes = { { x = 0.72, y = -0.05, z0 = -2.2, z1 = 1.2, w = 0.4, h = 0.66 } },
			spine = { z0 = -1.2, z1 = 4.4, y = 0.55, halfWidth = 0.36, height = 0.28 },
		},
		wing = {
			mount = "low",
			rootLE = { 0.6, -0.35, -1.0 }, rootChord = 3.2, tipChord = 1.4, span = 4.5,
			sweepDeg = 18, dihedralDeg = 3, rootThickness = 0.22, tipThickness = 0.08,
			aileronStart = 0.55, flapEnd = 0.5, controlChord = 0.24, spoilers = false,
			wingletHeight = 0,
		},
		engine = { kind = "jet", nozzleRadius = 0.36 },
		hstab = {
			rootLE = { 0.5, 0.2, 4.9 }, rootChord = 1.5, tipChord = 0.8, span = 2.0,
			sweepDeg = 22, dihedralDeg = 0, thickness = 0.1, controlChord = 0.4,
		},
		vstab = {
			rootLE = { 0, 0.55, 3.8 }, rootChord = 2.3, tipChord = 0.9, height = 1.9,
			sweepDeg = 40, thickness = 0.12, controlChord = 0.3,
		},
		cockpit = { style = "canopy", panel = "gauges", screens = 6, halfWidth = 0.45, panelDistance = 0.75, hud = true },
		seat = { 0, 0.11, -3.45 },
		livery = {
			body = { 245, 245, 245 },
			belly = { 245, 245, 245 },
			stripe = { 210, 30, 40 },
			accent = { 210, 30, 40 },
			tail = { 210, 30, 40 },
			hstab = { 245, 245, 245 },
			wing = { 245, 245, 245 },
			wingStripe = { 210, 30, 40 },
			noseColor = { 210, 30, 40 },
			engine = { 60, 64, 70 },
			code = "SJ-03",
		},
	},
}

return config
