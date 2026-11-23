--!strict
-- Stunts race HUD: ring counter, race clock, penalties and best time (top centre), a big
-- arrow or marker pointing at the next ring, cheers and miss warnings, and the results
-- card with a one-tap restart. It also recolours the course rings locally: the next ring
-- glows green (and shows through hills), the one after is yellow, passed rings fade.
-- The server times the race (MissionService); this only displays it.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Stunts = require(Shared.Stunts)
local Units = require(Shared.Units)

local StuntsHud = {}
StuntsHud.__index = StuntsHud

local WHITE = Color3.fromRGB(240, 244, 248)
local DIM = Color3.fromRGB(170, 180, 192)
local PANEL = Color3.fromRGB(12, 16, 24)
local GREEN = Color3.fromRGB(60, 230, 100)
local YELLOW = Color3.fromRGB(255, 210, 60)
local ORANGE = Color3.fromRGB(255, 140, 30)
local RED = Color3.fromRGB(240, 70, 60)
local PASSED = Color3.fromRGB(210, 215, 225)
local MEDAL_COLORS = {
	gold = Color3.fromRGB(255, 205, 50),
	silver = Color3.fromRGB(205, 212, 222),
	bronze = Color3.fromRGB(215, 140, 80),
}
local CHEERS = { "NICE!", "GREAT!", "AWESOME!", "SUPER!", "WOW!", "BRILLIANT!" }

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

