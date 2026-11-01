--!strict
-- Achievements panel (progress bars, rewards) and the unlock popup.
-- Data: Remotes.AchievementSync ({Stats, Unlocked}); popups: AchievementUnlocked(id).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Defs = require(Shared:WaitForChild("Achievements"))

local Achievements = {}

local DARK = Color3.fromRGB(30, 22, 18)
local GOLD = Color3.fromRGB(255, 200, 60)

local state = { Stats = {} :: { [string]: number }, Unlocked = {} :: { [string]: number } }
local panel: Frame
local list: ScrollingFrame
local title: TextLabel
local hudButton: TextButton
local popup: Frame
local popupQueue: { string } = {}
local showingPopup = false

local function corner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

local function fmt(n: number): string
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

local function render()
	local done = 0
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, def in Defs.List do
		local unlocked = state.Unlocked[def.Id] ~= nil
		if unlocked then
			done += 1
		end
		local value = math.min(state.Stats[def.Stat] or 0, def.Goal)
		local row = Instance.new("Frame")
		row.LayoutOrder = (if unlocked then 1000 else 0) + i -- unfinished first
		row.Size = UDim2.new(1, -8, 0, 54)
		row.BackgroundColor3 = if unlocked then Color3.fromRGB(60, 50, 20) else Color3.fromRGB(45, 36, 32)
		row.Parent = list
		corner(row, 10)
		label(row, def.Icon, UDim2.fromOffset(40, 40), UDim2.fromOffset(6, 7))
		label(row, def.Name .. (if unlocked then "  ✅" else ""), UDim2.new(1, -150, 0, 20), UDim2.fromOffset(52, 4), if unlocked then GOLD else Color3.new(1, 1, 1))
		label(row, def.Description, UDim2.new(1, -150, 0, 14), UDim2.fromOffset(52, 24), Color3.fromRGB(220, 210, 200))
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, -150, 0, 8)
		bar.Position = UDim2.fromOffset(52, 41)
		bar.BackgroundColor3 = Color3.fromRGB(20, 15, 12)
		bar.Parent = row
		corner(bar, 4)
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(value / def.Goal, 1)
		fill.BackgroundColor3 = if unlocked then GOLD else Color3.fromRGB(110, 200, 255)
		fill.Parent = bar
		corner(fill, 4)
		local right = label(row, if def.Stat == "BestRoll" then (if unlocked then "done" else "—") else `{fmt(value)}/{fmt(def.Goal)}`, UDim2.fromOffset(84, 18), UDim2.new(1, -92, 0, 6), Color3.fromRGB(220, 220, 230))
		right.TextXAlignment = Enum.TextXAlignment.Right
		local reward = label(row, `💎 {def.Gems}`, UDim2.fromOffset(84, 18), UDim2.new(1, -92, 0, 28), Color3.fromRGB(140, 220, 255))
		reward.TextXAlignment = Enum.TextXAlignment.Right
	end
	title.Text = `🏆 Achievements  {done}/{#Defs.List}`
	hudButton.Text = `🏆 {done}/{#Defs.List}`
end

local function showNextPopup()
	if showingPopup or #popupQueue == 0 then
		return
	end
	showingPopup = true
	local def = Defs.Find(table.remove(popupQueue, 1) :: string)
	if not def then
		showingPopup = false
		showNextPopup()
		return
	end
	local icon = popup:FindFirstChild("Icon") :: TextLabel
	local name = popup:FindFirstChild("Name") :: TextLabel
	local reward = popup:FindFirstChild("Reward") :: TextLabel
	icon.Text = def.Icon
	name.Text = def.Name
	reward.Text = `{def.Description}  +💎{def.Gems}`
	popup.Position = UDim2.new(0.5, 0, 0, -120)
	popup.Visible = true
	if Config.Sounds.Achievement ~= "" then
		for i, speed in { 1, 1.25, 1.5 } do
			task.delay((i - 1) * 0.12, function()
				local s = Instance.new("Sound")
				s.SoundId = Config.Sounds.Achievement
				s.PlaybackSpeed = speed
				s.SoundGroup = SoundService:FindFirstChild("SFX") :: SoundGroup? -- volume setting
				SoundService:PlayLocalSound(s)
				task.delay(2, s.Destroy, s)
			end)
		end
	end
	TweenService:Create(popup, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 80) }):Play()
	task.delay(3.4, function()
		local out = TweenService:Create(popup, TweenInfo.new(0.35), { Position = UDim2.new(0.5, 0, 0, -120) })
		out:Play()
		out.Completed:Wait()
		popup.Visible = false
		showingPopup = false
		showNextPopup()
	end)
