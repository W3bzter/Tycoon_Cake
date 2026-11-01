--!strict
-- Hand-baking interactions: pantry roll, mixing stations, ovens and display
-- counters. Every interaction is validated on the server (owner, unlocked,
-- visible, not broken, close enough, holding the right item) in Interact.
-- The pieces live in sibling modules; this one re-exports their API so other
-- services keep using BakingPipeline.X:
--   Ovens    oven states, bake timer, FinishBake (bake-time rolls), Overheat visuals
--   Display  display slots and the cakes on them
--   Pantry   pantry bins and the roll pop-up
--   BakeUtil shared helpers

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CakeData = require(Shared:WaitForChild("CakeData"))
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Services = script:FindFirstAncestor("Services") :: Folder
local BakeUtil = require(Services.Baking.BakeUtil)
local DataManager = require(Services.Core.DataManager)
local Display = require(Services.Baking.Display)
local Inventory = require(Services.Baking.Inventory)
local Ovens = require(Services.Baking.Ovens)
local Pantry = require(Services.Baking.Pantry)
local PlotManager = require(Services.Core.PlotManager)
local PlotStats = require(Services.Core.PlotStats)
local ToolFactory = require(Services.Core.ToolFactory)
local TycoonButtons = require(Services.World.TycoonButtons)

local notify, getItem, getPrompt, isNear, cakeName = BakeUtil.notify, BakeUtil.getItem, BakeUtil.getPrompt, BakeUtil.isNear, BakeUtil.cakeName

local BakingPipeline = {}

-- Re-exported API (see the sibling modules).
BakingPipeline.Baked = Ovens.Baked
BakingPipeline.FinishBake = Ovens.FinishBake
BakingPipeline.SetOvenBlocked = Ovens.SetOvenBlocked
BakingPipeline.GetOvens = Ovens.GetOvens
BakingPipeline.SetDoorGlow = Ovens.SetDoorGlow
BakingPipeline.ResetOven = Ovens.ResetOven
BakingPipeline.GetSlots = Display.GetSlots
BakingPipeline.PlaceCakeInFreeSlot = Display.PlaceCakeInFreeSlot
BakingPipeline.RollCake = Display.RollCake
BakingPipeline.GetSaleSlots = Display.GetSaleSlots
BakingPipeline.ReserveSlot = Display.ReserveSlot
BakingPipeline.ReleaseSlot = Display.ReleaseSlot
BakingPipeline.TakeCake = Display.TakeCake
BakingPipeline.ModifyCake = Display.ModifyCake
BakingPipeline.RefreshPantry = Pantry.RefreshPantry

-- (player, CakeInfo) after every hand mix, before auto-delete (stats/achievements).
local mixedEvent = Instance.new("BindableEvent")
BakingPipeline.Mixed = mixedEvent.Event

local OVEN_IDS = { "BasicOven", "Oven", "Oven2", "Oven3" } -- manual ovens (automated ones live in AutoProduction)
-- Hand tools are slower than machines (Phase 4 turns mixing into a minigame).
local BASIC_OVEN_SPEED = 2 -- bake-time multiplier
local HAND_MIX_HOLD = 1.5 -- seconds to hold the prompt when whisking by hand
local MACHINE_PART = {
	IngredientCrate = "Crate", -- the roll prompt
	PrepTable = "Body",
	BasicOven = "Body",
	Mixer = "Body",
	Oven = "Body",
	Oven2 = "Body",
	Oven3 = "Body",
	DisplayCounter = "Counter",
	DisplayCounter2 = "Counter",
}

-- Interactions -------------------------------------------------------------------

local handlers: { [string]: (Player, Model, Model, string?) -> () } = {}

-- The pantry is a free roll: one of every needed ingredient into the bag.
handlers.IngredientCrate = function(player)
	Inventory.Roll(player)
end

