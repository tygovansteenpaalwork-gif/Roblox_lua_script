----------------------------------------------------------------------
-- tab: Defense (anti fling / anti void / anti aim)
----------------------------------------------------------------------

local defTab = win:Tab("Defense")
local aflSec = defTab:Section("Anti Fling")
local aaSec = defTab:Section("Anti Aim")
local avSec = defTab:Section("Anti Void", "right")
local dsSec = defTab:Section("Desync", "right")
local arSec = defTab:Section("Anti Ragdoll")

-- anti fling ------------------------------------------------------------
-- 1) other players' bodies stop colliding with ours, so nothing can physically shove us
-- 2) if our own velocity spikes past what we could produce ourselves, cancel it and step
--    back to where we were a moment ago

local collisionOriginal = setmetatable({}, { __mode = "k" })
local function restoreCollisions()
    for part, was in pairs(collisionOriginal) do
        if part.Parent then part.CanCollide = was end
        collisionOriginal[part] = nil
    end
end
onUnload(restoreCollisions)

toggle(aflSec, "Anti Fling", "AntiFling", false, function(v) if not v then restoreCollisions() end end)
toggle(aflSec, "No Player Collision", "AntiFlingNoCollide", true)
slider(aflSec, "Max Speed", "AntiFlingSpeed", 60, 600, 220, { Suffix = " st/s" })

connect(RunService.Stepped, function()
    if not (C.AntiFling and C.AntiFlingNoCollide and U.Running) then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr ~= lp and plr.Character
        if char then
            for _, part in ipairs(char:GetChildren()) do
                if part:IsA("BasePart") and part.CanCollide then
                    if collisionOriginal[part] == nil then collisionOriginal[part] = true end
                    part.CanCollide = false
                end
            end
        end
    end
end)

local safeCF, safeAt, lastFlingNote = nil, 0, 0
connect(RunService.Heartbeat, function()
    if not (C.AntiFling and U.Running) then safeCF = nil return end
    local hum, root = myHumanoid()
    if not (hum and root) then return end

    -- what we could legitimately be doing ourselves
    local allowed = C.AntiFlingSpeed
    if C.SpeedEnabled then allowed = math.max(allowed, C.SpeedValue * 1.6) end
    if C.FlyEnabled then allowed = math.max(allowed, C.FlySpeed * 1.6) end

    -- falling fast is normal, so only sideways speed and upward speed count
    local vel = root.AssemblyLinearVelocity
    local speed = math.max(Vector3.new(vel.X, 0, vel.Z).Magnitude, math.max(vel.Y, 0))
    if speed > allowed or root.AssemblyAngularVelocity.Magnitude > 80 then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        if safeCF and (root.Position - safeCF.Position).Magnitude > 6 then root.CFrame = safeCF end
        if os.clock() - lastFlingNote > 2 then
            lastFlingNote = os.clock()
            notify("Anti Fling", "Cancelled a sudden launch", "warn")
        end
    elseif os.clock() - safeAt > 0.15 then
        safeCF, safeAt = root.CFrame, os.clock()
    end
end)

-- anti ragdoll ------------------------------------------------------------
-- The Strongest Battlegrounds flags its states with Accessory instances on the character:
-- "Ragdoll" / "RagdollSim" = ragdolled (server sets PlatformStand + FallingDown), "Freeze" = hit
-- stun (WalkSpeed and JumpPower forced to 0). We own our own physics, so while a flag is present we
-- refuse the state changes every frame. Nothing is deleted, so the game's own scripts keep working;
-- the server still believes we are ragdolled, so moves it validates itself may still be blocked.

toggle(arSec, "Anti Ragdoll", "AntiRagdoll", false)
toggle(arSec, "Cancel Hit Stun", "AntiRagdollStun", false)

-- the routine is shared with Movement > Anti Stun: see "anti stun + anti ragdoll" at the bottom of the Movement tab

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

-- anti aim + desync ----------------------------------------------------------------
-- Other players see where the server says we are. Right after physics each frame we shift our
-- root by an offset, and at the very start of the next render frame we take exactly that shift
-- back out - so the network snapshot is off while your own screen never shows it.
--   Anti Aim = a random jitter / spin every frame (nothing to lock onto)
--   Desync   = a steady offset: they see you beside, behind or above where you really are, a
--              step behind your movement (Lag), or circling your real position (Orbit)
-- Both can be on together; their offsets are combined into one shift that is undone as one.

local aaApplied
local function undoAntiAim()
    if aaApplied then
        local _, root = myHumanoid()
        if root then root.CFrame = root.CFrame * aaApplied:Inverse() end
        aaApplied = nil
    end
end
onUnload(undoAntiAim)

