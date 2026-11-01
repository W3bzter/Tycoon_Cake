--!strict
-- Mixing minigame (client). A sweet-spot zone drifts around a bowl; keep your
-- dot (it follows the mouse, or your finger while dragging on touch screens)
-- inside it. The share of time inside is sent to the server, which grades it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local MixGame = {}

local G = Config.Minigame
local SIZE = 300

local overlay: Frame
local area: Frame
local zone: Frame
local dot: Frame
local title: TextLabel
local meter: Frame
local status: TextLabel
local submit: RemoteEvent
local running = false
local touchPos: Vector2? = nil

local function circle(parent: Instance, name: string, size: number, color: Color3, transparency: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = f
	return f
end

function MixGame.Mount(screen: ScreenGui)
	submit = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MixSubmit") :: RemoteEvent

	overlay = Instance.new("Frame")
	overlay.Name = "MixGame"
	overlay.AnchorPoint = Vector2.new(0.5, 0.5)
	overlay.Position = UDim2.fromScale(0.5, 0.5)
	overlay.Size = UDim2.fromOffset(SIZE + 40, SIZE + 110)
	overlay.BackgroundColor3 = Color3.fromRGB(30, 22, 18)
	overlay.BackgroundTransparency = 0.05
	overlay.Visible = false
	overlay.ZIndex = 30
	overlay.Active = true -- swallow clicks so the camera doesn't spin
	overlay.Parent = screen
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = overlay
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(150, 236, 200)
	stroke.Thickness = 3
	stroke.Parent = overlay

	title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 32)
	title.Position = UDim2.fromOffset(10, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "🥣 Keep the dot in the sweet spot!"
	title.Parent = overlay

	area = circle(overlay, "Bowl", SIZE, Color3.fromRGB(255, 240, 210), 0)
	area.Position = UDim2.new(0.5, 0, 0, 46 + SIZE / 2)
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.fromRGB(150, 236, 200)
	rim.Thickness = 6
	rim.Parent = area

	zone = circle(area, "SweetSpot", 60, Color3.fromRGB(120, 230, 150), 0.25)
	dot = circle(area, "Dot", 18, Color3.fromRGB(255, 105, 160), 0)
	dot.ZIndex = 32

	meter = Instance.new("Frame")
	meter.Name = "Meter"
	meter.Size = UDim2.new(0, 0, 0, 10)
	meter.Position = UDim2.new(0, 20, 1, -46)
	meter.BackgroundColor3 = Color3.fromRGB(120, 230, 150)
	meter.Parent = overlay

	status = Instance.new("TextLabel")
	status.Size = UDim2.new(1, -20, 0, 26)
	status.Position = UDim2.new(0, 10, 1, -32)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.FredokaOne
	status.TextScaled = true
	status.TextColor3 = Color3.fromRGB(255, 240, 200)
	status.Parent = overlay

	-- Touch: follow the finger while it is down (works with drags anywhere).
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			touchPos = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			touchPos = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
end

-- Pointer position in pixels, relative to the bowl's centre.
local function pointer(): Vector2
	local screenPos = touchPos or UserInputService:GetMouseLocation()
	local centre = area.AbsolutePosition + area.AbsoluteSize / 2
	-- The HUD ignores the top-bar inset, so GUI and mouse coordinates match.
	return screenPos - centre
end

local function gradeFor(score: number): string
	for _, entry in G.Grades do
		if score >= entry[2] then
			return entry[1]
		end
	end
	return "Sloppy"
end

function MixGame.Play(sessionId: string, stationId: string, seed: number)
	if running then
		return
	end
	running = true
	local station = G.Stations[stationId] or G.Stations.Mixer
	local rng = Random.new(seed)
	local phases = { rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28) }
	local radiusPx = station.Radius * SIZE
	zone.Size = UDim2.fromOffset(radiusPx * 2, radiusPx * 2)
	title.Text = `🥣 {station.Label}: keep the dot in the sweet spot!`
	overlay.Visible = true
	meter.Size = UDim2.new(0, 0, 0, 10)

	local inside, total, elapsed = 0, 0, -G.ReadyTime
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		-- Zone drifts on a smooth looping path that stays inside the bowl.
		local t = math.max(0, elapsed) * station.Speed
		local reach = SIZE / 2 - radiusPx - 10
		local zx = math.sin(t * 1.3 + phases[1]) * 0.7 + math.sin(t * 2.1 + phases[2]) * 0.3
		local zy = math.cos(t * 1.1 + phases[3]) * 0.7 + math.sin(t * 1.7 + phases[1]) * 0.3
		local zonePos = Vector2.new(zx, zy) * reach
		zone.Position = UDim2.new(0.5, zonePos.X, 0.5, zonePos.Y)

		local p = pointer()
		if p.Magnitude > SIZE / 2 then
			p = p.Unit * (SIZE / 2)
		end
		dot.Position = UDim2.new(0.5, p.X, 0.5, p.Y)

		if elapsed < 0 then
			status.Text = "Get ready..."
			return
		end
		total += dt
		local isIn = (p - zonePos).Magnitude <= radiusPx
		if isIn then
			inside += dt
		end
		zone.BackgroundColor3 = if isIn then Color3.fromRGB(120, 230, 150) else Color3.fromRGB(255, 190, 120)
		local score = inside / math.max(total, 1e-3)
		meter.Size = UDim2.new(0, (SIZE) * math.min(1, elapsed / G.Duration), 0, 10)
		status.Text = string.format("%.1fs  |  %s (%d%%)", math.max(0, G.Duration - elapsed), gradeFor(score), math.floor(score * 100))

		if elapsed >= G.Duration then
			conn:Disconnect()
			submit:FireServer(sessionId, score)
			status.Text = `{gradeFor(score)}!`
			local pop = TweenService:Create(overlay, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true), { Size = UDim2.fromOffset(SIZE + 60, SIZE + 130) })
			pop:Play()
			task.delay(0.8, function()
				overlay.Visible = false
				running = false
				touchPos = nil
			end)
		end
	end)
end

return MixGame
