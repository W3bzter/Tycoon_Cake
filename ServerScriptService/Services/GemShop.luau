--!strict
-- Gem shop consumables, bought from the client HUD via Remotes.BuyGemItem(itemId).
-- (Gem-priced *upgrades* are regular purchase buttons handled by TycoonButtons.)
--   Shield: one Anomaly Shield charge (your plot skips the next Overheat or Mimic)
--   Boost:  2x bake speed for Config.Gems.BoostSeconds (stacks by extending)
--   Upgrade:<Name>: levelled upgrades (Config.GemUpgrades): Income, BakeSpeed, Luck
--
-- Luck changes the odds of the (always free) ingredient rolls, i.e. Gems buy an
-- edge on random outcomes. So we ask PolicyService per player: if paid random
-- items are restricted (or the check fails), Luck is hidden, can't be bought,
-- and counts as 0. Player attributes for the HUD: GemUpgrades ("Income:2,..."),
-- LuckAllowed (bool).

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DataManager = require(script.Parent.DataManager)
local Inventory = require(script.Parent.Inventory)
local Remotes = require(script.Parent.Remotes)

local GemShop = {}

local lastRequest: { [Player]: number } = {}
local luckAllowed: { [Player]: boolean } = {}

local function notify(player: Player, message: string)
	Remotes.Get("Notify"):FireClient(player, message)
end

-- PolicyService check, cached per player. Fails closed (restricted) on error.
local function checkPolicy(player: Player): boolean
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	local allowed = ok and info ~= nil and info.ArePaidRandomItemsRestricted == false
	luckAllowed[player] = allowed
	player:SetAttribute("LuckAllowed", allowed)
	return allowed
end

function GemShop.LuckAllowed(player: Player): boolean
	if luckAllowed[player] == nil then
		return checkPolicy(player)
	end
	return luckAllowed[player]
end

function GemShop.Level(player: Player, name: string): number
	local data = DataManager.Get(player)
	return data and data.GemUpgrades[name] or 0
end

function GemShop.UpgradeCost(name: string, level: number): number
	local def = Config.GemUpgrades[name]
	return math.floor(def.BaseCost * def.CostGrowth ^ level + 0.5)
end

local function syncUpgrades(player: Player)
	local data = DataManager.Get(player)
	if not data then
		return
	end
	local parts = {}
	for _, name in Config.GemUpgrades.Order do
		table.insert(parts, `{name}:{data.GemUpgrades[name] or 0}`)
	end
	player:SetAttribute("GemUpgrades", table.concat(parts, ","))
	Inventory.Sync(player) -- refreshes the Luck attribute / odds
end

local function buyUpgrade(player: Player, name: string): (boolean, string?)
	local data = DataManager.Get(player)
	if not table.find(Config.GemUpgrades.Order, name) or not data then
		return false, "unknown upgrade" -- only real upgrade names (not e.g. "Order")
	end
	local def = Config.GemUpgrades[name]
	if name == "Luck" and not GemShop.LuckAllowed(player) then
		return false, "not available"
	end
	local level = data.GemUpgrades[name] or 0
	if level >= def.MaxLevel then
		notify(player, `{def.Icon} {def.DisplayName} is maxed out!`)
		return false, "max level"
	end
	local cost = GemShop.UpgradeCost(name, level)
	if not DataManager.SpendGems(player, cost) then
		notify(player, `You need 💎 {cost} for {def.DisplayName} level {level + 1}.`)
		return false, "insufficient gems"
	end
	data.GemUpgrades[name] = level + 1
	syncUpgrades(player)
	notify(player, `{def.Icon} {def.DisplayName} upgraded to level {level + 1}!`)
	return true
end

function GemShop.StorageCost(name: string, level: number): number
	local def = Config.Storage[name]
	return math.floor(def.BaseCost * def.Growth ^ level + 0.5)
end

local function syncStorage(player: Player)
	local data = DataManager.Get(player)
	if data then
		player:SetAttribute("Storage", `Bag:{data.Storage.Bag or 0},Rack:{data.Storage.Rack or 0}`)
	end
end

-- Storage upgrades (Cash): bigger Ingredient Bag, bigger cake rack.
function GemShop.BuyStorage(player: Player, name: any): (boolean, string?)
	local data = DataManager.Get(player)
	if typeof(name) ~= "string" or not table.find(Config.Storage.Order, name) or not data then
		return false, "unknown upgrade"
	end
	local now = os.clock()
	if now - (lastRequest[player] or 0) < 0.5 then
		return false, "too fast"
	end
	lastRequest[player] = now
	local def = Config.Storage[name]
	local level = data.Storage[name] or 0
	if level >= def.MaxLevel then
		notify(player, `{def.Icon} {def.DisplayName} is maxed out!`)
		return false, "max level"
	end
	local cost = GemShop.StorageCost(name, level)
	if not DataManager.SpendCash(player, cost) then
		notify(player, `You need ${cost} for {def.DisplayName} level {level + 1}.`)
		return false, "insufficient cash"
	end
	data.Storage[name] = level + 1
	syncStorage(player)
	Inventory.Sync(player) -- new bag capacity
	notify(player, `{def.Icon} {def.DisplayName} upgraded to level {level + 1}!`)
	return true
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
	elseif itemId:sub(1, 8) == "Upgrade:" then
		return buyUpgrade(player, itemId:sub(9))
	end
	return false, "unknown item"
end

function GemShop.Init()
	Inventory.SetLuckProvider(function(player)
		if not GemShop.LuckAllowed(player) then
			return 0
		end
		return GemShop.Level(player, "Luck") * Config.GemUpgrades.Luck.PerLevel
	end)

	Remotes.Get("BuyGemItem").OnServerEvent:Connect(function(player, itemId)
		GemShop.Buy(player, itemId)
	end)
	Remotes.Get("ShopAction").OnServerEvent:Connect(function(player, action, arg)
		if action == "storage" then
			GemShop.BuyStorage(player, arg)
		end
	end)
	local function onReady(player: Player)
		syncStorage(player)
		task.spawn(function()
			checkPolicy(player)
			syncUpgrades(player)
		end)
	end
	DataManager.PlayerLoaded:Connect(onReady)
	DataManager.PlayerReset:Connect(onReady)
	for _, player in Players:GetPlayers() do
		if DataManager.IsLoaded(player) then
			onReady(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		luckAllowed[player] = nil
	end)
end

return GemShop
