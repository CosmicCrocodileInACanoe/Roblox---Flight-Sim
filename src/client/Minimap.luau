--!strict
-- Round minimap (top right, under the Controls button): land and sea with hill shading,
-- cities, airports with their runways, your aircraft, other players' aircraft and the
-- destination airport. Zoom with the - / + buttons; the middle button switches between
-- "north up" and "plane up" (the map turns so your nose always points up).
--
-- The base map is drawn once from WorldGen's height field. It uses an EditableImage when
-- the engine allows one, and otherwise falls back to a coarse grid of Frames.
-- All world <-> map maths lives in Shared.MapMath (tested offline).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapMath = require(Shared.MapMath)
local WorldGen = require(Shared.WorldGen)
local Airports = require(Shared.Airports)
local Units = require(Shared.Units)

local Minimap = {}
Minimap.__index = Minimap

local SIZE = 200 -- map diameter (px, before UIScale)
local IMAGE_SIDE = 512 -- base image, longest side (px)
local FALLBACK_SIDE = 72 -- Frame grid fallback, longest side (cells)
local SCAN_INTERVAL = 0.1 -- other aircraft and destination pointer (s)

local PANEL = Color3.fromRGB(14, 18, 26)
local WHITE = Color3.fromRGB(255, 255, 255)
local INK = Color3.fromRGB(20, 26, 36)
local GOLD = Color3.fromRGB(255, 200, 40)
local ME = Color3.fromRGB(255, 226, 60)
local FRIEND = Color3.fromRGB(80, 230, 255)
local CITY = Color3.fromRGB(255, 150, 90)
local RUNWAY = Color3.fromRGB(60, 64, 72)
local ACCENT = Color3.fromRGB(40, 120, 220)
local FONT = Enum.Font.GothamBold

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

