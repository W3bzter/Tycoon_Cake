--!strict
-- Builds the placeholder world from code so it lives in git, not the place file.
-- Workspace.Plots.Plot1..N  (Base, Sign, Spawn)
-- Workspace.Street          (Road, CustomerSpawn, CustomerDespawn)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PlotLayout = require(Shared:WaitForChild("PlotLayout"))

local WorldBuilder = {}

-- Visibility ------------------------------------------------------------------
-- Hidden things keep their original look in attributes so they can be restored.

local function setPartVisible(p: BasePart, visible: boolean)
	if p:GetAttribute("OrigTransparency") == nil then
		p:SetAttribute("OrigTransparency", p.Transparency)
		p:SetAttribute("OrigCanCollide", p.CanCollide)
	end
	p.Transparency = if visible then p:GetAttribute("OrigTransparency") :: number else 1
	p.CanCollide = if visible then p:GetAttribute("OrigCanCollide") :: boolean else false
	p.CanTouch = visible
	p.CanQuery = visible
end

function WorldBuilder.SetVisible(root: Instance, visible: boolean)
	if root:IsA("BasePart") then
		setPartVisible(root, visible)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			setPartVisible(d, visible)
		elseif d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			d.Enabled = visible
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = if visible then 0 else 1
		end
	end
	root:SetAttribute("Visible", visible)
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function buildSign(plot: Model, base: Part)
	local size = Config.PlotSize
	local sign = part({
		Name = "Sign",
		Size = Vector3.new(14, 6, 1),
		CFrame = base.CFrame * CFrame.new(-size.X / 2 + 10, 3.5, size.Z / 2 - 1),
		Color = Color3.fromRGB(110, 70, 40),
		Material = Enum.Material.Wood,
		Parent = plot,
	})

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Back -- faces the street (+Z)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = sign

	local label = Instance.new("TextLabel")
	label.Name = "OwnerLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 240, 210)
	label.Text = "Unclaimed Bakery"
	label.Parent = gui
end

local function buildUpgrades(plot: Model, base: Part)
	local floor = base.CFrame * CFrame.new(0, base.Size.Y / 2, 0)
	local items = plot:FindFirstChild("Items") :: Folder
	local buttons = plot:FindFirstChild("Buttons") :: Folder

	for index, upgrade in PlotLayout.Upgrades do
		local item = Instance.new("Model")
		item.Name = upgrade.Id
		for _, spec in upgrade.Parts do
			part({
				Name = spec.Name,
				Size = spec.Size,
				CFrame = floor * CFrame.new(spec.Offset),
				Color = spec.Color,
				Material = spec.Material or Enum.Material.SmoothPlastic,
				Shape = spec.Shape or Enum.PartType.Block,
				Transparency = spec.Transparency or 0,
				Parent = item,
			})
		end
		item.Parent = items
		WorldBuilder.SetVisible(item, false)

		local button = part({
			Name = upgrade.Id,
			Size = Vector3.new(6, 0.4, 6),
			CFrame = floor * CFrame.new(PlotLayout.ButtonOffset(index)),
			Color = Color3.fromRGB(90, 220, 110),
			Material = Enum.Material.Neon,
			Parent = buttons,
		})
		button:SetAttribute("UpgradeId", upgrade.Id)

		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(160, 50)
		gui.StudsOffset = Vector3.new(0, 3, 0)
		gui.MaxDistance = 60
		gui.Parent = button
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Text = `{upgrade.DisplayName}\n${upgrade.Price}`
		label.Parent = gui

		WorldBuilder.SetVisible(button, false)
	end
end

local function buildPlot(index: number, parent: Folder)
	local size = Config.PlotSize
	local x = (index - (Config.PlotCount + 1) / 2) * Config.PlotSpacing

	local plot = Instance.new("Model")
	plot.Name = `Plot{index}`
	plot:SetAttribute("PlotIndex", index)

	local base = part({
		Name = "Base",
		Size = size,
		CFrame = CFrame.new(x, size.Y / 2, Config.PlotRowZ),
		Color = Color3.fromRGB(235, 215, 180),
		Material = Enum.Material.WoodPlanks,
		Parent = plot,
	})
	plot.PrimaryPart = base

	part({
		Name = "Spawn",
		Size = Vector3.new(8, 0.2, 8),
		CFrame = base.CFrame * CFrame.new(0, size.Y / 2 + 0.1, size.Z / 2 - 8),
		Color = Color3.fromRGB(255, 170, 200),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = plot,
	})

	buildSign(plot, base)

	-- Containers later phases fill in.
	for _, name in { "Items", "Buttons" } do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = plot
	end
	buildUpgrades(plot, base)

	plot.Parent = parent
end

local function buildStreet()
	local street = Instance.new("Folder")
	street.Name = "Street"

	local half = Config.StreetLength / 2
	part({
		Name = "Road",
		Size = Vector3.new(Config.StreetLength, 0.2, Config.StreetWidth),
		CFrame = CFrame.new(0, 0.1, Config.StreetZ),
		Color = Color3.fromRGB(70, 70, 75),
		Material = Enum.Material.Asphalt,
		Parent = street,
	})

	for _, info in { { "CustomerSpawn", -half + 10 }, { "CustomerDespawn", half - 10 } } do
		part({
			Name = info[1],
			Size = Vector3.new(4, 0.2, 4),
			CFrame = CFrame.new(info[2] :: number, 0.3, Config.StreetZ),
			Color = Color3.fromRGB(120, 200, 255),
			Transparency = 0.5,
			CanCollide = false,
			Parent = street,
		})
	end

	street.Parent = workspace
end

function WorldBuilder.Init()
	for _, name in { "Plots", "Street" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	for i = 1, Config.PlotCount do
		buildPlot(i, plots)
	end
	plots.Parent = workspace

	buildStreet()
end

return WorldBuilder
