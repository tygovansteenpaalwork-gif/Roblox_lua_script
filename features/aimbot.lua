--[[
    Aimbot  -  aimbot.lua
    Soft aim with five aim types, FOV circle, sticky target, team / dead / wall checks.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/aimbot.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "aimbot", Title = "Aimbot" })

local AIM_TYPES, BIND, C, PRIORITIES, Ready, TARGET_PARTS = ctx.AIM_TYPES, ctx.BIND, ctx.C, ctx.PRIORITIES, ctx.Ready, ctx.TARGET_PARTS
local U, UserInputService, cam, charOf, color, cursorOverMenu = ctx.U, ctx.UserInputService, ctx.cam, ctx.charOf, ctx.color, ctx.cursorOverMenu
local dropdown, hasFn, keybind, lp, makeCircle, onUnload = ctx.dropdown, ctx.hasFn, ctx.keybind, ctx.lp, ctx.makeCircle, ctx.onUnload
local predicted, renderLast, screenPoint, selectTarget, slider, toggle = ctx.predicted, ctx.renderLast, ctx.screenPoint, ctx.selectTarget, ctx.slider, ctx.toggle
local viewportCenter, win = ctx.viewportCenter, ctx.win

local aimTab = win:Tab("Aimbot")
local aim = aimTab:Section("Soft Aim")
local aimTune = aimTab:Section("Targeting", "right")

toggle(aim, "Enabled", "AimEnabled", false)
dropdown(aim, "Mode", "AimMode", { "Hold Key", "Always On" }, "Hold Key")
keybind(aim, "Aim Key", "AimKey", Enum.UserInputType.MouseButton2)
dropdown(aim, "Aimbot Type", "AimType", AIM_TYPES, "Smooth Camera")
slider(aim, "Smoothness", "AimSmooth", 0, 95, 35, { Suffix = "%" })
slider(aim, "Prediction", "AimPredict", 0, 0.3, 0, { Decimals = 2, Suffix = "s" })
toggle(aim, "Sticky Target", "AimSticky", true)

dropdown(aimTune, "Target Part", "AimPart", TARGET_PARTS, "Head")
dropdown(aimTune, "Priority", "AimPriority", PRIORITIES, "Closest to Cursor")
slider(aimTune, "Max Distance", "AimDist", 50, 2000, 500, { Suffix = " st" })
slider(aimTune, "FOV Radius", "AimFov", 20, 800, 160, { Suffix = " px" })
toggle(aimTune, "Team Check", "AimTeam", true)
toggle(aimTune, "Dead Check", "AimDead", true)
toggle(aimTune, "Wall Check", "AimWall", true)
toggle(aimTune, "Show FOV Circle", "AimShowFov", true)
color(aimTune, "FOV Color", "AimFovColor", Color3.fromRGB(255, 255, 255))

local aimCircle = makeCircle()
local aimTarget
local faceLocked = false

-- "Character Face" switches off the humanoid's own turning; hand it back when done
local function releaseFace()
    if faceLocked then
        faceLocked = false
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.AutoRotate = true end
    end
end
onUnload(releaseFace)

renderLast(function(dt)
    if not (C.AimEnabled and U.Running) then
        aimTarget = nil
        releaseFace()
        aimCircle(0, Vector2.zero, C.AimFovColor, false)
        return
    end
    local center = viewportCenter()
    aimCircle(C.AimFov, center, C.AimFovColor, C.AimShowFov)

    local active = C.AimMode == "Always On" or (BIND.AimKey and BIND.AimKey:IsDown())
    if C.AimType == "Snap On Fire" then
        active = active and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end
    -- never fight the user while they are working in the menu
    if not active or cursorOverMenu() then aimTarget = nil releaseFace() return end

    local t = selectTarget({
        Origin = center, FOV = C.AimFov, MaxDist = C.AimDist, Team = C.AimTeam, Wall = C.AimWall,
        AllowDead = not C.AimDead,
        Part = C.AimPart, Priority = C.AimPriority, Sticky = C.AimSticky and aimTarget and aimTarget.plr or nil,
    })
    aimTarget = t
    if not t then return end

    local goal = predicted(t, C.AimPredict)
    local smooth = math.clamp(C.AimSmooth / 100, 0, 0.98)
    local alpha = 1 - smooth ^ (math.clamp(dt, 0.001, 0.1) * 60)

    local aimType = C.AimType
    if aimType ~= "Character Face" then releaseFace() end

    if aimType == "Hard Lock" or aimType == "Snap On Fire" then
        -- instant: the camera points exactly at the target, no smoothing
        local c = cam()
        c.CFrame = CFrame.lookAt(c.CFrame.Position, goal)
    elseif aimType == "Mouse Move" and hasFn("mousemoverel") then
        -- moves the real cursor (works in games that read the mouse delta, e.g. locked first person)
        local sp = screenPoint(goal)
        mousemoverel((sp.X - center.X) * alpha, (sp.Y - center.Y) * alpha)
    elseif aimType == "Character Face" then
        -- turns the character instead of the camera (third person)
        local char, hum, root = charOf(lp)
        if char then
            hum.AutoRotate = false
            faceLocked = true
            local flat = Vector3.new(goal.X, root.Position.Y, goal.Z)
            root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, flat), alpha)
        end
    else
        -- "Smooth Camera" (also the fallback when Mouse Move is not available)
        local c = cam()
        c.CFrame = c.CFrame:Lerp(CFrame.lookAt(c.CFrame.Position, goal), alpha)
    end
end)

Ready()
