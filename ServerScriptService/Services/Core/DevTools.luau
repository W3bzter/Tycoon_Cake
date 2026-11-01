--!strict
-- Studio-only developer tools. Everything here is gated on RunService:IsStudio()
-- on the server, so none of it can be used in the live game.
--   * Players get the "StudioSession" attribute (the client shows the dev panel).
--   * Remotes.DevResetData: reset your save to a brand-new player.
--     Command-bar alternative during a playtest (Server view):
--       game.ServerStorage.DebugBridge:Invoke("DataManager", "ResetToNew", game.Players:GetPlayers()[1])

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Services = script:FindFirstAncestor("Services") :: Folder
local DataManager = require(Services.Core.DataManager)
local Remotes = require(Services.Core.Remotes)

local DevTools = {}

function DevTools.Init()
	if not RunService:IsStudio() then
		return
	end
	local function mark(player: Player)
		player:SetAttribute("StudioSession", true)
	end
	Players.PlayerAdded:Connect(mark)
	for _, player in Players:GetPlayers() do
		mark(player)
	end

	Remotes.Get("DevResetData").OnServerEvent:Connect(function(player)
		if RunService:IsStudio() then
			DataManager.ResetToNew(player)
			Remotes.Get("Notify"):FireClient(player, "🛠️ Data reset: you're a brand-new player.")
		end
	end)
end

return DevTools
