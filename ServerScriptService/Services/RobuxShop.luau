--!strict
-- Robux developer products (Gem packs, Cash packs), configured in Config.Products.
-- There are no paid random items anywhere: every product grants a fixed amount.
--
-- ProcessReceipt, done carefully:
--   1. The buyer must be in this server with their data loaded; otherwise
--      NotProcessedYet (Roblox retries later, e.g. when they rejoin).
--   2. If the receipt ID is already in the player's saved Receipts list, it was
--      granted before: return PurchaseGranted without granting again.
--   3. Grant into the session and record the receipt ID, then save with
--      UpdateAsync. Only if that save succeeds do we return PurchaseGranted.
--      If it fails, the grant and the receipt are rolled back and we return
--      NotProcessedYet so Roblox retries.
-- The same receipt can't be processed twice at once (in-flight guard).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DataManager = require(script.Parent.DataManager)
local Remotes = require(script.Parent.Remotes)

local RobuxShop = {}

local inFlight: { [string]: boolean } = {}

local testProductsRef: { any } -- set below (Studio-only test products)

local function productFor(productId: number)
	if productId == 0 then
		return nil
	end
	for _, product in Config.Products do
		if product.Id == productId then
			return product
		end
	end
	for _, product in testProductsRef or {} do
		if product.Id == productId then
			return product
		end
	end
	return nil
end

local function grant(player: Player, product: any, sign: number)
	if product.Kind == "Gems" then
		DataManager.AddGems(player, sign * product.Amount)
	elseif product.Kind == "Cash" then
		DataManager.AddCash(player, sign * product.Amount)
	end
end

function RobuxShop.ProcessReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local receiptId = tostring(receiptInfo.PurchaseId)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	local product = productFor(receiptInfo.ProductId)
	if not product then
		warn(`[RobuxShop] Unknown product {receiptInfo.ProductId}; check Config.Products IDs.`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not player or not DataManager.IsLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataManager.Get(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if table.find(data.Receipts, receiptId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted earlier
	end
	if inFlight[receiptId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	inFlight[receiptId] = true

	grant(player, product, 1)
	table.insert(data.Receipts, receiptId)
	while #data.Receipts > Config.ReceiptHistoryLimit do
		table.remove(data.Receipts, 1)
	end

	local saved = DataManager.Save(player)
	inFlight[receiptId] = nil
	if not saved then
		-- Roll back so the retry doesn't double-grant, and let Roblox retry.
		grant(player, product, -1)
		local index = table.find(data.Receipts, receiptId)
		if index then
			table.remove(data.Receipts, index)
		end
		warn(`[RobuxShop] Save failed for receipt {receiptId}; will retry.`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	Remotes.Get("Notify"):FireClient(player, `Thank you! {product.Label} added 💖`)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Studio-only test hook: register a fake product so ProcessReceipt can be
-- exercised before real product IDs exist.
local testProducts: { any } = {}
testProductsRef = testProducts
function RobuxShop.AddTestProduct(id: number, kind: string, amount: number): boolean
	if not game:GetService("RunService"):IsStudio() then
		return false
	end
	table.insert(testProducts, { Key = "Test" .. id, Id = id, Kind = kind, Amount = amount, Label = `TEST {amount} {kind}` })
	return true
end

function RobuxShop.Init()
	MarketplaceService.ProcessReceipt = RobuxShop.ProcessReceipt
end

return RobuxShop
