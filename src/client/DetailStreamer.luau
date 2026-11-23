--!strict
-- Shows up-close world detail (windows, houses, trees, roof clutter) only near the camera.
-- The server files detail into tile Models under ReplicatedStorage.WorldDetail. This
-- client moves a tile into Workspace.World.Detail when the camera comes within
-- DetailTiles.LOAD_RADIUS and back when it passes UNLOAD_RADIUS. The move is local
-- to this client (nothing is cloned or replicated), and at most a couple of tiles move
-- per tick so loading never hitches.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DetailTiles = require(Shared.DetailTiles)

local DetailStreamer = {}

local TICK = 0.25

local source: Folder? = nil
local target: Folder? = nil
local models: { [string]: Model } = {}
local infos: { DetailTiles.TileInfo } = {}
local loaded: { [string]: boolean } = {}
local accum = 0

local function setup(): boolean
	-- the city detail tiles are built after take-off is allowed, so wait for all of it
	if ReplicatedStorage:GetAttribute("WorldComplete") ~= true then
		return false
	end
	local src = ReplicatedStorage:FindFirstChild("WorldDetail") :: Folder?
	local world = Workspace:FindFirstChild("World")
	if not src or not world then
		return false
	end
	local dst = Instance.new("Folder")
	dst.Name = "Detail"
	dst.Parent = world
	source, target = src, dst
	for _, m in src:GetChildren() do
		local key = m:GetAttribute("TileKey")
		if m:IsA("Model") and type(key) == "string" then
			models[key] = m
			table.insert(infos, { key = key, groundY = (m:GetAttribute("CenterY") :: number?) or 0 })
		end
	end
	return true
end

function DetailStreamer.update(dt: number)
	accum += dt
	if accum < TICK then
		return
	end
	accum = 0
	if not target and not setup() then
		return
	end
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local p = cam.CFrame.Position
	local toLoad, toUnload = DetailTiles.plan(infos, loaded, p.X, p.Y, p.Z)
	for _, key in toUnload do
		models[key].Parent = source
		loaded[key] = nil
	end
	for _, key in toLoad do
		models[key].Parent = target
		loaded[key] = true
	end
end

-- Number of tiles currently shown (for debugging / the dev console).
function DetailStreamer.loadedCount(): number
	local n = 0
	for _ in loaded do
		n += 1
	end
	return n
end

return DetailStreamer
