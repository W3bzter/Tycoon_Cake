--!strict
-- Placement geometry shared by the server (authority) and the client preview.
-- Everything is in plot-local studs on the floor plane (X, Z).
--   Footprint: an item's rect around its pivot at rotation 0 (from its template)
--   Rect:      { X0, X1, Z0, Z1 } in plot space
-- rot is 0..3 (quarter turns around Y).

local Config = require(script.Parent:WaitForChild("Config"))

export type Rect = { X0: number, X1: number, Z0: number, Z1: number }

local BuildRules = {}

local EPS = 0.05

-- The footprint rect a template carries (attributes set by the server).
function BuildRules.Footprint(template: Instance): Rect
	return {
		X0 = (template:GetAttribute("FootX0") :: number?) or -1,
		X1 = (template:GetAttribute("FootX1") :: number?) or 1,
		Z0 = (template:GetAttribute("FootZ0") :: number?) or -1,
		Z1 = (template:GetAttribute("FootZ1") :: number?) or 1,
	}
end

-- Footprint rotated by rot quarter turns and moved to grid cell (gx, gz).
function BuildRules.Place(foot: Rect, gx: number, gz: number, rot: number): Rect
	local corners = { { foot.X0, foot.Z0 }, { foot.X1, foot.Z1 } }
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	local a = (rot % 4) * math.pi / 2
	local c, s = math.round(math.cos(a)), math.round(math.sin(a))
	for _, cx in { corners[1][1], corners[2][1] } do
		for _, cz in { corners[1][2], corners[2][2] } do
			-- CFrame.Angles(0, a, 0) maps (x, z) to (x*c + z*s, -x*s + z*c)
			local rx, rz = cx * c + cz * s, -cx * s + cz * c
			x0, x1 = math.min(x0, rx), math.max(x1, rx)
			z0, z1 = math.min(z0, rz), math.max(z1, rz)
		end
	end
	local g = Config.Build.Grid
	local ox, oz = gx * g, gz * g
	return { X0 = x0 + ox, X1 = x1 + ox, Z0 = z0 + oz, Z1 = z1 + oz }
end

function BuildRules.Overlaps(a: Rect, b: Rect): boolean
	return a.X0 < b.X1 - EPS and b.X0 < a.X1 - EPS and a.Z0 < b.Z1 - EPS and b.Z0 < a.Z1 - EPS
end

-- Is `rect` inside the plot and clear of every reserved / other rect?
function BuildRules.Check(rect: Rect, reserved: { Rect }, others: { Rect }): (boolean, string?)
	local b = Config.Build.Bounds
	if rect.X0 < b.MinX - EPS or rect.X1 > b.MaxX + EPS or rect.Z0 < b.MinZ - EPS or rect.Z1 > b.MaxZ + EPS then
		return false, "outside your bakery"
	end
	for _, r in reserved do
		if BuildRules.Overlaps(rect, r) then
			return false, "in the way of something"
		end
	end
	for _, r in others do
		if BuildRules.Overlaps(rect, r) then
			return false, "overlaps another item"
		end
	end
	return true, nil
end

-- Plot-local CFrame of an item placed at (gx, gz, rot).
function BuildRules.LocalCFrame(gx: number, gz: number, rot: number): CFrame
	local g = Config.Build.Grid
	return CFrame.new(gx * g, 0, gz * g) * CFrame.Angles(0, (rot % 4) * math.pi / 2, 0)
end

-- Plot floor frame (origin = centre of the floor top).
function BuildRules.Floor(plot: Model): CFrame
	local base = plot.PrimaryPart :: BasePart
	return base.CFrame * CFrame.new(0, base.Size.Y / 2, 0)
end

return BuildRules
