-- ============================================================
-- Quantum Hub (Self-Contained)
-- Synthesized from local sources only. No external deps.
-- ============================================================

-- 1. Services and LocalPlayer ---------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[Quantum Hub] waiting for LocalPlayer...")
    local t0 = tick()
    while not Players.LocalPlayer and tick() - t0 < 15 do
        task.wait(0.25)
    end
    LocalPlayer = Players.LocalPlayer
    if not LocalPlayer then
        pcall(function()
            LocalPlayer = Players.PlayerAdded:Wait()
        end)
        LocalPlayer = LocalPlayer or Players.LocalPlayer
    end
end
if not LocalPlayer then
    warn("[Quantum Hub] FATAL: no LocalPlayer, aborting")
    return
end
-- Some executors inject before the game finishes loading; wait it out.
pcall(function()
    if not game:IsLoaded() then
        warn("[Quantum Hub] waiting for game load...")
        game.Loaded:Wait()
    end
end)
task.wait(1)
warn("[Quantum Hub] Starting...")

-- Placeholder teleport locations.
-- Base is exact. Others are reasonable placeholders: adjust later.
local TeleportLocations = {
    Base = CFrame.new(514, 71, -368),
    Forest = CFrame.new(1000, 70, -500), -- TODO: adjust placeholder CFrame
    Lake = CFrame.new(1500, 70, -600), -- TODO: adjust placeholder CFrame
    Desert = CFrame.new(2000, 70, -700), -- TODO: adjust placeholder CFrame
    Custom = CFrame.new(0, 0, 0), -- overwritten by Custom X,Y,Z textbox
}

local BASE_CFRAME = CFrame.new(514, 71, -368)

-- 2. Theme (Obsidian Rose) -------------------------------------
local Theme = {
    Background   = Color3.fromRGB(26, 26, 29),
    Panel        = Color3.fromRGB(36, 36, 42),
    Outline      = Color3.fromRGB(60, 60, 70),
    Accent       = Color3.fromRGB(179, 57, 90),
    AccentHover  = Color3.fromRGB(200, 70, 105),
    Text         = Color3.fromRGB(240, 230, 232),
    TextDim      = Color3.fromRGB(160, 150, 155),
    ButtonText   = Color3.fromRGB(255, 255, 255),
}

-- 3. Utility functions ------------------------------------------
local Connections = {}
local function TrackConnection(conn)
    if conn then
        table.insert(Connections, conn)
    end
    return conn
end

local function DisconnectAll()
    for _, conn in ipairs(Connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    table.clear(Connections)
end

local function getRemote(path)
    local ok, result = pcall(function()
        return ReplicatedStorage:FindFirstChild(path, true)
    end)
    if not ok then
        warn("[Quantum Hub] getRemote pcall failed for " .. tostring(path) .. ": " .. tostring(result))
        return nil
    end
    if not result then
        warn("[Quantum Hub] missing remote: " .. tostring(path))
        return nil
    end
    return result
end

local function safeInvoke(remote, ...)
    if not remote then
        warn("[Quantum Hub] safeInvoke called with nil remote")
        return false, nil
    end
    local args = { ... }
    local ok, res = pcall(function()
        return remote:InvokeServer(table.unpack(args))
    end)
    if not ok then
        warn("[Quantum Hub] Invoke failed (" .. tostring(remote:GetFullName()) .. "): " .. tostring(res))
        return false, nil
    end
    return true, res
end

local function safeFire(remote, ...)
    if not remote then
        warn("[Quantum Hub] safeFire called with nil remote")
        return false
    end
    local args = { ... }
    local ok, err = pcall(function()
        remote:FireServer(table.unpack(args))
    end)
    if not ok then
        warn("[Quantum Hub] Fire failed (" .. tostring(remote:GetFullName()) .. "): " .. tostring(err))
        return false
    end
    return true
end

local function MakeDraggable(main, handle)
    local dragging = false
    local dragStart = nil
    local startPos = nil
    pcall(function()
        handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                -- Ignore presses that begin on child buttons/boxes so taps
                -- on close/min (touch or mouse) never start a drag.
                local pos = input.Position
                local onControl = false
                pcall(function()
                    for _, d in ipairs(handle:GetDescendants()) do
                        if d:IsA("TextButton") or d:IsA("TextBox") then
                            local ap, as = d.AbsolutePosition, d.AbsoluteSize
                            if pos.X >= ap.X and pos.X <= ap.X + as.X and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y then
                                onControl = true
                                break
                            end
                        end
                    end
                end)
                if onControl then
                    return
                end
                dragging = true
                dragStart = input.Position
                startPos = main.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
    end)
end

-- Forward declaration for toast (defined in section 8).
local Notify

local function ParseXYZ(str)
    local ok, result = pcall(function()
        local x, y, z = string.match(tostring(str), "([^,]+),([^,]+),([^,]+)")
        if not x or not y or not z then
            return nil
        end
        local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
        if not nx or not ny or not nz then
            return nil
        end
        return CFrame.new(nx, ny, nz)
    end)
    if ok then
        return result
    end
    return nil
end

local function GetCharacter()
    local char = LocalPlayer and LocalPlayer.Character
    return char
end

local function GetHRP()
    local char = GetCharacter()
    if char then
        return char:FindFirstChild("HumanoidRootPart")
    end
    return nil
end

local function GetHumanoid()
    local char = GetCharacter()
    if char then
        return char:FindFirstChildOfClass("Humanoid")
    end
    return nil
end

local function ApplyCorner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = obj
    return c
end

local function ApplyStroke(obj, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.Outline
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = obj
    return s
end

-- Registry of open dropdown overlay lists so opening one (or minimizing
-- the window) closes the rest. Entries are setVisible closures; all calls
-- are pcall-wrapped because the owning GUI may be destroyed (Unload).
local OpenDropdowns = {}

local function CloseAllDropdowns()
    for _, fn in ipairs(OpenDropdowns) do
        pcall(fn, false)
    end
end

-- 4. UI helper builders (Instance.new only) ---------------------

local function styleButton(btn, accent)
    btn.BackgroundColor3 = accent and Theme.Accent or Theme.Panel
    btn.TextColor3 = Theme.ButtonText
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 14
    btn.AutoButtonColor = true
    btn.BorderSizePixel = 0
    ApplyCorner(btn, 8)
    ApplyStroke(btn, Theme.Outline, 1)
end

local function stylePanel(frame)
    frame.BackgroundColor3 = Theme.Panel
    frame.BorderSizePixel = 0
    ApplyCorner(frame, 8)
    ApplyStroke(frame, Theme.Outline, 1)
end

local function createWindow()
    -- Resolve a parent that actually renders in most executors.
    local parentGui = nil
    pcall(function()
        if typeof(gethui) == "function" then
            parentGui = gethui()
        elseif typeof(get_hidden_gui) == "function" then
            parentGui = get_hidden_gui()
        end
    end)
    if not parentGui then
        local ok, pg = pcall(function()
            return LocalPlayer:WaitForChild("PlayerGui", 10)
        end)
        if ok and pg then
            parentGui = pg
        else
            parentGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        end
    end
    if not parentGui then
        warn("[Quantum Hub] FATAL: no GUI parent found")
        return nil
    end

    local old = parentGui:FindFirstChild("QuantumHub")
    if old then
        pcall(function()
            old:Destroy()
        end)
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "QuantumHub"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 999
    gui.IgnoreGuiInset = true
    local okParent, parentErr = pcall(function()
        gui.Parent = parentGui
    end)
    if not okParent then
        warn("[Quantum Hub] FATAL: could not parent GUI: " .. tostring(parentErr))
        return nil
    end

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, 520, 0, 360)
    main.Position = UDim2.new(0.5, 0, 0.5, 0)
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.BackgroundColor3 = Theme.Background
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = gui
    ApplyCorner(main, 8)
    ApplyStroke(main, Theme.Outline, 1)

    -- Responsive scale for small viewports (phones): shrink the whole
    -- window to fit instead of clipping off-screen.
    local uiScale = Instance.new("UIScale")
    uiScale.Parent = main
    local scaleOverride = nil -- nil = auto-fit small viewports
    local function fitScale()
        pcall(function()
            if scaleOverride then
                uiScale.Scale = scaleOverride
                return
            end
            local cam = Workspace.CurrentCamera
            if not cam then
                return
            end
            local vs = cam.ViewportSize
            uiScale.Scale = math.clamp(math.min(vs.X / 640, vs.Y / 460), 0.55, 1)
        end)
    end
    fitScale()
    pcall(function()
        local cam = Workspace.CurrentCamera
        if cam then
            TrackConnection(cam:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale))
        end
    end)

    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.Size = UDim2.new(1, 0, 0, 36)
    topBar.BackgroundColor3 = Theme.Panel
    topBar.BorderSizePixel = 0
    topBar.Parent = main
    ApplyCorner(topBar, 8)
    ApplyStroke(topBar, Theme.Outline, 1)

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -90, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "Quantum Hub"
    title.TextColor3 = Theme.Text
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = topBar

    local minBtn = Instance.new("TextButton")
    minBtn.Name = "Minimize"
    minBtn.Size = UDim2.new(0, 36, 0, 28)
    minBtn.Position = UDim2.new(1, -80, 0.5, -14)
    minBtn.Text = "_"
    minBtn.TextSize = 16
    styleButton(minBtn, false)
    minBtn.Parent = topBar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "Close"
    closeBtn.Size = UDim2.new(0, 36, 0, 28)
    closeBtn.Position = UDim2.new(1, -40, 0.5, -14)
    closeBtn.Text = "X"
    closeBtn.TextSize = 14
    styleButton(closeBtn, true)
    closeBtn.Parent = topBar

    local body = Instance.new("Frame")
    body.Name = "Body"
    body.Position = UDim2.new(0, 0, 0, 38)
    body.Size = UDim2.new(1, 0, 1, -38)
    body.BackgroundTransparency = 1
    body.Parent = main

    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.new(0, 130, 1, -10)
    sidebar.Position = UDim2.new(0, 5, 0, 5)
    sidebar.BackgroundColor3 = Theme.Panel
    sidebar.BorderSizePixel = 0
    sidebar.Parent = body
    ApplyCorner(sidebar, 8)
    ApplyStroke(sidebar, Theme.Outline, 1)

    local sidePad = Instance.new("UIPadding")
    sidePad.PaddingTop = UDim.new(0, 8)
    sidePad.PaddingBottom = UDim.new(0, 8)
    sidePad.PaddingLeft = UDim.new(0, 8)
    sidePad.PaddingRight = UDim.new(0, 8)
    sidePad.Parent = sidebar

    local sideLayout = Instance.new("UIListLayout")
    sideLayout.FillDirection = Enum.FillDirection.Vertical
    sideLayout.Padding = UDim.new(0, 6)
    sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
    sideLayout.Parent = sidebar

    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -145, 1, -10)
    content.Position = UDim2.new(0, 140, 0, 5)
    content.BackgroundColor3 = Theme.Background
    content.BorderSizePixel = 0
    content.Parent = body
    ApplyCorner(content, 8)
    ApplyStroke(content, Theme.Outline, 1)

    MakeDraggable(main, topBar)

    local minimized = false
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        CloseAllDropdowns()
        body.Visible = not minimized
        if minimized then
            main.Size = UDim2.new(0, 520, 0, 36)
        else
            main.Size = UDim2.new(0, 520, 0, 360)
        end
    end)

    closeBtn.MouseButton1Click:Connect(function()
        pcall(function()
            DisconnectAll()
            gui:Destroy()
        end)
    end)

    return {
        Gui = gui,
        Main = main,
        Sidebar = sidebar,
        Content = content,
        SetScaleMode = function(mode)
            if mode == "Small" then
                scaleOverride = 0.55
            elseif mode == "Medium" then
                scaleOverride = 0.75
            elseif mode == "Large" then
                scaleOverride = 1
            else
                scaleOverride = nil
            end
            fitScale()
        end,
    }
end

local TabRegistry = {}

local function createTab(sidebar, content, name, order)
    local btn = Instance.new("TextButton")
    btn.Name = name .. "TabBtn"
    btn.Size = UDim2.new(1, 0, 0, 32)
    btn.Text = name
    btn.LayoutOrder = order or #TabRegistry + 1
    styleButton(btn, false)
    btn.Parent = sidebar

    local panel = Instance.new("ScrollingFrame")
    panel.Name = name .. "Panel"
    panel.Size = UDim2.new(1, -10, 1, -10)
    panel.Position = UDim2.new(0, 5, 0, 5)
    panel.BackgroundColor3 = Theme.Background
    panel.BorderSizePixel = 0
    panel.ScrollBarThickness = 4
    panel.ScrollBarImageColor3 = Theme.Accent
    panel.CanvasSize = UDim2.new(0, 0, 0, 0)
    panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
    panel.Visible = (#TabRegistry == 0)
    panel.Parent = content
    ApplyCorner(panel, 8)

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 8)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = panel

    local entry = { Name = name, Button = btn, Panel = panel }
    table.insert(TabRegistry, entry)

    local function refresh()
        for _, t in ipairs(TabRegistry) do
            local active = (t == entry)
            t.Panel.Visible = active
            t.Button.BackgroundColor3 = active and Theme.Accent or Theme.Panel
        end
    end

    btn.MouseButton1Click:Connect(function()
        for _, t in ipairs(TabRegistry) do
            t.Panel.Visible = (t == entry)
            t.Button.BackgroundColor3 = (t == entry) and Theme.Accent or Theme.Panel
        end
    end)

    -- Highlight first tab by default
    if #TabRegistry == 1 then
        btn.BackgroundColor3 = Theme.Accent
    end

    return panel
end

local function createToggle(parent, name, default, callback)
    local frame = Instance.new("Frame")
    frame.Name = name .. "Toggle"
    frame.Size = UDim2.new(1, 0, 0, 40)
    frame.BackgroundColor3 = Theme.Panel
    frame.BorderSizePixel = 0
    frame.Parent = parent
    ApplyCorner(frame, 8)
    ApplyStroke(frame, Theme.Outline, 1)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -84, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Theme.Text
    label.Font = Enum.Font.Gotham
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local state = default and true or false
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 64, 0, 28)
    btn.Position = UDim2.new(1, -72, 0.5, -14)
    btn.Text = state and "ON" or "OFF"
    btn.BackgroundColor3 = state and Theme.Accent or Theme.Background
    btn.TextColor3 = Theme.ButtonText
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.BorderSizePixel = 0
    btn.Parent = frame
    ApplyCorner(btn, 8)
    ApplyStroke(btn, Theme.Outline, 1)

    local function set(v)
        state = v and true or false
        btn.Text = state and "ON" or "OFF"
        btn.BackgroundColor3 = state and Theme.Accent or Theme.Background
        if callback then
            local ok, err = pcall(callback, state)
            if not ok then
                warn("[Quantum Hub] toggle callback failed (" .. tostring(name) .. "): " .. tostring(err))
            end
        end
    end

    btn.MouseButton1Click:Connect(function()
        set(not state)
    end)

    -- Apply default silently (no callback) so caller wires initial state itself.
    return frame, set
end

