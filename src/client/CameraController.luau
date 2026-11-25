--!strict
-- Chase, cockpit and tower cameras with mouse look, zoom and impact shake.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Units = require(Shared.Units)
local MathUtil = require(Shared.MathUtil)
local Airports = require(Shared.Airports)
local Effects = require(script.Parent.Effects)

local SPM = Units.STUDS_PER_METER

local CameraController = {}
CameraController.__index = CameraController

CameraController.MODES = { "chase", "cockpit", "tower" }
-- Seconds without looking around (right mouse drag or right stick) before the chase and
-- cockpit views ease back to straight ahead.
CameraController.RECENTER_DELAY = 10

local function defaultPitch(mode: string): number
	return if mode == "cockpit" then math.rad(-4) else math.rad(-8)
end

function CameraController.new()
	local self = setmetatable({}, CameraController) :: any
	self.mode = "chase"
	self.model = nil :: Model?
	self.cfg = nil
	self.yaw = 0
	self.pitch = math.rad(-8)
	self.zoom = 1
	self.camCF = nil :: CFrame?
	self.dragging = false
	self.lastLook = os.clock()
	self.towerPos = nil :: Vector3?
	self.connections = {}
	-- Right-mouse look is polled every frame in update() (see lookInput), so it works even
	-- when another script or a GUI swallows the mouse button events.
	self.lastMouse = nil :: Vector2?
	table.insert(self.connections, UserInputService.InputChanged:Connect(function(input, processed)
		if not self.model then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			self.zoom = math.clamp(self.zoom * (1 - input.Position.Z * 0.1), 0.35, 4)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local p = input.Position
			if p.Magnitude > 0.15 then
				self.lastLook = os.clock()
				self.yaw -= p.X * 0.05
				self.pitch = math.clamp(self.pitch + p.Y * 0.04, math.rad(-80), math.rad(70))
			end
		end
	end))
	return self
end

-- Radius (metres) of a sphere around the CoM that holds the whole aircraft.
local function aircraftRadius(cfg: any): number
	local f = cfg.geometry and cfg.geometry.fuselage
	local half = if f then math.max(-f.noseZ, f.tailEndZ) else 20
	return math.max(cfg.aero.wingSpan / 2, half)
end

function CameraController:attach(model: Model, cfg: any)
	self.model = model
	self.cfg = cfg
	self.radius = aircraftRadius(cfg)
	self.camCF = nil
	self.yaw = 0
	self.pitch = math.rad(-8)
	self:setMode(self.mode)
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	RunService:UnbindFromRenderStep("FlightCamera")
	RunService:BindToRenderStep("FlightCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		self:update(dt)
	end)
end

function CameraController:detach()
	RunService:UnbindFromRenderStep("FlightCamera")
	if self.dragging then
		self.dragging = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	self:applyCockpitVisibility(false)
	self.model = nil
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
	local character = Players.LocalPlayer.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
end

function CameraController:applyCockpitVisibility(inCockpit: boolean)
	local model = self.model
	if not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("HideInCockpit") then
				d.LocalTransparencyModifier = if inCockpit then 1 else 0
			elseif d:GetAttribute("CockpitOnly") then
				-- glass keeps some transparency inside (CockpitTransparency attribute)
				local inside = d:GetAttribute("CockpitTransparency")
				d.Transparency = if inCockpit then (if type(inside) == "number" then inside else 0) else 1
			end
		end
	end
	local character = Players.LocalPlayer.Character
	if character then
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				(d :: any).LocalTransparencyModifier = if inCockpit then 1 else 0
			end
		end
	end
end

function CameraController:setMode(mode: string)
	self.mode = mode
	self.yaw = 0
	self.pitch = defaultPitch(mode)
	self:applyCockpitVisibility(mode == "cockpit")
	self.towerPos = nil
	if mode == "tower" and self.model and self.model.PrimaryPart then
		local pos = self.model.PrimaryPart.Position
		local id = Airports.nearest(pos.X, pos.Z)
		local l = Airports.layout(id)
		local dist = (Vector3.new(l.cx, pos.Y, l.cz) - pos).Magnitude
		if dist < 9000 then
			local tx, tz = Airports.fromRunway(l, l.terminalHalfLen + 120 * SPM, (l.terminalNear + l.terminalFar) / 2)
			self.towerPos = Vector3.new(tx, l.y + 50 * SPM, tz)
		else
			-- "spotter" camera ahead of the aircraft
			local cf = self.model.PrimaryPart.CFrame
			local ahead = cf.Position + Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit * 900 + cf.RightVector * 120
			self.towerPos = ahead + Vector3.new(0, 30, 0)
		end
	end
end

