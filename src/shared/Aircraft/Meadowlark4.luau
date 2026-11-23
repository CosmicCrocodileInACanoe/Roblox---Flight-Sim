--!strict
-- Meadowlark 4: original, unbranded four-seat single-engine trainer (high wing, wing
-- struts, fixed tricycle gear with wheel spats). The gentlest aircraft in the game.
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
	id = "meadowlark4",
	displayName = "Meadowlark 4",
	class = "Light trainer",
	description = "Four-seat high-wing trainer with one propeller. Slow, steady and very easy to land.",
	unlocked = true,
	seats = 4,
	difficulty = 1,
	minRunwayM = 600,
	handling = "light",
	soundProfile = "prop",

	mass = 1050,
	inertia = { roll = 1300, pitch = 1800, yaw = 2700 },
	fuel = { capacity = 150, initial = 100 },

	speeds = {
		rotate = 52, v2 = 60, approach = 65, vref = 58, cruise = 110, vmo = 150,
		flapLimits = { 999, 110, 85, 85 }, gearLimit = 999,
	},

	aero = {
		wingSpan = 11.0,
		wingArea = 16.2,
		meanChord = 1.5,
		panels = Kit.panels(
			{ area = 16.2, x = 2.7, y = 1.05, z = 0.12, dihedralDeg = 1.7, aspect = 7.5, clAlpha = 4.9, cl0 = 0.3, incidenceDeg = 1.5, stallDeg = 15.5, cd0 = 0.011, chord = 1.5 },
			{ area = 4.0, pos = { 0, 0.25, 5.15 }, clAlpha = 3.9, incidenceDeg = -2.5, chord = 1.0 },
			{ area = 1.9, pos = { 0, 1.25, 5.0 }, aspect = 1.5, clAlpha = 2.6, chord = 1.1 }
		),
		bodyDrag = { x = 6, y = 7, z = 0.32 },
		bodyDragPos = { 0, 0, -0.3 },
		gearDragArea = 0.12,
		extraDamping = { roll = 0.5, pitch = 2, yaw = 2.5 },
		elevator = { maxDeflection = rad(28), clPerRad = 2.5 },
		aileron = { maxDeflection = rad(20), clPerRad = 0.45 },
		rudder = { maxDeflection = rad(30), clPerRad = 1.4 },
		trim = { maxDeflection = rad(13) },
		flaps = {
			labels = { "UP", "10", "20", "30" },
			deflectionDeg = { 0, 10, 20, 30 },
			dCl = { 0, 0.25, 0.5, 0.7 },
			dCd = { 0, 0.008, 0.02, 0.04 },
			dStallDeg = { 0, -1, -1.5, -2 },
			dCm = { 0, -0.02, -0.04, -0.06 },
			travelTime = 2.0,
		},
		speedbrake = { dCl = 0, dCd = 0.02 },
		groundEffect = true,
	},

	engines = {
		{
			name = "Engine", component = "Engine",
			pos = { 0, 0.05, -2.95 }, axis = { 0, 0, -1 },
			maxThrust = 3300, idleN1 = 25, spoolUpTau = 0.8, spoolDownTau = 0.6,
			startTime = 3, reverseFraction = 0, lapseSpeed = 260,
			fuelFlowIdle = 0.003, fuelFlowMax = 0.013,
		},
	},

	gear = {
		fixed = true,
		retractTime = 1,
		units = {
			Kit.gear("NoseGear", "NoseGear", { 0, -0.87, -2.1 }, { nose = true, strut = 0.45, wheel = 0.19, travel = 0.14, steerDeg = 30, fairing = true, leg = 0.07 }),
			Kit.gear("LeftMainGear", "LeftMainGear", { -1.05, -0.95, 0.55 }, { brace = { -0.35, -0.8, 0.55 }, strut = 0.36, wheel = 0.2, travel = 0.12, fairing = true, leg = 0.07 }),
			Kit.gear("RightMainGear", "RightMainGear", { 1.05, -0.95, 0.55 }, { brace = { 0.35, -0.8, 0.55 }, strut = 0.36, wheel = 0.2, travel = 0.12, fairing = true, leg = 0.07 }),
		},
		friction = { rolling = 0.025, brake = 0.5, lateral = 0.8 },
	},

	components = {
		Fuselage = Kit.comp(nil, 0, 8, 32, { 0, -0.4, 0 }),
		ForwardFuselage = Kit.comp("Fuselage", 120, 7, 27, { 0, -0.3, -1.6 }),
		AftFuselage = Kit.comp("Fuselage", 60, 6, 25, { 0, -0.1, 3.5 }),
		LeftWing = Kit.comp("Fuselage", 70, 6, 21, { -3, 1.05, 0.2 }),
		RightWing = Kit.comp("Fuselage", 70, 6, 21, { 3, 1.05, 0.2 }),
		Engine = Kit.comp("ForwardFuselage", 130, 5, 18, { 0, 0.05, -2.6 }),
		VerticalStab = Kit.comp("AftFuselage", 12, 5, 17, { 0, 1.2, 5.0 }),
		HorizontalStab = Kit.comp("AftFuselage", 15, 5, 17, { 0, 0.25, 5.1 }),
		NoseGear = Kit.comp("ForwardFuselage", 10, 6, 17, { 0, -1.2, -2.1 }, { gear = true }),
		LeftMainGear = Kit.comp("Fuselage", 15, 6, 19, { -1.05, -1.3, 0.55 }, { gear = true }),
		RightMainGear = Kit.comp("Fuselage", 15, 6, 19, { 1.05, -1.3, 0.55 }, { gear = true }),
	},
	gearLimits = { sinkDegrade = 3.3, sinkFail = 4.8, sinkDetach = 6.5, sideSpeedFail = 7 },
	gLimit = 3.8,

	hullPoints = {
		{ 0, -0.97, -2.0, "ForwardFuselage" }, { 0, -0.97, 0, "Fuselage" }, { 0, -0.6, 3.0, "AftFuselage" },
		{ 0, -0.25, 5.6, "AftFuselage" },
		{ -5.5, 1.15, 0.2, "LeftWing" }, { 5.5, 1.15, 0.2, "RightWing" },
		{ 0, -0.45, -2.7, "Engine" },
	},

	cameras = {
		cockpit = { -0.28, 0.5, 0.15 },
		chaseDistance = 15,
		chaseHeight = 3.5,
	},

	geometry = {
		fuselage = {
			radius = 0.62, deck = 0.7,
			noseZ = -2.9, cabinStartZ = -0.8, forwardSplitZ = -0.2, aftSplitZ = 1.6,
			cabinEndZ = 2.1, tailEndZ = 6.0, tailUpsweep = 0.4, noseDrop = 0.15, tailTipFraction = 0.25,
			windowRows = {}, doors = {}, apu = false, bellyFairing = false,
			-- wraparound windscreen on the sloping nose, side windows on the cabin
			windscreen = { yLow = 0.38, yHigh = 0.86, panes = { 2, 34, 64 } },
			cabin = {
				sideWindows = { { -0.35, 0.55, 0.05, 0.55 }, { 0.65, 1.45, 0.05, 0.5 } },
			},
		},
		wing = {
			mount = "high",
			rootLE = { 0.5, 0.98, -0.3 }, rootChord = 1.6, tipChord = 1.15, span = 5.0,
			sweepDeg = 0, dihedralDeg = 1.7, rootThickness = 0.2, tipThickness = 0.13,
			aileronStart = 0.62, flapEnd = 0.55, controlChord = 0.26, spoilers = false,
			wingletHeight = 0,
			strut = { at = 0.55, base = { 0.45, -0.75, 0.2 }, diameter = 0.08 },
		},
		engine = { kind = "piston", spinnerRadius = 0.17, spinnerLength = 0.3, propRadius = 0.95, blades = 2, exhaustZ = 1.6 },
		hstab = {
			rootLE = { 0.25, 0.22, 4.75 }, rootChord = 1.15, tipChord = 0.8, span = 1.55,
			sweepDeg = 5, dihedralDeg = 0, thickness = 0.1, controlChord = 0.4,
		},
		vstab = {
			rootLE = { 0, 0.62, 4.45 }, rootChord = 1.5, tipChord = 0.75, height = 1.45,
			sweepDeg = 35, thickness = 0.12, controlChord = 0.38,
		},
		cockpit = { style = "cabin", halfWidth = 0.55, seats = 2, panel = "gauges", screens = 6, panelDistance = 0.95 },
		seat = { -0.28, -0.3, 0.2 },
		livery = {
			body = { 248, 248, 246 },
			belly = { 210, 212, 216 },
			stripe = { 200, 40, 44 },
			accent = { 200, 40, 44 },
			tail = { 200, 40, 44 },
			hstab = { 248, 248, 246 },
			wing = { 244, 244, 242 },
			engine = { 248, 248, 246 },
			code = "OS-MLK",
		},
	},
}

return config
