--!strict
-- Anomaly intro cutscenes (Remotes.Cutscene: name, focus, plotName). Letterbox
-- bars, a scripted camera move around the focus point (style per anomaly in
-- Config.Cutscene.Shots), a colour tint, a title card, a sting and some shake.
-- Skippable (button or any key); the camera is always handed back afterwards.
--
-- Styles: push (slow push-in), low (low angle looking up), ground (rat's-eye
-- dolly), whip (fast whip-pans around the focus), tilt (camera rolls and looks
-- up), glitch (push with jitter + flicker), blackout (black, then a fade-in).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ScreenShake = require(script.Parent:WaitForChild("ScreenShake"))

local Cutscene = {}

local screenGui: ScreenGui
local topBar: Frame
local bottomBar: Frame
local title: TextLabel
local subtitle: TextLabel
local skipButton: TextButton
local blackout: Frame
local playing = false
local token = 0

function Cutscene.IsPlaying(): boolean
	return playing
end

local function bar(name: string, anchorY: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0, anchorY)
	f.Position = UDim2.fromScale(0, anchorY)
	f.Size = UDim2.fromScale(1, 0)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.ZIndex = 40
	f.Parent = screenGui
	return f
end

function Cutscene.Mount(player: Player)
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "Cutscene"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 50
	screenGui.Enabled = false
	screenGui.Parent = player:WaitForChild("PlayerGui")

	blackout = Instance.new("Frame")
	blackout.Size = UDim2.fromScale(1, 1)
	blackout.BackgroundColor3 = Color3.new(0, 0, 0)
	blackout.BackgroundTransparency = 1
	blackout.BorderSizePixel = 0
	blackout.ZIndex = 39
	blackout.Parent = screenGui
	topBar = bar("Top", 0)
	bottomBar = bar("Bottom", 1)

	title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 1)
	title.Position = UDim2.new(0.5, 0, 1, -38)
	title.Size = UDim2.new(0.8, 0, 0, 52)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 90, 90)
	title.ZIndex = 41
	title.Text = ""
	title.Parent = screenGui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = title

	subtitle = Instance.new("TextLabel")
	subtitle.AnchorPoint = Vector2.new(0.5, 1)
	subtitle.Position = UDim2.new(0.5, 0, 1, -12)
	subtitle.Size = UDim2.new(0.8, 0, 0, 24)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.FredokaOne
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromRGB(255, 230, 230)
	subtitle.ZIndex = 41
	subtitle.Text = ""
	subtitle.Parent = screenGui

	skipButton = Instance.new("TextButton")
	skipButton.AnchorPoint = Vector2.new(1, 0)
	skipButton.Position = UDim2.new(1, -16, 0, 16)
	skipButton.Size = UDim2.fromOffset(110, 34)
	skipButton.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	skipButton.TextColor3 = Color3.new(1, 1, 1)
	skipButton.Font = Enum.Font.FredokaOne
	skipButton.TextScaled = true
	skipButton.Text = "Skip ▶▶"
	skipButton.ZIndex = 42
	skipButton.Parent = screenGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = skipButton
end

local function playSting()
	local id = Config.Sounds.AnomalySting
	if id == "" then
		return
	end
	for i, speed in { 0.45, 0.6 } do
		task.delay((i - 1) * 0.18, function()
			local s = Instance.new("Sound")
			s.SoundId = id
			s.PlaybackSpeed = speed
			s.Volume = 1
			SoundService:PlayLocalSound(s)
			task.delay(3, s.Destroy, s)
		end)
	end
end

-- Camera keyframes { cframe, time } for a style around `focus`.
local function shots(style: string, focus: Vector3, from: CFrame): { { cf: CFrame, t: number } }
	local function look(offset: Vector3, at: Vector3?): CFrame
		return CFrame.lookAt(focus + offset, at or focus)
	end
	local L = Config.Cutscene.Length
	if style == "low" then
		return { { cf = look(Vector3.new(0, 1.5, 22), focus + Vector3.new(0, 6, 0)), t = 0.5 }, { cf = look(Vector3.new(2, 2, 12), focus + Vector3.new(0, 7, 0)), t = L - 1 } }
	elseif style == "ground" then
		return { { cf = look(Vector3.new(10, 1, 10)), t = 0.5 }, { cf = look(Vector3.new(3, 1, 4)), t = L - 1 } }
	elseif style == "whip" then
		local list = {}
		for i = 0, 3 do
			local a = math.rad(i * 110)
			table.insert(list, { cf = look(Vector3.new(math.sin(a) * 14, 6, math.cos(a) * 14)), t = 0.6 })
		end
		table.insert(list, { cf = look(Vector3.new(0, 5, 10)), t = L - 2.9 })
		return list
	elseif style == "tilt" then
		return { { cf = from * CFrame.Angles(0, 0, math.rad(25)), t = 1 }, { cf = from * CFrame.Angles(math.rad(55), 0, math.rad(-15)), t = L - 1.5 } }
	elseif style == "blackout" then
		return { { cf = look(Vector3.new(0, 4, 16)), t = 0.1 }, { cf = look(Vector3.new(0, 3, 9)), t = L - 0.6 } }
	end
	-- push / glitch
	return { { cf = look(Vector3.new(0, 8, 24)), t = 0.5 }, { cf = look(Vector3.new(0, 4, 11)), t = L - 1 } }
