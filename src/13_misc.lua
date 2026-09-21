----------------------------------------------------------------------
-- tab: Misc
----------------------------------------------------------------------

local miscTab = win:Tab("Misc")
local perf = miscTab:Section("Performance")
local tools = miscTab:Section("Tools", "right")

local savedQuality, savedShadows
toggle(perf, "FPS Boost", "FpsBoost", false, function(v)
    if v then
        savedShadows = Lighting.GlobalShadows
        pcall(function() savedQuality = settings().Rendering.QualityLevel end)
        Lighting.GlobalShadows = false
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
        pcall(function() workspace.Terrain.Decoration = false end)
    else
        if savedShadows ~= nil then Lighting.GlobalShadows = savedShadows end
        if savedQuality then pcall(function() settings().Rendering.QualityLevel = savedQuality end) end
        pcall(function() workspace.Terrain.Decoration = true end)
    end
end)
if hasFn("setfpscap") then
    slider(perf, "FPS Cap (0 = off)", "FpsCap", 0, 360, 0, { OnChange = function(v) pcall(setfpscap, v) end })
end

tools:Button({ Text = "Load Infinite Yield", Callback = function()
    notify("Infinite Yield", "Loading...")
    task.spawn(function()
        local ok, err = pcall(function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
        end)
        if not ok then notify("Infinite Yield", tostring(err), "error") end
    end)
end })
tools:Button({ Text = "Copy Game Info", Callback = function()
    if hasFn("setclipboard") then
        setclipboard(("PlaceId: %d\nGameId: %d\nJobId: %s"):format(game.PlaceId, game.GameId, game.JobId))
        notify("Copied", "Game info is on your clipboard", "success")
    end
end })

----------------------------------------------------------------------
-- Misc: universal tools (clean visuals, camera, waypoints, stats HUD - work in any game)
----------------------------------------------------------------------

