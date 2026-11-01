--!strict
-- Pantry bins -> Ingredient tools; Mixer -> typed RawBatter (best unlocked recipe
-- the held ingredients satisfy); Oven (timer) -> typed FinishedCake; Display
-- Counter: the cake model goes on a slot and is marked ForSale.
-- Every interaction is validated on the server: plot owner, machine unlocked,
-- player close enough, and holding the right items.
--
-- State lives in attributes so other services (CustomerAI, AnomalyManager) can read it:
--   Oven model:   OvenState = "Idle" | "Baking" | "Ready", BakeRemaining, Blocked, CakeType
--   Slot part:    HasCake, ForSale, Reserved, CakeType
--   Player:       UnlockedRecipes = "Vanilla,Chocolate" (for the client's mixer preview)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Assets = require(script.Parent.Assets)
local DataManager = require(script.Parent.DataManager)
local PlotManager = require(script.Parent.PlotManager)
local PlotStats = require(script.Parent.PlotStats)
local Remotes = require(script.Parent.Remotes)
local ToolFactory = require(script.Parent.ToolFactory)
local TycoonButtons = require(script.Parent.TycoonButtons)
local WorldBuilder = require(script.Parent.WorldBuilder)

local BakingPipeline = {}

local OVEN_IDS = { "Oven", "Oven2", "Oven3" } -- manual ovens (automated ones live in AutoProduction)
local COUNTER_IDS = { "DisplayCounter", "DisplayCounter2" }
local MACHINE_PART = {
	Mixer = "Body",
	Oven = "Body",
	Oven2 = "Body",
	Oven3 = "Body",
	DisplayCounter = "Counter",
	DisplayCounter2 = "Counter",
}

local function notify(player: Player, message: string)
	Remotes.Get("Notify"):FireClient(player, message)
end

local function getItem(plot: Model, id: string): Model?
	local items = plot:FindFirstChild("Items")
	return items and items:FindFirstChild(id) :: Model?
end

local function getPrompt(item: Instance): ProximityPrompt?
	return item:FindFirstChild("Prompt", true) :: ProximityPrompt?
end

local function isNear(player: Player, part: BasePart, prompt: ProximityPrompt): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	return (root.Position - part.Position).Magnitude <= prompt.MaxActivationDistance + Config.InteractSlack
end

local function hasUnlockFn(player: Player): (string) -> boolean
	return function(id)
		return DataManager.HasUnlock(player, id)
	end
end

local function cakeName(cakeType: string?): string
	local cake = cakeType and Recipes.Cakes[cakeType]
	return if cake then cake.DisplayName else "Cake"
end

-- Ovens ----------------------------------------------------------------------

local function setDoorGlow(oven: Model, on: boolean)
	local door = oven:FindFirstChild("Door") :: BasePart?
	if door then
		door.Material = if on then Enum.Material.Neon else Enum.Material.Glass
		door.Color = if on then Color3.fromRGB(255, 150, 60) else Color3.fromRGB(60, 40, 40)
	end
end

local function setOvenState(oven: Model, state: string)
	oven:SetAttribute("OvenState", state)
	setDoorGlow(oven, state == "Baking" and not oven:GetAttribute("Blocked"))
	local prompt = getPrompt(oven)
	if not prompt then
		return
	end
	if state == "Idle" then
		prompt.ActionText = "Bake Batter"
		prompt.ObjectText = "Oven"
	elseif state == "Baking" then
		prompt.ActionText = "Baking..."
	elseif state == "Ready" then
		prompt.ActionText = "Collect Cake"
		prompt.ObjectText = `{cakeName(oven:GetAttribute("CakeType") :: string?)} ready!`
	end
end

local function runBake(oven: Model, plot: Model)
	oven:SetAttribute("BakeRemaining", PlotStats.BakeDuration(PlotManager.GetOwner(plot), oven))
	setOvenState(oven, "Baking")
	local prompt = getPrompt(oven)
	while (oven:GetAttribute("BakeRemaining") :: number) > 0 do
		local dt = task.wait(0.25)
		if oven.Parent == nil or oven:GetAttribute("OvenState") ~= "Baking" then
			return -- plot was reset
		end
		if not oven:GetAttribute("Blocked") then -- Overheat Crisis pauses baking
			local remaining = math.max(0, (oven:GetAttribute("BakeRemaining") :: number) - dt)
			oven:SetAttribute("BakeRemaining", remaining)
			if prompt then
				prompt.ObjectText = `Oven ({math.ceil(remaining)}s)`
			end
		elseif prompt then
			prompt.ObjectText = "Oven (OVERHEATED)"
		end
	end
	setOvenState(oven, "Ready")
end

-- Overheat visuals + the Blocked flag runBake/ovenHandler respect.
function BakingPipeline.SetOvenBlocked(oven: Model, blocked: boolean)
	oven:SetAttribute("Blocked", blocked)
	local body = oven:FindFirstChild("Body") :: BasePart?
	if body then
		-- The body is a rounded box: the core part plus child pieces. Recolour them all.
		local shell: { BasePart } = { body }
		for _, d in body:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(shell, d)
			end
		end
		for _, p in shell do
			if p:GetAttribute("NormalColor") == nil then
				p:SetAttribute("NormalColor", p.Color)
			end
			p.Color = if blocked then Color3.fromRGB(230, 40, 30) else p:GetAttribute("NormalColor") :: Color3
		end
		setDoorGlow(oven, not blocked and oven:GetAttribute("OvenState") == "Baking")

		local smoke = body:FindFirstChild("OverheatSmoke")
		if blocked then
			if not smoke then
				local s = Instance.new("Smoke")
				s.Name = "OverheatSmoke"
				s.Color = Color3.fromRGB(60, 60, 60)
				s.Size = 4
				s.RiseVelocity = 6
				s.Opacity = 0.6
				s.Parent = body
			end
		elseif smoke then
			smoke:Destroy()
		end
	end

	-- Automated ovens manage their own prompts (AutoProduction).
	local prompt = if oven:GetAttribute("IsAutoOven") then nil else getPrompt(oven)
	if prompt then
		if blocked then
			prompt.ObjectText = "Oven (OVERHEATED)"
		else
			setOvenState(oven, oven:GetAttribute("OvenState") :: string)
		end
	end
end

-- Every unlocked oven on the plot, manual or automated (anything tagged IsOven).
function BakingPipeline.GetOvens(plot: Model): { Model }
	local ovens = {}
	local items = plot:FindFirstChild("Items")
	for _, item in (if items then items:GetChildren() else {}) do
		if item:IsA("Model") and item:GetAttribute("IsOven") and item:GetAttribute("Visible") then
			table.insert(ovens, item)
		end
	end
	return ovens
end

BakingPipeline.SetDoorGlow = setDoorGlow

-- Display slots ----------------------------------------------------------------

-- Slots on every unlocked display counter (names are unique per plot: "<Counter>_<i>").
local function getSlots(plot: Model, includeHidden: boolean?): { BasePart }
	local slots = {}
	for _, counterId in COUNTER_IDS do
		local counter = getItem(plot, counterId)
		local folder = counter and (includeHidden or counter:GetAttribute("Visible")) and counter:FindFirstChild("Slots")
		if folder then
			for i = 1, Config.DisplaySlots do
				local slot = folder:FindFirstChild(`{counterId}_{i}`) :: BasePart?
				if slot then
					table.insert(slots, slot)
				end
			end
		end
	end
	return slots
end
BakingPipeline.GetSlots = getSlots

local function cakesFolder(plot: Model): Folder
	local folder = plot:FindFirstChild("Cakes") :: Folder?
	if not folder then
		local created = Instance.new("Folder")
		created.Name = "Cakes"
		created.Parent = plot
		folder = created
	end
	return folder :: Folder
end

local function placeCake(plot: Model, slot: BasePart, cakeType: string)
	local model = Assets.Clone("Cakes", cakeType)
	model.Name = slot.Name
	model:SetAttribute("CakeType", cakeType)
	Assets.Anchor(model, slot.CFrame * CFrame.new(0, slot.Size.Y / 2, 0), cakesFolder(plot))

	slot:SetAttribute("CakeType", cakeType)
	slot:SetAttribute("HasCake", true)
	slot:SetAttribute("ForSale", true)
	slot:SetAttribute("Reserved", false)
end

-- Puts a cake on the first free display slot (used by automation). False if full.
function BakingPipeline.PlaceCakeInFreeSlot(plot: Model, cakeType: string): boolean
	for _, slot in getSlots(plot) do
		if not slot:GetAttribute("HasCake") then
			placeCake(plot, slot, cakeType)
			return true
		end
	end
	return false
end

-- Slots with a cake for sale that no customer has claimed yet.
function BakingPipeline.GetSaleSlots(plot: Model): { BasePart }
	local result = {}
	for _, slot in getSlots(plot) do
		if slot:GetAttribute("ForSale") and not slot:GetAttribute("Reserved") then
			table.insert(result, slot)
		end
	end
	return result
end

function BakingPipeline.ReserveSlot(slot: BasePart): boolean
	if slot:GetAttribute("ForSale") and not slot:GetAttribute("Reserved") then
		slot:SetAttribute("Reserved", true)
		return true
	end
	return false
end

function BakingPipeline.ReleaseSlot(slot: BasePart)
	slot:SetAttribute("Reserved", false)
end

-- Removes the cake from a slot. Returns true and its type if there was one.
function BakingPipeline.TakeCake(plot: Model, slot: BasePart): (boolean, string?)
	if not slot:GetAttribute("HasCake") then
		return false, nil
	end
	local cakeType = slot:GetAttribute("CakeType") :: string?
	local cake = cakesFolder(plot):FindFirstChild(slot.Name)
	if cake then
		cake:Destroy()
	end
	slot:SetAttribute("HasCake", false)
	slot:SetAttribute("ForSale", false)
	slot:SetAttribute("Reserved", false)
	slot:SetAttribute("CakeType", nil)
	return true, cakeType or "Vanilla"
end

-- Pantry ---------------------------------------------------------------------------

local function getBin(plot: Model, ingredient: string): Model?
	local pantry = getItem(plot, "IngredientCrate")
	local bins = pantry and pantry:FindFirstChild("Bins")
	return bins and bins:FindFirstChild(ingredient) :: Model?
end

-- Shows only the bins whose ingredient some unlocked recipe uses, and mirrors the
-- unlocked recipe list onto the player for the client-side mixer preview.
function BakingPipeline.RefreshPantry(plot: Model)
	local owner = PlotManager.GetOwner(plot)
	local pantry = getItem(plot, "IngredientCrate")
	if owner then
		owner:SetAttribute("UnlockedRecipes", table.concat(Recipes.Unlocked(hasUnlockFn(owner)), ","))
	end
	if not pantry or not pantry:GetAttribute("Visible") then
		return
	end
	local needed = if owner then Recipes.NeededIngredients(hasUnlockFn(owner)) else {}
	for _, ingredient in Recipes.IngredientOrder do
		local bin = getBin(plot, ingredient)
		if bin then
			WorldBuilder.SetVisible(bin, needed[ingredient] == true)
		end
	end
end

-- Interactions -------------------------------------------------------------------

local handlers: { [string]: (Player, Model, Model, string?) -> () } = {}

handlers.IngredientCrate = function(player, _plot, _item, ingredient)
	if not ingredient then
		return
	end
	if ToolFactory.Count(player, "Ingredient") >= Config.MaxIngredientsHeld then
		notify(player, `You can only carry {Config.MaxIngredientsHeld} ingredients.`)
		return
	end
	ToolFactory.Give(player, "Ingredient", ingredient)
end

handlers.Mixer = function(player)
	local held: { [string]: number } = {}
	for _, tool in ToolFactory.Find(player, "Ingredient") do
		local name = tool:GetAttribute("Variant") :: string?
		if name then
			held[name] = (held[name] or 0) + 1
		end
	end
	local cakeType = Recipes.BestRecipe(held, hasUnlockFn(player))
	if not cakeType then
		notify(player, "No recipe matches! Vanilla needs 🌾 Flour, 🥚 Eggs and 🍬 Sugar.")
		return
	end
	for _, ingredient in Recipes.Cakes[cakeType].Ingredients do
		ToolFactory.Take(player, "Ingredient", 1, ingredient)
	end
	local batch = PlotStats.Get(player).MixBatch -- Big Mixer makes 2 per mix
	for _ = 1, batch do
		ToolFactory.Give(player, "RawBatter", cakeType)
	end
	notify(player, if batch > 1 then `Mixed {batch}x {cakeName(cakeType)} batter!` else `Mixed {cakeName(cakeType)} batter!`)
end

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
		oven:SetAttribute("CakeType", batter:GetAttribute("Variant") or "Vanilla")
		batter:Destroy()
		task.spawn(runBake, oven, plot)
	elseif state == "Ready" then
		local cakeType = (oven:GetAttribute("CakeType") :: string?) or "Vanilla"
		setOvenState(oven, "Idle")
		ToolFactory.Give(player, "FinishedCake", cakeType)
	end
end
handlers.Oven = ovenHandler
handlers.Oven2 = ovenHandler
handlers.Oven3 = ovenHandler

local function counterHandler(player: Player, plot: Model, counter: Model)
	-- Prefer this counter's own slots, then any other counter's.
	local free: BasePart? = nil
	for _, slot in getSlots(plot) do
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
	local cakeType = (cake:GetAttribute("Variant") :: string?) or "Vanilla"
	cake:Destroy()
	placeCake(plot, free :: BasePart, cakeType)
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

	local target: Instance? = item
	local part: BasePart?
	if machineId == "IngredientCrate" then
		local bin = arg and getBin(plot, arg)
		if not bin or not bin:GetAttribute("Visible") then
			return false -- unknown ingredient or not unlocked yet
		end
		target = bin
		part = bin:FindFirstChild("Bin") :: BasePart?
	else
		part = item:FindFirstChild(MACHINE_PART[machineId]) :: BasePart?
	end
	local prompt = target and getPrompt(target)
	if not part or not prompt or not isNear(player, part, prompt) then
		return false
	end
	handler(player, plot, item, arg)
	return true
end

-- Setup ------------------------------------------------------------------------

local PROMPT_TEXT = {
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
			if table.find(OVEN_IDS, machineId) then
				item:SetAttribute("IsOven", true)
				item:SetAttribute("Blocked", false)
				setOvenState(item, "Idle")
			end
		end
	end

	-- One prompt per pantry bin.
	local pantry = getItem(plot, "IngredientCrate")
	if pantry then
		for _, ingredient in Recipes.IngredientOrder do
			local bin = getBin(plot, ingredient)
			local binPart = bin and bin:FindFirstChild("Bin") :: BasePart?
			if bin and binPart then
				local info = Recipes.Ingredients[ingredient]
				local prompt = makePrompt(binPart, `Take {info.DisplayName}`, `{info.Icon} Pantry`, bin:GetAttribute("Visible") == true, 6)
				prompt.Triggered:Connect(function(player)
					BakingPipeline.Interact(player, plot, "IngredientCrate", ingredient)
				end)
			end
		end
	end

	-- Invisible markers on top of each counter where cakes are shown.
	for _, counterId in COUNTER_IDS do
		local counter = getItem(plot, counterId)
		local counterPart = counter and counter:FindFirstChild("Counter") :: BasePart?
		if counter and counterPart then
			buildSlots(counter, counterPart, counterId)
		end
	end
end

local function resetPlot(plot: Model)
	for _, slot in getSlots(plot, true) do
		BakingPipeline.TakeCake(plot, slot)
	end
	for _, id in OVEN_IDS do
		local oven = getItem(plot, id)
		if oven then
			setOvenState(oven, "Idle")
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
