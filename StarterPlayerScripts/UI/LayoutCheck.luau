--!strict
-- Test helper (no runtime use): lists HUD pieces whose on-screen rectangles
-- overlap. Run from the MCP Client view:
--   require(game.Players.LocalPlayer.PlayerScripts.UI.LayoutCheck).Check()
-- Checks the visible top-level frames of BakeryHUD (and the SideBar buttons),
-- skipping full-screen overlays (flashes, confetti) and empty containers.

local Players = game:GetService("Players")

local LayoutCheck = {}

local IGNORE = { Toast = true, DevModeTag = true, DevResetButton = true }

local function rectOf(g: GuiObject): (Vector2, Vector2)
	return g.AbsolutePosition, g.AbsolutePosition + g.AbsoluteSize
end

local function visible(g: GuiObject): boolean
	local node: Instance? = g
	while node and node:IsA("GuiObject") do
		if not node.Visible then
			return false
		end
		node = node.Parent
	end
	return true
end

function LayoutCheck.Check(): { string }
	local screen = Players.LocalPlayer.PlayerGui:FindFirstChild("BakeryHUD") :: ScreenGui
	local viewport = screen.AbsoluteSize
	local pieces: { GuiObject } = {}
	local function consider(g: Instance)
		if not g:IsA("GuiObject") or IGNORE[g.Name] or not visible(g) then
			return
		end
		local size = g.AbsoluteSize
		if size.X < 4 or size.Y < 4 or (size.X > viewport.X * 0.9 and size.Y > viewport.Y * 0.9) then
			return -- empty, or a full-screen overlay
		end
		table.insert(pieces, g)
	end
	for _, child in screen:GetChildren() do
		if child.Name == "SideBar" then
			for _, b in child:GetChildren() do
				consider(b)
			end
		else
			consider(child)
		end
	end
	local overlaps = {}
	for i = 1, #pieces do
		for j = i + 1, #pieces do
			local a0, a1 = rectOf(pieces[i])
			local b0, b1 = rectOf(pieces[j])
			if a0.X < b1.X - 1 and b0.X < a1.X - 1 and a0.Y < b1.Y - 1 and b0.Y < a1.Y - 1 then
				table.insert(overlaps, `{pieces[i].Name} x {pieces[j].Name}`)
			end
		end
	end
	return overlaps
end

return LayoutCheck
