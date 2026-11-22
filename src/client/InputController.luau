--!strict
-- Keyboard / gamepad input -> raw pilot controls. Digital keys ramp smoothly so a tap
-- is a small input and a hold is a full deflection. Uses ContextActionService with a
-- high priority and sinks the keys while flying, so the default character controls
-- (including Space = jump out of the seat) never fire mid-flight.

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local InputController = {}
InputController.__index = InputController

local PRIORITY = Enum.ContextActionPriority.High.Value + 50

-- Default bindings (shown in the in-game help).
InputController.BINDINGS = {
	{ "W / S", "Pitch down / up" },
	{ "A / D", "Roll left / right" },
	{ "Q / E", "Rudder + nose-wheel steering" },
	{ "Shift / Ctrl", "Throttle up / down" },
	{ "I", "Start / stop engines" },
	{ "G", "Landing gear" },
	{ "F / V", "Flaps down / up" },
	{ "B", "Wheel brakes (hold)" },
	{ "P", "Parking brake" },
	{ "Z", "Reverse thrust (hold, on ground)" },
	{ "X", "Speedbrake" },
	{ "[ / ]", "Pitch trim (Simulation mode)" },
	{ "T", "Assisted / Simulation" },
	{ "C", "Camera: chase / cockpit / tower" },
	{ "Right mouse drag", "Look around" },
	{ "Mouse wheel", "Camera distance" },
	{ "H", "Hide HUD" },
	{ "F3", "Debug panel" },
	{ "M", "Menu (aircraft, mode, spawn, weather, failures)" },
	{ "R", "Reset / respawn" },
}

export type Raw = {
	pitch: number, roll: number, yaw: number, throttle: number,
	flaps: number, gearDown: boolean, brake: number, parkingBrake: boolean,
	speedbrake: number, reverse: boolean, trim: number,
}

function InputController.new(callbacks: { [string]: () -> () })
	local self = setmetatable({}, InputController) :: any
	self.callbacks = callbacks
	self.held = {} :: { [string]: boolean }
	self.raw = {
		pitch = 0, roll = 0, yaw = 0, throttle = 0, flaps = 1, gearDown = true,
		brake = 0, parkingBrake = false, speedbrake = 0, reverse = false, trim = 0,
	} :: Raw
	self.maxFlaps = 5
	self.gamepad = { lx = 0, ly = 0, lt = 0, rt = 0, lb = false, rb = false }
	self.bound = false
	return self
end

local HOLD_KEYS = {
	[Enum.KeyCode.W] = "pitchDown", [Enum.KeyCode.Up] = "pitchDown",
	[Enum.KeyCode.S] = "pitchUp", [Enum.KeyCode.Down] = "pitchUp",
	[Enum.KeyCode.A] = "rollLeft", [Enum.KeyCode.Left] = "rollLeft",
	[Enum.KeyCode.D] = "rollRight", [Enum.KeyCode.Right] = "rollRight",
	[Enum.KeyCode.Q] = "yawLeft", [Enum.KeyCode.E] = "yawRight",
	[Enum.KeyCode.LeftShift] = "throttleUp", [Enum.KeyCode.LeftControl] = "throttleDown",
	[Enum.KeyCode.B] = "brake", [Enum.KeyCode.Z] = "reverse",
	[Enum.KeyCode.LeftBracket] = "trimDown", [Enum.KeyCode.RightBracket] = "trimUp",
	[Enum.KeyCode.ButtonL1] = "yawLeft", [Enum.KeyCode.ButtonR1] = "yawRight",
	[Enum.KeyCode.ButtonB] = "brake",
}

local PRESS_KEYS = {
	[Enum.KeyCode.G] = "gear", [Enum.KeyCode.ButtonX] = "gear",
	[Enum.KeyCode.F] = "flapsDown", [Enum.KeyCode.DPadDown] = "flapsDown",
	[Enum.KeyCode.V] = "flapsUp", [Enum.KeyCode.DPadUp] = "flapsUp",
	[Enum.KeyCode.P] = "parkingBrake", [Enum.KeyCode.DPadLeft] = "parkingBrake",
	[Enum.KeyCode.X] = "speedbrake", [Enum.KeyCode.DPadRight] = "speedbrake",
	[Enum.KeyCode.I] = "engines", [Enum.KeyCode.ButtonY] = "engines",
	[Enum.KeyCode.T] = "assist",
	[Enum.KeyCode.C] = "camera", [Enum.KeyCode.ButtonSelect] = "camera",
	[Enum.KeyCode.H] = "hud",
	[Enum.KeyCode.F3] = "debug",
	[Enum.KeyCode.M] = "menu", [Enum.KeyCode.ButtonStart] = "menu",
	[Enum.KeyCode.R] = "reset",
}

