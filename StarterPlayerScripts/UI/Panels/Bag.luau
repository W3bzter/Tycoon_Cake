--!strict
-- Ingredient Bag panel: every rolled ingredient (rarity colour, traits, value
-- factor), ★ pin (used first when mixing), 🗑 toss, the recipe the mixer should
-- make, and the current roll odds. All actions go through Remotes.BagAction and
-- are validated by the server (Inventory).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
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
local oddsList: ScrollingFrame

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
		local row = label(oddsList, string.format("%s  %s%%  (x%s value)", tier.Name, if odds[i] >= 0.1 then string.format("%.2f", odds[i]) else string.format("%.3f", odds[i]), tostring(tier.Mult)), UDim2.new(1, 0, 0, 20), UDim2.new(), tier.Color)
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
	note.LayoutOrder = 50
	note.TextXAlignment = Enum.TextXAlignment.Left

	-- Bake-time rolls: cake traits and mutations.
	local function row(text: string, color: Color3, order: number)
		local r = label(oddsList, text, UDim2.new(1, 0, 0, 18), UDim2.new(), color)
		r.LayoutOrder = order
		r.TextXAlignment = Enum.TextXAlignment.Left
	end
	row("🔥 When a cake finishes baking it can gain:", Color3.fromRGB(255, 200, 140), 60)
	for j, name in Rarity.CakeTraitOrder do
		local t = Rarity.CakeTraits[name]
		if t.Chance > 0 then
			row(string.format("%s %s  %.1f%%  (%s)", t.Icon, name, t.Chance * 100, t.Description), Color3.fromRGB(255, 240, 200), 60 + j)
		end
	end
	local rebirths = (player:GetAttribute("Rebirths") :: number?) or 0
	row(string.format("🧬 Mutation chance: %.1f%% for a Common cake, more for rarer ones (x3 during anomalies)", Rarity.MutationChance(1, { Rebirths = rebirths }) * 100), Color3.fromRGB(220, 180, 255), 80)
	for j, name in Rarity.MutationOrder do
		local m = Rarity.Mutations[name]
		row(`{m.Icon} {name}  x{m.Mult} value{if m.AnomalyOnly then " (only during anomalies)" else ""}`, m.Color:Lerp(Color3.new(1, 1, 1), 0.3), 80 + j)
	end
end

