--!strict
-- Core: DevMode, data store, tycoon buttons, world layout, remote names.
-- Merged into Shared/Config (read it as Config.<Name>).

local Config = {}

-- DevMode ----------------------------------------------------------------------
-- Studio-only testing aid. Set DevMode = false to turn it off. Even when true it
-- does nothing in the live game: the server also requires RunService:IsStudio().
-- While active, your Cash and Gems are set to DevModeAmount on every join, and a
-- separate save key (Dev_<UserId>) is used so your real save is never touched.
Config.DevMode = true
Config.DevModeAmount = 1e12

-- Data -----------------------------------------------------------------------
Config.DataStoreName = "BakeryData_v1"
Config.DataMaxRetries = 3
Config.AutosaveInterval = 180 -- seconds
Config.StartingCash = 100 -- covers the hand-tool start (Pantry..Display Counter = 90)

-- Tycoon ---------------------------------------------------------------------
Config.ButtonCooldown = 1 -- seconds between purchase attempts per player

-- World ----------------------------------------------------------------------
Config.PlotCount = 4
Config.PlotSize = Vector3.new(80, 1, 80)
Config.PlotSpacing = 100 -- distance between plot centres along X
Config.PlotRowZ = -50 -- plot centres sit behind the street
Config.StreetLength = 500 -- road runs along X at world Z 5..25 (see WorldBuilder)

-- Remotes (created by the server in ReplicatedStorage.Remotes) -----------------
Config.RemoteNames = {
	"Notify", -- server -> client: (message: string)
	"AnomalyStarted", -- server -> client: (name: string, duration: number)
	"AnomalyEnded", -- server -> client: (name: string)
	"BuyGemItem", -- client -> server: (itemId: "Shield" | "Boost")
	"DevResetData", -- client -> server, Studio only: reset your save to a new player
	"RollResult", -- server -> client: (items) for the roll reveal
	"BagUpdate", -- server -> client: ({Items, Capacity, MixRecipe})
	"BagAction", -- client -> server: ("pin" | "discard", id) or ("recipe", name)
	"MixStart", -- server -> client: (sessionId, stationId, seed)
	"MixSubmit", -- client -> server: (sessionId, score 0..1)
	"Settings", -- client -> server: ("autodelete", kind, n) | ("keepspecial", bool)
	"ShopAction", -- client -> server: ("storage", "Bag" | "Rack")
	"GamePassPrompt", -- client -> server: (passKey) asks the server to prompt a pass purchase
	"Cutscene", -- server -> client: (anomalyName, focus: Vector3, plotName)
	"ScreenShake", -- server -> client: (intensity, duration)
	"Rebirth", -- client -> server: () try to rebirth
	"AchievementSync", -- server -> client: ({Stats, Unlocked})
	"AchievementUnlocked", -- server -> client: (achievementId)
}

return Config
