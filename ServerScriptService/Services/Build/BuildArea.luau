--!strict
-- Where players may NOT place things, as plot-local rects (Shared/BuildRules):
--   * every ground-level part of every fixed item (walls, pantry, stairs, the
--     automation machines...), found automatically from the built plot
--     (only the owner's size stage of staged items like the walls)
--   * Config.Build.Reserved (the entrance path for customers, the annex doorway)
-- and where they MAY: BuildRules.StageAreas(stage) (inside the walls + the front patio).
-- Both are mirrored to plot attributes (BuildReserved as JSON, BuildStage) so the
-- client's preview uses exactly the same rules.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildRules = require(Shared:WaitForChild("BuildRules"))
local Config = require(Shared:WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local TycoonButtons = require(Services.World.TycoonButtons)

local BuildArea = {}

local fixed: { [Model]: { [number]: { BuildRules.Rect } } } = {} -- plot -> stage -> static rects

-- The Stage of the nearest Stage-tagged model around `inst` inside `item`, if any.
local function stageAround(inst: Instance, item: Instance): number?
	local node: Instance? = inst
	while node and node ~= item do
		local stage = node:GetAttribute("Stage")
		if typeof(stage) == "number" then
			return stage
		end
		node = node.Parent
	end
	return nil
end

-- Plot-local XZ rect of a part (axis-aligned bounds of its rotated box).
local function partRect(floor: CFrame, part: BasePart): (BuildRules.Rect, number, number)
	local cf = floor:ToObjectSpace(part.CFrame)
	local half = part.Size / 2
	local x0, x1, z0, z1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local p = cf * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
				x0, x1 = math.min(x0, p.X), math.max(x1, p.X)
				z0, z1 = math.min(z0, p.Z), math.max(z1, p.Z)
				y0, y1 = math.min(y0, p.Y), math.max(y1, p.Y)
			end
		end
	end
	return { X0 = x0, X1 = x1, Z0 = z0, Z1 = z1 }, y0, y1
end

-- Collects the static rects once per stage (fixed items exist from server start).
local function staticRects(plot: Model, stage: number): { BuildRules.Rect }
	fixed[plot] = fixed[plot] or {}
	if fixed[plot][stage] then
		return fixed[plot][stage]
	end
	local rects: { BuildRules.Rect } = {}
	local floor = BuildRules.Floor(plot)
	local items = plot:FindFirstChild("Items")
	for _, item in (if items then items:GetChildren() else {}) do
		for _, d in item:GetDescendants() do
			local partStage = d:IsA("BasePart") and stageAround(d, item)
			if d:IsA("BasePart") and (not partStage or partStage == stage) then
				local rect, bottom, top = partRect(floor, d)
				-- Ground-level, solid-ish parts only: skips floor tiles/rugs, roofs, signs and the upstairs deck.
				if bottom < 3 and top - bottom >= 0.6 then
					table.insert(rects, rect)
				end
			end
		end
	end
	for _, r in Config.Build.Reserved do
		table.insert(rects, { X0 = r.X0, X1 = r.X1, Z0 = r.Z0, Z1 = r.Z1 })
	end
	fixed[plot][stage] = rects
	return rects
end

-- All reserved rects for `plot` at its owner's bakery size.
function BuildArea.Reserved(plot: Model, owner: Player?): { BuildRules.Rect }
	return table.clone(staticRects(plot, TycoonButtons.Stage(owner)))
end

-- Where the owner may place things (inside their bakery's current size + the patio).
function BuildArea.Areas(_plot: Model, owner: Player?): { BuildRules.Bounds }
	return BuildRules.StageAreas(TycoonButtons.Stage(owner))
end

-- Mirrors the reserved rects to the plot for the client preview.
function BuildArea.Publish(plot: Model, owner: Player?)
	local packed = {}
	for _, r in BuildArea.Reserved(plot, owner) do
		table.insert(packed, { math.floor(r.X0 * 10) / 10, math.ceil(r.X1 * 10) / 10, math.floor(r.Z0 * 10) / 10, math.ceil(r.Z1 * 10) / 10 })
	end
	plot:SetAttribute("BuildStage", TycoonButtons.Stage(owner))
	plot:SetAttribute("BuildReserved", HttpService:JSONEncode(packed))
end

return BuildArea
