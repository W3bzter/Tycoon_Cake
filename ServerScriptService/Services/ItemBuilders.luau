--!strict
-- Geometry for each upgrade, keyed by upgrade Id. Each builder fills `item`
-- (a Model) using plot-local coordinates relative to `floor` (top of the plot floor).
-- Part names BakingPipeline depends on: IngredientCrate.Crate, Mixer.Body,
-- Oven(2).Body + Door, DisplayCounter.Counter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Recipes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Recipes"))
local Assets = require(script.Parent.Assets)
local Style = require(script.Parent.Style)

local P = Style.Palette
local ItemBuilders: { [string]: (floor: CFrame, item: Model) -> () } = {}

local WALL_H = 14
local FACADE_Z = 23.5

local function at(floor: CFrame, x: number, y: number, z: number): CFrame
	return floor * CFrame.new(x, y, z)
end

ItemBuilders.Walls = function(floor, item)
	local wallColor = P.Vanilla
	-- Back and side walls.
	Style.Part({ Name = "BackWall", Size = Vector3.new(80, WALL_H, 1), CFrame = at(floor, 0, WALL_H / 2, -39.5), Color = wallColor, Parent = item })
	for _, x in { -39.5, 39.5 } do
		Style.Part({ Name = "SideWall", Size = Vector3.new(1, WALL_H, 64), CFrame = at(floor, x, WALL_H / 2, -8), Color = wallColor, Parent = item })
	end

	-- Front facade: low band, top band, pillars, glass windows, door gap at x -6..6.
	for _, side in { -1, 1 } do
		Style.Part({ Name = "FacadeLow", Size = Vector3.new(34, 3, 1), CFrame = at(floor, side * 23, 1.5, FACADE_Z), Color = P.Pink, Parent = item })
		for _, x in { 7, 23, 39 } do
			Style.RoundedBox("Pillar", Vector3.new(2, 7, 1.6), at(floor, side * x, 6.5, FACADE_Z), P.Pink, item, 0.5)
		end
		for _, x in { 15, 31 } do
			Style.Part({
				Name = "Window",
				Size = Vector3.new(14, 7, 0.3),
				CFrame = at(floor, side * x, 6.5, FACADE_Z),
				Color = P.Glass,
				Material = Enum.Material.Glass,
				Transparency = 0.55,
				Parent = item,
			})
			Style.Trim("Sill", Vector3.new(14.6, 0.6, 1.8), at(floor, side * x, 3.2, FACADE_Z), P.Butter, item)
		end
	end
	Style.Part({ Name = "FacadeTop", Size = Vector3.new(80, 4, 1), CFrame = at(floor, 0, 12, FACADE_Z), Color = P.Pink, Parent = item })

	-- Cornice and baseboard bands for a chunky outline.
	Style.Trim("Cornice", Vector3.new(81.5, 1.2, 2.2), at(floor, 0, WALL_H + 0.3, FACADE_Z), P.HotPink, item)
	Style.Trim("CorniceBack", Vector3.new(81.5, 1.2, 2.2), at(floor, 0, WALL_H + 0.3, -39.5), P.HotPink, item)
	for _, x in { -39.5, 39.5 } do
		Style.Part({ Name = "CorniceSide", Size = Vector3.new(2.2, 1.2, 64), CFrame = at(floor, x, WALL_H + 0.3, -8), Color = P.HotPink, Parent = item })
		Style.Part({ Name = "Baseboard", Size = Vector3.new(1.6, 1, 64), CFrame = at(floor, x, 0.5, -8), Color = P.HotPink, Parent = item })
	end
	Style.Part({ Name = "Baseboard", Size = Vector3.new(80, 1, 1.6), CFrame = at(floor, 0, 0.5, -39.5), Color = P.HotPink, Parent = item })

	-- Shop sign above the door.
	local sign = Style.RoundedBox("ShopSign", Vector3.new(22, 4.5, 1), at(floor, 0, 12, FACADE_Z + 1), P.White, item, 0.5)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- +Z, towards the street
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = P.HotPink
	label.Text = "🧁 BAKERY 🧁"
	label.Parent = gui
	local glow = Style.Part({ Name = "SignGlow", Size = Vector3.new(23, 5.5, 0.4), CFrame = at(floor, 0, 12, FACADE_Z + 0.4), Color = P.Butter, Parent = item })
	glow.Material = Enum.Material.Neon
