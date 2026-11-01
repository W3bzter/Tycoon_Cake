--!strict
-- The saved player data: its type and the template a brand-new player starts
-- with. DataManager.reconcile fills any missing field into old saves, so a new
-- field only needs adding here (type + template).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

export type PlayerData = {
	Cash: number,
	Gems: number,
	UnlockedUpgrades: { [string]: boolean },
	ShieldCharges: number, -- Anomaly Shields (Gem shop)
	BoostEndsAt: number, -- os.time() when the Bake Boost runs out
	Stats: { [string]: number },
	Bag: { any },
	NextItemId: number,
	MixRecipe: string,
	GemUpgrades: { [string]: number },
	Receipts: { string },
	Settings: { AutoDelete: { [string]: number }, KeepSpecial: boolean, AutoRoll: boolean? }, -- AutoRoll: Auto-Roller on/off (nil = on)
	Storage: { [string]: number },
	LinesEnabled: { boolean },
	LineRecipes: { string },
	Hoppers: { { any } },
	Rebirths: number,
	Achievements: { [string]: number },
	Broken: { [string]: number },
	Build: { Owned: { [string]: number }, Placed: { [string]: any }, NextUid: number, Migrated: boolean, MigratedShop: boolean, LegacyOvens: number },
}

local TEMPLATE: PlayerData = {
	Cash = Config.StartingCash,
	Gems = 0,
	UnlockedUpgrades = {},
	ShieldCharges = 0,
	BoostEndsAt = 0,
	-- Lifetime counters (achievements read these; see Shared/Achievements).
	Stats = {
		CakesSold = 0,
		CakesBaked = 0,
		TotalEarned = 0,
		IngredientsRolled = 0,
		BestRoll = 0, -- highest rarity index ever rolled
		Mutations = 0,
		PerfectMixes = 0,
		AnomaliesStopped = 0,
		OvensSaved = 0,
		MimicsStopped = 0,
		BrutesDefeated = 0,
		RatsSquashed = 0,
		GremlinsCaught = 0,
		PhantomsBanished = 0,
		Repairs = 0,
		Explosions = 0,
	},
	Bag = {}, -- rolled ingredients (Shared/Rarity Item)
	NextItemId = 1,
	MixRecipe = "Best", -- "Best" or a cake type
	GemUpgrades = { Income = 0, BakeSpeed = 0, Luck = 0 },
	Receipts = {}, -- recent Robux receipt IDs, oldest first (dedupe; see RobuxShop)
	-- Auto-delete thresholds per kind (0 = off; n = delete rarity < n).
	Settings = { AutoDelete = { Ingredient = 0, Batter = 0, Cake = 0 }, KeepSpecial = true },
	Storage = { Bag = 0, Rack = 0 }, -- storage upgrade levels (Config.Storage)
	LinesEnabled = { true, true, true }, -- production line on/off switches
	LineRecipes = { "Vanilla", "Vanilla", "Vanilla" },
	-- Ingredient sets loaded into each line's hopper: { {Recipe, Items} } per line.
	-- Saved so loaded ingredients are never lost when you leave.
	Hoppers = { {}, {}, {} },
	Rebirths = 0,
	Achievements = {}, -- id -> os.time() unlocked
	Broken = {}, -- machine id -> repair cost (Cash); re-applied on join
	-- Build mode: unplaced items (id -> count), placed items (uid -> {Id, GX, GZ, Rot}).
	Build = { Owned = {}, Placed = {}, NextUid = 1, Migrated = false, MigratedShop = false, LegacyOvens = 0 },
}

return {
	TEMPLATE = TEMPLATE,
}
