--!strict
-- Meridian 200: original, unbranded narrow-body twinjet (class: "Narrow-body twinjet A").
-- The forgiving starter airliner. Numbers are in the ballpark of a 150-180 seat
-- medium-haul twinjet at a typical landing weight, tuned for game feel.
--
-- BODY AXES (used by every number below):
--   x = right wing, y = up, z = toward the tail (Roblox object space; the nose points -z).
--   The origin is the centre of mass. Units are SI (metres, kg, N, s, radians unless *Deg).
--
-- TUNING ASSUMPTIONS (documented so they can be revisited during playtests):
--   * Mass 62 t is held constant apart from fuel burn and detached parts.
--   * Each wing panel represents one half-wing at ~45% semispan (strip theory, 1 strip/side).
--   * Tailplane lift slope is reduced by 40% to stand in for wing downwash.
--   * Flap/slat effects are lumped into Cl0 / Cd0 / stall-angle increments per notch.
--   * Gear spring rates are derived at runtime from static compression and damping ratio.

local rad = math.rad

local config = {
	id = "meridian200",
	displayName = "Meridian 200",
	class = "Narrow-body twinjet A",
	description = "Medium-haul twinjet. Stable, forgiving and the recommended first aircraft.",
	unlocked = true,

	mass = 62000, -- kg (effective, including initial fuel)
	-- Principal moments of inertia (kg m^2) about the body axes.
	inertia = { roll = 1.6e6, pitch = 3.8e6, yaw = 5.2e6 },

	fuel = {
		capacity = 18000, -- kg
		initial = 7000, -- kg (already included in `mass`)
	},

	speeds = { -- knots, used for prompts and warnings only (not for physics)
		rotate = 140,
		v2 = 150,
		approach = 140,
		vref = 133,
		cruise = 250,
		vmo = 340,
		flapLimits = { 999, 230, 215, 195, 177 },
		gearLimit = 270,
	},

	-- Aerodynamic model ------------------------------------------------------------
	aero = {
		wingSpan = 34.1,
		wingArea = 122.4,
		meanChord = 4.2,
		-- Lifting panels. `normal` is the panel lift axis in body axes, `incidence` adds to
		-- local angle of attack, `clAlpha` is the finite-wing lift slope (per radian).
		panels = {
			{
				name = "LeftWing", component = "LeftWing", role = "wing", side = -1,
				pos = { -7.6, -0.9, 0.55 }, normal = { math.sin(rad(5)), math.cos(rad(5)), 0 },
				area = 61.2, aspect = 9.5, oswald = 0.80,
				clAlpha = 5.19, cl0 = 0.25, incidence = rad(2.0),
				alphaStall = rad(14.5), stallWidth = rad(4.0),
				cd0 = 0.0085, cm0 = -0.05, chord = 4.2,
			},
			{
				name = "RightWing", component = "RightWing", role = "wing", side = 1,
				pos = { 7.6, -0.9, 0.55 }, normal = { -math.sin(rad(5)), math.cos(rad(5)), 0 },
				area = 61.2, aspect = 9.5, oswald = 0.80,
				clAlpha = 5.19, cl0 = 0.25, incidence = rad(2.0),
				alphaStall = rad(14.5), stallWidth = rad(4.0),
				cd0 = 0.0085, cm0 = -0.05, chord = 4.2,
			},
			{
				name = "Tailplane", component = "HorizontalStab", role = "hstab", side = 0,
				pos = { 0, 0.9, 16.6 }, normal = { 0, 1, 0 },
				area = 31.0, aspect = 5.0, oswald = 0.75,
				clAlpha = 4.49 * 0.6, cl0 = 0.0, incidence = rad(-3.0),
				alphaStall = rad(17), stallWidth = rad(5),
				cd0 = 0.008, cm0 = 0, chord = 2.5,
			},
			{
				name = "Fin", component = "VerticalStab", role = "vstab", side = 0,
				pos = { 0, 4.8, 16.0 }, normal = { 1, 0, 0 },
				area = 21.5, aspect = 1.9, oswald = 0.70,
				clAlpha = 3.0, cl0 = 0.0, incidence = 0,
				alphaStall = rad(20), stallWidth = rad(6),
				cd0 = 0.008, cm0 = 0, chord = 4.0,
			},
		},
		-- Fuselage/nacelle/misc drag as CdA (m^2) per body axis, applied at `bodyDragPos`.
		bodyDrag = { x = 80, y = 75, z = 1.35 },
		bodyDragPos = { 0, 0, -1.0 },
		gearDragArea = 3.4, -- CdA when gear fully down
		-- Extra (small) aerodynamic rotational damping, N m per (rad/s) per (kg/m^3 * m/s).
		extraDamping = { roll = 400, pitch = 2000, yaw = 2500 },

		-- Control surfaces: max deflection and lift-coefficient change per radian on the
		-- panel they act on.
		elevator = { maxDeflection = rad(25), clPerRad = 1.7 },
		aileron = { maxDeflection = rad(20), clPerRad = 0.33 },
		rudder = { maxDeflection = rad(30), clPerRad = 1.4 },
		trim = { maxDeflection = rad(13) }, -- elevator trim range

		-- Flaps per notch (index 1 = UP). Increments apply to wing panels.
		flaps = {
			labels = { "UP", "1", "2", "3", "FULL" },
			deflectionDeg = { 0, 8, 15, 25, 38 },
			dCl = { 0, 0.22, 0.40, 0.58, 0.75 },
			dCd = { 0, 0.004, 0.012, 0.025, 0.045 },
			dStallDeg = { 0, 0.5, 0.5, 0, 0 }, -- slats offset the flap stall-angle loss
			dCm = { 0, -0.02, -0.035, -0.05, -0.07 },
			travelTime = 2.5, -- seconds per notch
		},
		speedbrake = { dCl = -0.30, dCd = 0.035 },
		groundEffect = true,
	},

	-- Engines ----------------------------------------------------------------------
	engines = {
		{
			name = "LeftEngine", component = "LeftEngine",
			pos = { -5.75, -2.3, -3.0 }, axis = { 0, 0, -1 },
			maxThrust = 120000, idleN1 = 21, spoolUpTau = 2.2, spoolDownTau = 1.4,
			startTime = 12, reverseFraction = 0.45,
			fuelFlowIdle = 0.11, fuelFlowMax = 1.05, -- kg/s
		},
		{
			name = "RightEngine", component = "RightEngine",
			pos = { 5.75, -2.3, -3.0 }, axis = { 0, 0, -1 },
			maxThrust = 120000, idleN1 = 21, spoolUpTau = 2.2, spoolDownTau = 1.4,
			startTime = 12, reverseFraction = 0.45,
			fuelFlowIdle = 0.11, fuelFlowMax = 1.05,
		},
	},

	-- Landing gear (raycast suspension) ------------------------------------------------
	gear = {
		retractTime = 7,
		units = {
			{
				name = "NoseGear", component = "NoseGear",
				pos = { 0, -1.4, -12.5 }, strutLength = 2.05, wheelRadius = 0.55, travel = 0.45,
				staticCompression = 0.33, dampingRatio = 0.65,
				steerMaxDeg = 65, steerHighSpeedDeg = 6, brakes = false,
				retractAxis = "x", retractAngleDeg = 95, wheels = 2, wheelSpacing = 0.55,
			},
			{
				name = "LeftMainGear", component = "LeftMainGear",
				pos = { -3.8, -1.6, 0.9 }, strutLength = 1.9, wheelRadius = 0.6, travel = 0.5,
				staticCompression = 0.36, dampingRatio = 0.65,
				steerMaxDeg = 0, steerHighSpeedDeg = 0, brakes = true,
				retractAxis = "z", retractAngleDeg = 88, wheels = 2, wheelSpacing = 0.9,
			},
			{
				name = "RightMainGear", component = "RightMainGear",
				pos = { 3.8, -1.6, 0.9 }, strutLength = 1.9, wheelRadius = 0.6, travel = 0.5,
				staticCompression = 0.36, dampingRatio = 0.65,
				steerMaxDeg = 0, steerHighSpeedDeg = 0, brakes = true,
				retractAxis = "z", retractAngleDeg = -88, wheels = 2, wheelSpacing = 0.9,
			},
		},
		friction = { rolling = 0.02, brake = 0.55, lateral = 0.75 },
	},

	-- Structure / damage -------------------------------------------------------------
	-- impactThreshold: local velocity change (m/s) that starts to hurt.
	-- impactDestroy:   local velocity change that destroys the component in one hit.
	-- detachable:      at zero health the component separates as physical debris.
	components = {
		Fuselage = { parent = nil, mass = 0, impactThreshold = 9, impactDestroy = 36, detachable = false, ref = { 0, -1.5, 0 } },
		ForwardFuselage = { parent = "Fuselage", mass = 6000, impactThreshold = 8, impactDestroy = 30, detachable = true, ref = { 0, -1.2, -12 } },
		AftFuselage = { parent = "Fuselage", mass = 5000, impactThreshold = 7, impactDestroy = 28, detachable = true, ref = { 0, -0.6, 13 } },
		LeftWing = { parent = "Fuselage", mass = 4500, impactThreshold = 6, impactDestroy = 22, detachable = true, ref = { -10, -0.6, 2 } },
		RightWing = { parent = "Fuselage", mass = 4500, impactThreshold = 6, impactDestroy = 22, detachable = true, ref = { 10, -0.6, 2 } },
		LeftEngine = { parent = "LeftWing", mass = 2400, impactThreshold = 4, impactDestroy = 16, detachable = true, ref = { -5.75, -2.8, -3 } },
		RightEngine = { parent = "RightWing", mass = 2400, impactThreshold = 4, impactDestroy = 16, detachable = true, ref = { 5.75, -2.8, -3 } },
		HorizontalStab = { parent = "AftFuselage", mass = 700, impactThreshold = 5, impactDestroy = 18, detachable = true, ref = { 0, 0.9, 16.6 } },
		VerticalStab = { parent = "AftFuselage", mass = 600, impactThreshold = 5, impactDestroy = 18, detachable = true, ref = { 0, 4.8, 16 } },
		NoseGear = { parent = "ForwardFuselage", mass = 450, impactThreshold = 6, impactDestroy = 18, detachable = true, ref = { 0, -3.5, -12.5 }, gear = true },
		LeftMainGear = { parent = "LeftWing", mass = 1400, impactThreshold = 6, impactDestroy = 20, detachable = true, ref = { -3.8, -3.8, 0.9 }, gear = true },
		RightMainGear = { parent = "RightWing", mass = 1400, impactThreshold = 6, impactDestroy = 20, detachable = true, ref = { 3.8, -3.8, 0.9 }, gear = true },
	},
	-- Touchdown sink rates (m/s) for gear damage. ~3 m/s = 600 fpm.
	gearLimits = { sinkDegrade = 3.3, sinkFail = 4.8, sinkDetach = 6.5, sideSpeedFail = 9 },
	gLimit = 3.8, -- sustained load factor beyond which wings take progressive damage

	-- Points checked against the water surface for ditching (body axes).
	-- { x, y, z, component }
	hullPoints = {
		{ 0, -1.9, -16, "ForwardFuselage" }, { 0, -1.9, -8, "ForwardFuselage" }, { 0, -1.9, 0, "Fuselage" },
		{ 0, -1.9, 8, "AftFuselage" }, { 0, -1.0, 17, "AftFuselage" },
		{ -16.5, 0.4, 7, "LeftWing" }, { 16.5, 0.4, 7, "RightWing" },
		{ -5.75, -3.3, -3, "LeftEngine" }, { 5.75, -3.3, -3, "RightEngine" },
	},

	cameras = {
		cockpit = { -0.55, 0.85, -15.3 },
		chaseDistance = 62,
		chaseHeight = 12,
	},

	-- Visual geometry for the parametric airliner builder (metres, body axes). -----------
	geometry = {
		fuselage = {
			radius = 1.98,
			noseZ = -17.6, cabinStartZ = -13.4, forwardSplitZ = -6.0, aftSplitZ = 7.5,
			cabinEndZ = 9.0, tailEndZ = 20.2, tailUpsweep = 1.35,
		},
		wing = {
			rootLE = { 1.9, -1.05, -3.6 }, rootChord = 6.2, tipChord = 1.6, span = 15.2,
			sweepDeg = 27, dihedralDeg = 5, rootThickness = 0.75, tipThickness = 0.22,
			segments = 4, aileronStart = 0.68, flapEnd = 0.6, controlChord = 0.26,
			wingletHeight = 2.2,
		},
		engine = { length = 4.6, radius = 1.08, kind = "turbofan" },
		hstab = {
			rootLE = { 0.9, 0.9, 14.4 }, rootChord = 3.6, tipChord = 1.3, span = 6.0,
			sweepDeg = 32, dihedralDeg = 6, thickness = 0.35, controlChord = 0.32,
		},
		vstab = {
			rootLE = { 0, 1.9, 12.6 }, rootChord = 5.8, tipChord = 2.0, height = 6.4,
			sweepDeg = 38, thickness = 0.4, controlChord = 0.32,
		},
		seat = { -0.55, -0.15, -15.0 },
		livery = {
			body = { 242, 243, 245 },
			belly = { 196, 200, 206 },
			stripe = { 28, 92, 172 },
			accent = { 245, 176, 40 },
			tail = { 28, 92, 172 },
			wing = { 205, 208, 214 },
			engine = { 230, 231, 235 },
			airline = "SKYLINE",
		},
	},
}

return config
