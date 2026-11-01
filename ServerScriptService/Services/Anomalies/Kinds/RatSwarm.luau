--!strict
-- Rat Swarm: rats pour out of a hole in the back corner of every unshielded plot
-- with a pantry. Each rat runs for the pantry (steals ingredients from the
-- owner's bag) or a display counter (nibbles a cake: x0.5 value), then runs home.
-- Stomp them (touch), click them or whack them with the Frying Pan.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Services = script:FindFirstAncestor("Services") :: Folder
local BakingPipeline = require(Services.Baking.BakingPipeline)
local Common = require(Services.Anomalies.AnomalyCommon)
local Creatures = require(Services.Anomalies.Creatures)
local DataManager = require(Services.Core.DataManager)
local Inventory = require(Services.Baking.Inventory)
local NPCKit = require(Services.Customers.NPCKit)
local PlotManager = require(Services.Core.PlotManager)
local VFX = require(Services.Effects.VFX)

local rats: { [Model]: Model } = {} -- rat -> plot
local holes: { BasePart } = {}
local squashed: { [Model]: number } = {} -- plot -> rats squashed

local function folder(): Folder
	return workspace:WaitForChild("Anomalies") :: Folder
end

-- Rats walk on the floor; `y` is the floor height.
local function groundAt(pos: Vector3, y: number): Vector3
	return Vector3.new(pos.X, y + 0.55, pos.Z)
end

local function runRat(rat: Model, plot: Model, hole: Vector3, y: number)
	local cfg = Config.Anomalies.RatSwarm
	local owner = PlotManager.GetOwner(plot)
	local speed = cfg.Speed * (0.8 + math.random() * 0.4)
	local function go(to: Vector3): boolean
		local from = rat:GetPivot().Position
		if (to - from).Magnitude < 0.1 then
			return rat.Parent ~= nil
		end
		return NPCKit.Glide(rat, CFrame.lookAt(to, to + (to - from).Unit), speed)
	end

	-- Pick a target: a cake on display (40%) or the pantry.
	local slots = {}
	for _, slot in BakingPipeline.GetSlots(plot) do
		if slot:GetAttribute("HasCake") and not slot:GetAttribute("Reserved") then
			table.insert(slots, slot)
		end
	end
	local pantry = Common.item(plot, "IngredientCrate")
	local crate = pantry and pantry:FindFirstChild("Crate") :: BasePart?
	local slot = if #slots > 0 and (math.random() < 0.4 or not crate) then slots[math.random(#slots)] else nil
	local target = if slot then slot.Position + Common.floor(plot):VectorToWorldSpace(Vector3.new(0, 0, 2.5)) elseif crate then crate.Position + Common.floor(plot):VectorToWorldSpace(Vector3.new(0, 0, crate.Size.Z / 2 + 1)) else nil
	if not target then
		return
	end
	-- Scurry over in two legs (a little zig-zag looks more rat-like).
	local mid = (hole + target) / 2 + Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
	if not go(groundAt(mid, y)) or not go(groundAt(target, y)) then
		return
	end
	task.wait(0.6)
	if rat.Parent == nil then
		return
	end
	if slot then
		local info = BakingPipeline.ModifyCake(plot, slot, function(cake)
			return Rarity.AddCakeTrait(cake, "Nibbled")
		end)
		if info and owner then
			Common.notify(owner, `🐀 A rat nibbled your {Recipes.Cakes[info.Type] and Recipes.Cakes[info.Type].DisplayName or "cake"}! (x0.5 value)`)
		end
	elseif owner then
		local taken = Inventory.StealRandom(owner, cfg.Steal)
		if #taken > 0 then
			local names = {}
			for _, item in taken do
				table.insert(names, `{Rarity.Name(item.Rarity)} {item.Type}`)
			end
			Common.notify(owner, `🐀 A rat stole {table.concat(names, " and ")} from your bag!`)
		end
	end
	-- Run home and escape.
	if go(groundAt(hole, y)) then
		rats[rat] = nil
		rat:Destroy()
	end
end

return {
	CanRun = function()
		for _, plot in Common.ownedPlots() do
			if Common.item(plot, "IngredientCrate") then
				return true
			end
		end
		return false
	end,
	Run = function(cfg: any, deadline: number)
		local hasPantry = function(plot: Model)
			return Common.item(plot, "IngredientCrate") ~= nil
		end
		local protected = Common.consumeShields(hasPantry)
		local targets = Common.targetPlots(protected, hasPantry)
		Common.givePansToAll()
		squashed = {}
		for _, plot in targets do
			local floor = Common.floor(plot)
			local holeCf = floor * CFrame.new(-34, 0.06, -20)
			local hole = Instance.new("Part")
			hole.Name = "RatHole"
			hole.Shape = Enum.PartType.Cylinder
			hole.Size = Vector3.new(0.1, 4, 4)
			hole.CFrame = holeCf * CFrame.Angles(0, 0, math.rad(90))
			hole.Color = Color3.fromRGB(15, 10, 10)
			hole.Anchored = true
			hole.CanCollide = false
			hole.Parent = folder()
			table.insert(holes, hole)
			Common.cutscene("RatSwarm", plot, holeCf.Position)
		end
		Common.introWait()
		for _, plot in targets do
			local floor = Common.floor(plot)
			local holePos = (floor * CFrame.new(-34, 0, -20)).Position
			squashed[plot] = 0
			for i = 1, cfg.Count do
				task.delay(i * 0.5, function()
					if os.clock() > deadline then
						return
					end
					local rat = Creatures.BuildRat()
					rat:PivotTo(CFrame.new(groundAt(holePos, floor.Position.Y)))
					rat.Parent = folder()
					rats[rat] = plot
					NPCKit.MakeHittable(rat, {
						HP = 1,
						Touch = true,
						OnDefeat = function(player)
							rats[rat] = nil
							if rat.PrimaryPart then
								VFX.Burst(rat.PrimaryPart.Position, "Poof", Color3.fromRGB(150, 130, 110))
							end
							DataManager.AddStat(player, "RatsSquashed", 1)
							Common.reward(player, cfg.RewardCash, 0, nil, "🐀 Squashed!")
							squashed[plot] = (squashed[plot] or 0) + 1
							local owner = PlotManager.GetOwner(plot)
							if owner and squashed[plot] >= cfg.Count then
								DataManager.AddStat(owner, "AnomaliesStopped", 1)
								Common.reward(owner, 0, cfg.ClearGems, nil, "🧹 Every rat squashed!")
							end
							rat:Destroy()
						end,
					})
					runRat(rat, plot, holePos, floor.Position.Y)
				end)
			end
		end
		task.wait(cfg.Count * 0.5 + 0.5)
		Common.waitUntil(deadline, function()
			Common.givePansToAll()
			return next(rats) == nil
		end)
	end,
	Cleanup = function()
		for rat in rats do
			rat:Destroy()
		end
		rats = {}
		for _, hole in holes do
			hole:Destroy()
		end
		holes = {}
		Common.takePans()
	end,
}
