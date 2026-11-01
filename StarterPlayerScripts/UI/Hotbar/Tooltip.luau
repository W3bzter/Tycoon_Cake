--!strict
-- Hover card for hotbar items: name, rarity, value, mix quality, traits (with
-- what they do) and mutation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))
local ItemIcon = require(script.Parent:WaitForChild("ItemIcon"))

local Tooltip = {}

local frame: Frame
local list: Frame
local stroke: UIStroke

local function line(text: string, color: Color3, size: number, order: number)
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.new(1, 0, 0, size)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = color
	l.Text = text
	l.Parent = list
end

function Tooltip.Mount(parent: Instance)
	frame = Instance.new("Frame")
	frame.Name = "HotbarTooltip"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Size = UDim2.fromOffset(240, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Color3.fromRGB(40, 28, 36)
	frame.BackgroundTransparency = 0.05
	frame.Visible = false
	frame.ZIndex = 30
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = frame
	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(pad :: any)[side] = UDim.new(0, 10)
	end
	pad.Parent = frame
	list = Instance.new("Frame")
	list.Size = UDim2.fromScale(1, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
end

-- Shows the card for `tool` above the screen point `at` (pixels).
function Tooltip.Show(tool: Tool, at: Vector2)
	for _, child in list:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local info = ItemIcon.Describe(tool)
	local color = ItemIcon.Color(info)
	stroke.Color = color
	line(info.Name, Color3.new(1, 1, 1), 18, 1)
	local cake = info.Cake
	if cake then
		local tier = Rarity.Tiers[cake.Rarity] or Rarity.Tiers[1]
		line(`{tier.Name}  •  ${cake.Value}`, tier.Color, 16, 2)
		line(`🥣 {cake.Quality} mix{if cake.Fresh then "  🌿 Fresh" else ""}{if cake.Anomaly then "  👁️ Anomaly" else ""}`, Color3.fromRGB(230, 220, 210), 14, 3)
		for i, name in cake.Traits or {} do
			local t = Rarity.CakeTraits[name]
			if t then
				line(`{t.Icon} {name}: {t.Description}`, Color3.fromRGB(255, 235, 190), 14, 10 + i)
			end
		end
		if cake.Mutation and Rarity.Mutations[cake.Mutation] then
			local m = Rarity.Mutations[cake.Mutation]
			line(`{m.Icon} {cake.Mutation} mutation  (x{m.Mult} value)`, m.Color:Lerp(Color3.new(1, 1, 1), 0.3), 15, 30)
		end
	else
		line(if info.Kind == "FryingPan" then "Click to whack anomaly creatures!" elseif info.Kind == "FireExtinguisher" then "Click near an overheating oven!" else "", Color3.fromRGB(230, 220, 210), 14, 2)
	end
	frame.Position = UDim2.fromOffset(at.X, at.Y - 8)
	frame.Visible = true
end

function Tooltip.Hide()
	frame.Visible = false
end

return Tooltip
