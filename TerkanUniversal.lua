local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local VirtualUser      = game:GetService("VirtualUser")

local lp = Players.LocalPlayer

local UI
if TERKANUI then
    UI = TERKANUI
elseif readfile and isfile and isfile("TerkanUI.lua") then
    UI = loadstring(readfile("TerkanUI.lua"))()
else
    error("TerkanUI.lua not found - put it in your executor workspace folder")
end

if getgenv().__TerkanUniversal then
    pcall(getgenv().__TerkanUniversal.Unload)
end

local U = { Conns = {}, Binds = {}, Cleanups = {}, Running = true, White = {}, Black = {} }
getgenv().__TerkanUniversal = U

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(U.Conns, c)
    return c
end

local function onUnload(fn) table.insert(U.Cleanups, fn) end

local bindCounter = 0
local function renderLast(fn)
    bindCounter += 1
    local name = "TerkanU_" .. bindCounter
    RunService:BindToRenderStep(name, Enum.RenderPriority.Last.Value, fn)
    table.insert(U.Binds, name)
end

local function renderFirst(fn)
    bindCounter += 1
    local name = "TerkanU_" .. bindCounter
    RunService:BindToRenderStep(name, Enum.RenderPriority.First.Value, fn)
    table.insert(U.Binds, name)
end

local function cam() return workspace.CurrentCamera end

local function hasFn(name) return typeof(getgenv()[name]) == "function" end

local function parentGui()
    if hasFn("gethui") then
        local ok, res = pcall(gethui)
        if ok and res then return res end
    end
    local ok, core = pcall(function() return game:GetService("CoreGui") end)
    if ok and core then return core end
    return lp:WaitForChild("PlayerGui")
end

local C = {}
local TOG, BIND = {}, {}
U.C, U.TOG = C, TOG

local win = UI:Window({
    Title = "TERKAN",
    Version = "V 2.0",
    Footer = "Terkan Universal",
    ToggleKey = Enum.KeyCode.RightShift,
})

U.Win = win

local notify

local FEATURE_TOGGLES = {
    AimEnabled = true, SilentEnabled = true, TrigEnabled = true, RageEnabled = true, ESPEnabled = true,
    FlyEnabled = true, Noclip = true, SpeedEnabled = true, JumpEnabled = true, InfJump = true,
    AntiStun = true, AntiFling = true, AntiVoid = true, AntiAim = true, Desync = true, FollowEnabled = true,
    OrbitEnabled = true, Spectate = true, ClickTp = true, CursorEnabled = true, Fullbright = true,
    FovEnabled = true, FpsBoost = true, AntiAfk = true, VoidSpam = true, AntiRagdoll = true, FlingLoop = true, NoAnim = true, Freecam = true,
    CleanEffects = true, CleanFog = true, CleanParticles = true, ZoomUnlock = true, StatsHud = true,
    CfSpeed = true, CfFly = true, TkEnabled = true, ChatSpy = true,
}

local function toggle(sec, text, key, default, onChange)
    C[key] = default or false
    local api = sec:Toggle({
        Text = text, Default = default or false, Flag = key,
        Callback = function(v)
            C[key] = v
            if onChange then onChange(v) end

            if FEATURE_TOGGLES[key] and U.Ready and not U.LoadingConfig and C[key] == v then
                notify(text, v and "Enabled" or "Disabled", v and "success" or nil, "toggle")
            end
        end,
    })
    TOG[key] = api
    return api
end

local function slider(sec, text, key, min, max, default, opts)
    opts = opts or {}
    C[key] = default
    return sec:Slider({
        Text = text, Min = min, Max = max, Default = default, Flag = key,
        Decimals = opts.Decimals, Suffix = opts.Suffix, MaxLabel = opts.MaxLabel,
        Callback = function(v) C[key] = v if opts.OnChange then opts.OnChange(v) end end,
    })
end

local function dropdown(sec, text, key, options, default, onChange)
    C[key] = default
    return sec:Dropdown({
        Text = text, Options = options, Default = default, Flag = key,
        Callback = function(v) C[key] = v if onChange then onChange(v) end end,
    })
end

local function color(sec, text, key, default, onChange)
    C[key] = default
    return sec:ColorPicker({
        Text = text, Default = default, Flag = key,
        Callback = function(v) C[key] = v if onChange then onChange(v) end end,
    })
end

local function keybind(sec, text, key, default, callback, onChanged)
    BIND[key] = sec:Keybind({ Text = text, Default = default, Flag = key, Callback = callback, OnChanged = onChanged })
    return BIND[key]
end

local NOTIF_TITLES = {
    Config = "config", ["Anti Void"] = "protect", ["Anti Fling"] = "protect", Terkan = "startup",
    ["Target locked"] = "target", ["Target down"] = "target_dead",
    ["Player joined"] = "players", ["Player left"] = "players",
}

local function notifCategory(title, kind)
    if kind == "error" then return "warn" end
    local byTitle = NOTIF_TITLES[title]
    if byTitle then return byTitle end
    if kind == "warn" then return "warn" end
    return "misc"
end

local showToast

function notify(title, text, kind, category)
    category = category or notifCategory(title, kind)
    if C["Notif_" .. category] == false then return end
    showToast(title, text, kind)
end
U.Notify = notify

local overlay = Instance.new("ScreenGui")
overlay.Name = "TerkanOverlay"
overlay.ResetOnSpawn = false
overlay.IgnoreGuiInset = true
overlay.DisplayOrder = 9000
overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
overlay.Parent = parentGui()
onUnload(function() overlay:Destroy() end)

local function makeCircle()
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.BackgroundTransparency = 1
    f.Visible = false
    f.BorderSizePixel = 0
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = f
    local stroke = Instance.new("UIStroke"); stroke.Thickness = 1.5; stroke.Parent = f
    f.Parent = overlay
    return function(radius, pos, col, visible)
        f.Visible = visible
        if visible then
            f.Size = UDim2.fromOffset(radius * 2, radius * 2)
            f.Position = UDim2.fromOffset(pos.X, pos.Y)
            stroke.Color = col
        end
    end
end

local function makeLine()
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.BorderSizePixel = 0
    f.Visible = false
    f.Parent = overlay
    return function(a, b, col, visible, thickness)
        f.Visible = visible
        if visible then
            local d = b - a
            f.BackgroundColor3 = col
            f.Size = UDim2.fromOffset(d.Magnitude, thickness or 1.5)
            f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
            f.Rotation = math.deg(math.atan2(d.Y, d.X))
        end
    end
end

local function makeDot()
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Size = UDim2.fromOffset(7, 7)
    f.BorderSizePixel = 0
    f.Visible = false
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = f
    f.Parent = overlay
    return function(pos, col, visible)
        f.Visible = visible
        if visible then f.Position = UDim2.fromOffset(pos.X, pos.Y) f.BackgroundColor3 = col end
    end
end

local function viewportCenter()
    return cam().ViewportSize / 2
end

local function cursorOrCenter(followGun)
    if followGun then return UserInputService:GetMouseLocation() end
    return viewportCenter()
end

local toasts = {}
local TOAST_LINE = 24

local function toastColor(kind)
    if kind == "error" then return Color3.fromRGB(255, 72, 72) end
    if kind == "warn" then return Color3.fromRGB(255, 176, 46) end
    if C.NotifRainbow then return Color3.fromHSV((os.clock() * 0.4) % 1, 0.9, 1) end
    if C.NotifThemeColor ~= false then return UI.Theme.Accent end
    return C.NotifColor or Color3.fromRGB(255, 255, 255)
end

showToast = function(title, text, kind)
    if C.NotifOn == false then return end
    local label = Instance.new("TextLabel")
    label.Name = "Toast"
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromOffset(560, 22)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 15
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextTransparency = 1
    label.TextStrokeTransparency = 1
    label.Text = (text and text ~= "") and (title .. "  ·  " .. text) or title
    label.Parent = overlay
    table.insert(toasts, 1, { label = label, born = os.clock(), kind = kind })

    while #toasts > (C.NotifMax or 5) do
        table.remove(toasts).label:Destroy()
    end
end

onUnload(function()
    for _, t in ipairs(toasts) do t.label:Destroy() end
    table.clear(toasts)
end)

renderLast(function()
    if #toasts == 0 then return end
    local center = viewportCenter()
    local above = C.NotifPos ~= "Below Crosshair"
    local life = C.NotifDuration or 4
    local now = os.clock()

    for i = #toasts, 1, -1 do
        if now - toasts[i].born > life + 0.4 then
            toasts[i].label:Destroy()
            table.remove(toasts, i)
        end
    end

    for i, t in ipairs(toasts) do
        local age = now - t.born
        local fade = math.clamp(math.min(age / 0.2, (life + 0.4 - age) / 0.4), 0, 1)
        local slot = i - 1
        t.label.AnchorPoint = Vector2.new(0.5, above and 1 or 0)
        t.label.Position = UDim2.fromOffset(center.X, above and (center.Y - 70 - slot * TOAST_LINE)
            or (center.Y + 78 + slot * TOAST_LINE))
        t.label.TextColor3 = toastColor(t.kind)
        t.label.TextTransparency = 1 - fade
        t.label.TextStrokeTransparency = math.clamp(0.35 + (1 - fade), 0, 1)
    end
end)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function charOf(plr, allowDead)
    local c = plr.Character
    if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid")
    local root = c:FindFirstChild("HumanoidRootPart")
    if not (hum and root) then return end
    if not allowDead and (hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead) then return end
    return c, hum, root
end

local function sameTeam(plr)
    return lp.Team ~= nil and plr.Team ~= nil and plr.Team == lp.Team
end

local function screenPoint(pos)
    local v = cam():WorldToViewportPoint(pos)
    return Vector2.new(v.X, v.Y), v.Z > 0
end

local function visible(part, char)
    rayParams.FilterDescendantsInstances = { lp.Character }
    local origin = cam().CFrame.Position
    local res = workspace:Raycast(origin, part.Position - origin, rayParams)
    return res == nil or res.Instance:IsDescendantOf(char)
end

local randomPick = {}
local function candidateParts(plr, char, mode)
    local head = char:FindFirstChild("Head")
    local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
    if mode == "Head" then return { head } end
    if mode == "Torso" then return { torso } end
    if mode == "Random" then
        local pick = randomPick[plr]
        if not pick or os.clock() - pick.t > 0.7 then
            pick = { t = os.clock(), head = math.random() < 0.5 }
            randomPick[plr] = pick
        end
        return { pick.head and head or torso }
    end
    return {
        head, torso,
        char:FindFirstChild("LeftUpperArm") or char:FindFirstChild("Left Arm"),
        char:FindFirstChild("RightUpperArm") or char:FindFirstChild("Right Arm"),
        char:FindFirstChild("LeftUpperLeg") or char:FindFirstChild("Left Leg"),
        char:FindFirstChild("RightUpperLeg") or char:FindFirstChild("Right Leg"),
    }
end

local function selectTarget(o)
    local c = cam()
    local origin = o.Origin or viewportCenter()
    local camPos = c.CFrame.Position
    local best, bestScore

    local anyBlack = next(U.Black) ~= nil
    for _, plr in ipairs(Players:GetPlayers()) do
        local listed = not (C.ListRespectWhite and U.White[plr.Name])
            and not (C.ListOnlyBlack and anyBlack and not U.Black[plr.Name])
        if plr ~= lp and listed and (not o.Only or plr.Name == o.Only) then
            local char, hum, root = charOf(plr, o.AllowDead)
            if char and not (o.Team and sameTeam(plr)) and not (o.NoFF and char:FindFirstChildOfClass("ForceField")) then
                local dist = (root.Position - camPos).Magnitude
                if dist <= o.MaxDist and dist >= (o.MinDist or 0) then
                    for _, part in ipairs(candidateParts(plr, char, o.Part)) do
                        if part then
                            local sp, on = screenPoint(part.Position)
                            local fovDist = (sp - origin).Magnitude
                            if (o.FOV == nil) or (on and fovDist <= o.FOV) then
                                if (not o.Wall) or visible(part, char) then
                                    local score
                                    if o.Priority == "Lowest Health" then score = hum.Health
                                    elseif o.Priority == "Closest Distance" then score = dist
                                    else score = on and fovDist or (1e5 + dist) end
                                    if o.Sticky and o.Sticky == plr then score -= 1e6 end
                                    if C.ListBlackFirst and U.Black[plr.Name] then score -= 1e7 end
                                    if not bestScore or score < bestScore then
                                        bestScore = score
                                        best = {
                                            plr = plr, char = char, hum = hum, root = root, part = part,
                                            pos = part.Position, screen = sp, onScreen = on,
                                            dist = dist, fovDist = fovDist,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function predicted(t, seconds)
    if seconds and seconds > 0 then
        return t.part.Position + t.root.AssemblyLinearVelocity * seconds
    end
    return t.part.Position
end

local function cursorOverMenu()
    if not win.Main.Visible then return false end
    local m = UserInputService:GetMouseLocation()
    local p, s = win.Main.AbsolutePosition, win.Main.AbsoluteSize

    local top = game:GetService("GuiService"):GetGuiInset().Y
    return m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y + top and m.Y <= p.Y + s.Y + top
end

local function virtualClick(at)

    if win.Main.Visible and (not at or cursorOverMenu()) then return false end
    local vp = cam().ViewportSize
    local x, y = vp.X / 2, vp.Y / 2

    if at then x, y = at.X, at.Y end
    local vim = game:GetService("VirtualInputManager")
    vim:SendMouseButtonEvent(x, y, 0, true, game, 1)
    task.delay(0.03, function() vim:SendMouseButtonEvent(x, y, 0, false, game, 1) end)
    return true
end

local function fireWeapon(method, at)
    local char = lp.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    local canClick = hasFn("mouse1click") and not cursorOverMenu()
    if method == "Auto" then

        local ok, sent = pcall(virtualClick, at)
        if not (ok and sent) and (not win.Main.Visible or (at ~= nil and not cursorOverMenu())) then
            if tool then tool:Activate() elseif canClick then pcall(mouse1click) end
        end
    elseif method == "Virtual Click" then
        pcall(virtualClick, at)
    elseif method == "Mouse Click" and canClick then
        pcall(mouse1click)
    elseif tool then
        tool:Activate()
    else
        pcall(virtualClick)
    end
end

U.FireWeapon, U.CursorOverMenu, U.Win = fireWeapon, cursorOverMenu, win

local function ensureToolEquipped()
    local char = lp.Character
    if not char or char:FindFirstChildOfClass("Tool") then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local tool = lp.Backpack:FindFirstChildOfClass("Tool")
    if hum and tool then hum:EquipTool(tool) end
end

local AIM_TYPES = { "Smooth Camera", "Hard Lock", "Snap On Fire", "Mouse Move", "Character Face" }
local TARGET_PARTS = { "Head", "Torso", "Random", "Closest" }
local PRIORITIES = { "Closest to Cursor", "Closest Distance", "Lowest Health" }
local FIRE_METHODS = { "Auto", "Tool Activate", "Mouse Click", "Virtual Click" }

local aimTab = win:Tab("Aimbot")
local aim = aimTab:Section("Soft Aim")
local aimTune = aimTab:Section("Targeting", "right")

toggle(aim, "Enabled", "AimEnabled", false)
dropdown(aim, "Mode", "AimMode", { "Hold Key", "Always On" }, "Hold Key")
keybind(aim, "Aim Key", "AimKey", Enum.UserInputType.MouseButton2)
dropdown(aim, "Aimbot Type", "AimType", AIM_TYPES, "Smooth Camera")
slider(aim, "Smoothness", "AimSmooth", 0, 95, 35, { Suffix = "%" })
slider(aim, "Prediction", "AimPredict", 0, 0.3, 0, { Decimals = 2, Suffix = "s" })
toggle(aim, "Sticky Target", "AimSticky", true)

dropdown(aimTune, "Target Part", "AimPart", TARGET_PARTS, "Head")
dropdown(aimTune, "Priority", "AimPriority", PRIORITIES, "Closest to Cursor")
slider(aimTune, "Max Distance", "AimDist", 50, 2000, 500, { Suffix = " st" })
slider(aimTune, "FOV Radius", "AimFov", 20, 800, 160, { Suffix = " px" })
toggle(aimTune, "Team Check", "AimTeam", true)
toggle(aimTune, "Dead Check", "AimDead", true)
toggle(aimTune, "Wall Check", "AimWall", true)
toggle(aimTune, "Show FOV Circle", "AimShowFov", true)
color(aimTune, "FOV Color", "AimFovColor", Color3.fromRGB(255, 255, 255))

local aimCircle = makeCircle()
local aimTarget
local faceLocked = false

local function releaseFace()
    if faceLocked then
        faceLocked = false
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.AutoRotate = true end
    end
end
onUnload(releaseFace)

renderLast(function(dt)
    if not (C.AimEnabled and U.Running) then
        aimTarget = nil
        releaseFace()
        aimCircle(0, Vector2.zero, C.AimFovColor, false)
        return
    end
    local center = viewportCenter()
    aimCircle(C.AimFov, center, C.AimFovColor, C.AimShowFov)

    local active = C.AimMode == "Always On" or (BIND.AimKey and BIND.AimKey:IsDown())
    if C.AimType == "Snap On Fire" then
        active = active and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end

    if not active or cursorOverMenu() then aimTarget = nil releaseFace() return end

    local t = selectTarget({
        Origin = center, FOV = C.AimFov, MaxDist = C.AimDist, Team = C.AimTeam, Wall = C.AimWall,
        AllowDead = not C.AimDead,
        Part = C.AimPart, Priority = C.AimPriority, Sticky = C.AimSticky and aimTarget and aimTarget.plr or nil,
    })
    aimTarget = t
    if not t then return end

    local goal = predicted(t, C.AimPredict)
    local smooth = math.clamp(C.AimSmooth / 100, 0, 0.98)
    local alpha = 1 - smooth ^ (math.clamp(dt, 0.001, 0.1) * 60)

    local aimType = C.AimType
    if aimType ~= "Character Face" then releaseFace() end

    if aimType == "Hard Lock" or aimType == "Snap On Fire" then

        local c = cam()
        c.CFrame = CFrame.lookAt(c.CFrame.Position, goal)
    elseif aimType == "Mouse Move" and hasFn("mousemoverel") then

        local sp = screenPoint(goal)
        mousemoverel((sp.X - center.X) * alpha, (sp.Y - center.Y) * alpha)
    elseif aimType == "Character Face" then

        local char, hum, root = charOf(lp)
        if char then
            hum.AutoRotate = false
            faceLocked = true
            local flat = Vector3.new(goal.X, root.Position.Y, goal.Z)
            root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, flat), alpha)
        end
    else

        local c = cam()
        c.CFrame = c.CFrame:Lerp(CFrame.lookAt(c.CFrame.Position, goal), alpha)
    end
end)

local CAN_HOOK = hasFn("hookmetamethod") and hasFn("getnamecallmethod") and hasFn("checkcaller") and hasFn("newcclosure")

if CAN_HOOK then

    local silentTab = win:Tab("Silent")
    local silent = silentTab:Section("Silent Aim")
    local silentVis = silentTab:Section("Visuals", "right")

    local HOOKED = false

    toggle(silent, "Enabled", "SilentEnabled", false, function(v)
        if v and not HOOKED then

            C.SilentEnabled = false
            if TOG.SilentEnabled then TOG.SilentEnabled:Set(false, true) end
            notify("Silent Aim", "Unavailable: this executor cannot hook metamethods (hookmetamethod is missing).", "warn")
        end
    end)
    slider(silent, "Hit Chance", "SilentHit", 1, 100, 85, { Suffix = "%" })
    dropdown(silent, "Target Part", "SilentPart", TARGET_PARTS, "Head")
    dropdown(silent, "Priority", "SilentPriority", PRIORITIES, "Closest to Cursor")
    slider(silent, "Max Distance", "SilentDist", 50, 2000, 600, { Suffix = " st" })
    slider(silent, "Prediction", "SilentPredict", 0, 0.3, 0, { Decimals = 2, Suffix = "s" })
    toggle(silent, "Team Check", "SilentTeam", true)
    toggle(silent, "Dead Check", "SilentDead", true)
    toggle(silent, "Wall Check", "SilentWall", true)
    toggle(silent, "Only While Firing", "SilentFiringOnly", true)
    toggle(silent, "Target Any Direction", "SilentAnyDir", true)

    toggle(silentVis, "Visualize FOV", "SilentShowFov", true)
    slider(silentVis, "FOV Radius", "SilentFov", 20, 800, 200, { Suffix = " px" })
    color(silentVis, "FOV Color", "SilentFovColor", Color3.fromRGB(255, 255, 255))
    toggle(silentVis, "Follow Gunpoint", "SilentFollowGun", false)
    toggle(silentVis, "Follow Target", "SilentFollowTarget", true)
    color(silentVis, "Target Color", "SilentTargetColor", Color3.fromRGB(255, 60, 60))
    local silentMode = silentVis:Label("Mode: ...")

    local silentCircle, silentLine, silentDot = makeCircle(), makeLine(), makeDot()
    local silentTarget
    local silentRoll = true

    local function rollSilent() silentRoll = math.random(1, 100) <= C.SilentHit end

    connect(UserInputService.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            rollSilent()
        end
    end)

    local function firing()
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
            or (lp.Character and lp.Character:FindFirstChildOfClass("Tool") ~= nil and UserInputService.TouchEnabled)
    end

    local function silentGoal()
        if not (C.SilentEnabled and silentTarget and silentRoll) then return end
        if C.SilentFiringOnly and not firing() then return end
        if not silentTarget.part.Parent then return end
        return predicted(silentTarget, C.SilentPredict)
    end

    local RAY_METHODS = {
        Raycast = true, FindPartOnRay = true, FindPartOnRayWithIgnoreList = true,
        FindPartOnRayWithWhitelist = true, ViewportPointToRay = true, ScreenPointToRay = true,
    }

    if hasFn("hookmetamethod") and hasFn("getnamecallmethod") and hasFn("checkcaller") and hasFn("newcclosure") then
        local okHook = pcall(function()
            local oldNamecall
            oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                if U.Running and C.SilentEnabled and not checkcaller() then
                    local method = getnamecallmethod()
                    if RAY_METHODS[method] then
                        local goal = silentGoal()
                        if goal then
                            if method == "Raycast" and self == workspace then
                                local origin, direction, params = ...
                                if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                                    return oldNamecall(self, origin, (goal - origin).Unit * direction.Magnitude, params)
                                end
                            elseif method == "ViewportPointToRay" or method == "ScreenPointToRay" then
                                if typeof(self) == "Instance" and self:IsA("Camera") then
                                    local origin = self.CFrame.Position
                                    return Ray.new(origin, (goal - origin).Unit)
                                end
                            elseif self == workspace then
                                local ray, a, b, c = ...
                                if typeof(ray) == "Ray" then
                                    local newRay = Ray.new(ray.Origin, (goal - ray.Origin).Unit * ray.Direction.Magnitude)
                                    return oldNamecall(self, newRay, a, b, c)
                                end
                            end
                        end
                    end
                end
                return oldNamecall(self, ...)
            end))

            local oldIndex
            oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
                if U.Running and C.SilentEnabled and not checkcaller() and typeof(self) == "Instance"
                    and (key == "Hit" or key == "Target" or key == "UnitRay") and self:IsA("Mouse") then
                    local goal = silentGoal()
                    if goal then
                        if key == "Hit" then return CFrame.new(goal) end
                        if key == "UnitRay" then
                            local origin = cam().CFrame.Position
                            return Ray.new(origin, (goal - origin).Unit)
                        end
                        return silentTarget.part
                    end
                end
                return oldIndex(self, key)
            end))
        end)
        HOOKED = okHook
    end
    silentMode:Set(HOOKED and "Mode: hook (true silent)" or "Unavailable: needs hookmetamethod")

    local silentTick = 0
    renderLast(function()
        if not (C.SilentEnabled and U.Running) then
            silentTarget = nil
            U.SilentTarget = nil
            silentCircle(0, Vector2.zero, C.SilentFovColor, false)
            silentLine(Vector2.zero, Vector2.zero, C.SilentTargetColor, false)
            silentDot(Vector2.zero, C.SilentTargetColor, false)
            return
        end

        local origin = cursorOrCenter(C.SilentFollowGun)

        silentCircle(C.SilentFov, origin, C.SilentFovColor, C.SilentShowFov and not C.SilentAnyDir)

        silentTarget = selectTarget({
            Origin = origin, FOV = (not C.SilentAnyDir) and C.SilentFov or nil,
            MaxDist = C.SilentDist, Team = C.SilentTeam, Wall = C.SilentWall, AllowDead = not C.SilentDead,
            Part = C.SilentPart, Priority = C.SilentPriority, Sticky = silentTarget and silentTarget.plr or nil,
        })

        U.SilentTarget = silentTarget

        local showLine = C.SilentFollowTarget and silentTarget ~= nil and silentTarget.onScreen
        silentLine(origin, silentTarget and silentTarget.screen or origin, C.SilentTargetColor, showLine)
        silentDot(silentTarget and silentTarget.screen or origin, C.SilentTargetColor, showLine)

        if os.clock() - silentTick > 0.4 and not firing() then silentTick = os.clock() rollSilent() end
    end)
