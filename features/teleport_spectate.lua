--[[
    Teleport & Spectate  -  teleport_spectate.lua
    Teleport to a player, spectate, click teleport (hold a key and click).

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/teleport_spectate.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "teleport_spectate", Title = "Teleport & Spectate" })

local BIND, C, Players, Ready, U, UserInputService = ctx.BIND, ctx.C, ctx.Players, ctx.Ready, ctx.U, ctx.UserInputService
local addPlayerPicker, cam, charOf, connect, keybind, lp = ctx.addPlayerPicker, ctx.cam, ctx.charOf, ctx.connect, ctx.keybind, ctx.lp
local myHumanoid, notify, rayParams, renderLast, toggle, win = ctx.myHumanoid, ctx.notify, ctx.rayParams, ctx.renderLast, ctx.toggle, ctx.win

local playerTab = win:Tab("Teleport")
local tp = playerTab:Section("Teleport & Spectate")
local playerDD = addPlayerPicker(tp)

tp:Button({ Text = "Teleport To Player", Callback = function()
    local target = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    local root
    if target then
        local _, _, r = charOf(target)   -- (multi-return: never use `a and f()` here)
        root = r
    end
    local _, myRoot = myHumanoid()
    if root and myRoot then
        myRoot.CFrame = root.CFrame * CFrame.new(0, 0, 3)
    else
        notify("Teleport", "Pick a player that is alive first", "warn")
    end
end })

toggle(tp, "Spectate Player", "Spectate", false, function(v)
    if not v then
        local hum = myHumanoid()
        if hum then cam().CameraSubject = hum end
    end
end)
renderLast(function()
    if not (C.Spectate and U.Running) then return end
    local target = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    if not target then return end
    local _, hum = charOf(target)
    if hum then cam().CameraSubject = hum end
end)

toggle(tp, "Click Teleport (hold key)", "ClickTp", false)
keybind(tp, "Click TP Key", "ClickTpKey", Enum.KeyCode.LeftControl)
connect(UserInputService.InputBegan, function(input, gp)
    if gp or not C.ClickTp or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if not (BIND.ClickTpKey and BIND.ClickTpKey:IsDown()) then return end
    local pos = UserInputService:GetMouseLocation()
    local ray = cam():ViewportPointToRay(pos.X, pos.Y)
    rayParams.FilterDescendantsInstances = { lp.Character }
    local res = workspace:Raycast(ray.Origin, ray.Direction * 2000, rayParams)
    local _, root = myHumanoid()
    if res and root then root.CFrame = CFrame.new(res.Position + Vector3.new(0, 4, 0)) end
end)

Ready()
