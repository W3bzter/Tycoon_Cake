--!strict
-- Assigns each player the first free plot once their data has loaded, moves
-- their character there, and frees the plot when they leave.

local Players = game:GetService("Players")

local DataManager = require(script.Parent.DataManager)
local Remotes = require(script.Parent.Remotes)

local PlotManager = {}

local plotOf: { [Player]: Model } = {}

local claimedEvent = Instance.new("BindableEvent")
PlotManager.PlotClaimed = claimedEvent.Event -- (player, plot)
local releasedEvent = Instance.new("BindableEvent")
PlotManager.PlotReleased = releasedEvent.Event -- (plot)

local function plotsFolder(): Folder
	return workspace:WaitForChild("Plots") :: Folder
end

local function setSign(plot: Model, text: string)
	local label = plot:FindFirstChild("OwnerLabel", true) :: TextLabel?
	if label then
		label.Text = text
	end
end

local function moveToPlot(player: Player, character: Model)
	local plot = plotOf[player]
	local spawn = plot and plot:FindFirstChild("Spawn") :: BasePart?
	if not spawn then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root then
		character:PivotTo(spawn.CFrame * CFrame.new(0, 4, 0))
	end
end

local function claim(player: Player)
	if plotOf[player] then
		return
	end

	local free: Model? = nil
	for i = 1, #plotsFolder():GetChildren() do
		local plot = plotsFolder():FindFirstChild(`Plot{i}`) :: Model?
		if plot and plot:GetAttribute("OwnerUserId") == nil then
			free = plot
			break
		end
	end

	if not free then
		Remotes.Get("Notify"):FireClient(player, "All bakeries are taken. Feel free to look around!")
		return
	end

	local plot = free :: Model
	plotOf[player] = plot
	plot:SetAttribute("OwnerUserId", player.UserId)
	plot:SetAttribute("OwnerName", player.Name)
	player:SetAttribute("PlotName", plot.Name)
	setSign(plot, `{player.DisplayName}'s Bakery`)

	player.CharacterAdded:Connect(function(character)
		moveToPlot(player, character)
	end)
	if player.Character then
		task.spawn(moveToPlot, player, player.Character)
	end

	claimedEvent:Fire(player, plot)
end

local function release(player: Player)
	local plot = plotOf[player]
	if not plot then
		return
	end
	plotOf[player] = nil
	plot:SetAttribute("OwnerUserId", nil)
	plot:SetAttribute("OwnerName", nil)
	setSign(plot, "Unclaimed Bakery")
	releasedEvent:Fire(plot)
end

function PlotManager.GetPlot(player: Player): Model?
	return plotOf[player]
end

function PlotManager.GetOwner(plot: Model): Player?
	local userId = plot:GetAttribute("OwnerUserId")
	return if userId then Players:GetPlayerByUserId(userId :: number) else nil
end

function PlotManager.IsOwner(player: Player, plot: Model): boolean
	return plotOf[player] == plot
end

function PlotManager.Init()
	DataManager.PlayerLoaded:Connect(claim)
	Players.PlayerRemoving:Connect(release)
	-- Players whose data loaded before this service connected.
	for _, player in Players:GetPlayers() do
		if DataManager.IsLoaded(player) then
			task.spawn(claim, player)
		end
	end
end

return PlotManager
