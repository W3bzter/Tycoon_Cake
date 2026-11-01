--!strict
-- Studio-only end-to-end smoke test. Run during a playtest (Server view):
--   game.ServerStorage.DebugBridge:Invoke("SmokeTest", "Run", game.Players:GetPlayers()[1], true)
-- Second argument: also trigger every anomaly briefly (~2 minutes). Returns a
-- report: one OK/FAIL line per step plus every error/warning logged meanwhile.
-- WARNING: resets the player's (dev) save first. Update the steps when a
-- feature's API changes.

local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local Config = require(Shared:WaitForChild("Config"))
local PlotLayout = require(Shared:WaitForChild("PlotLayout"))

local Services = script:FindFirstAncestor("Services") :: Folder

local SmokeTest = {}

local function svc(name: string): any
	return require(Services:FindFirstChild(name, true) :: ModuleScript)
end

local function near(player: Player, part: BasePart)
	local character = player.Character
	if character then
		character:PivotTo(part.CFrame * CFrame.new(0, 2, 5))
		task.wait(0.2)
	end
end

-- The placed model of a kind ("MixStation", "Oven", "Counter").
local function placedOfKind(plot: Model, kind: string): Model?
	local folder = plot:FindFirstChild("Placed")
	for _, model in (if folder then folder:GetChildren() else {}) do
		if model:GetAttribute("Kind") == kind then
			return model :: Model
		end
	end
	return nil
end

-- How many of the oven's racks are in `state` (Baking/Ovens).
local function racksIn(oven: Model, state: string): number
	local n = 0
	local folder = oven:FindFirstChild("Racks")
	for _, rack in (if folder then folder:GetChildren() else {}) do
		n += if rack:GetAttribute("State") == state then 1 else 0
	end
	return n
end

-- Places one owned `id` on the first free grid cell (scanning the plot).
local function placeAnywhere(player: Player, plot: Model, id: string): boolean
	local BuildService = svc("BuildService")
	local b = Config.Build.Bounds
	local g = Config.Build.Grid
	for gz = math.ceil(b.MinZ / g), math.floor(b.MaxZ / g) do
		for gx = math.ceil(b.MinX / g), math.floor(b.MaxX / g) do
			if BuildService.CanPlace(player, plot, id, gx, gz, 0) then
				return (BuildService.Place(player, id, gx, gz, 0))
			end
		end
	end
	return false
end

-- Buys every floor button and every catalog item (machines at their default
-- spots, decor wherever it fits), repeating until nothing more can be bought.
local function buyEverything(player: Player, plot: Model): string
	local TycoonButtons = svc("TycoonButtons")
	local BuildService = svc("BuildService")
	local BuildModels = svc("BuildModels")
	local DataManager = svc("DataManager")
	local buttons, items = 0, 0
	for _ = 1, 15 do
		task.wait() -- let deferred ItemPlaced handlers (machine setup) run, like real play
		for _, u in PlotLayout.Upgrades do
			if TycoonButtons.TryPurchase(player, plot, u.Id) then
				buttons += 1
			end
		end
		for _, entry in BuildCatalog.List do
			if entry.UpgradeOf then
				local data = DataManager.Get(player)
				for uid, record in (if data then data.Build.Placed else {}) do
					if record.Id == entry.UpgradeOf and BuildService.Buy(player, entry.Id, uid) then
						items += 1
					end
				end
			elseif BuildService.CountOwned(player, entry.Id) < math.min(entry.Max or 1, 2) and BuildService.Buy(player, entry.Id) then
				items += 1
				local gx, gz = BuildModels.Default(entry.Id)
				if not (entry.Kind ~= "Decor" and BuildService.Place(player, entry.Id, gx, gz, 0)) then
					placeAnywhere(player, plot, entry.Id)
				end
			end
		end
	end
	return `{buttons} buttons, {items} build items`
end

SmokeTest.BuyEverything = buyEverything

