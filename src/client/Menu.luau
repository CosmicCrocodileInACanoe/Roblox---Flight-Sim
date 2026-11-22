--!strict
-- Main menu: aircraft, mode, route/destination, spawn point, assistance level,
-- weather, time of day, sandbox failures, and the control reference.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Airports = require(Shared.Airports)
local GameConfig = require(Shared.GameConfig)
local Registry = require(Shared.AircraftRegistry)
local InputController = require(script.Parent.InputController)

local Menu = {}
Menu.__index = Menu

local PANEL = Color3.fromRGB(14, 18, 26)
local BTN = Color3.fromRGB(34, 42, 56)
local ACCENT = Color3.fromRGB(40, 120, 220)
local WHITE = Color3.fromRGB(240, 244, 248)
local DIM = Color3.fromRGB(150, 160, 172)

local function make(className: string, props: { [string]: any }): any
	local inst = Instance.new(className) :: any
	for k, v in props do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function round(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

function Menu.new(callbacks: any)
	local self = setmetatable({}, Menu) :: any
	self.callbacks = callbacks
	self.selection = {
		aircraftId = "meridian200",
		mode = "airline",
		routeIndex = 1,
		spawnIndex = 1,
		assist = "assisted",
		weatherIndex = 1,
		timeIndex = 2,
		failures = {} :: { [string]: boolean },
	}
	self.flying = false

	local gui = make("ScreenGui", {
		Name = "FlightMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	self.gui = gui
	local backdrop = make("Frame", { Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45 })
	self.backdrop = backdrop
	local frame = make("Frame", {
		Parent = backdrop, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 860, 0, 560), BackgroundColor3 = PANEL, BackgroundTransparency = 0.05,
	})
	round(frame, 12)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	self.scale = scale
	local cam = workspace.CurrentCamera
	local function fit()
		local vp = cam.ViewportSize
		scale.Scale = math.clamp(math.min(vp.X / 900, vp.Y / 600), 0.5, 1.2)
	end
	fit()
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	make("TextLabel", {
		Parent = frame, Text = "OPEN SKIES  ·  Flight & Crash Simulator", Position = UDim2.fromOffset(24, 14),
		Size = UDim2.new(1, -48, 0, 34), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack,
		TextColor3 = WHITE, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left,
	})
	self.status = make("TextLabel", {
		Parent = frame, Text = "", Position = UDim2.fromOffset(24, 46), Size = UDim2.new(1, -48, 0, 20),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextColor3 = DIM, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local left = make("Frame", { Parent = frame, Position = UDim2.fromOffset(24, 76), Size = UDim2.new(0, 470, 1, -150), BackgroundTransparency = 1 })
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = left
	self.rows = {}

	local function row(title: string, onPrev: () -> (), onNext: () -> ()): TextLabel
		local r = make("Frame", { Parent = left, Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = BTN })
		round(r, 8)
		make("TextLabel", {
			Parent = r, Text = title, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0, 120, 1, 0),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextColor3 = DIM, TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local value = make("TextLabel", {
			Parent = r, Text = "", Position = UDim2.fromOffset(170, 0), Size = UDim2.new(1, -210, 1, 0),
			BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextColor3 = WHITE, TextSize = 15,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local prev = make("TextButton", {
			Parent = r, Text = "<", Position = UDim2.fromOffset(132, 3), Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = ACCENT, Font = Enum.Font.GothamBlack, TextColor3 = WHITE, TextSize = 18,
		})
		round(prev, 6)
		local nxt = make("TextButton", {
			Parent = r, Text = ">", Position = UDim2.new(1, -36, 0, 3), Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = ACCENT, Font = Enum.Font.GothamBlack, TextColor3 = WHITE, TextSize = 18,
		})
		round(nxt, 6)
		prev.Activated:Connect(function()
			onPrev()
			self:refresh()
		end)
		nxt.Activated:Connect(function()
			onNext()
			self:refresh()
		end)
		return value
	end

	local sel = self.selection
	local function cycle(key: string, n: number, d: number)
		sel[key] = ((sel[key] - 1 + d) % n) + 1
	end

	self.aircraftValue = row("Aircraft", function() end, function() end)
	self.modeValue = row("Mode", function()
		local i = 1
		for k, m in GameConfig.modes do
			if m.id == sel.mode then
				i = k
			end
		end
		sel.mode = GameConfig.modes[((i - 2) % #GameConfig.modes) + 1].id
		sel.spawnIndex = 1
	end, function()
		local i = 1
		for k, m in GameConfig.modes do
			if m.id == sel.mode then
				i = k
			end
		end
		sel.mode = GameConfig.modes[(i % #GameConfig.modes) + 1].id
		sel.spawnIndex = 1
	end)
	self.routeValue = row("Route", function()
		cycle("routeIndex", #Airports.routes, -1)
		sel.spawnIndex = 1
	end, function()
		cycle("routeIndex", #Airports.routes, 1)
		sel.spawnIndex = 1
	end)
	self.spawnValue = row("Start at", function()
		cycle("spawnIndex", #self:spawnList(), -1)
	end, function()
		cycle("spawnIndex", #self:spawnList(), 1)
	end)
	self.assistValue = row("Controls", function()
		sel.assist = if sel.assist == "assisted" then "simulation" else "assisted"
	end, function()
		sel.assist = if sel.assist == "assisted" then "simulation" else "assisted"
	end)
	self.weatherValue = row("Weather", function()
		cycle("weatherIndex", #GameConfig.weather, -1)
		self.callbacks.onWeather(GameConfig.weather[sel.weatherIndex])
	end, function()
		cycle("weatherIndex", #GameConfig.weather, 1)
		self.callbacks.onWeather(GameConfig.weather[sel.weatherIndex])
	end)
	self.timeValue = row("Time of day", function()
		cycle("timeIndex", #GameConfig.timeOfDay, -1)
		self.callbacks.onTime(GameConfig.timeOfDay[sel.timeIndex])
	end, function()
		cycle("timeIndex", #GameConfig.timeOfDay, 1)
		self.callbacks.onTime(GameConfig.timeOfDay[sel.timeIndex])
	end)

	-- Failures grid (sandbox)
	local fail = make("Frame", { Parent = left, Size = UDim2.new(1, 0, 0, 120), BackgroundTransparency = 1 })
	self.failFrame = fail
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.333, -6, 0, 34)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.Parent = fail
	self.failButtons = {}
	for _, f in GameConfig.failures do
		local b = make("TextButton", {
			Parent = fail, Text = f.label, BackgroundColor3 = BTN, Font = Enum.Font.GothamMedium,
			TextColor3 = WHITE, TextSize = 12, TextWrapped = true,
		})
		round(b, 6)
		b.Activated:Connect(function()
			sel.failures[f.id] = not sel.failures[f.id]
			self.callbacks.onFailure(f.id, sel.failures[f.id] == true)
			self:refresh()
		end)
		self.failButtons[f.id] = b
	end

	-- Right column: controls reference
	local right = make("ScrollingFrame", {
		Parent = frame, Position = UDim2.new(0, 514, 0, 76), Size = UDim2.new(1, -538, 1, -150),
		BackgroundColor3 = BTN, BackgroundTransparency = 0.3, ScrollBarThickness = 6, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, BorderSizePixel = 0,
	})
	round(right, 8)
	local lines = { "<b>CONTROLS</b>" }
	for _, b in InputController.BINDINGS do
		table.insert(lines, string.format('<font color="#8fd0ff">%s</font>   %s', b[1], b[2]))
	end
	table.insert(lines, "")
	table.insert(lines, "<b>FIRST FLIGHT</b>")
	table.insert(lines, "1. I to start engines (12 s), P to release brake.")
	table.insert(lines, "2. Taxi with a little throttle, steer with Q/E.")
	table.insert(lines, "3. On the runway: full throttle, at 140 kt hold S gently.")
	table.insert(lines, "4. Positive climb: G for gear up, V for flaps up above 190 kt.")
	table.insert(lines, "5. Follow the pink nav arrow. 15 nm out: descend to ~2,500 ft.")
	table.insert(lines, "6. Flaps FULL, gear down, 140 kt, keep the pink diamonds centred.")
	table.insert(lines, "7. At 30 ft: throttle idle, raise the nose slightly. B + Z to stop.")
	make("TextLabel", {
		Parent = right, Text = table.concat(lines, "\n"), RichText = true, Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextColor3 = WHITE, TextSize = 13, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	})

	-- Bottom buttons
	local fly = make("TextButton", {
		Parent = frame, Text = "FLY", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -18),
		Size = UDim2.fromOffset(180, 46), BackgroundColor3 = Color3.fromRGB(30, 160, 90), Font = Enum.Font.GothamBlack,
		TextColor3 = WHITE, TextSize = 22,
	})
	round(fly, 8)
	fly.Activated:Connect(function()
		self.callbacks.onFly(self:options())
	end)
	self.flyButton = fly
	local resume = make("TextButton", {
		Parent = frame, Text = "RESUME", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -216, 1, -18),
		Size = UDim2.fromOffset(150, 46), BackgroundColor3 = BTN, Font = Enum.Font.GothamBold,
		TextColor3 = WHITE, TextSize = 18, Visible = false,
	})
	round(resume, 8)
	resume.Activated:Connect(function()
		self:hide()
	end)
	self.resumeButton = resume

	self:refresh()
	return self
end

function Menu:route()
	return Airports.routes[self.selection.routeIndex]
end

function Menu:spawnList(): { any }
	local sel = self.selection
	local route = self:route()
	local list = {}
	for _, s in Airports.spawnPoints(route.from) do
		if s.kind ~= "approach" then
			table.insert(list, s)
		end
	end
	-- approaches into the destination
	for _, s in Airports.spawnPoints(route.to) do
		if s.kind == "approach" then
			table.insert(list, s)
		end
	end
	if sel.mode ~= "airline" then
		for _, s in Airports.sandboxSpawns() do
			table.insert(list, s)
		end
	end
	return list
end

function Menu:options()
	local sel = self.selection
	local spawns = self:spawnList()
	local sp = spawns[math.clamp(sel.spawnIndex, 1, #spawns)]
	local route = self:route()
	return {
		aircraftId = sel.aircraftId,
		mode = sel.mode,
		spawnId = sp.id,
		assist = sel.assist,
		destination = route.to,
		failures = if sel.mode == "sandbox" then table.clone(sel.failures) else {},
	}
end

function Menu:refresh()
	local sel = self.selection
	local cfg = Registry.get(sel.aircraftId)
	local planned = {}
	for _, p in Registry.planned do
		table.insert(planned, p.label)
	end
	self.aircraftValue.Text = cfg.displayName .. "  (" .. #planned .. " more types in Milestone 2)"
	for _, m in GameConfig.modes do
		if m.id == sel.mode then
			self.modeValue.Text = m.label
		end
	end
	local route = self:route()
	self.routeValue.Text = `{Airports.list[route.from].city} ({route.from}) to {Airports.list[route.to].city} ({route.to})`
	local spawns = self:spawnList()
	sel.spawnIndex = math.clamp(sel.spawnIndex, 1, #spawns)
	self.spawnValue.Text = spawns[sel.spawnIndex].label
	self.assistValue.Text = if sel.assist == "assisted" then "Assisted (auto-trim, protections)" else "Simulation (direct, manual trim)"
	self.weatherValue.Text = GameConfig.weather[sel.weatherIndex].label
	self.timeValue.Text = GameConfig.timeOfDay[sel.timeIndex].label
	self.failFrame.Visible = sel.mode == "sandbox"
	for id, b in self.failButtons do
		b.BackgroundColor3 = if sel.failures[id] then Color3.fromRGB(180, 60, 50) else BTN
	end
	self.status.Text = if sel.mode == "airline" then "Fly the route gate to gate. Your landing is graded by the server."
		elseif sel.mode == "sandbox" then "Crash and failure testing. Nothing is saved; R resets instantly."
		else "Explore freely. Landings at either airport are graded."
	self.resumeButton.Visible = self.flying
	self.flyButton.Text = if self.flying then "RESPAWN" else "FLY"
end

function Menu:show()
	self.backdrop.Visible = true
	self:refresh()
end

function Menu:hide()
	self.backdrop.Visible = false
end

function Menu:isOpen(): boolean
	return self.backdrop.Visible
end

function Menu:setStatus(text: string)
	self.status.Text = text
end

return Menu
