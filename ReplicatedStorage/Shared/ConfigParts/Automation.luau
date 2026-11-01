--!strict
-- Automation: Auto-Bakers (Factory/AutoBakers) and Cake Racks.
-- Merged into Shared/Config (read it as Config.<Name>).

local Config = {}

Config.AutoBaker = {
	Tick = 0.5, -- seconds between machine updates
	-- Seconds per cake, by machine (the Auto-Baker upgrades in place: Turbo, Golden).
	CycleSeconds = { AutoBaker = 12, TurboBaker = 8, GoldenBaker = 5 },
	Quality = "Good", -- machines always mix "Good"
	RackSlots = 9, -- cakes a Cake Rack holds (3 shelves x 3)
	RestockEvery = 1, -- seconds between moving a rack cake onto a free counter slot
}

return Config
