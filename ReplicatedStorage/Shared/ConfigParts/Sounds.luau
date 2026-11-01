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
}

return Config
