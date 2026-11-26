--!strict
-- Server half of the crash system (pure maths lives in Shared/Crash):
--   * dents:     ReportImpact -> crumple the parts near the contact point (replicates).
--   * sections:  ReportSection -> tear a break-point section off a component as debris
--                that keeps the aircraft's momentum.
--   * breakup:   tracked debris splits again on hard secondary impacts, within budgets.
--   * effects:   CrashFx broadcasts sparks/shards so everyone sees them.
--
-- Rewelding: a dented part's WeldConstraints are removed, the part is moved, and new
-- WeldConstraints are made to the same partners. Nothing else in the assembly moves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crash = require(Shared.Crash)
local SoftBody = require(Shared.SoftBody)
local Damage = require(Shared.Damage)
local GameConfig = require(Shared.GameConfig)
local Registry = require(Shared.AircraftRegistry)
local Units = require(Shared.Units)

local S = Units.STUDS_PER_METER
local MPS = Units.METERS_PER_STUD
local CC = GameConfig.crash

local CrashService = {}

export type Hooks = {
	remotes: Folder,
	debrisFolder: Folder,
	getAircraft: (Player) -> Model?,
	registerDebris: (Player, Model) -> (),
	maxRecentSpeed: (Player, number) -> number, -- m/s
}

local hooks: Hooks
local crumpleBudget: { [Player]: number } = {}
local splitBudget = 0

