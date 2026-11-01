--!strict
-- Build mode screens (UI/Build): the "🔨 Build" HUD toggle, the Build shop panel
-- (Kitchen / Decor: buy items into your build inventory and pick one to place;
-- Upgrades: fixed upgrades like the building, recipes, oven upgrades) and the
-- action bar above the hotbar (place / rotate / move / store / upgrade). Holds no
-- game state: BuildMode feeds it the latest BuildSync and calls SetMode.
-- Rows and widgets: UI/Build/BuildRows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local PlotLayout = require(Shared:WaitForChild("PlotLayout"))
local BuildRows = require(script.Parent:WaitForChild("BuildRows"))

local BuildMenu = {}

local C = BuildRows.Colors
local label, button, corner = BuildRows.Label, BuildRows.Button, BuildRows.Corner

export type Handlers = {
	Toggle: () -> (),
	Buy: (id: string) -> (),
	BuyUpgrade: (id: string) -> (),
	Place: (id: string) -> (),
	Rotate: () -> (),
	Confirm: () -> (),
	Cancel: () -> (),
	Move: () -> (),
	Store: () -> (),
	Upgrade: (id: string) -> (),
}

local TABS = { { "Kitchen", "🍳 Kitchen" }, { "Decor", "🌷 Decor" }, { "Upgrades", "⭐ Upgrades" } }
local PANEL_TOP = 54 -- pixels from the top of the screen: just under the clock
BuildMenu.PanelTop = PANEL_TOP

