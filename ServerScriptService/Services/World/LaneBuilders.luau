--!strict
-- The drive-thru lane (fixed upgrade "DriveThru", Config.DriveThru): a car lane
-- beside the plot (outside its floor, x 62..70) from the street to a turnaround
-- pad, a menu board where cars stop to order, the pickup kiosk at the window and
-- a street sign. The kiosk and menu board are the Blender models
-- (World/WorldModels DriveThruKiosk / MenuBoard) when imported, else blocks.
-- The kiosk's sliding part is named "KioskWindow" either way (Customers/DriveThru
-- slides it open when a car stops). Cars: Customers/DriveThru.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Services = script:FindFirstAncestor("Services") :: Folder
local Style = require(Services.World.Style)
local WorldModels = require(Services.World.WorldModels)

local P = Style.Palette
local LaneBuilders: { [string]: (floor: CFrame, item: Model) -> () } = {}

local function at(floor: CFrame, x: number, y: number, z: number): CFrame
	return floor * CFrame.new(x, y, z)
end

-- A board with text on the side facing `dir` (plot-local direction).
local function board(name: string, size: Vector3, cf: CFrame, color: Color3, text: string, textColor: Color3, floor: CFrame, dir: Vector3, parent: Instance): BasePart
	local part = Style.RoundedBox(name, size, cf, color, parent, math.min(0.4, size.Z / 2, size.X / 2))
	WorldModels.Write(part, floor:VectorToWorldSpace(dir), text, textColor)
	return part
end

local MENU_TEXT = "MENU\n🍰 Cakes\n🧁 Cupcakes\n☕ Coffee"

local function kiosk(floor: CFrame, item: Model, kz: number)
	local lane = Vector3.xAxis -- the window side faces the lane (+X)
	local model = WorldModels.Place("DriveThruKiosk", at(floor, 60, 0, kz), item, { Height = 9 })
	if model then
		model.Name = "Kiosk"
		local window = model:FindFirstChild("Window")
		if window then
			window.Name = "KioskWindow"
		end
		local sign = model:FindFirstChild("SignBoard") :: BasePart?
		if sign then
			WorldModels.Write(sign, floor:VectorToWorldSpace(lane), "🍰 PICK UP", P.White)
		end
		WorldModels.LightBulbs(model, 14)
		return
	end
	Style.RoundedBox("Kiosk", Vector3.new(2.4, 6.5, 7), at(floor, 60.8, 3.25, kz), P.Cream, item, 0.5)
	Style.Part({ Name = "KioskWindow", Size = Vector3.new(0.2, 2.4, 3.4), CFrame = at(floor, 62.05, 3.6, kz), Color = P.Glass, Material = Enum.Material.Glass, Transparency = 0.4, Parent = item })
	Style.Trim("Sill", Vector3.new(1.2, 0.3, 3.8), at(floor, 62.3, 2.35, kz), P.HotPink, item)
	Style.Part({ Name = "KioskRoof", Size = Vector3.new(4.2, 0.4, 8), CFrame = at(floor, 61.6, 6.7, kz) * CFrame.Angles(0, 0, math.rad(-12)), Color = P.HotPink, Parent = item })
	board("PickupSign", Vector3.new(0.3, 1.2, 3.6), at(floor, 62.25, 5.4, kz), P.White, "🍰 PICK UP", P.HotPink, floor, lane, item)
end

local function menuBoard(floor: CFrame, item: Model, mz: number)
	local lane = Vector3.xAxis
	local model = WorldModels.Place("MenuBoard", at(floor, 60.4, 0, mz), item)
	if model then
		model.Name = "MenuBoard"
		local sign = model:FindFirstChild("SignBoard") :: BasePart?
		if sign then
			WorldModels.Write(sign, floor:VectorToWorldSpace(lane), MENU_TEXT, P.White)
		end
		WorldModels.LightBulbs(model, 10)
		return
	end
	for _, dz in { -1.8, 1.8 } do
		Style.Cylinder("MenuPost", 5.4, 0.4, at(floor, 61, 2.7, mz + dz), P.Charcoal, item)
	end
	board("MenuBoard", Vector3.new(0.3, 3.4, 4.4), at(floor, 61, 4.2, mz), Color3.fromRGB(45, 55, 50), MENU_TEXT, P.White, floor, lane, item)
end

LaneBuilders.DriveThru = function(floor, item)
	local D = Config.DriveThru
	local x = D.LaneX
	local z0, z1 = D.EndZ - 5, Config.Building.FrontZ
	Style.Part({ Name = "Lane", Size = Vector3.new(8, 1, z1 - z0), CFrame = at(floor, x, -0.5, (z0 + z1) / 2), Color = P.Asphalt, Parent = item })
	for _, side in { -1, 1 } do
		Style.Part({ Name = "Curb", Size = Vector3.new(0.5, 0.5, z1 - z0), CFrame = at(floor, x + side * 4.25, 0.25, (z0 + z1) / 2), Color = P.White, Parent = item })
	end
	for z = z0 + 6, z1 - 4, 6 do
		Style.Part({ Name = "Dash", Size = Vector3.new(0.4, 0.05, 2.4), CFrame = at(floor, x, 0.03, z), Color = P.Butter, CanCollide = false, Parent = item })
	end
	Style.Cylinder("Turnaround", 0.06, 8, at(floor, x, 0.04, D.EndZ), P.HotPink, item).CanCollide = false
	kiosk(floor, item, D.WindowZ)
	menuBoard(floor, item, D.MenuZ)
	-- Street sign at the lane mouth.
	Style.Cylinder("SignPost", 7, 0.5, at(floor, x + 5.2, 3.5, z1 - 3), P.White, item)
	board("DriveThruSign", Vector3.new(6, 2.4, 0.4), at(floor, x + 5.2, 7.6, z1 - 3), P.HotPink, "🚗 DRIVE-THRU", P.White, floor, Vector3.zAxis, item)
end

return LaneBuilders