local function stroke(inst: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = inst
end

local function text(parent: Instance, t: string, pos: UDim2, size: UDim2, font: Enum.Font, color: Color3, textSize: number): TextLabel
	return make("TextLabel", {
		Parent = parent, Text = t, Position = pos, Size = size, BackgroundTransparency = 1,
		Font = font, TextColor3 = color, TextSize = textSize, TextStrokeTransparency = 0.5,
	})
end

function StuntsHud.new(callbacks: any)
	local self = setmetatable({}, StuntsHud) :: any
	self.callbacks = callbacks
	self.active = false
	self.data = nil :: any
	self.recvClock = 0
	self.flashUntil = 0
	self.coloredFor = -1
	self.highlight = nil :: Highlight?

	local gui = make("ScreenGui", {
		Name = "StuntsHud", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5, Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	self.gui = gui

	-- Top centre: ring count, clock, penalties, best
	local top = make("Frame", {
		Parent = gui, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(440, 84), BackgroundColor3 = PANEL, BackgroundTransparency = 0.25,
	})
	round(top, 12)
	self.ringLabel = text(top, "RING 1/12", UDim2.fromOffset(14, 6), UDim2.fromOffset(150, 40), Enum.Font.GothamBlack, GREEN, 28)
	self.ringLabel.TextXAlignment = Enum.TextXAlignment.Left
	self.timeLabel = text(top, "0:00.0", UDim2.new(0.5, -60, 0, 4), UDim2.fromOffset(200, 44), Enum.Font.RobotoMono, WHITE, 38)
	self.penaltyLabel = text(top, "", UDim2.new(1, -110, 0, 10), UDim2.fromOffset(96, 30), Enum.Font.GothamBlack, RED, 22)
	self.penaltyLabel.TextXAlignment = Enum.TextXAlignment.Right
	self.subLabel = text(top, "", UDim2.fromOffset(14, 50), UDim2.new(1, -28, 0, 26), Enum.Font.GothamBold, DIM, 17)

	-- Cheers / warnings under the top panel
	self.flash = text(gui, "", UDim2.new(0.5, -300, 0, 104), UDim2.fromOffset(600, 60), Enum.Font.GothamBlack, GREEN, 48)
	self.flash.TextStrokeTransparency = 0.1

	-- Pointer: an on-screen marker over the next ring, or an arrow at the screen edge.
	local marker = make("Frame", {
		Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(56, 56),
		BackgroundTransparency = 1, Visible = false,
	})
	local mc = Instance.new("UICorner")
	mc.CornerRadius = UDim.new(0.5, 0) -- a circle at any size
	mc.Parent = marker
	stroke(marker, GREEN, 4)
	self.marker = marker
	self.markerDist = text(marker, "", UDim2.new(0.5, -60, 1, 4), UDim2.fromOffset(120, 24), Enum.Font.GothamBlack, GREEN, 20)
	local arrow = make("Frame", {
		Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(80, 80),
		BackgroundTransparency = 1, Visible = false,
	})
	self.arrow = arrow
	-- a chunky chevron pointing up (Rotation 0 = up the screen)
	for _, side in { -1, 1 } do
		local bar = make("Frame", {
			Parent = arrow, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, side * 13, 0.5, 0),
			Size = UDim2.fromOffset(40, 13), Rotation = side * 45, BackgroundColor3 = GREEN, BorderSizePixel = 0,
		})
		round(bar, 6)
		stroke(bar, Color3.fromRGB(10, 40, 20), 2)
	end
	self.arrowDist = text(gui, "", UDim2.fromOffset(0, 0), UDim2.fromOffset(120, 24), Enum.Font.GothamBlack, GREEN, 20)
	self.arrowDist.AnchorPoint = Vector2.new(0.5, 0.5)
	self.arrowDist.Visible = false

	-- Results card
	local card = make("Frame", {
		Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(440, 330), BackgroundColor3 = PANEL, BackgroundTransparency = 0.08, Visible = false,
	})
	round(card, 16)
	stroke(card, GREEN, 3)
	self.card = card
	self.cardStroke = card:FindFirstChildOfClass("UIStroke")
	local scale = Instance.new("UIScale")
	scale.Parent = card
	self.cardScale = scale
	self.cardTitle = text(card, "FINISH!", UDim2.fromOffset(0, 14), UDim2.new(1, 0, 0, 50), Enum.Font.GothamBlack, GREEN, 44)
	self.cardTime = text(card, "", UDim2.fromOffset(0, 66), UDim2.new(1, 0, 0, 56), Enum.Font.RobotoMono, WHITE, 52)
	self.cardMedal = text(card, "", UDim2.fromOffset(0, 124), UDim2.new(1, 0, 0, 34), Enum.Font.GothamBlack, MEDAL_COLORS.gold, 28)
	self.cardLine = text(card, "", UDim2.fromOffset(16, 160), UDim2.new(1, -32, 0, 24), Enum.Font.GothamBold, WHITE, 18)
	self.cardBest = text(card, "", UDim2.fromOffset(16, 186), UDim2.new(1, -32, 0, 24), Enum.Font.GothamBold, YELLOW, 18)
	self.cardHint = text(card, "", UDim2.fromOffset(16, 212), UDim2.new(1, -32, 0, 22), Enum.Font.GothamMedium, DIM, 16)
	local again = make("TextButton", {
		Parent = card, Text = "FLY AGAIN (R)", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -18),
		Size = UDim2.new(0.5, -30, 0, 58), BackgroundColor3 = Color3.fromRGB(30, 160, 90), Font = Enum.Font.GothamBlack,
		TextColor3 = WHITE, TextSize = 22,
	})
	round(again, 12)
	again.Activated:Connect(function()
		self.callbacks.onRetry()
	end)
	local menuBtn = make("TextButton", {
		Parent = card, Text = "MENU (M)", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -18),
		Size = UDim2.new(0.5, -30, 0, 58), BackgroundColor3 = Color3.fromRGB(40, 70, 120), Font = Enum.Font.GothamBold,
		TextColor3 = WHITE, TextSize = 20,
	})
	round(menuBtn, 12)
	menuBtn.Activated:Connect(function()
		self.callbacks.onMenu()
	end)

	local cam = Workspace.CurrentCamera
	local function fit()
		local vp = cam.ViewportSize
		scale.Scale = math.clamp(math.min(vp.X / 520, vp.Y / 420), 0.6, 1.2)
	end
	fit()
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	return self
end

-- Course ring models in the world (built by the server).
function StuntsHud:rings(): { [number]: Model }
	local out = {}
	local world = Workspace:FindFirstChild("World")
	local folder = world and world:FindFirstChild("StuntCourse")
	if folder then
		for _, m in folder:GetChildren() do
			local i = m:GetAttribute("RingIndex")
			if type(i) == "number" and m:IsA("Model") then
				out[i] = m
			end
		end
	end
	return out
end

local function paint(model: Model, color: Color3, transparency: number)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Name == "Segment" then
			p.Color = color
			p.Transparency = transparency
		end
	end
end