end

local trigTab = win:Tab("Trigger")
local trig = trigTab:Section("Triggerbot")
local trigTune = trigTab:Section("Timing", "right")

toggle(trig, "Enabled", "TrigEnabled", false)
dropdown(trig, "Mode", "TrigMode", { "Always On", "Hold Key" }, "Always On")
keybind(trig, "Trigger Key", "TrigKey", Enum.KeyCode.LeftAlt)
dropdown(trig, "Target Part", "TrigPart", { "Any", "Head", "Torso" }, "Any")
dropdown(trig, "Fire Method", "TrigMethod", FIRE_METHODS, "Auto")
toggle(trig, "Team Check", "TrigTeam", true)
toggle(trig, "Dead Check", "TrigDead", true)

slider(trigTune, "Reaction Time", "TrigReaction", 0, 500, 60, { Suffix = " ms" })
slider(trigTune, "Shoot Delay", "TrigDelay", 0, 1000, 120, { Suffix = " ms" })
slider(trigTune, "Max Distance", "TrigDist", 10, 1500, 300, { Suffix = " st" })
toggle(trigTune, "Randomize Timing", "TrigRandom", true)

local trigSince, trigWait, lastShot = nil, 0, 0

toggle(trigTune, "Include NPCs / Dummies", "TrigNPC", true)

local function underCrosshair()
    if cursorOverMenu() then return nil, "cursor is on the menu" end
    local pos = UserInputService:GetMouseLocation()
    local ray = cam():ViewportPointToRay(pos.X, pos.Y)
    rayParams.FilterDescendantsInstances = { lp.Character }
    local res = workspace:Raycast(ray.Origin, ray.Direction * C.TrigDist, rayParams)
    if not res then return nil, "nothing under the cursor" end
    local model = res.Instance:FindFirstAncestorOfClass("Model")
    local plr = model and Players:GetPlayerFromCharacter(model)
    local hum
    if plr then
        if plr == lp then return nil, "that is you" end
        if C.ListRespectWhite and U.White[plr.Name] then return nil, "whitelisted: " .. plr.DisplayName end
        if C.ListOnlyBlack and next(U.Black) ~= nil and not U.Black[plr.Name] then return nil, "not on the blacklist" end
        if C.TrigTeam and sameTeam(plr) then return nil, "teammate" end
        local _, h = charOf(plr, not C.TrigDead)
        hum = h
    elseif C.TrigNPC and model and model ~= lp.Character then
        local h = model:FindFirstChildOfClass("Humanoid")
        if h and (not C.TrigDead or h.Health > 0) then hum = h end
    end
    if not hum then return nil, "not a target: " .. (model and model.Name or res.Instance.Name) end
    if C.TrigPart == "Head" and res.Instance.Name ~= "Head" then return nil, "not the head: " .. res.Instance.Name end
    if C.TrigPart == "Torso" and not (res.Instance.Name:find("Torso") or res.Instance.Name == "HumanoidRootPart") then
        return nil, "not the torso: " .. res.Instance.Name
    end
    return plr and plr.DisplayName or model.Name
end

connect(RunService.RenderStepped, function()
    if not (C.TrigEnabled and U.Running) then trigSince = nil return end
    if C.TrigMode == "Hold Key" and not (BIND.TrigKey and BIND.TrigKey:IsDown()) then
        trigSince = nil
        U.TrigTarget, U.TrigWhy = nil, "hold the trigger key"
        return
    end
    local target, why = underCrosshair()
    U.TrigTarget, U.TrigWhy = target, why
    if not target then trigSince = nil return end

    local now = os.clock()
    local jitter = C.TrigRandom and (0.85 + math.random() * 0.3) or 1
    if not trigSince then
        trigSince = now
        trigWait = (C.TrigReaction / 1000) * jitter
    end
    if now - trigSince < trigWait then return end
    if now - lastShot < (C.TrigDelay / 1000) * jitter then return end
    lastShot = now
    fireWeapon(C.TrigMethod, UserInputService:GetMouseLocation())
end)

do
local trigText = Instance.new("TextLabel")
trigText.Name = "TriggerStatus"
trigText.AnchorPoint = Vector2.new(0.5, 0)
trigText.BackgroundTransparency = 1
trigText.Size = UDim2.fromOffset(420, 20)
trigText.Font = Enum.Font.GothamBold
trigText.TextSize = 14
trigText.TextStrokeTransparency = 0.35
trigText.TextStrokeColor3 = Color3.new(0, 0, 0)
trigText.Visible = false
trigText.Parent = overlay

renderLast(function()
    local on = C.TrigEnabled and U.Running
    trigText.Visible = on and true or false
    if not on then return end
    local c = viewportCenter()
    trigText.Position = UDim2.fromOffset(c.X, c.Y + 36)
    if U.TrigTarget then
        trigText.Text = "TRIGGER  ·  " .. U.TrigTarget
        trigText.TextColor3 = Color3.fromRGB(255, 90, 90)
    else
        trigText.Text = "TRIGGER  ·  " .. tostring(U.TrigWhy or "nothing under the cursor")
        trigText.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
end)
end

local rageTarget = nil
do
local rageTab = win:Tab("Rage")
local rage = rageTab:Section("Rage Bot")
local rageFire = rageTab:Section("Firing", "right")
local rageFilt = rageTab:Section("Filters", "right")
local rageAbil = rageTab:Section("Abilities")
local rageMove = rageTab:Section("Positioning & Spin")

toggle(rage, "Enabled", "RageEnabled", false)

toggle(rage, "Pause While Menu Open", "RagePauseMenu", true)
dropdown(rage, "Mode", "RageMode", { "Always On", "Hold Key" }, "Always On")
keybind(rage, "Rage Key", "RageKey", Enum.KeyCode.V)

local RAGE_AUTO = "Everyone (Auto)"
local function rageChoices()
    local names = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then table.insert(names, plr.Name) end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    table.insert(names, 1, RAGE_AUTO)
    return names
end
C.RageWho = RAGE_AUTO
local rageWhoDD = rage:Dropdown({ Text = "Target Player", Options = rageChoices(), Default = RAGE_AUTO,
    Flag = "RageWho", NoSave = true, Callback = function(v) C.RageWho = v end })
local function refreshRageChoices() rageWhoDD:SetOptions(rageChoices()) end
connect(Players.PlayerAdded, refreshRageChoices)
connect(Players.PlayerRemoving, function() task.defer(refreshRageChoices) end)
rage:Button({ Text = "Refresh Player List", Callback = refreshRageChoices })
dropdown(rage, "Target Part", "RagePart", TARGET_PARTS, "Head")
dropdown(rage, "Priority", "RagePriority", { "Closest Distance", "Lowest Health", "Closest to Cursor" }, "Closest Distance")
slider(rage, "Max Distance", "RageDist", 50, 3000, 1000, { Suffix = " st" })
slider(rage, "Min Distance", "RageMinDist", 0, 200, 0, { Suffix = " st" })
slider(rage, "FOV Limit (0 = off)", "RageFov", 0, 1000, 0, { Suffix = " px" })
slider(rage, "Aim Smoothing", "RageSmooth", 0, 95, 0, { Suffix = "%" })
slider(rage, "Prediction", "RagePredict", 0, 0.3, 0.05, { Decimals = 2, Suffix = "s" })
toggle(rage, "Add Ping To Prediction", "RagePing", false)
toggle(rage, "Sticky Target", "RageSticky", true)
slider(rage, "Keep Target At Least", "RageSwitch", 0, 3, 0.4, { Decimals = 1, Suffix = "s" })

toggle(rageFire, "Auto Shoot", "RageShoot", true)
slider(rageFire, "Shoot Delay", "RageDelay", 0, 1000, 80, { Suffix = " ms" })
slider(rageFire, "Delay Jitter", "RageJitter", 0, 100, 0, { Suffix = "%" })
slider(rageFire, "Burst Shots", "RageBurst", 1, 10, 1)
slider(rageFire, "Burst Gap", "RageBurstGap", 10, 300, 40, { Suffix = " ms" })
slider(rageFire, "Only Fire Within", "RageAngle", 1, 180, 180, { Suffix = "°" })
dropdown(rageFire, "Fire Method", "RageMethod", FIRE_METHODS, "Auto")
toggle(rageFire, "Auto Equip Tool", "RageEquip", true)
slider(rageFire, "Warm-up", "RageWarmup", 0, 3, 1, { Decimals = 1, Suffix = "s" })

toggle(rageFilt, "Team Check", "RageTeam", true)
toggle(rageFilt, "Dead Check", "RageDead", true)
toggle(rageFilt, "Ignore Walls", "RageIgnoreWalls", false)
toggle(rageFilt, "Skip ForceField", "RageNoFF", true)

local RAGE_POSITIONS = { "Off", "Behind Target", "Above Target", "Below Target", "Orbit Target", "Strafe Target" }
dropdown(rageMove, "Position", "RagePosition", RAGE_POSITIONS, "Off")
slider(rageMove, "Position Distance", "RagePosDist", 3, 40, 8, { Decimals = 1, Suffix = " st" })
slider(rageMove, "Position Height", "RagePosHeight", -10, 30, 0, { Decimals = 1, Suffix = " st" })
slider(rageMove, "Position Speed", "RagePosSpeed", 0.2, 8, 2, { Decimals = 1, Suffix = "/s" })
slider(rageMove, "Position Smoothing", "RagePosSmooth", 0, 95, 0, { Suffix = "%" })
toggle(rageMove, "Spin Bot", "RageSpin", false, function(v)
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.AutoRotate = not v end
end)
dropdown(rageMove, "Spin Mode", "RageSpinMode", { "Spin", "Jitter" }, "Spin")
slider(rageMove, "Spin Speed", "RageSpinSpeed", 5, 90, 40, { Suffix = "°" })

local SLOT_KEYS = {
    Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
    Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}
local EXTRA_KEYS = { "Q", "E", "R", "T", "F", "G", "Z", "X", "C", "V" }

toggle(rageAbil, "Auto Use Abilities", "RageAbilitiesOn", true)
local abilityNames, slotOf, nextSlot = {}, {}, 1
local chosenTools, chosenKeys = {}, {}
local abilityDD, abilityLast = nil, ""

local function currentToolNames()
    local list = {}
    for _, holder in ipairs({ lp.Backpack, lp.Character }) do
        if holder then
            for _, x in ipairs(holder:GetChildren()) do
                if x:IsA("Tool") and not table.find(list, x.Name) then table.insert(list, x.Name) end
            end
        end
    end
    return list
end

local function refreshAbilities()
    local names = currentToolNames()
    local sig = table.concat(names, "|")
    if sig == abilityLast then return end
    abilityLast = sig
    local known = {}
    for _, n in ipairs(abilityNames) do known[n] = true end
    for _, n in ipairs(names) do
        if not slotOf[n] then slotOf[n], nextSlot = nextSlot, nextSlot + 1 end
        if not known[n] then chosenTools[n] = true end
    end
    abilityNames = names
    abilityDD:SetOptions(names)
    local picked = {}
    for _, n in ipairs(names) do if chosenTools[n] then table.insert(picked, n) end end
    abilityDD:Set(picked, true)
end

abilityDD = rageAbil:Dropdown({ Text = "Abilities To Use", Options = {}, Multi = true, Flag = "RageAbilityPick",
    Callback = function(picked)
        local set = {}
        for _, n in ipairs(picked) do set[n] = true end
        for _, n in ipairs(abilityNames) do chosenTools[n] = set[n] or nil end
    end })
rageAbil:Dropdown({ Text = "Extra Keys", Options = EXTRA_KEYS, Multi = true, Flag = "RageExtraKeys",
    Callback = function(picked)
        chosenKeys = {}
        for _, k in ipairs(picked) do chosenKeys[k] = true end
    end })
dropdown(rageAbil, "Ability Method", "RageAbilityMethod", { "Hotbar Key", "Equip + Activate" }, "Hotbar Key")
slider(rageAbil, "Ability Range", "RageAbilityRange", 3, 150, 14, { Suffix = " st" })
slider(rageAbil, "Delay Between Abilities", "RageAbilityDelay", 50, 2000, 350, { Suffix = " ms" })
slider(rageAbil, "Cooldown Per Ability", "RageAbilityCd", 0, 20, 2, { Decimals = 1, Suffix = "s" })

refreshAbilities()
task.spawn(function()
    while U.Running do
        pcall(refreshAbilities)
        task.wait(1)
    end
end)

local abilityReady, nextAbility, abilityIdx = {}, 0, 0
local function pressKey(code)
    local vim = game:GetService("VirtualInputManager")
    vim:SendKeyEvent(true, code, false, game)
    task.delay(0.05, function() vim:SendKeyEvent(false, code, false, game) end)
end

local function useAbility(now, t, off)
    if not C.RageAbilitiesOn or now < nextAbility then return end
    if t.dist > C.RageAbilityRange or off > C.RageAngle then return end
    if UserInputService:GetFocusedTextBox() then return end

    local ready = {}
    for _, n in ipairs(abilityNames) do
        if chosenTools[n] and (abilityReady["t:" .. n] or 0) <= now then table.insert(ready, { tool = n }) end
    end
    for _, k in ipairs(EXTRA_KEYS) do
        if chosenKeys[k] and (abilityReady["k:" .. k] or 0) <= now then table.insert(ready, { key = k }) end
    end
    if #ready == 0 then return end

    abilityIdx += 1
    local pick = ready[(abilityIdx - 1) % #ready + 1]
    if pick.key then
        pressKey(Enum.KeyCode[pick.key])
        abilityReady["k:" .. pick.key] = now + C.RageAbilityCd
    else
        if C.RageAbilityMethod == "Equip + Activate" then
            local tool = (lp.Character and lp.Character:FindFirstChild(pick.tool)) or lp.Backpack:FindFirstChild(pick.tool)
            local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
            if tool and hum then
                if tool.Parent ~= lp.Character then hum:EquipTool(tool) end
                tool:Activate()
            end
        elseif SLOT_KEYS[slotOf[pick.tool] or 99] then
            pressKey(SLOT_KEYS[slotOf[pick.tool]])
        end
        abilityReady["t:" .. pick.tool] = now + C.RageAbilityCd
    end
    nextAbility = now + C.RageAbilityDelay / 1000
end
U.RageAbilityState = function() return abilityNames, chosenTools, chosenKeys end

local rageState, rageOnAt = "off", 0
local rageLockedAt, rageKills = 0, 0
local burstLeft, nextShot, nextBurst = 0, 0, 0
local rageSpun = false

local function rageReset()
    rageTarget, burstLeft = nil, 0
    if rageSpun then
        rageSpun = false
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.AutoRotate = true end
    end
end
onUnload(rageReset)

local function rageSpot(base, now)
    local d, h, mode = C.RagePosDist, C.RagePosHeight, C.RagePosition
    local up = Vector3.new(0, h, 0)
    if mode == "Behind Target" then return base.Position - base.LookVector * d + up end
    if mode == "Above Target" then return base.Position + Vector3.new(0, d + h, 0) end
    if mode == "Below Target" then return base.Position - Vector3.new(0, d - h, 0) end
    if mode == "Orbit Target" then
        local a = now * C.RagePosSpeed
        return base.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * d + up
    end

    return base.Position + base.RightVector * math.sin(now * C.RagePosSpeed) * d + up
end

local function pingSeconds()
    local ok, v = pcall(function() return lp:GetNetworkPing() end)
    return (ok and type(v) == "number") and v or 0
end

renderLast(function(dt)
    if not (C.RageEnabled and U.Running) or rageState ~= "active"
        or (C.RageMode == "Hold Key" and not (BIND.RageKey and BIND.RageKey:IsDown())) then

        if rageTarget and rageTarget.hum.Health <= 0 then rageKills += 1 end
        rageReset()
        return
    end
    if C.RagePauseMenu and win.Main.Visible then rageReset() return end

    local char, hum, root = charOf(lp)
    if not char then return end
    local now = os.clock()

    if C.RageSpin then
        hum.AutoRotate = false
        rageSpun = true
        local turn = C.RageSpinMode == "Jitter" and (math.random() * 2 - 1) * 90 or C.RageSpinSpeed
        root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(turn), 0)
    elseif rageSpun then
        rageSpun = false
        hum.AutoRotate = true
    end

    local prev = rageTarget
    local keep = prev and (C.RageSticky or now - rageLockedAt < C.RageSwitch)
    local t = selectTarget({
        Only = C.RageWho ~= RAGE_AUTO and C.RageWho or nil,
        FOV = C.RageFov > 0 and C.RageFov or nil, MaxDist = C.RageDist, MinDist = C.RageMinDist,
        Team = C.RageTeam, NoFF = C.RageNoFF, Wall = not C.RageIgnoreWalls, AllowDead = not C.RageDead,
        Part = C.RagePart, Priority = C.RagePriority, Origin = cursorOrCenter(false),
        Sticky = keep and prev.plr or nil,
    })

    if prev and (not t or t.plr ~= prev.plr) then
        if prev.hum.Health <= 0 then rageKills += 1 end
        burstLeft = 0
    end
    if t and (not prev or t.plr ~= prev.plr) then rageLockedAt = now end
    rageTarget = t
    if not t then return end

    if C.RagePosition ~= "Off" then
        local base = t.root.CFrame
        local spot = rageSpot(base, now)
        if C.RagePosSmooth > 0 then
            spot = root.Position:Lerp(spot, 1 - (C.RagePosSmooth / 100) ^ (math.min(dt, 0.1) * 60))
        end

        local flat = Vector3.new(base.Position.X - spot.X, 0, base.Position.Z - spot.Z)
        if flat.Magnitude > 0.05 then
            root.CFrame = CFrame.lookAt(spot, spot + flat)
        else
            root.CFrame = CFrame.new(spot) * root.CFrame.Rotation
        end
    end

    local c = cam()
    local aimAt = predicted(t, C.RagePredict + (C.RagePing and pingSeconds() or 0))
    local goal = CFrame.lookAt(c.CFrame.Position, aimAt)
    if C.RageSmooth > 0 then
        c.CFrame = c.CFrame:Lerp(goal, 1 - (C.RageSmooth / 100) ^ (math.min(dt, 0.1) * 60))
    else
        c.CFrame = goal
    end

    local off = math.deg(math.acos(math.clamp(c.CFrame.LookVector:Dot((aimAt - c.CFrame.Position).Unit), -1, 1)))
    useAbility(now, t, off)
    if not C.RageShoot then return end
    if off > C.RageAngle then return end

    local function delay()
        local jitter = 1 + (math.random() * 2 - 1) * C.RageJitter / 100
        return (C.RageDelay / 1000) * jitter
    end
    if burstLeft == 0 and now >= nextBurst then burstLeft = C.RageBurst end
    if burstLeft > 0 and now >= nextShot then
        if C.RageEquip then ensureToolEquipped() end
        fireWeapon(C.RageMethod)
        burstLeft -= 1
        nextShot = now + C.RageBurstGap / 1000
        if burstLeft == 0 then nextBurst = now + delay() end
    end
end)
U.RageTarget = function() return rageTarget end

