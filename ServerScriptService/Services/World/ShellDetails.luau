--!strict
-- The finishing touches on the bakery building, per size stage (called from
-- ItemBuilders.Walls for each Stage model):
--   Roof     ceiling + chocolate roof with white icing drips, a chimney that
--            puffs smoke, vents and skylights. The front part (over the
--            Second Floor deck) hides once SecondFloor is owned (HideWhenOwned).
--            Roof parts are tagged "RoofPart", never collide and can't be
--            clicked or ray-hit (OrigCanQuery = false); UI/Effects/RoofFade
--            fades them while you look down into your own bakery.
--   Facade   window frames, planter boxes under the windows, wall lamps by the
--            door and string lights along the cornice (NightLight).
--   Inside   a chair rail along the walls.
-- Plot-local studs (+Z = street), as everywhere in World/.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Services = script:FindFirstAncestor("Services") :: Folder
local Style = require(Services.World.Style)

local P = Style.Palette
local B = Config.Building
local WALL_H = B.WallHeight
local FACADE_Z = B.FacadeZ
local DECK_BACK = FACADE_Z - 40 -- the Second Floor deck covers z DECK_BACK..FACADE_Z
local CHOCOLATE = Color3.fromRGB(122, 74, 58)

local ShellDetails = {}

local function at(floor: CFrame, x: number, y: number, z: number): CFrame
	return floor * CFrame.new(x, y, z)
end

local function nightLight(part: BasePart, range: number?)
	if range then
		local light = Instance.new("PointLight")
		light.Range = range
		light.Brightness = 1
		light.Color = Color3.fromRGB(255, 225, 170)
		light.Enabled = false
		light.Parent = part
		CollectionService:AddTag(light, "NightLight")
	end
	CollectionService:AddTag(part, "NightLight")
end

-- Marks every part under `root` as roof: no collisions, no clicks or rays, and
-- (when `hideWith` is set) hidden once that upgrade is owned.
local function roofParts(root: Instance, hideWith: string?)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false -- the bakery stays bright inside by day
			d:SetAttribute("OrigCanQuery", false)
			if hideWith then
				d:SetAttribute("HideWhenOwned", hideWith)
			end
			CollectionService:AddTag(d, "RoofPart")
		end
	end
end

-- One flat roof section: ceiling below, chocolate roof on top.
local function slab(floor: CFrame, parent: Instance, name: string, width: number, z0: number, z1: number)
	if z1 - z0 < 0.5 then
		return
	end
	local mid = (z0 + z1) / 2
	Style.Part({ Name = name .. "Ceiling", Size = Vector3.new(width, 0.3, z1 - z0), CFrame = at(floor, 0, WALL_H - 0.15, mid), Color = P.Cream, Parent = parent })
	Style.Part({ Name = name .. "Top", Size = Vector3.new(width, 0.5, z1 - z0), CFrame = at(floor, 0, WALL_H + 0.25, mid), Color = CHOCOLATE, Parent = parent })
end

function ShellDetails.Roof(floor: CFrame, stage: Model, halfX: number, backZ: number)
	local sideX = halfX - 0.5
	local width = sideX * 2
	local backC = backZ + 0.5
	local top = WALL_H + 0.5

	-- Rear section (always) and front section (gone once the deck is built).
	local rear = Instance.new("Model")
	rear.Name = "Roof"
	slab(floor, rear, "Rear", width, backC, math.max(backC, DECK_BACK))
	local chimneyX, chimneyZ = -sideX + 5, backC + 3.5
	local chimney = Style.RoundedBox("Chimney", Vector3.new(3.4, 7, 3.4), at(floor, chimneyX, top + 3.5, chimneyZ), P.Peach, rear, 0.4)
	chimney.Material = Enum.Material.Brick
	Style.Trim("ChimneyCap", Vector3.new(4.2, 0.8, 4.2), at(floor, chimneyX, top + 7.2, chimneyZ), P.Cocoa, rear)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "ChimneySmoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(245, 240, 235))
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
	smoke.Lifetime = NumberRange.new(3, 5)
	smoke.Rate = 3
	smoke.Speed = NumberRange.new(2, 4)
	smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.LightInfluence = 0.6
	local smokeAt = Instance.new("Attachment")
	smokeAt.Position = Vector3.new(0, 4, 0)
	smokeAt.Parent = chimney
	smoke.Parent = smokeAt
	for i, x in { sideX - 6, sideX - 12 } do -- vents on the rear section
		local vent = Style.RoundedBox("Vent", Vector3.new(4, 2, 3), at(floor, x, top + 1, backC + 3.5), P.Steel, rear, 0.4)
		Style.Part({ Name = "Grille", Size = Vector3.new(3, 1.2, 0.1), CFrame = at(floor, x, top + 1.1, backC + 5.05), Color = P.Charcoal, Parent = vent })
		Style.Cylinder("Fan", 0.3, 1.6, at(floor, x, top + 2.15, backC + 3.5), if i == 1 then P.HotPink else P.Mint, vent)
	end
	roofParts(rear)
	rear.Parent = stage

	local front = Instance.new("Model")
	front.Name = "RoofFront"
	slab(floor, front, "Front", width, math.max(backC, DECK_BACK), FACADE_Z)
	local skylights = math.max(1, math.floor(width / 24))
	for i = 1, skylights do
		local x = -width / 2 + (i - 0.5) * width / skylights
		Style.Trim("SkylightFrame", Vector3.new(7, 0.6, 7), at(floor, x, top + 0.3, FACADE_Z - 18), P.White, front)
		Style.Part({ Name = "Skylight", Size = Vector3.new(6, 0.7, 6), CFrame = at(floor, x, top + 0.35, FACADE_Z - 18), Color = P.Glass, Material = Enum.Material.Glass, Transparency = 0.35, Parent = front })
	end
	roofParts(front, "SecondFloor")
	front.Parent = stage

	-- White icing drips along the top of the facade (not roof: always shown).
	local drips = Instance.new("Model")
	drips.Name = "IcingDrips"
	for x = -sideX + 1, sideX - 1, 2.5 do
		local long = math.abs(math.floor(x)) % 3 == 0
		Style.Ball("Drip", if long then 1.3 else 0.9, at(floor, x, WALL_H - (if long then 0.8 else 0.5), FACADE_Z + 1.1), P.White, drips).CanCollide = false
	end
	drips.Parent = stage
