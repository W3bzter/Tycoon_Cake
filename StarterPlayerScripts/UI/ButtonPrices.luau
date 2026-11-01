--!strict
-- Tints the price on your own plot's purchase buttons red when you can't afford them.

local ButtonPrices = {}

local AFFORD = {
	Cash = Color3.fromRGB(70, 200, 160),
	Gems = Color3.fromRGB(110, 180, 255),
}
local TOO_EXPENSIVE = Color3.fromRGB(235, 70, 90)

local function refresh(player: Player)
	local plotName = player:GetAttribute("PlotName")
	local plots = workspace:FindFirstChild("Plots")
	local plot = plotName and plots and plots:FindFirstChild(plotName :: string)
	local buttons = plot and plot:FindFirstChild("Buttons")
	local leaderstats = player:FindFirstChild("leaderstats")
	if not buttons or not leaderstats then
		return
	end
	for _, pad in buttons:GetChildren() do
		local label = pad:FindFirstChild("Price", true) :: TextLabel?
		local currency = (pad:GetAttribute("Currency") :: string?) or "Cash"
		local price = pad:GetAttribute("Price") :: number?
		local balance = leaderstats:FindFirstChild(currency) :: IntValue?
		if label and price and balance then
			label.TextColor3 = if balance.Value >= price then AFFORD[currency] or AFFORD.Cash else TOO_EXPENSIVE
		end
	end
end

function ButtonPrices.Mount(player: Player)
	task.spawn(function()
		while true do
			refresh(player)
			task.wait(0.5)
		end
	end)
end

return ButtonPrices
