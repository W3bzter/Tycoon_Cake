--!strict
-- Floor purchase buttons. Owner-only, debounced, server-validated. Purchases are
-- stored in UnlockedUpgrades and replayed whenever the owner claims a plot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PlotLayout = require(Shared:WaitForChild("PlotLayout"))

local DataManager = require(script.Parent.DataManager)
local PlotManager = require(script.Parent.PlotManager)
local Remotes = require(script.Parent.Remotes)
local WorldBuilder = require(script.Parent.WorldBuilder)

local TycoonButtons = {}

local lastAttempt: { [Player]: number } = {}

local unlockedEvent = Instance.new("BindableEvent")
TycoonButtons.UpgradeUnlocked = unlockedEvent.Event -- (player, plot, upgradeId)

local function playSound(at: BasePart, soundId: string)
	if soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.8
	sound.Parent = at
	sound:Play()
	task.delay(3, sound.Destroy, sound)
end

local function requirementsMet(player: Player, upgrade: PlotLayout.Upgrade): boolean
	for _, id in upgrade.Requires or {} do
		if not DataManager.HasUnlock(player, id) then
			return false
		end
	end
	return true
end

-- Shows exactly the buttons whose prerequisite is owned and that aren't bought yet.
local function refreshButtons(plot: Model, owner: Player?)
	local buttons = plot:FindFirstChild("Buttons") :: Folder
	for _, upgrade in PlotLayout.Upgrades do
		local button = buttons:FindFirstChild(upgrade.Id)
		if button then
			local show = owner ~= nil and not DataManager.HasUnlock(owner, upgrade.Id) and requirementsMet(owner, upgrade)
			WorldBuilder.SetVisible(button, show)
		end
	end
end

local function showItem(plot: Model, upgradeId: string, visible: boolean)
	local item = (plot:FindFirstChild("Items") :: Folder):FindFirstChild(upgradeId)
	if item then
		WorldBuilder.SetVisible(item, visible)
	end
end

local function resetPlot(plot: Model)
	for _, upgrade in PlotLayout.Upgrades do
		showItem(plot, upgrade.Id, false)
	end
	refreshButtons(plot, nil)
end

-- Server-side purchase. Returns true on success (also used by tests via DebugBridge).
function TycoonButtons.TryPurchase(player: Player, plot: Model, upgradeId: string): (boolean, string?)
	if not PlotManager.IsOwner(player, plot) then
		return false, "not owner"
	end
	local upgrade = PlotLayout.Find(upgradeId)
	if not upgrade then
		return false, "unknown upgrade"
	end
	if DataManager.HasUnlock(player, upgradeId) then
		return false, "already owned"
	end
	if not requirementsMet(player, upgrade) then
		return false, "locked"
	end
	if upgrade.Currency == "Gems" then
		if not DataManager.SpendGems(player, upgrade.Price) then
			return false, "insufficient gems"
		end
	elseif not DataManager.SpendCash(player, upgrade.Price) then
		return false, "insufficient cash"
	end

	DataManager.Unlock(player, upgradeId)
	showItem(plot, upgradeId, true)
	refreshButtons(plot, player)
	unlockedEvent:Fire(player, plot, upgradeId)
	return true
end

local function hookButton(plot: Model, button: BasePart)
	local upgradeId = button:GetAttribute("UpgradeId") :: string
	local busy = false

	button.Touched:Connect(function(hit)
		if busy or button:GetAttribute("Visible") ~= true then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or not PlotManager.IsOwner(player, plot) then
			return
		end
		local now = os.clock()
		if now - (lastAttempt[player] or 0) < Config.ButtonCooldown then
			return
		end
		lastAttempt[player] = now

		busy = true
		local ok, reason = TycoonButtons.TryPurchase(player, plot, upgradeId)
		if ok then
			playSound(button, Config.Sounds.Purchase)
		elseif reason == "insufficient cash" or reason == "insufficient gems" then
			local upgrade = PlotLayout.Find(upgradeId)
			local price = upgrade and upgrade.Price or "?"
			playSound(button, Config.Sounds.Denied)
			Remotes.Get("Notify"):FireClient(
				player,
				if reason == "insufficient gems" then `You need 💎 {price} for that!` else `You need ${price} for that!`
			)
		end
		busy = false
	end)
end

function TycoonButtons.Init()
	for _, plot in (workspace:WaitForChild("Plots") :: Folder):GetChildren() do
		local buttons = plot:FindFirstChild("Buttons")
		if plot:IsA("Model") and buttons then
			for _, button in buttons:GetChildren() do
				if button:IsA("BasePart") then
					hookButton(plot, button)
				end
			end
		end
	end

	local function onClaimed(player: Player, plot: Model)
		resetPlot(plot)
		for _, upgrade in PlotLayout.Upgrades do
			if DataManager.HasUnlock(player, upgrade.Id) then
				showItem(plot, upgrade.Id, true)
			end
		end
		refreshButtons(plot, player)
	end

	PlotManager.PlotClaimed:Connect(onClaimed)
	PlotManager.PlotReleased:Connect(resetPlot)
	Players.PlayerRemoving:Connect(function(player)
		lastAttempt[player] = nil
	end)

	-- Plots claimed before this service was initialised.
	for _, player in Players:GetPlayers() do
		local plot = PlotManager.GetPlot(player)
		if plot then
			onClaimed(player, plot)
		end
	end
end

return TycoonButtons
