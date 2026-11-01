--!strict
-- Client audio: applies the player's volume settings (attributes MusicVolume /
-- SfxVolume, saved by the server) to SoundService.SFX / Music for this client
-- only, and plays UI sounds in the SFX group.
--   Audio.Play(soundId, speed?, volume?)
--   Audio.Mount(player)

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

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
end

return Audio