;(function()   -- own function: the main chunk is out of local registers
local uniTab = miscTab   -- these sections live on the Misc tab
local cleanSec = uniTab:Section("Clean Visuals")
local camSec = uniTab:Section("Camera", "right")
local wpSec = uniTab:Section("Waypoints")
local hudSec = uniTab:Section("Stats HUD", "right")

-- clean visuals -------------------------------------------------------------
-- Everything we touch is remembered (weak tables) and put back when the switch goes off.
-- Particles are also made fully transparent, because games often :Emit() them while Enabled is
-- false, which would otherwise still draw.

local EFFECT_CLASSES = {
    BlurEffect = true, DepthOfFieldEffect = true, BloomEffect = true,
    ColorCorrectionEffect = true, SunRaysEffect = true,
}
local effectOrig = setmetatable({}, { __mode = "k" })
local atmoOrig = setmetatable({}, { __mode = "k" })
local vfxOrig = setmetatable({}, { __mode = "k" })
local fogOrig

local function isVfx(inst)
    return inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles")
end

local function hideVfx(inst)
    local saved = vfxOrig[inst]
    if not saved then
        saved = { Enabled = inst.Enabled }
        if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") then saved.Transparency = inst.Transparency end
        vfxOrig[inst] = saved
    end
    inst.Enabled = false
    if saved.Transparency then inst.Transparency = NumberSequence.new(1) end
end

local function applyEffects()
    for _, parent in ipairs({ Lighting, cam() }) do
        if parent then
            for _, inst in ipairs(parent:GetChildren()) do
                if EFFECT_CLASSES[inst.ClassName] then
                    if effectOrig[inst] == nil then effectOrig[inst] = inst.Enabled end
                    if inst.Enabled then inst.Enabled = false end
                end
            end
        end
    end
end

local function restoreEffects()
    for inst, was in pairs(effectOrig) do
        pcall(function() inst.Enabled = was end)
        effectOrig[inst] = nil
    end
end

local function applyFog()
    if not fogOrig then fogOrig = { FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd } end
    Lighting.FogStart, Lighting.FogEnd = 1e6, 1e6
    for _, a in ipairs(Lighting:GetChildren()) do
        if a:IsA("Atmosphere") then
            if not atmoOrig[a] then atmoOrig[a] = { Density = a.Density, Haze = a.Haze } end
            a.Density, a.Haze = 0, 0
        end
    end
end

local function restoreFog()
    if fogOrig then
        pcall(function() Lighting.FogStart, Lighting.FogEnd = fogOrig.FogStart, fogOrig.FogEnd end)
        fogOrig = nil
    end
    for a, saved in pairs(atmoOrig) do
        pcall(function() a.Density, a.Haze = saved.Density, saved.Haze end)
        atmoOrig[a] = nil
    end
end

local function restoreVfx()
    for inst, saved in pairs(vfxOrig) do
        pcall(function()
            inst.Enabled = saved.Enabled
            if saved.Transparency then inst.Transparency = saved.Transparency end
        end)
        vfxOrig[inst] = nil
    end
end

toggle(cleanSec, "Remove Screen Effects", "CleanEffects", false, function(v)
    if v then applyEffects() else restoreEffects() end
end)
toggle(cleanSec, "Remove Fog & Atmosphere", "CleanFog", false, function(v)
    if v then applyFog() else restoreFog() end
end)
toggle(cleanSec, "Remove Particles & Trails", "CleanParticles", false, function(v)
    if not v then restoreVfx() return end
    task.spawn(function()
        local n = 0
        for _, d in ipairs(workspace:GetDescendants()) do
            if not (C.CleanParticles and U.Running) then return end
            if isVfx(d) then hideVfx(d) end
            n += 1
            if n % 3000 == 0 then task.wait() end   -- big maps: do not freeze a frame
        end
    end)
end)
toggle(cleanSec, "No Camera Shake", "CleanShake", false)
onUnload(function() restoreEffects() restoreFog() restoreVfx() end)

connect(workspace.DescendantAdded, function(inst)
    if C.CleanParticles and U.Running and isVfx(inst) then hideVfx(inst) end
end)

local cleanAt = 0
renderLast(function(dt)
    if not U.Running then return end
    if C.CleanShake then
        local hum = myHumanoid()
        if hum and hum.CameraOffset ~= Vector3.zero then hum.CameraOffset = Vector3.zero end
    end
    cleanAt += dt
    if cleanAt < 0.3 then return end
    cleanAt = 0
    -- games switch their own effects back on; keep them off
    if C.CleanEffects then applyEffects() end
    if C.CleanFog then applyFog() end
    if C.CleanParticles then
        for inst in pairs(vfxOrig) do
            if inst.Parent and inst.Enabled then inst.Enabled = false end
        end
    end
end)

-- freecam ---------------------------------------------------------------------
-- The camera detaches from your character and flies freely. Movement keys are swallowed so the
-- character stays put; hold right mouse to look around.

local ContextActionService = game:GetService("ContextActionService")
local FC_KEYS = {
    Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.E, Enum.KeyCode.Q,
    Enum.KeyCode.Space, Enum.KeyCode.LeftControl, Enum.KeyCode.LeftShift,
}
local fc = { pos = Vector3.zero, yaw = 0, pitch = 0, saved = nil }

local function fcStop()
    ContextActionService:UnbindAction(U.FreecamAction)
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    local c = cam()
    if c and fc.saved then
        c.CameraType = fc.saved.Type
        local hum = myHumanoid()
        c.CameraSubject = hum or fc.saved.Subject
    end
    fc.saved = nil
end
onUnload(fcStop)

toggle(camSec, "Freecam", "Freecam", false, function(v)
    if not v then fcStop() return end
    local c = cam()
    fc.saved = { Type = c.CameraType, Subject = c.CameraSubject }
    fc.pos = c.CFrame.Position
    fc.pitch, fc.yaw = c.CFrame:ToOrientation()
    ContextActionService:BindActionAtPriority(U.FreecamAction, function() return Enum.ContextActionResult.Sink end,
        false, Enum.ContextActionPriority.High.Value, table.unpack(FC_KEYS))
end)
slider(camSec, "Freecam Speed", "FreecamSpeed", 5, 300, 40, { Suffix = " st/s" })
slider(camSec, "Look Sensitivity", "FreecamSens", 0.1, 3, 1, { Decimals = 1, Suffix = "x" })

renderLast(function(dt)
    if not (C.Freecam and U.Running) then return end
    local c = cam()
    c.CameraType = Enum.CameraType.Scriptable
    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
        local d = UserInputService:GetMouseDelta()
        fc.yaw -= d.X * 0.003 * C.FreecamSens
        fc.pitch = math.clamp(fc.pitch - d.Y * 0.003 * C.FreecamSens, -1.5, 1.5)
    else
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end

    local rot = CFrame.fromOrientation(fc.pitch, fc.yaw, 0)
    local move = Vector3.zero
    if not UserInputService:GetFocusedTextBox() then
        local function down(key) return UserInputService:IsKeyDown(key) end
        if down(Enum.KeyCode.W) then move += Vector3.new(0, 0, -1) end
        if down(Enum.KeyCode.S) then move += Vector3.new(0, 0, 1) end
        if down(Enum.KeyCode.A) then move += Vector3.new(-1, 0, 0) end
        if down(Enum.KeyCode.D) then move += Vector3.new(1, 0, 0) end
        if down(Enum.KeyCode.E) or down(Enum.KeyCode.Space) then move += Vector3.new(0, 1, 0) end
        if down(Enum.KeyCode.Q) or down(Enum.KeyCode.LeftControl) then move += Vector3.new(0, -1, 0) end
    end
    local speed = C.FreecamSpeed * (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 3 or 1)
    fc.pos += rot:VectorToWorldSpace(move) * speed * math.clamp(dt, 0, 0.1)
    c.CFrame = CFrame.new(fc.pos) * rot
end)

-- unlimited zoom -----------------------------------------------------------------

local zoomOrig
toggle(camSec, "Unlimited Zoom", "ZoomUnlock", false, function(v)
    if v and not zoomOrig then
        zoomOrig = { Max = lp.CameraMaxZoomDistance, Min = lp.CameraMinZoomDistance }
    elseif not v and zoomOrig then
        lp.CameraMaxZoomDistance, lp.CameraMinZoomDistance = zoomOrig.Max, zoomOrig.Min
        zoomOrig = nil
    end
end)
slider(camSec, "Max Zoom", "ZoomMax", 20, 2000, 500, { Suffix = " st" })
onUnload(function()
    if zoomOrig then pcall(function() lp.CameraMaxZoomDistance, lp.CameraMinZoomDistance = zoomOrig.Max, zoomOrig.Min end) end
end)
renderLast(function()
    if not (C.ZoomUnlock and U.Running) then return end
    lp.CameraMaxZoomDistance = C.ZoomMax
    lp.CameraMinZoomDistance = 0
end)

-- waypoints (saved per game when the executor can write files) ------------------------------

local WP_FILE = "TerkanWaypoints_" .. tostring(game.PlaceId) .. ".json"
local waypoints = {}   -- name -> the 12 components of a CFrame
if readfile and isfile then
    pcall(function()
        if isfile(WP_FILE) then waypoints = HttpService:JSONDecode(readfile(WP_FILE)) end
    end)
end
local function saveWaypoints()
    if writefile then pcall(writefile, WP_FILE, HttpService:JSONEncode(waypoints)) end
end
local function wpNames()
    local names = {}
    for name in pairs(waypoints) do table.insert(names, name) end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

local wpName, wpSel = "", nil
local wpDD
wpSec:TextBox({ Text = "Name", Placeholder = "e.g. spawn", Flag = "WaypointName", NoSave = true,
    Callback = function(t) wpName = t or "" end })
wpDD = wpSec:Dropdown({ Text = "Waypoint", Options = wpNames(), Flag = "WaypointSel", NoSave = true,
    Callback = function(v) wpSel = v end })

wpSec:Button({ Text = "Save Current Position", Callback = function()
    local _, root = myHumanoid()
    if not root then notify("Waypoints", "You need a character first", "warn") return end
    local name = wpName:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Spot " .. (#wpNames() + 1) end
    waypoints[name] = { root.CFrame:GetComponents() }
    saveWaypoints()
    wpDD:SetOptions(wpNames())
    notify("Waypoints", "Saved \"" .. name .. "\"", "success")
end })
wpSec:Button({ Text = "Teleport To Waypoint", Callback = function()
    local data = wpSel and waypoints[wpSel]
    local _, root = myHumanoid()
    if not (data and root) then notify("Waypoints", "Pick a waypoint first", "warn") return end
    root.CFrame = CFrame.new(table.unpack(data))
    root.AssemblyLinearVelocity = Vector3.zero
end })
wpSec:Button({ Text = "Delete Waypoint", Callback = function()
    if not (wpSel and waypoints[wpSel]) then notify("Waypoints", "Pick a waypoint first", "warn") return end
    waypoints[wpSel] = nil
    wpSel = nil
    saveWaypoints()
    wpDD:SetOptions(wpNames())
end })

-- stats HUD ------------------------------------------------------------------------

local HUD_CORNERS = {
    ["Top Left"] = { Vector2.new(0, 0), UDim2.new(0, 8, 0, 8) },
    ["Top Right"] = { Vector2.new(1, 0), UDim2.new(1, -8, 0, 8) },
    ["Bottom Left"] = { Vector2.new(0, 1), UDim2.new(0, 8, 1, -8) },
    ["Bottom Right"] = { Vector2.new(1, 1), UDim2.new(1, -8, 1, -8) },
}
local hudGui, hudLbl
local hudTime, hudFrames = 0, 0

local function destroyHud()
    if hudGui then hudGui:Destroy() end
    hudGui, hudLbl = nil, nil
end
onUnload(destroyHud)

local function buildHud()
    hudGui = Instance.new("ScreenGui")
    hudGui.Name = U.rname()
    hudGui.ResetOnSpawn = false
    hudGui.IgnoreGuiInset = true
    hudGui.DisplayOrder = 100
    hudGui.Parent = parentGui()

    hudLbl = Instance.new("TextLabel")
    hudLbl.BackgroundColor3 = Color3.new(0, 0, 0)
    hudLbl.BackgroundTransparency = 0.45
    hudLbl.TextColor3 = Color3.new(1, 1, 1)
    hudLbl.Font = Enum.Font.Code
    hudLbl.TextSize = 14
    hudLbl.AutomaticSize = Enum.AutomaticSize.XY
    hudLbl.Size = UDim2.fromOffset(0, 0)
    hudLbl.Text = "..."
    hudLbl.Parent = hudGui
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
    pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
    pad.Parent = hudLbl
    Instance.new("UICorner", hudLbl).CornerRadius = UDim.new(0, 5)
end

toggle(hudSec, "Show FPS / Ping / Players", "StatsHud", false, function(v) if not v then destroyHud() end end)
dropdown(hudSec, "Corner", "HudCorner", { "Top Left", "Top Right", "Bottom Left", "Bottom Right" }, "Top Right")

connect(RunService.RenderStepped, function(dt)
    if not (C.StatsHud and U.Running) then return end
    if not hudGui then buildHud() end
    hudTime += dt
    hudFrames += 1
    if hudTime < 0.5 then return end
    local fps = math.floor(hudFrames / hudTime + 0.5)
    hudTime, hudFrames = 0, 0

    local ping = "?"
    pcall(function()
        ping = tostring(math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5))
    end)
    local corner = HUD_CORNERS[C.HudCorner] or HUD_CORNERS["Top Right"]
    hudLbl.AnchorPoint, hudLbl.Position = corner[1], corner[2]
    hudLbl.Text = ("FPS %d  |  Ping %s ms  |  Players %d/%d"):format(fps, ping, #Players:GetPlayers(), Players.MaxPlayers)
end)
end)()   -- universal

