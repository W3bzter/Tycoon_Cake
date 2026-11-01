--!strict
-- Fixed upgrades: the building itself, recipes, oven upgrades and (until the
-- Phase 5 factory annex) the automation line. They are bought from the Upgrades
-- tab of the Build shop (Build/BuildService "upgrade" -> World/TycoonButtons.
-- TryPurchase) and appear in a fixed spot; geometry lives in the server's
-- ItemBuilders and effects are totalled by PlotStats.
-- Everything else physical (pantry, mixing station, oven, counters, signs, decor)
-- is bought and placed in Build mode (Shared/BuildCatalog). Those ids still count
-- as unlocks, so Requires can name them ("Mixer", "DisplayCounter2", "IngredientCrate").
-- Plot-local offsets: origin = centre of the floor's top surface, +Z faces the
-- street; building size in Config.Building.

export type Upgrade = {
	Id: string,
	DisplayName: string,
	Icon: string,
	Category: string, -- "Build" | "Kitchen" | "Decor" | "Auto" | "Gems" (button colour)
	Tier: number,
	Price: number,
	Currency: string?, -- "Cash" (default) or "Gems"
	Requires: { string }?, -- all must be owned before the button appears
	ReplacedBy: string?, -- once that upgrade is owned, this item and its button are hidden
	Effects: { [string]: number }?, -- see PlotStats
}

local PlotLayout = {}


PlotLayout.Upgrades = {
	-- Tier 0: Hand tools (a new plot starts as bare floor; the Pantry is placed from the Build shop) ---
	{ Id = "Walls", DisplayName = "Bakery Building", Icon = "🏠", Category = "Build", Tier = 0, Price = 75, Requires = { "DisplayCounter" } },

	-- Tier 1: Manual machines (each replaces its hand tool in the same spot) -----------
	{ Id = "Awning", DisplayName = "Striped Awning", Icon = "⛱️", Category = "Decor", Tier = 1, Price = 200, Requires = { "Walls" } },
	{ Id = "BakeryExpansion1", DisplayName = "Bigger Bakery I", Icon = "📐", Category = "Build", Tier = 1, Price = 1500, Requires = { "Awning" } },

	-- Tier 2: Shopfront --------------------------------------------------------------
	{ Id = "RecipeChocolate", DisplayName = "Chocolate Recipe", Icon = "🍫", Category = "Kitchen", Tier = 2, Price = 600, Requires = { "Oven" } },
	{ Id = "FasterOvens1", DisplayName = "Oven Speed I", Icon = "⏱️", Category = "Kitchen", Tier = 2, Price = 1500, Requires = { "Oven" }, Effects = { BakeTime = 0.8 } },
	{ Id = "OvenRack2", DisplayName = "Oven Rack II", Icon = "🧁", Category = "Kitchen", Tier = 2, Price = 1000, Requires = { "Oven" }, Effects = { OvenRacks = 1 } },

	-- Tier 3: Expansion ----------------------------------------------------------------
	{ Id = "RecipeStrawberry", DisplayName = "Strawberry Recipe", Icon = "🍓", Category = "Kitchen", Tier = 3, Price = 3000, Requires = { "RecipeChocolate", "DisplayCounter2" } },
	{ Id = "SecondFloor", DisplayName = "Second Floor", Icon = "🪜", Category = "Build", Tier = 3, Price = 4500, Requires = { "Seating", "DisplayCounter2" } },
	{ Id = "BakeryExpansion2", DisplayName = "Bigger Bakery II", Icon = "📐", Category = "Build", Tier = 3, Price = 9000, Requires = { "BakeryExpansion1", "DisplayCounter2" } },
	{ Id = "FasterOvens2", DisplayName = "Oven Speed II", Icon = "⏱️", Category = "Kitchen", Tier = 3, Price = 8000, Requires = { "FasterOvens1" }, Effects = { BakeTime = 0.8 } },
	{ Id = "OvenRack3", DisplayName = "Oven Rack III", Icon = "🧁", Category = "Kitchen", Tier = 3, Price = 7500, Requires = { "OvenRack2", "FasterOvens1" }, Effects = { OvenRacks = 1 } },
	{ Id = "VIPLounge", DisplayName = "VIP Lounge", Icon = "👑", Category = "Decor", Tier = 3, Price = 15000, Requires = { "SecondFloor" }, Effects = { VIPChance = 0.12 } },

	-- Tier 4: Factory Annex (a new room behind the bakery), then automation inside it (line 1, bought in order) ------------------------------
	{ Id = "FactoryAnnex", DisplayName = "Factory Annex", Icon = "🏭", Category = "Build", Tier = 4, Price = 10000, Requires = { "BakeryExpansion2", "RecipeStrawberry", "FasterOvens2" } },
	{ Id = "IngredientConveyor", DisplayName = "Ingredient Conveyor", Icon = "📦", Category = "Auto", Tier = 4, Price = 12000, Requires = { "FactoryAnnex" } },
	{ Id = "AutoMixer", DisplayName = "Auto-Mixer", Icon = "🤖", Category = "Auto", Tier = 4, Price = 18000, Requires = { "IngredientConveyor" } },
	{ Id = "AutoOven", DisplayName = "Auto-Oven", Icon = "🤖", Category = "Auto", Tier = 4, Price = 27000, Requires = { "AutoMixer" } },
	{ Id = "CounterConveyor", DisplayName = "Counter Conveyor", Icon = "➡️", Category = "Auto", Tier = 4, Price = 40000, Requires = { "AutoOven" } },
	{ Id = "AutoRestock", DisplayName = "Auto-Restock Rack", Icon = "🗄️", Category = "Auto", Tier = 4, Price = 60000, Requires = { "CounterConveyor" }, Effects = { StorageSlots = 6 } },
	{ Id = "OvenRack4", DisplayName = "Oven Rack IV", Icon = "🧁", Category = "Kitchen", Tier = 4, Price = 40000, Requires = { "OvenRack3", "FasterOvens2" }, Effects = { OvenRacks = 1 } },

	-- Tier 5: Production lines --------------------------------------------------------------
	{ Id = "ProductionLine2", DisplayName = "Production Line 2", Icon = "🏭", Category = "Auto", Tier = 5, Price = 90000, Requires = { "AutoRestock" } },
	{ Id = "FasterOvens3", DisplayName = "Oven Speed III", Icon = "⏱️", Category = "Kitchen", Tier = 5, Price = 135000, Requires = { "FasterOvens2", "ProductionLine2" }, Effects = { BakeTime = 0.75 } },
	{ Id = "ProductionLine3", DisplayName = "Production Line 3", Icon = "🏭", Category = "Auto", Tier = 5, Price = 200000, Requires = { "ProductionLine2" } },
	{ Id = "GoldenShopfront", DisplayName = "Golden Shopfront", Icon = "✨", Category = "Decor", Tier = 5, Price = 300000, Requires = { "ProductionLine3" }, Effects = { SalePrice = 1.1, VIPChance = 0.05 } },

	-- Gem upgrades -------------------------------------------------------------------------
	{ Id = "RecipeRainbow", DisplayName = "Rainbow Recipe", Icon = "🌈", Category = "Gems", Tier = 3, Price = 25, Currency = "Gems", Requires = { "RecipeStrawberry" } },
	{ Id = "GoldenOven", DisplayName = "Golden Oven (2x speed)", Icon = "🌟", Category = "Gems", Tier = 3, Price = 40, Currency = "Gems", Requires = { "FasterOvens1" } },
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
