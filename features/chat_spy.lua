--[[
    Chat Spy  -  chat_spy.lua
    A draggable window with every chat message your client receives.

    Runs on its own: opens a small menu with just this feature. It is the same code as in the Terkan Universal hub
    (https://github.com/tygovansteenpaalwork-gif/Roblox_lua_script), cut out by tools/build_features.py - do not edit by hand, change src/ and run tools/build.py.

    Run it:   loadstring(game:HttpGet("https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/features/chat_spy.lua"))()
--]]

local BASE = "https://raw.githubusercontent.com/tygovansteenpaalwork-gif/Roblox_lua_script/main/"
local Core = getgenv().TerkanCore or loadstring(game:HttpGet(BASE .. "features/_core.lua"))()
local ctx = Core({ Name = "chat_spy", Title = "Chat Spy" })

local C, Players, Ready, RunService, U, UserInputService = ctx.C, ctx.Players, ctx.Ready, ctx.RunService, ctx.U, ctx.UserInputService
local connect, hasFn, lp, notify, onUnload, parentGui = ctx.connect, ctx.hasFn, ctx.lp, ctx.notify, ctx.onUnload, ctx.parentGui
local slider, toggle, win = ctx.slider, ctx.toggle, ctx.win

local miscTab = win:Tab("Chat Spy")

-- chat spy ------------------------------------------------------------------------------------
-- Logs every chat message this client receives, tagged public / whisper / team, in its own window.
-- It can only show what the server actually sends to you: with the newer TextChatService, whispers
-- between other people are never delivered to your client, so they cannot be seen by any script.

local chatSec = miscTab:Section("Chat Spy")
local chatOpt = miscTab:Section("Chat Spy Options", "right")

local TextChatService = game:GetService("TextChatService")
local chatLog, chatLabels, recentChat = {}, {}, {}
local chatGui, chatFrame, chatList, chatPos
local chatDrag   -- { start = Vector3, from = UDim2 } while the title bar is held

-- The window borrows its look from the menu (sharp corners, 2px accent border, top bar with a divider,
-- RobotoMono). Its colours are read from the live menu a couple of times a second, so switching the
-- theme in Settings switches this window too.
local TEXT_COLOR, FAINT_HEX = Color3.fromRGB(232, 226, 227), "#685a5e"
local TEAM_COLOR = Color3.fromRGB(110, 220, 140)
local chatColors = {
    Accent = Color3.fromRGB(255, 32, 48), Bg = Color3.fromRGB(11, 4, 6),
    BgTop = Color3.fromRGB(19, 5, 8), Border = Color3.fromRGB(96, 14, 24),
}
local chatStroke, chatTop, chatTitle, chatLine   -- window parts that follow the theme
local KIND_TAG = { public = "", private = "[PM] ", team = "[TEAM] " }

local function monoFont(inst, weight)
    local ok = pcall(function()
        inst.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", weight or Enum.FontWeight.Regular)
    end)
    if not ok then inst.Font = Enum.Font.Code end
end

local function readMenuColors()
    local main = win.Main
    if not main then return end
    chatColors.Bg = main.BackgroundColor3
    local s = main:FindFirstChildOfClass("UIStroke")
    if s then chatColors.Accent = s.Color end
    local top = main:FindFirstChild("TopBar")
    if top then
        chatColors.BgTop = top.BackgroundColor3
        for _, child in ipairs(top:GetChildren()) do
            if child:IsA("Frame") and child.Size.Y.Offset == 1 then chatColors.Border = child.BackgroundColor3 end
        end
    end
end

local function kindColor(kind)
    if kind == "private" then return chatColors.Accent end
    if kind == "team" then return TEAM_COLOR end
    return TEXT_COLOR
end

local function applyChatTheme()
    if not chatFrame then return end
    readMenuColors()
    chatFrame.BackgroundColor3 = chatColors.Bg
    chatStroke.Color = chatColors.Accent
    chatTop.BackgroundColor3 = chatColors.BgTop
    chatTitle.TextColor3 = chatColors.Accent
    chatLine.BackgroundColor3 = chatColors.Border
    chatList.ScrollBarImageColor3 = chatColors.Accent
    for _, label in ipairs(chatLabels) do label.TextColor3 = kindColor(label:GetAttribute("Kind")) end
end

local function esc(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function addChatLine(entry)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, -8, 0, 0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.RichText = true
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    monoFont(label)
    label.TextSize = C.ChatSize
    label:SetAttribute("Kind", entry.kind)
    label.TextColor3 = kindColor(entry.kind)
    label.Text = ("<font color=\"%s\">%s</font> %s<b>%s</b>: %s"):format(FAINT_HEX, entry.t, KIND_TAG[entry.kind] or "", esc(entry.name), esc(entry.text))
    label.Parent = chatList
    table.insert(chatLabels, label)
    while #chatLabels > C.ChatMax do table.remove(chatLabels, 1):Destroy() end
    task.defer(function()
        if chatList then chatList.CanvasPosition = Vector2.new(0, chatList.AbsoluteCanvasSize.Y) end
    end)
end

local function destroyChat()
    if chatFrame then chatPos = chatFrame.Position end
    if chatGui then chatGui:Destroy() end
    chatGui, chatFrame, chatList = nil, nil, nil
    chatStroke, chatTop, chatTitle, chatLine = nil, nil, nil, nil
    table.clear(chatLabels)
end
onUnload(destroyChat)

local function buildChat()
    readMenuColors()
    chatGui = Instance.new("ScreenGui")
    chatGui.Name = U.rname()
    chatGui.ResetOnSpawn = false
    chatGui.IgnoreGuiInset = true
    chatGui.DisplayOrder = 99
    chatGui.Parent = parentGui()

    chatFrame = Instance.new("Frame")
    chatFrame.BackgroundColor3 = chatColors.Bg
    chatFrame.BorderSizePixel = 0
    chatFrame.Size = UDim2.fromOffset(C.ChatW, C.ChatH)
    chatFrame.Position = chatPos or UDim2.new(0, 12, 1, -(C.ChatH + 12))
    chatFrame.Parent = chatGui
    chatStroke = Instance.new("UIStroke")
    chatStroke.Color = chatColors.Accent
    chatStroke.Thickness = 2
    chatStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    chatStroke.Parent = chatFrame

    chatTop = Instance.new("Frame")
    chatTop.BackgroundColor3 = chatColors.BgTop
    chatTop.BorderSizePixel = 0
    chatTop.Size = UDim2.new(1, 0, 0, 32)
    chatTop.Active = true
    chatTop.Parent = chatFrame
    chatTop.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            chatDrag = { start = input.Position, from = chatFrame.Position }
        end
    end)

    chatTitle = Instance.new("TextLabel")
    chatTitle.BackgroundTransparency = 1
    chatTitle.Position = UDim2.new(0, 12, 0, 0)
    chatTitle.Size = UDim2.new(0.5, 0, 1, 0)
    chatTitle.Text = "CHAT SPY"
    chatTitle.TextSize = 15
    chatTitle.TextColor3 = chatColors.Accent
    chatTitle.TextXAlignment = Enum.TextXAlignment.Left
    monoFont(chatTitle, Enum.FontWeight.Bold)
    chatTitle.Parent = chatTop

    local hint = Instance.new("TextLabel")
    hint.BackgroundTransparency = 1
    hint.AnchorPoint = Vector2.new(1, 0)
    hint.Position = UDim2.new(1, -12, 0, 0)
    hint.Size = UDim2.new(0.5, 0, 1, 0)
    hint.Text = "drag to move"
    hint.TextSize = 11
    hint.TextColor3 = Color3.fromRGB(104, 90, 94)
    hint.TextXAlignment = Enum.TextXAlignment.Right
    monoFont(hint)
    hint.Parent = chatTop

    chatLine = Instance.new("Frame")   -- divider under the top bar, like the menu's
    chatLine.BackgroundColor3 = chatColors.Border
    chatLine.BackgroundTransparency = 0.35
    chatLine.BorderSizePixel = 0
    chatLine.Position = UDim2.new(0, 0, 1, -1)
    chatLine.Size = UDim2.new(1, 0, 0, 1)
    chatLine.Parent = chatTop

    chatList = Instance.new("ScrollingFrame")
    chatList.BackgroundTransparency = 1
    chatList.BorderSizePixel = 0
    chatList.Position = UDim2.new(0, 8, 0, 38)
    chatList.Size = UDim2.new(1, -16, 1, -46)
    chatList.CanvasSize = UDim2.new()
    chatList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    chatList.ScrollBarThickness = 3
    chatList.ScrollBarImageColor3 = chatColors.Accent
    chatList.Parent = chatFrame
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 3)
    layout.Parent = chatList

    for _, entry in ipairs(chatLog) do addChatLine(entry) end
