--!nocheck
-- WTF Del3livery v5 | Murder Mystery Luau Script
-- Black Two-Column UI + Search + HUD Watermark + Void Fling + Murderer-Only Aim
-- Executor APIs (safe fallbacks): gethui, Drawing, firetouchinterest, getcustomasset, isfile

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local Config = {
    ScriptName = "wtf del3very;3",
    AuthorText = "by del1very;3",
    CustomLogoFile = "logo_wtf.jpg", -- скопируйте logo_wtf.jpg в папку workspace экзекутора
    ToggleKey = Enum.KeyCode.K,

    Roles = {
        KnifeNames = { "Knife" },
        GunNames = { "Gun", "Revolver" },
    },

    Farm = {
        CoinContainerNames = { "CoinContainer" },
        CoinPartNames = { "Coin_Server", "Coin" },
        DroppedGunNames = { "GunDrop" },
        CoinTweenSpeed = 28,
        CoinStepDelay = 0.08,
    },

    Combat = {
        AimFOV = 150,
        AimSmoothness = 0.35,
        AimWallCheck = true,
        AimOnlyMurderer = true,
        AutoShotDelay = 0.25,
        KillAllDelay = 0.2,
        FlingPower = 9e7,
        FlingDuration = 1.2,
        FlingMaxDistance = 280,
    },

    Movement = {
        FlySpeed = 55,
        FreeCamSpeed = 60,
        FreeCamSensitivity = 0.25,
        InvisibleSinkHeight = -9.5,
    },

    Colors = {
        Bg = Color3.fromRGB(10, 10, 13),
        Sidebar = Color3.fromRGB(13, 13, 17),
        Card = Color3.fromRGB(18, 18, 23),
        RowHover = Color3.fromRGB(26, 26, 33),
        Border = Color3.fromRGB(40, 40, 48),
        TrackOff = Color3.fromRGB(36, 36, 44),
        Accent = Color3.fromRGB(242, 244, 248),
        Text = Color3.fromRGB(232, 234, 240),
        Muted = Color3.fromRGB(125, 130, 145),
        Murderer = Color3.fromRGB(235, 70, 70),
        Sheriff = Color3.fromRGB(75, 155, 250),
        Innocent = Color3.fromRGB(75, 210, 130),
    },
}

