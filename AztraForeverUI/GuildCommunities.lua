-- Forever's "Guild & Communities" window (key J): the guild chat in its own window, a roster with sortable columns, the guild info and the guild log, in
-- Forever's metal portrait frame. References: docs/forever-ref/video2/mat-shots/forever-guild-{chat,roster,info}.png.
-- What 2.5.3 has and what it has not: the client has guild chat (CHAT_MSG_GUILD / OFFICER), the roster API, the MOTD, the guild info text and the guild event
-- log (verified against Gethe/wow-ui-source 2.5.3 FriendsFrame.lua / FriendsFrame.xml: sort keys name, zone, level, class, rank, note, online;
-- GetGuildRosterShowOffline / SetGuildRosterShowOffline; GetNumGuildMembers -> total, online). It has NO communities, NO guild news and NO voice chat, so the
-- "Join or Create Community" plate, the news column and the voice icon are not built: the left column carries only the guild card (name, online count), the
-- Info page widens its panels to the whole width, and the fourth side tab is the guild log (real data) instead of news.
-- Guild chat is only mirrored: our listeners record CHAT_MSG_GUILD / OFFICER / the guild system messages into AztraForeverUICharDB.guildChat (200 lines);
-- the normal chat frames receive everything as before. Opening this window hides the G-key guild window (GuildWindow.lua) and the other way round.
-- Nothing here is protected: it works in combat.
AFUI = AFUI or {}
local C = {}
AFUI.GuildCommunities = C

