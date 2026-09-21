--[[
    Freecam  -  freecam.lua
    Detach the camera from your character (WASD, E/Q up/down, Shift faster).

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/freecam.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "freecam", Title = "Freecam" })

local C, Ready, U, UserInputService, cam, myHumanoid = ctx.C, ctx.Ready, ctx.U, ctx.UserInputService, ctx.cam, ctx.myHumanoid
local onUnload, renderLast, slider, toggle, win = ctx.onUnload, ctx.renderLast, ctx.slider, ctx.toggle, ctx.win

local uniTab = win:Tab("Freecam")
local camSec = uniTab:Section("Camera")

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

Ready()