end

-- Pantry bin positions on the shelves (x, shelf-top y), in Recipes.IngredientOrder.
local BIN_SPOTS = {
	Flour = { -32, 0.4 },
	Eggs = { -28, 0.4 },
	Sugar = { -24, 0.4 },
	Butter = { -30.5, 3.3 },
	Milk = { -25.5, 3.3 },
	Strawberries = { -30.5, 6.2 },
	Chocolate = { -25.5, 6.2 },
}

ItemBuilders.IngredientCrate = function(floor, item)
	-- Pantry shelf against the back wall, one bin per ingredient. BakingPipeline
	-- adds a prompt to each Bins/<Ingredient>/Bin part and hides locked ones.
	local cabinet = Style.RoundedBox("Crate", Vector3.new(13, 9, 3), at(floor, -28, 4.5, -37.4), P.Peach, item, 0.5)
	for i, y in { 3.1, 6 } do
		Style.Trim(`Shelf{i}`, Vector3.new(13.4, 0.4, 3.8), at(floor, -28, y, -36.4), P.Vanilla, item)
	end

	local bins = Instance.new("Folder")
	bins.Name = "Bins"
	for _, ingredient in Recipes.IngredientOrder do
		local spot = BIN_SPOTS[ingredient]
		local info = Recipes.Ingredients[ingredient]
		local binModel = Instance.new("Model")
		binModel.Name = ingredient
		local binPart = Style.RoundedBox("Bin", Vector3.new(3.4, 0.8, 2.6), at(floor, spot[1], spot[2] + 0.4, -35.6), P.Cream, binModel, 0.4)
		local art = Assets.Clone("Ingredients", ingredient)
		Assets.Anchor(art, binPart.CFrame * CFrame.new(0, 0.4, 0), binModel)
		Style.Billboard(binPart, { `{info.Icon} {info.DisplayName}` }, {
			Name = "BinLabel",
			Width = 3.2,
			Height = 0.8,
			-- In front of the shelf edge and below the shelf above, so nothing clips it.
			Offset = Vector3.new(0, 1.5, 2.4),
			MaxDistance = 28,
			Stroke = P.DeepMint,
		})
		binModel.Parent = bins
	end
	bins.Parent = item
	Style.MachineSign(item, cabinet, "🥚", "Pantry")
end

ItemBuilders.Mixer = function(floor, item)
	local body = Style.RoundedBox("Body", Vector3.new(5, 3.5, 5), at(floor, -12, 1.75, -35), P.Mint, item, 1)
	Style.RoundedBox("Column", Vector3.new(1.4, 6, 1.4), at(floor, -12, 6.5, -37), P.Mint, item, 0.6)
	Style.RoundedBox("Arm", Vector3.new(1.4, 1.4, 4), at(floor, -12, 9, -35.7), P.Mint, item, 0.6)
	Style.Cylinder("Bowl", 2.4, 4.2, at(floor, -12, 4.7, -35), P.Steel, item).Material = Enum.Material.Metal
	Style.Cylinder("Whisk", 3, 0.4, at(floor, -12, 7, -35), P.Steel, item)
	Style.Ball("Knob", 0.8, at(floor, -12, 2, -32.4), P.HotPink, item)
	Style.MachineSign(item, body, "🥣", "Mixer")
end

