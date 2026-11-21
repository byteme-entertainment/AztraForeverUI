-- Forever's "Map & Quest Log" window has no stand-alone quest log: the quest list is a 333 u column on the right of the map window (docs/forever-ref/video-notes/
-- worldmap.md, questlog.md, frames 262-270 of the capture, Mat's capture forever-map-duskwood.png; QuestMapFrame of blizzard_uipanels_game/mainline/questmapframe.xml).
-- This file builds that column on the map window of WorldMap.lua: a search box ("Search Quest Log") + "Quests: n/25" + the settings cog on the window's Rock,
-- under them the dark stone body in its bronze frame: the zone headers as collapsible bars (gold + / -), the quests below them as "[level] Title" in the difficulty
-- colour with their wrapped objectives ("- ...") and the track checkbox at the right, and the thin scroll bar with its arrows at the far right.
-- The L key and the micro menu's Quest Log button open the map with the panel; Blizzard's QuestLogFrame is never shown.
-- Every Blizzard behaviour that survives stays the client's: headers collapse through Expand / CollapseQuestHeader, the tracker through Add / RemoveQuestWatch,
-- abandon and share through the client's own popups. There is no detail pane in Forever's panel, so the quest text is a tooltip on the row.
-- Client API, 2.5.3 (Gethe/wow-ui-source tag 2.5.3 Interface_TBC/FrameXML/QuestLogFrame.lua): GetNumQuestLogEntries() -> numEntries, numQuests;
-- GetQuestLogTitle(i) -> title, level, questTag, isHeader, isCollapsed, isComplete, frequency, questID; GetNumQuestLeaderBoards(i) and
-- GetQuestLogLeaderBoard(j, i) -> text, type, finished; IsQuestWatched / AddQuestWatch / RemoveQuestWatch(i); Expand / CollapseQuestHeader(i) (0 = all);
-- SelectQuestLogEntry(i); MAX_QUESTLOG_QUESTS 25, MAX_WATCHABLE_QUESTS 5; ToggleQuestLog(); frames QuestLogFrame (a UI panel, 2.5.3 shows it with ShowUIPanel).
AFUI = AFUI or {}
local Q = {}
AFUI.QuestLog = Q

