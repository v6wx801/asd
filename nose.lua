local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")
local Lighting         = game:GetService("Lighting")
local StarterGui       = game:GetService("StarterGui")
local LocalPlayer      = Players.LocalPlayer

local _has_newcclosure       = type(newcclosure)       == "function"
local _has_getnamecallmethod = type(getnamecallmethod)  == "function"
local _has_getrawmetatable   = type(getrawmetatable)    == "function"
local _has_setreadonly       = type(setreadonly)        == "function"
local _has_firetouchinterest = type(firetouchinterest)  == "function"

local function Notify(title, content, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title    = tostring(title   or "Stylo723"),
            Text     = tostring(content or ""),
            Duration = tonumber(duration) or 3,
        })
    end)
end

pcall(function()
    local function guardBall(ball)
        if not ball or not ball:IsA("BasePart") then return end
        pcall(function() ball.CanCollide = false end)
        ball:GetPropertyChangedSignal("CanCollide"):Connect(function()
            if ball.CanCollide then pcall(function() ball.CanCollide = false end) end
        end)
    end
    local function findAndGuard()
        local sys = Workspace:FindFirstChild("TPSSystem")
        if sys then
            local ball = sys:FindFirstChild("TPS")
            if ball then guardBall(ball) end
            sys.ChildAdded:Connect(function(c)
                if c.Name == "TPS" then guardBall(c) end
            end)
        end
    end
    findAndGuard()
    Workspace.ChildAdded:Connect(function(c)
        if c.Name == "TPSSystem" then task.wait(0.05); findAndGuard() end
    end)
end)

pcall(function()
    for _, b in pairs(workspace.FE.Actions:GetChildren()) do
        if b.Name == " " then b:Destroy() end
    end
end)
pcall(function()
    local ch = LocalPlayer.Character
    if ch then
        for _, b in pairs(ch:GetChildren()) do
            if b.Name == " " then b:Destroy() end
        end
    end
end)
pcall(function()
    local a = workspace.FE.Actions
    if not a then return end
    if a:FindFirstChild("KeepYourHeadUp_") then
        a.KeepYourHeadUp_:Destroy()
        local r = Instance.new("RemoteEvent")
        r.Name   = "KeepYourHeadUp_"
        r.Parent = a
    else
        a.KeepYourHeadUp_ = Instance.new("RemoteEvent")
        a.KeepYourHeadUp_.Name = "KeepYourHeadUp_"
    end
end)
local function isWeirdName(n)
    return string.match(n, "^[a-zA-Z]+%-%d+%a*%-%d+%a*$") ~= nil
end
local function deleteWeirdRemotes(parent, depth)
    depth = depth or 0
    if depth > 6 then return end
    pcall(function()
        for _, child in pairs(parent:GetChildren()) do
            if child:IsA("RemoteEvent") and isWeirdName(child.Name) then
                child:Destroy()
            else
                deleteWeirdRemotes(child, depth + 1)
            end
        end
    end)
end
pcall(function() deleteWeirdRemotes(game) end)

task.spawn(function()
    while true do
        pcall(function()
            LocalPlayer.SimulationRadius = 1000
            LocalPlayer.MaximumSimulationRadius = 1000
        end)
        task.wait(1)
    end
end)

local redzlib
pcall(function()
    redzlib = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/minhdepzai-v/LibraryRobloc/refs/heads/main/RedzLibrary.lua"
    ))()
end)

if not redzlib then
    local function mkStub()
        local t = {}
        setmetatable(t, {
            __index = function(_, _k)
                return function(...)
                    return mkStub()
                end
            end
        })
        return t
    end
    redzlib = {
        MakeWindow = function(_, _opts)
            local w = mkStub()
            w.SelectTab         = function() end
            w.AddMinimizeButton = function() end
            w.MakeTab           = function(_, _) return mkStub() end
            return w
        end
    }
    warn("[Stylo723] Redz UI no cargo revisa la url de mierda o tu conexion.")
end


local Window = redzlib:MakeWindow({
    Title      = "Stylo723 — 1.0",
    SubTitle   = "by Stylo Team",
    SaveFolder = "Stylo723",
})


