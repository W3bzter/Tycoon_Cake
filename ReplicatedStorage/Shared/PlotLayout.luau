--!strict
-- Upgrade list and placeholder geometry for one plot. All offsets are in the
-- plot's local space: origin = centre of the floor's top surface, +Z faces the street.

export type PartSpec = {
	Name: string,
	Size: Vector3,
	Offset: Vector3,
	Color: Color3,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Transparency: number?,
}

export type Upgrade = {
	Id: string,
	DisplayName: string,
	Price: number,
	Requires: string?, -- upgrade that must be owned before this button appears
	Parts: { PartSpec },
}

local Wood = Enum.Material.Wood
local Metal = Enum.Material.Metal
local Marble = Enum.Material.Marble

local PlotLayout = {}

PlotLayout.Upgrades = {
	{
		Id = "Walls",
		DisplayName = "Bakery Walls",
		Price = 10,
		Parts = {
			{ Name = "BackWall", Size = Vector3.new(80, 12, 1), Offset = Vector3.new(0, 6, -39.5), Color = Color3.fromRGB(250, 230, 200) },
			{ Name = "LeftWall", Size = Vector3.new(1, 12, 80), Offset = Vector3.new(-39.5, 6, 0), Color = Color3.fromRGB(250, 230, 200) },
			{ Name = "RightWall", Size = Vector3.new(1, 12, 80), Offset = Vector3.new(39.5, 6, 0), Color = Color3.fromRGB(250, 230, 200) },
		},
	},
	{
		Id = "IngredientCrate",
		DisplayName = "Ingredient Crate",
		Price = 20,
		Requires = "Walls",
		Parts = {
			{ Name = "Crate", Size = Vector3.new(4, 3, 4), Offset = Vector3.new(-28, 1.5, -28), Color = Color3.fromRGB(160, 110, 60), Material = Wood },
		},
	},
	{
		Id = "Mixer",
		DisplayName = "Mixer",
		Price = 40,
		Requires = "IngredientCrate",
		Parts = {
			{ Name = "Body", Size = Vector3.new(5, 4, 5), Offset = Vector3.new(-12, 2, -32), Color = Color3.fromRGB(200, 205, 210), Material = Metal },
			{ Name = "Bowl", Size = Vector3.new(4, 2, 4), Offset = Vector3.new(-12, 5, -32), Color = Color3.fromRGB(230, 230, 235), Material = Metal },
		},
	},
	{
		Id = "Oven",
		DisplayName = "Oven",
		Price = 60,
		Requires = "Mixer",
		Parts = {
			{ Name = "Body", Size = Vector3.new(8, 6, 5), Offset = Vector3.new(6, 3, -33), Color = Color3.fromRGB(60, 60, 65), Material = Metal },
			{ Name = "Door", Size = Vector3.new(6, 3.5, 0.2), Offset = Vector3.new(6, 3, -30.4), Color = Color3.fromRGB(20, 20, 20), Material = Enum.Material.Glass },
		},
	},
	{
		Id = "DisplayCounter",
		DisplayName = "Display Counter",
		Price = 80,
		Requires = "Oven",
		Parts = {
			{ Name = "Counter", Size = Vector3.new(20, 4, 4), Offset = Vector3.new(20, 2, 36), Color = Color3.fromRGB(245, 245, 245), Material = Marble },
		},
	},
	{
		Id = "Plants",
		DisplayName = "Potted Plants",
		Price = 100,
		Requires = "Walls",
		Parts = {
			{ Name = "PotL", Size = Vector3.new(3, 3, 3), Offset = Vector3.new(-36, 1.5, 36), Color = Color3.fromRGB(170, 90, 60) },
			{ Name = "LeavesL", Size = Vector3.new(4, 4, 4), Offset = Vector3.new(-36, 5, 36), Color = Color3.fromRGB(70, 160, 80), Material = Enum.Material.Grass, Shape = Enum.PartType.Ball },
			{ Name = "PotR", Size = Vector3.new(3, 3, 3), Offset = Vector3.new(-36, 1.5, -10), Color = Color3.fromRGB(170, 90, 60) },
			{ Name = "LeavesR", Size = Vector3.new(4, 4, 4), Offset = Vector3.new(-36, 5, -10), Color = Color3.fromRGB(70, 160, 80), Material = Enum.Material.Grass, Shape = Enum.PartType.Ball },
		},
	},
	{
		Id = "Awning",
		DisplayName = "Striped Awning",
		Price = 200,
		Requires = "DisplayCounter",
		Parts = {
			{ Name = "Awning", Size = Vector3.new(80, 1, 6), Offset = Vector3.new(0, 12, 38), Color = Color3.fromRGB(220, 70, 80), Material = Enum.Material.Fabric },
		},
	},
	{
		Id = "Oven2",
		DisplayName = "Second Oven",
		Price = 300,
		Requires = "DisplayCounter",
		Parts = {
			{ Name = "Body", Size = Vector3.new(8, 6, 5), Offset = Vector3.new(20, 3, -33), Color = Color3.fromRGB(60, 60, 65), Material = Metal },
			{ Name = "Door", Size = Vector3.new(6, 3.5, 0.2), Offset = Vector3.new(20, 3, -30.4), Color = Color3.fromRGB(20, 20, 20), Material = Enum.Material.Glass },
		},
	},
} :: { Upgrade }

-- Buttons sit in a row in front of the spawn pad.
function PlotLayout.ButtonOffset(index: number): Vector3
	return Vector3.new(-31.5 + (index - 1) * 9, 0.2, 22)
end

function PlotLayout.Find(id: string): Upgrade?
	for _, upgrade in PlotLayout.Upgrades do
		if upgrade.Id == id then
			return upgrade
		end
	end
	return nil
end

return PlotLayout
