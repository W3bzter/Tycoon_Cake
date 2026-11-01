--!strict
-- Ingredient Bag panel: every rolled ingredient (rarity colour, traits, value
-- factor), ★ pin (used first when mixing), 🗑 toss, the recipe the mixer should
-- make, and the current roll odds. All actions go through Remotes.BagAction and
-- are validated by the server (Inventory).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Bag = {}

local DARK = Color3.fromRGB(30, 22, 18)
local PINK = Color3.fromRGB(255, 105, 160)

local state = { Items = {}, Capacity = 40, MixRecipe = "Best" }
local action: RemoteEvent
local panel: Frame
local grid: ScrollingFrame
local title: TextLabel
local recipeButton: TextButton
local hudButton: TextButton
local oddsPanel: Frame
local oddsList: Frame

local function corner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function button(parent: Instance, text: string, color: Color3, size: UDim2, pos: UDim2?): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	if pos then
		b.Position = pos
	end
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.Text = text
	b.Parent = parent
	corner(b, 8)
	return b
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Text = text
	l.Parent = parent
	return l
end

local function recipeText(name: string): string
	if name == "Best" then
		return "🥣 Mix: Best recipe"
	end
	local cake = Recipes.Cakes[name]
	return `🥣 Mix: {cake and cake.Icon or ""} {name}`
end

local function renderOdds(player: Player)
	for _, child in oddsList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local luck = (player:GetAttribute("Luck") :: number?) or 0
	local odds = Rarity.Odds(luck)
	for i, tier in Rarity.Tiers do
		local row = label(oddsList, string.format("%s  %.2f%%  (x%s value)", tier.Name, odds[i], tostring(tier.Mult)), UDim2.new(1, 0, 0, 22), UDim2.new(), tier.Color)
		row.LayoutOrder = i
		row.TextXAlignment = Enum.TextXAlignment.Left
	end
	for j, name in Rarity.TraitOrder do
		local t = Rarity.Traits[name]
		local row = label(oddsList, string.format("%s %s  %.0f%%  (%s)", t.Icon, name, t.Chance * 100, t.Description), UDim2.new(1, 0, 0, 20), UDim2.new(), Color3.fromRGB(255, 240, 200))
		row.LayoutOrder = 10 + j
		row.TextXAlignment = Enum.TextXAlignment.Left
	end
	local note = label(oddsList, if luck > 0 then string.format("🍀 Luck +%d%% applied. Rolls are always free.", math.floor(luck * 100 + 0.5)) else "Rolls are always free.", UDim2.new(1, 0, 0, 18), UDim2.new(), Color3.fromRGB(200, 200, 210))
	note.LayoutOrder = 99
	note.TextXAlignment = Enum.TextXAlignment.Left
end

local function render()
	hudButton.Text = `🎒 Bag {#state.Items}/{state.Capacity}`
	title.Text = `🎒 Ingredient Bag  {#state.Items}/{state.Capacity}`
	recipeButton.Text = recipeText(state.MixRecipe)
	for _, child in grid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for order, item in state.Items do
		local tier = Rarity.Tiers[item.Rarity] or Rarity.Tiers[1]
		local cell = Instance.new("Frame")
		cell.LayoutOrder = order
		cell.BackgroundColor3 = tier.Color:Lerp(DARK, 0.7)
		cell.Parent = grid
		corner(cell, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Color = tier.Color
		stroke.Thickness = 2 + tier.Glow
		stroke.Parent = cell

		local info = Recipes.Ingredients[item.Type]
		label(cell, info and info.Icon or "❓", UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, 4))
		label(cell, item.Type, UDim2.new(1, -6, 0, 16), UDim2.fromOffset(3, 40))
		label(cell, tier.Name, UDim2.new(1, -6, 0, 16), UDim2.fromOffset(3, 57), tier.Color)
		local badges = ""
		for _, trait in item.Traits do
			badges ..= (Rarity.Traits[trait] and Rarity.Traits[trait].Icon or "")
		end
		label(cell, string.format("x%.1f %s", Rarity.Factor(item), badges), UDim2.new(1, -6, 0, 16), UDim2.fromOffset(3, 75), Color3.fromRGB(255, 240, 200))

		local pin = button(cell, if item.Pinned then "★" else "☆", if item.Pinned then Color3.fromRGB(255, 190, 40) else Color3.fromRGB(80, 70, 70), UDim2.fromOffset(22, 22), UDim2.fromOffset(3, 3))
		pin.Activated:Connect(function()
			action:FireServer("pin", item.Id)
		end)
		local toss = button(cell, "🗑", Color3.fromRGB(150, 60, 70), UDim2.fromOffset(22, 22), UDim2.new(1, -25, 0, 3))
		toss.Activated:Connect(function()
			action:FireServer("discard", item.Id)
		end)
	end
