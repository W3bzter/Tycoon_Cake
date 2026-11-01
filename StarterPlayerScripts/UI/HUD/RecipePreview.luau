--!strict
-- Shows what the mixer will make from the ingredients you're carrying, by
-- rewriting the mixer prompt's text locally (prompt text is shared on the
-- server, but a client-side change only affects this player's view).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Recipes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Recipes"))

local RecipePreview = {}

-- Ingredient counts in the bag, mirrored by the server as "Flour:2,Eggs:1,...".
local function heldIngredients(player: Player): { [string]: number }
	local held: { [string]: number } = {}
	for name, n in string.gmatch((player:GetAttribute("BagCounts") :: string?) or "", "(%w+):(%d+)") do
		held[name] = tonumber(n) or 0
	end
	return held
end

local function refresh(player: Player)
	local plotName = player:GetAttribute("PlotName")
	local plots = workspace:FindFirstChild("Plots")
	local plot = plotName and plots and plots:FindFirstChild(plotName :: string)
	local items = plot and plot:FindFirstChild("Items")
	-- Both mixing stations: the hand bowl (PrepTable) and the Mixer.
	local prompts: { ProximityPrompt } = {}
	for _, id in { "PrepTable", "Mixer" } do
		local station = items and items:FindFirstChild(id)
		local prompt = station and station:FindFirstChild("Prompt", true) :: ProximityPrompt?
		if prompt then
			table.insert(prompts, prompt)
		end
	end
	if #prompts == 0 then
		return
	end
	local unlocked: { [string]: boolean } = {}
	for name in string.gmatch((player:GetAttribute("UnlockedRecipes") :: string?) or "Vanilla", "[^,]+") do
		unlocked[name] = true
	end
	local function hasUnlock(id: string): boolean
		for cakeType, cake in Recipes.Cakes do
			if cake.UnlockId == id then
				return unlocked[cakeType] == true
			end
		end
		return false
	end
	local held = heldIngredients(player)
	local chosen = (player:GetAttribute("MixRecipe") :: string?) or "Best"
	local best: string?
	if chosen ~= "Best" and Recipes.Cakes[chosen] then
		best = chosen
		for _, ingredient in Recipes.Cakes[chosen].Ingredients do
			if (held[ingredient] or 0) < 1 then
				best = nil
			end
		end
	else
		best = Recipes.BestRecipe(held, hasUnlock)
	end
	local text = "Mix (roll ingredients first 🎲)"
	if best then
		local cake = Recipes.Cakes[best]
		text = `Mix → {cake.Icon} {(cake.DisplayName:gsub(" Cake", ""))} Batter`
	end
	for _, prompt in prompts do
		prompt.ActionText = text
	end
end

function RecipePreview.Mount(player: Player)
	task.spawn(function()
		while true do
			refresh(player)
			task.wait(0.3)
		end
	end)
end

return RecipePreview
