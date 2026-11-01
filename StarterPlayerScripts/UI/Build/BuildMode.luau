--!strict
-- Build mode on the client: the state machine and input. B (or the 🔨 Build
-- button) toggles it. While on: buy/place from the catalog panel, click a placed
-- item to move / rotate / store / upgrade it. R rotates, X stores, a quick
-- right-click (not a camera drag) or Backspace cancels. On touch, tap the floor to move the ghost and press Place.
-- Sends Remotes.BuildAction; the server (Build/BuildService) validates everything
-- and answers with BuildSync (+ Notify on refusals).
-- Uses UI/Build/BuildGhost (preview) and UI/Build/BuildMenu (screens).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local BuildGhost = require(script.Parent:WaitForChild("BuildGhost"))
local BuildMenu = require(script.Parent:WaitForChild("BuildMenu"))
local Toast = require(script.Parent.Parent:WaitForChild("HUD"):WaitForChild("Toast"))

local BuildMode = {}

local player = Players.LocalPlayer

local active = false
local mode = "idle" -- "idle" | "place" | "move"
local placingId: string? = nil
local moving: Model? = nil
local selected: Model? = nil
local hovered: Model? = nil
local ghost: BuildGhost.Ghost? = nil
local gx, gz, rot = 0, 0, 0
local cellOk, cellReason = false, nil :: string?
local owned: { [string]: number } = {}
local lastSend = 0
local lastKey = "" -- cell last checked by updateGhost
local rightDownAt: number? = nil -- right mouse press (click = cancel, drag = camera)
local rightMoved = 0 -- pixels the mouse moved while right is held (the cursor is locked, so count deltas)
local RIGHT_CLICK_TIME = 0.3 -- seconds
local RIGHT_CLICK_SLOP = 6 -- pixels
local menu: any = nil
local action: RemoteEvent = nil :: any

local selectBox = Instance.new("SelectionBox")
selectBox.Color3 = Color3.fromRGB(255, 200, 60)
selectBox.LineThickness = 0.08
selectBox.SurfaceTransparency = 1
local hoverBox = Instance.new("SelectionBox")
hoverBox.Color3 = Color3.fromRGB(255, 255, 255)
hoverBox.LineThickness = 0.04
hoverBox.SurfaceTransparency = 1

local function send(...: any): boolean
	local now = os.clock()
	if now - lastSend < Config.Build.ActionCooldown + 0.05 then
		return false -- the server would drop it silently
	end
	lastSend = now
	action:FireServer(...)
	return true
end

local function setFaded(model: Model?, faded: boolean)
	for _, d in (if model then model:GetDescendants() else {}) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if faded then 0.75 else 0
		end
	end
end

local function selectModel(model: Model?)
	selected = model
	selectBox.Adornee = model
	selectBox.Parent = if model then workspace.CurrentCamera else nil
	if menu then
		menu.SetMode(mode, selected)
	end
end

local function stopGhost()
	if ghost then
		ghost.Destroy()
		ghost = nil
	end
	setFaded(moving, false)
	placingId, moving = nil, nil
	mode = "idle"
	if menu then
		menu.SetMode(mode, selected)
	end
end

local function startGhost(id: string, from: Model?)
	stopGhost()
	local plot = BuildGhost.Plot()
	ghost = BuildGhost.New(id)
	if not plot or not ghost then
		Toast.Show("🔨 Build mode is still loading, try again in a moment.")
		stopGhost()
		return
	end
	placingId = id
	lastKey = ""
	if from then
		moving = from
		mode = "move"
		gx, gz, rot = BuildGhost.CellOf(plot, from)
		setFaded(from, true)
	else
		mode = "place"
		rot = 0
		local template = BuildGhost.Template(id) :: Model
		-- Start at the item's usual spot, pulled inside a small bakery's walls.
		local b = BuildGhost.Areas(plot)[1] -- inside the walls
		local g = Config.Build.Grid
		gx = math.clamp((template:GetAttribute("DefaultGX") :: number?) or 0, math.ceil(b.MinX / g) + 1, math.floor(b.MaxX / g) - 1)
		gz = math.clamp((template:GetAttribute("DefaultGZ") :: number?) or 0, math.ceil(b.MinZ / g) + 1, math.floor(b.MaxZ / g) - 1)
	end
	selectModel(nil)
	menu.SetMode(mode, nil)
end

-- Item under a screen ray among this plot's placed models.
local function placedAt(plot: Model, ray: Ray): Model?
	local folder = plot:FindFirstChild("Placed")
	if not folder then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	local inst: Instance? = hit and hit.Instance
	while inst and inst.Parent ~= folder do
		inst = inst.Parent
	end
	return if inst and inst:IsA("Model") then inst else nil
end

local function mouseRay(): Ray
	local pos = UserInputService:GetMouseLocation()
	return workspace.CurrentCamera:ViewportPointToRay(pos.X, pos.Y)
end

-- Re-checks the cell only when it, the rotation, or the plot (lastKey reset) changed.
local function updateGhost(plot: Model, force: boolean?)
	if not ghost or not placingId then
		return
	end
	local key = `{gx},{gz},{rot}`
	if key == lastKey and not force then
		return
	end
	lastKey = key
	local ok, reason, rect = BuildGhost.Check(plot, placingId, gx, gz, rot, moving)
	cellOk, cellReason = ok, reason
	if rect then
		ghost.Set(plot, gx, gz, rot, ok, rect)
	end
end

