--!strict
-- Shared tunables for Anomaly Bakery Tycoon. Required by both server and client.

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
Config.StartingCash = 250 -- enough to buy the core pipeline (Walls..DisplayCounter = 210)

-- Tycoon ---------------------------------------------------------------------
Config.ButtonCooldown = 1 -- seconds between purchase attempts per player

-- Baking ---------------------------------------------------------------------
Config.MaxIngredientsHeld = 8 -- recipes and prices live in Shared/Recipes
Config.BakeTime = 8 -- seconds in the oven
Config.DisplaySlots = 3 -- cakes per display counter
Config.InteractSlack = 6 -- extra studs allowed beyond a prompt's range (lag tolerance)

-- Customers ------------------------------------------------------------------
Config.CustomerInterval = 5 -- seconds between spawn checks
Config.MaxCustomers = 12
Config.CustomerWalkSpeed = 18
Config.CustomerTripTimeout = 60 -- give up on a leg of the trip after this long
Config.CustomerStandOff = 5 -- studs in front of the counter where customers stop

-- Anomalies --------------------------------------------------------------------
-- Duration is the countdown shown to players. For Overheat/Mimic it is a safety
-- timeout: those end early once players deal with them.
Config.AnomalyInterval = 180
Config.Anomalies = {
	GravityDistortion = {
		DisplayName = "GRAVITY DISTORTION",
		Description = "Gravity has dropped to 10%!",
		Weight = 1,
		Duration = 45,
		GravityScale = 0.1,
	},
	OverheatCrisis = {
		DisplayName = "OVERHEAT CRISIS",
		Description = "Ovens are overheating! Use your Fire Extinguisher on them.",
		Weight = 1,
		Duration = 60,
		ExtinguisherRange = 12,
	},
	MimicCustomer = {
		DisplayName = "MIMIC CUSTOMER",
		Description = "A glowing mimic is after your cakes! Click or touch it to stop it.",
		Weight = 1,
		Duration = 60,
		StopReward = 50,
	},
}

Config.WantedTip = 0.2 -- customers tip 20% when they get the cake they asked for
Config.VIPPayMult = 3 -- VIP customers pay 3x
Config.SpawnCheckInterval = 1 -- per-plot spawn timers are checked this often

-- Automation (production lines) -------------------------------------------------
Config.Auto = {
	FeedTime = 4, -- seconds for the ingredient conveyor to deliver one recipe's worth
	MixTime = 3,
	BakeMult = 1.5, -- automated ovens are slower than a player's oven until upgraded
	DeliverTime = 3, -- conveyor travel time to the counter
	HopperCap = 2, -- recipe sets the hopper can hold
	TrayCap = 2, -- batters / cakes waiting between steps
}

-- Gems --------------------------------------------------------------------------
Config.Gems = {
	ShieldPrice = 5,
	MaxShields = 3,
	BoostPrice = 3,
	BoostSeconds = 300,
	BoostBakeMult = 0.5, -- 2x bake speed while boosted
	ExtinguishReward = 1,
	MimicReward = 3,
	VIPGemChance = 0.25,
	VIPGemMax = 3,
}

-- Customer animations: Roblox's default R15 animations. Empty = skip
-- (the cheer falls back to a hop).
Config.Animations = {
	Idle = "rbxassetid://507766388",
	Walk = "rbxassetid://507777826",
	Cheer = "rbxassetid://507770677",
}

-- Sounds (built-in rbxasset:// files so they work without uploads; swap for
-- rbxassetid:// IDs any time). An empty string means "silent".
Config.Sounds = {
	Purchase = "rbxasset://sounds/electronicpingshort.wav",
	Denied = "rbxasset://sounds/clickfast.wav",
	Sale = "rbxasset://sounds/electronicpingshort.wav",
}

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
}

return Config
