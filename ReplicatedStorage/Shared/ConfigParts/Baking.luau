--!strict
-- Baking: ingredient rolls, mixing minigame, ovens, display, auto-delete, storage upgrades.
-- Merged into Shared/Config (read it as Config.<Name>).

local Config = {}

-- Ingredient rolls (always free; see Shared/Rarity for rarities and traits) ------
Config.Rolling = {
	BagSize = 40, -- ingredients the bag can hold
	Cooldown = 3, -- seconds between rolls (the reveal animation is ~1.5s)
	InstantCooldown = 0.75, -- with the Instant Roll game pass
}

-- Mutation events (Baking/MutationEvents): every GapMin..GapMax seconds one event
-- (picked by Weight) multiplies the bake mutation chance by Mult for Duration seconds.
Config.MutationEvents = {
	GapMin = 240,
	GapMax = 420,
	Duration = 90,
	Events = {
		{ Name = "Sugar Rush", Icon = "✨", Mult = 2, Weight = 6 },
		{ Name = "Mutation Storm", Icon = "🌪️", Mult = 3, Weight = 3 },
		{ Name = "Cosmic Bake", Icon = "🌌", Mult = 5, Weight = 1 },
	},
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
	Rack = { Icon = "🗄️", DisplayName = "More Cake Racks", PerLevel = 1, MaxLevel = 5, BaseCost = 25000, Growth = 2, Format = "+%d Cake Racks you can place" },
}

return Config
