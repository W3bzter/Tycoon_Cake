--!strict
-- Build mode / placement (Build/BuildService, UI/Build). Plot-local studs:
-- origin = centre of the floor top, +Z towards the street.
-- Merged into Shared/Config (read it as Config.<Name>).

local Config = {}

-- The bakery building shell (World/ItemBuilders.Walls, WorldBuilder floor/fence/entrance,
-- SecondFloor). Plot-local studs; the plot is Config.PlotSize (120 x 120, half = 60).
-- HalfX / BackZ are the fully expanded size; a bakery grows through Stages (the
-- first is what a new player gets, each Expansions upgrade adds one stage).
local B = {
	HalfX = 60, -- side walls at x ±(HalfX - 0.5) (last stage)
	BackZ = -60, -- back wall at z BackZ + 0.5 (last stage)
	Stages = {
		{ HalfX = 30, BackZ = -12 }, -- start: 60 x 48 inside
		{ HalfX = 45, BackZ = -36 }, -- Bigger Bakery I: 90 x 72
		{ HalfX = 60, BackZ = -60 }, -- Bigger Bakery II: 120 x 96
	},
	Expansions = { "BakeryExpansion1", "BakeryExpansion2" }, -- PlotLayout ids, stage 2 and 3
	FacadeZ = 35.5, -- shop front; the patio runs from here to the plot front (z 60)
	FrontZ = 60, -- plot front edge
	DoorHalf = 8, -- the doorway is x -DoorHalf..DoorHalf
	WallHeight = 18,
	DeckY = 18.5, -- second-floor deck height
	-- Back lot: the strip behind the plot's back edge (the delivery-truck loading
	-- dock goes here). World/MapBounds keeps it inside the map.
	BackLot = {
		Z0 = -60, -- the plot's back edge
		Z1 = -100,
	},
}
Config.Building = B

-- Detailed item models (World/Skins). Studio's FBX importer turns the Blender
-- models around, so they're turned back 180 degrees (checked in Studio). If a
-- future import faces another way, change this (0 / 90 / -90 / 180).
Config.Skins = {
	ImportYaw = 180,
}

Config.Build = {
	Grid = 2, -- studs per grid cell
	Bounds = { MinX = -B.HalfX + 0.5, MaxX = B.HalfX - 0.5, MinZ = B.BackZ + 0.5, MaxZ = B.FrontZ }, -- largest area; per stage see Shared/BuildRules.StageAreas
	MaxPlaced = 90, -- placed items per bakery
	ActionCooldown = 0.25, -- seconds between build requests
	-- Kept clear for customers (in addition to the footprints of
	-- every fixed machine/wall, which are found automatically).
	Reserved = {
		{ Name = "Entrance", X0 = -B.DoorHalf, X1 = B.DoorHalf, Z0 = B.FacadeZ - 10, Z1 = B.FrontZ },
	},
	-- Free furniture every new bakery starts with (Build/BuildMigration, once per
	-- save: Build.StarterGiven). Normal placed items: move or store them freely.
	-- X/Z = plot-local studs of the item centre, inside the first-stage walls or
	-- on the patio. A spot that's taken puts the item in the build inventory.
	Starter = {
		{ Id = "MenuBoard", X = 14, Z = 41 },
		{ Id = "Bench", X = -20, Z = 46 },
		{ Id = "PottedPlant", X = -26, Z = 56 },
		{ Id = "PottedPlant", X = 26, Z = 56 },
		{ Id = "FloorLamp", X = -24, Z = 31 },
		{ Id = "CakeStand", X = 14, Z = 30 },
		{ Id = "RunnerRug", X = 0, Z = 18 },
		{ Id = "BreadShelf", X = 20, Z = -8 },
	},
}

return Config
