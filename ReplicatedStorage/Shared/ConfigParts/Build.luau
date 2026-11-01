--!strict
-- Build mode / placement (Build/BuildService, UI/Build). Plot-local studs:
-- origin = centre of the floor top, +Z towards the street.
-- Merged into Shared/Config (read it as Config.<Name>).

local Config = {}

-- The bakery building shell (World/ItemBuilders.Walls, WorldBuilder floor/fence/entrance,
-- SecondFloor). Plot-local studs; the plot is Config.PlotSize (120 x 120, half = 60).
local B = {
	HalfX = 60, -- side walls at x ±(HalfX - 0.5)
	BackZ = -60, -- back wall at z BackZ + 0.5
	FacadeZ = 35.5, -- shop front; the patio runs from here to the plot front (z 60)
	FrontZ = 60, -- plot front edge
	DoorHalf = 8, -- the doorway is x -DoorHalf..DoorHalf
	WallHeight = 18,
	DeckY = 18.5, -- second-floor deck height
	-- Factory Annex (an expansion bought from the Upgrades tab): a room behind the
	-- back wall that holds all the automation (World/ItemBuilders). Doorway in the
	-- bakery's back wall at x DoorX0..DoorX1, sealed until the annex is owned.
	Annex = {
		Z0 = -60, -- shared wall with the bakery (the plot's back edge)
		Z1 = -100, -- annex back wall
		DoorX0 = -42,
		DoorX1 = -30,
		LineZ = -78, -- production line 1 row (hopper -> mixer -> oven)
		UnitZ = -92, -- Production Line 2/3 units
	},
}
Config.Building = B

Config.Build = {
	Grid = 2, -- studs per grid cell
	Bounds = { MinX = -B.HalfX + 0.5, MaxX = B.HalfX - 0.5, MinZ = B.BackZ + 0.5, MaxZ = B.FrontZ }, -- the plot floor (fixed walls and fences are reserved separately)
	MaxPlaced = 90, -- placed items per bakery
	ActionCooldown = 0.25, -- seconds between build requests
	-- Kept clear for customers (in addition to the footprints of
	-- every fixed machine/wall, which are found automatically).
	Reserved = {
		{ Name = "Entrance", X0 = -B.DoorHalf, X1 = B.DoorHalf, Z0 = B.FacadeZ - 10, Z1 = B.FrontZ },
	},
}

return Config
