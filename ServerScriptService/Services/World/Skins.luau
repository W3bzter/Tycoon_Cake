--!strict
-- Detailed models ("skins") for placeable items, made in Blender
-- (Art/blender/make_models.py -> Art/Models/<Id>.fbx) and imported into the place
-- file as ServerStorage.Assets.Models.<Id> (a Model of MeshParts, one per colour
-- role: Body, Trim, Accent, Metal, ...). See Art/README.md.
--
-- The item's own primitive build stays as an invisible skeleton (prompt parts,
-- cake slots, chair spots, sizes the game reads), except:
--   Keep   children left visible (e.g. the pantry's ingredient Bins)
--   Adopt  skeleton parts replaced by the skin's role mesh of the same name, so
--          code that finds them gets the detailed part (the oven's Body for
--          overheat colour + rack lights, its Door for the baking glow)
-- Each role is coloured from the palette here, so import colours don't matter.
-- The skin is rescaled to its authored size (Size = Art/Models/models.json) and
-- placed on the item's Anchor part, so the importer's scale/position don't matter
-- either. No template imported = the item keeps its current look.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local Style = require(Services.World.Style)

local P = Style.Palette

local Skins = {}

type RoleLook = Color3 | { Color: Color3, Material: Enum.Material?, Transparency: number? }
type Def = {
	Anchor: string, -- skeleton part whose X/Z is the skin's origin (floor level)
	Size: Vector3, -- authored bounds (models.json)
	Centre: Vector3, -- authored bounds centre, relative to the origin
	Roles: { [string]: RoleLook },
	Keep: { string }?,
	Adopt: { string }?,
}

local METAL = { Color = P.Steel, Material = Enum.Material.Metal }
local DARK = Color3.fromRGB(55, 40, 45)
local WOOD = { Color = Color3.fromRGB(205, 150, 110), Material = Enum.Material.Wood }
local LIGHT_WOOD = { Color = Color3.fromRGB(240, 205, 165), Material = Enum.Material.Wood }

Skins.Defs = {
	Oven = {
		Anchor = "Body",
		Size = Vector3.new(8, 10.155, 5.75),
		Centre = Vector3.new(0, 5.072, 0.375),
		Roles = { Body = P.Peach, Trim = P.Cream, Accent = P.HotPink, Metal = METAL, Dark = DARK, Door = { Color = Color3.fromRGB(60, 40, 40), Material = Enum.Material.Glass, Transparency = 0.2 } },
		Adopt = { "Body", "Door" },
	},
	Mixer = {
		Anchor = "Body",
		Size = Vector3.new(5, 10.04, 6.32),
		Centre = Vector3.new(0, 5.02, 0.26),
		Roles = { Body = P.Mint, Trim = P.Cream, Accent = P.HotPink, Metal = METAL, Dark = DARK },
	},
	IngredientCrate = {
		Anchor = "Crate",
		Size = Vector3.new(14, 11.675, 4.9),
		Centre = Vector3.new(0, 5.838, 0.75),
		Roles = { Wood = WOOD, LightWood = LIGHT_WOOD, Trim = P.Cream, Accent = P.HotPink, Glass = { Color = P.Sky, Material = Enum.Material.Glass, Transparency = 0.35 } },
		Keep = { "Bins" },
	},
	DisplayCounter = {
		Anchor = "Counter",
		Size = Vector3.new(20.6, 4.1, 4.65),
		Centre = Vector3.new(0, 2.05, 0.125),
		Roles = { Body = P.White, Stripe = P.Pink, Trim = P.Cream, Accent = P.HotPink, Top = P.Vanilla },
	},
	CafeTable = {
		Anchor = "TableTop",
		Size = Vector3.new(7.8, 3.425, 4.6),
		Centre = Vector3.new(0, 1.707, 0),
		Roles = { Top = P.White, Accent = P.HotPink, Cushion = P.Mint, Metal = METAL },
	},
	PottedPlant = {
		Anchor = "Pot",
		Size = Vector3.new(3.411, 4.925, 3.383),
		Centre = Vector3.new(-0.029, 2.463, 0.058),
		Roles = { Body = P.Peach, Accent = P.HotPink, Soil = P.Cocoa, Trim = P.White, Leaf = P.Leaf, LeafDark = P.Grass, Petal = P.HotPink, PetalB = P.Butter },
	},
} :: { [string]: Def }

local function template(id: string): Instance?
	local assets = ServerStorage:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Models")
	return models and models:FindFirstChild(id)
end

function Skins.Has(id: string): boolean
	return Skins.Defs[id] ~= nil and template(id) ~= nil
end

local function roleOf(part: BasePart): string
	-- "Body", "Body.001", "Body_1" ... -> "Body"
	return (string.match(part.Name, "^[%a]+") or part.Name)
end

local function look(part: BasePart, def: Def)
	local style = def.Roles[roleOf(part)]
	part.Material = Enum.Material.SmoothPlastic
	if typeof(style) == "Color3" then
		part.Color = style
	elseif style then
		part.Color = style.Color
		part.Material = style.Material or Enum.Material.SmoothPlastic
		part.Transparency = style.Transparency or 0
	end
end

local function isKept(inst: Instance, item: Model, keep: { string }): boolean
	local node: Instance? = inst
	while node and node ~= item do
		if node.Parent == item and table.find(keep, node.Name) then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Dresses `item` (catalog id `id`, built but not yet pivoted) in its detailed
-- model if one is imported. Returns true if it did.
function Skins.Apply(item: Model, id: string): boolean
	local def = Skins.Defs[id]
	local source = template(id)
	local anchor = item:FindFirstChild(def and def.Anchor or "", true) :: BasePart?
	if not def or not source or not anchor then
		return false
	end

	-- Clone into a Model of MeshParts, all anchored, coloured by role.
	local skin = Instance.new("Model")
	skin.Name = "Skin"
	local copy = source:Clone()
	if copy:IsA("BasePart") then
		copy.Parent = skin
	else
		for _, child in copy:GetChildren() do
			child.Parent = skin
		end
		copy:Destroy()
	end
	for _, d in skin:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			look(d, def)
			for _, extra in d:GetChildren() do
				if extra:IsA("SurfaceAppearance") then
					extra:Destroy() -- importer materials; colours come from the palette
				end
			end
		end
	end

	-- Rescale to the authored size, turn (Config.Skins.ImportYaw), then centre on the anchor.
	skin:PivotTo(CFrame.Angles(0, math.rad(Config.Skins.ImportYaw), 0))
	local _, imported = skin:GetBoundingBox()
	local factor = def.Size.Y / math.max(imported.Y, 1e-3)
	if math.abs(factor - 1) > 1e-3 then
		skin:ScaleTo(skin:GetScale() * factor)
	end
	local bbox = skin:GetBoundingBox()
	-- Items are built with the floor at y = 0 (BuildModels), so the origin is the
	-- anchor's spot on the floor.
	local origin = Vector3.new(anchor.Position.X, 0, anchor.Position.Z)
	skin:PivotTo(skin:GetPivot() + (origin + def.Centre - bbox.Position))

	-- Hide the skeleton, swap in adopted parts, keep what stays visible.
	local keep = def.Keep or {}
	for _, d in item:GetDescendants() do
		if d:IsA("BasePart") and not isKept(d, item, keep) then
			d.Transparency = 1
			d.CanCollide = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
	for _, name in def.Adopt or {} do
		local old = item:FindFirstChild(name)
		local new: Instance? = nil
		for _, d in skin:GetDescendants() do
			if d:IsA("BasePart") and roleOf(d) == name then
				new = d
				break
			end
		end
		if old and old:IsA("BasePart") and new and new:IsA("BasePart") then
			for _, child in old:GetChildren() do
				if not child:IsA("BasePart") then
					child.Parent = new -- signs, attachments
				end
			end
			old:Destroy()
			new.Name = name
			new.Parent = item
		end
	end
	skin.Parent = item
	return true
end

return Skins
