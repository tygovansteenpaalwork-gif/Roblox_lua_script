----------------------------------------------------------------------
-- tab: ESP
----------------------------------------------------------------------

local visTab = win:Tab("ESP")
local esp = visTab:Section("Player ESP")
local espCol = visTab:Section("ESP Colors", "right")
local world = visTab:Section("View", "right")

toggle(esp, "Enabled", "ESPEnabled", false)
toggle(esp, "Box (3D)", "ESP3D", true)
toggle(esp, "Names", "ESPName", true)
toggle(esp, "Distance & Health", "ESPInfo", true)
toggle(esp, "Held Item", "ESPHeld", true)
toggle(esp, "Health Bar", "ESPHealth", true)
toggle(esp, "Skeleton", "ESPSkeleton", true)
toggle(esp, "Chams", "ESPChams", false)
toggle(esp, "Tracers", "ESPTracers", false)
toggle(esp, "Team Check", "ESPTeam", false)
-- lobby / waiting-room / spectator rigs: fully see-through, or parked far under the map (Arsenal keeps dead and
-- respawning players ~450 studs below the arena). Drawing them put names and lines where nobody is.
toggle(esp, "Skip Hidden Rigs", "ESPNoHidden", true)
slider(esp, "Max Distance", "ESPDist", 100, 5000, 1500, { Suffix = " st" })

toggle(espCol, "Use Team Colors", "ESPTeamColors", false)
color(espCol, "Box", "ESP3DColor", Color3.fromRGB(255, 60, 60))
slider(espCol, "Box Scale", "ESP3DScale", 0.6, 1.8, 1, { Decimals = 2 })
slider(espCol, "Box Line Width", "ESP3DThick", 0.02, 0.3, 0.08, { Decimals = 2 })
color(espCol, "Name Text", "ESPTextColor", Color3.fromRGB(255, 255, 255))
color(espCol, "Chams Fill", "ESPFillColor", Color3.fromRGB(255, 60, 60))
color(espCol, "Chams Outline", "ESPOutlineColor", Color3.fromRGB(255, 255, 255))
color(espCol, "Tracer", "ESPTracerColor", Color3.fromRGB(255, 60, 60))
color(espCol, "Skeleton", "ESPSkelColor", Color3.fromRGB(255, 255, 255))
slider(espCol, "Skeleton Width", "ESPSkelWidth", 1, 4, 1.5, { Decimals = 1, Suffix = " px" })
color(espCol, "Health Bar", "ESPHealthColor", Color3.fromRGB(70, 220, 90))
toggle(espCol, "Health Bar Shifts To Red When Low", "ESPHealthShift", false)
color(espCol, "Whitelisted Player", "ListWhiteColor", Color3.fromRGB(80, 200, 255))
color(espCol, "Blacklisted Player", "ListBlackColor", Color3.fromRGB(255, 200, 0))
slider(espCol, "Chams Transparency", "ESPFillTrans", 0, 1, 0.55, { Decimals = 2 })
slider(espCol, "Tracer Width", "ESPTracerWidth", 1, 6, 1.5, { Decimals = 1, Suffix = " px" })

local espRoot = Instance.new("Folder")
espRoot.Name = U.rname()
espRoot.Parent = parentGui()
onUnload(function() espRoot:Destroy() end)

-- all 2D ESP frames (health bar, skeleton, tracer) live in one container of their own, so anything in it that no live
-- ESP object owns can be recognised and removed (the overlay itself is shared with other features)
U.EspLayer = Instance.new("Frame")
U.EspLayer.Name = U.rname()
U.EspLayer.BackgroundTransparency = 1
U.EspLayer.BorderSizePixel = 0
U.EspLayer.Size = UDim2.fromScale(1, 1)
U.EspLayer.Parent = overlay

local ESP = {}

local function frame(parent, props)
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    for k, v in pairs(props) do f[k] = v end
    f.Parent = parent
    return f
end

