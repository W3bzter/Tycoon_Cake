--!strict
-- Builds the world from code so it lives in git, not the place file.
-- Workspace.Plots.PlotN  (Base, Tiles, Fence, Entrance(Sign), Spawn, Items, Placed)
-- Workspace.Street       (Road, sidewalks, props, CustomerSpawn, CustomerDespawn)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PlotLayout = require(Shared:WaitForChild("PlotLayout"))

local Services = script:FindFirstAncestor("Services") :: Folder
local ItemBuilders = require(Services.World.ItemBuilders)
local Style = require(Services.World.Style)

local P = Style.Palette
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
	p.CanQuery = visible and p:GetAttribute("OrigCanQuery") ~= false -- roofs are never clickable
end

function WorldBuilder.SetVisible(root: Instance, visible: boolean)
	if root:IsA("BasePart") then
		setPartVisible(root, visible)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			setPartVisible(d, visible)
		elseif d:IsA("ProximityPrompt") then
			-- Only ever switched off here: Core/Prompts decides when each prompt shows.
			if not visible then
				d.Enabled = false
			end
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			d.Enabled = visible
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = if visible then 0 else 1
		elseif d:IsA("Light") then
			d.Enabled = visible
		end
	end
	root:SetAttribute("Visible", visible)
end

-- Plot ------------------------------------------------------------------------

local function buildEntrance(plot: Model, floor: CFrame)
	local entrance = Instance.new("Model")
	entrance.Name = "Entrance"
	local B = Config.Building
	local postX, z = B.DoorHalf + 2, B.FrontZ - 1
	for _, x in { -postX, postX } do
		Style.Cylinder("Post", 11, 1.4, floor * CFrame.new(x, 5.5, z), P.White, entrance)
		Style.Ball("PostTop", 2, floor * CFrame.new(x, 11.4, z), P.HotPink, entrance)
	end
	local board = Style.RoundedBox("Sign", Vector3.new(postX * 2 + 2, 3.6, 1), floor * CFrame.new(0, 9.4, z), P.HotPink, entrance, 0.6)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Back -- +Z, towards the street
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "OwnerLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = P.White
	label.Text = "Unclaimed Bakery"
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.Parent = label

	entrance.Parent = plot
end

