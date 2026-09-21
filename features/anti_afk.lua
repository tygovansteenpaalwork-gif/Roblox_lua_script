--[[
    Utility  -  anti_afk.lua
    Anti AFK and rejoin the current server.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/anti_afk.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "anti_afk", Title = "Utility" })

local C, Ready, TeleportService, VirtualUser, connect, lp = ctx.C, ctx.Ready, ctx.TeleportService, ctx.VirtualUser, ctx.connect, ctx.lp
local toggle, win = ctx.toggle, ctx.win

local playerTab = win:Tab("Utility")
local misc1 = playerTab:Section("Utility")

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

Ready()
