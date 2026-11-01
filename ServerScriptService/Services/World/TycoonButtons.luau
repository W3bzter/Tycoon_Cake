--!strict
-- Fixed upgrades (Shared/PlotLayout): purchase, and showing the owned ones on the
-- owner's plot. (There are no floor buttons any more: they're bought from the
-- Build shop's Upgrades tab, Build/BuildService.BuyUpgrade.) Purchases are stored
-- in UnlockedUpgrades and replayed whenever the owner claims a plot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildRules = require(Shared:WaitForChild("BuildRules"))
local Config = require(Shared:WaitForChild("Config"))
local PlotLayout = require(Shared:WaitForChild("PlotLayout"))

local Services = script:FindFirstAncestor("Services") :: Folder
local DataManager = require(Services.Core.DataManager)
local PlotManager = require(Services.Core.PlotManager)
local WorldBuilder = require(Services.World.WorldBuilder)

local TycoonButtons = {}

local unlockedEvent = Instance.new("BindableEvent")
TycoonButtons.UpgradeUnlocked = unlockedEvent.Event -- (player, plot, upgradeId)

local function requirementsMet(player: Player, upgrade: PlotLayout.Upgrade): boolean
	for _, id in upgrade.Requires or {} do
		if not DataManager.HasUnlock(player, id) then
			return false
		end
	end
	return true
end

-- A hand tool is "replaced" once its machine is owned (e.g. PrepTable -> Mixer).
local function isReplaced(player: Player, upgrade: PlotLayout.Upgrade): boolean
	return upgrade.ReplacedBy ~= nil and DataManager.HasUnlock(player, upgrade.ReplacedBy)
end

local function showItem(plot: Model, upgradeId: string, visible: boolean)
	local item = (plot:FindFirstChild("Items") :: Folder):FindFirstChild(upgradeId)
	if item then
		WorldBuilder.SetVisible(item, visible)
	end
end

-- Every owned, non-replaced item visible; everything else hidden.
local function syncItems(plot: Model, owner: Player)
	for _, upgrade in PlotLayout.Upgrades do
		showItem(plot, upgrade.Id, DataManager.HasUnlock(owner, upgrade.Id) and not isReplaced(owner, upgrade))
	end
end

-- The owner's bakery size stage (1 = starting size; Bigger Bakery upgrades add one).
function TycoonButtons.Stage(owner: Player?): number
	if not owner then
		return 1
	end
	return BuildRules.Stage(function(id)
		return DataManager.HasUnlock(owner, id)
	end)
end

-- The Stage of the nearest Stage-tagged model around `inst` inside `item`, if any.
local function stageAround(inst: Instance, item: Instance): number?
	local node: Instance? = inst
	while node and node ~= item do
		local stage = node:GetAttribute("Stage")
		if typeof(stage) == "number" then
			return stage
		end
		node = node.Parent
	end
	return nil
end

-- Visibility rules inside shown items:
--   Stage = n           models built per size stage (walls, awning, deck...): only the owner's stage shows
--   HideWhenOwned = id  parts that disappear once the owner has that upgrade (the
--                       panel sealing the Factory Annex doorway)
local function applyHideRules(plot: Model, owner: Player?)
	local current = TycoonButtons.Stage(owner)
	local items = plot:FindFirstChild("Items") :: Folder
	for _, item in items:GetChildren() do
		local itemVisible = item:GetAttribute("Visible") == true
		for _, d in item:GetDescendants() do
			local stage = d:GetAttribute("Stage")
			if typeof(stage) == "number" then
				WorldBuilder.SetVisible(d, itemVisible and stage == current)
			end
		end
		for _, d in item:GetDescendants() do
			local id = d:GetAttribute("HideWhenOwned")
			if typeof(id) == "string" and d:IsA("BasePart") then
				local stage = stageAround(d, item)
				local shown = itemVisible and (stage == nil or stage == current)
				WorldBuilder.SetVisible(d, shown and not (owner and DataManager.HasUnlock(owner, id)))
			end
		end
	end
end

-- Re-applies which fixed items and stage variants show (after unlocks granted in code).
function TycoonButtons.Sync(plot: Model, owner: Player)
	syncItems(plot, owner)
	applyHideRules(plot, owner)
end

local function resetPlot(plot: Model)
	for _, upgrade in PlotLayout.Upgrades do
		showItem(plot, upgrade.Id, false)
	end
	applyHideRules(plot, nil)
end

-- Lets other services announce an unlock the same way a button purchase does.
function TycoonButtons.FireUnlocked(player: Player, plot: Model, upgradeId: string)
	unlockedEvent:Fire(player, plot, upgradeId)
end

-- Server-side purchase (Build shop, SmokeTest). Returns true on success.
function TycoonButtons.TryPurchase(player: Player, plot: Model, upgradeId: string): (boolean, string?)
	if not PlotManager.IsOwner(player, plot) then
		return false, "not owner"
	end
	local upgrade = PlotLayout.Find(upgradeId)
	if not upgrade then
		return false, "unknown upgrade"
	end
	if DataManager.HasUnlock(player, upgradeId) then
		return false, "already owned"
	end
	if not requirementsMet(player, upgrade) then
		return false, "locked"
	end
	if isReplaced(player, upgrade) then
		return false, "replaced" -- e.g. the hand bowl once a Mixer is owned
	end
	if upgrade.Currency == "Gems" then
		if not DataManager.SpendGems(player, upgrade.Price) then
			return false, "insufficient gems"
		end
	elseif not DataManager.SpendCash(player, upgrade.Price) then
		return false, "insufficient cash"
	end

	DataManager.Unlock(player, upgradeId)
	showItem(plot, upgradeId, true)
	for _, other in PlotLayout.Upgrades do
		if other.ReplacedBy == upgradeId then
			showItem(plot, other.Id, false) -- the machine takes the hand tool's spot
		end
	end
	applyHideRules(plot, player)
	unlockedEvent:Fire(player, plot, upgradeId)
	return true
end

function TycoonButtons.Init()
	local function onClaimed(player: Player, plot: Model)
		-- Saves from before the Factory Annex: automation already owned gets the room free.
		if (DataManager.HasUnlock(player, "IngredientConveyor") or DataManager.HasUnlock(player, "ProductionLine2")) and not DataManager.HasUnlock(player, "FactoryAnnex") then
			DataManager.Unlock(player, "FactoryAnnex")
		end
		-- The annex doorway is in the full-size bakery's back wall.
		if DataManager.HasUnlock(player, "FactoryAnnex") then
			for _, id in Config.Building.Expansions do
				DataManager.Unlock(player, id)
			end
		end
		resetPlot(plot)
		syncItems(plot, player)
		applyHideRules(plot, player)
	end

	PlotManager.PlotClaimed:Connect(onClaimed)
	PlotManager.PlotReleased:Connect(resetPlot)

	-- Plots claimed before this service was initialised.
	for _, player in Players:GetPlayers() do
		local plot = PlotManager.GetPlot(player)
		if plot then
			onClaimed(player, plot)
		end
	end
end

return TycoonButtons
