--!strict
-- Builds the game's placeholder Tools in code and offers inventory helpers.
-- Every tool carries an "ItemKind" attribute; that (not the name) is what the
-- server checks, so renaming a tool can't fake an item.

local ToolFactory = {}

type ToolSpec = {
	DisplayName: string,
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
	Shape: Enum.PartType,
}

local SPECS: { [string]: ToolSpec } = {
	Ingredient = {
		DisplayName = "Ingredients",
		Size = Vector3.new(1, 1.2, 1),
		Color = Color3.fromRGB(245, 220, 120),
		Material = Enum.Material.Fabric,
		Shape = Enum.PartType.Block,
	},
	RawBatter = {
		DisplayName = "Raw Batter",
		Size = Vector3.new(1.6, 1, 1.6),
		Color = Color3.fromRGB(250, 240, 210),
		Material = Enum.Material.SmoothPlastic,
		Shape = Enum.PartType.Block,
	},
	FinishedCake = {
		DisplayName = "Cake",
		Size = Vector3.new(1.6, 1.6, 1.6),
		Color = Color3.fromRGB(150, 90, 60),
		Material = Enum.Material.SmoothPlastic,
		Shape = Enum.PartType.Ball,
	},
	FireExtinguisher = {
		DisplayName = "Fire Extinguisher",
		Size = Vector3.new(0.8, 2, 0.8),
		Color = Color3.fromRGB(210, 40, 40),
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Block,
	},
}

function ToolFactory.Make(kind: string): Tool
	local spec = SPECS[kind]
	assert(spec, `ToolFactory: unknown kind {kind}`)

	local tool = Instance.new("Tool")
	tool.Name = spec.DisplayName
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ItemKind", kind)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = spec.Size
	handle.Color = spec.Color
	handle.Material = spec.Material
	handle.Shape = spec.Shape
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	return tool
end

-- All tools of a kind in the player's backpack and hands.
function ToolFactory.Find(player: Player, kind: string): { Tool }
	local found = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in (container :: Instance):GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("ItemKind") == kind then
					table.insert(found, child)
				end
			end
		end
	end
	return found
end

function ToolFactory.Count(player: Player, kind: string): number
	return #ToolFactory.Find(player, kind)
end

function ToolFactory.Give(player: Player, kind: string): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil
	end
	local tool = ToolFactory.Make(kind)
	tool.Parent = backpack
	return tool
end

-- Removes `amount` tools of a kind, or nothing if the player has fewer.
function ToolFactory.Take(player: Player, kind: string, amount: number): boolean
	local tools = ToolFactory.Find(player, kind)
	if #tools < amount then
		return false
	end
	for i = 1, amount do
		tools[i]:Destroy()
	end
	return true
end

return ToolFactory
