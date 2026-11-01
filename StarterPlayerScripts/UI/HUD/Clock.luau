--!strict
-- Top-right day/night clock: "☀️ Day 4:12" / "🌙 Night 1:05 - anomalies!" from
-- the server's ReplicatedStorage attributes IsNight / PhaseEndsAt (World/DayNight),
-- plus "✨ Mutation x2 0:42" while a mutation event runs (Baking/MutationEvents).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Clock = {}

local DAY = Color3.fromRGB(255, 200, 80)
local NIGHT = Color3.fromRGB(120, 130, 255)
local EVENT = Color3.fromRGB(255, 110, 200)

local function timeLeft(endsAt: number?): string
	local left = math.max(0, (endsAt or 0) - workspace:GetServerTimeNow())
	return string.format("%d:%02d", left // 60, math.floor(left % 60))
end

local function chip(parent: Instance, order: number): (TextLabel, UIStroke)
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.fromOffset(220, 30)
	l.BackgroundColor3 = Color3.fromRGB(30, 22, 30)
	l.BackgroundTransparency = 0.2
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = l
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = l
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 3)
	pad.Parent = l
	return l, stroke
end

function Clock.Mount(screen: ScreenGui)
	local holder = Instance.new("Frame")
	holder.Name = "Clock"
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -12, 0, 12)
	holder.Size = UDim2.fromOffset(220, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.BackgroundTransparency = 1
	holder.Parent = screen
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder

	local phase, phaseStroke = chip(holder, 1)
	local event, eventStroke = chip(holder, 2)
	eventStroke.Color = EVENT

	RunService.Heartbeat:Connect(function()
		local night = ReplicatedStorage:GetAttribute("IsNight") == true
		local left = timeLeft(ReplicatedStorage:GetAttribute("PhaseEndsAt") :: number?)
		phase.Text = if night then `🌙 Night {left} · anomalies!` else `☀️ Day {left}`
		phaseStroke.Color = if night then NIGHT else DAY

		local mult = ReplicatedStorage:GetAttribute("MutationEventMult") :: number?
		local endsAt = ReplicatedStorage:GetAttribute("MutationEventEndsAt") :: number?
		local active = mult ~= nil and endsAt ~= nil and endsAt > workspace:GetServerTimeNow()
		event.Visible = active
		if active then
			local name = (ReplicatedStorage:GetAttribute("MutationEventName") :: string?) or "Mutations"
			event.Text = `✨ {name} x{mult} {timeLeft(endsAt)}`
		end
	end)
end

return Clock
