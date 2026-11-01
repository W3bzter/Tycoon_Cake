--!strict
-- Hand ovens: state machine (Idle/Baking/Ready), bake timer, bake-time rolls
-- (FinishBake, also used by automation), Overheat visuals (Blocked).
-- State lives in attributes: OvenState, BakeRemaining, Blocked + CakeData fields.

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

local notify, getPrompt, cakeName = BakeUtil.notify, BakeUtil.getPrompt, BakeUtil.cakeName

local Ovens = {}

local bakedEvent = Instance.new("BindableEvent")
Ovens.Baked = bakedEvent.Event -- (owner, CakeInfo) after every bake (manual and automated)

local function setDoorGlow(oven: Model, on: boolean)
	local door = oven:FindFirstChild("Door") :: BasePart?
	if door then
		door.Material = if on then Enum.Material.Neon else Enum.Material.Glass
		door.Color = if on then Color3.fromRGB(255, 150, 60) else Color3.fromRGB(60, 40, 40)
	end
end

local function setOvenState(oven: Model, state: string)
	oven:SetAttribute("OvenState", state)
	setDoorGlow(oven, state == "Baking" and not oven:GetAttribute("Blocked"))
	local prompt = getPrompt(oven)
	if not prompt then
		return
	end
	if state == "Idle" then
		prompt.ActionText = "Bake Batter"
		prompt.ObjectText = "Oven"
	elseif state == "Baking" then
		prompt.ActionText = "Baking..."
	elseif state == "Ready" then
		prompt.ActionText = "Collect Cake"
		prompt.ObjectText = `{cakeName(oven:GetAttribute("CakeType") :: string?)} ready!`
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

local function runBake(oven: Model, plot: Model)
	local duration = PlotStats.BakeDuration(PlotManager.GetOwner(plot), oven)
	if oven:GetAttribute("Fresh") then
		duration *= Rarity.FreshBakeMult -- Fresh ingredients bake faster
	end
	oven:SetAttribute("BakeRemaining", duration)
	setOvenState(oven, "Baking")
	local prompt = getPrompt(oven)
	local overheated = false
	while (oven:GetAttribute("BakeRemaining") :: number) > 0 do
		local dt = task.wait(0.25)
		if oven.Parent == nil or oven:GetAttribute("OvenState") ~= "Baking" then
			return -- plot was reset (or the oven exploded)
		end
		if not oven:GetAttribute("Blocked") and not oven:GetAttribute("Broken") then -- Overheat Crisis pauses baking
			local remaining = math.max(0, (oven:GetAttribute("BakeRemaining") :: number) - dt)
			oven:SetAttribute("BakeRemaining", remaining)
			if prompt then
				prompt.ObjectText = `Oven ({math.ceil(remaining)}s)`
			end
		else
			overheated = overheated or oven:GetAttribute("Blocked") == true
			if prompt then
				prompt.ObjectText = "Oven (OVERHEATED)"
			end
		end
	end
	local info = Ovens.FinishBake(PlotManager.GetOwner(plot), oven, CakeData.Read(oven), overheated)
	CakeData.Write(oven, info)
	setOvenState(oven, "Ready")
end

-- Overheat visuals + the Blocked flag runBake/ovenHandler respect.
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
		setDoorGlow(oven, not blocked and oven:GetAttribute("OvenState") == "Baking")

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

	-- Automated ovens manage their own prompts (AutoProduction).
	local prompt = if oven:GetAttribute("IsAutoOven") then nil else getPrompt(oven)
	if prompt then
		if blocked then
			prompt.ObjectText = "Oven (OVERHEATED)"
		else
			setOvenState(oven, oven:GetAttribute("OvenState") :: string)
		end
	end
end

-- Every unlocked oven on the plot, manual or automated (anything tagged IsOven).
function Ovens.GetOvens(plot: Model): { Model }
	local ovens = {}
	local items = plot:FindFirstChild("Items")
	for _, item in (if items then items:GetChildren() else {}) do
		if item:IsA("Model") and item:GetAttribute("IsOven") and item:GetAttribute("Visible") and not item:GetAttribute("Broken") then
			table.insert(ovens, item)
		end
	end
	return ovens
end

Ovens.SetDoorGlow = setDoorGlow

-- Empties a manual oven (an explosion or a smash loses whatever was baking).
function Ovens.ResetOven(oven: Model)
	if oven:GetAttribute("IsAutoOven") then
		return
	end
	CakeData.Clear(oven)
	setOvenState(oven, "Idle")
end

Ovens.SetState = setOvenState

-- Starts the bake timer for an oven that was just filled (yields in its own thread).
function Ovens.StartBake(oven: Model, plot: Model)
	task.spawn(runBake, oven, plot)
end

return Ovens
