--!strict
-- Sounds (built-in rbxasset:// files; swap for rbxassetid:// IDs any time).
-- Merged into Shared/Config (read it as Config.<Name>).

local Config = {}

-- Sounds (built-in rbxasset:// files so they work without uploads; swap for
-- rbxassetid:// IDs any time). An empty string means "silent".
Config.Sounds = {
	Purchase = "rbxasset://sounds/electronicpingshort.wav",
	Denied = "rbxasset://sounds/clickfast.wav",
	Sale = "rbxasset://sounds/electronicpingshort.wav",
	BigRoll = "rbxasset://sounds/electronicpingshort.wav", -- Legendary+ roll fanfare (pitched)
	Explosion = "rbxasset://sounds/collide.wav",
	Repair = "rbxasset://sounds/clickfast.wav",
	AnomalySting = "rbxasset://sounds/electronicpingshort.wav", -- cutscene sting (pitched down)
	Achievement = "rbxasset://sounds/electronicpingshort.wav",
	-- Build mode
	Place = "rbxasset://sounds/snap.wav",
	Store = "rbxasset://sounds/snap.wav", -- (swoosh.wav fails to load in-game: "not approved")
	UIClick = "rbxasset://sounds/button.wav",
	-- Baking and customers
	BakeDone = "rbxasset://sounds/electronicpingshort.wav", -- a rack finished (pitched up)
	Display = "rbxasset://sounds/snap.wav", -- cake put on a counter
	Tip = "rbxasset://sounds/electronicpingshort.wav", -- dine-in tip (pitched up)
	-- World
	NightFalls = "rbxasset://sounds/bass.wav",
	DayBreaks = "rbxasset://sounds/electronicpingshort.wav",
	MutationEvent = "rbxasset://sounds/electronicpingshort.wav",
	-- Background music, looped (UI/Audio). Paste rbxassetid:// IDs of tracks from
	-- the Creator Store (Audio); empty = no music.
	MusicDay = "",
	MusicNight = "",
}

return Config
