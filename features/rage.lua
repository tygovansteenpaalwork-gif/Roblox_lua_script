--[[
    Rage  -  rage.lua
    Automatic combat: targeting, burst fire, positioning, spinbot, abilities and the RAGE status text.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/rage.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "rage", Title = "Rage" })

local BIND, C, FIRE_METHODS, Players, Ready, TARGET_PARTS = ctx.BIND, ctx.C, ctx.FIRE_METHODS, ctx.Players, ctx.Ready, ctx.TARGET_PARTS
local U, UserInputService, cam, charOf, connect, cursorOrCenter = ctx.U, ctx.UserInputService, ctx.cam, ctx.charOf, ctx.connect, ctx.cursorOrCenter
local dropdown, ensureToolEquipped, fireWeapon, keybind, lp, notify = ctx.dropdown, ctx.ensureToolEquipped, ctx.fireWeapon, ctx.keybind, ctx.lp, ctx.notify
local onUnload, overlay, predicted, renderLast, selectTarget, slider = ctx.onUnload, ctx.overlay, ctx.predicted, ctx.renderLast, ctx.selectTarget, ctx.slider
local toggle, viewportCenter, win = ctx.toggle, ctx.viewportCenter, ctx.win

local rageTarget = nil
do
local rageTab = win:Tab("Rage")
local rage = rageTab:Section("Rage Bot")
local rageFire = rageTab:Section("Firing", "right")
local rageFilt = rageTab:Section("Filters", "right")
local rageAbil = rageTab:Section("Abilities")
local rageMove = rageTab:Section("Positioning & Spin")

toggle(rage, "Enabled", "RageEnabled", false)
-- while the menu is open Rage does nothing (no clicks, camera, teleport, keys), so the menu is always usable
-- and you can always switch Rage off; it carries on the moment the menu closes
toggle(rage, "Pause While Menu Open", "RagePauseMenu", true)
dropdown(rage, "Mode", "RageMode", { "Always On", "Hold Key" }, "Always On")
keybind(rage, "Rage Key", "RageKey", Enum.KeyCode.V)

-- who to shoot: everyone (best target by Priority) or one chosen player
local RAGE_AUTO = "Everyone (Auto)"
local function rageChoices()
    local names = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then table.insert(names, plr.Name) end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    table.insert(names, 1, RAGE_AUTO)
    return names
end
C.RageWho = RAGE_AUTO
local rageWhoDD = rage:Dropdown({ Text = "Target Player", Options = rageChoices(), Default = RAGE_AUTO,
    Flag = "RageWho", NoSave = true, Callback = function(v) C.RageWho = v end })
local function refreshRageChoices() rageWhoDD:SetOptions(rageChoices()) end
connect(Players.PlayerAdded, refreshRageChoices)
connect(Players.PlayerRemoving, function() task.defer(refreshRageChoices) end)
rage:Button({ Text = "Refresh Player List", Callback = refreshRageChoices })
dropdown(rage, "Target Part", "RagePart", TARGET_PARTS, "Head")
dropdown(rage, "Priority", "RagePriority", { "Closest Distance", "Lowest Health", "Closest to Cursor" }, "Closest Distance")
slider(rage, "Max Distance", "RageDist", 50, 3000, 1000, { Suffix = " st" })
slider(rage, "Min Distance", "RageMinDist", 0, 200, 0, { Suffix = " st" })
slider(rage, "FOV Limit (0 = off)", "RageFov", 0, 1000, 0, { Suffix = " px" })
slider(rage, "Aim Smoothing", "RageSmooth", 0, 95, 0, { Suffix = "%" })
slider(rage, "Prediction", "RagePredict", 0, 0.3, 0.05, { Decimals = 2, Suffix = "s" })
toggle(rage, "Add Ping To Prediction", "RagePing", false)
toggle(rage, "Sticky Target", "RageSticky", true)
slider(rage, "Keep Target At Least", "RageSwitch", 0, 3, 0.4, { Decimals = 1, Suffix = "s" })

