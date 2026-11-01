--!strict
-- Customer NPCs wearing the plot owner's friends' avatars (AvatarService).
-- They spawn at the bus stop, pathfind to the display counter with idle/walk
-- animations, show a bubble with the cake they want, buy (tipping 20% if it's the
-- cake they wanted), react happily, pay the owner, then walk off and despawn.
-- A cake slot is reserved before the customer spawns, so two customers never
-- go for the same cake.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local AvatarService = require(script.Parent.AvatarService)
local BakingPipeline = require(script.Parent.BakingPipeline)
local DataManager = require(script.Parent.DataManager)
local PlotManager = require(script.Parent.PlotManager)
local PlotStats = require(script.Parent.PlotStats)

local CustomerAI = {}

export type CustomerOptions = {
	-- Called when the customer reaches the counter with its reserved slot.
	-- Return false to make the customer leave without the default purchase.
	OnArrive: ((npc: Model, plot: Model, slot: BasePart) -> boolean?)?,
	Decorate: ((npc: Model) -> ())?,
	IgnoreCap: boolean?, -- anomaly NPCs spawn even when the street is full
	Wanted: string?, -- cake type shown in the speech bubble
	VIP: boolean?, -- gold glow, pays Config.VIPPayMult, may tip Gems
	PlotFilter: ((plot: Model) -> boolean)?, -- restricts which plots can be picked
	PreferAnomaly: boolean?, -- Mimics go for Anomaly-touched cakes first
}

local active: { [Model]: boolean } = {}
local spawning = 0 -- customers being built (avatar loading yields)
local npcFolder: Folder

-- NPC construction ---------------------------------------------------------------

local function buildBlockNpc(): Model
	-- Last-resort rig if avatar creation fails: welded blocks + Humanoid.
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

local function buildNpc(visitor: AvatarService.Visitor): Model
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(visitor.Description, Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		return model
	end
	ok, model = pcall(function() -- the friend's outfit failed to load: plain styled look
		return Players:CreateHumanoidModelFromDescription(AvatarService.StyledDefault(), Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		return model
	end
	return buildBlockNpc()
end

-- Animations -----------------------------------------------------------------------

type Tracks = { idle: AnimationTrack?, walk: AnimationTrack?, cheer: AnimationTrack? }

local function loadTrack(animator: Animator, id: string, priority: Enum.AnimationPriority): AnimationTrack?
	if id == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Priority = priority
		return track
	end
	return nil
end

-- Server-side tracks on a server-owned NPC replicate to every client.
local function setupAnimations(npc: Model): Tracks
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return {}
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local a = animator :: Animator
	local tracks: Tracks = {
		idle = loadTrack(a, Config.Animations.Idle, Enum.AnimationPriority.Idle),
		walk = loadTrack(a, Config.Animations.Walk, Enum.AnimationPriority.Movement),
		cheer = loadTrack(a, Config.Animations.Cheer, Enum.AnimationPriority.Action),
	}
	if tracks.idle then
		tracks.idle.Looped = true
		tracks.idle:Play()
	end
	if tracks.walk then
		tracks.walk.Looped = true
	end
	humanoid.Running:Connect(function(speed)
		local walk = tracks.walk
		if not walk then
			return
		end
		if speed > 0.5 then
			if not walk.IsPlaying then
				walk:Play(0.2)
			end
			walk:AdjustSpeed(speed / 16)
		elseif walk.IsPlaying then
			walk:Stop(0.2)
		end
	end)
	return tracks
end

-- Bubbles & effects ----------------------------------------------------------------------

local function headOf(npc: Model): BasePart?
	return npc:FindFirstChild("Head") :: BasePart?
end

local function setBubble(npc: Model, text: string?)
	local head = headOf(npc)
	if not head then
		return
	end
	local existing = head:FindFirstChild("WantBubble")
	if existing then
		existing:Destroy()
	end
	if not text then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "WantBubble"
	gui.Size = UDim2.fromScale(5, 1.6)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 105, 160)
	stroke.Thickness = 2
	stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.92, 0.85)
	label.Position = UDim2.fromScale(0.04, 0.075)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(140, 90, 70)
	label.Text = text
	label.Parent = frame
	gui.Parent = head
end

local function popText(npc: Model, text: string, color: Color3)
	local head = headOf(npc)
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(5, 1.6)
	gui.StudsOffset = Vector3.new(0, 5, 0) -- above the want/thanks bubble (offset 3.2)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 60
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
	task.delay(2.5, gui.Destroy, gui)
end
CustomerAI.PopText = popText

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

local function happyBurst(npc: Model)
	local head = headOf(npc)
	if not head then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds" -- built-in texture
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 120, 170), Color3.fromRGB(255, 220, 90))
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new(0.6, 0)
	emitter.Lifetime = NumberRange.new(0.8, 1.2)
	emitter.Speed = NumberRange.new(6, 10)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Rate = 0
	emitter.Parent = head
	emitter:Emit(25)
	task.delay(2, emitter.Destroy, emitter)
