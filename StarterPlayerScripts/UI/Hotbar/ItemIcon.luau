--!strict
-- A 3D icon for a Tool: its Handle (and the art welded to it) cloned into a
-- ViewportFrame, framed by its bounding box. Plus the rarity look shared by the
-- hotbar slots, the overflow grid and the tooltip.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CakeData = require(Shared:WaitForChild("CakeData"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local ItemIcon = {}

export type Info = {
	Name: string, -- display name without the value/badges suffix
	Rarity: number?, -- nil for plain tools (pan, extinguisher)
	Cake: Rarity.CakeInfo?,
	Kind: string,
}

-- What the hotbar knows about a tool (cakes and batters carry CakeData).
function ItemIcon.Describe(tool: Tool): Info
	local kind = (tool:GetAttribute("ItemKind") :: string?) or "Tool"
	local isCake = kind == "FinishedCake" or kind == "RawBatter"
	local cake = if isCake then CakeData.Read(tool, "Variant") else nil
	local name = tool.Name:gsub(" %$%d+.*$", "") -- drop "$123 ✨Glazed" from the tool name
	return { Name = name, Rarity = cake and cake.Rarity, Cake = cake, Kind = kind }
end

function ItemIcon.Color(info: Info): Color3
	if info.Rarity then
		return (Rarity.Tiers[info.Rarity] or Rarity.Tiers[1]).Color
	end
	return Color3.fromRGB(255, 170, 200)
end

-- "✨☁️🌌" badges for traits and mutation.
function ItemIcon.Badges(info: Info): string
	if not info.Cake then
		return ""
	end
	local s = ""
	for _, name in info.Cake.Traits or {} do
		local t = Rarity.CakeTraits[name]
		s ..= if t then t.Icon else ""
	end
	if info.Cake.Mutation and Rarity.Mutations[info.Cake.Mutation] then
		s ..= Rarity.Mutations[info.Cake.Mutation].Icon
	end
	return s
end

-- Fills `viewport` with a copy of the tool's handle and returns its camera.
function ItemIcon.Render(viewport: ViewportFrame, tool: Tool): Camera?
	viewport:ClearAllChildren()
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return nil
	end
	local model = Instance.new("Model")
	local copy = handle:Clone()
	for _, d in copy:GetDescendants() do
		-- Viewports don't render effects; drop them (and anything scripted).
		if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("LuaSourceContainer") or d:IsA("Smoke") or d:IsA("Fire") or d:IsA("BillboardGui") then
			d:Destroy()
		end
	end
	copy.Parent = model
	-- Extra parts welded to the handle (e.g. the pan disc, the extinguisher nozzle).
	for _, sibling in tool:GetChildren() do
		if sibling:IsA("BasePart") and sibling ~= handle then
			sibling:Clone().Parent = model
		end
	end
	model.Parent = viewport
	local cf, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local distance = size.Magnitude * 1.25 + 0.5
	camera:SetAttribute("Distance", distance)
	camera:SetAttribute("Focus", cf.Position)
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(distance * 0.6, distance * 0.45, distance * 0.6), cf.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Ambient = Color3.fromRGB(200, 200, 210)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -1.5, -0.5)
	return camera
end

-- Turns an icon camera around its subject (call every frame with elapsed time).
function ItemIcon.Spin(camera: Camera, t: number)
	local focus = camera:GetAttribute("Focus") :: Vector3?
	local distance = camera:GetAttribute("Distance") :: number?
	if focus and distance then
		local a = t * 0.8
		camera.CFrame = CFrame.lookAt(focus + Vector3.new(math.sin(a) * distance * 0.85, distance * 0.45, math.cos(a) * distance * 0.85), focus)
	end
end

return ItemIcon
