--!strict
-- Dine-in customers. After buying (CustomerAI), a customer may sit at a free chair
-- of a placed Café Table (BuildCatalog "CafeTable"), eat the cake at the table for
-- Config.DineIn.EatTime seconds, then leave a tip (TipMin..TipMax of what they
-- paid; doubled by the 2x Cash pass like any earning) and walk out.
-- Chairs are reserved with the attribute Occupied; a table with a diner can't be
-- moved or stored (BuildService blocker).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Services = script:FindFirstAncestor("Services") :: Folder
local BuildService = require(Services.Build.BuildService)
local CustomerLook = require(Services.Customers.CustomerLook)
local DataManager = require(Services.Core.DataManager)
local NPCKit = require(Services.Customers.NPCKit)
local PlotManager = require(Services.Core.PlotManager)

local DineIn = {}

local TABLE_ID = "CafeTable"

-- Free chairs of every placed café table on the plot: { chair, table }.
local function freeChairs(plot: Model): { { chair: BasePart, table: Model } }
	local list = {}
	local placed = plot:FindFirstChild("Placed")
	for _, model in (if placed then placed:GetChildren() else {}) do
		if model:IsA("Model") and model:GetAttribute("CatalogId") == TABLE_ID and not model:GetAttribute("Broken") then
			for _, part in model:GetChildren() do
				if part.Name == "Chair" and part:IsA("BasePart") and not part:GetAttribute("Occupied") then
					table.insert(list, { chair = part, table = model })
				end
			end
		end
	end
	return list
end

-- Little cake on the table in front of the diner (removed when they leave).
local function servePlate(tableModel: Model, chair: BasePart, cakeType: string?): Model
	local top = tableModel:FindFirstChild("TableTop") :: BasePart?
	local centre = if top then top.Position else tableModel:GetPivot().Position
	local towards = (chair.Position - centre) * Vector3.new(1, 0, 1)
	local at = centre + (if towards.Magnitude > 0 then towards.Unit * 1.2 else Vector3.zero) + Vector3.new(0, 0.3, 0)
	local plate = Instance.new("Model")
	plate.Name = "DinerPlate"
	local function piece(name: string, size: Vector3, offset: number, color: Color3)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = size
		p.CFrame = CFrame.new(at + Vector3.new(0, offset, 0)) * CFrame.Angles(0, 0, math.rad(90))
		p.Color = color
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = plate
	end
	local cake = cakeType and Recipes.Cakes[cakeType]
	piece("Plate", Vector3.new(0.12, 1.6, 1.6), 0, Color3.new(1, 1, 1))
	piece("Cake", Vector3.new(0.6, 1, 1), 0.36, if cake and cake.Color then cake.Color else Color3.fromRGB(255, 170, 200))
	plate.Parent = tableModel
	return plate
end

-- Tries to seat `npc` (who just paid `paid` for a `cakeType` cake on `plot`). Yields
-- for the whole meal. Returns false straight away if they don't stay.
function DineIn.TrySit(npc: Model, plot: Model, paid: number, cakeType: string?, tracks: CustomerLook.Tracks): boolean
	if math.random() >= Config.DineIn.Chance then
		return false
	end
	local chairs = freeChairs(plot)
	if #chairs == 0 then
		return false
	end
	local pick = chairs[math.random(#chairs)]
	local chair, tableModel = pick.chair, pick.table
	chair:SetAttribute("Occupied", true)

	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = npc.PrimaryPart :: BasePart
	local centre = tableModel:GetPivot().Position
	local away = (chair.Position - centre) * Vector3.new(1, 0, 1)
	away = if away.Magnitude > 0 then away.Unit else Vector3.new(0, 0, 1)
	local standAt = Vector3.new(chair.Position.X, 0, chair.Position.Z) + away * 2
	local ok = NPCKit.WalkTo(npc, standAt, Config.CustomerTripTimeout)
	if not ok or not npc.Parent or not chair.Parent then
		chair:SetAttribute("Occupied", nil)
		return false
	end

	-- Sit: face the table, drop onto the chair, play the sit pose.
	local seatTop = chair.Position.Y + chair.Size.Y / 2
	local look = Vector3.new(centre.X, seatTop, centre.Z)
	root.Anchored = true
	npc:PivotTo(CFrame.lookAt(Vector3.new(chair.Position.X, seatTop + root.Size.Y / 2 + humanoid.HipHeight * 0.35, chair.Position.Z), look))
	if tracks.idle then
		tracks.idle:Stop(0.2)
	end
	if tracks.sit then
		tracks.sit:Play(0.2)
	end
	local plate = servePlate(tableModel, chair, cakeType)
	CustomerLook.SetBubble(npc, "🍰 Nom nom...")

	local finishAt = os.clock() + Config.DineIn.EatTime
	while os.clock() < finishAt and npc.Parent and chair.Parent do
		task.wait(0.5)
	end
	plate:Destroy()

	if npc.Parent and chair.Parent then
		local owner = PlotManager.GetOwner(plot)
		local tip = math.max(1, math.floor(paid * (Config.DineIn.TipMin + math.random() * (Config.DineIn.TipMax - Config.DineIn.TipMin)) + 0.5))
		if owner then
			tip = DataManager.EarnCash(owner, tip)
			DataManager.AddStat(owner, "TotalEarned", tip)
		end
		CustomerLook.SetBubble(npc, "😊 Delicious!")
		CustomerLook.PopText(npc, `+${tip} tip!`, Color3.fromRGB(255, 220, 120))
		CustomerLook.PlaySound(root, Config.Sounds.Sale)
		task.wait(1.2)
	end
	if tracks.sit then
		tracks.sit:Stop(0.2)
	end
	if tracks.idle then
		tracks.idle:Play(0.2)
	end
	if npc.Parent then
		npc:PivotTo(CFrame.new(standAt + Vector3.new(0, root.Size.Y / 2 + humanoid.HipHeight, 0)))
		root.Anchored = false
	end
	chair:SetAttribute("Occupied", nil)
	return true
end

function DineIn.Init()
	table.insert(BuildService.Blockers, function(model: Model, _action: string): string?
		if model:GetAttribute("CatalogId") ~= TABLE_ID then
			return nil
		end
		for _, part in model:GetChildren() do
			if part:GetAttribute("Occupied") then
				return "A customer is eating there: wait until they leave."
			end
		end
		return nil
	end)
end

return DineIn
