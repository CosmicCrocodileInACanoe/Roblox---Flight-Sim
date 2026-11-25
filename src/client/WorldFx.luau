--!strict
-- Local presentation of the shared world: weather (wind, gusts, turbulence, haze),
-- time of day, PAPI light colours seen from this camera, windsocks, beacons/strobes,
-- and animation of OTHER players' aircraft from their replicated system attributes.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Units = require(Shared.Units)
local Registry = require(Shared.AircraftRegistry)
local FlightModel = require(Shared.FlightModel)
local WorldGen = require(Shared.WorldGen)
local DetailStreamer = require(script.Parent.DetailStreamer)

local WorldFx = {}

local weather = { windKts = 0, windFrom = 270, gustKts = 0, turbulence = 0, fog = 0 }
local papis: { BasePart } = {}
local socks: { BasePart } = {}
local scanned = false

function WorldFx.setWeather(w: any)
	weather = w
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		-- Clear days use the long-visibility base; fog thickens it the same way as before.
		atm.Density = WorldGen.atmosphere.density + w.fog * 0.6
		atm.Haze = WorldGen.atmosphere.haze + w.fog * 4
	end
	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds.Cover = math.clamp(0.5 + w.fog * 0.9 + w.turbulence * 0.15, 0, 1)
		clouds.Density = math.clamp(0.55 + w.fog, 0, 1)
	end
end

function WorldFx.setTime(t: any)
	Lighting.ClockTime = t.clock
	local night = t.clock > 20 or t.clock < 6
	Lighting.Brightness = if night then 0.6 else 2.6
	Lighting.OutdoorAmbient = if night then Color3.fromRGB(40, 46, 60) else Color3.fromRGB(118, 122, 132)
end

-- Wind at a world position (m/s, world axes). Mean wind + gusts + turbulence that
-- fades near the ground. Deterministic noise so it is smooth frame to frame.
function WorldFx.wind(pos: Vector3, t: number): Vector3
	local fromRad = math.rad(weather.windFrom)
	-- wind blows FROM windFrom, i.e. toward windFrom + 180
	local dx, dz = Units.xzFromHeading(weather.windFrom + 180)
	local alt = pos.Y * Units.METERS_PER_STUD
	local shear = math.clamp(0.7 + alt / 900, 0.7, 1.4)
	local base = weather.windKts * Units.MPS_PER_KT * shear
	local gust = weather.gustKts * Units.MPS_PER_KT * math.max(0, math.noise(t * 0.15, 3.1, 0.2))
	local mean = Vector3.new(dx, 0, dz) * (base + gust)
	local turb = weather.turbulence * 2.2 * math.clamp(alt / 150, 0.2, 1)
	local p = pos / 400
	local tx = math.noise(p.X + t * 0.6, p.Y, 1.7) * turb
	local ty = math.noise(p.Z + t * 0.7, p.X, 5.3) * turb * 0.8
	local tz = math.noise(p.Y + t * 0.5, p.Z, 9.1) * turb
	local _ = fromRad
	return mean + Vector3.new(tx, ty, tz)
end

local function scan()
	scanned = true
	local world = Workspace:FindFirstChild("World")
	if not world then
		scanned = false
		return
	end
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("PapiIndex") then
				table.insert(papis, d)
			elseif d:GetAttribute("Windsock") then
				table.insert(socks, d)
			end
		end
	end
end

local accum = 0
local beaconT = 0
function WorldFx.update(dt: number, localModel: Model?)
	DetailStreamer.update(dt)
	if not scanned then
		scan()
	end
	accum += dt
	beaconT += dt
	if accum < 0.1 then
		return
	end
	accum = 0
	local cam = Workspace.CurrentCamera
	local eye = cam.CFrame.Position
	-- PAPI: white above the unit's angle, red below.
	for _, p in papis do
		local d = p.Position - eye
		local horiz = math.sqrt(d.X * d.X + d.Z * d.Z)
		if horiz < 20000 then
			local elev = math.deg(math.atan2(eye.Y - p.Position.Y, horiz))
			local angle = p:GetAttribute("PapiAngle") :: number
			p.Color = if elev > angle then Color3.fromRGB(255, 255, 245) else Color3.fromRGB(255, 40, 40)
		end
	end
	-- Windsocks point downwind; droop when calm.
	local w = WorldFx.wind(Vector3.new(0, 20, 0), os.clock())
	local flat = Vector3.new(w.X, 0, w.Z)
	local strength = math.clamp(flat.Magnitude / 8, 0, 1)
	for _, s in socks do
		local pivot = Vector3.new(s:GetAttribute("PivotX") :: number, s:GetAttribute("PivotY") :: number, s:GetAttribute("PivotZ") :: number)
		local dir = if flat.Magnitude > 0.2 then flat.Unit else Vector3.new(1, 0, 0)
		local droop = (1 - strength) * math.rad(70)
		local cf = CFrame.lookAt(pivot, pivot + dir) * CFrame.Angles(-droop, 0, 0)
		-- cylinder axis is X: rotate so X points along the look direction
		s.CFrame = cf * CFrame.new(0, 0, -s.Size.X / 2) * CFrame.Angles(0, math.rad(90), 0)
	end
	-- Beacons blink on every aircraft; other players' aircraft get gear/flap animation.
	local blink = (beaconT % 1.2) < 0.15
	local aircraft = Workspace:FindFirstChild("Aircraft")
	if aircraft then
		for _, m in aircraft:GetChildren() do
			if m:IsA("Model") then
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") and d:GetAttribute("Beacon") then
						d.Transparency = if blink then 0 else 0.85
					end
				end
				if m ~= localModel then
					WorldFx.animateRemote(m)
				end
			end
		end
	end
end

-- Other players' aircraft: gear, flaps, spoilers and fans from replicated attributes.
function WorldFx.animateRemote(m: Model)
	local cfg = Registry.get(m:GetAttribute("AircraftId") :: string)
	if not cfg then
		return
	end
	local gearDown = m:GetAttribute("Sys_GearDown")
	local ext = (m:GetAttribute("_ext") :: number?) or (if gearDown == false then 0 else 1)
	local target = if gearDown == false then 0 else 1
	ext += math.clamp(target - ext, -0.1 / cfg.gear.retractTime, 0.1 / cfg.gear.retractTime)
	m:SetAttribute("_ext", ext)
	local flaps = (m:GetAttribute("Sys_Flaps") :: number?) or 1
	local flapDeg = FlightModel.notchLerp(cfg.aero.flaps.deflectionDeg, flaps)
	local sb = (m:GetAttribute("Sys_Speedbrake") :: number?) or 0
	for _, d in m:GetDescendants() do
		if d:IsA("Motor6D") then
			local kind = d:GetAttribute("Surface")
			if kind == "Flap" then
				d.Transform = CFrame.Angles(math.rad(flapDeg), 0, 0)
			elseif kind == "Spoiler" then
				d.Transform = CFrame.Angles(-math.rad(50) * sb, 0, 0)
			elseif d:GetAttribute("GearName") then
				for _, u in cfg.gear.units do
					if u.name == d:GetAttribute("GearName") then
						local a = math.rad(u.retractAngleDeg) * (1 - ext)
						d.Transform = if u.retractAxis == "x" then CFrame.Angles(a, 0, 0) else CFrame.Angles(0, 0, a)
					end
				end
			end
		end
	end
	local _ = Players
end

return WorldFx
