--!strict
-- Geometry for placeable decor (Shared/BuildCatalog Kind = "Decor"). Same
-- signature as ItemBuilders, but each item is built centred on the floor origin;
-- Build/BuildModels moves it to where the player placed it.

local Services = script:FindFirstAncestor("Services") :: Folder
local Style = require(Services.World.Style)

local P = Style.Palette

local DecorBuilders: { [string]: (floor: CFrame, item: Model) -> () } = {}

local function at(floor: CFrame, x: number, y: number, z: number): CFrame
	return floor * CFrame.new(x, y, z)
end

DecorBuilders.PottedPlant = function(floor, item)
	Style.Cylinder("Pot", 2.2, 2.6, at(floor, 0, 1.1, 0), P.Peach, item)
	Style.Ball("Leaves", 3, at(floor, 0, 3, 0), P.Leaf, item)
	Style.Ball("Flower", 0.9, at(floor, 0.8, 4.2, 0.5), P.HotPink, item)
	Style.Ball("Flower", 0.9, at(floor, -0.7, 4.1, -0.4), P.Butter, item)
end

DecorBuilders.Rug = function(floor, item)
	Style.Cylinder("Rug", 0.12, 7, at(floor, 0, 0.06, 0), P.Lilac, item)
	Style.Cylinder("RugRing", 0.14, 5, at(floor, 0, 0.07, 0), P.Pink, item)
	Style.Cylinder("RugCentre", 0.16, 2.6, at(floor, 0, 0.08, 0), P.Cream, item)
end

DecorBuilders.Balloons = function(floor, item)
	Style.RoundedBox("Weight", Vector3.new(1.4, 0.8, 1.4), at(floor, 0, 0.4, 0), P.Charcoal, item, 0.3)
	local colors = { P.HotPink, P.Sky, P.Butter, P.Mint, P.Lilac }
	for i, color in colors do
		local a = i / #colors * math.pi * 2
		local x, z, y = math.cos(a) * 0.9, math.sin(a) * 0.9, 6.5 + (i % 2) * 0.8
		Style.Part({ Name = "String", Size = Vector3.new(0.06, y - 0.8, 0.06), CFrame = CFrame.lookAt(at(floor, x / 2, (y + 0.8) / 2, z / 2).Position, at(floor, x, y, z).Position) * CFrame.Angles(math.rad(90), 0, 0), Color = P.White, Parent = item })
		local balloon = Style.Ball("Balloon", 1.8, at(floor, x, y, z), color, item)
		balloon.Material = Enum.Material.Glass
		balloon.Transparency = 0.1
	end
end

DecorBuilders.CafeTable = function(floor, item)
	Style.Cylinder("TableTop", 0.4, 4.4, at(floor, 0, 3, 0), P.White, item)
	Style.Cylinder("TableLeg", 2.8, 0.6, at(floor, 0, 1.4, 0), P.HotPink, item)
	for _, dx in { -3, 3 } do
		Style.RoundedBox("Chair", Vector3.new(1.8, 1.8, 1.8), at(floor, dx, 0.9, 0), P.Mint, item, 0.6)
	end
end

DecorBuilders.CupcakeStatue = function(floor, item)
	Style.RoundedBox("Plinth", Vector3.new(5, 1.2, 5), at(floor, 0, 0.6, 0), P.Cream, item, 0.6)
	Style.Cylinder("Case", 3.2, 4, at(floor, 0, 2.8, 0), P.Peach, item)
	Style.Ball("Frosting", 4.6, at(floor, 0, 5.2, 0), P.Pink, item)
	Style.Ball("Frosting2", 3.2, at(floor, 0, 6.6, 0), P.HotPink, item)
	local cherry = Style.Ball("Cherry", 1.2, at(floor, 0, 8.4, 0), Color3.fromRGB(230, 40, 60), item)
	cherry.Material = Enum.Material.Neon
end

DecorBuilders.CakeCharm = function(floor, item)
	Style.Cylinder("Stand", 3, 0.3, at(floor, 0, 1.5, 0), P.Gold, item)
	Style.Cylinder("Base", 0.4, 2, at(floor, 0, 0.2, 0), P.Gold, item)
	local charm = Style.Ball("Charm", 1.4, at(floor, 0, 3.6, 0), Color3.fromRGB(80, 220, 120), item)
	charm.Material = Enum.Material.Neon
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = P.Gold
	sparkle.Parent = charm
end

return DecorBuilders
