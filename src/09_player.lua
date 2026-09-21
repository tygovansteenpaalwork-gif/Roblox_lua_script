----------------------------------------------------------------------
-- tab: Player
----------------------------------------------------------------------

local playerTab = win:Tab("Player")
local tp = playerTab:Section("Teleport & Spectate")
local misc1 = playerTab:Section("Utility", "right")

local function playerNames()
    local names = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then table.insert(names, plr.Name) end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

local renderInventory   -- assigned by the Inventory section below
local playerDD = tp:Dropdown({ Text = "Player", Options = playerNames(), Flag = "SelectedPlayer", NoSave = true,
    Callback = function(v)
        C.SelectedPlayer = v
        if renderInventory then renderInventory() end
    end })
local orbitDD   -- assigned by the Orbit section below
local function refreshPlayers()
    playerDD:SetOptions(playerNames())
    if orbitDD then orbitDD:SetOptions(playerNames()) end
end
connect(Players.PlayerAdded, refreshPlayers)
connect(Players.PlayerRemoving, function() task.defer(refreshPlayers) end)

tp:Button({ Text = "Teleport To Player", Callback = function()
    local target = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    local root
    if target then
        local _, _, r = charOf(target)   -- (multi-return: never use `a and f()` here)
        root = r
    end
    local _, myRoot = myHumanoid()
    if root and myRoot then
        myRoot.CFrame = root.CFrame * CFrame.new(0, 0, 3)
    else
        notify("Teleport", "Pick a player that is alive first", "warn")
    end
end })

toggle(tp, "Spectate Player", "Spectate", false, function(v)
    if not v then
        local hum = myHumanoid()
        if hum then cam().CameraSubject = hum end
    end
end)
renderLast(function()
    if not (C.Spectate and U.Running) then return end
    local target = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    if not target then return end
    local _, hum = charOf(target)
    if hum then cam().CameraSubject = hum end
end)

toggle(tp, "Click Teleport (hold key)", "ClickTp", false)
keybind(tp, "Click TP Key", "ClickTpKey", Enum.KeyCode.LeftControl)
connect(UserInputService.InputBegan, function(input, gp)
    if gp or not C.ClickTp or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if not (BIND.ClickTpKey and BIND.ClickTpKey:IsDown()) then return end
    local pos = UserInputService:GetMouseLocation()
    local ray = cam():ViewportPointToRay(pos.X, pos.Y)
    rayParams.FilterDescendantsInstances = { lp.Character }
    local res = workspace:Raycast(ray.Origin, ray.Direction * 2000, rayParams)
    local _, root = myHumanoid()
    if res and root then root.CFrame = CFrame.new(res.Position + Vector3.new(0, 4, 0)) end
end)

-- follow ---------------------------------------------------------------

local follow = playerTab:Section("Follow Player")
local followAutoAt = 0   -- when the Auto Distance glide started, so it always begins at the far end

-- follow and orbit both drive our position, so only one may be on at a time
toggle(follow, "Follow Selected Player", "FollowEnabled", false, function(v)
    if v then followAutoAt = os.clock() end
    if v and C.OrbitEnabled and TOG.OrbitEnabled then
        C.OrbitEnabled = false
        TOG.OrbitEnabled:Set(false, true)
    end
end)
slider(follow, "Distance Behind", "FollowDist", 0, 30, 5, { Decimals = 1, Suffix = " st" })
slider(follow, "Height", "FollowHeight", -5, 15, 0, { Decimals = 1, Suffix = " st" })
toggle(follow, "Face Their Back", "FollowFace", true)
toggle(follow, "Auto Distance", "FollowAuto", false, function(v) if v then followAutoAt = os.clock() end end)
slider(follow, "Auto Far", "FollowAutoFar", 0, 30, 5, { Decimals = 1, Suffix = " st" })
slider(follow, "Auto Near", "FollowAutoNear", 0, 30, 0, { Decimals = 1, Suffix = " st" })
slider(follow, "Auto Speed", "FollowAutoSpeed", 0.1, 4, 0.6, { Decimals = 2, Suffix = "/s" })

