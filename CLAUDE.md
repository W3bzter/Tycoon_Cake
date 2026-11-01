# MyGame

This is a Roblox game project that uses **Script Sync** to keep the scripts in this folder in sync with Roblox Studio.

## Folder → Studio service mapping

| Folder                  | Studio service                                  |
|-------------------------|-------------------------------------------------|
| `ServerScriptService/`  | `ServerScriptService`                           |
| `ReplicatedStorage/`    | `ReplicatedStorage`                             |
| `StarterPlayerScripts/` | `StarterPlayer.StarterPlayerScripts`            |

Put server-only scripts in `ServerScriptService`, shared modules/assets used by both server and client in `ReplicatedStorage`, and client LocalScripts in `StarterPlayerScripts`.

## Notes

- Place files (`*.rbxl`, `*.rbxlx`) and `*.lock` files are git-ignored.
- The Roblox Studio MCP server (`Roblox_Studio`) is available for interacting with the open Studio session.
