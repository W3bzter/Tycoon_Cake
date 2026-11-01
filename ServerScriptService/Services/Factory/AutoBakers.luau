--!strict
-- Auto-Bakers: placeable machines that bake by themselves (Shared/BuildCatalog
-- Kind "AutoBaker": Auto-Baker -> Turbo Baker -> Golden Baker upgrade in place).
-- Each one, while on, takes one recipe's ingredients from the owner's bag
-- (cheapest, never pinned), bakes for Config.AutoBaker.CycleSeconds[id] and makes
-- a "Good" cake that goes through Ovens.FinishBake (traits, mutations, stats).
-- The cake goes on a free display slot, else on a Cake Rack (Kind "CakeRack"),
-- else the machine waits ("Full"). (Racks: Factory/CakeRacks.)
-- Prompts: R = recipe, T = on/off (a broken machine shows only Repair).
-- Recipe / on-off are saved on the placed record (PlayerData.Build.Placed[uid]).
-- Full Automation pass: when the bag can't make a baker's recipe, it rolls for you
-- (normal cooldown and odds).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Services = script:FindFirstAncestor("Services") :: Folder
local BakingPipeline = require(Services.Baking.BakingPipeline)
local BuildService = require(Services.Build.BuildService)
local DataManager = require(Services.Core.DataManager)
local GamePasses = require(Services.Core.GamePasses)
local Inventory = require(Services.Baking.Inventory)
local PlotManager = require(Services.Core.PlotManager)
local Prompts = require(Services.Core.Prompts)
local Remotes = require(Services.Core.Remotes)

local CakeRacks = require(Services.Factory.CakeRacks)
local AutoBakers = {}

local A = Config.AutoBaker

type Job = { recipe: string, items: { Rarity.Item }, left: number }
local jobs: { [Model]: Job } = {} -- machine -> the cake it is baking
local status: { [Model]: string } = {}

local function notify(player: Player, message: string)
	Remotes.Get("Notify"):FireClient(player, message)
end

local function plotOf(model: Model): Model?
	local plots = workspace:FindFirstChild("Plots")
	local node: Instance? = model
	while node and node.Parent ~= plots do
		node = node.Parent
	end
	return node :: Model?
end

local function recordOf(owner: Player, model: Model): any
	local data = DataManager.Get(owner)
	return data and data.Build.Placed[model:GetAttribute("Uid") :: string]
end

local ofKind = CakeRacks.OfKind

-- Machines ---------------------------------------------------------------------------

local function setSign(model: Model, text: string)
	if status[model] == text then
		return
	end
	status[model] = text
	local sign = model:FindFirstChild("MachineSign", true)
	local line = sign and sign:FindFirstChild("Line1", true) :: TextLabel?
	if line then
		line.Text = text
	end
end

local function setWorking(model: Model, on: boolean)
	local door = model:FindFirstChild("Door") :: BasePart?
	if door then
		door.Material = if on then Enum.Material.Neon else Enum.Material.Glass
		door.Color = if on then Color3.fromRGB(255, 150, 60) else Color3.fromRGB(60, 40, 40)
	end
	local whisk = model:FindFirstChild("Whisk")
	if whisk then
		if on then
			CollectionService:AddTag(whisk, "FxSpin") -- spun by the client (UI/Effects/WorldFX)
		else
			CollectionService:RemoveTag(whisk, "FxSpin")
		end
	end
	local steam = model:FindFirstChild("Steam", true)
	if steam and steam:IsA("ParticleEmitter") then
		steam.Enabled = on
	end
end

local function finish(owner: Player, plot: Model, model: Model, job: Job): boolean
	local cake = Recipes.Cakes[job.recipe] or Recipes.Cakes.Vanilla
	local info = Rarity.MakeCake(job.recipe, cake.Price, job.items, A.Quality)
	info = BakingPipeline.FinishBake(owner, model, info, false)
	if Inventory.ShouldDelete(owner, "Cake", info.Rarity, Rarity.IsSpecial(info)) then
		return true
	end
	return BakingPipeline.PlaceCakeInFreeSlot(plot, info) or CakeRacks.Store(plot, info)
end

