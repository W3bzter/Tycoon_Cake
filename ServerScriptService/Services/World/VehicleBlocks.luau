--!strict
-- Block (part-built) versions of the drive-thru car and the delivery truck, used
-- when the Blender models (ServerStorage.Assets.World.Car / DeliveryTruck) are
-- not imported. Front towards -Z, pivot on the ground at the centre. The truck's
-- back doors are a Model "BackDoor". Customers/Vehicles picks which to use.

local CollectionService = game:GetService("CollectionService")

local Services = script:FindFirstAncestor("Services") :: Folder
local Style = require(Services.World.Style)

local VehicleBlocks = {}

local P = Style.Palette

local function finish(model: Model, body: BasePart): Model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	model.PrimaryPart = body
	model.WorldPivot = CFrame.new()
	return model
end

local function headlights(model: Model, xs: { number }, y: number, z: number)
	for _, x in xs do
		local lamp = Style.Ball("Headlight", 0.6, CFrame.new(x, y, z), P.Butter, model)
		lamp.Material = Enum.Material.Neon
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Range = 24
		light.Angle = 60
		light.Brightness = 2
		light.Enabled = false
		light.Parent = lamp
		CollectionService:AddTag(light, "NightLight")
	end
end

local function wheels(model: Model, xs: { number }, zs: { number }, size: number)
	for _, x in xs do
		for _, z in zs do
			Style.Cylinder("Wheel", 0.7, size, CFrame.new(x, size / 2, z) * CFrame.Angles(0, 0, math.rad(90)), P.Charcoal, model)
			Style.Cylinder("Hubcap", 0.75, size * 0.45, CFrame.new(x, size / 2, z) * CFrame.Angles(0, 0, math.rad(90)), P.Steel, model)
		end
	end
end

-- A chunky cartoon car in a random colour.
function VehicleBlocks.Car(color: Color3): Model
	local car = Instance.new("Model")
	car.Name = "DriveThruCar"

	local body = Style.RoundedBox("Body", Vector3.new(4.2, 1.6, 7.4), CFrame.new(0, 1.5, 0), color, car, 0.7)
	Style.RoundedBox("Cabin", Vector3.new(3.8, 1.6, 3.8), CFrame.new(0, 3.0, 0.6), color, car, 0.6)
	for _, z in { -1.31, 2.51 } do -- windscreen and back window
		Style.Part({ Name = "Window", Size = Vector3.new(3.3, 1.1, 0.12), CFrame = CFrame.new(0, 3.05, z), Color = P.Glass, Material = Enum.Material.Glass, Transparency = 0.3, Parent = car })
	end
	for _, x in { -1.92, 1.92 } do
		Style.Part({ Name = "Window", Size = Vector3.new(0.12, 1.1, 3), CFrame = CFrame.new(x, 3.05, 0.6), Color = P.Glass, Material = Enum.Material.Glass, Transparency = 0.3, Parent = car })
	end
	wheels(car, { -1.92, 1.92 }, { -2.4, 2.4 }, 1.6)
	headlights(car, { -1.4, 1.4 }, 1.7, -3.7)
	return finish(car, body)
end

-- A bakery delivery truck: cab in front, a tall pink box with a cake sign, and
-- roll-up back doors (Model "BackDoor", opened by DeliveryTrucks). Length ~14.
function VehicleBlocks.Truck(): Model
	local truck = Instance.new("Model")
	truck.Name = "DeliveryTruck"
	local chassis = Style.RoundedBox("Body", Vector3.new(5.6, 1, 13.6), CFrame.new(0, 1.6, 0), P.Charcoal, truck, 0.3)
	-- Cab (front, -Z)
	Style.RoundedBox("Cab", Vector3.new(5.4, 4, 3.8), CFrame.new(0, 4, -4.8), P.White, truck, 0.7)
	Style.Part({ Name = "Windscreen", Size = Vector3.new(4.6, 1.8, 0.12), CFrame = CFrame.new(0, 4.9, -6.72), Color = P.Glass, Material = Enum.Material.Glass, Transparency = 0.3, Parent = truck })
	for _, x in { -2.72, 2.72 } do
		Style.Part({ Name = "Window", Size = Vector3.new(0.12, 1.6, 2), CFrame = CFrame.new(x, 4.9, -5), Color = P.Glass, Material = Enum.Material.Glass, Transparency = 0.3, Parent = truck })
	end
	Style.Trim("Grille", Vector3.new(4, 0.9, 0.3), CFrame.new(0, 2.6, -6.8), P.Steel, truck)
	-- Cargo box
	local box = Style.RoundedBox("CargoBox", Vector3.new(5.8, 6, 9), CFrame.new(0, 5.1, 2.1), P.Pink, truck, 0.5)
	Style.Trim("BoxStripe", Vector3.new(5.95, 0.6, 8.6), CFrame.new(0, 3.2, 2.1), P.HotPink, truck)
	for _, side in { -1, 1 } do
		local panel = Style.Part({ Name = "SidePanel", Size = Vector3.new(0.1, 3.2, 6.4), CFrame = CFrame.new(side * 2.95, 5.6, 2.1), Color = P.White, Parent = truck })
		local gui = Instance.new("SurfaceGui")
		gui.Face = if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = panel
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = P.HotPink
		label.Text = "🍰 CAKE\nDELIVERY"
		label.Parent = gui
	end
	local door = Instance.new("Model")
	door.Name = "BackDoor"
	Style.Part({ Name = "Door", Size = Vector3.new(5, 5.2, 0.2), CFrame = CFrame.new(0, 5.1, 6.65), Color = P.Peach, Parent = door })
	for i = 1, 4 do
		Style.Part({ Name = "Slat", Size = Vector3.new(4.8, 0.12, 0.1), CFrame = CFrame.new(0, 2.9 + i * 1.05, 6.78), Color = P.Cocoa, Parent = door })
	end
	door.Parent = truck
	for _, x in { -2.3, 2.3 } do
		local tail = Style.Part({ Name = "TailLight", Size = Vector3.new(0.6, 0.6, 0.15), CFrame = CFrame.new(x, 2.4, 6.75), Color = Color3.fromRGB(255, 70, 70), Material = Enum.Material.Neon, Parent = truck })
		tail.CanCollide = false
	end
	wheels(truck, { -2.75, 2.75 }, { -4.6, 3.8 }, 2.2)
	headlights(truck, { -1.9, 1.9 }, 2.7, -6.85)
	box.CanCollide = false
	return finish(truck, chassis)
end

return VehicleBlocks
