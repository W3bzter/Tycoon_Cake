--!strict
-- Build mode screens (UI/Build): the "🔨 Build" HUD toggle, the catalog panel
-- (buy items into your build inventory, pick one to place) and the action bar
-- above the hotbar (place / rotate / move / store / upgrade). Holds no game
-- state: BuildMode feeds it the latest BuildSync and calls SetMode.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local Config = require(Shared:WaitForChild("Config"))
local PlotLayout = require(Shared:WaitForChild("PlotLayout"))

local BuildMenu = {}

local DARK = Color3.fromRGB(30, 22, 18)
local CREAM = Color3.fromRGB(255, 240, 200)
local ORANGE = Color3.fromRGB(255, 150, 60)
local GREEN = Color3.fromRGB(70, 190, 110)
local BLUE = Color3.fromRGB(70, 140, 220)
local GREY = Color3.fromRGB(95, 85, 80)
local RED = Color3.fromRGB(220, 70, 70)

export type Handlers = {
	Toggle: () -> (),
	Buy: (id: string) -> (),
	Place: (id: string) -> (),
	Rotate: () -> (),
	Confirm: () -> (),
	Cancel: () -> (),
	Move: () -> (),
	Store: () -> (),
	Upgrade: (id: string) -> (),
}

export type SyncState = { Owned: { [string]: number }, Counts: { [string]: number }, Unlocked: { string } }

