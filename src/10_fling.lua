----------------------------------------------------------------------
-- tab: Fling (fling / fling all / void spam)
----------------------------------------------------------------------

-- Touch fling: we stick to the target's root part while spinning at absurd speed, so the physics
-- contact throws them. Velocity is only applied for the physics step and zeroed again on the next
-- render frame, so we never fly off ourselves. One job runs at a time (flingBusy); bumping
-- flingToken cancels it. Whitelisted players are always skipped.
do
local flingTab = win:Tab("Fling")
local flg = flingTab:Section("Fling")
local flgTune = flingTab:Section("Tuning", "right")
local vsp = flingTab:Section("Void Spam")

local flingToken, flingBusy = 0, false

local function stopFling() flingToken += 1 end
onUnload(stopFling)

local function isProtected(plr)
    return (C.ListRespectWhite and U.White[plr.Name]) or (C.FlingSkipTeam and sameTeam(plr))
end

-- our own body must not collide while we sit inside the target. The original CanCollide values are
-- remembered and put back afterwards: without that the parts stay non-solid and we fall through the map.
local savedCollide = setmetatable({}, { __mode = "k" })

local function restoreBody()
    for part, was in pairs(savedCollide) do
        if part.Parent then part.CanCollide = was end
        savedCollide[part] = nil
    end
end

-- status text above the crosshair: "<JOB> ACTIVE", or "<JOB> LOADING... 2.3s" while a delay runs
local jobName, jobStatus
local jobLabel = Instance.new("TextLabel")
jobLabel.Name = "JobStatus"
jobLabel.AnchorPoint = Vector2.new(0.5, 1)
jobLabel.BackgroundTransparency = 1
jobLabel.Size = UDim2.fromOffset(360, 22)
jobLabel.Font = Enum.Font.GothamBold
jobLabel.TextSize = 16
jobLabel.TextStrokeTransparency = 0.35
jobLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
jobLabel.Visible = false
jobLabel.Parent = overlay
onUnload(function() jobLabel:Destroy() end)

