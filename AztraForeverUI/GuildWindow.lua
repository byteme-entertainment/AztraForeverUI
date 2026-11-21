-- Forever's Guild window: its own window (G key / the Guild micro button / the Guild tab of the Social panel) in Forever's metal portrait frame:
-- guild name, member count, Message of the Day (click to edit), a sortable roster (status dot, class icon, class-coloured name, level, class, zone or
-- last seen, rank), a Show Offline filter, Guild Info and Guild Log pages, Add Member / Guild Control, and a member detail panel (notes, Promote /
-- Demote / Remove / Invite / Whisper). Without a guild it shows the "not in a guild" state. When the Social panel is open the window docks to its right
-- edge and follows it; otherwise it sits where the left panels sit. It is our own frame built on the client's guild API (GuildRoster,
-- GetGuildRosterInfo, SortGuildRoster, GuildSetMOTD, SetGuildInfoText, GuildPromote ...): the client's own GuildFrame page stays hidden and its Guild
-- Control popup (Blizzard_GuildControlUI) is opened by our button. Nothing here is protected.
-- Forever's code does not ship a guild frame in tools/ref (camelot's friendsframe has Contacts / Raid / Quick Join only, guilds went to Communities in
-- later builds); the look follows the Character / Professions / Social captures, the roster follows the old client's GuildFrame columns.
-- API names (verified): Gethe/wow-ui-source tag 2.5.3 Interface_TBC/FrameXML/FriendsFrame.lua (FRIEND_TAB_GUILD = 3, GUILDMEMBERS_TO_DISPLAY = 13,
-- InGuildCheck, GuildStatus_Update) and the 2.4.3 GuildFrame.lua roster API (GetGuildRosterInfo: name, rank, rankIndex, level, class, zone, note,
-- officernote, online, status, classFileName).
AFUI = AFUI or {}
local G = {}
AFUI.GuildWindow = G

