--[[
    Clean Visuals  -  clean_visuals.lua
    Removes screen effects, fog and particles; can switch off camera shake.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/clean_visuals.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "clean_visuals", Title = "Clean Visuals" })

local C, Lighting, Ready, U, cam, connect = ctx.C, ctx.Lighting, ctx.Ready, ctx.U, ctx.cam, ctx.connect
local myHumanoid, onUnload, renderLast, toggle, win = ctx.myHumanoid, ctx.onUnload, ctx.renderLast, ctx.toggle, ctx.win

local uniTab = win:Tab("Clean Visuals")
local cleanSec = uniTab:Section("Clean Visuals")

-- clean visuals -------------------------------------------------------------
-- Everything we touch is remembered (weak tables) and put back when the switch goes off.
-- Particles are also made fully transparent, because games often :Emit() them while Enabled is
-- false, which would otherwise still draw.

local EFFECT_CLASSES = {
    BlurEffect = true, DepthOfFieldEffect = true, BloomEffect = true,
    ColorCorrectionEffect = true, SunRaysEffect = true,
}
local effectOrig = setmetatable({}, { __mode = "k" })
local atmoOrig = setmetatable({}, { __mode = "k" })
local vfxOrig = setmetatable({}, { __mode = "k" })
local fogOrig

local function isVfx(inst)
    return inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles")
end

local function hideVfx(inst)
    local saved = vfxOrig[inst]
    if not saved then
        saved = { Enabled = inst.Enabled }
        if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") then saved.Transparency = inst.Transparency end
        vfxOrig[inst] = saved
    end
    inst.Enabled = false
    if saved.Transparency then inst.Transparency = NumberSequence.new(1) end
end

local function applyEffects()
    for _, parent in ipairs({ Lighting, cam() }) do
        if parent then
            for _, inst in ipairs(parent:GetChildren()) do
                if EFFECT_CLASSES[inst.ClassName] then
                    if effectOrig[inst] == nil then effectOrig[inst] = inst.Enabled end
                    if inst.Enabled then inst.Enabled = false end
                end
            end
        end
    end
end

local function restoreEffects()
    for inst, was in pairs(effectOrig) do
        pcall(function() inst.Enabled = was end)
        effectOrig[inst] = nil
    end
end

local function applyFog()
    if not fogOrig then fogOrig = { FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd } end
    Lighting.FogStart, Lighting.FogEnd = 1e6, 1e6
    for _, a in ipairs(Lighting:GetChildren()) do
        if a:IsA("Atmosphere") then
            if not atmoOrig[a] then atmoOrig[a] = { Density = a.Density, Haze = a.Haze } end
            a.Density, a.Haze = 0, 0
        end
    end
end

local function restoreFog()
    if fogOrig then
        pcall(function() Lighting.FogStart, Lighting.FogEnd = fogOrig.FogStart, fogOrig.FogEnd end)
        fogOrig = nil
    end
    for a, saved in pairs(atmoOrig) do
        pcall(function() a.Density, a.Haze = saved.Density, saved.Haze end)
        atmoOrig[a] = nil
    end
end

local function restoreVfx()
    for inst, saved in pairs(vfxOrig) do
        pcall(function()
            inst.Enabled = saved.Enabled
            if saved.Transparency then inst.Transparency = saved.Transparency end
        end)
        vfxOrig[inst] = nil
    end
end

toggle(cleanSec, "Remove Screen Effects", "CleanEffects", false, function(v)
    if v then applyEffects() else restoreEffects() end
end)
toggle(cleanSec, "Remove Fog & Atmosphere", "CleanFog", false, function(v)
    if v then applyFog() else restoreFog() end
end)
toggle(cleanSec, "Remove Particles & Trails", "CleanParticles", false, function(v)
    if not v then restoreVfx() return end
    task.spawn(function()
        local n = 0
        for _, d in ipairs(workspace:GetDescendants()) do
            if not (C.CleanParticles and U.Running) then return end
            if isVfx(d) then hideVfx(d) end
            n += 1
            if n % 3000 == 0 then task.wait() end   -- big maps: do not freeze a frame
        end
    end)
end)
toggle(cleanSec, "No Camera Shake", "CleanShake", false)
onUnload(function() restoreEffects() restoreFog() restoreVfx() end)

connect(workspace.DescendantAdded, function(inst)
    if C.CleanParticles and U.Running and isVfx(inst) then hideVfx(inst) end
end)

local cleanAt = 0
renderLast(function(dt)
    if not U.Running then return end
    if C.CleanShake then
        local hum = myHumanoid()
        if hum and hum.CameraOffset ~= Vector3.zero then hum.CameraOffset = Vector3.zero end
    end
    cleanAt += dt
    if cleanAt < 0.3 then return end
    cleanAt = 0
    -- games switch their own effects back on; keep them off
    if C.CleanEffects then applyEffects() end
    if C.CleanFog then applyFog() end
    if C.CleanParticles then
        for inst in pairs(vfxOrig) do
            if inst.Parent and inst.Enabled then inst.Enabled = false end
        end
    end
end)

Ready()
