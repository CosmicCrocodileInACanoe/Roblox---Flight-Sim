--!strict
-- Wildfires for the water bomber: where they burn, where dropped water lands, and how
-- much of it reaches a fire. Pure and deterministic (no Roblox), shared by the server's
-- FireService, the client's drop prediction and the offline tests.
--
-- Positions are studs (world x, z, ground y); amounts of water are kilograms.

local function req(name: string): any
	if script then
		return (require :: any)((script :: any).Parent[name])
	end
	return (require :: any)("./" .. name)
end

local Units = req("Units")
local WorldGen = req("WorldGen")
local Airports = req("Airports")
local Stunts = req("Stunts")

local Wildfire = {}

Wildfire.ACTIVE = 4 -- fires burning at once
Wildfire.SITE_COUNT = 10 -- candidate sites; burnt-out fires relight at another one
Wildfire.MIN_SPACING = 9000 -- studs between sites
Wildfire.RADIUS_M = 55 -- burning area radius (metres)
Wildfire.WATER_TO_PUT_OUT = 7000 -- kg reaching the fire (about one and a bit full loads)
Wildfire.RELIGHT_SECONDS = 75 -- a new fire starts this long after one goes out
Wildfire.REGROW_PER_SECOND = 0.004 -- a damped fire slowly flares up again (fraction/s)

local S = Units.STUDS_PER_METER

local function inAirport(x: number, z: number): boolean
	for _, id in Airports.order do
		local l = Airports.layout(id)
		local along, cross = Airports.toRunway(l, x, z)
		local latv = cross * l.side
		if math.abs(along) < l.halfLen + 5000 and latv > -(l.halfWidth + 2500) and latv < math.abs(l.terminalFar) + 2500 then
			return true
		end
		if math.abs(cross) < 1500 and math.abs(along) < l.halfLen + 22000 then
			return true -- approach paths
		end
	end
	return false
end

local function nearCity(x: number, z: number): boolean
	for _, c in WorldGen.cities do
		if (x - c.x) ^ 2 + (z - c.z) ^ 2 < (c.radius * 2.6) ^ 2 then
			return true
		end
	end
	return false
end

-- Candidate fire sites: wooded, dry land inside the detailed part of the map, away from
-- airports, towns and the Stunts course, spread out. Same list on server and client.
local cachedSites: { any }? = nil
function Wildfire.sites(): { any }
	if cachedSites then
		return cachedSites
	end
	local b = WorldGen.INNER
	local candidates = {}
	local step = 2500
	local x = b.minX + 3000
	while x < b.maxX - 3000 do
		local z = b.minZ + 3000
		while z < b.maxZ - 3000 do
			local px = x + (WorldGen.rand(x, z, 301) - 0.5) * 1500
			local pz = z + (WorldGen.rand(x, z, 302) - 0.5) * 1500
			local forest = WorldGen.fbm(px / 5000, pz / 5000, 2, 77)
			local h = WorldGen.height(px, pz)
			if forest > 0.18 and h > 40 and h < 1800 and not inAirport(px, pz) and not nearCity(px, pz) and not Stunts.inCourseArea(px, pz, 600) then
				table.insert(candidates, { x = px, z = pz, score = WorldGen.rand(px, pz, 303) })
			end
			z += step
		end
		x += step
	end
	table.sort(candidates, function(a, c)
		return a.score < c.score
	end)
	local out = {}
	for _, c in candidates do
		local ok = true
		for _, o in out do
			if (o.x - c.x) ^ 2 + (o.z - c.z) ^ 2 < Wildfire.MIN_SPACING ^ 2 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(out, { id = #out + 1, x = c.x, z = c.z, y = WorldGen.meshHeight(c.x, c.z) })
			if #out >= Wildfire.SITE_COUNT then
				break
			end
		end
	end
	cachedSites = out
	return out
end

-- Where a load released at (px, py, pz) (studs) moving at (vx, vz) (studs/s) hits the
-- ground at height `groundY` (studs). Returns the impact x, z. Water falls about like a
-- heavy, draggy blob: it slows quickly in the air, so it lands well short of where a
-- bomb would.
function Wildfire.impactPoint(px: number, py: number, pz: number, vx: number, vz: number, groundY: number): (number, number)
	local hM = math.max(0, (py - groundY) / S)
	-- fall time with drag (the curtain soon stops speeding up)
	local t = math.sqrt(2 * hM / Units.G) * (1 + hM / 260)
	-- horizontal speed decays with a ~1.6 s time constant
	local tau = 1.6
	local k = tau * (1 - math.exp(-t / tau))
	return px + vx * k, pz + vz * k
end

-- Share of the water that reaches the ground as a useful curtain. Low and slow drops
-- work best; from high up much of it blows away as mist.
function Wildfire.dropEfficiency(heightM: number): number
	return math.clamp(1 - (heightM - 40) / 300, 0.15, 1)
end

-- Radius (m) the curtain spreads over on the ground: wider when dropped from higher.
function Wildfire.footprintRadius(heightM: number): number
	return math.clamp(25 + heightM * 0.12, 25, 70)
end

-- Kilograms of a drop that reach one fire. dist: metres from the impact point to the
-- fire's centre.
function Wildfire.waterOnFire(kg: number, distM: number, heightM: number, fireRadiusM: number?): number
	local radius = fireRadiusM or Wildfire.RADIUS_M
	local spread = Wildfire.footprintRadius(heightM)
	local reach = radius + spread
	if distM >= reach then
		return 0
	end
	local overlap = if distM <= radius then 1 else 1 - (distM - radius) / spread
	return kg * Wildfire.dropEfficiency(heightM) * overlap
end

-- One fire's state as kept by the server and mirrored to clients through attributes.
function Wildfire.newFire(site: any): any
	return { site = site, strength = 1, burning = true }
end

-- Apply water (kg reaching it) to a fire. Returns true when that put it out.
function Wildfire.douse(fire: any, kgOnFire: number): boolean
	if not fire.burning or kgOnFire <= 0 then
		return false
	end
	fire.strength -= kgOnFire / Wildfire.WATER_TO_PUT_OUT
	if fire.strength <= 0 then
		fire.strength = 0
		fire.burning = false
		return true
	end
	return false
end

-- A fire nobody is fighting slowly grows back to full strength.
function Wildfire.regrow(fire: any, dt: number)
	if fire.burning then
		fire.strength = math.min(1, fire.strength + Wildfire.REGROW_PER_SECOND * dt)
	end
end

return Wildfire
