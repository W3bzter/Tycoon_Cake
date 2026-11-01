--!strict
-- Gremlin Sabotage: a gremlin teleports between the automation machines of every
-- unshielded plot with a production line. Each time it lands it sits still for a
-- moment (catchable), then sabotages: switches a line off, scrambles a line's
-- recipe, or jams a conveyor. Catch it Catches times (click, touch or pan).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Services = script.Parent.Parent
local AutoProduction = require(Services.AutoProduction)
local Common = require(Services.AnomalyCommon)
local DataManager = require(Services.DataManager)
local NPCKit = require(Services.NPCKit)
local PlotManager = require(Services.PlotManager)
local Repairs = require(Services.Repairs)
local VFX = require(Services.VFX)

local AUTO_IDS = { "IngredientConveyor", "AutoMixer", "AutoOven", "CounterConveyor", "ProductionLine2", "ProductionLine3" }
local LINE_ITEM = { "IngredientConveyor", "ProductionLine2", "ProductionLine3" }

local gremlins: { [Model]: Model } = {} -- gremlin -> plot

local function folder(): Folder
	return workspace:WaitForChild("Anomalies") :: Folder
end

local function machines(plot: Model): { Model }
	local list = {}
	for _, id in AUTO_IDS do
		local item = Common.item(plot, id)
		if item then
			table.insert(list, item)
		end
	end
	return list
end

local function activeLines(plot: Model): { number }
	local list = {}
	for i, id in LINE_ITEM do
		if Common.item(plot, id) then
			table.insert(list, i)
		end
	end
	return list
end

local function setVisible(model: Model, visible: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("BaseTransparency") == nil then
				d:SetAttribute("BaseTransparency", d.Transparency)
			end
			d.Transparency = if visible then d:GetAttribute("BaseTransparency") :: number else 1
		end
	end
	model:SetAttribute("Catchable", visible)
end

local function sabotage(plot: Model, at: Model)
	local owner = PlotManager.GetOwner(plot)
	local data = owner and DataManager.Get(owner)
	if not owner or not data then
		return
	end
	local lines = activeLines(plot)
	local roll = math.random(3)
	if roll == 1 and #lines > 0 then
		local i = lines[math.random(#lines)]
		if data.LinesEnabled[i] ~= false then
			AutoProduction.SetEnabled(owner, plot, i, false)
			Common.notify(owner, `👺 The Gremlin switched Line {i} OFF! Hold T on it to turn it back on.`)
			return
		end
	end
	if roll <= 2 and #lines > 0 then
		local i = lines[math.random(#lines)]
		local line = AutoProduction.GetLine(plot, i)
		local menu = Recipes.Unlocked(function(id)
			return DataManager.HasUnlock(owner, id)
		end)
		if line and #menu > 1 then
			local pick = menu[math.random(#menu)]
			line.recipe = pick
			data.LineRecipes[i] = pick
			Common.notify(owner, `👺 The Gremlin changed Line {i}'s recipe to {Recipes.Cakes[pick].DisplayName}!`)
			return
		end
	end
	-- Jam: the machine it sits on (or a conveyor) stops delivering for a while.
	local target = Common.item(plot, "CounterConveyor") or at
	target:SetAttribute("JammedUntil", os.clock() + Config.Anomalies.Gremlin.JamSeconds)
	Common.notify(owner, `👺 The Gremlin jammed your {Common.displayName(target.Name)} for {Config.Anomalies.Gremlin.JamSeconds}s!`)
end

local function runGremlin(plot: Model, deadline: number)
	local cfg = Config.Anomalies.Gremlin
	local owner = PlotManager.GetOwner(plot)
	local gremlin = NPCKit.BuildGremlin()
	local list = machines(plot)
	if #list == 0 then
		return
	end
	local function spotOn(item: Model): CFrame
		local main = Repairs.MainPart(item) or (item.PrimaryPart :: BasePart)
		local top = main.Position + Vector3.new(0, main.Size.Y / 2 + 1.6, 0)
		return CFrame.lookAt(top, top + Common.floor(plot).LookVector * -1)
	end
	local current = list[1]
	gremlin:PivotTo(spotOn(current))
	gremlin.Parent = folder()
	gremlins[gremlin] = plot
	local jumpNow = false
	NPCKit.MakeHittable(gremlin, {
		HP = cfg.Catches,
		BarOffset = 4,
		CanHit = function()
			return gremlin:GetAttribute("Catchable") == true
		end,
		OnHit = function(player, hp)
			Common.notify(player, `👺 Caught the Gremlin! ({cfg.Catches - hp}/{cfg.Catches}) It blinked away!`)
			jumpNow = true
		end,
		OnDefeat = function(player)
			gremlins[gremlin] = nil
			if gremlin.PrimaryPart then
				VFX.Burst(gremlin.PrimaryPart.Position, "Poof", Color3.fromRGB(120, 255, 120))
			end
			DataManager.AddStat(player, "AnomaliesStopped", 1)
			Common.reward(player, 0, cfg.RewardGems, "GremlinsCaught", "👺 You caught the Gremlin for good!")
			gremlin:Destroy()
		end,
	})
	setVisible(gremlin, true)
	Common.cutscene("Gremlin", plot, gremlin:GetPivot().Position)
	Common.introWait()

	while gremlin.Parent and os.clock() < deadline do
		-- Sit still (catchable) for a moment, then sabotage and blink away.
		setVisible(gremlin, true)
		local t0 = os.clock()
		while gremlin.Parent and not jumpNow and os.clock() - t0 < cfg.VisibleTime do
			task.wait(0.1)
		end
		if not gremlin.Parent or os.clock() >= deadline then
			break
		end
		if not jumpNow then
			sabotage(plot, current)
		end
		jumpNow = false
		VFX.Burst(gremlin:GetPivot().Position, "Poof", Color3.fromRGB(120, 255, 120))
		setVisible(gremlin, false)
		task.wait(math.max(0.5, cfg.ActionInterval - cfg.VisibleTime))
		list = machines(plot)
		if #list == 0 or not gremlin.Parent then
			break
		end
		current = list[math.random(#list)]
		gremlin:PivotTo(spotOn(current))
		VFX.Burst(gremlin:GetPivot().Position, "Poof", Color3.fromRGB(120, 255, 120))
		if owner then
			Common.playSound(gremlin:GetPivot().Position, Config.Sounds.Denied, 1.8, 0.8)
		end
	end
	if gremlin.Parent then
		gremlins[gremlin] = nil
		gremlin:Destroy()
	end
end

return {
	CanRun = function()
		for _, plot in Common.ownedPlots() do
			if #activeLines(plot) > 0 then
				return true
			end
		end
		return false
	end,
	Run = function(_cfg: any, deadline: number)
		local hasLine = function(plot: Model)
			return #activeLines(plot) > 0
		end
		local protected = Common.consumeShields(hasLine)
		Common.givePansToAll()
		for _, plot in Common.targetPlots(protected, hasLine) do
			task.spawn(runGremlin, plot, deadline)
		end
		task.wait(1)
		Common.waitUntil(deadline, function()
			Common.givePansToAll()
			return next(gremlins) == nil
		end)
	end,
	Cleanup = function()
		for g in gremlins do
			g:Destroy()
		end
		gremlins = {}
		Common.takePans()
	end,
}
