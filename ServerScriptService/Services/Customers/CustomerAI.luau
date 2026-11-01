--!strict
-- Customer NPCs wearing the plot owner's friends' avatars (AvatarService).
-- They spawn at the bus stop, pathfind to the display counter with idle/walk
-- animations, show a bubble with the cake they want, buy (tipping 20% if it's the
-- cake they wanted), react happily, pay the owner, then walk off and despawn.
-- A cake slot is reserved before the customer spawns, so two customers never
-- go for the same cake.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Services = script:FindFirstAncestor("Services") :: Folder
local AvatarService = require(Services.Customers.AvatarService)
local CustomerLook = require(Services.Customers.CustomerLook)
local BakingPipeline = require(Services.Baking.BakingPipeline)
local DataManager = require(Services.Core.DataManager)
local PlotManager = require(Services.Core.PlotManager)
local NPCKit = require(Services.Customers.NPCKit)
local PlotStats = require(Services.Core.PlotStats)

local CustomerAI = {}

local buildNpc, setupAnimations, setBubble, popText = CustomerLook.BuildNpc, CustomerLook.SetupAnimations, CustomerLook.SetBubble, CustomerLook.PopText
local playSound, celebrate, makeVIP = CustomerLook.PlaySound, CustomerLook.Celebrate, CustomerLook.MakeVIP
type Tracks = CustomerLook.Tracks
CustomerAI.PopText = popText

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
	-- Selling an Epic or better cake can also earn Gems (slowly).
	local rare = Config.RareCakeGems[info.Rarity]
	if rare and math.random() < rare[1] then
		gems += rare[2]
	end
	if owner then
		DataManager.AddCash(owner, pay)
		DataManager.RecordSale(owner)
		DataManager.AddStat(owner, "TotalEarned", pay)
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

-- Lifecycle ----------------------------------------------------------------------------

local function counterStandPoint(slot: BasePart): Vector3
	-- Customers stand in front of the counter (its +Z side, whichever way it was placed).
	local p = (slot.CFrame * CFrame.new(0, 0, Config.CustomerStandOff)).Position
	return Vector3.new(p.X, 0, p.Z)
end

local function walkTo(npc: Model, target: Vector3): boolean
	return NPCKit.WalkTo(npc, target, Config.CustomerTripTimeout)
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
				-- A haunted plot (Phantom anomaly) scares customers away.
				if owner and not plot:GetAttribute("Haunted") and now >= (nextSpawn[plot] or 0) and #BakingPipeline.GetSaleSlots(plot) > 0 then
					nextSpawn[plot] = now + Config.CustomerInterval * PlotStats.Get(owner).CustomerRate
					task.spawn(CustomerAI.TrySpawnForPlot, plot) -- avatar loading yields
				end
			end
		end
	end)
end

return CustomerAI