if not _G._Stylo723P then
    _G._Stylo723P = {
        reachEnabled  = false,
        reachDistance = 1,
        currentSpeed  = 10000,
        reactPower    = 10000,
    }
end
local P = _G._Stylo723P

if not _G._StyRBall then _G._StyRBall = nil end
if not _G._StyRHRP  then _G._StyRHRP  = nil end

if not _G._StyCacheWorker then
    _G._StyCacheWorker = RunService.RenderStepped:Connect(function()
        pcall(function()
            local sys    = Workspace:FindFirstChild("TPSSystem")
            _G._StyRBall = sys and sys:FindFirstChild("TPS")
            local ch     = LocalPlayer.Character
            _G._StyRHRP  = ch and ch:FindFirstChild("HumanoidRootPart")
        end)
    end)
end

if not _G._StyCharConn then
    _G._StyCharConn = LocalPlayer.CharacterAdded:Connect(function(char)
        pcall(function()
            _G._StyRHRP = char:WaitForChild("HumanoidRootPart", 3)
            if P.reachEnabled and _G._StyReachRestart then
                task.wait(0.05)
                _G._StyReachRestart()
            end
        end)
    end)
end

local FlagTab = Window:MakeTab({"Flag Func", "flag"})
Window:SelectTab(FlagTab)

local _injectedFlags = {}
local _flagKey       = ""
local _flagVal       = ""


local function tryInjectFlag(rawKey, rawVal)
    
    local key = tostring(rawKey or ""):gsub("[^%w_:]", ""):sub(1, 128)
    if key == "" then
        Notify("Flag Inject", "box vacia, pon la puta ff maricon autista.", 3)
        return false, "key vacia"
    end
    local numCheck = tonumber(rawVal)
    local value    = numCheck
        and tostring(math.clamp(numCheck, -1e15, 1e15))
        or  tostring(rawVal or ""):sub(1, 256)

    local ok, method = false, ""

    
    pcall(function()
        if setfflag then
            setfflag(key, value)
            ok = true; method = "setfflag"
        end
    end)
    
    if not ok then
        pcall(function()
            if _G.setfflag then
                _G.setfflag(key, value)
                ok = true; method = "_G.setfflag"
            end
        end)
    end
    
    if not ok then
        pcall(function()
            if syn and syn.setfflag then
                syn.setfflag(key, value)
                ok = true; method = "syn.setfflag"
            end
        end)
    end
   
    if not ok then
        pcall(function()
            local s = settings()
            if s then
                s[key] = value
                ok = true; method = "settings()"
            end
        end)
    end

    
    _injectedFlags[key] = value

    local report = ok
        and ("OK (" .. method .. ")")
        or  "Registrado local (executor sin soporte setfflag)"

    Notify("Flag Inject", report .. "\n" .. key .. " = " .. value, 4)
    return true, report
end

-- UI del Flag Inject
FlagTab:AddSection({"Fast Flag Injector"})
FlagTab:AddParagraph({"Como usarlo",
    "1. pon la puta ff\n2. comprueba el valor (true/false/numero)\n3. Pulsa Inject Flag"
})

FlagTab:AddTextBox({
    Name            = "Flag Name (key, valor)",
    Description     = "Ej: FInterpolation",
    PlaceholderText = "Finterpolation : 'valor' ",
    Callback        = function(v)
        pcall(function() _flagKey = tostring(v or "") end)
    end,
})

FlagTab:AddTextBox({
    Name            = "Flag Value",
    Description     = "true  /  false  /  numero",
    PlaceholderText = "true / false / numero",
    Callback        = function(v)
        pcall(function()
            local num = tonumber(v)
            _flagVal  = num
                and tostring(math.clamp(num, -1e15, 1e15))
                or  tostring(v or "")
        end)
    end,
})

FlagTab:AddButton({"Inject Flag", function()
    pcall(function() tryInjectFlag(_flagKey, _flagVal) end)
end})

