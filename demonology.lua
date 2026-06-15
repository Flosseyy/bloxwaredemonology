--[[
    BloxWare - Demonology (V3)
    Developed for Nathan Lorenzo
    
    Fixes:
    - Fixed Rayfield Slider Syntax error (using Range = {16, 100} instead of Min/Max) to stop the UI from crashing/freezing on "Waiting..."
    - Added Live Ghost Solver (auto-detects spawned evidences in workspace and crosses them out to solve the EXACT Ghost Type)
    - Full Ghost ESP and Overhead Billboard tags showing Ghost skin and distance.
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- State variables
local GhostESP_Enabled = false
local GhostTag_Enabled = false
local FavoriteRoomESP_Enabled = false
local ShowWalls_Enabled = false
local SpeedHack_Enabled = false
local SpeedHack_Value = 25
local InfiniteStamina_Enabled = false
local FullBright_Enabled = false

local HighlightInstance = nil
local BillboardInstance = nil
local RoomHighlightInstance = nil

-- Backup lighting settings
local old_ambient = Lighting.Ambient
local old_outdoor = Lighting.OutdoorAmbient
local old_brightness = Lighting.Brightness
local old_shadows = Lighting.GlobalShadows

-- Ghost Types & Evidence Formula Table (Mapped from Journal)
local GhostFormulas = {
    Spirit = {"Handprints", "GhostWriting", "SpiritBox"},
    Wraith = {"EMFLevel5", "SpiritBox", "LaserProjector"},
    Ghoul = {"SpiritBox", "FreezingTemperatures", "GhostOrb"},
    Phantom = {"EMFLevel5", "Handprints", "GhostOrb"},
    Shadow = {"EMFLevel5", "GhostWriting", "LaserProjector"},
    Demon = {"EMFLevel5", "Handprints", "FreezingTemperatures"},
    Specter = {"EMFLevel5", "FreezingTemperatures", "LaserProjector"},
    Entity = {"SpiritBox", "Handprints", "LaserProjector"},
    Skinwalker = {"FreezingTemperatures", "GhostWriting", "SpiritBox"},
    Banshee = {"GhostOrb", "Handprints", "FreezingTemperatures"},
    Wendigo = {"GhostOrb", "GhostWriting", "LaserProjector"},
    Nightmare = {"EMFLevel5", "SpiritBox", "GhostOrb"},
    Leviathan = {"GhostOrb", "GhostWriting", "Handprints"},
    Oni = {"LaserProjector", "SpiritBox", "FreezingTemperatures"},
    Umbra = {"GhostOrb", "LaserProjector", "Handprints"},
    Revenant = {"GhostWriting", "EMFLevel5", "FreezingTemperatures"},
    Aswang = {"Wither", "EMFLevel5", "GhostWriting"},
    Dybbuk = {"Wither", "FreezingTemperatures", "Handprints"},
    Wisp = {"Wither", "LaserProjector", "GhostOrb"},
    Siren = {"Wither", "SpiritBox", "EMFLevel5"},
    Dullahan = {"Wither", "FreezingTemperatures", "LaserProjector"},
    Vex = {"Wither", "FreezingTemperatures", "GhostOrb"},
    Keres = {"Wither", "SpiritBox", "Handprints"}
}

-- Notification helper
local function Notify(title, text, duration)
    pcall(function()
        if _G.RayfieldLoaded then
            _G.Rayfield:Notify({
                Title = title,
                Content = text,
                Duration = duration or 3,
                Image = 4483362458
            })
        else
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = title,
                Text = text,
                Duration = duration or 3
            })
        end
    end)
end

-- Robust Ghost Finder
local function FindActiveGhost()
    local directGhost = Workspace:FindFirstChild("Ghost")
    if directGhost and directGhost:IsA("Model") then
        return directGhost
    end
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Model") and obj:GetAttribute("IsGhost") == true then
            return obj
        end
    end
    return nil
end

-- Scan Map for Evidence and Solve Ghost Type
local function SolveGhostType()
    local active_evidences = {}
    
    -- 1. Check Ghost Orb
    if Workspace:FindFirstChild("GhostOrb") then
        table.insert(active_evidences, "GhostOrb")
    end
    
    -- 2. Check Handprints
    local handprints = Workspace:FindFirstChild("Handprints")
    if handprints and #handprints:GetChildren() > 0 then
        table.insert(active_evidences, "Handprints")
    end
    
    -- 3. Check Ghost Writing (Checks items & interactables)
    local items = Workspace:FindFirstChild("Items") or Workspace:FindFirstChild("Interactables")
    if items then
        for _, item in ipairs(items:GetDescendants()) do
            if item.Name:lower():find("book") and item:GetAttribute("HasWriting") == true then
                table.insert(active_evidences, "GhostWriting")
                break
            end
        end
    end
    
    -- 4. Check Laser Projector Interaction
    local ghost = FindActiveGhost()
    if ghost and ghost:GetAttribute("LaserProjectorActive") == true then
        table.insert(active_evidences, "LaserProjector")
    end
    
    -- 5. Check Freezing Temperatures
    if ghost and ghost:GetAttribute("Freezing") == true then
        table.insert(active_evidences, "FreezingTemperatures")
    end

    -- 6. Check Wither
    if Workspace:FindFirstChild("WitheredFlowers") or (ghost and ghost:GetAttribute("WitherActive") == true) then
        table.insert(active_evidences, "Wither")
    end

    -- Solve by checking matching formulas
    local possible_ghosts = {}
    for ghostName, formula in pairs(GhostFormulas) do
        local matches = true
        for _, ev in ipairs(active_evidences) do
            if not table.find(formula, ev) then
                matches = false
                break
            end
        end
        if matches then
            table.insert(possible_ghosts, ghostName)
        end
    end
    
    if #possible_ghosts == 1 then
        return possible_ghosts[1] .. " (100% Solved! ✅)"
    elseif #possible_ghosts > 1 and #active_evidences > 0 then
        return table.concat(possible_ghosts, " / ") .. " (Incomplete Evidence)"
    else
        return "Waiting on Evidence... (Look for Orbs/Prints)"
    end
