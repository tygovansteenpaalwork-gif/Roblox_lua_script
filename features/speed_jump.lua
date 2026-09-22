--[[
    Speed & Jump  -  speed_jump.lua
    Speed, jump power, infinite jump and anti stun. WalkSpeed / JumpPower are not touched: the CFrame mover does the work.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/speed_jump.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "speed_jump", Title = "Speed & Jump" })

local BIND, C, Ready, RunService, U, UserInputService = ctx.BIND, ctx.C, ctx.Ready, ctx.RunService, ctx.U, ctx.UserInputService
local cam, connect, keybind, lp, myHumanoid, renderLast = ctx.cam, ctx.connect, ctx.keybind, ctx.lp, ctx.myHumanoid, ctx.renderLast
local slider, toggle, win = ctx.slider, ctx.toggle, ctx.win

local moveTab = win:Tab("Speed & Jump")
local move = moveTab:Section("Speed & Jump")
local cfSec = moveTab:Section("CFrame Speed")
local cfFlySec = moveTab:Section("CFrame Fly & Dash", "right")

local orig = {}
-- Speed and Jump do NOT touch WalkSpeed / JumpPower (those properties replicate, so a game can read the changed value):
-- the extra speed is added by moving the character (see CFrame Speed further down), the jump by a velocity kick.
toggle(move, "Speed", "SpeedEnabled", false)
slider(move, "Walk Speed", "SpeedValue", 16, 300, 60, { Suffix = "" })

toggle(move, "Jump Power", "JumpEnabled", false)
slider(move, "Jump Value", "JumpValue", 20, 300, 80)
toggle(move, "Infinite Jump", "InfJump", false)
connect(UserInputService.JumpRequest, function()
    if not C.InfJump then return end
    local hum = myHumanoid()
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)
connect(UserInputService.JumpRequest, function()
    if not (C.JumpEnabled and U.Running) then return end
    RunService.Heartbeat:Wait()   -- after the humanoid has given its own normal jump
    local hum, root = myHumanoid()
    if not (hum and root) then return end
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
        local v = root.AssemblyLinearVelocity
        if v.Y < C.JumpValue then root.AssemblyLinearVelocity = Vector3.new(v.X, C.JumpValue, v.Z) end
    end
end)

-- Anti Stun: the routine itself is at the bottom of this tab (shared with Defense > Anti Ragdoll)
toggle(move, "Anti Stun", "AntiStun", false, function(v)
    local hum = myHumanoid()
    if hum and U.StunStates then U.StunStates(hum, v) end
end)

-- anti stun + anti ragdoll ------------------------------------------------------
-- ONE routine for two switches, so they never run twice or undo each other:
--   Movement > Anti Stun      always: every down / ragdoll / stun state and every stun flag, whatever caused it
--   Defense  > Anti Ragdoll   only while the game has flagged us. The Strongest Battlegrounds uses Accessory
--                             instances: "Ragdoll" / "RagdollSim" = ragdolled, "Freeze" = hit stun (that one only
--                             with Cancel Hit Stun). Other games use similar names or attributes, also checked.
-- Nothing of the game is deleted; the server may still think we are stunned, so moves it checks itself can stay blocked.
do
local STUN_FLAGS = { "Ragdoll", "RagdollSim", "Freeze", "Stun", "Stunned", "Knocked", "Downed", "NoMove", "NoMovement" }
local DOWN_STATES = {
    [Enum.HumanoidStateType.Ragdoll] = true, [Enum.HumanoidStateType.FallingDown] = true,
    [Enum.HumanoidStateType.Physics] = true, [Enum.HumanoidStateType.PlatformStanding] = true,
}
local good = { speed = 16, jump = 50, height = 7.2 }   -- our last normal values, put back while stunned
local st = { scanAt = 0, controlsAt = 0 }

-- the humanoid refuses to ragdoll / fall down at all; a new humanoid (respawn) needs it again
function U.StunStates(hum, off)
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not off)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not off)
    end)
end

local function stunFlag(char, hum)
    for _, n in ipairs(STUN_FLAGS) do
        if char:FindFirstChild(n) or char:GetAttribute(n) or hum:GetAttribute(n) then return n end
    end
end

