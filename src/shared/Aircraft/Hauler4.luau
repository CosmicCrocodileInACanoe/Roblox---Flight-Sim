--!strict
-- Hauler 4: original, unbranded four-engine high-wing cargo freighter (turboprops, T-tail,
-- upswept tail with a loading ramp, main gear in big side sponsons). Heavy but gentle;
-- lands on short strips.
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
		pos = { x, 0.85, -3.0 }, axis = { 0, 0, -1 },
		maxThrust = 34000, idleN1 = 25, spoolUpTau = 1.5, spoolDownTau = 1.0,
		startTime = 9, reverseFraction = 0.35, lapseSpeed = 280,
		fuelFlowIdle = 0.04, fuelFlowMax = 0.3,
	}
end

local config = {
	id = "hauler4",
	displayName = "Hauler 4",
	class = "Cargo freighter",
	description = "Big four-propeller cargo plane with a ramp in the tail. Heavy, slow and steady.",
	unlocked = true,
	seats = 3,
	difficulty = 3,
	minRunwayM = 1200,
	soundProfile = "prop",

	mass = 52000,
	inertia = { roll = 1.6e6, pitch = 2.6e6, yaw = 3.8e6 },
	fuel = { capacity = 20000, initial = 9000 },

	speeds = {
		rotate = 110, v2 = 118, approach = 122, vref = 114, cruise = 250, vmo = 280,
		flapLimits = { 999, 190, 170, 150 }, gearLimit = 180,
	},

	aero = {
		wingSpan = 38.0,
		wingArea = 150,
		meanChord = 4.1,
		panels = Kit.panels(
			{ area = 150, x = 9.0, y = 2.4, z = 0.2, dihedralDeg = 0, aspect = 9.6, oswald = 0.8, clAlpha = 5.2, cl0 = 0.3, incidenceDeg = 2.0, stallDeg = 15, cd0 = 0.011, cm0 = -0.05, chord = 4.1 },
			{ area = 30, pos = { 0, 8.6, 17.6 }, aspect = 4.5, clAlpha = 4.0, incidenceDeg = -2.5, chord = 2.7, downwash = 0.7 },
			{ area = 26, pos = { 0, 5.3, 16.0 }, aspect = 1.6, clAlpha = 2.8, chord = 4.4 }
		),
		bodyDrag = { x = 80, y = 90, z = 2.4 },
		bodyDragPos = { 0, 0, -0.5 },
		gearDragArea = 3.0,
		extraDamping = { roll = 600, pitch = 2400, yaw = 3200 },
		elevator = { maxDeflection = rad(25), clPerRad = 1.7 },
		aileron = { maxDeflection = rad(20), clPerRad = 0.34 },
		rudder = { maxDeflection = rad(30), clPerRad = 1.4 },
		trim = { maxDeflection = rad(13) },
		flaps = {
			labels = { "UP", "15", "30", "40" },
			deflectionDeg = { 0, 15, 30, 40 },
			dCl = { 0, 0.35, 0.65, 0.85 },
			dCd = { 0, 0.012, 0.035, 0.06 },
			dStallDeg = { 0, -1, -2, -2.5 },
			dCm = { 0, -0.03, -0.05, -0.07 },
			travelTime = 2.5,
		},
		speedbrake = { dCl = -0.2, dCd = 0.03 },
		groundEffect = true,
	},

	engines = {
		engine("LeftOuterEngine", -9.8),
		engine("LeftInnerEngine", -5.0),
		engine("RightInnerEngine", 5.0),
		engine("RightOuterEngine", 9.8),
	},

	gear = {
		retractTime = 7,
		units = {
			Kit.gear("NoseGear", "NoseGear", { 0, -1.55, -11.2 }, { nose = true, strut = 1.0, wheel = 0.45, travel = 0.3, steerDeg = 60, wheels = 2, wheelSpacing = 0.5 }),
			Kit.gear("LeftMainGear", "LeftMainGear", { -2.3, -1.6, 1.0 }, { strut = 0.85, wheel = 0.6, travel = 0.35, wheels = 2, wheelSpacing = 0.7 }),
			Kit.gear("RightMainGear", "RightMainGear", { 2.3, -1.6, 1.0 }, { strut = 0.85, wheel = 0.6, travel = 0.35, wheels = 2, wheelSpacing = 0.7 }),
		},
		friction = { rolling = 0.02, brake = 0.55, lateral = 0.75 },
	},

	components = {
		Fuselage = Kit.comp(nil, 0, 8, 32, { 0, -1.2, 0 }),
		ForwardFuselage = Kit.comp("Fuselage", 5000, 7, 27, { 0, -1.0, -10 }),
		AftFuselage = Kit.comp("Fuselage", 4000, 6, 25, { 0, -0.2, 11 }),
		LeftWing = Kit.comp("Fuselage", 4500, 6, 21, { -9, 2.4, 0.5 }),
		RightWing = Kit.comp("Fuselage", 4500, 6, 21, { 9, 2.4, 0.5 }),
		LeftOuterEngine = Kit.comp("LeftWing", 900, 4, 15, { -9.8, 0.85, -3.0 }),
		LeftInnerEngine = Kit.comp("LeftWing", 900, 4, 15, { -5.0, 0.85, -3.0 }),
		RightInnerEngine = Kit.comp("RightWing", 900, 4, 15, { 5.0, 0.85, -3.0 }),
		RightOuterEngine = Kit.comp("RightWing", 900, 4, 15, { 9.8, 0.85, -3.0 }),
		VerticalStab = Kit.comp("AftFuselage", 700, 5, 17, { 0, 5.3, 16.0 }),
		HorizontalStab = Kit.comp("VerticalStab", 600, 5, 17, { 0, 8.6, 17.6 }),
		NoseGear = Kit.comp("ForwardFuselage", 300, 6, 17, { 0, -2.8, -11.2 }, { gear = true }),
		LeftMainGear = Kit.comp("Fuselage", 900, 6, 19, { -2.3, -2.8, 1.0 }, { gear = true }),
		RightMainGear = Kit.comp("Fuselage", 900, 6, 19, { 2.3, -2.8, 1.0 }, { gear = true }),
	},
	gearLimits = { sinkDegrade = 3.3, sinkFail = 4.8, sinkDetach = 6.5, sideSpeedFail = 8 },
	gLimit = 3.0,

	hullPoints = {
		{ 0, -2.0, -12.5, "ForwardFuselage" }, { 0, -2.0, -6, "ForwardFuselage" }, { 0, -2.0, 0, "Fuselage" },
		{ 0, -2.0, 6, "AftFuselage" }, { 0, -0.6, 15, "AftFuselage" },
		{ -19.0, 2.5, 1.5, "LeftWing" }, { 19.0, 2.5, 1.5, "RightWing" },
		{ -9.8, 0.2, -3.0, "LeftOuterEngine" }, { -5.0, 0.2, -3.0, "LeftInnerEngine" },
		{ 5.0, 0.2, -3.0, "RightInnerEngine" }, { 9.8, 0.2, -3.0, "RightOuterEngine" },
	},

	cameras = {
		cockpit = { -0.55, 0.85, -13.0 },
		chaseDistance = 60,
		chaseHeight = 12,
	},

	geometry = {
		fuselage = {
			radius = 2.0,
			noseZ = -15.2, cabinStartZ = -12.0, forwardSplitZ = -5.0, aftSplitZ = 5.5,
			cabinEndZ = 7.5, tailEndZ = 18.5, tailUpsweep = 2.0, noseDrop = 0.45, tailTipFraction = 0.25,
			windowRows = {}, doors = { -10.5 }, apu = false, stripe = false,
			windscreen = { yLow = 0.4, yHigh = 1.15 },
			sponsons = { x = 2.15, y = -1.2, z0 = -2.2, z1 = 4.2, r = 0.85 },
			noseColor = { 70, 74, 80 },
		},
		wing = {
			mount = "high",
			rootLE = { 1.6, 2.4, -2.0 }, rootChord = 5.0, tipChord = 2.6, span = 17.4,
			sweepDeg = 3, dihedralDeg = -1, rootThickness = 0.75, tipThickness = 0.3,
			aileronStart = 0.72, flapEnd = 0.62, controlChord = 0.28, spoilers = false,
			wingletHeight = 0,
		},
		engine = { length = 4.6, radius = 0.62, kind = "turboprop", propRadius = 2.1, blades = 6 },
		hstab = {
			rootLE = { 0.2, 8.5, 16.9 }, rootChord = 3.2, tipChord = 1.8, span = 6.0,
			sweepDeg = 14, dihedralDeg = 0, thickness = 0.3, controlChord = 0.34,
		},
		vstab = {
			rootLE = { 0, 1.8, 12.6 }, rootChord = 5.6, tipChord = 3.2, height = 6.8,
			sweepDeg = 35, thickness = 0.4, controlChord = 0.32,
		},
		seat = { -0.55, -0.1, -12.8 },
		livery = {
			body = { 150, 160, 150 },
			belly = { 120, 128, 122 },
			stripe = { 90, 98, 92 },
			accent = { 250, 200, 60 },
			tail = { 130, 140, 132 },
			wing = { 150, 160, 150 },
			engine = { 140, 150, 142 },
			code = "HL-004",
		},
	},
}

return config