end

function ShellDetails.Facade(floor: CFrame, stage: Model, halfX: number, backZ: number)
	local sideX = halfX - 0.5
	local inner, outer = B.DoorHalf + 1, sideX
	local bays = math.max(1, math.floor((outer - inner) / 16))
	local bay = (outer - inner) / bays
	local colors = { P.HotPink, P.Butter, P.Sky, P.Mint, P.Lilac }

	for _, side in { -1, 1 } do
		for i = 1, bays do
			local x = side * (inner + (i - 0.5) * bay)
			-- Window frame head and a planter box with flowers under the sill.
			Style.Trim("WindowHead", Vector3.new(bay - 1.2, 0.6, 1.6), at(floor, x, 10.1, FACADE_Z), P.White, stage)
			local planter = Style.RoundedBox("Planter", Vector3.new(bay - 3, 1.6, 1.6), at(floor, x, 0.8, FACADE_Z + 1.4), P.Cocoa, stage, 0.4)
			Style.Part({ Name = "Soil", Size = Vector3.new(bay - 3.4, 0.2, 1.2), CFrame = at(floor, x, 1.65, FACADE_Z + 1.4), Color = P.Leaf, CanCollide = false, Parent = planter })
			local n = math.max(2, math.floor((bay - 4) / 1.6))
			for f = 1, n do
				local fx = x - (bay - 4) / 2 + (f - 0.5) * (bay - 4) / n
				Style.Ball("Flower", 0.8, at(floor, fx, 2.05, FACADE_Z + 1.4), colors[(f + i) % #colors + 1], planter).CanCollide = false
			end
		end
	end
	-- Wall lamps either side of the door.
	for _, side in { -1, 1 } do
		local x = side * (B.DoorHalf + 2.6)
		Style.RoundedBox("SconceBack", Vector3.new(0.8, 1.6, 0.4), at(floor, x, 8.4, FACADE_Z + 0.7), P.Charcoal, stage, 0.2)
		local bulb = Style.Ball("Sconce", 1, at(floor, x, 8.6, FACADE_Z + 1.1), P.Butter, stage)
		bulb.CanCollide = false
		nightLight(bulb, 14)
	end
	-- String lights along the cornice.
	local lights = Instance.new("Model")
	lights.Name = "StringLights"
	Style.Part({ Name = "Wire", Size = Vector3.new(sideX * 2, 0.08, 0.08), CFrame = at(floor, 0, WALL_H + 1.05, FACADE_Z + 1.3), Color = P.Charcoal, CanCollide = false, Parent = lights })
	local k = 0
	for x = -sideX + 2, sideX - 2, 4.5 do
		k += 1
		local bulb = Style.Ball("Bulb", 0.6, at(floor, x, WALL_H + 0.75, FACADE_Z + 1.3), colors[k % #colors + 1], lights)
		bulb.CanCollide = false
		nightLight(bulb)
	end
	lights.Parent = stage

	-- Inside: a chair rail along the back and side walls.
	local backC = backZ + 0.5
	local depth = FACADE_Z - backC
	Style.Part({ Name = "ChairRail", Size = Vector3.new(sideX * 2 - 1, 0.4, 0.3), CFrame = at(floor, 0, 4, backC + 0.65), Color = P.White, CanCollide = false, Parent = stage })
	for _, side in { -1, 1 } do
		Style.Part({ Name = "ChairRail", Size = Vector3.new(0.3, 0.4, depth - 1), CFrame = at(floor, side * (sideX - 0.65), 4, backC + depth / 2), Color = P.White, CanCollide = false, Parent = stage })
	end
end

-- A welcome mat in the doorway (one for every stage: the door never moves).
function ShellDetails.Mat(floor: CFrame, item: Model)
	local mat = Style.RoundedBox("WelcomeMat", Vector3.new(10, 0.1, 3.4), at(floor, 0, 0.05, FACADE_Z + 2.2), P.HotPink, item, 0.4)
	mat.CanCollide = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.5
	gui.Parent = mat
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = P.White
	label.Text = "WELCOME"
	label.Rotation = 180
	label.Parent = gui
end

return ShellDetails
