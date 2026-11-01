--!strict
-- Shared NPC code for customers and anomaly creatures.
--   NPCKit.WalkTo(npc, target, timeout)   pathfinding walk for Humanoid NPCs
--   NPCKit.Glide(model, cframe, speed)    straight tween for anchored creatures
--   (creature models are built in Anomalies/Creatures)
--   NPCKit.MakeHittable(model, opts)      HP bar, click / touch / Frying Pan hits
--   NPCKit.PanHit(player)                 hit the nearest hittable creature in range

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local VFX = require(Services.Effects.VFX)

local NPCKit = {}

-- Movement ------------------------------------------------------------------------------

local function moveTo(humanoid: Humanoid, position: Vector3): boolean
	-- Polls instead of MoveToFinished:Wait(), which never returns if the NPC is
	-- destroyed mid-walk and would leak the coroutine.
	local done, reached = false, false
	local conn = humanoid.MoveToFinished:Once(function(result)
		done, reached = true, result
	end)
	humanoid:MoveTo(position)
	local started = os.clock()
	while not done and humanoid:IsDescendantOf(workspace) and os.clock() - started < 8 do
		task.wait(0.1)
	end
	conn:Disconnect()
	return reached
end

-- Walks along a computed path; recomputes when blocked and teleports as a last resort.
function NPCKit.WalkTo(npc: Model, target: Vector3, timeout: number?): boolean
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = npc.PrimaryPart :: BasePart
	local deadline = os.clock() + (timeout or 60)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
	})

	for _attempt = 1, 3 do
		if npc.Parent == nil or humanoid.Health <= 0 then
			return false
		end
		local ok = pcall(function()
			path:ComputeAsync(root.Position, target)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local blocked = false
			for _, waypoint in path:GetWaypoints() do
				if npc.Parent == nil or os.clock() > deadline then
					return false
				end
				if waypoint.Action == Enum.PathWaypointAction.Jump then
					humanoid.Jump = true
				end
				if not moveTo(humanoid, waypoint.Position) then
					blocked = true
					break
				end
			end
			if not blocked then
				return true
			end
		elseif moveTo(humanoid, target) then
			return true -- no path, but a straight walk worked
		end
	end

	-- Stuck: snap to the goal so the game keeps moving.
	if npc.Parent then
		npc:PivotTo(CFrame.new(target + Vector3.new(0, 3, 0)))
		return true
	end
	return false
end

-- Moves an anchored model to `cf` at `speed` studs/s (yields). False if destroyed.
function NPCKit.Glide(model: Model, cf: CFrame, speed: number): boolean
	if model.Parent == nil then
		return false
	end
	local value = Instance.new("CFrameValue")
	value.Value = model:GetPivot()
	local conn = value.Changed:Connect(function(v)
		if model.Parent then
			model:PivotTo(v)
		end
	end)
	local duration = math.max(0.05, (cf.Position - value.Value.Position).Magnitude / speed)
	local tween = TweenService:Create(value, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Value = cf })
	tween:Play()
	local started = os.clock()
	while os.clock() - started < duration and model.Parent do
		task.wait(0.05)
	end
	tween:Cancel()
	conn:Disconnect()
	value:Destroy()
	return model.Parent ~= nil
end

-- Hitting -------------------------------------------------------------------------------

export type HitOptions = {
	HP: number,
	Touch: boolean?, -- touching it counts as a hit (stomping rats)
	CanHit: (() -> boolean)?, -- e.g. only while the creature is visible
	OnHit: ((player: Player, hpLeft: number) -> ())?,
	OnDefeat: (player: Player) -> (),
	BarOffset: number?,
}

type Target = { model: Model, opts: HitOptions, hp: number, lastHit: { [Player]: number } }
local targets: { [Model]: Target } = {}

local function updateBar(t: Target)
	local root = t.model.PrimaryPart
	local gui = root and root:FindFirstChild("HPBar") :: BillboardGui?
	local fill = gui and gui:FindFirstChild("Fill", true) :: Frame?
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(t.hp / t.opts.HP, 0, 1), 1)
	end
end

local function hit(t: Target, player: Player)
	if t.hp <= 0 or t.model.Parent == nil or (t.opts.CanHit and not t.opts.CanHit()) then
		return
	end
	local now = os.clock()
	if now - (t.lastHit[player] or 0) < 0.3 then
		return
	end
	t.lastHit[player] = now
	t.hp -= Config.Gems.PanDamage
	updateBar(t)
	local root = t.model.PrimaryPart
	if root then
		VFX.Burst(root.Position, "Catch")
	end
	if t.hp <= 0 then
		targets[t.model] = nil
		t.opts.OnDefeat(player)
	elseif t.opts.OnHit then
		t.opts.OnHit(player, t.hp)
	end
end

function NPCKit.MakeHittable(model: Model, opts: HitOptions)
	local t: Target = { model = model, opts = opts, hp = opts.HP, lastHit = {} }
	targets[model] = t
	model.Destroying:Connect(function()
		targets[model] = nil
	end)
	local root = model.PrimaryPart :: BasePart
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 40
	click.Parent = root
	click.MouseClick:Connect(function(player)
		hit(t, player)
	end)
	if opts.Touch then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Touched:Connect(function(other)
					local character = other:FindFirstAncestorOfClass("Model")
					local player = character and Players:GetPlayerFromCharacter(character)
					if player then
						hit(t, player)
					end
				end)
			end
		end
	end
	if opts.HP > 1 then
		local gui = Instance.new("BillboardGui")
		gui.Name = "HPBar"
		gui.Size = UDim2.fromScale(5, 0.6)
		gui.StudsOffsetWorldSpace = Vector3.new(0, opts.BarOffset or 4, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 80
		local back = Instance.new("Frame")
		back.Size = UDim2.fromScale(1, 1)
		back.BackgroundColor3 = Color3.fromRGB(40, 10, 10)
		back.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = back
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
		fill.Parent = back
		corner:Clone().Parent = fill
		gui.Parent = root
	end
end

-- Frying Pan: hits the nearest hittable creature within range of the player.
function NPCKit.PanHit(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local best: Target?, bestDist = nil, Config.Gems.PanRange
	for model, t in targets do
		local p = model.PrimaryPart
		if p and model.Parent then
			local _, size = model:GetBoundingBox()
			local dist = (p.Position - root.Position).Magnitude - size.Magnitude * 0.3
			if dist <= bestDist then
				best, bestDist = t, dist
			end
		end
	end
	if best then
		hit(best, player)
		return true
	end
	return false
end

function NPCKit.HP(model: Model): number?
	local t = targets[model]
	return t and t.hp
end

return NPCKit
