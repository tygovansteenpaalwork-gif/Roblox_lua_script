--[[
    Stats HUD  -  stats_hud.lua
    FPS, ping and player count in a corner.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/stats_hud.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "stats_hud", Title = "Stats HUD" })

local C, Players, Ready, RunService, U, connect = ctx.C, ctx.Players, ctx.Ready, ctx.RunService, ctx.U, ctx.connect
local dropdown, onUnload, parentGui, toggle, win = ctx.dropdown, ctx.onUnload, ctx.parentGui, ctx.toggle, ctx.win

local uniTab = win:Tab("Stats HUD")
local hudSec = uniTab:Section("Stats HUD")

-- stats HUD ------------------------------------------------------------------------

local HUD_CORNERS = {
    ["Top Left"] = { Vector2.new(0, 0), UDim2.new(0, 8, 0, 8) },
    ["Top Right"] = { Vector2.new(1, 0), UDim2.new(1, -8, 0, 8) },
    ["Bottom Left"] = { Vector2.new(0, 1), UDim2.new(0, 8, 1, -8) },
    ["Bottom Right"] = { Vector2.new(1, 1), UDim2.new(1, -8, 1, -8) },
}
local hudGui, hudLbl
local hudTime, hudFrames = 0, 0

local function destroyHud()
    if hudGui then hudGui:Destroy() end
    hudGui, hudLbl = nil, nil
end
onUnload(destroyHud)

local function buildHud()
    hudGui = Instance.new("ScreenGui")
    hudGui.Name = U.rname()
    hudGui.ResetOnSpawn = false
    hudGui.IgnoreGuiInset = true
    hudGui.DisplayOrder = 100
    hudGui.Parent = parentGui()

    hudLbl = Instance.new("TextLabel")
    hudLbl.BackgroundColor3 = Color3.new(0, 0, 0)
    hudLbl.BackgroundTransparency = 0.45
    hudLbl.TextColor3 = Color3.new(1, 1, 1)
    hudLbl.Font = Enum.Font.Code
    hudLbl.TextSize = 14
    hudLbl.AutomaticSize = Enum.AutomaticSize.XY
    hudLbl.Size = UDim2.fromOffset(0, 0)
    hudLbl.Text = "..."
    hudLbl.Parent = hudGui
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
    pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
    pad.Parent = hudLbl
    Instance.new("UICorner", hudLbl).CornerRadius = UDim.new(0, 5)
end

toggle(hudSec, "Show FPS / Ping / Players", "StatsHud", false, function(v) if not v then destroyHud() end end)
dropdown(hudSec, "Corner", "HudCorner", { "Top Left", "Top Right", "Bottom Left", "Bottom Right" }, "Top Right")

connect(RunService.RenderStepped, function(dt)
    if not (C.StatsHud and U.Running) then return end
    if not hudGui then buildHud() end
    hudTime += dt
    hudFrames += 1
    if hudTime < 0.5 then return end
    local fps = math.floor(hudFrames / hudTime + 0.5)
    hudTime, hudFrames = 0, 0

    local ping = "?"
    pcall(function()
        ping = tostring(math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5))
    end)
    local corner = HUD_CORNERS[C.HudCorner] or HUD_CORNERS["Top Right"]
    hudLbl.AnchorPoint, hudLbl.Position = corner[1], corner[2]
    hudLbl.Text = ("FPS %d  |  Ping %s ms  |  Players %d/%d"):format(fps, ping, #Players:GetPlayers(), Players.MaxPlayers)
end)

Ready()
