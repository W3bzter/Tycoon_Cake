--!strict
-- Client audio: applies the player's volume settings (attributes MusicVolume /
-- SfxVolume, saved by the server) to SoundService.SFX / Music for this client
-- only, and plays UI sounds in the SFX group.
--   Audio.Play(soundId, speed?, volume?)
--   Audio.Mount(player)            volumes + background music (Config.Sounds.MusicDay /
--                                  MusicNight, swapped at dusk/dawn; empty = none)
--   Audio.HookClicks(screenGui)    a click sound on every button, now and later

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Audio = {}

local function group(name: string): SoundGroup?
	local g = SoundService:FindFirstChild(name)
	return if g and g:IsA("SoundGroup") then g else nil
end

function Audio.Play(soundId: string?, speed: number?, volume: number?)
	if not soundId or soundId == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.PlaybackSpeed = speed or 1
	s.Volume = volume or 0.7
	s.SoundGroup = group("SFX")
	SoundService:PlayLocalSound(s)
	task.delay(5, s.Destroy, s)
end

function Audio.Mount(player: Player?)
	local p = player or Players.LocalPlayer
	local function apply()
		local sfx, music = group("SFX"), group("Music")
		if sfx then
			sfx.Volume = (p:GetAttribute("SfxVolume") :: number?) or 1
		end
		if music then
			music.Volume = (p:GetAttribute("MusicVolume") :: number?) or 0.6
		end
	end
	p:GetAttributeChangedSignal("SfxVolume"):Connect(apply)
	p:GetAttributeChangedSignal("MusicVolume"):Connect(apply)
	SoundService.ChildAdded:Connect(apply) -- the groups arrive from the server
	apply()

	-- Background music: day / night tracks, cross-faded.
	local current: Sound? = nil
	local function playMusic()
		local night = ReplicatedStorage:GetAttribute("IsNight") == true
		local id = if night then Config.Sounds.MusicNight else Config.Sounds.MusicDay
		if current and current.SoundId == id then
			return
		end
		local old = current
		current = nil
		if old then
			TweenService:Create(old, TweenInfo.new(2), { Volume = 0 }):Play()
			task.delay(2.1, old.Destroy, old)
		end
		if id and id ~= "" then
			local s = Instance.new("Sound")
			s.Name = "Music"
			s.SoundId = id
			s.Looped = true
			s.Volume = 0
			s.SoundGroup = group("Music")
			s.Parent = SoundService
			s:Play()
			TweenService:Create(s, TweenInfo.new(2), { Volume = 0.5 }):Play()
			current = s
		end
	end
	ReplicatedStorage:GetAttributeChangedSignal("IsNight"):Connect(playMusic)
	playMusic()
end

function Audio.HookClicks(screen: ScreenGui)
	local function hook(inst: Instance)
		if inst:IsA("GuiButton") then
			inst.Activated:Connect(function()
				Audio.Play(Config.Sounds.UIClick, 1, 0.4)
			end)
		end
	end
	for _, d in screen:GetDescendants() do
		hook(d)
	end
	screen.DescendantAdded:Connect(hook)
end

return Audio
