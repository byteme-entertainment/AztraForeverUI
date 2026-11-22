-- Chat quality of life on Blizzard's chat windows (round 24): the always visible edit box strip, clickable links with a copy box, a
-- Copy Chat window, grey timestamps in the client's formats. Hooks and the official filter API only: no Blizzard function is replaced,
-- nothing here is protected. Settings (AFUI.GetSetting / SetSetting): chatTimestamps ('none'), chatFade (true), chatCopyLinks (true), chatStrip (true).
local C = {}
AFUI.ChatQoL = C

C.DEFAULTS = { chatTimestamps = "none", chatFade = true, chatCopyLinks = true, chatStrip = true, chatKeepHistory = true, chatGuildInWindow = false }
C.HISTORY_LINES = 150 -- saved lines per window
C.HISTORY_CHARS = 500 -- saved characters per line
C.COPY_LINES = 250 -- lines the Copy Chat window shows
C.BUFFER = 500     -- lines kept per window when the client cannot list its own (GetMessageInfo)

---------------------------------------------------------------- settings (the minimal API, only until the Settings module brings its own)
if not AFUI.GetSetting then
  local function store(create)
    local db = AztraForeverUIDB
    if type(db) ~= "table" then if not create then return end; db = {}; AztraForeverUIDB = db end
    if type(db.settings) ~= "table" then if not create then return end; db.settings = {} end
    return db.settings
  end
  function AFUI.GetSetting(key, default)
    local s = store(false)
    local v = s and s[key]
    if v == nil then return default end
    return v
  end
  function AFUI.SetSetting(key, value) store(true)[key] = value end
end

function C.Get(key) return AFUI.GetSetting(key, C.DEFAULTS[key]) end

---------------------------------------------------------------- links
local URL_COLOR = "|cff5ea0ff" -- Forever's hyperlink blue (video notes: chat)
C.TYPE = "afuiurl"

-- The link at the start of one whitespace-free token, and what follows it ("http://a.b/c)." -> the url, ").").
-- Plain Lua patterns (no regex in 5.1): http(s)://..., www.x.y, discord.gg/code.
function C.UrlIn(token)
  if token:find("|", 1, true) then return end -- escapes (colours, other links) are never ours to touch
  local body = token:match("^https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+")
    or token:match("^www%.[%w%-]+%.[%w%-%.]*%w[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]*")
    or token:match("^discord%.gg/[%w%-_]+")
    or token:match("^discord%.com/invite/[%w%-_]+")
  if not body then return end
  local tail = ""
  while true do -- sentence punctuation and a closing bracket without an opener belong to the text, not the link
    local last = body:sub(-1)
    if last:find("^[%.,;:!%?'\"]$") or (last == ")" and not body:find("(", 1, true)) or (last == "]" and not body:find("[", 1, true)) then
      tail = last .. tail; body = body:sub(1, -2)
    else break end
  end
  if #body < 5 then return end
  return body, tail .. token:sub(#body + #tail + 1)
end

local function linkOf(url) return URL_COLOR .. "|H" .. C.TYPE .. ":" .. url .. "|h[" .. url .. "]|h|r" end

-- Turns every url in `text` into a hyperlink; existing hyperlinks (|H...|h...|h) stay as they are.
function C.Linkify(text)
  if type(text) ~= "string" or text == "" then return text end
  local out, pos = {}, 1
  while true do
    local a, b = text:find("|H.-|h.-|h", pos)
    local plainPart = text:sub(pos, (a or #text + 1) - 1)
    out[#out + 1] = (plainPart:gsub("%S+", function(token)
      local url, rest = C.UrlIn(token)
      if url then return linkOf(url) .. rest end
    end))
    if not a then break end
    out[#out + 1] = text:sub(a, b)
    pos = b + 1
  end
  return table.concat(out)
end

C.EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
  "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_BATTLEGROUND", "CHAT_MSG_BATTLEGROUND_LEADER", "CHAT_MSG_WHISPER",
  "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" }

-- ChatFrame_AddMessageEventFilter: returns (false, newMessage, rest...) like the official filters do.
function C.Filter(_, _, msg, ...)
  if C.Get("chatCopyLinks") == false then return false, msg, ... end
  return false, C.Linkify(msg), ...
end

---------------------------------------------------------------- the copy box (url) and the Copy Chat window
local function widgets() return AFUI.EditModeWidgets end

local function textFont() return (_G.ChatFontNormal and ChatFontNormal.GetFont and ChatFontNormal:GetFont()) or "Fonts\\ARIALN.TTF" end

local function title(f, text)
  local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOP", f, "TOP", 0, -14); t:SetText(text)
  return t
end

-- A small window with the url selected: Ctrl+C copies it (WoW cannot open a browser), Esc / Enter closes.
function C.CopyBox()
  if C.box then return C.box end
  local W = widgets()
  if not W then return end
  local f = W.Panel("AFUI_ChatCopyBox", 440, 96, true)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  f.title = title(f, "Copy link")
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 14); hint:SetText("Press Ctrl+C to copy, then Esc"); hint:SetTextColor(0.6, 0.6, 0.6)
  f.hint = hint
  local eb = CreateFrame("EditBox", "AFUI_ChatCopyBoxEdit", f)
  eb:SetAutoFocus(false); eb:SetFont(textFont(), 14, ""); eb:SetTextInsets(8, 8, 0, 0)
  eb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -38); eb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -38); eb:SetHeight(24)
  eb:SetMaxLetters(0)
  local back = eb:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(back, 0, 0, 0, 0.6); back:SetAllPoints(eb)
  eb:SetScript("OnEscapePressed", function() f:Hide() end)
  eb:SetScript("OnEnterPressed", function() f:Hide() end)
  eb:SetScript("OnTextChanged", function(self, user) -- read only in effect: what the player typed is put back
    if user and f.url and self:GetText() ~= f.url then self:SetText(f.url); self:HighlightText() end
  end)
  f.edit = eb
  f.close = W.CloseButton(f, function() f:Hide() end)
  f:SetScript("OnShow", function() eb:SetFocus(); eb:HighlightText() end)
  if _G.UISpecialFrames then table.insert(UISpecialFrames, "AFUI_ChatCopyBox") end
  C.box = f
  return f