end

-- Fallback Custom UI creation (If Rayfield can't load)
local function CreateCustomUI()
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "BloxWare_Demonology"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    -- Destroy old UI if exists
    local oldUI = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("BloxWare_Demonology") or LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("ScreenGui")
    if oldUI then oldUI:Destroy() end
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    
    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Parent = ScreenGui
    MainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 26)
    MainFrame.BorderColor3 = Color3.fromRGB(35, 35, 69)
    MainFrame.BorderSizePixel = 1
    MainFrame.Position = UDim2.new(0.3, 0, 0.25, 0)
    MainFrame.Size = UDim2.new(0, 520, 0, 380)
    MainFrame.Active = true
    MainFrame.Draggable = true
    
    -- Round corners
    local UICorner = Instance.new("Corner")
    UICorner.CornerRadius = UDim.new(0, 8)
    UICorner.Parent = MainFrame
    
    -- Gradient Border Accent
    local Stroke = Instance.new("UIStroke")
    Stroke.Thickness = 2
    Stroke.Color = Color3.fromRGB(77, 100, 255)
    Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    Stroke.Parent = MainFrame
    
    -- Title Bar
    local TitleBar = Instance.new("Frame")
    TitleBar.Name = "TitleBar"
    TitleBar.Parent = MainFrame
    TitleBar.BackgroundColor3 = Color3.fromRGB(23, 23, 44)
    TitleBar.BorderSizePixel = 0
    TitleBar.Size = UDim2.new(1, 0, 0, 40)
    
    local TitleCorner = Instance.new("Corner")
    TitleCorner.CornerRadius = UDim.new(0, 8)
    TitleCorner.Parent = TitleBar
    
    local TitleText = Instance.new("TextLabel")
    TitleText.Parent = TitleBar
    TitleText.BackgroundTransparency = 1
    TitleText.Position = UDim2.new(0, 15, 0, 0)
    TitleText.Size = UDim2.new(0, 300, 1, 0)
    TitleText.Text = "BloxWare - Demonology v2 👻"
    TitleText.TextColor3 = Color3.fromRGB(255, 255, 255)
    TitleText.Font = Enum.Font.GothamBold
    TitleText.TextSize = 15
    TitleText.TextXAlignment = Enum.TextXAlignment.Left
    
    -- Close button
    local CloseButton = Instance.new("TextButton")
    CloseButton.Parent = TitleBar
    CloseButton.BackgroundTransparency = 1
    CloseButton.Position = UDim2.new(1, -40, 0, 0)
    CloseButton.Size = UDim2.new(0, 40, 1, 0)
    CloseButton.Text = "X"
    CloseButton.TextColor3 = Color3.fromRGB(150, 150, 170)
    CloseButton.Font = Enum.Font.GothamBold
    CloseButton.TextSize = 16
    
    CloseButton.MouseButton1Click:Connect(function()
        ScreenGui.Enabled = false
        Notify("BloxWare", "Script minimized. Press RightShift to re-open!", 3)
    end)
    
    CloseButton.MouseEnter:Connect(function() CloseButton.TextColor3 = Color3.fromRGB(255, 80, 80) end)
    CloseButton.MouseLeave:Connect(function() CloseButton.TextColor3 = Color3.fromRGB(150, 150, 170) end)
    
    -- Sidebar Navigation
    local Sidebar = Instance.new("Frame")
    Sidebar.Name = "Sidebar"
    Sidebar.Parent = MainFrame
    Sidebar.BackgroundColor3 = Color3.fromRGB(20, 20, 38)
    Sidebar.BorderSizePixel = 0
    Sidebar.Position = UDim2.new(0, 0, 0, 40)
    Sidebar.Size = UDim2.new(0, 130, 1, -40)
    
    local SidebarCorner = Instance.new("Corner")
    SidebarCorner.CornerRadius = UDim.new(0, 8)
    SidebarCorner.Parent = Sidebar
    
    -- Content container
    local ContentFrame = Instance.new("Frame")
    ContentFrame.Name = "Content"
    ContentFrame.Parent = MainFrame
    ContentFrame.BackgroundTransparency = 1
    ContentFrame.Position = UDim2.new(0, 135, 0, 45)
    ContentFrame.Size = UDim2.new(1, -145, 1, -55)
    
    local TabButtons = {}
    local TabFrames = {}
    
    local function CreateTab(tabName)
        local frame = Instance.new("ScrollingFrame")
        frame.Name = tabName .. "Tab"
        frame.Parent = ContentFrame
        frame.Size = UDim2.new(1, 0, 1, 0)
        frame.BackgroundTransparency = 1
        frame.BorderSizePixel = 0
        frame.ScrollBarThickness = 4
        frame.Visible = false
        
        local layout = Instance.new("UIListLayout")
        layout.Parent = frame
        layout.Padding = UDim.new(0, 8)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        
        TabFrames[tabName] = frame
        
        local btn = Instance.new("TextButton")
        btn.Parent = Sidebar
        btn.Size = UDim2.new(1, -10, 0, 35)
        btn.Position = UDim2.new(0, 5, 0, 5 + (#TabButtons * 40))
        btn.BackgroundColor3 = Color3.fromRGB(25, 25, 48)
        btn.BorderSizePixel = 0
        btn.Text = tabName
        btn.TextColor3 = Color3.fromRGB(200, 200, 220)
        btn.Font = Enum.Font.GothamSemibold
        btn.TextSize = 12
        
        local btnCorner = Instance.new("Corner")
        btnCorner.CornerRadius = UDim.new(0, 4)
        btnCorner.Parent = btn
        
        btn.MouseButton1Click:Connect(function()
            for name, f in pairs(TabFrames) do f.Visible = (name == tabName) end
            for name, b in pairs(TabButtons) do
                if name == tabName then
                    b.BackgroundColor3 = Color3.fromRGB(77, 100, 255)
                    b.TextColor3 = Color3.fromRGB(255, 255, 255)
                else
                    b.BackgroundColor3 = Color3.fromRGB(25, 25, 48)
                    b.TextColor3 = Color3.fromRGB(200, 200, 220)
                end
            end
        end)
        
        TabButtons[tabName] = btn
        return frame
    end
    
    -- Create our Tabs
    local InfoTab = CreateTab("Ghost Tracker")
    local ESPTab = CreateTab("Visuals (ESP)")
    local PlayerTab = CreateTab("Local Player")
    local TeleportTab = CreateTab("Teleports")
    
    -- Set default active tab
    TabFrames["Ghost Tracker"].Visible = true
    TabButtons["Ghost Tracker"].BackgroundColor3 = Color3.fromRGB(77, 100, 255)
    TabButtons["Ghost Tracker"].TextColor3 = Color3.fromRGB(255, 255, 255)
    
    -- Content creation helper
    local function CreateInfoLabel(parent, labelName, defaultText)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, -10, 0, 28)
        frame.BackgroundTransparency = 1
        frame.Parent = parent
        
        local txt = Instance.new("TextLabel")
        txt.Size = UDim2.new(1, 0, 1, 0)
        txt.BackgroundTransparency = 1
        txt.Text = " " .. labelName .. ": " .. defaultText
        txt.TextColor3 = Color3.fromRGB(220, 220, 240)
        txt.Font = Enum.Font.Gotham
        txt.TextSize = 13
        txt.TextXAlignment = Enum.TextXAlignment.Left
        txt.Parent = frame
        
        return txt
    end
    
    -- Create Info Fields under Ghost Tracker Tab
    local StatusLbl = CreateInfoLabel(InfoTab, "Session Status", "In Lobby / Waiting...")
    StatusLbl.TextColor3 = Color3.fromRGB(255, 200, 50)
    
    local GhostTypeLbl = CreateInfoLabel(InfoTab, "Solved Ghost Type", "Analyzing Evidence...")
    GhostTypeLbl.Font = Enum.Font.GothamBold
    GhostTypeLbl.TextColor3 = Color3.fromRGB(77, 255, 77)
    
    local GhostModelLbl = CreateInfoLabel(InfoTab, "Ghost Model (Skin)", "Waiting for game...")
    GhostModelLbl.Font = Enum.Font.GothamBold
    GhostModelLbl.TextColor3 = Color3.fromRGB(255, 100, 100)
    
    local FavoriteRoomLbl = CreateInfoLabel(InfoTab, "Favorite Room", "Waiting...")
    local CurrentRoomLbl = CreateInfoLabel(InfoTab, "Current Room", "Waiting...")
    local StateLbl = CreateInfoLabel(InfoTab, "Current Behavior", "Idle")
    local GenderLbl = CreateInfoLabel(InfoTab, "Gender", "Unknown")
    local AgeLbl = CreateInfoLabel(InfoTab, "Age", "Unknown")
    
    -- Extracted Attributes box title
    local AttrTitle = Instance.new("TextLabel")
    AttrTitle.Size = UDim2.new(1, -10, 0, 20)
    AttrTitle.BackgroundTransparency = 1
    AttrTitle.Text = " [All Active Ghost Attributes]"
    AttrTitle.TextColor3 = Color3.fromRGB(150, 150, 180)
    AttrTitle.Font = Enum.Font.GothamSemibold
    AttrTitle.TextSize = 11
    AttrTitle.TextXAlignment = Enum.TextXAlignment.Left
    AttrTitle.Parent = InfoTab
    
    -- Attribute scroll frame
    local AttrContainer = Instance.new("Frame")
    AttrContainer.Size = UDim2.new(1, -10, 0, 100)
    AttrContainer.BackgroundColor3 = Color3.fromRGB(10, 10, 18)
    AttrContainer.BorderSizePixel = 0
    AttrContainer.Parent = InfoTab
    
    local AttrCorner = Instance.new("Corner")
    AttrCorner.CornerRadius = UDim.new(0, 4)
    AttrCorner.Parent = AttrContainer
    
    local AttrScroll = Instance.new("ScrollingFrame")
    AttrScroll.Size = UDim2.new(1, -10, 1, -10)
    AttrScroll.Position = UDim2.new(0, 5, 0, 5)
    AttrScroll.BackgroundTransparency = 1
    AttrScroll.BorderSizePixel = 0
    AttrScroll.ScrollBarThickness = 2
    AttrScroll.Parent = AttrContainer
    
    local AttrLayout = Instance.new("UIListLayout")
    AttrLayout.Parent = AttrScroll
    AttrLayout.Padding = UDim.new(0, 4)
    
    local function RefreshAttributes()
        for _, child in ipairs(AttrScroll:GetChildren()) do
            if child:IsA("TextLabel") then child:Destroy() end
        end
        
        local Ghost = FindActiveGhost()
        if Ghost then
            for k, v in pairs(Ghost:GetAttributes()) do
                local lbl = Instance.new("TextLabel")
                lbl.Size = UDim2.new(1, 0, 0, 16)
                lbl.BackgroundTransparency = 1
                lbl.Text = "  " .. tostring(k) .. ": " .. tostring(v)
                lbl.TextColor3 = Color3.fromRGB(180, 180, 200)
                lbl.Font = Enum.Font.SourceSans
                lbl.TextSize = 13
                lbl.TextXAlignment = Enum.TextXAlignment.Left
                lbl.Parent = AttrScroll
            end
        else
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, 0, 0, 20)
            lbl.BackgroundTransparency = 1
            lbl.Text = "  Waiting for Ghost to spawn..."
            lbl.TextColor3 = Color3.fromRGB(150, 150, 150)
            lbl.Font = Enum.Font.SourceSansItalic
            lbl.TextSize = 13
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Parent = AttrScroll
        end
    end
    
    -- Component Builders
    local function CreateToggle(parent, name, default, callback)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, -10, 0, 35)
        frame.BackgroundTransparency = 1
        frame.Parent = parent
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0.7, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = " " .. name
        label.TextColor3 = Color3.fromRGB(220, 220, 240)
        label.Font = Enum.Font.Gotham
        label.TextSize = 13
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = frame
        
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 50, 0, 24)
        btn.Position = UDim2.new(1, -55, 0.5, -12)
        btn.BackgroundColor3 = default and Color3.fromRGB(77, 100, 255) or Color3.fromRGB(40, 40, 55)
        btn.Text = default and "ON" or "OFF"
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.Parent = frame
        
        local btnCorner = Instance.new("Corner")
        btnCorner.CornerRadius = UDim.new(0, 4)
        btnCorner.Parent = btn
        
        local state = default
        btn.MouseButton1Click:Connect(function()
            state = not state
            btn.BackgroundColor3 = state and Color3.fromRGB(77, 100, 255) or Color3.fromRGB(40, 40, 55)
            btn.Text = state and "ON" or "OFF"
            callback(state)
        end)
    end
    
    local function CreateButton(parent, name, callback)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, -10, 0, 35)
        frame.BackgroundTransparency = 1
        frame.Parent = parent
        
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 30)
        btn.Position = UDim2.new(0, 0, 0.5, -15)
        btn.BackgroundColor3 = Color3.fromRGB(45, 45, 68)
        btn.Text = name
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Font = Enum.Font.GothamSemibold
        btn.TextSize = 12
        btn.Parent = frame
        
        local btnCorner = Instance.new("Corner")
        btnCorner.CornerRadius = UDim.new(0, 4)
        btnCorner.Parent = btn
        
        btn.MouseButton1Click:Connect(callback)
    end
    
    local function CreateSlider(parent, name, minVal, maxVal, default, callback)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, -10, 0, 45)
        frame.BackgroundTransparency = 1
        frame.Parent = parent
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0.6, 0, 0.5, 0)
        label.BackgroundTransparency = 1
        label.Text = " " .. name
        label.TextColor3 = Color3.fromRGB(220, 220, 240)
        label.Font = Enum.Font.Gotham
        label.TextSize = 13
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = frame
        
        local valLabel = Instance.new("TextLabel")
        valLabel.Size = UDim2.new(0.4, 0, 0.5, 0)
        valLabel.Position = UDim2.new(0.6, 0, 0, 0)
        valLabel.BackgroundTransparency = 1
        valLabel.Text = tostring(default)
        valLabel.TextColor3 = Color3.fromRGB(77, 100, 255)
        valLabel.Font = Enum.Font.GothamBold
        valLabel.TextSize = 13
        valLabel.TextXAlignment = Enum.TextXAlignment.Right
        valLabel.Parent = frame
        
        local sliderBg = Instance.new("Frame")
        sliderBg.Size = UDim2.new(1, -10, 0, 6)
        sliderBg.Position = UDim2.new(0, 5, 0.75, -3)
        sliderBg.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
        sliderBg.BorderSizePixel = 0
        sliderBg.Parent = frame
        
        local sliderCorner = Instance.new("Corner")
        sliderCorner.CornerRadius = UDim.new(0, 3)
        sliderCorner.Parent = sliderBg
        
        local sliderFill = Instance.new("Frame")
        sliderFill.Size = UDim2.new((default - minVal)/(maxVal - minVal), 0, 1, 0)
        sliderFill.BackgroundColor3 = Color3.fromRGB(77, 100, 255)
        sliderFill.BorderSizePixel = 0
        sliderFill.Parent = sliderBg
        
        local fillCorner = Instance.new("Corner")
        fillCorner.CornerRadius = UDim.new(0, 3)
        fillCorner.Parent = sliderFill
        
        local sliderBtn = Instance.new("TextButton")
        sliderBtn.Size = UDim2.new(0, 12, 0, 12)
        sliderBtn.Position = UDim2.new((default - minVal)/(maxVal - minVal), -6, 0.5, -6)
        sliderBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        sliderBtn.BorderSizePixel = 0
        sliderBtn.Text = ""
        sliderBtn.Parent = sliderBg
        
        local btnCorner = Instance.new("Corner")
        btnCorner.CornerRadius = UDim.new(0, 6)
        btnCorner.Parent = sliderBtn
        
        local dragging = false
        sliderBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end
        end)
        
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
        
        local function UpdateSlider(xPos)
            local percentage = math.clamp((xPos - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
            local val = math.floor(minVal + (maxVal - minVal) * percentage)
            sliderFill.Size = UDim2.new(percentage, 0, 1, 0)
            sliderBtn.Position = UDim2.new(percentage, -6, 0.5, -6)
            valLabel.Text = tostring(val)
            callback(val)
        end
        
        UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                UpdateSlider(input.Position.X)
            end
        end)
    end
    
    -- Setup Visuals/ESP Tab Toggles
    CreateToggle(ESPTab, "Ghost Outline Highlight ESP", false, function(v)
        GhostESP_Enabled = v
        Notify("ESP", "Ghost Outline " .. (v and "Enabled" or "Disabled"), 2)
    end)
    
    CreateToggle(ESPTab, "Ghost Overlay Billboard Tag", false, function(v)
        GhostTag_Enabled = v
        Notify("ESP", "Overhead Tag " .. (v and "Enabled" or "Disabled"), 2)
    end)
    
    CreateToggle(ESPTab, "Ghost Favorite Room ESP", false, function(v)
        FavoriteRoomESP_Enabled = v
        Notify("ESP", "Favorite Room Highlight " .. (v and "Enabled" or "Disabled"), 2)
    end)
    
    CreateToggle(ESPTab, "Show Invisible Pathing Ghost Walls", false, function(v)
        ShowWalls_Enabled = v
        local InvisibleWalls = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("InvisibleGhostWalls")
        if InvisibleWalls then
            for _, wall in ipairs(InvisibleWalls:GetChildren()) do
                if wall:IsA("BasePart") then wall.Transparency = v and 0.5 or 1 end
            end
            Notify("ESP", "Invisible Ghost Walls are now " .. (v and "Visible" or "Hidden"), 2)
        else
            Notify("Error", "InvisibleGhostWalls not found!", 3)
        end
    end)
    
    -- Setup Local Player Controls
    CreateToggle(PlayerTab, "Enable Walkspeed Adjuster", false, function(v)
        SpeedHack_Enabled = v
        Notify("Player Hack", "Walkspeed Hack " .. (v and "Enabled" or "Disabled"), 2)
    end)
    
    CreateSlider(PlayerTab, "Walkspeed Custom Value", 16, 100, 25, function(v)
        SpeedHack_Value = v
    end)
    
    CreateToggle(PlayerTab, "Infinite Running Stamina", false, function(v)
        InfiniteStamina_Enabled = v
        Notify("Player Hack", "Infinite Stamina " .. (v and "Enabled" or "Disabled"), 2)
    end)
    
    CreateToggle(PlayerTab, "Full Bright (See in the Dark)", false, function(v)
        FullBright_Enabled = v
        if FullBright_Enabled then
            Lighting.Ambient = Color3.fromRGB(255, 255, 255)
            Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
            Lighting.Brightness = 3
            Lighting.GlobalShadows = false
        else
            Lighting.Ambient = old_ambient
            Lighting.OutdoorAmbient = old_outdoor
            Lighting.Brightness = old_brightness
            Lighting.GlobalShadows = old_shadows
        end
        Notify("Visuals", "Full Bright " .. (v and "Activated" or "Deactivated"), 2)
    end)
    
    -- Setup Teleports
    CreateButton(TeleportTab, "Teleport behind Ghost (Backstud offset)", function()
        local Ghost = FindActiveGhost()
        if Ghost and Ghost.PrimaryPart then
            LocalPlayer.Character:PivotTo(Ghost.PrimaryPart.CFrame * CFrame.new(0, 0, 4))
            Notify("Teleport", "Successfully teleported behind the Ghost!", 2)
        else
            Notify("Error", "Ghost model not found in workspace!", 3)
        end
    end)
    
    CreateButton(TeleportTab, "Teleport to Favorite Room", function()
        local Ghost = FindActiveGhost()
        local favRoom = Ghost and Ghost:GetAttribute("FavoriteRoom")
        if favRoom then
            local Rooms = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Rooms")
            local roomPart = Rooms and Rooms:FindFirstChild(favRoom)
            if roomPart then
                local boundingBox = roomPart:FindFirstChild("BoundingBox") or roomPart
                local targetCF = boundingBox:IsA("Model") and boundingBox:GetPivot() or boundingBox.CFrame
                LocalPlayer.Character:PivotTo(targetCF * CFrame.new(0, 3, 0))
                Notify("Teleport", "Teleported to Favorite Room: " .. favRoom, 2)
            else
                Notify("Error", "Could not locate room part in Workspace!", 3)
            end
        else
            Notify("Error", "Favorite room is currently unknown!", 3)
        end
    end)
    
    CreateButton(TeleportTab, "Teleport to Safe Base Camp (Van)", function()
        local Rooms = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Rooms")
        local baseCamp = Rooms and Rooms:FindFirstChild("Base Camp")
        if baseCamp then
            local boundingBox = baseCamp:FindFirstChild("BoundingBox") or baseCamp
            local targetCF = boundingBox:IsA("Model") and boundingBox:GetPivot() or boundingBox.CFrame
            LocalPlayer.Character:PivotTo(targetCF * CFrame.new(0, 3, 0))
            Notify("Teleport", "Teleported back to Base Camp!", 2)
        else
            Notify("Error", "Base Camp room not found!", 3)
        end
    end)
    
    -- Minimize / Toggle UI keybind
    UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.RightShift then
            ScreenGui.Enabled = not ScreenGui.Enabled
        end
    end)
    
    -- Continuous updater thread
    task.spawn(function()
        local lastRefresh = 0
        while ScreenGui.Parent do
            task.wait(0.2)
            
            local Ghost = FindActiveGhost()
            if Ghost then
                StatusLbl.Text = " Session Status: Match Active 🎮"
                StatusLbl.TextColor3 = Color3.fromRGB(50, 255, 100)
                
                -- Live Solve Ghost Class
                local solvedType = SolveGhostType()
                GhostTypeLbl.Text = " Solved Ghost Type: " .. tostring(solvedType)
                
                -- Retrieve Visual Model skin (the actual ghost 3D model skin name, like Rattle, Biter, etc.)
                local visModel = Ghost:GetAttribute("VisualModel") or "Ghost"
                GhostModelLbl.Text = " Ghost Model (Skin): " .. tostring(visModel):upper()
                
                FavoriteRoomLbl.Text = " Favorite Room: " .. tostring(Ghost:GetAttribute("FavoriteRoom") or "Searching...")
                CurrentRoomLbl.Text = " Current Room: " .. tostring(Ghost:GetAttribute("CurrentRoom") or "Unknown")
                GenderLbl.Text = " Gender: " .. tostring(Ghost:GetAttribute("Gender") or "Unknown")
                AgeLbl.Text = " Age: " .. tostring(Ghost:GetAttribute("Age") or "Unknown")
                
                local state = "Idle / Roaming"
                if Ghost:GetAttribute("Hunting") then
                    state = "⚠️ HUNTING! ⚠️"
                    StateLbl.TextColor3 = Color3.fromRGB(255, 40, 40)
                elseif Ghost:GetAttribute("EventActive") then
                    state = "⭐ ACTIVE EVENT ⭐"
                    StateLbl.TextColor3 = Color3.fromRGB(255, 200, 40)
                else
                    StateLbl.TextColor3 = Color3.fromRGB(220, 220, 240)
                end
                StateLbl.Text = " Current Behavior: " .. state
            else
                StatusLbl.Text = " Session Status: Waiting for Game Start..."
                StatusLbl.TextColor3 = Color3.fromRGB(255, 200, 50)
                
                GhostTypeLbl.Text = " Solved Ghost Type: Analyzing Evidence..."
                GhostModelLbl.Text = " Ghost Model (Skin): Waiting on Spawn..."
                FavoriteRoomLbl.Text = " Favorite Room: Waiting..."
                CurrentRoomLbl.Text = " Current Room: Waiting..."
                StateLbl.Text = " Current Behavior: Inactive"
                GenderLbl.Text = " Gender: Unknown"
                AgeLbl.Text = " Age: Unknown"
                StateLbl.TextColor3 = Color3.fromRGB(150, 150, 150)
            end
            
            if tick() - lastRefresh >= 2 then
                RefreshAttributes()
                lastRefresh = tick()
            end
        end
    end)
    
    Notify("BloxWare Loaded", "Press [RightShift] to Toggle menu!", 5)
    return ScreenGui