-- Floor tiles and patio fence for one size stage (`parent` = the Walls item's
-- Stage<n> model, so they show with that stage's walls).
local function buildFloor(parent: Instance, floor: CFrame, halfX: number, backZ: number)
	-- Pink checker tiles (8 studs) inside the building footprint.
	local B = Config.Building
	local tiles = Instance.new("Model")
	tiles.Name = "Tiles"
	local countX = math.floor(halfX * 2 / 8)
	local countZ = math.floor((B.FacadeZ + 0.5 - backZ) / 8)
	for ix = 0, countX - 1 do
		for iz = 0, countZ - 1 do
			if (ix + iz) % 2 == 0 then
				Style.Part({
					Name = "Tile",
					Size = Vector3.new(8, 0.05, 8),
					CFrame = floor * CFrame.new(-halfX + 4 + ix * 8, 0.025, backZ + 4 + iz * 8),
					Color = P.Pink,
					CanCollide = false,
					Parent = tiles,
				})
			end
		end
	end
	tiles.Parent = parent

	-- Low picket fence along the patio sides (plot edges, every stage).
	local fence = Instance.new("Model")
	fence.Name = "Fence"
	local z0, z1 = B.FacadeZ + 0.5, B.FrontZ
	for _, x in { -(B.HalfX - 0.4), B.HalfX - 0.4 } do -- the patio is always full plot width
		for z = z0, z1, 4 do
			Style.RoundedBox("Picket", Vector3.new(0.8, 3, 0.8), floor * CFrame.new(x, 1.5, z), P.White, fence, 0.35)
		end
		Style.Part({ Name = "Rail", Size = Vector3.new(0.4, 0.5, z1 - z0), CFrame = floor * CFrame.new(x, 2.2, (z0 + z1) / 2), Color = P.White, Parent = fence })
	end
	fence.Parent = parent
end

local function buildUpgrades(plot: Model, floor: CFrame)
	local items = plot:FindFirstChild("Items") :: Folder

	for _, upgrade in PlotLayout.Upgrades do
		local item = Instance.new("Model")
		item.Name = upgrade.Id
		local builder = ItemBuilders[upgrade.Id]
		if builder then
			builder(floor, item)
		else
			warn(`[WorldBuilder] No ItemBuilder for upgrade {upgrade.Id}`)
		end
		if upgrade.Id == "Walls" then
			-- A new plot is just the bare floor: tiles, fence and entrance arch
			-- arrive with the building.
			for i, st in Config.Building.Stages do
				buildFloor(item:FindFirstChild(`Stage{i}`) or item, floor, st.HalfX, st.BackZ)
			end
			buildEntrance(item, floor)
		end
		item.Parent = items
		WorldBuilder.SetVisible(item, false)
	end
end

-- Plot `index` (1..PlotCount*PlotRows): the near row faces +Z, the far row
-- (indices after PlotCount) faces -Z; both face the street. Everything on a plot
-- is built relative to its floor, so it works either way round.
local function plotCFrame(index: number): CFrame
	local column = (index - 1) % Config.PlotCount + 1
	local x = (column - (Config.PlotCount + 1) / 2) * Config.PlotSpacing
	local y = Config.PlotSize.Y / 2
	if index <= Config.PlotCount then
		return CFrame.new(x, y, Config.PlotRowZ)
	end
	return CFrame.new(x, y, Config.PlotRowZB) * CFrame.Angles(0, math.pi, 0)
end
WorldBuilder.PlotCFrame = plotCFrame

local function buildPlot(index: number, parent: Folder)
	local size = Config.PlotSize

	local plot = Instance.new("Model")
	plot.Name = `Plot{index}`
	plot:SetAttribute("PlotIndex", index)

	local base = Style.Part({
		Name = "Base",
		Size = size,
		CFrame = plotCFrame(index),
		Color = P.Vanilla,
		Material = Enum.Material.WoodPlanks,
		Parent = plot,
	})
	plot.PrimaryPart = base
	local floor = base.CFrame * CFrame.new(0, size.Y / 2, 0)

	local spawnPad = Style.Cylinder("Spawn", 0.2, 7, floor * CFrame.new(0, 0.1, (Config.Building.FacadeZ + Config.Building.FrontZ) / 2), P.Lilac, plot)
	spawnPad.CanCollide = false

	for _, name in { "Items" } do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = plot
	end

	-- Floating owner tag over the spawn pad (always visible, even on a bare plot).
	local tag = Style.Billboard(spawnPad, { "Unclaimed Bakery" }, {
		Name = "OwnerTag",
		Width = 12,
		Height = 1.8,
		Offset = Vector3.new(0, 7, 0),
		MaxDistance = 150,
		Stroke = P.Lilac,
	})
	local tagLabel = tag:FindFirstChild("Line1", true)
	if tagLabel then
		tagLabel.Name = "OwnerLabel"
	end

	buildUpgrades(plot, floor)

	plot.Parent = parent
end

-- Street ------------------------------------------------------------------------
-- Near-row plot fronts are at world Z = PlotRowZ + PlotSize.Z / 2 (-10). From there
-- towards +Z: sidewalk (-10..5), road (5..25), far sidewalk (25..40) with the bus
-- stops, then the far row's fronts (Config.PlotRowZB - 60 = 40).

local ROAD_MIN, ROAD_MAX = 5, 25

local function buildBusStop(x: number, parent: Instance, name: string)
	local stop = Instance.new("Model")
	stop.Name = name .. "Stop"
	local cf = CFrame.new(x, 0.6, 30)
	Style.RoundedBox("Roof", Vector3.new(10, 0.6, 5), cf * CFrame.new(0, 8, 0), P.Mint, stop, 0.6)
	for _, px in { -4.4, 4.4 } do
		Style.Cylinder("Post", 8, 0.5, cf * CFrame.new(px, 4, -2), P.White, stop)
	end
	Style.Bench(cf * CFrame.new(0, 0, -1) * CFrame.Angles(0, math.pi, 0), stop, P.Butter)
	Style.Billboard(stop:FindFirstChild("Roof") :: BasePart, { "🚌 Bus Stop" }, { Width = 6, Height = 1.4, Offset = Vector3.new(0, 1.6, 0), MaxDistance = 120 })
	stop.Parent = parent

	-- Invisible marker the customer code uses (names must stay the same).
	Style.Part({
		Name = name,
		Size = Vector3.new(4, 0.2, 4),
		CFrame = CFrame.new(x, 0.7, ROAD_MAX + 2),
		Transparency = 1,
		CanCollide = false,
		Parent = parent,
	})
end

local function buildStreet()
	local street = Instance.new("Folder")
	street.Name = "Street"
	local length = Config.StreetLength
	local half = length / 2

	Style.Part({
		Name = "Road",
		Size = Vector3.new(length, 0.2, ROAD_MAX - ROAD_MIN),
		CFrame = CFrame.new(0, 0.1, (ROAD_MIN + ROAD_MAX) / 2),
		Color = P.Asphalt,
		Parent = street,
	})
	Style.Part({ Name = "Sidewalk", Size = Vector3.new(length, 0.6, 15), CFrame = CFrame.new(0, 0.3, -2.5), Color = P.Sidewalk, Parent = street })
	Style.Part({ Name = "FarSidewalk", Size = Vector3.new(length, 0.6, 15), CFrame = CFrame.new(0, 0.3, 32.5), Color = P.Sidewalk, Parent = street }) -- up to the far row (z 40)
	for _, z in { ROAD_MIN - 0.3, ROAD_MAX + 0.3 } do
		Style.Part({ Name = "Curb", Size = Vector3.new(length, 0.7, 0.6), CFrame = CFrame.new(0, 0.35, z), Color = P.White, Parent = street })
	end

	local marks = Instance.new("Model")
	marks.Name = "Markings"
	for x = -half + 7, half - 7, 14 do
		Style.Part({ Name = "Dash", Size = Vector3.new(6, 0.05, 0.6), CFrame = CFrame.new(x, 0.22, 15), Color = P.Butter, CanCollide = false, Parent = marks })
	end
	-- Zebra crossing in front of each plot.
	for i = 1, Config.PlotCount do
		local px = (i - (Config.PlotCount + 1) / 2) * Config.PlotSpacing
		for s = -3, 3 do
			Style.Part({
				Name = "Zebra",
				Size = Vector3.new(1.4, 0.06, ROAD_MAX - ROAD_MIN - 2),
				CFrame = CFrame.new(px + s * 2.8, 0.23, 15),
				Color = P.White,
				CanCollide = false,
				Parent = marks,
			})
		end
	end
	marks.Parent = street

	local props = Instance.new("Model")
	props.Name = "Props"
	local spacing = Config.PlotSpacing
	for i = 0, Config.PlotCount do
		local x = (i - Config.PlotCount / 2) * spacing -- between plots (and at both ends)
		Style.Lamp(CFrame.new(x, 0.6, -7), props)
		Style.Tree(CFrame.new(x + 12, 0.6, 31), props)
		Style.Bench(CFrame.new(x - 12, 0.6, 31) * CFrame.Angles(0, math.pi, 0), props)
	end
	for i = 1, Config.PlotCount do
		local x = (i - (Config.PlotCount + 1) / 2) * spacing -- across from each plot
		Style.Lamp(CFrame.new(x - 40, 0.6, 33), props)
		Style.Lamp(CFrame.new(x + 40, 0.6, 33), props)
	end
	for _, x in { -(half - 15), half - 15 } do
		Style.Tree(CFrame.new(x, 0.6, -5), props, 1.3)
	end
	props.Parent = street

	buildBusStop(-half + 12, street, "CustomerSpawn")
	buildBusStop(half - 12, street, "CustomerDespawn")

	street.Parent = workspace
end

local function restyleDefaults()
	local baseplate = workspace:FindFirstChild("Baseplate") :: BasePart?
	if baseplate then
		baseplate.Color = P.Grass
		baseplate.Material = Enum.Material.Grass
		for _, child in baseplate:GetChildren() do
			if child:IsA("Texture") then
				child:Destroy()
			end
		end
	end
	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawn then
		spawn.Color = P.Lilac
		spawn.Material = Enum.Material.SmoothPlastic
		for _, child in spawn:GetChildren() do
			if child:IsA("Decal") then
				child:Destroy()
			end
		end
	end
end

function WorldBuilder.Init()
	for _, name in { "Plots", "Street" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	restyleDefaults()

	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	for i = 1, Config.PlotCount * (Config.PlotRows or 1) do
		buildPlot(i, plots)
		task.wait() -- spread the build over a few frames
	end
	plots.Parent = workspace

	buildStreet()
end

return WorldBuilder