local rageText = Instance.new("TextLabel")
rageText.Name = "RageStatus"
rageText.AnchorPoint = Vector2.new(0.5, 1)
rageText.BackgroundTransparency = 1
rageText.Size = UDim2.fromOffset(360, 22)
rageText.Font = Enum.Font.GothamBold
rageText.TextSize = 16
rageText.TextStrokeTransparency = 0.35
rageText.TextStrokeColor3 = Color3.new(0, 0, 0)
rageText.Visible = false
rageText.Parent = overlay

local rageAlpha = 0

local function rageTextColor()
    if C.RageStatusRainbow then return Color3.fromHSV((os.clock() * 0.4) % 1, 0.9, 1) end
    return C.RageStatusColor or Color3.fromRGB(255, 255, 255)
end

renderLast(function(dt)

    if C.RageEnabled and U.Running then
        if rageState == "off" then rageState, rageOnAt, rageKills = "loading", os.clock(), 0 end
        if rageState == "loading" and os.clock() - rageOnAt >= C.RageWarmup then rageState = "active" end
    else
        rageState = "off"
    end

    local want = rageState ~= "off" and C.RageStatus
    rageAlpha += ((want and 1 or 0) - rageAlpha) * math.min(dt * 12, 1)
    rageText.Visible = rageAlpha > 0.02
    if not rageText.Visible then return end

    local text
    if rageState == "loading" then

        local dots = string.rep(".", 1 + math.floor(os.clock() * 3) % 3)
        text = "RAGE LOADING" .. dots .. string.rep(" ", 3 - #dots)
    else
        local armed = C.RageMode ~= "Hold Key" or (BIND.RageKey ~= nil and BIND.RageKey:IsDown())
        local kills = rageKills > 0 and ("  ·  " .. rageKills .. " K") or ""
        if C.RagePauseMenu and win.Main.Visible then
            text = "RAGE PAUSED  ·  menu open" .. kills
        elseif not armed then
            text = "RAGE READY" .. kills
        elseif rageTarget then
            text = "RAGE ACTIVE  ·  " .. rageTarget.plr.DisplayName .. kills
        elseif C.RageWho ~= RAGE_AUTO then
            text = "RAGE ACTIVE  ·  waiting for " .. C.RageWho .. kills
        else
            text = "RAGE ACTIVE" .. kills
        end
    end

    local center = viewportCenter()
    rageText.Text = text
    rageText.TextColor3 = rageTextColor()
    rageText.TextTransparency = 1 - rageAlpha
    rageText.TextStrokeTransparency = math.clamp(0.35 + (1 - rageAlpha), 0, 1)
    rageText.Position = UDim2.fromOffset(center.X, center.Y - 30)
end)
end

local curTab = win:Tab("Cursor")
local cur = curTab:Section("Crosshair")
local curLook = curTab:Section("Look", "right")
local curTxt = curTab:Section("Target Label", "right")

local CURSOR_STYLES = { "Cross + Dot", "Cross", "X", "Star", "Circle + Dot", "Circle", "Dot" }
local CURSOR_ANIMS = { "None", "Pulse", "Heartbeat", "Shrink On Target", "Grow On Target" }

toggle(cur, "Custom Cursor", "CursorEnabled", false)
dropdown(cur, "Style", "CursorStyle", CURSOR_STYLES, "Cross + Dot")
dropdown(cur, "Position", "CursorPos", { "Follow Mouse", "Screen Center" }, "Follow Mouse")
toggle(cur, "Dashed Lines", "CursorDashed", false)
toggle(cur, "Outline", "CursorOutline", true)
toggle(cur, "Hide System Cursor", "CursorHideSys", true)

toggle(curLook, "Rainbow", "CursorRainbow", false)
slider(curLook, "Rainbow Speed", "CursorRainbowSpeed", 0.05, 2, 0.3, { Decimals = 2 })
color(curLook, "Color", "CursorColor", Color3.fromRGB(255, 32, 48))
slider(curLook, "Size", "CursorSize", 4, 60, 12, { Suffix = " px" })
slider(curLook, "Line Width", "CursorThick", 1, 8, 2, { Suffix = " px" })
slider(curLook, "Gap", "CursorGap", 0, 30, 4, { Suffix = " px" })
slider(curLook, "Dot Size", "CursorDot", 2, 20, 4, { Suffix = " px" })
slider(curLook, "Rotation Speed", "CursorSpin", 0, 720, 0, { Suffix = "°/s" })
dropdown(curLook, "Animation", "CursorAnim", CURSOR_ANIMS, "None")
slider(curLook, "Animation Speed", "CursorAnimSpeed", 0.2, 4, 1.2, { Decimals = 1, Suffix = "/s" })
slider(curLook, "Animation Amount", "CursorAnimAmount", 0.05, 1, 0.3, { Decimals = 2 })

toggle(curTxt, "Show Target Name", "CursorLabel", true)
dropdown(curTxt, "Target Source", "CursorSource", { "Auto", "Under Crosshair" }, "Auto")
toggle(curTxt, "Show Distance & HP", "CursorLabelInfo", false)
slider(curTxt, "Text Size", "CursorLabelSize", 10, 28, 14)
toggle(curTxt, "Same Color As Cursor", "CursorLabelSame", true)
color(curTxt, "Text Color", "CursorLabelColor", Color3.fromRGB(255, 255, 255))
dropdown(curTxt, "Text Animation", "CursorLabelAnim", { "None", "Pulse", "Pop", "Fade" }, "None")

local STYLE_PARTS = {
    ["Cross + Dot"]  = { arms = { 0, 90, 180, 270 }, dot = true },
    ["Cross"]        = { arms = { 0, 90, 180, 270 } },
    ["X"]            = { arms = { 45, 135, 225, 315 } },
    ["Star"]         = { arms = { 0, 45, 90, 135, 180, 225, 270, 315 } },
    ["Circle + Dot"] = { ring = true, dot = true },
    ["Circle"]       = { ring = true },
    ["Dot"]          = { dot = true },
}

local curRoot = Instance.new("Frame")
curRoot.Name = "TerkanCursor"
curRoot.AnchorPoint = Vector2.new(0.5, 0.5)
curRoot.BackgroundTransparency = 1
curRoot.Size = UDim2.fromOffset(0, 0)
curRoot.Visible = false
curRoot.Parent = overlay

local function curPiece(round)
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.BorderSizePixel = 0
    f.Visible = false
    f.Parent = curRoot
    if round then
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = f
    end
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.new(0, 0, 0)
    stroke.Thickness = 1
    stroke.Parent = f
    return { frame = f, stroke = stroke }
end

local curArms = {}
for i = 1, 16 do curArms[i] = curPiece(false) end
local curDot = curPiece(true)

local curRing = Instance.new("Frame")
curRing.AnchorPoint = Vector2.new(0.5, 0.5)
curRing.BackgroundTransparency = 1
curRing.BorderSizePixel = 0
curRing.Visible = false
curRing.Parent = curRoot
do
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = curRing
end
local curRingStroke = Instance.new("UIStroke")
curRingStroke.Parent = curRing

local curLabel = Instance.new("TextLabel")
curLabel.AnchorPoint = Vector2.new(0.5, 0)
curLabel.BackgroundTransparency = 1
curLabel.Size = UDim2.fromOffset(300, 20)
curLabel.Font = Enum.Font.GothamBold
curLabel.TextStrokeTransparency = 0.35
curLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
curLabel.Visible = false
curLabel.Parent = curRoot

onUnload(function() curRoot:Destroy() end)

local sysIconOriginal
local function setSystemCursor(visibleIcon)
    if sysIconOriginal == nil then sysIconOriginal = UserInputService.MouseIconEnabled end
    UserInputService.MouseIconEnabled = visibleIcon
end
local function restoreSystemCursor()
    if sysIconOriginal ~= nil then
        UserInputService.MouseIconEnabled = sysIconOriginal
        sysIconOriginal = nil
    end
end
onUnload(restoreSystemCursor)

local function cursorTargetPlayer(pos)
    if C.CursorSource ~= "Under Crosshair" then
        local t = (C.RageEnabled and rageTarget) or (C.AimEnabled and aimTarget) or U.SilentTarget
        if t and t.plr and charOf(t.plr) then return t.plr end
    end
    local ray = cam():ViewportPointToRay(pos.X, pos.Y)
    rayParams.FilterDescendantsInstances = { lp.Character }
    local res = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
    if not res then return end
    local model = res.Instance:FindFirstAncestorOfClass("Model")
    local plr = model and Players:GetPlayerFromCharacter(model)
    if plr and plr ~= lp and charOf(plr) then return plr end
end

local curScale = 1
local curLastPlr, curNewAt = nil, 0

renderLast(function()
    if not (C.CursorEnabled and U.Running) then
        curRoot.Visible = false
        restoreSystemCursor()
        return
    end

    if cursorOverMenu() then
        curRoot.Visible = false
        setSystemCursor(true)
        return
    end
    setSystemCursor(not C.CursorHideSys)

    local pos = C.CursorPos == "Screen Center" and viewportCenter() or UserInputService:GetMouseLocation()
    curRoot.Visible = true
    curRoot.Position = UDim2.fromOffset(pos.X, pos.Y)

    local t = os.clock()
    local col = C.CursorRainbow and Color3.fromHSV((t * C.CursorRainbowSpeed) % 1, 0.9, 1) or C.CursorColor

    local plr = cursorTargetPlayer(pos)
    if plr ~= curLastPlr then curLastPlr, curNewAt = plr, t end

    local speed, amount, anim = C.CursorAnimSpeed, C.CursorAnimAmount, C.CursorAnim
    local goalScale = 1
    if anim == "Pulse" then
        goalScale = 1 + math.sin(t * speed * 2 * math.pi) * amount
        curScale = goalScale
    elseif anim == "Heartbeat" then
        local p = (t * speed) % 1
        local beat = 0
        if p < 0.15 then beat = math.sin(p / 0.15 * math.pi)
        elseif p > 0.25 and p < 0.40 then beat = math.sin((p - 0.25) / 0.15 * math.pi) end
        curScale = 1 + beat * amount
    else
        if anim == "Shrink On Target" then goalScale = plr and (1 - amount * 0.7) or 1
        elseif anim == "Grow On Target" then goalScale = plr and (1 + amount) or 1 end
        curScale += (goalScale - curScale) * 0.2
    end

    local size, gap, thick = C.CursorSize * curScale, C.CursorGap * curScale, C.CursorThick
    local spin = (t * C.CursorSpin) % 360
    local parts = STYLE_PARTS[C.CursorStyle] or STYLE_PARTS["Cross + Dot"]

    local used = 0
    if parts.arms then
        local segments = C.CursorDashed and { { 0, 0.4 }, { 0.6, 1 } } or { { 0, 1 } }
        for _, angle in ipairs(parts.arms) do
            local a = angle + spin
            local rad = math.rad(a)
            local dx, dy = math.cos(rad), math.sin(rad)
            for _, seg in ipairs(segments) do
                used += 1
                local piece = curArms[used]
                local mid = gap + (seg[1] + seg[2]) / 2 * size
                piece.frame.Size = UDim2.fromOffset(math.max((seg[2] - seg[1]) * size, 1), thick)
                piece.frame.Position = UDim2.fromOffset(dx * mid, dy * mid)
                piece.frame.Rotation = a
                piece.frame.BackgroundColor3 = col
                piece.stroke.Enabled = C.CursorOutline
                piece.frame.Visible = true
            end
        end
    end
    for i = used + 1, #curArms do curArms[i].frame.Visible = false end

    curDot.frame.Visible = parts.dot == true
    if parts.dot then
        local d = C.CursorDot * curScale
        curDot.frame.Size = UDim2.fromOffset(d, d)
        curDot.frame.Position = UDim2.fromOffset(0, 0)
        curDot.frame.BackgroundColor3 = col
        curDot.stroke.Enabled = C.CursorOutline
    end

    curRing.Visible = parts.ring == true
    if parts.ring then
        local d = size * 2
        curRing.Size = UDim2.fromOffset(d, d)
        curRingStroke.Color = col
        curRingStroke.Thickness = thick
    end

    local showLabel = C.CursorLabel and plr ~= nil
    curLabel.Visible = showLabel
    if showLabel then
        local text = plr.DisplayName
        if C.CursorLabelInfo then
            local _, hum, root = charOf(plr)
            if hum and root then
                text = string.format("%s  |  %d st  |  %d hp", text, (root.Position - cam().CFrame.Position).Magnitude, hum.Health)
            end
        end

        local extent = (parts.ring and size or (parts.arms and (gap + size) or 0)) + (parts.dot and C.CursorDot * curScale / 2 or 0) + 8
        local textScale, textFade = 1, 0
        local ta = C.CursorLabelAnim
        if ta == "Pulse" then
            textScale = 1 + math.sin(t * speed * 2 * math.pi) * amount * 0.5
        elseif ta == "Pop" then

            local p = math.clamp((t - curNewAt) / 0.35, 0, 1)
            local c1 = 1.70158
            local ease = 1 + (c1 + 1) * (p - 1) ^ 3 + c1 * (p - 1) ^ 2
            textScale = 0.4 + 0.6 * ease
        elseif ta == "Fade" then
            textFade = 0.5 * (0.5 + 0.5 * math.sin(t * speed * 2 * math.pi))
        end

        curLabel.Text = text
        curLabel.TextSize = math.max(math.floor(C.CursorLabelSize * textScale + 0.5), 6)
        curLabel.TextColor3 = C.CursorLabelSame and col or C.CursorLabelColor
        curLabel.TextTransparency = textFade
        curLabel.Position = UDim2.fromOffset(0, extent)
    end
end)

local visTab = win:Tab("Visuals")
local esp = visTab:Section("Player ESP")
local espCol = visTab:Section("ESP Colors", "right")
local world = visTab:Section("View", "right")

toggle(esp, "Enabled", "ESPEnabled", false)
toggle(esp, "Box (3D)", "ESP3D", true)
toggle(esp, "Names", "ESPName", true)
toggle(esp, "Distance & Health", "ESPInfo", true)
toggle(esp, "Held Item", "ESPHeld", true)
toggle(esp, "Health Bar", "ESPHealth", true)
toggle(esp, "Skeleton", "ESPSkeleton", true)
toggle(esp, "Chams", "ESPChams", false)
toggle(esp, "Tracers", "ESPTracers", false)
toggle(esp, "Team Check", "ESPTeam", false)
slider(esp, "Max Distance", "ESPDist", 100, 5000, 1500, { Suffix = " st" })

toggle(espCol, "Use Team Colors", "ESPTeamColors", false)
color(espCol, "Box", "ESP3DColor", Color3.fromRGB(255, 60, 60))
slider(espCol, "Box Scale", "ESP3DScale", 0.6, 1.8, 1, { Decimals = 2 })
slider(espCol, "Box Line Width", "ESP3DThick", 0.02, 0.3, 0.08, { Decimals = 2 })
color(espCol, "Name Text", "ESPTextColor", Color3.fromRGB(255, 255, 255))
color(espCol, "Chams Fill", "ESPFillColor", Color3.fromRGB(255, 60, 60))
color(espCol, "Chams Outline", "ESPOutlineColor", Color3.fromRGB(255, 255, 255))
color(espCol, "Tracer", "ESPTracerColor", Color3.fromRGB(255, 60, 60))
color(espCol, "Skeleton", "ESPSkelColor", Color3.fromRGB(255, 255, 255))
slider(espCol, "Skeleton Width", "ESPSkelWidth", 1, 4, 1.5, { Decimals = 1, Suffix = " px" })
color(espCol, "Health Bar", "ESPHealthColor", Color3.fromRGB(70, 220, 90))
toggle(espCol, "Health Bar Shifts To Red When Low", "ESPHealthShift", false)
color(espCol, "Whitelisted Player", "ListWhiteColor", Color3.fromRGB(80, 200, 255))
color(espCol, "Blacklisted Player", "ListBlackColor", Color3.fromRGB(255, 200, 0))
slider(espCol, "Chams Transparency", "ESPFillTrans", 0, 1, 0.55, { Decimals = 2 })
slider(espCol, "Tracer Width", "ESPTracerWidth", 1, 6, 1.5, { Decimals = 1, Suffix = " px" })

local espRoot = Instance.new("Folder")
espRoot.Name = "TerkanESP"
espRoot.Parent = parentGui()
onUnload(function() espRoot:Destroy() end)

local ESP = {}

local function frame(parent, props)
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    for k, v in pairs(props) do f[k] = v end
    f.Parent = parent
    return f
end

local function label(parent, props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.GothamBold
    l.TextSize = 13
    l.TextStrokeTransparency = 0.35
    l.TextStrokeColor3 = Color3.new(0, 0, 0)
    for k, v in pairs(props) do l[k] = v end
    l.Parent = parent
    return l
end

U.skelBones = function(char, hum)
    local out = {}
    local function part(name)
        local p = char:FindFirstChild(name)
        return p and p:IsA("BasePart") and p or nil
    end
    local function top(p) return (p.CFrame * CFrame.new(0, p.Size.Y / 2, 0)).Position end
    local function bottom(p) return (p.CFrame * CFrame.new(0, -p.Size.Y / 2, 0)).Position end
    local function add(a, b) if a and b then out[#out + 1] = { a, b } end end

    if hum.RigType == Enum.HumanoidRigType.R15 then
        local head, ut, lt = part("Head"), part("UpperTorso"), part("LowerTorso")
        add(head and head.Position, ut and ut.Position)
        add(ut and ut.Position, lt and lt.Position)
        for _, side in ipairs({ "Left", "Right" }) do
            local ua, la, hand = part(side .. "UpperArm"), part(side .. "LowerArm"), part(side .. "Hand")
            add(ut and ut.Position, ua and ua.Position)
            add(ua and ua.Position, la and la.Position)
            add(la and la.Position, hand and hand.Position)
            local ul, ll, foot = part(side .. "UpperLeg"), part(side .. "LowerLeg"), part(side .. "Foot")
            add(lt and lt.Position, ul and ul.Position)
            add(ul and ul.Position, ll and ll.Position)
            add(ll and ll.Position, foot and foot.Position)
        end
    else
        local head, torso = part("Head"), part("Torso")
        local la, ra, ll, rl = part("Left Arm"), part("Right Arm"), part("Left Leg"), part("Right Leg")
        if torso then
            local neck, pelvis = top(torso), bottom(torso)
            add(head and head.Position, neck)
            add(neck, pelvis)
            add(la and top(la), ra and top(ra))
            add(ll and top(ll), rl and top(rl))
        end
        for _, name in ipairs({ "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
            local limb = part(name)
            if limb then add(top(limb), bottom(limb)) end
        end
    end
    return out
end

local function buildESP(plr)
    local o = { plr = plr, tick = 0 }

    o.hl = Instance.new("Highlight")
    o.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    o.hl.Enabled = false
    o.hl.Parent = espRoot

    o.hpBack = frame(overlay, {
        Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(4, 10), Visible = false,
        BackgroundColor3 = Color3.fromRGB(15, 15, 15), BackgroundTransparency = 0.15,
    })
    local hpStroke = Instance.new("UIStroke")
    hpStroke.Color = Color3.new(0, 0, 0)
    hpStroke.Thickness = 1
    hpStroke.Parent = o.hpBack
    o.hpFill = frame(o.hpBack, {
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(70, 220, 90),
    })

    o.bones = {}
    for i = 1, 14 do
        o.bones[i] = frame(overlay, { AnchorPoint = Vector2.new(0.5, 0.5), Visible = false })
    end

    o.info = Instance.new("BillboardGui")
    o.info.AlwaysOnTop = true
    o.info.LightInfluence = 0
    o.info.Size = UDim2.fromOffset(220, 48)
    o.info.StudsOffset = Vector3.new(0, 4.2, 0)
    o.info.ResetOnSpawn = false
    o.info.Enabled = false
    o.info.Parent = espRoot
    local stack = Instance.new("UIListLayout")
    stack.SortOrder = Enum.SortOrder.LayoutOrder
    stack.VerticalAlignment = Enum.VerticalAlignment.Bottom
    stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
    stack.Parent = o.info
    o.nameLabel = label(o.info, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1 })
    o.subLabel = label(o.info, {
        Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 2, Font = Enum.Font.Gotham, TextSize = 12,
    })
    o.heldLabel = label(o.info, {
        Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 3, Font = Enum.Font.Gotham, TextSize = 12,
    })

    o.edges = {}
    for i = 1, 12 do
        local e = Instance.new("BoxHandleAdornment")
        e.AlwaysOnTop = true
        e.ZIndex = 1
        e.Transparency = 0
        e.Visible = false
        e.Parent = espRoot
        o.edges[i] = e
    end

    o.tracer = frame(overlay, { AnchorPoint = Vector2.new(0.5, 0.5), Visible = false })
    return o
end

local function layoutEdges(o, scale, thick)
    local sx, sy, sz = 4 * scale, 5.8 * scale, 2.6 * scale
    local cy = -0.3 * scale
    local i = 0
    local function put(size, offset)
        i += 1
        o.edges[i].Size = size
        o.edges[i].CFrame = CFrame.new(offset)
    end
    for _, y in ipairs({ -1, 1 }) do
        for _, z in ipairs({ -1, 1 }) do put(Vector3.new(sx, thick, thick), Vector3.new(0, cy + y * sy / 2, z * sz / 2)) end
    end
    for _, x in ipairs({ -1, 1 }) do
        for _, z in ipairs({ -1, 1 }) do put(Vector3.new(thick, sy, thick), Vector3.new(x * sx / 2, cy, z * sz / 2)) end
    end
    for _, x in ipairs({ -1, 1 }) do
        for _, y in ipairs({ -1, 1 }) do put(Vector3.new(thick, thick, sz), Vector3.new(x * sx / 2, cy + y * sy / 2, 0)) end
    end
    o.edgeSig = scale .. "|" .. thick
end

local function destroyESP(o)
    for _, key in ipairs({ "hl", "hpBack", "info", "tracer" }) do
        if o[key] then pcall(function() o[key]:Destroy() end) end
    end
    for _, e in ipairs(o.edges or {}) do pcall(function() e:Destroy() end) end
    for _, b in ipairs(o.bones or {}) do pcall(function() b:Destroy() end) end
end

local function hideESP(o)
    o.hl.Enabled = false
    o.hpBack.Visible = false
    o.info.Enabled = false
    o.tracer.Visible = false
    for _, e in ipairs(o.edges) do e.Visible = false end
    for _, b in ipairs(o.bones) do b.Visible = false end
end

connect(Players.PlayerRemoving, function(plr)
    if ESP[plr] then destroyESP(ESP[plr]) ESP[plr] = nil end
end)
onUnload(function() for _, o in pairs(ESP) do destroyESP(o) end table.clear(ESP) end)

connect(RunService.RenderStepped, function()
    if not U.Running then return end
    local c = cam()
    local camPos = c.CFrame.Position
    local vp = c.ViewportSize
    local now = os.clock()

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then
            local char, hum, root = charOf(plr)
            local show = C.ESPEnabled and char ~= nil
            if show and C.ESPTeam and sameTeam(plr) then show = false end
            local dist = show and (root.Position - camPos).Magnitude or 0
            if show and dist > C.ESPDist then show = false end

            local o = ESP[plr]
            if show and not o then o = buildESP(plr) ESP[plr] = o end
            if o then
                if not show then
                    hideESP(o)
                else

                    local listCol = (U.Black[plr.Name] and C.ListBlackColor) or (U.White[plr.Name] and C.ListWhiteColor) or nil
                    local teamCol = listCol or (C.ESPTeamColors and plr.Team and plr.TeamColor.Color)

                    o.hl.Adornee = char
                    o.hl.FillColor = teamCol or C.ESPFillColor
                    o.hl.OutlineColor = C.ESPOutlineColor
                    o.hl.FillTransparency = C.ESPFillTrans
                    o.hl.Enabled = C.ESPChams

                    o.hpBack.Visible = false
                    if C.ESPHealth then
                        local sx, sy, sz = 4 * C.ESP3DScale, 5.8 * C.ESP3DScale, 2.6 * C.ESP3DScale
                        local cy = -0.3 * C.ESP3DScale
                        local minX, minY, maxY, allOn = math.huge, math.huge, -math.huge, true
                        for xi = -1, 1, 2 do
                            for yi = -1, 1, 2 do
                                for zi = -1, 1, 2 do
                                    local sp, on = screenPoint((root.CFrame * CFrame.new(xi * sx / 2, cy + yi * sy / 2, zi * sz / 2)).Position)
                                    if not on then allOn = false end
                                    minX, minY, maxY = math.min(minX, sp.X), math.min(minY, sp.Y), math.max(maxY, sp.Y)
                                end
                            end
                        end
                        if allOn and maxY - minY > 4 then
                            o.hpBack.Visible = true
                            o.hpBack.Position = UDim2.fromOffset(math.floor(minX - 8), math.floor(minY))
                            o.hpBack.Size = UDim2.fromOffset(4, math.floor(maxY - minY))
                        end
                    end

                    if C.ESP3D then
                        local sig = C.ESP3DScale .. "|" .. C.ESP3DThick
                        if o.edgeSig ~= sig then layoutEdges(o, C.ESP3DScale, C.ESP3DThick) end
                        local col3 = teamCol or C.ESP3DColor
                        for _, e in ipairs(o.edges) do
                            e.Adornee = root
                            e.Color3 = col3
                            e.Visible = true
                        end
                    else
                        for _, e in ipairs(o.edges) do e.Visible = false end
                    end

                    local hasHeld = C.ESPHeld and o.heldName ~= nil
                    o.info.Adornee = root
                    o.info.Enabled = C.ESPName or C.ESPInfo or hasHeld
                    o.nameLabel.Visible = C.ESPName
                    o.nameLabel.TextColor3 = teamCol or C.ESPTextColor
                    o.subLabel.Visible = C.ESPInfo
                    o.subLabel.TextColor3 = C.ESPTextColor
                    o.heldLabel.Visible = hasHeld
                    o.heldLabel.TextColor3 = C.ESPTextColor

                    if now - o.tick > 0.1 then
                        o.tick = now
                        o.nameLabel.Text = plr.DisplayName
                        o.subLabel.Text = string.format("%d st  |  %d hp", dist, hum.Health)
                        local tool = char:FindFirstChildOfClass("Tool")
                        o.heldName = tool and tool.Name or nil
                        o.heldLabel.Text = tool and ("[ " .. tool.Name .. " ]") or ""
                    end

                    local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                    o.hpFill.Size = UDim2.new(1, 0, frac, 0)
                    o.hpFill.BackgroundColor3 = C.ESPHealthShift
                        and Color3.fromRGB(230, 60, 60):Lerp(C.ESPHealthColor, frac) or C.ESPHealthColor

                    if C.ESPSkeleton then
                        local joints = U.skelBones(char, hum)
                        local skelCol = teamCol or C.ESPSkelColor
                        for i, line in ipairs(o.bones) do
                            local pair = joints[i]
                            local a, aOn, b, bOn
                            if pair then
                                a, aOn = screenPoint(pair[1])
                                b, bOn = screenPoint(pair[2])
                            end
                            if pair and aOn and bOn then
                                local d = b - a
                                line.Visible = true
                                line.BackgroundColor3 = skelCol
                                line.Size = UDim2.fromOffset(d.Magnitude, C.ESPSkelWidth)
                                line.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
                                line.Rotation = math.deg(math.atan2(d.Y, d.X))
                            else
                                line.Visible = false
                            end
                        end
                    else
                        for _, line in ipairs(o.bones) do line.Visible = false end
                    end

                    if C.ESPTracers then
                        local sp, on = screenPoint(root.Position)
                        if on then
                            local from = Vector2.new(vp.X / 2, vp.Y)
                            local d = sp - from
                            o.tracer.Visible = true
                            o.tracer.BackgroundColor3 = teamCol or C.ESPTracerColor
                            o.tracer.Size = UDim2.fromOffset(d.Magnitude, C.ESPTracerWidth)
                            o.tracer.Position = UDim2.fromOffset((from.X + sp.X) / 2, (from.Y + sp.Y) / 2)
                            o.tracer.Rotation = math.deg(math.atan2(d.Y, d.X))
                        else
                            o.tracer.Visible = false
                        end
                    else
                        o.tracer.Visible = false
                    end
                end
            end
        end
    end
end)

local originalLighting
toggle(world, "Fullbright", "Fullbright", false, function(v)
    if v and not originalLighting then
        originalLighting = {
            Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd,
            GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
        }
    elseif not v and originalLighting then
        for k, val in pairs(originalLighting) do pcall(function() Lighting[k] = val end) end
        originalLighting = nil
    end
end)
slider(world, "Fullbright Brightness", "FullbrightLevel", 1, 5, 2, { Decimals = 1 })
slider(world, "Fullbright Time Of Day", "FullbrightTime", 0, 24, 14, { Decimals = 1, Suffix = " h" })
toggle(world, "Custom FOV", "FovEnabled", false)
slider(world, "Field of View", "FovValue", 30, 120, 90, { Suffix = "°" })

local originalFov
renderLast(function()
    if C.Fullbright then
        Lighting.Brightness = C.FullbrightLevel
        Lighting.ClockTime = C.FullbrightTime
        Lighting.FogEnd = 1e6
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
        Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
    end
    if C.FovEnabled then
        originalFov = originalFov or cam().FieldOfView
        cam().FieldOfView = C.FovValue
    elseif originalFov then
        cam().FieldOfView = originalFov
        originalFov = nil
    end
end)
onUnload(function()
    if originalLighting then for k, val in pairs(originalLighting) do pcall(function() Lighting[k] = val end) end end
    if originalFov then cam().FieldOfView = originalFov end
end)

local moveTab = win:Tab("Movement")
local move = moveTab:Section("Speed & Jump")
local fly = moveTab:Section("Flight & Collision", "right")

local function myHumanoid()
    local c = lp.Character
    return c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart"), c
end

local orig = {}
toggle(move, "Speed", "SpeedEnabled", false, function(v)
    local hum = myHumanoid()
    if not hum then return end
    if v then orig.speed = hum.WalkSpeed
    elseif orig.speed then hum.WalkSpeed = orig.speed orig.speed = nil end
end)
slider(move, "Walk Speed", "SpeedValue", 16, 300, 60, { Suffix = "" })

toggle(move, "Jump Power", "JumpEnabled", false, function(v)
    local hum = myHumanoid()
    if not hum then return end
    if v then
        orig.useJumpPower, orig.jumpPower = hum.UseJumpPower, hum.JumpPower
    elseif orig.jumpPower then
        hum.UseJumpPower = orig.useJumpPower
        hum.JumpPower = orig.jumpPower
        orig.jumpPower = nil
    end
end)
slider(move, "Jump Value", "JumpValue", 20, 300, 80)
toggle(move, "Infinite Jump", "InfJump", false)
connect(UserInputService.JumpRequest, function()
    if not C.InfJump then return end
    local hum = myHumanoid()
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

toggle(move, "Anti Stun", "AntiStun", false, function(v)
    local hum = myHumanoid()
    if not hum then return end
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not v)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not v)
    end)
end)

local flyState = {}
local function stopFly()
    if flyState.bv then flyState.bv:Destroy() flyState.bv = nil end
    if flyState.bg then flyState.bg:Destroy() flyState.bg = nil end
    local hum = myHumanoid()
    if hum then hum.PlatformStand = false end
end

toggle(fly, "Fly", "FlyEnabled", false, function(v) if not v then stopFly() end end)
slider(fly, "Fly Speed", "FlySpeed", 10, 300, 70)
slider(fly, "Vertical Speed", "FlyVertical", 0.2, 2, 1, { Decimals = 2, Suffix = "x" })
slider(fly, "Fly Smoothing", "FlySmooth", 0, 95, 0, { Suffix = "%" })

local function typing() return UserInputService:GetFocusedTextBox() ~= nil end

renderLast(function(dt)
    if not (C.FlyEnabled and U.Running) then return end
    local hum, root = myHumanoid()
    if not hum or not root then return end

    if not (flyState.bv and flyState.bv.Parent) then
        stopFly()
        flyState.bv = Instance.new("BodyVelocity")
        flyState.bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        flyState.bv.Velocity = Vector3.zero
        flyState.bv.Parent = root
        flyState.bg = Instance.new("BodyGyro")
        flyState.bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
        flyState.bg.P = 1e5
        flyState.bg.CFrame = root.CFrame
        flyState.bg.Parent = root
    end
    hum.PlatformStand = true

    local look = cam().CFrame
    local dir = Vector3.zero
    if not typing() then
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += look.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= look.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += look.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= look.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then dir += Vector3.yAxis * C.FlyVertical end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then dir -= Vector3.yAxis * C.FlyVertical end
    end
    local want = dir.Magnitude > 0 and dir.Unit * C.FlySpeed or Vector3.zero
    if C.FlySmooth > 0 then

        want = flyState.bv.Velocity:Lerp(want, 1 - (C.FlySmooth / 100) ^ (math.min(dt, 0.1) * 60))
    end
    flyState.bv.Velocity = want
    flyState.bg.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(look.LookVector.X, 0, look.LookVector.Z))
end)
onUnload(stopFly)

local noclipOriginal = {}
toggle(fly, "Noclip", "Noclip", false, function(v)
    if not v then
        for part, was in pairs(noclipOriginal) do
            if part.Parent then part.CanCollide = was end
        end
        table.clear(noclipOriginal)
    end
end)

local function applyNoclip()
    if not (C.Noclip and U.Running) then return end
    local _, _, char = myHumanoid()
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            if noclipOriginal[part] == nil then noclipOriginal[part] = true end
            part.CanCollide = false
        end
    end
end
connect(RunService.Stepped, applyNoclip)

local lastGoodSpeed, lastGoodJump, antiStunScan = 16, 50, 0
renderLast(function()
    if not U.Running then return end
    local hum, root = myHumanoid()
    if not hum then return end

    if C.SpeedEnabled then
        hum.WalkSpeed = C.SpeedValue
    elseif hum.WalkSpeed > 0 then
        lastGoodSpeed = hum.WalkSpeed
    end

    if C.JumpEnabled then
        hum.UseJumpPower = true
        hum.JumpPower = C.JumpValue
    elseif hum.JumpPower > 0 then
        lastGoodJump = hum.JumpPower
    end

    if C.AntiStun and not C.FlyEnabled then
        if hum.PlatformStand then hum.PlatformStand = false end
        local state = hum:GetState()
        if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown
            or state == Enum.HumanoidStateType.Physics then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        if hum.WalkSpeed < 1 then hum.WalkSpeed = C.SpeedEnabled and C.SpeedValue or lastGoodSpeed end
        if hum.UseJumpPower and hum.JumpPower < 1 then hum.JumpPower = C.JumpEnabled and C.JumpValue or lastGoodJump end
        if root and root.Anchored then root.Anchored = false end

        if os.clock() - antiStunScan > 0.25 then
            antiStunScan = os.clock()
            local _, _, char = myHumanoid()
            if char then
                for _, d in ipairs(char:GetDescendants()) do
                    if d:IsA("Motor6D") and not d.Enabled then d.Enabled = true
                    elseif d:IsA("BallSocketConstraint") and d.Enabled then d.Enabled = false end
                end
            end
        end
    end
end)

local defTab = win:Tab("Defense")
local aflSec = defTab:Section("Anti Fling")
local aaSec = defTab:Section("Anti Aim")
local avSec = defTab:Section("Anti Void", "right")
local dsSec = defTab:Section("Desync", "right")
local arSec = defTab:Section("Anti Ragdoll")

local collisionOriginal = setmetatable({}, { __mode = "k" })
local function restoreCollisions()
    for part, was in pairs(collisionOriginal) do
        if part.Parent then part.CanCollide = was end
        collisionOriginal[part] = nil
    end
end
onUnload(restoreCollisions)

toggle(aflSec, "Anti Fling", "AntiFling", false, function(v) if not v then restoreCollisions() end end)
toggle(aflSec, "No Player Collision", "AntiFlingNoCollide", true)
slider(aflSec, "Max Speed", "AntiFlingSpeed", 60, 600, 220, { Suffix = " st/s" })

connect(RunService.Stepped, function()
    if not (C.AntiFling and C.AntiFlingNoCollide and U.Running) then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr ~= lp and plr.Character
        if char then
            for _, part in ipairs(char:GetChildren()) do
                if part:IsA("BasePart") and part.CanCollide then
                    if collisionOriginal[part] == nil then collisionOriginal[part] = true end
                    part.CanCollide = false
                end
            end
        end
    end
end)

local safeCF, safeAt, lastFlingNote = nil, 0, 0
connect(RunService.Heartbeat, function()
    if not (C.AntiFling and U.Running) then safeCF = nil return end
    local hum, root = myHumanoid()
    if not (hum and root) then return end

    local allowed = C.AntiFlingSpeed
    if C.SpeedEnabled then allowed = math.max(allowed, C.SpeedValue * 1.6) end
    if C.FlyEnabled then allowed = math.max(allowed, C.FlySpeed * 1.6) end

    local vel = root.AssemblyLinearVelocity
    local speed = math.max(Vector3.new(vel.X, 0, vel.Z).Magnitude, math.max(vel.Y, 0))
    if speed > allowed or root.AssemblyAngularVelocity.Magnitude > 80 then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        if safeCF and (root.Position - safeCF.Position).Magnitude > 6 then root.CFrame = safeCF end
        if os.clock() - lastFlingNote > 2 then
            lastFlingNote = os.clock()
            notify("Anti Fling", "Cancelled a sudden launch", "warn")
        end
    elseif os.clock() - safeAt > 0.15 then
        safeCF, safeAt = root.CFrame, os.clock()
    end
end)

toggle(arSec, "Anti Ragdoll", "AntiRagdoll", false)
toggle(arSec, "Cancel Hit Stun", "AntiRagdollStun", false)

local ragSpeed, ragJump, ragScan = 16, 50, 0
renderLast(function()
    if not (C.AntiRagdoll and U.Running) then return end
    local hum, root, char = myHumanoid()
    if not (hum and root) then return end

    local ragged = char:FindFirstChild("Ragdoll") or char:FindFirstChild("RagdollSim")
    local stunned = C.AntiRagdollStun and char:FindFirstChild("Freeze")
    if not (ragged or stunned) then

        if hum.WalkSpeed > 0 then ragSpeed = hum.WalkSpeed end
        if hum.JumpPower > 0 then ragJump = hum.JumpPower end
        return
    end

    if ragged and not C.FlyEnabled then
        if hum.PlatformStand then hum.PlatformStand = false end
        local state = hum:GetState()
        if state == Enum.HumanoidStateType.FallingDown or state == Enum.HumanoidStateType.PlatformStanding
            or state == Enum.HumanoidStateType.Ragdoll then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        if root.Anchored then root.Anchored = false end
        if os.clock() - ragScan > 0.25 then
            ragScan = os.clock()
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("Motor6D") and not d.Enabled then d.Enabled = true end
            end
        end
    end
    if ragged or stunned then
        if hum.WalkSpeed < 1 then hum.WalkSpeed = C.SpeedEnabled and C.SpeedValue or ragSpeed end
        if hum.JumpPower < 1 then
            hum.UseJumpPower = true
            hum.JumpPower = C.JumpEnabled and C.JumpValue or ragJump
        end
    end
end)

toggle(avSec, "Anti Void", "AntiVoid", false)
slider(avSec, "Rescue Margin", "VoidMargin", 20, 400, 150, { Suffix = " st" })

local groundCF, groundAt, lastVoidNote = nil, 0, 0
connect(RunService.Heartbeat, function()
    if not (C.AntiVoid and U.Running) then return end
    local hum, root = myHumanoid()
    if not (hum and root) then return end

    local level = math.max(workspace.FallenPartsDestroyHeight, -1000) + C.VoidMargin
    if root.Position.Y > level + 30 and hum.FloorMaterial ~= Enum.Material.Air and os.clock() - groundAt > 0.25 then
        groundCF, groundAt = root.CFrame, os.clock()
    end

    if root.Position.Y < level then
        local dest = groundCF
        if not dest then
            local spawn = lp.RespawnLocation or workspace:FindFirstChildWhichIsA("SpawnLocation", true)
            dest = spawn and (spawn.CFrame + Vector3.new(0, 4, 0))
        end
        if dest then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = dest + Vector3.new(0, 3, 0)
            if os.clock() - lastVoidNote > 2 then
                lastVoidNote = os.clock()
                notify("Anti Void", "Pulled you back from the void", "warn")
            end
        end
    end
end)

local aaApplied
local function undoAntiAim()
    if aaApplied then
        local _, root = myHumanoid()
        if root then root.CFrame = root.CFrame * aaApplied:Inverse() end
        aaApplied = nil
    end
end
onUnload(undoAntiAim)

toggle(aaSec, "Anti Aim", "AntiAim", false, function(v) if not v then undoAntiAim() end end)
dropdown(aaSec, "Mode", "AntiAimMode", { "Jitter", "Spin", "Jitter + Spin" }, "Jitter")
slider(aaSec, "Jitter Range", "AntiAimRange", 0.5, 10, 3, { Decimals = 1, Suffix = " st" })
slider(aaSec, "Spin Amount", "AntiAimSpin", 10, 120, 60, { Suffix = "°" })

local desyncAnchor
local lagHistory = {}

toggle(dsSec, "Desync", "Desync", false, function(v)
    if v then desyncAnchor, lagHistory = nil, {} else undoAntiAim() end
end)
dropdown(dsSec, "Mode", "DesyncMode", { "Stay Here", "Behind", "Left", "Right", "Above", "Lag", "Orbit" }, "Stay Here",
    function() desyncAnchor, lagHistory = nil, {} end)
dsSec:Button({ Text = "Set Anchor Here", Callback = function() desyncAnchor = nil end })
slider(dsSec, "Stay Radius", "DesyncStayRadius", 5, 300, 120, { Suffix = " st", MaxLabel = "Infinite" })
slider(dsSec, "Distance", "DesyncDist", 1, 25, 6, { Decimals = 1, Suffix = " st" })
slider(dsSec, "Lag Time", "DesyncLag", 0.05, 1.5, 0.3, { Decimals = 2, Suffix = "s" })
slider(dsSec, "Orbit Speed", "DesyncOrbit", 0.3, 6, 2, { Decimals = 1, Suffix = "/s" })

renderFirst(undoAntiAim)

local DESYNC_DIRS = {
    Behind = Vector3.new(0, 0, 1), Left = Vector3.new(-1, 0, 0),
    Right = Vector3.new(1, 0, 0), Above = Vector3.new(0, 1, 0),
}

local function desyncShift(root)
    local mode = C.DesyncMode
    local dir = DESYNC_DIRS[mode]
    if dir then return CFrame.new(dir * C.DesyncDist) end

    if mode == "Stay Here" then

        if not desyncAnchor then desyncAnchor = root.CFrame end

        if C.DesyncStayRadius < 300 and (root.Position - desyncAnchor.Position).Magnitude > C.DesyncStayRadius then desyncAnchor = root.CFrame end
        return root.CFrame:ToObjectSpace(desyncAnchor)
    end

    if mode == "Lag" then

        local now = os.clock()
        table.insert(lagHistory, { t = now, pos = root.Position })
        local target = now - C.DesyncLag
        local keep = 1
        for i = 1, #lagHistory do
            if lagHistory[i].t <= target then keep = i else break end
        end
        for _ = 2, keep do table.remove(lagHistory, 1) end
        local a, b = lagHistory[1], lagHistory[2]
        local goal
        if a.t >= target or not b then
            goal = a.pos
        else
            goal = a.pos:Lerp(b.pos, math.clamp((target - a.t) / math.max(b.t - a.t, 1e-4), 0, 1))
        end
        return root.CFrame:ToObjectSpace(CFrame.new(goal) * root.CFrame.Rotation)
    end

    local a = os.clock() * C.DesyncOrbit * 2 * math.pi
    return CFrame.new(Vector3.new(math.cos(a), 0, math.sin(a)) * C.DesyncDist)
end

connect(RunService.Heartbeat, function()
    if not ((C.AntiAim or C.Desync) and U.Running) then return end
    local _, root = myHumanoid()
    if not root then return end
    undoAntiAim()

    local total = CFrame.new()
    if C.Desync then
        local ds = desyncShift(root)
        total = total * ds
        U.GhostCF = root.CFrame * ds
    else
        U.GhostCF = nil
    end
    if C.AntiAim then
        local mode = C.AntiAimMode
        local offset, spin = Vector3.zero, 0
        if mode ~= "Spin" then
            offset = Vector3.new(math.random() * 2 - 1, (math.random() * 2 - 1) * 0.5, math.random() * 2 - 1) * C.AntiAimRange
        end
        if mode ~= "Jitter" then
            spin = math.rad(math.random(-180, 180)) * (C.AntiAimSpin / 120)
        end
        total = total * CFrame.new(offset) * CFrame.Angles(0, spin, 0)
    end

    aaApplied = total
    root.CFrame = root.CFrame * total
end)

do
local ghost, ghostChar, ghostPairs, ghostCount = nil, nil, {}, 0
toggle(dsSec, "Show Copy", "DesyncGhost", true)

local JUNK = { "Script", "LocalScript", "ModuleScript", "Animator", "Sound", "BillboardGui", "SurfaceGui",
    "ParticleEmitter", "Beam", "Trail", "Light", "Tool", "ForceField", "Highlight" }

local function partPath(p, root)
    local names = {}
    while p and p ~= root do table.insert(names, 1, p.Name) p = p.Parent end
    return table.concat(names, "/")
end

local function destroyGhost()
    if ghost then ghost:Destroy() end
    ghost, ghostChar, ghostPairs, ghostCount = nil, nil, {}, 0
end
onUnload(destroyGhost)

local function countParts(char)
    local n = 0
    for _, d in ipairs(char:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
    return n
end

local function buildGhost(char)
    destroyGhost()
    local wasArchivable = char.Archivable
    char.Archivable = true
    local ok, copy = pcall(function() return char:Clone() end)
    char.Archivable = wasArchivable
    if not (ok and copy) then return end

    local byPath = {}
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then byPath[partPath(d, char)] = d end
    end
    local pairsList = {}
    for _, d in ipairs(copy:GetDescendants()) do
        if d:IsA("BasePart") then
            local orig = byPath[partPath(d, copy)]
            if orig then
                d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.Massless = true, false, false, false, true
                table.insert(pairsList, { o = orig, g = d })
            end
        end
    end
    for _, d in ipairs(copy:GetDescendants()) do
        for _, cls in ipairs(JUNK) do
            if d.Parent and d:IsA(cls) then d:Destroy() break end
        end
    end

    for _, d in ipairs(copy:GetDescendants()) do
        if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
            local a, b = d.Part0, d.Part1
            if (a and not a:IsDescendantOf(copy)) or (b and not b:IsDescendantOf(copy)) then d:Destroy() end
        end
    end
    local cloneHum = copy:FindFirstChildOfClass("Humanoid")
    if cloneHum then
        cloneHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        cloneHum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        cloneHum.RequiresNeck, cloneHum.BreakJointsOnDeath = false, false

        cloneHum.EvaluateStateMachine = false
    end
    for i = #pairsList, 1, -1 do
        if not pairsList[i].g:IsDescendantOf(copy) then table.remove(pairsList, i) end
    end
    copy.Name = "DesyncCopy"
    copy.Parent = workspace.CurrentCamera
    ghost, ghostChar, ghostPairs, ghostCount = copy, char, pairsList, countParts(char)
end

renderLast(function()
    if not (U.Running and C.Desync and C.DesyncGhost and U.GhostCF) then
        if ghost then destroyGhost() end
        return
    end
    local char, _, root = charOf(lp, true)
    if not char then destroyGhost() return end
    if char ~= ghostChar or not ghost or not ghost.Parent or countParts(char) ~= ghostCount then buildGhost(char) end
    if not ghost then return end

    local rel = root.CFrame:Inverse()
    for _, pr in ipairs(ghostPairs) do
        if pr.o.Parent then
            pr.g.CFrame = U.GhostCF * (rel * pr.o.CFrame)
            pr.g.CanCollide = false
        end
    end
end)
end

local playerTab = win:Tab("Player")
local tp = playerTab:Section("Teleport & Spectate")
local misc1 = playerTab:Section("Utility", "right")

local function playerNames()
    local names = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then table.insert(names, plr.Name) end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

local renderInventory
local playerDD = tp:Dropdown({ Text = "Player", Options = playerNames(), Flag = "SelectedPlayer", NoSave = true,
    Callback = function(v)
        C.SelectedPlayer = v
        if renderInventory then renderInventory() end
    end })
local orbitDD
local function refreshPlayers()
    playerDD:SetOptions(playerNames())
    if orbitDD then orbitDD:SetOptions(playerNames()) end
end
connect(Players.PlayerAdded, refreshPlayers)
connect(Players.PlayerRemoving, function() task.defer(refreshPlayers) end)

tp:Button({ Text = "Teleport To Player", Callback = function()
    local target = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    local root
    if target then
        local _, _, r = charOf(target)
        root = r
    end
    local _, myRoot = myHumanoid()
    if root and myRoot then
        myRoot.CFrame = root.CFrame * CFrame.new(0, 0, 3)
    else
        notify("Teleport", "Pick a player that is alive first", "warn")
    end
end })

toggle(tp, "Spectate Player", "Spectate", false, function(v)
    if not v then
        local hum = myHumanoid()
        if hum then cam().CameraSubject = hum end
    end
end)
renderLast(function()
    if not (C.Spectate and U.Running) then return end
    local target = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    if not target then return end
    local _, hum = charOf(target)
    if hum then cam().CameraSubject = hum end
end)

toggle(tp, "Click Teleport (hold key)", "ClickTp", false)
keybind(tp, "Click TP Key", "ClickTpKey", Enum.KeyCode.LeftControl)
connect(UserInputService.InputBegan, function(input, gp)
    if gp or not C.ClickTp or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if not (BIND.ClickTpKey and BIND.ClickTpKey:IsDown()) then return end
    local pos = UserInputService:GetMouseLocation()
    local ray = cam():ViewportPointToRay(pos.X, pos.Y)
    rayParams.FilterDescendantsInstances = { lp.Character }
    local res = workspace:Raycast(ray.Origin, ray.Direction * 2000, rayParams)
    local _, root = myHumanoid()
    if res and root then root.CFrame = CFrame.new(res.Position + Vector3.new(0, 4, 0)) end
end)

local follow = playerTab:Section("Follow Player")
local followAutoAt = 0

toggle(follow, "Follow Selected Player", "FollowEnabled", false, function(v)
    if v then followAutoAt = os.clock() end
    if v and C.OrbitEnabled and TOG.OrbitEnabled then
        C.OrbitEnabled = false
        TOG.OrbitEnabled:Set(false, true)
    end
end)
slider(follow, "Distance Behind", "FollowDist", 0, 30, 5, { Decimals = 1, Suffix = " st" })
slider(follow, "Height", "FollowHeight", -5, 15, 0, { Decimals = 1, Suffix = " st" })
toggle(follow, "Face Their Back", "FollowFace", true)
toggle(follow, "Auto Distance", "FollowAuto", false, function(v) if v then followAutoAt = os.clock() end end)
slider(follow, "Auto Far", "FollowAutoFar", 0, 30, 5, { Decimals = 1, Suffix = " st" })
slider(follow, "Auto Near", "FollowAutoNear", 0, 30, 0, { Decimals = 1, Suffix = " st" })
slider(follow, "Auto Speed", "FollowAutoSpeed", 0.1, 4, 0.6, { Decimals = 2, Suffix = "/s" })

local function followDistance()
    if not C.FollowAuto then return C.FollowDist end
    local far = math.max(C.FollowAutoFar, C.FollowAutoNear)
    local near = math.min(C.FollowAutoFar, C.FollowAutoNear)

    local wave = 0.5 + 0.5 * math.cos((os.clock() - followAutoAt) * C.FollowAutoSpeed * 2 * math.pi)
    return near + (far - near) * wave
end

renderLast(function()
    if not (C.FollowEnabled and U.Running) then return end
    local target = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    if not target then return end
    local _, _, targetRoot = charOf(target)
    local _, myRoot = myHumanoid()
    if not (targetRoot and myRoot) then return end

    local base = targetRoot.CFrame

    local pos = base:PointToWorldSpace(Vector3.new(0, C.FollowHeight, followDistance()))
    local toward = Vector3.new(base.Position.X - pos.X, 0, base.Position.Z - pos.Z)
    if C.FollowFace and toward.Magnitude > 0.05 then
        myRoot.CFrame = CFrame.lookAt(pos, pos + toward)
    else
        myRoot.CFrame = CFrame.new(pos) * base.Rotation
    end
    myRoot.AssemblyLinearVelocity = Vector3.zero
end)

local orbit = playerTab:Section("Orbit Player")
orbitDD = orbit:Dropdown({ Text = "Orbit Player", Options = playerNames(), Flag = "OrbitPlayer", NoSave = true,
    Callback = function(v) C.OrbitPlayer = v end })
toggle(orbit, "Orbit", "OrbitEnabled", false, function(v)
    if v and C.FollowEnabled and TOG.FollowEnabled then
        C.FollowEnabled = false
        TOG.FollowEnabled:Set(false, true)
    end
end)
toggle(orbit, "Lock On Target", "OrbitLock", true)
dropdown(orbit, "Orbit Mode", "OrbitMode", { "Circle", "Bobbing", "Figure Eight" }, "Circle")
slider(orbit, "Height", "OrbitHeight", -10, 30, 3, { Decimals = 1, Suffix = " st" })
slider(orbit, "Distance", "OrbitDist", 1, 40, 8, { Decimals = 1, Suffix = " st" })
slider(orbit, "Rotation Speed", "OrbitSpeed", 10, 720, 120, { Suffix = "°/s" })
toggle(orbit, "Reverse Direction", "OrbitReverse", false)

local orbitAngle = 0
renderLast(function(dt)
    if not (C.OrbitEnabled and U.Running) then return end
    local target = C.OrbitPlayer and Players:FindFirstChild(C.OrbitPlayer)
    if not target then return end
    local _, _, targetRoot = charOf(target)
    local _, myRoot = myHumanoid()
    if not (targetRoot and myRoot) then return end

    orbitAngle += math.rad(C.OrbitSpeed) * math.clamp(dt, 0, 0.1) * (C.OrbitReverse and -1 or 1)
    local r, h, a = C.OrbitDist, C.OrbitHeight, orbitAngle
    local offset
    if C.OrbitMode == "Bobbing" then
        offset = Vector3.new(math.cos(a) * r, h + math.sin(a * 2) * math.min(r * 0.4, 4), math.sin(a) * r)
    elseif C.OrbitMode == "Figure Eight" then
        offset = Vector3.new(math.cos(a) * r, h, math.sin(a * 2) * r * 0.6)
    else
        offset = Vector3.new(math.cos(a) * r, h, math.sin(a) * r)
    end

    local center = targetRoot.Position
    local pos = center + offset
    if C.OrbitLock then

        myRoot.CFrame = CFrame.lookAt(pos, center)
        local c = cam()
        c.CFrame = CFrame.lookAt(c.CFrame.Position, center)
    else
        myRoot.CFrame = CFrame.new(pos) * myRoot.CFrame.Rotation
    end
    myRoot.AssemblyLinearVelocity = Vector3.zero
end)

do
local animSec = playerTab:Section("Animations", "right")

local function setAnimateScript(disabled)
    local char = lp.Character
    local script = char and char:FindFirstChild("Animate")
    if script and script:IsA("LocalScript") then script.Disabled = disabled end
end

toggle(animSec, "No Animations", "NoAnim", false, function(v)
    if v then return end
    setAnimateScript(false)

    local hum = myHumanoid()
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            if track.Speed == 0 then track:Stop(0) end
        end
    end
end)
dropdown(animSec, "Mode", "NoAnimMode", { "Stop All", "Stop Attacks Only", "Freeze Pose" }, "Stop All")
toggle(animSec, "Disable Animate Script (Stop All)", "NoAnimScript", true)
onUnload(function() setAnimateScript(false) end)

local function suppress(track)
    local mode = C.NoAnimMode
    if mode == "Freeze Pose" then
        if track.Speed ~= 0 then track:AdjustSpeed(0) end
    elseif mode == "Stop Attacks Only" then

        local pv = track.Priority.Value
        if pv >= Enum.AnimationPriority.Action.Value and pv < Enum.AnimationPriority.Core.Value then track:Stop(0) end
    else
        track:Stop(0)
    end
end

local hooked, hookConn
local function sweep()
    if not (C.NoAnim and U.Running) then return end
    local hum = myHumanoid()
    if not hum then return end
    if C.NoAnimMode == "Stop All" and C.NoAnimScript then setAnimateScript(true) end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then return end
    if animator ~= hooked then
        if hookConn then hookConn:Disconnect() end
        hooked = animator
        hookConn = animator.AnimationPlayed:Connect(function(track)
            if C.NoAnim and U.Running then suppress(track) end
        end)
    end
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do suppress(track) end
end
onUnload(function() if hookConn then hookConn:Disconnect() end end)

renderFirst(sweep)
renderLast(sweep)
connect(RunService.Stepped, sweep)
connect(RunService.Heartbeat, sweep)
end

local inv = playerTab:Section("Inventory", "right")
toggle(inv, "Live Refresh", "InvLive", true)

local invRows = {}
for i = 1, 14 do
    invRows[i] = inv:Label("")
    invRows[i].Instance.Visible = false
end

local INV_SKIP = { Backpack = true, PlayerGui = true, PlayerScripts = true, StarterGear = true, leaderstats = true }

local function inventoryLines(plr)
    local lines = {}
    local char = plr.Character
    local held = char and char:FindFirstChildOfClass("Tool")
    table.insert(lines, plr.DisplayName .. " (" .. plr.Name .. ")")
    table.insert(lines, "Holding: " .. (held and held.Name or "nothing"))

    local bag = plr:FindFirstChildOfClass("Backpack")
    local items = {}
    if bag then
        for _, tool in ipairs(bag:GetChildren()) do table.insert(items, tool.Name) end
    end
    table.insert(lines, ("Backpack: %d item(s)"):format(#items))
    for i, name in ipairs(items) do
        if i > 7 then table.insert(lines, ("  + %d more"):format(#items - 7)) break end
        table.insert(lines, "  - " .. name)
    end

    for _, child in ipairs(plr:GetChildren()) do
        if not INV_SKIP[child.Name] and (child:IsA("Folder") or child:IsA("Configuration")) then
            local n = #child:GetChildren()
            if n > 0 then table.insert(lines, ("%s: %d entries"):format(child.Name, n)) end
        end
    end
    return lines
end

renderInventory = function()
    local plr = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    local lines = plr and inventoryLines(plr) or { "Pick a player above" }
    for i, row in ipairs(invRows) do
        local text = lines[i]
        row.Instance.Visible = text ~= nil
        if text then row:Set(text) end
    end
end

local invAccum = 0
connect(RunService.Heartbeat, function(dt)
    if not (C.InvLive and U.Running) then return end
    invAccum += dt
    if invAccum >= 0.5 then invAccum = 0 renderInventory() end
end)
renderInventory()

toggle(misc1, "Anti AFK", "AntiAfk", true)
connect(lp.Idled, function()
    if not C.AntiAfk then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end)
end)

misc1:Button({ Text = "Rejoin Server", Callback = function()
    pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, lp) end)
end })

misc1:Button({ Text = "Server Hop", Callback = function()
    notify("Server Hop", "Searching for a smaller server...")
    task.spawn(function()
        local ok, err = pcall(function()
            local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
            local data = HttpService:JSONDecode(game:HttpGet(url))
            for _, server in ipairs(data.data or {}) do
                if server.id ~= game.JobId and server.playing < server.maxPlayers then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, lp)
                    return
                end
            end
            error("no other server found")
        end)
        if not ok then notify("Server Hop", tostring(err), "error") end
    end)
end })

do
local listSec = playerTab:Section("Whitelist & Blacklist", "right")
local whiteDD, blackDD

local function presentNames()
    local present = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then present[plr.Name] = true end
    end
    return present
end

local function pickedOf(set)
    local picked, present = {}, presentNames()
    for name in pairs(set) do
        if present[name] then table.insert(picked, name) end
    end
    table.sort(picked, function(a, b) return a:lower() < b:lower() end)
    return picked
end

local function takePicks(set, other, picks)
    local present = presentNames()
    for name in pairs(set) do
        if present[name] then set[name] = nil end
    end
    for _, name in ipairs(picks) do
        set[name] = true
        other[name] = nil
    end
end

local function syncSelections()
    if whiteDD then whiteDD:Set(pickedOf(U.White), true) end
    if blackDD then blackDD:Set(pickedOf(U.Black), true) end
end

whiteDD = listSec:Dropdown({ Text = "Whitelist (friends)", Options = playerNames(), Multi = true, Flag = "ListWhite",
    Callback = function(picks) takePicks(U.White, U.Black, picks) syncSelections() end })
blackDD = listSec:Dropdown({ Text = "Blacklist (targets)", Options = playerNames(), Multi = true, Flag = "ListBlack",
    Callback = function(picks) takePicks(U.Black, U.White, picks) syncSelections() end })

local function refreshLists()
    whiteDD:SetOptions(playerNames())
    blackDD:SetOptions(playerNames())
    syncSelections()
end
connect(Players.PlayerAdded, refreshLists)
connect(Players.PlayerRemoving, function() task.defer(refreshLists) end)

listSec:Button({ Text = "Refresh Player List", Callback = refreshLists })
listSec:Button({ Text = "Clear Whitelist", Callback = function() table.clear(U.White) syncSelections() end })
listSec:Button({ Text = "Clear Blacklist", Callback = function() table.clear(U.Black) syncSelections() end })
toggle(listSec, "Skip Whitelisted Players", "ListRespectWhite", true)
toggle(listSec, "Target Blacklisted First", "ListBlackFirst", true)
toggle(listSec, "Only Target Blacklist", "ListOnlyBlack", false)

local function whitelistFriends()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and not U.White[plr.Name] then
            local ok, isFriend = pcall(lp.IsFriendsWith, lp, plr.UserId)
            if ok and isFriend then
                U.White[plr.Name] = true
                U.Black[plr.Name] = nil
            end
        end
    end
    syncSelections()
end
toggle(listSec, "Auto-Whitelist Roblox Friends", "AutoWhiteFriends", false, function(v)
    if v then task.spawn(whitelistFriends) end
end)
connect(Players.PlayerAdded, function()
    if C.AutoWhiteFriends then task.delay(1, whitelistFriends) end
end)
end

do
local flingTab = win:Tab("Fling")
local flg = flingTab:Section("Fling")
local flgTune = flingTab:Section("Tuning", "right")
local vsp = flingTab:Section("Void Spam")

local flingToken, flingBusy = 0, false

local function stopFling() flingToken += 1 end
onUnload(stopFling)

local function isProtected(plr)
    return (C.ListRespectWhite and U.White[plr.Name]) or (C.FlingSkipTeam and sameTeam(plr))
end

local function goHome(origin)
    for _ = 1, 3 do
        local hum, myRoot = myHumanoid()
        if myRoot then
            myRoot.AssemblyLinearVelocity = Vector3.zero
            myRoot.AssemblyAngularVelocity = Vector3.zero
            myRoot.CFrame = origin
        end
        if hum and cam() then cam().CameraSubject = hum end
        RunService.Heartbeat:Wait()
    end
end

connect(RunService.Stepped, function()
    if not (flingBusy and U.Running) then return end
    local _, _, char = myHumanoid()
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = false end
    end
end)

local function voidLine() return math.max(workspace.FallenPartsDestroyHeight, -1000) + C.VoidDepth end

local function attack(target, void, token)
    local _, _, root0 = charOf(target)
    if not root0 then return "gone" end
    local startPos, startAt = root0.Position, os.clock()
    local limit = void and C.VoidTime or C.FlingTime

    while flingToken == token and U.Running do
        RunService.Heartbeat:Wait()
        local hum, myRoot = myHumanoid()
        local _, tHum, tRoot = charOf(target)
        if not (hum and myRoot) then return "me" end
        if not tRoot then return "gone" end

        if void then
            if tRoot.Position.Y < voidLine() then return "done" end
        elseif (tRoot.Position - startPos).Magnitude > 120 or tRoot.AssemblyLinearVelocity.Magnitude > 400 then
            return "done"
        end
        if os.clock() - startAt > limit then return "timeout" end

        if C.FlingCamera then cam().CameraSubject = tHum end

        local p = void and C.VoidPower or C.FlingPower
        local pos = tRoot.Position + tRoot.AssemblyLinearVelocity * 0.08 + Vector3.new(0, (math.random() - 0.5) * 2, 0)
        local dir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
        dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.xAxis
        local push = void and (dir * p * C.VoidSide + Vector3.new(0, -p * C.VoidDrop, 0))
            or Vector3.new(dir.X * p, p, dir.Z * p)

        myRoot.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(math.random(0, 359)), 0, math.rad(math.random(0, 359)))
        myRoot.AssemblyLinearVelocity = push
        myRoot.AssemblyAngularVelocity = Vector3.new(p, p, p)
        RunService.RenderStepped:Wait()
        myRoot = select(2, myHumanoid())
        if myRoot then
            myRoot.AssemblyLinearVelocity = Vector3.zero
            myRoot.AssemblyAngularVelocity = Vector3.zero
        end
    end
    return "cancel"
end

local function startJob(name, body)
    if flingBusy then
        notify(name, "Something is already running - press Stop first", "warn")
        return false
    end
    local _, myRoot = myHumanoid()
    if not myRoot then
        notify(name, "You need a character first", "warn")
        return false
    end
    flingToken += 1
    local token, origin = flingToken, myRoot.CFrame
    flingBusy = true
    task.spawn(function()
        local ok, err = pcall(body, token, origin)
        if not ok then notify(name, tostring(err), "error") end
        goHome(origin)
        flingBusy = false

        for _, key in ipairs({ "VoidSpam", "FlingLoop" }) do
            if C[key] and TOG[key] then
                C[key] = false
                TOG[key]:Set(false, true)
            end
        end
    end)
    return true
end

local function selectedTarget(name)
    local target = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    if not target then
        notify(name, "Pick a player on the Player tab first", "warn")
    elseif isProtected(target) then
        notify(name, target.DisplayName .. " is protected (whitelist / team)", "warn")
        return nil
    end
    return target
end

local RESULT_TEXT = {
    done = "launched", gone = "not alive right now", timeout = "no luck (try more Power / Time)",
    me = "you have no character", cancel = "stopped",
}

flg:Button({ Text = "Fling Selected Player", Callback = function()
    local target = selectedTarget("Fling")
    if not target then return end
    startJob("Fling", function(token, origin)
        local res = attack(target, false, token)
        notify("Fling", target.DisplayName .. ": " .. RESULT_TEXT[res], res == "done" and "success" or "warn")
    end)
end })

local function targetList(mode)
    local list = {}
    if mode == "Selected" then
        local plr = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
        if plr and not isProtected(plr) then list[1] = plr end
        return list
    end

    local _, myRoot = myHumanoid()
    local myPos = myRoot and myRoot.Position or Vector3.zero
    local dist = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and not isProtected(plr) and (mode ~= "Blacklist Only" or U.Black[plr.Name]) then
            local _, _, root = charOf(plr)
            if root then
                dist[plr] = (root.Position - myPos).Magnitude
                table.insert(list, plr)
            end
        end
    end
    table.sort(list, function(a, b)
        if C.ListBlackFirst and U.Black[a.Name] ~= U.Black[b.Name] then return U.Black[a.Name] == true end
        return dist[a] < dist[b]
    end)
    if mode == "Nearest" and #list > 1 then list = { list[1] } end
    return list
end

local function flingPass(token)
    local hit, tried = 0, 0
    for _, plr in ipairs(targetList("All")) do
        if flingToken ~= token or not U.Running then break end
        if charOf(plr) then
            tried += 1
            if attack(plr, false, token) == "done" then hit += 1 end
        end
    end
    return hit, tried
end

flg:Button({ Text = "Fling All", Callback = function()
    startJob("Fling All", function(token)
        local hit, tried = flingPass(token)
        notify("Fling All", ("Launched %d of %d players"):format(hit, tried), hit > 0 and "success" or "warn")
    end)
end })

toggle(flg, "Loop Fling All", "FlingLoop", false, function(v)
    if not v then stopFling() return end
    if not startJob("Fling All", function(token)
        while flingToken == token and U.Running do
            flingPass(token)
            task.wait(C.FlingLoopDelay)
        end
    end) then
        C.FlingLoop = false
        if TOG.FlingLoop then TOG.FlingLoop:Set(false, true) end
    end
end)
slider(flg, "Loop Pause", "FlingLoopDelay", 0.1, 10, 1, { Decimals = 1, Suffix = " s" })

flg:Button({ Text = "Stop", Callback = function() stopFling() end })

local function voidJob(token, origin)
    local kills = 0
    while flingToken == token and U.Running do
        local list = targetList(C.VoidTargets)
        if #list == 0 then
            if C.VoidTargets == "Selected" and not (C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)) then
                notify("Void Spam", "Player left the server", "warn")
                break
            end
            task.wait(0.5)
        else
            for _, plr in ipairs(list) do
                if flingToken ~= token or not U.Running then break end
                local _, _, root = charOf(plr)
                if root and root.Position.Y >= voidLine() then
                    local res = attack(plr, true, token)
                    if res == "cancel" then return end
                    goHome(origin)
                    if res == "done" then
                        kills += 1
                        if C.VoidNotify then
                            notify("Void Spam", ("%s sent to the void (%d total)"):format(plr.DisplayName, kills), "success")
                        end
                        task.wait(C.VoidGap)
                    end
                end
            end
            task.wait(C.VoidDelay)
        end
    end
