--!strict
-- BeamNG-style vertex dents on the client, using EditableMesh.
--
-- When a part gets dented, it can be swapped (on this client only) for a subdivided mesh
-- of the same shape built with AssetService:CreateEditableMesh. Vertices near the hit
-- are pushed in, so panels bow and crease instead of just moving as a block.
--
-- Why client-only: EditableMesh does not replicate, so the server broadcasts each dent
-- (DentFx) and every client deforms its own skins. Physics never uses the skins; the
-- original part stays (hidden locally with LocalTransparencyModifier) for collisions.
--
-- Fallback: if the Mesh/Image APIs are off for the experience, creation fails once and
-- the module switches itself off. Part dents and beam bending (server) still work.
-- Memory: at most GameConfig.crash.meshSkins.maxSkins skins live at once; the oldest
-- reverts to the plain part when a new one is needed.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crash = require(Shared.Crash)
local SoftBody = require(Shared.SoftBody)
local GameConfig = require(Shared.GameConfig)
local Registry = require(Shared.AircraftRegistry)
local Units = require(Shared.Units)

local S = Units.STUDS_PER_METER
local CFG = GameConfig.crash.meshSkins

local MeshSkins = {}

type Skin = {
	part: BasePart,
	meshPart: MeshPart,
	em: any, -- EditableMesh
	ids: { number },
	verts: { SoftBody.Vec },
	rest: { SoftBody.Vec },
	conn: RBXScriptConnection?,
}

local disabled = not CFG.enabled
local warned = false
local skins: { [BasePart]: Skin } = {}
local order: { BasePart } = {}
local pending: { [BasePart]: boolean } = {}
local seed = 0

local function off(why: string)
	disabled = true
	if not warned then
		warned = true
		warn("[MeshSkins] off, using part dents only: " .. why)
	end
end

-- Which grid shape matches a part, or nil if it can't be skinned.
function MeshSkins.shapeOf(part: BasePart): string?
	if part:IsA("WedgePart") then
		return "wedge"
	elseif part:IsA("Part") then
		local sm = part:FindFirstChildOfClass("SpecialMesh")
		if sm then
			if sm.MeshType == Enum.MeshType.Sphere then
				return "ellipsoid"
			elseif sm.MeshType == Enum.MeshType.Cylinder then
				return "cylinderX"
			elseif sm.MeshType == Enum.MeshType.Brick then
				return "box"
			end
			return nil
		end
		if part.Shape == Enum.PartType.Block then
			return "box"
		elseif part.Shape == Enum.PartType.Cylinder then
			return "cylinderX"
		elseif part.Shape == Enum.PartType.Ball then
			return "ellipsoid"
		end
	end
	return nil
end

local function release(part: BasePart)
	local s = skins[part]
	if not s then
		return
	end
	skins[part] = nil
	local i = table.find(order, part)
	if i then
		table.remove(order, i)
	end
	if s.conn then
		s.conn:Disconnect()
	end
	local ltm = s.meshPart.LocalTransparencyModifier
	pcall(function()
		s.meshPart:Destroy()
		s.em:Destroy()
	end)
	if part.Parent then
		-- hand visibility back to the part (it stays hidden if the skin was hidden, e.g. a
		-- nose panel in the cockpit view)
		part.LocalTransparencyModifier = ltm
	end
end