local function label(parent, props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.GothamBold
    l.TextSize = 13
    l.TextStrokeTransparency = 0.35
    l.TextStrokeColor3 = Color3.new(0, 0, 0)
    for k, v in pairs(props) do l[k] = v end
    l.Parent = parent
    return l
end

-- Joint world positions for the skeleton, keyed by name (R6 names are synthetic: limb tops / bottoms
-- rather than real instances) plus a fixed list of bone connections per rig. Keying by name lets the
-- ESP loop project each joint on screen ONCE per frame and reuse it for every bone touching it, instead
-- of projecting both endpoints of every bone separately (most joints are shared by 2+ bones).
local R15_JOINT_PARTS = {
    "Head", "UpperTorso", "LowerTorso",
    "LeftUpperArm", "LeftLowerArm", "LeftHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperArm", "RightLowerArm", "RightHand", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}
local R15_BONES = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}
local R6_BONES = {
    { "Head", "Neck" }, { "Neck", "Pelvis" },
    { "LeftShoulder", "RightShoulder" }, { "LeftHip", "RightHip" },
    { "LeftShoulder", "LeftElbow" }, { "RightShoulder", "RightElbow" },
    { "LeftHip", "LeftAnkle" }, { "RightHip", "RightAnkle" },
}

-- The joint PARTS are looked up once a second per character (15 FindFirstChild calls per player per frame cost ~1.8 ms
-- per frame in Arsenal, whose characters have ~60 children); their positions are read every frame into a reused table.
local R6_LIMBS = { Head = "Head", Torso = "Torso", LA = "Left Arm", RA = "Right Arm", LL = "Left Leg", RL = "Right Leg" }
U.skelCache = setmetatable({}, { __mode = "k" })
U.skelJoints = function(char, hum)
    local now = os.clock()
    local sc = U.skelCache[char]
    if not sc or now - sc.at > 1 then
        local r15 = hum.RigType == Enum.HumanoidRigType.R15
        local parts = {}
        for key, name in pairs(r15 and R15_JOINT_PARTS or R6_LIMBS) do
            local p = char:FindFirstChild(name)
            if p and p:IsA("BasePart") then parts[r15 and name or key] = p end
        end
        sc = { at = now, r15 = r15, parts = parts, pos = sc and sc.pos or {} }
        U.skelCache[char] = sc
    end
    local pos, parts = sc.pos, sc.parts
    table.clear(pos)
    if sc.r15 then
        for name, p in pairs(parts) do pos[name] = p.Position end
        return pos, R15_BONES
    end
    local function ends(p)
        local cf, h = p.CFrame, p.Size.Y / 2
        return cf:PointToWorldSpace(Vector3.new(0, h, 0)), cf:PointToWorldSpace(Vector3.new(0, -h, 0))
    end
    if parts.Head then pos.Head = parts.Head.Position end
    if parts.Torso then pos.Neck, pos.Pelvis = ends(parts.Torso) end
    if parts.LA then pos.LeftShoulder, pos.LeftElbow = ends(parts.LA) end
    if parts.RA then pos.RightShoulder, pos.RightElbow = ends(parts.RA) end
    if parts.LL then pos.LeftHip, pos.LeftAnkle = ends(parts.LL) end
    if parts.RL then pos.RightHip, pos.RightAnkle = ends(parts.RL) end
    return pos, R6_BONES
end

-- why the ESP set of a player was (re)built - kept for U.EspStats(), to see what makes the number of sets grow
U.EspBuilds, U.EspSwept, U.EspLog = 0, 0, {}

