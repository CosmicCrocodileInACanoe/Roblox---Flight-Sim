--!strict
-- Units and atmosphere.
--
-- Convention used everywhere in this project:
--   * All flight physics is computed in SI units (metres, kilograms, seconds, newtons).
--   * The Roblox world is measured in studs. 1 stud = 0.28 m (Roblox's own avatar scale).
--   * Workspace.Gravity is set to 9.80665 / 0.28 = 35.02 studs/s^2 so that free fall in
--     the engine matches real gravity at this scale.
--   * Conversions between SI and studs happen ONLY at the boundary (FlightController on
--     the client, world builders on the server). Pure modules never see studs.

local Units = {}

Units.METERS_PER_STUD = 0.28
Units.STUDS_PER_METER = 1 / 0.28
Units.G = 9.80665
Units.GRAVITY_STUDS = 9.80665 / 0.28

Units.KTS_PER_MPS = 1.943844
Units.MPS_PER_KT = 1 / 1.943844
Units.FT_PER_M = 3.280840
Units.FPM_PER_MPS = 196.8504
Units.NM_PER_M = 1 / 1852

Units.SEA_LEVEL_DENSITY = 1.225 -- kg/m^3
Units.SEA_LEVEL_TEMP = 288.15 -- K
Units.SPEED_OF_SOUND_SL = 340.29 -- m/s

-- International Standard Atmosphere, troposphere only (valid to 11 km, clamped).
function Units.airDensity(altitudeM: number): number
	local h = math.clamp(altitudeM, -500, 11000)
	return 1.225 * (1 - 2.25577e-5 * h) ^ 4.25588
end

function Units.densityRatio(altitudeM: number): number
	return Units.airDensity(altitudeM) / 1.225
end

function Units.speedOfSound(altitudeM: number): number
	local h = math.clamp(altitudeM, -500, 11000)
	local t = 288.15 - 0.0065 * h
	return math.sqrt(1.4 * 287.05 * t)
end

-- Indicated (equivalent) airspeed from true airspeed.
function Units.tasToIas(tas: number, altitudeM: number): number
	return tas * math.sqrt(Units.densityRatio(altitudeM))
end

-- Compass heading in degrees (0 = north = world -Z, 90 = east = world +X)
-- from a horizontal world direction (x, z).
function Units.headingFromXZ(x: number, z: number): number
	local h = math.deg(math.atan2(x, -z))
	if h < 0 then
		h += 360
	end
	return h
end

-- Horizontal unit direction (x, z) for a compass heading in degrees.
function Units.xzFromHeading(headingDeg: number): (number, number)
	local r = math.rad(headingDeg)
	return math.sin(r), -math.cos(r)
end

return Units
