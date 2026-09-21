--[[
    Whitelist & Blacklist  -  whitelist_blacklist.lua
    Friends are skipped by every targeting feature, blacklisted players are targeted first. Auto-whitelists Roblox friends.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/whitelist_blacklist.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "whitelist_blacklist", Title = "Whitelist & Blacklist" })

local C, Players, Ready, U, connect, lp = ctx.C, ctx.Players, ctx.Ready, ctx.U, ctx.connect, ctx.lp
local playerNames, toggle, win = ctx.playerNames, ctx.toggle, ctx.win

local playerTab = win:Tab("Lists")

-- whitelist & blacklist
----------------------------------------------------------------------

-- Whitelist = friends: skipped by aimbot, silent aim, triggerbot and rage, and drawn in their own
-- colour in the ESP. Blacklist = priority targets: aimed at first, drawn in their own colour, and with
-- "Only Target Blacklist" nobody else is targeted at all. A player is on at most one list. The lists are
-- stored by player NAME, so they survive someone leaving and rejoining (and are saved in configs).
do
local listSec = playerTab:Section("Whitelist & Blacklist", "right")
local whiteDD, blackDD

local function presentNames()
    local present = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then present[plr.Name] = true end
    end
    return present
end

local function pickedOf(set)
    local picked, present = {}, presentNames()
    for name in pairs(set) do
        if present[name] then table.insert(picked, name) end
    end
    table.sort(picked, function(a, b) return a:lower() < b:lower() end)
    return picked
end

-- a dropdown only knows the players that are here right now, so entries of absent players are kept
local function takePicks(set, other, picks)
    local present = presentNames()
    for name in pairs(set) do
        if present[name] then set[name] = nil end
    end
    for _, name in ipairs(picks) do
        set[name] = true
        other[name] = nil          -- never on both lists
    end
end

local function syncSelections()
    if whiteDD then whiteDD:Set(pickedOf(U.White), true) end
    if blackDD then blackDD:Set(pickedOf(U.Black), true) end
end

whiteDD = listSec:Dropdown({ Text = "Whitelist (friends)", Options = playerNames(), Multi = true, Flag = "ListWhite",
    Callback = function(picks) takePicks(U.White, U.Black, picks) syncSelections() end })
blackDD = listSec:Dropdown({ Text = "Blacklist (targets)", Options = playerNames(), Multi = true, Flag = "ListBlack",
    Callback = function(picks) takePicks(U.Black, U.White, picks) syncSelections() end })

local function refreshLists()
    whiteDD:SetOptions(playerNames())
    blackDD:SetOptions(playerNames())
    syncSelections()
end
connect(Players.PlayerAdded, refreshLists)
connect(Players.PlayerRemoving, function() task.defer(refreshLists) end)

listSec:Button({ Text = "Refresh Player List", Callback = refreshLists })
listSec:Button({ Text = "Clear Whitelist", Callback = function() table.clear(U.White) syncSelections() end })
listSec:Button({ Text = "Clear Blacklist", Callback = function() table.clear(U.Black) syncSelections() end })
toggle(listSec, "Skip Whitelisted Players", "ListRespectWhite", true)
toggle(listSec, "Target Blacklisted First", "ListBlackFirst", true)
toggle(listSec, "Only Target Blacklist", "ListOnlyBlack", false)

-- Roblox friends never become targets: they are added to the whitelist as they join
local function whitelistFriends()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and not U.White[plr.Name] then
            local ok, isFriend = pcall(lp.IsFriendsWith, lp, plr.UserId)   -- yields, hence the thread
            if ok and isFriend then
                U.White[plr.Name] = true
                U.Black[plr.Name] = nil
            end
        end
    end
    syncSelections()
end
toggle(listSec, "Auto-Whitelist Roblox Friends", "AutoWhiteFriends", false, function(v)
    if v then task.spawn(whitelistFriends) end
end)
connect(Players.PlayerAdded, function()
    if C.AutoWhiteFriends then task.delay(1, whitelistFriends) end
end)
end   -- lists

Ready()
