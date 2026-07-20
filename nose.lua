local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local TweenService      = game:GetService("TweenService")
local LocalPlayer       = Players.LocalPlayer

local _tspawn  = task and task.spawn  or spawn
local _twait   = task and task.wait   or wait
local _tdelay  = task and task.delay  or function(t, f) _tspawn(function() _twait(t); f() end) end

local _has_newcclosure        = type(newcclosure)        == "function"
local _has_hookmetamethod     = type(hookmetamethod)     == "function"
local _has_getnamecallmethod  = type(getnamecallmethod)  == "function"
local _has_getrawmetatable    = type(getrawmetatable)    == "function"
local _has_setreadonly        = type(setreadonly)        == "function"
local _has_firetouchinterest  = type(firetouchinterest)  == "function"
local _has_isreadonly         = type(isreadonly)         == "function"
local _has_getconnections     = type(getconnections)     == "function"

local function safeCall(fn, ...)
    local ok, res = pcall(fn, ...)
    return ok and res or nil
end

-- ── Función para proteger tabla de metatables ──────────────
local function trySetReadonly(meta, state)
    if _has_setreadonly then pcall(setreadonly, meta, state) end
end

-- ── Wrapper newcclosure seguro ─────────────────────────────
local function safeClosure(fn)
    if _has_newcclosure then
        local ok, c = pcall(newcclosure, fn)
        if ok and c then return c end
    end
    return fn
end

-- ── VxnityUI ───────────────────────────────────────────────
local VxnityUI = {}
VxnityUI.__index = VxnityUI

-- ── Parent de GUI: Delta-safe ───────────────────────────────
local function getGuiParent()
    if type(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg end
    local ok2, pg = pcall(function() return LocalPlayer:WaitForChild("PlayerGui", 5) end)
    if ok2 and pg then return pg end
    return LocalPlayer.PlayerGui
end

-- ── Centralized Connection Manager ───────────────────────────
if _G._TLConns then
    for name, conn in pairs(_G._TLConns) do
        pcall(function() conn:Disconnect() end)
    end
    _G._TLConns = {}
else
    _G._TLConns = {}
end

local function cleanConn(name)
    if _G._TLConns[name] then
        pcall(function() _G._TLConns[name]:Disconnect() end)
        _G._TLConns[name] = nil
    end
end

local function setConn(name, connection)
    cleanConn(name)
    _G._TLConns[name] = connection
end

-- ── Cleanup de ejecuciones anteriores ──────────────────────
pcall(function()
    local old = getGuiParent():FindFirstChild("TouchlineProGui")
    if old then old:Destroy() end
end)
pcall(function() local g = getGuiParent():FindFirstChild("TLNotifGui"); if g then g:Destroy() end end)

-- Desconectar loops anteriores de forma segura
local _prevConns = {
    "_TLMainLoop","_TLHelperConn","_TLFollowConn",
    "_TLDribbleConn","_TLContinuousReactConn","_TLReachConn"
}
for _, k in ipairs(_prevConns) do
    pcall(function()
        if _G[k] then _G[k]:Disconnect(); _G[k] = nil end
    end)
end
pcall(function()
    if _G._TLTouchReactConn then
        for _, c in pairs(_G._TLTouchReactConn) do pcall(function() c:Disconnect() end) end
        _G._TLTouchReactConn = nil
    end
end)
_G._TLReactHookInstalled = nil 

if not _G._TLPersist then
    _G._TLPersist = {
        reachEnabled    = false, reachDistance = 5,    reactPower = 0,
        ballSpeedMult   = 1.0,   reactHookOn   = false, gkHookOn = false,
        helperEnabled   = false, helperActive  = false,
        magnetMode      = true,  predictMode   = true,  spaceLock = false,
        continuousReact = false, continuousPower = 1e22,
        autoReact       = false, autoReactRange = 8,   autoReactCooldown = 0,
        counterReact    = false, counterPower   = 1e22,
        reactDirection  = "camera",
        perfRed = false, perfShadow = false, perfPhysics = false, perfNet = false,
        -- nuevos
        antiRagdoll = false, espEnabled = false,
        walkSpeed = 16, jumpPower = 50,
        -- optimizaciones delay & reach
        reachMode = "Hybrid",
        reactCooldownVal = 0.1,
        instantVelocity = true,
        autoReactMode = "Always in Range",
    }
end
local P = _G._TLPersist

_G._TLBall = _G._TLBall or nil
_G._TLHRP  = _G._TLHRP  or nil

-- Actualizar HRP si ya hay personaje
pcall(function()
    local ch = LocalPlayer.Character
    if ch then
        _G._TLHRP = ch:FindFirstChild("HumanoidRootPart") or _G._TLHRP
    end
end)

-- Exploit de simulación de física (Network Ownership Client Claim)
_tspawn(function()
    while true do
        pcall(function()
            LocalPlayer.SimulationRadius = 1000
            LocalPlayer.MaximumSimulationRadius = 1000
        end)
        _twait(1)
    end
end)

local BALL_PATTERNS  = {"ball","football","soccer","balon","bola","tpstball","matchball","tps","sphere","pelota","playground"}
local _detectedBalls = {}

local function isBallPart(obj)
    if not obj:IsA("BasePart") then return false end
    if obj.Transparency == 1 and obj.CanCollide == false and obj.Anchored then return false end -- ignorar spawns invisibles
    
    local name = obj.Name:lower()
    for _, pat in ipairs(BALL_PATTERNS) do
        if name:find(pat, 1, true) then return true end
    end
    
    -- Chequeo de forma esférica (para MeshParts y Parts generales)
    local size = obj.Size
    local isSpherical = math.abs(size.X - size.Y) < 0.15 and math.abs(size.X - size.Z) < 0.15
    if isSpherical and size.X >= 0.3 and size.X <= 8 then
        if obj:IsA("Part") and obj.Shape == Enum.PartType.Ball then
            return true
        end
        if obj:IsA("MeshPart") then
            return true
        end
        local parentName = obj.Parent and obj.Parent.Name:lower() or ""
        if parentName:find("ball") or parentName:find("soccer") or parentName:find("football") then
            return true
        end
    end
    return false
end

local function registerBall(obj)
    if isBallPart(obj) then
        _detectedBalls[obj] = true
    end
end

local function unregisterBall(obj)
    _detectedBalls[obj] = nil
end

-- Inicializar registro dinámico
for _, obj in ipairs(Workspace:GetDescendants()) do
    pcall(registerBall, obj)
end

setConn("ballAdded", Workspace.DescendantAdded:Connect(function(obj)
    _tdelay(0.05, function()
        pcall(registerBall, obj)
    end)
end))

setConn("ballRemoved", Workspace.DescendantRemoving:Connect(function(obj)
    pcall(unregisterBall, obj)
end))

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function findBall()
    local root = getRoot()
    local bestBall = nil
    local bestDist = math.huge
    local count = 0
    
    for ball in pairs(_detectedBalls) do
        if ball and ball.Parent then
            count = count + 1
            if root then
                local dist = (ball.Position - root.Position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    bestBall = ball
                end
            else
                bestBall = ball
                break
            end
        else
            _detectedBalls[ball] = nil
        end
    end
    
    -- Fallback si no hay nada registrado
    if count == 0 then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if isBallPart(obj) then
                _detectedBalls[obj] = true
                local dist = root and (obj.Position - root.Position).Magnitude or 0
                if dist < bestDist then
                    bestDist = dist
                    bestBall = obj
                end
            end
        end
    end
    
    _G._TLBall = bestBall
    return bestBall
end

local lastPreparedBall = nil
local function prepareBall(ball)
    if not ball or not ball:IsA("BasePart") then return false end
    if lastPreparedBall == ball then return true end
    lastPreparedBall = ball
    pcall(function() ball.CanCollide = false end)
    pcall(function() ball.Massless   = true  end)
    return true
end

pcall(function()
    local _guardConns = {}

    local function guardBall(ball)
        if not ball or not ball:IsA("BasePart") then return end
        if _guardConns[ball] then pcall(function() _guardConns[ball]:Disconnect() end) end
        pcall(function() ball.CanCollide = false end)
        local conn
        conn = ball:GetPropertyChangedSignal("CanCollide"):Connect(function()
            if not ball.Parent then
                pcall(function() conn:Disconnect() end)
                _guardConns[ball] = nil; return
            end
            if ball.CanCollide then pcall(function() ball.CanCollide = false end) end
        end)
        _guardConns[ball] = conn
    end

    local b = findBall()
    if b then guardBall(b); _G._TLBall = b end

    setConn("ballGuardAdded", Workspace.DescendantAdded:Connect(function(obj)
        if isBallPart(obj) then
            _tdelay(0.05, function()
                guardBall(obj)
                _G._TLBall = obj
            end)
        end
    end))
end)

local ACCENT      = Color3.fromRGB(255, 75, 135)
local ACCENT2     = Color3.fromRGB(200, 40, 100)
local ACCENT3     = Color3.fromRGB(180, 50, 220)
local ACCENT_SOFT = Color3.fromRGB(255, 140, 180)
local BG_DARK     = Color3.fromRGB(10, 6, 14)
local BG_FRAME    = Color3.fromRGB(18, 12, 22)
local BG_ELEM     = Color3.fromRGB(26, 18, 30)
local BG_HOVER    = Color3.fromRGB(34, 24, 38)
local TEXT_WHITE  = Color3.fromRGB(255, 255, 255)
local TEXT_GRAY   = Color3.fromRGB(155, 135, 160)
local TEXT_MID    = Color3.fromRGB(200, 175, 210)
local OUTLINE     = Color3.fromRGB(55, 35, 55)

local _flashPool = {}
local MAX_FLASH  = 3

local function flashBall()
    local ball = _G._TLBall
    if not ball or not ball.Parent then return end
    if #_flashPool >= MAX_FLASH then
        local old = table.remove(_flashPool, 1)
        pcall(function() if old and old.Parent then old:Destroy() end end)
    end
    pcall(function()
        local flash = Instance.new("Part")
        flash.Size         = ball.Size * 2.0
        flash.CFrame       = ball.CFrame
        flash.Anchored     = true
        flash.CanCollide   = false
        flash.Material     = Enum.Material.Neon
        flash.Color        = ACCENT
        flash.Transparency = 0.15
        flash.Parent       = Workspace
        table.insert(_flashPool, flash)

        _tspawn(function()
            for i = 0, 12 do
                pcall(function()
                    if flash and flash.Parent then
                        flash.Transparency = 0.15 + (i / 12) * 0.85
                        flash.Size = ball.Parent and ball.Size * (2.0 + i * 0.25) or flash.Size
                    end
                end)
                _twait(0.01)
            end
            pcall(function() if flash and flash.Parent then flash:Destroy() end end)
            for i, v in ipairs(_flashPool) do
                if v == flash then table.remove(_flashPool, i); break end
            end
        end)

        -- Trail
        local att0  = Instance.new("Attachment", ball)
        local att1  = Instance.new("Attachment", ball)
        att0.Position = Vector3.new(0, ball.Size.Y * 0.5, 0)
        att1.Position = Vector3.new(0, -ball.Size.Y * 0.5, 0)
        local trail = Instance.new("Trail")
        trail.Attachment0  = att0; trail.Attachment1 = att1
        trail.Lifetime     = 0.2;  trail.MinLength   = 0.05
        trail.Color        = ColorSequence.new({ColorSequenceKeypoint.new(0,ACCENT), ColorSequenceKeypoint.new(1,ACCENT2)})
        trail.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.05), NumberSequenceKeypoint.new(1,1)})
        trail.WidthScale   = NumberSequence.new({NumberSequenceKeypoint.new(0,2),    NumberSequenceKeypoint.new(1,0)})
        trail.LightEmission = 1; trail.FaceCamera = true; trail.Parent = ball
        _tdelay(0.4, function()
            pcall(function() att0:Destroy(); att1:Destroy(); trail:Destroy() end)
        end)
    end)
end

local function getAimDirection(hrp)
    local mode = P.reactDirection or "camera"
    if mode == "camera" then
        local cam = Workspace.CurrentCamera
        if cam then
            local flat = cam.CFrame.LookVector * Vector3.new(1,0,1)
            if flat.Magnitude > 0.1 then return flat.Unit end
        end
    elseif mode == "mouse" then
        local cam = Workspace.CurrentCamera
        if cam then
            if UserInputService.TouchEnabled then
                -- Touch fallback on mobile to camera look direction
                local flat = cam.CFrame.LookVector * Vector3.new(1,0,1)
                if flat.Magnitude > 0.1 then return flat.Unit end
            else
                local mp  = UserInputService:GetMouseLocation()
                local ray = cam:ViewportPointToRay(mp.X, mp.Y)
                local dir = ray.Direction * Vector3.new(1,0,1)
                if dir.Magnitude > 0.1 then return dir.Unit end
            end
        end
    end
    return hrp.CFrame.LookVector
end

local function getIncomingRedirect(ball, hrp)
    local bv = ball.AssemblyLinearVelocity
    if bv.Magnitude > 5 then
        local toMe = (hrp.Position - ball.Position).Unit
        if bv.Unit:Dot(toMe) > 0.4 then
            return (toMe * 1.5 + hrp.CFrame.LookVector * 0.5).Unit
        end
    end
    return nil
end

local function getGravity()
    local g = Workspace.Gravity
    return Vector3.new(0, -g, 0)
end

local function predictBallPosition(ball, timeAhead)
    local pos = ball.Position
    local vel = ball.AssemblyLinearVelocity
    local grav = getGravity()
    return pos + vel * timeAhead + 0.5 * grav * timeAhead * timeAhead
end

local function isBallComingToPlayer(ball, hrp, range)
    local futurePos  = predictBallPosition(ball, 0.3)
    local distNow    = (ball.Position  - hrp.Position).Magnitude
    local distFuture = (futurePos - hrp.Position).Magnitude
    if distFuture < distNow and distFuture < range then return true, distFuture end
    return false, distNow
end

local function tweenQuint(obj,t,p) return TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quint,       Enum.EasingDirection.Out), p) end
local function tweenBack(obj,t,p)  return TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Back,        Enum.EasingDirection.Out), p) end
local function tweenExpo(obj,t,p)  return TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), p) end
local function tweenSine(obj,t,p)  return TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Sine,        Enum.EasingDirection.Out), p) end

local _notifStack = {}
local _notifGui   = nil