type Piece = {
	model: Model,
	owner: Player,
	profile: Crash.Profile,
	state: Crash.PieceState,
	lastV: Vector3?,
	lastFx: number,
	born: number,
}
local pieces: { [Model]: Piece } = {}

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function finiteV(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

local function fx(kind: string, pos: Vector3, intensity: number, vel: Vector3?, except: Player?)
	local r = hooks.remotes:FindFirstChild("CrashFx") :: RemoteEvent?
	if not r then
		return
	end
	for _, pl in Players:GetPlayers() do
		if pl ~= except then
			r:FireClient(pl, kind, pos, intensity, vel)
		end
	end
end

-- Parts of a component that can dent or tear: visible, welded, not the joint root/seat.
local function componentParts(compModel: Instance): { BasePart }
	local out = {}
	for _, d in compModel:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" and not d:IsA("Seat") and not d:IsA("VehicleSeat") and d.Transparency < 1 then
			table.insert(out, d)
		end
	end
	return out
end

-- Move one welded part to `newCF`, keeping it welded to the same partners.
local function reweldTo(part: BasePart, newCF: CFrame): boolean
	-- A part driven by a Motor6D/Weld (gear leg, control surface) stays joined to the
	-- aircraft after its welds go, and moving it would move the whole aircraft. Skip it.
	for _, j in part:GetJoints() do
		if j:IsA("JointInstance") and j.Part1 == part then
			return false
		end
	end
	local partners = {}
	for _, j in part:GetJoints() do
		if j:IsA("WeldConstraint") then
			local other = if j.Part0 == part then j.Part1 else j.Part0
			if other then
				table.insert(partners, other)
			end
			j:Destroy()
		end
	end
	if #partners == 0 then
		return false
	end
	part.CFrame = newCF
	for _, other in partners do
		local w = Instance.new("WeldConstraint")
		w.Name = "Weld"
		w.Part0 = other
		w.Part1 = part
		w.Parent = part
	end
	return true
end

-- Dents -------------------------------------------------------------------------------
function CrashService.crumple(model: Model, cfg: any, compName: string, pointM: Vector3, dirBody: Vector3, dv: number): number
	local core = model.PrimaryPart
	local compModel = model:FindFirstChild(compName)
	if not core or not compModel then
		return 0
	end
	local profile = Crash.profiles(cfg)[compName]
	local depth = Crash.dentDepth(profile, dv)
	if depth <= 0 then
		return 0
	end
	local coreCF = core.CFrame
	local list: { Crash.CrumplePart } = {}
	local byId: { [number]: BasePart } = {}
	for i, p in componentParts(compModel) do
		local lp = coreCF:PointToObjectSpace(p.Position) * MPS
		byId[i] = p
		table.insert(list, { id = i, pos = { lp.X, lp.Y, lp.Z }, dent = (p:GetAttribute("DentM") :: number?) or 0 })
	end
	local seed = math.floor(os.clock() * 1000) % 100000 + #list
	local moves = Crash.crumple(profile, list, { pointM.X, pointM.Y, pointM.Z }, { dirBody.X, dirBody.Y, dirBody.Z }, depth, seed)
	local dark = Color3.fromRGB(64, 64, 70)
	for _, m in moves do
		local part = byId[m.id]
		local offsetW = coreCF:VectorToWorldSpace(v3(m.offset) * S)
		local newCF = (part.CFrame + offsetW) * CFrame.Angles(m.twist[1], m.twist[2], m.twist[3])
		if reweldTo(part, newCF) then
			local amount = v3(m.offset).Magnitude
			part:SetAttribute("DentM", ((part:GetAttribute("DentM") :: number?) or 0) + amount)
			part.Color = part.Color:Lerp(dark, CC.scuffDarken * m.weight * math.min(1, amount / profile.maxDent))
		end
	end
	return #moves
end

-- Bending -----------------------------------------------------------------------------
-- Bends a wing/tail/nose like a beam (see Shared/SoftBody). Control surfaces hang off an
-- invisible Mount -> Motor6D -> Hinge; moving the Mount carries the surface with it, so
-- Hinge parts and the parts welded to them "ride" instead of being moved directly.
function CrashService.bend(model: Model, cfg: any, compName: string, pointM: Vector3, dirBody: Vector3, dv: number, toughness: number?): number
	local core = model.PrimaryPart
	local compModel = model:FindFirstChild(compName)
	if not core or not compModel then
		return 0
	end
	local kind = Crash.kind(compName)
	local bp = SoftBody.bendProfile(cfg, compName, kind)
	local point = { pointM.X, pointM.Y, pointM.Z }
	local axis = SoftBody.beamAxis(cfg, compName, kind, point)
	if not bp or not axis then
		return 0
	end
	local tough = toughness or 1
	if tough ~= 1 then
		local t: any = table.clone(bp :: any)
		t.bendThreshold *= tough
		bp = t
	end
	local driven: { [BasePart]: boolean } = {}
	for _, d in compModel:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 then
			driven[d.Part1 :: BasePart] = true
		end
	end
	local parts: { BasePart } = {}
	local list: { SoftBody.BendPart } = {}
	local isRider: { [BasePart]: boolean } = {}
	local coreCF = core.CFrame
	for _, d in compModel:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" and not d:IsA("Seat") and not d:IsA("VehicleSeat") then
			local rider = driven[d] == true
			if not rider then
				for _, j in d:GetJoints() do
					if j:IsA("WeldConstraint") then
						local other = if j.Part0 == d then j.Part1 else j.Part0
						if other and driven[other :: BasePart] then
							rider = true
							break
						end
					end
				end
			end
			table.insert(parts, d)
			isRider[d] = rider
			local lp = coreCF:PointToObjectSpace(d.Position) * MPS
			table.insert(list, { id = #parts, pos = { lp.X, lp.Y, lp.Z } })
		end
	end
	local already = {
		bentDeg = (model:GetAttribute("BendDeg_" .. compName) :: number?) or 0,
		crushed = (model:GetAttribute("CrushM_" .. compName) :: number?) or 0,
	}
	local res = SoftBody.bend(bp, list, axis, point, { dirBody.X, dirBody.Y, dirBody.Z }, dv, already)
	if #res.moves == 0 then
		return 0
	end
	model:SetAttribute("BendDeg_" .. compName, already.bentDeg + res.bentDeg)
	model:SetAttribute("CrushM_" .. compName, already.crushed + res.crushed)
	-- Targets from the original poses, then movers first, riders checked afterwards.
	local targets: { [BasePart]: CFrame } = {}
	for _, mv in res.moves do
		local part = parts[mv.id]
		local pivotW = coreCF:PointToWorldSpace(v3(mv.pivot) * S)
		local rotW = coreCF:VectorToWorldSpace(v3(mv.rotation))
		local angle = rotW.Magnitude
		local r = if angle > 1e-6 then CFrame.fromAxisAngle(rotW / angle, angle) else CFrame.identity
		local tW = coreCF:VectorToWorldSpace(v3(mv.translate) * S)
		targets[part] = (CFrame.new(pivotW) * r * CFrame.new(-pivotW) * part.CFrame) + tW
	end
	local moved = 0
	for part, cf in targets do
		if not isRider[part] and reweldTo(part, cf) then
			moved += 1
		end
	end
	for part, cf in targets do
		if isRider[part] and (part.Position - cf.Position).Magnitude > 0.05 then
			reweldTo(part, cf)
		end
	end
	return moved
end

-- Collapse ------------------------------------------------------------------------------
-- With break-apart off, a component whose health runs out stays on and collapses: wings
-- and tailplanes droop from the root, the fin leans over, and a wrecked centre fuselage
-- breaks its back (nose and tail sag). Each component collapses once.
local function rootPoint(model: Model, compName: string, axis: SoftBody.Vec, zone: number): Vector3?
	local core = model.PrimaryPart
	local compModel = model:FindFirstChild(compName)
	if not core or not compModel then
		return nil
	end
	local a = v3(axis)
	local sMin, best = math.huge, nil
	for _, d in compModel:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" then
			local lp = core.CFrame:PointToObjectSpace(d.Position) * MPS
			local sv = lp:Dot(a)
			if sv < sMin then
				sMin, best = sv, lp
			end
		end
	end
	if not best then
		return nil
	end
	return best + a * zone
end

function CrashService.collapse(model: Model, cfg: any, compName: string)
	local key = "Collapsed_" .. compName
	if model:GetAttribute(key) then
		return
	end
	model:SetAttribute(key, true)
	local kind = Crash.kind(compName)
	if compName == "Fuselage" then
		for _, sec in { "ForwardFuselage", "AftFuselage" } do
			if cfg.components[sec] and model:GetAttribute("Dmg_" .. sec) ~= "detached" then
				local bp = SoftBody.bendProfile(cfg, sec, "fuselage")
				local axis = SoftBody.beamAxis(cfg, sec, "fuselage", { 0, 0, 0 })
				if bp and axis then
					local pt = rootPoint(model, sec, axis, bp.bendZone * 0.5)
					if pt then
						CrashService.bend(model, cfg, sec, pt, Vector3.new(0, -1, 0), bp.bendThreshold + 12 / bp.bendPerMps)
					end
				end
			end
		end
		return
	end
	local bp = SoftBody.bendProfile(cfg, compName, kind)
	local ref = cfg.components[compName].ref or { 0, 0, 0 }
	local axis = SoftBody.beamAxis(cfg, compName, kind, ref)
	if not bp or not axis then
		return
	end
	local pt = rootPoint(model, compName, axis, bp.bendZone)
	if not pt then
		return
	end
	local dir = if axis[2] > 0.5 then Vector3.new(if math.random() < 0.5 then -1 else 1, 0, 0) else Vector3.new(0, -1, 0)
	CrashService.bend(model, cfg, compName, pt, dir, bp.bendThreshold + 25 / bp.bendPerMps)
end

-- Debris tracking -----------------------------------------------------------------------
function CrashService.track(owner: Player, debris: Model, profile: Crash.Profile, integrity: number?)
	local count = 0
	for _, d in debris:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	pieces[debris] = {
		model = debris, owner = owner, profile = profile,
		state = { integrity = integrity or profile.integrity, parts = count },
		lastV = nil, lastFx = 0, born = os.clock(),
	}
end

-- Give a freshly separated assembly the velocity it had as part of the parent at that
-- point, plus a push away from the break (m/s).
local function inherit(anchor: BasePart, v: Vector3, w: Vector3, origin: Vector3, away: Vector3, pushMps: number)
	local r = anchor.Position - origin
	local nv = Crash.inheritVelocity({ v.X, v.Y, v.Z }, { w.X, w.Y, w.Z }, { r.X, r.Y, r.Z }, { away.X, away.Y, away.Z }, pushMps * S)
	local vel = v3(nv)
	if finiteV(vel) then
		anchor.AssemblyLinearVelocity = vel
		anchor.AssemblyAngularVelocity = w + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.5
	end
end

local function prepareDebrisPart(part: BasePart, ownerId: number)
	if part.CanCollide then
		part.Massless = false
	end
	part.CollisionGroup = GameConfig.CollisionGroups.Debris
	part:SetAttribute("DebrisOwner", ownerId)
end

-- Move `group` into a new debris model welded to one anchor. Joints from the group to
-- parts outside it are destroyed. Returns the model (unparented) and its anchor.
local function carve(group: { BasePart }, name: string, ownerId: number): (Model, BasePart)
	local inGroup: { [BasePart]: boolean } = {}
	local anchor = group[1]
	local best = -1
	for _, p in group do
		inGroup[p] = true
		local vol = p.Size.X * p.Size.Y * p.Size.Z
		if p.CanCollide and vol > best then
			anchor, best = p, vol
		end
	end
	for _, p in group do
		for _, j in p:GetJoints() do
			local a: Instance? = nil
			local b: Instance? = nil
			if j:IsA("WeldConstraint") then
				a, b = j.Part0, j.Part1
			elseif j:IsA("JointInstance") then
				a, b = j.Part0, j.Part1
			else
				continue
			end
			local other = if a == p then b else a
			if other and not inGroup[other :: BasePart] then
				j:Destroy()
			end
		end
	end
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("DebrisOwner", ownerId)
	for _, p in group do
		p.Parent = m
		prepareDebrisPart(p, ownerId)
		if p ~= anchor then
			local linked = false
			for _, j in p:GetJoints() do
				if j:IsA("WeldConstraint") or j:IsA("JointInstance") then
					linked = true
					break
				end
			end
			if not linked then
				local w = Instance.new("WeldConstraint")
				w.Name = "Weld"
				w.Part0 = anchor
				w.Part1 = p
				w.Parent = p
			end
		end
	end
	m.PrimaryPart = anchor
	return m, anchor
end

-- Break points ----------------------------------------------------------------------------
function CrashService.breakSection(p: Player, model: Model, cfg: any, compName: string, section: Crash.Section): Model?
	local core = model.PrimaryPart
	local compModel = model:FindFirstChild(compName)
	if not core or not compModel then
		return nil
	end
	local coreCF = core.CFrame
	local list: { Crash.CrumplePart } = {}
	local byId: { [number]: BasePart } = {}
	for i, part in componentParts(compModel) do
		local lp = coreCF:PointToObjectSpace(part.Position) * MPS
		byId[i] = part
		table.insert(list, { id = i, pos = { lp.X, lp.Y, lp.Z } })
	end
	local insideIds = Crash.partition(section, list)
	if #insideIds == 0 then
		return nil
	end
	local group: { BasePart } = {}
	local seen: { [BasePart]: boolean } = {}
	for _, id in insideIds do
		local part = byId[id]
		seen[part] = true
		table.insert(group, part)
	end
	-- Control surfaces hinge on a panel; they go with their panel.
	for _, part in componentParts(compModel) do
		if not seen[part] then
			for _, j in part:GetJoints() do
				if j:IsA("Motor6D") and j.Part0 and seen[j.Part0 :: BasePart] then
					seen[part] = true
					table.insert(group, part)
					break
				end
			end
		end
	end
	local v, w = core.AssemblyLinearVelocity, core.AssemblyAngularVelocity
	local origin = core.Position
	local debris, anchor = carve(group, `Debris_{p.UserId}_{compName}_{section.id}`, p.UserId)
	debris.Parent = hooks.debrisFolder
	pcall(function()
		anchor:SetNetworkOwner(nil)
	end)
	inherit(anchor, v, w, origin, coreCF:VectorToWorldSpace(v3(section.normal)), 2.5)
	hooks.registerDebris(p, debris)
	CrashService.track(p, debris, Crash.profiles(cfg)[compName])
	fx("shards", anchor.Position, 1.5, anchor.AssemblyLinearVelocity, p)
	fx("sparks", anchor.Position, 2, nil, p)
	return debris
end

-- Secondary breakup ----------------------------------------------------------------------
local function split(piece: Piece): boolean
	local model = piece.model
	local anchor = model.PrimaryPart
	if not anchor or model:FindFirstChild("PilotSeat", true) then
		return false
	end
	local parts: { BasePart } = {}
	local list: { Crash.CrumplePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			local lp = anchor.CFrame:PointToObjectSpace(d.Position) * MPS
			table.insert(list, { id = #parts, pos = { lp.X, lp.Y, lp.Z } })
		end
	end
	local n, off = Crash.splitPlane(list)
	if not n or not off then
		return false
	end
	local section: Crash.Section = { id = "split", normal = n, offset = off, lost = 0 }
	local insideIds, restIds = Crash.partition(section, list)
	if #insideIds == 0 or #restIds == 0 then
		return false
	end
	-- Keep the current anchor on the side that stays in this model.
	local anchorInside = false
	for _, id in insideIds do
		if parts[id] == anchor then
			anchorInside = true
			break
		end
	end
	if anchorInside then
		insideIds, restIds = restIds, insideIds
	end
	local group: { BasePart } = {}
	for _, id in insideIds do
		table.insert(group, parts[id])
	end
	local v, w = anchor.AssemblyLinearVelocity, anchor.AssemblyAngularVelocity
	local origin = anchor.Position
	local normalW = anchor.CFrame:VectorToWorldSpace(v3(n))
	if anchorInside then
		normalW = -normalW
	end
	-- Re-link the parts that stay, in case some hung off a part that just left.
	local rest: { BasePart } = {}
	for _, id in restIds do
		table.insert(rest, parts[id])
	end
	local newModel, newAnchor = carve(group, model.Name .. "_b", piece.owner.UserId)
	for _, p in rest do
		if p ~= anchor then
			local linked = false
			for _, j in p:GetJoints() do
				if j:IsA("WeldConstraint") or j:IsA("JointInstance") then
					linked = true
					break
				end
			end
			if not linked then
				local wc = Instance.new("WeldConstraint")
				wc.Name = "Weld"
				wc.Part0 = anchor
				wc.Part1 = p
				wc.Parent = p
			end
		end
	end
	newModel.Parent = hooks.debrisFolder
	pcall(function()
		newAnchor:SetNetworkOwner(nil)
	end)
	inherit(newAnchor, v, w, origin, normalW, CC.splitPush * 0.5)
	inherit(anchor, v, w, origin, -normalW, CC.splitPush * 0.5)
	piece.state.parts = #rest
	hooks.registerDebris(piece.owner, newModel)
	CrashService.track(piece.owner, newModel, piece.profile, piece.state.integrity)
	return true
end

local function stepPieces(dt: number)
	splitBudget = math.min(CC.maxSplitsPerSecond, splitBudget + CC.maxSplitsPerSecond * dt)
	for p, b in crumpleBudget do
		crumpleBudget[p] = math.min(CC.maxCrumplesPerSecond, b + CC.maxCrumplesPerSecond * dt)
	end
	local now = os.clock()
	for model, piece in pieces do
		local anchor = model.PrimaryPart
		if not model.Parent or not anchor then
			pieces[model] = nil
			continue
		end
		local v = anchor.AssemblyLinearVelocity
		local last = piece.lastV
		piece.lastV = v
		if not last or now - piece.born < 0.25 then
			continue -- let it clear the aircraft first
		end
		-- Velocity change the engine's gravity doesn't explain = an impact.
		local dvStuds = (v - last) - Vector3.new(0, -Units.GRAVITY_STUDS * dt, 0)
		local dv = dvStuds.Magnitude * MPS
		if dv > 6 and now - piece.lastFx > 0.25 then
			piece.lastFx = now
			fx("sparks", anchor.Position, math.clamp(dv / 8, 0.5, 3), nil, nil)
			if dv > 10 then
				fx("shards", anchor.Position, math.clamp(dv / 12, 0.5, 2), v * 0.4, nil)
			end
		end
		if splitBudget >= 1 and Crash.secondaryBreak(piece.profile, piece.state, dv) then
			if split(piece) then
				splitBudget -= 1
			else
				piece.state.integrity = 0
			end
		end
	end
end

-- Remotes -----------------------------------------------------------------------------
local function validAircraft(p: Player, model: any, compName: any): (Model?, any)
	if typeof(model) ~= "Instance" or model ~= hooks.getAircraft(p) or type(compName) ~= "string" then
		return nil, nil
	end
	local m = model :: Model
	local cfg = Registry.get(m:GetAttribute("AircraftId") :: string)
	if not cfg or not cfg.components[compName] then
		return nil, nil
	end
	if m:GetAttribute("Dmg_" .. compName) == "detached" then
		return nil, nil
	end
	if Crash.justRepaired(m:GetAttribute("RepairedAt"), os.clock()) then
		return nil, nil -- about parts that Fix all just replaced
	end
	return m, cfg
end

local function plausibleDv(p: Player, dv: any): number?
	if type(dv) ~= "number" or dv ~= dv or dv < 0 then
		return nil
	end
	local seen = hooks.maxRecentSpeed(p, 3)
	return math.min(dv, seen * 1.6 + 12, 150)
end

local function onReportImpact(p: Player, model: any, compName: any, point: any, dir: any, dv: any)
	local m, cfg = validAircraft(p, model, compName)
	if not m or typeof(point) ~= "Vector3" or typeof(dir) ~= "Vector3" then
		return
	end
	if not finiteV(point) or point.Magnitude > 150 or not finiteV(dir) then
		return
	end
	local d = plausibleDv(p, dv)
	if not d then
		return
	end
	local budget = crumpleBudget[p] or CC.maxCrumplesPerSecond
	if budget < 1 then
		return
	end
	crumpleBudget[p] = budget - 1
	local unitDir = if dir.Magnitude > 1e-6 then dir.Unit else Vector3.zero
	local tough = Crash.crashToughness((m:GetAttribute("Toughness") :: number?) or 1)
	local moved = CrashService.crumple(m, cfg, compName, point, unitDir, d)
	moved += CrashService.bend(m, cfg, compName, point, unitDir, d, tough)
	if compName == "Fuselage" and math.abs(unitDir.Y) > 0.4 then
		-- A hard belly/roof hit on the centre bends the whole airframe: nose and tail sag
		-- (or lift) the opposite way to the push.
		for _, sec in { "ForwardFuselage", "AftFuselage" } do
			local secCfg = cfg.components[sec]
			if secCfg and m:GetAttribute("Dmg_" .. sec) ~= "detached" then
				moved += CrashService.bend(m, cfg, sec, v3(secCfg.ref or { 0, 0, 0 }), Vector3.new(0, -unitDir.Y, 0), d * 0.8, tough)
			end
		end
	end
	-- Every client dents its own mesh skins (EditableMesh doesn't replicate).
	local depth = Crash.dentDepth(Crash.profiles(cfg, tough)[compName], d)
	if depth > 0 then
		local r = hooks.remotes:FindFirstChild("DentFx") :: RemoteEvent?
		if r then
			r:FireAllClients(m, compName, point, unitDir, depth, d)
		end
	end
	if moved > 0 and d > 8 and m.PrimaryPart then
		local worldPos = m.PrimaryPart.CFrame:PointToWorldSpace(point * S)
		fx("sparks", worldPos, math.clamp(d / 8, 0.5, 3), nil, p)
	end
end

-- Sections torn by the HUD's Events button (failures, tornado debris) need no impact;
-- they're rate limited instead. It only ever affects the reporting player's own aircraft.
local lastEventSection: { [Player]: { tokens: number, t: number } } = {}

local function onReportSection(p: Player, model: any, compName: any, sectionId: any, dv: any, cause: any)
	local m, cfg = validAircraft(p, model, compName)
	if not m or type(sectionId) ~= "string" then
		return
	end
	local profile = Crash.profiles(cfg)[compName]
	local section = Crash.findSection(profile, sectionId)
	local key = `Section_{compName}_{sectionId}`
	if not section or m:GetAttribute(key) then
		return
	end
	if cause == "event" then
		-- token bucket: up to 4 at once, refilling one every half second
		local now = os.clock()
		local b = lastEventSection[p] or { tokens = 4, t = now }
		b.tokens = math.min(4, b.tokens + (now - b.t) * 2)
		b.t = now
		lastEventSection[p] = b
		if b.tokens < 1 then
			return
		end
		b.tokens -= 1
	else
		local d = plausibleDv(p, dv)
		-- A tear needs a real impact the server could have seen.
		if not d or d < profile.sectionBreakDv * 0.6 then
			return
		end
	end
	m:SetAttribute(key, true)
	CrashService.breakSection(p, m, cfg, compName, section)
end

function CrashService.init(h: Hooks)
	hooks = h
	;(h.remotes:FindFirstChild("ReportImpact") :: RemoteEvent).OnServerEvent:Connect(onReportImpact)
	;(h.remotes:FindFirstChild("ReportSection") :: RemoteEvent).OnServerEvent:Connect(onReportSection)
	RunService.Heartbeat:Connect(stepPieces)
	Players.PlayerRemoving:Connect(function(p)
		crumpleBudget[p] = nil
		lastEventSection[p] = nil
		for model, piece in pieces do
			if piece.owner == p then
				pieces[model] = nil
			end
		end
	end)
end

-- Fire -----------------------------------------------------------------------------------
-- A crashed part burns: flames, black smoke and an orange glow on its biggest visible
-- part, so the fire stays on the piece if it breaks off. Once per component, capped per
-- aircraft and across the game, and it dies down after a while. Fix all removes the
-- burnt parts, so their fires go with them.
local fires: { { t: number, items: { Instance } } } = {}

function CrashService.ignite(model: Model, compName: string, intensity: number?): boolean
	local FC = CC.fire
	local key = "OnFire_" .. compName
	local count = (model:GetAttribute("FireCount") :: number?) or 0
	if model:GetAttribute(key) or count >= FC.maxPerAircraft then
		return false
	end
	local comp = model:FindFirstChild(compName)
	if not comp then
		return false
	end
	local best: BasePart? = nil
	local bestVol = 0
	for _, d in comp:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" and d.Transparency < 0.9 and not d:IsA("Seat") then
			local vol = d.Size.X * d.Size.Y * d.Size.Z
			if vol > bestVol then
				best, bestVol = d, vol
			end
		end
	end
	if not best then
		return false
	end
	model:SetAttribute(key, true)
	model:SetAttribute("FireCount", count + 1)
	local size = math.clamp(bestVol ^ (1 / 3) * 0.9 * (intensity or 1), 4, 24)
	local fire = Instance.new("Fire")
	fire.Name = "CrashFire"
	fire.Size = size
	fire.Heat = math.clamp(size * 0.8, 6, 25)
	fire.Color = Color3.fromRGB(255, 150, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 70, 15)
	fire.Parent = best
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "CrashSmoke"
	smoke.Color = ColorSequence.new(Color3.fromRGB(45, 42, 40), Color3.fromRGB(110, 106, 100))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.4), NumberSequenceKeypoint.new(1, size * 1.6) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(4, 7)
	smoke.Speed = NumberRange.new(6, 12)
	smoke.Rate = 10
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.Acceleration = Vector3.new(1, 4, 0)
	smoke.Parent = best
	local glow = Instance.new("PointLight")
	glow.Name = "CrashGlow"
	glow.Color = Color3.fromRGB(255, 140, 50)
	glow.Range = math.clamp(size * 2, 10, 50)
	glow.Brightness = 3
	glow.Parent = best
	local rec = { t = os.clock(), items = { fire, smoke, glow } :: { Instance } }
	table.insert(fires, rec)
	while #fires > FC.maxTotal do
		local old = table.remove(fires, 1) :: any
		for _, it in old.items do
			it:Destroy()
		end
	end
	task.delay(FC.burnTime, function()
		fire.Enabled = false
		smoke.Enabled = false
		glow.Enabled = false
		task.delay(8, function()
			for _, it in rec.items do
				it:Destroy()
			end
			local i = table.find(fires, rec)
			if i then
				table.remove(fires, i)
			end
		end)
	end)
	return true
end

-- Does a part of this kind burn when it breaks? Engines, wings (fuel tanks) and the body.
function CrashService.burns(compName: string): boolean
	local kind = Crash.kind(compName)
	return kind == "engine" or kind == "wing" or kind == "fuselage"
end

-- Exposed for AircraftService when a whole component detaches.
CrashService.inherit = inherit
CrashService.fx = fx

-- Silence unused-import lint in strict mode: Damage is kept for future server-side checks.
local _ = Damage

return CrashService