local function buildOven(x: number)
	return function(floor: CFrame, item: Model)
		local body = Style.RoundedBox("Body", Vector3.new(8, 7, 5), at(floor, x, 3.5, -35), P.Peach, item, 1)
		Style.Trim("DoorFrame", Vector3.new(6.4, 4.4, 0.4), at(floor, x, 3.2, -32.4), P.Cream, item)
		Style.Part({
			Name = "Door",
			Size = Vector3.new(5.4, 3.4, 0.3),
			CFrame = at(floor, x, 3.2, -32.2),
			Color = Color3.fromRGB(60, 40, 40),
			Material = Enum.Material.Glass,
			Transparency = 0.2,
			Parent = item,
		})
		for i = -1, 1 do
			Style.Ball("Knob", 0.7, at(floor, x + i * 1.6, 6.1, -32.4), P.HotPink, item)
		end
		Style.Cylinder("Chimney", 3, 1.2, at(floor, x + 2.5, 8.5, -36.5), P.Steel, item).Material = Enum.Material.Metal
		Style.MachineSign(item, body, "🔥", "Oven")
	end
end
ItemBuilders.Oven = buildOven(6)
ItemBuilders.Oven2 = buildOven(20)

local function buildCounter(x: number, stripe: Color3)
	return function(floor: CFrame, item: Model)
		local counter = Style.RoundedBox("Counter", Vector3.new(20, 4, 4), at(floor, x, 2, 32), P.White, item, 0.8)
		Style.Trim("Kick", Vector3.new(20.4, 0.8, 4.4), at(floor, x, 0.4, 32), P.HotPink, item)
		for i = 0, 4 do
			Style.Part({
				Name = "Stripe",
				Size = Vector3.new(1.6, 3, 0.2),
				CFrame = at(floor, x - 8 + i * 4, 2.3, 34.05),
				Color = stripe,
				Parent = item,
			})
		end
		Style.MachineSign(item, counter, "🍰", "Display Counter")
	end
end
ItemBuilders.DisplayCounter = buildCounter(20, P.Pink)
ItemBuilders.DisplayCounter2 = buildCounter(-20, P.Mint)

ItemBuilders.Plants = function(floor, item)
	local spots = { { -10, 27 }, { 10, 27 }, { -36, -2 }, { 36, -8 } }
	for _, s in spots do
		local x, z = s[1], s[2]
		Style.Cylinder("Pot", 2.2, 2.6, at(floor, x, 1.1, z), P.Peach, item)
		Style.Ball("Leaves", 3, at(floor, x, 3, z), P.Leaf, item)
		Style.Ball("Flower", 0.9, at(floor, x + 0.8, 4.2, z + 0.5), P.HotPink, item)
		Style.Ball("Flower", 0.9, at(floor, x - 0.7, 4.1, z - 0.4), P.Butter, item)
	end
end

ItemBuilders.Awning = function(floor, item)
	Style.StripedAwning(78, 6, at(floor, 0, 10.2, FACADE_Z + 0.6), P.HotPink, P.White, item)
end

ItemBuilders.Oven3 = buildOven(34)

-- Helpers for the Phase D items ------------------------------------------------------

local DECK_Y = 14.5

-- A text panel facing +Z (into the room / towards the street).
local function panel(name: string, size: Vector3, cf: CFrame, color: Color3, text: string, textColor: Color3, parent: Instance): Part
	local board = Style.RoundedBox(name, size, cf, color, parent, math.min(0.4, size.Z / 2))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.9, 0.85)
	label.Position = UDim2.fromScale(0.05, 0.075)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = textColor
	label.Text = text
	label.Parent = gui
	return board
end

-- Flat conveyor belt between two plot-local points on the floor (axis-aligned).
local function belt(name: string, from: Vector3, to: Vector3, floor: CFrame, parent: Instance): Part
	local mid = (from + to) / 2
	local delta = to - from
	local size = Vector3.new(math.max(math.abs(delta.X), 2), 0.6, math.max(math.abs(delta.Z), 2))
	local b = Style.Part({ Name = name, Size = size, CFrame = at(floor, mid.X, 0.3, mid.Z), Color = P.Charcoal, Parent = parent })
	-- Side rails
	local alongX = math.abs(delta.X) >= math.abs(delta.Z)
	for _, s in { -1, 1 } do
		local offset = if alongX then Vector3.new(0, 0.45, s * (size.Z / 2)) else Vector3.new(s * (size.X / 2), 0.45, 0)
		Style.Part({
			Name = "Rail",
			Size = if alongX then Vector3.new(size.X, 0.3, 0.3) else Vector3.new(0.3, 0.3, size.Z),
			CFrame = at(floor, mid.X + offset.X, offset.Y + 0.3, mid.Z + offset.Z),
			Color = P.Butter,
			Parent = parent,
		})
	end
	return b
