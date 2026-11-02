--!strict
-- What the drive-thru cars (Customers/DriveThru) and the delivery trucks
-- (Customers/DeliveryTrucks) share: their models, moving them along a path, and
-- small helpers. Vehicles are anchored models moved by the server (no physics),
-- front towards -Z, pivot on the ground at their centre, all in workspace.Vehicles.
-- Models: the Blender Car / DeliveryTruck (World/WorldModels) when imported, else
-- the block versions (World/VehicleBlocks). Every move goes through `move`, which
-- also rolls the Wheel*/Hub* parts by the distance driven. Headlights are
-- NightLight (on at night).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildRules = require(Shared:WaitForChild("BuildRules"))
local Config = require(Shared:WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local Style = require(Services.World.Style)
local VehicleBlocks = require(Services.World.VehicleBlocks)
local WorldModels = require(Services.World.WorldModels)

local Vehicles = {}

local P = Style.Palette
local ROAD_MID = 15 -- world Z of the road's centre line (WorldBuilder)
Vehicles.RoadY = 0.2
Vehicles.SidewalkY = 0.6
Vehicles.TruckLength = 14
-- Where vehicles appear and vanish: just inside the tunnel mouths at the road ends.
Vehicles.EndX = Config.StreetLength / 2 + 5
local CAR_COLORS = { P.Sky, P.Mint, P.Lilac, P.Butter, P.Peach, P.HotPink, Color3.fromRGB(240, 90, 80) }

local folder: Folder? = nil
function Vehicles.Folder(): Folder
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "Vehicles"
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

-- Wheels that roll as the vehicle moves (Blender models only).
type Wheel = { part: BasePart, offset: CFrame, radius: number }
type Rig = { wheels: { Wheel }, last: CFrame, roll: number }
local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any

local function rig(model: Model)
	local pivot = model:GetPivot()
	local wheels: { Wheel } = {}
	local radius = 1
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 5) == "Wheel" then
			radius = math.max(0.3, math.max(d.Size.Y, d.Size.Z) / 2)
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (string.sub(d.Name, 1, 5) == "Wheel" or string.sub(d.Name, 1, 3) == "Hub") then
			table.insert(wheels, { part = d, offset = pivot:ToObjectSpace(d.CFrame), radius = radius })
		end
	end
	if #wheels > 0 then
		rigs[model] = { wheels = wheels, last = pivot, roll = 0 }
	end
end

-- Moves the vehicle and rolls its wheels by the (signed) distance driven.
local function move(model: Model, cf: CFrame)
	model:PivotTo(cf)
	local r = rigs[model]
	if not r then
		return
	end
	local forward = (cf.Position - r.last.Position):Dot(cf.LookVector)
	r.last = cf
	r.roll -= forward / r.wheels[1].radius -- front is -Z: rolling forward turns about -X
	local spin = CFrame.Angles(r.roll, 0, 0)
	for _, w in r.wheels do
		w.part.CFrame = cf * CFrame.new(w.offset.Position) * spin * w.offset.Rotation
	end
end

