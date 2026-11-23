--!strict
-- Flight HUD: speed/altitude/vertical speed/heading, attitude indicator, engines and
-- configuration, navigation + approach guidance, warnings, damage, objectives,
-- landing results, and a developer debug panel. Built entirely from code.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Units = require(Shared.Units)
local Airports = require(Shared.Airports)
local Damage = require(Shared.Damage)

local SPM = Units.STUDS_PER_METER

local Hud = {}
Hud.__index = Hud

local FONT = Enum.Font.GothamMedium
local MONO = Enum.Font.RobotoMono
local GREEN = Color3.fromRGB(90, 235, 140)
local AMBER = Color3.fromRGB(255, 190, 60)
local RED = Color3.fromRGB(255, 70, 70)
local WHITE = Color3.fromRGB(240, 244, 248)
local DIM = Color3.fromRGB(160, 170, 180)
local PANEL = Color3.fromRGB(12, 16, 22)

local function make(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className) :: any
	for k, v in props do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(r: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	return c
end

local function panel(parent: Instance, pos: UDim2, size: UDim2, anchor: Vector2?): Frame
	return make("Frame", {
		Parent = parent, Position = pos, Size = size, AnchorPoint = anchor or Vector2.zero,
		BackgroundColor3 = PANEL, BackgroundTransparency = 0.35, BorderSizePixel = 0,
	}, { corner(8) })
end

local function label(parent: Instance, text: string, pos: UDim2, size: UDim2, font: Enum.Font?, color: Color3?, align: Enum.TextXAlignment?, textSize: number?): TextLabel
	return make("TextLabel", {
		Parent = parent, Text = text, Position = pos, Size = size, BackgroundTransparency = 1,
		Font = font or FONT, TextColor3 = color or WHITE, TextXAlignment = align or Enum.TextXAlignment.Left,
		TextSize = textSize or 16, TextStrokeTransparency = 0.7, RichText = true,
	})
end

local function fmtThousands(n: number): string
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-" else "") .. out
end

function Hud.new()
	local self = setmetatable({}, Hud) :: any
	local gui = make("ScreenGui", {
		Name = "FlightHud", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	self.gui = gui
	self.visible = true
	self.debug = false
	self.flight = make("Frame", { Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	local root = self.flight

	-- Speed (left)
	-- bottom row, either side of the attitude ball, above the engine/config panels
	local sp = panel(root, UDim2.new(0.5, -100, 1, -146), UDim2.fromOffset(120, 140), Vector2.new(1, 1))
	self.ias = label(sp, "---", UDim2.fromOffset(10, 8), UDim2.new(1, -20, 0, 40), MONO, WHITE, Enum.TextXAlignment.Right, 34)
	label(sp, "KT IAS", UDim2.fromOffset(10, 46), UDim2.new(1, -20, 0, 16), FONT, DIM, Enum.TextXAlignment.Right, 12)
	self.gs = label(sp, "GS ---", UDim2.fromOffset(10, 70), UDim2.new(1, -20, 0, 18), MONO, DIM, Enum.TextXAlignment.Right, 15)
	self.speedHint = label(sp, "", UDim2.fromOffset(10, 94), UDim2.new(1, -20, 0, 36), FONT, AMBER, Enum.TextXAlignment.Right, 13)
	self.speedHint.TextWrapped = true

	-- Altitude (right)
	local al = panel(root, UDim2.new(0.5, 104, 1, -146), UDim2.fromOffset(140, 140), Vector2.new(0, 1))
	self.alt = label(al, "---", UDim2.fromOffset(10, 8), UDim2.new(1, -20, 0, 40), MONO, WHITE, Enum.TextXAlignment.Left, 30)
	label(al, "FT MSL", UDim2.fromOffset(10, 46), UDim2.new(1, -20, 0, 16), FONT, DIM, Enum.TextXAlignment.Left, 12)
	self.vs = label(al, "", UDim2.fromOffset(10, 70), UDim2.new(1, -20, 0, 18), MONO, WHITE, Enum.TextXAlignment.Left, 15)
	self.ra = label(al, "", UDim2.fromOffset(10, 94), UDim2.new(1, -20, 0, 18), MONO, GREEN, Enum.TextXAlignment.Left, 15)

	-- Attitude indicator (centre-bottom so it never hides the runway)
	local adi = make("CanvasGroup", {
		Parent = root, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(150, 150), BackgroundColor3 = Color3.fromRGB(20, 20, 20), BackgroundTransparency = 0.2,
	}, { corner(75) })
	self.adiHorizon = make("Frame", {
		Parent = adi, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 600), BackgroundTransparency = 1,
	})
	make("Frame", { Parent = self.adiHorizon, Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = Color3.fromRGB(56, 130, 210), BorderSizePixel = 0 })
	make("Frame", { Parent = self.adiHorizon, Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = Color3.fromRGB(130, 90, 50), BorderSizePixel = 0 })
	make("Frame", { Parent = self.adiHorizon, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = WHITE, BorderSizePixel = 0 })
	for _, deg in { -20, -10, 10, 20 } do
		make("Frame", {
			Parent = self.adiHorizon, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -deg * 4),
			Size = UDim2.fromOffset(if math.abs(deg) == 10 then 40 else 60, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0,
		})
	end
	-- fixed aircraft symbol
	make("Frame", { Parent = adi, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(70, 3), BackgroundColor3 = Color3.fromRGB(255, 210, 0), BorderSizePixel = 0, ZIndex = 3 })
	make("Frame", { Parent = adi, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = Color3.fromRGB(255, 210, 0), BorderSizePixel = 0, ZIndex = 3 })
	self.adi = adi
	-- approach deviation bars (localizer below, glideslope right of the ADI)
	self.loc = make("Frame", { Parent = root, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -134), Size = UDim2.fromOffset(150, 12), BackgroundTransparency = 1, Visible = false })
	make("Frame", { Parent = self.loc, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = DIM, BorderSizePixel = 0 })
	self.locDot = make("Frame", { Parent = self.loc, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = Color3.fromRGB(230, 90, 230), BorderSizePixel = 0, Rotation = 45 })
	self.gsBar = make("Frame", { Parent = root, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.5, 84, 1, -150), Size = UDim2.fromOffset(12, 150), BackgroundTransparency = 1, Visible = false })
	make("Frame", { Parent = self.gsBar, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = DIM, BorderSizePixel = 0 })
	self.gsDot = make("Frame", { Parent = self.gsBar, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = Color3.fromRGB(230, 90, 230), BorderSizePixel = 0, Rotation = 45 })

	-- Heading + navigation (top centre)
	local hd = panel(root, UDim2.new(0.5, 0, 0, 12), UDim2.fromOffset(420, 64), Vector2.new(0.5, 0))
	self.navPanel = hd
	self.heading = label(hd, "HDG ---", UDim2.fromOffset(12, 6), UDim2.new(0, 140, 0, 26), MONO, WHITE, Enum.TextXAlignment.Left, 22)
	self.navArrow = label(hd, "^", UDim2.new(0.5, -15, 0, 4), UDim2.fromOffset(30, 30), Enum.Font.GothamBlack, Color3.fromRGB(230, 90, 230), Enum.TextXAlignment.Center, 26)
	self.nav = label(hd, "", UDim2.new(0.5, 20, 0, 6), UDim2.new(0.5, -30, 0, 26), MONO, Color3.fromRGB(230, 150, 240), Enum.TextXAlignment.Right, 16)
	self.navSub = label(hd, "", UDim2.fromOffset(12, 36), UDim2.new(1, -24, 0, 20), FONT, DIM, Enum.TextXAlignment.Center, 13)

	-- Objective / tutorial (top left)
	local ob = panel(root, UDim2.fromOffset(12, 12), UDim2.fromOffset(330, 74))
	self.objectivePanel = ob
	label(ob, "OBJECTIVE", UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 14), FONT, DIM, Enum.TextXAlignment.Left, 11)
	self.objective = label(ob, "Free flight", UDim2.fromOffset(12, 22), UDim2.new(1, -24, 0, 46), FONT, WHITE, Enum.TextXAlignment.Left, 14)
	self.objective.TextWrapped = true
	self.objective.TextYAlignment = Enum.TextYAlignment.Top

	-- Engines (bottom left)
	local en = panel(root, UDim2.new(0, 12, 1, -12), UDim2.fromOffset(230, 128), Vector2.new(0, 1))
	label(en, "ENGINES", UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 14), FONT, DIM, Enum.TextXAlignment.Left, 11)
	self.engineBars = {}
	-- up to four engines: two tall bars for a twin, four compact ones for a jumbo
	for i = 1, 4 do
		local bg = make("Frame", { Parent = en, BackgroundColor3 = Color3.fromRGB(40, 44, 50), BorderSizePixel = 0 }, { corner(4) })
		local fill = make("Frame", { Parent = bg, Size = UDim2.fromScale(0, 1), BackgroundColor3 = GREEN, BorderSizePixel = 0 }, { corner(4) })
		local txt = label(en, "", UDim2.new(), UDim2.fromOffset(80, 18), MONO, WHITE, Enum.TextXAlignment.Left, 14)
		self.engineBars[i] = { bg = bg, fill = fill, text = txt }
	end
	self.engineCount = 0
	self.throttle = label(en, "", UDim2.fromOffset(12, 86), UDim2.new(1, -24, 0, 16), MONO, WHITE, Enum.TextXAlignment.Left, 14)
	self.fuel = label(en, "", UDim2.fromOffset(12, 104), UDim2.new(1, -24, 0, 16), MONO, DIM, Enum.TextXAlignment.Left, 13)

	-- Configuration strip (bottom centre-left)
	local cfgp = panel(root, UDim2.new(0, 252, 1, -12), UDim2.fromOffset(250, 128), Vector2.new(0, 1))
	label(cfgp, "CONFIG", UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 14), FONT, DIM, Enum.TextXAlignment.Left, 11)
	self.flaps = label(cfgp, "", UDim2.fromOffset(12, 24), UDim2.new(1, -24, 0, 18), MONO, WHITE, Enum.TextXAlignment.Left, 15)
	self.gear = label(cfgp, "", UDim2.fromOffset(12, 44), UDim2.new(1, -24, 0, 18), MONO, GREEN, Enum.TextXAlignment.Left, 15)
	self.brakes = label(cfgp, "", UDim2.fromOffset(12, 64), UDim2.new(1, -24, 0, 18), MONO, WHITE, Enum.TextXAlignment.Left, 15)
	self.trim = label(cfgp, "", UDim2.fromOffset(12, 84), UDim2.new(1, -24, 0, 18), MONO, DIM, Enum.TextXAlignment.Left, 14)
	self.mode = label(cfgp, "", UDim2.fromOffset(12, 104), UDim2.new(1, -24, 0, 18), FONT, Color3.fromRGB(120, 200, 255), Enum.TextXAlignment.Left, 13)

	-- Damage (bottom right)
	local dm = panel(root, UDim2.new(1, -12, 1, -12), UDim2.fromOffset(200, 170), Vector2.new(1, 1))
	label(dm, "AIRFRAME", UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 14), FONT, DIM, Enum.TextXAlignment.Left, 11)
	self.damageList = label(dm, "", UDim2.fromOffset(12, 22), UDim2.new(1, -24, 1, -28), MONO, WHITE, Enum.TextXAlignment.Left, 12)
	self.damageList.TextYAlignment = Enum.TextYAlignment.Top

	-- Warnings (centre)
	self.warning = label(root, "", UDim2.new(0.5, -250, 0.5, -150), UDim2.fromOffset(500, 44), Enum.Font.GothamBlack, RED, Enum.TextXAlignment.Center, 34)
	self.caution = label(root, "", UDim2.new(0.5, -250, 0.5, -108), UDim2.fromOffset(500, 26), Enum.Font.GothamBold, AMBER, Enum.TextXAlignment.Center, 20)
	self.touchdown = label(root, "", UDim2.new(0.5, -250, 0.5, 90), UDim2.fromOffset(500, 30), Enum.Font.GothamBold, WHITE, Enum.TextXAlignment.Center, 22)

	-- Debug panel (F3)
	local dbg = panel(gui, UDim2.new(1, -12, 0, 12), UDim2.fromOffset(330, 400), Vector2.new(1, 0))
	dbg.Visible = false
	self.debugPanel = dbg
	self.debugText = label(dbg, "", UDim2.fromOffset(10, 8), UDim2.new(1, -20, 1, -16), MONO, WHITE, Enum.TextXAlignment.Left, 12)
	self.debugText.TextYAlignment = Enum.TextYAlignment.Top

	-- Toasts
	self.toast = label(gui, "", UDim2.new(0.5, -300, 0, 90), UDim2.fromOffset(600, 28), Enum.Font.GothamBold, WHITE, Enum.TextXAlignment.Center, 18)
	self.toastUntil = 0

	-- Landing result card
	local card = panel(gui, UDim2.new(0.5, 0, 0.32, 0), UDim2.fromOffset(360, 220), Vector2.new(0.5, 0))
	card.Visible = false
	card.BackgroundTransparency = 0.1
	self.card = card
	self.cardGrade = label(card, "", UDim2.fromOffset(16, 10), UDim2.fromOffset(110, 80), Enum.Font.GothamBlack, GREEN, Enum.TextXAlignment.Left, 64)
	self.cardScore = label(card, "", UDim2.fromOffset(130, 18), UDim2.new(1, -146, 0, 30), Enum.Font.GothamBold, WHITE, Enum.TextXAlignment.Left, 22)
	self.cardSub = label(card, "", UDim2.fromOffset(130, 50), UDim2.new(1, -146, 0, 36), FONT, DIM, Enum.TextXAlignment.Left, 14)
	self.cardRemarks = label(card, "", UDim2.fromOffset(16, 96), UDim2.new(1, -32, 1, -106), FONT, WHITE, Enum.TextXAlignment.Left, 14)
	self.cardRemarks.TextYAlignment = Enum.TextYAlignment.Top
	self.cardRemarks.TextWrapped = true
	self.cardUntil = 0

	self.mission = nil :: any
	return self