local function createCheckbox(parent, name, default, callback)
    local frame = Instance.new("Frame")
    frame.Name = name .. "Checkbox"
    frame.Size = UDim2.new(1, 0, 0, 34)
    frame.BackgroundTransparency = 1
    frame.Parent = parent

    local box = Instance.new("TextButton")
    box.Size = UDim2.new(0, 26, 0, 26)
    box.Position = UDim2.new(0, 2, 0.5, -13)
    box.Text = ""
    box.BackgroundColor3 = Theme.Panel
    box.BorderSizePixel = 0
    box.Parent = frame
    ApplyCorner(box, 8)
    ApplyStroke(box, Theme.Outline, 1)

    local check = Instance.new("TextLabel")
    check.Size = UDim2.new(1, 0, 1, 0)
    check.BackgroundTransparency = 1
    check.Text = default and "X" or ""
    check.TextColor3 = Theme.Accent
    check.Font = Enum.Font.GothamBold
    check.TextSize = 16
    check.Parent = box

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -40, 1, 0)
    label.Position = UDim2.new(0, 34, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Theme.TextDim
    label.Font = Enum.Font.Gotham
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local state = default and true or false
    local function set(v)
        state = v and true or false
        check.Text = state and "X" or ""
        if callback then
            local ok, err = pcall(callback, state)
            if not ok then
                warn("[Quantum Hub] checkbox callback failed (" .. tostring(name) .. "): " .. tostring(err))
            end
        end
    end

    box.MouseButton1Click:Connect(function()
        set(not state)
    end)

    return frame, set
end

local function createSlider(parent, name, min, max, default, callback)
    local frame = Instance.new("Frame")
    frame.Name = name .. "Slider"
    frame.Size = UDim2.new(1, 0, 0, 64)
    frame.BackgroundColor3 = Theme.Panel
    frame.BorderSizePixel = 0
    frame.Parent = parent
    ApplyCorner(frame, 8)
    ApplyStroke(frame, Theme.Outline, 1)

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 6)
    pad.Parent = frame

    local topRow = Instance.new("Frame")
    topRow.Size = UDim2.new(1, 0, 0, 16)
    topRow.BackgroundTransparency = 1
    topRow.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Theme.Text
    label.Font = Enum.Font.Gotham
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = topRow

    local value = default
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Size = UDim2.new(0.3, 0, 1, 0)
    valueLabel.Position = UDim2.new(0.7, 0, 0, 0)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = tostring(default)
    valueLabel.TextColor3 = Theme.TextDim
    valueLabel.Font = Enum.Font.Gotham
    valueLabel.TextSize = 13
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Parent = topRow

    local bar = Instance.new("TextButton")
    bar.Name = "Bar"
    bar.Size = UDim2.new(1, 0, 0, 14)
    bar.Position = UDim2.new(0, 0, 0, 26)
    bar.Text = ""
    bar.BackgroundColor3 = Theme.Background
    bar.BorderSizePixel = 0
    bar.AutoButtonColor = false
    bar.Parent = frame
    ApplyCorner(bar, 8)
    ApplyStroke(bar, Theme.Outline, 1)

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(0.5, 0, 1, 0)
    fill.BackgroundColor3 = Theme.Accent
    fill.BorderSizePixel = 0
    fill.Parent = bar
    ApplyCorner(fill, 8)

    local function apply(v)
        v = math.clamp(tonumber(v) or default, min, max)
        value = v
        local alpha = 0
        if max ~= min then
            alpha = (v - min) / (max - min)
        end
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        if math.abs(v) >= 100 then
            valueLabel.Text = string.format("%.0f", v)
        elseif max <= 1 or (max - min) < 2 then
            valueLabel.Text = string.format("%.2f", v)
        else
            valueLabel.Text = string.format("%.1f", v)
        end
        if callback then
            local ok, err = pcall(callback, v)
            if not ok then
                warn("[Quantum Hub] slider callback failed (" .. tostring(name) .. "): " .. tostring(err))
            end
        end
    end

    local dragging = false
    local function updateFromInput(inputPos)
        local absPos = bar.AbsolutePosition
        local absSize = bar.AbsoluteSize
        if absSize.X <= 0 then
            return
        end
        local alpha = math.clamp((inputPos.X - absPos.X) / absSize.X, 0, 1)
        apply(min + (max - min) * alpha)
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromInput(input.Position)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input.Position)
        end
    end)

    -- Init fill without firing callback
    do
        local alpha = 0
        if max ~= min then
            alpha = (default - min) / (max - min)
        end
        fill.Size = UDim2.new(math.clamp(alpha, 0, 1), 0, 1, 0)
    end

    return frame, apply
end

local function createDropdown(parent, name, options, default, callback)
    local frame = Instance.new("Frame")
    frame.Name = name .. "Dropdown"
    frame.Size = UDim2.new(1, 0, 0, 40)
    frame.BackgroundColor3 = Theme.Panel
    frame.BorderSizePixel = 0
    frame.Parent = parent
    ApplyCorner(frame, 8)
    ApplyStroke(frame, Theme.Outline, 1)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.45, 0, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Theme.Text
    label.Font = Enum.Font.Gotham
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local current = default
    local mainBtn = Instance.new("TextButton")
    mainBtn.Size = UDim2.new(0.5, -10, 0, 28)
    mainBtn.Position = UDim2.new(0.5, 0, 0.5, -14)
    mainBtn.Text = tostring(default) .. " v"
    styleButton(mainBtn, true)
    mainBtn.Parent = frame

    -- The option list lives on the ScreenGui itself (found by walking up),
    -- NOT inside the row frame: ScrollingFrame clipping + sibling ZIndex
    -- is what hid the choices. As a top-level overlay it always renders.
    local rootGui = nil
    pcall(function()
        local node = parent
        while node do
            if node:IsA("ScreenGui") then
                rootGui = node
                break
            end
            node = node.Parent
        end
    end)
    if not rootGui then
        rootGui = parent
    end

    local list = Instance.new("Frame")
    list.Name = name .. "Options"
    list.Size = UDim2.new(0, 180, 0, #options * 32 + 8)
    list.BackgroundColor3 = Theme.Background
    list.BorderSizePixel = 0
    list.Visible = false
    list.ZIndex = 200
    list.Parent = rootGui
    ApplyCorner(list, 8)
    ApplyStroke(list, Theme.Accent, 1)

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 2)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = list

    local listPad = Instance.new("UIPadding")
    listPad.PaddingTop = UDim.new(0, 4)
    listPad.PaddingBottom = UDim.new(0, 4)
    listPad.PaddingLeft = UDim.new(0, 4)
    listPad.PaddingRight = UDim.new(0, 4)
    listPad.Parent = list

    local function setVisible(v)
        local ok = pcall(function()
            if v then
                local ap = mainBtn.AbsolutePosition
                local as = mainBtn.AbsoluteSize
                list.Position = UDim2.fromOffset(ap.X, ap.Y + as.Y + 4)
                list.Size = UDim2.fromOffset(math.max(as.X + 60, 170), #options * 32 + 8)
            end
            list.Visible = v
        end)
        if not ok then
            pcall(function()
                list.Visible = false
            end)
        end
    end
    table.insert(OpenDropdowns, setVisible)

    local function set(v)
        current = v
        mainBtn.Text = tostring(v) .. " v"
        setVisible(false)
        if callback then
            local ok, err = pcall(callback, v)
            if not ok then
                warn("[Quantum Hub] dropdown callback failed (" .. tostring(name) .. "): " .. tostring(err))
            end
        end
    end

    for i, opt in ipairs(options) do
        local ob = Instance.new("TextButton")
        ob.Size = UDim2.new(1, 0, 0, 30)
        ob.LayoutOrder = i
        ob.Text = tostring(opt)
        ob.TextSize = 14
        ob.ZIndex = 201
        styleButton(ob, false)
        ob.Parent = list
        ob.MouseButton1Click:Connect(function()
            set(opt)
        end)
    end

    mainBtn.MouseButton1Click:Connect(function()
        local was = list.Visible
        CloseAllDropdowns()
        setVisible(not was)
    end)

    return frame, set
end

local function createButton(parent, name, callback)
    local btn = Instance.new("TextButton")
    btn.Name = name .. "Button"
    btn.Size = UDim2.new(1, 0, 0, 40)
    btn.Text = name
    styleButton(btn, true)
    btn.Parent = parent
    btn.MouseButton1Click:Connect(function()
        if callback then
            local ok, err = pcall(callback)
            if not ok then
                warn("[Quantum Hub] button callback failed (" .. tostring(name) .. "): " .. tostring(err))
            end
        end
    end)
    btn.MouseEnter:Connect(function()
        btn.BackgroundColor3 = Theme.AccentHover
    end)
    btn.MouseLeave:Connect(function()
        btn.BackgroundColor3 = Theme.Accent
    end)
    return btn
end

local function createTextbox(parent, name, default, callback)
    local frame = Instance.new("Frame")
    frame.Name = name .. "Textbox"
    frame.Size = UDim2.new(1, 0, 0, 40)
    frame.BackgroundColor3 = Theme.Panel
    frame.BorderSizePixel = 0
    frame.Parent = parent
    ApplyCorner(frame, 8)
    ApplyStroke(frame, Theme.Outline, 1)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.4, 0, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Theme.Text
    label.Font = Enum.Font.Gotham
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.55, -10, 0, 28)
    box.Position = UDim2.new(0.45, 0, 0.5, -14)
    box.Text = tostring(default)
    box.PlaceholderText = tostring(default)
    box.BackgroundColor3 = Theme.Background
    box.TextColor3 = Theme.Text
    box.PlaceholderColor3 = Theme.TextDim
    box.Font = Enum.Font.Gotham
    box.TextSize = 13
    box.ClearTextOnFocus = false
    box.BorderSizePixel = 0
    box.Parent = frame
    ApplyCorner(box, 8)
    ApplyStroke(box, Theme.Outline, 1)

    box.FocusLost:Connect(function(enterPressed)
        if callback then
            local ok, err = pcall(callback, box.Text)
            if not ok then
                warn("[Quantum Hub] textbox callback failed (" .. tostring(name) .. "): " .. tostring(err))
            end
        end
    end)

    return frame, box
end

local function SectionLabel(parent, text)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 24)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = Theme.Accent
    l.Font = Enum.Font.GothamBold
    l.TextSize = 14
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

-- 5. Module tables -----------------------------------------------

-- KillAura --------------------------------------------------------
local KillAura = {
    Enabled = false,
    Range = 16.5,
    Priority = "Nearest",
    AttackDelay = 0.1,
    last = 0,
    BatSwing = nil,
    ToolGameplayGuard = nil,
}

function KillAura:CreateSeed()
    local ok, res = pcall(function()
        return ("%*:%*:%*"):format(LocalPlayer.UserId, 100, math.floor(Workspace:GetServerTimeNow() * 1000))
    end)
    if ok and res then
        return res
    end
    return nil
end

function KillAura:EnsureRemotes()
    if not self.BatSwing then
        self.BatSwing = getRemote("RE/BatSwing/Trigger")
    end
    if not self.ToolGameplayGuard then
        local ok, mod = pcall(function()
            local client = ReplicatedStorage:FindFirstChild("Client")
            if not client then
                return nil
            end
            local m = client:FindFirstChild("ToolGameplayGuard")
            if not m then
                return nil
            end
            return require(m)
        end)
        if ok and mod then
            self.ToolGameplayGuard = mod
        else
            warn("[Quantum Hub] KillAura missing ToolGameplayGuard: " .. tostring(mod))
        end
    end
    return self.BatSwing ~= nil
end

function KillAura:CanUseTool()
    local ok, res = pcall(function()
        local c = LocalPlayer.Character
        if not c then
            return false
        end
        local t = c:FindFirstChildOfClass("Tool")
        if not t or t:GetAttribute("ItemType") ~= "Gear" then
            return false
        end
        local h = c:FindFirstChild("HumanoidRootPart")
        if not h then
            return false
        end
        if self.ToolGameplayGuard then
            local insideOk, inside = pcall(function()
                return self.ToolGameplayGuard.IsLocalInsideArena()
            end)
            if insideOk and inside then
                return false
            end
        end
        if Workspace:GetAttribute("Event_MonsterEvent") then
            if h.Position.Z > -268 then
                return true
            end
            return false
        else
            return true
        end
    end)
    if ok then
        return res
    end
    return false
end

function KillAura:GetTarget()
    local ok, res = pcall(function()
        local best = nil
        local bestDist = math.huge
        local bestHealth = math.huge
        local bestMaxHealth = -math.huge
        local bestMax = nil
        local candidates = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LocalPlayer then
                continue
            end
            local char = p.Character
            if not char then
                continue
            end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                continue
            end
            local dist = LocalPlayer:DistanceFromCharacter(hrp.Position)
            if dist and dist <= self.Range then
                if self.Priority == "Nearest" then
                    if dist < bestDist then
                        bestDist = dist
                        best = p
                    end
                elseif self.Priority == "Lowest Health" then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    local hp = hum and hum.Health or math.huge
                    if hp < bestHealth then
                        bestHealth = hp
                        best = p
                    end
                elseif self.Priority == "Highest Health" then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    local hp = hum and hum.Health or -math.huge
                    if hp > bestMaxHealth then
                        bestMaxHealth = hp
                        bestMax = p
                    end
                elseif self.Priority == "Random" then
                    table.insert(candidates, p)
                else
                    if dist < bestDist then
                        bestDist = dist
                        best = p
                    end
                end
            end
        end
        if self.Priority == "Random" and #candidates > 0 then
            return candidates[math.random(1, #candidates)]
        end
        if self.Priority == "Highest Health" then
            return bestMax
        end
        return best
    end)
    if ok then
        return res
    end
    return nil
end

function KillAura:Attack(target)
    if not self.BatSwing then
        return
    end
    local seed = self:CreateSeed()
    if not seed then
        return
    end
    safeFire(self.BatSwing, target, seed)
end

function KillAura:Toggle(state)
    self.Enabled = state and true or false
    if self.Enabled then
        if not self:EnsureRemotes() then
            warn("[Quantum Hub] KillAura enabled but remote missing")
        end
        self.last = tick()
    end
end

function KillAura:Run()
    if not self.Enabled then
        return
    end
    local target = self:GetTarget()
    if target then
        if tick() - self.last >= (self.AttackDelay or 0.1) then
            if self:CanUseTool() then
                self:Attack(target)
                self.last = tick()
            end
        end
    end
end

-- NoKnockback -----------------------------------------------------
local NoKnockback = {
    Enabled = false,
    RigSync = nil,
}

function NoKnockback:Toggle(state)
    self.Enabled = state and true or false
    if self.Enabled then
        local remote = getRemote("RE/RigSync/Refresh")
        if not remote then
            warn("[Quantum Hub] NoKnockback: remote not found")
            return
        end
        self.RigSync = remote
        if not getconnections then
            warn("[Quantum Hub] NoKnockback requires getconnections")
            return
        end
        local ok, conns = pcall(function()
            return getconnections(remote.OnClientEvent)
        end)
        if not ok or not conns then
            warn("[Quantum Hub] NoKnockback failed to get connections: " .. tostring(conns))
            return
        end
        local patched = 0
        pcall(function()
            for _, conn in ipairs(conns) do
                conn:Disconnect()
                patched = patched + 1
            end
        end)
        warn("[Quantum Hub] NoKnockback patched " .. tostring(patched) .. " connections")
        if Notify then
            Notify("NoKnockback: patched " .. tostring(patched))
        end
    else
        warn("[Quantum Hub] NoKnockback disabled: rejoin required to restore knockback")
        if Notify then
            Notify("NoKnockback off: rejoin to restore")
        end
    end
end

-- InstantInteract -------------------------------------------------
local InstantInteract = {
    Enabled = false,
    Conn = nil,
}

function InstantInteract:Toggle(state)
    self.Enabled = state and true or false
    if self.Conn then
        pcall(function()
            self.Conn:Disconnect()
        end)
        self.Conn = nil
    end
    if self.Enabled then
        local ok, conn = pcall(function()
            return ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, player)
                if player == LocalPlayer and tostring(prompt) == "CarryAreaEgg" then
                    pcall(function()
                        prompt.HoldDuration = 0
                    end)
                end
            end)
        end)
        if ok and conn then
            self.Conn = TrackConnection(conn)
        else
            warn("[Quantum Hub] InstantInteract failed to bind: " .. tostring(conn))
        end
    end
end

