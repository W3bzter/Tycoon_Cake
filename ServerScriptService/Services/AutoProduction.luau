--!strict
-- Automated production lines, ticked on the server every TICK seconds per plot.
--
-- Line 1 is bought step by step and each step is useful on its own:
--   IngredientConveyor  fills the hopper with the line recipe's ingredients
--                       (no Auto-Mixer yet: grab the ready kit from the hopper)
--   AutoMixer           hopper -> batter tray (no Auto-Oven yet: take the batter)
--   AutoOven            batter -> cake tray, 1.5x slower than a player's oven until
--                       speed upgrades (no conveyor yet: take the cake)
--   CounterConveyor     cake tray -> display counter
--   AutoRestock         overflow storage rack that refills empty display slots
-- ProductionLine2/3 are self-contained units that run the whole chain.
-- Each line bakes one recipe, chosen on its panel; players can still bake any
-- recipe by hand in parallel. Automated ovens honour Blocked (Overheat Crisis).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Assets = require(script.Parent.Assets)
local BakingPipeline = require(script.Parent.BakingPipeline)
local DataManager = require(script.Parent.DataManager)
local Inventory = require(script.Parent.Inventory)
local PlotManager = require(script.Parent.PlotManager)
local PlotStats = require(script.Parent.PlotStats)
local Remotes = require(script.Parent.Remotes)
local ToolFactory = require(script.Parent.ToolFactory)

local AutoProduction = {}

local TICK = 0.5
local A = Config.Auto

type Line = {
	name: string,
	unitId: string?, -- set for self-contained production units
	recipe: string,
	hopper: number,
	batter: number,
	tray: { Rarity.CakeInfo }, -- finished cakes waiting
	feedT: number,
	mixT: number,
	bakeRemaining: number?, -- nil = oven idle
	baking: Rarity.CakeInfo?, -- the cake currently in the oven
	deliverT: number,
}

type PlotState = {
	lines: { Line },
	storage: { Rarity.CakeInfo }, -- cakes on the restock rack
}

local states: { [Model]: PlotState } = {}

local function newLine(name: string, unitId: string?): Line
	return {
		name = name,
		unitId = unitId,
		recipe = "Vanilla",
		hopper = 0,
		batter = 0,
		tray = {},
		feedT = 0,
		mixT = 0,
		bakeRemaining = nil,
		baking = nil,
		deliverT = 0,
	}
end

local function getItem(plot: Model, id: string): Model?
	local items = plot:FindFirstChild("Items")
	return items and items:FindFirstChild(id) :: Model?
end

local function owns(owner: Player, id: string): boolean
	return DataManager.HasUnlock(owner, id)
end

local function hasUnlockFn(owner: Player)
	return function(id: string)
		return DataManager.HasUnlock(owner, id)
	end
end

-- The oven model that bakes for a line (AutoOven for line 1, the unit itself otherwise).
local function ovenFor(plot: Model, line: Line): Model?
	return getItem(plot, line.unitId or "AutoOven")
end

-- The item whose part shows the line's status/recipe prompts.
local function controlFor(plot: Model, line: Line): (Model?, BasePart?)
	if line.unitId then
		local unit = getItem(plot, line.unitId)
		return unit, unit and unit:FindFirstChild("Panel") :: BasePart?
	end
	local conveyor = getItem(plot, "IngredientConveyor")
	return conveyor, conveyor and conveyor:FindFirstChild("Hopper") :: BasePart?
end

local function isLineActive(owner: Player, line: Line): boolean
	return owns(owner, line.unitId or "IngredientConveyor")
end

-- Visuals -------------------------------------------------------------------------------

-- `lift`: the hopper's status sits above its own machine sign (which is low);
-- production-unit panels have no sign of their own, so theirs sits just above.
local function statusGui(part: BasePart, lift: number): TextLabel
	local gui = part:FindFirstChild("LineStatus") :: BillboardGui?
	if not gui then
		local created = Instance.new("BillboardGui")
		created.Name = "LineStatus"
		created.Size = UDim2.fromScale(7, 1.2)
		created.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + lift, 0)
		created.MaxDistance = 35
		created.LightInfluence = 0
		created.AlwaysOnTop = true
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
		label.BackgroundTransparency = 0.15
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.Parent = created
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.4, 0)
		corner.Parent = label
		created.Parent = part
		gui = created
	end
	return (gui :: BillboardGui):FindFirstChild("Text") :: TextLabel
end