end

toggle(vsp, "Void Spam", "VoidSpam", false, function(v)
    if not v then stopFling() return end
    local ok = true
    if C.VoidTargets == "Selected" then ok = selectedTarget("Void Spam") ~= nil end
    if ok then ok = startJob("Void Spam", voidJob) end
    if not ok then
        C.VoidSpam = false
        if TOG.VoidSpam then TOG.VoidSpam:Set(false, true) end
    end
end)
dropdown(vsp, "Targets", "VoidTargets", { "Selected", "All", "Nearest", "Blacklist Only" }, "Selected")
slider(vsp, "Delay Between Targets", "VoidGap", 0, 5, 0.3, { Decimals = 1, Suffix = " s" })
slider(vsp, "Delay Between Rounds", "VoidDelay", 0, 5, 0.5, { Decimals = 1, Suffix = " s" })
toggle(vsp, "Notify Each Kill", "VoidNotify", false)

slider(flgTune, "Fling Power", "FlingPower", 10000, 1000000, 100000)
slider(flgTune, "Fling Time Per Player", "FlingTime", 1, 15, 5, { Decimals = 1, Suffix = " s" })
slider(flgTune, "Void Power", "VoidPower", 10000, 1000000, 100000)
slider(flgTune, "Void Time Per Player", "VoidTime", 1, 15, 6, { Decimals = 1, Suffix = " s" })
slider(flgTune, "Void Depth", "VoidDepth", 20, 400, 80, { Suffix = " st" })
slider(flgTune, "Downward Force", "VoidDrop", 0, 2, 1, { Decimals = 1, Suffix = "x" })
slider(flgTune, "Sideways Force", "VoidSide", 0, 2, 1, { Decimals = 1, Suffix = "x" })
toggle(flgTune, "Camera Follows Target", "FlingCamera", true)
toggle(flgTune, "Skip Teammates", "FlingSkipTeam", false)
end

