--[[
    Superman Fly  -  superman_fly.lua
    Fly like Superman (R6 and R15, the arm pose is measured) with a hover pose; others see it.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/superman_fly.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "superman_fly", Title = "Superman Fly" })

local C, Ready, RunService, U, UserInputService, cam = ctx.C, ctx.Ready, ctx.RunService, ctx.U, ctx.UserInputService, ctx.cam
local connect, myHumanoid, notify, onUnload, slider, toggle = ctx.connect, ctx.myHumanoid, ctx.notify, ctx.onUnload, ctx.slider, ctx.toggle
local typing, win = ctx.typing, ctx.win

local funTab = win:Tab("Superman Fly")

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
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
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

Ready()
