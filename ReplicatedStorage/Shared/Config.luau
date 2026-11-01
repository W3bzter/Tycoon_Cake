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
Config.StartingCash = 100 -- covers the hand-tool start (Pantry..Display Counter = 90)

-- Tycoon ---------------------------------------------------------------------
Config.ButtonCooldown = 1 -- seconds between purchase attempts per player

-- Ingredient rolls (always free; see Shared/Rarity for rarities and traits) ------
Config.Rolling = {
	BagSize = 40, -- ingredients the bag can hold
	Cooldown = 3, -- seconds between rolls (the reveal animation is ~1.5s)
}

-- Mixing minigame ------------------------------------------------------------------
-- Keep the dot inside the drifting sweet spot. Score = share of time inside.
-- Radius/speed are relative to the play area (0..1). Automation always mixes "Good".
Config.Minigame = {
	Duration = 4, -- seconds of play
	ReadyTime = 0.8, -- "Get ready" before it starts
	Grades = { { "Perfect", 0.85 }, { "Great", 0.65 }, { "Good", 0.4 }, { "Sloppy", 0 } },
	Stations = {
		PrepTable = { Radius = 0.11, Speed = 1.35, Label = "Hand whisk" }, -- hard
		Mixer = { Radius = 0.17, Speed = 0.9, Label = "Mixer" }, -- easier
	},
	Timeout = 10, -- seconds after the start before an unanswered session is dropped
}

-- Baking ---------------------------------------------------------------------
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
		Description = "Ovens are overheating! Use your Fire Extinguisher before they EXPLODE!",
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
	Brute = {
		DisplayName = "BRUTE BREAK-IN",
		Description = "A Brute is smashing into your bakery! Whack it with the Frying Pan before it wrecks your machines.",
		Weight = 1,
		Duration = 90,
		HP = 12,
		SmashInterval = 8, -- seconds between machine smashes
		MaxBreaks = 3, -- machines it can break per plot
		RewardCash = 300,
		RewardGems = 5,
	},
	RatSwarm = {
		DisplayName = "RAT SWARM",
		Description = "Rats are raiding your pantry and nibbling cakes! Stomp or whack them!",
		Weight = 1,
		Duration = 60,
		Count = 7,
		Steal = 2, -- bag ingredients a rat steals from the pantry
		Speed = 9, -- studs per second
		RewardCash = 20, -- per rat
		ClearGems = 2, -- squash every rat
	},
	Gremlin = {
		DisplayName = "GREMLIN SABOTAGE",
		Description = "A Gremlin is sabotaging your production lines! Catch it 3 times!",
		Weight = 1,
		Duration = 75,
		Catches = 3,
		ActionInterval = 6, -- seconds between sabotage moves
		VisibleTime = 4, -- seconds it sits still (catchable) after a move
		JamSeconds = 15,
		RewardGems = 4,
	},
	Phantom = {
		DisplayName = "PHANTOM HAUNTING",
		Description = "A Phantom is scaring customers away and spooking cakes! Click it when it appears!",
		Weight = 1,
		Duration = 75,
		Banishes = 4,
		AppearEvery = 6, -- seconds between appearances
		VisibleTime = 3,
		RewardGems = 4,
	},
}

-- Anomaly intro cutscenes (client: UI/Cutscene). Creatures wait this long
-- before they act. Style picks the camera move; Tint colours the screen.
Config.Cutscene = {
	Length = 4,
	Shots = {
		GravityDistortion = { Style = "tilt", Tint = Color3.fromRGB(150, 180, 255) },
		OverheatCrisis = { Style = "push", Tint = Color3.fromRGB(255, 140, 80) },
		MimicCustomer = { Style = "glitch", Tint = Color3.fromRGB(190, 120, 255) },
		Brute = { Style = "low", Tint = Color3.fromRGB(255, 90, 90) },
		RatSwarm = { Style = "ground", Tint = Color3.fromRGB(200, 170, 120) },
		Gremlin = { Style = "whip", Tint = Color3.fromRGB(120, 255, 140) },
		Phantom = { Style = "blackout", Tint = Color3.fromRGB(170, 200, 255) },
	},
}

-- Repairs: broken machines can't be used until repaired for a share of their price.
Config.Repair = {
	ExplodeFraction = 0.5, -- ovens that explode after an unchecked Overheat
	DamageFraction = 0.25, -- machines smashed by anomalies
	HoldTime = 2, -- seconds to hold the Repair prompt
	OverheatWarning = 10, -- last seconds of an Overheat where ovens flash
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
	HopperCap = 4, -- recipe sets the hopper can hold (players load them from the bag)
	TrayCap = 2, -- batters / cakes waiting between steps
	AutoLoadInterval = 1, -- Full Automation pass: seconds between auto-loads per line
}

