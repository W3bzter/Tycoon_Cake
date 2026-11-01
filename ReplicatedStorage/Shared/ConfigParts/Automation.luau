--!strict
-- Automation: production line timings.
-- Merged into Shared/Config (read it as Config.<Name>).

local Config = {}

-- Automation (production lines) -------------------------------------------------
Config.Auto = {
	FeedTime = 4, -- seconds for the ingredient conveyor to deliver one recipe's worth
	MixTime = 3,
	BakeMult = 1.5, -- automated ovens are slower than a player's oven until upgraded
	DeliverTime = 3, -- conveyor travel time to the counter
	HopperCap = 4, -- recipe sets the hopper can hold (players load them from the bag)
	TrayCap = 2, -- batters / cakes waiting between steps
	AutoLoadInterval = 1, -- Full Automation pass: seconds between auto-loads per line
}

return Config
