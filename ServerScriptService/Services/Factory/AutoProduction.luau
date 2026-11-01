--!strict
-- Automated production lines, ticked on the server every TICK seconds per plot.
--
-- Hoppers never fill themselves: players load them from their Ingredient Bag
-- (prompt "Load Hopper" = one recipe set, "Fill Hopper" = up to the cap), and the
-- line turns exactly those ingredients into batter and cakes (fixed "Good" mix),
-- so cake values come from what you loaded. The Full Automation Game Pass
-- (GamePasses) auto-loads the cheapest unpinned ingredients and auto-rolls at the
-- pantry when the bag can't fill a hopper.
--
-- Line 1 is bought step by step and each step is useful on its own:
--   IngredientConveyor  the hopper (no Auto-Mixer yet: unload a kit back to the bag)
--   AutoMixer           hopper -> batter tray (no Auto-Oven yet: take the batter)
--   AutoOven            batter -> cake tray, 1.5x slower than a player's oven until
--                       speed upgrades (no conveyor yet: take the cake)
--   CounterConveyor     cake tray -> display counter
--   AutoRestock         overflow storage rack that refills empty display slots
-- ProductionLine2/3 are self-contained units that run the whole chain.
-- Each line has an on/off switch (saved in PlayerData.LinesEnabled) and a recipe
-- (PlayerData.LineRecipes). Hopper contents are saved (PlayerData.Hoppers).
-- Automated ovens honour Blocked (Overheat Crisis).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Services = script:FindFirstAncestor("Services") :: Folder
local Assets = require(Services.World.Assets)
local BakingPipeline = require(Services.Baking.BakingPipeline)
local DataManager = require(Services.Core.DataManager)
local GamePasses = require(Services.Core.GamePasses)
local Inventory = require(Services.Baking.Inventory)
local PlotManager = require(Services.Core.PlotManager)
local PlotStats = require(Services.Core.PlotStats)
local Remotes = require(Services.Core.Remotes)
local ToolFactory = require(Services.Core.ToolFactory)
local VFX = require(Services.Effects.VFX)

local AutoProduction = {}

local TICK = 0.5
local A = Config.Auto

-- One loaded recipe's worth of ingredients.
type HopperSet = { Recipe: string, Items: { Rarity.Item } }

type Line = {
	index: number,
	name: string,
	unitId: string?, -- set for self-contained production units
	recipe: string, -- what "Load Hopper" loads next (saved in LineRecipes)
	hopper: { HopperSet }, -- the owner's saved PlayerData.Hoppers[index] while claimed
	batter: { Rarity.CakeInfo },
	tray: { Rarity.CakeInfo }, -- finished cakes waiting
	mixT: number,
	bakeRemaining: number?, -- nil = oven idle
	baking: Rarity.CakeInfo?, -- the cake currently in the oven
	deliverT: number,
	autoLoadT: number,
	starved: boolean?, -- Full Automation: bag full and nothing usable
}

type PlotState = {
	lines: { Line },
	storage: { Rarity.CakeInfo }, -- cakes on the restock rack
}

local states: { [Model]: PlotState } = {}
local lastStarveWarning: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any