local function round(inst: Instance, r: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = r
	c.Parent = inst
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
end

-- Top-down aeroplane icon pointing up, drawn twice (dark outline, then colour).
local function planeIcon(parent: Instance, size: number, color: Color3, z: number): Frame
	local holder = make("Frame", {
		Parent = parent, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1, ZIndex = z,
	})
	local parts = {
		{ 0.5, 0.5, 0.2, 0.95 }, -- fuselage
		{ 0.5, 0.42, 0.96, 0.2 }, -- wings
		{ 0.5, 0.88, 0.48, 0.14 }, -- tailplane
	}
	for pass = 1, 2 do
		local pad = if pass == 1 then 3 else 0
		for _, p in parts do
			local f = make("Frame", {
				Parent = holder, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(p[1], p[2]),
				Size = UDim2.new(p[3], pad, p[4], pad), BackgroundColor3 = if pass == 1 then INK else color,
				BorderSizePixel = 0, ZIndex = z + pass - 1,
			})
			round(f, UDim.new(0.5, 0))
		end
	end
	return holder
end

local function tagLabel(parent: Instance, text: string, color: Color3, textSize: number, z: number): TextLabel
	return make("TextLabel", {
		Parent = parent, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, Text = text, Font = FONT,
		TextSize = textSize, TextColor3 = color, TextStrokeColor3 = INK, TextStrokeTransparency = 0.2, ZIndex = z,
	})
end

local function button(parent: Instance, text: string, pos: UDim2, size: UDim2): TextButton
	local b = make("TextButton", {
		Parent = parent, Position = pos, Size = size, BackgroundColor3 = PANEL, BackgroundTransparency = 0.15,
		Text = text, Font = Enum.Font.GothamBlack, TextColor3 = WHITE, TextSize = 18, AutoButtonColor = true,
	})
	round(b, UDim.new(0, 8))
	return b
end

function Minimap.new()
	local self = setmetatable({}, Minimap) :: any
	self.enabled = true
	self.flying = false
	self.mode = "north" -- "north" | "heading"
	self.zoom = MapMath.DEFAULT_ZOOM
	self.rotation = 0
	self.nextScan = 0
	self.others = {} :: { [Model]: any }
	self.counterRotate = {} :: { GuiObject } -- labels kept upright when the map turns
	self.sized = {} :: { (number) -> () } -- things whose pixel size depends on zoom

	-- World rectangle covered by the map, from the world data (adapts to a bigger world).
	local pts = {}
	for _, id in Airports.order do
		local l = Airports.layout(id)
		table.insert(pts, { x = l.cx, z = l.cz, r = l.halfLen })
	end
	for _, c in WorldGen.cities do
		table.insert(pts, { x = c.x, z = c.z, r = c.radius * 2 })
	end
	self.bounds = MapMath.worldBounds(WorldGen.BOUNDS, pts, 1000)
	local b = self.bounds
	local worldW, worldH = b.maxX - b.minX, b.maxZ - b.minZ
	self.worldW, self.worldH = worldW, worldH

	local gui = make("ScreenGui", {
		Name = "Minimap", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	self.gui = gui
	local holder = make("Frame", {
		Parent = gui, Name = "Holder", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 48),
		Size = UDim2.fromOffset(SIZE, SIZE + 40), BackgroundTransparency = 1, Visible = false,
	})
	self.holder = holder
	local uiScale = make("UIScale", { Parent = holder })
	local function rescale()
		local cam = Workspace.CurrentCamera
		local h = if cam then cam.ViewportSize.Y else 800
		uiScale.Scale = math.clamp(h / 760, 0.6, 1)
	end
	rescale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	-- Round window. CanvasGroup clips rotated children cleanly.
	local window = make("CanvasGroup", {
		Parent = holder, Name = "Window", Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = rgb(table.unpack(MapMath.WATER_RGB)), BorderSizePixel = 0, ZIndex = 1,
	})
	round(window, UDim.new(0.5, 0))
	self.window = window
	local pivot = make("Frame", {
		Parent = window, Name = "Pivot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(SIZE, SIZE), BackgroundTransparency = 1,
	})
	self.pivot = pivot
	local layer = make("Frame", { Parent = pivot, Name = "World", BackgroundTransparency = 1, ClipsDescendants = false })
	self.layer = layer

	-- Places a child of the world layer at a world point (scale coordinates, so zoom only
	-- has to resize the layer).
	local function at(x: number, z: number): UDim2
		return UDim2.fromScale((x - b.minX) / worldW, (z - b.minZ) / worldH)
	end
	self.at = at

	-- Cities: soft orange area with the name on top.
	for _, c in WorldGen.cities do
		local area = make("Frame", {
			Parent = layer, AnchorPoint = Vector2.new(0.5, 0.5), Position = at(c.x, c.z),
			BackgroundColor3 = CITY, BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 2,
		})
		round(area, UDim.new(0.5, 0))
		table.insert(self.sized, function(scale: number)
			local d = math.max(c.radius * 2.4 * scale, 14)
			area.Size = UDim2.fromOffset(d, d)
		end)
		local name = tagLabel(layer, c.name, WHITE, 13, 6)
		name.Position = at(c.x, c.z - c.radius * 0.6)
		table.insert(self.counterRotate, name)
	end

	-- Airports: runway strip (true heading) plus a code tag.
	self.airportTags = {}
	self.airportRings = {}
	for _, id in Airports.order do
		local l = Airports.layout(id)
		local cx, cz, len, wid, rot = MapMath.runwayRect(l)
		local strip = make("Frame", {
			Parent = layer, AnchorPoint = Vector2.new(0.5, 0.5), Position = at(cx, cz), Rotation = rot,
			BackgroundColor3 = RUNWAY, BorderSizePixel = 0, ZIndex = 4,
		})
		make("UIStroke", { Parent = strip, Color = WHITE, Thickness = 1.5 })
		table.insert(self.sized, function(scale: number)
			strip.Size = UDim2.fromOffset(math.max(len * scale, 12), math.max(wid * scale, 3))
		end)
		local ring = make("Frame", {
			Parent = layer, AnchorPoint = Vector2.new(0.5, 0.5), Position = at(cx, cz), Size = UDim2.fromOffset(30, 30),
			BackgroundTransparency = 1, Visible = false, ZIndex = 3,
		})
		round(ring, UDim.new(0.5, 0))
		make("UIStroke", { Parent = ring, Color = GOLD, Thickness = 3 })
		self.airportRings[id] = ring
		local tag = tagLabel(layer, id, WHITE, 12, 7)
		tag.BackgroundColor3 = PANEL
		tag.BackgroundTransparency = 0.25
		make("UIPadding", {
			Parent = tag, PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
			PaddingTop = UDim.new(0, 1), PaddingBottom = UDim.new(0, 1),
		})
		round(tag, UDim.new(0, 4))
		self.airportTags[id] = tag
		table.insert(self.counterRotate, tag)
		local tx, tz = (cx - b.minX) / worldW, (cz - b.minZ) / worldH
		table.insert(self.sized, function(scale: number)
			-- keep the tag just below the runway, whatever the zoom
			tag.Position = UDim2.new(tx, 0, tz, math.max(wid * scale, 3) * 0.5 + 12)
		end)
	end

	-- Overlay (not rotated): own aircraft, north marker, destination pointer, rim.
	local overlay = make("Frame", {
		Parent = holder, Name = "Overlay", Size = UDim2.fromOffset(SIZE, SIZE), BackgroundTransparency = 1, ZIndex = 2,
	})
	local rim = make("Frame", { Parent = overlay, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1 })
	round(rim, UDim.new(0.5, 0))
	make("UIStroke", { Parent = rim, Color = WHITE, Thickness = 3, Transparency = 0.1 })
	self.me = planeIcon(overlay, 22, ME, 10)
	self.me.Position = UDim2.fromScale(0.5, 0.5)
	local north = tagLabel(overlay, "N", WHITE, 14, 12)
	north.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	north.BackgroundTransparency = 0
	north.AutomaticSize = Enum.AutomaticSize.None
	north.Size = UDim2.fromOffset(20, 20)
	round(north, UDim.new(0.5, 0))
	self.north = north
	-- Points to the destination when it is off the map.
	local pointer = make("Frame", {
		Parent = overlay, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = GOLD, BorderSizePixel = 0, Visible = false, ZIndex = 11,
	})
	round(pointer, UDim.new(0.5, 0))
	make("UIStroke", { Parent = pointer, Color = INK, Thickness = 2 })
	local arrow = make("TextLabel", {
		Parent = pointer, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "^",
		Font = Enum.Font.GothamBlack, TextSize = 20, TextColor3 = INK, ZIndex = 12, Position = UDim2.fromOffset(0, 3),
	})
	self.pointer = pointer
	self.pointerArrow = arrow

	-- Buttons under the map: zoom out, map mode, zoom in.
	local row = SIZE + 6
	local minus = button(holder, "-", UDim2.fromOffset(0, row), UDim2.fromOffset(40, 32))
	local plus = button(holder, "+", UDim2.fromOffset(SIZE - 40, row), UDim2.fromOffset(40, 32))
	local modeBtn = button(holder, "", UDim2.fromOffset(46, row), UDim2.fromOffset(SIZE - 92, 32))
	modeBtn.TextSize = 13
	modeBtn.Font = FONT
	self.modeBtn = modeBtn
	minus.Activated:Connect(function()
		self:setZoom(self.zoom + 1)
	end)
	plus.Activated:Connect(function()
		self:setZoom(self.zoom - 1)
	end)
	modeBtn.Activated:Connect(function()
		self.mode = if self.mode == "north" then "heading" else "north"
		self:_refreshModeText()
	end)
	self:_refreshModeText()

	self:setZoom(self.zoom)
	task.spawn(function()
		self:_buildBase()
	end)
	return self
end

function Minimap:_refreshModeText()
	self.modeBtn.Text = if self.mode == "north" then "Map: North up" else "Map: Plane up"
end

function Minimap:setZoom(index: number)
	self.zoom = MapMath.clampZoom(index)
	local scale = MapMath.scale(SIZE, MapMath.ZOOMS[self.zoom])
	self.scale = scale
	self.layer.Size = UDim2.fromOffset(self.worldW * scale, self.worldH * scale)
	for _, fn in self.sized do
		fn(scale)
	end
end

-- Base map --------------------------------------------------------------------

local function sampleHeights(b: any, w: number, h: number, yieldEvery: number): { number }
	local hs = table.create(w * h, 0)
	for j = 0, h - 1 do
		for i = 0, w - 1 do
			local x, z = MapMath.pixelToWorld(b, w, h, i, j)
			hs[j * w + i + 1] = WorldGen.meshHeight(x, z)
		end
		if j % yieldEvery == yieldEvery - 1 then
			task.wait()
		end
	end
	return hs
end

local function colorAt(hs: { number }, w: number, h: number, i: number, j: number, studsPerPx: number): (number, number, number)
	local function H(ii: number, jj: number): number
		return hs[math.clamp(jj, 0, h - 1) * w + math.clamp(ii, 0, w - 1) + 1]
	end
	local gx = (H(i + 1, j) - H(i - 1, j)) / (2 * studsPerPx)
	local gz = (H(i, j + 1) - H(i, j - 1)) / (2 * studsPerPx)
	return MapMath.terrainColor(H(i, j), gx, gz, WorldGen.SEA_LEVEL)
end

function Minimap:_buildEditable(): boolean
	local b = self.bounds
	local w, h = MapMath.imageSize(b, IMAGE_SIDE)
	local AssetService = game:GetService("AssetService")
	local ok, img = pcall(function()
		return (AssetService :: any):CreateEditableImage({ Size = Vector2.new(w, h) })
	end)
	if not ok or img == nil then
		return false
	end
	local hs = sampleHeights(b, w, h, 24)
	local studsPerPx = (b.maxX - b.minX) / w
	local buf = buffer.create(w * h * 4)
	for j = 0, h - 1 do
		for i = 0, w - 1 do
			local r, g, bl = colorAt(hs, w, h, i, j, studsPerPx)
			local o = (j * w + i) * 4
			buffer.writeu8(buf, o, math.floor(r))
			buffer.writeu8(buf, o + 1, math.floor(g))
			buffer.writeu8(buf, o + 2, math.floor(bl))
			buffer.writeu8(buf, o + 3, 255)
		end
		if j % 48 == 47 then
			task.wait()
		end
	end
	local shown = pcall(function()
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), buf)
		make("ImageLabel", {
			Parent = self.layer, Name = "Base", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			ImageContent = (Content :: any).fromObject(img), ZIndex = 1,
		})
	end)
	if shown then
		self.baseImage = img
	end
	return shown
