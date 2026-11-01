--!strict
-- What each mutation, cake trait, ingredient trait and rarity tier looks like.
-- Each entry builds its emitters/shells inside a model FX root (see FxKit).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))

local FxKit = require(script.Parent.FxKit)
local TEX, RAINBOW, seq, fade, emitter, light, shell = FxKit.TEX, FxKit.RAINBOW, FxKit.seq, FxKit.fade, FxKit.emitter, FxKit.light, FxKit.shell

local CakeFX = {}

-- Mutations ---------------------------------------------------------------------------

local MUTATION_FX: { [string]: (Folder, Attachment, Vector3, BasePart, boolean) -> () } = {}

MUTATION_FX.Molten = function(folder, att, size, base, lite)
	emitter(att, { Texture = TEX.Fire, Color = seq(Color3.fromRGB(255, 120, 30)), Rate = if lite then 8 else 18, Size = fade(size.X * 0.4, 0), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(25, 25), Acceleration = Vector3.new(0, 4, 0), Lifetime = NumberRange.new(0.5, 0.9) })
	emitter(att, { Color = seq(Color3.fromRGB(255, 200, 80)), Rate = 10, Size = fade(0.15, 0), Speed = NumberRange.new(2, 5), Acceleration = Vector3.new(0, 6, 0) })
	light(att, Color3.fromRGB(255, 120, 40), 2, 8, true)
	if not lite then
		shell(folder, base, att.WorldPosition, size, { Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 90, 20), Transparency = 0.85 })
	end
end

MUTATION_FX.Frozen = function(folder, att, size, base, lite)
	emitter(att, { Color = seq(Color3.fromRGB(200, 240, 255)), Rate = 10, Size = fade(0.25, 0.05), Speed = NumberRange.new(0.5, 1), Acceleration = Vector3.new(0, -2, 0), RotSpeed = NumberRange.new(-90, 90) })
	emitter(att, { Texture = TEX.Smoke, Color = seq(Color3.fromRGB(220, 245, 255)), Rate = 3, Size = fade(size.X * 0.5, size.X), Transparency = fade(0.7, 1), Speed = NumberRange.new(0.2, 0.5), Acceleration = Vector3.new(0, -0.5, 0) })
	light(att, Color3.fromRGB(140, 220, 255), 1.2, 7)
	if not lite then
		shell(folder, base, att.WorldPosition, size, { Material = Enum.Material.Ice, Color = Color3.fromRGB(170, 230, 255), Transparency = 0.6 })
	end
end

MUTATION_FX.Electric = function(folder, att, size, base, lite)
	emitter(att, { Color = seq(Color3.fromRGB(255, 250, 120)), Rate = 25, Lifetime = NumberRange.new(0.1, 0.25), Speed = NumberRange.new(6, 10), Size = fade(0.3, 0) })
	light(att, Color3.fromRGB(255, 240, 100), 3, 9, true)
	-- Two zig-zag arcs between attachments around the cake.
	for i = 1, (if lite then 1 else 2) do
		local a0 = Instance.new("Attachment")
		local a1 = Instance.new("Attachment")
		a0.Parent = base
		a1.Parent = base
		a0.WorldPosition = att.WorldPosition + Vector3.new(size.X * 0.6, size.Y * (0.2 * i), 0)
		a1.WorldPosition = att.WorldPosition + Vector3.new(-size.X * 0.6, size.Y * 0.3, size.Z * 0.3 * i)
		folder.Destroying:Connect(function()
			a0:Destroy()
			a1:Destroy()
		end)
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = seq(Color3.fromRGB(255, 255, 160))
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Width0 = 0.12
		beam.Width1 = 0.12
		beam.Segments = 12
		beam.CurveSize0 = 2
		beam.CurveSize1 = -2
		beam.FaceCamera = true
		beam.Parent = folder
		CollectionService:AddTag(beam, "FxFlicker")
	end
end

