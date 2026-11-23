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
local ControlsPopup = require(Client.ControlsPopup)
local FlightPanel = require(Client.FlightPanel)
local Minimap = require(Client.Minimap)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder

local fc: any = nil
local destination: string? = nil
local hud = Hud.new()
local camera = CameraController.new()
local controlsPopup = ControlsPopup.new()
local minimap = Minimap.new()

local function command(name: string)
	return function()
		if fc then
			fc:command(name)
		end
	end
end

local menu: any
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
	controls = function()
		controlsPopup:toggle()
	end,
	panel = function()
		if flightPanel then
			flightPanel:toggle()
		end
	end,
	minimap = function()
		minimap:toggle()
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
	input:unbind()
	camera:detach()
	hud:setFlying(false)
	flightPanel:setFlying(false)
	minimap:setFlying(false)
	menu.flying = false
	menu:show()
end

menu = Menu.new({
	onFly = function(options: any)
		destination = options.destination
		menu:setStatus("Requesting aircraft...")
		;(remotes:WaitForChild("RequestSpawn") :: RemoteEvent):FireServer(options)
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

if ReplicatedStorage:GetAttribute("WorldReady") ~= true then
	menu:setStatus("Building the world (first load takes a few seconds)...")
	ReplicatedStorage:GetAttributeChangedSignal("WorldReady"):Wait()
	menu:refresh()
end

;(remotes:WaitForChild("AircraftAssigned") :: RemoteEvent).OnClientEvent:Connect(function(model: Model, options: any, sp: any)
	if fc then
		fc:destroy()
		fc = nil
	end
	if not model then
		return
	end
	model:WaitForChild("Core", 10)
	local cfg = Registry.get(model:GetAttribute("AircraftId") :: string)
	fc = FlightController.new(model, options, sp, remotes, input)
	fc.windProvider = WorldFx.wind
	destination = options.destination
	input:bind()
	camera:attach(model, cfg)
	hud:setFlying(true)
	flightPanel:setFlying(true)
	minimap:setFlying(true)
	menu.flying = true
	menu:hide()
end)

;(remotes:WaitForChild("MissionUpdate") :: RemoteEvent).OnClientEvent:Connect(function(data: any)
	hud:setMission(data)
	if data and data.destination then
		destination = data.destination
	end
end)
;(remotes:WaitForChild("LandingResult") :: RemoteEvent).OnClientEvent:Connect(function(result: any)
	hud:showLanding(result)
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
local menuKeys, controlsKeys = keysFor("menu"), keysFor("controls")
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
	if fc then
		hud:update(fc.telemetry, destination)
		flightPanel:update(fc.telemetry)
		minimap:update(fc.telemetry, destination, fc.model)
	else
		hud:update(nil, nil)
	end
end)
