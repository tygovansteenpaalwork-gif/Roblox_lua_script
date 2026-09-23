--[[
    Anti Ragdoll  -  anti_ragdoll.lua
    Refuses the ragdoll / hit-stun state (made for The Strongest Battlegrounds).

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/anti_ragdoll.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "anti_ragdoll", Title = "Anti Ragdoll" })

local C, Ready, U, lp, myHumanoid, renderLast = ctx.C, ctx.Ready, ctx.U, ctx.lp, ctx.myHumanoid, ctx.renderLast
local toggle, win = ctx.toggle, ctx.win

local defTab = win:Tab("Anti Ragdoll")
local arSec = defTab:Section("Anti Ragdoll")

-- anti ragdoll ------------------------------------------------------------
-- The Strongest Battlegrounds flags its states with Accessory instances on the character:
-- "Ragdoll" / "RagdollSim" = ragdolled (server sets PlatformStand + FallingDown), "Freeze" = hit
-- stun (WalkSpeed and JumpPower forced to 0). We own our own physics, so while a flag is present we
-- refuse the state changes every frame. Nothing is deleted, so the game's own scripts keep working;
-- the server still believes we are ragdolled, so moves it validates itself may still be blocked.

toggle(arSec, "Anti Ragdoll", "AntiRagdoll", false)
toggle(arSec, "Cancel Hit Stun", "AntiRagdollStun", false)

-- the routine is shared with Movement > Anti Stun: see "anti stun + anti ragdoll" at the bottom of the Movement tab

-- anti stun + anti ragdoll ------------------------------------------------------
-- ONE routine for two switches, so they never run twice or undo each other:
--   Movement > Anti Stun      always: every down / ragdoll / stun state and every stun flag, whatever caused it
--   Defense  > Anti Ragdoll   only while the game has flagged us. The Strongest Battlegrounds uses Accessory
--                             instances: "Ragdoll" / "RagdollSim" = ragdolled, "Freeze" = hit stun (that one only
--                             with Cancel Hit Stun). Other games use similar names or attributes, also checked.
-- Nothing of the game is deleted; the server may still think we are stunned, so moves it checks itself can stay blocked.
do
local STUN_FLAGS = { "Ragdoll", "RagdollSim", "Freeze", "Stun", "Stunned", "Knocked", "Downed", "NoMove", "NoMovement" }
local DOWN_STATES = {
    [Enum.HumanoidStateType.Ragdoll] = true, [Enum.HumanoidStateType.FallingDown] = true,
    [Enum.HumanoidStateType.Physics] = true, [Enum.HumanoidStateType.PlatformStanding] = true,
}
local good = { speed = 16, jump = 50, height = 7.2 }   -- our last normal values, put back while stunned
local st = { scanAt = 0, controlsAt = 0 }

-- the humanoid refuses to ragdoll / fall down at all; a new humanoid (respawn) needs it again
function U.StunStates(hum, off)
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not off)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not off)
    end)
end

local function stunFlag(char, hum)
    for _, n in ipairs(STUN_FLAGS) do
        if char:FindFirstChild(n) or char:GetAttribute(n) or hum:GetAttribute(n) then return n end
    end
    return nil
end

renderLast(function()
    if not U.Running then return end
    local hum, root, char = myHumanoid()
    if not (hum and root) then return end

    if st.hum ~= hum then
        st.hum = hum
        if C.AntiStun then U.StunStates(hum, true) end
    end

    local flag = (C.AntiStun or C.AntiRagdoll) and stunFlag(char, hum)
    if not flag then
        if hum.WalkSpeed >= 4 then good.speed = hum.WalkSpeed end
        if hum.JumpPower >= 5 then good.jump = hum.JumpPower end
        if hum.JumpHeight >= 1 then good.height = hum.JumpHeight end
    end
    local act = C.AntiStun or (C.AntiRagdoll and flag and (flag ~= "Freeze" or C.AntiRagdollStun))
    if not act then return end

    -- our own features that lie down / float on purpose
    local ours = C.FlyEnabled or C.SuperFly or C.LayDown
    if not ours then
        if hum.PlatformStand then hum.PlatformStand = false end
        if DOWN_STATES[hum:GetState()] then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
    end
    if root.Anchored then root.Anchored = false end
    if hum.WalkSpeed < 4 then hum.WalkSpeed = good.speed end
    if hum.UseJumpPower then
        if hum.JumpPower < 5 then hum.JumpPower = good.jump end
    elseif hum.JumpHeight < 1 then
        hum.JumpHeight = good.height
    end

    local now = os.clock()
    -- 4x a second: joints back on, ragdoll sockets off, nothing of us anchored, and (while flagged)
    -- no game mover that pins us to a spot. We create no movers ourselves, so every one is the game's.
    if now - st.scanAt > 0.25 then
        st.scanAt = now
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("Motor6D") then
                if not d.Enabled then d.Enabled = true end
            elseif d:IsA("BallSocketConstraint") then
                if d.Enabled and not ours then d.Enabled = false end
            elseif d:IsA("BasePart") then
                if d.Anchored then d.Anchored = false end
            elseif flag and (d:IsA("AlignPosition") or d:IsA("AlignOrientation")) then
                if d.Enabled then d.Enabled = false end
            elseif flag and d:IsA("BodyPosition") then
                d.MaxForce = Vector3.zero
            elseif flag and d:IsA("BodyGyro") then
                d.MaxTorque = Vector3.zero
            end
        end
    end
    -- some games switch the movement controls off during a stun: switch them back on (twice a second)
    if flag and now - st.controlsAt > 0.5 then
        st.controlsAt = now
        pcall(function()
            if not U.controls then
                local pm = lp:FindFirstChildOfClass("PlayerScripts") and lp.PlayerScripts:FindFirstChild("PlayerModule")
                U.controls = pm and require(pm):GetControls()
            end
            if U.controls then U.controls:Enable() end
        end)
    end
end)
end   -- anti stun

Ready()
