--!strict
-- Display counters: slots ("<Counter>_<i>" parts with HasCake/ForSale/Reserved +
-- CakeData attributes), placing/taking/modifying displayed cakes and their
-- rarity ring, value tag and VFX.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CakeData = require(Shared:WaitForChild("CakeData"))
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local Services = script:FindFirstAncestor("Services") :: Folder
local Assets = require(Services.World.Assets)
local BakeUtil = require(Services.Baking.BakeUtil)
local Inventory = require(Services.Baking.Inventory)
local VFX = require(Services.Effects.VFX)


local Display = {}

-- Display counters are placed items (Kind "Counter"); their slots are parts named
-- "<counter model name>_<i>" in the counter's Slots folder.
local function counters(plot: Model): { Model }
	local list = {}
	for _, model in BakeUtil.machines(plot) do
		if model:GetAttribute("Kind") == "Counter" then
			table.insert(list, model)
		end
	end
	return list
end

-- Slots of every usable counter (`includeBroken` also lists broken ones).
local function getSlots(plot: Model, includeBroken: boolean?): { BasePart }
	local slots = {}
	for _, counter in counters(plot) do
		local usable = counter:GetAttribute("Visible") and not counter:GetAttribute("Broken")
		local folder = (includeBroken or usable) and counter:FindFirstChild("Slots")
		if folder then
			for i = 1, Config.DisplaySlots do
				local slot = folder:FindFirstChild(`{counter.Name}_{i}`) :: BasePart?
				if slot then
					table.insert(slots, slot)
				end
			end
		end
	end
	return slots
end
Display.GetSlots = getSlots

local function cakesFolder(plot: Model): Folder
	local folder = plot:FindFirstChild("Cakes") :: Folder?
	if not folder then
		local created = Instance.new("Folder")
		created.Name = "Cakes"
		created.Parent = plot
		folder = created
	end
	return folder :: Folder
end

-- Rarity glow ring + always-on-top "Rare $123" label under/over a displayed cake.
local function decorateCake(model: Model, info: Rarity.CakeInfo)
	local tier = Rarity.Tiers[info.Rarity] or Rarity.Tiers[1]
	local _, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local ring = Instance.new("Part")
	ring.Name = "RarityRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, 2.6, 2.6)
	ring.CFrame = CFrame.new(pivot.Position - Vector3.new(0, size.Y / 2 - 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = tier.Color
	ring.Material = if tier.Glow > 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Parent = model
	if tier.Glow > 0 then
		local light = Instance.new("PointLight")
		light.Color = tier.Color
		light.Range = 4 + tier.Glow * 2
		light.Brightness = tier.Glow
		light.Parent = ring
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "ValueTag"
	gui.Size = UDim2.fromScale(3.6, 1)
	gui.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 0.9, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 30
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(30, 22, 18)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = tier.Color
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	local badges = Rarity.CakeBadges(info)
	label.Text = `{info.Anomaly and "👁️ " or ""}{tier.Name} ${info.Value}{if badges ~= "" then "\n" .. badges else ""}`
	if badges ~= "" then
		gui.Size = UDim2.fromScale(3.6, 1.7)
	end
	if info.Mutation and Rarity.Mutations[info.Mutation] then
		label.TextColor3 = Rarity.Mutations[info.Mutation].Color:Lerp(Color3.new(1, 1, 1), 0.2)
	end
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = tier.Color
	stroke.Thickness = 1.5
	stroke.Parent = label
	gui.Parent = model.PrimaryPart or ring
	VFX.ApplyCake(model, info)
end

local function placeCake(plot: Model, slot: BasePart, info: Rarity.CakeInfo)
	local model = Assets.Clone("Cakes", info.Type)
	model.Name = slot.Name
	model:SetAttribute("CakeType", info.Type)
	Assets.Anchor(model, slot.CFrame * CFrame.new(0, slot.Size.Y / 2, 0), cakesFolder(plot))
	decorateCake(model, info)
	model:SetAttribute("SlotOffset", slot.CFrame:ToObjectSpace(model:GetPivot())) -- for Reposition

	CakeData.Write(slot, info)
	slot:SetAttribute("HasCake", true)
	slot:SetAttribute("ForSale", true)
	slot:SetAttribute("Reserved", false)
end

-- Puts a cake on the first free display slot (used by automation). False if full.
function Display.PlaceCakeInFreeSlot(plot: Model, info: Rarity.CakeInfo): boolean
	for _, slot in getSlots(plot) do
		if not slot:GetAttribute("HasCake") then
			placeCake(plot, slot, info)
			return true
		end
	end
	return false
end

-- A rolled cake of `cakeType` with fixed "Good" quality (automation uses this).
function Display.RollCake(owner: Player, cakeType: string): Rarity.CakeInfo
	local items = {}
	for _, ingredient in Recipes.Cakes[cakeType].Ingredients do
		table.insert(items, Inventory.MakeItem(owner, ingredient))
	end
	return Rarity.MakeCake(cakeType, Recipes.Cakes[cakeType].Price, items, "Good")
end

-- Slots with a cake for sale that no customer has claimed yet.
function Display.GetSaleSlots(plot: Model): { BasePart }
	local result = {}
	for _, slot in getSlots(plot) do
		if slot:GetAttribute("ForSale") and not slot:GetAttribute("Reserved") then
			table.insert(result, slot)
		end
	end
	return result
end

function Display.ReserveSlot(slot: BasePart): boolean
	if slot:GetAttribute("ForSale") and not slot:GetAttribute("Reserved") then
		slot:SetAttribute("Reserved", true)
		return true
	end
	return false
end

function Display.ReleaseSlot(slot: BasePart)
	slot:SetAttribute("Reserved", false)
end

-- Removes the cake from a slot. Returns true and its info if there was one.
function Display.TakeCake(plot: Model, slot: BasePart): (boolean, Rarity.CakeInfo?)
	if not slot:GetAttribute("HasCake") then
		return false, nil
	end
	local info = CakeData.Read(slot)
	local cake = cakesFolder(plot):FindFirstChild(slot.Name)
	if cake then
		cake:Destroy()
	end
	CakeData.Clear(slot)
	slot:SetAttribute("HasCake", false)
	slot:SetAttribute("ForSale", false)
	slot:SetAttribute("Reserved", false)
	return true, info
end

-- Changes a displayed cake in place (Phantom curses, Rats nibble). Skips slots a
-- customer has already claimed. Returns the new info, or nil.
function Display.ModifyCake(plot: Model, slot: BasePart, change: (Rarity.CakeInfo) -> Rarity.CakeInfo): Rarity.CakeInfo?
	if not slot:GetAttribute("HasCake") or slot:GetAttribute("Reserved") then
		return nil
	end
	local ok, info = Display.TakeCake(plot, slot)
	if not ok or not info then
		return nil
	end
	local updated = change(info)
	placeCake(plot, slot, updated)
	return updated
end

Display.Place = placeCake

-- After a counter moved (Build mode): its cakes follow their slots.
function Display.Reposition(plot: Model, counter: Model)
	local slots = counter:FindFirstChild("Slots")
	for _, slot in (if slots then slots:GetChildren() else {}) do
		local cake = slot:IsA("BasePart") and slot:GetAttribute("HasCake") and cakesFolder(plot):FindFirstChild(slot.Name)
		if cake and cake:IsA("Model") then
			local offset = cake:GetAttribute("SlotOffset") :: CFrame?
			if offset then
				cake:PivotTo(slot.CFrame * offset)
			end
		end
	end
end

return Display