end

local function recipePoster(x: number, cakeName: string, icon: string, color: Color3)
	return function(floor: CFrame, item: Model)
		Style.RoundedBox("Frame", Vector3.new(7, 5, 0.4), at(floor, x, 11, -38.8), P.Cocoa, item, 0.3)
		panel("Poster", Vector3.new(6.2, 4.2, 0.3), at(floor, x, 11, -38.5), color, `{icon}\n{cakeName}`, P.Cocoa, item)
	end
end
ItemBuilders.RecipeChocolate = recipePoster(-6, "Chocolate", "🍫", P.Peach)
ItemBuilders.RecipeStrawberry = recipePoster(-16, "Strawberry", "🍓", P.Pink)
ItemBuilders.RecipeRainbow = recipePoster(26, "Rainbow", "🌈", P.Lilac)

ItemBuilders.Seating = function(floor, item)
	for _, spot in { { -28, 6 }, { -16, 6 }, { -28, 16 }, { -16, 16 } } do
		local x, z = spot[1], spot[2]
		Style.Cylinder("TableTop", 0.4, 4.4, at(floor, x, 3, z), P.White, item)
		Style.Cylinder("TableLeg", 2.8, 0.6, at(floor, x, 1.4, z), P.HotPink, item)
		for _, dx in { -3, 3 } do
			Style.RoundedBox("Chair", Vector3.new(1.8, 1.8, 1.8), at(floor, x + dx, 0.9, z), P.Mint, item, 0.6)
		end
	end
end

ItemBuilders.StreetSign = function(floor, item)
	Style.Cylinder("Post", 9, 0.8, at(floor, -36, 4.5, 36), P.White, item)
	panel("Board", Vector3.new(8, 4, 0.6), at(floor, -36, 9, 36), P.Butter, "🎂 FRESH CAKES!", P.HotPink, item)
end

ItemBuilders.RadioAd = function(floor, item)
	Style.Cylinder("Pole", 5, 0.5, at(floor, 34, 2.5, 33), P.Charcoal, item)
	local radio = Style.RoundedBox("Radio", Vector3.new(4, 2.6, 2), at(floor, 34, 6, 33), P.Sky, item, 0.6)
	Style.Cylinder("Speaker", 0.3, 1.8, at(floor, 33.2, 6, 34.05) * CFrame.Angles(0, math.rad(90), math.rad(-90)), P.Charcoal, item)
	for i, offset in { Vector3.new(-1, 3.4, 0), Vector3.new(1.2, 4.2, 0) } do
		local note = Style.Ball(`Note{i}`, 0.7, at(floor, 34 + offset.X, 6 + offset.Y - 3, 33), P.HotPink, item)
		note.Material = Enum.Material.Neon
	end
	Style.MachineSign(item, radio, "📻", "Radio Ad")
end

ItemBuilders.FasterOvens1 = function(floor, item)
	for _, x in { 6, 20 } do
		local dial = Style.Part({
			Name = "Gauge",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 2.4, 2.4),
			CFrame = at(floor, x, 10.5, -38.8) * CFrame.Angles(0, math.rad(90), 0),
			Color = P.White,
			Parent = item,
		})
		Style.Part({ Name = "Needle", Size = Vector3.new(0.15, 1, 0.1), CFrame = at(floor, x + 0.3, 10.7, -38.6) * CFrame.Angles(0, 0, math.rad(-35)), Color = P.HotPink, Parent = dial })
	end
end
ItemBuilders.FasterOvens2 = function(floor, item)
	Style.Part({ Name = "Gauge", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.4, 2.4), CFrame = at(floor, 34, 10.5, -38.8) * CFrame.Angles(0, math.rad(90), 0), Color = P.White, Parent = item })
	for _, x in { 6, 20, 34 } do
		local fan = Style.Cylinder("TurboFan", 0.8, 2, at(floor, x - 2.5, 8.2, -36.5), P.Sky, item)
		fan.Material = Enum.Material.Neon
	end
