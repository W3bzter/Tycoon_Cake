--!strict
-- Creates ReplicatedStorage.Remotes with one RemoteEvent per name in Config.RemoteNames.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Remotes = {}
local events: { [string]: RemoteEvent } = {}

function Remotes.Init()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end

	for _, name in Config.RemoteNames do
		local remote = folder:FindFirstChild(name) :: RemoteEvent?
		if not remote then
			local created = Instance.new("RemoteEvent")
			created.Name = name
			created.Parent = folder
			remote = created
		end
		events[name] = remote :: RemoteEvent
	end
end

function Remotes.Get(name: string): RemoteEvent
	local remote = events[name]
	assert(remote, `Unknown remote '{name}'`)
	return remote
end

return Remotes
