--!strict
-- Custom hotbar (replaces Roblox's backpack bar). Up to Config.Hotbar.Slots
-- slots: 3D icon (ItemIcon), frame colour + glow by rarity (shimmer for Mythic+),
-- trait/mutation badges, number key. Keys 1-9 / click / tap equip and unequip,
-- gamepad bumpers cycle. Hover (or long-press) shows the Tooltip. More items than
-- slots: a "+N" slot opens a grid of everything you're carrying.
-- Tools stay in their order across equip/unequip; new tools go to the end.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))
local ItemIcon = require(script.Parent:WaitForChild("ItemIcon"))
local Tooltip = require(script.Parent:WaitForChild("Tooltip"))

local Hotbar = {}

local H = Config.Hotbar
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine }

local player = Players.LocalPlayer
local order: { Tool } = {} -- every tool the player carries, in hotbar order
local bar: Frame
local grid: Frame
local gridList: ScrollingFrame
local cameras: { Camera } = {}
local shimmer: { UIGradient } = {}
local dirty = true

local function corner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function isEquipped(tool: Tool): boolean
	return player.Character ~= nil and tool.Parent == player.Character
end

local function toggle(tool: Tool)
	local h = humanoid()
	if not h then
		return
	end
	if isEquipped(tool) then
		h:UnequipTools()
	else
		h:EquipTool(tool)
	end
end

-- One cartoony slot (also used in the overflow grid).
local function makeSlot(parent: Instance, tool: Tool, keyText: string?, onClick: () -> ()): Frame
	local info = ItemIcon.Describe(tool)
	local color = ItemIcon.Color(info)
	local equipped = isEquipped(tool)
	local slot = Instance.new("Frame")
	slot.Size = UDim2.fromOffset(H.SlotSize, H.SlotSize)
	slot.BackgroundColor3 = color:Lerp(Color3.fromRGB(40, 28, 36), 0.7)
	slot.Parent = parent
	corner(slot, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = if equipped then 5 else 3 + (info.Rarity or 0) * 0.3
	stroke.Color = if equipped then Color3.new(1, 1, 1) else color
	stroke.Parent = slot
	if info.Rarity and info.Rarity >= Rarity.MYTHIC and not equipped then
		stroke.Color = Color3.new(1, 1, 1)
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, color) })
		g.Parent = stroke
		table.insert(shimmer, g)
	end
	-- Soft glow behind rare items.
	if (info.Rarity or 0) >= 3 then
		local glow = Instance.new("Frame")
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.Size = UDim2.new(1, 10 + info.Rarity * 2, 1, 10 + info.Rarity * 2)
		glow.BackgroundColor3 = color
		glow.BackgroundTransparency = 0.75
		glow.ZIndex = 0
		glow.Parent = slot
		corner(glow, 18)
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, -8, 1, -8)
	viewport.Position = UDim2.fromOffset(4, 4)
	viewport.BackgroundTransparency = 1
	viewport.Parent = slot
	local camera = ItemIcon.Render(viewport, tool)
	if camera then
		table.insert(cameras, camera)
	end
	if keyText then
		local key = Instance.new("TextLabel")
		key.Size = UDim2.fromOffset(20, 20)
		key.Position = UDim2.fromOffset(3, 3)
		key.BackgroundColor3 = Color3.fromRGB(255, 105, 160)
		key.TextColor3 = Color3.new(1, 1, 1)
		key.Font = Enum.Font.FredokaOne
		key.TextScaled = true
		key.Text = keyText
		key.ZIndex = 3
		key.Parent = slot
		corner(key, 10)
	end
	local badges = ItemIcon.Badges(info)
	if badges ~= "" then
		local b = Instance.new("TextLabel")
		b.AnchorPoint = Vector2.new(1, 1)
		b.Position = UDim2.new(1, -2, 1, -2)
		b.Size = UDim2.new(1, -4, 0, 16)
		b.BackgroundTransparency = 1
		b.TextXAlignment = Enum.TextXAlignment.Right
		b.TextScaled = true
		b.Text = badges
		b.ZIndex = 3
		b.Parent = slot
	end
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.ZIndex = 4
	button.Parent = slot
	button.Activated:Connect(onClick)
	button.MouseEnter:Connect(function()
		Tooltip.Show(tool, slot.AbsolutePosition + Vector2.new(slot.AbsoluteSize.X / 2, 0))
	end)
	button.MouseLeave:Connect(Tooltip.Hide)
	button.TouchLongPress:Connect(function()
		Tooltip.Show(tool, slot.AbsolutePosition + Vector2.new(slot.AbsoluteSize.X / 2, 0))
		task.delay(2.5, Tooltip.Hide)
	end)
	if equipped then
		slot.Size = UDim2.fromOffset(H.SlotSize + 8, H.SlotSize + 8)
	end
	return slot
end

