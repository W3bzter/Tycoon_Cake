--!strict
-- Geometry for each upgrade, keyed by upgrade Id. Each builder fills `item`
-- (a Model) using plot-local coordinates relative to `floor` (top of the plot floor).
-- Part names BakingPipeline depends on: IngredientCrate.Crate, Mixer.Body,
-- Oven(2).Body + Door, DisplayCounter.Counter.

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

ItemBuilders.IngredientCrate = function(floor, item)
	-- Pantry shelf against the back wall. "Crate" is the interact part.
	local cabinet = Style.RoundedBox("Crate", Vector3.new(12, 8, 3), at(floor, -28, 4, -37.4), P.Peach, item, 0.5)
	for i, y in { 2.4, 4.9, 7.4 } do
		Style.Trim(`Shelf{i}`, Vector3.new(12.4, 0.4, 3.6), at(floor, -28, y, -36.6), P.Vanilla, item)
	end
	local goods = {
		{ -32, 3.2, P.White, Enum.PartType.Ball }, -- flour
		{ -28, 3.2, P.Cream, Enum.PartType.Block }, -- eggs
		{ -24, 3.2, P.Pink, Enum.PartType.Block }, -- sugar
		{ -31, 5.7, P.Butter, Enum.PartType.Block }, -- butter
		{ -25, 5.7, P.White, Enum.PartType.Cylinder }, -- milk
	}
	for _, g in goods do
		Style.Part({
			Name = "Goods",
			Shape = g[4],
			Size = Vector3.new(1.6, 1.6, 1.6),
			CFrame = at(floor, g[1], g[2], -36.2),
			Color = g[3],
			Parent = item,
		})
	end
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

ItemBuilders.DisplayCounter = function(floor, item)
	local counter = Style.RoundedBox("Counter", Vector3.new(20, 4, 4), at(floor, 20, 2, 32), P.White, item, 0.8)
	Style.Trim("Kick", Vector3.new(20.4, 0.8, 4.4), at(floor, 20, 0.4, 32), P.HotPink, item)
	for i = 0, 4 do
		Style.Part({
			Name = "Stripe",
			Size = Vector3.new(1.6, 3, 0.2),
			CFrame = at(floor, 12 + i * 4, 2.3, 34.05),
			Color = P.Pink,
			Parent = item,
		})
	end
	Style.MachineSign(item, counter, "🍰", "Display Counter")
end

ItemBuilders.Plants = function(floor, item)
	local spots = { { -10, 27 }, { 10, 27 }, { -36, -2 }, { 36, -2 } }
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

return ItemBuilders
