--!strict
-- Build mode on the server. Players buy catalog items (Shared/BuildCatalog) into
-- their build inventory and place, move, rotate, store or upgrade them on a grid
-- inside their own bakery. Everything is validated here (owner, ownership,
-- requirements, money, bounds, overlaps, machine state); the client only previews.
--
-- Data: PlayerData.Build = { Owned = {id -> count}, Placed = {uid -> {Id, GX, GZ, Rot}}, NextUid, Migrated }
-- Placed models live in plot.Placed, named "<Id>_<uid>", with attributes
-- CatalogId, Kind, Uid, Visible. Other services react to ItemPlaced/ItemRemoved.
-- Remotes: BuildAction (client -> server), BuildSync (server -> client).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local BuildRules = require(Shared:WaitForChild("BuildRules"))
local Config = require(Shared:WaitForChild("Config"))
local PlotLayout = require(Shared:WaitForChild("PlotLayout"))

local Services = script:FindFirstAncestor("Services") :: Folder
local BuildArea = require(Services.Build.BuildArea)
local BuildModels = require(Services.Build.BuildModels)
local DataManager = require(Services.Core.DataManager)
local PlotManager = require(Services.Core.PlotManager)
local Remotes = require(Services.Core.Remotes)
local TycoonButtons = require(Services.World.TycoonButtons)

local BuildService = {}

local placedEvent = Instance.new("BindableEvent")
BuildService.ItemPlaced = placedEvent.Event -- (plot, model) after a model is spawned or rebuilt
local removedEvent = Instance.new("BindableEvent")
BuildService.ItemRemoved = removedEvent.Event -- (plot, model) just before a model is destroyed
local movedEvent = Instance.new("BindableEvent")
BuildService.ItemMoved = movedEvent.Event -- (plot, model) after it moved/rotated

-- Set by machine services: may this placed model be stored/moved/upgraded right now?
-- Return a reason string to refuse ("The oven is baking").
BuildService.Blockers = {} :: { (model: Model, action: string) -> string? }

local lastAction: { [Player]: number } = {}

local function notify(player: Player, message: string)
	Remotes.Get("Notify"):FireClient(player, message)
end

local function buildData(player: Player): any
	local data = DataManager.Get(player)
	return data and data.Build
end

local function placedFolder(plot: Model): Folder
	local folder = plot:FindFirstChild("Placed") :: Folder?
	if not folder then
		local created = Instance.new("Folder")
		created.Name = "Placed"
		created.Parent = plot
		folder = created
	end
	return folder :: Folder
end

-- How many of `id` the player has (in the inventory plus placed). Upgrade chains
-- count as one item: a Mixer counts as your "PrepTable" (Max = 1 per chain).
function BuildService.CountOwned(player: Player, id: string): number
	local b = buildData(player)
	if not b then
		return 0
	end
	local root = BuildCatalog.Root(id)
	local n = 0
	for ownedId, count in b.Owned do
		if BuildCatalog.Root(ownedId) == root then
			n += count
		end
	end
	for _, record in b.Placed do
		if BuildCatalog.Root(record.Id) == root then
			n += 1
		end
	end
	return n
end

local function sync(player: Player)
	local b = buildData(player)
	local data = DataManager.Get(player)
	if not b or not data then
		return
	end
	local unlocked = {}
	for id in data.UnlockedUpgrades do
		table.insert(unlocked, id)
	end
	local counts = {}
	for _, entry in BuildCatalog.List do
		counts[entry.Id] = BuildService.CountOwned(player, entry.Id)
	end
	Remotes.Get("BuildSync"):FireClient(player, { Owned = b.Owned, Counts = counts, Unlocked = unlocked })
	local plot = PlotManager.GetPlot(player)
	if plot then
		BuildArea.Publish(plot, player)
	end
end
BuildService.Sync = sync

local function modelFor(plot: Model, uid: string): Model?
	for _, model in placedFolder(plot):GetChildren() do
		if model:GetAttribute("Uid") == uid then
			return model :: Model
		end
	end
	return nil
end
BuildService.ModelFor = modelFor

-- Spawns (or rebuilds) the model for one placed record.
local function spawn(plot: Model, uid: string, record: any): Model
	local folder = placedFolder(plot)
	local old = modelFor(plot, uid)
	local model = BuildModels.Build(record.Id)
	local entry = BuildCatalog.Find(record.Id)
	model.Name = `{record.Id}_{uid}`
	model:SetAttribute("Uid", uid)
	model:SetAttribute("Kind", entry and entry.Kind or "Decor")
	model:SetAttribute("Visible", true)
	BuildModels.PlaceAt(model, plot, record.GX, record.GZ, record.Rot)
	model.Parent = folder
	if old then
		removedEvent:Fire(plot, old)
		old:Destroy()
	end
	placedEvent:Fire(plot, model)
	return model
end

