--!strict
-- Building blocks for world effects: built-in particle textures, emitters,
-- lights, the per-model FX root (folder + centre attachment) and shells.

local CollectionService = game:GetService("CollectionService")

local FxKit = {}

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

FxKit.TEX = TEX
FxKit.RAINBOW = RAINBOW
FxKit.seq = seq
FxKit.fade = fade
FxKit.emitter = emitter
FxKit.light = light
FxKit.fxRoot = fxRoot
FxKit.shell = shell

return FxKit