local function confirm()
	local plot = BuildGhost.Plot()
	if not plot or not placingId then
		return
	end
	updateGhost(plot, true)
	if not cellOk then
		Toast.Show(`🔨 Can't place it there: {cellReason or "blocked"}.`)
		return
	end
	if mode == "move" and moving then
		if send("move", moving:GetAttribute("Uid"), gx, gz, rot) then
			stopGhost()
		end
	elseif send("place", placingId, gx, gz, rot) then
		local left = (owned[placingId] or 0) - 1
		owned[placingId] = left
		if left <= 0 then
			stopGhost()
		end
	end
end

local function rotate()
	if mode ~= "idle" then
		rot = (rot + 1) % 4
		local plot = BuildGhost.Plot()
		if plot then
			updateGhost(plot)
		end
	elseif selected then
		local plot = BuildGhost.Plot()
		if plot then
			local x, z, r = BuildGhost.CellOf(plot, selected)
			send("move", selected:GetAttribute("Uid"), x, z, (r + 1) % 4)
		end
	end
end

local function cancel()
	if mode ~= "idle" then
		stopGhost()
	else
		selectModel(nil)
	end
end

local function store()
	if selected and mode == "idle" and send("store", selected:GetAttribute("Uid")) then
		selectModel(nil)
	end
end

local function setActive(on: boolean)
	local plot = BuildGhost.Plot()
	if on and not plot then
		Toast.Show("🔨 Claim a bakery first!")
		return
	end
	active = on
	stopGhost()
	selectModel(nil)
	hoverBox.Adornee = nil
	hoverBox.Parent = nil
	-- Prompt keys (R, Q...) double as build keys; hide prompts while building.
	ProximityPromptService.Enabled = not on
	if on and plot then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools() -- a clicked Tool would fire too
		end
		BuildGhost.ShowOverlay(plot)
	else
		BuildGhost.HideOverlay()
	end
	menu.SetActive(on)
end

function BuildMode.IsActive(): boolean
	return active
end

function BuildMode.Mount(screen: ScreenGui)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	action = remotes:WaitForChild("BuildAction") :: RemoteEvent
	menu = BuildMenu.Mount(screen, player, {
		Toggle = function()
			setActive(not active)
		end,
		Buy = function(id)
			send("buy", id)
		end,
		BuyUpgrade = function(id)
			send("upgrade", id)
		end,
		Place = function(id)
			startGhost(id, nil)
		end,
		Rotate = rotate,
		Confirm = confirm,
		Cancel = cancel,
		Move = function()
			local model = selected
			if model then
				startGhost(model:GetAttribute("CatalogId") :: string, model)
			end
		end,
		Store = store,
		Upgrade = function(id)
			if selected then
				send("buy", id, selected:GetAttribute("Uid"))
			end
		end,
	})

	local hinted = false
	remotes:WaitForChild("BuildSync").OnClientEvent:Connect(function(state)
		if not hinted and (state.Counts or {}).IngredientCrate == 0 then
			hinted = true -- a brand-new bakery: point at the Build shop
			Toast.Show("🔨 Press B (or the Build button) to buy and place your Pantry!")
		end
		owned = table.clone(state.Owned or {})
		lastKey = "" -- placed items / reserved spots may have changed
		menu.Refresh(state)
		if mode == "place" and placingId and (owned[placingId] or 0) <= 0 then
			stopGhost()
		end
		-- An upgrade rebuilds the model: drop a selection that no longer exists.
		if selected and not selected:IsDescendantOf(workspace) then
			selectModel(nil)
		elseif selected then
			menu.SetMode(mode, selected)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.B and not processed then
			setActive(not active)
			return
		end
		if not active then
			return
		end
		local plot = BuildGhost.Plot()
		if input.KeyCode == Enum.KeyCode.R then
			rotate()
		elseif input.KeyCode == Enum.KeyCode.X or input.KeyCode == Enum.KeyCode.Delete then
			store()
		elseif input.KeyCode == Enum.KeyCode.Backspace then
			cancel()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			-- Right mouse also turns the camera: only a quick click without dragging cancels (see InputEnded).
			rightDownAt, rightMoved = os.clock(), 0
		elseif processed or not plot then
			return -- clicks on the UI
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			if mode ~= "idle" then
				confirm()
			else
				selectModel(placedAt(plot, mouseRay()))
			end
		elseif input.UserInputType == Enum.UserInputType.Touch then
			local ray = workspace.CurrentCamera:ScreenPointToRay(input.Position.X, input.Position.Y)
			if mode ~= "idle" then
				local x, z = BuildGhost.CellAt(plot, ray)
				if x and z then
					gx, gz = x, z
					updateGhost(plot)
				end
			else
				selectModel(placedAt(plot, ray))
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if rightDownAt and input.UserInputType == Enum.UserInputType.MouseMovement then
			rightMoved += input.Delta.Magnitude
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if active and input.UserInputType == Enum.UserInputType.MouseButton2 and rightDownAt then
			local quick = os.clock() - rightDownAt < RIGHT_CLICK_TIME
			local still = rightMoved < RIGHT_CLICK_SLOP
			rightDownAt = nil
			if quick and still then
				cancel()
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not active then
			return
		end
		local plot = BuildGhost.Plot()
		if not plot then
			setActive(false)
			return
		end
		if selected and not selected:IsDescendantOf(workspace) then
			selectModel(nil)
		end
		if not UserInputService.MouseEnabled then
			if mode ~= "idle" then
				updateGhost(plot) -- touch moves the cell on tap
			end
			return
		end
		if mode ~= "idle" then
			local x, z = BuildGhost.CellAt(plot, mouseRay())
			if x and z then
				gx, gz = x, z
			end
			updateGhost(plot)
		else
			local over = placedAt(plot, mouseRay())
			if over ~= hovered then
				hovered = over
				hoverBox.Adornee = if over ~= selected then over else nil
				hoverBox.Parent = if over then workspace.CurrentCamera else nil
			end
		end
	end)
end

return BuildMode
