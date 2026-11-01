--!strict
-- Day and night (Config.DayNight). Moves Lighting.ClockTime through the day
-- (DaySeconds) and the night (NightSeconds), turns the lighting moonlit at night,
-- and switches every light tagged "NightLight" (street lamps, bakery ceiling
-- bulbs) on at night. Anomalies only start at night (AnomalyManager asks IsNight).
-- ReplicatedStorage attributes for clients: IsNight, PhaseEndsAt (server time).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local Remotes = require(Services.Core.Remotes)

local DayNight = {}

local changedEvent = Instance.new("BindableEvent")
DayNight.Changed = changedEvent.Event -- (isNight)

local LOOKS = {
	Day = {
		Brightness = 3,
		Ambient = Color3.fromRGB(120, 105, 120),
		OutdoorAmbient = Color3.fromRGB(170, 160, 175),
	},
	Night = {
		Brightness = 1.2,
		Ambient = Color3.fromRGB(60, 55, 85),
		OutdoorAmbient = Color3.fromRGB(70, 75, 120),
	},
}

local isNight = false
local phaseStart = 0

function DayNight.IsNight(): boolean
	return isNight
end

-- Lights tagged NightLight: on at night, but only where their part is shown
-- (hidden items keep their lights off).
local function applyLights()
	for _, inst in CollectionService:GetTagged("NightLight") do
		local part = if inst:IsA("BasePart") then inst else inst:FindFirstAncestorWhichIsA("BasePart")
		local shown = part ~= nil and part.Transparency < 1
		if inst:IsA("Light") then
			inst.Enabled = isNight and shown
		elseif inst:IsA("BasePart") and shown then
			inst.Material = if isNight then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

local function playSting(soundId: string?, speed: number)
	if not soundId or soundId == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.PlaybackSpeed = speed
	s.Volume = 0.8
	s.SoundGroup = SoundService:FindFirstChild("SFX") :: SoundGroup?
	s.Parent = SoundService -- non-positional: everyone hears it
	s:Play()
	task.delay(5, s.Destroy, s)
end

local function setPhase(night: boolean)
	isNight = night
	phaseStart = os.clock()
	local cfg = Config.DayNight
	local length = if night then cfg.NightSeconds else cfg.DaySeconds
	ReplicatedStorage:SetAttribute("IsNight", night)
	ReplicatedStorage:SetAttribute("PhaseEndsAt", workspace:GetServerTimeNow() + length)
	TweenService:Create(Lighting, TweenInfo.new(cfg.TransitionTime), if night then LOOKS.Night else LOOKS.Day):Play()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, TweenInfo.new(cfg.TransitionTime), {
			Color = if night then Color3.fromRGB(110, 120, 180) else Color3.fromRGB(255, 225, 205),
			Decay = if night then Color3.fromRGB(60, 50, 110) else Color3.fromRGB(255, 170, 190),
		}):Play()
	end
	applyLights()
	Remotes.Get("Notify"):FireAllClients(if night then "🌙 Night falls... the anomalies are coming!" else "☀️ Good morning! The bakery is safe for now.")
	playSting(if night then Config.Sounds.NightFalls else Config.Sounds.DayBreaks, 1)
	changedEvent:Fire(night)
end

-- Clock time for the current moment of the current phase.
local function clockNow(): number
	local cfg = Config.DayNight
	local t = os.clock() - phaseStart
	if isNight then
		local span = (24 - cfg.DuskClock) + cfg.DawnClock
		return (cfg.DuskClock + span * math.min(t / cfg.NightSeconds, 1)) % 24
	end
	return cfg.DawnClock + (cfg.DuskClock - cfg.DawnClock) * math.min(t / cfg.DaySeconds, 1)
end

function DayNight.Init()
	setPhase(false)
	local lastLights = 0
	RunService.Heartbeat:Connect(function()
		local cfg = Config.DayNight
		Lighting.ClockTime = clockNow()
		local elapsed = os.clock() - phaseStart
		if elapsed >= (if isNight then cfg.NightSeconds else cfg.DaySeconds) then
			setPhase(not isNight)
		end
		if os.clock() - lastLights > 2 then
			lastLights = os.clock()
			applyLights() -- items shown/hidden since (purchases, placements)
		end
	end)
end

-- Studio/testing: jump to night or day now.
function DayNight.Skip(): boolean
	setPhase(not isNight)
	return isNight
end

return DayNight
