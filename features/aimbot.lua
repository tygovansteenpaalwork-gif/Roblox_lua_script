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

local AIM_TYPES, BIND, C, PRIORITIES, Ready, RunService = ctx.AIM_TYPES, ctx.BIND, ctx.C, ctx.PRIORITIES, ctx.Ready, ctx.RunService
local TARGET_PARTS, U, UserInputService, cam, charOf, color = ctx.TARGET_PARTS, ctx.U, ctx.UserInputService, ctx.cam, ctx.charOf, ctx.color
local cursorOverMenu, dropdown, hasFn, keybind, lp, makeCircle = ctx.cursorOverMenu, ctx.dropdown, ctx.hasFn, ctx.keybind, ctx.lp, ctx.makeCircle
local notify, onUnload, predicted, renderLast, screenPoint, selectTarget = ctx.notify, ctx.onUnload, ctx.predicted, ctx.renderLast, ctx.screenPoint, ctx.selectTarget
local slider, toggle, viewportCenter, win = ctx.slider, ctx.toggle, ctx.viewportCenter, ctx.win

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
toggle(aimTune, "Skip ForceField", "AimNoFF", true)
toggle(aimTune, "Skip Invisible Rigs", "AimNoInvis", true)
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
        U.AimMouseMode, U.AimMouseBlocked = nil, nil   -- switching the aimbot off and on checks the camera again
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
    -- never fight the user while they are working in the menu, nor Rage while it has a target (both would turn the camera)
    if not active or cursorOverMenu() or (U.RageTarget and U.RageTarget()) then aimTarget = nil releaseFace() return end

    local opts = {
        Origin = center, FOV = C.AimFov, MaxDist = C.AimDist, Team = C.AimTeam, Wall = C.AimWall,
        AllowDead = not C.AimDead, NoFF = C.AimNoFF, NoInvis = C.AimNoInvis,
        Part = C.AimPart, Priority = C.AimPriority,
    }
    -- Sticky: a locked target may drift out to 1.5x the circle before it is let go, so a fast target (or
    -- smoothing that lags behind) does not lose the lock right at the edge and grab someone else
    local t
    if C.AimSticky and aimTarget and aimTarget.plr.Parent then
        opts.Only, opts.FOV = aimTarget.plr.Name, C.AimFov * 1.5
        t = selectTarget(opts)
        opts.Only, opts.FOV = nil, C.AimFov
    end
    t = t or selectTarget(opts)
    aimTarget = t
    if not t then return end

    local goal = predicted(t, C.AimPredict)
    local smooth = math.clamp(C.AimSmooth / 100, 0, 0.98)
    local alpha = 1 - smooth ^ (math.clamp(dt, 0.001, 0.1) * 60)

    local aimType = C.AimType
    if aimType ~= "Character Face" then releaseFace() end
    local instant = aimType == "Hard Lock" or aimType == "Snap On Fire"
    -- this game overwrites the camera itself (see the check below): turn it through the mouse instead
    if U.AimMouseMode and aimType ~= "Character Face" and hasFn("mousemoverel") then
        aimType = "Mouse Move"
        if instant then alpha = 1 end
    end

    if aimType == "Hard Lock" or aimType == "Snap On Fire" then
        -- instant: the camera points exactly at the target, no smoothing
        local c = cam()
        c.CFrame = CFrame.lookAt(c.CFrame.Position, goal)
        U.aimLook = c.CFrame.LookVector
    elseif aimType == "Mouse Move" and hasFn("mousemoverel") then
        -- moves the real cursor (works in games that read the mouse delta, e.g. locked first person)
        local sp = screenPoint(goal)
        local dx, dy = (sp.X - center.X) * alpha, (sp.Y - center.Y) * alpha
        mousemoverel(dx, dy)
        -- switched here automatically: the camera check below verifies that the mouse really turns the view
        if U.AimMouseMode then U.mouseSent = { look = cam().CFrame.LookVector, px = math.sqrt(dx * dx + dy * dy) } end
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
        U.aimLook = c.CFrame.LookVector
    end
end)

-- Some games keep their own camera angles and write them back every frame. The aimbot then only wins while it
-- is locked: the moment it lets go, the camera jumps back to where the game had it ("the camera resets").
-- Right after the game's camera scripts we check whether the direction the aimbot set last frame survived.
-- If it was undone several frames in a row while the mouse did not move, the aimbot switches to moving the
-- mouse, which goes through the game's own camera controls and so keeps the view where it was aimed.
do
    local undone, deaf = 0, 0
    local name = "TerkanU_AimCamCheck"
    RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, U.Guard(function()
        -- in mouse mode: a clear mouse move that did not turn the camera at all means the mouse does not steer
        -- the view here (e.g. third person without holding the right mouse button): go back to camera aiming
        local sent = U.mouseSent
        U.mouseSent = nil
        if sent and U.AimMouseMode then
            if sent.px > 4 then
                if cam().CFrame.LookVector:Dot(sent.look) > math.cos(math.rad(0.2)) then deaf += 1 else deaf = 0 end
            end
            if deaf >= 15 then
                U.AimMouseMode, U.AimMouseBlocked, deaf, undone = nil, true, 0, 0
                notify("Aimbot", "Moving the mouse does not turn the camera here: back to turning the camera", "warn")
            end
            return
        end

        local want = U.aimLook
        U.aimLook = nil
        if not want or U.AimMouseMode or U.AimMouseBlocked then return end
        local moved = UserInputService:GetMouseDelta().Magnitude > 1
        if not moved and cam().CFrame.LookVector:Dot(want) < math.cos(math.rad(4)) then
            undone += 1
        else
            undone = math.max(undone - 1, 0)
        end
        if undone >= 8 then
            U.AimMouseMode = true
            if hasFn("mousemoverel") then
                notify("Aimbot", "This game resets the camera itself: aiming now moves the mouse instead", "warn")
            else
                notify("Aimbot", "This game resets the camera itself, and this executor has no mousemoverel to work around it", "warn")
            end
        end
    end))
    table.insert(U.Binds, name)
end

Ready()