end

local function celebrate(npc: Model, tracks: Tracks)
	happyBurst(npc)
	if tracks.cheer then
		tracks.cheer:Play()
	else
		local humanoid = npc:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Jump = true
		end
	end
end

local function defaultPurchase(npc: Model, plot: Model, slot: BasePart, options: CustomerOptions, tracks: Tracks)
	local ok, info = BakingPipeline.TakeCake(plot, slot)
	if not ok or not info then
		return
	end
	local cakeType = info.Type
	local owner = PlotManager.GetOwner(plot)
	local stats = PlotStats.Get(owner)
	local gotWanted = options.Wanted ~= nil and cakeType == options.Wanted
	local pay = info.Value * stats.SalePrice -- value from ingredient rarities/traits/mix quality
	if gotWanted then
		pay *= 1 + Config.WantedTip
	end
	if options.VIP then
		pay *= Config.VIPPayMult
	end
	pay = math.floor(pay + 0.5)

	local gems = 0
	if options.VIP and math.random() < Config.Gems.VIPGemChance then
		gems = math.random(1, Config.Gems.VIPGemMax)
	end
	if owner then
		DataManager.AddCash(owner, pay)
		DataManager.RecordSale(owner)
		if gems > 0 then
			DataManager.AddGems(owner, gems)
		end
	end

	setBubble(npc, if options.VIP then "👑 Exquisite!" elseif gotWanted then "😍 Yum!" else "😋 Thanks!")
	playSound(npc.PrimaryPart :: BasePart, Config.Sounds.Sale)
	local text = `+${pay}` .. (if gotWanted then " (tip!)" else "") .. (if gems > 0 then ` +💎{gems}` else "")
	popText(npc, text, if options.VIP then Color3.fromRGB(255, 215, 80) else Color3.fromRGB(120, 255, 120))
	celebrate(npc, tracks)
end

local function makeVIP(npc: Model)
	npc:SetAttribute("IsVIP", true)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 205, 60)
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = Color3.fromRGB(255, 230, 120)
	highlight.Parent = npc
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = "👑 " .. humanoid.DisplayName
	end
end

-- Lifecycle ----------------------------------------------------------------------------

local function counterStandPoint(slot: BasePart): Vector3
	-- Plots face +Z (the street), so customers stand on the street side of the counter.
	return Vector3.new(slot.Position.X, 0, slot.Position.Z + Config.CustomerStandOff)
end

local function moveTo(humanoid: Humanoid, position: Vector3): boolean
	-- Polls instead of MoveToFinished:Wait(), which never returns if the NPC is
	-- destroyed mid-walk (e.g. a stopped Mimic) and would leak the coroutine.
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

function CustomerAI.Spawn(plot: Model, slot: BasePart, options: CustomerOptions?): Model?
	local street = workspace:FindFirstChild("Street")
	local spawnPad = street and street:FindFirstChild("CustomerSpawn") :: BasePart?
	local despawnPad = street and street:FindFirstChild("CustomerDespawn") :: BasePart?
	if not spawnPad or not despawnPad then
		BakingPipeline.ReleaseSlot(slot)
		return nil
	end

	spawning += 1
	local visitor = AvatarService.PickVisitor(plot)
	local npc = buildNpc(visitor)
	spawning -= 1

	npc.Name = "Customer"
	npc:SetAttribute("VisitorUserId", visitor.UserId)
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = Config.CustomerWalkSpeed
	humanoid.DisplayName = visitor.DisplayName
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.NameDisplayDistance = 50
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	npc:PivotTo(spawnPad.CFrame * CFrame.new(0, 4, 0))
	local opts: CustomerOptions = options or {}
	if opts.VIP then
		makeVIP(npc)
	end
	if opts.Decorate then
		opts.Decorate(npc)
	end
	npc.Parent = npcFolder
	local root = npc.PrimaryPart :: BasePart
	pcall(function()
		root:SetNetworkOwner(nil) -- server drives the NPC; avoids client-owned jitter
	end)
	active[npc] = true

	local wanted = opts.Wanted
	if wanted and Recipes.Cakes[wanted] then
		local cake = Recipes.Cakes[wanted]
		setBubble(npc, (if opts.VIP then "👑 " else "") .. `{cake.Icon} {cake.DisplayName}, please!`)
	end
	local tracks = setupAnimations(npc)

	task.spawn(function()
		local arrived = walkTo(npc, counterStandPoint(slot))
		if arrived and npc.Parent and slot:GetAttribute("HasCake") then
			local doDefault = true
			if opts.OnArrive then
				doDefault = opts.OnArrive(npc, plot, slot) ~= false
			end
			if doDefault then
				defaultPurchase(npc, plot, slot, opts, tracks)
			end
			task.wait(2)
		else
			BakingPipeline.ReleaseSlot(slot)
		end

		if npc.Parent then
			setBubble(npc, nil)
			walkTo(npc, despawnPad.Position)
		end
		active[npc] = nil
		npc:Destroy()
	end)

	return npc
