--!strict
-- Mutation events: every Config.MutationEvents.GapMin..GapMax seconds, one event
-- (weighted) multiplies the bake mutation chance for everyone for Duration
-- seconds (Shared/CakeRolls: BakeContext.EventMult, filled in by Ovens.FinishBake).
-- ReplicatedStorage attributes for clients (UI/HUD/Clock): MutationEventName,
-- MutationEventMult, MutationEventEndsAt. Test: DebugBridge:Invoke("MutationEvents",
-- "Start", "Cosmic Bake").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local Remotes = require(Services.Core.Remotes)

local MutationEvents = {}

local token = 0

local function sting(speed: number)
	local id = Config.Sounds.MutationEvent
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = speed
	s.Volume = 0.9
	s.SoundGroup = SoundService:FindFirstChild("SFX") :: SoundGroup?
	s.Parent = SoundService
	s:Play()
	task.delay(5, s.Destroy, s)
end

local function pick(): any
	local cfg = Config.MutationEvents
	local total = 0
	for _, e in cfg.Events do
		total += e.Weight
	end
	local roll = math.random() * total
	for _, e in cfg.Events do
		roll -= e.Weight
		if roll <= 0 then
			return e
		end
	end
	return cfg.Events[1]
end

function MutationEvents.Active(): number
	return (ReplicatedStorage:GetAttribute("MutationEventMult") :: number?) or 1
end

-- Starts an event now (by name, or a weighted random one). Returns its name.
function MutationEvents.Start(name: string?): string
	local event = pick()
	for _, e in Config.MutationEvents.Events do
		if e.Name == name then
			event = e
		end
	end
	token += 1
	local mine = token
	local duration = Config.MutationEvents.Duration
	ReplicatedStorage:SetAttribute("MutationEventName", event.Name)
	ReplicatedStorage:SetAttribute("MutationEventMult", event.Mult)
	ReplicatedStorage:SetAttribute("MutationEventEndsAt", workspace:GetServerTimeNow() + duration)
	Remotes.Get("Notify"):FireAllClients(`{event.Icon} {string.upper(event.Name)}! Mutations x{event.Mult} for {duration} seconds: bake now!`)
	sting(1 + (event.Mult - 2) * 0.1)
	task.delay(duration, function()
		if mine == token then
			ReplicatedStorage:SetAttribute("MutationEventName", nil)
			ReplicatedStorage:SetAttribute("MutationEventMult", nil)
			ReplicatedStorage:SetAttribute("MutationEventEndsAt", nil)
			Remotes.Get("Notify"):FireAllClients(`{event.Icon} {event.Name} is over.`)
		end
	end)
	return event.Name
end

function MutationEvents.Init()
	task.spawn(function()
		while true do
			local cfg = Config.MutationEvents
			task.wait(math.random(cfg.GapMin, cfg.GapMax))
			MutationEvents.Start()
			task.wait(cfg.Duration)
		end
	end)
end

return MutationEvents
