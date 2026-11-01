--!strict
-- Roll reveal: one card per rolled ingredient. Each card flickers through rarity
-- colours, then lands on its result (staggered). The show gets louder with the
-- best tier's Fx (Shared/Rarity):
--   glow       pulsing card glow (Rare)
--   shake      card shake (Epic)
--   rays       golden rays + tint flash + small camera shake (Legendary)
--   mythic     screen dims, spinning rays, giant gradient title, confetti, shake,
--              and that card's reveal is slowed down for suspense
--   divine     white-gold flash + double rays on top of mythic
--   anomalous  glitch: RGB-split title, flickering inverted tint, heavy shake
--   void / celestial  a full-screen blackout / white-out cutscene first
--              (UI/Effects/RarityCutscene), then the divine show
-- Purely visual: the server already put the items in the bag. Auto-deleted items
-- (item.Deleted) are shown greyed with a bin.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Recipes = require(Shared:WaitForChild("Recipes"))
local RarityCutscene = require(script.Parent:WaitForChild("RarityCutscene"))
local ScreenShake = require(script.Parent:WaitForChild("ScreenShake"))

local RollReveal = {}

local container: Frame
local overlay: Frame
local raysFrame: Frame
local bigTitle: TextLabel
local ghostTitles: { TextLabel } = {}
local confettiLayer: Frame
local token = 0
local fxConn: RBXScriptConnection? = nil

local FX_LEVEL = { none = 0, glow = 1, shake = 2, rays = 3, mythic = 4, divine = 5, anomalous = 6, void = 7, celestial = 8 }

local function playSound(id: string?, speed: number?, volume: number?)
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = speed or 1
	s.Volume = volume or 0.7
	SoundService:PlayLocalSound(s)
	task.delay(4, s.Destroy, s)
end

local function card(parent: Instance, item: any, order: number): (Frame, TextLabel, TextLabel, UIStroke)
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.fromOffset(92, 112)
	frame.BackgroundColor3 = Color3.fromRGB(30, 22, 30)
	frame.BackgroundTransparency = 0.1
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = frame

	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(1, 0, 0, 46)
	icon.Position = UDim2.fromOffset(0, 6)
	icon.BackgroundTransparency = 1
	icon.TextScaled = true
	icon.Text = Recipes.Ingredients[item.Type] and Recipes.Ingredients[item.Type].Icon or "❓"
	icon.Parent = frame

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -8, 0, 20)
	name.Position = UDim2.fromOffset(4, 54)
	name.BackgroundTransparency = 1
	name.TextScaled = true
	name.Font = Enum.Font.FredokaOne
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Text = item.Type
	name.Parent = frame

	local rarity = Instance.new("TextLabel")
	rarity.Size = UDim2.new(1, -8, 0, 30)
	rarity.Position = UDim2.fromOffset(4, 76)
	rarity.BackgroundTransparency = 1
	rarity.TextScaled = true
	rarity.Font = Enum.Font.FredokaOne
	rarity.Text = "?"
	rarity.Parent = frame
	return frame, rarity, name, stroke
end

function RollReveal.Mount(screen: ScreenGui)
	overlay = Instance.new("Frame")
	overlay.Name = "RollOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 18
	overlay.Active = false
	overlay.Parent = screen

	raysFrame = Instance.new("Frame")
	raysFrame.Name = "Rays"
	raysFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	raysFrame.Position = UDim2.fromScale(0.5, 0.42)
	raysFrame.Size = UDim2.fromOffset(10, 10)
	raysFrame.BackgroundTransparency = 1
	raysFrame.Visible = false
	raysFrame.ZIndex = 19
	raysFrame.Parent = screen
	for i = 1, 16 do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromOffset(1400, if i % 2 == 0 then 26 else 46)
		ray.Rotation = i * (180 / 16)
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = Color3.new(1, 1, 1)
		ray.ZIndex = 19
		local grad = Instance.new("UIGradient")
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 0.55),
			NumberSequenceKeypoint.new(0.5, 0.15),
			NumberSequenceKeypoint.new(0.58, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		grad.Parent = ray
		ray.Parent = raysFrame
	end

	container = Instance.new("Frame")
	container.Name = "RollReveal"
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.42)
	container.Size = UDim2.fromOffset(720, 264) -- two rows when a 2x Roll reveals 14 cards
	container.BackgroundTransparency = 1
	container.Visible = false
	container.ZIndex = 20
	container.Parent = screen
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Wraps = true
	layout.Parent = container

	local function titleLabel(name: string, z: number): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = name
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, 0.24)
		t.Size = UDim2.new(0.9, 0, 0, 90)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Visible = false
		t.ZIndex = z
		t.Parent = screen
		return t
	end
	ghostTitles = { titleLabel("GlitchRed", 21), titleLabel("GlitchCyan", 21) }
	ghostTitles[1].TextColor3 = Color3.fromRGB(255, 40, 80)
	ghostTitles[2].TextColor3 = Color3.fromRGB(40, 255, 230)
	bigTitle = titleLabel("BigRollTitle", 22)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(30, 10, 30)
	stroke.Parent = bigTitle
	local grad = Instance.new("UIGradient")
	grad.Name = "Shine"
	grad.Parent = bigTitle

	confettiLayer = Instance.new("Frame")
	confettiLayer.Name = "Confetti"
	confettiLayer.Size = UDim2.fromScale(1, 1)
	confettiLayer.BackgroundTransparency = 1
	confettiLayer.ZIndex = 23
	confettiLayer.ClipsDescendants = true
	confettiLayer.Parent = screen
