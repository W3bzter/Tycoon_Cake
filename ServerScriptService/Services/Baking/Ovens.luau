--!strict
-- The bakery oven (one per bakery; automated ovens live in Factory/AutoProduction).
-- An oven has racks: each rack bakes one cake on its own timer. Rack count comes
-- from PlotStats.OvenRacks (Oven Rack upgrades), speed from PlotStats.BakeDuration
-- (Oven Speed upgrades, Golden Oven). Both show on the oven: a light per rack on
-- top (grey empty / orange baking / green ready), a blue vent per speed level and
-- a gold band for the Golden Oven.
--
-- State: oven/Racks/RackN (Configuration) with attributes State ("Idle" | "Baking"
-- | "Ready"), BakeRemaining + CakeData fields. The oven model mirrors the overall
-- state in OvenState ("Ready" if any rack is ready, else "Baking" if any is
-- baking, else "Idle"), plus Racks (count) and Blocked (Overheat Crisis).
-- FinishBake (bake-time rolls) is also used by automation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CakeData = require(Shared:WaitForChild("CakeData"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local Services = script:FindFirstAncestor("Services") :: Folder
local BakeUtil = require(Services.Baking.BakeUtil)
local DataManager = require(Services.Core.DataManager)
local PlotManager = require(Services.Core.PlotManager)
local PlotStats = require(Services.Core.PlotStats)
local VFX = require(Services.Effects.VFX)
local Style = require(Services.World.Style)

local notify, getPrompt, cakeName = BakeUtil.notify, BakeUtil.getPrompt, BakeUtil.cakeName

local Ovens = {}

local bakedEvent = Instance.new("BindableEvent")
Ovens.Baked = bakedEvent.Event -- (owner, CakeInfo) after every bake (manual and automated)

local SPEED_UPGRADES = { "FasterOvens1", "FasterOvens2", "FasterOvens3" }
local LIGHT_COLORS = {
	Idle = Color3.fromRGB(120, 110, 105),
	Baking = Color3.fromRGB(255, 150, 60),
	Ready = Color3.fromRGB(90, 230, 120),
}

local function plotOf(oven: Model): Model?
	local plots = workspace:FindFirstChild("Plots")
	local node: Instance? = oven
	while node and node.Parent ~= plots do
		node = node.Parent
	end
	return node :: Model?
end

local function racksOf(oven: Model): { Instance }
	local folder = oven:FindFirstChild("Racks")
	local racks = if folder then folder:GetChildren() else {}
	table.sort(racks, function(a, b)
		return (a:GetAttribute("Index") :: number) < (b:GetAttribute("Index") :: number)
	end)
	return racks
end
Ovens.Racks = racksOf

local function setDoorGlow(oven: Model, on: boolean)
	local door = oven:FindFirstChild("Door") :: BasePart?
	if door then
		door.Material = if on then Enum.Material.Neon else Enum.Material.Glass
		door.Color = if on then Color3.fromRGB(255, 150, 60) else Color3.fromRGB(60, 40, 40)
	end
end
Ovens.SetDoorGlow = setDoorGlow

-- Recomputes the oven's overall state, its prompt text, door glow and rack lights.
local function refresh(oven: Model)
	local racks = racksOf(oven)
	local ready, baking, soonest = 0, 0, math.huge
	local readyType: string? = nil
	for _, rack in racks do
		local state = rack:GetAttribute("State")
		if state == "Ready" then
			ready += 1
			readyType = readyType or (rack:GetAttribute("CakeType") :: string?)
		elseif state == "Baking" then
			baking += 1
			soonest = math.min(soonest, (rack:GetAttribute("BakeRemaining") :: number?) or 0)
		end
		local light = oven:FindFirstChild(`RackLight{rack:GetAttribute("Index")}`, true) :: BasePart?
		if light then
			light.Color = LIGHT_COLORS[state :: string] or LIGHT_COLORS.Idle
		end
	end
	local overall = if ready > 0 then "Ready" elseif baking > 0 then "Baking" else "Idle"
	oven:SetAttribute("OvenState", overall)
	local blocked = oven:GetAttribute("Blocked") == true
	setDoorGlow(oven, baking > 0 and not blocked)

	local prompt = getPrompt(oven)
	if not prompt then
		return
	end
	local name = if BakeUtil.idOf(oven) == "BasicOven" then "Basic Oven" else "Oven"
	local free = #racks - ready - baking
	if ready > 0 then
		prompt.ActionText = "Collect Cake"
		prompt.ObjectText = `{cakeName(readyType)} ready!` .. (if ready > 1 then ` (+{ready - 1} more)` else "")
	elseif free > 0 then
		prompt.ActionText = "Bake Batter"
		prompt.ObjectText = if #racks > 1 then `{name} ({free}/{#racks} racks free)` else name
	else
		prompt.ActionText = "Baking..."
		prompt.ObjectText = `{name} ({math.ceil(soonest)}s)`
	end
	if blocked then
		prompt.ObjectText = `{name} (OVERHEATED)`
	end
end
Ovens.Refresh = refresh

-- Rack lights, speed vents and the golden band on top of / beside the oven body.
local function decorate(oven: Model, owner: Player?)
	local old = oven:FindFirstChild("OvenDeco")
	if old then
		old:Destroy()
	end
	local body = oven:FindFirstChild("Body") :: BasePart?
	if not body then
		return
	end
	local deco = Instance.new("Model")
	deco.Name = "OvenDeco"
	local P = Style.Palette
	local top = body.Size.Y / 2
	local n = #racksOf(oven)
	for i = 1, n do
		local light = Style.Ball(`RackLight{i}`, 0.7, body.CFrame * CFrame.new((i - (n + 1) / 2) * 1.2, top + 0.45, 0), LIGHT_COLORS.Idle, deco)
		light.Material = Enum.Material.Neon
	end
	local level = 0
	for _, id in SPEED_UPGRADES do
		if owner and DataManager.HasUnlock(owner, id) then
			level += 1
		end
	end
	for i = 1, level do
		local vent = Style.Part({
			Name = "SpeedVent",
			Size = Vector3.new(0.2, 0.5, body.Size.Z * 0.6),
			CFrame = body.CFrame * CFrame.new(body.Size.X / 2 + 0.15, top - 0.6 - (i - 1) * 0.8, 0),
			Color = P.Sky,
			Parent = deco,
		})
		vent.Material = Enum.Material.Neon
	end
	if owner and DataManager.HasUnlock(owner, "GoldenOven") then
		local band = Style.Part({ Name = "GoldBand", Size = Vector3.new(body.Size.X + 0.3, 0.4, body.Size.Z + 0.3), CFrame = body.CFrame * CFrame.new(0, top - 0.25, 0), Color = P.Gold, Parent = deco })
		band.Material = Enum.Material.Neon
	end
	for _, d in deco:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	deco.Parent = oven
end

-- Makes the oven's rack count match its owner's upgrades and redraws the extras.
-- Racks are only removed from the end (a rebirth); their cakes are lost.
function Ovens.Setup(oven: Model, plot: Model?)
	if oven:GetAttribute("IsAutoOven") then
		return
	end
	local owner = PlotManager.GetOwner(plot or plotOf(oven) :: Model)
	local want = if BakeUtil.idOf(oven) == "BasicOven" then 1 else math.max(1, PlotStats.Get(owner).OvenRacks)
	local folder = oven:FindFirstChild("Racks")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Racks"
		folder.Parent = oven
	end
	local racks = racksOf(oven)
	for i = #racks + 1, want do
		local rack = Instance.new("Configuration")
		rack.Name = `Rack{i}`
		rack:SetAttribute("Index", i)
		rack:SetAttribute("State", "Idle")
		rack.Parent = folder
	end
	for i = want + 1, #racks do
		racks[i]:Destroy()
	end
	oven:SetAttribute("Racks", want)
	decorate(oven, owner)
	refresh(oven)
end

-- Re-applies upgrades to every manual oven on the plot (after a purchase).
function Ovens.SetupPlot(plot: Model)
	for _, item in BakeUtil.machines(plot) do
		if item:GetAttribute("IsOven") and not item:GetAttribute("IsAutoOven") then
			Ovens.Setup(item, plot)
		end
	end
end

-- Bake finished (manual or automated): rolls cake traits and a mutation
-- (Shared/Rarity.RollBake), records stats and celebrates mutations.
function Ovens.FinishBake(owner: Player?, oven: Model, info: Rarity.CakeInfo, overheated: boolean?): Rarity.CakeInfo
	local data = owner and DataManager.Get(owner)
	local out = Rarity.RollBake(info, {
		AnomalyActive = ReplicatedStorage:GetAttribute("ActiveAnomaly") ~= nil,
		Overheated = overheated,
		Rebirths = data and data.Rebirths or 0,
		EventMult = (ReplicatedStorage:GetAttribute("MutationEventMult") :: number?) or 1, -- Baking/MutationEvents
	})
	if owner then
		bakedEvent:Fire(owner, out)
		if out.Mutation then
			local m = Rarity.Mutations[out.Mutation]
			local body = oven:FindFirstChild("Body") :: BasePart?
			if body then
				VFX.Burst(body.Position, "Mutation", m.Color)
			end
			notify(owner, `{m.Icon} MUTATION! {out.Mutation} {cakeName(out.Type)} (x{m.Mult} value)`)
		end
	end
	return out
end

local function runBake(oven: Model, rack: Instance, plot: Model)
	local duration = PlotStats.BakeDuration(PlotManager.GetOwner(plot), oven)
	if rack:GetAttribute("Fresh") then
		duration *= Rarity.FreshBakeMult -- Fresh ingredients bake faster
	end
	rack:SetAttribute("BakeRemaining", duration)
	rack:SetAttribute("State", "Baking")
	refresh(oven)
	local overheated = false
	while (rack:GetAttribute("BakeRemaining") :: number) > 0 do
		local dt = task.wait(0.25)
		if rack.Parent == nil or oven.Parent == nil or rack:GetAttribute("State") ~= "Baking" then
			return -- plot was reset, the oven exploded or was rebuilt
		end
		if oven:GetAttribute("Blocked") or oven:GetAttribute("Broken") then -- Overheat Crisis / broken pauses baking
			overheated = overheated or oven:GetAttribute("Blocked") == true
		else
			rack:SetAttribute("BakeRemaining", math.max(0, (rack:GetAttribute("BakeRemaining") :: number) - dt))
		end
		refresh(oven)
	end
	local info = Ovens.FinishBake(PlotManager.GetOwner(plot), oven, CakeData.Read(rack), overheated)
	CakeData.Write(rack, info)
	rack:SetAttribute("State", "Ready")
	refresh(oven)
end

-- The first rack in `state` ("Idle" = free, "Ready" = a cake to collect).
function Ovens.RackIn(oven: Model, state: string): Instance?
	for _, rack in racksOf(oven) do
		if rack:GetAttribute("State") == state then
			return rack
		end
	end
	return nil
end

-- Puts a batter in a free rack and starts its timer (in its own thread).
function Ovens.Load(oven: Model, rack: Instance, info: Rarity.CakeInfo, plot: Model)
	CakeData.Write(rack, info)
	task.spawn(runBake, oven, rack, plot)
end

-- Takes the finished cake out of a ready rack.
function Ovens.Collect(oven: Model, rack: Instance): Rarity.CakeInfo
	local info = CakeData.Read(rack)
	CakeData.Clear(rack)
	rack:SetAttribute("State", "Idle")
	rack:SetAttribute("BakeRemaining", nil)
	refresh(oven)
	return info
end

-- Overheat visuals + the Blocked flag runBake and the oven handler respect.
function Ovens.SetOvenBlocked(oven: Model, blocked: boolean)
	oven:SetAttribute("Blocked", blocked)
	local body = oven:FindFirstChild("Body") :: BasePart?
	if body then
		-- The body is a rounded box: the core part plus child pieces. Recolour them all.
		local shell: { BasePart } = { body }
		for _, d in body:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(shell, d)
			end
		end
		for _, p in shell do
			if p:GetAttribute("NormalColor") == nil then
				p:SetAttribute("NormalColor", p.Color)
			end
			p.Color = if blocked then Color3.fromRGB(230, 40, 30) else p:GetAttribute("NormalColor") :: Color3
		end
		local smoke = body:FindFirstChild("OverheatSmoke")
		if blocked then
			if not smoke then
				local s = Instance.new("Smoke")
				s.Name = "OverheatSmoke"
				s.Color = Color3.fromRGB(60, 60, 60)
				s.Size = 4
				s.RiseVelocity = 6
				s.Opacity = 0.6
				s.Parent = body
			end
		elseif smoke then
			smoke:Destroy()
		end
	end
	if oven:GetAttribute("IsAutoOven") then
		-- Automated ovens manage their own prompts (AutoProduction).
		setDoorGlow(oven, not blocked and oven:GetAttribute("OvenState") == "Baking")
	else
		refresh(oven)
	end
end

-- Every unlocked oven on the plot, manual or automated (anything tagged IsOven).
function Ovens.GetOvens(plot: Model): { Model }
	local ovens = {}
	for _, item in BakeUtil.machines(plot) do
		if item:GetAttribute("IsOven") and item:GetAttribute("Visible") and not item:GetAttribute("Broken") then
			table.insert(ovens, item)
		end
	end
	return ovens
end

-- Empties a manual oven (an explosion, a smash or a plot reset loses whatever was baking).
function Ovens.ResetOven(oven: Model)
	if oven:GetAttribute("IsAutoOven") then
		return
	end
	for _, rack in racksOf(oven) do
		CakeData.Clear(rack)
		rack:SetAttribute("State", "Idle")
		rack:SetAttribute("BakeRemaining", nil)
	end
	refresh(oven)
end

return Ovens
