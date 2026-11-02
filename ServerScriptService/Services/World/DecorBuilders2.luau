--!strict
-- More placeable decor (Shared/BuildCatalog Kind = "Decor"); same rules as
-- World/DecorBuilders: built centred on the floor origin, front towards +Z.
-- Lamps and lit signs are tagged NightLight (World/DayNight lights them at night).

local CollectionService = game:GetService("CollectionService")

local Services = script:FindFirstAncestor("Services") :: Folder
local Style = require(Services.World.Style)

local P = Style.Palette

local DecorBuilders2: { [string]: (floor: CFrame, item: Model) -> () } = {}

local function at(floor: CFrame, x: number, y: number, z: number): CFrame
	return floor * CFrame.new(x, y, z)
end

local function glow(part: BasePart, range: number, color: Color3?)
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = 1.2
	light.Color = color or Color3.fromRGB(255, 225, 170)
	light.Enabled = false
	light.Parent = part
	CollectionService:AddTag(part, "NightLight")
	CollectionService:AddTag(light, "NightLight")
end

-- Text on the street-facing (+Z) side of a board.
local function write(board: BasePart, text: string, color: Color3, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- +Z (see ItemBuilders: Back faces the street)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.3
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.9, 0.9)
	label.Position = UDim2.fromScale(0.05, 0.05)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = font or Enum.Font.FredokaOne
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
end

DecorBuilders2.MenuBoard = function(floor, item)
	for _, side in { -1, 1 } do
		Style.Part({ Name = "Leg", Size = Vector3.new(0.4, 6.4, 0.4), CFrame = at(floor, side * 1.6, 3, 0) * CFrame.Angles(math.rad(-8), 0, 0), Color = P.Cocoa, Parent = item })
	end
	local board = Style.Part({ Name = "Board", Size = Vector3.new(3.8, 4.4, 0.25), CFrame = at(floor, 0, 3.6, 0.3) * CFrame.Angles(math.rad(-8), 0, 0), Color = Color3.fromRGB(45, 55, 50), Parent = item })
	Style.Part({ Name = "Frame", Size = Vector3.new(4.2, 4.8, 0.2), CFrame = at(floor, 0, 3.6, 0.2) * CFrame.Angles(math.rad(-8), 0, 0), Color = P.Peach, Parent = item })
	write(board, "TODAY\n🍰 Cakes\n🧁 Cupcakes\n☕ Coffee", P.White, Enum.Font.PermanentMarker)
end

DecorBuilders2.CakeStand = function(floor, item)
	Style.RoundedBox("Table", Vector3.new(3.6, 3, 3.6), at(floor, 0, 1.5, 0), P.Pink, item, 1)
	Style.Cylinder("Plate", 0.2, 3.2, at(floor, 0, 3.1, 0), P.White, item)
	Style.Cylinder("Stem", 1.6, 0.3, at(floor, 0, 4, 0), P.Gold, item)
	Style.Cylinder("Plate2", 0.2, 2.2, at(floor, 0, 4.8, 0), P.White, item)
	Style.Cylinder("Cake", 1, 2.4, at(floor, 0, 3.7, 0), P.Vanilla, item)
	Style.Cylinder("Icing", 0.3, 2.5, at(floor, 0, 4.25, 0), P.HotPink, item)
	for i = 1, 4 do
		local a = i * math.pi / 2
		Style.Ball("Cupcake", 0.6, at(floor, math.cos(a) * 0.65, 5.2, math.sin(a) * 0.65), if i % 2 == 0 then P.Mint else P.Lilac, item)
	end
	local dome = Style.Ball("Dome", 3.4, at(floor, 0, 4.4, 0), P.Glass, item)
	dome.Material = Enum.Material.Glass
	dome.Transparency = 0.75
	dome.CanCollide = false
end

