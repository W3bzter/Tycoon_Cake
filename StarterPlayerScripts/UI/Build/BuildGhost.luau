--!strict
-- Build mode visuals and geometry on the client (UI/Build): the see-through ghost
-- of the item being placed, its footprint plate, and the grid / no-build overlay.
-- Uses Shared/BuildRules and the plot's BuildReserved attribute, so the preview
-- agrees with what the server (Build/BuildService) will accept. Preview only:
-- the server re-checks everything.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildRules = require(Shared:WaitForChild("BuildRules"))
local Config = require(Shared:WaitForChild("Config"))

local BuildGhost = {}

local OK_COLOR = Color3.fromRGB(90, 230, 120)
local BAD_COLOR = Color3.fromRGB(255, 80, 80)
local GRID_COLOR = Color3.fromRGB(255, 255, 255)
local QUARTER = math.pi / 2

export type Ghost = {
	Model: Model,
	Set: (plot: Model, gx: number, gz: number, rot: number, ok: boolean, rect: BuildRules.Rect) -> (),
	Destroy: () -> (),
}

local function visualPart(color: Color3, transparency: number): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Transparency = transparency
	return p
end

-- The local player's plot (PlotManager sets the PlotName attribute).
function BuildGhost.Plot(): Model?
	local name = Players.LocalPlayer:GetAttribute("PlotName")
	local plots = workspace:FindFirstChild("Plots")
	local plot = if typeof(name) == "string" and plots then plots:FindFirstChild(name) else nil
	if plot and plot:IsA("Model") and plot.PrimaryPart then
		return plot
	end
	return nil
end

