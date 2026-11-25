--!strict
-- The HUD's Events button (top right, or J) and its menu: failures that break parts
-- and weather hazards (tornado, lightning, birds, strong winds). Each button calls
-- onTrigger(id); HazardController does the rest.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Hazards = require(Shared.Hazards)
local Controls = require(Shared.Controls)

local HazardPanel = {}
HazardPanel.__index = HazardPanel

local PANEL = Color3.fromRGB(14, 18, 26)
local FAIL = Color3.fromRGB(150, 52, 46)
local WEATHER = Color3.fromRGB(44, 92, 150)
local NEUTRAL = Color3.fromRGB(52, 58, 72)
local FIX = Color3.fromRGB(46, 130, 70)
local WHITE = Color3.fromRGB(240, 244, 248)
local DIM = Color3.fromRGB(160, 170, 182)

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

function HazardPanel.new(onTrigger: (string) -> ())
	local self = setmetatable({}, HazardPanel) :: any
	self.flying = false
	self.open = false
	local gui = make("ScreenGui", {
		Name = "HazardPanel", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 6,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	self.gui = gui

	-- Button in the top-right row, left of "Buttons (U)" and "Controls (K)".
	local key = Controls.firstKey("events")
	local button = make("TextButton", {
		Parent = gui, Name = "EventsButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -258, 0, 8),
		Size = UDim2.fromOffset(130, 32), BackgroundColor3 = FAIL, BackgroundTransparency = 0.1,
		Text = if key then `! Events ({key})` else "! Events", Font = Enum.Font.GothamBold, TextColor3 = WHITE,
		TextSize = 14, Visible = false, AutoButtonColor = true,
	})
	round(button, 8)
	button.Activated:Connect(function()
		self:toggle()
	end)
	self.button = button

	-- "Fix all" sits left of the Events button: repairs everything, puts broken parts back.
	local fixKey = Controls.firstKey("fixAll")
	local fixButton = make("TextButton", {
		Parent = gui, Name = "FixAllButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -396, 0, 8),
		Size = UDim2.fromOffset(130, 32), BackgroundColor3 = FIX, BackgroundTransparency = 0.1,
		Text = if fixKey then `Fix all ({fixKey})` else "Fix all", Font = Enum.Font.GothamBold, TextColor3 = WHITE,
		TextSize = 14, Visible = false, AutoButtonColor = true,
	})
	round(fixButton, 8)
	fixButton.Activated:Connect(function()
		onTrigger("fixall")
	end)
	self.fixButton = fixButton

	-- Menu: drops down on the right, left of the minimap.
	local panel = make("Frame", {
		Parent = gui, Name = "Panel", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -228, 0, 48),
		Size = UDim2.fromOffset(300, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = PANEL, BackgroundTransparency = 0.08, Visible = false,
	})
	round(panel, 10)
	make("UIPadding", {
		Parent = panel, PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
	})
	make("UIListLayout", { Parent = panel, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) })
	self.panel = panel

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function heading(text: string)
		make("TextLabel", {
			Parent = panel, LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1,
			Text = text, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left,
		})
	end
	local function grid(): Frame
		local g = make("Frame", {
			Parent = panel, LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		})
		make("UIGridLayout", {
			Parent = g, CellSize = UDim2.new(0.5, -3, 0, 38), CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		return g
	end
	local function eventButton(parent: Instance, id: string, text: string, color: Color3, hint: string?)
		local b = make("TextButton", {
			Parent = parent, Name = id, LayoutOrder = nextOrder(), BackgroundColor3 = color, Text = text,
			Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = WHITE, TextWrapped = true, AutoButtonColor = true,
		})
		round(b, 7)
		b.Activated:Connect(function()
			onTrigger(id)
		end)
		if hint then
			b.MouseEnter:Connect(function()
				self.hint.Text = hint
			end)
		end
	end

	local top = make("Frame", { Parent = panel, LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 })
	make("TextLabel", {
		Parent = top, Size = UDim2.new(1, -30, 1, 0), BackgroundTransparency = 1, Text = "FAILURES & WEATHER",
		Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left,
	})
	local close = make("TextButton", {
		Parent = top, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = NEUTRAL, Text = "X", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = WHITE,
	})
	round(close, 6)
	close.Activated:Connect(function()
		self:setOpen(false)
	end)

	local fixg = grid()
	eventButton(fixg, "fixall", "Fix all damage", FIX, "Repairs everything: dents, bends, failures and parts that broke off")
	heading("FAILURES (break parts, change how it flies)")
	local fg = grid()
	for _, f in Hazards.FAILURES do
		eventButton(fg, f.id, f.label, FAIL, f.hint)
	end
	heading("WEATHER & HAZARDS")
	local wg = grid()
	for _, w in Hazards.WEATHER do
		eventButton(wg, w.id, w.label, WEATHER, w.hint)
	end
	local mg = grid()
	eventButton(mg, "random", "Random failure", FAIL, "Something random breaks")
	eventButton(mg, "clear", "Clear weather", NEUTRAL, "Ends the tornado, winds and birds. Damage stays until you fix it (Y) or reset (R)")

	self.hint = make("TextLabel", {
		Parent = panel, LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1,
		Text = "Hover a button to see what it does. R resets the aircraft.", Font = Enum.Font.GothamMedium,
		TextSize = 12, TextColor3 = DIM, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	self.status = make("TextLabel", {
		Parent = panel, LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1,
		Text = "", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.fromRGB(255, 200, 90),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	return self
end

function HazardPanel:setOpen(on: boolean)
	self.open = on and self.flying
	self.panel.Visible = self.open
end

function HazardPanel:toggle()
	self:setOpen(not self.open)
end

function HazardPanel:setFlying(on: boolean)
	self.flying = on
	self.button.Visible = on
	self.fixButton.Visible = on
	if not on then
		self:setOpen(false)
	end
end

function HazardPanel:setStatus(text: string)
	if self.open then
		self.status.Text = text
	end
end

return HazardPanel