end

function Hud:setFlying(on: boolean)
	self.flight.Visible = on and self.visible
end

-- Stunts mode has its own race HUD (client/StuntsHud.luau): hide the airport navigation,
-- the objective box and landing grades while racing.
function Hud:setStuntsMode(on: boolean)
	self.stunts = on
	self.navPanel.Visible = not on
	self.objectivePanel.Visible = not on
	if on then
		self.cardUntil = 0
	end
end

function Hud:toggle()
	self.visible = not self.visible
	self.flight.Visible = self.visible
end

function Hud:toggleDebug()
	self.debug = not self.debug
	self.debugPanel.Visible = self.debug
end

function Hud:notify(text: string, seconds: number?)
	self.toast.Text = text
	self.toastUntil = os.clock() + (seconds or 4)
end

function Hud:setMission(data: any)
	self.mission = data
end

function Hud:showLanding(result: any)
	if self.stunts then
		return
	end
	local colors = { A = GREEN, B = GREEN, C = AMBER, D = AMBER, F = RED, CRASH = RED }
	self.cardGrade.Text = result.letter
	self.cardGrade.TextColor3 = colors[result.letter] or WHITE
	self.cardGrade.TextSize = if result.letter == "CRASH" then 34 else 64
	self.cardScore.Text = `Landing score {result.score}/100`
	self.cardSub.Text = `{result.airport or ""}  ·  {result.vsFpm or "?"} fpm ({result.vsSource or "server"})`
	self.cardRemarks.Text = table.concat(result.remarks or {}, "\n")
	self.card.Visible = true
	self.cardUntil = os.clock() + 9
