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
U.Version = "2.6.3"   -- also in version.txt on GitHub: the menu compares the two at startup

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

-- Writing a property of an Instance is expensive (every write crosses into the engine and can trigger a re-layout),
-- and what the per-frame features draw (ESP, cursor, glow) is mostly the same frame after frame. U.put only writes
-- when the value really changed; the last written value is remembered per instance. A property written through
-- U.put must ALWAYS be written through U.put, or the remembered value goes stale.
do
    local written = setmetatable({}, { __mode = "k" })
    function U.put(inst, prop, v)
        local c = written[inst]
        if not c then c = {} written[inst] = c end
        if c[prop] ~= v then
            c[prop] = v
            inst[prop] = v
        end
    end
end

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
    SpinOn = true, HeadSit = true, SitOn = true, LayDown = true, SkyOn = true, SuperFly = true, PunchOn = true, SkinOn = true, Potato = true,
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
    U.BindNames[key] = text
    BIND[key] = sec:Keybind({ Text = text, Default = default, Flag = key, Callback = callback,
        OnChanged = function(k)
            -- a key you set by hand that another keybind already uses: say which one (not while a config loads)
            if k and U.Ready and not U.LoadingConfig then U.WarnBindClash(key, k) end
            if onChanged then onChanged(k) end
        end })
    return BIND[key]
end

-- keybinds that share one key: pressing it switches BOTH features (e.g. Fly and something else on F)
U.BindNames = {}
function U.WarnBindClash(key, code)
    local users = {}
    if key ~= "MenuKey" and win.ToggleKey == code then table.insert(users, "Menu Key") end
    for other, b in pairs(BIND) do
        if other ~= key and other ~= "MenuKey" and b:Get() == code then table.insert(users, U.BindNames[other] or other) end
    end
    if #users > 0 then
        notify("Keybind", ("%s (%s) is also used by: %s"):format(U.BindNames[key] or key, code.Name, table.concat(users, ", ")), "warn")
    end
    return #users > 0
end
-- after startup / loading a config: one warning per key that more than one keybind uses
function U.WarnAllBindClashes()
    local done = {}
    for key, b in pairs(BIND) do
        local code = b:Get()
        if code and not done[code] and U.WarnBindClash(key, code) then done[code] = true end
    end
end

-- The BaseParts of a character, cached: rebuilt only when something is added to or removed from it.
-- Noclip, Superman noclip and fling touch every part on every physics step.
function U.CharParts(char)
    local e = U.partCache
    if not (e and e.char == char) then
        if e then for _, c in ipairs(e.conns) do c:Disconnect() end end
        e = { char = char, dirty = true }
        local function dirty() e.dirty = true end
        e.conns = { char.DescendantAdded:Connect(dirty), char.DescendantRemoving:Connect(dirty) }
        U.partCache = e
    end
    if e.dirty then
        e.dirty = false
        local list = {}
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then list[#list + 1] = d end
        end
        e.parts = list
    end
    return e.parts
end
onUnload(function()
    if U.partCache then for _, c in ipairs(U.partCache.conns) do c:Disconnect() end end
end)

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
    local put = U.put
    return function(radius, pos, col, visible)
        put(f, "Visible", visible)
        if visible then
            put(f, "Size", UDim2.fromOffset(radius * 2, radius * 2))
            put(f, "Position", UDim2.fromOffset(pos.X, pos.Y))
            put(stroke, "Color", col)
        end
    end
end

local function makeLine()
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.BorderSizePixel = 0
    f.Visible = false
    f.Parent = overlay
    local put = U.put
    return function(a, b, col, visible, thickness)
        put(f, "Visible", visible)
        if visible then
            local d = b - a
            put(f, "BackgroundColor3", col)
            put(f, "Size", UDim2.fromOffset(d.Magnitude, thickness or 1.5))
            put(f, "Position", UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2))
            put(f, "Rotation", math.deg(math.atan2(d.Y, d.X)))
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
    local put = U.put
    return function(pos, col, visible)
        put(f, "Visible", visible)
        if visible then put(f, "Position", UDim2.fromOffset(pos.X, pos.Y)) put(f, "BackgroundColor3", col) end
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

-- Glow for a TextLabel. Roblox UI cannot blur, so the light is faked: three copies right behind the text, each
-- with a same-coloured outline that is thicker and fainter than the one before. U.SyncGlow copies text, size and
-- position from the label every frame, so the glow follows whatever the label does (fading, moving, resizing).
function U.NewGlow(label)
    local g = { label = label, layers = {} }
    for i = 1, 3 do
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.TextStrokeTransparency = 1
        l.ZIndex = label.ZIndex - 1
        l.Visible = false
        local s = Instance.new("UIStroke")
        s.LineJoinMode = Enum.LineJoinMode.Round
        s.Parent = l
        l.Parent = label.Parent
        g.layers[i] = { label = l, stroke = s }
    end
    return g
end

-- on: glow wanted, size: outline width of the widest layer in px, fade: 0 (hidden) .. 1 (fully visible)
function U.SyncGlow(g, on, color, size, fade)
    local src = g.label
    local show = on and src.Visible and fade > 0.01
    local put = U.put
    fade = show and math.floor(fade * 50) / 50 or 0   -- 2% steps: a finished fade writes nothing any more
    for i, e in ipairs(g.layers) do
        local l = e.label
        put(l, "Visible", show)
        if show then
            put(l, "Text", src.Text) put(l, "Font", src.Font) put(l, "TextSize", src.TextSize)
            put(l, "TextTruncate", src.TextTruncate) put(l, "Size", src.Size) put(l, "Position", src.Position)
            put(l, "AnchorPoint", src.AnchorPoint) put(l, "TextXAlignment", src.TextXAlignment)
            put(l, "TextYAlignment", src.TextYAlignment)
            put(l, "TextColor3", color)
            put(l, "TextTransparency", 1 - fade)
            put(e.stroke, "Color", color)
            put(e.stroke, "Thickness", size * i / 3)
            put(e.stroke, "Transparency", 1 - fade * (0.5 - 0.13 * i))   -- inner layer brightest
        end
    end
end

function U.DropGlow(g)
    if not g then return end
    for _, e in ipairs(g.layers) do e.label:Destroy() end
end

local toasts = {}   -- newest first: { label, born, kind, glow }
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
        local t = table.remove(toasts)
        t.label:Destroy()
        U.DropGlow(t.glow)
    end
end

onUnload(function()
    for _, t in ipairs(toasts) do t.label:Destroy() U.DropGlow(t.glow) end
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
            U.DropGlow(toasts[i].glow)
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
        local col = toastColor(t.kind)
        t.label.TextColor3 = col
        t.label.TextTransparency = 1 - fade
        t.label.TextStrokeTransparency = math.clamp(0.35 + (1 - fade), 0, 1)
        -- glow layers are only made once the setting is on (and kept until the toast is gone)
        if C.NotifGlow and not t.glow then t.glow = U.NewGlow(t.label) end
        if t.glow then U.SyncGlow(t.glow, C.NotifGlow, col, C.NotifGlowSize or 6, fade) end
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
    -- see-through things do not count as a wall: invisible parts and parts without collision (hit effects,
    -- beams, glass panes ...). Battleground games spawn many of those between two fighters, and every one used
    -- to drop the lock for a frame. The ray simply continues behind them (a few times at most).
    local origin = cam().CFrame.Position
    local goal = part.Position
    for _ = 1, 5 do
        local dir = goal - origin
        local res = workspace:Raycast(origin, dir, rayParams)
        if res == nil or res.Instance:IsDescendantOf(char) then return true end
        local hit = res.Instance
        if hit.CanCollide and hit.Transparency < 0.9 then return false end
        origin = res.Position + dir.Unit * 0.05
    end
    return false
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
-- The answer is kept for a quarter of a second per character: walking all parts of every player every frame cost
-- about 1 ms per frame in games with detailed characters (Arsenal), and aimbot, rage and ESP all ask for it.
U.invCache = setmetatable({}, { __mode = "k" })
function U.isInvisible(char)
    local now = os.clock()
    local hit = U.invCache[char]
    if hit and now - hit.at < 0.25 then return hit.v end
    local v = true
    for _, p in ipairs(char:GetChildren()) do
        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and p.Transparency < 0.9 then v = false break end
    end
    U.invCache[char] = { at = now, v = v }
    return v
end

-- Knocked out but not dead: Da Hood style games keep the health up and flag it in BodyEffects ("K.O" / "Dead"),
-- other games use an attribute. Such a player cannot be hurt, so the dead check skips them too. Kept 0.2 s per character.
U.downCache = setmetatable({}, { __mode = "k" })
function U.isDowned(char)
    local now = os.clock()
    local hit = U.downCache[char]
    if hit and now - hit.at < 0.2 then return hit.v end
    local v = false
    local be = char:FindFirstChild("BodyEffects")
    if be then
        local ko, dead = be:FindFirstChild("K.O"), be:FindFirstChild("Dead")
        v = (ko ~= nil and ko:IsA("ValueBase") and ko.Value == true) or (dead ~= nil and dead:IsA("ValueBase") and dead.Value == true)
    end
    if not v then
        v = char:GetAttribute("KO") == true or char:GetAttribute("Knocked") == true or char:GetAttribute("Downed") == true
    end
    U.downCache[char] = { at = now, v = v }
    return v
end

-- o: Only (player name: consider nobody else), Skip (set of players to pass over), Origin, FOV (px, nil = no limit), MaxDist, MinDist, Team, NoFF (skip ForceField), NoInvis (skip invisible rigs), Wall, Part, Priority, Sticky (plr)
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
        if listed and (not o.Only or plr.Name == o.Only) and not (o.Skip and o.Skip[plr]) then
            -- same test as charOf(plr, o.AllowDead), on the shared per-frame snapshot
            local char, hum, root = e.char, e.hum, e.root
            if not (hum and root)
                or (not o.AllowDead and (hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead or U.isDowned(e.char))) then
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

local AIM_TYPES = { "Smooth Camera", "Hard Lock", "Snap On Fire", "Mouse Move", "Character Face" }
local TARGET_PARTS = { "Head", "Torso", "Random", "Closest" }
local PRIORITIES = { "Closest to Cursor", "Closest Distance", "Lowest Health" }
local FIRE_METHODS = { "Auto", "Tool Activate", "Mouse Click", "Virtual Click" }

----------------------------------------------------------------------
-- tab: Aimbot (soft aim)
----------------------------------------------------------------------

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
toggle(aimTune, "Skip ForceField", "AimNoFF", true)
toggle(aimTune, "Skip Invisible Rigs", "AimNoInvis", true)
toggle(aimTune, "Show FOV Circle", "AimShowFov", true)
color(aimTune, "FOV Color", "AimFovColor", Color3.fromRGB(255, 255, 255))

local aimCircle = makeCircle()
local aimTarget
local faceLocked = false

-- "Character Face" switches off the humanoid's own turning; hand it back when done
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
        U.AimMouseMode, U.AimMouseBlocked = nil, nil   -- switching the aimbot off and on checks the camera again
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
    -- never fight the user while they are working in the menu, nor Rage while it has a target (both would turn the camera)
    if not active or cursorOverMenu() or (U.RageTarget and U.RageTarget()) then aimTarget = nil releaseFace() return end

    local opts = {
        Origin = center, FOV = C.AimFov, MaxDist = C.AimDist, Team = C.AimTeam, Wall = C.AimWall,
        AllowDead = not C.AimDead, NoFF = C.AimNoFF, NoInvis = C.AimNoInvis,
        Part = C.AimPart, Priority = C.AimPriority,
    }
    -- Sticky: a locked target may drift out to 1.5x the circle before it is let go, so a fast target (or
    -- smoothing that lags behind) does not lose the lock right at the edge and grab someone else
    local t
    if C.AimSticky and aimTarget and aimTarget.plr.Parent then
        opts.Only, opts.FOV = aimTarget.plr.Name, C.AimFov * 1.5
        t = selectTarget(opts)
        opts.Only, opts.FOV = nil, C.AimFov
    end
    t = t or selectTarget(opts)
    aimTarget = t
    if not t then return end

    local goal = predicted(t, C.AimPredict)
    local smooth = math.clamp(C.AimSmooth / 100, 0, 0.98)
    local alpha = 1 - smooth ^ (math.clamp(dt, 0.001, 0.1) * 60)

    local aimType = C.AimType
    if aimType ~= "Character Face" then releaseFace() end
    local instant = aimType == "Hard Lock" or aimType == "Snap On Fire"
    -- this game overwrites the camera itself (see the check below): turn it through the mouse instead
    if U.AimMouseMode and aimType ~= "Character Face" and hasFn("mousemoverel") then
        aimType = "Mouse Move"
        if instant then alpha = 1 end
    end

    if aimType == "Hard Lock" or aimType == "Snap On Fire" then
        -- instant: the camera points exactly at the target, no smoothing
        local c = cam()
        c.CFrame = CFrame.lookAt(c.CFrame.Position, goal)
        U.aimLook = c.CFrame.LookVector
    elseif aimType == "Mouse Move" and hasFn("mousemoverel") then
        -- moves the real cursor (works in games that read the mouse delta, e.g. locked first person)
        local sp = screenPoint(goal)
        local dx, dy = (sp.X - center.X) * alpha, (sp.Y - center.Y) * alpha
        mousemoverel(dx, dy)
        -- switched here automatically: the camera check below verifies that the mouse really turns the view
        if U.AimMouseMode then U.mouseSent = { look = cam().CFrame.LookVector, px = math.sqrt(dx * dx + dy * dy) } end
    elseif aimType == "Character Face" then
        -- turns the character instead of the camera (third person)
        local char, hum, root = charOf(lp)
        if char then
            hum.AutoRotate = false
            faceLocked = true
            local flat = Vector3.new(goal.X, root.Position.Y, goal.Z)
            root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, flat), alpha)
        end
    else
        -- "Smooth Camera" (also the fallback when Mouse Move is not available)
        local c = cam()
        c.CFrame = c.CFrame:Lerp(CFrame.lookAt(c.CFrame.Position, goal), alpha)
        U.aimLook = c.CFrame.LookVector
    end
end)

-- Some games keep their own camera angles and write them back every frame. The aimbot then only wins while it
-- is locked: the moment it lets go, the camera jumps back to where the game had it ("the camera resets").
-- Right after the game's camera scripts we check whether the direction the aimbot set last frame survived.
-- If it was undone several frames in a row while the mouse did not move, the aimbot switches to moving the
-- mouse, which goes through the game's own camera controls and so keeps the view where it was aimed.
do
    local undone, deaf = 0, 0
    local name = "TerkanU_AimCamCheck"
    RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, U.Guard(function()
        -- in mouse mode: a clear mouse move that did not turn the camera at all means the mouse does not steer
        -- the view here (e.g. third person without holding the right mouse button): go back to camera aiming
        local sent = U.mouseSent
        U.mouseSent = nil
        if sent and U.AimMouseMode then
            if sent.px > 4 then
                if cam().CFrame.LookVector:Dot(sent.look) > math.cos(math.rad(0.2)) then deaf += 1 else deaf = 0 end
            end
            if deaf >= 15 then
                U.AimMouseMode, U.AimMouseBlocked, deaf, undone = nil, true, 0, 0
                notify("Aimbot", "Moving the mouse does not turn the camera here: back to turning the camera", "warn")
            end
            return
        end

        local want = U.aimLook
        U.aimLook = nil
        if not want or U.AimMouseMode or U.AimMouseBlocked then return end
        local moved = UserInputService:GetMouseDelta().Magnitude > 1
        if not moved and cam().CFrame.LookVector:Dot(want) < math.cos(math.rad(4)) then
            undone += 1
        else
            undone = math.max(undone - 1, 0)
        end
        if undone >= 8 then
            U.AimMouseMode = true
            if hasFn("mousemoverel") then
                notify("Aimbot", "This game resets the camera itself: aiming now moves the mouse instead", "warn")
            else
                notify("Aimbot", "This game resets the camera itself, and this executor has no mousemoverel to work around it", "warn")
            end
        end
    end))
    table.insert(U.Binds, name)
end

-- Silent aim only exists on executors that can hook metamethods (see the tab for details)
local CAN_HOOK = hasFn("hookmetamethod") and hasFn("getnamecallmethod") and hasFn("checkcaller") and hasFn("newcclosure")

if CAN_HOOK then
    ----------------------------------------------------------------------
    -- tab: Silent Aim
    ----------------------------------------------------------------------

    local silentTab = win:Tab("Silent")
    local silent = silentTab:Section("Silent Aim")
    local silentVis = silentTab:Section("Visuals", "right")

    local HOOKED = false   -- becomes true once the metamethod hooks below are installed

    toggle(silent, "Enabled", "SilentEnabled", false, function(v)
        if v and not HOOKED then
            -- no camera-flick fallback: silent aim either really is silent, or it stays off
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

    -- Real silent aim rewrites what the weapon script reads, so it needs metamethod hooks.
    -- Every path a gun can use to find its target is redirected: workspace raycasts, the old
    -- FindPartOnRay family, camera ray helpers, and Mouse.Hit / Target / UnitRay. Because the
    -- direction is rewritten from the ray origin straight to the target, it does not matter
    -- where the camera is looking.
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
        -- the circle only means something when targets are limited to it
        silentCircle(C.SilentFov, origin, C.SilentFovColor, C.SilentShowFov and not C.SilentAnyDir)

        silentTarget = selectTarget({
            Origin = origin, FOV = (not C.SilentAnyDir) and C.SilentFov or nil,
            MaxDist = C.SilentDist, Team = C.SilentTeam, Wall = C.SilentWall, AllowDead = not C.SilentDead,
            Part = C.SilentPart, Priority = C.SilentPriority, Sticky = silentTarget and silentTarget.plr or nil,
        })

        U.SilentTarget = silentTarget   -- the custom cursor reads this to name who is being aimed at

        -- a target behind the camera has no meaningful screen position, so no line for it
        local showLine = C.SilentFollowTarget and silentTarget ~= nil and silentTarget.onScreen
        silentLine(origin, silentTarget and silentTarget.screen or origin, C.SilentTargetColor, showLine)
        silentDot(silentTarget and silentTarget.screen or origin, C.SilentTargetColor, showLine)

        if os.clock() - silentTick > 0.4 and not firing() then silentTick = os.clock() rollSilent() end
    end)
end

----------------------------------------------------------------------
-- tab: Triggerbot
----------------------------------------------------------------------

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

-- returns (name, nil) when something valid is under the cursor, otherwise (nil, reason); the reason is
-- shown in the trigger status line so you can see WHY it is not firing
local function underCrosshair()
    if cursorOverMenu() then return nil, "cursor is on the menu" end   -- aiming at the menu is not aiming at the world
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
    -- Rage already clicks for its own target: two bots clicking means double shots
    if U.RageTarget and U.RageTarget() then
        trigSince = nil
        U.TrigTarget, U.TrigWhy = nil, "paused: Rage has a target"
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
    fireWeapon(C.TrigMethod, UserInputService:GetMouseLocation())   -- click where the enemy is under the cursor
end)

-- trigger status: a small line just below the crosshair while the triggerbot is on. It says what it
-- is aiming at, or why it is not firing (menu, hold key, wrong part, teammate ...).
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
end   -- trigger status

----------------------------------------------------------------------
-- tab: Rage
----------------------------------------------------------------------

-- rageTarget stays a file-level local (the cursor label reads it); everything else lives in this
-- block, because Luau allows at most 200 locals per function and the file is right at that limit
local rageTarget = nil
do
local rageTab = win:Tab("Rage")
local rage = rageTab:Section("Rage Bot")
local rageFire = rageTab:Section("Firing", "right")
local rageFilt = rageTab:Section("Filters", "right")
local rageAbil = rageTab:Section("Abilities")
local rageMove = rageTab:Section("Positioning & Spin")

-- small state of this tab in one table: the main chunk has (almost) no free local slots
local R = {
    AUTO = "Auto", NONE = "No Tool (fists)",
    skip = {},          -- [plr] = until when Rage passes over that player (gave up: no damage)
    warned = {},        -- extra keys we already warned about
    seen = {},          -- every tool name ever listed (only a NEW tool starts ticked as an ability)
    holdUntil = 0,      -- the ability tool stays in hand until then, afterwards the weapon comes back
    equipAt = 0, progressAt = 0, whyAt = 0,
}

toggle(rage, "Enabled", "RageEnabled", false)
-- while the menu is open Rage does nothing (no clicks, camera, teleport, keys), so the menu is always usable
-- and you can always switch Rage off; it carries on the moment the menu closes
toggle(rage, "Pause While Menu Open", "RagePauseMenu", true)
dropdown(rage, "Mode", "RageMode", { "Always On", "Hold Key" }, "Always On")
keybind(rage, "Rage Key", "RageKey", Enum.KeyCode.V)

-- who to shoot: everyone (best target by Priority) or one chosen player
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
-- a target that takes no damage for this long is passed over for 5 s (unreachable, god mode, stuck in a wall ...)
slider(rage, "Give Up If No Damage (0 = off)", "RageGiveUp", 0, 15, 4, { Decimals = 1, Suffix = "s" })

toggle(rageFire, "Auto Shoot", "RageShoot", true)
slider(rageFire, "Shoot Delay", "RageDelay", 0, 1000, 80, { Suffix = " ms" })
slider(rageFire, "Delay Jitter", "RageJitter", 0, 100, 0, { Suffix = "%" })
slider(rageFire, "Burst Shots", "RageBurst", 1, 10, 1)
slider(rageFire, "Burst Gap", "RageBurstGap", 10, 300, 40, { Suffix = " ms" })
slider(rageFire, "Only Fire Within", "RageAngle", 1, 180, 180, { Suffix = "°" })
dropdown(rageFire, "Fire Method", "RageMethod", FIRE_METHODS, "Auto")
toggle(rageFire, "Auto Equip Tool", "RageEquip", true)
-- an empty gun (its "Ammo" value at 0) is reloaded with R
toggle(rageFire, "Auto Reload", "RageReload", true)
-- what Rage holds while shooting: Auto = the first tool that is not an ability, No Tool = empty hands
-- (punch / M1 games), or one tool from your inventory. The list fills itself with your tools.
C.RageWeapon = R.AUTO
R.weaponDD = rageFire:Dropdown({ Text = "Weapon", Options = { R.AUTO, R.NONE }, Default = R.AUTO, Flag = "RageWeapon",
    Callback = function(v)
        C.RageWeapon = v or R.AUTO
        if R.refresh then task.defer(R.refresh) end   -- the weapon leaves the ability list at once
    end })
slider(rageFire, "Warm-up", "RageWarmup", 0, 3, 1, { Decimals = 1, Suffix = "s" })

toggle(rageFilt, "Team Check", "RageTeam", true)
toggle(rageFilt, "Dead Check", "RageDead", true)
toggle(rageFilt, "Ignore Walls", "RageIgnoreWalls", false)
toggle(rageFilt, "Skip ForceField", "RageNoFF", true)
toggle(rageFilt, "Skip Invisible Rigs", "RageNoInvis", true)
-- a gun with a "Range" value (Da Hood style: shotguns 70 studs) only picks targets it can reach
toggle(rageFilt, "Respect Weapon Range", "RageRange", true)

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