----------------------------------------------------------------------
-- Misc: CFrame movement, telekinesis, chat spy
----------------------------------------------------------------------

;(function()   -- own function: the main chunk is out of local registers
local cfSec = moveTab:Section("CFrame Speed")   -- these two live on the Movement tab, the rest of this block on Misc
local cfFlySec = moveTab:Section("CFrame Fly & Dash", "right")

local function keyDown(key)
    return not UserInputService:GetFocusedTextBox() and UserInputService:IsKeyDown(key)
end

-- CFrame movement -----------------------------------------------------------------------------
-- Moves the character by editing its CFrame instead of WalkSpeed / velocity, so games that watch
-- WalkSpeed see nothing unusual. Every move is checked against walls first (Stop At Walls) because a
-- CFrame step, unlike physics, would otherwise pass straight through thin geometry.

toggle(cfSec, "CFrame Speed", "CfSpeed", false)
slider(cfSec, "Extra Speed", "CfSpeedValue", 0, 300, 30, { Suffix = " st/s" })
slider(cfSec, "Acceleration Time", "CfAccel", 0, 1, 0.1, { Decimals = 2, Suffix = " s" })
toggle(cfSec, "Only While Holding Key", "CfSpeedHold", false)
keybind(cfSec, "Speed Hold Key", "CfSpeedKey", nil)
slider(cfSec, "Sprint Multiplier", "CfSprint", 1, 5, 2, { Decimals = 1, Suffix = "x" })
keybind(cfSec, "Sprint Key", "CfSprintKey", nil)
toggle(cfSec, "Only On The Ground", "CfGroundOnly", false)
toggle(cfSec, "Stop At Walls", "CfWallCheck", true)

toggle(cfFlySec, "CFrame Fly", "CfFly", false)
slider(cfFlySec, "Fly Speed", "CfFlySpeed", 5, 500, 60, { Suffix = " st/s" })
slider(cfFlySec, "Vertical Multiplier", "CfFlyVert", 0.2, 3, 1, { Decimals = 1, Suffix = "x" })
toggle(cfFlySec, "Fly Toward Camera Pitch", "CfFlyPitch", true)
toggle(cfFlySec, "Face Fly Direction", "CfFlyFace", false)
local doDash   -- defined below, once the dash state exists; the key calls it through this upvalue
keybind(cfFlySec, "Dash Key", "CfDashKey", nil, function() if doDash then doDash() end end)
slider(cfFlySec, "Dash Distance", "CfDashDist", 5, 200, 40, { Suffix = " st" })
slider(cfFlySec, "Dash Time", "CfDashTime", 0.05, 1, 0.15, { Decimals = 2, Suffix = " s" })
slider(cfFlySec, "Dash Cooldown", "CfDashCd", 0, 5, 0.5, { Decimals = 1, Suffix = " s" })
toggle(cfFlySec, "Dash Toward Camera", "CfDashCamera", false)

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.RespectCanCollide = true
local function blocked(root, dir, dist)
    if not C.CfWallCheck or dir.Magnitude < 1e-3 then return false end
    wallParams.FilterDescendantsInstances = { lp.Character }
    return workspace:Raycast(root.Position, dir.Unit * (dist + 1.5), wallParams) ~= nil
end

local function smooth(cur, target, dt)
    local a = C.CfAccel <= 0.001 and 1 or (1 - math.exp(-dt / C.CfAccel))
    return cur:Lerp(target, a)
end

local walkVel, flyVel, flyPos, flyRoot = Vector3.zero, Vector3.zero, nil, nil
local dash = { left = 0, dir = Vector3.zero, cd = 0 }

doDash = function()
    local hum, root = myHumanoid()
    if not (hum and root) or hum.Health <= 0 or dash.cd > 0 then return end
    local dir = hum.MoveDirection
    if C.CfDashCamera then
        local look = cam().CFrame.LookVector
        dir = Vector3.new(look.X, 0, look.Z)
    elseif dir.Magnitude < 0.1 then
        local look = root.CFrame.LookVector
        dir = Vector3.new(look.X, 0, look.Z)
    end
    if dir.Magnitude < 0.01 then return end
    dash.dir, dash.left, dash.cd = dir.Unit, C.CfDashTime, C.CfDashCd + C.CfDashTime
end

renderLast(function(dt)
    if not U.Running or C.Freecam then return end
    dt = math.clamp(dt, 0, 0.1)
    local hum, root = myHumanoid()
    if not (hum and root) or hum.Health <= 0 then flyPos = nil return end
    dash.cd = math.max(0, dash.cd - dt)

    if dash.left > 0 then
        local step = math.min(dt, dash.left)
        dash.left -= step
        local move = dash.dir * (C.CfDashDist / C.CfDashTime) * step
        if not blocked(root, dash.dir, move.Magnitude) then
            root.CFrame += move
            if flyPos then flyPos += move end
        end
        local v = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)   -- do not fall while dashing
    end

    if C.CfFly then
        -- our own authoritative position: physics would otherwise sink us a little every frame
        if flyRoot ~= root or not flyPos or (root.Position - flyPos).Magnitude > 12 then
            flyPos, flyRoot, flyVel = root.Position, root, Vector3.zero
        end
        local dir = Vector3.zero
        if C.CfFlyPitch then
            local cf = cam().CFrame
            if keyDown(Enum.KeyCode.W) then dir += cf.LookVector end
            if keyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
            if keyDown(Enum.KeyCode.D) then dir += cf.RightVector end
            if keyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
        else
            dir = hum.MoveDirection
        end
        if keyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis * C.CfFlyVert end
        if keyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis * C.CfFlyVert end
        if dir.Magnitude > 1 then dir = dir.Unit end

        local speed = C.CfFlySpeed * ((BIND.CfSprintKey and BIND.CfSprintKey:IsDown()) and C.CfSprint or 1)
        flyVel = smooth(flyVel, dir * speed, dt)
        local step = flyVel * dt
        if blocked(root, flyVel, step.Magnitude) then flyVel, step = Vector3.zero, Vector3.zero end
        flyPos += step

        local flat = Vector3.new(dir.X, 0, dir.Z)
        if C.CfFlyFace and flat.Magnitude > 0.1 then
            root.CFrame = CFrame.lookAt(flyPos, flyPos + flat)
        else
            root.CFrame = CFrame.new(flyPos) * root.CFrame.Rotation
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return
    end
    flyPos = nil

    local plainSpeed = (C.SpeedEnabled and not C.CfSpeed) and math.max(C.SpeedValue - 16, 0) or 0   -- the Movement tab's Speed
    if C.CfSpeed or plainSpeed > 0 then
        local held = plainSpeed > 0 or not C.CfSpeedHold or (BIND.CfSpeedKey and BIND.CfSpeedKey:IsDown())
        local dir = hum.MoveDirection
        if not held or (C.CfGroundOnly and hum.FloorMaterial == Enum.Material.Air) then dir = Vector3.zero end
        local speed = plainSpeed > 0 and plainSpeed
            or C.CfSpeedValue * ((BIND.CfSprintKey and BIND.CfSprintKey:IsDown()) and C.CfSprint or 1)
        walkVel = smooth(walkVel, dir * speed, dt)
        if walkVel.Magnitude > 0.05 then
            local move = walkVel * dt
            if not blocked(root, walkVel, move.Magnitude) then root.CFrame += move end
        end
    else
        walkVel = Vector3.zero
    end
end)

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

