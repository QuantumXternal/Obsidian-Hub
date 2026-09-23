-- Delta smoke test: run this FIRST in Delta before the hub.
-- If all 4 prints appear, Delta basics work and the problem is the hub file/raw.
warn("[Smoke] 1: script running")

local okHttp, body = pcall(function()
    return game:HttpGet("https://raw.githubusercontent.com/QuantumXternal/Obsidian-Hub/main/QuantumHub.lua", true)
end)
warn("[Smoke] 2: HttpGet ok=" .. tostring(okHttp) .. " bytes=" .. tostring(body and #body or 0))

local parent = nil
pcall(function()
    if typeof(gethui) == "function" then
        parent = gethui()
    end
end)
if not parent then
    parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui", 10)
end
warn("[Smoke] 3: gui parent=" .. tostring(parent and parent:GetFullName() or "NIL"))

local okGui = pcall(function()
    local g = Instance.new("ScreenGui")
    g.Name = "DeltaSmoke"
    local f = Instance.new("TextLabel")
    f.Size = UDim2.new(0, 200, 0, 50)
    f.Position = UDim2.new(0.5, -100, 0.5, -25)
    f.Text = "DELTA SMOKE OK"
    f.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    f.Parent = g
    g.Parent = parent
    task.delay(5, function()
        pcall(function()
            g:Destroy()
        end)
    end)
end)
warn("[Smoke] 4: gui draw ok=" .. tostring(okGui))
warn("[Smoke] done - if you see a green label, Delta is fine")