-- abilities ---------------------------------------------------------------
-- Every tool in the Backpack/hand is an ability (in The Strongest Battlegrounds the four moves are
-- tools). They are listed in "Abilities To Use"; new tools show up ticked, on their own. Loose keys
-- that are not tools (dash, ultimate ...) can be ticked under "Extra Keys". While Rage has a target
-- within range, ticked abilities are used in rotation, each respecting its own cooldown.
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
    R.toolOf = {}
    for _, holder in ipairs({ lp.Backpack, lp.Character }) do
        if holder then
            for _, x in ipairs(holder:GetChildren()) do
                if x:IsA("Tool") and not table.find(list, x.Name) then
                    table.insert(list, x.Name)
                    R.toolOf[x.Name] = x
                end
            end
        end
    end
    return list
end

-- An ability is a tool WITHOUT a model: The Strongest Battlegrounds' moves are empty tools. A tool with parts is a
-- weapon or an item (guns, knives, a wallet ...): pressing its hotbar key would just swap what you hold.
-- The tool is looked up live (not from the last scan). Right after a respawn a gun can exist for a moment before its
-- parts have streamed in: seen then, it looked like an empty tool, was taken for an ability, and Rage kept switching
-- to it. So an empty tool only counts as an ability once it has stayed empty for 2 seconds (or says it needs no
-- handle); until then it is treated as a weapon, which is the safe side.
R.firstSeen = setmetatable({}, { __mode = "k" })
function R.isAbilityTool(name)
    local char = lp.Character
    local t = (char and char:FindFirstChild(name)) or lp.Backpack:FindFirstChild(name)
    if not (t and t:IsA("Tool")) then t = R.toolOf and R.toolOf[name] end
    if not (t and t:IsA("Tool")) then return false end
    if t:FindFirstChildWhichIsA("BasePart", true) then return false end
    if not t.RequiresHandle then return true end
    local seen = R.firstSeen[t]
    if not seen then seen = os.clock() R.firstSeen[t] = seen end
    return os.clock() - seen > 2
end

-- a gun: a tool with an "Ammo" value (Da Hood style); returns the ammo left
function R.ammoOf(tool)
    local a = tool and tool:FindFirstChild("Ammo")
    if a and a:IsA("ValueBase") then return tonumber(a.Value) end
    return nil
end

local function refreshAbilities()
    local names = currentToolNames()
    local flags = {}
    for _, n in ipairs(names) do table.insert(flags, R.isAbilityTool(n) and "a" or "w") end
    local sig = table.concat(names, "|") .. "#" .. table.concat(flags) .. "#" .. tostring(C.RageWeapon)
    if sig == abilityLast then return end
    abilityLast = sig
    -- weapon list: the fixed choices, every tool, and the chosen weapon even while it is not in the inventory
    -- (dead, not given yet) - otherwise the dropdown would forget it
    local weapons = { R.AUTO, R.NONE }
    for _, n in ipairs(names) do table.insert(weapons, n) end
    if not table.find(weapons, C.RageWeapon) then table.insert(weapons, C.RageWeapon) end
    R.weaponDD:SetOptions(weapons)
    for _, n in ipairs(names) do
        if not slotOf[n] then slotOf[n], nextSlot = nextSlot, nextSlot + 1 end
        if not R.seen[n] then R.seen[n], chosenTools[n] = true, true end   -- a new tool starts ticked
    end
    -- only model-less tools are abilities, and the weapon is never one
    local abil = {}
    for _, n in ipairs(names) do
        if n ~= C.RageWeapon and R.isAbilityTool(n) then table.insert(abil, n) end
    end
    names = abil
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
-- Rage presses keys through VirtualInputManager, which this menu sees as real key presses: a key that is
-- also a menu keybind (F = Fly, G = Telekinesis fire, V = Rage key ...) would switch that feature on and
-- off every few hundred ms. Such keys are skipped, with one warning per key.
function R.menuKey(code)
    if win.ToggleKey == code then return true end
    for _, b in pairs(BIND) do
        if b:Get() == code then return true end
    end
    return false
end
function R.warnKey(k)
    if R.warned[k] then return end
    R.warned[k] = true
    notify("Rage", "Extra key " .. k .. " is skipped: a menu keybind already uses it", "warn")
end

rageAbil:Dropdown({ Text = "Extra Keys", Options = EXTRA_KEYS, Multi = true, Flag = "RageExtraKeys",
    Callback = function(picked)
        chosenKeys, R.warned = {}, {}
        for _, k in ipairs(picked) do chosenKeys[k] = true end
    end })
-- Equip + Activate puts the tool in your hand directly; Hotbar Key presses its number key instead
-- (the slot number is a guess: the order in which the tools were first seen)
dropdown(rageAbil, "Ability Method", "RageAbilityMethod", { "Equip + Activate", "Hotbar Key" }, "Equip + Activate")
slider(rageAbil, "Ability Range", "RageAbilityRange", 3, 150, 14, { Suffix = " st" })
slider(rageAbil, "Delay Between Abilities", "RageAbilityDelay", 50, 2000, 350, { Suffix = " ms" })
slider(rageAbil, "Cooldown Per Ability", "RageAbilityCd", 0, 20, 2, { Decimals = 1, Suffix = "s" })

