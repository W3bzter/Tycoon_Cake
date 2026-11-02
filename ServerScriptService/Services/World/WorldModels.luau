--!strict
-- Blender world models (Art/World, Art/README.md "World models"): vehicles,
-- trees, mountains, street props, the drive-thru kiosk and menu board, cake
-- pallets. Imported into the place file as ServerStorage.Assets.World.<Name>
-- (a Model of MeshParts, one per colour role).
--
-- WorldModels.Clone(name, opts) returns a ready copy, or nil when that model
-- isn't imported (callers then build their block version):
--   * every MeshPart coloured by its role name (Body, Leaves, Rock, ...)
--   * turned by Config.Skins.ImportYaw, scaled so its height is Size.Y (or
--     opts.Height), pivoted on the ground under its origin, with the authored
--     front (Defs[name].Front) as it was in Blender
--   * anchored, no touch; collisions off unless opts.Collide
-- Moving parts are left for the caller (Vehicles spins Wheel*/Hub*, DeliveryTrucks
-- rolls RearDoor, DriveThru slides the kiosk Window); Leaves* are tagged FxSway
-- (client sway, UI/Effects/WorldFX) and Bulb parts NightLight.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local Style = require(Services.World.Style)

local P = Style.Palette

local WorldModels = {}

-- Authored bounds from Art/World/world.json (Size, Centre relative to the origin).
type Def = { Size: Vector3, Centre: Vector3 }
WorldModels.Defs = {
	Car = { Size = Vector3.new(4.68, 3.675, 7.865), Centre = Vector3.new(0, 1.838, 0.013) },
	DeliveryTruck = { Size = Vector3.new(6.688, 8.2, 14.205), Centre = Vector3.new(0, 4.1, -0.053) },
	RoundTree = { Size = Vector3.new(8.191, 11.6, 8.314), Centre = Vector3.new(0.486, 5.8, -0.167) },
	PineTree = { Size = Vector3.new(5.6, 10.65, 5.6), Centre = Vector3.new(0, 5.325, 0) },
	Bush = { Size = Vector3.new(3.844, 2.7, 2.489), Centre = Vector3.new(0.028, 1.05, -0.036) },
	MountainA = { Size = Vector3.new(147.721, 101, 145.477), Centre = Vector3.new(0, 50.5, -2.262) },
	MountainB = { Size = Vector3.new(147.721, 86, 145.477), Centre = Vector3.new(0, 43, -2.262) },
	Hill = { Size = Vector3.new(57.063, 21, 60), Centre = Vector3.new(0, 0, 0) },
	StreetLamp = { Size = Vector3.new(1.6, 11.05, 3.981), Centre = Vector3.new(0, 5.525, 1.338) },
	DriveThruKiosk = { Size = Vector3.new(5.527, 10.525, 7.8), Centre = Vector3.new(1.064, 5.262, 0) },
	MenuBoard = { Size = Vector3.new(2.6, 6.298, 6.4), Centre = Vector3.new(0.854, 3.149, 0.6) },
	PalletOfCakes = { Size = Vector3.new(4, 3.676, 4), Centre = Vector3.new(0, 1.833, 0) },
	TrafficCone = { Size = Vector3.new(1.6, 2.6, 1.6), Centre = Vector3.new(0, 1.3, 0) },
	FireHydrant = { Size = Vector3.new(1.7, 2.9, 1.45), Centre = Vector3.new(0, 1.45, 0.075) },
	Bench = { Size = Vector3.new(6, 3.6, 2.15), Centre = Vector3.new(0, 1.8, -0.2) },
	TrashCan = { Size = Vector3.new(2, 3.175, 2), Centre = Vector3.new(0, 1.587, 0) },
	Mailbox = { Size = Vector3.new(1.39, 3.9, 2), Centre = Vector3.new(0.045, 1.95, 0) },
} :: { [string]: Def }

type Look = { Color: Color3, Material: Enum.Material?, Transparency: number? }
local function L(color: Color3, material: Enum.Material?, transparency: number?): Look
	return { Color = color, Material = material, Transparency = transparency }
