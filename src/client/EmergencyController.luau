--!strict
-- The emergency services, on every client (visual only; see Shared/Rescue and
-- server/EmergencyService). When the server announces an incident this builds the
-- vehicles and drives them to the scene:
--   land_crash   police cars, fire trucks and ambulances drive in from the nearest
--                airport or town, park round the wreck with their lights going, and the
--                fire trucks spray water on it.
--   water_crash  rescue boats sail out and helicopters circle overhead with searchlights.
--   ditch        rescue boats and a ferry sail out, life rafts carry the passengers
--                across, and the helicopter circles. The pilot is told how many
--                passengers are safe.
-- Fix all, Reset or a new flight clears the incident and the vehicles are removed.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rescue = require(Shared.Rescue)
local Registry = require(Shared.AircraftRegistry)
local Selection = require(Shared.Selection)
local Airports = require(Shared.Airports)
local WorldGen = require(Shared.WorldGen)
local Units = require(Shared.Units)
local ResponderModels = require(script.Parent.ResponderModels)

local SPM = Units.STUDS_PER_METER
local SEA = WorldGen.SEA_LEVEL
local MAX_AGE = 260 -- s; the server clears them at 240

local FLASH_COLORS = {
	red = Color3.fromRGB(255, 40, 30),
	blue = Color3.fromRGB(40, 90, 255),
	white = Color3.fromRGB(255, 255, 255),
	amber = Color3.fromRGB(255, 170, 20),
}
local FLASH_OFF = Color3.fromRGB(50, 50, 54)

local EmergencyController = {}
EmergencyController.__index = EmergencyController

type Vehicle = {
	model: Model,
	root: BasePart,
	role: string,
	kind: string, -- "ground" | "boat" | "air"
	pts: { Vector3 },
	cum: { number },
	total: number,
	speed: number, -- studs/s
	delay: number,
	s: number,
	state: string, -- "waiting" | "driving" | "arrived" | "leaving" | "gone"
	arrivedAt: number?,
	target: Vector3, -- what it faces once there (the wreck)
	flash: { BasePart },
	hub: BasePart?,
	spray: ParticleEmitter?,
	phase: number,
	orbit: number,
	yaw: CFrame?,
}

type Raft = {
	model: Model,
	share: number,
	target: Vehicle?,
	state: string, -- "waiting" | "moving" | "done"
	pos: Vector3,
	from: Vector3?,
	to: Vector3?,
	t0: number,
	phase: number,
}

