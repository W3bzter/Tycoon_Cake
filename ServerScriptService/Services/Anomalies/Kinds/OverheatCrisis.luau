--!strict
-- Overheat Crisis: every oven on unshielded plots overheats (Blocked) and players
-- put them out with the Fire Extinguisher. In the last Config.Repair.OverheatWarning
-- seconds the ovens flash and beep; any oven still overheating when time runs out
-- EXPLODES and stays broken until repaired for Config.Repair.ExplodeFraction of
-- its price (Repairs).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local BakingPipeline = require(Services.Baking.BakingPipeline)
local Common = require(Services.Anomalies.AnomalyCommon)
local DataManager = require(Services.Core.DataManager)
local PlotManager = require(Services.Core.PlotManager)
local Repairs = require(Services.World.Repairs)
local ToolFactory = require(Services.Core.ToolFactory)
local VFX = require(Services.Effects.VFX)

local active = false

local function blockedOvens(): { Model }
	local result = {}
	for _, plot in Common.ownedPlots() do
		for _, oven in BakingPipeline.GetOvens(plot) do
			if oven:GetAttribute("Blocked") then
				table.insert(result, oven)
			end
		end
	end
	return result
end

local function useExtinguisher(player: Player): boolean
	if not active or ToolFactory.Count(player, "FireExtinguisher") == 0 then
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
	local body = best:FindFirstChild("Body") :: BasePart?
	if body then
		VFX.Burst(body.Position, "Smoke", Color3.fromRGB(230, 240, 255))
	end
	DataManager.AddGems(player, Config.Gems.ExtinguishReward)
	DataManager.AddStat(player, "OvensSaved", 1)
	Common.notify(player, `🧯 Oven saved! +💎{Config.Gems.ExtinguishReward}`)
	return true
end

local function giveExtinguisher(player: Player)
	if ToolFactory.Count(player, "FireExtinguisher") > 0 then
		return
	end
	local tool = ToolFactory.Give(player, "FireExtinguisher")
	if tool then
		tool.Activated:Connect(function()
			useExtinguisher(player)
		end)
	end
end

-- The shell parts of an oven body (the rounded box is the core part + children).
local function shellParts(oven: Model): { BasePart }
	local body = oven:FindFirstChild("Body") :: BasePart?
	if not body then
		return {}
	end
	local parts: { BasePart } = { body }
	for _, d in body:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

local function explode(oven: Model)
	local plot = oven:FindFirstAncestorOfClass("Model")
	while plot and plot.Parent ~= workspace:FindFirstChild("Plots") do
		plot = plot:FindFirstAncestorOfClass("Model")
	end
	local body = oven:FindFirstChild("Body") :: BasePart?
	if not plot or not body then
		return
	end
	local pos = body.Position
	local boom = Instance.new("Explosion")
	boom.Position = pos
	boom.BlastPressure = 0 -- purely visual: nobody gets flung or killed
	boom.BlastRadius = 0
	boom.DestroyJointRadiusPercent = 0
	boom.ExplosionType = Enum.ExplosionType.NoCraters
	boom.Parent = workspace
	VFX.Burst(pos, "Explosion")
	VFX.Burst(pos + Vector3.new(0, 2, 0), "Smoke")
	Common.shake(pos, 80, 1.5, 0.9)
	Common.playSound(pos, Config.Sounds.Explosion, 0.6, 2)
	-- Flying scraps.
	for _ = 1, 8 do
		local scrap = Instance.new("Part")
		scrap.Size = Vector3.new(math.random(4, 10) / 10, math.random(2, 6) / 10, math.random(4, 10) / 10)
		scrap.Color = if math.random() < 0.5 then Color3.fromRGB(60, 55, 55) else body.Color
		scrap.Material = Enum.Material.Metal
		scrap.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0))
		scrap.CanQuery = false
		scrap.Parent = workspace
		scrap.AssemblyLinearVelocity = Vector3.new(math.random(-30, 30), math.random(25, 45), math.random(-30, 30))
		scrap.AssemblyAngularVelocity = Vector3.new(math.random(-10, 10), math.random(-10, 10), math.random(-10, 10))
		Debris:AddItem(scrap, 4)
	end
	BakingPipeline.SetOvenBlocked(oven, false)
	local owner = PlotManager.GetOwner(plot)
	if Repairs.Break(plot, oven.Name, Config.Repair.ExplodeFraction, "Exploded") and owner then
		DataManager.AddStat(owner, "Explosions", 1)
		Common.notify(owner, `💥 Your oven EXPLODED! Hold Q on it to repair (${oven:GetAttribute("RepairCost")}).`)
	end
end

return {
	CanRun = function()
		for _, plot in Common.ownedPlots() do
			if #BakingPipeline.GetOvens(plot) > 0 then
				return true
			end
		end
		return false
	end,
	Run = function(_cfg: any, deadline: number)
		active = true
		local protected = Common.consumeShields(function(plot)
			return #BakingPipeline.GetOvens(plot) > 0
		end)
		for _, plot in Common.targetPlots(protected) do
			local ovens = BakingPipeline.GetOvens(plot)
			for _, oven in ovens do
				BakingPipeline.SetOvenBlocked(oven, true)
			end
			local first = ovens[1] and ovens[1]:FindFirstChild("Body") :: BasePart?
			if first then
				Common.cutscene("OverheatCrisis", plot, first.Position)
			end
		end
		-- Re-check every tick so respawned/new players also get an extinguisher.
		local flash, lastBeep = false, 0
		Common.waitUntil(deadline, function()
			for _, player in Players:GetPlayers() do
				giveExtinguisher(player)
			end
			local blocked = blockedOvens()
			local left = deadline - os.clock()
			if left < Config.Repair.OverheatWarning then
				flash = not flash
				for _, oven in blocked do
					for _, p in shellParts(oven) do
						p.Color = if flash then Color3.fromRGB(255, 240, 200) else Color3.fromRGB(230, 40, 30)
					end
				end
				if os.clock() - lastBeep > math.max(0.25, left / 10) then
					lastBeep = os.clock()
					for _, oven in blocked do
						local body = oven:FindFirstChild("Body") :: BasePart?
						if body then
							Common.playSound(body.Position, Config.Sounds.Denied, 1.6, 0.6)
						end
					end
				end
			end
			return #blocked == 0
		end)
		-- Time's up: whatever is still overheating blows.
		for _, oven in blockedOvens() do
			explode(oven)
		end
	end,
	Cleanup = function()
		active = false
		for _, oven in blockedOvens() do
			BakingPipeline.SetOvenBlocked(oven, false)
		end
		for _, player in Players:GetPlayers() do
			ToolFactory.Take(player, "FireExtinguisher", ToolFactory.Count(player, "FireExtinguisher"))
		end
	end,
}
