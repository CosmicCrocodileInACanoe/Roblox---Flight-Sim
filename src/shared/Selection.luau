--!strict
-- Pure menu/spawn selection logic, shared by the menu (what to offer) and the server
-- (what to accept). No Roblox APIs, so tests/test_selection.luau can check it offline.
--
-- Rules:
--   * The departure airport decides which ground spawns are offered.
--   * Every "Start at" list puts runways first, so the default is always a runway.
--   * An aircraft is only offered runways long enough and gates wide enough for it.
--   * Airline mode only offers routes that leave from the chosen airport.

local function req(name: string): any
	if script then
		return (require :: any)((script :: any).Parent[name])
	end
	return (require :: any)("./" .. name)
end
local Airports = req("Airports")
local Units = req("Units")

local Selection = {}

-- Extra card facts the aircraft configs don't carry (approximate, for the menu only).
Selection.SEATS = { kestrel72 = 70, meridian200 = 180, atlas400 = 410, celestia800 = 550 }
-- 1 = easiest. Kestrel is the gentlest; the jumbos need more planning.
Selection.DIFFICULTY = { kestrel72 = 1, meridian200 = 2, atlas400 = 3, celestia800 = 4 }
Selection.DIFFICULTY_LABELS = { "Easiest", "Easy", "Tricky", "Expert" }
-- Runway length each type needs to take off and land with a margin (metres). The
-- fleet tests check every type lifts off within 85% of the shortest (2,600 m) runway.
Selection.MIN_RUNWAY_M = { kestrel72 = 1200, meridian200 = 2000, atlas400 = 2400, celestia800 = 2500 }
local DEFAULT_MIN_RUNWAY_M = 2600

-- Gate fit: wingtip clearance between neighbouring stands (metres, ICAO code F uses 7.5)
-- and the margin kept from the jet bridges / apron edge.
Selection.GATE_WINGTIP_CLEARANCE_M = 7.5
Selection.GATE_EDGE_MARGIN_M = 5
-- Stand geometry, metres from the runway centreline (matches Airports.layout and the
-- world builder: stand centre 340 m, jet bridges reach 12 m out from the terminal).
local GATE_LATERAL_M = 340
local JET_BRIDGE_DEPTH_M = 12

local SPM = Units.STUDS_PER_METER

-- Size of an aircraft in metres: wingspan, nose (forward of CoM) and tail (aft of CoM).
function Selection.dimensions(cfg: any): (number, number, number)
	local span = (cfg.aero and cfg.aero.wingSpan) or 40
	local fus = cfg.geometry and cfg.geometry.fuselage
	local nose = if fus and fus.noseZ then -fus.noseZ else span * 0.5
	local tail = if fus and fus.tailEndZ then fus.tailEndZ else span * 0.5
	return span, nose, tail
end

function Selection.minRunwayM(cfg: any): number
	return cfg.minRunwayM or Selection.MIN_RUNWAY_M[cfg.id] or DEFAULT_MIN_RUNWAY_M
end

function Selection.runwayFits(cfg: any, airportId: string): boolean
	local ap = Airports.list[airportId]
	return ap ~= nil and ap.runway.lengthM >= Selection.minRunwayM(cfg)
end

-- Why a gate stand at this airport cannot take this aircraft, or nil if it fits.
function Selection.gateProblem(cfg: any, airportId: string): string?
	local ap = Airports.list[airportId]
	if not ap then
		return "unknown airport"
	end
	local l = Airports.layout(airportId)
	local span, nose, tail = Selection.dimensions(cfg)
	if ap.gateSpacingM - span < Selection.GATE_WINGTIP_CLEARANCE_M then
		return "wings too wide for the gate spacing"
	end
	local terminalNearM = math.abs(l.terminalNear) / SPM
	local apronNearM = math.abs(l.apronNear) / SPM
	if GATE_LATERAL_M + tail > terminalNearM - JET_BRIDGE_DEPTH_M - Selection.GATE_EDGE_MARGIN_M then
		return "tail would hit the jet bridges"
	end
	if GATE_LATERAL_M - nose < apronNearM + Selection.GATE_EDGE_MARGIN_M then
		return "nose would stick out over the taxiway"
	end
	local outer = 0
	for _, g in l.gates do
		outer = math.max(outer, math.abs(g.along) / SPM)
	end
	if outer + span * 0.5 > l.apronHalfLen / SPM - Selection.GATE_EDGE_MARGIN_M then
		return "end gates are too close to the apron edge"
	end
	return nil
end

