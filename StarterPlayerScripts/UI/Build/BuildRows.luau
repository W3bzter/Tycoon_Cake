--!strict
-- Shared widgets for the Build shop (UI/Build/BuildMenu) and one row builder per
-- kind of shop entry: placeable catalog items (Shared/BuildCatalog) and fixed
-- upgrades (Shared/PlotLayout, the "Upgrades" tab).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local PlotLayout = require(Shared:WaitForChild("PlotLayout"))

local BuildRows = {}

BuildRows.Colors = {
	Dark = Color3.fromRGB(30, 22, 18),
	Cream = Color3.fromRGB(255, 240, 200),
	Muted = Color3.fromRGB(215, 195, 170),
	Orange = Color3.fromRGB(255, 150, 60),
	Green = Color3.fromRGB(70, 190, 110),
	Blue = Color3.fromRGB(70, 140, 220),
	Grey = Color3.fromRGB(95, 85, 80),
	Red = Color3.fromRGB(220, 70, 70),
	Row = Color3.fromRGB(55, 42, 35),
}
local C = BuildRows.Colors

export type SyncState = { Owned: { [string]: number }, Counts: { [string]: number }, Unlocked: { string } }

-- What a row needs from the menu: current state, money, and the actions.
export type Context = {
	State: SyncState,
	Money: (currency: string?) -> number,
	Buy: (id: string) -> (),
	Place: (id: string) -> (),
	BuyUpgrade: (id: string) -> (),
}