end

-- Premium Rayfield Interface loader (Fixed Syntax!)
local function LoadRayfield()
    local success, Rayfield = pcall(function()
        return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
    end)
    
    if not success or not Rayfield then
        warn("Rayfield failed. Launching Custom BloxWare GUI Fallback...")
        CreateCustomUI()
        return
    end
    
    _G.RayfieldLoaded = true
    _G.Rayfield = Rayfield
    
    local Window = Rayfield:CreateWindow({
        Name = "BloxWare - Demonology Premium 👻",
        LoadingTitle = "BloxWare Premium",
        LoadingSubtitle = "by Nathan Lorenzo",
        ConfigurationSaving = { Enabled = false },
        Discord = { Enabled = false },
        KeySystem = false
    })
    
    local MainTab = Window:CreateTab("Ghost Tracker", 4483362458)
    local ESPTab = Window:CreateTab("Visuals (ESP)", 4483362458)
    local PlayerTab = Window:CreateTab("Player Modifications", 4483362458)
    local TeleportTab = Window:CreateTab("Teleports", 4483362458)
    
    local StatusLabel = MainTab:CreateLabel("Session Status: Waiting...")
    local SolverLabel = MainTab:CreateLabel("Solved Ghost Type: Analyzing Evidence...")
    local ModelLabel = MainTab:CreateLabel("Ghost Model (Skin): Waiting on Spawn...")
    local FavRoomLabel = MainTab:CreateLabel("Favorite Room: Waiting...")
    local CurrRoomLabel = MainTab:CreateLabel("Current Room: Waiting...")
    local BehaviorLabel = MainTab:CreateLabel("Current Behavior: Inactive")
    local IdentityLabel = MainTab:CreateLabel("Identity: Gender (?), Age (?)")
    
    MainTab:CreateButton({
        Name = "Print Ghost Attributes to Console (Press F9)",
        Callback = function()
            local Ghost = FindActiveGhost()
            if Ghost then
                print("======== BLOXWARE GHOST ATTRIBUTES ========")
                for k, v in pairs(Ghost:GetAttributes()) do
                    print(tostring(k) .. ": " .. tostring(v))
                end
                print("==========================================")
                Rayfield:Notify({
                    Title = "Attributes Extracted",
                    Content = "Press F9 to open the Roblox developer console!",
                    Duration = 4,
                    Image = 4483362458,
                })
            else
                Rayfield:Notify({
                    Title = "Error",
                    Content = "Ghost not spawned in map yet!",
                    Duration = 3,
                    Image = 4483362458,
                })
            end
        end,
    })
    
    -- Visual Toggles
    ESPTab:CreateToggle({
        Name = "Ghost Outline Highlight ESP",
        CurrentValue = false,
        Callback = function(Value) GhostESP_Enabled = Value end,
    })
    
    ESPTab:CreateToggle({
        Name = "Ghost Overhead Billboard Tag",
        CurrentValue = false,
        Callback = function(Value) GhostTag_Enabled = Value end,
    })
    
    ESPTab:CreateToggle({
        Name = "Highlight Favorite Room (Blue Outline)",
        CurrentValue = false,
        Callback = function(Value) FavoriteRoomESP_Enabled = Value end,
    })
    
    ESPTab:CreateToggle({
        Name = "Show Pathing Ghost Walls",
        CurrentValue = false,
        Callback = function(Value)
            ShowWalls_Enabled = Value
            local InvisibleWalls = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("InvisibleGhostWalls")
            if InvisibleWalls then
                for _, wall in ipairs(InvisibleWalls:GetChildren()) do
                    if wall:IsA("BasePart") then wall.Transparency = Value and 0.5 or 1 end
                end
            end
        end,
    })
    
    -- Player Toggles
    PlayerTab:CreateToggle({
        Name = "Walkspeed Adjuster Hack",
        CurrentValue = false,
        Callback = function(Value) SpeedHack_Enabled = Value end,
    })
    
    PlayerTab:CreateSlider({
        Name = "Walkspeed Custom Speed Value",
        Range = {16, 100}, -- Correct Rayfield syntax to prevent crashes!
        Increment = 1,
        CurrentValue = 25,
        Callback = function(Value) SpeedHack_Value = Value end,
    })
    
    PlayerTab:CreateToggle({
        Name = "Infinite Sprint Stamina & Energy",
        CurrentValue = false,
        Callback = function(Value) InfiniteStamina_Enabled = Value end,
    })
    
    PlayerTab:CreateToggle({
        Name = "Full Bright (Daylight Simulation)",
        CurrentValue = false,
        Callback = function(Value)
            FullBright_Enabled = Value
            if FullBright_Enabled then
                Lighting.Ambient = Color3.fromRGB(255, 255, 255)
                Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
                Lighting.Brightness = 3
                Lighting.GlobalShadows = false
            else
                Lighting.Ambient = old_ambient
                Lighting.OutdoorAmbient = old_outdoor
                Lighting.Brightness = old_brightness
                Lighting.GlobalShadows = old_shadows
            end
        end,
    })
    
    -- Teleports
    TeleportTab:CreateButton({
        Name = "Teleport behind Ghost",
        Callback = function()
            local Ghost = FindActiveGhost()
            if Ghost and Ghost.PrimaryPart then
                LocalPlayer.Character:PivotTo(Ghost.PrimaryPart.CFrame * CFrame.new(0, 0, 4))
            else
                Rayfield:Notify({
                    Title = "Error",
                    Content = "Ghost is not spawned yet!",
                    Duration = 3,
                    Image = 4483362458
                })
            end
        end,
    })
    
    TeleportTab:CreateButton({
        Name = "Teleport to Favorite Room",
        Callback = function()
            local Ghost = FindActiveGhost()
            local favRoom = Ghost and Ghost:GetAttribute("FavoriteRoom")
            if favRoom then
                local Rooms = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Rooms")
                local roomPart = Rooms and Rooms:FindFirstChild(favRoom)
                if roomPart then
                    local boundingBox = roomPart:FindFirstChild("BoundingBox") or roomPart
                    local targetCF = boundingBox:IsA("Model") and boundingBox:GetPivot() or boundingBox.CFrame
                    LocalPlayer.Character:PivotTo(targetCF * CFrame.new(0, 3, 0))
                else
                    Rayfield:Notify({
                        Title = "Error",
                        Content = "Favorite Room part not found in Workspace!",
                        Duration = 3,
                        Image = 4483362458
                    })
                end
            else
                Rayfield:Notify({
                    Title = "Error",
                    Content = "Favorite Room is currently unknown!",
                    Duration = 3,
                    Image = 4483362458
                })
            end
        end,
    })
    
    TeleportTab:CreateButton({
        Name = "Teleport to Base Camp (Van)",
        Callback = function()
            local Rooms = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Rooms")
            local baseCamp = Rooms and Rooms:FindFirstChild("Base Camp")
            if baseCamp then
                local boundingBox = baseCamp:FindFirstChild("BoundingBox") or baseCamp
                local targetCF = boundingBox:IsA("Model") and boundingBox:GetPivot() or boundingBox.CFrame
                LocalPlayer.Character:PivotTo(targetCF * CFrame.new(0, 3, 0))
            else
                Rayfield:Notify({
                    Title = "Error",
                    Content = "Base Camp room not found in workspace!",
                    Duration = 3,
                    Image = 4483362458
                })
            end
        end,
    })
    
    -- Rayfield dynamic updates loop
    task.spawn(function()
        while true do
            task.wait(0.2)
            local Ghost = FindActiveGhost()
            if Ghost then
                StatusLabel:Set("Session Status: Match Active 🎮")
                
                local solvedType = SolveGhostType()
                SolverLabel:Set("Solved Ghost Type: " .. tostring(solvedType))
                
                local visModel = Ghost:GetAttribute("VisualModel") or "Ghost"
                ModelLabel:Set("Ghost Model (Skin): " .. tostring(visModel):upper())
                
                FavRoomLabel:Set("Favorite Room: " .. tostring(Ghost:GetAttribute("FavoriteRoom") or "Not Revealed"))
                CurrRoomLabel:Set("Current Room: " .. tostring(Ghost:GetAttribute("CurrentRoom") or "Searching..."))
                IdentityLabel:Set(string.format("Identity: %s (%s yrs old)", tostring(Ghost:GetAttribute("Gender") or "Male"), tostring(Ghost:GetAttribute("Age") or "45")))
                
                local state = "Idle / Roaming"
                if Ghost:GetAttribute("Hunting") then
                    state = "⚠️ HUNTING! ⚠️"
                elseif Ghost:GetAttribute("EventActive") then
                    state = "⭐ ACTIVE EVENT ⭐"
                end
                BehaviorLabel:Set("Current Behavior: " .. state)
            else
                StatusLabel:Set("Session Status: Waiting for Game Start...")
                SolverLabel:Set("Solved Ghost Type: Analyzing Evidence...")
                ModelLabel:Set("Ghost Model (Skin): Waiting on Spawn...")
                FavRoomLabel:Set("Favorite Room: Waiting...")
                CurrRoomLabel:Set("Current Room: Waiting...")
                BehaviorLabel:Set("Current Behavior: Inactive")
            end
        end
    end)
    
    Rayfield:Notify({
        Title = "BloxWare Premium",
        Content = "Demonology Script Loaded! Press [RightShift] to Toggle UI.",
        Duration = 5,
        Image = 4483362458,
    })