FlagTab:AddButton({"Remove Flag", function()
    pcall(function()
        if _flagKey == "" then
            Notify("Flag Inject", "pon la fastflag  primero amigo", 3)
            return
        end
        _injectedFlags[_flagKey] = nil
        pcall(function() if setfflag then setfflag(_flagKey, "") end end)
        Notify("Flag Remove", "Eliminada: " .. tostring(_flagKey), 3)
    end)
end})

FlagTab:AddButton({"Clear All Flags", function()
    pcall(function()
        for k in pairs(_injectedFlags) do
            pcall(function() if setfflag then setfflag(k, "") end end)
        end
        _injectedFlags = {}
        _flagKey = ""
        _flagVal = ""
        Notify("Flag Inject", "Todas las flags limpiadas.", 3)
    end)
end})

FlagTab:AddSection({"Quick Flags — Rendimiento — unchecked"})

local QUICK_FLAGS = {
    { key = "FFlag::DebugForceFastGPUTextureDeallocation", value = "true",  label = "Fast GPU Dealloc"    },
    { key = "FFlag::GraphicsGLUseLightingDeferredPass",    value = "false", label = "No Deferred Lighting" },
    { key = "FFlag::DisablePostFx",                        value = "true",  label = "Disable PostFX"       },
    { key = "FFlag::EnableSmoothTerrainInterpolation",     value = "false", label = "No Terrain Smooth"    },
    { key = "FFlag::DebugDisableDedicatedServerPreload",   value = "true",  label = "Less Server Preload"  },
}
for _, qf in ipairs(QUICK_FLAGS) do
    local q = qf
    FlagTab:AddButton({"Quick: " .. q.label, function()
        pcall(function() tryInjectFlag(q.key, q.value) end)
    end})
end


local HomeTab = Window:MakeTab({"Home", "house"})

HomeTab:AddDiscordInvite({
    Name        = "Stylo723 — Comunidad Oficial",
    Description = "Únete al servidor de Discord del script.",
    Logo        = "rbxassetid://96308139812879",
    Invite      = "https://discord.gg/9e2YyPcwN",
})

HomeTab:AddSection({"Informacion"})
HomeTab:AddParagraph({"Stylo723 — 1.0",
    "Script para TPS Street Soccer\nUsuario: " .. tostring(LocalPlayer.Name) .. "\nRank: Free User"
})
HomeTab:AddParagraph({"Discord", "discord.gg/ujuwhftzz5"})

HomeTab:AddSection({"Changelog v1.0"})
HomeTab:AddParagraph({"Novedades",
    "+ Redz UI v5 (API real)\n+ Flag Inject (FastFlags multi-metodo)\n+ Reacts x100 (100 -> 10000)\n+ Anti-Crash global (pcall)\n+ Ball CanCollide Guardian"
})

local ReachTab = Window:MakeTab({"Reach", "target"})

local reachEnabled  = P.reachEnabled
local reachDistance = P.reachDistance
local reachConnection

local function startReach()
    pcall(function()
        if reachConnection then reachConnection:Disconnect() end
        local _char, _root, _hum, _tps, _limb = nil, nil, nil, nil, nil
        local _lastRig, _frameSkip = nil, 0
        reachConnection = RunService.RenderStepped:Connect(function()
            pcall(function()
                local character = LocalPlayer.Character
                if not character then return end
                if character ~= _char then
                    _char    = character
                    _root    = character:FindFirstChild("HumanoidRootPart")
                    _hum     = character:FindFirstChild("Humanoid")
                    _limb    = nil
                    _lastRig = nil
                end
                if not (_root and _hum) then return end
                _frameSkip = _frameSkip + 1
                if _frameSkip >= 3 then
                    _frameSkip = 0
                    local sys = Workspace:FindFirstChild("TPSSystem")
                    _tps = sys and sys:FindFirstChild("TPS")
                end
                if not _tps or not _tps.Parent then return end
                local d = _root.Position - _tps.Position
                if (d.X*d.X + d.Y*d.Y + d.Z*d.Z) > reachDistance * reachDistance then return end
                local rig = _hum.RigType
                if rig ~= _lastRig or not _limb or not _limb.Parent then
                    _lastRig = rig
                    local pf   = Lighting:FindFirstChild(LocalPlayer.Name)
                    local foot = pf and pf:FindFirstChild("PreferredFoot")
                    if foot then
                        local nm = (rig == Enum.HumanoidRigType.R6)
                            and ((foot.Value == 1) and "Right Leg" or "Left Leg")
                            or  ((foot.Value == 1) and "RightLowerLeg" or "LeftLowerLeg")
                        _limb = _char:FindFirstChild(nm)
                    end
                end
                if _limb then
                    firetouchinterest(_limb, _tps, 0)
                    firetouchinterest(_limb, _tps, 1)
                end
            end)
        end)
    end)