local function create(part: BasePart, shape: string): Skin?
	local size = part.Size
	local g = SoftBody.grid(shape, { size.X, size.Y, size.Z }, CFG.grid)
	local okEm, em = pcall(function()
		return (AssetService :: any):CreateEditableMesh()
	end)
	if not okEm or not em then
		off(tostring(em))
		return nil
	end
	local ids: { number } = {}
	local okBuild, err = pcall(function()
		for i, v in g.verts do
			ids[i] = em:AddVertex(Vector3.new(v[1], v[2], v[3]))
		end
		for _, t in g.tris do
			em:AddTriangle(ids[t[1]], ids[t[2]], ids[t[3]])
		end
	end)
	if not okBuild then
		pcall(function()
			em:Destroy()
		end)
		off(tostring(err))
		return nil
	end
	local okMp, mp = pcall(function()
		return (AssetService :: any):CreateMeshPartAsync((Content :: any).fromObject(em), { CollisionFidelity = Enum.CollisionFidelity.Box })
	end)
	if not okMp or not mp or not part.Parent then
		pcall(function()
			em:Destroy()
		end)
		if not okMp then
			off(tostring(mp))
		end
		return nil
	end
	local meshPart = mp :: MeshPart
	meshPart.Name = "DentSkin"
	meshPart.Size = size
	meshPart.CFrame = part.CFrame
	meshPart.Color = part.Color
	meshPart.Material = part.Material
	meshPart.Reflectance = part.Reflectance
	meshPart.Transparency = part.Transparency
	meshPart.Anchored = false
	meshPart.CanCollide = false
	meshPart.CanTouch = false
	meshPart.CanQuery = false
	meshPart.Massless = true
	pcall(function()
		(meshPart :: any).DoubleSided = true -- in case the winding is backwards
	end)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part
	w.Part1 = meshPart
	w.Parent = meshPart
	-- The skin stands in for the part, cockpit view included: a dented nose panel must
	-- still vanish in the cockpit or it blocks the windscreen.
	if part:GetAttribute("HideInCockpit") then
		meshPart:SetAttribute("HideInCockpit", true)
	end
	meshPart.LocalTransparencyModifier = part.LocalTransparencyModifier
	meshPart.Parent = part
	part.LocalTransparencyModifier = 1
	local rest = {}
	for i, v in g.verts do
		rest[i] = { v[1], v[2], v[3] }
	end
	local s: Skin = { part = part, meshPart = meshPart, em = em, ids = ids, verts = g.verts, rest = rest, conn = nil }
	s.conn = part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			release(part)
		end
	end)
	skins[part] = s
	table.insert(order, part)
	while #order > CFG.maxSkins do
		release(order[1])
	end
	return s
end

local function deform(s: Skin, worldPoint: Vector3, worldDir: Vector3, depth: number, radius: number)
	local part = s.part
	local lp = part.CFrame:PointToObjectSpace(worldPoint)
	local ld = part.CFrame:VectorToObjectSpace(worldDir)
	local size = part.Size
	local maxOff = CFG.maxOffsetFrac * math.min(size.X, size.Y, size.Z) + depth * 0.25
	seed += 1
	local moved = SoftBody.dentVertices(s.verts, s.rest, { lp.X, lp.Y, lp.Z }, { ld.X, ld.Y, ld.Z }, depth, radius, maxOff, seed)
	pcall(function()
		for i, nv in moved do
			s.verts[i] = nv
			s.em:SetPosition(s.ids[i], Vector3.new(nv[1], nv[2], nv[3]))
		end
	end)
	s.meshPart.Color = part.Color -- the server darkens dented parts
end

-- DentFx handler. Point/dir in body metres/axes of `model`, depth in metres.
function MeshSkins.onDent(model: Model, compName: string, pointM: Vector3, dirBody: Vector3, depthM: number)
	if disabled then
		return
	end
	local core = model.PrimaryPart
	local compModel = model:FindFirstChild(compName)
	local cfg = Registry.get(model:GetAttribute("AircraftId") :: string)
	if not core or not compModel or not cfg or not cfg.components[compName] then
		return
	end
	local prof = Crash.profiles(cfg)[compName]
	local worldPoint = core.CFrame:PointToWorldSpace(pointM * S)
	local worldDir = core.CFrame:VectorToWorldSpace(dirBody)
	local radius = prof.dentRadius * S * CFG.radiusScale
	local depth = depthM * S
	local cands: { { part: BasePart, d: number } } = {}
	for _, d in compModel:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "Root" and d.Name ~= "DentSkin" then
			local dist = (d.Position - worldPoint).Magnitude - d.Size.Magnitude * 0.5
			if dist < radius then
				table.insert(cands, { part = d, d = dist })
			end
		end
	end
	table.sort(cands, function(a: { part: BasePart, d: number }, b: { part: BasePart, d: number }): boolean
		return a.d < b.d
	end)
	local made = 0
	for i = 1, math.min(#cands, 8) do
		local part = cands[i].part
		local s = skins[part]
		if not s and made < CFG.newPerDent and not pending[part] then
			local shape = MeshSkins.shapeOf(part)
			if shape then
				made += 1
				pending[part] = true
				local ok, res = pcall(create, part, shape)
				pending[part] = nil
				s = if ok then res else nil
				if disabled then
					return
				end
			end
		end
		if s then
			deform(s, worldPoint, worldDir, depth, radius)
		end
	end
end

function MeshSkins.count(): number
	return #order
end

function MeshSkins.isEnabled(): boolean
	return not disabled
end

return MeshSkins
