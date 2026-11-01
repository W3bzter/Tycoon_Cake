--!strict
-- The Ingredient Bag: saved per player (PlayerData.Bag). A free roll at the
-- pantry adds one of every ingredient your unlocked recipes use, each with a
-- rolled rarity and traits. Mixing takes ingredients from here: pinned (★)
-- items first, then the most valuable.
--
-- Remotes:
--   RollResult (server -> client)  items just rolled, for the reveal animation
--   BagUpdate  (server -> client)  full bag + capacity + selected recipe
--   BagAction  (client -> server)  "pin" id | "discard" id | "recipe" name
-- Player attribute BagCounts ("Flour:2,Eggs:1,...") feeds the mixer preview.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Services = script:FindFirstAncestor("Services") :: Folder
local DataManager = require(Services.Core.DataManager)
local GamePasses = require(Services.Core.GamePasses)
local Remotes = require(Services.Core.Remotes)

local Inventory = {}

local lastRoll: { [Player]: number } = {}
local lastAction: { [Player]: number } = {}
local rng = Random.new()

local function notify(player: Player, message: string)
	Remotes.Get("Notify"):FireClient(player, message)
end

local function hasUnlockFn(player: Player)
	return function(id: string)
		return DataManager.HasUnlock(player, id)
	end
end

-- Luck shifts roll odds. Filled in by the Gem upgrades (Phase 5); 0 for now.
local luckProvider: (Player) -> number = function()
	return 0
end
function Inventory.SetLuckProvider(fn: (Player) -> number)
	luckProvider = fn
end
function Inventory.Luck(player: Player): number
	return luckProvider(player)
end

function Inventory.Capacity(player: Player): number
	local data = DataManager.Get(player)
	local level = data and data.Storage.Bag or 0
	return Config.Rolling.BagSize + level * Config.Storage.Bag.PerLevel
end

-- Auto-delete: should an item of `kind` ("Ingredient" | "Batter" | "Cake") with
-- this rarity be thrown away? `special` = it has traits or a mutation.
function Inventory.ShouldDelete(player: Player, kind: string, rarity: number, special: boolean): boolean
	local data = DataManager.Get(player)
	if not data then
		return false
	end
	local threshold = data.Settings.AutoDelete[kind] or 0
	if threshold <= 0 or rarity >= threshold then
		return false
	end
	return not (special and data.Settings.KeepSpecial)
end

local function syncSettings(player: Player)
	local data = DataManager.Get(player)
	if not data then
		return
	end
	local parts = {}
	for _, kind in Config.AutoDelete.Kinds do
		table.insert(parts, `{kind}:{data.Settings.AutoDelete[kind] or 0}`)
	end
	player:SetAttribute("AutoDelete", table.concat(parts, ","))
	player:SetAttribute("KeepSpecial", data.Settings.KeepSpecial)
	-- Settings panel (UI/Panels/Settings): volumes 0..1, auto-roll pop-ups.
	player:SetAttribute("MusicVolume", data.Settings.MusicVolume or 0.6)
	player:SetAttribute("SfxVolume", data.Settings.SfxVolume or 1)
	player:SetAttribute("AutoRollPopups", data.Settings.AutoRollPopups ~= false)
	-- World labels a player chose to hide (UI/Effects/WorldLabels): Machines, Cakes, Customers.
	local hidden = data.Settings.HideLabels or {}
	for _, kind in Config.LabelKinds do
		player:SetAttribute(`Hide{kind}Labels`, hidden[kind] == true)
	end
end
Inventory.SyncSettings = syncSettings

