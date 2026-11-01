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

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))

local CakeFX = require(script.Parent.CakeFX)
local FxKit = require(script.Parent.FxKit)
local TEX, seq, fade, emitter, light, fxRoot = FxKit.TEX, FxKit.seq, FxKit.fade, FxKit.emitter, FxKit.light, FxKit.fxRoot
local MUTATION_FX, CAKE_TRAIT_FX, INGREDIENT_TRAIT_FX, rarityAura = CakeFX.Mutations, CakeFX.CakeTraits, CakeFX.IngredientTraits, CakeFX.RarityAura

local VFX = {}

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
