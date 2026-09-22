--[[
    Cursor  -  cursor.lua
    Custom crosshair with styles, rainbow, animations and an 'aiming at' label.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/cursor.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "cursor", Title = "Cursor" })

local C, Players, Ready, U, UserInputService, cam = ctx.C, ctx.Players, ctx.Ready, ctx.U, ctx.UserInputService, ctx.cam
local charOf, color, cursorOverMenu, dropdown, lp, onUnload = ctx.charOf, ctx.color, ctx.cursorOverMenu, ctx.dropdown, ctx.lp, ctx.onUnload
local overlay, rayParams, renderLast, slider, toggle, viewportCenter = ctx.overlay, ctx.rayParams, ctx.renderLast, ctx.slider, ctx.toggle, ctx.viewportCenter
local win = ctx.win

local rageTarget, aimTarget

local curTab = win:Tab("Cursor")
local cur = curTab:Section("Crosshair")
local curLook = curTab:Section("Look", "right")
local curTxt = curTab:Section("Target Label", "right")

local CURSOR_STYLES = { "Cross + Dot", "Cross", "X", "Star", "Circle + Dot", "Circle", "Dot" }
local CURSOR_ANIMS = { "None", "Pulse", "Heartbeat", "Shrink On Target", "Grow On Target" }

toggle(cur, "Custom Cursor", "CursorEnabled", false)
dropdown(cur, "Style", "CursorStyle", CURSOR_STYLES, "Cross + Dot")
dropdown(cur, "Position", "CursorPos", { "Follow Mouse", "Screen Center" }, "Follow Mouse")
toggle(cur, "Dashed Lines", "CursorDashed", false)
toggle(cur, "Outline", "CursorOutline", true)
toggle(cur, "Hide System Cursor", "CursorHideSys", true)

toggle(curLook, "Rainbow", "CursorRainbow", false)
slider(curLook, "Rainbow Speed", "CursorRainbowSpeed", 0.05, 2, 0.3, { Decimals = 2 })
color(curLook, "Color", "CursorColor", Color3.fromRGB(255, 32, 48))
slider(curLook, "Size", "CursorSize", 4, 60, 12, { Suffix = " px" })
slider(curLook, "Line Width", "CursorThick", 1, 8, 2, { Suffix = " px" })
slider(curLook, "Gap", "CursorGap", 0, 30, 4, { Suffix = " px" })
slider(curLook, "Dot Size", "CursorDot", 2, 20, 4, { Suffix = " px" })
-- a soft light around the crosshair (and the target name) in the cursor's own colour, rainbow included
toggle(curLook, "Glow", "CursorGlow", false)
slider(curLook, "Glow Size", "CursorGlowSize", 2, 16, 6, { Suffix = " px" })
slider(curLook, "Rotation Speed", "CursorSpin", 0, 720, 0, { Suffix = "°/s" })
dropdown(curLook, "Animation", "CursorAnim", CURSOR_ANIMS, "None")
slider(curLook, "Animation Speed", "CursorAnimSpeed", 0.2, 4, 1.2, { Decimals = 1, Suffix = "/s" })
slider(curLook, "Animation Amount", "CursorAnimAmount", 0.05, 1, 0.3, { Decimals = 2 })

toggle(curTxt, "Show Target Name", "CursorLabel", true)
dropdown(curTxt, "Target Source", "CursorSource", { "Auto", "Under Crosshair" }, "Auto")
toggle(curTxt, "Show Distance & HP", "CursorLabelInfo", false)
slider(curTxt, "Text Size", "CursorLabelSize", 10, 28, 14)
toggle(curTxt, "Same Color As Cursor", "CursorLabelSame", true)
color(curTxt, "Text Color", "CursorLabelColor", Color3.fromRGB(255, 255, 255))
dropdown(curTxt, "Text Animation", "CursorLabelAnim", { "None", "Pulse", "Pop", "Fade" }, "None")

