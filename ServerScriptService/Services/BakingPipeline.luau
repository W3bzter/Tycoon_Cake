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

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local CakeData = require(Shared:WaitForChild("CakeData"))

local Assets = require(script.Parent.Assets)
local VFX = require(script.Parent.VFX)
local DataManager = require(script.Parent.DataManager)
local Inventory = require(script.Parent.Inventory)
local PlotManager = require(script.Parent.PlotManager)
local PlotStats = require(script.Parent.PlotStats)
local Remotes = require(script.Parent.Remotes)
local ToolFactory = require(script.Parent.ToolFactory)
local TycoonButtons = require(script.Parent.TycoonButtons)
local WorldBuilder = require(script.Parent.WorldBuilder)

local BakingPipeline = {}

-- (player, CakeInfo) after every hand mix, before auto-delete (stats/achievements).
local mixedEvent = Instance.new("BindableEvent")
BakingPipeline.Mixed = mixedEvent.Event
-- (owner, CakeInfo) after every bake (manual and automated), with traits/mutation.
local bakedEvent = Instance.new("BindableEvent")
BakingPipeline.Baked = bakedEvent.Event

local OVEN_IDS = { "BasicOven", "Oven", "Oven2", "Oven3" } -- manual ovens (automated ones live in AutoProduction)
local COUNTER_IDS = { "DisplayCounter", "DisplayCounter2" }
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

-- Bake finished (manual or automated): rolls cake traits and a mutation
-- (Shared/Rarity.RollBake), records stats and celebrates mutations.
function BakingPipeline.FinishBake(owner: Player?, oven: Model, info: Rarity.CakeInfo, overheated: boolean?): Rarity.CakeInfo
	local data = owner and DataManager.Get(owner)
	local out = Rarity.RollBake(info, {
		AnomalyActive = ReplicatedStorage:GetAttribute("ActiveAnomaly") ~= nil,
		Overheated = overheated,
		Rebirths = data and data.Rebirths or 0,
	})
	if owner then
		bakedEvent:Fire(owner, out)
		if out.Mutation then
			local m = Rarity.Mutations[out.Mutation]
			local body = oven:FindFirstChild("Body") :: BasePart?
			if body then
				VFX.Burst(body.Position, "Mutation", m.Color)
			end
			notify(owner, `{m.Icon} MUTATION! {out.Mutation} {cakeName(out.Type)} (x{m.Mult} value)`)
		end
	end
	return out
end

local function runBake(oven: Model, plot: Model)
	local duration = PlotStats.BakeDuration(PlotManager.GetOwner(plot), oven)
	if oven:GetAttribute("Fresh") then
		duration *= Rarity.FreshBakeMult -- Fresh ingredients bake faster
	end
	oven:SetAttribute("BakeRemaining", duration)
	setOvenState(oven, "Baking")
	local prompt = getPrompt(oven)
	local overheated = false
	while (oven:GetAttribute("BakeRemaining") :: number) > 0 do
		local dt = task.wait(0.25)
		if oven.Parent == nil or oven:GetAttribute("OvenState") ~= "Baking" then
			return -- plot was reset (or the oven exploded)
		end
		if not oven:GetAttribute("Blocked") and not oven:GetAttribute("Broken") then -- Overheat Crisis pauses baking
			local remaining = math.max(0, (oven:GetAttribute("BakeRemaining") :: number) - dt)
			oven:SetAttribute("BakeRemaining", remaining)
			if prompt then
				prompt.ObjectText = `Oven ({math.ceil(remaining)}s)`
			end
		else
			overheated = overheated or oven:GetAttribute("Blocked") == true
			if prompt then
				prompt.ObjectText = "Oven (OVERHEATED)"
			end
		end
	end
	local info = BakingPipeline.FinishBake(PlotManager.GetOwner(plot), oven, CakeData.Read(oven), overheated)
	CakeData.Write(oven, info)
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
		if item:IsA("Model") and item:GetAttribute("IsOven") and item:GetAttribute("Visible") and not item:GetAttribute("Broken") then
			table.insert(ovens, item)
		end
	end
	return ovens
end

BakingPipeline.SetDoorGlow = setDoorGlow

-- Empties a manual oven (an explosion or a smash loses whatever was baking).
function BakingPipeline.ResetOven(oven: Model)
	if oven:GetAttribute("IsAutoOven") then
		return
	end
	CakeData.Clear(oven)
	setOvenState(oven, "Idle")
end

-- Display slots ----------------------------------------------------------------

-- Slots on every unlocked display counter (names are unique per plot: "<Counter>_<i>").
local function getSlots(plot: Model, includeHidden: boolean?): { BasePart }
	local slots = {}
	for _, counterId in COUNTER_IDS do
		local counter = getItem(plot, counterId)
		local usable = counter and counter:GetAttribute("Visible") and not counter:GetAttribute("Broken")
		local folder = counter and (includeHidden or usable) and counter:FindFirstChild("Slots")
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