-- Hold the right mouse button and drag to look around. Polled each frame:
--   * the cursor is locked in place while held (re-asserted every frame, because
--     Roblox's default camera script resets MouseBehavior);
--   * movement comes from GetMouseDelta when the lock holds, otherwise from the
--     change in cursor position, so it works either way.
function CameraController:lookInput()
	local held = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	if held then
		local loc = UserInputService:GetMouseLocation()
		if not self.dragging then
			self.dragging = true
			self.lastMouse = loc
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		local d = UserInputService:GetMouseDelta()
		if d.Magnitude < 1e-3 and self.lastMouse then
			d = loc - self.lastMouse
		end
		self.lastMouse = loc
		self.lastLook = os.clock() -- holding the look button counts as looking, even if still
		self.yaw -= d.X * 0.006
		self.pitch = math.clamp(self.pitch - d.Y * 0.006, math.rad(-80), math.rad(70))
	elseif self.dragging then
		self.dragging = false
		self.lastMouse = nil
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

function CameraController:cycle()
	local idx = table.find(CameraController.MODES, self.mode) or 1
	self:setMode(CameraController.MODES[idx % #CameraController.MODES + 1])
end

function CameraController:update(dt: number)
	local model = self.model
	if not model then
		return
	end
	local core = model.PrimaryPart
	if not core or not core.Parent then
		return
	end
	local cam = Workspace.CurrentCamera
	local cf = core.CFrame
	self:lookInput()
	-- nobody has looked around for a while: drift back to straight ahead
	local idle = os.clock() - self.lastLook
	self.yaw = MathUtil.recenter(self.yaw, 0, idle, CameraController.RECENTER_DELAY, dt)
	self.pitch = MathUtil.recenter(self.pitch, defaultPitch(self.mode), idle, CameraController.RECENTER_DELAY, dt)
	local shake = Effects.shakeAmount
	Effects.shakeAmount = math.max(0, shake - dt * 1.8)
	local shakeCF = CFrame.new()
	if shake > 0.01 then
		local s = shake * 0.6
		shakeCF = CFrame.Angles((math.random() - 0.5) * 0.02 * s, (math.random() - 0.5) * 0.02 * s, (math.random() - 0.5) * 0.01 * s)
	end

	if self.mode == "cockpit" then
		local eye = self.cfg.cameras.cockpit
		local pos = cf:PointToWorldSpace(Vector3.new(eye[1], eye[2], eye[3]) * SPM)
		local look = CFrame.Angles(0, self.yaw, 0) * CFrame.Angles(self.pitch, 0, 0)
		cam.CFrame = CFrame.new(pos) * cf.Rotation * look * shakeCF
		cam.FieldOfView = 75
	elseif self.mode == "tower" and self.towerPos then
		local target = cf.Position
		cam.CFrame = CFrame.lookAt(self.towerPos, target) * shakeCF
		local dist = (target - self.towerPos).Magnitude
		cam.FieldOfView = math.clamp(math.deg(2 * math.atan(260 / math.max(dist, 1))), 6, 70)
	else
		-- Chase: follow heading and pitch with lag, ignore most of the roll.
		local look = cf.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.05 then
			flat = Vector3.new(cf.UpVector.X, 0, cf.UpVector.Z)
		end
		flat = flat.Unit
		local pitchA = math.asin(math.clamp(look.Y, -1, 1)) * 0.7
		local basis = CFrame.lookAt(Vector3.zero, flat) * CFrame.Angles(pitchA, 0, 0)
		local alpha = 1 - math.exp(-dt * 5)
		local lagged = if self.camCF then (self.camCF :: CFrame):Lerp(basis, alpha) else basis
		self.camCF = lagged
		local orbit = lagged * CFrame.Angles(0, self.yaw, 0) * CFrame.Angles(self.pitch, 0, 0)
		-- never closer than the aircraft's own size, or the camera ends up inside the
		-- fuselage or a wing and the aircraft seems to vanish (faces are one-sided)
		local minDist = (self.radius * 1.3 + 6) * SPM
		local dist = math.max(self.cfg.cameras.chaseDistance * SPM * self.zoom, minDist)
		local height = self.cfg.cameras.chaseHeight * SPM * math.sqrt(self.zoom)
		local target = cf.Position + Vector3.new(0, height * 0.35, 0)
		local camPos = target + orbit:VectorToWorldSpace(Vector3.new(0, height * 0.5, dist))
		-- keep the camera above the ground and water (looking up from below the runway
		-- would hide everything)
		self.rayParams = self.rayParams or RaycastParams.new()
		local params = self.rayParams :: RaycastParams
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model, Players.LocalPlayer.Character :: any }
		params.IgnoreWater = false
		local hit = Workspace:Raycast(camPos + Vector3.new(0, 400, 0), Vector3.new(0, -800, 0), params)
		if hit and camPos.Y < hit.Position.Y + 3 * SPM then
			camPos = Vector3.new(camPos.X, hit.Position.Y + 3 * SPM, camPos.Z)
		end
		cam.CFrame = CFrame.lookAt(camPos, target + lagged.LookVector * 20) * shakeCF
		cam.FieldOfView = 70
	end
end

return CameraController
