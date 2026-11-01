--!strict
-- Game Passes (Config.GamePasses). Ownership is checked with
-- UserOwnsGamePassAsync once per player and cached; it fails closed (an error
-- counts as "not owned"), and re-checks after a purchase in this server.
-- Player attribute per pass (e.g. FullAutomation = true) for the HUD.
--
-- Game Passes don't go through ProcessReceipt (that's developer products in
-- RobuxShop, which stays the only place that sets it).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local Remotes = require(Services.Core.Remotes)

local GamePasses = {}

local owned: { [Player]: { [string]: boolean } } = {}
local testOwned: { [Player]: { [string]: boolean } } = {}

local changedEvent = Instance.new("BindableEvent")
GamePasses.Changed = changedEvent.Event -- (player, key, owns)

local function set(player: Player, key: string, value: boolean)
	owned[player] = owned[player] or {}
	local before = owned[player][key]
	owned[player][key] = value
	player:SetAttribute(key, value)
	if before ~= value then
		changedEvent:Fire(player, key, value)
	end
end

local function check(player: Player, key: string)
	local def = Config.GamePasses[key]
	if not def or def.Id == 0 then
		set(player, key, false)
		return
	end
	local ok, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.Id)
	end)
	set(player, key, ok and result == true)
end

function GamePasses.Owns(player: Player, key: string): boolean
	if testOwned[player] and testOwned[player][key] then
		return true
	end
	return owned[player] ~= nil and owned[player][key] == true
end

-- Owned AND allowed to work here: RandomItems passes need the paid-random-items
-- policy check (Economy/GemShop sets LuckAllowed; missing = not allowed).
function GamePasses.Active(player: Player, key: string): boolean
	local def = Config.GamePasses[key]
	if def and def.RandomItems and player:GetAttribute("LuckAllowed") ~= true then
		return false
	end
	return GamePasses.Owns(player, key)
end

-- Studio-only test hook (DebugBridge): pretend the player owns a pass.
function GamePasses.SetTestOwned(player: Player, key: string, value: boolean): boolean
	if not RunService:IsStudio() then
		return false
	end
	testOwned[player] = testOwned[player] or {}
	testOwned[player][key] = value
	player:SetAttribute(key, value or (owned[player] ~= nil and owned[player][key] == true))
	changedEvent:Fire(player, key, GamePasses.Owns(player, key))
	return true
end

function GamePasses.Init()
	local function onJoin(player: Player)
		for key in Config.GamePasses do
			task.spawn(check, player, key)
		end
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		onJoin(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		testOwned[player] = nil
	end)

	Remotes.Get("GamePassPrompt").OnServerEvent:Connect(function(player, key)
		local def = typeof(key) == "string" and Config.GamePasses[key]
		if not def then
			return
		end
		if def.Id == 0 then
			Remotes.Get("Notify"):FireClient(player, `{def.Label} isn't set up yet (coming soon!)`)
			return
		end
		if def.RandomItems and player:GetAttribute("LuckAllowed") ~= true then
			return -- not sold where paid random items are restricted
		end
		if GamePasses.Owns(player, key) then
			Remotes.Get("Notify"):FireClient(player, `You already own {def.Label}!`)
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, def.Id)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for key, def in Config.GamePasses do
			if def.Id == passId then
				set(player, key, true)
				Remotes.Get("Notify"):FireClient(player, `Thank you! {def.Label} unlocked 💖`)
			end
		end
	end)
end

return GamePasses