toggle(aaSec, "Anti Aim", "AntiAim", false, function(v) if not v then undoAntiAim() end end)
dropdown(aaSec, "Mode", "AntiAimMode", { "Jitter", "Spin", "Jitter + Spin" }, "Jitter")
slider(aaSec, "Jitter Range", "AntiAimRange", 0.5, 10, 3, { Decimals = 1, Suffix = " st" })
slider(aaSec, "Spin Amount", "AntiAimSpin", 10, 120, 60, { Suffix = "°" })

local desyncAnchor      -- "Stay Here": the spot other players keep seeing you at
local lagHistory = {}    -- "Lag": recent real positions with timestamps

toggle(dsSec, "Desync", "Desync", false, function(v)
    if v then desyncAnchor, lagHistory = nil, {} else undoAntiAim() end
end)
dropdown(dsSec, "Mode", "DesyncMode", { "Stay Here", "Behind", "Left", "Right", "Above", "Lag", "Orbit" }, "Stay Here",
    function() desyncAnchor, lagHistory = nil, {} end)
dsSec:Button({ Text = "Set Anchor Here", Callback = function() desyncAnchor = nil end })
slider(dsSec, "Stay Radius", "DesyncStayRadius", 5, 300, 120, { Suffix = " st", MaxLabel = "Infinite" })
slider(dsSec, "Distance", "DesyncDist", 1, 25, 6, { Decimals = 1, Suffix = " st" })
slider(dsSec, "Lag Time", "DesyncLag", 0.05, 1.5, 0.3, { Decimals = 2, Suffix = "s" })
slider(dsSec, "Orbit Speed", "DesyncOrbit", 0.3, 6, 2, { Decimals = 1, Suffix = "/s" })

renderFirst(undoAntiAim)

local DESYNC_DIRS = {
    Behind = Vector3.new(0, 0, 1), Left = Vector3.new(-1, 0, 0),
    Right = Vector3.new(1, 0, 0), Above = Vector3.new(0, 1, 0),
}

-- The shift to apply, as a CFrame in the root's own space (+Z is behind the character).
-- Applying it moves the root to where other players should see it.
local function desyncShift(root)
    local mode = C.DesyncMode
    local dir = DESYNC_DIRS[mode]
    if dir then return CFrame.new(dir * C.DesyncDist) end

    if mode == "Stay Here" then
        -- others keep seeing you where the anchor was set while you walk around freely
        if not desyncAnchor then desyncAnchor = root.CFrame end
        -- gone too far: the anchor moves to you, so the ghost never ends up hundreds of studs away
        -- slider at its maximum (300) = infinite: never re-anchor
        if C.DesyncStayRadius < 300 and (root.Position - desyncAnchor.Position).Magnitude > C.DesyncStayRadius then desyncAnchor = root.CFrame end
        return root.CFrame:ToObjectSpace(desyncAnchor)
    end

    if mode == "Lag" then
        -- others see where you were `DesyncLag` seconds ago, read back from a history of your
        -- real positions (independent of how the game moves the character)
        local now = os.clock()
        table.insert(lagHistory, { t = now, pos = root.Position })
        local target = now - C.DesyncLag
        local keep = 1
        for i = 1, #lagHistory do
            if lagHistory[i].t <= target then keep = i else break end
        end
        for _ = 2, keep do table.remove(lagHistory, 1) end   -- drop what is older than the bracket
        local a, b = lagHistory[1], lagHistory[2]
        local goal
        if a.t >= target or not b then
            goal = a.pos                                      -- history not that long yet
        else
            goal = a.pos:Lerp(b.pos, math.clamp((target - a.t) / math.max(b.t - a.t, 1e-4), 0, 1))
        end
        return root.CFrame:ToObjectSpace(CFrame.new(goal) * root.CFrame.Rotation)
    end

    local a = os.clock() * C.DesyncOrbit * 2 * math.pi   -- Orbit
    return CFrame.new(Vector3.new(math.cos(a), 0, math.sin(a)) * C.DesyncDist)
end

connect(RunService.Heartbeat, function()
    if not ((C.AntiAim or C.Desync) and U.Running) then return end
    local _, root = myHumanoid()
    if not root then return end
    undoAntiAim()   -- a render step may have been skipped; never stack two shifts

    local total = CFrame.new()
    if C.Desync then
        local ds = desyncShift(root)
        total = total * ds
        U.GhostCF = root.CFrame * ds   -- where other players see the character (for the "copy" below)
    else
        U.GhostCF = nil
    end
    if C.AntiAim then
        local mode = C.AntiAimMode
        local offset, spin = Vector3.zero, 0
        if mode ~= "Spin" then
            offset = Vector3.new(math.random() * 2 - 1, (math.random() * 2 - 1) * 0.5, math.random() * 2 - 1) * C.AntiAimRange
        end
        if mode ~= "Jitter" then
            spin = math.rad(math.random(-180, 180)) * (C.AntiAimSpin / 120)
        end
        total = total * CFrame.new(offset) * CFrame.Angles(0, spin, 0)
    end

    aaApplied = total
    root.CFrame = root.CFrame * total
end)

