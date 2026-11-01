--!strict
-- Server side of the mixing minigame. Using a mixing station starts a session
-- (one per player); the client plays it and reports the share of time it kept
-- the dot in the sweet spot. The server checks the session id, that it was
-- actually played for the full duration (not too early, not too late), clamps
-- the score, turns it into a grade and only then mixes (taking ingredients).
--
-- Limits of the approach: the score is client-reported, so a cheater could
-- claim "Perfect". The timing checks stop instant/spam submissions, and the
-- upside is capped at the Perfect multiplier (x1.5).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local BakingPipeline = require(Services.Baking.BakingPipeline)
local Remotes = require(Services.Core.Remotes)

local MixingGame = {}

type Session = { id: string, station: Model, startedAt: number }

local sessions: { [Player]: Session } = {}
local G = Config.Minigame

function MixingGame.Grade(score: number): string
	for _, entry in G.Grades do
		if score >= entry[2] then
			return entry[1]
		end
	end
	return "Sloppy"
end

function MixingGame.Start(player: Player, station: Model)
	local existing = sessions[player]
	if existing and os.clock() - existing.startedAt < G.Timeout then
		return -- already mixing
	end
	local session = { id = HttpService:GenerateGUID(false), station = station, startedAt = os.clock() }
	sessions[player] = session
	-- The client looks up Config.Minigame.Stations[stationId]: the hand bowl is hard, mixers are easier.
	local stationId = if station:GetAttribute("CatalogId") == "PrepTable" then "PrepTable" else "Mixer"
	Remotes.Get("MixStart"):FireClient(player, session.id, stationId, math.random(1, 1e6))
	task.delay(G.Timeout, function()
		if sessions[player] == session then
			sessions[player] = nil -- abandoned: nothing was taken from the bag
		end
	end)
end

-- Returns (accepted, grade or reason).
function MixingGame.Submit(player: Player, sessionId: any, score: any): (boolean, string)
	local session = sessions[player]
	if not session or typeof(sessionId) ~= "string" or sessionId ~= session.id then
		return false, "no session"
	end
	local elapsed = os.clock() - session.startedAt
	local minTime = G.ReadyTime + G.Duration - 0.35 -- small allowance for latency
	if elapsed < minTime then
		return false, "too early" -- keep the session: a real result may still come
	end
	sessions[player] = nil
	if typeof(score) ~= "number" or score ~= score then -- also rejects NaN
		return false, "bad score"
	end
	local grade = MixingGame.Grade(math.clamp(score, 0, 1))
	if session.station.Parent == nil or session.station:GetAttribute("Visible") ~= true then
		return false, "station gone"
	end
	BakingPipeline.Mix(player, session.station, grade)
	return true, grade
end

function MixingGame.Init()
	BakingPipeline.OnMixRequested = MixingGame.Start
	Remotes.Get("MixSubmit").OnServerEvent:Connect(function(player, sessionId, score)
		MixingGame.Submit(player, sessionId, score)
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

-- Test helper: the active session id for a player (DebugBridge).
function MixingGame.SessionId(player: Player): string?
	local s = sessions[player]
	return s and s.id
end

return MixingGame
