--[[
    Utility  -  anti_afk.lua
    Anti AFK, rejoin and server hop (to a smaller server).

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/anti_afk.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "anti_afk", Title = "Utility" })

local C, HttpService, Ready, TeleportService, VirtualUser, connect = ctx.C, ctx.HttpService, ctx.Ready, ctx.TeleportService, ctx.VirtualUser, ctx.connect
local lp, notify, toggle, win = ctx.lp, ctx.notify, ctx.toggle, ctx.win

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

----------------------------------------------------------------------

Ready()