do
local avatarTab = win:Tab("Avatar")
local avPlayer = avatarTab:Section("Copy Player")
local avUser = avatarTab:Section("Copy By Username", "right")

local APPEAR = { Accessory = true, Shirt = true, Pants = true, ShirtGraphic = true, BodyColors = true, CharacterMesh = true }
local JUNK_CLASSES = { "Script", "LocalScript", "ModuleScript", "Sound", "ParticleEmitter", "BillboardGui", "SurfaceGui" }

local function tidy(inst)
    local doomed = {}
    for _, d in ipairs(inst:GetDescendants()) do
        local bad = d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint")
        if not bad then
            for _, cls in ipairs(JUNK_CLASSES) do
                if d:IsA(cls) then bad = true break end
            end
        end
        if bad then table.insert(doomed, d) end
    end
    for _, d in ipairs(doomed) do pcall(function() d:Destroy() end) end
end

local function safeClone(inst)
    local was = inst.Archivable
    inst.Archivable = true
    local ok, c = pcall(function() return inst:Clone() end)
    inst.Archivable = was
    if ok and c then tidy(c) return c end
end

local DECOR = { Decal = true, Texture = true, SpecialMesh = true, SurfaceAppearance = true }

local function insideAccessory(inst, char)
    local p = inst.Parent
    while p and p ~= char do
        if p:IsA("Accessory") then return true end
        p = p.Parent
    end
    return false