local function buildESP(plr, why)
    local o = { plr = plr, tick = 0 }
    U.EspBuilds += 1
    table.insert(U.EspLog, ("%.1f %s %s"):format(os.clock() % 10000, plr.Name, why or "new"))
    if #U.EspLog > 20 then table.remove(U.EspLog, 1) end

    o.hl = Instance.new("Highlight")
    o.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    o.hl.Enabled = false
    o.hl.Parent = espRoot

    -- health bar: a dark track just left of the box, the fill grows from the bottom up. It is a plain 2D
    -- frame on the overlay, placed every frame from the projected corners of the 3D box (a BillboardGui
    -- carrying only frames did not render at all, so this cannot go missing)
    o.hpBack = frame(U.EspLayer, {
        Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(4, 10), Visible = false,
        BackgroundColor3 = Color3.fromRGB(15, 15, 15), BackgroundTransparency = 0.15,
    })
    local hpStroke = Instance.new("UIStroke")
    hpStroke.Color = Color3.new(0, 0, 0)
    hpStroke.Thickness = 1
    hpStroke.Parent = o.hpBack
    o.hpFill = frame(o.hpBack, {
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(70, 220, 90),
    })

    -- skeleton: up to 14 thin 2D lines between joints, drawn on the overlay like the tracer
    o.bones = {}
    for i = 1, 14 do
        o.bones[i] = frame(U.EspLayer, { AnchorPoint = Vector2.new(0.5, 0.5), Visible = false })
    end

    -- text stack above the head; hidden labels take no space (bottom aligned)
    o.info = Instance.new("BillboardGui")
    o.info.AlwaysOnTop = true
    o.info.LightInfluence = 0
    o.info.Size = UDim2.fromOffset(220, 48)
    o.info.StudsOffset = Vector3.new(0, 4.2, 0)
    o.info.ResetOnSpawn = false
    o.info.Enabled = false
    o.info.Parent = espRoot
    local stack = Instance.new("UIListLayout")
    stack.SortOrder = Enum.SortOrder.LayoutOrder
    stack.VerticalAlignment = Enum.VerticalAlignment.Bottom
    stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
    stack.Parent = o.info
    o.nameLabel = label(o.info, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1 })
    o.subLabel = label(o.info, {
        Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 2, Font = Enum.Font.Gotham, TextSize = 12,
    })
    o.heldLabel = label(o.info, {
        Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 3, Font = Enum.Font.Gotham, TextSize = 12,
    })

    -- real 3D box: 12 thin edges adorned straight onto the root part (no extra parts in the
    -- workspace). Fixed proportions on purpose - the true bounding box balloons with tools.
    o.edges = {}
    for i = 1, 12 do
        local e = Instance.new("BoxHandleAdornment")
        e.AlwaysOnTop = true
        e.ZIndex = 1
        e.Transparency = 0
        e.Visible = false
        e.Parent = espRoot
        o.edges[i] = e
    end

    o.tracer = frame(U.EspLayer, { AnchorPoint = Vector2.new(0.5, 0.5), Visible = false })
    return o
end

local function layoutEdges(o, scale, thick)
    local sx, sy, sz = 4 * scale, 5.8 * scale, 2.6 * scale
    local cy = -0.3 * scale
    local i = 0
    local function put(size, offset)
        i += 1
        o.edges[i].Size = size
        o.edges[i].CFrame = CFrame.new(offset)
    end
    for _, y in ipairs({ -1, 1 }) do
        for _, z in ipairs({ -1, 1 }) do put(Vector3.new(sx, thick, thick), Vector3.new(0, cy + y * sy / 2, z * sz / 2)) end
    end
    for _, x in ipairs({ -1, 1 }) do
        for _, z in ipairs({ -1, 1 }) do put(Vector3.new(thick, sy, thick), Vector3.new(x * sx / 2, cy, z * sz / 2)) end
    end
    for _, x in ipairs({ -1, 1 }) do
        for _, y in ipairs({ -1, 1 }) do put(Vector3.new(thick, thick, sz), Vector3.new(x * sx / 2, cy + y * sy / 2, 0)) end
    end
end

local function destroyESP(o)
    for _, key in ipairs({ "hl", "hpBack", "info", "tracer" }) do
        if o[key] then pcall(function() o[key]:Destroy() end) end
    end
    for _, e in ipairs(o.edges or {}) do pcall(function() e:Destroy() end) end
    for _, b in ipairs(o.bones or {}) do pcall(function() b:Destroy() end) end
end

-- hidden once, not re-hidden every frame while the player stays off the ESP
local function hideESP(o)
    if o.isHidden then return end
    o.isHidden = true
    U.put(o.hl, "Enabled", false)
    U.put(o.hpBack, "Visible", false)
    U.put(o.info, "Enabled", false)
    U.put(o.tracer, "Visible", false)
    for _, e in ipairs(o.edges) do U.put(e, "Visible", false) end
    for _, b in ipairs(o.bones) do U.put(b, "Visible", false) end
end

connect(Players.PlayerRemoving, function(plr)
    if ESP[plr] then destroyESP(ESP[plr]) ESP[plr] = nil end
end)
onUnload(function() for _, o in pairs(ESP) do destroyESP(o) end table.clear(ESP) end)

