-- Obsidian Hub Loader
-- Single entry point for executor: loadstrings this file, which pulls QuantumHub.lua
local URL = "https://raw.githubusercontent.com/QuantumXternal/Obsidian-Hub/main/QuantumHub.lua"

local ok, err = pcall(function()
    local src = game:HttpGet(URL, true)
    assert(type(src) == "string" and #src > 1000, "HttpGet returned short/empty body (" .. tostring(#(src or "")) .. " bytes)")
    local fn, loadErr = loadstring(src)
    assert(fn, "loadstring compile failed: " .. tostring(loadErr))
    fn()
end)

if not ok then
    warn("[Obsidian Hub] load failed: " .. tostring(err))
end