---------------------------------------------------------------- data (pure; specs: tests/lua/guildcomm_spec.lua)
-- Spacing, defined once: every panel's rectangle comes from C.Layout (below), never from a number typed where it is anchored.
--   M      the one margin between the window frame and every inner panel (left, right and bottom; the title bar is TOP)
--   G      the one gap between neighbouring panels (left column | pages, log | member list, log / input, MOTD / guild info)
--   RIM    the 1 px bronze rule round every inner panel (WinKit K.panel's colour); INSET = what content keeps clear of it (rim + 1 px)
C.M, C.G, C.RIM, C.INSET = 8, 6, { 0.45, 0.37, 0.2 }, 2
C.TOP, C.HEAD, C.STRIP_H = 26, 28, 28 -- title bar, header row of the pages (channel field, counts), bottom strip (Invite Member)
C.LEFT_W, C.MEM_W, C.INPUT_H, C.HDR_H, C.MOTD_H = 165, 156, 24, 20, 120
C.CAP = 200
C.ROWS, C.MROWS, C.ROW_H = 15, 16, 20 -- roster rows, member list rows
-- The pages' height is whole rows: the member list holds MROWS rows inside its rim, the roster body ROWS rows under its HDR_H head.
C.CH = C.MROWS * C.ROW_H + 2 * C.INSET
C.W, C.W_NONE, C.H_NONE = 814, 430, 230
C.H = C.TOP + C.HEAD + C.CH + C.G + C.STRIP_H + C.M
local GUILD = "Interface\\AddOns\\AztraForeverUI\\Media\\guild\\" -- not Media/plain: bluemenu-main is 256 x 1024
-- The tab icons are the ones Blizzard_Communities' CommunitiesFrame.xml names (UI_Chat, achievement_guildperk_everybodysfriend, inv_misc_scrollunrolled01), shipped
-- under Media/guild because a 2.5.3 client has none of them (the old chat bubble path drew a white plate there).
C.TABS = {
  { key = "chat", tip = "Chat", icon = GUILD .. "UI_Chat" },
  { key = "roster", tip = "Roster", icon = GUILD .. "achievement_guildperk_everybodysfriend" },
  { key = "info", tip = "Info", icon = GUILD .. "inv_misc_scrollunrolled01" },
  { key = "log", tip = "Guild Log", icon = "Interface\\Icons\\INV_Misc_Map_01" },
}
-- Roster columns (the screenshot): Lvl, Class, Name, Zone, Rank, Note; `sort` is the client's SortGuildRoster key.
C.COLUMNS = {
  { key = "level", label = "Lvl", sort = "level" }, { key = "class", label = "Class", sort = "class" }, { key = "name", label = "Name", sort = "name" },
  { key = "zone", label = "Zone", sort = "zone" }, { key = "rank", label = "Rank", sort = "rank" }, { key = "note", label = "Note", sort = "note" },
}
-- Column widths for a roster `w` px wide: Lvl and Class are fixed, the rest share what is left, Note takes the remainder (no hole at the end).
function C.Columns(w)
  local r = w - 106
  local name, zone, rank = math.floor(r * 0.27), math.floor(r * 0.27), math.floor(r * 0.2)
  return { level = 50, class = 56, name = name, zone = zone, rank = rank, note = r - name - zone - rank }
end

function C.Counts(online, total) return string.format("%d/%d Online", online or 0, total or 0) end

-- "5 hours" / "< an hour" for an offline member (GetGuildRosterLastOnline -> years, months, days, hours).
local function ago(n, unit) return n .. " " .. unit .. (n == 1 and "" or "s") end
function C.LastSeen(y, m, d, h)
  if not y then return "Offline" end
  m, d, h = m or 0, d or 0, h or 0
  if y > 0 then return ago(y, "year") end
  if m > 0 then return ago(m, "month") end
  if d > 0 then return ago(d, "day") end
  if h > 0 then return ago(h, "hour") end
  return "< an hour"
end

-- Cut `text` to fit `w` px in fontstring `fs` with "..." (the preview has no automatic ellipsis; the client's is the same on the result).
function C.Fit(fs, text, w)
  text = text or ""
  fs:SetText(text)
  if not w or fs:GetStringWidth() <= w then return text end
  local n = #text
  while n > 0 do
    n = n - 1
    fs:SetText(string.sub(text, 1, n) .. "...")
    if fs:GetStringWidth() <= w then return string.sub(text, 1, n) .. "..." end
  end
  return ""
end

-- Members: online first, the client's order inside each group.
function C.Members(list)
  local out = {}
  for i, m in ipairs(list) do out[i] = m; m.n = i end
  table.sort(out, function(a, b)
    if (a.online and true or false) ~= (b.online and true or false) then return a.online and true or false end
    return a.n < b.n
  end)
  return out
end

-- Can this player speak in the officer channel? The rank flags of 2.5.3: 1 listen guild, 2 speak guild, 3 listen officer, 4 speak officer.
function C.CanOfficer(rankIndex, flags, leader)
  if leader then return true end
  return flags and flags[4] and true or false
end

-- A roster row: left whispers (member list) or selects (roster), right opens the player menu, a double click whispers.
function C.RowAction(button, double, list)
  if button == "RightButton" then return "menu" end
  if list then return "whisper" end
  return double and "whisper" or "select"
end

function C.Hex(r, g, b) return string.format("%02x%02x%02x", math.floor((r or 1) * 255 + 0.5), math.floor((g or 1) * 255 + 0.5), math.floor((b or 1) * 255 + 0.5)) end
local function chatHex(kind)
  local ti = _G.ChatTypeInfo and ChatTypeInfo[kind]
  if ti then return C.Hex(ti.r, ti.g, ti.b) end
  return ({ GUILD = "40ff40", OFFICER = "40c040", SYSTEM = "ffff80" })[kind] or "ffffff"
end
local function classHex(token)
  local c = token and _G.RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
  return c and C.Hex(c.r, c.g, c.b) or "ffffff"
end

-- Append an entry and keep the newest `cap`.
function C.AddLine(hist, entry, cap)
  hist[#hist + 1] = entry
  cap = cap or C.CAP
  while #hist > cap do table.remove(hist, 1) end
  return hist
end

-- The shown text of one entry (guild green brackets, class coloured name; officer chat in its own green; the MOTD yellow; system lines in the system colour).
function C.LineText(e)
  if e.k == "motd" then return "|cffffff00Message of the Day: \"" .. (e.x or "") .. "\"|r" end
  if e.k == "system" then return "|cff" .. chatHex("SYSTEM") .. (e.x or "") .. "|r" end
  local col = chatHex(e.k == "officer" and "OFFICER" or "GUILD")
  local tag = e.k == "officer" and "[O] " or ""
  return "|cff" .. col .. tag .. "[|r|cff" .. classHex(e.c) .. (e.n or "?") .. "|r|cff" .. col .. "]: " .. (e.x or "") .. "|r"
end

-- "Today" / "Yesterday" / the date of timestamp t.
function C.DayLabel(t, now)
  if not date or not t then return "" end
  local function day(x) return date("%Y%m%d", x) end
  if day(t) == day(now) then return "Today" end
  if day(t) == day(now - 86400) then return "Yesterday" end
  return date("%B %d, %Y", t)
end

-- The log as display lines: a grey day separator (with a blank line before it) when the day changes, then the entries.
function C.BuildLines(hist, now)
  local out, last = {}, nil
  for _, e in ipairs(hist) do
    local d = date and e.t and date("%Y%m%d", e.t) or nil
    if d and d ~= last then
      if #out > 0 then out[#out + 1] = " " end
      out[#out + 1] = "|cff9d9d9d" .. C.DayLabel(e.t, now or e.t) .. "|r"
      out[#out + 1] = " "
      last = d
    end
    out[#out + 1] = C.LineText(e)
  end
  return out
end

-- Guild system messages (the client's own format strings turned into patterns), so joins, leaves and promotions land in the log.
local SYSTEM_FORMATS = { "ERR_GUILD_JOIN_S", "ERR_GUILD_LEAVE_S", "ERR_GUILD_PROMOTE_SSS", "ERR_GUILD_DEMOTE_SSS", "ERR_GUILD_REMOVE_SS", "ERR_GUILD_INVITE_S",
  "ERR_GUILD_DISBAND_S", "ERR_GUILD_RANK_CHANGED_S" }
local patterns
local function buildPatterns()
  patterns = {}
  for _, n in ipairs(SYSTEM_FORMATS) do
    local f = _G[n]
    if type(f) == "string" then
      local p = string.gsub(f, "([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
      p = string.gsub(p, "%%%%[1-9]?%$?s", ".+")
      patterns[#patterns + 1] = "^" .. p .. "$"
    end
  end
end
function C.IsGuildSystem(text)
  if type(text) ~= "string" then return false end
  if not patterns then buildPatterns() end
  for _, p in ipairs(patterns) do if string.find(text, p) then return true end end
  return false
end

-- J is the client's own Guild / Social key (TBC Classic): the window takes it over only while J is free or still one of those stock toggles.
local STOCK_J = { TOGGLEGUILDTAB = true, TOGGLEGUILD = true, TOGGLESOCIAL = true }
-- What to do with the key: "bind" J once (free or stock, and the player has not decided before: their own unbinding is respected); "migrate" a SHIFT-J
-- binding of an earlier version to J; nil = leave every key alone. actionJ / actionShiftJ = GetBindingAction of that key, haveKey = our action already has a key.
function C.BindPlan(actionJ, already, actionShiftJ, haveKey)
  if not (actionJ == nil or actionJ == "" or STOCK_J[actionJ]) then return nil end
  if actionShiftJ == "AFUI_GUILDCOMM" then return already and "migrate" or nil end
  if not already and not haveKey then return "bind" end
  return nil
end

---------------------------------------------------------------- state
local state = { tab = "chat", channel = "GUILD", offset = 0, selected = nil, collapsed = false, memberOffset = 0 }
C.state = state
local win, roster, members = nil, {}, {}
local classOf = {} -- name -> class token, from the last roster read
local hist = {}
C.hist = function() return hist end
local function db() return AztraForeverUICharDB end

local function api(fn) local f = _G[fn]; if type(f) ~= "function" and _G.C_GuildInfo then f = C_GuildInfo[fn] end; return type(f) == "function" and f or nil end
local function canDo(fn, ...) local f = api(fn); return f and f(...) end
local function has(fn) return api(fn) ~= nil end
local function K() return AFUI.WinKit end
local function P() return AFUI.Professions.Kit end
local function fs(parent, font, layer) local t = parent:CreateFontString(nil, layer or "OVERLAY", font or "GameFontHighlight"); t:SetJustifyH("LEFT"); return t end
local function bare(name) return (string.gsub(name or "", "%-.*$", "")) end

---------------------------------------------------------------- chat capture (runs with the window closed too)
local function now() return time and time() or 0 end
local function record(e)
  if not AFUI.ModuleEnabled("guild") then return end -- Guild windows switched off: guild chat is not kept for a window that is not drawn
  e.t = e.t or now()
  C.AddLine(hist, e, C.CAP)
  if win and win:IsShown() and state.tab == "chat" then C.RefreshChat() end
end

local function classFor(name, guid)
  if guid and guid ~= "" and type(GetPlayerInfoByGUID) == "function" then
    local _, token = GetPlayerInfoByGUID(guid)
    if token then return token end
  end
  return classOf[name]
end

local function onChat(kind)
  return function(_, text, sender, _, _, _, _, _, _, _, _, _, guid)
    local name = bare(sender)
    record({ k = kind, n = name, c = classFor(name, guid), x = text })
  end
end

local function lastOf(kind) for i = #hist, 1, -1 do if hist[i].k == kind then return hist[i] end end end
local function noteMotd(text)
  if not text or text == "" then return end
  local l = lastOf("motd")
  if l and l.x == text then return end
  record({ k = "motd", x = text })
end

local function setupChat()
  local d = db()
  if d then
    if type(d.guildChat) ~= "table" then d.guildChat = {} end
    hist = d.guildChat
    while #hist > C.CAP do table.remove(hist, 1) end
    if d.guildCommTab then
      for _, t in ipairs(C.TABS) do if t.key == d.guildCommTab then state.tab = t.key end end
    end
  end
end
AFUI.On("CHAT_MSG_GUILD", onChat("guild"))
AFUI.On("CHAT_MSG_OFFICER", onChat("officer"))
AFUI.On("CHAT_MSG_SYSTEM", function(_, text) if C.IsGuildSystem(text) then record({ k = "system", x = text }) end end)
AFUI.On("GUILD_MOTD", function(_, text) noteMotd(text) end)

---------------------------------------------------------------- roster data
local function collect()
  roster = {}
  if not IsInGuild() then return 0, 0 end
  local total, online = GetNumGuildMembers()
  total, online = total or 0, online or 0
  local showOff = not (has("GetGuildRosterShowOffline")) or GetGuildRosterShowOffline()
  local n = showOff and total or online
  for i = 1, n do
    local name, rank, rankIndex, level, class, zone, note, officer, on, status, token = GetGuildRosterInfo(i)
    if name then
      name = bare(name)
      if token then classOf[name] = token end
      roster[#roster + 1] = { i = i, name = name, rank = rank, rankIndex = rankIndex, level = level, class = class, zone = zone, note = note, officer = officer, online = on, status = status, token = token }
    end
  end
  return total, online
end

local function classColor(token)
  local c = token and _G.RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
  if c then return c.r, c.g, c.b end
  return 1, 0.82, 0
end

local function lastSeen(i)
  if not GetGuildRosterLastOnline then return C.LastSeen(nil) end
  return C.LastSeen(GetGuildRosterLastOnline(i))
end

---------------------------------------------------------------- small widgets
local function edges(f, r, g, b)
  r, g, b = r or C.RIM[1], g or C.RIM[2], b or C.RIM[3]
  for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1 }, { "TOPRIGHT", "BOTTOMRIGHT", 1 } }) do
    local t = f:CreateTexture(nil, "BORDER"); AFUI.SetColor(t, r, g, b, 1); t:SetPoint(e[1], f); t:SetPoint(e[2], f)
    if e[3] then t:SetWidth(1) else t:SetHeight(1) end
  end
end

-- Forever's insets (the client's InsetFrameTemplate Bg is UI-Background-Marble): `dark` = the chat log / roster / member list (marble on a grey base, about #1c1d1a
-- averaged), `brown` = the Info panels (about #412e13). A solid base under the tiled marble; 2.4.3 has no tiling (and no 256 px marble worth it): base colour only.
-- The panel sits at (x1, y1) / (x2, y2) offsets from `to`; returns the base texture.
local FILL = { dark = { 0.155, 0.16, 0.145, 0.45 }, brown = { 0.367, 0.25, 0.09, 0.35 } }
local function fill(f, kind, to, x1, y1, x2, y2)
  local c = FILL[kind]
  to = to or f
  local base = f:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(base, c[1], c[2], c[3], 1)
  base:SetPoint("TOPLEFT", to, "TOPLEFT", x1 or 0, y1 or 0); base:SetPoint("BOTTOMRIGHT", to, "BOTTOMRIGHT", x2 or 0, y2 or 0)
  if not AFUI.IS_243 then
    local m = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    m:SetTexture(GUILD .. "UI-Background-Marble", "REPEAT", "REPEAT") -- tiling needs the wrap mode: with CLAMP the last texel row / column smears into streaks
    m:SetAlpha(c[4])
    m:SetPoint("TOPLEFT", base, "TOPLEFT"); m:SetPoint("BOTTOMRIGHT", base, "BOTTOMRIGHT")
    if type(m.SetHorizTile) == "function" and type(m.SetVertTile) == "function" then m:SetHorizTile(true); m:SetVertTile(true) end
  end
  return base
end

-- Every inner panel is made here: the same 1 px bronze rim and the same marble fill, whatever the page. `shade` darkens the fill (the send box).
local function box(f, kind, shade)
  fill(f, kind); edges(f)
  if shade then local t = f:CreateTexture(nil, "BACKGROUND", nil, 2); AFUI.SetColor(t, 0, 0, 0, shade); t:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1); t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1) end
  return f
end
-- A rectangle of C.Layout (window coordinates, y down) as the frame's anchors and size.
local function place(f, r)
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", win, "TOPLEFT", r.x, -r.y); f:SetWidth(r.w); f:SetHeight(r.h)
end
local function panelFrame(parent, kind, r, shade)
  local f = CreateFrame("Frame", nil, parent); box(f, kind, shade); place(f, r)
  return f
end
-- What a list may use inside its panel: the panel less the rim's inset, the scroll bar (inside the rim, on the right) taking its width.
local function content(r) return { w = r.w - 2 * C.INSET - K().SB.W - 1, h = r.h - 2 * C.INSET } end
local function barInside(panel) return function(bar)
  bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -C.INSET, -C.INSET); bar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -C.INSET, C.INSET)
end end

-- Forever's minimal scroll bar (WinKit.scrollbar): the lists scroll by rows (a glide, the rows tick), the log frames by lines.
local function rowsBar(list, panel, offset, setOffset, maxOff, rows)
  return K().scrollbar(list, { get = offset, set = setOffset, max = maxOff, view = function() return rows end, step = 2, integer = true, eps = 0.01 },
    { parent = panel, place = barInside(panel) })
end
-- A ScrollingMessageFrame: the bar's 0 is the oldest line (the frame counts from the newest), `step` lines a notch.
local function logBar(log, panel)
  local function lines() return math.max(1, math.floor((log:GetHeight() or 0) / (select(2, log:GetFont()) or 14))) end
  local function maxOff() return math.max(0, (log:GetNumMessages() or 0) - lines()) end
  local function cur() return (log.GetScrollOffset and log:GetScrollOffset()) or (log.GetCurrentScroll and log:GetCurrentScroll()) or 0 end
  local bar = K().scrollbar(log, {
    get = function() return maxOff() - cur() end,
    set = function(v) if log.SetScrollOffset then log:SetScrollOffset(maxOff() - v) end end,
    max = maxOff, view = lines, step = 3, integer = true, eps = 0.01,
  }, { parent = panel, place = barInside(panel) })
  if type(hooksecurefunc) == "function" then
    pcall(hooksecurefunc, log, "AddMessage", function() bar:Refresh() end)
    pcall(hooksecurefunc, log, "Clear", function() bar:Refresh() end)
  end
  return bar
end

local function redButton(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"); b:SetText(text); K().button(b, w, 22)
  return b
end

---------------------------------------------------------------- chat page
function C.RefreshChat()
  if not win or not win.log then return end
  local log = win.log
  log:Clear()
  for _, l in ipairs(C.BuildLines(hist, now())) do log:AddMessage(l) end
  if log.ScrollToBottom then log:ScrollToBottom() end
end

local function officerOK()
  local _, _, idx = GetGuildInfo("player")
  local flags
  if idx and type(GuildControlGetRankFlags) == "function" then flags = { GuildControlGetRankFlags(idx + 1) } end
  if C.CanOfficer(idx, flags, canDo("IsGuildLeader") and true or false) then return true end
  -- the rank flags can be unreadable (nil) until the client has the guild control data: an officer can edit the officer note, which says the same
  if not (flags and flags[4] ~= nil) then
    if type(CanEditOfficerNote) == "function" and CanEditOfficerNote() then return true end
    if C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer() then return true end
  end
  return false
end

local function sendText(text)
  text = string.gsub(text or "", "^%s+", ""); text = string.gsub(text, "%s+$", "")
  if text == "" then return false end
  if string.sub(text, 1, 1) == "/" then
    if type(ChatFrame_OpenChat) == "function" then ChatFrame_OpenChat(text) end -- a slash command goes through the client's own edit box
    return true
  end
  local channel = state.channel == "OFFICER" and officerOK() and "OFFICER" or "GUILD"
  SendChatMessage(text, channel)
  return true
end
C.Send = sendText

local function updateMembers()
  local list = C.Members(roster)
  members = list
  local rows = win.mrows
  local maxOff = math.max(0, #list - C.MROWS)
  if state.memberOffset > maxOff then state.memberOffset = maxOff end
  win.msb:Refresh()
  for i = 1, C.MROWS do
    local r, m = rows[i], list[state.memberOffset + i]
    if not m then r:Hide() else
      r:Show(); r.m = m
      local cr, cg, cb = classColor(m.token)
      local dim = m.online and 1 or 0.5
      r.name:SetText(m.name); r.name:SetTextColor(cr * dim, cg * dim, cb * dim)
      r.crown:SetShown(m.rankIndex == 0)
      if m.rankIndex == 0 then r.crown:ClearAllPoints(); r.crown:SetPoint("LEFT", r.name, "LEFT", math.min(r.name:GetStringWidth(), 100) + 3, 0) end
    end
  end
end

-- Where a page's list goes inside its panel (rect r): clear of the rim, the scroll bar's strip kept free on the right. The text logs keep 2 px more air.
local LOG_PAD = C.INSET + 2
local function sizeLog(f, panel, r)
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", panel, "TOPLEFT", LOG_PAD, -LOG_PAD)
  f:SetWidth(r.w - LOG_PAD - (K().SB.W + C.INSET + 3)); f:SetHeight(r.h - 2 * LOG_PAD)
end

-- The channel menu: our own frames (the client's UIDropDownMenu would taint). Opens under the field, Guild and Officer, the current one ticked; Officer is
-- greyed with a reason when the rank cannot speak there. Closes on a choice, a click anywhere else (a full screen catcher under it), Escape and the window hiding.
local CHANNELS = { { key = "GUILD", text = "Guild" }, { key = "OFFICER", text = "Officer" } }
C.CHANNELS = CHANNELS
C.OFFICER_TIP = "Your rank cannot speak in officer chat"
C.ITEM_H, C.CHANNEL_W = 22, 130
C.TOGGLE_LABEL = "Guild chat in chat windows"
C.TOGGLE_TIP = "On: guild chat also appears in your normal chat windows. Off: it shows only here (this window keeps it either way)."
local function rgb(hex) return tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255, tonumber(string.sub(hex, 5, 6), 16) / 255 end

function C.ChannelMenuShown() return win and win.channelMenu and win.channelMenu:IsShown() and true or false end
function C.CloseChannelMenu()
  if not (win and win.channelMenu) then return end
  win.channelMenu:Hide(); win.channelMenu.catcher:Hide()
  if win.channel.bar.state then win.channel.bar:state(nil) end
end
function C.ChooseChannel(key)
  for _, c in ipairs(CHANNELS) do
    if c.key == key and (key ~= "OFFICER" or officerOK()) then state.channel = key; C.CloseChannelMenu(); C.UpdateHeader(); return true end
  end
  return false
end
function C.OpenChannelMenu()
  local m = win and win.channelMenu
  if not m then return end
  local can = officerOK()
  for _, it in ipairs(m.items) do
    local ok = it.key ~= "OFFICER" or can
    it.afOK = ok
    it.check:SetShown(state.channel == it.key and ok)
    if ok then it.label:SetTextColor(rgb(chatHex(it.key))) else it.label:SetTextColor(0.5, 0.5, 0.5) end
  end
  m.catcher:Show(); m:Show()
  if win.channel.bar.state then win.channel.bar:state("open") end
end

local function buildChannelMenu(ch)
  local H = C.ITEM_H
  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent); catcher:SetFrameStrata("DIALOG"); catcher:SetFrameLevel(90)
  catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp"); catcher:Hide()
  catcher:SetScript("OnClick", function() C.CloseChannelMenu() end)
  local m = CreateFrame("Frame", nil, UIParent)
  m:SetFrameStrata("DIALOG"); m:SetFrameLevel(100); m:SetWidth(C.CHANNEL_W); m:SetHeight(#CHANNELS * H + 2 * C.INSET)
  m:SetPoint("TOPLEFT", ch, "BOTTOMLEFT", 0, -2)
  m:EnableMouse(true); m:Hide(); box(m, "dark")
  m.catcher, m.items = catcher, {}
  for i, c in ipairs(CHANNELS) do
    local b = CreateFrame("Button", nil, m)
    b:SetWidth(C.CHANNEL_W - 2 * C.INSET); b:SetHeight(H); b:SetPoint("TOPLEFT", m, "TOPLEFT", C.INSET, -C.INSET - (i - 1) * H)
    K().row(b)
    b.key = c.key
    b.check = b:CreateTexture(nil, "ARTWORK"); b.check:SetWidth(14); b.check:SetHeight(14); b.check:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.check:SetTexture("Interface\\AddOns\\AztraForeverUI\\Media\\plain\\UI-CheckBox-Check"); b.check:Hide()
    b.label = fs(b, "GameFontNormal"); b.label:SetPoint("LEFT", b, "LEFT", 22, 0); b.label:SetText(c.text)
    b:SetScript("OnClick", function() C.ChooseChannel(c.key) end) -- a greyed Officer does nothing (ChooseChannel refuses it)
    b:SetScript("OnEnter", function(self)
      if not self.afOK and self.key == "OFFICER" then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(C.OFFICER_TIP, 1, 0.3, 0.3, 1, true); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    m.items[i] = b
  end
  if m.EnableKeyboard then -- Escape closes the menu alone (the window stays); every other key goes on to the game
    m:EnableKeyboard(true)
    m:SetScript("OnKeyDown", function(self, key)
      if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(key ~= "ESCAPE") end
      if key == "ESCAPE" then C.CloseChannelMenu() end
    end)
  end
  win.channelMenu = m
end

-- The chat page's frames; C.ApplyLayout puts every one of them in its rectangle.
local function buildChat(host)
  local pn = win.p
  -- log, with its scroll bar inside the panel
  pn.log = CreateFrame("Frame", nil, host); box(pn.log, "dark")
  local log = CreateFrame("ScrollingMessageFrame", nil, pn.log)
  log:SetFont(ARIAL_NARROW_FONT or STANDARD_TEXT_FONT or "Fonts/ARIALN.TTF", 14); log:SetJustifyH("LEFT"); log:SetMaxLines(600); log:SetFading(false); if log.SetIndentedWordWrap then log:SetIndentedWordWrap(true) end
  if log.SetInsertMode then log:SetInsertMode("BOTTOM") end
  win.log = log
  win.logSb = logBar(log, pn.log)
  -- input: the panel itself, as wide as the log's
  local input = CreateFrame("EditBox", nil, host); input:SetAutoFocus(false); input:SetMaxLetters(255); input:SetFontObject(GameFontHighlight); input:SetTextInsets(8, 8, 0, 0)
  box(input, "dark", 0.5)
  input:SetScript("OnEnterPressed", function(self) if sendText(self:GetText()) then self:SetText("") end end)
  input:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  win.input, pn.input = input, input
  -- channel field ("Guild" in guild green) with the real menu
  local ch = CreateFrame("Button", nil, win.header); ch:SetWidth(C.CHANNEL_W); ch:SetHeight(24)
  local W = AFUI.EditModeWidgets -- Forever's field with the boxed down arrow (f0134); WinKit's bar where the widgets are not loaded
  ch.bar = (W and W.ForeverField or K().bar)(ch, "BACKGROUND"); ch.bar:place(ch, 0, 0, 0, 0)
  ch.text = fs(ch, "GameFontNormal"); ch.text:SetPoint("LEFT", ch, "LEFT", 14, 1)
  ch:SetScript("OnClick", function() if C.ChannelMenuShown() then C.CloseChannelMenu() else C.OpenChannelMenu() end end)
  ch:SetScript("OnEnter", function() if ch.bar.state and not C.ChannelMenuShown() then ch.bar:state("hover") end end)
  ch:SetScript("OnLeave", function() if ch.bar.state and not C.ChannelMenuShown() then ch.bar:state(nil) end end)
  win.channel = ch
  buildChannelMenu(ch)
  -- guild chat in the normal chat windows: off by default (this window keeps it). A checkbox with its label; the tooltip has the whole story.
  local gb = CreateFrame("CheckButton", nil, win.header, "OptionsCheckButtonTemplate"); K().check(gb); gb:SetWidth(26); gb:SetHeight(26)
  gb.label = fs(win.header, "GameFontNormal"); gb.label:SetPoint("LEFT", gb, "RIGHT", 2, 0); gb.label:SetText(C.TOGGLE_LABEL)
  gb:SetScript("OnClick", function() AFUI.SetSetting("chatGuildInWindow", not AFUI.GetSetting("chatGuildInWindow", false)); C.UpdateHeader() end)
  gb:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(C.TOGGLE_LABEL, 1, 1, 1)
    GameTooltip:AddLine(C.TOGGLE_TIP, 0.9, 0.8, 0.5, true); GameTooltip:Show()
  end)
  gb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  win.chatToggle = gb
  if AFUI.OnSettingChanged then AFUI.OnSettingChanged("chatGuildInWindow", function() C.UpdateHeader() end) end
  -- member list
  local mh = CreateFrame("Frame", nil, host); box(mh, "dark")
  pn.members = mh
  -- the list's watermark (CommunitiesMemberList.xml: an emblem, 128 px, ADD at 10 % in the bottom right corner); 2.5.3 has no guild emblem API, so the banner's shield
  local wm = P().atlasTex(mh, "BORDER", "communities-guildbanner-border", 111, 103.5); wm:SetPoint("BOTTOMRIGHT", mh, "BOTTOMRIGHT", -2, 3)
  wm:SetBlendMode("ADD"); wm:SetAlpha(0.1)
  win.mrows = {}
  for i = 1, C.MROWS do
    local r = CreateFrame("Button", nil, mh)
    r:SetHeight(C.ROW_H - 1); r:SetPoint("TOPLEFT", mh, "TOPLEFT", C.INSET, -C.INSET - (i - 1) * C.ROW_H)
    K().row(r)
    r.name = fs(r, "GameFontNormal"); r.name:SetPoint("LEFT", r, "LEFT", 8, 0); r.name:SetWidth(110)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.crown = r:CreateTexture(nil, "OVERLAY"); r.crown:SetWidth(12); r.crown:SetHeight(12); r.crown:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon"); r.crown:Hide()
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, button)
      local m = self.m; if not m then return end
      local act = C.RowAction(button, false, true)
      if act == "menu" then if type(FriendsFrame_ShowDropdown) == "function" then FriendsFrame_ShowDropdown(m.name, m.online and 1 or nil) end
      elseif m.online and type(ChatFrame_SendTell) == "function" and m.name ~= UnitName("player") then ChatFrame_SendTell(m.name) end
    end)
    r:Hide()
    win.mrows[i] = r
  end
  win.msb = rowsBar(mh, mh, function() return state.memberOffset end, function(v) if v ~= state.memberOffset then state.memberOffset = v; updateMembers() end end,
    function() return math.max(0, #members - C.MROWS) end, C.MROWS)
end

---------------------------------------------------------------- roster page
-- The roster page: the column heads (one strip, HDR_H high) over the body panel; the rows, the heads' widths and the scroll bar are placed by C.ApplyLayout.
local function buildRoster(host)
  local pn = win.p
  win.heads = {}
  win.rrows = {}
  for _, c in ipairs(C.COLUMNS) do
    local h = CreateFrame("Button", nil, host)
    local bg = P().atlasTex(h, "BACKGROUND", "profession-tab-c60"); bg:SetAllPoints(h)
    local hl = P().atlasTex(h, "HIGHLIGHT", "profession-tab-glow-c60"); hl:SetAllPoints(h)
    h.label = fs(h, "GameFontNormalSmall"); h.label:SetText(c.label)
    h:SetScript("OnClick", function() if SortGuildRoster then SortGuildRoster(c.sort) end; C.Update() end)
    h.col = c
    win.heads[#win.heads + 1] = h
  end
  local body = CreateFrame("Frame", nil, host); box(body, "dark")
  pn.rbody, win.rbody = body, body
  for i = 1, C.ROWS do
    local r = CreateFrame("Button", nil, body)
    r:SetHeight(C.ROW_H); r:SetPoint("TOPLEFT", body, "TOPLEFT", C.INSET, -C.INSET - (i - 1) * C.ROW_H)
    r.alt = r:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(r.alt, 1, 1, 1, 0.05); r.alt:SetAllPoints(r)
    r.sel = r:CreateTexture(nil, "BORDER"); AFUI.SetColor(r.sel, 0.8, 0.62, 0.12, 0.28); r.sel:SetAllPoints(r); r.sel:Hide()
    K().row(r)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetWidth(16); r.icon:SetHeight(16)
    r.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    r.crown = r:CreateTexture(nil, "OVERLAY"); r.crown:SetWidth(11); r.crown:SetHeight(11); r.crown:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon"); r.crown:Hide()
    for _, c in ipairs(C.COLUMNS) do
      local t = fs(r, "GameFontHighlight"); t:SetHeight(14)
      if t.SetWordWrap then t:SetWordWrap(false) end
      r[c.key] = t
    end
    r.class:SetText("")
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, button)
      local m = self.m; if not m then return end
      state.selected = m.i
      if SetGuildRosterSelection then SetGuildRosterSelection(m.i) end
      C.Update()
      if C.RowAction(button) == "menu" and type(FriendsFrame_ShowDropdown) == "function" then FriendsFrame_ShowDropdown(m.name, m.online and 1 or nil) end
    end)
    r:SetScript("OnDoubleClick", function(self, button)
      if C.RowAction(button, true) == "whisper" and self.m and self.m.online and type(ChatFrame_SendTell) == "function" then ChatFrame_SendTell(self.m.name) end
    end)
    r:Hide()
    win.rrows[i] = r
  end
  win.rsb = rowsBar(body, body, function() return state.offset end, function(v) if v ~= state.offset then state.offset = v; C.Update() end end,
    function() return math.max(0, #roster - C.ROWS) end, C.ROWS)
  win.empty = fs(body, "GameFontNormal"); win.empty:SetPoint("TOP", body, "TOP", 0, -60); win.empty:SetText("No members to show."); win.empty:Hide()
end

local function updateRoster()
  local maxOff = math.max(0, #roster - C.ROWS)
  if state.offset > maxOff then state.offset = maxOff end
  win.rsb:Refresh()
  local cw = win.cw
  for i = 1, C.ROWS do
    local r, m = win.rrows[i], roster[state.offset + i]
    if not m then r:Hide() else
      r:Show(); r.m = m
      r.alt:SetAlpha(i % 2 == 0 and 1 or 0)
      if state.selected == m.i then r.sel:Show() else r.sel:Hide() end
      local cr, cg, cb = classColor(m.token)
      local dim = m.online and 1 or 0.5
      local coords = m.token and _G.CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[m.token]
      if coords then r.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4]); r.icon:Show() else r.icon:Hide() end
      r.icon:SetAlpha(dim)
      r.level:SetText(tostring(m.level or "")); r.level:SetTextColor(dim, dim, dim)
      C.Fit(r.name, m.name, cw.name - 22 - (m.rankIndex == 0 and 12 or 0)); r.name:SetTextColor(cr * dim, cg * dim, cb * dim)
      r.crown:ClearAllPoints()
      if m.rankIndex == 0 then r.crown:SetPoint("LEFT", r.name, "LEFT", math.min(r.name:GetStringWidth(), cw.name - 22) + 2, 0); r.crown:Show() else r.crown:Hide() end
      if m.online then C.Fit(r.zone, m.zone or "", cw.zone - 12); r.zone:SetTextColor(1, 1, 1)
      else r.zone:SetText(lastSeen(m.i)); r.zone:SetTextColor(0.5, 0.5, 0.5) end
      C.Fit(r.rank, m.rank or "", cw.rank - 12); r.rank:SetTextColor(dim, dim, dim)
      C.Fit(r.note, m.note or "", cw.note - 12); r.note:SetTextColor(dim, dim, dim)
    end
  end
  if #roster == 0 then win.empty:Show() else win.empty:Hide() end
end

---------------------------------------------------------------- info + log pages
local function panel(parent, title)
  local p = CreateFrame("Frame", nil, parent)
  box(p, "brown") -- the parchment-brown inset, the same bronze rim as every panel
  local band = p:CreateTexture(nil, "BORDER"); AFUI.SetColor(band, 0, 0, 0, 0.3); band:SetHeight(26)
  band:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1); band:SetPoint("TOPRIGHT", p, "TOPRIGHT", -1, -1) -- the dark title strip
  local rule = p:CreateTexture(nil, "BORDER"); AFUI.SetColor(rule, 0.1, 0.07, 0.03, 1); rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", band, "BOTTOMLEFT"); rule:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT")
  p.title = fs(p, "GameFontNormal"); p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -8); p.title:SetText(title)
  return p
end

local function buildInfo(host)
  local pn = win.p
  local lab = fs(host, "GameFontNormal"); lab:SetText("Info"); win.infoLabel = lab
  local mp = panel(host, "Message of the Day"); pn.motd = mp
  win.motdText = fs(mp); win.motdText:SetPoint("TOPLEFT", mp, "TOPLEFT", 10, -28); win.motdText:SetJustifyV("TOP")
  local me = CreateFrame("EditBox", nil, mp); me:SetHeight(24); me:SetPoint("TOPLEFT", mp, "TOPLEFT", 6, -26); me:SetAutoFocus(false); me:SetMaxLetters(128)
  me:SetFontObject(GameFontHighlight); me:SetTextInsets(6, 6, 0, 0); box(me, "dark", 0.5); me:Hide()
  me:SetScript("OnEnterPressed", function(self) if GuildSetMOTD then GuildSetMOTD(self:GetText()) end; self:Hide(); self:ClearFocus(); C.Update() end)
  me:SetScript("OnEscapePressed", function(self) self:Hide(); self:ClearFocus() end)
  me:SetScript("OnShow", function() if win and win.motdText then win.motdText:Hide() end end) -- the editor sits on the static text: show one or the other, never both
  me:SetScript("OnHide", function() if win and win.motdText then win.motdText:Show() end end)
  mp:EnableMouse(true)
  mp:SetScript("OnMouseUp", function() if canDo("CanEditMOTD") then me:SetText(GetGuildRosterMOTD and GetGuildRosterMOTD() or ""); me:Show(); me:SetFocus() end end)
  mp:SetScript("OnEnter", function(self) if canDo("CanEditMOTD") then GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Click to change the message of the day", 1, 1, 1); GameTooltip:Show() end end)
  mp:SetScript("OnLeave", function() GameTooltip:Hide() end)
  win.motdEdit = me
  local ip = panel(host, "Guild Information"); pn.ginfo = ip
  win.infoText = fs(ip); win.infoText:SetPoint("TOPLEFT", ip, "TOPLEFT", 10, -28); win.infoText:SetJustifyV("TOP")
  local ie = CreateFrame("EditBox", nil, ip); ie:SetMultiLine(true); ie:SetPoint("TOPLEFT", ip, "TOPLEFT", 6, -26); ie:SetAutoFocus(false); ie:SetMaxLetters(500)
  ie:SetFontObject(GameFontHighlight); ie:SetTextInsets(6, 6, 4, 4); box(ie, "dark", 0.5); ie:Hide()
  ie:SetScript("OnEscapePressed", function(self) self:ClearFocus(); C.Update() end)
  ie:SetScript("OnEditFocusLost", function(self) -- saved when the officer leaves the box (the client's Save button does the same call)
    if self:IsShown() and SetGuildInfoText and self:GetText() ~= (GetGuildInfoText and GetGuildInfoText() or "") then SetGuildInfoText(self:GetText()) end
  end)
  win.infoEdit = ie
end

local function buildLog(host)
  local lab = fs(host, "GameFontNormal"); lab:SetText("Guild Log"); win.logLabel = lab
  local pnl = CreateFrame("Frame", nil, host); box(pnl, "dark"); win.p.glog = pnl
  local log = CreateFrame("ScrollingMessageFrame", nil, pnl)
  log:SetFont(ARIAL_NARROW_FONT or STANDARD_TEXT_FONT or "Fonts/ARIALN.TTF", 14); log:SetJustifyH("LEFT"); log:SetMaxLines(200); log:SetFading(false)
  win.glog = log
  logBar(log, pnl)
end

local EVENTS = {
  invite = "%s invited %s to the guild.", join = "%s joined the guild.", promote = "%s promoted %s to %s.",
  demote = "%s demoted %s to %s.", remove = "%s removed %s from the guild.", quit = "%s has left the guild.",
}
function C.EventText(kind, p1, p2, rank)
  local f = EVENTS[kind]
  if not f then return nil end
  p1, p2 = p1 or "Unknown", p2 or "Unknown"
  if kind == "join" or kind == "quit" then return string.format(f, p1) end
  if kind == "promote" or kind == "demote" then return string.format(f, p1, p2, rank or "?") end
  return string.format(f, p1, p2)
end

local function updateLog()
  local log = win.glog
  log:Clear()
  local n = GetNumGuildEvents and GetNumGuildEvents() or 0
  local any = false
  for i = n, 1, -1 do -- newest first
    local kind, p1, p2, rank = GetGuildEventInfo(i)
    local t = C.EventText(kind, p1, p2, rank)
    if t then log:AddMessage(t); any = true end
  end
  if not any then log:AddMessage("|cff9d9d9dNo recent guild events.|r") end
  if log.ScrollToTop then log:ScrollToTop() end
end

---------------------------------------------------------------- update
function C.UpdateHeader()
  if not win then return end
  local total, online = collect()
  win.counts:SetText(C.Counts(online, total))
  local can = officerOK()
  local ch = win.channel
  ch.text:SetText(state.channel == "OFFICER" and can and "Officer" or "Guild")
  win.chatToggle:SetChecked(AFUI.GetSetting("chatGuildInWindow", false) and true or false)
  if win.chatToggle.SetHitRectInsets and win.chatToggle.label.GetStringWidth then win.chatToggle:SetHitRectInsets(0, -(win.chatToggle.label:GetStringWidth() + 4), 0, 0) end -- the label clicks too
  ch.text:SetTextColor(rgb(chatHex(state.channel == "OFFICER" and can and "OFFICER" or "GUILD")))
  return total, online
end

function C.Update()
  if not win then return end
  local inGuild = IsInGuild()
  win.guildHost:SetShown(inGuild); win.noGuild:SetShown(not inGuild)
  for _, b in ipairs(win.tabs) do b:SetShown(inGuild) end
  win.fold:SetShown(inGuild)
  P().chrome(win, inGuild and C.W or C.W_NONE, inGuild and C.H or C.H_NONE)
  win.title:SetText(inGuild and "Guild & Communities" or "Guild")
  if not inGuild then return end
  local total, online = C.UpdateHeader()
  local gname = GetGuildInfo("player")
  win.cardName:SetText(gname or ""); win.cardSub:SetText(online .. " online")
  win.invite:SetShown(state.tab ~= "info" and state.tab ~= "log"); win.invite[canDo("CanGuildInvite") and "Enable" or "Disable"](win.invite)
  win.viewLog:SetShown(state.tab == "info")
  for _, t in ipairs(C.TABS) do
    local b = win.tabByKey[t.key]
    b.afActive = state.tab == t.key
  end
  K().refreshTabs()
  win.chatHost:SetShown(state.tab == "chat"); win.rosterHost:SetShown(state.tab == "roster")
  win.infoHost:SetShown(state.tab == "info"); win.logHost:SetShown(state.tab == "log")
  win.channel:SetShown(state.tab == "chat"); win.chatToggle:SetShown(state.tab == "chat"); win.chatToggle.label:SetShown(state.tab == "chat"); win.showOffline:SetShown(state.tab == "roster")
  if state.tab ~= "chat" then C.CloseChannelMenu() end
  win.showOfflineLabel:SetShown(state.tab == "roster")
  if state.tab == "chat" then updateMembers()
  elseif state.tab == "roster" then updateRoster()
  elseif state.tab == "info" then
    local motd = GetGuildRosterMOTD and GetGuildRosterMOTD() or ""
    win.motdText:SetText(motd ~= "" and motd or "No message of the day.")
    local info = GetGuildInfoText and GetGuildInfoText() or ""
    local can = canDo("CanEditGuildInfo") and true or false
    win.infoText:SetText(info ~= "" and info or "No guild information set.")
    win.infoText:SetShown(not can)
    win.infoEdit:SetShown(can)
    if can and not win.infoEdit:HasFocus() then win.infoEdit:SetText(info) end
  else updateLog() end
end

function C.SetTab(key)
  if not win then return end
  state.tab = key
  if db() then db().guildCommTab = key end
  if key == "log" and QueryGuildEventLog then QueryGuildEventLog() end
  if key == "chat" then C.RefreshChat() end
  C.Update()
end

---------------------------------------------------------------- layout
-- The left column (guild card) folds away with the arrow button next to the X; the pages take the room.
function C.MainX(collapsed) return collapsed and 64 or (C.M + C.LEFT_W + C.G) end -- folded: clear of the portrait ring
function C.MainWidth(collapsed) return C.W - C.MainX(collapsed) - C.M end

-- Every panel's rectangle ({ x, y, w, h } in window coordinates, y down), derived from the constants at the top and nothing else. Pure: the specs check it.
-- One margin M to the frame, one gap G between panels; the tops of the pages' panels are on one line, so are their bottoms (the left column's too).
function C.Layout(collapsed)
  local M, G, W, H = C.M, C.G, C.W, C.H
  local mx = C.MainX(collapsed)
  local mw = W - mx - M
  local top, bottom = C.TOP + C.HEAD, H - M - C.STRIP_H - G
  local ch = bottom - top
  local logW = mw - C.MEM_W - G
  return {
    left = { x = M, y = C.TOP, w = C.LEFT_W, h = bottom - C.TOP },
    strip = { x = M, y = H - M - C.STRIP_H, w = W - 2 * M, h = C.STRIP_H },
    header = { x = mx, y = C.TOP, w = mw, h = C.HEAD },
    main = { x = mx, y = top, w = mw, h = ch },
    -- chat
    log = { x = mx, y = top, w = logW, h = ch - C.INPUT_H - G },
    input = { x = mx, y = bottom - C.INPUT_H, w = logW, h = C.INPUT_H },
    members = { x = mx + mw - C.MEM_W, y = top, w = C.MEM_W, h = ch },
    -- roster
    rhead = { x = mx, y = top, w = mw, h = C.HDR_H },
    rbody = { x = mx, y = top + C.HDR_H, w = mw, h = ch - C.HDR_H },
    -- info and log
    motd = { x = mx, y = top, w = mw, h = C.MOTD_H },
    ginfo = { x = mx, y = top + C.MOTD_H + G, w = mw, h = ch - C.MOTD_H - G },
    glog = { x = mx, y = top, w = mw, h = ch },
  }
end

-- The left column (CommunitiesList.xml CommunitiesListFrameTemplate; texcoords are the XML's, into the 256 x 1024 bluemenu-main sheet): navy gradient, a filigree at
-- the top and bottom, and above everything the gold-edged border (four corners, side strips of bluemenu-vert, top / bottom strips of bluemenu-goldborder-horiz).
-- 2.4.3 cannot load a 1024 px texture: flat navy there.
C.MENU = { -- name = { l, r, t, b } of bluemenu-main
  bg = { 0.00390625, 0.82421875, 0.18554688, 0.58984375 }, top = { 0.00390625, 0.7265625, 0.12988281, 0.18359375 }, bottom = { 0.26171875, 0.984375, 0.06542969, 0.11914063 },
  tl = { 0.00390625, 0.25390625, 0.00097656, 0.06347656 }, tr = { 0.51953125, 0.76953125, 0.00097656, 0.06347656 },
  bl = { 0.26171875, 0.51171875, 0.00097656, 0.06347656 }, br = { 0.51171875, 0.26171875, 0.00097656, 0.06347656 }, -- br is the bl piece mirrored
}
-- Texel sizes of the sheet pieces (bluemenu-main is 256 x 1024): every piece keeps its aspect. The navy background is cropped (never squeezed) to the column's
-- shape, the two filigrees scale uniformly to the column's width, the border strips tile along their length (bluemenu-vert 128 x 128, bluemenu-goldborder-horiz 64 x 128).
local function texels(c) return (c[2] - c[1]) * 256, (c[4] - c[3]) * 1024 end
function C.CropToAspect(c, w, h) -- the sub-rectangle of piece c that fills a w x h region at one scale: { l, r, t, b }
  local tw, th = texels(c)
  local s = math.max(w / tw, h / th)
  local uw, uh = w / s, h / s -- texels of the piece that fit
  local dl, dt = (tw - uw) / 2 / 256, (th - uh) / 2 / 1024
  return { c[1] + dl, c[2] - dl, c[3] + dt, c[4] - dt }
end
function C.Filigree(c, w) local tw, th = texels(c); return w, w * th / tw end -- the filigree's size at width w, native aspect
function C.LeftArt(left)
  if AFUI.IS_243 then
    local flat = left:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(flat, 0.045, 0.07, 0.115, 1); flat:SetAllPoints(left)
    return
  end
  local MAIN = GUILD .. "bluemenu-main"
  local function piece(parent, layer, file, c)
    local t = parent:CreateTexture(nil, layer); t:SetTexture(file); t:SetTexCoord(c[1], c[2], c[3], c[4]); return t
  end
  local colW, colH = C.LEFT_W - 4, C.Layout(false).left.h -- the background's region (the column less its 2 px side margins)
  local bg = piece(left, "BACKGROUND", MAIN, C.CropToAspect(C.MENU.bg, colW, colH)); bg:SetPoint("TOPLEFT", left, "TOPLEFT", 2, 0); bg:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -2, 0)
  local fw, fh = C.Filigree(C.MENU.top, C.LEFT_W - 24)
  local top = piece(left, "ARTWORK", MAIN, C.MENU.top); top:SetWidth(fw); top:SetHeight(fh); top:SetPoint("TOP", left, "TOP", 0, -8)
  local bot = piece(left, "ARTWORK", MAIN, C.MENU.bottom); bot:SetWidth(fw); bot:SetHeight(fh); bot:SetPoint("BOTTOM", left, "BOTTOM", 0, 6)
  local ov = CreateFrame("Frame", nil, left); ov:SetAllPoints(left); ov:SetFrameLevel(left:GetFrameLevel() + 4)
  local function corner(name, point, x, y)
    local t = piece(ov, "ARTWORK", MAIN, C.MENU[name]); t:SetWidth(64); t:SetHeight(64); t:SetPoint(point, ov, point, x, y); return t
  end
  local tl, tr, bl, br = corner("tl", "TOPLEFT", 3, 2), corner("tr", "TOPRIGHT", -1, 2), corner("bl", "BOTTOMLEFT", 3, 0), corner("br", "BOTTOMRIGHT", 0, 0)
  local VERT, HORIZ = GUILD .. "bluemenu-vert", GUILD .. "bluemenu-goldborder-horiz"
  local function strip(layer, file, c, horizontal) -- tiled along its length at native size, only the strip's own band across
    local t = ov:CreateTexture(nil, layer)
    t:SetTexture(file, horizontal and "REPEAT" or "CLAMP", horizontal and "CLAMP" or "REPEAT"); t:SetTexCoord(c[1], c[2], c[3], c[4])
    if horizontal and t.SetHorizTile then t:SetHorizTile(true) elseif t.SetVertTile then t:SetVertTile(true) end
    return t
  end
  local lb = strip("BORDER", VERT, { 0.0625, 0.3984375, 0, 1 }); lb:SetWidth(43); lb:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); lb:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
  local rb = strip("BORDER", VERT, { 0.4140625, 0.75, 0, 1 }); rb:SetWidth(43); rb:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT"); rb:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  local tb = strip("BORDER", HORIZ, { 0, 1, 0.0078125, 0.34375 }, true); tb:SetHeight(43); tb:SetPoint("TOPLEFT", tl, "TOPRIGHT"); tb:SetPoint("TOPRIGHT", tr, "TOPLEFT")
  local bb = strip("BORDER", HORIZ, { 0, 1, 0.359375, 0.6953125 }, true); bb:SetHeight(43); bb:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT"); bb:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
end

-- The portrait ring (Compat.lua: centre 25, -22 from the window's top left, opening radius 26.5): a dark round field with the banner's shield at its native aspect,
-- wholly inside the opening. (A 2.5.3 client has no guild tabard API for a real emblem; the shirt icon this used drew its own black corners and cut the picture.)
C.CREST = { cx = 25, cy = -22, w = 36, h = 33.5, field = { 0.05, 0.07, 0.12 }, back = { 0.14, 0.2, 0.36 }, edge = { 1, 0.82, 0.3 } } -- w x h keeps the shield sheet's 74 x 69
function C.Crest(f)
  local k = C.CREST
  f.afPortrait:Hide() -- the window's own picture sits under the left column's corner ornament, which would cut it: the crest has a frame above the column
  local cf = CreateFrame("Frame", nil, f); cf:SetAllPoints(f); cf:SetFrameLevel(f:GetFrameLevel() + 8) -- under the ring (+10), over the column (+5)
  local field = cf:CreateTexture(nil, "ARTWORK")
  AFUI.WindowPortrait(cf, field) -- the round opening, cut into strips like every window's portrait
  for _, st in ipairs(field.afStrips) do AFUI.SetColor(st, k.field[1], k.field[2], k.field[3], 1) end
  local function shield(name)
    local t = cf:CreateTexture(nil, "ARTWORK", nil, 3); AFUI.SetAtlas(t, name); t:SetWidth(k.w); t:SetHeight(k.h); t:SetPoint("CENTER", f, "TOPLEFT", k.cx, k.cy); return t
  end
  local back = shield("communities-guildbanner-background")
  back:SetVertexColor(k.back[1], k.back[2], k.back[3])
  local edge = shield("communities-guildbanner-border")
  edge:SetVertexColor(k.edge[1], k.edge[2], k.edge[3])
  f.afCrest = { frame = cf, field = field, back = back, edge = edge }
end

local function build()
  if win then return win end
  local Kt = K()
  local f = CreateFrame("Frame", "AFUIGuildCommFrame", UIParent)
  win = f
  f:SetFrameStrata("MEDIUM"); f:SetToplevel(true); f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true); f:Hide()
  f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -90) -- above the unit frames and the bars
  f.p = {} -- the page panels by name (C.ApplyLayout anchors each one)
  P().chrome(f, C.W, C.H)
  C.Crest(f)
  f.title = f.afLabels:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOP", f, "TOP", 0, -6); f.title:SetText("Guild & Communities")
  local close = CreateFrame("Button", nil, f); P().closeButton(close, f); close:SetScript("OnClick", function() f:Hide() end)
  local fold = CreateFrame("Button", nil, f); fold:SetWidth(28); fold:SetHeight(28); fold:SetPoint("TOPRIGHT", f, "TOPRIGHT", -29, 3); fold:SetFrameLevel(f:GetFrameLevel() + 30)
  AFUI.SetButtonAtlas(fold, { "redbutton-condense", "redbutton-condense-pressed", "redbutton-highlight", "redbutton-condense-disabled" })
  fold:SetScript("OnClick", function() C.SetCollapsed(not state.collapsed) end)
  fold:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(state.collapsed and "Show the guild list" or "Hide the guild list", 1, 1, 1); GameTooltip:Show() end)
  fold:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.fold = fold
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "AFUIGuildCommFrame") end

  local host = CreateFrame("Frame", nil, f); host:SetAllPoints(f); f.guildHost = host
  -- bottom strip: a panel like the others
  local strip = CreateFrame("Frame", nil, host); box(strip, "dark"); f.strip = strip
  -- left column: the guild card
  local left = CreateFrame("Frame", nil, host)
  C.LeftArt(left)
  f.left = left
  local card = CreateFrame("Button", nil, left); card:SetWidth(C.LEFT_W - 2); card:SetHeight(58); card:SetPoint("TOPLEFT", left, "TOPLEFT", 1, -50)
  card.bg = P().atlasTex(card, "BACKGROUND", "communities-nav-button-green-normal"); card.bg:SetAllPoints(card)
  card.shield = P().atlasTex(card, "ARTWORK", "communities-guildbanner-background", 38, 35.4); card.shield:SetPoint("LEFT", card, "LEFT", 8, 0)
  card.edge = P().atlasTex(card, "OVERLAY", "communities-guildbanner-border", 38, 35.4); card.edge:SetPoint("LEFT", card, "LEFT", 8, 0)
  f.cardName = fs(card, "GameFontHighlight"); f.cardName:SetPoint("LEFT", card, "LEFT", 54, 7); f.cardName:SetWidth(104)
  f.cardName:SetTextColor(0.3, 1, 0.3)
  f.cardSub = fs(card, "GameFontHighlightSmall"); f.cardSub:SetPoint("TOPLEFT", f.cardName, "BOTTOMLEFT", 0, -2); f.cardSub:SetTextColor(0.55, 0.85, 0.55)
  card:SetScript("OnClick", function() C.SetTab("chat") end)
  -- header strip of the main area (channel button / show offline, the count)
  local header = CreateFrame("Frame", nil, host); f.header = header; header:SetHeight(28)
  f.counts = fs(header, "GameFontNormalSmall"); f.counts:SetPoint("RIGHT", header, "RIGHT", -C.INSET, 0); f.counts:SetJustifyH("RIGHT")
  f.showOffline = CreateFrame("CheckButton", nil, header, "OptionsCheckButtonTemplate"); Kt.check(f.showOffline); f.showOffline:SetWidth(26); f.showOffline:SetHeight(26)
  f.showOffline:SetPoint("LEFT", header, "LEFT", 0, 0)
  f.showOfflineLabel = fs(header, "GameFontNormal"); f.showOfflineLabel:SetPoint("LEFT", f.showOffline, "RIGHT", 4, 0); f.showOfflineLabel:SetText("Show Offline Members")
  f.showOffline:SetScript("OnClick", function(self)
    if SetGuildRosterShowOffline then SetGuildRosterShowOffline(self:GetChecked() and true or false) end
    state.offset = 0
    local r = api("GuildRoster"); if r then r() end
    C.Update()
  end)
  -- pages
  local main = CreateFrame("Frame", nil, host); f.main = main
  for _, n in ipairs({ "chatHost", "rosterHost", "infoHost", "logHost" }) do
    local p = CreateFrame("Frame", nil, main); p:SetAllPoints(main); f[n] = p
  end
  buildChat(f.chatHost); buildRoster(f.rosterHost); buildInfo(f.infoHost); buildLog(f.logHost)
  -- bottom buttons, inside the strip with the same padding at both ends
  f.invite = redButton(host, "Invite Member", 150); f.invite:SetPoint("RIGHT", strip, "RIGHT", -(C.INSET + 2), 0)
  f.invite:SetScript("OnClick", function() if StaticPopup_Show then StaticPopup_Show("ADD_GUILDMEMBER") end end)
  f.viewLog = redButton(host, "View Log", 110); f.viewLog:SetPoint("LEFT", strip, "LEFT", C.INSET + 2, 0)
  f.viewLog:SetScript("OnClick", function() C.SetTab("log") end)
  -- side tabs
  f.tabs, f.tabByKey = {}, {}
  for i, t in ipairs(C.TABS) do
    local b = CreateFrame("Button", "AFUIGuildCommTab" .. i, f)
    Kt.sideTab(b, f, i, t.icon, t.tip)
    b:SetScript("OnClick", function() C.SetTab(t.key) end)
    f.tabs[i] = b; f.tabByKey[t.key] = b
  end
  -- not in a guild
  local ng = CreateFrame("Frame", nil, f); ng:SetAllPoints(f); f.noGuild = ng; ng:Hide()
  local t1 = fs(ng, "GameFontNormalLarge"); t1:SetPoint("TOP", ng, "TOP", 0, -70); t1:SetJustifyH("CENTER"); t1:SetText("You are not in a guild")
  local t2 = fs(ng, "GameFontHighlight"); t2:SetPoint("TOP", t1, "BOTTOM", 0, -14); t2:SetWidth(330); t2:SetJustifyH("CENTER")
  t2:SetText("Ask a guild officer for an invitation. The guild chat, roster and info appear here once you join.")
  C.SetCollapsed(false, true)
  f:SetScript("OnShow", function()
    if IsInGuild() then
      local r = api("GuildRoster"); if r then r() end
      if has("GetGuildRosterShowOffline") then f.showOffline:SetChecked(GetGuildRosterShowOffline() and true or false) end
      noteMotd(GetGuildRosterMOTD and GetGuildRosterMOTD() or "")
      C.RefreshChat()
    end
    C.Update()
  end)
  for _, e in ipairs({ "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "GUILD_MOTD", "GUILD_EVENT_LOG_UPDATE" }) do pcall(f.RegisterEvent, f, e) end
  f:SetScript("OnEvent", function(self) if self:IsShown() then C.Update() end end)
  f:HookScript("OnHide", function() C.CloseChannelMenu() end)
  return f
end

-- Puts every frame in its rectangle of C.Layout (left column shown or folded): the one place that anchors the window's panels.
function C.ApplyLayout()
  if not win then return end
  local L, p = C.Layout(state.collapsed), win.p
  local I, G = C.INSET, C.G
  place(win.left, L.left); place(win.strip, L.strip); place(win.header, L.header); place(win.main, L.main)
  -- header row: the channel field, the toggle after it, the count at the right edge
  win.channel:ClearAllPoints(); win.channel:SetPoint("LEFT", win.header, "LEFT", 0, 0)
  win.chatToggle:ClearAllPoints(); win.chatToggle:SetPoint("LEFT", win.channel, "RIGHT", G + 4, 0)
  -- chat
  place(p.log, L.log); sizeLog(win.log, p.log, L.log); place(p.input, L.input); place(p.members, L.members)
  local mrw = content(L.members).w
  for _, r in ipairs(win.mrows) do r:SetWidth(mrw) end
  -- roster
  place(p.rbody, L.rbody)
  local rw = content(L.rbody).w
  local cw = C.Columns(rw)
  win.cw = cw
  local x = L.rhead.x
  for i, h in ipairs(win.heads) do -- the heads run edge to edge over the panel: the first one covers the rim's inset, the last one the bar's strip
    local hx, hw = x, cw[h.col.key]
    if i == 1 then hw = hw + I; h.label:ClearAllPoints(); h.label:SetPoint("LEFT", h, "LEFT", 8 + I, 0) else h.label:ClearAllPoints(); h.label:SetPoint("LEFT", h, "LEFT", 8, 0) end
    if i == #win.heads then hw = L.rhead.x + L.rhead.w - hx end
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", win, "TOPLEFT", hx, -L.rhead.y); h:SetWidth(hw); h:SetHeight(L.rhead.h)
    x = x + hw
  end
  for _, r in ipairs(win.rrows) do
    r:SetWidth(rw)
    local cx = 0
    for _, c in ipairs(C.COLUMNS) do
      r[c.key]:ClearAllPoints(); r[c.key]:SetPoint("LEFT", r, "LEFT", cx + 8, 0); r[c.key]:SetWidth(cw[c.key] - 10)
      if c.key == "class" then r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT", r, "LEFT", cx + 14, 0) end
      cx = cx + cw[c.key]
    end
  end
  -- info and log
  win.infoLabel:ClearAllPoints(); win.infoLabel:SetPoint("LEFT", win, "TOPLEFT", L.header.x, -(L.header.y + L.header.h / 2))
  win.logLabel:ClearAllPoints(); win.logLabel:SetPoint("LEFT", win, "TOPLEFT", L.header.x, -(L.header.y + L.header.h / 2))
  place(p.motd, L.motd); place(p.ginfo, L.ginfo); place(p.glog, L.glog); sizeLog(win.glog, p.glog, L.glog)
  win.motdText:SetWidth(L.motd.w - 22); win.infoText:SetWidth(L.ginfo.w - 22)
  win.motdEdit:SetWidth(L.motd.w - 12); win.infoEdit:SetWidth(L.ginfo.w - 12); win.infoEdit:SetHeight(L.ginfo.h - 32)
end

function C.SetCollapsed(on, quiet)
  state.collapsed = on and true or false
  if not win then return end
  win.left:SetShown(not state.collapsed)
  C.ApplyLayout()
  if not quiet then C.RefreshChat(); C.Update() end
end
C.Relayout = function() C.SetCollapsed(state.collapsed) end

---------------------------------------------------------------- show / hide / toggle
function C.Open()
  build()
  if AFUI.GuildWindow and AFUI.GuildWindow.Hide then AFUI.GuildWindow.Hide() end -- one guild window at a time
  win:Show(); win:Raise()
  return true
end
function C.Hide() if win then win:Hide() end end
function C.IsShown() return win and win:IsShown() and true or false end
function C.Toggle()
  if C.IsShown() then C.Hide() else C.Open() end
end
function C.Frame() return win end

AFUI.RegisterModule("GuildCommunities", { OnLogin = function()
  setupChat()
  if IsInGuild and IsInGuild() then local r = api("GuildRoster"); if r then r() end end
end })
