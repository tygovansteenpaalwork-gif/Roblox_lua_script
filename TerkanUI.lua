--[[
    TerkanUI  -  minimal dark/red exploit UI library
    Layout: topbar (title + stats) | sidebar tabs | 2 content columns | footer

    Quick start:
        local UI = loadstring(readfile("TerkanUI.lua"))()
        local win = UI:Window({ Title = "TERKAN", Version = "V 1.0", Footer = "Terkan Steal a Egg V4.6" })
        local main = win:Tab("Main")
        local aim  = main:Section("Aimbot")            -- left column
        local def  = main:Section("Defense", "right")  -- right column

        aim:Dropdown({ Text = "Areas", Options = {"All","Front","Back"}, Default = "All", Callback = print })
        aim:Toggle({ Text = "Auto Steal Selected", Default = true, Callback = print })
        def:Slider({ Text = "Aura Range", Min = 5, Max = 50, Default = 15, Callback = print })
        def:TextBox({ Text = "Cash Reserve", Default = "0", Numeric = true, Callback = print })
--]]

local Players           = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")
local Stats              = game:GetService("Stats")
local HttpService        = game:GetService("HttpService")
local Lighting           = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------------
-- theme
----------------------------------------------------------------------

local Theme = {
    Accent      = Color3.fromRGB(255, 32, 48),
    AccentDark  = Color3.fromRGB(120, 10, 20),
    AccentDeep  = Color3.fromRGB(58, 5, 11),

    Bg          = Color3.fromRGB(11, 4, 6),
    BgTop       = Color3.fromRGB(19, 5, 8),
    Field       = Color3.fromRGB(28, 7, 11),
    FieldHover  = Color3.fromRGB(40, 9, 14),

    Border      = Color3.fromRGB(96, 14, 24),
    BorderSoft  = Color3.fromRGB(60, 10, 18),

    Text        = Color3.fromRGB(232, 226, 227),
    TextDim     = Color3.fromRGB(150, 132, 136),
    TextFaint   = Color3.fromRGB(104, 90, 94),

    Off         = Color3.fromRGB(44, 44, 46),
    OffKnob     = Color3.fromRGB(255, 255, 255),
}

----------------------------------------------------------------------
-- theming
--   A theme is just an accent colour; every other role is derived from it. Applying a
--   theme walks the whole GUI and swaps each old role colour for the new one, so nothing
--   has to be registered per element. Instances tagged "TerkanNoTheme" (colour pickers,
--   swatches) are skipped on purpose.
----------------------------------------------------------------------

local THEME_ROLES = { "Accent", "AccentDark", "AccentDeep", "Bg", "BgTop", "Field", "FieldHover", "Border", "BorderSoft" }

local DEFAULT_ROLES = {}
for _, role in ipairs(THEME_ROLES) do DEFAULT_ROLES[role] = Theme[role] end

local function deriveTheme(accent)
    local maxc = math.max(accent.R, accent.G, accent.B, 0.001)
    local hue = Color3.new(accent.R / maxc, accent.G / maxc, accent.B / maxc)
    local out = { Accent = accent }
    for _, role in ipairs(THEME_ROLES) do
        if role ~= "Accent" then
            local d = DEFAULT_ROLES[role]
            local k = math.max(d.R, d.G, d.B)
            out[role] = Color3.new(hue.R * k, hue.G * k, hue.B * k)
        end
    end
    return out
end

local Themes = {
    ["Terkan Red"] = DEFAULT_ROLES,
    ["Ocean Blue"] = deriveTheme(Color3.fromRGB(46, 134, 255)),
    ["Emerald"]    = deriveTheme(Color3.fromRGB(38, 214, 118)),
    ["Violet"]     = deriveTheme(Color3.fromRGB(150, 92, 255)),
    ["Rose"]       = deriveTheme(Color3.fromRGB(255, 84, 160)),
    ["Amber"]      = deriveTheme(Color3.fromRGB(255, 166, 30)),
    ["Cyan"]       = deriveTheme(Color3.fromRGB(30, 214, 230)),
    ["Snow"]       = deriveTheme(Color3.fromRGB(235, 235, 240)),
}
local ThemeNames = { "Terkan Red", "Ocean Blue", "Emerald", "Violet", "Rose", "Amber", "Cyan", "Snow" }

local function colorKey(c)
    return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local Sizes = {
    Window      = Vector2.new(720, 566),
    TopBar      = 48,
    Footer      = 32,
    Sidebar     = 156,
    Row         = 30,   -- dropdown / textbox / button height
    Slider      = 28,
    Gap         = 7,    -- gap between elements
    SectionGap  = 16,
    Pad         = 16,
}

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local FONT_FAMILY = "rbxasset://fonts/families/RobotoMono.json"

local function applyFont(inst, weight)
    local ok = pcall(function()
        inst.FontFace = Font.new(FONT_FAMILY, weight or Enum.FontWeight.Regular)
    end)
    if not ok then
        inst.Font = Enum.Font.Code
    end
end

