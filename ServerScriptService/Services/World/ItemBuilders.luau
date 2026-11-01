--!strict
-- Geometry for each upgrade, keyed by upgrade Id. Each builder fills `item`
-- (a Model) using plot-local coordinates relative to `floor` (top of the plot floor).
-- Part names BakingPipeline depends on: IngredientCrate.Crate, Mixer.Body,
-- Oven(2).Body + Door, DisplayCounter.Counter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Recipes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Recipes"))
local Services = script:FindFirstAncestor("Services") :: Folder
local Assets = require(Services.World.Assets)
local Style = require(Services.World.Style)

local P = Style.Palette
local ItemBuilders: { [string]: (floor: CFrame, item: Model) -> () } = {}

local B = Config.Building -- building shell size (ConfigParts/Build)
local WALL_H = B.WallHeight
local FACADE_Z = B.FacadeZ
local BACK_Z = B.BackZ + 0.5 -- back wall centre
local SIDE_X = B.HalfX - 0.5 -- side wall centres (±)
local DECK_Y = B.DeckY

local function at(floor: CFrame, x: number, y: number, z: number): CFrame
	return floor * CFrame.new(x, y, z)
end

ItemBuilders.Walls = function(floor, item)
	local wallColor = P.Vanilla
	local width = B.HalfX * 2
	local depth = FACADE_Z - B.BackZ -- side walls run from the back wall to the facade
	local midZ = (FACADE_Z + B.BackZ) / 2
	-- Back wall (with the Factory Annex doorway) and side walls.
	local A = B.Annex
	local doorH = 10
	local function backPiece(name: string, x0: number, x1: number, y0: number, y1: number, depth: number?): Part
		return Style.Part({ Name = name, Size = Vector3.new(x1 - x0, y1 - y0, depth or 1), CFrame = at(floor, (x0 + x1) / 2, (y0 + y1) / 2, BACK_Z), Color = wallColor, Parent = item })
	end
	backPiece("BackWall", -B.HalfX, A.DoorX0, 0, WALL_H)
	backPiece("BackWall", A.DoorX1, B.HalfX, 0, WALL_H)
	backPiece("BackWallLintel", A.DoorX0, A.DoorX1, doorH, WALL_H)
	-- Seals the doorway until the annex is bought (TycoonButtons hides HideWhenOwned parts).
	local block = backPiece("AnnexDoorBlock", A.DoorX0, A.DoorX1, 0, doorH, 0.8)
	block.Color = P.Cream
	block:SetAttribute("HideWhenOwned", "FactoryAnnex")
	local blockGui = Instance.new("SurfaceGui")
	blockGui.Face = Enum.NormalId.Back -- +Z, into the bakery
	blockGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	blockGui.PixelsPerStud = 30
	blockGui.LightInfluence = 0
	blockGui.Parent = block
	local blockText = Instance.new("TextLabel")
	blockText.Size = UDim2.fromScale(1, 0.4)
	blockText.Position = UDim2.fromScale(0, 0.3)
	blockText.BackgroundTransparency = 1
	blockText.TextScaled = true
	blockText.Font = Enum.Font.FredokaOne
	blockText.TextColor3 = P.HotPink
	blockText.Text = "🔒 Factory Annex\n(Build shop → Upgrades)"
	blockText.Parent = blockGui
	for _, x in { -SIDE_X, SIDE_X } do
		Style.Part({ Name = "SideWall", Size = Vector3.new(1, WALL_H, depth), CFrame = at(floor, x, WALL_H / 2, midZ), Color = wallColor, Parent = item })
	end

	-- Front facade on each side of the doorway: low band, pillars, glass windows
	-- (the facade from the door edge to the side wall is split into equal bays).
	local inner, outer = B.DoorHalf + 1, SIDE_X
	local bays = math.max(1, math.floor((outer - inner) / 16))
	local bay = (outer - inner) / bays
	local topY = 10 -- windows and the doorway are 10 studs tall; the band above fills to the roof
	for _, side in { -1, 1 } do
		Style.Part({ Name = "FacadeLow", Size = Vector3.new(outer - B.DoorHalf, 3, 1), CFrame = at(floor, side * (outer + B.DoorHalf) / 2, 1.5, FACADE_Z), Color = P.Pink, Parent = item })
		for i = 0, bays do
			Style.RoundedBox("Pillar", Vector3.new(2, 7, 1.6), at(floor, side * (inner + i * bay), 6.5, FACADE_Z), P.Pink, item, 0.5)
		end
		for i = 1, bays do
			local x = side * (inner + (i - 0.5) * bay)
			Style.Part({
				Name = "Window",
				Size = Vector3.new(bay - 2, 7, 0.3),
				CFrame = at(floor, x, 6.5, FACADE_Z),
				Color = P.Glass,
				Material = Enum.Material.Glass,
				Transparency = 0.55,
				Parent = item,
			})
			Style.Trim("Sill", Vector3.new(bay - 1.4, 0.6, 1.8), at(floor, x, 3.2, FACADE_Z), P.Butter, item)
		end
	end
	Style.Part({ Name = "FacadeTop", Size = Vector3.new(width, WALL_H - topY, 1), CFrame = at(floor, 0, (WALL_H + topY) / 2, FACADE_Z), Color = P.Pink, Parent = item })

	-- Cornice and baseboard bands for a chunky outline.
	Style.Trim("Cornice", Vector3.new(width + 1.5, 1.2, 2.2), at(floor, 0, WALL_H + 0.3, FACADE_Z), P.HotPink, item)
	Style.Trim("CorniceBack", Vector3.new(width + 1.5, 1.2, 2.2), at(floor, 0, WALL_H + 0.3, BACK_Z), P.HotPink, item)
	for _, x in { -SIDE_X, SIDE_X } do
		Style.Part({ Name = "CorniceSide", Size = Vector3.new(2.2, 1.2, depth), CFrame = at(floor, x, WALL_H + 0.3, midZ), Color = P.HotPink, Parent = item })
		Style.Part({ Name = "Baseboard", Size = Vector3.new(1.6, 1, depth), CFrame = at(floor, x, 0.5, midZ), Color = P.HotPink, Parent = item })
	end
	for _, span in { { -B.HalfX, A.DoorX0 }, { A.DoorX1, B.HalfX } } do
		Style.Part({ Name = "Baseboard", Size = Vector3.new(span[2] - span[1], 1, 1.6), CFrame = at(floor, (span[1] + span[2]) / 2, 0.5, BACK_Z), Color = P.HotPink, Parent = item })
	end

	-- Shop sign above the door.
	local sign = Style.RoundedBox("ShopSign", Vector3.new(22, 4.5, 1), at(floor, 0, (topY + WALL_H) / 2, FACADE_Z + 1), P.White, item, 0.5)
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
	local glow = Style.Part({ Name = "SignGlow", Size = Vector3.new(23, 5.5, 0.4), CFrame = at(floor, 0, (topY + WALL_H) / 2, FACADE_Z + 0.4), Color = P.Butter, Parent = item })
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
			MaxDistance = 22,
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
	Style.StripedAwning(B.HalfX * 2 - 2, 6, at(floor, 0, 10.2, FACADE_Z + 0.6), P.HotPink, P.White, item)
