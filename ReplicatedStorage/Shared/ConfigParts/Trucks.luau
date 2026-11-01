--!strict
-- Delivery trucks (Customers/DeliveryTrucks, dock built by World/DockBuilders).
-- With the Loading Dock upgrade a truck regularly comes out of a tunnel, reverses
-- into the bay on the patio corner (opposite the drive-thru), loads cakes (Cake
-- Racks first, then counters) and pays for all of them at once.
-- Plot-local studs: +Z towards the street, the plot front is at z 60.
-- Merged into Shared/Config (read it as Config.<Name>).

local Config = {}

Config.Trucks = {
	Interval = 75, -- seconds between trucks per bakery (x the Faster Trucks upgrade)
	MinCakes = 2, -- a truck only comes when at least this many cakes are ready
	Capacity = 4, -- cakes per truck (+ the Bigger Truck upgrades: PlotStats.TruckCapacity)
	PayMult = 1.2, -- bulk orders pay a bonus on each cake's sale price
	Speed = 30, -- studs per second on the road
	ReverseSpeed = 10, -- studs per second backing into the bay
	LoadTime = 0.6, -- seconds per cake loaded
	BayX = -46, -- bay centre (the drive-thru is on the +X side)
	BayHalfWidth = 6,
	DockZ = 41, -- the dock platform's front edge (the truck's back stops here)
	ShedDepth = 5, -- dock shed from DockZ - ShedDepth to DockZ
}

return Config
