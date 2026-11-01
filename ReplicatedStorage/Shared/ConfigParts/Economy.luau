--!strict
-- Economy: Gems, Gem upgrades, rare-cake Gems, Robux products, Game Passes.
-- Merged into Shared/Config (read it as Config.<Name>).

local Config = {}

-- Game Passes. Create them on the Creator Dashboard (Monetization > Passes)
-- and paste each ID here. ID 0 = not set up yet.
-- FullAutomation: an Auto-Baker whose recipe your bag can't make rolls its own
-- ingredients (normal cooldown and odds) instead of waiting.
-- It only automates free actions.
-- RandomItems = true: the pass gives more free rolls (random items), so it is only
-- sold and only works where PolicyService allows paid random items (same gate as
-- the Luck upgrade: player attribute LuckAllowed, fails closed). Never changes odds.
-- DoubleCash / DoubleGems double what you EARN in play (sales, tips, rewards,
-- achievements), not Robux purchases.
Config.GamePasses = {
	FullAutomation = { Id = 0, Label = "🤖 Full Automation", Description = "Auto-Bakers roll their own ingredients when your bag runs out" },
	DoubleRoll = { Id = 0, Label = "🎲 2x Roll", Description = "Every roll gives 2 of each ingredient", RandomItems = true },
	InstantRoll = { Id = 0, Label = "⚡ Instant Roll", Description = "Roll again almost instantly", RandomItems = true },
	DoubleCash = { Id = 0, Label = "💵 2x Cash", Description = "Earn double Cash" },
	DoubleGems = { Id = 0, Label = "💎 2x Gems", Description = "Earn double Gems" },
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
	[9] = { 1, 120 }, -- Void
	[10] = { 1, 400 }, -- Celestial
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

return Config