-- what each style is made of: arm angles (degrees), plus a centre dot and/or a ring
local STYLE_PARTS = {
    ["Cross + Dot"]  = { arms = { 0, 90, 180, 270 }, dot = true },
    ["Cross"]        = { arms = { 0, 90, 180, 270 } },
    ["X"]            = { arms = { 45, 135, 225, 315 } },
    ["Star"]         = { arms = { 0, 45, 90, 135, 180, 225, 270, 315 } },
    ["Circle + Dot"] = { ring = true, dot = true },
    ["Circle"]       = { ring = true },
    ["Dot"]          = { dot = true },
}

local curRoot = Instance.new("Frame")
curRoot.Name = U.rname()
curRoot.AnchorPoint = Vector2.new(0.5, 0.5)
curRoot.BackgroundTransparency = 1
curRoot.Size = UDim2.fromOffset(0, 0)
curRoot.Visible = false
curRoot.Parent = overlay

local function curPiece(round)
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.BorderSizePixel = 0
    f.Visible = false
    f.Parent = curRoot
    if round then
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = f
    end
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.new(0, 0, 0)
    stroke.Thickness = 1
    stroke.Parent = f
    return { frame = f, stroke = stroke }
end

-- 8 arms, each of which can be split into two dashes = 16 pieces at most
local curArms = {}
for i = 1, 16 do curArms[i] = curPiece(false) end
local curDot = curPiece(true)

local curRing = Instance.new("Frame")
curRing.AnchorPoint = Vector2.new(0.5, 0.5)
curRing.BackgroundTransparency = 1
curRing.BorderSizePixel = 0
curRing.Visible = false
curRing.Parent = curRoot
do
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = curRing
end
local curRingStroke = Instance.new("UIStroke")
curRingStroke.Parent = curRing

local curLabel = Instance.new("TextLabel")
curLabel.AnchorPoint = Vector2.new(0.5, 0)
curLabel.BackgroundTransparency = 1
curLabel.Size = UDim2.fromOffset(300, 20)
curLabel.Font = Enum.Font.GothamBold
curLabel.TextStrokeTransparency = 0.35
curLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
curLabel.Visible = false
curLabel.Parent = curRoot

-- glow: two soft layers behind every piece. Roblox UI cannot blur, so a bigger, rounded, see-through copy in
-- the same colour is what reads as light. [1] = inner (brighter), [2] = outer (fainter).
local curGlow = { arms = {}, label = U.NewGlow(curLabel) }
do
    local function halo()
        local f = Instance.new("Frame")
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.BorderSizePixel = 0
        f.ZIndex = 0
        f.Visible = false
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = f
        f.Parent = curRoot
        return f
    end
    local function ringHalo()
        local f = halo()
        f.BackgroundTransparency = 1
        local stroke = Instance.new("UIStroke"); stroke.Parent = f
        return { frame = f, stroke = stroke }
    end
    for i = 1, #curArms do curGlow.arms[i] = { halo(), halo() } end
    curGlow.dot = { halo(), halo() }
    curGlow.ring = { ringHalo(), ringHalo() }
end
local GLOW_ALPHA = { 0.62, 0.84 }   -- transparency of the inner / outer layer

onUnload(function() curRoot:Destroy() end)

-- the normal pointer is hidden while the custom one is drawn, and handed back afterwards
local sysIconOriginal
local function setSystemCursor(visibleIcon)
    if sysIconOriginal == nil then sysIconOriginal = UserInputService.MouseIconEnabled end
    UserInputService.MouseIconEnabled = visibleIcon
end
local function restoreSystemCursor()
    if sysIconOriginal ~= nil then
        UserInputService.MouseIconEnabled = sysIconOriginal
        sysIconOriginal = nil
    end
end
onUnload(restoreSystemCursor)