-- Self-healing: once a second, drop the sets of players who are gone or whose instances were destroyed, and destroy
-- everything in the ESP folder / layer that no live set owns. Whatever the cause of a leak, it cannot pile up.
function U.EspSweep()
    for plr, o in pairs(ESP) do
        if not plr.Parent then
            destroyESP(o) ESP[plr] = nil
        elseif o.hl.Parent ~= espRoot or o.hpBack.Parent ~= U.EspLayer then
            destroyESP(o) ESP[plr] = nil   -- rebuilt on the next frame (reason "orphaned")
            U.EspOrphaned = plr
        end
    end
    local live = {}
    for _, o in pairs(ESP) do
        live[o.hl], live[o.info], live[o.hpBack], live[o.tracer] = true, true, true, true
        for _, e in ipairs(o.edges) do live[e] = true end
        for _, b in ipairs(o.bones) do live[b] = true end
    end
    local removed = 0
    for _, box in ipairs({ espRoot, U.EspLayer }) do
        for _, child in ipairs(box:GetChildren()) do
            if not live[child] then child:Destroy() removed += 1 end
        end
    end
    U.EspSwept += removed
    return removed
end

-- for debugging: how many ESP sets exist, how many instances they hold, how often they were built / swept
-- A point on screen, but only when it is clearly in front of the camera. A point just in front of the lens
-- (a player standing inside / right next to you) projects to thousands of pixels, which drew huge broken lines.
function U.espPoint(pos)
    local v = (U.espCam or cam()):WorldToViewportPoint(pos)
    return Vector2.new(v.X, v.Y), v.Z > 1
end

-- see "Skip Hidden Rigs": invisible, or more than 250 studs below your own character
function U.espHidden(char, root)
    if U.isInvisible(char) then return true end
    local me = U.espMeRoot
    return me ~= nil and root.Position.Y < me.Position.Y - 250
end

function U.EspStats()
    local sets = 0
    for _ in pairs(ESP) do sets += 1 end
    return { sets = sets, folder = #espRoot:GetChildren(), layer = #U.EspLayer:GetChildren(),
             builds = U.EspBuilds, swept = U.EspSwept, log = U.EspLog }
end