-- Mythic+ bag cards get a slowly turning shimmer on their border.
local shimmer: { UIGradient } = {}
RunService.RenderStepped:Connect(function(dt)
	for i = #shimmer, 1, -1 do
		local g = shimmer[i]
		if g.Parent == nil then
			table.remove(shimmer, i)
		else
			g.Rotation = (g.Rotation + dt * 120) % 360
		end
	end
end)

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
		if item.Rarity >= Rarity.MYTHIC then
			stroke.Color = Color3.new(1, 1, 1)
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, tier.Color),
				ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, tier.Color),
			})
			g.Parent = stroke
			table.insert(shimmer, g)
		end

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
	local deleteButton = button(panel, "🗑️ Auto-delete", Color3.fromRGB(190, 80, 90), UDim2.fromOffset(140, 30), UDim2.fromOffset(402, 44))

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
	oddsList = Instance.new("ScrollingFrame")
	oddsList.Size = UDim2.new(1, -16, 1, -16)
	oddsList.Position = UDim2.fromOffset(8, 8)
	oddsList.BackgroundTransparency = 1
	oddsList.ScrollBarThickness = 6
	oddsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	oddsList.CanvasSize = UDim2.new()
	oddsList.Parent = oddsPanel
	local oddsLayout = Instance.new("UIListLayout")
	oddsLayout.Padding = UDim.new(0, 4)
	oddsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	oddsLayout.Parent = oddsList

	-- Auto-delete settings: per kind, delete anything below a chosen rarity.
	local settingsRemote = remotes:WaitForChild("Settings") :: RemoteEvent
	local deletePanel = Instance.new("Frame")
	deletePanel.Name = "AutoDeletePanel"
	deletePanel.Size = UDim2.new(1, -24, 1, -92)
	deletePanel.Position = UDim2.fromOffset(12, 82)
	deletePanel.BackgroundColor3 = DARK
	deletePanel.Visible = false
	deletePanel.ZIndex = 6
	deletePanel.Parent = panel
	corner(deletePanel, 10)
	local intro = label(deletePanel, "Throw away anything BELOW the rarity you pick. Applies to new rolls, mixes and bakes.", UDim2.new(1, -16, 0, 36), UDim2.fromOffset(8, 6), Color3.fromRGB(255, 230, 200))
	intro.TextWrapped = true
	local rowButtons: { [string]: TextButton } = {}
	for i, kind in Config.AutoDelete.Kinds do
		label(deletePanel, Config.AutoDelete.Labels[kind], UDim2.fromOffset(170, 34), UDim2.fromOffset(8, 50 + (i - 1) * 44)).TextXAlignment = Enum.TextXAlignment.Left
		local b = button(deletePanel, "Off", Color3.fromRGB(80, 70, 70), UDim2.fromOffset(300, 34), UDim2.fromOffset(190, 50 + (i - 1) * 44))
		b.Activated:Connect(function()
			local current = 0
			for k, n in string.gmatch((player:GetAttribute("AutoDelete") :: string?) or "", "(%w+):(%d+)") do
				if k == kind then
					current = tonumber(n) or 0
				end
			end
			-- Off -> below Uncommon (2) -> ... -> below the top tier -> Off
			local nextValue = if current == 0 then 2 else current + 1
			if nextValue > #Rarity.Tiers then
				nextValue = 0
			end
			settingsRemote:FireServer("autodelete", kind, nextValue)
		end)
		rowButtons[kind] = b
	end
	local keepButton = button(deletePanel, "", Color3.fromRGB(70, 160, 120), UDim2.new(1, -16, 0, 34), UDim2.fromOffset(8, 190))
	keepButton.Activated:Connect(function()
		settingsRemote:FireServer("keepspecial", player:GetAttribute("KeepSpecial") ~= true)
	end)
	local function renderSettings()
		local values: { [string]: number } = {}
		for k, n in string.gmatch((player:GetAttribute("AutoDelete") :: string?) or "", "(%w+):(%d+)") do
			values[k] = tonumber(n) or 0
		end
		for kind, b in rowButtons do
			local n = values[kind] or 0
			if n <= 0 then
				b.Text = "Off (keep everything)"
				b.BackgroundColor3 = Color3.fromRGB(80, 70, 70)
			else
				local tier = Rarity.Tiers[n]
				b.Text = `Delete below {tier.Name}`
				b.BackgroundColor3 = tier.Color:Lerp(DARK, 0.45)
			end
		end
		local keep = player:GetAttribute("KeepSpecial") == true
		keepButton.Text = if keep then "✅ Keep anything with traits or mutations" else "⬜ Keep anything with traits or mutations"
		keepButton.BackgroundColor3 = if keep then Color3.fromRGB(70, 160, 120) else Color3.fromRGB(80, 70, 70)
		local anyOn = false
		for _, n in values do
			anyOn = anyOn or n > 0
		end
		deleteButton.Text = if anyOn then "🗑️ Auto-delete ON" else "🗑️ Auto-delete"
	end
	player:GetAttributeChangedSignal("AutoDelete"):Connect(renderSettings)
	player:GetAttributeChangedSignal("KeepSpecial"):Connect(renderSettings)
	renderSettings()
	deleteButton.Activated:Connect(function()
		deletePanel.Visible = not deletePanel.Visible
		oddsPanel.Visible = false
	end)

	oddsButton.Activated:Connect(function()
		oddsPanel.Visible = not oddsPanel.Visible
		deletePanel.Visible = false
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
