--!strict
-- Auto-Roller (fixed upgrade "AutoRoller"): rolls ingredients for you at the
-- pantry's normal cooldown and odds, wherever you are, while your bag has room.
-- Quiet rolls (no "bag full" toast each time), but every roll still shows the
-- on-screen reveal, like rolling by hand.
-- On/off: T on the pantry (PlayerData.Settings.AutoRoll; missing = on).
-- Needs a placed, working pantry (not broken) on the owner's plot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local BakeUtil = require(Services.Baking.BakeUtil)
local BuildService = require(Services.Build.BuildService)
local DataManager = require(Services.Core.DataManager)
local Inventory = require(Services.Baking.Inventory)
local PlotManager = require(Services.Core.PlotManager)
local Prompts = require(Services.Core.Prompts)
local TycoonButtons = require(Services.World.TycoonButtons)

local AutoRoll = {}

local UPGRADE = "AutoRoller"
local CHECK_EVERY = 0.5 -- seconds; Inventory.Roll enforces the real cooldown

local bagFullNotified: { [Player]: boolean } = {}

function AutoRoll.IsOn(player: Player): boolean
	local data = DataManager.Get(player)
	return data ~= nil and DataManager.HasUnlock(player, UPGRADE) and data.Settings.AutoRoll ~= false
end

local function workingPantry(plot: Model): Model?
	local pantry = BakeUtil.findMachine(plot, "IngredientCrate")
	if pantry and pantry:GetAttribute("Visible") == true and not pantry:GetAttribute("Broken") then
		return pantry
	end
	return nil
end

local function updatePrompt(pantry: Model, owner: Player?)
	local prompt = Prompts.Get(pantry, "AutoRollPrompt")
	if prompt then
		prompt.ActionText = if owner and AutoRoll.IsOn(owner) then "🎲 Auto-Roll: ON" else "🎲 Auto-Roll: OFF"
		prompt.ObjectText = "Pantry"
	end
end

function AutoRoll.Toggle(player: Player)
	local data = DataManager.Get(player)
	local plot = PlotManager.GetPlot(player)
	if not data or not plot or not DataManager.HasUnlock(player, UPGRADE) then
		return
	end
	data.Settings.AutoRoll = data.Settings.AutoRoll == false -- missing counts as on
	bagFullNotified[player] = nil
	BakeUtil.notify(player, if data.Settings.AutoRoll then "🎲 Auto-Roll on." else "🎲 Auto-Roll off.")
	local pantry = workingPantry(plot)
	if pantry then
		updatePrompt(pantry, player)
	end
end

local function setupPantry(plot: Model, model: Model)
	if model:GetAttribute("Kind") ~= "Pantry" then
		return
	end
	local part = model:FindFirstChild("Crate") :: BasePart?
	if not part then
		return
	end
	Prompts.Add(model, part, {
		Name = "AutoRollPrompt",
		Action = "🎲 Auto-Roll: ON",
		Object = "Pantry",
		Key = Config.Prompts.Keys.Toggle,
		Order = 2,
		Show = function()
			local owner = PlotManager.GetOwner(plot)
			return owner ~= nil and DataManager.HasUnlock(owner, UPGRADE)
		end,
		Trigger = function(player)
			if PlotManager.IsOwner(player, plot) then
				AutoRoll.Toggle(player)
			end
		end,
	})
	updatePrompt(model, PlotManager.GetOwner(plot))
end

local function tick()
	for _, player in Players:GetPlayers() do
		local plot = PlotManager.GetPlot(player)
		if plot and DataManager.IsLoaded(player) and AutoRoll.IsOn(player) and workingPantry(plot) then
			if Inventory.Roll(player, true, DataManager.Get(player).Settings.AutoRollPopups ~= false) then -- pop-ups: Settings panel
				bagFullNotified[player] = nil
			elseif not Inventory.RollFits(player) and not bagFullNotified[player] then
				bagFullNotified[player] = true
				BakeUtil.notify(player, "🎒 Bag full: Auto-Roll is waiting. Mix some cakes or toss ingredients!")
			end
		end
	end
end

function AutoRoll.Init()
	BuildService.OnPlaced(setupPantry)
	TycoonButtons.UpgradeUnlocked:Connect(function(player, plot, id)
		if id == UPGRADE then
			BakeUtil.notify(player, "🎲 Auto-Roller on! Press T at your pantry to switch it off.")
			local pantry = workingPantry(plot)
			if pantry then
				updatePrompt(pantry, player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		bagFullNotified[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			local ok, err = pcall(tick)
			if not ok then
				warn(`[AutoRoll] {err}`)
			end
		end
	end)
end

return AutoRoll
