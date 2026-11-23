--!strict
-- Server entry point: physics settings, collision groups, remotes, world generation,
-- and service start-up.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Units = require(Shared.Units)
local GameConfig = require(Shared.GameConfig)
local Airports = require(Shared.Airports)

local Server = script.Parent
local AircraftService = require(Server.AircraftService)
local MissionService = require(Server.MissionService)
local ProgressService = require(Server.ProgressService)
local TerrainBuilder = require(Server.World.TerrainBuilder)
local AirportBuilder = require(Server.World.AirportBuilder)
local CityBuilder = require(Server.World.CityBuilder)
local StuntCourseBuilder = require(Server.World.StuntCourseBuilder)

-- Physics scale: 1 stud = 0.28 m, so real gravity is 35.02 studs/s^2.
Workspace.Gravity = Units.GRAVITY_STUDS

-- Collision groups ------------------------------------------------------------------
local CG = GameConfig.CollisionGroups
for _, g in { CG.Aircraft, CG.Debris, "AircraftProtected" } do
	pcall(function()
		PhysicsService:RegisterCollisionGroup(g)
	end)
end
PhysicsService:CollisionGroupSetCollidable(CG.Aircraft, CG.Aircraft, GameConfig.aircraftCollide)
PhysicsService:CollisionGroupSetCollidable("AircraftProtected", CG.Aircraft, false)
PhysicsService:CollisionGroupSetCollidable("AircraftProtected", "AircraftProtected", false)
PhysicsService:CollisionGroupSetCollidable("AircraftProtected", CG.Debris, false)
PhysicsService:CollisionGroupSetCollidable(CG.Debris, CG.Debris, true)

-- Remotes --------------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
for _, name in GameConfig.Remotes do
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
end
remotes.Parent = ReplicatedStorage

-- Character spawn at Harbor City terminal (landside) ----------------------------------
local hbr = Airports.layout("HBR")
local spawnX, spawnZ = Airports.fromRunway(hbr, 0, hbr.terminalFar + hbr.side * 60 * Units.STUDS_PER_METER)
local spawn = Instance.new("SpawnLocation")
spawn.Name = "TerminalSpawn"
spawn.Anchored = true
spawn.Size = Vector3.new(24, 1, 24)
spawn.CFrame = CFrame.new(spawnX, hbr.y + 1, spawnZ)
spawn.Neutral = true
spawn.Duration = 0
spawn.Color = Color3.fromRGB(28, 92, 172)
spawn.Material = Enum.Material.SmoothPlastic
spawn.Parent = Workspace

-- Lighting ----------------------------------------------------------------------------
Lighting.ClockTime = 13.5
Lighting.Brightness = 2.6
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.6
Lighting.OutdoorAmbient = Color3.fromRGB(128, 132, 140)
local WorldGen = require(Shared.WorldGen)
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = WorldGen.atmosphere.density
atmosphere.Offset = WorldGen.atmosphere.offset
atmosphere.Haze = WorldGen.atmosphere.haze
atmosphere.Glare = WorldGen.atmosphere.glare
atmosphere.Color = Color3.fromRGB(199, 214, 230)
atmosphere.Decay = Color3.fromRGB(106, 120, 140)
atmosphere.Parent = Lighting
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.35
bloom.Size = 30
bloom.Threshold = 1.6
bloom.Parent = Lighting
local rays = Instance.new("SunRaysEffect")
rays.Intensity = 0.04
rays.Parent = Lighting
local clouds = Instance.new("Clouds")
clouds.Cover = 0.55
clouds.Density = 0.6
clouds.Parent = Workspace.Terrain

-- Services -------------------------------------------------------------------------
ProgressService.init()
AircraftService.init(remotes)
MissionService.init(remotes, ProgressService)
AircraftService.setTelemetryHandler(MissionService.onTelemetry)
AircraftService.setSpawnHandler(MissionService.onSpawned)

-- World -------------------------------------------------------------------------------
ReplicatedStorage:SetAttribute("WorldReady", false)
local world = Instance.new("Folder")
world.Name = "World"
world.Parent = Workspace

local t0 = os.clock()
-- Stage 1 (players wait): the land around the airports and cities, and the airports.
ReplicatedStorage:SetAttribute("WorldStage", "land")
local nearParts = TerrainBuilder.buildNear(world)
local airports = Instance.new("Folder")
airports.Name = "Airports"
airports.Parent = world
ReplicatedStorage:SetAttribute("WorldStage", "airports")
for _, id in Airports.order do
	AirportBuilder.build(id, airports)
end
-- The Stunts ring course (a few hundred parts, so it is ready before anyone can fly).
local _, ringParts = StuntCourseBuilder.build(world)
print(string.format("[World] airports and ring course ready in %.1fs (%d land parts, %d ring parts)", os.clock() - t0, nearParts, ringParts))
ReplicatedStorage:SetAttribute("WorldReady", true)

-- Stage 2 (while people fly): the far hills, the open sea, then cities and forests.
task.spawn(function()
	local t1 = os.clock()
	local farParts = TerrainBuilder.buildFar(world)
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = world
	local sceneryParts, detailParts, detailTiles = CityBuilder.build(scenery, world)
	print(string.format(
		"[World] far land %d parts, scenery %d (+%d up-close detail parts in %d tiles) in %.1fs more",
		farParts, sceneryParts - (detailParts or 0), detailParts or 0, detailTiles or 0, os.clock() - t1
	))
	ReplicatedStorage:SetAttribute("WorldComplete", true)
end)
ReplicatedStorage:SetAttribute("GameVersion", GameConfig.VERSION)
