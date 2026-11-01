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
- The world (plots, street, machines, buttons) and all Tools are built from code (`WorldBuilder`, `ItemBuilders`, `ToolFactory`), because the place file is not in git. Don't build gameplay parts by hand in Studio.
- `StarterPlayerScripts/ClientController.local.luau` is the client entry point; HUD pieces live in `StarterPlayerScripts/UI/`.

### Where things live
- **Config** (`ReplicatedStorage/Shared/Config.luau`): every tunable: timers, prices of consumables, automation timings, Gem rewards, animation and sound IDs.
- **Upgrades** (`ReplicatedStorage/Shared/PlotLayout.luau`): metadata only (Id, Tier, Category, Price, Currency, Requires list, Effects, button position). Plot-local coordinates; the file header has the floor plan. Chained upgrades reuse one button spot.
- **Geometry** (`Services/ItemBuilders.luau`): one builder per upgrade Id, using the **`Style`** toolkit (pastel palette, `RoundedBox`, billboards, `MachineSign`, street props). Keep the part names other services look up: `Crate`/`Bins`, `Body`, `Door`, `Counter`, `Hopper`, `Panel`, `StorageSlots`.
- **Effects** (`Services/PlotStats.luau`): totals upgrade `Effects` and the Gem boost into BakeTime, CustomerRate, SalePrice (multipliers) and MixBatch, VIPChance, StorageSlots (additive). Add a new effect by adding it here and reading it where it applies.
- **Recipes** (`ReplicatedStorage/Shared/Recipes.luau`): ingredients, cakes, prices, unlock upgrade Ids. The mixer makes the most valuable unlocked recipe the held ingredients satisfy.
- **Baking** (`Services/BakingPipeline.luau`): pantry bins, mixer, manual ovens, display counters. State is in attributes (`OvenState`, `Blocked`, `CakeType`, slot `HasCake`/`ForSale`/`Reserved`). Anything with `IsOven` is an oven for Overheat Crisis.
- **Automation** (`Services/AutoProduction.luau`): production lines ticked every 0.5s. Line 1 is built step by step (each step usable alone); lines 2 and 3 are self-contained units. Automated ovens are tagged `IsOven` + `IsAutoOven`.
- **Customers** (`Services/CustomerAI.luau` + `Services/AvatarService.luau`): per-plot spawn timers. NPCs wear the owner's friends' avatars (fallback: other players, then a colour-only default), want a cake, tip, can be VIPs.
- **Gems**: earned in `AnomalyManager` (extinguish, stop Mimic) and `CustomerAI` (VIP tips). Spent on gem upgrades (`Currency = "Gems"` in PlotLayout) and consumables in `Services/GemShop.luau` (Shield, Boost) via the `BuyGemItem` remote. Shields are consumed in `AnomalyManager`.
- **Player data** (`Services/DataManager.luau`): Cash, Gems, UnlockedUpgrades, ShieldCharges, BoostEndsAt, Stats. Add new fields to `TEMPLATE`; `reconcile()` fills them in for old saves.

### Art assets live in the place file (press Ctrl+S)
- Ingredient, batter-bowl and cake meshes (made with `generate_mesh`) are templates in `ServerStorage.Assets/{Ingredients,Cakes,Props}`. That's in the place file, **not git**, so save the place (Ctrl+S) after changing them.
- `Services/Assets.luau` lists the expected names, strips any scripts from templates, and falls back to primitive models when a template is missing, so a fresh place or git clone still works.
- `Lighting.Technology` (Future) can't be set by scripts or the MCP; set it in Studio's Properties panel. Everything else about lighting is in `Services/LightingSetup.luau`.

## Notes

- Place files (`*.rbxl`, `*.rbxlx`) and `*.lock` files are git-ignored.
- The Roblox Studio MCP server (`Roblox_Studio`) is available for interacting with the open Studio session.
- Script file types: `*.server.luau` → Script, `*.local.luau` → LocalScript, plain `*.luau` → ModuleScript. Use `.local.luau` for scripts in `StarterPlayerScripts`. `*.client.luau` becomes a `Script` with `RunContext = Client`, which runs twice when placed in StarterPlayerScripts.
- Testing: `require()` from MCP `execute_luau` gets a separate module copy, not the running one. In Studio playtests, call the running services through `ServerStorage.DebugBridge:Invoke("ServiceName", "Method", ...)` (created by `Main` only when `RunService:IsStudio()`).
- Edits made while a playtest is running don't reach that playtest: stop it, check the change synced, then start again.
