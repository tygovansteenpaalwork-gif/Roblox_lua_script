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

-- Joint pairs (world positions) for the skeleton. R6 uses the tops / bottoms of the limbs and torso,
-- R15 the centres of the body parts. Anything missing is simply skipped.
U.skelBones = function(char, hum)
    local out = {}
    local function part(name)
        local p = char:FindFirstChild(name)
        return p and p:IsA("BasePart") and p or nil
    end
    local function top(p) return (p.CFrame * CFrame.new(0, p.Size.Y / 2, 0)).Position end
    local function bottom(p) return (p.CFrame * CFrame.new(0, -p.Size.Y / 2, 0)).Position end
    local function add(a, b) if a and b then out[#out + 1] = { a, b } end end

    if hum.RigType == Enum.HumanoidRigType.R15 then
        local head, ut, lt = part("Head"), part("UpperTorso"), part("LowerTorso")
        add(head and head.Position, ut and ut.Position)
        add(ut and ut.Position, lt and lt.Position)
        for _, side in ipairs({ "Left", "Right" }) do
            local ua, la, hand = part(side .. "UpperArm"), part(side .. "LowerArm"), part(side .. "Hand")
            add(ut and ut.Position, ua and ua.Position)
            add(ua and ua.Position, la and la.Position)
            add(la and la.Position, hand and hand.Position)
            local ul, ll, foot = part(side .. "UpperLeg"), part(side .. "LowerLeg"), part(side .. "Foot")
            add(lt and lt.Position, ul and ul.Position)
            add(ul and ul.Position, ll and ll.Position)
            add(ll and ll.Position, foot and foot.Position)
        end
    else
        local head, torso = part("Head"), part("Torso")
        local la, ra, ll, rl = part("Left Arm"), part("Right Arm"), part("Left Leg"), part("Right Leg")
        if torso then
            local neck, pelvis = top(torso), bottom(torso)
            add(head and head.Position, neck)
            add(neck, pelvis)
            add(la and top(la), ra and top(ra))       -- shoulders
            add(ll and top(ll), rl and top(rl))       -- hips
        end
        for _, name in ipairs({ "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
            local limb = part(name)
            if limb then add(top(limb), bottom(limb)) end
        end
    end
    return out
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
    o.edgeSig = scale .. "|" .. thick
end

local function destroyESP(o)
    for _, key in ipairs({ "hl", "hpBack", "info", "tracer" }) do
        if o[key] then pcall(function() o[key]:Destroy() end) end
    end
    for _, e in ipairs(o.edges or {}) do pcall(function() e:Destroy() end) end
    for _, b in ipairs(o.bones or {}) do pcall(function() b:Destroy() end) end
end

local function hideESP(o)
    o.hl.Enabled = false
    o.hpBack.Visible = false
    o.info.Enabled = false
    o.tracer.Visible = false
    for _, e in ipairs(o.edges) do e.Visible = false end
    for _, b in ipairs(o.bones) do b.Visible = false end
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
function U.EspStats()
    local sets = 0
    for _ in pairs(ESP) do sets += 1 end
    return { sets = sets, folder = #espRoot:GetChildren(), layer = #U.EspLayer:GetChildren(),
             builds = U.EspBuilds, swept = U.EspSwept, log = U.EspLog }
end

connect(RunService.RenderStepped, function()
    if not U.Running then return end
    local c = cam()
    local camPos = c.CFrame.Position
    local vp = c.ViewportSize
    local now = os.clock()

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
                    -- blacklist / whitelist colours win over team colours
                    local listCol = (U.Black[plr.Name] and C.ListBlackColor) or (U.White[plr.Name] and C.ListWhiteColor) or nil
                    local teamCol = listCol or (C.ESPTeamColors and plr.Team and plr.TeamColor.Color)

                    o.hl.Adornee = char
                    o.hl.FillColor = teamCol or C.ESPFillColor
                    o.hl.OutlineColor = C.ESPOutlineColor
                    o.hl.FillTransparency = C.ESPFillTrans
                    o.hl.Enabled = C.ESPChams

                    -- health bar: project the 8 corners of the (invisible or drawn) 3D box to the screen and put
                    -- the bar just left of the leftmost corner, as tall as the box appears on screen
                    o.hpBack.Visible = false
                    if C.ESPHealth then
                        local sx, sy, sz = 4 * C.ESP3DScale, 5.8 * C.ESP3DScale, 2.6 * C.ESP3DScale
                        local cy = -0.3 * C.ESP3DScale
                        local minX, minY, maxY, allOn = math.huge, math.huge, -math.huge, true
                        for xi = -1, 1, 2 do
                            for yi = -1, 1, 2 do
                                for zi = -1, 1, 2 do
                                    local sp, on = screenPoint((root.CFrame * CFrame.new(xi * sx / 2, cy + yi * sy / 2, zi * sz / 2)).Position)
                                    if not on then allOn = false end
                                    minX, minY, maxY = math.min(minX, sp.X), math.min(minY, sp.Y), math.max(maxY, sp.Y)
                                end
                            end
                        end
                        if allOn and maxY - minY > 4 then
                            o.hpBack.Visible = true
                            o.hpBack.Position = UDim2.fromOffset(math.floor(minX - 8), math.floor(minY))
                            o.hpBack.Size = UDim2.fromOffset(4, math.floor(maxY - minY))
                        end
                    end

                    -- 3D box
                    if C.ESP3D then
                        local sig = C.ESP3DScale .. "|" .. C.ESP3DThick
                        if o.edgeSig ~= sig then layoutEdges(o, C.ESP3DScale, C.ESP3DThick) end
                        local col3 = teamCol or C.ESP3DColor
                        for _, e in ipairs(o.edges) do
                            e.Adornee = root
                            e.Color3 = col3
                            e.Visible = true
                        end
                    else
                        for _, e in ipairs(o.edges) do e.Visible = false end
                    end

                    local hasHeld = C.ESPHeld and o.heldName ~= nil
                    o.info.Adornee = root
                    o.info.Enabled = C.ESPName or C.ESPInfo or hasHeld
                    o.nameLabel.Visible = C.ESPName
                    o.nameLabel.TextColor3 = teamCol or C.ESPTextColor
                    o.subLabel.Visible = C.ESPInfo
                    o.subLabel.TextColor3 = C.ESPTextColor
                    o.heldLabel.Visible = hasHeld
                    o.heldLabel.TextColor3 = C.ESPTextColor

                    if now - o.tick > 0.1 then
                        o.tick = now
                        o.nameLabel.Text = plr.DisplayName
                        o.subLabel.Text = string.format("%d st  |  %d hp", dist, hum.Health)
                        local tool = char:FindFirstChildOfClass("Tool")
                        o.heldName = tool and tool.Name or nil
                        o.heldLabel.Text = tool and ("[ " .. tool.Name .. " ]") or ""
                    end

                    -- health bar fill, every frame: grows from the bottom, green (or shifting to red when enabled)
                    local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                    o.hpFill.Size = UDim2.new(1, 0, frac, 0)
                    o.hpFill.BackgroundColor3 = C.ESPHealthShift
                        and Color3.fromRGB(230, 60, 60):Lerp(C.ESPHealthColor, frac) or C.ESPHealthColor

                    -- skeleton
                    if C.ESPSkeleton then
                        local joints = U.skelBones(char, hum)
                        local skelCol = teamCol or C.ESPSkelColor
                        for i, line in ipairs(o.bones) do
                            local pair = joints[i]
                            local a, aOn, b, bOn
                            if pair then
                                a, aOn = screenPoint(pair[1])
                                b, bOn = screenPoint(pair[2])
                            end
                            if pair and aOn and bOn then
                                local d = b - a
                                line.Visible = true
                                line.BackgroundColor3 = skelCol
                                line.Size = UDim2.fromOffset(d.Magnitude, C.ESPSkelWidth)
                                line.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
                                line.Rotation = math.deg(math.atan2(d.Y, d.X))
                            else
                                line.Visible = false
                            end
                        end
                    else
                        for _, line in ipairs(o.bones) do line.Visible = false end
                    end

                    if C.ESPTracers then
                        local sp, on = screenPoint(root.Position)
                        if on then
                            local from = Vector2.new(vp.X / 2, vp.Y)
                            local d = sp - from
                            o.tracer.Visible = true
                            o.tracer.BackgroundColor3 = teamCol or C.ESPTracerColor
                            o.tracer.Size = UDim2.fromOffset(d.Magnitude, C.ESPTracerWidth)
                            o.tracer.Position = UDim2.fromOffset((from.X + sp.X) / 2, (from.Y + sp.Y) / 2)
                            o.tracer.Rotation = math.deg(math.atan2(d.Y, d.X))
                        else
                            o.tracer.Visible = false
                        end
                    else
                        o.tracer.Visible = false
                    end
                end
            end
        end
    end
end)

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

local originalFov
renderLast(function()
    if C.Fullbright then
        Lighting.Brightness = C.FullbrightLevel
        Lighting.ClockTime = C.FullbrightTime
        Lighting.FogEnd = 1e6
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
        Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
    end
    if C.FovEnabled then
        originalFov = originalFov or cam().FieldOfView
        cam().FieldOfView = C.FovValue
    elseif originalFov then
        cam().FieldOfView = originalFov
        originalFov = nil
    end
end)
onUnload(function()
    if originalLighting then for k, val in pairs(originalLighting) do pcall(function() Lighting[k] = val end) end end
    if originalFov then cam().FieldOfView = originalFov end
end)

