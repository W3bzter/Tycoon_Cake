--!strict
-- Shared tunables for Anomaly Bakery Tycoon (server and client).
-- Every number lives in a feature part under Shared/ConfigParts; this module
-- merges them so code keeps reading Config.<Name>. Add a new setting to the part
-- for its feature (or create a new part file and add its name to the list below).

local Config: { [string]: any } = {}

local parts = script.Parent:WaitForChild("ConfigParts")
-- Keep this list in sync with the files in ConfigParts.
for _, name in { "Core", "Baking", "Customers", "Automation", "Anomalies", "Economy", "Sounds" } do
	local module = parts:WaitForChild(name)
	if module then
		for key, value in require(module) :: any do
			assert(Config[key] == nil, `Config.{key} is defined in two ConfigParts`)
			Config[key] = value
		end
	end
end

return Config
