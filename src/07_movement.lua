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

toggle(move, "Anti Stun", "AntiStun", false, function(v)
    local hum = myHumanoid()
    if not hum then return end
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not v)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not v)
    end)
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

-- speed / jump / anti stun locks (Last priority beats the game's own scripts) ---

local lastGoodSpeed, lastGoodJump, antiStunScan = 16, 50, 0
renderLast(function()
    if not U.Running then return end
    local hum, root = myHumanoid()
    if not hum then return end

    if hum.WalkSpeed > 0 then lastGoodSpeed = hum.WalkSpeed end
    if hum.JumpPower > 0 then lastGoodJump = hum.JumpPower end

    if C.AntiStun and not C.FlyEnabled and not C.SuperFly and not C.LayDown then
        if hum.PlatformStand then hum.PlatformStand = false end
        local state = hum:GetState()
        if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown
            or state == Enum.HumanoidStateType.Physics then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        if hum.WalkSpeed < 1 then hum.WalkSpeed = lastGoodSpeed end
        if hum.UseJumpPower and hum.JumpPower < 1 then hum.JumpPower = lastGoodJump end
        if root and root.Anchored then root.Anchored = false end

        -- ragdoll systems break the joints; re-enable them (scanned 4x a second, not every frame)
        if os.clock() - antiStunScan > 0.25 then
            antiStunScan = os.clock()
            local _, _, char = myHumanoid()
            if char then
                for _, d in ipairs(char:GetDescendants()) do
                    if d:IsA("Motor6D") and not d.Enabled then d.Enabled = true
                    elseif d:IsA("BallSocketConstraint") and d.Enabled then d.Enabled = false end
                end
            end
        end
    end
end)

