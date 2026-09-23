--[[
    Rage  -  rage.lua
    Automatic combat: targeting, burst fire, positioning, spinbot, abilities and the RAGE status text.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/rage.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "rage", Title = "Rage" })

local BIND, C, FIRE_METHODS, Players, Ready, TARGET_PARTS = ctx.BIND, ctx.C, ctx.FIRE_METHODS, ctx.Players, ctx.Ready, ctx.TARGET_PARTS
local U, UserInputService, cam, charOf, connect, cursorOrCenter = ctx.U, ctx.UserInputService, ctx.cam, ctx.charOf, ctx.connect, ctx.cursorOrCenter
local dropdown, fireWeapon, keybind, lp, notify, onUnload = ctx.dropdown, ctx.fireWeapon, ctx.keybind, ctx.lp, ctx.notify, ctx.onUnload
local overlay, predicted, renderLast, sameTeam, screenPoint, selectTarget = ctx.overlay, ctx.predicted, ctx.renderLast, ctx.sameTeam, ctx.screenPoint, ctx.selectTarget
local slider, toggle, viewportCenter, win = ctx.slider, ctx.toggle, ctx.viewportCenter, ctx.win

local rageTarget = nil
do
local rageTab = win:Tab("Rage")
local rage = rageTab:Section("Rage Bot")
local rageFire = rageTab:Section("Firing", "right")
local rageFilt = rageTab:Section("Filters", "right")
local rageAbil = rageTab:Section("Abilities")
local rageMove = rageTab:Section("Positioning & Spin")

-- small state of this tab in one table: the main chunk has (almost) no free local slots
local R = {
    AUTO = "Auto", NONE = "No Tool (fists)",
    skip = {},          -- [plr] = until when Rage passes over that player (gave up: no damage)
    warned = {},        -- extra keys we already warned about
    seen = {},          -- every tool name ever listed (only a NEW tool starts ticked as an ability)
    holdUntil = 0,      -- the ability tool stays in hand until then, afterwards the weapon comes back
    equipAt = 0, progressAt = 0, whyAt = 0,
}

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
-- a target that takes no damage for this long is passed over for 5 s (unreachable, god mode, stuck in a wall ...)
slider(rage, "Give Up If No Damage (0 = off)", "RageGiveUp", 0, 15, 4, { Decimals = 1, Suffix = "s" })

toggle(rageFire, "Auto Shoot", "RageShoot", true)
slider(rageFire, "Shoot Delay", "RageDelay", 0, 1000, 80, { Suffix = " ms" })
slider(rageFire, "Delay Jitter", "RageJitter", 0, 100, 0, { Suffix = "%" })
slider(rageFire, "Burst Shots", "RageBurst", 1, 10, 1)
slider(rageFire, "Burst Gap", "RageBurstGap", 10, 300, 40, { Suffix = " ms" })
slider(rageFire, "Only Fire Within", "RageAngle", 1, 180, 180, { Suffix = "°" })
dropdown(rageFire, "Fire Method", "RageMethod", FIRE_METHODS, "Auto")
toggle(rageFire, "Auto Equip Tool", "RageEquip", true)
-- an empty gun (its "Ammo" value at 0) is reloaded with R
toggle(rageFire, "Auto Reload", "RageReload", true)
-- what Rage holds while shooting: Auto = the first tool that is not an ability, No Tool = empty hands
-- (punch / M1 games), or one tool from your inventory. The list fills itself with your tools.
C.RageWeapon = R.AUTO
R.weaponDD = rageFire:Dropdown({ Text = "Weapon", Options = { R.AUTO, R.NONE }, Default = R.AUTO, Flag = "RageWeapon",
    Callback = function(v)
        C.RageWeapon = v or R.AUTO
        if R.refresh then task.defer(R.refresh) end   -- the weapon leaves the ability list at once
    end })
slider(rageFire, "Warm-up", "RageWarmup", 0, 3, 1, { Decimals = 1, Suffix = "s" })