renderLast(function()
    local show = C.JobStatusText and U.Running and flingBusy and jobName ~= nil
    jobLabel.Visible = show
    if not show then return end
    local name = string.upper(jobName)
    if jobStatus then
        local dots = string.rep(".", 1 + math.floor(os.clock() * 3) % 3)
        jobLabel.Text = ("%s LOADING%s%s  %.1fs"):format(name, dots, string.rep(" ", 3 - #dots), math.max(jobStatus - os.clock(), 0))
    else
        jobLabel.Text = name .. " ACTIVE"
    end
    jobLabel.TextColor3 = C.RageStatusRainbow and Color3.fromHSV((os.clock() * 0.4) % 1, 0.9, 1)
        or C.RageStatusColor or Color3.fromRGB(255, 255, 255)
    local center = viewportCenter()
    jobLabel.Position = UDim2.fromOffset(center.X, center.Y - 8)
end)

-- waits `secs` (cancellable by Stop) while showing the loading text
local function loadingWait(secs)
    if secs <= 0 then return end
    local token = flingToken
    local untilAt = os.clock() + secs
    jobStatus = untilAt
    while flingToken == token and U.Running and os.clock() < untilAt do RunService.Heartbeat:Wait() end
    if jobStatus == untilAt then jobStatus = nil end
end

local function goHome(origin)
    -- solid again BEFORE we arrive, and lifted a little so we land on the floor instead of inside it
    restoreBody()
    for _ = 1, 3 do
        local hum, myRoot = myHumanoid()
        if myRoot then
            myRoot.AssemblyLinearVelocity = Vector3.zero
            myRoot.AssemblyAngularVelocity = Vector3.zero
            myRoot.CFrame = origin + Vector3.new(0, 2, 0)
        end
        if hum and cam() then cam().CameraSubject = hum end
        RunService.Heartbeat:Wait()
    end
end

connect(RunService.Stepped, function()
    if not (flingBusy and U.Running) then return end
    local _, _, char = myHumanoid()
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if savedCollide[part] == nil then savedCollide[part] = part.CanCollide end
            part.CanCollide = false
        end
    end
end)
onUnload(restoreBody)

-- One attempt on one player. Returns "done" (launched / in the void), "gone" (dead, respawning or
-- left), "timeout", "me" (we have no character) or "cancel".
-- below this height a player counts as "in the void" (kill line plus the Void Depth slider)
local function voidLine()
    local h = workspace.FallenPartsDestroyHeight
    if h ~= h then h = -500 end   -- some games set it to NaN, which makes every comparison false
    return math.max(h, -1000) + C.VoidDepth
end

-- maxTime / force are only given by Punch Fling (a short burst instead of the full Fling Time)
local function attack(target, void, token, maxTime, force)
    local _, _, root0 = charOf(target)
    if not root0 then return "gone" end
    local startPos, startAt = root0.Position, os.clock()
    local limit = maxTime or (void and C.VoidTime or C.FlingTime)

    while flingToken == token and U.Running do
        RunService.Heartbeat:Wait()
        local hum, myRoot = myHumanoid()
        local _, tHum, tRoot = charOf(target)
        if not (hum and myRoot) then return "me" end
        if not tRoot then return "gone" end

        if void then
            if tRoot.Position.Y < voidLine() then return "done" end
        elseif (tRoot.Position - startPos).Magnitude > 120 or tRoot.AssemblyLinearVelocity.Magnitude > 400 then
            return "done"
        end
        if os.clock() - startAt > limit then return "timeout" end

        if C.FlingCamera and not maxTime then cam().CameraSubject = tHum end   -- not for the short Punch burst

        -- lead a moving target a little, and wobble so the contact keeps changing
        local p = force or (void and C.VoidPower or C.FlingPower)
        local pos = tRoot.Position + tRoot.AssemblyLinearVelocity * 0.08 + Vector3.new(0, (math.random() - 0.5) * 2, 0)
        local dir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
        dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.xAxis
        local push = void and (dir * p * C.VoidSide + Vector3.new(0, -p * C.VoidDrop, 0))
            or Vector3.new(dir.X * p, p, dir.Z * p)

        myRoot.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(math.random(0, 359)), 0, math.rad(math.random(0, 359)))
        myRoot.AssemblyLinearVelocity = push
        myRoot.AssemblyAngularVelocity = Vector3.new(p, p, p)
        RunService.RenderStepped:Wait()
        myRoot = select(2, myHumanoid())
        if myRoot then
            myRoot.AssemblyLinearVelocity = Vector3.zero
            myRoot.AssemblyAngularVelocity = Vector3.zero
        end
    end
    return "cancel"
end

-- Runs body(token, origin) as the one active job, then puts us back where we started.
local function startJob(name, body)
    if flingBusy then
        notify(name, "Something is already running - press Stop first", "warn")
        return false
    end
    local _, myRoot = myHumanoid()
    if not myRoot then
        notify(name, "You need a character first", "warn")
        return false
    end
    flingToken += 1
    local token, origin = flingToken, myRoot.CFrame
    flingBusy, jobName, jobStatus = true, name, nil
    notify(name, "Active", "success", "toggle")
    task.spawn(function()
        local ok, err = pcall(body, token, origin)
        if not ok then notify(name, tostring(err), "error") end
        goHome(origin)
        flingBusy, jobName, jobStatus = false, nil, nil
        restoreBody()
        notify(name, "Stopped", nil, "toggle")
        -- a looping job that ended (error, cancelled, nobody left) must not leave its switch on
        for _, key in ipairs({ "VoidSpam", "FlingLoop" }) do
            if C[key] and TOG[key] then
                C[key] = false
                TOG[key]:Set(false, true)
            end
        end
    end)
    return true
end

local function selectedTarget(name)
    local target = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    if not target then
        notify(name, "Pick a player on the Player tab first", "warn")
    elseif isProtected(target) then
        notify(name, target.DisplayName .. " is protected (whitelist / team)", "warn")
        return nil
    end
    return target
end

local RESULT_TEXT = {
    done = "launched", gone = "not alive right now", timeout = "no luck (try more Power / Time)",
    me = "you have no character", cancel = "stopped",
}

-- fling ------------------------------------------------------------------

flg:Button({ Text = "Fling Selected Player", Callback = function()
    local target = selectedTarget("Fling")
    if not target then return end
    startJob("Fling", function(token, origin)
        local res = attack(target, false, token)
        notify("Fling", target.DisplayName .. ": " .. RESULT_TEXT[res], res == "done" and "success" or "warn")
    end)
end })

-- everyone we are allowed to hit, ordered by the current options. `mode` is one of
-- Selected / All / Nearest / Blacklist Only (Nearest keeps just the closest one).
local function targetList(mode)
    local list = {}
    if mode == "Selected" then
        local plr = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
        if plr and not isProtected(plr) then list[1] = plr end
        return list
    end

    local _, myRoot = myHumanoid()
    local myPos = myRoot and myRoot.Position or Vector3.zero
    local dist = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and not isProtected(plr) and (mode ~= "Blacklist Only" or U.Black[plr.Name]) then
            local _, _, root = charOf(plr)
            if root then
                dist[plr] = (root.Position - myPos).Magnitude
                table.insert(list, plr)
            end
        end
    end
    table.sort(list, function(a, b)
        if C.ListBlackFirst and U.Black[a.Name] ~= U.Black[b.Name] then return U.Black[a.Name] == true end
        return dist[a] < dist[b]
    end)
    if mode == "Nearest" and #list > 1 then list = { list[1] } end
    return list
end

-- one pass over everybody; returns launched, tried
local function flingPass(token, origin)
    local hit, tried = 0, 0
    for _, plr in ipairs(targetList("All")) do
        if flingToken ~= token or not U.Running then break end
        if charOf(plr) then
            tried += 1
            local res = attack(plr, false, token)
            if res == "done" then hit += 1 end
            if res ~= "cancel" then
                goHome(origin)
                loadingWait(C.FlingGap)
            end
        end
    end
    return hit, tried
end

flg:Button({ Text = "Fling All", Callback = function()
    startJob("Fling All", function(token, origin)
        local hit, tried = flingPass(token, origin)
        notify("Fling All", ("Launched %d of %d players"):format(hit, tried), hit > 0 and "success" or "warn")
    end)
end })

toggle(flg, "Loop Fling All", "FlingLoop", false, function(v)
    if not v then stopFling() return end
    if not startJob("Fling All", function(token, origin)
        while flingToken == token and U.Running do
            flingPass(token, origin)
            loadingWait(C.FlingLoopDelay)
        end
    end) then
        C.FlingLoop = false
        if TOG.FlingLoop then TOG.FlingLoop:Set(false, true) end
    end
end)
slider(flg, "Loop Pause", "FlingLoopDelay", 0.1, 30, 1, { Decimals = 1, Suffix = " s" })
slider(flg, "Next Player Delay", "FlingGap", 0, 30, 0.5, { Decimals = 1, Suffix = " s" })

flg:Button({ Text = "Stop", Callback = function() stopFling() end })

-- void spam ----------------------------------------------------------------
-- keeps sending players under the map. Each round it builds the target list again, so people who
-- respawn or join are picked up automatically; players already in the void are skipped.

local function voidJob(token, origin)
    local kills = 0
    while flingToken == token and U.Running do
        local list = targetList(C.VoidTargets)
        if #list == 0 then
            if C.VoidTargets == "Selected" and not (C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)) then
                notify("Void Spam", "Player left the server", "warn")
                break
            end
            task.wait(0.5)   -- nobody valid right now (dead / respawning): keep watching
        else
            for _, plr in ipairs(list) do
                if flingToken ~= token or not U.Running then break end
                local _, _, root = charOf(plr)
                if root and root.Position.Y >= voidLine() then
                    local res = attack(plr, true, token)
                    if res == "cancel" then return end
                    goHome(origin)   -- never wait around under the map
                    if res == "done" then
                        kills += 1
                        if C.VoidNotify then
                            notify("Void Spam", ("%s sent to the void (%d total)"):format(plr.DisplayName, kills), "success")
                        end
                        loadingWait(C.VoidGap)   -- back home, then wait before the next player
                    end
                end
            end
            loadingWait(C.VoidDelay)
        end
    end