end

-- titleText / hintText (optional) replace the box's default "Copy link" / "Press Ctrl+C to copy, then Esc" (the About page's links).
function C.OpenUrl(url, titleText, hintText)
  local f = C.CopyBox()
  if not f or not url or url == "" then return end
  f.title:SetText(titleText or "Copy link")
  f.hint:SetText(hintText or "Press Ctrl+C to copy, then Esc")
  f.url = url
  f.edit:SetText(url)
  if f:IsShown() then f.edit:SetFocus(); f.edit:HighlightText() else f:Show() end
  return f
end

-- Lines of one chat window as plain text: the client's own list when it has one (GetNumMessages / GetMessageInfo), else our buffer.
local function plain(s)
  s = tostring(s or "")
  s = s:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return s
end
C.Plain = plain

C.buffers = {}
function C.Lines(chat, n)
  n = n or C.COPY_LINES
  local raw
  local count = chat.GetNumMessages and chat:GetNumMessages()
  if type(count) == "number" and chat.GetMessageInfo then
    raw = {}
    for i = math.max(1, count - n + 1), count do raw[#raw + 1] = (chat:GetMessageInfo(i)) end
  else
    raw = C.buffers[chat:GetName()] or {}
  end
  local out = {}
  for i = math.max(1, #raw - n + 1), #raw do out[#out + 1] = plain(raw[i]) end
  return out
end

---------------------------------------------------------------- history that survives /reload and the client (AztraForeverUICharDB.chatLog)
-- Every line a window gets is copied into chatLog[windowName] (text + colour + line id, newest last) by the AddMessage hook, so the saved data is complete
-- whenever the game writes it. At login the lines are put back into their windows (flag C.replaying: a replayed line is never stored a second time).
-- The Combat Log window is skipped. Lines the guild filter hides never reach AddMessage, so they are never saved either.
local function isCombatLog(chat)
  if chat == _G.COMBATLOG then return true end
  local tab = _G[chat:GetName() .. "Tab"]
  local label = tab and tab.GetText and tab:GetText()
  if label and _G.COMBAT_LOG and label == _G.COMBAT_LOG then return true end
  return _G.COMBATLOG == nil and chat:GetName() == "ChatFrame2"
end

local function logTable(create)
  local db = _G.AztraForeverUICharDB
  if type(db) ~= "table" then return end
  if type(db.chatLog) ~= "table" then if not create then return end; db.chatLog = {} end
  return db.chatLog
end

function C.Record(chat, text, r, g, b, id)
  if C.replaying or type(text) ~= "string" or text == "" or C.Get("chatKeepHistory") == false or isCombatLog(chat) then return end
  local log = logTable(true)
  if not log then return end
  local name = chat:GetName()
  local list = log[name]
  if type(list) ~= "table" then list = {}; log[name] = list end
  if #text > C.HISTORY_CHARS then text = plain(text):sub(1, C.HISTORY_CHARS) end -- cut as plain text: a cut escape code would corrupt the line
  list[#list + 1] = { t = text, r = tonumber(r), g = tonumber(g), b = tonumber(b), id = tonumber(id) }
  while #list > C.HISTORY_LINES do table.remove(list, 1) end
end

C.SEPARATOR = "--- previous session ---" -- dim grey, shown once after the replayed lines (never saved)
function C.Replay()
  if C.Get("chatKeepHistory") == false then return end
  local log = logTable(false)
  if not log then return end
  C.replaying = true
  pcall(function()
    for i = 1, 20 do
      local chat, list = _G["ChatFrame" .. i], log["ChatFrame" .. i]
      if chat and type(list) == "table" and not isCombatLog(chat) then
        local n = 0
        for _, e in ipairs(list) do
          if type(e) == "table" and type(e.t) == "string" then
            chat:AddMessage(e.t, tonumber(e.r), tonumber(e.g), tonumber(e.b), tonumber(e.id)); n = n + 1
          end
        end
        if n > 0 then chat:AddMessage(C.SEPARATOR, 0.5, 0.5, 0.5) end
      end
    end
  end)
  C.replaying = false
end

function C.ClearHistory() local db = _G.AztraForeverUICharDB; if type(db) == "table" then db.chatLog = {} end end

-- The guild window (Guild & Communities) shows and keeps guild chat itself, from the events: a message filter only hides the line in the chat windows.
function C.GuildFilter() return AFUI.ModuleEnabled("guild") and not C.Get("chatGuildInWindow") end -- Guild windows switched off: no window to read guild chat in, so the chat windows keep it

local function feed(chat)
  if chat.afuiFed then return end
  chat.afuiFed = true
  local name = chat:GetName()
  hooksecurefunc(chat, "AddMessage", function(_, text, r, g, b2, id)
    C.Record(chat, text, r, g, b2, id)
    local b = C.buffers[name]
    if not b then b = {}; C.buffers[name] = b end
    b[#b + 1] = text
    if #b > C.BUFFER then table.remove(b, 1) end
  end)
end

function C.CopyWindow()
  if C.win then return C.win end
  local W, K = widgets(), AFUI.WinKit
  if not (W and K) then return end
  local f = W.Panel("AFUI_ChatCopyWindow", 560, 380, true)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f.title = title(f, "Copy Chat")
  f.close = W.CloseButton(f, function() f:Hide() end)
  local scroll = CreateFrame("ScrollFrame", "AFUI_ChatCopyScroll", f)
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44); scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -42, 20)
  local back = scroll:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(back, 0, 0, 0, 0.5); back:SetAllPoints(scroll)
  local eb = CreateFrame("EditBox", "AFUI_ChatCopyEdit", scroll)
  eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFont(textFont(), 14, ""); eb:SetMaxLetters(0)
  eb:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0); eb:SetWidth(498); eb:SetTextInsets(6, 6, 4, 4)
  eb:SetScript("OnEscapePressed", function() f:Hide() end)
  eb:SetScript("OnTextChanged", function(self, user)
    if user and f.text and self:GetText() ~= f.text then self:SetText(f.text) end -- selectable, not editable
    scroll:UpdateScrollChildRect()
  end)
  scroll:SetScrollChild(eb)
  scroll:EnableMouseWheel(true)
  f.scroll, f.edit = scroll, eb
  K.scrollbar(scroll, {
    get = function() return scroll:GetVerticalScroll() or 0 end,
    set = function(v) scroll:SetVerticalScroll(v) end,
    max = function() return scroll:GetVerticalScrollRange() or 0 end,
    view = function() return scroll:GetHeight() or 0 end,
    step = 40,
  }, { parent = f, x = 3 })
  K.makeMovable(f, nil, "chatcopy")
  if _G.UISpecialFrames then table.insert(UISpecialFrames, "AFUI_ChatCopyWindow") end
  C.win = f
  return f
end

local function windowName(chat)
  local n = chat:GetName()
  if n == "ChatFrame1" then return "General" end
  local tab = _G[n .. "Tab"]
  return tab and tab.GetText and tab:GetText() or n
end

-- Shows the last lines of `chat` (default: the General window) selectable in a scrollable window.
function C.ShowCopy(chat)
  chat = chat or _G.ChatFrame1
  local f = C.CopyWindow()
  if not (f and chat) then return end
  local lines = C.Lines(chat)
  local text = table.concat(lines, "\n")
  f.text, f.lines = text, #lines
  f.title:SetText("Copy Chat - " .. windowName(chat))
  f.edit:SetText(text)
  f:Show()
  f.scroll:SetVerticalScroll(f.scroll:GetVerticalScrollRange() or 0) -- newest line in view
  f.edit:SetFocus(); f.edit:HighlightText(0, 0)
  return f
end

---------------------------------------------------------------- timestamps
C.STAMP_COLOR = "|cff9a9a9a"
-- The setting's value -> the client's showTimestamps CVar string (the formats of the client's own dropdown).
C.STAMPS = { none = "none", ["15:27"] = "%H:%M ", ["15:27:32"] = "%H:%M:%S ", ["03:27 PM"] = "%I:%M %p ", ["03:27:32 PM"] = "%I:%M:%S %p " }
C.STAMP_ORDER = { "none", "15:27", "15:27:32", "03:27 PM", "03:27:32 PM" }

function C.StampSetting(cvar) for k, v in pairs(C.STAMPS) do if v == cvar then return k end end end
-- "%H:%M " -> "|cff9a9a9a%H:%M|r " (nil for none): the clock grey, the space after it plain.
function C.Coloured(fmt)
  if not fmt or fmt == "none" then return nil end
  if fmt:find("|c", 1, true) then return fmt end
  local clock, space = fmt:match("^(.-)(%s*)$")
  return C.STAMP_COLOR .. clock .. "|r" .. space
end

local later = {}
local timer = CreateFrame("Frame")
timer:Hide()
timer:SetScript("OnUpdate", function(self)
  local run = later
  later = {}
  self:Hide()
  for _, fn in ipairs(run) do fn() end
end)
local function nextFrame(fn) later[#later + 1] = fn; timer:Show() end

-- Puts the grey format into the global the chat windows read (CHAT_TIMESTAMP_FORMAT). The client sets it from the CVar after its own
-- CVAR_UPDATE handler, so a change is recoloured a frame later.
function C.Recolour()
  local fmt = _G.CHAT_TIMESTAMP_FORMAT
  if type(fmt) == "string" and fmt ~= "" and not fmt:find("|c", 1, true) then _G.CHAT_TIMESTAMP_FORMAT = C.Coloured(fmt) end
end

function C.ApplyTimestamps()
  local want = AFUI.GetSetting("chatTimestamps", nil) -- unset: the native dropdown decides, we only colour it
  local cvar = want and C.STAMPS[want]
  if cvar then
    if SetCVar then SetCVar("showTimestamps", cvar) end
    _G.CHAT_TIMESTAMP_FORMAT = C.Coloured(cvar)
  else
    C.Recolour()
  end
end

-- The native dropdown changed the CVar: our setting follows it.
function C.OnCVar(_, name, value)
  local n = tostring(name):lower()
  if n ~= "show_timestamps" and n ~= "showtimestamps" then return end
  local label = C.StampSetting((GetCVar and GetCVar("showTimestamps")) or value)
  if label and AFUI.GetSetting("chatTimestamps", nil) ~= nil and AFUI.GetSetting("chatTimestamps", nil) ~= label then AFUI.SetSetting("chatTimestamps", label) end
  nextFrame(C.Recolour)
end

---------------------------------------------------------------- the edit box strip
local TYPES = { SAY = true, YELL = true, GUILD = true, OFFICER = true, PARTY = true, RAID = true, RAID_WARNING = true, BATTLEGROUND = true, EMOTE = true }

function C.editBox() return _G.ChatFrame1EditBox or _G.ChatFrameEditBox end

-- "Say:" / "Guild:" / "To Name:" / "[2]:" in the chat type's colour.
function C.Header(eb)
  local kind = eb and eb.GetAttribute and eb:GetAttribute("chatType") or "SAY"
  local info = _G.ChatTypeInfo and ChatTypeInfo[kind] or { r = 1, g = 1, b = 1 }
  local text
  if kind == "WHISPER" then text = "To " .. tostring(eb:GetAttribute("tellTarget") or "") .. ":"
  elseif kind == "CHANNEL" then text = "[" .. tostring(eb:GetAttribute("channelTarget") or 1) .. "]:"
  elseif TYPES[kind] then text = (tostring(_G["CHAT_" .. kind .. "_SEND"] or (kind .. ": ")):gsub("%s+$", ""))
  else text, info = (tostring(_G.CHAT_SAY_SEND or "Say: "):gsub("%s+$", "")), (_G.ChatTypeInfo and ChatTypeInfo.SAY) or info end
  return text, info.r, info.g, info.b
end

local STRIP_ALPHA = 0.35 -- the deactivated edit box in Forever (chatframeeditbox.lua: the "im" style keeps it at 0.35)

function C.Strip()
  if C.strip then return C.strip end
  local A, chat = AFUI.ChatArt, _G.ChatFrame1
  if not (A and chat) then return end
  local s = CreateFrame("Button", "AFUI_ChatStrip", UIParent)
  s:SetFrameStrata("LOW"); s:SetHeight(32)
  s:SetPoint("TOPLEFT", chat, "BOTTOMLEFT", -5, -2); s:SetPoint("TOPRIGHT", chat, "BOTTOMRIGHT", 5, -2) -- where ChatFrame1EditBox sits
  s:EnableMouse(true)
  local parts = {}
  for i, k in ipairs({ "Left", "Mid", "Right" }) do
    local t = s:CreateTexture("AFUI_ChatStrip" .. k, "BACKGROUND")
    A.Art(t, "UI-ChatInputBorder-" .. k .. "2")
    t:SetAlpha(STRIP_ALPHA)
    parts[i] = t
  end
  for _, d in ipairs({ { parts[1], "LEFT" }, { parts[3], "RIGHT" } }) do
    d[1]:SetWidth(32); d[1]:SetHeight(32); d[1]:SetPoint(d[2], s, d[2], 0, 0)
  end
  parts[2]:SetHeight(32); parts[2]:SetPoint("TOPLEFT", parts[1], "TOPRIGHT"); parts[2]:SetPoint("TOPRIGHT", parts[3], "TOPLEFT")
  if A.V.tile and parts[2].SetHorizTile then parts[2]:SetHorizTile(true) end
  s.header = s:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
  s.header:SetPoint("LEFT", s, "LEFT", 15, 0)
  s.prompt = s:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
  s.prompt:SetPoint("LEFT", s.header, "RIGHT", 4, 0)
  s.prompt:SetText("Press Enter to chat"); s.prompt:SetTextColor(1, 1, 1); s.prompt:SetAlpha(STRIP_ALPHA)
  s.parts = parts
  s:SetScript("OnClick", function() if _G.ChatFrame_OpenChat then ChatFrame_OpenChat("", chat) end end)
  s:SetScript("OnShow", function(self)
    local text, r, g, b = C.Header(C.editBox())
    self.header:SetText(text); self.header:SetTextColor(r, g, b); self.header:SetAlpha(0.8)
  end)
  s:Hide()
  C.strip = s
  return s
end

-- Shown while the real edit box is not (it takes the strip's place with the same art, so nothing jumps) and 'chatStrip' is on.
function C.UpdateStrip()
  local s = C.Strip()
  if not s then return end
  local eb, chat = C.editBox(), _G.ChatFrame1
  local show = C.Get("chatStrip") ~= false and chat and (chat:IsShown() or chat.isDocked) and not (eb and eb:IsShown())
  if show then s:Show() else s:Hide() end
  return show
end

---------------------------------------------------------------- hooks
-- Right click on a chat tab: the client opens its tab menu, "Copy Chat" is appended to it.
function C.MenuItem(tab, button)
  if button ~= "RightButton" or not (_G.DropDownList1 and DropDownList1:IsShown() and _G.UIDropDownMenu_AddButton) then return end
  local chat = tab.afuiChat or (tab.GetID and _G["ChatFrame" .. tostring(tab:GetID())])
  if not chat then return end
  local info = _G.UIDropDownMenu_CreateInfo and UIDropDownMenu_CreateInfo() or {}
  info.text, info.notCheckable, info.func = "Copy Chat", 1, function() C.ShowCopy(chat) end
  UIDropDownMenu_AddButton(info, 1)
end

function C.Apply()
  C.UpdateStrip()
  if AFUI.ChatApplyFade then AFUI.ChatApplyFade() end
  C.ApplyTimestamps()
end

local function feedAll() for i = 1, 20 do local chat = _G["ChatFrame" .. i]; if chat then feed(chat) end end end

local function setup()
  if C.ready then return end
  C.ready = true
  if _G.ChatFrame_AddMessageEventFilter then
    for _, e in ipairs(C.EVENTS) do ChatFrame_AddMessageEventFilter(e, C.Filter) end
  end
  if _G.SetItemRef then
    hooksecurefunc("SetItemRef", function(link)
      local url = type(link) == "string" and link:match("^" .. C.TYPE .. ":(.+)$")
      if url then C.OpenUrl(url) end
    end)
  end
  local tip = _G.ItemRefTooltip -- the client does not know our link type: after its own SetHyperlink runs, close the tooltip (a post-hook: no Blizzard function is replaced)
  if tip and tip.SetHyperlink then
    hooksecurefunc(tip, "SetHyperlink", function(self, link)
      if type(link) == "string" and link:find("^" .. C.TYPE .. ":") then self:Hide() end
    end)
  end
  if _G.ChatFrame_AddMessageEventFilter then
    for _, e in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER" }) do ChatFrame_AddMessageEventFilter(e, C.GuildFilter) end
  end
  feedAll()
  C.Replay()
  if AFUI.OnSettingChanged then AFUI.OnSettingChanged("chatKeepHistory", function(v) if v == false then C.ClearHistory() end end) end
  AFUI.Slash.Register("chatlog", function(rest)
    if tostring(rest or ""):lower():find("clear", 1, true) then AFUI.Print("saved chat history cleared"); C.ClearHistory() else AFUI.Print("usage: /afui chatlog clear") end
  end, "wipe the chat history saved between sessions", "/afui chatlog clear")
  if _G.FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", feedAll) end
  if _G.FCF_Tab_OnClick then hooksecurefunc("FCF_Tab_OnClick", C.MenuItem) end
  SLASH_AFUICOPY1 = "/copychat"
  SlashCmdList["AFUICOPY"] = function() C.ShowCopy(_G.DEFAULT_CHAT_FRAME) end
  local eb, chat = C.editBox(), _G.ChatFrame1
  if eb then eb:HookScript("OnShow", C.UpdateStrip); eb:HookScript("OnHide", C.UpdateStrip) end
  if chat then chat:HookScript("OnShow", C.UpdateStrip); chat:HookScript("OnHide", C.UpdateStrip) end
  if type(AFUI.SetSetting) == "function" then
    hooksecurefunc(AFUI, "SetSetting", function(key)
      if key == "chatStrip" then C.UpdateStrip()
      elseif key == "chatFade" and AFUI.ChatApplyFade then AFUI.ChatApplyFade()
      elseif key == "chatTimestamps" then C.ApplyTimestamps() end
    end)
  end
  AFUI.On("CVAR_UPDATE", C.OnCVar)
  C.Apply()
end

AFUI.RegisterModule("ChatQoL", { OnLogin = setup })