---------------------------------------------------------------- data (pure; specs: tests/lua/guildwindow_spec.lua)
G.W, G.H, G.H_NONE = 430, 520, 270
G.ROSTER_W = 380
G.ROWS, G.ROW_H = 10, 28
G.ICON = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
G.COLUMNS = {
  { key = "name", label = "Name", w = 126 }, { key = "level", label = "Lvl", w = 30 }, { key = "class", label = "Class", w = 54 },
  { key = "zone", label = "Zone", w = 104 }, { key = "rank", label = "Rank", w = 66 },
}
-- Pages the client can feed: the roster always; Guild Info needs GetGuildInfoText, Guild Log the event log API. A page it cannot feed is not built.
function G.PageList(has)
  local out = { { "roster", "Roster" } }
  if has.info then out[#out + 1] = { "info", "Guild Info" } end
  if has.log then out[#out + 1] = { "log", "Guild Log" } end
  return out
end
-- n buttons of equal width across `total` px with `gap` between them (no hole at the end).
-- A roster row: left click selects, right click opens the player menu, a double click whispers (the client's guild list does the same).
function G.RowAction(button, double)
  if button == "RightButton" then return "menu" end
  return double and "whisper" or "select"
end
function G.SplitWidth(total, gap, n) return math.floor((total - gap * (n - 1)) / n) end

function G.Counts(n, online) return string.format("%d member%s, %d online", n, n == 1 and "" or "s", online) end

local function ago(n, unit) return n .. " " .. unit .. (n == 1 and "" or "s") end
-- GetGuildRosterLastOnline(index) -> years, months, days, hours
function G.LastOnline(y, m, d, h)
  if not y then return "Offline" end
  m, d, h = m or 0, d or 0, h or 0
  if y > 0 then return ago(y, "year") end
  if m > 0 then return ago(m, "month") end
  if d > 0 then return ago(d, "day") end
  if h > 0 then return ago(h, "hour") end
  return "< 1 hour"
end

-- Where the window goes: right of the Social panel when that is open, else where the client's left panels sit.
function G.Anchor(socialOpen)
  if socialOpen then return { "TOPLEFT", "FriendsFrame", "TOPRIGHT", AFUI.IS_243 and 2 or 62, 0 } end -- 2.5.3: clear of the side tabs (55 px)
  return { "TOPLEFT", "UIParent", "TOPLEFT", 16, -116 }
end

-- The G key while the window is alone and shown closes it; everything else shows (and focuses) it.
function G.Toggle(mode, shown)
  if mode == "alone" and shown then return "hide" end
  return "show"
end

local EVENTS = {
  invite = "%s invited %s to the guild.", join = "%s joined the guild.", promote = "%s promoted %s to %s.",
  demote = "%s demoted %s to %s.", remove = "%s removed %s from the guild.", quit = "%s has left the guild.",
}
-- One line of the guild log (GetGuildEventInfo: type, player1, player2, rank).
function G.EventText(kind, p1, p2, rank)
  local fmt = EVENTS[kind]
  if not fmt then return nil end
  p1, p2 = p1 or "Unknown", p2 or "Unknown"
  if kind == "join" or kind == "quit" then return string.format(fmt, p1) end
  if kind == "promote" or kind == "demote" then return string.format(fmt, p1, p2, rank or "?") end
  return string.format(fmt, p1, p2)
end

function G.StatusTexture(online, status)
  if not online then return "Interface\\FriendsFrame\\StatusIcon-Offline" end
  if status and status ~= "" then
    if status == _G.CHAT_FLAG_DND or string.find(status, "DND") or string.find(status, "Busy") then return "Interface\\FriendsFrame\\StatusIcon-DnD" end
    return "Interface\\FriendsFrame\\StatusIcon-Away"
  end
  return "Interface\\FriendsFrame\\StatusIcon-Online"
end

---------------------------------------------------------------- window
local K = AFUI.WinKit
local win, rows, state = nil, {}, { page = "roster", offset = 0, selected = nil, showOffline = true, mode = "docked" }
local list = {}

local function fs(parent, font, layer) local t = parent:CreateFontString(nil, layer or "OVERLAY", font or "GameFontHighlight"); t:SetJustifyH("LEFT"); return t end
local function P() return AFUI.Professions.Kit end
-- 2.5.3 moved some guild calls into C_GuildInfo (FriendsFrame.lua uses C_GuildInfo.GuildRoster, CanEditOfficerNote, CanViewOfficerNote and has no global GuildRoster)
local function api(fn) local f = _G[fn]; if type(f) ~= "function" and _G.C_GuildInfo then f = C_GuildInfo[fn] end; return type(f) == "function" and f or nil end
local function canDo(fn, ...) local f = api(fn); return f and f(...) end
local function has(fn) return api(fn) ~= nil end
local function setEn(b, on) if on then b:Enable() else b:Disable() end end

local function darkBox(f, a)
  for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1 }, { "TOPRIGHT", "BOTTOMRIGHT", 1 } }) do
    local t = f:CreateTexture(nil, "BORDER"); AFUI.SetColor(t, 0.45, 0.37, 0.2, 1); t:SetPoint(e[1], f); t:SetPoint(e[2], f)
    if e[3] then t:SetWidth(1) else t:SetHeight(1) end
  end
  local bg = f:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(bg, 0.02, 0.02, 0.02, a or 0.7); bg:SetAllPoints(f)
end

