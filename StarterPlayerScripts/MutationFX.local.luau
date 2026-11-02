--!strict
-- World effects while a mutation event runs (Baking/MutationEvents sets the
-- ReplicatedStorage attributes MutationEventName / MutationEventMult /
-- MutationEventEndsAt). Client-only and self-contained:
--   Sugar Rush      warm pink tint, drifting pink/yellow/mint sparkles and sprinkles
--   Mutation Storm  dark purple tint, fast swirling particles, lightning flashes + thunder
--   Cosmic Bake     deep violet tint, twinkling stars and shooting stars
-- Unknown event names get the Sugar Rush look in their own colour. Everything
-- fades in and out; particles follow the camera so they're always around you.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local LOOKS = {
	["Sugar Rush"] = {
		Tint = Color3.fromRGB(255, 225, 240),
		Saturation = 0.25,
		Colors = { Color3.fromRGB(255, 120, 190), Color3.fromRGB(255, 225, 110), Color3.fromRGB(140, 240, 200) },
		Rate = 40,
		Speed = NumberRange.new(1, 3),
		Lightning = false,
		Shooting = false,
	},
	["Mutation Storm"] = {
		Tint = Color3.fromRGB(205, 175, 255),
		Saturation = 0.1,
		Brightness = -0.06,
		Colors = { Color3.fromRGB(170, 90, 255), Color3.fromRGB(110, 230, 255), Color3.fromRGB(255, 255, 255) },
		Rate = 90,
		Speed = NumberRange.new(10, 22),
		Spin = true,
		Lightning = true,
		Shooting = false,
	},
	["Cosmic Bake"] = {
		Tint = Color3.fromRGB(185, 185, 255),
		Saturation = 0.3,
		Brightness = -0.04,
		Colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 200, 255), Color3.fromRGB(255, 170, 250) },
		Rate = 55,
		Speed = NumberRange.new(0.2, 0.8),
		Twinkle = true,
		Lightning = false,
		Shooting = true,
	},
}

local FADE = 2.5

local tint: ColorCorrectionEffect? = nil
local holder: Part? = nil
local emitters: { ParticleEmitter } = {}
local running: { RBXScriptConnection } = {}
local token = 0