renderLast(function()
    if not U.Running then return end
    local hum, root, char = myHumanoid()
    if not (hum and root) then return end

    if st.hum ~= hum then
        st.hum = hum
        if C.AntiStun then U.StunStates(hum, true) end
    end

    local flag = (C.AntiStun or C.AntiRagdoll) and stunFlag(char, hum)
    if not flag then
        if hum.WalkSpeed >= 4 then good.speed = hum.WalkSpeed end
        if hum.JumpPower >= 5 then good.jump = hum.JumpPower end
        if hum.JumpHeight >= 1 then good.height = hum.JumpHeight end
    end
    local act = C.AntiStun or (C.AntiRagdoll and flag and (flag ~= "Freeze" or C.AntiRagdollStun))
    if not act then return end

    -- our own features that lie down / float on purpose
    local ours = C.FlyEnabled or C.SuperFly or C.LayDown
    if not ours then
        if hum.PlatformStand then hum.PlatformStand = false end
        if DOWN_STATES[hum:GetState()] then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
    end
    if root.Anchored then root.Anchored = false end
    if hum.WalkSpeed < 4 then hum.WalkSpeed = good.speed end
    if hum.UseJumpPower then
        if hum.JumpPower < 5 then hum.JumpPower = good.jump end
    elseif hum.JumpHeight < 1 then
        hum.JumpHeight = good.height
    end

    local now = os.clock()
    -- 4x a second: joints back on, ragdoll sockets off, nothing of us anchored, and (while flagged)
    -- no game mover that pins us to a spot. We create no movers ourselves, so every one is the game's.
    if now - st.scanAt > 0.25 then
        st.scanAt = now
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("Motor6D") then
                if not d.Enabled then d.Enabled = true end
            elseif d:IsA("BallSocketConstraint") then
                if d.Enabled and not ours then d.Enabled = false end
            elseif d:IsA("BasePart") then
                if d.Anchored then d.Anchored = false end
            elseif flag and (d:IsA("AlignPosition") or d:IsA("AlignOrientation")) then
                if d.Enabled then d.Enabled = false end
            elseif flag and d:IsA("BodyPosition") then
                d.MaxForce = Vector3.zero
            elseif flag and d:IsA("BodyGyro") then
                d.MaxTorque = Vector3.zero
            end
        end
    end
    -- some games switch the movement controls off during a stun: switch them back on (twice a second)
    if flag and now - st.controlsAt > 0.5 then
        st.controlsAt = now
        pcall(function()
            if not U.controls then
                local pm = lp:FindFirstChildOfClass("PlayerScripts") and lp.PlayerScripts:FindFirstChild("PlayerModule")
                U.controls = pm and require(pm):GetControls()
            end
            if U.controls then U.controls:Enable() end
        end)
    end
end)
end   -- anti stun

local function keyDown(key)
    return not UserInputService:GetFocusedTextBox() and UserInputService:IsKeyDown(key)
end

-- CFrame movement -----------------------------------------------------------------------------
-- Moves the character by editing its CFrame instead of WalkSpeed / velocity, so games that watch
-- WalkSpeed see nothing unusual. Every move is checked against walls first (Stop At Walls) because a
-- CFrame step, unlike physics, would otherwise pass straight through thin geometry.

toggle(cfSec, "CFrame Speed", "CfSpeed", false)
slider(cfSec, "Extra Speed", "CfSpeedValue", 0, 300, 30, { Suffix = " st/s" })
slider(cfSec, "Acceleration Time", "CfAccel", 0, 1, 0.1, { Decimals = 2, Suffix = " s" })
toggle(cfSec, "Only While Holding Key", "CfSpeedHold", false)
keybind(cfSec, "Speed Hold Key", "CfSpeedKey", nil)
slider(cfSec, "Sprint Multiplier", "CfSprint", 1, 5, 2, { Decimals = 1, Suffix = "x" })
keybind(cfSec, "Sprint Key", "CfSprintKey", nil)
toggle(cfSec, "Only On The Ground", "CfGroundOnly", false)
toggle(cfSec, "Stop At Walls", "CfWallCheck", true)

toggle(cfFlySec, "CFrame Fly", "CfFly", false)
slider(cfFlySec, "Fly Speed", "CfFlySpeed", 5, 500, 60, { Suffix = " st/s" })
slider(cfFlySec, "Vertical Multiplier", "CfFlyVert", 0.2, 3, 1, { Decimals = 1, Suffix = "x" })
toggle(cfFlySec, "Fly Toward Camera Pitch", "CfFlyPitch", true)
toggle(cfFlySec, "Face Fly Direction", "CfFlyFace", false)
local doDash   -- defined below, once the dash state exists; the key calls it through this upvalue
keybind(cfFlySec, "Dash Key", "CfDashKey", nil, function() if doDash then doDash() end end)
slider(cfFlySec, "Dash Distance", "CfDashDist", 5, 200, 40, { Suffix = " st" })
slider(cfFlySec, "Dash Time", "CfDashTime", 0.05, 1, 0.15, { Decimals = 2, Suffix = " s" })
slider(cfFlySec, "Dash Cooldown", "CfDashCd", 0, 5, 0.5, { Decimals = 1, Suffix = " s" })
toggle(cfFlySec, "Dash Toward Camera", "CfDashCamera", false)

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.RespectCanCollide = true
local function blocked(root, dir, dist)
    if not C.CfWallCheck or dir.Magnitude < 1e-3 then return false end
    wallParams.FilterDescendantsInstances = { lp.Character }
    return workspace:Raycast(root.Position, dir.Unit * (dist + 1.5), wallParams) ~= nil
