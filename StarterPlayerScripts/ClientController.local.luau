-- Client entry point: builds the HUD and wires server RemoteEvents to UI modules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UI = script.Parent:WaitForChild("UI")

local AnomalyAlert = require(UI:WaitForChild("AnomalyAlert"))
local ButtonPrices = require(UI:WaitForChild("ButtonPrices"))
local CurrencyDisplay = require(UI:WaitForChild("CurrencyDisplay"))
local GemShop = require(UI:WaitForChild("GemShop"))
local InteractHighlighter = require(UI:WaitForChild("InteractHighlighter"))
local RecipePreview = require(UI:WaitForChild("RecipePreview"))
local Toast = require(UI:WaitForChild("Toast"))

local screen = Instance.new("ScreenGui")
screen.Name = "BakeryHUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true -- lets the anomaly flash cover the whole screen
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = player:WaitForChild("PlayerGui")

-- Studio-only DevMode marker (the server sets this attribute only inside Studio).
local devTag = Instance.new("TextLabel")
devTag.Name = "DevModeTag"
devTag.AnchorPoint = Vector2.new(0.5, 0)
devTag.Position = UDim2.new(0.5, 0, 0, 8)
devTag.Size = UDim2.fromOffset(220, 26)
devTag.BackgroundColor3 = Color3.fromRGB(255, 70, 90)
devTag.TextColor3 = Color3.new(1, 1, 1)
devTag.Font = Enum.Font.FredokaOne
devTag.TextScaled = true
devTag.Text = "🛠️ DEV MODE (Studio only)"
devTag.Visible = player:GetAttribute("DevMode") == true
devTag.Parent = screen
Instance.new("UICorner").Parent = devTag
player:GetAttributeChangedSignal("DevMode"):Connect(function()
	devTag.Visible = player:GetAttribute("DevMode") == true
end)

CurrencyDisplay.Mount(screen, player)
Toast.Mount(screen)
AnomalyAlert.Mount(screen)
InteractHighlighter.Mount(player)
ButtonPrices.Mount(player)
RecipePreview.Mount(player)
GemShop.Mount(screen, player)

Remotes:WaitForChild("Notify").OnClientEvent:Connect(Toast.Show)
Remotes:WaitForChild("AnomalyStarted").OnClientEvent:Connect(function(name: string, duration: number)
	AnomalyAlert.Show(name, workspace:GetServerTimeNow() + duration)
end)
Remotes:WaitForChild("AnomalyEnded").OnClientEvent:Connect(AnomalyAlert.Hide)

-- Joined mid-anomaly: the server mirrors the active one in attributes.
local active = ReplicatedStorage:GetAttribute("ActiveAnomaly")
local endsAt = ReplicatedStorage:GetAttribute("AnomalyEndsAt")
if active and endsAt then
	AnomalyAlert.Show(active, endsAt)
end
