--!strict
-- Gem shop HUD: shield count + boost timer, and a small panel to buy an
-- Anomaly Shield or a Bake Boost. Purchases are validated by the server (GemShop).

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local GemShop = {}

local PINK = Color3.fromRGB(255, 105, 160)
local SKY = Color3.fromRGB(110, 180, 255)
local DARK = Color3.fromRGB(30, 22, 18)

local function rounded(inst: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = inst
end

local function textButton(parent: Instance, text: string, color: Color3, size: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	rounded(b, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = b
	return b
end

function GemShop.Mount(screen: ScreenGui, player: Player)
	local buy = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuyGemItem") :: RemoteEvent

	-- Status row above the Cash/Gems panel (which sits at bottom-left, 76px tall).
	local status = Instance.new("TextLabel")
	status.Name = "GemStatus"
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.new(0, 16, 1, -100)
	status.Size = UDim2.fromOffset(190, 30)
	status.BackgroundColor3 = DARK
	status.BackgroundTransparency = 0.25
	status.TextColor3 = Color3.fromRGB(255, 240, 200)
	status.Font = Enum.Font.FredokaOne
	status.TextScaled = true
	status.Parent = screen
	rounded(status, 8)

	local toggle = textButton(screen, "💎 Shop", SKY, UDim2.fromOffset(110, 34))
	toggle.Name = "GemShopToggle"
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 214, 1, -16)

	local panel = Instance.new("ScrollingFrame")
	panel.Name = "GemShopPanel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 214, 1, -58)
	panel.Size = UDim2.new(0, 300, 0.7, 0)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.1
	panel.ScrollBarThickness = 6
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.CanvasSize = UDim2.new()
	panel.Visible = false
	panel.Parent = screen
	rounded(panel, 12)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(300, 470)
	sizeLimit.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = SKY
	stroke.Thickness = 2
	stroke.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = panel

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function header(text: string)
		local h = Instance.new("TextLabel")
		h.LayoutOrder = nextOrder()
		h.Size = UDim2.new(0.92, 0, 0, 22)
		h.BackgroundTransparency = 1
		h.Font = Enum.Font.FredokaOne
		h.TextScaled = true
		h.TextColor3 = Color3.fromRGB(255, 240, 200)
		h.TextXAlignment = Enum.TextXAlignment.Left
		h.Text = text
		h.Parent = panel
	end

	-- Consumables
	header("⚡ Boosts")
	local g = Config.Gems
	local shieldButton = textButton(panel, `🛡️ Anomaly Shield  💎{g.ShieldPrice}`, PINK, UDim2.new(0.92, 0, 0, 38))
	shieldButton.Name = "BuyShield"
	shieldButton.LayoutOrder = nextOrder()
	local boostButton = textButton(panel, `⚡ 2x Bake Boost ({g.BoostSeconds // 60}m)  💎{g.BoostPrice}`, PINK, UDim2.new(0.92, 0, 0, 38))
	boostButton.Name = "BuyBoost"
	boostButton.LayoutOrder = nextOrder()
	shieldButton.Activated:Connect(function()
		buy:FireServer("Shield")
	end)
	boostButton.Activated:Connect(function()
		buy:FireServer("Boost")
	end)

	-- Levelled Gem upgrades
	header("💎 Gem Upgrades")
	local upgradeButtons: { [string]: TextButton } = {}
	for _, name in Config.GemUpgrades.Order do
		local b = textButton(panel, name, Color3.fromRGB(70, 140, 220), UDim2.new(0.92, 0, 0, 38))
		b.Name = "Upgrade" .. name
		b.LayoutOrder = nextOrder()
		b.Activated:Connect(function()
			buy:FireServer("Upgrade:" .. name)
		end)
		upgradeButtons[name] = b
	end
	local function refreshUpgrades()
		local levels: { [string]: number } = {}
		for name, lvl in string.gmatch((player:GetAttribute("GemUpgrades") :: string?) or "", "(%w+):(%d+)") do
			levels[name] = tonumber(lvl) or 0
		end
		for name, b in upgradeButtons do
			local def = Config.GemUpgrades[name]
			local level = levels[name] or 0
			local effect = string.format(def.Format, math.floor(level * def.PerLevel * 100 + 0.5))
			if level >= def.MaxLevel then
				b.Text = `{def.Icon} {def.DisplayName} MAX ({effect})`
			else
				local cost = math.floor(def.BaseCost * def.CostGrowth ^ level + 0.5)
				b.Text = `{def.Icon} {def.DisplayName} Lv{level}→{level + 1}  💎{cost}`
			end
		end
		-- Luck changes random roll odds: hidden where paid random items are restricted.
		upgradeButtons.Luck.Visible = player:GetAttribute("LuckAllowed") == true
	end
	player:GetAttributeChangedSignal("GemUpgrades"):Connect(refreshUpgrades)
	player:GetAttributeChangedSignal("LuckAllowed"):Connect(refreshUpgrades)
	refreshUpgrades()

	-- Storage upgrades (Cash)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local shopAction = remotes:WaitForChild("ShopAction") :: RemoteEvent
	header("📦 Storage ($ Cash)")
	local storageButtons: { [string]: TextButton } = {}
	for _, name in Config.Storage.Order do
		local b = textButton(panel, name, Color3.fromRGB(60, 160, 90), UDim2.new(0.92, 0, 0, 38))
		b.Name = "Storage" .. name
		b.LayoutOrder = nextOrder()
		b.Activated:Connect(function()
			shopAction:FireServer("storage", name)
		end)
		storageButtons[name] = b
	end
	local function refreshStorage()
		local levels: { [string]: number } = {}
		for name, lvl in string.gmatch((player:GetAttribute("Storage") :: string?) or "", "(%w+):(%d+)") do
			levels[name] = tonumber(lvl) or 0
		end
		for name, b in storageButtons do
			local def = Config.Storage[name]
			local level = levels[name] or 0
			if level >= def.MaxLevel then
				b.Text = `{def.Icon} {def.DisplayName} MAX ({string.format(def.Format, level * def.PerLevel)})`
			else
				local cost = math.floor(def.BaseCost * def.Growth ^ level + 0.5)
				b.Text = `{def.Icon} {def.DisplayName} Lv{level}→{level + 1}  ${cost}`
			end
		end
	end
	player:GetAttributeChangedSignal("Storage"):Connect(refreshStorage)
	refreshStorage()

	-- Game Passes (one-time Robux purchases)
	header("🎟️ Game Passes")
	local passPrompt = remotes:WaitForChild("GamePassPrompt") :: RemoteEvent
	for key, def in Config.GamePasses do
		local ready = def.Id ~= 0
		local b = textButton(panel, def.Label, if ready then Color3.fromRGB(0, 170, 110) else Color3.fromRGB(90, 90, 100), UDim2.new(0.92, 0, 0, 46))
		b.Name = "Pass" .. key
		b.LayoutOrder = nextOrder()
		local price = ""
		local function refreshPass()
			if player:GetAttribute(key) == true then
				b.Text = `{def.Label} ✅ OWNED\n{def.Description}`
				b.BackgroundColor3 = Color3.fromRGB(70, 120, 90)
			else
				b.Text = `{def.Label}{if ready then price else " (coming soon)"}\n{def.Description}`
			end
		end
		b.Activated:Connect(function()
			passPrompt:FireServer(key)
		end)
		player:GetAttributeChangedSignal(key):Connect(refreshPass)
		refreshPass()
		if ready then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(def.Id, Enum.InfoType.GamePass)
				end)
				if ok and info and info.PriceInRobux then
					price = `  R${info.PriceInRobux}`
					refreshPass()
				end
			end)
		end
	end

	-- Robux developer products (fixed amounts, never random)
	header("🛒 Robux Shop")
	for _, product in Config.Products do
		local ready = product.Id ~= 0
		local b = textButton(panel, if ready then product.Label else `{product.Label} (coming soon)`, if ready then Color3.fromRGB(0, 170, 110) else Color3.fromRGB(90, 90, 100), UDim2.new(0.92, 0, 0, 34))
		b.Name = "Product" .. product.Key
		b.LayoutOrder = nextOrder()
		b.AutoButtonColor = ready
		if ready then
			b.Activated:Connect(function()
				MarketplaceService:PromptProductPurchase(player, product.Id)
			end)
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(product.Id, Enum.InfoType.Product)
				end)
				if ok and info and info.PriceInRobux then
					b.Text = `{product.Label}  R${info.PriceInRobux}`
				end
			end)
		end
	end

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	RunService.Heartbeat:Connect(function()
		local shields = (player:GetAttribute("ShieldCharges") :: number?) or 0
		local left = ((player:GetAttribute("BoostEndsAt") :: number?) or 0) - workspace:GetServerTimeNow()
		local boost = if left > 0 then string.format("⚡ %d:%02d", left // 60, math.floor(left % 60)) else "⚡ off"
		status.Text = `🛡️ x{shields}   {boost}`
	end)
end

return GemShop