function VxnityUI:Notify(opts)
    local title    = opts.Title    or ""
    local desc     = opts.Desc     or ""
    local duration = opts.Duration or 3
    local parent   = getGuiParent()
    if not _notifGui or not _notifGui.Parent then
        _notifGui = Instance.new("ScreenGui")
        _notifGui.Name = "TLNotifGui"; _notifGui.ResetOnSpawn = false
        _notifGui.IgnoreGuiInset = true; _notifGui.Parent = parent
    end
    local function reposition()
        for i, entry in ipairs(_notifStack) do
            local yOff = -(80 + (i-1)*72)
            tweenQuint(entry.frame, 0.3, {Position = UDim2.new(1,-305,1,yOff)}):Play()
        end
    end
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(290,64)
    frame.Position = UDim2.new(1,20,1,-80-(#_notifStack*72))
    frame.BackgroundColor3 = BG_FRAME; frame.BorderSizePixel = 0
    frame.BackgroundTransparency = 1; frame.Parent = _notifGui
    Instance.new("UICorner",frame).CornerRadius = UDim.new(0,10)
    local accentBar = Instance.new("Frame")
    accentBar.Size = UDim2.fromOffset(3,44); accentBar.Position = UDim2.new(0,0,0.5,-22)
    accentBar.BackgroundColor3 = ACCENT; accentBar.BorderSizePixel = 0; accentBar.Parent = frame
    Instance.new("UICorner",accentBar).CornerRadius = UDim.new(1,0)
    local barGrad = Instance.new("UIGradient")
    barGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,ACCENT3),ColorSequenceKeypoint.new(0.5,ACCENT),ColorSequenceKeypoint.new(1,ACCENT3)})
    barGrad.Rotation = 180; barGrad.Parent = accentBar
    local stroke = Instance.new("UIStroke"); stroke.Color = OUTLINE; stroke.Thickness = 1.5; stroke.Parent = frame
    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1,-18,0.5,0); titleLbl.Position = UDim2.fromOffset(14,4)
    titleLbl.BackgroundTransparency = 1; titleLbl.Text = title; titleLbl.TextColor3 = TEXT_WHITE
    titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextSize = 13
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.TextTransparency = 1; titleLbl.Parent = frame
    local descLbl = Instance.new("TextLabel")
    descLbl.Size = UDim2.new(1,-18,0.5,0); descLbl.Position = UDim2.new(0,14,0.5,0)
    descLbl.BackgroundTransparency = 1; descLbl.Text = desc; descLbl.TextColor3 = TEXT_GRAY
    descLbl.Font = Enum.Font.Gotham; descLbl.TextSize = 11
    descLbl.TextXAlignment = Enum.TextXAlignment.Left; descLbl.TextTransparency = 1; descLbl.Parent = frame
    local entry = {frame=frame, titleLbl=titleLbl, descLbl=descLbl}
    table.insert(_notifStack, entry)
    while #_notifStack > 3 do
        local old = table.remove(_notifStack, 1)
        pcall(function()
            tweenQuint(old.frame, 0.2, {BackgroundTransparency=1}):Play()
            tweenSine(old.titleLbl, 0.15, {TextTransparency=1}):Play()
            tweenSine(old.descLbl,  0.15, {TextTransparency=1}):Play()
            _tdelay(0.25, function() pcall(function() old.frame:Destroy() end) end)
        end)
    end
    reposition()
    tweenExpo(frame, 0.45, {BackgroundTransparency=0}):Play()
    _tdelay(0.1, function()
        tweenSine(titleLbl, 0.3, {TextTransparency=0}):Play()
        _tdelay(0.08, function() tweenSine(descLbl, 0.3, {TextTransparency=0}):Play() end)
    end)
    _tdelay(duration, function()
        for i, e in ipairs(_notifStack) do
            if e == entry then table.remove(_notifStack,i); break end
        end
        pcall(function()
            tweenQuint(frame, 0.35, {Position=UDim2.new(1,20,frame.Position.Y.Scale,frame.Position.Y.Offset), BackgroundTransparency=1}):Play()
            tweenSine(titleLbl, 0.25, {TextTransparency=1}):Play()
            tweenSine(descLbl,  0.25, {TextTransparency=1}):Play()
            _tdelay(0.4, function() pcall(function() frame:Destroy() end) end)
        end)
        reposition()
    end)
end


