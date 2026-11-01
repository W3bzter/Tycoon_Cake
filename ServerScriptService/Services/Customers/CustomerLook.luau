--!strict
-- How customers look and react: avatar rigs (with fallbacks), idle/walk/cheer
-- animations, speech bubbles, floating text, sounds, the happy burst and the
-- VIP highlight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local AvatarService = require(Services.Customers.AvatarService)

local CustomerLook = {}

-- NPC construction ---------------------------------------------------------------

local function buildBlockNpc(): Model
	-- Last-resort rig if avatar creation fails: welded blocks + Humanoid.
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Parent = model

	local function limb(name: string, size: Vector3, offset: Vector3, color: Color3)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.CFrame = root.CFrame * CFrame.new(offset)
		p.CanCollide = false
		p.Massless = true
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
	end
	limb("Torso", Vector3.new(2, 2, 1), Vector3.zero, Color3.fromRGB(90, 140, 220))
	limb("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0), Color3.fromRGB(255, 220, 180))
	limb("Legs", Vector3.new(2, 2, 1), Vector3.new(0, -2, 0), Color3.fromRGB(60, 60, 80))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.HipHeight = 2
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

local function buildNpc(visitor: AvatarService.Visitor): Model
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(visitor.Description, Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		return model
	end
	ok, model = pcall(function() -- the friend's outfit failed to load: plain styled look
		return Players:CreateHumanoidModelFromDescription(AvatarService.StyledDefault(), Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		return model
	end
	return buildBlockNpc()
end

-- Animations -----------------------------------------------------------------------

export type Tracks = { idle: AnimationTrack?, walk: AnimationTrack?, cheer: AnimationTrack?, sit: AnimationTrack? }

local function loadTrack(animator: Animator, id: string, priority: Enum.AnimationPriority): AnimationTrack?
	if id == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Priority = priority
		return track
	end
	return nil
end

-- Server-side tracks on a server-owned NPC replicate to every client.
local function setupAnimations(npc: Model): Tracks
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return {}
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local a = animator :: Animator
	local tracks: Tracks = {
		idle = loadTrack(a, Config.Animations.Idle, Enum.AnimationPriority.Idle),
		walk = loadTrack(a, Config.Animations.Walk, Enum.AnimationPriority.Movement),
		cheer = loadTrack(a, Config.Animations.Cheer, Enum.AnimationPriority.Action),
		sit = loadTrack(a, Config.Animations.Sit or "", Enum.AnimationPriority.Action),
	}
	if tracks.sit then
		tracks.sit.Looped = true
	end
	if tracks.idle then
		tracks.idle.Looped = true
		tracks.idle:Play()
	end
	if tracks.walk then
		tracks.walk.Looped = true
	end
	humanoid.Running:Connect(function(speed)
		local walk = tracks.walk
		if not walk then
			return
		end
		if speed > 0.5 then
			if not walk.IsPlaying then
				walk:Play(0.2)
			end
			walk:AdjustSpeed(speed / 16)
		elseif walk.IsPlaying then
			walk:Stop(0.2)
		end
	end)
	return tracks
end

-- Bubbles & effects ----------------------------------------------------------------------

local function headOf(npc: Model): BasePart?
	return npc:FindFirstChild("Head") :: BasePart?
end

local function setBubble(npc: Model, text: string?)
	local head = headOf(npc)
	if not head then
		return
	end
	local existing = head:FindFirstChild("WantBubble")
	if existing then
		existing:Destroy()
	end
	if not text then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "WantBubble"
	gui.Size = UDim2.fromScale(5, 1.6)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 105, 160)
	stroke.Thickness = 2
	stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.92, 0.85)
	label.Position = UDim2.fromScale(0.04, 0.075)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(140, 90, 70)
	label.Text = text
	label.Parent = frame
	gui.Parent = head
end

local function popText(npc: Model, text: string, color: Color3)
	local head = headOf(npc)
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(5, 1.6)
	gui.StudsOffset = Vector3.new(0, 5, 0) -- above the want/thanks bubble (offset 3.2)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 60
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	gui.Parent = head
	task.delay(2.5, gui.Destroy, gui)
end

local function playSound(parent: Instance, soundId: string)
	if soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Parent = parent
	sound:Play()
	task.delay(3, sound.Destroy, sound)
end

local function happyBurst(npc: Model)
	local head = headOf(npc)
	if not head then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds" -- built-in texture
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 120, 170), Color3.fromRGB(255, 220, 90))
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new(0.6, 0)
	emitter.Lifetime = NumberRange.new(0.8, 1.2)
	emitter.Speed = NumberRange.new(6, 10)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Rate = 0
	emitter.Parent = head
	emitter:Emit(25)
	task.delay(2, emitter.Destroy, emitter)
end

local function celebrate(npc: Model, tracks: Tracks)
	happyBurst(npc)
	if tracks.cheer then
		tracks.cheer:Play()
	else
		local humanoid = npc:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Jump = true
		end
	end
end

local function makeVIP(npc: Model)
	npc:SetAttribute("IsVIP", true)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 205, 60)
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = Color3.fromRGB(255, 230, 120)
	highlight.Parent = npc
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = "👑 " .. humanoid.DisplayName
	end
end

CustomerLook.BuildNpc = buildNpc
CustomerLook.SetupAnimations = setupAnimations
CustomerLook.SetBubble = setBubble
CustomerLook.PopText = popText
CustomerLook.PlaySound = playSound
CustomerLook.Celebrate = celebrate
CustomerLook.MakeVIP = makeVIP

return CustomerLook