function BuildMenu.Mount(screen: ScreenGui, player: Player, h: Handlers)
	local menu = {}
	local state: BuildRows.SyncState = { Owned = {}, Counts = {}, Unlocked = {} }
	local tab = "Kitchen"

	local function money(currency: string?): number
		local stats = player:FindFirstChild("leaderstats")
		local value = stats and stats:FindFirstChild(if currency == "Gems" then "Gems" else "Cash")
		return if value and value:IsA("IntValue") then value.Value else 0
	end

	local toggle = button(screen, "🔨 Build", C.Orange, UDim2.fromOffset(110, 34), h.Toggle)
	toggle.Name = "BuildToggle"
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 746, 1, -16)

	-- Shop panel: the whole right side, top to bottom. While Build mode is on the
	-- side button column and the hotbar hide (HUD attribute BuildActive) to make room.
	local panel = Instance.new("Frame")
	panel.Name = "BuildPanel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, PANEL_TOP)
	panel.Size = UDim2.new(0.36, 0, 1, -(PANEL_TOP + 16))
	panel.BackgroundColor3 = C.Dark
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Parent = screen
	corner(panel, 12)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(330, 200)
	limit.MaxSize = Vector2.new(480, 760)
	limit.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Orange
	stroke.Thickness = 2
	stroke.Parent = panel
	label(panel, "  🔨 Build Shop", UDim2.new(1, 0, 0, 30))
	local close = button(panel, "✖", C.Red, UDim2.fromOffset(30, 26), h.Toggle)
	close.Name = "CloseButton"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -6, 0, 3)

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(8, 32)
	tabs.Size = UDim2.new(1, -16, 0, 30)
	tabs.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabs

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(0, 68)
	list.Size = UDim2.new(1, 0, 1, -74)
	list.BackgroundTransparency = 1
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local ctx: BuildRows.Context = {
		State = state,
		Money = money,
		Buy = h.Buy,
		Place = h.Place,
		BuyUpgrade = h.BuyUpgrade,
	}

	local tabButtons: { [string]: TextButton } = {}
	local function render()
		ctx.State = state
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for name, b in tabButtons do
			b.BackgroundColor3 = if name == tab then C.Orange else C.Grey
		end
		if tab == "Upgrades" then
			-- Buyable first, then locked, then owned (each in list order).
			for i, upgrade in PlotLayout.Upgrades do
				local owned = table.find(state.Unlocked, upgrade.Id) ~= nil
				local ready = true
				for _, req in upgrade.Requires or {} do
					ready = ready and table.find(state.Unlocked, req) ~= nil
				end
				BuildRows.Upgrade(list, i + (if owned then 2000 elseif ready then 0 else 1000), upgrade, ctx)
			end
			return
		end
		for i, entry in BuildCatalog.List do
			if entry.Category == tab then
				-- Items waiting in your inventory float to the top.
				BuildRows.Catalog(list, if (state.Owned[entry.Id] or 0) > 0 then i else i + 1000, entry, ctx)
			end
		end
	end
	for _, t in TABS do
		tabButtons[t[1]] = button(tabs, t[2], C.Grey, UDim2.new(1 / 3, -4, 0, 28), function()
			tab = t[1]
			render()
		end)
	end

	-- Hint bar above the hotbar: one line of help + at most three buttons, so it
	-- stays narrow (it used to carry the upgrade button too and ran under the shop).
	local bar = Instance.new("Frame")
	bar.Name = "BuildActionBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -16) -- the hotbar is hidden in Build mode
	bar.Size = UDim2.fromOffset(0, 0)
	bar.AutomaticSize = Enum.AutomaticSize.XY
	bar.BackgroundColor3 = C.Dark
	bar.BackgroundTransparency = 0.15
	bar.Visible = false
	bar.Parent = screen
	corner(bar, 10)
	local barLayout = Instance.new("UIListLayout")
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	barLayout.Padding = UDim.new(0, 4)
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.Parent = bar
	local barPad = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(barPad :: any)[side] = UDim.new(0, 6)
	end
	barPad.Parent = bar
	local barButtons = Instance.new("Frame")
	barButtons.BackgroundTransparency = 1
	barButtons.AutomaticSize = Enum.AutomaticSize.XY
	barButtons.LayoutOrder = 2
	barButtons.Parent = bar
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = barButtons
	local hintLabel = label(bar, "", UDim2.fromOffset(300, 20))
	hintLabel.LayoutOrder = 1
	hintLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- Selection card (left side, clear of the shop panel, the side bar, the
	-- currency panel and the hotbar): the selected item's upgrade + actions.
	local card = Instance.new("Frame")
	card.Name = "BuildSelectionCard"
	card.AnchorPoint = Vector2.new(0, 0.5)
	card.Position = UDim2.new(0, 16, 0.4, 0)
	card.Size = UDim2.fromOffset(250, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = C.Dark
	card.BackgroundTransparency = 0.1
	card.Visible = false
	card.Parent = screen
	corner(card, 12)
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = C.Orange
	cardStroke.Thickness = 2
	cardStroke.Parent = card
	local cardLayout = Instance.new("UIListLayout")
	cardLayout.Padding = UDim.new(0, 6)
	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardLayout.Parent = card
	local cardPad = barPad:Clone()
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(cardPad :: any)[side] = UDim.new(0, 10)
	end
	cardPad.Parent = card

	local function clear(frame: Instance)
		for _, child in frame:GetChildren() do
			if child:IsA("GuiObject") and child ~= hintLabel and child ~= barButtons then
				child:Destroy()
			end
		end
	end

	local active = false
	local currentMode = "idle"
	local currentSelected: Model? = nil

	-- mode: "idle" | "place" | "move". selected: the clicked placed model (idle only).
	function menu.SetMode(mode: string, selected: Model?)
		currentMode, currentSelected = mode, selected
		clear(barButtons)
		clear(card)
		local size = UDim2.fromOffset(96, 30)
		local placing = mode == "place" or mode == "move"
		-- The shop only shows while you're browsing (not placing, nothing selected).
		panel.Visible = active and not placing and selected == nil
		card.Visible = active and not placing and selected ~= nil
		bar.Visible = active and selected == nil
		-- Centred in the free gap between the bottom-left money buttons and the shop.
		local gem = screen:FindFirstChild("GemShopToggle") :: GuiObject?
		local left = if gem and gem.Visible then gem.AbsolutePosition.X + gem.AbsoluteSize.X + 16 else 0
		local right = if panel.Visible then panel.AbsolutePosition.X - 16 else screen.AbsoluteSize.X
		bar.Position = UDim2.new(0, (left + right) / 2, 1, -16)
		if placing then
			hintLabel.Text = "Click to place · R rotate · right-click cancel"
			button(barButtons, "🔄 Rotate", C.Blue, size, h.Rotate)
			button(barButtons, "✅ Place", C.Green, size, h.Confirm)
			button(barButtons, "✖ Cancel", C.Red, size, h.Cancel)
		elseif selected then
			local id = selected:GetAttribute("CatalogId") :: string
			local title = label(card, BuildRows.NameOf(id), UDim2.new(1, 0, 0, 26))
			title.LayoutOrder = 1
			title.TextXAlignment = Enum.TextXAlignment.Center
			local nextEntry = BuildCatalog.NextUpgrade(id)
			if nextEntry then
				local missing = {}
				for _, req in nextEntry.Requires or {} do
					if not table.find(state.Unlocked, req) then
						table.insert(missing, BuildRows.NameOf(req))
					end
				end
				local ready = #missing == 0
				local text = if ready
					then `⬆️ {nextEntry.Name}  {BuildRows.PriceText(nextEntry.Currency, nextEntry.Price)}`
					else `🔒 {nextEntry.Name}: needs {table.concat(missing, ", ")}`
				local up = button(card, text, if ready then C.Orange else C.Grey, UDim2.new(1, 0, 0, 40), function()
					h.Upgrade(nextEntry.Id)
				end)
				up.Name = "UpgradeButton"
				up.LayoutOrder = 2
			end
			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, 30)
			row.LayoutOrder = 3
			row.Parent = card
			local grid = Instance.new("UIGridLayout")
			grid.CellSize = UDim2.new(1 / 3, -4, 1, 0)
			grid.CellPadding = UDim2.fromOffset(6, 0)
			grid.Parent = row
			button(row, "✋ Move", C.Blue, size, h.Move)
			button(row, "🔄 Rotate", C.Blue, size, h.Rotate)
			button(row, "📦 Store", C.Grey, size, h.Store)
			local close = button(card, "✖ Deselect", C.Red, UDim2.new(1, 0, 0, 28), h.Cancel)
			close.LayoutOrder = 4
		else
			hintLabel.Text = "Click an item to move or upgrade it · B to leave"
			button(barButtons, "Done", C.Orange, size, h.Toggle)
		end
	end

	function menu.SetActive(isActive: boolean)
		active = isActive
		screen:SetAttribute("BuildActive", isActive) -- Hotbar and the side column step aside
		toggle.Text = if active then "✖ Close" else "🔨 Build"
		if not active then
			panel.Visible, card.Visible, bar.Visible = false, false, false
			return
		end
		render()
		menu.SetMode(currentMode, currentSelected)
	end

	function menu.Refresh(newState: BuildRows.SyncState)
		state = newState
		if panel.Visible then
			render()
		end
		-- (BuildMode re-selects an upgraded item and calls SetMode again.)
	end

	-- Prices turn green/grey as money changes.
	task.spawn(function()
		local stats = player:WaitForChild("leaderstats")
		for _, name in { "Cash", "Gems" } do
			local value = stats:WaitForChild(name) :: IntValue
			value.Changed:Connect(function()
				if panel.Visible then
					render()
				end
			end)
		end
	end)

	menu.SetMode("idle", nil)
	return menu
end

return BuildMenu
