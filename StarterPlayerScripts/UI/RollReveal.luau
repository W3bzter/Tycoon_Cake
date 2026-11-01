--!strict
-- Roll reveal: one card per rolled ingredient. Each card flickers through rarity
-- colours, then lands on its result (staggered), with a glow for rare+ and a
-- bigger flash for Legendary / Mythic. Purely visual: the server already put the
-- items in the bag.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local RollReveal = {}

local container: Frame
local token = 0

local function card(parent: Instance, item: any, order: number): (Frame, TextLabel, TextLabel, UIStroke)
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.fromOffset(92, 112)
	frame.BackgroundColor3 = Color3.fromRGB(30, 22, 30)
	frame.BackgroundTransparency = 0.1
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = frame

	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(1, 0, 0, 46)
	icon.Position = UDim2.fromOffset(0, 6)
	icon.BackgroundTransparency = 1
	icon.TextScaled = true
	icon.Text = Recipes.Ingredients[item.Type] and Recipes.Ingredients[item.Type].Icon or "❓"
	icon.Parent = frame

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -8, 0, 20)
	name.Position = UDim2.fromOffset(4, 54)
	name.BackgroundTransparency = 1
	name.TextScaled = true
	name.Font = Enum.Font.FredokaOne
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Text = item.Type
	name.Parent = frame

	local rarity = Instance.new("TextLabel")
	rarity.Size = UDim2.new(1, -8, 0, 30)
	rarity.Position = UDim2.fromOffset(4, 76)
	rarity.BackgroundTransparency = 1
	rarity.TextScaled = true
	rarity.Font = Enum.Font.FredokaOne
	rarity.Text = "?"
	rarity.Parent = frame
	return frame, rarity, name, stroke
end

function RollReveal.Mount(screen: ScreenGui)
	container = Instance.new("Frame")
	container.Name = "RollReveal"
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.42)
	container.Size = UDim2.fromOffset(700, 130)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.ZIndex = 20
	container.Parent = screen
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container
end

function RollReveal.Show(items: { any })
	token += 1
	local mine = token
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	container.Visible = true

	local best = 1
	for i, item in items do
		local frame, rarityLabel, _, stroke = card(container, item, i)
		frame.Size = UDim2.fromOffset(0, 112)
		TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(92, 112) }):Play()
		best = math.max(best, item.Rarity)
		task.spawn(function()
			-- Flicker through random rarities, then land (later cards land later).
			local flickers = 6 + i * 2
			for f = 1, flickers do
				if mine ~= token then
					return
				end
				local tier = Rarity.Tiers[math.random(#Rarity.Tiers)]
				stroke.Color = tier.Color
				rarityLabel.TextColor3 = tier.Color
				rarityLabel.Text = tier.Name
				task.wait(0.04 + f * 0.006)
			end
			local tier = Rarity.Tiers[item.Rarity]
			stroke.Color = tier.Color
			stroke.Thickness = 3 + tier.Glow * 1.5
			rarityLabel.TextColor3 = tier.Color
			local badges = ""
			for _, trait in item.Traits do
				badges ..= (Rarity.Traits[trait] and Rarity.Traits[trait].Icon or "")
			end
			rarityLabel.Text = tier.Name .. (if badges ~= "" then " " .. badges else "")
			frame.BackgroundColor3 = tier.Color:Lerp(Color3.fromRGB(30, 22, 30), 0.75)
			if item.Deleted then -- auto-deleted by the player's settings: never reached the bag
				rarityLabel.Text = "🗑️ " .. rarityLabel.Text
				frame.BackgroundTransparency = 0.6
				stroke.Transparency = 0.6
				return
			end
			if tier.Glow >= 2 then
				TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 2, true), { Size = UDim2.fromOffset(104, 124) }):Play()
			end
		end)
	end

	task.delay(3.2, function()
		if mine == token then
			container.Visible = false
		end
	end)
	return best
end

return RollReveal