end

function Bag.Mount(screen: ScreenGui, player: Player)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	action = remotes:WaitForChild("BagAction") :: RemoteEvent

	hudButton = button(screen, "🎒 Bag", PINK, UDim2.fromOffset(130, 34))
	hudButton.Name = "BagToggle"
	hudButton.AnchorPoint = Vector2.new(0, 1)
	hudButton.Position = UDim2.new(0, 332, 1, -16)

	panel = Instance.new("Frame")
	panel.Name = "BagPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(560, 400)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.ZIndex = 5
	panel.Parent = screen
	corner(panel, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = PINK
	stroke.Thickness = 3
	stroke.Parent = panel
	local maxSize = Instance.new("UISizeConstraint")
	maxSize.MaxSize = Vector2.new(560, 400)
	maxSize.Parent = panel

	title = label(panel, "🎒 Ingredient Bag", UDim2.new(1, -60, 0, 30), UDim2.fromOffset(12, 8))
	title.TextXAlignment = Enum.TextXAlignment.Left
	local close = button(panel, "X", Color3.fromRGB(150, 60, 70), UDim2.fromOffset(34, 30), UDim2.new(1, -44, 0, 8))
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	recipeButton = button(panel, "🥣 Mix: Best recipe", Color3.fromRGB(70, 200, 160), UDim2.fromOffset(260, 30), UDim2.fromOffset(12, 44))
	recipeButton.Activated:Connect(function()
		-- Cycle Best -> each unlocked recipe -> Best.
		local options = { "Best" }
		for name in string.gmatch((player:GetAttribute("UnlockedRecipes") :: string?) or "Vanilla", "[^,]+") do
			table.insert(options, name)
		end
		local i = table.find(options, state.MixRecipe) or 1
		action:FireServer("recipe", options[(i % #options) + 1])
	end)
	local oddsButton = button(panel, "🎲 Odds", Color3.fromRGB(110, 180, 255), UDim2.fromOffset(110, 30), UDim2.fromOffset(282, 44))
	label(panel, "★ = use first", UDim2.fromOffset(140, 22), UDim2.fromOffset(402, 48), Color3.fromRGB(255, 220, 140))

	grid = Instance.new("ScrollingFrame")
	grid.Size = UDim2.new(1, -24, 1, -92)
	grid.Position = UDim2.fromOffset(12, 82)
	grid.BackgroundTransparency = 1
	grid.ScrollBarThickness = 6
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(98, 96)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	oddsPanel = Instance.new("Frame")
	oddsPanel.Name = "OddsPanel"
	oddsPanel.Size = UDim2.new(1, -24, 1, -92)
	oddsPanel.Position = UDim2.fromOffset(12, 82)
	oddsPanel.BackgroundColor3 = DARK
	oddsPanel.Visible = false
	oddsPanel.ZIndex = 6
	oddsPanel.Parent = panel
	corner(oddsPanel, 10)
	oddsList = Instance.new("Frame")
	oddsList.Size = UDim2.new(1, -16, 1, -16)
	oddsList.Position = UDim2.fromOffset(8, 8)
	oddsList.BackgroundTransparency = 1
	oddsList.Parent = oddsPanel
	local oddsLayout = Instance.new("UIListLayout")
	oddsLayout.Padding = UDim.new(0, 4)
	oddsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	oddsLayout.Parent = oddsList

	oddsButton.Activated:Connect(function()
		oddsPanel.Visible = not oddsPanel.Visible
		if oddsPanel.Visible then
			renderOdds(player)
		end
	end)
	hudButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
	player:GetAttributeChangedSignal("Luck"):Connect(function()
		if oddsPanel.Visible then
			renderOdds(player)
		end
	end)

	local bagUpdate = remotes:WaitForChild("BagUpdate") :: RemoteEvent
	bagUpdate.OnClientEvent:Connect(function(payload)
		state = payload
		render()
	end)
	render()
	-- The server's first BagUpdate may arrive before we were listening.
	action:FireServer("sync")
end

-- For tests.
function Bag.GetState()
	return state
end

return Bag