---------------------------------------------------------------- geometry (pure; specs: tests/lua/questlog_spec.lua)
-- Row heights from Mat's capture (1 u = 1.406 px): the header bars are 22 u (QuestLogHeaderTemplate), a quest title line 23 u with its top padding, an objective
-- line 12 u; headers are 6 u apart, a quest block has 4 u of air under its last line. Quest and objective rows that wrap are taller (Q.Heights' measure).
Q.ROW = { header = 22, quest = 23, obj = 12 }
Q.AFTER = { header = 6, quest = 0, obj = 0 }
Q.BLOCK = 4
Q.TOP = 29 -- the search row above the body, from the panel's top
Q.PAD = { l = 11, r = 11, top = 6 } -- the list's insets inside the body

-- "[15] ", "[15+] " (elite), "[15D] " (dungeon), "[15R] " (raid), "[15G] " (group), "[15P] " (PvP)
local TAGS = { Elite = "+", Dungeon = "D", Raid = "R", Group = "G", PvP = "P" }
function Q.LevelText(level, tag)
  return "[" .. (level or 0) .. (TAGS[tag] or "") .. "] "
end

-- entries (Q.Read): { index, title, level, tag, isHeader, collapsed, complete, watched, objectives = { { text, done } } }.
-- Rows: header { kind = "header", index, title, collapsed } / quest { kind = "quest", index, title, level, tag, watched, complete } / obj { kind = "obj", text, done }.
-- With a search text the quests whose title contains it (any case) stay, with their header; headers never hide quests then.
function Q.Rows(entries, filter)
  local out, f = {}, filter and string.lower(filter) or ""
  local head, quests = nil, {}
  local function flush()
    if head and (f == "" or #quests > 0) then out[#out + 1] = head end
    for _, e in ipairs(quests) do
      out[#out + 1] = { kind = "quest", index = e.index, questID = e.questID, title = e.title, level = e.level, tag = e.tag, watched = e.watched, complete = e.complete }
      for _, o in ipairs(e.objectives or {}) do out[#out + 1] = { kind = "obj", text = o.text, done = o.done } end
    end
    head, quests = nil, {}
  end
  for _, e in ipairs(entries) do
    if e.isHeader then
      flush()
      head = { kind = "header", index = e.index, title = e.title, collapsed = e.collapsed }
    elseif f == "" or string.find(string.lower(e.title or ""), f, 1, true) then
      quests[#quests + 1] = e
    end
  end
  flush()
  return out
end

-- Top offset of every row and the total height of the list. `measure(row)` answers the height of a wrapped row (nil: the row's fixed one).
function Q.Heights(rows, measure)
  local tops, y = {}, 0
  for i, r in ipairs(rows) do
    tops[i] = y
    local last = r.kind ~= "header" and not (rows[i + 1] and rows[i + 1].kind == "obj") -- the end of a quest's block
    y = y + math.max(Q.ROW[r.kind], measure and measure(r) or 0) + Q.AFTER[r.kind] + (last and Q.BLOCK or 0)
  end
  return tops, y
end

-- GetQuestLogTitle(i) of 2.5.3: title, level, questTag, isHeader, isCollapsed, isComplete, frequency, questID. `api` is injectable for the spec.
function Q.Read(api)
  api = api or _G
  local out = {}
  local n = api.GetNumQuestLogEntries and api.GetNumQuestLogEntries() or 0
  for i = 1, n do
    local title, level, tag, isHeader, isCollapsed, isComplete, _, questID = api.GetQuestLogTitle(i)
    if title then
      local e = { index = i, questID = questID, title = title, level = level, tag = tag, isHeader = isHeader and true or false, collapsed = isCollapsed and true or false, complete = isComplete }
      if not e.isHeader then
        e.watched = api.IsQuestWatched and api.IsQuestWatched(i) and true or false
        e.objectives = {}
        for j = 1, api.GetNumQuestLeaderBoards and api.GetNumQuestLeaderBoards(i) or 0 do
          local text, _, done = api.GetQuestLogLeaderBoard(j, i)
          if text then e.objectives[#e.objectives + 1] = { text = text, done = done and true or false } end
        end
      end
      out[#out + 1] = e
    end
  end
  return out
end

-- The client numbers only the VISIBLE rows (the quests of a collapsed zone have no index), so the watched quests of a collapsed zone are invisible to Q.Read.
-- ReadAll expands every header, reads, and collapses the same headers again bottom-up (indexes above a header never move); Q.scanning stops the events
-- the expand / collapse raise from scanning again, and the result is cached while what is visible (+ the client's watch count) is unchanged.
function Q.ReadAll(api)
  api = api or _G
  local vis, collapsed, any = Q.Read(api), {}, false
  for _, e in ipairs(vis) do if e.isHeader and e.collapsed then collapsed[e.title] = true; any = true end end
  if not any or Q.scanning or not (api.ExpandQuestHeader and api.CollapseQuestHeader) then return vis end
  local sig = {}
  for _, e in ipairs(vis) do sig[#sig + 1] = (e.title or "") .. (e.watched and "*" or "") .. (e.collapsed and "-" or "") end
  sig = table.concat(sig, "|") .. "#" .. (api.GetNumQuestWatches and api.GetNumQuestWatches() or 0)
  if Q.scanSig == sig and Q.scanCache then return Q.scanCache end
  Q.scanning = true
  local ok, full = pcall(function()
    api.ExpandQuestHeader(0)
    local all = Q.Read(api)
    for i = #all, 1, -1 do if all[i].isHeader and collapsed[all[i].title] then api.CollapseQuestHeader(i) end end
    return all
  end)
  Q.scanning = false
  if not ok then return vis end
  Q.scanSig, Q.scanCache = sig, full
  return full
end

-- The log index of a quest id now (a row's index goes stale when the log changed since the last refresh); `fallback` when the id is not in the log.
function Q.IndexOf(questID, fallback, api)
  api = api or _G
  if questID then
    for i = 1, api.GetNumQuestLogEntries and api.GetNumQuestLogEntries() or 0 do
      local _, _, _, isHeader, _, _, _, id = api.GetQuestLogTitle(i)
      if not isHeader and id == questID then return i end
    end
  end
  return fallback
end

-- "Quests: 39/40": the label gold, the numbers white (red over the cap).
function Q.CountText(n, max)
  return string.format("Quests: %s%d/%d|r", n > max and "|cffff2020" or "|cffffffff", n, max)
end

local K = AFUI.WinKit
local panel, rows, content, scroll, bar, search, count, hint
local pool = {}
local expandedForSearch = false

local function difficulty(level)
  local f = _G.GetQuestDifficultyColor or _G.GetDifficultyColor
  local c = f and f(level or 0)
  if c then
    local r, g, b = c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1
    if r > 0.99 and g > 0.99 and b < 0.01 then g = 0.82 end -- the "standard" yellow is the gold of Forever's quest titles (1, 0.82, 0)
    return r, g, b
  end
  return 1, 1, 1
end

---------------------------------------------------------------- actions
local function questieLoaded() return _G.Questie ~= nil or _G.QuestieLoader ~= nil end
Q.QuestieLoaded = questieLoaded

-- The tick: the client's own watch calls with the quest LOG INDEX (never the id). Questie hooks Add / RemoveQuestWatch (and replaces IsQuestWatched), so with
-- Questie the tracker and its map icons follow. The client's limit (MAX_WATCHABLE_QUESTS: 5 in TBC, 25 later) is read from the client; Questie manages its own
-- list, so there the result is checked after the call instead of before. A refused tick shows the client's message and the box goes back (Refresh repaints it).
function Q.Track(index, questID)
  index = Q.IndexOf(questID, index)
  local function refused()
    UIErrorsFrame:AddMessage(string.format(QUEST_WATCH_TOO_MANY or "You may only track %d quests.", MAX_WATCHABLE_QUESTS or 5), 1, 0.1, 0.1, 1)
  end
  if IsQuestWatched(index) then RemoveQuestWatch(index)
  elseif not questieLoaded() and GetNumQuestWatches and GetNumQuestWatches() >= (MAX_WATCHABLE_QUESTS or 5) then refused()
  else
    AddQuestWatch(index)
    if not IsQuestWatched(index) then refused() end
  end
  if QuestWatch_Update and not InCombatLockdown() then QuestWatch_Update() end -- tainted call: never in combat
  Q.Refresh()
  if AFUI.MapQuestPins then AFUI.MapQuestPins.Refresh() end -- the map's quest points follow the tick at once
end

function Q.ToggleHeader(index, collapsed)
  if collapsed then ExpandQuestHeader(index) else CollapseQuestHeader(index) end
  Q.Refresh()
end

function Q.ClearSearch()
  if search then search:SetText(""); search:ClearFocus() end
end

local function menuFor(row)
  SelectQuestLogEntry(row.index)
  local items = { { text = row.title, title = true } }
  items[#items + 1] = { text = ABANDON_QUEST or "Abandon Quest", func = function()
    SelectQuestLogEntry(row.index); SetAbandonQuest()
    local t = GetAbandonQuestItems and GetAbandonQuestItems()
    if t then StaticPopup_Show("ABANDON_QUEST_WITH_ITEMS", GetAbandonQuestName(), t) else StaticPopup_Show("ABANDON_QUEST", GetAbandonQuestName()) end
  end }
  if GetQuestLogPushable and GetQuestLogPushable() then
    items[#items + 1] = { text = SHARE_QUEST or "Share Quest", func = function() SelectQuestLogEntry(row.index); QuestLogPushQuest() end }
  end
  return items
end

local function onClick(self, button)
  local r = self.row
  if not r then return end
  if r.kind == "header" then Q.ToggleHeader(r.index, r.collapsed); return end
  if r.kind ~= "quest" then return end
  if IsShiftKeyDown() then
    local link = GetQuestLink and GetQuestLink(r.index)
    if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
    return
  end
  if button == "RightButton" and AFUI.EditModeWidgets then AFUI.EditModeWidgets.OpenMenu(self, menuFor(r), 140)
  elseif AFUI.MapQuestPins then AFUI.MapQuestPins.Select(r.questID, r.index)
  else SelectQuestLogEntry(r.index) end
end

local function onEnter(self)
  local r = self.row
  if not r or r.kind ~= "quest" then return end
  Q.quiet = true; SelectQuestLogEntry(r.index); Q.quiet = nil -- the selection raises QUEST_LOG_UPDATE: no list rebuild under the mouse
  local desc, objectives = GetQuestLogQuestText()
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText(r.title, 1, 1, 1)
  if objectives and objectives ~= "" then GameTooltip:AddLine(objectives, 1, 0.82, 0, 1) end
  if desc and desc ~= "" then GameTooltip:AddLine(desc, 0.8, 0.8, 0.8, 1) end
  GameTooltip:AddLine("Right-click: abandon / share. Shift-click: link in chat.", 0.5, 0.5, 0.5, 1)
  GameTooltip:Show()
end

---------------------------------------------------------------- rows
local TEXT_W = 205 -- the width of a wrapped title / objective (QuestLogObjectiveTemplate's text is 205 u)
local HEADER_FONT = _G.Game15Font_Shadow and "Game15Font_Shadow" or "GameFontNormalLarge"

-- the checkbox: questlog-icon-ticksquare, the yellow tick when watched (QuestLogTrackCheckboxTemplate)
local function checkbox(cb)
  cb:SetNormalTexture(""); cb:SetPushedTexture(""); cb:SetDisabledTexture(""); cb:SetHighlightTexture("")
  AFUI.SetButtonAtlas(cb, { "questlog-icon-ticksquare", "questlog-icon-ticksquare", "questlog-icon-ticksquare", "questlog-icon-ticksquare" }, 0.4)
  -- the tick is our own texture, shown by Q.Refresh from the watch state: the client's checked texture can come out empty on a skinned CheckButton
  cb.tick = cb:CreateTexture(nil, "OVERLAY")
  AFUI.SetAtlas(cb.tick, "questlog-icon-checkmark-yellow")
  cb.tick:SetWidth(17); cb.tick:SetHeight(14); cb.tick:SetPoint("CENTER", cb, "CENTER", 1, 1); cb.tick:Hide()
  local e = AFUI_ATLAS and AFUI_ATLAS["questlog-icon-checkmark-yellow"]
  if e then
    cb:SetCheckedTexture(e[1])
    local t = cb:GetCheckedTexture()
    if t then t:SetTexCoord(e[4], e[5], e[6], e[7]); t:SetWidth(e[2]); t:SetHeight(e[3]); t:ClearAllPoints(); t:SetPoint("CENTER", cb, "CENTER", 1, 1) end
  end
end

-- The header bar: common-button-list-collapseExpand cut in three (UiTextureAtlasElementSliceData: 18 u left and right caps, the middle stretched).
local function bar3(b)
  local e = AFUI_ATLAS and AFUI_ATLAS["common-button-list-collapseexpand"]
  local parts = {}
  if e then
    local cap = 18
    local du = (e[5] - e[4]) * cap / e[2]
    local l, m, r = b:CreateTexture(nil, "BACKGROUND"), b:CreateTexture(nil, "BACKGROUND"), b:CreateTexture(nil, "BACKGROUND")
    for _, t in ipairs({ l, m, r }) do t:SetTexture(e[1]) end
    l:SetTexCoord(e[4], e[4] + du, e[6], e[7]); l:SetWidth(cap); l:SetPoint("TOPLEFT", b, "TOPLEFT"); l:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT")
    r:SetTexCoord(e[5] - du, e[5], e[6], e[7]); r:SetWidth(cap); r:SetPoint("TOPRIGHT", b, "TOPRIGHT"); r:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
    m:SetTexCoord(e[4] + du, e[5] - du, e[6], e[7]); m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    parts = { l, m, r }
  end
  return {
    Show = function() for _, t in ipairs(parts) do t:Show() end end,
    Hide = function() for _, t in ipairs(parts) do t:Hide() end end,
  }
end

AFUI.ListBar = bar3 -- the Friends list's section header draws the same bar (SocialFrame.lua)

local function newRow(i)
  local P = AFUI.Professions.Kit
  local b = CreateFrame("Button", nil, content)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.bar = bar3(b)
  b.sign = P.atlasTex(b, "OVERLAY", "common-button-list-plus-c60", 13, 13); b.sign:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  AFUI.SetButtonAtlas(b, { nil, nil, "common-button-list-collapseexpand" }, 0.4)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.text:SetJustifyH("LEFT"); b.text:SetJustifyV("TOP")
  b.dash = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); b.dash:SetJustifyH("LEFT"); b.dash:SetText("-")
  b.check = CreateFrame("CheckButton", nil, b)
  b.check:SetWidth(14); b.check:SetHeight(14); b.check:SetPoint("TOPRIGHT", b, "TOPRIGHT", -4, -8)
  checkbox(b.check)
  b.check:SetScript("OnClick", function(self) if b.row then Q.Track(b.row.index, b.row.questID) end end)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", onEnter)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pool[i] = b
  return b
end

-- Sets the row's look and answers its height (a title or objective that wraps is taller than its line).
local function paintRow(b, r)
  b.row = r
  b.text:ClearAllPoints(); b.dash:ClearAllPoints()
  local h = Q.ROW[r.kind]
  if r.kind == "header" then
    b.bar.Show(); b.sign:Show(); b.check:Hide(); b.dash:Hide(); b:EnableMouse(true)
    AFUI.SetAtlas(b.sign, r.collapsed and "common-button-list-plus-c60" or "common-button-list-minus-c60")
    b.sign:SetWidth(13); b.sign:SetHeight(r.collapsed and 13 or 4)
    b.text:SetFontObject(_G[HEADER_FONT]); b.text:SetJustifyV("MIDDLE")
    b.text:SetPoint("LEFT", b, "LEFT", 8, 0); b.text:SetPoint("RIGHT", b, "RIGHT", -26, 0)
    b.text:SetText(r.title)
    b.text:SetTextColor(0.56, 0.54, 0.5) -- Forever's zone bars are dim grey for every zone (also the one of the map shown), measured from Mat's capture
  elseif r.kind == "quest" then
    b.bar.Hide(); b.sign:Hide(); b.dash:Hide(); b:EnableMouse(true)
    b.check:Show(); b.check:SetChecked(r.watched); if r.watched then b.check.tick:Show() else b.check.tick:Hide() end
    b.text:SetFontObject(GameFontNormal); b.text:SetJustifyV("TOP")
    b.text:SetPoint("TOPLEFT", b, "TOPLEFT", 24, -8); b.text:SetWidth(TEXT_W)
    b.text:SetText(Q.LevelText(r.level, r.tag) .. r.title)
    b.text:SetTextColor(difficulty(r.level))
    h = math.max(h, 8 + (b.text:GetStringHeight() or 14) + 1)
  else
    b.bar.Hide(); b.sign:Hide(); b.check:Hide(); b:EnableMouse(false)
    b.dash:Show(); b.dash:SetPoint("TOPLEFT", b, "TOPLEFT", 24, 0)
    b.text:SetFontObject(GameFontHighlight); b.text:SetJustifyV("TOP")
    b.text:SetPoint("TOPLEFT", b, "TOPLEFT", 35, 0); b.text:SetWidth(TEXT_W)
    b.text:SetText(r.text)
    if r.done then b.text:SetTextColor(0.6, 0.6, 0.6); b.dash:SetTextColor(0.6, 0.6, 0.6) else b.text:SetTextColor(0.9, 0.9, 0.9); b.dash:SetTextColor(0.9, 0.9, 0.9) end
    h = math.max(h, b.text:GetStringHeight() or 12)
  end
  r.h = h
  return h
end

function Q.Refresh()
  if not panel or not panel:IsShown() then return end
  local text = search:GetText() or ""
  rows = Q.Rows(Q.Read(), text)
  for i, r in ipairs(rows) do paintRow(pool[i] or newRow(i), r) end
  local tops, total = Q.Heights(rows, function(r) return r.h end)
  content:SetHeight(math.max(total + Q.PAD.top, 1))
  for i, r in ipairs(rows) do
    local b = pool[i]
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -tops[i]); b:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -tops[i])
    b:SetHeight(r.h)
    b:Show()
  end
  for i = #rows + 1, #pool do pool[i].row = nil; pool[i]:Hide() end
  local _, n = GetNumQuestLogEntries()
  count:SetText(Q.CountText(n or 0, MAX_QUESTLOG_QUESTS or 25))
  if #rows == 0 then hint:SetText(text ~= "" and "No quest matches." or "You have no quests."); hint:Show() else hint:Hide() end
  local want, followed = scroll:GetVerticalScroll(), Q.follow
  if Q.follow then -- the map changed: bring the zone's header to the top once (the player's own scrolling is left alone afterwards)
    Q.follow = false
    for i, r in ipairs(rows) do if r.kind == "header" and r.title == Q.zone then want = tops[i]; break end end
  end
  bar:Refresh() -- the range changed: clamp the offset and the thumb
  if followed then bar:ScrollTo(want) end -- glides to the zone's header
end

-- The zone header follows the map shown: gold, and scrolled to. Only the list's look changes; no header is expanded, collapsed or clicked.
function Q.SetZone(name)
  if name == Q.zone then return end
  Q.zone, Q.follow = name, true
  Q.Refresh()
end
local function mapName(id)
  local info = id and _G.C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
  return info and info.name
end

---------------------------------------------------------------- the panel
-- The search / count boxes: the client's search border art (16 / 224 / 16 texels wide, 40 high) fitted to the box.
local function boxBorder(f)
  local P = AFUI.Professions.Kit
  local l = P.atlasTex(f, "BACKGROUND", "common-search-border-left-c60"); l:SetPoint("TOPLEFT", f, "TOPLEFT"); l:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT"); l:SetWidth(8)
  local r = P.atlasTex(f, "BACKGROUND", "common-search-border-right-c60"); r:SetPoint("TOPRIGHT", f, "TOPRIGHT"); r:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT"); r:SetWidth(8)
  local m = P.atlasTex(f, "BACKGROUND", "common-search-border-middle-c60"); m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
end

local function build(win)
  local P = AFUI.Professions.Kit
  local W = AFUI.WORLDMAP
  local base = win:GetFrameLevel()
  -- QuestMapFrame: TOPRIGHT / BOTTOMRIGHT 3 from the window's edge, 333 wide, its top level with the navbar's
  panel = CreateFrame("Frame", "AFUI_QuestPanel", win)
  panel:SetFrameLevel(base + 8)
  panel:SetWidth(W.PANEL_W)
  panel:SetPoint("TOPRIGHT", win, "TOPRIGHT", -3, -W.NAV.t)
  panel:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -3, 3)
  panel:EnableMouse(true)

  -- search row (on the window's Rock)
  search = CreateFrame("EditBox", "AFUI_QuestSearch", panel)
  search:SetAutoFocus(false); search:SetFontObject(GameFontHighlightSmall); search:SetMaxLetters(60)
  search:SetHeight(18); search:SetWidth(201); search:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -3)
  boxBorder(search)
  search:SetTextInsets(24, 8, 0, 0)
  local glass = P.atlasTex(search, "OVERLAY", "common-search-magnifyingglass", 12, 12); glass:SetPoint("LEFT", search, "LEFT", 7, 0)
  local ph = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); ph:SetPoint("LEFT", search, "LEFT", 24, 0); ph:SetText("Search Quest Log")
  search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  search:SetScript("OnEditFocusGained", function() ph:Hide() end)
  search:SetScript("OnEditFocusLost", function(self) if (self:GetText() or "") == "" then ph:Show() end end)
  search:SetScript("OnTextChanged", function(self)
    local t = self:GetText() or ""
    if t ~= "" and not expandedForSearch then expandedForSearch = true; ExpandQuestHeader(0) end -- the client hides the quests of collapsed headers
    if t == "" then expandedForSearch = false end
    if t ~= "" then ph:Hide() elseif not self:HasFocus() then ph:Show() end
    Q.Refresh()
  end)

  local box = CreateFrame("Frame", nil, panel)
  box:SetWidth(100); box:SetHeight(18); box:SetPoint("TOPLEFT", search, "TOPRIGHT", 4, 0)
  boxBorder(box)
  count = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  count:SetPoint("RIGHT", box, "RIGHT", -7, 0); count:SetJustifyH("RIGHT")

  -- the settings cog (UIPanelIconDropdownButtonTemplate): the client's own expand / collapse of every header
  local cog = CreateFrame("Button", nil, panel)
  cog:SetWidth(15); cog:SetHeight(16); cog:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -7, -3)
  AFUI.SetButtonAtlas(cog, { "questlog-icon-setting", "questlog-icon-setting", "questlog-icon-setting" }, 0.4)
  cog:SetScript("OnClick", function(self)
    if not AFUI.EditModeWidgets then return end
    AFUI.EditModeWidgets.OpenMenu(self, {
      { text = "Expand All", func = function() ExpandQuestHeader(0); Q.Refresh() end },
      { text = "Collapse All", func = function() CollapseQuestHeader(0); Q.Refresh() end },
    }, 120)
  end)

  -- the body: the stone background in its bronze frame (QuestLogBorderFrameTemplate: -3, +7 / +3, -6 around it)
  local body = CreateFrame("Frame", nil, panel)
  body:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -Q.TOP); body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -22, 0)
  local stone = body:CreateTexture(nil, "BACKGROUND"); AFUI.SetAtlas(stone, "questlog-main-background"); stone:SetAllPoints(body)
  local frame = CreateFrame("Frame", nil, body)
  frame:SetFrameLevel(body:GetFrameLevel() + 6)
  frame:SetPoint("TOPLEFT", body, "TOPLEFT", -3, 7); frame:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 3, -6)
  local shade = frame:CreateTexture(nil, "ARTWORK"); AFUI.SetAtlas(shade, "questlog-frame-gradient-bottom"); shade:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 4); shade:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 4); shade:SetHeight(66)
  AFUI.NineSlice(frame, "OVERLAY", "questlog-frame", 22)
  local fil = frame:CreateTexture(nil, "OVERLAY"); AFUI.SetAtlas(fil, "questlog-frame-filigree", true); fil:SetPoint("TOP", frame, "TOP", 0, 1)

  scroll = CreateFrame("ScrollFrame", "AFUI_QuestScroll", body)
  scroll:SetPoint("TOPLEFT", body, "TOPLEFT", Q.PAD.l, -Q.PAD.top); scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -Q.PAD.r, 6)
  content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(W.PANEL_W - 22 - Q.PAD.l - Q.PAD.r); content:SetHeight(1)
  content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  scroll:SetScrollChild(content)
  scroll:EnableMouseWheel(true)

  hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  hint:SetPoint("TOP", body, "TOP", 0, -40)

  -- the shared scroll bar (arrows, track, thumb, wheel, glide), flush with the body in the 22 u column at its right
  bar = AFUI.WinKit.scrollbar(scroll, {
    get = function() return scroll:GetVerticalScroll() end, set = function(v) scroll:SetVerticalScroll(v) end,
    max = function() return math.max(content:GetHeight() - scroll:GetHeight(), 0) end, view = function() return scroll:GetHeight() end, step = 40,
  }, { parent = panel, fit = body, place = function(b) b:SetPoint("TOPLEFT", body, "TOPRIGHT", 3, 0); b:SetPoint("BOTTOMLEFT", body, "BOTTOMRIGHT", 3, 0) end })
  Q.bar = bar

  panel:SetScript("OnShow", Q.Refresh)
  return panel
