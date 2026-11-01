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
local BuildService = require(Services.Build.BuildService)
local Display = require(Services.Baking.Display)
local Inventory = require(Services.Baking.Inventory)
local Ovens = require(Services.Baking.Ovens)
local Pantry = require(Services.Baking.Pantry)
local PlotManager = require(Services.Core.PlotManager)
local PlotStats = require(Services.Core.PlotStats)
local Prompts = require(Services.Core.Prompts)
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

-- Hand tools are slower than machines.
local BASIC_OVEN_SPEED = 2 -- bake-time multiplier for the Basic Oven
-- Which part carries a machine's prompt, by kind.
local PROMPT_PART = { Pantry = "Crate", MixStation = "Body", Oven = "Body", Counter = "Counter" }
local PROMPT_TEXT = {
	IngredientCrate = { "🎲 Roll Ingredients", "Pantry (free)" },
	PrepTable = { "Whisk Batter", "Mixing Bowl" },
	Mixer = { "Mix Batter", "Mixer" },
	BigMixer = { "Mix Batter", "Big Mixer" },
	BasicOven = { "Bake Batter", "Basic Oven" },
	Oven = { "Bake Batter", "Oven" },
	DisplayCounter = { "Display Cake", "Display Counter" },
}

local idOf = BakeUtil.idOf

-- The placed item's Kind ("Pantry", "MixStation", "Oven", "Counter", "Decor").
local function kindOf(model: Model): string?
	return model:GetAttribute("Kind") :: string?
end

local function plotOf(model: Model): Model?
	local plots = workspace:FindFirstChild("Plots")
	local node: Instance? = model
	while node and node.Parent ~= plots do
		node = node.Parent
	end
	return node :: Model?
end

-- Interactions -------------------------------------------------------------------

local handlers: { [string]: (Player, Model, Model, string?) -> () } = {}

-- The pantry is a free roll: one of every needed ingredient into the bag.
handlers.Pantry = function(player)
	Inventory.Roll(player)
end

-- Mixes one batch from the Ingredient Bag (pinned first, then most valuable).
-- `quality` comes from the mixing minigame; "Good" without it.
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
	-- The Big Mixer makes 2 per mix (PlotStats.MixBatch); the hand bowl always makes 1.
	local batch = if idOf(station) ~= "PrepTable" then PlotStats.Get(player).MixBatch else 1
	for _ = 1, batch do
		ToolFactory.GiveCakeItem(player, "RawBatter", info)
	end
	notify(player, `{info.Quality} mix! {batch > 1 and `{batch}x ` or ""}{Rarity.Name(info.Rarity)} {cakeName(cakeType)} batter (${info.Value})`)
	return info
end

-- Set by MixingGame: starts the minigame, which calls Mix with the grade.
-- Without it, mixing happens instantly at "Good" quality.
BakingPipeline.OnMixRequested = nil :: ((Player, Model) -> ())?

handlers.MixStation = function(player, _plot, station)
	if not Inventory.PeekRecipe(player) then
		BakingPipeline.Mix(player, station) -- explains what's missing
	elseif BakingPipeline.OnMixRequested then
		BakingPipeline.OnMixRequested(player, station)
	else
		BakingPipeline.Mix(player, station)
	end
end

-- E on the oven: collect a finished cake if there is one, otherwise load every
-- Raw Batter you carry into the free racks (Baking/Ovens).
handlers.Oven = function(player, plot, oven)
	if oven:GetAttribute("Blocked") then
		notify(player, "This oven is overheating! Put it out first.")
		return
	end
	local ready = Ovens.RackIn(oven, "Ready")
	if ready then
		local info = Ovens.Collect(oven, ready)
		if Inventory.ShouldDelete(player, "Cake", info.Rarity, Rarity.IsSpecial(info)) then
			notify(player, `🗑️ Auto-deleted a {Rarity.Name(info.Rarity)} {cakeName(info.Type)}`)
			return
		end
		ToolFactory.GiveCakeItem(player, "FinishedCake", info)
		return
	end
	local batters = ToolFactory.Find(player, "RawBatter")
	if #batters == 0 then
		notify(player, "You need Raw Batter from the mixer.")
		return
	end
	local loaded = 0
	for _, batter in batters do
		local rack = Ovens.RackIn(oven, "Idle")
		if not rack then
			break
		end
		Ovens.Load(oven, rack, ToolFactory.GetCakeInfo(batter), plot)
		batter:Destroy()
		loaded += 1
	end
	if loaded == 0 then
		notify(player, "Every rack is baking. Buy more Oven Racks in the Build shop's Upgrades tab!")
	end
end

handlers.Counter = function(player, plot, counter)
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