end

local chatThemeAt = 0
connect(RunService.Heartbeat, function(dt)
    if not chatFrame then return end
    chatThemeAt += dt
    if chatThemeAt < 0.4 then return end
    chatThemeAt = 0
    applyChatTheme()
end)

connect(UserInputService.InputChanged, function(input)
    if chatDrag and chatFrame and input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - chatDrag.start
        chatFrame.Position = UDim2.new(chatDrag.from.X.Scale, chatDrag.from.X.Offset + d.X,
            chatDrag.from.Y.Scale, chatDrag.from.Y.Offset + d.Y)
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then chatDrag = nil end
end)

local function logChat(kind, name, text)
    if not (C.ChatSpy and U.Running) then return end
    if C.ChatPrivateOnly and kind == "public" then return end
    -- the same message can arrive through more than one route
    local key, now = name .. "\0" .. text, os.clock()
    if recentChat[key] and now - recentChat[key] < 1 then return end
    if next(recentChat) and math.random() < 0.05 then
        for k, t in pairs(recentChat) do if now - t > 5 then recentChat[k] = nil end end
    end
    recentChat[key] = now

    local entry = { t = os.date("%H:%M:%S"), kind = kind, name = name, text = text }
    table.insert(chatLog, entry)
    while #chatLog > C.ChatMax do table.remove(chatLog, 1) end
    if chatList then addChatLine(entry) end
    if kind ~= "public" and C.ChatNotify then notify("Chat Spy", name .. ": " .. text) end