function InputController:_handle(_actionName: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local key = input.KeyCode
	if input.UserInputType == Enum.UserInputType.Gamepad1 then
		if key == Enum.KeyCode.Thumbstick1 then
			self.gamepad.lx = input.Position.X
			self.gamepad.ly = input.Position.Y
			return Enum.ContextActionResult.Sink
		elseif key == Enum.KeyCode.ButtonR2 then
			self.gamepad.rt = input.Position.Z
			return Enum.ContextActionResult.Sink
		elseif key == Enum.KeyCode.ButtonL2 then
			self.gamepad.lt = input.Position.Z
			return Enum.ContextActionResult.Sink
		end
	end
	local hold = HOLD_KEYS[key]
	if hold then
		self.held[hold] = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
		return Enum.ContextActionResult.Sink
	end
	local press = PRESS_KEYS[key]
	if press then
		if state == Enum.UserInputState.Begin then
			self:_press(press)
		end
		return Enum.ContextActionResult.Sink
	end
	if key == Enum.KeyCode.Space or key == Enum.KeyCode.ButtonA then
		return Enum.ContextActionResult.Sink -- never jump out of the seat
	end
	return Enum.ContextActionResult.Pass
end

function InputController:_press(name: string)
	local raw = self.raw
	if name == "gear" then
		raw.gearDown = not raw.gearDown
	elseif name == "flapsDown" then
		raw.flaps = math.min(self.maxFlaps, raw.flaps + 1)
	elseif name == "flapsUp" then
		raw.flaps = math.max(1, raw.flaps - 1)
	elseif name == "parkingBrake" then
		raw.parkingBrake = not raw.parkingBrake
	elseif name == "speedbrake" then
		raw.speedbrake = if raw.speedbrake < 0.25 then 0.5 elseif raw.speedbrake < 0.75 then 1 else 0
	end
	local cb = self.callbacks[name]
	if cb then
		cb()
	end
end

function InputController:bind()
	if self.bound then
		return
	end
	self.bound = true
	local keys = {}
	for k in HOLD_KEYS do
		table.insert(keys, k)
	end
	for k in PRESS_KEYS do
		table.insert(keys, k)
	end
	table.insert(keys, Enum.KeyCode.Space)
	table.insert(keys, Enum.KeyCode.ButtonA)
	table.insert(keys, Enum.KeyCode.Thumbstick1)
	table.insert(keys, Enum.KeyCode.ButtonR2)
	table.insert(keys, Enum.KeyCode.ButtonL2)
	ContextActionService:BindActionAtPriority("FlightControls", function(a, s, i)
		return self:_handle(a, s, i)
	end, false, PRIORITY, table.unpack(keys))
end

function InputController:unbind()
	if not self.bound then
		return
	end
	self.bound = false
	ContextActionService:UnbindAction("FlightControls")
	table.clear(self.held)
end

local function ramp(current: number, target: number, rate: number, dt: number): number
	local d = target - current
	local maxStep = rate * dt
	if math.abs(d) <= maxStep then
		return target
	end
	return current + math.sign(d) * maxStep
end

-- Advance continuous axes. Returns the raw control table.
function InputController:update(dt: number): Raw
	local h, raw, gp = self.held, self.raw, self.gamepad
	local function axis(neg: string, pos: string): number
		return (if h[pos] then 1 else 0) - (if h[neg] then 1 else 0)
	end
	local pitchT = axis("pitchDown", "pitchUp")
	local rollT = axis("rollLeft", "rollRight")
	local yawT = axis("yawLeft", "yawRight")
	-- gamepad overrides when deflected (deadzone 0.12)
	if math.abs(gp.ly) > 0.12 then
		pitchT = -gp.ly
	end
	if math.abs(gp.lx) > 0.12 then
		rollT = gp.lx
	end
	-- Keyboard: ramp up over ~0.35 s, return to centre faster.
	local function rate(cur: number, tgt: number): number
		return if math.abs(tgt) > math.abs(cur) then 2.8 else 4.5
	end
	raw.pitch = ramp(raw.pitch, pitchT, rate(raw.pitch, pitchT), dt)
	raw.roll = ramp(raw.roll, rollT, rate(raw.roll, rollT), dt)
	raw.yaw = ramp(raw.yaw, yawT, rate(raw.yaw, yawT), dt)

	local thr = axis("throttleDown", "throttleUp")
	if gp.rt > 0.05 or gp.lt > 0.05 then
		thr = gp.rt - gp.lt
	end
	raw.throttle = math.clamp(raw.throttle + thr * 0.45 * dt, 0, 1)
	raw.brake = if h.brake then 1 else 0
	raw.reverse = h.reverse == true
	raw.trim = math.clamp(raw.trim + axis("trimDown", "trimUp") * 0.25 * dt, -1, 1)
	return raw
end

function InputController.isTyping(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

return InputController