local function collect()
  list = {}
  if not IsInGuild() then return 0, 0 end
  local total = GetNumGuildMembers(true) or 0
  local online = 0
  for i = 1, total do
    local name, rank, rankIndex, level, class, zone, note, officer, on, status, token = GetGuildRosterInfo(i)
    if name then
      if on then online = online + 1 end
      if on or state.showOffline then
        list[#list + 1] = { i = i, name = name, rank = rank, rankIndex = rankIndex, level = level, class = class, zone = zone, note = note, officer = officer, online = on, status = status, token = token }
      end
    end
  end
  return total, online
end

local function lastSeen(i) -- `and` would cut the four values down to one
  if not GetGuildRosterLastOnline then return G.LastOnline(nil) end
  return G.LastOnline(GetGuildRosterLastOnline(i))
end

local function classColor(token)
  local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
  if c then return c.r, c.g, c.b end
  return 1, 0.82, 0
end

---------------------------------------------------------------- member detail panel
local function updateDetail()
  local d = win and win.detail
  if not d then return end
  local m
  for _, e in ipairs(list) do if e.i == state.selected then m = e end end
  if not m or state.page ~= "roster" or not win:IsShown() then d:Hide(); return end
  d:Show()
  d.name:SetText((m.name:gsub("%-.*$", ""))); d.name:SetTextColor(classColor(m.token))
  d.info:SetText("Level " .. tostring(m.level or "?") .. " " .. tostring(m.class or ""))
  d.rank:SetText("Rank: " .. tostring(m.rank or "?"))
  d.zone:SetText(m.online and ("Zone: " .. tostring(m.zone or "Unknown")) or ("Last seen: " .. lastSeen(m.i)))
  if not d.note:HasFocus() then d.note:SetText(m.note or ""); d.note:SetCursorPosition(0) end
  if canDo("CanEditPublicNote") then d.note:Enable() else d.note:Disable() end
  local canOff = canDo("CanViewOfficerNote")
  canOff = canOff and has("GuildRosterSetOfficerNote") and true or false
  d.officerLabel:SetShown(canOff); d.officer:SetShown(canOff)
  -- the buttons follow the last visible field: no hole where the officer note is not shown
  local base = canOff and -228 or -178
  d.promote:ClearAllPoints(); d.promote:SetPoint("TOPLEFT", d, "TOPLEFT", 14, base)
  d.demote:ClearAllPoints(); d.demote:SetPoint("TOPLEFT", d, "TOPLEFT", 120, base)
  d.invite:ClearAllPoints(); d.invite:SetPoint("TOPLEFT", d, "TOPLEFT", 14, base - 28)
  d.whisper:ClearAllPoints(); d.whisper:SetPoint("TOPLEFT", d, "TOPLEFT", 120, base - 28)
  d.remove:ClearAllPoints(); d.remove:SetPoint("TOPLEFT", d, "TOPLEFT", 14, base - 56)
  d:SetHeight(-base + 56 + 22 + 14)
  if canOff then if not d.officer:HasFocus() then d.officer:SetText(m.officer or ""); d.officer:SetCursorPosition(0) end if canDo("CanEditOfficerNote") then d.officer:Enable() else d.officer:Disable() end end
  local me = UnitName("player")
  local other = m.name ~= me
  setEn(d.promote, other and canDo("CanGuildPromote") and true or false)
  setEn(d.demote, other and canDo("CanGuildDemote") and true or false)
  setEn(d.remove, other and canDo("CanGuildRemove") and true or false)
  setEn(d.invite, other and m.online and true or false)
  setEn(d.whisper, other and m.online and true or false)
end

local function buildDetail(f)
  local d = CreateFrame("Frame", nil, f)
  d:SetWidth(230); d:SetHeight(320); d:SetPoint("TOPLEFT", f, "TOPRIGHT", 2, -28); d:Hide()
  K.panel(d)
  d.name = fs(d, "GameFontNormalLarge"); d.name:SetPoint("TOPLEFT", d, "TOPLEFT", 14, -14); d.name:SetWidth(200); d.name:SetJustifyH("LEFT")
  d.info = fs(d); d.info:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -6)
  d.rank = fs(d); d.rank:SetPoint("TOPLEFT", d.info, "BOTTOMLEFT", 0, -4)
  d.zone = fs(d); d.zone:SetPoint("TOPLEFT", d.rank, "BOTTOMLEFT", 0, -4); d.zone:SetWidth(200); d.zone:SetJustifyH("LEFT")
  local function edit(label, y, onEnter)
    local l = fs(d, "GameFontNormalSmall"); l:SetPoint("TOPLEFT", d, "TOPLEFT", 14, y); l:SetText(label)
    local e = CreateFrame("EditBox", nil, d); e:SetWidth(200); e:SetHeight(22); e:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -3)
    e:SetFontObject(GameFontHighlightSmall); e:SetAutoFocus(false); e:SetMaxLetters(31); e:SetTextInsets(6, 6, 0, 0)
    darkBox(e, 0.8)
    e:SetScript("OnEnterPressed", function(self) onEnter(self:GetText()); self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); updateDetail() end)
    return l, e
  end
  local _, n = edit("Public note", -108, function(t) if state.selected and GuildRosterSetPublicNote then GuildRosterSetPublicNote(state.selected, t) end end)
  d.note = n
  d.officerLabel, d.officer = edit("Officer note", -158, function(t) if state.selected and GuildRosterSetOfficerNote then GuildRosterSetOfficerNote(state.selected, t) end end)
  local function btn(label, x, y, fn)
    local b = CreateFrame("Button", nil, d, "UIPanelButtonTemplate"); b:SetText(label); K.button(b, 96)
    b:SetPoint("TOPLEFT", d, "TOPLEFT", x, y); b:SetScript("OnClick", fn); return b
  end
  local function sel() for _, e in ipairs(list) do if e.i == state.selected then return e end end end
  d.promote = btn("Promote", 14, -228, function() local m = sel(); if m then GuildPromote(m.name) end end)
  d.demote = btn("Demote", 120, -228, function() local m = sel(); if m then GuildDemote(m.name) end end)
  d.invite = btn("Invite", 14, -256, function() local m = sel(); if m then (C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit)(m.name) end end)
  d.whisper = btn("Whisper", 120, -256, function() local m = sel(); if m and ChatFrame_SendTell then ChatFrame_SendTell(m.name) end end)
  d.remove = btn("Remove", 14, -284, function() local m = sel(); if m then GuildUninvite(m.name) end end)
  d.remove:SetWidth(202)
  local x = CreateFrame("Button", nil, d); x:SetWidth(24); x:SetHeight(24); x:SetPoint("TOPRIGHT", d, "TOPRIGHT", -4, -4)
  P().closeButton(x, d); x:SetScript("OnClick", function() state.selected = nil; d:Hide() end)
  f.detail = d
