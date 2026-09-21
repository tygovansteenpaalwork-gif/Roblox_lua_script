--[[
    Punch Fling  -  punch_fling.lua
    A real punch animation plus one short fling per punch (TSB's Normal Punch inside TSB).

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/punch_fling.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "punch_fling", Title = "Punch Fling" })

local C, Players, Ready, RunService, U, UserInputService = ctx.C, ctx.Players, ctx.Ready, ctx.RunService, ctx.U, ctx.UserInputService
local cam, charOf, connect, cursorOverMenu, dropdown, keybind = ctx.cam, ctx.charOf, ctx.connect, ctx.cursorOverMenu, ctx.dropdown, ctx.keybind
local lp, myHumanoid, notify, onUnload, overlay, renderLast = ctx.lp, ctx.myHumanoid, ctx.notify, ctx.onUnload, ctx.overlay, ctx.renderLast
local sameTeam, slider, toggle, typing, viewportCenter, win = ctx.sameTeam, ctx.slider, ctx.toggle, ctx.typing, ctx.viewportCenter, ctx.win

local flingTab = win:Tab("Punch Fling")

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

local RESULT_TEXT = {
    done = "launched", gone = "not alive right now", timeout = "no luck (try more Power / Time)",
    me = "you have no character", cancel = "stopped",
}

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

Ready()
