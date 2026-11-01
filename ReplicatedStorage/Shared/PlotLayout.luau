--!strict
-- Upgrade list (metadata only; the geometry lives in the server's ItemBuilders).
-- Offsets are in plot-local space: origin = centre of the floor's top surface,
-- +Z faces the street. Building footprint: x -40..40, z -40..24 (facade at z 24);
-- patio z 24..40 with the display counters.

export type Upgrade = {
	Id: string,
	DisplayName: string,
	Icon: string, -- emoji shown on the button and machine sign
	Category: string, -- "Build" | "Kitchen" | "Decor" | "Gems" (button colour)
	Price: number,
	Currency: string?, -- "Cash" (default) or "Gems"
	Requires: string?, -- upgrade that must be owned before this button appears
	Button: Vector3, -- where the purchase pad sits
}

local PlotLayout = {}

PlotLayout.Upgrades = {
	{ Id = "Walls", DisplayName = "Bakery Building", Icon = "🏠", Category = "Build", Price = 10, Button = Vector3.new(-12, 0, 31) },
	{ Id = "IngredientCrate", DisplayName = "Pantry", Icon = "🥚", Category = "Kitchen", Price = 20, Requires = "Walls", Button = Vector3.new(-28, 0, -24) },
	{ Id = "Mixer", DisplayName = "Mixer", Icon = "🥣", Category = "Kitchen", Price = 40, Requires = "IngredientCrate", Button = Vector3.new(-12, 0, -24) },
	{ Id = "Oven", DisplayName = "Oven", Icon = "🔥", Category = "Kitchen", Price = 60, Requires = "Mixer", Button = Vector3.new(6, 0, -24) },
	{ Id = "DisplayCounter", DisplayName = "Display Counter", Icon = "🍰", Category = "Kitchen", Price = 80, Requires = "Oven", Button = Vector3.new(20, 0, 26.5) },
	{ Id = "Plants", DisplayName = "Potted Plants", Icon = "🌷", Category = "Decor", Price = 100, Requires = "Walls", Button = Vector3.new(-26, 0, 10) },
	{ Id = "Awning", DisplayName = "Striped Awning", Icon = "⛱️", Category = "Decor", Price = 200, Requires = "DisplayCounter", Button = Vector3.new(-24, 0, 31) },
	{ Id = "Oven2", DisplayName = "Second Oven", Icon = "🔥", Category = "Kitchen", Price = 300, Requires = "DisplayCounter", Button = Vector3.new(20, 0, -24) },
} :: { Upgrade }

function PlotLayout.Find(id: string): Upgrade?
	for _, upgrade in PlotLayout.Upgrades do
		if upgrade.Id == id then
			return upgrade
		end
	end
	return nil
end

function PlotLayout.Index(id: string): number?
	for i, upgrade in PlotLayout.Upgrades do
		if upgrade.Id == id then
			return i
		end
	end
	return nil
end

return PlotLayout