end

local function pathOf(inst, char)
    local names = {}
    local p = inst.Parent
    while p and p ~= char do table.insert(names, 1, p.Name) p = p.Parent end
    return table.concat(names, "/")
end

local function findByPath(char, path)
    local cur = char
    for name in path:gmatch("[^/]+") do
        cur = cur and cur:FindFirstChild(name)
    end
    return cur
end

local function takeSnapshot(char)
    local snap = { items = {}, decor = {}, colors = {} }
    for _, d in ipairs(char:GetDescendants()) do
        if APPEAR[d.ClassName] and not insideAccessory(d, char) then
            local c = safeClone(d)
            if c then table.insert(snap.items, { inst = c, host = pathOf(d, char) }) end
        elseif DECOR[d.ClassName] and d.Parent:IsA("BasePart") and not insideAccessory(d, char) then
            local c = safeClone(d)
            if c then table.insert(snap.decor, { path = pathOf(d, char), inst = c }) end
        elseif d:IsA("BasePart") and not insideAccessory(d, char) then
            snap.colors[(pathOf(d, char) ~= "" and (pathOf(d, char) .. "/") or "") .. d.Name] = d.Color
        end
    end
    return snap
end

local function attachAccessory(acc, host, char)
    local handle = acc:FindFirstChild("Handle")
    local hAtt = handle and handle:FindFirstChildOfClass("Attachment")
    if not hAtt then return end
    local target = host and host:FindFirstChild(hAtt.Name)
    if not (target and target:IsA("Attachment")) then
        local head = char:FindFirstChild("Head")
        target = head and head:FindFirstChild(hAtt.Name)
    end
    if not (target and target:IsA("Attachment")) then
        target = nil
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("Attachment") and d.Name == hAtt.Name and not insideAccessory(d, char) then target = d break end
        end
    end
    if not target then return end
    local w = Instance.new("Weld")
    w.Name = "AccessoryWeld"
    w.Part0, w.Part1 = handle, target.Parent
    w.C0, w.C1 = hAtt.CFrame, target.CFrame
    w.Parent = handle
end

local function applySnapshot(snap)
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (char and hum) then return false end

    local doomed = {}
    for _, d in ipairs(char:GetDescendants()) do
        if (APPEAR[d.ClassName] and not insideAccessory(d, char))
            or (DECOR[d.ClassName] and d.Parent:IsA("BasePart") and not insideAccessory(d, char)) then
            table.insert(doomed, d)
        end
    end
    for _, d in ipairs(doomed) do pcall(function() d:Destroy() end) end
    for _, e in ipairs(snap.items) do
        local n = e.inst:Clone()
        local host = e.host ~= "" and findByPath(char, e.host) or nil
        n.Parent = (host and host:IsA("BasePart")) and host or char
        if n:IsA("Accessory") then attachAccessory(n, host, char) end
    end
    for _, e in ipairs(snap.decor) do
        local part = findByPath(char, e.path)
        if part and part:IsA("BasePart") then e.inst:Clone().Parent = part end
    end
    for path, col in pairs(snap.colors) do
        local p = findByPath(char, path)
        if p and p:IsA("BasePart") then p.Color = col end
    end
    return true
end

local mine
local worn
local wornName

local function wear(snap, label)
    if not lp.Character then notify("Avatar", "No character yet", "warn") return end
    if not mine then mine = takeSnapshot(lp.Character) end
    if applySnapshot(snap) then
        worn, wornName = snap, label
        notify("Avatar", "You are now a copy of " .. label, "success")
    end
end

local function restore()
    if not (worn and mine) then notify("Avatar", "You are already yourself", "warn") return end
    applySnapshot(mine)
    worn, wornName, mine = nil, nil, nil
    notify("Avatar", "Your own look is back", "success")
end
onUnload(function() if worn and mine then pcall(applySnapshot, mine) end end)

connect(lp.CharacterAdded, function(char)
    local keep, snap, label = C.AvatarKeep, worn, wornName
    mine = nil
    if not (keep and snap) then worn, wornName = nil, nil return end
    task.spawn(function()
        char:WaitForChild("Humanoid", 10)
        task.wait(2)
        if lp.Character ~= char or not U.Running then return end
        mine = takeSnapshot(char)
        applySnapshot(snap)
    end)
end)

local avSelected
local avDD
local function refreshAvatarPlayers()
    if avDD then avDD:SetOptions(playerNames()) end
end
avDD = avPlayer:Dropdown({ Text = "Player", Options = playerNames(), Flag = "AvatarPlayer", NoSave = true,
    Callback = function(v) avSelected = v end })
connect(Players.PlayerAdded, refreshAvatarPlayers)
connect(Players.PlayerRemoving, function() task.defer(refreshAvatarPlayers) end)
avPlayer:Button({ Text = "Refresh Player List", Callback = refreshAvatarPlayers })
avPlayer:Button({ Text = "Copy Avatar", Callback = function()
    local plr = avSelected and Players:FindFirstChild(avSelected)
    if not (plr and plr.Character) then notify("Avatar", "Pick a player that has a character first", "warn") return end
    wear(takeSnapshot(plr.Character), plr.DisplayName)
end })
avPlayer:Button({ Text = "Restore My Avatar", Callback = restore })
toggle(avPlayer, "Keep Look After Respawn", "AvatarKeep", true)

local avName = ""
avUser:TextBox({ Text = "Username or UserId", Placeholder = "e.g. Roblox", Flag = "AvatarName", NoSave = true,
    Callback = function(t) avName = t or "" end })
