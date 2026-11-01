--!strict
-- Delivery trucks (fixed upgrade "LoadingDock", Config.Trucks; dock model:
-- World/DockBuilders). Every Trucks.Interval seconds (x Faster Trucks), when the
-- bakery has at least MinCakes ready (Cake Racks + cakes for sale), a truck
-- comes out of a tunnel, drives past the bay, backs into it, opens its doors and
-- loads up to Capacity (+ Bigger Truck upgrades) cakes, Cake Racks first, each
-- one shown as a box sliding from the dock into the truck. It pays every cake's
-- sale price x PayMult in one go (EarnCash) and drives off into the far tunnel.
-- One truck per bakery at a time; none while the bakery is Haunted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local Services = script:FindFirstAncestor("Services") :: Folder
local Audio = require(Services.Core.Audio)
local BakingPipeline = require(Services.Baking.BakingPipeline)
local CakeRacks = require(Services.Factory.CakeRacks)
local DataManager = require(Services.Core.DataManager)
local Display = require(Services.Baking.Display)
local DockBuilders = require(Services.World.DockBuilders)
local PlotManager = require(Services.Core.PlotManager)
local PlotStats = require(Services.Core.PlotStats)
local Remotes = require(Services.Core.Remotes)
local Style = require(Services.World.Style)
local Vehicles = require(Services.Customers.Vehicles)

local DeliveryTrucks = {}

local UPGRADE = "LoadingDock"
local T = Config.Trucks

local busy: { [Model]: boolean } = {}
local nextAt: { [Model]: number } = {}

-- Cakes a truck could take now: rack slots first, then cakes for sale.
local function readySlots(plot: Model): { BasePart }
	local list = {}
	for _, slot in CakeRacks.Slots(plot) do
		if slot:GetAttribute("HasCake") and not slot:GetAttribute("Reserved") then
			table.insert(list, slot)
		end
	end
	for _, slot in BakingPipeline.GetSaleSlots(plot) do
		table.insert(list, slot)
	end
	return list
end

function DeliveryTrucks.Ready(plot: Model): number
	return #readySlots(plot)
end

-- A cake box sliding from the dock door into the truck.
local function boxSlide(from: Vector3, to: Vector3)
	local box = Style.Part({
		Name = "CakeBox",
		Size = Vector3.new(1.4, 1, 1.4),
		CFrame = CFrame.new(from),
		Color = Style.Palette.Peach,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = Vehicles.Folder(),
	})
	local tween = TweenService:Create(box, TweenInfo.new(T.LoadTime * 0.9, Enum.EasingStyle.Quad), { CFrame = CFrame.new(to) })
	tween:Play()
	tween.Completed:Once(function()
		box:Destroy()
	end)
end

-- Takes one cake off `slot`. Returns its info, or nil if it went in the meantime.
local function takeCake(plot: Model, slot: BasePart): Rarity.CakeInfo?
	if slot:GetAttribute("ForSale") then
		if not BakingPipeline.ReserveSlot(slot) then
			return nil
		end
	elseif slot:GetAttribute("Reserved") or not slot:GetAttribute("HasCake") then
		return nil
	else
		slot:SetAttribute("Reserved", true)
	end
	local ok, info = Display.TakeCake(plot, slot)
	slot:SetAttribute("Reserved", false)
	return if ok then info else nil
end

