--[[
    Orbit Player  -  orbit.lua
    Circle around a player (circle, bob or figure eight) with lock-on.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/orbit.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "orbit", Title = "Orbit Player" })

local C, Players, Ready, TOG, U, addPlayerPicker = ctx.C, ctx.Players, ctx.Ready, ctx.TOG, ctx.U, ctx.addPlayerPicker
local cam, charOf, dropdown, myHumanoid, playerNames, renderLast = ctx.cam, ctx.charOf, ctx.dropdown, ctx.myHumanoid, ctx.playerNames, ctx.renderLast
local slider, toggle, win = ctx.slider, ctx.toggle, ctx.win

local playerTab = win:Tab("Orbit")
local tp = playerTab:Section("Player")
local playerDD = addPlayerPicker(tp)

-- orbit ------------------------------------------------------------------

local orbit = playerTab:Section("Orbit Player")
orbitDD = orbit:Dropdown({ Text = "Orbit Player", Options = playerNames(), Flag = "OrbitPlayer", NoSave = true,
    Callback = function(v) C.OrbitPlayer = v end })
toggle(orbit, "Orbit", "OrbitEnabled", false, function(v)
    if v and C.FollowEnabled and TOG.FollowEnabled then
        C.FollowEnabled = false
        TOG.FollowEnabled:Set(false, true)
    end
end)
toggle(orbit, "Lock On Target", "OrbitLock", true)
dropdown(orbit, "Orbit Mode", "OrbitMode", { "Circle", "Bobbing", "Figure Eight" }, "Circle")
slider(orbit, "Height", "OrbitHeight", -10, 30, 3, { Decimals = 1, Suffix = " st" })
slider(orbit, "Distance", "OrbitDist", 1, 40, 8, { Decimals = 1, Suffix = " st" })
slider(orbit, "Rotation Speed", "OrbitSpeed", 10, 720, 120, { Suffix = "°/s" })
toggle(orbit, "Reverse Direction", "OrbitReverse", false)

local orbitAngle = 0
renderLast(function(dt)
    if not (C.OrbitEnabled and U.Running) then return end
    local target = C.OrbitPlayer and Players:FindFirstChild(C.OrbitPlayer)
    if not target then return end
    local _, _, targetRoot = charOf(target)
    local _, myRoot = myHumanoid()
    if not (targetRoot and myRoot) then return end

    orbitAngle += math.rad(C.OrbitSpeed) * math.clamp(dt, 0, 0.1) * (C.OrbitReverse and -1 or 1)
    local r, h, a = C.OrbitDist, C.OrbitHeight, orbitAngle
    local offset
    if C.OrbitMode == "Bobbing" then
        offset = Vector3.new(math.cos(a) * r, h + math.sin(a * 2) * math.min(r * 0.4, 4), math.sin(a) * r)
    elseif C.OrbitMode == "Figure Eight" then
        offset = Vector3.new(math.cos(a) * r, h, math.sin(a * 2) * r * 0.6)
    else
        offset = Vector3.new(math.cos(a) * r, h, math.sin(a) * r)
    end

    local center = targetRoot.Position
    local pos = center + offset
    if C.OrbitLock then
        -- the character faces the target and the camera stays locked onto them
        myRoot.CFrame = CFrame.lookAt(pos, center)
        local c = cam()
        c.CFrame = CFrame.lookAt(c.CFrame.Position, center)
    else
        myRoot.CFrame = CFrame.new(pos) * myRoot.CFrame.Rotation
    end
    myRoot.AssemblyLinearVelocity = Vector3.zero
end)

Ready()
