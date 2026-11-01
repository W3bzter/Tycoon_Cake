--!strict
-- Every Config.AnomalyInterval seconds, picks one anomaly (weighted, only ones that
-- can currently run) and broadcasts start/end over RemoteEvents. One at a time.
--
-- ReplicatedStorage attributes ActiveAnomaly / AnomalyEndsAt mirror the current
-- anomaly so clients that join mid-anomaly can still show the alert.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local BakingPipeline = require(script.Parent.BakingPipeline)
local CustomerAI = require(script.Parent.CustomerAI)
local DataManager = require(script.Parent.DataManager)
local PlotManager = require(script.Parent.PlotManager)
local Remotes = require(script.Parent.Remotes)
local ToolFactory = require(script.Parent.ToolFactory)

type AnomalyDef = {
	CanRun: () -> boolean,
	Run: (cfg: any, deadline: number) -> (), -- yields until the anomaly is over
	Cleanup: () -> (), -- always called afterwards, even if Run errored
}

local AnomalyManager = {}
local defs: { [string]: AnomalyDef } = {}
local running: string? = nil

local function ownedPlots(): { Model }
	local plots = {}
	for _, plot in (workspace:WaitForChild("Plots") :: Folder):GetChildren() do
		if plot:IsA("Model") and PlotManager.GetOwner(plot) then
			table.insert(plots, plot)
		end
	end
	return plots
end

local function waitUntil(deadline: number, done: () -> boolean)
	while os.clock() < deadline and not done() do
		task.wait(0.25)
	end
end

-- Gravity Distortion ----------------------------------------------------------------

local savedGravity: number? = nil

defs.GravityDistortion = {
	CanRun = function()
		return true
	end,
	Run = function(cfg, deadline)
		savedGravity = workspace.Gravity
		workspace.Gravity = (savedGravity :: number) * cfg.GravityScale
		waitUntil(deadline, function()
			return false
		end)
	end,
	Cleanup = function()
		if savedGravity then
			workspace.Gravity = savedGravity
			savedGravity = nil
		end
	end,
}

-- Overheat Crisis ---------------------------------------------------------------------

local function blockedOvens(): { Model }
	local result = {}
	for _, plot in ownedPlots() do
		for _, oven in BakingPipeline.GetOvens(plot) do
			if oven:GetAttribute("Blocked") then
				table.insert(result, oven)
			end
		end
	end
	return result
end

-- Server-side extinguish: the nearest overheated oven within range of the player.
function AnomalyManager.UseExtinguisher(player: Player): boolean
	if running ~= "OverheatCrisis" or ToolFactory.Count(player, "FireExtinguisher") == 0 then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local range = Config.Anomalies.OverheatCrisis.ExtinguisherRange
	local best: Model?, bestDist = nil, math.huge
	for _, oven in blockedOvens() do
		local body = oven:FindFirstChild("Body") :: BasePart?
		local dist = body and (body.Position - root.Position).Magnitude or math.huge
		if dist <= range and dist < bestDist then
			best, bestDist = oven, dist
		end
	end
	if not best then
		return false
	end
	BakingPipeline.SetOvenBlocked(best, false)
	return true
end

local function giveExtinguisher(player: Player)
	if ToolFactory.Count(player, "FireExtinguisher") > 0 then
		return
	end
	local tool = ToolFactory.Give(player, "FireExtinguisher")
	if tool then
		tool.Activated:Connect(function()
			AnomalyManager.UseExtinguisher(player)
		end)
	end
end

defs.OverheatCrisis = {
	CanRun = function()
		for _, plot in ownedPlots() do
			if #BakingPipeline.GetOvens(plot) > 0 then
				return true
			end
		end
		return false
	end,
	Run = function(_cfg, deadline)
		for _, plot in ownedPlots() do
			for _, oven in BakingPipeline.GetOvens(plot) do
				BakingPipeline.SetOvenBlocked(oven, true)
			end
		end
		-- Re-check every tick so respawned/new players also get an extinguisher.
		waitUntil(deadline, function()
			for _, player in Players:GetPlayers() do
				giveExtinguisher(player)
			end
			return #blockedOvens() == 0
		end)
	end,
	Cleanup = function()
		for _, oven in blockedOvens() do
			BakingPipeline.SetOvenBlocked(oven, false)
		end
		for _, player in Players:GetPlayers() do
			ToolFactory.Take(player, "FireExtinguisher", ToolFactory.Count(player, "FireExtinguisher"))
		end
	end,
}

-- Mimic Customer --------------------------------------------------------------------------

local mimic: Model? = nil