end

function Achievements.Mount(screen: ScreenGui)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	hudButton = Instance.new("TextButton")
	hudButton.Name = "AchievementsToggle"
	hudButton.AnchorPoint = Vector2.new(0, 1)
	hudButton.Position = UDim2.new(0, 470, 1, -16)
	hudButton.Size = UDim2.fromOffset(130, 34)
	hudButton.BackgroundColor3 = Color3.fromRGB(230, 170, 40)
	hudButton.TextColor3 = Color3.new(1, 1, 1)
	hudButton.Font = Enum.Font.FredokaOne
	hudButton.TextScaled = true
	hudButton.Text = "🏆"
	hudButton.Parent = screen
	corner(hudButton, 8)

	panel = Instance.new("Frame")
	panel.Name = "AchievementsPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(520, 420)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.ZIndex = 5
	panel.Parent = screen
	corner(panel, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 3
	stroke.Parent = panel
	local maxSize = Instance.new("UISizeConstraint")
	maxSize.MaxSize = Vector2.new(520, 420)
	maxSize.Parent = panel
	title = label(panel, "🏆 Achievements", UDim2.new(1, -60, 0, 30), UDim2.fromOffset(12, 8), GOLD)
	local close = Instance.new("TextButton")
	close.Size = UDim2.fromOffset(34, 30)
	close.Position = UDim2.new(1, -44, 0, 8)
	close.BackgroundColor3 = Color3.fromRGB(150, 60, 70)
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Font = Enum.Font.FredokaOne
	close.TextScaled = true
	close.Text = "X"
	close.Parent = panel
	corner(close, 8)
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -20, 1, -54)
	list.Position = UDim2.fromOffset(10, 46)
	list.BackgroundTransparency = 1
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	-- Unlock popup (slides down from the top).
	popup = Instance.new("Frame")
	popup.Name = "AchievementPopup"
	popup.AnchorPoint = Vector2.new(0.5, 0)
	popup.Size = UDim2.fromOffset(420, 84)
	popup.BackgroundColor3 = Color3.fromRGB(50, 38, 15)
	popup.Visible = false
	popup.ZIndex = 35
	popup.Parent = screen
	corner(popup, 14)
	local pstroke = Instance.new("UIStroke")
	pstroke.Color = GOLD
	pstroke.Thickness = 3
	pstroke.Parent = popup
	local icon = label(popup, "🏆", UDim2.fromOffset(64, 64), UDim2.fromOffset(10, 10))
	icon.Name = "Icon"
	icon.ZIndex = 36
	local head = label(popup, "ACHIEVEMENT UNLOCKED!", UDim2.new(1, -90, 0, 18), UDim2.fromOffset(82, 8), GOLD)
	head.ZIndex = 36
	local name = label(popup, "", UDim2.new(1, -90, 0, 28), UDim2.fromOffset(82, 26))
	name.Name = "Name"
	name.ZIndex = 36
	local reward = label(popup, "", UDim2.new(1, -90, 0, 18), UDim2.fromOffset(82, 56), Color3.fromRGB(140, 220, 255))
	reward.Name = "Reward"
	reward.ZIndex = 36

	hudButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			render()
		end
	end)
	local syncRemote = remotes:WaitForChild("AchievementSync") :: RemoteEvent
	local unlockedRemote = remotes:WaitForChild("AchievementUnlocked") :: RemoteEvent
	syncRemote.OnClientEvent:Connect(function(payload)
		state = payload
		render()
	end)
	unlockedRemote.OnClientEvent:Connect(function(id: string)
		table.insert(popupQueue, id)
		showNextPopup()
	end)
	render()
end

return Achievements