function BuildGhost.Template(id: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("BuildTemplates")
	local template = folder and folder:FindFirstChild(id)
	return if template and template:IsA("Model") then template else nil
end

function BuildGhost.Footprint(id: string): BuildRules.Rect?
	local template = BuildGhost.Template(id)
	return if template then BuildRules.Footprint(template) else nil
end

-- Grid cell and rotation of a placed model (the inverse of BuildRules.LocalCFrame).
function BuildGhost.CellOf(plot: Model, model: Model): (number, number, number)
	local cf = BuildRules.Floor(plot):ToObjectSpace(model:GetPivot())
	local g = Config.Build.Grid
	local look = cf.LookVector -- CFrame.Angles(0, a, 0).LookVector = (-sin a, 0, -cos a)
	local rot = math.round(math.atan2(-look.X, -look.Z) / QUARTER) % 4
	return math.round(cf.Position.X / g), math.round(cf.Position.Z / g), rot
end

-- Rects of every placed item on the plot except `ignore` (the one being moved).
local function placedRects(plot: Model, ignore: Model?): { BuildRules.Rect }
	local rects = {}
	local folder = plot:FindFirstChild("Placed")
	for _, model in (if folder then folder:GetChildren() else {}) do
		local id = model:GetAttribute("CatalogId")
		local foot = if typeof(id) == "string" then BuildGhost.Footprint(id) else nil
		if model ~= ignore and model:IsA("Model") and foot then
			local gx, gz, rot = BuildGhost.CellOf(plot, model)
			table.insert(rects, BuildRules.Place(foot, gx, gz, rot))
		end
	end
	return rects
end

-- The server's no-build rects for this plot (walls, entrance path, unbought buttons).
function BuildGhost.Reserved(plot: Model): { BuildRules.Rect }
	local rects = {}
	local raw = plot:GetAttribute("BuildReserved")
	if typeof(raw) == "string" then
		local ok, packed = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(packed) == "table" then
			for _, r in packed do
				table.insert(rects, { X0 = r[1], X1 = r[2], Z0 = r[3], Z1 = r[4] })
			end
		end
	end
	return rects
end

-- Same check the server runs: (ok, reason, rect).
function BuildGhost.Check(plot: Model, id: string, gx: number, gz: number, rot: number, ignore: Model?): (boolean, string?, BuildRules.Rect?)
	local foot = BuildGhost.Footprint(id)
	if not foot then
		return false, "still loading", nil
	end
	local rect = BuildRules.Place(foot, gx, gz, rot)
	local ok, reason = BuildRules.Check(rect, BuildGhost.Reserved(plot), placedRects(plot, ignore))
	return ok, reason, rect
end

-- The grid cell a screen ray points at on the plot floor (nil if it misses the floor plane).
function BuildGhost.CellAt(plot: Model, ray: Ray): (number?, number?)
	local floor = BuildRules.Floor(plot)
	local origin = floor:PointToObjectSpace(ray.Origin)
	local dir = floor:VectorToObjectSpace(ray.Direction)
	if dir.Y > -1e-3 then
		return nil, nil
	end
	local hit = origin + dir * (-origin.Y / dir.Y)
	local g = Config.Build.Grid
	return math.round(hit.X / g), math.round(hit.Z / g)
end

-- A see-through copy of catalog item `id` with a coloured footprint plate under it.
function BuildGhost.New(id: string): Ghost?
	local template = BuildGhost.Template(id)
	if not template then
		return nil
	end
	local model = template:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 0.4 + d.Transparency * 0.6
			d.CastShadow = false
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = math.max(d.Transparency, 0.4)
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.65
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	local plate = visualPart(OK_COLOR, 0.45)
	plate.Material = Enum.Material.Neon
	model.Parent = workspace.CurrentCamera
	plate.Parent = workspace.CurrentCamera

	local ghost = {} :: Ghost
	ghost.Model = model
	function ghost.Set(plot, gx, gz, rot, ok, rect)
		local floor = BuildRules.Floor(plot)
		model:PivotTo(floor * BuildRules.LocalCFrame(gx, gz, rot))
		local color = if ok then OK_COLOR else BAD_COLOR
		highlight.FillColor = color
		highlight.OutlineColor = color
		plate.Color = color
		plate.Size = Vector3.new(math.max(rect.X1 - rect.X0, 0.2), 0.1, math.max(rect.Z1 - rect.Z0, 0.2))
		plate.CFrame = floor * CFrame.new((rect.X0 + rect.X1) / 2, 0.08, (rect.Z0 + rect.Z1) / 2)
	end
	function ghost.Destroy()
		model:Destroy()
		plate:Destroy()
	end
	return ghost
end

-- Grid lines over the plot floor plus red plates where nothing may be built.
local overlay: Folder? = nil
local overlayConn: RBXScriptConnection? = nil

function BuildGhost.HideOverlay()
	if overlayConn then
		overlayConn:Disconnect()
		overlayConn = nil
	end
	if overlay then
		overlay:Destroy()
		overlay = nil
	end
end

function BuildGhost.ShowOverlay(plot: Model)
	BuildGhost.HideOverlay()
	local folder = Instance.new("Folder")
	folder.Name = "BuildOverlay"
	overlay = folder
	local floor = BuildRules.Floor(plot)
	local b = Config.Build.Bounds
	local g = Config.Build.Grid
	local w, d = b.MaxX - b.MinX, b.MaxZ - b.MinZ
	local cx, cz = (b.MinX + b.MaxX) / 2, (b.MinZ + b.MaxZ) / 2
	-- Lines sit on cell edges: items pivot on cell centres (multiples of Grid).
	for x = (math.ceil(b.MinX / g - 0.5) + 0.5) * g, b.MaxX, g do
		local line = visualPart(GRID_COLOR, 0.8)
		line.Size = Vector3.new(0.08, 0.04, d)
		line.CFrame = floor * CFrame.new(x, 0.04, cz)
		line.Parent = folder
	end
	for z = (math.ceil(b.MinZ / g - 0.5) + 0.5) * g, b.MaxZ, g do
		local line = visualPart(GRID_COLOR, 0.8)
		line.Size = Vector3.new(w, 0.04, 0.08)
		line.CFrame = floor * CFrame.new(cx, 0.04, z)
		line.Parent = folder
	end
	local blocked = Instance.new("Folder")
	blocked.Name = "Reserved"
	blocked.Parent = folder
	local function drawReserved()
		blocked:ClearAllChildren()
		for _, r in BuildGhost.Reserved(plot) do
			local plate = visualPart(BAD_COLOR, 0.75)
			plate.Size = Vector3.new(math.max(r.X1 - r.X0, 0.1), 0.06, math.max(r.Z1 - r.Z0, 0.1))
			plate.CFrame = floor * CFrame.new((r.X0 + r.X1) / 2, 0.05, (r.Z0 + r.Z1) / 2)
			plate.Parent = blocked
		end
	end
	drawReserved()
	overlayConn = plot:GetAttributeChangedSignal("BuildReserved"):Connect(drawReserved)
	folder.Parent = workspace.CurrentCamera
end

return BuildGhost
