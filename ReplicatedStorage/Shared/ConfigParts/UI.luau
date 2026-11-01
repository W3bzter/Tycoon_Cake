--!strict
-- UI: hotbar layout.
-- Merged into Shared/Config (read it as Config.<Name>).

local Config = {}

Config.Hotbar = {
	Slots = 9, -- keys 1-9; with more items the last slot becomes "+N" (opens a grid)
	SlotSize = 64, -- pixels (shrinks on narrow screens)
	BottomOffset = 60, -- pixels above the bottom edge (clears the button row)
}

return Config
