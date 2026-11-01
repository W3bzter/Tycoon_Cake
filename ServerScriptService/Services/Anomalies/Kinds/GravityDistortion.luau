--!strict
-- Gravity Distortion: world gravity drops (Config.Anomalies.GravityDistortion.GravityScale).

local Common = require(script:FindFirstAncestor("Anomalies").AnomalyCommon)

local savedGravity: number? = nil

return {
	CanRun = function()
		return true
	end,
	Run = function(cfg: any, deadline: number)
		Common.cutsceneAll("GravityDistortion", nil)
		savedGravity = workspace.Gravity
		workspace.Gravity = (savedGravity :: number) * cfg.GravityScale
		Common.waitUntil(deadline, function()
			return false
		end)
	end,
	Cleanup = function()
		if savedGravity then
			workspace.Gravity = savedGravity
			savedGravity = nil
		end
	end,
}