function SmokeTest.Run(player: Player, withAnomalies: boolean?): string
	assert(RunService:IsStudio(), "Studio only")
	local report: { string } = {}
	local logged: { string } = {}
	local logConn = LogService.MessageOut:Connect(function(message, kind)
		if kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning then
			table.insert(logged, message)
		end
	end)
	local function step(name: string, fn: () -> string?)
		local ok, result = pcall(fn)
		table.insert(report, (if ok then "OK   " else "FAIL ") .. name .. (if result then ": " .. tostring(result) else ""))
	end

	local DataManager = svc("DataManager")
	local PlotManager = svc("PlotManager")
	local Inventory = svc("Inventory")
	local BakingPipeline = svc("BakingPipeline")
	local BuildService = svc("BuildService")

	step("reset to a new player", function()
		assert(DataManager.ResetToNew(player))
		task.wait(1)
		return nil
	end)
	local plot = PlotManager.GetPlot(player) :: Model
	step("buy and place everything", function()
		return buyEverything(player, plot)
	end)
	step("placement rules", function()
		local counter = placedOfKind(plot, "Counter") :: Model
		assert(counter, "no counter placed")
		local data = DataManager.Get(player)
		local record = data.Build.Placed[counter:GetAttribute("Uid")]
		-- On top of another item / outside the plot / on the entrance path: refused.
		assert(not BuildService.CanPlace(player, plot, "PottedPlant", record.GX, record.GZ, 0), "overlap allowed")
		assert(not BuildService.CanPlace(player, plot, "PottedPlant", 40, 0, 0), "outside allowed")
		assert(not BuildService.CanPlace(player, plot, "PottedPlant", 0, 15, 0), "entrance allowed")
		return `{#plot.Placed:GetChildren()} items placed`
	end)
	step("oven racks", function()
		task.wait() -- deferred UpgradeUnlocked handlers re-set up the oven
		local oven = placedOfKind(plot, "Oven") :: Model
		assert(oven, "no oven placed")
		local racks = oven:GetAttribute("Racks")
		assert(racks == 4, `expected 4 racks, got {racks}`)
		assert(racksIn(oven, "Idle") + racksIn(oven, "Baking") + racksIn(oven, "Ready") == 4, "rack instances missing")
		return `{oven:GetAttribute("CatalogId")}: {racks} racks`
	end)
	step("roll ingredients", function()
		for _ = 1, 3 do
			assert(Inventory.Roll(player), "roll refused")
			task.wait(Config.Rolling.Cooldown + 0.1)
		end
		return Inventory.Describe(player):sub(1, 40)
	end)
	step("hand mix (Perfect)", function()
		local station = placedOfKind(plot, "MixStation") :: Model
		local info = BakingPipeline.Mix(player, station, "Perfect")
		assert(info, "mix failed")
		return `{station:GetAttribute("CatalogId")}: {info.Type} ${info.Value}`
	end)
	step("bake and collect", function()
		local oven = placedOfKind(plot, "Oven") :: Model
		near(player, oven:FindFirstChild("Body") :: BasePart)
		assert(BakingPipeline.Interact(player, plot, oven), "bake refused")
		-- Every batter goes in at once (a Big Mixer makes 2): wait for all racks.
		local loaded = racksIn(oven, "Baking")
		local deadline = os.clock() + 30
		while racksIn(oven, "Baking") > 0 and os.clock() < deadline do
			task.wait(0.5)
		end
		assert(oven:GetAttribute("OvenState") == "Ready", "never finished")
		local collected = 0
		while oven:GetAttribute("OvenState") == "Ready" and collected < 4 do
			BakingPipeline.Interact(player, plot, oven)
			collected += 1
		end
		return `{loaded} racks baked, {collected} collected`
	end)
	step("display the cake", function()
		local counter = placedOfKind(plot, "Counter") :: Model
		near(player, counter:FindFirstChild("Counter") :: BasePart)
		for _, slot in BakingPipeline.GetSlots(plot) do
			BakingPipeline.TakeCake(plot, slot)
		end
		assert(BakingPipeline.Interact(player, plot, counter), "display refused")
		return `{#BakingPipeline.GetSaleSlots(plot)} for sale`
	end)
	step("move a counter with a cake, store refused, store decor", function()
		local counter = placedOfKind(plot, "Counter") :: Model
		local uid = counter:GetAttribute("Uid") :: string
		local record = DataManager.Get(player).Build.Placed[uid]
		local moved = false
		for dz = -6, 6 do
			if BuildService.Move(player, uid, record.GX, record.GZ + dz, (record.Rot + 2) % 4) then
				moved = true
				break
			end
		end
		assert(moved, "could not move the counter anywhere nearby")
		local slot = counter.Slots:GetChildren()[1] :: BasePart
		if slot:GetAttribute("HasCake") then
			local cake = plot.Cakes:FindFirstChild(slot.Name) :: Model
			assert((cake:GetPivot().Position - slot.Position).Magnitude < 4, "cake didn't follow its counter")
			assert(not BuildService.Store(player, uid), "stored a counter with cakes on it")
		end
		local decor = nil
		for _, model in plot.Placed:GetChildren() do
			if model:GetAttribute("Kind") == "Decor" then
				decor = model
			end
		end
		assert(decor, "no decor placed")
		assert(BuildService.Store(player, decor:GetAttribute("Uid")), "store failed")
		return nil
	end)
	step("automation line", function()
		local AutoProduction = svc("AutoProduction")
		for _ = 1, 2 do
			Inventory.Roll(player)
			task.wait(Config.Rolling.Cooldown + 0.1)
		end
		AutoProduction.Load(player, plot, 1, true)
		task.wait(12)
		return AutoProduction.Describe(plot):sub(1, 90)
	end)
	step("prompt rules (working vs broken)", function()
		local Prompts = svc("Prompts")
		local Repairs = svc("Repairs")
		task.wait(0.5)
		local lines = {}
		local targets = { placedOfKind(plot, "MixStation"), placedOfKind(plot, "Oven"), plot.Items:FindFirstChild("IngredientConveyor"), plot.Items:FindFirstChild("ProductionLine2") }
		for _, item in targets do
			local model = item :: Model
			Prompts.Refresh(model)
			local working = Prompts.Visible(model)
			for _, name in working do
				assert(not name:find("Repair"), `{model.Name} shows Repair while working`)
			end
			assert(Repairs.Break(plot, model.Name, 0.25, "test"), `could not break {model.Name}`)
			local broken = Prompts.Visible(model)
			assert(#broken == 1 and broken[1]:find("RepairPrompt"), `{model.Name} broken shows {table.concat(broken, ",")}`)
			Repairs.ForceRepair(plot, model.Name)
			Prompts.Refresh(model)
			table.insert(lines, `{model.Name}: {table.concat(working, " ")}`)
		end
		return table.concat(lines, " | ")
	end)
	if withAnomalies then
		local AnomalyManager = svc("AnomalyManager")
		for name in Config.Anomalies do
			step("anomaly " .. name, function()
				while AnomalyManager.GetActive() do
					task.wait(0.5)
				end
				-- Fresh conditions: nothing broken, a cake on display.
				local data = DataManager.Get(player)
				for id in (if data then data.Broken else {}) do
					svc("Repairs").ForceRepair(plot, id)
				end
				BakingPipeline.PlaceCakeInFreeSlot(plot, { Type = "Vanilla", Value = 50, Rarity = 1, Anomaly = false, Fresh = false, Quality = "Good", Traits = {} })
				local ok, why = AnomalyManager.Trigger(name, 10)
				assert(ok, why)
				task.wait(11)
				while AnomalyManager.GetActive() do
					task.wait(0.5)
				end
				return nil
			end)
		end
	end
	step("reset again", function()
		assert(DataManager.ResetToNew(player))
		return nil
	end)

	logConn:Disconnect()
	table.insert(report, `-- {#logged} errors/warnings logged`)
	for _, message in logged do
		table.insert(report, "  " .. message:sub(1, 160))
	end
	return table.concat(report, "\n")
end

return SmokeTest
