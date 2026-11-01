--!strict
-- Warm, sunny, saturated look. Reuses the place's existing lighting objects
-- (by class) so nothing is duplicated, and creates any that are missing.
-- Lighting.Technology can't be set from scripts; set it to Future in Studio.

local Lighting = game:GetService("Lighting")

local LightingSetup = {}

local function ensure<T>(className: string): T
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		return existing :: any
	end
	local created = Instance.new(className :: any)
	created.Parent = Lighting
	return created :: any
end

function LightingSetup.Init()
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(120, 105, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 160, 175)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.ShadowSoftness = 0.4
	Lighting.ExposureCompensation = -0.1 -- pastels blow out to white without this

	local sky = ensure("Sky") :: Sky
	sky.SunAngularSize = 18
	sky.CelestialBodiesShown = true

	local atmosphere = ensure("Atmosphere") :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(255, 225, 205)
	atmosphere.Decay = Color3.fromRGB(255, 170, 190)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.2

	local bloom = ensure("BloomEffect") :: BloomEffect
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.6

	local sunRays = ensure("SunRaysEffect") :: SunRaysEffect
	sunRays.Intensity = 0.06
	sunRays.Spread = 0.8

	local cc = ensure("ColorCorrectionEffect") :: ColorCorrectionEffect
	cc.Saturation = 0.22
	cc.Contrast = 0.06
	cc.Brightness = 0.02
	cc.TintColor = Color3.fromRGB(255, 248, 238)

	-- Depth of field blurs the bright cartoony scene; keep it off.
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.Enabled = false
	end
end

return LightingSetup
