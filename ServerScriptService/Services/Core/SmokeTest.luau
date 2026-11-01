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

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local PlotLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlotLayout"))

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
	local TycoonButtons = svc("TycoonButtons")
	local Inventory = svc("Inventory")
	local BakingPipeline = svc("BakingPipeline")

	step("reset to a new player", function()
		assert(DataManager.ResetToNew(player))
		task.wait(1)
		return nil
	end)
	local plot = PlotManager.GetPlot(player) :: Model
	step("buy every upgrade", function()
		local bought = 0
		for _ = 1, 12 do
			for _, u in PlotLayout.Upgrades do
				if TycoonButtons.TryPurchase(player, plot, u.Id) then
					bought += 1
				end
			end
		end
		return `{bought} bought`
	end)
	step("roll ingredients", function()
		for _ = 1, 3 do
			assert(Inventory.Roll(player), "roll refused")
			task.wait(Config.Rolling.Cooldown + 0.1)
		end
		return Inventory.Describe(player):sub(1, 40)
	end)
	step("hand mix (Perfect)", function()
		local mixer = plot.Items:FindFirstChild("Mixer") :: Model
		local info = BakingPipeline.Mix(player, mixer, "Perfect")
		assert(info, "mix failed")
		return `{info.Type} ${info.Value}`
	end)
	step("bake and collect", function()
		local oven = plot.Items:FindFirstChild("Oven") :: Model
		near(player, oven:FindFirstChild("Body") :: BasePart)
		assert(BakingPipeline.Interact(player, plot, "Oven"), "bake refused")
		local deadline = os.clock() + 30
		while oven:GetAttribute("OvenState") ~= "Ready" and os.clock() < deadline do
			task.wait(0.5)
		end
		assert(oven:GetAttribute("OvenState") == "Ready", "never finished")
		BakingPipeline.Interact(player, plot, "Oven")
		return nil
	end)
	step("display the cake", function()
		local counter = plot.Items:FindFirstChild("DisplayCounter") :: Model
		near(player, counter:FindFirstChild("Counter") :: BasePart)
		for _, slot in BakingPipeline.GetSlots(plot) do
			BakingPipeline.TakeCake(plot, slot)
		end
		assert(BakingPipeline.Interact(player, plot, "DisplayCounter"), "display refused")
		return `{#BakingPipeline.GetSaleSlots(plot)} for sale`
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
