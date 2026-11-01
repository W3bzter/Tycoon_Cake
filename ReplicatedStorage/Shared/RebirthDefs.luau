--!strict
-- Rebirth requirements (shared so the client panel shows exactly what the server
-- checks). Rebirth n+1 needs Cash (Cost) and specific cakes held in your
-- inventory (FinishedCake tools). A rebirth resets Cash and plot upgrades and
-- keeps everything else; each rebirth gives +25% cake prices (PlotStats) and +10%
-- mutation chance (Rarity.MutationChance).

local Rarity = require(script.Parent:WaitForChild("Rarity"))
local Recipes = require(script.Parent:WaitForChild("Recipes"))

export type Requirement = {
	Count: number,
	MinRarity: number?,
	Type: string?, -- cake type
	Trait: string?, -- a specific cake trait
	AnyTrait: boolean?,
	Mutation: string?, -- a specific mutation
	AnyMutation: boolean?,
}

local RebirthDefs = {}

RebirthDefs.SalePriceBonus = 0.25 -- per rebirth
RebirthDefs.BaseCost = 500000
RebirthDefs.CostGrowth = 2.5

-- Hand-written requirements for the first rebirths (index = rebirth number).
local LIST: { { Requirement } } = {
	{ { Count = 1, MinRarity = 3, AnyTrait = true } },
	{ { Count = 1, MinRarity = 4, Type = "Chocolate", Trait = "Glazed" }, { Count = 1, AnyMutation = true } },
	{ { Count = 1, Mutation = "Galaxy" }, { Count = 1, AnyMutation = true } },
	{ { Count = 1, MinRarity = 5, Type = "Strawberry", AnyMutation = true }, { Count = 2, Trait = "Fluffy" } },
	{ { Count = 1, MinRarity = 6, AnyMutation = true }, { Count = 1, Type = "Rainbow", Trait = "GoldenCrust" } },
}

-- Cash needed for the rebirth after `done` rebirths.
function RebirthDefs.Cost(done: number): number
	return math.floor(RebirthDefs.BaseCost * RebirthDefs.CostGrowth ^ done + 0.5)
end

-- Requirements for the rebirth after `done` rebirths.
function RebirthDefs.Requirements(done: number): { Requirement }
	local n = done + 1
	if LIST[n] then
		return LIST[n]
	end
	-- Generated after the hand-written ones: more, rarer mutated cakes.
	local extra = n - #LIST
	local named = { "Molten", "Frozen", "Electric", "Galaxy", "Rainbow" }
	return {
		{ Count = 1 + extra // 2, MinRarity = math.min(8, 6 + extra // 3) -- never asks for Void/Celestial, AnyMutation = true },
		{ Count = 1, Mutation = named[(n % #named) + 1] },
	}
end

local function hasTrait(info: Rarity.CakeInfo, name: string?): boolean
	return name ~= nil and table.find(info.Traits or {}, name) ~= nil
end

function RebirthDefs.Matches(req: Requirement, info: Rarity.CakeInfo): boolean
	if req.MinRarity and info.Rarity < req.MinRarity then
		return false
	end
	if req.Type and info.Type ~= req.Type then
		return false
	end
	if req.Trait and not hasTrait(info, req.Trait) then
		return false
	end
	if req.AnyTrait and #(info.Traits or {}) == 0 then
		return false
	end
	if req.Mutation and info.Mutation ~= req.Mutation then
		return false
	end
	if req.AnyMutation and info.Mutation == nil then
		return false
	end
	return true
end

local function specificity(req: Requirement): number
	local s = 0
	for _, key in { "MinRarity", "Type", "Trait", "AnyTrait", "Mutation", "AnyMutation" } do
		if (req :: any)[key] then
			s += if key == "Mutation" or key == "Trait" or key == "Type" then 2 else 1
		end
	end
	return s
end

-- Assigns held cakes to requirements (most specific requirement first, each cake
-- used once). Returns (all met, picked cake indices, per-requirement found count).
function RebirthDefs.Match(reqs: { Requirement }, cakes: { Rarity.CakeInfo }): (boolean, { number }, { number })
	local order = {}
	for i in reqs do
		table.insert(order, i)
	end
	table.sort(order, function(a, b)
		return specificity(reqs[a]) > specificity(reqs[b])
	end)
	local used: { [number]: boolean } = {}
	local picked: { number } = {}
	local found: { number } = {}
	local ok = true
	for _, i in order do
		local req = reqs[i]
		found[i] = 0
		for c, info in cakes do
			if found[i] >= req.Count then
				break
			end
			if not used[c] and RebirthDefs.Matches(req, info) then
				used[c] = true
				found[i] += 1
				table.insert(picked, c)
			end
		end
		ok = ok and found[i] >= req.Count
	end
	return ok, picked, found
end

-- "1x Epic+ Chocolate cake with ✨Glazed" style text.
function RebirthDefs.Describe(req: Requirement): string
	local parts = { `{req.Count}x` }
	if req.MinRarity then
		table.insert(parts, Rarity.Name(req.MinRarity) .. "+")
	end
	if req.Type and Recipes.Cakes[req.Type] then
		table.insert(parts, Recipes.Cakes[req.Type].Icon .. " " .. Recipes.Cakes[req.Type].DisplayName)
	else
		table.insert(parts, "cake")
	end
	local with = {}
	if req.Trait and Rarity.CakeTraits[req.Trait] then
		table.insert(with, Rarity.CakeTraits[req.Trait].Icon .. req.Trait)
	end
	if req.AnyTrait then
		table.insert(with, "any trait")
	end
	if req.Mutation and Rarity.Mutations[req.Mutation] then
		table.insert(with, Rarity.Mutations[req.Mutation].Icon .. req.Mutation .. " mutation")
	end
	if req.AnyMutation then
		table.insert(with, "any mutation")
	end
	local text = table.concat(parts, " ")
	if #with > 0 then
		text ..= " with " .. table.concat(with, " + ")
	end
	return text
end

return RebirthDefs