end
ItemBuilders.FasterOvens3 = function(floor, item)
	for _, x in { 6, 20, 34 } do
		local flame = Style.Ball("TurboFlame", 1.2, at(floor, x + 2.5, 10.5, -36.5), Color3.fromRGB(255, 140, 60), item)
		flame.Material = Enum.Material.Neon
	end
end

ItemBuilders.BigMixer = function(floor, item)
	local bowl = Style.Cylinder("BigBowl", 3, 5.6, at(floor, -12, 5.3, -35), P.Steel, item)
	bowl.Material = Enum.Material.Metal
	Style.Billboard(bowl, { "XL" }, { Name = "XL", Width = 1.6, Height = 1, Offset = Vector3.new(0, 2.4, 0), MaxDistance = 40, Stroke = P.DeepMint })
end

ItemBuilders.GoldenOven = function(floor, item)
	Style.Trim("Crown", Vector3.new(8.8, 0.8, 5.8), at(floor, 6, 7.3, -35), P.Gold, item)
	local star = Style.Ball("Star", 1.4, at(floor, 6, 9, -35), P.Gold, item)
	star.Material = Enum.Material.Neon
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = P.Gold
	sparkle.Parent = star
end

ItemBuilders.CakeCharm = function(floor, item)
	Style.Part({ Name = "Chain", Size = Vector3.new(0.15, 2.4, 0.15), CFrame = at(floor, 20, 9.4, 32), Color = P.Gold, Parent = item })
	local charm = Style.Ball("Charm", 1.4, at(floor, 20, 7.6, 32), Color3.fromRGB(80, 220, 120), item)
	charm.Material = Enum.Material.Neon
end

ItemBuilders.GoldenShopfront = function(floor, item)
	Style.Trim("GoldCornice", Vector3.new(82, 1.4, 2.6), at(floor, 0, WALL_H + 0.4, FACADE_Z), P.Gold, item)
	for _, x in { -7, 7 } do
		Style.RoundedBox("GoldPillar", Vector3.new(2.4, 7.2, 2), at(floor, x, 6.5, FACADE_Z), P.Gold, item, 0.6)
	end
	local glow = Style.Part({ Name = "GoldGlow", Size = Vector3.new(23.4, 5.9, 0.3), CFrame = at(floor, 0, 12, FACADE_Z + 0.25), Color = P.Gold, Parent = item })
	glow.Material = Enum.Material.Neon
end

-- Second floor: a deck over the dining area at wall height, reached by stairs on
-- the right. The stairwell (x 31..39, z -4..24) is left open.
ItemBuilders.SecondFloor = function(floor, item)
	local deckColor = P.Peach
	Style.Part({ Name = "Deck", Size = Vector3.new(71, 1, 36), CFrame = at(floor, -4.5, DECK_Y - 0.5, 6), Color = deckColor, Material = Enum.Material.WoodPlanks, Parent = item })
	Style.Part({ Name = "Landing", Size = Vector3.new(9, 1, 8), CFrame = at(floor, 35.5, DECK_Y - 0.5, -8), Color = deckColor, Material = Enum.Material.WoodPlanks, Parent = item })
	local steps = 16
	local rise, run = DECK_Y / steps, 1.5
	for i = 1, steps do
		local h = rise * i
		Style.Part({
			Name = "Step",
			Size = Vector3.new(8, h, run),
			CFrame = at(floor, 35, h / 2, 20 - (i - 0.5) * run),
			Color = if i % 2 == 0 then P.Cream else P.Vanilla,
			Parent = item,
		})
	end
	-- Railings: back edge of the deck, and along the stairwell.
	Style.Part({ Name = "RailBack", Size = Vector3.new(80, 0.5, 0.5), CFrame = at(floor, 0, DECK_Y + 3, -11.8), Color = P.White, Parent = item })
	Style.Part({ Name = "RailWell", Size = Vector3.new(0.5, 0.5, 28), CFrame = at(floor, 30.8, DECK_Y + 3, 10), Color = P.White, Parent = item })
	for x = -38, 30, 6 do
		Style.Part({ Name = "Baluster", Size = Vector3.new(0.4, 3, 0.4), CFrame = at(floor, x, DECK_Y + 1.5, -11.8), Color = P.White, Parent = item })
	end
	for z = -4, 24, 6 do
		Style.Part({ Name = "Baluster", Size = Vector3.new(0.4, 3, 0.4), CFrame = at(floor, 30.8, DECK_Y + 1.5, z), Color = P.White, Parent = item })
	end
	-- Rooftop café tables.
	for _, spot in { { -30, 0 }, { -30, 14 }, { 10, 2 }, { 20, 14 } } do
		Style.Cylinder("TableTop", 0.4, 4.4, at(floor, spot[1], DECK_Y + 3, spot[2]), P.White, item)
		Style.Cylinder("TableLeg", 2.8, 0.6, at(floor, spot[1], DECK_Y + 1.4, spot[2]), P.Sky, item)
		Style.Cylinder("Umbrella", 0.4, 6, at(floor, spot[1], DECK_Y + 7, spot[2]), P.HotPink, item)
		Style.Cylinder("Pole", 4, 0.3, at(floor, spot[1], DECK_Y + 5, spot[2]), P.White, item)
	end