R.refresh = refreshAbilities
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
    if UserInputService:GetFocusedTextBox() then return end   -- never type into chat

    local ready = {}
    for _, n in ipairs(abilityNames) do
        if chosenTools[n] and (abilityReady["t:" .. n] or 0) <= now then table.insert(ready, { tool = n }) end
    end
    for _, k in ipairs(EXTRA_KEYS) do
        if chosenKeys[k] and (abilityReady["k:" .. k] or 0) <= now then
            if R.menuKey(Enum.KeyCode[k]) then R.warnKey(k) else table.insert(ready, { key = k }) end
        end
    end
    if #ready == 0 then return end

    abilityIdx += 1
    local pick = ready[(abilityIdx - 1) % #ready + 1]
    -- last check on the real tool: a weapon or item is never used as an ability (and never swapped to)
    if pick.tool and (pick.tool == C.RageWeapon or not R.isAbilityTool(pick.tool)) then
        abilityReady["t:" .. pick.tool] = now + 5
        abilityLast = ""   -- rebuild the ability list on the next scan
        return
    end
    if pick.key then
        pressKey(Enum.KeyCode[pick.key])
        abilityReady["k:" .. pick.key] = now + C.RageAbilityCd
    else
        local char = lp.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local held = char and char:FindFirstChild(pick.tool)
        local slot = SLOT_KEYS[slotOf[pick.tool] or 99]
        if held and held:IsA("Tool") then
            held:Activate()   -- already in hand: its hotbar key would put it AWAY again
        elseif C.RageAbilityMethod == "Hotbar Key" and slot and not R.menuKey(slot) then
            pressKey(slot)
        else
            local tool = lp.Backpack:FindFirstChild(pick.tool)
            if tool and tool:IsA("Tool") and hum then
                hum:EquipTool(tool)
                tool:Activate()
            end
        end
        abilityReady["t:" .. pick.tool] = now + C.RageAbilityCd
        -- keep the ability tool in hand for a moment, then the weapon comes back (R.equipWeapon)
        R.holdUntil = now + math.min(C.RageAbilityDelay / 1000, 0.5)
    end
    nextAbility = now + C.RageAbilityDelay / 1000
end
U.RageAbilityState = function() return abilityNames, chosenTools, chosenKeys end   -- self-tests

-- puts the chosen weapon in hand (not while an ability tool is still being used); a few times a second at most
function R.equipWeapon(now)
    if not C.RageEquip or now < R.holdUntil or now < R.equipAt then return end
    R.equipAt = now + 0.15
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local held = char:FindFirstChildOfClass("Tool")
    local w = C.RageWeapon
    -- (only model-less tools count: an old config may still have guns ticked as abilities)
    local function isAbility(name) return C.RageAbilitiesOn and chosenTools[name] and name ~= w and R.isAbilityTool(name) end
    if w == R.NONE then
        if held then hum:UnequipTools() end
    elseif w == R.AUTO then
        -- a gun first (one with ammo left if possible); in games without guns the first tool that is no ability;
        -- only abilities in the inventory: fight with empty hands
        local guns, other = {}, nil
        for _, x in ipairs(lp.Backpack:GetChildren()) do
            if x:IsA("Tool") and not isAbility(x.Name) then
                if R.ammoOf(x) then table.insert(guns, x) elseif not other then other = x end
            end
        end
        if held and not isAbility(held.Name) then
            if R.ammoOf(held) or #guns == 0 then return end   -- a gun (reloaded when empty), or no guns here at all
        end
        local pick
        for _, g in ipairs(guns) do
            if (R.ammoOf(g) or 0) > 0 then pick = g break end
        end
        pick = pick or guns[1] or other
        if pick then hum:EquipTool(pick) elseif held then hum:UnequipTools() end
    elseif not (held and held.Name == w) then
        local x = lp.Backpack:FindFirstChild(w)
        if x and x:IsA("Tool") then hum:EquipTool(x) end
    end
end

-- empty gun in hand: press R (once a second at most, not while the game already reloads, never while typing)
function R.autoReload(now)
    if not C.RageReload or now < (R.reloadAt or 0) then return end
    local char = lp.Character
    local ammo = R.ammoOf(char and char:FindFirstChildOfClass("Tool"))
    if not ammo or ammo > 0 then return end
    local be = char:FindFirstChild("BodyEffects")
    local busy = be and be:FindFirstChild("Reload")
    if busy and busy:IsA("ValueBase") and busy.Value == true then return end
    if UserInputService:GetFocusedTextBox() or R.menuKey(Enum.KeyCode.R) then return end
    R.reloadAt = now + 1
    pressKey(Enum.KeyCode.R)
end

-- a spot Rage may put the character on: a real number, and not in (or under) the void
function R.safeSpot(p)
    if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z or p.Magnitude > 1e5 then return false end
    local floor = workspace.FallenPartsDestroyHeight
    if floor ~= floor then floor = -1000 end   -- NaN in some games
    return p.Y > math.max(floor, -1000) + 20
end

-- after teleporting every frame the physics has built up speed: drop it, or the character shoots away
function R.stopPos()
    R.positioned = false
    local _, _, root = charOf(lp)
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

-- why there is no target: the reason of the nearest player that was passed over (for the status text)
function R.noTargetWhy()
    local camPos = cam().CFrame.Position
    local anyBlack = next(U.Black) ~= nil
    local why, bestDist = nil, math.huge
    for _, e in ipairs(U.Others()) do
        local plr, char, hum, root = e.plr, e.char, e.hum, e.root
        if C.RageWho == RAGE_AUTO or plr.Name == C.RageWho then
            local r
            local dist = root and (root.Position - camPos).Magnitude or 1e9
            if C.ListRespectWhite and U.White[plr.Name] then r = "whitelisted"
            elseif C.ListOnlyBlack and anyBlack and not U.Black[plr.Name] then r = "not on blacklist"
            elseif R.skip[plr] then r = "gave up, no damage"
            elseif not (char and hum and root) then r = "no character"
            elseif C.RageDead and hum.Health <= 0 then r = "dead"
            elseif C.RageDead and U.isDowned(char) then r = "knocked out"
            elseif C.RageTeam and sameTeam(plr) then r = "teammate"
            elseif C.RageNoFF and char:FindFirstChildOfClass("ForceField") then r = "forcefield"
            elseif C.RageNoInvis and U.isInvisible(char) then r = "invisible"
            elseif dist > C.RageDist then r = "too far"
            elseif dist < C.RageMinDist then r = "too close"
            else
                local part = char:FindFirstChild("Head") or root
                local sp, on = screenPoint(part.Position)
                if C.RageFov > 0 and not (on and (sp - cursorOrCenter(false)).Magnitude <= C.RageFov) then r = "outside FOV"
                elseif not C.RageIgnoreWalls then r = "behind wall" end
            end
            if r and dist < bestDist then why, bestDist = r, dist end
        end
    end
    if C.RageWho ~= RAGE_AUTO and not Players:FindFirstChild(C.RageWho) then return "not in server" end
    return why or (#U.Others() == 0 and "no other players" or nil)
end

local rageState, rageOnAt = "off", 0   -- "off" | "loading" | "active"; driven by the status pill below
local rageLockedAt, rageKills = 0, 0
local burstLeft, nextShot, nextBurst = 0, 0, 0
local rageSpun = false                  -- true while WE have AutoRotate switched off for the spin bot

local function rageReset()
    rageTarget, burstLeft = nil, 0
    if R.positioned then R.stopPos() end
    if rageSpun then
        rageSpun = false
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.AutoRotate = true end
    end
end
onUnload(rageReset)

-- where the local character should stand relative to the target for the chosen Position mode
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
    -- Strafe: slides left and right of the target's facing
    return base.Position + base.RightVector * math.sin(now * C.RagePosSpeed) * d + up
end

local function pingSeconds()
    local ok, v = pcall(function() return lp:GetNetworkPing() end)
    return (ok and type(v) == "number") and v or 0
end

renderLast(function(dt)
    if not (C.RageEnabled and U.Running) or rageState ~= "active"
        or (C.RageMode == "Hold Key" and not (BIND.RageKey and BIND.RageKey:IsDown())) then
        -- off / warming up / key released: drop the target, give the character its rotation back
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

    -- keep the current target for a minimum time (or forever when Sticky) so it does not flicker
    local prev = rageTarget
    local keep = prev and (C.RageSticky or now - rageLockedAt < C.RageSwitch)
    for plr, untilT in pairs(R.skip) do
        if untilT <= now then R.skip[plr] = nil end
    end
    R.autoReload(now)
    -- a gun with a Range value only picks targets it can reach (distances are measured from the camera). Not while
    -- Position is on: then Rage moves you next to the target anyway.
    local maxDist = C.RageDist
    if C.RageRange and C.RagePosition == "Off" then
        local tool = char:FindFirstChildOfClass("Tool")
        local range = tool and tool:FindFirstChild("Range")
        if range and range:IsA("ValueBase") and tonumber(range.Value) then
            maxDist = math.min(maxDist, range.Value + (cam().CFrame.Position - root.Position).Magnitude)
        end
    end
    local t = selectTarget({
        Only = C.RageWho ~= RAGE_AUTO and C.RageWho or nil, Skip = R.skip,
        FOV = C.RageFov > 0 and C.RageFov or nil, MaxDist = maxDist, MinDist = C.RageMinDist,
        Team = C.RageTeam, NoFF = C.RageNoFF, NoInvis = C.RageNoInvis, Wall = not C.RageIgnoreWalls, AllowDead = not C.RageDead,
        Part = C.RagePart, Priority = C.RagePriority, Origin = cursorOrCenter(false),
        Sticky = keep and prev.plr or nil,
    })

    if prev and (not t or t.plr ~= prev.plr) then
        if prev.hum.Health <= 0 then rageKills += 1 end
        burstLeft = 0
    end
    if t and (not prev or t.plr ~= prev.plr) then rageLockedAt = now end

    -- give up on a target that takes no damage for a while (unreachable, god mode, stuck in a wall ...):
    -- pass over it for 5 s. Not for one chosen player (there is nobody else), and only while Rage attacks.
    if t and C.RageGiveUp > 0 and C.RageWho == RAGE_AUTO and (C.RageShoot or C.RageAbilitiesOn) then
        local hp = t.hum.Health
        if t.plr ~= R.hpPlr then R.hpPlr, R.progressAt = t.plr, now
        elseif hp < R.hp then R.progressAt = now end
        R.hp = hp
        if now - R.progressAt > C.RageGiveUp then
            R.skip[t.plr], R.hpPlr, burstLeft = now + 5, nil, 0
            t = nil
        end
    end

    rageTarget = t
    if not t then
        if R.positioned then R.stopPos() end
        if now - R.whyAt > 0.25 then R.whyAt, R.why = now, R.noTargetWhy() end
        return
    end
    R.why = nil

    if C.RagePosition ~= "Off" then
        local base = t.root.CFrame
        local spot = rageSpot(base, now)
        if C.RagePosSmooth > 0 then
            spot = root.Position:Lerp(spot, 1 - (C.RagePosSmooth / 100) ^ (math.min(dt, 0.1) * 60))
        end
        -- never follow a target into the void or to a broken (NaN / far away) position
        if R.safeSpot(spot) then
            -- stay upright: face the target on our own height. Straight above/below it there is no
            -- horizontal direction (lookAt would produce a NaN CFrame), so keep the current yaw then.
            local flat = Vector3.new(base.Position.X - spot.X, 0, base.Position.Z - spot.Z)
            if flat.Magnitude > 0.05 then
                root.CFrame = CFrame.lookAt(spot, spot + flat)
            else
                root.CFrame = CFrame.new(spot) * root.CFrame.Rotation
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            R.positioned = true
        elseif R.positioned then
            R.stopPos()
        end
    elseif R.positioned then
        R.stopPos()
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
    R.equipWeapon(now)
    if not C.RageShoot then return end
    if off > C.RageAngle then return end

    -- burst fire: RageBurst shots RageBurstGap ms apart, then wait the (jittered) shoot delay
    local function delay()
        local jitter = 1 + (math.random() * 2 - 1) * C.RageJitter / 100
        return (C.RageDelay / 1000) * jitter
    end
    if burstLeft == 0 and now >= nextBurst then burstLeft = C.RageBurst end
    if burstLeft > 0 and now >= nextShot then
        fireWeapon(C.RageMethod)
        burstLeft -= 1
        nextShot = now + C.RageBurstGap / 1000
        if burstLeft == 0 then nextBurst = now + delay() end
    end
end)
U.RageTarget = function() return rageTarget end   -- exposed for self-tests

-- rage status -----------------------------------------------------------
-- Plain text, fixed just above the middle of the screen, for as long as Rage is on:
-- "RAGE LOADING..." with animated dots during the warm-up, then "RAGE ACTIVE" (with the
-- target's name) - or "RAGE READY" in hold-key mode while the key is up. The colour (or
-- rainbow) is chosen on the Notifications page. It disappears the moment Rage is switched off.

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
R.glow = U.NewGlow(rageText)
onUnload(function() U.DropGlow(R.glow) end)

local rageAlpha = 0

local function rageTextColor()
    if C.RageStatusRainbow then return Color3.fromHSV((os.clock() * 0.4) % 1, 0.9, 1) end
    return C.RageStatusColor or Color3.fromRGB(255, 255, 255)
end

renderLast(function(dt)
    -- state follows the flag, however it got switched (button, keybind or a loaded config)
    if C.RageEnabled and U.Running then
        if rageState == "off" then rageState, rageOnAt, rageKills = "loading", os.clock(), 0 end
        if rageState == "loading" and os.clock() - rageOnAt >= C.RageWarmup then
            rageState = "active"
            notify("Rage", "Active", "success", "toggle")
        end
    else
        rageState = "off"
    end

    local want = rageState ~= "off" and C.RageStatus
    rageAlpha += ((want and 1 or 0) - rageAlpha) * math.min(dt * 12, 1)
    rageText.Visible = rageAlpha > 0.02
    if not rageText.Visible then U.SyncGlow(R.glow, false) return end

    local text
    if rageState == "loading" then
        -- one to three dots, padded with spaces so the text does not shift sideways
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
        else
            local why = R.why and (" (" .. R.why .. ")") or ""
            if C.RageWho ~= RAGE_AUTO then
                text = "RAGE ACTIVE  ·  waiting for " .. C.RageWho .. why .. kills
            else
                text = "RAGE ACTIVE  ·  no target" .. why .. kills
            end
        end
    end

    local center = viewportCenter()
    rageText.Text = text
    rageText.TextColor3 = rageTextColor()
    rageText.TextTransparency = 1 - rageAlpha
    rageText.TextStrokeTransparency = math.clamp(0.35 + (1 - rageAlpha), 0, 1)
    rageText.Position = UDim2.fromOffset(center.X, center.Y - 30)
    U.SyncGlow(R.glow, C.NotifGlow, rageText.TextColor3, C.NotifGlowSize or 6, rageAlpha)
end)
end   -- rage block

----------------------------------------------------------------------
-- tab: Cursor (custom crosshair + "aiming at" label)
----------------------------------------------------------------------

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
-- a soft light around the crosshair (and the target name) in the cursor's own colour, rainbow included
toggle(curLook, "Glow", "CursorGlow", false)
slider(curLook, "Glow Size", "CursorGlowSize", 2, 16, 6, { Suffix = " px" })
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

-- what each style is made of: arm angles (degrees), plus a centre dot and/or a ring
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
curRoot.Name = U.rname()
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

-- 8 arms, each of which can be split into two dashes = 16 pieces at most
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

-- glow: two soft layers behind every piece. Roblox UI cannot blur, so a bigger, rounded, see-through copy in
-- the same colour is what reads as light. [1] = inner (brighter), [2] = outer (fainter).
local curGlow = { arms = {}, label = U.NewGlow(curLabel) }
do
    local function halo()
        local f = Instance.new("Frame")
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.BorderSizePixel = 0
        f.ZIndex = 0
        f.Visible = false
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = f
        f.Parent = curRoot
        return f
    end
    local function ringHalo()
        local f = halo()
        f.BackgroundTransparency = 1
        local stroke = Instance.new("UIStroke"); stroke.Parent = f
        return { frame = f, stroke = stroke }
    end
    for i = 1, #curArms do curGlow.arms[i] = { halo(), halo() } end
    curGlow.dot = { halo(), halo() }
    curGlow.ring = { ringHalo(), ringHalo() }
end
local GLOW_ALPHA = { 0.62, 0.84 }   -- transparency of the inner / outer layer

onUnload(function() curRoot:Destroy() end)

-- The normal pointer is hidden while the custom one is drawn, and handed back afterwards.
-- It is hidden by giving it a fully transparent 1x1 image, NOT with MouseIconEnabled: games like The Strongest
-- Battlegrounds switch MouseIconEnabled back on every frame, and switching it off again every frame cost ~3 ms per
-- frame (measured). No game touched MouseIcon, so the blank image stays put and costs nothing.
-- Without getcustomasset the old MouseIconEnabled way is used.
local BLANK_PNG = "\137\80\78\71\13\10\26\10\0\0\0\13\73\72\68\82\0\0\0\1\0\0\0\1\8\6\0\0\0\31\21\196\137\0\0\0\11"
    .. "\73\68\65\84\120\156\99\96\0\2\0\0\5\0\1\122\94\171\63\0\0\0\0\73\69\78\68\174\66\96\130"
local sysCursor = {}   -- enabled / icon: the game's own values before we changed them; blank: our image
local function blankIcon()
    if sysCursor.blank == nil then
        sysCursor.blank = false
        pcall(function()
            if not isfolder("Terkan") then makefolder("Terkan") end
            writefile("Terkan/cursor_blank.png", BLANK_PNG)
            sysCursor.blank = getcustomasset("Terkan/cursor_blank.png")
        end)
    end
    return sysCursor.blank
end
local function setSystemCursor(visibleIcon)
    local blank = hasFn("getcustomasset") and blankIcon()
    if blank then
        if sysCursor.icon == nil then sysCursor.icon = UserInputService.MouseIcon end
        local want = visibleIcon and sysCursor.icon or blank
        if UserInputService.MouseIcon ~= want then UserInputService.MouseIcon = want end
    else
        if sysCursor.enabled == nil then sysCursor.enabled = UserInputService.MouseIconEnabled end
        UserInputService.MouseIconEnabled = visibleIcon
    end
end
local function restoreSystemCursor()
    if sysCursor.icon ~= nil then
        UserInputService.MouseIcon = sysCursor.icon
        sysCursor.icon = nil
    end
    if sysCursor.enabled ~= nil then
        UserInputService.MouseIconEnabled = sysCursor.enabled
        sysCursor.enabled = nil
    end
end
onUnload(restoreSystemCursor)

-- who is being aimed at: rage / aimbot / silent target first, otherwise whoever is under the cursor
local function cursorTargetPlayer(pos)
    if C.CursorSource ~= "Under Crosshair" then
        local t = (C.RageEnabled and rageTarget) or (C.AimEnabled and aimTarget) or U.SilentTarget
        if t and t.plr and charOf(t.plr) then return t.plr end   -- dead players are never shown
    end
    local ray = cam():ViewportPointToRay(pos.X, pos.Y)
    rayParams.FilterDescendantsInstances = { lp.Character }
    local res = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
    if not res then return end
    local model = res.Instance:FindFirstAncestorOfClass("Model")
    local plr = model and Players:GetPlayerFromCharacter(model)
    if plr and plr ~= lp and charOf(plr) then return plr end
end

local curScale = 1            -- smoothed scale for the "on target" animations
local curLastPlr, curNewAt = nil, 0

renderLast(function()
    local put = U.put
    if not (C.CursorEnabled and U.Running) then
        put(curRoot, "Visible", false)
        restoreSystemCursor()
        return
    end

    -- over the menu the normal pointer is needed to click anything
    if cursorOverMenu() then
        put(curRoot, "Visible", false)
        setSystemCursor(true)
        return
    end
    setSystemCursor(not C.CursorHideSys)

    local pos = C.CursorPos == "Screen Center" and viewportCenter() or UserInputService:GetMouseLocation()
    put(curRoot, "Visible", true)
    put(curRoot, "Position", UDim2.fromOffset(pos.X, pos.Y))

    local t = os.clock()
    local col = C.CursorRainbow and Color3.fromHSV((t * C.CursorRainbowSpeed) % 1, 0.9, 1) or C.CursorColor

    local plr = cursorTargetPlayer(pos)
    if plr ~= curLastPlr then curLastPlr, curNewAt = plr, t end

    -- size animation ---------------------------------------------------
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

    -- arms (or dashes)
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
                put(piece.frame, "Size", UDim2.fromOffset(math.max((seg[2] - seg[1]) * size, 1), thick))
                put(piece.frame, "Position", UDim2.fromOffset(dx * mid, dy * mid))
                put(piece.frame, "Rotation", a)
                put(piece.frame, "BackgroundColor3", col)
                put(piece.stroke, "Enabled", C.CursorOutline)
                put(piece.frame, "Visible", true)
                for k, h in ipairs(curGlow.arms[used]) do
                    put(h, "Visible", C.CursorGlow)
                    if C.CursorGlow then
                        local pad = C.CursorGlowSize * k / 2
                        put(h, "Size", UDim2.fromOffset(piece.frame.Size.X.Offset + pad * 2, thick + pad * 2))
                        put(h, "Position", piece.frame.Position) put(h, "Rotation", a)
                        put(h, "BackgroundColor3", col) put(h, "BackgroundTransparency", GLOW_ALPHA[k])
                    end
                end
            end
        end
    end
    for i = used + 1, #curArms do
        put(curArms[i].frame, "Visible", false)
        for _, h in ipairs(curGlow.arms[i]) do put(h, "Visible", false) end
    end

    -- centre dot
    put(curDot.frame, "Visible", parts.dot == true)
    if parts.dot then
        local d = C.CursorDot * curScale
        put(curDot.frame, "Size", UDim2.fromOffset(d, d))
        put(curDot.frame, "Position", UDim2.fromOffset(0, 0))
        put(curDot.frame, "BackgroundColor3", col)
        put(curDot.stroke, "Enabled", C.CursorOutline)
    end
    for k, h in ipairs(curGlow.dot) do
        put(h, "Visible", C.CursorGlow and parts.dot == true)
        if h.Visible then
            local d = C.CursorDot * curScale + C.CursorGlowSize * k
            put(h, "Size", UDim2.fromOffset(d, d))
            put(h, "Position", UDim2.fromOffset(0, 0))
            put(h, "BackgroundColor3", col) put(h, "BackgroundTransparency", GLOW_ALPHA[k])
        end
    end

    -- ring
    put(curRing, "Visible", parts.ring == true)
    if parts.ring then
        local d = size * 2
        put(curRing, "Size", UDim2.fromOffset(d, d))
        put(curRingStroke, "Color", col)
        put(curRingStroke, "Thickness", thick)
    end
    for k, h in ipairs(curGlow.ring) do
        put(h.frame, "Visible", C.CursorGlow and parts.ring == true)
        if h.frame.Visible then
            put(h.frame, "Size", curRing.Size)
            put(h.stroke, "Color", col)
            put(h.stroke, "Thickness", thick + C.CursorGlowSize * k)
            put(h.stroke, "Transparency", GLOW_ALPHA[k])
        end
    end

    -- "aiming at" label --------------------------------------------------
    local showLabel = C.CursorLabel and plr ~= nil
    put(curLabel, "Visible", showLabel)
    if showLabel then
        local text = plr.DisplayName
        if C.CursorLabelInfo then
            local _, hum, root = charOf(plr)
            if hum and root then
                text = string.format("%s  |  %d st  |  %d hp", text, (root.Position - cam().CFrame.Position).Magnitude, hum.Health)
            end
        end

        -- measured from the UNscaled cursor so the size animation never moves or resizes the text
        local extent = (parts.ring and C.CursorSize or (parts.arms and (C.CursorGap + C.CursorSize) or 0)) + (parts.dot and C.CursorDot / 2 or 0) + 8
        local textScale, textFade = 1, 0
        local ta = C.CursorLabelAnim
        if ta == "Pulse" then
            textScale = 1 + math.sin(t * speed * 2 * math.pi) * amount * 0.5
        elseif ta == "Pop" then
            -- springs in with a little overshoot each time the target changes
            local p = math.clamp((t - curNewAt) / 0.35, 0, 1)
            local c1 = 1.70158
            local ease = 1 + (c1 + 1) * (p - 1) ^ 3 + c1 * (p - 1) ^ 2
            textScale = 0.4 + 0.6 * ease
        elseif ta == "Fade" then
            textFade = 0.5 * (0.5 + 0.5 * math.sin(t * speed * 2 * math.pi))
        end

        put(curLabel, "Text", text)
        put(curLabel, "TextSize", math.max(math.floor(C.CursorLabelSize * textScale + 0.5), 6))
        put(curLabel, "TextColor3", C.CursorLabelSame and col or C.CursorLabelColor)
        put(curLabel, "TextTransparency", textFade)
        put(curLabel, "Position", UDim2.fromOffset(0, extent))
    end
    U.SyncGlow(curGlow.label, C.CursorGlow and showLabel, curLabel.TextColor3, C.CursorGlowSize * 0.75, 1 - curLabel.TextTransparency)
end)

----------------------------------------------------------------------
-- tab: ESP
----------------------------------------------------------------------

local visTab = win:Tab("ESP")
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
-- lobby / waiting-room / spectator rigs: fully see-through, or parked far under the map (Arsenal keeps dead and
-- respawning players ~450 studs below the arena). Drawing them put names and lines where nobody is.
toggle(esp, "Skip Hidden Rigs", "ESPNoHidden", true)
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
toggle(espCol, "Health Bar Red When Low", "ESPHealthShift", false)
color(espCol, "Whitelisted Player", "ListWhiteColor", Color3.fromRGB(80, 200, 255))
color(espCol, "Blacklisted Player", "ListBlackColor", Color3.fromRGB(255, 200, 0))
slider(espCol, "Chams Transparency", "ESPFillTrans", 0, 1, 0.55, { Decimals = 2 })
slider(espCol, "Tracer Width", "ESPTracerWidth", 1, 6, 1.5, { Decimals = 1, Suffix = " px" })

local espRoot = Instance.new("Folder")
espRoot.Name = U.rname()
espRoot.Parent = parentGui()
onUnload(function() espRoot:Destroy() end)

-- all 2D ESP frames (health bar, skeleton, tracer) live in one container of their own, so anything in it that no live
-- ESP object owns can be recognised and removed (the overlay itself is shared with other features)
U.EspLayer = Instance.new("Frame")
U.EspLayer.Name = U.rname()
U.EspLayer.BackgroundTransparency = 1
U.EspLayer.BorderSizePixel = 0
U.EspLayer.Size = UDim2.fromScale(1, 1)
U.EspLayer.Parent = overlay

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

-- Joint world positions for the skeleton, keyed by name (R6 names are synthetic: limb tops / bottoms
-- rather than real instances) plus a fixed list of bone connections per rig. Keying by name lets the
-- ESP loop project each joint on screen ONCE per frame and reuse it for every bone touching it, instead
-- of projecting both endpoints of every bone separately (most joints are shared by 2+ bones).
local R15_JOINT_PARTS = {
    "Head", "UpperTorso", "LowerTorso",
    "LeftUpperArm", "LeftLowerArm", "LeftHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperArm", "RightLowerArm", "RightHand", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}
local R15_BONES = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}
local R6_BONES = {
    { "Head", "Neck" }, { "Neck", "Pelvis" },
    { "LeftShoulder", "RightShoulder" }, { "LeftHip", "RightHip" },
    { "LeftShoulder", "LeftElbow" }, { "RightShoulder", "RightElbow" },
    { "LeftHip", "LeftAnkle" }, { "RightHip", "RightAnkle" },
}

-- The joint PARTS are looked up once a second per character (15 FindFirstChild calls per player per frame cost ~1.8 ms
-- per frame in Arsenal, whose characters have ~60 children); their positions are read every frame into a reused table.
local R6_LIMBS = { Head = "Head", Torso = "Torso", LA = "Left Arm", RA = "Right Arm", LL = "Left Leg", RL = "Right Leg" }
U.skelCache = setmetatable({}, { __mode = "k" })
U.skelJoints = function(char, hum)
    local now = os.clock()
    local sc = U.skelCache[char]
    if not sc or now - sc.at > 1 then
        local r15 = hum.RigType == Enum.HumanoidRigType.R15
        local parts = {}
        for key, name in pairs(r15 and R15_JOINT_PARTS or R6_LIMBS) do
            local p = char:FindFirstChild(name)
            if p and p:IsA("BasePart") then parts[r15 and name or key] = p end
        end
        sc = { at = now, r15 = r15, parts = parts, pos = sc and sc.pos or {} }
        U.skelCache[char] = sc
    end
    local pos, parts = sc.pos, sc.parts
    table.clear(pos)
    if sc.r15 then
        for name, p in pairs(parts) do pos[name] = p.Position end
        return pos, R15_BONES
    end
    local function ends(p)
        local cf, h = p.CFrame, p.Size.Y / 2
        return cf:PointToWorldSpace(Vector3.new(0, h, 0)), cf:PointToWorldSpace(Vector3.new(0, -h, 0))
    end
    if parts.Head then pos.Head = parts.Head.Position end
    if parts.Torso then pos.Neck, pos.Pelvis = ends(parts.Torso) end
    if parts.LA then pos.LeftShoulder, pos.LeftElbow = ends(parts.LA) end
    if parts.RA then pos.RightShoulder, pos.RightElbow = ends(parts.RA) end
    if parts.LL then pos.LeftHip, pos.LeftAnkle = ends(parts.LL) end
    if parts.RL then pos.RightHip, pos.RightAnkle = ends(parts.RL) end
    return pos, R6_BONES
end

-- why the ESP set of a player was (re)built - kept for U.EspStats(), to see what makes the number of sets grow
U.EspBuilds, U.EspSwept, U.EspLog = 0, 0, {}

local function buildESP(plr, why)
    local o = { plr = plr, tick = 0 }
    U.EspBuilds += 1
    table.insert(U.EspLog, ("%.1f %s %s"):format(os.clock() % 10000, plr.Name, why or "new"))
    if #U.EspLog > 20 then table.remove(U.EspLog, 1) end

    o.hl = Instance.new("Highlight")
    o.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    o.hl.Enabled = false
    o.hl.Parent = espRoot

    -- health bar: a dark track just left of the box, the fill grows from the bottom up. It is a plain 2D
    -- frame on the overlay, placed every frame from the projected corners of the 3D box (a BillboardGui
    -- carrying only frames did not render at all, so this cannot go missing)
    o.hpBack = frame(U.EspLayer, {
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

    -- skeleton: up to 14 thin 2D lines between joints, drawn on the overlay like the tracer
    o.bones = {}
    for i = 1, 14 do
        o.bones[i] = frame(U.EspLayer, { AnchorPoint = Vector2.new(0.5, 0.5), Visible = false })
    end

    -- text stack above the head; hidden labels take no space (bottom aligned)
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

    -- real 3D box: 12 thin edges adorned straight onto the root part (no extra parts in the
    -- workspace). Fixed proportions on purpose - the true bounding box balloons with tools.
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

    o.tracer = frame(U.EspLayer, { AnchorPoint = Vector2.new(0.5, 0.5), Visible = false })
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
end

local function destroyESP(o)
    for _, key in ipairs({ "hl", "hpBack", "info", "tracer" }) do
        if o[key] then pcall(function() o[key]:Destroy() end) end
    end
    for _, e in ipairs(o.edges or {}) do pcall(function() e:Destroy() end) end
    for _, b in ipairs(o.bones or {}) do pcall(function() b:Destroy() end) end
end

-- hidden once, not re-hidden every frame while the player stays off the ESP
local function hideESP(o)
    if o.isHidden then return end
    o.isHidden = true
    U.put(o.hl, "Enabled", false)
    U.put(o.hpBack, "Visible", false)
    U.put(o.info, "Enabled", false)
    U.put(o.tracer, "Visible", false)
    for _, e in ipairs(o.edges) do U.put(e, "Visible", false) end
    for _, b in ipairs(o.bones) do U.put(b, "Visible", false) end
end

connect(Players.PlayerRemoving, function(plr)
    if ESP[plr] then destroyESP(ESP[plr]) ESP[plr] = nil end
end)
onUnload(function() for _, o in pairs(ESP) do destroyESP(o) end table.clear(ESP) end)

-- Self-healing: once a second, drop the sets of players who are gone or whose instances were destroyed, and destroy
-- everything in the ESP folder / layer that no live set owns. Whatever the cause of a leak, it cannot pile up.
function U.EspSweep()
    for plr, o in pairs(ESP) do
        if not plr.Parent then
            destroyESP(o) ESP[plr] = nil
        elseif o.hl.Parent ~= espRoot or o.hpBack.Parent ~= U.EspLayer then
            destroyESP(o) ESP[plr] = nil   -- rebuilt on the next frame (reason "orphaned")
            U.EspOrphaned = plr
        end
    end
    local live = {}
    for _, o in pairs(ESP) do
        live[o.hl], live[o.info], live[o.hpBack], live[o.tracer] = true, true, true, true
        for _, e in ipairs(o.edges) do live[e] = true end
        for _, b in ipairs(o.bones) do live[b] = true end
    end
    local removed = 0
    for _, box in ipairs({ espRoot, U.EspLayer }) do
        for _, child in ipairs(box:GetChildren()) do
            if not live[child] then child:Destroy() removed += 1 end
        end
    end
    U.EspSwept += removed
    return removed
end

-- for debugging: how many ESP sets exist, how many instances they hold, how often they were built / swept
-- A point on screen, but only when it is clearly in front of the camera. A point just in front of the lens
-- (a player standing inside / right next to you) projects to thousands of pixels, which drew huge broken lines.
function U.espPoint(pos)
    local v = (U.espCam or cam()):WorldToViewportPoint(pos)
    return Vector2.new(v.X, v.Y), v.Z > 1
end

-- see "Skip Hidden Rigs": invisible, or more than 250 studs below your own character
function U.espHidden(char, root)
    if U.isInvisible(char) then return true end
    local me = U.espMeRoot
    return me ~= nil and root.Position.Y < me.Position.Y - 250
end

function U.EspStats()
    local sets = 0
    for _ in pairs(ESP) do sets += 1 end
    return { sets = sets, folder = #espRoot:GetChildren(), layer = #U.EspLayer:GetChildren(),
             builds = U.EspBuilds, swept = U.EspSwept, log = U.EspLog }
end

-- The 2D parts (tracers, health bars, skeleton) must be projected with exactly the camera the frame is drawn with,
-- or they hang beside the character. So they are drawn at PreRender, the last moment before drawing: after the
-- aimbot / rage turned the camera, and after games that set their own field of view late in the frame (Arsenal
-- puts it back to 70 after RenderStepped - with Custom FOV on, the ESP used to project with 120 and slid inwards).
-- Custom FOV is applied here once more first, so it really is the field of view the frame is drawn with.
local function drawESP()
    if not U.Running then return end
    if U.applyFov then U.applyFov() end
    -- ESP off: hide every set once, then skip the whole player loop until it is switched on again
    if not C.ESPEnabled then
        if not U.espAllHidden then
            for _, o in pairs(ESP) do hideESP(o) end
            U.espAllHidden = true
        end
        return
    end
    U.espAllHidden = false
    local c = cam()
    U.espCam = c
    local _, _, meRoot = charOf(lp, true)
    U.espMeRoot = meRoot
    local camCF = c.CFrame
    local camPos, camRight = camCF.Position, camCF.RightVector
    local vp = c.ViewportSize
    local now = os.clock()
    local put = U.put

    if now - (U.EspSweepAt or 0) > 1 then
        U.EspSweepAt = now
        U.EspSweep()
    end

    for _, e in ipairs(U.Others()) do
        local plr = e.plr
        do
            local char, hum, root = e.char, e.hum, e.root
            if not (hum and root) or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then char = nil end
            local show = C.ESPEnabled and char ~= nil
            if show and C.ESPTeam and sameTeam(plr) then show = false end
            if show and C.ESPNoHidden and U.espHidden(char, root) then show = false end
            local dist = show and (root.Position - camPos).Magnitude or 0
            if show and dist > C.ESPDist then show = false end

            local o = ESP[plr]
            if show and not o then
                o = buildESP(plr, U.EspOrphaned == plr and "orphaned" or "new")
                if U.EspOrphaned == plr then U.EspOrphaned = nil end
                ESP[plr] = o
            end
            if o then
                if not show then
                    hideESP(o)
                else
                    o.isHidden = false
                    -- blacklist / whitelist colours win over team colours
                    local listCol = (U.Black[plr.Name] and C.ListBlackColor) or (U.White[plr.Name] and C.ListWhiteColor) or nil
                    local teamCol = listCol or (C.ESPTeamColors and plr.Team and plr.TeamColor.Color)

                    put(o.hl, "Adornee", char)
                    put(o.hl, "FillColor", teamCol or C.ESPFillColor)
                    put(o.hl, "OutlineColor", C.ESPOutlineColor)
                    put(o.hl, "FillTransparency", C.ESPFillTrans)
                    put(o.hl, "Enabled", C.ESPChams)

                    -- health bar: project the 8 corners of the (invisible or drawn) 3D box to the screen and put
                    -- the bar just left of the leftmost corner, as tall as the box appears on screen
                    local hpShown = false
                    if C.ESPHealth then
                        -- the left edge of the box as the camera sees it: 2 projections instead of all 8 corners
                        local sc = C.ESP3DScale
                        local mid = root.Position + Vector3.new(0, -0.3 * sc, 0) - camRight * (2 * sc)
                        local up = Vector3.new(0, 2.9 * sc, 0)
                        local top, on1 = U.espPoint(mid + up)
                        local bottom, on2 = U.espPoint(mid - up)
                        local minX, minY, maxY = math.min(top.X, bottom.X), math.min(top.Y, bottom.Y), math.max(top.Y, bottom.Y)
                        if on1 and on2 and maxY - minY > 4 then
                            hpShown = true
                            put(o.hpBack, "Position", UDim2.fromOffset(math.floor(minX - 8), math.floor(minY)))
                            put(o.hpBack, "Size", UDim2.fromOffset(4, math.floor(maxY - minY)))
                            -- fill: grows from the bottom, green (or shifting to red when enabled)
                            local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                            put(o.hpFill, "Size", UDim2.new(1, 0, math.floor(frac * 100) / 100, 0))
                            put(o.hpFill, "BackgroundColor3", C.ESPHealthShift
                                and Color3.fromRGB(230, 60, 60):Lerp(C.ESPHealthColor, math.floor(frac * 20) / 20) or C.ESPHealthColor)
                        end
                    end
                    put(o.hpBack, "Visible", hpShown)

                    -- 3D box
                    if C.ESP3D then
                        if o.edgeScale ~= C.ESP3DScale or o.edgeThick ~= C.ESP3DThick then
                            o.edgeScale, o.edgeThick = C.ESP3DScale, C.ESP3DThick
                            layoutEdges(o, C.ESP3DScale, C.ESP3DThick)
                        end
                        local col3 = teamCol or C.ESP3DColor
                        for _, e in ipairs(o.edges) do
                            put(e, "Adornee", root)
                            put(e, "Color3", col3)
                            put(e, "Visible", true)
                        end
                    else
                        for _, e in ipairs(o.edges) do put(e, "Visible", false) end
                    end

                    local hasHeld = C.ESPHeld and o.heldName ~= nil
                    put(o.info, "Adornee", root)
                    put(o.info, "Enabled", C.ESPName or C.ESPInfo or hasHeld)
                    put(o.nameLabel, "Visible", C.ESPName)
                    put(o.nameLabel, "TextColor3", teamCol or C.ESPTextColor)
                    put(o.subLabel, "Visible", C.ESPInfo)
                    put(o.subLabel, "TextColor3", C.ESPTextColor)
                    put(o.heldLabel, "Visible", hasHeld)
                    put(o.heldLabel, "TextColor3", C.ESPTextColor)

                    if now - o.tick > 0.1 then
                        o.tick = now
                        put(o.nameLabel, "Text", plr.DisplayName)
                        put(o.subLabel, "Text", string.format("%d st  |  %d hp", dist, hum.Health))
                        local tool = char:FindFirstChildOfClass("Tool")
                        o.heldName = tool and tool.Name or nil
                        put(o.heldLabel, "Text", tool and ("[ " .. tool.Name .. " ]") or "")
                    end

                    -- skeleton: project each joint once (many bones share a joint - shoulders/hips/elbows...)
                    -- and reuse it for every bone touching it; the projection table is reused, not rebuilt every frame
                    if C.ESPSkeleton then
                        local joints, bones = U.skelJoints(char, hum)
                        local skelCol = teamCol or C.ESPSkelColor
                        local proj = o.proj or {}
                        o.proj = proj
                        table.clear(proj)
                        for i, line in ipairs(o.bones) do
                            local pair = bones[i]
                            local a, b
                            if pair then
                                for k = 1, 2 do
                                    local name = pair[k]
                                    local cached = proj[name]
                                    if cached == nil then
                                        local p = joints[name]
                                        if p then
                                            local sp, on = U.espPoint(p)
                                            cached = on and sp or false
                                        else
                                            cached = false
                                        end
                                        proj[name] = cached
                                    end
                                    if k == 1 then a = cached else b = cached end
                                end
                            end
                            if a and b then
                                local d = b - a
                                put(line, "Visible", true)
                                put(line, "BackgroundColor3", skelCol)
                                put(line, "Size", UDim2.fromOffset(math.floor(d.Magnitude + 0.5), C.ESPSkelWidth))
                                put(line, "Position", UDim2.fromOffset(math.floor((a.X + b.X) / 2), math.floor((a.Y + b.Y) / 2)))
                                put(line, "Rotation", math.floor(math.deg(math.atan2(d.Y, d.X)) * 2) / 2)
                            else
                                put(line, "Visible", false)
                            end
                        end
                    else
                        for _, line in ipairs(o.bones) do put(line, "Visible", false) end
                    end

                    local tracerShown = false
                    if C.ESPTracers then
                        local sp, on = U.espPoint(root.Position)
                        if on then
                            tracerShown = true
                            local fx, fy = vp.X / 2, vp.Y
                            local dx, dy = sp.X - fx, sp.Y - fy
                            put(o.tracer, "BackgroundColor3", teamCol or C.ESPTracerColor)
                            put(o.tracer, "Size", UDim2.fromOffset(math.floor(math.sqrt(dx * dx + dy * dy) + 0.5), C.ESPTracerWidth))
                            put(o.tracer, "Position", UDim2.fromOffset(math.floor((fx + sp.X) / 2), math.floor((fy + sp.Y) / 2)))
                            put(o.tracer, "Rotation", math.floor(math.deg(math.atan2(dy, dx)) * 2) / 2)
                        end
                    end
                    put(o.tracer, "Visible", tracerShown)
                end
            end
        end
    end
end
if RunService.PreRender then
    connect(RunService.PreRender, drawESP)
else
    connect(RunService.RenderStepped, drawESP)
end

-- view -----------------------------------------------------------------

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

-- Custom FOV: set at RenderPriority.Last (so the rest of the frame sees it) and again right before drawing (see drawESP),
-- because some games put their own field of view back late in the frame
function U.applyFov()
    if C.FovEnabled then
        U.origFov = U.origFov or cam().FieldOfView
        cam().FieldOfView = C.FovValue
    elseif U.origFov then
        cam().FieldOfView = U.origFov
        U.origFov = nil
    end
end
local FULLBRIGHT_AMBIENT = Color3.fromRGB(178, 178, 178)
renderLast(function()
    if C.Fullbright then
        -- written every frame on purpose: the engine skips a write of an unchanged value itself, which measured
        -- ~10x cheaper than reading the value first to compare (a read allocates a new Color3)
        Lighting.Brightness = C.FullbrightLevel
        Lighting.ClockTime = C.FullbrightTime
        Lighting.FogEnd = 1e6
        Lighting.GlobalShadows = false
        Lighting.Ambient = FULLBRIGHT_AMBIENT
        Lighting.OutdoorAmbient = FULLBRIGHT_AMBIENT
    end
    U.applyFov()
end)
onUnload(function()
    if originalLighting then for k, val in pairs(originalLighting) do pcall(function() Lighting[k] = val end) end end
    if U.origFov then cam().FieldOfView = U.origFov end
end)

----------------------------------------------------------------------
-- tab: Visuals (shader-pack style: vivid colours, bloom, sun rays, depth of field, Future lighting, reflections)
-- No colour tint anywhere: the ColorCorrection tint stays white, only saturation / contrast change.
----------------------------------------------------------------------

;(function()   -- own function: the main chunk is out of local registers
local vibeTab = win:Tab("Visuals")
local gradeSec = vibeTab:Section("Shaders")
local lightSec = vibeTab:Section("Lighting", "right")
local timeSec = vibeTab:Section("Time Of Day", "right")

local PRESET_NAMES = { "Natural", "Vivid", "Ultra Vivid", "Extreme", "Hyper", "Cinematic" }
local PRESETS = {
    ["Natural"]     = { sat = 0.15, contrast = 0.10, bloom = 0.30, sun = 0.10, dof = 0 },
    ["Vivid"]       = { sat = 0.45, contrast = 0.20, bloom = 0.50, sun = 0.20, dof = 0 },
    ["Ultra Vivid"] = { sat = 0.80, contrast = 0.30, bloom = 0.80, sun = 0.30, dof = 0 },
    ["Extreme"]     = { sat = 1.30, contrast = 0.40, bloom = 1.00, sun = 0.40, dof = 0 },
    ["Hyper"]       = { sat = 2.00, contrast = 0.50, bloom = 1.40, sun = 0.50, dof = 0 },
    ["Cinematic"]   = { sat = 0.25, contrast = 0.30, bloom = 0.60, sun = 0.20, dof = 0.30 },
}
local function preset() return PRESETS[C.ShLook] or PRESETS.Vivid end

-- vivid colours: our own ColorCorrection / Bloom / SunRays / DepthOfField, removed again when off
local cc, bloom, sun, dof

local function ensureFx()
    if not (cc and cc.Parent) then cc = Instance.new("ColorCorrectionEffect") cc.Name = U.rname() cc.Parent = Lighting end
    if not (bloom and bloom.Parent) then bloom = Instance.new("BloomEffect") bloom.Name = U.rname() bloom.Size = 24 bloom.Threshold = 0.9 bloom.Parent = Lighting end
    if not (sun and sun.Parent) then sun = Instance.new("SunRaysEffect") sun.Name = U.rname() sun.Spread = 0.7 sun.Parent = Lighting end
    if not (dof and dof.Parent) then
        dof = Instance.new("DepthOfFieldEffect") dof.Name = U.rname()
        dof.NearIntensity, dof.FocusDistance, dof.InFocusRadius = 0, 60, 40
        dof.Parent = Lighting
    end
end

local function applyShader()
    ensureFx()
    local k, p = C.ShIntensity / 100, preset()
    cc.TintColor = Color3.new(1, 1, 1)
    cc.Saturation, cc.Contrast, cc.Brightness = p.sat * k, p.contrast * k, 0
    bloom.Intensity = p.bloom * k
    sun.Intensity = p.sun * k
    dof.FarIntensity = p.dof * k
end

local function restoreShader()
    for _, o in ipairs({ cc, bloom, sun, dof }) do if o then pcall(function() o:Destroy() end) end end
    cc, bloom, sun, dof = nil, nil, nil, nil
end

-- lighting engine: Future lighting (hidden property), sun shadows and sky reflections
local techOrig, reflOrig, qualOrig

local function setFuture(v)
    if v then
        if techOrig == nil then
            local ok, cur = pcall(function() return gethiddenproperty(Lighting, "Technology") end)
            if ok then techOrig = cur end
        end
        if not pcall(function() sethiddenproperty(Lighting, "Technology", Enum.Technology.Future) end) then
            notify("Future Lighting", "This executor cannot change the lighting engine", "warn")
        end
    elseif techOrig ~= nil then
        pcall(function() sethiddenproperty(Lighting, "Technology", techOrig) end)
        techOrig = nil
    end
end

local function applyReflect()
    if not reflOrig then
        reflOrig = { GlobalShadows = Lighting.GlobalShadows, EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
            EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale }
        pcall(function() reflOrig.ShadowSoftness = Lighting.ShadowSoftness end)
    end
    pcall(function() Lighting.ShadowSoftness = 0.45 end)
    Lighting.GlobalShadows = true
    Lighting.EnvironmentDiffuseScale = 1
    Lighting.EnvironmentSpecularScale = 1
end

local function restoreReflect()
    if not reflOrig then return end
    for k, v in pairs(reflOrig) do pcall(function() Lighting[k] = v end) end
    reflOrig = nil
end

local function setMaxQuality(v)
    local ok, r = pcall(settings)
    if not (ok and r) then return end
    if v then
        if qualOrig == nil then qualOrig = r.Rendering.QualityLevel end
        pcall(function() r.Rendering.QualityLevel = Enum.QualityLevel.Level21 end)
    elseif qualOrig ~= nil then
        pcall(function() r.Rendering.QualityLevel = qualOrig end)
        qualOrig = nil
    end
end

-- clear air: no haze, no fog (only lowers them, adds no colour)
local airOrig, airFog
local function applyAir()
    if not airFog then airFog = { FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd } airOrig = {} end
    Lighting.FogStart, Lighting.FogEnd = 1e6, 1e6
    for _, a in ipairs(Lighting:GetChildren()) do
        if a:IsA("Atmosphere") then
            if not airOrig[a] then airOrig[a] = { Density = a.Density, Haze = a.Haze } end
            a.Density, a.Haze = math.min(a.Density, 0.2), 0
        end
    end
end
local function restoreAir()
    if not airFog then return end
    for k, v in pairs(airFog) do pcall(function() Lighting[k] = v end) end
    for a, sv in pairs(airOrig) do pcall(function() a.Density, a.Haze = sv.Density, sv.Haze end) end
    airFog, airOrig = nil, nil
end

-- rich light: a brighter, punchier sun
local lightOrig
local function applyLight()
    if not lightOrig then lightOrig = { Brightness = Lighting.Brightness, ExposureCompensation = Lighting.ExposureCompensation } end
    Lighting.Brightness = math.max(lightOrig.Brightness, 3)
    Lighting.ExposureCompensation = lightOrig.ExposureCompensation + 0.25
end
local function restoreLight()
    if not lightOrig then return end
    for k, v in pairs(lightOrig) do pcall(function() Lighting[k] = v end) end
    lightOrig = nil
end

-- pretty water: clearer, reflective, calmer waves
local waterOrig
local WATER_PROPS = { "WaterReflectance", "WaterTransparency", "WaterWaveSize", "WaterWaveSpeed" }
local function setWater(v)
    local t = workspace.Terrain
    if v then
        if not waterOrig then
            waterOrig = {}
            for _, k in ipairs(WATER_PROPS) do waterOrig[k] = t[k] end
        end
        t.WaterReflectance, t.WaterTransparency, t.WaterWaveSize, t.WaterWaveSpeed = 1, 0.85, 0.25, 12
    elseif waterOrig then
        for k, val in pairs(waterOrig) do pcall(function() t[k] = val end) end
        waterOrig = nil
    end
end

-- extra stars in the night sky
local starOrig = setmetatable({}, { __mode = "k" })
local function setStars(v)
    for _, sky in ipairs(Lighting:GetChildren()) do
        if sky:IsA("Sky") then
            if v then
                if starOrig[sky] == nil then starOrig[sky] = sky.StarCount end
                sky.StarCount = 5000
            elseif starOrig[sky] ~= nil then
                sky.StarCount = starOrig[sky]
                starOrig[sky] = nil
            end
        end
    end
end

local timeOrig
local function restoreTime()
    if timeOrig ~= nil then Lighting.ClockTime = timeOrig timeOrig = nil end
end

-- ui ---------------------------------------------------------------------------
toggle(gradeSec, "Vivid Colors", "ShOn", false, function(v)
    if v then applyShader() else restoreShader() end
end)
dropdown(gradeSec, "Look", "ShLook", PRESET_NAMES, "Vivid", function()
    if C.ShOn then applyShader() end
end)
slider(gradeSec, "Intensity", "ShIntensity", 0, 100, 100, { Suffix = "%", OnChange = function()
    if C.ShOn then applyShader() end
end })

toggle(lightSec, "Future Lighting", "ShFuture", false, setFuture)
toggle(lightSec, "Shadows & Reflections", "ShReflect", false, function(v)
    if v then applyReflect() else restoreReflect() end
end)
toggle(lightSec, "Max Graphics", "ShMax", false, setMaxQuality)
toggle(lightSec, "Rich Light", "ShLight", false, function(v)
    if v then applyLight() else restoreLight() end
end)
toggle(lightSec, "Clear Air", "ShAir", false, function(v)
    if v then applyAir() else restoreAir() end
end)
toggle(lightSec, "Pretty Water", "ShWater", false, setWater)
toggle(lightSec, "Extra Stars", "ShStars", false, setStars)

toggle(timeSec, "Lock Time", "ShTime", false, function(v)
    if not v then restoreTime() end
end)
slider(timeSec, "Time Of Day", "ShClock", 0, 24, 14, { Decimals = 1 })

onUnload(function() restoreShader() setFuture(false) restoreReflect() setMaxQuality(false) restoreLight() restoreAir() setWater(false) setStars(false) restoreTime() end)

local slowAt = 0
renderLast(function(dt)
    if not U.Running then return end
    if C.ShTime then
        if timeOrig == nil then timeOrig = Lighting.ClockTime end
        Lighting.ClockTime = C.ShClock
    end
    slowAt += dt
    if slowAt < 0.3 then return end
    slowAt = 0
    -- games reset their lighting now and then; keep our look on
    if C.ShOn then applyShader() end
    if C.ShReflect then applyReflect() end
    if C.ShLight then applyLight() end
    if C.ShAir then applyAir() end
end)
-- weapon skin ---------------------------------------------------------------------------------------------
-- Changes how YOUR weapon looks, only on your own screen (the game decides what others see). It covers the
-- viewmodel - the gun + arms model many shooters put right in front of the camera (Arsenal: Camera.Arms) - and a
-- Tool held by your character. Everything it changes is remembered and put back when it is switched off.
local skinSec = vibeTab:Section("Weapon Skin", "right")
local SKIN_MATERIAL = {
    Neon = Enum.Material.Neon, Glass = Enum.Material.Glass, ForceField = Enum.Material.ForceField,
    Smooth = Enum.Material.SmoothPlastic, Chrome = Enum.Material.Metal,
}
local skin = {
    orig = setmetatable({}, { __mode = "k" }),   -- [instance] = { property = original value }
    parts = {}, models = {}, outlines = {}, scanAt = 0,
}

local function restoreSkin()
    for inst, saved in pairs(skin.orig) do
        pcall(function() for prop, v in pairs(saved) do inst[prop] = v end end)
    end
    table.clear(skin.orig)
    table.clear(skin.parts)
    for _, h in pairs(skin.outlines) do h:Destroy() end
    table.clear(skin.outlines)
    skin.scanAt = 0
end
onUnload(restoreSkin)

-- a changed choice starts from the original look again, so nothing of the previous style is left behind
local function restyle() if C.SkinOn then restoreSkin() end end

toggle(skinSec, "Weapon Skin", "SkinOn", false, function(v) if not v then restoreSkin() end end)
dropdown(skinSec, "Material", "SkinMaterial", { "Original", "Neon", "Glass", "ForceField", "Smooth", "Chrome" }, "Neon", restyle)
dropdown(skinSec, "Color", "SkinColorMode", { "Original", "Solid Color", "Rainbow" }, "Rainbow", restyle)
color(skinSec, "Skin Color", "SkinColor", Color3.fromRGB(255, 32, 48))
slider(skinSec, "Transparency", "SkinTrans", 0, 0.9, 0, { Decimals = 2 })
toggle(skinSec, "Outline", "SkinOutline", false)
toggle(skinSec, "Include Arms", "SkinArms", false, restyle)

local function remember(inst, props)
    if skin.orig[inst] then return end
    local saved = {}
    for _, prop in ipairs(props) do
        local ok, v = pcall(function() return inst[prop] end)
        if ok then saved[prop] = v end
    end
    skin.orig[inst] = saved
end

-- arms, hands, gloves and sleeves of the viewmodel - but not a weapon's "Handle" (it contains "hand")
local function isArm(name)
    name = name:lower()
    if name:find("handle") then return false end
    return name:find("arm") or name:find("hand") or name:find("glove") or name:find("sleeve")
end

-- the viewmodel(s): models right in front of the camera, plus a Tool in your character's hand
local function weaponModels()
    local list = {}
    local c = cam()
    local camPos = c.CFrame.Position
    for _, m in ipairs(c:GetChildren()) do
        if m:IsA("Model") then
            local p = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
            if p and (p.Position - camPos).Magnitude < 15 then table.insert(list, m) end
        end
    end
    local char = lp.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if tool then table.insert(list, tool) end
    return list
end

-- 4x a second: which parts to paint. Textures and SurfaceAppearances would cover a new colour, so while a colour is
-- chosen they are hidden (and restored with everything else).
local function scanSkin()
    local recolor = C.SkinColorMode ~= "Original"
    local parts = {}
    skin.models = weaponModels()
    for _, m in ipairs(skin.models) do
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then
                local saved = skin.orig[d]
                local baseT = saved and saved.Transparency or d.Transparency
                -- invisible helper parts (root, joints, hit boxes) stay invisible
                if baseT < 0.95 and (C.SkinArms or not isArm(d.Name)) then
                    table.insert(parts, d)
                    if recolor then
                        if d:IsA("MeshPart") then
                            remember(d, { "Material", "Color", "Transparency", "Reflectance", "TextureID" })
                            pcall(function() d.TextureID = "" end)
                        end
                        for _, k in ipairs(d:GetChildren()) do
                            if k:IsA("SurfaceAppearance") then
                                remember(k, { "Parent" })
                                k.Parent = nil
                            elseif k:IsA("Decal") or k:IsA("Texture") then
                                remember(k, { "Transparency" })
                                k.Transparency = 1
                            elseif k:IsA("SpecialMesh") then
                                remember(k, { "TextureId" })
                                k.TextureId = ""
                            end
                        end
                    end
                end
            end
        end
    end
    skin.parts = parts
end

renderLast(function()
    if not (C.SkinOn and U.Running) then return end
    local now = os.clock()
    if now - skin.scanAt > 0.25 then
        skin.scanAt = now
        scanSkin()
    end

    local mat = SKIN_MATERIAL[C.SkinMaterial]
    local col = (C.SkinColorMode == "Rainbow" and Color3.fromHSV((now * 0.25) % 1, 0.85, 1))
        or (C.SkinColorMode == "Solid Color" and C.SkinColor) or nil
    for _, p in ipairs(skin.parts) do
        if p.Parent then
            remember(p, { "Material", "Color", "Transparency", "Reflectance" })
            local saved = skin.orig[p]
            if mat then p.Material = mat end
            if col then p.Color = col end
            p.Reflectance = C.SkinMaterial == "Chrome" and 0.6 or saved.Reflectance
            p.Transparency = math.max(saved.Transparency or 0, C.SkinTrans)
        end
    end

    -- outline: a Highlight that only draws the edge, in the skin colour (rainbow included)
    local lineCol = col or C.SkinColor
    local keep = {}
    if C.SkinOutline then
        for _, m in ipairs(skin.models) do
            keep[m] = true
            local h = skin.outlines[m]
            if not (h and h.Parent) then
                h = Instance.new("Highlight")
                h.Name = U.rname()
                h.FillTransparency = 1
                h.DepthMode = Enum.HighlightDepthMode.Occluded
                h.Adornee = m
                h.Parent = m
                skin.outlines[m] = h
            end
            h.OutlineColor = lineCol
        end
    end
    for m, h in pairs(skin.outlines) do
        if not keep[m] then h:Destroy() skin.outlines[m] = nil end
    end
end)
end)()

----------------------------------------------------------------------
-- tab: Movement
----------------------------------------------------------------------

local moveTab = win:Tab("Movement")
local move = moveTab:Section("Speed & Jump")
local fly = moveTab:Section("Flight & Collision", "right")

-- Looked up ONCE per frame instead of once per feature per frame (every Movement/Defense/Fling/FE/Misc
-- feature that touches our own character calls this, same idea as U.Others() for other players).
local meHum, meRoot, meChar, meFrame, meTime = nil, nil, nil, -1, 0
local function myHumanoid()
    local now = os.clock()
    if meFrame == U.Frame and now - meTime < 0.1 then return meHum, meRoot, meChar end
    local c = lp.Character
    meHum, meRoot, meChar = c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart"), c
    meFrame, meTime = U.Frame, now
    return meHum, meRoot, meChar
end

local orig = {}
-- Speed and Jump do NOT touch WalkSpeed / JumpPower (those properties replicate, so a game can read the changed value):
-- the extra speed is added by moving the character (see CFrame Speed further down), the jump by a velocity kick.
toggle(move, "Speed", "SpeedEnabled", false)
slider(move, "Walk Speed", "SpeedValue", 16, 300, 60, { Suffix = "" })

toggle(move, "Jump Power", "JumpEnabled", false)
slider(move, "Jump Value", "JumpValue", 20, 300, 80)
toggle(move, "Infinite Jump", "InfJump", false)
connect(UserInputService.JumpRequest, function()
    if not C.InfJump then return end
    local hum = myHumanoid()
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)
connect(UserInputService.JumpRequest, function()
    if not (C.JumpEnabled and U.Running) then return end
    RunService.Heartbeat:Wait()   -- after the humanoid has given its own normal jump
    local hum, root = myHumanoid()
    if not (hum and root) then return end
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
        local v = root.AssemblyLinearVelocity
        if v.Y < C.JumpValue then root.AssemblyLinearVelocity = Vector3.new(v.X, C.JumpValue, v.Z) end
    end
end)

-- Anti Stun: the routine itself is at the bottom of this tab (shared with Defense > Anti Ragdoll)
toggle(move, "Anti Stun", "AntiStun", false, function(v)
    local hum = myHumanoid()
    if hum and U.StunStates then U.StunStates(hum, v) end
end)

-- fly ------------------------------------------------------------------

-- Flying is done by setting the root's velocity every frame (no BodyVelocity / BodyGyro objects inside the character,
-- which is the first thing an anti-fly check looks for). Gravity is cancelled by adding half a frame of it back.
local flyState = { vel = Vector3.zero }
local function stopFly()
    flyState.vel = Vector3.zero
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
        -- frame-rate independent glide: 0% = instant, 95% = very floaty
        want = flyState.vel:Lerp(want, 1 - (C.FlySmooth / 100) ^ (math.min(dt, 0.1) * 60))
    end
    flyState.vel = want
    root.AssemblyLinearVelocity = want + Vector3.new(0, workspace.Gravity * math.min(dt, 0.1) * 0.5, 0)
    root.AssemblyAngularVelocity = Vector3.zero
    local flat = Vector3.new(look.LookVector.X, 0, look.LookVector.Z)
    if flat.Magnitude > 0.01 then root.CFrame = CFrame.lookAt(root.Position, root.Position + flat) end
end)
onUnload(stopFly)

-- noclip -----------------------------------------------------------------

local noclipOriginal = setmetatable({}, { __mode = "k" })   -- weak: parts of old characters are forgotten
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
    for _, part in ipairs(U.CharParts(char)) do
        if part.CanCollide then
            if noclipOriginal[part] == nil then noclipOriginal[part] = true end
            part.CanCollide = false
        end
    end
end
connect(RunService.Stepped, applyNoclip)

-- anti stun + anti ragdoll ------------------------------------------------------
-- ONE routine for two switches, so they never run twice or undo each other:
--   Movement > Anti Stun      always: every down / ragdoll / stun state and every stun flag, whatever caused it
--   Defense  > Anti Ragdoll   only while the game has flagged us. The Strongest Battlegrounds uses Accessory
--                             instances: "Ragdoll" / "RagdollSim" = ragdolled, "Freeze" = hit stun (that one only
--                             with Cancel Hit Stun). Other games use similar names or attributes, also checked.
-- Nothing of the game is deleted; the server may still think we are stunned, so moves it checks itself can stay blocked.
do
local STUN_FLAGS = { "Ragdoll", "RagdollSim", "Freeze", "Stun", "Stunned", "Knocked", "Downed", "NoMove", "NoMovement" }
local DOWN_STATES = {
    [Enum.HumanoidStateType.Ragdoll] = true, [Enum.HumanoidStateType.FallingDown] = true,
    [Enum.HumanoidStateType.Physics] = true, [Enum.HumanoidStateType.PlatformStanding] = true,
}
local good = { speed = 16, jump = 50, height = 7.2 }   -- our last normal values, put back while stunned
local st = { scanAt = 0, controlsAt = 0 }

-- the humanoid refuses to ragdoll / fall down at all; a new humanoid (respawn) needs it again
function U.StunStates(hum, off)
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not off)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not off)
    end)