end

function Minimap:_buildFrames()
	local b = self.bounds
	local w, h = MapMath.imageSize(b, FALLBACK_SIDE)
	local hs = sampleHeights(b, w, h, 8)
	local studsPerPx = (b.maxX - b.minX) / w
	local base = make("Frame", { Parent = self.layer, Name = "Base", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	local function quant(v: number): number
		return math.floor(v / 20 + 0.5) * 20
	end
	for j = 0, h - 1 do
		-- Merge runs of the same (quantised) colour along each row into one Frame.
		local i = 0
		while i < w do
			local r, g, bl = colorAt(hs, w, h, i, j, studsPerPx)
			r, g, bl = quant(r), quant(g), quant(bl)
			local run = 1
			while i + run < w do
				local r2, g2, b2 = colorAt(hs, w, h, i + run, j, studsPerPx)
				if quant(r2) ~= r or quant(g2) ~= g or quant(b2) ~= bl then
					break
				end
				run += 1
			end
			make("Frame", {
				Parent = base, Position = UDim2.fromScale(i / w, j / h), Size = UDim2.new(run / w, 1, 1 / h, 1),
				BackgroundColor3 = rgb(math.min(r, 255), math.min(g, 255), math.min(bl, 255)), BorderSizePixel = 0, ZIndex = 1,
			})
			i += run
		end
		if j % 8 == 7 then
			task.wait()
		end
	end
end

function Minimap:_buildBase()
	local ok, shown = pcall(function()
		return self:_buildEditable()
	end)
	if ok and shown then
		return
	end
	local fine, err = pcall(function()
		self:_buildFrames()
	end)
	if not fine then
		warn("[Minimap] could not draw the base map: " .. tostring(err))
	end
end

-- Public API ------------------------------------------------------------------

function Minimap:_refreshVisible()
	self.holder.Visible = self.enabled and self.flying
end

function Minimap:setFlying(on: boolean)
	self.flying = on
	self:_refreshVisible()
end

function Minimap:toggle()
	self.enabled = not self.enabled
	self:_refreshVisible()
end

local function aircraftPose(m: Model): (Vector3?, number)
	local core = m.PrimaryPart or m:FindFirstChild("Core")
	local cf = if core and core:IsA("BasePart") then core.CFrame else m:GetPivot()
	local look = cf.LookVector
	return cf.Position, Units.headingFromXZ(look.X, look.Z)
end

function Minimap:_scanOthers(ownModel: Model?)
	local folder = Workspace:FindFirstChild("Aircraft")
	local seen = {}
	local myId = Players.LocalPlayer.UserId
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") and m ~= ownModel and m:GetAttribute("AircraftId") ~= nil and m:GetAttribute("OwnerUserId") ~= myId then
				seen[m] = true
				local mk = self.others[m]
				if not mk then
					local holder = make("Frame", {
						Parent = self.layer, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18),
						BackgroundTransparency = 1, ZIndex = 8,
					})
					local icon = planeIcon(holder, 16, FRIEND, 8)
					icon.Position = UDim2.fromScale(0.5, 0.5)
					local owner = Players:GetPlayerByUserId((m:GetAttribute("OwnerUserId") :: number?) or 0)
					local name = tagLabel(holder, if owner then owner.DisplayName else "", FRIEND, 11, 9)
					name.Position = UDim2.new(0.5, 0, 0, -8)
					mk = { holder = holder, icon = icon, name = name }
					self.others[m] = mk
				end
				local pos, heading = aircraftPose(m)
				if pos then
					mk.holder.Position = self.at(pos.X, pos.Z)
					mk.icon.Rotation = heading
				end
			end
		end
	end
	for m, mk in self.others do
		if not seen[m] then
			mk.holder:Destroy()
			self.others[m] = nil
		end
	end
end

-- Wildfires (Workspace.Wildfires, from the server): a pulsing orange dot while burning.
function Minimap:_scanFires()
	local folder = Workspace:FindFirstChild("Wildfires")
	self.fires = self.fires or {}
	local seen = {}
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") and m.PrimaryPart then
				seen[m] = true
				local mk = self.fires[m]
				if not mk then
					local dot = make("Frame", {
						Parent = self.layer, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14),
						BackgroundColor3 = Color3.fromRGB(255, 110, 30), BorderSizePixel = 0, ZIndex = 7,
					})
					round(dot, UDim.new(0.5, 0))
					make("UIStroke", { Parent = dot, Color = Color3.fromRGB(255, 230, 120), Thickness = 2 })
					local p = m.PrimaryPart.Position
					dot.Position = self.at(p.X, p.Z)
					mk = { dot = dot }
					self.fires[m] = mk
				end
				local burning = m:GetAttribute("Burning") ~= false
				mk.dot.Visible = burning
				local pulse = 12 + 5 * math.abs(math.sin(os.clock() * 4))
				mk.dot.Size = UDim2.fromOffset(pulse, pulse)
			end
		end
	end
	for m, mk in self.fires do
		if not seen[m] then
			mk.dot:Destroy()
			self.fires[m] = nil
		end
	end
