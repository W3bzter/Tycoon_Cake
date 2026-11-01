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
Config.MaxIngredientsHeld = 8 -- recipes and prices live in Shared/Recipes
Config.BakeTime = 8 -- seconds in the oven
Config.DisplaySlots = 3 -- cakes per display counter
Config.InteractSlack = 6 -- extra studs allowed beyond a prompt's range (lag tolerance)

-- Customers ------------------------------------------------------------------
Config.CustomerInterval = 5 -- seconds between spawn checks
Config.MaxCustomers = 6
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

-- Animations (rbxassetid:// strings; empty = skip and just do a hop)
Config.Animations = {
	Buy = "",
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
}

return Config
