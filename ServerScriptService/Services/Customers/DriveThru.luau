--!strict
-- Drive-thru cars (fixed upgrade "DriveThru", lane built by ItemBuilders.DriveThru).
-- Every Config.DriveThru.Interval seconds (sped up by the customer-rate upgrades),
-- if the bakery has a cake for sale, a car comes out of a tunnel, drives along
-- the road, turns into the lane, stops at the kiosk, buys a cake (reserved like a
-- walking customer's, so they never fight over one), pays PayMult x the price,
-- turns round on the pad and drives off into the other tunnel. One car per bakery
-- at a time. Car model and movement: Customers/Vehicles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local Audio = require(Services.Core.Audio)
local BakingPipeline = require(Services.Baking.BakingPipeline)
local DataManager = require(Services.Core.DataManager)
local PlotManager = require(Services.Core.PlotManager)
local PlotStats = require(Services.Core.PlotStats)
local Vehicles = require(Services.Customers.Vehicles)

local DriveThru = {}

local UPGRADE = "DriveThru"

local busy: { [Model]: boolean } = {}
local nextAt: { [Model]: number } = {}

-- Buys one cake at the window. Returns what was paid (nil = nothing for sale).
local function buy(plot: Model, car: Model): number?
	local slots = BakingPipeline.GetSaleSlots(plot)
	local owner = PlotManager.GetOwner(plot)
	if #slots == 0 or not owner then
		return nil
	end
	local slot = slots[math.random(#slots)]
	if not BakingPipeline.ReserveSlot(slot) then
		return nil
	end
	local ok, info = BakingPipeline.TakeCake(plot, slot)
	if not ok or not info then
		BakingPipeline.ReleaseSlot(slot)
		return nil
	end
	local pay = math.floor(info.Value * PlotStats.Get(owner).SalePrice * Config.DriveThru.PayMult + 0.5)
	pay = DataManager.EarnCash(owner, pay)
	DataManager.RecordSale(owner)
	DataManager.AddStat(owner, "TotalEarned", pay)
	Audio.PlayAt(car.PrimaryPart :: BasePart, Config.Sounds.Sale, 1.1, 0.8)
	return pay
end

-- Slides the kiosk window open (or shut) along its width, if the kiosk has one.
local function slideWindow(plot: Model, open: boolean)
	local items = plot:FindFirstChild("Items")
	local lane = items and items:FindFirstChild(UPGRADE)
	local window = lane and lane:FindFirstChild("KioskWindow", true)
	if not window or not window:IsA("BasePart") then
		return
	end
	local closed = window:GetAttribute("ClosedCFrame") :: CFrame?
	if not closed then
		closed = window.CFrame
		window:SetAttribute("ClosedCFrame", closed)
	end
	local target = (closed :: CFrame) * CFrame.new(0, 0, if open then -window.Size.Z * 0.9 else 0)
	TweenService:Create(window, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { CFrame = target }):Play()
end

local function runCar(plot: Model)
	busy[plot] = true
	local D = Config.DriveThru
	local roadZ, local3 = Vehicles.Road(plot)
	local function lane(z: number): Vector3
		return local3(D.LaneX, 0, z)
	end
	local mouth = lane(Config.Building.FrontZ + 4)
	local xEnd = Vehicles.EndX
	local fromX = if math.random() < 0.5 then -xEnd else xEnd
	local roadY, walkY = Vehicles.RoadY, Vehicles.SidewalkY
	local roadIn = Vector3.new(mouth.X, roadY, roadZ)
	local alive = function()
		return PlotManager.GetOwner(plot) ~= nil
	end

	local car = Vehicles.BuildCar()
	car:PivotTo(CFrame.lookAt(Vector3.new(fromX, roadY, roadZ), roadIn))
	car.Parent = Vehicles.Folder()
	Vehicles.Drive(car, {
		Vector3.new(fromX, roadY, roadZ),
		roadIn,
		Vector3.new(mouth.X, walkY, mouth.Z),
		lane(Config.Building.FrontZ - 2),
		lane(D.MenuZ),
	}, D.Speed)
	-- Order at the menu board, then pull up to the window.
	if car.Parent then
		Vehicles.Pop(car, "🗣️ One cake, please!", Color3.fromRGB(255, 210, 120))
		Vehicles.Sleep(D.MenuStop, alive)
	end
	Vehicles.Drive(car, { lane(D.MenuZ), lane(D.WindowZ) }, D.Speed * 0.6)
	if car.Parent and Vehicles.Sleep(0.2, alive) then
		slideWindow(plot, true)
		Vehicles.Sleep(0.5, alive)
		local paid = buy(plot, car)
		Vehicles.Pop(car, if paid then `🚗 +${paid}` else "😢 Sold out!", if paid then Color3.fromRGB(120, 255, 120) else Color3.fromRGB(255, 120, 120))
		Vehicles.Sleep(D.StopTime, function()
			return true
		end)
		slideWindow(plot, false)
	end
	Vehicles.Drive(car, { lane(D.WindowZ), lane(D.EndZ) }, D.Speed)
	Vehicles.TurnAround(car, 1)
	Vehicles.Drive(car, {
		lane(D.EndZ),
		lane(Config.Building.FrontZ - 2),
		Vector3.new(mouth.X, walkY, mouth.Z),
		roadIn,
		Vector3.new(-fromX, roadY, roadZ), -- out through the other tunnel
	}, D.Speed)
	car:Destroy()
	busy[plot] = nil
end

-- Sends a car now if none is on its way (tests).
function DriveThru.SendNow(plot: Model)
	if busy[plot] then
		return
	end
	local ok, err = pcall(runCar, plot)
	if not ok then
		busy[plot] = nil
		warn(`[DriveThru] {err}`)
	end
end

function DriveThru.Init()
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, plot in (workspace:WaitForChild("Plots") :: Folder):GetChildren() do
				local owner = plot:IsA("Model") and PlotManager.GetOwner(plot)
				if owner and DataManager.HasUnlock(owner, UPGRADE) and not busy[plot] and not plot:GetAttribute("Haunted") then
					if not nextAt[plot] then
						nextAt[plot] = now + Config.DriveThru.Interval
					elseif now >= nextAt[plot] and #BakingPipeline.GetSaleSlots(plot) > 0 then
						nextAt[plot] = now + Config.DriveThru.Interval * PlotStats.Get(owner).CustomerRate
						task.spawn(function()
							local ok, err = pcall(runCar, plot :: Model)
							if not ok then
								busy[plot :: Model] = nil
								warn(`[DriveThru] {err}`)
							end
						end)
					end
				elseif not owner then
					nextAt[plot] = nil
				end
			end
		end
	end)
end

return DriveThru
