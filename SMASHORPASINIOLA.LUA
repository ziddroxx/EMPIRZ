local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local localPlayer = Players.LocalPlayer
local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local rootPart = nil
local function refreshCharacter()
    character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    rootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart")
end
refreshCharacter()
localPlayer.CharacterAdded:Connect(refreshCharacter)

-- Safe wrappers for file ops (some executors use different names but Xeno supports these commonly)
local canWrite = type(writefile) == "function"
local canRead  = type(readfile) == "function"
local canIsFolder = type(isfolder) == "function"
local canMakeFolder = type(makefolder) == "function"
local canIsFile = type(isfile) == "function"

-- simple JSON encode/decode (lightweight)
local HttpService = game:GetService("HttpService")

local function encodeTable(t)
    local ok, s = pcall(function() return HttpService:JSONEncode(t) end)
    if ok then return s end
    return nil
end

local function decodeTable(s)
    local ok, t = pcall(function() return HttpService:JSONDecode(s) end)
    if ok then return t end
    return nil
end



-- ================
--  Default config
-- ================
local DefaultConfig = {
    binds = {
        PlaceStair = Enum.KeyCode.P.Name,
        PhantomToggle = Enum.KeyCode.F.Name,
        FloorHackToggle = Enum.KeyCode.R.Name
    },
    options = {
        phantom = false,
        anti_bee = false,
        esp_base_time = false,
        floorhack = false,
        decorationsTransparency = true,
        decorationsTransparencyValue = 0.7,
        esp_players = false,
        invisible_players = false,
        autoexec = false
    }
}
local ConfigFileName = "EmpireConfig.json"

-- try to load config from disk
local Config = DefaultConfig
if canRead and canIsFile and isfile(ConfigFileName) then
    local ok, s = pcall(readfile, ConfigFileName)
    if ok and s then
        local parsed = decodeTable(s)
        if type(parsed) == "table" then Config = parsed end
    end
end

-- Apply binds from Config (convert names to Enum.KeyCode values)
local function keyFromName(name)
    for k,v in pairs(Enum.KeyCode:GetEnumItems()) do
        if v.Name == name then return v end
    end
    return Enum.KeyCode.Unknown
end

local keybinds = {
    PlaceStair = keyFromName(Config.binds.PlaceStair) ~= Enum.KeyCode.Unknown and keyFromName(Config.binds.PlaceStair) or Enum.KeyCode.Q,
    PhantomToggle = keyFromName(Config.binds.PhantomToggle) ~= Enum.KeyCode.Unknown and keyFromName(Config.binds.PhantomToggle) or Enum.KeyCode.E,
    FloorHackToggle = keyFromName(Config.binds.FloorHackToggle) ~= Enum.KeyCode.Unknown and keyFromName(Config.binds.FloorHackToggle) or Enum.KeyCode.R
}

-- visual settings
local stairSize = 7
local stairHeight = 5
local stairColor = Color3.fromRGB(0, 200, 255)

-- States
local phantomActive = Config.options.phantom
local floorHackActive = Config.options.floorhack
local decorationsTransparencyEnabled = Config.options.decorationsTransparency
local decorationsTransparencyValue = Config.options.decorationsTransparencyValue or 0.7
local invisibleEnabled = Config.options.invisible_players or false
local hiddenCharacters = {} -- stocke les données pour restaurer les joueurs
local antiBeeEnabled = Config.options.anti_bee or false
local effectsBlocked = false
local originalCameraType = workspace.CurrentCamera.CameraType



-- ================
-- Decorations transparency (only Workspace.Plots.*.Decorations)
-- ================
local function makeDecorationsTransparent()
    if not decorationsTransparencyEnabled then return end
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return end
    for _, base in ipairs(plotsFolder:GetChildren()) do
        local decorations = base:FindFirstChild("Decorations")
        if decorations then
            for _, obj in ipairs(decorations:GetDescendants()) do
                if obj:IsA("BasePart") and not obj:IsDescendantOf(character) then
                    pcall(function() obj.Transparency = decorationsTransparencyValue end)
                end
            end
        end
    end
end
-- Run once at start
makeDecorationsTransparent()

-- Stronger watcher: applies now and to all future decorations
local decoConns = {}

local function applyDecoTransparency(container)
	if not decorationsTransparencyEnabled then return end
	for _, obj in ipairs(container:GetDescendants()) do
		if obj:IsA("BasePart") and not obj:IsDescendantOf(character) then
			pcall(function() obj.Transparency = decorationsTransparencyValue end)
		end
	end
end

local function attachDecoWatcher(decorations)
	if not decorations then return end
	local conn = decorations.DescendantAdded:Connect(function(d)
		if decorationsTransparencyEnabled and d:IsA("BasePart") and not d:IsDescendantOf(character) then
			pcall(function() d.Transparency = decorationsTransparencyValue end)
		end
	end)
	table.insert(decoConns, conn)
	applyDecoTransparency(decorations)
end

local function watchPlotsForDecorations()
	for _, c in ipairs(decoConns) do pcall(function() c:Disconnect() end) end
	decoConns = {}

	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return end

	for _, base in ipairs(plotsFolder:GetChildren()) do
		local decorations = base:FindFirstChild("Decorations")
		if decorations then
			attachDecoWatcher(decorations)
		end
	end

	table.insert(decoConns, plotsFolder.ChildAdded:Connect(function(newBase)
		task.wait(0.05)
		local decorations = newBase:FindFirstChild("Decorations")
		if decorations then
			attachDecoWatcher(decorations)
		end
	end))

	table.insert(decoConns, plotsFolder.DescendantAdded:Connect(function(d)
		if decorationsTransparencyEnabled and d:IsA("Folder") and d.Name == "Decorations" then
			attachDecoWatcher(d)
		end
	end))
end

watchPlotsForDecorations()
if decorationsTransparencyEnabled then
	makeDecorationsTransparent()
end

-- ================
--  GUI (toggle icon + main)
-- ================
local EMPIRE_GUI = Instance.new("ScreenGui")
EMPIRE_GUI.Name = "EMPIRE_SCRIPT"
EMPIRE_GUI.ResetOnSpawn = false
EMPIRE_GUI.Parent = game:GetService("CoreGui")

-- Floating icon
local iconButton = Instance.new("TextButton")
iconButton.Name = "EmpireIcon"
iconButton.Size = UDim2.new(0, 44, 0, 44)
iconButton.Position = UDim2.new(0, 120, 0, 220)
iconButton.BackgroundColor3 = Color3.fromRGB(20,20,20)
iconButton.BackgroundTransparency = 0.15
iconButton.Text = "⚡"
iconButton.TextColor3 = Color3.fromRGB(0,200,255)
iconButton.TextSize = 26
iconButton.Font = Enum.Font.GothamBold
iconButton.Parent = EMPIRE_GUI
iconButton.Active = true
iconButton.Draggable = true
Instance.new("UICorner", iconButton).CornerRadius = UDim.new(1,0)




-- Main window (compact by default, can be resized)
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 340, 0, 320)
mainFrame.Position = UDim2.new(0.5, -170, 0.5, -150)
mainFrame.AnchorPoint = Vector2.new(0.5,0.5)
mainFrame.BackgroundColor3 = Color3.fromRGB(10,10,10)
mainFrame.BackgroundTransparency = 0
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = EMPIRE_GUI
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0,10)
local mainStroke = Instance.new("UIStroke", mainFrame)
mainStroke.Transparency = 0.7
-- Quand le joueur relâche la souris après avoir déplacé le GUI
mainFrame:GetPropertyChangedSignal("Position"):Connect(function()
    -- mettre à jour la config avec la nouvelle position
    Config.gui_position = {
        X = mainFrame.Position.X.Scale,
        Y = mainFrame.Position.Y.Scale,
        OffsetX = mainFrame.Position.X.Offset,
        OffsetY = mainFrame.Position.Y.Offset
    }
    if type(commitConfig) == "function" then
        pcall(commitConfig)
    end
end)