function BuildRows.Corner(inst: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

function BuildRows.Label(parent: Instance, text: string, size: UDim2, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color or C.Cream
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

function BuildRows.Button(parent: Instance, text: string, color: Color3, size: UDim2, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.Text = text
	b.Parent = parent
	BuildRows.Corner(b, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 3)
	pad.Parent = b
	b.Activated:Connect(onClick)
	return b
end

-- Display name of a catalog item or a fixed upgrade id.
function BuildRows.NameOf(id: string): string
	local entry = BuildCatalog.Find(id)
	if entry then
		return entry.Name
	end
	local upgrade = PlotLayout.Find(id)
	return if upgrade then upgrade.DisplayName else id
end

function BuildRows.PriceText(currency: string?, price: number): string
	return if currency == "Gems" then `💎{price}` else `${price}`
end

-- One line saying what a fixed upgrade does (PlotLayout has no descriptions).
local function describe(upgrade: PlotLayout.Upgrade): string
	local parts = {}
	for key, value in upgrade.Effects or {} do
		if key == "BakeTime" then
			table.insert(parts, `Bakes {math.round((1 - value) * 100)}% faster`)
		elseif key == "CustomerRate" then
			table.insert(parts, `Customers {math.round((1 / value - 1) * 100)}% more often`)
		elseif key == "SalePrice" then
			table.insert(parts, `+{math.round((value - 1) * 100)}% cake prices`)
		elseif key == "VIPChance" then
			table.insert(parts, `+{math.round(value * 100)}% VIP customers`)
		elseif key == "StorageSlots" then
			table.insert(parts, `+{value} storage slots`)
		end
	end
	if #parts > 0 then
		return table.concat(parts, ", ")
	elseif string.sub(upgrade.Id, 1, 6) == "Recipe" then
		return "Unlocks a new cake to bake."
	elseif upgrade.Category == "Auto" then
		return "Automation: bakes and sells for you."
	elseif upgrade.Category == "Build" then
		return "Builds onto your bakery."
	end
	return "A fixed upgrade for your bakery."
end

local function missingFor(ctx: Context, requires: { string }?): { string }
	local missing = {}
	for _, id in requires or {} do
		if not table.find(ctx.State.Unlocked, id) then
			table.insert(missing, BuildRows.NameOf(id))
		end
	end
	return missing
end

-- The common row frame: icon, name, a one-line description and a right-hand stack.
local function rowFrame(parent: Instance, order: number, icon: string, name: string, info: string): Frame
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.new(0.94, 0, 0, 62)
	frame.BackgroundColor3 = C.Row
	frame.Parent = parent
	BuildRows.Corner(frame, 8)
	local iconLabel = BuildRows.Label(frame, icon, UDim2.fromOffset(40, 40))
	iconLabel.Position = UDim2.fromOffset(6, 11)
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	BuildRows.Label(frame, name, UDim2.new(1, -150, 0, 24)).Position = UDim2.fromOffset(52, 6)
	local desc = BuildRows.Label(frame, info, UDim2.new(1, -150, 0, 26), C.Muted)
	desc.Position = UDim2.fromOffset(52, 30)
	desc.TextWrapped = true

	local right = Instance.new("Frame")
	right.Name = "Right"
	right.BackgroundTransparency = 1
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Position = UDim2.new(1, -6, 0.5, 0)
	right.Size = UDim2.fromOffset(92, 54)
	right.Parent = frame
	local stack = Instance.new("UIListLayout")
	stack.Padding = UDim.new(0, 4)
	stack.VerticalAlignment = Enum.VerticalAlignment.Center
	stack.Parent = right
	return frame
end

local function centred(right: Instance, text: string, height: number, color: Color3?)
	local l = BuildRows.Label(right, text, UDim2.new(1, 0, 0, height), color)
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextWrapped = true
end

-- A placeable catalog item: Buy (into your build inventory) and Place (n).
function BuildRows.Catalog(parent: Instance, order: number, entry: BuildCatalog.Entry, ctx: Context)
	local missing = missingFor(ctx, entry.Requires)
	local count = ctx.State.Counts[entry.Id] or 0
	local inBag = ctx.State.Owned[entry.Id] or 0
	local info = if #missing > 0 then `🔒 Needs {table.concat(missing, ", ")}` else entry.Description
	local right = rowFrame(parent, order, entry.Icon, entry.Name, info):FindFirstChild("Right") :: Frame

	if entry.UpgradeOf then
		centred(right, `Select your {BuildRows.NameOf(entry.UpgradeOf)} to upgrade`, 54, C.Muted)
		return
	end
	local maxed = entry.Max ~= nil and count >= entry.Max
	if #missing == 0 and not maxed then
		local price = BuildCatalog.PriceFor(entry, count)
		local afford = ctx.Money(entry.Currency) >= price
		BuildRows.Button(right, `Buy {BuildRows.PriceText(entry.Currency, price)}`, if afford then C.Green else C.Grey, UDim2.new(1, 0, 0, 25), function()
			ctx.Buy(entry.Id)
		end)
	elseif maxed and inBag == 0 then
		centred(right, "✅ Owned", 25)
	end
	if inBag > 0 then
		BuildRows.Button(right, `Place ({inBag})`, C.Blue, UDim2.new(1, 0, 0, 25), function()
			ctx.Place(entry.Id)
		end)
	end
end

-- A fixed upgrade (Upgrades tab): one Buy button, then "Owned".
function BuildRows.Upgrade(parent: Instance, order: number, upgrade: PlotLayout.Upgrade, ctx: Context)
	local owned = table.find(ctx.State.Unlocked, upgrade.Id) ~= nil
	local missing = missingFor(ctx, upgrade.Requires)
	local info = if not owned and #missing > 0 then `🔒 Needs {table.concat(missing, ", ")}` else describe(upgrade)
	local right = rowFrame(parent, order, upgrade.Icon, upgrade.DisplayName, info):FindFirstChild("Right") :: Frame
	if owned then
		centred(right, "✅ Owned", 25)
	elseif #missing == 0 then
		local afford = ctx.Money(upgrade.Currency) >= upgrade.Price
		BuildRows.Button(right, `Buy {BuildRows.PriceText(upgrade.Currency, upgrade.Price)}`, if afford then C.Green else C.Grey, UDim2.new(1, 0, 0, 25), function()
			ctx.BuyUpgrade(upgrade.Id)
		end)
	else
		centred(right, BuildRows.PriceText(upgrade.Currency, upgrade.Price), 25, C.Muted)
	end
end

return BuildRows