-- AutoBuy ---------------------------------------------------------
local AutoBuy = {
    Enabled = false,
    BuyTreadmills = true,
    BuyBases = true,
    BuyTrails = true,
    MaxSpend = 1000000,
    BuyInterval = 0.5,
    Treadmills = nil,
    Trails = nil,
    Bases = nil,
    Save = nil,
    TrailRemote = nil,
    TreadmillRemote = nil,
    BaseRemote = nil,
}

function AutoBuy:CanAfford(m, c)
    local ok, res = pcall(function()
        m = tonumber(m)
        c = tonumber(c)
        if not m or not c then
            return false
        end
        return m >= c
    end)
    if ok then
        return res
    end
    return false
end

function AutoBuy:EnsureData()
    if not self.Treadmills then
        pcall(function()
            local data = ReplicatedStorage:FindFirstChild("Data")
            if data then
                local m = data:FindFirstChild("Treadmills")
                if m then
                    self.Treadmills = require(m)
                end
            end
        end)
    end
    if not self.Trails then
        pcall(function()
            local data = ReplicatedStorage:FindFirstChild("Data")
            if data then
                local m = data:FindFirstChild("Trails")
                if m then
                    self.Trails = require(m)
                end
            end
        end)
    end
    if not self.Bases then
        pcall(function()
            local data = ReplicatedStorage:FindFirstChild("Data")
            if data then
                local m = data:FindFirstChild("Bases")
                if m then
                    self.Bases = require(m)
                end
            end
        end)
    end
    if not self.Save then
        pcall(function()
            local shared = ReplicatedStorage:FindFirstChild("Shared")
            if shared then
                local m = shared:FindFirstChild("Save")
                if m then
                    self.Save = require(m)
                end
            end
        end)
    end
    if not self.TrailRemote then
        self.TrailRemote = getRemote("RF/Trailwear/AskPurchase")
    end
    if not self.TreadmillRemote then
        self.TreadmillRemote = getRemote("RF/Treadmill/AskTierRaise")
    end
    if not self.BaseRemote then
        self.BaseRemote = getRemote("RE/Homestead/AskBaseTierRaise")
    end
end

function AutoBuy:GetTreadmills(saveData)
    local out = {}
    local ok, res = pcall(function()
        local list = {}
        local l = saveData.TreadmillUpgradeLevel
        for id, t in pairs(self.Treadmills.Directory) do
            local lvl = self.Treadmills.GetUpgradeLevel(id)
            if lvl and lvl > l and self:CanAfford(saveData.Money, t.Price) and tonumber(t.Price) <= (self.MaxSpend or math.huge) then
                table.insert(list, id)
            end
        end
        return list
    end)
    if ok and res then
        out = res
    end
    return out
end

function AutoBuy:GetTrails(saveData)
    local out = {}
    local ok, res = pcall(function()
        local list = {}
        for _, trial in pairs(self.Trails.Directory) do
            if not saveData.TrailInventory[trial._id] and self:CanAfford(saveData.Money, trial.Price) and tonumber(trial.Price) <= (self.MaxSpend or math.huge) then
                table.insert(list, trial._id)
            end
        end
        return list
    end)
    if ok and res then
        out = res
    end
    return out
end

function AutoBuy:GetBaseUpgradeable(saveData)
    local ok, res = pcall(function()
        local l = saveData.BaseUpgradeLevel + 1
        local n = self.Bases.BASES[l]
        if not n then
            return false
        end
        if tonumber(n.Cost) and tonumber(n.Cost) > (self.MaxSpend or math.huge) then
            return false
        end
        return self:CanAfford(saveData.Money, n.Cost)
    end)
    if ok then
        return res
    end
    return false
end

function AutoBuy:Run()
    if not self.Enabled then
        return
    end
    self:EnsureData()
    if not self.Save then
        return
    end
    local ok, saveData = pcall(function()
        return self.Save.Get()
    end)
    if not ok or not saveData then
        return
    end
    pcall(function()
        if self.BuyTrails and self.Trails and self.TrailRemote then
            for _, trail in ipairs(self:GetTrails(saveData)) do
                warn("[Quantum Hub] purchased trail: " .. tostring(trail))
                safeInvoke(self.TrailRemote, trail)
                task.wait(0.1)
            end
        end
        if self.BuyTreadmills and self.Treadmills and self.TreadmillRemote then
            -- Refresh money mid-cycle so MaxSpend is respected
            local d = saveData
            for _, id in ipairs(self:GetTreadmills(d)) do
                warn("[Quantum Hub] purchased treadmill: " .. tostring(id))
                safeInvoke(self.TreadmillRemote, id)
                task.wait(0.1)
            end
        end
        if self.BuyBases and self.Bases and self.BaseRemote then
            if self:GetBaseUpgradeable(saveData) then
                safeFire(self.BaseRemote)
            end
        end
    end)
end

function AutoBuy:Toggle(state)
    self.Enabled = state and true or false
    if self.Enabled then
        self:EnsureData()
    end
end

-- AutoSell --------------------------------------------------------
local AutoSell = {
    Enabled = false,
    Rarities = {
        Common = true,
        Uncommon = true,
        Rare = true,
        Epic = true,
        Legendary = true,
        Mythic = false, -- safer default: never auto-sell Mythic unless chosen
    },
    Save = nil,
    Assets = nil,
    WearRemote = nil,
    SellRemote = nil,
}

function AutoSell:EnsureData()
    if not self.Save then
        pcall(function()
            local shared = ReplicatedStorage:FindFirstChild("Shared")
            if shared then
                local m = shared:FindFirstChild("Save")
                if m then
                    self.Save = require(m)
                end
            end
        end)
    end
    if not self.Assets then
        pcall(function()
            local data = ReplicatedStorage:FindFirstChild("Data")
            if data then
                local m = data:FindFirstChild("Assets")
                if m then
                    self.Assets = require(m)
                end
            end
        end)
    end
    if not self.WearRemote then
        self.WearRemote = getRemote("RF/EggWorld/AskWearTool")
    end
    if not self.SellRemote then
        self.SellRemote = getRemote("RE/PetSatchel/SellPet")
    end
end

function AutoSell:Run()
    if not self.Enabled then
        return
    end
    self:EnsureData()
    if not self.Save or not self.Assets then
        return
    end
    local ok, data = pcall(function()
        return self.Save.Get()
    end)
    if not ok or not data then
        return
    end
    local inv = data.EggInventory
    if not inv then
        return
    end
    pcall(function()
        for uid, eggdata in pairs(inv) do
            if not self.Enabled then
                break
            end
            if eggdata.Placement then
                continue
            end
            local rok, rarity = pcall(function()
                return self.Assets.Directory[eggdata.AssetCategory].Rarity.DisplayName
            end)
            if rok and rarity and self.Rarities[rarity] then
                safeInvoke(self.WearRemote, uid)
                safeFire(self.SellRemote, { uid })
                task.wait(0.1)
            end
        end
    end)
end

function AutoSell:Toggle(state)
    self.Enabled = state and true or false
    if self.Enabled then
        self:EnsureData()
    end
end

-- AutoFarm --------------------------------------------------------
local AutoFarm = {
    Enabled = false,
    MinArea = 9,
    ReturnToBase = true,
    CycleDelay = 1.5,
    GoSpeed = 1500, -- un-hardcoded farm travel speed (was fixed 430)
    Areas = {
        "Forest",
        "Lake",
        "Desert",
        "Jungle",
        "Snow",
        "Volcano",
        "Abyss Ocean",
        "Prehistoric",
        "Cosmic",
        "Cherry Blossom",
        "Titan Temple",
        "Light Dark",
    },
    EggState = nil,
    Token = 0,
    WasEnabled = false,
    PausedBySteal = false,
}

function AutoFarm:Pause()
    if self.Enabled then
        self.WasEnabled = true
        self.PausedBySteal = true
        self.Enabled = false
        self.Token = self.Token + 1
        warn("[Quantum Hub] AutoFarm paused (steal running)")
    end
end

function AutoFarm:Resume()
    if self.PausedBySteal then
        self.PausedBySteal = false
        if self.WasEnabled then
            self.WasEnabled = false
            self:Toggle(true)
        end
    end
end

function AutoFarm:EnsureData()
    if not self.EggState then
        pcall(function()
            local client = ReplicatedStorage:FindFirstChild("Client")
            if client then
                local m = client:FindFirstChild("EggState")
                if m then
                    self.EggState = require(m)
                end
            end
        end)
    end
end

function AutoFarm:GetBestEgg()
    local ok, res = pcall(function()
        local egg = nil
        local bestArea = 0
        local records = self.EggState.ReadFieldEggs().Records
        for _, data in pairs(records) do
            local idx = table.find(self.Areas, data.AreaId)
            if idx and idx >= (self.MinArea or 1) then
                if idx > bestArea then
                    bestArea = idx
                    egg = data
                end
            end
        end
        return egg
    end)
    if ok then
        return res
    end
    return nil
end

function AutoFarm:GoTo(cframePos)
    pcall(function()
        local hrp = GetHRP()
        local char = GetCharacter()
        if not hrp or not char then
            return
        end
        local target = cframePos
        if typeof(cframePos) == "table" and cframePos.BoundsCFrame then
            target = cframePos.BoundsCFrame
        end
        if typeof(target) ~= "CFrame" then
            return
        end
        local dist = math.huge
        local t0 = tick()
        repeat
            local dt = task.wait(0.01)
            hrp = GetHRP()
            char = GetCharacter()
            if not hrp or not char then
                break
            end
            local start = hrp.Position
            dist = (target.Position - start).Magnitude
            if dist <= 5 then
                break
            end
            local dir = (target.Position - start)
            if dir.Magnitude > 0 then
                local spd = tonumber(self.GoSpeed) or 430
                local step = start + dir.Unit * dt * spd
                pcall(function()
                    char:MoveTo(step)
                end)
            end
            if tick() - t0 > 30 then
                break
            end
        until dist <= 5
    end)
end

function AutoFarm:GetPromptForEgg(egg)
    local ok, res = pcall(function()
        local targetPos = nil
        if typeof(egg) == "table" and egg.BoundsCFrame then
            targetPos = egg.BoundsCFrame.Position
        elseif typeof(egg) == "CFrame" then
            targetPos = egg.Position
        else
            return nil
        end
        local closest = nil
        local closestDist = math.huge
        for _, v in ipairs(Workspace:GetDescendants()) do
            if v.Name == "#CarryAreaEgg" then
                local p = v.Parent
                local base = nil
                if p and p:IsA("BasePart") then
                    base = p
                elseif p and p:IsA("ProximityPrompt") then
                    base = p.Parent
                    if base and not base:IsA("BasePart") then
                        base = nil
                    end
                end
                if v:IsA("ProximityPrompt") then
                    local holder = v.Parent
                    if holder and holder:IsA("BasePart") then
                        local d = (targetPos - holder.Position).Magnitude
                        if d < closestDist then
                            closestDist = d
                            closest = v
                        end
                    end
                elseif base then
                    local pr = base:FindFirstChildOfClass("ProximityPrompt")
                    if pr then
                        local d = (targetPos - base.Position).Magnitude
                        if d < closestDist then
                            closestDist = d
                            closest = pr
                        end
                    end
                end
            end
        end
        -- Fallback: any CarryAreaEgg prompt
        if not closest then
            for _, v in ipairs(Workspace:GetDescendants()) do
                if v:IsA("ProximityPrompt") and tostring(v) == "CarryAreaEgg" then
                    return v
                end
            end
        end
        return closest
    end)
    if ok then
        return res
    end
    return nil
end

function AutoFarm:FarmOnce()
    local egg = self:GetBestEgg()
    if egg then
        self:GoTo(BASE_CFRAME)
        task.wait(0.1)
        self:GoTo(egg)
        task.wait(0.5)
        local prompt = self:GetPromptForEgg(egg)
        if prompt and fireproximityprompt then
            pcall(function()
                fireproximityprompt(prompt)
            end)
        end
        task.wait(2)
        if prompt and fireproximityprompt then
            pcall(function()
                local stillThere = self:GetPromptForEgg(egg)
                if stillThere then
                    fireproximityprompt(stillThere)
                end
            end)
        end
        if self.ReturnToBase then
            self:GoTo(BASE_CFRAME)
            task.wait(0.1)
        end
    else
        if self.ReturnToBase then
            self:GoTo(BASE_CFRAME)
            task.wait(0.5)
        else
            task.wait(0.5)
        end
    end
end

function AutoFarm:Toggle(state)
    self.Enabled = state and true or false
    if self.Enabled then
        if not fireproximityprompt then
            warn("[Quantum Hub] AutoFarm requires fireproximityprompt")
            if Notify then
                Notify("AutoFarm needs fireproximityprompt")
            end
            self.Enabled = false
            return
        end
        self:EnsureData()
        self.Token = self.Token + 1
        local myToken = self.Token
        task.spawn(function()
            while self.Enabled and myToken == self.Token do
                local ok, err = pcall(function()
                    self:FarmOnce()
                end)
                if not ok then
                    warn("[Quantum Hub] AutoFarm cycle failed: " .. tostring(err))
                end
                local delay = math.clamp(tonumber(self.CycleDelay) or 5, 1, 20)
                local waited = 0
                while waited < delay and self.Enabled and myToken == self.Token do
                    task.wait(0.25)
                    waited = waited + 0.25
                end
            end
        end)
    else
        self.Token = self.Token + 1
    end
end

-- AutoRedeem ------------------------------------------------------
local AutoRedeem = {
    Enabled = false,
    Interval = 1,
    RedeemRemote = nil,
    Token = 0,
}

function AutoRedeem:Toggle(state)
    self.Enabled = state and true or false
    if self.Enabled then
        if not self.RedeemRemote then
            self.RedeemRemote = getRemote("RF/Codex/AskRedeemAll")
        end
        self.Token = self.Token + 1
        local myToken = self.Token
        task.spawn(function()
            while self.Enabled and myToken == self.Token do
                pcall(function()
                    if self.RedeemRemote then
                        safeInvoke(self.RedeemRemote)
                    else
                        self.RedeemRemote = getRemote("RF/Codex/AskRedeemAll")
                    end
                end)
                task.wait(math.clamp(tonumber(self.Interval) or 1, 1, 10))
            end
        end)
    else
        self.Token = self.Token + 1
    end
end

-- Forward declarations: AutoSteal travel reuses these movement modules,
-- which are defined below. (Luau locals must be declared before use.)
local Glide, Blink, Fly, AutoTreadmill, PlaceHatch