local function render()
	dirty = false
	cameras = {}
	shimmer = {}
	Tooltip.Hide()
	for _, child in bar:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local shown = math.min(#order, H.Slots)
	local overflow = #order - shown
	if overflow > 0 then
		shown = H.Slots - 1 -- the last slot becomes "+N"
		overflow = #order - shown
	end
	for i = 1, shown do
		local tool = order[i]
		local slot = makeSlot(bar, tool, tostring(i), function()
			toggle(tool)
		end)
		slot.LayoutOrder = i
	end
	if overflow > 0 then
		local more = Instance.new("Frame")
		more.LayoutOrder = H.Slots
		more.Size = UDim2.fromOffset(H.SlotSize, H.SlotSize)
		more.BackgroundColor3 = Color3.fromRGB(255, 105, 160)
		more.Parent = bar
		corner(more, 14)
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromScale(1, 1)
		b.BackgroundTransparency = 1
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.FredokaOne
		b.TextScaled = true
		b.Text = `+{overflow}`
		b.Parent = more
		b.Activated:Connect(function()
			grid.Visible = not grid.Visible
			dirty = true
		end)
	end
	-- Overflow grid lists everything; clicking moves the item into slot 1 and equips it.
	for _, child in gridList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if grid.Visible then
		for i, tool in order do
			local slot = makeSlot(gridList, tool, nil, function()
				local index = table.find(order, tool)
				if index then
					table.remove(order, index)
					table.insert(order, 1, tool)
				end
				grid.Visible = false
				toggle(tool)
				dirty = true
			end)
			slot.LayoutOrder = i
		end
	end
	bar.Visible = #order > 0
end

local function track(tool: Instance)
	if not tool:IsA("Tool") or table.find(order, tool) then
		return
	end
	table.insert(order, tool)
	dirty = true
	tool.AncestryChanged:Connect(function()
		local parent = tool.Parent
		local character = player.Character
		local backpack = player:FindFirstChildOfClass("Backpack")
		if parent ~= backpack and (character == nil or parent ~= character) then
			local index = table.find(order, tool)
			if index then
				table.remove(order, index)
			end
		end
		dirty = true -- equipped state changed or the tool went away
	end)
	tool:GetAttributeChangedSignal("CakeRarity"):Connect(function()
		dirty = true
	end)
end

local function watch(container: Instance?)
	if not container then
		return
	end
	for _, child in container:GetChildren() do
		track(child)
	end
	container.ChildAdded:Connect(track)
end

function Hotbar.Mount(screen: ScreenGui)
	-- Hide Roblox's backpack bar (retry: CoreGui may not be ready yet).
	task.spawn(function()
		for _ = 1, 20 do
			if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then
				break
			end
			task.wait(0.5)
		end
	end)

	bar = Instance.new("Frame")
	bar.Name = "Hotbar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -H.BottomOffset)
	bar.Size = UDim2.fromOffset(0, H.SlotSize + 10)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundTransparency = 1
	bar.Visible = false
	bar.Parent = screen
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar
	-- Shrink on small (phone) screens.
	local scale = Instance.new("UIScale")
	scale.Parent = bar
	local function rescale()
		local width = screen.AbsoluteSize.X
		scale.Scale = math.clamp(width / (H.Slots * (H.SlotSize + 8) + 60), 0.55, 1)
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	rescale()

	grid = Instance.new("Frame")
	grid.Name = "HotbarGrid"
	grid.AnchorPoint = Vector2.new(0.5, 1)
	grid.Position = UDim2.new(0.5, 0, 1, -(H.BottomOffset + H.SlotSize + 24))
	grid.Size = UDim2.fromOffset(H.Slots * (H.SlotSize + 8) + 16, 2 * (H.SlotSize + 8) + 16)
	grid.BackgroundColor3 = Color3.fromRGB(40, 28, 36)
	grid.BackgroundTransparency = 0.1
	grid.Visible = false
	grid.Parent = screen
	corner(grid, 14)
	gridList = Instance.new("ScrollingFrame")
	gridList.Size = UDim2.new(1, -16, 1, -16)
	gridList.Position = UDim2.fromOffset(8, 8)
	gridList.BackgroundTransparency = 1
	gridList.ScrollBarThickness = 6
	gridList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	gridList.CanvasSize = UDim2.new()
	gridList.Parent = grid
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(H.SlotSize, H.SlotSize)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridList

	Tooltip.Mount(screen)

	watch(player:FindFirstChildOfClass("Backpack"))
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watch(child)
		end
	end)
	watch(player.Character)
	player.CharacterAdded:Connect(function(character)
		order = {}
		dirty = true
		watch(character)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local index = table.find(KEYS, input.KeyCode)
		if index and order[index] and (index < H.Slots or #order <= H.Slots) then
			toggle(order[index])
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 or input.KeyCode == Enum.KeyCode.ButtonL1 then
			if #order == 0 then
				return
			end
			local current = 0
			for i, tool in order do
				if isEquipped(tool) then
					current = i
				end
			end
			local step = if input.KeyCode == Enum.KeyCode.ButtonR1 then 1 else -1
			local nextIndex = ((current - 1 + step) % math.min(#order, H.Slots)) + 1
			toggle(order[nextIndex])
		end
	end)

	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		if dirty then
			render()
		end
		for _, camera in cameras do
			ItemIcon.Spin(camera, t)
		end
		for _, g in shimmer do
			g.Rotation = (g.Rotation + dt * 120) % 360
		end
	end)
end

-- Test helper: names in hotbar order.
function Hotbar.Order(): { string }
	local names = {}
	for _, tool in order do
		table.insert(names, tool.Name)
	end
	return names
end

return Hotbar
