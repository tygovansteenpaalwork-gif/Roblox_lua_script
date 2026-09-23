--[[
    No Animations  -  no_animations.lua
    Stops the animations of your own character (stop all, attacks only, freeze pose).

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/no_animations.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "no_animations", Title = "No Animations" })

local C, Ready, RunService, U, connect, dropdown = ctx.C, ctx.Ready, ctx.RunService, ctx.U, ctx.connect, ctx.dropdown
local lp, myHumanoid, onUnload, renderFirst, renderLast, toggle = ctx.lp, ctx.myHumanoid, ctx.onUnload, ctx.renderFirst, ctx.renderLast, ctx.toggle
local win = ctx.win

local playerTab = win:Tab("No Animations")

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

Ready()