end

local function confetti(colors: { Color3 }, count: number)
	for _ = 1, count do
		local bit = Instance.new("Frame")
		bit.Size = UDim2.fromOffset(math.random(6, 12), math.random(10, 18))
		bit.Position = UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.3, 0.4)
		bit.AnchorPoint = Vector2.new(0.5, 0.5)
		bit.BackgroundColor3 = colors[math.random(#colors)]
		bit.BorderSizePixel = 0
		bit.Rotation = math.random(0, 360)
		bit.ZIndex = 23
		bit.Parent = confettiLayer
		local dur = 1.6 + math.random() * 1.4
		TweenService:Create(bit, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(math.random(), 1.1),
			Rotation = bit.Rotation + math.random(-540, 540),
		}):Play()
		task.delay(dur, bit.Destroy, bit)
	end
end

local function stopFx()
	if fxConn then
		fxConn:Disconnect()
		fxConn = nil
	end
	raysFrame.Visible = false
	bigTitle.Visible = false
	for _, g in ghostTitles do
		g.Visible = false
	end
	TweenService:Create(overlay, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
end

-- The big moment for Legendary and up.
local function bigMoment(tier: any, level: number, itemType: string, onDone: () -> ())
	local color = tier.Color
	raysFrame.Visible = true
	for _, ray in raysFrame:GetChildren() do
		if ray:IsA("Frame") then
			ray.BackgroundColor3 = color
		end
	end
	raysFrame.Size = UDim2.fromOffset(0, 0)
	TweenService:Create(raysFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(10, 10) }):Play()
	if level == FX_LEVEL.rays then
		overlay.BackgroundColor3 = color
		overlay.BackgroundTransparency = 0.6
		TweenService:Create(overlay, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
		ScreenShake.Shake(0.4, 0.4)
		playSound(Config.Sounds.BigRoll, 1.1, 0.6)
		local t0 = os.clock()
		fxConn = RunService.RenderStepped:Connect(function(dt)
			raysFrame.Rotation += dt * 40
			if os.clock() - t0 > 1.6 then
				stopFx()
				onDone()
			end
		end)
		return
	end

	-- Mythic and above: the full show.
	overlay.BackgroundColor3 = if level == FX_LEVEL.divine then Color3.new(1, 1, 0.9) else Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = if level == FX_LEVEL.divine then 0 else 0.35
	if level == FX_LEVEL.divine then
		TweenService:Create(overlay, TweenInfo.new(0.9), { BackgroundTransparency = 0.45, BackgroundColor3 = Color3.fromRGB(60, 45, 10) }):Play()
	end
	bigTitle.Text = `{string.upper(tier.Name)}!`
	bigTitle.Visible = true
	bigTitle.Size = UDim2.new(0.2, 0, 0, 30)
	TweenService:Create(bigTitle, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Size = UDim2.new(0.9, 0, 0, 100) }):Play()
	local shine = bigTitle:FindFirstChild("Shine") :: UIGradient
	shine.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, color),
	})
	local info = Recipes.Ingredients[itemType]
	confetti({ color, Color3.new(1, 1, 1), Color3.fromRGB(255, 220, 90) }, if level >= FX_LEVEL.divine then 90 else 60)
	ScreenShake.Shake(if level == FX_LEVEL.anomalous then 1.6 else 0.9, 1.2)
	playSound(Config.Sounds.BigRoll, if level == FX_LEVEL.anomalous then 0.6 else 0.85, 1)
	task.delay(0.25, playSound, Config.Sounds.BigRoll, 1.3, 0.8)
	if info then
		bigTitle.Text ..= `  {info.Icon}`
	end

	local glitch = level == FX_LEVEL.anomalous
	for _, g in ghostTitles do
		g.Text = bigTitle.Text
		g.Visible = glitch
	end
	local t0 = os.clock()
	fxConn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		raysFrame.Rotation += dt * (if level >= FX_LEVEL.divine then 70 else 45)
		shine.Offset = Vector2.new(math.sin(t * 3) * 0.6, 0)
		bigTitle.Rotation = math.sin(t * 5) * 3
		if glitch then
			for i, g in ghostTitles do
				g.Size = bigTitle.Size
				g.Rotation = bigTitle.Rotation
				g.Position = UDim2.new(0.5, (if i == 1 then -1 else 1) * math.random(2, 10), 0.24, math.random(-6, 6))
			end
			overlay.BackgroundColor3 = if math.random() < 0.2 then Color3.fromRGB(40, 255, 200) else Color3.new(0, 0, 0)
			overlay.BackgroundTransparency = 0.25 + math.random() * 0.3
			bigTitle.Visible = math.random() > 0.08
		end
		if t > 3.4 then
			stopFx()
			onDone()
		end
	end)
