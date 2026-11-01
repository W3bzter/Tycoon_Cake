--!strict
-- Shared NPC code for customers and anomaly creatures.
--   NPCKit.WalkTo(npc, target, timeout)   pathfinding walk for Humanoid NPCs
--   NPCKit.Glide(model, cframe, speed)    straight tween for anchored creatures
--   NPCKit.Build<Brute|Rat|Gremlin|Phantom>()
--   NPCKit.MakeHittable(model, opts)      HP bar, click / touch / Frying Pan hits
--   NPCKit.PanHit(player)                 hit the nearest hittable creature in range

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local VFX = require(script.Parent.VFX)

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

-- Builders -----------------------------------------------------------------------------

local function part(model: Model, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.Anchored = true
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

local function weldTo(base: BasePart, p: BasePart)
	p.Anchored = false
	p.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = p
	weld.Parent = p
end

-- The Brute: a huge R15 bruiser with horns and glowing eyes.
function NPCKit.BuildBrute(): Model
	local desc = Instance.new("HumanoidDescription")
	local skin = Color3.fromRGB(110, 70, 80)
	desc.HeadColor = skin
	desc.TorsoColor = Color3.fromRGB(70, 50, 60)
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.LeftLegColor = Color3.fromRGB(50, 40, 45)
	desc.RightLegColor = Color3.fromRGB(50, 40, 45)
	desc.WidthScale = 1.3
	desc.DepthScale = 1.2
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	local npc: Model
	if ok and model then
		npc = model
	else -- fallback: a blocky rig
		npc = Instance.new("Model")
		local root = part(npc, { Name = "HumanoidRootPart", Size = Vector3.new(2, 2, 1), Transparency = 1 })
		root.Anchored = false
		local torso = part(npc, { Name = "UpperTorso", Size = Vector3.new(2.6, 2.4, 1.4), Color = desc.TorsoColor, CFrame = root.CFrame })
		weldTo(root, torso)
		local head = part(npc, { Name = "Head", Size = Vector3.new(1.4, 1.4, 1.4), Color = skin, CFrame = root.CFrame * CFrame.new(0, 1.9, 0) })
		weldTo(root, head)
		local humanoid = Instance.new("Humanoid")
		humanoid.RigType = Enum.HumanoidRigType.R6
		humanoid.HipHeight = 2
		humanoid.Parent = npc
		npc.PrimaryPart = root
	end
	npc.Name = "Brute"
	local head = npc:FindFirstChild("Head") :: BasePart?
	if head then
		for _, side in { -1, 1 } do
			local horn = part(npc, { Name = "Horn", Size = Vector3.new(0.3, 0.9, 0.3), Color = Color3.fromRGB(240, 230, 210), CFrame = head.CFrame * CFrame.new(side * 0.5, 0.75, 0) * CFrame.Angles(0, 0, -side * 0.5) })
			weldTo(head, horn)
			local eye = part(npc, { Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.28, Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon, CFrame = head.CFrame * CFrame.new(side * 0.25, 0.15, -0.55) })
			weldTo(head, eye)
		end
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 50, 50)
		light.Range = 10
		light.Brightness = 2
		light.Parent = head
	end
	npc:ScaleTo(2.2)
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = 10
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	for _, d in npc:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false -- walk through the shop like a ghost-train villain; doors are smashed for show
		end
	end
	return npc
end

