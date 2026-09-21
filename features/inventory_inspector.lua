--[[
    Inventory Inspector  -  inventory_inspector.lua
    Shows what a player holds and carries.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/inventory_inspector.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "inventory_inspector", Title = "Inventory Inspector" })

local C, Players, Ready, RunService, U, addPlayerPicker = ctx.C, ctx.Players, ctx.Ready, ctx.RunService, ctx.U, ctx.addPlayerPicker
local connect, toggle, win = ctx.connect, ctx.toggle, ctx.win

local playerTab = win:Tab("Inventory")
local tp = playerTab:Section("Player")
local renderInventory
local playerDD = addPlayerPicker(tp)

-- inventory inspector ----------------------------------------------------
-- Roblox only replicates other players' Backpack in games that choose to; whatever the
-- server does not send simply cannot be shown.

local inv = playerTab:Section("Inventory", "right")
toggle(inv, "Live Refresh", "InvLive", true)

local invRows = {}
for i = 1, 14 do
    invRows[i] = inv:Label("")
    invRows[i].Instance.Visible = false
end

local INV_SKIP = { Backpack = true, PlayerGui = true, PlayerScripts = true, StarterGear = true, leaderstats = true }

local function inventoryLines(plr)
    local lines = {}
    local char = plr.Character
    local held = char and char:FindFirstChildOfClass("Tool")
    table.insert(lines, plr.DisplayName .. " (" .. plr.Name .. ")")
    table.insert(lines, "Holding: " .. (held and held.Name or "nothing"))

    local bag = plr:FindFirstChildOfClass("Backpack")
    local items = {}
    if bag then
        for _, tool in ipairs(bag:GetChildren()) do table.insert(items, tool.Name) end
    end
    table.insert(lines, ("Backpack: %d item(s)"):format(#items))
    for i, name in ipairs(items) do
        if i > 7 then table.insert(lines, ("  + %d more"):format(#items - 7)) break end
        table.insert(lines, "  - " .. name)
    end

    -- games that store an inventory as folders on the player
    for _, child in ipairs(plr:GetChildren()) do
        if not INV_SKIP[child.Name] and (child:IsA("Folder") or child:IsA("Configuration")) then
            local n = #child:GetChildren()
            if n > 0 then table.insert(lines, ("%s: %d entries"):format(child.Name, n)) end
        end
    end
    return lines
end

renderInventory = function()
    local plr = C.SelectedPlayer and Players:FindFirstChild(C.SelectedPlayer)
    local lines = plr and inventoryLines(plr) or { "Pick a player above" }
    for i, row in ipairs(invRows) do
        local text = lines[i]
        row.Instance.Visible = text ~= nil
        if text then row:Set(text) end
    end
end

local invAccum = 0
connect(RunService.Heartbeat, function(dt)
    if not (C.InvLive and U.Running) then return end
    invAccum += dt
    if invAccum >= 0.5 then invAccum = 0 renderInventory() end
end)
renderInventory()

Ready()