toggle(rageFire, "Auto Shoot", "RageShoot", true)
slider(rageFire, "Shoot Delay", "RageDelay", 0, 1000, 80, { Suffix = " ms" })
slider(rageFire, "Delay Jitter", "RageJitter", 0, 100, 0, { Suffix = "%" })
slider(rageFire, "Burst Shots", "RageBurst", 1, 10, 1)
slider(rageFire, "Burst Gap", "RageBurstGap", 10, 300, 40, { Suffix = " ms" })
slider(rageFire, "Only Fire Within", "RageAngle", 1, 180, 180, { Suffix = "°" })
dropdown(rageFire, "Fire Method", "RageMethod", FIRE_METHODS, "Auto")
toggle(rageFire, "Auto Equip Tool", "RageEquip", true)
slider(rageFire, "Warm-up", "RageWarmup", 0, 3, 1, { Decimals = 1, Suffix = "s" })

toggle(rageFilt, "Team Check", "RageTeam", true)
toggle(rageFilt, "Dead Check", "RageDead", true)
toggle(rageFilt, "Ignore Walls", "RageIgnoreWalls", false)
toggle(rageFilt, "Skip ForceField", "RageNoFF", true)
toggle(rageFilt, "Skip Invisible Rigs", "RageNoInvis", true)

local RAGE_POSITIONS = { "Off", "Behind Target", "Above Target", "Below Target", "Orbit Target", "Strafe Target" }
dropdown(rageMove, "Position", "RagePosition", RAGE_POSITIONS, "Off")
slider(rageMove, "Position Distance", "RagePosDist", 3, 40, 8, { Decimals = 1, Suffix = " st" })
slider(rageMove, "Position Height", "RagePosHeight", -10, 30, 0, { Decimals = 1, Suffix = " st" })
slider(rageMove, "Position Speed", "RagePosSpeed", 0.2, 8, 2, { Decimals = 1, Suffix = "/s" })
slider(rageMove, "Position Smoothing", "RagePosSmooth", 0, 95, 0, { Suffix = "%" })
toggle(rageMove, "Spin Bot", "RageSpin", false, function(v)
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.AutoRotate = not v end
end)
dropdown(rageMove, "Spin Mode", "RageSpinMode", { "Spin", "Jitter" }, "Spin")
slider(rageMove, "Spin Speed", "RageSpinSpeed", 5, 90, 40, { Suffix = "°" })

-- abilities ---------------------------------------------------------------
-- Every tool in the Backpack/hand is an ability (in The Strongest Battlegrounds the four moves are
-- tools). They are listed in "Abilities To Use"; new tools show up ticked, on their own. Loose keys
-- that are not tools (dash, ultimate ...) can be ticked under "Extra Keys". While Rage has a target
-- within range, ticked abilities are used in rotation, each respecting its own cooldown.
local SLOT_KEYS = {
    Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
    Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}
local EXTRA_KEYS = { "Q", "E", "R", "T", "F", "G", "Z", "X", "C", "V" }

toggle(rageAbil, "Auto Use Abilities", "RageAbilitiesOn", true)
local abilityNames, slotOf, nextSlot = {}, {}, 1
local chosenTools, chosenKeys = {}, {}
local abilityDD, abilityLast = nil, ""

local function currentToolNames()
    local list = {}
    for _, holder in ipairs({ lp.Backpack, lp.Character }) do
        if holder then
            for _, x in ipairs(holder:GetChildren()) do
                if x:IsA("Tool") and not table.find(list, x.Name) then table.insert(list, x.Name) end
            end
        end
    end
    return list
end

local function refreshAbilities()
    local names = currentToolNames()
    local sig = table.concat(names, "|")
    if sig == abilityLast then return end
    abilityLast = sig
    local known = {}
    for _, n in ipairs(abilityNames) do known[n] = true end
    for _, n in ipairs(names) do
        if not slotOf[n] then slotOf[n], nextSlot = nextSlot, nextSlot + 1 end
        if not known[n] then chosenTools[n] = true end   -- a new tool starts ticked
    end
    abilityNames = names
    abilityDD:SetOptions(names)
    local picked = {}
    for _, n in ipairs(names) do if chosenTools[n] then table.insert(picked, n) end end
    abilityDD:Set(picked, true)
