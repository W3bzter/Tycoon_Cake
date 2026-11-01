--!strict
-- Rebirth (Remotes.Rebirth). Requirements and cost come from Shared/RebirthDefs:
-- Cash plus specific cakes held in the inventory (FinishedCake tools). On success
-- the cakes and Cash are taken and the player's data is reset through
-- DataManager.ApplyReset, which rebuilds the plot from scratch:
--   reset: Cash (to StartingCash), plot upgrades, broken machines, line switches/recipes
--   kept:  Gems, Gem upgrades, Ingredient Bag and hoppers, storage levels,
--          achievements, stats, settings, receipts, shields/boost
-- Each rebirth adds +25% cake prices (PlotStats) and +10% mutation chance.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RebirthDefs = require(Shared:WaitForChild("RebirthDefs"))

local Services = script:FindFirstAncestor("Services") :: Folder
local DataManager = require(Services.Core.DataManager)
local Remotes = require(Services.Core.Remotes)
local ToolFactory = require(Services.Core.ToolFactory)
local VFX = require(Services.Effects.VFX)

local Rebirth = {}

local lastRequest: { [Player]: number } = {}

local function notify(player: Player, message: string)
	Remotes.Get("Notify"):FireClient(player, message)
end

function Rebirth.Request(player: Player): (boolean, string?)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < 1 then
		return false, "too fast"
	end
	lastRequest[player] = now
	local data = DataManager.Get(player)
	if not data then
		return false, "not loaded"
	end

	local done = data.Rebirths
	local cost = RebirthDefs.Cost(done)
	local reqs = RebirthDefs.Requirements(done)
	local tools = ToolFactory.Find(player, "FinishedCake")
	local cakes = {}
	for i, tool in tools do
		cakes[i] = ToolFactory.GetCakeInfo(tool)
	end
	local ok, picked = RebirthDefs.Match(reqs, cakes)
	if not ok then
		notify(player, "♻️ You're missing some of the cakes for this rebirth. Hold them in your inventory!")
		return false, "missing cakes"
	end
	if data.Cash < cost then
		notify(player, `♻️ You need ${cost} to rebirth.`)
		return false, "insufficient cash"
	end

	-- Pay: the cakes and the Cash.
	for _, index in picked do
		tools[index]:Destroy()
	end
	DataManager.SpendCash(player, cost)

	local fresh = DataManager.NewData()
	local new = DataManager.DeepCopy(data)
	new.Cash = if DataManager.DevActive then Config.DevModeAmount else Config.StartingCash
	new.UnlockedUpgrades = {}
	new.Broken = {}
	new.Build = fresh.Build -- placed equipment and decor go with the bakery
	new.Build.Migrated = true
	new.Build.MigratedShop = true
	new.Build.MigratedAutoBakers = true
	new.Rebirths = done + 1
	new.MixRecipe = "Best" -- recipes must be re-unlocked

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		VFX.Burst(root.Position, "Rebirth")
		VFX.Pillar(root.Position, Color3.fromRGB(255, 240, 180), 3)
	end
	DataManager.ApplyReset(player, new, true) -- keep held cakes you didn't need
	DataManager.MaxStat(player, "Rebirths", new.Rebirths)
	for _, other in Players:GetPlayers() do
		notify(other, `♻️ {player.DisplayName} reached Rebirth {new.Rebirths}! (+{math.floor(new.Rebirths * RebirthDefs.SalePriceBonus * 100)}% cake prices)`)
	end
	return true
end

function Rebirth.Init()
	Remotes.Get("Rebirth").OnServerEvent:Connect(function(player)
		Rebirth.Request(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return Rebirth
