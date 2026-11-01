--!strict
-- Studio-only developer tools. Everything here is gated on RunService:IsStudio()
-- on the server, so none of it can be used in the live game.
--   * Players get the "StudioSession" attribute (the client shows the dev panel).
--   * Remotes.DevResetData: reset your save to a brand-new player.
--     Command-bar alternative during a playtest (Server view):
--       game.ServerStorage.DebugBridge:Invoke("DataManager", "ResetToNew", game.Players:GetPlayers()[1])
--   * Remotes.DevPreviewRoll / DevTools.PreviewRoll: play a roll reveal with one
--     ingredient of a chosen rarity (e.g. "Void", "Celestial") to check its
--     effects. Visual only: nothing is added to the bag. Command bar (Server view):
--       game.ServerStorage.DebugBridge:Invoke("DevTools", "PreviewRoll", game.Players:GetPlayers()[1], "Void")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Services = script:FindFirstAncestor("Services") :: Folder
local DataManager = require(Services.Core.DataManager)
local Remotes = require(Services.Core.Remotes)

local DevTools = {}

-- Plays a roll reveal for `player` where one ingredient is `rarity` (tier name or
-- index) and the rest are Common..Rare. Studio only, visual only.
function DevTools.PreviewRoll(player: Player, rarity: string | number): string
	if not RunService:IsStudio() then
		return "Studio only"
	end
	local index: number? = if typeof(rarity) == "number" then rarity else nil
	for i, tier in Rarity.Tiers do
		if typeof(rarity) == "string" and string.lower(tier.Name) == string.lower(rarity) then
			index = i
		end
	end
	if not index or not Rarity.Tiers[index] then
		return `unknown rarity {rarity}`
	end
	local items = {}
	for i, ingredient in Recipes.IngredientOrder do
		table.insert(items, { Id = -i, Type = ingredient, Rarity = math.random(1, 3), Traits = {} })
	end
	items[math.random(#items)].Rarity = index
	Remotes.Get("RollResult"):FireClient(player, items)
	return `previewing {Rarity.Tiers[index].Name}`
end

function DevTools.Init()
	if not RunService:IsStudio() then
		return
	end
	local function mark(player: Player)
		player:SetAttribute("StudioSession", true)
	end
	Players.PlayerAdded:Connect(mark)
	for _, player in Players:GetPlayers() do
		mark(player)
	end

	Remotes.Get("DevPreviewRoll").OnServerEvent:Connect(function(player, rarity)
		if typeof(rarity) == "string" then
			DevTools.PreviewRoll(player, rarity)
		end
	end)

	Remotes.Get("DevResetData").OnServerEvent:Connect(function(player)
		if RunService:IsStudio() then
			DataManager.ResetToNew(player)
			Remotes.Get("Notify"):FireClient(player, "🛠️ Data reset: you're a brand-new player.")
		end
	end)
end

return DevTools
