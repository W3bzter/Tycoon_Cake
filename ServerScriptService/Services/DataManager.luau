--!strict
-- Player data: load/save with DataStoreService (pcall + retries), session cache,
-- leaderstats, autosave, save on leave and BindToClose.
--
-- Safety rule: if a player's load FAILED, their session is never saved, so a
-- DataStore outage can't overwrite real data with defaults.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

export type PlayerData = {
	Cash: number,
	Gems: number,
	UnlockedUpgrades: { [string]: boolean },
	ShieldCharges: number, -- Anomaly Shields (Gem shop)
	BoostEndsAt: number, -- os.time() when the Bake Boost runs out
	Stats: { CakesSold: number },
}

type Session = {
	data: PlayerData,
	canSave: boolean,
}

local DataManager = {}

local TEMPLATE: PlayerData = {
	Cash = Config.StartingCash,
	Gems = 0,
	UnlockedUpgrades = {},
	ShieldCharges = 0,
	BoostEndsAt = 0,
	Stats = { CakesSold = 0 },
}

local store: DataStore? = nil
local sessions: { [Player]: Session } = {}

local loadedEvent = Instance.new("BindableEvent")
DataManager.PlayerLoaded = loadedEvent.Event -- (player, data)
local resetEvent = Instance.new("BindableEvent")
DataManager.PlayerReset = resetEvent.Event -- (player) after a Studio data reset

-- Helpers --------------------------------------------------------------------

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end

local function reconcile(data: { [any]: any }, template: { [any]: any })
	for key, default in template do
		if data[key] == nil then
			data[key] = deepCopy(default)
		elseif type(default) == "table" and type(data[key]) == "table" then
			reconcile(data[key], default)
		end
	end
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T | string)
	local lastErr: any
	for attempt = 1, Config.DataMaxRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(`[DataManager] {label} failed (attempt {attempt}/{Config.DataMaxRetries}): {result}`)
		if attempt < Config.DataMaxRetries then
			task.wait(2 ^ (attempt - 1)) -- 1s, 2s, ...
		end
	end
	return false, tostring(lastErr)
end

-- DevMode: only ever active inside Studio (checked here, on the server). It uses a
-- separate save key, because Studio and the live game share DataStores; the
-- live save is never touched by a dev session.
local DEV_ACTIVE = Config.DevMode == true and RunService:IsStudio()
DataManager.DevActive = DEV_ACTIVE

local function keyFor(player: Player): string
	return if DEV_ACTIVE then `Dev_{player.UserId}` else `Player_{player.UserId}`
end