-- Toggle visibility
local guiVisible = true
local function toggleMainGUI()
    guiVisible = not guiVisible
    mainFrame.Visible = guiVisible
end
iconButton.MouseButton1Click:Connect(toggleMainGUI)
mainFrame.Visible = true

-- Title and tabs
local title = Instance.new("TextLabel", mainFrame)
title.Size = UDim2.new(1, -20, 0, 36)
title.Position = UDim2.new(0,10,0,8)
title.BackgroundTransparency = 1
title.Text = "⚡ EMPIRE"
title.TextColor3 = Color3.fromRGB(0,200,255)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left

-- Tabs container
local tabsFrame = Instance.new("Frame", mainFrame)
tabsFrame.Size = UDim2.new(1, -20, 0, 36)
tabsFrame.Position = UDim2.new(0,10,0,46)
tabsFrame.BackgroundTransparency = 1

local function mkTab(name, x)
    local btn = Instance.new("TextButton", tabsFrame)
    btn.Size = UDim2.new(0, 100, 0, 28)
    btn.Position = UDim2.new(0, x, 0, 4)
    btn.Text = name
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 14
    btn.BackgroundColor3 = Color3.fromRGB(0,200,255)
    Instance.new("UICorner", btn)
    return btn
end

local playerTabBtn = mkTab("Player", 0)
local espTabBtn = mkTab("ESP", 108)
local configTabBtn = mkTab("Config", 216)

-- Content containers
local contentFrame = Instance.new("Frame", mainFrame)
contentFrame.Size = UDim2.new(1, -20, 1, -92)
contentFrame.Position = UDim2.new(0,10,0,86)
contentFrame.BackgroundTransparency = 1

local playerContainer = Instance.new("Frame", contentFrame)
playerContainer.Size = UDim2.new(1,0,1,0)
playerContainer.BackgroundTransparency = 1

local espContainer = Instance.new("Frame", contentFrame)
espContainer.Size = UDim2.new(1,0,1,0)
espContainer.BackgroundTransparency = 1
espContainer.Visible = false

local configContainer = Instance.new("Frame", contentFrame)
configContainer.Size = UDim2.new(1,0,1,0)
configContainer.BackgroundTransparency = 1
configContainer.Visible = false

-- Tab switching
local function showCategory(cat)
    playerContainer.Visible = (cat == "Player")
    espContainer.Visible = (cat == "ESP")
    configContainer.Visible = (cat == "Config")
end
playerTabBtn.MouseButton1Click:Connect(function() showCategory("Player") end)
espTabBtn.MouseButton1Click:Connect(function() showCategory("ESP") end)
configTabBtn.MouseButton1Click:Connect(function() showCategory("Config") end)

-- small helper to create labelled button inside a container
local function addLabeledButton(parent, y, text)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(0.62, 0, 0, 32)
    btn.Position = UDim2.new(0, 6, 0, y)
    btn.Text = text
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 14
    btn.BackgroundColor3 = Color3.fromRGB(0,200,255)
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)
    local bind = Instance.new("TextButton", parent)
    bind.Size = UDim2.new(0.3, -8, 0, 26)
    bind.Position = UDim2.new(0.66, 6, 0, y+3)
    bind.Text = "Bind"
    bind.Font = Enum.Font.Gotham
    bind.TextSize = 12
    bind.BackgroundColor3 = Color3.fromRGB(0,200,255)
    Instance.new("UICorner", bind).CornerRadius = UDim.new(0,6)
    return btn, bind
end

-- =================
--  Player category
-- =================
local placeBtn, placeBindBtn = addLabeledButton(playerContainer, 6, "Poser escalier [".. keybinds.PlaceStair.Name .."]")
local phantomBtn, phantomBindBtn = addLabeledButton(playerContainer, 46, (phantomActive and "Phantom Glide (ON)" or "Phantom Glide (OFF)").." [".. keybinds.PhantomToggle.Name .."]")
local floorBtn, floorBindBtn = addLabeledButton(playerContainer, 86, (floorHackActive and "Floor Hack (ON)" or "Floor Hack (OFF)").." [".. keybinds.FloorHackToggle.Name .."]")

-- Decorations transparency toggle
local decoToggle = Instance.new("TextButton", playerContainer)
decoToggle.Size = UDim2.new(0.62,0,0,32)
decoToggle.Position = UDim2.new(0,6,0,126)
decoToggle.Text = (decorationsTransparencyEnabled and "Decorations Transparency: ON" or "Decorations Transparency: OFF")
decoToggle.Font = Enum.Font.GothamSemibold
decoToggle.TextSize = 14
decoToggle.BackgroundColor3 = Color3.fromRGB(0,200,255)
Instance.new("UICorner", decoToggle).CornerRadius = UDim.new(0,6)

-- Close small
local closeBtn = Instance.new("TextButton", playerContainer)
closeBtn.Size = UDim2.new(0.96,0,0,28)
closeBtn.Position = UDim2.new(0.02,0,1,-36)
closeBtn.Text = "Close (Destroy GUI)"
closeBtn.Font = Enum.Font.Gotham
closeBtn.TextSize = 12
closeBtn.BackgroundColor3 = Color3.fromRGB(0,200,255)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,6)

-- Stair function
local function createStairObject()
    if not rootPart then refreshCharacter() end
    if not rootPart or not rootPart.Parent then return end
    local spawnPos = rootPart.Position + rootPart.CFrame.LookVector * (6 + (stairSize/2))
    spawnPos = Vector3.new(spawnPos.X, rootPart.Position.Y - 3, spawnPos.Z)
    local part = Instance.new("Part")
    part.Size = Vector3.new(stairSize, stairHeight, stairSize)
    part.Anchored = true
    part.CanCollide = true
    part.Material = Enum.Material.Neon
    part.Color = stairColor
    part.CFrame = CFrame.new(spawnPos)
    part.Parent = workspace
    Debris:AddItem(part, 20)
end

-- Phantom Glide
local function setPhantomState(state)
    phantomActive = state
    phantomBtn.Text = (phantomActive and "Phantom Glide (ON)" or "Phantom Glide (OFF)") .. " [".. keybinds.PhantomToggle.Name .."]"
    if phantomActive then
        spawn(function()
            while phantomActive and rootPart and rootPart.Parent do
                rootPart.Velocity = rootPart.CFrame.LookVector * 28
                RunService.Heartbeat:Wait()
            end
        end)
    end
end

-- Floor Hack corrected (single thin platform under player that rises until it detects ceiling)
local floorLoop = nil
local floorPart = nil
local function setFloorHack(state)
    floorHackActive = state
    floorBtn.Text = (floorHackActive and "Floor Hack (ON)" or "Floor Hack (OFF)") .. " [".. keybinds.FloorHackToggle.Name .."]"
    if floorHackActive then
        if not rootPart then refreshCharacter() end
        if floorPart and floorPart.Parent then floorPart:Destroy() end
        floorPart = Instance.new("Part")
        floorPart.Size = Vector3.new(8, 0.4, 8) -- thin carpet
        floorPart.Anchored = true
        floorPart.CanCollide = true
        floorPart.Material = Enum.Material.Neon
        floorPart.Color = stairColor
        floorPart.CFrame = CFrame.new((rootPart and rootPart.Position or Vector3.new(0,0,0)) - Vector3.new(0,3,0))
        floorPart.Parent = workspace

        floorLoop = RunService.Heartbeat:Connect(function()
            if not rootPart or not rootPart.Parent or not floorPart or not floorPart.Parent then return end
            -- keep under player horizontally
            local pos = Vector3.new(rootPart.Position.X, floorPart.Position.Y, rootPart.Position.Z)
            floorPart.CFrame = CFrame.new(pos)
            -- raycast up from floorPart to detect ceiling within short distance
            local rayOrigin = floorPart.Position + Vector3.new(0, 0.5, 0)
            local rayDirection = Vector3.new(0, 3.5, 0) -- look a few studs above
            local raycastParams = RaycastParams.new()
            raycastParams.FilterDescendantsInstances = {character, floorPart}
            raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
            local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
            if not rayResult then
                -- only move up slowly if no ceiling detected
                floorPart.CFrame = floorPart.CFrame + Vector3.new(0, 0.18, 0)
            end
        end)
    else
        if floorLoop then floorLoop:Disconnect() end
        if floorPart and floorPart.Parent then floorPart:Destroy() end
        floorPart = nil
    end
