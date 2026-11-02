-- Client entry point: builds the HUD and wires server RemoteEvents to UI modules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UI = script.Parent:WaitForChild("UI")

local loadedUI: { [string]: any } = {} -- name -> running module (for the Studio ClientBridge)

-- A broken or missing UI module (e.g. a new file Script Sync hasn't copied into
-- Studio yet) must not take the whole HUD down: it's skipped with a warning and
-- replaced by a stub whose functions do nothing.
local function loadUI(folder: string, name: string): any
	local ok, result = pcall(function()
		local holder = UI:WaitForChild(folder, 15)
		local module = holder and holder:WaitForChild(name, 15)
		assert(module, `UI/{folder}/{name} is missing (has Script Sync copied it into Studio?)`)
		return require(module :: ModuleScript)
	end)
	if ok then
		loadedUI[name] = result
		return result
	end
	warn(`[ClientController] {folder}/{name} failed to load, skipping it: {result}`)
	return setmetatable({}, { __index = function()
		return function() end
	end })
end

-- Mounts one piece of UI; an error there is reported but the rest still loads.
local function safe(label: string, fn: (...any) -> ...any, ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(`[ClientController] {label} failed to start: {err}`)
	end
end

local AnomalyAlert = loadUI("HUD", "AnomalyAlert")
local Bag = loadUI("Panels", "Bag")
local RollReveal = loadUI("Effects", "RollReveal")
local MixGame = loadUI("Panels", "MixGame")
local CurrencyDisplay = loadUI("HUD", "CurrencyDisplay")
local GemShop = loadUI("Panels", "GemShop")
local InteractHighlighter = loadUI("HUD", "InteractHighlighter")
local RecipePreview = loadUI("HUD", "RecipePreview")
local Toast = loadUI("HUD", "Toast")
local WorldFX = loadUI("Effects", "WorldFX")
local WorldLabels = loadUI("Effects", "WorldLabels")
local RoofFade = loadUI("Effects", "RoofFade")
local Cutscene = loadUI("Effects", "Cutscene")
local Achievements = loadUI("Panels", "Achievements")
local Rebirth = loadUI("Panels", "Rebirth")
local ScreenShake = loadUI("Effects", "ScreenShake")
local Hotbar = loadUI("Hotbar", "Hotbar")
local BuildMode = loadUI("Build", "BuildMode")
local SettingsPanel = loadUI("Panels", "Settings")
local Clock = loadUI("HUD", "Clock")
local audioModule = UI:WaitForChild("Audio", 15)
local Audio = if audioModule then require(audioModule :: ModuleScript) :: any else nil

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

-- Studio-only rarity previews (visual only: DevTools.PreviewRoll).
for i, preview in { { "Void", "🕳️ Test Void" }, { "Celestial", "✨ Test Celestial" } } do
	local b = Instance.new("TextButton")
	b.Name = `DevPreview{preview[1]}`
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Position = UDim2.new(0.5, (i - 1.5) * 112, 0, 68)
	b.Size = UDim2.fromOffset(106, 24)
	b.BackgroundColor3 = if preview[1] == "Void" then Color3.fromRGB(70, 30, 120) else Color3.fromRGB(200, 190, 150)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.Text = preview[2]
	b.Visible = player:GetAttribute("StudioSession") == true
	b.Parent = screen
	Instance.new("UICorner").Parent = b
	player:GetAttributeChangedSignal("StudioSession"):Connect(function()
		b.Visible = player:GetAttribute("StudioSession") == true
	end)
	b.Activated:Connect(function()
		Remotes:WaitForChild("DevPreviewRoll"):FireServer(preview[1])
	end)
end

if Audio then
	safe("Audio", Audio.Mount, player)
	safe("Audio clicks", Audio.HookClicks, screen)
end
safe("CurrencyDisplay", CurrencyDisplay.Mount, screen, player)
safe("Toast", Toast.Mount, screen)
safe("AnomalyAlert", AnomalyAlert.Mount, screen)
safe("InteractHighlighter", InteractHighlighter.Mount, player)
safe("RecipePreview", RecipePreview.Mount, player)
safe("GemShop", GemShop.Mount, screen, player)
safe("Bag", Bag.Mount, screen, player)
safe("Achievements", Achievements.Mount, screen)
safe("Rebirth", Rebirth.Mount, screen, player)
safe("Hotbar", Hotbar.Mount, screen)
safe("BuildMode", BuildMode.Mount, screen)
safe("Settings", SettingsPanel.Mount, screen, player)
safe("Clock", Clock.Mount, screen)

-- Right-side button column: Build, Bag, Achievements, Rebirth, Settings (money and
-- the Gem shop stay bottom-left, the hotbar bottom-centre).
local sideBar = Instance.new("Frame")
sideBar.Name = "SideBar"
sideBar.AnchorPoint = Vector2.new(1, 0.5)
sideBar.Position = UDim2.new(1, -12, 0.5, 0)
sideBar.Size = UDim2.fromOffset(136, 0)
sideBar.AutomaticSize = Enum.AutomaticSize.Y
sideBar.BackgroundTransparency = 1
sideBar.Parent = screen
local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 8)
sideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.Parent = sideBar
for order, name in { "BuildToggle", "BagToggle", "AchievementsToggle", "RebirthToggle", "SettingsToggle" } do
	local b = screen:FindFirstChild(name)
	if b and b:IsA("GuiObject") then
		b.AnchorPoint = Vector2.zero
		b.Size = UDim2.fromOffset(130, 36)
		b.LayoutOrder = order
		b.Parent = sideBar
	end
end
-- Build mode takes the whole right side for its shop: the column steps aside
-- (BuildMenu sets the HUD's BuildActive attribute; the shop has its own close button).
screen:GetAttributeChangedSignal("BuildActive"):Connect(function()
	sideBar.Visible = screen:GetAttribute("BuildActive") ~= true
end)
safe("RollReveal", RollReveal.Mount, screen)
Remotes:WaitForChild("RollResult").OnClientEvent:Connect(RollReveal.Show)
safe("MixGame", MixGame.Mount, screen)
Remotes:WaitForChild("MixStart").OnClientEvent:Connect(MixGame.Play)

safe("WorldFX", WorldFX.Mount)
safe("WorldLabels", WorldLabels.Mount)
safe("RoofFade", RoofFade.Mount, screen)
Remotes:WaitForChild("ScreenShake").OnClientEvent:Connect(ScreenShake.Shake)

Remotes:WaitForChild("Notify").OnClientEvent:Connect(Toast.Show)
-- Anomaly intro cutscene first, then the alert banner.
safe("Cutscene", Cutscene.Mount, player)
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

-- Studio-only test hook (the client twin of ServerStorage.DebugBridge): calls into
-- the *running* UI modules, which a require() from MCP can't reach.
--   game.Players.LocalPlayer.PlayerScripts.ClientBridge:Invoke("BuildMode", "Toggle")
if game:GetService("RunService"):IsStudio() then
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "ClientBridge"
	bridge.OnInvoke = function(moduleName: string, method: string, ...)
		local module = loadedUI[moduleName]
		assert(module, `ClientBridge: unknown UI module {moduleName}`)
		local fn = module[method]
		assert(type(fn) == "function", `ClientBridge: {moduleName}.{method} is not a function`)
		return fn(...)
	end
	bridge.Parent = player:WaitForChild("PlayerScripts")
end