avUser:Button({ Text = "Copy By Username", Callback = function()
    local name = (avName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then notify("Avatar", "Type a username or UserId first", "warn") return end
    task.spawn(function()
        local id = tonumber(name)
        if not id then
            local ok, res = pcall(function() return Players:GetUserIdFromNameAsync(name) end)
            if not (ok and res) then notify("Avatar", "User '" .. name .. "' was not found", "error") return end
            id = res
        end
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        local ok, model = pcall(function()
            local desc = Players:GetHumanoidDescriptionFromUserId(id)
            return Players:CreateHumanoidModelFromDescription(desc, hum and hum.RigType or Enum.HumanoidRigType.R15)
        end)
        if not (ok and model) then notify("Avatar", "Could not load that avatar (" .. tostring(model) .. ")", "error") return end
        local snap = takeSnapshot(model)
        model:Destroy()
        wear(snap, name)
    end)
end })
avUser:Button({ Text = "Restore My Avatar", Callback = restore })
end

local miscTab = win:Tab("Misc")
local perf = miscTab:Section("Performance")
local tools = miscTab:Section("Tools", "right")

local savedQuality, savedShadows
toggle(perf, "FPS Boost", "FpsBoost", false, function(v)
    if v then
        savedShadows = Lighting.GlobalShadows
        pcall(function() savedQuality = settings().Rendering.QualityLevel end)
        Lighting.GlobalShadows = false
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
        pcall(function() workspace.Terrain.Decoration = false end)
    else
        if savedShadows ~= nil then Lighting.GlobalShadows = savedShadows end
        if savedQuality then pcall(function() settings().Rendering.QualityLevel = savedQuality end) end
        pcall(function() workspace.Terrain.Decoration = true end)
    end
end)
if hasFn("setfpscap") then
    slider(perf, "FPS Cap (0 = off)", "FpsCap", 0, 360, 0, { OnChange = function(v) pcall(setfpscap, v) end })
end

tools:Button({ Text = "Load Infinite Yield", Callback = function()
    notify("Infinite Yield", "Loading...")
    task.spawn(function()
        local ok, err = pcall(function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
        end)
        if not ok then notify("Infinite Yield", tostring(err), "error") end
    end)
end })
tools:Button({ Text = "Copy Game Info", Callback = function()
    if hasFn("setclipboard") then
        setclipboard(("PlaceId: %d\nGameId: %d\nJobId: %s"):format(game.PlaceId, game.GameId, game.JobId))
        notify("Copied", "Game info is on your clipboard", "success")
    end
end })

;(function()
local uniTab = miscTab
local cleanSec = uniTab:Section("Clean Visuals")
local camSec = uniTab:Section("Camera", "right")
local wpSec = uniTab:Section("Waypoints")
local hudSec = uniTab:Section("Stats HUD", "right")

local EFFECT_CLASSES = {
    BlurEffect = true, DepthOfFieldEffect = true, BloomEffect = true,
    ColorCorrectionEffect = true, SunRaysEffect = true,
}
local effectOrig = setmetatable({}, { __mode = "k" })
local atmoOrig = setmetatable({}, { __mode = "k" })
local vfxOrig = setmetatable({}, { __mode = "k" })
local fogOrig

local function isVfx(inst)
    return inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles")
end

local function hideVfx(inst)
    local saved = vfxOrig[inst]
    if not saved then
        saved = { Enabled = inst.Enabled }
        if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") then saved.Transparency = inst.Transparency end
        vfxOrig[inst] = saved
    end
    inst.Enabled = false
    if saved.Transparency then inst.Transparency = NumberSequence.new(1) end
end

local function applyEffects()
    for _, parent in ipairs({ Lighting, cam() }) do
        if parent then
            for _, inst in ipairs(parent:GetChildren()) do
                if EFFECT_CLASSES[inst.ClassName] then
                    if effectOrig[inst] == nil then effectOrig[inst] = inst.Enabled end
                    if inst.Enabled then inst.Enabled = false end
                end
            end
        end
    end
end

local function restoreEffects()
    for inst, was in pairs(effectOrig) do
        pcall(function() inst.Enabled = was end)
        effectOrig[inst] = nil
    end
end

local function applyFog()
    if not fogOrig then fogOrig = { FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd } end
    Lighting.FogStart, Lighting.FogEnd = 1e6, 1e6
    for _, a in ipairs(Lighting:GetChildren()) do
        if a:IsA("Atmosphere") then
            if not atmoOrig[a] then atmoOrig[a] = { Density = a.Density, Haze = a.Haze } end
            a.Density, a.Haze = 0, 0
        end
    end
end

local function restoreFog()
    if fogOrig then
        pcall(function() Lighting.FogStart, Lighting.FogEnd = fogOrig.FogStart, fogOrig.FogEnd end)
        fogOrig = nil
    end
    for a, saved in pairs(atmoOrig) do
        pcall(function() a.Density, a.Haze = saved.Density, saved.Haze end)
        atmoOrig[a] = nil
    end
end

local function restoreVfx()
    for inst, saved in pairs(vfxOrig) do
        pcall(function()
            inst.Enabled = saved.Enabled
            if saved.Transparency then inst.Transparency = saved.Transparency end
        end)
        vfxOrig[inst] = nil
    end
end

toggle(cleanSec, "Remove Screen Effects", "CleanEffects", false, function(v)
    if v then applyEffects() else restoreEffects() end
end)
toggle(cleanSec, "Remove Fog & Atmosphere", "CleanFog", false, function(v)
    if v then applyFog() else restoreFog() end
end)
toggle(cleanSec, "Remove Particles & Trails", "CleanParticles", false, function(v)
    if not v then restoreVfx() return end
    task.spawn(function()
        local n = 0
        for _, d in ipairs(workspace:GetDescendants()) do
            if not (C.CleanParticles and U.Running) then return end
            if isVfx(d) then hideVfx(d) end
            n += 1
            if n % 3000 == 0 then task.wait() end
        end
    end)
end)
toggle(cleanSec, "No Camera Shake", "CleanShake", false)
onUnload(function() restoreEffects() restoreFog() restoreVfx() end)

connect(workspace.DescendantAdded, function(inst)
    if C.CleanParticles and U.Running and isVfx(inst) then hideVfx(inst) end
end)

local cleanAt = 0
renderLast(function(dt)
    if not U.Running then return end
    if C.CleanShake then
        local hum = myHumanoid()
        if hum and hum.CameraOffset ~= Vector3.zero then hum.CameraOffset = Vector3.zero end
    end
    cleanAt += dt
    if cleanAt < 0.3 then return end
    cleanAt = 0

    if C.CleanEffects then applyEffects() end
    if C.CleanFog then applyFog() end
    if C.CleanParticles then
        for inst in pairs(vfxOrig) do
            if inst.Parent and inst.Enabled then inst.Enabled = false end
        end
    end
end)

local ContextActionService = game:GetService("ContextActionService")
local FC_KEYS = {
    Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.E, Enum.KeyCode.Q,
    Enum.KeyCode.Space, Enum.KeyCode.LeftControl, Enum.KeyCode.LeftShift,
}
local fc = { pos = Vector3.zero, yaw = 0, pitch = 0, saved = nil }

local function fcStop()
    ContextActionService:UnbindAction("TerkanFreecam")
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    local c = cam()
    if c and fc.saved then
        c.CameraType = fc.saved.Type
        local hum = myHumanoid()
        c.CameraSubject = hum or fc.saved.Subject
    end
    fc.saved = nil
end
onUnload(fcStop)

toggle(camSec, "Freecam", "Freecam", false, function(v)
    if not v then fcStop() return end
    local c = cam()
    fc.saved = { Type = c.CameraType, Subject = c.CameraSubject }
    fc.pos = c.CFrame.Position
    fc.pitch, fc.yaw = c.CFrame:ToOrientation()
    ContextActionService:BindActionAtPriority("TerkanFreecam", function() return Enum.ContextActionResult.Sink end,
        false, Enum.ContextActionPriority.High.Value, table.unpack(FC_KEYS))
end)
slider(camSec, "Freecam Speed", "FreecamSpeed", 5, 300, 40, { Suffix = " st/s" })
slider(camSec, "Look Sensitivity", "FreecamSens", 0.1, 3, 1, { Decimals = 1, Suffix = "x" })

renderLast(function(dt)
    if not (C.Freecam and U.Running) then return end
    local c = cam()
    c.CameraType = Enum.CameraType.Scriptable
    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
        local d = UserInputService:GetMouseDelta()
        fc.yaw -= d.X * 0.003 * C.FreecamSens
        fc.pitch = math.clamp(fc.pitch - d.Y * 0.003 * C.FreecamSens, -1.5, 1.5)
    else
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end

    local rot = CFrame.fromOrientation(fc.pitch, fc.yaw, 0)
    local move = Vector3.zero
    if not UserInputService:GetFocusedTextBox() then
        local function down(key) return UserInputService:IsKeyDown(key) end
        if down(Enum.KeyCode.W) then move += Vector3.new(0, 0, -1) end
        if down(Enum.KeyCode.S) then move += Vector3.new(0, 0, 1) end
        if down(Enum.KeyCode.A) then move += Vector3.new(-1, 0, 0) end
        if down(Enum.KeyCode.D) then move += Vector3.new(1, 0, 0) end
        if down(Enum.KeyCode.E) or down(Enum.KeyCode.Space) then move += Vector3.new(0, 1, 0) end
        if down(Enum.KeyCode.Q) or down(Enum.KeyCode.LeftControl) then move += Vector3.new(0, -1, 0) end
    end
    local speed = C.FreecamSpeed * (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 3 or 1)
    fc.pos += rot:VectorToWorldSpace(move) * speed * math.clamp(dt, 0, 0.1)
    c.CFrame = CFrame.new(fc.pos) * rot
end)

local zoomOrig
toggle(camSec, "Unlimited Zoom", "ZoomUnlock", false, function(v)
    if v and not zoomOrig then
        zoomOrig = { Max = lp.CameraMaxZoomDistance, Min = lp.CameraMinZoomDistance }
    elseif not v and zoomOrig then
        lp.CameraMaxZoomDistance, lp.CameraMinZoomDistance = zoomOrig.Max, zoomOrig.Min
        zoomOrig = nil
    end
end)
slider(camSec, "Max Zoom", "ZoomMax", 20, 2000, 500, { Suffix = " st" })
onUnload(function()
    if zoomOrig then pcall(function() lp.CameraMaxZoomDistance, lp.CameraMinZoomDistance = zoomOrig.Max, zoomOrig.Min end) end
end)
renderLast(function()
    if not (C.ZoomUnlock and U.Running) then return end
    lp.CameraMaxZoomDistance = C.ZoomMax
    lp.CameraMinZoomDistance = 0
end)

local WP_FILE = "TerkanWaypoints_" .. tostring(game.PlaceId) .. ".json"
local waypoints = {}
if readfile and isfile then
    pcall(function()
        if isfile(WP_FILE) then waypoints = HttpService:JSONDecode(readfile(WP_FILE)) end
    end)
end
local function saveWaypoints()
    if writefile then pcall(writefile, WP_FILE, HttpService:JSONEncode(waypoints)) end
end
local function wpNames()
    local names = {}
    for name in pairs(waypoints) do table.insert(names, name) end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

local wpName, wpSel = "", nil
local wpDD
wpSec:TextBox({ Text = "Name", Placeholder = "e.g. spawn", Flag = "WaypointName", NoSave = true,
    Callback = function(t) wpName = t or "" end })
wpDD = wpSec:Dropdown({ Text = "Waypoint", Options = wpNames(), Flag = "WaypointSel", NoSave = true,
    Callback = function(v) wpSel = v end })

wpSec:Button({ Text = "Save Current Position", Callback = function()
    local _, root = myHumanoid()
    if not root then notify("Waypoints", "You need a character first", "warn") return end
    local name = wpName:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Spot " .. (#wpNames() + 1) end
    waypoints[name] = { root.CFrame:GetComponents() }
    saveWaypoints()
    wpDD:SetOptions(wpNames())
    notify("Waypoints", "Saved \"" .. name .. "\"", "success")
end })
wpSec:Button({ Text = "Teleport To Waypoint", Callback = function()
    local data = wpSel and waypoints[wpSel]
    local _, root = myHumanoid()
    if not (data and root) then notify("Waypoints", "Pick a waypoint first", "warn") return end
    root.CFrame = CFrame.new(table.unpack(data))
    root.AssemblyLinearVelocity = Vector3.zero
end })
wpSec:Button({ Text = "Delete Waypoint", Callback = function()
    if not (wpSel and waypoints[wpSel]) then notify("Waypoints", "Pick a waypoint first", "warn") return end
    waypoints[wpSel] = nil
    wpSel = nil
    saveWaypoints()
    wpDD:SetOptions(wpNames())
end })

local HUD_CORNERS = {
    ["Top Left"] = { Vector2.new(0, 0), UDim2.new(0, 8, 0, 8) },
    ["Top Right"] = { Vector2.new(1, 0), UDim2.new(1, -8, 0, 8) },
    ["Bottom Left"] = { Vector2.new(0, 1), UDim2.new(0, 8, 1, -8) },
    ["Bottom Right"] = { Vector2.new(1, 1), UDim2.new(1, -8, 1, -8) },
}
local hudGui, hudLbl
local hudTime, hudFrames = 0, 0

local function destroyHud()
    if hudGui then hudGui:Destroy() end
    hudGui, hudLbl = nil, nil
end
onUnload(destroyHud)

local function buildHud()
    hudGui = Instance.new("ScreenGui")
    hudGui.Name = "TerkanStats"
    hudGui.ResetOnSpawn = false
    hudGui.IgnoreGuiInset = true
    hudGui.DisplayOrder = 100
    hudGui.Parent = parentGui()

    hudLbl = Instance.new("TextLabel")
    hudLbl.BackgroundColor3 = Color3.new(0, 0, 0)
    hudLbl.BackgroundTransparency = 0.45
    hudLbl.TextColor3 = Color3.new(1, 1, 1)
    hudLbl.Font = Enum.Font.Code
    hudLbl.TextSize = 14
    hudLbl.AutomaticSize = Enum.AutomaticSize.XY
    hudLbl.Size = UDim2.fromOffset(0, 0)
    hudLbl.Text = "..."
    hudLbl.Parent = hudGui
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
    pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
    pad.Parent = hudLbl
    Instance.new("UICorner", hudLbl).CornerRadius = UDim.new(0, 5)
end

toggle(hudSec, "Show FPS / Ping / Players", "StatsHud", false, function(v) if not v then destroyHud() end end)
dropdown(hudSec, "Corner", "HudCorner", { "Top Left", "Top Right", "Bottom Left", "Bottom Right" }, "Top Right")

connect(RunService.RenderStepped, function(dt)
    if not (C.StatsHud and U.Running) then return end
    if not hudGui then buildHud() end
    hudTime += dt
    hudFrames += 1
    if hudTime < 0.5 then return end
    local fps = math.floor(hudFrames / hudTime + 0.5)
    hudTime, hudFrames = 0, 0

    local ping = "?"
    pcall(function()
        ping = tostring(math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5))
    end)
    local corner = HUD_CORNERS[C.HudCorner] or HUD_CORNERS["Top Right"]
    hudLbl.AnchorPoint, hudLbl.Position = corner[1], corner[2]
    hudLbl.Text = ("FPS %d  |  Ping %s ms  |  Players %d/%d"):format(fps, ping, #Players:GetPlayers(), Players.MaxPlayers)
end)
end)()

;(function()
local cfSec = moveTab:Section("CFrame Speed")
local cfFlySec = moveTab:Section("CFrame Fly & Dash", "right")

local function keyDown(key)
    return not UserInputService:GetFocusedTextBox() and UserInputService:IsKeyDown(key)
end

toggle(cfSec, "CFrame Speed", "CfSpeed", false)
slider(cfSec, "Extra Speed", "CfSpeedValue", 0, 300, 30, { Suffix = " st/s" })
slider(cfSec, "Acceleration Time", "CfAccel", 0, 1, 0.1, { Decimals = 2, Suffix = " s" })
toggle(cfSec, "Only While Holding Key", "CfSpeedHold", false)
keybind(cfSec, "Speed Hold Key", "CfSpeedKey", nil)
slider(cfSec, "Sprint Multiplier", "CfSprint", 1, 5, 2, { Decimals = 1, Suffix = "x" })
keybind(cfSec, "Sprint Key", "CfSprintKey", nil)
toggle(cfSec, "Only On The Ground", "CfGroundOnly", false)
toggle(cfSec, "Stop At Walls", "CfWallCheck", true)

toggle(cfFlySec, "CFrame Fly", "CfFly", false)
slider(cfFlySec, "Fly Speed", "CfFlySpeed", 5, 500, 60, { Suffix = " st/s" })
slider(cfFlySec, "Vertical Multiplier", "CfFlyVert", 0.2, 3, 1, { Decimals = 1, Suffix = "x" })
toggle(cfFlySec, "Fly Toward Camera Pitch", "CfFlyPitch", true)
toggle(cfFlySec, "Face Fly Direction", "CfFlyFace", false)
local doDash
keybind(cfFlySec, "Dash Key", "CfDashKey", nil, function() if doDash then doDash() end end)
slider(cfFlySec, "Dash Distance", "CfDashDist", 5, 200, 40, { Suffix = " st" })
slider(cfFlySec, "Dash Time", "CfDashTime", 0.05, 1, 0.15, { Decimals = 2, Suffix = " s" })
slider(cfFlySec, "Dash Cooldown", "CfDashCd", 0, 5, 0.5, { Decimals = 1, Suffix = " s" })
toggle(cfFlySec, "Dash Toward Camera", "CfDashCamera", false)

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.RespectCanCollide = true
local function blocked(root, dir, dist)
    if not C.CfWallCheck or dir.Magnitude < 1e-3 then return false end
    wallParams.FilterDescendantsInstances = { lp.Character }
    return workspace:Raycast(root.Position, dir.Unit * (dist + 1.5), wallParams) ~= nil
end

local function smooth(cur, target, dt)
    local a = C.CfAccel <= 0.001 and 1 or (1 - math.exp(-dt / C.CfAccel))
    return cur:Lerp(target, a)
end

local walkVel, flyVel, flyPos, flyRoot = Vector3.zero, Vector3.zero, nil, nil
local dash = { left = 0, dir = Vector3.zero, cd = 0 }

doDash = function()
    local hum, root = myHumanoid()
    if not (hum and root) or hum.Health <= 0 or dash.cd > 0 then return end
    local dir = hum.MoveDirection
    if C.CfDashCamera then
        local look = cam().CFrame.LookVector
        dir = Vector3.new(look.X, 0, look.Z)
    elseif dir.Magnitude < 0.1 then
        local look = root.CFrame.LookVector
        dir = Vector3.new(look.X, 0, look.Z)
    end
    if dir.Magnitude < 0.01 then return end
    dash.dir, dash.left, dash.cd = dir.Unit, C.CfDashTime, C.CfDashCd + C.CfDashTime
end

renderLast(function(dt)
    if not U.Running or C.Freecam then return end
    dt = math.clamp(dt, 0, 0.1)
    local hum, root = myHumanoid()
    if not (hum and root) or hum.Health <= 0 then flyPos = nil return end
    dash.cd = math.max(0, dash.cd - dt)

    if dash.left > 0 then
        local step = math.min(dt, dash.left)
        dash.left -= step
        local move = dash.dir * (C.CfDashDist / C.CfDashTime) * step
        if not blocked(root, dash.dir, move.Magnitude) then
            root.CFrame += move
            if flyPos then flyPos += move end
        end
        local v = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
    end

    if C.CfFly then

        if flyRoot ~= root or not flyPos or (root.Position - flyPos).Magnitude > 12 then
            flyPos, flyRoot, flyVel = root.Position, root, Vector3.zero
        end
        local dir = Vector3.zero
        if C.CfFlyPitch then
            local cf = cam().CFrame
            if keyDown(Enum.KeyCode.W) then dir += cf.LookVector end
            if keyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
            if keyDown(Enum.KeyCode.D) then dir += cf.RightVector end
            if keyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
        else
            dir = hum.MoveDirection
        end
        if keyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis * C.CfFlyVert end
        if keyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis * C.CfFlyVert end
        if dir.Magnitude > 1 then dir = dir.Unit end

        local speed = C.CfFlySpeed * ((BIND.CfSprintKey and BIND.CfSprintKey:IsDown()) and C.CfSprint or 1)
        flyVel = smooth(flyVel, dir * speed, dt)
        local step = flyVel * dt
        if blocked(root, flyVel, step.Magnitude) then flyVel, step = Vector3.zero, Vector3.zero end
        flyPos += step

        local flat = Vector3.new(dir.X, 0, dir.Z)
        if C.CfFlyFace and flat.Magnitude > 0.1 then
            root.CFrame = CFrame.lookAt(flyPos, flyPos + flat)
        else
            root.CFrame = CFrame.new(flyPos) * root.CFrame.Rotation
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return
    end
    flyPos = nil

    if C.CfSpeed then
        local held = not C.CfSpeedHold or (BIND.CfSpeedKey and BIND.CfSpeedKey:IsDown())
        local dir = hum.MoveDirection
        if not held or (C.CfGroundOnly and hum.FloorMaterial == Enum.Material.Air) then dir = Vector3.zero end
        local speed = C.CfSpeedValue * ((BIND.CfSprintKey and BIND.CfSprintKey:IsDown()) and C.CfSprint or 1)
        walkVel = smooth(walkVel, dir * speed, dt)
        if walkVel.Magnitude > 0.05 then
            local move = walkVel * dt
            if not blocked(root, walkVel, move.Magnitude) then root.CFrame += move end
        end
    else
        walkVel = Vector3.zero
    end
end)

do
local TK_MAX, TK_SIZE, TK_RESCAN, INF_RANGE, CYCLE_TIME = 250, 400, 0.75, 1600, 8
local TAU, GOLDEN = math.pi * 2, math.pi * (3 - math.sqrt(5))
local SHAPES = { "Ring", "Tornado", "Sphere", "Infinity", "Galaxy", "DNA Helix", "Wings", "Cycle" }
local CYCLE = { "Infinity", "Ring", "Galaxy", "Sphere", "Tornado", "DNA Helix", "Wings" }

local tkSec = miscTab:Section("Telekinesis")

local parts, partSet, origCollide = {}, {}, {}
local claimOrig, scanAt, scanCount, fireUntil = nil, 0, 0, 0

local function setClaim(on)
    if on then
        if not claimOrig then
            claimOrig = {}
            pcall(function() claimOrig.Max = lp.MaximumSimulationRadius end)
            if gethiddenproperty then pcall(function() claimOrig.Sim = gethiddenproperty(lp, "SimulationRadius") end) end
        end
    elseif claimOrig then
        pcall(function() if claimOrig.Max then lp.MaximumSimulationRadius = claimOrig.Max end end)
        if sethiddenproperty and claimOrig.Sim then pcall(sethiddenproperty, lp, "SimulationRadius", claimOrig.Sim) end
        claimOrig = nil
    end
end

local function mine(part) return not isnetworkowner or isnetworkowner(part) end

local function letGo(part, stop)
    local c = origCollide[part]
    origCollide[part] = nil
    if not part.Parent then return end
    if c ~= nil then pcall(function() part.CanCollide = c end) end
    if stop then
        pcall(function()
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
        end)
    end
end

local function releaseAll()
    for _, part in ipairs(parts) do letGo(part, true) end
    table.clear(parts)
    table.clear(partSet)
    scanCount = 0
end

local function grabbableRoot(part)
    local root = part.AssemblyRootPart
    if not root or root.Anchored or root.Size.Magnitude > TK_SIZE then return nil end
    if root:IsDescendantOf(cam()) then return nil end
    local model = root:FindFirstAncestorOfClass("Model")
    while model do
        if model:FindFirstChildOfClass("Humanoid") then return nil end
        model = model:FindFirstAncestorOfClass("Model")
    end
    return root
end

local function scan(root)
    local range = C.TkRange >= INF_RANGE and math.huge or C.TkRange
    local pos = root.Position

    for i = #parts, 1, -1 do
        local part = parts[i]
        if not part.Parent or part.Anchored then
            partSet[part] = nil
            letGo(part, false)
            table.remove(parts, i)
        end
    end

    local seen, found = {}, {}
    local function consider(p)
        local r = grabbableRoot(p)
        if r and not seen[r] and not partSet[r] then
            seen[r] = true
            table.insert(found, { part = r, dist = (r.Position - pos).Magnitude })
        end
    end
    if range <= 500 then
        local ignore = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character then table.insert(ignore, plr.Character) end
        end
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = ignore
        for _, p in ipairs(workspace:GetPartBoundsInRadius(pos, range, params)) do consider(p) end
    else
        for _, p in ipairs(workspace:GetDescendants()) do
            if p:IsA("BasePart") and not p.Anchored and (range == math.huge or (p.Position - pos).Magnitude <= range) then
                consider(p)
            end
        end
    end
    table.sort(found, function(a, b) return a.dist < b.dist end)

    for _, f in ipairs(found) do
        if #parts >= TK_MAX then
            if not mine(f.part) then break end
            local dropped
            for i = #parts, 1, -1 do
                if not mine(parts[i]) then
                    partSet[parts[i]] = nil
                    letGo(parts[i], false)
                    table.remove(parts, i)
                    dropped = true
                    break
                end
            end
            if not dropped then break end
        end
        partSet[f.part] = true
        table.insert(parts, f.part)
    end

    scanCount += 1
    if scanCount == 2 then
        if #parts == 0 then
            notify("Telekinesis", "No loose parts in range - anchored parts and characters cannot be moved", "warn")
        else
            local owned = 0
            if isnetworkowner then
                for _, p in ipairs(parts) do if isnetworkowner(p) then owned += 1 end end
                notify("Telekinesis", #parts .. " parts found, " .. owned .. " are yours (only those move for other players)",
                    owned > 0 and "success" or "warn")
            else
                notify("Telekinesis", #parts .. " parts found", "success")
            end
        end
    end
end

local function shapeOffset(shape, i, n, t, r, right, flat)
    local u = (i - 1) / math.max(n - 1, 1)
    if shape == "Ring" then
        local layers = math.ceil(n / 36)
        local perLayer = math.ceil(n / layers)
        local layer, idx = math.floor((i - 1) / perLayer), (i - 1) % perLayer
        local count = math.min(perLayer, n - layer * perLayer)
        local a = t * 1.3 + idx / count * TAU + layer * 0.5
        return right * math.cos(a) * r + flat * math.sin(a) * r + Vector3.yAxis * ((layer - (layers - 1) / 2) * 2.2)
    elseif shape == "Tornado" then
        local a = u * TAU * 4 + t * 3
        local rad = r * (1 + 0.9 * u)
        return right * math.cos(a) * rad + flat * math.sin(a) * rad + Vector3.yAxis * (-2 + u * r * 1.6)
    elseif shape == "Sphere" then
        local yy = 1 - 2 * (i - 0.5) / n
        local rr = math.sqrt(math.max(0, 1 - yy * yy))
        local a = GOLDEN * i + t * 0.8
        return right * (math.cos(a) * rr * r) + flat * (math.sin(a) * rr * r) + Vector3.yAxis * (yy * r)
    elseif shape == "Infinity" then
        local a = u * TAU + t * 0.9
        local s = math.sin(a)
        local den = 1 + s * s
        local size = math.max(r * 0.8, 6)
        local z = r + ((i % 3) - 1) * 0.9 + math.sin(t * 2 + i) * 0.3
        return right * (size * math.cos(a) / den) + Vector3.yAxis * (2 + size * s * math.cos(a) / den * 1.1) + flat * z
    elseif shape == "Galaxy" then
        local arm = (i - 1) % 3
        local k = math.floor((i - 1) / 3)
        local f = k / math.max(math.ceil(n / 3) - 1, 1)
        local rad = r * (1 + f * 1.1)
        local a = arm / 3 * TAU + f * TAU * 1.1 + t * 0.9
        return right * math.cos(a) * rad + flat * math.sin(a) * rad + Vector3.yAxis * (math.sin(t * 1.5 + f * 6) * 1.2)
    elseif shape == "DNA Helix" then
        local strand = (i - 1) % 2
        local f = math.floor((i - 1) / 2) / math.max(math.ceil(n / 2) - 1, 1)
        local a = f * TAU * 2.5 + t * 2.2 + strand * math.pi
        return right * math.cos(a) * r + flat * math.sin(a) * r + Vector3.yAxis * (-2 + f * r * 2.2)
    else
        local side = (i % 2 == 0) and 1 or -1
        local k = math.floor((i - 1) / 2)
        local row = k % 3
        local cols = math.max(math.ceil(math.ceil(n / 2) / 3), 1)
        local f = (math.floor(k / 3) + 0.5) / cols
        local x = side * (r * 0.5 + f * r * 1.3)
        local y = 1 + f * r * 0.5 - row * r * 0.25 * (1 - 0.5 * f) + math.abs(x) * math.sin(t * 2.6) * 0.22
        return right * x + Vector3.yAxis * y - flat * (3 + r * 0.25 + row * 0.25)
    end
end

toggle(tkSec, "Telekinesis", "TkEnabled", false, function(v)
    if v then
        setClaim(true)
        scanAt, scanCount = 0, 0
    else
        releaseAll()
        setClaim(false)
    end
end)
dropdown(tkSec, "Pattern", "TkShape", SHAPES, "Infinity")
slider(tkSec, "Distance", "TkDist", 4, 200, 16, { Suffix = " st" })
slider(tkSec, "Range", "TkRange", 25, INF_RANGE, 300, { Suffix = " st", MaxLabel = "Infinite" })
keybind(tkSec, "Fire Key", "TkFireKey", Enum.KeyCode.G, function()
    if not C.TkEnabled or #parts == 0 then return end
    local m = UserInputService:GetMouseLocation()
    local ray = cam():ViewportPointToRay(m.X, m.Y)
    rayParams.FilterDescendantsInstances = { lp.Character }
    local res = workspace:Raycast(ray.Origin, ray.Direction * 2000, rayParams)
    local target = res and res.Position or (ray.Origin + ray.Direction * 500)
    for _, part in ipairs(parts) do
        if part.Parent then
            local d = target - part.Position
            if d.Magnitude > 0.1 then part.AssemblyLinearVelocity = d.Unit * 500 end
        end
    end
    fireUntil = os.clock() + 1
end)
tkSec:Button({ Text = "Release All", Callback = function() releaseAll() end })

onUnload(function()
    releaseAll()
    setClaim(false)
end)

local lost = 0
U.TkStats = function()
    local m, anch, gone = 0, 0, 0
    for _, part in ipairs(parts) do
        if not part.Parent then gone += 1 elseif part.Anchored then anch += 1 end
        if part.Parent and mine(part) then m += 1 end
    end
    return { held = #parts, mine = m, anchored = anch, gone = gone, lost = lost }
end

connect(RunService.Heartbeat, function()
    if claimOrig and C.TkEnabled and U.Running then
        pcall(function() lp.MaximumSimulationRadius = 1e9 end)
        if sethiddenproperty then pcall(sethiddenproperty, lp, "SimulationRadius", 1e9) end
    end
end)

connect(RunService.PreSimulation or RunService.Heartbeat, function(dt)
    if not (C.TkEnabled and U.Running) then return end
    local _, root = myHumanoid()
    if not root then
        for _, part in ipairs(parts) do if origCollide[part] ~= nil then letGo(part, true) end end
        return
    end
    local now = os.clock()

    if now - scanAt > TK_RESCAN then
        scanAt = now
        scan(root)
    end
    local n = #parts
    if n == 0 or now < fireUntil then return end

    local shape = C.TkShape
    if shape == "Cycle" then shape = CYCLE[math.floor(now / CYCLE_TIME) % #CYCLE + 1] end
    local look = cam().CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.zAxis
    local right = flat:Cross(Vector3.yAxis)
    local center = root.Position + Vector3.new(0, 2, 0)
    local gain = math.min(18 * math.max(dt, 1 / 240), 0.9) / math.max(dt, 1 / 240)

    for i = 1, n do
        local part = parts[i]
        if not mine(part) then
            if origCollide[part] ~= nil then lost += 1 letGo(part, false) end
            continue
        end
        if origCollide[part] == nil then
            origCollide[part] = part.CanCollide
            part.CanCollide = false
        end
        local v = (center + shapeOffset(shape, i, n, now, C.TkDist, right, flat) - part.Position) * gain
        if v.Magnitude > 900 then v = v.Unit * 900 end
        part.AssemblyLinearVelocity = v
        part.AssemblyAngularVelocity = Vector3.new(0, 4, 0)
    end
end)
end

local chatSec = miscTab:Section("Chat Spy")
local chatOpt = miscTab:Section("Chat Spy Options", "right")

local TextChatService = game:GetService("TextChatService")
local chatLog, chatLabels, recentChat = {}, {}, {}
local chatGui, chatFrame, chatList, chatPos
local chatDrag

local TEXT_COLOR, FAINT_HEX = Color3.fromRGB(232, 226, 227), "#685a5e"
local TEAM_COLOR = Color3.fromRGB(110, 220, 140)
local chatColors = {
    Accent = Color3.fromRGB(255, 32, 48), Bg = Color3.fromRGB(11, 4, 6),
    BgTop = Color3.fromRGB(19, 5, 8), Border = Color3.fromRGB(96, 14, 24),
}
local chatStroke, chatTop, chatTitle, chatLine
local KIND_TAG = { public = "", private = "[PM] ", team = "[TEAM] " }

local function monoFont(inst, weight)
    local ok = pcall(function()
        inst.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", weight or Enum.FontWeight.Regular)
    end)
    if not ok then inst.Font = Enum.Font.Code end
end

local function readMenuColors()
    local main = win.Main
    if not main then return end
    chatColors.Bg = main.BackgroundColor3
    local s = main:FindFirstChildOfClass("UIStroke")
    if s then chatColors.Accent = s.Color end
    local top = main:FindFirstChild("TopBar")
    if top then
        chatColors.BgTop = top.BackgroundColor3
        for _, child in ipairs(top:GetChildren()) do
            if child:IsA("Frame") and child.Size.Y.Offset == 1 then chatColors.Border = child.BackgroundColor3 end
        end
    end
end

local function kindColor(kind)
    if kind == "private" then return chatColors.Accent end
    if kind == "team" then return TEAM_COLOR end
    return TEXT_COLOR
end

local function applyChatTheme()
    if not chatFrame then return end
    readMenuColors()
    chatFrame.BackgroundColor3 = chatColors.Bg
    chatStroke.Color = chatColors.Accent
    chatTop.BackgroundColor3 = chatColors.BgTop
    chatTitle.TextColor3 = chatColors.Accent
    chatLine.BackgroundColor3 = chatColors.Border
    chatList.ScrollBarImageColor3 = chatColors.Accent
    for _, label in ipairs(chatLabels) do label.TextColor3 = kindColor(label:GetAttribute("Kind")) end
end

local function esc(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function addChatLine(entry)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, -8, 0, 0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.RichText = true
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    monoFont(label)
    label.TextSize = C.ChatSize
    label:SetAttribute("Kind", entry.kind)
    label.TextColor3 = kindColor(entry.kind)
    label.Text = ("<font color=\"%s\">%s</font> %s<b>%s</b>: %s"):format(FAINT_HEX, entry.t, KIND_TAG[entry.kind] or "", esc(entry.name), esc(entry.text))
    label.Parent = chatList
    table.insert(chatLabels, label)
    while #chatLabels > C.ChatMax do table.remove(chatLabels, 1):Destroy() end
    task.defer(function()
        if chatList then chatList.CanvasPosition = Vector2.new(0, chatList.AbsoluteCanvasSize.Y) end
    end)
end

local function destroyChat()
    if chatFrame then chatPos = chatFrame.Position end
    if chatGui then chatGui:Destroy() end
    chatGui, chatFrame, chatList = nil, nil, nil
    chatStroke, chatTop, chatTitle, chatLine = nil, nil, nil, nil
    table.clear(chatLabels)
end
onUnload(destroyChat)

local function buildChat()
    readMenuColors()
    chatGui = Instance.new("ScreenGui")
    chatGui.Name = "TerkanChat"
    chatGui.ResetOnSpawn = false
    chatGui.IgnoreGuiInset = true
    chatGui.DisplayOrder = 99
    chatGui.Parent = parentGui()

    chatFrame = Instance.new("Frame")
    chatFrame.BackgroundColor3 = chatColors.Bg
    chatFrame.BorderSizePixel = 0
    chatFrame.Size = UDim2.fromOffset(C.ChatW, C.ChatH)
    chatFrame.Position = chatPos or UDim2.new(0, 12, 1, -(C.ChatH + 12))
    chatFrame.Parent = chatGui
    chatStroke = Instance.new("UIStroke")
    chatStroke.Color = chatColors.Accent
    chatStroke.Thickness = 2
    chatStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    chatStroke.Parent = chatFrame

    chatTop = Instance.new("Frame")
    chatTop.BackgroundColor3 = chatColors.BgTop
    chatTop.BorderSizePixel = 0
    chatTop.Size = UDim2.new(1, 0, 0, 32)
    chatTop.Active = true
    chatTop.Parent = chatFrame
    chatTop.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            chatDrag = { start = input.Position, from = chatFrame.Position }
        end
    end)

    chatTitle = Instance.new("TextLabel")
    chatTitle.BackgroundTransparency = 1
    chatTitle.Position = UDim2.new(0, 12, 0, 0)
    chatTitle.Size = UDim2.new(0.5, 0, 1, 0)
    chatTitle.Text = "CHAT SPY"
    chatTitle.TextSize = 15
    chatTitle.TextColor3 = chatColors.Accent
    chatTitle.TextXAlignment = Enum.TextXAlignment.Left
    monoFont(chatTitle, Enum.FontWeight.Bold)
    chatTitle.Parent = chatTop

    local hint = Instance.new("TextLabel")
    hint.BackgroundTransparency = 1
    hint.AnchorPoint = Vector2.new(1, 0)
    hint.Position = UDim2.new(1, -12, 0, 0)
    hint.Size = UDim2.new(0.5, 0, 1, 0)
    hint.Text = "drag to move"
    hint.TextSize = 11
    hint.TextColor3 = Color3.fromRGB(104, 90, 94)
    hint.TextXAlignment = Enum.TextXAlignment.Right
    monoFont(hint)
    hint.Parent = chatTop

    chatLine = Instance.new("Frame")
    chatLine.BackgroundColor3 = chatColors.Border
    chatLine.BackgroundTransparency = 0.35
    chatLine.BorderSizePixel = 0
    chatLine.Position = UDim2.new(0, 0, 1, -1)
    chatLine.Size = UDim2.new(1, 0, 0, 1)
    chatLine.Parent = chatTop

    chatList = Instance.new("ScrollingFrame")
    chatList.BackgroundTransparency = 1
    chatList.BorderSizePixel = 0
    chatList.Position = UDim2.new(0, 8, 0, 38)
    chatList.Size = UDim2.new(1, -16, 1, -46)
    chatList.CanvasSize = UDim2.new()
    chatList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    chatList.ScrollBarThickness = 3
    chatList.ScrollBarImageColor3 = chatColors.Accent
    chatList.Parent = chatFrame
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 3)
    layout.Parent = chatList

    for _, entry in ipairs(chatLog) do addChatLine(entry) end
end

local chatThemeAt = 0
connect(RunService.Heartbeat, function(dt)
    if not chatFrame then return end
    chatThemeAt += dt
    if chatThemeAt < 0.4 then return end
    chatThemeAt = 0
    applyChatTheme()
end)

connect(UserInputService.InputChanged, function(input)
    if chatDrag and chatFrame and input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - chatDrag.start
        chatFrame.Position = UDim2.new(chatDrag.from.X.Scale, chatDrag.from.X.Offset + d.X,
            chatDrag.from.Y.Scale, chatDrag.from.Y.Offset + d.Y)
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then chatDrag = nil end
end)

local function logChat(kind, name, text)
    if not (C.ChatSpy and U.Running) then return end
    if C.ChatPrivateOnly and kind == "public" then return end

    local key, now = name .. "\0" .. text, os.clock()
    if recentChat[key] and now - recentChat[key] < 1 then return end
    if next(recentChat) and math.random() < 0.05 then
        for k, t in pairs(recentChat) do if now - t > 5 then recentChat[k] = nil end end
    end
    recentChat[key] = now

    local entry = { t = os.date("%H:%M:%S"), kind = kind, name = name, text = text }
    table.insert(chatLog, entry)
    while #chatLog > C.ChatMax do table.remove(chatLog, 1) end
    if chatList then addChatLine(entry) end
    if kind ~= "public" and C.ChatNotify then notify("Chat Spy", name .. ": " .. text) end
end

toggle(chatSec, "Chat Spy", "ChatSpy", false, function(v)
    if v then buildChat() else destroyChat() end
end)
toggle(chatSec, "Only Whispers & Team", "ChatPrivateOnly", false)
toggle(chatSec, "Notify On Whispers & Team", "ChatNotify", true)
chatSec:Button({ Text = "Copy Log", Callback = function()
    if not hasFn("setclipboard") then notify("Chat Spy", "Your executor cannot copy to the clipboard", "warn") return end
    local lines = {}
    for _, e in ipairs(chatLog) do
        table.insert(lines, ("[%s] [%s] %s: %s"):format(e.t, e.kind, e.name, e.text))
    end
    setclipboard(table.concat(lines, "\n"))
    notify("Chat Spy", #lines .. " lines copied", "success")
end })
chatSec:Button({ Text = "Clear Log", Callback = function()
    table.clear(chatLog)
    for _, l in ipairs(chatLabels) do l:Destroy() end
    table.clear(chatLabels)
end })
slider(chatOpt, "Lines Kept", "ChatMax", 20, 300, 80)
slider(chatOpt, "Text Size", "ChatSize", 10, 22, 14)
slider(chatOpt, "Window Width", "ChatW", 240, 800, 380, { OnChange = function(v)
    if chatFrame then chatFrame.Size = UDim2.fromOffset(v, C.ChatH) end
end })
slider(chatOpt, "Window Height", "ChatH", 100, 600, 220, { OnChange = function(v)
    if chatFrame then chatFrame.Size = UDim2.fromOffset(C.ChatW, v) end
end })

local newChat = false
pcall(function() newChat = TextChatService.ChatVersion == Enum.ChatVersion.TextChatService end)

if not newChat then
    local function hookPlayer(plr)
        if plr == lp then return end
        connect(plr.Chatted, function(msg)
            local low = msg:lower()
            local kind = "public"
            if low:match("^/w ") or low:match("^/whisper ") or low:match("^/msg ") then kind = "private"
            elseif low:match("^/t ") or low:match("^/team ") then kind = "team" end
            logChat(kind, plr.Name, msg)
        end)
    end
    for _, plr in ipairs(Players:GetPlayers()) do hookPlayer(plr) end
    connect(Players.PlayerAdded, hookPlayer)
end
pcall(function()
    connect(TextChatService.MessageReceived, function(message)
        local source = message.TextSource
        local plr = source and Players:GetPlayerByUserId(source.UserId)
        if not plr or plr == lp then return end
        local channel = message.TextChannel and message.TextChannel.Name or ""
        local kind = "public"
        if channel:find("Whisper") then kind = "private" elseif channel:find("Team") then kind = "team" end
        logChat(kind, plr.Name, message.Text)
    end)
end)
end)()

local notifTab = win:Tab("Notifications")
local notifSec = notifTab:Section("Appearance")
local notifShow = notifTab:Section("Show Notifications For", "right")

toggle(notifSec, "Notifications", "NotifOn", true)
slider(notifSec, "Duration", "NotifDuration", 1, 10, 4, { Suffix = "s" })
slider(notifSec, "Max On Screen", "NotifMax", 1, 8, 5)
toggle(notifSec, "Use Theme Color", "NotifThemeColor", true)
color(notifSec, "Notification Color", "NotifColor", Color3.fromRGB(255, 32, 48))
toggle(notifSec, "Notification Rainbow", "NotifRainbow", false)
dropdown(notifSec, "Position", "NotifPos", { "Above Crosshair", "Below Crosshair" }, "Above Crosshair")
color(notifSec, "Rage Text Color", "RageStatusColor", Color3.fromRGB(255, 255, 255))
toggle(notifSec, "Rage Text Rainbow", "RageStatusRainbow", false)
notifSec:Button({ Text = "Test Notification", Callback = function()
    showToast("Terkan", "This is how notifications look")
end })
notifSec:Button({ Text = "Test Warning", Callback = function()
    showToast("Warning", "This is how a warning looks", "warn")
end })

toggle(notifShow, "Feature On / Off", "Notif_toggle", false)
toggle(notifShow, "Rage Status Bar", "RageStatus", true)
toggle(notifShow, "Config Events", "Notif_config", true)
toggle(notifShow, "Protection Alerts", "Notif_protect", true)
toggle(notifShow, "Warnings & Errors", "Notif_warn", true)
toggle(notifShow, "Target Locked", "Notif_target", false)
toggle(notifShow, "Target Eliminated", "Notif_target_dead", false)
toggle(notifShow, "Player Joined / Left", "Notif_players", false)
toggle(notifShow, "Startup Message", "Notif_startup", true)
toggle(notifShow, "Other", "Notif_misc", true)

local watchedPlr
local watchAccum = 0
local lockNotedAt = {}
connect(RunService.Heartbeat, function(dt)
    watchAccum += dt
    if watchAccum < 0.2 then return end
    watchAccum = 0
    if not (C.Notif_target or C.Notif_target_dead) then watchedPlr = nil return end

    local t = (C.RageEnabled and rageTarget) or (C.AimEnabled and aimTarget) or U.SilentTarget
    local plr = t and t.plr
    if plr == watchedPlr then return end

    if watchedPlr and C.Notif_target_dead then
        local char = watchedPlr.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and (hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead) then
            notify("Target down", watchedPlr.DisplayName .. " was eliminated", "success")
        end
    end
    if plr and C.Notif_target and os.clock() - (lockNotedAt[plr] or 0) > 2 then
        lockNotedAt[plr] = os.clock()
        notify("Target locked", plr.DisplayName)
    end
    watchedPlr = plr
end)

connect(Players.PlayerAdded, function(plr) notify("Player joined", plr.DisplayName .. " joined the server") end)
connect(Players.PlayerRemoving, function(plr) notify("Player left", plr.DisplayName .. " left the server") end)

local settingsTab = win:Tab("Settings")
local cfgSec = settingsTab:Section("Configs")
local themeSec = settingsTab:Section("Theme", "right")
local menuSec = settingsTab:Section("Menu", "right")
local bindSec = settingsTab:Section("Binds", "right")

local cfgName = cfgSec:TextBox({ Text = "Config Name", Placeholder = "my config", Flag = "_cfgName", NoSave = true,
    Callback = function(v) C._cfgName = v end })
local cfgList = cfgSec:Dropdown({ Text = "Config List", Options = win:ListConfigs(), Flag = "_cfgList", NoSave = true,
    Callback = function(v) C._cfgList = v end })
local autoloadLabel = cfgSec:Label("Autoload: none")

local function refreshConfigs()
    cfgList:SetOptions(win:ListConfigs())
    autoloadLabel:Set("Autoload: " .. (win:GetAutoload() or "none"))
end
refreshConfigs()

cfgSec:Button({ Text = "Create Config", Callback = function()
    local ok, res = win:SaveConfig(C._cfgName or "", false)
    if ok then refreshConfigs() cfgList:Set(res, true) C._cfgList = res notify("Config", "Created '" .. res .. "'", "success")
    else notify("Config", tostring(res), "error") end
end })
cfgSec:Button({ Text = "Overwrite Config", Callback = function()
    local name = C._cfgList
    if not name then notify("Config", "Select a config in the list first", "warn") return end
    local ok, res = win:SaveConfig(name, true)
    if ok then notify("Config", "Saved over '" .. name .. "'", "success") else notify("Config", tostring(res), "error") end
end })
cfgSec:Button({ Text = "Load Config", Callback = function()
    local name = C._cfgList
    if not name then notify("Config", "Select a config in the list first", "warn") return end
    U.LoadingConfig = true
    task.delay(0.8, function() U.LoadingConfig = false end)
    local ok, res = win:LoadConfig(name)
    if ok then notify("Config", ("Loaded '%s' (%d settings)"):format(name, res), "success")
    else notify("Config", tostring(res), "error") end
end })
cfgSec:Button({ Text = "Delete Config", Callback = function()
    local name = C._cfgList
    if not name then notify("Config", "Select a config in the list first", "warn") return end
    if win:DeleteConfig(name) then
        C._cfgList = nil
        cfgList:Set(nil, true)
        refreshConfigs()
        notify("Config", "Deleted '" .. name .. "'", "success")
    else
        notify("Config", "Could not delete", "error")
    end
end })
cfgSec:Button({ Text = "Refresh List", Callback = function() refreshConfigs() end })
cfgSec:Button({ Text = "Set As Autoload", Callback = function()
    local name = C._cfgList
    if not name then notify("Config", "Select a config in the list first", "warn") return end
    if win:SetAutoload(name) then refreshConfigs() notify("Config", "'" .. name .. "' loads on startup", "success") end
end })
cfgSec:Button({ Text = "Clear Autoload", Callback = function()
    win:SetAutoload(nil)
    refreshConfigs()
end })

local accentPicker
local DEFAULT_ACCENT = Color3.fromRGB(255, 32, 48)
local function sameColor(a, b)
    return math.floor(a.R * 255 + 0.5) == math.floor(b.R * 255 + 0.5)
        and math.floor(a.G * 255 + 0.5) == math.floor(b.G * 255 + 0.5)
        and math.floor(a.B * 255 + 0.5) == math.floor(b.B * 255 + 0.5)
end

themeSec:Dropdown({ Text = "Theme", Options = UI.ThemeNames, Default = "Terkan Red", Flag = "_theme", NoSave = true,
    Callback = function(name)
        if win:SetTheme(name) and accentPicker then
            accentPicker:Set(UI.Themes[name].Accent, true)
            C.AccentColor = UI.Themes[name].Accent
        end
    end })
accentPicker = color(themeSec, "Accent Color", "AccentColor", DEFAULT_ACCENT, function(c)
    if sameColor(c, DEFAULT_ACCENT) then win:SetTheme("Terkan Red") else win:SetAccent(c) end
end)

keybind(menuSec, "Menu Key", "MenuKey", Enum.KeyCode.RightShift, nil, function(key)
    win:SetToggleKey(key or Enum.KeyCode.RightShift)
end)
toggle(menuSec, "Background Blur", "BlurOn", false, function(v) win:SetBlur(v, C.BlurSize) end)
slider(menuSec, "Blur Strength", "BlurSize", 4, 40, 16, { OnChange = function(v) if C.BlurOn then win:SetBlur(true, v) end end })
slider(menuSec, "UI Scale", "UiScale", 0.6, 1.4, 1, { Decimals = 2, OnChange = function(v) win:SetScale(v) end })
menuSec:Button({ Text = "Unload Menu", Callback = function() U.Unload() end })

local function flip(key) return function() if TOG[key] then TOG[key]:Set(not TOG[key]:Get()) end end end
keybind(bindSec, "Soft Aim", "BindAim", nil, flip("AimEnabled"))
if TOG.SilentEnabled then keybind(bindSec, "Silent Aim", "BindSilent", nil, flip("SilentEnabled")) end
keybind(bindSec, "Triggerbot", "BindTrig", nil, flip("TrigEnabled"))
keybind(bindSec, "Rage Bot", "BindRage", Enum.KeyCode.End, flip("RageEnabled"))
keybind(bindSec, "ESP", "BindEsp", nil, flip("ESPEnabled"))
keybind(bindSec, "Fly", "BindFly", Enum.KeyCode.F, flip("FlyEnabled"))
keybind(bindSec, "Follow Player", "BindFollow", nil, flip("FollowEnabled"))
keybind(bindSec, "Orbit Player", "BindOrbit", nil, flip("OrbitEnabled"))
keybind(bindSec, "Custom Cursor", "BindCursor", nil, flip("CursorEnabled"))
keybind(bindSec, "Anti Fling", "BindAntiFling", nil, flip("AntiFling"))
keybind(bindSec, "Anti Void", "BindAntiVoid", nil, flip("AntiVoid"))
keybind(bindSec, "Void Spam", "BindVoidSpam", nil, flip("VoidSpam"))
keybind(bindSec, "Loop Fling All", "BindFlingLoop", nil, flip("FlingLoop"))
keybind(bindSec, "No Animations", "BindNoAnim", nil, flip("NoAnim"))
keybind(bindSec, "Freecam", "BindFreecam", nil, flip("Freecam"))
keybind(bindSec, "CFrame Speed", "BindCfSpeed", nil, flip("CfSpeed"))
keybind(bindSec, "CFrame Fly", "BindCfFly", nil, flip("CfFly"))
keybind(bindSec, "Telekinesis", "BindTelekinesis", nil, flip("TkEnabled"))
keybind(bindSec, "Chat Spy", "BindChatSpy", nil, flip("ChatSpy"))
keybind(bindSec, "Clean Particles", "BindCleanParticles", nil, flip("CleanParticles"))
keybind(bindSec, "Anti Ragdoll", "BindAntiRagdoll", nil, flip("AntiRagdoll"))
keybind(bindSec, "Anti Aim", "BindAntiAim", nil, flip("AntiAim"))
keybind(bindSec, "Desync", "BindDesync", nil, flip("Desync"))
keybind(bindSec, "Noclip", "BindNoclip", nil, flip("Noclip"))
keybind(bindSec, "Speed", "BindSpeed", nil, flip("SpeedEnabled"))

function U.Unload()
    if not U.Running then return end
    U.Running = false
    for _, name in ipairs(U.Binds) do pcall(function() RunService:UnbindFromRenderStep(name) end) end
    for _, c in ipairs(U.Conns) do pcall(function() c:Disconnect() end) end
    for _, fn in ipairs(U.Cleanups) do pcall(fn) end
    pcall(function() win:Destroy() end)
    getgenv().__TerkanUniversal = nil
end

task.defer(function()
    U.LoadingConfig = true
    local ok, res = win:LoadAutoload()
    if ok then notify("Terkan", "Autoload config applied", "success")
    else notify("Terkan", "Universal loaded - " .. tostring(win.ToggleKey.Name) .. " toggles the menu") end
    task.delay(0.8, function()
        U.LoadingConfig = false
        U.Ready = true
    end)
end)

return win
