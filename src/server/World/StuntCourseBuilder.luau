--!strict
-- Builds the Stunts ring course (Shared.Stunts) as floating neon rings with big numbers.
-- Rings are scenery only: no collisions, no touch events and no raycast hits, so they
-- never dent an aircraft or fool a ground-height check. Each client recolours them for
-- its own race (next ring bright, passed rings faded); see client/StuntsHud.luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Stunts = require(Shared.Stunts)
local Units = require(Shared.Units)

local StuntCourseBuilder = {}

local SPM = Units.STUDS_PER_METER
StuntCourseBuilder.SEGMENTS = 20
StuntCourseBuilder.TUBE_M = 2.2 -- ring tube thickness
StuntCourseBuilder.DEPTH_M = 1.6 -- ring depth along the flight path

local RING_COLOR = Color3.fromRGB(255, 140, 30)

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end

-- One ring as a Model named "Ring<i>" with attribute RingIndex. Returns (model, parts).
function StuntCourseBuilder.buildRing(r: any, parent: Instance): (Model, number)
	local model = Instance.new("Model")
	model.Name = `Ring{r.index}`
	model:SetAttribute("RingIndex", r.index)
	local center = Vector3.new(r.x, r.y, r.z)
	local n = Vector3.new(r.nx, r.ny, r.nz)
	-- ring frame: LookVector = flight direction; the ring lies in its Right/Up plane
	local upHint = if math.abs(n.Y) > 0.95 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local frame = CFrame.lookAt(center, center + n, upHint)
	local right, up = frame.RightVector, frame.UpVector
	local tube = StuntCourseBuilder.TUBE_M * SPM
	local depth = StuntCourseBuilder.DEPTH_M * SPM
	local rMid = Stunts.RING_RADIUS_M * SPM + tube / 2
	local segs = StuntCourseBuilder.SEGMENTS
	-- segment length covers the outer edge so neighbours overlap with no gaps
	local segLen = 2 * (rMid + tube / 2) * math.tan(math.pi / segs) + 0.2
	local count = 0
	for k = 0, segs - 1 do
		local a = (k + 0.5) / segs * 2 * math.pi
		local radial = right * math.cos(a) + up * math.sin(a)
		local tangent = -right * math.sin(a) + up * math.cos(a)
		local pos = center + radial * rMid
		local cf = CFrame.fromMatrix(pos, radial, tangent, -n)
		part("Segment", Vector3.new(tube, segLen, depth), cf, RING_COLOR, model)
		count += 1
	end
	-- the ring number, floating above the top of the ring
	local anchor = part("Label", Vector3.new(1, 1, 1), CFrame.new(center + Vector3.new(0, rMid + tube * 2, 0)), RING_COLOR, model)
	anchor.Transparency = 1
	local bb = Instance.new("BillboardGui")
	bb.Name = "Number"
	bb.Size = UDim2.fromOffset(120, 60)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 2500
	bb.LightInfluence = 0
	bb.Parent = anchor
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextStrokeTransparency = 0.2
	text.Text = if r.index == 1 then "START" elseif r.index == #Stunts.course() then "FINISH" else tostring(r.index)
	text.Parent = bb
	count += 1
	model.Parent = parent
	return model, count
end

-- Build the whole course under `parent` (a Folder named "StuntCourse"). Returns the folder
-- and the part count.
function StuntCourseBuilder.build(parent: Instance): (Folder, number)
	local folder = Instance.new("Folder")
	folder.Name = "StuntCourse"
	local count = 0
	for _, r in Stunts.course() do
		local _, n = StuntCourseBuilder.buildRing(r, folder)
		count += n
	end
	folder.Parent = parent
	return folder, count
end

return StuntCourseBuilder