-- Auto-delete (per player, saved in PlayerData.Settings). A kind's threshold n
-- deletes anything of rarity < n (0 = off). KeepSpecial spares traits/mutations.
Config.AutoDelete = {
	Kinds = { "Ingredient", "Batter", "Cake" },
	Labels = { Ingredient = "🥚 Ingredients", Batter = "🥣 Batters", Cake = "🍰 Cakes" },
}

-- Storage upgrades (levelled, paid with Cash; cost = BaseCost * Growth ^ level).
Config.Storage = {
	Order = { "Bag", "Rack" },
	Bag = { Icon = "🎒", DisplayName = "Bigger Bag", PerLevel = 10, MaxLevel = 6, BaseCost = 2000, Growth = 2.2, Format = "+%d bag slots" },
	Rack = { Icon = "🗄️", DisplayName = "Bigger Cake Rack", PerLevel = 3, MaxLevel = 5, BaseCost = 25000, Growth = 2, Format = "+%d rack slots (needs Auto-Restock)" },
}

-- Game Passes. Create them on the Creator Dashboard (Monetization > Passes)
-- and paste each ID here. ID 0 = not set up yet.
-- FullAutomation: hoppers load themselves from your bag (cheapest unpinned
-- ingredients first) and the pantry auto-rolls (normal cooldown and odds) when
-- the bag can't fill a hopper. It only automates free actions.
Config.GamePasses = {
	FullAutomation = { Id = 0, Label = "🤖 Full Automation", Description = "Hoppers load themselves from your bag" },
}

-- Gem upgrades (levelled; cost = BaseCost * CostGrowth ^ level) -------------------
-- Luck shifts roll odds, so it is hidden/disabled for players whose
-- PolicyService says paid random items are restricted.
Config.GemUpgrades = {
	Order = { "Income", "BakeSpeed", "Luck" },
	Income = { Icon = "💰", DisplayName = "Income", PerLevel = 0.10, MaxLevel = 10, BaseCost = 10, CostGrowth = 1.6, Format = "+%d%% cake prices" },
	BakeSpeed = { Icon = "⏱️", DisplayName = "Baking Speed", PerLevel = 0.05, MaxLevel = 10, BaseCost = 8, CostGrowth = 1.6, Format = "-%d%% bake time" },
	Luck = { Icon = "🍀", DisplayName = "Luck", PerLevel = 0.05, MaxLevel = 10, BaseCost = 12, CostGrowth = 1.6, Format = "+%d%% luck (better roll odds)" },
}

-- Gems from selling rare cakes: { chance, amount } by cake rarity index.
Config.RareCakeGems = {
	[4] = { 0.15, 1 }, -- Epic
	[5] = { 0.5, 2 }, -- Legendary
	[6] = { 1, 5 }, -- Mythic
	[7] = { 1, 12 }, -- Divine
	[8] = { 1, 40 }, -- Anomalous
}

-- Robux developer products. Create these on the Creator Dashboard
-- (Monetization > Developer Products) and paste each product's ID here.
-- ID 0 = not set up yet (the button says so and nothing can be bought).
Config.Products = {
	{ Key = "GemsSmall", Id = 0, Kind = "Gems", Amount = 100, Label = "💎 100 Gems" },
	{ Key = "GemsMedium", Id = 0, Kind = "Gems", Amount = 550, Label = "💎 550 Gems" },
	{ Key = "GemsLarge", Id = 0, Kind = "Gems", Amount = 1200, Label = "💎 1,200 Gems" },
	{ Key = "CashSmall", Id = 0, Kind = "Cash", Amount = 5000, Label = "$ 5,000 Cash" },
	{ Key = "CashMedium", Id = 0, Kind = "Cash", Amount = 50000, Label = "$ 50,000 Cash" },
	{ Key = "CashLarge", Id = 0, Kind = "Cash", Amount = 500000, Label = "$ 500,000 Cash" },
}
Config.ReceiptHistoryLimit = 200 -- receipt IDs remembered per player (dedupe)

-- Gems --------------------------------------------------------------------------
Config.Gems = {
	ShieldPrice = 5,
	MaxShields = 3,
	BoostPrice = 3,
	BoostSeconds = 300,
	BoostBakeMult = 0.5, -- 2x bake speed while boosted
	ExtinguishReward = 1,
	MimicReward = 3,
	PanDamage = 1, -- Frying Pan hit
	PanRange = 12, -- studs
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
	BigRoll = "rbxasset://sounds/electronicpingshort.wav", -- Legendary+ roll fanfare (pitched)
	Explosion = "rbxasset://sounds/collide.wav",
	Repair = "rbxasset://sounds/clickfast.wav",
	AnomalySting = "rbxasset://sounds/electronicpingshort.wav", -- cutscene sting (pitched down)
	Achievement = "rbxasset://sounds/electronicpingshort.wav",
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