function VxnityUI:CreateWindow(opts)
    local uiConns = {}
    local function regUiConn(c)
        table.insert(uiConns, c)
        return c
    end

    local isMobile = UserInputService.TouchEnabled
    
    local title    = opts.Title    or "Touchline v1"
    local subtitle = opts.Subtitle or "el mejor script plemium jaja"
    
    local defaultSize = isMobile and UDim2.fromOffset(500, 320) or UDim2.fromOffset(660, 460)
    local size     = opts.Size     or defaultSize

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "TouchlineProGui"; ScreenGui.ResetOnSpawn = false
    ScreenGui.IgnoreGuiInset = true; ScreenGui.Parent = getGuiParent()

    local MainFrame = Instance.new("Frame"); MainFrame.Name = "MainFrame"
    MainFrame.Size = size
    MainFrame.Position = UDim2.new(0.5,-size.X.Offset/2, 0.5,-size.Y.Offset/2)
    MainFrame.BackgroundColor3 = BG_DARK; MainFrame.BorderSizePixel = 0; MainFrame.Parent = ScreenGui
    Instance.new("UICorner",MainFrame).CornerRadius = UDim.new(0,14)
    local mainStroke = Instance.new("UIStroke"); mainStroke.Color = OUTLINE; mainStroke.Thickness = 1.5; mainStroke.Parent = MainFrame
    local mainGrad = Instance.new("UIGradient")
    mainGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,ACCENT2),ColorSequenceKeypoint.new(0.5,OUTLINE),ColorSequenceKeypoint.new(1,ACCENT3)})
    mainGrad.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.7),NumberSequenceKeypoint.new(0.5,1),NumberSequenceKeypoint.new(1,0.7)})
    mainGrad.Rotation = 45; mainGrad.Parent = mainStroke

    local TopBar = Instance.new("Frame"); TopBar.Name = "TopBar"
    TopBar.Size = UDim2.new(1,0,0,42); TopBar.BackgroundColor3 = BG_FRAME
    TopBar.BorderSizePixel = 0; TopBar.Parent = MainFrame
    Instance.new("UICorner",TopBar).CornerRadius = UDim.new(0,14)
    local topGrad = Instance.new("UIGradient")
    topGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,ACCENT2),ColorSequenceKeypoint.new(0.5,BG_FRAME),ColorSequenceKeypoint.new(1,BG_FRAME)})
    topGrad.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.85),NumberSequenceKeypoint.new(0.5,1),NumberSequenceKeypoint.new(1,1)})
    topGrad.Parent = TopBar
    local accentLine = Instance.new("Frame")
    accentLine.Size = UDim2.new(1,0,0,2); accentLine.Position = UDim2.new(0,0,1,-2)
    accentLine.BackgroundColor3 = ACCENT; accentLine.BorderSizePixel = 0; accentLine.Parent = TopBar
    local accentLineGrad = Instance.new("UIGradient")
    accentLineGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,ACCENT3),ColorSequenceKeypoint.new(0.5,ACCENT),ColorSequenceKeypoint.new(1,ACCENT3)})
    accentLineGrad.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.3),NumberSequenceKeypoint.new(0.5,0),NumberSequenceKeypoint.new(1,0.3)})
    accentLineGrad.Parent = accentLine

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Size = UDim2.new(0, isMobile and 150 or 220, 1, 0); TitleLabel.Position = UDim2.fromOffset(14,0)
    TitleLabel.BackgroundTransparency = 1; TitleLabel.Text = title; TitleLabel.TextColor3 = TEXT_WHITE
    TitleLabel.Font = Enum.Font.GothamBold; TitleLabel.TextSize = isMobile and 12 or 14
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left; TitleLabel.Parent = TopBar
    local titleGrad = Instance.new("UIGradient")
    titleGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,TEXT_WHITE),ColorSequenceKeypoint.new(1,ACCENT_SOFT)})
    titleGrad.Parent = TitleLabel

    local SubtitleLabel = Instance.new("TextLabel")
    SubtitleLabel.Size = UDim2.new(0,150,1,0); SubtitleLabel.Position = UDim2.fromOffset(isMobile and 140 or 170,0)
    SubtitleLabel.BackgroundTransparency = 1; SubtitleLabel.Text = subtitle; SubtitleLabel.TextColor3 = TEXT_GRAY
    SubtitleLabel.Font = Enum.Font.Gotham; SubtitleLabel.TextSize = 10
    SubtitleLabel.TextXAlignment = Enum.TextXAlignment.Left; SubtitleLabel.Parent = TopBar

    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Size = UDim2.fromOffset(28,28); CloseBtn.Position = UDim2.new(1,-36,0,7)
    CloseBtn.BackgroundColor3 = BG_ELEM; CloseBtn.Text = "X"; CloseBtn.TextColor3 = TEXT_GRAY
    CloseBtn.Font = Enum.Font.GothamBold; CloseBtn.TextSize = 13; CloseBtn.Parent = TopBar
    Instance.new("UICorner",CloseBtn).CornerRadius = UDim.new(0,8)
    CloseBtn.MouseEnter:Connect(function() tweenSine(CloseBtn,0.15,{BackgroundColor3=Color3.fromRGB(180,40,60),TextColor3=TEXT_WHITE}):Play() end)
    CloseBtn.MouseLeave:Connect(function() tweenSine(CloseBtn,0.15,{BackgroundColor3=BG_ELEM,TextColor3=TEXT_GRAY}):Play() end)

    local MinBtn = Instance.new("TextButton")
    MinBtn.Size = UDim2.fromOffset(28,28); MinBtn.Position = UDim2.new(1,-68,0,7)
    MinBtn.BackgroundColor3 = BG_ELEM; MinBtn.Text = "-"; MinBtn.TextColor3 = TEXT_GRAY
    MinBtn.Font = Enum.Font.GothamBold; MinBtn.TextSize = 13; MinBtn.Parent = TopBar
    Instance.new("UICorner",MinBtn).CornerRadius = UDim.new(0,8)
    MinBtn.MouseEnter:Connect(function() tweenSine(MinBtn,0.15,{BackgroundColor3=BG_HOVER,TextColor3=TEXT_WHITE}):Play() end)
    MinBtn.MouseLeave:Connect(function() tweenSine(MinBtn,0.15,{BackgroundColor3=BG_ELEM,TextColor3=TEXT_GRAY}):Play() end)

    local Sidebar
    if isMobile then
        Sidebar = Instance.new("ScrollingFrame")
        Sidebar.ScrollBarThickness = 0
        Sidebar.CanvasSize = UDim2.new(0, 0, 0, 0)
        Sidebar.AutomaticCanvasSize = Enum.AutomaticSize.X
        Sidebar.ScrollingDirection = Enum.ScrollingDirection.X
        Sidebar.Size = UDim2.new(1, -12, 0, 38)
        Sidebar.Position = UDim2.new(0, 6, 0, 42)
    else
        Sidebar = Instance.new("Frame")
        Sidebar.Size = UDim2.new(0, 135, 1, -42)
        Sidebar.Position = UDim2.new(0, 0, 0, 42)
    end
    Sidebar.Name = "Sidebar"
    Sidebar.BackgroundColor3 = BG_FRAME; Sidebar.BorderSizePixel = 0; Sidebar.Parent = MainFrame
    
    local sidebarGrad = Instance.new("UIGradient")
    sidebarGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,BG_FRAME),ColorSequenceKeypoint.new(1,BG_DARK)})
    sidebarGrad.Rotation = isMobile and 90 or 180; sidebarGrad.Parent = Sidebar

    local Content = Instance.new("Frame"); Content.Name = "Content"
    if isMobile then
        Content.Size = UDim2.new(1, -12, 1, -88)
        Content.Position = UDim2.new(0, 6, 0, 84)
    else
        Content.Size = UDim2.new(1, -135, 1, -42)
        Content.Position = UDim2.new(0, 135, 0, 42)
    end
    Content.BackgroundColor3 = BG_DARK; Content.BorderSizePixel = 0; Content.Parent = MainFrame
    pcall(function() Content.ClipDescendants = true end)

    local dragging, dragStart, startPos
    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = MainFrame.Position
        end
    end)
    TopBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    regUiConn(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+delta.X, startPos.Y.Scale, startPos.Y.Offset+delta.Y)
        end
    end))

    local minimized = false
    local originalSize = size
    CloseBtn.MouseButton1Click:Connect(function()
        tweenBack(MainFrame, 0.3, {Size=UDim2.fromOffset(0,0)}):Play()
        _tdelay(0.3, function()
            pcall(function()
                for _, c in ipairs(uiConns) do pcall(function() c:Disconnect() end) end
                ScreenGui:Destroy()
            end)
        end)
    end)
    MinBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then 
            tweenQuint(MainFrame,0.25,{Size=UDim2.fromOffset(size.X.Offset,42)}):Play()
        else 
            tweenQuint(MainFrame,0.25,{Size=originalSize}):Play() 
        end
    end)

    local tabs, tabButtons, tabFrames = {}, {}, {}
    local currentTab = nil
    
    local sidebarLayout = Instance.new("UIListLayout", Sidebar)
    sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
    sidebarLayout.Padding = UDim.new(0, isMobile and 6 or 2)
    if isMobile then
        sidebarLayout.FillDirection = Enum.FillDirection.Horizontal
    end
    
    local sidebarPad = Instance.new("UIPadding", Sidebar)
    if isMobile then
        sidebarPad.PaddingTop = UDim.new(0, 4)
        sidebarPad.PaddingBottom = UDim.new(0, 4)
        sidebarPad.PaddingLeft = UDim.new(0, 4)
        sidebarPad.PaddingRight = UDim.new(0, 4)
    else
        sidebarPad.PaddingTop = UDim.new(0, 6)
        sidebarPad.PaddingLeft = UDim.new(0, 6)
        sidebarPad.PaddingRight = UDim.new(0, 6)
    end

    local function createTab(name, order)
        local tabBtn = Instance.new("TextButton"); tabBtn.Name = "TabBtn_"..name
        tabBtn.BackgroundColor3 = BG_ELEM
        tabBtn.Font = Enum.Font.GothamMedium; tabBtn.TextSize = 11
        tabBtn.LayoutOrder = order; tabBtn.Parent = Sidebar; tabBtn.AutoButtonColor = false
        Instance.new("UICorner",tabBtn).CornerRadius = UDim.new(0,6)
        
        if isMobile then
            tabBtn.Size = UDim2.new(0, 0, 1, 0)
            tabBtn.AutomaticSize = Enum.AutomaticSize.X
            tabBtn.Text = "  " .. name .. "  "
            tabBtn.TextXAlignment = Enum.TextXAlignment.Center
        else
            tabBtn.Size = UDim2.new(1, 0, 0, 38)
            tabBtn.Text = "  "..name
            tabBtn.TextXAlignment = Enum.TextXAlignment.Left
        end

        local tabFrame = Instance.new("ScrollingFrame"); tabFrame.Name = "TabFrame_"..name
        tabFrame.Size = UDim2.new(1,-8,1,-8); tabFrame.Position = UDim2.fromOffset(4,4)
        tabFrame.BackgroundTransparency = 1; tabFrame.BorderSizePixel = 0; tabFrame.Visible = false
        tabFrame.ScrollBarThickness = isMobile and 2 or 4
        tabFrame.ScrollBarImageColor3 = ACCENT
        tabFrame.CanvasSize = UDim2.fromOffset(0,0); tabFrame.Parent = Content
        local layout = Instance.new("UIListLayout",tabFrame)
        layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Padding = UDim.new(0, isMobile and 4 or 6)
        local pad = Instance.new("UIPadding",tabFrame)
        pad.PaddingTop = UDim.new(0,6); pad.PaddingLeft = UDim.new(0,4); pad.PaddingRight = UDim.new(0,4)
        pcall(function() tabFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y end)

        table.insert(tabs, name)
        tabButtons[name] = tabBtn; tabFrames[name] = tabFrame

        tabBtn.MouseEnter:Connect(function()
            if currentTab ~= name then tweenSine(tabBtn,0.15,{BackgroundColor3=BG_HOVER}):Play() end
        end)
        tabBtn.MouseLeave:Connect(function()
            if currentTab ~= name then tweenSine(tabBtn,0.15,{BackgroundColor3=BG_ELEM}):Play() end
        end)
        tabBtn.MouseButton1Click:Connect(function()
            if currentTab == name then return end
            local oldTab = currentTab; currentTab = name
            if oldTab then
                local oF = tabFrames[oldTab]; local oB = tabButtons[oldTab]
                tweenSine(oB,0.2,{BackgroundColor3=BG_ELEM}):Play(); oB.TextColor3 = TEXT_GRAY
                oF.BackgroundTransparency = 0
                tweenSine(oF,0.15,{BackgroundTransparency=1}):Play()
                _tdelay(0.15, function() if oF then oF.Visible = false end end)
            end
            tabFrame.Visible = true; tabFrame.BackgroundTransparency = 1
            tweenSine(tabFrame,0.2,{BackgroundTransparency=0}):Play()
            tweenBack(tabBtn,0.25,{BackgroundColor3=ACCENT}):Play()
            tabBtn.TextColor3 = TEXT_WHITE
        end)
        return tabFrame
    end

    local tabOrder = 0
    local function nextOrder() tabOrder = tabOrder+1; return tabOrder end

    local win = setmetatable({}, VxnityUI)
    win._gui = ScreenGui; win._frame = MainFrame; win._content = Content
    win._createTab = createTab; win._nextOrder = nextOrder
    win._tabFrames = tabFrames; win._tabButtons = tabButtons

    function win:Tab(opts)
        local name = opts.Title or "Tab"
        local tf = createTab(name, nextOrder())
        if not currentTab then
            currentTab = name; tf.Visible = true
            tabButtons[name].BackgroundColor3 = ACCENT; tabButtons[name].TextColor3 = TEXT_WHITE
        end
        local tabObj = setmetatable({_frame=tf, _order=0, _parent=win}, {__index=VxnityUI})

        function tabObj:Section(opts)
            self._order = self._order+1
            local sec = Instance.new("TextLabel")
            sec.Size = UDim2.new(1,0,0,24); sec.BackgroundTransparency = 1
            sec.Text = "  "..(opts.Title or ""):upper(); sec.TextColor3 = ACCENT
            sec.Font = Enum.Font.GothamBold; sec.TextSize = 11
            sec.TextXAlignment = Enum.TextXAlignment.Left; sec.LayoutOrder = self._order; sec.Parent = self._frame
            local secGrad = Instance.new("UIGradient")
            secGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,ACCENT),ColorSequenceKeypoint.new(0.4,ACCENT_SOFT),ColorSequenceKeypoint.new(1,ACCENT_SOFT)})
            secGrad.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,0.4)})
            secGrad.Parent = sec
            local line = Instance.new("Frame")
            line.Size = UDim2.new(1,-12,0,1); line.Position = UDim2.new(0,6,1,-2)
            line.BackgroundColor3 = ACCENT; line.BackgroundTransparency = 0.6
            line.BorderSizePixel = 0; line.LayoutOrder = self._order; line.Parent = self._frame
            local lineGrad = Instance.new("UIGradient")
            lineGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,ACCENT3),ColorSequenceKeypoint.new(0.5,ACCENT),ColorSequenceKeypoint.new(1,Color3.fromRGB(40,28,45))})
            lineGrad.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.2),NumberSequenceKeypoint.new(1,0.8)})
            lineGrad.Parent = line
            return self
        end

        function tabObj:Toggle(opts)
            self._order = self._order+1
            local state = false
            local persistKey = opts.PersistKey
            if persistKey and P[persistKey] ~= nil then state = P[persistKey] end
            local row = Instance.new("TextButton")
            row.Size = UDim2.new(1,0,0, isMobile and 54 or 48); row.BackgroundColor3 = BG_ELEM
            row.BorderSizePixel = 0; row.LayoutOrder = self._order; row.Parent = self._frame
            row.Text = ""; row.AutoButtonColor = false
            Instance.new("UICorner",row).CornerRadius = UDim.new(0,8)
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1,-60,1,0); lbl.Position = UDim2.fromOffset(12,0)
            lbl.BackgroundTransparency = 1; lbl.Text = opts.Title or ""
            lbl.TextColor3 = TEXT_WHITE; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = isMobile and 12 or 13
            lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row
            if opts.Desc then
                local d = Instance.new("TextLabel")
                d.Size = UDim2.new(1,-60,0,12); d.Position = UDim2.fromOffset(12, isMobile and 32 or 28)
                d.BackgroundTransparency = 1; d.Text = opts.Desc; d.TextColor3 = TEXT_GRAY
                d.Font = Enum.Font.Gotham; d.TextSize = 9
                d.TextXAlignment = Enum.TextXAlignment.Left; d.Parent = row
                lbl.Position = UDim2.fromOffset(12, 6)
            end
            local togBtn = Instance.new("Frame")
            togBtn.Size = UDim2.fromOffset(48,26); togBtn.Position = UDim2.new(1,-58,0.5,-13)
            togBtn.BackgroundColor3 = BG_DARK; togBtn.Parent = row
            Instance.new("UICorner",togBtn).CornerRadius = UDim.new(1,0)
            local togStroke = Instance.new("UIStroke"); togStroke.Color = OUTLINE; togStroke.Thickness = 1.5; togStroke.Parent = togBtn
            local dot = Instance.new("Frame")
            dot.Size = UDim2.fromOffset(20,20); dot.Position = UDim2.fromOffset(3,3)
            dot.BackgroundColor3 = TEXT_GRAY; dot.Parent = togBtn
            Instance.new("UICorner",dot).CornerRadius = UDim.new(1,0)
            local glowFrame = Instance.new("Frame")
            glowFrame.Size = UDim2.new(1,4,1,4); glowFrame.Position = UDim2.new(0,-2,0,-2)
            glowFrame.BackgroundColor3 = ACCENT; glowFrame.BackgroundTransparency = 1
            glowFrame.ZIndex = row.ZIndex-1; glowFrame.Parent = row
            Instance.new("UICorner",glowFrame).CornerRadius = UDim.new(0,10)

            local glowConn = nil
            local function setToggleVisual(s)
                if s then
                    dot.Position = UDim2.fromOffset(25,3); dot.BackgroundColor3 = ACCENT
                    togBtn.BackgroundColor3 = ACCENT2; glowFrame.BackgroundTransparency = 0.85
                    if glowConn then pcall(function() glowConn:Disconnect() end); glowConn = nil end
                    local pulseUp = true
                    glowConn = regUiConn(RunService.Heartbeat:Connect(function()
                        if not state then
                            pcall(function() glowConn:Disconnect() end); glowConn = nil; return
                        end
                        if pulseUp then
                            glowFrame.BackgroundTransparency = glowFrame.BackgroundTransparency + 0.02
                            if glowFrame.BackgroundTransparency >= 0.92 then pulseUp = false end
                        else
                            glowFrame.BackgroundTransparency = glowFrame.BackgroundTransparency - 0.02
                            if glowFrame.BackgroundTransparency <= 0.82 then pulseUp = true end
                        end
                    end))
                else
                    dot.Position = UDim2.fromOffset(3,3); dot.BackgroundColor3 = TEXT_GRAY
                    togBtn.BackgroundColor3 = BG_DARK; glowFrame.BackgroundTransparency = 1
                    if glowConn then pcall(function() glowConn:Disconnect() end); glowConn = nil end
                end
            end

            row.MouseEnter:Connect(function() tweenSine(row,0.12,{BackgroundColor3=BG_HOVER}):Play() end)
            row.MouseLeave:Connect(function() tweenSine(row,0.12,{BackgroundColor3=BG_ELEM}):Play() end)
            row.MouseButton1Click:Connect(function()
                state = not state
                setToggleVisual(state)
                if persistKey then P[persistKey] = state end
                if opts.Callback then opts.Callback(state) end
            end)
            if state then setToggleVisual(true) end
            return self
        end

        function tabObj:Slider(opts)
            self._order = self._order+1
            local sMin = opts.Value and opts.Value.Min or 0
            local sMax = opts.Value and opts.Value.Max or 100
            local val  = opts.Value and opts.Value.Default or sMin
            local step = opts.Step
            if not step then
                local range = sMax-sMin
                if range <= 2 then step = 0.1
                elseif range <= 10 then step = 0.5
                elseif range <= 50 then step = 1
                else step = 10 end
            end
            local function roundVal(v) return math.floor((v-sMin)/step+0.5)*step+sMin end
            val = roundVal(math.clamp(val, sMin, sMax))
            local function formatVal(v)
                if step < 1 then return string.format("%.1f",v) end
                return tostring(math.floor(v+0.5))
            end
            
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1,0,0, isMobile and 58 or 52); row.BackgroundColor3 = BG_ELEM
            row.BorderSizePixel = 0; row.LayoutOrder = self._order; row.Parent = self._frame
            Instance.new("UICorner",row).CornerRadius = UDim.new(0,8)
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(0.55,0,0,16); lbl.Position = UDim2.fromOffset(10,4)
            lbl.BackgroundTransparency = 1; lbl.Text = opts.Title or ""
            lbl.TextColor3 = TEXT_WHITE; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = isMobile and 11 or 12
            lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row
            local valLbl = Instance.new("TextLabel")
            valLbl.Size = UDim2.new(0.45,-10,0,16); valLbl.Position = UDim2.new(0.55,0,0,4)
            valLbl.BackgroundTransparency = 1; valLbl.Text = formatVal(val)
            valLbl.TextColor3 = ACCENT; valLbl.Font = Enum.Font.GothamBold; valLbl.TextSize = isMobile and 12 or 13
            valLbl.TextXAlignment = Enum.TextXAlignment.Right; valLbl.Parent = row
            if opts.Desc then
                local d = Instance.new("TextLabel")
                d.Size = UDim2.new(1,-20,0,10); d.Position = UDim2.fromOffset(10,20)
                d.BackgroundTransparency = 1; d.Text = opts.Desc; d.TextColor3 = TEXT_GRAY
                d.Font = Enum.Font.Gotham; d.TextSize = 8
                d.TextXAlignment = Enum.TextXAlignment.Left; d.Parent = row
            end
            local minusBtn = Instance.new("TextButton")
            minusBtn.Size = UDim2.fromOffset(24,24); minusBtn.Position = UDim2.new(0,6,1, isMobile and -32 or -30)
            minusBtn.BackgroundColor3 = BG_DARK; minusBtn.Text = "-"
            minusBtn.TextColor3 = TEXT_WHITE; minusBtn.Font = Enum.Font.GothamBold
            minusBtn.TextSize = 16; minusBtn.Parent = row
            Instance.new("UICorner",minusBtn).CornerRadius = UDim.new(0,4)
            local plusBtn = Instance.new("TextButton")
            plusBtn.Size = UDim2.fromOffset(24,24); plusBtn.Position = UDim2.new(1,-30,1, isMobile and -32 or -30)
            plusBtn.BackgroundColor3 = BG_DARK; plusBtn.Text = "+"
            plusBtn.TextColor3 = TEXT_WHITE; plusBtn.Font = Enum.Font.GothamBold
            plusBtn.TextSize = 16; plusBtn.Parent = row
            Instance.new("UICorner",plusBtn).CornerRadius = UDim.new(0,4)
            
            local track = Instance.new("Frame")
            track.Size = UDim2.new(1,-72,0,8); track.Position = UDim2.new(0,36,1, isMobile and -24 or -26)
            track.BackgroundColor3 = BG_DARK; track.BorderSizePixel = 0; track.Parent = row
            Instance.new("UICorner",track).CornerRadius = UDim.new(1,0)
            local startPct = math.clamp((val-sMin)/(sMax-sMin),0,1)
            local fill = Instance.new("Frame")
            fill.Size = UDim2.new(startPct,0,1,0); fill.BackgroundColor3 = ACCENT
            fill.BorderSizePixel = 0; fill.Parent = track
            Instance.new("UICorner",fill).CornerRadius = UDim.new(1,0)
            local fillGrad = Instance.new("UIGradient")
            fillGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,ACCENT),ColorSequenceKeypoint.new(1,ACCENT3)})
            fillGrad.Rotation = 90; fillGrad.Parent = fill
            local knob = Instance.new("TextButton")
            knob.Size = UDim2.fromOffset(22,22); knob.Position = UDim2.new(startPct,-11,0.5,-11)
            knob.BackgroundColor3 = TEXT_WHITE; knob.Text = ""; knob.Parent = track
            Instance.new("UICorner",knob).CornerRadius = UDim.new(1,0)
            local knobStroke = Instance.new("UIStroke"); knobStroke.Color = ACCENT; knobStroke.Thickness = 2; knobStroke.Parent = knob
            
            local function updateSlider(newVal)
                newVal = roundVal(math.clamp(newVal,sMin,sMax)); val = newVal
                local pct = (sMax>sMin) and math.clamp((val-sMin)/(sMax-sMin),0,1) or 0
                fill.Size = UDim2.new(pct,0,1,0); knob.Position = UDim2.new(pct,-11,0.5,-11)
                valLbl.Text = formatVal(val)
                if opts.Callback then opts.Callback(val) end
            end
            track.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    local pct = math.clamp((input.Position.X-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1)
                    updateSlider(sMin+pct*(sMax-sMin))
                end
            end)
            local sliding = false
            knob.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then sliding = true end
            end)
            knob.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then sliding = false end
            end)
            regUiConn(UserInputService.InputChanged:Connect(function(input)
                if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    local pct = math.clamp((input.Position.X-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1)
                    updateSlider(sMin+pct*(sMax-sMin))
                end
            end))
            minusBtn.MouseButton1Click:Connect(function() updateSlider(val-step) end)
            plusBtn.MouseButton1Click:Connect(function() updateSlider(val+step) end)
            return self
        end

        function tabObj:Button(opts)
            self._order = self._order+1
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1,0,0, isMobile and 46 or 42); btn.BackgroundColor3 = BG_ELEM
            btn.Text = "  "..(opts.Title or ""); btn.TextColor3 = TEXT_WHITE
            btn.Font = Enum.Font.GothamMedium; btn.TextSize = 13
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.LayoutOrder = self._order; btn.Parent = self._frame; btn.AutoButtonColor = false
            Instance.new("UICorner",btn).CornerRadius = UDim.new(0,8)
            if opts.Desc then
                local d = Instance.new("TextLabel")
                d.Size = UDim2.new(1,-20,0,11); d.Position = UDim2.fromOffset(10, isMobile and 28 or 24)
                d.BackgroundTransparency = 1; d.Text = opts.Desc; d.TextColor3 = TEXT_GRAY
                d.Font = Enum.Font.Gotham; d.TextSize = 9
                d.TextXAlignment = Enum.TextXAlignment.Left; d.Parent = btn
                btn.Size = UDim2.new(1,0,0, isMobile and 54 or 48)
            end
            local accentDot = Instance.new("Frame")
            accentDot.Size = UDim2.fromOffset(3,16); accentDot.Position = UDim2.new(0,4,0.5,-8)
            accentDot.BackgroundColor3 = ACCENT; accentDot.BackgroundTransparency = 0.6
            accentDot.Visible = false; accentDot.Parent = btn
            Instance.new("UICorner",accentDot).CornerRadius = UDim.new(1,0)
            btn.MouseEnter:Connect(function()
                tweenSine(btn,0.12,{BackgroundColor3=BG_HOVER}):Play()
                accentDot.Visible = true; tweenSine(accentDot,0.12,{BackgroundTransparency=0.3}):Play()
            end)
            btn.MouseLeave:Connect(function()
                tweenSine(btn,0.12,{BackgroundColor3=BG_ELEM}):Play()
                tweenSine(accentDot,0.15,{BackgroundTransparency=0.6}):Play()
            end)
            btn.MouseButton1Click:Connect(function()
                tweenQuint(btn,0.1,{BackgroundColor3=ACCENT2}):Play()
                _tdelay(0.1, function() tweenQuint(btn,0.15,{BackgroundColor3=BG_ELEM}):Play() end)
                if opts.Callback then opts.Callback() end
            end)
            return self
        end

        function tabObj:Keybind(opts)
            self._order = self._order+1
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1,0,0, isMobile and 46 or 42); row.BackgroundColor3 = BG_ELEM
            row.BorderSizePixel = 0; row.LayoutOrder = self._order; row.Parent = self._frame
            Instance.new("UICorner",row).CornerRadius = UDim.new(0,8)
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1,-70,1,0); lbl.Position = UDim2.fromOffset(12,0)
            lbl.BackgroundTransparency = 1; lbl.Text = opts.Title or ""
            lbl.TextColor3 = TEXT_WHITE; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 13
            lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row
            local bind = Instance.new("TextButton")
            bind.Size = UDim2.fromOffset(52,26); bind.Position = UDim2.new(1,-62,0.5,-13)
            bind.BackgroundColor3 = BG_DARK; bind.Text = opts.Default or "..."
            bind.TextColor3 = TEXT_GRAY; bind.Font = Enum.Font.Gotham; bind.TextSize = 11; bind.Parent = row
            Instance.new("UICorner",bind).CornerRadius = UDim.new(0,6)
            local bindStroke = Instance.new("UIStroke"); bindStroke.Color = OUTLINE; bindStroke.Thickness = 1; bindStroke.Parent = bind
            bind.MouseEnter:Connect(function() tweenSine(bind,0.12,{BackgroundColor3=BG_HOVER,TextColor3=TEXT_WHITE}):Play(); tweenSine(bindStroke,0.12,{Color=ACCENT}):Play() end)
            bind.MouseLeave:Connect(function() tweenSine(bind,0.12,{BackgroundColor3=BG_DARK,TextColor3=TEXT_GRAY}):Play(); tweenSine(bindStroke,0.12,{Color=OUTLINE}):Play() end)
            local listening = false; local currentKey = opts.Default; local listenPulse = nil
            bind.MouseButton1Click:Connect(function()
                listening = true; bind.Text = "..."
                if listenPulse then listenPulse:Disconnect() end
                local toggle = true
                listenPulse = regUiConn(RunService.Heartbeat:Connect(function()
                    if not listening then pcall(function() listenPulse:Disconnect() end); listenPulse = nil; return end
                    toggle = not toggle; bind.TextColor3 = toggle and ACCENT or TEXT_GRAY
                end))
            end)
            regUiConn(UserInputService.InputBegan:Connect(function(input, processed)
                if listening and not processed then
                    local key = input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode or input.UserInputType
                    currentKey = key
                    bind.Text = tostring(key):split(".")[3] or "?"
                    bind.TextColor3 = TEXT_GRAY; listening = false
                    if listenPulse then pcall(function() listenPulse:Disconnect() end); listenPulse = nil end
                    if opts.Callback then opts.Callback(currentKey) end
                end
            end))
            return self
        end

        function tabObj:Input(opts)
            self._order = self._order+1
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1,0,0, isMobile and 62 or 58); row.BackgroundColor3 = BG_ELEM
            row.BorderSizePixel = 0; row.LayoutOrder = self._order; row.Parent = self._frame
            Instance.new("UICorner",row).CornerRadius = UDim.new(0,8)
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1,-10,0,18); lbl.Position = UDim2.fromOffset(12,6)
            lbl.BackgroundTransparency = 1; lbl.Text = opts.Title or ""
            lbl.TextColor3 = TEXT_WHITE; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 12
            lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row
            local inputBox = Instance.new("TextBox")
            inputBox.Size = UDim2.new(1,-16,0, isMobile and 30 or 26); inputBox.Position = UDim2.fromOffset(8, isMobile and 28 or 26)
            inputBox.BackgroundColor3 = BG_DARK; inputBox.BorderSizePixel = 0
            inputBox.Text = opts.Default or ""; inputBox.PlaceholderText = opts.PlaceholderText or ""
            inputBox.TextColor3 = TEXT_WHITE; inputBox.PlaceholderColor3 = TEXT_GRAY
            inputBox.Font = Enum.Font.Gotham; inputBox.TextSize = 12
            inputBox.ClearTextOnFocus = false; inputBox.Parent = row
            Instance.new("UICorner",inputBox).CornerRadius = UDim.new(0,6)
            local inputStroke = Instance.new("UIStroke"); inputStroke.Color = OUTLINE; inputStroke.Thickness = 1; inputStroke.Parent = inputBox
            inputBox.Focused:Connect(function() tweenSine(inputStroke,0.15,{Color=ACCENT}):Play() end)
            inputBox.FocusLost:Connect(function(enter)
                tweenSine(inputStroke,0.15,{Color=OUTLINE}):Play()
                if opts.Callback then opts.Callback(inputBox.Text) end
            end)
            return self
        end

        function tabObj:Dropdown(opts)
            self._order = self._order+1
            local options  = opts.Options or {}
            local selected = opts.Default or (options[1] or "")
            local open     = false
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1,0,0, isMobile and 48 or 42); row.BackgroundColor3 = BG_ELEM
            row.BorderSizePixel = 0; row.LayoutOrder = self._order; row.Parent = self._frame
            Instance.new("UICorner",row).CornerRadius = UDim.new(0,8)
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(0.4,0,1,0); lbl.Position = UDim2.fromOffset(12,0)
            lbl.BackgroundTransparency = 1; lbl.Text = opts.Title or ""
            lbl.TextColor3 = TEXT_WHITE; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 13
            lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row
            local selBtn = Instance.new("TextButton")
            selBtn.Size = UDim2.new(0.55,0,0.7,0); selBtn.Position = UDim2.new(0.42,0,0.15,0)
            selBtn.BackgroundColor3 = BG_DARK; selBtn.Text = "  "..selected.."  v"
            selBtn.TextColor3 = TEXT_WHITE; selBtn.Font = Enum.Font.Gotham; selBtn.TextSize = 11
            selBtn.TextXAlignment = Enum.TextXAlignment.Left; selBtn.Parent = row
            Instance.new("UICorner",selBtn).CornerRadius = UDim.new(0,6)
            local selStroke = Instance.new("UIStroke"); selStroke.Color = OUTLINE; selStroke.Thickness = 1; selStroke.Parent = selBtn
            local listFrame = Instance.new("Frame")
            listFrame.Size = UDim2.new(0.55,0,0, #options * (isMobile and 34 or 28))
            listFrame.Position = UDim2.new(0.42,0,1,2)
            listFrame.BackgroundColor3 = BG_ELEM; listFrame.BorderSizePixel = 0
            listFrame.Visible = false; listFrame.ZIndex = 10; listFrame.Parent = row
            Instance.new("UICorner",listFrame).CornerRadius = UDim.new(0,6)
            Instance.new("UIStroke",listFrame).Color = OUTLINE
            local listLayout = Instance.new("UIListLayout",listFrame)
            listLayout.SortOrder = Enum.SortOrder.LayoutOrder
            for i, opt in ipairs(options) do
                local optBtn = Instance.new("TextButton")
                optBtn.Size = UDim2.new(1,0,0, isMobile and 34 or 28); optBtn.BackgroundColor3 = BG_ELEM
                optBtn.Text = "  "..opt; optBtn.TextColor3 = TEXT_WHITE
                optBtn.Font = Enum.Font.Gotham; optBtn.TextSize = 11
                optBtn.TextXAlignment = Enum.TextXAlignment.Left
                optBtn.LayoutOrder = i; optBtn.Parent = listFrame; optBtn.ZIndex = 11; optBtn.AutoButtonColor = false
                optBtn.MouseEnter:Connect(function() tweenSine(optBtn,0.1,{BackgroundColor3=BG_HOVER}):Play() end)
                optBtn.MouseLeave:Connect(function() tweenSine(optBtn,0.1,{BackgroundColor3=BG_ELEM}):Play() end)
                optBtn.MouseButton1Click:Connect(function()
                    selected = opt; selBtn.Text = "  "..opt.."  v"; open = false; listFrame.Visible = false
                    if opts.Callback then opts.Callback(opt,i) end
                end)
            end
            selBtn.MouseButton1Click:Connect(function()
                open = not open; listFrame.Visible = open
                if open then tweenSine(selStroke,0.15,{Color=ACCENT}):Play()
                else tweenSine(selStroke,0.15,{Color=OUTLINE}):Play() end
            end)
            return self
        end

        return tabObj
    end

    local OpenBtn = Instance.new("TextButton"); OpenBtn.Name = "TLOpenBtn"
    OpenBtn.Size = UDim2.fromOffset(52,52)
    OpenBtn.Position = isMobile and UDim2.new(0.85, -26, 0.2, -26) or UDim2.new(0,12,0.5,-26)
    OpenBtn.BackgroundColor3 = ACCENT; OpenBtn.Text = "TL"; OpenBtn.TextColor3 = TEXT_WHITE
    OpenBtn.Font = Enum.Font.GothamBold; OpenBtn.TextSize = 18; OpenBtn.Parent = ScreenGui
    OpenBtn.AutoButtonColor = false
    Instance.new("UICorner",OpenBtn).CornerRadius = UDim.new(1,0)
    local openGrad = Instance.new("UIGradient")
    openGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,ACCENT),ColorSequenceKeypoint.new(1,ACCENT3)})
    openGrad.Rotation = 135; openGrad.Parent = OpenBtn
    local openGlow = Instance.new("Frame")
    openGlow.Size = UDim2.new(1,12,1,12); openGlow.Position = UDim2.new(0,-6,0,-6)
    openGlow.BackgroundColor3 = ACCENT; openGlow.BackgroundTransparency = 0.85
    openGlow.ZIndex = OpenBtn.ZIndex-1; openGlow.Parent = OpenBtn
    Instance.new("UICorner",openGlow).CornerRadius = UDim.new(1,0)
    _tspawn(function()
        local pulseUp = true
        while openGlow and openGlow.Parent do
            if pulseUp then openGlow.BackgroundTransparency = openGlow.BackgroundTransparency + 0.005
            else openGlow.BackgroundTransparency = openGlow.BackgroundTransparency - 0.005 end
            if openGlow.BackgroundTransparency >= 0.95 then pulseUp = false end
            if openGlow.BackgroundTransparency <= 0.80 then pulseUp = true end
            _twait(0.03)
        end
    end)
    OpenBtn.MouseEnter:Connect(function() 
        if not isMobile then
            tweenSine(OpenBtn,0.15,{Size=UDim2.fromOffset(56,56)}):Play() 
        end
    end)
    OpenBtn.MouseLeave:Connect(function() 
        if not isMobile then
            tweenSine(OpenBtn,0.2,{Size=UDim2.fromOffset(52,52)}):Play() 
        end
    end)

    -- Mobile touch drag support para el botón flotante
    local floatDragging, floatDragStart, floatStartPos
    local totalDragDistance = 0
    local dragThreshold = 8

    OpenBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            floatDragging = true
            floatDragStart = input.Position
            floatStartPos = OpenBtn.Position
            totalDragDistance = 0
        end
    end)
    
    OpenBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            floatDragging = false
        end
    end)
    
    regUiConn(UserInputService.InputChanged:Connect(function(input)
        if floatDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - floatDragStart
            totalDragDistance = delta.Magnitude
            OpenBtn.Position = UDim2.new(floatStartPos.X.Scale, floatStartPos.X.Offset + delta.X, floatStartPos.Y.Scale, floatStartPos.Y.Offset + delta.Y)
        end
    end))

    MainFrame.Visible = false
    OpenBtn.MouseButton1Click:Connect(function()
        if totalDragDistance > dragThreshold then return end
        MainFrame.Visible = not MainFrame.Visible
        if MainFrame.Visible then
            MainFrame.Size = UDim2.fromOffset(0,0)
            tweenBack(MainFrame, 0.35, {Size=originalSize}):Play()
        end
    end)
    
    return win
