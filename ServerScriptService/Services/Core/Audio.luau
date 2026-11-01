--!strict
-- Sound groups + world sounds. Creates SoundService.SFX and SoundService.Music
-- (they replicate; each client sets their volumes from the player's settings,
-- UI/Audio). Every sound should play in one of them so the volume sliders work.
--   Audio.PlayAt(part, soundId, speed?, volume?)  a 3D sound from a part (SFX)
--   Audio.Group(name)                             the SoundGroup ("SFX" | "Music")

local SoundService = game:GetService("SoundService")

local Audio = {}

local function group(name: string): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = 1
	g.Parent = SoundService
	return g
end
Audio.Group = group

function Audio.PlayAt(part: Instance, soundId: string?, speed: number?, volume: number?)
	if not soundId or soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.PlaybackSpeed = speed or 1
	sound.Volume = volume or 0.8
	sound.SoundGroup = group("SFX")
	sound.Parent = part
	sound:Play()
	task.delay(4, sound.Destroy, sound)
end

function Audio.Init()
	group("SFX")
	group("Music")
end

return Audio
