----------------------------------------------------------------------
-- tab: FE (spin, headsit, FE animations, superman fly, custom skybox; telekinesis is added to it further down)
----------------------------------------------------------------------

-- FE = everything here moves / animates YOUR OWN character, which the server replicates, so other
-- players see it: spin (root CFrame), headsit (Humanoid.Sit + root CFrame), emotes and poses
-- (animation tracks on your own Animator). The skybox only exists on your own screen.
;(function()
local funTab = win:Tab("FE")
U.FeTab = funTab   -- telekinesis (further down) puts its section on this tab too
local spinSec = funTab:Section("Spin")
local sitSec = funTab:Section("Headsit", "right")
local animSec = funTab:Section("Animations")
local poseSec = funTab:Section("Poses", "right")
local skySec = funTab:Section("Custom Skybox")
local skyLook = funTab:Section("Sky Look", "right")

-- spin ------------------------------------------------------------------
local spinAuto
local function spinRestore()
    local hum = myHumanoid()
    if hum and spinAuto ~= nil then hum.AutoRotate = spinAuto end
    spinAuto = nil
end

toggle(spinSec, "Spin", "SpinOn", false, function(v) if not v then spinRestore() end end)
slider(spinSec, "Spin Speed", "SpinSpeed", 30, 3600, 720, { Suffix = "°/s" })
dropdown(spinSec, "Axis", "SpinAxis", { "Normal", "Flip (front)", "Roll (side)" }, "Normal")
dropdown(spinSec, "Direction", "SpinDir", { "Left", "Right" }, "Left")

connect(RunService.Heartbeat, function(dt)
    if not (C.SpinOn and U.Running) then return end
    local hum, root = myHumanoid()
    if not (hum and root) then return end
    if spinAuto == nil then spinAuto = hum.AutoRotate end
    hum.AutoRotate = false   -- otherwise the humanoid turns us back towards the walk direction
    local a = math.rad(C.SpinSpeed * dt) * (C.SpinDir == "Left" and 1 or -1)
    local rot = C.SpinAxis == "Flip (front)" and CFrame.Angles(a, 0, 0)
        or C.SpinAxis == "Roll (side)" and CFrame.Angles(0, 0, a)
        or CFrame.Angles(0, a, 0)
    root.CFrame = root.CFrame * rot
end)
onUnload(spinRestore)

-- headsit ---------------------------------------------------------------
-- We sit (Humanoid.Sit = true gives the real sit animation everybody sees) on top of somebody's head:
-- every frame our root is put just above their head and our body is made non-solid so we never push them.
local sitSaved

local function headsitTarget()
    if C.HeadSitTarget == "Selected Player" then
        return C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    end
    local _, myRoot = myHumanoid()
    if not myRoot then return end
    local best, bestDist
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then
            local _, _, root = charOf(plr)
            if root then
                local d = (root.Position - myRoot.Position).Magnitude
                if not bestDist or d < bestDist then best, bestDist = plr, d end
            end
        end
    end
    return best
end

local function headsitStop()
    if sitSaved then
        for part, was in pairs(sitSaved) do
            if part.Parent then part.CanCollide = was end
        end
        sitSaved = nil
    end
    local hum = myHumanoid()
    if hum then hum.Sit = false end
end

toggle(sitSec, "Headsit", "HeadSit", false, function(v)
    if not v then headsitStop() return end
    if not headsitTarget() then
        notify("Headsit", C.HeadSitTarget == "Selected Player" and "Pick a player on the Player tab first" or "Nobody to sit on", "warn")
        C.HeadSit = false
        if TOG.HeadSit then TOG.HeadSit:Set(false, true) end
    end
end)
dropdown(sitSec, "Target", "HeadSitTarget", { "Selected Player", "Nearest Player" }, "Selected Player")
slider(sitSec, "Height", "HeadSitHeight", -2, 4, 0, { Decimals = 1, Suffix = " st" })
toggle(sitSec, "Face Same Way As Target", "HeadSitFace", true)

connect(RunService.Heartbeat, function()
    if not (C.HeadSit and U.Running) then return end
    local hum, root, char = myHumanoid()
    if not (hum and root) then return end
    local plr = headsitTarget()
    local tchar, _, troot = nil, nil, nil
    if plr then tchar, _, troot = charOf(plr) end
    local head = tchar and tchar:FindFirstChild("Head")
    if not head then return end   -- target dead / respawning: we keep waiting

    sitSaved = sitSaved or setmetatable({}, { __mode = "k" })
    for _, part in ipairs(U.CharParts(char)) do
        if part.CanCollide then
            if sitSaved[part] == nil then sitSaved[part] = true end
            part.CanCollide = false
        end
    end
    hum.Sit = true
    local pos = head.Position + Vector3.new(0, head.Size.Y / 2 + 1.2 + C.HeadSitHeight, 0)
    local rot = C.HeadSitFace and troot.CFrame.Rotation or root.CFrame.Rotation
    root.CFrame = CFrame.new(pos) * rot
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end)
onUnload(headsitStop)

-- animations (FE) -------------------------------------------------------
-- Default Roblox emotes (checked: they load). Animation tracks played on your own Animator replicate.
local EMOTE_NAMES = { "Dance 1", "Dance 2", "Dance 3", "Wave", "Point", "Cheer", "Laugh", "Sit" }
local EMOTES = {
    R15 = { ["Dance 1"] = 507771019, ["Dance 2"] = 507776043, ["Dance 3"] = 507777268, Wave = 507770239,
            Point = 507770453, Cheer = 507770677, Laugh = 507770818, Sit = 2506281703 },
    R6  = { ["Dance 1"] = 182435998, ["Dance 2"] = 182436842, ["Dance 3"] = 182436935, Wave = 128777973,
            Point = 128853357, Cheer = 129423030, Laugh = 129423131 },
}

local curTrack
local function stopEmote()
    if curTrack then
        pcall(function() curTrack:Stop(0.2) curTrack:Destroy() end)
        curTrack = nil
    end
end

local function playAnim(id, label)
    local hum = myHumanoid()
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not animator then notify("Animations", "You need a character first", "warn") return end
    stopEmote()
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. tostring(id)
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    anim:Destroy()
    if not (ok and track) then notify("Animations", "Could not load " .. label, "error") return end
    track.Priority = Enum.AnimationPriority.Action4   -- above the walk / idle animations
    track.Looped = C.AnimLoop
    track:Play(0.15, 1, C.AnimFreeze and 0 or C.AnimSpeed)
    curTrack = track
    task.delay(2, function()
        if curTrack == track and track.Length == 0 then
            stopEmote()
            notify("Animations", label .. " does not work in this game", "warn")
        end
    end)
end

local function playEmote()
    local hum = myHumanoid()
    if not hum then notify("Animations", "You need a character first", "warn") return end
    local id = EMOTES[hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"][C.AnimEmote]
    if id then playAnim(id, C.AnimEmote)
    elseif C.AnimEmote == "Sit" then hum.Sit = true
    else notify("Animations", C.AnimEmote .. " does not exist for this rig", "warn") end
end

dropdown(animSec, "Emote", "AnimEmote", EMOTE_NAMES, "Dance 1")
animSec:Button({ Text = "Play Emote", Callback = playEmote })
animSec:Button({ Text = "Stop Animation", Callback = stopEmote })
slider(animSec, "Speed", "AnimSpeed", 0.1, 3, 1, { Decimals = 1, Suffix = "x", OnChange = function(v)
    if curTrack and not C.AnimFreeze then curTrack:AdjustSpeed(v) end
end })
toggle(animSec, "Loop", "AnimLoop", true, function(v) if curTrack then curTrack.Looped = v end end)
toggle(animSec, "Freeze Frame", "AnimFreeze", false, function(v)
    if curTrack then curTrack:AdjustSpeed(v and 0 or C.AnimSpeed) end
end)
toggle(animSec, "Stop When I Move", "AnimStopMove", true)
keybind(animSec, "Emote Key", "BindEmote", nil, playEmote)

local customId = ""
animSec:TextBox({ Text = "Animation ID", Placeholder = "e.g. 507771019", Flag = "AnimCustomId", NoSave = true,
    Callback = function(t) customId = t or "" end })
animSec:Button({ Text = "Play Animation ID", Callback = function()
    local id = tostring(customId):match("%d+")
    if not id then notify("Animations", "Type an animation ID first", "warn") return end
    playAnim(id, "animation " .. id)
end })

connect(RunService.Heartbeat, function()
    if not curTrack then return end
    if not curTrack.IsPlaying then curTrack = nil return end
    if C.AnimStopMove then
        local hum = myHumanoid()
        if hum and hum.MoveDirection.Magnitude > 0.1 then stopEmote() end
    end
end)
onUnload(stopEmote)

-- poses (FE) --------------------------------------------------------------
toggle(poseSec, "Sit Anywhere", "SitOn", false, function(v)
    if not v then local hum = myHumanoid() if hum then hum.Sit = false end end
end)
connect(RunService.Heartbeat, function()
    if not (C.SitOn and U.Running) then return end
    local hum = myHumanoid()
    if hum then hum.Sit = true end
end)

toggle(poseSec, "Lay Down", "LayDown", false, function(v)
    if not v then local hum = myHumanoid() if hum then hum.PlatformStand = false end end
end)
dropdown(poseSec, "Lay Position", "LayFace", { "Face Up", "Face Down" }, "Face Up")
connect(RunService.Heartbeat, function()
    if not (C.LayDown and U.Running) then return end
    local hum, root = myHumanoid()
    if not (hum and root) then return end
    hum.PlatformStand = true
    local look = root.CFrame.LookVector
    local yaw = math.atan2(-look.X, -look.Z)
    local tilt = math.rad(C.LayFace == "Face Up" and 90 or -90)
    root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, 0)
    root.AssemblyAngularVelocity = Vector3.zero
end)
poseSec:Button({ Text = "Stop All Animations", Callback = function()
    stopEmote()
    local hum = myHumanoid()
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do pcall(function() track:Stop(0.1) end) end
    end
end })

-- superman fly (FE) --------------------------------------------------------
-- Flies where the camera looks with real physics (the root's velocity, like the normal Fly), so walls and
-- floors stop you smoothly instead of rubber-banding. Moving = the Superman pose: body turned horizontal (head
-- first, belly down) with the default Roblox Cheer animation raising both arms. Standing still = Hover: upright,
-- floating with Roblox's Levitation idle animation and a slow bob. Everything is your own character (root
-- orientation + animation tracks), which the server replicates, so other players see it.
local superSec = funTab:Section("Superman Fly")
local superTracks = {}          -- "fly" / "hover" -> AnimationTrack
local superMode                 -- which of the two is showing
local superRot = CFrame.new()   -- smoothed orientation
local superVel = Vector3.zero
local superMovedAt = 0
local superSaved
local superReady = false   -- orientation state was taken from the character
-- Which animation gives the best "both arms forward" is MEASURED once per rig (R6 and R15 have different animations):
-- every candidate is scrubbed through its frames and the arm directions are compared with the direction of the head.
local FLY_CANDIDATES = {
    R15 = { 507770677, 507765000, 507765644, 10921294559, 10921293373, 10921137402 },   -- Cheer, Jump, Climb, Superhero Jump / Fall, Levitation Jump
    R6  = { 129423030, 125750702, 180436334, 128777973, 180436148 },                    -- Cheer, Jump, Climb, Wave, Fall
}
local HOVER_IDS = { R15 = 10921132962, R6 = 180436148 }   -- Levitation idle / the R6 fall pose
local poseCache = {}        -- "R6" / "R15" -> { id, hold, loops, score } or false when nothing worked
local poseBusy = false

local function superClearTracks()
    for name, track in pairs(superTracks) do
        pcall(function() track:Stop(0.2) track:Destroy() end)
        superTracks[name] = nil
    end
    superMode = nil
end

local function superStop()
    superClearTracks()
    superVel = Vector3.zero
    superReady = false
    if superSaved then
        for part, was in pairs(superSaved) do
            if part.Parent then part.CanCollide = was end
        end
        superSaved = nil
    end
    local hum, root = myHumanoid()
    if hum then hum.PlatformStand = false end
    if root then   -- stand up again, facing where the head was pointing
        local up = root.CFrame.UpVector
        local flat = Vector3.new(up.X, 0, up.Z)
        if flat.Magnitude < 0.1 then flat = Vector3.new(cam().CFrame.LookVector.X, 0, cam().CFrame.LookVector.Z) end
        if flat.Magnitude > 0.01 then root.CFrame = CFrame.lookAt(root.Position, root.Position + flat) end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

-- how far both arms point along the body's head direction (1 = straight up over the head), whatever way the body is turned
local function armAlignment(char)
    local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    local l = char:FindFirstChild("LeftUpperArm") or char:FindFirstChild("Left Arm")
    local r = char:FindFirstChild("RightUpperArm") or char:FindFirstChild("Right Arm")
    if not (torso and l and r) then return end
    local up = torso.CFrame.UpVector
    return math.min((-l.CFrame.UpVector):Dot(up), (-r.CFrame.UpVector):Dot(up))
end

local function calibratePose(hum)
    local rigKey = hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"
    local animator, char = hum:FindFirstChildOfClass("Animator"), hum.Parent
    if not animator then return end
    poseBusy = true
    notify("Superman Fly", "Finding the best arm pose for your character (a few seconds, once)", nil, "misc")
    local best
    for _, id in ipairs(FLY_CANDIDATES[rigKey]) do
        if not (C.SuperFly and U.Running) then poseBusy = false return end
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://" .. id
        local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
        anim:Destroy()
        if ok and track then
            local t0 = os.clock()
            while track.Length == 0 and os.clock() - t0 < 1.5 do task.wait() end
            local len = track.Length
            if len > 0 then
                track.Priority = Enum.AnimationPriority.Action4
                track.Looped = true
                track:Play(0, 1, 0)
                local bestS, bestT, minS = -2, 0, 2
                for i = 0, 16 do
                    local t = len * i / 16 * 0.999
                    track.TimePosition = t
                    RunService.RenderStepped:Wait()
                    RunService.Heartbeat:Wait()
                    local score = char.Parent and armAlignment(char)
                    if score then
                        if score > bestS then bestS, bestT = score, t end
                        minS = math.min(minS, score)
                    end
                end
                if not best or bestS > best.score then best = { id = id, hold = bestT, score = bestS, loops = minS >= 0.8 } end
            end
            pcall(function() track:Stop(0) track:Destroy() end)
        end
    end
    poseCache[rigKey] = best or false
    poseBusy = false
    if best then
        notify("Superman Fly", ("Arm pose found (%d%% straight)"):format(math.floor(best.score * 100)), "success", "misc")
    else
        notify("Superman Fly", "No arm pose worked for this character - you fly without one", "warn")
    end
end

-- crossfade to the pose for `mode`
local function superSetMode(hum, mode)
    if superMode == mode then
        local t = superTracks[mode]
        if t and t.IsPlaying then return end
    end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then return end
    local rigKey = hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"

    local id, freeze, holdAt
    if mode == "fly" then
        local pose = poseCache[rigKey]
        if pose == nil then
            if not poseBusy then task.spawn(calibratePose, hum) end
            return   -- flying already works, the pose follows in a moment
        end
        if not pose then superMode = mode return end
        id, holdAt = pose.id, pose.hold
        freeze = C.SuperFreeze and not pose.loops   -- a pose that keeps the arms up all the time needs no freezing
    else
        id = HOVER_IDS[rigKey]
    end
    if not id then superMode = mode return end

    local other = superTracks[mode == "fly" and "hover" or "fly"]
    if other then pcall(function() other:Stop(0.25) end) end
    local track = superTracks[mode]
    if not track then
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://" .. id
        local ok, loaded = pcall(function() return animator:LoadAnimation(anim) end)
        anim:Destroy()
        if not (ok and loaded) then return end
        loaded.Priority = Enum.AnimationPriority.Action4
        loaded.Looped = true
        track = loaded
        superTracks[mode] = track
    end
    track:Play(0.25, 1, freeze and 0 or 1)
    if freeze then track.TimePosition = holdAt end   -- stay in the moment where both arms point forward
    superMode = mode
end

U.SuperDebug = function() return { pose = poseCache, mode = superMode, busy = poseBusy } end   -- exposed for self-tests

toggle(superSec, "Superman Fly", "SuperFly", false, function(v)
    if not v then superStop() end
end)
slider(superSec, "Fly Speed", "SuperSpeed", 20, 400, 100)
toggle(superSec, "Hover When Standing Still", "SuperHover", true)
toggle(superSec, "Hold Arms Forward", "SuperFreeze", true, function()
    superClearTracks()   -- rebuilt on the next frame
end)
toggle(superSec, "Pass Through Walls", "SuperNoclip", false, function(v)
    if not v and superSaved then
        for part, was in pairs(superSaved) do
            if part.Parent then part.CanCollide = was end
        end
        superSaved = nil
    end
end)

connect(RunService.Heartbeat, function(dt)
    if not (C.SuperFly and U.Running) then return end
    local hum, root, char = myHumanoid()
    if not (hum and root) then return end
    hum.PlatformStand = true

    if not superReady then
        superReady = true
        superRot = root.CFrame.Rotation
    end

    if C.SuperNoclip then
        superSaved = superSaved or setmetatable({}, { __mode = "k" })
        for _, part in ipairs(U.CharParts(char)) do
            if part.CanCollide then
                if superSaved[part] == nil then superSaved[part] = true end
                part.CanCollide = false
            end
        end
    end

    local look = cam().CFrame
    local dir = Vector3.zero
    if not typing() then
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += look.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= look.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += look.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= look.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then dir += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then dir -= Vector3.yAxis end
    end
    local moving = dir.Magnitude > 0
    if moving then superMovedAt = os.clock() end
    local hovering = C.SuperHover and not moving and os.clock() - superMovedAt > 0.35

    local want = moving and dir.Unit * C.SuperSpeed or Vector3.zero
    if hovering then want = Vector3.new(0, math.sin(os.clock() * 2) * 1.2, 0) end   -- slow bob
    superVel = superVel:Lerp(want, 1 - 0.002 ^ math.min(dt, 0.1))   -- a short glide instead of a hard stop

    local target
    if hovering then
        -- upright, facing where the camera looks
        local flat = Vector3.new(look.LookVector.X, 0, look.LookVector.Z)
        target = CFrame.lookAt(Vector3.zero, flat.Magnitude > 0.01 and flat or Vector3.zAxis * -1)
    else
        -- head along the camera direction, belly towards the ground
        local head = look.LookVector
        local back = Vector3.yAxis - head * head.Y
        if back.Magnitude < 0.08 then back = look.UpVector - head * look.UpVector:Dot(head) end   -- looking straight up / down
        back = back.Unit
        target = CFrame.fromMatrix(Vector3.zero, head:Cross(back), head, back)
    end
    superRot = superRot:Lerp(target, math.clamp(dt * 8, 0, 1))
    -- no BodyVelocity / BodyGyro: velocity and orientation are set on the root itself every frame
    root.AssemblyLinearVelocity = superVel + Vector3.new(0, workspace.Gravity * math.min(dt, 0.1) * 0.5, 0)
    root.AssemblyAngularVelocity = Vector3.zero
    root.CFrame = CFrame.new(root.Position) * superRot

    superSetMode(hum, hovering and "hover" or "fly")
end)
onUnload(superStop)

-- custom skybox -----------------------------------------------------------
-- Either a picture (Roblox image id, a link, or a file in the executor's workspace folder) on all six
-- sides, or a sky we draw ourselves: the pictures are generated as PNG files (gradient + stars) and
-- loaded through getcustomasset. Only your own screen changes.
local SKY_DIR, SKY_SIZE = "TerkanSky", 256

local crcTable = {}
for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
        c = (c % 2 == 1) and bit32.bxor(0xEDB88320, bit32.rshift(c, 1)) or bit32.rshift(c, 1)
    end
    crcTable[i] = c
end
local function crc32(s)
    local c = 0xFFFFFFFF
    for i = 1, #s do c = bit32.bxor(crcTable[bit32.band(bit32.bxor(c, s:byte(i)), 0xFF)], bit32.rshift(c, 8)) end
    return bit32.bxor(c, 0xFFFFFFFF)
end
local function adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end
local function pngChunk(kind, data)
    return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", crc32(kind .. data))
end
-- raw = every row prefixed with filter byte 0; wrapped in "stored" (uncompressed) deflate blocks
local function encodePng(w, h, raw)
    local z, pos, n = { "\120\1" }, 1, #raw
    while pos <= n do
        local len = math.min(65535, n - pos + 1)
        z[#z + 1] = string.pack("<BI2I2", (pos + len > n) and 1 or 0, len, 65535 - len) .. raw:sub(pos, pos + len - 1)
        pos += len
    end
    z[#z + 1] = string.pack(">I4", adler32(raw))
    return "\137PNG\r\n\26\n" .. pngChunk("IHDR", string.pack(">I4I4BBBBB", w, h, 8, 2, 0, 0, 0))
        .. pngChunk("IDAT", table.concat(z)) .. pngChunk("IEND", "")
end

-- zenith / middle / horizon colour and how many stars
local SKY_PRESETS = {
    ["Sunset"]      = { Color3.fromRGB(30, 20, 80),  Color3.fromRGB(210, 80, 95),  Color3.fromRGB(255, 175, 80), 0.0004 },
    ["Neon Night"]  = { Color3.fromRGB(4, 0, 24),    Color3.fromRGB(70, 0, 120),   Color3.fromRGB(255, 0, 170),  0.0020 },
    ["Aurora"]      = { Color3.fromRGB(0, 8, 28),    Color3.fromRGB(0, 100, 90),   Color3.fromRGB(70, 220, 130), 0.0025 },
    ["Blood Moon"]  = { Color3.fromRGB(8, 0, 0),     Color3.fromRGB(90, 0, 10),    Color3.fromRGB(210, 35, 20),  0.0015 },
    ["Deep Space"]  = { Color3.fromRGB(0, 0, 6),     Color3.fromRGB(8, 6, 34),     Color3.fromRGB(28, 12, 60),   0.0060 },
    ["Pastel Dawn"] = { Color3.fromRGB(120, 150, 230), Color3.fromRGB(235, 170, 215), Color3.fromRGB(255, 225, 185), 0 },
    ["Ocean Blue"]  = { Color3.fromRGB(10, 60, 160), Color3.fromRGB(60, 150, 230), Color3.fromRGB(190, 235, 255), 0 },
}
local SKY_PRESET_NAMES = { "Sunset", "Neon Night", "Aurora", "Blood Moon", "Deep Space", "Pastel Dawn", "Ocean Blue" }

local function makeFace(kind, preset, seed)
    local zenith, mid, horizon, density = preset[1], preset[2], preset[3], preset[4]
    local S = SKY_SIZE
    local rnd = Random.new(seed)
    local stars = {}
    for _ = 1, math.floor(S * S * density) do stars[rnd:NextInteger(0, S * S - 1)] = rnd:NextNumber(0.45, 1) end

    local rows = {}
    for y = 0, S - 1 do
        local t = y / (S - 1)          -- 0 = top of the picture, 1 = bottom
        local base
        if kind == "up" then base = zenith
        elseif kind == "down" then base = horizon:Lerp(Color3.new(0, 0, 0), 0.5)
        elseif t < 0.6 then base = zenith:Lerp(mid, t / 0.6)
        else base = mid:Lerp(horizon, (t - 0.6) / 0.4) end
        local fade = kind == "side" and math.clamp(1 - t * 1.4, 0, 1) or 1   -- no stars near the horizon
        local buf = { "\0" }
        for x = 0, S - 1 do
            local col = base
            local b = stars[y * S + x]
            if b then col = base:Lerp(Color3.new(1, 1, 1), b * fade) end
            buf[#buf + 1] = string.char(math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5))
        end
        rows[#rows + 1] = table.concat(buf)
    end
    return encodePng(S, S, table.concat(rows))
end

-- Sky property -> how that face of the cube is drawn
local FACES = {
    { "SkyboxBk", "side", 11 }, { "SkyboxFt", "side", 22 }, { "SkyboxLf", "side", 33 },
    { "SkyboxRt", "side", 44 }, { "SkyboxUp", "up", 55 },   { "SkyboxDn", "down", 66 },
}

local presetAssets = {}
local function presetSky(name)
    if presetAssets[name] then return presetAssets[name] end
    if not isfolder(SKY_DIR) then makefolder(SKY_DIR) end
    local out = {}
    for _, face in ipairs(FACES) do
        local path = ("%s/%s_%s_v1.png"):format(SKY_DIR, name:gsub("%s", ""), face[1])
        if not isfile(path) then
            writefile(path, makeFace(face[2], SKY_PRESETS[name], face[3]))
            task.wait()   -- generating is heavy: one picture per frame, so the game does not freeze
        end
        out[face[1]] = getcustomasset(path)
    end
    presetAssets[name] = out
    return out
end

-- a Roblox image id, a link or a file name  ->  something a Sky can show (all six sides)
local function imageSky(source)
    source = (source or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if source == "" then return nil, "Type an image id, link or file name first" end
    local url = source:match("^https?://.+")
    local id = source:match("^rbxassetid://(%d+)$") or source:match("^(%d+)$")
        or (source:find("roblox.com", 1, true) and source:match("[?&]id=(%d+)"))
    local asset
    if id then
        asset = "rbxassetid://" .. id
    elseif url then
        local ok, res = pcall(request, { Url = url, Method = "GET" })
        if not (ok and res and res.Success and res.Body and #res.Body > 0) then
            return nil, "Could not download that link"
        end
        if not isfolder(SKY_DIR) then makefolder(SKY_DIR) end
        local ext = url:match("%.(%a%a%a%a?)[%?#]?[^/]*$")
        ext = (ext == "jpg" or ext == "jpeg" or ext == "png") and ext or "png"
        local path = SKY_DIR .. "/custom." .. ext
        writefile(path, res.Body)
        asset = getcustomasset(path)
    elseif isfile(source) then
        asset = getcustomasset(source)
    elseif isfile(SKY_DIR .. "/" .. source) then
        asset = getcustomasset(SKY_DIR .. "/" .. source)
    else
        return nil, "Not an image id, link or file in your executor workspace"
    end
    local out = {}
    for _, face in ipairs(FACES) do out[face[1]] = asset end
    return out
end

local skyObj, hiddenSkies = nil, {}
local skyGen = 0
local skyImageText = ""

local function hideGameSkies()
    for _, s in ipairs(Lighting:GetChildren()) do
        if s:IsA("Sky") and s ~= skyObj then
            hiddenSkies[s] = true
            s.Parent = nil
        end
    end
end

local function skyOff()
    skyGen += 1
    if skyObj then skyObj:Destroy() skyObj = nil end
    for s in pairs(hiddenSkies) do
        s.Parent = Lighting
        hiddenSkies[s] = nil
    end
end

local function skyOn()
    skyGen += 1
    local gen = skyGen
    task.spawn(function()
        local textures, err
        local ok, res, msg = pcall(function()
            if C.SkySource == "Image" then return imageSky(skyImageText) end
            return presetSky(C.SkyPreset)
        end)
        if ok then textures, err = res, msg else err = tostring(res) end
        if gen ~= skyGen or not C.SkyOn then return end   -- switched off / changed while loading
        if not textures then
            notify("Skybox", err or "Could not build the sky", "error")
            C.SkyOn = false
            if TOG.SkyOn then TOG.SkyOn:Set(false, true) end
            return
        end
        if not skyObj then
            skyObj = Instance.new("Sky")
            skyObj.Name = U.rname()
        end
        skyObj.StarCount = 0
        for prop, asset in pairs(textures) do skyObj[prop] = asset end
        skyObj.CelestialBodiesShown = C.SkySun
        hideGameSkies()
        skyObj.Parent = Lighting
    end)
end

toggle(skySec, "Custom Skybox", "SkyOn", false, function(v)
    if v then skyOn() else skyOff() end
end)
dropdown(skySec, "Source", "SkySource", { "Preset", "Image" }, "Preset", function()
    if C.SkyOn then skyOn() end
end)
dropdown(skySec, "Preset", "SkyPreset", SKY_PRESET_NAMES, "Neon Night", function()
    if C.SkyOn and C.SkySource == "Preset" then skyOn() end
end)
skySec:TextBox({ Text = "Image (id / link / file)", Placeholder = "rbxassetid://123 or https://... or mysky.png",
    Flag = "SkyImage", NoSave = true, Callback = function(t) skyImageText = t or "" end })
skySec:Button({ Text = "Use This Image", Callback = function()
    C.SkySource = "Image"
    C.SkyOn = true
    if TOG.SkyOn then TOG.SkyOn:Set(true, true) end
    skyOn()
end })

toggle(skyLook, "Show Sun & Moon", "SkySun", true, function(v)
    if skyObj then skyObj.CelestialBodiesShown = v end
end)
slider(skyLook, "Rotate Sky", "SkySpin", 0, 30, 0, { Decimals = 1, Suffix = "°/s" })

local skySlow, skyAngle = 0, 0
renderLast(function(dt)
    if not (C.SkyOn and U.Running and skyObj) then return end
    skyAngle = (skyAngle + C.SkySpin * dt) % 360
    skyObj.SkyboxOrientation = Vector3.new(0, skyAngle, 0)
    skySlow += dt
    if skySlow < 0.5 then return end
    skySlow = 0
    -- games put their own sky back now and then; ours stays the one that shows
    if skyObj.Parent ~= Lighting then skyObj.Parent = Lighting end
    hideGameSkies()
end)
onUnload(skyOff)
end)()

