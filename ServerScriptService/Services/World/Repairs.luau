--!strict
-- Broken machines. Ovens explode after an unchecked Overheat Crisis and anomalies
-- (Brute, ...) smash machines. A broken machine can't be used until its owner
-- holds the Repair prompt and pays a share of its upgrade price (Config.Repair).
--
-- The model gets the attribute Broken = true (BakingPipeline, AutoProduction and
-- AnomalyManager all check it) plus visuals: darkened, smoking, sparking and a
-- "🔧 BROKEN" label. Breaks are saved (PlayerData.Broken: id -> cost) and
-- re-applied when the owner claims a plot, so leaving doesn't skip a repair.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local PlotLayout = require(Shared:WaitForChild("PlotLayout"))

local Services = script:FindFirstAncestor("Services") :: Folder
local BakingPipeline = require(Services.Baking.BakingPipeline)
local BuildService = require(Services.Build.BuildService)
local DataManager = require(Services.Core.DataManager)
local PlotManager = require(Services.Core.PlotManager)
local Prompts = require(Services.Core.Prompts)
local Remotes = require(Services.Core.Remotes)
local Style = require(Services.World.Style)
local VFX = require(Services.Effects.VFX)

local Repairs = {}

-- Machines that can break (the pantry never does: rolling must always work):
-- these fixed automation machines, plus every placed machine (Build mode Kind
-- MixStation, Oven or Counter). Decor never breaks.
Repairs.Breakable = {
	"IngredientConveyor", "AutoMixer", "AutoOven", "CounterConveyor", "AutoRestock", "ProductionLine2", "ProductionLine3",
}
local BREAKABLE_KINDS = { MixStation = true, Oven = true, Counter = true }
local MAIN_PARTS = { "Body", "Counter", "Hopper", "Panel", "Rack" }

local repairedEvent = Instance.new("BindableEvent")
Repairs.Repaired = repairedEvent.Event -- (player, itemId)
local brokenEvent = Instance.new("BindableEvent")
Repairs.Broke = brokenEvent.Event -- (owner, itemId, reason)

local function notify(player: Player, message: string)
	Remotes.Get("Notify"):FireClient(player, message)
end

-- A fixed item (plot.Items) or placed item (plot.Placed) by model name.
local function getItem(plot: Model, name: string): Model?
	for _, folderName in { "Items", "Placed" } do
		local folder = plot:FindFirstChild(folderName)
		local item = folder and folder:FindFirstChild(name)
		if item and item:IsA("Model") then
			return item
		end
	end
	-- Or a placed item by catalog id ("Oven"), for tests and callers that only know the id.
	local placed = plot:FindFirstChild("Placed")
	for _, item in (if placed then placed:GetChildren() else {}) do
		if item:IsA("Model") and item:GetAttribute("CatalogId") == name then
			return item
		end
	end
	return nil
end

local function isBreakable(item: Model): boolean
	return BREAKABLE_KINDS[item:GetAttribute("Kind") :: string] == true or table.find(Repairs.Breakable, item.Name) ~= nil
end

-- Every breakable machine on the plot (fixed and placed).
local function machines(plot: Model): { Model }
	local list = {}
	for _, folderName in { "Items", "Placed" } do
		local folder = plot:FindFirstChild(folderName)
		for _, item in (if folder then folder:GetChildren() else {}) do
			if item:IsA("Model") and isBreakable(item) then
				table.insert(list, item)
			end
		end
	end
	return list
end

function Repairs.MainPart(item: Model): BasePart?
	for _, name in MAIN_PARTS do
		local part = item:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)
end

-- Repair cost: `fraction` of the item's price (catalog price for placed items).
function Repairs.Cost(item: Model, fraction: number): number
	local catalogId = item:GetAttribute("CatalogId") :: string?
	local upgrade: any = if catalogId then BuildCatalog.Find(catalogId) else PlotLayout.Find(item.Name)
	local price = upgrade and upgrade.Price or 100
	if upgrade and upgrade.Currency == "Gems" then
		price *= 100 -- gem items are repaired with Cash too
	end
	return math.max(1, math.floor(price * fraction + 0.5))
end

-- Visuals ---------------------------------------------------------------------------------