-- Colour every ring for the current race state (or back to plain orange when stopped).
function StuntsHud:colorRings()
	local d = self.data
	local nextRing = if self.active and d then d.nextRing else -1
	local results = (self.active and d and d.results) or {}
	for i, m in self:rings() do
		if not self.active then
			paint(m, ORANGE, 0)
		elseif results[i] == "hit" then
			paint(m, PASSED, 0.82)
		elseif results[i] == "miss" then
			paint(m, RED, 0.7)
		elseif i == nextRing then
			paint(m, GREEN, 0)
		elseif i == nextRing + 1 then
			paint(m, YELLOW, 0.1)
		else
			paint(m, ORANGE, 0.35)
		end
	end
	-- the next ring also shows through hills and haze
	local target = if self.active and d and (d.state == "ready" or d.state == "racing") then self:rings()[nextRing] else nil
	if target then
		local h = self.highlight
		if not h then
			h = Instance.new("Highlight")
			h.Name = "NextRingHighlight"
			h.FillColor = GREEN
			h.FillTransparency = 0.75
			h.OutlineColor = WHITE
			h.OutlineTransparency = 0
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			self.highlight = h
		end
		h.Adornee = target
		h.Parent = target
		h.Enabled = true
	elseif self.highlight then
		self.highlight.Enabled = false
	end
end

function StuntsHud:start()
	self.active = true
	self.data = nil
	self.gui.Enabled = true
	self.card.Visible = false
	self.flash.Text = ""
	self.coloredFor = -1
end

function StuntsHud:stop()
	self.active = false
	self.data = nil
	self.gui.Enabled = false
	self.card.Visible = false
	if self.highlight then
		self.highlight:Destroy()
		self.highlight = nil
	end
	self:colorRings()
end

function StuntsHud:isActive(): boolean
	return self.active
end

function StuntsHud:showFlash(t: string, color: Color3, seconds: number)
	self.flash.Text = t
	self.flash.TextColor3 = color
	self.flashUntil = os.clock() + seconds
end

