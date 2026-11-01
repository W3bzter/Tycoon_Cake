--!strict
-- Loads art templates saved in the PLACE FILE (not git) under ServerStorage.Assets:
--   Assets/Ingredients/<Flour|Eggs|Sugar|Butter|Milk|Strawberries|Chocolate>
--   Assets/Cakes/<Vanilla|Chocolate|Strawberry|Rainbow>
--   Assets/Props/<BatterBowl>
-- Each template is a MeshPart or Model. If one is missing (fresh place, git
-- clone, unsaved Studio session) a primitive fallback in the same colours is
-- built instead, so the game always works. Save the place (Ctrl+S) after
-- adding or changing templates.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Recipes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Recipes"))

local Assets = {}

Assets.Expected = {
	Ingredients = Recipes.IngredientOrder,
	Cakes = Recipes.CakeOrder,
	Props = { "BatterBowl" },
}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function upright(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.rad(90))
end

-- Fallbacks --------------------------------------------------------------------

local function fallbackIngredient(name: string, model: Model)
	local info = Recipes.Ingredients[name]
	local color = info and info.Color or Color3.new(1, 1, 1)
	if name == "Eggs" then
		part({ Name = "Carton", Size = Vector3.new(1.8, 0.4, 1), Color = Color3.fromRGB(200, 170, 130), Parent = model })
		for i = 0, 2 do
			part({ Name = "Egg", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, CFrame = CFrame.new(-0.55 + i * 0.55, 0.35, 0), Color = color, Parent = model })
		end
	elseif name == "Milk" then
		part({ Name = "Bottle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 0.8, 0.8), CFrame = upright(CFrame.new()), Color = color, Parent = model })
		part({ Name = "Cap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 0.5, 0.5), CFrame = upright(CFrame.new(0, 0.9, 0)), Color = Color3.fromRGB(120, 180, 255), Parent = model })
	elseif name == "Strawberries" then
		part({ Name = "Basket", Size = Vector3.new(1.6, 0.6, 1.1), Color = Color3.fromRGB(200, 150, 90), Parent = model })
		for i = 0, 2 do
			part({ Name = "Berry", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.55, CFrame = CFrame.new(-0.5 + i * 0.5, 0.45, 0), Color = color, Parent = model })
		end
	elseif name == "Chocolate" then
		part({ Name = "Bar", Size = Vector3.new(1.6, 0.35, 0.9), Color = color, Parent = model })
		part({ Name = "Wrapper", Size = Vector3.new(0.8, 0.4, 0.95), CFrame = CFrame.new(0.4, 0, 0), Color = Color3.fromRGB(220, 50, 60), Parent = model })
	elseif name == "Butter" then
		part({ Name = "Stick", Size = Vector3.new(1.4, 0.6, 0.7), Color = color, Parent = model })
	else -- Flour, Sugar: sacks
		part({ Name = "Sack", Size = Vector3.new(1.2, 1.4, 0.9), Color = color, Parent = model })
		part({ Name = "Tie", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, CFrame = CFrame.new(0, 0.85, 0), Color = color, Parent = model })
	end
end

local function fallbackCake(name: string, model: Model)
	local info = Recipes.Cakes[name]
	local frosting = info and info.Color or Color3.new(1, 1, 1)
	local sponge = if name == "Chocolate" then Color3.fromRGB(90, 50, 35) else Color3.fromRGB(240, 200, 140)
	part({ Name = "Plate", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 2.4, 2.4), CFrame = upright(CFrame.new(0, -0.8, 0)), Color = Color3.new(1, 1, 1), Parent = model })
	if name == "Rainbow" then
		local layers = { Color3.fromRGB(255, 120, 140), Color3.fromRGB(255, 210, 110), Color3.fromRGB(140, 220, 150), Color3.fromRGB(130, 180, 255) }
		for i, c in layers do
			part({ Name = "Layer", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 2, 2), CFrame = upright(CFrame.new(0, -0.55 + (i - 1) * 0.4, 0)), Color = c, Parent = model })
		end
		part({ Name = "Frosting", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2.1, 2.1), CFrame = upright(CFrame.new(0, 1.15, 0)), Color = Color3.new(1, 1, 1), Parent = model })
		for i = -1, 1 do
			part({ Name = "Candle", Size = Vector3.new(0.15, 0.6, 0.15), CFrame = CFrame.new(i * 0.5, 1.55, 0), Color = Color3.fromRGB(255, 180, 220), Parent = model })
			local flame = part({ Name = "Flame", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.25, CFrame = CFrame.new(i * 0.5, 1.95, 0), Color = Color3.fromRGB(255, 200, 80), Parent = model })
			flame.Material = Enum.Material.Neon
		end
	else
		part({ Name = "Sponge", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 2, 2), CFrame = upright(CFrame.new(0, -0.2, 0)), Color = sponge, Parent = model })
		part({ Name = "Frosting", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.45, 2.15, 2.15), CFrame = upright(CFrame.new(0, 0.45, 0)), Color = frosting, Parent = model })
		local topping = if name == "Strawberry" then Color3.fromRGB(235, 50, 70) elseif name == "Chocolate" then Color3.fromRGB(70, 35, 25) else Color3.fromRGB(230, 30, 60)
		part({ Name = "Topping", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, CFrame = CFrame.new(0, 0.9, 0), Color = topping, Parent = model })
	end
