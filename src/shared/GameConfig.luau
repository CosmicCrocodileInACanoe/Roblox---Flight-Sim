--!strict
-- Game-wide tunables shared by server and client.

local GameConfig = {}

GameConfig.VERSION = "0.1.0-m1"

GameConfig.Remotes = {
	-- client -> server
	"RequestSpawn",
	"RequestReset",
	"ControllerReady",
	"ReportDamage",
	"ReportSystems",
	"ReportTouchdown",
	"ReportImpact", -- (model, component, pointBodyM: Vector3, dirBody: Vector3, dv)
	"ReportSection", -- (model, component, sectionId, dv, cause: "event"?)
	"WaterDrop", -- (model, impactX, impactZ (studs), kg, dropHeightM) water bomber drops
	"RequestRepair", -- () Fix all: every part back on, good as new, right where the aircraft is
	"AircraftRepaired", -- server -> owner (model): Fix all swapped the parts, reset damage in place
	"ReportCrash", -- (model, worldPos: Vector3, dv) the airframe was destroyed: explode + crater
	"ReportEmergency", -- (model, situation: "land_crash"|"water_crash"|"ditch") call the rescue services
	-- server -> client
	"AircraftAssigned",
	"MissionUpdate",
	"LandingResult",
	"Notify",
	"CrashFx", -- (kind: "sparks"|"shards"|"dust", worldPos: Vector3, intensity, velocity: Vector3?)
	"DentFx", -- (model, component, pointBodyM: Vector3, dirBody: Vector3, depthM, dv) -> mesh skins
	"StuntsUpdate", -- (data) Stunts race state: next ring, times, events, results
	"Emergency", -- (incident) fire trucks, ambulances, police, boats, helicopters, ferries set off
	"EmergencyClear", -- (incidentId) Fix all / Reset / left: the responders go home
}

GameConfig.CollisionGroups = {
	Aircraft = "Aircraft",
	Debris = "Debris",
	World = "Default",
}

-- Aircraft-vs-aircraft collisions between different players. Spawn protection keeps
-- freshly spawned aircraft non-colliding with other aircraft for a few seconds.
GameConfig.aircraftCollide = true
GameConfig.spawnProtectionSeconds = 8

GameConfig.debris = {
	maxPiecesPerPlayer = 24,
	maxPiecesTotal = 80,
	lifetime = 75, -- seconds
}

-- BeamNG-style crash feel (see shared/Crash.luau for per-component profiles).
GameConfig.crash = {
	-- On (default): parts dent and bend first, then tear off when their health runs out,
	-- so a real crash breaks the plane apart (wings, engines, tail, nose and tail sections).
	-- Off: planes bend, crumple and collapse but stay in one piece; parts tear off only in
	-- truly extreme hits (Damage.EXTREME_FACTOR x their destroy speed).
	breakApart = true,
	-- Craters where a destroyed aircraft hits the ground (server, shared by everyone).
	crater = {
		minDv = 10, -- m/s; softer wrecks just explode
		maxCraters = 12, -- oldest goes first
		lifetime = 900, -- s
	},
	repairCooldown = 2, -- s between Fix all presses
	extremeSectionFactor = 2.0, -- break-apart off: tearing a section needs this x the dv
	impactReportMinInterval = 0.12, -- s between dent reports for one component
	maxCrumplesPerSecond = 12, -- server, per player
	maxSplitsPerSecond = 6, -- server, debris secondary breakups across the game
	splitPush = 6, -- m/s separation push for a freshly split piece
	clientMaxShards = 60, -- client-only cosmetic shards alive at once
	shardLifetime = 6, -- s
	scuffDarken = 0.35, -- how much a fully dented part darkens
	-- Client-side EditableMesh skins (BeamNG-style vertex dents). Needs "Allow Mesh / Image
	-- APIs" in Game Settings > Security. Falls back to part dents and bending without it.
	meshSkins = {
		enabled = true,
		maxSkins = 6, -- live skins per client (memory; some devices cap EditableMeshes at ~8)
		newPerDent = 2, -- skins created per dent at most
		grid = 4, -- subdivisions per face edge: 6*(n+1)^2 vertices (150 at 4)
		maxOffsetFrac = 0.45, -- a vertex never moves more than this * the part's smallest size
		radiusScale = 1.6, -- dent radius on the skin vs the profile's dentRadius
	},
}

GameConfig.rateLimits = {
	spawnSeconds = 2.0,
	damageReportsPerSecond = 30,
	systemsReportsPerSecond = 8,
}

-- Server sanity limits on replicated aircraft motion (m/s, m/s^2).
GameConfig.limits = {
	-- Ground speed, m/s. Beyond this the server resets the aircraft. It has to clear the
	-- Arrowstar's Mach 2+ dash (about 600 m/s high up) plus a strong tailwind; at 360 the
	-- server used to reset it at about 700 kt, long before Mach 2.
	maxSpeed = 900,
	maxTeleportStudsPerSample = 1800,
}

GameConfig.modes = {
	{ id = "free", label = "Free Flight" },
	{ id = "airline", label = "Airline Flight" },
	{ id = "sandbox", label = "Crash / Test Sandbox" },
	{ id = "stunts", label = "Stunts: Ring Race" },
}

GameConfig.weather = {
	{ id = "calm", label = "Calm", windKts = 0, windFrom = 270, gustKts = 0, turbulence = 0, fog = 0 },
	{ id = "breeze", label = "Light breeze", windKts = 6, windFrom = 250, gustKts = 2, turbulence = 0.15, fog = 0 },
	{ id = "crosswind", label = "Crosswind 15 kt", windKts = 15, windFrom = 0, gustKts = 4, turbulence = 0.3, fog = 0 },
	{ id = "gusty", label = "Gusty 20G30", windKts = 20, windFrom = 300, gustKts = 10, turbulence = 0.6, fog = 0.1 },
	{ id = "storm", label = "Storm", windKts = 28, windFrom = 200, gustKts = 14, turbulence = 1.0, fog = 0.45 },
}

GameConfig.timeOfDay = {
	{ id = "morning", label = "Morning", clock = 7.4 },
	{ id = "noon", label = "Midday", clock = 13.0 },
	{ id = "sunset", label = "Sunset", clock = 18.1 },
	{ id = "night", label = "Night", clock = 22.5 },
}

GameConfig.failures = {
	{ id = "engine1", label = "Left engine failure" },
	{ id = "engine2", label = "Right engine failure" },
	{ id = "elevatorJam", label = "Elevator jammed" },
	{ id = "aileronJam", label = "Ailerons jammed" },
	{ id = "rudderJam", label = "Rudder jammed" },
	{ id = "gearStuck", label = "Gear stuck" },
	{ id = "flapsJam", label = "Flaps jammed" },
	{ id = "fuelLeak", label = "Fuel leak" },
	{ id = "leftWingDamage", label = "Left wing damaged" },
}

return GameConfig