local function updateLeaderstat(player: Player, stat: string, value: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	local valueObj = leaderstats and leaderstats:FindFirstChild(stat) :: IntValue?
	if valueObj then
		valueObj.Value = value
	end
end

local function createLeaderstats(player: Player, data: PlayerData)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	for _, stat in { "Cash", "Gems" } do
		local v = Instance.new("IntValue")
		v.Name = stat
		v.Value = (data :: any)[stat]
		v.Parent = leaderstats
	end
	leaderstats.Parent = player
end

-- Load / save ----------------------------------------------------------------

local function load(player: Player)
	local data: PlayerData
	local canSave = false

	if store then
		local ds = store :: DataStore
		local ok, result = withRetries(`Load {player.UserId}`, function()
			return ds:GetAsync(keyFor(player))
		end)
		if ok then
			data = if type(result) == "table" then result :: any else deepCopy(TEMPLATE)
			reconcile(data :: any, TEMPLATE :: any)
			canSave = true
		else
			warn(`[DataManager] Using temporary data for {player.Name}; progress will NOT be saved this session.`)
			data = deepCopy(TEMPLATE)
		end
	else
		data = deepCopy(TEMPLATE)
	end

	if player.Parent == nil then
		return -- left while loading
	end

	if DEV_ACTIVE then
		data.Cash = Config.DevModeAmount
		data.Gems = Config.DevModeAmount
		player:SetAttribute("DevMode", true)
		print(`[DataManager] DevMode: {player.Name} topped up to {Config.DevModeAmount} Cash/Gems (dev save key)`)
	end

	sessions[player] = { data = data, canSave = canSave }
	createLeaderstats(player, data)
	-- Mirrored for the client HUD (shield count, boost timer).
	player:SetAttribute("ShieldCharges", data.ShieldCharges)
	player:SetAttribute("BoostEndsAt", data.BoostEndsAt)
	loadedEvent:Fire(player, data)
end

function DataManager.Save(player: Player): boolean
	local session = sessions[player]
	if not session or not session.canSave or not store then
		return false
	end
	local ds = store :: DataStore
	local snapshot = deepCopy(session.data)
	local ok = withRetries(`Save {player.UserId}`, function()
		return ds:UpdateAsync(keyFor(player), function()
			return snapshot
		end)
	end)
	return ok
end

local function onPlayerRemoving(player: Player)
	DataManager.Save(player)
	sessions[player] = nil
end

-- Public API -----------------------------------------------------------------

function DataManager.Get(player: Player): PlayerData?
	local session = sessions[player]
	return session and session.data
end

function DataManager.IsLoaded(player: Player): boolean
	return sessions[player] ~= nil
end

function DataManager.AddCash(player: Player, amount: number)
	local data = DataManager.Get(player)
	if not data then
		return
	end
	data.Cash += amount
	updateLeaderstat(player, "Cash", data.Cash)
end

-- Returns true and deducts if the player can afford it.
function DataManager.SpendCash(player: Player, amount: number): boolean
	local data = DataManager.Get(player)
	if not data or amount < 0 or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	updateLeaderstat(player, "Cash", data.Cash)
	return true
end

function DataManager.AddGems(player: Player, amount: number)
	local data = DataManager.Get(player)
	if not data then
		return
	end
	data.Gems += amount
	updateLeaderstat(player, "Gems", data.Gems)
end

-- Returns true and deducts if the player has enough Gems.
function DataManager.SpendGems(player: Player, amount: number): boolean
	local data = DataManager.Get(player)
	if not data or amount < 0 or data.Gems < amount then
		return false
	end
	data.Gems -= amount
	updateLeaderstat(player, "Gems", data.Gems)
	return true
end

function DataManager.AddShield(player: Player, amount: number)
	local data = DataManager.Get(player)
	if data then
		data.ShieldCharges = math.max(0, data.ShieldCharges + amount)
		player:SetAttribute("ShieldCharges", data.ShieldCharges)
	end
end

-- Uses one Anomaly Shield if the player has any.
function DataManager.UseShield(player: Player): boolean
	local data = DataManager.Get(player)
	if not data or data.ShieldCharges <= 0 then
		return false
	end
	DataManager.AddShield(player, -1)
	return true
end

function DataManager.ExtendBoost(player: Player, seconds: number)
	local data = DataManager.Get(player)
	if data then
		data.BoostEndsAt = math.max(data.BoostEndsAt, os.time()) + seconds
		player:SetAttribute("BoostEndsAt", data.BoostEndsAt)
	end
end

function DataManager.RecordSale(player: Player)
	local data = DataManager.Get(player)
	if data then
		data.Stats.CakesSold += 1
	end
end

-- Studio-only: wipe this session's save back to a brand-new player (DevMode
-- still tops up Cash/Gems; with DevMode off this resets your real save).
function DataManager.ResetToNew(player: Player): boolean
	if not RunService:IsStudio() then
		return false
	end
	local session = sessions[player]
	if not session then
		return false
	end
	local data = deepCopy(TEMPLATE)
	if DEV_ACTIVE then
		data.Cash = Config.DevModeAmount
		data.Gems = Config.DevModeAmount
	end
	session.data = data
	updateLeaderstat(player, "Cash", data.Cash)
	updateLeaderstat(player, "Gems", data.Gems)
	player:SetAttribute("ShieldCharges", data.ShieldCharges)
	player:SetAttribute("BoostEndsAt", data.BoostEndsAt)
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		for _, tool in (if container then container:GetChildren() else {}) do
			if tool:IsA("Tool") then
				tool:Destroy()
			end
		end
	end
	DataManager.Save(player)
	print(`[DataManager] Studio reset: {player.Name} is now a brand-new player ({keyFor(player)})`)
	resetEvent:Fire(player)
	return true
end

function DataManager.Unlock(player: Player, upgradeId: string)
	local data = DataManager.Get(player)
	if data then
		data.UnlockedUpgrades[upgradeId] = true
	end
end

function DataManager.HasUnlock(player: Player, upgradeId: string): boolean
	local data = DataManager.Get(player)
	return data ~= nil and data.UnlockedUpgrades[upgradeId] == true
end

function DataManager.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn(`[DataManager] DataStore unavailable ({result}); running with unsaved in-memory data.`)
	end

	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in sessions do
				task.spawn(DataManager.Save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				DataManager.Save(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait()
		end
	end)
end

return DataManager