end
local GLASS = L(P.Glass, Enum.Material.Glass, 0.3)
local NEON_BUTTER = L(P.Butter, Enum.Material.Neon)
local WOOD = L(Color3.fromRGB(190, 135, 95), Enum.Material.Wood)

-- Colour of every role name (the part name without digits/suffix).
local ROLES: { [string]: Look } = {
	Cargo = L(P.Pink),
	Tire = L(P.Charcoal),
	Wheel = L(P.Charcoal),
	Hub = L(P.Steel, Enum.Material.Metal),
	Metal = L(P.Steel, Enum.Material.Metal),
	Glass = GLASS,
	Window = GLASS,
	Light = NEON_BUTTER,
	Bulb = L(P.Butter),
	TailLight = L(Color3.fromRGB(255, 70, 70), Enum.Material.Neon),
	Dark = L(Color3.fromRGB(60, 55, 70)),
	Trim = L(P.White),
	Accent = L(P.HotPink),
	Door = L(P.Peach),
	SignBoard = L(Color3.fromRGB(45, 55, 50)),
	Rock = L(Color3.fromRGB(150, 140, 160)),
	RockDark = L(Color3.fromRGB(115, 105, 130)),
	Snow = L(Color3.fromRGB(250, 250, 255)),
	Grass = L(P.Grass),
	Leaves = L(P.Leaf),
	LeavesDark = L(Color3.fromRGB(70, 160, 95)),
	Trunk = L(P.Cocoa),
	Flower = L(P.HotPink),
	Flowers = L(P.HotPink),
	Cardboard = L(Color3.fromRGB(225, 185, 135)),
	Wood = WOOD,
	LightWood = L(Color3.fromRGB(240, 205, 165), Enum.Material.Wood),
	Ribbon = L(P.HotPink),
	Cone = L(Color3.fromRGB(255, 140, 60)),
	Flag = L(Color3.fromRGB(255, 70, 70)),
}

local function folder(): Instance?
	local assets = ServerStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("World")
end

function WorldModels.Has(name: string): boolean
	local f = folder()
	return WorldModels.Defs[name] ~= nil and f ~= nil and f:FindFirstChild(name) ~= nil
end