local function validateConfig(cfg)
    assert(type(cfg) == "table", "[wtf del3very;3] Config must be a table")
    assert(#cfg.Roles.KnifeNames > 0 and #cfg.Roles.GunNames > 0, "[wtf del3very;3] Role tool names missing")
    assert(#cfg.Farm.DroppedGunNames > 0, "[wtf del3very;3] DroppedGunNames missing")
    assert(cfg.Combat.AimFOV > 0, "[wtf del3very;3] AimFOV must be > 0")
end
validateConfig(Config)

-- ============================================================================
-- STATE & CLEANUP
-- ============================================================================
local State = {
    Unloaded = false,
    IsFlinging = false,
    SelectedTarget = nil,
    ShowWatermark = true,
    ESP = false,
    Invisible = false,
    Fly = false,
    Noclip = false,
    FreeCam = false,
    Aim = false,
    AutoShot = false,
    KillAll = false,
    KillSheriff = false,
    AutoFarmCoins = false,
    AutoRevolver = false,
}

local Connections = {}
local ESPObjects = {}
local ActiveMovers = {}
local SavedInvisible = { HipHeight = nil, CameraOffset = nil, Transparencies = {}, DescConn = nil }
local Searchables = {}
local FovCircle = nil
local RootGui = nil

local function track(conn)
    table.insert(Connections, conn)
    return conn
end

local function tween(obj, info, props)
    local t = TweenService:Create(obj, info, props)
    t:Play()
    return t
end

local function safeGetUIContainer()
    if type(gethui) == "function" then
        local ok, res = pcall(gethui)
        if ok and typeof(res) == "Instance" then return res end
    end
    return CoreGui
end

local uiParent = safeGetUIContainer()
local oldGui = uiParent:FindFirstChild("WTF_Del3livery_UI")
if oldGui then oldGui:Destroy() end

-- ============================================================================
-- HELPERS
-- ============================================================================
local function getCharParts(player)
    local char = player and player.Character
    if not char then return nil, nil, nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    return char, hrp, hum
end

local function isAlive(player)
    local _, hrp, hum = getCharParts(player)
    return hrp ~= nil and hum ~= nil and hum.Health > 0
end

local function hasToolInList(player, names)
    if not player then return false, nil end
    local function scan(container)
        if not container then return nil end
        for _, name in ipairs(names) do
            local item = container:FindFirstChild(name)
            if item and item:IsA("Tool") then return item end
        end
        return nil
    end
    local tool = scan(player.Character) or scan(player:FindFirstChildOfClass("Backpack"))
    return tool ~= nil, tool
end

local function getPlayerRole(player)
    if hasToolInList(player, Config.Roles.KnifeNames) then
        return "Murderer", Config.Colors.Murderer
    end
    if hasToolInList(player, Config.Roles.GunNames) then
        return "Sheriff", Config.Colors.Sheriff
    end
    return "Innocent", Config.Colors.Innocent
end

local function findPlayerByRole(roleName)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isAlive(p) and getPlayerRole(p) == roleName then
            return p
        end
    end
    return nil
end

local function equipToolFromNames(names)
    local char, _, hum = getCharParts(LocalPlayer)
    if not char or not hum then return nil end
    for _, name in ipairs(names) do
        local equipped = char:FindFirstChild(name)
        if equipped and equipped:IsA("Tool") then return equipped end
        local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
        local inBp = bp and bp:FindFirstChild(name)
        if inBp and inBp:IsA("Tool") then
            hum:EquipTool(inBp)
            return inBp
        end
    end
    return nil
end

local function touchPart(part)
    local _, hrp = getCharParts(LocalPlayer)
    if not hrp or not part or not part:IsA("BasePart") then return end
    if type(firetouchinterest) == "function" then
        pcall(firetouchinterest, hrp, part, 0)
        task.wait()
        pcall(firetouchinterest, hrp, part, 1)
    else
        hrp.CFrame = part.CFrame
    end
end

-- ============================================================================
-- FEATURE: ESP
-- ============================================================================
local function clearESPForPlayer(player)
    local entry = ESPObjects[player]
    if entry then
        if entry.Highlight then entry.Highlight:Destroy() end
        if entry.Billboard then entry.Billboard:Destroy() end
        ESPObjects[player] = nil
    end
end

local function updateESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char, hrp, hum = getCharParts(player)
            if State.ESP and char and hrp and hum and hum.Health > 0 then
                local role, color = getPlayerRole(player)
                local entry = ESPObjects[player]
                if not entry then
                    entry = {}
                    ESPObjects[player] = entry
                end

                if not entry.Highlight or entry.Highlight.Parent ~= RootGui then
                    if entry.Highlight then entry.Highlight:Destroy() end
                    local hl = Instance.new("Highlight")
                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.FillTransparency = 0.65
                    hl.OutlineTransparency = 0
                    hl.Parent = RootGui
                    entry.Highlight = hl
                end
                entry.Highlight.Adornee = char
                entry.Highlight.FillColor = color
                entry.Highlight.OutlineColor = color

                if not entry.Billboard or entry.Billboard.Parent ~= RootGui then
                    if entry.Billboard then entry.Billboard:Destroy() end
                    local bb = Instance.new("BillboardGui")
                    bb.Size = UDim2.fromOffset(170, 40)
                    bb.StudsOffset = Vector3.new(0, 3.2, 0)
                    bb.AlwaysOnTop = true
                    bb.Parent = RootGui

                    local lbl = Instance.new("TextLabel")
                    lbl.Size = UDim2.fromScale(1, 1)
                    lbl.BackgroundTransparency = 1
                    lbl.Font = Enum.Font.GothamBold
                    lbl.TextSize = 12
                    lbl.TextStrokeTransparency = 0.2
                    lbl.Parent = bb
                    entry.Billboard = bb
                    entry.Label = lbl
                end

                local _, myHrp = getCharParts(LocalPlayer)
                local dist = myHrp and math.floor((myHrp.Position - hrp.Position).Magnitude) or 0
                entry.Billboard.Adornee = hrp
                entry.Label.TextColor3 = color
                entry.Label.Text = string.format("%s\n[%s | %dm]", player.Name, role, dist)
            else
                clearESPForPlayer(player)
            end
        end
    end
end

track(Players.PlayerRemoving:Connect(clearESPForPlayer))

-- ============================================================================
-- FEATURE: INVISIBLE (Скрытие тела, предметов в руках и уход под пол)
-- ============================================================================
local function hideInstanceVisual(inst)
    if (inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture")) and inst.Name ~= "HumanoidRootPart" then
        if SavedInvisible.Transparencies[inst] == nil then
            SavedInvisible.Transparencies[inst] = inst.Transparency
        end
        inst.Transparency = 1
    elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") then
        if SavedInvisible.Transparencies[inst] == nil then
            SavedInvisible.Transparencies[inst] = inst.Enabled
        end
        inst.Enabled = false
    end
end

local function applyInvisible(enabled)
    local char, _, hum = getCharParts(LocalPlayer)
    if SavedInvisible.DescConn then
        SavedInvisible.DescConn:Disconnect()
        SavedInvisible.DescConn = nil
    end
    if not char or not hum then return end

    if enabled then
        if SavedInvisible.HipHeight == nil then
            SavedInvisible.HipHeight = hum.HipHeight
            SavedInvisible.CameraOffset = hum.CameraOffset
        end
        hum.HipHeight = Config.Movement.InvisibleSinkHeight
        hum.CameraOffset = Vector3.new(0, math.abs(Config.Movement.InvisibleSinkHeight), 0)

        for _, desc in ipairs(char:GetDescendants()) do
            hideInstanceVisual(desc)
        end
        SavedInvisible.DescConn = char.DescendantAdded:Connect(function(desc)
            if State.Invisible then hideInstanceVisual(desc) end
        end)
    else
        if SavedInvisible.HipHeight ~= nil then
            hum.HipHeight = SavedInvisible.HipHeight
            hum.CameraOffset = SavedInvisible.CameraOffset or Vector3.zero
            SavedInvisible.HipHeight = nil
            SavedInvisible.CameraOffset = nil
        end
        for inst, orig in pairs(SavedInvisible.Transparencies) do
            if inst and inst.Parent then
                if typeof(orig) == "boolean" then
                    inst.Enabled = orig
                else
                    inst.Transparency = orig
                end
            end
        end
        table.clear(SavedInvisible.Transparencies)
    end
end

-- ============================================================================
-- FEATURE: FLY / NOCLIP / FREE CAMERA
-- ============================================================================
local function clearFlyMovers()
    for _, obj in ipairs(ActiveMovers) do
        if obj and obj.Parent then obj:Destroy() end
    end
    table.clear(ActiveMovers)
    local _, _, hum = getCharParts(LocalPlayer)
    if hum then hum.PlatformStand = false end
end

local function setupFly()
    clearFlyMovers()
    local _, hrp, hum = getCharParts(LocalPlayer)
    if not hrp or not hum then return end
    hum.PlatformStand = true

    local att = Instance.new("Attachment", hrp)
    att.Name = "WTF_FlyAtt"
    local lv = Instance.new("LinearVelocity", hrp)
    lv.Name = "WTF_FlyVel"
    lv.Attachment0 = att
    lv.MaxForce = math.huge
    lv.VectorVelocity = Vector3.zero
    local ao = Instance.new("AlignOrientation", hrp)
    ao.Name = "WTF_FlyOri"
    ao.Attachment0 = att
    ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
    ao.Responsiveness = 200
    ao.MaxTorque = math.huge
    ao.CFrame = Camera.CFrame

    table.insert(ActiveMovers, att)
    table.insert(ActiveMovers, lv)
    table.insert(ActiveMovers, ao)
end

local freeCamCFrame = nil
local freeCamYaw, freeCamPitch = 0, 0

local function setFreeCam(enabled)
    local _, hrp, hum = getCharParts(LocalPlayer)
    if enabled then
        freeCamCFrame = Camera.CFrame
        local rx, ry, _ = freeCamCFrame:ToEulerAnglesYXZ()
        freeCamPitch, freeCamYaw = rx, ry
        Camera.CameraType = Enum.CameraType.Scriptable
        if hrp then hrp.Anchored = true end
        if hum then hum.WalkSpeed = 0 end
    else
        Camera.CameraType = Enum.CameraType.Custom
        if hum then
            Camera.CameraSubject = hum
            hum.WalkSpeed = 16
        end
        if hrp then hrp.Anchored = false end
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        freeCamCFrame = nil
    end
end

-- ============================================================================
-- FEATURE: AIM & AUTO SHOT (Murderer Only toggleable)
-- ============================================================================
local function initFovCircle()
    local ok, circle = pcall(function()
        local c = Drawing.new("Circle")
        c.Thickness = 1.5
        c.NumSides = 64
        c.Radius = Config.Combat.AimFOV
        c.Filled = false
        c.Color = Config.Colors.Accent
        c.Visible = false
        return c
    end)
    if ok and circle then FovCircle = circle end
end
initFovCircle()

local function hasLineOfSight(origin, targetPart)
    if not Config.Combat.AimWallCheck then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local char = LocalPlayer.Character
    params.FilterDescendantsInstances = char and { char, targetPart.Parent } or { targetPart.Parent }
    return Workspace:Raycast(origin, targetPart.Position - origin, params) == nil
end

local function getBestAimTarget()
    local viewportCenter = Camera.ViewportSize / 2
    local bestPlayer, bestPart, bestDist = nil, nil, Config.Combat.AimFOV

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and isAlive(player) then
            local targetRole = getPlayerRole(player)
            if Config.Combat.AimOnlyMurderer and targetRole ~= "Murderer" then
                continue
            end
            local char = player.Character
            local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
            if head then
                local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
                if onScreen then
                    local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - viewportCenter).Magnitude
                    if dist2D < bestDist and hasLineOfSight(Camera.CFrame.Position, head) then
                        bestDist, bestPlayer, bestPart = dist2D, player, head
                    end
                end
            end
        end
    end
    return bestPlayer, bestPart
end

-- ============================================================================
-- FEATURE: KILL / SOON (VOID FLING С ЗАЩИТОЙ СЕБЯ)
-- ============================================================================
local function performKnifeAttack(targetPlayer)
    local knife = equipToolFromNames(Config.Roles.KnifeNames)
    if not knife then return false end
    local _, myHrp = getCharParts(LocalPlayer)
    local _, targetHrp = getCharParts(targetPlayer)
    if not myHrp or not targetHrp then return false end

    myHrp.CFrame = targetHrp.CFrame * CFrame.new(0, 0, 2.2)
    knife:Activate()
    local handle = knife:FindFirstChild("Handle")
    if handle and type(firetouchinterest) == "function" then
        pcall(firetouchinterest, targetHrp, handle, 0)
        task.wait()
        pcall(firetouchinterest, targetHrp, handle, 1)
    end
    return true
end

local function zeroCharacterVelocity(char)
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
        end
    end
end

local function executeSoon(targetPlayer, statusCallback)
    if State.IsFlinging or not targetPlayer or not isAlive(targetPlayer) then return end
    local myChar, myHrp, myHum = getCharParts(LocalPlayer)
    local targetChar, targetHrp = getCharParts(targetPlayer)
    if not myChar or not myHrp or not myHum or not targetChar or not targetHrp then return end

    local voidY = Workspace.FallenPartsDestroyHeight + 35
    if myHrp.Position.Y <= voidY then return end

    State.IsFlinging = true
    local savedCFrame = myHrp.CFrame
    local oldProps = myHrp.CustomPhysicalProperties
    myHrp.CustomPhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5)

    myHum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
    myHum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    myHum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    myHum.PlatformStand = true

    local oldCollide = {}
    for _, p in ipairs(myChar:GetDescendants()) do
        if p:IsA("BasePart") then
            oldCollide[p] = p.CanCollide
            p.CanCollide = (p == myHrp or p.Name == "UpperTorso" or p.Name == "LowerTorso" or p.Name == "Torso")
        end
    end

    local myCheck = myChar:FindFirstChild("UpperTorso") or myChar:FindFirstChild("Torso") or myHrp
    local tCheck = targetChar:FindFirstChild("UpperTorso") or targetChar:FindFirstChild("Torso") or targetHrp
    local okCol, canCol = pcall(function() return myCheck:CanCollideWith(tCheck) end)
    if okCol and canCol == false then
        if statusCallback then statusCallback("server disabled player collisions (void fling limited)") end
    elseif statusCallback then
        statusCallback("sending " .. targetPlayer.Name .. " to void...")
    end

    local bav = Instance.new("BodyAngularVelocity")
    bav.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bav.P = math.huge
    bav.AngularVelocity = Vector3.new(Config.Combat.FlingPower, Config.Combat.FlingPower, Config.Combat.FlingPower)
    bav.Parent = myHrp

    local thrust = Instance.new("BodyThrust")
    thrust.Force = Vector3.new(6e5, -4e5, 6e5)
    thrust.Location = myHrp.Position
    thrust.Parent = myHrp

    local startTime = os.clock()
    while os.clock() - startTime < Config.Combat.FlingDuration do
        if State.Unloaded or not isAlive(targetPlayer) or not isAlive(LocalPlayer) then break end
        if targetHrp.Position.Y <= voidY then break end
        if (targetHrp.Position - savedCFrame.Position).Magnitude > Config.Combat.FlingMaxDistance then break end

        local pred = targetHrp.CFrame + (targetHrp.AssemblyLinearVelocity * 0.08)
        if (myHrp.Position - pred.Position).Magnitude > 2.2 then
            myHrp.CFrame = pred
        end
        thrust.Location = myHrp.Position
        RunService.Heartbeat:Wait()
    end

    if bav and bav.Parent then bav:Destroy() end
    if thrust and thrust.Parent then thrust:Destroy() end
    myHrp.CustomPhysicalProperties = oldProps

    for _ = 1, 6 do
        if not myChar.Parent then break end
        zeroCharacterVelocity(myChar)
        myHrp.CFrame = savedCFrame
        RunService.Heartbeat:Wait()
    end

    for part, can in pairs(oldCollide) do
        if part and part.Parent then part.CanCollide = can end
    end
    myHum.PlatformStand = false
    myHum:ChangeState(Enum.HumanoidStateType.GettingUp)
    task.wait(0.15)
    if myHum.Parent then
        myHum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        myHum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
        myHum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
    end
    State.IsFlinging = false
    if statusCallback and okCol and canCol ~= false then
        statusCallback("target: " .. targetPlayer.Name)
    end
end

local function smartKillPlayer(targetPlayer, statusCallback)
    if not targetPlayer or not isAlive(targetPlayer) then return end
    if hasToolInList(LocalPlayer, Config.Roles.KnifeNames) then
        performKnifeAttack(targetPlayer)
    elseif hasToolInList(LocalPlayer, Config.Roles.GunNames) then
        local gun = equipToolFromNames(Config.Roles.GunNames)
        local char = targetPlayer.Character
        local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
        if gun and head then
            Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, head.Position)
            gun:Activate()
        end
    else
        executeSoon(targetPlayer, statusCallback)
    end