-- chat spy ------------------------------------------------------------------------------------
-- Logs every chat message this client receives, tagged public / whisper / team, in its own window.
-- It can only show what the server actually sends to you: with the newer TextChatService, whispers
-- between other people are never delivered to your client, so they cannot be seen by any script.

local chatSec = miscTab:Section("Chat Spy")
local chatOpt = miscTab:Section("Chat Spy Options", "right")

local TextChatService = game:GetService("TextChatService")
local chatLog, chatLabels, recentChat = {}, {}, {}
local chatGui, chatFrame, chatList, chatPos
local chatDrag   -- { start = Vector3, from = UDim2 } while the title bar is held

-- The window borrows its look from the menu (sharp corners, 2px accent border, top bar with a divider,
-- RobotoMono). Its colours are read from the live menu a couple of times a second, so switching the
-- theme in Settings switches this window too.
local TEXT_COLOR, FAINT_HEX = Color3.fromRGB(232, 226, 227), "#685a5e"
local TEAM_COLOR = Color3.fromRGB(110, 220, 140)
local chatColors = {
    Accent = Color3.fromRGB(255, 32, 48), Bg = Color3.fromRGB(11, 4, 6),
    BgTop = Color3.fromRGB(19, 5, 8), Border = Color3.fromRGB(96, 14, 24),
}
local chatStroke, chatTop, chatTitle, chatLine   -- window parts that follow the theme
local KIND_TAG = { public = "", private = "[PM] ", team = "[TEAM] " }

