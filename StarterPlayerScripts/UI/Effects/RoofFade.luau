--!strict
-- Lets you see into a bakery from above: a plot's roof (parts tagged "RoofPart",
-- World/ShellDetails) fades on this client while the camera is above the
-- ceiling and either your character is inside that building, or you are in
-- Build mode (HUD attribute BuildActive) looking at that plot. From inside, in
-- first person or close up, the roof stays: it is the ceiling.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildRules = require(Shared:WaitForChild("BuildRules"))
local Config = require(Shared:WaitForChild("Config"))

local RoofFade = {}

local player = Players.LocalPlayer
local B = Config.Building
local faded: { [Model]: boolean } = {} -- plot -> roof currently faded

local function plotOf(part: Instance): Model?
	local plots = workspace:FindFirstChild("Plots")
	local node: Instance? = part
	while node and node.Parent ~= plots do
		node = node.Parent
	end
	return node :: Model?
end

-- Plot-local position of `pos` and whether it is inside the building's walls.
local function inside(plot: Model, pos: Vector3): (boolean, Vector3)
	local stage = B.Stages[(plot:GetAttribute("BuildStage") :: number?) or 1] or B.Stages[1]
	local lp = BuildRules.Floor(plot):PointToObjectSpace(pos)
	local ok = math.abs(lp.X) < stage.HalfX and lp.Z > stage.BackZ and lp.Z < B.FacadeZ
	return ok, lp
end

local function setFaded(plot: Model, on: boolean)
	if (faded[plot] == true) == on then
		return
	end
	faded[plot] = on or nil
	for _, part in CollectionService:GetTagged("RoofPart") do
		if part:IsA("BasePart") and part:IsDescendantOf(plot) then
			part.LocalTransparencyModifier = if on then 1 else 0
		end
	end
end

local function update(screen: ScreenGui?)
	local plots = workspace:FindFirstChild("Plots")
	local camera = workspace.CurrentCamera
	if not plots or not camera then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local building = screen ~= nil and screen:GetAttribute("BuildActive") == true
	for _, plot in plots:GetChildren() do
		if plot:IsA("Model") and plot.PrimaryPart then -- (streamed-out plots have none)
			local _, camLocal = inside(plot, camera.CFrame.Position)
			local above = camLocal.Y > B.WallHeight - 0.5
			local want = false
			if above then
				if building then
					want = math.abs(camLocal.X) < Config.PlotSize.X / 2 + 20 and math.abs(camLocal.Z) < Config.PlotSize.Z / 2 + 40
				elseif root then
					local isIn, rootLocal = inside(plot, root.Position)
					want = isIn and rootLocal.Y < B.WallHeight
				end
			end
			setFaded(plot, want)
		end
	end
end

function RoofFade.Mount(screen: ScreenGui?)
	-- Parts streamed in or rebuilt while faded pick up the current state.
	CollectionService:GetInstanceAddedSignal("RoofPart"):Connect(function(part)
		local plot = plotOf(part)
		if plot and faded[plot] and part:IsA("BasePart") then
			part.LocalTransparencyModifier = 1
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.15)
			local ok, err = pcall(update, screen)
			if not ok then
				warn(`[RoofFade] {err}`)
				task.wait(5)
			end
		end
	end)
end

return RoofFade
