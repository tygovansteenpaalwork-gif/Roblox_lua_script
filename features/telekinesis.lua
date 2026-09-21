--[[
    Telekinesis  -  telekinesis.lua
    Pulls loose parts to you and floats them in patterns (Infinity, Ring, Tornado, Galaxy ...). Others see the parts move.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/telekinesis.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "telekinesis", Title = "Telekinesis" })

local C, Players, Ready, RunService, U, UserInputService = ctx.C, ctx.Players, ctx.Ready, ctx.RunService, ctx.U, ctx.UserInputService
local cam, connect, dropdown, keybind, lp, myHumanoid = ctx.cam, ctx.connect, ctx.dropdown, ctx.keybind, ctx.lp, ctx.myHumanoid
local notify, onUnload, rayParams, slider, toggle, win = ctx.notify, ctx.onUnload, ctx.rayParams, ctx.slider, ctx.toggle, ctx.win

local miscTab = win:Tab("Telekinesis")

-- telekinesis --------------------------------------------------------------------------------
-- Every loose (unanchored) part within Range gets pulled to you and floats around you in a pattern.
-- Roblox lets the client closest to a loose part simulate it, and a part you simulate can be moved
-- freely - the server and other players then see it move. Turning the switch off gives every part back
-- (collision restored, physics radius reset). Anchored parts and characters can never be grabbed.

do
local TK_MAX, TK_SIZE, TK_RESCAN, INF_RANGE, CYCLE_TIME = 250, 400, 0.75, 1600, 8
local TAU, GOLDEN = math.pi * 2, math.pi * (3 - math.sqrt(5))
local SHAPES = { "Ring", "Tornado", "Sphere", "Infinity", "Galaxy", "DNA Helix", "Wings", "Cycle" }
local CYCLE = { "Infinity", "Ring", "Galaxy", "Sphere", "Tornado", "DNA Helix", "Wings" }

local tkSec = (U.FeTab or miscTab):Section("Telekinesis", "right")   -- lives on the FE tab (others see the parts move)

local parts, partSet, origCollide = {}, {}, {}   -- assembly roots we hold, lookup, and their old CanCollide
local claimOrig, scanAt, scanCount, fireUntil = nil, 0, 0, 0

-- widen the physics radius so far-away parts are simulated by us; restore the old values afterwards
local function setClaim(on)
    if on then
        if not claimOrig then
            claimOrig = {}
            pcall(function() claimOrig.Max = lp.MaximumSimulationRadius end)
            if gethiddenproperty then pcall(function() claimOrig.Sim = gethiddenproperty(lp, "SimulationRadius") end) end
        end
    elseif claimOrig then
        pcall(function() if claimOrig.Max then lp.MaximumSimulationRadius = claimOrig.Max end end)
        if sethiddenproperty and claimOrig.Sim then pcall(sethiddenproperty, lp, "SimulationRadius", claimOrig.Sim) end
        claimOrig = nil
    end
end

-- only parts we network-own answer to our velocity, and only those are seen moving by other players
local function mine(part) return not isnetworkowner or isnetworkowner(part) end

local function letGo(part, stop)
    local c = origCollide[part]
    origCollide[part] = nil
    if not part.Parent then return end
    if c ~= nil then pcall(function() part.CanCollide = c end) end
    if stop then
        pcall(function()
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
        end)
    end
end

local function releaseAll()
    for _, part in ipairs(parts) do letGo(part, true) end
    table.clear(parts)
    table.clear(partSet)
    scanCount = 0
end

-- the free-moving assembly root a part belongs to, or nil if it is anchored / belongs to a character
local function grabbableRoot(part)
    local root = part.AssemblyRootPart
    if not root or root.Anchored or root.Size.Magnitude > TK_SIZE then return nil end
    if root:IsDescendantOf(cam()) then return nil end
    local model = root:FindFirstAncestorOfClass("Model")
    while model do   -- never anything that belongs to a player or NPC
        if model:FindFirstChildOfClass("Humanoid") then return nil end
        model = model:FindFirstAncestorOfClass("Model")
    end
    return root
end