end

-- Binds: connect UI buttons
placeBtn.MouseButton1Click:Connect(createStairObject)
phantomBtn.MouseButton1Click:Connect(function() setPhantomState(not phantomActive) end)
floorBtn.MouseButton1Click:Connect(function() setFloorHack(not floorHackActive) end)

placeBindBtn.MouseButton1Click:Connect(function() 
    bindingTarget = "PlaceStair" 
    placeBindBtn.Text = "..."
end)
phantomBindBtn.MouseButton1Click:Connect(function() 
    bindingTarget = "PhantomToggle" 
    phantomBindBtn.Text = "..."
end)
floorBindBtn.MouseButton1Click:Connect(function() 
    bindingTarget = "FloorHackToggle" 
    floorBindBtn.Text = "..."
end)

decoToggle.MouseButton1Click:Connect(function()
    decorationsTransparencyEnabled = not decorationsTransparencyEnabled
    decoToggle.Text = (decorationsTransparencyEnabled and "Decorations Transparency: ON" or "Decorations Transparency: OFF")
    if decorationsTransparencyEnabled then
        makeDecorationsTransparent()
    else
        -- reset decorations transparency to 0 (opaque) by iterating (best-effort)
        local plotsFolder = workspace:FindFirstChild("Plots")
        if plotsFolder then
            for _, base in ipairs(plotsFolder:GetChildren()) do
                local decorations = base:FindFirstChild("Decorations")
                if decorations then
                    for _, obj in ipairs(decorations:GetDescendants()) do
                        if obj:IsA("BasePart") and not obj:IsDescendantOf(character) then
                            pcall(function() obj.Transparency = 0 end)
                        end
                    end
                end
            end
        end
    end
    if type(commitConfig) == "function" then pcall(commitConfig) end
end)

closeBtn.MouseButton1Click:Connect(function()
    EMPIRE_GUI:Destroy()
end)

-- Input binds (rebind keys)
local bindingTarget = nil
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if bindingTarget then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            keybinds[bindingTarget] = input.KeyCode
            -- update config and UI
            if bindingTarget == "PlaceStair" then
                placeBindBtn.Text = "[" .. keybinds.PlaceStair.Name .. "]"
                placeBtn.Text = "Poser escalier [" .. keybinds.PlaceStair.Name .. "]"
            elseif bindingTarget == "PhantomToggle" then
                phantomBindBtn.Text = "[" .. keybinds.PhantomToggle.Name .. "]"
                phantomBtn.Text = (phantomActive and "Phantom Glide (ON)" or "Phantom Glide (OFF)") .. " [" .. keybinds.PhantomToggle.Name .. "]"
            elseif bindingTarget == "FloorHackToggle" then
                floorBindBtn.Text = "[" .. keybinds.FloorHackToggle.Name .. "]"
                floorBtn.Text = (floorHackActive and "Floor Hack (ON)" or "Floor Hack (OFF)") .. " [" .. keybinds.FloorHackToggle.Name .. "]"
            end
            bindingTarget = nil
        end
    else
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode == keybinds.PlaceStair then
                createStairObject()
            elseif input.KeyCode == keybinds.PhantomToggle then
                setPhantomState(not phantomActive)
            elseif input.KeyCode == keybinds.FloorHackToggle then
                setFloorHack(not floorHackActive)
            end
        end
    end
end)

-- =================
--  ESP Best Brainrot (ajout)
-- =================

local function parseMoneyText(text)
    local cleanText = text:gsub("[^%d%.]", "")
    if text:find("M") or text:find("m") then
        return tonumber(cleanText) * 1000000
    elseif text:find("K") or text:find("k") then
        return tonumber(cleanText) * 1000
    else
        return tonumber(cleanText) or 0
    end
end

