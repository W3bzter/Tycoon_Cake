--!strict
-- Small helpers shared by the Baking modules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Services = script:FindFirstAncestor("Services") :: Folder
local DataManager = require(Services.Core.DataManager)
local Remotes = require(Services.Core.Remotes)

local BakeUtil = {}

function BakeUtil.notify(player: Player, message: string)
	Remotes.Get("Notify"):FireClient(player, message)
end

function BakeUtil.getItem(plot: Model, id: string): Model?
	local items = plot:FindFirstChild("Items")
	return items and items:FindFirstChild(id) :: Model?
end

function BakeUtil.getPrompt(item: Instance): ProximityPrompt?
	return item:FindFirstChild("Prompt", true) :: ProximityPrompt?
end

function BakeUtil.isNear(player: Player, part: BasePart, prompt: ProximityPrompt): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	return (root.Position - part.Position).Magnitude <= prompt.MaxActivationDistance + Config.InteractSlack
end

function BakeUtil.hasUnlockFn(player: Player): (string) -> boolean
	return function(id)
		return DataManager.HasUnlock(player, id)
	end
end

function BakeUtil.cakeName(cakeType: string?): string
	local cake = cakeType and Recipes.Cakes[cakeType]
	return if cake then cake.DisplayName else "Cake"
end

-- Every machine/item model on a plot: fixed ones (plot.Items) and placed ones
-- (plot.Placed, Build mode).
function BakeUtil.machines(plot: Model): { Model }
	local list = {}
	for _, folderName in { "Items", "Placed" } do
		local folder = plot:FindFirstChild(folderName)
		for _, child in (if folder then folder:GetChildren() else {}) do
			if child:IsA("Model") then
				table.insert(list, child)
			end
		end
	end
	return list
end

-- A machine by model name ("Oven_3", "IngredientCrate") or catalog id ("Oven").
function BakeUtil.findMachine(plot: Model, key: string): Model?
	local byName = BakeUtil.getItem(plot, key)
	if byName then
		return byName
	end
	local placed = plot:FindFirstChild("Placed")
	local named = placed and placed:FindFirstChild(key)
	if named and named:IsA("Model") then
		return named
	end
	for _, model in BakeUtil.machines(plot) do
		if model:GetAttribute("CatalogId") == key then
			return model
		end
	end
	return nil
end

-- What a model is: its catalog id (placed) or its fixed upgrade id.
function BakeUtil.idOf(model: Model): string
	return (model:GetAttribute("CatalogId") :: string?) or model.Name
end

return BakeUtil