end

-- ============================================================================
-- FEATURE: FARM
-- ============================================================================
local function findCoins()
    local coins = {}
    for _, desc in ipairs(Workspace:GetDescendants()) do
        if desc:IsA("BasePart") then
            local isCoin = table.find(Config.Farm.CoinPartNames, desc.Name) ~= nil
            if not isCoin and desc.Parent then
                isCoin = table.find(Config.Farm.CoinContainerNames, desc.Parent.Name) ~= nil
            end
            if isCoin and desc:FindFirstChildOfClass("TouchTransmitter") then
                table.insert(coins, desc)
            end
        end
    end
    return coins
end

local function findDroppedGun()
    for _, name in ipairs(Config.Farm.DroppedGunNames) do
        local gun = Workspace:FindFirstChild(name, true)
        if gun then
            if gun:IsA("BasePart") then return gun end
            local part = gun:FindFirstChildWhichIsA("BasePart")
            if part then return part end
        end
    end
    return nil
end

-- ============================================================================
-- RUNTIME LOOPS
-- ============================================================================
track(RunService.RenderStepped:Connect(function(dt)
    if State.Unloaded then return end
    Camera = Workspace.CurrentCamera
    updateESP()

    if FovCircle then
        FovCircle.Visible = State.Aim or State.AutoShot
        FovCircle.Radius = Config.Combat.AimFOV
        FovCircle.Position = Camera.ViewportSize / 2
    end

    if State.FreeCam and freeCamCFrame then
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
            local delta = UserInputService:GetMouseDelta()
            freeCamYaw -= math.rad(delta.X * Config.Movement.FreeCamSensitivity)
            freeCamPitch = math.clamp(freeCamPitch - math.rad(delta.Y * Config.Movement.FreeCamSensitivity), -math.rad(89), math.rad(89))
        else
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end
        local rot = CFrame.fromEulerAnglesYXZ(freeCamPitch, freeCamYaw, 0)
        local move = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += rot.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= rot.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += rot.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= rot.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.E) or UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.Q) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.yAxis end
        if move.Magnitude > 0 then move = move.Unit * Config.Movement.FreeCamSpeed * dt end
        freeCamCFrame = CFrame.new(freeCamCFrame.Position + move) * rot
        Camera.CFrame = freeCamCFrame
        return
    end

    if State.Fly then
        local _, hrp = getCharParts(LocalPlayer)
        local lv = hrp and hrp:FindFirstChild("WTF_FlyVel")
        local ao = hrp and hrp:FindFirstChild("WTF_FlyOri")
        if lv and ao then
            local camCF = Camera.CFrame
            local dir = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
            lv.VectorVelocity = dir.Magnitude > 0 and (dir.Unit * Config.Movement.FlySpeed) or Vector3.zero
            ao.CFrame = camCF
        end
    end

    if State.Aim then
        local _, targetPart = getBestAimTarget()
        if targetPart then
            Camera.CFrame = Camera.CFrame:Lerp(CFrame.lookAt(Camera.CFrame.Position, targetPart.Position), Config.Combat.AimSmoothness)
        end
    end