end

local function smooth(cur, target, dt)
    local a = C.CfAccel <= 0.001 and 1 or (1 - math.exp(-dt / C.CfAccel))
    return cur:Lerp(target, a)
end

local walkVel, flyVel, flyPos, flyRoot = Vector3.zero, Vector3.zero, nil, nil
local dash = { left = 0, dir = Vector3.zero, cd = 0 }

doDash = function()
    local hum, root = myHumanoid()
    if not (hum and root) or hum.Health <= 0 or dash.cd > 0 then return end
    local dir = hum.MoveDirection
    if C.CfDashCamera then
        local look = cam().CFrame.LookVector
        dir = Vector3.new(look.X, 0, look.Z)
    elseif dir.Magnitude < 0.1 then
        local look = root.CFrame.LookVector
        dir = Vector3.new(look.X, 0, look.Z)
    end
    if dir.Magnitude < 0.01 then return end
    dash.dir, dash.left, dash.cd = dir.Unit, C.CfDashTime, C.CfDashCd + C.CfDashTime
end

renderLast(function(dt)
    if not U.Running or C.Freecam then return end
    dt = math.clamp(dt, 0, 0.1)
    local hum, root = myHumanoid()
    if not (hum and root) or hum.Health <= 0 then flyPos = nil return end
    dash.cd = math.max(0, dash.cd - dt)

    if dash.left > 0 then
        local step = math.min(dt, dash.left)
        dash.left -= step
        local move = dash.dir * (C.CfDashDist / C.CfDashTime) * step
        if not blocked(root, dash.dir, move.Magnitude) then
            root.CFrame += move
            if flyPos then flyPos += move end
        end
        local v = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)   -- do not fall while dashing
    end

    if C.CfFly then
        -- our own authoritative position: physics would otherwise sink us a little every frame
        if flyRoot ~= root or not flyPos or (root.Position - flyPos).Magnitude > 12 then
            flyPos, flyRoot, flyVel = root.Position, root, Vector3.zero
        end
        local dir = Vector3.zero
        if C.CfFlyPitch then
            local cf = cam().CFrame
            if keyDown(Enum.KeyCode.W) then dir += cf.LookVector end
            if keyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
            if keyDown(Enum.KeyCode.D) then dir += cf.RightVector end
            if keyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
        else
            dir = hum.MoveDirection
        end
        if keyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis * C.CfFlyVert end
        if keyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis * C.CfFlyVert end
        if dir.Magnitude > 1 then dir = dir.Unit end

        local speed = C.CfFlySpeed * ((BIND.CfSprintKey and BIND.CfSprintKey:IsDown()) and C.CfSprint or 1)
        flyVel = smooth(flyVel, dir * speed, dt)
        local step = flyVel * dt
        if blocked(root, flyVel, step.Magnitude) then flyVel, step = Vector3.zero, Vector3.zero end
        flyPos += step

        local flat = Vector3.new(dir.X, 0, dir.Z)
        if C.CfFlyFace and flat.Magnitude > 0.1 then
            root.CFrame = CFrame.lookAt(flyPos, flyPos + flat)
        else
            root.CFrame = CFrame.new(flyPos) * root.CFrame.Rotation
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return
    end
    flyPos = nil

    local plainSpeed = (C.SpeedEnabled and not C.CfSpeed) and math.max(C.SpeedValue - 16, 0) or 0   -- the Movement tab's Speed
    if C.CfSpeed or plainSpeed > 0 then
        local held = plainSpeed > 0 or not C.CfSpeedHold or (BIND.CfSpeedKey and BIND.CfSpeedKey:IsDown())
        local dir = hum.MoveDirection
        if not held or (C.CfGroundOnly and hum.FloorMaterial == Enum.Material.Air) then dir = Vector3.zero end
        local speed = plainSpeed > 0 and plainSpeed
            or C.CfSpeedValue * ((BIND.CfSprintKey and BIND.CfSprintKey:IsDown()) and C.CfSprint or 1)
        walkVel = smooth(walkVel, dir * speed, dt)
        if walkVel.Magnitude > 0.05 then
            local move = walkVel * dt
            if not blocked(root, walkVel, move.Magnitude) then root.CFrame += move end
        end
    else
        walkVel = Vector3.zero
    end
end)

Ready()
