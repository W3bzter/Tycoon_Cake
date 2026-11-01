--!strict
-- Reads/writes a CakeInfo (Shared/Rarity) as attributes on any instance: tools,
-- ovens, display slots. One place so every hop (batter -> oven -> tool -> counter
-- -> customer) carries the same fields. Shared so the client can read held cakes
-- (e.g. the rebirth panel's requirement check).
--
-- Attributes: <typeAttr> (CakeType, or Variant on tools), CakeValue, CakeRarity,
-- Anomaly, Fresh, Quality, CakeTraits ("Glazed,Fluffy"), Mutation.

local Rarity = require(script.Parent:WaitForChild("Rarity"))
local Recipes = require(script.Parent:WaitForChild("Recipes"))

local CakeData = {}

local FIELDS = { "CakeValue", "CakeRarity", "Anomaly", "Fresh", "Quality", "CakeTraits", "Mutation" }

function CakeData.Write(inst: Instance, info: Rarity.CakeInfo, typeAttr: string?)
	inst:SetAttribute(typeAttr or "CakeType", info.Type)
	inst:SetAttribute("CakeValue", info.Value)
	inst:SetAttribute("CakeRarity", info.Rarity)
	inst:SetAttribute("Anomaly", info.Anomaly)
	inst:SetAttribute("Fresh", info.Fresh)
	inst:SetAttribute("Quality", info.Quality)
	inst:SetAttribute("CakeTraits", table.concat(info.Traits or {}, ","))
	inst:SetAttribute("Mutation", info.Mutation)
end

function CakeData.Read(inst: Instance, typeAttr: string?): Rarity.CakeInfo
	local cakeType = (inst:GetAttribute(typeAttr or "CakeType") :: string?) or "Vanilla"
	local cake = Recipes.Cakes[cakeType]
	local traits = {}
	for name in string.gmatch((inst:GetAttribute("CakeTraits") :: string?) or "", "[^,]+") do
		table.insert(traits, name)
	end
	return {
		Type = cakeType,
		Value = (inst:GetAttribute("CakeValue") :: number?) or (cake and cake.Price or 25),
		Rarity = (inst:GetAttribute("CakeRarity") :: number?) or 1,
		Anomaly = inst:GetAttribute("Anomaly") == true,
		Fresh = inst:GetAttribute("Fresh") == true,
		Quality = (inst:GetAttribute("Quality") :: string?) or "Good",
		Traits = traits,
		Mutation = inst:GetAttribute("Mutation") :: string?,
	}
end

function CakeData.Clear(inst: Instance, typeAttr: string?)
	inst:SetAttribute(typeAttr or "CakeType", nil)
	for _, field in FIELDS do
		inst:SetAttribute(field, nil)
	end
end

return CakeData