end

local function show(on)
  if not panel then return end
  if on then panel:Show(); Q.Refresh() else panel:Hide() end
end

---------------------------------------------------------------- the L key and the Quest Log button
local function mapShown() return _G.WorldMapFrame and WorldMapFrame:IsShown() end
local function setOpenFlag() if AztraForeverUICharDB then AztraForeverUICharDB.questPanelOpen = true end end

-- The real frames decide, never a saved flag: the panel counts as open only while its frame is actually shown on a shown map.
local function panelShown() return _G.AFUI_QuestPanel and _G.AFUI_QuestPanel:IsShown() and true or false end

-- Show the map with the quest panel (nothing toggles off).
function Q.Show()
  setOpenFlag()
  -- the maximized map has no quest panel: asking for the quest log brings the windowed layout back
  if AztraForeverUICharDB and AztraForeverUICharDB.worldMapMaximized and AFUI.WorldMapSetMaximized then AFUI.WorldMapSetMaximized(false) end
  if not mapShown() and ToggleWorldMap then ToggleWorldMap() end
  -- whatever the saved flags or a stale layout said, the panel frame itself must end up shown
  if mapShown() and _G.AFUI_QuestPanel and not panelShown() and AFUI.WorldMapSetPanel then AFUI.WorldMapSetPanel(true) end
