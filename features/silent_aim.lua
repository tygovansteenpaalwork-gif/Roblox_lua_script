--[[
    Silent Aim  -  silent_aim.lua
    Silent aim with hit chance and FOV. Needs an executor with hookmetamethod.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/silent_aim.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "silent_aim", Title = "Silent Aim" })

local C, PRIORITIES, Ready, TARGET_PARTS, TOG, U = ctx.C, ctx.PRIORITIES, ctx.Ready, ctx.TARGET_PARTS, ctx.TOG, ctx.U
local UserInputService, cam, color, connect, cursorOrCenter, dropdown = ctx.UserInputService, ctx.cam, ctx.color, ctx.connect, ctx.cursorOrCenter, ctx.dropdown
local hasFn, lp, makeCircle, makeDot, makeLine, notify = ctx.hasFn, ctx.lp, ctx.makeCircle, ctx.makeDot, ctx.makeLine, ctx.notify
local predicted, renderLast, selectTarget, slider, toggle, win = ctx.predicted, ctx.renderLast, ctx.selectTarget, ctx.slider, ctx.toggle, ctx.win

local aimTarget
local aimCircle = makeCircle()

-- Silent aim only exists on executors that can hook metamethods (see the tab for details)
local CAN_HOOK = hasFn("hookmetamethod") and hasFn("getnamecallmethod") and hasFn("checkcaller") and hasFn("newcclosure")