end

_G._StyReachRestart = function()
    if P.reachEnabled then pcall(startReach) end
end

ReachTab:AddSection({"Method A — FireTouchInterest"})

ReachTab:AddToggle({
    Name     = "Active FireTouchInterest",
    Default  = false,
    Callback = function(state)
        pcall(function()
            reachEnabled   = state
            P.reachEnabled = state
            if state then
                startReach()
            else
                if reachConnection then
                    reachConnection:Disconnect()
                    reachConnection = nil
                end
            end
        end)
    end,
})

ReachTab:AddSlider({
    Name     = "Reach Distance",
    Min      = 1,
    Max      = 15,
    Increase = 1,
    Default  = 1,
    Callback = function(val)
        pcall(function()
            reachDistance   = tonumber(val) or 1
            P.reachDistance = reachDistance
        end)
    end,
})

ReachTab:AddSection({"Method B — Hitbox Resize ( Probabilidsd de ban 85%) "})

ReachTab:AddTextBox({
    Name            = "Leg Hitbox R6",
    Description     = "Redimensiona las piernas (R6)",
    PlaceholderText = "Minimo: 1",
    Callback        = function(value)
        pcall(function()
            local v = math.max(tonumber(value) or 1, 0.1)
            local c = LocalPlayer.Character
            if not c then return end
            for _, n in pairs({"Right Leg", "Left Leg"}) do
                local p = c:FindFirstChild(n)
                if p then p.Size = Vector3.new(v, 2, v); p.CanCollide = false end
            end
            local hrp = c:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.Size = Vector3.new(v, 2, v); hrp.CanCollide = false end
        end)
    end,
})

ReachTab:AddTextBox({
    Name            = "Legs Size R15",
    Description     = "Redimensiona las piernas (R15)",
    PlaceholderText = "Minimo: 1",
    Callback        = function(value)
        pcall(function()
            local v = math.max(tonumber(value) or 1, 0.1)
            local c = LocalPlayer.Character
            if not c then return end
            for _, n in pairs({"RightLowerLeg", "LeftLowerLeg"}) do
                local p = c:FindFirstChild(n)
                if p then p.Size = Vector3.new(v, 2, v); p.CanCollide = false end
            end
            local hrp = c:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.Size = Vector3.new(v, 2, v); hrp.CanCollide = false end
        end)
    end,
})

ReachTab:AddButton({"Fake Legs (Appear Normal)", function()
    pcall(function()
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local humanoid  = character:WaitForChild("Humanoid")
        if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
            Notify("Reach", "Solo funciona con R6.", 3)
            return
        end
        for _, side in pairs({"Left", "Right"}) do
            local real = character[side .. " Leg"]
            real.Transparency = 1
            real.Massless     = true
            local fake        = Instance.new("Part", character)
            fake.Name         = side .. " Leg Fake"
            fake.CanCollide   = false
            fake.Color        = real.Color
            fake.Size         = Vector3.new(1, 2, 1)
            fake.Position     = real.Position
            local motor       = Instance.new("Motor6D", character.Torso)
            motor.Part0       = character.Torso
            motor.Part1       = fake
            if side == "Left" then
                motor.C0 = CFrame.new(-1,-1,0,0,0,-1,0,1,0,1,0,0)
                motor.C1 = CFrame.new(-0.5,1,0,0,0,-1,0,1,0,1,0,0)
            else
                motor.C0 = CFrame.new(1,-1,0,0,0,1,0,1,0,-1,0,0)
                motor.C1 = CFrame.new(0.5,1,0,0,0,1,0,1,0,-1,0,0)
            end
        end
        Notify("Reach", "Fake Legs activadas.", 2)
    end)
end})