end

local ScreenLoader = Instance.new("ScreenGui")
ScreenLoader.Name = "TLSystemLoader"; ScreenLoader.ResetOnSpawn = false
ScreenLoader.IgnoreGuiInset = true; ScreenLoader.Parent = getGuiParent()

local loadFrame = Instance.new("Frame")
loadFrame.Size = UDim2.fromOffset(280,150); loadFrame.Position = UDim2.new(0.5,-140,0.5,-75)
loadFrame.BackgroundColor3 = BG_DARK; loadFrame.BorderSizePixel = 0; loadFrame.Parent = ScreenLoader
Instance.new("UICorner",loadFrame).CornerRadius = UDim.new(0,14)
local loadStroke = Instance.new("UIStroke"); loadStroke.Color = OUTLINE; loadStroke.Thickness = 1.5; loadStroke.Parent = loadFrame
local loaderTitle = Instance.new("TextLabel")
loaderTitle.Size = UDim2.new(1,0,0,34); loaderTitle.Position = UDim2.fromOffset(0,18)
loaderTitle.BackgroundTransparency = 1; loaderTitle.Text = "TOUCHLINE PRO"
loaderTitle.TextColor3 = ACCENT; loaderTitle.Font = Enum.Font.GothamBold; loaderTitle.TextSize = 20; loaderTitle.Parent = loadFrame
local titleGrad = Instance.new("UIGradient")
titleGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,ACCENT),ColorSequenceKeypoint.new(0.5,ACCENT_SOFT),ColorSequenceKeypoint.new(1,ACCENT3)})
titleGrad.Rotation = 90; titleGrad.Parent = loaderTitle
local loaderSub = Instance.new("TextLabel")
loaderSub.Size = UDim2.new(1,0,0,16); loaderSub.Position = UDim2.fromOffset(0,56)
loaderSub.BackgroundTransparency = 1; loaderSub.Text = "Cargando v2..."
loaderSub.TextColor3 = TEXT_GRAY; loaderSub.Font = Enum.Font.Gotham; loaderSub.TextSize = 11; loaderSub.Parent = loadFrame
local progressTrack = Instance.new("Frame")
progressTrack.Size = UDim2.new(0.8,0,0,6); progressTrack.Position = UDim2.new(0.1,0,0,84)
progressTrack.BackgroundColor3 = BG_ELEM; progressTrack.BorderSizePixel = 0; progressTrack.Parent = loadFrame
Instance.new("UICorner",progressTrack).CornerRadius = UDim.new(1,0)
local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.new(0,0,1,0); progressFill.BackgroundColor3 = ACCENT
progressFill.BorderSizePixel = 0; progressFill.Parent = progressTrack
Instance.new("UICorner",progressFill).CornerRadius = UDim.new(1,0)
local progressGrad = Instance.new("UIGradient")
progressGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,ACCENT3),ColorSequenceKeypoint.new(0.5,ACCENT),ColorSequenceKeypoint.new(1,ACCENT3)})
progressGrad.Rotation = 90; progressGrad.Parent = progressFill
local authorLabel = Instance.new("TextLabel")
authorLabel.Size = UDim2.new(1,0,0,14); authorLabel.Position = UDim2.new(0,0,1,-26)
authorLabel.BackgroundTransparency = 1; authorLabel.Text = "by Gonzita — v2"
authorLabel.TextColor3 = TEXT_MID; authorLabel.Font = Enum.Font.Gotham; authorLabel.TextSize = 10; authorLabel.Parent = loadFrame

