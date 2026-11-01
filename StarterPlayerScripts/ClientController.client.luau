-- Client entry point: builds the HUD and wires server RemoteEvents to UI modules.

-- Script Sync makes this a Script with RunContext = Client, which runs both from
-- StarterPlayer.StarterPlayerScripts and from the player's PlayerScripts copy.
-- Only the PlayerScripts copy should run.
if not script:FindFirstAncestorOfClass("PlayerScripts") then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UI = script.Parent:WaitForChild("UI")

local AnomalyAlert = require(UI:WaitForChild("AnomalyAlert"))
local CurrencyDisplay = require(UI:WaitForChild("CurrencyDisplay"))
local Toast = require(UI:WaitForChild("Toast"))

local screen = Instance.new("ScreenGui")
screen.Name = "BakeryHUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true -- lets the anomaly flash cover the whole screen
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = player:WaitForChild("PlayerGui")

CurrencyDisplay.Mount(screen, player)
Toast.Mount(screen)
AnomalyAlert.Mount(screen)

Remotes:WaitForChild("Notify").OnClientEvent:Connect(Toast.Show)
Remotes:WaitForChild("AnomalyStarted").OnClientEvent:Connect(function(name: string, duration: number)
	AnomalyAlert.Show(name, workspace:GetServerTimeNow() + duration)
end)
Remotes:WaitForChild("AnomalyEnded").OnClientEvent:Connect(AnomalyAlert.Hide)

-- Joined mid-anomaly: the server mirrors the active one in attributes.
local active = ReplicatedStorage:GetAttribute("ActiveAnomaly")
local endsAt = ReplicatedStorage:GetAttribute("AnomalyEndsAt")
if active and endsAt then
	AnomalyAlert.Show(active, endsAt)
end
