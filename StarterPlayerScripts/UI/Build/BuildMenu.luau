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
local Config = require(Shared:WaitForChild("Config"))
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

	-- Shop panel (right side)
	local panel = Instance.new("Frame")
	panel.Name = "BuildPanel"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -16, 0.45, 0)
	panel.Size = UDim2.new(0, 360, 0.62, 0)
	panel.BackgroundColor3 = C.Dark
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Parent = screen
	corner(panel, 12)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(360, 500)
	limit.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Orange
	stroke.Thickness = 2
	stroke.Parent = panel
	label(panel, "  🔨 Build Shop", UDim2.new(1, 0, 0, 30))

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
		tabButtons[t[1]] = button(tabs, t[2], C.Grey, UDim2.fromOffset(108, 28), function()
			tab = t[1]
			render()
		end)
	end

	-- Action bar (above the hotbar)
	local bar = Instance.new("Frame")
	bar.Name = "BuildActionBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -(Config.Hotbar.BottomOffset + Config.Hotbar.SlotSize + 16))
	bar.Size = UDim2.fromOffset(0, 40)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundColor3 = C.Dark
	bar.BackgroundTransparency = 0.15
	bar.Visible = false
	bar.Parent = screen
	corner(bar, 10)
	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barLayout.Padding = UDim.new(0, 6)
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.Parent = bar
	local barPad = Instance.new("UIPadding")
	barPad.PaddingLeft = UDim.new(0, 8)
	barPad.PaddingRight = UDim.new(0, 8)
	barPad.Parent = bar

	local function hint(text: string, width: number)
		local l = label(bar, text, UDim2.fromOffset(width, 22))
		l.TextXAlignment = Enum.TextXAlignment.Center
	end

	-- mode: "idle" | "place" | "move". selected: the clicked placed model (idle only).
	function menu.SetMode(mode: string, selected: Model?)
		for _, child in bar:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local size = UDim2.fromOffset(96, 30)
		if mode == "place" or mode == "move" then
			hint("Click to place · R rotate · right-click cancel", 330)
			button(bar, "🔄 Rotate", C.Blue, size, h.Rotate)
			button(bar, "✅ Place", C.Green, size, h.Confirm)
			button(bar, "✖ Cancel", C.Red, size, h.Cancel)
		elseif selected then
			local id = selected:GetAttribute("CatalogId") :: string
			hint(BuildRows.NameOf(id), 150)
			button(bar, "✋ Move", C.Blue, size, h.Move)
			button(bar, "🔄 Rotate", C.Blue, size, h.Rotate)
			button(bar, "📦 Store", C.Grey, size, h.Store)
			local nextEntry = BuildCatalog.NextUpgrade(id)
			if nextEntry then
				local ready = true
				for _, req in nextEntry.Requires or {} do
					ready = ready and table.find(state.Unlocked, req) ~= nil
				end
				local text = if ready then `⬆️ {nextEntry.Name} {BuildRows.PriceText(nextEntry.Currency, nextEntry.Price)}` else `🔒 {nextEntry.Name}`
				button(bar, text, if ready then C.Orange else C.Grey, UDim2.fromOffset(190, 30), function()
					h.Upgrade(nextEntry.Id)
				end)
			end
			button(bar, "✖", C.Red, UDim2.fromOffset(34, 30), h.Cancel)
		else
			hint("Click an item to move it · B to leave", 290)
			button(bar, "Done", C.Orange, size, h.Toggle)
		end
	end

	function menu.SetActive(active: boolean)
		panel.Visible = active
		bar.Visible = active
		toggle.Text = if active then "✖ Close" else "🔨 Build"
		if active then
			render()
		end
	end

	function menu.Refresh(newState: BuildRows.SyncState)
		state = newState
		if panel.Visible then
			render()
		end
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