-- Rarity glow ring + always-on-top "Rare $123" label under/over a displayed cake.
local function decorateCake(model: Model, info: Rarity.CakeInfo)
	local tier = Rarity.Tiers[info.Rarity] or Rarity.Tiers[1]
	local _, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local ring = Instance.new("Part")
	ring.Name = "RarityRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, 2.6, 2.6)
	ring.CFrame = CFrame.new(pivot.Position - Vector3.new(0, size.Y / 2 - 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = tier.Color
	ring.Material = if tier.Glow > 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Parent = model
	if tier.Glow > 0 then
		local light = Instance.new("PointLight")
		light.Color = tier.Color
		light.Range = 4 + tier.Glow * 2
		light.Brightness = tier.Glow
		light.Parent = ring
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "ValueTag"
	gui.Size = UDim2.fromScale(3.6, 1)
	gui.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 0.9, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 30
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(30, 22, 18)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = tier.Color
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	local badges = Rarity.CakeBadges(info)
	label.Text = `{info.Anomaly and "👁️ " or ""}{tier.Name} ${info.Value}{if badges ~= "" then "\n" .. badges else ""}`
	if badges ~= "" then
		gui.Size = UDim2.fromScale(3.6, 1.7)
	end
	if info.Mutation and Rarity.Mutations[info.Mutation] then
		label.TextColor3 = Rarity.Mutations[info.Mutation].Color:Lerp(Color3.new(1, 1, 1), 0.2)
	end
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = tier.Color
	stroke.Thickness = 1.5
	stroke.Parent = label
	gui.Parent = model.PrimaryPart or ring
	VFX.ApplyCake(model, info)
end

local function placeCake(plot: Model, slot: BasePart, info: Rarity.CakeInfo)
	local model = Assets.Clone("Cakes", info.Type)
	model.Name = slot.Name
	model:SetAttribute("CakeType", info.Type)
	Assets.Anchor(model, slot.CFrame * CFrame.new(0, slot.Size.Y / 2, 0), cakesFolder(plot))
	decorateCake(model, info)

	CakeData.Write(slot, info)
	slot:SetAttribute("HasCake", true)
	slot:SetAttribute("ForSale", true)
	slot:SetAttribute("Reserved", false)
end

-- Puts a cake on the first free display slot (used by automation). False if full.
function BakingPipeline.PlaceCakeInFreeSlot(plot: Model, info: Rarity.CakeInfo): boolean
	for _, slot in getSlots(plot) do
		if not slot:GetAttribute("HasCake") then
			placeCake(plot, slot, info)
			return true
		end
	end
	return false
end

-- A rolled cake of `cakeType` with fixed "Good" quality (automation uses this).
function BakingPipeline.RollCake(owner: Player, cakeType: string): Rarity.CakeInfo
	local items = {}
	for _, ingredient in Recipes.Cakes[cakeType].Ingredients do
		table.insert(items, Inventory.MakeItem(owner, ingredient))
	end
	return Rarity.MakeCake(cakeType, Recipes.Cakes[cakeType].Price, items, "Good")
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

-- Removes the cake from a slot. Returns true and its info if there was one.
function BakingPipeline.TakeCake(plot: Model, slot: BasePart): (boolean, Rarity.CakeInfo?)
	if not slot:GetAttribute("HasCake") then
		return false, nil
	end
	local info = CakeData.Read(slot)
	local cake = cakesFolder(plot):FindFirstChild(slot.Name)
	if cake then
		cake:Destroy()
	end
	CakeData.Clear(slot)
	slot:SetAttribute("HasCake", false)
	slot:SetAttribute("ForSale", false)
	slot:SetAttribute("Reserved", false)
	return true, info
end

-- Changes a displayed cake in place (Phantom curses, Rats nibble). Skips slots a
-- customer has already claimed. Returns the new info, or nil.
function BakingPipeline.ModifyCake(plot: Model, slot: BasePart, change: (Rarity.CakeInfo) -> Rarity.CakeInfo): Rarity.CakeInfo?
	if not slot:GetAttribute("HasCake") or slot:GetAttribute("Reserved") then
		return nil
	end
	local ok, info = BakingPipeline.TakeCake(plot, slot)
	if not ok or not info then
		return nil
	end
	local updated = change(info)
	placeCake(plot, slot, updated)
	return updated
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

-- Roll spectacle: Rare+ ingredients pop out of the pantry (everyone sees it);
-- Mythic+ also fire a pillar of light and a server-wide announcement.
local function showPantryRoll(player: Player, items: { any })
	local plot = PlotManager.GetPlot(player)
	local pantry = plot and getItem(plot, "IngredientCrate")
	local crate = pantry and pantry:FindFirstChild("Crate") :: BasePart?
	if not plot or not crate then
		return
	end
	local shown = {}
	for _, item in items do
		if item.Rarity >= 3 and not item.Deleted then
			table.insert(shown, item)
		end
	end
	for i, item in shown do
		local model = Assets.Clone("Ingredients", item.Type)
		model:ScaleTo(model:GetScale() * (1 + item.Rarity * 0.12))
		local offset = (i - (#shown + 1) / 2) * 2.6
		local cf = crate.CFrame * CFrame.new(offset, crate.Size.Y / 2 + 3, 0)
		Assets.Anchor(model, CFrame.new(cf.Position), plot)
		VFX.ApplyIngredient(model, item)
		CollectionService:AddTag(model, "FxBob") -- the client floats and spins it
		Debris:AddItem(model, 2.8)
		local tier = Rarity.Tiers[item.Rarity]
		if item.Rarity >= Rarity.MYTHIC then
			VFX.Pillar(cf.Position, tier.Color, 4)
			VFX.Burst(cf.Position, "Rebirth", tier.Color)
			local info = Recipes.Ingredients[item.Type]
			for _, other in Players:GetPlayers() do
				notify(other, `⭐ {player.DisplayName} rolled {string.upper(tier.Name)} {info and info.Icon or ""} {item.Type}!`)
			end
		end
	end
end

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
		task.spawn(runBake, oven, plot)
	elseif state == "Ready" then
		local info = CakeData.Read(oven)
		setOvenState(oven, "Idle")
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
	local info = ToolFactory.GetCakeInfo(cake)
	cake:Destroy()
	placeCake(plot, free :: BasePart, info)
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
				setOvenState(item, "Idle")
			end
		end
	end

	-- (Pantry bins are decorative stock now; the single roll prompt is on the cabinet.)

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
	Inventory.Rolled:Connect(showPantryRoll)

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
