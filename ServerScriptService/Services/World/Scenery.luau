--!strict
-- Cartoon scenery from the Blender world models (World/WorldModels), each with a
-- block fallback when its model isn't imported:
--   Lamp / Tree / Bench  street props (WorldBuilder): StreetLamp (Bulb glows at
--                        night), RoundTree / PineTree (Leaves sway), Bench
--   Ring(...)            the mountains and hills all round the map (MapBounds;
--                        returns false when the mountain models are missing, so
--                        MapBounds builds its terrain cliffs instead)
--   Forest(...)          trees and bushes on the free grass inside the walls and
--                        along the mountain feet (seeded: the same every server)
-- Sizes and counts: Config.Scenery.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Services = script:FindFirstAncestor("Services") :: Folder
local Style = require(Services.World.Style)
local WorldModels = require(Services.World.WorldModels)

local Scenery = {}

local S = Config.Scenery

-- Street lamp; its arm (+Z of `cf`) hangs over the road.
function Scenery.Lamp(cf: CFrame, parent: Instance): Model
	local lamp = WorldModels.Place("StreetLamp", cf, parent)
	if lamp then
		lamp.Name = "Lamp"
		WorldModels.LightBulbs(lamp, 22)
		return lamp
	end
	return Style.Lamp(cf, parent)
end

-- A tree: round or pine (`kind`), `scale` x the usual size.
function Scenery.Tree(cf: CFrame, parent: Instance, scale: number?, kind: string?): Model
	local s = scale or 1
	local name = kind or "RoundTree"
	local tree = WorldModels.Place(name, cf, parent, { Height = (if name == "PineTree" then 10.65 else 11.6) * s })
	if tree then
		tree.Name = "Tree"
		return tree
	end
	return Style.Tree(cf, parent, s)
end

function Scenery.Bench(cf: CFrame, parent: Instance, color: Color3?): Model
	local bench = WorldModels.Place("Bench", cf, parent, { Collide = true })
	return bench or Style.Bench(cf, parent, color)
end

local function bush(cf: CFrame, parent: Instance, scale: number)
	if not WorldModels.Place("Bush", cf, parent, { Height = 2.7 * scale, Shadows = false }) then
		Style.Ball("Bush", 3 * scale, cf * CFrame.new(0, 1.2 * scale, 0), Style.Palette.Leaf, parent)
	end
end

export type Rect = { X0: number, X1: number, Z0: number, Z1: number }

-- World-space bounds of every part in `model`.
local function bounds(model: Model): (Vector3, Vector3)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local h = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local c = d.CFrame * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
						lo, hi = lo:Min(c), hi:Max(c)
					end
				end
			end
		end
	end
	return lo, hi
end

