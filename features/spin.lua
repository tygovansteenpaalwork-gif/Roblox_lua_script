--[[
    Spin  -  spin.lua
    Spin your character around any axis at any speed (others see it).

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/spin.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "spin", Title = "Spin" })

local C, Ready, RunService, U, connect, dropdown = ctx.C, ctx.Ready, ctx.RunService, ctx.U, ctx.connect, ctx.dropdown
local myHumanoid, onUnload, slider, toggle, win = ctx.myHumanoid, ctx.onUnload, ctx.slider, ctx.toggle, ctx.win

local funTab = win:Tab("Spin")
local spinSec = funTab:Section("Spin")

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

Ready()
