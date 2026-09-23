--[[
    Avatar  -  avatar_copy.lua
    Become a copy of another player or of any Roblox user (by name or id). Only on your screen.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/avatar_copy.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "avatar_copy", Title = "Avatar" })

local C, Players, Ready, U, connect, lp = ctx.C, ctx.Players, ctx.Ready, ctx.U, ctx.connect, ctx.lp
local notify, onUnload, playerNames, toggle, win = ctx.notify, ctx.onUnload, ctx.playerNames, ctx.toggle, ctx.win

-- Copies what a player WEARS (accessories, shirt, pants, graphic tee, body colours, character
-- meshes, face, head mesh, limb colours) onto your own character. It only changes your own client:
-- other players keep seeing your real avatar. The source can be someone in the server (their live
-- look, whatever the game gave them) or any Roblox user by name / id (their catalog avatar, built
-- with CreateHumanoidModelFromDescription). Your own look is saved first so "Restore" is exact.
do
local avatarTab = win:Tab("Avatar")
local avPlayer = avatarTab:Section("Copy Player")
local avUser = avatarTab:Section("Copy By Username", "right")

local APPEAR = { Accessory = true, Shirt = true, Pants = true, ShirtGraphic = true, BodyColors = true, CharacterMesh = true }
local JUNK_CLASSES = { "Script", "LocalScript", "ModuleScript", "Sound", "ParticleEmitter", "BillboardGui", "SurfaceGui" }

