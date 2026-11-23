--!strict
-- Vector X1: original, unbranded single-seat, single-engine light fighter (chin intake,
-- bubble canopy, swept wing with root strakes, one fin). Quick and agile; in Easy mode
-- it still levels itself when you let go.
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
	id = "vectorx1",
	displayName = "Vector X1",
	class = "Light fighter",
	description = "Fast single-seat jet with a bubble canopy. Rolls quickly and climbs like a rocket.",
	unlocked = true,
	seats = 1,
	difficulty = 3,
	minRunwayM = 1200,
	handling = "fighter",
	soundProfile = "jet",
	assist = { easyBankDeg = 60, easyPitchUpDeg = 30, easyPitchDownDeg = -20, easyPitchRateDeg = 14, aerobatic = true },

	mass = 7000,
	inertia = { roll = 9000, pitch = 55000, yaw = 62000 },
	fuel = { capacity = 3000, initial = 2000 },

	speeds = {
		rotate = 105, v2 = 120, approach = 128, vref = 118, cruise = 250, vmo = 380,
		flapLimits = { 999, 220, 190 }, gearLimit = 220,
	},

	aero = {
		wingSpan = 10.6,
		wingArea = 30,
		meanChord = 3.0,
		panels = Kit.panels(
			{ area = 30, x = 2.5, y = -0.1, z = 0.25, dihedralDeg = -1, aspect = 3.6, oswald = 0.75, clAlpha = 3.8, cl0 = 0.15, incidenceDeg = 2.0, stallDeg = 22, stallWidthDeg = 6, cd0 = 0.011, cm0 = 0, chord = 3.0 },
			{ area = 7.5, pos = { 0, 0.05, 6.2 }, aspect = 3.2, clAlpha = 3.4, incidenceDeg = -1.0, chord = 1.5, downwash = 0.65 },
			{ area = 5.0, pos = { 0, 1.9, 5.4 }, aspect = 1.4, clAlpha = 2.6, chord = 2.0 }
		),
		bodyDrag = { x = 14, y = 20, z = 0.95 },
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
			pos = { 0, 0, 7.2 }, axis = { 0, 0, -1 },
			maxThrust = 70000, idleN1 = 24, spoolUpTau = 1.2, spoolDownTau = 0.9,
			startTime = 6, reverseFraction = 0,
			fuelFlowIdle = 0.08, fuelFlowMax = 1.4,
		},
	},

	gear = {
		retractTime = 3,
		units = {
			Kit.gear("NoseGear", "NoseGear", { 0, -0.95, -4.4 }, { nose = true, strut = 0.95, wheel = 0.28, travel = 0.22, steerDeg = 40, leg = 0.1 }),
			Kit.gear("LeftMainGear", "LeftMainGear", { -1.45, -0.75, 0.9 }, { strut = 1.05, wheel = 0.36, travel = 0.25, leg = 0.12 }),
			Kit.gear("RightMainGear", "RightMainGear", { 1.45, -0.75, 0.9 }, { strut = 1.05, wheel = 0.36, travel = 0.25, leg = 0.12 }),
		},
		friction = { rolling = 0.02, brake = 0.55, lateral = 0.75 },
	},

	components = {
		Fuselage = Kit.comp(nil, 0, 9, 34, { 0, -0.2, 0 }),
		ForwardFuselage = Kit.comp("Fuselage", 600, 8, 28, { 0, -0.1, -4.5 }),
		AftFuselage = Kit.comp("Fuselage", 500, 7, 26, { 0, 0, 4.5 }),
		LeftWing = Kit.comp("Fuselage", 450, 7, 24, { -2.8, -0.1, 0.8 }),
		RightWing = Kit.comp("Fuselage", 450, 7, 24, { 2.8, -0.1, 0.8 }),
		Engine = Kit.comp("AftFuselage", 1400, 7, 24, { 0, 0, 5.8 }),
		VerticalStab = Kit.comp("AftFuselage", 90, 6, 20, { 0, 1.9, 5.4 }),
		HorizontalStab = Kit.comp("AftFuselage", 120, 6, 20, { 0, 0, 6.2 }),
		NoseGear = Kit.comp("ForwardFuselage", 60, 6, 17, { 0, -1.5, -4.4 }, { gear = true }),
		LeftMainGear = Kit.comp("Fuselage", 110, 6, 19, { -1.45, -1.4, 0.9 }, { gear = true }),
		RightMainGear = Kit.comp("Fuselage", 110, 6, 19, { 1.45, -1.4, 0.9 }, { gear = true }),
	},
	gearLimits = { sinkDegrade = 3.6, sinkFail = 5.2, sinkDetach = 7, sideSpeedFail = 7 },
	gLimit = 9,

	hullPoints = {
		{ 0, -0.95, -4.5, "ForwardFuselage" }, { 0, -1.05, 0, "Fuselage" }, { 0, -0.7, 4.0, "AftFuselage" },
		{ 0, -0.5, 7.0, "Engine" },
		{ -5.1, -0.15, 3.2, "LeftWing" }, { 5.1, -0.15, 3.2, "RightWing" },
		{ 0, -0.6, -7.4, "ForwardFuselage" },
	},

	cameras = {
		cockpit = { 0, 0.88, -3.4 },
		chaseDistance = 20,
		chaseHeight = 4,
	},

	geometry = {
		fuselage = {
			radius = 0.74, halfWidth = 0.64,
			noseZ = -7.8, cabinStartZ = -4.9, forwardSplitZ = -2.6, aftSplitZ = 2.6,
			cabinEndZ = 3.5, tailEndZ = 6.6, tailUpsweep = 0.0, noseDrop = 0.12, tailTipFraction = 0.62,
			windowRows = {}, doors = {}, windscreen = false, apu = false, bellyFairing = false, stripe = false,
			noseColor = { 70, 74, 80 }, pitot = 1.0,
			canopy = { z0 = -4.4, z1 = -1.6, y = 0.62, halfWidth = 0.44, height = 0.62, frames = { 0.2 }, frameColor = { 40, 44, 50 }, pilots = { { 0, 0.88, -3.4 } } },
			intakes = { { x = 0, y = -0.74, z0 = -2.6, z1 = 1.6, w = 1.05, h = 0.6 } },
			spine = { z0 = -2.2, z1 = 5.2, y = 0.6, halfWidth = 0.4, height = 0.32 },
		},
		wing = {
			mount = "mid",
			rootLE = { 0.7, -0.1, -2.0 }, rootChord = 4.5, tipChord = 1.3, span = 4.6,
			sweepDeg = 38, dihedralDeg = -1, rootThickness = 0.22, tipThickness = 0.08,
			aileronStart = 0.55, flapEnd = 0.5, controlChord = 0.24, spoilers = false,
			wingletHeight = 0,
			strake = { x = 0.68, z0 = -4.4, reach = 0.6 },
		},
		engine = { kind = "jet", nozzleRadius = 0.48 },
		hstab = {
			rootLE = { 0.6, 0.0, 5.3 }, rootChord = 2.1, tipChord = 0.8, span = 2.3,
			sweepDeg = 40, dihedralDeg = 0, thickness = 0.1, controlChord = 0.4,
		},
		vstab = {
			rootLE = { 0, 0.6, 3.9 }, rootChord = 3.0, tipChord = 1.0, height = 2.6,
			sweepDeg = 45, thickness = 0.12, controlChord = 0.3,
		},
		cockpit = { style = "canopy", panel = "screens", screens = 3, halfWidth = 0.45, panelDistance = 0.75, hud = true },
		seat = { 0, 0.13, -3.25 },
		livery = {
			body = { 40, 90, 170 },
			belly = { 200, 206, 214 },
			stripe = { 250, 200, 40 },
			accent = { 250, 200, 40 },
			tail = { 40, 90, 170 },
			hstab = { 40, 90, 170 },
			wing = { 40, 90, 170 },
			wingStripe = { 250, 200, 40 },
			engine = { 60, 64, 70 },
			code = "VX-01",
		},
	},
}

return config
