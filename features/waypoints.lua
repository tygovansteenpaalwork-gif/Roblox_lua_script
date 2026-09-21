--[[
    Waypoints  -  waypoints.lua
    Save positions with a name and teleport back (saved per game).

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/waypoints.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "waypoints", Title = "Waypoints" })

local HttpService, Ready, myHumanoid, notify, win = ctx.HttpService, ctx.Ready, ctx.myHumanoid, ctx.notify, ctx.win

local uniTab = win:Tab("Waypoints")
local wpSec = uniTab:Section("Waypoints")

-- waypoints (saved per game when the executor can write files) ------------------------------

local WP_FILE = "TerkanWaypoints_" .. tostring(game.PlaceId) .. ".json"
local waypoints = {}   -- name -> the 12 components of a CFrame
if readfile and isfile then
    pcall(function()
        if isfile(WP_FILE) then waypoints = HttpService:JSONDecode(readfile(WP_FILE)) end
    end)
end
local function saveWaypoints()
    if writefile then pcall(writefile, WP_FILE, HttpService:JSONEncode(waypoints)) end
end
local function wpNames()
    local names = {}
    for name in pairs(waypoints) do table.insert(names, name) end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

local wpName, wpSel = "", nil
local wpDD
wpSec:TextBox({ Text = "Name", Placeholder = "e.g. spawn", Flag = "WaypointName", NoSave = true,
    Callback = function(t) wpName = t or "" end })
wpDD = wpSec:Dropdown({ Text = "Waypoint", Options = wpNames(), Flag = "WaypointSel", NoSave = true,
    Callback = function(v) wpSel = v end })

wpSec:Button({ Text = "Save Current Position", Callback = function()
    local _, root = myHumanoid()
    if not root then notify("Waypoints", "You need a character first", "warn") return end
    local name = wpName:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Spot " .. (#wpNames() + 1) end
    waypoints[name] = { root.CFrame:GetComponents() }
    saveWaypoints()
    wpDD:SetOptions(wpNames())
    notify("Waypoints", "Saved \"" .. name .. "\"", "success")
end })
wpSec:Button({ Text = "Teleport To Waypoint", Callback = function()
    local data = wpSel and waypoints[wpSel]
    local _, root = myHumanoid()
    if not (data and root) then notify("Waypoints", "Pick a waypoint first", "warn") return end
    root.CFrame = CFrame.new(table.unpack(data))
    root.AssemblyLinearVelocity = Vector3.zero
end })
wpSec:Button({ Text = "Delete Waypoint", Callback = function()
    if not (wpSel and waypoints[wpSel]) then notify("Waypoints", "Pick a waypoint first", "warn") return end
    waypoints[wpSel] = nil
    wpSel = nil
    saveWaypoints()
    wpDD:SetOptions(wpNames())
end })

Ready()