-- Every joint / constraint inside a clone is removed. A cloned Weld keeps pointing at the ORIGINAL
-- part (e.g. the other player's Head), which welds your character to theirs: you cannot move and
-- you get dragged around whenever they walk. Accessories are re-welded by hand (attachAccessory).
local function tidy(inst)
    local doomed = {}
    for _, d in ipairs(inst:GetDescendants()) do
        local bad = d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint")
        if not bad then
            for _, cls in ipairs(JUNK_CLASSES) do
                if d:IsA(cls) then bad = true break end
            end
        end
        if bad then table.insert(doomed, d) end
    end
    for _, d in ipairs(doomed) do pcall(function() d:Destroy() end) end
end

local function safeClone(inst)
    local was = inst.Archivable
    inst.Archivable = true
    local ok, c = pcall(function() return inst:Clone() end)
    inst.Archivable = was
    if ok and c then tidy(c) return c end
    return nil
end

local DECOR = { Decal = true, Texture = true, SpecialMesh = true, SurfaceAppearance = true }

local function insideAccessory(inst, char)
    local p = inst.Parent
    while p and p ~= char do
        if p:IsA("Accessory") then return true end
        p = p.Parent
    end
    return false
end

local function pathOf(inst, char)
    local names = {}
    local p = inst.Parent
    while p and p ~= char do table.insert(names, 1, p.Name) p = p.Parent end
    return table.concat(names, "/")
end

local function findByPath(char, path)
    local cur = char
    for name in path:gmatch("[^/]+") do
        cur = cur and cur:FindFirstChild(name)
    end
    return cur
end

-- everything that makes a character look like itself, as unparented clones. Games hide things:
-- The Strongest Battlegrounds keeps hair and glasses inside a hidden FakeHead part, so the whole
-- character is searched, not just its direct children.
local function takeSnapshot(char)
    local snap = { items = {}, decor = {}, colors = {} }
    for _, d in ipairs(char:GetDescendants()) do
        if APPEAR[d.ClassName] and not insideAccessory(d, char) then
            local c = safeClone(d)
            if c then table.insert(snap.items, { inst = c, host = pathOf(d, char) }) end
        elseif DECOR[d.ClassName] and d.Parent:IsA("BasePart") and not insideAccessory(d, char) then
            local c = safeClone(d)
            if c then table.insert(snap.decor, { path = pathOf(d, char), inst = c }) end   -- path = the part that carries it
        elseif d:IsA("BasePart") and not insideAccessory(d, char) then
            snap.colors[(pathOf(d, char) ~= "" and (pathOf(d, char) .. "/") or "") .. d.Name] = d.Color
        end
    end
    return snap
end

-- Humanoid:AddAccessory does not weld anything on the client, so the handle is welded by hand to the
-- attachment with the same name (on the part it sat on, else on the head, else anywhere on the character)
local function attachAccessory(acc, host, char)
    local handle = acc:FindFirstChild("Handle")
    local hAtt = handle and handle:FindFirstChildOfClass("Attachment")
    if not hAtt then return end
    local target = host and host:FindFirstChild(hAtt.Name)
    if not (target and target:IsA("Attachment")) then
        local head = char:FindFirstChild("Head")
        target = head and head:FindFirstChild(hAtt.Name)
    end
    if not (target and target:IsA("Attachment")) then
        target = nil
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("Attachment") and d.Name == hAtt.Name and not insideAccessory(d, char) then target = d break end
        end
    end
    if not target then return end
    local w = Instance.new("Weld")
    w.Name = "AccessoryWeld"
    w.Part0, w.Part1 = handle, target.Parent
    w.C0, w.C1 = hAtt.CFrame, target.CFrame
    w.Parent = handle
end

local function applySnapshot(snap)
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (char and hum) then return false end
    -- collect first, destroy after: Destroy() also un-parents every descendant, which would break the walk
    local doomed = {}
    for _, d in ipairs(char:GetDescendants()) do
        if (APPEAR[d.ClassName] and not insideAccessory(d, char))
            or (DECOR[d.ClassName] and d.Parent:IsA("BasePart") and not insideAccessory(d, char)) then
            table.insert(doomed, d)
        end
    end
    for _, d in ipairs(doomed) do pcall(function() d:Destroy() end) end
    for _, e in ipairs(snap.items) do
        local n = e.inst:Clone()
        local host = e.host ~= "" and findByPath(char, e.host) or nil
        n.Parent = (host and host:IsA("BasePart")) and host or char   -- same spot it had on the source
        if n:IsA("Accessory") then attachAccessory(n, host, char) end
    end
    for _, e in ipairs(snap.decor) do
        local part = findByPath(char, e.path)
        if part and part:IsA("BasePart") then e.inst:Clone().Parent = part end
    end
    for path, col in pairs(snap.colors) do
        local p = findByPath(char, path)
        if p and p:IsA("BasePart") then p.Color = col end
    end
    return true
end

local mine       -- snapshot of your own look, taken right before the first copy
local worn       -- snapshot of the look you are currently wearing (nil = your own)
local wornName

local function wear(snap, label)
    if not lp.Character then notify("Avatar", "No character yet", "warn") return end
    if not mine then mine = takeSnapshot(lp.Character) end
    if applySnapshot(snap) then
        worn, wornName = snap, label
        notify("Avatar", "You are now a copy of " .. label, "success")
    end
end

local function restore()
    if not (worn and mine) then notify("Avatar", "You are already yourself", "warn") return end
    applySnapshot(mine)
    worn, wornName, mine = nil, nil, nil
    notify("Avatar", "Your own look is back", "success")
end
onUnload(function() if worn and mine then pcall(applySnapshot, mine) end end)

-- keep the copied look after a respawn (the server hands you a fresh character each time)
connect(lp.CharacterAdded, function(char)
    local keep, snap, label = C.AvatarKeep, worn, wornName
    mine = nil
    if not (keep and snap) then worn, wornName = nil, nil return end
    task.spawn(function()
        char:WaitForChild("Humanoid", 10)
        task.wait(2)                          -- let the game finish dressing the new character
        if lp.Character ~= char or not U.Running then return end
        mine = takeSnapshot(char)
        if applySnapshot(snap) and label then notify("Avatar", "Still a copy of " .. label, "success") end
    end)
end)

local avSelected
local avDD
local function refreshAvatarPlayers()
    if avDD then avDD:SetOptions(playerNames()) end
end
avDD = avPlayer:Dropdown({ Text = "Player", Options = playerNames(), Flag = "AvatarPlayer", NoSave = true,
    Callback = function(v) avSelected = v end })
connect(Players.PlayerAdded, refreshAvatarPlayers)
connect(Players.PlayerRemoving, function() task.defer(refreshAvatarPlayers) end)
avPlayer:Button({ Text = "Refresh Player List", Callback = refreshAvatarPlayers })
avPlayer:Button({ Text = "Copy Avatar", Callback = function()
    local plr = avSelected and Players:FindFirstChild(avSelected)
    if not (plr and plr.Character) then notify("Avatar", "Pick a player that has a character first", "warn") return end
    wear(takeSnapshot(plr.Character), plr.DisplayName)
end })
avPlayer:Button({ Text = "Restore My Avatar", Callback = restore })
toggle(avPlayer, "Keep Look After Respawn", "AvatarKeep", true)

local avName = ""
avUser:TextBox({ Text = "Username or UserId", Placeholder = "e.g. Roblox", Flag = "AvatarName", NoSave = true,
    Callback = function(t) avName = t or "" end })
avUser:Button({ Text = "Copy By Username", Callback = function()
    local name = (avName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then notify("Avatar", "Type a username or UserId first", "warn") return end
    task.spawn(function()
        local id = tonumber(name)
        if not id then
            local ok, res = pcall(function() return Players:GetUserIdFromNameAsync(name) end)
            if not (ok and res) then notify("Avatar", "User '" .. name .. "' was not found", "error") return end
            id = res
        end
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        local ok, model = pcall(function()
            local desc = Players:GetHumanoidDescriptionFromUserId(id)
            return Players:CreateHumanoidModelFromDescription(desc, hum and hum.RigType or Enum.HumanoidRigType.R15)
        end)
        if not (ok and model) then notify("Avatar", "Could not load that avatar (" .. tostring(model) .. ")", "error") return end
        local snap = takeSnapshot(model)
        model:Destroy()
        wear(snap, name)
    end)
end })
avUser:Button({ Text = "Restore My Avatar", Callback = restore })
end   -- avatar tab

Ready()