local MossingTab = Window:MakeTab({"Mossing", "star"})

local headReachEnabled = false
local headReachSize    = Vector3.new(1, 1.5, 1)
local headTransparency = 0.5
local headOffset       = Vector3.new(0, 0, 0)
local headBoxPart
local headConnection

local function updateHeadBox()
    pcall(function()
        if headBoxPart then headBoxPart:Destroy() end
        headBoxPart              = Instance.new("Part")
        headBoxPart.Size         = headReachSize
        headBoxPart.Transparency = headTransparency
        headBoxPart.Anchored     = true
        headBoxPart.CanCollide   = false
        headBoxPart.Color        = Color3.fromRGB(200, 30, 30)
        headBoxPart.Material     = Enum.Material.Neon
        headBoxPart.Name         = "HeadReachBox"
        headBoxPart.Parent       = Workspace
    end)
end

local function startHeadReach()
    if not headReachEnabled then return end
    pcall(function()
        if headConnection then headConnection:Disconnect() end
        updateHeadBox()
        local _head, _tps, _char = nil, nil, nil
        local _skipFrame = 0
        headConnection = RunService.RenderStepped:Connect(function()
            pcall(function()
                local character = LocalPlayer.Character
                if not character then return end
                if character ~= _char then
                    _char = character
                    _head = character:FindFirstChild("Head")
                end
                if not _head or not _head.Parent then return end
                _skipFrame = _skipFrame + 1
                if _skipFrame >= 4 then
                    _skipFrame = 0
                    local sys = Workspace:FindFirstChild("TPSSystem")
                    _tps = sys and sys:FindFirstChild("TPS")
                end
                if not _tps or not _tps.Parent then return end
                if _tps.CanCollide then pcall(function() _tps.CanCollide = false end) end
                if headBoxPart and headBoxPart.Parent then
                    headBoxPart.CFrame = _head.CFrame * CFrame.new(headOffset)
                    local rel = headBoxPart.CFrame:PointToObjectSpace(_tps.Position)
                    local hs  = headBoxPart.Size * 0.5
                    if math.abs(rel.X) <= hs.X
                    and math.abs(rel.Y) <= hs.Y
                    and math.abs(rel.Z) <= hs.Z then
                        firetouchinterest(_head, _tps, 0)
                        firetouchinterest(_head, _tps, 1)
                    end
                end
            end)
        end)
    end)
end

MossingTab:AddSection({"Moss Reach — Head Hitbox"})

MossingTab:AddToggle({
    Name     = "Active Moss Reach",
    Default  = false,
    Callback = function(state)
        pcall(function()
            headReachEnabled = state
            if state then
                startHeadReach()
            else
                if headConnection then headConnection:Disconnect() end
                if headBoxPart    then headBoxPart:Destroy() end
            end
        end)
    end,
})

MossingTab:AddSlider({
    Name     = "Range X",
    Min      = 0,
    Max      = 50,
    Increase = 1,
    Default  = 1,
    Callback = function(val)
        pcall(function()
            headReachSize = Vector3.new(tonumber(val) or 1, headReachSize.Y, headReachSize.Z)
            if headReachEnabled then updateHeadBox() end
        end)
    end,
})

MossingTab:AddSlider({
    Name     = "Range Y",
    Min      = 0,
    Max      = 50,
    Increase = 1,
    Default  = 2,
    Callback = function(val)
        pcall(function()
            local v = tonumber(val) or 2
            headReachSize = Vector3.new(headReachSize.X, v, headReachSize.Z)
            headOffset    = Vector3.new(headOffset.X, v / 2.5, headOffset.Z)
            if headReachEnabled then updateHeadBox() end
        end)
    end,
})

MossingTab:AddSlider({
    Name     = "Range Z",
    Min      = 0,
    Max      = 50,
    Increase = 1,
    Default  = 1,
    Callback = function(val)
        pcall(function()
            headReachSize = Vector3.new(headReachSize.X, headReachSize.Y, tonumber(val) or 1)
            if headReachEnabled then updateHeadBox() end
        end)
    end,
})