end

local function fallbackProp(name: string, model: Model)
	if name == "BatterBowl" then
		part({ Name = "Bowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 1.8, 1.8), CFrame = upright(CFrame.new()), Color = Color3.fromRGB(150, 236, 200), Parent = model })
		part({ Name = "Batter", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 1.5, 1.5), CFrame = upright(CFrame.new(0, 0.45, 0)), Color = Color3.fromRGB(255, 240, 200), Parent = model })
	end
end

local FALLBACKS: { [string]: (string, Model) -> () } = {
	Ingredients = fallbackIngredient,
	Cakes = fallbackCake,
	Props = fallbackProp,
}

-- Public --------------------------------------------------------------------------

function Assets.HasTemplate(category: string, name: string): boolean
	local root = ServerStorage:FindFirstChild("Assets")
	local folder = root and root:FindFirstChild(category)
	return folder ~= nil and folder:FindFirstChild(name) ~= nil
end

-- Returns a fresh Model (PrimaryPart set, all parts unanchored and non-colliding).
-- The caller decides how to place it: Anchor() for world props, AttachTo() for tools.
function Assets.Clone(category: string, name: string): Model
	local model: Model
	local root = ServerStorage:FindFirstChild("Assets")
	local folder = root and root:FindFirstChild(category)
	local template = folder and folder:FindFirstChild(name)

	if template and template:IsA("Model") then
		model = template:Clone()
	elseif template and template:IsA("BasePart") then
		model = Instance.new("Model")
		template:Clone().Parent = model
	else
		model = Instance.new("Model")
		local build = FALLBACKS[category]
		if build then
			build(name, model)
		end
	end
	model.Name = name

	local biggest: BasePart? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
			d:Destroy() -- never run code that came with an asset
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.Massless = true
			if not biggest or d.Size.Magnitude > (biggest :: BasePart).Size.Magnitude then
				biggest = d
			end
		end
	end
	model.PrimaryPart = biggest
	return model
end

-- Anchors a cloned model so its bottom centre sits at `cf`.
function Assets.Anchor(model: Model, cf: CFrame, parent: Instance)
	local boxCf, size = model:GetBoundingBox()
	local pivotOffset = boxCf:ToObjectSpace(model:GetPivot())
	model:PivotTo(cf * CFrame.new(0, size.Y / 2, 0) * pivotOffset)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model.Parent = parent
end

-- Welds a cloned model onto a tool Handle, centred on it.
function Assets.AttachTo(model: Model, handle: BasePart)
	local boxCf = model:GetBoundingBox()
	model:PivotTo(handle.CFrame * boxCf:ToObjectSpace(model:GetPivot()))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = d
			weld.Parent = d
		end
	end
	model.Parent = handle
end

return Assets
