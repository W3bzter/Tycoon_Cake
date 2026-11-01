--!strict
-- Outlines the nearest interactable machines on the local player's own plot.
-- Roblox renders at most ~31 Highlights at once, so we keep a small budget and
-- create them client-side only.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local MAX_HIGHLIGHTS = 8
local RANGE = 45

local InteractHighlighter = {}

local active: { [Model]: Highlight } = {}

local function makeHighlight(model: Model): Highlight
	local h = Instance.new("Highlight")
	h.Name = "InteractOutline"
	h.Adornee = model
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.OutlineColor = Color3.new(1, 1, 1)
	h.OutlineTransparency = 0
	h.FillColor = Color3.fromRGB(255, 240, 200)
	h.FillTransparency = 0.88
	h.Parent = model
	return h
end

local function update(player: Player)
	local wanted: { [Model]: boolean } = {}
	local plotName = player:GetAttribute("PlotName")
	local plots = workspace:FindFirstChild("Plots")
	local plot = plotName and plots and plots:FindFirstChild(plotName :: string)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if plot and root then
		local candidates = {}
		for _, inst in CollectionService:GetTagged("Interactable") do
			if inst:IsA("Model") and inst:IsDescendantOf(plot) and inst:GetAttribute("Visible") == true then
				local dist = (inst:GetPivot().Position - root.Position).Magnitude
				if dist <= RANGE then
					table.insert(candidates, { model = inst, dist = dist })
				end
			end
		end
		table.sort(candidates, function(a, b)
			return a.dist < b.dist
		end)
		for i = 1, math.min(MAX_HIGHLIGHTS, #candidates) do
			wanted[candidates[i].model] = true
		end
	end

	for model, highlight in active do
		if not wanted[model] or model.Parent == nil then
			highlight:Destroy()
			active[model] = nil
		end
	end
	for model in wanted do
		if not active[model] then
			active[model] = makeHighlight(model)
		end
	end
end

function InteractHighlighter.Mount(player: Player)
	task.spawn(function()
		while true do
			update(player)
			task.wait(0.3)
		end
	end)
end

return InteractHighlighter