end

local function stunFlag(char, hum)
    for _, n in ipairs(STUN_FLAGS) do
        if char:FindFirstChild(n) or char:GetAttribute(n) or hum:GetAttribute(n) then return n end
    end
end

renderLast(function()
    if not U.Running then return end
    local hum, root, char = myHumanoid()
    if not (hum and root) then return end

    if st.hum ~= hum then
        st.hum = hum
        if C.AntiStun then U.StunStates(hum, true) end
    end

    local flag = (C.AntiStun or C.AntiRagdoll) and stunFlag(char, hum)
    if not flag then
        if hum.WalkSpeed >= 4 then good.speed = hum.WalkSpeed end
        if hum.JumpPower >= 5 then good.jump = hum.JumpPower end
        if hum.JumpHeight >= 1 then good.height = hum.JumpHeight end
    end
    local act = C.AntiStun or (C.AntiRagdoll and flag and (flag ~= "Freeze" or C.AntiRagdollStun))
    if not act then return end

    -- our own features that lie down / float on purpose
    local ours = C.FlyEnabled or C.SuperFly or C.LayDown
    if not ours then
        if hum.PlatformStand then hum.PlatformStand = false end
        if DOWN_STATES[hum:GetState()] then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
    end
    if root.Anchored then root.Anchored = false end
    if hum.WalkSpeed < 4 then hum.WalkSpeed = good.speed end
    if hum.UseJumpPower then
        if hum.JumpPower < 5 then hum.JumpPower = good.jump end
    elseif hum.JumpHeight < 1 then
        hum.JumpHeight = good.height
    end

    local now = os.clock()
    -- 4x a second: joints back on, ragdoll sockets off, nothing of us anchored, and (while flagged)
    -- no game mover that pins us to a spot. We create no movers ourselves, so every one is the game's.
    if now - st.scanAt > 0.25 then
        st.scanAt = now
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("Motor6D") then
                if not d.Enabled then d.Enabled = true end
            elseif d:IsA("BallSocketConstraint") then
                if d.Enabled and not ours then d.Enabled = false end
            elseif d:IsA("BasePart") then
                if d.Anchored then d.Anchored = false end
            elseif flag and (d:IsA("AlignPosition") or d:IsA("AlignOrientation")) then
                if d.Enabled then d.Enabled = false end
            elseif flag and d:IsA("BodyPosition") then
                d.MaxForce = Vector3.zero
            elseif flag and d:IsA("BodyGyro") then
                d.MaxTorque = Vector3.zero
            end
        end
    end
    -- some games switch the movement controls off during a stun: switch them back on (twice a second)
    if flag and now - st.controlsAt > 0.5 then
        st.controlsAt = now
        pcall(function()
            if not U.controls then
                local pm = lp:FindFirstChildOfClass("PlayerScripts") and lp.PlayerScripts:FindFirstChild("PlayerModule")
                U.controls = pm and require(pm):GetControls()
            end
            if U.controls then U.controls:Enable() end
        end)
    end
end)
end   -- anti stun
----------------------------------------------------------------------
-- tab: Defense (anti fling / anti void / anti aim)
----------------------------------------------------------------------

