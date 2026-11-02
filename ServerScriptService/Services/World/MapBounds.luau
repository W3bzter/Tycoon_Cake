--!strict
-- Encloses the map: cartoon mountains and hills all round (World/Scenery, the
-- Blender world models) with trees, or rocky terrain cliffs when the mountain
-- models are not imported; a dark sealed tunnel where the road meets each end
-- (a concrete portal into the mountain), tall invisible walls just inside, a
-- ground slab under everything, and a fall safety net that puts anyone below
-- the world back on their plot. Sizes come from Config (street, plots, Scenery).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local PlotManager = require(Services.Core.PlotManager)
local Scenery = require(Services.World.Scenery)
local WorldModels = require(Services.World.WorldModels)
local Style = require(Services.World.Style)

local P = Style.Palette

local MapBounds = {}

local CLIFF_THICK = 44
local CLIFF_HIGH = 70
local ROAD_MIN, ROAD_MAX = 5, 25 -- WorldBuilder's road
local TUNNEL_W, TUNNEL_H = 24, 18

-- Inner edges of the playable area (studs, world).
function MapBounds.Edges(): (number, number, number)
	local half = Config.StreetLength / 2
	local plotHalf = Config.PlotSize.Z / 2
	local annex = Config.Building.BackLot.Z0 - Config.Building.BackLot.Z1 -- back lot depth (loading dock)
	local zMin = Config.PlotRowZ - plotHalf - annex - 12
	local zMax = if (Config.PlotRows or 1) > 1 then Config.PlotRowZB + plotHalf + annex + 12 else 60
	return half, zMin, zMax
end

local function part(props: { [string]: any }): Part
	local p = Style.Part(props)
	p.Anchored = true
	return p
end