end

ItemBuilders.VIPLounge = function(floor, item)
	Style.Part({ Name = "Carpet", Size = Vector3.new(18, 0.1, 12), CFrame = at(floor, -18, DECK_Y + 0.05, 10), Color = Color3.fromRGB(200, 40, 70), Parent = item })
	for _, x in { -24, -12 } do
		local sofa = Style.RoundedBox("Sofa", Vector3.new(6, 2, 3), at(floor, x, DECK_Y + 1, 14), P.Lilac, item, 0.8)
		Style.RoundedBox("SofaBack", Vector3.new(6, 2.6, 1), at(floor, x, DECK_Y + 2.3, 15.2), P.Lilac, sofa, 0.4)
	end
	for _, x in { -27, -9 } do
		Style.Cylinder("RopePost", 3, 0.5, at(floor, x, DECK_Y + 1.5, 4.5), P.Gold, item)
		Style.Ball("RopeKnob", 0.8, at(floor, x, DECK_Y + 3.2, 4.5), P.Gold, item)
	end
	Style.Part({ Name = "Rope", Size = Vector3.new(18, 0.3, 0.3), CFrame = at(floor, -18, DECK_Y + 2.6, 4.5), Color = Color3.fromRGB(200, 40, 70), Parent = item })
	local crown = panel("VIPSign", Vector3.new(6, 2.4, 0.4), at(floor, -18, DECK_Y + 6, 16), P.Gold, "👑 VIP", P.White, item)
	Style.MachineSign(item, crown, "👑", "VIP Lounge")
end

-- Automation: production line 1 (row at z -18) --------------------------------------------

ItemBuilders.IngredientConveyor = function(floor, item)
	local hopper = Style.RoundedBox("Hopper", Vector3.new(4, 3, 4), at(floor, -24, 1.5, -18), P.Lilac, item, 0.8)
	Style.Trim("HopperRim", Vector3.new(4.6, 0.5, 4.6), at(floor, -24, 3.2, -18), P.White, item)
	local tube = Style.Part({
		Name = "Tube",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(13, 1.2, 1.2),
		CFrame = at(floor, -26, 5, -26.5) * CFrame.Angles(0, math.rad(90), 0),
		Color = P.Sky,
		Transparency = 0.3,
		Parent = item,
	})
	tube.Material = Enum.Material.Glass
	belt("Belt", Vector3.new(-22, 0, -18), Vector3.new(-14.5, 0, -18), floor, item)
	Style.MachineSign(item, hopper, "📦", "Line 1 Hopper")
end

