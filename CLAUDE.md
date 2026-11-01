# MyGame

This is a Roblox game project that uses **Script Sync** to keep the scripts in this folder in sync with Roblox Studio.

## Folder → Studio service mapping

| Folder                  | Studio service                                  |
|-------------------------|-------------------------------------------------|
| `ServerScriptService/`  | `ServerScriptService`                           |
| `ReplicatedStorage/`    | `ReplicatedStorage`                             |
| `StarterPlayerScripts/` | `StarterPlayer.StarterPlayerScripts`            |

Each Studio service is synced via the `MyGame` root folder: in Studio's Script Sync settings, link the services to `MyGame` itself, so each service maps to the top-level folder of the same name. Don't link a service to its own subfolder (e.g. `MyGame/ServerScriptService`). Studio then nests the service inside it (`ServerScriptService/ServerScriptService/`), and scripts don't show up in Studio.

Put server-only scripts in `ServerScriptService`, shared modules/assets used by both server and client in `ReplicatedStorage`, and client LocalScripts in `StarterPlayerScripts`.

## Game: Anomaly Bakery Tycoon

- `ServerScriptService/Main.server.luau` is the only server entry point; it `Init()`s the modules in `ServerScriptService/Services/` in a fixed order. Add new services to its `ORDER` list.
- The world (plots, street, machines, buttons) and all Tools are built from code (`WorldBuilder`, `ToolFactory`), because the place file is not in git. Don't build gameplay parts by hand in Studio.
- Tunables live in `ReplicatedStorage/Shared/Config.luau`; upgrades and their placeholder geometry in `ReplicatedStorage/Shared/PlotLayout.luau`.
- `StarterPlayerScripts/ClientController.client.luau` is the client entry point.

## Notes

- Place files (`*.rbxl`, `*.rbxlx`) and `*.lock` files are git-ignored.
- The Roblox Studio MCP server (`Roblox_Studio`) is available for interacting with the open Studio session.
- Script Sync turns `*.client.luau` into a `Script` with `RunContext = Client`, which runs twice when it's in StarterPlayerScripts (Studio logs a warning about this). Client entry scripts must start with `if not script:FindFirstAncestorOfClass("PlayerScripts") then return end`.
- Testing: `require()` from MCP `execute_luau` gets a separate module copy, not the running one. In Studio playtests, call the running services through `ServerStorage.DebugBridge:Invoke("ServiceName", "Method", ...)` (created by `Main` only when `RunService:IsStudio()`).
- Edits made while a playtest is running don't reach that playtest: stop it, check the change synced, then start again.