-- The machine's own sign turns red while broken (no extra label, so labels never
-- pile up on screen). Machines without a sign get a BrokenSign in the same spot.
local function setSignBroken(item: Model, main: BasePart, cost: number?)
	local sign = item:FindFirstChild("MachineSign", true) :: BillboardGui?
	local frame = sign and sign:FindFirstChildOfClass("Frame")
	local text = frame and frame:FindFirstChild("Line1") :: TextLabel?
	if sign and frame and text then
		if cost then
			if sign:GetAttribute("NormalText") == nil then
				sign:SetAttribute("NormalText", text.Text)
				sign:SetAttribute("NormalBackground", frame.BackgroundColor3)
				sign:SetAttribute("NormalTextColor", text.TextColor3)
			end
			text.Text = `🔧 BROKEN  ${cost}`
			frame.BackgroundColor3 = Color3.fromRGB(150, 25, 35)
			text.TextColor3 = Color3.new(1, 1, 1)
		elseif sign:GetAttribute("NormalText") ~= nil then
			text.Text = sign:GetAttribute("NormalText") :: string
			frame.BackgroundColor3 = sign:GetAttribute("NormalBackground") :: Color3
			text.TextColor3 = sign:GetAttribute("NormalTextColor") :: Color3
			sign:SetAttribute("NormalText", nil)
		end
		return
	end
	local old = main:FindFirstChild("BrokenSign")
	if old then
		old:Destroy()
	end
	if cost then
		Style.Billboard(main, { `🔧 BROKEN  ${cost}` }, {
			Name = "BrokenSign",
			Width = 6,
			Height = 1.4,
			Offset = Vector3.new(0, main.Size.Y / 2 + 4, 0),
			Background = Color3.fromRGB(150, 25, 35),
			Stroke = Color3.fromRGB(255, 200, 80),
			TextColor = Color3.new(1, 1, 1),
			MaxDistance = 35,
		})
	end
end

local function setBrokenLook(item: Model, cost: number?)
	local main = Repairs.MainPart(item)
	for _, d in item:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			if cost then
				if d:GetAttribute("PreBreakColor") == nil then
					d:SetAttribute("PreBreakColor", d.Color)
				end
				d.Color = (d:GetAttribute("PreBreakColor") :: Color3):Lerp(Color3.fromRGB(35, 30, 30), 0.55)
			elseif d:GetAttribute("PreBreakColor") ~= nil then
				d.Color = d:GetAttribute("PreBreakColor") :: Color3
				d:SetAttribute("PreBreakColor", nil)
			end
		end
	end
	if not main then
		return
	end
	for _, name in { "BrokenSmoke", "BrokenSparks" } do
		local old = main:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	setSignBroken(item, main, cost)
	local prompt = Prompts.Get(item, "RepairPrompt")
	if not cost then
		Prompts.Refresh(item)
		return
	end
	local smoke = Instance.new("Smoke")
	smoke.Name = "BrokenSmoke"
	smoke.Color = Color3.fromRGB(50, 50, 50)
	smoke.Opacity = 0.35
	smoke.RiseVelocity = 4
	smoke.Size = 3
	smoke.Parent = main
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "BrokenSparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 190, 80))
	sparks.LightEmission = 1
	sparks.Rate = 6
	sparks.Lifetime = NumberRange.new(0.2, 0.5)
	sparks.Speed = NumberRange.new(5, 9)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Acceleration = Vector3.new(0, -20, 0)
	sparks.Size = NumberSequence.new(0.2, 0)
	sparks.Parent = main
	if prompt then
		local upgrade = PlotLayout.Find(item.Name)
		prompt.ObjectText = `Broken {if upgrade then upgrade.DisplayName else item.Name}`
		prompt.ActionText = `🔧 Repair (${cost})`
	end
	Prompts.Refresh(item) -- shows only Repair now (Broken is set before this runs)
end

-- Break / repair ----------------------------------------------------------------------------

function Repairs.IsBroken(item: Model?): boolean
	return item ~= nil and item:GetAttribute("Broken") == true
end

-- Breaks a visible machine on `plot`. `fraction` of its price is the repair cost.
function Repairs.Break(plot: Model, itemId: string, fraction: number, reason: string?): boolean
	local owner = PlotManager.GetOwner(plot)
	local item = getItem(plot, itemId)
	local data = owner and DataManager.Get(owner)
	if not owner or not data or not item or not isBreakable(item) then
		return false
	end
	if item:GetAttribute("Visible") ~= true or Repairs.IsBroken(item) then
		return false
	end
	local cost = Repairs.Cost(item, fraction)
	data.Broken[item.Name] = cost
	item:SetAttribute("Broken", true)
	item:SetAttribute("RepairCost", cost)
	-- Whatever was in or on it is lost.
	if item:GetAttribute("IsOven") and not item:GetAttribute("IsAutoOven") then
		BakingPipeline.ResetOven(item)
	end
	if item:GetAttribute("Kind") == "Counter" then
		for _, slot in BakingPipeline.GetSlots(plot, true) do
			if slot:IsDescendantOf(item) and not slot:GetAttribute("Reserved") then
				BakingPipeline.TakeCake(plot, slot)
			end
		end
	end
	setBrokenLook(item, cost)
	brokenEvent:Fire(owner, itemId, reason or "Broken")
	return true
