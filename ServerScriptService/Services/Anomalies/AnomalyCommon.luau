--!strict
-- Helpers shared by the anomaly modules in Services/Anomalies.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local PlotLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlotLayout"))

local Services = script:FindFirstAncestor("Services") :: Folder
local DataManager = require(Services.Core.DataManager)
local NPCKit = require(Services.Customers.NPCKit)
local PlotManager = require(Services.Core.PlotManager)
local Remotes = require(Services.Core.Remotes)
local ToolFactory = require(Services.Core.ToolFactory)

local Common = {}

function Common.notify(player: Player, message: string)
	Remotes.Get("Notify"):FireClient(player, message)
end

function Common.ownedPlots(): { Model }
	local plots = {}
	for _, plot in (workspace:WaitForChild("Plots") :: Folder):GetChildren() do
		if plot:IsA("Model") and PlotManager.GetOwner(plot) then
			table.insert(plots, plot)
		end
	end
	return plots
end

-- Yields until `deadline` (os.clock) or until done() returns true.
function Common.waitUntil(deadline: number, done: () -> boolean)
	while os.clock() < deadline and not done() do
		task.wait(0.25)
	end
end

-- Anomaly Shield: each owner with a charge uses one and their plot is skipped.
-- Pass `eligible` to only spend shields on plots this anomaly would hit.
function Common.consumeShields(eligible: ((Model) -> boolean)?): { [Model]: boolean }
	local protected = {}
	for _, plot in Common.ownedPlots() do
		local owner = PlotManager.GetOwner(plot)
		if owner and (eligible == nil or eligible(plot)) and DataManager.UseShield(owner) then
			protected[plot] = true
			Common.notify(owner, "🛡️ Your Anomaly Shield protected your bakery!")
		end
	end
	return protected
end

-- Owned, unprotected plots that pass `filter`.
function Common.targetPlots(protected: { [Model]: boolean }, filter: ((Model) -> boolean)?): { Model }
	local result = {}
	for _, plot in Common.ownedPlots() do
		if not protected[plot] and (filter == nil or filter(plot)) then
			table.insert(result, plot)
		end
	end
	return result
end

-- Plot-local frame: origin = centre of the floor top, +Z faces the street.
function Common.floor(plot: Model): CFrame
	local base = plot.PrimaryPart :: BasePart
	return base.CFrame * CFrame.new(0, base.Size.Y / 2, 0)
end

-- A shown item by fixed upgrade id (plot.Items) or catalog id of a placed one (plot.Placed).
function Common.item(plot: Model, id: string): Model?
	local items = plot:FindFirstChild("Items")
	local item = items and items:FindFirstChild(id) :: Model?
	if not item then
		local placed = plot:FindFirstChild("Placed")
		for _, model in (if placed then placed:GetChildren() else {}) do
			if model:GetAttribute("CatalogId") == id and model:IsA("Model") then
				item = model
				break
			end
		end
	end
	return if item and item:GetAttribute("Visible") == true then item else nil
end

-- Intro cutscene for one plot's owner (focus = what the camera looks at).
function Common.cutscene(name: string, plot: Model, focus: Vector3?)
	local owner = PlotManager.GetOwner(plot)
	if owner then
		Remotes.Get("Cutscene"):FireClient(owner, name, focus, plot.Name)
	end
end

-- Intro cutscene for everyone (global anomalies). nil focus = their own plot.
function Common.cutsceneAll(name: string, focus: Vector3?)
	for _, player in Players:GetPlayers() do
		local plot = PlotManager.GetPlot(player)
		local f = focus
		if not f and plot then
			f = (Common.floor(plot) * CFrame.new(0, 6, -10)).Position
		end
		Remotes.Get("Cutscene"):FireClient(player, name, f, plot and plot.Name)
	end
end

-- Creatures wait while the intro cutscene plays.
function Common.introWait()
	task.wait(Config.Cutscene.Length)
end

-- Screen shake for players within `radius` of `position`.
function Common.shake(position: Vector3, radius: number, intensity: number, duration: number)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - position).Magnitude <= radius then
			Remotes.Get("ScreenShake"):FireClient(player, intensity, duration)
		end
	end
end

function Common.playSound(at: Vector3, soundId: string, speed: number?, volume: number?)
	if soundId == "" then
		return
	end
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(at)
	holder.Parent = workspace
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.PlaybackSpeed = speed or 1
	sound.Volume = volume or 1
	sound.RollOffMaxDistance = 150
	sound.Parent = holder
	sound:Play()
	task.delay(4, holder.Destroy, holder)
end

-- Frying Pan for fighting creatures (one per player).
function Common.givePan(player: Player)
	if ToolFactory.Count(player, "FryingPan") > 0 then
		return
	end
	local tool = ToolFactory.Give(player, "FryingPan")
	if tool then
		tool.Activated:Connect(function()
			NPCKit.PanHit(player)
		end)
	end
end

function Common.givePansToAll()
	for _, player in Players:GetPlayers() do
		Common.givePan(player)
	end
end

function Common.takePans()
	for _, player in Players:GetPlayers() do
		ToolFactory.Take(player, "FryingPan", ToolFactory.Count(player, "FryingPan"))
	end
end

-- Cash/Gems reward + a stat for achievements.
function Common.reward(player: Player, cash: number, gems: number, stat: string?, message: string)
	if cash > 0 then
		cash = DataManager.EarnCash(player, cash)
	end
	if gems > 0 then
		gems = DataManager.EarnGems(player, gems)
	end
	if stat then
		DataManager.AddStat(player, stat, 1)
	end
	local parts = { message }
	if cash > 0 then
		table.insert(parts, `+${cash}`)
	end
	if gems > 0 then
		table.insert(parts, `+💎{gems}`)
	end
	Common.notify(player, table.concat(parts, " "))
end

-- Player-facing name of a machine ("ProductionLine2" -> "Production Line 2").
function Common.displayName(itemId: string): string
	local upgrade = PlotLayout.Find(itemId)
	return if upgrade then upgrade.DisplayName else itemId
end

-- Where a creature enters a plot from the street: just outside the front door.
function Common.streetPoint(plot: Model, x: number?): Vector3
	return (Common.floor(plot) * CFrame.new(x or 0, 0, 46)).Position
end

return Common