end

-- =============================================================================
-- SHARED ESP AND EXPLOIT THREADS (Active under both Rayfield and Custom UI)
-- =============================================================================

-- 1. Ghost ESP Thread (Highlight Outline & Text Billboard)
task.spawn(function()
    while true do
        task.wait(0.1)
        local Ghost = FindActiveGhost()
        
        if Ghost then
            -- Highlight ESP
            if GhostESP_Enabled then
                if not HighlightInstance or HighlightInstance.Parent ~= Ghost then
                    if HighlightInstance then HighlightInstance:Destroy() end
                    HighlightInstance = Instance.new("Highlight")
                    HighlightInstance.Name = "BloxWare_Highlight"
                    HighlightInstance.FillColor = Color3.fromRGB(255, 40, 40)
                    HighlightInstance.FillTransparency = 0.5
                    HighlightInstance.OutlineColor = Color3.fromRGB(255, 255, 255)
                    HighlightInstance.OutlineTransparency = 0
                    HighlightInstance.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    HighlightInstance.Parent = Ghost
                end
                
                -- Flash Highlight if hunting
                if Ghost:GetAttribute("Hunting") then
                    local flash = math.sin(tick() * 12) > 0
                    HighlightInstance.FillColor = flash and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 0, 0)
                else
                    HighlightInstance.FillColor = Color3.fromRGB(255, 40, 40)
                end
            else
                if HighlightInstance then
                    HighlightInstance:Destroy()
                    HighlightInstance = nil
                end
            end
            
            -- Billboard Text Tag ESP
            if GhostTag_Enabled then
                local root = Ghost:FindFirstChild("HumanoidRootPart") or Ghost.PrimaryPart
                if root then
                    if not BillboardInstance or BillboardInstance.Parent ~= root then
                        if BillboardInstance then BillboardInstance:Destroy() end
                        
                        BillboardInstance = Instance.new("BillboardGui")
                        BillboardInstance.Name = "BloxWare_Billboard"
                        BillboardInstance.AlwaysOnTop = true
                        BillboardInstance.Size = UDim2.new(0, 200, 0, 60)
                        BillboardInstance.ExtentsOffset = Vector3.new(0, 4, 0)
                        BillboardInstance.Parent = root
                        
                        local txt = Instance.new("TextLabel")
                        txt.Name = "InfoLabel"
                        txt.Parent = BillboardInstance
                        txt.Size = UDim2.new(1, 0, 1, 0)
                        txt.BackgroundTransparency = 1
                        txt.TextColor3 = Color3.fromRGB(255, 70, 70)
                        txt.TextStrokeTransparency = 0
                        txt.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                        txt.Font = Enum.Font.GothamBold
                        txt.TextSize = 13
                        txt.Text = ""
                    end
                    
                    local dist = 0
                    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                        dist = math.floor((LocalPlayer.Character.HumanoidRootPart.Position - root.Position).Magnitude)
                    end
                    
                    local visModel = Ghost:GetAttribute("VisualModel") or "Ghost"
                    
                    local state = "Idle / Roaming"
                    if Ghost:GetAttribute("Hunting") then
                        state = "⚠️ HUNTING! ⚠️"
                        BillboardInstance.InfoLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
                    elseif Ghost:GetAttribute("EventActive") then
                        state = "⭐ ACTIVE EVENT ⭐"
                        BillboardInstance.InfoLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
                    else
                        BillboardInstance.InfoLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
                    end
                    
                    BillboardInstance.InfoLabel.Text = string.format("%s\nDist: %d studs\nState: %s", tostring(visModel):upper(), dist, state)
                end
            else
                if BillboardInstance then
                    BillboardInstance:Destroy()
                    BillboardInstance = nil
                end
            end
        else
            -- Cleanup if ghost is gone
            if HighlightInstance then HighlightInstance:Destroy() HighlightInstance = nil end
            if BillboardInstance then BillboardInstance:Destroy() BillboardInstance = nil end
        end
    end
