--!strict
-- Client entry point: menu -> spawn request -> flight controller, camera, HUD.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Registry = require(Shared.AircraftRegistry)
local Controls = require(Shared.Controls)

local Client = script.Parent
local InputController = require(Client.InputController)
local FlightController = require(Client.FlightController)
local CameraController = require(Client.CameraController)
local Hud = require(Client.Hud)
local Menu = require(Client.Menu)
local WorldFx = require(Client.WorldFx)
local Effects = require(Client.Effects)
local MeshSkins = require(Client.MeshSkins)
local ControlsPopup = require(Client.ControlsPopup)
local FlightPanel = require(Client.FlightPanel)
local Minimap = require(Client.Minimap)
local SoundController = require(Client.SoundController)
local StuntsHud = require(Client.StuntsHud)
local Stunts = require(Shared.Stunts)
local HazardController = require(Client.HazardController)
local HazardPanel = require(Client.HazardPanel)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder

local fc: any = nil
local destination: string? = nil
local hud = Hud.new()
local camera = CameraController.new()
local controlsPopup = ControlsPopup.new()
local minimap = Minimap.new()
local sound = SoundController.new()
local menu: any
-- Failures and weather events (the HUD's Events button, J)
local hazards = HazardController.new({
	notify = function(text: string)
		hud:notify(text, 5)
	end,
})
local hazardPanel = HazardPanel.new(function(id: string)
	if id == "fixall" then
		(remotes:WaitForChild("RequestRepair") :: RemoteEvent):FireServer()
		return
	end
	hud:notify(hazards:trigger(id), 5)
end)
local stunts = StuntsHud.new({
	onRetry = function()
		(remotes:WaitForChild("RequestReset") :: RemoteEvent):FireServer()
	end,
	onMenu = function()
		menu:show()
	end,
})

local function command(name: string)
	return function()
		if fc then
			fc:command(name)
		end
	end
end

local flightPanel: any
local input = InputController.new({
	camera = function()
		camera:cycle()
	end,
	hud = function()
		hud:toggle()
	end,
	debug = function()
		hud:toggleDebug()
	end,
	menu = function()
		if menu:isOpen() then
			menu:hide()
		else
			menu:show()
		end
	end,
	reset = function()
		(remotes:WaitForChild("RequestReset") :: RemoteEvent):FireServer()
	end,
	fixAll = function()
		if fc then
			(remotes:WaitForChild("RequestRepair") :: RemoteEvent):FireServer()
		end
	end,
	controls = function()
		controlsPopup:toggle()
	end,
	music = function()
		sound:toggleMusic()
	end,
	panel = function()
		if flightPanel then
			flightPanel:toggle()
		end
	end,
	minimap = function()
		minimap:toggle()
	end,
	events = function()
		hazardPanel:toggle()
	end,
	engines = command("engines"),
	assist = command("assist"),
})

flightPanel = FlightPanel.new(input, {})

local function stopFlying()
	if fc then
		fc:destroy()
		fc = nil
	end
	sound:detach()
	input:unbind()
	camera:detach()
	hud:setFlying(false)
	hud:setStuntsMode(false)
	hazards:attach(nil)
	hazardPanel:setFlying(false)
	stunts:stop()
	flightPanel:setFlying(false)
	minimap:setFlying(false)
	menu.flying = false
	menu:show()
end

-- Ask the server for an aircraft. While the world is still being built the request is
-- held and sent automatically when it is ready; if nothing comes back, say so.
local pendingOptions: any = nil
local requestId = 0
local function sendRequest(options: any)
	requestId += 1
	local id = requestId
	destination = options.destination
	menu:setStatus("Requesting aircraft...")
	;(remotes:WaitForChild("RequestSpawn") :: RemoteEvent):FireServer(options)
	task.delay(10, function()
		if id == requestId and not fc and menu:isOpen() then
			menu:setStatus("No answer from the server yet. Press Fly again in a moment.")
		end
	end)
end
local function requestFlight(options: any)
	if ReplicatedStorage:GetAttribute("WorldReady") ~= true then
		pendingOptions = options
		menu:setStatus("The world is still being built. Your flight starts as soon as it is ready...")
		return
	end
	sendRequest(options)
end

menu = Menu.new({
	onFly = function(options: any)
		requestFlight(options)
	end,
	onWeather = function(w: any)
		WorldFx.setWeather(w)
	end,
	onTime = function(t: any)
		WorldFx.setTime(t)
	end,
	onFailure = function(id: string, on: boolean)
		if fc and menu.selection.mode == "sandbox" then
			fc:setFailure(id, on)
		end
	end,
})
WorldFx.setWeather(GameConfig.weather[1])
WorldFx.setTime(GameConfig.timeOfDay[2])

local function onAssigned(model: Model, options: any, sp: any, repaired: boolean?)
	if fc then
		fc:destroy()
		fc = nil
	end
	hazards:attach(nil)
	sound:detach()
	if not model then
		return
	end
	-- Start the race HUD before anything yields, so the server's first race update
	-- (sent right after this event) is never missed.
	local racing = type(options) == "table" and options.mode == Stunts.MODE
	if repaired then
		-- Fix all: same flight, keep the race and mission going.
	elseif racing then
		stunts:start()
	else
		stunts:stop()
	end
	hud:setStuntsMode(racing)
	model:WaitForChild("Core", 10)
	local cfg = Registry.get(model:GetAttribute("AircraftId") :: string)
	fc = FlightController.new(model, options, sp, remotes, input)
	fc.windProvider = function(pos: Vector3, t: number): Vector3
		return WorldFx.wind(pos, t) + hazards:windAt(pos, t)
	end
	hazards:attach(fc)
	hazardPanel:setFlying(true)
	sound:attach(fc)
	destination = options.destination
	input:bind()
	camera:attach(model, cfg)
	hud:setFlying(true)
	flightPanel:setFlying(true)
	minimap:setFlying(true)
	menu.flying = true
	menu:hide()
end
;(remotes:WaitForChild("AircraftAssigned") :: RemoteEvent).OnClientEvent:Connect(function(model: Model, options: any, sp: any, repaired: any)
	requestId += 1 -- answered
	local ok, err = xpcall(onAssigned, debug.traceback, model, options, sp, repaired == true)
	if not ok then
		warn("[Flight] could not start the flight: " .. tostring(err))
		menu:setStatus("Could not start the flight (see Output, F9): " .. tostring(err):split("\n")[1])
	end
end)

;(remotes:WaitForChild("MissionUpdate") :: RemoteEvent).OnClientEvent:Connect(function(data: any)
	hud:setMission(data)
	if data and data.destination then
		destination = data.destination
	end
end)
;(remotes:WaitForChild("StuntsUpdate") :: RemoteEvent).OnClientEvent:Connect(function(data: any)
	stunts:onUpdate(data)
end)
;(remotes:WaitForChild("LandingResult") :: RemoteEvent).OnClientEvent:Connect(function(result: any)
	hud:showLanding(result)
end)
;(remotes:WaitForChild("DentFx") :: RemoteEvent).OnClientEvent:Connect(function(model: any, comp: any, point: any, dir: any, depth: any)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or type(comp) ~= "string" then
		return
	end
	if typeof(point) ~= "Vector3" or typeof(dir) ~= "Vector3" or type(depth) ~= "number" or depth ~= depth or depth <= 0 then
		return
	end
	local cam = workspace.CurrentCamera
	local core = (model :: Model).PrimaryPart
	if not core or (cam and (cam.CFrame.Position - core.Position).Magnitude > 1500) then
		return -- too far away to see a dent
	end
	MeshSkins.onDent(model :: Model, comp, point, dir, math.min(depth, 2))
end)
;(remotes:WaitForChild("CrashFx") :: RemoteEvent).OnClientEvent:Connect(function(kind: any, pos: any, intensity: any, vel: any)
	if type(kind) ~= "string" or typeof(pos) ~= "Vector3" or type(intensity) ~= "number" or intensity ~= intensity then
		return
	end
	if vel ~= nil and typeof(vel) ~= "Vector3" then
		return
	end
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - pos).Magnitude > 4000 then
		return
	end
	Effects.crashFx(kind, pos, intensity, vel)
end)
;(remotes:WaitForChild("Notify") :: RemoteEvent).OnClientEvent:Connect(function(text: string)
	requestId += 1 -- answered
	hud:notify(text)
	if menu:isOpen() then
		menu:setStatus(text)
	end
end)