end

toggle(vsp, "Void Spam", "VoidSpam", false, function(v)
    if not v then stopFling() return end
    local ok = true
    if C.VoidTargets == "Selected" then ok = selectedTarget("Void Spam") ~= nil end
    if ok then ok = startJob("Void Spam", voidJob) end
    if not ok then
        C.VoidSpam = false
        if TOG.VoidSpam then TOG.VoidSpam:Set(false, true) end
    end
end)
dropdown(vsp, "Targets", "VoidTargets", { "Selected", "All", "Nearest", "Blacklist Only" }, "Selected")
slider(vsp, "Next Player Delay", "VoidGap", 0, 30, 1, { Decimals = 1, Suffix = " s" })
slider(vsp, "Delay Between Rounds", "VoidDelay", 0, 30, 0.5, { Decimals = 1, Suffix = " s" })
toggle(vsp, "Show Status Text", "JobStatusText", true)
toggle(vsp, "Notify Each Kill", "VoidNotify", false)

;(function()  -- own function: the fling block is close to Lua's 200-locals limit
-- punch fling ---------------------------------------------------------------
-- A real punch animation (played on your own Animator, so everybody sees it) plus ONE short contact per
-- punch: when the fist lands we snap onto the player in front of us for a few frames with a directional
-- push, then go straight back to where we stood. No spinning, no flying around, and only players inside
-- Reach and in front of you are touched. Whitelisted players are skipped like everywhere else.
local pnch = flingTab:Section("Punch Fling")

-- Roblox's own tool swings (they load everywhere); the game's own animations are added by the scan buttons
-- The Strongest Battlegrounds: the four M1 hits of "Normal Punch" (R6, game animations, seen by everybody; checked)
local IN_TSB = game.PlaceId == 10449761463   -- The Strongest Battlegrounds (also its private servers)
local PUNCH_TSB = "Normal Punch (TSB)"
local PUNCH_TSB_MOVE = "Normal Punch Ability (TSB)"
local TSB_M1 = { 10469493270, 10469630950, 10469639222, 10469643643 }
local tsbIndex, tsbLastAt = 0, 0
local PUNCH_BUILTIN = {
    ["Hand Slam"] = { R15 = 243827693, R6 = 243827693 },   -- Roblox's own slam animation (0.75 s, checked)
    -- what the game plays when you use the Normal Punch move (hotbar slot 4), logged from a real use; 1.17 s
    [PUNCH_TSB_MOVE] = { R15 = 10468665991, R6 = 10468665991 },
    ["Lunge (thrust)"] = { R15 = 522638767, R6 = 129967478 },
    ["Slash (swing)"]  = { R15 = 522635514, R6 = 129967390 },
}
local PUNCH_NONE = "None (no animation)"
local PUNCH_COMBO = "Combo (cycles through all)"
local comboIndex = 0
local PUNCH_WORDS = { "punch", "m1", "attack", "hit", "strike", "combat", "melee", "swing", "slash", "jab", "hook", "fist", "kick", "uppercut" }
local gameAnims = {}   -- dropdown label -> animation id, found in the game

local function punchOptions()
    -- the two TSB animations are game-owned: they only exist in the list (and only work) inside TSB
    local list = {}
    if IN_TSB then
        table.insert(list, PUNCH_TSB_MOVE)
        table.insert(list, PUNCH_TSB)
    end
    for _, name in ipairs({ "Hand Slam", "Lunge (thrust)", "Slash (swing)", PUNCH_COMBO, PUNCH_NONE }) do table.insert(list, name) end
    local extra = {}
    for label in pairs(gameAnims) do table.insert(extra, label) end
    table.sort(extra)
    for _, label in ipairs(extra) do table.insert(list, label) end
    return list
end

local punchDD
local function scanGameAnims(all)
    table.clear(gameAnims)
    local roots = { game:GetService("ReplicatedStorage"), game:GetService("StarterPlayer"), game:GetService("StarterPack"),
        lp:FindFirstChildOfClass("Backpack"), lp.Character }
    local seen, count = {}, 0
    for _, root in ipairs(roots) do
        for _, d in ipairs(root:GetDescendants()) do
            local id = d:IsA("Animation") and d.AnimationId:match("%d+")
            if id and not seen[id] and count < 80 then
                local lname = d.Name:lower() .. " " .. (d.Parent and d.Parent.Name:lower() or "")
                local match = all
                if not match then
                    for _, word in ipairs(PUNCH_WORDS) do
                        if lname:find(word, 1, true) then match = true break end
                    end
                end
                if match then
                    seen[id] = true
                    count += 1
                    gameAnims[("Game: %s (%s)"):format(d.Name, d.Parent and d.Parent.Name or "?")] = id
                end
            end
        end
    end
    if punchDD then punchDD:SetOptions(punchOptions()) end
    notify("Punch Fling", ("Found %d game animations"):format(count), count > 0 and "success" or "warn", "misc")
end

local function playPunchAnim()
    local pick = C.PunchAnim
    if pick == PUNCH_NONE then return end
    if not IN_TSB and (pick == PUNCH_TSB or pick == PUNCH_TSB_MOVE) then pick = "Hand Slam" end   -- e.g. from a config saved in TSB
    if pick == PUNCH_COMBO then   -- every punch plays the next animation of the list
        local pool = {}
        for _, option in ipairs(punchOptions()) do
            if option ~= PUNCH_NONE and option ~= PUNCH_COMBO then table.insert(pool, option) end
        end
        comboIndex = comboIndex % #pool + 1
        pick = pool[comboIndex]
    end
    local hum = myHumanoid()
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not animator then return end
    local id = gameAnims[pick]
    local speed = pick == PUNCH_TSB_MOVE and 1 or 1.3
    if pick == PUNCH_TSB then   -- the four M1 hits of Normal Punch in a row; the chain restarts after a pause
        if os.clock() - tsbLastAt > 1.2 then tsbIndex = 0 end
        tsbIndex = tsbIndex % #TSB_M1 + 1
        tsbLastAt = os.clock()
        id, speed = TSB_M1[tsbIndex], 1
    end
    if not id then
        local set = PUNCH_BUILTIN[pick]
        id = set and set[hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"]
    end
    if not id then return end
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. tostring(id)
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    anim:Destroy()
    if not (ok and track) then return end
    track.Priority = Enum.AnimationPriority.Action4
    track.Looped = false
    track:Play(0.05, 1, speed)
    track.Stopped:Once(function() track:Destroy() end)
end

local function punchTarget()
    local _, myRoot = myHumanoid()
    if not myRoot then return end
    local best, bestDist
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and not isProtected(plr) then
            local _, _, root = charOf(plr)
            if root then
                local off = root.Position - myRoot.Position
                local d = off.Magnitude
                -- in front of us (a very close player counts from any side)
                if d <= C.PunchReach and (d < 3 or myRoot.CFrame.LookVector:Dot(off.Unit) > 0) and (not bestDist or d < bestDist) then
                    best, bestDist = plr, d
                end
            end
        end
    end
    return best
end

-- The "hidden fling" loop, verified on the alt in TSB (it launched them ~490 studs): for one physics step per frame
-- our root gets a velocity spike while we sit inside the target's torso, and it is put back to zero before the
-- next frame is drawn, so nothing flies away from us - but whoever we touch at that moment is thrown. The whole
-- thing lasts at most 0.8 s (it stops the moment they are launched) and then we are back where we stood.
-- Our body must stay solid for the contact, so this deliberately does NOT use the no-collide flingBusy mode.
local function hiddenBurst(target, token, origin)
    local startAt, movel, res = os.clock(), 0.1, "timeout"
    local _, _, t0 = charOf(target)
    if not t0 then return "gone" end
    local startPos = t0.Position
    local function myRootNow() return select(2, myHumanoid()) end
    while os.clock() - startAt < 0.8 and flingToken == token and U.Running do
        local tchar, _, tRoot = charOf(target)
        if not tRoot then res = "gone" break end
        if tRoot.AssemblyLinearVelocity.Magnitude > 250 or (tRoot.Position - startPos).Magnitude > 40 then res = "done" break end

        RunService.Heartbeat:Wait()
        local root = myRootNow()
        local torso = tchar and (tchar:FindFirstChild("Torso") or tchar:FindFirstChild("UpperTorso") or tRoot)
        if not (root and torso) then res = "me" break end
        root.CFrame = CFrame.new(torso.Position)
        root.AssemblyLinearVelocity = Vector3.new(0, C.PunchPower, 0)
        RunService.RenderStepped:Wait()
        root = myRootNow()
        if root then root.AssemblyLinearVelocity = Vector3.zero end
        RunService.Stepped:Wait()
        root = myRootNow()
        if root then root.AssemblyLinearVelocity = Vector3.new(0, movel, 0) end
        movel = -movel
    end
    if flingToken ~= token then res = "cancel" end
    goHome(origin)
    return res
end

local punching = false
local function punch(verbose)
    if punching or flingBusy or not U.Running then return end
    local _, myRoot = myHumanoid()
    if not myRoot then return end
    punching = true
    local origin, token = myRoot.CFrame, flingToken
    local target = C.PunchHit and punchTarget()
    if verbose and C.PunchHit and not target then
        notify("Punch Fling", ("Nobody in reach in front of you (Reach %d st)"):format(C.PunchReach), "warn")
    end
    playPunchAnim()
    task.spawn(function()
        task.wait(0.12)   -- the moment the fist lands
        if target and U.Running and flingToken == token then
            local res = hiddenBurst(target, token, origin)
            if verbose then
                notify("Punch Fling", target.DisplayName .. ": " .. (RESULT_TEXT[res] or res), res == "done" and "success" or "warn")
            end
        end
        task.wait(0.25)   -- short pause so holding the key cannot stack punches
        punching = false
    end)
end
onUnload(function() punching = false end)
U.Punch = punch   -- exposed for self-tests

toggle(pnch, "Punch Fling", "PunchOn", false)
keybind(pnch, "Punch Key", "BindPunch", nil, function() if C.PunchOn then punch() end end)
toggle(pnch, "Punch On Left Click", "PunchClick", false)
punchDD = dropdown(pnch, "Animation", "PunchAnim", punchOptions(), IN_TSB and PUNCH_TSB_MOVE or "Hand Slam")
pnch:Button({ Text = "Scan Game Animations", Callback = function() scanGameAnims(false) end })
pnch:Button({ Text = "Scan All Game Animations", Callback = function() scanGameAnims(true) end })
slider(pnch, "Reach", "PunchReach", 3, 25, 8, { Suffix = " st" })
slider(pnch, "Push Power", "PunchPower", 1000, 1000000, 10000)
toggle(pnch, "Fling On Hit", "PunchHit", true)
pnch:Button({ Text = "Punch Now (test)", Callback = function() punch(true) end })

connect(UserInputService.InputBegan, function(input, processed)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if processed or not (C.PunchOn and C.PunchClick and U.Running) or typing() or cursorOverMenu() then return end
    punch()
end)

end)()  -- punch fling

-- tuning -----------------------------------------------------------------

slider(flgTune, "Fling Power", "FlingPower", 10000, 1000000, 100000)
slider(flgTune, "Fling Time Per Player", "FlingTime", 1, 15, 5, { Decimals = 1, Suffix = " s" })
slider(flgTune, "Void Power", "VoidPower", 10000, 1000000, 100000)
slider(flgTune, "Void Time Per Player", "VoidTime", 1, 15, 6, { Decimals = 1, Suffix = " s" })
slider(flgTune, "Void Depth", "VoidDepth", 20, 400, 80, { Suffix = " st" })
slider(flgTune, "Downward Force", "VoidDrop", 0, 2, 1, { Decimals = 1, Suffix = "x" })
slider(flgTune, "Sideways Force", "VoidSide", 0, 2, 1, { Decimals = 1, Suffix = "x" })
toggle(flgTune, "Camera Follows Target", "FlingCamera", true)
toggle(flgTune, "Skip Teammates", "FlingSkipTeam", false)
end   -- fling

