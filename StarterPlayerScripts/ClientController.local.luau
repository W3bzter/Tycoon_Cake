-- Client entry point: builds the HUD and wires server RemoteEvents to UI modules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UI = script.Parent:WaitForChild("UI")

local AnomalyAlert = require(UI:WaitForChild("HUD"):WaitForChild("AnomalyAlert"))
local Bag = require(UI:WaitForChild("Panels"):WaitForChild("Bag"))
local RollReveal = require(UI:WaitForChild("Effects"):WaitForChild("RollReveal"))
local MixGame = require(UI:WaitForChild("Panels"):WaitForChild("MixGame"))
local ButtonPrices = require(UI:WaitForChild("HUD"):WaitForChild("ButtonPrices"))
local CurrencyDisplay = require(UI:WaitForChild("HUD"):WaitForChild("CurrencyDisplay"))
local GemShop = require(UI:WaitForChild("Panels"):WaitForChild("GemShop"))
local InteractHighlighter = require(UI:WaitForChild("HUD"):WaitForChild("InteractHighlighter"))
local RecipePreview = require(UI:WaitForChild("HUD"):WaitForChild("RecipePreview"))
local Toast = require(UI:WaitForChild("HUD"):WaitForChild("Toast"))
local WorldFX = require(UI:WaitForChild("Effects"):WaitForChild("WorldFX"))
local Cutscene = require(UI:WaitForChild("Effects"):WaitForChild("Cutscene"))
local Achievements = require(UI:WaitForChild("Panels"):WaitForChild("Achievements"))
local Rebirth = require(UI:WaitForChild("Panels"):WaitForChild("Rebirth"))
local ScreenShake = require(UI:WaitForChild("Effects"):WaitForChild("ScreenShake"))
local Hotbar = require(UI:WaitForChild("Hotbar"):WaitForChild("Hotbar"))
local BuildMode = require(UI:WaitForChild("Build"):WaitForChild("BuildMode"))

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

-- Studio-only "reset my data" button (two clicks to confirm).
local resetButton = Instance.new("TextButton")
resetButton.Name = "DevResetButton"
resetButton.AnchorPoint = Vector2.new(0.5, 0)
resetButton.Position = UDim2.new(0.5, 0, 0, 38)
resetButton.Size = UDim2.fromOffset(220, 26)
resetButton.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
resetButton.TextColor3 = Color3.new(1, 1, 1)
resetButton.Font = Enum.Font.FredokaOne
resetButton.TextScaled = true
resetButton.Text = "🔄 Reset my data"
resetButton.Visible = player:GetAttribute("StudioSession") == true
resetButton.Parent = screen
Instance.new("UICorner").Parent = resetButton
player:GetAttributeChangedSignal("StudioSession"):Connect(function()
	resetButton.Visible = player:GetAttribute("StudioSession") == true
end)
local armedUntil = 0
resetButton.Activated:Connect(function()
	if os.clock() < armedUntil then
		armedUntil = 0
		resetButton.Text = "🔄 Reset my data"
		Remotes:WaitForChild("DevResetData"):FireServer()
	else
		armedUntil = os.clock() + 3
		resetButton.Text = "⚠️ Click again to confirm"
		task.delay(3, function()
			if os.clock() >= armedUntil then
				resetButton.Text = "🔄 Reset my data"
			end
		end)
	end
end)

CurrencyDisplay.Mount(screen, player)
Toast.Mount(screen)
AnomalyAlert.Mount(screen)
InteractHighlighter.Mount(player)
ButtonPrices.Mount(player)
RecipePreview.Mount(player)
GemShop.Mount(screen, player)
Bag.Mount(screen, player)
Achievements.Mount(screen)
Rebirth.Mount(screen, player)
Hotbar.Mount(screen)
BuildMode.Mount(screen)
RollReveal.Mount(screen)
Remotes:WaitForChild("RollResult").OnClientEvent:Connect(RollReveal.Show)
MixGame.Mount(screen)
Remotes:WaitForChild("MixStart").OnClientEvent:Connect(MixGame.Play)

WorldFX.Mount()
Remotes:WaitForChild("ScreenShake").OnClientEvent:Connect(ScreenShake.Shake)

Remotes:WaitForChild("Notify").OnClientEvent:Connect(Toast.Show)
-- Anomaly intro cutscene first, then the alert banner.
Cutscene.Mount(player)
Remotes:WaitForChild("Cutscene").OnClientEvent:Connect(Cutscene.Play)
Remotes:WaitForChild("AnomalyStarted").OnClientEvent:Connect(function(name: string, duration: number)
	local endsAt = workspace:GetServerTimeNow() + duration
	task.wait(0.3) -- the cutscene (if this anomaly reaches us) starts right after
	while Cutscene.IsPlaying() do
		task.wait(0.1)
	end
	if ReplicatedStorage:GetAttribute("ActiveAnomaly") == name then
		AnomalyAlert.Show(name, endsAt)
	end
end)
Remotes:WaitForChild("AnomalyEnded").OnClientEvent:Connect(AnomalyAlert.Hide)

-- Joined mid-anomaly: the server mirrors the active one in attributes.
local active = ReplicatedStorage:GetAttribute("ActiveAnomaly")
local endsAt = ReplicatedStorage:GetAttribute("AnomalyEndsAt")
if active and endsAt then
	AnomalyAlert.Show(active, endsAt)
end