end))

track(RunService.Stepped:Connect(function()
    if State.Unloaded or State.IsFlinging then return end
    if State.Noclip or State.Invisible then
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = false end
            end
        end
    end
end))

track(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.35)
    if State.Unloaded then return end
    table.clear(SavedInvisible.Transparencies)
    SavedInvisible.HipHeight = nil
    SavedInvisible.CameraOffset = nil
    if State.Invisible then applyInvisible(true) end
    if State.Fly then setupFly() end
end))

task.spawn(function()
    while not State.Unloaded do
        if State.AutoShot then
            local hasGun, gun = hasToolInList(LocalPlayer, Config.Roles.GunNames)
            if hasGun and gun and gun.Parent == LocalPlayer.Character then
                local _, targetPart = getBestAimTarget()
                if targetPart then
                    Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, targetPart.Position)
                    gun:Activate()
                    task.wait(Config.Combat.AutoShotDelay)
                end
            end
        end

        if State.KillAll and hasToolInList(LocalPlayer, Config.Roles.KnifeNames) then
            for _, p in ipairs(Players:GetPlayers()) do
                if not State.KillAll or State.Unloaded then break end
                if p ~= LocalPlayer and isAlive(p) then
                    performKnifeAttack(p)
                    task.wait(Config.Combat.KillAllDelay)
                end
            end
        end

        if State.KillSheriff and hasToolInList(LocalPlayer, Config.Roles.KnifeNames) then
            local sheriff = findPlayerByRole("Sheriff")
            if sheriff then
                performKnifeAttack(sheriff)
                task.wait(Config.Combat.KillAllDelay)
            end
        end

        if State.AutoRevolver and not hasToolInList(LocalPlayer, Config.Roles.KnifeNames) then
            local dropped = findDroppedGun()
            local _, hrp = getCharParts(LocalPlayer)
            if dropped and hrp then
                local saved = hrp.CFrame
                touchPart(dropped)
                task.wait(0.1)
                if hrp and hrp.Parent then hrp.CFrame = saved end
            end
        end

        if State.AutoFarmCoins then
            for _, coin in ipairs(findCoins()) do
                if not State.AutoFarmCoins or State.Unloaded then break end
                local _, hrp = getCharParts(LocalPlayer)
                if hrp and coin and coin.Parent then
                    local dist = (hrp.Position - coin.Position).Magnitude
                    local dur = math.clamp(dist / Config.Farm.CoinTweenSpeed, 0.05, 3)
                    local tw = TweenService:Create(hrp, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = coin.CFrame })
                    tw:Play()
                    tw.Completed:Wait()
                    task.wait(Config.Farm.CoinStepDelay)
                end
            end
        end

        task.wait(0.1)
    end
end)

-- ============================================================================
-- UI v5 (Black Theme, Search Sidebar, Two-Column Layout, HUD Watermark)
-- ============================================================================
local function tryLoadCustomLogo()
    if type(isfile) == "function" and type(getcustomasset) == "function" then
        local okExists, exists = pcall(isfile, Config.CustomLogoFile)
        if okExists and exists then
            local okAsset, asset = pcall(getcustomasset, Config.CustomLogoFile)
            if okAsset and type(asset) == "string" then return asset end
        end
    end
    return nil
end

