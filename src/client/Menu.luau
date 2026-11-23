--!strict
-- Main menu: aircraft (with a little aircraft card), departure airport, mode, route or
-- destination, start point (always a runway by default), assistance level, weather,
-- time of day, sandbox failures, and the control reference. What is offered comes from
-- Shared.Selection, the same rules the server uses to accept a spawn request.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Airports = require(Shared.Airports)
local GameConfig = require(Shared.GameConfig)
local Registry = require(Shared.AircraftRegistry)
local Assist = require(Shared.Assist)
local Selection = require(Shared.Selection)
local Stunts = require(Shared.Stunts)
local InputController = require(script.Parent.InputController)

local Menu = {}
Menu.__index = Menu

local PANEL = Color3.fromRGB(14, 18, 26)
local BTN = Color3.fromRGB(34, 42, 56)
local CARD = Color3.fromRGB(24, 32, 46)
local ACCENT = Color3.fromRGB(40, 120, 220)
local WHITE = Color3.fromRGB(240, 244, 248)
local DIM = Color3.fromRGB(150, 160, 172)
local KEY = Color3.fromRGB(143, 208, 255)
local GOOD = Color3.fromRGB(30, 160, 90)
local DIFF_COLORS = {
	Color3.fromRGB(70, 200, 110),
	Color3.fromRGB(150, 210, 70),
	Color3.fromRGB(240, 170, 50),
	Color3.fromRGB(235, 90, 70),
}

local W, H = 1000, 660

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

local function wrapIndex(i: number, n: number): number
	if n <= 0 then
		return 1
	end
	return ((i - 1) % n) + 1
end

