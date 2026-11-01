--!strict
-- Gem shop HUD: shield count + boost timer, and a small panel to buy an
-- Anomaly Shield or a Bake Boost. Purchases are validated by the server (GemShop).

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

	local panel = Instance.new("Frame")
	panel.Name = "GemShopPanel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 214, 1, -58)
	panel.Size = UDim2.fromOffset(240, 120)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Parent = screen
	rounded(panel, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = SKY
	stroke.Thickness = 2
	stroke.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = panel

	local g = Config.Gems
	local shieldButton = textButton(panel, `🛡️ Anomaly Shield  💎{g.ShieldPrice}`, PINK, UDim2.new(0.92, 0, 0, 44))
	shieldButton.Name = "BuyShield"
	local boostButton = textButton(panel, `⚡ 2x Bake Boost ({g.BoostSeconds // 60}m)  💎{g.BoostPrice}`, PINK, UDim2.new(0.92, 0, 0, 44))
	boostButton.Name = "BuyBoost"

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
	shieldButton.Activated:Connect(function()
		buy:FireServer("Shield")
	end)
	boostButton.Activated:Connect(function()
		buy:FireServer("Boost")
	end)

	RunService.Heartbeat:Connect(function()
		local shields = (player:GetAttribute("ShieldCharges") :: number?) or 0
		local left = ((player:GetAttribute("BoostEndsAt") :: number?) or 0) - workspace:GetServerTimeNow()
		local boost = if left > 0 then string.format("⚡ %d:%02d", left // 60, math.floor(left % 60)) else "⚡ off"
		status.Text = `🛡️ x{shields}   {boost}`
	end)
end

return GemShop