-- Rects of every placed item on the plot except `ignoreUid`.
local function placedRects(player: Player, ignoreUid: string?): { BuildRules.Rect }
	local rects = {}
	local b = buildData(player)
	for uid, record in (if b then b.Placed else {}) do
		if uid ~= ignoreUid then
			table.insert(rects, BuildRules.Place(BuildModels.Footprint(record.Id), record.GX, record.GZ, record.Rot))
		end
	end
	return rects
end

function BuildService.CanPlace(player: Player, plot: Model, id: string, gx: number, gz: number, rot: number, ignoreUid: string?): (boolean, string?)
	local rect = BuildRules.Place(BuildModels.Footprint(id), gx, gz, rot)
	return BuildRules.Check(rect, BuildArea.Reserved(plot, player), placedRects(player, ignoreUid))
end

local function blocked(model: Model, action: string): string?
	if model:GetAttribute("Broken") then
		return "Repair it first (hold Q)."
	end
	for _, check in BuildService.Blockers do
		local reason = check(model, action)
		if reason then
			return reason
		end
	end
	return nil
end

local function requirementsMet(player: Player, entry: BuildCatalog.Entry): boolean
	for _, id in entry.Requires or {} do
		if not DataManager.HasUnlock(player, id) then
			return false
		end
	end
	return true
end

local function grantUnlocks(player: Player, plot: Model, entry: BuildCatalog.Entry, count: number)
	local ids = { entry.Id }
	if entry.Unlocks and entry.Unlocks[count] then
		table.insert(ids, entry.Unlocks[count])
	end
	for _, id in ids do
		if not DataManager.HasUnlock(player, id) then
			DataManager.Unlock(player, id)
			TycoonButtons.FireUnlocked(player, plot, id)
		end
	end
end

-- Buys one `id`. Upgrades (UpgradeOf) need `uid` of the placed item to upgrade.
function BuildService.Buy(player: Player, id: string, uid: string?): (boolean, string?)
	local entry = BuildCatalog.Find(id)
	local plot = PlotManager.GetPlot(player)
	local b = buildData(player)
	if not entry or not plot or not b then
		return false, "unknown item"
	end
	if not requirementsMet(player, entry) then
		return false, "locked"
	end
	local count = BuildService.CountOwned(player, id)
	local target: Model? = nil
	if entry.UpgradeOf then
		local record = uid and b.Placed[uid]
		if not record or record.Id ~= entry.UpgradeOf then
			return false, `Place your {entry.UpgradeOf} first, then upgrade it.`
		end
		target = modelFor(plot, uid :: string)
		local reason = target and blocked(target :: Model, "upgrade")
		if reason then
			return false, reason
		end
	elseif entry.Max and count >= entry.Max then
		return false, `You can only have {entry.Max}.`
	end
	local price = BuildCatalog.PriceFor(entry, count)
	local paid = if entry.Currency == "Gems" then DataManager.SpendGems(player, price) else DataManager.SpendCash(player, price)
	if not paid then
		return false, if entry.Currency == "Gems" then `You need 💎 {price}.` else `You need ${price}.`
	end
	if entry.UpgradeOf and uid then
		b.Placed[uid].Id = id -- same spot, better machine
		spawn(plot, uid, b.Placed[uid])
	else
		b.Owned[id] = (b.Owned[id] or 0) + 1
	end
	grantUnlocks(player, plot, entry, count + 1)
	sync(player)
	return true
end

function BuildService.Place(player: Player, id: string, gx: number, gz: number, rot: number): (boolean, string?)
	local plot = PlotManager.GetPlot(player)
	local b = buildData(player)
	if not plot or not b or (b.Owned[id] or 0) <= 0 then
		return false, "You don't have one to place."
	end
	local count = 0
	for _ in b.Placed do
		count += 1
	end
	if count >= Config.Build.MaxPlaced then
		return false, "Your bakery is full."
	end
	local ok, reason = BuildService.CanPlace(player, plot, id, gx, gz, rot)
	if not ok then
		return false, `Can't place it there: {reason}.`
	end
	b.Owned[id] -= 1
	if b.Owned[id] <= 0 then
		b.Owned[id] = nil
	end
	local uid = tostring(b.NextUid)
	b.NextUid += 1
	b.Placed[uid] = { Id = id, GX = gx, GZ = gz, Rot = rot % 4 }
	spawn(plot, uid, b.Placed[uid])
	sync(player)
	return true
end

function BuildService.Move(player: Player, uid: string, gx: number, gz: number, rot: number): (boolean, string?)
	local plot = PlotManager.GetPlot(player)
	local b = buildData(player)
	local record = b and b.Placed[uid]
	local model = plot and modelFor(plot, uid)
	if not plot or not record or not model then
		return false, "nothing to move"
	end
	local reason = blocked(model, "move")
	if reason then
		return false, reason
	end
	local ok, why = BuildService.CanPlace(player, plot, record.Id, gx, gz, rot, uid)
	if not ok then
		return false, `Can't move it there: {why}.`
	end
	record.GX, record.GZ, record.Rot = gx, gz, rot % 4
	BuildModels.PlaceAt(model, plot, gx, gz, record.Rot)
	movedEvent:Fire(plot, model)
	sync(player)
	return true
end