end

abilityDD = rageAbil:Dropdown({ Text = "Abilities To Use", Options = {}, Multi = true, Flag = "RageAbilityPick",
    Callback = function(picked)
        local set = {}
        for _, n in ipairs(picked) do set[n] = true end
        for _, n in ipairs(abilityNames) do chosenTools[n] = set[n] or nil end
    end })
rageAbil:Dropdown({ Text = "Extra Keys", Options = EXTRA_KEYS, Multi = true, Flag = "RageExtraKeys",
    Callback = function(picked)
        chosenKeys = {}
        for _, k in ipairs(picked) do chosenKeys[k] = true end
    end })
dropdown(rageAbil, "Ability Method", "RageAbilityMethod", { "Hotbar Key", "Equip + Activate" }, "Hotbar Key")
slider(rageAbil, "Ability Range", "RageAbilityRange", 3, 150, 14, { Suffix = " st" })
slider(rageAbil, "Delay Between Abilities", "RageAbilityDelay", 50, 2000, 350, { Suffix = " ms" })
slider(rageAbil, "Cooldown Per Ability", "RageAbilityCd", 0, 20, 2, { Decimals = 1, Suffix = "s" })

refreshAbilities()
task.spawn(function()
    while U.Running do
        pcall(refreshAbilities)
        task.wait(1)
    end
end)

local abilityReady, nextAbility, abilityIdx = {}, 0, 0
local function pressKey(code)
    local vim = game:GetService("VirtualInputManager")
    vim:SendKeyEvent(true, code, false, game)
    task.delay(0.05, function() vim:SendKeyEvent(false, code, false, game) end)
end