local function newLine(index: number, name: string, unitId: string?): Line
	return {
		index = index,
		name = name,
		unitId = unitId,
		recipe = "Vanilla",
		hopper = {},
		batter = {},
		tray = {},
		mixT = 0,
		bakeRemaining = nil,
		baking = nil,
		deliverT = 0,
		autoLoadT = 0,
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

local function notify(player: Player, message: string)
	Remotes.Get("Notify"):FireClient(player, message)
end

local function isEnabled(owner: Player, line: Line): boolean
	local data = DataManager.Get(owner)
	return data == nil or data.LinesEnabled[line.index] ~= false
end

-- A machine is usable if it isn't Broken (Repairs, Phase 8).
local function working(model: Model?): boolean
	return model ~= nil and model:GetAttribute("Broken") ~= true
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

local function slide(plot: Model, info: Rarity.CakeInfo, points: { Vector3 }, duration: number)
	-- Cosmetic cake riding the conveyor. Anchored model moved via a CFrameValue tween.
	local model = Assets.Clone("Cakes", info.Type)
	model:ScaleTo(model:GetScale() * 0.55)
	Assets.Anchor(model, CFrame.new(points[1]), plot)
	VFX.ApplyCake(model, info, true)
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
		if marker then -- extra (upgraded) slots are stored but not all shown
			local model = Assets.Clone("Cakes", info.Type)
			model:ScaleTo(model:GetScale() * 0.6)
			Assets.Anchor(model, marker.CFrame, folder)
			VFX.ApplyCake(model, info, true)
		end
	end
	folder.Parent = plot
end

-- Loading ---------------------------------------------------------------------------------

-- Moves recipe sets from the owner's bag into the hopper. Returns how many loaded.
local function loadSets(owner: Player, line: Line, maxSets: number, order: string): number
	local loaded = 0
	while loaded < maxSets and #line.hopper < A.HopperCap do
		local cakeType, items = Inventory.TakeForRecipe(owner, line.recipe, order)
		if not cakeType or not items then
			break
		end
		table.insert(line.hopper, { Recipe = cakeType, Items = items })
		loaded += 1
	end
	return loaded
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
	if not Recipes.IsUnlocked(line.recipe, hasUnlockFn(owner)) then
		line.recipe = "Vanilla"
	end
	local oven = ovenFor(plot, line)
	if not isEnabled(owner, line) then
		if oven and has("AutoOven") then
			BakingPipeline.SetDoorGlow(oven, false)
		end
		return
	end

	-- Full Automation pass: keep the hopper topped up from the bag.
	local hopperOk = working((controlFor(plot, line)))
	if hopperOk and GamePasses.Owns(owner, "FullAutomation") and #line.hopper < A.HopperCap then
		line.autoLoadT += TICK
		if line.autoLoadT >= A.AutoLoadInterval then
			line.autoLoadT = 0
			if loadSets(owner, line, 1, "cheapest") > 0 then
				line.starved = false
			elseif Inventory.RollFits(owner) then
				Inventory.Roll(owner, true) -- normal cooldown and odds; loads next time
			else
				-- The bag is too full to roll and has nothing this line can use.
				line.starved = true
				local now = os.clock()
				if now - (lastStarveWarning[owner] or 0) > 45 then
					lastStarveWarning[owner] = now
					notify(owner, `🎒 {line.name} is starving: your bag is full of ingredients it can't use. Toss some, change its recipe, or mix by hand!`)
				end
			end
		end
	end

	-- Mix
	local mixer = if isUnit then getItem(plot, line.unitId :: string) else getItem(plot, "AutoMixer")
	if hopperOk and has("AutoMixer") and working(mixer) and #line.hopper > 0 and #line.batter < A.TrayCap then
		line.mixT += TICK
		if line.mixT >= A.MixTime then
			line.mixT = 0
			local set = table.remove(line.hopper, 1) :: HopperSet
			local cake = Recipes.Cakes[set.Recipe] or Recipes.Cakes.Vanilla
			local info = Rarity.MakeCake(set.Recipe, cake.Price, set.Items, "Good")
			if not Inventory.ShouldDelete(owner, "Batter", info.Rarity, Rarity.IsSpecial(info)) then
				for _ = 1, PlotStats.Get(owner).MixBatch do
					if #line.batter < A.TrayCap then
						table.insert(line.batter, table.clone(info))
					end
				end
			end
		end
	end

	-- Bake
	if has("AutoOven") and oven then
		local blocked = oven:GetAttribute("Blocked") == true or not working(oven)
		if line.bakeRemaining == nil then
			if #line.batter > 0 and #line.tray < A.TrayCap and not blocked then
				line.baking = table.remove(line.batter, 1)
				line.bakeRemaining = PlotStats.BakeDuration(owner, oven, Config.BakeTime * A.BakeMult)
					* (if (line.baking :: Rarity.CakeInfo).Fresh then Rarity.FreshBakeMult else 1)
			end
		elseif not blocked then
			line.bakeRemaining = (line.bakeRemaining :: number) - TICK
			if (line.bakeRemaining :: number) <= 0 then
				line.bakeRemaining = nil
				local info = BakingPipeline.FinishBake(owner, oven, line.baking :: Rarity.CakeInfo, false)
				line.baking = nil
				if not Inventory.ShouldDelete(owner, "Cake", info.Rarity, Rarity.IsSpecial(info)) then
					table.insert(line.tray, info)
				end
			end
		end
		BakingPipeline.SetDoorGlow(oven, line.bakeRemaining ~= nil and not blocked)
	end

	-- Deliver (conveyor for line 1; production units deliver directly)
	local conveyor = if isUnit then nil else getItem(plot, "CounterConveyor")
	local jammed = (if isUnit then getItem(plot, line.unitId :: string) else conveyor)
	jammed = if jammed and (jammed:GetAttribute("JammedUntil") or 0) > os.clock() then jammed else nil
	if has("CounterConveyor") and #line.tray > 0 and (isUnit or working(conveyor)) and not jammed then
		line.deliverT += TICK
		if line.deliverT >= A.DeliverTime then
			if deliver(plot, owner, state, line.tray[1]) then
				line.deliverT = 0
				table.remove(line.tray, 1)
			end
		elseif not isUnit and math.abs(line.deliverT - TICK) < 1e-6 then
			-- Show the cake riding the belt for this delivery.
			local floor = (plot.PrimaryPart :: BasePart).CFrame * CFrame.new(0, 0.6, 0)
			slide(plot, line.tray[1], {
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
	local enabled = isEnabled(owner, line)
	local auto = if GamePasses.Owns(owner, "FullAutomation") then "🤖" else ""
	local hopperText = `{auto}📦 {#line.hopper}/{A.HopperCap}`
	local bakeText = if line.bakeRemaining then `{math.ceil(line.bakeRemaining)}s` else "-"
	local status: string
	if not enabled then
		status = `⏸ OFF | {cake.Icon} {hopperText}`
	elseif line.unitId then
		status = `🏭 {cake.Icon} {hopperText} | 🥣 {#line.batter} | 🔥 {bakeText} | 🍰 {#line.tray}`
	else
		status = `{cake.Icon} {hopperText}`
		if owns(owner, "AutoMixer") then
			status ..= ` | 🥣 {#line.batter}`
		end
		if owns(owner, "AutoOven") then
			status ..= ` | 🔥 {bakeText} | 🍰 {#line.tray}`
		end
	end
	if line.starved and #line.hopper == 0 and auto ~= "" then
		status ..= " | 🎒 bag full!"
	elseif #line.hopper == 0 and enabled and auto == "" then
		status ..= " | load me!"
	end
	statusGui(part, if line.unitId then 1.6 else 3.2).Text = status

	local recipePrompt = part:FindFirstChild("RecipePrompt") :: ProximityPrompt?
	if recipePrompt then
		recipePrompt.ObjectText = `{line.name}: {cake.Icon} {cake.DisplayName}`
	end
	local load = part:FindFirstChild("LoadPrompt") :: ProximityPrompt?
	local fill = part:FindFirstChild("FillPrompt") :: ProximityPrompt?
	local full = #line.hopper >= A.HopperCap
	if load then
		load.Enabled = not full
		load.ObjectText = `{line.name} hopper {#line.hopper}/{A.HopperCap}`
	end
	if fill then
		fill.Enabled = not full
	end
	local toggle = part:FindFirstChild("TogglePrompt") :: ProximityPrompt?
	if toggle then
		toggle.Enabled = true
		toggle.ActionText = if enabled then "⏸ Turn Off" else "▶ Turn On"
		toggle.ObjectText = line.name
	end

	if line.unitId then
		return
	end
	-- Manual hand-offs for the steps that aren't automated yet.
	local grab = part:FindFirstChild("GrabPrompt") :: ProximityPrompt?
	if grab then
		grab.Enabled = not owns(owner, "AutoMixer") and #line.hopper > 0
	end
	local mixer = getItem(plot, "AutoMixer")
	local mixerPrompt = mixer and mixer:FindFirstChild("TakePrompt", true) :: ProximityPrompt?
	if mixerPrompt then
		mixerPrompt.Enabled = mixer:GetAttribute("Visible") == true and not owns(owner, "AutoOven") and #line.batter > 0
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
	if not owner or not state or not DataManager.IsLoaded(owner) then
		return
	end
	for _, line in state.lines do
		if isLineActive(owner, line) then
			tickLine(plot, owner, state, line)
			updatePrompts(plot, owner, line)
		end
	end
	-- Auto-Restock: refill empty display slots from storage.
	local moved = false
	while #state.storage > 0 and BakingPipeline.PlaceCakeInFreeSlot(plot, state.storage[1]) do
		table.remove(state.storage, 1)
		moved = true
	end
	if moved then
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

local function lineAt(plot: Model, index: number): Line?
	local state = states[plot]
	return state and state.lines[index]
end

function AutoProduction.CycleRecipe(player: Player, plot: Model, lineIndex: number)
	local line = lineAt(plot, lineIndex)
	local data = DataManager.Get(player)
	if not line or not data or not PlotManager.IsOwner(player, plot) then
		return
	end
	local menu = Recipes.Unlocked(hasUnlockFn(player))
	local i = table.find(menu, line.recipe) or 0
	line.recipe = menu[(i % #menu) + 1]
	data.LineRecipes[lineIndex] = line.recipe
	-- Sets already in the hopper keep their own recipe; only new loads change.
	local cake = Recipes.Cakes[line.recipe]
	notify(player, `{line.name} now loads {cake.Icon} {cake.DisplayName}`)
end

-- Hand loading: `fill` loads up to the cap, otherwise one set. Pinned (★) items
-- are used first, like hand mixing.
function AutoProduction.Load(player: Player, plot: Model, lineIndex: number, fill: boolean?): number
	local line = lineAt(plot, lineIndex)
	if not line or not PlotManager.IsOwner(player, plot) or not isLineActive(player, line) then
		return 0
	end
	if not working((controlFor(plot, line))) then
		notify(player, `🔧 {line.name} is broken! Repair it first (hold Q).`)
		return 0
	end
	if #line.hopper >= A.HopperCap then
		notify(player, `{line.name}'s hopper is full.`)
		return 0
	end
	local n = loadSets(player, line, if fill then A.HopperCap else 1, "best")
	local cake = Recipes.Cakes[line.recipe]
	if n == 0 then
		notify(player, `🎒 Your bag is missing ingredients for {cake.Icon} {cake.DisplayName}. Roll at the pantry!`)
	else
		notify(player, `📦 Loaded {n} {cake.DisplayName} kit{n > 1 and "s" or ""} into {line.name}`)
	end
	return n
end

function AutoProduction.SetEnabled(player: Player, plot: Model, lineIndex: number, enabled: boolean?)
	local line = lineAt(plot, lineIndex)
	local data = DataManager.Get(player)
	if not line or not data or not PlotManager.IsOwner(player, plot) then
		return
	end
	local value = if enabled == nil then data.LinesEnabled[lineIndex] == false else enabled
	data.LinesEnabled[lineIndex] = value
	notify(player, `{line.name} turned {value and "ON ▶" or "OFF ⏸"}`)
end

-- Line 1 without an Auto-Mixer: take a loaded kit back into the bag.
function AutoProduction.GrabKit(player: Player, plot: Model)
	local line = lineAt(plot, 1)
	if not line or #line.hopper <= 0 or DataManager.HasUnlock(player, "AutoMixer") then
		return false
	end
	if not Inventory.AddItems(player, line.hopper[1].Items) then
		notify(player, "🎒 Your bag is too full for a whole recipe kit!")
		return false
	end
	table.remove(line.hopper, 1)
	return true
end

function AutoProduction.TakeBatter(player: Player, plot: Model)
	local line = lineAt(plot, 1)
	if not line or #line.batter <= 0 or DataManager.HasUnlock(player, "AutoOven") then
		return false
	end
	ToolFactory.GiveCakeItem(player, "RawBatter", table.remove(line.batter, 1) :: Rarity.CakeInfo)
	return true
end

function AutoProduction.TakeCake(player: Player, plot: Model)
	local line = lineAt(plot, 1)
	if not line or #line.tray <= 0 or DataManager.HasUnlock(player, "CounterConveyor") then
		return false
	end
	ToolFactory.GiveCakeItem(player, "FinishedCake", table.remove(line.tray, 1) :: Rarity.CakeInfo)
	return true
end

-- Gremlin (Phase 8) and tests: the live line table.
function AutoProduction.GetLine(plot: Model, lineIndex: number): Line?
	return lineAt(plot, lineIndex)
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
		lines = { newLine(1, "Line 1"), newLine(2, "Line 2", "ProductionLine2"), newLine(3, "Line 3", "ProductionLine3") },
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
			addPrompt(part, "LoadPrompt", "📥 Load Hopper", Enum.KeyCode.E, function(player)
				if canUse(player, plot, part) then
					AutoProduction.Load(player, plot, index, false)
				end
			end)
			local fill = addPrompt(part, "FillPrompt", "📥 Fill Hopper", Enum.KeyCode.F, function(player)
				if canUse(player, plot, part) then
					AutoProduction.Load(player, plot, index, true)
				end
			end)
			fill.HoldDuration = 0.6
			addPrompt(part, "TogglePrompt", "⏸ Turn Off", Enum.KeyCode.T, function(player)
				if canUse(player, plot, part) then
					AutoProduction.SetEnabled(player, plot, index)
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
		addPrompt(hopper, "GrabPrompt", "Unload Kit", Enum.KeyCode.G, function(player)
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
		state.lines[i] = newLine(line.index, line.name, line.unitId)
	end
	state.storage = {}
	refreshStorage(plot, state)
end

-- Binds the owner's saved hoppers/recipes to the plot's lines.
local function onClaimed(player: Player, plot: Model)
	local state = states[plot]
	local data = DataManager.Get(player)
	if not state or not data then
		return
	end
	resetPlot(plot)
	for i, line in state.lines do
		data.Hoppers[i] = data.Hoppers[i] or {}
		line.hopper = data.Hoppers[i]
		line.recipe = data.LineRecipes[i] or "Vanilla"
	end
end

-- Test/debug summary that crosses the DebugBridge cleanly.
function AutoProduction.Describe(plot: Model): string
	local state = states[plot]
	if not state then
		return "no state"
	end
	local owner = PlotManager.GetOwner(plot)
	local parts = {}
	for _, line in state.lines do
		local on = if owner then isEnabled(owner, line) else true
		table.insert(parts, `{line.name}[{line.recipe}{on and "" or " OFF"}] hopper={#line.hopper} batter={#line.batter} baking={line.bakeRemaining and string.format("%.1f", line.bakeRemaining) or "-"} tray={#line.tray}`)
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
	PlotManager.PlotClaimed:Connect(onClaimed)
	for plot in states do
		local owner = PlotManager.GetOwner(plot)
		if owner then
			onClaimed(owner, plot)
		end
	end

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