end

function CustomerAI.Count(): number
	local n = spawning
	for _ in active do
		n += 1
	end
	return n
end

-- Sends a customer to `plot`: decides what they want (from the owner's unlocked
-- recipes; VIPs want the priciest), and reserves that cake if it's on display,
-- otherwise any cake for sale.
function CustomerAI.TrySpawnForPlot(plot: Model, options: CustomerOptions?): Model?
	if CustomerAI.Count() >= Config.MaxCustomers and not (options and options.IgnoreCap) then
		return nil
	end
	local owner = PlotManager.GetOwner(plot)
	local slots = BakingPipeline.GetSaleSlots(plot)
	if not owner or #slots == 0 then
		return nil
	end

	local opts: CustomerOptions = {}
	for k, v in (options or {}) :: any do
		(opts :: any)[k] = v
	end
	local menu = Recipes.Unlocked(function(id)
		return DataManager.HasUnlock(owner, id)
	end)
	if opts.VIP == nil and not opts.OnArrive then -- anomaly NPCs are never VIPs
		opts.VIP = math.random() < PlotStats.Get(owner).VIPChance
	end
	opts.Wanted = opts.Wanted or (if opts.VIP then menu[#menu] else menu[math.random(#menu)])

	local slot = slots[math.random(#slots)]
	for _, s in slots do
		if s:GetAttribute("CakeType") == opts.Wanted then
			slot = s
			break
		end
	end
	if opts.PreferAnomaly then
		for _, s in slots do
			if s:GetAttribute("Anomaly") then
				slot = s -- Mimics are drawn to Anomaly-touched cakes
				break
			end
		end
	end
	if not BakingPipeline.ReserveSlot(slot) then
		return nil
	end
	return CustomerAI.Spawn(plot, slot, opts)
end

-- Picks a random owned plot with cakes for sale (optionally filtered).
function CustomerAI.TrySpawnForAnyPlot(options: CustomerOptions?): Model?
	local plots = {}
	for _, plot in (workspace:WaitForChild("Plots") :: Folder):GetChildren() do
		if
			plot:IsA("Model")
			and PlotManager.GetOwner(plot)
			and #BakingPipeline.GetSaleSlots(plot) > 0
			and (not options or not options.PlotFilter or options.PlotFilter(plot))
		then
			table.insert(plots, plot)
		end
	end
	if #plots == 0 then
		return nil
	end
	return CustomerAI.TrySpawnForPlot(plots[math.random(#plots)], options)
end

function CustomerAI.Init()
	npcFolder = Instance.new("Folder")
	npcFolder.Name = "Customers"
	npcFolder.Parent = workspace

	-- Each plot has its own timer, so Street Sign / Radio Ad speed up only that plot.
	local nextSpawn: { [Model]: number } = {}
	task.spawn(function()
		while true do
			task.wait(Config.SpawnCheckInterval)
			local now = os.clock()
			for _, plot in (workspace:WaitForChild("Plots") :: Folder):GetChildren() do
				local owner = plot:IsA("Model") and PlotManager.GetOwner(plot)
				if owner and now >= (nextSpawn[plot] or 0) and #BakingPipeline.GetSaleSlots(plot) > 0 then
					nextSpawn[plot] = now + Config.CustomerInterval * PlotStats.Get(owner).CustomerRate
					task.spawn(CustomerAI.TrySpawnForPlot, plot) -- avatar loading yields
				end
			end
		end
	end)
end

return CustomerAI