if CAN_HOOK then
    ----------------------------------------------------------------------
    -- tab: Silent Aim
    ----------------------------------------------------------------------

    local silentTab = win:Tab("Silent")
    local silent = silentTab:Section("Silent Aim")
    local silentVis = silentTab:Section("Visuals", "right")

    local HOOKED = false   -- becomes true once the metamethod hooks below are installed

    toggle(silent, "Enabled", "SilentEnabled", false, function(v)
        if v and not HOOKED then
            -- no camera-flick fallback: silent aim either really is silent, or it stays off
            C.SilentEnabled = false
            if TOG.SilentEnabled then TOG.SilentEnabled:Set(false, true) end
            notify("Silent Aim", "Unavailable: this executor cannot hook metamethods (hookmetamethod is missing).", "warn")
        end
    end)
    slider(silent, "Hit Chance", "SilentHit", 1, 100, 85, { Suffix = "%" })
    dropdown(silent, "Target Part", "SilentPart", TARGET_PARTS, "Head")
    dropdown(silent, "Priority", "SilentPriority", PRIORITIES, "Closest to Cursor")
    slider(silent, "Max Distance", "SilentDist", 50, 2000, 600, { Suffix = " st" })
    slider(silent, "Prediction", "SilentPredict", 0, 0.3, 0, { Decimals = 2, Suffix = "s" })
    toggle(silent, "Team Check", "SilentTeam", true)
    toggle(silent, "Dead Check", "SilentDead", true)
    toggle(silent, "Wall Check", "SilentWall", true)
    toggle(silent, "Only While Firing", "SilentFiringOnly", true)
    toggle(silent, "Target Any Direction", "SilentAnyDir", true)

    toggle(silentVis, "Visualize FOV", "SilentShowFov", true)
    slider(silentVis, "FOV Radius", "SilentFov", 20, 800, 200, { Suffix = " px" })
    color(silentVis, "FOV Color", "SilentFovColor", Color3.fromRGB(255, 255, 255))
    toggle(silentVis, "Follow Gunpoint", "SilentFollowGun", false)
    toggle(silentVis, "Follow Target", "SilentFollowTarget", true)
    color(silentVis, "Target Color", "SilentTargetColor", Color3.fromRGB(255, 60, 60))
    local silentMode = silentVis:Label("Mode: ...")

    local silentCircle, silentLine, silentDot = makeCircle(), makeLine(), makeDot()
    local silentTarget
    local silentRoll = true

    local function rollSilent() silentRoll = math.random(1, 100) <= C.SilentHit end

    connect(UserInputService.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            rollSilent()
        end
    end)

    local function firing()
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
            or (lp.Character and lp.Character:FindFirstChildOfClass("Tool") ~= nil and UserInputService.TouchEnabled)
    end

    local function silentGoal()
        if not (C.SilentEnabled and silentTarget and silentRoll) then return end
        if C.SilentFiringOnly and not firing() then return end
        if not silentTarget.part.Parent then return end
        return predicted(silentTarget, C.SilentPredict)
    end

    -- Real silent aim rewrites what the weapon script reads, so it needs metamethod hooks.
    -- Every path a gun can use to find its target is redirected: workspace raycasts, the old
    -- FindPartOnRay family, camera ray helpers, and Mouse.Hit / Target / UnitRay. Because the
    -- direction is rewritten from the ray origin straight to the target, it does not matter
    -- where the camera is looking.
    local RAY_METHODS = {
        Raycast = true, FindPartOnRay = true, FindPartOnRayWithIgnoreList = true,
        FindPartOnRayWithWhitelist = true, ViewportPointToRay = true, ScreenPointToRay = true,
    }

    if hasFn("hookmetamethod") and hasFn("getnamecallmethod") and hasFn("checkcaller") and hasFn("newcclosure") then
        local okHook = pcall(function()
            local oldNamecall
            oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                if U.Running and C.SilentEnabled and not checkcaller() then
                    local method = getnamecallmethod()
                    if RAY_METHODS[method] then
                        local goal = silentGoal()
                        if goal then
                            if method == "Raycast" and self == workspace then
                                local origin, direction, params = ...
                                if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                                    return oldNamecall(self, origin, (goal - origin).Unit * direction.Magnitude, params)
                                end
                            elseif method == "ViewportPointToRay" or method == "ScreenPointToRay" then
                                if typeof(self) == "Instance" and self:IsA("Camera") then
                                    local origin = self.CFrame.Position
                                    return Ray.new(origin, (goal - origin).Unit)
                                end
                            elseif self == workspace then
                                local ray, a, b, c = ...
                                if typeof(ray) == "Ray" then
                                    local newRay = Ray.new(ray.Origin, (goal - ray.Origin).Unit * ray.Direction.Magnitude)
                                    return oldNamecall(self, newRay, a, b, c)
                                end
                            end
                        end
                    end
                end
                return oldNamecall(self, ...)
            end))

            local oldIndex
            oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
                if U.Running and C.SilentEnabled and not checkcaller() and typeof(self) == "Instance"
                    and (key == "Hit" or key == "Target" or key == "UnitRay") and self:IsA("Mouse") then
                    local goal = silentGoal()
                    if goal then
                        if key == "Hit" then return CFrame.new(goal) end
                        if key == "UnitRay" then
                            local origin = cam().CFrame.Position
                            return Ray.new(origin, (goal - origin).Unit)
                        end
                        return silentTarget.part
                    end
                end
                return oldIndex(self, key)
            end))
        end)
        HOOKED = okHook
    end
    silentMode:Set(HOOKED and "Mode: hook (true silent)" or "Unavailable: needs hookmetamethod")

    local silentTick = 0
    renderLast(function()
        if not (C.SilentEnabled and U.Running) then
            silentTarget = nil
            U.SilentTarget = nil
            silentCircle(0, Vector2.zero, C.SilentFovColor, false)
            silentLine(Vector2.zero, Vector2.zero, C.SilentTargetColor, false)
            silentDot(Vector2.zero, C.SilentTargetColor, false)
            return
        end

        local origin = cursorOrCenter(C.SilentFollowGun)
        -- the circle only means something when targets are limited to it
        silentCircle(C.SilentFov, origin, C.SilentFovColor, C.SilentShowFov and not C.SilentAnyDir)

        silentTarget = selectTarget({
            Origin = origin, FOV = (not C.SilentAnyDir) and C.SilentFov or nil,
            MaxDist = C.SilentDist, Team = C.SilentTeam, Wall = C.SilentWall, AllowDead = not C.SilentDead,
            Part = C.SilentPart, Priority = C.SilentPriority, Sticky = silentTarget and silentTarget.plr or nil,
        })

        U.SilentTarget = silentTarget   -- the custom cursor reads this to name who is being aimed at

        -- a target behind the camera has no meaningful screen position, so no line for it
        local showLine = C.SilentFollowTarget and silentTarget ~= nil and silentTarget.onScreen
        silentLine(origin, silentTarget and silentTarget.screen or origin, C.SilentTargetColor, showLine)
        silentDot(silentTarget and silentTarget.screen or origin, C.SilentTargetColor, showLine)

        if os.clock() - silentTick > 0.4 and not firing() then silentTick = os.clock() rollSilent() end
    end)
end

Ready()