local function monoFont(inst, weight)
    local ok = pcall(function()
        inst.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", weight or Enum.FontWeight.Regular)
    end)
    if not ok then inst.Font = Enum.Font.Code end
end

local function readMenuColors()
    local main = win.Main
    if not main then return end
    chatColors.Bg = main.BackgroundColor3
    local s = main:FindFirstChildOfClass("UIStroke")
    if s then chatColors.Accent = s.Color end
    local top = main:FindFirstChild("TopBar")
    if top then
        chatColors.BgTop = top.BackgroundColor3
        for _, child in ipairs(top:GetChildren()) do
            if child:IsA("Frame") and child.Size.Y.Offset == 1 then chatColors.Border = child.BackgroundColor3 end
        end
    end
end

local function kindColor(kind)
    if kind == "private" then return chatColors.Accent end
    if kind == "team" then return TEAM_COLOR end
    return TEXT_COLOR
end

local function applyChatTheme()
    if not chatFrame then return end
    readMenuColors()
    chatFrame.BackgroundColor3 = chatColors.Bg
    chatStroke.Color = chatColors.Accent
    chatTop.BackgroundColor3 = chatColors.BgTop
    chatTitle.TextColor3 = chatColors.Accent
    chatLine.BackgroundColor3 = chatColors.Border
    chatList.ScrollBarImageColor3 = chatColors.Accent
    for _, label in ipairs(chatLabels) do label.TextColor3 = kindColor(label:GetAttribute("Kind")) end