end


-- Hand tools (Tier 0). They stand where the Mixer / Oven will go and are hidden
-- once those are bought (PlotLayout ReplacedBy).
ItemBuilders.PrepTable = function(floor, item)
	local top = Style.RoundedBox("Body", Vector3.new(6, 0.6, 4), at(floor, -12, 3.2, -35), P.Peach, item, 0.6)
	for _, dx in { -2.4, 2.4 } do
		for _, dz in { -1.4, 1.4 } do
			Style.Part({ Name = "Leg", Size = Vector3.new(0.5, 2.9, 0.5), CFrame = at(floor, -12 + dx, 1.45, -35 + dz), Color = P.Cocoa, Parent = item })
		end
	end
	Style.Cylinder("Bowl", 1.2, 2.8, at(floor, -12.5, 4.1, -35), P.Mint, item)
	Style.Cylinder("Batter", 0.1, 2.3, at(floor, -12.5, 4.65, -35), P.Cream, item)
	local whisk = Style.Part({
		Name = "Whisk",
		Size = Vector3.new(0.2, 2.6, 0.2),
		CFrame = at(floor, -11.6, 5, -35) * CFrame.Angles(0, 0, math.rad(-25)),
		Color = P.Steel,
		Parent = item,
	})
	whisk.Material = Enum.Material.Metal
	Style.MachineSign(item, top, "🥄", "Mixing Bowl")
