--[[
    Follow Player  -  follow.lua
    Follow a player at a distance, with a gliding automatic distance.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/follow.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "follow", Title = "Follow Player" })

local C, Players, Ready, TOG, U, addPlayerPicker = ctx.C, ctx.Players, ctx.Ready, ctx.TOG, ctx.U, ctx.addPlayerPicker
local charOf, myHumanoid, renderLast, slider, toggle, win = ctx.charOf, ctx.myHumanoid, ctx.renderLast, ctx.slider, ctx.toggle, ctx.win

local playerTab = win:Tab("Follow")
local tp = playerTab:Section("Player")
local orbitDD
local playerDD = addPlayerPicker(tp)

-- follow ---------------------------------------------------------------

local follow = playerTab:Section("Follow Player")
local followAutoAt = 0   -- when the Auto Distance glide started, so it always begins at the far end

-- follow and orbit both drive our position, so only one may be on at a time
toggle(follow, "Follow Selected Player", "FollowEnabled", false, function(v)
    if v then followAutoAt = os.clock() end
    if v and C.OrbitEnabled and TOG.OrbitEnabled then
        C.OrbitEnabled = false
        TOG.OrbitEnabled:Set(false, true)
    end
end)
slider(follow, "Distance Behind", "FollowDist", 0, 30, 5, { Decimals = 1, Suffix = " st" })
slider(follow, "Height", "FollowHeight", -5, 15, 0, { Decimals = 1, Suffix = " st" })
toggle(follow, "Face Their Back", "FollowFace", true)
toggle(follow, "Auto Distance", "FollowAuto", false, function(v) if v then followAutoAt = os.clock() end end)
slider(follow, "Auto Far", "FollowAutoFar", 0, 30, 5, { Decimals = 1, Suffix = " st" })
slider(follow, "Auto Near", "FollowAutoNear", 0, 30, 0, { Decimals = 1, Suffix = " st" })
slider(follow, "Auto Speed", "FollowAutoSpeed", 0.1, 4, 0.6, { Decimals = 2, Suffix = "/s" })

-- Auto Distance glides far -> near -> far continuously: a cosine, so the speed eases to zero
-- at both ends and there is never a jump or a sudden stop.
local function followDistance()
    if not C.FollowAuto then return C.FollowDist end
    local far = math.max(C.FollowAutoFar, C.FollowAutoNear)
    local near = math.min(C.FollowAutoFar, C.FollowAutoNear)
    -- measured from the moment it was switched on: cos(0) = 1, so it starts at the far end
    -- (no jump) and then glides toward the near end and back
    local wave = 0.5 + 0.5 * math.cos((os.clock() - followAutoAt) * C.FollowAutoSpeed * 2 * math.pi)
    return near + (far - near) * wave
end

renderLast(function()
    if not (C.FollowEnabled and U.Running) then return end
    local target = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    if not target then return end
    local _, _, targetRoot = charOf(target)
    local _, myRoot = myHumanoid()
    if not (targetRoot and myRoot) then return end

    local base = targetRoot.CFrame
    -- +Z is behind a character (its LookVector is -Z)
    local pos = base:PointToWorldSpace(Vector3.new(0, C.FollowHeight, followDistance()))
    local toward = Vector3.new(base.Position.X - pos.X, 0, base.Position.Z - pos.Z)
    if C.FollowFace and toward.Magnitude > 0.05 then
        myRoot.CFrame = CFrame.lookAt(pos, pos + toward)
    else
        myRoot.CFrame = CFrame.new(pos) * base.Rotation
    end
    myRoot.AssemblyLinearVelocity = Vector3.zero
end)

Ready()
