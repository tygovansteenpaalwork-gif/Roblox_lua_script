--[[
    Unlimited Zoom  -  unlimited_zoom.lua
    Removes the camera zoom limit.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/unlimited_zoom.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "unlimited_zoom", Title = "Unlimited Zoom" })

local C, Ready, U, lp, onUnload, renderLast = ctx.C, ctx.Ready, ctx.U, ctx.lp, ctx.onUnload, ctx.renderLast
local slider, toggle, win = ctx.slider, ctx.toggle, ctx.win

local uniTab = win:Tab("Zoom")
local camSec = uniTab:Section("Camera")

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

Ready()