-- who is being aimed at: rage / aimbot / silent target first, otherwise whoever is under the cursor
local function cursorTargetPlayer(pos)
    if C.CursorSource ~= "Under Crosshair" then
        local t = (C.RageEnabled and rageTarget) or (C.AimEnabled and aimTarget) or U.SilentTarget
        if t and t.plr and charOf(t.plr) then return t.plr end   -- dead players are never shown
    end
    local ray = cam():ViewportPointToRay(pos.X, pos.Y)
    rayParams.FilterDescendantsInstances = { lp.Character }
    local res = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
    if not res then return end
    local model = res.Instance:FindFirstAncestorOfClass("Model")
    local plr = model and Players:GetPlayerFromCharacter(model)
    if plr and plr ~= lp and charOf(plr) then return plr end
end

local curScale = 1            -- smoothed scale for the "on target" animations
local curLastPlr, curNewAt = nil, 0

renderLast(function()
    if not (C.CursorEnabled and U.Running) then
        curRoot.Visible = false
        restoreSystemCursor()
        return
    end

    -- over the menu the normal pointer is needed to click anything
    if cursorOverMenu() then
        curRoot.Visible = false
        setSystemCursor(true)
        return
    end
    setSystemCursor(not C.CursorHideSys)

    local pos = C.CursorPos == "Screen Center" and viewportCenter() or UserInputService:GetMouseLocation()
    curRoot.Visible = true
    curRoot.Position = UDim2.fromOffset(pos.X, pos.Y)

    local t = os.clock()
    local col = C.CursorRainbow and Color3.fromHSV((t * C.CursorRainbowSpeed) % 1, 0.9, 1) or C.CursorColor

    local plr = cursorTargetPlayer(pos)
    if plr ~= curLastPlr then curLastPlr, curNewAt = plr, t end

    -- size animation ---------------------------------------------------
    local speed, amount, anim = C.CursorAnimSpeed, C.CursorAnimAmount, C.CursorAnim
    local goalScale = 1
    if anim == "Pulse" then
        goalScale = 1 + math.sin(t * speed * 2 * math.pi) * amount
        curScale = goalScale
    elseif anim == "Heartbeat" then
        local p = (t * speed) % 1
        local beat = 0
        if p < 0.15 then beat = math.sin(p / 0.15 * math.pi)
        elseif p > 0.25 and p < 0.40 then beat = math.sin((p - 0.25) / 0.15 * math.pi) end
        curScale = 1 + beat * amount
    else
        if anim == "Shrink On Target" then goalScale = plr and (1 - amount * 0.7) or 1
        elseif anim == "Grow On Target" then goalScale = plr and (1 + amount) or 1 end
        curScale += (goalScale - curScale) * 0.2
    end

    local size, gap, thick = C.CursorSize * curScale, C.CursorGap * curScale, C.CursorThick
    local spin = (t * C.CursorSpin) % 360
    local parts = STYLE_PARTS[C.CursorStyle] or STYLE_PARTS["Cross + Dot"]

    -- arms (or dashes)
    local used = 0
    if parts.arms then
        local segments = C.CursorDashed and { { 0, 0.4 }, { 0.6, 1 } } or { { 0, 1 } }
        for _, angle in ipairs(parts.arms) do
            local a = angle + spin
            local rad = math.rad(a)
            local dx, dy = math.cos(rad), math.sin(rad)
            for _, seg in ipairs(segments) do
                used += 1
                local piece = curArms[used]
                local mid = gap + (seg[1] + seg[2]) / 2 * size
                piece.frame.Size = UDim2.fromOffset(math.max((seg[2] - seg[1]) * size, 1), thick)
                piece.frame.Position = UDim2.fromOffset(dx * mid, dy * mid)
                piece.frame.Rotation = a
                piece.frame.BackgroundColor3 = col
                piece.stroke.Enabled = C.CursorOutline
                piece.frame.Visible = true
                for k, h in ipairs(curGlow.arms[used]) do
                    h.Visible = C.CursorGlow
                    if C.CursorGlow then
                        local pad = C.CursorGlowSize * k / 2
                        h.Size = UDim2.fromOffset(piece.frame.Size.X.Offset + pad * 2, thick + pad * 2)
                        h.Position, h.Rotation = piece.frame.Position, a
                        h.BackgroundColor3, h.BackgroundTransparency = col, GLOW_ALPHA[k]
                    end
                end
            end
        end
    end
    for i = used + 1, #curArms do
        curArms[i].frame.Visible = false
        for _, h in ipairs(curGlow.arms[i]) do h.Visible = false end
    end

    -- centre dot
    curDot.frame.Visible = parts.dot == true
    if parts.dot then
        local d = C.CursorDot * curScale
        curDot.frame.Size = UDim2.fromOffset(d, d)
        curDot.frame.Position = UDim2.fromOffset(0, 0)
        curDot.frame.BackgroundColor3 = col
        curDot.stroke.Enabled = C.CursorOutline
    end
    for k, h in ipairs(curGlow.dot) do
        h.Visible = C.CursorGlow and parts.dot == true
        if h.Visible then
            local d = C.CursorDot * curScale + C.CursorGlowSize * k
            h.Size = UDim2.fromOffset(d, d)
            h.Position = UDim2.fromOffset(0, 0)
            h.BackgroundColor3, h.BackgroundTransparency = col, GLOW_ALPHA[k]
        end
    end

    -- ring
    curRing.Visible = parts.ring == true
    if parts.ring then
        local d = size * 2
        curRing.Size = UDim2.fromOffset(d, d)
        curRingStroke.Color = col
        curRingStroke.Thickness = thick
    end
    for k, h in ipairs(curGlow.ring) do
        h.frame.Visible = C.CursorGlow and parts.ring == true
        if h.frame.Visible then
            h.frame.Size = curRing.Size
            h.stroke.Color = col
            h.stroke.Thickness = thick + C.CursorGlowSize * k
            h.stroke.Transparency = GLOW_ALPHA[k]
        end
    end

    -- "aiming at" label --------------------------------------------------
    local showLabel = C.CursorLabel and plr ~= nil
    curLabel.Visible = showLabel
    if showLabel then
        local text = plr.DisplayName
        if C.CursorLabelInfo then
            local _, hum, root = charOf(plr)
            if hum and root then
                text = string.format("%s  |  %d st  |  %d hp", text, (root.Position - cam().CFrame.Position).Magnitude, hum.Health)
            end
        end

        -- measured from the UNscaled cursor so the size animation never moves or resizes the text
        local extent = (parts.ring and C.CursorSize or (parts.arms and (C.CursorGap + C.CursorSize) or 0)) + (parts.dot and C.CursorDot / 2 or 0) + 8
        local textScale, textFade = 1, 0
        local ta = C.CursorLabelAnim
        if ta == "Pulse" then
            textScale = 1 + math.sin(t * speed * 2 * math.pi) * amount * 0.5
        elseif ta == "Pop" then
            -- springs in with a little overshoot each time the target changes
            local p = math.clamp((t - curNewAt) / 0.35, 0, 1)
            local c1 = 1.70158
            local ease = 1 + (c1 + 1) * (p - 1) ^ 3 + c1 * (p - 1) ^ 2
            textScale = 0.4 + 0.6 * ease
        elseif ta == "Fade" then
            textFade = 0.5 * (0.5 + 0.5 * math.sin(t * speed * 2 * math.pi))
        end

        curLabel.Text = text
        curLabel.TextSize = math.max(math.floor(C.CursorLabelSize * textScale + 0.5), 6)
        curLabel.TextColor3 = C.CursorLabelSame and col or C.CursorLabelColor
        curLabel.TextTransparency = textFade
        curLabel.Position = UDim2.fromOffset(0, extent)
    end
    U.SyncGlow(curGlow.label, C.CursorGlow and showLabel, curLabel.TextColor3, C.CursorGlowSize * 0.75, 1 - curLabel.TextTransparency)
end)

Ready()
