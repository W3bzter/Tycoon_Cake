-- Single server entry point. Initialises every service in a fixed order so
-- dependencies (Remotes, World, Data) always exist before the systems that use them.

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Services = script.Parent:WaitForChild("Services")

local ORDER = {
	"Remotes",
	"Prompts",
	"LightingSetup",
	"WorldBuilder",
	"DataManager",
	"GamePasses",
	"PlotManager",
	"Inventory",
	"TycoonButtons",
	"BuildModels",
	"BuildService",
	"BuildMigration",
	"BakingPipeline",
	"AutoRoll",
	"MixingGame",
	"DineIn",
	"CustomerAI",
	"AutoProduction",
	"Repairs",
	"Achievements",
	"AnomalyManager",
	"GemShop",
	"Rebirth",
	"RobuxShop",
	"DevTools",
}

-- Services live in feature folders (Core, World, Baking, ...); find them by name.
-- Script Sync may still be creating instances when the server starts, so wait.
local function findModule(name: string): ModuleScript
	local deadline = os.clock() + 10
	while true do
		local module = Services:FindFirstChild(name, true)
		if module and module:IsA("ModuleScript") then
			return module
		end
		assert(os.clock() < deadline, `[Main] service module {name} not found`)
		task.wait(0.1)
	end
end

local loaded: { [string]: any } = {}

for _, name in ORDER do
	local module = require(findModule(name)) :: any
	loaded[name] = module
	if type(module.Init) == "function" then
		module.Init()
	end
end

-- Studio-only test hook: lets MCP/command-bar code call into the *running*
-- service instances (a fresh require() from another context gets a separate copy).
-- Usage: ServerStorage.DebugBridge:Invoke("DataManager", "AddCash", player, 100)
if RunService:IsStudio() then
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "DebugBridge"
	bridge.OnInvoke = function(serviceName: string, method: string, ...)
		local service = loaded[serviceName]
		if not service then
			-- Helper modules without Init (Assets, ToolFactory, Style...) aren't in ORDER.
			local module = Services:FindFirstChild(serviceName, true)
			service = module and module:IsA("ModuleScript") and (require(module) :: any)
		end
		assert(service, `DebugBridge: unknown service {serviceName}`)
		local fn = service[method]
		assert(type(fn) == "function", `DebugBridge: {serviceName}.{method} is not a function`)
		return fn(...)
	end
	bridge.Parent = ServerStorage
end

print("[Main] All services initialised")
