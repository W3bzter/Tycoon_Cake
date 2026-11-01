--!strict
-- Full-screen cutscenes for the two rarest tiers (Shared/Rarity Fx), played by
-- RollReveal before the card lands:
--   void       BLACKOUT: the screen cuts to pure black and silence, a heartbeat,
--              then a purple vortex tears open (spinning rings pulled inward,
--              glitching title, inverted flashes, camera zoom) and implodes.
--   celestial  WHITE-OUT: a blinding white flash that holds, then golden and
--              rainbow rays bloom, rings burst outward, stars rain, the title
--              descends, and the white fades back into the world.
-- Purely visual (the server already gave the item). About 6 seconds; lives in its
-- own ScreenGui above everything else.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ScreenShake = require(script.Parent:WaitForChild("ScreenShake"))

local RarityCutscene = {}

local DURATION = 6.2
local playing = false

local function sound(speed: number, volume: number)
	local id = Config.Sounds.BigRoll
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = speed
	s.Volume = volume
	s.SoundGroup = SoundService:FindFirstChild("SFX") :: SoundGroup? -- volume setting
	SoundService:PlayLocalSound(s)
	task.delay(5, s.Destroy, s)
end

local function frame(parent: Instance, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function ring(parent: Instance, color: Color3, size: number, z: number): Frame
	local r = frame(parent, color, z)
	r.BackgroundTransparency = 1
	r.Size = UDim2.fromOffset(size, size)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = r
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 6
	stroke.Parent = r
	return r
end

local function title(parent: Instance, text: string, color: Color3, z: number): TextLabel
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.5)
	t.Size = UDim2.new(0.9, 0, 0, 120)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	t.TextTransparency = 1
	t.ZIndex = z
	t.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = t
	return t
end

-- Camera field-of-view punch (restored at the end).
local function fovPunch(to: number, time: number): () -> ()
	local camera = workspace.CurrentCamera
	local base = camera.FieldOfView
	TweenService:Create(camera, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { FieldOfView = to }):Play()
	return function()
		TweenService:Create(camera, TweenInfo.new(0.6, Enum.EasingStyle.Back), { FieldOfView = base }):Play()
	end
end