local function useAbility(now, t, off)
    if not C.RageAbilitiesOn or now < nextAbility then return end
    if t.dist > C.RageAbilityRange or off > C.RageAngle then return end
    if UserInputService:GetFocusedTextBox() then return end   -- never type into chat

    local ready = {}
    for _, n in ipairs(abilityNames) do
        if chosenTools[n] and (abilityReady["t:" .. n] or 0) <= now then table.insert(ready, { tool = n }) end
    end
    for _, k in ipairs(EXTRA_KEYS) do
        if chosenKeys[k] and (abilityReady["k:" .. k] or 0) <= now then table.insert(ready, { key = k }) end
    end
    if #ready == 0 then return end

    abilityIdx += 1
    local pick = ready[(abilityIdx - 1) % #ready + 1]
    if pick.key then
        pressKey(Enum.KeyCode[pick.key])
        abilityReady["k:" .. pick.key] = now + C.RageAbilityCd
    else
        if C.RageAbilityMethod == "Equip + Activate" then
            local tool = (lp.Character and lp.Character:FindFirstChild(pick.tool)) or lp.Backpack:FindFirstChild(pick.tool)
            local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
            if tool and hum then
                if tool.Parent ~= lp.Character then hum:EquipTool(tool) end
                tool:Activate()
            end
        elseif SLOT_KEYS[slotOf[pick.tool] or 99] then
            pressKey(SLOT_KEYS[slotOf[pick.tool]])
        end
        abilityReady["t:" .. pick.tool] = now + C.RageAbilityCd
    end
    nextAbility = now + C.RageAbilityDelay / 1000
end
U.RageAbilityState = function() return abilityNames, chosenTools, chosenKeys end   -- self-tests

local rageState, rageOnAt = "off", 0   -- "off" | "loading" | "active"; driven by the status pill below
local rageLockedAt, rageKills = 0, 0
local burstLeft, nextShot, nextBurst = 0, 0, 0
local rageSpun = false                  -- true while WE have AutoRotate switched off for the spin bot

local function rageReset()
    rageTarget, burstLeft = nil, 0
    if rageSpun then
        rageSpun = false
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.AutoRotate = true end
    end
end
onUnload(rageReset)

-- where the local character should stand relative to the target for the chosen Position mode
local function rageSpot(base, now)
    local d, h, mode = C.RagePosDist, C.RagePosHeight, C.RagePosition
    local up = Vector3.new(0, h, 0)
    if mode == "Behind Target" then return base.Position - base.LookVector * d + up end
    if mode == "Above Target" then return base.Position + Vector3.new(0, d + h, 0) end
    if mode == "Below Target" then return base.Position - Vector3.new(0, d - h, 0) end
    if mode == "Orbit Target" then
        local a = now * C.RagePosSpeed
        return base.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * d + up
    end
    -- Strafe: slides left and right of the target's facing
    return base.Position + base.RightVector * math.sin(now * C.RagePosSpeed) * d + up
end

local function pingSeconds()
    local ok, v = pcall(function() return lp:GetNetworkPing() end)
    return (ok and type(v) == "number") and v or 0
end

renderLast(function(dt)
    if not (C.RageEnabled and U.Running) or rageState ~= "active"
        or (C.RageMode == "Hold Key" and not (BIND.RageKey and BIND.RageKey:IsDown())) then
        -- off / warming up / key released: drop the target, give the character its rotation back
        if rageTarget and rageTarget.hum.Health <= 0 then rageKills += 1 end
        rageReset()
        return
    end
    if C.RagePauseMenu and win.Main.Visible then rageReset() return end

    local char, hum, root = charOf(lp)
    if not char then return end
    local now = os.clock()

    if C.RageSpin then
        hum.AutoRotate = false
        rageSpun = true
        local turn = C.RageSpinMode == "Jitter" and (math.random() * 2 - 1) * 90 or C.RageSpinSpeed
        root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(turn), 0)
    elseif rageSpun then
        rageSpun = false
        hum.AutoRotate = true
    end

    -- keep the current target for a minimum time (or forever when Sticky) so it does not flicker
    local prev = rageTarget
    local keep = prev and (C.RageSticky or now - rageLockedAt < C.RageSwitch)
    local t = selectTarget({
        Only = C.RageWho ~= RAGE_AUTO and C.RageWho or nil,
        FOV = C.RageFov > 0 and C.RageFov or nil, MaxDist = C.RageDist, MinDist = C.RageMinDist,
        Team = C.RageTeam, NoFF = C.RageNoFF, NoInvis = C.RageNoInvis, Wall = not C.RageIgnoreWalls, AllowDead = not C.RageDead,
        Part = C.RagePart, Priority = C.RagePriority, Origin = cursorOrCenter(false),
        Sticky = keep and prev.plr or nil,
    })

    if prev and (not t or t.plr ~= prev.plr) then
        if prev.hum.Health <= 0 then rageKills += 1 end
        burstLeft = 0
    end
    if t and (not prev or t.plr ~= prev.plr) then rageLockedAt = now end
    rageTarget = t
    if not t then return end

    if C.RagePosition ~= "Off" then
        local base = t.root.CFrame
        local spot = rageSpot(base, now)
        if C.RagePosSmooth > 0 then
            spot = root.Position:Lerp(spot, 1 - (C.RagePosSmooth / 100) ^ (math.min(dt, 0.1) * 60))
        end
        -- stay upright: face the target on our own height. Straight above/below it there is no
        -- horizontal direction (lookAt would produce a NaN CFrame), so keep the current yaw then.
        local flat = Vector3.new(base.Position.X - spot.X, 0, base.Position.Z - spot.Z)
        if flat.Magnitude > 0.05 then
            root.CFrame = CFrame.lookAt(spot, spot + flat)
        else
            root.CFrame = CFrame.new(spot) * root.CFrame.Rotation
        end
    end

    local c = cam()
    local aimAt = predicted(t, C.RagePredict + (C.RagePing and pingSeconds() or 0))
    local goal = CFrame.lookAt(c.CFrame.Position, aimAt)
    if C.RageSmooth > 0 then
        c.CFrame = c.CFrame:Lerp(goal, 1 - (C.RageSmooth / 100) ^ (math.min(dt, 0.1) * 60))
    else
        c.CFrame = goal
    end

    local off = math.deg(math.acos(math.clamp(c.CFrame.LookVector:Dot((aimAt - c.CFrame.Position).Unit), -1, 1)))
    useAbility(now, t, off)
    if not C.RageShoot then return end
    if off > C.RageAngle then return end

    -- burst fire: RageBurst shots RageBurstGap ms apart, then wait the (jittered) shoot delay
    local function delay()
        local jitter = 1 + (math.random() * 2 - 1) * C.RageJitter / 100
        return (C.RageDelay / 1000) * jitter
    end
    if burstLeft == 0 and now >= nextBurst then burstLeft = C.RageBurst end
    if burstLeft > 0 and now >= nextShot then
        if C.RageEquip then ensureToolEquipped() end
        fireWeapon(C.RageMethod)
        burstLeft -= 1
        nextShot = now + C.RageBurstGap / 1000
        if burstLeft == 0 then nextBurst = now + delay() end
    end
end)
U.RageTarget = function() return rageTarget end   -- exposed for self-tests

