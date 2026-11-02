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
local Rarity = require(Shared:WaitForChild("Rarity"))
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
	step("starter furniture", function()
		local data = DataManager.Get(player)
		assert(data.Build.StarterGiven, "starter not given")
		local placed, stored = #plot.Placed:GetChildren(), 0
		for _, n in data.Build.Owned do
			stored += n
		end
		assert(placed + stored == #Config.Build.Starter, `{placed} placed + {stored} stored, expected {#Config.Build.Starter}`)
		return `{placed} placed, {stored} in inventory`
	end)
	step("buy and place everything", function()
		return buyEverything(player, plot)
	end)
	step("pause auto-bakers (they'd eat the bag the hand tests use)", function()
		local data = DataManager.Get(player)
		local n = 0
		for _, record in data.Build.Placed do
			if string.find(record.Id, "Baker$") then
				record.Off = true
				n += 1
			end
		end
		return `{n} paused`
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
	step("auto-roll", function()
		local data = DataManager.Get(player)
		local before = #data.Bag
		data.Settings.AutoRoll = nil -- on
		task.wait(Config.Rolling.Cooldown * 2 + 0.6)
		local after = #data.Bag
		data.Settings.AutoRoll = false -- off, so the manual roll checks below get the cooldown
		assert(after > before or not Inventory.RollFits(player), "auto-roll didn't roll")
		task.wait(Config.Rolling.Cooldown + 0.1)
		return `+{after - before} ingredients`
	end)
	step("roll ingredients", function()
		local bagData = DataManager.Get(player)
		table.clear(bagData.Bag) -- the auto-roll step filled it; start empty so 3 rolls fit
		Inventory.Sync(player)
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
		task.wait() -- ItemMoved handlers are deferred (they run at the end of the frame)
		local slot = counter.Slots:GetChildren()[1] :: BasePart
		if slot:GetAttribute("HasCake") then
			local cake = plot.Cakes:FindFirstChild(slot.Name) :: Model
			local gap = (cake:GetPivot().Position - slot.Position).Magnitude
			assert(gap < 4, `cake didn't follow its counter: {slot.Name} gap {math.floor(gap)} offset {cake:GetAttribute("SlotOffset")}`)
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
	step("auto-baker bakes a cake", function()
		local AutoBakers = svc("AutoBakers")
		local baker = placedOfKind(plot, "AutoBaker")
		assert(baker, "no Auto-Baker placed")
		local data = DataManager.Get(player)
		local record = data.Build.Placed[baker:GetAttribute("Uid")]
		record.Recipe, record.Off = "Vanilla", nil
		baker:SetAttribute("JammedUntil", nil)
		local before = data.Stats.CakesBaked or 0
		for _ = 1, 2 do
			Inventory.Roll(player)
			task.wait(Config.Rolling.Cooldown + 0.1)
		end
		local deadline = os.clock() + Config.AutoBaker.CycleSeconds.AutoBaker + 4
		while os.clock() < deadline and (data.Stats.CakesBaked or 0) <= before do
			task.wait(0.5)
		end
		assert((data.Stats.CakesBaked or 0) > before, "no cake baked: " .. AutoBakers.Describe(plot))
		return AutoBakers.Describe(plot):sub(1, 90)
	end)
	step("delivery truck loads and pays", function()
		local CakeRacks = svc("CakeRacks")
		local DeliveryTrucks = svc("DeliveryTrucks")
		assert(DataManager.HasUnlock(player, "LoadingDock"), "Loading Dock not bought")
		for _ = 1, 3 do
			CakeRacks.Store(plot, Rarity.MakeCake("Vanilla", 10, {}, "Good"))
		end
		local ready = DeliveryTrucks.Ready(plot)
		assert(ready >= 3, `only {ready} cakes ready`)
		local data = DataManager.Get(player)
		local cash = data.Cash
		local t0 = os.clock()
		local took = DeliveryTrucks.SendNow(plot)
		assert(took > 0, "truck took no cakes")
		assert(data.Cash > cash, "truck didn't pay")
		return `{took} cakes, +${data.Cash - cash} in {math.floor(os.clock() - t0)}s`
	end)
	step("prompt rules (working vs broken)", function()
		local Prompts = svc("Prompts")
		local Repairs = svc("Repairs")
		task.wait(0.5)
		local lines = {}
		local targets = { placedOfKind(plot, "MixStation"), placedOfKind(plot, "Oven"), placedOfKind(plot, "AutoBaker") }
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
	step("migrate an old automation save", function()
		local data = DataManager.Get(player) :: any
		for _, id in { "FactoryAnnex", "IngredientConveyor", "ProductionLine2", "AutoRestock" } do
			data.UnlockedUpgrades[id] = true
		end
		data.Hoppers = { { { Id = "smoke-hopper", Type = "Flour", Rarity = 1 } } }
		data.Build.MigratedAutoBakers = false
		local cash, bag, bakers = data.Cash, #data.Bag, data.Build.Owned.AutoBaker or 0
		BuildService.Migrate(player, plot)
		assert(data.Cash - cash == 172000, `refund {data.Cash - cash}`)
		assert((data.Build.Owned.AutoBaker or 0) - bakers == 2, "free Auto-Bakers not given")
		assert((data.Build.Owned.CakeRack or 0) >= 1, "free Cake Rack not given")
		assert(#data.Bag == bag + 1 and data.Hoppers == nil, "hopper items not returned")
		assert(not data.UnlockedUpgrades.FactoryAnnex, "old unlock kept")
		return "refund $172000, 2 bakers, rack, 1 ingredient back"
	end)
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
