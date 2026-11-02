--!strict
-- Client-side animation for effects the server builds (Services/VFX), driven by
-- CollectionService tags so the server never tweens every frame:
--   FxSpin     anchored part rotates (rings around their axis, shells around Y)
--   FxRainbow  part / light colour cycles through the rainbow
--   FxFlicker  light brightness / beam flickers (fire, electricity)
--   FxBob      model floats up and down and turns (pantry roll pop-ups)
--   FxSway     tree / bush leaves sway gently about the plant's base (attribute
--              SwayPivot; World/WorldModels), only near the camera
-- Changes are local to this client; the server's values are untouched.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local WorldFX = {}

local spin: { [BasePart]: boolean } = {}
local rainbow: { [Instance]: number } = {} -- instance -> hue offset
local flicker: { [Instance]: number } = {} -- light -> base brightness (beams: 0)
local bob: { [Model]: { origin: CFrame, t0: number } } = {}
local sway: { [BasePart]: { base: CFrame, pivot: Vector3, phase: number } } = {}
local SWAY_RANGE = 220 -- studs from the camera
local SWAY_ANGLE = math.rad(2.2)

local function track(tag: string, add: (Instance) -> (), remove: (Instance) -> ())
	for _, inst in CollectionService:GetTagged(tag) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)
end

function WorldFX.Mount()
	track("FxSpin", function(inst)
		if inst:IsA("BasePart") then
			spin[inst] = true
		end
	end, function(inst)
		spin[inst :: any] = nil
	end)
	track("FxRainbow", function(inst)
		rainbow[inst] = math.random()
	end, function(inst)
		rainbow[inst] = nil
	end)
	track("FxFlicker", function(inst)
		flicker[inst] = if inst:IsA("PointLight") then inst.Brightness else 0
	end, function(inst)
		flicker[inst] = nil
	end)
	track("FxBob", function(inst)
		if inst:IsA("Model") then
			bob[inst] = { origin = inst:GetPivot(), t0 = os.clock() }
		end
	end, function(inst)
		bob[inst :: any] = nil
	end)

	track("FxSway", function(inst)
		local pivot = inst:GetAttribute("SwayPivot")
		if inst:IsA("BasePart") and typeof(pivot) == "Vector3" then
			sway[inst] = { base = inst.CFrame, pivot = pivot, phase = (pivot.X * 0.13 + pivot.Z * 0.07) % 6.28 }
		end
	end, function(inst)
		sway[inst :: any] = nil
	end)

	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		for part in spin do
			if part.Parent == nil then
				spin[part] = nil
			elseif part.Anchored then -- welded (held) parts would drag the character
				local axis = if part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then CFrame.Angles(dt * 1.8, 0, 0) else CFrame.Angles(0, dt * 1.2, 0)
				part.CFrame *= axis
			end
		end
		for inst, offset in rainbow do
			if inst.Parent == nil then
				rainbow[inst] = nil
			else
				local c = Color3.fromHSV((elapsed * 0.25 + offset) % 1, 0.75, 1)
				if inst:IsA("BasePart") then
					inst.Color = c
				elseif inst:IsA("PointLight") then
					inst.Color = c
				end
			end
		end
		for inst, base in flicker do
			if inst.Parent == nil then
				flicker[inst] = nil
			elseif inst:IsA("PointLight") then
				inst.Brightness = base * (0.4 + math.random() * 0.8)
			elseif inst:IsA("Beam") then
				inst.Enabled = math.random() < 0.55
				inst.CurveSize0 = (math.random() - 0.5) * 6
				inst.CurveSize1 = (math.random() - 0.5) * 6
			end
		end
		local camera = workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		for part, info in sway do
			if part.Parent == nil then
				sway[part] = nil
			elseif (info.pivot - eye).Magnitude < SWAY_RANGE then
				local a = math.sin(elapsed * 1.3 + info.phase) * SWAY_ANGLE
				local around = CFrame.new(info.pivot) * CFrame.Angles(a, 0, a * 0.6)
				part.CFrame = around * CFrame.new(-info.pivot) * info.base
			end
		end
		for model, info in bob do
			if model.Parent == nil then
				bob[model] = nil
			else
				local t = os.clock() - info.t0
				local rise = math.min(1, t / 0.4) * 1.5 -- pops up out of the pantry first
				model:PivotTo(info.origin * CFrame.new(0, rise + math.sin(t * 3) * 0.3, 0) * CFrame.Angles(0, t * 2, 0))
			end
		end
	end)
end

return WorldFX