local function tickMachine(owner: Player, plot: Model, model: Model, dt: number)
	local record = recordOf(owner, model)
	if not record then
		return
	end
	local id = model:GetAttribute("CatalogId") :: string
	local recipe = record.Recipe or "Vanilla"
	if not Recipes.IsUnlocked(recipe, function(u)
		return DataManager.HasUnlock(owner, u)
	end) then
		recipe = "Vanilla"
		record.Recipe = nil
	end
	local cake = Recipes.Cakes[recipe]
	if model:GetAttribute("Broken") then
		setWorking(model, false)
		return
	end
	if record.Off then
		setWorking(model, false)
		setSign(model, `⏸ OFF · {cake.Icon} {cake.DisplayName}`)
		return
	end
	if ((model:GetAttribute("JammedUntil") :: number?) or 0) > os.clock() then
		setWorking(model, false)
		setSign(model, "🔧 Jammed!")
		return
	end
	local job = jobs[model]
	if not job then
		local cakeType, items = Inventory.TakeForRecipe(owner, recipe, "cheapest")
		if not cakeType or not items then
			setWorking(model, false)
			setSign(model, `🎒 Needs {cake.Icon} ingredients`)
			if GamePasses.Active(owner, "FullAutomation") and Inventory.RollFits(owner) then
				Inventory.Roll(owner, true) -- normal cooldown and odds
			end
			return
		end
		job = { recipe = cakeType, items = items, left = A.CycleSeconds[id] or A.CycleSeconds.AutoBaker }
		jobs[model] = job
	end
	if job.left > 0 then
		job.left -= dt
		setWorking(model, true)
		setSign(model, `{cake.Icon} {cake.DisplayName} · {math.max(0, math.ceil(job.left))}s`)
		return
	end
	-- Done: needs somewhere to put the cake.
	if finish(owner, plot, model, job) then
		jobs[model] = nil
	else
		setWorking(model, false)
		setSign(model, "📦 Full: sell cakes or add a Cake Rack")
	end
end

local function canUse(player: Player, plot: Model, part: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return PlotManager.IsOwner(player, plot) and root ~= nil and (root.Position - part.Position).Magnitude <= Config.Prompts.Distance + Config.InteractSlack
end

-- R: next unlocked recipe. Ingredients already taken finish their own cake.
function AutoBakers.CycleRecipe(player: Player, model: Model)
	local record = recordOf(player, model)
	if not record then
		return
	end
	local menu = Recipes.Unlocked(function(u)
		return DataManager.HasUnlock(player, u)
	end)
	local i = table.find(menu, record.Recipe or "Vanilla") or 0
	record.Recipe = menu[(i % #menu) + 1]
	local cake = Recipes.Cakes[record.Recipe]
	notify(player, `🤖 Now baking {cake.Icon} {cake.DisplayName}`)
end

-- T: on/off (`on` forces a state; the Gremlin switches machines off).
function AutoBakers.SetOn(player: Player, model: Model, on: boolean?)
	local record = recordOf(player, model)
	if record then
		local value = if on == nil then record.Off == true else on
		record.Off = if value then nil else true
	end
end

local function setupMachine(plot: Model, model: Model)
	if model:GetAttribute("Kind") ~= "AutoBaker" then
		return
	end
	local body = model:FindFirstChild("Body") :: BasePart?
	if not body then
		return
	end
	local K = Config.Prompts.Keys
	Prompts.Add(model, body, {
		Name = "RecipePrompt",
		Action = "Change Recipe",
		Object = "Auto-Baker",
		Key = K.Recipe,
		Order = 1,
		Trigger = function(player)
			if canUse(player, plot, body) then
				AutoBakers.CycleRecipe(player, model)
			end
		end,
	})
	local toggle = Prompts.Add(model, body, {
		Name = "TogglePrompt",
		Action = "⏸ Turn Off",
		Object = "Auto-Baker",
		Key = K.Toggle,
		Order = 2,
		Trigger = function(player)
			if canUse(player, plot, body) then
				AutoBakers.SetOn(player, model)
			end
		end,
	})
	task.spawn(function()
		while model.Parent do -- keep the toggle's text in step with the state
			local owner = PlotManager.GetOwner(plot)
			local record = owner and recordOf(owner, model)
			toggle.ActionText = if record and record.Off then "▶ Turn On" else "⏸ Turn Off"
			task.wait(0.5)
		end
	end)
end

local function onRemoved(plot: Model, model: Model)
	local job = jobs[model]
	jobs[model] = nil
	status[model] = nil
	local owner = PlotManager.GetOwner(plot)
	if job and owner then
		Inventory.AddItems(owner, job.items) -- unfinished batch back to the bag (if it fits)
	end
end

-- Test/debug summary.
function AutoBakers.Describe(plot: Model): string
	local parts = {}
	for _, model in ofKind(plot, "AutoBaker") do
		table.insert(parts, `{model.Name}: {status[model] or "-"}`)
	end
	table.insert(parts, `rack {CakeRacks.Count(plot)}/{#CakeRacks.Slots(plot)}`)
	return table.concat(parts, " | ")
end

function AutoBakers.Init()
	BuildService.OnPlaced(setupMachine)
	BuildService.ItemRemoved:Connect(onRemoved)

	task.spawn(function()
		while true do
			task.wait(A.Tick)
			for _, player in Players:GetPlayers() do
				local plot = PlotManager.GetPlot(player)
				if plot and DataManager.IsLoaded(player) then
					local ok, err = pcall(function()
						local bakers = ofKind(plot, "AutoBaker")
						for _, model in bakers do
							tickMachine(player, plot, model, A.Tick)
						end
						DataManager.MaxStat(player, "AutoBakersOwned", #bakers)
					end)
					if not ok then
						warn(`[AutoBakers] {plot.Name}: {err}`)
					end
				end
			end
		end
	end)
end

return AutoBakers
