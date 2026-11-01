--!strict
-- Gem shop consumables, bought from the client HUD via Remotes.BuyGemItem(itemId).
-- (Gem-priced *upgrades* are regular purchase buttons handled by TycoonButtons.)
--   Shield: one Anomaly Shield charge (your plot skips the next Overheat or Mimic)
--   Boost:  2x bake speed for Config.Gems.BoostSeconds (stacks by extending)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DataManager = require(script.Parent.DataManager)
local Remotes = require(script.Parent.Remotes)

local GemShop = {}

local lastRequest: { [Player]: number } = {}

local function notify(player: Player, message: string)
	Remotes.Get("Notify"):FireClient(player, message)
end

function GemShop.Buy(player: Player, itemId: any): (boolean, string?)
	if typeof(itemId) ~= "string" then
		return false, "bad item"
	end
	local now = os.clock()
	if now - (lastRequest[player] or 0) < 0.5 then
		return false, "too fast"
	end
	lastRequest[player] = now

	local data = DataManager.Get(player)
	if not data then
		return false, "not loaded"
	end

	if itemId == "Shield" then
		if data.ShieldCharges >= Config.Gems.MaxShields then
			notify(player, `You can hold at most {Config.Gems.MaxShields} shields.`)
			return false, "max shields"
		end
		if not DataManager.SpendGems(player, Config.Gems.ShieldPrice) then
			notify(player, `You need 💎 {Config.Gems.ShieldPrice} for a shield.`)
			return false, "insufficient gems"
		end
		DataManager.AddShield(player, 1)
		notify(player, "🛡️ Anomaly Shield ready!")
		return true
	elseif itemId == "Boost" then
		if not DataManager.SpendGems(player, Config.Gems.BoostPrice) then
			notify(player, `You need 💎 {Config.Gems.BoostPrice} for a boost.`)
			return false, "insufficient gems"
		end
		DataManager.ExtendBoost(player, Config.Gems.BoostSeconds)
		notify(player, "⚡ Bake Boost active: ovens bake 2x faster!")
		return true
	end
	return false, "unknown item"
end

function GemShop.Init()
	Remotes.Get("BuyGemItem").OnServerEvent:Connect(function(player, itemId)
		GemShop.Buy(player, itemId)
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return GemShop