local function playVoid(gui: ScreenGui, color: Color3, label: string)
	local black = frame(gui, Color3.new(0, 0, 0), 1)
	black.BackgroundTransparency = 0 -- instant blackout
	ScreenShake.Shake(0.2, 0.2)
	task.wait(0.9) -- silence...
	for beat = 1, 2 do -- ...heartbeat
		sound(0.35, 1)
		local pulse = frame(gui, color, 2)
		pulse.BackgroundTransparency = 0.85
		TweenService:Create(pulse, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		task.delay(0.4, pulse.Destroy, pulse)
		task.wait(if beat == 1 then 0.45 else 0.6)
	end

	-- The vortex tears open.
	local rings: { Frame } = {}
	for i = 1, 14 do
		local r = ring(gui, if i % 3 == 0 then Color3.new(1, 1, 1) else color, 1600 - i * 100, 3)
		r.Rotation = i * 17
		table.insert(rings, r)
	end
	local name = title(gui, label, color, 6)
	local ghostA = title(gui, label, Color3.fromRGB(255, 40, 80), 5)
	local ghostB = title(gui, label, Color3.fromRGB(40, 220, 255), 5)
	TweenService:Create(name, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	local restoreFov = fovPunch(115, 2.4)
	ScreenShake.Shake(1.8, 2.6)
	sound(0.5, 1)
	task.delay(0.3, sound, 0.7, 0.9)
	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		for i, r in rings do
			r.Rotation += dt * (60 + i * 25) * (if i % 2 == 0 then 1 else -1)
			local s = math.max(8, (1600 - i * 100) * (1 - t / 2.6) + math.sin(t * 9 + i) * 20)
			r.Size = UDim2.fromOffset(s, s)
		end
		-- Glitch: RGB-split ghosts, inverted flashes.
		for k, g in { ghostA, ghostB } do
			g.TextTransparency = 0.35
			g.Position = UDim2.new(0.5, (if k == 1 then -1 else 1) * math.random(3, 14), 0.5, math.random(-8, 8))
		end
		name.Rotation = math.sin(t * 13) * 4
		black.BackgroundColor3 = if math.random() < 0.08 then Color3.new(1, 1, 1) elseif math.random() < 0.15 then color:Lerp(Color3.new(0, 0, 0), 0.6) else Color3.new(0, 0, 0)
	end)
	task.wait(2.6)
	conn:Disconnect()
	-- Implode, then the lights come back.
	for _, r in rings do
		r:Destroy()
	end
	ghostA:Destroy()
	ghostB:Destroy()
	black.BackgroundColor3 = Color3.new(1, 1, 1)
	sound(1.4, 1)
	ScreenShake.Shake(1, 0.5)
	restoreFov()
	TweenService:Create(black, TweenInfo.new(0.25), { BackgroundColor3 = Color3.new(0, 0, 0) }):Play()
	task.wait(0.35)
	TweenService:Create(black, TweenInfo.new(1), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(name, TweenInfo.new(1.2), { TextTransparency = 1, Size = UDim2.new(1.4, 0, 0, 200) }):Play()
	task.wait(1.2)
end

local function playCelestial(gui: ScreenGui, label: string)
	local white = frame(gui, Color3.new(1, 1, 1), 1)
	white.BackgroundTransparency = 0 -- blinding white-out
	sound(1.6, 1)
	ScreenShake.Shake(0.6, 0.4)
	local restoreFov = fovPunch(40, 1.2) -- the world zooms in under the light
	task.wait(1.2)

	-- Rays bloom from the centre.
	local rays = frame(gui, Color3.new(1, 1, 1), 2)
	rays.BackgroundTransparency = 1
	rays.Size = UDim2.fromOffset(10, 10)
	for i = 1, 24 do
		local ray = frame(rays, Color3.fromHSV(i / 24, 0.35, 1), 2)
		ray.Size = UDim2.fromOffset(2200, if i % 2 == 0 then 24 else 50)
		ray.Rotation = i * (180 / 24)
		ray.BackgroundTransparency = 0.3
	end
	local name = title(gui, label, Color3.fromRGB(255, 215, 90), 6)
	name.Position = UDim2.fromScale(0.5, 0.2)
	TweenService:Create(name, TweenInfo.new(1.2, Enum.EasingStyle.Back), { TextTransparency = 0, Position = UDim2.fromScale(0.5, 0.45) }):Play()
	TweenService:Create(white, TweenInfo.new(1.5), { BackgroundColor3 = Color3.fromRGB(255, 240, 200), BackgroundTransparency = 0.15 }):Play()
	sound(1.2, 1)
	task.delay(0.4, sound, 1.8, 0.8)

	-- Rings burst outward, stars rain down.
	local t0 = os.clock()
	local lastRing, lastStar = 0, 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		rays.Rotation += dt * 50
		for _, ray in rays:GetChildren() do
			if ray:IsA("Frame") then
				ray.BackgroundColor3 = Color3.fromHSV((t * 0.3 + ray.Rotation / 180) % 1, 0.35, 1)
			end
		end
		name.Rotation = math.sin(t * 2) * 2
		if t - lastRing > 0.25 then
			lastRing = t
			local r = ring(gui, Color3.fromHSV((t * 0.5) % 1, 0.4, 1), 40, 3)
			TweenService:Create(r, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(2400, 2400) }):Play()
			TweenService:Create(r:FindFirstChildOfClass("UIStroke") :: UIStroke, TweenInfo.new(1.2), { Transparency = 1 }):Play()
			task.delay(1.3, r.Destroy, r)
		end
		if t - lastStar > 0.05 then
			lastStar = t
			local star = Instance.new("TextLabel")
			star.BackgroundTransparency = 1
			star.Text = if math.random() < 0.5 then "✨" else "⭐"
			star.TextScaled = true
			star.Size = UDim2.fromOffset(28, 28)
			star.Position = UDim2.fromScale(math.random(), -0.05)
			star.ZIndex = 4
			star.Parent = gui
			TweenService:Create(star, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(star.Position.X.Scale + (math.random() - 0.5) * 0.2, 1.05), Rotation = math.random(-360, 360) }):Play()
			task.delay(1.5, star.Destroy, star)
		end
	end)
	ScreenShake.Shake(0.8, 2.4)
	task.wait(3)
	conn:Disconnect()
	-- One last flash, then the white fades back into the world.
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.BackgroundTransparency = 0
	rays:Destroy()
	restoreFov()
	TweenService:Create(white, TweenInfo.new(1.4), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(name, TweenInfo.new(1.4), { TextTransparency = 1 }):Play()
	task.wait(1.4)
end

function RarityCutscene.IsPlaying(): boolean
	return playing
end

-- Plays the cutscene for `fx` ("void" | "celestial"), then calls onDone.
-- A second one while playing is skipped (onDone still runs).
function RarityCutscene.Play(fx: string, tierName: string, color: Color3, itemIcon: string?, onDone: (() -> ())?)
	if playing then
		if onDone then
			onDone()
		end
		return
	end
	playing = true
	local gui = Instance.new("ScreenGui")
	gui.Name = "RarityCutscene"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100 -- above the HUD and the roll reveal
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local label = `{string.upper(tierName)}!` .. (if itemIcon then `  {itemIcon}` else "")
	task.spawn(function()
		local ok, err = pcall(function()
			if fx == "void" then
				playVoid(gui, color, label)
			else
				playCelestial(gui, label)
			end
		end)
		if not ok then
			warn(`[RarityCutscene] {err}`)
		end
		gui:Destroy()
		playing = false
		if onDone then
			onDone()
		end
	end)
end

RarityCutscene.Duration = DURATION

return RarityCutscene