local function scan(root)
    local range = C.TkRange >= INF_RANGE and math.huge or C.TkRange
    local pos = root.Position

    for i = #parts, 1, -1 do   -- forget parts that were destroyed or got anchored (Range only limits new pickups)
        local part = parts[i]
        if not part.Parent or part.Anchored then
            partSet[part] = nil
            letGo(part, false)
            table.remove(parts, i)
        end
    end

    local seen, found = {}, {}
    local function consider(p)
        local r = grabbableRoot(p)
        if r and not seen[r] and not partSet[r] then
            seen[r] = true
            table.insert(found, { part = r, dist = (r.Position - pos).Magnitude })
        end
    end
    if range <= 500 then
        local ignore = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character then table.insert(ignore, plr.Character) end
        end
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = ignore
        for _, p in ipairs(workspace:GetPartBoundsInRadius(pos, range, params)) do consider(p) end
    else   -- huge ranges: spatial queries are unreliable out there, so walk the whole workspace
        for _, p in ipairs(workspace:GetDescendants()) do
            if p:IsA("BasePart") and not p.Anchored and (range == math.huge or (p.Position - pos).Magnitude <= range) then
                consider(p)
            end
        end
    end
    table.sort(found, function(a, b) return a.dist < b.dist end)

    for _, f in ipairs(found) do
        if #parts >= TK_MAX then   -- full: make room for a part we own by dropping one we don't
            if not mine(f.part) then break end
            local dropped
            for i = #parts, 1, -1 do
                if not mine(parts[i]) then
                    partSet[parts[i]] = nil
                    letGo(parts[i], false)
                    table.remove(parts, i)
                    dropped = true
                    break
                end
            end
            if not dropped then break end
        end
        partSet[f.part] = true
        table.insert(parts, f.part)
    end

    scanCount += 1
    if scanCount == 2 then   -- one report per activation, once ownership had a moment to settle
        if #parts == 0 then
            notify("Telekinesis", "No loose parts in range - anchored parts and characters cannot be moved", "warn")
        else
            local owned = 0
            if isnetworkowner then
                for _, p in ipairs(parts) do if isnetworkowner(p) then owned += 1 end end
                notify("Telekinesis", #parts .. " parts found, " .. owned .. " are yours (only those move for other players)",
                    owned > 0 and "success" or "warn")
            else
                notify("Telekinesis", #parts .. " parts found", "success")
            end
        end
    end
end

-- Where part i of n floats, relative to the centre point above you. right / flat are horizontal camera axes.
local function shapeOffset(shape, i, n, t, r, right, flat)
    local u = (i - 1) / math.max(n - 1, 1)
    if shape == "Ring" then
        local layers = math.ceil(n / 36)
        local perLayer = math.ceil(n / layers)
        local layer, idx = math.floor((i - 1) / perLayer), (i - 1) % perLayer
        local count = math.min(perLayer, n - layer * perLayer)
        local a = t * 1.3 + idx / count * TAU + layer * 0.5
        return right * math.cos(a) * r + flat * math.sin(a) * r + Vector3.yAxis * ((layer - (layers - 1) / 2) * 2.2)
    elseif shape == "Tornado" then
        local a = u * TAU * 4 + t * 3
        local rad = r * (1 + 0.9 * u)
        return right * math.cos(a) * rad + flat * math.sin(a) * rad + Vector3.yAxis * (-2 + u * r * 1.6)
    elseif shape == "Sphere" then
        local yy = 1 - 2 * (i - 0.5) / n
        local rr = math.sqrt(math.max(0, 1 - yy * yy))
        local a = GOLDEN * i + t * 0.8
        return right * (math.cos(a) * rr * r) + flat * (math.sin(a) * rr * r) + Vector3.yAxis * (yy * r)
    elseif shape == "Infinity" then   -- lemniscate, standing upright in front of you, facing the camera
        local a = u * TAU + t * 0.9
        local s = math.sin(a)
        local den = 1 + s * s
        local size = math.max(r * 0.8, 6)
        local z = r + ((i % 3) - 1) * 0.9 + math.sin(t * 2 + i) * 0.3   -- Distance = how far in front of you it hangs
        return right * (size * math.cos(a) / den) + Vector3.yAxis * (2 + size * s * math.cos(a) / den * 1.1) + flat * z
    elseif shape == "Galaxy" then   -- three spiral arms lying flat around you
        local arm = (i - 1) % 3
        local k = math.floor((i - 1) / 3)
        local f = k / math.max(math.ceil(n / 3) - 1, 1)
        local rad = r * (1 + f * 1.1)
        local a = arm / 3 * TAU + f * TAU * 1.1 + t * 0.9
        return right * math.cos(a) * rad + flat * math.sin(a) * rad + Vector3.yAxis * (math.sin(t * 1.5 + f * 6) * 1.2)
    elseif shape == "DNA Helix" then   -- two strands twisting around each other
        local strand = (i - 1) % 2
        local f = math.floor((i - 1) / 2) / math.max(math.ceil(n / 2) - 1, 1)
        local a = f * TAU * 2.5 + t * 2.2 + strand * math.pi
        return right * math.cos(a) * r + flat * math.sin(a) * r + Vector3.yAxis * (-2 + f * r * 2.2)
    else   -- Wings: feathers in three rows behind you, flapping
        local side = (i % 2 == 0) and 1 or -1
        local k = math.floor((i - 1) / 2)
        local row = k % 3
        local cols = math.max(math.ceil(math.ceil(n / 2) / 3), 1)
        local f = (math.floor(k / 3) + 0.5) / cols
        local x = side * (r * 0.5 + f * r * 1.3)
        local y = 1 + f * r * 0.5 - row * r * 0.25 * (1 - 0.5 * f) + math.abs(x) * math.sin(t * 2.6) * 0.22
        return right * x + Vector3.yAxis * y - flat * (3 + r * 0.25 + row * 0.25)
    end
end

toggle(tkSec, "Telekinesis", "TkEnabled", false, function(v)
    if v then
        setClaim(true)
        scanAt, scanCount = 0, 0
    else
        releaseAll()
        setClaim(false)
    end
end)
dropdown(tkSec, "Pattern", "TkShape", SHAPES, "Infinity")
slider(tkSec, "Distance", "TkDist", 4, 200, 16, { Suffix = " st" })
slider(tkSec, "Range", "TkRange", 25, INF_RANGE, 300, { Suffix = " st", MaxLabel = "Infinite" })
keybind(tkSec, "Fire Key", "TkFireKey", Enum.KeyCode.G, function()
    if not C.TkEnabled or #parts == 0 then return end
    local m = UserInputService:GetMouseLocation()
    local ray = cam():ViewportPointToRay(m.X, m.Y)
    rayParams.FilterDescendantsInstances = { lp.Character }
    local res = workspace:Raycast(ray.Origin, ray.Direction * 2000, rayParams)
    local target = res and res.Position or (ray.Origin + ray.Direction * 500)
    for _, part in ipairs(parts) do
        if part.Parent then
            local d = target - part.Position
            if d.Magnitude > 0.1 then part.AssemblyLinearVelocity = d.Unit * 500 end
        end
    end
    fireUntil = os.clock() + 1
end)
tkSec:Button({ Text = "Release All", Callback = function() releaseAll() end })

onUnload(function()
    releaseAll()
    setClaim(false)
end)

local lost = 0
U.TkStats = function()
    local m, anch, gone = 0, 0, 0
    for _, part in ipairs(parts) do
        if not part.Parent then gone += 1 elseif part.Anchored then anch += 1 end
        if part.Parent and mine(part) then m += 1 end
    end
    return { held = #parts, mine = m, anchored = anch, gone = gone, lost = lost }
end

connect(RunService.Heartbeat, function()
    if claimOrig and C.TkEnabled and U.Running then
        pcall(function() lp.MaximumSimulationRadius = 1e9 end)
        if sethiddenproperty then pcall(sethiddenproperty, lp, "SimulationRadius", 1e9) end
    end
end)

-- PreSimulation runs right before the physics step, so the velocities we set are used that same frame
connect(RunService.PreSimulation or RunService.Heartbeat, function(dt)
    if not (C.TkEnabled and U.Running) then return end
    local _, root = myHumanoid()
    if not root then   -- dead or respawning: stop the parts and give collision back so they land instead of falling out of the map
        for _, part in ipairs(parts) do if origCollide[part] ~= nil then letGo(part, true) end end
        return
    end
    local now = os.clock()

    if now - scanAt > TK_RESCAN then
        scanAt = now
        scan(root)
    end
    local n = #parts
    if n == 0 or now < fireUntil then return end

    local shape = C.TkShape
    if shape == "Cycle" then shape = CYCLE[math.floor(now / CYCLE_TIME) % #CYCLE + 1] end
    local look = cam().CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.zAxis
    local right = flat:Cross(Vector3.yAxis)
    local center = root.Position + Vector3.new(0, 2, 0)
    local gain = math.min(18 * math.max(dt, 1 / 240), 0.9) / math.max(dt, 1 / 240)   -- never overshoots on low fps

    for i = 1, n do
        local part = parts[i]
        if not mine(part) then
            if origCollide[part] ~= nil then lost += 1 letGo(part, false) end   -- lost it: give the collision back
            continue
        end
        if origCollide[part] == nil then
            origCollide[part] = part.CanCollide
            part.CanCollide = false   -- so it never shoves or traps you
        end
        local v = (center + shapeOffset(shape, i, n, now, C.TkDist, right, flat) - part.Position) * gain
        if v.Magnitude > 900 then v = v.Unit * 900 end
        part.AssemblyLinearVelocity = v
        part.AssemblyAngularVelocity = Vector3.new(0, 4, 0)
    end
end)
end

Ready()