-- Auto Distance glides far -> near -> far continuously: a cosine, so the speed eases to zero
-- at both ends and there is never a jump or a sudden stop.
local function followDistance()
    if not C.FollowAuto then return C.FollowDist end
    local far = math.max(C.FollowAutoFar, C.FollowAutoNear)
    local near = math.min(C.FollowAutoFar, C.FollowAutoNear)
    -- measured from the moment it was switched on: cos(0) = 1, so it starts at the far end
    -- (no jump) and then glides toward the near end and back
    local wave = 0.5 + 0.5 * math.cos((os.clock() - followAutoAt) * C.FollowAutoSpeed * 2 * math.pi)
    return near + (far - near) * wave
end

renderLast(function()
    if not (C.FollowEnabled and U.Running) then return end
    local target = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    if not target then return end
    local _, _, targetRoot = charOf(target)
    local _, myRoot = myHumanoid()
    if not (targetRoot and myRoot) then return end

    local base = targetRoot.CFrame
    -- +Z is behind a character (its LookVector is -Z)
    local pos = base:PointToWorldSpace(Vector3.new(0, C.FollowHeight, followDistance()))
    local toward = Vector3.new(base.Position.X - pos.X, 0, base.Position.Z - pos.Z)
    if C.FollowFace and toward.Magnitude > 0.05 then
        myRoot.CFrame = CFrame.lookAt(pos, pos + toward)
    else
        myRoot.CFrame = CFrame.new(pos) * base.Rotation
    end
    myRoot.AssemblyLinearVelocity = Vector3.zero
end)

-- orbit ------------------------------------------------------------------

local orbit = playerTab:Section("Orbit Player")
orbitDD = orbit:Dropdown({ Text = "Orbit Player", Options = playerNames(), Flag = "OrbitPlayer", NoSave = true,
    Callback = function(v) C.OrbitPlayer = v end })
toggle(orbit, "Orbit", "OrbitEnabled", false, function(v)
    if v and C.FollowEnabled and TOG.FollowEnabled then
        C.FollowEnabled = false
        TOG.FollowEnabled:Set(false, true)
    end
end)
toggle(orbit, "Lock On Target", "OrbitLock", true)
dropdown(orbit, "Orbit Mode", "OrbitMode", { "Circle", "Bobbing", "Figure Eight" }, "Circle")
slider(orbit, "Height", "OrbitHeight", -10, 30, 3, { Decimals = 1, Suffix = " st" })
slider(orbit, "Distance", "OrbitDist", 1, 40, 8, { Decimals = 1, Suffix = " st" })
slider(orbit, "Rotation Speed", "OrbitSpeed", 10, 720, 120, { Suffix = "°/s" })
toggle(orbit, "Reverse Direction", "OrbitReverse", false)

local orbitAngle = 0
renderLast(function(dt)
    if not (C.OrbitEnabled and U.Running) then return end
    local target = C.OrbitPlayer and Players:FindFirstChild(C.OrbitPlayer)
    if not target then return end
    local _, _, targetRoot = charOf(target)
    local _, myRoot = myHumanoid()
    if not (targetRoot and myRoot) then return end

    orbitAngle += math.rad(C.OrbitSpeed) * math.clamp(dt, 0, 0.1) * (C.OrbitReverse and -1 or 1)
    local r, h, a = C.OrbitDist, C.OrbitHeight, orbitAngle
    local offset
    if C.OrbitMode == "Bobbing" then
        offset = Vector3.new(math.cos(a) * r, h + math.sin(a * 2) * math.min(r * 0.4, 4), math.sin(a) * r)
    elseif C.OrbitMode == "Figure Eight" then
        offset = Vector3.new(math.cos(a) * r, h, math.sin(a * 2) * r * 0.6)
    else
        offset = Vector3.new(math.cos(a) * r, h, math.sin(a) * r)
    end

    local center = targetRoot.Position
    local pos = center + offset
    if C.OrbitLock then
        -- the character faces the target and the camera stays locked onto them
        myRoot.CFrame = CFrame.lookAt(pos, center)
        local c = cam()
        c.CFrame = CFrame.lookAt(c.CFrame.Position, center)
    else
        myRoot.CFrame = CFrame.new(pos) * myRoot.CFrame.Rotation
    end
    myRoot.AssemblyLinearVelocity = Vector3.zero
end)