-- The 2D parts (tracers, health bars, skeleton) must be projected with exactly the camera the frame is drawn with,
-- or they hang beside the character. So they are drawn at PreRender, the last moment before drawing: after the
-- aimbot / rage turned the camera, and after games that set their own field of view late in the frame (Arsenal
-- puts it back to 70 after RenderStepped - with Custom FOV on, the ESP used to project with 120 and slid inwards).
-- Custom FOV is applied here once more first, so it really is the field of view the frame is drawn with.
local function drawESP()
    if not U.Running then return end
    if U.applyFov then U.applyFov() end
    -- ESP off: hide every set once, then skip the whole player loop until it is switched on again
    if not C.ESPEnabled then
        if not U.espAllHidden then
            for _, o in pairs(ESP) do hideESP(o) end
            U.espAllHidden = true
        end
        return
    end
    U.espAllHidden = false
    local c = cam()
    U.espCam = c
    local _, _, meRoot = charOf(lp, true)
    U.espMeRoot = meRoot
    local camCF = c.CFrame
    local camPos, camRight = camCF.Position, camCF.RightVector
    local vp = c.ViewportSize
    local now = os.clock()
    local put = U.put

    if now - (U.EspSweepAt or 0) > 1 then
        U.EspSweepAt = now
        U.EspSweep()
    end

    for _, e in ipairs(U.Others()) do
        local plr = e.plr
        do
            local char, hum, root = e.char, e.hum, e.root
            if not (hum and root) or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then char = nil end
            local show = C.ESPEnabled and char ~= nil
            if show and C.ESPTeam and sameTeam(plr) then show = false end
            if show and C.ESPNoHidden and U.espHidden(char, root) then show = false end
            local dist = show and (root.Position - camPos).Magnitude or 0
            if show and dist > C.ESPDist then show = false end

            local o = ESP[plr]
            if show and not o then
                o = buildESP(plr, U.EspOrphaned == plr and "orphaned" or "new")
                if U.EspOrphaned == plr then U.EspOrphaned = nil end
                ESP[plr] = o
            end
            if o then
                if not show then
                    hideESP(o)
                else
                    o.isHidden = false
                    -- blacklist / whitelist colours win over team colours
                    local listCol = (U.Black[plr.Name] and C.ListBlackColor) or (U.White[plr.Name] and C.ListWhiteColor) or nil
                    local teamCol = listCol or (C.ESPTeamColors and plr.Team and plr.TeamColor.Color)

                    put(o.hl, "Adornee", char)
                    put(o.hl, "FillColor", teamCol or C.ESPFillColor)
                    put(o.hl, "OutlineColor", C.ESPOutlineColor)
                    put(o.hl, "FillTransparency", C.ESPFillTrans)
                    put(o.hl, "Enabled", C.ESPChams)

                    -- health bar: project the 8 corners of the (invisible or drawn) 3D box to the screen and put
                    -- the bar just left of the leftmost corner, as tall as the box appears on screen
                    local hpShown = false
                    if C.ESPHealth then
                        -- the left edge of the box as the camera sees it: 2 projections instead of all 8 corners
                        local sc = C.ESP3DScale
                        local mid = root.Position + Vector3.new(0, -0.3 * sc, 0) - camRight * (2 * sc)
                        local up = Vector3.new(0, 2.9 * sc, 0)
                        local top, on1 = U.espPoint(mid + up)
                        local bottom, on2 = U.espPoint(mid - up)
                        local minX, minY, maxY = math.min(top.X, bottom.X), math.min(top.Y, bottom.Y), math.max(top.Y, bottom.Y)
                        if on1 and on2 and maxY - minY > 4 then
                            hpShown = true
                            put(o.hpBack, "Position", UDim2.fromOffset(math.floor(minX - 8), math.floor(minY)))
                            put(o.hpBack, "Size", UDim2.fromOffset(4, math.floor(maxY - minY)))
                            -- fill: grows from the bottom, green (or shifting to red when enabled)
                            local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                            put(o.hpFill, "Size", UDim2.new(1, 0, math.floor(frac * 100) / 100, 0))
                            put(o.hpFill, "BackgroundColor3", C.ESPHealthShift
                                and Color3.fromRGB(230, 60, 60):Lerp(C.ESPHealthColor, math.floor(frac * 20) / 20) or C.ESPHealthColor)
                        end
                    end
                    put(o.hpBack, "Visible", hpShown)

                    -- 3D box
                    if C.ESP3D then
                        if o.edgeScale ~= C.ESP3DScale or o.edgeThick ~= C.ESP3DThick then
                            o.edgeScale, o.edgeThick = C.ESP3DScale, C.ESP3DThick
                            layoutEdges(o, C.ESP3DScale, C.ESP3DThick)
                        end
                        local col3 = teamCol or C.ESP3DColor
                        for _, e in ipairs(o.edges) do
                            put(e, "Adornee", root)
                            put(e, "Color3", col3)
                            put(e, "Visible", true)
                        end
                    else
                        for _, e in ipairs(o.edges) do put(e, "Visible", false) end
                    end

                    local hasHeld = C.ESPHeld and o.heldName ~= nil
                    put(o.info, "Adornee", root)
                    put(o.info, "Enabled", C.ESPName or C.ESPInfo or hasHeld)
                    put(o.nameLabel, "Visible", C.ESPName)
                    put(o.nameLabel, "TextColor3", teamCol or C.ESPTextColor)
                    put(o.subLabel, "Visible", C.ESPInfo)
                    put(o.subLabel, "TextColor3", C.ESPTextColor)
                    put(o.heldLabel, "Visible", hasHeld)
                    put(o.heldLabel, "TextColor3", C.ESPTextColor)

                    if now - o.tick > 0.1 then
                        o.tick = now
                        put(o.nameLabel, "Text", plr.DisplayName)
                        put(o.subLabel, "Text", string.format("%d st  |  %d hp", dist, hum.Health))
                        local tool = char:FindFirstChildOfClass("Tool")
                        o.heldName = tool and tool.Name or nil
                        put(o.heldLabel, "Text", tool and ("[ " .. tool.Name .. " ]") or "")
                    end

                    -- skeleton: project each joint once (many bones share a joint - shoulders/hips/elbows...)
                    -- and reuse it for every bone touching it; the projection table is reused, not rebuilt every frame
                    if C.ESPSkeleton then
                        local joints, bones = U.skelJoints(char, hum)
                        local skelCol = teamCol or C.ESPSkelColor
                        local proj = o.proj or {}
                        o.proj = proj
                        table.clear(proj)
                        for i, line in ipairs(o.bones) do
                            local pair = bones[i]
                            local a, b
                            if pair then
                                for k = 1, 2 do
                                    local name = pair[k]
                                    local cached = proj[name]
                                    if cached == nil then
                                        local p = joints[name]
                                        if p then
                                            local sp, on = U.espPoint(p)
                                            cached = on and sp or false
                                        else
                                            cached = false
                                        end
                                        proj[name] = cached
                                    end
                                    if k == 1 then a = cached else b = cached end
                                end
                            end
                            if a and b then
                                local d = b - a
                                put(line, "Visible", true)
                                put(line, "BackgroundColor3", skelCol)
                                put(line, "Size", UDim2.fromOffset(math.floor(d.Magnitude + 0.5), C.ESPSkelWidth))
                                put(line, "Position", UDim2.fromOffset(math.floor((a.X + b.X) / 2), math.floor((a.Y + b.Y) / 2)))
                                put(line, "Rotation", math.floor(math.deg(math.atan2(d.Y, d.X)) * 2) / 2)
                            else
                                put(line, "Visible", false)
                            end
                        end
                    else
                        for _, line in ipairs(o.bones) do put(line, "Visible", false) end
                    end

                    local tracerShown = false
                    if C.ESPTracers then
                        local sp, on = U.espPoint(root.Position)
                        if on then
                            tracerShown = true
                            local fx, fy = vp.X / 2, vp.Y
                            local dx, dy = sp.X - fx, sp.Y - fy
                            put(o.tracer, "BackgroundColor3", teamCol or C.ESPTracerColor)
                            put(o.tracer, "Size", UDim2.fromOffset(math.floor(math.sqrt(dx * dx + dy * dy) + 0.5), C.ESPTracerWidth))
                            put(o.tracer, "Position", UDim2.fromOffset(math.floor((fx + sp.X) / 2), math.floor((fy + sp.Y) / 2)))
                            put(o.tracer, "Rotation", math.floor(math.deg(math.atan2(dy, dx)) * 2) / 2)
                        end
                    end
                    put(o.tracer, "Visible", tracerShown)
                end
            end
        end
    end
