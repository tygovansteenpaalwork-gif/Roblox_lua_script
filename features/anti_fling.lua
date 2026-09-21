--[[
    Anti Fling  -  anti_fling.lua
    Stops other players' bodies from flinging you and cancels sudden launches.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/anti_fling.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "anti_fling", Title = "Anti Fling" })

local C, Players, Ready, RunService, U, connect = ctx.C, ctx.Players, ctx.Ready, ctx.RunService, ctx.U, ctx.connect
local lp, myHumanoid, notify, onUnload, slider, toggle = ctx.lp, ctx.myHumanoid, ctx.notify, ctx.onUnload, ctx.slider, ctx.toggle
local win = ctx.win

local defTab = win:Tab("Anti Fling")
local aflSec = defTab:Section("Anti Fling")

-- anti fling ------------------------------------------------------------
-- 1) other players' bodies stop colliding with ours, so nothing can physically shove us
-- 2) if our own velocity spikes past what we could produce ourselves, cancel it and step
--    back to where we were a moment ago

local collisionOriginal = setmetatable({}, { __mode = "k" })
local function restoreCollisions()
    for part, was in pairs(collisionOriginal) do
        if part.Parent then part.CanCollide = was end
        collisionOriginal[part] = nil
    end
end
onUnload(restoreCollisions)

toggle(aflSec, "Anti Fling", "AntiFling", false, function(v) if not v then restoreCollisions() end end)
toggle(aflSec, "No Player Collision", "AntiFlingNoCollide", true)
slider(aflSec, "Max Speed", "AntiFlingSpeed", 60, 600, 220, { Suffix = " st/s" })

connect(RunService.Stepped, function()
    if not (C.AntiFling and C.AntiFlingNoCollide and U.Running) then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr ~= lp and plr.Character
        if char then
            for _, part in ipairs(char:GetChildren()) do
                if part:IsA("BasePart") and part.CanCollide then
                    if collisionOriginal[part] == nil then collisionOriginal[part] = true end
                    part.CanCollide = false
                end
            end
        end
    end
end)

local safeCF, safeAt, lastFlingNote = nil, 0, 0
connect(RunService.Heartbeat, function()
    if not (C.AntiFling and U.Running) then safeCF = nil return end
    local hum, root = myHumanoid()
    if not (hum and root) then return end

    -- what we could legitimately be doing ourselves
    local allowed = C.AntiFlingSpeed
    if C.SpeedEnabled then allowed = math.max(allowed, C.SpeedValue * 1.6) end
    if C.FlyEnabled then allowed = math.max(allowed, C.FlySpeed * 1.6) end

    -- falling fast is normal, so only sideways speed and upward speed count
    local vel = root.AssemblyLinearVelocity
    local speed = math.max(Vector3.new(vel.X, 0, vel.Z).Magnitude, math.max(vel.Y, 0))
    if speed > allowed or root.AssemblyAngularVelocity.Magnitude > 80 then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        if safeCF and (root.Position - safeCF.Position).Magnitude > 6 then root.CFrame = safeCF end
        if os.clock() - lastFlingNote > 2 then
            lastFlingNote = os.clock()
            notify("Anti Fling", "Cancelled a sudden launch", "warn")
        end
    elseif os.clock() - safeAt > 0.15 then
        safeCF, safeAt = root.CFrame, os.clock()
    end
end)

Ready()