end

-- L: the map with the panel opens; pressed again it closes. With the map open and the panel hidden (folded away, maximized) it shows the panel instead.
function Q.IsOpen() return mapShown() and (not _G.AFUI_QuestPanel or panelShown()) or false end
function Q.Toggle()
  if Q.IsOpen() then ToggleWorldMap(); return end
  Q.Show()
end

-- The L key goes straight to Q.Toggle through an override binding: ToggleQuestLog would show QuestLogFrame with ShowUIPanel, whose panel manager can close
-- the map again in the same press (it treats the map and the log as rival panels). /afui qlog prints the state when a press still fails.
local qbtn = CreateFrame("Button", "AFUI_QuestLogToggle", UIParent)
qbtn:SetScript("OnClick", function() Q.Toggle() end)
local qOwner = CreateFrame("Frame")
function Q.BindKeys()
  AFUI.RunOutOfCombat(function()
    ClearOverrideBindings(qOwner)
    if not GetBindingKey then return end
    for _, k in ipairs({ GetBindingKey("TOGGLEQUESTLOG") }) do SetOverrideBindingClick(qOwner, false, k, "AFUI_QuestLogToggle") end
  end)
end
AFUI.On("UPDATE_BINDINGS", Q.BindKeys)

-- /afui qlog: one line per fact, "qlog: ..." in chat; returns the lines.
function Q.Diag()
  local function sh(f) return f and (f:IsShown() and "shown" or "hidden") or "missing" end
  local db = AztraForeverUICharDB or {}
  local out = {
    "L=" .. tostring(GetBindingAction and GetBindingAction("L") or "?") .. " TOGGLEQUESTLOG keys=" .. tostring(GetBindingKey and table.concat({ GetBindingKey("TOGGLEQUESTLOG") }, ",") or "?"),
    "QuestLogFrame=" .. sh(_G.QuestLogFrame) .. " WorldMapFrame=" .. sh(_G.WorldMapFrame) .. " AFUI_QuestPanel=" .. sh(_G.AFUI_QuestPanel),
    "saved questPanelOpen=" .. tostring(db.questPanelOpen) .. " worldMapMaximized=" .. tostring(db.worldMapMaximized),
    "WorldMapPanelOpen=" .. tostring(AFUI.WorldMapPanelOpen()) .. " WorldMapPanelVisible=" .. tostring(AFUI.WorldMapPanelVisible()) .. " Q.IsOpen=" .. tostring(Q.IsOpen()),
  }
  for _, l in ipairs(out) do AFUI.Print("qlog: " .. l) end
  return out
