--!strict
-- Cartoony building toolkit: pastel palette, chunky rounded boxes, signage and
-- street props. Everything is anchored SmoothPlastic unless stated otherwise.

local CollectionService = game:GetService("CollectionService")

local Style = {}

Style.Palette = {
	Cream = Color3.fromRGB(255, 244, 222),
	Vanilla = Color3.fromRGB(255, 236, 196),
	Pink = Color3.fromRGB(255, 182, 206),
	HotPink = Color3.fromRGB(255, 105, 160),
	Mint = Color3.fromRGB(150, 236, 200),
	DeepMint = Color3.fromRGB(70, 200, 160),
	Butter = Color3.fromRGB(255, 226, 120),
	Sky = Color3.fromRGB(140, 205, 255),
	Lilac = Color3.fromRGB(200, 170, 255),
	Peach = Color3.fromRGB(255, 196, 150),
	Cocoa = Color3.fromRGB(140, 90, 70),
	White = Color3.fromRGB(255, 255, 255),
	Steel = Color3.fromRGB(205, 215, 230),
	Charcoal = Color3.fromRGB(70, 70, 90),
	Grass = Color3.fromRGB(130, 210, 110),
	Leaf = Color3.fromRGB(90, 190, 100),
	Asphalt = Color3.fromRGB(85, 90, 110),
	Sidewalk = Color3.fromRGB(196, 178, 196),
	Glass = Color3.fromRGB(190, 235, 255),
	Gold = Color3.fromRGB(255, 205, 60),
}
local P = Style.Palette

-- Category colours for purchase buttons.
Style.CategoryColor = {
	Build = P.HotPink,
	Kitchen = P.DeepMint,
	Decor = P.Butter,
	Gems = P.Sky,
}

function Style.Part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = parent
	return p
end

-- A disc/cylinder standing upright (Roblox cylinders run along X, so rotate).
function Style.Cylinder(name: string, height: number, diameter: number, cf: CFrame, color: Color3, parent: Instance?): Part
	return Style.Part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Parent = parent,
	})
end

function Style.Ball(name: string, diameter: number, cf: CFrame, color: Color3, parent: Instance?): Part
	return Style.Part({
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = cf,
		Color = color,
		Parent = parent,
	})
end

-- Box with rounded vertical edges. Returns the core part, named `name`; the
-- extra pieces are parented to it so they move/hide/recolour together.
function Style.RoundedBox(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance?, radius: number?): Part
	local r = math.min(radius or 0.6, size.X / 2, size.Z / 2)
	local core = Style.Part({
		Name = name,
		Size = Vector3.new(size.X - 2 * r, size.Y, size.Z),
		CFrame = cf,
		Color = color,
		Parent = parent,
	})
	Style.Part({
		Name = "Fill",
		Size = Vector3.new(size.X, size.Y, size.Z - 2 * r),
		CFrame = cf,
		Color = color,
		Parent = core,
	})
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Style.Cylinder("Edge", size.Y, 2 * r, cf * CFrame.new(sx * (size.X / 2 - r), 0, sz * (size.Z / 2 - r)), color, core)
		end
	end
	return core
end

-- Thin contrasting band, e.g. a counter top or cornice.
function Style.Trim(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance?): Part
	return Style.RoundedBox(name, size, cf, color, parent, math.min(0.4, size.Z / 2))
end