end

local function esc(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function addChatLine(entry)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, -8, 0, 0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.RichText = true
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    monoFont(label)
    label.TextSize = C.ChatSize
    label:SetAttribute("Kind", entry.kind)
    label.TextColor3 = kindColor(entry.kind)
    label.Text = ("<font color=\"%s\">%s</font> %s<b>%s</b>: %s"):format(FAINT_HEX, entry.t, KIND_TAG[entry.kind] or "", esc(entry.name), esc(entry.text))
    label.Parent = chatList
    table.insert(chatLabels, label)
    while #chatLabels > C.ChatMax do table.remove(chatLabels, 1):Destroy() end
    task.defer(function()
        if chatList then chatList.CanvasPosition = Vector2.new(0, chatList.AbsoluteCanvasSize.Y) end
    end)
end

local function destroyChat()
    if chatFrame then chatPos = chatFrame.Position end
    if chatGui then chatGui:Destroy() end
    chatGui, chatFrame, chatList = nil, nil, nil
    chatStroke, chatTop, chatTitle, chatLine = nil, nil, nil, nil
    table.clear(chatLabels)
end
onUnload(destroyChat)

local function buildChat()
    readMenuColors()
    chatGui = Instance.new("ScreenGui")
    chatGui.Name = U.rname()
    chatGui.ResetOnSpawn = false
    chatGui.IgnoreGuiInset = true
    chatGui.DisplayOrder = 99
    chatGui.Parent = parentGui()

    chatFrame = Instance.new("Frame")
    chatFrame.BackgroundColor3 = chatColors.Bg
    chatFrame.BorderSizePixel = 0
    chatFrame.Size = UDim2.fromOffset(C.ChatW, C.ChatH)
    chatFrame.Position = chatPos or UDim2.new(0, 12, 1, -(C.ChatH + 12))
    chatFrame.Parent = chatGui
    chatStroke = Instance.new("UIStroke")
    chatStroke.Color = chatColors.Accent
    chatStroke.Thickness = 2
    chatStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    chatStroke.Parent = chatFrame

    chatTop = Instance.new("Frame")
    chatTop.BackgroundColor3 = chatColors.BgTop
    chatTop.BorderSizePixel = 0
    chatTop.Size = UDim2.new(1, 0, 0, 32)
    chatTop.Active = true
    chatTop.Parent = chatFrame
    chatTop.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            chatDrag = { start = input.Position, from = chatFrame.Position }
        end
    end)

    chatTitle = Instance.new("TextLabel")
    chatTitle.BackgroundTransparency = 1
    chatTitle.Position = UDim2.new(0, 12, 0, 0)
    chatTitle.Size = UDim2.new(0.5, 0, 1, 0)
    chatTitle.Text = "CHAT SPY"
    chatTitle.TextSize = 15
    chatTitle.TextColor3 = chatColors.Accent
    chatTitle.TextXAlignment = Enum.TextXAlignment.Left
    monoFont(chatTitle, Enum.FontWeight.Bold)
    chatTitle.Parent = chatTop

    local hint = Instance.new("TextLabel")
    hint.BackgroundTransparency = 1
    hint.AnchorPoint = Vector2.new(1, 0)
    hint.Position = UDim2.new(1, -12, 0, 0)
    hint.Size = UDim2.new(0.5, 0, 1, 0)
    hint.Text = "drag to move"
    hint.TextSize = 11
    hint.TextColor3 = Color3.fromRGB(104, 90, 94)
    hint.TextXAlignment = Enum.TextXAlignment.Right
    monoFont(hint)
    hint.Parent = chatTop

    chatLine = Instance.new("Frame")   -- divider under the top bar, like the menu's
    chatLine.BackgroundColor3 = chatColors.Border
    chatLine.BackgroundTransparency = 0.35
    chatLine.BorderSizePixel = 0
    chatLine.Position = UDim2.new(0, 0, 1, -1)
    chatLine.Size = UDim2.new(1, 0, 0, 1)
    chatLine.Parent = chatTop

    chatList = Instance.new("ScrollingFrame")
    chatList.BackgroundTransparency = 1
    chatList.BorderSizePixel = 0
    chatList.Position = UDim2.new(0, 8, 0, 38)
    chatList.Size = UDim2.new(1, -16, 1, -46)
    chatList.CanvasSize = UDim2.new()
    chatList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    chatList.ScrollBarThickness = 3
    chatList.ScrollBarImageColor3 = chatColors.Accent
    chatList.Parent = chatFrame
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 3)
    layout.Parent = chatList

    for _, entry in ipairs(chatLog) do addChatLine(entry) end