-- random neutral name for anything a game script could look at (see the same helper in TerkanUniversal)
local function randomName()
    local letters, out = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", {}
    for i = 1, math.random(8, 12) do
        local k = math.random(1, #letters)
        out[i] = letters:sub(k, k)
    end
    return table.concat(out)
end

local function new(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then inst[k] = v end
    end
    if parent then inst.Parent = parent end
    return inst
end

-- sharp corners everywhere: no-op kept so call sites don't need touching
local function corner(inst, radius)
    return nil
end

local function stroke(inst, color, thickness, transparency)
    return new("UIStroke", {
        Color = color or Theme.BorderSoft,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, inst)
end

local function padding(inst, t, b, l, r)
    return new("UIPadding", {
        PaddingTop    = UDim.new(0, t or 0),
        PaddingBottom = UDim.new(0, b or 0),
        PaddingLeft   = UDim.new(0, l or 0),
        PaddingRight  = UDim.new(0, r or 0),
    }, inst)
end

local function vlist(inst, pad)
    return new("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, pad or 0),
    }, inst)
end

local function tween(inst, props, time, style)
    local t = TweenService:Create(inst, TweenInfo.new(time or 0.14,
        style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

local function text(parent, str, size, color, weight, align)
    local lbl = new("TextLabel", {
        BackgroundTransparency = 1,
        Text = str or "",
        TextSize = size or 13,
        TextColor3 = color or Theme.Text,
        TextXAlignment = align or Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,   -- a label that is too long ends in "..." instead of running under the control
        Size = UDim2.new(1, 0, 1, 0),
    }, parent)
    applyFont(lbl, weight)
    return lbl
end

local function round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(value * mult + 0.5) / mult
end

-- accepts both Toggle({Text=..}) and Toggle("Text", default, callback)
local function cfg(a, ...)
    if type(a) == "table" then return a end
    local extra = { ... }
    return { Text = a, _positional = extra }
end

local function getParentGui()
    if gethui then
        local ok, res = pcall(gethui)
        if ok and res then return res end
    end
    local ok, core = pcall(function() return game:GetService("CoreGui") end)
    if ok and core then return core end
    return LocalPlayer:WaitForChild("PlayerGui")
end

----------------------------------------------------------------------
-- library root
----------------------------------------------------------------------

local TerkanUI = {}

-- Every element callback runs inside this guard: an error is reported once through TerkanUI.OnError (the hub shows it
-- as a notification) instead of vanishing into the console.
local function guardCallback(cb)
    if not cb then return nil end
    return function(...)
        local ok, err = pcall(cb, ...)
        if not ok then (TerkanUI.OnError or warn)(err) end
    end
end
TerkanUI.__index = TerkanUI

local Window  = {}; Window.__index  = Window
local Tab     = {}; Tab.__index     = Tab
local Section = {}; Section.__index = Section

function TerkanUI:Window(options)
    options = options or {}

    local self = setmetatable({
        Title      = options.Title or "TERKAN",
        Version    = options.Version or "V 1.0",
        Footer     = options.Footer or "",
        ToggleKey  = options.ToggleKey or Enum.KeyCode.RightShift,
        Tabs       = {},
        Accented   = {},     -- kept for old call sites; theming now walks the GUI instead
        Conns      = {},
        OpenMenu   = nil,    -- currently open dropdown
        Flags      = {},     -- [flag] = { Kind, Get, Set }  (everything saved in configs)
        ConfigFolder = options.ConfigFolder or "Terkan",
        BlurEnabled = false,
        BlurSize   = 16,
        Notifications = {
            Enabled = true,
            Duration = 4,
            Position = "Bottom Right",
            UseThemeColor = true,
            Color = Color3.fromRGB(255, 32, 48),
            Max = 5,
        },
    }, Window)

    local size = options.Size or Sizes.Window

    -- screen gui -----------------------------------------------------
    local gui = new("ScreenGui", {
        Name = randomName(),
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 9999,
    })
    pcall(function() gui.Parent = getParentGui() end)
    if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
    self.Gui = gui

    local scale = new("UIScale", { Scale = options.Scale or 1 }, gui)
    self.Scale = scale

    -- main frame -----------------------------------------------------
    local main = new("Frame", {
        Name = "Main",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size.X, size.Y),
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel = 0,
        ClipsDescendants = false,
    }, gui)
    corner(main, 9)
    -- one plain 2px border, nothing else (no glow ring, no accent streak)
    local mainStroke = stroke(main, Theme.Accent, 2, 0)
    self.Main = main
    table.insert(self.Accented, { mainStroke, "Color" })

    -- top bar --------------------------------------------------------
    local topbar = new("Frame", {
        Name = "TopBar",
        Size = UDim2.new(1, 0, 0, Sizes.TopBar),
        BackgroundColor3 = Theme.BgTop,
        BorderSizePixel = 0,
    }, main)
    corner(topbar, 9)
    new("Frame", { -- square off the bottom corners
        Size = UDim2.new(1, 0, 0, 12),
        Position = UDim2.new(0, 0, 1, -12),
        BackgroundColor3 = Theme.BgTop,
        BorderSizePixel = 0,
    }, topbar)

    -- bottom divider of the topbar
    local topLine = new("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        ZIndex = 4,
    }, topbar)
    table.insert(self.Accented, { topLine, "BackgroundColor3" })

    local title = text(topbar, self.Title, 20, Theme.Accent, Enum.FontWeight.Bold)
    title.Position = UDim2.new(0, Sizes.Pad + 10, 0, 0)
    title.Size = UDim2.new(0, 300, 1, 0)
    title.ZIndex = 5
    self.TitleLabel = title
    table.insert(self.Accented, { title, "TextColor3" })

    -- stat readouts (FPS / PING / VER), right aligned
    local stats = new("Frame", {
        Name = "Stats",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -(Sizes.Pad + 8), 0.5, 0),
        Size = UDim2.new(0, 340, 0, 20),
        BackgroundTransparency = 1,
        ZIndex = 5,
    }, topbar)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 18),
    }, stats)

    local function statEntry(order, name, initial)
        local holder = new("Frame", {
            BackgroundTransparency = 1,
            LayoutOrder = order,
            AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.new(0, 0, 1, 0),
        }, stats)
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 5),
        }, holder)

        local key = text(holder, name .. ":", 13, Theme.TextDim, Enum.FontWeight.Medium)
        key.AutomaticSize = Enum.AutomaticSize.X
        key.Size = UDim2.new(0, 0, 1, 0)

        local val = text(holder, initial, 13, Theme.Accent, Enum.FontWeight.Bold)
        val.AutomaticSize = Enum.AutomaticSize.X
        val.Size = UDim2.new(0, 0, 1, 0)
        table.insert(self.Accented, { val, "TextColor3" })
        return val
    end

    local fpsVal  = statEntry(1, "FPS", "0")
    local pingVal = statEntry(2, "PING", "0")
    statEntry(3, "VER", self.Version)

    -- sidebar --------------------------------------------------------
    -- a scrolling list: with many tabs the last ones (Settings!) must never fall out of view
    local sidebar = new("ScrollingFrame", {
        Name = "Sidebar",
        Position = UDim2.new(0, 0, 0, Sizes.TopBar),
        Size = UDim2.new(0, Sizes.Sidebar, 1, -(Sizes.TopBar + Sizes.Footer)),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.35,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ClipsDescendants = true,
    }, main)
    padding(sidebar, 12, 10, 12, 10)
    vlist(sidebar, 3)
    table.insert(self.Accented, { sidebar, "ScrollBarImageColor3" })
    self.Sidebar = sidebar

    local sideLine = new("Frame", {
        Position = UDim2.new(0, Sizes.Sidebar, 0, Sizes.TopBar),
        Size = UDim2.new(0, 1, 1, -(Sizes.TopBar + Sizes.Footer)),
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
    }, main)
    table.insert(self.Accented, { sideLine, "BackgroundColor3" })

    -- body (holds one page per tab) ----------------------------------
    local body = new("Frame", {
        Name = "Body",
        Position = UDim2.new(0, Sizes.Sidebar + 1, 0, Sizes.TopBar),
        Size = UDim2.new(1, -(Sizes.Sidebar + 1), 1, -(Sizes.TopBar + Sizes.Footer)),
        BackgroundTransparency = 1,
    }, main)
    self.Body = body

    -- footer ---------------------------------------------------------
    local footer = new("Frame", {
        Name = "Footer",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, Sizes.Footer),
        BackgroundTransparency = 1,
    }, main)
    local footLine = new("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.55,
        BorderSizePixel = 0,
    }, footer)
    table.insert(self.Accented, { footLine, "BackgroundColor3" })

    local footText = text(footer, self.Footer, 12, Theme.TextFaint, Enum.FontWeight.Medium,
        Enum.TextXAlignment.Center)
    self.FooterLabel = footText

    -- overlay (dropdown menus escape the scrolling frames) -----------
    local overlay = new("Frame", {
        Name = "Overlay",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 50,
        Visible = false,
    }, main)
    self.Overlay = overlay

    local blocker = new("TextButton", {
        Name = "Blocker",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 50,
    }, overlay)
    blocker.MouseButton1Click:Connect(function()
        self:CloseMenu()
    end)

    -- behaviour ------------------------------------------------------
    -- one shared drag controller for the window and every slider. release is
    -- watched globally: InputEnded on the element itself never fires when the
    -- cursor leaves it before the button comes up, which sticks the drag on.
    self.ActiveDrag = nil
    table.insert(self.Conns, UserInputService.InputChanged:Connect(function(input)
        if not self.ActiveDrag then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            self.ActiveDrag(input.Position)
        end
    end))
    table.insert(self.Conns, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            self.ActiveDrag = nil
        end
    end))

    self:_makeDraggable(topbar)

    table.insert(self.Conns, UserInputService.InputBegan:Connect(function(input, gp)
        if UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == self.ToggleKey then
            self:SetVisible(not main.Visible)
        end
    end))

    -- fps / ping
    local frames, elapsed = 0, 0
    table.insert(self.Conns, RunService.RenderStepped:Connect(function(dt)
        frames += 1
        elapsed += dt
        if elapsed >= 0.5 then
            fpsVal.Text = tostring(math.floor(frames / elapsed + 0.5))
            frames, elapsed = 0, 0
            local ok, ping = pcall(function()
                return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5)
            end)
            pingVal.Text = ok and tostring(ping) or "-"
        end
    end))

    -- open animation
    main.Size = UDim2.fromOffset(size.X, 0)
    tween(main, { Size = UDim2.fromOffset(size.X, size.Y) }, 0.25, Enum.EasingStyle.Quart)

    return self