end
if RunService.PreRender then
    connect(RunService.PreRender, drawESP)
else
    connect(RunService.RenderStepped, drawESP)
end

-- view -----------------------------------------------------------------

local originalLighting
toggle(world, "Fullbright", "Fullbright", false, function(v)
    if v and not originalLighting then
        originalLighting = {
            Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd,
            GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
        }
    elseif not v and originalLighting then
        for k, val in pairs(originalLighting) do pcall(function() Lighting[k] = val end) end
        originalLighting = nil
    end
end)
slider(world, "Fullbright Brightness", "FullbrightLevel", 1, 5, 2, { Decimals = 1 })
slider(world, "Fullbright Time Of Day", "FullbrightTime", 0, 24, 14, { Decimals = 1, Suffix = " h" })
toggle(world, "Custom FOV", "FovEnabled", false)
slider(world, "Field of View", "FovValue", 30, 120, 90, { Suffix = "°" })

-- Custom FOV: set at RenderPriority.Last (so the rest of the frame sees it) and again right before drawing (see drawESP),
-- because some games put their own field of view back late in the frame
function U.applyFov()
    if C.FovEnabled then
        U.origFov = U.origFov or cam().FieldOfView
        cam().FieldOfView = C.FovValue
    elseif U.origFov then
        cam().FieldOfView = U.origFov
        U.origFov = nil
    end
end
local FULLBRIGHT_AMBIENT = Color3.fromRGB(178, 178, 178)
renderLast(function()
    if C.Fullbright then
        -- written every frame on purpose: the engine skips a write of an unchanged value itself, which measured
        -- ~10x cheaper than reading the value first to compare (a read allocates a new Color3)
        Lighting.Brightness = C.FullbrightLevel
        Lighting.ClockTime = C.FullbrightTime
        Lighting.FogEnd = 1e6
        Lighting.GlobalShadows = false
        Lighting.Ambient = FULLBRIGHT_AMBIENT
        Lighting.OutdoorAmbient = FULLBRIGHT_AMBIENT
    end
    U.applyFov()
end)
onUnload(function()
    if originalLighting then for k, val in pairs(originalLighting) do pcall(function() Lighting[k] = val end) end end
    if U.origFov then cam().FieldOfView = U.origFov end
end)