local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = {}
	for _, name in { "Aircraft", "Debris", "LocalEffects", "Responders", "Craters", "Wildfires" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	params.FilterDescendantsInstances = list
	return params
end

-- Road height: the runway/ground part under (x, z) if it is close to the terrain mesh,
-- otherwise the mesh itself (so trucks don't climb onto roofs or trees).
local function groundY(params: RaycastParams, x: number, z: number): number
	local mh = WorldGen.meshHeight(x, z)
	local hit = Workspace:Raycast(Vector3.new(x, mh + 300, z), Vector3.new(0, -600, 0), params)
	if hit and hit.Position.Y <= mh + 15 and hit.Position.Y >= mh - 5 then
		return hit.Position.Y
	end
	return math.max(mh, SEA)
end

local function isLand(x: number, z: number): boolean
	return WorldGen.meshHeight(x, z) > SEA + 1
end

local function isSea(x: number, z: number): boolean
	return WorldGen.meshHeight(x, z) < SEA - 6
end

-- Angle (atan2(z, x), the convention Rescue.slot uses) from (x, z) toward the nearest
-- airport or town: where the crews come from. Also returns how far away it is.
local function homeAngle(x: number, z: number, airportsOnly: boolean?): (number, number)
	local best, bestD, bx, bz = nil, math.huge, x + 1, z
	for _, id in Airports.order do
		local l = Airports.layout(id)
		local d = math.sqrt((l.cx - x) ^ 2 + (l.cz - z) ^ 2)
		if d < bestD then
			best, bestD, bx, bz = id, d, l.cx, l.cz
		end
	end
	if not airportsOnly then
		for _, c in WorldGen.cities do
			local d = math.sqrt((c.x - x) ^ 2 + (c.z - z) ^ 2)
			if d < bestD then
				best, bestD, bx, bz = c.id, d, c.x, c.z
			end
		end
	end
	local _ = best
	return math.atan2(bz - z, bx - x), bestD
end

-- Turn `default` (an angle from the scene, as homeAngle) until a start point `dist`
-- studs out at height y is inside the local camera's view, so the crews can be seen
-- coming in. In the chase view that is mostly the far side of the wreck. Points nearer
-- the middle of the screen win; if none is on screen, `default` stands.
local function viewAngle(x: number, y: number, z: number, dist: number, default: number): number
	local cam = Workspace.CurrentCamera
	if not cam then
		return default
	end
	local vp = cam.ViewportSize
	local best, bestScore = default, math.huge
	for k = 0, 23 do
		local a = default + k * math.rad(15)
		local p = Vector3.new(x + math.cos(a) * dist, y, z + math.sin(a) * dist)
		local sp, on = cam:WorldToViewportPoint(p)
		if on and sp.Z > 0 then
			local dx = (sp.X - vp.X / 2) / math.max(vp.X, 1)
			local dy = (sp.Y - vp.Y / 2) / math.max(vp.Y, 1)
			-- off-centre costs, and so does turning far from the way home
			local turn = math.abs(((k * 15 + 180) % 360) - 180) / 180
			local score = dx * dx + dy * dy + turn * 0.05
			if score < bestScore then
				best, bestScore = a, score
			end
		end
	end
	return best
end

local function buildPath(pts: { Vector3 }): ({ number }, number)
	local cum = { 0 }
	for i = 2, #pts do
		cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	return cum, cum[#cum]
end

local function sample(v: Vehicle, s: number): Vector3
	local pts, cum = v.pts, v.cum
	if s <= 0 then
		return pts[1]
	end
	if s >= v.total then
		return pts[#pts]
	end
	local lo, hi = 1, #pts
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if cum[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local seg = cum[hi] - cum[lo]
	local a = if seg > 0 then (s - cum[lo]) / seg else 0
	return pts[lo]:Lerp(pts[hi], a)
end

-- A straight route from a to b sampled every 40 studs, at height h(x, z).
local function route(a: Vector3, b: Vector3, h: (number, number) -> number): { Vector3 }
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local n = math.max(1, math.ceil(flat.Magnitude / 40))
	local out = {}
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		table.insert(out, Vector3.new(p.X, h(p.X, p.Z), p.Z))
	end
	return out
end

function EmergencyController.new(remotes: Folder, notify: (string) -> ())
	local self = setmetatable({}, EmergencyController) :: any
	self.notify = notify
	self.incidents = {} :: { [string]: any }
	self.folder = Instance.new("Folder")
	self.folder.Name = "Responders"
	self.folder.Parent = Workspace
	self.time = 0
	;(remotes:WaitForChild("Emergency") :: RemoteEvent).OnClientEvent:Connect(function(data: any)
		local ok, err = pcall(function()
			self:start(data)
		end)
		if not ok then
			warn("[Emergency] " .. tostring(err))
		end
	end)
	;(remotes:WaitForChild("EmergencyClear") :: RemoteEvent).OnClientEvent:Connect(function(id: any)
		if type(id) == "string" then
			self:clear(id)
		end
	end)
	return self
end

function EmergencyController:clear(id: string)
	local inc = self.incidents[id]
	if inc then
		self.incidents[id] = nil
		inc.folder:Destroy()
	end
end

local function collectFlash(m: Model): { BasePart }
	local out = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Flash") then
			table.insert(out, d)
		end
	end
	return out
end

function EmergencyController:addVehicle(inc: any, role: string, kind: string, pts: { Vector3 }, speedMps: number, delay: number): Vehicle
	local model, hub
	if role == "fireTruck" then
		model = ResponderModels.fireTruck()
	elseif role == "ambulance" then
		model = ResponderModels.ambulance()
	elseif role == "police" then
		model = ResponderModels.police()
	elseif role == "rescueBoat" then
		model = ResponderModels.rescueBoat()
	elseif role == "ferry" then
		model = ResponderModels.ferry()
	else
		model, hub = ResponderModels.helicopter()
	end
	local root = model.PrimaryPart :: BasePart
	local cum, total = buildPath(pts)
	local v: Vehicle = {
		model = model, root = root, role = role, kind = kind, pts = pts, cum = cum, total = total,
		speed = speedMps * SPM, delay = delay, s = 0, state = "waiting", arrivedAt = nil,
		target = inc.pos, flash = collectFlash(model), hub = hub, spray = nil,
		phase = math.random() * 6.28, orbit = math.random() * 6.28, yaw = nil,
	}
	if role == "fireTruck" then
		local nozzle = model:FindFirstChild("Nozzle") :: BasePart?
		if nozzle then
			-- tilt the cannon up so the jet arcs onto the wreck
			local att = Instance.new("Attachment")
			att.CFrame = CFrame.new(0, 0, -1.7) * CFrame.Angles(math.rad(24), 0, 0)
			att.Parent = nozzle
			local e = Instance.new("ParticleEmitter")
			e.EmissionDirection = Enum.NormalId.Front
			e.Color = ColorSequence.new(Color3.fromRGB(220, 236, 255))
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.9) })
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3.5) })
			e.Speed = NumberRange.new(68, 76)
			e.SpreadAngle = Vector2.new(4, 4)
			e.Lifetime = NumberRange.new(2, 2.6)
			e.Acceleration = Vector3.new(0, -Units.GRAVITY_STUDS, 0)
			e.Rate = 90
			e.Enabled = false
			e.Parent = att
			v.spray = e
		end
	end
	-- Parent first: the welds take hold at the offsets the model was built with, and
	-- from then on moving the Root carries every welded part along.
	model.Parent = inc.folder
	local p0, p1 = pts[1], pts[math.min(2, #pts)]
	local dir = Vector3.new(p1.X - p0.X, 0, p1.Z - p0.Z)
	root.CFrame = if dir.Magnitude > 0.1 then CFrame.lookAt(p0, p0 + dir) else CFrame.new(p0)
	if hub then
		hub.CFrame = root.CFrame * CFrame.new(0, 5.6, 0)
	end
	table.insert(inc.vehicles, v)
	return v
end

function EmergencyController:start(data: any)
	if type(data) ~= "table" or type(data.id) ~= "string" or typeof(data.pos) ~= "Vector3" then
		return
	end
	if not Rescue.SITUATIONS[data.situation] or self.incidents[data.id] then
		return
	end
	local cfg = Registry.get(data.aircraftId)
	local spanM = if cfg then (Selection.dimensions(cfg)) else 30
	local pos: Vector3 = data.pos
	local folder = Instance.new("Folder")
	folder.Name = "Incident_" .. data.id
	folder.Parent = self.folder
	local inc = {
		id = data.id, situation = data.situation, pos = pos, ownerUserId = data.ownerUserId,
		mine = data.ownerUserId == Players.LocalPlayer.UserId, passengers = tonumber(data.passengers) or 1,
		rescued = 0, t = 0, vehicles = {} :: { Vehicle }, rafts = {} :: { Raft }, raftsOut = false,
		folder = folder, cfg = cfg, spanM = spanM, leaveAt = nil :: number?, done = false,
	}
	self.incidents[data.id] = inc
	local params = rayParams()
	local x, z = pos.X, pos.Z
	local plan = Rescue.plan(data.situation)

	if data.situation == Rescue.LAND_CRASH then
		local home, homeDist = homeAngle(x, z)
		local radius = (spanM * 0.5 + 14) * SPM
		local nGround = 0
		for _, u in plan do
			nGround += u.count
		end
		local startDist = math.clamp(homeDist, radius + 120, plan[1].distM * SPM)
		local angle = viewAngle(x, pos.Y + 5, z, startDist, home)
		local sx, sz, a = Rescue.findStart(isLand, x, z, startDist, angle, radius)
		if not sx or not sz or not a then
			a = angle
			sx, sz = x + math.cos(angle) * (radius + 200), z + math.sin(angle) * (radius + 200)
		end
		local slotI = 0
		for _, u in plan do
			for k = 1, u.count do
				slotI += 1
				local dx, dz = Rescue.slot(slotI, nGround, radius, a :: number)
				-- queue up along the road, side by side in two lanes
				local back = (slotI - 1) * 6
				local lane = (if slotI % 2 == 0 then 1 else -1) * 7
				local ux, uz = math.cos(a :: number), math.sin(a :: number)
				local s0x = (sx :: number) + ux * back - uz * lane
				local s0z = (sz :: number) + uz * back + ux * lane
				local fromP = Vector3.new(s0x, 0, s0z)
				local toP = Vector3.new(x + dx, 0, z + dz)
				local pts = route(fromP, toP, function(px, pz)
					return groundY(params, px, pz)
				end)
				self:addVehicle(inc, u.role, "ground", pts, u.speed, u.delay + (k - 1) * 1.2)
			end
		end
	else
		local boatDist = 150 * SPM
		for _, u in plan do
			if u.role == "rescueBoat" then
				boatDist = u.distM * SPM
			end
		end
		local angle = viewAngle(x, SEA + 3, z, boatDist, (homeAngle(x, z)))
		local airAngle = viewAngle(x, SEA + 60, z, 350 * SPM, (homeAngle(x, z, true)))
		local boatRadius = (spanM * 0.5 + 16) * SPM
		local nBoats = 0
		for _, u in plan do
			if u.role == "rescueBoat" then
				nBoats += u.count
			end
		end
		local function water(_px: number, _pz: number): number
			return SEA
		end
		local bi = 0
		for _, u in plan do
			for k = 1, u.count do
				if u.role == "rescueBoat" then
					bi += 1
					local sx, sz, a = Rescue.findStart(isSea, x, z, u.distM * SPM, angle + (bi - 1) * 0.35, boatRadius)
					if not sx or not sz or not a then
						a = angle
						sx, sz = x + math.cos(angle) * (boatRadius + 150), z + math.sin(angle) * (boatRadius + 150)
					end
					local dx, dz = Rescue.slot(bi, math.max(nBoats, 2), boatRadius, a :: number)
					local pts = route(Vector3.new(sx :: number, 0, sz :: number), Vector3.new(x + dx, 0, z + dz), water)
					self:addVehicle(inc, u.role, "boat", pts, u.speed, u.delay + (k - 1) * 1.5)
				elseif u.role == "ferry" then
					local r = (spanM * 0.5 + 40) * SPM
					local fa = viewAngle(x, SEA + 10, z, u.distM * SPM, angle + math.rad(35))
					local sx, sz, a = Rescue.findStart(isSea, x, z, u.distM * SPM, fa, r)
					if not sx or not sz or not a then
						a = angle + math.rad(70)
						sx, sz = x + math.cos(a :: number) * (r + 200), z + math.sin(a :: number) * (r + 200)
					end
					local pts = route(Vector3.new(sx :: number, 0, sz :: number), Vector3.new(x + math.cos(a :: number) * r, 0, z + math.sin(a :: number) * r), water)
					self:addVehicle(inc, u.role, "boat", pts, u.speed, u.delay)
				else -- helicopter
					local a = airAngle + (k - 1) * 0.6
					local d = u.distM * SPM
					-- low enough to stay in the chase view over the wreck
					local hoverH = SEA + 45 + (k - 1) * 18
					local from = Vector3.new(x + math.cos(a) * d, SEA + 140, z + math.sin(a) * d)
					local to = Vector3.new(x + math.cos(a) * 60, hoverH, z + math.sin(a) * 60)
					local pts = {}
					for i = 0, 20 do
						local f = i / 20
						local p = from:Lerp(to, f)
						-- cruise high, come down over the last third
						local y = if f < 0.66 then from.Y else from.Y + (hoverH - from.Y) * ((f - 0.66) / 0.34)
						table.insert(pts, Vector3.new(p.X, y, p.Z))
					end
					local v = self:addVehicle(inc, u.role, "air", pts, u.speed, u.delay + (k - 1) * 2)
					v.orbit = a
				end
			end
		end
	end
	-- Joining late: catch up quickly.
	local age = math.clamp(tonumber(data.age) or 0, 0, MAX_AGE)
	while inc.t < age do
		self:stepIncident(inc, math.min(0.5, age - inc.t))
	end
end

-- Life rafts beside the ditched aircraft, by the doors on both sides.
function EmergencyController:launchRafts(inc: any)
	inc.raftsOut = true
	local shares = Rescue.rafts(inc.passengers)
	local model: Model? = nil
	local aircraft = Workspace:FindFirstChild("Aircraft")
	if aircraft then
		for _, m in aircraft:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("OwnerUserId") == inc.ownerUserId then
				model = m
			end
		end
	end
	local core = model and model.PrimaryPart
	local cf = if core then core.CFrame else CFrame.new(inc.pos)
	local cfg = inc.cfg
	local fusR = (cfg and cfg.geometry and cfg.geometry.fuselage and cfg.geometry.fuselage.radius) or 1.5
	local nose = (cfg and cfg.geometry and cfg.geometry.fuselage and cfg.geometry.fuselage.noseZ) or -6
	local carriers: { Vehicle } = {}
	for _, v in inc.vehicles do
		if v.role == "ferry" then
			table.insert(carriers, 1, v)
		elseif v.role == "rescueBoat" then
			table.insert(carriers, v)
		end
	end
	for j, share in shares do
		local side = if j % 2 == 1 then -1 else 1
		local z = if j <= 2 then nose * 0.55 else -nose * 0.6
		local lp = Vector3.new(side * (fusR + 5), 0, z) * SPM
		local wp = cf:PointToWorldSpace(lp)
		local raft = ResponderModels.lifeRaft()
		local p = Vector3.new(wp.X, SEA, wp.Z)
		raft.Parent = inc.folder
		;(raft.PrimaryPart :: BasePart).CFrame = CFrame.new(p)
		table.insert(inc.rafts, {
			model = raft, share = share, target = if #carriers > 0 then carriers[((j - 1) % #carriers) + 1] else nil,
			state = "waiting", pos = p, t0 = 0, phase = math.random() * 6.28,
		})
	end
end

local function faceFlat(pos: Vector3, toward: Vector3): CFrame
	local d = Vector3.new(toward.X - pos.X, 0, toward.Z - pos.Z)
	if d.Magnitude < 0.1 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, pos + d)
end

function EmergencyController:stepVehicle(inc: any, v: Vehicle, dt: number)
	local t = inc.t
	if v.state == "gone" then
		return
	end
	if v.state == "waiting" then
		if t >= v.delay then
			v.state = "driving"
		end
	elseif v.state == "driving" or v.state == "leaving" then
		local remaining = if v.state == "driving" then v.total - v.s else v.s
		local ease = if v.state == "driving" then math.clamp(remaining / 80, 0.2, 1) else math.clamp(v.s / 80 + 0.3, 0.3, 1)
		local step = v.speed * ease * dt
		v.s += if v.state == "driving" then step else -step
		if v.state == "driving" and v.s >= v.total then
			v.s = v.total
			v.state = "arrived"
			v.arrivedAt = t
		elseif v.state == "leaving" and v.s <= 0 then
			v.state = "gone"
			v.model:Destroy()
			return
		end
	end
	local root = v.root
	local cf: CFrame
	if v.state == "arrived" then
		local p = v.pts[#v.pts]
		if v.kind == "air" then
			-- circle the scene slowly, nose toward it
			-- sway to and fro on the side it came in from (the side the camera sees)
			local arrivedFor = t - (v.arrivedAt or t)
			local swing = math.sin(arrivedFor * 0.15) * 0.5
			local r = 60
			p = Vector3.new(inc.pos.X + math.cos(v.orbit + swing) * r, p.Y + math.sin(t * 0.7 + v.phase) * 1.5, inc.pos.Z + math.sin(v.orbit + swing) * r)
			cf = faceFlat(p, inc.pos) * CFrame.Angles(math.rad(-4), 0, math.rad(6))
		else
			local want = faceFlat(p, v.target)
			local cur = v.yaw or root.CFrame
			cf = cur:Lerp(want, math.clamp(dt * 1.5, 0, 1))
			cf = CFrame.new(p) * cf.Rotation
			v.yaw = cf
		end
	else
		local s = v.s
		local p = sample(v, s)
		local ahead = sample(v, if v.state == "leaving" then s - 10 else s + 10)
		if (ahead - p).Magnitude < 0.05 then
			cf = CFrame.new(p) * root.CFrame.Rotation
		else
			local d = ahead - p
			if v.kind ~= "ground" then
				d = Vector3.new(d.X, if v.kind == "air" then d.Y * 0.3 else 0, d.Z)
			end
			cf = CFrame.lookAt(p, p + d)
			if v.kind == "air" and v.state ~= "waiting" then
				cf *= CFrame.Angles(math.rad(-8), 0, 0) -- nose down in forward flight
			end
		end
		v.yaw = nil
	end
	if v.kind == "boat" then
		-- bob on the swell
		local bob = math.sin(t * 1.3 + v.phase) * 0.5
		cf = (cf + Vector3.new(0, bob, 0)) * CFrame.Angles(math.sin(t * 0.9 + v.phase) * 0.03, 0, math.sin(t * 1.1 + v.phase) * 0.04)
	end
	root.CFrame = cf
	if v.hub then
		v.hub.CFrame = cf * CFrame.new(0, 5.6, 0) * CFrame.Angles(0, (t * 22) % (2 * math.pi), 0)
	end
	if v.spray then
		v.spray.Enabled = v.state == "arrived" and v.arrivedAt ~= nil and t - v.arrivedAt > 2 and t - v.arrivedAt < 60
	end
end

function EmergencyController:stepRafts(inc: any, dt: number)
	local t = inc.t
	local _ = dt
	for _, r in inc.rafts do
		if r.state == "done" then
			continue
		end
		local root = r.model.PrimaryPart :: BasePart
		if r.state == "waiting" then
			local tv = r.target
			if tv and tv.state == "arrived" then
				r.state = "moving"
				r.from = r.pos
				local side = (r.pos - tv.root.Position)
				side = Vector3.new(side.X, 0, side.Z)
				local off = if side.Magnitude > 0.1 then side.Unit * (if tv.role == "ferry" then 20 else 8) else Vector3.zero
				r.to = Vector3.new(tv.root.Position.X, SEA, tv.root.Position.Z) + off
				r.t0 = t
			end
		end
		if r.state == "moving" and r.from and r.to then
			local f = math.clamp((t - r.t0) / Rescue.RAFT_TRANSFER_S, 0, 1)
			r.pos = r.from:Lerp(r.to, f * f * (3 - 2 * f))
			if f >= 1 then
				r.state = "done"
				r.model:Destroy()
				inc.rescued += r.share
				if inc.mine then
					if inc.rescued >= inc.passengers then
						self.notify(string.format("Everyone is safe: all %d passengers rescued!", inc.passengers))
					else
						self.notify(string.format("Rescued %d of %d passengers", inc.rescued, inc.passengers))
					end
				end
				continue
			end
		end
		local bob = math.sin(t * 1.6 + r.phase) * 0.4
		root.CFrame = CFrame.new(r.pos + Vector3.new(0, bob, 0)) * CFrame.Angles(math.sin(t + r.phase) * 0.05, t * 0.1 + r.phase, 0)
	end
	if inc.raftsOut and not inc.leaveAt then
		local all = #inc.rafts > 0
		for _, r in inc.rafts do
			if r.state ~= "done" then
				all = false
			end
		end
		if all then
			inc.leaveAt = t + 10 -- everyone aboard: head home
		end
	end
end

function EmergencyController:stepIncident(inc: any, dt: number)
	inc.t += dt
	if inc.situation == Rescue.DITCH and not inc.raftsOut and inc.t >= Rescue.RAFT_OUT_S then
		self:launchRafts(inc)
	end
	for _, v in inc.vehicles do
		self:stepVehicle(inc, v, dt)
	end
	if #inc.rafts > 0 then
		self:stepRafts(inc, dt)
	end
	if inc.leaveAt and inc.t >= inc.leaveAt and not inc.done then
		inc.done = true
		for _, v in inc.vehicles do
			if v.state ~= "gone" then
				v.state = "leaving"
				if v.kind == "air" then
					-- fly back out from wherever the orbit has got to
					v.pts = { v.pts[1], v.root.Position }
					v.cum, v.total = buildPath(v.pts)
					v.s = v.total
				end
			end
		end
	end
end

function EmergencyController:update(dt: number)
	self.time += dt
	local on = math.floor(self.time * 4) % 2
	for id, inc in self.incidents do
		if inc.t > MAX_AGE or not inc.folder.Parent then
			self:clear(id)
			continue
		end
		self:stepIncident(inc, dt)
		for _, v in inc.vehicles do
			if v.state == "gone" then
				continue
			end
			for _, p in v.flash do
				local lit = (on + ((p:GetAttribute("Phase") :: number?) or 0)) % 2 == 0
				p.Color = if lit then FLASH_COLORS[p:GetAttribute("Flash") :: string] or FLASH_COLORS.white else FLASH_OFF
				local l = p:FindFirstChildOfClass("PointLight")
				if l then
					l.Enabled = lit
					l.Color = p.Color
				end
			end
		end
	end
end

return EmergencyController