end

-- keep the old spelling working
TerkanUI.new = TerkanUI.Window
TerkanUI.CreateWindow = TerkanUI.Window

----------------------------------------------------------------------
-- window methods
----------------------------------------------------------------------

function Window:_makeDraggable(handle)
    local main = self.Main

    handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end

        local startInput, startPos = input.Position, main.Position
        self:CloseMenu()
        self.ActiveDrag = function(position)
            local delta = position - startInput
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

function Window:CloseMenu()
    if self.OpenMenu then
        self.OpenMenu()
        self.OpenMenu = nil
    end
    self.Overlay.Visible = false
end

function Window:SetVisible(state)
    self.Main.Visible = state
    if not state then self:CloseMenu() end
    self:_updateBlur()
end

function Window:Toggle()
    self:SetVisible(not self.Main.Visible)
end

function Window:SetToggleKey(keyCode)
    self.ToggleKey = keyCode
end

function Window:SetScale(value)
    self.Scale.Scale = value
end

function Window:SetTitle(str)
    self.TitleLabel.Text = str
end

function Window:SetFooter(str)
    self.FooterLabel.Text = str
end

local COLOR_PROPS = { "BackgroundColor3", "TextColor3", "ImageColor3", "ScrollBarImageColor3", "Color", "PlaceholderColor3" }

function Window:ApplyTheme(roles)
    local map = {}
    for _, role in ipairs(THEME_ROLES) do
        local key = colorKey(Theme[role])
        if map[key] == nil then map[key] = roles[role] end
    end

    local function protected(inst)
        local p = inst
        while p and p ~= self.Gui do
            if p:GetAttribute("TerkanNoTheme") then return true end
            p = p.Parent
        end
        return false
    end

    for _, inst in ipairs(self.Gui:GetDescendants()) do
        for _, prop in ipairs(COLOR_PROPS) do
            local ok, cur = pcall(function() return inst[prop] end)
            if ok and typeof(cur) == "Color3" then
                local new = map[colorKey(cur)]
                if new and not protected(inst) then
                    pcall(function() inst[prop] = new end)
                end
            end
        end
    end

    for _, role in ipairs(THEME_ROLES) do Theme[role] = roles[role] end
    self.Notifications.Color = self.Notifications.UseThemeColor and Theme.Accent or self.Notifications.Color
end

function Window:SetAccent(color)
    self:ApplyTheme(deriveTheme(color))
end

function Window:SetTheme(name)
    local roles = Themes[name]
    if not roles then return false end
    self.ThemeName = name
    self:ApplyTheme(roles)
    return true
end

function Window:GetThemeNames() return ThemeNames end

-- blur behind the menu while it is open ------------------------------

function Window:_updateBlur()
    local want = self.BlurEnabled and self.Main and self.Main.Visible
    if want then
        if not self.Blur then
            self.Blur = new("BlurEffect", { Name = randomName(), Size = 0 }, Lighting)
        end
        tween(self.Blur, { Size = self.BlurSize }, 0.2)
    elseif self.Blur then
        tween(self.Blur, { Size = 0 }, 0.2)
    end
end

function Window:SetBlur(enabled, size)
    self.BlurEnabled = enabled and true or false
    if size then self.BlurSize = size end
    self:_updateBlur()
end

-- flags + configs ----------------------------------------------------

local function encodeValue(kind, v)
    if kind == "color" then return "#" .. v:ToHex() end
    if kind == "keybind" then return v and tostring(v) or "" end
    return v
end

local function decodeValue(kind, v)
    if kind == "color" then
        local ok, c = pcall(Color3.fromHex, tostring(v))
        return ok and c or nil
    end
    if kind == "keybind" then
        if type(v) ~= "string" or v == "" then return nil end
        local enumType, name = v:match("^Enum%.(%w+)%.(%w+)$")
        if enumType and Enum[enumType] and Enum[enumType][name] then return Enum[enumType][name] end
        return nil
    end
    return v
end

local function fsAvailable()
    return typeof(writefile) == "function" and typeof(readfile) == "function"
        and typeof(isfile) == "function" and typeof(isfolder) == "function"
        and typeof(makefolder) == "function" and typeof(listfiles) == "function"
end