end

local chatThemeAt = 0
connect(RunService.Heartbeat, function(dt)
    if not chatFrame then return end
    chatThemeAt += dt
    if chatThemeAt < 0.4 then return end
    chatThemeAt = 0
    applyChatTheme()
end)

connect(UserInputService.InputChanged, function(input)
    if chatDrag and chatFrame and input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - chatDrag.start
        chatFrame.Position = UDim2.new(chatDrag.from.X.Scale, chatDrag.from.X.Offset + d.X,
            chatDrag.from.Y.Scale, chatDrag.from.Y.Offset + d.Y)
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then chatDrag = nil end
end)

local function logChat(kind, name, text)
    if not (C.ChatSpy and U.Running) then return end
    if C.ChatPrivateOnly and kind == "public" then return end
    -- the same message can arrive through more than one route
    local key, now = name .. "\0" .. text, os.clock()
    if recentChat[key] and now - recentChat[key] < 1 then return end
    if next(recentChat) and math.random() < 0.05 then
        for k, t in pairs(recentChat) do if now - t > 5 then recentChat[k] = nil end end
    end
    recentChat[key] = now

    local entry = { t = os.date("%H:%M:%S"), kind = kind, name = name, text = text }
    table.insert(chatLog, entry)
    while #chatLog > C.ChatMax do table.remove(chatLog, 1) end
    if chatList then addChatLine(entry) end
    if kind ~= "public" and C.ChatNotify then notify("Chat Spy", name .. ": " .. text) end
