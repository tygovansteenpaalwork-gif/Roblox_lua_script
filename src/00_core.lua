--[[
    Terkan Universal  -  general purpose hub on TerkanUI
    Tabs: Aimbot | Silent (only with metamethod hooks) | Trigger | Rage | Cursor | Visuals | Movement | Defense | Player | Misc | Notifications | Settings
    Everything that keeps a value "forced" is bound at RenderPriority.Last so a game's own
    script cannot win the ordering race against it.
--]]

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

-- only one copy at a time
if getgenv().__TerkanUniversal then
    pcall(getgenv().__TerkanUniversal.Unload)
end

----------------------------------------------------------------------
-- lifecycle helpers
----------------------------------------------------------------------

-- White / Black are sets of player names (see the Lists section on the Player tab): whitelisted players are
-- skipped by every targeting feature, blacklisted players are targeted first and drawn in their own colour
local U = { Conns = {}, Binds = {}, Cleanups = {}, Running = true, White = {}, Black = {} }
getgenv().__TerkanUniversal = U

-- Everything we put somewhere a game script can look (Lighting, PlayerGui, bound actions) gets a random neutral name
-- instead of "Terkan...", so a name-based scan finds nothing. (A method on U: the main chunk has no free local slots.)
function U.rname()
    local letters, out = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", {}
    for i = 1, math.random(8, 12) do
        local k = math.random(1, #letters)
        out[i] = letters:sub(k, k)
    end
    return table.concat(out)
end
U.FreecamAction = U.rname()
U.Version = "2.3.0"   -- also in version.txt on GitHub: the menu compares the two at startup

-- Errors inside a feature are shown once as a notification (and in the console) instead of silently killing that feature.
-- Every connection, render step and menu callback goes through U.Guard.
U.Seen = {}
function U.Report(err)
    local msg = tostring(err)
    if U.Seen[msg] then return end
    U.Seen[msg] = true
    warn("[Terkan] " .. msg)
    if U.Notify then U.Notify("Script error", msg:sub(1, 170), "error") end
end
function U.Guard(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then U.Report(err) end
    end
end
UI.OnError = U.Report

local function connect(signal, fn)
    local c = signal:Connect(U.Guard(fn))
    table.insert(U.Conns, c)
    return c
end

local function onUnload(fn) table.insert(U.Cleanups, fn) end

local bindCounter = 0
local function renderLast(fn)
    bindCounter += 1
    local name = "TerkanU_" .. bindCounter
    RunService:BindToRenderStep(name, Enum.RenderPriority.Last.Value, U.Guard(fn))
    table.insert(U.Binds, name)
end

-- runs before everything else in the frame (used to undo a temporary offset before anything reads it)
local function renderFirst(fn)
    bindCounter += 1
    local name = "TerkanU_" .. bindCounter
    RunService:BindToRenderStep(name, Enum.RenderPriority.First.Value, U.Guard(fn))
    table.insert(U.Binds, name)
end

-- frame counter: lets per-frame caches (U.Others) know when they are stale
U.Frame = 0
renderFirst(function() U.Frame += 1 end)

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

----------------------------------------------------------------------
-- config values: every UI element writes into C, features only ever read C
----------------------------------------------------------------------

local C = {}
local TOG, BIND = {}, {}
U.C, U.TOG = C, TOG   -- exposed for self-tests

local win = UI:Window({
    Title = "TERKAN",
    Version = "V " .. U.Version:match("^%d+%.%d+"),
    Footer = "Terkan Universal",
    ToggleKey = Enum.KeyCode.RightShift,
})

U.Win = win   -- exposed for self-tests

local notify   -- defined further down; declared here so toggle() below captures the local, not a global

-- switches that count as "a feature" for the optional Feature On / Off notifications
local FEATURE_TOGGLES = {
    AimEnabled = true, SilentEnabled = true, TrigEnabled = true, RageEnabled = true, ESPEnabled = true,
    FlyEnabled = true, Noclip = true, SpeedEnabled = true, JumpEnabled = true, InfJump = true,
    AntiStun = true, AntiFling = true, AntiVoid = true, AntiAim = true, Desync = true, FollowEnabled = true,
    OrbitEnabled = true, Spectate = true, ClickTp = true, CursorEnabled = true, Fullbright = true,
    FovEnabled = true, FpsBoost = true, AntiAfk = true, VoidSpam = true, AntiRagdoll = true, FlingLoop = true, NoAnim = true, Freecam = true,
    CleanEffects = true, CleanFog = true, CleanParticles = true, ZoomUnlock = true, StatsHud = true,
    CfSpeed = true, CfFly = true, TkEnabled = true, ChatSpy = true, ShOn = true, ShFuture = true,
    SpinOn = true, HeadSit = true, SitOn = true, LayDown = true, SkyOn = true, SuperFly = true, PunchOn = true,
}

local function toggle(sec, text, key, default, onChange)
    C[key] = default or false
    local api = sec:Toggle({
        Text = text, Default = default or false, Flag = key,
        Callback = function(v)
            C[key] = v
            if onChange then onChange(v) end
            -- not during startup or while a config is being applied, and not if onChange refused the change
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

-- Every notification belongs to a category, and each category has its own switch on the
-- Notifications page (C["Notif_<category>"]). Errors always count as "warn" so they cannot be
-- hidden by switching off an unrelated category.
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

local showToast   -- the on-screen text lines, defined below once the overlay exists

function notify(title, text, kind, category)
    category = category or notifCategory(title, kind)
    if C["Notif_" .. category] == false then return end
    showToast(title, text, kind)
end
U.Notify = notify   -- exposed for self-tests

----------------------------------------------------------------------
-- overlay for the FOV circles and the follow-target line
----------------------------------------------------------------------

local overlay = Instance.new("ScreenGui")
overlay.Name = U.rname()
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

----------------------------------------------------------------------
-- notifications: plain text lines just above the middle of the screen, like the rage status
-- (newest closest to the middle, older ones stacked away from it, each fading in and out)
----------------------------------------------------------------------

local toasts = {}   -- newest first: { label, born, kind }
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

----------------------------------------------------------------------
-- targeting
----------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- Returns character, humanoid, root - or nothing. Unless allowDead is set, a player only counts
-- while they are really alive: health above zero AND not in the Dead state (some games keep the
-- health value up while the humanoid is already dead, or the reverse).
local function charOf(plr, allowDead)
    local c = plr.Character
    if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid")
    local root = c:FindFirstChild("HumanoidRootPart")
    if not (hum and root) then return end
    if not allowDead and (hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead) then return end
    return c, hum, root
end

-- The other players with their character parts, looked up ONCE per frame instead of once per feature per frame
-- (aimbot, rage, trigger, ESP ... all ask for the same list). Entries: { plr, char, hum, root } - char / hum / root
-- are nil while the player has no character. Stale after one render frame or 0.1 s, whichever comes first.
function U.Others()
    local now = os.clock()
    if U.snap and U.snapFrame == U.Frame and now - U.snapTime < 0.1 then return U.snap end
    local out = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then
            local c = plr.Character
            out[#out + 1] = {
                plr = plr, char = c,
                hum = c and c:FindFirstChildOfClass("Humanoid"),
                root = c and c:FindFirstChild("HumanoidRootPart"),
            }
        end
    end
    U.snap, U.snapFrame, U.snapTime = out, U.Frame, now
    return out
end

local function sameTeam(plr)
    return lp.Team ~= nil and plr.Team ~= nil and plr.Team == lp.Team
end

local function screenPoint(pos)
    local v = cam():WorldToViewportPoint(pos)
    return Vector2.new(v.X, v.Y), v.Z > 0
end

local function visible(part, char)
    local me = lp.Character
    if U.rayChar ~= me then U.rayChar = me rayParams.FilterDescendantsInstances = { me } end
    local origin = cam().CFrame.Position
    local res = workspace:Raycast(origin, part.Position - origin, rayParams)
    return res == nil or res.Instance:IsDescendantOf(char)
end

local randomPick = {}
connect(Players.PlayerRemoving, function(plr) randomPick[plr] = nil end)
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

-- True when every visible-capable body part is (almost) fully transparent: lobby / spectator / hidden rigs that
-- belong to a player but are nothing you can actually hit. (A method on U: the main chunk has no free local slots.)
function U.isInvisible(char)
    for _, p in ipairs(char:GetChildren()) do
        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and p.Transparency < 0.9 then return false end
    end
    return true
end

-- o: Only (player name: consider nobody else), Origin, FOV (px, nil = no limit), MaxDist, MinDist, Team, NoFF (skip ForceField), NoInvis (skip invisible rigs), Wall, Part, Priority, Sticky (plr)
local function selectTarget(o)
    local c = cam()
    local origin = o.Origin or viewportCenter()
    local camPos = c.CFrame.Position
    local best, bestScore

    local anyBlack = next(U.Black) ~= nil
    for _, e in ipairs(U.Others()) do
        local plr = e.plr
        local listed = not (C.ListRespectWhite and U.White[plr.Name])
            and not (C.ListOnlyBlack and anyBlack and not U.Black[plr.Name])
        if listed and (not o.Only or plr.Name == o.Only) then
            -- same test as charOf(plr, o.AllowDead), on the shared per-frame snapshot
            local char, hum, root = e.char, e.hum, e.root
            if not (hum and root)
                or (not o.AllowDead and (hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead)) then
                char = nil
            end
            if char and not (o.Team and sameTeam(plr)) and not (o.NoFF and char:FindFirstChildOfClass("ForceField"))
                and not (o.NoInvis and U.isInvisible(char)) then
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
                                    -- these two scores are the same for every part of this player: the first part that
                                    -- passed decides, so skip the remaining parts (and their wall raycasts)
                                    if o.Priority == "Lowest Health" or o.Priority == "Closest Distance" then break end
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

-- True while the real cursor is on top of the menu. mouse1click() clicks wherever the
-- cursor is, so an auto-clicking feature must never fire then: the click would land on
-- the menu itself (switching the feature back off, or hitting Unload).
local function cursorOverMenu()
    if not win.Main.Visible then return false end
    local m = UserInputService:GetMouseLocation()
    local p, s = win.Main.AbsolutePosition, win.Main.AbsoluteSize
    -- GetMouseLocation is in viewport space, AbsolutePosition in GUI space: they differ by the top inset
    local top = game:GetService("GuiService"):GetGuiInset().Y
    return m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y + top and m.Y <= p.Y + s.Y + top
end

-- A click made INSIDE the game (VirtualInputManager) at the middle of the screen. Unlike
-- mouse1click it does not depend on the real cursor or on the window being focused (in The
-- Strongest Battlegrounds mouse1click started no attack at all, this does). It is skipped while
-- the menu covers that point, because the click would land on the menu.
local function virtualClick(at)
    -- While the menu is open NO virtual click is sent at all, wherever the menu sits: every
    -- VirtualInputManager event moves the game's idea of the mouse position, so the user's own
    -- click on a menu button (e.g. switching Rage off) lands on nothing and never registers.
    -- Exception: a click AT the real cursor (the triggerbot) moves nothing, so it may run with the menu
    -- open as long as the cursor is not on the menu itself.
    if win.Main.Visible and (not at or cursorOverMenu()) then return false end
    local vp = cam().ViewportSize
    local x, y = vp.X / 2, vp.Y / 2
    -- `at` = a mouse position (viewport coordinates): click exactly there, e.g. where the triggerbot sees an enemy
    if at then x, y = at.X, at.Y end   -- VirtualInputManager and GetMouseLocation share one coordinate space (measured: no inset)
    local vim = game:GetService("VirtualInputManager")
    vim:SendMouseButtonEvent(x, y, 0, true, game, 1)
    task.delay(0.03, function() vim:SendMouseButtonEvent(x, y, 0, false, game, 1) end)   -- short hold: some games ignore a same-frame press+release
    return true
end

local function fireWeapon(method, at)
    local char = lp.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    local canClick = hasFn("mouse1click") and not cursorOverMenu()
    if method == "Auto" then
        -- a click inside the game works for tools AND punch/M1 games (Tool:Activate and mouse1click
        -- start no attack in e.g. The Strongest Battlegrounds); fall back only if it cannot be sent
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
        pcall(virtualClick)   -- no tool (e.g. punch-based games): click inside the game
    end
end

U.FireWeapon, U.CursorOverMenu, U.Win = fireWeapon, cursorOverMenu, win   -- exposed for self-tests

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