-- Single validated entry point (prompts call this; tests can too via DebugBridge).
-- `machine` is the model, or its name / catalog id ("Oven", "IngredientCrate").
function BakingPipeline.Interact(player: Player, plot: Model, machine: Model | string, arg: string?): boolean
	local model = if typeof(machine) == "string" then BakeUtil.findMachine(plot, machine) else machine
	if not model or not model:IsDescendantOf(plot) then
		return false
	end
	local kind = kindOf(model)
	local handler = kind and handlers[kind]
	if not handler or not PlotManager.IsOwner(player, plot) or model:GetAttribute("Visible") ~= true then
		return false
	end
	if kind == "Pantry" and not DataManager.HasUnlock(player, "IngredientCrate") then
		return false
	end
	if model:GetAttribute("Broken") then
		notify(player, `🔧 This machine is broken! Hold Q to repair it (${model:GetAttribute("RepairCost") or "?"}).`)
		return false
	end
	local part = model:FindFirstChild(PROMPT_PART[kind :: string]) :: BasePart?
	local prompt = Prompts.Get(model, "Prompt")
	if not part or not prompt or not isNear(player, part, prompt) then
		return false
	end
	handler(player, plot, model, arg)
	return true
end

-- Setup ------------------------------------------------------------------------

local function buildSlots(counter: Model, counterPart: BasePart)
	local old = counter:FindFirstChild("Slots")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Slots"
	local spacing = counterPart.Size.X / (Config.DisplaySlots + 1)
	for i = 1, Config.DisplaySlots do
		local slot = Instance.new("Part")
		slot.Name = `{counter.Name}_{i}` -- unique per plot
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

-- Gives a machine its prompt and state (fixed pantry at start, placed items when placed).
local function setupMachine(plot: Model, model: Model)
	local kind = kindOf(model)
	local partName = kind and PROMPT_PART[kind :: string]
	local part = partName and model:FindFirstChild(partName) :: BasePart?
	if not kind or not part then
		return -- decor has no machine prompt
	end
	local text = PROMPT_TEXT[idOf(model)] or { "Use", idOf(model) }
	Prompts.Add(model, part, {
		Name = "Prompt",
		Action = text[1],
		Object = text[2],
		Key = Config.Prompts.Keys.Main,
		Hold = if idOf(model) == "PrepTable" then Config.Prompts.HandMixHold else nil,
		Trigger = function(player)
			BakingPipeline.Interact(player, plot, model)
		end,
	})
	if kind == "Oven" then
		model:SetAttribute("IsOven", true)
		model:SetAttribute("Blocked", false)
		model:SetAttribute("SpeedMult", if idOf(model) == "BasicOven" then BASIC_OVEN_SPEED else nil) -- read by PlotStats.BakeDuration
		Ovens.Setup(model, plot) -- racks + upgrade visuals
	elseif kind == "Counter" then
		buildSlots(model, part)
	end
end

-- A placed item may not be moved/stored/upgraded while it's busy.
local function busyReason(model: Model, action: string): string?
	local kind = kindOf(model)
	-- No OvenState yet = setupMachine (a deferred ItemPlaced handler) hasn't run: a brand-new, empty oven.
	local state = model:GetAttribute("OvenState")
	if kind == "Oven" and ((state ~= nil and state ~= "Idle") or model:GetAttribute("Blocked")) then
		return "The oven is busy: wait for its cakes and collect them first."
	end
	local plot = plotOf(model)
	if kind == "Counter" and action ~= "move" and plot then
		for _, slot in Display.GetSlots(plot) do
			if slot:IsDescendantOf(model) and slot:GetAttribute("HasCake") then
				return "Sell the cakes on this counter first."
			end
		end
	end
	return nil
end

local function resetPlot(plot: Model)
	for _, slot in Display.GetSlots(plot, true) do
		BakingPipeline.TakeCake(plot, slot)
	end
	for _, oven in Ovens.GetOvens(plot) do
		if not oven:GetAttribute("IsAutoOven") then
			Ovens.ResetOven(oven)
			BakingPipeline.SetOvenBlocked(oven, false)
		end
	end
end

function BakingPipeline.Init()
	BuildService.OnPlaced(function(plot, model)
		setupMachine(plot, model)
		if kindOf(model) == "Pantry" then
			task.defer(BakingPipeline.RefreshPantry, plot) -- show only the bins your recipes use
		end
	end)
	BuildService.ItemMoved:Connect(function(plot, model)
		if kindOf(model) == "Counter" then
			Display.Reposition(plot, model)
		end
	end)
	table.insert(BuildService.Blockers, busyReason)
	PlotManager.PlotReleased:Connect(resetPlot)
	Inventory.Rolled:Connect(Pantry.ShowRoll)

	-- TycoonButtons shows/hides whole items; defer so the bin filter runs after it.
	PlotManager.PlotClaimed:Connect(function(_player, plot)
		task.defer(BakingPipeline.RefreshPantry, plot)
	end)
	TycoonButtons.UpgradeUnlocked:Connect(function(_player, plot)
		task.defer(BakingPipeline.RefreshPantry, plot)
		Ovens.SetupPlot(plot) -- Oven Rack / Oven Speed / Golden Oven bought
	end)
	for _, plot in (workspace:WaitForChild("Plots") :: Folder):GetChildren() do
		if plot:IsA("Model") and PlotManager.GetOwner(plot) then
			task.defer(BakingPipeline.RefreshPantry, plot)
		end
	end
end

return BakingPipeline
