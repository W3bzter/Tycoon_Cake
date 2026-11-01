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

return BakeUtil