-- rage status -----------------------------------------------------------
-- Plain text, fixed just above the middle of the screen, for as long as Rage is on:
-- "RAGE LOADING..." with animated dots during the warm-up, then "RAGE ACTIVE" (with the
-- target's name) - or "RAGE READY" in hold-key mode while the key is up. The colour (or
-- rainbow) is chosen on the Notifications page. It disappears the moment Rage is switched off.

local rageText = Instance.new("TextLabel")
rageText.Name = "RageStatus"
rageText.AnchorPoint = Vector2.new(0.5, 1)
rageText.BackgroundTransparency = 1
rageText.Size = UDim2.fromOffset(360, 22)
rageText.Font = Enum.Font.GothamBold
rageText.TextSize = 16
rageText.TextStrokeTransparency = 0.35
rageText.TextStrokeColor3 = Color3.new(0, 0, 0)
rageText.Visible = false
rageText.Parent = overlay

local rageAlpha = 0

local function rageTextColor()
    if C.RageStatusRainbow then return Color3.fromHSV((os.clock() * 0.4) % 1, 0.9, 1) end
    return C.RageStatusColor or Color3.fromRGB(255, 255, 255)
end

renderLast(function(dt)
    -- state follows the flag, however it got switched (button, keybind or a loaded config)
    if C.RageEnabled and U.Running then
        if rageState == "off" then rageState, rageOnAt, rageKills = "loading", os.clock(), 0 end
        if rageState == "loading" and os.clock() - rageOnAt >= C.RageWarmup then
            rageState = "active"
            notify("Rage", "Active", "success", "toggle")
        end
    else
        rageState = "off"
    end

    local want = rageState ~= "off" and C.RageStatus
    rageAlpha += ((want and 1 or 0) - rageAlpha) * math.min(dt * 12, 1)
    rageText.Visible = rageAlpha > 0.02
    if not rageText.Visible then return end

    local text
    if rageState == "loading" then
        -- one to three dots, padded with spaces so the text does not shift sideways
        local dots = string.rep(".", 1 + math.floor(os.clock() * 3) % 3)
        text = "RAGE LOADING" .. dots .. string.rep(" ", 3 - #dots)
    else
        local armed = C.RageMode ~= "Hold Key" or (BIND.RageKey ~= nil and BIND.RageKey:IsDown())
        local kills = rageKills > 0 and ("  ·  " .. rageKills .. " K") or ""
        if C.RagePauseMenu and win.Main.Visible then
            text = "RAGE PAUSED  ·  menu open" .. kills
        elseif not armed then
            text = "RAGE READY" .. kills
        elseif rageTarget then
            text = "RAGE ACTIVE  ·  " .. rageTarget.plr.DisplayName .. kills
        elseif C.RageWho ~= RAGE_AUTO then
            text = "RAGE ACTIVE  ·  waiting for " .. C.RageWho .. kills
        else
            text = "RAGE ACTIVE" .. kills
        end
    end

    local center = viewportCenter()
    rageText.Text = text
    rageText.TextColor3 = rageTextColor()
    rageText.TextTransparency = 1 - rageAlpha
    rageText.TextStrokeTransparency = math.clamp(0.35 + (1 - rageAlpha), 0, 1)
    rageText.Position = UDim2.fromOffset(center.X, center.Y - 30)
end)
end   -- rage block

Ready()
