--[[
    Anti Ragdoll  -  anti_ragdoll.lua
    Refuses the ragdoll / hit-stun state (made for The Strongest Battlegrounds).

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/anti_ragdoll.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "anti_ragdoll", Title = "Anti Ragdoll" })

local C, Ready, U, myHumanoid, renderLast, toggle = ctx.C, ctx.Ready, ctx.U, ctx.myHumanoid, ctx.renderLast, ctx.toggle
local win = ctx.win

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

local ragSpeed, ragJump, ragScan = 16, 50, 0
renderLast(function()
    if not (C.AntiRagdoll and U.Running) then return end
    local hum, root, char = myHumanoid()
    if not (hum and root) then return end

    local ragged = char:FindFirstChild("Ragdoll") or char:FindFirstChild("RagdollSim")
    local stunned = C.AntiRagdollStun and char:FindFirstChild("Freeze")
    if not (ragged or stunned) then
        -- remember our normal values so they can be put back afterwards
        if hum.WalkSpeed > 0 then ragSpeed = hum.WalkSpeed end
        if hum.JumpPower > 0 then ragJump = hum.JumpPower end
        return
    end

    if ragged and not C.FlyEnabled then
        if hum.PlatformStand then hum.PlatformStand = false end
        local state = hum:GetState()
        if state == Enum.HumanoidStateType.FallingDown or state == Enum.HumanoidStateType.PlatformStanding
            or state == Enum.HumanoidStateType.Ragdoll then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        if root.Anchored then root.Anchored = false end
        if os.clock() - ragScan > 0.25 then
            ragScan = os.clock()
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("Motor6D") and not d.Enabled then d.Enabled = true end
            end
        end
    end
    if ragged or stunned then
        if hum.WalkSpeed < 1 then hum.WalkSpeed = ragSpeed end
        if hum.JumpPower < 1 then
            hum.UseJumpPower = true
            hum.JumpPower = ragJump
        end
    end
end)

Ready()
