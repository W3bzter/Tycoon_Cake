--!strict
-- Customer NPCs: spawn on the street, pathfind to a plot's display counter,
-- buy a cake (sound + hop/animation), pay the plot owner, walk off and despawn.
-- A cake slot is reserved before the customer spawns, so two customers never
-- go for the same cake.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local BakingPipeline = require(script.Parent.BakingPipeline)
local DataManager = require(script.Parent.DataManager)
local PlotManager = require(script.Parent.PlotManager)

local CustomerAI = {}

export type CustomerOptions = {
	-- Called when the customer reaches the counter with its reserved slot.
	-- Return false to make the customer leave without the default purchase.
	OnArrive: ((npc: Model, plot: Model, slot: BasePart) -> boolean?)?,
	Decorate: ((npc: Model) -> ())?,
	IgnoreCap: boolean?, -- anomaly NPCs spawn even when the street is full
}

local active: { [Model]: boolean } = {}
local npcFolder: Folder

-- NPC construction ---------------------------------------------------------------

local function buildBlockNpc(): Model
	-- Fallback rig: a few welded blocks + Humanoid. Walks fine without animations.
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Parent = model

	local function limb(name: string, size: Vector3, offset: Vector3, color: Color3)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.CFrame = root.CFrame * CFrame.new(offset)
		p.CanCollide = false
		p.Massless = true
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
	end
	limb("Torso", Vector3.new(2, 2, 1), Vector3.zero, Color3.fromRGB(90, 140, 220))
	limb("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0), Color3.fromRGB(255, 220, 180))
	limb("Legs", Vector3.new(2, 2, 1), Vector3.new(0, -2, 0), Color3.fromRGB(60, 60, 80))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.HipHeight = 2
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

local function buildNpc(): Model
	local ok, model = pcall(function()
		local description = Instance.new("HumanoidDescription")
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		return model
	end
	return buildBlockNpc()
end

-- Movement ------------------------------------------------------------------------

-- Polls instead of MoveToFinished:Wait(), which never returns if the NPC is
-- destroyed mid-walk (e.g. a stopped Mimic) and would leak the coroutine.
local function moveTo(humanoid: Humanoid, position: Vector3): boolean
	local done, reached = false, false
	local conn = humanoid.MoveToFinished:Once(function(result)
		done, reached = true, result
	end)
	humanoid:MoveTo(position)
	local started = os.clock()
	while not done and humanoid:IsDescendantOf(workspace) and os.clock() - started < 8 do
		task.wait(0.1)
	end
	conn:Disconnect()
	return reached
end

-- Walks along a computed path; recomputes when blocked and teleports as a last resort.
local function walkTo(npc: Model, target: Vector3): boolean
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = npc.PrimaryPart :: BasePart
	local deadline = os.clock() + Config.CustomerTripTimeout
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
	})

	for _attempt = 1, 3 do
		if npc.Parent == nil or humanoid.Health <= 0 then
			return false
		end
		local ok = pcall(function()
			path:ComputeAsync(root.Position, target)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local blocked = false
			for _, waypoint in path:GetWaypoints() do
				if npc.Parent == nil or os.clock() > deadline then
					return false
				end
				if waypoint.Action == Enum.PathWaypointAction.Jump then
					humanoid.Jump = true
				end
				if not moveTo(humanoid, waypoint.Position) then
					blocked = true
					break
				end
			end
			if not blocked then
				return true
			end
		elseif moveTo(humanoid, target) then
			return true -- no path, but a straight walk worked
		end
	end

	-- Stuck: snap to the goal so the shop keeps moving.
	if npc.Parent then
		npc:PivotTo(CFrame.new(target + Vector3.new(0, 3, 0)))
		return true
	end
	return false
end

-- Purchase --------------------------------------------------------------------------

local function playSound(parent: Instance, soundId: string)
	if soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Parent = parent
	sound:Play()
	task.delay(3, sound.Destroy, sound)
end

local function popText(npc: Model, text: string, color: Color3)
	local head = npc:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(4, 1.5)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	gui.Parent = head
	task.delay(2, gui.Destroy, gui)
end
CustomerAI.PopText = popText

local function celebrate(npc: Model)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if Config.Animations.Buy ~= "" then
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		local animation = Instance.new("Animation")
		animation.AnimationId = Config.Animations.Buy
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if ok and track then
			track:Play()
			return
		end
	end
	humanoid.Jump = true
end

local function defaultPurchase(npc: Model, plot: Model, slot: BasePart)
	local ok, cakeType = BakingPipeline.TakeCake(plot, slot)
	if not ok then
		return
	end
	local cake = Recipes.Cakes[cakeType or "Vanilla"] or Recipes.Cakes.Vanilla
	local owner = PlotManager.GetOwner(plot)
	if owner then
		DataManager.AddCash(owner, cake.Price)
	end
	playSound(npc.PrimaryPart :: BasePart, Config.Sounds.Sale)
	popText(npc, `+${cake.Price}`, Color3.fromRGB(120, 255, 120))
	celebrate(npc)
end

-- Lifecycle ----------------------------------------------------------------------------

local function counterStandPoint(slot: BasePart): Vector3
	-- Plots face +Z (the street), so customers stand on the street side of the counter.
	return Vector3.new(slot.Position.X, 0, slot.Position.Z + Config.CustomerStandOff)
end

function CustomerAI.Spawn(plot: Model, slot: BasePart, options: CustomerOptions?): Model?
	local street = workspace:FindFirstChild("Street")
	local spawnPad = street and street:FindFirstChild("CustomerSpawn") :: BasePart?
	local despawnPad = street and street:FindFirstChild("CustomerDespawn") :: BasePart?
	if not spawnPad or not despawnPad then
		BakingPipeline.ReleaseSlot(slot)
		return nil
	end

	local npc = buildNpc()
	npc.Name = "Customer"
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = Config.CustomerWalkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	npc:PivotTo(spawnPad.CFrame * CFrame.new(0, 4, 0))
	if options and options.Decorate then
		options.Decorate(npc)
	end
	npc.Parent = npcFolder
	local root = npc.PrimaryPart :: BasePart
	pcall(function()
		root:SetNetworkOwner(nil) -- server drives the NPC; avoids client-owned jitter
	end)
	active[npc] = true

	task.spawn(function()
		local arrived = walkTo(npc, counterStandPoint(slot))
		if arrived and npc.Parent and slot:GetAttribute("HasCake") then
			local doDefault = true
			if options and options.OnArrive then
				doDefault = options.OnArrive(npc, plot, slot) ~= false
			end
			if doDefault then
				defaultPurchase(npc, plot, slot)
			end
			task.wait(1)
		else
			BakingPipeline.ReleaseSlot(slot)
		end

		if npc.Parent then
			walkTo(npc, despawnPad.Position)
		end
		active[npc] = nil
		npc:Destroy()
	end)

	return npc
end

function CustomerAI.Count(): number
	local n = 0
	for _ in active do
		n += 1
	end
	return n
end

-- Picks a random owned plot with an unreserved cake for sale and sends a customer.
function CustomerAI.TrySpawnForAnyPlot(options: CustomerOptions?): Model?
	if CustomerAI.Count() >= Config.MaxCustomers and not (options and options.IgnoreCap) then
		return nil
	end
	local candidates = {}
	for _, plot in (workspace:WaitForChild("Plots") :: Folder):GetChildren() do
		if plot:IsA("Model") and PlotManager.GetOwner(plot) then
			for _, slot in BakingPipeline.GetSaleSlots(plot) do
				table.insert(candidates, { plot = plot, slot = slot })
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	local pick = candidates[math.random(#candidates)]
	if not BakingPipeline.ReserveSlot(pick.slot) then
		return nil
	end
	return CustomerAI.Spawn(pick.plot, pick.slot, options)
end

function CustomerAI.Init()
	npcFolder = Instance.new("Folder")
	npcFolder.Name = "Customers"
	npcFolder.Parent = workspace

	task.spawn(function()
		while true do
			task.wait(Config.CustomerInterval)
			CustomerAI.TrySpawnForAnyPlot()
		end
	end)
end

return CustomerAI
