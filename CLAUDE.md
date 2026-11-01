# MyGame: Anomaly Bakery Tycoon

Roblox game synced with Studio by **Script Sync**. Read this file first, then open only the modules you need.

## Sync setup
Folders map to Studio services: `ServerScriptService/`, `ReplicatedStorage/`, `StarterPlayerScripts/` (= `StarterPlayer.StarterPlayerScripts`). In Script Sync, link each service to the `MyGame` root (not to its own subfolder, or Studio nests it and scripts don't show).
File types: `*.server.luau` = Script, `*.local.luau` = LocalScript, plain `*.luau` = ModuleScript. Never use `*.client.luau` in StarterPlayerScripts (runs twice).

## Ground rules
- The world, machines, buttons and all Tools are built from code. Don't build gameplay parts in Studio; the place file isn't in git.
- Every tunable number lives in `ReplicatedStorage/Shared/ConfigParts/<Feature>.luau`, read as `Config.<Name>` (`Shared/Config.luau` merges the parts; add a new part's name to its list).
- Keep modules small (about 300 lines max) and in the folder of their feature. Server modules require siblings as `require(Services.<Folder>.<Module>)` with `local Services = script:FindFirstAncestor("Services")`.
- All player actions are validated on the server (owner, distance, unlocked, not broken, rate limits).
- Prompts: create them only with `Prompts.Add(model, part, spec)` and never set `Enabled` yourself. A rule (`Show`) decides visibility; a Broken item shows only its Repair prompt; visible prompts on one part stack via `UIOffset`. Keys: E main, F fill (hold), R recipe, T on/off, G unload, Q repair (`Config.Prompts`). MCP screenshots don't show prompt UI; check `Prompts.Visible(model)` instead.
- Labels: every BillboardGui is `AlwaysOnTop`, `LightInfluence = 0`, short `MaxDistance` (`Style.Billboard` does this). Don't add labels that can stack on screen; reuse the machine's sign.
- Robux: `Core/RobuxShop` is the only place that sets `ProcessReceipt`. Game Passes go through `Core/GamePasses`. Paid things never change random odds; Luck is PolicyService-gated (fails closed).

## Server layout (`ServerScriptService/`)
`Main.server.luau` is the only entry point: it `Init()`s services by name in `ORDER` (add new services there) and, in Studio, creates `ServerStorage.DebugBridge`.

| Folder | Modules |
|---|---|
| `Core/` | `Remotes` (creates `Config.RemoteNames`), `Prompts` (creates every ProximityPrompt and decides when it shows), `DataManager` (load/save, stats, `ApplyReset`), `PlayerDataSchema` (data type + template), `PlotManager` (claim/release plots), `PlotStats` (totals upgrade Effects, Gem upgrades, rebirth bonus), `ToolFactory` (all Tools), `GamePasses`, `RobuxShop`, `DevTools` (Studio reset button), `SmokeTest` |
| `World/` | `WorldBuilder` (plots, street), `ItemBuilders` (one builder per upgrade id), `Style` (palette, shapes, billboards), `Assets` (mesh templates with primitive fallbacks), `LightingSetup`, `TycoonButtons` (fixed-upgrade purchases + showing owned ones; no floor pads any more), `Repairs` (broken machines) |
| `Baking/` | `BakingPipeline` (interactions + setup; re-exports the others), `Ovens` (the one bakery oven: racks `Racks/RackN` each bake a cake, count = `PlotStats.OvenRacks` from Oven Rack upgrades; speed = Oven Speed / Golden Oven; upgrade lights/vents drawn on the oven; `FinishBake` = bake-time rolls), `Display` (counter slots, cakes on them), `Pantry` (bins, roll pop-up), `BakeUtil`, `Inventory` (Ingredient Bag, rolls, auto-delete), `MixingGame` (minigame sessions) |
| `Factory/` | `AutoProduction` (production lines, hoppers, Full Automation auto-load) |
| `Customers/` | `CustomerAI` (spawn, walk, buy), `CustomerLook` (rigs, animations, bubbles), `AvatarService` (friends' avatars), `NPCKit` (walking, gliding, hit system/Frying Pan) |
| `Anomalies/` | `AnomalyManager` (timer, trigger), `AnomalyCommon` (shields, cutscenes, rewards), `Creatures` (Brute/Rat/Gremlin/Phantom models), `Kinds/<Name>` (one module per anomaly: `{CanRun, Run(cfg, deadline), Cleanup}`) |
| `Economy/` | `GemShop` (consumables, Gem upgrades, Cash storage upgrades), `Rebirth`, `Achievements` |
| `Effects/` | `VFX` (public API: ApplyCake/ApplyIngredient/Burst/Pillar), `CakeFX` (per mutation/trait/rarity look), `FxKit` (emitters, shells) |

## Shared (`ReplicatedStorage/Shared/`)
`Config` + `ConfigParts/*`, `PlotLayout` (fixed upgrades: building, recipes, oven upgrades, automation; bought from the Build shop's Upgrades tab), `BuildCatalog` (placeable items), `BuildRules` (grid placement rules), `Recipes`, `Rarity` (tiers, ingredient traits, MakeCake; re-exports `CakeRolls`), `CakeRolls` (cake traits, mutations, RollBake), `CakeData` (CakeInfo ⇄ attributes), `RebirthDefs`, `Achievements` (definitions).

## Client (`StarterPlayerScripts/`)
`ClientController.local.luau` mounts everything and wires remotes. `UI/HUD/` (currency, toasts, highlighter, anomaly banner, recipe preview), `UI/Panels/` (Bag + auto-delete, Shop, Achievements, Rebirth, MixGame), `UI/Effects/` (RollReveal, Cutscene, WorldFX tag animations, ScreenShake), `UI/Hotbar/` (custom hotbar replacing Roblox's backpack bar: `Hotbar` slots/keys 1-9/overflow grid, `ItemIcon` 3D ViewportFrame icons + rarity look, `Tooltip`), `UI/Build/` (Build mode, B key: `BuildMode` state + input, `BuildGhost` ghost preview/grid/no-build overlay using `Shared/BuildRules` + the plot's `BuildReserved` attribute, `BuildMenu` shop panel (Kitchen / Decor / Upgrades tabs) + action bar, `BuildRows` shop rows + widgets). Build mode hides ProximityPrompts (`ProximityPromptService.Enabled`) because R/Q/X double as build keys.

## Remotes (`Config.RemoteNames`)
Server→client: `Notify`, `BuildSync`, `AnomalyStarted/Ended`, `Cutscene`, `ScreenShake`, `RollResult`, `BagUpdate`, `MixStart`, `AchievementSync/Unlocked`.
Client→server: `BuildAction`, `BagAction`, `Settings`, `MixSubmit`, `BuyGemItem`, `ShopAction`, `GamePassPrompt`, `Rebirth`, `DevResetData` (Studio).

## Player data (`Core/PlayerDataSchema`)
Cash, Gems, UnlockedUpgrades, ShieldCharges, BoostEndsAt, Stats (lifetime counters; achievements watch them), Bag, NextItemId, MixRecipe, GemUpgrades, Receipts, Settings (auto-delete), Storage, LinesEnabled, LineRecipes, Hoppers, Rebirths, Achievements, Broken. New field = add it to the schema; `reconcile()` fills old saves.

## Key flows
- Cake value: ingredients (rarity × traits) → mix grade → bake rolls (cake traits, mutation) → `PlotStats.SalePrice` when sold.
- Every bake ends in `Ovens.FinishBake` (fires `Baked`). Stats go through `DataManager.AddStat/MaxStat` → `StatChanged` → achievements.
- Fixed upgrades live in `plot.Items` (by upgrade id); placed items in `plot.Placed` (`<Id>_<uid>`, attributes `CatalogId`, `Kind`, `Uid`). Find machines with `BakeUtil.findMachine(plot, idOrName)`. `Broken`, `Visible`, `IsOven` are attributes.
- Building size: `Config.Building` (ConfigParts/Build). Walls, floor, fence, entrance, deck and placement bounds all read it; don't hard-code building edges.

## Testing
- Stop the playtest, let Script Sync push the edits, start again (edits never reach a running test).
- Smoke test (Server view): `game.ServerStorage.DebugBridge:Invoke("SmokeTest", "Run", game.Players:GetPlayers()[1], true)` → OK/FAIL per step plus logged errors. It resets the dev save. Update its steps when an API changes.
- Call running services via `DebugBridge:Invoke("<Module>", "<Function>", ...)`; it finds any module by name. Tables returned through it are copies. `require()` from MCP gets a separate module copy.
- `Config.DevMode` (Studio only): Cash/Gems top-up and a separate `Dev_<UserId>` save key. HUD "Reset my data" button (Studio only).
- MCP screenshots don't show particles or always-on-top billboards.
- Art meshes live in `ServerStorage.Assets` in the place file (not git): press Ctrl+S after changing them. `Lighting.Technology` must be set in Studio by hand.