local function cleanName(name)
    return (tostring(name or ""):gsub("[^%w _%-]", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Window:_register(flag, kind, api, noSave)
    if not flag then return end
    self.Flags[flag] = {
        Kind = kind,
        NoSave = noSave,
        Api = api,
        Get = function() return api:Get() end,
        Set = function(v, silent) api:Set(v, silent) end,
    }
end

function Window:GetFlag(flag)
    local entry = self.Flags[flag]
    return entry and entry.Get()
end

function Window:_configDir()
    local root = self.ConfigFolder
    pcall(function()
        if not isfolder(root) then makefolder(root) end
        if not isfolder(root .. "/configs") then makefolder(root .. "/configs") end
    end)
    return root .. "/configs"
end

function Window:ListConfigs()
    local names = {}
    if not fsAvailable() then return names end
    local ok, files = pcall(listfiles, self:_configDir())
    if ok then
        for _, path in ipairs(files) do
            local name = tostring(path):match("([^/\\]+)%.json$")
            if name then table.insert(names, name) end
        end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function Window:SaveConfig(name, overwrite)
    if not fsAvailable() then return false, "This executor has no file access" end
    name = cleanName(name)
    if name == "" then return false, "Enter a config name" end
    local path = self:_configDir() .. "/" .. name .. ".json"
    local exists = false
    pcall(function() exists = isfile(path) end)
    if exists and not overwrite then return false, "Config already exists" end
    if overwrite and not exists then return false, "Config does not exist" end

    local data = { version = 1, flags = {} }
    for flag, entry in pairs(self.Flags) do
        if not entry.NoSave then
            local ok, value = pcall(entry.Get)
            if ok and value ~= nil then data.flags[flag] = encodeValue(entry.Kind, value) end
            if ok and value == nil and entry.Kind == "keybind" then data.flags[flag] = "" end
        end
    end
    local ok, err = pcall(function() writefile(path, HttpService:JSONEncode(data)) end)
    if not ok then return false, tostring(err) end
    return true, name
end

-- The order in which LoadConfig applies the saved flags. pairs() has no fixed order, so a toggle could switch a
-- feature on (and run its callback) before the dropdowns / sliders that tell it HOW to run were loaded.
--   registered: self.Flags, [flag] = { Kind = "toggle" | "slider" | "dropdown" | "color" | "keybind" | ..., ... }
--   saved:      the flags in the config file, [flag] = raw value
-- Returns a list of flag names (from `saved`) in the order they must be applied.
-- Settings first, then keybinds, toggles last: a toggle's callback may start its feature right away, so everything
-- that feature reads must already be loaded. Alphabetical within a group, so every load runs in the same order.
local LOAD_RANK = { keybind = 1, toggle = 2 }   -- anything else (slider, dropdown, color, textbox, unknown) = 0
local function loadOrder(registered, saved)
    local order = {}
    for flag in pairs(saved) do table.insert(order, flag) end
    local function rank(flag)
        local entry = registered[flag]   -- nil for a flag from an older version that no longer exists
        return entry and LOAD_RANK[entry.Kind] or 0
    end
    table.sort(order, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    return order
end

function Window:LoadConfig(name)
    if not fsAvailable() then return false, "This executor has no file access" end
    name = cleanName(name)
    local path = self:_configDir() .. "/" .. name .. ".json"
    local exists = false
    pcall(function() exists = isfile(path) end)
    if not exists then return false, "Config not found" end

    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if not ok or type(data) ~= "table" or type(data.flags) ~= "table" then return false, "Config is corrupted" end

    local applied = 0
    for _, flag in ipairs(loadOrder(self.Flags, data.flags)) do
        local raw = data.flags[flag]
        local entry = self.Flags[flag]
        if entry then
            local value = decodeValue(entry.Kind, raw)
            if value ~= nil or entry.Kind == "keybind" then
                if pcall(entry.Set, value, false) then applied += 1 end
            end
        end
    end
    return true, applied
end

function Window:DeleteConfig(name)
    if not fsAvailable() or typeof(delfile) ~= "function" then return false, "Cannot delete files here" end
    local path = self:_configDir() .. "/" .. cleanName(name) .. ".json"
    local ok = pcall(delfile, path)
    return ok
end

function Window:GetAutoload()
    if not fsAvailable() then return nil end
    local path = self.ConfigFolder .. "/autoload.txt"
    local ok, value = pcall(function() return isfile(path) and readfile(path) or nil end)
    if ok and value and value ~= "" then return cleanName(value) end
end

function Window:SetAutoload(name)
    if not fsAvailable() then return false end
    self:_configDir()
    local path = self.ConfigFolder .. "/autoload.txt"
    local ok = pcall(function() writefile(path, name and cleanName(name) or "") end)
    return ok
end

function Window:LoadAutoload()
    local name = self:GetAutoload()
    if name then return self:LoadConfig(name) end
    return false, "No autoload set"
end

function Window:Destroy()
    for _, conn in ipairs(self.Conns) do
        pcall(function() conn:Disconnect() end)
    end
    if self.Blur then pcall(function() self.Blur:Destroy() end) end
    if self.Gui then self.Gui:Destroy() end
end

----------------------------------------------------------------------
-- tabs
----------------------------------------------------------------------

function Window:Tab(name)
    local win = self

    local page = new("Frame", {
        Name = "Page_" .. name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
    }, self.Body)

    -- two columns with a divider between them
    local function column(xScale, xOffset, widthScale, widthOffset)
        local sf = new("ScrollingFrame", {
            Position = UDim2.new(xScale, xOffset, 0, 0),
            Size = UDim2.new(widthScale, widthOffset, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Theme.Accent,
            ScrollBarImageTransparency = 0.35,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ClipsDescendants = true,
        }, page)
        padding(sf, Sizes.Pad, Sizes.Pad, Sizes.Pad, Sizes.Pad + 4)
        vlist(sf, Sizes.SectionGap)
        table.insert(win.Accented, { sf, "ScrollBarImageColor3" })
        return sf
    end

    local left  = column(0, 0, 0.5, -1)
    local right = column(0.5, 1, 0.5, -1)

    local colLine = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 10),
        Size = UDim2.new(0, 1, 1, -20),
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
    }, page)
    table.insert(win.Accented, { colLine, "BackgroundColor3" })

    -- sidebar button
    local btn = new("TextButton", {
        Name = "Tab_" .. name,
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Theme.AccentDeep,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = #self.Tabs + 1,
    }, self.Sidebar)
    corner(btn, 5)

    local bar = new("Frame", {
        Size = UDim2.new(0, 3, 1, -8),
        Position = UDim2.new(0, 0, 0, 4),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, btn)
    corner(bar, 2)
    table.insert(win.Accented, { bar, "BackgroundColor3" })

    local lbl = text(btn, name, 15, Theme.TextDim, Enum.FontWeight.Medium)
    lbl.Position = UDim2.new(0, 16, 0, 0)
    lbl.Size = UDim2.new(1, -16, 1, 0)

    local tab = setmetatable({
        Name = name,
        Window = self,
        Page = page,
        Left = left,
        Right = right,
        Button = btn,
        Label = lbl,
        Bar = bar,
        Sections = {},
    }, Tab)

    btn.MouseEnter:Connect(function()
        if self.ActiveTab ~= tab then
            tween(lbl, { TextColor3 = Theme.Text }, 0.12)
        end
    end)
    btn.MouseLeave:Connect(function()
        if self.ActiveTab ~= tab then
            tween(lbl, { TextColor3 = Theme.TextDim }, 0.12)
        end
    end)
    btn.MouseButton1Click:Connect(function()
        self:SelectTab(name)
    end)

    table.insert(self.Tabs, tab)
    if not self.ActiveTab then self:SelectTab(name) end
    return tab
end

-- name: the tab's name, or the tab object itself. An unknown name changes nothing (it used to hide every page and
-- leave an empty menu).
function Window:SelectTab(name)
    if type(name) == "table" then name = name.Name end
    local found = false
    for _, tab in ipairs(self.Tabs) do
        if tab.Name == name then found = true break end
    end
    if not found then return false end
    self:CloseMenu()
    for _, tab in ipairs(self.Tabs) do
        local active = (tab.Name == name)
        tab.Page.Visible = active
        tween(tab.Button, { BackgroundTransparency = active and 0.15 or 1 }, 0.14)
        tween(tab.Bar, { BackgroundTransparency = active and 0 or 1 }, 0.14)
        tween(tab.Label, { TextColor3 = active and Theme.Accent or Theme.TextDim }, 0.14)
        if active then self.ActiveTab = tab end
    end
end

----------------------------------------------------------------------
-- sections
----------------------------------------------------------------------

function Tab:Section(name, side)
    local parent = (side == "right" or side == "Right") and self.Right or self.Left
    local isFirst = true
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("Frame") then isFirst = false break end
    end

    local holder = new("Frame", {
        Name = "Section_" .. tostring(name),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = #parent:GetChildren(),
    }, parent)
    vlist(holder, Sizes.Gap)

    -- separator above every section except the first in its column
    if not isFirst then
        local sep = new("Frame", {
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.Border,
            BackgroundTransparency = 0.6,
            BorderSizePixel = 0,
            LayoutOrder = 0,
        }, holder)
        table.insert(self.Window.Accented, { sep, "BackgroundColor3" })
        new("UIPadding", { PaddingBottom = UDim.new(0, 4) }, sep)
    end

    local header = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 24),
        LayoutOrder = 1,
    }, holder)
    local hlbl = text(header, name, 17, Theme.Accent, Enum.FontWeight.Bold)
    table.insert(self.Window.Accented, { hlbl, "TextColor3" })

    local section = setmetatable({
        Name = name,
        Tab = self,
        Window = self.Window,
        Holder = holder,
        Order = 2,
    }, Section)

    table.insert(self.Sections, section)
    return section
end

function Section:_row(height)
    self.Order += 1
    return new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, height),
        LayoutOrder = self.Order,
    }, self.Holder)
end

-- label shown above a field (dropdown / textbox)
function Section:_fieldLabel(str)
    local row = self:_row(18)
    text(row, str, 14, Theme.Text, Enum.FontWeight.Regular)
    return row
end

----------------------------------------------------------------------
-- elements
----------------------------------------------------------------------

function Section:Label(str, color)
    local row = self:_row(18)
    local lbl = text(row, str, 13, color or Theme.TextDim, Enum.FontWeight.Regular)
    return {
        Set = function(_, s) lbl.Text = s end,
        Instance = row,
    }
end