_tspawn(function()
    local shimmer = Instance.new("Frame")
    shimmer.Size = UDim2.new(0.3,0,1,0); shimmer.Position = UDim2.new(-0.3,0,0,0)
    shimmer.BackgroundColor3 = Color3.fromRGB(255,255,255); shimmer.BackgroundTransparency = 0.7
    shimmer.BorderSizePixel = 0; shimmer.Parent = progressTrack
    Instance.new("UICorner",shimmer).CornerRadius = UDim.new(1,0)
    while shimmer and shimmer.Parent do
        shimmer.Position = UDim2.new(-0.3,0,0,0)
        tweenQuint(shimmer,1.2,{Position=UDim2.new(1.3,0,0,0)}):Play()
        _twait(1.3)
    end
end)

tweenQuint(progressFill,1.5,{Size=UDim2.new(1,0,1,0)}):Play()

_tspawn(function()
    _twait(1.6)
    tweenExpo(loadFrame, 0.3, {BackgroundTransparency=1}):Play()
    tweenSine(loaderTitle, 0.2, {TextTransparency=1}):Play()
    tweenSine(loaderSub,   0.2, {TextTransparency=1}):Play()
    tweenSine(authorLabel, 0.2, {TextTransparency=1}):Play()
    tweenSine(loadStroke,  0.25, {Thickness=0}):Play()
    _twait(0.35)
    pcall(function() ScreenLoader:Destroy() end)
end)

local currentReactPower = P.reactPower
local ballSpeedMult   = P.ballSpeedMult

local function getReactTargets()
    return _G._TLBall, _G._TLHRP
end

local function applyVelocityRamped(ball, targetVel, steps)
    steps = steps or 1
    if steps <= 1 then
        pcall(function() ball.AssemblyLinearVelocity = targetVel end)
        return
    end
    _tspawn(function()
        for i = 1, steps do
            pcall(function()
                if ball and ball.Parent then
                    ball.AssemblyLinearVelocity = targetVel * (i / steps)
                end
            end)
            _twait(0.016)
        end
    end)
end

-- Centralized Namecall Hook Manager
local oldNamecall = nil
local gkMap = {SaveRA=true,SaveLA=true,SaveRL=true,SaveLL=true,SaveT=true,Tackle=true,Header=true,Kick=true}

local function centralNamecall(self, ...)
    local m = _has_getnamecallmethod and getnamecallmethod() or ""
    
    -- 1. Anti-Kick Protection
    if m == "Kick" or m == "kick" then
        return
    end
    
    -- 2. React Hook
    if m == "FireServer" and currentReactPower > 0 and P.reactHookOn then
        local ball, hrp = getReactTargets()
        if ball and ball.Parent and hrp then
            if prepareBall(ball) then
                local aim      = getAimDirection(hrp)
                local redirect = P.counterReact and getIncomingRedirect(ball, hrp)
                local dir      = redirect or aim
                local targetPos = hrp.Position + dir * 0.15 + Vector3.new(0, 0.05, 0)
                pcall(function() ball.CFrame = CFrame.new(targetPos) end)
                local finalVel = dir * (currentReactPower * ballSpeedMult)
                if P.instantVelocity then
                    pcall(function() ball.AssemblyLinearVelocity = finalVel end)
                else
                    applyVelocityRamped(ball, finalVel, 2)
                end
                pcall(function() ball.AssemblyAngularVelocity = Vector3.new(0, 0, 0) end)
                flashBall()
            end
        end
    end
    
    -- 3. GK Hook
    if m == "FireServer" and P.gkHookOn then
        local selfName = tostring(self.Name or "")
        if gkMap[selfName] then
            local ball, hrp = getReactTargets()
            if ball and hrp then
                pcall(function()
                    prepareBall(ball)
                    local aim = getAimDirection(hrp)
                    ball.CFrame = CFrame.new(hrp.Position + aim * 0.15 + Vector3.new(0, 0.05, 0))
                    applyVelocityRamped(ball, aim * (currentReactPower * ballSpeedMult), 2)
                end)
            end
        end
    end
    
    return oldNamecall(self, ...)
end

local function installCentralHook()
    if _G._TLCentralHookInstalled then return end
    
    local hookSuccess = false
    if _has_hookmetamethod then
        local ok, old = pcall(hookmetamethod, game, "__namecall", safeClosure(centralNamecall))
        if ok and old then
            oldNamecall = old
            hookSuccess = true
        end
    end
    
    if not hookSuccess and _has_getrawmetatable then
        local ok, meta = pcall(getrawmetatable, game)
        if ok and meta then
            local old = rawget(meta, "__namecall")
            if old then
                oldNamecall = old
                trySetReadonly(meta, false)
                meta.__namecall = safeClosure(centralNamecall)
                trySetReadonly(meta, true)
                hookSuccess = true
            end
        end
    end
    
    if hookSuccess then
        _G._TLCentralHookInstalled = true
    end
end

pcall(installCentralHook)

VxnityUI:Notify({ Title="Touchline v1", Desc="Script plemium — v1 mejorado", Duration=3 })

local Window = VxnityUI:CreateWindow({
    Title    = "Touchline  (v1)",
    Subtitle = "By Gonzita — Mejorado",
    Size     = UDim2.fromOffset(660,460)
})


local HomeTab = Window:Tab({ Title="Inicio" })
HomeTab:Section({ Title="Info" })
HomeTab:Button({ Title="Touchline P v1", Desc="Build mejorado — Gonzita" })
HomeTab:Button({ Title="Jugador: "..LocalPlayer.Name, Desc="Executor: Delta / Fluxus / Synapse" })
HomeTab:Section({ Title="Changelog v1" })
HomeTab:Button({ Title="✓ task.spawn / task.wait (no deprecated)" })
HomeTab:Button({ Title="✓ Fix doble AssemblyLinearVelocity" })
HomeTab:Button({ Title="✓ Fix glowConn closure bug" })
HomeTab:Button({ Title="✓ Fix GK Hook (hum.LLCL eliminado)" })
HomeTab:Button({ Title="✓ Anti-kick hook mejorado (sigiloso)" })
HomeTab:Button({ Title="✓ findBall más preciso" })
HomeTab:Button({ Title="✓ Tab Misc: WalkSpeed, JumpPower, Anti-Ragdoll" })
HomeTab:Button({ Title="✓ Tab ESP: Selección visual del balón" })
HomeTab:Button({ Title="✓ React cooldown corregido (0.3s)" })
HomeTab:Button({ Title="✓ Velocity ramping para evitar detección" })


local BallTab       = Window:Tab({ Title="Balon" })
local ballEnabled   = false
local ballSize      = 1
local ballTrans     = 0.4
local highlightEnabled = false
local highlightPart    = nil
local speedBoost    = false
local speedMult     = 2.0
local maxBallSpeed  = 400
local _lastBallSpd  = 0
local _kickDetected = false

BallTab:Section({ Title="Visuales del Balon" })
BallTab:Toggle({ Title="Control de Tamano", Desc="Activa control visual del balon",
    Callback=function(v) ballEnabled=v end })
BallTab:Slider({ Title="Tamano del Balon", Value={Min=1,Max=50,Default=1}, Step=1,
    Callback=function(v) ballSize=v end })
BallTab:Slider({ Title="Transparencia", Value={Min=0,Max=1,Default=0.4}, Step=0.1,
    Callback=function(v) ballTrans=v end })
BallTab:Toggle({ Title="Resaltado Visual", Desc="Muestra area del balon",
    Callback=function(state)
        highlightEnabled=state
        if state then
            highlightPart = Instance.new("Part"); highlightPart.Name = "TL_BallHL"
            highlightPart.Size = Vector3.new(9,0.1,9); highlightPart.Anchored = true
            highlightPart.BrickColor = BrickColor.new("Bright blue"); highlightPart.Transparency = 0.7
            highlightPart.CanCollide = false; highlightPart.Material = Enum.Material.Neon
            highlightPart.Parent = Workspace
        else
            if highlightPart then highlightPart:Destroy(); highlightPart=nil end
        end
    end })
BallTab:Section({ Title="Guardian CanCollide" })
BallTab:Button({ Title="Activar Guardian", Desc="Fuerza CanCollide = false",
    Callback=function()
        local b = findBall()
        if b then pcall(function() b.CanCollide=false end) end
        VxnityUI:Notify({Title="Guardian",Desc="CanCollide desactivado",Duration=2})
    end })
BallTab:Section({ Title="Velocidad del Balon" })
BallTab:Toggle({ Title="Aumento de Velocidad", Desc="Solo aplica al patear",
    Callback=function(v) speedBoost=v end })
BallTab:Slider({ Title="Multiplicador", Value={Min=1,Max=15,Default=2}, Step=1,
    Callback=function(v) speedMult=v end })
BallTab:Slider({ Title="Velocidad Maxima", Value={Min=100,Max=1500,Default=400}, Step=10,
    Callback=function(v) maxBallSpeed=v end })
BallTab:Section({ Title="Preajustes" })
BallTab:Button({ Title="Normal (x1)",  Callback=function() speedMult=1;  VxnityUI:Notify({Title="Velocidad",Desc="x1.0",Duration=1.5}) end })
BallTab:Button({ Title="Rapido (x3)", Callback=function() speedMult=3;  VxnityUI:Notify({Title="Velocidad",Desc="x3.0",Duration=1.5}) end })
BallTab:Button({ Title="Turbo (x5)",  Callback=function() speedMult=5;  VxnityUI:Notify({Title="Velocidad",Desc="x5.0",Duration=1.5}) end })
BallTab:Button({ Title="LOCURA (x10)",Callback=function() speedMult=10; VxnityUI:Notify({Title="Velocidad",Desc="x10.0",Duration=1.5}) end })

local ReachTab       = Window:Tab({ Title="Alcance" })
local reachEnabled   = P.reachEnabled
local reachDistance  = P.reachDistance
local reachMode      = P.reachMode or "Hybrid"
local function startReach()
    cleanConn("reach")
    local _char, _root, _hum, _ball, _limb = nil,nil,nil,nil,nil
    local _lastRig, _frameSkip = nil, 0
    setConn("reach", RunService.Heartbeat:Connect(function()  -- Heartbeat > RenderStepped para física
        local character = LocalPlayer.Character
        if not character then return end
        if character ~= _char then
            _char = character; _root = character:FindFirstChild("HumanoidRootPart")
            _hum  = character:FindFirstChild("Humanoid"); _limb = nil; _lastRig = nil
        end
        if not (_root and _hum) then return end
        _frameSkip = _frameSkip + 1
        if _frameSkip >= 2 then  -- cada 2 frames (más reactivo)
            _frameSkip = 0
            _ball = findBall()
            if _ball then _G._TLBall = _ball end
        end
        if not _ball or not _ball.Parent then return end
        local dx = _root.Position.X - _ball.Position.X
        local dy = _root.Position.Y - _ball.Position.Y
        local dz = _root.Position.Z - _ball.Position.Z
        if (dx*dx + dy*dy + dz*dz) > reachDistance*reachDistance then return end
        local rig = _hum.RigType
        if rig ~= _lastRig or not _limb or not _limb.Parent then
            _lastRig = rig
            if rig == Enum.HumanoidRigType.R6 then
                _limb = _char:FindFirstChild("Right Leg") or _char:FindFirstChild("Left Leg")
            else
                _limb = _char:FindFirstChild("RightLowerLeg") or _char:FindFirstChild("LeftLowerLeg")
            end
        end
        local partsToFire = {}
        if _limb then table.insert(partsToFire, _limb) end
        if rig == Enum.HumanoidRigType.R6 then
            for _, n in ipairs({"Right Leg","Left Leg"}) do
                local p = _char:FindFirstChild(n); if p and p ~= _limb then table.insert(partsToFire,p) end
            end
        else
            for _, n in ipairs({"RightLowerLeg","LeftLowerLeg","RightFoot","LeftFoot"}) do
                local p = _char:FindFirstChild(n); if p and p ~= _limb then table.insert(partsToFire,p) end
            end
        end
        if _root then table.insert(partsToFire, _root) end

        local useTouch = (reachMode == "firetouchinterest" or reachMode == "Hybrid") and _has_firetouchinterest
        local useCollide = (reachMode == "Physical Collision" or reachMode == "Hybrid")

        if useTouch then
            for _, part in ipairs(partsToFire) do
                pcall(function() firetouchinterest(part,_ball,0); firetouchinterest(part,_ball,1) end)
            end
        end

        if useCollide then
            pcall(function()
                -- Trae ligeramente el balón hacia el cuerpo para forzar detección de colisión del motor de Roblox
                for _, part in ipairs(partsToFire) do
                    if part and _ball and _ball.Parent then
                        local diff = part.Position - _ball.Position
                        local dist = diff.Magnitude
                        if dist < reachDistance and dist > 0.1 then
                            local nudgeDir = diff.Unit
                            _ball.CFrame = _ball.CFrame + nudgeDir * 0.05
                        end
                    end
                end
            end)
        end
    end))