-- desync copy -------------------------------------------------------------
-- A plain copy of your character (same looks, clothes, accessories) drawn where OTHER players see you (the desynced spot), so
-- you can check it on your own screen. It only exists on your client (parented to the camera) and
-- mirrors your live pose relative to the shifted root, so animations play on it exactly as others
-- see them.
do
local ghost, ghostChar, ghostPairs, ghostCount = nil, nil, {}, 0
toggle(dsSec, "Show Copy", "DesyncGhost", true)

-- The Humanoid and the joints stay: clothes, body colours and CharacterMesh limbs are only applied
-- to a model that still has a Humanoid, without it the copy would be bare grey/coloured blocks.
local JUNK = { "Script", "LocalScript", "ModuleScript", "Animator", "Sound", "BillboardGui", "SurfaceGui",
    "ParticleEmitter", "Beam", "Trail", "Light", "Tool", "ForceField", "Highlight" }

local function partPath(p, root)
    local names = {}
    while p and p ~= root do table.insert(names, 1, p.Name) p = p.Parent end
    return table.concat(names, "/")
end

local function destroyGhost()
    if ghost then ghost:Destroy() end
    ghost, ghostChar, ghostPairs, ghostCount = nil, nil, {}, 0
end
onUnload(destroyGhost)

local function countParts(char)
    local n = 0
    for _, d in ipairs(char:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
    return n
end

local function buildGhost(char)
    destroyGhost()
    local wasArchivable = char.Archivable
    char.Archivable = true
    local ok, copy = pcall(function() return char:Clone() end)
    char.Archivable = wasArchivable
    if not (ok and copy) then return end

    local byPath = {}
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then byPath[partPath(d, char)] = d end
    end
    local pairsList = {}
    for _, d in ipairs(copy:GetDescendants()) do
        if d:IsA("BasePart") then
            local orig = byPath[partPath(d, copy)]
            if orig then
                d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.Massless = true, false, false, false, true
                table.insert(pairsList, { o = orig, g = d })
            end
        end
    end
    for _, d in ipairs(copy:GetDescendants()) do
        for _, cls in ipairs(JUNK) do
            if d.Parent and d:IsA(cls) then d:Destroy() break end
        end
    end
    -- a joint that still points at a part OUTSIDE the copy (a cloned weld keeps its original target)
    -- would weld the anchored copy to your real character and freeze you: cut those
    for _, d in ipairs(copy:GetDescendants()) do
        if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
            local a, b = d.Part0, d.Part1
            if (a and not a:IsDescendantOf(copy)) or (b and not b:IsDescendantOf(copy)) then d:Destroy() end
        end
    end
    local cloneHum = copy:FindFirstChildOfClass("Humanoid")
    if cloneHum then
        cloneHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None   -- no name tag / health bar
        cloneHum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        cloneHum.RequiresNeck, cloneHum.BreakJointsOnDeath = false, false
        -- a live Humanoid keeps switching CanCollide back on for torso and limbs, and then the copy
        -- (standing where you were) blocks your real character. Freeze its state machine.
        cloneHum.EvaluateStateMachine = false
    end
    for i = #pairsList, 1, -1 do   -- parts that lived inside removed junk (e.g. a Tool's Handle) are gone
        if not pairsList[i].g:IsDescendantOf(copy) then table.remove(pairsList, i) end
    end
    copy.Name = "DesyncCopy"
    copy.Parent = workspace.CurrentCamera
    ghost, ghostChar, ghostPairs, ghostCount = copy, char, pairsList, countParts(char)
end

renderLast(function()
    if not (U.Running and C.Desync and C.DesyncGhost and U.GhostCF) then
        if ghost then destroyGhost() end
        return
    end
    local char, _, root = charOf(lp, true)
    if not char then destroyGhost() return end
    if char ~= ghostChar or not ghost or not ghost.Parent or countParts(char) ~= ghostCount then buildGhost(char) end
    if not ghost then return end

    local rel = root.CFrame:Inverse()
    for _, pr in ipairs(ghostPairs) do
        if pr.o.Parent then
            pr.g.CFrame = U.GhostCF * (rel * pr.o.CFrame)
            pr.g.CanCollide = false   -- belt and braces: the copy must never touch you
        end
    end
end)
end   -- desync copy block

