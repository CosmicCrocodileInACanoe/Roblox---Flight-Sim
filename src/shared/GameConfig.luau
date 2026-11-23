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
	"ReportSection", -- (model, component, sectionId, dv)
	-- server -> client
	"AircraftAssigned",
	"MissionUpdate",
	"LandingResult",
	"Notify",
	"CrashFx", -- (kind: "sparks"|"shards"|"dust", worldPos: Vector3, intensity, velocity: Vector3?)
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
	impactReportMinInterval = 0.12, -- s between dent reports for one component
	maxCrumplesPerSecond = 12, -- server, per player
	maxSplitsPerSecond = 6, -- server, debris secondary breakups across the game
	splitPush = 6, -- m/s separation push for a freshly split piece
	clientMaxShards = 60, -- client-only cosmetic shards alive at once
	shardLifetime = 6, -- s
	scuffDarken = 0.35, -- how much a fully dented part darkens
}

GameConfig.rateLimits = {
	spawnSeconds = 2.0,
	damageReportsPerSecond = 30,
	systemsReportsPerSecond = 8,
}

-- Server sanity limits on replicated aircraft motion (m/s, m/s^2).
GameConfig.limits = {
	maxSpeed = 360, -- well above Vmo; beyond this the server resets the aircraft
	maxTeleportStudsPerSample = 1800,
}

GameConfig.modes = {
	{ id = "free", label = "Free Flight" },
	{ id = "airline", label = "Airline Flight" },
	{ id = "sandbox", label = "Crash / Test Sandbox" },
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
