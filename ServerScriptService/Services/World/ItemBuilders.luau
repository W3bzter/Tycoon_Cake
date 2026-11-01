--!strict
-- Geometry for each upgrade, keyed by upgrade Id. Each builder fills `item`
-- (a Model) using plot-local coordinates relative to `floor` (top of the plot floor).
-- Part names BakingPipeline depends on: IngredientCrate.Crate, Mixer.Body,
-- Oven(2).Body + Door, DisplayCounter.Counter.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Recipes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Recipes"))
local Services = script:FindFirstAncestor("Services") :: Folder
local Assets = require(Services.World.Assets)
local DockBuilders = require(Services.World.DockBuilders)
local Style = require(Services.World.Style)

local P = Style.Palette
local ItemBuilders: { [string]: (floor: CFrame, item: Model) -> () } = {}

local B = Config.Building -- building shell size (ConfigParts/Build)
local WALL_H = B.WallHeight
local FACADE_Z = B.FacadeZ
local SIDE_X = B.HalfX - 0.5 -- side wall centres (±)
local DECK_Y = B.DeckY

local function at(floor: CFrame, x: number, y: number, z: number): CFrame
	return floor * CFrame.new(x, y, z)
end

-- Every size stage of a fixed item: one child model per Config.Building.Stages
-- entry, tagged Stage = n. Only the owner's current stage is shown (TycoonButtons).
local function perStage(item: Model, build: (stage: Model, halfX: number, backZ: number, last: boolean) -> ())
	for i, st in B.Stages do
		local stage = Instance.new("Model")
		stage.Name = `Stage{i}`
		stage:SetAttribute("Stage", i)
		build(stage, st.HalfX, st.BackZ, i == #B.Stages)
		stage.Parent = item
	end
end

-- The bakery shell for one size stage.
local function buildShell(floor: CFrame, item: Model, halfX: number, backZ: number)
	local wallColor = P.Vanilla
	local width = halfX * 2
	local depth = FACADE_Z - backZ -- side walls run from the back wall to the facade
	local midZ = (FACADE_Z + backZ) / 2
	local backC = backZ + 0.5
	local sideX = halfX - 0.5
	-- Back wall and side walls.
	Style.Part({ Name = "BackWall", Size = Vector3.new(width, WALL_H, 1), CFrame = at(floor, 0, WALL_H / 2, backC), Color = wallColor, Parent = item })
	for _, x in { -sideX, sideX } do
		Style.Part({ Name = "SideWall", Size = Vector3.new(1, WALL_H, depth), CFrame = at(floor, x, WALL_H / 2, midZ), Color = wallColor, Parent = item })
	end

	-- Front facade on each side of the doorway: low band, pillars, glass windows
	-- (the facade from the door edge to the side wall is split into equal bays).
	local inner, outer = B.DoorHalf + 1, sideX
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
	Style.Trim("CorniceBack", Vector3.new(width + 1.5, 1.2, 2.2), at(floor, 0, WALL_H + 0.3, backC), P.HotPink, item)
	for _, x in { -sideX, sideX } do
		Style.Part({ Name = "CorniceSide", Size = Vector3.new(2.2, 1.2, depth), CFrame = at(floor, x, WALL_H + 0.3, midZ), Color = P.HotPink, Parent = item })
		Style.Part({ Name = "Baseboard", Size = Vector3.new(1.6, 1, depth), CFrame = at(floor, x, 0.5, midZ), Color = P.HotPink, Parent = item })
	end
	Style.Part({ Name = "Baseboard", Size = Vector3.new(width, 1, 1.6), CFrame = at(floor, 0, 0.5, backC), Color = P.HotPink, Parent = item })

	-- Hanging ceiling lamps in a grid (World/DayNight lights them at night).
	local lamps = Instance.new("Model")
	lamps.Name = "CeilingLamps"
	local spacing = 24
	local countX = math.max(1, math.floor((width - 12) / spacing) + 1)
	local countZ = math.max(1, math.floor((depth - 16) / spacing) + 1)
	for ix = 0, countX - 1 do
		for iz = 0, countZ - 1 do
			local x = -((countX - 1) * spacing) / 2 + ix * spacing
			local z = midZ - ((countZ - 1) * spacing) / 2 + iz * spacing
			Style.Part({ Name = "Cord", Size = Vector3.new(0.15, 2.4, 0.15), CFrame = at(floor, x, WALL_H - 1.2, z), Color = P.Charcoal, CanCollide = false, Parent = lamps })
			Style.Cylinder("Shade", 0.7, 1.8, at(floor, x, WALL_H - 2.6, z), P.HotPink, lamps).CanCollide = false
			local bulb = Style.Ball("Bulb", 0.9, at(floor, x, WALL_H - 3.1, z), P.Butter, lamps)
			bulb.CanCollide = false
			local light = Instance.new("PointLight")
			light.Range = 24
			light.Brightness = 1.1
			light.Color = Color3.fromRGB(255, 225, 170)
			light.Shadows = false
			light.Enabled = false
			light.Parent = bulb
			CollectionService:AddTag(bulb, "NightLight")
			CollectionService:AddTag(light, "NightLight")
		end
	end
	lamps.Parent = item
end

ItemBuilders.Walls = function(floor, item)
	perStage(item, function(stage, halfX, backZ)
		buildShell(floor, stage, halfX, backZ)
	end)
	local topY = 10

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
	perStage(item, function(stage, halfX)
		Style.StripedAwning(halfX * 2 - 2, 6, at(floor, 0, 10.2, FACADE_Z + 0.6), P.HotPink, P.White, stage)
	end)
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

local function recipePoster(x: number, cakeName: string, icon: string, color: Color3)
	return function(floor: CFrame, item: Model)
		perStage(item, function(stage, _halfX, backZ)
			Style.RoundedBox("Frame", Vector3.new(7, 5, 0.4), at(floor, x, 11, backZ + 1.8), P.Cocoa, stage, 0.3)
			panel("Poster", Vector3.new(6.2, 4.2, 0.3), at(floor, x, 11, backZ + 2.1), color, `{icon}\n{cakeName}`, P.Cocoa, stage)
		end)
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
-- Bigger Bakery: the Walls/Awning/deck... items hold every size stage; the
-- expansions only change which stage shows (TycoonButtons).
ItemBuilders.BakeryExpansion1 = noModel
ItemBuilders.BakeryExpansion2 = noModel
ItemBuilders.AutoRoller = noModel -- Baking/AutoRoll; its on/off prompt sits on the pantry

ItemBuilders.BigMixer = function(floor, item)
	local bowl = Style.Cylinder("BigBowl", 3, 5.6, at(floor, -12, 5.3, -35), P.Steel, item)
	bowl.Material = Enum.Material.Metal -- (no extra label: it would overlap the Mixer's sign)
end

ItemBuilders.GoldenOven = noModel
ItemBuilders.LoadingDock = DockBuilders.LoadingDock -- trucks: Customers/DeliveryTrucks
ItemBuilders.FasterTrucks = noModel
ItemBuilders.BiggerTruck1 = noModel
ItemBuilders.BiggerTruck2 = noModel

ItemBuilders.CakeCharm = function(floor, item)
	Style.Part({ Name = "Chain", Size = Vector3.new(0.15, 2.4, 0.15), CFrame = at(floor, 20, 9.4, 32), Color = P.Gold, Parent = item })
	local charm = Style.Ball("Charm", 1.4, at(floor, 20, 7.6, 32), Color3.fromRGB(80, 220, 120), item)
	charm.Material = Enum.Material.Neon
end

ItemBuilders.GoldenShopfront = function(floor, item)
	perStage(item, function(stage, halfX)
		Style.Trim("GoldCornice", Vector3.new(halfX * 2 + 2, 1.4, 2.6), at(floor, 0, WALL_H + 0.4, FACADE_Z), P.Gold, stage)
	end)
	for _, x in { -(B.DoorHalf + 1), B.DoorHalf + 1 } do
		Style.RoundedBox("GoldPillar", Vector3.new(2.4, 7.2, 2), at(floor, x, 6.5, FACADE_Z), P.Gold, item, 0.6)
	end
	local glow = Style.Part({ Name = "GoldGlow", Size = Vector3.new(23.4, 5.9, 0.3), CFrame = at(floor, 0, (10 + WALL_H) / 2, FACADE_Z + 0.25), Color = P.Gold, Parent = item })
	glow.Material = Enum.Material.Neon
end

-- Second floor: a deck over the front (dining) half of the building at wall
-- height, reached by stairs along the right wall. The stairwell (x WELL_X..SIDE_X,
-- from the landing to the facade) is left open.
local function buildDeck(floor: CFrame, item: Model, halfX: number)
	local sideX = halfX - 0.5
	local deckColor = P.Peach
	local wellX = sideX - 9.5 -- deck's right edge = stairwell's left edge
	local back = FACADE_Z - 40 -- deck's back edge
	local steps, run = 16, 1.5
	local rise = DECK_Y / steps
	local stairBottom = FACADE_Z - 4 -- the lowest step, near the shop front
	local stairTop = stairBottom - steps * run -- where the landing starts
	local deckW = wellX + sideX
	Style.Part({ Name = "Deck", Size = Vector3.new(deckW, 1, FACADE_Z - back), CFrame = at(floor, (wellX - sideX) / 2, DECK_Y - 0.5, (back + FACADE_Z) / 2), Color = deckColor, Material = Enum.Material.WoodPlanks, Parent = item })
	Style.Part({ Name = "Landing", Size = Vector3.new(sideX - wellX, 1, stairTop - back), CFrame = at(floor, (wellX + sideX) / 2, DECK_Y - 0.5, (back + stairTop) / 2), Color = deckColor, Material = Enum.Material.WoodPlanks, Parent = item })
	for i = 1, steps do
		local h = rise * i
		Style.Part({
			Name = "Step",
			Size = Vector3.new(8, h, run),
			CFrame = at(floor, sideX - 5, h / 2, stairBottom - (i - 0.5) * run),
			Color = if i % 2 == 0 then P.Cream else P.Vanilla,
			Parent = item,
		})
	end
	-- Railings: back edge of the deck, and along the stairwell.
	Style.Part({ Name = "RailBack", Size = Vector3.new(sideX * 2, 0.5, 0.5), CFrame = at(floor, 0, DECK_Y + 3, back + 0.2), Color = P.White, Parent = item })
	Style.Part({ Name = "RailWell", Size = Vector3.new(0.5, 0.5, FACADE_Z - stairTop), CFrame = at(floor, wellX - 0.2, DECK_Y + 3, (stairTop + FACADE_Z) / 2), Color = P.White, Parent = item })
	for x = -sideX + 2, wellX, 6 do
		Style.Part({ Name = "Baluster", Size = Vector3.new(0.4, 3, 0.4), CFrame = at(floor, x, DECK_Y + 1.5, back + 0.2), Color = P.White, Parent = item })
	end
	for z = stairTop, FACADE_Z - 1, 6 do
		Style.Part({ Name = "Baluster", Size = Vector3.new(0.4, 3, 0.4), CFrame = at(floor, wellX - 0.2, DECK_Y + 1.5, z), Color = P.White, Parent = item })
	end
	-- Rooftop café tables (clear of the VIP Lounge at x -27..-9, z 4..17).
	local spots = { { -18, 27 }, { 2, 6 }, { wellX - 6, 26 } }
	if halfX >= 45 then
		table.insert(spots, { -halfX + 8, 6 })
		table.insert(spots, { -halfX + 8, 26 })
	end
	for _, spot in spots do
		Style.Cylinder("TableTop", 0.4, 4.4, at(floor, spot[1], DECK_Y + 3, spot[2]), P.White, item)
		Style.Cylinder("TableLeg", 2.8, 0.6, at(floor, spot[1], DECK_Y + 1.4, spot[2]), P.Sky, item)
		Style.Cylinder("Umbrella", 0.4, 6, at(floor, spot[1], DECK_Y + 7, spot[2]), P.HotPink, item)
		Style.Cylinder("Pole", 4, 0.3, at(floor, spot[1], DECK_Y + 5, spot[2]), P.White, item)
	end
end

ItemBuilders.SecondFloor = function(floor, item)
	perStage(item, function(stage, halfX)
		buildDeck(floor, stage, halfX)
	end)
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

-- Drive-thru: a car lane beside the plot (outside its floor, x 62..70) from the
-- street to a turnaround pad, a pickup kiosk at the window and a street sign.
-- Cars: Customers/DriveThru (Config.DriveThru).
ItemBuilders.DriveThru = function(floor, item)
	local D = Config.DriveThru
	local x = D.LaneX
	local z0, z1 = D.EndZ - 5, B.FrontZ
	Style.Part({ Name = "Lane", Size = Vector3.new(8, 1, z1 - z0), CFrame = at(floor, x, -0.5, (z0 + z1) / 2), Color = P.Asphalt, Parent = item })
	for _, side in { -1, 1 } do
		Style.Part({ Name = "Curb", Size = Vector3.new(0.5, 0.5, z1 - z0), CFrame = at(floor, x + side * 4.25, 0.25, (z0 + z1) / 2), Color = P.White, Parent = item })
	end
	for z = z0 + 6, z1 - 4, 6 do
		Style.Part({ Name = "Dash", Size = Vector3.new(0.4, 0.05, 2.4), CFrame = at(floor, x, 0.03, z), Color = P.Butter, CanCollide = false, Parent = item })
	end
	Style.Cylinder("Turnaround", 0.06, 8, at(floor, x, 0.04, D.EndZ), P.HotPink, item).CanCollide = false
	-- Pickup kiosk on the bakery side of the lane, window facing the lane (+X).
	local kz = D.WindowZ
	Style.RoundedBox("Kiosk", Vector3.new(2.4, 6.5, 7), at(floor, 60.8, 3.25, kz), P.Cream, item, 0.5)
	Style.Part({ Name = "KioskWindow", Size = Vector3.new(0.2, 2.4, 3.4), CFrame = at(floor, 62.05, 3.6, kz), Color = P.Glass, Material = Enum.Material.Glass, Transparency = 0.4, Parent = item })
	Style.Trim("Sill", Vector3.new(1.2, 0.3, 3.8), at(floor, 62.3, 2.35, kz), P.HotPink, item)
	Style.Part({ Name = "KioskRoof", Size = Vector3.new(4.2, 0.4, 8), CFrame = at(floor, 61.6, 6.7, kz) * CFrame.Angles(0, 0, math.rad(-12)), Color = P.HotPink, Parent = item })
	panel("PickupSign", Vector3.new(3.6, 1.2, 0.3), at(floor, 62.25, 5.4, kz) * CFrame.Angles(0, math.rad(90), 0), P.White, "🍰 PICK UP", P.HotPink, item)
	-- Street sign at the lane mouth.
	Style.Cylinder("SignPost", 7, 0.5, at(floor, x + 5.2, 3.5, z1 - 3), P.White, item)
	panel("DriveThruSign", Vector3.new(6, 2.4, 0.4), at(floor, x + 5.2, 7.6, z1 - 3), P.HotPink, "🚗 DRIVE-THRU", P.White, item)
end

return ItemBuilders