local function makeLogoWidget(parent, sizePx)
    local custom = tryLoadCustomLogo()
    if custom then
        local img = Instance.new("ImageLabel")
        img.Size = UDim2.fromOffset(sizePx, sizePx)
        img.BackgroundTransparency = 1
        img.ScaleType = Enum.ScaleType.Fit
        img.Image = custom
        img.Parent = parent
        return img
    end
    local box = Instance.new("Frame")
    box.Size = UDim2.fromOffset(sizePx, sizePx)
    box.BackgroundTransparency = 1
    box.Parent = parent

    local function slash(x, y, w, h, rot)
        local f = Instance.new("Frame")
        f.Size = UDim2.fromOffset(w, h)
        f.Position = UDim2.fromOffset(x, y)
        f.Rotation = rot
        f.BorderSizePixel = 0
        f.BackgroundColor3 = Config.Colors.Accent
        f.Parent = box
    end
    slash(4, 4, 3, sizePx - 8, -18)
    slash(10, 4, 3, sizePx - 8, 18)
    slash(16, 4, 3, sizePx - 8, -18)
    slash(22, 4, 3, sizePx - 8, 18)
    return box
end

local function makeSidebarIcon(parent, name)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.fromOffset(14, 14)
    holder.Position = UDim2.fromOffset(10, 8)
    holder.BackgroundTransparency = 1
    holder.Parent = parent

    local parts = {}
    local function line(x, y, w, h, rot)
        local f = Instance.new("Frame")
        f.Size = UDim2.fromOffset(w, h)
        f.Position = UDim2.fromOffset(x, y)
        f.Rotation = rot or 0
        f.BorderSizePixel = 0
        f.BackgroundColor3 = Config.Colors.Muted
        f.Parent = holder
        table.insert(parts, f)
        return f
    end

    if name == "combat" then
        line(6, 1, 2, 12, 0); line(1, 6, 12, 2, 0)
    elseif name == "visual" then
        line(2, 6, 10, 2, 0); line(5, 4, 4, 6, 0)
    elseif name == "movement" then
        line(2, 4, 8, 2, 35); line(2, 8, 8, 2, -35)
    elseif name == "farm" then
        line(3, 3, 8, 8, 45)
    elseif name == "target" then
        line(6, 1, 2, 12, 0); line(1, 6, 12, 2, 0); line(4, 4, 6, 6, 0)
    else
        line(2, 3, 10, 2, 0); line(2, 7, 10, 2, 0); line(2, 11, 10, 2, 0)
    end
    return parts
end

