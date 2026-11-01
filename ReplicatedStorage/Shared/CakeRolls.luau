--!strict
-- Bake-time rolls: cake traits, mutations and their value maths (RollBake).
-- Rarity re-exports everything here, so code can keep using Rarity.X.

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

local CakeRolls = {}

-- Cake traits (rolled at bake time) ------------------------------------------------------
-- Each rolled independently. Chance multipliers come from the bake context.
CakeRolls.CakeTraits = {
	Fluffy = { Icon = "☁️", Chance = 0.12, Mult = 1.25, Description = "x1.25 value (Perfect/Great mixes are fluffier)" },
	Sprinkled = { Icon = "🎊", Chance = 0.10, Mult = 1.2, Description = "x1.2 value" },
	Glazed = { Icon = "✨", Chance = 0.08, Mult = 1.4, Description = "x1.4 value" },
	GoldenCrust = { Icon = "🥇", Chance = 0.015, Mult = 2, Description = "x2 value" },
	Cursed = { Icon = "💀", Chance = 0.01, Mult = 3, Description = "x3 value, but anomalies want it (more likely during anomalies)" },
	Burnt = { Icon = "🔥", Chance = 0.04, Mult = 0.6, Description = "x0.6 value (Sloppy mixes and overheated ovens burn)" },
	Nibbled = { Icon = "🐀", Chance = 0, Mult = 0.5, Description = "x0.5 value (a rat got to it)" },
	Spooked = { Icon = "👻", Chance = 0, Mult = 0.7, Description = "x0.7 value (a Phantom haunted it)" },
}
CakeRolls.CakeTraitOrder = { "Fluffy", "Sprinkled", "Glazed", "GoldenCrust", "Cursed", "Burnt", "Nibbled", "Spooked" }

-- Mutations: at most one per cake. Weight picks which one, once a cake mutates.
CakeRolls.Mutations = {
	Molten = { Icon = "🌋", Color = Color3.fromRGB(255, 110, 30), Mult = 3, Weight = 30 },
	Frozen = { Icon = "❄️", Color = Color3.fromRGB(140, 220, 255), Mult = 3, Weight = 30 },
	Electric = { Icon = "⚡", Color = Color3.fromRGB(255, 240, 80), Mult = 4, Weight = 20 },
	Galaxy = { Icon = "🌌", Color = Color3.fromRGB(150, 90, 255), Mult = 6, Weight = 12 },
	Rainbow = { Icon = "🌈", Color = Color3.fromRGB(255, 120, 200), Mult = 8, Weight = 8 },
	Void = { Icon = "🕳️", Color = Color3.fromRGB(60, 0, 90), Mult = 15, Weight = 10, AnomalyOnly = true },
}
CakeRolls.MutationOrder = { "Molten", "Frozen", "Electric", "Galaxy", "Rainbow", "Void" }
CakeRolls.MutationBaseChance = 0.03 -- tune to 1 in Studio to see every effect

export type BakeContext = {
	AnomalyActive: boolean?, -- an anomaly is running: x3 mutations, Void possible, more Cursed
	Overheated: boolean?, -- the oven overheated during this bake: likely Burnt
	Rebirths: number?, -- +10% mutation chance per rebirth
	EventMult: number?, -- a mutation event is running (Baking/MutationEvents): x this
}

-- Chance this cake mutates (shown in the UI too).
function CakeRolls.MutationChance(rarity: number, ctx: BakeContext?): number
	local c = ctx or {}
	local chance = CakeRolls.MutationBaseChance * (1 + 0.15 * (rarity - 1))
	if c.AnomalyActive then
		chance *= 3
	end
	chance *= 1 + 0.1 * (c.Rebirths or 0)
	chance *= c.EventMult or 1
	return math.min(chance, 1)
end

-- Rolls bake-time traits and a mutation onto a freshly baked cake (returns a copy).
function CakeRolls.RollBake(info: CakeInfo, ctx: BakeContext?, rng: Random?): CakeInfo
	local r = rng or Random.new()
	local c = ctx or {}
	local out = table.clone(info)
	local traits = table.clone(info.Traits or {})
	local function roll(name: string, mult: number)
		if not table.find(traits, name) and r:NextNumber() < CakeRolls.CakeTraits[name].Chance * mult then
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
	if not mutation and r:NextNumber() < CakeRolls.MutationChance(info.Rarity, c) then
		local total = 0
		for _, name in CakeRolls.MutationOrder do
			local m = CakeRolls.Mutations[name]
			if not m.AnomalyOnly or c.AnomalyActive then
				total += m.Weight
			end
		end
		local pickAt = r:NextNumber() * total
		for _, name in CakeRolls.MutationOrder do
			local m = CakeRolls.Mutations[name]
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
			value *= CakeRolls.CakeTraits[name].Mult
		end
	end
	if mutation and mutation ~= info.Mutation then
		value *= CakeRolls.Mutations[mutation].Mult
	end
	out.Traits = traits
	out.Mutation = mutation
	out.Anomaly = info.Anomaly or table.find(traits, "Cursed") ~= nil
	out.Value = math.max(1, math.floor(value + 0.5))
	return out
end

-- Adds a cake trait after baking (e.g. Nibbled) and applies its value change.
function CakeRolls.AddCakeTrait(info: CakeInfo, name: string): CakeInfo
	local out = table.clone(info)
	local traits = table.clone(info.Traits or {})
	if not table.find(traits, name) then
		table.insert(traits, name)
		out.Value = math.max(1, math.floor(info.Value * CakeRolls.CakeTraits[name].Mult + 0.5))
	end
	out.Traits = traits
	out.Anomaly = out.Anomaly or name == "Cursed"
	return out
end

-- "✨☁️ 🌌" style badge string for a cake.
function CakeRolls.CakeBadges(info: CakeInfo): string
	local s = ""
	for _, name in info.Traits or {} do
		local t = CakeRolls.CakeTraits[name]
		s ..= if t then t.Icon else ""
	end
	if info.Mutation and CakeRolls.Mutations[info.Mutation] then
		s ..= (if s ~= "" then " " else "") .. CakeRolls.Mutations[info.Mutation].Icon .. info.Mutation
	end
	return s
end

return CakeRolls
