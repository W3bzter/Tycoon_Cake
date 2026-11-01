--!strict
-- Phantom Haunting: the lights flicker and a Phantom drifts through every
-- unshielded plot with a display counter. While it haunts a plot no customers
-- come (plot attribute Haunted, read by CustomerAI). Every few seconds it
-- materialises (catchable) and spooks a displayed cake (x0.7 value). Click / pan
-- it Banishes times while it's visible to banish it.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local Services = script.Parent.Parent
local BakingPipeline = require(Services.BakingPipeline)
local Common = require(Services.AnomalyCommon)
local DataManager = require(Services.DataManager)
local NPCKit = require(Services.NPCKit)
local PlotManager = require(Services.PlotManager)
local VFX = require(Services.VFX)

local phantoms: { [Model]: Model } = {} -- phantom -> plot
local haunted: { Model } = {}
local savedExposure: number? = nil
local flickering = false

local function folder(): Folder
	return workspace:WaitForChild("Anomalies") :: Folder
end

local function setVisible(model: Model, visible: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("BaseTransparency") == nil then
				d:SetAttribute("BaseTransparency", d.Transparency)
			end
			local base = d:GetAttribute("BaseTransparency") :: number
			d.Transparency = if visible then base else math.max(base, 0.93)
		elseif d:IsA("PointLight") then
			d.Enabled = visible
		end
	end
	model:SetAttribute("Catchable", visible)
end

local function spook(plot: Model)
	local slots = {}
	for _, slot in BakingPipeline.GetSlots(plot) do
		if slot:GetAttribute("HasCake") and not slot:GetAttribute("Reserved") and not string.find((slot:GetAttribute("CakeTraits") :: string?) or "", "Spooked") then
			table.insert(slots, slot)
		end
	end
	if #slots == 0 then
		return
	end
	local info = BakingPipeline.ModifyCake(plot, slots[math.random(#slots)], function(cake)
		return Rarity.AddCakeTrait(cake, "Spooked")
	end)
	local owner = PlotManager.GetOwner(plot)
	if info and owner then
		Common.notify(owner, "👻 The Phantom spooked one of your cakes! (x0.7 value)")
	end
end

local function randomSpot(plot: Model): CFrame
	local floor = Common.floor(plot)
	return floor * CFrame.new(math.random(-28, 28), 7, math.random(-22, 18))
end

local function runPhantom(plot: Model, deadline: number)
	local cfg = Config.Anomalies.Phantom
	local phantom = NPCKit.BuildPhantom()
	phantom:PivotTo(randomSpot(plot))
	phantom.Parent = folder()
	phantoms[phantom] = plot
	local vanishNow = false
	NPCKit.MakeHittable(phantom, {
		HP = cfg.Banishes,
		BarOffset = 4.5,
		CanHit = function()
			return phantom:GetAttribute("Catchable") == true
		end,
		OnHit = function(player, hp)
			Common.notify(player, `👻 Hit! ({cfg.Banishes - hp}/{cfg.Banishes}) The Phantom fled!`)
			vanishNow = true
		end,
		OnDefeat = function(player)
			phantoms[phantom] = nil
			plot:SetAttribute("Haunted", nil)
			if phantom.PrimaryPart then
				VFX.Burst(phantom.PrimaryPart.Position, "Poof", Color3.fromRGB(200, 220, 255))
			end
			DataManager.AddStat(player, "AnomaliesStopped", 1)
			Common.reward(player, 0, cfg.RewardGems, "PhantomsBanished", "👻 You banished the Phantom!")
			phantom:Destroy()
		end,
	})
	setVisible(phantom, true)
	Common.cutscene("Phantom", plot, phantom:GetPivot().Position)
	Common.introWait()

	while phantom.Parent and os.clock() < deadline do
		-- Drift around unseen, then materialise.
		setVisible(phantom, false)
		local driftUntil = os.clock() + math.max(1, cfg.AppearEvery - cfg.VisibleTime)
		while phantom.Parent and os.clock() < driftUntil do
			NPCKit.Glide(phantom, randomSpot(plot), 10)
		end
		if not phantom.Parent or os.clock() >= deadline then
			break
		end
		setVisible(phantom, true)
		VFX.Burst(phantom:GetPivot().Position, "Poof", Color3.fromRGB(200, 220, 255))
		spook(plot)
		local t0 = os.clock()
		vanishNow = false
		while phantom.Parent and not vanishNow and os.clock() - t0 < cfg.VisibleTime do
			task.wait(0.1)
		end
	end
	if phantom.Parent then
		phantoms[phantom] = nil
		phantom:Destroy()
	end
	plot:SetAttribute("Haunted", nil)
end

return {
	CanRun = function()
		for _, plot in Common.ownedPlots() do
			if Common.item(plot, "DisplayCounter") then
				return true
			end
		end
		return false
	end,
	Run = function(_cfg: any, deadline: number)
		local hasCounter = function(plot: Model)
			return Common.item(plot, "DisplayCounter") ~= nil
		end
		local protected = Common.consumeShields(hasCounter)
		local targets = Common.targetPlots(protected, hasCounter)
		Common.givePansToAll()
		-- Flickering lights (global).
		savedExposure = Lighting.ExposureCompensation
		flickering = true
		task.spawn(function()
			while flickering do
				local base = savedExposure or 0
				Lighting.ExposureCompensation = base - (if math.random() < 0.25 then 2.2 else 0.6 + math.random() * 0.6)
				task.wait(0.08 + math.random() * 0.5)
			end
		end)
		for _, plot in targets do
			plot:SetAttribute("Haunted", true)
			table.insert(haunted, plot)
			task.spawn(runPhantom, plot, deadline)
		end
		task.wait(1)
		Common.waitUntil(deadline, function()
			Common.givePansToAll()
			return next(phantoms) == nil
		end)
	end,
	Cleanup = function()
		flickering = false
		if savedExposure then
			Lighting.ExposureCompensation = savedExposure
			savedExposure = nil
		end
		for p in phantoms do
			p:Destroy()
		end
		phantoms = {}
		for _, plot in haunted do
			plot:SetAttribute("Haunted", nil)
		end
		haunted = {}
		Common.takePans()
	end,
}