local function sequence(colors: { Color3 }): ColorSequence
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(#colors - 1, 1), c))
	end
	return ColorSequence.new(keys)
end

local function thunder()
	local id = Config.Sounds.NightFalls -- a deep boom
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = 0.45 + math.random() * 0.2
	s.Volume = 0.6
	s.SoundGroup = SoundService:FindFirstChild("SFX") :: SoundGroup?
	SoundService:PlayLocalSound(s)
	task.delay(5, s.Destroy, s)
end

local function stop()
	token += 1
	for _, c in running do
		c:Disconnect()
	end
	running = {}
	for _, e in emitters do
		e.Enabled = false
	end
	local oldHolder, oldTint = holder, tint
	holder, tint, emitters = nil, nil, {}
	if oldTint then
		TweenService:Create(oldTint, TweenInfo.new(FADE), { TintColor = Color3.new(1, 1, 1), Saturation = 0, Brightness = 0 }):Play()
		task.delay(FADE + 0.1, oldTint.Destroy, oldTint)
	end
	if oldHolder then
		task.delay(4, oldHolder.Destroy, oldHolder) -- let the last particles finish
	end
end

local function start(name: string)
	stop()
	token += 1
	local mine = token
	local look = LOOKS[name] or LOOKS["Sugar Rush"]

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "MutationTint"
	cc.Parent = Lighting
	tint = cc
	TweenService:Create(cc, TweenInfo.new(FADE), {
		TintColor = look.Tint,
		Saturation = look.Saturation or 0,
		Brightness = look.Brightness or 0,
	}):Play()

	-- An invisible box around the camera that particles spawn inside.
	local box = Instance.new("Part")
	box.Name = "MutationFX"
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.Transparency = 1
	box.Size = Vector3.new(90, 40, 90)
	box.Parent = workspace.CurrentCamera
	holder = box

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Shape = Enum.ParticleEmitterShape.Box
	sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	sparkles.Color = sequence(look.Colors)
	sparkles.LightEmission = 0.8
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.45), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Transparency = NumberSequence.new(0.1)
	sparkles.Lifetime = NumberRange.new(2.5, 4.5)
	sparkles.Rate = look.Rate
	sparkles.Speed = look.Speed
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.RotSpeed = NumberRange.new(-120, 120)
	if look.Spin then
		sparkles.Acceleration = Vector3.new(0, -2, 0)
		sparkles.Drag = 1
	else
		sparkles.Acceleration = Vector3.new(0, -0.6, 0)
	end
	sparkles.Parent = box
	table.insert(emitters, sparkles)

	if name == "Sugar Rush" or not LOOKS[name] then
		-- Sprinkles: little coloured rods tumbling down.
		local sprinkles = sparkles:Clone()
		sprinkles.Name = "Sprinkles"
		sprinkles.Squash = NumberSequence.new(2.5)
		sprinkles.LightEmission = 0.2
		sprinkles.Rate = 25
		sprinkles.Size = NumberSequence.new(0.18)
		sprinkles.Acceleration = Vector3.new(0, -4, 0)
		sprinkles.Parent = box
		table.insert(emitters, sprinkles)
	end
	if look.Shooting then
		local streaks = Instance.new("ParticleEmitter")
		streaks.Name = "ShootingStars"
		streaks.Shape = Enum.ParticleEmitterShape.Box
		streaks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		streaks.Color = ColorSequence.new(Color3.new(1, 1, 1))
		streaks.LightEmission = 1
		streaks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
		streaks.Squash = NumberSequence.new(-3)
		streaks.Lifetime = NumberRange.new(0.6, 1)
		streaks.Rate = 2
		streaks.Speed = NumberRange.new(70, 100)
		streaks.EmissionDirection = Enum.NormalId.Bottom
		streaks.SpreadAngle = Vector2.new(35, 35)
		streaks.Orientation = Enum.ParticleOrientation.VelocityParallel
		streaks.Parent = box
		table.insert(emitters, streaks)
	end

	local camera = workspace.CurrentCamera
	table.insert(running, RunService.RenderStepped:Connect(function()
		box.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 6, 0))
		if look.Twinkle then
			sparkles.Transparency = NumberSequence.new(0.2 + 0.5 * (0.5 + 0.5 * math.sin(os.clock() * 6)))
		end
	end))

	if look.Lightning then
		task.spawn(function()
			while mine == token do
				task.wait(math.random(4, 9))
				if mine ~= token or not tint then
					break
				end
				local flash = tint
				local base = flash.Brightness
				flash.Brightness = base + 0.45
				task.wait(0.07)
				flash.Brightness = base + 0.05
				task.wait(0.06)
				flash.Brightness = base + 0.35
				TweenService:Create(flash, TweenInfo.new(0.4), { Brightness = base }):Play()
				task.delay(0.3 + math.random() * 0.6, thunder)
			end
		end)
	end
end

local function refresh()
	local name = ReplicatedStorage:GetAttribute("MutationEventName") :: string?
	local endsAt = ReplicatedStorage:GetAttribute("MutationEventEndsAt") :: number?
	local active = name ~= nil and endsAt ~= nil and endsAt > workspace:GetServerTimeNow()
	if active then
		if not holder or (holder :: Part):GetAttribute("Event") ~= name then
			start(name :: string)
			if holder then
				(holder :: Part):SetAttribute("Event", name)
			end
		end
	elseif holder then
		stop()
	end
end

ReplicatedStorage:GetAttributeChangedSignal("MutationEventName"):Connect(refresh)
ReplicatedStorage:GetAttributeChangedSignal("MutationEventEndsAt"):Connect(refresh)
Players.LocalPlayer.CharacterAdded:Connect(refresh)
refresh()
