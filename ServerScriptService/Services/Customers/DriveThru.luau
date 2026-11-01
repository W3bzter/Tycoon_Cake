--!strict
-- Drive-thru cars (fixed upgrade "DriveThru", lane built by ItemBuilders.DriveThru).
-- Every Config.DriveThru.Interval seconds (sped up by the customer-rate upgrades),
-- if the bakery has a cake for sale, a car comes out of a tunnel, drives along
-- the road, turns into the lane, stops at the kiosk, buys a cake (reserved like a
-- walking customer's, so they never fight over one), pays PayMult x the price,
-- turns round on the pad and drives off into the other tunnel. One car per bakery
-- at a time. Cars are anchored models moved by the server (no physics).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildRules = require(Shared:WaitForChild("BuildRules"))
local Config = require(Shared:WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local Audio = require(Services.Core.Audio)
local BakingPipeline = require(Services.Baking.BakingPipeline)
local DataManager = require(Services.Core.DataManager)
local PlotManager = require(Services.Core.PlotManager)
local PlotStats = require(Services.Core.PlotStats)
local Style = require(Services.World.Style)

local DriveThru = {}

local P = Style.Palette
local UPGRADE = "DriveThru"
local ROAD_MID, ROAD_Y, SIDEWALK_Y = 15, 0.2, 0.6
local CAR_COLORS = { P.Sky, P.Mint, P.Lilac, P.Butter, P.Peach, P.HotPink, Color3.fromRGB(240, 90, 80) }

local busy: { [Model]: boolean } = {}
local nextAt: { [Model]: number } = {}
local folder: Folder

-- A chunky cartoon car, front towards -Z, pivot on the ground at its centre.
local function buildCar(): Model
	local car = Instance.new("Model")
	car.Name = "DriveThruCar"
	local color = CAR_COLORS[math.random(#CAR_COLORS)]
	local body = Style.RoundedBox("Body", Vector3.new(4.2, 1.6, 7.4), CFrame.new(0, 1.5, 0), color, car, 0.7)
	Style.RoundedBox("Cabin", Vector3.new(3.8, 1.6, 3.8), CFrame.new(0, 3.0, 0.6), color, car, 0.6)
	for _, z in { -1.31, 2.51 } do -- windscreen and back window
		Style.Part({ Name = "Window", Size = Vector3.new(3.3, 1.1, 0.12), CFrame = CFrame.new(0, 3.05, z), Color = P.Glass, Material = Enum.Material.Glass, Transparency = 0.3, Parent = car })
	end
	for _, x in { -1.92, 1.92 } do
		Style.Part({ Name = "Window", Size = Vector3.new(0.12, 1.1, 3), CFrame = CFrame.new(x, 3.05, 0.6), Color = P.Glass, Material = Enum.Material.Glass, Transparency = 0.3, Parent = car })
		for _, z in { -2.4, 2.4 } do
			Style.Cylinder("Wheel", 0.7, 1.6, CFrame.new(x, 0.8, z) * CFrame.Angles(0, 0, math.rad(90)), P.Charcoal, car)
		end
	end
	for _, x in { -1.4, 1.4 } do
		local light = Style.Ball("Headlight", 0.6, CFrame.new(x, 1.7, -3.7), P.Butter, car)
		light.Material = Enum.Material.Neon
	end
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	car.PrimaryPart = body
	car.WorldPivot = CFrame.new()
	return car
end

local function sleep(seconds: number, alive: () -> boolean): boolean
	local untilAt = os.clock() + seconds
	while os.clock() < untilAt do
		if not alive() then
			return false
		end
		task.wait(0.1)
	end
	return true
end

-- Drives `car` through `points` at Config speed, facing the way it goes.
local function drive(car: Model, points: { Vector3 })
	local speed = Config.DriveThru.Speed
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local flat = (b - a) * Vector3.new(1, 0, 1)
		local length = (b - a).Magnitude
		if length > 0.05 and car.Parent then
			local facing = if flat.Magnitude > 0.05 then flat.Unit else car:GetPivot().LookVector
			local t = 0
			while t < length and car.Parent do
				t = math.min(length, t + RunService.Heartbeat:Wait() * speed)
				local pos = a:Lerp(b, t / length)
				car:PivotTo(CFrame.lookAt(pos, pos + facing))
			end
		end
	end
end

-- Turns the car round on the spot over `time` seconds.
local function turnAround(car: Model, time: number)
	local start = car:GetPivot()
	local t = 0
	while t < time and car.Parent do
		t = math.min(time, t + RunService.Heartbeat:Wait())
		car:PivotTo(start * CFrame.Angles(0, math.pi * (t / time), 0))
	end
end

local function popText(car: Model, text: string, color: Color3)
	local gui = Style.Billboard(car.PrimaryPart :: BasePart, { text }, { Name = "Pop", Width = 6, Height = 1.6, Offset = Vector3.new(0, 5, 0), MaxDistance = 80, Stroke = color })
	task.delay(2.5, gui.Destroy, gui)
end

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

local function runCar(plot: Model)
	busy[plot] = true
	local D = Config.DriveThru
	local floor = BuildRules.Floor(plot)
	local towardsStreet = floor:VectorToWorldSpace(Vector3.zAxis).Z -- +1 near row, -1 far row
	local roadZ = ROAD_MID - 5 * towardsStreet -- the carriageway on the bakery's side
	local function lane(z: number): Vector3
		return (floor * CFrame.new(D.LaneX, 0, z)).Position
	end
	local mouth = lane(Config.Building.FrontZ + 4)
	local xEnd = Config.StreetLength / 2 - 6
	local fromX = if math.random() < 0.5 then -xEnd else xEnd
	local roadIn = Vector3.new(mouth.X, ROAD_Y, roadZ)
	local alive = function()
		return PlotManager.GetOwner(plot) ~= nil
	end

	local car = buildCar()
	car:PivotTo(CFrame.lookAt(Vector3.new(fromX, ROAD_Y, roadZ), roadIn))
	car.Parent = folder
	drive(car, {
		Vector3.new(fromX, ROAD_Y, roadZ),
		roadIn,
		Vector3.new(mouth.X, SIDEWALK_Y, mouth.Z),
		lane(Config.Building.FrontZ - 2),
		lane(D.WindowZ),
	})
	if car.Parent and sleep(0.4, alive) then
		local paid = buy(plot, car)
		popText(car, if paid then `🚗 +${paid}` else "😢 Sold out!", if paid then Color3.fromRGB(120, 255, 120) else Color3.fromRGB(255, 120, 120))
		sleep(D.StopTime, function()
			return true
		end)
	end
	drive(car, { lane(D.WindowZ), lane(D.EndZ) })
	turnAround(car, 1)
	drive(car, {
		lane(D.EndZ),
		lane(Config.Building.FrontZ - 2),
		Vector3.new(mouth.X, SIDEWALK_Y, mouth.Z),
		roadIn,
		Vector3.new(-fromX, ROAD_Y, roadZ), -- out through the other tunnel
	})
	car:Destroy()
	busy[plot] = nil
end

function DriveThru.Init()
	folder = Instance.new("Folder")
	folder.Name = "DriveThruCars"
	folder.Parent = workspace
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