end

---------------------------------------------------------------- pages
local function setPage(p)
  state.page = p
  win.rosterHost:SetShown(p == "roster"); win.infoHost:SetShown(p == "info"); win.logHost:SetShown(p == "log")
  for _, b in ipairs(win.pageButtons) do
    local on = b.page == p
    local t = b:GetFontString(); if t then t:SetFontObject(on and GameFontHighlight or GameFontNormal) end
    b:SetAlpha(on and 1 or 0.8)
  end
  if p == "log" and QueryGuildEventLog then QueryGuildEventLog() end
  G.Update()
end

local function updateLog()
  local n = GetNumGuildEvents and GetNumGuildEvents() or 0
  local lines = {}
  for i = n, math.max(1, n - 17), -1 do
    local kind, p1, p2, rank, y, mo, d, h = GetGuildEventInfo(i)
    local t = G.EventText(kind, p1, p2, rank)
    if t then lines[#lines + 1] = t end
  end
  win.logText:SetText(#lines > 0 and table.concat(lines, "\n") or "No recent guild events.")
end

local function updateRoster(total, online)
  local maxOff = math.max(0, #list - G.ROWS)
  if state.offset > maxOff then state.offset = maxOff end
  win.scroll:Refresh()
  for i = 1, G.ROWS do
    local r, m = rows[i], list[state.offset + i]
    if not m then r:Hide() else
      r:Show(); r.m = m
      r.alt:SetAlpha(i % 2 == 0 and 1 or 0)
      r.sel:SetShown(state.selected == m.i)
      r.dot:SetTexture(G.StatusTexture(m.online, m.status))
      local cr, cg, cb = classColor(m.token)
      local dim = m.online and 1 or 0.55
      local coords = m.token and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[m.token]
      if coords then r.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4]); r.icon:Show() else r.icon:Hide() end
      r.icon:SetAlpha(dim)
      r.name:SetText((m.name:gsub("%-.*$", ""))); r.name:SetTextColor(cr * dim, cg * dim, cb * dim)
      r.level:SetText(tostring(m.level or "")); r.level:SetTextColor(dim, dim, dim)
      r.class:SetText(m.class or ""); r.class:SetTextColor(cr * dim, cg * dim, cb * dim)
      r.zone:SetText(m.online and (m.zone or "") or lastSeen(m.i))
      r.zone:SetTextColor(m.online and 1 or 0.5, m.online and 0.82 or 0.5, m.online and 0 or 0.5)
      r.rank:SetText(m.rank or ""); r.rank:SetTextColor(0.75 * dim, 0.75 * dim, 0.75 * dim)
    end
  end
  win.empty:SetShown(#list == 0)
end

function G.Update()
  if not win then return end
  local inGuild = IsInGuild()
  win.guildHost:SetShown(inGuild); win.noGuild:SetShown(not inGuild)
  P().chrome(win, G.W, inGuild and G.H or G.H_NONE) -- the not-in-a-guild state is a short window, not an empty tall one
  if not inGuild then win.title:SetText("Guild"); updateDetail(); return end
  local gname, grank = GetGuildInfo("player")
  win.title:SetText("Guild")
  local total, online = collect()
  win.gname:SetText(gname or "")
  win.counts:SetText(G.Counts(total, online) .. (grank and ("   -   You are: " .. grank) or ""))
  local motd = GetGuildRosterMOTD and GetGuildRosterMOTD() or ""
  win.motd:SetText(motd ~= "" and motd or "No message of the day.")
  win.motd:SetTextColor(motd ~= "" and 1 or 0.5, motd ~= "" and 1 or 0.5, motd ~= "" and 1 or 0.5)
  setEn(win.add, canDo("CanGuildInvite") and true or false)
  if win.control then setEn(win.control, canDo("IsGuildLeader") and true or false) end
  if state.page == "roster" then updateRoster(total, online)
  elseif state.page == "info" then
    local t = GetGuildInfoText and GetGuildInfoText() or ""
    local can = canDo("CanEditGuildInfo")
    win.infoText:SetText(t ~= "" and t or "No guild information set.")
    win.infoText:SetShown(not can); win.infoEdit:SetShown(can); win.infoSave:SetShown(can)
    if can and not win.infoEdit:HasFocus() then win.infoEdit:SetText(t) end
  else updateLog() end
  updateDetail()
end

local function buildRoster(host)
  local col = 0
  win.heads = {}
  for _, c in ipairs(G.COLUMNS) do
    local h = CreateFrame("Button", nil, host)
    h:SetWidth(c.w); h:SetHeight(24); h:SetPoint("TOPLEFT", host, "TOPLEFT", col, 0)
    local bg = P().atlasTex(h, "BACKGROUND", "profession-tab-c60"); bg:SetAllPoints(h)
    local hl = P().atlasTex(h, "HIGHLIGHT", "profession-tab-glow-c60"); hl:SetAllPoints(h)
    local t = fs(h, "GameFontNormal"); t:SetPoint("LEFT", h, "LEFT", c == G.COLUMNS[1] and 46 or 6, 0); t:SetText(c.label)
    h:SetScript("OnClick", function() if SortGuildRoster then SortGuildRoster(c.key) end; G.Update() end)
    win.heads[#win.heads + 1] = h
    col = col + c.w
  end
  for i = 1, G.ROWS do
    local r = CreateFrame("Button", nil, host)
    r:SetWidth(G.ROSTER_W); r:SetHeight(G.ROW_H); r:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -26 - (i - 1) * G.ROW_H)
    r.alt = r:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(r.alt, 1, 1, 1, 0.05); r.alt:SetAllPoints(r)
    r.sel = r:CreateTexture(nil, "BORDER"); AFUI.SetColor(r.sel, 0.8, 0.62, 0.12, 0.28); r.sel:SetAllPoints(r); r.sel:Hide()
    K.row(r)
    r.dot = r:CreateTexture(nil, "ARTWORK"); r.dot:SetWidth(14); r.dot:SetHeight(14); r.dot:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetWidth(22); r.icon:SetHeight(22); r.icon:SetPoint("LEFT", r, "LEFT", 20, 0)
    r.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    local x = 0
    for j, c in ipairs(G.COLUMNS) do
      local t = fs(r, "GameFontHighlight"); t:SetJustifyH("LEFT")
      t:SetPoint("LEFT", r, "LEFT", x + (j == 1 and 46 or 6), 0); t:SetWidth(c.w - (j == 1 and 48 or 8)); t:SetHeight(14); if t.SetWordWrap then t:SetWordWrap(false) end
      r[c.key] = t
      x = x + c.w
    end
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, button)
      if not self.m then return end
      state.selected = self.m.i
      if SetGuildRosterSelection then SetGuildRosterSelection(self.m.i) end
      G.Update()
      if G.RowAction(button) == "menu" and type(FriendsFrame_ShowDropdown) == "function" then FriendsFrame_ShowDropdown(self.m.name, self.m.online and 1 or nil) end -- whisper / invite / ...
    end)
    r:SetScript("OnDoubleClick", function(self, button)
      if G.RowAction(button, true) == "whisper" and self.m and self.m.online and type(ChatFrame_SendTell) == "function" then ChatFrame_SendTell(self.m.name) end
    end)
    r:Hide()
    rows[i] = r
  end
  win.empty = fs(host, "GameFontNormal"); win.empty:SetPoint("TOP", host, "TOP", 0, -80); win.empty:SetText("No members to show."); win.empty:Hide()
  -- the shared scroll bar, flush with the rows (rows are the unit: it glides, the rows tick over)
  win.scroll = K.scrollbar(host, { get = function() return state.offset end, set = function(v) if v ~= state.offset then state.offset = v; G.Update() end end,
    max = function() return math.max(0, #list - G.ROWS) end, view = function() return G.ROWS end, step = 2, integer = true, eps = 0.01 },
    { parent = host, place = function(bar) bar:SetPoint("TOPLEFT", host, "TOPLEFT", G.ROSTER_W + 3, -26); bar:SetHeight(G.ROWS * G.ROW_H) end })
end

local function textBox(parent, w, h, multi)
  local e = CreateFrame("EditBox", nil, parent); e:SetWidth(w); e:SetHeight(h); e:SetFontObject(GameFontHighlight); e:SetAutoFocus(false)
  e:SetTextInsets(8, 8, 6, 6); if multi then e:SetMultiLine(true) end
  darkBox(e, 0.8)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return e
end

local function build()
  if win then return win end
  local f = CreateFrame("Frame", "AFUIGuildFrame", UIParent)
  win = f
  f:SetFrameStrata("MEDIUM"); f:SetToplevel(true); f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true); f:Hide()
  P().chrome(f, G.W, G.H)
  if AFUI.GuildCommunities and AFUI.GuildCommunities.Crest then AFUI.GuildCommunities.Crest(f) else f.afPortrait:SetTexture(G.ICON) end
  f.title = f.afLabels:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOP", f, "TOP", 0, -6)
  local close = CreateFrame("Button", nil, f); P().closeButton(close, f); close:SetScript("OnClick", function() f:Hide() end)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "AFUIGuildFrame") end

  -- in a guild
  local host = CreateFrame("Frame", nil, f); host:SetAllPoints(f); f.guildHost = host
  f.gname = fs(host, "GameFontNormalLarge"); f.gname:SetPoint("TOPLEFT", host, "TOPLEFT", 70, -34); f.gname:SetWidth(240); f.gname:SetJustifyH("LEFT")
  f.counts = fs(host, "GameFontHighlightSmall"); f.counts:SetPoint("TOPLEFT", f.gname, "BOTTOMLEFT", 0, -4)
  if has("SetGuildRosterShowOffline") then -- without the call the roster always lists everyone: no filter to show
  local off = CreateFrame("CheckButton", nil, host, "OptionsCheckButtonTemplate"); K.check(off); off:SetPoint("TOPRIGHT", host, "TOPRIGHT", -88, -34); off:SetChecked(true)
  local ol = fs(host, "GameFontNormalSmall"); ol:SetPoint("LEFT", off, "RIGHT", 2, 0); ol:SetText("Show offline")
  off:SetScript("OnClick", function(self)
    state.showOffline = self:GetChecked() and true or false; state.offset = 0
    if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end
    G.Update()
  end)
  end
  -- Message of the Day
  local motd = CreateFrame("Button", nil, host); motd:SetWidth(G.ROSTER_W + 16); motd:SetHeight(50); motd:SetPoint("TOPLEFT", host, "TOPLEFT", 14, -78); darkBox(motd, 0.55)
  local ml = fs(motd, "GameFontNormalSmall"); ml:SetPoint("TOPLEFT", motd, "TOPLEFT", 8, -6); ml:SetText("Message of the Day")
  f.motd = fs(motd); f.motd:SetPoint("TOPLEFT", ml, "BOTTOMLEFT", 0, -3); f.motd:SetWidth(G.ROSTER_W - 4); f.motd:SetJustifyH("LEFT"); f.motd:SetJustifyV("TOP")
  local me = textBox(motd, G.ROSTER_W, 24, false); me:SetPoint("TOPLEFT", motd, "TOPLEFT", 6, -20); me:SetMaxLetters(128); me:SetFrameLevel(motd:GetFrameLevel() + 3); me:Hide()
  me:SetScript("OnEnterPressed", function(self) if GuildSetMOTD then GuildSetMOTD(self:GetText()) end; self:Hide(); G.Update() end)
  me:SetScript("OnEscapePressed", function(self) self:Hide() end)
  motd:SetScript("OnClick", function() if canDo("CanEditMOTD") then me:SetText(GetGuildRosterMOTD and GetGuildRosterMOTD() or ""); me:Show(); me:SetFocus() end end)
  motd:SetScript("OnEnter", function(self) if canDo("CanEditMOTD") then GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Click to change the message of the day", 1, 1, 1); GameTooltip:Show() end end)
  motd:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- page buttons
  f.pageButtons = {}
  local pages = G.PageList({ info = has("GetGuildInfoText"), log = has("GetNumGuildEvents") and has("GetGuildEventInfo") })
  local pw = G.SplitWidth(G.ROSTER_W + 16, 6, #pages)
  for i, p in ipairs(pages) do
    local b = CreateFrame("Button", nil, host, "UIPanelButtonTemplate"); b:SetText(p[2]); K.button(b, pw); b.page = p[1]
    b:SetPoint("TOPLEFT", host, "TOPLEFT", 14 + (i - 1) * (pw + 6), -134)
    b:SetScript("OnClick", function() setPage(p[1]) end)
    f.pageButtons[i] = b
  end
  if #pages == 1 then f.pageButtons[1]:Hide(); f.rosterTop = -134 end -- only the roster: no lone tab, the roster moves up
  -- roster page
  f.rosterHost = CreateFrame("Frame", nil, host); f.rosterHost:SetPoint("TOPLEFT", host, "TOPLEFT", 16, f.rosterTop and (f.rosterTop - 2) or -168); f.rosterHost:SetWidth(G.ROSTER_W); f.rosterHost:SetHeight(G.ROWS * G.ROW_H + 28)
  buildRoster(f.rosterHost)
  -- info page
  f.infoHost = CreateFrame("Frame", nil, host); f.infoHost:SetPoint("TOPLEFT", host, "TOPLEFT", 16, -168); f.infoHost:SetWidth(G.ROSTER_W); f.infoHost:SetHeight(312); darkBox(f.infoHost, 0.45); f.infoHost:Hide()
  f.infoText = fs(f.infoHost); f.infoText:SetPoint("TOPLEFT", f.infoHost, "TOPLEFT", 10, -10); f.infoText:SetWidth(G.ROSTER_W - 20); f.infoText:SetJustifyH("LEFT"); f.infoText:SetJustifyV("TOP")
  f.infoEdit = textBox(f.infoHost, G.ROSTER_W - 12, 262, true); f.infoEdit:SetPoint("TOPLEFT", f.infoHost, "TOPLEFT", 6, -6); f.infoEdit:SetMaxLetters(500); f.infoEdit:Hide()
  f.infoSave = CreateFrame("Button", nil, f.infoHost, "UIPanelButtonTemplate"); f.infoSave:SetText("Save"); K.button(f.infoSave, 96); f.infoSave:SetPoint("TOPLEFT", f.infoHost, "TOPLEFT", 6, -280); f.infoSave:Hide()
  f.infoSave:SetScript("OnClick", function() if SetGuildInfoText then SetGuildInfoText(f.infoEdit:GetText()) end; f.infoEdit:ClearFocus() end)
  -- log page
  f.logHost = CreateFrame("Frame", nil, host); f.logHost:SetPoint("TOPLEFT", host, "TOPLEFT", 16, -168); f.logHost:SetWidth(G.ROSTER_W); f.logHost:SetHeight(312); darkBox(f.logHost, 0.45); f.logHost:Hide()
  f.logText = fs(f.logHost); f.logText:SetPoint("TOPLEFT", f.logHost, "TOPLEFT", 10, -10); f.logText:SetWidth(G.ROSTER_W - 20); f.logText:SetJustifyH("LEFT"); f.logText:SetJustifyV("TOP"); f.logText:SetSpacing(4)
  -- bottom buttons
  local hasControl = _G.GuildControlPopupFrame ~= nil or (GetAddOnInfo and GetAddOnInfo("Blizzard_GuildControlUI") ~= nil)
  local bw = G.SplitWidth(G.ROSTER_W + 16, 6, hasControl and 2 or 1)
  f.add = CreateFrame("Button", nil, host, "UIPanelButtonTemplate"); f.add:SetText("Add Member"); K.button(f.add, bw); f.add:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 14, 14)
  f.add:SetScript("OnClick", function() if StaticPopup_Show then StaticPopup_Show("ADD_GUILDMEMBER") end end)
  if hasControl then
    f.control = CreateFrame("Button", nil, host, "UIPanelButtonTemplate"); f.control:SetText("Guild Control"); K.button(f.control, bw); f.control:SetPoint("LEFT", f.add, "RIGHT", 6, 0)
    f.control:SetScript("OnClick", function()
      if not _G.GuildControlPopupFrame and LoadAddOn then LoadAddOn("Blizzard_GuildControlUI") end
      local p = _G.GuildControlPopupFrame
      if p then if p:IsShown() then p:Hide() else p:Show() end end
    end)
  end
  buildDetail(f)
  -- not in a guild
  local ng = CreateFrame("Frame", nil, f); ng:SetAllPoints(f); f.noGuild = ng; ng:Hide()
  local ic = ng:CreateTexture(nil, "ARTWORK"); ic:SetWidth(72); ic:SetHeight(72); ic:SetPoint("TOP", ng, "TOP", 0, -56); ic:SetTexture(G.ICON); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local t1 = fs(ng, "GameFontNormalLarge"); t1:SetPoint("TOP", ic, "BOTTOM", 0, -16); t1:SetJustifyH("CENTER"); t1:SetText("You are not in a guild")
  local t2 = fs(ng, "GameFontHighlight"); t2:SetPoint("TOP", t1, "BOTTOM", 0, -12); t2:SetWidth(320); t2:SetJustifyH("CENTER"); t2:SetText("Ask a guild officer for an invitation, or find a guild through the Who list and the Looking For Group tool.")
  f:SetScript("OnShow", function() if IsInGuild() then if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end; local r = api("GuildRoster"); if r then r() end end; setPage(state.page) end)
  for _, e in ipairs({ "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "GUILD_MOTD", "GUILD_EVENT_LOG_UPDATE" }) do pcall(f.RegisterEvent, f, e) end
  f:SetScript("OnEvent", function(self) if self:IsShown() then G.Update() end end)
  return f
end

---------------------------------------------------------------- show / hide / dock
local function socialOpen() return _G.FriendsFrame and _G.FriendsFrame:IsShown() end

function G.Reanchor()
  if not win then return end
  local a = G.Anchor(socialOpen() and true or false)
  win:ClearAllPoints(); win:SetPoint(a[1], _G[a[2]] or UIParent, a[3], a[4], a[5])
end

-- mode: "alone" (the G key opened it with no Social panel) or "docked" (Social is open). Returns whether it is shown afterwards.
function G.Open(mode)
  build()
  if AFUI.GuildCommunities and AFUI.GuildCommunities.Hide then AFUI.GuildCommunities.Hide() end -- one guild window at a time (J has its own)
  state.mode = mode
  if G.Toggle(mode, win:IsShown()) == "hide" then win:Hide(); return false end
  G.Reanchor(); win:Show(); win:Raise()
  return true
end

function G.Select(i) build(); state.selected = i; G.Update() end
function G.SetPage(p) build(); setPage(p) end
function G.Hide() if win then win:Hide() end end
function G.IsShown() return win and win:IsShown() end

local function setup()
  local S = AFUI.SocialFrame
  local f = _G.FriendsFrame
  if S and S.HookGuild then S.HookGuild(G) end
  if f then
    f:HookScript("OnShow", function() if win and win:IsShown() then G.Reanchor() end end)
    f:HookScript("OnHide", function() if win and win:IsShown() then G.Reanchor() end end)
  end
end
function G.Setup() AFUI.RunOutOfCombat(setup) end
AFUI.RegisterModule("GuildWindow", { OnLogin = G.Setup })