-- A rat: anchored parts, moved with Glide. PrimaryPart "Body".
function NPCKit.BuildRat(): Model
	local model = Instance.new("Model")
	model.Name = "Rat"
	local fur = Color3.fromRGB(120, 110, 115)
	local body = part(model, { Name = "Body", Size = Vector3.new(1.4, 1, 2), Color = fur, CanTouch = true })
	local function rel(name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?, mat: Enum.Material?)
		part(model, { Name = name, Size = size, CFrame = body.CFrame * offset, Color = color, Shape = shape or Enum.PartType.Block, Material = mat or Enum.Material.SmoothPlastic, CanTouch = true })
	end
	rel("Head", Vector3.new(0.9, 0.8, 0.9), CFrame.new(0, 0.15, -1.2), fur)
	rel("Nose", Vector3.one * 0.25, CFrame.new(0, 0.15, -1.7), Color3.fromRGB(255, 150, 170), Enum.PartType.Ball)
	for _, side in { -1, 1 } do
		rel("Ear", Vector3.new(0.15, 0.5, 0.5), CFrame.new(side * 0.4, 0.65, -1.1), Color3.fromRGB(255, 170, 190), Enum.PartType.Cylinder)
		rel("Eye", Vector3.one * 0.18, CFrame.new(side * 0.25, 0.35, -1.6), Color3.fromRGB(255, 40, 40), Enum.PartType.Ball, Enum.Material.Neon)
	end
	rel("Tail", Vector3.new(0.15, 0.15, 1.8), CFrame.new(0, 0, 1.8) * CFrame.Angles(0.4, 0, 0), Color3.fromRGB(255, 170, 190))
	model.PrimaryPart = body
	return model
end

-- A gremlin: small green imp with big ears. PrimaryPart "Body".
function NPCKit.BuildGremlin(): Model
	local model = Instance.new("Model")
	model.Name = "Gremlin"
	local skin = Color3.fromRGB(90, 200, 90)
	local body = part(model, { Name = "Body", Size = Vector3.new(1.6, 1.8, 1.2), Color = skin })
	part(model, { Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, CFrame = body.CFrame * CFrame.new(0, 1.6, 0), Color = skin })
	for _, side in { -1, 1 } do
		part(model, { Name = "Ear", Size = Vector3.new(1.4, 0.2, 0.7), CFrame = body.CFrame * CFrame.new(side * 1.2, 1.9, 0) * CFrame.Angles(0, 0, side * 0.5), Color = skin })
		part(model, { Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.45, CFrame = body.CFrame * CFrame.new(side * 0.35, 1.75, -0.6), Color = Color3.fromRGB(255, 240, 60), Material = Enum.Material.Neon })
		part(model, { Name = "Leg", Size = Vector3.new(0.4, 0.9, 0.4), CFrame = body.CFrame * CFrame.new(side * 0.4, -1.3, 0), Color = Color3.fromRGB(60, 140, 60) })
	end
	part(model, { Name = "Grin", Size = Vector3.new(0.8, 0.12, 0.1), CFrame = body.CFrame * CFrame.new(0, 1.3, -0.78), Color = Color3.fromRGB(30, 30, 30) })
	part(model, { Name = "Wrench", Size = Vector3.new(0.25, 1.6, 0.25), CFrame = body.CFrame * CFrame.new(1.1, 0, -0.3) * CFrame.Angles(0, 0, -0.6), Color = Color3.fromRGB(170, 170, 180), Material = Enum.Material.Metal })
	model.PrimaryPart = body
	return model
end

-- A phantom: translucent glowing sheet ghost. PrimaryPart "Body".
function NPCKit.BuildPhantom(): Model
	local model = Instance.new("Model")
	model.Name = "Phantom"
	local body = part(model, { Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.one * 4, Color = Color3.fromRGB(220, 235, 255), Material = Enum.Material.Neon, Transparency = 0.35 })
	part(model, { Name = "Skirt", Size = Vector3.new(3.6, 3, 3.6), CFrame = body.CFrame * CFrame.new(0, -2, 0), Color = Color3.fromRGB(220, 235, 255), Material = Enum.Material.Neon, Transparency = 0.45 })
	for _, side in { -1, 1 } do
		part(model, { Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 1.1, 0.4), CFrame = body.CFrame * CFrame.new(side * 0.7, 0.4, -1.8), Color = Color3.fromRGB(10, 10, 30), Transparency = 0 })
	end
	part(model, { Name = "Mouth", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 1.2, 0.4), CFrame = body.CFrame * CFrame.new(0, -0.6, -1.85), Color = Color3.fromRGB(10, 10, 30) })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(170, 200, 255)
	light.Range = 16
	light.Brightness = 3
	light.Parent = body
	model.PrimaryPart = body
	return model
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