-- Mixes one batch from the Ingredient Bag (pinned first, then most valuable).
-- `quality` comes from the mixing minigame (Phase 4); "Good" until then.
function BakingPipeline.Mix(player: Player, station: Model, quality: string?): Rarity.CakeInfo?
	local cakeType, items = Inventory.TakeForRecipe(player)
	if not cakeType or not items then
		local chosen = DataManager.Get(player) and (DataManager.Get(player) :: any).MixRecipe
		notify(
			player,
			if chosen and chosen ~= "Best"
				then `Your bag is missing ingredients for {cakeName(chosen)}. Roll at the pantry!`
				else "Not enough ingredients for any recipe. Roll at the pantry! 🎲"
		)
		return nil
	end
	local info = Rarity.MakeCake(cakeType, Recipes.Cakes[cakeType].Price, items, quality)
	mixedEvent:Fire(player, info)
	if Inventory.ShouldDelete(player, "Batter", info.Rarity, Rarity.IsSpecial(info)) then
		notify(player, `🗑️ Auto-deleted a {Rarity.Name(info.Rarity)} {cakeName(cakeType)} batter ({info.Quality} mix)`)
		return info
	end
	-- Big Mixer makes 2 per mix; the hand bowl always makes 1.
	local batch = if station.Name == "Mixer" then PlotStats.Get(player).MixBatch else 1
	for _ = 1, batch do
		ToolFactory.GiveCakeItem(player, "RawBatter", info)
	end
	notify(player, `{info.Quality} mix! {batch > 1 and `{batch}x ` or ""}{Rarity.Name(info.Rarity)} {cakeName(cakeType)} batter (${info.Value})`)
	return info
end

-- Set by MixingGame: starts the minigame, which calls Mix with the grade.
-- Without it, mixing happens instantly at "Good" quality.
BakingPipeline.OnMixRequested = nil :: ((Player, Model) -> ())?

local function mixHandler(player: Player, _plot: Model, station: Model)
	if not Inventory.PeekRecipe(player) then
		BakingPipeline.Mix(player, station) -- explains what's missing
	elseif BakingPipeline.OnMixRequested then
		BakingPipeline.OnMixRequested(player, station)
	else
		BakingPipeline.Mix(player, station)
	end
end
handlers.PrepTable = mixHandler
handlers.Mixer = mixHandler

local function ovenHandler(player: Player, plot: Model, oven: Model)
	if oven:GetAttribute("Blocked") then
		notify(player, "This oven is overheating! Put it out first.")
		return
	end
	local state = oven:GetAttribute("OvenState")
	if state == "Idle" then
		local batter = ToolFactory.Find(player, "RawBatter")[1]
		if not batter then
			notify(player, "You need Raw Batter from the mixer.")
			return
		end
		CakeData.Write(oven, ToolFactory.GetCakeInfo(batter))
		batter:Destroy()
		Ovens.StartBake(oven, plot)
	elseif state == "Ready" then
		local info = CakeData.Read(oven)
		Ovens.SetState(oven, "Idle")
		if Inventory.ShouldDelete(player, "Cake", info.Rarity, Rarity.IsSpecial(info)) then
			notify(player, `🗑️ Auto-deleted a {Rarity.Name(info.Rarity)} {cakeName(info.Type)}`)
			return
		end
		ToolFactory.GiveCakeItem(player, "FinishedCake", info)
	end
end
for _, id in OVEN_IDS do
	handlers[id] = ovenHandler
end

local function counterHandler(player: Player, plot: Model, counter: Model)
	-- Prefer this counter's own slots, then any other counter's.
	local free: BasePart? = nil
	for _, slot in Display.GetSlots(plot) do
		if not slot:GetAttribute("HasCake") and (free == nil or slot:IsDescendantOf(counter)) then
			free = slot
			if slot:IsDescendantOf(counter) then
				break
			end
		end
	end
	if not free then
		notify(player, "The display counter is full.")
		return
	end
	local cake = ToolFactory.Find(player, "FinishedCake")[1]
	if not cake then
		notify(player, "You need a finished cake from the oven.")
		return
	end
	local info = ToolFactory.GetCakeInfo(cake)
	cake:Destroy()
	Display.Place(plot, free :: BasePart, info)
end
handlers.DisplayCounter = counterHandler
handlers.DisplayCounter2 = counterHandler

-- Single validated entry point (prompts call this; tests can too via DebugBridge).
-- `arg` is the ingredient name for the pantry.
function BakingPipeline.Interact(player: Player, plot: Model, machineId: string, arg: string?): boolean
	local handler = handlers[machineId]
	local item = getItem(plot, machineId)
	if not handler or not item then
		return false
	end
	if not PlotManager.IsOwner(player, plot) then
		return false
	end
	if not DataManager.HasUnlock(player, machineId) or not item:GetAttribute("Visible") then
		return false
	end
	if item:GetAttribute("Broken") then
		notify(player, `🔧 This machine is broken! Hold Q to repair it (${item:GetAttribute("RepairCost") or "?"}).`)
		return false
	end

	local part = item:FindFirstChild(MACHINE_PART[machineId]) :: BasePart?
	local prompt = part and part:FindFirstChild("Prompt") :: ProximityPrompt?
	if not part or not prompt or not isNear(player, part, prompt) then
		return false
	end
	handler(player, plot, item, arg)
	return true
end

-- Setup ------------------------------------------------------------------------