toggle(rageFilt, "Team Check", "RageTeam", true)
toggle(rageFilt, "Dead Check", "RageDead", true)
toggle(rageFilt, "Ignore Walls", "RageIgnoreWalls", false)
toggle(rageFilt, "Skip ForceField", "RageNoFF", true)
toggle(rageFilt, "Skip Invisible Rigs", "RageNoInvis", true)
-- a gun with a "Range" value (Da Hood style: shotguns 70 studs) only picks targets it can reach
toggle(rageFilt, "Respect Weapon Range", "RageRange", true)

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
    R.toolOf = {}
    for _, holder in ipairs({ lp.Backpack, lp.Character }) do
        if holder then
            for _, x in ipairs(holder:GetChildren()) do
                if x:IsA("Tool") and not table.find(list, x.Name) then
                    table.insert(list, x.Name)
                    R.toolOf[x.Name] = x
                end
            end
        end
    end
    return list
end

-- An ability is a tool WITHOUT a model: The Strongest Battlegrounds' moves are empty tools. A tool with parts is a
-- weapon or an item (guns, knives, a wallet ...): pressing its hotbar key would just swap what you hold.
function R.isAbilityTool(name)
    local t = R.toolOf and R.toolOf[name]
    return t ~= nil and t:FindFirstChildWhichIsA("BasePart", true) == nil
end

-- a gun: a tool with an "Ammo" value (Da Hood style); returns the ammo left
function R.ammoOf(tool)
    local a = tool and tool:FindFirstChild("Ammo")
    if a and a:IsA("ValueBase") then return tonumber(a.Value) end
    return nil
end

local function refreshAbilities()
    local names = currentToolNames()
    local sig = table.concat(names, "|") .. "#" .. tostring(C.RageWeapon)
    if sig == abilityLast then return end
    abilityLast = sig
    -- weapon list: the fixed choices, every tool, and the chosen weapon even while it is not in the inventory
    -- (dead, not given yet) - otherwise the dropdown would forget it
    local weapons = { R.AUTO, R.NONE }
    for _, n in ipairs(names) do table.insert(weapons, n) end
    if not table.find(weapons, C.RageWeapon) then table.insert(weapons, C.RageWeapon) end
    R.weaponDD:SetOptions(weapons)
    for _, n in ipairs(names) do
        if not slotOf[n] then slotOf[n], nextSlot = nextSlot, nextSlot + 1 end
        if not R.seen[n] then R.seen[n], chosenTools[n] = true, true end   -- a new tool starts ticked
    end
    -- only model-less tools are abilities, and the weapon is never one
    local abil = {}
    for _, n in ipairs(names) do
        if n ~= C.RageWeapon and R.isAbilityTool(n) then table.insert(abil, n) end
    end
    names = abil
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
-- Rage presses keys through VirtualInputManager, which this menu sees as real key presses: a key that is
-- also a menu keybind (F = Fly, G = Telekinesis fire, V = Rage key ...) would switch that feature on and
-- off every few hundred ms. Such keys are skipped, with one warning per key.
function R.menuKey(code)
    if win.ToggleKey == code then return true end
    for _, b in pairs(BIND) do
        if b:Get() == code then return true end
    end
    return false
end
function R.warnKey(k)
    if R.warned[k] then return end
    R.warned[k] = true
    notify("Rage", "Extra key " .. k .. " is skipped: a menu keybind already uses it", "warn")
end

rageAbil:Dropdown({ Text = "Extra Keys", Options = EXTRA_KEYS, Multi = true, Flag = "RageExtraKeys",
    Callback = function(picked)
        chosenKeys, R.warned = {}, {}
        for _, k in ipairs(picked) do chosenKeys[k] = true end
    end })
-- Equip + Activate puts the tool in your hand directly; Hotbar Key presses its number key instead
-- (the slot number is a guess: the order in which the tools were first seen)
dropdown(rageAbil, "Ability Method", "RageAbilityMethod", { "Equip + Activate", "Hotbar Key" }, "Equip + Activate")
slider(rageAbil, "Ability Range", "RageAbilityRange", 3, 150, 14, { Suffix = " st" })
slider(rageAbil, "Delay Between Abilities", "RageAbilityDelay", 50, 2000, 350, { Suffix = " ms" })
slider(rageAbil, "Cooldown Per Ability", "RageAbilityCd", 0, 20, 2, { Decimals = 1, Suffix = "s" })