end

_G._TLReachRestart = function() if reachEnabled then startReach() end end

ReachTab:Section({ Title="Alcance de Piernas" })
ReachTab:Toggle({ Title="Activar Alcance", Desc="Contacto automatico con el balon",
    Callback=function(v)
        reachEnabled=v; P.reachEnabled=v
        if v then startReach()
        else cleanConn("reach") end
    end })
ReachTab:Dropdown({ Title="Modo de Alcance", Options={"Hybrid", "firetouchinterest", "Physical Collision"}, Default=reachMode,
    Callback=function(opt) reachMode=opt; P.reachMode=opt; if reachEnabled then startReach() end end })
ReachTab:Slider({ Title="Distancia de Alcance", Value={Min=1,Max=25,Default=5}, Step=1,
    Desc="Rango de activacion",
    Callback=function(v) reachDistance=v; P.reachDistance=v end })
ReachTab:Section({ Title="Tamano Piernas R6" })
ReachTab:Input({ Title="Tamano R6", PlaceholderText="ej: 10",
    Callback=function(Value)
        local v = tonumber(Value) or 1
        local char = LocalPlayer.Character
        if char then
            for _, name in ipairs({"Right Leg","Left Leg"}) do
                local p = char:FindFirstChild(name)
                if p then pcall(function() p.Size=Vector3.new(v,2,v); p.CanCollide=false end) end
            end
        end
    end })
ReachTab:Section({ Title="Tamano Piernas R15" })
ReachTab:Input({ Title="Tamano R15", PlaceholderText="ej: 10",
    Callback=function(Value)
        local v = tonumber(Value) or 1
        local char = LocalPlayer.Character
        if char then
            for _, name in ipairs({"RightLowerLeg","LeftLowerLeg"}) do
                local p = char:FindFirstChild(name)
                if p then pcall(function() p.Size=Vector3.new(v,2,v); p.CanCollide=false end) end
            end
        end
    end })
ReachTab:Button({ Title="Restaurar Piernas", Desc="Tamano original",
    Callback=function()
        local char = LocalPlayer.Character
        if char then
            for _, name in ipairs({"Right Leg","Left Leg","RightLowerLeg","LeftLowerLeg"}) do
                local p = char:FindFirstChild(name)
                if p then pcall(function() p.Size=Vector3.new(1,2,1); p.Transparency=0; p.Massless=false; p.CanCollide=false end) end
            end
        end
        VxnityUI:Notify({Title="Restaurado",Desc="Piernas restauradas",Duration=2})
    end })

local ReactsTab       = Window:Tab({ Title="Reacts" })
local continuousReact = P.continuousReact
local continuousPower = P.continuousPower

local function applyReactInstant(power)
    local ball, hrp = getReactTargets()
    if not (ball and ball.Parent and hrp) then return end
    if not prepareBall(ball) then return end
    local aim      = getAimDirection(hrp)
    local redirect = P.counterReact and getIncomingRedirect(ball, hrp)
    local dir      = redirect or aim
    local targetPos = hrp.Position + dir * 0.15 + Vector3.new(0, 0.05, 0)

    pcall(function() ball.CFrame = CFrame.new(targetPos) end)
    local finalVel = dir * (power * ballSpeedMult)
    
    if P.instantVelocity then
        pcall(function() ball.AssemblyLinearVelocity = finalVel end)
    else
        local rampSteps = (power > 1e15) and 3 or 1
        applyVelocityRamped(ball, finalVel, rampSteps)
    end
    pcall(function() ball.AssemblyAngularVelocity = Vector3.new(0,0,0) end)
    flashBall()
end

-- Hook de React (más sigiloso con safeClosure)
local function enableReactHook()
    P.reactHookOn = true
    pcall(installCentralHook)
end

-- React continuo
if not _G._TLContinuousReactConn then
    _G._TLContinuousReactConn = RunService.Heartbeat:Connect(function()
        if not continuousReact or continuousPower <= 0 then return end
        local ball = _G._TLBall; local hrp = _G._TLHRP
        if not (ball and ball.Parent and hrp) then return end
        if not ball:IsA("BasePart") then return end
        local dist = (ball.Position - hrp.Position).Magnitude
        if dist > 30 then return end
        local coming = isBallComingToPlayer(ball, hrp, 25)
        if not coming and dist > 12 then return end
        if not prepareBall(ball) then return end
        local aim      = getAimDirection(hrp)
        local redirect = P.counterReact and getIncomingRedirect(ball,hrp)
        local dir      = redirect or aim
        local targetPos = hrp.Position + dir * 0.15 + Vector3.new(0,0.05,0)
        pcall(function() ball.CFrame = CFrame.new(targetPos) end)
        pcall(function() ball.AssemblyLinearVelocity = dir * (continuousPower * ballSpeedMult) end)
        pcall(function() ball.AssemblyAngularVelocity = Vector3.new(0,0,0) end)
    end)
end

local function applyPreset(power, _, extraOffset, extraVel, curve)
    currentReactPower = power; P.reactPower = power
    enableReactHook()
    local ball, hrp = getReactTargets()
    if not (ball and hrp) then return end
    if not prepareBall(ball) then return end
    local aim      = getAimDirection(hrp)
    local redirect = P.counterReact and getIncomingRedirect(ball,hrp)
    local baseDir  = redirect or aim
    local offset   = extraOffset or 0.15
    local finalDir = extraVel and (baseDir + Vector3.new(0,extraVel,0)).Unit or baseDir
    pcall(function() ball.CFrame = CFrame.new(hrp.Position + baseDir*offset + Vector3.new(0,0.05,0)) end)
    local finalVel = finalDir * (power * ballSpeedMult)
    if P.instantVelocity then
        pcall(function() ball.AssemblyLinearVelocity = finalVel end)
    else
        applyVelocityRamped(ball, finalVel, 2)
    end
    if curve then pcall(function() ball.AssemblyAngularVelocity = Vector3.new(0,curve*50,0) end)
    else pcall(function() ball.AssemblyAngularVelocity = Vector3.new(0,0,0) end) end
    flashBall()
end

local function applyShotCurve(power, upForce, forwardForce, curveForce)
    currentReactPower = power; P.reactPower = power
    enableReactHook()
    local ball, hrp = getReactTargets()
    if not (ball and hrp) then return end
    if not prepareBall(ball) then return end
    local aim = getAimDirection(hrp)
    local vel = (aim*(forwardForce or power) + Vector3.new(0,upForce or 0,0)) * ballSpeedMult
    pcall(function() ball.CFrame = CFrame.new(hrp.Position + aim*0.15 + Vector3.new(0,0.1,0)) end)
    if P.instantVelocity then
        pcall(function() ball.AssemblyLinearVelocity = vel end)
    else
        applyVelocityRamped(ball, vel, 2)
    end
    pcall(function() ball.AssemblyAngularVelocity = Vector3.new(0,(curveForce or 0)*50,0) end)
    flashBall()
end

ReactsTab:Section({ Title="Sistema de React Potencia" })
ReactsTab:Button({ Title="VELOCIDAD ULTRA",    Desc="Balon a velocidad maxima!",  Callback=function() currentReactPower=5e18;  P.reactPower=currentReactPower; enableReactHook(); applyReactInstant(currentReactPower); VxnityUI:Notify({Title="ULTRA",  Desc="Velocidad maxima!",  Duration=2}) end })
ReactsTab:Button({ Title="MEGA POTENCIA",      Desc="Potencia extrema!",          Callback=function() currentReactPower=1e22;  P.reactPower=currentReactPower; enableReactHook(); applyReactInstant(currentReactPower); VxnityUI:Notify({Title="MEGA",   Desc="Potencia extrema!",  Duration=2}) end })
ReactsTab:Button({ Title="VELOCIDAD HYPER",    Desc="Hyper velocidad!",           Callback=function() currentReactPower=2e22;  P.reactPower=currentReactPower; enableReactHook(); applyReactInstant(currentReactPower); VxnityUI:Notify({Title="HYPER",  Desc="Hyper velocidad!",   Duration=2}) end })
ReactsTab:Button({ Title="PATADA DEFINITIVA",                                     Callback=function() currentReactPower=8e20;  P.reactPower=currentReactPower; enableReactHook(); applyReactInstant(currentReactPower); VxnityUI:Notify({Title="DEFI",   Desc="Activada!",          Duration=2}) end })
ReactsTab:Button({ Title="POTENCIA MAXIMA",                                       Callback=function() currentReactPower=1e25;  P.reactPower=currentReactPower; enableReactHook(); applyReactInstant(currentReactPower); VxnityUI:Notify({Title="MAXIMA", Desc="Absoluta!",          Duration=2}) end })

ReactsTab:Section({ Title="React Continuo" })
ReactsTab:Toggle({ Title="React Continuo ACTIVO", Desc="React con prediccion",
    PersistKey="continuousReact",
    Callback=function(state)
        continuousReact=state; P.continuousReact=state
        if state then enableReactHook(); VxnityUI:Notify({Title="CONTINUO",Desc="Activado!",Duration=2})
        else VxnityUI:Notify({Title="CONTINUO",Desc="Desactivado",Duration=2}) end
    end })
ReactsTab:Slider({ Title="Potencia Continua", Value={Min=1,Max=30,Default=22}, Step=1,
    Callback=function(val) continuousPower=10^val; P.continuousPower=10^val end })

ReactsTab:Section({ Title="Potencia Custom" })
ReactsTab:Slider({ Title="Potencia Base", Value={Min=18,Max=30,Default=22}, Step=1,
    Callback=function(val) currentReactPower=10^val; P.reactPower=10^val end })
ReactsTab:Slider({ Title="Multiplicador Velocidad", Value={Min=1,Max=50,Default=1}, Step=1,
    Callback=function(val) ballSpeedMult=val; P.ballSpeedMult=val end })

ReactsTab:Section({ Title="Preajustes de Accion" })
ReactsTab:Button({ Title="HYPER SNAP",   Desc="Snap ultra rapido!",    Callback=function() applyPreset(3e20,nil,0.2,nil,1);   VxnityUI:Notify({Title="HYPER SNAP",Desc="Snap!",  Duration=2}) end })
ReactsTab:Button({ Title="MEGA LOCK",    Desc="Bloqueo pesado!",       Callback=function() applyPreset(5e22,nil,0);           VxnityUI:Notify({Title="MEGA LOCK", Desc="Lock!",  Duration=2}) end })
ReactsTab:Button({ Title="ULTRA PIVOT",  Desc="Pivote!",               Callback=function() applyPreset(4e22,nil,0.15,nil,2); VxnityUI:Notify({Title="PIVOT",     Desc="Activo!",Duration=2}) end })
ReactsTab:Button({ Title="KENYAH MAX",   Desc="Prediccion!",           Callback=function() applyPreset(6e23,nil,0.15,nil,1.5);VxnityUI:Notify({Title="KENYAH",    Desc="Activo!",Duration=2}) end })
ReactsTab:Button({ Title="AERO MAX",     Desc="Aereo!",                Callback=function() applyPreset(5e22,nil,0.18,0.08,0.8);VxnityUI:Notify({Title="AERO",    Desc="Activo!",Duration=2}) end })

ReactsTab:Section({ Title="Shot Curves / Chips" })
ReactsTab:Button({ Title="LOB (Tiro Alto)",    Desc="Arco alto",       Callback=function() applyShotCurve(2e22,80000,30000,0);   VxnityUI:Notify({Title="LOB",   Desc="Arco!",    Duration=2}) end })
ReactsTab:Button({ Title="CHIP (Tiro Corto)",  Desc="Rapido arriba",   Callback=function() applyShotCurve(3e22,120000,15000,0);  VxnityUI:Notify({Title="CHIP",  Desc="Chip!",    Duration=2}) end })
ReactsTab:Button({ Title="CURVE (Tiro Curvo)", Desc="Efecto lateral",  Callback=function() applyShotCurve(5e22,20000,40000,3);   VxnityUI:Notify({Title="CURVE", Desc="Efecto!",  Duration=2}) end })
ReactsTab:Button({ Title="POWER SHOT",         Desc="Maxima potencia", Callback=function() applyShotCurve(1e25,5000,80000,0);    VxnityUI:Notify({Title="POWER", Desc="Disparo!", Duration=2}) end })
ReactsTab:Button({ Title="CROSS (Centro)",     Desc="Centro ancho",    Callback=function() applyShotCurve(4e22,60000,25000,2);   VxnityUI:Notify({Title="CROSS", Desc="Centro!",  Duration=2}) end })

-- Touch-react
if not _G._TLTouchReactConn then
    _G._TLTouchReactConn = {}
    local function setupTouchReact()
        for _, conn in pairs(_G._TLTouchReactConn) do pcall(function() conn:Disconnect() end) end
        _G._TLTouchReactConn = {}
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local c = hrp.Touched:Connect(function(hit)
                local ball = _G._TLBall
                if ball and hit == ball and P.autoReact and currentReactPower > 0 then
                    applyReactInstant(currentReactPower)
                end
            end)
            table.insert(_G._TLTouchReactConn, c)
        end
        char.ChildAdded:Connect(function(child)
            if child.Name == "HumanoidRootPart" then
                local c = child.Touched:Connect(function(hit)
                    local ball = _G._TLBall
                    if ball and hit == ball and P.autoReact and currentReactPower > 0 then
                        applyReactInstant(currentReactPower)
                    end
                end)
                table.insert(_G._TLTouchReactConn, c)
            end
        end)
    end
    setupTouchReact()
    LocalPlayer.CharacterAdded:Connect(function() _tdelay(0.1, setupTouchReact) end)