-- no animations ----------------------------------------------------------
-- We own our character's Animator, and animation playback replicates from the owner to the server,
-- so stopping our own tracks is what other players see too (a track stopped in the same frame it
-- started never gets sent). The game's own scripts keep playing them, so it is redone every frame.
do
local animSec = playerTab:Section("Animations", "right")

local function setAnimateScript(disabled)
    local char = lp.Character
    local script = char and char:FindFirstChild("Animate")
    if script and script:IsA("LocalScript") then script.Disabled = disabled end
end

toggle(animSec, "No Animations", "NoAnim", false, function(v)
    if v then return end
    setAnimateScript(false)
    -- frozen tracks would stay frozen; stop them so the game restarts fresh ones
    local hum = myHumanoid()
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            if track.Speed == 0 then track:Stop(0) end
        end
    end
end)
dropdown(animSec, "Mode", "NoAnimMode", { "Stop All", "Stop Attacks Only", "Freeze Pose" }, "Stop All")
toggle(animSec, "Disable Animate Script (Stop All)", "NoAnimScript", true)
onUnload(function() setAnimateScript(false) end)

local function suppress(track)
    local mode = C.NoAnimMode
    if mode == "Freeze Pose" then
        if track.Speed ~= 0 then track:AdjustSpeed(0) end
    elseif mode == "Stop Attacks Only" then
        -- Action priorities are what games use for moves; movement / idle / core are left alone
        local pv = track.Priority.Value
        if pv >= Enum.AnimationPriority.Action.Value and pv < Enum.AnimationPriority.Core.Value then track:Stop(0) end
    else
        track:Stop(0)
    end
end

-- A track is stopped the moment it starts (AnimationPlayed), and everything still playing is swept at
-- the start of the frame, after the game's own render code, after physics and right before the frame
-- is sent to the server - a single sweep per frame let some tracks slip through for a frame.
local hooked, hookConn
local function sweep()
    if not (C.NoAnim and U.Running) then return end
    local hum = myHumanoid()
    if not hum then return end
    if C.NoAnimMode == "Stop All" and C.NoAnimScript then setAnimateScript(true) end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then return end
    if animator ~= hooked then   -- new character / new Animator: hook it
        if hookConn then hookConn:Disconnect() end
        hooked = animator
        hookConn = animator.AnimationPlayed:Connect(function(track)
            if C.NoAnim and U.Running then suppress(track) end
        end)
    end
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do suppress(track) end
end
onUnload(function() if hookConn then hookConn:Disconnect() end end)

renderFirst(sweep)
renderLast(sweep)
connect(RunService.Stepped, sweep)
connect(RunService.Heartbeat, sweep)
end   -- no animations

-- inventory inspector ----------------------------------------------------
-- Roblox only replicates other players' Backpack in games that choose to; whatever the
-- server does not send simply cannot be shown.

local inv = playerTab:Section("Inventory", "right")
toggle(inv, "Live Refresh", "InvLive", true)

local invRows = {}
for i = 1, 14 do
    invRows[i] = inv:Label("")
    invRows[i].Instance.Visible = false
end

local INV_SKIP = { Backpack = true, PlayerGui = true, PlayerScripts = true, StarterGear = true, leaderstats = true }