local PROMPT_TEXT = {
	IngredientCrate = { "🎲 Roll Ingredients", "Pantry (free)" },
	PrepTable = { "Whisk Batter", "Mixing Bowl" },
	BasicOven = { "Bake Batter", "Basic Oven" },
	Mixer = { "Mix Batter", "Mixer" },
	Oven = { "Bake Batter", "Oven" },
	Oven2 = { "Bake Batter", "Oven" },
	Oven3 = { "Bake Batter", "Oven" },
	DisplayCounter = { "Display Cake", "Display Counter" },
	DisplayCounter2 = { "Display Cake", "Display Counter" },
}

local function makePrompt(parent: BasePart, action: string, object: string, visible: boolean, distance: number?): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.MaxActivationDistance = distance or 10
	prompt.HoldDuration = 0.2
	prompt.RequiresLineOfSight = false
	prompt.Enabled = visible
	prompt.Parent = parent
	return prompt
end

local function buildSlots(counter: Model, counterPart: BasePart, counterId: string)
	local folder = Instance.new("Folder")
	folder.Name = "Slots"
	local spacing = counterPart.Size.X / (Config.DisplaySlots + 1)
	for i = 1, Config.DisplaySlots do
		local slot = Instance.new("Part")
		slot.Name = `{counterId}_{i}`
		slot.Size = Vector3.new(2, 0.2, 2)
		slot.CFrame = counterPart.CFrame * CFrame.new(-counterPart.Size.X / 2 + spacing * i, counterPart.Size.Y / 2 + 0.1, 0)
		slot.Transparency = 1
		slot.Anchored = true
		slot.CanCollide = false
		slot:SetAttribute("HasCake", false)
		slot:SetAttribute("ForSale", false)
		slot:SetAttribute("Reserved", false)
		slot.Parent = folder
	end
	folder.Parent = counter
end

local function setupPlot(plot: Model)
	for machineId, partName in MACHINE_PART do
		local item = getItem(plot, machineId)
		local part = item and item:FindFirstChild(partName) :: BasePart?
		if item and part then
			local text = PROMPT_TEXT[machineId]
			local prompt = makePrompt(part, text[1], text[2], item:GetAttribute("Visible") == true)
			prompt.Triggered:Connect(function(player)
				BakingPipeline.Interact(player, plot, machineId)
			end)
			if machineId == "PrepTable" then
				prompt.HoldDuration = HAND_MIX_HOLD
			end
			if table.find(OVEN_IDS, machineId) then
				item:SetAttribute("IsOven", true)
				item:SetAttribute("Blocked", false)
				if machineId == "BasicOven" then
					item:SetAttribute("SpeedMult", BASIC_OVEN_SPEED) -- read by PlotStats.BakeDuration
				end
				Ovens.SetState(item, "Idle")
			end
		end
	end

	-- (Pantry bins are decorative stock now; the single roll prompt is on the cabinet.)

	-- Invisible markers on top of each counter where cakes are shown.
	for _, counterId in Display.COUNTER_IDS do
		local counter = getItem(plot, counterId)
		local counterPart = counter and counter:FindFirstChild("Counter") :: BasePart?
		if counter and counterPart then
			buildSlots(counter, counterPart, counterId)
		end
	end
end

local function resetPlot(plot: Model)
	for _, slot in Display.GetSlots(plot, true) do
		BakingPipeline.TakeCake(plot, slot)
	end
	for _, id in OVEN_IDS do
		local oven = getItem(plot, id)
		if oven then
			Ovens.SetState(oven, "Idle")
			BakingPipeline.SetOvenBlocked(oven, false)
		end
	end
end

function BakingPipeline.Init()
	for _, plot in (workspace:WaitForChild("Plots") :: Folder):GetChildren() do
		if plot:IsA("Model") then
			setupPlot(plot)
		end
	end
	PlotManager.PlotReleased:Connect(resetPlot)
	Inventory.Rolled:Connect(Pantry.ShowRoll)

	-- TycoonButtons shows/hides whole items; defer so the bin filter runs after it.
	PlotManager.PlotClaimed:Connect(function(_player, plot)
		task.defer(BakingPipeline.RefreshPantry, plot)
	end)
	TycoonButtons.UpgradeUnlocked:Connect(function(_player, plot)
		task.defer(BakingPipeline.RefreshPantry, plot)
	end)
	for _, plot in (workspace:WaitForChild("Plots") :: Folder):GetChildren() do
		if plot:IsA("Model") and PlotManager.GetOwner(plot) then
			task.defer(BakingPipeline.RefreshPantry, plot)
		end
	end
end


return BakingPipeline
