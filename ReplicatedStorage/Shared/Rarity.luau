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

export type CakeInfo = {
	Type: string, -- cake type (Recipes.Cakes)
	Value: number, -- final sale price before shop multipliers
	Rarity: number,
	Anomaly: boolean, -- Anomaly-touched: Mimics go for it first
	Fresh: boolean, -- bakes faster
	Quality: string, -- mix grade (Phase 4)
	Traits: { string }?, -- cake traits rolled at bake time (Phase 7)
	Mutation: string?, -- at most one mutation, rolled at bake time (Phase 7)
}

local Rarity = {}

-- Fx: how loud the roll reveal / world effects get for this tier
-- ("none" | "glow" | "shake" | "rays" | "mythic" | "divine" | "anomalous").
Rarity.Tiers = {
	{ Name = "Common", Color = Color3.fromRGB(205, 205, 215), Mult = 1, Weight = 60, Glow = 0, Fx = "none" },
	{ Name = "Uncommon", Color = Color3.fromRGB(90, 220, 120), Mult = 1.5, Weight = 25, Glow = 0.5, Fx = "none" },
	{ Name = "Rare", Color = Color3.fromRGB(80, 160, 255), Mult = 2.5, Weight = 10, Glow = 1, Fx = "glow" },
	{ Name = "Epic", Color = Color3.fromRGB(180, 90, 255), Mult = 5, Weight = 4, Glow = 1.5, Fx = "shake" },
	{ Name = "Legendary", Color = Color3.fromRGB(255, 180, 40), Mult = 12, Weight = 0.9, Glow = 2, Fx = "rays" },
	{ Name = "Mythic", Color = Color3.fromRGB(255, 60, 140), Mult = 40, Weight = 0.1, Glow = 3, Fx = "mythic" },
	{ Name = "Divine", Color = Color3.fromRGB(255, 245, 190), Mult = 100, Weight = 0.02, Glow = 4, Fx = "divine" },
	{ Name = "Anomalous", Color = Color3.fromRGB(40, 255, 200), Mult = 300, Weight = 0.005, Glow = 5, Fx = "anomalous" },
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

-- Cake traits (rolled at bake time) ------------------------------------------------------
-- Each rolled independently. Chance multipliers come from the bake context.
Rarity.CakeTraits = {
	Fluffy = { Icon = "☁️", Chance = 0.12, Mult = 1.25, Description = "x1.25 value (Perfect/Great mixes are fluffier)" },
	Sprinkled = { Icon = "🎊", Chance = 0.10, Mult = 1.2, Description = "x1.2 value" },
	Glazed = { Icon = "✨", Chance = 0.08, Mult = 1.4, Description = "x1.4 value" },
	GoldenCrust = { Icon = "🥇", Chance = 0.015, Mult = 2, Description = "x2 value" },
	Cursed = { Icon = "💀", Chance = 0.01, Mult = 3, Description = "x3 value, but anomalies want it (more likely during anomalies)" },
	Burnt = { Icon = "🔥", Chance = 0.04, Mult = 0.6, Description = "x0.6 value (Sloppy mixes and overheated ovens burn)" },
	Nibbled = { Icon = "🐀", Chance = 0, Mult = 0.5, Description = "x0.5 value (a rat got to it)" },
}
Rarity.CakeTraitOrder = { "Fluffy", "Sprinkled", "Glazed", "GoldenCrust", "Cursed", "Burnt", "Nibbled" }

-- Mutations: at most one per cake. Weight picks which one, once a cake mutates.
Rarity.Mutations = {
	Molten = { Icon = "🌋", Color = Color3.fromRGB(255, 110, 30), Mult = 3, Weight = 30 },
	Frozen = { Icon = "❄️", Color = Color3.fromRGB(140, 220, 255), Mult = 3, Weight = 30 },
	Electric = { Icon = "⚡", Color = Color3.fromRGB(255, 240, 80), Mult = 4, Weight = 20 },
	Galaxy = { Icon = "🌌", Color = Color3.fromRGB(150, 90, 255), Mult = 6, Weight = 12 },
	Rainbow = { Icon = "🌈", Color = Color3.fromRGB(255, 120, 200), Mult = 8, Weight = 8 },
	Void = { Icon = "🕳️", Color = Color3.fromRGB(60, 0, 90), Mult = 15, Weight = 10, AnomalyOnly = true },
}
Rarity.MutationOrder = { "Molten", "Frozen", "Electric", "Galaxy", "Rainbow", "Void" }
Rarity.MutationBaseChance = 0.03 -- tune to 1 in Studio to see every effect

export type BakeContext = {
	AnomalyActive: boolean?, -- an anomaly is running: x3 mutations, Void possible, more Cursed
	Overheated: boolean?, -- the oven overheated during this bake: likely Burnt
	Rebirths: number?, -- +10% mutation chance per rebirth
}

-- Chance this cake mutates (shown in the UI too).
function Rarity.MutationChance(rarity: number, ctx: BakeContext?): number
	local c = ctx or {}
	local chance = Rarity.MutationBaseChance * (1 + 0.15 * (rarity - 1))
	if c.AnomalyActive then
		chance *= 3
	end
	chance *= 1 + 0.1 * (c.Rebirths or 0)
	return math.min(chance, 1)
end

-- Rolls bake-time traits and a mutation onto a freshly baked cake (returns a copy).
function Rarity.RollBake(info: CakeInfo, ctx: BakeContext?, rng: Random?): CakeInfo
	local r = rng or Random.new()
	local c = ctx or {}
	local out = table.clone(info)
	local traits = table.clone(info.Traits or {})
	local function roll(name: string, mult: number)
		if not table.find(traits, name) and r:NextNumber() < Rarity.CakeTraits[name].Chance * mult then
			table.insert(traits, name)
		end
	end
	local q = info.Quality
	if c.Overheated or q == "Sloppy" then
		roll("Burnt", if c.Overheated then 12 else 8)
	end
	local burnt = table.find(traits, "Burnt") ~= nil
	if not burnt then
		roll("Fluffy", if q == "Perfect" then 2.5 elseif q == "Great" then 1.6 else 1)
		roll("GoldenCrust", 1)
	end
	roll("Sprinkled", 1)
	roll("Glazed", 1)
	roll("Cursed", if c.AnomalyActive then 5 else 1)
	if not burnt then
		roll("Burnt", 1)
	end

	local mutation = info.Mutation
	if not mutation and r:NextNumber() < Rarity.MutationChance(info.Rarity, c) then
		local total = 0
		for _, name in Rarity.MutationOrder do
			local m = Rarity.Mutations[name]
			if not m.AnomalyOnly or c.AnomalyActive then
				total += m.Weight
			end
		end
		local pickAt = r:NextNumber() * total
		for _, name in Rarity.MutationOrder do
			local m = Rarity.Mutations[name]
			if not m.AnomalyOnly or c.AnomalyActive then
				pickAt -= m.Weight
				if pickAt <= 0 then
					mutation = name
					break
				end
			end
		end
	end

	local value = info.Value
	for _, name in traits do
		if not table.find(info.Traits or {}, name) then -- only newly added traits change value
			value *= Rarity.CakeTraits[name].Mult
		end
	end
	if mutation and mutation ~= info.Mutation then
		value *= Rarity.Mutations[mutation].Mult
	end
	out.Traits = traits
	out.Mutation = mutation
	out.Anomaly = info.Anomaly or table.find(traits, "Cursed") ~= nil
	out.Value = math.max(1, math.floor(value + 0.5))
	return out
end

-- Adds a cake trait after baking (e.g. Nibbled) and applies its value change.
function Rarity.AddCakeTrait(info: CakeInfo, name: string): CakeInfo
	local out = table.clone(info)
	local traits = table.clone(info.Traits or {})
	if not table.find(traits, name) then
		table.insert(traits, name)
		out.Value = math.max(1, math.floor(info.Value * Rarity.CakeTraits[name].Mult + 0.5))
	end
	out.Traits = traits
	out.Anomaly = out.Anomaly or name == "Cursed"
	return out
end

-- "✨☁️ 🌌" style badge string for a cake.
function Rarity.CakeBadges(info: CakeInfo): string
	local s = ""
	for _, name in info.Traits or {} do
		local t = Rarity.CakeTraits[name]
		s ..= if t then t.Icon else ""
	end
	if info.Mutation and Rarity.Mutations[info.Mutation] then
		s ..= (if s ~= "" then " " else "") .. Rarity.Mutations[info.Mutation].Icon .. info.Mutation
	end
	return s
end

-- Anything with a trait or a mutation counts as "special" (auto-delete can keep it).
function Rarity.IsSpecial(thing: any): boolean
	return (thing.Traits ~= nil and #thing.Traits > 0) or thing.Mutation ~= nil
end

function Rarity.Name(index: number): string
	local tier = Rarity.Tiers[index]
	return if tier then tier.Name else "Common"
end

return Rarity
