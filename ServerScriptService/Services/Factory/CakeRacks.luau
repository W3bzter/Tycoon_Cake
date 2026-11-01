--!strict
-- Cake Racks (Shared/BuildCatalog Kind "CakeRack"): placeable shelves that hold
-- cakes the Auto-Bakers made while the counters were full (and that the delivery
-- trucks pick up). Each rack has Config.AutoBaker.RackSlots slots with the same
-- attributes as counter slots (HasCake, Reserved) but ForSale = false. Every
-- Config.AutoBaker.RestockEvery seconds one rack cake moves to a free counter slot.
-- How many racks you can place: BuildService.MaxFor (Storage › More Cake Racks).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local Services = script:FindFirstAncestor("Services") :: Folder
local BakingPipeline = require(Services.Baking.BakingPipeline)
local BuildService = require(Services.Build.BuildService)
local Display = require(Services.Baking.Display)
local PlotManager = require(Services.Core.PlotManager)

local CakeRacks = {}

local A = Config.AutoBaker

-- Placed models of one Kind on a plot.
function CakeRacks.OfKind(plot: Model, kind: string): { Model }
	local list = {}
	local folder = plot:FindFirstChild("Placed")
	for _, model in (if folder then folder:GetChildren() else {}) do
		if model:IsA("Model") and model:GetAttribute("Kind") == kind then
			table.insert(list, model)
		end
	end
	return list
end

-- Slots of every working Cake Rack on the plot.
function CakeRacks.Slots(plot: Model): { BasePart }
	local slots = {}
	for _, rack in CakeRacks.OfKind(plot, "CakeRack") do
		local folder = not rack:GetAttribute("Broken") and rack:FindFirstChild("Slots")
		for _, slot in (if folder then folder:GetChildren() else {}) do
			if slot:IsA("BasePart") then
				table.insert(slots, slot)
			end
		end
	end
	return slots
end

-- Cakes on the plot's racks right now.
function CakeRacks.Count(plot: Model): number
	local n = 0
	for _, slot in CakeRacks.Slots(plot) do
		if slot:GetAttribute("HasCake") then
			n += 1
		end
	end
	return n
end

local function buildSlots(rack: Model)
	local folder = Instance.new("Folder")
	folder.Name = "Slots"
	for i = 1, A.RackSlots do
		local spot = rack:FindFirstChild(`Spot{i}`) :: BasePart?
		if spot then
			local slot = spot:Clone()
			slot.Name = `{rack.Name}_{i}` -- unique per plot, like counter slots
			slot:SetAttribute("HasCake", false)
			slot:SetAttribute("ForSale", false)
			slot:SetAttribute("Reserved", false)
			slot.Parent = folder
		end
	end
	folder.Parent = rack
end

-- Puts a cake on a free rack slot. False when every rack is full.
function CakeRacks.Store(plot: Model, info: Rarity.CakeInfo): boolean
	for _, slot in CakeRacks.Slots(plot) do
		if not slot:GetAttribute("HasCake") then
			Display.Place(plot, slot, info)
			slot:SetAttribute("ForSale", false) -- stored, not for sale
			return true
		end
	end
	return false
end

-- Moves one rack cake onto a free counter slot.
local function restock(plot: Model)
	for _, slot in CakeRacks.Slots(plot) do
		if slot:GetAttribute("HasCake") and not slot:GetAttribute("Reserved") then
			for _, counterSlot in BakingPipeline.GetSlots(plot) do
				if not counterSlot:GetAttribute("HasCake") then
					local ok, info = Display.TakeCake(plot, slot)
					if ok and info then
						BakingPipeline.PlaceCakeInFreeSlot(plot, info)
					end
					return
				end
			end
			return
		end
	end
end

-- Cakes on a rack must leave it before it can be stored or upgraded.
local function busyReason(model: Model, action: string): string?
	if model:GetAttribute("Kind") == "CakeRack" and action ~= "move" then
		local folder = model:FindFirstChild("Slots")
		for _, slot in (if folder then folder:GetChildren() else {}) do
			if slot:GetAttribute("HasCake") then
				return "Move the cakes off this rack first (they go to your counters)."
			end
		end
	end
	return nil
end

function CakeRacks.Init()
	BuildService.OnPlaced(function(_plot, model)
		if model:GetAttribute("Kind") == "CakeRack" then
			buildSlots(model)
		end
	end)
	BuildService.ItemMoved:Connect(function(plot, model)
		if model:GetAttribute("Kind") == "CakeRack" then
			Display.Reposition(plot, model)
		end
	end)
	table.insert(BuildService.Blockers, busyReason)

	task.spawn(function()
		while true do
			task.wait(A.RestockEvery)
			for _, player in Players:GetPlayers() do
				local plot = PlotManager.GetPlot(player)
				if plot then
					local ok, err = pcall(restock, plot)
					if not ok then
						warn(`[CakeRacks] {plot.Name}: {err}`)
					end
				end
			end
		end
	end)
end

return CakeRacks
