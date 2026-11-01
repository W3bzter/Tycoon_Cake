--!strict
-- Anomaly alert: red screen flash plus a warning banner with a live countdown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local AnomalyAlert = {}

local flash: Frame
local banner: Frame
local title: TextLabel
local description: TextLabel
local countdown: TextLabel
local countdownConn: RBXScriptConnection? = nil

local function text(parent: Instance, name: string, size: number, color: Color3, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, size + 6)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = size
	label.TextColor3 = color
	label.TextWrapped = true
	label.Parent = parent
	return label
end

function AnomalyAlert.Mount(screen: ScreenGui)
	flash = Instance.new("Frame")
	flash.Name = "AnomalyFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.fromRGB(255, 30, 30)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 10
	flash.Active = false
	flash.Parent = screen

	banner = Instance.new("Frame")
	banner.Name = "AnomalyBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 70)
	banner.Size = UDim2.new(0.9, 0, 0, 0)
	banner.AutomaticSize = Enum.AutomaticSize.Y
	banner.BackgroundColor3 = Color3.fromRGB(40, 0, 0)
	banner.BackgroundTransparency = 0.15
	banner.Visible = false
	banner.ZIndex = 11
	banner.Parent = screen

	local maxSize = Instance.new("UISizeConstraint")
	maxSize.MaxSize = Vector2.new(560, math.huge)
	maxSize.Parent = banner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = banner
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 70, 70)
	stroke.Thickness = 3
	stroke.Parent = banner
	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(pad :: any)[side] = UDim.new(0, 10)
	end
	pad.Parent = banner
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = banner

	title = text(banner, "Title", 30, Color3.fromRGB(255, 90, 90), 1)
	description = text(banner, "Description", 18, Color3.fromRGB(255, 230, 230), 2)
	description.AutomaticSize = Enum.AutomaticSize.Y
	countdown = text(banner, "Countdown", 22, Color3.fromRGB(255, 220, 120), 3)
	for _, label in { title, description, countdown } do
		label.ZIndex = 12
	end
end

local function pulseFlash()
	local up = TweenInfo.new(0.12)
	local down = TweenInfo.new(0.35)
	for _ = 1, 3 do
		TweenService:Create(flash, up, { BackgroundTransparency = 0.45 }):Play()
		task.wait(0.12)
		TweenService:Create(flash, down, { BackgroundTransparency = 1 }):Play()
		task.wait(0.35)
	end
end

function AnomalyAlert.Show(name: string, endsAt: number)
	local info = Config.Anomalies[name]
	title.Text = "!! " .. (if info then info.DisplayName else name) .. " !!"
	description.Text = if info then info.Description else ""
	banner.Visible = true
	task.spawn(pulseFlash)

	if countdownConn then
		countdownConn:Disconnect()
	end
	countdownConn = RunService.Heartbeat:Connect(function()
		local remaining = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
		countdown.Text = `Ends in {remaining}s`
	end)
end

function AnomalyAlert.Hide(_name: string?)
	if countdownConn then
		countdownConn:Disconnect()
		countdownConn = nil
	end
	banner.Visible = false
	flash.BackgroundTransparency = 1
end

return AnomalyAlert