-- Moves `model` along `outward` until its footprint is off every rect in `keepOff`
-- (a mountain's grass skirt reaches far: it must never lie on the road).
local function pushOff(model: Model, outward: Vector3, keepOff: { Rect })
	for _ = 1, 4 do
		local lo, hi = bounds(model)
		local move = 0
		for _, r in keepOff do
			if lo.X < r.X1 and hi.X > r.X0 and lo.Z < r.Z1 and hi.Z > r.Z0 then
				local need = if outward.X > 0.5 then r.X1 - lo.X
					elseif outward.X < -0.5 then hi.X - r.X0
					elseif outward.Z > 0.5 then r.Z1 - lo.Z
					else hi.Z - r.Z0
				move = math.max(move, need + 1)
			end
		end
		if move <= 0 then
			return
		end
		model:PivotTo(model:GetPivot() + outward * move)
	end
end

-- Mountains (two staggered rows) and hills round the rectangle xEdge / zMin..zMax.
-- `keepClear(x, z)` = true where no hill may stand (the tunnel mouths); `anchors`
-- = extra mountains (one over each tunnel, so the road runs into it); `keepOff`
-- = rects no mountain may cover (the street, up to the tunnel mouths).
function Scenery.Ring(xEdge: number, zMin: number, zMax: number, parent: Instance, keepClear: (number, number) -> boolean, anchors: { Vector3 }, keepOff: { Rect }): boolean
	if not WorldModels.Has("MountainA") then
		return false
	end
	local rng = Random.new(S.Seed)
	local model = Instance.new("Model")
	model.Name = "Mountains"
	-- Walk the rectangle's outline at distance `out` from the edges, every `step`.
	local function outline(out: number, step: number, fn: (x: number, z: number, outward: Vector3) -> ())
		local x0, x1, z0, z1 = -xEdge - out, xEdge + out, zMin - out, zMax + out
		local sides = {
			{ Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z0), Vector3.new(0, 0, -1) },
			{ Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1), Vector3.new(1, 0, 0) },
			{ Vector3.new(x1, 0, z1), Vector3.new(x0, 0, z1), Vector3.new(0, 0, 1) },
			{ Vector3.new(x0, 0, z1), Vector3.new(x0, 0, z0), Vector3.new(-1, 0, 0) },
		}
		for _, side in sides do
			local a, b, outward = side[1], side[2], side[3]
			local n = math.max(1, math.floor((b - a).Magnitude / step))
			for i = 0, n - 1 do
				local p = a:Lerp(b, (i + rng:NextNumber(0.2, 0.8)) / n)
				fn(p.X, p.Z, outward)
			end
		end
	end
	local function mountain(x: number, z: number, height: number, outward: Vector3)
		local name = if rng:NextNumber() < 0.5 then "MountainA" else "MountainB"
		-- Front (+Z) towards the map, so the grassy side faces the players.
		local cf = CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(x, 0, z) + outward) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0)
		local placed = WorldModels.Place(name, cf, model, { Height = height, Shadows = false })
		if placed then
			pushOff(placed, outward, keepOff)
		end
	end
	outline(S.MountainOut, S.MountainStep, function(x, z, outward)
		mountain(x, z, rng:NextNumber(S.MountainHeight.Min, S.MountainHeight.Max), outward)
	end)
	outline(S.MountainOut + S.BackRowOut, S.MountainStep * 1.1, function(x, z, outward)
		mountain(x, z, rng:NextNumber(S.MountainHeight.Max, S.MountainHeight.Max * 1.35), outward)
	end)
	for _, a in anchors do
		local outward = Vector3.new(math.sign(a.X), 0, 0)
		mountain(a.X, a.Z, S.MountainHeight.Max, outward)
	end
	outline(S.HillOut, S.HillStep, function(x, z, outward)
		if not keepClear(x, z) then
			local cf = CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(x, 0, z) + outward) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0)
			WorldModels.Place("Hill", cf, model, { Height = rng:NextNumber(S.HillHeight.Min, S.HillHeight.Max), Shadows = false })
		end
	end)
	model.Parent = parent
	return true
end

-- Trees and bushes where `free(x, z)` says the ground is free, inside the
-- rectangle, plus a belt along the mountain feet outside the walls.
function Scenery.Forest(xEdge: number, zMin: number, zMax: number, parent: Instance, free: (number, number) -> boolean)
	local rng = Random.new(S.Seed + 1)
	local model = Instance.new("Model")
	model.Name = "Forest"
	local kinds = { "RoundTree", "RoundTree", "PineTree" }
	local function scatter(count: number, x0: number, x1: number, z0: number, z1: number, gap: number, check: boolean)
		local placed: { Vector3 } = {}
		local tries = 0
		while #placed < count and tries < count * 12 do
			tries += 1
			local p = Vector3.new(rng:NextNumber(x0, x1), 0, rng:NextNumber(z0, z1))
			local ok = not check or free(p.X, p.Z)
			for _, q in placed do
				if ok and (q - p).Magnitude < gap then
					ok = false
				end
			end
			if ok then
				table.insert(placed, p)
				local cf = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
				if rng:NextNumber() < S.BushShare then
					bush(cf, model, rng:NextNumber(0.9, 1.5))
				else
					Scenery.Tree(cf, model, rng:NextNumber(0.85, 1.35), kinds[rng:NextInteger(1, #kinds)])
				end
			end
		end
	end
	-- Inside the walls: only where `free` allows.
	scatter(S.InsideTrees, -xEdge + 4, xEdge - 4, zMin + 4, zMax - 4, 9, true)
	-- Outside, between the walls and the mountains: a belt on each side.
	local belt = S.OutsideBelt
	for _, r in {
		{ -xEdge - belt, xEdge + belt, zMin - belt, zMin - 3 },
		{ -xEdge - belt, xEdge + belt, zMax + 3, zMax + belt },
		{ -xEdge - belt, -xEdge - 3, zMin, zMax },
		{ xEdge + 3, xEdge + belt, zMin, zMax },
	} do
		local area = (r[2] - r[1]) * (r[4] - r[3])
		local count = math.floor(S.OutsideTreesPer1000 * area / 1000)
		scatter(count, r[1], r[2], r[3], r[4], 10, true)
	end
	model.Parent = parent
end

return Scenery