end

ItemBuilders.BasicOven = function(floor, item)
	Style.RoundedBox("Stand", Vector3.new(6, 3, 4), at(floor, 6, 1.5, -35), P.Cream, item, 0.6)
	local body = Style.RoundedBox("Body", Vector3.new(4, 2.6, 3), at(floor, 6, 4.3, -35.2), P.Peach, item, 0.6)
	Style.Part({
		Name = "Door",
		Size = Vector3.new(2.8, 1.6, 0.2),
		CFrame = at(floor, 6, 4.2, -33.6),
		Color = Color3.fromRGB(60, 40, 40),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Parent = item,
	})
	Style.Part({ Name = "Tray", Size = Vector3.new(3.4, 0.15, 2), CFrame = at(floor, 6, 3.08, -32.6), Color = P.Steel, Parent = item })
	Style.MachineSign(item, body, "🍞", "Basic Oven")
end

-- Helpers for the Phase D items ------------------------------------------------------


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
		Style.RoundedBox("Frame", Vector3.new(7, 5, 0.4), at(floor, x, 11, BACK_Z + 1.3), P.Cocoa, item, 0.3)
		panel("Poster", Vector3.new(6.2, 4.2, 0.3), at(floor, x, 11, BACK_Z + 1.6), color, `{icon}\n{cakeName}`, P.Cocoa, item)
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

-- Oven upgrades have no fixed model: the placed oven shows them (Baking/Ovens:
-- a blue vent per speed level, a light per rack, a gold band for Golden Oven).
local function noModel(_floor: CFrame, _item: Model) end
ItemBuilders.FasterOvens1 = noModel
ItemBuilders.FasterOvens2 = noModel
ItemBuilders.FasterOvens3 = noModel
ItemBuilders.OvenRack2 = noModel
ItemBuilders.OvenRack3 = noModel
ItemBuilders.OvenRack4 = noModel