-- The role colour key: Wheel* / Hub* share one look whatever their suffix.
local function roleKey(name: string): string
	for _, prefix in { "Wheel", "Hub", "Leaves" } do
		if string.sub(name, 1, #prefix) == prefix then
			return if prefix == "Leaves" and string.sub(name, 1, 10) == "LeavesDark" then "LeavesDark" else prefix
		end
	end
	return string.match(name, "^%a+") or name
end

export type Options = {
	Height: number?, -- studs (default: the authored height)
	Roles: { [string]: Color3 }?, -- per-copy colours, e.g. { Body = red }
	Collide: boolean?,
	Shadows: boolean?, -- default true
}

-- A fresh, unparented copy pivoted at its ground origin (identity rotation), or nil.
function WorldModels.Clone(name: string, opts: Options?): Model?
	local f = folder()
	local def = WorldModels.Defs[name]
	local source = f and f:FindFirstChild(name)
	if not def or not source then
		return nil
	end
	local o = opts or {}
	local model = Instance.new("Model")
	model.Name = name
	local copy = source:Clone()
	if copy:IsA("BasePart") then
		copy.Parent = model
	else
		for _, child in copy:GetChildren() do
			child.Parent = model
		end
		copy:Destroy()
	end
	local count = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
			d.Anchored = true
			d.CanTouch = false
			d.CanCollide = o.Collide == true
			d.CanQuery = o.Collide == true
			d.CastShadow = o.Shadows ~= false
			local key = roleKey(d.Name)
			local custom = o.Roles and o.Roles[key]
			local look = ROLES[key]
			d.Material = Enum.Material.SmoothPlastic
			if custom then
				d.Color = custom
			elseif look then
				d.Color = look.Color
				d.Material = look.Material or Enum.Material.SmoothPlastic
				d.Transparency = look.Transparency or 0
			end
			if key == "Leaves" or key == "LeavesDark" or key == "Flowers" then
				CollectionService:AddTag(d, "FxSway")
			end
			for _, extra in d:GetChildren() do
				if extra:IsA("SurfaceAppearance") then
					extra:Destroy()
				end
			end
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	if count == 0 then
		model:Destroy()
		return nil
	end
	-- Turn like the item skins, scale to height, then put the origin at (0, 0, 0).
	model:PivotTo(CFrame.Angles(0, math.rad(Config.Skins.ImportYaw), 0))
	local _, size = model:GetBoundingBox()
	local height = o.Height or def.Size.Y
	model:ScaleTo(model:GetScale() * height / math.max(size.Y, 1e-3))
	local box = model:GetBoundingBox()
	local k = height / def.Size.Y
	local centre = def.Centre * k
	model.WorldPivot = CFrame.new(box.Position - centre)
	model:PivotTo(CFrame.new())
	-- A PrimaryPart (for labels and sounds) takes over the pivot, so give it an
	-- offset that keeps the pivot at the ground origin (its own frame is turned).
	local root = (model:FindFirstChild("Body") or model:FindFirstChildWhichIsA("BasePart")) :: BasePart?
	if root then
		root.PivotOffset = root.CFrame:ToObjectSpace(CFrame.new())
		model.PrimaryPart = root
	end
	model:SetAttribute("WorldModel", name)
	return model
end

-- Clone + place at `cf` under `parent` (ground origin at cf). Nil if not imported.
function WorldModels.Place(name: string, cf: CFrame, parent: Instance, opts: Options?): Model?
	local model = WorldModels.Clone(name, opts)
	if model then
		model:PivotTo(cf)
		-- Sway pivots are world positions: set them once the model is in place.
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and CollectionService:HasTag(d, "FxSway") then
				d:SetAttribute("SwayPivot", cf.Position)
			end
		end
		model.Parent = parent
	end
	return model
end

-- Makes every Bulb part a night light (glows + lights up at night: World/DayNight).
function WorldModels.LightBulbs(model: Model, range: number, color: Color3?)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and roleKey(d.Name) == "Bulb" then
			local light = Instance.new("PointLight")
			light.Range = range
			light.Brightness = 1.3
			light.Color = color or Color3.fromRGB(255, 220, 160)
			light.Enabled = false
			light.Parent = d
			CollectionService:AddTag(d, "NightLight")
			CollectionService:AddTag(light, "NightLight")
		end
	end
end

-- The face of `part` whose outward normal points most along `worldDir`.
function WorldModels.FaceToward(part: BasePart, worldDir: Vector3): Enum.NormalId
	local best, bestDot = Enum.NormalId.Front, -math.huge
	for _, id in Enum.NormalId:GetEnumItems() do
		local n = part.CFrame:VectorToWorldSpace(Vector3.FromNormalId(id))
		local dot = n:Dot(worldDir)
		if dot > bestDot then
			best, bestDot = id, dot
		end
	end
	return best
end

-- Writes `text` on the face of `part` that looks along `worldDir`.
function WorldModels.Write(part: BasePart, worldDir: Vector3, text: string, color: Color3?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = WorldModels.FaceToward(part, worldDir)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.9, 0.86)
	label.Position = UDim2.fromScale(0.05, 0.07)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color or P.White
	label.Text = text
	label.Parent = gui
	return gui
end

-- Startup report: which world models the place file has.
function WorldModels.Report()
	local found, missing = {}, {}
	for name in WorldModels.Defs do
		table.insert(if WorldModels.Has(name) then found else missing, name)
	end
	table.sort(found)
	print(`[WorldModels] {#found} world models found{if #found > 0 then ": " .. table.concat(found, ", ") else ""}`)
	if #missing > 0 then
		table.sort(missing)
		warn(`[WorldModels] not imported (block versions used): {table.concat(missing, ", ")}`)
	end
end

return WorldModels