MossingTab:AddToggle({
    Name     = "Stealth Mode",
    Default  = false,
    Callback = function(v)
        pcall(function()
            headTransparency = v and 1 or 0.5
            if headBoxPart then headBoxPart.Transparency = headTransparency end
        end)
    end,
})


local ReactTab = Window:MakeTab({"Reacts", "zap"})

local REACT_ACTIONS = {
    Kick   = true, KickC1 = true, Tackle = true, Header = true,
    SaveRA = true, SaveLA = true, SaveRL = true, SaveLL = true, SaveT  = true,
}

local currentSpeed      = P.currentSpeed or 10000
local currentReactPower = P.reactPower   or 10000


local function getAtt(ball)
    local att = ball:FindFirstChild("_StyAtt")
    if not att then
        att        = Instance.new("Attachment")
        att.Name   = "_StyAtt"
        att.Parent = ball
    end
    return att
end

local function removeLV(ball)
    pcall(function()
        local lv = ball:FindFirstChild("_StyLV")
        if lv then lv:Destroy() end
    end)
end

local function fireReact(dir, speed, snapFwd, liftY)
    pcall(function()
        local ball = _G._StyRBall
        local hrp  = _G._StyRHRP
        if not (ball and ball.Parent and hrp) then return end

        local s   = math.clamp(tonumber(speed) or currentSpeed, 1, 999999)
        local fwd = dir or hrp.CFrame.LookVector
        local sf  = snapFwd or 0.4
        local ly  = liftY   or 0

        pcall(function() ball:SetNetworkOwner(LocalPlayer) end)
        pcall(function() ball.CanCollide = false end)

        local dist = (ball.Position - hrp.Position).Magnitude
        if dist > 6 then
            ball.CFrame = CFrame.new(hrp.Position + fwd * sf + Vector3.new(0, ly, 0))
        end

        ball.AssemblyLinearVelocity  = Vector3.zero
        ball.AssemblyAngularVelocity = Vector3.zero

        removeLV(ball)
        local att = getAtt(ball)
        local lv  = Instance.new("LinearVelocity")
        lv.Name                   = "_StyLV"
        lv.Attachment0            = att
        lv.MaxForce               = math.huge
        lv.RelativeTo             = Enum.ActuatorRelativeTo.World
        lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        lv.VectorVelocity         = (fwd + Vector3.new(0, ly * 0.01, 0)).Unit * s
        lv.Parent                 = ball

        ball.AssemblyLinearVelocity = (fwd + Vector3.new(0, ly * 0.01, 0)).Unit * s

        task.defer(function()
            pcall(function()
                removeLV(ball)
                if ball and ball.Parent then
                    if ball.AssemblyLinearVelocity.Magnitude < s * 0.4 then
                        ball.AssemblyLinearVelocity =
                            (fwd + Vector3.new(0, ly * 0.01, 0)).Unit * s
                    end
                end
            end)
        end)
    end)
end

local function enableReactHook()
    pcall(function()
        if _G._StyReactHookInstalled then return end
        _G._StyReactHookInstalled = true
        local meta        = getrawmetatable(game)
        local oldNamecall = meta.namecall
        setreadonly(meta, false)
        meta.namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if method == "Kick" or method == "kick" then
                return
            end
            if method == "FireServer" and currentReactPower > 0 and REACT_ACTIONS[tostring(self)] then
                pcall(function()
                    local ball = _G._StyRBall
                    local hrp  = _G._StyRHRP
                    if not (ball and ball.Parent and hrp) then return end
                    pcall(function() ball:SetNetworkOwner(LocalPlayer) end)
                    if ball.CanCollide then pcall(function() ball.CanCollide = false end) end
                    ball.AssemblyLinearVelocity = hrp.CFrame.LookVector * currentSpeed
                    ball.AssemblyAngularVelocity = Vector3.zero
                end)
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(meta, true)
    end)
end
enableReactHook()



ReactTab:AddSection({"Speed Tiers — x100 Multiplier"})

