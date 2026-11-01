--!strict
-- Crate -> Ingredient, Mixer (3 Ingredient) -> RawBatter, Oven (timer) -> FinishedCake,
-- Display Counter: cake goes on a slot and is marked ForSale.
-- Every interaction is validated on the server: plot owner, machine unlocked,
-- player close enough, and holding the right items.
--
-- State lives in attributes so other services (CustomerAI, AnomalyManager) can read it:
--   Oven model:   OvenState = "Idle" | "Baking" | "Ready", BakeRemaining, Blocked
--   Slot part:    HasCake, ForSale, Reserved

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DataManager = require(script.Parent.DataManager)
local PlotManager = require(script.Parent.PlotManager)
local Remotes = require(script.Parent.Remotes)
local ToolFactory = require(script.Parent.ToolFactory)

local BakingPipeline = {}

local OVEN_IDS = { "Oven", "Oven2" }
local MACHINE_PART = {
	IngredientCrate = "Crate",
	Mixer = "Body",
	Oven = "Body",
	Oven2 = "Body",
	DisplayCounter = "Counter",
}

local function notify(player: Player, message: string)
	Remotes.Get("Notify"):FireClient(player, message)
end

local function getItem(plot: Model, id: string): Model?
	local items = plot:FindFirstChild("Items")
	return items and items:FindFirstChild(id) :: Model?
end

local function getPrompt(item: Model): ProximityPrompt?
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
		prompt.ObjectText = "Oven (ready!)"
	end
end

local function runBake(oven: Model)
	oven:SetAttribute("BakeRemaining", Config.BakeTime)
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
		else
			if smoke then
				smoke:Destroy()
			end
		end
	end

	local prompt = getPrompt(oven)
	if prompt then
		if blocked then
			prompt.ObjectText = "Oven (OVERHEATED)"
		else
			setOvenState(oven, oven:GetAttribute("OvenState") :: string)
			if oven:GetAttribute("OvenState") == "Idle" then
				prompt.ObjectText = "Oven"
			end
		end
	end
end

function BakingPipeline.GetOvens(plot: Model): { Model }
	local ovens = {}
	for _, id in OVEN_IDS do
		local oven = getItem(plot, id)
		if oven and oven:GetAttribute("Visible") then
			table.insert(ovens, oven)
		end
	end
	return ovens
end

-- Display slots ----------------------------------------------------------------

local function getSlots(plot: Model): { BasePart }
	local counter = getItem(plot, "DisplayCounter")
	local folder = counter and counter:FindFirstChild("Slots")
	local slots = {}
	if folder then
		for i = 1, Config.DisplaySlots do
			local slot = folder:FindFirstChild(`Slot{i}`) :: BasePart?
			if slot then
				table.insert(slots, slot)
			end
		end
	end
	return slots
end

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

local function placeCake(plot: Model, slot: BasePart)
	local cake = Instance.new("Part")
	cake.Name = slot.Name
	cake.Shape = Enum.PartType.Cylinder
	cake.Size = Vector3.new(1.5, 2.4, 2.4) -- cylinder axis is X; rotated upright below
	cake.CFrame = slot.CFrame * CFrame.new(0, 0.75, 0) * CFrame.Angles(0, 0, math.rad(90))
	cake.Color = Color3.fromRGB(150, 90, 60)
	cake.Material = Enum.Material.SmoothPlastic
	cake.Anchored = true
	cake.CanCollide = false
	cake.Parent = cakesFolder(plot)

	slot:SetAttribute("HasCake", true)
	slot:SetAttribute("ForSale", true)
	slot:SetAttribute("Reserved", false)
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

-- Removes the cake from a slot. Returns true if there was one.
function BakingPipeline.TakeCake(plot: Model, slot: BasePart): boolean
	if not slot:GetAttribute("HasCake") then
		return false
	end
	local cake = cakesFolder(plot):FindFirstChild(slot.Name)
	if cake then
		cake:Destroy()
	end
	slot:SetAttribute("HasCake", false)
	slot:SetAttribute("ForSale", false)
	slot:SetAttribute("Reserved", false)
	return true
end

-- Interactions -------------------------------------------------------------------