end

ReactsTab:Section({ Title="React Automatico" })
local autoReactRange = P.autoReactRange or 8
local autoReactCD = 0
local reactCooldownVal = P.reactCooldownVal or 0.1
local autoReactMode = P.autoReactMode or "Always in Range"

ReactsTab:Toggle({ Title="React Automatico", Desc="Reacciona cuando el balon esta cerca",
    PersistKey="autoReact",
    Callback=function(state)
        P.autoReact=state
        if state then VxnityUI:Notify({Title="AUTO REACT",Desc="Activado!",Duration=2})
        else VxnityUI:Notify({Title="AUTO REACT",Desc="Desactivado",Duration=2}) end
    end })
ReactsTab:Dropdown({ Title="Modo Auto React", Options={"Always in Range", "Coming Only"}, Default=autoReactMode,
    Callback=function(opt) autoReactMode=opt; P.autoReactMode=opt end })
ReactsTab:Slider({ Title="Rango Auto React", Value={Min=3,Max=25,Default=8}, Step=1,
    Desc="Distancia maxima",
    Callback=function(v) autoReactRange=v; P.autoReactRange=v end })
ReactsTab:Slider({ Title="Delay / Cooldown React", Value={Min=0,Max=1,Default=0.1}, Step=0.05,
    Desc="Segundos de espera (0 = sin delay)",
    Callback=function(v) reactCooldownVal=v; P.reactCooldownVal=v end })
ReactsTab:Toggle({ Title="Velocidad Instantanea", Desc="Fuerza velocidad instantanea (0 delay)",
    PersistKey="instantVelocity",
    Callback=function(state) P.instantVelocity=state end })

ReactsTab:Section({ Title="Direccion del React" })
ReactsTab:Toggle({ Title="Direccion: Camara", Desc="Apunta donde mira la camara",
    Callback=function(state) if state then P.reactDirection="camera" end end })
ReactsTab:Toggle({ Title="Direccion: Mouse", Desc="Apunta donde apuntas",
    Callback=function(state) if state then P.reactDirection="mouse" end end })

ReactsTab:Section({ Title="React Counter" })
ReactsTab:Toggle({ Title="React Counter", Desc="Redirige balones entrantes", PersistKey="counterReact",
    Callback=function(state)
        P.counterReact=state
        if state then VxnityUI:Notify({Title="COUNTER",Desc="Activado!",Duration=2})
        else VxnityUI:Notify({Title="COUNTER",Desc="Desactivado",Duration=2}) end
    end })
ReactsTab:Slider({ Title="Potencia Counter", Value={Min=18,Max=30,Default=22}, Step=1,
    Callback=function(v) P.counterPower=10^v end })

ReactsTab:Section({ Title="React Arquero (GK)" })
ReactsTab:Button({ Title="Activar GK Hook", Desc="Hook para Saves/Headers/Kicks",
    Callback=function()
        if not (_has_getrawmetatable and _has_getnamecallmethod) then
            VxnityUI:Notify({Title="Error",Desc="Metatable no disponible en este executor",Duration=3}); return
        end
        local ok, meta = pcall(getrawmetatable, game)
        if not ok or not meta then
            VxnityUI:Notify({Title="Error",Desc="No se pudo acceder al metatable",Duration=3}); return
        end
        local oldNC = rawget(meta, "__namecall")
        if not oldNC then
            VxnityUI:Notify({Title="Error",Desc="__namecall no encontrado",Duration=3}); return
        end
        local gkMap = {SaveRA=true,SaveLA=true,SaveRL=true,SaveLL=true,SaveT=true,Tackle=true,Header=true,Kick=true}
        trySetReadonly(meta, false)
        -- FIX: reemplazado hum.LLCL (inexistente) por lógica correcta de GK
        meta.__namecall = safeClosure(function(self, ...)
            local m = _has_getnamecallmethod and getnamecallmethod() or ""
            if m == "FireServer" then
                local selfName = tostring(self.Name or "")
                if gkMap[selfName] then
                    -- Aplicar react al recibir una acción de GK
                    local ball, hrp = getReactTargets()
                    if ball and hrp then
                        pcall(function()
                            prepareBall(ball)
                            local aim = getAimDirection(hrp)
                            ball.CFrame = CFrame.new(hrp.Position + aim * 0.15 + Vector3.new(0,0.05,0))
                            applyVelocityRamped(ball, aim * (currentReactPower * ballSpeedMult), 2)
                        end)
                    end
                end
            end
            return oldNC(self, ...)
        end)
        trySetReadonly(meta, true)
        VxnityUI:Notify({Title="Arquero GK",Desc="Hook activado!",Duration=2})
    end })

local ImanTab      = Window:Tab({ Title="Iman" })
local toggleEnabled= P.helperEnabled
local helperActive = P.helperActive
local magnetMode   = P.magnetMode
local predictMode  = P.predictMode
local spaceLock    = P.spaceLock
local followBall   = false
local followEnabled = false
local lockedPos     = nil
local lastHRPPos    = nil
local lastTick      = tick()

local CONFIG = {
    FOLLOW_DISTANCE = 0.08, FOLLOW_SPEED  = 30000, DEAD_ZONE   = 0.03,
    MAX_DISTANCE    = 0.2,  STRONG_PULL   = 50000, SOFT_PULL   = 35000,
    MAGNET_PULL     = 80000, PREDICT_OFFSET = 0.04,
    VERTICAL_OFFSET = -0.05, LOCK_RADIUS  = 0.01,
}

local function getOrCreateAtt(ball)
    local att = ball:FindFirstChild("_tlAtt")
    if not att then att = Instance.new("Attachment"); att.Name = "_tlAtt"; att.Parent = ball end
    return att
end

local function getOrCreateLV(ball, att)
    local lv = ball:FindFirstChild("_tlLV")
    if not lv then
        lv = Instance.new("LinearVelocity"); lv.Name = "_tlLV"; lv.Attachment0 = att
        lv.MaxForce = math.huge; lv.RelativeTo = Enum.ActuatorRelativeTo.World
        lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        lv.VectorVelocity = Vector3.new(0,0,0); lv.Parent = ball
    end
    return lv
end

local function cleanupBall(ball)
    if not ball then return end
    pcall(function()
        local lv = ball:FindFirstChild("_tlLV")
        if lv then lv.VectorVelocity = Vector3.new(0,0,0) end
    end)
end

local function getPredictedTarget(hrp)
    local now = tick(); local dt = now - lastTick; lastTick = now
    local currentPos = hrp.Position
    if lastHRPPos and dt > 0 and dt < 0.1 then
        local velocity = (currentPos - lastHRPPos) / dt; lastHRPPos = currentPos
        return currentPos + velocity * CONFIG.PREDICT_OFFSET + Vector3.new(0,CONFIG.VERTICAL_OFFSET,0)
    end
    lastHRPPos = currentPos
    return currentPos + hrp.CFrame.LookVector * CONFIG.FOLLOW_DISTANCE + Vector3.new(0,CONFIG.VERTICAL_OFFSET,0)
end

ImanTab:Section({ Title="Sistema Iman / Helper" })
ImanTab:Toggle({ Title="Activar Helper", Desc="Control del balon", PersistKey="helperEnabled",
    Callback=function(state) toggleEnabled=state; P.helperEnabled=state; if not state then helperActive=false; P.helperActive=false end end })
ImanTab:Toggle({ Title="Helper Activo", Desc="Balon adherido", PersistKey="helperActive",
    Callback=function(state) helperActive=state; P.helperActive=state end })
ImanTab:Toggle({ Title="Modo Iman",     Desc="Balon pegado",     PersistKey="magnetMode",
    Callback=function(state) magnetMode=state; P.magnetMode=state end })
ImanTab:Toggle({ Title="Modo Prediccion", Desc="Anticipa movimiento", PersistKey="predictMode",
    Callback=function(state) predictMode=state; P.predictMode=state end })
ImanTab:Toggle({ Title="Bloqueo Espacial", Desc="Congela el balon", PersistKey="spaceLock",
    Callback=function(state) spaceLock=state; P.spaceLock=state end })
ImanTab:Section({ Title="Ajuste Fino" })
ImanTab:Slider({ Title="Zona Muerta", Value={Min=0,Max=10,Default=0}, Step=1,
    Callback=function(val) CONFIG.DEAD_ZONE=val end })
ImanTab:Slider({ Title="Offset Vertical", Value={Min=-5,Max=5,Default=0}, Step=1,
    Callback=function(val) CONFIG.VERTICAL_OFFSET=val end })
ImanTab:Section({ Title="Seguimiento Auto" })
ImanTab:Toggle({ Title="Seguimiento (tecla B)", Desc="Mover hacia el balon",
    Callback=function(state) followEnabled=state; if not state then followBall=false end end })

UserInputService.InputBegan:Connect(function(input, gp)
    if input.KeyCode == Enum.KeyCode.B and not gp and followEnabled then followBall = not followBall end
end)

if not _G._TLHelperConn then
    _G._TLHelperConn = RunService.Heartbeat:Connect(function()
        if not (helperActive and toggleEnabled) then
            local ball = _G._TLBall; if ball then cleanupBall(ball) end; lockedPos=nil; return
        end
        local ball = _G._TLBall; local hrp = _G._TLHRP
        local char = LocalPlayer.Character; local hum = char and char:FindFirstChild("Humanoid")
        if not (ball and hrp and hum) then return end
        if hum.Health <= 0 then return end
        if not ball:IsA("BasePart") then return end
        if not prepareBall(ball) then return end
        local att = getOrCreateAtt(ball); local lv = getOrCreateLV(ball,att)
        local ballPos = ball.Position; local hrpPos = hrp.Position
        if spaceLock then
            if not lockedPos then lockedPos = ballPos end
            local toLock = lockedPos - ballPos
            if toLock.Magnitude > CONFIG.LOCK_RADIUS then
                lv.VectorVelocity = toLock.Unit*CONFIG.MAGNET_PULL
                pcall(function() ball.AssemblyLinearVelocity = toLock.Unit*CONFIG.MAGNET_PULL end)
            else
                lv.VectorVelocity = Vector3.new(0,0,0)
                pcall(function() ball.AssemblyLinearVelocity = Vector3.new(0,0,0) end)
            end
            return
        else lockedPos = nil end
        local targetPos = predictMode and getPredictedTarget(hrp)
            or (hrpPos + hrp.CFrame.LookVector*CONFIG.FOLLOW_DISTANCE + Vector3.new(0,CONFIG.VERTICAL_OFFSET,0))
        local toTarget = targetPos - ballPos; local toTargetDist = toTarget.Magnitude
        if magnetMode then
            if toTargetDist > 0.04 then
                local speed = math.clamp(toTargetDist*1200, 80, CONFIG.MAGNET_PULL)
                lv.VectorVelocity = toTarget.Unit*speed
                pcall(function() ball.AssemblyLinearVelocity = toTarget.Unit*speed end)
            else
                pcall(function() ball.CFrame = CFrame.new(targetPos) end)
                lv.VectorVelocity = Vector3.new(0,0,0)
                pcall(function() ball.AssemblyLinearVelocity = Vector3.new(0,0,0) end)
            end
            return
        end
        local dist = (ballPos - hrpPos).Magnitude
        if dist > CONFIG.MAX_DISTANCE then
            local dir = (targetPos-ballPos).Unit
            lv.VectorVelocity = dir*CONFIG.STRONG_PULL
            pcall(function() ball.AssemblyLinearVelocity = dir*CONFIG.STRONG_PULL end)
        elseif dist > CONFIG.DEAD_ZONE then
            local speed = math.clamp(toTargetDist*CONFIG.SOFT_PULL, 20, CONFIG.FOLLOW_SPEED)
            lv.VectorVelocity = toTarget.Unit*speed
        else lv.VectorVelocity = Vector3.new(0,0,0) end
    end)
end

if not _G._TLFollowConn then
    _G._TLFollowConn = RunService.Heartbeat:Connect(function()
        if not (followBall and followEnabled) then return end
        local ball = _G._TLBall; local char = LocalPlayer.Character
        local hum = char and char:FindFirstChild("Humanoid")
        if hum and ball then hum:MoveTo(ball.Position) end
    end)
end

local DribbleTab      = Window:Tab({ Title="Dribble" })
local dribbleEnabled  = false
local dribbleIntensity = "Alto"
local dribbleActivation = "Click"
local dribbleActive   = false

local DRIBBLE_CONFIG = {
    Bajo  = {strength=30000,  deadzone=0.03,  offset=0.08},
    Medio = {strength=60000,  deadzone=0.015, offset=0.05},
    Alto  = {strength=100000, deadzone=0.008, offset=0.03},
}

local function applyDribbleAssist()
    if not dribbleEnabled then return end
    local ball = _G._TLBall; local hrp = _G._TLHRP
    if not (ball and hrp) then return end
    local cfg = DRIBBLE_CONFIG[dribbleIntensity] or DRIBBLE_CONFIG.Alto
    if not prepareBall(ball) then return end
    local targetPos = hrp.Position + hrp.CFrame.LookVector*cfg.offset + Vector3.new(0,0.02,0)
    local diff = targetPos - ball.Position; local dist = diff.Magnitude
    pcall(function()
        if dist > cfg.deadzone then
            local speed = math.clamp(dist*cfg.strength, 800, cfg.strength)
            ball.AssemblyLinearVelocity = diff.Unit*speed + hrp.CFrame.LookVector*80
        else
            ball.AssemblyLinearVelocity = ball.AssemblyLinearVelocity*0.85 + hrp.CFrame.LookVector*60
        end
        ball.AssemblyAngularVelocity = Vector3.new(50,0,50)
    end)
end

DribbleTab:Section({ Title="Asistente de Dribble" })
DribbleTab:Toggle({ Title="Activar Dribble", Desc="Asistencia rapida",
    Callback=function(state) dribbleEnabled=state end })
DribbleTab:Slider({ Title="Intensidad", Value={Min=1,Max=3,Default=3}, Step=1,
    Desc="1=Bajo, 2=Medio, 3=Alto",
    Callback=function(val)
        local niveles = {"Bajo","Medio","Alto"}; dribbleIntensity = niveles[math.floor(val)] or "Alto"
    end })
