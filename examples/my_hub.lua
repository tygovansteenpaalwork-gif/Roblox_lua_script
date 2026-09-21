--[[
    Example: your own hub, with your own tabs and functions, on the helpers of the Terkan library.

    Terkan.core() gives you a window plus the same helpers the Terkan hub is built with: toggle / slider / dropdown /
    keybind (they fill the table C for you), connect (cleaned up on unload), notify and the targeting functions.
    This example adds two tabs and one function of its own: it tells you which player is nearest.

    Run it:  loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/examples/my_hub.lua"))()
--]]

local Terkan = loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/Terkan.lua"))()
local ctx = Terkan.core({ Name = "myhub", Title = "My Hub" })

local win, C = ctx.win, ctx.C
local toggle, slider, dropdown, keybind = ctx.toggle, ctx.slider, ctx.dropdown, ctx.keybind
local connect, notify, selectTarget = ctx.connect, ctx.notify, ctx.selectTarget

----------------------------------------------------------------------
-- tab 1: your own function
----------------------------------------------------------------------
local tab = win:Tab("Radar")
local sec = tab:Section("Nearest player")

-- toggle(section, text, key, default): the value is kept in C[key], and saved in configs
toggle(sec, "Announce nearest", "AnnounceNearest", false)
slider(sec, "Max distance", "AnnounceDist", 50, 2000, 500, { Suffix = " st" })
dropdown(sec, "Aim at", "AnnouncePart", { "Head", "Torso" }, "Head")
keybind(sec, "Announce now", "AnnounceKey", Enum.KeyCode.H, function() C.AnnounceNow = true end)

local last = 0
connect(game:GetService("RunService").Heartbeat, function()
    if not (C.AnnounceNearest or C.AnnounceNow) then return end
    if os.clock() - last < 2 then return end      -- at most once every two seconds
    last, C.AnnounceNow = os.clock(), false

    -- selectTarget looks at every other player and returns the best one (or nil)
    local target = selectTarget({
        MaxDist = C.AnnounceDist, Part = C.AnnouncePart, Priority = "Closest Distance",
        Team = false, Wall = false,
    })
    if target then
        notify("Nearest", ("%s  -  %d studs"):format(target.plr.DisplayName, target.dist), "success")
    else
        notify("Nearest", "nobody in range", "warn")
    end
end)

----------------------------------------------------------------------
-- tab 2: anything else you like, with the plain UI controls
----------------------------------------------------------------------
local info = win:Tab("About"):Section("My Hub")
info:Label("Built on the Terkan library")
info:Button({ Text = "Say hello", Callback = function() notify("Hello", "It works", "success") end })

ctx.Ready()   -- the menu is completely built
