--!strict
-- Anomaly creature models built from code: Brute (R15, scaled up), Rat,
-- Gremlin and Phantom (anchored part models; PrimaryPart "Body").

local Players = game:GetService("Players")

local Creatures = {}

local function part(model: Model, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.Anchored = true
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

local function weldTo(base: BasePart, p: BasePart)
	p.Anchored = false
	p.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = p
	weld.Parent = p
end

-- The Brute: a huge R15 bruiser with horns and glowing eyes.
function Creatures.BuildBrute(): Model
	local desc = Instance.new("HumanoidDescription")
	local skin = Color3.fromRGB(110, 70, 80)
	desc.HeadColor = skin
	desc.TorsoColor = Color3.fromRGB(70, 50, 60)
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.LeftLegColor = Color3.fromRGB(50, 40, 45)
	desc.RightLegColor = Color3.fromRGB(50, 40, 45)
	desc.WidthScale = 1.3
	desc.DepthScale = 1.2
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	local npc: Model
	if ok and model then
		npc = model
	else -- fallback: a blocky rig
		npc = Instance.new("Model")
		local root = part(npc, { Name = "HumanoidRootPart", Size = Vector3.new(2, 2, 1), Transparency = 1 })
		root.Anchored = false
		local torso = part(npc, { Name = "UpperTorso", Size = Vector3.new(2.6, 2.4, 1.4), Color = desc.TorsoColor, CFrame = root.CFrame })
		weldTo(root, torso)
		local head = part(npc, { Name = "Head", Size = Vector3.new(1.4, 1.4, 1.4), Color = skin, CFrame = root.CFrame * CFrame.new(0, 1.9, 0) })
		weldTo(root, head)
		local humanoid = Instance.new("Humanoid")
		humanoid.RigType = Enum.HumanoidRigType.R6
		humanoid.HipHeight = 2
		humanoid.Parent = npc
		npc.PrimaryPart = root
	end
	npc.Name = "Brute"
	local head = npc:FindFirstChild("Head") :: BasePart?
	if head then
		for _, side in { -1, 1 } do
			local horn = part(npc, { Name = "Horn", Size = Vector3.new(0.3, 0.9, 0.3), Color = Color3.fromRGB(240, 230, 210), CFrame = head.CFrame * CFrame.new(side * 0.5, 0.75, 0) * CFrame.Angles(0, 0, -side * 0.5) })
			weldTo(head, horn)
			local eye = part(npc, { Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.28, Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon, CFrame = head.CFrame * CFrame.new(side * 0.25, 0.15, -0.55) })
			weldTo(head, eye)
		end
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 50, 50)
		light.Range = 10
		light.Brightness = 2
		light.Parent = head
	end
	npc:ScaleTo(2.2)
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = 10
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	for _, d in npc:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false -- walk through the shop like a ghost-train villain; doors are smashed for show
		end
	end
	return npc
end

-- A rat: anchored parts, moved with Glide. PrimaryPart "Body".
function Creatures.BuildRat(): Model
	local model = Instance.new("Model")
	model.Name = "Rat"
	local fur = Color3.fromRGB(120, 110, 115)
	local body = part(model, { Name = "Body", Size = Vector3.new(1.4, 1, 2), Color = fur, CanTouch = true })
	local function rel(name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?, mat: Enum.Material?)
		part(model, { Name = name, Size = size, CFrame = body.CFrame * offset, Color = color, Shape = shape or Enum.PartType.Block, Material = mat or Enum.Material.SmoothPlastic, CanTouch = true })
	end
	rel("Head", Vector3.new(0.9, 0.8, 0.9), CFrame.new(0, 0.15, -1.2), fur)
	rel("Nose", Vector3.one * 0.25, CFrame.new(0, 0.15, -1.7), Color3.fromRGB(255, 150, 170), Enum.PartType.Ball)
	for _, side in { -1, 1 } do
		rel("Ear", Vector3.new(0.15, 0.5, 0.5), CFrame.new(side * 0.4, 0.65, -1.1), Color3.fromRGB(255, 170, 190), Enum.PartType.Cylinder)
		rel("Eye", Vector3.one * 0.18, CFrame.new(side * 0.25, 0.35, -1.6), Color3.fromRGB(255, 40, 40), Enum.PartType.Ball, Enum.Material.Neon)
	end
	rel("Tail", Vector3.new(0.15, 0.15, 1.8), CFrame.new(0, 0, 1.8) * CFrame.Angles(0.4, 0, 0), Color3.fromRGB(255, 170, 190))
	model.PrimaryPart = body
	return model
end

-- A gremlin: small green imp with big ears. PrimaryPart "Body".
function Creatures.BuildGremlin(): Model
	local model = Instance.new("Model")
	model.Name = "Gremlin"
	local skin = Color3.fromRGB(90, 200, 90)
	local body = part(model, { Name = "Body", Size = Vector3.new(1.6, 1.8, 1.2), Color = skin })
	part(model, { Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, CFrame = body.CFrame * CFrame.new(0, 1.6, 0), Color = skin })
	for _, side in { -1, 1 } do
		part(model, { Name = "Ear", Size = Vector3.new(1.4, 0.2, 0.7), CFrame = body.CFrame * CFrame.new(side * 1.2, 1.9, 0) * CFrame.Angles(0, 0, side * 0.5), Color = skin })
		part(model, { Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.45, CFrame = body.CFrame * CFrame.new(side * 0.35, 1.75, -0.6), Color = Color3.fromRGB(255, 240, 60), Material = Enum.Material.Neon })
		part(model, { Name = "Leg", Size = Vector3.new(0.4, 0.9, 0.4), CFrame = body.CFrame * CFrame.new(side * 0.4, -1.3, 0), Color = Color3.fromRGB(60, 140, 60) })
	end
	part(model, { Name = "Grin", Size = Vector3.new(0.8, 0.12, 0.1), CFrame = body.CFrame * CFrame.new(0, 1.3, -0.78), Color = Color3.fromRGB(30, 30, 30) })
	part(model, { Name = "Wrench", Size = Vector3.new(0.25, 1.6, 0.25), CFrame = body.CFrame * CFrame.new(1.1, 0, -0.3) * CFrame.Angles(0, 0, -0.6), Color = Color3.fromRGB(170, 170, 180), Material = Enum.Material.Metal })
	model.PrimaryPart = body
	return model
end

-- A phantom: translucent glowing sheet ghost. PrimaryPart "Body".
function Creatures.BuildPhantom(): Model
	local model = Instance.new("Model")
	model.Name = "Phantom"
	local body = part(model, { Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.one * 4, Color = Color3.fromRGB(220, 235, 255), Material = Enum.Material.Neon, Transparency = 0.35 })
	part(model, { Name = "Skirt", Size = Vector3.new(3.6, 3, 3.6), CFrame = body.CFrame * CFrame.new(0, -2, 0), Color = Color3.fromRGB(220, 235, 255), Material = Enum.Material.Neon, Transparency = 0.45 })
	for _, side in { -1, 1 } do
		part(model, { Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 1.1, 0.4), CFrame = body.CFrame * CFrame.new(side * 0.7, 0.4, -1.8), Color = Color3.fromRGB(10, 10, 30), Transparency = 0 })
	end
	part(model, { Name = "Mouth", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 1.2, 0.4), CFrame = body.CFrame * CFrame.new(0, -0.6, -1.85), Color = Color3.fromRGB(10, 10, 30) })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(170, 200, 255)
	light.Range = 16
	light.Brightness = 3
	light.Parent = body
	model.PrimaryPart = body
	return model
end

return Creatures
