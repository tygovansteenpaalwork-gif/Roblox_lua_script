--[[
    Custom Skybox  -  custom_skybox.lua
    A drawn sky (sunset, neon night, aurora ...) or your own image as the sky. Only on your screen.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change the hub and rebuild.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/custom_skybox.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "custom_skybox", Title = "Custom Skybox" })

local C, Lighting, Ready, TOG, U, dropdown = ctx.C, ctx.Lighting, ctx.Ready, ctx.TOG, ctx.U, ctx.dropdown
local notify, onUnload, renderLast, slider, toggle, win = ctx.notify, ctx.onUnload, ctx.renderLast, ctx.slider, ctx.toggle, ctx.win

local funTab = win:Tab("Custom Skybox")
local skySec = funTab:Section("Custom Skybox")
local skyLook = funTab:Section("Sky Look", "right")

-- custom skybox -----------------------------------------------------------
-- Either a picture (Roblox image id, a link, or a file in the executor's workspace folder) on all six
-- sides, or a sky we draw ourselves: the pictures are generated as PNG files (gradient + stars) and
-- loaded through getcustomasset. Only your own screen changes.
local SKY_DIR, SKY_SIZE = "TerkanSky", 256

local crcTable = {}
for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
        c = (c % 2 == 1) and bit32.bxor(0xEDB88320, bit32.rshift(c, 1)) or bit32.rshift(c, 1)
    end
    crcTable[i] = c
end
local function crc32(s)
    local c = 0xFFFFFFFF
    for i = 1, #s do c = bit32.bxor(crcTable[bit32.band(bit32.bxor(c, s:byte(i)), 0xFF)], bit32.rshift(c, 8)) end
    return bit32.bxor(c, 0xFFFFFFFF)
end
local function adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end
local function pngChunk(kind, data)
    return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", crc32(kind .. data))
end
-- raw = every row prefixed with filter byte 0; wrapped in "stored" (uncompressed) deflate blocks
local function encodePng(w, h, raw)
    local z, pos, n = { "\120\1" }, 1, #raw
    while pos <= n do
        local len = math.min(65535, n - pos + 1)
        z[#z + 1] = string.pack("<BI2I2", (pos + len > n) and 1 or 0, len, 65535 - len) .. raw:sub(pos, pos + len - 1)
        pos += len
    end
    z[#z + 1] = string.pack(">I4", adler32(raw))
    return "\137PNG\r\n\26\n" .. pngChunk("IHDR", string.pack(">I4I4BBBBB", w, h, 8, 2, 0, 0, 0))
        .. pngChunk("IDAT", table.concat(z)) .. pngChunk("IEND", "")
end

-- zenith / middle / horizon colour and how many stars
local SKY_PRESETS = {
    ["Sunset"]      = { Color3.fromRGB(30, 20, 80),  Color3.fromRGB(210, 80, 95),  Color3.fromRGB(255, 175, 80), 0.0004 },
    ["Neon Night"]  = { Color3.fromRGB(4, 0, 24),    Color3.fromRGB(70, 0, 120),   Color3.fromRGB(255, 0, 170),  0.0020 },
    ["Aurora"]      = { Color3.fromRGB(0, 8, 28),    Color3.fromRGB(0, 100, 90),   Color3.fromRGB(70, 220, 130), 0.0025 },
    ["Blood Moon"]  = { Color3.fromRGB(8, 0, 0),     Color3.fromRGB(90, 0, 10),    Color3.fromRGB(210, 35, 20),  0.0015 },
    ["Deep Space"]  = { Color3.fromRGB(0, 0, 6),     Color3.fromRGB(8, 6, 34),     Color3.fromRGB(28, 12, 60),   0.0060 },
    ["Pastel Dawn"] = { Color3.fromRGB(120, 150, 230), Color3.fromRGB(235, 170, 215), Color3.fromRGB(255, 225, 185), 0 },
    ["Ocean Blue"]  = { Color3.fromRGB(10, 60, 160), Color3.fromRGB(60, 150, 230), Color3.fromRGB(190, 235, 255), 0 },
}
local SKY_PRESET_NAMES = { "Sunset", "Neon Night", "Aurora", "Blood Moon", "Deep Space", "Pastel Dawn", "Ocean Blue" }

local function makeFace(kind, preset, seed)
    local zenith, mid, horizon, density = preset[1], preset[2], preset[3], preset[4]
    local S = SKY_SIZE
    local rnd = Random.new(seed)
    local stars = {}
    for _ = 1, math.floor(S * S * density) do stars[rnd:NextInteger(0, S * S - 1)] = rnd:NextNumber(0.45, 1) end

    local rows = {}
    for y = 0, S - 1 do
        local t = y / (S - 1)          -- 0 = top of the picture, 1 = bottom
        local base
        if kind == "up" then base = zenith
        elseif kind == "down" then base = horizon:Lerp(Color3.new(0, 0, 0), 0.5)
        elseif t < 0.6 then base = zenith:Lerp(mid, t / 0.6)
        else base = mid:Lerp(horizon, (t - 0.6) / 0.4) end
        local fade = kind == "side" and math.clamp(1 - t * 1.4, 0, 1) or 1   -- no stars near the horizon
        local buf = { "\0" }
        for x = 0, S - 1 do
            local col = base
            local b = stars[y * S + x]
            if b then col = base:Lerp(Color3.new(1, 1, 1), b * fade) end
            buf[#buf + 1] = string.char(math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5))
        end
        rows[#rows + 1] = table.concat(buf)
    end
    return encodePng(S, S, table.concat(rows))
end

-- Sky property -> how that face of the cube is drawn
local FACES = {
    { "SkyboxBk", "side", 11 }, { "SkyboxFt", "side", 22 }, { "SkyboxLf", "side", 33 },
    { "SkyboxRt", "side", 44 }, { "SkyboxUp", "up", 55 },   { "SkyboxDn", "down", 66 },
}

local presetAssets = {}
local function presetSky(name)
    if presetAssets[name] then return presetAssets[name] end
    if not isfolder(SKY_DIR) then makefolder(SKY_DIR) end
    local out = {}
    for _, face in ipairs(FACES) do
        local path = ("%s/%s_%s_v1.png"):format(SKY_DIR, name:gsub("%s", ""), face[1])
        if not isfile(path) then
            writefile(path, makeFace(face[2], SKY_PRESETS[name], face[3]))
            task.wait()   -- generating is heavy: one picture per frame, so the game does not freeze
        end
        out[face[1]] = getcustomasset(path)
    end
    presetAssets[name] = out
    return out
end

-- a Roblox image id, a link or a file name  ->  something a Sky can show (all six sides)
local function imageSky(source)
    source = (source or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if source == "" then return nil, "Type an image id, link or file name first" end
    local url = source:match("^https?://.+")
    local id = source:match("^rbxassetid://(%d+)$") or source:match("^(%d+)$")
        or (source:find("roblox.com", 1, true) and source:match("[?&]id=(%d+)"))
    local asset
    if id then
        asset = "rbxassetid://" .. id
    elseif url then
        local ok, res = pcall(request, { Url = url, Method = "GET" })
        if not (ok and res and res.Success and res.Body and #res.Body > 0) then
            return nil, "Could not download that link"
        end
        if not isfolder(SKY_DIR) then makefolder(SKY_DIR) end
        local ext = url:match("%.(%a%a%a%a?)[%?#]?[^/]*$")
        ext = (ext == "jpg" or ext == "jpeg" or ext == "png") and ext or "png"
        local path = SKY_DIR .. "/custom." .. ext
        writefile(path, res.Body)
        asset = getcustomasset(path)
    elseif isfile(source) then
        asset = getcustomasset(source)
    elseif isfile(SKY_DIR .. "/" .. source) then
        asset = getcustomasset(SKY_DIR .. "/" .. source)
    else
        return nil, "Not an image id, link or file in your executor workspace"
    end
    local out = {}
    for _, face in ipairs(FACES) do out[face[1]] = asset end
    return out
end

local skyObj, hiddenSkies = nil, {}
local skyGen = 0
local skyImageText = ""

local function hideGameSkies()
    for _, s in ipairs(Lighting:GetChildren()) do
        if s:IsA("Sky") and s ~= skyObj then
            hiddenSkies[s] = true
            s.Parent = nil
        end
    end
end

local function skyOff()
    skyGen += 1
    if skyObj then skyObj:Destroy() skyObj = nil end
    for s in pairs(hiddenSkies) do
        s.Parent = Lighting
        hiddenSkies[s] = nil
    end
end

local function skyOn()
    skyGen += 1
    local gen = skyGen
    task.spawn(function()
        local textures, err
        local ok, res, msg = pcall(function()
            if C.SkySource == "Image" then return imageSky(skyImageText) end
            return presetSky(C.SkyPreset)
        end)
        if ok then textures, err = res, msg else err = tostring(res) end
        if gen ~= skyGen or not C.SkyOn then return end   -- switched off / changed while loading
        if not textures then
            notify("Skybox", err or "Could not build the sky", "error")
            C.SkyOn = false
            if TOG.SkyOn then TOG.SkyOn:Set(false, true) end
            return
        end
        if not skyObj then
            skyObj = Instance.new("Sky")
            skyObj.Name = U.rname()
        end
        skyObj.StarCount = 0
        for prop, asset in pairs(textures) do skyObj[prop] = asset end
        skyObj.CelestialBodiesShown = C.SkySun
        hideGameSkies()
        skyObj.Parent = Lighting
    end)
end

toggle(skySec, "Custom Skybox", "SkyOn", false, function(v)
    if v then skyOn() else skyOff() end
end)
dropdown(skySec, "Source", "SkySource", { "Preset", "Image" }, "Preset", function()
    if C.SkyOn then skyOn() end
end)
dropdown(skySec, "Preset", "SkyPreset", SKY_PRESET_NAMES, "Neon Night", function()
    if C.SkyOn and C.SkySource == "Preset" then skyOn() end
end)
skySec:TextBox({ Text = "Image (id / link / file)", Placeholder = "rbxassetid://123 or https://... or mysky.png",
    Flag = "SkyImage", NoSave = true, Callback = function(t) skyImageText = t or "" end })
skySec:Button({ Text = "Use This Image", Callback = function()
    C.SkySource = "Image"
    C.SkyOn = true
    if TOG.SkyOn then TOG.SkyOn:Set(true, true) end
    skyOn()
end })

toggle(skyLook, "Show Sun & Moon", "SkySun", true, function(v)
    if skyObj then skyObj.CelestialBodiesShown = v end
end)
slider(skyLook, "Rotate Sky", "SkySpin", 0, 30, 0, { Decimals = 1, Suffix = "°/s" })

local skySlow, skyAngle = 0, 0
renderLast(function(dt)
    if not (C.SkyOn and U.Running and skyObj) then return end
    skyAngle = (skyAngle + C.SkySpin * dt) % 360
    skyObj.SkyboxOrientation = Vector3.new(0, skyAngle, 0)
    skySlow += dt
    if skySlow < 0.5 then return end
    skySlow = 0
    -- games put their own sky back now and then; ours stays the one that shows
    if skyObj.Parent ~= Lighting then skyObj.Parent = Lighting end
    hideGameSkies()
end)
onUnload(skyOff)

Ready()