MUTATION_FX.Galaxy = function(folder, att, size, base, lite)
	emitter(att, { Texture = TEX.Vortex, Color = seq(Color3.fromRGB(160, 100, 255)), Rate = 4, Size = fade(size.X * 0.7, size.X * 1.1), Transparency = fade(0.4, 1), Speed = NumberRange.new(0), RotSpeed = NumberRange.new(60, 120), Lifetime = NumberRange.new(1.2, 1.6) })
	emitter(att, { Color = seq(Color3.fromRGB(255, 255, 255)), Rate = 14, Size = fade(0.18, 0), Speed = NumberRange.new(0.5, 1.5), Lifetime = NumberRange.new(1, 2) })
	light(att, Color3.fromRGB(150, 90, 255), 2, 9)
	if not lite then
		local s = shell(folder, base, att.WorldPosition, size, { Material = Enum.Material.ForceField, Color = Color3.fromRGB(130, 80, 255), Transparency = 0 })
		CollectionService:AddTag(s, "FxSpin")
	end
end

MUTATION_FX.Rainbow = function(folder, att, size, base, lite)
	emitter(att, { Color = RAINBOW, Rate = 18, Size = fade(0.3, 0), Speed = NumberRange.new(1.5, 3), Lifetime = NumberRange.new(1, 1.6) })
	local l = light(att, Color3.fromRGB(255, 120, 200), 2, 9)
	CollectionService:AddTag(l, "FxRainbow")
	if not lite then
		-- A force-field bubble whose colour cycles on the client.
		local s = shell(folder, base, att.WorldPosition, size, { Material = Enum.Material.ForceField, Color = Color3.fromRGB(255, 120, 200), Transparency = 0 })
		CollectionService:AddTag(s, "FxRainbow")
		CollectionService:AddTag(s, "FxSpin")
	end
end

MUTATION_FX.Void = function(folder, att, size, base, lite)
	-- Particles that swell then collapse back to nothing, spinning: a tiny black hole.
	emitter(att, { Texture = TEX.Vortex, Color = seq(Color3.fromRGB(110, 0, 170)), Rate = 6, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size.X * 1.4), NumberSequenceKeypoint.new(1, 0) }), Transparency = fade(0.2, 0.6), Speed = NumberRange.new(0), RotSpeed = NumberRange.new(-200, -120), Lifetime = NumberRange.new(0.8, 1.1), LightEmission = 0.4 })
	emitter(att, { Texture = TEX.Smoke, Color = seq(Color3.fromRGB(20, 0, 30)), Rate = 6, Size = fade(size.X * 0.6, size.X * 1.2), Transparency = fade(0.3, 1), Speed = NumberRange.new(0.2, 0.6), LightEmission = 0 })
	light(att, Color3.fromRGB(120, 0, 200), 1.5, 10, true)
	if not lite then
		local s = shell(folder, base, att.WorldPosition, size, { Material = Enum.Material.Neon, Color = Color3.fromRGB(10, 0, 20), Transparency = 0.45 })
		CollectionService:AddTag(s, "FxSpin")
	end
end

-- Traits ---------------------------------------------------------------------------------

local CAKE_TRAIT_FX: { [string]: (Attachment, Vector3) -> () } = {
	Glazed = function(att, size)
		emitter(att, { Color = seq(Color3.new(1, 1, 1)), Rate = 3, Size = fade(0.35, 0), Speed = NumberRange.new(0), Lifetime = NumberRange.new(0.3, 0.5) })
	end,
	Sprinkled = function(att, size)
		emitter(att, { Color = RAINBOW, Rate = 4, Size = fade(0.12, 0.12), Speed = NumberRange.new(1, 2), Acceleration = Vector3.new(0, -5, 0), LightEmission = 0.3 })
	end,
	Burnt = function(att, size)
		emitter(att, { Texture = TEX.Smoke, Color = seq(Color3.fromRGB(60, 55, 50)), Rate = 3, Size = fade(size.X * 0.3, size.X * 0.8), Transparency = fade(0.5, 1), Speed = NumberRange.new(1, 2), SpreadAngle = Vector2.new(15, 15), LightEmission = 0 })
	end,
	Cursed = function(att, size)
		emitter(att, { Texture = TEX.Fire, Color = seq(Color3.fromRGB(160, 60, 255)), Rate = 8, Size = fade(size.X * 0.25, 0), Speed = NumberRange.new(1, 2), SpreadAngle = Vector2.new(20, 20) })
	end,
	Fluffy = function(att, size)
		emitter(att, { Texture = TEX.Smoke, Color = seq(Color3.new(1, 1, 1)), Rate = 1.5, Size = fade(0.4, 0.9), Transparency = fade(0.4, 1), Speed = NumberRange.new(0.5, 1), LightEmission = 0.2 })
	end,
	GoldenCrust = function(att, size)
		emitter(att, { Color = seq(Color3.fromRGB(255, 210, 60)), Rate = 8, Size = fade(0.3, 0) })
	end,
}

