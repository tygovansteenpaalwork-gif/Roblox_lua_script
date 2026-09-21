--[[
    Example: your own menu on the Terkan library.

    Loads the library, builds a window with a tab and two sections, and shows every kind of control.
    Run it:  loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/examples/my_menu.lua"))()
--]]

local Terkan = loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/Terkan.lua"))()
local UI = Terkan.ui()

local win = UI:Window({
    Title = "MY MENU",
    Version = "V 1.0",
    Footer = "built on Terkan",
    ToggleKey = Enum.KeyCode.RightShift,
})

local tab = win:Tab("Main")
local left = tab:Section("Controls")
local right = tab:Section("Choices", "right")

left:Toggle({ Text = "Enabled", Default = false, Callback = function(on) print("enabled:", on) end })
left:Slider({ Text = "Speed", Min = 1, Max = 100, Default = 20, Callback = function(v) print("speed:", v) end })
left:Slider({ Text = "Delay", Min = 0.1, Max = 2, Default = 0.5, Decimals = 1 })
left:Button({ Text = "Say hello", Callback = function()
    win:Notify({ Title = "Hello", Text = "The button works" })
end })

right:Dropdown({ Text = "Mode", Options = { "Fast", "Normal", "Slow" }, Default = "Normal",
    Callback = function(v) print("mode:", v) end })
right:Keybind({ Text = "Action key", Default = Enum.KeyCode.G, Callback = function() print("action!") end })
right:ColorPicker({ Text = "Colour", Default = Color3.fromRGB(255, 60, 60), Callback = function(c) print("colour:", c) end })

-- the loader can also run any single feature of the hub, in a small menu of its own:
--   Terkan.feature("esp")
--   Terkan.list()   -- all names
