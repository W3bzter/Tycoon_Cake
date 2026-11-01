--!strict
-- Upgrade list (metadata only; geometry lives in the server's ItemBuilders and
-- effects are totalled by the server's PlotStats).
-- Offsets are plot-local: origin = centre of the floor's top surface, +Z faces the
-- street. Building x -40..40, z -40..24 (facade at z 24), patio z 24..40.
-- Floor plan: kitchen z -40..-30 | manual buttons z -24 | automation line z -18 |
-- line buttons z -12 | recipe buttons z -4 | dining z 0..20 | upstairs deck y 14.5.
-- Chained upgrades (Faster Ovens I/II/III ...) reuse one button spot, since only
-- the next one in the chain is ever shown.

export type Upgrade = {
	Id: string,
	DisplayName: string,
	Icon: string,
	Category: string, -- "Build" | "Kitchen" | "Decor" | "Auto" | "Gems" (button colour)
	Tier: number,
	Price: number,
	Currency: string?, -- "Cash" (default) or "Gems"
	Requires: { string }?, -- all must be owned before the button appears
	Effects: { [string]: number }?, -- see PlotStats
	Button: Vector3, -- pad position (y = floor height it sits on)
}

local PlotLayout = {}

local DECK_Y = 14.5

PlotLayout.Upgrades = {
	-- Tier 1: Starter -----------------------------------------------------------
	{ Id = "Walls", DisplayName = "Bakery Building", Icon = "🏠", Category = "Build", Tier = 1, Price = 10, Button = Vector3.new(-12, 0, 31) },
	{ Id = "IngredientCrate", DisplayName = "Pantry", Icon = "🥚", Category = "Kitchen", Tier = 1, Price = 20, Requires = { "Walls" }, Button = Vector3.new(-28, 0, -24) },
	{ Id = "Mixer", DisplayName = "Mixer", Icon = "🥣", Category = "Kitchen", Tier = 1, Price = 40, Requires = { "IngredientCrate" }, Button = Vector3.new(-12, 0, -24) },
	{ Id = "Oven", DisplayName = "Oven", Icon = "🔥", Category = "Kitchen", Tier = 1, Price = 60, Requires = { "Mixer" }, Button = Vector3.new(6, 0, -24) },
	{ Id = "DisplayCounter", DisplayName = "Display Counter", Icon = "🍰", Category = "Kitchen", Tier = 1, Price = 80, Requires = { "Oven" }, Button = Vector3.new(20, 0, 26.5) },
	{ Id = "Plants", DisplayName = "Potted Plants", Icon = "🌷", Category = "Decor", Tier = 1, Price = 100, Requires = { "Walls" }, Button = Vector3.new(-35, 0, 19) },
	{ Id = "Awning", DisplayName = "Striped Awning", Icon = "⛱️", Category = "Decor", Tier = 1, Price = 200, Requires = { "DisplayCounter" }, Button = Vector3.new(-24, 0, 31) },
	{ Id = "Oven2", DisplayName = "Second Oven", Icon = "🔥", Category = "Kitchen", Tier = 1, Price = 300, Requires = { "DisplayCounter" }, Button = Vector3.new(20, 0, -24) },

	-- Tier 2: Shopfront --------------------------------------------------------------
	{ Id = "RecipeChocolate", DisplayName = "Chocolate Recipe", Icon = "🍫", Category = "Kitchen", Tier = 2, Price = 400, Requires = { "DisplayCounter" }, Button = Vector3.new(-30, 0, -4) },
	{ Id = "DisplayCounter2", DisplayName = "Second Counter", Icon = "🍰", Category = "Build", Tier = 2, Price = 600, Requires = { "Awning" }, Button = Vector3.new(-20, 0, 27) },
	{ Id = "Seating", DisplayName = "Café Seating", Icon = "☕", Category = "Decor", Tier = 2, Price = 750, Requires = { "DisplayCounter" }, Button = Vector3.new(-6, 0, 10) },
	{ Id = "StreetSign", DisplayName = "Street Sign", Icon = "🪧", Category = "Decor", Tier = 2, Price = 900, Requires = { "Awning" }, Effects = { CustomerRate = 0.85 }, Button = Vector3.new(-33, 0, 28) },
	{ Id = "FasterOvens1", DisplayName = "Faster Ovens I", Icon = "⏱️", Category = "Kitchen", Tier = 2, Price = 1200, Requires = { "Oven2" }, Effects = { BakeTime = 0.8 }, Button = Vector3.new(-3, 0, -24) },
	{ Id = "BigMixer", DisplayName = "Big Mixer", Icon = "🥣", Category = "Kitchen", Tier = 2, Price = 1800, Requires = { "Oven2" }, Effects = { MixBatch = 1 }, Button = Vector3.new(-20, 0, -24) },

	-- Tier 3: Expansion ----------------------------------------------------------------
	{ Id = "RecipeStrawberry", DisplayName = "Strawberry Recipe", Icon = "🍓", Category = "Kitchen", Tier = 3, Price = 3000, Requires = { "RecipeChocolate", "DisplayCounter2" }, Button = Vector3.new(-20, 0, -4) },
	{ Id = "SecondFloor", DisplayName = "Second Floor", Icon = "🪜", Category = "Build", Tier = 3, Price = 4500, Requires = { "Seating", "DisplayCounter2" }, Button = Vector3.new(26, 0, 16) },
	{ Id = "Oven3", DisplayName = "Third Oven", Icon = "🔥", Category = "Kitchen", Tier = 3, Price = 6000, Requires = { "FasterOvens1" }, Button = Vector3.new(34, 0, -24) },
	{ Id = "FasterOvens2", DisplayName = "Faster Ovens II", Icon = "⏱️", Category = "Kitchen", Tier = 3, Price = 8000, Requires = { "FasterOvens1", "Oven3" }, Effects = { BakeTime = 0.8 }, Button = Vector3.new(-3, 0, -24) },
	{ Id = "RadioAd", DisplayName = "Radio Ad", Icon = "📻", Category = "Decor", Tier = 3, Price = 10000, Requires = { "StreetSign" }, Effects = { CustomerRate = 0.8 }, Button = Vector3.new(34, 0, 27) },
	{ Id = "VIPLounge", DisplayName = "VIP Lounge", Icon = "👑", Category = "Decor", Tier = 3, Price = 15000, Requires = { "SecondFloor" }, Effects = { VIPChance = 0.12 }, Button = Vector3.new(-10, DECK_Y, 10) },

	-- Tier 4: Automation (production line 1, bought in order) ------------------------------
	{ Id = "IngredientConveyor", DisplayName = "Ingredient Conveyor", Icon = "📦", Category = "Auto", Tier = 4, Price = 12000, Requires = { "RecipeStrawberry", "Oven3" }, Button = Vector3.new(-24, 0, -12) },
	{ Id = "AutoMixer", DisplayName = "Auto-Mixer", Icon = "🤖", Category = "Auto", Tier = 4, Price = 18000, Requires = { "IngredientConveyor" }, Button = Vector3.new(-12, 0, -12) },
	{ Id = "AutoOven", DisplayName = "Auto-Oven", Icon = "🤖", Category = "Auto", Tier = 4, Price = 27000, Requires = { "AutoMixer" }, Button = Vector3.new(4, 0, -12) },
	{ Id = "CounterConveyor", DisplayName = "Counter Conveyor", Icon = "➡️", Category = "Auto", Tier = 4, Price = 40000, Requires = { "AutoOven" }, Button = Vector3.new(10, 0, -12) },
	{ Id = "AutoRestock", DisplayName = "Auto-Restock Rack", Icon = "🗄️", Category = "Auto", Tier = 4, Price = 60000, Requires = { "CounterConveyor" }, Effects = { StorageSlots = 6 }, Button = Vector3.new(10, 0, 14) },

	-- Tier 5: Production lines --------------------------------------------------------------
	{ Id = "ProductionLine2", DisplayName = "Production Line 2", Icon = "🏭", Category = "Auto", Tier = 5, Price = 90000, Requires = { "AutoRestock" }, Button = Vector3.new(9.5, 0, -4) },
	{ Id = "FasterOvens3", DisplayName = "Faster Ovens III", Icon = "⏱️", Category = "Kitchen", Tier = 5, Price = 135000, Requires = { "FasterOvens2", "ProductionLine2" }, Effects = { BakeTime = 0.75 }, Button = Vector3.new(-3, 0, -24) },
	{ Id = "ProductionLine3", DisplayName = "Production Line 3", Icon = "🏭", Category = "Auto", Tier = 5, Price = 200000, Requires = { "ProductionLine2" }, Button = Vector3.new(9.5, 0, 6) },
	{ Id = "GoldenShopfront", DisplayName = "Golden Shopfront", Icon = "✨", Category = "Decor", Tier = 5, Price = 300000, Requires = { "ProductionLine3" }, Effects = { SalePrice = 1.1, VIPChance = 0.05 }, Button = Vector3.new(12, 0, 27) },

	-- Gem upgrades -------------------------------------------------------------------------
	{ Id = "RecipeRainbow", DisplayName = "Rainbow Recipe", Icon = "🌈", Category = "Gems", Tier = 3, Price = 25, Currency = "Gems", Requires = { "RecipeStrawberry" }, Button = Vector3.new(-10, 0, -4) },
	{ Id = "GoldenOven", DisplayName = "Golden Oven (2x speed)", Icon = "🌟", Category = "Gems", Tier = 3, Price = 40, Currency = "Gems", Requires = { "Oven3" }, Button = Vector3.new(6, 0, -24) },
	{ Id = "CakeCharm", DisplayName = "Cake Charm (+15%)", Icon = "🍀", Category = "Gems", Tier = 2, Price = 30, Currency = "Gems", Requires = { "DisplayCounter2" }, Effects = { SalePrice = 1.15 }, Button = Vector3.new(20, 0, 26.5) },
} :: { Upgrade }

function PlotLayout.Find(id: string): Upgrade?
	for _, upgrade in PlotLayout.Upgrades do
		if upgrade.Id == id then
			return upgrade
		end
	end
	return nil
end

return PlotLayout