DecorBuilders2.Bookshelf = function(floor, item)
	Style.RoundedBox("Frame", Vector3.new(5, 7, 1.8), at(floor, 0, 3.5, -0.2), P.Cocoa, item, 0.3)
	local colors = { P.HotPink, P.Sky, P.Butter, P.Mint, P.Lilac, P.Peach }
	for row, y in { 1.2, 3.2, 5.2 } do
		Style.Part({ Name = "Shelf", Size = Vector3.new(4.6, 0.2, 1.6), CFrame = at(floor, 0, y - 0.9, 0.1), Color = P.Peach, Parent = item })
		local x = -2
		local k = row
		while x < 1.8 do
			k += 1
			local w = 0.35 + (k % 3) * 0.12
			Style.Part({ Name = "Book", Size = Vector3.new(w, 1.2 + (k % 2) * 0.3, 1.1), CFrame = at(floor, x + w / 2, y - 0.2, 0.3), Color = colors[k % #colors + 1], Parent = item })
			x += w + 0.05
		end
	end
end

DecorBuilders2.Bench = function(floor, item)
	Style.RoundedBox("Seat", Vector3.new(6, 0.5, 1.8), at(floor, 0, 1.7, 0), P.Peach, item, 0.3)
	Style.RoundedBox("Back", Vector3.new(6, 1.6, 0.4), at(floor, 0, 2.9, -0.8), P.Peach, item, 0.2)
	for _, x in { -2.4, 2.4 } do
		Style.Part({ Name = "Leg", Size = Vector3.new(0.4, 1.5, 1.6), CFrame = at(floor, x, 0.75, 0), Color = P.Charcoal, Parent = item })
	end
end

DecorBuilders2.BigPlant = function(floor, item)
	Style.Cylinder("Pot", 2.6, 3.2, at(floor, 0, 1.3, 0), P.Cream, item)
	Style.Cylinder("PotBand", 0.5, 3.3, at(floor, 0, 2.2, 0), P.HotPink, item)
	Style.Cylinder("Trunk", 5, 0.5, at(floor, 0, 5, 0), P.Cocoa, item)
	for i = 1, 6 do
		local a = i * math.pi / 3
		local leaf = Style.Ball("Leaf", 2.4, at(floor, math.cos(a) * 1.5, 7.2 + (i % 2) * 0.6, math.sin(a) * 1.5), if i % 2 == 0 then P.Leaf else P.Grass, item)
		leaf.CanCollide = false
	end
	Style.Ball("Crown", 2.6, at(floor, 0, 8.2, 0), P.Leaf, item).CanCollide = false
end

DecorBuilders2.FloorLamp = function(floor, item)
	Style.Cylinder("Base", 0.4, 2, at(floor, 0, 0.2, 0), P.Charcoal, item)
	Style.Cylinder("Pole", 6.4, 0.3, at(floor, 0, 3.4, 0), P.Gold, item)
	local shade = Style.Cylinder("Shade", 1.8, 2.6, at(floor, 0, 7.2, 0), P.Butter, item)
	shade.CanCollide = false
	local bulb = Style.Ball("Bulb", 0.9, at(floor, 0, 6.6, 0), P.Butter, item)
	bulb.CanCollide = false
	glow(bulb, 16)
end

DecorBuilders2.Fountain = function(floor, item)
	Style.Cylinder("Basin", 1.6, 8, at(floor, 0, 0.8, 0), P.Cream, item)
	local water = Style.Cylinder("Water", 0.2, 7, at(floor, 0, 1.55, 0), P.Sky, item)
	water.Material = Enum.Material.Glass
	water.Transparency = 0.3
	Style.Cylinder("Column", 3, 1, at(floor, 0, 3, 0), P.Cream, item)
	Style.Cylinder("Bowl", 0.5, 3, at(floor, 0, 4.6, 0), P.Pink, item)
	local top = Style.Ball("Spout", 0.9, at(floor, 0, 5.2, 0), P.Sky, item)
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
	spray.Size = NumberSequence.new(0.35, 0.15)
	spray.Lifetime = NumberRange.new(0.8, 1.1)
	spray.Rate = 30
	spray.Speed = NumberRange.new(6, 8)
	spray.SpreadAngle = Vector2.new(20, 20)
	spray.Acceleration = Vector3.new(0, -18, 0)
	spray.LightInfluence = 0.5
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = top
end

DecorBuilders2.Piano = function(floor, item)
	Style.RoundedBox("Body", Vector3.new(6, 4.4, 2.2), at(floor, 0, 2.6, -0.4), P.Charcoal, item, 0.3)
	Style.Part({ Name = "Keys", Size = Vector3.new(5.4, 0.25, 1), CFrame = at(floor, 0, 2.7, 1.1), Color = P.White, Parent = item })
	for x = -2.4, 2.4, 0.8 do
		Style.Part({ Name = "BlackKey", Size = Vector3.new(0.3, 0.15, 0.6), CFrame = at(floor, x, 2.88, 0.95), Color = Color3.fromRGB(20, 20, 25), Parent = item })
	end
	for _, x in { -2.6, 2.6 } do
		Style.Part({ Name = "Leg", Size = Vector3.new(0.5, 2.4, 0.5), CFrame = at(floor, x, 1.2, 1.2), Color = P.Charcoal, Parent = item })
	end
	Style.RoundedBox("Stool", Vector3.new(2.4, 1.8, 1.4), at(floor, 0, 0.9, 2.8), P.HotPink, item, 0.4)
	Style.Part({ Name = "Music", Size = Vector3.new(1.6, 1.2, 0.05), CFrame = at(floor, 0, 5.4, 0.6) * CFrame.Angles(math.rad(-12), 0, 0), Color = P.White, Parent = item })
end

DecorBuilders2.CupcakeSign = function(floor, item)
	Style.Cylinder("Post", 6, 0.4, at(floor, 0, 3, 0), P.White, item)
	Style.Cylinder("Base", 0.4, 2, at(floor, 0, 0.2, 0), P.White, item)
	local wrapper = Style.Cylinder("Wrapper", 1.6, 2.4, at(floor, 0, 6.8, 0), P.Pink, item)
	local frosting = Style.Ball("Frosting", 3, at(floor, 0, 8.2, 0), P.HotPink, item)
	local cherry = Style.Ball("Cherry", 0.9, at(floor, 0, 9.9, 0), Color3.fromRGB(235, 50, 70), item)
	for _, part in { wrapper, frosting, cherry } do
		part.CanCollide = false
	end
	glow(frosting, 18, Color3.fromRGB(255, 160, 200))
	CollectionService:AddTag(cherry, "NightLight")
end

DecorBuilders2.FlowerCart = function(floor, item)
	Style.RoundedBox("Cart", Vector3.new(5, 2, 3), at(floor, 0, 2.2, 0), P.Mint, item, 0.4)
	for _, x in { -1.8, 1.8 } do
		Style.Cylinder("Wheel", 0.4, 2, at(floor, x, 1, 1.6) * CFrame.Angles(0, 0, math.rad(90)), P.Cocoa, item)
	end
	Style.Cylinder("Handle", 4, 0.25, at(floor, 0, 3, -2.1) * CFrame.Angles(0, 0, math.rad(90)), P.Cocoa, item)
	local colors = { P.HotPink, P.Butter, P.Lilac, P.Sky, P.White, P.Peach }
	for i = 0, 11 do
		local x, z = -1.9 + (i % 4) * 1.25, -0.9 + math.floor(i / 4) * 0.9
		Style.Ball("Bloom", 0.9, at(floor, x, 3.6 + (i % 3) * 0.2, z), colors[i % #colors + 1], item).CanCollide = false
	end
	Style.Ball("Leaves", 1.8, at(floor, 0, 3.3, 0), P.Leaf, item).CanCollide = false
end

DecorBuilders2.Sofa = function(floor, item)
	Style.RoundedBox("Seat", Vector3.new(7, 1.4, 3), at(floor, 0, 1.2, 0.2), P.Lilac, item, 0.6)
	Style.RoundedBox("Back", Vector3.new(7, 2.6, 1), at(floor, 0, 2.4, -1.2), P.Lilac, item, 0.4)
	for _, x in { -3.3, 3.3 } do
		Style.RoundedBox("Arm", Vector3.new(0.8, 2, 3.2), at(floor, x, 1.6, 0), P.Lilac, item, 0.35)
	end
	for _, x in { -1.6, 1.6 } do
		Style.RoundedBox("Cushion", Vector3.new(1.6, 1.4, 0.5), at(floor, x, 2.5, -0.5), if x < 0 then P.Butter else P.Mint, item, 0.25)
	end
end

return DecorBuilders2