-- Striped, slightly tilted awning with a scalloped front edge.
-- `cf` is the centre of the back (wall) edge; the awning extends towards +Z.
function Style.StripedAwning(width: number, depth: number, cf: CFrame, colorA: Color3, colorB: Color3, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Awning"
	local tilt = cf * CFrame.Angles(math.rad(20), 0, 0) -- front edge slopes down towards +Z
	local stripes = math.max(2, math.floor(width / 3))
	local stripeW = width / stripes
	for i = 1, stripes do
		local x = -width / 2 + stripeW * (i - 0.5)
		Style.Part({
			Name = "Stripe",
			Size = Vector3.new(stripeW, 0.4, depth),
			CFrame = tilt * CFrame.new(x, 0, depth / 2),
			Color = if i % 2 == 0 then colorA else colorB,
			Parent = model,
		})
		Style.Ball("Scallop", stripeW * 0.55, tilt * CFrame.new(x, -0.25, depth), if i % 2 == 0 then colorA else colorB, model)
	end
	model.Parent = parent
	return model
end

function Style.Lamp(cf: CFrame, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Lamp"
	Style.Cylinder("Base", 0.6, 1.6, cf * CFrame.new(0, 0.3, 0), P.Charcoal, model)
	Style.Cylinder("Post", 9, 0.5, cf * CFrame.new(0, 4.8, 0), P.Charcoal, model)
	local bulb = Style.Ball("Bulb", 1.8, cf * CFrame.new(0, 9.6, 0), P.Butter, model)
	bulb.Material = Enum.Material.Neon
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Parent = bulb
	model.Parent = parent
	return model
end

function Style.Tree(cf: CFrame, parent: Instance, scale: number?): Model
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "Tree"
	Style.Cylinder("Trunk", 6 * s, 1.4 * s, cf * CFrame.new(0, 3 * s, 0), P.Cocoa, model)
	Style.Ball("Leaves", 7 * s, cf * CFrame.new(0, 7.5 * s, 0), P.Leaf, model)
	Style.Ball("Leaves", 5 * s, cf * CFrame.new(1.8 * s, 9.5 * s, 0.6 * s), P.Grass, model)
	Style.Ball("Leaves", 4.5 * s, cf * CFrame.new(-1.6 * s, 9 * s, -0.8 * s), P.Grass, model)
	model.Parent = parent
	return model
end

function Style.Bench(cf: CFrame, parent: Instance, color: Color3?): Model
	local model = Instance.new("Model")
	model.Name = "Bench"
	local c = color or P.Peach
	Style.RoundedBox("Seat", Vector3.new(6, 0.5, 2), cf * CFrame.new(0, 1.6, 0), c, model, 0.25)
	Style.RoundedBox("Back", Vector3.new(6, 1.6, 0.4), cf * CFrame.new(0, 2.8, -0.8), c, model, 0.2)
	for _, x in { -2.4, 2.4 } do
		Style.Part({ Name = "Leg", Size = Vector3.new(0.4, 1.4, 1.6), CFrame = cf * CFrame.new(x, 0.7, 0), Color = P.Charcoal, Parent = model })
	end
	model.Parent = parent
	return model
end

-- Floating billboard label (emoji + text) used over machines and buttons.
function Style.Billboard(adornee: BasePart, lines: { string }, opts: { [string]: any }?): BillboardGui
	local o = opts or {}
	local gui = Instance.new("BillboardGui")
	gui.Name = o.Name or "Label"
	gui.Size = UDim2.fromScale(o.Width or 7, o.Height or 2.4) -- studs
	gui.StudsOffsetWorldSpace = o.Offset or Vector3.new(0, 4, 0)
	gui.MaxDistance = o.MaxDistance or 70
	gui.LightInfluence = 0
	gui.Parent = adornee

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = o.Background or P.White
	frame.BackgroundTransparency = o.BackgroundTransparency or 0.05
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = o.Stroke or P.HotPink
	stroke.Thickness = 3
	stroke.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.Name = `Line{i}`
		label.LayoutOrder = i
		label.Size = UDim2.fromScale(0.94, 0.92 / #lines)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = o.TextColor or P.Cocoa
		label.Text = line
		label.Parent = frame
	end
	return gui
end

function Style.MachineSign(item: Model, anchor: BasePart, emoji: string, text: string)
	Style.Billboard(anchor, { `{emoji} {text}` }, {
		Name = "MachineSign",
		Width = 6,
		Height = 1.4,
		Offset = Vector3.new(0, anchor.Size.Y / 2 + 3, 0),
		MaxDistance = 45,
	})
	CollectionService:AddTag(item, "Interactable")
end

return Style
