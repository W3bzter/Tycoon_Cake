--!strict
-- Cash / Gems panel. Reads the server's leaderstats values, so no extra remote is needed.

local TweenService = game:GetService("TweenService")

local CurrencyDisplay = {}

local SUFFIXES = { { 1e15, "Q" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" } }

local function formatNumber(n: number): string
	-- Big numbers are abbreviated so they always fit the panel (1.25M, 1.00T).
	for _, entry in SUFFIXES do
		if n >= entry[1] then
			return string.format("%.2f%s", n / entry[1], entry[2])
		end
	end
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

local function makeRow(parent: Frame, order: number, color: Color3, prefix: string): TextLabel
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 34)
	label.BackgroundColor3 = Color3.fromRGB(30, 22, 18)
	label.BackgroundTransparency = 0.25
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 24
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = prefix .. "..."
	label.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.Parent = label
	return label
end

local function bind(label: TextLabel, value: IntValue, prefix: string)
	local baseSize = label.TextSize
	local function update()
		label.Text = prefix .. formatNumber(value.Value)
		label.TextSize = baseSize + 6
		TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Back), { TextSize = baseSize }):Play()
	end
	value.Changed:Connect(update)
	update()
end

function CurrencyDisplay.Mount(screen: ScreenGui, player: Player)
	local panel = Instance.new("Frame")
	panel.Name = "Currency"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 16, 1, -16) -- bottom-left, clear of the Roblox top bar
	panel.Size = UDim2.fromOffset(190, 76)
	panel.BackgroundTransparency = 1
	panel.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local cashLabel = makeRow(panel, 1, Color3.fromRGB(140, 255, 140), "$ ")
	local gemsLabel = makeRow(panel, 2, Color3.fromRGB(130, 210, 255), "Gems ")

	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats")
		bind(cashLabel, leaderstats:WaitForChild("Cash") :: IntValue, "$ ")
		bind(gemsLabel, leaderstats:WaitForChild("Gems") :: IntValue, "Gems ")
	end)
end

return CurrencyDisplay
