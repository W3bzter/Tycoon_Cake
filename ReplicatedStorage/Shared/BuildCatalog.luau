--!strict
-- Everything a player can buy in Build mode and place in their bakery.
-- Buying puts the item in the build inventory (PlayerData.Build.Owned); placing
-- it builds the model (World/ItemBuilders or World/DecorBuilders) at the chosen
-- grid spot. Server: Build/BuildService. Client: UI/Build.
--
--   Kind       "MixStation" | "Oven" | "Counter" | "Decor" (machines get prompts)
--   UpgradeOf  bought in place on a placed item of that id (same spot, new model)
--   Max        how many you can own (counting placed ones)
--   Prices     price of the 1st, 2nd, ... copy (else Price for every copy)
--   Unlocks    legacy upgrade ids granted by the Nth purchase, so PlotLayout
--              requirement chains (e.g. "DisplayCounter2") keep working
--   Effects    like PlotLayout effects (PlotStats), active once owned
--   Front      extra studs kept clear in front (+Z) of it (customers stand there)

export type Entry = {
	Id: string,
	Name: string,
	Icon: string,
	Kind: string,
	Category: string, -- "Kitchen" | "Decor" (shop tabs)
	Price: number,
	Prices: { number }?,
	Currency: string?, -- "Cash" (default) | "Gems"
	Requires: { string }?,
	Max: number?,
	UpgradeOf: string?,
	Unlocks: { [number]: string }?,
	Effects: { [string]: number }?,
	Front: number?,
	Description: string,
}

local BuildCatalog = {}

BuildCatalog.List = {
	-- Mixing station: bowl -> Mixer -> Big Mixer (upgrades in place)
	{ Id = "PrepTable", Name = "Mixing Bowl & Whisk", Icon = "🥄", Kind = "MixStation", Category = "Kitchen", Price = 15, Requires = { "IngredientCrate" }, Max = 1, Description = "Mix batter by hand (harder minigame)." },
	{ Id = "Mixer", Name = "Mixer", Icon = "🥣", Kind = "MixStation", Category = "Kitchen", Price = 150, Requires = { "Walls" }, UpgradeOf = "PrepTable", Description = "Upgrades your bowl: an easier mixing minigame." },
	{ Id = "BigMixer", Name = "Big Mixer", Icon = "🥣", Kind = "MixStation", Category = "Kitchen", Price = 2000, Requires = { "Mixer", "Oven" }, UpgradeOf = "Mixer", Effects = { MixBatch = 1 }, Description = "Upgrades your Mixer: 2 batters per mix." },
	-- The oven (one per bakery)
	{ Id = "BasicOven", Name = "Baking Tray & Basic Oven", Icon = "🍞", Kind = "Oven", Category = "Kitchen", Price = 25, Requires = { "PrepTable" }, Max = 1, Description = "Bakes your batter (slowly)." },
	{ Id = "Oven", Name = "Oven", Icon = "🔥", Kind = "Oven", Category = "Kitchen", Price = 300, Requires = { "Mixer" }, UpgradeOf = "BasicOven", Description = "Upgrades your basic oven: bakes twice as fast." },
	-- Display counters
	{ Id = "DisplayCounter", Name = "Display Counter", Icon = "🍰", Kind = "Counter", Category = "Kitchen", Price = 40, Prices = { 40, 800, 6000, 25000 }, Requires = { "BasicOven" }, Max = 4, Unlocks = { [1] = "DisplayCounter", [2] = "DisplayCounter2" }, Front = 5, Description = "Customers buy the cakes you put here." },
	-- Decor
	{ Id = "PottedPlant", Name = "Potted Plant", Icon = "🌷", Kind = "Decor", Category = "Decor", Price = 25, Requires = { "Walls" }, Max = 12, Unlocks = { [1] = "Plants" }, Description = "A cheerful plant." },
	{ Id = "Rug", Name = "Cosy Rug", Icon = "🟪", Kind = "Decor", Category = "Decor", Price = 60, Requires = { "Walls" }, Max = 6, Description = "A soft round rug." },
	{ Id = "Balloons", Name = "Balloon Bunch", Icon = "🎈", Kind = "Decor", Category = "Decor", Price = 150, Requires = { "Walls" }, Max = 6, Description = "Party balloons on a weight." },
	{ Id = "CafeTable", Name = "Café Table", Icon = "☕", Kind = "Decor", Category = "Decor", Price = 225, Requires = { "Walls" }, Max = 8, Unlocks = { [1] = "Seating" }, Description = "A table with two chairs." },
	{ Id = "CupcakeStatue", Name = "Cupcake Statue", Icon = "🧁", Kind = "Decor", Category = "Decor", Price = 5000, Requires = { "SecondFloor" }, Max = 2, Description = "A giant cupcake. Very important." },
	{ Id = "CakeCharm", Name = "Cake Charm (+15%)", Icon = "🍀", Kind = "Decor", Category = "Decor", Price = 30, Currency = "Gems", Requires = { "DisplayCounter2" }, Max = 1, Effects = { SalePrice = 1.15 }, Description = "A lucky charm: +15% cake prices while owned." },
} :: { Entry }

function BuildCatalog.Find(id: string): Entry?
	for _, entry in BuildCatalog.List do
		if entry.Id == id then
			return entry
		end
	end
	return nil
end

-- Price of the next copy, given how many you already own.
function BuildCatalog.PriceFor(entry: Entry, owned: number): number
	if entry.Prices then
		return entry.Prices[math.min(owned + 1, #entry.Prices)]
	end
	return entry.Price
end

-- The chain root of an upgradable item ("BigMixer" -> "PrepTable").
function BuildCatalog.Root(id: string): string
	local entry = BuildCatalog.Find(id)
	while entry and entry.UpgradeOf do
		id = entry.UpgradeOf
		entry = BuildCatalog.Find(id)
	end
	return id
end

-- The next upgrade of `id`, if any ("PrepTable" -> "Mixer").
function BuildCatalog.NextUpgrade(id: string): Entry?
	for _, entry in BuildCatalog.List do
		if entry.UpgradeOf == id then
			return entry
		end
	end
	return nil
end

return BuildCatalog