local INGREDIENT_TRAIT_FX: { [string]: (Attachment, Vector3) -> () } = {
	Golden = function(att)
		emitter(att, { Color = seq(Color3.fromRGB(255, 210, 60)), Rate = 10, Size = fade(0.3, 0) })
	end,
	Fresh = function(att)
		emitter(att, { Color = seq(Color3.fromRGB(110, 230, 110)), Rate = 4, Size = fade(0.25, 0.1), Speed = NumberRange.new(0.5, 1), Acceleration = Vector3.new(0, -1.5, 0), RotSpeed = NumberRange.new(-120, 120) })
	end,
	Organic = function(att)
		emitter(att, { Texture = TEX.Glow, Color = seq(Color3.fromRGB(150, 220, 90)), Rate = 4, Size = fade(0.3, 0), Speed = NumberRange.new(0.3, 0.8) })
	end,
	AnomalyTouched = function(att, size)
		emitter(att, { Texture = TEX.Smoke, Color = seq(Color3.fromRGB(150, 60, 230)), Rate = 4, Size = fade(size.X * 0.3, size.X * 0.7), Transparency = fade(0.4, 1), Speed = NumberRange.new(0.5, 1) })
	end,
}

-- Rarity aura shared by ingredients and cakes.
local function rarityAura(folder: Folder, att: Attachment, size: Vector3, base: BasePart, rarity: number, lite: boolean)
	local tier = Rarity.Tiers[rarity] or Rarity.Tiers[1]
	if rarity >= 3 then
		emitter(att, { Color = seq(tier.Color), Rate = 2 + rarity * (if lite then 0.5 else 1.5), Size = fade(0.25 + rarity * 0.03, 0), Speed = NumberRange.new(0.5, 1.5) })
	end
	if rarity >= 5 and not lite then
		light(att, tier.Color, tier.Glow * 0.6, 6 + tier.Glow)
	end
	if rarity >= Rarity.MYTHIC and not lite then
		emitter(att, { Texture = TEX.Glow, Color = seq(tier.Color), Rate = 3, Size = fade(size.X * 0.9, size.X * 1.4), Transparency = fade(0.6, 1), Speed = NumberRange.new(0) })
		-- Spinning halo rings for Mythic and above (two for Divine/Anomalous).
		for i = 1, (if rarity >= 7 then 2 else 1) do
			local ring = Instance.new("Part")
			ring.Name = "Halo"
			ring.Shape = Enum.PartType.Cylinder
			ring.Size = Vector3.new(0.1, size.X * (1.3 + i * 0.25), size.X * (1.3 + i * 0.25))
			ring.CFrame = CFrame.new(att.WorldPosition - Vector3.new(0, size.Y * 0.45 - i * 0.15, 0)) * CFrame.Angles(math.rad(i * 12), 0, math.rad(90))
			ring.Material = Enum.Material.ForceField
			ring.Color = tier.Color
			ring.CanCollide = false
			ring.CanQuery = false
			ring.CanTouch = false
			ring.Massless = true
			ring.Anchored = base.Anchored
			ring.Parent = folder
			if not base.Anchored then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = base
				weld.Part1 = ring
				weld.Parent = ring
			end
			CollectionService:AddTag(ring, "FxSpin")
			if rarity == 8 then
				CollectionService:AddTag(ring, "FxRainbow")
			end
		end
	end
end

CakeFX.Mutations = MUTATION_FX
CakeFX.CakeTraits = CAKE_TRAIT_FX
CakeFX.IngredientTraits = INGREDIENT_TRAIT_FX
CakeFX.RarityAura = rarityAura

return CakeFX
