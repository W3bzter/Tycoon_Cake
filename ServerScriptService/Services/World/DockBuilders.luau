--!strict
-- The Loading Dock (fixed upgrade "LoadingDock", Config.Trucks): a small loading
-- shed on the front patio corner opposite the drive-thru, with a roll-up door,
-- bumpers, a canopy light (NightLight) and a painted truck bay running out to
-- the street. Trucks: Customers/DeliveryTrucks. Plot-local studs (+Z = street).
-- An invisible BayBlock keeps the bay free of placed items (Build/BuildArea
-- reserves every ground-level part of a fixed item).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Services = script:FindFirstAncestor("Services") :: Folder
local Style = require(Services.World.Style)

local P = Style.Palette
local DockBuilders: { [string]: (floor: CFrame, item: Model) -> () } = {}

-- A board with text on its street side (+Z).
local function sign(name: string, size: Vector3, cf: CFrame, color: Color3, text: string, textColor: Color3, parent: Instance)
	local board = Style.RoundedBox(name, size, cf, color, parent, math.min(0.4, size.Z / 2))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.92, 0.85)
	label.Position = UDim2.fromScale(0.04, 0.075)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = textColor
	label.Text = text
	label.Parent = gui
end

-- Where a truck's back stops (in front of the bumpers), plot-local z.
function DockBuilders.StopZ(): number
	return Config.Trucks.DockZ + 2.2
end

DockBuilders.LoadingDock = function(floor, item)
	local T = Config.Trucks
	local x, half, dz = T.BayX, T.BayHalfWidth, T.DockZ
	local width = half * 2 + 4
	local front = Config.Building.FrontZ
	local function at(px: number, py: number, pz: number): CFrame
		return floor * CFrame.new(px, py, pz)
	end

	-- Shed: body, roof trim, roll-up door with slats, and the dock platform.
	local shedH = 8
	Style.RoundedBox("Shed", Vector3.new(width, shedH, T.ShedDepth), at(x, shedH / 2, dz - T.ShedDepth / 2), P.Cream, item, 0.6)
	Style.Trim("ShedRoof", Vector3.new(width + 1, 0.8, T.ShedDepth + 1), at(x, shedH + 0.2, dz - T.ShedDepth / 2), P.Cocoa, item)
	Style.Part({ Name = "DockPlatform", Size = Vector3.new(width - 1, 1.6, 1.6), CFrame = at(x, 0.8, dz + 0.8), Color = P.Steel, Parent = item })
	Style.Part({ Name = "DockDoor", Size = Vector3.new(half * 2 - 2, 5.6, 0.3), CFrame = at(x, 1.6 + 2.8, dz + 0.1), Color = P.Peach, Parent = item })
	for i = 1, 5 do
		Style.Part({ Name = "DoorSlat", Size = Vector3.new(half * 2 - 2.2, 0.15, 0.1), CFrame = at(x, 1.6 + i * 0.95, dz + 0.3), Color = P.Cocoa, CanCollide = false, Parent = item })
	end
	Style.Trim("DoorFrame", Vector3.new(half * 2 - 0.6, 0.5, 0.6), at(x, 7.4, dz + 0.2), P.HotPink, item)
	for _, side in { -1, 1 } do
		Style.Trim("DoorPost", Vector3.new(0.5, 6, 0.6), at(x + side * (half - 0.55), 4.6, dz + 0.2), P.HotPink, item)
		-- Black rubber bumpers and yellow-black bollards at the bay mouth.
		Style.RoundedBox("Bumper", Vector3.new(1.2, 1.2, 0.7), at(x + side * 3, 0.9, dz + 1.95), P.Charcoal, item, 0.25)
		Style.Cylinder("Bollard", 2.4, 0.7, at(x + side * (half + 0.9), 1.2, front - 1.5), P.Butter, item)
		Style.Cylinder("BollardBand", 0.4, 0.75, at(x + side * (half + 0.9), 1.6, front - 1.5), P.Charcoal, item).CanCollide = false
	end

	-- Canopy over the door with a light that comes on at night.
	Style.Part({ Name = "Canopy", Size = Vector3.new(width, 0.35, 3.4), CFrame = at(x, 8.2, dz + 1.5) * CFrame.Angles(math.rad(-10), 0, 0), Color = P.HotPink, Parent = item })
	local bulb = Style.Ball("DockLamp", 0.9, at(x, 7.7, dz + 1.6), P.Butter, item)
	local light = Instance.new("PointLight")
	light.Range = 22
	light.Brightness = 1.6
	light.Color = Color3.fromRGB(255, 225, 170)
	light.Enabled = false
	light.Parent = bulb
	CollectionService:AddTag(bulb, "NightLight")
	CollectionService:AddTag(light, "NightLight")
	sign("DockSign", Vector3.new(width - 3, 1.6, 0.3), at(x, shedH - 0.3, dz - 0.05) * CFrame.new(0, 1.6, 0), P.White, "📦 LOADING DOCK", P.Cocoa, item)

	-- The painted bay (flat, walk-over) and its reserved footprint.
	local bayLen = front - (dz + 1.6)
	local bayZ = (dz + 1.6 + front) / 2
	Style.Part({ Name = "BayPad", Size = Vector3.new(half * 2, 0.06, bayLen), CFrame = at(x, 0.03, bayZ), Color = P.Asphalt, CanCollide = false, Parent = item })
	for _, side in { -1, 1 } do
		Style.Part({ Name = "BayLine", Size = Vector3.new(0.4, 0.07, bayLen), CFrame = at(x + side * (half - 0.2), 0.04, bayZ), Color = P.Butter, CanCollide = false, Parent = item })
	end
	for z = dz + 4, front - 3, 3 do -- chevrons pointing at the dock
		for _, side in { -1, 1 } do
			Style.Part({
				Name = "Chevron",
				Size = Vector3.new(0.35, 0.07, 2.2),
				CFrame = at(x + side * 0.75, 0.045, z) * CFrame.Angles(0, side * math.rad(40), 0),
				Color = P.White,
				CanCollide = false,
				Parent = item,
			})
		end
	end
	Style.Part({
		Name = "BayBlock",
		Size = Vector3.new(half * 2 + 1, 1, bayLen),
		CFrame = at(x, 0.5, bayZ),
		Transparency = 1,
		CanCollide = false,
		Parent = item,
	})
end

return DockBuilders