function Menu.new(callbacks: any)
	local self = setmetatable({}, Menu) :: any
	self.callbacks = callbacks
	local aircraftIds = Selection.flyableAircraft(Registry)
	self.aircraftIds = aircraftIds
	self.selection = {
		aircraftId = if table.find(aircraftIds, "kestrel72") then "kestrel72" else aircraftIds[1], -- easiest first
		airport = Airports.order[1],
		mode = "airline",
		destIndex = 1,
		spawnIndex = 1,
		assist = "easy",
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
		Size = UDim2.fromOffset(W, H), BackgroundColor3 = PANEL, BackgroundTransparency = 0.05,
	})
	round(frame, 14)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	self.scale = scale
	local cam = workspace.CurrentCamera
	local function fit()
		local vp = cam.ViewportSize
		scale.Scale = math.clamp(math.min(vp.X / (W + 40), vp.Y / (H + 40)), 0.45, 1.2)
	end
	fit()
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	make("TextLabel", {
		Parent = frame, Text = "OPEN SKIES  ·  Flight & Crash Simulator", Position = UDim2.fromOffset(24, 14),
		Size = UDim2.new(1, -48, 0, 36), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack,
		TextColor3 = WHITE, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left,
	})
	self.status = make("TextLabel", {
		Parent = frame, Text = "", Position = UDim2.fromOffset(24, 50), Size = UDim2.new(1, -48, 0, 24),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextColor3 = DIM, TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	})

	-- Left column: one row per choice, each with big < and > buttons.
	local LEFT_W = 560
	local left = make("Frame", { Parent = frame, Position = UDim2.fromOffset(24, 88), Size = UDim2.new(0, LEFT_W, 1, -178), BackgroundTransparency = 1 })
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = left
	local rowCount = 0

	local function row(title: string, onPrev: () -> (), onNext: () -> ()): (TextLabel, TextLabel)
		rowCount += 1
		local r = make("Frame", { Parent = left, Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = BTN, LayoutOrder = rowCount })
		round(r, 10)
		local titleLabel = make("TextLabel", {
			Parent = r, Text = title, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 126, 1, 0),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextColor3 = DIM, TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local value = make("TextLabel", {
			Parent = r, Text = "", Position = UDim2.fromOffset(188, 0), Size = UDim2.new(1, -240, 1, 0),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextColor3 = WHITE, TextSize = 18,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local prev = make("TextButton", {
			Parent = r, Text = "<", Position = UDim2.fromOffset(142, 4), Size = UDim2.fromOffset(38, 38),
			BackgroundColor3 = ACCENT, Font = Enum.Font.GothamBlack, TextColor3 = WHITE, TextSize = 22,
		})
		round(prev, 8)
		local nxt = make("TextButton", {
			Parent = r, Text = ">", Position = UDim2.new(1, -44, 0, 4), Size = UDim2.fromOffset(38, 38),
			BackgroundColor3 = ACCENT, Font = Enum.Font.GothamBlack, TextColor3 = WHITE, TextSize = 22,
		})
		round(nxt, 8)
		prev.Activated:Connect(function()
			onPrev()
			self:refresh()
		end)
		nxt.Activated:Connect(function()
			onNext()
			self:refresh()
		end)
		return value, titleLabel
	end

	local sel = self.selection
	local function cycle(key: string, n: number, d: number)
		sel[key] = wrapIndex(sel[key] + d, n)
	end
	-- Changing the aircraft, airport, mode or route starts the list again on a runway.
	local function stepAircraft(d: number)
		if sel.mode == Stunts.MODE then
			return -- Stunts always uses the stunt plane
		end
		local i = table.find(aircraftIds, sel.aircraftId) or 1
		sel.aircraftId = aircraftIds[wrapIndex(i + d, #aircraftIds)]
		sel.spawnIndex = 1
	end
	local function stepAirport(d: number)
		local i = table.find(Airports.order, sel.airport) or 1
		sel.airport = Airports.order[wrapIndex(i + d, #Airports.order)]
		sel.destIndex = 1
		sel.spawnIndex = 1
	end
	local function stepMode(d: number)
		local i = 1
		for k, m in GameConfig.modes do
			if m.id == sel.mode then
				i = k
			end
		end
		sel.mode = GameConfig.modes[wrapIndex(i + d, #GameConfig.modes)].id
		sel.destIndex = 1
		sel.spawnIndex = 1
	end
	local function stepDest(d: number)
		cycle("destIndex", #self:destinations(), d)
		sel.spawnIndex = 1
	end

	self.aircraftValue = row("Aircraft", function()
		stepAircraft(-1)
	end, function()
		stepAircraft(1)
	end)
	self.airportValue = row("Airport", function()
		stepAirport(-1)
	end, function()
		stepAirport(1)
	end)
	self.modeValue = row("Mode", function()
		stepMode(-1)
	end, function()
		stepMode(1)
	end)
	self.routeValue, self.routeTitle = row("Route", function()
		stepDest(-1)
	end, function()
		stepDest(1)
	end)
	self.spawnValue = row("Start at", function()
		cycle("spawnIndex", #self:spawnList(), -1)
	end, function()
		cycle("spawnIndex", #self:spawnList(), 1)
	end)
	self.assistValue = row("Assistance", function()
		sel.assist = Assist.nextMode(Assist.nextMode(sel.assist))
	end, function()
		sel.assist = Assist.nextMode(sel.assist)
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

	-- Right column: the aircraft card on top, then controls (or sandbox failures).
	local RIGHT_X = 24 + LEFT_W + 20
	local RIGHT_W = W - RIGHT_X - 24
	local card = make("Frame", {
		Parent = frame, Position = UDim2.fromOffset(RIGHT_X, 88), Size = UDim2.fromOffset(RIGHT_W, 214),
		BackgroundColor3 = CARD,
	})
	round(card, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = card
	self.cardName = make("TextLabel", {
		Parent = card, Text = "", Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -130, 0, 32),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextColor3 = WHITE, TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	self.cardClass = make("TextLabel", {
		Parent = card, Text = "", Position = UDim2.fromOffset(14, 42), Size = UDim2.new(1, -130, 0, 20),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextColor3 = KEY, TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- Difficulty: four little blocks, filled up to the aircraft's level.
	make("TextLabel", {
		Parent = card, Text = "Difficulty", Position = UDim2.fromOffset(14, 68), Size = UDim2.fromOffset(80, 20),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextColor3 = DIM, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	self.diffBlocks = {}
	for i = 1, 4 do
		local b = make("Frame", {
			Parent = card, Position = UDim2.fromOffset(96 + (i - 1) * 22, 71), Size = UDim2.fromOffset(18, 14),
			BackgroundColor3 = DIFF_COLORS[i],
		})
		round(b, 4)
		self.diffBlocks[i] = b
	end
	self.diffLabel = make("TextLabel", {
		Parent = card, Text = "", Position = UDim2.fromOffset(186, 68), Size = UDim2.fromOffset(68, 20),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextColor3 = WHITE, TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	-- Stat chips: seats, cruise speed, wingspan.
	self.chips = {}
	for i = 1, 3 do
		local chip = make("TextLabel", {
			Parent = card, Text = "", Position = UDim2.fromOffset(14 + (i - 1) * 80, 96), Size = UDim2.fromOffset(74, 40),
			BackgroundColor3 = BTN, Font = Enum.Font.GothamBold, TextColor3 = WHITE, TextSize = 14,
			TextWrapped = true, RichText = true,
		})
		round(chip, 8)
		self.chips[i] = chip
	end
	self.cardDesc = make("TextLabel", {
		Parent = card, Text = "", Position = UDim2.fromOffset(14, 144), Size = UDim2.new(1, -28, 0, 62),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextColor3 = WHITE, TextSize = 15,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	})
	-- Top-down silhouette, drawn to scale against the biggest aircraft in the fleet.
	local SIL = 104
	local sil = make("Frame", {
		Parent = card, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(SIL, SIL + 20),
		BackgroundColor3 = BTN, BackgroundTransparency = 0.4,
	})
	round(sil, 10)
	local maxSize = 1
	for _, id in Registry.order do
		local cfg = Registry.get(id)
		if cfg then
			local span, nose, tail = Selection.dimensions(cfg)
			maxSize = math.max(maxSize, span, nose + tail)
		end
	end
	self.silScale = (SIL - 12) / maxSize
	local function silPart(): Frame
		local p = make("Frame", { Parent = sil, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = WHITE, BorderSizePixel = 0 })
		round(p, 3)
		return p
	end
	self.silWing = silPart()
	self.silTail = silPart()
	self.silBody = silPart()
	self.silSize = make("TextLabel", {
		Parent = sil, Text = "", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1, -4, 0, 16), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextColor3 = DIM, TextSize = 12,
	})
	self.silHalf = SIL / 2

	local lowerY = 88 + 214 + 12
	local lowerH = H - lowerY - 90
	local right = make("ScrollingFrame", {
		Parent = frame, Position = UDim2.fromOffset(RIGHT_X, lowerY), Size = UDim2.fromOffset(RIGHT_W, lowerH),
		BackgroundColor3 = BTN, BackgroundTransparency = 0.3, ScrollBarThickness = 6, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, BorderSizePixel = 0,
	})
	round(right, 10)
	self.controlsFrame = right
	local lines = { "<b>CONTROLS</b>" }
	for _, b in InputController.BINDINGS do
		table.insert(lines, string.format('<font color="#8fd0ff">%s</font>   %s', b[1], b[2]))
	end
	table.insert(lines, "")
	table.insert(lines, "<b>FIRST FLIGHT</b>")
	table.insert(lines, "1. You start on the runway with engines running.")
	table.insert(lines, "2. Hold Shift for full throttle. At take-off speed hold S gently.")
	table.insert(lines, "3. Climbing? G for gear up, V for flaps up when fast.")
	table.insert(lines, "4. Follow the pink nav arrow to the other airport.")
	table.insert(lines, "5. Line up, flaps down (F), gear down (G), slow down.")
	table.insert(lines, "6. Just before touching down: throttle idle, nose up a little.")
	table.insert(lines, "7. On the ground: B (brakes) and Z (reverse) to stop.")
	self.helpText = table.concat(lines, "\n")
	self.stuntsHelpText = table.concat({
		"<b>STUNTS: RING RACE</b>",
		"Fly through all the rings in order, from START to FINISH, as fast as you can.",
		"",
		'<font color="#5ad27a">Green ring</font>   the one to fly through next',
		'<font color="#ffd23c">Yellow ring</font>   the one after that',
		'<font color="#8fd0ff">Big arrow</font>   points to the next ring',
		"",
		"The clock starts at the START ring.",
		`Miss a ring and you get +{Stunts.MISS_PENALTY_S} seconds.`,
		"Touch the ground and the run is over.",
		"",
		"<b>TIPS</b>",
		"A / D roll hard into the turns, S pulls you round.",
		"Too fast to make a turn? Ctrl for less throttle.",
		`Beat {Stunts.formatTime(Stunts.MEDALS.gold)} for GOLD!`,
		"R starts again instantly.",
	}, "\n")
	self.helpLabel = make("TextLabel", {
		Parent = right, Text = self.helpText, RichText = true, Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextColor3 = WHITE, TextSize = 15, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	})

	-- Failures grid (sandbox only), in place of the controls list.
	local fail = make("Frame", {
		Parent = frame, Position = UDim2.fromOffset(RIGHT_X, lowerY), Size = UDim2.fromOffset(RIGHT_W, lowerH),
		BackgroundTransparency = 1, Visible = false,
	})
	self.failFrame = fail
	make("TextLabel", {
		Parent = fail, Text = "BREAK SOMETHING (tap to turn on)", Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextColor3 = DIM, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local failGrid = make("Frame", { Parent = fail, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 1, -26), BackgroundTransparency = 1 })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.333, -6, 0, 50)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.Parent = failGrid
	self.failButtons = {}
	for _, f in GameConfig.failures do
		local b = make("TextButton", {
			Parent = failGrid, Text = f.label, BackgroundColor3 = BTN, Font = Enum.Font.GothamBold,
			TextColor3 = WHITE, TextSize = 14, TextWrapped = true,
		})
		round(b, 8)
		b.Activated:Connect(function()
			sel.failures[f.id] = not sel.failures[f.id]
			self.callbacks.onFailure(f.id, sel.failures[f.id] == true)
			self:refresh()
		end)
		self.failButtons[f.id] = b
	end

	-- Tip under the rows (what the chosen start means).
	self.tip = make("TextLabel", {
		Parent = frame, Text = "", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -20),
		Size = UDim2.fromOffset(W - 24 - 24 - 400, 46), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
		TextColor3 = KEY, TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- Bottom buttons
	local fly = make("TextButton", {
		Parent = frame, Text = "FLY", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -18),
		Size = UDim2.fromOffset(200, 54), BackgroundColor3 = GOOD, Font = Enum.Font.GothamBlack,
		TextColor3 = WHITE, TextSize = 26,
	})
	round(fly, 10)
	fly.Activated:Connect(function()
		self.callbacks.onFly(self:options())
	end)
	self.flyButton = fly
	local resume = make("TextButton", {
		Parent = frame, Text = "RESUME", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -236, 1, -18),
		Size = UDim2.fromOffset(160, 54), BackgroundColor3 = BTN, Font = Enum.Font.GothamBold,
		TextColor3 = WHITE, TextSize = 20, Visible = false,
	})
	round(resume, 10)
	resume.Activated:Connect(function()
		self:hide()
	end)
	self.resumeButton = resume

	self:refresh()
	return self
end

-- The aircraft that will fly: the picked one, or the stunt plane in Stunts mode.
function Menu:aircraftId(): string
	if self.selection.mode == Stunts.MODE and Registry.get(Registry.stuntAircraftId) then
		return Registry.stuntAircraftId
	end
	return self.selection.aircraftId
end

function Menu:aircraft(): any
	return Registry.get(self:aircraftId())
end

-- Destination choices: airport ids, or false for "no destination" (free flight / sandbox).
function Menu:destinations(): { any }
	return Selection.destinations(self.selection.airport, self.selection.mode)
end

function Menu:destination(): string?
	local list = self:destinations()
	local d = list[math.clamp(self.selection.destIndex, 1, math.max(1, #list))]
	return if d then d else nil
end

function Menu:spawnList(): { any }
	local sel = self.selection
	return Selection.spawnList(sel.airport, self:aircraft(), sel.mode, self:destination())
end

function Menu:spawn(): any
	local spawns = self:spawnList()
	return spawns[math.clamp(self.selection.spawnIndex, 1, #spawns)]
end

function Menu:options()
	local sel = self.selection
	local sp = self:spawn()
	local dest = self:destination()
	-- An approach start lands at the airport it approaches.
	if sp.kind == "approach" and sel.mode == "airline" then
		dest = sp.airport
	end
	return {
		aircraftId = self:aircraftId(),
		airport = sel.airport,
		mode = sel.mode,
		spawnId = sp.id,
		assist = sel.assist,
		destination = dest,
		failures = if sel.mode == "sandbox" then table.clone(sel.failures) else {},
	}
end

local function airportName(id: string): string
	local ap = Airports.list[id]
	return if ap then `{ap.city} ({id})` else id
end

function Menu:refreshCard(cfg: any)
	local c = Selection.card(cfg)
	self.cardName.Text = c.name
	self.cardClass.Text = c.class
	for i, b in self.diffBlocks do
		b.BackgroundTransparency = if i <= c.difficulty then 0 else 0.8
	end
	self.diffLabel.Text = c.difficultyLabel
	self.diffLabel.TextColor3 = DIFF_COLORS[c.difficulty] or WHITE
	self.chips[1].Text = if c.seats then `<font size="18">{c.seats}</font>\nseats` else "-"
	self.chips[2].Text = if c.cruiseKt then `<font size="18">{c.cruiseKt}</font>\nkt cruise` else "-"
	self.chips[3].Text = `<font size="18">{math.floor(c.spanM + 0.5)} m</font>\nwingspan`
	self.cardDesc.Text = c.description
	-- silhouette, nose up
	local k: number = self.silScale
	local h: number = self.silHalf
	local spanPx = math.max(8, c.spanM * k)
	local lenPx = math.max(8, c.lengthM * k)
	local bodyW = math.max(4, lenPx * 0.085)
	self.silBody.Size = UDim2.fromOffset(bodyW, lenPx)
	self.silBody.Position = UDim2.fromOffset(h, h)
	self.silWing.Size = UDim2.fromOffset(spanPx, math.max(4, lenPx * 0.16))
	self.silWing.Position = UDim2.fromOffset(h, h - lenPx * 0.02)
	self.silTail.Size = UDim2.fromOffset(math.max(6, spanPx * 0.36), math.max(3, lenPx * 0.08))
	self.silTail.Position = UDim2.fromOffset(h, h + lenPx * 0.42)
	self.silSize.Text = `{math.floor(c.lengthM + 0.5)} m long`
end

function Menu:refresh()
	local sel = self.selection
	local cfg = self:aircraft()
	local n = #self.aircraftIds
	local i = table.find(self.aircraftIds, sel.aircraftId) or 1
	local stunts = sel.mode == Stunts.MODE
	self.aircraftValue.Text = if stunts then `{cfg.displayName}  (stunt plane)` else `{cfg.displayName}  ({i} of {n})`
	self:refreshCard(cfg)

	local ap = Airports.list[sel.airport]
	self.airportValue.Text = ap.name
	for _, m in GameConfig.modes do
		if m.id == sel.mode then
			self.modeValue.Text = m.label
		end
	end

	local dests = self:destinations()
	sel.destIndex = math.clamp(sel.destIndex, 1, math.max(1, #dests))
	local dest = self:destination()
	if stunts then
		self.routeTitle.Text = "Course"
		self.routeValue.Text = `{#Stunts.course()} rings, high and low, near Harbor City`
	elseif sel.mode == "airline" then
		self.routeTitle.Text = "Route"
		self.routeValue.Text = if dest then `{airportName(sel.airport)} to {airportName(dest)}` else "No routes from here"
	else
		self.routeTitle.Text = "Fly to"
		self.routeValue.Text = if dest then airportName(dest) else "Nowhere: just explore"
	end

	local spawns = self:spawnList()
	sel.spawnIndex = math.clamp(sel.spawnIndex, 1, #spawns)
	local sp = spawns[sel.spawnIndex]
	self.spawnValue.Text = Selection.spawnLabel(sp)
	self.assistValue.Text = Assist.LABELS[sel.assist] or sel.assist
	self.weatherValue.Text = GameConfig.weather[sel.weatherIndex].label
	self.timeValue.Text = GameConfig.timeOfDay[sel.timeIndex].label

	local sandbox = sel.mode == "sandbox"
	self.failFrame.Visible = sandbox
	self.controlsFrame.Visible = not sandbox
	for id, b in self.failButtons do
		b.BackgroundColor3 = if sel.failures[id] then Color3.fromRGB(180, 60, 50) else BTN
	end

	local tip
	if stunts then
		tip = `Fly through every ring in order. Don't touch the ground! A missed ring costs {Stunts.MISS_PENALTY_S} seconds.`
	elseif sp.kind == "runway" then
		tip = "Engines on, lined up and ready. Full throttle to go!"
	elseif sp.kind == "gate" then
		tip = "Parked at the gate: press I for engines, P to let the brake off, then taxi to the runway."
	elseif sp.kind == "approach" then
		tip = "Already flying: line up with the runway lights and land."
	else
		tip = "Starting in the air."
	end
	if not stunts and not Selection.gateFits(cfg, sel.airport) then
		tip ..= ` The {cfg.displayName} is too big for the gates here.`
	end
	self.tip.Text = tip

	self.helpLabel.Text = if stunts then self.stuntsHelpText else self.helpText
	self.status.Text = if stunts then "Stunts: race the ring course against the clock!"
		elseif sel.mode == "airline" then "Fly the route from runway to gate. Your landing gets a score!"
		elseif sandbox then "Crash and failure testing. Nothing is saved; R resets instantly."
		else "Fly anywhere you like. Landings at any airport get a score."
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
