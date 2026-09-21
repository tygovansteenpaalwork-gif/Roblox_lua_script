--[[
    Headsit  -  headsit.lua
    Sit on somebody's head with the real sit animation (others see it).

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/headsit.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "headsit", Title = "Headsit" })

local C, Players, Ready, RunService, TOG, U = ctx.C, ctx.Players, ctx.Ready, ctx.RunService, ctx.TOG, ctx.U
local addPlayerPicker, charOf, connect, dropdown, lp, myHumanoid = ctx.addPlayerPicker, ctx.charOf, ctx.connect, ctx.dropdown, ctx.lp, ctx.myHumanoid
local notify, onUnload, slider, toggle, win = ctx.notify, ctx.onUnload, ctx.slider, ctx.toggle, ctx.win

local funTab = win:Tab("Headsit")
local sitSec = funTab:Section("Headsit")
local playerDD = addPlayerPicker(sitSec)

-- headsit ---------------------------------------------------------------
-- We sit (Humanoid.Sit = true gives the real sit animation everybody sees) on top of somebody's head:
-- every frame our root is put just above their head and our body is made non-solid so we never push them.
local sitSaved

local function headsitTarget()
    if C.HeadSitTarget == "Selected Player" then
        return C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    end
    local _, myRoot = myHumanoid()
    if not myRoot then return end
    local best, bestDist
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then
            local _, _, root = charOf(plr)
            if root then
                local d = (root.Position - myRoot.Position).Magnitude
                if not bestDist or d < bestDist then best, bestDist = plr, d end
            end
        end
    end
    return best
end

local function headsitStop()
    if sitSaved then
        for part, was in pairs(sitSaved) do
            if part.Parent then part.CanCollide = was end
        end
        sitSaved = nil
    end
    local hum = myHumanoid()
    if hum then hum.Sit = false end
end

toggle(sitSec, "Headsit", "HeadSit", false, function(v)
    if not v then headsitStop() return end
    if not headsitTarget() then
        notify("Headsit", C.HeadSitTarget == "Selected Player" and "Pick a player on the Player tab first" or "Nobody to sit on", "warn")
        C.HeadSit = false
        if TOG.HeadSit then TOG.HeadSit:Set(false, true) end
    end
end)
dropdown(sitSec, "Target", "HeadSitTarget", { "Selected Player", "Nearest Player" }, "Selected Player")
slider(sitSec, "Height", "HeadSitHeight", -2, 4, 0, { Decimals = 1, Suffix = " st" })
toggle(sitSec, "Face Same Way As Target", "HeadSitFace", true)

connect(RunService.Heartbeat, function()
    if not (C.HeadSit and U.Running) then return end
    local hum, root, char = myHumanoid()
    if not (hum and root) then return end
    local plr = headsitTarget()
    local tchar, _, troot = nil, nil, nil
    if plr then tchar, _, troot = charOf(plr) end
    local head = tchar and tchar:FindFirstChild("Head")
    if not head then return end   -- target dead / respawning: we keep waiting

    sitSaved = sitSaved or setmetatable({}, { __mode = "k" })
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if sitSaved[part] == nil then sitSaved[part] = part.CanCollide end
            part.CanCollide = false
        end
    end
    hum.Sit = true
    local pos = head.Position + Vector3.new(0, head.Size.Y / 2 + 1.2 + C.HeadSitHeight, 0)
    local rot = C.HeadSitFace and troot.CFrame.Rotation or root.CFrame.Rotation
    root.CFrame = CFrame.new(pos) * rot
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end)
onUnload(headsitStop)

Ready()
