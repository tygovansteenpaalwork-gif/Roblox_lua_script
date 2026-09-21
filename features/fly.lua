--[[
    Fly  -  fly.lua
    Fly with the root's velocity (no body movers), vertical speed and smoothing.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/fly.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "fly", Title = "Fly" })

local C, Ready, U, UserInputService, cam, myHumanoid = ctx.C, ctx.Ready, ctx.U, ctx.UserInputService, ctx.cam, ctx.myHumanoid
local onUnload, renderLast, slider, toggle, typing, win = ctx.onUnload, ctx.renderLast, ctx.slider, ctx.toggle, ctx.typing, ctx.win

local moveTab = win:Tab("Fly")
local fly = moveTab:Section("Flight & Collision")

-- fly ------------------------------------------------------------------

-- Flying is done by setting the root's velocity every frame (no BodyVelocity / BodyGyro objects inside the character,
-- which is the first thing an anti-fly check looks for). Gravity is cancelled by adding half a frame of it back.
local flyState = { vel = Vector3.zero }
local function stopFly()
    flyState.vel = Vector3.zero
    local hum = myHumanoid()
    if hum then hum.PlatformStand = false end
end

toggle(fly, "Fly", "FlyEnabled", false, function(v) if not v then stopFly() end end)
slider(fly, "Fly Speed", "FlySpeed", 10, 300, 70)
slider(fly, "Vertical Speed", "FlyVertical", 0.2, 2, 1, { Decimals = 2, Suffix = "x" })
slider(fly, "Fly Smoothing", "FlySmooth", 0, 95, 0, { Suffix = "%" })

local function typing() return UserInputService:GetFocusedTextBox() ~= nil end

renderLast(function(dt)
    if not (C.FlyEnabled and U.Running) then return end
    local hum, root = myHumanoid()
    if not hum or not root then return end

    hum.PlatformStand = true

    local look = cam().CFrame
    local dir = Vector3.zero
    if not typing() then
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += look.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= look.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += look.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= look.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then dir += Vector3.yAxis * C.FlyVertical end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then dir -= Vector3.yAxis * C.FlyVertical end
    end
    local want = dir.Magnitude > 0 and dir.Unit * C.FlySpeed or Vector3.zero
    if C.FlySmooth > 0 then
        -- frame-rate independent glide: 0% = instant, 95% = very floaty
        want = flyState.vel:Lerp(want, 1 - (C.FlySmooth / 100) ^ (math.min(dt, 0.1) * 60))
    end
    flyState.vel = want
    root.AssemblyLinearVelocity = want + Vector3.new(0, workspace.Gravity * math.min(dt, 0.1) * 0.5, 0)
    root.AssemblyAngularVelocity = Vector3.zero
    local flat = Vector3.new(look.LookVector.X, 0, look.LookVector.Z)
    if flat.Magnitude > 0.01 then root.CFrame = CFrame.lookAt(root.Position, root.Position + flat) end
end)
onUnload(stopFly)

Ready()
