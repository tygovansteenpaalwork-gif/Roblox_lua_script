--[[
    FE Animations  -  fe_animations.lua
    Emotes, your own animation ids, sit anywhere, lay down: animations others can see.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/fe_animations.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "fe_animations", Title = "FE Animations" })

local C, Ready, RunService, U, connect, dropdown = ctx.C, ctx.Ready, ctx.RunService, ctx.U, ctx.connect, ctx.dropdown
local keybind, myHumanoid, notify, onUnload, slider, toggle = ctx.keybind, ctx.myHumanoid, ctx.notify, ctx.onUnload, ctx.slider, ctx.toggle
local win = ctx.win

local funTab = win:Tab("FE Animations")
local animSec = funTab:Section("Animations")
local poseSec = funTab:Section("Poses", "right")

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

Ready()