local function buildUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "WTF_Del3livery_UI"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = uiParent
    RootGui = gui

    local animInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local main = Instance.new("Frame")
    main.Size = UDim2.fromOffset(740, 470)
    main.Position = UDim2.new(0.5, -370, 0.5, -235)
    main.BackgroundColor3 = Config.Colors.Bg
    main.BackgroundTransparency = 0.08
    main.BorderSizePixel = 0
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Config.Colors.Border
    stroke.Thickness = 1

    local topBar = Instance.new("Frame")
    topBar.Size = UDim2.new(1, 0, 0, 46)
    topBar.BackgroundTransparency = 1
    topBar.Parent = main

    local logo = makeLogoWidget(topBar, 28)
    logo.Position = UDim2.fromOffset(14, 9)

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.fromOffset(180, 16)
    titleLbl.Position = UDim2.fromOffset(50, 8)
    titleLbl.BackgroundTransparency = 1
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 13
    titleLbl.TextColor3 = Config.Colors.Text
    titleLbl.Text = Config.ScriptName
    titleLbl.Parent = topBar

    local subLbl = Instance.new("TextLabel")
    subLbl.Size = UDim2.fromOffset(180, 12)
    subLbl.Position = UDim2.fromOffset(50, 25)
    subLbl.BackgroundTransparency = 1
    subLbl.TextXAlignment = Enum.TextXAlignment.Left
    subLbl.Font = Enum.Font.Gotham
    subLbl.TextSize = 10
    subLbl.TextColor3 = Config.Colors.Muted
    subLbl.Text = Config.AuthorText
    subLbl.Parent = topBar

    local function makeTopBtn(txt, xOffset, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(24, 24)
        b.Position = UDim2.new(1, xOffset, 0, 11)
        b.BackgroundTransparency = 1
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 13
        b.TextColor3 = Config.Colors.Muted
        b.Text = txt
        b.Parent = topBar
        b.MouseButton1Click:Connect(cb)
        return b
    end

    local minimized = false
    makeTopBtn("—", -64, function()
        minimized = not minimized
        main.Size = minimized and UDim2.fromOffset(740, 46) or UDim2.fromOffset(740, 470)
    end)
    local unloadBtn = makeTopBtn("×", -32, function() end)

    do
        local dragging, dragStart, startPos
        topBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging, dragStart, startPos = true, input.Position, main.Position
            end
        end)
        track(UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local d = input.Position - dragStart
                main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end))
        track(UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end))
    end

    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0, 168, 1, -54)
    sidebar.Position = UDim2.fromOffset(8, 46)
    sidebar.BackgroundColor3 = Config.Colors.Sidebar
    sidebar.BackgroundTransparency = 0.25
    sidebar.BorderSizePixel = 0
    sidebar.Parent = main
    Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 8)

    local searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(1, -16, 0, 28)
    searchBox.Position = UDim2.fromOffset(8, 8)
    searchBox.BackgroundColor3 = Config.Colors.Card
    searchBox.TextColor3 = Config.Colors.Text
    searchBox.PlaceholderText = "Search"
    searchBox.PlaceholderColor3 = Config.Colors.Muted
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextSize = 12
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.Text = ""
    searchBox.ClearTextOnFocus = false
    searchBox.Parent = sidebar
    Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 6)
    Instance.new("UIPadding", searchBox).PaddingLeft = UDim.new(0, 10)

    local tabListFrame = Instance.new("Frame")
    tabListFrame.Size = UDim2.new(1, -16, 1, -46)
    tabListFrame.Position = UDim2.fromOffset(8, 42)
    tabListFrame.BackgroundTransparency = 1
    tabListFrame.Parent = sidebar
    Instance.new("UIListLayout", tabListFrame).Padding = UDim.new(0, 3)

    local contentArea = Instance.new("Frame")
    contentArea.Size = UDim2.new(1, -190, 1, -54)
    contentArea.Position = UDim2.fromOffset(182, 46)
    contentArea.BackgroundTransparency = 1
    contentArea.ClipsDescendants = true
    contentArea.Parent = main

    local tabs = {}
    local function createTab(name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 30)
        btn.BackgroundColor3 = Config.Colors.Card
        btn.BackgroundTransparency = 1
        btn.AutoButtonColor = false
        btn.Text = ""
        btn.Parent = tabListFrame
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

        local iconParts = makeSidebarIcon(btn, name)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -34, 1, 0)
        lbl.Position = UDim2.fromOffset(32, 0)
        lbl.BackgroundTransparency = 1
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 12
        lbl.TextColor3 = Config.Colors.Muted
        lbl.Text = name
        lbl.Parent = btn

        local page = Instance.new("ScrollingFrame")
        page.Size = UDim2.fromScale(1, 1)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 2
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Visible = false
        page.Parent = contentArea

        local cols = Instance.new("Frame")
        cols.Size = UDim2.new(1, -4, 0, 0)
        cols.AutomaticSize = Enum.AutomaticSize.Y
        cols.BackgroundTransparency = 1
        cols.Parent = page

        local leftCol = Instance.new("Frame")
        leftCol.Size = UDim2.new(0.5, -5, 0, 0)
        leftCol.AutomaticSize = Enum.AutomaticSize.Y
        leftCol.BackgroundTransparency = 1
        leftCol.Parent = cols
        Instance.new("UIListLayout", leftCol).Padding = UDim.new(0, 8)

        local rightCol = Instance.new("Frame")
        rightCol.Size = UDim2.new(0.5, -5, 0, 0)
        rightCol.Position = UDim2.new(0.5, 5, 0, 0)
        rightCol.AutomaticSize = Enum.AutomaticSize.Y
        rightCol.BackgroundTransparency = 1
        rightCol.Parent = cols
        Instance.new("UIListLayout", rightCol).Padding = UDim.new(0, 8)

        btn.MouseButton1Click:Connect(function()
            for _, t in ipairs(tabs) do
                t.Page.Visible = false
                tween(t.Btn, animInfo, { BackgroundTransparency = 1 })
                t.Lbl.TextColor3 = Config.Colors.Muted
                for _, p in ipairs(t.IconParts) do p.BackgroundColor3 = Config.Colors.Muted end
            end
            page.Visible = true
            tween(btn, animInfo, { BackgroundTransparency = 0 })
            lbl.TextColor3 = Config.Colors.Text
            for _, p in ipairs(iconParts) do p.BackgroundColor3 = Config.Colors.Text end
        end)

        table.insert(tabs, { Btn = btn, Lbl = lbl, Page = page, IconParts = iconParts })
        return leftCol, rightCol, btn, page, lbl, iconParts
    end

    local function createSection(col, headerText)
        local wrap = Instance.new("Frame")
        wrap.Size = UDim2.new(1, 0, 0, 0)
        wrap.AutomaticSize = Enum.AutomaticSize.Y
        wrap.BackgroundTransparency = 1
        wrap.Parent = col
        Instance.new("UIListLayout", wrap).Padding = UDim.new(0, 4)

        local hdr = Instance.new("TextLabel")
        hdr.Size = UDim2.new(1, 0, 0, 16)
        hdr.BackgroundTransparency = 1
        hdr.TextXAlignment = Enum.TextXAlignment.Left
        hdr.Font = Enum.Font.GothamMedium
        hdr.TextSize = 11
        hdr.TextColor3 = Config.Colors.Muted
        hdr.Text = headerText
        hdr.Parent = wrap

        local card = Instance.new("Frame")
        card.Size = UDim2.new(1, 0, 0, 0)
        card.AutomaticSize = Enum.AutomaticSize.Y
        card.BackgroundColor3 = Config.Colors.Card
        card.BackgroundTransparency = 0.15
        card.Parent = wrap
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
        Instance.new("UIListLayout", card).Padding = UDim.new(0, 2)
        local cp = Instance.new("UIPadding", card)
        cp.PaddingTop, cp.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
        cp.PaddingLeft, cp.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
        return card
    end

    local function addToggle(section, label, defaultVal, callback)
        local state = defaultVal or false
        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, 0, 0, 32)
        row.BackgroundTransparency = 1
        row.Text = ""
        row.Parent = section

        local txt = Instance.new("TextLabel")
        txt.Size = UDim2.new(1, -50, 1, 0)
        txt.Position = UDim2.fromOffset(6, 0)
        txt.BackgroundTransparency = 1
        txt.TextXAlignment = Enum.TextXAlignment.Left
        txt.Font = Enum.Font.Gotham
        txt.TextSize = 12
        txt.TextColor3 = Config.Colors.Text
        txt.Text = label
        txt.Parent = row

        local pill = Instance.new("Frame")
        pill.Size = UDim2.fromOffset(32, 16)
        pill.Position = UDim2.new(1, -38, 0.5, -8)
        pill.BackgroundColor3 = state and Config.Colors.Accent or Config.Colors.TrackOff
        pill.Parent = row
        Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.fromOffset(12, 12)
        knob.Position = state and UDim2.fromOffset(18, 2) or UDim2.fromOffset(2, 2)
        knob.BackgroundColor3 = state and Config.Colors.Bg or Config.Colors.Text
        knob.Parent = pill
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

        row.MouseButton1Click:Connect(function()
            state = not state
            tween(pill, animInfo, { BackgroundColor3 = state and Config.Colors.Accent or Config.Colors.TrackOff })
            tween(knob, animInfo, {
                Position = state and UDim2.fromOffset(18, 2) or UDim2.fromOffset(2, 2),
                BackgroundColor3 = state and Config.Colors.Bg or Config.Colors.Text,
            })
            callback(state)
        end)

        table.insert(Searchables, { Row = row, Text = string.lower(label) })
        return row
    end

    local function addButton(section, label, textColor, callback)
        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, 0, 0, 30)
        row.BackgroundColor3 = Config.Colors.RowHover
        row.BackgroundTransparency = 0.45
        row.Text = ""
        row.Parent = section
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

        local txt = Instance.new("TextLabel")
        txt.Size = UDim2.new(1, -12, 1, 0)
        txt.Position = UDim2.fromOffset(8, 0)
        txt.BackgroundTransparency = 1
        txt.TextXAlignment = Enum.TextXAlignment.Left
        txt.Font = Enum.Font.GothamMedium
        txt.TextSize = 12
        txt.TextColor3 = textColor or Config.Colors.Text
        txt.Text = label
        txt.Parent = row

        row.MouseButton1Click:Connect(callback)
        table.insert(Searchables, { Row = row, Text = string.lower(label) })
        return row
    end

    local function addSlider(section, label, minVal, maxVal, defaultVal, decimals, callback)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 42)
        row.BackgroundTransparency = 1
        row.Parent = section

        local txt = Instance.new("TextLabel")
        txt.Size = UDim2.new(1, -12, 0, 18)
        txt.Position = UDim2.fromOffset(6, 2)
        txt.BackgroundTransparency = 1
        txt.TextXAlignment = Enum.TextXAlignment.Left
        txt.Font = Enum.Font.Gotham
        txt.TextSize = 12
        txt.TextColor3 = Config.Colors.Text
        txt.Text = string.format("%s: %." .. decimals .. "f", label, defaultVal)
        txt.Parent = row

        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(1, -12, 0, 4)
        bar.Position = UDim2.fromOffset(6, 28)
        bar.BackgroundColor3 = Config.Colors.TrackOff
        bar.Parent = row
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.fromScale(math.clamp((defaultVal - minVal) / (maxVal - minVal), 0, 1), 1)
        fill.BackgroundColor3 = Config.Colors.Accent
        fill.Parent = bar
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local sliding = false
        local function updateX(x)
            local alpha = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            local val = minVal + (maxVal - minVal) * alpha
            fill.Size = UDim2.fromScale(alpha, 1)
            txt.Text = string.format("%s: %." .. decimals .. "f", label, val)
            callback(val)
        end

        bar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                sliding = true
                updateX(input.Position.X)
            end
        end)
        track(UserInputService.InputChanged:Connect(function(input)
            if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then updateX(input.Position.X) end
        end))
        track(UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then sliding = false end
        end))

        table.insert(Searchables, { Row = row, Text = string.lower(label) })
    end

    -- Tabs
    local cL, cR, cBtn, cPage, cLbl, cIcons = createTab("combat")
    local vL, vR = createTab("visual")
    local mL, mR = createTab("movement")
    local fL, fR = createTab("farm")
    local tL, tR, _, tPage = createTab("target")
    local xL, xR = createTab("misc")

    cPage.Visible = true
    cBtn.BackgroundTransparency = 0
    cLbl.TextColor3 = Config.Colors.Text
    for _, p in ipairs(cIcons) do p.BackgroundColor3 = Config.Colors.Text end

    -- Combat
    local aimSec = createSection(cL, "aimbot (murderer)")
    addToggle(aimSec, "aim lock", false, function(v) State.Aim = v end)
    addToggle(aimSec, "only murderer", Config.Combat.AimOnlyMurderer, function(v) Config.Combat.AimOnlyMurderer = v end)
    addToggle(aimSec, "auto shot", false, function(v) State.AutoShot = v end)
    addSlider(aimSec, "aim fov", 40, 400, Config.Combat.AimFOV, 0, function(v) Config.Combat.AimFOV = v end)
    addSlider(aimSec, "smoothness", 0.05, 1.0, Config.Combat.AimSmoothness, 2, function(v) Config.Combat.AimSmoothness = v end)

    local knifeSec = createSection(cR, "murderer tools")
    addToggle(knifeSec, "kill all (knife)", false, function(v) State.KillAll = v end)
    addToggle(knifeSec, "kill sheriff (tp + knife)", false, function(v) State.KillSheriff = v end)

    -- Visual
    local espSec = createSection(vL, "player esp")
    addToggle(espSec, "esp (murderer / sheriff / inno)", false, function(v) State.ESP = v end)
    local camSec = createSection(vR, "camera")
    addToggle(camSec, "free camera", false, function(v)
        State.FreeCam = v
        setFreeCam(v)
    end)
    addSlider(camSec, "freecam speed", 15, 160, Config.Movement.FreeCamSpeed, 0, function(v) Config.Movement.FreeCamSpeed = v end)

    -- Movement
    local moveSec = createSection(mL, "character")
    addToggle(moveSec, "invisible (body + tools)", false, function(v)
        State.Invisible = v
        applyInvisible(v)
    end)
    addToggle(moveSec, "fly (wasd + space/ctrl)", false, function(v)
        State.Fly = v
        if v then setupFly() else clearFlyMovers() end
    end)
    addToggle(moveSec, "noclip", false, function(v) State.Noclip = v end)
    local speedSec = createSection(mR, "speed")
    addSlider(speedSec, "fly speed", 15, 160, Config.Movement.FlySpeed, 0, function(v) Config.Movement.FlySpeed = v end)

    -- Farm
    local farmSecL = createSection(fL, "coins")
    addToggle(farmSecL, "auto farm coins", false, function(v) State.AutoFarmCoins = v end)
    addSlider(farmSecL, "coin speed", 10, 60, Config.Farm.CoinTweenSpeed, 0, function(v) Config.Farm.CoinTweenSpeed = v end)
    local farmSecR = createSection(fR, "weapons")
    addToggle(farmSecR, "auto revolver (steal gun)", false, function(v) State.AutoRevolver = v end)

    -- Target
    local actSec = createSection(tL, "selected target")
    local selTitle = Instance.new("TextLabel")
    selTitle.Size = UDim2.new(1, 0, 0, 22)
    selTitle.BackgroundTransparency = 1
    selTitle.TextXAlignment = Enum.TextXAlignment.Left
    selTitle.Font = Enum.Font.GothamMedium
    selTitle.TextSize = 11
    selTitle.TextColor3 = Config.Colors.Muted
    selTitle.Text = "  target: <none>"
    selTitle.Parent = actSec

    local function setStatus(msg)
        if selTitle and selTitle.Parent then selTitle.Text = "  " .. msg end
    end

    local quickSec = createSection(tL, "quick kill")
    addButton(quickSec, "kill murderer", Config.Colors.Murderer, function()
        local m = findPlayerByRole("Murderer")
        if m then task.spawn(smartKillPlayer, m, setStatus) end
    end)
    addButton(quickSec, "kill sheriff", Config.Colors.Sheriff, function()
        local s = findPlayerByRole("Sheriff")
        if s then task.spawn(smartKillPlayer, s, setStatus) end
    end)

    addButton(actSec, "soon (void fling)", Config.Colors.Accent, function()
        if State.SelectedTarget then task.spawn(executeSoon, State.SelectedTarget, setStatus) end
    end)
    addButton(actSec, "tp to target", Config.Colors.Text, function()
        local _, myHrp = getCharParts(LocalPlayer)
        local _, tHrp = getCharParts(State.SelectedTarget)
        if myHrp and tHrp then myHrp.CFrame = tHrp.CFrame * CFrame.new(0, 0, 3) end
    end)
    addButton(actSec, "kill target", Config.Colors.Murderer, function()
        if State.SelectedTarget then task.spawn(smartKillPlayer, State.SelectedTarget, setStatus) end
    end)

    local playersSec = createSection(tR, "players")
    local function refreshPlayers()
        if State.Unloaded or not playersSec.Parent then return end
        for _, ch in ipairs(playersSec:GetChildren()) do
            if ch:IsA("TextButton") then ch:Destroy() end
        end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local role, roleColor = getPlayerRole(p)
                local row = Instance.new("TextButton")
                row.Size = UDim2.new(1, 0, 0, 34)
                row.BackgroundColor3 = (State.SelectedTarget == p) and Config.Colors.RowHover or Config.Colors.Sidebar
                row.BackgroundTransparency = 0.25
                row.Text = ""
                row.Parent = playersSec
                Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

                local av = Instance.new("ImageLabel")
                av.Size = UDim2.fromOffset(24, 24)
                av.Position = UDim2.fromOffset(5, 5)
                av.BackgroundColor3 = Config.Colors.Bg
                av.Parent = row
                Instance.new("UICorner", av).CornerRadius = UDim.new(1, 0)
                task.spawn(function()
                    local ok, thumb = pcall(Players.GetUserThumbnailAsync, Players, p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                    if ok and thumb and av.Parent then av.Image = thumb end
                end)

                local nLbl = Instance.new("TextLabel")
                nLbl.Size = UDim2.new(1, -98, 1, 0)
                nLbl.Position = UDim2.fromOffset(34, 0)
                nLbl.BackgroundTransparency = 1
                nLbl.TextXAlignment = Enum.TextXAlignment.Left
                nLbl.Font = Enum.Font.Gotham
                nLbl.TextSize = 11
                nLbl.TextColor3 = Config.Colors.Text
                nLbl.Text = p.Name
                nLbl.Parent = row

                local rLbl = Instance.new("TextLabel")
                rLbl.Size = UDim2.fromOffset(60, 18)
                rLbl.Position = UDim2.new(1, -64, 0.5, -9)
                rLbl.BackgroundTransparency = 1
                rLbl.TextXAlignment = Enum.TextXAlignment.Right
                rLbl.Font = Enum.Font.GothamBold
                rLbl.TextSize = 10
                rLbl.TextColor3 = roleColor
                rLbl.Text = role
                rLbl.Parent = row

                row.MouseButton1Click:Connect(function()
                    State.SelectedTarget = p
                    setStatus("target: " .. p.Name)
                    refreshPlayers()
                end)
            end
        end
    end
    refreshPlayers()
    track(Players.PlayerAdded:Connect(function() task.wait(0.2); refreshPlayers() end))
    track(Players.PlayerRemoving:Connect(function(p)
        if State.SelectedTarget == p then
            State.SelectedTarget = nil
            setStatus("target: <none>")
        end
        task.wait(0.1); refreshPlayers()
    end))

    -- Misc & HUD Watermark
    local winSec = createSection(xL, "window")
    addButton(winSec, "show / hide ui (K)", Config.Colors.Text, function() main.Visible = not main.Visible end)
    local hudSec = createSection(xR, "hud")

    local hudFrame = Instance.new("Frame")
    hudFrame.Size = UDim2.fromOffset(172, 36)
    hudFrame.Position = UDim2.new(0, 12, 1, -48)
    hudFrame.BackgroundColor3 = Config.Colors.Bg
    hudFrame.BackgroundTransparency = 0.15
    hudFrame.BorderSizePixel = 0
    hudFrame.Parent = gui
    Instance.new("UICorner", hudFrame).CornerRadius = UDim.new(0, 8)
    local hudStroke = Instance.new("UIStroke", hudFrame)
    hudStroke.Color = Config.Colors.Border
    hudStroke.Thickness = 1

    local hudLogo = makeLogoWidget(hudFrame, 22)
    hudLogo.Position = UDim2.fromOffset(8, 7)

    local hudTitle = Instance.new("TextLabel")
    hudTitle.Size = UDim2.fromOffset(128, 14)
    hudTitle.Position = UDim2.fromOffset(36, 4)
    hudTitle.BackgroundTransparency = 1
    hudTitle.TextXAlignment = Enum.TextXAlignment.Left
    hudTitle.Font = Enum.Font.GothamBold
    hudTitle.TextSize = 11
    hudTitle.TextColor3 = Config.Colors.Text
    hudTitle.Text = Config.ScriptName
    hudTitle.Parent = hudFrame

    local hudStats = Instance.new("TextLabel")
    hudStats.Size = UDim2.fromOffset(128, 12)
    hudStats.Position = UDim2.fromOffset(36, 19)
    hudStats.BackgroundTransparency = 1
    hudStats.TextXAlignment = Enum.TextXAlignment.Left
    hudStats.Font = Enum.Font.Code
    hudStats.TextSize = 10
    hudStats.TextColor3 = Config.Colors.Muted
    hudStats.Text = "60 FPS  0 MS"
    hudStats.Parent = hudFrame

    addToggle(hudSec, "watermark hud", true, function(v)
        State.ShowWatermark = v
        hudFrame.Visible = v
    end)

    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local q = string.lower(searchBox.Text)
        for _, item in ipairs(Searchables) do
            if item.Row and item.Row.Parent then
                item.Row.Visible = (q == "" or string.find(item.Text, q, 1, true) ~= nil)
            end
        end
    end)

    local fpsCount, lastTick = 0, os.clock()
    track(RunService.RenderStepped:Connect(function()
        fpsCount += 1
        local now = os.clock()
        if now - lastTick >= 0.5 then
            local fps = math.floor(fpsCount / (now - lastTick))
            fpsCount, lastTick = 0, now
            local okPing, ping = pcall(function()
                return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
            end)
            hudStats.Text = string.format("%d FPS  %d MS", fps, okPing and ping or 0)
        end
    end))

    task.spawn(function()
        while not State.Unloaded and gui.Parent do
            if tPage.Visible then refreshPlayers() end
            task.wait(1.2)
        end
    end)

    track(UserInputService.InputBegan:Connect(function(input, gp)
        if not gp and input.KeyCode == Config.ToggleKey then
            main.Visible = not main.Visible
        end
    end))

    unloadBtn.MouseButton1Click:Connect(function()
        State.Unloaded = true
        State.ESP, State.Fly, State.Noclip, State.FreeCam, State.Invisible = false, false, false, false, false
        clearFlyMovers()
        setFreeCam(false)
        applyInvisible(false)
        for p in pairs(ESPObjects) do clearESPForPlayer(p) end
        if FovCircle then FovCircle:Remove() end
        for _, c in ipairs(Connections) do
            if c.Connected then c:Disconnect() end
        end
        gui:Destroy()
    end)
end

buildUI()