local function runTruck(plot: Model): number
	busy[plot] = true
	local owner = PlotManager.GetOwner(plot)
	local alive = function()
		return PlotManager.GetOwner(plot) == owner
	end
	local roadZ, local3 = Vehicles.Road(plot)
	local roadY, walkY = Vehicles.RoadY, Vehicles.SidewalkY
	local front = Config.Building.FrontZ
	local street = local3(0, 0, 1) - local3(0, 0, 0) -- the plot's +Z in world space
	local bayRoad = local3(T.BayX, 0, front)
	local xEnd = Config.StreetLength / 2 - 6
	local fromX = if math.random() < 0.5 then -xEnd else xEnd
	local dir = if bayRoad.X > fromX then 1 else -1 -- travel direction along the road
	local past = Vector3.new(bayRoad.X + dir * 14, roadY, roadZ)
	local mouth = local3(T.BayX, walkY, front + 7)
	local parkPos = local3(T.BayX, 0, DockBuilders.StopZ() + Vehicles.TruckLength / 2)

	local truck = Vehicles.BuildTruck()
	truck:PivotTo(CFrame.lookAt(Vector3.new(fromX, roadY, roadZ), past))
	truck.Parent = Vehicles.Folder()
	Vehicles.Drive(truck, { Vector3.new(fromX, roadY, roadZ), past }, T.Speed)
	-- Back into the bay: swing round while reversing to the mouth, then straight in.
	Vehicles.Glide(truck, CFrame.lookAt(mouth, mouth + street), T.ReverseSpeed, 1.6)
	Vehicles.Glide(truck, CFrame.lookAt(parkPos, parkPos + street), T.ReverseSpeed)

	local cakes, total = 0, 0
	if truck.Parent and alive() and owner then
		local door = truck:FindFirstChild("BackDoor") :: Model?
		if door then
			door:PivotTo(door:GetPivot() + Vector3.new(0, 4.6, 0)) -- roll the door up
		end
		local capacity = T.Capacity + PlotStats.Get(owner).TruckCapacity
		local dockDoor = local3(T.BayX, 2.6, T.DockZ + 0.6)
		local truckBack = local3(T.BayX, 3.2, DockBuilders.StopZ() + 1.5)
		for _, slot in readySlots(plot) do
			if cakes >= capacity or not alive() then
				break
			end
			local info = takeCake(plot, slot)
			if info then
				cakes += 1
				total += info.Value * PlotStats.Get(owner).SalePrice * T.PayMult
				boxSlide(dockDoor, truckBack)
				Audio.PlayAt(truck.PrimaryPart :: BasePart, Config.Sounds.Sale, 0.8 + cakes * 0.05, 0.5)
				Vehicles.Sleep(T.LoadTime, alive)
			end
		end
		if cakes > 0 and alive() then
			local pay = DataManager.EarnCash(owner, math.floor(total + 0.5))
			DataManager.AddStat(owner, "CakesSold", cakes)
			DataManager.AddStat(owner, "TotalEarned", pay)
			DataManager.AddStat(owner, "TrucksLoaded", 1)
			Vehicles.Pop(truck, `🚚 {cakes} cakes +${pay}`, Color3.fromRGB(120, 255, 120), 9)
			Remotes.Get("Notify"):FireClient(owner, `🚚 A delivery truck bought {cakes} cakes for ${pay}!`)
			total = pay
		end
		if door then
			Vehicles.Sleep(0.6, alive)
			door:PivotTo(door:GetPivot() - Vector3.new(0, 4.6, 0))
		end
		Vehicles.Sleep(0.6, alive)
	end
	-- Pull out and carry on along the road into the far tunnel.
	Vehicles.Glide(truck, CFrame.lookAt(mouth, mouth + street), T.ReverseSpeed * 1.5)
	Vehicles.Drive(truck, { mouth, Vector3.new(bayRoad.X, roadY, roadZ), Vector3.new(dir * xEnd, roadY, roadZ) }, T.Speed)
	truck:Destroy()
	busy[plot] = nil
	return cakes
end

-- Sends a truck now if none is on its way (tests). Returns the cakes it took.
function DeliveryTrucks.SendNow(plot: Model): number
	if busy[plot] then
		return 0
	end
	local ok, result = pcall(runTruck, plot)
	if not ok then
		busy[plot] = nil
		warn(`[DeliveryTrucks] {result}`)
		return 0
	end
	return result
end

function DeliveryTrucks.Init()
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, plot in (workspace:WaitForChild("Plots") :: Folder):GetChildren() do
				local owner = plot:IsA("Model") and PlotManager.GetOwner(plot)
				if owner and DataManager.HasUnlock(owner, UPGRADE) and not busy[plot] and not plot:GetAttribute("Haunted") then
					local every = T.Interval * PlotStats.Get(owner).TruckInterval
					if not nextAt[plot] then
						nextAt[plot] = now + every
					elseif now >= nextAt[plot] and DeliveryTrucks.Ready(plot :: Model) >= T.MinCakes then
						nextAt[plot] = now + every
						task.spawn(DeliveryTrucks.SendNow, plot :: Model)
					end
				elseif not owner then
					nextAt[plot] = nil
				end
			end
		end
	end)
end

return DeliveryTrucks
