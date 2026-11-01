--!strict
-- Shared tunables for Anomaly Bakery Tycoon. Required by both server and client.

local Config = {}

-- Data -----------------------------------------------------------------------
Config.DataStoreName = "BakeryData_v1"
Config.DataMaxRetries = 3
Config.AutosaveInterval = 180 -- seconds
Config.StartingCash = 250 -- enough to buy the core pipeline (Walls..DisplayCounter = 210)

-- Tycoon ---------------------------------------------------------------------
Config.ButtonCooldown = 1 -- seconds between purchase attempts per player

-- Baking ---------------------------------------------------------------------
Config.MaxIngredientsHeld = 6
Config.IngredientsPerBatter = 3
Config.BakeTime = 8 -- seconds in the oven
Config.DisplaySlots = 3 -- cakes per display counter
Config.InteractSlack = 6 -- extra studs allowed beyond a prompt's range (lag tolerance)

-- Sounds (built-in rbxasset:// files so they work without uploads; swap for
-- rbxassetid:// IDs any time). An empty string means "silent".
Config.Sounds = {
	Purchase = "rbxasset://sounds/electronicpingshort.wav",
	Denied = "rbxasset://sounds/clickfast.wav",
}

-- World ----------------------------------------------------------------------
Config.PlotCount = 4
Config.PlotSize = Vector3.new(80, 1, 80)
Config.PlotSpacing = 100 -- distance between plot centres along X
Config.PlotRowZ = -50 -- plot centres sit behind the street
Config.StreetZ = 15
Config.StreetLength = 500
Config.StreetWidth = 30

-- Remotes (created by the server in ReplicatedStorage.Remotes) -----------------
Config.RemoteNames = {
	"Notify", -- server -> client: (message: string)
	"AnomalyStarted", -- server -> client: (name: string, duration: number)
	"AnomalyEnded", -- server -> client: (name: string)
}

return Config