-- Server update (MissionService.sendStunts).
function StuntsHud:onUpdate(data: any)
	if not self.active or type(data) ~= "table" then
		return
	end
	-- keep the per-ring results here (the server sends counts and events)
	local prev = self.data
	local results = if prev and prev.results and data.state ~= "ready" then prev.results else {}
	for _, e in data.events or {} do
		if e.kind == "start" or e.kind == "pass" or e.kind == "finish" then
			if e.ring then
				results[e.ring] = results[e.ring] or "hit"
			end
		elseif e.kind == "miss" and e.ring then
			results[e.ring] = "miss"
		end
	end
	data.results = results
	self.data = data
	self.recvClock = os.clock()
	for _, e in data.events or {} do
		if e.kind == "ready" then
			self.card.Visible = false
			self:showFlash("Fly through the START ring!", YELLOW, 6)
		elseif e.kind == "start" then
			self:showFlash("GO! GO! GO!", GREEN, 1.6)
		elseif e.kind == "pass" then
			self:showFlash(CHEERS[(e.ring % #CHEERS) + 1], GREEN, 1.0)
		elseif e.kind == "miss" then
			self:showFlash(`MISSED! +{Stunts.MISS_PENALTY_S} s`, RED, 1.6)
		end
	end
	if data.state == "finished" then
		self:showResults(data, false)
	elseif data.state == "crashed" then
		self:showResults(data, true)
	end
	self:colorRings()
end

function StuntsHud:showResults(d: any, crashed: boolean)
	self.flash.Text = ""
	self.card.Visible = true
	if crashed then
		self.cardTitle.Text = "CRASHED!"
		self.cardTitle.TextColor3 = RED
		;(self.cardStroke :: UIStroke).Color = RED
		self.cardTime.Text = `{d.hit} of {d.total} rings`
		self.cardMedal.Text = if d.crashReason == "ground" then "You touched the ground" else "The plane broke up"
		self.cardMedal.TextColor3 = WHITE
		self.cardLine.Text = "Pull up early before the low rings!"
		self.cardBest.Text = if d.best then `Your best: {Stunts.formatTime(d.best)}` else ""
		self.cardHint.Text = "Press R to try again straight away."
		return
	end
	local total = d.totalTime or (d.elapsed + d.penalties)
	self.cardTitle.Text = "FINISH!"
	self.cardTitle.TextColor3 = GREEN
	;(self.cardStroke :: UIStroke).Color = if d.medal then MEDAL_COLORS[d.medal] else GREEN
	self.cardTime.Text = Stunts.formatTime(total)
	self.cardMedal.Text = if d.medal then `{string.upper(d.medal)} MEDAL` else "Finished!"
	self.cardMedal.TextColor3 = if d.medal then MEDAL_COLORS[d.medal] else WHITE
	local line = `{d.hit} of {d.total} rings`
	if d.missed > 0 then
		line ..= `  ·  {d.missed} missed (+{d.penalties} s)`
	end
	self.cardLine.Text = line
	self.cardBest.Text = if d.newBest then "NEW BEST TIME!" elseif d.best then `Your best: {Stunts.formatTime(d.best)}` else ""
	local m = Stunts.MEDALS
	if d.medal == "gold" then
		self.cardHint.Text = "Top pilot! Can you go even faster?"
	elseif d.medal == "silver" then
		self.cardHint.Text = `Gold is under {Stunts.formatTime(m.gold)}. Try again!`
	elseif d.medal == "bronze" then
		self.cardHint.Text = `Silver is under {Stunts.formatTime(m.silver)}. Try again!`
	else
		self.cardHint.Text = `Bronze is under {Stunts.formatTime(m.bronze)}. Try again!`
	end
end

-- Every frame while flying: clock, ring count and the pointer to the next ring.
function StuntsHud:update(position: Vector3?)
	if not self.active then
		return
	end
	local d = self.data
	local now = os.clock()
	if now > self.flashUntil then
		self.flash.Text = ""
	end
	if not d then
		return
	end
	local total = d.total or #Stunts.course()
	local nextRing = math.clamp(d.nextRing or 1, 1, total)
	local racing = d.state == "racing"
	local elapsed = d.elapsed or 0
	if racing then
		elapsed += now - self.recvClock
	end
	self.timeLabel.Text = Stunts.formatTime(if d.state == "finished" and d.totalTime then d.totalTime - d.penalties else elapsed)
	self.ringLabel.Text = if d.state == "finished" then "DONE!" else `RING {nextRing}/{total}`
	self.ringLabel.TextColor3 = if d.state == "crashed" then RED else GREEN
	self.penaltyLabel.Text = if (d.penalties or 0) > 0 then `+{d.penalties} s` else ""
	if d.state == "ready" then
		self.subLabel.Text = "The clock starts at the START ring"
	elseif d.best then
		self.subLabel.Text = `Best {Stunts.formatTime(d.best)}  ·  Gold under {Stunts.formatTime(Stunts.MEDALS.gold)}`
	else
		self.subLabel.Text = `Gold under {Stunts.formatTime(Stunts.MEDALS.gold)}`
	end

	-- pointer
	local showPointer = position ~= nil and (d.state == "ready" or racing)
	if not showPointer then
		self.marker.Visible = false
		self.arrow.Visible = false
		self.arrowDist.Visible = false
		return
	end
	local r = Stunts.course()[nextRing]
	local target = Vector3.new(r.x, r.y, r.z)
	local distM = ((target - (position :: Vector3)).Magnitude * Units.METERS_PER_STUD)
	local distText = string.format("%d m", math.floor(distM / 10 + 0.5) * 10)
	local cam = Workspace.CurrentCamera
	local vp = cam.ViewportSize
	local sp, onScreen = cam:WorldToViewportPoint(target)
	local margin = 70
	if onScreen and sp.Z > 0 and sp.X > margin and sp.X < vp.X - margin and sp.Y > margin and sp.Y < vp.Y - margin then
		self.arrow.Visible = false
		self.arrowDist.Visible = false
		self.marker.Visible = true
		self.marker.Position = UDim2.fromOffset(sp.X, sp.Y)
		-- the marker grows as the ring gets closer
		local px = math.clamp(4000 / math.max(distM, 1), 40, 140)
		self.marker.Size = UDim2.fromOffset(px, px)
		self.markerDist.Text = distText
	else
		self.marker.Visible = false
		-- direction on screen from the centre; behind the camera, flip it
		local cx, cy = vp.X / 2, vp.Y / 2
		local dx, dy = sp.X - cx, sp.Y - cy
		if sp.Z < 0 then
			dx, dy = -dx, -dy
		end
		if math.abs(dx) < 1e-3 and math.abs(dy) < 1e-3 then
			dy = 1
		end
		local len = math.sqrt(dx * dx + dy * dy)
		local ux, uy = dx / len, dy / len
		-- place it on an ellipse inside the screen edge
		local ax, ay = vp.X * 0.5 - 90, vp.Y * 0.5 - 90
		local k = 1 / math.sqrt((ux / ax) ^ 2 + (uy / ay) ^ 2)
		local x, y = cx + ux * k, cy + uy * k
		self.arrow.Visible = true
		self.arrow.Position = UDim2.fromOffset(x, y)
		self.arrow.Rotation = math.deg(math.atan2(ux, -uy))
		self.arrowDist.Visible = true
		self.arrowDist.Position = UDim2.fromOffset(x - ux * 60, y - uy * 60)
		self.arrowDist.Text = distText
	end
end

return StuntsHud
