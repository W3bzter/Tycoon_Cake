--!strict
-- Anomalies come at night only (World/DayNight): the first Config.DayNight.FirstAnomaly
-- seconds after dark, then every AnomalyEvery seconds until morning. Each time it
-- picks one anomaly (weighted, only ones that can currently run) and broadcasts
-- start/end over RemoteEvents. One at a time; one still running at dawn finishes.
--
-- Each anomaly is a module in Services/Anomalies returning
--   { CanRun: () -> boolean, Run: (cfg, deadline) -> () (yields), Cleanup: () -> () }
-- with its settings in Config.Anomalies[name] and its intro shot in
-- Config.Cutscene.Shots[name]. Shared helpers live in AnomalyCommon.
--
-- ReplicatedStorage attributes ActiveAnomaly / AnomalyEndsAt mirror the current
-- anomaly so clients that join mid-anomaly can still show the alert.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Services = script:FindFirstAncestor("Services") :: Folder
local DayNight = require(Services.World.DayNight)
local Remotes = require(Services.Core.Remotes)

type AnomalyDef = {
	CanRun: () -> boolean,
	Run: (cfg: any, deadline: number) -> (),
	Cleanup: () -> (),
}

local AnomalyManager = {}
local defs: { [string]: AnomalyDef } = {}
local running: string? = nil

function AnomalyManager.GetActive(): string?
	return running
end

-- Starts an anomaly now (used by the timer and by tests). Returns false if it can't.
function AnomalyManager.Trigger(name: string, durationOverride: number?): (boolean, string?)
	local def = defs[name]
	local cfg = Config.Anomalies[name]
	if not def or not cfg then
		return false, "unknown anomaly"
	end
	if running then
		return false, `{running} already active`
	end
	if not def.CanRun() then
		return false, "conditions not met"
	end

	running = name
	local duration = durationOverride or cfg.Duration
	local deadline = os.clock() + duration
	ReplicatedStorage:SetAttribute("ActiveAnomaly", name)
	ReplicatedStorage:SetAttribute("AnomalyEndsAt", workspace:GetServerTimeNow() + duration)
	Remotes.Get("AnomalyStarted"):FireAllClients(name, duration)
	print(`[AnomalyManager] {name} started`)

	task.spawn(function()
		local ok, err = pcall(def.Run, cfg, deadline)
		if not ok then
			warn(`[AnomalyManager] {name} errored: {err}`)
		end
		local cleaned, cleanupErr = pcall(def.Cleanup)
		if not cleaned then
			warn(`[AnomalyManager] {name} cleanup errored: {cleanupErr}`)
		end
		running = nil
		ReplicatedStorage:SetAttribute("ActiveAnomaly", nil)
		ReplicatedStorage:SetAttribute("AnomalyEndsAt", nil)
		Remotes.Get("AnomalyEnded"):FireAllClients(name)
		print(`[AnomalyManager] {name} ended`)
	end)
	return true
end

-- `timeLeft`: seconds until morning; anomalies that wouldn't finish by then are
-- skipped (the intro cutscene plays first, so it counts too).
local function pickAnomaly(timeLeft: number?): string?
	local options, total = {}, 0
	for name, def in defs do
		local fits = timeLeft == nil or Config.Anomalies[name].Duration + Config.Cutscene.Length <= timeLeft
		if fits and def.CanRun() then
			local weight = Config.Anomalies[name].Weight
			total += weight
			table.insert(options, { name = name, weight = weight })
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = math.random() * total
	for _, option in options do
		roll -= option.weight
		if roll <= 0 then
			return option.name
		end
	end
	return options[#options].name
end

function AnomalyManager.Init()
	local anomalyFolder = Instance.new("Folder")
	anomalyFolder.Name = "Anomalies" -- creatures, rat holes, ...
	anomalyFolder.Parent = workspace

	for _, module in script.Parent:WaitForChild("Kinds"):GetChildren() do
		if module:IsA("ModuleScript") then
			if Config.Anomalies[module.Name] then
				defs[module.Name] = require(module) :: any
			else
				warn(`[AnomalyManager] {module.Name} has no Config.Anomalies entry; skipped`)
			end
		end
	end

	task.spawn(function()
		local nextAt: number? = nil
		while true do
			task.wait(1)
			if not DayNight.IsNight() then
				nextAt = nil -- daytime: no anomalies
			elseif not nextAt then
				nextAt = os.clock() + Config.DayNight.FirstAnomaly
			elseif os.clock() >= nextAt and not running then
				nextAt = os.clock() + Config.DayNight.AnomalyEvery
				local nightLeft = ((ReplicatedStorage:GetAttribute("PhaseEndsAt") :: number?) or math.huge) - workspace:GetServerTimeNow()
				local name = pickAnomaly(nightLeft) -- never one that runs into the morning
				if name then
					task.spawn(AnomalyManager.Trigger, name)
				end
			end
		end
	end)

	game:BindToClose(function()
		local name = running
		if name then
			pcall(defs[name].Cleanup)
		end
	end)
end

return AnomalyManager