local function inventoryLines(plr)
    local lines = {}
    local char = plr.Character
    local held = char and char:FindFirstChildOfClass("Tool")
    table.insert(lines, plr.DisplayName .. " (" .. plr.Name .. ")")
    table.insert(lines, "Holding: " .. (held and held.Name or "nothing"))

    local bag = plr:FindFirstChildOfClass("Backpack")
    local items = {}
    if bag then
        for _, tool in ipairs(bag:GetChildren()) do table.insert(items, tool.Name) end
    end
    table.insert(lines, ("Backpack: %d item(s)"):format(#items))
    for i, name in ipairs(items) do
        if i > 7 then table.insert(lines, ("  + %d more"):format(#items - 7)) break end
        table.insert(lines, "  - " .. name)
    end

    -- games that store an inventory as folders on the player
    for _, child in ipairs(plr:GetChildren()) do
        if not INV_SKIP[child.Name] and (child:IsA("Folder") or child:IsA("Configuration")) then
            local n = #child:GetChildren()
            if n > 0 then table.insert(lines, ("%s: %d entries"):format(child.Name, n)) end
        end
    end
    return lines
end

renderInventory = function()
    local plr = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    local lines = plr and inventoryLines(plr) or { "Pick a player above" }
    for i, row in ipairs(invRows) do
        local text = lines[i]
        row.Instance.Visible = text ~= nil
        if text then row:Set(text) end
    end
end

local invAccum = 0
connect(RunService.Heartbeat, function(dt)
    if not (C.InvLive and U.Running) then return end
    invAccum += dt
    if invAccum >= 0.5 then invAccum = 0 renderInventory() end
end)
renderInventory()

toggle(misc1, "Anti AFK", "AntiAfk", true)
connect(lp.Idled, function()
    if not C.AntiAfk then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end)
end)

misc1:Button({ Text = "Rejoin Server", Callback = function()
    pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, lp) end)
end })

----------------------------------------------------------------------
-- whitelist & blacklist
----------------------------------------------------------------------

-- Whitelist = friends: skipped by aimbot, silent aim, triggerbot and rage, and drawn in their own
-- colour in the ESP. Blacklist = priority targets: aimed at first, drawn in their own colour, and with
-- "Only Target Blacklist" nobody else is targeted at all. A player is on at most one list. The lists are
-- stored by player NAME, so they survive someone leaving and rejoining (and are saved in configs).
do
local listSec = playerTab:Section("Whitelist & Blacklist", "right")
local whiteDD, blackDD

local function presentNames()
    local present = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then present[plr.Name] = true end
    end
    return present
end

local function pickedOf(set)
    local picked, present = {}, presentNames()
    for name in pairs(set) do
        if present[name] then table.insert(picked, name) end
    end
    table.sort(picked, function(a, b) return a:lower() < b:lower() end)
    return picked
end

-- a dropdown only knows the players that are here right now, so entries of absent players are kept
local function takePicks(set, other, picks)
    local present = presentNames()
    for name in pairs(set) do
        if present[name] then set[name] = nil end
    end
    for _, name in ipairs(picks) do
        set[name] = true
        other[name] = nil          -- never on both lists
    end
end

local function syncSelections()
    if whiteDD then whiteDD:Set(pickedOf(U.White), true) end
    if blackDD then blackDD:Set(pickedOf(U.Black), true) end
end

whiteDD = listSec:Dropdown({ Text = "Whitelist (friends)", Options = playerNames(), Multi = true, Flag = "ListWhite",
    Callback = function(picks) takePicks(U.White, U.Black, picks) syncSelections() end })
blackDD = listSec:Dropdown({ Text = "Blacklist (targets)", Options = playerNames(), Multi = true, Flag = "ListBlack",
    Callback = function(picks) takePicks(U.Black, U.White, picks) syncSelections() end })

local function refreshLists()
    whiteDD:SetOptions(playerNames())
    blackDD:SetOptions(playerNames())
    syncSelections()
end
connect(Players.PlayerAdded, refreshLists)
connect(Players.PlayerRemoving, function() task.defer(refreshLists) end)

listSec:Button({ Text = "Refresh Player List", Callback = refreshLists })
listSec:Button({ Text = "Clear Whitelist", Callback = function() table.clear(U.White) syncSelections() end })
listSec:Button({ Text = "Clear Blacklist", Callback = function() table.clear(U.Black) syncSelections() end })
toggle(listSec, "Skip Whitelisted Players", "ListRespectWhite", true)
toggle(listSec, "Target Blacklisted First", "ListBlackFirst", true)
toggle(listSec, "Only Target Blacklist", "ListOnlyBlack", false)

-- Roblox friends never become targets: they are added to the whitelist as they join
local function whitelistFriends()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and not U.White[plr.Name] then
            local ok, isFriend = pcall(lp.IsFriendsWith, lp, plr.UserId)   -- yields, hence the thread
            if ok and isFriend then
                U.White[plr.Name] = true
                U.Black[plr.Name] = nil
            end
        end
    end
    syncSelections()
end
toggle(listSec, "Auto-Whitelist Roblox Friends", "AutoWhiteFriends", false, function(v)
    if v then task.spawn(whitelistFriends) end
end)
connect(Players.PlayerAdded, function()
    if C.AutoWhiteFriends then task.delay(1, whitelistFriends) end
end)
end   -- lists