local function slide(plot: Model, cakeType: string, points: { Vector3 }, duration: number)
	-- Cosmetic cake riding the conveyor. Anchored model moved via a CFrameValue tween.
	local model = Assets.Clone("Cakes", cakeType)
	model:ScaleTo(model:GetScale() * 0.55)
	Assets.Anchor(model, CFrame.new(points[1]), plot)
	local value = Instance.new("CFrameValue")
	value.Value = model:GetPivot()
	value.Changed:Connect(function(cf)
		model:PivotTo(cf)
	end)
	local legTime = duration / math.max(1, #points - 1)
	task.spawn(function()
		local _, size = model:GetBoundingBox()
		for i = 2, #points do
			local tween = TweenService:Create(value, TweenInfo.new(legTime, Enum.EasingStyle.Linear), {
				Value = CFrame.new(points[i] + Vector3.new(0, size.Y / 2, 0)),
			})
			tween:Play()
			tween.Completed:Wait()
		end
		model:Destroy()
		value:Destroy()
	end)
end

local function refreshStorage(plot: Model, state: PlotState)
	local rack = getItem(plot, "AutoRestock")
	local markers = rack and rack:FindFirstChild("StorageSlots")
	local shown = plot:FindFirstChild("StoredCakes")
	if shown then
		shown:Destroy()
	end
	if not markers or #state.storage == 0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "StoredCakes"
	for i, info in state.storage do
		local marker = markers:FindFirstChild(`Store{i}`) :: BasePart?
		if marker then
			local model = Assets.Clone("Cakes", info.Type)
			model:ScaleTo(model:GetScale() * 0.6)
			Assets.Anchor(model, marker.CFrame, folder)
		end
	end
	folder.Parent = plot
end

-- Production -------------------------------------------------------------------------------

local function deliver(plot: Model, owner: Player, state: PlotState, info: Rarity.CakeInfo): boolean
	if BakingPipeline.PlaceCakeInFreeSlot(plot, info) then
		return true
	end
	local cap = PlotStats.Get(owner).StorageSlots
	if #state.storage < cap then
		table.insert(state.storage, info)
		refreshStorage(plot, state)
		return true
	end
	return false -- display and storage full: the line waits
end

local function tickLine(plot: Model, owner: Player, state: PlotState, line: Line)
	local isUnit = line.unitId ~= nil
	local has = function(id: string)
		return isUnit or owns(owner, id)
	end
	local recipe = Recipes.Cakes[line.recipe]
	if not recipe or not Recipes.IsUnlocked(line.recipe, hasUnlockFn(owner)) then
		line.recipe = "Vanilla"
		recipe = Recipes.Cakes.Vanilla
	end

	-- Feed
	if line.hopper < A.HopperCap then
		line.feedT += TICK
		if line.feedT >= A.FeedTime then
			line.feedT = 0
			line.hopper += 1
		end
	end

	-- Mix
	if has("AutoMixer") and line.hopper > 0 and line.batter < A.TrayCap then
		line.mixT += TICK
		if line.mixT >= A.MixTime then
			line.mixT = 0
			line.hopper -= 1
			line.batter = math.min(A.TrayCap, line.batter + PlotStats.Get(owner).MixBatch)
		end
	end

	-- Bake
	local oven = ovenFor(plot, line)
	if has("AutoOven") and oven then
		local blocked = oven:GetAttribute("Blocked") == true
		if line.bakeRemaining == nil then
			if line.batter > 0 and #line.tray < A.TrayCap and not blocked then
				line.batter -= 1
				-- Automated lines roll their ingredients too, with a fixed "Good" mix.
				line.baking = BakingPipeline.RollCake(owner, line.recipe)
				line.bakeRemaining = PlotStats.BakeDuration(owner, oven, Config.BakeTime * A.BakeMult)
			end
		elseif not blocked then
			line.bakeRemaining = (line.bakeRemaining :: number) - TICK
			if (line.bakeRemaining :: number) <= 0 then
				line.bakeRemaining = nil
				table.insert(line.tray, line.baking :: Rarity.CakeInfo)
				line.baking = nil
			end
		end
		BakingPipeline.SetDoorGlow(oven, line.bakeRemaining ~= nil and not blocked)
	end

	-- Deliver (conveyor for line 1; production units deliver directly)
	if has("CounterConveyor") and #line.tray > 0 then
		line.deliverT += TICK
		if line.deliverT >= A.DeliverTime then
			if deliver(plot, owner, state, line.tray[1]) then
				line.deliverT = 0
				table.remove(line.tray, 1)
			end
		elseif not isUnit and math.abs(line.deliverT - TICK) < 1e-6 then
			-- Show the cake riding the belt for this delivery.
			local floor = (plot.PrimaryPart :: BasePart).CFrame * CFrame.new(0, 0.6, 0)
			slide(plot, line.tray[1].Type, {
				(floor * CFrame.new(4, 0, -15)).Position,
				(floor * CFrame.new(4, 0, 27)).Position,
				(floor * CFrame.new(9, 0, 27)).Position,
			}, A.DeliverTime)
		end
	end
end

local function updatePrompts(plot: Model, owner: Player, line: Line)
	local control, part = controlFor(plot, line)
	if not control or not part or not control:GetAttribute("Visible") then
		return
	end
	local cake = Recipes.Cakes[line.recipe]
	local status: string
	if line.unitId then
		status = `🏭 {cake.Icon} | 🥣 {line.batter} | 🔥 {if line.bakeRemaining then `{math.ceil(line.bakeRemaining)}s` else "-"} | 🍰 {#line.tray}`
	else
		status = `{cake.Icon} 📦 {line.hopper}/{A.HopperCap}`
		if owns(owner, "AutoMixer") then
			status ..= ` | 🥣 {line.batter}`
		end
		if owns(owner, "AutoOven") then
			status ..= ` | 🔥 {if line.bakeRemaining then `{math.ceil(line.bakeRemaining)}s` else "-"} | 🍰 {#line.tray}`
		end
	end
	statusGui(part, if line.unitId then 1.6 else 3.2).Text = status

	local recipePrompt = part:FindFirstChild("RecipePrompt") :: ProximityPrompt?
	if recipePrompt then
		recipePrompt.ObjectText = `{line.name}: {cake.Icon} {cake.DisplayName}`
	end

	if line.unitId then
		return
	end
	-- Manual hand-offs for the steps that aren't automated yet.
	local grab = part:FindFirstChild("GrabPrompt") :: ProximityPrompt?
	if grab then
		grab.Enabled = not owns(owner, "AutoMixer") and line.hopper > 0
	end
	local mixer = getItem(plot, "AutoMixer")
	local mixerPrompt = mixer and mixer:FindFirstChild("TakePrompt", true) :: ProximityPrompt?
	if mixerPrompt then
		mixerPrompt.Enabled = mixer:GetAttribute("Visible") == true and not owns(owner, "AutoOven") and line.batter > 0
	end
	local oven = getItem(plot, "AutoOven")
	local ovenPrompt = oven and oven:FindFirstChild("TakePrompt", true) :: ProximityPrompt?
	if ovenPrompt then
		ovenPrompt.Enabled = oven:GetAttribute("Visible") == true and not owns(owner, "CounterConveyor") and #line.tray > 0
	end
end

local function tickPlot(plot: Model)
	local owner = PlotManager.GetOwner(plot)
	local state = states[plot]
	if not owner or not state then
		return
	end
	for _, line in state.lines do
		if isLineActive(owner, line) then
			tickLine(plot, owner, state, line)
			updatePrompts(plot, owner, line)
		end
	end
	-- Auto-Restock: refill empty display slots from storage.
	while #state.storage > 0 and BakingPipeline.PlaceCakeInFreeSlot(plot, state.storage[1]) do
		table.remove(state.storage, 1)
		refreshStorage(plot, state)
	end
end

-- Player interaction ------------------------------------------------------------------------

local function canUse(player: Player, plot: Model, part: BasePart): boolean
	if not PlotManager.IsOwner(player, plot) then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and (root.Position - part.Position).Magnitude <= 10 + Config.InteractSlack
end

local function notify(player: Player, message: string)
	Remotes.Get("Notify"):FireClient(player, message)
end

function AutoProduction.CycleRecipe(player: Player, plot: Model, lineIndex: number)
	local state = states[plot]
	local line = state and state.lines[lineIndex]
	if not line or not PlotManager.IsOwner(player, plot) then
		return
	end
	local menu = Recipes.Unlocked(hasUnlockFn(player))
	local i = table.find(menu, line.recipe) or 0
	line.recipe = menu[(i % #menu) + 1]
	-- Batter already made keeps its old type out of simplicity: clear in-progress work.
	line.hopper, line.batter, line.feedT, line.mixT = 0, 0, 0, 0
	local cake = Recipes.Cakes[line.recipe]
	notify(player, `{line.name} now bakes {cake.Icon} {cake.DisplayName}`)
end

function AutoProduction.GrabKit(player: Player, plot: Model)
	local line = states[plot] and states[plot].lines[1]
	if not line or line.hopper <= 0 or DataManager.HasUnlock(player, "AutoMixer") then
		return false
	end
	-- The kit goes into the Ingredient Bag as freshly rolled ingredients.
	local items = {}
	for _, ingredient in Recipes.Cakes[line.recipe].Ingredients do
		table.insert(items, Inventory.MakeItem(player, ingredient))
	end
	if not Inventory.AddItems(player, items) then
		notify(player, "🎒 Your bag is too full for a whole recipe kit!")
		return false
	end
	line.hopper -= 1
	return true
end

function AutoProduction.TakeBatter(player: Player, plot: Model)
	local line = states[plot] and states[plot].lines[1]
	if not line or line.batter <= 0 or DataManager.HasUnlock(player, "AutoOven") then
		return false
	end
	line.batter -= 1
	ToolFactory.GiveCakeItem(player, "RawBatter", BakingPipeline.RollCake(player, line.recipe))
	return true
end

function AutoProduction.TakeCake(player: Player, plot: Model)
	local line = states[plot] and states[plot].lines[1]
	if not line or #line.tray <= 0 or DataManager.HasUnlock(player, "CounterConveyor") then
		return false
	end
	ToolFactory.GiveCakeItem(player, "FinishedCake", table.remove(line.tray, 1) :: Rarity.CakeInfo)
	return true
end

local function addPrompt(part: BasePart, name: string, action: string, key: Enum.KeyCode, onTrigger: (Player) -> ())
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.KeyboardKeyCode = key
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration = 0.2
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = part
	prompt.Triggered:Connect(onTrigger)
	return prompt
end

local function setupPlot(plot: Model)
	states[plot] = {
		lines = { newLine("Line 1"), newLine("Line 2", "ProductionLine2"), newLine("Line 3", "ProductionLine3") },
		storage = {},
	}

	for index, line in states[plot].lines do
		local control, part = controlFor(plot, line)
		if control and part then
			addPrompt(part, "RecipePrompt", "Change Recipe", Enum.KeyCode.R, function(player)
				if canUse(player, plot, part) then
					AutoProduction.CycleRecipe(player, plot, index)
				end
			end)
		end
		local oven = ovenFor(plot, line)
		if oven then
			oven:SetAttribute("IsOven", true)
			oven:SetAttribute("IsAutoOven", true)
			oven:SetAttribute("Blocked", false)
		end
	end

	local _, hopper = controlFor(plot, states[plot].lines[1])
	if hopper then
		addPrompt(hopper, "GrabPrompt", "Grab Recipe Kit", Enum.KeyCode.E, function(player)
			if canUse(player, plot, hopper) then
				AutoProduction.GrabKit(player, plot)
			end
		end)
	end
	local mixer = getItem(plot, "AutoMixer")
	local mixerBody = mixer and mixer:FindFirstChild("Body") :: BasePart?
	if mixerBody then
		addPrompt(mixerBody, "TakePrompt", "Take Batter", Enum.KeyCode.E, function(player)
			if canUse(player, plot, mixerBody) then
				AutoProduction.TakeBatter(player, plot)
			end
		end)
	end
	local oven = getItem(plot, "AutoOven")
	local ovenBody = oven and oven:FindFirstChild("Body") :: BasePart?
	if ovenBody then
		addPrompt(ovenBody, "TakePrompt", "Take Cake", Enum.KeyCode.E, function(player)
			if canUse(player, plot, ovenBody) then
				AutoProduction.TakeCake(player, plot)
			end
		end)
	end
end

local function resetPlot(plot: Model)
	local state = states[plot]
	if not state then
		return
	end
	for i, line in state.lines do
		state.lines[i] = newLine(line.name, line.unitId)
	end
	state.storage = {}
	refreshStorage(plot, state)
end

-- Test/debug summary that crosses the DebugBridge cleanly.
function AutoProduction.Describe(plot: Model): string
	local state = states[plot]
	if not state then
		return "no state"
	end
	local parts = {}
	for _, line in state.lines do
		table.insert(parts, `{line.name}[{line.recipe}] hopper={line.hopper} batter={line.batter} baking={line.bakeRemaining and string.format("%.1f", line.bakeRemaining) or "-"} tray={#line.tray}`)
	end
	table.insert(parts, `storage={#state.storage}`)
	return table.concat(parts, " | ")
end

function AutoProduction.Init()
	for _, plot in (workspace:WaitForChild("Plots") :: Folder):GetChildren() do
		if plot:IsA("Model") then
			setupPlot(plot)
		end
	end
	PlotManager.PlotReleased:Connect(resetPlot)

	task.spawn(function()
		while true do
			task.wait(TICK)
			for plot in states do
				local ok, err = pcall(tickPlot, plot)
				if not ok then
					warn(`[AutoProduction] {plot.Name}: {err}`)
				end
			end
		end
	end)
end

return AutoProduction