local defTab = win:Tab("Defense")
local aflSec = defTab:Section("Anti Fling")
local aaSec = defTab:Section("Anti Aim")
local avSec = defTab:Section("Anti Void", "right")
local dsSec = defTab:Section("Desync", "right")
local arSec = defTab:Section("Anti Ragdoll")

-- anti fling ------------------------------------------------------------
-- 1) other players' bodies stop colliding with ours, so nothing can physically shove us
-- 2) if our own velocity spikes past what we could produce ourselves, cancel it and step
--    back to where we were a moment ago

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

    -- what we could legitimately be doing ourselves
    local allowed = C.AntiFlingSpeed
    if C.SpeedEnabled then allowed = math.max(allowed, C.SpeedValue * 1.6) end
    if C.FlyEnabled then allowed = math.max(allowed, C.FlySpeed * 1.6) end

    -- falling fast is normal, so only sideways speed and upward speed count
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

-- anti ragdoll ------------------------------------------------------------
-- The Strongest Battlegrounds flags its states with Accessory instances on the character:
-- "Ragdoll" / "RagdollSim" = ragdolled (server sets PlatformStand + FallingDown), "Freeze" = hit
-- stun (WalkSpeed and JumpPower forced to 0). We own our own physics, so while a flag is present we
-- refuse the state changes every frame. Nothing is deleted, so the game's own scripts keep working;
-- the server still believes we are ragdolled, so moves it validates itself may still be blocked.

toggle(arSec, "Anti Ragdoll", "AntiRagdoll", false)
toggle(arSec, "Cancel Hit Stun", "AntiRagdollStun", false)

-- the routine is shared with Movement > Anti Stun: see "anti stun + anti ragdoll" at the bottom of the Movement tab

-- anti void -------------------------------------------------------------
-- remembers the last solid ground you stood on; if you drop under the rescue line
-- (a margin above the map's FallenPartsDestroyHeight) you are put back there

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

-- anti aim + desync ----------------------------------------------------------------
-- Other players see where the server says we are. Right after physics each frame we shift our
-- root by an offset, and at the very start of the next render frame we take exactly that shift
-- back out - so the network snapshot is off while your own screen never shows it.
--   Anti Aim = a random jitter / spin every frame (nothing to lock onto)
--   Desync   = a steady offset: they see you beside, behind or above where you really are, a
--              step behind your movement (Lag), or circling your real position (Orbit)
-- Both can be on together; their offsets are combined into one shift that is undone as one.

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

local desyncAnchor      -- "Stay Here": the spot other players keep seeing you at
local lagHistory = {}    -- "Lag": recent real positions with timestamps

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

-- The shift to apply, as a CFrame in the root's own space (+Z is behind the character).
-- Applying it moves the root to where other players should see it.
local function desyncShift(root)
    local mode = C.DesyncMode
    local dir = DESYNC_DIRS[mode]
    if dir then return CFrame.new(dir * C.DesyncDist) end

    if mode == "Stay Here" then
        -- others keep seeing you where the anchor was set while you walk around freely
        if not desyncAnchor then desyncAnchor = root.CFrame end
        -- gone too far: the anchor moves to you, so the ghost never ends up hundreds of studs away
        -- slider at its maximum (300) = infinite: never re-anchor
        if C.DesyncStayRadius < 300 and (root.Position - desyncAnchor.Position).Magnitude > C.DesyncStayRadius then desyncAnchor = root.CFrame end
        return root.CFrame:ToObjectSpace(desyncAnchor)
    end

    if mode == "Lag" then
        -- others see where you were `DesyncLag` seconds ago, read back from a history of your
        -- real positions (independent of how the game moves the character)
        local now = os.clock()
        table.insert(lagHistory, { t = now, pos = root.Position })
        local target = now - C.DesyncLag
        local keep = 1
        for i = 1, #lagHistory do
            if lagHistory[i].t <= target then keep = i else break end
        end
        for _ = 2, keep do table.remove(lagHistory, 1) end   -- drop what is older than the bracket
        local a, b = lagHistory[1], lagHistory[2]
        local goal
        if a.t >= target or not b then
            goal = a.pos                                      -- history not that long yet
        else
            goal = a.pos:Lerp(b.pos, math.clamp((target - a.t) / math.max(b.t - a.t, 1e-4), 0, 1))
        end
        return root.CFrame:ToObjectSpace(CFrame.new(goal) * root.CFrame.Rotation)
    end

    local a = os.clock() * C.DesyncOrbit * 2 * math.pi   -- Orbit
    return CFrame.new(Vector3.new(math.cos(a), 0, math.sin(a)) * C.DesyncDist)
end

connect(RunService.Heartbeat, function()
    if not ((C.AntiAim or C.Desync) and U.Running) then return end
    local _, root = myHumanoid()
    if not root then return end
    undoAntiAim()   -- a render step may have been skipped; never stack two shifts

    local total = CFrame.new()
    if C.Desync then
        local ds = desyncShift(root)
        total = total * ds
        U.GhostCF = root.CFrame * ds   -- where other players see the character (for the "copy" below)
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

-- desync copy -------------------------------------------------------------
-- A plain copy of your character (same looks, clothes, accessories) drawn where OTHER players see you (the desynced spot), so
-- you can check it on your own screen. It only exists on your client (parented to the camera) and
-- mirrors your live pose relative to the shifted root, so animations play on it exactly as others
-- see them.
do
local ghost, ghostChar, ghostPairs, ghostCount = nil, nil, {}, 0
toggle(dsSec, "Show Copy", "DesyncGhost", true)

-- The Humanoid and the joints stay: clothes, body colours and CharacterMesh limbs are only applied
-- to a model that still has a Humanoid, without it the copy would be bare grey/coloured blocks.
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

-- asked every frame while the ghost is shown: the cached part list, not a walk over every descendant
local function countParts(char)
    return #U.CharParts(char)
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
    -- a joint that still points at a part OUTSIDE the copy (a cloned weld keeps its original target)
    -- would weld the anchored copy to your real character and freeze you: cut those
    for _, d in ipairs(copy:GetDescendants()) do
        if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
            local a, b = d.Part0, d.Part1
            if (a and not a:IsDescendantOf(copy)) or (b and not b:IsDescendantOf(copy)) then d:Destroy() end
        end
    end
    local cloneHum = copy:FindFirstChildOfClass("Humanoid")
    if cloneHum then
        cloneHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None   -- no name tag / health bar
        cloneHum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        cloneHum.RequiresNeck, cloneHum.BreakJointsOnDeath = false, false
        -- a live Humanoid keeps switching CanCollide back on for torso and limbs, and then the copy
        -- (standing where you were) blocks your real character. Freeze its state machine.
        cloneHum.EvaluateStateMachine = false
    end
    for i = #pairsList, 1, -1 do   -- parts that lived inside removed junk (e.g. a Tool's Handle) are gone
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
            pr.g.CanCollide = false   -- belt and braces: the copy must never touch you
        end
    end
end)
end   -- desync copy block

----------------------------------------------------------------------
-- tab: Player
----------------------------------------------------------------------

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

local renderInventory   -- assigned by the Inventory section below
local playerDD = tp:Dropdown({ Text = "Player", Options = playerNames(), Flag = "SelectedPlayer", NoSave = true,
    Callback = function(v)
        C.SelectedPlayer = v
        if renderInventory then renderInventory() end
    end })
local orbitDD   -- assigned by the Orbit section below
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
        local _, _, r = charOf(target)   -- (multi-return: never use `a and f()` here)
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
    -- Fly goes down with LeftControl (the default Click TP key): clicking while descending must not teleport
    if C.FlyEnabled then return end
    local pos = UserInputService:GetMouseLocation()
    local ray = cam():ViewportPointToRay(pos.X, pos.Y)
    rayParams.FilterDescendantsInstances = { lp.Character }
    local res = workspace:Raycast(ray.Origin, ray.Direction * 2000, rayParams)
    local _, root = myHumanoid()
    if res and root then root.CFrame = CFrame.new(res.Position + Vector3.new(0, 4, 0)) end
end)

-- follow ---------------------------------------------------------------

local follow = playerTab:Section("Follow Player")
local followAutoAt = 0   -- when the Auto Distance glide started, so it always begins at the far end

-- follow and orbit both drive our position, so only one may be on at a time
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

-- Auto Distance glides far -> near -> far continuously: a cosine, so the speed eases to zero
-- at both ends and there is never a jump or a sudden stop.
local function followDistance()
    if not C.FollowAuto then return C.FollowDist end
    local far = math.max(C.FollowAutoFar, C.FollowAutoNear)
    local near = math.min(C.FollowAutoFar, C.FollowAutoNear)
    -- measured from the moment it was switched on: cos(0) = 1, so it starts at the far end
    -- (no jump) and then glides toward the near end and back
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
    -- +Z is behind a character (its LookVector is -Z)
    local pos = base:PointToWorldSpace(Vector3.new(0, C.FollowHeight, followDistance()))
    local toward = Vector3.new(base.Position.X - pos.X, 0, base.Position.Z - pos.Z)
    if C.FollowFace and toward.Magnitude > 0.05 then
        myRoot.CFrame = CFrame.lookAt(pos, pos + toward)
    else
        myRoot.CFrame = CFrame.new(pos) * base.Rotation
    end
    myRoot.AssemblyLinearVelocity = Vector3.zero
end)

-- orbit ------------------------------------------------------------------

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
        -- the character faces the target and the camera stays locked onto them
        myRoot.CFrame = CFrame.lookAt(pos, center)
        local c = cam()
        c.CFrame = CFrame.lookAt(c.CFrame.Position, center)
    else
        myRoot.CFrame = CFrame.new(pos) * myRoot.CFrame.Rotation
    end
    myRoot.AssemblyLinearVelocity = Vector3.zero
end)

-- no animations ----------------------------------------------------------
-- We own our character's Animator, and animation playback replicates from the owner to the server,
-- so stopping our own tracks is what other players see too (a track stopped in the same frame it
-- started never gets sent). The game's own scripts keep playing them, so it is redone every frame.
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
    -- frozen tracks would stay frozen; stop them so the game restarts fresh ones
    local hum = myHumanoid()
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            if track.Speed == 0 then track:Stop(0) end
        end
    end
end)
dropdown(animSec, "Mode", "NoAnimMode", { "Stop All", "Stop Attacks Only", "Freeze Pose" }, "Stop All")
toggle(animSec, "Disable Animate (Stop All)", "NoAnimScript", true)
onUnload(function() setAnimateScript(false) end)

local function suppress(track)
    local mode = C.NoAnimMode
    if mode == "Freeze Pose" then
        if track.Speed ~= 0 then track:AdjustSpeed(0) end
    elseif mode == "Stop Attacks Only" then
        -- Action priorities are what games use for moves; movement / idle / core are left alone
        local pv = track.Priority.Value
        if pv >= Enum.AnimationPriority.Action.Value and pv < Enum.AnimationPriority.Core.Value then track:Stop(0) end
    else
        track:Stop(0)
    end
end

-- A track is stopped the moment it starts (AnimationPlayed), and everything still playing is swept at
-- the start of the frame, after the game's own render code, after physics and right before the frame
-- is sent to the server - a single sweep per frame let some tracks slip through for a frame.
local hooked, hookConn
local function sweep()
    if not (C.NoAnim and U.Running) then return end
    local hum = myHumanoid()
    if not hum then return end
    if C.NoAnimMode == "Stop All" and C.NoAnimScript then setAnimateScript(true) end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then return end
    if animator ~= hooked then   -- new character / new Animator: hook it
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
end   -- no animations

-- inventory inspector ----------------------------------------------------
-- Roblox only replicates other players' Backpack in games that choose to; whatever the
-- server does not send simply cannot be shown.

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

    -- games that store an inventory as folders on the player
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

----------------------------------------------------------------------
-- whitelist & blacklist
----------------------------------------------------------------------

-- Whitelist = friends: skipped by aimbot, silent aim, triggerbot and rage, and drawn in their own
-- colour in the ESP. Blacklist = priority targets: aimed at first, drawn in their own colour, and with
-- "Only Target Blacklist" nobody else is targeted at all. A player is on at most one list. The lists are
-- stored by player NAME, so they survive someone leaving and rejoining (and are saved in configs).
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

-- a dropdown only knows the players that are here right now, so entries of absent players are kept
local function takePicks(set, other, picks)
    local present = presentNames()
    for name in pairs(set) do
        if present[name] then set[name] = nil end
    end
    for _, name in ipairs(picks) do
        set[name] = true
        other[name] = nil          -- never on both lists
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

-- Roblox friends never become targets: they are added to the whitelist as they join
local function whitelistFriends()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and not U.White[plr.Name] then
            local ok, isFriend = pcall(lp.IsFriendsWith, lp, plr.UserId)   -- yields, hence the thread
            if ok and isFriend then
                U.White[plr.Name] = true
                U.Black[plr.Name] = nil
            end
        end
    end
    syncSelections()
end
toggle(listSec, "Whitelist Roblox Friends", "AutoWhiteFriends", false, function(v)
    if v then task.spawn(whitelistFriends) end
end)
connect(Players.PlayerAdded, function()
    if C.AutoWhiteFriends then task.delay(1, whitelistFriends) end
end)
end   -- lists

----------------------------------------------------------------------
-- tab: Fling (fling / fling all / void spam)
----------------------------------------------------------------------

-- Touch fling: we stick to the target's root part while spinning at absurd speed, so the physics
-- contact throws them. Velocity is only applied for the physics step and zeroed again on the next
-- render frame, so we never fly off ourselves. One job runs at a time (flingBusy); bumping
-- flingToken cancels it. Whitelisted players are always skipped.
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

-- our own body must not collide while we sit inside the target. The original CanCollide values are
-- remembered and put back afterwards: without that the parts stay non-solid and we fall through the map.
local savedCollide = setmetatable({}, { __mode = "k" })

local function restoreBody()
    for part, was in pairs(savedCollide) do
        if part.Parent then part.CanCollide = was end
        savedCollide[part] = nil
    end
end

-- status text above the crosshair: "<JOB> ACTIVE", or "<JOB> LOADING... 2.3s" while a delay runs
local jobName, jobStatus
local jobLabel = Instance.new("TextLabel")
jobLabel.Name = "JobStatus"
jobLabel.AnchorPoint = Vector2.new(0.5, 1)
jobLabel.BackgroundTransparency = 1
jobLabel.Size = UDim2.fromOffset(360, 22)
jobLabel.Font = Enum.Font.GothamBold
jobLabel.TextSize = 16
jobLabel.TextStrokeTransparency = 0.35
jobLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
jobLabel.Visible = false
jobLabel.Parent = overlay
onUnload(function() jobLabel:Destroy() end)