end

-- Call every frame with the flight telemetry (position, heading), the destination
-- airport id (or nil) and the local aircraft model (so it is not drawn twice).
function Minimap:update(t: any, destination: string?, ownModel: Model?)
	if not t or not t.position or not self.holder.Visible then
		return
	end
	local pos: Vector3 = t.position
	local heading: number = t.heading or 0
	local rot = MapMath.mapRotation(self.mode, heading)
	local view = { cx = pos.X, cz = pos.Z, scale = self.scale, rotation = rot }

	-- Every frame: move and turn the map, the own arrow and the north marker.
	local ox, oy = MapMath.layerOffset(self.bounds, view, SIZE)
	self.layer.Position = UDim2.fromOffset(ox, oy)
	self.pivot.Rotation = rot
	self.me.Rotation = MapMath.markerRotation(heading, rot)
	local nx, ny = MapMath.rotate(0, -(SIZE * 0.5 - 12), rot)
	self.north.Position = UDim2.fromOffset(SIZE * 0.5 + nx, SIZE * 0.5 + ny)
	if rot ~= self.rotation then
		self.rotation = rot
		for _, g in self.counterRotate do
			g.Rotation = -rot
		end
		for _, mk in self.others do
			mk.name.Rotation = -rot
		end
	end

	-- About 10 times a second: other aircraft and the destination.
	local now = os.clock()
	if now < self.nextScan then
		return
	end
	self.nextScan = now + SCAN_INTERVAL
	self:_scanOthers(ownModel)
	self:_scanFires()
	for _, mk in self.others do
		mk.name.Rotation = -rot
	end

	local dest = if destination and Airports.list[destination] then destination else nil
	for id, ring in self.airportRings do
		local on = id == dest
		ring.Visible = on
		local tag = self.airportTags[id]
		tag.BackgroundColor3 = if on then GOLD else PANEL
		tag.TextColor3 = if on then INK else WHITE
		tag.Text = if on then `{id}  Fly here!` else id
		if on then
			local pulse = 30 + 8 * math.abs(math.sin(now * 3))
			ring.Size = UDim2.fromOffset(pulse, pulse)
		end
	end
	if dest then
		local l = Airports.layout(dest)
		local sx, sy = MapMath.toScreen(view, l.cx, l.cz)
		local inside, ex, ey, angle = MapMath.edgePointer(sx, sy, SIZE * 0.5 - 14)
		self.pointer.Visible = not inside
		if not inside then
			self.pointer.Position = UDim2.fromOffset(SIZE * 0.5 + ex, SIZE * 0.5 + ey)
			self.pointer.Rotation = angle
		end
	else
		self.pointer.Visible = false
	end
end

return Minimap
