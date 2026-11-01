--!strict
-- Ingredients and cake recipes. Shared so the client can preview what the mixer
-- will make. A recipe without UnlockId is available from the start; the others
-- need that upgrade (added to the shop in Phase D).

export type Ingredient = { DisplayName: string, Icon: string, Color: Color3 }
export type Cake = {
	DisplayName: string,
	Icon: string,
	Price: number,
	Ingredients: { string },
	UnlockId: string?,
	Color: Color3, -- frosting colour, used by fallback models and UI accents
}

local Recipes = {}

Recipes.IngredientOrder = { "Flour", "Eggs", "Sugar", "Butter", "Milk", "Strawberries", "Chocolate" }

Recipes.Ingredients = {
	Flour = { DisplayName = "Flour", Icon = "🌾", Color = Color3.fromRGB(250, 248, 240) },
	Eggs = { DisplayName = "Eggs", Icon = "🥚", Color = Color3.fromRGB(255, 240, 215) },
	Sugar = { DisplayName = "Sugar", Icon = "🍬", Color = Color3.fromRGB(255, 190, 215) },
	Butter = { DisplayName = "Butter", Icon = "🧈", Color = Color3.fromRGB(255, 225, 110) },
	Milk = { DisplayName = "Milk", Icon = "🥛", Color = Color3.fromRGB(235, 245, 255) },
	Strawberries = { DisplayName = "Strawberries", Icon = "🍓", Color = Color3.fromRGB(235, 60, 80) },
	Chocolate = { DisplayName = "Chocolate", Icon = "🍫", Color = Color3.fromRGB(110, 60, 40) },
} :: { [string]: Ingredient }

-- Cheapest first.
Recipes.CakeOrder = { "Vanilla", "Chocolate", "Strawberry", "Rainbow" }

Recipes.Cakes = {
	Vanilla = {
		DisplayName = "Vanilla Cake",
		Icon = "🍰",
		Price = 25,
		Ingredients = { "Flour", "Eggs", "Sugar" },
		Color = Color3.fromRGB(255, 250, 235),
	},
	Chocolate = {
		DisplayName = "Chocolate Cake",
		Icon = "🍫",
		Price = 45,
		Ingredients = { "Flour", "Eggs", "Sugar", "Chocolate" },
		UnlockId = "RecipeChocolate",
		Color = Color3.fromRGB(120, 70, 45),
	},
	Strawberry = {
		DisplayName = "Strawberry Cake",
		Icon = "🍓",
		Price = 70,
		Ingredients = { "Flour", "Eggs", "Butter", "Strawberries" },
		UnlockId = "RecipeStrawberry",
		Color = Color3.fromRGB(255, 160, 190),
	},
	Rainbow = {
		DisplayName = "Rainbow Cake",
		Icon = "🌈",
		Price = 150,
		Ingredients = { "Flour", "Sugar", "Milk", "Strawberries", "Chocolate" },
		UnlockId = "RecipeRainbow",
		Color = Color3.fromRGB(190, 160, 255),
	},
} :: { [string]: Cake }

type HasUnlock = (id: string) -> boolean

function Recipes.IsUnlocked(cakeType: string, hasUnlock: HasUnlock): boolean
	local cake = Recipes.Cakes[cakeType]
	return cake ~= nil and (cake.UnlockId == nil or hasUnlock(cake.UnlockId))
end

function Recipes.Unlocked(hasUnlock: HasUnlock): { string }
	local list = {}
	for _, cakeType in Recipes.CakeOrder do
		if Recipes.IsUnlocked(cakeType, hasUnlock) then
			table.insert(list, cakeType)
		end
	end
	return list
end

-- Ingredients used by at least one unlocked recipe (which pantry bins to show).
function Recipes.NeededIngredients(hasUnlock: HasUnlock): { [string]: boolean }
	local set = {}
	for _, cakeType in Recipes.Unlocked(hasUnlock) do
		for _, ingredient in Recipes.Cakes[cakeType].Ingredients do
			set[ingredient] = true
		end
	end
	return set
end

-- The most valuable unlocked recipe the held ingredients satisfy, or nil.
function Recipes.BestRecipe(held: { [string]: number }, hasUnlock: HasUnlock): string?
	for i = #Recipes.CakeOrder, 1, -1 do
		local cakeType = Recipes.CakeOrder[i]
		if Recipes.IsUnlocked(cakeType, hasUnlock) then
			local ok = true
			for _, ingredient in Recipes.Cakes[cakeType].Ingredients do
				if (held[ingredient] or 0) < 1 then
					ok = false
					break
				end
			end
			if ok then
				return cakeType
			end
		end
	end
	return nil
end

return Recipes
