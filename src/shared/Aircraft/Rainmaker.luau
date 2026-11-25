--!strict
-- Rainmaker: original, unbranded twin-turboprop firefighting flying boat (amphibian).
-- The fuselage is a boat hull with a planing step, the wing sits high on top with the
-- engines well clear of the spray, small floats hang under the wingtips, and the wheels
-- fold into the hull sides so it also uses runways. It skims the sea to scoop up a tank
-- of water and drops it on wildfires (see FlightModel's water tank and Wildfire).
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
		pos = { x, 2.15, -2.6 }, axis = { 0, 0, -1 },
		maxThrust = 40000, idleN1 = 25, spoolUpTau = 1.3, spoolDownTau = 0.9,
		startTime = 8, reverseFraction = 0.35, lapseSpeed = 270,
		fuelFlowIdle = 0.03, fuelFlowMax = 0.24,
	}
end

local KEEL = -1.95 -- hull bottom (metres below the CoM)

local config = {
	id = "rainmaker",
	displayName = "Rainmaker",
	class = "Firefighting flying boat (amphibian)",
	description = "Water bomber on a boat hull. Skim the sea to scoop 6 tonnes of water, then hold L over a wildfire to drop it. Lands on runways too.",
	unlocked = true,
	seats = 2,
	difficulty = 3,
	minRunwayM = 1100,
	soundProfile = "prop",
	-- a heavy, low and slow worker: Easy mode keeps its banks a bit shallower
	assist = { easyBankDeg = 40, easyRollLead = 0.8 },

	mass = 14000, -- kg, empty tank, including the initial fuel
	inertia = { roll = 2.8e5, pitch = 3.6e5, yaw = 5.8e5 },
	fuel = { capacity = 5800, initial = 2400 },

	-- Scoop at 50+ kt on the hull (about 12 s for a full tank), drop in about 3 s.
	-- Parked at an airport, a hose fills it (slower).
	waterTank = { capacity = 6000, scoopMinKt = 50, scoopRate = 500, dropRate = 2000, refillRate = 250, component = "Fuselage" },

	speeds = {
		rotate = 72, v2 = 80, approach = 84, vref = 78, cruise = 170, vmo = 205,
		flapLimits = { 999, 160, 140, 125 }, gearLimit = 150,
	},

	aero = {
		wingSpan = 28.6,
		wingArea = 96,
		meanChord = 3.4,
		panels = Kit.panels(
			{ area = 96, x = 6.8, y = 2.0, z = -0.15, dihedralDeg = 1, aspect = 8.5, oswald = 0.8, clAlpha = 5.2, cl0 = 0.32, incidenceDeg = 2.0, stallDeg = 15, cd0 = 0.012, cm0 = -0.05, chord = 3.4 },
			{ area = 24, pos = { 0, 4.4, 9.4 }, aspect = 4.2, clAlpha = 4.0, incidenceDeg = -2.5, chord = 2.4, downwash = 0.72 },
			{ area = 17, pos = { 0, 3.4, 9.0 }, aspect = 1.5, clAlpha = 2.8, chord = 3.2 }
		),
		bodyDrag = { x = 45, y = 44, z = 1.6 },
		bodyDragPos = { 0, -0.4, -0.6 },
		gearDragArea = 1.2,
		extraDamping = { roll = 160, pitch = 650, yaw = 850 },
		elevator = { maxDeflection = rad(25), clPerRad = 1.8 },
		aileron = { maxDeflection = rad(20), clPerRad = 0.38 },
		rudder = { maxDeflection = rad(30), clPerRad = 1.4 },
		trim = { maxDeflection = rad(13) },
		flaps = {
			labels = { "UP", "10", "15", "25" },
			deflectionDeg = { 0, 10, 15, 25 },
			dCl = { 0, 0.25, 0.45, 0.7 },
			dCd = { 0, 0.012, 0.03, 0.07 },
			dStallDeg = { 0, -1, -1.5, -2.5 },
			dCm = { 0, -0.02, -0.035, -0.055 },
			travelTime = 2.5,
		},
		speedbrake = { dCl = -0.1, dCd = 0.025 },
		groundEffect = true,
	},

	engines = {
		engine("LeftEngine", -4.4),
		engine("RightEngine", 4.4),
	},

	-- The hull rides on the water (FlightModel: hull points tagged "float" below).
	water = { restDepth = 0.4, keelDrag = 0.065, sideDrag = 1.1, heaveDamping = 0.9, humpSpeed = 17, safeSink = 2.8, linearDamping = 6 },

	gear = {
		retractTime = 6,
		units = {
			Kit.gear("NoseGear", "NoseGear", { 0, -1.45, -6.4 }, { nose = true, strut = 0.9, wheel = 0.34, travel = 0.28, steerDeg = 55, wheels = 2, wheelSpacing = 0.4 }),
			Kit.gear("LeftMainGear", "LeftMainGear", { -1.75, -1.35, 0.7 }, { strut = 1.0, wheel = 0.42, travel = 0.32, wheels = 2, wheelSpacing = 0.45, retractAxis = "z", retractDeg = 80 }),
			Kit.gear("RightMainGear", "RightMainGear", { 1.75, -1.35, 0.7 }, { strut = 1.0, wheel = 0.42, travel = 0.32, wheels = 2, wheelSpacing = 0.45, retractAxis = "z", retractDeg = -80 }),
		},
		friction = { rolling = 0.02, brake = 0.55, lateral = 0.75 },
	},

	components = {
		Fuselage = Kit.comp(nil, 0, 9, 34, { 0, -0.9, 0 }),
		ForwardFuselage = Kit.comp("Fuselage", 1600, 8, 29, { 0, -0.8, -6.5 }),
		AftFuselage = Kit.comp("Fuselage", 1200, 7, 26, { 0, -0.3, 6.5 }),
		LeftWing = Kit.comp("Fuselage", 1500, 6, 22, { -7.0, 2.0, -0.2 }),
		RightWing = Kit.comp("Fuselage", 1500, 6, 22, { 7.0, 2.0, -0.2 }),
		LeftEngine = Kit.comp("LeftWing", 700, 5, 17, { -4.4, 2.15, -2.6 }),
		RightEngine = Kit.comp("RightWing", 700, 5, 17, { 4.4, 2.15, -2.6 }),
		LeftFloat = Kit.comp("LeftWing", 90, 7, 24, { -12.2, -0.25, -0.1 }),
		RightFloat = Kit.comp("RightWing", 90, 7, 24, { 12.2, -0.25, -0.1 }),
		VerticalStab = Kit.comp("AftFuselage", 300, 5, 17, { 0, 3.4, 9.0 }),
		HorizontalStab = Kit.comp("VerticalStab", 280, 5, 17, { 0, 4.4, 9.4 }),
		NoseGear = Kit.comp("ForwardFuselage", 150, 6, 17, { 0, -2.6, -6.4 }, { gear = true }),
		LeftMainGear = Kit.comp("Fuselage", 350, 6, 19, { -1.75, -2.6, 0.7 }, { gear = true }),
		RightMainGear = Kit.comp("Fuselage", 350, 6, 19, { 1.75, -2.6, 0.7 }, { gear = true }),
	},
	gearLimits = { sinkDegrade = 3.4, sinkFail = 4.9, sinkDetach = 6.6, sideSpeedFail = 7 },
	gLimit = 3.3,

	hullPoints = {
		-- the planing hull: keel ahead of the step, the afterbody behind it, the chines
		-- either side and the bow (only wet when the nose dips)
		{ 0, KEEL, -4.0, "ForwardFuselage", "float" }, { 0, KEEL, -1.0, "Fuselage", "float" },
		{ 0, KEEL + 0.05, 1.9, "Fuselage", "float" }, { 0, KEEL + 0.22, 4.2, "AftFuselage", "float" },
		{ -1.0, KEEL + 0.3, -2.4, "ForwardFuselage", "float" }, { 1.0, KEEL + 0.3, -2.4, "ForwardFuselage", "float" },
		{ -1.0, KEEL + 0.3, 2.0, "Fuselage", "float" }, { 1.0, KEEL + 0.3, 2.0, "Fuselage", "float" },
		{ 0, KEEL + 0.6, -6.8, "ForwardFuselage", "float" },
		-- wingtip floats: dry when level, they catch the wing in a bank on the water
		{ -12.2, -0.6, -0.1, "LeftFloat", "float" }, { 12.2, -0.6, -0.1, "RightFloat", "float" },
		-- the rear hull, wings, engines (a ditching if these get wet)
		{ 0, -0.95, 7.2, "AftFuselage" }, { 0, -0.2, 10.4, "AftFuselage" },
		{ -14.0, 2.2, 0.2, "LeftWing" }, { 14.0, 2.2, 0.2, "RightWing" },
		{ -4.4, 1.5, -2.6, "LeftEngine" }, { 4.4, 1.5, -2.6, "RightEngine" },
	},

	cameras = {
		cockpit = { -0.45, 0.95, -6.9 },
		chaseDistance = 42,
		chaseHeight = 9,
	},

	geometry = {
		fuselage = {
			radius = 1.3, deck = 0.65,
			noseZ = -9.4, cabinStartZ = -6.6, forwardSplitZ = -3.8, aftSplitZ = 3.6,
			cabinEndZ = 5.0, tailEndZ = 11.0, tailUpsweep = 1.25, noseDrop = 0.3, tailTipFraction = 0.24,
			windowRows = {}, doors = { -5.2, 3.8 }, apu = false, bellyFairing = false, stripe = false,
			windscreen = { yLow = 0.55, yHigh = 1.25 },
			pitot = 0.6,
			-- the boat hull under the barrel: a V keel, chines and spray rails, the step
			-- behind the tank, and the tank doors and scoop probes
			boatHull = { bowZ = -8.6, stepZ = 2.2, keelY = KEEL, chineY = KEEL + 0.32, chineX = 1.12, tailZ = 8.5, doors = { -2.6, 1.4 }, probesZ = 2.5 },
		},
		wing = {
			mount = "high",
			rootLE = { 1.3, 2.0, -1.9 }, rootChord = 3.9, tipChord = 2.7, span = 13.0,
			sweepDeg = 0, dihedralDeg = 1, rootThickness = 0.55, tipThickness = 0.35,
			aileronStart = 0.66, flapEnd = 0.6, controlChord = 0.28, spoilers = false,
			wingletHeight = 0,
		},
		engine = { length = 4.0, radius = 0.55, kind = "turboprop", propRadius = 1.95, blades = 4 },
		hstab = {
			rootLE = { 0.2, 4.4, 8.4 }, rootChord = 2.6, tipChord = 1.7, span = 4.8,
			sweepDeg = 8, dihedralDeg = 0, thickness = 0.24, controlChord = 0.34,
		},
		vstab = {
			rootLE = { 0, 1.4, 6.2 }, rootChord = 4.4, tipChord = 2.4, height = 4.2,
			sweepDeg = 24, thickness = 0.34, controlChord = 0.32,
		},
		-- wingtip floats on single pylons up to the wing (no cross brace, no water rudder)
		floats = {
			x = 12.2, y = -0.25, z0 = -1.6, z1 = 1.5, halfWidth = 0.3, halfHeight = 0.34,
			struts = { { z = -0.4, x = 12.2, y = 2.05 }, { z = 0.6, x = 12.2, y = 2.05 } },
			brace = false, waterRudder = false, step = false,
		},
		seat = { -0.45, -0.1, -6.8 },
		livery = {
			body = { 250, 214, 40 },
			belly = { 200, 36, 32 },
			stripe = { 200, 36, 32 },
			accent = { 30, 30, 34 },
			tail = { 200, 36, 32 },
			wing = { 250, 214, 40 },
			engine = { 250, 214, 40 },
			hstab = { 250, 214, 40 },
			code = "FB-06",
		},
	},
}

return config
