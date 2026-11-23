--!strict
-- On-screen flight controls for mouse and touch, alongside the keyboard:
--   left:  a throttle lever (drag it, or tap IDLE / MAX) and a flight stick pad
--          (drag the knob: up = nose down, down = nose up, sideways = roll),
--          with rudder buttons under it;
--   right: big toggle buttons for gear, flaps, speedbrake, brakes, parking brake,
--          reverse, engines, assist mode and camera, each lit to show its state.
-- Everything goes through InputController, so it does exactly what the keys do.
-- U (or the "Buttons" button, top right) hides and shows the panel.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local FlightPanel = {}
FlightPanel.__index = FlightPanel

local PANEL = Color3.fromRGB(14, 18, 26)
local OFF = Color3.fromRGB(34, 40, 54)
local ON = Color3.fromRGB(40, 150, 90)
local WARN = Color3.fromRGB(200, 130, 30)
local RED = Color3.fromRGB(190, 60, 60)
local WHITE = Color3.fromRGB(240, 244, 248)
local DIM = Color3.fromRGB(150, 160, 172)
local BLUE = Color3.fromRGB(40, 120, 220)

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

local function isPointer(io: InputObject): boolean
	return io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch
end

local function isMove(io: InputObject): boolean
	return io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch
end

function FlightPanel.new(input: any, callbacks: { [string]: () -> () })
	local self = setmetatable({}, FlightPanel) :: any
	self.input = input
	self.callbacks = callbacks
	self.shown = true
	self.flying = false
	self.buttons = {} :: { [string]: TextButton }
	self.connections = {} :: { RBXScriptConnection }

	local gui = make("ScreenGui", {
		Name = "FlightPanel", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 5,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	self.gui = gui

	-- "Buttons" toggle next to the Controls button (top right).
	local toggle = make("TextButton", {
		Parent = gui, Name = "PanelToggle", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -140, 0, 8),
		Size = UDim2.fromOffset(110, 32), BackgroundColor3 = PANEL, BackgroundTransparency = 0.15,
		Text = "Buttons (U)", Font = Enum.Font.GothamBold, TextColor3 = WHITE, TextSize = 14, Visible = false,
	})
	round(toggle, 8)
	toggle.Activated:Connect(function()
		self:toggle()
	end)
	self.toggleButton = toggle

	local root = make("Frame", { Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	self.root = root

	-------------------------------------------------------------------------------
	-- Left: throttle lever
	local thr = make("Frame", {
		Parent = root, Name = "Throttle", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, -20),
		Size = UDim2.fromOffset(70, 250), BackgroundColor3 = PANEL, BackgroundTransparency = 0.25,
	})
	round(thr, 10)
	make("TextLabel", {
		Parent = thr, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 4), BackgroundTransparency = 1,
		Text = "THRUST", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = DIM,
	})
	local maxB = make("TextButton", {
		Parent = thr, Position = UDim2.fromOffset(8, 24), Size = UDim2.new(1, -16, 0, 22), BackgroundColor3 = OFF,
		Text = "MAX", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = WHITE,
	})
	round(maxB, 6)
	local track = make("Frame", {
		Parent = thr, Name = "Track", Position = UDim2.fromOffset(20, 52), Size = UDim2.new(1, -40, 1, -110),
		BackgroundColor3 = Color3.fromRGB(26, 30, 40), Active = true,
	})
	round(track, 6)
	local fill = make("Frame", {
		Parent = track, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = ON, BorderSizePixel = 0,
	})
	round(fill, 6)
	local handle = make("Frame", {
		Parent = track, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(1, 16, 0, 14),
		BackgroundColor3 = WHITE,
	})
	round(handle, 4)
	local idleB = make("TextButton", {
		Parent = thr, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -30), Size = UDim2.new(1, -16, 0, 22),
		BackgroundColor3 = OFF, Text = "IDLE", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = WHITE,
	})
	round(idleB, 6)
	self.thrText = make("TextLabel", {
		Parent = thr, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -6), Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1, Text = "0%", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = WHITE,
	})
	self.thrFill, self.thrHandle = fill, handle
	maxB.Activated:Connect(function()
		input:setThrottle(1)
	end)
	idleB.Activated:Connect(function()
		input:setThrottle(0)
	end)

	-------------------------------------------------------------------------------
	-- Left: flight stick pad
	local pad = make("Frame", {
		Parent = root, Name = "Stick", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 92, 0.5, -45),
		Size = UDim2.fromOffset(160, 160), BackgroundColor3 = PANEL, BackgroundTransparency = 0.35, Active = true,
	})
	round(pad, 80)
	make("Frame", { Parent = pad, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -20, 0, 2), BackgroundColor3 = DIM, BackgroundTransparency = 0.5, BorderSizePixel = 0 })
	make("Frame", { Parent = pad, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 2, 1, -20), BackgroundColor3 = DIM, BackgroundTransparency = 0.5, BorderSizePixel = 0 })
	make("TextLabel", { Parent = pad, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Text = "nose down", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = DIM })
	make("TextLabel", { Parent = pad, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -6), Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Text = "nose up", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = DIM })
	local knob = make("Frame", {
		Parent = pad, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(54, 54),
		BackgroundColor3 = BLUE,
	})
	round(knob, 27)
	self.knob = knob

	-- rudder buttons under the stick
	local function holdButton(parent: Instance, name: string, text: string, action: string, pos: UDim2, size: UDim2): TextButton
		local b = make("TextButton", {
			Parent = parent, Name = name, Position = pos, Size = size, BackgroundColor3 = OFF, BackgroundTransparency = 0.1,
			Text = text, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = WHITE, AutoButtonColor = false,
		})
		round(b, 8)
		local function set(on: boolean)
			input:setVirtualHeld(action, on)
			b.BackgroundColor3 = if on then ON else OFF
		end
		b.InputBegan:Connect(function(io)
			if isPointer(io) then
				set(true)
			end
		end)
		b.InputEnded:Connect(function(io)
			if isPointer(io) then
				set(false)
			end
		end)
		b.MouseLeave:Connect(function()
			set(false)
		end)
		return b
	end
	local rud = make("Frame", {
		Parent = root, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 92, 0.5, 60), Size = UDim2.fromOffset(160, 40),
		BackgroundTransparency = 1,
	})
	holdButton(rud, "RudderLeft", "< RUDDER", "yawLeft", UDim2.fromOffset(0, 0), UDim2.fromOffset(78, 40))
	holdButton(rud, "RudderRight", "RUDDER >", "yawRight", UDim2.fromOffset(82, 0), UDim2.fromOffset(78, 40))

	-- drag tracking for the stick and the throttle (one pointer each)
	local dragStick: InputObject? = nil
	local dragThrottle: InputObject? = nil
	local function stickFrom(pos: Vector3)
		local c = pad.AbsolutePosition + pad.AbsoluteSize / 2
		local r = pad.AbsoluteSize.X / 2 - 27
		local d = Vector2.new(pos.X, pos.Y) - c
		if d.Magnitude > r then
			d = d.Unit * r
		end
		knob.Position = UDim2.new(0.5, d.X, 0.5, d.Y)
		-- a little dead zone in the middle; screen y grows downward = pull = nose up
		local x, y = d.X / r, d.Y / r
		local function dz(v: number): number
			return if math.abs(v) < 0.08 then 0 else (v - math.sign(v) * 0.08) / 0.92
		end
		input:setStick(dz(x), dz(y), true)
	end
	local function throttleFrom(pos: Vector3)
		local top, h = track.AbsolutePosition.Y, track.AbsoluteSize.Y
		input:setThrottle(1 - (pos.Y - top) / math.max(h, 1))
	end
	pad.InputBegan:Connect(function(io)
		if isPointer(io) then
			dragStick = io
			stickFrom(io.Position)
		end
	end)
	track.InputBegan:Connect(function(io)
		if isPointer(io) then
			dragThrottle = io
			throttleFrom(io.Position)
		end
	end)
	table.insert(self.connections, UserInputService.InputChanged:Connect(function(io)
		if not isMove(io) then
			return
		end
		-- touch: follow the same finger; mouse: any movement while the button is down
		if dragStick and (io == dragStick or (io.UserInputType == Enum.UserInputType.MouseMovement and dragStick.UserInputType == Enum.UserInputType.MouseButton1)) then
			stickFrom(io.Position)
		end
		if dragThrottle and (io == dragThrottle or (io.UserInputType == Enum.UserInputType.MouseMovement and dragThrottle.UserInputType == Enum.UserInputType.MouseButton1)) then
			throttleFrom(io.Position)
		end
	end))
	table.insert(self.connections, UserInputService.InputEnded:Connect(function(io)
		if dragStick and (io == dragStick or io.UserInputType == dragStick.UserInputType) then
			dragStick = nil
			knob.Position = UDim2.fromScale(0.5, 0.5)
			input:setStick(0, 0, false)
		end
		if dragThrottle and (io == dragThrottle or io.UserInputType == dragThrottle.UserInputType) then
			dragThrottle = nil
		end
	end))

	-------------------------------------------------------------------------------
	-- Right: toggle buttons
	local col = make("Frame", {
		Parent = root, Name = "Buttons", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, -40),
		Size = UDim2.fromOffset(176, 330), BackgroundColor3 = PANEL, BackgroundTransparency = 0.25,
	})
	round(col, 10)
	local grid = make("UIGridLayout", {
		Parent = col, CellSize = UDim2.fromOffset(80, 46), CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local _ = grid
	local order = 0
	local function pressButton(name: string, text: string, action: string): TextButton
		order += 1
		local b = make("TextButton", {
			Parent = col, Name = name, LayoutOrder = order, BackgroundColor3 = OFF, Text = text,
			Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = WHITE, TextWrapped = true, AutoButtonColor = true,
		})
		round(b, 8)
		b.Activated:Connect(function()
			input:press(action)
		end)
		self.buttons[name] = b
		return b
	end
	pressButton("Gear", "GEAR\nDOWN", "gear")
	pressButton("Engines", "ENGINES\nOFF", "engines")
	pressButton("FlapsUp", "FLAPS -", "flapsUp")
	pressButton("FlapsDown", "FLAPS +", "flapsDown")
	pressButton("Speedbrake", "AIR BRAKE\nOFF", "speedbrake")
	pressButton("Parking", "PARK\nBRAKE", "parkingBrake")
	order += 1
	local brake = holdButton(col, "Brake", "BRAKES\n(hold)", "brake", UDim2.new(), UDim2.new())
	brake.LayoutOrder = order
	brake.TextSize = 13
	order += 1
	local rev = holdButton(col, "Reverse", "REVERSE\n(hold)", "reverse", UDim2.new(), UDim2.new())
	rev.LayoutOrder = order
	rev.TextSize = 13
	pressButton("Assist", "EASY", "assist")
	pressButton("Camera", "CAMERA", "camera")
	return self
end

function FlightPanel:setFlying(on: boolean)
	self.flying = on
	self.toggleButton.Visible = on
	self.root.Visible = on and self.shown
	if not on then
		self.input:setStick(0, 0, false)
	end
end

function FlightPanel:toggle()
	self.shown = not self.shown
	self.root.Visible = self.flying and self.shown
	self.toggleButton.BackgroundColor3 = if self.shown then PANEL else BLUE
end

local function paint(b: TextButton?, text: string, color: Color3)
	if b then
		b.Text = text
		b.BackgroundColor3 = color
	end
end

-- t: FlightController telemetry
function FlightPanel:update(t: any)
	if not t or not self.root.Visible then
		return
	end
	local thr = t.throttle or 0
	self.thrFill.Size = UDim2.fromScale(1, thr)
	self.thrHandle.Position = UDim2.fromScale(0.5, 1 - thr)
	self.thrText.Text = string.format("%d%%", math.floor(thr * 100 + 0.5))
	local b = self.buttons
	local moving = t.gearExt and t.gearExt > 0.02 and t.gearExt < 0.98
	paint(b.Gear, if moving then "GEAR\nMOVING" elseif t.gearCmd then "GEAR\nDOWN" else "GEAR\nUP",
		if moving then WARN elseif t.gearCmd then ON else OFF)
	local running, starting = 0, false
	for _, e in t.n1 or {} do
		if e.running then
			running += 1
		end
		starting = starting or e.starting
	end
	local n = #(t.n1 or {})
	paint(b.Engines, if starting then "ENGINES\nSTARTING" elseif running == n and n > 0 then "ENGINES\nON" elseif running > 0 then "ENGINES\nPART" else "ENGINES\nOFF",
		if starting then WARN elseif running == n and n > 0 then ON elseif running > 0 then WARN else RED)
	local flap = t.flapCmd or "UP"
	paint(b.FlapsUp, "FLAPS -\n" .. flap, OFF)
	paint(b.FlapsDown, "FLAPS +\n" .. flap, if flap ~= "UP" then ON else OFF)
	local sb = t.speedbrake or 0
	paint(b.Speedbrake, if sb > 0.75 then "AIR BRAKE\nFULL" elseif sb > 0.2 then "AIR BRAKE\nHALF" else "AIR BRAKE\nOFF", if sb > 0.2 then WARN else OFF)
	paint(b.Parking, "PARK\nBRAKE", if t.parkingBrake then RED else OFF)
	local mode = t.assist or "easy"
	paint(b.Assist, string.upper(mode), if mode == "easy" then ON elseif mode == "assisted" then BLUE else OFF)
end

function FlightPanel:destroy()
	for _, c in self.connections do
		c:Disconnect()
	end
	self.gui:Destroy()
end

return FlightPanel