end

toggle(chatSec, "Chat Spy", "ChatSpy", false, function(v)
    if v then buildChat() else destroyChat() end
end)
toggle(chatSec, "Only Whispers & Team", "ChatPrivateOnly", false)
toggle(chatSec, "Notify On Whispers & Team", "ChatNotify", true)
chatSec:Button({ Text = "Copy Log", Callback = function()
    if not hasFn("setclipboard") then notify("Chat Spy", "Your executor cannot copy to the clipboard", "warn") return end
    local lines = {}
    for _, e in ipairs(chatLog) do
        table.insert(lines, ("[%s] [%s] %s: %s"):format(e.t, e.kind, e.name, e.text))
    end
    setclipboard(table.concat(lines, "\n"))
    notify("Chat Spy", #lines .. " lines copied", "success")
end })
chatSec:Button({ Text = "Clear Log", Callback = function()
    table.clear(chatLog)
    for _, l in ipairs(chatLabels) do l:Destroy() end
    table.clear(chatLabels)
end })
slider(chatOpt, "Lines Kept", "ChatMax", 20, 300, 80)
slider(chatOpt, "Text Size", "ChatSize", 10, 22, 14)
slider(chatOpt, "Window Width", "ChatW", 240, 800, 380, { OnChange = function(v)
    if chatFrame then chatFrame.Size = UDim2.fromOffset(v, C.ChatH) end
end })
slider(chatOpt, "Window Height", "ChatH", 100, 600, 220, { OnChange = function(v)
    if chatFrame then chatFrame.Size = UDim2.fromOffset(C.ChatW, v) end
end })

-- classic chat: Player.Chatted carries the raw text, so whispers and team chat can be recognised
-- by their command prefix. New chat: TextChatService knows which channel a message came from.
local newChat = false
pcall(function() newChat = TextChatService.ChatVersion == Enum.ChatVersion.TextChatService end)

if not newChat then
    local function hookPlayer(plr)
        if plr == lp then return end
        connect(plr.Chatted, function(msg)
            local low = msg:lower()
            local kind = "public"
            if low:match("^/w ") or low:match("^/whisper ") or low:match("^/msg ") then kind = "private"
            elseif low:match("^/t ") or low:match("^/team ") then kind = "team" end
            logChat(kind, plr.Name, msg)
        end)
    end
    for _, plr in ipairs(Players:GetPlayers()) do hookPlayer(plr) end
    connect(Players.PlayerAdded, hookPlayer)
end
pcall(function()
    connect(TextChatService.MessageReceived, function(message)
        local source = message.TextSource
        local plr = source and Players:GetPlayerByUserId(source.UserId)
        if not plr or plr == lp then return end
        local channel = message.TextChannel and message.TextChannel.Name or ""
        local kind = "public"
        if channel:find("Whisper") then kind = "private" elseif channel:find("Team") then kind = "team" end
        logChat(kind, plr.Name, message.Text)
    end)
end)
end)()   -- cframe / telekinesis / chat spy