function Section:Divider()
    local row = self:_row(9)
    local line = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.6,
        BorderSizePixel = 0,
    }, row)
    table.insert(self.Window.Accented, { line, "BackgroundColor3" })
    return { Instance = row }
end

function Section:Button(a, ...)
    local o = cfg(a, ...)
    local callback = guardCallback(o.Callback or (o._positional and o._positional[1]))

    local row = self:_row(Sizes.Row)
    local btn = new("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Field,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, row)
    corner(btn, 4)
    local st = stroke(btn, Theme.Border, 1, 0.3)
    table.insert(self.Window.Accented, { st, "Color" })

    local lbl = text(btn, o.Text or "Button", 14, Theme.Text, Enum.FontWeight.Medium,
        Enum.TextXAlignment.Center)

    btn.MouseEnter:Connect(function()
        tween(btn, { BackgroundColor3 = Theme.FieldHover }, 0.12)
        tween(lbl, { TextColor3 = Theme.Accent }, 0.12)
    end)
    btn.MouseLeave:Connect(function()
        tween(btn, { BackgroundColor3 = Theme.Field }, 0.12)
        tween(lbl, { TextColor3 = Theme.Text }, 0.12)
    end)
    btn.MouseButton1Click:Connect(function()
        tween(btn, { BackgroundColor3 = Theme.AccentDark }, 0.07)
        task.delay(0.09, function()
            if btn.Parent then tween(btn, { BackgroundColor3 = Theme.Field }, 0.12) end
        end)
        if callback then task.spawn(callback) end
    end)

    return { Instance = row, SetText = function(_, s) lbl.Text = s end }
end

function Section:Toggle(a, ...)
    local o = cfg(a, ...)
    local default, callback
    if o._positional then
        default, callback = o._positional[1], o._positional[2]
    end
    default = (o.Default ~= nil) and o.Default or default or false
    callback = guardCallback(o.Callback or callback)

    local row = self:_row(26)
    local lbl = text(row, o.Text or "Toggle", 14, Theme.Text, Enum.FontWeight.Regular)
    lbl.Size = UDim2.new(1, -56, 1, 0)

    local track = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(46, 22),
        BackgroundColor3 = default and Theme.Accent or Theme.Off,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, row)
    corner(track, 4)

    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = default and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(18, 16),
        BackgroundColor3 = default and Color3.fromRGB(255, 255, 255) or Theme.OffKnob,
        BackgroundTransparency = 0,   -- solid: always clearly visible
        BorderSizePixel = 0,
    }, track)
    corner(knob, 3)

    local state = default
    local api = {}

    local function render(fire)
        tween(track, { BackgroundColor3 = state and Theme.Accent or Theme.Off }, 0.14)
        tween(knob, {
            Position = state and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
            BackgroundColor3 = state and Color3.fromRGB(255, 255, 255) or Theme.OffKnob,
            BackgroundTransparency = 0,
        }, 0.14)
        if fire and callback then task.spawn(callback, state) end
    end

    track.MouseButton1Click:Connect(function()
        state = not state
        render(true)
    end)

    function api:Set(value, silent)
        state = value and true or false
        render(not silent)
    end
    function api:Get() return state end
    api.Instance = row

    self.Window:_register(o.Flag, "toggle", api, o.NoSave)
    if default and callback then task.spawn(callback, true) end
    return api
end

function Section:Slider(a, ...)
    local o = cfg(a, ...)
    local min, max, default, callback, decimals
    if o._positional then
        min, max, default, callback, decimals = table.unpack(o._positional)
    end
    min      = o.Min or min or 0
    max      = o.Max or max or 100
    default  = (o.Default ~= nil) and o.Default or default or min
    decimals = o.Decimals or decimals or 0
    callback = guardCallback(o.Callback or callback)
    local suffix = o.Suffix or ""

    local row = self:_row(Sizes.Slider)
    local track = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Field,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, row)
    corner(track, 4)
    local st = stroke(track, Theme.Border, 1, 0.35)
    table.insert(self.Window.Accented, { st, "Color" })

    local fill = new("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
    }, track)
    corner(fill, 4)
    table.insert(self.Window.Accented, { fill, "BackgroundColor3" })

    local lbl = text(track, "", 13, Theme.Text, Enum.FontWeight.Medium, Enum.TextXAlignment.Right)
    lbl.ZIndex = 3
    padding(lbl, 0, 0, 10, 10)

    local value = math.clamp(default, min, max)
    local hit = new("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,
    }, track)

    local api = {}

    local function render(fire, instant)
        local alpha = (max == min) and 0 or (value - min) / (max - min)
        if instant then
            fill.Size = UDim2.fromScale(alpha, 1)
        else
            tween(fill, { Size = UDim2.fromScale(alpha, 1) }, 0.08)
        end
        if o.MaxLabel and value >= max then
            lbl.Text = string.format("%s: %s", o.Text or "Slider", o.MaxLabel)
        else
            lbl.Text = string.format("%s: %s%s", o.Text or "Slider", tostring(round(value, decimals)), suffix)
        end
        if fire and callback then task.spawn(callback, value) end
    end

    local function setFromX(x)
        local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        local raw = min + (max - min) * alpha
        local newValue = round(raw, decimals)
        if newValue ~= value then
            value = newValue
            render(true, true)
        end
    end

    local win = self.Window
    hit.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        setFromX(input.Position.X)
        win.ActiveDrag = function(position) setFromX(position.X) end
    end)

    function api:Set(v, silent)
        value = math.clamp(round(v, decimals), min, max)
        render(not silent)
    end
    function api:Get() return value end
    api.Instance = row

    self.Window:_register(o.Flag, "slider", api, o.NoSave)
    render(false, true)
    if callback then task.spawn(callback, value) end
    return api
end

function Section:TextBox(a, ...)
    local o = cfg(a, ...)
    local default, placeholder, callback
    if o._positional then
        default, placeholder, callback = table.unpack(o._positional)
    end
    default     = o.Default or default or ""
    placeholder = o.Placeholder or placeholder or ""
    callback = guardCallback(o.Callback or callback)

    if o.Text then self:_fieldLabel(o.Text) end

    local row = self:_row(Sizes.Row)
    local box = new("TextBox", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Field,
        BorderSizePixel = 0,
        Text = tostring(default),
        PlaceholderText = placeholder,
        PlaceholderColor3 = Theme.TextFaint,
        TextColor3 = Theme.Text,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        ClipsDescendants = true,
    }, row)
    applyFont(box, Enum.FontWeight.Regular)
    corner(box, 4)
    padding(box, 0, 0, 10, 10)
    local st = stroke(box, Theme.Border, 1, 0.35)
    table.insert(self.Window.Accented, { st, "Color" })

    box.Focused:Connect(function()
        tween(st, { Transparency = 0 }, 0.12)
        tween(box, { BackgroundColor3 = Theme.FieldHover }, 0.12)
    end)
    box.FocusLost:Connect(function(enter)
        tween(st, { Transparency = 0.35 }, 0.12)
        tween(box, { BackgroundColor3 = Theme.Field }, 0.12)
        if o.Numeric then
            local n = tonumber(box.Text)
            if not n then
                box.Text = tostring(default)
            else
                box.Text = tostring(n)
            end
        end
        if callback then task.spawn(callback, box.Text, enter) end
    end)

    local api = {
        Instance = row,
        Set = function(_, s, silent)
            box.Text = tostring(s)
            if not silent and callback then task.spawn(callback, box.Text, false) end
        end,
        Get = function() return box.Text end,
    }
    self.Window:_register(o.Flag, "textbox", api, o.NoSave)
    return api
end