function BuildService.Store(player: Player, uid: string): (boolean, string?)
	local plot = PlotManager.GetPlot(player)
	local b = buildData(player)
	local record = b and b.Placed[uid]
	local model = plot and modelFor(plot, uid)
	if not plot or not record or not model then
		return false, "nothing to store"
	end
	local reason = blocked(model, "store")
	if reason then
		return false, reason
	end
	b.Placed[uid] = nil
	b.Owned[record.Id] = (b.Owned[record.Id] or 0) + 1
	removedEvent:Fire(plot, model)
	model:Destroy()
	sync(player)
	return true
end

-- Buys a fixed upgrade (Shared/PlotLayout: the building, recipes, oven upgrades,
-- automation) from the Upgrades tab. It appears in its fixed spot.
local UPGRADE_REASONS = {
	["not owner"] = "That isn't your bakery.",
	["already owned"] = "You already have that.",
	locked = "That's still locked.",
	replaced = "You already have something better.",
}
function BuildService.BuyUpgrade(player: Player, id: string): (boolean, string?)
	local plot = PlotManager.GetPlot(player)
	local upgrade = PlotLayout.Find(id)
	if not plot or not upgrade then
		return false, "unknown upgrade"
	end
	local ok, reason = TycoonButtons.TryPurchase(player, plot, id)
	if ok then
		notify(player, `✅ {upgrade.Icon} {upgrade.DisplayName} bought!`)
		return true
	elseif reason == "insufficient cash" or reason == "insufficient gems" then
		return false, if reason == "insufficient gems" then `You need 💎 {upgrade.Price}.` else `You need ${upgrade.Price}.`
	end
	return false, UPGRADE_REASONS[reason or ""] or reason
end

-- Remotes.BuildAction: ("buy", id, uid?) | ("place", id, gx, gz, rot) | ("move", uid, gx, gz, rot) | ("store", uid) | ("upgrade", id)
local function onAction(player: Player, action: any, a: any, b: any, c: any, d: any)
	local now = os.clock()
	if now - (lastAction[player] or 0) < Config.Build.ActionCooldown then
		return
	end
	lastAction[player] = now
	local ok, reason
	local function int(v: any): number?
		return if typeof(v) == "number" and v == v and math.abs(v) < 1000 then math.floor(v) else nil
	end
	if action == "buy" and typeof(a) == "string" then
		ok, reason = BuildService.Buy(player, a, if typeof(b) == "string" then b else nil)
	elseif action == "place" and typeof(a) == "string" and int(b) and int(c) and int(d) then
		ok, reason = BuildService.Place(player, a, int(b) :: number, int(c) :: number, int(d) :: number)
	elseif action == "move" and typeof(a) == "string" and int(b) and int(c) and int(d) then
		ok, reason = BuildService.Move(player, a, int(b) :: number, int(c) :: number, int(d) :: number)
	elseif action == "store" and typeof(a) == "string" then
		ok, reason = BuildService.Store(player, a)
	elseif action == "upgrade" and typeof(a) == "string" then
		ok, reason = BuildService.BuyUpgrade(player, a)
	else
		return
	end
	if not ok and reason then
		notify(player, `🔨 {reason}`)
	end
end

local function clearPlot(plot: Model)
	for _, model in placedFolder(plot):GetChildren() do
		removedEvent:Fire(plot, model)
		model:Destroy()
	end
	plot:SetAttribute("BuildReserved", nil)
end

local function onClaimed(player: Player, plot: Model)
	clearPlot(plot)
	local b = buildData(player)
	if not b then
		return
	end
	BuildService.Migrate(player, plot)
	for uid, record in b.Placed do
		if BuildCatalog.Find(record.Id) then
			spawn(plot, uid, record)
		else
			b.Placed[uid] = nil -- an item that no longer exists
		end
	end
	sync(player)
end

-- Runs `fn(plot, model)` for every placed model now and every one placed later.
function BuildService.OnPlaced(fn: (Model, Model) -> ())
	placedEvent.Event:Connect(fn)
	for _, plot in (workspace:WaitForChild("Plots") :: Folder):GetChildren() do
		local folder = plot:FindFirstChild("Placed")
		for _, model in (if folder then folder:GetChildren() else {}) do
			if model:IsA("Model") then
				fn(plot :: Model, model)
			end
		end
	end
end

-- Set by Build/BuildMigration (old saves -> placed items).
BuildService.Migrate = function(_player: Player, _plot: Model) end

function BuildService.Init()
	Remotes.Get("BuildAction").OnServerEvent:Connect(onAction)
	PlotManager.PlotClaimed:Connect(function(player, plot)
		task.defer(onClaimed, player, plot) -- after TycoonButtons has shown the fixed items
	end)
	PlotManager.PlotReleased:Connect(clearPlot)
	TycoonButtons.UpgradeUnlocked:Connect(function(player)
		sync(player) -- buttons bought = their spots free up; new catalog items unlock
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		local plot = PlotManager.GetPlot(player)
		if plot then
			task.defer(onClaimed, player, plot)
		end
	end
end

return BuildService
