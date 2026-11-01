--!strict
-- One-time conversion of saves from before placement (PlayerData.Build.Migrated).
-- Equipment the player had bought is placed where it used to stand; if that spot
-- is no longer allowed it goes into the build inventory instead.
--   mixing station: the best of BigMixer > Mixer > PrepTable
--   oven: Oven > BasicOven (extra ovens Oven2/Oven3 are kept as Build.LegacyOvens
--         for the oven-slot upgrade)
--   counters: DisplayCounter (+ DisplayCounter2 at its old spot)
--   Plants -> 4 potted plants, Seating -> 4 café tables (their old spots)
--   CakeCharm -> inventory
-- Second pass (PlayerData.Build.MigratedShop), when the floor buttons went away:
--   Pantry (IngredientCrate), Street Sign, Radio Ad -> placed at their old spots
-- Phase 4 (one oven with racks): each old extra oven (Build.LegacyOvens, from
--   Oven2/Oven3) becomes a free Oven Rack upgrade (OvenRack2, OvenRack3).

local Services = script:FindFirstAncestor("Services") :: Folder
local BuildModels = require(Services.Build.BuildModels)
local BuildService = require(Services.Build.BuildService)
local DataManager = require(Services.Core.DataManager)

local BuildMigration = {}

local OLD_PLANT_SPOTS = { { -10, 27 }, { 10, 27 }, { -36, -2 }, { 36, -8 } }
local OLD_TABLE_SPOTS = { { -28, 6 }, { -16, 6 }, { -28, 16 }, { -16, 16 } }

local SHOP_ITEMS = { "IngredientCrate", "StreetSign", "RadioAd" } -- were fixed floor-button items

local function convertLegacyOvens(player: Player, b: any)
	for i = 1, math.min(b.LegacyOvens or 0, 2) do
		DataManager.Unlock(player, `OvenRack{i + 1}`)
	end
	b.LegacyOvens = 0
end

local function migrate(player: Player, plot: Model)
	local data = DataManager.Get(player)
	local b = data and data.Build
	if not data or not b or (b.Migrated and b.MigratedShop and (b.LegacyOvens or 0) == 0) then
		return
	end
	local has = function(id: string)
		return data.UnlockedUpgrades[id] == true
	end
	local function put(id: string, gx: number?, gz: number?)
		local dgx, dgz = BuildModels.Default(id)
		local x, z = gx or dgx, gz or dgz
		if BuildService.CanPlace(player, plot, id, x, z, 0) then
			local uid = tostring(b.NextUid)
			b.NextUid += 1
			b.Placed[uid] = { Id = id, GX = x, GZ = z, Rot = 0 }
		else
			b.Owned[id] = (b.Owned[id] or 0) + 1
		end
	end

	if not b.MigratedShop then
		b.MigratedShop = true
		for _, id in SHOP_ITEMS do
			if has(id) and BuildService.CountOwned(player, id) == 0 then
				put(id)
			end
		end
	end
	if b.Migrated then
		convertLegacyOvens(player, b)
		return
	end
	b.Migrated = true

	local mix = if has("BigMixer") then "BigMixer" elseif has("Mixer") then "Mixer" elseif has("PrepTable") then "PrepTable" else nil
	if mix then
		put(mix)
	end
	local oven = if has("Oven") then "Oven" elseif has("BasicOven") then "BasicOven" else nil
	if oven then
		put(oven)
	end
	b.LegacyOvens = (if has("Oven2") then 1 else 0) + (if has("Oven3") then 1 else 0)
	if has("DisplayCounter") then
		put("DisplayCounter")
	end
	if has("DisplayCounter2") then
		put("DisplayCounter", -10, 16) -- the second counter stood at x -20
	end
	if has("Plants") then
		for _, s in OLD_PLANT_SPOTS do
			put("PottedPlant", s[1] // 2, s[2] // 2)
		end
	end
	if has("Seating") then
		for _, s in OLD_TABLE_SPOTS do
			put("CafeTable", s[1] // 2, s[2] // 2)
		end
	end
	if has("CakeCharm") then
		b.Owned.CakeCharm = (b.Owned.CakeCharm or 0) + 1
	end
	convertLegacyOvens(player, b)
end

function BuildMigration.Init()
	BuildService.Migrate = migrate
end

return BuildMigration
