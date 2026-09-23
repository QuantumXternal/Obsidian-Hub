# Obsidian Hub

Self-contained Roblox hub. No external dependencies at runtime (all UI built with `Instance.new`).

## Files

- `QuantumHub.lua` — the full hub (paste directly into executor, or load via URL).
- `Loader.lua` — tiny loader that fetches `QuantumHub.lua` from `main`.

## Usage (executor one-liner)

Direct (recommended, Option A):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/QuantumXternal/Obsidian-Hub/main/QuantumHub.lua"))()
```

Via loader:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/QuantumXternal/Obsidian-Hub/main/Loader.lua"))()
```

## Notes

- `QuantumHub.lua` ends with `print("[Quantum Hub] Loaded.")`.
- If the raw CDN lags after a push, append a cache-buster: `.../QuantumHub.lua?v=1`.