-- Remotes.Settings: ("autodelete", kind, n) | ("keepspecial", bool)
function Inventory.SettingsAction(player: Player, action: any, a: any, b: any)
	local data = DataManager.Get(player)
	if not data then
		return
	end
	if action == "autodelete" and typeof(a) == "string" and table.find(Config.AutoDelete.Kinds, a) and typeof(b) == "number" then
		data.Settings.AutoDelete[a] = math.clamp(math.floor(b), 0, #Rarity.Tiers)
	elseif action == "keepspecial" and typeof(a) == "boolean" then
		data.Settings.KeepSpecial = a
	elseif action == "volume" and (a == "Music" or a == "SFX") and typeof(b) == "number" and b == b then
		local v = math.clamp(math.floor(b * 10 + 0.5) / 10, 0, 1)
		if a == "Music" then
			data.Settings.MusicVolume = v
		else
			data.Settings.SfxVolume = v
		end
	elseif action == "autorollpopups" and typeof(a) == "boolean" then
		data.Settings.AutoRollPopups = a
	elseif action == "hidelabels" and typeof(a) == "string" and table.find(Config.LabelKinds, a) and typeof(b) == "boolean" then
		data.Settings.HideLabels = data.Settings.HideLabels or {}
		data.Settings.HideLabels[a] = if b then true else nil
	else
		return
	end
	syncSettings(player)
end

local function bagOf(player: Player): { Rarity.Item }?
	local data = DataManager.Get(player)
	return data and data.Bag
end

local function sorted(bag: { Rarity.Item }): { Rarity.Item }
	local copy = table.clone(bag)
	table.sort(copy, function(a, b)
		if (a.Pinned == true) ~= (b.Pinned == true) then
			return a.Pinned == true
		end
		local fa, fb = Rarity.Factor(a), Rarity.Factor(b)
		if fa ~= fb then
			return fa > fb
		end
		return a.Id < b.Id
	end)
	return copy
end

function Inventory.Counts(player: Player): { [string]: number }
	local counts = {}
	for _, item in bagOf(player) or {} do
		counts[item.Type] = (counts[item.Type] or 0) + 1
	end
	return counts
end

function Inventory.Sync(player: Player)
	local data = DataManager.Get(player)
	if not data then
		return
	end
	local parts = {}
	for name, n in Inventory.Counts(player) do
		table.insert(parts, `{name}:{n}`)
	end
	player:SetAttribute("BagCounts", table.concat(parts, ","))
	player:SetAttribute("MixRecipe", data.MixRecipe)
	player:SetAttribute("Luck", Inventory.Luck(player))
	Remotes.Get("BagUpdate"):FireClient(player, {
		Items = sorted(data.Bag),
		Capacity = Inventory.Capacity(player),
		MixRecipe = data.MixRecipe,
	})
end

function Inventory.MakeItem(player: Player, ingredient: string): Rarity.Item
	local data = DataManager.Get(player)
	local id = 0
	if data then
		id = data.NextItemId
		data.NextItemId += 1
	end
	return {
		Id = id,
		Type = ingredient,
		Rarity = Rarity.RollRarity(Inventory.Luck(player), rng),
		Traits = Rarity.RollTraits(rng),
		Pinned = false,
	}
end

-- Adds items if they all fit. Returns false (and adds nothing) if the bag is too full.
function Inventory.AddItems(player: Player, items: { Rarity.Item }): boolean
	local bag = bagOf(player)
	if not bag or #bag + #items > Inventory.Capacity(player) then
		return false
	end
	for _, item in items do
		table.insert(bag, item)
	end
	Inventory.Sync(player)
	return true
end

-- Would a roll fit in the bag right now (ignoring the cooldown)?
function Inventory.RollFits(player: Player): boolean
	local bag = bagOf(player)
	if not bag then
		return false
	end
	local count = 0
	local copies = if GamePasses.Active(player, "DoubleRoll") then 2 else 1
	for _ in Recipes.NeededIngredients(hasUnlockFn(player)) do
		count += copies
	end
	return #bag + count <= Inventory.Capacity(player)
end

-- Fired after every successful roll with all rolled items (including auto-deleted
-- ones, marked Deleted). Used for stats, achievements and the pantry VFX.
local rollEvent = Instance.new("BindableEvent")
Inventory.Rolled = rollEvent.Event -- (player, items)

-- One free roll: one of every ingredient the unlocked recipes use.
-- `quiet` skips the "bag full" toast (Full Automation auto-rolls).
-- `reveal` forces the on-screen reveal even when quiet (the Auto-Roller).
function Inventory.Roll(player: Player, quiet: boolean?, reveal: boolean?): boolean
	local now = os.clock()
	local cooldown = if GamePasses.Active(player, "InstantRoll") then Config.Rolling.InstantCooldown else Config.Rolling.Cooldown
	if now - (lastRoll[player] or 0) < cooldown then
		return false
	end
	local copies = if GamePasses.Active(player, "DoubleRoll") then 2 else 1 -- 2x Roll pass: same odds, twice the items
	local needed = Recipes.NeededIngredients(hasUnlockFn(player))
	local count = 0
	for _, ingredient in Recipes.IngredientOrder do
		if needed[ingredient] then
			count += copies
		end
	end
	local bag = bagOf(player)
	if not bag or #bag + count > Inventory.Capacity(player) then
		if not quiet then
			notify(player, "🎒 Your bag is too full to roll. Mix some cakes or toss ingredients!")
		end
		return false
	end
	local rolled, kept = {}, {}
	for _ = 1, copies do
		for _, ingredient in Recipes.IngredientOrder do
			if needed[ingredient] then
				local item: any = Inventory.MakeItem(player, ingredient)
				if Inventory.ShouldDelete(player, "Ingredient", item.Rarity, Rarity.IsSpecial(item)) then
					item.Deleted = true -- shown greyed out in the reveal, never stored
				else
					table.insert(kept, item)
				end
				table.insert(rolled, item)
			end
		end
	end
	Inventory.AddItems(player, kept)
	lastRoll[player] = now
	-- Auto-rolls (Full Automation) only show the reveal for Legendary or better.
	local best = 1
	for _, item in rolled do
		best = math.max(best, item.Rarity)
	end
	if not quiet or reveal or best >= 5 then
		Remotes.Get("RollResult"):FireClient(player, rolled)
	end
	rollEvent:Fire(player, rolled)
	return true
end

-- Which recipe the next mix would make (chosen recipe, or the best one the bag
-- can make), without taking anything. nil if the bag can't make it.
function Inventory.PeekRecipe(player: Player): string?
	local data = DataManager.Get(player)
	if not data then
		return nil
	end
	local unlocked = hasUnlockFn(player)
	if data.MixRecipe ~= "Best" and Recipes.IsUnlocked(data.MixRecipe, unlocked) then
		for _, ingredient in Recipes.Cakes[data.MixRecipe].Ingredients do
			if (Inventory.Counts(player)[ingredient] or 0) < 1 then
				return nil
			end
		end
		return data.MixRecipe
	end
	return Recipes.BestRecipe(Inventory.Counts(player), unlocked)
end

-- One item per ingredient of `cakeType`, or nil if the bag can't make it.
-- order "best": pinned first, then most valuable (hand mixing).
-- order "cheapest": never pinned, least valuable first (automation), so your
-- best ingredients stay in the bag for the minigame.
local function pick(bag: { Rarity.Item }, cakeType: string, order: string): { Rarity.Item }?
	local list: { Rarity.Item }
	if order == "cheapest" then
		list = {}
		for _, item in bag do
			if not item.Pinned then
				table.insert(list, item)
			end
		end
		table.sort(list, function(a, b)
			local fa, fb = Rarity.Factor(a), Rarity.Factor(b)
			if fa ~= fb then
				return fa < fb
			end
			return a.Id < b.Id
		end)
	else
		list = sorted(bag)
	end
	local chosen: { Rarity.Item } = {}
	for _, ingredient in Recipes.Cakes[cakeType].Ingredients do
		local found = false
		for _, item in list do
			if item.Type == ingredient and not table.find(chosen, item) then
				table.insert(chosen, item)
				found = true
				break
			end
		end
		if not found then
			return nil
		end
	end
	return chosen
end

function Inventory.CanMake(player: Player, cakeType: string, order: string?): boolean
	local bag = bagOf(player)
	return bag ~= nil and Recipes.Cakes[cakeType] ~= nil and pick(bag, cakeType, order or "best") ~= nil
end

-- Picks the ingredients for one batch and removes them from the bag.
-- Without `forcedRecipe` it makes PeekRecipe's choice (hand mixing).
function Inventory.TakeForRecipe(player: Player, forcedRecipe: string?, order: string?): (string?, { Rarity.Item }?)
	local data = DataManager.Get(player)
	local cakeType = forcedRecipe or Inventory.PeekRecipe(player)
	if not data or not cakeType or not Recipes.Cakes[cakeType] then
		return nil, nil
	end
	local chosen = pick(data.Bag, cakeType, order or "best")
	if not chosen then
		return nil, nil
	end
	for _, item in chosen do
		local index = table.find(data.Bag, item)
		if index then
			table.remove(data.Bag, index)
		end
	end
	Inventory.Sync(player)
	return cakeType, chosen
end

-- Rat Swarm: removes up to `n` random unpinned items. Returns what was taken.
function Inventory.StealRandom(player: Player, n: number): { Rarity.Item }
	local bag = bagOf(player)
	local taken = {}
	if not bag then
		return taken
	end
	for _ = 1, n do
		local candidates = {}
		for i, item in bag do
			if not item.Pinned then
				table.insert(candidates, i)
			end
		end
		if #candidates == 0 then
			break
		end
		table.insert(taken, table.remove(bag, candidates[rng:NextInteger(1, #candidates)]))
	end
	if #taken > 0 then
		Inventory.Sync(player)
	end
	return taken
end

local function findItem(bag: { Rarity.Item }, id: number): (Rarity.Item?, number?)
	for i, item in bag do
		if item.Id == id then
			return item, i
		end
	end
	return nil, nil
end

function Inventory.Action(player: Player, action: any, arg: any)
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.15 then
		return
	end
	lastAction[player] = now
	local data = DataManager.Get(player)
	if not data then
		return
	end
	if action == "pin" and typeof(arg) == "number" then
		local item = findItem(data.Bag, arg)
		if item then
			item.Pinned = not item.Pinned
		end
	elseif action == "discard" and typeof(arg) == "number" then
		local _, index = findItem(data.Bag, arg)
		if index then
			table.remove(data.Bag, index)
		end
	elseif action == "recipe" and typeof(arg) == "string" then
		if arg == "Best" or Recipes.IsUnlocked(arg, hasUnlockFn(player)) then
			data.MixRecipe = arg
		end
	elseif action == "sync" then
		-- client (re)opened: just resend
	else
		return
	end
	Inventory.Sync(player)
end

function Inventory.Init()
	Remotes.Get("BagAction").OnServerEvent:Connect(Inventory.Action)
	Remotes.Get("Settings").OnServerEvent:Connect(Inventory.SettingsAction)
	local function ready(player: Player)
		Inventory.Sync(player)
		syncSettings(player)
	end
	DataManager.PlayerLoaded:Connect(ready)
	DataManager.PlayerReset:Connect(ready)
	for _, player in Players:GetPlayers() do
		if DataManager.IsLoaded(player) then
			ready(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
		lastAction[player] = nil
	end)
end

-- Test helper: a short summary that crosses the DebugBridge.
function Inventory.Describe(player: Player): string
	local parts = {}
	for _, item in sorted(bagOf(player) or {}) do
		table.insert(parts, `{item.Type}:{Rarity.Name(item.Rarity)}{#item.Traits > 0 and ("+" .. table.concat(item.Traits, "+")) or ""}{item.Pinned and "*" or ""}`)
	end
	return `{#parts} items: ` .. table.concat(parts, " ")
end

return Inventory