end

function RollReveal.Show(items: { any })
	token += 1
	local mine = token
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	stopFx()
	container.Visible = true

	-- The best kept item decides how big the show is.
	local best, bestIndex = 0, 0
	for i, item in items do
		if not item.Deleted and item.Rarity > best then
			best, bestIndex = item.Rarity, i
		end
	end
	local bestTier = Rarity.Tiers[math.max(best, 1)]
	local level = FX_LEVEL[bestTier.Fx] or 0

	for i, item in items do
		local frame, rarityLabel, _, stroke = card(container, item, i)
		frame.Size = UDim2.fromOffset(0, 112)
		TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(92, 112) }):Play()
		task.spawn(function()
			-- Flicker through random rarities, then land (later cards land later;
			-- the Mythic+ card keeps everyone waiting a little longer).
			local suspense = i == bestIndex and level >= FX_LEVEL.mythic
			local flickers = 6 + i * 2 + (if suspense then 14 else 0)
			for f = 1, flickers do
				if mine ~= token then
					return
				end
				local tier = Rarity.Tiers[math.random(#Rarity.Tiers)]
				stroke.Color = tier.Color
				rarityLabel.TextColor3 = tier.Color
				rarityLabel.Text = tier.Name
				task.wait(0.04 + f * (if suspense then 0.009 else 0.006))
			end
			local tier = Rarity.Tiers[item.Rarity]
			stroke.Color = tier.Color
			stroke.Thickness = 3 + tier.Glow * 1.5
			rarityLabel.TextColor3 = tier.Color
			local badges = ""
			for _, trait in item.Traits do
				badges ..= (Rarity.Traits[trait] and Rarity.Traits[trait].Icon or "")
			end
			rarityLabel.Text = tier.Name .. (if badges ~= "" then " " .. badges else "")
			frame.BackgroundColor3 = tier.Color:Lerp(Color3.fromRGB(30, 22, 30), 0.75)
			if item.Deleted then -- auto-deleted by the player's settings: never reached the bag
				rarityLabel.Text = "🗑️ " .. rarityLabel.Text
				frame.BackgroundTransparency = 0.6
				stroke.Transparency = 0.6
				return
			end
			local cardLevel = FX_LEVEL[tier.Fx] or 0
			if cardLevel >= FX_LEVEL.glow then
				TweenService:Create(stroke, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = stroke.Thickness + 3 }):Play()
			end
			if cardLevel >= FX_LEVEL.shake then
				task.spawn(function()
					for _ = 1, 10 do
						frame.Rotation = (math.random() - 0.5) * 12
						task.wait(0.03)
					end
					frame.Rotation = 0
				end)
			end
			if tier.Glow >= 2 then
				TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 2, true), { Size = UDim2.fromOffset(104, 124) }):Play()
			end
			if i == bestIndex and level >= FX_LEVEL.rays and mine == token then
				local function finish()
					if mine == token then
						container.Visible = false
					end
				end
				if level >= FX_LEVEL.void then
					-- Void / Celestial: full-screen blackout / white-out first, then the big show.
					local ingredient = Recipes.Ingredients[item.Type]
					RarityCutscene.Play(tier.Fx, tier.Name, tier.Color, ingredient and ingredient.Icon, function()
						if mine == token then
							bigMoment(tier, FX_LEVEL.divine, item.Type, finish)
						end
					end)
				else
					bigMoment(tier, level, item.Type, finish)
				end
			end
		end)
	end

	-- Legendary+ hide when their big moment ends (see bigMoment); this is a fallback.
	local hold = if level >= FX_LEVEL.void then 20 elseif level >= FX_LEVEL.mythic then 12 elseif level >= FX_LEVEL.rays then 6 else 3.2
	task.delay(hold, function()
		if mine == token then
			container.Visible = false
		end
	end)
	return best
end

return RollReveal