function Section:Dropdown(a, ...)
    local o = cfg(a, ...)
    local options, default, callback
    if o._positional then
        options, default, callback = table.unpack(o._positional)
    end
    options  = o.Options or options or {}
    default  = (o.Default ~= nil) and o.Default or default
    callback = guardCallback(o.Callback or callback)
    local multi = o.Multi or false

    local win = self.Window

    if o.Text then self:_fieldLabel(o.Text) end

    local row = self:_row(Sizes.Row)
    local box = new("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Field,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
    }, row)
    corner(box, 4)
    local st = stroke(box, Theme.Border, 1, 0.35)
    table.insert(win.Accented, { st, "Color" })

    local valueLabel = text(box, "", 14, Theme.Text, Enum.FontWeight.Regular)
    valueLabel.Size = UDim2.new(1, -34, 1, 0)
    padding(valueLabel, 0, 0, 10, 0)

    -- chevron drawn as an image (monospace fonts have no triangle glyph)
    local chevron = new("ImageLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -9, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        Image = "rbxassetid://6031091004",
        ImageColor3 = Theme.Accent,
    }, box)
    table.insert(win.Accented, { chevron, "ImageColor3" })

    -- state ----------------------------------------------------------
    local selected = {}          -- [option] = true (multi) / single value in selected[1]
    local single = nil

    local function displayText()
        if multi then
            local picked = {}
            for _, opt in ipairs(options) do
                if selected[opt] then table.insert(picked, tostring(opt)) end
            end
            if #picked == 0 then return "None" end
            if #picked == #options then return "All" end
            return table.concat(picked, ", ")
        end
        return single ~= nil and tostring(single) or "..."
    end

    local menu, menuList
    local api = {}
    local ROW_H = 26

    local function menuHeight()
        return math.max(ROW_H * math.min(#options, 7) + 8, ROW_H + 8)
    end

    local function fire()
        valueLabel.Text = displayText()
        if not callback then return end
        if multi then
            local picked = {}
            for _, opt in ipairs(options) do
                if selected[opt] then table.insert(picked, opt) end
            end
            task.spawn(callback, picked)
        else
            task.spawn(callback, single)
        end
    end

    -- menu -----------------------------------------------------------
    local function closeMenu()
        if menu then
            menu:Destroy()
            menu, menuList = nil, nil
        end
        tween(chevron, { Rotation = 0 }, 0.12)
    end

    -- (re)fills the open menu; used on open and by SetOptions so a list that
    -- refreshes (player joined/left) stays open at the same scroll spot
    local function buildItems()
        for _, child in ipairs(menuList:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        for index, opt in ipairs(options) do
            local isOn = multi and selected[opt] or (not multi and single == opt)

            local item = new("TextButton", {
                Size = UDim2.new(1, 0, 0, ROW_H - 2),
                BackgroundColor3 = Theme.AccentDeep,
                BackgroundTransparency = isOn and 0.1 or 1,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = index,
                ZIndex = 62,
            }, menuList)
            corner(item, 3)

            local itemLabel = text(item, tostring(opt), 13,
                isOn and Theme.Accent or Theme.TextDim, Enum.FontWeight.Regular)
            padding(itemLabel, 0, 0, 8, 8)

            item.MouseEnter:Connect(function()
                if not (multi and selected[opt]) and single ~= opt then
                    tween(item, { BackgroundTransparency = 0.5 }, 0.1)
                    tween(itemLabel, { TextColor3 = Theme.Text }, 0.1)
                end
            end)
            item.MouseLeave:Connect(function()
                if not (multi and selected[opt]) and single ~= opt then
                    tween(item, { BackgroundTransparency = 1 }, 0.1)
                    tween(itemLabel, { TextColor3 = Theme.TextDim }, 0.1)
                end
            end)

            item.MouseButton1Click:Connect(function()
                if multi then
                    selected[opt] = not selected[opt] or nil
                    fire()
                    local on = selected[opt] and true or false
                    tween(item, { BackgroundTransparency = on and 0.1 or 1 }, 0.1)
                    tween(itemLabel, { TextColor3 = on and Theme.Accent or Theme.TextDim }, 0.1)
                else
                    single = opt
                    fire()
                    win:CloseMenu()
                end
            end)
        end

    end

    local function openMenu()
        win:CloseMenu()

        local absPos  = box.AbsolutePosition
        local absSize = box.AbsoluteSize
        local rootPos = win.Main.AbsolutePosition
        local scale   = win.Scale.Scale

        local x = (absPos.X - rootPos.X) / scale
        local y = (absPos.Y - rootPos.Y + absSize.Y + 4) / scale
        local width = absSize.X / scale

        local height = menuHeight()

        -- flip upwards if it would leave the window (anchored at the bottom,
        -- so a later height change grows away from the box, not over it)
        local anchor = Vector2.new(0, 0)
        local winH = win.Main.AbsoluteSize.Y / scale
        if y + height > winH - 6 then
            y = (absPos.Y - rootPos.Y) / scale - 4
            anchor = Vector2.new(0, 1)
        end

        menu = new("Frame", {
            Name = "DropdownMenu",
            AnchorPoint = anchor,
            Position = UDim2.fromOffset(math.floor(x), math.floor(y)),
            Size = UDim2.fromOffset(math.floor(width), 0),
            BackgroundColor3 = Theme.BgTop,
            BorderSizePixel = 0,
            ZIndex = 60,
        }, win.Overlay)
        corner(menu, 4)
        stroke(menu, Theme.Accent, 1, 0.25)

        menuList = new("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = Theme.Accent,
            ZIndex = 61,
        }, menu)
        padding(menuList, 4, 4, 4, 4)
        vlist(menuList, 2)

        buildItems()

        win.Overlay.Visible = true
        win.OpenMenu = closeMenu
        tween(menu, { Size = UDim2.fromOffset(math.floor(width), height) }, 0.14)
        tween(chevron, { Rotation = 180 }, 0.14)
    end

    box.MouseEnter:Connect(function()
        tween(box, { BackgroundColor3 = Theme.FieldHover }, 0.12)
    end)
    box.MouseLeave:Connect(function()
        tween(box, { BackgroundColor3 = Theme.Field }, 0.12)
    end)
    box.MouseButton1Click:Connect(function()
        if menu then win:CloseMenu() else openMenu() end
    end)

    -- defaults -------------------------------------------------------
    if multi then
        if default == "All" or default == true then
            for _, opt in ipairs(options) do selected[opt] = true end
        elseif type(default) == "table" then
            for _, opt in ipairs(default) do selected[opt] = true end
        elseif default ~= nil then
            selected[default] = true
        end
    else
        single = default
    end
    valueLabel.Text = displayText()

    function api:Set(value, silent)
        if multi then
            selected = {}
            if value == "All" then
                for _, opt in ipairs(options) do selected[opt] = true end
            elseif type(value) == "table" then
                for _, opt in ipairs(value) do selected[opt] = true end
            elseif value ~= nil then
                selected[value] = true
            end
        else
            single = value
        end
        if silent then
            valueLabel.Text = displayText()
        else
            fire()
        end
    end

    function api:Get()
        if not multi then return single end
        local picked = {}
        for _, opt in ipairs(options) do
            if selected[opt] then table.insert(picked, opt) end
        end
        return picked
    end

    function api:SetOptions(newOptions)
        newOptions = newOptions or {}
        local same = #newOptions == #options
        if same then
            for i, opt in ipairs(newOptions) do
                if options[i] ~= opt then same = false break end
            end
        end
        options = newOptions
        if menu and not same then
            local scroll = menuList.CanvasPosition
            buildItems()
            tween(menu, { Size = UDim2.fromOffset(menu.Size.X.Offset, menuHeight()) }, 0.1)
            task.defer(function()   -- canvas size updates after layout
                if menuList then menuList.CanvasPosition = scroll end
            end)
        end
        if not multi and single ~= nil then
            local found = false
            for _, opt in ipairs(options) do
                if opt == single then found = true break end
            end
            if not found then single = nil end
        end
        valueLabel.Text = displayText()
    end

    api.Instance = row
    self.Window:_register(o.Flag, "dropdown", api, o.NoSave)
    return api
end

----------------------------------------------------------------------
-- keybinds  (keyboard keys, MB2 and MB3; Backspace clears, Escape cancels)
----------------------------------------------------------------------

local function bindName(bind)
    if not bind then return "NONE" end
    if bind.EnumType == Enum.UserInputType then
        local short = { MouseButton1 = "MB1", MouseButton2 = "MB2", MouseButton3 = "MB3" }
        return short[bind.Name] or bind.Name
    end
    return bind.Name
end

local function bindMatches(input, bind)
    if not bind then return false end
    if bind.EnumType == Enum.KeyCode then return input.KeyCode == bind end
    return input.UserInputType == bind
end

local function bindIsDown(bind)
    if not bind then return false end
    if UserInputService:GetFocusedTextBox() then return false end   -- never fire while typing (chat, config name, ...)
    if bind.EnumType == Enum.KeyCode then return UserInputService:IsKeyDown(bind) end
    return UserInputService:IsMouseButtonPressed(bind)
end

function Section:Keybind(a, ...)
    local o = cfg(a, ...)
    local default, callback
    if o._positional then default, callback = o._positional[1], o._positional[2] end
    default  = o.Default or default
    callback = guardCallback(o.Callback or callback)
    local onChanged = guardCallback(o.OnChanged)
    local win = self.Window

    local row = self:_row(26)
    local lbl = text(row, o.Text or "Keybind", 14, Theme.Text, Enum.FontWeight.Regular)
    lbl.Size = UDim2.new(1, -96, 1, 0)

    local btn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(88, 24),
        BackgroundColor3 = Theme.Field,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, row)
    stroke(btn, Theme.Border, 1, 0.35)

    local keyLabel = text(btn, bindName(default), 12, Theme.Accent,
        Enum.FontWeight.Medium, Enum.TextXAlignment.Center)

    local current, listening = default, false
    local api = {}

    local function setBind(bind, fire)
        current = bind
        keyLabel.Text = bindName(bind)
        if fire and onChanged then task.spawn(onChanged, bind) end
    end

    btn.MouseButton1Click:Connect(function()
        if listening then return end
        listening = true
        keyLabel.Text = "..."
    end)

    table.insert(win.Conns, UserInputService.InputBegan:Connect(function(input, gp)
        if listening then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                listening = false
                if input.KeyCode == Enum.KeyCode.Escape then
                    setBind(current, false)
                elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
                    setBind(nil, true)
                else
                    setBind(input.KeyCode, true)
                end
            elseif input.UserInputType == Enum.UserInputType.MouseButton2
                or input.UserInputType == Enum.UserInputType.MouseButton3 then
                listening = false
                setBind(input.UserInputType, true)
            end
            return
        end
        -- hotkeys must still fire when the GAME sinks the key (gp = true for its own binds);
        -- only ignore them while the user is typing in a textbox (chat, config name, ...)
        if not current or UserInputService:GetFocusedTextBox() then return end
        if bindMatches(input, current) and callback then
            task.spawn(callback, current)
        end
    end))

    function api:Get() return current end
    function api:Set(key, silent) setBind(key, not silent) end
    function api:IsDown() return bindIsDown(current) end
    api.Instance = row

    win:_register(o.Flag, "keybind", api, o.NoSave)
    return api
end

----------------------------------------------------------------------
-- colour picker  (saturation/value square, hue bar, hex box)
----------------------------------------------------------------------

function Section:ColorPicker(a, ...)
    local o = cfg(a, ...)
    local default, callback
    if o._positional then default, callback = o._positional[1], o._positional[2] end
    default  = o.Default or default or Color3.fromRGB(255, 255, 255)
    callback = guardCallback(o.Callback or callback)
    local win = self.Window

    local row = self:_row(26)
    local lbl = text(row, o.Text or "Color", 14, Theme.Text, Enum.FontWeight.Regular)
    lbl.Size = UDim2.new(1, -56, 1, 0)

    local swatch = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(46, 22),
        BackgroundColor3 = default,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, row)
    swatch:SetAttribute("TerkanNoTheme", true)
    stroke(swatch, Theme.Border, 1, 0.15)

    local color = default
    local h, s, v = color:ToHSV()
    local menu, refreshPanel
    local api = {}

    local function commit(fire)
        color = Color3.fromHSV(h, s, v)
        swatch.BackgroundColor3 = color
        if refreshPanel then refreshPanel() end
        if fire and callback then task.spawn(callback, color) end
    end

    local function closeMenu()
        if menu then menu:Destroy() menu = nil end
        refreshPanel = nil
    end

    local function openMenu()
        win:CloseMenu()

        local W, H = 214, 180
        local absPos, absSize = swatch.AbsolutePosition, swatch.AbsoluteSize
        local rootPos = win.Main.AbsolutePosition
        local scale = win.Scale.Scale

        local x = (absPos.X - rootPos.X + absSize.X) / scale - W
        local y = (absPos.Y - rootPos.Y + absSize.Y + 4) / scale
        local winH = win.Main.AbsoluteSize.Y / scale
        if y + H > winH - 6 then y = (absPos.Y - rootPos.Y) / scale - H - 4 end
        x = math.max(6, x)

        menu = new("Frame", {
            Name = "ColorMenu",
            Position = UDim2.fromOffset(math.floor(x), math.floor(y)),
            Size = UDim2.fromOffset(W, H),
            BackgroundColor3 = Theme.BgTop,
            BorderSizePixel = 0,
            ZIndex = 60,
        }, win.Overlay)
        stroke(menu, Theme.Accent, 1, 0.25)

        -- saturation (left to right) / value (top to bottom) square
        local sv = new("TextButton", {
            Position = UDim2.fromOffset(8, 8),
            Size = UDim2.fromOffset(W - 16, 112),
            BackgroundColor3 = Color3.fromHSV(h, 1, 1),
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 62,
        }, menu)
        sv:SetAttribute("TerkanNoTheme", true)

        local white = new("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 63,
        }, sv)
        new("UIGradient", { Transparency = NumberSequence.new(0, 1) }, white)

        local black = new("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BorderSizePixel = 0,
            ZIndex = 64,
        }, sv)
        new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }, black)

        local svMarker = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(10, 10),
            BackgroundTransparency = 1,
            ZIndex = 66,
        }, sv)
        svMarker:SetAttribute("TerkanNoTheme", true)
        new("UICorner", { CornerRadius = UDim.new(1, 0) }, svMarker)
        new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, svMarker)

        -- hue bar
        local hueBar = new("TextButton", {
            Position = UDim2.fromOffset(8, 128),
            Size = UDim2.fromOffset(W - 16, 14),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 62,
        }, menu)
        hueBar:SetAttribute("TerkanNoTheme", true)
        local keys = {}
        for i = 0, 6 do
            table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i % 6) / 6 + (i == 6 and 0 or 0), 1, 1)))
        end
        keys[7] = ColorSequenceKeypoint.new(1, Color3.fromHSV(0, 1, 1))
        new("UIGradient", { Color = ColorSequence.new(keys) }, hueBar)

        local hueMarker = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(4, 18),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 66,
        }, hueBar)
        hueMarker:SetAttribute("TerkanNoTheme", true)

        -- hex box
        local hex = new("TextBox", {
            Position = UDim2.fromOffset(8, 150),
            Size = UDim2.fromOffset(W - 16, 22),
            BackgroundColor3 = Theme.Field,
            BorderSizePixel = 0,
            Text = "",
            TextColor3 = Theme.Text,
            TextSize = 13,
            ClearTextOnFocus = false,
            ZIndex = 62,
        }, menu)
        applyFont(hex, Enum.FontWeight.Regular)
        stroke(hex, Theme.Border, 1, 0.35)

        refreshPanel = function()
            sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
            svMarker.Position = UDim2.fromScale(s, 1 - v)
            hueMarker.Position = UDim2.new(h, 0, 0.5, 0)
            if not hex:IsFocused() then hex.Text = "#" .. color:ToHex():upper() end
        end

        local function fromSV(pos)
            s = math.clamp((pos.X - sv.AbsolutePosition.X) / math.max(sv.AbsoluteSize.X, 1), 0, 1)
            v = 1 - math.clamp((pos.Y - sv.AbsolutePosition.Y) / math.max(sv.AbsoluteSize.Y, 1), 0, 1)
            commit(true)
        end
        local function fromHue(pos)
            h = math.clamp((pos.X - hueBar.AbsolutePosition.X) / math.max(hueBar.AbsoluteSize.X, 1), 0, 0.999)
            commit(true)
        end

        local function pressed(input)
            return input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
        end
        sv.InputBegan:Connect(function(input)
            if not pressed(input) then return end
            fromSV(input.Position)
            win.ActiveDrag = fromSV
        end)
        hueBar.InputBegan:Connect(function(input)
            if not pressed(input) then return end
            fromHue(input.Position)
            win.ActiveDrag = fromHue
        end)
        hex.FocusLost:Connect(function()
            local ok, c = pcall(Color3.fromHex, (hex.Text:gsub("#", "")))
            if ok and c then
                h, s, v = c:ToHSV()
                commit(true)
            end
            refreshPanel()
        end)

        refreshPanel()
        win.Overlay.Visible = true
        win.OpenMenu = closeMenu
    end

    swatch.MouseButton1Click:Connect(function()
        if menu then win:CloseMenu() else openMenu() end
    end)

    function api:Get() return color end
    function api:Set(c, silent)
        if typeof(c) ~= "Color3" then return end
        h, s, v = c:ToHSV()
        commit(not silent)
    end
    function api:Open() if not menu then openMenu() end end
    function api:Close() if menu then win:CloseMenu() end end
    api.Instance = row

    win:_register(o.Flag, "color", api, o.NoSave)
    if callback then task.spawn(callback, color) end
    return api