end

local function damageColor(state: string): Color3
	if state == "normal" then
		return GREEN
	elseif state == "degraded" then
		return AMBER
	end
	return RED
end

local SHORT = {
	Fuselage = "Fuselage ctr", ForwardFuselage = "Fuselage fwd", AftFuselage = "Fuselage aft",
	LeftWing = "Left wing", RightWing = "Right wing", LeftEngine = "Engine 1", RightEngine = "Engine 2",
	LeftOuterEngine = "Engine 1", LeftInnerEngine = "Engine 2", RightInnerEngine = "Engine 3", RightOuterEngine = "Engine 4",
	LeftWingGear = "Left wing gear", RightWingGear = "Right wing gear", LeftBodyGear = "Left body gear", RightBodyGear = "Right body gear",
	HorizontalStab = "Tailplane", VerticalStab = "Fin", NoseGear = "Nose gear",
	LeftMainGear = "Left main", RightMainGear = "Right main",
}
local DAMAGE_ORDER = { "ForwardFuselage", "Fuselage", "AftFuselage", "LeftWing", "RightWing",
	"LeftOuterEngine", "LeftEngine", "LeftInnerEngine", "RightInnerEngine", "RightEngine", "RightOuterEngine",
	"HorizontalStab", "VerticalStab", "NoseGear", "LeftMainGear", "RightMainGear",
	"LeftWingGear", "RightWingGear", "LeftBodyGear", "RightBodyGear" }
