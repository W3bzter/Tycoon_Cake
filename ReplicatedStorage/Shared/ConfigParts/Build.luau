--!strict
-- Build mode / placement (Build/BuildService, UI/Build). Plot-local studs:
-- origin = centre of the floor top, +Z towards the street.
-- Merged into Shared/Config (read it as Config.<Name>).

local Config = {}

Config.Build = {
	Grid = 2, -- studs per grid cell
	Bounds = { MinX = -39.5, MaxX = 39.5, MinZ = -39.5, MaxZ = 40 }, -- the plot floor (fixed walls and fences are reserved separately)
	MaxPlaced = 60, -- placed items per bakery
	ActionCooldown = 0.25, -- seconds between build requests
	-- Kept clear for customers and floor buttons (in addition to the footprints of
	-- every fixed machine/wall, which are found automatically).
	Reserved = {
		{ Name = "Entrance", X0 = -6, X1 = 6, Z0 = 14, Z1 = 40 },
	},
	ButtonClearance = 3, -- studs kept clear around every floor button
}

return Config
