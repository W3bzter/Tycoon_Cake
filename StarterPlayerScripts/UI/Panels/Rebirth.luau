--!strict
-- Rebirth panel: current rebirths and bonus, the next rebirth's Cash cost and cake
-- requirements (✓/✗ live from the cakes you're holding, using the same matching
-- as the server: Shared/RebirthDefs), and a two-click confirm button that fires
-- Remotes.Rebirth.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CakeData = require(Shared:WaitForChild("CakeData"))
local RebirthDefs = require(Shared:WaitForChild("RebirthDefs"))

local Rebirth = {}

local DARK = Color3.fromRGB(30, 22, 18)
local MINT = Color3.fromRGB(90, 230, 170)

local function corner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.TextScaled = true
	l.TextWrapped = true
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

local function heldCakes(player: Player): { any }
	local cakes = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		for _, tool in (if container then container:GetChildren() else {}) do
			if tool:IsA("Tool") and tool:GetAttribute("ItemKind") == "FinishedCake" then
				table.insert(cakes, CakeData.Read(tool, "Variant"))
			end
		end
	end
	return cakes
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function cash(player: Player): number
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Cash") :: IntValue?
	return value and value.Value or 0
end

function Rebirth.Mount(screen: ScreenGui, player: Player)
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Rebirth") :: RemoteEvent

	local hudButton = Instance.new("TextButton")
	hudButton.Name = "RebirthToggle"
	hudButton.AnchorPoint = Vector2.new(0, 1)
	hudButton.Position = UDim2.new(0, 608, 1, -16)
	hudButton.Size = UDim2.fromOffset(130, 34)
	hudButton.BackgroundColor3 = Color3.fromRGB(60, 190, 140)
	hudButton.TextColor3 = Color3.new(1, 1, 1)
	hudButton.Font = Enum.Font.FredokaOne
	hudButton.TextScaled = true
	hudButton.Text = "♻️ Rebirth"
	hudButton.Parent = screen
	corner(hudButton, 8)

	local panel = Instance.new("Frame")
	panel.Name = "RebirthPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(480, 380)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.ZIndex = 5
	panel.Parent = screen
	corner(panel, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = MINT
	stroke.Thickness = 3
	stroke.Parent = panel
	local maxSize = Instance.new("UISizeConstraint")
	maxSize.MaxSize = Vector2.new(480, 380)
	maxSize.Parent = panel

	local title = label(panel, "♻️ Rebirth", UDim2.new(1, -60, 0, 30), UDim2.fromOffset(14, 8), MINT)
	local close = Instance.new("TextButton")
	close.Size = UDim2.fromOffset(34, 30)
	close.Position = UDim2.new(1, -44, 0, 8)
	close.BackgroundColor3 = Color3.fromRGB(150, 60, 70)
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Font = Enum.Font.FredokaOne
	close.TextScaled = true
	close.Text = "X"
	close.Parent = panel
	corner(close, 8)
	local bonus = label(panel, "", UDim2.new(1, -28, 0, 20), UDim2.fromOffset(14, 42), Color3.fromRGB(255, 230, 160))
	local resetNote = label(panel, "Resets your Cash and bakery upgrades. Keeps Gems, Gem upgrades, your Ingredient Bag, storage, achievements and Robux items.", UDim2.new(1, -28, 0, 34), UDim2.fromOffset(14, 66), Color3.fromRGB(210, 200, 190))
	resetNote.TextScaled = true
	label(panel, "Hold these cakes in your inventory:", UDim2.new(1, -28, 0, 20), UDim2.fromOffset(14, 108), Color3.new(1, 1, 1))
	local reqList = Instance.new("Frame")
	reqList.Size = UDim2.new(1, -28, 0, 150)
	reqList.Position = UDim2.fromOffset(14, 132)
	reqList.BackgroundTransparency = 1
	reqList.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = reqList
	local costLabel = label(panel, "", UDim2.new(1, -28, 0, 22), UDim2.fromOffset(14, 286))
	local go = Instance.new("TextButton")
	go.Size = UDim2.new(1, -28, 0, 44)
	go.Position = UDim2.new(0, 14, 1, -56)
	go.BackgroundColor3 = MINT
	go.TextColor3 = Color3.new(1, 1, 1)
	go.Font = Enum.Font.FredokaOne
	go.TextScaled = true
	go.Text = "♻️ REBIRTH"
	go.Parent = panel
	corner(go, 10)

	local armedUntil = 0
	local function render()
		local done = (player:GetAttribute("Rebirths") :: number?) or 0
		local reqs = RebirthDefs.Requirements(done)
		local cost = RebirthDefs.Cost(done)
		local cakes = heldCakes(player)
		local ok, _, found = RebirthDefs.Match(reqs, cakes)
		local affordable = cash(player) >= cost
		title.Text = `♻️ Rebirth {done + 1}`
		bonus.Text = `Rebirths: {done}  |  Now: +{math.floor(done * RebirthDefs.SalePriceBonus * 100)}% cake prices  →  next: +{math.floor((done + 1) * RebirthDefs.SalePriceBonus * 100)}% and more mutations`
		for _, child in reqList:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		for i, req in reqs do
			local met = (found[i] or 0) >= req.Count
			local row = label(reqList, `{if met then "✅" else "❌"} {RebirthDefs.Describe(req)}  ({math.min(found[i] or 0, req.Count)}/{req.Count})`, UDim2.new(1, 0, 0, 24), UDim2.new(), if met then MINT else Color3.fromRGB(255, 150, 150))
			row.LayoutOrder = i
		end
		costLabel.Text = `{if affordable then "✅" else "❌"} Cost: ${commas(cost)}`
		costLabel.TextColor3 = if affordable then MINT else Color3.fromRGB(255, 150, 150)
		local ready = ok and affordable
		go.AutoButtonColor = ready
		go.BackgroundColor3 = if ready then MINT else Color3.fromRGB(80, 80, 90)
		if os.clock() >= armedUntil then
			go.Text = if ready then "♻️ REBIRTH" else "Not ready yet"
		end
	end

	go.Activated:Connect(function()
		if os.clock() < armedUntil then
			armedUntil = 0
			remote:FireServer()
			panel.Visible = false
		else
			armedUntil = os.clock() + 3
			go.Text = "⚠️ Click again to rebirth!"
		end
	end)
	close.Activated:Connect(function()
		panel.Visible = false
	end)
	hudButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			render()
		end
	end)
	-- Live refresh while open (held cakes and cash change all the time).
	task.spawn(function()
		while true do
			task.wait(0.5)
			if panel.Visible then
				render()
			end
		end
	end)
	player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		hudButton.Text = `♻️ Rebirth ({(player:GetAttribute("Rebirths") :: number?) or 0})`
	end)
	hudButton.Text = `♻️ Rebirth ({(player:GetAttribute("Rebirths") :: number?) or 0})`
end

return Rebirth