local function formatMoney(value)
    if value >= 1000000 then
        return string.format("%.1fM $/s", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.1fK $/s", value / 1000)
    else
        return string.format("%.0f $/s", value)
    end
end

local activeBrainrotESP = nil
local brainrotEnabled = false

local function createOrUpdateBrainrotESP(part, name, moneyPerSecond)
    if not activeBrainrotESP then
        local esp = Instance.new("BillboardGui")
        esp.Name = "BrainrotESP"
        esp.Size = UDim2.new(0, 250, 0, 90)
        esp.StudsOffset = Vector3.new(0, 3, 0)
        esp.AlwaysOnTop = true
        esp.Parent = part

        local bg = Instance.new("Frame", esp)
        bg.Size = UDim2.new(1,0,1,0)
        bg.BackgroundColor3 = Color3.fromRGB(20,20,20)
        bg.BackgroundTransparency = 0.3
        bg.BorderSizePixel = 0
        Instance.new("UICorner", bg).CornerRadius = UDim.new(0,15)

        local stroke = Instance.new("UIStroke", bg)
        stroke.Thickness = 2
        stroke.Color = Color3.fromRGB(255,255,255)

        local glow = Instance.new("UIStroke", bg)
        glow.Thickness = 6
        glow.Transparency = 0.8
        glow.Color = Color3.fromRGB(255,255,255)

        local nameLabel = Instance.new("TextLabel", bg)
        nameLabel.Name = "NameLabel"
        nameLabel.Size = UDim2.new(1,-10,0.5,-5)
        nameLabel.Position = UDim2.new(0,5,0,0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextScaled = true
        nameLabel.TextColor3 = Color3.fromRGB(255,255,255)
        nameLabel.TextStrokeTransparency = 0.2
        nameLabel.Font = Enum.Font.GothamBold

        local moneyLabel = Instance.new("TextLabel", bg)
        moneyLabel.Name = "MoneyLabel"
        moneyLabel.Size = UDim2.new(1,-10,0.5,-5)
        moneyLabel.Position = UDim2.new(0,5,0.5,0)
        moneyLabel.BackgroundTransparency = 1
        moneyLabel.TextScaled = true
        moneyLabel.TextColor3 = Color3.fromRGB(0,255,0)
        moneyLabel.TextStrokeTransparency = 0.2
        moneyLabel.Font = Enum.Font.GothamBold

        task.spawn(function()
            local t = 0
            while esp.Parent do
                t += 0.05
                local pulse = 0.5 + math.sin(t) * 0.5
                glow.Transparency = 0.6 + pulse * 0.3
                task.wait(0.05)
            end
        end)

        activeBrainrotESP = esp
    end

    activeBrainrotESP.Adornee = part
    local bg = activeBrainrotESP:FindFirstChild("Frame")
    if bg then
        local nameLabel = bg:FindFirstChild("NameLabel")
        local moneyLabel = bg:FindFirstChild("MoneyLabel")
        if nameLabel then nameLabel.Text = name end
        if moneyLabel then moneyLabel.Text = formatMoney(moneyPerSecond) end
    end
end

-- Fast, event-driven Best Brainrot tracker
local trackedOverheads = {}
local bestSpawn, bestName, bestMoney = nil, nil, 0

local function recomputeBest()
	bestSpawn, bestName, bestMoney = nil, nil, 0
	for _, info in pairs(trackedOverheads) do
		local displayName = info.displayName
		local generation  = info.generation
		local stolen      = info.stolen
		if displayName and generation and generation:IsA("TextLabel") then
			local isCrafting = (stolen and stolen:IsA("TextLabel") and stolen.Text == "CRAFTING")
			if not isCrafting then
				local money = parseMoneyText(generation.Text)
				if money and money > bestMoney then
					bestMoney = money
					bestName  = displayName.Text
					bestSpawn = info.spawn
				end
			end
		end
	end

	if brainrotEnabled and bestSpawn and bestName then
		createOrUpdateBrainrotESP(bestSpawn, bestName, bestMoney)
	elseif activeBrainrotESP then
		-- Supprime l’ancien ESP s’il n’y a plus de brainrot valide
		activeBrainrotESP:Destroy()
		activeBrainrotESP = nil
	end
end

-- Boucle d’actualisation automatique (plus réactive)
task.spawn(function()
	while true do
		if brainrotEnabled then
			recomputeBest()
		end
		task.wait(0.5) -- refresh toutes les 0.5 secondes (plus fluide que 0.2 sans lag)
	end
end)

local function hookOverhead(spawn, overhead)
	if not overhead or not spawn then return end
	if trackedOverheads[overhead] then return end

	local displayName = overhead:FindFirstChild("DisplayName")
	local generation  = overhead:FindFirstChild("Generation")
	local stolen      = overhead:FindFirstChild("Stolen")

	trackedOverheads[overhead] = {
		spawn = spawn,
		displayName = displayName,
		generation = generation,
		stolen = stolen,
		conns = {}
	}

	local recalc = function() recomputeBest() end
	if generation and generation:IsA("TextLabel") then
		table.insert(trackedOverheads[overhead].conns, generation:GetPropertyChangedSignal("Text"):Connect(recalc))
	end
	if stolen and stolen:IsA("TextLabel") then
		table.insert(trackedOverheads[overhead].conns, stolen:GetPropertyChangedSignal("Text"):Connect(recalc))
	end
	if displayName and displayName:IsA("TextLabel") then
		table.insert(trackedOverheads[overhead].conns, displayName:GetPropertyChangedSignal("Text"):Connect(recalc))
	end

	table.insert(trackedOverheads[overhead].conns, overhead.AncestryChanged:Connect(function(_, _)
		if not overhead:IsDescendantOf(workspace) then
			for _, c in ipairs(trackedOverheads[overhead].conns) do pcall(function() c:Disconnect() end) end
			trackedOverheads[overhead] = nil
			recomputeBest()
		end
	end))

	recomputeBest()
end

local plotsFolder = workspace:FindFirstChild("Plots")
if plotsFolder then
	-- Register existing
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		local pods = plot:FindFirstChild("AnimalPodiums")
		if pods then
			for _, podium in ipairs(pods:GetChildren()) do
				local base = podium:FindFirstChild("Base")
				if base then
					local spawn = base:FindFirstChild("Spawn")
					if spawn then
						local att = spawn:FindFirstChild("Attachment")
						local overhead = att and att:FindFirstChild("AnimalOverhead")
						if overhead then
							hookOverhead(spawn, overhead)
						end
					end
				end
			end
		end
	end

	-- Watch for new overheads anywhere under Plots
	plotsFolder.DescendantAdded:Connect(function(d)
		if not d or d.Name ~= "AnimalOverhead" then return end
		local att = d.Parent
		if not att or att.Name ~= "Attachment" then return end
		local spawn = att.Parent
		if not spawn or spawn.Name ~= "Spawn" then return end
		hookOverhead(spawn, d)
	end)
end

local function setBrainrotESP(state)
	brainrotEnabled = state
	if not state and activeBrainrotESP then
		activeBrainrotESP:Destroy()
		activeBrainrotESP = nil
	end
	if state then recomputeBest() end
end

-- Mise à jour périodique rapide et constante pour ESP Best Brainrot
-- Le système principal est déjà ultra-rapide (événementiel), cette boucle est pour la robustesse.
task.spawn(function()
	while true do
		if brainrotEnabled then
			-- On appelle la fonction de recalcul
			recomputeBest()
		end
		-- Mise à jour rapide et constante toutes les 0.2 secondes.
		-- C'est un excellent équilibre entre vitesse et non-lag.
		task.wait(0.2) 
	end
end)

-- =================
--  ESP Base Time
-- =================

local baseTimeEnabled = false
local activeBaseESPs = {}

-- Fonction pour interpoler entre deux couleurs
local function lerpColor(color1, color2, t)
    return Color3.new(
        color1.R + (color2.R - color1.R) * t,
        color1.G + (color2.G - color1.G) * t,
        color1.B + (color2.B - color1.B) * t
    )
end

-- Création d'un ESP sur une base
local function createBaseESP(target, lockedLabel, remainingLabel)
    if target:FindFirstChild("BaseStateESP") then
        target.BaseStateESP:Destroy()
    end

    local esp = Instance.new("BillboardGui")
    esp.Name = "BaseStateESP"
    esp.Adornee = target
    esp.Size = UDim2.new(0, 150, 0, 35)
    esp.StudsOffset = Vector3.new(0, 3, 0)
    esp.AlwaysOnTop = true
    esp.Parent = target

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.TextStrokeTransparency = 0
    textLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.GothamBold
    textLabel.Text = ""
    textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    textLabel.Parent = esp

    local MAX_TIME = 120
    local flashing = false

    local function updateState()
        if not lockedLabel.Visible then
            textLabel.Text = "Ouvert"
            textLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
            flashing = false
            textLabel.Visible = true
        else
            if remainingLabel and remainingLabel.Visible then
                textLabel.Text = remainingLabel.Text
                local numbers = string.match(textLabel.Text, "(%d+)")
                if numbers then
                    local timeLeft = tonumber(numbers)
                    if timeLeft then
                        local alpha = math.clamp(timeLeft / MAX_TIME, 0, 1)
                        local green = Color3.fromRGB(0, 255, 0)
                        local orange = Color3.fromRGB(255, 170, 0)
                        local red = Color3.fromRGB(255, 0, 0)
                        if alpha > 0.5 then
                            textLabel.TextColor3 = lerpColor(orange, green, (alpha - 0.5) * 2)
                        else
                            textLabel.TextColor3 = lerpColor(red, orange, alpha * 2)
                        end
                        if timeLeft <= 10 and not flashing then
                            flashing = true
                            task.spawn(function()
                                while flashing and esp.Parent do
                                    textLabel.Visible = not textLabel.Visible
                                    task.wait(0.5)
                                end
                                textLabel.Visible = true
                            end)
                        elseif timeLeft > 10 then
                            flashing = false
                            textLabel.Visible = true
                        end
                    end
                end
            else
                textLabel.Text = "VIDE"
                textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                flashing = false
                textLabel.Visible = true
            end
        end
    end

    lockedLabel:GetPropertyChangedSignal("Visible"):Connect(updateState)
    if remainingLabel then
        remainingLabel:GetPropertyChangedSignal("Text"):Connect(updateState)
        remainingLabel:GetPropertyChangedSignal("Visible"):Connect(updateState)
    end

    task.spawn(function()
        while esp.Parent do
            updateState()
            task.wait(0.5)
        end
    end)

    updateState()
    activeBaseESPs[target] = esp
end

-- Scan d’un achat
local function scanPurchase(purchase)
    local lockedLabel, remainingLabel, foundParent
    for _, child in ipairs(purchase:GetChildren()) do
        if child:IsA("Model") or child:IsA("Folder") or child:IsA("BasePart") then
            for _, subChild in ipairs(child:GetChildren()) do
                local billboardGui = subChild:IsA("BillboardGui") and subChild or subChild:FindFirstChildOfClass("BillboardGui")
                if billboardGui then
                    for _, guiChild in ipairs(billboardGui:GetChildren()) do
                        if guiChild:IsA("TextLabel") then
                            if guiChild.Name:lower():find("locked") then
                                lockedLabel = guiChild
                                foundParent = child
                            elseif guiChild.Name:lower():find("time") or guiChild.Name:lower():find("remaining") then
                                remainingLabel = guiChild
                            end
                        end
                    end
                end
            end
        end
    end

    if lockedLabel and foundParent then
        local adorneeTarget = nil
        if foundParent:IsA("BasePart") then
            adorneeTarget = foundParent
        elseif foundParent:IsA("Model") and foundParent.PrimaryPart then
            adorneeTarget = foundParent.PrimaryPart
        elseif foundParent:IsA("Model") then
            local firstPart = foundParent:FindFirstChildWhichIsA("BasePart")
            if firstPart then
                local att = firstPart:FindFirstChild("BaseStateAttachment") or Instance.new("Attachment")
                att.Name = "BaseStateAttachment"
                att.Parent = firstPart
                adorneeTarget = att
            end
        end
        if adorneeTarget then
            createBaseESP(adorneeTarget, lockedLabel, remainingLabel)
        end
    end
end

-- Scan toutes les bases
local function scanAllPlots()
    local Plots = workspace:FindFirstChild("Plots")
    if not Plots then return end
    for _, plot in ipairs(Plots:GetChildren()) do
        if plot:FindFirstChild("Purchases") then
            for _, purchase in ipairs(plot.Purchases:GetChildren()) do
                scanPurchase(purchase)
            end
        end
    end
end

-- Boucle contrôlée par toggle
task.spawn(function()
    while true do
        if baseTimeEnabled then
            scanAllPlots()
        end
        task.wait(5)
    end
end)



-- =================
--  ESP category
-- =================
local espToggle = Instance.new("TextButton", espContainer)

espToggle.Size = UDim2.new(0.95,0,0,36)
espToggle.Position = UDim2.new(0.025,0,0,6)
espToggle.Text = (Config.options.esp_players and "ESP Players: ON" or "ESP Players: OFF")
espToggle.Font = Enum.Font.GothamSemibold
espToggle.TextSize = 14
espToggle.BackgroundColor3 = Color3.fromRGB(0,200,255)
Instance.new("UICorner", espToggle).CornerRadius = UDim.new(0,6)

-- esp base time
local baseTimeToggle = Instance.new("TextButton", espContainer)
baseTimeToggle.Size = UDim2.new(0.95,0,0,36)
baseTimeToggle.Position = UDim2.new(0.025,0,0,178) -- ajuste si besoin
baseTimeToggle.Text = (baseTimeEnabled and "ESP Base Time: ON" or "ESP Base Time: OFF")
baseTimeToggle.Font = Enum.Font.GothamSemibold
baseTimeToggle.TextSize = 14
baseTimeToggle.BackgroundColor3 = Color3.fromRGB(0,200,255)
Instance.new("UICorner", baseTimeToggle).CornerRadius = UDim.new(0,6)

baseTimeToggle.MouseButton1Click:Connect(function()
    baseTimeEnabled = not baseTimeEnabled
    baseTimeToggle.Text = (baseTimeEnabled and "ESP Base Time: ON" or "ESP Base Time: OFF")
    if not baseTimeEnabled then
        for _, esp in pairs(activeBaseESPs) do
            if esp then esp:Destroy() end
        end
        activeBaseESPs = {}
    end
    if type(commitConfig) == "function" then pcall(commitConfig) end
end)




-- ESP implementation using Highlight
local espEnabled = Config.options.esp_players or false
local espObjects = {}
local espConnection = nil

local function getRainbowColor()
    local cycle = tick() / 4
    local hue = (cycle - math.floor(cycle))
    return Color3.fromHSV(hue, 1, 1)
end

local function createESPForPlayer(plr)
    if not plr or not plr.Character then return end
    if plr == localPlayer then return end
    if espObjects[plr] then return end
    local hl = Instance.new("Highlight")
    hl.Name = "EmpireESP"
    hl.FillTransparency = 1
    hl.OutlineTransparency = 0
    hl.Parent = plr.Character
    espObjects[plr] = hl
    plr.CharacterAdded:Connect(function(char)
        task.wait(0.8)
        if espObjects[plr] then
            espObjects[plr].Parent = char
        end
    end)
end

-- BEST BRAINROT toggle
local brainrotToggle = Instance.new("TextButton", espContainer)
brainrotToggle.Size = UDim2.new(0.95,0,0,36)
brainrotToggle.Position = UDim2.new(0.025,0,0,136) -- sous Anti Bee
brainrotToggle.Text = (brainrotEnabled and "ESP Best Brainrot: ON" or "ESP Best Brainrot: OFF")
brainrotToggle.Font = Enum.Font.GothamSemibold
brainrotToggle.TextSize = 14
brainrotToggle.BackgroundColor3 = Color3.fromRGB(0,200,255)
Instance.new("UICorner", brainrotToggle).CornerRadius = UDim.new(0,6)

brainrotToggle.MouseButton1Click:Connect(function()
    setBrainrotESP(not brainrotEnabled)
    brainrotToggle.Text = (brainrotEnabled and "ESP Best Brainrot: ON" or "ESP Best Brainrot: OFF")
    Config.options.esp_best_brainrot = brainrotEnabled
    if type(commitConfig) == "function" then pcall(commitConfig) end
end)



-- Invisible Players toggle (UI)
local invisibleToggle = Instance.new("TextButton", espContainer)
invisibleToggle.Size = UDim2.new(0.95,0,0,36)
invisibleToggle.Position = UDim2.new(0.025,0,0,48) -- place juste sous espToggle
invisibleToggle.Text = (invisibleEnabled and "Invisible Players: ON" or "Invisible Players: OFF")
invisibleToggle.Font = Enum.Font.GothamSemibold
invisibleToggle.TextSize = 14
invisibleToggle.BackgroundColor3 = Color3.fromRGB(0,200,255)
Instance.new("UICorner", invisibleToggle).CornerRadius = UDim.new(0,6)
-- Anti Bee toggle (bloque effets visuels)
local antiBeeToggle = Instance.new("TextButton", espContainer)
antiBeeToggle.Size = UDim2.new(0.95,0,0,36)
antiBeeToggle.Position = UDim2.new(0.025,0,0,92) -- en dessous des autres
antiBeeToggle.Text = (antiBeeEnabled and "Anti Bee: ON" or "Anti Bee: OFF")
antiBeeToggle.Font = Enum.Font.GothamSemibold
antiBeeToggle.TextSize = 14
antiBeeToggle.BackgroundColor3 = Color3.fromRGB(0,200,255)
Instance.new("UICorner", antiBeeToggle).CornerRadius = UDim.new(0,6)


-- Fonctions pour cacher / restaurer joueurs
local function hidePlayer(otherPlayer)
    if not otherPlayer or not otherPlayer.Character then return end
    if hiddenCharacters[otherPlayer] then return end
    local char = otherPlayer.Character
    hiddenCharacters[otherPlayer] = {}

    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("BasePart") or obj:IsA("MeshPart") then
            table.insert(hiddenCharacters[otherPlayer], {
                Part = obj,
                OriginalTransparency = obj.Transparency,
                OriginalCanCollide = obj.CanCollide
            })
            pcall(function()
                obj.Transparency = 1
                obj.CanCollide = false
            end)
        end
    end

    -- Accessoires (Handle)
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Accessory") and child:FindFirstChild("Handle") then
            local h = child.Handle
            table.insert(hiddenCharacters[otherPlayer], {
                Part = h,
                OriginalTransparency = h.Transparency,
                OriginalCanCollide = h.CanCollide
            })
            pcall(function()
                h.Transparency = 1
                h.CanCollide = false
            end)
        end
    end
end

local function restorePlayer(otherPlayer)
    if not hiddenCharacters[otherPlayer] then return end
    for _, data in ipairs(hiddenCharacters[otherPlayer]) do
        if data.Part then
            pcall(function()
                data.Part.Transparency = data.OriginalTransparency
                data.Part.CanCollide = data.OriginalCanCollide
            end)
        end
    end
    hiddenCharacters[otherPlayer] = nil
end

local function setInvisiblePlayers(state)
    invisibleEnabled = state
    invisibleToggle.Text = (invisibleEnabled and "Invisible Players: ON" or "Invisible Players: OFF")
    -- persist dans Config pour sauvegarde
    Config.options.invisible_players = invisibleEnabled
    -- commitConfig() existe plus bas dans ton script ; l'appeler ici est OK
    if type(commitConfig) == "function" then pcall(commitConfig) end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= localPlayer then
            if invisibleEnabled then
                hidePlayer(plr)
                -- ré-appliquer au respawn
                plr.CharacterAdded:Connect(function()
                    if invisibleEnabled then hidePlayer(plr) end
                end)
            else
                restorePlayer(plr)
            end
        end
    end
end

-- UI binding + events
invisibleToggle.MouseButton1Click:Connect(function()
    setInvisiblePlayers(not invisibleEnabled)
end)

-- garder propre si des joueurs arrivent / partent
Players.PlayerAdded:Connect(function(p)
    if invisibleEnabled then
        p.CharacterAdded:Connect(function() hidePlayer(p) end)
    end
end)
Players.PlayerRemoving:Connect(function(p)
    -- restaurer proprement si un joueur quitte
    restorePlayer(p)
end)


local function removeESPForPlayer(plr)
    if espObjects[plr] then
        pcall(function() espObjects[plr]:Destroy() end)
        espObjects[plr] = nil
    end
end

local function enableESP(state)
    espEnabled = state
    espToggle.Text = (espEnabled and "ESP Players: ON" or "ESP Players: OFF")
    if espEnabled then
        for _,plr in ipairs(Players:GetPlayers()) do
            createESPForPlayer(plr)
        end
        Players.PlayerAdded:Connect(function(plr) createESPForPlayer(plr) end)
        Players.PlayerRemoving:Connect(function(plr) removeESPForPlayer(plr) end)
        if espConnection then espConnection:Disconnect() end
        espConnection = RunService.RenderStepped:Connect(function()
            local color = getRainbowColor()
            for _,hl in pairs(espObjects) do
                if hl and hl.Parent then
                    pcall(function() hl.OutlineColor = color end)
                end
            end
        end)
    else
        if espConnection then espConnection:Disconnect() end
        for plr,_ in pairs(espObjects) do
            pcall(function() espObjects[plr]:Destroy() end)
        end
        espObjects = {}
    end
end

espToggle.MouseButton1Click:Connect(function() 
    enableESP(not espEnabled)
end)

-- initialize esp state from config
if Config.options.esp_players then
    enableESP(true)
end

-- =========================
-- Anti Bee (bloque effets)
-- =========================
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Camera = workspace.CurrentCamera
local antiBeeEnabled = Config.options.anti_bee or false
local antiBeeConns = {}
local originalCameraType = Camera and Camera.CameraType or Enum.CameraType.Custom

local function onDescendantAdded(desc)
    pcall(function()
        if not desc then return end
        if desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Explosion")
           or desc:IsA("Fire") or desc:IsA("Smoke") or desc:IsA("Sparkles") then
            -- supprimer les nouveaux effets
            desc:Destroy()
            return
        end
        if desc:IsA("Sound") then
            -- stopper les nouveaux sons
            desc:Stop()
            return
        end
    end)
end

local function destroyExistingEffects()
    -- parcourt workspace + Lighting pour supprimer/stopper tout ce que l'on veut bloquer
    for _, obj in ipairs(workspace:GetDescendants()) do
        pcall(function()
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Explosion")
               or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
                obj:Destroy()
            elseif obj:IsA("Sound") then
                obj:Stop()
            end
        end)
    end
    for _, obj in ipairs(Lighting:GetDescendants()) do
        pcall(function()
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Explosion")
               or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
                obj:Destroy()
            end
        end)
    end
end

local function enableAntiBee()
    antiBeeEnabled = true
    antiBeeToggle.Text = "Anti Bee: ON"
    Config.options.anti_bee = true
    if type(commitConfig) == "function" then pcall(commitConfig) end

    -- supprimer les effets déjà présents
    destroyExistingEffects()

    -- se connecter aux nouveaux descendants (attrape particules/sounds ajoutés partout)
    antiBeeConns.workspace = workspace.DescendantAdded:Connect(onDescendantAdded)
    antiBeeConns.lighting = Lighting.DescendantAdded:Connect(onDescendantAdded)

    -- stopper les sons existants (redondant mais utile)
    for _, s in ipairs(workspace:GetDescendants()) do
        if s:IsA("Sound") then
            pcall(function() s:Stop() end)
        end
    end

    -- tenter d'empêcher les changements de CameraType (empêche certaines sources de "forcer" la cam)
    if Camera then
        originalCameraType = Camera.CameraType
        antiBeeConns.cameraType = Camera:GetPropertyChangedSignal("CameraType"):Connect(function()
            if antiBeeEnabled and Camera and Camera.CameraType ~= Enum.CameraType.Custom then
                Camera.CameraType = Enum.CameraType.Custom
            end
        end)
        -- Bind simple pour maintenir le CameraType (préserve la caméra normale dans la plupart des jeux)
        antiBeeConns.renderBind = RunService:BindToRenderStep("AntiBeeCam", Enum.RenderPriority.Camera.Value, function()
            if antiBeeEnabled and Camera and Camera.CameraType ~= Enum.CameraType.Custom then
                Camera.CameraType = Enum.CameraType.Custom
            end
        end)
    end
end

local function disableAntiBee()
    antiBeeEnabled = false
    antiBeeToggle.Text = "Anti Bee: OFF"
    Config.options.anti_bee = false
    if type(commitConfig) == "function" then pcall(commitConfig) end

    -- déconnecter toutes nos connexions
    if antiBeeConns.workspace then antiBeeConns.workspace:Disconnect() end
    if antiBeeConns.lighting then antiBeeConns.lighting:Disconnect() end
    if antiBeeConns.cameraType then antiBeeConns.cameraType:Disconnect() end
    if antiBeeConns.renderBind then
        pcall(function() RunService:UnbindFromRenderStep("AntiBeeCam") end)
    end
    antiBeeConns = {}

    -- restaurer camera type (si possible)
    pcall(function()
        if Camera then Camera.CameraType = originalCameraType end
    end)
end

-- bouton GUI (déjà créé plus haut)
antiBeeToggle.MouseButton1Click:Connect(function()
    if antiBeeEnabled then
        disableAntiBee()
    else
        enableAntiBee()
    end
end)

-- si config demande activation au démarrage
if Config.options.anti_bee then
    enableAntiBee()
end



-- =================
--  Config category
-- =================
-- Save / Load UI
local saveBtn = Instance.new("TextButton", configContainer)
saveBtn.Size = UDim2.new(0.46, -6, 0, 36)
saveBtn.Position = UDim2.new(0.02, 0, 0, 6)
saveBtn.Text = "Save Config"
saveBtn.Font = Enum.Font.GothamSemibold
saveBtn.TextSize = 14
saveBtn.BackgroundColor3 = Color3.fromRGB(0,200,255)
Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0,6)

local loadBtn = Instance.new("TextButton", configContainer)
loadBtn.Size = UDim2.new(0.46, -6, 0, 36)
loadBtn.Position = UDim2.new(0.52, 0, 0, 6)
loadBtn.Text = "Load Config"
loadBtn.Font = Enum.Font.GothamSemibold
loadBtn.TextSize = 14
loadBtn.BackgroundColor3 = Color3.fromRGB(0,200,255)
Instance.new("UICorner", loadBtn).CornerRadius = UDim.new(0,6)

local autoExecToggle = Instance.new("TextButton", configContainer)
autoExecToggle.Size = UDim2.new(0.95,0,0,36)
autoExecToggle.Position = UDim2.new(0.025,0,0,56)
autoExecToggle.Text = (Config.options.autoexec and "AutoExec: ON" or "AutoExec: OFF")
autoExecToggle.Font = Enum.Font.GothamSemibold
autoExecToggle.TextSize = 14
autoExecToggle.BackgroundColor3 = Color3.fromRGB(0,200,255)
Instance.new("UICorner", autoExecToggle).CornerRadius = UDim.new(0,6)

-- Save function
local function gatherCurrentConfig()
    local cfg = {
        binds = {
            PlaceStair = keybinds.PlaceStair.Name,
            PhantomToggle = keybinds.PhantomToggle.Name,
            FloorHackToggle = keybinds.FloorHackToggle.Name
        },
        gui_position = {
            X = mainFrame.Position.X.Scale,
            Y = mainFrame.Position.Y.Scale,
            OffsetX = mainFrame.Position.X.Offset,
            OffsetY = mainFrame.Position.Y.Offset
        },
        options = {
            -- mouvements / hacks
            phantom = phantomActive,
            floorhack = floorHackActive,

            -- ESP
            esp_players = espEnabled,
            invisible_players = invisibleEnabled,
            anti_bee = antiBeeEnabled,
            esp_best_brainrot = brainrotEnabled,
            esp_remaining_time = remainingTimerEnabled,
            esp_base_time = baseTimeEnabled,

            -- visuels
            decorationsTransparency = decorationsTransparencyEnabled,
            decorationsTransparencyValue = decorationsTransparencyValue,

            -- autoexec
            autoexec = Config.options.autoexec or false
        }
    }
    return cfg
end



local function loadConfigFromDisk()
    if not canRead or not canIsFile or not isfile(ConfigFileName) then
        warn("[EMPIRE] readfile/isfile not available or config missing.")
        return false
    end
    local ok, s = pcall(readfile, ConfigFileName)
    if not ok or not s then return false end
    local parsed = decodeTable(s)
    if type(parsed) ~= "table" then return false end

    -- reposition GUI si sauvegardé
    if parsed.gui_position then
        mainFrame.Position = UDim2.new(
            parsed.gui_position.X,
            parsed.gui_position.OffsetX,
            parsed.gui_position.Y,
            parsed.gui_position.OffsetY
        )
    end

    -- appliquer les binds
    if parsed.binds then
        if parsed.binds.PlaceStair then keybinds.PlaceStair = keyFromName(parsed.binds.PlaceStair) end
        if parsed.binds.PhantomToggle then keybinds.PhantomToggle = keyFromName(parsed.binds.PhantomToggle) end
        if parsed.binds.FloorHackToggle then keybinds.FloorHackToggle = keyFromName(parsed.binds.FloorHackToggle) end
    end

    -- appliquer les options avec les vraies fonctions
    if parsed.options then
        -- mouvements / hacks
        setPhantomState(parsed.options.phantom or false)
        setFloorHack(parsed.options.floorhack or false)

        -- ESP Players
        enableESP(parsed.options.esp_players or false)

        -- Invisible Players
        setInvisiblePlayers(parsed.options.invisible_players or false)

        -- Anti Bee
        if parsed.options.anti_bee then
            enableAntiBee()
        else
            disableAntiBee()
        end

        -- Brainrot ESP
        setBrainrotESP(parsed.options.esp_best_brainrot or false)

        -- RemainingTime ESP
        remainingTimerEnabled = parsed.options.esp_remaining_time or false
        if timerToggle then
            timerToggle.Text = (remainingTimerEnabled and "ESP RemainingTime: ON" or "ESP RemainingTime: OFF")
        end

        -- Base Time ESP
        baseTimeEnabled = parsed.options.esp_base_time or false
        if baseTimeToggle then
            baseTimeToggle.Text = (baseTimeEnabled and "ESP Base Time: ON" or "ESP Base Time: OFF")
        end

        -- déco
        decorationsTransparencyEnabled = (parsed.options.decorationsTransparency == nil and true) or parsed.options.decorationsTransparency
        decorationsTransparencyValue = parsed.options.decorationsTransparencyValue or decorationsTransparencyValue

        -- apply decorations transparency immediately if enabled
        if decorationsTransparencyEnabled then
            pcall(makeDecorationsTransparent)
        end
    end

    -- update les textes UI
    placeBtn.Text = "Poser escalier [".. keybinds.PlaceStair.Name .."]"
    phantomBtn.Text = (phantomActive and "Phantom Glide (ON)" or "Phantom Glide (OFF)") .. " [".. keybinds.PhantomToggle.Name .."]"
    floorBtn.Text = (floorHackActive and "Floor Hack (ON)" or "Floor Hack (OFF)") .. " [".. keybinds.FloorHackToggle.Name .."]"
    decoToggle.Text = (decorationsTransparencyEnabled and "Decorations Transparency: ON" or "Decorations Transparency: OFF")
    espToggle.Text = (espEnabled and "ESP Players: ON" or "ESP Players: OFF")

    return true
end

saveBtn.MouseButton1Click:Connect(function()
    local ok = commitConfig()
    if ok then
        -- update current Config table
        Config = gatherCurrentConfig()
        Config.options.autoexec = Config.options.autoexec or false
        print("[EMPIRE] Configuration saved to "..ConfigFileName)
    else
        warn("[EMPIRE] Failed to save configuration.")
    end
end)

loadBtn.MouseButton1Click:Connect(function()
    local ok = loadConfigFromDisk()
    if ok then
        print("[EMPIRE] Configuration loaded from "..ConfigFileName)
    else
        warn("[EMPIRE] Failed to load configuration.")
    end
end)


-- =================
--  AutoExec support
-- =================
-- We'll attempt to create an "autoexec" folder and write a launcher file that will:
--  - read the saved EmpireConfig.json and then run the script automatically.
-- Because writing a full copy of the script into autoexec can be heavy, we create
-- a minimal autoexec loader that will load the saved config and then attempt to run
-- the main script by loading a stored copy (if present). We'll also attempt to write
-- a copy of current script as "Empire_autoexec_script.lua" if writefile is available.
-- NOTE: behaviour depends on the executor autoexec implementation (Xeno commonly supports autoexec folder).

local function tryMakeAutoexecFolder()
    if not canMakeFolder or not canIsFolder then
        -- some exploits only provide writefile but not makefolder; we still try to write to "autoexec/..." path
        return true
    end
    if not isfolder("autoexec") then
        local ok, e = pcall(function() makefolder("autoexec") end)
        if not ok then
            warn("[EMPIRE] makefolder autoexec failed:", e)
            return false
        end
    end
    return true
end

local function writeAutoexecFiles(selfScriptSource)
    if not canWrite then
        warn("[EMPIRE] writefile unavailable; cannot create autoexec files.")
        return false
    end
    local ok = tryMakeAutoexecFolder()
    if not ok then return false end

    -- launcher content: tries to load saved config and run embedded script if present
    local launcher = [[
-- Empire AutoExec loader (generated)
local function safeRead(fn)
    local ok, s = pcall(readfile, fn)
    if ok then return s end
    return nil
end
-- try to load config (EmpireConfig.json)
local cfg = nil
pcall(function()
    local s = safeRead("]]..ConfigFileName..[[")
    if s then
        local HttpService = game:GetService("HttpService")
        local ok, parsed = pcall(function() return HttpService:JSONDecode(s) end)
        if ok and type(parsed) == "table" then cfg = parsed end
    end
end)

-- If an embedded script was saved as "Empire_autoexec_script.lua", execute it.
pcall(function()
    if isfile("autoexec/Empire_autoexec_script.lua") then
        local s = readfile("autoexec/Empire_autoexec_script.lua")
        if s then
            local f, err = loadstring(s)
            if f then
                pcall(f)
            end
        end
    end
end)
    ]]

    local launcherPath = "autoexec/Empire_autoexec_launcher.lua"
    local ok1, e1 = pcall(function() writefile(launcherPath, launcher) end)
    if not ok1 then warn("[EMPIRE] writefile launcher failed:", e1) end

    -- if we have the source provided, write a copy into autoexec to try to run the full script
    if selfScriptSource and type(selfScriptSource) == "string" and #selfScriptSource > 10 then
        local scriptPath = "autoexec/Empire_autoexec_script.lua"
        local ok2, e2 = pcall(function() writefile(scriptPath, selfScriptSource) end)
        if not ok2 then warn("[EMPIRE] writefile script failed:", e2) end
    end

    return true
end

-- Toggle UI for autoexec
local function setAutoExecFlag(state)
    Config.options.autoexec = state
    autoExecToggle.Text = (state and "AutoExec: ON" or "AutoExec: OFF")
    if state then
        -- attempt to write launcher and script copy
        -- To write a copy of the full running script, we attempt to build "self source" by collecting a trimmed version of code.
        -- Best-effort: we create a small wrapper + a copy of current file if possible.
        local selfSource = nil
        -- We try to get our own source by reading the file if the user originally loaded from local file path
        -- but usually the exploit executed the script directly; so we can't guarantee perfect self-copy.
        -- We'll write a practical launcher (above) and attempt to write a saved "script snapshot" if the script has set shared.EMPIRE_SELF_SOURCE.
        if type(shared) == "table" and type(shared.EMPIRE_SELF_SOURCE) == "string" then
            selfSource = shared.EMPIRE_SELF_SOURCE
        end
        -- If no shared source available, we'll write a lightweight notice file so user can manually place the script into Xeno's autoexec folder:
        if not selfSource then
            selfSource = "-- Empire Autoexec placeholder\n-- Your executor attempted to enable AutoExec but a full self-copy could not be created automatically.\n-- If Xeno runs scripts placed in its autoexec folder, place your current Empire script as:\n-- autoexec/Empire_autoexec_script.lua\n-- Also keep EmpireConfig.json at the root of the executor folder.\n"
        end

        local ok = writeAutoexecFiles(selfSource)
        if ok then
            print("[EMPIRE] AutoExec files written to autoexec/. If Xeno supports autoexec, the script will run automatically next launch.")
        else
            warn("[EMPIRE] AutoExec creation failed.")
        end
    else
        -- disable: remove autoexec files if possible
        if canWrite and isfile and isfile("autoexec/Empire_autoexec_launcher.lua") then
            pcall(function() writefile("autoexec/Empire_autoexec_launcher.lua", "") end)
        end
    end
end

autoExecToggle.MouseButton1Click:Connect(function()
    setAutoExecFlag(not Config.options.autoexec)
end)

-- Initialize autoexec state from config
if Config.options.autoexec then
    autoExecToggle.Text = "AutoExec: ON"
else
    autoExecToggle.Text = "AutoExec: OFF"
end

-- =================
--  Final: hook save on exit / provide manual save on toggle changes
-- =================
local function commitConfig()
    local cfg = gatherCurrentConfig()
    cfg.options.autoexec = (cfg.options.autoexec == true) and true or false

    if not canWrite then
        warn("[EMPIRE] writefile not available; cannot save config.")
        return false
    end

    local encoded = encodeTable(cfg)
    if not encoded then
        warn("[EMPIRE] JSON encode failed; config not saved.")
        return false
    end

    local ok, err = pcall(function()
        writefile(ConfigFileName, encoded)
    end)

    if not ok then
        warn("[EMPIRE] writefile failed:", err)
        return false
    end

    Config = cfg
    return true
end

local function saveConfigToDisk()
    return commitConfig()
end


local UserInputService = game:GetService("UserInputService")

-- touche pour ouvrir/fermer le GUI : Control Droite
local toggleKey = Enum.KeyCode.RightControl

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end -- ignore si capturé par autre chose
    if input.KeyCode == toggleKey then
        mainFrame.Visible = not mainFrame.Visible
    end
end)


