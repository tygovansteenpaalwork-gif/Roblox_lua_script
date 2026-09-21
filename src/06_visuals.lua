----------------------------------------------------------------------
-- tab: Visuals (shader-pack style: vivid colours, bloom, sun rays, depth of field, Future lighting, reflections)
-- No colour tint anywhere: the ColorCorrection tint stays white, only saturation / contrast change.
----------------------------------------------------------------------

;(function()   -- own function: the main chunk is out of local registers
local vibeTab = win:Tab("Visuals")
local gradeSec = vibeTab:Section("Shaders")
local lightSec = vibeTab:Section("Lighting", "right")
local timeSec = vibeTab:Section("Time Of Day", "right")

local PRESET_NAMES = { "Natural", "Vivid", "Ultra Vivid", "Extreme", "Hyper", "Cinematic" }
local PRESETS = {
    ["Natural"]     = { sat = 0.15, contrast = 0.10, bloom = 0.30, sun = 0.10, dof = 0 },
    ["Vivid"]       = { sat = 0.45, contrast = 0.20, bloom = 0.50, sun = 0.20, dof = 0 },
    ["Ultra Vivid"] = { sat = 0.80, contrast = 0.30, bloom = 0.80, sun = 0.30, dof = 0 },
    ["Extreme"]     = { sat = 1.30, contrast = 0.40, bloom = 1.00, sun = 0.40, dof = 0 },
    ["Hyper"]       = { sat = 2.00, contrast = 0.50, bloom = 1.40, sun = 0.50, dof = 0 },
    ["Cinematic"]   = { sat = 0.25, contrast = 0.30, bloom = 0.60, sun = 0.20, dof = 0.30 },
}
local function preset() return PRESETS[C.ShLook] or PRESETS.Vivid end

-- vivid colours: our own ColorCorrection / Bloom / SunRays / DepthOfField, removed again when off
local cc, bloom, sun, dof

local function ensureFx()
    if not (cc and cc.Parent) then cc = Instance.new("ColorCorrectionEffect") cc.Name = U.rname() cc.Parent = Lighting end
    if not (bloom and bloom.Parent) then bloom = Instance.new("BloomEffect") bloom.Name = U.rname() bloom.Size = 24 bloom.Threshold = 0.9 bloom.Parent = Lighting end
    if not (sun and sun.Parent) then sun = Instance.new("SunRaysEffect") sun.Name = U.rname() sun.Spread = 0.7 sun.Parent = Lighting end
    if not (dof and dof.Parent) then
        dof = Instance.new("DepthOfFieldEffect") dof.Name = U.rname()
        dof.NearIntensity, dof.FocusDistance, dof.InFocusRadius = 0, 60, 40
        dof.Parent = Lighting
    end
end

local function applyShader()
    ensureFx()
    local k, p = C.ShIntensity / 100, preset()
    cc.TintColor = Color3.new(1, 1, 1)
    cc.Saturation, cc.Contrast, cc.Brightness = p.sat * k, p.contrast * k, 0
    bloom.Intensity = p.bloom * k
    sun.Intensity = p.sun * k
    dof.FarIntensity = p.dof * k
end

local function restoreShader()
    for _, o in ipairs({ cc, bloom, sun, dof }) do if o then pcall(function() o:Destroy() end) end end
    cc, bloom, sun, dof = nil, nil, nil, nil
end

-- lighting engine: Future lighting (hidden property), sun shadows and sky reflections
local techOrig, reflOrig, qualOrig

local function setFuture(v)
    if v then
        if techOrig == nil then
            local ok, cur = pcall(function() return gethiddenproperty(Lighting, "Technology") end)
            if ok then techOrig = cur end
        end
        if not pcall(function() sethiddenproperty(Lighting, "Technology", Enum.Technology.Future) end) then
            notify("Future Lighting", "This executor cannot change the lighting engine", "warn")
        end
    elseif techOrig ~= nil then
        pcall(function() sethiddenproperty(Lighting, "Technology", techOrig) end)
        techOrig = nil
    end
end

local function applyReflect()
    if not reflOrig then
        reflOrig = { GlobalShadows = Lighting.GlobalShadows, EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
            EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale }
        pcall(function() reflOrig.ShadowSoftness = Lighting.ShadowSoftness end)
    end
    pcall(function() Lighting.ShadowSoftness = 0.45 end)
    Lighting.GlobalShadows = true
    Lighting.EnvironmentDiffuseScale = 1
    Lighting.EnvironmentSpecularScale = 1
end

local function restoreReflect()
    if not reflOrig then return end
    for k, v in pairs(reflOrig) do pcall(function() Lighting[k] = v end) end
    reflOrig = nil
end

local function setMaxQuality(v)
    local ok, r = pcall(settings)
    if not (ok and r) then return end
    if v then
        if qualOrig == nil then qualOrig = r.Rendering.QualityLevel end
        pcall(function() r.Rendering.QualityLevel = Enum.QualityLevel.Level21 end)
    elseif qualOrig ~= nil then
        pcall(function() r.Rendering.QualityLevel = qualOrig end)
        qualOrig = nil
    end
end

-- clear air: no haze, no fog (only lowers them, adds no colour)
local airOrig, airFog
local function applyAir()
    if not airFog then airFog = { FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd } airOrig = {} end
    Lighting.FogStart, Lighting.FogEnd = 1e6, 1e6
    for _, a in ipairs(Lighting:GetChildren()) do
        if a:IsA("Atmosphere") then
            if not airOrig[a] then airOrig[a] = { Density = a.Density, Haze = a.Haze } end
            a.Density, a.Haze = math.min(a.Density, 0.2), 0
        end
    end
end
local function restoreAir()
    if not airFog then return end
    for k, v in pairs(airFog) do pcall(function() Lighting[k] = v end) end
    for a, sv in pairs(airOrig) do pcall(function() a.Density, a.Haze = sv.Density, sv.Haze end) end
    airFog, airOrig = nil, nil
end

-- rich light: a brighter, punchier sun
local lightOrig
local function applyLight()
    if not lightOrig then lightOrig = { Brightness = Lighting.Brightness, ExposureCompensation = Lighting.ExposureCompensation } end
    Lighting.Brightness = math.max(lightOrig.Brightness, 3)
    Lighting.ExposureCompensation = lightOrig.ExposureCompensation + 0.25
end
local function restoreLight()
    if not lightOrig then return end
    for k, v in pairs(lightOrig) do pcall(function() Lighting[k] = v end) end
    lightOrig = nil
end

-- pretty water: clearer, reflective, calmer waves
local waterOrig
local WATER_PROPS = { "WaterReflectance", "WaterTransparency", "WaterWaveSize", "WaterWaveSpeed" }
local function setWater(v)
    local t = workspace.Terrain
    if v then
        if not waterOrig then
            waterOrig = {}
            for _, k in ipairs(WATER_PROPS) do waterOrig[k] = t[k] end
        end
        t.WaterReflectance, t.WaterTransparency, t.WaterWaveSize, t.WaterWaveSpeed = 1, 0.85, 0.25, 12
    elseif waterOrig then
        for k, val in pairs(waterOrig) do pcall(function() t[k] = val end) end
        waterOrig = nil
    end
end

-- extra stars in the night sky
local starOrig = setmetatable({}, { __mode = "k" })
local function setStars(v)
    for _, sky in ipairs(Lighting:GetChildren()) do
        if sky:IsA("Sky") then
            if v then
                if starOrig[sky] == nil then starOrig[sky] = sky.StarCount end
                sky.StarCount = 5000
            elseif starOrig[sky] ~= nil then
                sky.StarCount = starOrig[sky]
                starOrig[sky] = nil
            end
        end
    end
end

local timeOrig
local function restoreTime()
    if timeOrig ~= nil then Lighting.ClockTime = timeOrig timeOrig = nil end
end

-- ui ---------------------------------------------------------------------------
toggle(gradeSec, "Vivid Colors", "ShOn", false, function(v)
    if v then applyShader() else restoreShader() end
end)
dropdown(gradeSec, "Look", "ShLook", PRESET_NAMES, "Vivid", function()
    if C.ShOn then applyShader() end
end)
slider(gradeSec, "Intensity", "ShIntensity", 0, 100, 100, { Suffix = "%", OnChange = function()
    if C.ShOn then applyShader() end
end })

toggle(lightSec, "Future Lighting", "ShFuture", false, setFuture)
toggle(lightSec, "Shadows & Reflections", "ShReflect", false, function(v)
    if v then applyReflect() else restoreReflect() end
end)
toggle(lightSec, "Max Graphics", "ShMax", false, setMaxQuality)
toggle(lightSec, "Rich Light", "ShLight", false, function(v)
    if v then applyLight() else restoreLight() end
end)
toggle(lightSec, "Clear Air", "ShAir", false, function(v)
    if v then applyAir() else restoreAir() end
end)
toggle(lightSec, "Pretty Water", "ShWater", false, setWater)
toggle(lightSec, "Extra Stars", "ShStars", false, setStars)

toggle(timeSec, "Lock Time", "ShTime", false, function(v)
    if not v then restoreTime() end
end)
slider(timeSec, "Time Of Day", "ShClock", 0, 24, 14, { Decimals = 1 })

onUnload(function() restoreShader() setFuture(false) restoreReflect() setMaxQuality(false) restoreLight() restoreAir() setWater(false) setStars(false) restoreTime() end)

local slowAt = 0
renderLast(function(dt)
    if not U.Running then return end
    if C.ShTime then
        if timeOrig == nil then timeOrig = Lighting.ClockTime end
        Lighting.ClockTime = C.ShClock
    end
    slowAt += dt
    if slowAt < 0.3 then return end
    slowAt = 0
    -- games reset their lighting now and then; keep our look on
    if C.ShOn then applyShader() end
    if C.ShReflect then applyReflect() end
    if C.ShLight then applyLight() end
    if C.ShAir then applyAir() end
end)
end)()