end

----------------------------------------------------------------------
-- notifications
----------------------------------------------------------------------

local NOTIFY_PLACES = {
    ["Top Left"]     = { Vector2.new(0, 0), UDim2.new(0, 14, 0, 14),   Enum.VerticalAlignment.Top,    Enum.HorizontalAlignment.Left },
    ["Top Right"]    = { Vector2.new(1, 0), UDim2.new(1, -14, 0, 14),  Enum.VerticalAlignment.Top,    Enum.HorizontalAlignment.Right },
    ["Bottom Left"]  = { Vector2.new(0, 1), UDim2.new(0, 14, 1, -14),  Enum.VerticalAlignment.Bottom, Enum.HorizontalAlignment.Left },
    ["Bottom Right"] = { Vector2.new(1, 1), UDim2.new(1, -14, 1, -14), Enum.VerticalAlignment.Bottom, Enum.HorizontalAlignment.Right },
}
local NotifyPlaceNames = { "Top Left", "Top Right", "Bottom Left", "Bottom Right" }

local NOTIFY_KINDS = {
    success = Color3.fromRGB(64, 214, 120),
    warn    = Color3.fromRGB(255, 176, 46),
    error   = Color3.fromRGB(255, 72, 72),
}

function Window:SetNotifications(settings)
    for k, v in pairs(settings or {}) do self.Notifications[k] = v end
    if self.NotifyHolder and self.NotifyPlace ~= self.Notifications.Position then
        self.NotifyHolder:Destroy()
        self.NotifyHolder = nil
    end