local TIERS = {
    { name = "React 100",  speed = 10000  },
    { name = "React 200",  speed = 20000  },
    { name = "React 350",  speed = 35000  },
    { name = "React 500",  speed = 50000  },
    { name = "React 700",  speed = 70000  },
    { name = "React 1000", speed = 100000 },
}

for _, tier in ipairs(TIERS) do
    local t = tier
    ReactTab:AddButton({t.name .. "  |  " .. tostring(t.speed), function()
        pcall(function()
            currentSpeed      = t.speed
            currentReactPower = t.speed
            P.currentSpeed    = t.speed
            P.reactPower      = t.speed
            Notify(t.name, "Speed activo: " .. tostring(t.speed), 2)
        end)
    end})
end

ReactTab:AddSection({"Control Manual de Speed"})

ReactTab:AddSlider({
    Name     = "React Speed",
    Min      = 100,
    Max      = 200000,
    Increase = 100,
    Default  = 10000,
    Callback = function(val)
        pcall(function()
            local v           = math.clamp(tonumber(val) or 10000, 1, 999999)
            currentSpeed      = v
            currentReactPower = v
            P.currentSpeed    = v
            P.reactPower      = v
        end)
    end,
})

ReactTab:AddSection({"Manual Fire"})

ReactTab:AddButton({"Ground Shot", function()
    pcall(function()
        local hrp = _G._StyRHRP
        if not hrp then return end
        fireReact(hrp.CFrame.LookVector, currentSpeed, 0.4, 0)
        Notify("Ground Shot", tostring(currentSpeed) .. " s/s", 1)
    end)
end})

ReactTab:AddButton({"Lifted Shot  20deg", function()
    pcall(function()
        local hrp = _G._StyRHRP
        if not hrp then return end
        local look  = hrp.CFrame.LookVector
        local angle = math.rad(20)
        local dir   = Vector3.new(
            look.X * math.cos(angle),
            math.sin(angle),
            look.Z * math.cos(angle)
        ).Unit
        fireReact(dir, currentSpeed, 0.4, 0)
        Notify("Lifted Shot", tostring(currentSpeed) .. " s/s | 20deg", 1)
    end)
end})

ReactTab:AddButton({"Aerial Shot  35deg", function()
    pcall(function()
        local hrp = _G._StyRHRP
        if not hrp then return end
        local look  = hrp.CFrame.LookVector
        local angle = math.rad(35)
        local dir   = Vector3.new(
            look.X * math.cos(angle),
            math.sin(angle),
            look.Z * math.cos(angle)
        ).Unit
        fireReact(dir, currentSpeed, 0.3, 0)
        Notify("Aerial Shot", tostring(currentSpeed) .. " s/s | 35deg", 1)
    end)
end})

ReactTab:AddButton({"Snap and Fire", function()
    pcall(function()
        local ball = _G._StyRBall
        local hrp  = _G._StyRHRP
        if not (ball and hrp) then return end
        pcall(function() ball:SetNetworkOwner(LocalPlayer) end)
        pcall(function() ball.CanCollide = false end)
        local look = hrp.CFrame.LookVector
        ball.CFrame = CFrame.new(hrp.Position + look * 0.3 + Vector3.new(0, 0.1, 0))
        ball.AssemblyLinearVelocity  = Vector3.zero
        ball.AssemblyAngularVelocity = Vector3.zero
        task.wait()
        fireReact(look, currentSpeed, 0, 0)
        Notify("Snap and Fire", tostring(currentSpeed) .. " s/s", 1)
    end)
end})

ReactTab:AddButton({"Goalkeeper Clear", function()
    pcall(function()
        local hrp = _G._StyRHRP
        if not hrp then return end
        local look  = hrp.CFrame.LookVector
        local angle = math.rad(15)
        local dir   = Vector3.new(
            look.X * math.cos(angle),
            math.sin(angle),
            look.Z * math.cos(angle)
        ).Unit
        fireReact(dir, currentSpeed, 0.4, 0)
        Notify("GK Clear", tostring(currentSpeed) .. " s/s", 1)
    end)
end})

task.wait(1)
Notify("Stylo723 — 1.0", "Cargado | discord.gg/ujuwhftzz5", 5)
