--!strict
-- Sprite: original, unbranded single-seat aerobatic monoplane (low wing, bubble canopy,
-- three-blade propeller, fixed gear with spats). Rolls very fast and loops easily; in
-- Easy mode it still levels itself when you let go.
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
	id = "sprite",
	displayName = "Sprite",
	class = "Aerobatic stunt plane",
	description = "Tiny stunt plane that rolls in a blink. Loops, rolls and air-show tricks.",
	unlocked = true,
	seats = 1,
	difficulty = 2,
	minRunwayM = 600,
	handling = "aerobatic",
	soundProfile = "prop",
	assist = { easyBankDeg = 60, easyPitchUpDeg = 28, easyPitchDownDeg = -20, easyPitchRateDeg = 16, aerobatic = true },

	mass = 820,
	inertia = { roll = 500, pitch = 1300, yaw = 1700 },
	fuel = { capacity = 120, initial = 80 },

	speeds = {
		rotate = 56, v2 = 64, approach = 68, vref = 62, cruise = 150, vmo = 220,
		flapLimits = { 999, 110, 95 }, gearLimit = 999,
	},

	aero = {
		wingSpan = 7.5,
		wingArea = 10.8,
		meanChord = 1.45,
		panels = Kit.panels(
			{ area = 10.8, x = 1.8, y = -0.3, z = 0.06, dihedralDeg = 0, aspect = 5.2, clAlpha = 4.5, cl0 = 0.1, incidenceDeg = 1.5, stallDeg = 17, cd0 = 0.011, cm0 = 0, chord = 1.45 },
			{ area = 2.6, pos = { 0, 0.18, 4.25 }, clAlpha = 3.6, incidenceDeg = -1.0, chord = 0.85 },
			{ area = 1.6, pos = { 0, 0.95, 4.1 }, aspect = 1.4, clAlpha = 2.6, chord = 1.05 }
		),
		bodyDrag = { x = 5, y = 6, z = 0.25 },
		bodyDragPos = { 0, 0, -0.3 },
		gearDragArea = 0.1,
		extraDamping = { roll = 0.2, pitch = 1, yaw = 1.5 },
		elevator = { maxDeflection = rad(28), clPerRad = 2.4 },
		aileron = { maxDeflection = rad(22), clPerRad = 1.25 },
		rudder = { maxDeflection = rad(30), clPerRad = 1.6 },
		trim = { maxDeflection = rad(10) },
		flaps = {
			labels = { "UP", "1", "2" },
			deflectionDeg = { 0, 10, 20 },
			dCl = { 0, 0.2, 0.35 },
			dCd = { 0, 0.008, 0.02 },
			dStallDeg = { 0, -1, -1.5 },
			dCm = { 0, -0.01, -0.02 },
			travelTime = 1.5,
		},
		speedbrake = { dCl = 0, dCd = 0.02 },
		groundEffect = true,
	},

	engines = {
		{
			name = "Engine", component = "Engine",
			pos = { 0, 0.0, -2.7 }, axis = { 0, 0, -1 },
			maxThrust = 5500, idleN1 = 25, spoolUpTau = 0.5, spoolDownTau = 0.4,
			startTime = 3, reverseFraction = 0, lapseSpeed = 300,
			fuelFlowIdle = 0.004, fuelFlowMax = 0.022,
		},
	},

	gear = {
		fixed = true,
		retractTime = 1,
		units = {
			Kit.gear("NoseGear", "NoseGear", { 0, -0.54, -1.8 }, { nose = true, strut = 0.4, wheel = 0.17, travel = 0.12, steerDeg = 30, fairing = true, leg = 0.06 }),
			Kit.gear("LeftMainGear", "LeftMainGear", { -0.95, -0.42, 0.35 }, { strut = 0.5, wheel = 0.19, travel = 0.12, fairing = true, leg = 0.07 }),
			Kit.gear("RightMainGear", "RightMainGear", { 0.95, -0.42, 0.35 }, { strut = 0.5, wheel = 0.19, travel = 0.12, fairing = true, leg = 0.07 }),
		},
		friction = { rolling = 0.025, brake = 0.5, lateral = 0.8 },
	},

	components = {
		Fuselage = Kit.comp(nil, 0, 8, 32, { 0, -0.3, 0 }),
		ForwardFuselage = Kit.comp("Fuselage", 90, 7, 27, { 0, -0.2, -1.4 }),
		AftFuselage = Kit.comp("Fuselage", 45, 6, 25, { 0, -0.1, 3.0 }),
		LeftWing = Kit.comp("Fuselage", 60, 6, 21, { -2.2, -0.3, 0.2 }),
		RightWing = Kit.comp("Fuselage", 60, 6, 21, { 2.2, -0.3, 0.2 }),
		Engine = Kit.comp("ForwardFuselage", 160, 5, 18, { 0, 0, -2.3 }),
		VerticalStab = Kit.comp("AftFuselage", 10, 5, 17, { 0, 0.95, 4.1 }),
		HorizontalStab = Kit.comp("AftFuselage", 12, 5, 17, { 0, 0.18, 4.25 }),
		NoseGear = Kit.comp("ForwardFuselage", 8, 6, 17, { 0, -0.9, -1.8 }, { gear = true }),
		LeftMainGear = Kit.comp("LeftWing", 12, 6, 19, { -0.95, -0.9, 0.35 }, { gear = true }),
		RightMainGear = Kit.comp("RightWing", 12, 6, 19, { 0.95, -0.9, 0.35 }, { gear = true }),
	},
	gearLimits = { sinkDegrade = 3.3, sinkFail = 4.8, sinkDetach = 6.5, sideSpeedFail = 7 },
	gLimit = 9,

	hullPoints = {
		{ 0, -0.55, -1.8, "ForwardFuselage" }, { 0, -0.55, 0, "Fuselage" }, { 0, -0.4, 2.8, "AftFuselage" },
		{ 0, -0.1, 4.8, "AftFuselage" },
		{ -3.75, -0.3, 0.3, "LeftWing" }, { 3.75, -0.3, 0.3, "RightWing" },
		{ 0, -0.35, -2.5, "Engine" },
	},

	cameras = {
		cockpit = { 0, 0.62, 0.35 },
		chaseDistance = 13,
		chaseHeight = 3,
	},

	geometry = {
		fuselage = {
			radius = 0.55, halfWidth = 0.46,
			noseZ = -2.6, cabinStartZ = -1.6, forwardSplitZ = -0.3, aftSplitZ = 1.3,
			cabinEndZ = 1.8, tailEndZ = 5.0, tailUpsweep = 0.3, noseDrop = 0.05, tailTipFraction = 0.25,
			windowRows = {}, doors = {}, windscreen = false, apu = false, bellyFairing = false,
			canopy = { z0 = -0.45, z1 = 1.35, y = 0.42, halfWidth = 0.42, height = 0.45, frames = { 0.05 }, frameColor = { 250, 200, 40 } },
		},
		wing = {
			mount = "low",
			rootLE = { 0.45, -0.3, -0.45 }, rootChord = 1.75, tipChord = 1.0, span = 3.3,
			sweepDeg = 3, dihedralDeg = 0, rootThickness = 0.18, tipThickness = 0.1,
			aileronStart = 0.5, flapEnd = 0.45, controlChord = 0.28, spoilers = false,
			wingletHeight = 0,
		},
		engine = { kind = "piston", spinnerRadius = 0.2, spinnerLength = 0.34, propRadius = 0.98, blades = 3, spinnerColor = { 250, 200, 40 }, exhaustZ = 1.0, bladeChord = 0.16 },
		hstab = {
			rootLE = { 0.2, 0.15, 3.9 }, rootChord = 1.0, tipChord = 0.7, span = 1.4,
			sweepDeg = 8, dihedralDeg = 0, thickness = 0.09, controlChord = 0.45,
		},
		vstab = {
			rootLE = { 0, 0.45, 3.6 }, rootChord = 1.3, tipChord = 0.8, height = 1.25,
			sweepDeg = 30, thickness = 0.1, controlChord = 0.45,
		},
		cockpit = { style = "canopy", panel = "gauges", screens = 6, halfWidth = 0.4, panelDistance = 0.7 },
		seat = { 0, -0.13, 0.45 },
		livery = {
			body = { 220, 30, 40 },
			belly = { 245, 245, 245 },
			stripe = { 250, 200, 40 },
			accent = { 250, 200, 40 },
			tail = { 220, 30, 40 },
			hstab = { 245, 245, 245 },
			wing = { 245, 245, 245 },
			wingStripe = { 220, 30, 40 },
			engine = { 220, 30, 40 },
			code = "SPRITE",
		},
	},
}

return config