local handlers: { [string]: (Player, Model, Model) -> () } = {}

handlers.IngredientCrate = function(player)
	if ToolFactory.Count(player, "Ingredient") >= Config.MaxIngredientsHeld then
		notify(player, `You can only carry {Config.MaxIngredientsHeld} ingredients.`)
		return
	end
	ToolFactory.Give(player, "Ingredient")
end

handlers.Mixer = function(player)
	local need = Config.IngredientsPerBatter
	if not ToolFactory.Take(player, "Ingredient", need) then
		notify(player, `The mixer needs {need} ingredients.`)
		return
	end
	ToolFactory.Give(player, "RawBatter")
end

local function ovenHandler(player: Player, _plot: Model, oven: Model)
	if oven:GetAttribute("Blocked") then
		notify(player, "This oven is overheating! Put it out first.")
		return
	end
	local state = oven:GetAttribute("OvenState")
	if state == "Idle" then
		if not ToolFactory.Take(player, "RawBatter", 1) then
			notify(player, "You need Raw Batter from the mixer.")
			return
		end
		task.spawn(runBake, oven)
	elseif state == "Ready" then
		setOvenState(oven, "Idle")
		ToolFactory.Give(player, "FinishedCake")
	end
end
handlers.Oven = ovenHandler
handlers.Oven2 = ovenHandler

handlers.DisplayCounter = function(player, plot)
	local free: BasePart? = nil
	for _, slot in getSlots(plot) do
		if not slot:GetAttribute("HasCake") then
			free = slot
			break
		end
	end
	if not free then
		notify(player, "The display counter is full.")
		return
	end
	if not ToolFactory.Take(player, "FinishedCake", 1) then
		notify(player, "You need a finished cake from the oven.")
		return
	end
	placeCake(plot, free :: BasePart)
end

-- Single validated entry point (prompts call this; tests can too via DebugBridge).
function BakingPipeline.Interact(player: Player, plot: Model, machineId: string): boolean
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
	local part = item:FindFirstChild(MACHINE_PART[machineId]) :: BasePart?
	local prompt = getPrompt(item)
	if not part or not prompt or not isNear(player, part, prompt) then
		return false
	end
	handler(player, plot, item)
	return true
end

-- Setup ------------------------------------------------------------------------

local PROMPT_TEXT = {
	IngredientCrate = { "Take Ingredient", "Ingredient Crate" },
	Mixer = { "Mix Batter", "Mixer" },
	Oven = { "Bake Batter", "Oven" },
	Oven2 = { "Bake Batter", "Oven" },
	DisplayCounter = { "Display Cake", "Display Counter" },
}

local function setupPlot(plot: Model)
	for machineId, partName in MACHINE_PART do
		local item = getItem(plot, machineId)
		local part = item and item:FindFirstChild(partName) :: BasePart?
		if item and part then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "Prompt"
			prompt.ActionText = PROMPT_TEXT[machineId][1]
			prompt.ObjectText = PROMPT_TEXT[machineId][2]
			prompt.MaxActivationDistance = 10
			prompt.HoldDuration = 0.2
			prompt.RequiresLineOfSight = false
			prompt.Enabled = item:GetAttribute("Visible") == true
			prompt.Parent = part
			prompt.Triggered:Connect(function(player)
				BakingPipeline.Interact(player, plot, machineId)
			end)

			if machineId == "Oven" or machineId == "Oven2" then
				item:SetAttribute("IsOven", true)
				item:SetAttribute("Blocked", false)
				setOvenState(item, "Idle")
			end
		end
	end

	-- Invisible markers on top of the counter where cakes are shown.
	local counter = getItem(plot, "DisplayCounter")
	local counterPart = counter and counter:FindFirstChild("Counter") :: BasePart?
	if counter and counterPart then
		local folder = Instance.new("Folder")
		folder.Name = "Slots"
		local spacing = counterPart.Size.X / (Config.DisplaySlots + 1)
		for i = 1, Config.DisplaySlots do
			local slot = Instance.new("Part")
			slot.Name = `Slot{i}`
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
end

local function resetPlot(plot: Model)
	for _, slot in getSlots(plot) do
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
end

return BakingPipeline
