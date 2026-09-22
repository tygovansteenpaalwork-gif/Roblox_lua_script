----------------------------------------------------------------------
-- tab: Triggerbot
----------------------------------------------------------------------

local trigTab = win:Tab("Trigger")
local trig = trigTab:Section("Triggerbot")
local trigTune = trigTab:Section("Timing", "right")

toggle(trig, "Enabled", "TrigEnabled", false)
dropdown(trig, "Mode", "TrigMode", { "Always On", "Hold Key" }, "Always On")
keybind(trig, "Trigger Key", "TrigKey", Enum.KeyCode.LeftAlt)
dropdown(trig, "Target Part", "TrigPart", { "Any", "Head", "Torso" }, "Any")
dropdown(trig, "Fire Method", "TrigMethod", FIRE_METHODS, "Auto")
toggle(trig, "Team Check", "TrigTeam", true)
toggle(trig, "Dead Check", "TrigDead", true)

slider(trigTune, "Reaction Time", "TrigReaction", 0, 500, 60, { Suffix = " ms" })
slider(trigTune, "Shoot Delay", "TrigDelay", 0, 1000, 120, { Suffix = " ms" })
slider(trigTune, "Max Distance", "TrigDist", 10, 1500, 300, { Suffix = " st" })
toggle(trigTune, "Randomize Timing", "TrigRandom", true)

local trigSince, trigWait, lastShot = nil, 0, 0

toggle(trigTune, "Include NPCs / Dummies", "TrigNPC", true)

-- returns (name, nil) when something valid is under the cursor, otherwise (nil, reason); the reason is
-- shown in the trigger status line so you can see WHY it is not firing
local function underCrosshair()
    if cursorOverMenu() then return nil, "cursor is on the menu" end   -- aiming at the menu is not aiming at the world
    local pos = UserInputService:GetMouseLocation()
    local ray = cam():ViewportPointToRay(pos.X, pos.Y)
    rayParams.FilterDescendantsInstances = { lp.Character }
    local res = workspace:Raycast(ray.Origin, ray.Direction * C.TrigDist, rayParams)
    if not res then return nil, "nothing under the cursor" end
    local model = res.Instance:FindFirstAncestorOfClass("Model")
    local plr = model and Players:GetPlayerFromCharacter(model)
    local hum
    if plr then
        if plr == lp then return nil, "that is you" end
        if C.ListRespectWhite and U.White[plr.Name] then return nil, "whitelisted: " .. plr.DisplayName end
        if C.ListOnlyBlack and next(U.Black) ~= nil and not U.Black[plr.Name] then return nil, "not on the blacklist" end
        if C.TrigTeam and sameTeam(plr) then return nil, "teammate" end
        local _, h = charOf(plr, not C.TrigDead)
        hum = h
    elseif C.TrigNPC and model and model ~= lp.Character then
        local h = model:FindFirstChildOfClass("Humanoid")
        if h and (not C.TrigDead or h.Health > 0) then hum = h end
    end
    if not hum then return nil, "not a target: " .. (model and model.Name or res.Instance.Name) end
    if C.TrigPart == "Head" and res.Instance.Name ~= "Head" then return nil, "not the head: " .. res.Instance.Name end
    if C.TrigPart == "Torso" and not (res.Instance.Name:find("Torso") or res.Instance.Name == "HumanoidRootPart") then
        return nil, "not the torso: " .. res.Instance.Name
    end
    return plr and plr.DisplayName or model.Name
end

connect(RunService.RenderStepped, function()
    if not (C.TrigEnabled and U.Running) then trigSince = nil return end
    if C.TrigMode == "Hold Key" and not (BIND.TrigKey and BIND.TrigKey:IsDown()) then
        trigSince = nil
        U.TrigTarget, U.TrigWhy = nil, "hold the trigger key"
        return
    end
    -- Rage already clicks for its own target: two bots clicking means double shots
    if U.RageTarget and U.RageTarget() then
        trigSince = nil
        U.TrigTarget, U.TrigWhy = nil, "paused: Rage has a target"
        return
    end
    local target, why = underCrosshair()
    U.TrigTarget, U.TrigWhy = target, why
    if not target then trigSince = nil return end

    local now = os.clock()
    local jitter = C.TrigRandom and (0.85 + math.random() * 0.3) or 1
    if not trigSince then
        trigSince = now
        trigWait = (C.TrigReaction / 1000) * jitter
    end
    if now - trigSince < trigWait then return end
    if now - lastShot < (C.TrigDelay / 1000) * jitter then return end
    lastShot = now
    fireWeapon(C.TrigMethod, UserInputService:GetMouseLocation())   -- click where the enemy is under the cursor
end)

-- trigger status: a small line just below the crosshair while the triggerbot is on. It says what it
-- is aiming at, or why it is not firing (menu, hold key, wrong part, teammate ...).
do
local trigText = Instance.new("TextLabel")
trigText.Name = "TriggerStatus"
trigText.AnchorPoint = Vector2.new(0.5, 0)
trigText.BackgroundTransparency = 1
trigText.Size = UDim2.fromOffset(420, 20)
trigText.Font = Enum.Font.GothamBold
trigText.TextSize = 14
trigText.TextStrokeTransparency = 0.35
trigText.TextStrokeColor3 = Color3.new(0, 0, 0)
trigText.Visible = false
trigText.Parent = overlay

renderLast(function()
    local on = C.TrigEnabled and U.Running
    trigText.Visible = on and true or false
    if not on then return end
    local c = viewportCenter()
    trigText.Position = UDim2.fromOffset(c.X, c.Y + 36)
    if U.TrigTarget then
        trigText.Text = "TRIGGER  ·  " .. U.TrigTarget
        trigText.TextColor3 = Color3.fromRGB(255, 90, 90)
    else
        trigText.Text = "TRIGGER  ·  " .. tostring(U.TrigWhy or "nothing under the cursor")
        trigText.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
end)
end   -- trigger status

