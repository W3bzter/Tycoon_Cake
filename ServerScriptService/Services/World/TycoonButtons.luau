--!strict
-- Fixed upgrades (Shared/PlotLayout): purchase, and showing the owned ones on the
-- owner's plot. (There are no floor buttons any more: they're bought from the
-- Build shop's Upgrades tab, Build/BuildService.BuyUpgrade.) Purchases are stored
-- in UnlockedUpgrades and replayed whenever the owner claims a plot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
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

local function resetPlot(plot: Model)
	for _, upgrade in PlotLayout.Upgrades do
		showItem(plot, upgrade.Id, false)
	end
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
	unlockedEvent:Fire(player, plot, upgradeId)
	return true
end

function TycoonButtons.Init()
	local function onClaimed(player: Player, plot: Model)
		resetPlot(plot)
		syncItems(plot, player)
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
