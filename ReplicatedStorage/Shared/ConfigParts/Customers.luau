--!strict
-- Customers: spawn pacing, walking, tips/VIP, animations.
-- Merged into Shared/Config (read it as Config.<Name>).

local Config = {}

-- Customers ------------------------------------------------------------------
Config.CustomerInterval = 5 -- seconds between spawn checks
Config.MaxCustomers = 12
Config.CustomerWalkSpeed = 18
Config.CustomerTripTimeout = 60 -- give up on a leg of the trip after this long
Config.CustomerStandOff = 5 -- studs in front of the counter where customers stop

Config.WantedTip = 0.2 -- customers tip 20% when they get the cake they asked for
Config.VIPPayMult = 3 -- VIP customers pay 3x
Config.SpawnCheckInterval = 1 -- per-plot spawn timers are checked this often

-- Customer animations: Roblox's default R15 animations. Empty = skip
-- (the cheer falls back to a hop).
Config.Animations = {
	Idle = "rbxassetid://507766388",
	Walk = "rbxassetid://507777826",
	Cheer = "rbxassetid://507770677",
	Sit = "rbxassetid://2506281703", -- dine-in customers
}

-- Dine-in (Customers/DineIn): after buying, some customers sit at a free chair of a
-- placed Café Table, eat, and leave a tip on top of what they paid.
Config.DineIn = {
	Chance = 0.5, -- of customers who sit down (if a chair is free)
	EatTime = 10, -- seconds at the table
	TipMin = 0.1, -- tip = this..TipMax share of what they paid
	TipMax = 0.3,
}

-- Drive-thru (fixed upgrade "DriveThru", Customers/DriveThru): cars come out of a
-- tunnel, drive into the lane beside your bakery, buy a cake at the window and
-- leave. Lane geometry is plot-local (+Z = towards the street; the plot ends at 60).
Config.DriveThru = {
	Interval = 25, -- seconds between cars per bakery (x the customer-rate upgrades)
	Speed = 34, -- studs per second
	StopTime = 2.5, -- seconds at the window
	PayMult = 1.15, -- drive-thru customers pay a little extra
	LaneX = 66, -- lane centre, beside the plot (plot edge at 60)
	WindowZ = 30, -- where cars stop at the kiosk
	EndZ = 9, -- turnaround pad
}

return Config