end
AFUI.Slash.Register("qlog", Q.Diag, "print the quest log / map state (paste it when L misbehaves)", "/afui qlog")

-- The ticks follow the client's watch state whoever changed it: the log's events, the watch hooks (shift-click in the log, Blizzard's tracker, our tracker,
-- Questie), the login / zoning events and Questie's late start (ADDON_LOADED; Questie swaps IsQuestWatched after the login).
local syncHooked
function Q.SyncEvents()
  if syncHooked then return end
  syncHooked = true
  local function refresh() if not (Q.scanning or Q.quiet) then Q.Refresh() end end -- not for the events our own header scan / hover selection raise
  for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
    "UNIT_QUEST_LOG_CHANGED", "ADDON_LOADED", "PLAYER_ENTERING_WORLD" }) do AFUI.On(ev, refresh) end
  AFUI.On("PLAYER_ENTERING_WORLD", function() if _G.C_Timer and C_Timer.After then C_Timer.After(3, refresh) end end)
  for _, fn in ipairs({ "AddQuestWatch", "RemoveQuestWatch" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, refresh) end
  end
end

local done
local function setup()
  if done then return end
  local win = AFUI.WorldMapWindow
  if not win then return end -- WorldMap.lua sets it up first (login, or ADDON_LOADED of Blizzard_WorldMap)
  done = true
  build(win)
  table.insert(AFUI.WorldMapPanelHooks, show)
  if AFUI.MapChangedHooks then table.insert(AFUI.MapChangedHooks, function(id) Q.SetZone(mapName(id)) end) end
  show(AFUI.WorldMapPanelOpen())
  AFUI.WorldMapPanelShow(AFUI.WorldMapPanelOpen())
  Q.SyncEvents()
end
Q.Setup = setup

local hooked
local function hookLog()
  if hooked then return end
  hooked = true
  -- nothing of Blizzard's is replaced (taint): ToggleQuestLog runs, the frame it shows is sent to the map at once
  local f = _G.QuestLogFrame
  if f then f:HookScript("OnShow", function() if f:IsShown() then HideUIPanel(f); Q.Toggle() end end) end
end

function Q.Setup()
  hookLog()
  Q.BindKeys()
  AFUI.RunOutOfCombat(function() if AFUI.SetupWorldMap then AFUI.SetupWorldMap() end; setup() end)
end
AFUI.RegisterModule("QuestLog", { OnLogin = Q.Setup })
AFUI.On("ADDON_LOADED", function(_, addon) if addon == "Blizzard_WorldMap" then AFUI.RunOutOfCombat(setup) end end)
