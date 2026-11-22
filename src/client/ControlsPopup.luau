--!strict
-- "Controls" button (always on screen, top right) and the popup it opens. The list is
-- generated from Shared.Controls, so it always matches the real bindings.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controls = require(ReplicatedStorage:WaitForChild("Shared").Controls)

local ControlsPopup = {}
ControlsPopup.__index = ControlsPopup

local PANEL = Color3.fromRGB(14, 18, 26)
local ROW = Color3.fromRGB(26, 32, 44)
local KEY = Color3.fromRGB(143, 208, 255)
local WHITE = Color3.fromRGB(240, 244, 248)
local DIM = Color3.fromRGB(150, 160, 172)
local ACCENT = Color3.fromRGB(40, 120, 220)

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

function ControlsPopup.new()
	local self = setmetatable({}, ControlsPopup) :: any
	local gui = make("ScreenGui", {
		Name = "ControlsPopup", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 20,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	self.gui = gui

	local hotkey = Controls.firstKey("controls")
	local button = make("TextButton", {
		Parent = gui, Name = "ControlsButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromOffset(120, 32), BackgroundColor3 = PANEL, BackgroundTransparency = 0.15,
		Text = if hotkey then `Controls ({hotkey})` else "Controls", Font = Enum.Font.GothamBold,
		TextColor3 = WHITE, TextSize = 14, AutoButtonColor = true,
	})
	round(button, 8)
	button.Activated:Connect(function()
		self:toggle()
	end)

	local panel = make("Frame", {
		Parent = gui, Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 600, 0.8, 0), BackgroundColor3 = PANEL, BackgroundTransparency = 0.04, Visible = false,
	})
	round(panel, 12)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(600, 640)
	sizeLimit.MinSize = Vector2.new(320, 240)
	sizeLimit.Parent = panel
	self.panel = panel

	make("TextLabel", {
		Parent = panel, Text = "CONTROLS", Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -80, 0, 30),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextColor3 = WHITE, TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local close = make("TextButton", {
		Parent = panel, Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(32, 32), BackgroundColor3 = ACCENT, Font = Enum.Font.GothamBlack,
		TextColor3 = WHITE, TextSize = 16,
	})
	round(close, 6)
	close.Activated:Connect(function()
		self:hide()
	end)

	local list = make("ScrollingFrame", {
		Parent = panel, Position = UDim2.fromOffset(14, 54), Size = UDim2.new(1, -28, 1, -68),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local lastGroup = ""
	for _, r in Controls.rows() do
		if r.group ~= lastGroup then
			lastGroup = r.group
			make("TextLabel", {
				Parent = list, LayoutOrder = nextOrder(), Text = string.upper(r.group), Size = UDim2.new(1, -8, 0, 28),
				BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextColor3 = DIM, TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom,
			})
		end
		local row = make("Frame", { Parent = list, LayoutOrder = nextOrder(), Size = UDim2.new(1, -8, 0, 28), BackgroundColor3 = ROW })
		round(row, 6)
		make("TextLabel", {
			Parent = row, Text = r.keys, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.34, -10, 1, 0),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextColor3 = KEY, TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		make("TextLabel", {
			Parent = row, Text = r.label, Position = UDim2.new(0.34, 0, 0, 0), Size = UDim2.new(0.44, -6, 1, 0),
			BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextColor3 = WHITE, TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		make("TextLabel", {
			Parent = row, Text = r.gamepad, Position = UDim2.new(0.78, 0, 0, 0), Size = UDim2.new(0.22, -10, 1, 0),
			BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextColor3 = DIM, TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	return self
end

function ControlsPopup:isOpen(): boolean
	return self.panel.Visible
end

function ControlsPopup:show()
	self.panel.Visible = true
end

function ControlsPopup:hide()
	self.panel.Visible = false
end

function ControlsPopup:toggle()
	self.panel.Visible = not self.panel.Visible
end

return ControlsPopup