R.refresh = refreshAbilities
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
        if chosenKeys[k] and (abilityReady["k:" .. k] or 0) <= now then
            if R.menuKey(Enum.KeyCode[k]) then R.warnKey(k) else table.insert(ready, { key = k }) end
        end
    end
    if #ready == 0 then return end

    abilityIdx += 1
    local pick = ready[(abilityIdx - 1) % #ready + 1]
    if pick.key then
        pressKey(Enum.KeyCode[pick.key])
        abilityReady["k:" .. pick.key] = now + C.RageAbilityCd
    else
        local char = lp.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local held = char and char:FindFirstChild(pick.tool)
        local slot = SLOT_KEYS[slotOf[pick.tool] or 99]
        if held and held:IsA("Tool") then
            held:Activate()   -- already in hand: its hotbar key would put it AWAY again
        elseif C.RageAbilityMethod == "Hotbar Key" and slot and not R.menuKey(slot) then
            pressKey(slot)
        else
            local tool = lp.Backpack:FindFirstChild(pick.tool)
            if tool and tool:IsA("Tool") and hum then
                hum:EquipTool(tool)
                tool:Activate()
            end
        end
        abilityReady["t:" .. pick.tool] = now + C.RageAbilityCd
        -- keep the ability tool in hand for a moment, then the weapon comes back (R.equipWeapon)
        R.holdUntil = now + math.min(C.RageAbilityDelay / 1000, 0.5)
    end
    nextAbility = now + C.RageAbilityDelay / 1000
end
U.RageAbilityState = function() return abilityNames, chosenTools, chosenKeys end   -- self-tests

-- puts the chosen weapon in hand (not while an ability tool is still being used); a few times a second at most
function R.equipWeapon(now)
    if not C.RageEquip or now < R.holdUntil or now < R.equipAt then return end
    R.equipAt = now + 0.15
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local held = char:FindFirstChildOfClass("Tool")
    local w = C.RageWeapon
    -- (only model-less tools count: an old config may still have guns ticked as abilities)
    local function isAbility(name) return C.RageAbilitiesOn and chosenTools[name] and name ~= w and R.isAbilityTool(name) end
    if w == R.NONE then
        if held then hum:UnequipTools() end
    elseif w == R.AUTO then
        -- a gun first (one with ammo left if possible); in games without guns the first tool that is no ability;
        -- only abilities in the inventory: fight with empty hands
        local guns, other = {}, nil
        for _, x in ipairs(lp.Backpack:GetChildren()) do
            if x:IsA("Tool") and not isAbility(x.Name) then
                if R.ammoOf(x) then table.insert(guns, x) elseif not other then other = x end
            end
        end
        if held and not isAbility(held.Name) then
            if R.ammoOf(held) or #guns == 0 then return end   -- a gun (reloaded when empty), or no guns here at all
        end
        local pick
        for _, g in ipairs(guns) do
            if (R.ammoOf(g) or 0) > 0 then pick = g break end
        end
        pick = pick or guns[1] or other
        if pick then hum:EquipTool(pick) elseif held then hum:UnequipTools() end
    elseif not (held and held.Name == w) then
        local x = lp.Backpack:FindFirstChild(w)
        if x and x:IsA("Tool") then hum:EquipTool(x) end
    end
end

-- empty gun in hand: press R (once a second at most, not while the game already reloads, never while typing)
function R.autoReload(now)
    if not C.RageReload or now < (R.reloadAt or 0) then return end
    local char = lp.Character
    local ammo = R.ammoOf(char and char:FindFirstChildOfClass("Tool"))
    if not ammo or ammo > 0 then return end
    local be = char:FindFirstChild("BodyEffects")
    local busy = be and be:FindFirstChild("Reload")
    if busy and busy:IsA("ValueBase") and busy.Value == true then return end
    if UserInputService:GetFocusedTextBox() or R.menuKey(Enum.KeyCode.R) then return end
    R.reloadAt = now + 1
    pressKey(Enum.KeyCode.R)
end

-- a spot Rage may put the character on: a real number, and not in (or under) the void
function R.safeSpot(p)
    if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z or p.Magnitude > 1e5 then return false end
    local floor = workspace.FallenPartsDestroyHeight
    if floor ~= floor then floor = -1000 end   -- NaN in some games
    return p.Y > math.max(floor, -1000) + 20
end

-- after teleporting every frame the physics has built up speed: drop it, or the character shoots away
function R.stopPos()
    R.positioned = false
    local _, _, root = charOf(lp)
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

-- why there is no target: the reason of the nearest player that was passed over (for the status text)
function R.noTargetWhy()
    local camPos = cam().CFrame.Position
    local anyBlack = next(U.Black) ~= nil
    local why, bestDist = nil, math.huge
    for _, e in ipairs(U.Others()) do
        local plr, char, hum, root = e.plr, e.char, e.hum, e.root
        if C.RageWho == RAGE_AUTO or plr.Name == C.RageWho then
            local r
            local dist = root and (root.Position - camPos).Magnitude or 1e9
            if C.ListRespectWhite and U.White[plr.Name] then r = "whitelisted"
            elseif C.ListOnlyBlack and anyBlack and not U.Black[plr.Name] then r = "not on blacklist"
            elseif R.skip[plr] then r = "gave up, no damage"
            elseif not (char and hum and root) then r = "no character"
            elseif C.RageDead and hum.Health <= 0 then r = "dead"
            elseif C.RageDead and U.isDowned(char) then r = "knocked out"
            elseif C.RageTeam and sameTeam(plr) then r = "teammate"
            elseif C.RageNoFF and char:FindFirstChildOfClass("ForceField") then r = "forcefield"
            elseif C.RageNoInvis and U.isInvisible(char) then r = "invisible"
            elseif dist > C.RageDist then r = "too far"
            elseif dist < C.RageMinDist then r = "too close"
            else
                local part = char:FindFirstChild("Head") or root
                local sp, on = screenPoint(part.Position)
                if C.RageFov > 0 and not (on and (sp - cursorOrCenter(false)).Magnitude <= C.RageFov) then r = "outside FOV"
                elseif not C.RageIgnoreWalls then r = "behind wall" end
            end
            if r and dist < bestDist then why, bestDist = r, dist end
        end
    end
    if C.RageWho ~= RAGE_AUTO and not Players:FindFirstChild(C.RageWho) then return "not in server" end
    return why or (#U.Others() == 0 and "no other players" or nil)
end

local rageState, rageOnAt = "off", 0   -- "off" | "loading" | "active"; driven by the status pill below
local rageLockedAt, rageKills = 0, 0
local burstLeft, nextShot, nextBurst = 0, 0, 0
local rageSpun = false                  -- true while WE have AutoRotate switched off for the spin bot

local function rageReset()
    rageTarget, burstLeft = nil, 0
    if R.positioned then R.stopPos() end
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
    for plr, untilT in pairs(R.skip) do
        if untilT <= now then R.skip[plr] = nil end
    end
    R.autoReload(now)
    -- a gun with a Range value only picks targets it can reach (distances are measured from the camera). Not while
    -- Position is on: then Rage moves you next to the target anyway.
    local maxDist = C.RageDist
    if C.RageRange and C.RagePosition == "Off" then
        local tool = char:FindFirstChildOfClass("Tool")
        local range = tool and tool:FindFirstChild("Range")
        if range and range:IsA("ValueBase") and tonumber(range.Value) then
            maxDist = math.min(maxDist, range.Value + (cam().CFrame.Position - root.Position).Magnitude)
        end
    end
    local t = selectTarget({
        Only = C.RageWho ~= RAGE_AUTO and C.RageWho or nil, Skip = R.skip,
        FOV = C.RageFov > 0 and C.RageFov or nil, MaxDist = maxDist, MinDist = C.RageMinDist,
        Team = C.RageTeam, NoFF = C.RageNoFF, NoInvis = C.RageNoInvis, Wall = not C.RageIgnoreWalls, AllowDead = not C.RageDead,
        Part = C.RagePart, Priority = C.RagePriority, Origin = cursorOrCenter(false),
        Sticky = keep and prev.plr or nil,
    })

    if prev and (not t or t.plr ~= prev.plr) then
        if prev.hum.Health <= 0 then rageKills += 1 end
        burstLeft = 0
    end
    if t and (not prev or t.plr ~= prev.plr) then rageLockedAt = now end

    -- give up on a target that takes no damage for a while (unreachable, god mode, stuck in a wall ...):
    -- pass over it for 5 s. Not for one chosen player (there is nobody else), and only while Rage attacks.
    if t and C.RageGiveUp > 0 and C.RageWho == RAGE_AUTO and (C.RageShoot or C.RageAbilitiesOn) then
        local hp = t.hum.Health
        if t.plr ~= R.hpPlr then R.hpPlr, R.progressAt = t.plr, now
        elseif hp < R.hp then R.progressAt = now end
        R.hp = hp
        if now - R.progressAt > C.RageGiveUp then
            R.skip[t.plr], R.hpPlr, burstLeft = now + 5, nil, 0
            t = nil
        end
    end

    rageTarget = t
    if not t then
        if R.positioned then R.stopPos() end
        if now - R.whyAt > 0.25 then R.whyAt, R.why = now, R.noTargetWhy() end
        return
    end
    R.why = nil

    if C.RagePosition ~= "Off" then
        local base = t.root.CFrame
        local spot = rageSpot(base, now)
        if C.RagePosSmooth > 0 then
            spot = root.Position:Lerp(spot, 1 - (C.RagePosSmooth / 100) ^ (math.min(dt, 0.1) * 60))
        end
        -- never follow a target into the void or to a broken (NaN / far away) position
        if R.safeSpot(spot) then
            -- stay upright: face the target on our own height. Straight above/below it there is no
            -- horizontal direction (lookAt would produce a NaN CFrame), so keep the current yaw then.
            local flat = Vector3.new(base.Position.X - spot.X, 0, base.Position.Z - spot.Z)
            if flat.Magnitude > 0.05 then
                root.CFrame = CFrame.lookAt(spot, spot + flat)
            else
                root.CFrame = CFrame.new(spot) * root.CFrame.Rotation
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            R.positioned = true
        elseif R.positioned then
            R.stopPos()
        end
    elseif R.positioned then
        R.stopPos()
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
    R.equipWeapon(now)
    if not C.RageShoot then return end
    if off > C.RageAngle then return end

    -- burst fire: RageBurst shots RageBurstGap ms apart, then wait the (jittered) shoot delay
    local function delay()
        local jitter = 1 + (math.random() * 2 - 1) * C.RageJitter / 100
        return (C.RageDelay / 1000) * jitter
    end
    if burstLeft == 0 and now >= nextBurst then burstLeft = C.RageBurst end
    if burstLeft > 0 and now >= nextShot then
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
R.glow = U.NewGlow(rageText)
onUnload(function() U.DropGlow(R.glow) end)

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
    if not rageText.Visible then U.SyncGlow(R.glow, false) return end

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
        else
            local why = R.why and (" (" .. R.why .. ")") or ""
            if C.RageWho ~= RAGE_AUTO then
                text = "RAGE ACTIVE  ·  waiting for " .. C.RageWho .. why .. kills
            else
                text = "RAGE ACTIVE  ·  no target" .. why .. kills
            end
        end
    end

    local center = viewportCenter()
    rageText.Text = text
    rageText.TextColor3 = rageTextColor()
    rageText.TextTransparency = 1 - rageAlpha
    rageText.TextStrokeTransparency = math.clamp(0.35 + (1 - rageAlpha), 0, 1)
    rageText.Position = UDim2.fromOffset(center.X, center.Y - 30)
    U.SyncGlow(R.glow, C.NotifGlow, rageText.TextColor3, C.NotifGlowSize or 6, rageAlpha)
end)
end   -- rage block

Ready()
