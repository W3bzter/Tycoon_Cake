--!strict
-- Shows what the mixer will make from the ingredients you're carrying, by
-- rewriting the mixer prompt's text locally (prompt text is shared on the
-- server, but a client-side change only affects this player's view).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Recipes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Recipes"))

local RecipePreview = {}

local function heldIngredients(player: Player): { [string]: number }
	local held: { [string]: number } = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, tool in (container :: Instance):GetChildren() do
				if tool:IsA("Tool") and tool:GetAttribute("ItemKind") == "Ingredient" then
					local name = tool:GetAttribute("Variant") :: string?
					if name then
						held[name] = (held[name] or 0) + 1
					end
				end
			end
		end
	end
	return held
end

local function refresh(player: Player)
	local plotName = player:GetAttribute("PlotName")
	local plots = workspace:FindFirstChild("Plots")
	local plot = plotName and plots and plots:FindFirstChild(plotName :: string)
	local mixer = plot and plot:FindFirstChild("Items") and plot.Items:FindFirstChild("Mixer")
	local prompt = mixer and mixer:FindFirstChild("Prompt", true) :: ProximityPrompt?
	if not prompt then
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
	local best = Recipes.BestRecipe(heldIngredients(player), hasUnlock)
	if best then
		local cake = Recipes.Cakes[best]
		prompt.ActionText = `Mix → {cake.Icon} {(cake.DisplayName:gsub(" Cake", ""))} Batter`
	else
		prompt.ActionText = "Mix (need a recipe's ingredients)"
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
