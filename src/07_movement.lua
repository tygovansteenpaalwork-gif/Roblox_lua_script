----------------------------------------------------------------------
-- tab: Movement
----------------------------------------------------------------------

local moveTab = win:Tab("Movement")
local move = moveTab:Section("Speed & Jump")
local fly = moveTab:Section("Flight & Collision", "right")

-- Looked up ONCE per frame instead of once per feature per frame (every Movement/Defense/Fling/FE/Misc
-- feature that touches our own character calls this, same idea as U.Others() for other players).
local meHum, meRoot, meChar, meFrame, meTime = nil, nil, nil, -1, 0
local function myHumanoid()
    local now = os.clock()
    if meFrame == U.Frame and now - meTime < 0.1 then return meHum, meRoot, meChar end
    local c = lp.Character
    meHum, meRoot, meChar = c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart"), c
    meFrame, meTime = U.Frame, now
    return meHum, meRoot, meChar
end

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

-- fly ------------------------------------------------------------------

-- Flying is done by setting the root's velocity every frame (no BodyVelocity / BodyGyro objects inside the character,
-- which is the first thing an anti-fly check looks for). Gravity is cancelled by adding half a frame of it back.
local flyState = { vel = Vector3.zero }
local function stopFly()
    flyState.vel = Vector3.zero
    local hum = myHumanoid()
    if hum then hum.PlatformStand = false end
end

toggle(fly, "Fly", "FlyEnabled", false, function(v) if not v then stopFly() end end)
slider(fly, "Fly Speed", "FlySpeed", 10, 300, 70)
slider(fly, "Vertical Speed", "FlyVertical", 0.2, 2, 1, { Decimals = 2, Suffix = "x" })
slider(fly, "Fly Smoothing", "FlySmooth", 0, 95, 0, { Suffix = "%" })

local function typing() return UserInputService:GetFocusedTextBox() ~= nil end

renderLast(function(dt)
    if not (C.FlyEnabled and U.Running) then return end
    local hum, root = myHumanoid()
    if not hum or not root then return end

    hum.PlatformStand = true

    local look = cam().CFrame
    local dir = Vector3.zero
    if not typing() then
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += look.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= look.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += look.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= look.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then dir += Vector3.yAxis * C.FlyVertical end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then dir -= Vector3.yAxis * C.FlyVertical end
    end
    local want = dir.Magnitude > 0 and dir.Unit * C.FlySpeed or Vector3.zero
    if C.FlySmooth > 0 then
        -- frame-rate independent glide: 0% = instant, 95% = very floaty
        want = flyState.vel:Lerp(want, 1 - (C.FlySmooth / 100) ^ (math.min(dt, 0.1) * 60))
    end
    flyState.vel = want
    root.AssemblyLinearVelocity = want + Vector3.new(0, workspace.Gravity * math.min(dt, 0.1) * 0.5, 0)
    root.AssemblyAngularVelocity = Vector3.zero
    local flat = Vector3.new(look.LookVector.X, 0, look.LookVector.Z)
    if flat.Magnitude > 0.01 then root.CFrame = CFrame.lookAt(root.Position, root.Position + flat) end
end)
onUnload(stopFly)

-- noclip -----------------------------------------------------------------

local noclipOriginal = setmetatable({}, { __mode = "k" })   -- weak: parts of old characters are forgotten
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
    for _, part in ipairs(U.CharParts(char)) do
        if part.CanCollide then
            if noclipOriginal[part] == nil then noclipOriginal[part] = true end
            part.CanCollide = false
        end
    end
end
connect(RunService.Stepped, applyNoclip)

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
