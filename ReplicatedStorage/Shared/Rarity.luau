--!strict
-- Ingredient rarities, traits and cake-value maths. Shared so the client can
-- show odds and values exactly as the server computes them.
--
-- Rolls are always free (never sold for Robux or Gems). Luck (Phase 5 Gem
-- upgrade) shifts weight towards higher rarities: weight_i * (1 + luck)^(i - 1).

export type Item = {
	Id: number,
	Type: string, -- ingredient name (Recipes.Ingredients)
	Rarity: number, -- index into Rarity.Tiers
	Traits: { string },
	Pinned: boolean?, -- used first when mixing
}

local CakeRolls = require(script.Parent:WaitForChild("CakeRolls"))
export type CakeInfo = CakeRolls.CakeInfo
export type BakeContext = CakeRolls.BakeContext

local Rarity = {}

-- Fx: how loud the roll reveal / world effects get for this tier
-- ("none" | "glow" | "shake" | "rays" | "mythic" | "divine" | "anomalous" | "void" | "celestial").
-- Void and Celestial play a full-screen cutscene (UI/Effects/RarityCutscene).
Rarity.Tiers = {
	{ Name = "Common", Color = Color3.fromRGB(205, 205, 215), Mult = 1, Weight = 60, Glow = 0, Fx = "none" },
	{ Name = "Uncommon", Color = Color3.fromRGB(90, 220, 120), Mult = 1.5, Weight = 25, Glow = 0.5, Fx = "none" },
	{ Name = "Rare", Color = Color3.fromRGB(80, 160, 255), Mult = 2.5, Weight = 10, Glow = 1, Fx = "glow" },
	{ Name = "Epic", Color = Color3.fromRGB(180, 90, 255), Mult = 5, Weight = 4, Glow = 1.5, Fx = "shake" },
	{ Name = "Legendary", Color = Color3.fromRGB(255, 180, 40), Mult = 12, Weight = 0.9, Glow = 2, Fx = "rays" },
	{ Name = "Mythic", Color = Color3.fromRGB(255, 60, 140), Mult = 40, Weight = 0.1, Glow = 3, Fx = "mythic" },
	{ Name = "Divine", Color = Color3.fromRGB(255, 245, 190), Mult = 100, Weight = 0.02, Glow = 4, Fx = "divine" },
	{ Name = "Anomalous", Color = Color3.fromRGB(40, 255, 200), Mult = 300, Weight = 0.005, Glow = 5, Fx = "anomalous" },
	{ Name = "Void", Color = Color3.fromRGB(140, 60, 255), Mult = 1000, Weight = 0.0007, Glow = 6, Fx = "void" }, -- blackout cutscene
	{ Name = "Celestial", Color = Color3.fromRGB(255, 255, 255), Mult = 3000, Weight = 0.00014, Glow = 7, Fx = "celestial" }, -- white-out cutscene
}
Rarity.MYTHIC = 6 -- tiers at or above this index get the big effects

-- Each trait is rolled independently.
Rarity.Traits = {
	Golden = { Icon = "🌟", Chance = 0.02, Mult = 2, Description = "x2 value" },
	Fresh = { Icon = "🌿", Chance = 0.10, Mult = 1.2, Description = "x1.2 value, bakes 20% faster" },
	Organic = { Icon = "🍃", Chance = 0.08, Mult = 1.3, Description = "x1.3 value" },
	AnomalyTouched = { Icon = "👁️", Chance = 0.02, Mult = 3, Description = "x3 value, but Mimics want it" },
}
Rarity.TraitOrder = { "Golden", "Fresh", "Organic", "AnomalyTouched" }

-- Mix quality grades (Phase 4 minigame). Automated mixers always make "Good".
Rarity.Quality = {
	Perfect = 1.5,
	Great = 1.25,
	Good = 1,
	Sloppy = 0.75,
}

Rarity.FreshBakeMult = 0.8

-- Percent chance of each tier for a given luck value.
function Rarity.Odds(luck: number?): { number }
	local l = math.max(0, luck or 0)
	local weights, total = {}, 0
	for i, tier in Rarity.Tiers do
		local w = tier.Weight * (1 + l) ^ (i - 1)
		weights[i] = w
		total += w
	end
	for i, w in weights do
		weights[i] = w / total * 100
	end
	return weights
end

function Rarity.RollRarity(luck: number?, rng: Random?): number
	local odds = Rarity.Odds(luck)
	local roll = (rng or Random.new()):NextNumber() * 100
	for i, pct in odds do
		roll -= pct
		if roll <= 0 then
			return i
		end
	end
	return 1
end

function Rarity.RollTraits(rng: Random?): { string }
	local r = rng or Random.new()
	local traits = {}
	for _, name in Rarity.TraitOrder do
		if r:NextNumber() < Rarity.Traits[name].Chance then
			table.insert(traits, name)
		end
	end
	return traits
end

-- How much an ingredient multiplies its cake's value.
function Rarity.Factor(item: Item): number
	local f = Rarity.Tiers[item.Rarity].Mult
	for _, trait in item.Traits do
		local t = Rarity.Traits[trait]
		if t then
			f *= t.Mult
		end
	end
	return f
end

-- Cake value = recipe price x average ingredient factor x mix quality.
function Rarity.MakeCake(cakeType: string, basePrice: number, items: { Item }, quality: string?): CakeInfo
	local factorSum, raritySum = 0, 0
	local anomaly, fresh = false, false
	for _, item in items do
		factorSum += Rarity.Factor(item)
		raritySum += item.Rarity
		anomaly = anomaly or table.find(item.Traits, "AnomalyTouched") ~= nil
		fresh = fresh or table.find(item.Traits, "Fresh") ~= nil
	end
	local n = math.max(1, #items)
	local grade = quality or "Good"
	return {
		Type = cakeType,
		Value = math.max(1, math.floor(basePrice * (factorSum / n) * (Rarity.Quality[grade] or 1) + 0.5)),
		Rarity = math.clamp(math.floor(raritySum / n + 0.5), 1, #Rarity.Tiers),
		Anomaly = anomaly,
		Fresh = fresh,
		Quality = grade,
	}
end

-- Bake-time rolls (Shared/CakeRolls), re-exported.
Rarity.CakeTraits = CakeRolls.CakeTraits
Rarity.CakeTraitOrder = CakeRolls.CakeTraitOrder
Rarity.Mutations = CakeRolls.Mutations
Rarity.MutationOrder = CakeRolls.MutationOrder
Rarity.MutationChance = CakeRolls.MutationChance
Rarity.RollBake = CakeRolls.RollBake
Rarity.AddCakeTrait = CakeRolls.AddCakeTrait
Rarity.CakeBadges = CakeRolls.CakeBadges

-- Anything with a trait or a mutation counts as "special" (auto-delete can keep it).
function Rarity.IsSpecial(thing: any): boolean
	return (thing.Traits ~= nil and #thing.Traits > 0) or thing.Mutation ~= nil
end

function Rarity.Name(index: number): string
	local tier = Rarity.Tiers[index]
	return if tier then tier.Name else "Common"
end

return Rarity
