--!strict
-- World effects built from code (server-side, so everyone sees them). Uses only
-- built-in rbxasset:// particle textures, so no uploads are needed.
--
--   VFX.ApplyCake(model, info, light?)       rarity ring + cake traits + mutation
--   VFX.ApplyIngredient(model, item, light?)  rarity aura + ingredient traits
--   VFX.Burst(position, kind)                one-shot effects (explosion, repair, ...)
--   VFX.Pillar(position, color, seconds)     a beam of light (Mythic+ rolls, rebirth)
--
-- Everything goes in a Folder named "FX" inside the model, so calling Apply again
-- replaces the old effects. Animation is done on the client (UI/WorldFX) via
-- CollectionService tags: FxSpin (rotate), FxRainbow (hue cycle), FxFlicker
-- (lights/beams flicker), FxBob (float up and down).

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))

local VFX = {}

local TEX = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
	Vortex = "rbxasset://textures/particles/forcefield_vortex_main.dds",
}

local function seq(c: Color3): ColorSequence
	return ColorSequence.new(c)
end

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 190, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 255, 90)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(90, 255, 120)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(80, 160, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 90, 255)),
})

local function fade(a: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

type EmitterProps = { [string]: any }

-- A ParticleEmitter with sensible defaults; `p` overrides anything.
local function emitter(parent: Instance, p: EmitterProps): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX.Sparkle
	e.LightEmission = 0.8
	e.LightInfluence = 0
	e.Rate = 6
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(1, 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = fade(0.4, 0)
	e.Transparency = fade(0.1, 1)
	e.Drag = 1
	for k, v in p do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function light(parent: Instance, color: Color3, brightness: number, range: number, flicker: boolean?): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = parent
	if flicker then
		CollectionService:AddTag(l, "FxFlicker")
	end
	return l
end

local function anchorPart(model: Model): BasePart?
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

-- The model's FX folder (fresh) plus a centre attachment and the model size.
type Root = { folder: Folder, att: Attachment, size: Vector3, base: BasePart }
local function fxRoot(model: Model): Root?
	local base = anchorPart(model)
	if not base then
		return nil
	end
	local old = model:FindFirstChild("FX")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "FX"
	folder.Parent = model
	local cf, size = model:GetBoundingBox()
	local att = Instance.new("Attachment")
	att.Name = "FxCenter"
	att.Parent = base -- parent first: WorldCFrame is relative to the parent part
	att.WorldCFrame = CFrame.new(cf.Position)
	-- The attachment lives on a model part; remember to clean it up with the folder.
	folder.Destroying:Connect(function()
		att:Destroy()
	end)
	return { folder = folder, att = att, size = size, base = base }
end

-- A non-colliding shell around the model (moves with it: anchored like the base
-- part, or welded to it when the model is a held tool).
local function shell(folder: Folder, base: BasePart, center: Vector3, size: Vector3, props: { [string]: any }): Part
	local s = Instance.new("Part")
	s.Name = "Shell"
	s.Shape = Enum.PartType.Ball
	local d = math.max(size.X, size.Z) * 1.25
	s.Size = Vector3.new(d, d, d)
	s.CFrame = CFrame.new(center)
	s.CanCollide = false
	s.CanQuery = false
	s.CanTouch = false
	s.Massless = true
	s.CastShadow = false
	s.Anchored = base.Anchored
	for k, v in props do
		(s :: any)[k] = v
	end
	s.Parent = folder
	if not base.Anchored then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = base
		weld.Part1 = s
		weld.Parent = s
	end
	return s
end

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

-- Public -----------------------------------------------------------------------------------

-- `lite` = fewer particles and no shells (held tools, conveyor/rack cakes).
function VFX.ApplyCake(model: Model, info: Rarity.CakeInfo, lite: boolean?)
	local root = fxRoot(model)
	if not root then
		return
	end
	local folder, att, size, base = root.folder, root.att, root.size, root.base
	local isLite = lite == true
	rarityAura(folder, att, size, base, info.Rarity, isLite)
	for _, trait in info.Traits or {} do
		local fx = CAKE_TRAIT_FX[trait]
		if fx then
			fx(att, size)
		end
	end
	if info.Mutation and MUTATION_FX[info.Mutation] then
		MUTATION_FX[info.Mutation](folder, att, size, base, isLite)
	end
end

function VFX.ApplyIngredient(model: Model, item: Rarity.Item, lite: boolean?)
	local root = fxRoot(model)
	if not root then
		return
	end
	local folder, att, size, base = root.folder, root.att, root.size, root.base
	rarityAura(folder, att, size, base, item.Rarity, lite == true)
	for _, trait in item.Traits do
		local fx = INGREDIENT_TRAIT_FX[trait]
		if fx then
			fx(att, size)
		end
	end
end

-- A temporary invisible anchor part at `position` for one-shot effects.
local function anchorAt(position: Vector3, lifetime: number): (Part, Attachment)
	local p = Instance.new("Part")
	p.Name = "FxAnchor"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.CFrame = CFrame.new(position)
	p.Parent = workspace
	local att = Instance.new("Attachment")
	att.Parent = p
	Debris:AddItem(p, lifetime)
	return p, att
end

local BURSTS: { [string]: { Color: Color3, Count: number, Texture: string, Speed: number, Size: number } } = {
	Explosion = { Color = Color3.fromRGB(255, 140, 40), Count = 60, Texture = TEX.Fire, Speed = 25, Size = 3 },
	Smoke = { Color = Color3.fromRGB(70, 70, 70), Count = 30, Texture = TEX.Smoke, Speed = 8, Size = 5 },
	Repair = { Color = Color3.fromRGB(120, 255, 160), Count = 40, Texture = TEX.Sparkle, Speed = 10, Size = 0.8 },
	Smash = { Color = Color3.fromRGB(200, 180, 160), Count = 35, Texture = TEX.Smoke, Speed = 14, Size = 2 },
	Catch = { Color = Color3.fromRGB(255, 230, 90), Count = 35, Texture = TEX.Sparkle, Speed = 12, Size = 1 },
	Poof = { Color = Color3.fromRGB(180, 120, 255), Count = 30, Texture = TEX.Smoke, Speed = 8, Size = 2 },
	Rebirth = { Color = Color3.fromRGB(255, 255, 255), Count = 120, Texture = TEX.Sparkle, Speed = 35, Size = 1.5 },
	Mutation = { Color = Color3.fromRGB(200, 140, 255), Count = 50, Texture = TEX.Sparkle, Speed = 14, Size = 1 },
}

function VFX.Burst(position: Vector3, kind: string, color: Color3?)
	local def = BURSTS[kind] or BURSTS.Catch
	local _, att = anchorAt(position, 4)
	local e = emitter(att, {
		Texture = def.Texture,
		Color = seq(color or def.Color),
		Rate = 0,
		Speed = NumberRange.new(def.Speed * 0.5, def.Speed),
		Size = fade(def.Size, 0),
		Lifetime = NumberRange.new(0.6, 1.4),
		Drag = 3,
	})
	e:Emit(def.Count)
	if kind == "Explosion" or kind == "Rebirth" or kind == "Mutation" then
		local l = light(att, color or def.Color, 6, 24)
		task.delay(0.4, function()
			l.Brightness = 2
		end)
	end
end

function VFX.Pillar(position: Vector3, color: Color3, seconds: number)
	local p, bottom = anchorAt(position, seconds)
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 60, 0)
	top.Parent = p
	local beam = Instance.new("Beam")
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.Color = seq(color)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0 = 4
	beam.Width1 = 7
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	beam.FaceCamera = true
	beam.Parent = p
	emitter(bottom, { Color = seq(color), Rate = 30, Size = fade(0.6, 0), Speed = NumberRange.new(8, 16), SpreadAngle = Vector2.new(10, 10), Lifetime = NumberRange.new(1, 2) })
	light(bottom, color, 5, 20)
end

return VFX