end

local function clear(item: Model)
	item:SetAttribute("Broken", nil)
	item:SetAttribute("RepairCost", nil)
	setBrokenLook(item, nil)
end

function Repairs.Repair(player: Player, plot: Model, itemId: string): (boolean, string?)
	local item = getItem(plot, itemId)
	local data = DataManager.Get(player)
	if not item or not data or not PlotManager.IsOwner(player, plot) or not Repairs.IsBroken(item) then
		return false, "not broken"
	end
	local main = Repairs.MainPart(item)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not main or not root or (root.Position - main.Position).Magnitude > 14 + Config.InteractSlack then
		return false, "too far"
	end
	local cost = data.Broken[item.Name] or (item:GetAttribute("RepairCost") :: number?) or Repairs.Cost(item, Config.Repair.DamageFraction)
	if not DataManager.SpendCash(player, cost) then
		notify(player, `You need ${cost} to repair this.`)
		return false, "insufficient cash"
	end
	data.Broken[item.Name] = nil
	clear(item)
	VFX.Burst(main.Position, "Repair")
	notify(player, `🔧 Repaired for ${cost}!`)
	repairedEvent:Fire(player, itemId)
	return true
end

-- Studio/test helper: repair without paying.
function Repairs.ForceRepair(plot: Model, itemId: string)
	local owner = PlotManager.GetOwner(plot)
	local data = owner and DataManager.Get(owner)
	local item = getItem(plot, itemId)
	if data then
		data.Broken[if item then item.Name else itemId] = nil
	end
	if item then
		clear(item)
	end
end

-- Working (visible and not broken) breakable machines on a plot.
function Repairs.WorkingMachines(plot: Model): { Model }
	local result = {}
	for _, item in machines(plot) do
		if item:GetAttribute("Visible") == true and not Repairs.IsBroken(item) then
			table.insert(result, item)
		end
	end
	return result
end

-- Setup --------------------------------------------------------------------------------------

local function addRepairPrompt(plot: Model, item: Model)
	local main = Repairs.MainPart(item)
	if not main or Prompts.Get(item, "RepairPrompt") then
		return
	end
	Prompts.Add(item, main, {
		Name = "RepairPrompt",
		Action = "🔧 Repair",
		Key = Config.Prompts.Keys.Repair,
		Hold = Config.Prompts.RepairHold,
		Distance = 12,
		Repair = true,
		Trigger = function(player)
			Repairs.Repair(player, plot, item.Name)
		end,
	})
end

local function resetPlot(plot: Model)
	for _, item in machines(plot) do
		if Repairs.IsBroken(item) then
			clear(item)
		end
	end
end

local function applyBreak(item: Model, cost: number)
	item:SetAttribute("Broken", true)
	item:SetAttribute("RepairCost", cost)
	setBrokenLook(item, cost)
end

-- Saved breaks of fixed machines come back when the owner claims a plot;
-- placed machines get theirs when they're placed (see Init).
local function applySaved(player: Player, plot: Model)
	local data = DataManager.Get(player)
	if not data then
		return
	end
	for name, cost in data.Broken do
		local placedName = string.match(name, "_%d+$") ~= nil
		local item = getItem(plot, name)
		if item and item:GetAttribute("Visible") == true then
			applyBreak(item, cost)
		elseif not placedName then
			data.Broken[name] = nil -- no longer owned/shown
		end
	end
end

function Repairs.Init()
	for _, plot in (workspace:WaitForChild("Plots") :: Folder):GetChildren() do
		if plot:IsA("Model") then
			for _, item in machines(plot) do
				addRepairPrompt(plot, item)
			end
		end
	end
	BuildService.OnPlaced(function(plot, model)
		if not isBreakable(model) then
			return
		end
		addRepairPrompt(plot, model)
		local owner = PlotManager.GetOwner(plot)
		local data = owner and DataManager.Get(owner)
		local cost = data and data.Broken[model.Name]
		if cost then
			applyBreak(model, cost)
		end
	end)
	BuildService.ItemRemoved:Connect(function(plot, model)
		local owner = PlotManager.GetOwner(plot)
		local data = owner and DataManager.Get(owner)
		if data and not model:GetAttribute("Broken") then
			data.Broken[model.Name] = nil
		end
	end)
	PlotManager.PlotReleased:Connect(resetPlot)
	PlotManager.PlotClaimed:Connect(function(player, plot)
		task.defer(applySaved, player, plot)
	end)
	for _, player in Players:GetPlayers() do
		local plot = PlotManager.GetPlot(player)
		if plot then
			task.defer(applySaved, player, plot)
		end
	end
end

return Repairs