-- AutoSteal -------------------------------------------------------
-- TODO: adjust the candidate field names below to this game's exact
-- egg record schema (AreaId/BoundsCFrame verified from EggState).
local AutoSteal = {
    Enabled = false,
    ScanRadius = 1500,
    MovementMethod = "Fly", -- Walk / Glide / Blink / Fly
    FilterMode = "Rarity", -- Rarity / Best Value / Weight-Size
    AreaAllow = {}, -- empty = all areas; keys are AreaId strings
    ReturnToBase = true,
    GoBackOut = true,
    MoveSpeed = 500,
    BlinkDistance = 100,
    CycleDelay = 1.5,
    HoverHeight = 12, -- Fly hover above ground (0-300); Glide fixed 12
    MinValue = 0,
    MaxValue = 1000000000,
    BestValueOnly = false,
    PlaceEnabled = false, -- deposit after base return (user toggle)
    HatchEnabled = false, -- hatch when ready (user toggle)
    MinWeight = 0,
    MaxWeight = 1000000,
    RarityAllow = {}, -- empty = allow all; TODO: adjust names via DiscoverFilters
    MutationAllow = {}, -- empty = allow all; TODO: adjust names via DiscoverFilters
    -- Pinned rarity display order (real names still come from DiscoverFilters).
    -- TODO: adjust pin list if this game adds/removes rarities.
    -- Rarity rank, highest to lowest: Divine first, Common last.
    -- TODO: adjust rank if this game adds/removes rarities.
    PinRarities = { "Divine", "Eternal", "Secret", "Cosmic", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common" },
    SecretFirst = false, -- Divine/Eternal/Secret jump queue in any mode
    DiscoveredRarities = {},
    DiscoveredMutations = {},
    EggState = nil,
    Save = nil,
    Assets = nil,
    Token = 0,
    LastMatches = {},
    PreviewLabel = nil, -- wired by UI construction
    StealOwnedGlide = false,
    StealOwnedFly = false,
    SavedWalkSpeed = 16,
    StealDriving = false, -- true while TravelTo owns the character
}

function AutoSteal:EnsureData()
    if not self.EggState then
        pcall(function()
            local client = ReplicatedStorage:FindFirstChild("Client")
            if client then
                local m = client:FindFirstChild("EggState")
                if m then
                    self.EggState = require(m)
                end
            end
        end)
    end
    if not self.Save then
        pcall(function()
            local shared = ReplicatedStorage:FindFirstChild("Shared")
            if shared then
                local m = shared:FindFirstChild("Save")
                if m then
                    self.Save = require(m)
                end
            end
        end)
    end
    if not self.Assets then
        pcall(function()
            local data = ReplicatedStorage:FindFirstChild("Data")
            if data then
                local m = data:FindFirstChild("Assets")
                if m then
                    self.Assets = require(m)
                end
            end
        end)
    end
end

-- Collect real rarity/mutation names from game data so filters never
-- hardcode wrong names. TODO: adjust containers if this game stores
-- mutations elsewhere.
function AutoSteal:DiscoverFilters()
    self:EnsureData()
    pcall(function()
        local rar = {}
        if self.Assets and self.Assets.Directory then
            for _, entry in pairs(self.Assets.Directory) do
                local ok, name = pcall(function()
                    return entry.Rarity.DisplayName or entry.Rarity.Name
                end)
                if ok and name and not table.find(rar, tostring(name)) then
                    table.insert(rar, tostring(name))
                end
            end
        end
        if #rar == 0 and self.EggState then
            local ok, field = pcall(function()
                return self.EggState.ReadFieldEggs()
            end)
            if ok and field and field.Records then
                for _, egg in pairs(field.Records) do
                    local name = self:ResolveRarity(egg)
                    if name and not table.find(rar, name) then
                        table.insert(rar, name)
                    end
                end
            end
        end
        table.sort(rar)
        local ordered = {}
        local seen = {}
        for _, pname in ipairs(self.PinRarities) do
            if table.find(rar, pname) then
                table.insert(ordered, pname)
                seen[pname] = true
            end
        end
        for _, rname in ipairs(rar) do
            if not seen[rname] then
                table.insert(ordered, rname)
            end
        end
        self.DiscoveredRarities = ordered
    end)
    pcall(function()
        local muts = {}
        if self.Assets then
            for _, key in ipairs({ "Mutations", "MutationList", "MutationDirectory" }) do
                local t = self.Assets[key]
                if typeof(t) == "table" then
                    for _, m in pairs(t) do
                        local n = nil
                        pcall(function()
                            if typeof(m) == "string" then
                                n = m
                            elseif typeof(m) == "table" then
                                n = m.DisplayName or m.Name
                            end
                        end)
                        if n and not table.find(muts, tostring(n)) then
                            table.insert(muts, tostring(n))
                        end
                    end
                end
            end
        end
        if #muts == 0 and self.EggState then
            local ok, field = pcall(function()
                return self.EggState.ReadFieldEggs()
            end)
            if ok and field and field.Records then
                for _, egg in pairs(field.Records) do
                    local name = self:ResolveMutation(egg)
                    if name and not table.find(muts, name) then
                        table.insert(muts, name)
                    end
                end
            end
        end
        table.sort(muts)
        self.DiscoveredMutations = muts
    end)
end

function AutoSteal:ResolveRarity(egg)
    local ok, res = pcall(function()
        if not self.Assets or not self.Assets.Directory then
            return nil
        end
        local entry = self.Assets.Directory[egg.AssetCategory]
        if not entry then
            return nil
        end
        return entry.Rarity.DisplayName or entry.Rarity.Name
    end)
    if ok and res then
        return tostring(res)
    end
    return nil
end

-- TODO: adjust candidate fields to this game's egg mutation schema.
function AutoSteal:ResolveMutation(egg)
    local ok, res = pcall(function()
        if typeof(egg) ~= "table" then
            return nil
        end
        local raw = egg.Mutation or egg.MutationId or egg.MutationName
        if raw == nil then
            return nil
        end
        if typeof(raw) == "string" then
            return raw
        end
        if self.Assets then
            for _, key in ipairs({ "Mutations", "MutationList", "MutationDirectory" }) do
                local t = self.Assets[key]
                if typeof(t) == "table" then
                    local e = t[raw] or t[tostring(raw)]
                    if e ~= nil then
                        if typeof(e) == "string" then
                            return e
                        end
                        if typeof(e) == "table" then
                            return e.DisplayName or e.Name
                        end
                    end
                end
            end
        end
        return tostring(raw)
    end)
    if ok and res then
        return tostring(res)
    end
    return nil
end

-- TODO: adjust candidate fields to this game's egg weight/size schema.
function AutoSteal:ResolveWeight(egg)
    local ok, res = pcall(function()
        if typeof(egg) ~= "table" then
            return nil
        end
        return tonumber(egg.Weight or egg.Size or egg.Mass or egg.Scale)
    end)
    if ok then
        return res
    end
    return nil
end

-- TODO: adjust candidate fields to this game's egg value schema.
function AutoSteal:ResolveValue(egg)
    local ok, res = pcall(function()
        if typeof(egg) ~= "table" then
            return nil
        end
        local v = tonumber(egg.Value or egg.Cost or egg.Price)
        if v then
            return v
        end
        if self.Assets and self.Assets.Directory and egg.AssetCategory then
            local entry = self.Assets.Directory[egg.AssetCategory]
            if entry then
                return tonumber(entry.Value or entry.Cost or entry.Price)
            end
        end
        return nil
    end)
    if ok then
        return res
    end
    return nil
end

function AutoSteal:GetEggPos(egg)
    local ok, res = pcall(function()
        if typeof(egg) == "table" then
            -- TODO: adjust to this game's exact egg record position fields.
            if egg.BoundsCFrame then
                if typeof(egg.BoundsCFrame) == "CFrame" then
                    return egg.BoundsCFrame.Position
                end
            end
            if typeof(egg.Position) == "Vector3" then
                return egg.Position
            end
            if typeof(egg.CFrame) == "CFrame" then
                return egg.CFrame.Position
            end
        elseif typeof(egg) == "CFrame" then
            return egg.Position
        end
        return nil
    end)
    if ok then
        return res
    end
    return nil
end

-- Allow-list truth: no `true` entry anywhere = allow all. This keeps
-- unchecked-everything, cleared tables, and pre-discovery states honest.
local function AllowAll(t)
    for _, v in pairs(t) do
        if v == true then
            return false
        end
    end
    return true
end

function AutoSteal:PassesFilters(egg)
    local ok, res = pcall(function()
        local mode = self.FilterMode or "Rarity"
        local rarity = self:ResolveRarity(egg)
        if mode == "Rarity" and not AllowAll(self.RarityAllow) then
            -- Unresolvable rarity passes so schema drift can't hide everything.
            -- TODO: adjust to reject here if strict filtering is wanted.
            if rarity ~= nil and self.RarityAllow[rarity] ~= true then
                return false
            end
        end
        local mut = self:ResolveMutation(egg)
        if not AllowAll(self.MutationAllow) then
            if mut ~= nil and self.MutationAllow[mut] ~= true then
                return false
            end
        end
        local w = self:ResolveWeight(egg)
        if w ~= nil and mode == "Weight-Size" then
            if w < (self.MinWeight or 0) or w > (self.MaxWeight or math.huge) then
                return false
            end
        end
        local v = self:ResolveValue(egg) or 0
        if mode == "Best Value" and (v < (self.MinValue or 0) or v > (self.MaxValue or math.huge)) then
            return false
        end
        return true
    end)
    if ok then
        return res
    end
    return false
end

function AutoSteal:GetMatches()
    local out = {}
    pcall(function()
        if not self.EggState then
            return
        end
        local hrp = GetHRP()
        if not hrp then
            return
        end
        local ok, field = pcall(function()
            return self.EggState.ReadFieldEggs()
        end)
        if not ok or not field or not field.Records then
            return
        end
        local origin = hrp.Position
        for _, egg in pairs(field.Records) do
            local pos = self:GetEggPos(egg)
            if pos then
                local dist = (pos - origin).Magnitude
                local areaOk = true
                pcall(function()
                    -- Compare raw AND tostring: AreaId may be a number or a name.
                    -- TODO: adjust if this game keys areas differently.
                    if not AllowAll(self.AreaAllow) and typeof(egg) == "table" and egg.AreaId ~= nil then
                        local raw, named = egg.AreaId, tostring(egg.AreaId)
                        areaOk = self.AreaAllow[raw] == true or self.AreaAllow[named] == true
                    end
                end)
                if areaOk and dist <= (self.ScanRadius or 300) and self:PassesFilters(egg) then
                    local area = "?"
                    pcall(function()
                        if typeof(egg) == "table" and egg.AreaId ~= nil then
                            area = tostring(egg.AreaId)
                        end
                    end)
                    table.insert(out, {
                        Egg = egg,
                        Pos = pos,
                        Dist = dist,
                        Area = area,
                        Rarity = self:ResolveRarity(egg) or "?",
                        Mutation = self:ResolveMutation(egg) or "-",
                        Weight = self:ResolveWeight(egg),
                        Value = self:ResolveValue(egg) or 0,
                    })
                end
            end
        end
        local mode = self.FilterMode or "Rarity"
        local secretFirst = self.SecretFirst and true or false
        table.sort(out, function(a, b)
            if secretFirst then
                local at, bt = (self:RankOf(a.Rarity) <= 3), (self:RankOf(b.Rarity) <= 3)
                if at ~= bt then
                    return at
                end
            end
            if mode == "Rarity" then
                local ar, br = self:RankOf(a.Rarity), self:RankOf(b.Rarity)
                if ar ~= br then
                    return ar < br
                end
                return a.Dist < b.Dist
            end
            if a.Value ~= b.Value then
                return a.Value > b.Value
            end
            return a.Dist < b.Dist
        end)
    end)
    self.LastMatches = out
    self:UpdatePreview(out)
    return out
end

-- Tier rank from the pinned sequence (Divine first). Unknown = last.
function AutoSteal:RankOf(rarity)
    local idx = table.find(self.PinRarities, tostring(rarity or "?"))
    if idx then
        return idx
    end
    return 999
end

function AutoSteal:UpdatePreview(matches)
    pcall(function()
        local label = self.PreviewLabel
        if not label then
            return
        end
        matches = matches or self.LastMatches or {}
        if #matches == 0 then
            label.Text = "No eggs match the current filters."
            return
        end
        local lines = {}
        for i = 1, math.min(#matches, 8) do
            local m = matches[i]
            table.insert(lines, string.format("%d. %s | %s | %s | %s", i, tostring(m.Area), tostring(m.Rarity), tostring(m.Mutation), tostring(m.Value)))
        end
        if #matches > 8 then
            table.insert(lines, "+" .. tostring(#matches - 8) .. " more")
        end
        label.Text = table.concat(lines, "\n")
    end)
end

function AutoSteal:RefreshPreview()
    self:EnsureData()
    local matches = self:GetMatches()
    if Notify then
        Notify("AutoSteal: " .. tostring(#matches) .. " match(es)")
    end
end

function AutoSteal:GetPrompt(pos)
    local ok, res = pcall(function()
        local closest = nil
        local cd = math.huge
        local maxD = math.max((self.ScanRadius or 300), 60)
        for _, v in ipairs(Workspace:GetDescendants()) do
            if v:IsA("ProximityPrompt") and (tostring(v) == "CarryAreaEgg" or v.Name == "#CarryAreaEgg") then
                -- Holders can be parts, models, or attachments.
                -- TODO: adjust if this game parents prompts elsewhere.
                local anchor = nil
                local holder = v.Parent
                if holder then
                    if holder:IsA("BasePart") then
                        anchor = holder.Position
                    elseif holder:IsA("Model") then
                        local pivOk, piv = pcall(function()
                            return holder:GetPivot().Position
                        end)
                        if pivOk then
                            anchor = piv
                        end
                    elseif holder:IsA("Attachment") then
                        anchor = holder.WorldPosition
                    end
                end
                if anchor then
                    local d = (pos - anchor).Magnitude
                    if d < cd and d <= maxD then
                        cd = d
                        closest = v
                    end
                end
            end
        end
        return closest
    end)
    if ok then
        return res
    end
    return nil
end

-- TODO: adjust Walk steering if this game server-clamps WalkSpeed.
function AutoSteal:TravelTo(pos, token)
    local method = self.MovementMethod or "Walk"
    local speed = math.clamp(tonumber(self.MoveSpeed) or 500, 100, 1500)
    self.StealDriving = true
    if method == "Blink" then
        pcall(function()
            local hrp0 = GetHRP()
            if hrp0 then
                hrp0.CFrame = CFrame.new(hrp0.Position, pos)
            end
        end)
        local steps = 0
        while self.Enabled and token == self.Token and steps < 40 do
            local hrp = GetHRP()
            if not hrp then
                break
            end
            if (pos - hrp.Position).Magnitude <= 6 then
                break
            end
            pcall(function()
                hrp.CFrame = CFrame.new(hrp.Position, pos)
                Blink.Distance = math.clamp(tonumber(self.BlinkDistance) or 100, 100, 1500)
                Blink:BlinkNow()
            end)
            task.wait(0.55)
            steps = steps + 1
        end
        self.StealDriving = false
        return
    end
    if method == "Fly" then
        local hover = math.clamp(tonumber(self.HoverHeight) or 12, 0, 300)
        pcall(function()
            Fly.Speed = speed
            if not Fly.Enabled then
                Fly:Toggle(true)
                self.StealOwnedFly = true
            end
        end)
        local t0 = tick()
        while self.Enabled and token == self.Token and tick() - t0 < 30 do
            local hrp = GetHRP()
            if not hrp then
                break
            end
            local aim = pos + Vector3.new(0, hover, 0)
            local dir = aim - hrp.Position
            local flat = Vector3.new(dir.X, 0, dir.Z)
            if flat.Magnitude <= 6 then
                break
            end
            pcall(function()
                if Fly.BV and Fly.BV.Parent == hrp then
                    Fly.BV.Velocity = dir.Unit * speed
                else
                    hrp.CFrame = hrp.CFrame + dir.Unit * math.min(dir.Magnitude, speed * 0.05)
                end
            end)
            task.wait(0.05)
        end
        pcall(function()
            if Fly.BV then
                Fly.BV.Velocity = Vector3.new(0, 0, 0)
            end
        end)
        self.StealDriving = false
        return
    end
    -- Walk grounded; Glide shares steering but holds +12 hover (built-in).
    local glideHover = 12
    pcall(function()
        if method == "Glide" then
            Glide.Speed = speed
            if not Glide.Enabled then
                Glide:Toggle(true)
                self.StealOwnedGlide = true
            end
        end
        local hum = GetHumanoid()
        if hum then
            hum.WalkSpeed = speed
        end
    end)
    local t0 = tick()
    while self.Enabled and token == self.Token and tick() - t0 < 30 do
        local dt = task.wait(0.05)
        local hrp = GetHRP()
        local char = GetCharacter()
        if not hrp or not char then
            break
        end
        local offset = pos - hrp.Position
        local arrived = false
        if method == "Glide" then
            arrived = Vector3.new(offset.X, 0, offset.Z).Magnitude <= 6
        else
            arrived = offset.Magnitude <= 6
        end
        if arrived then
            break
        end
        pcall(function()
            local hum = GetHumanoid()
            if hum then
                hum.WalkSpeed = speed
            end
            if method == "Glide" and Glide.BV and Glide.BV.Parent == hrp then
                local dy = (pos.Y + glideHover) - hrp.Position.Y
                Glide.BV.Velocity = Vector3.new(0, math.clamp(dy * 2, -30, 30), 0)
            end
            char:MoveTo(hrp.Position + offset.Unit * math.min(offset.Magnitude, speed * dt))
        end)
    end
    self.StealDriving = false
end

function AutoSteal:StopMovement()
    pcall(function()
        local hum = GetHumanoid()
        if hum then
            hum.WalkSpeed = self.SavedWalkSpeed or 16
        end
    end)
    if self.StealOwnedGlide then
        pcall(function()
            Glide:Toggle(false)
        end)
        self.StealOwnedGlide = false
    end
    if self.StealOwnedFly then
        pcall(function()
            Fly:Toggle(false)
        end)
        self.StealOwnedFly = false
    end
end

-- Egg detector: how many eggs the save holds (nil when unreadable).
function AutoSteal:EggCount()
    local ok, res = pcall(function()
        if not self.Save then
            return nil
        end
        local d = self.Save.Get()
        if not d or not d.EggInventory then
            return nil
        end
        local n = 0
        for _ in pairs(d.EggInventory) do
            n = n + 1
        end
        return n
    end)
    if ok then
        return res
    end
    return nil
end

-- True when an egg is in hand right now: tool equipped, or the save
-- grew since beforeCount. Same Tool pattern as KillAura:CanUseTool.
function AutoSteal:IsHoldingEgg(beforeCount)
    local held = false
    pcall(function()
        local char = GetCharacter()
        if char and char:FindFirstChildOfClass("Tool") then
            held = true
        end
    end)
    if not held and beforeCount ~= nil then
        pcall(function()
            local now = self:EggCount()
            if now ~= nil and now > beforeCount then
                held = true
            end
        end)
    end
    return held
end

-- True when this exact target can still be stolen (record + prompt exist).
function AutoSteal:TargetStillThere(best)
    local ok, res = pcall(function()
        if not self.EggState then
            return false
        end
        local f = self.EggState.ReadFieldEggs()
        if not f or not f.Records then
            return false
        end
        for _, egg in pairs(f.Records) do
            local pos = self:GetEggPos(egg)
            if pos and (pos - best.Pos).Magnitude <= 10 then
                local areaOk = true
                if typeof(egg) == "table" and egg.AreaId ~= nil and best.Area ~= "?" then
                    areaOk = tostring(egg.AreaId) == tostring(best.Area)
                end
                if areaOk and self:GetPrompt(pos) ~= nil then
                    return true
                end
            end
        end
        return false
    end)
    if ok then
        return res
    end
    return false
end

-- After a hover arrival (Fly/Glide), drop to the egg for a grounded
-- grab like reference hubs do, then fire. No-op for Walk/Blink.
function AutoSteal:LandForGrab(pos)
    pcall(function()
        local m = self.MovementMethod or "Walk"
        if m ~= "Fly" and m ~= "Glide" then
            return
        end
        local hrp = GetHRP()
        if not hrp then
            return
        end
        hrp.CFrame = CFrame.new(pos.X, pos.Y + 3, pos.Z)
        if Fly.BV then
            Fly.BV.Velocity = Vector3.new(0, 0, 0)
        end
        task.wait(0.3)
    end)
end

-- One grab attempt at an arrived target. Returns "held", "retry"
-- (still stealable), or "gone".
function AutoSteal:GrabAt(best, token)
    if not self.Enabled or token ~= self.Token then
        return "gone"
    end
    local before = self:EggCount()
    task.wait(0.4)
    local prompt = self:GetPrompt(best.Pos)
    if prompt and fireproximityprompt then
        pcall(function()
            fireproximityprompt(prompt)
        end)
        task.wait(0.5)
        if self:IsHoldingEgg(before) then
            return "held"
        end
        pcall(function()
            local again = self:GetPrompt(best.Pos)
            if again and fireproximityprompt then
                fireproximityprompt(again)
            end
        end)
        task.wait(0.5)
        if self:IsHoldingEgg(before) then
            return "held"
        end
    else
        warn("[Quantum Hub] AutoSteal: no prompt at target")
    end
    if self:TargetStillThere(best) then
        return "retry"
    end
    return "gone"
end

-- Fresh matches excluding positions already proven unstealable.
function AutoSteal:PickFresh(ignored)
    local fresh = self:GetMatches()
    if not ignored or #ignored == 0 then
        return fresh
    end
    local out = {}
    for _, m in ipairs(fresh) do
        local skip = false
        for _, ip in ipairs(ignored) do
            local ok, close = pcall(function()
                return (m.Pos - ip).Magnitude <= 10
            end)
            if ok and close then
                skip = true
                break
            end
        end
        if not skip then
            table.insert(out, m)
        end
    end
    return out
end

function AutoSteal:PickBest(matches)
    local best = matches[1]
    if self.BestValueOnly then
        for _, m in ipairs(matches) do
            if m.Value > best.Value then
                best = m
            end
        end
    end
    return best
end

function AutoSteal:GoBaseAndDeposit(token, lastPos)
    if not self.ReturnToBase then
        return
    end
    self:TravelTo(BASE_CFRAME.Position, token)
    if not self.Enabled or token ~= self.Token then
        return
    end
    pcall(function()
        if self.PlaceEnabled then
            PlaceHatch:PlaceOnce()
        end
    end)
    pcall(function()
        if self.HatchEnabled then
            PlaceHatch:HatchOnce()
        end
    end)
    if self.GoBackOut and self.Enabled and token == self.Token and lastPos then
        self:TravelTo(lastPos, token)
    end
end

function AutoSteal:StealOnce()
    local token = self.Token
    local ignored = {}
    local matches = self:PickFresh(ignored)
    if #matches == 0 then
        if Notify then
            Notify("AutoSteal: no matches")
        end
        -- Nothing to steal: hold base instead of idling in the field.
        if self.ReturnToBase then
            self:TravelTo(BASE_CFRAME.Position, token)
        end
        return
    end
    local best = self:PickBest(matches)
    local goneStreak = 0
    while self.Enabled and token == self.Token do
        self:TravelTo(best.Pos, token)
        if not self.Enabled or token ~= self.Token then
            return
        end
        self:LandForGrab(best.Pos)
        if not self.Enabled or token ~= self.Token then
            return
        end
        local result = self:GrabAt(best, token)
        if not self.Enabled or token ~= self.Token then
            return
        end
        if result == "held" then
            -- INSTANT base on the success path: no extra waits.
            if Notify then
                Notify("AutoSteal: stole " .. tostring(best.Rarity) .. " (" .. tostring(best.Value) .. ")")
            end
            self:GoBaseAndDeposit(token, best.Pos)
            return
        end
        if result == "retry" then
            -- Same egg still stealable: re-travel and re-fire until held.
            goneStreak = 0
            task.wait(0.25)
        else
            goneStreak = goneStreak + 1
            if goneStreak < 3 then
                task.wait(0.5)
            else
                -- Fully stolen/gone: blacklist this spot and retarget
                -- immediately with no base trip.
                table.insert(ignored, best.Pos)
                local fresh = self:PickFresh(ignored)
                if #fresh > 0 then
                    best = self:PickBest(fresh)
                    goneStreak = 0
                    if Notify then
                        Notify("AutoSteal: retargeting " .. tostring(best.Rarity))
                    end
                else
                    -- Nothing else selected: back to base, resume cycling.
                    if Notify then
                        Notify("AutoSteal: target gone, returning")
                    end
                    if self.ReturnToBase then
                        self:TravelTo(BASE_CFRAME.Position, token)
                    end
                    return
                end
            end
        end
    end
end

function AutoSteal:Toggle(state)
    self.Enabled = state and true or false
    if self.Enabled then
        -- Hard requirement: without the prompt API nothing can be stolen,
        -- so abort instead of travelling forever.
        if not fireproximityprompt then
            warn("[Quantum Hub] AutoSteal aborted: missing fireproximityprompt")
            if Notify then
                Notify("AutoSteal aborted: executor lacks prompt API")
            end
            self.Enabled = false
            return
        end
        -- Boot with retries: game data is often not ready on first enable.
        local ready = false
        for attempt = 1, 5 do
            self:EnsureData()
            if self.EggState then
                local ok, field = pcall(function()
                    return self.EggState.ReadFieldEggs()
                end)
                if ok and field and field.Records then
                    ready = true
                    break
                end
            end
            task.wait(1)
        end
        if not ready then
            warn("[Quantum Hub] AutoSteal aborted: EggState/field eggs unreadable")
            if Notify then
                Notify("AutoSteal aborted: no egg data")
            end
            self.Enabled = false
            return
        end
        pcall(function()
            local hum = GetHumanoid()
            self.SavedWalkSpeed = (hum and hum.WalkSpeed) or 16
        end)
        self:DiscoverFilters()
        pcall(function()
            AutoTreadmill:Pause()
        end)
        pcall(function()
            AutoFarm:Pause()
        end)
        self.Token = self.Token + 1
        local myToken = self.Token
        if Notify then
            Notify("AutoSteal enabled (" .. tostring(self.MovementMethod or "Walk") .. ")")
        end
        task.spawn(function()
            while self.Enabled and myToken == self.Token do
                local ok, err = pcall(function()
                    self:StealOnce()
                end)
                if not ok then
                    warn("[Quantum Hub] AutoSteal cycle failed: " .. tostring(err))
                end
                local delay = math.clamp(tonumber(self.CycleDelay) or 5, 1, 20)
                local waited = 0
                while waited < delay and self.Enabled and myToken == self.Token do
                    task.wait(0.25)
                    waited = waited + 0.25
                end
            end
        end)
    else
        self.Token = self.Token + 1
        self:StopMovement()
        pcall(function()
            AutoTreadmill:Resume()
        end)
        pcall(function()
            AutoFarm:Resume()
        end)
    end
end

-- SpeedBypass -----------------------------------------------------
local SpeedBypass = {
    Enabled = false,
    WalkSpeed = 1500,
    SafeMode = false,
    Hooked = false,
    SpeedConn = nil,
}

function SpeedBypass:CollectGC()
    local ok, res = pcall(function()
        return getgc()
    end)
    if ok and res then
        return res
    end
    warn("[Quantum Hub] SpeedBypass failed to get gc: " .. tostring(res))
    return nil
end

function SpeedBypass:SafeHook(f, c)
    local ok, res = pcall(function()
        return hookfunction(f, newlclosure(c))
    end)
    if ok and res then
        return res
    end
    warn("[Quantum Hub] SpeedBypass failed to hook: " .. tostring(res))
    return nil
end

function SpeedBypass:FindFunction(nups, linedefined)
    local ok, res = pcall(function()
        local gc = self:CollectGC()
        if not gc then
            return nil
        end
        for _, f in pairs(gc) do
            if typeof(f) == "function" and islclosure(f) then
                local upvs = debug.getupvalues(f)
                local line = debug.info(f, "l")
                if upvs and #upvs == nups and line == linedefined then
                    if nups == 10 then
                        local t = debug.getupvalue(f, 3)
                        if typeof(t) == "table" and rawget(t, "Humanoid") then
                            return f
                        end
                    else
                        return f
                    end
                end
            end
        end
        return nil
    end)
    if ok then
        return res
    end
    return nil
end

function SpeedBypass:InitHook()
    if self.Hooked then
        return true
    end
    if not getgc then
        warn("[Quantum Hub] SpeedBypass missing getgc")
        return false
    end
    if not hookfunction then
        warn("[Quantum Hub] SpeedBypass missing hookfunction")
        return false
    end
    if not islclosure then
        warn("[Quantum Hub] SpeedBypass missing islclosure")
        return false
    end
    local func3
    pcall(function()
        local gc = self:CollectGC()
        if not gc then
            return
        end
        for _, f in pairs(gc) do
            if typeof(f) == "function" and islclosure(f) then
                local upvs = debug.getupvalues(f)
                local line = debug.info(f, "l")
                if upvs and #upvs == 19 and line == 640 then
                    func3 = f
                    break
                end
            end
        end
    end)
    if not func3 then
        warn("[Quantum Hub] SpeedBypass: target function (19 upvalues, line 640) not found")
        return false
    end
    local v7 = nil
    pcall(function()
        v7 = debug.getupvalue(func3, 2)
    end)
    if not v7 then
        warn("[Quantum Hub] SpeedBypass: upvalue 2 missing")
        return false
    end
    local hooked
    hooked = self:SafeHook(v7, function(p1, p2)
        if p2 and typeof(p2) == "table" then
            pcall(function()
                setmetatable(p2, {})
            end)
        end
        return hooked(p1, p2)
    end)
    if not hooked then
        return false
    end
    self.Hooked = true
    return true
end

function SpeedBypass:Toggle(state)
    self.Enabled = state and true or false
    if self.Enabled then
        local okHook = false
        pcall(function()
            okHook = self:InitHook()
        end)
        if not okHook then
            warn("[Quantum Hub] SpeedBypass hook failed, WalkSpeed only")
        end
        if self.SpeedConn then
            pcall(function()
                self.SpeedConn:Disconnect()
            end)
            self.SpeedConn = nil
        end
        local ok, conn = pcall(function()
            return RunService.Heartbeat:Connect(function()
                if not self.Enabled then
                    return
                end
                -- Yield while AutoSteal drives movement (it sets WalkSpeed itself).
                if AutoSteal.StealDriving then
                    return
                end
                local char = LocalPlayer.Character
                if not char then
                    return
                end
                local hum = char:FindFirstChildOfClass("Humanoid")
                if not hum then
                    return
                end
                local want = tonumber(self.WalkSpeed) or 500
                if self.SafeMode and want > 500 then
                    want = 500
                end
                pcall(function()
                    hum.WalkSpeed = want
                end)
            end)
        end)
        if ok and conn then
            self.SpeedConn = TrackConnection(conn)
        end
    else
        if self.SpeedConn then
            pcall(function()
                self.SpeedConn:Disconnect()
            end)
            self.SpeedConn = nil
        end
        pcall(function()
            local hum = GetHumanoid()
            if hum then
                hum.WalkSpeed = 16
            end
        end)
    end
end

-- Glide -----------------------------------------------------------
-- (assigned, not re-declared: forward-declared above for AutoSteal)
Glide = {
    Enabled = false,
    Speed = 50,
    BV = nil,
}

function Glide:Toggle(state)
    self.Enabled = state and true or false
    if self.BV then
        pcall(function()
            self.BV:Destroy()
        end)
        self.BV = nil
    end
    if self.Enabled then
        local hrp = GetHRP()
        if not hrp then
            warn("[Quantum Hub] Glide: no HumanoidRootPart")
            return
        end
        local ok, bv = pcall(function()
            local b = Instance.new("BodyVelocity")
            b.MaxForce = Vector3.new(0, 1e5, 0)
            b.Velocity = Vector3.new(0, -(tonumber(self.Speed) or 50) * 0.1, 0)
            b.Parent = hrp
            return b
        end)
        if ok and bv then
            self.BV = bv
        end
    end
end

function Glide:Refresh()
    if self.Enabled and self.BV then
        -- Yield while AutoSteal drives the same BodyVelocity (hover hold).
        if AutoSteal.StealDriving then
            return
        end
        pcall(function()
            local hrp = GetHRP()
            if not hrp then
                return
            end
            if self.BV.Parent ~= hrp then
                self.BV.Parent = hrp
            end
            self.BV.Velocity = Vector3.new(0, -(tonumber(self.Speed) or 50) * 0.1, 0)
        end)
    end
end

-- Blink -----------------------------------------------------------
-- (assigned, not re-declared: forward-declared above for AutoSteal)
Blink = {
    Enabled = false,
    Distance = 20,
    LastBlink = 0,
}

function Blink:Toggle(state)
    self.Enabled = state and true or false
end

function Blink:BlinkNow()
    if tick() - (self.LastBlink or 0) < 0.5 then
        return
    end
    self.LastBlink = tick()
    pcall(function()
        local hrp = GetHRP()
        if not hrp then
            return
        end
        local d = math.clamp(tonumber(self.Distance) or 20, 5, 100)
        hrp.CFrame = hrp.CFrame + (hrp.CFrame.LookVector * d)
    end)
end

-- Fly -------------------------------------------------------------
-- (assigned, not re-declared: forward-declared above for AutoSteal)
Fly = {
    Enabled = false,
    Speed = 50,
    BV = nil,
    FlyConn = nil,
}

function Fly:Toggle(state)
    self.Enabled = state and true or false
    if self.BV then
        pcall(function()
            self.BV:Destroy()
        end)
        self.BV = nil
    end
    if self.FlyConn then
        pcall(function()
            self.FlyConn:Disconnect()
        end)
        self.FlyConn = nil
    end
    if self.Enabled then
        local hrp = GetHRP()
        if not hrp then
            warn("[Quantum Hub] Fly: no HumanoidRootPart")
            return
        end
        local ok, bv = pcall(function()
            local b = Instance.new("BodyVelocity")
            b.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            b.Velocity = Vector3.new(0, 0, 0)
            b.Parent = hrp
            return b
        end)
        if ok and bv then
            self.BV = bv
        else
            return
        end
        local ok2, conn = pcall(function()
            return RunService.RenderStepped:Connect(function()
                if not self.Enabled or not self.BV then
                    return
                end
                -- Yield while AutoSteal drives the same BodyVelocity.
                if AutoSteal.StealDriving then
                    return
                end
                local hrpNow = GetHRP()
                if not hrpNow then
                    return
                end
                if self.BV.Parent ~= hrpNow then
                    self.BV.Parent = hrpNow
                end
                local cam = Workspace.CurrentCamera
                if not cam then
                    return
                end
                local speed = tonumber(self.Speed) or 50
                local dir = Vector3.new(0, 0, 0)
                pcall(function()
                    local cf = cam.CFrame
                    local forward = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
                    if forward.Magnitude > 0 then
                        forward = forward.Unit
                    end
                    local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
                    if right.Magnitude > 0 then
                        right = right.Unit
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                        dir = dir + forward
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                        dir = dir - forward
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                        dir = dir + right
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                        dir = dir - right
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                        dir = dir + Vector3.new(0, 1, 0)
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                        dir = dir - Vector3.new(0, 1, 0)
                    end
                    if dir.Magnitude > 0 then
                        dir = dir.Unit * speed
                    end
                end)
                pcall(function()
                    self.BV.Velocity = dir
                end)
            end)
        end)
        if ok2 and conn then
            self.FlyConn = TrackConnection(conn)
        end
    end
end

-- Teleport --------------------------------------------------------
local Teleport = {
    Location = "Base",
    Custom = "0,0,0",
}

function Teleport:TeleportNow()
    local dest = nil
    pcall(function()
        if self.Location == "Custom" then
            dest = ParseXYZ(self.Custom)
            if not dest then
                warn("[Quantum Hub] Teleport: bad Custom X,Y,Z: " .. tostring(self.Custom))
                return
            end
        else
            dest = TeleportLocations[self.Location]
            if not dest then
                dest = BASE_CFRAME
            end
        end
    end)
    if not dest then
        return
    end
    pcall(function()
        local hrp = GetHRP()
        if hrp then
            hrp.CFrame = dest
        else
            local char = GetCharacter()
            if char then
                char:MoveTo(dest.Position)
            end
        end
    end)
end

-- AutoTreadmill -----------------------------------------------------
-- Stand-on-treadmill loop. Teleports once onto the treadmill pad and lets
-- the game magnet you on (no walk loop). AutoSteal pauses this while
-- stealing and resumes it afterwards.
-- TODO: adjust treadmill pad name matching if this game names it differently.
-- (assigned, not re-declared: forward-declared above for AutoSteal)
AutoTreadmill = {
    Enabled = false,
    Token = 0,
    TreadmillCF = nil,
    WasEnabled = false,
    PausedBySteal = false,
}

function AutoTreadmill:FindTreadmill()
    local ok, res = pcall(function()
        for _, v in ipairs(Workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                local n = string.lower(v.Name)
                if string.find(n, "treadmill", 1, true) then
                    return v.CFrame + Vector3.new(0, 3, 0)
                end
            end
        end
        return nil
    end)
    if ok then
        return res
    end
    return nil
end

function AutoTreadmill:Pause()
    if self.Enabled then
        self.WasEnabled = true
        self.PausedBySteal = true
        self.Enabled = false
        self.Token = self.Token + 1
        warn("[Quantum Hub] AutoTreadmill paused (steal running)")
    end
end

function AutoTreadmill:Resume()
    if self.PausedBySteal then
        self.PausedBySteal = false
        if self.WasEnabled then
            self.WasEnabled = false
            self:Toggle(true)
        end
    end
end

function AutoTreadmill:Toggle(state)
    self.Enabled = state and true or false
    if self.Enabled then
        self.WasEnabled = false
        self.PausedBySteal = false
        local cf = self:FindTreadmill()
        if cf then
            self.TreadmillCF = cf
        end
        if not self.TreadmillCF then
            warn("[Quantum Hub] AutoTreadmill: pad not found")
            if Notify then
                Notify("Treadmill: pad not found")
            end
            self.Enabled = false
            return
        end
        self.Token = self.Token + 1
        local myToken = self.Token
        if Notify then
            Notify("AutoTreadmill enabled")
        end
        task.spawn(function()
            while self.Enabled and myToken == self.Token do
                pcall(function()
                    local hrp = GetHRP()
                    if hrp and self.TreadmillCF then
                        if (self.TreadmillCF.Position - hrp.Position).Magnitude > 8 then
                            hrp.CFrame = self.TreadmillCF
                        end
                    end
                end)
                task.wait(1)
            end
        end)
    else
        self.Token = self.Token + 1
    end
end

-- AntiTrap ----------------------------------------------------------
-- Neuters trap touch-interest: traps are BaseParts named Hitbox under
-- workspace.__DEBRIS. Suppress CanTouch/CanQuery (never destroy), restore
-- on disable. Ported from friend reference (no executor functions needed).
local AntiTrap = {
    Enabled = false,
    Conn = nil,
}

local function AntiTrapSweep(state)
    pcall(function()
        local debris = Workspace:FindFirstChild("__DEBRIS")
        if not debris then
            return
        end
        for _, v in ipairs(debris:GetDescendants()) do
            if v:IsA("BasePart") and v.Name == "Hitbox" then
                v.CanTouch = state
                v.CanQuery = state
            end
        end
    end)
end

function AntiTrap:Toggle(state)
    self.Enabled = state and true or false
    if self.Conn then
        pcall(function()
            self.Conn:Disconnect()
        end)
        self.Conn = nil
    end
    if self.Enabled then
        AntiTrapSweep(false)
        local ok, conn = pcall(function()
            local debris = Workspace:WaitForChild("__DEBRIS", 10)
            return debris.DescendantAdded:Connect(function(v)
                task.wait(0.1)
                pcall(function()
                    if v and v.Parent and v:IsA("BasePart") and v.Name == "Hitbox" then
                        v.CanTouch = false
                        v.CanQuery = false
                    end
                end)
            end)
        end)
        if ok and conn then
            self.Conn = TrackConnection(conn)
            if Notify then
                Notify("Anti-Trap enabled")
            end
        else
            warn("[Quantum Hub] AntiTrap: no __DEBRIS (" .. tostring(conn) .. ")")
        end
    else
        AntiTrapSweep(true)
    end
end

-- AntiAFK -----------------------------------------------------------
local AntiAFK = {
    Enabled = false,
    Conn = nil,
}

function AntiAFK:Toggle(state)
    self.Enabled = state and true or false
    if self.Conn then
        pcall(function()
            self.Conn:Disconnect()
        end)
        self.Conn = nil
    end
    if self.Enabled then
        local ok, conn = pcall(function()
            local vu = game:GetService("VirtualUser")
            return LocalPlayer.Idled:Connect(function()
                pcall(function()
                    vu:CaptureController()
                    vu:ClickButton2(Vector2.new())
                end)
            end)
        end)
        if ok and conn then
            self.Conn = TrackConnection(conn)
            if Notify then
                Notify("Anti AFK enabled")
            end
        else
            warn("[Quantum Hub] AntiAFK failed: " .. tostring(conn))
            self.Enabled = false
        end
    end
end

-- GraphicsOpt -------------------------------------------------------
-- Reversible client-side low-graphics toggle (save on enable, restore
-- on disable, everything pcall-wrapped).
local GraphicsOpt = {
    Low = false,
    Saved = {},
}

function GraphicsOpt:ApplyLow()
    pcall(function()
        local L = game:GetService("Lighting")
        self.Saved.GlobalShadows = L.GlobalShadows
        self.Saved.Technology = L.Technology
        self.Saved.Brightness = L.Brightness
        L.GlobalShadows = false
        pcall(function()
            L.Technology = Enum.Technology.Compatibility
        end)
        L.Brightness = 1
        for _, v in ipairs(L:GetChildren()) do
            if v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("SunRaysEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("ColorCorrectionEffect") then
                self.Saved[v] = v.Enabled
                v.Enabled = false
            end
        end
    end)
    pcall(function()
        self.Saved.Streaming = Workspace.StreamingEnabled
        Workspace.StreamingEnabled = true
    end)
    pcall(function()
        -- TODO: adjust if this client exposes a different quality API.
        local q = settings():GetService("RenderSettings")
        self.Saved.Quality = q.QualityLevel
        q.QualityLevel = Enum.QualityLevel.Level01
    end)
end

function GraphicsOpt:Restore()
    pcall(function()
        local L = game:GetService("Lighting")
        if self.Saved.GlobalShadows ~= nil then
            L.GlobalShadows = self.Saved.GlobalShadows
        end
        if self.Saved.Technology ~= nil then
            L.Technology = self.Saved.Technology
        end
        if self.Saved.Brightness ~= nil then
            L.Brightness = self.Saved.Brightness
        end
        for obj, was in pairs(self.Saved) do
            if typeof(obj) == "Instance" and obj.Parent then
                obj.Enabled = was
            end
        end
    end)
    pcall(function()
        if self.Saved.Streaming ~= nil then
            Workspace.StreamingEnabled = self.Saved.Streaming
        end
    end)
    pcall(function()
        local q = settings():GetService("RenderSettings")
        if self.Saved.Quality ~= nil then
            q.QualityLevel = self.Saved.Quality
        end
    end)
    self.Saved = {}
end

function GraphicsOpt:Toggle(state)
    self.Low = state and true or false
    if self.Low then
        self:ApplyLow()
        if Notify then
            Notify("Low graphics ON")
        end
    else
        self:Restore()
        if Notify then
            Notify("Graphics restored")
        end
    end
end

-- Named levels for the Graphics dropdown. Normal restores everything.
function GraphicsOpt:SetLevel(level)
    if level == "Ultra Low" then
        self:ApplyLow()
        pcall(function()
            -- TODO: adjust if this client streams assets differently.
            for _, v in ipairs(Workspace:GetDescendants()) do
                if v:IsA("BasePart") then
                    pcall(function()
                        v.Material = Enum.Material.SmoothPlastic
                    end)
                elseif v:IsA("Decal") or v:IsA("Texture") then
                    pcall(function()
                        v.Transparency = 1
                    end)
                elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
                    pcall(function()
                        v.Enabled = false
                    end)
                end
            end
        end)
        self.Low = true
        if Notify then
            Notify("Ultra Low graphics ON")
        end
    elseif level == "Low" then
        self:Toggle(true)
    else
        self:Toggle(false)
    end
end

-- PlaceHatch --------------------------------------------------------
-- Deposit + hatch helpers used by AutoSteal after base return (only when
-- the user enables them). Remotes are resolved at runtime from candidate
-- paths because the exact names vary by update.
-- TODO: adjust candidate remote paths to this game's exact names.
-- (assigned, not re-declared: forward-declared above for AutoSteal)
PlaceHatch = {
    PlaceRemotes = { "RF/EggWorld/AskPlaceEgg", "RE/EggWorld/PlaceEgg", "RF/EggWorld/AskPlace" },
    HatchRemotes = { "RF/EggWorld/AskHatch", "RE/EggWorld/HatchEgg", "RF/Hatch/AskHatch" },
}

function PlaceHatch:TryEach(list, isInvoke)
    for _, path in ipairs(list) do
        local remote = getRemote(path)
        if remote then
            if isInvoke then
                local ok = safeInvoke(remote)
                if ok then
                    return true
                end
            else
                if safeFire(remote) then
                    return true
                end
            end
        end
    end
    return false
end

function PlaceHatch:PlaceOnce()
    if self:TryEach(self.PlaceRemotes, true) then
        return true
    end
    return self:TryEach(self.PlaceRemotes, false)
end

function PlaceHatch:HatchOnce()
    if self:TryEach(self.HatchRemotes, true) then
        return true
    end
    return self:TryEach(self.HatchRemotes, false)
end

-- 6. UI construction using the helpers -----------------------------

local Window = createWindow()
if not Window then
    warn("[Quantum Hub] FATAL: window creation failed, aborting")
    return
end
warn("[Quantum Hub] Window created")
local Sidebar = Window.Sidebar
local Content = Window.Content

local MainTab = createTab(Sidebar, Content, "Main", 1)
local AutomationTab = createTab(Sidebar, Content, "Automation", 2)
local StealTab = createTab(Sidebar, Content, "Steal", 3)
local TreadmillTab = createTab(Sidebar, Content, "Treadmill", 4)
local MiscTab = createTab(Sidebar, Content, "Misc", 5)
local SettingsTab = createTab(Sidebar, Content, "Settings", 6)

-- Floating reopen button (mobile): tap toggles the window, drag moves it.
local floatBtn = Instance.new("TextButton")
floatBtn.Name = "FloatToggle"
floatBtn.Size = UDim2.new(0, 56, 0, 56)
floatBtn.Position = UDim2.new(1, -70, 1, -150)
floatBtn.Text = "QH"
floatBtn.Font = Enum.Font.GothamBold
floatBtn.TextSize = 16
floatBtn.ZIndex = 500
floatBtn.BackgroundColor3 = Theme.Accent
floatBtn.TextColor3 = Theme.ButtonText
floatBtn.AutoButtonColor = true
floatBtn.BorderSizePixel = 0
floatBtn.Parent = Window.Gui
ApplyCorner(floatBtn, 28)
ApplyStroke(floatBtn, Theme.Outline, 1)
do
    local downPos, startPos, draggingFloat = nil, nil, false
    floatBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            downPos = input.Position
            startPos = floatBtn.Position
            draggingFloat = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if downPos and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - downPos
            if delta.Magnitude > 12 then
                draggingFloat = true
                pcall(function()
                    floatBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
                end)
            end
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if downPos and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            if not draggingFloat then
                CloseAllDropdowns()
                Window.Main.Visible = not Window.Main.Visible
            end
            downPos, draggingFloat = nil, false
        end
    end)
end

-- Tab 1: Main (Combat)
SectionLabel(MainTab, "Combat")
createDropdown(MainTab, "Kill Aura Mode", { "Off", "On" }, "Off", function(v)
    KillAura:Toggle(v == "On")
end)
createSlider(MainTab, "Range", 5, 30, 16.5, function(v)
    KillAura.Range = v
end)
createDropdown(MainTab, "Priority", { "Nearest", "Lowest Health", "Random", "Highest Health" }, "Nearest", function(v)
    KillAura.Priority = v
end)
createSlider(MainTab, "Attack Delay", 0.05, 0.5, 0.1, function(v)
    KillAura.AttackDelay = v
end)
createDropdown(MainTab, "Knockback Protection", { "Off", "On" }, "Off", function(v)
    NoKnockback:Toggle(v == "On")
end)
createToggle(MainTab, "Instant Interact", true, function(v)
    InstantInteract:Toggle(v)
end)

-- Tab 2: Automation
SectionLabel(AutomationTab, "Auto Buy")
createDropdown(AutomationTab, "Auto Buy", { "Off", "On" }, "Off", function(v)
    AutoBuy:Toggle(v == "On")
end)
local buySetters = {}
createDropdown(AutomationTab, "Buy Set", { "All", "Treadmills Only", "Bases Only", "Trails Only", "Treadmills+Bases", "Treadmills+Trails", "Bases+Trails" }, "All", function(v)
    local t, b, tr = true, true, true
    if v == "Treadmills Only" then
        b, tr = false, false
    elseif v == "Bases Only" then
        t, tr = false, false
    elseif v == "Trails Only" then
        t, b = false, false
    elseif v == "Treadmills+Bases" then
        tr = false
    elseif v == "Treadmills+Trails" then
        b = false
    elseif v == "Bases+Trails" then
        t = false
    end
    AutoBuy.BuyTreadmills, AutoBuy.BuyBases, AutoBuy.BuyTrails = t, b, tr
    if buySetters.Treadmills then
        pcall(buySetters.Treadmills, t)
    end
    if buySetters.Bases then
        pcall(buySetters.Bases, b)
    end
    if buySetters.Trails then
        pcall(buySetters.Trails, tr)
    end
end)
do
    local _, s1 = createCheckbox(AutomationTab, "Treadmills", true, function(v)
        AutoBuy.BuyTreadmills = v
    end)
    buySetters.Treadmills = s1
    local _, s2 = createCheckbox(AutomationTab, "Bases", true, function(v)
        AutoBuy.BuyBases = v
    end)
    buySetters.Bases = s2
    local _, s3 = createCheckbox(AutomationTab, "Trails", true, function(v)
        AutoBuy.BuyTrails = v
    end)
    buySetters.Trails = s3
end
createSlider(AutomationTab, "Max Spend per Cycle", 0, 1000000000, 1000000, function(v)
    AutoBuy.MaxSpend = v
end)
createSlider(AutomationTab, "Buy Interval", 0.1, 2, 0.5, function(v)
    AutoBuy.BuyInterval = v
end)

SectionLabel(AutomationTab, "Auto Sell")
createDropdown(AutomationTab, "Auto Sell", { "Off", "On" }, "Off", function(v)
    AutoSell:Toggle(v == "On")
end)
local sellSetters = {}
local function ApplySellSet(set)
    for r, want in pairs(set) do
        AutoSell.Rarities[r] = want
        if sellSetters[r] then
            pcall(sellSetters[r], want)
        end
    end
end
createDropdown(AutomationTab, "Sell Preset", { "Junk Only (no Mythic)", "Standard (no Mythic)", "All incl Mythic", "Sell Nothing" }, "Junk Only (no Mythic)", function(v)
    if v == "Standard (no Mythic)" then
        ApplySellSet({ Common = true, Uncommon = true, Rare = true, Epic = true, Legendary = true, Mythic = false })
    elseif v == "All incl Mythic" then
        ApplySellSet({ Common = true, Uncommon = true, Rare = true, Epic = true, Legendary = true, Mythic = true })
    elseif v == "Sell Nothing" then
        ApplySellSet({ Common = false, Uncommon = false, Rare = false, Epic = false, Legendary = false, Mythic = false })
    else
        ApplySellSet({ Common = true, Uncommon = true, Rare = true, Epic = false, Legendary = false, Mythic = false })
    end
end)
for _, rarity in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }) do
    local r = rarity
    local def = (r ~= "Epic" and r ~= "Legendary" and r ~= "Mythic")
    AutoSell.Rarities[r] = def
    local _, setFn = createCheckbox(AutomationTab, r, def, function(v)
        AutoSell.Rarities[r] = v
    end)
    sellSetters[r] = setFn
end

SectionLabel(AutomationTab, "Auto Farm")
createDropdown(AutomationTab, "Auto Farm", { "Off", "On" }, "Off", function(v)
    AutoFarm:Toggle(v == "On")
end)
createDropdown(AutomationTab, "Farm Area Floor", { "Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano", "Abyss Ocean", "Prehistoric", "Cosmic", "Cherry Blossom", "Titan Temple", "Light Dark" }, "Cherry Blossom", function(v)
    AutoFarm.MinArea = table.find(AutoFarm.Areas, v) or 1
end)
createDropdown(AutomationTab, "Farm Return", { "Return to Base", "Stay in Field" }, "Return to Base", function(v)
    AutoFarm.ReturnToBase = (v == "Return to Base")
end)
createSlider(AutomationTab, "Farm Speed", 100, 5000, 1500, function(v)
    AutoFarm.GoSpeed = v
end)
createSlider(AutomationTab, "Cycle Delay", 1, 20, 1.5, function(v)
    AutoFarm.CycleDelay = v
end)

SectionLabel(AutomationTab, "Auto Redeem Index")
createDropdown(AutomationTab, "Auto Redeem", { "Off", "On" }, "Off", function(v)
    AutoRedeem:Toggle(v == "On")
end)
createDropdown(AutomationTab, "Redeem Interval", { "1s Turbo", "2s Safe", "5s Slow" }, "1s Turbo", function(v)
    if v == "2s Safe" then
        AutoRedeem.Interval = 2
    elseif v == "5s Slow" then
        AutoRedeem.Interval = 5
    else
        AutoRedeem.Interval = 1
    end
end)

-- Tab 3: Steal (Auto Steal)
SectionLabel(StealTab, "Auto Steal")
createDropdown(StealTab, "Auto Steal", { "Off", "Instant Return to Base", "Return + Re-engage", "Stay (no return)" }, "Off", function(v)
    if v == "Off" then
        AutoSteal:Toggle(false)
    else
        AutoSteal.ReturnToBase = (v ~= "Stay (no return)")
        AutoSteal.GoBackOut = (v == "Return + Re-engage")
        AutoSteal:Toggle(true)
    end
end)
createDropdown(StealTab, "Pickup Mode", { "Instant (Hold=0)", "Normal" }, "Instant (Hold=0)", function(v)
    InstantInteract:Toggle(v == "Instant (Hold=0)")
end)
createCheckbox(StealTab, "Secret First (any mode)", false, function(v)
    AutoSteal.SecretFirst = v
end)
createButton(StealTab, "Steal Now (one grab)", function()
    pcall(function()
        if not AutoSteal.Enabled then
            AutoSteal:Toggle(true)
        else
            task.spawn(function()
                pcall(function()
                    AutoSteal:StealOnce()
                end)
            end)
        end
    end)
end)
createButton(StealTab, "Stop Current Steal", function()
    AutoSteal.Token = AutoSteal.Token + 1
    AutoSteal:StopMovement()
    if Notify then
        Notify("Steal stopped")
    end
end)
pcall(function()
    InstantInteract:Toggle(true)
end)
-- Forward declarations: visibility updaters are defined after the panels.
local UpdateStealVisibility, UpdateMovementBox
createDropdown(StealTab, "Steal On", { "Rarity", "Best Value", "Weight-Size" }, "Rarity", function(v)
    AutoSteal.FilterMode = v
    if UpdateStealVisibility then
        UpdateStealVisibility()
    end
end)
createSlider(StealTab, "Scan Radius", 50, 10000, 1500, function(v)
    AutoSteal.ScanRadius = v
end)
createSlider(StealTab, "Cycle Delay", 0.5, 10, 1.5, function(v)
    AutoSteal.CycleDelay = v
end)
createCheckbox(StealTab, "Return to Base", true, function(v)
    AutoSteal.ReturnToBase = v
end)
createCheckbox(StealTab, "Go Back Out", true, function(v)
    AutoSteal.GoBackOut = v
end)
createCheckbox(StealTab, "Auto Place (after base)", false, function(v)
    AutoSteal.PlaceEnabled = v
end)
createCheckbox(StealTab, "Auto Hatch (when ready)", false, function(v)
    AutoSteal.HatchEnabled = v
end)
createButton(StealTab, "Place Eggs Now", function()
    pcall(function()
        PlaceHatch:PlaceOnce()
    end)
end)
createButton(StealTab, "Hatch Now", function()
    pcall(function()
        PlaceHatch:HatchOnce()
    end)
end)

SectionLabel(StealTab, "Area (empty = all areas)")
-- TODO: adjust area list if this game adds/removes biomes.
local areaBox = Instance.new("Frame")
areaBox.Name = "AreaBox"
areaBox.Size = UDim2.new(1, 0, 0, 0)
areaBox.AutomaticSize = Enum.AutomaticSize.Y
areaBox.BackgroundTransparency = 1
areaBox.Parent = StealTab
local areaLayout = Instance.new("UIListLayout")
areaLayout.Padding = UDim.new(0, 4)
areaLayout.SortOrder = Enum.SortOrder.LayoutOrder
areaLayout.Parent = areaBox
local areaSetters = {}
for _, aname in ipairs({ "Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano", "Abyss Ocean", "Prehistoric", "Cosmic", "Cherry Blossom", "Titan Temple", "Light Dark" }) do
    local an = aname
    AutoSteal.AreaAllow[an] = true
    local _, setFn = createCheckbox(areaBox, an, true, function(v)
        if v then
            AutoSteal.AreaAllow[an] = true
        else
            AutoSteal.AreaAllow[an] = false
        end
    end)
    areaSetters[an] = setFn
end
createDropdown(StealTab, "Area Preset", { "All Areas", "High Tier Only (Cosmic+)", "Cherry+Titan+LightDark", "Custom" }, "All Areas", function(v)
    if v == "Custom" then
        return
    end
    local want = {}
    if v == "All Areas" then
        want = nil -- empty = allow all
    elseif v == "High Tier Only (Cosmic+)" then
        want = { Cosmic = true, ["Cherry Blossom"] = true, ["Titan Temple"] = true, ["Light Dark"] = true }
    elseif v == "Cherry+Titan+LightDark" then
        want = { ["Cherry Blossom"] = true, ["Titan Temple"] = true, ["Light Dark"] = true }
    end
    AutoSteal.AreaAllow = {}
    for an, setFn in pairs(areaSetters) do
        local on = (want == nil) or (want[an] == true)
        if on then
            AutoSteal.AreaAllow[an] = true
        end
        pcall(setFn, on)
    end
    AutoSteal:RefreshPreview()
end)

SectionLabel(StealTab, "Movement")
createDropdown(StealTab, "Movement Method", { "Walk", "Glide", "Blink", "Fly" }, "Fly", function(v)
    AutoSteal.MovementMethod = v
    if UpdateMovementBox then
        UpdateMovementBox()
    end
end)
local moveBox = Instance.new("Frame")
moveBox.Name = "MoveBox"
moveBox.Size = UDim2.new(1, 0, 0, 0)
moveBox.AutomaticSize = Enum.AutomaticSize.Y
moveBox.BackgroundTransparency = 1
moveBox.Parent = StealTab
local moveLayout = Instance.new("UIListLayout")
moveLayout.Padding = UDim.new(0, 6)
moveLayout.SortOrder = Enum.SortOrder.LayoutOrder
moveLayout.Parent = moveBox
local walkCtl, walkApply = createSlider(moveBox, "Walk Speed", 100, 1500, 500, function(v)
    AutoSteal.MoveSpeed = v
end)
local flyCtl, flyApply = createSlider(moveBox, "Fly Speed", 100, 1500, 800, function(v)
    Fly.Speed = v
    AutoSteal.MoveSpeed = v
end)
local blinkCtl, blinkApply = createSlider(moveBox, "Blink Distance", 100, 1500, 100, function(v)
    AutoSteal.BlinkDistance = v
end)
local glideCtl, glideApply = createSlider(moveBox, "Glide Speed", 100, 1500, 800, function(v)
    Glide.Speed = v
    AutoSteal.MoveSpeed = v
end)
createSlider(moveBox, "Fly Hover Height", 0, 300, 12, function(v)
    AutoSteal.HoverHeight = v
end)
UpdateMovementBox = function()
    local m = AutoSteal.MovementMethod or "Fly"
    walkCtl.Visible = (m == "Walk")
    flyCtl.Visible = (m == "Fly")
    blinkCtl.Visible = (m == "Blink")
    glideCtl.Visible = (m == "Glide")
end
UpdateMovementBox()

SectionLabel(StealTab, "Anti-Clamp (serves steal speed)")
createToggle(StealTab, "Speed Bypass", false, function(v)
    SpeedBypass:Toggle(v)
end)
local bypassCtl, bypassApply = createSlider(StealTab, "Bypass Speed", 100, 1500, 1500, function(v)
    SpeedBypass.WalkSpeed = v
end)
createDropdown(StealTab, "Anti-Clamp", { "Off", "Capped 500", "Uncapped" }, "Uncapped", function(v)
    if v == "Off" then
        SpeedBypass:Toggle(false)
    else
        SpeedBypass.SafeMode = (v == "Capped 500")
        SpeedBypass:Toggle(true)
    end
end)
createDropdown(StealTab, "Speed Preset", { "Legit 100", "Fast 500", "Blatant 1000", "Insane 1500" }, "Fast 500", function(v)
    local walk, fly, glide, blink, bypass = 100, 100, 100, 100, 500
    if v == "Legit 100" then
        walk, fly, glide, blink, bypass = 100, 100, 100, 100, 500
    elseif v == "Fast 500" then
        walk, fly, glide, blink, bypass = 500, 500, 500, 300, 1000
    elseif v == "Blatant 1000" then
        walk, fly, glide, blink, bypass = 1000, 1000, 1000, 800, 1500
    elseif v == "Insane 1500" then
        walk, fly, glide, blink, bypass = 1500, 1500, 1500, 1500, 1500
    end
    AutoSteal.MoveSpeed = walk
    Fly.Speed = fly
    Glide.Speed = glide
    AutoSteal.BlinkDistance = blink
    Blink.Distance = blink
    SpeedBypass.WalkSpeed = bypass
    pcall(walkApply, walk)
    pcall(flyApply, fly)
    pcall(glideApply, glide)
    pcall(blinkApply, blink)
    pcall(bypassApply, bypass)
    if Notify then
        Notify("Speed preset: " .. tostring(v))
    end
end)

SectionLabel(StealTab, "Travel (manual jumps)")
createDropdown(StealTab, "Location", { "Base", "Forest", "Lake", "Desert", "Custom" }, "Base", function(v)
    Teleport.Location = v
end)
createTextbox(StealTab, "Custom X,Y,Z", "0,0,0", function(v)
    Teleport.Custom = v
end)
createButton(StealTab, "Teleport", function()
    Teleport:TeleportNow()
end)

-- Static egg-type picker: always visible, checked = steal only those,
-- all unchecked = allow all. Discovery extras render below it.
local eggTypeSetters = {}
SectionLabel(StealTab, "Egg Types (unchecked = allow all)")
local eggTypeBox = Instance.new("Frame")
eggTypeBox.Name = "EggTypeBox"
eggTypeBox.Size = UDim2.new(1, 0, 0, 0)
eggTypeBox.AutomaticSize = Enum.AutomaticSize.Y
eggTypeBox.BackgroundTransparency = 1
eggTypeBox.Parent = StealTab
local eggTypeLayout = Instance.new("UIListLayout")
eggTypeLayout.Padding = UDim.new(0, 4)
eggTypeLayout.SortOrder = Enum.SortOrder.LayoutOrder
eggTypeLayout.Parent = eggTypeBox
for _, ename in ipairs(AutoSteal.PinRarities) do
    local en = ename
    local _, setFn = createCheckbox(eggTypeBox, en, false, function(v)
        if v then
            AutoSteal.RarityAllow[en] = true
        else
            AutoSteal.RarityAllow[en] = nil
        end
    end)
    eggTypeSetters[en] = setFn
end

-- Filter context panels: only the active Steal On mode is visible.
local rarityPanel = Instance.new("Frame")
rarityPanel.Name = "RarityPanel"
rarityPanel.Size = UDim2.new(1, 0, 0, 0)
rarityPanel.AutomaticSize = Enum.AutomaticSize.Y
rarityPanel.BackgroundTransparency = 1
rarityPanel.Parent = StealTab
local rarityPanelLayout = Instance.new("UIListLayout")
rarityPanelLayout.Padding = UDim.new(0, 6)
rarityPanelLayout.SortOrder = Enum.SortOrder.LayoutOrder
rarityPanelLayout.Parent = rarityPanel

local valuePanel = Instance.new("Frame")
valuePanel.Name = "ValuePanel"
valuePanel.Size = UDim2.new(1, 0, 0, 0)
valuePanel.AutomaticSize = Enum.AutomaticSize.Y
valuePanel.BackgroundTransparency = 1
valuePanel.Visible = false
valuePanel.Parent = StealTab
local valuePanelLayout = Instance.new("UIListLayout")
valuePanelLayout.Padding = UDim.new(0, 6)
valuePanelLayout.SortOrder = Enum.SortOrder.LayoutOrder
valuePanelLayout.Parent = valuePanel

local weightPanel = Instance.new("Frame")
weightPanel.Name = "WeightPanel"
weightPanel.Size = UDim2.new(1, 0, 0, 0)
weightPanel.AutomaticSize = Enum.AutomaticSize.Y
weightPanel.BackgroundTransparency = 1
weightPanel.Visible = false
weightPanel.Parent = StealTab
local weightPanelLayout = Instance.new("UIListLayout")
weightPanelLayout.Padding = UDim.new(0, 6)
weightPanelLayout.SortOrder = Enum.SortOrder.LayoutOrder
weightPanelLayout.Parent = weightPanel

SectionLabel(rarityPanel, "Rarity (empty = allow all)")
local rarityBox = Instance.new("Frame")
rarityBox.Name = "RarityBox"
rarityBox.Size = UDim2.new(1, 0, 0, 0)
rarityBox.AutomaticSize = Enum.AutomaticSize.Y
rarityBox.BackgroundTransparency = 1
rarityBox.Parent = rarityPanel
local rarityLayout = Instance.new("UIListLayout")
rarityLayout.Padding = UDim.new(0, 4)
rarityLayout.SortOrder = Enum.SortOrder.LayoutOrder
rarityLayout.Parent = rarityBox

SectionLabel(rarityPanel, "Mutation")
local mutationBox = Instance.new("Frame")
mutationBox.Name = "MutationBox"
mutationBox.Size = UDim2.new(1, 0, 0, 0)
mutationBox.AutomaticSize = Enum.AutomaticSize.Y
mutationBox.BackgroundTransparency = 1
mutationBox.Parent = rarityPanel
local mutationLayout = Instance.new("UIListLayout")
mutationLayout.Padding = UDim.new(0, 4)
mutationLayout.SortOrder = Enum.SortOrder.LayoutOrder
mutationLayout.Parent = mutationBox

local function RebuildFilterBox(box, names, allow, skip)
    for _, c in ipairs(box:GetChildren()) do
        if c:IsA("Frame") or c.Name == "EmptyNote" then
            c:Destroy()
        end
    end
    local shown = {}
    for _, fname in ipairs(names) do
        -- Pinned egg types live in the static picker above; never duplicate.
        if skip and table.find(skip, fname) then
            continue
        end
        table.insert(shown, fname)
    end
    if #shown == 0 then
        local l = Instance.new("TextLabel")
        l.Name = "EmptyNote"
        l.Size = UDim2.new(1, 0, 0, 28)
        l.BackgroundTransparency = 1
        l.Text = "None discovered yet — press Refresh Filters in game."
        l.TextColor3 = Theme.TextDim
        l.Font = Enum.Font.Gotham
        l.TextSize = 13
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Parent = box
        return
    end
    for _, fname in ipairs(shown) do
        local fn = fname
        allow[fn] = true
        createCheckbox(box, fn, true, function(v)
            allow[fn] = v and true or false
        end)
    end
end

local function RebuildStealFilters()
    RebuildFilterBox(rarityBox, AutoSteal.DiscoveredRarities, AutoSteal.RarityAllow, AutoSteal.PinRarities)
    RebuildFilterBox(mutationBox, AutoSteal.DiscoveredMutations, AutoSteal.MutationAllow, {})
end

createDropdown(StealTab, "Filter Preset", { "All", "Secrets Only", "Secret+Eternal+Divine", "Mythic+", "Custom" }, "All", function(v)
    if v == "Custom" then
        return
    end
    local want = {}
    if v == "Secrets Only" then
        want = { Secret = true }
    elseif v == "Secret+Eternal+Divine" then
        want = { Secret = true, Eternal = true, Divine = true }
    elseif v == "Mythic+" then
        want = { Mythic = true, Divine = true, Eternal = true, Secret = true, Cosmic = true }
    end
    AutoSteal.RarityAllow = {}
    for _, en in ipairs(AutoSteal.PinRarities) do
        local on = (want[en] == true)
        AutoSteal.RarityAllow[en] = on and true or nil
        if eggTypeSetters[en] then
            pcall(eggTypeSetters[en], on)
        end
    end
    RebuildStealFilters()
    AutoSteal:RefreshPreview()
end)
createDropdown(StealTab, "Value Strategy", { "All Values", "Best Value Only" }, "All Values", function(v)
    AutoSteal.BestValueOnly = (v == "Best Value Only")
end)
createButton(rarityPanel, "Refresh Filters", function()
    AutoSteal:DiscoverFilters()
    RebuildStealFilters()
    AutoSteal:RefreshPreview()
end)
createButton(rarityPanel, "Reset Filters", function()
    AutoSteal.RarityAllow = {}
    AutoSteal.MutationAllow = {}
    AutoSteal.AreaAllow = {}
    AutoSteal.MinValue = 0
    AutoSteal.MaxValue = 1000000000
    AutoSteal.MinWeight = 0
    AutoSteal.MaxWeight = 1000000
    AutoSteal.BestValueOnly = false
    for _, fn in pairs(eggTypeSetters) do
        pcall(fn, false)
    end
    for _, fn in pairs(areaSetters) do
        pcall(fn, false)
    end
    RebuildStealFilters()
    AutoSteal:RefreshPreview()
end)
createCheckbox(valuePanel, "Best Value Only", false, function(v)
    AutoSteal.BestValueOnly = v
end)
createSlider(valuePanel, "Min Value", 0, 1000000000, 0, function(v)
    AutoSteal.MinValue = v
end)
createSlider(valuePanel, "Max Value", 0, 1000000000, 1000000000, function(v)
    AutoSteal.MaxValue = v
end)
createSlider(weightPanel, "Min Weight", 0, 1000000, 0, function(v)
    AutoSteal.MinWeight = v
end)
createSlider(weightPanel, "Max Weight", 0, 1000000, 1000000, function(v)
    AutoSteal.MaxWeight = v
end)

UpdateStealVisibility = function()
    local mode = AutoSteal.FilterMode or "Rarity"
    rarityPanel.Visible = (mode == "Rarity")
    valuePanel.Visible = (mode == "Best Value")
    weightPanel.Visible = (mode == "Weight-Size")
end
UpdateStealVisibility()

SectionLabel(StealTab, "Preview (matching eggs)")
local previewLabel = Instance.new("TextLabel")
previewLabel.Name = "StealPreview"
previewLabel.Size = UDim2.new(1, 0, 0, 140)
previewLabel.BackgroundColor3 = Theme.Panel
previewLabel.BorderSizePixel = 0
previewLabel.Text = "Press Refresh Preview."
previewLabel.TextColor3 = Theme.Text
previewLabel.Font = Enum.Font.Gotham
previewLabel.TextSize = 13
previewLabel.TextWrapped = true
previewLabel.TextXAlignment = Enum.TextXAlignment.Left
previewLabel.TextYAlignment = Enum.TextYAlignment.Top
previewLabel.Parent = StealTab
ApplyCorner(previewLabel, 8)
ApplyStroke(previewLabel, Theme.Outline, 1)
local previewPad = Instance.new("UIPadding")
previewPad.PaddingTop = UDim.new(0, 8)
previewPad.PaddingBottom = UDim.new(0, 8)
previewPad.PaddingLeft = UDim.new(0, 8)
previewPad.PaddingRight = UDim.new(0, 8)
previewPad.Parent = previewLabel
AutoSteal.PreviewLabel = previewLabel
createButton(StealTab, "Refresh Preview", function()
    AutoSteal:RefreshPreview()
end)
pcall(function()
    AutoSteal:DiscoverFilters()
end)
RebuildStealFilters()
pcall(function()
    AutoSteal:RefreshPreview()
end)

-- Tab 4: Treadmill (Auto Treadmill)
SectionLabel(TreadmillTab, "Auto Treadmill")
createDropdown(TreadmillTab, "Auto Treadmill", { "Off", "On" }, "Off", function(v)
    AutoTreadmill:Toggle(v == "On")
end)
createButton(TreadmillTab, "Find Treadmill Pad", function()
    local cf = AutoTreadmill:FindTreadmill()
    if cf then
        AutoTreadmill.TreadmillCF = cf
        if Notify then
            Notify("Treadmill pad locked")
        end
    else
        warn("[Quantum Hub] Treadmill pad not found")
        if Notify then
            Notify("Treadmill pad not found")
        end
    end
end)

-- Tab 5: Misc
SectionLabel(MiscTab, "Session")
createDropdown(MiscTab, "Anti AFK", { "Off", "On" }, "On", function(v)
    AntiAFK:Toggle(v == "On")
end)
pcall(function()
    AntiAFK:Toggle(true)
end)
SectionLabel(MiscTab, "Protection")
createDropdown(MiscTab, "Anti-Trap", { "Off", "On" }, "Off", function(v)
    AntiTrap:Toggle(v == "On")
end)
SectionLabel(MiscTab, "Client Graphics (reversible)")
createDropdown(MiscTab, "Graphics", { "Normal", "Low", "Ultra Low" }, "Normal", function(v)
    GraphicsOpt:SetLevel(v)
end)

-- Tab 6: Settings
SectionLabel(SettingsTab, "Settings")
createDropdown(SettingsTab, "UI Scale", { "Auto", "Small", "Medium", "Large" }, "Auto", function(v)
    Window.SetScaleMode(v)
end)
createButton(SettingsTab, "Unload Quantum Hub", function()
    pcall(function()
        DisconnectAll()
    end)
    pcall(function()
        if InstantInteract.Conn then
            InstantInteract.Conn:Disconnect()
        end
    end)
    pcall(function()
        if SpeedBypass.SpeedConn then
            SpeedBypass.SpeedConn:Disconnect()
        end
    end)
    pcall(function()
        if Fly.FlyConn then
            Fly.FlyConn:Disconnect()
        end
    end)
    pcall(function()
        if Glide.BV then
            Glide.BV:Destroy()
        end
    end)
    pcall(function()
        if Fly.BV then
            Fly.BV:Destroy()
        end
    end)
    pcall(function()
        AutoBuy.Enabled = false
        AutoSell.Enabled = false
        AutoFarm.Enabled = false
        AutoFarm.PausedBySteal = false
        AutoFarm.WasEnabled = false
        AutoRedeem.Enabled = false
        AutoSteal.Enabled = false
        AutoSteal.StealDriving = false
        KillAura.Enabled = false
        SpeedBypass.Enabled = false
        Glide.Enabled = false
        Fly.Enabled = false
        Blink.Enabled = false
    end)
    pcall(function()
        AutoFarm.Token = AutoFarm.Token + 1
        AutoRedeem.Token = AutoRedeem.Token + 1
        AutoSteal.Token = AutoSteal.Token + 1
        AutoSteal:StopMovement()
        AutoTreadmill.Enabled = false
        AutoTreadmill.Token = AutoTreadmill.Token + 1
        AntiAFK:Toggle(false)
        AntiTrap:Toggle(false)
        GraphicsOpt:Restore()
    end)
    pcall(function()
        Window.Gui:Destroy()
    end)
    warn("[Quantum Hub] Unloaded.")
end)

-- 7. Loops (RunService.Heartbeat, task.spawn polling loops) --------

TrackConnection(RunService.Heartbeat:Connect(function()
    pcall(function()
        KillAura:Run()
    end)
    pcall(function()
        Glide:Refresh()
    end)
end))

-- AutoBuy loop (interval configurable)
task.spawn(function()
    while true do
        task.wait(tonumber(AutoBuy.BuyInterval) or 0.5)
        pcall(function()
            if AutoBuy.Enabled then
                AutoBuy:Run()
            end
        end)
    end
end)

-- Secret / Eternal / Divine field notifier every 1.5s (edge-triggered).
task.spawn(function()
    local lastCount = 0
    while true do
        task.wait(1.5)
        pcall(function()
            AutoSteal:EnsureData()
            if not AutoSteal.EggState then
                return
            end
            local ok, field = pcall(function()
                return AutoSteal.EggState.ReadFieldEggs()
            end)
            if not ok or not field or not field.Records then
                return
            end
            local n = 0
            for _, egg in pairs(field.Records) do
                local r = AutoSteal:ResolveRarity(egg)
                if r == "Secret" or r == "Eternal" or r == "Divine" then
                    n = n + 1
                end
            end
            if n > 0 and n ~= lastCount and Notify then
                Notify("Secret/Eternal/Divine in field: " .. tostring(n))
            end
            lastCount = n
        end)
    end
end)

-- AutoSell loop every 1s
task.spawn(function()
    while true do
        task.wait(1)
        pcall(function()
            if AutoSell.Enabled then
                AutoSell:Run()
            end
        end)
    end
end)

-- Re-apply Glide velocity on respawn / movement drift
TrackConnection(RunService.Heartbeat:Connect(function()
    pcall(function()
        if Glide.Enabled and Glide.BV then
            local hrp = GetHRP()
            if hrp and Glide.BV.Parent ~= hrp then
                Glide.BV.Parent = hrp
            end
        end
        if Fly.Enabled and Fly.BV then
            local hrp = GetHRP()
            if hrp and Fly.BV.Parent ~= hrp then
                Fly.BV.Parent = hrp
            end
        end
    end)
end))

-- 8. Toast (Library:Notify equivalent) ------------------------------
Notify = function(text)
    pcall(function()
        local gui = Window and Window.Gui
        if not gui then
            return
        end
        local toast = Instance.new("Frame")
        toast.Size = UDim2.new(0, 260, 0, 44)
        toast.Position = UDim2.new(1, -270, 1, -54)
        toast.BackgroundColor3 = Theme.Panel
        toast.BorderSizePixel = 0
        toast.Parent = gui
        ApplyCorner(toast, 8)
        ApplyStroke(toast, Theme.Accent, 1)

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 10)
        pad.PaddingRight = UDim.new(0, 10)
        pad.PaddingTop = UDim.new(0, 6)
        pad.PaddingBottom = UDim.new(0, 6)
        pad.Parent = toast

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = tostring(text)
        label.TextColor3 = Theme.Text
        label.Font = Enum.Font.Gotham
        label.TextSize = 12
        label.TextWrapped = true
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = toast

        task.spawn(function()
            task.wait(5)
            pcall(function()
                local tw = TweenService:Create(toast, TweenInfo.new(0.5), { BackgroundTransparency = 1 })
                tw:Play()
                pcall(function()
                    local tw2 = TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 })
                    tw2:Play()
                end)
                tw.Completed:Wait()
                toast:Destroy()
            end)
        end)
    end)
end

-- 9. Final print -----------------------------------------------------
print("[Quantum Hub] Loaded.")
