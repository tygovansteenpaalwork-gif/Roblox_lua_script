--[[
    Terkan  -  library loader
    ------------------------------------------------------------------------------------------
    One entry point for everything in this repository: the UI library (TerkanUI), the whole hub and every feature
    as a file of its own.

        local Terkan = loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/Terkan.lua"))()

        Terkan.hub()                 -- the whole hub (TerkanUI + TerkanUniversal)
        Terkan.feature("esp")        -- one feature in a small menu of its own
        Terkan.list()                -- { "aimbot", "anti_afk", ... }
        Terkan.info("rage")          -- { name, title, about, file }
        Terkan.ui()                  -- only the UI library, to build your own menu
        Terkan.version()             -- version of the hub on GitHub

    Point it at another copy of the repository (a fork, a branch, a local web server) with Terkan.setBase(url).
--]]

local Terkan = {}

local base = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local cache = {}

function Terkan.setBase(url)
    base = url:sub(-1) == "/" and url or url .. "/"
    cache = {}
end

local function fetch(path)
    if cache[path] then return cache[path] end
    local ok, body = pcall(function() return game:HttpGet(base .. path) end)
    if not ok or type(body) ~= "string" or body == "" then
        error("Terkan: could not download " .. path .. " (" .. tostring(body) .. ")", 3)
    end
    cache[path] = body
    return body
end

local function run(path, ...)
    local fn, err = loadstring(fetch(path), "=" .. path)
    if not fn then error("Terkan: " .. path .. " does not compile: " .. tostring(err), 3) end
    return fn(...)
end

-- the machine readable index of the features, written by tools/build.py
function Terkan.manifest()
    if not cache.__manifest then
        cache.__manifest = game:GetService("HttpService"):JSONDecode(fetch("features/manifest.json"))
    end
    return cache.__manifest
end

function Terkan.list()
    local names = {}
    for _, f in ipairs(Terkan.manifest().features) do names[#names + 1] = f.name end
    for _, a in ipairs(Terkan.manifest().aliases) do names[#names + 1] = a.name end
    table.sort(names)
    return names
end

function Terkan.info(name)
    local m = Terkan.manifest()
    for _, f in ipairs(m.features) do
        if f.name == name then return f end
    end
    for _, a in ipairs(m.aliases) do
        if a.name == name then return { name = a.name, about = a.about, file = "features/" .. a.target .. ".lua" } end
    end
end

-- the UI library on its own (also stored in TERKANUI, which the hub and the features look for)
function Terkan.ui()
    if not getgenv().TERKANUI then getgenv().TERKANUI = run("TerkanUI.lua") end
    return getgenv().TERKANUI
end

function Terkan.hub()
    Terkan.ui()
    return run("TerkanUniversal.lua")
end

function Terkan.feature(name)
    if not Terkan.info(name) then
        error("Terkan: unknown feature '" .. tostring(name) .. "' - Terkan.list() shows them all", 2)
    end
    Terkan.ui()
    return run("features/" .. name .. ".lua")
end

function Terkan.version()
    cache["version.txt"] = nil   -- always ask GitHub
    return (fetch("version.txt"):gsub("%s+", ""))
end

return Terkan