function Selection.gateFits(cfg: any, airportId: string): boolean
	return Selection.gateProblem(cfg, airportId) == nil
end

-- Routes (from Airports.routes) that leave from this airport, in list order.
function Selection.routesFrom(airportId: string): { any }
	local out = {}
	for _, r in Airports.routes do
		if r.from == airportId then
			table.insert(out, r)
		end
	end
	return out
end

-- Destination choices for a mode. Airline: the route destinations (never empty while a
-- route exists). Free flight / sandbox: the same airports plus `false` = no destination.
function Selection.destinations(airportId: string, mode: string): { any }
	local out: { any } = {}
	for _, r in Selection.routesFrom(airportId) do
		table.insert(out, r.to)
	end
	if mode ~= "airline" then
		table.insert(out, false)
	end
	return out
end

-- The spawn points offered for this airport, aircraft and mode, runways first, then
-- gates, then approaches, then (outside airline mode) the in-flight sandbox starts.
-- In airline mode the approach start skips to the end of the route, so it is the
-- approach into the destination; otherwise it is the approach into this airport.
-- Never empty: if no runway is long enough, the runways are still offered.
function Selection.spawnList(airportId: string, cfg: any, mode: string, destination: string?): { any }
	if not Airports.list[airportId] then
		airportId = Airports.order[1]
	end
	local runways, gates = {}, {}
	for _, s in Airports.spawnPoints(airportId) do
		if s.kind == "runway" then
			table.insert(runways, s)
		elseif s.kind == "gate" then
			table.insert(gates, s)
		end
	end
	local out = {}
	local runwayOk = Selection.runwayFits(cfg, airportId)
	for _, s in runways do
		table.insert(out, s)
	end
	if runwayOk and Selection.gateFits(cfg, airportId) then
		for _, s in gates do
			table.insert(out, s)
		end
	end
	local approachInto = airportId
	if mode == "airline" and destination and destination ~= airportId and Airports.list[destination] then
		approachInto = destination
	end
	if Selection.runwayFits(cfg, approachInto) then
		for _, s in Airports.spawnPoints(approachInto) do
			if s.kind == "approach" then
				table.insert(out, s)
			end
		end
	end
	if mode ~= "airline" then
		for _, s in Airports.sandboxSpawns() do
			table.insert(out, s)
		end
	end
	return out
end

function Selection.defaultSpawn(airportId: string, cfg: any, mode: string, destination: string?): any
	return Selection.spawnList(airportId, cfg, mode, destination)[1]
end

-- The spawn the server should use: the requested one if it is offered for this
-- airport/aircraft/mode, otherwise the first runway of the airport.
function Selection.resolveSpawn(spawnId: any, airportId: string, cfg: any, mode: string, destination: string?): any
	local list = Selection.spawnList(airportId, cfg, mode, destination)
	if type(spawnId) == "string" then
		for _, s in list do
			if s.id == spawnId then
				return s
			end
		end
	end
	return list[1]
end

-- Unlocked aircraft ids in registry order.
function Selection.flyableAircraft(registry: any): { string }
	local out = {}
	for _, id in registry.order do
		local cfg = registry.types[id]
		if cfg and cfg.unlocked then
			table.insert(out, id)
		end
	end
	return out
end

-- Friendly, short label for the "Start at" row.
function Selection.spawnLabel(sp: any): string
	local ap = Airports.list[sp.airport]
	local city = if ap then ap.city else sp.airport
	if sp.kind == "runway" then
		local ident = string.match(sp.id, "rwy(%w+)$") or "?"
		return `Runway {ident}: ready for take-off`
	elseif sp.kind == "gate" then
		local n = string.match(sp.id, "gate(%d+)$") or "?"
		return `Gate {n}: parked, engines off`
	elseif sp.kind == "approach" then
		local ident = string.match(sp.id, "final(%w+)$") or "?"
		return `In the air: landing at {city}, runway {ident}`
	end
	return sp.label
end

-- Everything the aircraft card shows.
function Selection.card(cfg: any)
	local span, nose, tail = Selection.dimensions(cfg)
	local d = Selection.DIFFICULTY[cfg.id] or 2
	return {
		name = cfg.displayName,
		class = cfg.class or "",
		description = cfg.description or "",
		seats = Selection.SEATS[cfg.id],
		cruiseKt = cfg.speeds and cfg.speeds.cruise,
		spanM = span,
		lengthM = nose + tail,
		difficulty = d,
		difficultyLabel = Selection.DIFFICULTY_LABELS[d] or "",
	}
end

return Selection