end

function Cutscene.Play(name: string, focus: Vector3?, _plotName: string?)
	local cfg = Config.Anomalies[name]
	local shot = Config.Cutscene.Shots[name] or { Style = "push", Tint = Color3.fromRGB(255, 120, 120) }
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	token += 1
	local mine = token
	playing = true

	local player = Players.LocalPlayer
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local from = camera.CFrame
	local target = focus or (root and root.Position) or from.Position + from.LookVector * 20

	-- UI in (the main HUD hides for the shot)
	screenGui.Enabled = true
	local hud = player:FindFirstChild("PlayerGui") and (player.PlayerGui :: any):FindFirstChild("BakeryHUD") :: ScreenGui?
	if hud then
		hud.Enabled = false
	end
	title.Text = ""
	subtitle.Text = if cfg then cfg.Description else ""
	subtitle.TextTransparency = 1
	topBar.Size = UDim2.fromScale(1, 0)
	bottomBar.Size = UDim2.fromScale(1, 0)
	TweenService:Create(topBar, TweenInfo.new(0.35), { Size = UDim2.fromScale(1, 0.12) }):Play()
	TweenService:Create(bottomBar, TweenInfo.new(0.35), { Size = UDim2.fromScale(1, 0.16) }):Play()
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "CutsceneTint"
	cc.TintColor = Color3.new(1, 1, 1)
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(0.6), { TintColor = shot.Tint, Contrast = 0.15, Saturation = -0.15 }):Play()
	blackout.BackgroundTransparency = if shot.Style == "blackout" then 0 else 1
	if shot.Style == "blackout" then
		TweenService:Create(blackout, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 0.25 }):Play()
	end
	playSting()
	ScreenShake.Shake(0.7, 0.6)

	-- Typewriter title
	local fullTitle = if cfg then `⚠ {cfg.DisplayName} ⚠` else name
	task.spawn(function()
		for i = 1, #fullTitle do
			if mine ~= token then
				return
			end
			title.Text = string.sub(fullTitle, 1, i)
			task.wait(0.03)
		end
		TweenService:Create(subtitle, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	end)

	-- Camera
	camera.CameraType = Enum.CameraType.Scriptable
	local skipped = false
	local skipConn = skipButton.Activated:Connect(function()
		skipped = true
	end)
	local keyConn = UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and (input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType == Enum.UserInputType.Gamepad1) then
			skipped = true
		end
	end)
	local jitter: RBXScriptConnection? = nil
	if shot.Style == "glitch" then
		jitter = RunService.RenderStepped:Connect(function()
			if math.random() < 0.15 then
				camera.CFrame *= CFrame.new((math.random() - 0.5) * 1.2, (math.random() - 0.5) * 1.2, 0)
				cc.Saturation = -1
			else
				cc.Saturation = -0.15
			end
		end)
	end

	for _, key in shots(shot.Style, target, from) do
		if skipped or mine ~= token then
			break
		end
		local tween = TweenService:Create(camera, TweenInfo.new(key.t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = key.cf })
		tween:Play()
		local t0 = os.clock()
		while os.clock() - t0 < key.t and not skipped and mine == token do
			task.wait()
		end
		tween:Cancel()
	end

	-- Hand the camera back.
	skipConn:Disconnect()
	keyConn:Disconnect()
	if jitter then
		jitter:Disconnect()
	end
	if mine ~= token then
		cc:Destroy()
		return -- a newer cutscene took over
	end
	if hud then
		hud.Enabled = true
	end
	local back = TweenService:Create(camera, TweenInfo.new(if skipped then 0.15 else 0.5, Enum.EasingStyle.Sine), { CFrame = from })
	back:Play()
	TweenService:Create(topBar, TweenInfo.new(0.35), { Size = UDim2.fromScale(1, 0) }):Play()
	TweenService:Create(bottomBar, TweenInfo.new(0.35), { Size = UDim2.fromScale(1, 0) }):Play()
	TweenService:Create(blackout, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(cc, TweenInfo.new(0.5), { TintColor = Color3.new(1, 1, 1), Contrast = 0, Saturation = 0 }):Play()
	task.wait(if skipped then 0.15 else 0.5)
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	task.delay(0.5, cc.Destroy, cc)
	screenGui.Enabled = false
	playing = false
end

return Cutscene
