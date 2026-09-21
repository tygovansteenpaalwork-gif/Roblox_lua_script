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