ItemBuilders.AutoMixer = function(floor, item)
	local body = Style.RoundedBox("Body", Vector3.new(5, 4, 5), at(floor, -12, 2, -18), P.Lilac, item, 1)
	Style.Cylinder("Bowl", 2.2, 4, at(floor, -12, 5.1, -18), P.Steel, item).Material = Enum.Material.Metal
	Style.Ball("Light", 0.8, at(floor, -12, 3, -15.4), P.DeepMint, item).Material = Enum.Material.Neon
	belt("Belt", Vector3.new(-9.5, 0, -18), Vector3.new(1, 0, -18), floor, item)
	Style.MachineSign(item, body, "🤖", "Auto-Mixer")
end

ItemBuilders.AutoOven = function(floor, item)
	local body = Style.RoundedBox("Body", Vector3.new(6, 6, 5), at(floor, 4, 3, -18), P.Lilac, item, 1)
	Style.Part({
		Name = "Door",
		Size = Vector3.new(4, 2.6, 0.3),
		CFrame = at(floor, 4, 3, -15.4),
		Color = Color3.fromRGB(60, 40, 40),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Parent = item,
	})
	Style.Cylinder("Chimney", 2.4, 1, at(floor, 5.5, 7, -19), P.Steel, item)
	Style.MachineSign(item, body, "🤖", "Auto-Oven")
end

ItemBuilders.CounterConveyor = function(floor, item)
	belt("Belt", Vector3.new(4, 0, -15), Vector3.new(4, 0, 27), floor, item)
	belt("BeltTurn", Vector3.new(5, 0, 27), Vector3.new(9, 0, 27), floor, item)
	local chute = Style.RoundedBox("Chute", Vector3.new(2.4, 3, 2.4), at(floor, 9, 1.5, 27.5), P.Lilac, item, 0.6)
	Style.MachineSign(item, chute, "➡️", "To Counter")
end

ItemBuilders.AutoRestock = function(floor, item)
	local rack = Style.RoundedBox("Rack", Vector3.new(8, 6, 3), at(floor, 14, 3, 20.5), P.Lilac, item, 0.6)
	for i, y in { 2, 4 } do
		Style.Trim(`Shelf{i}`, Vector3.new(8.4, 0.3, 3.4), at(floor, 14, y, 20.2), P.White, item)
	end
	-- Marker parts where stored cakes are shown (3 per shelf).
	local slots = Instance.new("Folder")
	slots.Name = "StorageSlots"
	local n = 0
	for _, y in { 2.15, 4.15 } do
		for _, dx in { -2.5, 0, 2.5 } do
			n += 1
			Style.Part({ Name = `Store{n}`, Size = Vector3.new(1.6, 0.1, 1.6), CFrame = at(floor, 14 + dx, y, 19.6), Transparency = 1, CanCollide = false, Parent = slots })
		end
	end
	slots.Parent = item
	Style.MachineSign(item, rack, "🗄️", "Restock Rack")
end

local function productionUnit(z: number, label: string)
	return function(floor: CFrame, item: Model)
		local body = Style.RoundedBox("Body", Vector3.new(10, 6, 5), at(floor, 20, 3, z), P.Lilac, item, 1)
		Style.Part({
			Name = "Door",
			Size = Vector3.new(4, 2.6, 0.3),
			CFrame = at(floor, 22, 3, z + 2.6),
			Color = Color3.fromRGB(60, 40, 40),
			Material = Enum.Material.Glass,
			Transparency = 0.2,
			Parent = item,
		})
		Style.RoundedBox("Hopper", Vector3.new(3, 2, 3), at(floor, 17, 7, z), P.White, item, 0.6)
		local panelPart = panel("Panel", Vector3.new(2.6, 2, 0.3), at(floor, 16.5, 3.4, z + 2.6), P.Charcoal, "🏭", P.White, item)
		panelPart:SetAttribute("Role", "RecipePanel")
		Style.Cylinder("Chimney", 2.4, 1, at(floor, 23.5, 7, z - 1), P.Steel, item)
		Style.MachineSign(item, body, "🏭", label)
	end
end
ItemBuilders.ProductionLine2 = productionUnit(-4, "Production Line 2")
ItemBuilders.ProductionLine3 = productionUnit(9, "Production Line 3")

return ItemBuilders
