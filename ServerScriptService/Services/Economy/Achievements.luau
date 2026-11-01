--!strict
-- Achievements (definitions in Shared/Achievements). Listens to every
-- DataManager.StatChanged and unlocks definitions whose goal is reached: saves
-- PlayerData.Achievements[id] = os.time(), pays Gems, tells the client
-- (AchievementUnlocked) and awards the Roblox badge if one is set.
--
-- Also feeds stats that no other service records:
--   IngredientsRolled, BestRoll  (Inventory.Rolled)
--   PerfectMixes                 (BakingPipeline.Mixed)
--   CakesBaked, Mutations, Mutation<Name> (BakingPipeline.Baked)
--   Repairs                      (Repairs.Repaired)
--   LinesOwned                   (TycoonButtons.UpgradeUnlocked)

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Defs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Achievements"))

local Services = script:FindFirstAncestor("Services") :: Folder
local BakingPipeline = require(Services.Baking.BakingPipeline)
local DataManager = require(Services.Core.DataManager)
local Inventory = require(Services.Baking.Inventory)
local Remotes = require(Services.Core.Remotes)
local Repairs = require(Services.World.Repairs)
local TycoonButtons = require(Services.World.TycoonButtons)

local Achievements = {}

local dirty: { [Player]: boolean } = {}

local function sync(player: Player)
	local data = DataManager.Get(player)
	if data then
		Remotes.Get("AchievementSync"):FireClient(player, { Stats = data.Stats, Unlocked = data.Achievements })
	end
end

local function unlock(player: Player, def: Defs.Achievement)
	local data = DataManager.Get(player)
	if not data or data.Achievements[def.Id] then
		return
	end
	data.Achievements[def.Id] = os.time()
	if def.Gems > 0 then
		DataManager.EarnGems(player, def.Gems)
	end
	Remotes.Get("AchievementUnlocked"):FireClient(player, def.Id)
	if def.BadgeId ~= 0 then
		task.spawn(function()
			pcall(function()
				BadgeService:AwardBadge(player.UserId, def.BadgeId)
			end)
		end)
	end
	dirty[player] = true
end

-- Checks every definition against the player's current stats.
function Achievements.CheckAll(player: Player)
	local data = DataManager.Get(player)
	if not data then
		return
	end
	for _, def in Defs.List do
		if not data.Achievements[def.Id] and (data.Stats[def.Stat] or 0) >= def.Goal then
			unlock(player, def)
		end
	end
end

local function onStat(player: Player, stat: string, value: number)
	dirty[player] = true
	local data = DataManager.Get(player)
	if not data then
		return
	end
	for _, def in Defs.List do
		if def.Stat == stat and value >= def.Goal and not data.Achievements[def.Id] then
			unlock(player, def)
		end
	end
end

local LINE_IDS = { "IngredientConveyor", "ProductionLine2", "ProductionLine3" }

function Achievements.Init()
	DataManager.StatChanged:Connect(onStat)

	Inventory.Rolled:Connect(function(player, items)
		local best = 0
		for _, item in items do
			best = math.max(best, item.Rarity)
		end
		DataManager.AddStat(player, "IngredientsRolled", #items)
		DataManager.MaxStat(player, "BestRoll", best)
	end)
	BakingPipeline.Mixed:Connect(function(player, info)
		if info.Quality == "Perfect" then
			DataManager.AddStat(player, "PerfectMixes", 1)
		end
	end)
	BakingPipeline.Baked:Connect(function(player, info)
		DataManager.AddStat(player, "CakesBaked", 1)
		if info.Mutation then
			DataManager.AddStat(player, "Mutations", 1)
			DataManager.AddStat(player, "Mutation" .. info.Mutation, 1)
		end
	end)
	Repairs.Repaired:Connect(function(player)
		DataManager.AddStat(player, "Repairs", 1)
	end)
	TycoonButtons.UpgradeUnlocked:Connect(function(player)
		local owned = 0
		for _, id in LINE_IDS do
			if DataManager.HasUnlock(player, id) then
				owned += 1
			end
		end
		DataManager.MaxStat(player, "LinesOwned", owned)
	end)

	local function ready(player: Player)
		Achievements.CheckAll(player) -- catches up old saves
		sync(player)
	end
	DataManager.PlayerLoaded:Connect(ready)
	DataManager.PlayerReset:Connect(ready)
	for _, player in Players:GetPlayers() do
		if DataManager.IsLoaded(player) then
			ready(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)

	-- Progress bars update at most every 2 seconds.
	task.spawn(function()
		while true do
			task.wait(2)
			for player in dirty do
				dirty[player] = nil
				if player.Parent then
					sync(player)
				end
			end
		end
	end)
end

return Achievements
