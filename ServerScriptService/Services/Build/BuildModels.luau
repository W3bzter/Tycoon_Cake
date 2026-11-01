--!strict
-- Builds placeable items (Shared/BuildCatalog). Each item is built once with the
-- plot-origin floor frame, then its pivot is set to the grid cell nearest its
-- centre (floor height). Old fixed builders (ItemBuilders) therefore keep working
-- unchanged, and an item placed at Default(id) sits exactly where it used to be.
--
-- Templates (one per catalog id, no prompts or scripts) go to
-- ReplicatedStorage.BuildTemplates for the client's ghost preview; they carry the
-- footprint as attributes FootX0/X1/Z0/Z1 (see Shared/BuildRules) and the
-- default cell as DefaultGX/DefaultGZ.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local BuildRules = require(Shared:WaitForChild("BuildRules"))
local Config = require(Shared:WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local DecorBuilders = require(Services.World.DecorBuilders)
local ItemBuilders = require(Services.World.ItemBuilders)
local MachineBuilders = require(Services.World.MachineBuilders)
local Skins = require(Services.World.Skins)

local BuildModels = {}

type Info = { foot: BuildRules.Rect, defaultGX: number, defaultGZ: number }
local infos: { [string]: Info } = {}

local function runBuilders(id: string, model: Model)
	local floor = CFrame.new()
	if id == "BigMixer" then
		ItemBuilders.Mixer(floor, model)
		ItemBuilders.BigMixer(floor, model)
	elseif DecorBuilders[id] then
		DecorBuilders[id](floor, model)
	elseif MachineBuilders[id] then
		MachineBuilders[id](floor, model)
	elseif ItemBuilders[id] then
		ItemBuilders[id](floor, model)
	else
		warn(`[BuildModels] no builder for {id}`)
	end
	Skins.Apply(model, id) -- detailed Blender model over the primitives, if imported
end

-- A fresh model of catalog item `id`, pivoted on its grid cell (not parented).
function BuildModels.Build(id: string): Model
	local model = Instance.new("Model")
	model.Name = id
	runBuilders(id, model)
	local g = Config.Build.Grid
	local info = infos[id]
	if not info then
		local cf, size = model:GetBoundingBox()
		local gx, gz = math.round(cf.Position.X / g), math.round(cf.Position.Z / g)
		local px, pz = gx * g, gz * g
		local entry = BuildCatalog.Find(id)
		local front = entry and entry.Front or 0
		info = {
			foot = {
				X0 = cf.Position.X - size.X / 2 - px,
				X1 = cf.Position.X + size.X / 2 - px,
				Z0 = cf.Position.Z - size.Z / 2 - pz,
				Z1 = cf.Position.Z + size.Z / 2 - pz + front,
			},
			defaultGX = gx,
			defaultGZ = gz,
		}
		infos[id] = info
	end
	model.WorldPivot = CFrame.new(info.defaultGX * g, 0, info.defaultGZ * g)
	model:SetAttribute("CatalogId", id)
	return model
end

function BuildModels.Footprint(id: string): BuildRules.Rect
	if not infos[id] then
		BuildModels.Build(id):Destroy()
	end
	return infos[id].foot
end

-- The cell an item stood on before placement existed (old saves).
function BuildModels.Default(id: string): (number, number)
	if not infos[id] then
		BuildModels.Build(id):Destroy()
	end
	return infos[id].defaultGX, infos[id].defaultGZ
end

-- Moves a built model to (gx, gz, rot) on `plot`.
function BuildModels.PlaceAt(model: Model, plot: Model, gx: number, gz: number, rot: number)
	model:PivotTo(BuildRules.Floor(plot) * BuildRules.LocalCFrame(gx, gz, rot))
end

function BuildModels.Init()
	Skins.Report()
	local folder = Instance.new("Folder")
	folder.Name = "BuildTemplates"
	for _, entry in BuildCatalog.List do
		local template = BuildModels.Build(entry.Id)
		local foot = infos[entry.Id].foot
		template:SetAttribute("FootX0", foot.X0)
		template:SetAttribute("FootX1", foot.X1)
		template:SetAttribute("FootZ0", foot.Z0)
		template:SetAttribute("FootZ1", foot.Z1)
		template:SetAttribute("DefaultGX", infos[entry.Id].defaultGX)
		template:SetAttribute("DefaultGZ", infos[entry.Id].defaultGZ)
		for _, d in template:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			elseif d:IsA("BillboardGui") or d:IsA("LuaSourceContainer") then
				d:Destroy()
			end
		end
		template:PivotTo(CFrame.new())
		template.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

return BuildModels
