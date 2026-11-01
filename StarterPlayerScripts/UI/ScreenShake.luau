--!strict
-- Camera shake via the local Humanoid's CameraOffset (works with the default
-- camera). Overlapping shakes keep the strongest. Used by roll reveals,
-- explosions (Remotes.ScreenShake) and cutscenes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ScreenShake = {}

local intensity = 0
local endsAt = 0
local conn: RBXScriptConnection? = nil

local function humanoid(): Humanoid?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function ScreenShake.Shake(strength: number, duration: number)
	local now = os.clock()
	if now > endsAt or strength >= intensity then
		intensity = strength
	end
	endsAt = math.max(endsAt, now + duration)
	if conn then
		return
	end
	conn = RunService.RenderStepped:Connect(function()
		local h = humanoid()
		local left = endsAt - os.clock()
		if left <= 0 then
			if h then
				h.CameraOffset = Vector3.zero
			end
			intensity = 0
			if conn then
				conn:Disconnect()
				conn = nil
			end
			return
		end
		local s = intensity * math.min(1, left * 2) -- eases out at the end
		if h then
			h.CameraOffset = Vector3.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, (math.random() - 0.5) * s * 0.5)
		end
	end)
end

return ScreenShake