ItemBuilders.BigMixer = function(floor, item)
	local bowl = Style.Cylinder("BigBowl", 3, 5.6, at(floor, -12, 5.3, -35), P.Steel, item)
	bowl.Material = Enum.Material.Metal -- (no extra label: it would overlap the Mixer's sign)
end

ItemBuilders.GoldenOven = noModel

ItemBuilders.CakeCharm = function(floor, item)
	Style.Part({ Name = "Chain", Size = Vector3.new(0.15, 2.4, 0.15), CFrame = at(floor, 20, 9.4, 32), Color = P.Gold, Parent = item })
	local charm = Style.Ball("Charm", 1.4, at(floor, 20, 7.6, 32), Color3.fromRGB(80, 220, 120), item)
	charm.Material = Enum.Material.Neon
end

ItemBuilders.GoldenShopfront = function(floor, item)
	Style.Trim("GoldCornice", Vector3.new(B.HalfX * 2 + 2, 1.4, 2.6), at(floor, 0, WALL_H + 0.4, FACADE_Z), P.Gold, item)
	for _, x in { -(B.DoorHalf + 1), B.DoorHalf + 1 } do
		Style.RoundedBox("GoldPillar", Vector3.new(2.4, 7.2, 2), at(floor, x, 6.5, FACADE_Z), P.Gold, item, 0.6)
	end
	local glow = Style.Part({ Name = "GoldGlow", Size = Vector3.new(23.4, 5.9, 0.3), CFrame = at(floor, 0, (10 + WALL_H) / 2, FACADE_Z + 0.25), Color = P.Gold, Parent = item })
	glow.Material = Enum.Material.Neon
end

-- Second floor: a deck over the front (dining) half of the building at wall
-- height, reached by stairs along the right wall. The stairwell (x WELL_X..SIDE_X,
-- from the landing to the facade) is left open.
ItemBuilders.SecondFloor = function(floor, item)
	local deckColor = P.Peach
	local wellX = SIDE_X - 9.5 -- deck's right edge = stairwell's left edge
	local back = FACADE_Z - 40 -- deck's back edge
	local steps, run = 16, 1.5
	local rise = DECK_Y / steps
	local stairBottom = FACADE_Z - 4 -- the lowest step, near the shop front
	local stairTop = stairBottom - steps * run -- where the landing starts
	local deckW = wellX + SIDE_X
	Style.Part({ Name = "Deck", Size = Vector3.new(deckW, 1, FACADE_Z - back), CFrame = at(floor, (wellX - SIDE_X) / 2, DECK_Y - 0.5, (back + FACADE_Z) / 2), Color = deckColor, Material = Enum.Material.WoodPlanks, Parent = item })
	Style.Part({ Name = "Landing", Size = Vector3.new(SIDE_X - wellX, 1, stairTop - back), CFrame = at(floor, (wellX + SIDE_X) / 2, DECK_Y - 0.5, (back + stairTop) / 2), Color = deckColor, Material = Enum.Material.WoodPlanks, Parent = item })
	for i = 1, steps do
		local h = rise * i
		Style.Part({
			Name = "Step",
			Size = Vector3.new(8, h, run),
			CFrame = at(floor, SIDE_X - 5, h / 2, stairBottom - (i - 0.5) * run),
			Color = if i % 2 == 0 then P.Cream else P.Vanilla,
			Parent = item,
		})
	end
	-- Railings: back edge of the deck, and along the stairwell.
	Style.Part({ Name = "RailBack", Size = Vector3.new(SIDE_X * 2, 0.5, 0.5), CFrame = at(floor, 0, DECK_Y + 3, back + 0.2), Color = P.White, Parent = item })
	Style.Part({ Name = "RailWell", Size = Vector3.new(0.5, 0.5, FACADE_Z - stairTop), CFrame = at(floor, wellX - 0.2, DECK_Y + 3, (stairTop + FACADE_Z) / 2), Color = P.White, Parent = item })
	for x = -SIDE_X + 2, wellX, 6 do
		Style.Part({ Name = "Baluster", Size = Vector3.new(0.4, 3, 0.4), CFrame = at(floor, x, DECK_Y + 1.5, back + 0.2), Color = P.White, Parent = item })
	end
	for z = stairTop, FACADE_Z - 1, 6 do
		Style.Part({ Name = "Baluster", Size = Vector3.new(0.4, 3, 0.4), CFrame = at(floor, wellX - 0.2, DECK_Y + 1.5, z), Color = P.White, Parent = item })
	end
	-- Rooftop café tables (clear of the VIP Lounge at x -27..-9, z 4..17).
	for _, spot in { { -44, 4 }, { -44, 24 }, { 10, 6 }, { 28, 24 } } do
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

-- Factory Annex: a room behind the bakery's back wall (Config.Building.Annex) that
-- holds all the automation below. Its own floor, walls and a doorway from the bakery.
local ANNEX = B.Annex
local LINE_Z = ANNEX.LineZ
ItemBuilders.FactoryAnnex = function(floor, item)
	local z0, z1 = ANNEX.Z0, ANNEX.Z1
	local depth = z0 - z1
	local midZ = (z0 + z1) / 2
	local width = B.HalfX * 2
	Style.Part({ Name = "AnnexFloor", Size = Vector3.new(width, 1, depth), CFrame = at(floor, 0, -0.5, midZ), Color = P.Steel, Material = Enum.Material.Concrete, Parent = item })
	-- Yellow safety stripes along the line rows.
	for _, z in { LINE_Z + 4.5, LINE_Z - 4.5, ANNEX.UnitZ + 4.5 } do
		Style.Part({ Name = "Stripe", Size = Vector3.new(width - 8, 0.05, 0.5), CFrame = at(floor, 0, 0.03, z), Color = P.Butter, CanCollide = false, Parent = item })
	end
	local wallColor = Color3.fromRGB(205, 200, 215)
	Style.Part({ Name = "AnnexBackWall", Size = Vector3.new(width, WALL_H, 1), CFrame = at(floor, 0, WALL_H / 2, z1 + 0.5), Color = wallColor, Parent = item })
	for _, x in { -SIDE_X, SIDE_X } do
		Style.Part({ Name = "AnnexSideWall", Size = Vector3.new(1, WALL_H, depth), CFrame = at(floor, x, WALL_H / 2, midZ), Color = wallColor, Parent = item })
		Style.Part({ Name = "AnnexCornice", Size = Vector3.new(2.2, 1.2, depth), CFrame = at(floor, x, WALL_H + 0.3, midZ), Color = P.Lilac, Parent = item })
	end
	Style.Trim("AnnexCorniceBack", Vector3.new(width + 1.5, 1.2, 2.2), at(floor, 0, WALL_H + 0.3, z1 + 0.5), P.Lilac, item)
	-- Sign over the doorway (annex side).
	local doorX = (ANNEX.DoorX0 + ANNEX.DoorX1) / 2
	panel("AnnexSign", Vector3.new(10, 2.4, 0.4), at(floor, doorX, 12, z0 - 0.8), P.Lilac, "🏭 FACTORY", P.White, item)
end

-- Automation: production line 1 (row at LINE_Z in the annex) ----------------------------

ItemBuilders.IngredientConveyor = function(floor, item)
	local hopper = Style.RoundedBox("Hopper", Vector3.new(4, 3, 4), at(floor, -24, 1.5, LINE_Z), P.Lilac, item, 0.8)
	Style.Trim("HopperRim", Vector3.new(4.6, 0.5, 4.6), at(floor, -24, 3.2, LINE_Z), P.White, item)
	local tube = Style.Part({
		Name = "Tube",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(13, 1.2, 1.2),
		CFrame = at(floor, -26, 5, LINE_Z - 8.5) * CFrame.Angles(0, math.rad(90), 0),
		Color = P.Sky,
		Transparency = 0.3,
		Parent = item,
	})
	tube.Material = Enum.Material.Glass
	belt("Belt", Vector3.new(-22, 0, LINE_Z), Vector3.new(-14.5, 0, LINE_Z), floor, item)
	Style.MachineSign(item, hopper, "📦", "Line 1 Hopper", 1.4)
end

ItemBuilders.AutoMixer = function(floor, item)
	local body = Style.RoundedBox("Body", Vector3.new(5, 4, 5), at(floor, -12, 2, LINE_Z), P.Lilac, item, 1)
	Style.Cylinder("Bowl", 2.2, 4, at(floor, -12, 5.1, LINE_Z), P.Steel, item).Material = Enum.Material.Metal
	Style.Ball("Light", 0.8, at(floor, -12, 3, LINE_Z + 2.6), P.DeepMint, item).Material = Enum.Material.Neon
	belt("Belt", Vector3.new(-9.5, 0, LINE_Z), Vector3.new(1, 0, LINE_Z), floor, item)
	Style.MachineSign(item, body, "🤖", "Auto-Mixer", 1.4)
end

ItemBuilders.AutoOven = function(floor, item)
	local body = Style.RoundedBox("Body", Vector3.new(6, 6, 5), at(floor, 4, 3, LINE_Z), P.Lilac, item, 1)
	Style.Part({
		Name = "Door",
		Size = Vector3.new(4, 2.6, 0.3),
		CFrame = at(floor, 4, 3, LINE_Z + 2.6),
		Color = Color3.fromRGB(60, 40, 40),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Parent = item,
	})
	Style.Cylinder("Chimney", 2.4, 1, at(floor, 5.5, 7, LINE_Z - 1), P.Steel, item)
	Style.MachineSign(item, body, "🤖", "Auto-Oven", 1.4)
end

-- Cakes ride from the Auto-Oven to a hatch in the shared wall; from there they go
-- onto your display counters (Factory/AutoProduction animates the same path).
ItemBuilders.CounterConveyor = function(floor, item)
	local turnZ = ANNEX.Z0 - 4
	belt("Belt", Vector3.new(4, 0, LINE_Z + 3), Vector3.new(4, 0, turnZ), floor, item)
	belt("BeltTurn", Vector3.new(5, 0, turnZ), Vector3.new(9, 0, turnZ), floor, item)
	local chute = Style.RoundedBox("Chute", Vector3.new(2.4, 3, 2.4), at(floor, 9, 1.5, turnZ + 0.5), P.Lilac, item, 0.6)
	Style.MachineSign(item, chute, "➡️", "To Counters", 1.4)
end

ItemBuilders.AutoRestock = function(floor, item)
	local x, z = 26, ANNEX.Z0 - 2.5 -- against the shared wall, shelves facing the annex
	local rack = Style.RoundedBox("Rack", Vector3.new(8, 6, 3), at(floor, x, 3, z), P.Lilac, item, 0.6)
	for i, y in { 2, 4 } do
		Style.Trim(`Shelf{i}`, Vector3.new(8.4, 0.3, 3.4), at(floor, x, y, z - 0.3), P.White, item)
	end
	-- Marker parts where stored cakes are shown (3 per shelf).
	local slots = Instance.new("Folder")
	slots.Name = "StorageSlots"
	local n = 0
	for _, y in { 2.15, 4.15 } do
		for _, dx in { -2.5, 0, 2.5 } do
			n += 1
			Style.Part({ Name = `Store{n}`, Size = Vector3.new(1.6, 0.1, 1.6), CFrame = at(floor, x + dx, y, z - 0.9), Transparency = 1, CanCollide = false, Parent = slots })
		end
	end
	slots.Parent = item
	Style.MachineSign(item, rack, "🗄️", "Restock Rack", 1.4)
end

local function productionUnit(x: number, label: string)
	return function(floor: CFrame, item: Model)
		local z = ANNEX.UnitZ
		local body = Style.RoundedBox("Body", Vector3.new(10, 6, 5), at(floor, x, 3, z), P.Lilac, item, 1)
		Style.Part({
			Name = "Door",
			Size = Vector3.new(4, 2.6, 0.3),
			CFrame = at(floor, x + 2, 3, z + 2.6),
			Color = Color3.fromRGB(60, 40, 40),
			Material = Enum.Material.Glass,
			Transparency = 0.2,
			Parent = item,
		})
		Style.RoundedBox("Hopper", Vector3.new(3, 2, 3), at(floor, x - 3, 7, z), P.White, item, 0.6)
		local panelPart = panel("Panel", Vector3.new(2.6, 2, 0.3), at(floor, x - 3.5, 3.4, z + 2.6), P.Charcoal, "🏭", P.White, item)
		panelPart:SetAttribute("Role", "RecipePanel")
		Style.Cylinder("Chimney", 2.4, 1, at(floor, x + 3.5, 7, z - 1), P.Steel, item)
		Style.MachineSign(item, body, "🏭", label, 1.4)
	end
end
ItemBuilders.ProductionLine2 = productionUnit(-6, "Production Line 2")
ItemBuilders.ProductionLine3 = productionUnit(24, "Production Line 3")

return ItemBuilders