local DAMAGE_RANK = {}
for i, n in DAMAGE_ORDER do
	DAMAGE_RANK[n] = i
end

-- Navigation: destination bearing/distance and approach deviations.
local function navInfo(t: any, destId: string?)
	local pos = t.position
	local id = destId
	if not id or not Airports.list[id] then
		local near = Airports.nearest(pos.X, pos.Z)
		id = near
		-- in free flight, point at the airport you are not at
		local l = Airports.layout(near)
		local d = math.sqrt((l.cx - pos.X) ^ 2 + (l.cz - pos.Z) ^ 2)
		if d < 8000 and t.onGround then
			id = if near == "HBR" then "RDV" else "HBR"
		end
	end
	local l = Airports.layout(id :: string)
	local dx, dz = l.cx - pos.X, l.cz - pos.Z
	local distM = math.sqrt(dx * dx + dz * dz) / SPM
	local bearing = Units.headingFromXZ(dx, dz)
	-- choose the runway end best aligned with the current track toward the field
	local best, bestScore = l.ends[1], math.huge
	for _, e in l.ends do
		local diff = math.abs(((t.heading - e.heading + 540) % 360) - 180)
		local px, pz = pos.X - e.thx, pos.Z - e.thz
		local before = -(px * e.dx + pz * e.dz)
		local score = diff + (if before < 0 then 90 else 0)
		if score < bestScore then
			best, bestScore = e, score
		end
	end
	local px, pz = pos.X - best.thx, pos.Z - best.thz
	local beforeM = -(px * best.dx + pz * best.dz) / SPM -- metres before threshold
	local rx, rz = Units.xzFromHeading(best.heading + 90)
	local crossM = (px * rx + pz * rz) / SPM
	local locDeg = math.deg(math.atan2(crossM, math.max(beforeM, 1)))
	local heightM = (pos.Y - l.y) / SPM - 3.9
	local gsDeg = math.deg(math.atan2(heightM, math.max(beforeM + 300, 1)))
	return {
		id = id, name = Airports.list[id :: string].name, distNm = distM * Units.NM_PER_M, bearing = bearing,
		ident = best.ident, beforeM = beforeM, locDeg = locDeg, gsDevDeg = gsDeg - 3, onApproach = beforeM > -200 and beforeM < 18000 and math.abs(locDeg) < 12,
	}
