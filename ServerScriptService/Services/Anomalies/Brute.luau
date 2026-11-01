--!strict
-- Brute Break-In: a huge Brute stomps in from the street on every unshielded plot
-- with a building, smashes the front door (screen shake), then walks to a working
-- machine every few seconds and breaks it (Repairs, Config.Repair.DamageFraction),
-- up to MaxBreaks. Players whack it with the Frying Pan (or click it) until its
-- HP runs out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Services = script.Parent.Parent
local Common = require(Services.AnomalyCommon)
local DataManager = require(Services.DataManager)
local NPCKit = require(Services.NPCKit)
local PlotManager = require(Services.PlotManager)
local Repairs = require(Services.Repairs)
local VFX = require(Services.VFX)

local brutes: { [Model]: Model } = {} -- npc -> plot

local function folder(): Folder
	return workspace:WaitForChild("Anomalies") :: Folder
end

local function defeat(npc: Model, player: Player)
	local cfg = Config.Anomalies.Brute
	brutes[npc] = nil
	if npc.PrimaryPart then
		VFX.Burst(npc.PrimaryPart.Position, "Poof", Color3.fromRGB(255, 90, 90))
		VFX.Burst(npc.PrimaryPart.Position, "Catch")
		Common.shake(npc.PrimaryPart.Position, 50, 0.8, 0.5)
	end
	DataManager.AddStat(player, "AnomaliesStopped", 1)
	Common.reward(player, cfg.RewardCash, cfg.RewardGems, "BrutesDefeated", "💪 You knocked out the Brute!")
	npc:Destroy()
end

local function flash(npc: Model)
	local h = Instance.new("Highlight")
	h.FillColor = Color3.fromRGB(255, 40, 40)
	h.FillTransparency = 0.3
	h.OutlineTransparency = 1
	h.Parent = npc
	task.delay(1.1, h.Destroy, h)
end

local function smash(npc: Model, at: Vector3)
	VFX.Burst(at, "Smash")
	Common.shake(at, 60, 1.2, 0.5)
	Common.playSound(at, Config.Sounds.Explosion, 1.3, 1)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Jump = true
	end
end

local function runBrute(plot: Model, deadline: number)
	local cfg = Config.Anomalies.Brute
	local owner = PlotManager.GetOwner(plot)
	local floor = Common.floor(plot)
	local npc = NPCKit.BuildBrute()
	local start = Common.streetPoint(plot)
	npc:PivotTo(CFrame.lookAt(start + Vector3.new(0, 6, 0), floor.Position + Vector3.new(0, 6, 0)))
	npc.Parent = folder()
	pcall(function()
		(npc.PrimaryPart :: BasePart):SetNetworkOwner(nil)
	end)
	brutes[npc] = plot
	NPCKit.MakeHittable(npc, {
		HP = cfg.HP,
		BarOffset = 9,
		OnHit = function()
			flash(npc)
		end,
		OnDefeat = function(player)
			defeat(npc, player)
		end,
	})
	local door = (floor * CFrame.new(0, 4, 23.5)).Position
	Common.cutscene("Brute", plot, door)

	-- It doesn't pathfind: it's anchored and stomps in straight lines, crashing
	-- through fences and walls, with a walk animation and footstep shakes.
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = npc.PrimaryPart :: BasePart
	root.Anchored = true
	local standY = floor.Position.Y + humanoid.HipHeight + root.Size.Y / 2
	npc:PivotTo(CFrame.lookAt(Vector3.new(start.X, standY, start.Z), Vector3.new(floor.Position.X, standY, floor.Position.Z)))
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local walkTrack: AnimationTrack? = nil
	if animator and Config.Animations.Walk ~= "" then
		local anim = Instance.new("Animation")
		anim.AnimationId = Config.Animations.Walk
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok then
			walkTrack = track
			track.Looped = true
		end
	end
	local function stomp(to: Vector3): boolean
		local from = npc:GetPivot().Position
		local goal = Vector3.new(to.X, standY, to.Z)
		if (goal - from).Magnitude < 0.5 then
			return npc.Parent ~= nil
		end
		if walkTrack then
			walkTrack:Play(0.2, 1, 0.7)
		end
		local steps = true
		task.spawn(function()
			while steps and npc.Parent do
				Common.shake(npc:GetPivot().Position, 35, 0.25, 0.15)
				task.wait(0.55)
			end
		end)
		local ok = NPCKit.Glide(npc, CFrame.lookAt(goal, goal + (goal - from) * Vector3.new(1, 0, 1)), humanoid.WalkSpeed)
		steps = false
		if walkTrack then
			walkTrack:Stop(0.2)
		end
		return ok
	end
	Common.introWait()

	local alive = function()
		return npc.Parent ~= nil and os.clock() < deadline
	end
	-- Break in through the front door.
	if alive() then
		stomp((floor * CFrame.new(0, 0, 28)).Position)
	end
	if alive() then
		smash(npc, door)
		if owner then
			Common.notify(owner, "💥 The Brute smashed through your front door!")
		end
	end

	local breaks = 0
	while alive() and breaks < cfg.MaxBreaks do
		local machines = Repairs.WorkingMachines(plot)
		if #machines == 0 then
			break
		end
		local target = machines[math.random(#machines)]
		local main = Repairs.MainPart(target)
		if not main then
			break
		end
		-- Stand on the street side of the machine.
		local stand = main.Position + floor:VectorToWorldSpace(Vector3.new(0, 0, 6))
		stomp(stand)
		if npc.Parent then
			npc:PivotTo(CFrame.lookAt(npc:GetPivot().Position, Vector3.new(main.Position.X, standY, main.Position.Z)))
		end
		if not alive() then
			break
		end
		flash(npc) -- wind-up: a chance to land a few more hits
		task.wait(1.2)
		if not alive() then
			break
		end
		smash(npc, main.Position)
		if Repairs.Break(plot, target.Name, Config.Repair.DamageFraction, "Smashed") then
			breaks += 1
			if owner then
				Common.notify(owner, `🔨 The Brute smashed your {Common.displayName(target.Name)}! Hold Q on it to repair.`)
			end
		end
		task.wait(math.max(1, cfg.SmashInterval - 1.2))
	end

	-- Done (or time's up): it stomps off.
	if npc.Parent then
		brutes[npc] = nil
		stomp(Common.streetPoint(plot))
		if npc.Parent then
			if npc.PrimaryPart then
				VFX.Burst(npc.PrimaryPart.Position, "Poof")
			end
			npc:Destroy()
		end
	end
end

return {
	CanRun = function()
		for _, plot in Common.ownedPlots() do
			if Common.item(plot, "Walls") and #Repairs.WorkingMachines(plot) > 0 then
				return true
			end
		end
		return false
	end,
	Run = function(_cfg: any, deadline: number)
		local hasWalls = function(plot: Model)
			return Common.item(plot, "Walls") ~= nil
		end
		local protected = Common.consumeShields(hasWalls)
		Common.givePansToAll()
		for _, plot in Common.targetPlots(protected, hasWalls) do
			task.spawn(runBrute, plot, deadline)
		end
		task.wait(1)
		Common.waitUntil(deadline, function()
			Common.givePansToAll()
			return next(brutes) == nil
		end)
	end,
	Cleanup = function()
		for npc in brutes do
			npc:Destroy()
		end
		brutes = {}
		Common.takePans()
	end,
}