end)

-- 2. Favorite Room Highlight Thread
task.spawn(function()
    while true do
        task.wait(0.5)
        local Ghost = FindActiveGhost()
        local favRoom = Ghost and Ghost:GetAttribute("FavoriteRoom")
        
        if FavoriteRoomESP_Enabled and favRoom then
            local Rooms = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Rooms")
            local roomPart = Rooms and Rooms:FindFirstChild(favRoom)
            if roomPart then
                if not RoomHighlightInstance or RoomHighlightInstance.Parent ~= roomPart then
                    if RoomHighlightInstance then RoomHighlightInstance:Destroy() end
                    RoomHighlightInstance = Instance.new("Highlight")
                    RoomHighlightInstance.Name = "BloxWare_RoomESP"
                    RoomHighlightInstance.FillColor = Color3.fromRGB(0, 140, 255)
                    RoomHighlightInstance.FillTransparency = 0.65
                    RoomHighlightInstance.OutlineColor = Color3.fromRGB(255, 255, 255)
                    RoomHighlightInstance.OutlineTransparency = 0.2
                    RoomHighlightInstance.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    RoomHighlightInstance.Parent = roomPart
                end
            else
                if RoomHighlightInstance then RoomHighlightInstance:Destroy() RoomHighlightInstance = nil end
            end
        else
            if RoomHighlightInstance then RoomHighlightInstance:Destroy() RoomHighlightInstance = nil end
        end
    end
end)

-- 3. Speed Hack Loop
task.spawn(function()
    while true do
        task.wait()
        if SpeedHack_Enabled then
            pcall(function()
                local char = LocalPlayer.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum and hum.WalkSpeed ~= SpeedHack_Value then
                    hum.WalkSpeed = SpeedHack_Value
                end
            end)
        end
    end
end)

-- 4. Infinite Stamina Loop
task.spawn(function()
    while true do
        task.wait()
        if InfiniteStamina_Enabled then
            pcall(function()
                LocalPlayer:SetAttribute("Stamina", LocalPlayer:GetAttribute("MaxStamina") or 100)
                LocalPlayer:SetAttribute("Energy", 100)
            end)
        end
    end
end)

-- Load Rayfield Premium with Custom UI fallback
LoadRayfield()