end

function Hud:update(t: any, destId: string?)
	local now = os.clock()
	self.toast.Visible = now < self.toastUntil
	self.card.Visible = now < self.cardUntil
	if not t or not t.ias then
		return
	end
	if not self.flight.Visible then
		return
	end

	-- speed
	self.ias.Text = string.format("%d", math.floor(t.ias + 0.5))
	self.gs.Text = string.format("GS %d", math.floor(t.gs + 0.5))
	local sp = t.speeds
	local flapIdx = math.clamp(math.floor(t.flapPos + 0.5), 1, #sp.flapLimits)
	local hint = ""
	if t.onGround and t.ias > 40 and t.ias < sp.rotate and t.throttle > 0.6 then
		hint = string.format("ROTATE AT %d", sp.rotate)
	elseif t.onGround and t.ias >= sp.rotate and t.throttle > 0.6 then
		hint = "ROTATE (S)"
	elseif not t.onGround and t.raFt < 3000 and t.gearExt > 0.9 and t.flapPos > 3.5 then
		hint = string.format("APPROACH %d", sp.approach)
	end
	self.speedHint.Text = hint
	local over = t.ias > sp.vmo or t.ias > sp.flapLimits[flapIdx] + 5
	self.ias.TextColor3 = if over then RED elseif (not t.onGround and t.stallWarning) then RED else WHITE

	-- altitude / vs / radio altitude
	self.alt.Text = fmtThousands(t.altFt)
	local vs = math.floor(t.vsFpm / 10 + 0.5) * 10
	self.vs.Text = string.format("%s%s fpm", if vs > 0 then "+" else "", fmtThousands(vs))
	self.vs.TextColor3 = if vs < -2000 and t.raFt < 2500 then RED else WHITE
	self.ra.Text = if t.raFt < 2500 then string.format("RA %s", fmtThousands(t.raFt)) else ""
	self.ra.TextColor3 = if t.raFt < 100 then AMBER else GREEN

	-- attitude
	self.adiHorizon.Rotation = -t.bank
	local pitchPx = math.clamp(t.pitch, -35, 35) * 4
	local br = math.rad(-t.bank)
	self.adiHorizon.Position = UDim2.new(0.5, -math.sin(br) * pitchPx, 0.5, math.cos(br) * pitchPx)

	-- heading & nav
	self.heading.Text = string.format("HDG %03d°", math.floor(t.heading + 0.5) % 360)
	local nav = navInfo(t, destId)
	local rel = ((nav.bearing - t.heading + 540) % 360) - 180
	self.navArrow.Rotation = rel
	self.nav.Text = string.format("%s %.1f nm  %03d°", nav.id, nav.distNm, math.floor(nav.bearing + 0.5) % 360)
	local etaMin = if t.gs > 30 then nav.distNm / t.gs * 60 else 0
	self.navSub.Text = string.format("%s  ·  RWY %s  ·  ETA %s", nav.name, nav.ident, if etaMin > 0 then string.format("%d:%02d", math.floor(etaMin), math.floor((etaMin % 1) * 60)) else "--")

	-- approach guidance (localizer/glideslope) inside 10 nm on an aligned approach
	local showApp = nav.onApproach and nav.distNm < 10 and not t.onGround
	self.loc.Visible = showApp
	self.gsBar.Visible = showApp and nav.beforeM > 0
	if showApp then
		local locX = math.clamp(nav.locDeg / 2.5, -1, 1) -- full scale 2.5 deg
		self.locDot.Position = UDim2.new(0.5 - locX * 0.5, 0, 0.5, 0)
		local gsY = math.clamp(nav.gsDevDeg / 0.7, -1, 1) -- full scale 0.7 deg
		self.gsDot.Position = UDim2.new(0.5, 0, 0.5 + gsY * 0.5, 0)
	end

	-- objective text
	local m = self.mission
	if m and m.text then
		self.objective.Text = m.text
	elseif m and m.mode == "sandbox" then
		self.objective.Text = "Crash sandbox: try failures from the menu (M). R resets instantly."
	else
		self.objective.Text = if t.onGround and t.gs < 2 and not t.n1[1].running then "Free flight: press I to start engines, P to release the brake" else "Free flight: explore, land anywhere for a grade"
	end

	-- engines
	local count = math.min(#t.n1, 4)
	if count ~= self.engineCount then
		self.engineCount = count
		local h, step = if count > 2 then 12 else 18, if count > 2 then 15 else 30
		for i, b in self.engineBars do
			local y = 24 + (i - 1) * step
			b.bg.Visible, b.text.Visible = i <= count, i <= count
			b.bg.Position, b.bg.Size = UDim2.fromOffset(12, y), UDim2.fromOffset(120, h)
			b.text.Position = UDim2.fromOffset(140, y + h / 2 - 9)
		end
	end
	for i, b in self.engineBars do
		local e = t.n1[i]
		if e then
			b.fill.Size = UDim2.fromScale(math.clamp(e.n1 / 100, 0, 1), 1)
			local status = if e.failed then "FAIL" elseif e.starting then "START" elseif e.running then string.format("%d%%", math.floor(e.n1 + 0.5)) else "OFF"
			if e.reverser > 0.1 then
				status ..= " REV"
			end
			b.text.Text = status
			b.fill.BackgroundColor3 = if e.failed then RED elseif e.starting then AMBER else GREEN
			b.text.TextColor3 = if e.failed then RED else WHITE
		end
	end
	self.throttle.Text = string.format("THR %3d%%", math.floor(t.throttle * 100 + 0.5))
	self.fuel.Text = string.format("FUEL %s kg  (%.1f kg/s)", fmtThousands(t.fuel), t.fuelFlow or 0)

	-- configuration
	self.flaps.Text = if t.flapCmd ~= t.flapLabel then string.format("FLAPS %s > %s", t.flapLabel, t.flapCmd) else string.format("FLAPS %s", t.flapLabel)
	local gearTxt, gearCol
	if t.gearExt >= 0.999 then
		gearTxt, gearCol = "GEAR DOWN", GREEN
	elseif t.gearExt <= 0.001 then
		gearTxt, gearCol = "GEAR UP", DIM
	else
		gearTxt, gearCol = "GEAR TRANSIT", AMBER
	end
	if t.failures and t.failures.gearStuck then
		gearTxt ..= " (STUCK)"
		gearCol = RED
	end
	self.gear.Text = gearTxt
	self.gear.TextColor3 = gearCol
	local brakeTxt = if t.parkingBrake then "PARK BRAKE" elseif t.brake > 0 then "BRAKES" else "BRAKES OFF"
	if t.speedbrake > 0.05 then
		brakeTxt ..= string.format("  SPDBRK %d%%", math.floor(t.speedbrake * 100))
	end
	self.brakes.Text = brakeTxt
	self.brakes.TextColor3 = if t.parkingBrake then AMBER else WHITE
	self.trim.Text = string.format("TRIM %+.2f   G %.2f", t.trim, t.gLoad)
	self.mode.Text = `{string.upper(t.assist or "easy")} (T to switch)`

	-- damage
	-- only parts that are hurt, worst first (in a fixed order), so it fits any aircraft
	local lines = {}
	local dmg = t.damage
	local names = {}
	for name, c in dmg.components do
		if c.state ~= "normal" or c.health < 0.995 then
			table.insert(names, name)
		end
	end
	table.sort(names, function(a, b)
		local ra, rb = Damage.STATE_RANK[dmg.components[a].state], Damage.STATE_RANK[dmg.components[b].state]
		if ra ~= rb then
			return ra > rb
		end
		return (DAMAGE_RANK[a] or 99) < (DAMAGE_RANK[b] or 99)
	end)
	if #names == 0 then
		table.insert(lines, '<font color="#5ad27a">All parts OK</font>')
	end
	for k, name in names do
		local c = dmg.components[name]
		if k > 9 then
			table.insert(lines, string.format("+%d more", #names - 9))
			break
		end
		if c then
			local col = damageColor(c.state)
			local hex = string.format("#%02x%02x%02x", math.floor(col.R * 255), math.floor(col.G * 255), math.floor(col.B * 255))
			local pct = if c.state == "detached" then "LOST" else string.format("%d%%", math.floor(c.health * 100 + 0.5))
			table.insert(lines, string.format('<font color="%s">%-13s %s</font>', hex, SHORT[name] or name, pct))
		end
	end
	self.damageList.Text = table.concat(lines, "\n")

	-- warnings
	local warn = ""
	local caution = ""
	if t.crashed then
		warn = "AIRCRAFT DESTROYED  ·  R TO RESET"
	elseif t.stall then
		warn = "STALL  ·  NOSE DOWN, ADD POWER"
	elseif t.stallWarning and math.floor(now * 4) % 2 == 0 then
		warn = "STALL"
	elseif not t.onGround and t.raFt < 1500 and t.vsFpm < -2500 then
		warn = "PULL UP"
	elseif t.ias > sp.vmo + 5 then
		warn = "OVERSPEED"
	end
	if not self.stunts and not t.onGround and t.raFt < 900 and t.gearExt < 0.99 and t.vsFpm < -300 then
		caution = "GEAR NOT DOWN"
	elseif t.ias > sp.flapLimits[flapIdx] + 5 and t.flapPos > 1.1 then
		caution = "FLAP OVERSPEED: RETRACT FLAPS (V)"
	elseif not t.onGround and t.gearExt > 0.5 and t.ias > sp.gearLimit then
		caution = "GEAR OVERSPEED"
	elseif (function()
		for _, e in t.n1 do
			if e.failed then
				return true
			end
		end
		return false
	end)() then
		caution = "ENGINE FAILURE"
	elseif t.fuel <= 0 then
		caution = "FUEL EXHAUSTED"
	elseif t.inWater then
		caution = "IN WATER"
	end
	self.warning.Text = warn
	self.caution.Text = caution

	-- touchdown flash
	local td = t.touchdownFlash
	if td and t.time - td.t < 5 then
		self.touchdown.Text = string.format("TOUCHDOWN %s fpm", fmtThousands(math.floor(td.vsFpm)))
		self.touchdown.TextColor3 = if td.vsFpm > -240 then GREEN elseif td.vsFpm > -600 then AMBER else RED
	else
		self.touchdown.Text = ""
	end

	if self.debug then
		local g = t.gears
		local gearLines = {}
		for i, gs in g do
			table.insert(gearLines, string.format("  %-13s %s comp %.2fm load %3dkN slip %+.1f", gs.cfg.name, if gs.onGround then "GND" else "air", gs.compression, math.floor(gs.load / 1000), gs.slip))
		end
		local w = t.wind or Vector3.zero
		self.debugText.Text = table.concat({
			string.format("IAS %.1f kt  TAS %.1f kt  GS %.1f kt", t.ias, t.tas, t.gs),
			string.format("ALT %.0f ft  AGL %.1f ft  VS %+.0f fpm", t.altFt, t.raFt, t.vsFpm),
			string.format("PITCH %+.2f  BANK %+.2f  HDG %.1f  TRK %.1f", t.pitch, t.bank, t.heading, t.track),
			string.format("AOA %+.2f  WING AOA %+.2f / stall %.1f  BETA %+.2f", t.aoa, t.wingAlpha, t.stallAlpha, t.beta),
			string.format("LIFT %.0f kN  DRAG %.0f kN  THRUST %.0f kN", t.lift / 1000, t.drag / 1000, t.thrust / 1000),
			string.format("LOAD %.2f g  STALL %s  WARN %s", t.gLoad, tostring(t.stall), tostring(t.stallWarning)),
			string.format("WIND %.1f %.1f %.1f m/s", w.X, w.Y, w.Z),
			string.format("GEAR ext %.2f  FLAPS %.2f  SPDBRK %.2f  TRIM %+.2f", t.gearExt, t.flapPos, t.speedbrake, t.trim),
			string.format("OWNER %s  FAULT %s  WHEELS %d", t.ownership, tostring(t.fault), t.wheels),
			"GEAR:",
			table.concat(gearLines, "\n"),
			string.format("DAMAGE overall %.0f%%  destroyed %s", Damage.overall(dmg) * 100, tostring(dmg.destroyed)),
			string.format("POS %.0f %.0f %.0f", t.position.X, t.position.Y, t.position.Z),
		}, "\n")
	end
end

return Hud
