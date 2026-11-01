--!strict
-- Totals the Effects of a player's unlocked upgrades (PlotLayout) plus active
-- Gem boosts into the numbers other services use. Multipliers multiply,
-- additive stats add.
--   BakeTime      x  oven time multiplier (Faster Ovens)
--   CustomerRate  x  customer spawn interval multiplier (Street Sign, Radio Ad)
--   SalePrice     x  cake price multiplier (Cake Charm, Golden Shopfront)
--   MixBatch      +  extra batters per mix (Big Mixer)
--   VIPChance     +  chance a customer is a VIP (VIP Lounge, Golden Shopfront)
--   StorageSlots  +  overflow cake storage (Auto-Restock)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PlotLayout = require(Shared:WaitForChild("PlotLayout"))
local RebirthDefs = require(Shared:WaitForChild("RebirthDefs"))

local DataManager = require(script.Parent.DataManager)

local PlotStats = {}

local MULTIPLIERS = { BakeTime = true, CustomerRate = true, SalePrice = true }

export type Stats = {
	BakeTime: number,
	CustomerRate: number,
	SalePrice: number,
	MixBatch: number,
	VIPChance: number,
	StorageSlots: number,
}

function PlotStats.Get(player: Player?): Stats
	local stats: { [string]: number } = {
		BakeTime = 1,
		CustomerRate = 1,
		SalePrice = 1,
		MixBatch = 1,
		VIPChance = 0,
		StorageSlots = 0,
	}
	if not player then
		return stats :: any
	end
	for _, upgrade in PlotLayout.Upgrades do
		if upgrade.Effects and DataManager.HasUnlock(player, upgrade.Id) then
			for key, value in upgrade.Effects do
				if MULTIPLIERS[key] then
					stats[key] *= value
				else
					stats[key] = (stats[key] or 0) + value
				end
			end
		end
	end
	if PlotStats.BoostActive(player) then
		stats.BakeTime *= Config.Gems.BoostBakeMult
	end
	-- Levelled Gem upgrades (Luck is handled by Inventory's luck provider).
	local data = DataManager.Get(player)
	local levels = data and data.GemUpgrades
	if levels then
		stats.SalePrice *= 1 + (levels.Income or 0) * Config.GemUpgrades.Income.PerLevel
		stats.BakeTime *= 1 - (levels.BakeSpeed or 0) * Config.GemUpgrades.BakeSpeed.PerLevel
	end
	-- Rebirths: permanent cake price bonus.
	if data and data.Rebirths > 0 then
		stats.SalePrice *= 1 + data.Rebirths * RebirthDefs.SalePriceBonus
	end
	-- Storage upgrade: extra rack slots (the rack itself comes with Auto-Restock).
	if data and DataManager.HasUnlock(player, "AutoRestock") then
		stats.StorageSlots += (data.Storage.Rack or 0) * Config.Storage.Rack.PerLevel
	end
	return stats :: any
end

function PlotStats.BoostActive(player: Player): boolean
	local data = DataManager.Get(player)
	return data ~= nil and (data.BoostEndsAt or 0) > os.time()
end

-- Bake duration for a specific oven model on `owner`'s plot.
function PlotStats.BakeDuration(owner: Player?, oven: Model, base: number?): number
	local duration = (base or Config.BakeTime) * PlotStats.Get(owner).BakeTime
	if owner and oven.Name == "Oven" and DataManager.HasUnlock(owner, "GoldenOven") then
		duration *= 0.5
	end
	return duration * ((oven:GetAttribute("SpeedMult") :: number?) or 1)
end

return PlotStats
