--!strict
-- Picks who a customer "is": one of the plot owner's Roblox friends, falling
-- back to other players in the server (and their friends), then to a styled
-- default look. All web calls are pcall-wrapped, retried and cached.

local Players = game:GetService("Players")

local PlotManager = require(script.Parent.PlotManager)

local AvatarService = {}

export type Visitor = {
	UserId: number?,
	DisplayName: string,
	Description: HumanoidDescription,
}

type FriendEntry = { Id: number, DisplayName: string }

local FRIEND_TTL = 600 -- seconds
local MAX_FRIENDS = 50
local DESCRIPTION_TIMEOUT = 3 -- seconds before falling back to a default look

local friendCache: { [number]: { at: number, list: { FriendEntry } } } = {}
local descriptionCache: { [number]: HumanoidDescription } = {}
local pendingDescriptions: { [number]: boolean } = {}

local function retry<T>(attempts: number, fn: () -> T): (boolean, T?)
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt < attempts then
			task.wait(attempt)
		end
	end
	return false, nil
end

function AvatarService.GetFriends(userId: number): { FriendEntry }
	local cached = friendCache[userId]
	if cached and os.clock() - cached.at < FRIEND_TTL then
		return cached.list
	end
	local list: { FriendEntry } = {}
	local ok = retry(2, function()
		local pages = Players:GetFriendsAsync(userId)
		while #list < MAX_FRIENDS do
			for _, entry in pages:GetCurrentPage() do
				table.insert(list, { Id = entry.Id, DisplayName = entry.DisplayName or entry.Username })
				if #list >= MAX_FRIENDS then
					break
				end
			end
			if pages.IsFinished or #list >= MAX_FRIENDS then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
		return true
	end)
	if not ok then
		list = {}
	end
	friendCache[userId] = { at = os.clock(), list = list }
	return list
end

-- Cached avatar description, or nil if it isn't available within the timeout.
-- A slow fetch keeps running in the background and fills the cache for next time.
function AvatarService.GetDescription(userId: number): HumanoidDescription?
	local cached = descriptionCache[userId]
	if cached then
		return cached:Clone()
	end
	if not pendingDescriptions[userId] then
		pendingDescriptions[userId] = true
		task.spawn(function()
			local ok, description = retry(2, function()
				return Players:GetHumanoidDescriptionFromUserId(userId)
			end)
			if ok and description then
				descriptionCache[userId] = description :: HumanoidDescription
			end
			pendingDescriptions[userId] = nil
		end)
	end
	local deadline = os.clock() + DESCRIPTION_TIMEOUT
	while not descriptionCache[userId] and pendingDescriptions[userId] and os.clock() < deadline do
		task.wait(0.1)
	end
	local result = descriptionCache[userId]
	return result and result:Clone()
end

local PASTELS = {
	Color3.fromRGB(255, 205, 180),
	Color3.fromRGB(240, 190, 150),
	Color3.fromRGB(200, 150, 110),
	Color3.fromRGB(140, 100, 75),
	Color3.fromRGB(255, 225, 200),
}
local OUTFITS = {
	Color3.fromRGB(255, 182, 206),
	Color3.fromRGB(150, 236, 200),
	Color3.fromRGB(140, 205, 255),
	Color3.fromRGB(255, 226, 120),
	Color3.fromRGB(200, 170, 255),
	Color3.fromRGB(255, 196, 150),
}

-- A cheerful default look built only from colours and scales (no asset IDs).
function AvatarService.StyledDefault(): HumanoidDescription
	local d = Instance.new("HumanoidDescription")
	local skin = PASTELS[math.random(#PASTELS)]
	local top = OUTFITS[math.random(#OUTFITS)]
	local bottom = OUTFITS[math.random(#OUTFITS)]
	d.HeadColor = skin
	d.LeftArmColor = skin
	d.RightArmColor = skin
	d.TorsoColor = top
	d.LeftLegColor = bottom
	d.RightLegColor = bottom
	d.HeightScale = 0.9 + math.random() * 0.2
	d.WidthScale = 0.9 + math.random() * 0.2
	d.HeadScale = 1 + math.random() * 0.1
	return d
end

local NAMES = { "Sprinkles", "Muffin", "Biscuit", "Cocoa", "Maple", "Peaches", "Truffle", "Honey", "Mochi", "Pudding" }

-- Chooses a visitor for a customer at `plot`.
function AvatarService.PickVisitor(plot: Model): Visitor
	local owner = PlotManager.GetOwner(plot)
	local pool: { FriendEntry } = {}
	if owner then
		pool = AvatarService.GetFriends(owner.UserId)
	end
	if #pool == 0 then
		-- No friends: other players in the server, then their friends.
		for _, player in Players:GetPlayers() do
			if player ~= owner then
				table.insert(pool, { Id = player.UserId, DisplayName = player.DisplayName })
				for _, friend in AvatarService.GetFriends(player.UserId) do
					table.insert(pool, friend)
				end
			end
		end
	end

	if #pool > 0 then
		local pick = pool[math.random(#pool)]
		local description = AvatarService.GetDescription(pick.Id)
		if description then
			return { UserId = pick.Id, DisplayName = pick.DisplayName, Description = description }
		end
	end
	return { UserId = nil, DisplayName = NAMES[math.random(#NAMES)], Description = AvatarService.StyledDefault() }
end

-- Test helper: summary that crosses the DebugBridge cleanly.
function AvatarService.Describe(plot: Model): string
	local owner = PlotManager.GetOwner(plot)
	local friends = owner and AvatarService.GetFriends(owner.UserId) or {}
	local v = AvatarService.PickVisitor(plot)
	return `friends={#friends} picked={v.DisplayName} userId={v.UserId or "default"}`
end

return AvatarService
