--[[
    Anti Void  -  anti_void.lua
    Puts you back on the last solid ground when you fall below the map.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/anti_void.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "anti_void", Title = "Anti Void" })

local C, Ready, RunService, U, connect, lp = ctx.C, ctx.Ready, ctx.RunService, ctx.U, ctx.connect, ctx.lp
local myHumanoid, notify, slider, toggle, win = ctx.myHumanoid, ctx.notify, ctx.slider, ctx.toggle, ctx.win

local defTab = win:Tab("Anti Void")
local avSec = defTab:Section("Anti Void")

-- anti void -------------------------------------------------------------
-- remembers the last solid ground you stood on; if you drop under the rescue line
-- (a margin above the map's FallenPartsDestroyHeight) you are put back there

toggle(avSec, "Anti Void", "AntiVoid", false)
slider(avSec, "Rescue Margin", "VoidMargin", 20, 400, 150, { Suffix = " st" })

local groundCF, groundAt, lastVoidNote = nil, 0, 0
connect(RunService.Heartbeat, function()
    if not (C.AntiVoid and U.Running) then return end
    local hum, root = myHumanoid()
    if not (hum and root) then return end

    local level = math.max(workspace.FallenPartsDestroyHeight, -1000) + C.VoidMargin
    if root.Position.Y > level + 30 and hum.FloorMaterial ~= Enum.Material.Air and os.clock() - groundAt > 0.25 then
        groundCF, groundAt = root.CFrame, os.clock()
    end

    if root.Position.Y < level then
        local dest = groundCF
        if not dest then
            local spawn = lp.RespawnLocation or workspace:FindFirstChildWhichIsA("SpawnLocation", true)
            dest = spawn and (spawn.CFrame + Vector3.new(0, 4, 0))
        end
        if dest then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = dest + Vector3.new(0, 3, 0)
            if os.clock() - lastVoidNote > 2 then
                lastVoidNote = os.clock()
                notify("Anti Void", "Pulled you back from the void", "warn")
            end
        end
    end
end)

Ready()