-- The menu and controls keys work even when not flying (flight keys are unbound then).
local function keysFor(action: string): { [Enum.KeyCode]: boolean }
	local set = {}
	for _, b in Controls.KEYMAP do
		if b.action == action then
			for _, name in b.keys do
				local ok, code = pcall(function()
					return (Enum.KeyCode :: any)[name]
				end)
				if ok and code then
					set[code] = true
				end
			end
		end
	end
	return set
end
local menuKeys, controlsKeys, musicKeys = keysFor("menu"), keysFor("controls"), keysFor("music")
UserInputService.InputBegan:Connect(function(io, processed)
	if processed or fc then
		return
	end
	if menuKeys[io.KeyCode] then
		if menu:isOpen() then
			menu:hide()
		else
			menu:show()
		end
	elseif controlsKeys[io.KeyCode] then
		controlsPopup:toggle()
	elseif musicKeys[io.KeyCode] then
		sound:toggleMusic()
	end
end)

player.CharacterAdded:Connect(function()
	if fc then
		stopFlying()
	end
end)

RunService.PreSimulation:Connect(function(dt)
	if fc then
		fc:step(dt)
		if not fc.alive then
			stopFlying()
		end
	end
end)

RunService.Heartbeat:Connect(function(dt)
	WorldFx.update(dt, if fc then fc.model else nil)
	hazards:update(dt)
	hazardPanel:setStatus(hazards:status())
	if fc then
		sound:update(dt, camera.mode)
	end
	sound:updateMusic(dt)
	if fc then
		hud:update(fc.telemetry, destination)
		flightPanel:update(fc.telemetry)
		minimap:update(fc.telemetry, destination, fc.model)
		local core = fc.model.PrimaryPart
		stunts:update(if core then core.Position else nil)
	else
		hud:update(nil, nil)
	end
end)

-- Wait for the world last, so every handler above is already connected (a message the
-- server sends while the world builds is never lost).
if ReplicatedStorage:GetAttribute("WorldReady") ~= true then
	local function showStage()
		if pendingOptions == nil then
			local stage = ReplicatedStorage:GetAttribute("WorldStage")
			menu:setStatus("Building the world" .. (if type(stage) == "string" then ": " .. stage else "") .. " (first load takes a little while)...")
		end
	end
	showStage()
	local stageConn = ReplicatedStorage:GetAttributeChangedSignal("WorldStage"):Connect(showStage)
	task.spawn(function()
		while ReplicatedStorage:GetAttribute("WorldReady") ~= true do
			ReplicatedStorage:GetAttributeChangedSignal("WorldReady"):Wait()
		end
		stageConn:Disconnect()
		menu:refresh()
		if pendingOptions then
			local o = pendingOptions
			pendingOptions = nil
			sendRequest(o)
		else
			menu:setStatus("Ready. Press Fly!")
		end
	end)
end
