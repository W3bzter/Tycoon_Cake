--!strict
-- Mimic Customer: a glowing fake customer goes for a cake (Anomaly-touched or
-- Cursed first) and steals it without paying. Click or touch it to stop it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Services = script.Parent.Parent
local BakingPipeline = require(Services.BakingPipeline)
local Common = require(Services.AnomalyCommon)
local CustomerAI = require(Services.CustomerAI)
local DataManager = require(Services.DataManager)
local PlotManager = require(Services.PlotManager)
local VFX = require(Services.VFX)

local mimic: Model? = nil

local function stopMimic(player: Player): boolean
	local npc = mimic
	if not npc or npc.Parent == nil or npc:GetAttribute("Stopped") then
		return false
	end
	npc:SetAttribute("Stopped", true)
	if npc.PrimaryPart then
		VFX.Burst(npc.PrimaryPart.Position, "Poof")
	end
	DataManager.AddStat(player, "AnomaliesStopped", 1)
	Common.reward(player, Config.Anomalies.MimicCustomer.StopReward, Config.Gems.MimicReward, "MimicsStopped", "You stopped the Mimic!")
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
	click.MouseClick:Connect(stopMimic)

	for _, d in npc:GetDescendants() do
		if d:IsA("BasePart") then
			d.Touched:Connect(function(hit)
				local character = hit:FindFirstAncestorOfClass("Model")
				local player = character and Players:GetPlayerFromCharacter(character)
				if player then
					stopMimic(player)
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
			Common.notify(owner, "The Mimic stole one of your cakes!")
		end
	end
	return false -- skip the normal purchase
end

return {
	CanRun = function()
		for _, plot in Common.ownedPlots() do
			if #BakingPipeline.GetSaleSlots(plot) > 0 then
				return true
			end
		end
		return false
	end,
	Run = function(_cfg: any, deadline: number)
		local protected = Common.consumeShields(function(plot)
			return #BakingPipeline.GetSaleSlots(plot) > 0
		end)
		mimic = CustomerAI.TrySpawnForAnyPlot({
			Decorate = decorateMimic,
			OnArrive = mimicArrives,
			IgnoreCap = true,
			PreferAnomaly = true,
			PlotFilter = function(plot)
				return not protected[plot]
			end,
		})
		local m = mimic
		if m and m.PrimaryPart then
			Common.cutsceneAll("MimicCustomer", m.PrimaryPart.Position)
		end
		Common.waitUntil(deadline, function()
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
