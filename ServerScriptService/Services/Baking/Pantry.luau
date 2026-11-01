--!strict
-- Pantry: which ingredient bins show, the unlocked-recipe mirror for the client,
-- and the Rare+ roll pop-up / Mythic+ pillar at the pantry.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Services = script:FindFirstAncestor("Services") :: Folder
local Assets = require(Services.World.Assets)
local BakeUtil = require(Services.Baking.BakeUtil)
local PlotManager = require(Services.Core.PlotManager)
local VFX = require(Services.Effects.VFX)
local WorldBuilder = require(Services.World.WorldBuilder)

local notify, getItem, hasUnlockFn = BakeUtil.notify, BakeUtil.getItem, BakeUtil.hasUnlockFn

local Pantry = {}

local function getBin(plot: Model, ingredient: string): Model?
	local pantry = getItem(plot, "IngredientCrate")
	local bins = pantry and pantry:FindFirstChild("Bins")
	return bins and bins:FindFirstChild(ingredient) :: Model?
end

-- Shows only the bins whose ingredient some unlocked recipe uses, and mirrors the
-- unlocked recipe list onto the player for the client-side mixer preview.
function Pantry.RefreshPantry(plot: Model)
	local owner = PlotManager.GetOwner(plot)
	local pantry = getItem(plot, "IngredientCrate")
	if owner then
		owner:SetAttribute("UnlockedRecipes", table.concat(Recipes.Unlocked(hasUnlockFn(owner)), ","))
	end
	if not pantry or not pantry:GetAttribute("Visible") then
		return
	end
	local needed = if owner then Recipes.NeededIngredients(hasUnlockFn(owner)) else {}
	for _, ingredient in Recipes.IngredientOrder do
		local bin = getBin(plot, ingredient)
		if bin then
			WorldBuilder.SetVisible(bin, needed[ingredient] == true)
		end
	end
end

-- Roll spectacle: Rare+ ingredients pop out of the pantry (everyone sees it);
-- Mythic+ also fire a pillar of light and a server-wide announcement.
local function showPantryRoll(player: Player, items: { any })
	local plot = PlotManager.GetPlot(player)
	local pantry = plot and getItem(plot, "IngredientCrate")
	local crate = pantry and pantry:FindFirstChild("Crate") :: BasePart?
	if not plot or not crate then
		return
	end
	local shown = {}
	for _, item in items do
		if item.Rarity >= 3 and not item.Deleted then
			table.insert(shown, item)
		end
	end
	for i, item in shown do
		local model = Assets.Clone("Ingredients", item.Type)
		model:ScaleTo(model:GetScale() * (1 + item.Rarity * 0.12))
		local offset = (i - (#shown + 1) / 2) * 2.6
		local cf = crate.CFrame * CFrame.new(offset, crate.Size.Y / 2 + 3, 0)
		Assets.Anchor(model, CFrame.new(cf.Position), plot)
		VFX.ApplyIngredient(model, item)
		CollectionService:AddTag(model, "FxBob") -- the client floats and spins it
		Debris:AddItem(model, 2.8)
		local tier = Rarity.Tiers[item.Rarity]
		if item.Rarity >= Rarity.MYTHIC then
			VFX.Pillar(cf.Position, tier.Color, 4)
			VFX.Burst(cf.Position, "Rebirth", tier.Color)
			local info = Recipes.Ingredients[item.Type]
			for _, other in Players:GetPlayers() do
				notify(other, `⭐ {player.DisplayName} rolled {string.upper(tier.Name)} {info and info.Icon or ""} {item.Type}!`)
			end
		end
	end
end

Pantry.ShowRoll = showPantryRoll

return Pantry
