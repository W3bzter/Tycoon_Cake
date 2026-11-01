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
- **Upgrades** (`ReplicatedStorage/Shared/PlotLayout.luau`): metadata only (Id, Tier, Category, Price, Currency, Requires list, ReplacedBy, Effects, button position). Plot-local coordinates; the file header has the floor plan. Chained upgrades reuse one button spot. Progression: Tier 0 hand tools (Pantry, Mixing Bowl `PrepTable`, `BasicOven`) → Tier 1 manual machines, which replace their hand tool via `ReplacedBy` (replaced items/buttons stay hidden and can't be bought) → Tier 4-5 automation. A new plot shows only the floor, spawn pad, owner tag and the Pantry button.
- **Geometry** (`Services/ItemBuilders.luau`): one builder per upgrade Id, using the **`Style`** toolkit (pastel palette, `RoundedBox`, billboards, `MachineSign`, street props). Keep the part names other services look up: `Crate`/`Bins`, `Body`, `Door`, `Counter`, `Hopper`, `Panel`, `StorageSlots`.
- **Labels**: every BillboardGui is `AlwaysOnTop`, `LightInfluence = 0`, with a short `MaxDistance` (`Style.Billboard` does this by default). `MachineSign`'s `lift` keeps front-row (automation) signs low and back-wall signs high so they never line up on screen; after adding labels, rerun the projected-overlap check (see the Phase 1 commit). Always-on-top billboards don't appear in MCP screenshots, but they do render in-game.
- **Effects** (`Services/PlotStats.luau`): totals upgrade `Effects`, the Gem boost and the levelled Gem upgrades into BakeTime, CustomerRate, SalePrice (multipliers) and MixBatch, VIPChance, StorageSlots (additive). Add a new effect by adding it here and reading it where it applies.
- **Recipes** (`ReplicatedStorage/Shared/Recipes.luau`): ingredients, cakes, base prices, unlock upgrade Ids.
- **Rarity & value** (`ReplicatedStorage/Shared/Rarity.luau`): 6 rarities (colour, glow, value mult, odds), 4 traits, mix-quality multipliers, Luck odds shift, and `MakeCake` (value = recipe price × average ingredient factor × mix quality). Shared so the client shows the same odds/values as the server.
- **Ingredient Bag** (`Services/Inventory.luau`): saved per player (`PlayerData.Bag`). A free roll at the pantry adds one of every ingredient the unlocked recipes use. Mixing takes from the bag (★ pinned first, then most valuable, for the chosen `MixRecipe` or the best one). Rolls are never sold for Robux or Gems.
- **Baking** (`Services/BakingPipeline.luau`): pantry roll, mixing stations, ovens, display counters. Batter/cakes carry a `CakeInfo` (type, value, rarity, Anomaly, Fresh, quality) as tool/oven/slot attributes; customers pay the cake's value. Anything with `IsOven` is an oven for Overheat Crisis.
- **Mixing minigame** (`Services/MixingGame.luau` + `StarterPlayerScripts/UI/MixGame.luau`): a server-owned session per mix; the client reports the share of time inside the sweet spot; the server checks session id/timing and grades it (Perfect/Great/Good/Sloppy). Ingredients are only taken when a valid result arrives. Automation always mixes "Good".
- **Automation** (`Services/AutoProduction.luau`): production lines ticked every 0.5s. Line 1 is built step by step (each step usable alone); lines 2 and 3 are self-contained units. Lines roll their own ingredients. Automated ovens are tagged `IsOven` + `IsAutoOven`.
- **Customers** (`Services/CustomerAI.luau` + `Services/AvatarService.luau`): per-plot spawn timers. NPCs wear the owner's friends' avatars (fallback: other players, then a colour-only default), want a cake, tip, can be VIPs. Mimics prefer Anomaly-touched cakes.
- **Gems**: earned in `AnomalyManager` (extinguish, stop Mimic) and `CustomerAI` (VIP tips, Epic+ cake sales, `Config.RareCakeGems`). Spent on gem-priced plot upgrades (`Currency = "Gems"`), consumables and levelled upgrades (Income, Baking Speed, Luck; `Config.GemUpgrades`) in `Services/GemShop.luau` via the `BuyGemItem` remote. **Luck is gated by PolicyService** (`ArePaidRandomItemsRestricted`, fails closed): hidden, unbuyable and 0 for restricted players.
- **Robux shop** (`Services/RobuxShop.luau`): developer products in `Config.Products` (fixed Gem/Cash amounts, never random; ID 0 = not set up). `ProcessReceipt` dedupes by receipt ID saved in `PlayerData.Receipts`, and returns `PurchaseGranted` only after `DataManager.Save` succeeds (otherwise it rolls back and returns `NotProcessedYet`). Keep it the only place that sets `MarketplaceService.ProcessReceipt`.
- **Player data** (`Services/DataManager.luau`): Cash, Gems, UnlockedUpgrades, ShieldCharges, BoostEndsAt, Stats, Bag, NextItemId, MixRecipe, GemUpgrades, Receipts. Add new fields to `TEMPLATE`; `reconcile()` fills them in for old saves.

### DevMode and Studio tools
- `Config.DevMode = true` (set `false` to disable): only when `RunService:IsStudio()`, your Cash/Gems are set to `Config.DevModeAmount` on join and the save key is `Dev_<UserId>` instead of `Player_<UserId>`, so the real save (shared with the live game) is never touched. A "DEV MODE" tag shows on the HUD.
- Studio-only "🔄 Reset my data" HUD button (`Services/DevTools.luau`) resets the current save key to a brand-new player and rebuilds the plot. With DevMode off it resets your real save. Command-bar equivalent is in the DevTools header.

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