local function buildCliffs(xEdge: number, zMin: number, zMax: number)
	local terrain = workspace.Terrain
	local t, h = CLIFF_THICK, CLIFF_HIGH
	local outerX = xEdge + t
	-- Four walls of rock, standing on the ground (y 0).
	local walls = {
		{ CFrame.new(0, h / 2, zMin - t / 2), Vector3.new(outerX * 2, h, t) },
		{ CFrame.new(0, h / 2, zMax + t / 2), Vector3.new(outerX * 2, h, t) },
		{ CFrame.new(-xEdge - t / 2, h / 2, (zMin + zMax) / 2), Vector3.new(t, h, zMax - zMin + t * 2) },
		{ CFrame.new(xEdge + t / 2, h / 2, (zMin + zMax) / 2), Vector3.new(t, h, zMax - zMin + t * 2) },
	}
	for _, w in walls do
		terrain:FillBlock(w[1], w[2], Enum.Material.Rock)
	end
	-- Boulders: a lumpy skyline along the top and rubble along the foot.
	local rng = Random.new(7)
	local materials = { Enum.Material.Rock, Enum.Material.Slate, Enum.Material.Basalt, Enum.Material.Rock }
	local function lumps(from: Vector3, to: Vector3, inward: Vector3)
		local length = (to - from).Magnitude
		local steps = math.floor(length / 16)
		for i = 0, steps do
			local p = from:Lerp(to, i / math.max(steps, 1))
			local top = p + Vector3.new(0, h + rng:NextNumber(-4, 8), 0) + inward * rng:NextNumber(-10, 10)
			terrain:FillBall(top, rng:NextNumber(10, 20), materials[rng:NextInteger(1, #materials)])
			-- Rubble at the foot, but none near the road (the tunnel mouths).
			local nearRoad = math.abs(p.Z - (ROAD_MIN + ROAD_MAX) / 2) < TUNNEL_W
			if not nearRoad then
				local foot = p + inward * (t / 2 + rng:NextNumber(0, 4)) + Vector3.new(0, rng:NextNumber(2, 10), 0)
				terrain:FillBall(foot, rng:NextNumber(5, 11), materials[rng:NextInteger(1, #materials)])
			end
		end
	end
	lumps(Vector3.new(-outerX, 0, zMin - t / 2), Vector3.new(outerX, 0, zMin - t / 2), Vector3.new(0, 0, 1))
	lumps(Vector3.new(-outerX, 0, zMax + t / 2), Vector3.new(outerX, 0, zMax + t / 2), Vector3.new(0, 0, -1))
	lumps(Vector3.new(-xEdge - t / 2, 0, zMin), Vector3.new(-xEdge - t / 2, 0, zMax), Vector3.new(1, 0, 0))
	lumps(Vector3.new(xEdge + t / 2, 0, zMin), Vector3.new(xEdge + t / 2, 0, zMax), Vector3.new(-1, 0, 0))
end

-- A sealed tunnel where the road meets the cliff at x = side * xEdge.
local function buildTunnel(side: number, xEdge: number, parent: Instance)
	local terrain = workspace.Terrain
	local zMid = (ROAD_MIN + ROAD_MAX) / 2
	local depth = CLIFF_THICK - 6
	-- Clear a corridor in front of the mouth (no stray rock on the road), then carve
	-- the tube (it stops short of the far side of the cliff, so it's a dead end).
	local approach = 30
	terrain:FillBlock(CFrame.new(side * (xEdge - approach / 2), (TUNNEL_H + 6) / 2, zMid), Vector3.new(approach + 2, TUNNEL_H + 6, TUNNEL_W + 8), Enum.Material.Air)
	terrain:FillBlock(CFrame.new(side * (xEdge + depth / 2), TUNNEL_H / 2, zMid), Vector3.new(depth + 2, TUNNEL_H, TUNNEL_W), Enum.Material.Air)
	terrain:FillBall(Vector3.new(side * (xEdge + depth / 2), TUNNEL_H - 2, zMid), TUNNEL_W / 2, Enum.Material.Air)

	local model = Instance.new("Model")
	model.Name = if side > 0 then "TunnelEast" else "TunnelWest"
	-- Road continuing into the dark.
	part({ Name = "TunnelRoad", Size = Vector3.new(depth, 0.2, ROAD_MAX - ROAD_MIN), CFrame = CFrame.new(side * (xEdge + depth / 2), 0.1, zMid), Color = P.Asphalt, Parent = model })
	-- Stone arch around the mouth.
	local archColor = Color3.fromRGB(150, 140, 135)
	for _, z in { ROAD_MIN - 2.5, ROAD_MAX + 2.5 } do
		part({ Name = "ArchPillar", Size = Vector3.new(3, TUNNEL_H + 2, 3), CFrame = CFrame.new(side * (xEdge + 1), (TUNNEL_H + 2) / 2, z), Color = archColor, Material = Enum.Material.Slate, Parent = model })
	end
	part({ Name = "ArchTop", Size = Vector3.new(3, 3, TUNNEL_W + 6), CFrame = CFrame.new(side * (xEdge + 1), TUNNEL_H + 2.5, zMid), Color = archColor, Material = Enum.Material.Slate, Parent = model })
	-- Warning lamps either side of the mouth.
	for _, z in { ROAD_MIN - 2.5, ROAD_MAX + 2.5 } do
		local lamp = Style.Ball("TunnelLamp", 1, CFrame.new(side * (xEdge - 0.8), TUNNEL_H - 3, z), Color3.fromRGB(255, 170, 60), model)
		lamp.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 160, 80)
		light.Range = 14
		light.Brightness = 1.4
		light.Parent = lamp
	end
	-- Darkness: layered black veils getting thicker, then a pitch-black back wall.
	for i, alpha in { 0.75, 0.5, 0.25 } do
		part({ Name = "Gloom", Size = Vector3.new(0.2, TUNNEL_H, TUNNEL_W), CFrame = CFrame.new(side * (xEdge + i * 7), TUNNEL_H / 2, zMid), Color = Color3.new(0, 0, 0), Transparency = alpha, CanCollide = false, CanQuery = false, CastShadow = false, Parent = model })
	end
	part({ Name = "TunnelVoid", Size = Vector3.new(1, TUNNEL_H + 4, TUNNEL_W + 4), CFrame = CFrame.new(side * (xEdge + depth - 2), TUNNEL_H / 2, zMid), Color = Color3.new(0, 0, 0), Material = Enum.Material.Neon, CastShadow = false, Parent = model })
	model.Parent = parent
end

-- With the Blender mountains there is no rock to carve: a concrete portal box
-- runs from the arch into the mountain that sits over each tunnel.
local function buildPortal(side: number, xEdge: number, parent: Instance)
	local zMid = (ROAD_MIN + ROAD_MAX) / 2
	local depth = CLIFF_THICK - 4
	local x = side * (xEdge + 2 + depth / 2)
	local color = Color3.fromRGB(165, 155, 160)
	local model = Instance.new("Model")
	model.Name = if side > 0 then "PortalEast" else "PortalWest"
	for _, z in { ROAD_MIN - 3.5, ROAD_MAX + 3.5 } do
		part({ Name = "PortalWall", Size = Vector3.new(depth, TUNNEL_H + 6, 4), CFrame = CFrame.new(x, (TUNNEL_H + 6) / 2, z), Color = color, Material = Enum.Material.Concrete, Parent = model })
	end
	part({ Name = "PortalRoof", Size = Vector3.new(depth, 4, TUNNEL_W + 11), CFrame = CFrame.new(x, TUNNEL_H + 2, zMid), Color = color, Material = Enum.Material.Concrete, Parent = model })
	model.Parent = parent
end

-- Grass that isn't taken by the street, a plot, its drive-thru lane or a tunnel
-- approach (where Scenery may put trees).
local function freeGround(x: number, z: number, xEdge: number): boolean
	if z > -16 and z < 46 then -- sidewalks and road
		return false
	end
	if math.abs(z - (ROAD_MIN + ROAD_MAX) / 2) < 36 and math.abs(x) > xEdge - 60 then
		return false -- tunnel approaches and portals
	end
	local rows = { Config.PlotRowZ }
	if (Config.PlotRows or 1) > 1 then
		table.insert(rows, Config.PlotRowZB)
	end
	for i = 1, Config.PlotCount do
		local px = (i - (Config.PlotCount + 1) / 2) * Config.PlotSpacing
		for _, pz in rows do
			if math.abs(x - px) < Config.PlotSize.X / 2 + 16 and math.abs(z - pz) < Config.PlotSize.Z / 2 + 4 then
				return false
			end
		end
	end
	return true
end

local function invisibleWall(name: string, cf: CFrame, size: Vector3, parent: Instance)
	part({ Name = name, Size = size, CFrame = cf, Transparency = 1, CanCollide = true, CanQuery = false, CanTouch = false, CastShadow = false, Parent = parent })
end

function MapBounds.Init()
	WorldModels.Report()
	local xEdge, zMin, zMax = MapBounds.Edges()
	local folder = Instance.new("Folder")
	folder.Name = "MapBounds"

	-- Ground under everything, out to the mountains (a hair below a Baseplate's top).
	local reach = Config.Scenery.MountainOut + Config.Scenery.BackRowOut + 120
	part({ Name = "Ground", Size = Vector3.new(xEdge * 2 + reach * 2, 4, zMax - zMin + reach * 2), CFrame = CFrame.new(0, -2.05, (zMin + zMax) / 2), Color = P.Grass, Material = Enum.Material.Grass, Parent = folder })

	-- Mountains and hills (Blender models), else rocky terrain cliffs.
	local zRoad = (ROAD_MIN + ROAD_MAX) / 2
	local function tunnelMouth(x: number, z: number): boolean
		return math.abs(x) > xEdge - 20 and math.abs(z - zRoad) < 48
	end
	local anchors = { Vector3.new(-(xEdge + 70), 0, zRoad), Vector3.new(xEdge + 70, 0, zRoad) }
	local mountains = Scenery.Ring(xEdge, zMin, zMax, folder, tunnelMouth, anchors)
	if not mountains then
		buildCliffs(xEdge, zMin, zMax)
	end
	for _, side in { -1, 1 } do
		buildTunnel(side, xEdge, folder)
		if mountains then
			buildPortal(side, xEdge, folder)
		end
	end
	Scenery.Forest(xEdge, zMin, zMax, folder, function(x, z)
		return freeGround(x, z, xEdge)
	end)

	-- Invisible walls just inside the cliffs (they also close the tunnel mouths).
	local h, y = 400, 200
	invisibleWall("WallSouth", CFrame.new(0, y, zMin + 1), Vector3.new(xEdge * 2, h, 2), folder)
	invisibleWall("WallNorth", CFrame.new(0, y, zMax - 1), Vector3.new(xEdge * 2, h, 2), folder)
	invisibleWall("WallWest", CFrame.new(-xEdge + 1, y, (zMin + zMax) / 2), Vector3.new(2, h, zMax - zMin), folder)
	invisibleWall("WallEast", CFrame.new(xEdge - 1, y, (zMin + zMax) / 2), Vector3.new(2, h, zMax - zMin), folder)
	invisibleWall("Ceiling", CFrame.new(0, h + 1, (zMin + zMax) / 2), Vector3.new(xEdge * 2, 2, zMax - zMin), folder)
	folder.Parent = workspace

	-- Fall safety net: anyone below the world goes back to their plot (or the spawn).
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and root.Position.Y < -40 then
					local plot = PlotManager.GetPlot(player)
					local pad = plot and plot:FindFirstChild("Spawn") :: BasePart?
					local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
					local target = if pad then pad.CFrame else if spawnLocation then spawnLocation.CFrame else CFrame.new(0, 10, 0)
					player.Character:PivotTo(target * CFrame.new(0, 5, 0))
					root.AssemblyLinearVelocity = Vector3.zero
				end
			end
		end
	end)
end

return MapBounds