DribbleTab:Dropdown({ Title="Activacion", Options={"Click","Hold"}, Default="Click",
    Callback=function(opt) dribbleActivation=opt end })
DribbleTab:Button({ Title="Probar Dribble", Desc="Prueba la asistencia",
    Callback=function()
        if dribbleEnabled then applyDribbleAssist(); VxnityUI:Notify({Title="Dribble",Desc="Intensidad: "..dribbleIntensity,Duration=1}) end
    end })

if not _G._TLDribbleConn then
    _G._TLDribbleConn = RunService.Heartbeat:Connect(function()
        if dribbleEnabled and dribbleActive then applyDribbleAssist() end
    end)
end
UserInputService.InputBegan:Connect(function(input)
    if not dribbleEnabled then return end
    if dribbleActivation == "Click" then
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dribbleActive = true; applyDribbleAssist()
            _tdelay(0.05, function() dribbleActive = false end)
        end
    elseif dribbleActivation == "Hold" then
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dribbleActive = true
        end
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if dribbleActivation == "Hold" then
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dribbleActive = false
        end
    end
end)

local MiscTab = Window:Tab({ Title="Misc" })

-- WalkSpeed
local wsVal = P.walkSpeed or 16
MiscTab:Section({ Title="Jugador" })
MiscTab:Toggle({ Title="WalkSpeed Custom", Desc="Activa velocidad de movimiento custom",
    Callback=function(state)
        local char = LocalPlayer.Character
        local hum  = char and char:FindFirstChild("Humanoid")
        if hum then
            if state then hum.WalkSpeed = wsVal
            else hum.WalkSpeed = 16 end
        end
    end })
MiscTab:Slider({ Title="WalkSpeed", Value={Min=16,Max=200,Default=16}, Step=1,
    Callback=function(v)
        wsVal = v; P.walkSpeed = v
        local char = LocalPlayer.Character
        local hum  = char and char:FindFirstChild("Humanoid")
        if hum then pcall(function() hum.WalkSpeed = v end) end
    end })

-- JumpPower
local jpVal = P.jumpPower or 50
MiscTab:Slider({ Title="JumpPower", Value={Min=50,Max=400,Default=50}, Step=5,
    Callback=function(v)
        jpVal = v; P.jumpPower = v
        local char = LocalPlayer.Character
        local hum  = char and char:FindFirstChild("Humanoid")
        if hum then pcall(function() hum.JumpPower = v end) end
    end })

-- Anti-Ragdoll
local antiRagdollConn = nil
MiscTab:Section({ Title="Anti-Ragdoll" })
MiscTab:Toggle({ Title="Anti-Ragdoll", Desc="Evita que el personaje se caiga", PersistKey="antiRagdoll",
    Callback=function(state)
        P.antiRagdoll = state
        if state then
            antiRagdollConn = RunService.Heartbeat:Connect(function()
                local char = LocalPlayer.Character; if not char then return end
                local hum  = char:FindFirstChild("Humanoid"); if not hum then return end
                pcall(function()
                    if hum:GetState() == Enum.HumanoidStateType.Ragdoll or
                       hum:GetState() == Enum.HumanoidStateType.FallingDown then
                        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    end
                end)
                -- Eliminar joints de ragdoll si aparecen
                for _, v in ipairs(char:GetDescendants()) do
                    if v:IsA("BallSocketConstraint") or v:IsA("HingeConstraint") then
                        if v.Name:find("Ragdoll") or v.Name:find("ragdoll") then
                            pcall(function() v:Destroy() end)
                        end
                    end
                end
            end)
            VxnityUI:Notify({Title="Anti-Ragdoll",Desc="Activado!",Duration=2})
        else
            if antiRagdollConn then antiRagdollConn:Disconnect(); antiRagdollConn=nil end
            VxnityUI:Notify({Title="Anti-Ragdoll",Desc="Desactivado",Duration=2})
        end
    end })

-- Noclip
local noclipConn = nil
MiscTab:Section({ Title="Noclip" })
MiscTab:Toggle({ Title="Noclip", Desc="Atraviesa paredes",
    Callback=function(state)
        if state then
            noclipConn = RunService.Stepped:Connect(function()
                local char = LocalPlayer.Character; if not char then return end
                for _, p in ipairs(char:GetDescendants()) do
                    if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                        pcall(function() p.CanCollide = false end)
                    end
                end
            end)
            VxnityUI:Notify({Title="Noclip",Desc="Activado!",Duration=2})
        else
            if noclipConn then noclipConn:Disconnect(); noclipConn=nil end
            VxnityUI:Notify({Title="Noclip",Desc="Desactivado",Duration=2})
        end
    end })

local ESPTab = Window:Tab({ Title="ESP" })
local espBox       = nil
local espHighlight = nil
local espConn      = nil

local function setupBallESP(enable)
    if not enable then
        if espConn then espConn:Disconnect(); espConn=nil end
        if espBox  then pcall(function() espBox:Destroy() end); espBox=nil end
        if espHighlight then pcall(function() espHighlight:Destroy() end); espHighlight=nil end
        return
    end
    espConn = RunService.Heartbeat:Connect(function()
        local ball = _G._TLBall
        if not (ball and ball.Parent) then return end
        -- Usar SelectionBox para ESP visual
        if not espBox or not espBox.Parent then
            pcall(function() if espBox then espBox:Destroy() end end)
            espBox = Instance.new("SelectionBox")
            espBox.Color3    = ACCENT
            espBox.LineThickness = 0.04
            espBox.SurfaceTransparency = 0.7
            espBox.SurfaceColor3 = ACCENT
            espBox.Parent    = Workspace.CurrentCamera
        end
        pcall(function() espBox.Adornee = ball end)
        -- Highlight adicional
        if not espHighlight or not espHighlight.Parent then
            pcall(function() if espHighlight then espHighlight:Destroy() end end)
            espHighlight = Instance.new("SelectionBox")
            espHighlight.Color3    = ACCENT3
            espHighlight.LineThickness = 0.02
            espHighlight.SurfaceTransparency = 0.9
            espHighlight.SurfaceColor3 = ACCENT3
            espHighlight.Parent  = Workspace.CurrentCamera
        end
        pcall(function() espHighlight.Adornee = ball end)
    end)
end

ESPTab:Section({ Title="ESP del Balon" })
ESPTab:Toggle({ Title="Ball ESP", Desc="Resalta el balon a traves de paredes", PersistKey="espEnabled",
    Callback=function(state)
        P.espEnabled = state
        setupBallESP(state)
        if state then VxnityUI:Notify({Title="Ball ESP",Desc="Activado!",Duration=2})
        else VxnityUI:Notify({Title="Ball ESP",Desc="Desactivado",Duration=2}) end
    end })
ESPTab:Button({ Title="Encontrar Balon", Desc="Busca y marca el balon ahora",
    Callback=function()
        local b = findBall()
        if b then
            VxnityUI:Notify({Title="Balon",Desc="Encontrado: "..b.Name,Duration=3})
        else
            VxnityUI:Notify({Title="Balon",Desc="No encontrado en el mapa",Duration=3})
        end
    end })
ESPTab:Button({ Title="Info del Balon", Desc="Posicion y velocidad actual",
    Callback=function()
        local b = _G._TLBall
        if b and b.Parent then
            local pos = b.Position; local vel = b.AssemblyLinearVelocity
            VxnityUI:Notify({
                Title="Balon Info",
                Desc=string.format("Vel: %.0f | Pos: %.0f,%.0f,%.0f", vel.Magnitude, pos.X,pos.Y,pos.Z),
                Duration=4
            })
        else
            VxnityUI:Notify({Title="Balon",Desc="Balon no disponible",Duration=2})
        end
    end })

local PerfTab = Window:Tab({ Title="Perf" })
PerfTab:Section({ Title="Red" })
PerfTab:Toggle({ Title="Optimizar Red", Desc="Reduce latencia", PersistKey="perfNet",
    Callback=function(state)
        if state then pcall(function() settings().Network.Physics=30 end)
        else pcall(function() settings().Network.Physics=60 end) end
    end })
PerfTab:Section({ Title="CPU" })
PerfTab:Toggle({ Title="Optimizar Fisica", Desc="Reduce calculos", PersistKey="perfPhysics",
    Callback=function(state)
        if state then pcall(function() settings().Physics.PhysicsEngine="Voxel" end)
        else pcall(function() settings().Physics.PhysicsEngine="EnvironmentalPhysics" end) end
    end })
PerfTab:Section({ Title="GPU" })
PerfTab:Toggle({ Title="Reducir Efectos", Desc="Minimizar particulas", PersistKey="perfRed",
    Callback=function(state)
        if state then pcall(function() settings().Rendering.EffectsQuality=0 end)
        else pcall(function() settings().Rendering.EffectsQuality=10 end) end
    end })
PerfTab:Toggle({ Title="Reducir Sombras", Desc="Sombras desactivadas", PersistKey="perfShadow",
    Callback=function(state)
        if state then pcall(function() settings().Rendering.ShadowQuality=0 end)
        else pcall(function() settings().Rendering.ShadowQuality=10 end) end
    end })

local ConfigTab = Window:Tab({ Title="Config" })
ConfigTab:Section({ Title="Guardar / Cargar" })
ConfigTab:Button({ Title="Guardar Config", Desc="Guarda todos los ajustes actuales",
    Callback=function()
        _G._TLConfig = {}
        for k,v in pairs(P) do _G._TLConfig[k]=v end
        VxnityUI:Notify({Title="Config",Desc="Guardado exitosamente",Duration=2})
    end })
ConfigTab:Button({ Title="Cargar Config", Desc="Restaura la ultima config guardada",
    Callback=function()
        if _G._TLConfig then
            for k,v in pairs(_G._TLConfig) do P[k]=v end
            VxnityUI:Notify({Title="Config",Desc="Configuracion cargada",Duration=2})
        else VxnityUI:Notify({Title="Config",Desc="No hay config guardada",Duration=2}) end
    end })
ConfigTab:Button({ Title="Config por Defecto", Desc="Restaura valores originales",
    Callback=function()
        P.reachEnabled=false; P.reachDistance=5; P.reactPower=0; P.ballSpeedMult=1.0
        P.helperEnabled=false; P.magnetMode=true; P.predictMode=true; P.spaceLock=false
        P.continuousReact=false; P.continuousPower=1e22; P.autoReact=false; P.autoReactRange=8
        P.counterReact=false; P.counterPower=1e22; P.reactDirection="camera"
        P.walkSpeed=16; P.jumpPower=50; P.antiRagdoll=false; P.espEnabled=false
        VxnityUI:Notify({Title="Config",Desc="Valores originales restaurados",Duration=2})
    end })


if not _G._TLMainLoop then
    _G._TLMainLoop = RunService.Heartbeat:Connect(function()
        pcall(function()
            -- Actualizar HRP
            local char = LocalPlayer.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then _G._TLHRP = hrp end
            end

            local ball = _G._TLBall
            if not ball or not ball.Parent then
                local b = findBall()
                if b then _G._TLBall = b end
                return
            end


            if ballEnabled then
                pcall(function() ball.Size = Vector3.new(ballSize,ballSize,ballSize) end)
                pcall(function() ball.Transparency = ballTrans end)
            end
            pcall(function() ball.CanCollide = false end)

            if highlightEnabled and highlightPart and highlightPart.Parent then
                highlightPart.Position = ball.Position - Vector3.new(0,1,0)
            end

            if speedBoost then
                local vel = ball.AssemblyLinearVelocity
                local curSpeed = vel.Magnitude
                if _lastBallSpd < 10 and curSpeed > 40 then _kickDetected = true end
                if _kickDetected and curSpeed > 1 then
                    local newSpeed = math.min(curSpeed * speedMult, maxBallSpeed)
                    if math.abs(newSpeed - curSpeed) > 1 then
                        pcall(function() ball.AssemblyLinearVelocity = vel.Unit * newSpeed end)
                    end
                end
                if curSpeed < 2 then _kickDetected = false end
                _lastBallSpd = curSpeed
            end

            if P.autoReact and currentReactPower > 0 then
                local now = tick()
                if now > autoReactCD then
                    local hrp = _G._TLHRP
                    if hrp then
                        local dist = (ball.Position - hrp.Position).Magnitude
                        local shouldReact = false
                        if autoReactMode == "Always in Range" then
                            shouldReact = (dist < autoReactRange)
                        else -- "Coming Only"
                            local coming, fDist = isBallComingToPlayer(ball, hrp, autoReactRange)
                            shouldReact = coming or (dist < 3)
                        end
                        
                        if shouldReact then
                            applyReactInstant(currentReactPower)
                            autoReactCD = now + reactCooldownVal
                        end
                    end
                end
            end
        end)
    end)
end
LocalPlayer.CharacterAdded:Connect(function(char)
    _G._TLHRP = char:WaitForChild("HumanoidRootPart", 3)
    _tdelay(0.1, function()
        local b = findBall()
        if b then _G._TLBall = b end
        if P.reachEnabled and _G._TLReachRestart then
            _tdelay(0.05, _G._TLReachRestart)
        end
        -- Aplicar WalkSpeed/JumpPower al respawn
        local hum = char:FindFirstChild("Humanoid")
        if hum then
            pcall(function() hum.WalkSpeed = P.walkSpeed or 16 end)
            pcall(function() hum.JumpPower  = P.jumpPower  or 50 end)
        end
    end)
end)

pcall(function()
    local a = Workspace:FindFirstChild("FE") and Workspace.FE:FindFirstChild("Actions")
    if not a then return end
    for _, b in pairs(a:GetChildren()) do
        if b.Name == " " then pcall(function() b:Destroy() end) end
    end
    if a:FindFirstChild("KeepYourHeadUp_") then
        a.KeepYourHeadUp_:Destroy()
    end
    local r = Instance.new("RemoteEvent"); r.Name="KeepYourHeadUp_"; r.Parent=a
end)
pcall(function()
    local ch = LocalPlayer.Character
    if ch then
        for _, b in pairs(ch:GetChildren()) do
            if b.Name == " " then pcall(function() b:Destroy() end) end
        end
    end
end)

if P.perfNet     then pcall(function() settings().Network.Physics=30 end) end
if P.perfPhysics then pcall(function() settings().Physics.PhysicsEngine="Voxel" end) end
if P.perfRed     then pcall(function() settings().Rendering.EffectsQuality=0 end) end
if P.perfShadow  then pcall(function() settings().Rendering.ShadowQuality=0 end) end
if P.espEnabled  then setupBallESP(true) end

VxnityUI:Notify({ Title="Touchline v1", Desc="la cagada esta porfin ejecuta la ui", Duration=4 })
