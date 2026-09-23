----------------------------------------------------------------------
-- tab: Settings
----------------------------------------------------------------------

local settingsTab = win:Tab("Settings")
local cfgSec = settingsTab:Section("Configs")
local themeSec = settingsTab:Section("Theme", "right")
local menuSec = settingsTab:Section("Menu", "right")
local bindSec = settingsTab:Section("Binds", "right")

-- configs
cfgSec:TextBox({ Text = "Config Name", Placeholder = "my config", Flag = "_cfgName", NoSave = true,
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
    if ok then notify("Terkan", ("Autoload config applied (%d settings)"):format(res), "success")
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