function AnomalyManager.StopMimic(player: Player): boolean
	local npc = mimic
	if not npc or npc.Parent == nil or npc:GetAttribute("Stopped") then
		return false
	end
	npc:SetAttribute("Stopped", true)
	DataManager.AddCash(player, Config.Anomalies.MimicCustomer.StopReward)
	Remotes.Get("Notify"):FireClient(player, `You stopped the Mimic! +${Config.Anomalies.MimicCustomer.StopReward}`)
	npc:Destroy() -- CustomerAI sees the NPC gone and releases the reserved slot
	return true
end

local function decorateMimic(npc: Model)
	npc.Name = "Mimic"
	npc:SetAttribute("IsMimic", true)
	for _, d in npc:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.Material = Enum.Material.Neon
			d.Color = Color3.fromRGB(170, 80, 255)
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(170, 80, 255)
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.5
	highlight.Parent = npc

	local root = npc.PrimaryPart :: BasePart
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 40
	click.Parent = root
	click.MouseClick:Connect(AnomalyManager.StopMimic)

	for _, d in npc:GetDescendants() do
		if d:IsA("BasePart") then
			d.Touched:Connect(function(hit)
				local character = hit:FindFirstAncestorOfClass("Model")
				local player = character and Players:GetPlayerFromCharacter(character)
				if player then
					AnomalyManager.StopMimic(player)
				end
			end)
		end
	end
end

local function mimicArrives(npc: Model, plot: Model, slot: BasePart): boolean
	if npc:GetAttribute("Stopped") then
		return false
	end
	if BakingPipeline.TakeCake(plot, slot) then -- steals: no payment
		CustomerAI.PopText(npc, "STOLEN!", Color3.fromRGB(255, 80, 80))
		local owner = PlotManager.GetOwner(plot)
		if owner then
			Remotes.Get("Notify"):FireClient(owner, "The Mimic stole one of your cakes!")
		end
	end
	return false -- skip the normal purchase
end

defs.MimicCustomer = {
	CanRun = function()
		for _, plot in ownedPlots() do
			if #BakingPipeline.GetSaleSlots(plot) > 0 then
				return true
			end
		end
		return false
	end,
	Run = function(_cfg, deadline)
		mimic = CustomerAI.TrySpawnForAnyPlot({
			Decorate = decorateMimic,
			OnArrive = mimicArrives,
			IgnoreCap = true,
		})
		waitUntil(deadline, function()
			return mimic == nil or (mimic :: Model).Parent == nil
		end)
	end,
	Cleanup = function()
		if mimic and mimic.Parent then
			mimic:Destroy()
		end
		mimic = nil
	end,
}

-- Manager ------------------------------------------------------------------------------------

function AnomalyManager.GetActive(): string?
	return running
end

-- Starts an anomaly now (used by the timer and by tests). Returns false if it can't.
function AnomalyManager.Trigger(name: string): (boolean, string?)
	local def = defs[name]
	local cfg = Config.Anomalies[name]
	if not def or not cfg then
		return false, "unknown anomaly"
	end
	if running then
		return false, `{running} already active`
	end
	if not def.CanRun() then
		return false, "conditions not met"
	end

	running = name
	local deadline = os.clock() + cfg.Duration
	ReplicatedStorage:SetAttribute("ActiveAnomaly", name)
	ReplicatedStorage:SetAttribute("AnomalyEndsAt", workspace:GetServerTimeNow() + cfg.Duration)
	Remotes.Get("AnomalyStarted"):FireAllClients(name, cfg.Duration)
	print(`[AnomalyManager] {name} started`)

	task.spawn(function()
		local ok, err = pcall(def.Run, cfg, deadline)
		if not ok then
			warn(`[AnomalyManager] {name} errored: {err}`)
		end
		pcall(def.Cleanup)
		running = nil
		ReplicatedStorage:SetAttribute("ActiveAnomaly", nil)
		ReplicatedStorage:SetAttribute("AnomalyEndsAt", nil)
		Remotes.Get("AnomalyEnded"):FireAllClients(name)
		print(`[AnomalyManager] {name} ended`)
	end)
	return true
end

local function pickAnomaly(): string?
	local options, total = {}, 0
	for name, def in defs do
		if def.CanRun() then
			local weight = Config.Anomalies[name].Weight
			total += weight
			table.insert(options, { name = name, weight = weight })
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = math.random() * total
	for _, option in options do
		roll -= option.weight
		if roll <= 0 then
			return option.name
		end
	end
	return options[#options].name
end

function AnomalyManager.Init()
	task.spawn(function()
		while true do
			task.wait(Config.AnomalyInterval)
			local name = pickAnomaly()
			if name then
				AnomalyManager.Trigger(name)
			end
		end
	end)

	game:BindToClose(function()
		local name = running
		if name then
			pcall(defs[name].Cleanup)
		end
	end)
end

return AnomalyManager