-- Auto-load config au lancement
task.spawn(function()
    task.wait(0.5) -- laisse le temps au GUI de se créer
    local ok = loadConfigFromDisk()
    if ok then
        print("[EMPIRE] Configuration auto-load réussie depuis "..ConfigFileName)
    else
        warn("[EMPIRE] Aucune configuration trouvée ou erreur de lecture.")
    end
end)




-- When user toggles phantom/floor via UI we should update config saved states
-- Connectors already update variables; ensure commit on change events
-- We'll override the UI buttons' actions to commit after toggling (they already toggle local state)
phantomBtn.MouseButton1Click:Connect(function()
    setPhantomState(not phantomActive)
    commitConfig()
end)
floorBtn.MouseButton1Click:Connect(function()
    setFloorHack(not floorHackActive)
    commitConfig()
end)
decoToggle.MouseButton1Click:Connect(function()
    commitConfig()
end)
espToggle.MouseButton1Click:Connect(function()
    commitConfig()
end)
autoExecToggle.MouseButton1Click:Connect(function()
    commitConfig()
end)
saveBtn.MouseButton1Click:Connect(function()
    local ok = commitConfig()
    if ok then print("[EMPIRE] Configuration saved to "..ConfigFileName) else warn("[EMPIRE] Failed to save configuration.") end
end)
loadBtn.MouseButton1Click:Connect(function()
    loadConfigFromDisk()
end)