local function corner(inst: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

local function label(parent: Instance, text: string, size: UDim2, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color or CREAM
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, color: Color3, size: UDim2, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.Text = text
	b.Parent = parent
	corner(b, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 3)
	pad.Parent = b
	b.Activated:Connect(onClick)
	return b
end

-- Display name of a catalog item or a floor-button upgrade id.
function BuildMenu.NameOf(id: string): string
	local entry = BuildCatalog.Find(id)
	if entry then
		return entry.Name
	end
	for _, u in PlotLayout.Upgrades do
		if u.Id == id then
			return u.DisplayName
		end
	end
	return id
end

function BuildMenu.PriceText(entry: BuildCatalog.Entry, price: number): string
	return if entry.Currency == "Gems" then `💎{price}` else `${price}`
end

function BuildMenu.Mount(screen: ScreenGui, player: Player, h: Handlers)
	local menu = {}
	local state: SyncState = { Owned = {}, Counts = {}, Unlocked = {} }
	local tab = "Kitchen"

	local toggle = button(screen, "🔨 Build", ORANGE, UDim2.fromOffset(110, 34), h.Toggle)
	toggle.Name = "BuildToggle"
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 746, 1, -16)

	-- Catalog panel (right side)
	local panel = Instance.new("Frame")
	panel.Name = "BuildPanel"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -16, 0.45, 0)
	panel.Size = UDim2.new(0, 330, 0.62, 0)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Parent = screen
	corner(panel, 12)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(330, 480)
	limit.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = ORANGE
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

	local function unlocked(id: string): boolean
		return table.find(state.Unlocked, id) ~= nil
	end
	local function money(entry: BuildCatalog.Entry): number
		local stats = player:FindFirstChild("leaderstats")
		local value = stats and stats:FindFirstChild(if entry.Currency == "Gems" then "Gems" else "Cash")
		return if value and value:IsA("IntValue") then value.Value else 0
	end

	local function row(entry: BuildCatalog.Entry, order: number)
		local frame = Instance.new("Frame")
		frame.LayoutOrder = order
		frame.Size = UDim2.new(0.94, 0, 0, 62)
		frame.BackgroundColor3 = Color3.fromRGB(55, 42, 35)
		frame.Parent = list
		corner(frame, 8)
		local icon = label(frame, entry.Icon, UDim2.fromOffset(40, 40))
		icon.Position = UDim2.fromOffset(6, 11)
		icon.TextXAlignment = Enum.TextXAlignment.Center
		local name = label(frame, entry.Name, UDim2.new(1, -150, 0, 24))
		name.Position = UDim2.fromOffset(52, 6)
		local missing: { string } = {}
		for _, id in entry.Requires or {} do
			if not unlocked(id) then
				table.insert(missing, BuildMenu.NameOf(id))
			end
		end
		local count = state.Counts[entry.Id] or 0
		local inBag = state.Owned[entry.Id] or 0
		local info = if #missing > 0 then `🔒 Needs {table.concat(missing, ", ")}` else entry.Description
		local desc = label(frame, info, UDim2.new(1, -150, 0, 26), Color3.fromRGB(215, 195, 170))
		desc.Position = UDim2.fromOffset(52, 30)
		desc.TextWrapped = true

		local right = Instance.new("Frame")
		right.BackgroundTransparency = 1
		right.AnchorPoint = Vector2.new(1, 0.5)
		right.Position = UDim2.new(1, -6, 0.5, 0)
		right.Size = UDim2.fromOffset(92, 54)
		right.Parent = frame
		local stack = Instance.new("UIListLayout")
		stack.Padding = UDim.new(0, 4)
		stack.VerticalAlignment = Enum.VerticalAlignment.Center
		stack.Parent = right

		if entry.UpgradeOf then
			local note = label(right, `Select your {BuildMenu.NameOf(entry.UpgradeOf)} to upgrade`, UDim2.new(1, 0, 1, 0), Color3.fromRGB(215, 195, 170))
			note.TextWrapped = true
			note.TextXAlignment = Enum.TextXAlignment.Center
			return
		end
		if #missing == 0 and not (entry.Max and count >= entry.Max) then
			local price = BuildCatalog.PriceFor(entry, count)
			local afford = money(entry) >= price
			button(right, `Buy {BuildMenu.PriceText(entry, price)}`, if afford then GREEN else GREY, UDim2.new(1, 0, 0, 25), function()
				h.Buy(entry.Id)
			end)
		elseif entry.Max and count >= entry.Max and inBag == 0 then
			label(right, "✅ Owned", UDim2.new(1, 0, 0, 25)).TextXAlignment = Enum.TextXAlignment.Center
		end
		if inBag > 0 then
			button(right, `Place ({inBag})`, BLUE, UDim2.new(1, 0, 0, 25), function()
				h.Place(entry.Id)
			end)
		end
	end

	local tabButtons: { [string]: TextButton } = {}
	local function render()
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for name, b in tabButtons do
			b.BackgroundColor3 = if name == tab then ORANGE else GREY
		end
		for i, entry in BuildCatalog.List do
			if entry.Category == tab then
				-- Items waiting in your inventory float to the top.
				row(entry, if (state.Owned[entry.Id] or 0) > 0 then i else i + 1000)
			end
		end
	end
	for _, name in { "Kitchen", "Decor" } do
		tabButtons[name] = button(tabs, if name == "Kitchen" then "🍳 Kitchen" else "🌷 Decor", GREY, UDim2.fromOffset(110, 28), function()
			tab = name
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
	bar.BackgroundColor3 = DARK
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
			button(bar, "🔄 Rotate", BLUE, size, h.Rotate)
			button(bar, "✅ Place", GREEN, size, h.Confirm)
			button(bar, "✖ Cancel", RED, size, h.Cancel)
		elseif selected then
			local id = selected:GetAttribute("CatalogId") :: string
			hint(`{BuildMenu.NameOf(id)}`, 150)
			button(bar, "✋ Move", BLUE, size, h.Move)
			button(bar, "🔄 Rotate", BLUE, size, h.Rotate)
			button(bar, "📦 Store", GREY, size, h.Store)
			local nextEntry = BuildCatalog.NextUpgrade(id)
			if nextEntry then
				local ready = true
				for _, req in nextEntry.Requires or {} do
					ready = ready and unlocked(req)
				end
				local text = if ready then `⬆️ {nextEntry.Name} {BuildMenu.PriceText(nextEntry, nextEntry.Price)}` else `🔒 {nextEntry.Name}`
				button(bar, text, if ready then ORANGE else GREY, UDim2.fromOffset(190, 30), function()
					h.Upgrade(nextEntry.Id)
				end)
			end
			button(bar, "✖", RED, UDim2.fromOffset(34, 30), h.Cancel)
		else
			hint("Click an item to move it · B to leave", 290)
			button(bar, "Done", ORANGE, size, h.Toggle)
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

	function menu.Refresh(newState: SyncState)
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
