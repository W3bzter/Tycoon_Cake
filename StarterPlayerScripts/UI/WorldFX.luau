--!strict
-- Client-side animation for effects the server builds (Services/VFX), driven by
-- CollectionService tags so the server never tweens every frame:
--   FxSpin     anchored part rotates (rings around their axis, shells around Y)
--   FxRainbow  part / light colour cycles through the rainbow
--   FxFlicker  light brightness / beam flickers (fire, electricity)
--   FxBob      model floats up and down and turns (pantry roll pop-ups)
-- Changes are local to this client; the server's values are untouched.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local WorldFX = {}

local spin: { [BasePart]: boolean } = {}
local rainbow: { [Instance]: number } = {} -- instance -> hue offset
local flicker: { [Instance]: number } = {} -- light -> base brightness (beams: 0)
local bob: { [Model]: { origin: CFrame, t0: number } } = {}

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