-- Make sure current UI labels reflect actual binds and states
placeBindBtn.Text = "[" .. keybinds.PlaceStair.Name .. "]"
phantomBindBtn.Text = "[" .. keybinds.PhantomToggle.Name .. "]"
floorBindBtn.Text = "[" .. keybinds.FloorHackToggle.Name .. "]"
placeBtn.Text = "Poser escalier [" .. keybinds.PlaceStair.Name .. "]"
phantomBtn.Text = (phantomActive and "Phantom Glide (ON)" or "Phantom Glide (OFF)") .. " [".. keybinds.PhantomToggle.Name .."]"
floorBtn.Text = (floorHackActive and "Floor Hack (ON)" or "Floor Hack (OFF)") .. " [".. keybinds.FloorHackToggle.Name .."]"

-- Persist a lightweight self-source if possible (helps autoexec create a full script snapshot)
-- If you run this script by loading a local file, set shared.EMPIRE_SELF_SOURCE = readfile("path/to/this.lua")
-- so AutoExec can copy the real script into autoexec/.
-- We still create a launcher even without that.
shared = shared or {}
if not shared.EMPIRE_SELF_SOURCE then
    -- optional: user can set shared.EMPIRE_SELF_SOURCE externally if they load script from a file
    shared.EMPIRE_SELF_SOURCE = nil
end

-- Print final ready message
print("[EMPIRE] GUI & systems loaded. Player / ESP / Config ready.")

-- If the config indicated phantom/floor active at start, enable them
if Config.options.phantom and phantomActive then setPhantomState(true) end
if Config.options.floorhack and floorHackActive then setFloorHack(true) end
if Config.options.anti_bee then
    blockEffects(true)
end

-- initialiser l'état Invisible Players si configuré
if Config.options.invisible_players then
    -- setInvisiblePlayers est défini plus haut (si tu as collé le bloc ESP)
    setInvisiblePlayers(true)
end




-- Example of checking is user have a premium:
if KeyPremium then
	print("Key is premium!")
end


