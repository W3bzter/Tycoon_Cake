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


-- Kitchen props (no machine: pure looks) ------------------------------------------

DecorBuilders.Fridge = function(floor, item)
	Style.RoundedBox("Body", Vector3.new(4, 8, 3), at(floor, 0, 4, 0), P.White, item, 0.6)
	Style.Part({ Name = "DoorGap", Size = Vector3.new(3.8, 0.12, 0.1), CFrame = at(floor, 0, 5.4, 1.52), Color = P.Steel, Parent = item })
	for _, y in { 3.4, 6.6 } do
		Style.RoundedBox("Handle", Vector3.new(0.3, 1.6, 0.3), at(floor, 1.4, y, 1.65), P.Steel, item, 0.12)
	end
	Style.Ball("Magnet", 0.6, at(floor, -0.8, 6.8, 1.55), P.HotPink, item)
	Style.Ball("Magnet", 0.5, at(floor, -0.2, 7.2, 1.55), P.Sky, item)
	Style.RoundedBox("Note", Vector3.new(1, 1.2, 0.05), at(floor, -0.6, 3.6, 1.53), P.Butter, item, 0.05)
end

DecorBuilders.Sink = function(floor, item)
	Style.RoundedBox("Cabinet", Vector3.new(6, 3.4, 3), at(floor, 0, 1.7, 0), P.Mint, item, 0.4)
	Style.Trim("Top", Vector3.new(6.4, 0.4, 3.2), at(floor, 0, 3.6, 0), P.White, item)
	Style.Part({ Name = "Basin", Size = Vector3.new(3, 0.3, 2), CFrame = at(floor, 0, 3.72, 0.1), Color = P.Steel, Parent = item })
	Style.Cylinder("Tap", 1.4, 0.3, at(floor, 0, 4.5, -1.1), P.Steel, item)
	Style.Part({ Name = "Spout", Size = Vector3.new(0.3, 0.3, 1.2), CFrame = at(floor, 0, 5.1, -0.6), Color = P.Steel, Parent = item })
	for _, x in { -1.5, 1.5 } do
		Style.Part({ Name = "DoorLine", Size = Vector3.new(0.1, 2.6, 0.05), CFrame = at(floor, x * 0.02, 1.7, 1.52), Color = P.DeepMint, Parent = item })
		Style.Ball("Knob", 0.35, at(floor, x * 0.4, 2.4, 1.6), P.White, item)
	end
end

DecorBuilders.PrepCounter = function(floor, item)
	Style.Trim("Top", Vector3.new(8, 0.6, 3.4), at(floor, 0, 3.4, 0), P.Cream, item)
	for _, x in { -3.4, 3.4 } do
		for _, z in { -1.2, 1.2 } do
			Style.Cylinder("Leg", 3.1, 0.4, at(floor, x, 1.55, z), P.Steel, item)
		end
	end
	Style.Part({ Name = "Shelf", Size = Vector3.new(7.4, 0.3, 2.8), CFrame = at(floor, 0, 0.9, 0), Color = P.Steel, Parent = item })
	Style.Cylinder("RollingPin", 3, 0.5, at(floor, -1.5, 3.95, 0.3) * CFrame.Angles(0, 0, math.rad(90)), P.Peach, item)
	Style.Cylinder("Bowl", 0.9, 1.8, at(floor, 2, 4.15, -0.2), P.Sky, item)
	Style.Ball("Dough", 1.2, at(floor, 0.4, 3.95, -0.4), P.Vanilla, item)
end

DecorBuilders.CoffeeMachine = function(floor, item)
	Style.RoundedBox("Cart", Vector3.new(4, 3, 3), at(floor, 0, 1.5, 0), P.Cocoa, item, 0.4)
	Style.RoundedBox("Machine", Vector3.new(3, 2.6, 2.2), at(floor, 0, 4.3, -0.2), P.HotPink, item, 0.5)
	Style.Part({ Name = "Spout", Size = Vector3.new(0.4, 0.6, 0.4), CFrame = at(floor, 0, 3.7, 1), Color = P.Charcoal, Parent = item })
	Style.Cylinder("Cup", 0.6, 0.6, at(floor, 0, 3.3, 1), P.White, item)
	Style.Ball("Light", 0.35, at(floor, 1, 5, 0.92), P.Mint, item).Material = Enum.Material.Neon
	for _, x in { -1.2, 1.2 } do
		Style.Cylinder("Mug", 0.6, 0.6, at(floor, x, 3.3, 1), if x < 0 then P.Butter else P.Sky, item)
	end
end

DecorBuilders.BreadShelf = function(floor, item)
	Style.RoundedBox("Frame", Vector3.new(6, 6, 2), at(floor, 0, 3, -0.4), P.Cocoa, item, 0.3)
	for i, y in { 1.4, 3.4, 5.2 } do
		Style.Part({ Name = "Shelf", Size = Vector3.new(5.6, 0.25, 2), CFrame = at(floor, 0, y - 0.4, 0.2), Color = P.Peach, Parent = item })
		for k = -1, 1 do
			Style.RoundedBox("Basket", Vector3.new(1.5, 0.6, 1.3), at(floor, k * 1.8, y - 0.05, 0.3), P.Butter, item, 0.3)
			if (i + k) % 2 == 0 then
				Style.RoundedBox("Loaf", Vector3.new(1.3, 0.6, 0.9), at(floor, k * 1.8, y + 0.35, 0.3), Color3.fromRGB(205, 140, 80), item, 0.35)
			else
				Style.Ball("Bun", 0.8, at(floor, k * 1.8, y + 0.35, 0.3), Color3.fromRGB(220, 160, 95), item)
			end
		end
	end
end

DecorBuilders.RunnerRug = function(floor, item)
	Style.RoundedBox("Rug", Vector3.new(4, 0.1, 10), at(floor, 0, 0.05, 0), P.HotPink, item, 0.6).CanCollide = false
	Style.RoundedBox("Stripe", Vector3.new(2.6, 0.12, 8.6), at(floor, 0, 0.07, 0), P.Cream, item, 0.4).CanCollide = false
	for _, z in { -3, 0, 3 } do
		Style.Ball("Dot", 0.8, at(floor, 0, 0.05, z), P.Mint, item).CanCollide = false
	end
end

return DecorBuilders
