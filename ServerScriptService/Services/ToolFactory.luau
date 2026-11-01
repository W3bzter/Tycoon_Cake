--!strict
-- Builds the game's Tools in code and offers inventory helpers.
-- Every tool carries an "ItemKind" attribute (Ingredient, RawBatter, FinishedCake,
-- FireExtinguisher) and, where relevant, a "Variant" (ingredient name or cake
-- type). The server checks those attributes, never the tool's name.
-- Held items show the art from Assets (meshes in the place file, or fallbacks).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Recipes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Recipes"))
local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))
local CakeData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CakeData"))
local Assets = require(script.Parent.Assets)
local VFX = require(script.Parent.VFX)

local ToolFactory = {}

local function displayName(kind: string, variant: string?): string
	if kind == "Ingredient" and variant and Recipes.Ingredients[variant] then
		local info = Recipes.Ingredients[variant]
		return `{info.Icon} {info.DisplayName}`
	elseif kind == "RawBatter" then
		local cake = variant and Recipes.Cakes[variant]
		return if cake then `🥣 {(cake.DisplayName:gsub(" Cake", ""))} Batter` else "🥣 Batter"
	elseif kind == "FinishedCake" then
		local cake = variant and Recipes.Cakes[variant]
		return if cake then `{cake.Icon} {cake.DisplayName}` else "🍰 Cake"
	elseif kind == "FireExtinguisher" then
		return "🧯 Fire Extinguisher"
	end
	return kind
end

local function artFor(kind: string, variant: string?): Model?
	if kind == "Ingredient" and variant then
		return Assets.Clone("Ingredients", variant)
	elseif kind == "RawBatter" then
		return Assets.Clone("Props", "BatterBowl")
	elseif kind == "FinishedCake" then
		return Assets.Clone("Cakes", variant or "Vanilla")
	end
	return nil
end

function ToolFactory.Make(kind: string, variant: string?): Tool
	local tool = Instance.new("Tool")
	tool.Name = displayName(kind, variant)
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ItemKind", kind)
	if variant then
		tool:SetAttribute("Variant", variant)
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local art = artFor(kind, variant)
	if art then
		handle.Transparency = 1
		Assets.AttachTo(art, handle)
	elseif kind == "FireExtinguisher" then
		handle.Size = Vector3.new(0.8, 2, 0.8)
		handle.Color = Color3.fromRGB(220, 40, 40)
		handle.Material = Enum.Material.SmoothPlastic
		local nozzle = Instance.new("Part")
		nozzle.Name = "Nozzle"
		nozzle.Size = Vector3.new(0.3, 0.3, 0.8)
		nozzle.Color = Color3.fromRGB(40, 40, 40)
		nozzle.CanCollide = false
		nozzle.Massless = true
		nozzle.CFrame = handle.CFrame * CFrame.new(0, 0.9, -0.5)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = nozzle
		weld.Parent = nozzle
		nozzle.Parent = tool
	end

	return tool
end

-- All tools of a kind (optionally a specific variant) in the backpack and hands.
function ToolFactory.Find(player: Player, kind: string, variant: string?): { Tool }
	local found = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in (container :: Instance):GetChildren() do
				if
					child:IsA("Tool")
					and child:GetAttribute("ItemKind") == kind
					and (variant == nil or child:GetAttribute("Variant") == variant)
				then
					table.insert(found, child)
				end
			end
		end
	end
	return found
end

function ToolFactory.Count(player: Player, kind: string, variant: string?): number
	return #ToolFactory.Find(player, kind, variant)
end

function ToolFactory.Give(player: Player, kind: string, variant: string?): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil
	end
	local tool = ToolFactory.Make(kind, variant)
	tool.Parent = backpack
	return tool
end

-- Cake info (Shared/Rarity CakeInfo) travels on batter/cake tools as attributes
-- (Shared/CakeData; the type is the tool's Variant).
function ToolFactory.SetCakeInfo(tool: Tool, info: Rarity.CakeInfo)
	CakeData.Write(tool, info, "Variant")
	local cake = Recipes.Cakes[info.Type]
	local base = if cake then (cake.DisplayName:gsub(" Cake", "")) else info.Type
	local kind = tool:GetAttribute("ItemKind")
	local icon = if kind == "RawBatter" then "🥣" elseif cake then cake.Icon else "🍰"
	local suffix = if kind == "RawBatter" then " Batter" else " Cake"
	local badges = Rarity.CakeBadges(info)
	tool.Name = `{icon} {Rarity.Name(info.Rarity)} {base}{suffix} ${info.Value}{if badges ~= "" then " " .. badges else ""}`
	local handle = tool:FindFirstChild("Handle")
	local art = handle and handle:FindFirstChildWhichIsA("Model")
	if art then
		VFX.ApplyCake(art, info, true)
	end
end

function ToolFactory.GetCakeInfo(tool: Tool): Rarity.CakeInfo
	return CakeData.Read(tool, "Variant")
end

function ToolFactory.GiveCakeItem(player: Player, kind: string, info: Rarity.CakeInfo): Tool?
	local tool = ToolFactory.Give(player, kind, info.Type)
	if tool then
		ToolFactory.SetCakeInfo(tool, info)
	end
	return tool
end

-- Removes `amount` tools of a kind/variant, or nothing if the player has fewer.
function ToolFactory.Take(player: Player, kind: string, amount: number, variant: string?): boolean
	local tools = ToolFactory.Find(player, kind, variant)
	if #tools < amount then
		return false
	end
	for i = 1, amount do
		tools[i]:Destroy()
	end
	return true
end

return ToolFactory