local function headlights(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Light" then
			local light = Instance.new("SpotLight")
			light.Face = WorldModels.FaceToward(d, -Vector3.zAxis)
			light.Range = 26
			light.Angle = 70
			light.Brightness = 2
			light.Enabled = false
			light.Parent = d
			CollectionService:AddTag(light, "NightLight")
		end
	end
end

-- A drive-thru car in a random colour.
function Vehicles.BuildCar(): Model
	local color = CAR_COLORS[math.random(#CAR_COLORS)]
	local car = WorldModels.Clone("Car", { Roles = { Body = color } })
	if not car then
		return VehicleBlocks.Car(color)
	end
	car.Name = "DriveThruCar"
	headlights(car)
	rig(car)
	return car
end

-- A bakery delivery truck (the model has its own cake emblem on the box).
function Vehicles.BuildTruck(): Model
	local truck = WorldModels.Clone("DeliveryTruck", { Roles = { Body = P.White } })
	if not truck then
		return VehicleBlocks.Truck()
	end
	truck.Name = "DeliveryTruck"
	headlights(truck)
	rig(truck)
	return truck
end

-- Rolls the truck's back door up (open) or down. Blender model: RearDoor rolls
-- up into the box top (shrinks upwards to a thin roll); block truck: the
-- BackDoor model jumps up.
function Vehicles.SetRearDoor(truck: Model, open: boolean)
	local door = truck:FindFirstChild("RearDoor")
	if door and door:IsA("BasePart") then
		local closed = door:GetAttribute("ClosedOffset") :: CFrame?
		local fullSize = door:GetAttribute("ClosedSize") :: Vector3?
		if not closed or not fullSize then
			closed = truck:GetPivot():ToObjectSpace(door.CFrame)
			fullSize = door.Size
			door:SetAttribute("ClosedOffset", closed)
			door:SetAttribute("ClosedSize", fullSize)
		end
		local cf = truck:GetPivot() * (closed :: CFrame)
		local size = fullSize :: Vector3
		if open then
			-- The door's own axis that points up (imports turn part frames).
			local axes = { cf.RightVector, cf.UpVector, -cf.LookVector }
			local best, k = 1, 0
			for i, a in axes do
				if math.abs(a.Y) > k then
					best, k = i, math.abs(a.Y)
				end
			end
			local height = ({ size.X, size.Y, size.Z })[best]
			local keep = 0.1 -- what's left showing: the rolled-up door
			local scale = Vector3.new(if best == 1 then keep else 1, if best == 2 then keep else 1, if best == 3 then keep else 1)
			size = size * scale
			cf += Vector3.new(0, height * (1 - keep) / 2, 0)
		end
		TweenService:Create(door, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { CFrame = cf, Size = size }):Play()
		return
	end
	local block = truck:FindFirstChild("BackDoor")
	if block and block:IsA("Model") then
		local up = block:GetAttribute("Open") == true
		if up ~= open then
			block:PivotTo(block:GetPivot() + Vector3.new(0, if open then 4.6 else -4.6, 0))
			block:SetAttribute("Open", open)
		end
	end
end

-- Waits `seconds`, stopping early (false) once `alive()` is false.
function Vehicles.Sleep(seconds: number, alive: () -> boolean): boolean
	local untilAt = os.clock() + seconds
	while os.clock() < untilAt do
		if not alive() then
			return false
		end
		task.wait(0.1)
	end
	return true
end

-- Drives `model` through `points` at `speed`, facing the way it goes.
function Vehicles.Drive(model: Model, points: { Vector3 }, speed: number)
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local flat = (b - a) * Vector3.new(1, 0, 1)
		local length = (b - a).Magnitude
		if length > 0.05 and model.Parent then
			local facing = if flat.Magnitude > 0.05 then flat.Unit else model:GetPivot().LookVector
			local t = 0
			while t < length and model.Parent do
				t = math.min(length, t + RunService.Heartbeat:Wait() * speed)
				local pos = a:Lerp(b, t / length)
				move(model, CFrame.lookAt(pos, pos + facing))
			end
		end
	end
end

-- Moves (and turns) `model` from where it is to `target` at `speed` studs/s,
-- taking at least `minTime` seconds: used for reversing and turning.
function Vehicles.Glide(model: Model, target: CFrame, speed: number, minTime: number?)
	local start = model:GetPivot()
	local time = math.max((target.Position - start.Position).Magnitude / speed, minTime or 0)
	local t = 0
	while t < time and model.Parent do
		t = math.min(time, t + RunService.Heartbeat:Wait())
		local alpha = t / time
		move(model, start:Lerp(target, alpha * alpha * (3 - 2 * alpha))) -- ease in/out
	end
end

-- Turns the model round on the spot over `time` seconds.
function Vehicles.TurnAround(model: Model, time: number)
	local start = model:GetPivot()
	local t = 0
	while t < time and model.Parent do
		t = math.min(time, t + RunService.Heartbeat:Wait())
		move(model, start * CFrame.Angles(0, math.pi * (t / time), 0))
	end
end

-- A short-lived "+$" / "sold out" label over the vehicle.
function Vehicles.Pop(model: Model, text: string, color: Color3, height: number?)
	local gui = Style.Billboard(model.PrimaryPart :: BasePart, { text }, { Name = "Pop", Width = 6, Height = 1.6, Offset = Vector3.new(0, height or 5, 0), MaxDistance = 80, Stroke = color })
	task.delay(2.5, gui.Destroy, gui)
end

-- The road next to `plot`: Z of the carriageway on the bakery's side, and the
-- world position of plot-local (x, y, z).
function Vehicles.Road(plot: Model): (number, (x: number, y: number, z: number) -> Vector3)
	local floor = BuildRules.Floor(plot)
	local towardsStreet = floor:VectorToWorldSpace(Vector3.zAxis).Z -- +1 near row, -1 far row
	local roadZ = ROAD_MID - 5 * towardsStreet
	return roadZ, function(x: number, y: number, z: number): Vector3
		return (floor * CFrame.new(x, y, z)).Position
	end
end

return Vehicles
