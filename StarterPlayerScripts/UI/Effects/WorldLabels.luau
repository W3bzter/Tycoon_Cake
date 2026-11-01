--!strict
-- Hides the world labels a player switched off in Settings (Config.LabelKinds;
-- player attributes Hide<Kind>Labels, saved by the server):
--   Machines   MachineSign (name / status) and BinLabel (pantry). A broken
--              machine's sign still shows, so a repair is never missed.
--   Cakes      ValueTag (price tags on cakes)
--   Customers  any label on a model in workspace.Customers (bubbles, names) or
--              over a drive-thru car / delivery truck. Anomaly HP bars stay.
-- Only this client's copy is changed (BillboardGui.Enabled is local here).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local WorldLabels = {}

local player = Players.LocalPlayer
local tracked: { [BillboardGui]: string } = {} -- gui -> kind

local function kindOf(gui: BillboardGui): string?
	if gui.Name == "MachineSign" or gui.Name == "BinLabel" then
		return "Machines"
	elseif gui.Name == "ValueTag" then
		return "Cakes"
	elseif gui.Name ~= "HPBar" then
		local customers = workspace:FindFirstChild("Customers")
		local vehicles = workspace:FindFirstChild("Vehicles")
		if (customers and gui:IsDescendantOf(customers)) or (vehicles and gui:IsDescendantOf(vehicles)) then
			return "Customers"
		end
	end
	return nil
end

local function hidden(kind: string): boolean
	return player:GetAttribute(`Hide{kind}Labels`) == true
end

-- Inside a fixed item the server hid (WorldBuilder.SetVisible sets Visible = false).
local function inHiddenItem(gui: BillboardGui): boolean
	local node: Instance? = gui.Parent
	while node and node ~= workspace do
		if node:GetAttribute("Visible") == false then
			return true
		end
		node = node.Parent
	end
	return false
end

-- A broken machine keeps its (red) sign.
local function exempt(gui: BillboardGui): boolean
	local node: Instance? = gui.Parent
	while node and node ~= workspace do
		if node:GetAttribute("Broken") == true then
			return true
		end
		node = node.Parent
	end
	return false
end

-- What the server last wanted for each label (it hides labels of hidden items),
-- so showing labels again never switches on one the server had switched off.
local serverEnabled: { [BillboardGui]: boolean } = {}
local written: { [BillboardGui]: boolean } = {} -- the value this script last set (signals are deferred)

local function apply(gui: BillboardGui)
	local kind = tracked[gui]
	if kind then
		local want = serverEnabled[gui] ~= false and not inHiddenItem(gui) and (not hidden(kind) or exempt(gui))
		if gui.Enabled ~= want then
			written[gui] = want
			gui.Enabled = want
		end
	end
end

local function track(inst: Instance)
	if not inst:IsA("BillboardGui") then
		return
	end
	local kind = kindOf(inst)
	if not kind then
		return
	end
	tracked[inst] = kind
	serverEnabled[inst] = inst.Enabled
	apply(inst)
	inst.AncestryChanged:Connect(function()
		if not inst:IsDescendantOf(workspace) then
			tracked[inst], serverEnabled[inst], written[inst] = nil, nil, nil
		end
	end)
	-- The server switched the label on or off: remember it, then re-apply.
	inst:GetPropertyChangedSignal("Enabled"):Connect(function()
		if written[inst] == nil or inst.Enabled ~= written[inst] then
			serverEnabled[inst] = inst.Enabled
			apply(inst)
		end
	end)
end

local function applyAll()
	for gui in tracked do
		apply(gui)
	end
end

function WorldLabels.Mount()
	workspace.DescendantAdded:Connect(track)
	for _, d in workspace:GetDescendants() do
		track(d)
	end
	for _, kind in Config.LabelKinds do
		player:GetAttributeChangedSignal(`Hide{kind}Labels`):Connect(applyAll)
	end
	-- Machines break and get repaired: re-check now and then.
	task.spawn(function()
		while true do
			task.wait(2)
			applyAll()
		end
	end)
end

return WorldLabels
