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
Config.PlotCount = 4 -- bakeries per side of the street
Config.PlotRows = 2 -- 1 = one side only; 2 = a second row across the street, facing it
Config.PlotRowZB = 100 -- far row centres (fronts at world Z 40, behind the far sidewalk)
Config.PlotSize = Vector3.new(120, 1, 120) -- building size: Config.Building (ConfigParts/Build)
Config.PlotSpacing = 140 -- distance between plot centres along X
Config.PlotRowZ = -70 -- plot centres sit behind the street; fronts at world Z -10 (PlotRowZ + PlotSize.Z / 2)
Config.StreetLength = 640 -- road runs along X at world Z 5..25 (see WorldBuilder)

-- Remotes (created by the server in ReplicatedStorage.Remotes) -----------------
Config.RemoteNames = {
	"Notify", -- server -> client: (message: string)
	"BuildAction", -- client -> server: ("buy", id, uid?) | ("place", id, gx, gz, rot) | ("move", uid, gx, gz, rot) | ("store", uid) | ("upgrade", id)
	"BuildSync", -- server -> client: ({Owned, Counts, Unlocked})
	"AnomalyStarted", -- server -> client: (name: string, duration: number)
	"AnomalyEnded", -- server -> client: (name: string)
	"BuyGemItem", -- client -> server: (itemId: "Shield" | "Boost")
	"DevResetData", -- client -> server, Studio only: reset your save to a new player
	"DevPreviewRoll", -- client -> server, Studio only: (rarityName) play that tier's roll reveal (visual only)
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

-- Interaction prompts (Core/Prompts) ---------------------------------------------
-- Keys are fixed per action so prompts on one machine never share a key.
Config.Prompts = {
	Keys = {
		Main = Enum.KeyCode.E, -- roll, mix, bake, collect, display, load, take
		Fill = Enum.KeyCode.F, -- hold: fill a hopper
		Recipe = Enum.KeyCode.R,
		Toggle = Enum.KeyCode.T, -- line on/off
		Unload = Enum.KeyCode.G,
		Repair = Enum.KeyCode.Q,
	},
	DefaultHold = 0.2,
	HandMixHold = 1.5, -- whisking by hand takes longer
	FillHold = 0.6,
	RepairHold = 2,
	Distance = 10, -- studs
	AnchorLift = 1, -- studs above the part where prompts sit
	StackSpacing = 78, -- pixels between stacked prompts on one part
	RefreshInterval = 0.2, -- seconds between rule checks
}

return Config
