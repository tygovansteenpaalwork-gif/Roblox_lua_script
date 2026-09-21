--[[
    Noclip  -  noclip.lua
    Walk through walls.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/noclip.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "noclip", Title = "Noclip" })

local C, Ready, RunService, U, connect, myHumanoid = ctx.C, ctx.Ready, ctx.RunService, ctx.U, ctx.connect, ctx.myHumanoid
local toggle, win = ctx.toggle, ctx.win

local moveTab = win:Tab("Noclip")
local fly = moveTab:Section("Flight & Collision")

-- noclip -----------------------------------------------------------------

local noclipOriginal = {}
toggle(fly, "Noclip", "Noclip", false, function(v)
    if not v then
        for part, was in pairs(noclipOriginal) do
            if part.Parent then part.CanCollide = was end
        end
        table.clear(noclipOriginal)
    end
end)

local function applyNoclip()
    if not (C.Noclip and U.Running) then return end
    local _, _, char = myHumanoid()
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            if noclipOriginal[part] == nil then noclipOriginal[part] = true end
            part.CanCollide = false
        end
    end
end
connect(RunService.Stepped, applyNoclip)

Ready()
