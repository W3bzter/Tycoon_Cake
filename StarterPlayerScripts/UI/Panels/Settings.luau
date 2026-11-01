--!strict
-- Settings panel (⚙️ button in the right-side bar): Music and Sound effects volume
-- (0..100% in 10% steps) and whether Auto-Roller rolls pop up on screen. Saved
-- by the server (Remotes.Settings -> Inventory.SettingsAction) and mirrored back
-- as player attributes; UI/Audio applies the volumes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = {}

local DARK = Color3.fromRGB(30, 22, 18)
local CREAM = Color3.fromRGB(255, 240, 200)
local GREEN = Color3.fromRGB(70, 190, 110)
local GREY = Color3.fromRGB(95, 85, 80)
local BLUE = Color3.fromRGB(70, 140, 220)

local function corner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function label(parent: Instance, text: string, size: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = CREAM
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, color: Color3, size: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.Text = text
	b.Parent = parent
	corner(b, 8)
	return b
end

function Settings.Mount(screen: ScreenGui, player: Player)
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Settings") :: RemoteEvent

	local toggle = button(screen, "⚙️ Settings", GREY, UDim2.fromOffset(130, 34))
	toggle.Name = "SettingsToggle"

	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(320, 230)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.08
	panel.Visible = false
	panel.ZIndex = 30
	panel.Parent = screen
	corner(panel, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = CREAM
	stroke.Thickness = 2
	stroke.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 10)
	pad.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 30)
	header.LayoutOrder = 0
	header.Parent = panel
	label(header, "⚙️ Settings", UDim2.new(1, -40, 1, 0))
	local close = button(header, "✖", Color3.fromRGB(220, 70, 70), UDim2.fromOffset(30, 30))
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	-- One volume row: name, -, value, +.
	local function volumeRow(order: number, title: string, kind: string, attr: string, default: number)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 34)
		row.LayoutOrder = order
		row.Parent = panel
		local titleLabel = label(row, title, UDim2.new(0.45, 0, 1, 0))
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = 18 -- so "Music" and "Sound effects" match
		cap.Parent = titleLabel
		local minus = button(row, "−", BLUE, UDim2.fromOffset(34, 30))
		minus.Position = UDim2.new(0.48, 0, 0, 2)
		local value = label(row, "", UDim2.fromOffset(60, 30))
		value.Position = UDim2.new(0.48, 40, 0, 2)
		value.TextXAlignment = Enum.TextXAlignment.Center
		local plus = button(row, "+", BLUE, UDim2.fromOffset(34, 30))
		plus.Position = UDim2.new(0.48, 104, 0, 2)
		local function current(): number
			return (player:GetAttribute(attr) :: number?) or default
		end
		local function render()
			value.Text = `{math.round(current() * 100)}%`
		end
		minus.Activated:Connect(function()
			remote:FireServer("volume", kind, math.max(0, current() - 0.1))
		end)
		plus.Activated:Connect(function()
			remote:FireServer("volume", kind, math.min(1, current() + 0.1))
		end)
		player:GetAttributeChangedSignal(attr):Connect(render)
		render()
	end
	volumeRow(1, "🎵 Music", "Music", "MusicVolume", 0.6)
	volumeRow(2, "🔊 Sound effects", "SFX", "SfxVolume", 1)

	local popups = button(panel, "", GREEN, UDim2.new(1, 0, 0, 36))
	popups.LayoutOrder = 3
	local function renderPopups()
		local on = player:GetAttribute("AutoRollPopups") ~= false
		popups.Text = if on then "🎲 Auto-Roll pop-ups: ON" else "🎲 Auto-Roll pop-ups: OFF"
		popups.BackgroundColor3 = if on then GREEN else GREY
	end
	popups.Activated:Connect(function()
		remote:FireServer("autorollpopups", player:GetAttribute("AutoRollPopups") == false)
	end)
	player:GetAttributeChangedSignal("AutoRollPopups"):Connect(renderPopups)
	renderPopups()
	local note = label(panel, "(Legendary and better always show)", UDim2.new(1, 0, 0, 18))
	note.LayoutOrder = 4
	note.TextColor3 = Color3.fromRGB(200, 185, 160)

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

return Settings
