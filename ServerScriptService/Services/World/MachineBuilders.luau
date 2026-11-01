--!strict
-- Geometry for placeable automation (Shared/BuildCatalog Kind "AutoBaker" /
-- "CakeRack"). Same signature as ItemBuilders, built centred on the floor origin
-- with the front facing +Z; Build/BuildModels moves them where they're placed.
-- Part names Factory/AutoBakers relies on:
--   Auto-Bakers: Body (prompts, repairs), Door (glows while baking), Whisk (spins),
--                Chimney with a ParticleEmitter "Steam"
--   Cake Rack:   Body, Spot1..Spot9 (invisible cake spots on the shelves)

local Services = script:FindFirstAncestor("Services") :: Folder
local Style = require(Services.World.Style)

local P = Style.Palette

local MachineBuilders: { [string]: (floor: CFrame, item: Model) -> () } = {}

local function at(floor: CFrame, x: number, y: number, z: number): CFrame
	return floor * CFrame.new(x, y, z)
end

-- One Auto-Baker; `trim` colours the tier (Auto / Turbo / Golden).
local function autoBaker(color: Color3, trim: Color3, label: string, extra: ((CFrame, Model) -> ())?)
	return function(floor: CFrame, item: Model)
		local body = Style.RoundedBox("Body", Vector3.new(6, 5, 5), at(floor, 0, 2.5, 0), color, item, 0.8)
		Style.Trim("Base", Vector3.new(6.4, 0.6, 5.4), at(floor, 0, 0.3, 0), trim, item)
		-- Oven door on the front (+Z), with a handle and a little window frame.
		Style.Trim("DoorFrame", Vector3.new(4.4, 2.8, 0.3), at(floor, 0, 2.1, 2.55), P.Cream, item)
		Style.Part({
			Name = "Door",
			Size = Vector3.new(3.8, 2.2, 0.2),
			CFrame = at(floor, 0, 2.1, 2.72),
			Color = Color3.fromRGB(60, 40, 40),
			Material = Enum.Material.Glass,
			Transparency = 0.2,
			Parent = item,
		})
		Style.Part({ Name = "Handle", Size = Vector3.new(2.6, 0.25, 0.25), CFrame = at(floor, 0, 3.45, 2.95), Color = P.Steel, Material = Enum.Material.Metal, Parent = item })
		-- Control strip with three lights.
		for i = -1, 1 do
			local lamp = Style.Ball("Lamp", 0.45, at(floor, i * 0.9, 4.35, 2.55), if i == 0 then P.Mint else trim, item)
			lamp.Material = Enum.Material.Neon
		end
		-- Mixing bowl on top with a whisk that spins while it works.
		Style.Cylinder("Bowl", 1.4, 3.2, at(floor, -0.8, 5.7, -0.4), P.Steel, item).Material = Enum.Material.Metal
		Style.Cylinder("Batter", 0.15, 2.7, at(floor, -0.8, 6.35, -0.4), P.Cream, item)
		Style.RoundedBox("Arm", Vector3.new(0.8, 3.2, 0.8), at(floor, -0.8, 7.2, -2.1), trim, item, 0.3)
		Style.RoundedBox("ArmTop", Vector3.new(0.8, 0.8, 2), at(floor, -0.8, 8.6, -1.2), trim, item, 0.3)
		Style.Cylinder("Whisk", 2.2, 0.35, at(floor, -0.8, 7.1, -0.4), P.Steel, item).Material = Enum.Material.Metal
		-- Chimney with a steam puff.
		local chimney = Style.Cylinder("Chimney", 2.4, 1.1, at(floor, 2, 6.2, -1.2), P.Charcoal, item)
		local steam = Instance.new("ParticleEmitter")
		steam.Name = "Steam"
		steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
		steam.Color = ColorSequence.new(Color3.new(1, 1, 1))
		steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.4) })
		steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
		steam.Lifetime = NumberRange.new(1.2, 1.8)
		steam.Speed = NumberRange.new(2, 3)
		steam.SpreadAngle = Vector2.new(12, 12)
		steam.Rate = 4
		steam.Enabled = false
		steam.Parent = chimney
		if extra then
			extra(floor, item)
		end
		Style.MachineSign(item, body, "🤖", label, 6)
	end
end

MachineBuilders.AutoBaker = autoBaker(P.Mint, P.DeepMint, "Auto-Baker")
MachineBuilders.TurboBaker = autoBaker(P.Sky, P.Lilac, "Turbo Baker", function(floor, item)
	-- Twin exhaust fins for speed.
	for _, x in { -3.2, 3.2 } do
		Style.RoundedBox("Fin", Vector3.new(0.4, 3, 3), at(floor, x, 2.6, -0.5), P.Lilac, item, 0.2)
	end
end)
MachineBuilders.GoldenBaker = autoBaker(P.Butter, P.Gold, "Golden Baker", function(floor, item)
	local star = Style.Ball("Star", 1.2, at(floor, 2, 7.9, -1.2), P.Gold, item)
	star.Material = Enum.Material.Neon
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = P.Gold
	sparkle.Parent = star
end)

-- Cake Rack: three shelves of three cake spots, open at the front (+Z).
MachineBuilders.CakeRack = function(floor, item)
	local width, depth, height = 9, 3.2, 8
	local body = Style.RoundedBox("Body", Vector3.new(width, 0.6, depth), at(floor, 0, 0.3, 0), P.Peach, item, 0.3)
	for _, x in { -width / 2 + 0.3, width / 2 - 0.3 } do
		Style.Part({ Name = "Post", Size = Vector3.new(0.5, height, depth), CFrame = at(floor, x, height / 2, 0), Color = P.Peach, Parent = item })
	end
	Style.Part({ Name = "BackPanel", Size = Vector3.new(width, height, 0.3), CFrame = at(floor, 0, height / 2, -depth / 2 + 0.15), Color = P.Cream, Parent = item })
	Style.Trim("Top", Vector3.new(width + 0.4, 0.5, depth + 0.4), at(floor, 0, height + 0.25, 0), P.HotPink, item)
	local spot = 0
	for row, y in { 0.6, 3.1, 5.6 } do
		if row > 1 then
			Style.Part({ Name = "Shelf", Size = Vector3.new(width - 1, 0.3, depth - 0.3), CFrame = at(floor, 0, y - 0.15, 0.1), Color = P.White, Parent = item })
		end
		for _, x in { -2.8, 0, 2.8 } do
			spot += 1
			Style.Part({
				Name = `Spot{spot}`,
				Size = Vector3.new(2, 0.2, 2),
				CFrame = at(floor, x, y + 0.1, 0.2),
				Transparency = 1,
				CanCollide = false,
				Parent = item,
			})
		end
	end
	Style.MachineSign(item, body, "🗄️", "Cake Rack", 8.6)
end

return MachineBuilders