end

function Window:GetNotifyPlaces() return NotifyPlaceNames end

function Window:Notify(options)
    options = type(options) == "table" and options or { Title = options }
    local n = self.Notifications
    if n.Enabled == false and not options.Force then return end

    local duration = options.Duration or n.Duration
    local accent = options.Color or NOTIFY_KINDS[options.Kind or ""]
        or (n.UseThemeColor and Theme.Accent or n.Color)

    if not self.NotifyHolder then
        local place = NOTIFY_PLACES[n.Position] or NOTIFY_PLACES["Bottom Right"]
        local holder = new("Frame", {
            Name = "Notifications",
            AnchorPoint = place[1],
            Position = place[2],
            Size = UDim2.fromOffset(290, 500),
            BackgroundTransparency = 1,
        }, self.Gui)
        new("UIListLayout", {
            VerticalAlignment = place[3],
            HorizontalAlignment = place[4],
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 8),
        }, holder)
        self.NotifyHolder = holder
        self.NotifyPlace = n.Position
        self.NotifyCounter = 0
    end

    -- keep the stack short: drop the oldest cards
    local cards = {}
    for _, child in ipairs(self.NotifyHolder:GetChildren()) do
        if child:IsA("Frame") then table.insert(cards, child) end
    end
    table.sort(cards, function(x, y) return x.LayoutOrder < y.LayoutOrder end)
    while #cards >= (n.Max or 5) do
        table.remove(cards, 1):Destroy()
    end

    self.NotifyCounter += 1
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.BgTop,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = self.NotifyCounter,
    }, self.NotifyHolder)
    card:SetAttribute("TerkanNoTheme", true)
    local st = stroke(card, accent, 1, 1)
    padding(card, 9, 9, 12, 12)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }, card)

    local title = text(card, options.Title or "Terkan", 14, accent, Enum.FontWeight.Bold)
    title.Size = UDim2.new(1, 0, 0, 18)
    title.LayoutOrder = 1
    title.TextTransparency = 1

    local body
    if options.Text and options.Text ~= "" then
        body = text(card, options.Text, 13, Theme.TextDim, Enum.FontWeight.Regular)
        body.Size = UDim2.new(1, 0, 0, 0)
        body.AutomaticSize = Enum.AutomaticSize.Y
        body.TextWrapped = true
        body.TextYAlignment = Enum.TextYAlignment.Top
        body.LayoutOrder = 2
        body.TextTransparency = 1
    end

    tween(card, { BackgroundTransparency = 0 }, 0.2)
    tween(st, { Transparency = 0.2 }, 0.2)
    tween(title, { TextTransparency = 0 }, 0.2)
    if body then tween(body, { TextTransparency = 0 }, 0.2) end

    task.delay(duration, function()
        if not card.Parent then return end
        tween(card, { BackgroundTransparency = 1 }, 0.25)
        tween(st, { Transparency = 1 }, 0.25)
        tween(title, { TextTransparency = 1 }, 0.25)
        if body then tween(body, { TextTransparency = 1 }, 0.25) end
        task.delay(0.3, function() if card.Parent then card:Destroy() end end)
    end)
end

TerkanUI.Theme = Theme
TerkanUI.Themes = Themes
TerkanUI.ThemeNames = ThemeNames
TerkanUI.NotifyPlaces = NotifyPlaceNames
TerkanUI.Sizes = Sizes

return TerkanUI