end

toggle(chatSec, "Chat Spy", "ChatSpy", false, function(v)
    if v then buildChat() else destroyChat() end
end)
toggle(chatSec, "Only Whispers & Team", "ChatPrivateOnly", false)
toggle(chatSec, "Notify On Whispers & Team", "ChatNotify", true)
chatSec:Button({ Text = "Copy Log", Callback = function()
    if not hasFn("setclipboard") then notify("Chat Spy", "Your executor cannot copy to the clipboard", "warn") return end
    local lines = {}
    for _, e in ipairs(chatLog) do
        table.insert(lines, ("[%s] [%s] %s: %s"):format(e.t, e.kind, e.name, e.text))
    end
    setclipboard(table.concat(lines, "\n"))
    notify("Chat Spy", #lines .. " lines copied", "success")
end })
chatSec:Button({ Text = "Clear Log", Callback = function()
    table.clear(chatLog)
    for _, l in ipairs(chatLabels) do l:Destroy() end
    table.clear(chatLabels)
end })
slider(chatOpt, "Lines Kept", "ChatMax", 20, 300, 80)
slider(chatOpt, "Text Size", "ChatSize", 10, 22, 14)
slider(chatOpt, "Window Width", "ChatW", 240, 800, 380, { OnChange = function(v)
    if chatFrame then chatFrame.Size = UDim2.fromOffset(v, C.ChatH) end
end })
slider(chatOpt, "Window Height", "ChatH", 100, 600, 220, { OnChange = function(v)
    if chatFrame then chatFrame.Size = UDim2.fromOffset(C.ChatW, v) end
end })

-- classic chat: Player.Chatted carries the raw text, so whispers and team chat can be recognised
-- by their command prefix. New chat: TextChatService knows which channel a message came from.
local newChat = false
pcall(function() newChat = TextChatService.ChatVersion == Enum.ChatVersion.TextChatService end)

if not newChat then
    local function hookPlayer(plr)
        if plr == lp then return end
        connect(plr.Chatted, function(msg)
            local low = msg:lower()
            local kind = "public"
            if low:match("^/w ") or low:match("^/whisper ") or low:match("^/msg ") then kind = "private"
            elseif low:match("^/t ") or low:match("^/team ") then kind = "team" end
            logChat(kind, plr.Name, msg)
        end)
    end
    for _, plr in ipairs(Players:GetPlayers()) do hookPlayer(plr) end
    connect(Players.PlayerAdded, hookPlayer)
end
pcall(function()
    connect(TextChatService.MessageReceived, function(message)
        local source = message.TextSource
        local plr = source and Players:GetPlayerByUserId(source.UserId)
        if not plr or plr == lp then return end
        local channel = message.TextChannel and message.TextChannel.Name or ""
        local kind = "public"
        if channel:find("Whisper") then kind = "private" elseif channel:find("Team") then kind = "team" end
        logChat(kind, plr.Name, message.Text)
    end)
end)

Ready()
