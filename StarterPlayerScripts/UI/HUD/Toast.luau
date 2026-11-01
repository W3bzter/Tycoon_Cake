--!strict
-- Short message at the bottom of the screen for server Notify events.

local TweenService = game:GetService("TweenService")

local Toast = {}

local label: TextLabel
local token = 0

function Toast.Mount(screen: ScreenGui)
	label = Instance.new("TextLabel")
	label.Name = "Toast"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -110)
	label.Size = UDim2.fromOffset(0, 40)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundColor3 = Color3.fromRGB(30, 22, 18)
	label.BackgroundTransparency = 0.2
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 22
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Visible = false
	label.Parent = screen
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = label
end

function Toast.Show(message: string)
	token += 1
	local mine = token
	label.Text = message
	label.TextTransparency = 0
	label.BackgroundTransparency = 0.2
	label.Visible = true
	task.delay(2.5, function()
		if mine ~= token then
			return -- a newer toast replaced this one
		end
		local info = TweenInfo.new(0.4)
		TweenService:Create(label, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.wait(0.4)
		if mine == token then
			label.Visible = false
		end
	end)
end

return Toast