renderLast(function()
    local show = C.JobStatusText and U.Running and flingBusy and jobName ~= nil
    jobLabel.Visible = show
    if not show then return end
    local name = string.upper(jobName)
    if jobStatus then
        local dots = string.rep(".", 1 + math.floor(os.clock() * 3) % 3)
        jobLabel.Text = ("%s LOADING%s%s  %.1fs"):format(name, dots, string.rep(" ", 3 - #dots), math.max(jobStatus - os.clock(), 0))
    else
        jobLabel.Text = name .. " ACTIVE"
    end
    jobLabel.TextColor3 = C.RageStatusRainbow and Color3.fromHSV((os.clock() * 0.4) % 1, 0.9, 1)
        or C.RageStatusColor or Color3.fromRGB(255, 255, 255)
    local center = viewportCenter()
    jobLabel.Position = UDim2.fromOffset(center.X, center.Y - 8)
end)

-- waits `secs` (cancellable by Stop) while showing the loading text
local function loadingWait(secs)
    if secs <= 0 then return end
    local token = flingToken
    local untilAt = os.clock() + secs
    jobStatus = untilAt
    while flingToken == token and U.Running and os.clock() < untilAt do RunService.Heartbeat:Wait() end
    if jobStatus == untilAt then jobStatus = nil end
end

local function goHome(origin)
    -- solid again BEFORE we arrive, and lifted a little so we land on the floor instead of inside it
    restoreBody()
    for _ = 1, 3 do
        local hum, myRoot = myHumanoid()
        if myRoot then
            myRoot.AssemblyLinearVelocity = Vector3.zero
            myRoot.AssemblyAngularVelocity = Vector3.zero
            myRoot.CFrame = origin + Vector3.new(0, 2, 0)
        end
        if hum and cam() then cam().CameraSubject = hum end
        RunService.Heartbeat:Wait()
    end
end

connect(RunService.Stepped, function()
    if not (flingBusy and U.Running) then return end
    local _, _, char = myHumanoid()
    if not char then return end
    for _, part in ipairs(U.CharParts(char)) do
        if part.CanCollide then
            if savedCollide[part] == nil then savedCollide[part] = true end
            part.CanCollide = false
        end
    end
end)
onUnload(restoreBody)

-- One attempt on one player. Returns "done" (launched / in the void), "gone" (dead, respawning or
-- left), "timeout", "me" (we have no character) or "cancel".
-- below this height a player counts as "in the void" (kill line plus the Void Depth slider)
local function voidLine()
    local h = workspace.FallenPartsDestroyHeight
    if h ~= h then h = -500 end   -- some games set it to NaN, which makes every comparison false
    return math.max(h, -1000) + C.VoidDepth
end

-- maxTime / force are only given by Punch Fling (a short burst instead of the full Fling Time)
local function attack(target, void, token, maxTime, force)
    local _, _, root0 = charOf(target)
    if not root0 then return "gone" end
    local startPos, startAt = root0.Position, os.clock()
    local limit = maxTime or (void and C.VoidTime or C.FlingTime)

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

        if C.FlingCamera and not maxTime then cam().CameraSubject = tHum end   -- not for the short Punch burst

        -- lead a moving target a little, and wobble so the contact keeps changing
        local p = force or (void and C.VoidPower or C.FlingPower)
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

-- Runs body(token, origin) as the one active job, then puts us back where we started.
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
    flingBusy, jobName, jobStatus = true, name, nil
    notify(name, "Active", "success", "toggle")
    task.spawn(function()
        local ok, err = pcall(body, token, origin)
        if not ok then notify(name, tostring(err), "error") end
        goHome(origin)
        flingBusy, jobName, jobStatus = false, nil, nil
        restoreBody()
        notify(name, "Stopped", nil, "toggle")
        -- a looping job that ended (error, cancelled, nobody left) must not leave its switch on
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

-- fling ------------------------------------------------------------------

flg:Button({ Text = "Fling Selected Player", Callback = function()
    local target = selectedTarget("Fling")
    if not target then return end
    startJob("Fling", function(token, origin)
        local res = attack(target, false, token)
        notify("Fling", target.DisplayName .. ": " .. RESULT_TEXT[res], res == "done" and "success" or "warn")
    end)
end })

-- everyone we are allowed to hit, ordered by the current options. `mode` is one of
-- Selected / All / Nearest / Blacklist Only (Nearest keeps just the closest one).
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

-- one pass over everybody; returns launched, tried
local function flingPass(token, origin)
    local hit, tried = 0, 0
    for _, plr in ipairs(targetList("All")) do
        if flingToken ~= token or not U.Running then break end
        if charOf(plr) then
            tried += 1
            local res = attack(plr, false, token)
            if res == "done" then hit += 1 end
            if res ~= "cancel" then
                goHome(origin)
                loadingWait(C.FlingGap)
            end
        end
    end
    return hit, tried
end

flg:Button({ Text = "Fling All", Callback = function()
    startJob("Fling All", function(token, origin)
        local hit, tried = flingPass(token, origin)
        notify("Fling All", ("Launched %d of %d players"):format(hit, tried), hit > 0 and "success" or "warn")
    end)
end })

toggle(flg, "Loop Fling All", "FlingLoop", false, function(v)
    if not v then stopFling() return end
    if not startJob("Fling All", function(token, origin)
        while flingToken == token and U.Running do
            flingPass(token, origin)
            loadingWait(C.FlingLoopDelay)
        end
    end) then
        C.FlingLoop = false
        if TOG.FlingLoop then TOG.FlingLoop:Set(false, true) end
    end
end)
slider(flg, "Loop Pause", "FlingLoopDelay", 0.1, 30, 1, { Decimals = 1, Suffix = " s" })
slider(flg, "Next Player Delay", "FlingGap", 0, 30, 0.5, { Decimals = 1, Suffix = " s" })

flg:Button({ Text = "Stop", Callback = function() stopFling() end })

-- void spam ----------------------------------------------------------------
-- keeps sending players under the map. Each round it builds the target list again, so people who
-- respawn or join are picked up automatically; players already in the void are skipped.

local function voidJob(token, origin)
    local kills = 0
    while flingToken == token and U.Running do
        local list = targetList(C.VoidTargets)
        if #list == 0 then
            if C.VoidTargets == "Selected" and not (C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)) then
                notify("Void Spam", "Player left the server", "warn")
                break
            end
            task.wait(0.5)   -- nobody valid right now (dead / respawning): keep watching
        else
            for _, plr in ipairs(list) do
                if flingToken ~= token or not U.Running then break end
                local _, _, root = charOf(plr)
                if root and root.Position.Y >= voidLine() then
                    local res = attack(plr, true, token)
                    if res == "cancel" then return end
                    goHome(origin)   -- never wait around under the map
                    if res == "done" then
                        kills += 1
                        if C.VoidNotify then
                            notify("Void Spam", ("%s sent to the void (%d total)"):format(plr.DisplayName, kills), "success")
                        end
                        loadingWait(C.VoidGap)   -- back home, then wait before the next player
                    end
                end
            end
            loadingWait(C.VoidDelay)
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
slider(vsp, "Next Player Delay", "VoidGap", 0, 30, 1, { Decimals = 1, Suffix = " s" })
slider(vsp, "Delay Between Rounds", "VoidDelay", 0, 30, 0.5, { Decimals = 1, Suffix = " s" })
toggle(vsp, "Show Status Text", "JobStatusText", true)
toggle(vsp, "Notify Each Kill", "VoidNotify", false)

;(function()  -- own function: the fling block is close to Lua's 200-locals limit
-- punch fling ---------------------------------------------------------------
-- A real punch animation (played on your own Animator, so everybody sees it) plus ONE short contact per
-- punch: when the fist lands we snap onto the player in front of us for a few frames with a directional
-- push, then go straight back to where we stood. No spinning, no flying around, and only players inside
-- Reach and in front of you are touched. Whitelisted players are skipped like everywhere else.
local pnch = flingTab:Section("Punch Fling")

-- Roblox's own tool swings (they load everywhere); the game's own animations are added by the scan buttons
-- The Strongest Battlegrounds: the four M1 hits of "Normal Punch" (R6, game animations, seen by everybody; checked)
local IN_TSB = game.PlaceId == 10449761463   -- The Strongest Battlegrounds (also its private servers)
local PUNCH_TSB = "Normal Punch (TSB)"
local PUNCH_TSB_MOVE = "Normal Punch Ability (TSB)"
local TSB_M1 = { 10469493270, 10469630950, 10469639222, 10469643643 }
local tsbIndex, tsbLastAt = 0, 0
local PUNCH_BUILTIN = {
    ["Hand Slam"] = { R15 = 243827693, R6 = 243827693 },   -- Roblox's own slam animation (0.75 s, checked)
    -- what the game plays when you use the Normal Punch move (hotbar slot 4), logged from a real use; 1.17 s
    [PUNCH_TSB_MOVE] = { R15 = 10468665991, R6 = 10468665991 },
    ["Lunge (thrust)"] = { R15 = 522638767, R6 = 129967478 },
    ["Slash (swing)"]  = { R15 = 522635514, R6 = 129967390 },
}
local PUNCH_NONE = "None (no animation)"
local PUNCH_COMBO = "Combo (cycles through all)"
local comboIndex = 0
local PUNCH_WORDS = { "punch", "m1", "attack", "hit", "strike", "combat", "melee", "swing", "slash", "jab", "hook", "fist", "kick", "uppercut" }
local gameAnims = {}   -- dropdown label -> animation id, found in the game

local function punchOptions()
    -- the two TSB animations are game-owned: they only exist in the list (and only work) inside TSB
    local list = {}
    if IN_TSB then
        table.insert(list, PUNCH_TSB_MOVE)
        table.insert(list, PUNCH_TSB)
    end
    for _, name in ipairs({ "Hand Slam", "Lunge (thrust)", "Slash (swing)", PUNCH_COMBO, PUNCH_NONE }) do table.insert(list, name) end
    local extra = {}
    for label in pairs(gameAnims) do table.insert(extra, label) end
    table.sort(extra)
    for _, label in ipairs(extra) do table.insert(list, label) end
    return list
end

local punchDD
local function scanGameAnims(all)
    table.clear(gameAnims)
    local roots = { game:GetService("ReplicatedStorage"), game:GetService("StarterPlayer"), game:GetService("StarterPack"),
        lp:FindFirstChildOfClass("Backpack"), lp.Character }
    local seen, count = {}, 0
    for _, root in ipairs(roots) do
        for _, d in ipairs(root:GetDescendants()) do
            local id = d:IsA("Animation") and d.AnimationId:match("%d+")
            if id and not seen[id] and count < 80 then
                local lname = d.Name:lower() .. " " .. (d.Parent and d.Parent.Name:lower() or "")
                local match = all
                if not match then
                    for _, word in ipairs(PUNCH_WORDS) do
                        if lname:find(word, 1, true) then match = true break end
                    end
                end
                if match then
                    seen[id] = true
                    count += 1
                    gameAnims[("Game: %s (%s)"):format(d.Name, d.Parent and d.Parent.Name or "?")] = id
                end
            end
        end
    end
    if punchDD then punchDD:SetOptions(punchOptions()) end
    notify("Punch Fling", ("Found %d game animations"):format(count), count > 0 and "success" or "warn", "misc")
end

local function playPunchAnim()
    local pick = C.PunchAnim
    if pick == PUNCH_NONE then return end
    if not IN_TSB and (pick == PUNCH_TSB or pick == PUNCH_TSB_MOVE) then pick = "Hand Slam" end   -- e.g. from a config saved in TSB
    if pick == PUNCH_COMBO then   -- every punch plays the next animation of the list
        local pool = {}
        for _, option in ipairs(punchOptions()) do
            if option ~= PUNCH_NONE and option ~= PUNCH_COMBO then table.insert(pool, option) end
        end
        comboIndex = comboIndex % #pool + 1
        pick = pool[comboIndex]
    end
    local hum = myHumanoid()
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not animator then return end
    local id = gameAnims[pick]
    local speed = pick == PUNCH_TSB_MOVE and 1 or 1.3
    if pick == PUNCH_TSB then   -- the four M1 hits of Normal Punch in a row; the chain restarts after a pause
        if os.clock() - tsbLastAt > 1.2 then tsbIndex = 0 end
        tsbIndex = tsbIndex % #TSB_M1 + 1
        tsbLastAt = os.clock()
        id, speed = TSB_M1[tsbIndex], 1
    end
    if not id then
        local set = PUNCH_BUILTIN[pick]
        id = set and set[hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"]
    end
    if not id then return end
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. tostring(id)
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    anim:Destroy()
    if not (ok and track) then return end
    track.Priority = Enum.AnimationPriority.Action4
    track.Looped = false
    track:Play(0.05, 1, speed)
    track.Stopped:Once(function() track:Destroy() end)
end

local function punchTarget()
    local _, myRoot = myHumanoid()
    if not myRoot then return end
    local best, bestDist
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and not isProtected(plr) then
            local _, _, root = charOf(plr)
            if root then
                local off = root.Position - myRoot.Position
                local d = off.Magnitude
                -- in front of us (a very close player counts from any side)
                if d <= C.PunchReach and (d < 3 or myRoot.CFrame.LookVector:Dot(off.Unit) > 0) and (not bestDist or d < bestDist) then
                    best, bestDist = plr, d
                end
            end
        end
    end
    return best
end

-- The "hidden fling" loop, verified on the alt in TSB (it launched them ~490 studs): for one physics step per frame
-- our root gets a velocity spike while we sit inside the target's torso, and it is put back to zero before the
-- next frame is drawn, so nothing flies away from us - but whoever we touch at that moment is thrown. The whole
-- thing lasts at most 0.8 s (it stops the moment they are launched) and then we are back where we stood.
-- Our body must stay solid for the contact, so this deliberately does NOT use the no-collide flingBusy mode.
local function hiddenBurst(target, token, origin)
    local startAt, movel, res = os.clock(), 0.1, "timeout"
    local _, _, t0 = charOf(target)
    if not t0 then return "gone" end
    local startPos = t0.Position
    local function myRootNow() return select(2, myHumanoid()) end
    while os.clock() - startAt < 0.8 and flingToken == token and U.Running do
        local tchar, _, tRoot = charOf(target)
        if not tRoot then res = "gone" break end
        if tRoot.AssemblyLinearVelocity.Magnitude > 250 or (tRoot.Position - startPos).Magnitude > 40 then res = "done" break end

        RunService.Heartbeat:Wait()
        local root = myRootNow()
        local torso = tchar and (tchar:FindFirstChild("Torso") or tchar:FindFirstChild("UpperTorso") or tRoot)
        if not (root and torso) then res = "me" break end
        root.CFrame = CFrame.new(torso.Position)
        root.AssemblyLinearVelocity = Vector3.new(0, C.PunchPower, 0)
        RunService.RenderStepped:Wait()
        root = myRootNow()
        if root then root.AssemblyLinearVelocity = Vector3.zero end
        RunService.Stepped:Wait()
        root = myRootNow()
        if root then root.AssemblyLinearVelocity = Vector3.new(0, movel, 0) end
        movel = -movel
    end
    if flingToken ~= token then res = "cancel" end
    goHome(origin)
    return res
end

local punching = false
local function punch(verbose)
    if punching or flingBusy or not U.Running then return end
    local _, myRoot = myHumanoid()
    if not myRoot then return end
    punching = true
    local origin, token = myRoot.CFrame, flingToken
    local target = C.PunchHit and punchTarget()
    if verbose and C.PunchHit and not target then
        notify("Punch Fling", ("Nobody in reach in front of you (Reach %d st)"):format(C.PunchReach), "warn")
    end
    playPunchAnim()
    task.spawn(function()
        task.wait(0.12)   -- the moment the fist lands
        if target and U.Running and flingToken == token then
            local res = hiddenBurst(target, token, origin)
            if verbose then
                notify("Punch Fling", target.DisplayName .. ": " .. (RESULT_TEXT[res] or res), res == "done" and "success" or "warn")
            end
        end
        task.wait(0.25)   -- short pause so holding the key cannot stack punches
        punching = false
    end)
end
onUnload(function() punching = false end)
U.Punch = punch   -- exposed for self-tests

toggle(pnch, "Punch Fling", "PunchOn", false)
keybind(pnch, "Punch Key", "BindPunch", nil, function() if C.PunchOn then punch() end end)
toggle(pnch, "Punch On Left Click", "PunchClick", false)
punchDD = dropdown(pnch, "Animation", "PunchAnim", punchOptions(), IN_TSB and PUNCH_TSB_MOVE or "Hand Slam")
pnch:Button({ Text = "Scan Game Animations", Callback = function() scanGameAnims(false) end })
pnch:Button({ Text = "Scan All Game Animations", Callback = function() scanGameAnims(true) end })
slider(pnch, "Reach", "PunchReach", 3, 25, 8, { Suffix = " st" })
slider(pnch, "Push Power", "PunchPower", 1000, 1000000, 10000)
toggle(pnch, "Fling On Hit", "PunchHit", true)
pnch:Button({ Text = "Punch Now (test)", Callback = function() punch(true) end })

connect(UserInputService.InputBegan, function(input, processed)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if processed or not (C.PunchOn and C.PunchClick and U.Running) or typing() or cursorOverMenu() then return end
    punch()
end)

end)()  -- punch fling

-- tuning -----------------------------------------------------------------

slider(flgTune, "Fling Power", "FlingPower", 10000, 1000000, 100000)
slider(flgTune, "Fling Time Per Player", "FlingTime", 1, 15, 5, { Decimals = 1, Suffix = " s" })
slider(flgTune, "Void Power", "VoidPower", 10000, 1000000, 100000)
slider(flgTune, "Void Time Per Player", "VoidTime", 1, 15, 6, { Decimals = 1, Suffix = " s" })
slider(flgTune, "Void Depth", "VoidDepth", 20, 400, 80, { Suffix = " st" })
slider(flgTune, "Downward Force", "VoidDrop", 0, 2, 1, { Decimals = 1, Suffix = "x" })
slider(flgTune, "Sideways Force", "VoidSide", 0, 2, 1, { Decimals = 1, Suffix = "x" })
toggle(flgTune, "Camera Follows Target", "FlingCamera", true)
toggle(flgTune, "Skip Teammates", "FlingSkipTeam", false)
end   -- fling

----------------------------------------------------------------------
-- tab: Avatar (become a copy of another player)
----------------------------------------------------------------------

-- Copies what a player WEARS (accessories, shirt, pants, graphic tee, body colours, character
-- meshes, face, head mesh, limb colours) onto your own character. It only changes your own client:
-- other players keep seeing your real avatar. The source can be someone in the server (their live
-- look, whatever the game gave them) or any Roblox user by name / id (their catalog avatar, built
-- with CreateHumanoidModelFromDescription). Your own look is saved first so "Restore" is exact.
do
local avatarTab = win:Tab("Avatar")
local avPlayer = avatarTab:Section("Copy Player")
local avUser = avatarTab:Section("Copy By Username", "right")

local APPEAR = { Accessory = true, Shirt = true, Pants = true, ShirtGraphic = true, BodyColors = true, CharacterMesh = true }
local JUNK_CLASSES = { "Script", "LocalScript", "ModuleScript", "Sound", "ParticleEmitter", "BillboardGui", "SurfaceGui" }

-- Every joint / constraint inside a clone is removed. A cloned Weld keeps pointing at the ORIGINAL
-- part (e.g. the other player's Head), which welds your character to theirs: you cannot move and
-- you get dragged around whenever they walk. Accessories are re-welded by hand (attachAccessory).
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

-- everything that makes a character look like itself, as unparented clones. Games hide things:
-- The Strongest Battlegrounds keeps hair and glasses inside a hidden FakeHead part, so the whole
-- character is searched, not just its direct children.
local function takeSnapshot(char)
    local snap = { items = {}, decor = {}, colors = {} }
    for _, d in ipairs(char:GetDescendants()) do
        if APPEAR[d.ClassName] and not insideAccessory(d, char) then
            local c = safeClone(d)
            if c then table.insert(snap.items, { inst = c, host = pathOf(d, char) }) end
        elseif DECOR[d.ClassName] and d.Parent:IsA("BasePart") and not insideAccessory(d, char) then
            local c = safeClone(d)
            if c then table.insert(snap.decor, { path = pathOf(d, char), inst = c }) end   -- path = the part that carries it
        elseif d:IsA("BasePart") and not insideAccessory(d, char) then
            snap.colors[(pathOf(d, char) ~= "" and (pathOf(d, char) .. "/") or "") .. d.Name] = d.Color
        end
    end
    return snap
end

-- Humanoid:AddAccessory does not weld anything on the client, so the handle is welded by hand to the
-- attachment with the same name (on the part it sat on, else on the head, else anywhere on the character)
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
    -- collect first, destroy after: Destroy() also un-parents every descendant, which would break the walk
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
        n.Parent = (host and host:IsA("BasePart")) and host or char   -- same spot it had on the source
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

local mine       -- snapshot of your own look, taken right before the first copy
local worn       -- snapshot of the look you are currently wearing (nil = your own)
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

-- keep the copied look after a respawn (the server hands you a fresh character each time)
connect(lp.CharacterAdded, function(char)
    local keep, snap, label = C.AvatarKeep, worn, wornName
    mine = nil
    if not (keep and snap) then worn, wornName = nil, nil return end
    task.spawn(function()
        char:WaitForChild("Humanoid", 10)
        task.wait(2)                          -- let the game finish dressing the new character
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
end   -- avatar tab

----------------------------------------------------------------------
-- tab: FE (spin, headsit, FE animations, superman fly, custom skybox; telekinesis is added to it further down)
----------------------------------------------------------------------

-- FE = everything here moves / animates YOUR OWN character, which the server replicates, so other
-- players see it: spin (root CFrame), headsit (Humanoid.Sit + root CFrame), emotes and poses
-- (animation tracks on your own Animator). The skybox only exists on your own screen.
;(function()
local funTab = win:Tab("FE")
U.FeTab = funTab   -- telekinesis (further down) puts its section on this tab too
local spinSec = funTab:Section("Spin")
local sitSec = funTab:Section("Headsit", "right")
local animSec = funTab:Section("Animations")
local poseSec = funTab:Section("Poses", "right")
local skySec = funTab:Section("Custom Skybox")
local skyLook = funTab:Section("Sky Look", "right")

-- spin ------------------------------------------------------------------
local spinAuto
local function spinRestore()
    local hum = myHumanoid()
    if hum and spinAuto ~= nil then hum.AutoRotate = spinAuto end
    spinAuto = nil
end

toggle(spinSec, "Spin", "SpinOn", false, function(v) if not v then spinRestore() end end)
slider(spinSec, "Spin Speed", "SpinSpeed", 30, 3600, 720, { Suffix = "°/s" })
dropdown(spinSec, "Axis", "SpinAxis", { "Normal", "Flip (front)", "Roll (side)" }, "Normal")
dropdown(spinSec, "Direction", "SpinDir", { "Left", "Right" }, "Left")

connect(RunService.Heartbeat, function(dt)
    if not (C.SpinOn and U.Running) then return end
    local hum, root = myHumanoid()
    if not (hum and root) then return end
    if spinAuto == nil then spinAuto = hum.AutoRotate end
    hum.AutoRotate = false   -- otherwise the humanoid turns us back towards the walk direction
    local a = math.rad(C.SpinSpeed * dt) * (C.SpinDir == "Left" and 1 or -1)
    local rot = C.SpinAxis == "Flip (front)" and CFrame.Angles(a, 0, 0)
        or C.SpinAxis == "Roll (side)" and CFrame.Angles(0, 0, a)
        or CFrame.Angles(0, a, 0)
    root.CFrame = root.CFrame * rot
end)
onUnload(spinRestore)

-- headsit ---------------------------------------------------------------
-- We sit (Humanoid.Sit = true gives the real sit animation everybody sees) on top of somebody's head:
-- every frame our root is put just above their head and our body is made non-solid so we never push them.
local sitSaved

local function headsitTarget()
    if C.HeadSitTarget == "Selected Player" then
        return C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    end
    local _, myRoot = myHumanoid()
    if not myRoot then return end
    local best, bestDist
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then
            local _, _, root = charOf(plr)
            if root then
                local d = (root.Position - myRoot.Position).Magnitude
                if not bestDist or d < bestDist then best, bestDist = plr, d end
            end
        end
    end
    return best
end

local function headsitStop()
    if sitSaved then
        for part, was in pairs(sitSaved) do
            if part.Parent then part.CanCollide = was end
        end
        sitSaved = nil
    end
    local hum = myHumanoid()
    if hum then hum.Sit = false end
end

toggle(sitSec, "Headsit", "HeadSit", false, function(v)
    if not v then headsitStop() return end
    if not headsitTarget() then
        notify("Headsit", C.HeadSitTarget == "Selected Player" and "Pick a player on the Player tab first" or "Nobody to sit on", "warn")
        C.HeadSit = false
        if TOG.HeadSit then TOG.HeadSit:Set(false, true) end
    end
end)
dropdown(sitSec, "Target", "HeadSitTarget", { "Selected Player", "Nearest Player" }, "Selected Player")
slider(sitSec, "Height", "HeadSitHeight", -2, 4, 0, { Decimals = 1, Suffix = " st" })
toggle(sitSec, "Face Same Way As Target", "HeadSitFace", true)

connect(RunService.Heartbeat, function()
    if not (C.HeadSit and U.Running) then return end
    local hum, root, char = myHumanoid()
    if not (hum and root) then return end
    local plr = headsitTarget()
    local tchar, _, troot = nil, nil, nil
    if plr then tchar, _, troot = charOf(plr) end
    local head = tchar and tchar:FindFirstChild("Head")
    if not head then return end   -- target dead / respawning: we keep waiting

    sitSaved = sitSaved or setmetatable({}, { __mode = "k" })
    for _, part in ipairs(U.CharParts(char)) do
        if part.CanCollide then
            if sitSaved[part] == nil then sitSaved[part] = true end
            part.CanCollide = false
        end
    end
    hum.Sit = true
    local pos = head.Position + Vector3.new(0, head.Size.Y / 2 + 1.2 + C.HeadSitHeight, 0)
    local rot = C.HeadSitFace and troot.CFrame.Rotation or root.CFrame.Rotation
    root.CFrame = CFrame.new(pos) * rot
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end)
onUnload(headsitStop)

-- animations (FE) -------------------------------------------------------
-- Default Roblox emotes (checked: they load). Animation tracks played on your own Animator replicate.
local EMOTE_NAMES = { "Dance 1", "Dance 2", "Dance 3", "Wave", "Point", "Cheer", "Laugh", "Sit" }
local EMOTES = {
    R15 = { ["Dance 1"] = 507771019, ["Dance 2"] = 507776043, ["Dance 3"] = 507777268, Wave = 507770239,
            Point = 507770453, Cheer = 507770677, Laugh = 507770818, Sit = 2506281703 },
    R6  = { ["Dance 1"] = 182435998, ["Dance 2"] = 182436842, ["Dance 3"] = 182436935, Wave = 128777973,
            Point = 128853357, Cheer = 129423030, Laugh = 129423131 },
}

local curTrack
local function stopEmote()
    if curTrack then
        pcall(function() curTrack:Stop(0.2) curTrack:Destroy() end)
        curTrack = nil
    end
end

local function playAnim(id, label)
    local hum = myHumanoid()
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not animator then notify("Animations", "You need a character first", "warn") return end
    stopEmote()
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. tostring(id)
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    anim:Destroy()
    if not (ok and track) then notify("Animations", "Could not load " .. label, "error") return end
    track.Priority = Enum.AnimationPriority.Action4   -- above the walk / idle animations
    track.Looped = C.AnimLoop
    track:Play(0.15, 1, C.AnimFreeze and 0 or C.AnimSpeed)
    curTrack = track
    task.delay(2, function()
        if curTrack == track and track.Length == 0 then
            stopEmote()
            notify("Animations", label .. " does not work in this game", "warn")
        end
    end)
end

local function playEmote()
    local hum = myHumanoid()
    if not hum then notify("Animations", "You need a character first", "warn") return end
    local id = EMOTES[hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"][C.AnimEmote]
    if id then playAnim(id, C.AnimEmote)
    elseif C.AnimEmote == "Sit" then hum.Sit = true
    else notify("Animations", C.AnimEmote .. " does not exist for this rig", "warn") end
end

dropdown(animSec, "Emote", "AnimEmote", EMOTE_NAMES, "Dance 1")
animSec:Button({ Text = "Play Emote", Callback = playEmote })
animSec:Button({ Text = "Stop Animation", Callback = stopEmote })
slider(animSec, "Speed", "AnimSpeed", 0.1, 3, 1, { Decimals = 1, Suffix = "x", OnChange = function(v)
    if curTrack and not C.AnimFreeze then curTrack:AdjustSpeed(v) end
end })
toggle(animSec, "Loop", "AnimLoop", true, function(v) if curTrack then curTrack.Looped = v end end)
toggle(animSec, "Freeze Frame", "AnimFreeze", false, function(v)
    if curTrack then curTrack:AdjustSpeed(v and 0 or C.AnimSpeed) end
end)
toggle(animSec, "Stop When I Move", "AnimStopMove", true)
keybind(animSec, "Emote Key", "BindEmote", nil, playEmote)

local customId = ""
animSec:TextBox({ Text = "Animation ID", Placeholder = "e.g. 507771019", Flag = "AnimCustomId", NoSave = true,
    Callback = function(t) customId = t or "" end })
animSec:Button({ Text = "Play Animation ID", Callback = function()
    local id = tostring(customId):match("%d+")
    if not id then notify("Animations", "Type an animation ID first", "warn") return end
    playAnim(id, "animation " .. id)
end })

connect(RunService.Heartbeat, function()
    if not curTrack then return end
    if not curTrack.IsPlaying then curTrack = nil return end
    if C.AnimStopMove then
        local hum = myHumanoid()
        if hum and hum.MoveDirection.Magnitude > 0.1 then stopEmote() end
    end
end)
onUnload(stopEmote)

-- poses (FE) --------------------------------------------------------------
toggle(poseSec, "Sit Anywhere", "SitOn", false, function(v)
    if not v then local hum = myHumanoid() if hum then hum.Sit = false end end
end)
connect(RunService.Heartbeat, function()
    if not (C.SitOn and U.Running) then return end
    local hum = myHumanoid()
    if hum then hum.Sit = true end
end)

toggle(poseSec, "Lay Down", "LayDown", false, function(v)
    if not v then local hum = myHumanoid() if hum then hum.PlatformStand = false end end
end)
dropdown(poseSec, "Lay Position", "LayFace", { "Face Up", "Face Down" }, "Face Up")
connect(RunService.Heartbeat, function()
    if not (C.LayDown and U.Running) then return end
    local hum, root = myHumanoid()
    if not (hum and root) then return end
    hum.PlatformStand = true
    local look = root.CFrame.LookVector
    local yaw = math.atan2(-look.X, -look.Z)
    local tilt = math.rad(C.LayFace == "Face Up" and 90 or -90)
    root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, 0)
    root.AssemblyAngularVelocity = Vector3.zero
end)
poseSec:Button({ Text = "Stop All Animations", Callback = function()
    stopEmote()
    local hum = myHumanoid()
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do pcall(function() track:Stop(0.1) end) end
    end
end })

-- superman fly (FE) --------------------------------------------------------
-- Flies where the camera looks with real physics (the root's velocity, like the normal Fly), so walls and
-- floors stop you smoothly instead of rubber-banding. Moving = the Superman pose: body turned horizontal (head
-- first, belly down) with the default Roblox Cheer animation raising both arms. Standing still = Hover: upright,
-- floating with Roblox's Levitation idle animation and a slow bob. Everything is your own character (root
-- orientation + animation tracks), which the server replicates, so other players see it.
local superSec = funTab:Section("Superman Fly")
local superTracks = {}          -- "fly" / "hover" -> AnimationTrack
local superMode                 -- which of the two is showing
local superRot = CFrame.new()   -- smoothed orientation
local superVel = Vector3.zero
local superMovedAt = 0
local superSaved
local superReady = false   -- orientation state was taken from the character
-- Which animation gives the best "both arms forward" is MEASURED once per rig (R6 and R15 have different animations):
-- every candidate is scrubbed through its frames and the arm directions are compared with the direction of the head.
local FLY_CANDIDATES = {
    R15 = { 507770677, 507765000, 507765644, 10921294559, 10921293373, 10921137402 },   -- Cheer, Jump, Climb, Superhero Jump / Fall, Levitation Jump
    R6  = { 129423030, 125750702, 180436334, 128777973, 180436148 },                    -- Cheer, Jump, Climb, Wave, Fall
}
local HOVER_IDS = { R15 = 10921132962, R6 = 180436148 }   -- Levitation idle / the R6 fall pose
local poseCache = {}        -- "R6" / "R15" -> { id, hold, loops, score } or false when nothing worked
local poseBusy = false

local function superClearTracks()
    for name, track in pairs(superTracks) do
        pcall(function() track:Stop(0.2) track:Destroy() end)
        superTracks[name] = nil
    end
    superMode = nil
end

local function superStop()
    superClearTracks()
    superVel = Vector3.zero
    superReady = false
    if superSaved then
        for part, was in pairs(superSaved) do
            if part.Parent then part.CanCollide = was end
        end
        superSaved = nil
    end
    local hum, root = myHumanoid()
    if hum then hum.PlatformStand = false end
    if root then   -- stand up again, facing where the head was pointing
        local up = root.CFrame.UpVector
        local flat = Vector3.new(up.X, 0, up.Z)
        if flat.Magnitude < 0.1 then flat = Vector3.new(cam().CFrame.LookVector.X, 0, cam().CFrame.LookVector.Z) end
        if flat.Magnitude > 0.01 then root.CFrame = CFrame.lookAt(root.Position, root.Position + flat) end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

-- how far both arms point along the body's head direction (1 = straight up over the head), whatever way the body is turned
local function armAlignment(char)
    local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    local l = char:FindFirstChild("LeftUpperArm") or char:FindFirstChild("Left Arm")
    local r = char:FindFirstChild("RightUpperArm") or char:FindFirstChild("Right Arm")
    if not (torso and l and r) then return end
    local up = torso.CFrame.UpVector
    return math.min((-l.CFrame.UpVector):Dot(up), (-r.CFrame.UpVector):Dot(up))
end

local function calibratePose(hum)
    local rigKey = hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"
    local animator, char = hum:FindFirstChildOfClass("Animator"), hum.Parent
    if not animator then return end
    poseBusy = true
    notify("Superman Fly", "Finding the best arm pose for your character (a few seconds, once)", nil, "misc")
    local best
    for _, id in ipairs(FLY_CANDIDATES[rigKey]) do
        if not (C.SuperFly and U.Running) then poseBusy = false return end
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://" .. id
        local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
        anim:Destroy()
        if ok and track then
            local t0 = os.clock()
            while track.Length == 0 and os.clock() - t0 < 1.5 do task.wait() end
            local len = track.Length
            if len > 0 then
                track.Priority = Enum.AnimationPriority.Action4
                track.Looped = true
                track:Play(0, 1, 0)
                local bestS, bestT, minS = -2, 0, 2
                for i = 0, 16 do
                    local t = len * i / 16 * 0.999
                    track.TimePosition = t
                    RunService.RenderStepped:Wait()
                    RunService.Heartbeat:Wait()
                    local score = char.Parent and armAlignment(char)
                    if score then
                        if score > bestS then bestS, bestT = score, t end
                        minS = math.min(minS, score)
                    end
                end
                if not best or bestS > best.score then best = { id = id, hold = bestT, score = bestS, loops = minS >= 0.8 } end
            end
            pcall(function() track:Stop(0) track:Destroy() end)
        end
    end
    poseCache[rigKey] = best or false
    poseBusy = false
    if best then
        notify("Superman Fly", ("Arm pose found (%d%% straight)"):format(math.floor(best.score * 100)), "success", "misc")
    else
        notify("Superman Fly", "No arm pose worked for this character - you fly without one", "warn")
    end
end

-- crossfade to the pose for `mode`
local function superSetMode(hum, mode)
    if superMode == mode then
        local t = superTracks[mode]
        if t and t.IsPlaying then return end
    end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then return end
    local rigKey = hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"

    local id, freeze, holdAt
    if mode == "fly" then
        local pose = poseCache[rigKey]
        if pose == nil then
            if not poseBusy then task.spawn(calibratePose, hum) end
            return   -- flying already works, the pose follows in a moment
        end
        if not pose then superMode = mode return end
        id, holdAt = pose.id, pose.hold
        freeze = C.SuperFreeze and not pose.loops   -- a pose that keeps the arms up all the time needs no freezing
    else
        id = HOVER_IDS[rigKey]
    end
    if not id then superMode = mode return end

    local other = superTracks[mode == "fly" and "hover" or "fly"]
    if other then pcall(function() other:Stop(0.25) end) end
    local track = superTracks[mode]
    if not track then
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://" .. id
        local ok, loaded = pcall(function() return animator:LoadAnimation(anim) end)
        anim:Destroy()
        if not (ok and loaded) then return end
        loaded.Priority = Enum.AnimationPriority.Action4
        loaded.Looped = true
        track = loaded
        superTracks[mode] = track
    end
    track:Play(0.25, 1, freeze and 0 or 1)
    if freeze then track.TimePosition = holdAt end   -- stay in the moment where both arms point forward
    superMode = mode
end

U.SuperDebug = function() return { pose = poseCache, mode = superMode, busy = poseBusy } end   -- exposed for self-tests

toggle(superSec, "Superman Fly", "SuperFly", false, function(v)
    if not v then superStop() end
end)
slider(superSec, "Fly Speed", "SuperSpeed", 20, 400, 100)
toggle(superSec, "Hover When Standing Still", "SuperHover", true)
toggle(superSec, "Hold Arms Forward", "SuperFreeze", true, function()
    superClearTracks()   -- rebuilt on the next frame
end)
toggle(superSec, "Pass Through Walls", "SuperNoclip", false, function(v)
    if not v and superSaved then
        for part, was in pairs(superSaved) do
            if part.Parent then part.CanCollide = was end
        end
        superSaved = nil
    end
end)

connect(RunService.Heartbeat, function(dt)
    if not (C.SuperFly and U.Running) then return end
    local hum, root, char = myHumanoid()
    if not (hum and root) then return end
    hum.PlatformStand = true

    if not superReady then
        superReady = true
        superRot = root.CFrame.Rotation
    end

    if C.SuperNoclip then
        superSaved = superSaved or setmetatable({}, { __mode = "k" })
        for _, part in ipairs(U.CharParts(char)) do
            if part.CanCollide then
                if superSaved[part] == nil then superSaved[part] = true end
                part.CanCollide = false
            end
        end
    end

    local look = cam().CFrame
    local dir = Vector3.zero
    if not typing() then
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += look.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= look.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += look.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= look.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then dir += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then dir -= Vector3.yAxis end
    end
    local moving = dir.Magnitude > 0
    if moving then superMovedAt = os.clock() end
    local hovering = C.SuperHover and not moving and os.clock() - superMovedAt > 0.35

    local want = moving and dir.Unit * C.SuperSpeed or Vector3.zero
    if hovering then want = Vector3.new(0, math.sin(os.clock() * 2) * 1.2, 0) end   -- slow bob
    superVel = superVel:Lerp(want, 1 - 0.002 ^ math.min(dt, 0.1))   -- a short glide instead of a hard stop

    local target
    if hovering then
        -- upright, facing where the camera looks
        local flat = Vector3.new(look.LookVector.X, 0, look.LookVector.Z)
        target = CFrame.lookAt(Vector3.zero, flat.Magnitude > 0.01 and flat or Vector3.zAxis * -1)
    else
        -- head along the camera direction, belly towards the ground
        local head = look.LookVector
        local back = Vector3.yAxis - head * head.Y
        if back.Magnitude < 0.08 then back = look.UpVector - head * look.UpVector:Dot(head) end   -- looking straight up / down
        back = back.Unit
        target = CFrame.fromMatrix(Vector3.zero, head:Cross(back), head, back)
    end
    superRot = superRot:Lerp(target, math.clamp(dt * 8, 0, 1))
    -- no BodyVelocity / BodyGyro: velocity and orientation are set on the root itself every frame
    root.AssemblyLinearVelocity = superVel + Vector3.new(0, workspace.Gravity * math.min(dt, 0.1) * 0.5, 0)
    root.AssemblyAngularVelocity = Vector3.zero
    root.CFrame = CFrame.new(root.Position) * superRot

    superSetMode(hum, hovering and "hover" or "fly")
end)
onUnload(superStop)

-- custom skybox -----------------------------------------------------------
-- Either a picture (Roblox image id, a link, or a file in the executor's workspace folder) on all six
-- sides, or a sky we draw ourselves: the pictures are generated as PNG files (gradient + stars) and
-- loaded through getcustomasset. Only your own screen changes.
local SKY_DIR, SKY_SIZE = "TerkanSky", 256

local crcTable = {}
for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
        c = (c % 2 == 1) and bit32.bxor(0xEDB88320, bit32.rshift(c, 1)) or bit32.rshift(c, 1)
    end
    crcTable[i] = c
end
local function crc32(s)
    local c = 0xFFFFFFFF
    for i = 1, #s do c = bit32.bxor(crcTable[bit32.band(bit32.bxor(c, s:byte(i)), 0xFF)], bit32.rshift(c, 8)) end
    return bit32.bxor(c, 0xFFFFFFFF)
end
local function adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end
local function pngChunk(kind, data)
    return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", crc32(kind .. data))
end
-- raw = every row prefixed with filter byte 0; wrapped in "stored" (uncompressed) deflate blocks
local function encodePng(w, h, raw)
    local z, pos, n = { "\120\1" }, 1, #raw
    while pos <= n do
        local len = math.min(65535, n - pos + 1)
        z[#z + 1] = string.pack("<BI2I2", (pos + len > n) and 1 or 0, len, 65535 - len) .. raw:sub(pos, pos + len - 1)
        pos += len
    end
    z[#z + 1] = string.pack(">I4", adler32(raw))
    return "\137PNG\r\n\26\n" .. pngChunk("IHDR", string.pack(">I4I4BBBBB", w, h, 8, 2, 0, 0, 0))
        .. pngChunk("IDAT", table.concat(z)) .. pngChunk("IEND", "")
end

-- zenith / middle / horizon colour and how many stars
local SKY_PRESETS = {
    ["Sunset"]      = { Color3.fromRGB(30, 20, 80),  Color3.fromRGB(210, 80, 95),  Color3.fromRGB(255, 175, 80), 0.0004 },
    ["Neon Night"]  = { Color3.fromRGB(4, 0, 24),    Color3.fromRGB(70, 0, 120),   Color3.fromRGB(255, 0, 170),  0.0020 },
    ["Aurora"]      = { Color3.fromRGB(0, 8, 28),    Color3.fromRGB(0, 100, 90),   Color3.fromRGB(70, 220, 130), 0.0025 },
    ["Blood Moon"]  = { Color3.fromRGB(8, 0, 0),     Color3.fromRGB(90, 0, 10),    Color3.fromRGB(210, 35, 20),  0.0015 },
    ["Deep Space"]  = { Color3.fromRGB(0, 0, 6),     Color3.fromRGB(8, 6, 34),     Color3.fromRGB(28, 12, 60),   0.0060 },
    ["Pastel Dawn"] = { Color3.fromRGB(120, 150, 230), Color3.fromRGB(235, 170, 215), Color3.fromRGB(255, 225, 185), 0 },
    ["Ocean Blue"]  = { Color3.fromRGB(10, 60, 160), Color3.fromRGB(60, 150, 230), Color3.fromRGB(190, 235, 255), 0 },
}
local SKY_PRESET_NAMES = { "Sunset", "Neon Night", "Aurora", "Blood Moon", "Deep Space", "Pastel Dawn", "Ocean Blue" }

local function makeFace(kind, preset, seed)
    local zenith, mid, horizon, density = preset[1], preset[2], preset[3], preset[4]
    local S = SKY_SIZE
    local rnd = Random.new(seed)
    local stars = {}
    for _ = 1, math.floor(S * S * density) do stars[rnd:NextInteger(0, S * S - 1)] = rnd:NextNumber(0.45, 1) end

    local rows = {}
    for y = 0, S - 1 do
        local t = y / (S - 1)          -- 0 = top of the picture, 1 = bottom
        local base
        if kind == "up" then base = zenith
        elseif kind == "down" then base = horizon:Lerp(Color3.new(0, 0, 0), 0.5)
        elseif t < 0.6 then base = zenith:Lerp(mid, t / 0.6)
        else base = mid:Lerp(horizon, (t - 0.6) / 0.4) end
        local fade = kind == "side" and math.clamp(1 - t * 1.4, 0, 1) or 1   -- no stars near the horizon
        local buf = { "\0" }
        for x = 0, S - 1 do
            local col = base
            local b = stars[y * S + x]
            if b then col = base:Lerp(Color3.new(1, 1, 1), b * fade) end
            buf[#buf + 1] = string.char(math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5))
        end
        rows[#rows + 1] = table.concat(buf)
    end
    return encodePng(S, S, table.concat(rows))
end

-- Sky property -> how that face of the cube is drawn
local FACES = {
    { "SkyboxBk", "side", 11 }, { "SkyboxFt", "side", 22 }, { "SkyboxLf", "side", 33 },
    { "SkyboxRt", "side", 44 }, { "SkyboxUp", "up", 55 },   { "SkyboxDn", "down", 66 },
}

local presetAssets = {}
local function presetSky(name)
    if presetAssets[name] then return presetAssets[name] end
    if not isfolder(SKY_DIR) then makefolder(SKY_DIR) end
    local out = {}
    for _, face in ipairs(FACES) do
        local path = ("%s/%s_%s_v1.png"):format(SKY_DIR, name:gsub("%s", ""), face[1])
        if not isfile(path) then
            writefile(path, makeFace(face[2], SKY_PRESETS[name], face[3]))
            task.wait()   -- generating is heavy: one picture per frame, so the game does not freeze
        end
        out[face[1]] = getcustomasset(path)
    end
    presetAssets[name] = out
    return out
end

-- a Roblox image id, a link or a file name  ->  something a Sky can show (all six sides)
local function imageSky(source)
    source = (source or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if source == "" then return nil, "Type an image id, link or file name first" end
    local url = source:match("^https?://.+")
    local id = source:match("^rbxassetid://(%d+)$") or source:match("^(%d+)$")
        or (source:find("roblox.com", 1, true) and source:match("[?&]id=(%d+)"))
    local asset
    if id then
        asset = "rbxassetid://" .. id
    elseif url then
        local ok, res = pcall(request, { Url = url, Method = "GET" })
        if not (ok and res and res.Success and res.Body and #res.Body > 0) then
            return nil, "Could not download that link"
        end
        if not isfolder(SKY_DIR) then makefolder(SKY_DIR) end
        local ext = url:match("%.(%a%a%a%a?)[%?#]?[^/]*$")
        ext = (ext == "jpg" or ext == "jpeg" or ext == "png") and ext or "png"
        local path = SKY_DIR .. "/custom." .. ext
        writefile(path, res.Body)
        asset = getcustomasset(path)
    elseif isfile(source) then
        asset = getcustomasset(source)
    elseif isfile(SKY_DIR .. "/" .. source) then
        asset = getcustomasset(SKY_DIR .. "/" .. source)
    else
        return nil, "Not an image id, link or file in your executor workspace"
    end
    local out = {}
    for _, face in ipairs(FACES) do out[face[1]] = asset end
    return out
end

local skyObj, hiddenSkies = nil, {}
local skyGen = 0
local skyImageText = ""

local function hideGameSkies()
    for _, s in ipairs(Lighting:GetChildren()) do
        if s:IsA("Sky") and s ~= skyObj then
            hiddenSkies[s] = true
            s.Parent = nil
        end
    end
end

local function skyOff()
    skyGen += 1
    if skyObj then skyObj:Destroy() skyObj = nil end
    for s in pairs(hiddenSkies) do
        s.Parent = Lighting
        hiddenSkies[s] = nil
    end
end

local function skyOn()
    skyGen += 1
    local gen = skyGen
    task.spawn(function()
        local textures, err
        local ok, res, msg = pcall(function()
            if C.SkySource == "Image" then return imageSky(skyImageText) end
            return presetSky(C.SkyPreset)
        end)
        if ok then textures, err = res, msg else err = tostring(res) end
        if gen ~= skyGen or not C.SkyOn then return end   -- switched off / changed while loading
        if not textures then
            notify("Skybox", err or "Could not build the sky", "error")
            C.SkyOn = false
            if TOG.SkyOn then TOG.SkyOn:Set(false, true) end
            return
        end
        if not skyObj then
            skyObj = Instance.new("Sky")
            skyObj.Name = U.rname()
        end
        skyObj.StarCount = 0
        for prop, asset in pairs(textures) do skyObj[prop] = asset end
        skyObj.CelestialBodiesShown = C.SkySun
        hideGameSkies()
        skyObj.Parent = Lighting
    end)
end

toggle(skySec, "Custom Skybox", "SkyOn", false, function(v)
    if v then skyOn() else skyOff() end
end)
dropdown(skySec, "Source", "SkySource", { "Preset", "Image" }, "Preset", function()
    if C.SkyOn then skyOn() end
end)
dropdown(skySec, "Preset", "SkyPreset", SKY_PRESET_NAMES, "Neon Night", function()
    if C.SkyOn and C.SkySource == "Preset" then skyOn() end
end)
skySec:TextBox({ Text = "Image (id / link / file)", Placeholder = "rbxassetid://123 or https://... or mysky.png",
    Flag = "SkyImage", NoSave = true, Callback = function(t) skyImageText = t or "" end })
skySec:Button({ Text = "Use This Image", Callback = function()
    C.SkySource = "Image"
    C.SkyOn = true
    if TOG.SkyOn then TOG.SkyOn:Set(true, true) end
    skyOn()
end })

toggle(skyLook, "Show Sun & Moon", "SkySun", true, function(v)
    if skyObj then skyObj.CelestialBodiesShown = v end
end)
slider(skyLook, "Rotate Sky", "SkySpin", 0, 30, 0, { Decimals = 1, Suffix = "°/s" })

local skySlow, skyAngle = 0, 0
renderLast(function(dt)
    if not (C.SkyOn and U.Running and skyObj) then return end
    skyAngle = (skyAngle + C.SkySpin * dt) % 360
    skyObj.SkyboxOrientation = Vector3.new(0, skyAngle, 0)
    skySlow += dt
    if skySlow < 0.5 then return end
    skySlow = 0
    -- games put their own sky back now and then; ours stays the one that shows
    if skyObj.Parent ~= Lighting then skyObj.Parent = Lighting end
    hideGameSkies()
end)
onUnload(skyOff)
end)()

----------------------------------------------------------------------
-- tab: Misc
----------------------------------------------------------------------

local miscTab = win:Tab("Misc")
local perf = miscTab:Section("Performance")
local tools = miscTab:Section("Tools", "right")

local savedShadows
-- The graphics quality level is left alone on purpose: lowering it also shortens how far you can see.
toggle(perf, "FPS Boost", "FpsBoost", false, function(v)
    if v then
        savedShadows = Lighting.GlobalShadows
        Lighting.GlobalShadows = false
        pcall(function() workspace.Terrain.Decoration = false end)
    else
        if savedShadows ~= nil then Lighting.GlobalShadows = savedShadows end
        pcall(function() workspace.Terrain.Decoration = true end)
    end
end)
if hasFn("setfpscap") then
    slider(perf, "FPS Cap (0 = off)", "FpsCap", 0, 360, 0, { OnChange = function(v) pcall(setfpscap, v) end })
end

-- potato mode ------------------------------------------------------------------------------------------------
-- Much further than FPS Boost: every part to SmoothPlastic without its own shadow, textures / decals / PBR skins
-- (SurfaceAppearance) away, particles and post effects off, the cheapest lighting and plain terrain. The graphics
-- quality level is NOT lowered: that also shortens how far you can see. Players are left
-- alone (you must still see who is who), and so is the viewmodel under the camera (the Weapon Skin works there).
-- Every original is remembered and put back when it is switched off. Big maps are done in slices, so switching it on
-- does not freeze a frame; things that appear later are done as they come.
;(function()
local potato = {
    mat = setmetatable({}, { __mode = "k" }),      -- [part] = original Material
    shadow = setmetatable({}, { __mode = "k" }),   -- [part] = true: CastShadow was on
    tex = setmetatable({}, { __mode = "k" }),      -- [decal / texture] = original Transparency
    surf = setmetatable({}, { __mode = "k" }),     -- [SurfaceAppearance] = original parent
    fx = setmetatable({}, { __mode = "k" }),       -- [emitter / post effect] = true: was enabled
    gen = 0,                                       -- bumped on off: a running slice stops
}
local FX_CLASSES = { "ParticleEmitter", "Trail", "Beam", "Smoke", "Fire", "Sparkles",
    "BloomEffect", "BlurEffect", "SunRaysEffect", "ColorCorrectionEffect", "DepthOfFieldEffect" }

-- characters and the viewmodel stay as they are
local function leaveAlone(inst)
    local c = workspace.CurrentCamera
    if c and inst:IsDescendantOf(c) then return true end
    local model = inst:FindFirstAncestorOfClass("Model")
    while model do
        if model:FindFirstChildOfClass("Humanoid") then return true end
        model = model:FindFirstAncestorOfClass("Model")
    end
    return false
end

local function isFx(d)
    for _, cls in ipairs(FX_CLASSES) do
        if d:IsA(cls) then return true end
    end
    return false
end

local function potatoOne(d)
    if not (C.Potato and U.Running and d.Parent) then return end
    if d:IsA("BasePart") then
        if leaveAlone(d) then return end
        if d.Material ~= Enum.Material.SmoothPlastic and potato.mat[d] == nil then
            potato.mat[d] = d.Material
            d.Material = Enum.Material.SmoothPlastic
        end
        if d.CastShadow then potato.shadow[d] = true d.CastShadow = false end
    elseif d:IsA("Decal") or d:IsA("Texture") then
        if leaveAlone(d) then return end
        if potato.tex[d] == nil then potato.tex[d] = d.Transparency end
        d.Transparency = 1
    elseif d:IsA("SurfaceAppearance") then
        if leaveAlone(d) then return end
        potato.surf[d] = d.Parent
        d.Parent = nil
    elseif isFx(d) then
        if d.Enabled then potato.fx[d] = true d.Enabled = false end
    end
end

local lightOrig
local function potatoLighting(on)
    local t = workspace.Terrain
    if on then
        if not lightOrig then
            -- (Terrain.Decoration does not exist in every client: reading it may throw)
            lightOrig = { shadows = Lighting.GlobalShadows, waves = t.WaterWaveSize, refl = t.WaterReflectance }
            pcall(function() lightOrig.deco = t.Decoration end)
            pcall(function() lightOrig.tech = gethiddenproperty(Lighting, "Technology") end)
        end
        Lighting.GlobalShadows = false
        pcall(function() sethiddenproperty(Lighting, "Technology", Enum.Technology.Compatibility) end)
        pcall(function() t.Decoration = false end)
        t.WaterWaveSize, t.WaterReflectance = 0, 0
    elseif lightOrig then
        Lighting.GlobalShadows = lightOrig.shadows
        if lightOrig.deco ~= nil then pcall(function() t.Decoration = lightOrig.deco end) end
        t.WaterWaveSize, t.WaterReflectance = lightOrig.waves, lightOrig.refl
        if lightOrig.tech then pcall(function() sethiddenproperty(Lighting, "Technology", lightOrig.tech) end) end
        lightOrig = nil
    end
end

local function potatoOn()
    potato.gen += 1
    local gen = potato.gen
    potatoLighting(true)
    task.spawn(function()
        for _, root in ipairs({ Lighting, workspace }) do
            for i, d in ipairs(root:GetDescendants()) do
                if potato.gen ~= gen or not C.Potato then return end
                pcall(potatoOne, d)
                if i % 1500 == 0 then task.wait() end   -- big maps: a slice per frame
            end
        end
    end)
end

local function potatoOff()
    potato.gen += 1
    potatoLighting(false)
    for p, m in pairs(potato.mat) do pcall(function() p.Material = m end) end
    for p in pairs(potato.shadow) do pcall(function() p.CastShadow = true end) end
    for d, tr in pairs(potato.tex) do pcall(function() d.Transparency = tr end) end
    for s, parent in pairs(potato.surf) do pcall(function() s.Parent = parent end) end
    for f in pairs(potato.fx) do pcall(function() f.Enabled = true end) end
    for _, t in pairs(potato) do if type(t) == "table" then table.clear(t) end end
end

toggle(perf, "Potato Mode", "Potato", false, function(v) if v then potatoOn() else potatoOff() end end)
-- new things: a moment later, so a character is complete (with its Humanoid) before it is looked at
connect(workspace.DescendantAdded, function(d) if C.Potato then task.defer(pcall, potatoOne, d) end end)
connect(Lighting.DescendantAdded, function(d) if C.Potato then task.defer(pcall, potatoOne, d) end end)
onUnload(potatoOff)
end)()

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

----------------------------------------------------------------------
-- Misc: universal tools (clean visuals, camera, waypoints, stats HUD - work in any game)
----------------------------------------------------------------------

;(function()   -- own function: the main chunk is out of local registers
local uniTab = miscTab   -- these sections live on the Misc tab
local cleanSec = uniTab:Section("Clean Visuals")
local camSec = uniTab:Section("Camera", "right")
local wpSec = uniTab:Section("Waypoints")
local hudSec = uniTab:Section("Stats HUD", "right")

-- clean visuals -------------------------------------------------------------
-- Everything we touch is remembered (weak tables) and put back when the switch goes off.
-- Particles are also made fully transparent, because games often :Emit() them while Enabled is
-- false, which would otherwise still draw.

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
            if n % 3000 == 0 then task.wait() end   -- big maps: do not freeze a frame
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
    -- games switch their own effects back on; keep them off
    if C.CleanEffects then applyEffects() end
    if C.CleanFog then applyFog() end
    if C.CleanParticles then
        for inst in pairs(vfxOrig) do
            if inst.Parent and inst.Enabled then inst.Enabled = false end
        end
    end
end)

-- freecam ---------------------------------------------------------------------
-- The camera detaches from your character and flies freely. Movement keys are swallowed so the
-- character stays put; hold right mouse to look around.

local ContextActionService = game:GetService("ContextActionService")
local FC_KEYS = {
    Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.E, Enum.KeyCode.Q,
    Enum.KeyCode.Space, Enum.KeyCode.LeftControl, Enum.KeyCode.LeftShift,
}
local fc = { pos = Vector3.zero, yaw = 0, pitch = 0, saved = nil }

local function fcStop()
    ContextActionService:UnbindAction(U.FreecamAction)
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
    ContextActionService:BindActionAtPriority(U.FreecamAction, function() return Enum.ContextActionResult.Sink end,
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

-- unlimited zoom -----------------------------------------------------------------

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

-- waypoints (saved per game when the executor can write files) ------------------------------

local WP_FILE = "TerkanWaypoints_" .. tostring(game.PlaceId) .. ".json"
local waypoints = {}   -- name -> the 12 components of a CFrame
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

-- stats HUD ------------------------------------------------------------------------

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
    hudGui.Name = U.rname()
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
end)()   -- universal

----------------------------------------------------------------------
-- Misc: CFrame movement, telekinesis, chat spy
----------------------------------------------------------------------

;(function()   -- own function: the main chunk is out of local registers
local cfSec = moveTab:Section("CFrame Speed")   -- these two live on the Movement tab, the rest of this block on Misc
local cfFlySec = moveTab:Section("CFrame Fly & Dash", "right")

local function keyDown(key)
    return not UserInputService:GetFocusedTextBox() and UserInputService:IsKeyDown(key)
end

-- CFrame movement -----------------------------------------------------------------------------
-- Moves the character by editing its CFrame instead of WalkSpeed / velocity, so games that watch
-- WalkSpeed see nothing unusual. Every move is checked against walls first (Stop At Walls) because a
-- CFrame step, unlike physics, would otherwise pass straight through thin geometry.

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
local doDash   -- defined below, once the dash state exists; the key calls it through this upvalue
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
        root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)   -- do not fall while dashing
    end

    if C.CfFly then
        -- our own authoritative position: physics would otherwise sink us a little every frame
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

    local plainSpeed = (C.SpeedEnabled and not C.CfSpeed) and math.max(C.SpeedValue - 16, 0) or 0   -- the Movement tab's Speed
    if C.CfSpeed or plainSpeed > 0 then
        local held = plainSpeed > 0 or not C.CfSpeedHold or (BIND.CfSpeedKey and BIND.CfSpeedKey:IsDown())
        local dir = hum.MoveDirection
        if not held or (C.CfGroundOnly and hum.FloorMaterial == Enum.Material.Air) then dir = Vector3.zero end
        local speed = plainSpeed > 0 and plainSpeed
            or C.CfSpeedValue * ((BIND.CfSprintKey and BIND.CfSprintKey:IsDown()) and C.CfSprint or 1)
        walkVel = smooth(walkVel, dir * speed, dt)
        if walkVel.Magnitude > 0.05 then
            local move = walkVel * dt
            if not blocked(root, walkVel, move.Magnitude) then root.CFrame += move end
        end
    else
        walkVel = Vector3.zero
    end
end)

-- telekinesis --------------------------------------------------------------------------------
-- Every loose (unanchored) part within Range gets pulled to you and floats around you in a pattern.
-- Roblox lets the client closest to a loose part simulate it, and a part you simulate can be moved
-- freely - the server and other players then see it move. Turning the switch off gives every part back
-- (collision restored, physics radius reset). Anchored parts and characters can never be grabbed.

do
local TK_MAX, TK_SIZE, TK_RESCAN, INF_RANGE, CYCLE_TIME = 250, 400, 0.75, 1600, 8
local TAU, GOLDEN = math.pi * 2, math.pi * (3 - math.sqrt(5))
local SHAPES = { "Ring", "Tornado", "Sphere", "Infinity", "Galaxy", "DNA Helix", "Wings", "Cycle" }
local CYCLE = { "Infinity", "Ring", "Galaxy", "Sphere", "Tornado", "DNA Helix", "Wings" }

local tkSec = (U.FeTab or miscTab):Section("Telekinesis", "right")   -- lives on the FE tab (others see the parts move)

local parts, partSet, origCollide = {}, {}, {}   -- assembly roots we hold, lookup, and their old CanCollide
local claimOrig, scanAt, scanCount, fireUntil = nil, 0, 0, 0

-- widen the physics radius so far-away parts are simulated by us; restore the old values afterwards
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

-- only parts we network-own answer to our velocity, and only those are seen moving by other players
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

-- the free-moving assembly root a part belongs to, or nil if it is anchored / belongs to a character
local function grabbableRoot(part)
    local root = part.AssemblyRootPart
    if not root or root.Anchored or root.Size.Magnitude > TK_SIZE then return nil end
    if root:IsDescendantOf(cam()) then return nil end
    local model = root:FindFirstAncestorOfClass("Model")
    while model do   -- never anything that belongs to a player or NPC
        if model:FindFirstChildOfClass("Humanoid") then return nil end
        model = model:FindFirstAncestorOfClass("Model")
    end
    return root
end

local function scan(root)
    local range = C.TkRange >= INF_RANGE and math.huge or C.TkRange
    local pos = root.Position

    for i = #parts, 1, -1 do   -- forget parts that were destroyed or got anchored (Range only limits new pickups)
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
    else   -- huge ranges: spatial queries are unreliable out there, so walk the whole workspace
        for _, p in ipairs(workspace:GetDescendants()) do
            if p:IsA("BasePart") and not p.Anchored and (range == math.huge or (p.Position - pos).Magnitude <= range) then
                consider(p)
            end
        end
    end
    table.sort(found, function(a, b) return a.dist < b.dist end)

    for _, f in ipairs(found) do
        if #parts >= TK_MAX then   -- full: make room for a part we own by dropping one we don't
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
    if scanCount == 2 then   -- one report per activation, once ownership had a moment to settle
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

-- Where part i of n floats, relative to the centre point above you. right / flat are horizontal camera axes.
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
    elseif shape == "Infinity" then   -- lemniscate, standing upright in front of you, facing the camera
        local a = u * TAU + t * 0.9
        local s = math.sin(a)
        local den = 1 + s * s
        local size = math.max(r * 0.8, 6)
        local z = r + ((i % 3) - 1) * 0.9 + math.sin(t * 2 + i) * 0.3   -- Distance = how far in front of you it hangs
        return right * (size * math.cos(a) / den) + Vector3.yAxis * (2 + size * s * math.cos(a) / den * 1.1) + flat * z
    elseif shape == "Galaxy" then   -- three spiral arms lying flat around you
        local arm = (i - 1) % 3
        local k = math.floor((i - 1) / 3)
        local f = k / math.max(math.ceil(n / 3) - 1, 1)
        local rad = r * (1 + f * 1.1)
        local a = arm / 3 * TAU + f * TAU * 1.1 + t * 0.9
        return right * math.cos(a) * rad + flat * math.sin(a) * rad + Vector3.yAxis * (math.sin(t * 1.5 + f * 6) * 1.2)
    elseif shape == "DNA Helix" then   -- two strands twisting around each other
        local strand = (i - 1) % 2
        local f = math.floor((i - 1) / 2) / math.max(math.ceil(n / 2) - 1, 1)
        local a = f * TAU * 2.5 + t * 2.2 + strand * math.pi
        return right * math.cos(a) * r + flat * math.sin(a) * r + Vector3.yAxis * (-2 + f * r * 2.2)
    else   -- Wings: feathers in three rows behind you, flapping
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

-- PreSimulation runs right before the physics step, so the velocities we set are used that same frame
connect(RunService.PreSimulation or RunService.Heartbeat, function(dt)
    if not (C.TkEnabled and U.Running) then return end
    local _, root = myHumanoid()
    if not root then   -- dead or respawning: stop the parts and give collision back so they land instead of falling out of the map
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
    local gain = math.min(18 * math.max(dt, 1 / 240), 0.9) / math.max(dt, 1 / 240)   -- never overshoots on low fps

    for i = 1, n do
        local part = parts[i]
        if not mine(part) then
            if origCollide[part] ~= nil then lost += 1 letGo(part, false) end   -- lost it: give the collision back
            continue
        end
        if origCollide[part] == nil then
            origCollide[part] = part.CanCollide
            part.CanCollide = false   -- so it never shoves or traps you
        end
        local v = (center + shapeOffset(shape, i, n, now, C.TkDist, right, flat) - part.Position) * gain
        if v.Magnitude > 900 then v = v.Unit * 900 end
        part.AssemblyLinearVelocity = v
        part.AssemblyAngularVelocity = Vector3.new(0, 4, 0)
    end
end)
end

-- chat spy ------------------------------------------------------------------------------------
-- Logs every chat message this client receives, tagged public / whisper / team, in its own window.
-- It can only show what the server actually sends to you: with the newer TextChatService, whispers
-- between other people are never delivered to your client, so they cannot be seen by any script.

local chatSec = miscTab:Section("Chat Spy")
local chatOpt = miscTab:Section("Chat Spy Options", "right")

local TextChatService = game:GetService("TextChatService")
local chatLog, chatLabels, recentChat = {}, {}, {}
local chatGui, chatFrame, chatList, chatPos
local chatDrag   -- { start = Vector3, from = UDim2 } while the title bar is held

-- The window borrows its look from the menu (sharp corners, 2px accent border, top bar with a divider,
-- RobotoMono). Its colours are read from the live menu a couple of times a second, so switching the
-- theme in Settings switches this window too.
local TEXT_COLOR, FAINT_HEX = Color3.fromRGB(232, 226, 227), "#685a5e"
local TEAM_COLOR = Color3.fromRGB(110, 220, 140)
local chatColors = {
    Accent = Color3.fromRGB(255, 32, 48), Bg = Color3.fromRGB(11, 4, 6),
    BgTop = Color3.fromRGB(19, 5, 8), Border = Color3.fromRGB(96, 14, 24),
}
local chatStroke, chatTop, chatTitle, chatLine   -- window parts that follow the theme
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
    chatGui.Name = U.rname()
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

    chatLine = Instance.new("Frame")   -- divider under the top bar, like the menu's
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
    -- the same message can arrive through more than one route
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

-- classic chat: Player.Chatted carries the raw text, so whispers and team chat can be recognised
-- by their command prefix. New chat: TextChatService knows which channel a message came from.
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
end)()   -- cframe / telekinesis / chat spy

----------------------------------------------------------------------
-- tab: Notifications
----------------------------------------------------------------------

local notifTab = win:Tab("Notifications")
local notifSec = notifTab:Section("Appearance")
local notifShow = notifTab:Section("Show Notifications For", "right")

toggle(notifSec, "Notifications", "NotifOn", true)
slider(notifSec, "Duration", "NotifDuration", 1, 10, 4, { Suffix = "s" })
slider(notifSec, "Max On Screen", "NotifMax", 1, 8, 5)
toggle(notifSec, "Use Theme Color", "NotifThemeColor", true)
color(notifSec, "Notification Color", "NotifColor", Color3.fromRGB(255, 32, 48))
toggle(notifSec, "Notification Rainbow", "NotifRainbow", false)
-- a soft light around every notification and the Rage text, in their own colour
toggle(notifSec, "Glow", "NotifGlow", false)
slider(notifSec, "Glow Size", "NotifGlowSize", 2, 14, 6, { Suffix = " px" })
dropdown(notifSec, "Position", "NotifPos", { "Above Crosshair", "Below Crosshair" }, "Above Crosshair")
color(notifSec, "Rage Text Color", "RageStatusColor", Color3.fromRGB(255, 255, 255))
toggle(notifSec, "Rage Text Rainbow", "RageStatusRainbow", false)
notifSec:Button({ Text = "Test Notification", Callback = function()
    showToast("Terkan", "This is how notifications look")
end })
notifSec:Button({ Text = "Test Warning", Callback = function()
    showToast("Warning", "This is how a warning looks", "warn")
end })

-- one switch per kind of notification; anything switched off is simply never shown
toggle(notifShow, "Feature On / Off", "Notif_toggle", true)
toggle(notifShow, "Rage Status Bar", "RageStatus", true)
toggle(notifShow, "Config Events", "Notif_config", true)
toggle(notifShow, "Protection Alerts", "Notif_protect", true)
toggle(notifShow, "Warnings & Errors", "Notif_warn", true)
toggle(notifShow, "Target Locked", "Notif_target", false)
toggle(notifShow, "Target Eliminated", "Notif_target_dead", false)
toggle(notifShow, "Player Joined / Left", "Notif_players", false)
toggle(notifShow, "Startup Message", "Notif_startup", true)
toggle(notifShow, "Other", "Notif_misc", true)

-- target events: watch whoever the rage / aimbot / silent aim is currently on
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

    -- the previous target is gone: was that because they died?
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

----------------------------------------------------------------------
-- tab: Settings
----------------------------------------------------------------------

local settingsTab = win:Tab("Settings")
local cfgSec = settingsTab:Section("Configs")
local themeSec = settingsTab:Section("Theme", "right")
local menuSec = settingsTab:Section("Menu", "right")
local bindSec = settingsTab:Section("Binds", "right")

-- configs
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
    U.LoadingConfig = true                              -- setting many switches at once must not toast each one
    task.delay(0.8, function() U.LoadingConfig = false U.WarnAllBindClashes() end)
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

-- theme
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

-- menu
keybind(menuSec, "Menu Key", "MenuKey", Enum.KeyCode.RightShift, nil, function(key)
    win:SetToggleKey(key or Enum.KeyCode.RightShift)
end)
toggle(menuSec, "Background Blur", "BlurOn", false, function(v) win:SetBlur(v, C.BlurSize) end)
slider(menuSec, "Blur Strength", "BlurSize", 4, 40, 16, { OnChange = function(v) if C.BlurOn then win:SetBlur(true, v) end end })
slider(menuSec, "UI Scale", "UiScale", 0.6, 1.4, 1, { Decimals = 2, OnChange = function(v) win:SetScale(v) end })
-- free mouse: while the menu is open the pointer is handed back, even in first-person / mouse-locked games.
-- Two layers: a Modal button (the official way to unlock the mouse) and forcing MouseBehavior every frame.
;(function()
    toggle(menuSec, "Free Mouse When Menu Open", "FreeMouse", true)

    local modalGui = Instance.new("ScreenGui")
    modalGui.Name = U.rname()
    modalGui.ResetOnSpawn = false
    modalGui.DisplayOrder = 1
    modalGui.Parent = parentGui()   -- not PlayerGui: a game script could see it there
    local modal = Instance.new("TextButton")
    modal.Size = UDim2.fromOffset(2, 2)
    modal.BackgroundTransparency = 1
    modal.Text = ""
    modal.Modal = true
    modal.Visible = false
    modal.Parent = modalGui
    onUnload(function() modalGui:Destroy() end)

    local wasFree = false
    local function frame()
        if not U.Running then return end
        local open = C.FreeMouse and win.Main.Visible
        if open then
            modal.Visible = true
            if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
                UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            end
            UserInputService.MouseIconEnabled = true
            wasFree = true
        elseif wasFree then
            wasFree = false
            modal.Visible = false   -- the game locks the mouse again by itself
        end
    end
    bindCounter += 1
    local name = "TerkanU_" .. bindCounter
    RunService:BindToRenderStep(name, Enum.RenderPriority.Last.Value + 1, U.Guard(frame))   -- after the custom cursor code
    table.insert(U.Binds, name)
end)()

menuSec:Button({ Text = "Unload Menu", Callback = function() U.Unload() end })

-- quick toggle binds
local function flip(key) return function() if TOG[key] then TOG[key]:Set(not TOG[key]:Get()) end end end
keybind(bindSec, "Soft Aim", "BindAim", nil, flip("AimEnabled"))
if TOG.SilentEnabled then keybind(bindSec, "Silent Aim", "BindSilent", nil, flip("SilentEnabled")) end
keybind(bindSec, "Triggerbot", "BindTrig", nil, flip("TrigEnabled"))
keybind(bindSec, "Rage Bot", "BindRage", Enum.KeyCode.End, flip("RageEnabled"))   -- End = on/off switch that never needs the menu
keybind(bindSec, "ESP", "BindEsp", nil, flip("ESPEnabled"))
keybind(bindSec, "Spin", "BindSpin", nil, flip("SpinOn"))
keybind(bindSec, "Headsit", "BindHeadsit", nil, flip("HeadSit"))
keybind(bindSec, "Superman Fly", "BindSuper", nil, flip("SuperFly"))
keybind(bindSec, "Punch Fling", "BindPunchFling", nil, flip("PunchOn"))
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
keybind(bindSec, "Weapon Skin", "BindSkin", nil, flip("SkinOn"))
keybind(bindSec, "Potato Mode", "BindPotato", nil, flip("Potato"))

----------------------------------------------------------------------
-- startup / unload
----------------------------------------------------------------------

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
    else
        notify("Terkan", "Universal loaded - " .. tostring(win.ToggleKey.Name) .. " toggles the menu")
        -- no autoload config of your own: start with the settings that suit this game (a saved config always wins)
        local GAME_PROFILES = {
            [10449761463] = { name = "The Strongest Battlegrounds", flags = { PunchOn = true, PunchAnim = "Normal Punch Ability (TSB)" } },
        }
        local profile = GAME_PROFILES[game.PlaceId]
        if profile then
            for flag, value in pairs(profile.flags) do
                local entry = win.Flags[flag]
                if entry then pcall(entry.Set, value, false) end
            end
            notify("Terkan", profile.name .. " profile applied (Punch Fling is on)", "success", "startup")
        end
    end

    -- newer version on GitHub? (a tiny version.txt; a failed request is simply ignored)
    task.spawn(function()
        local fine, body = pcall(function()
            return game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/version.txt")
        end)
        local remote = fine and type(body) == "string" and body:match("(%d+)%.(%d+)%.(%d+)") and body:match("%d+%.%d+%.%d+")
        if not remote then return end
        local function parts(v) local a, b, c = v:match("(%d+)%.(%d+)%.(%d+)") return { tonumber(a), tonumber(b), tonumber(c) } end
        local r, l = parts(remote), parts(U.Version)
        for i = 1, 3 do
            if r[i] ~= l[i] then
                if r[i] > l[i] then
                    notify("Update", ("Version %s is out (you have %s) - run your loader again"):format(remote, U.Version), nil, "startup")
                end
                break
            end
        end
    end)
    task.delay(0.8, function()
        U.LoadingConfig = false
        U.Ready = true          -- from here on, switching a feature may notify
        U.WarnAllBindClashes()
    end)
end)

return win
