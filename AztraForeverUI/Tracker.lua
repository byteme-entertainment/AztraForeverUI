-- Forever's objective tracker, built on the client's quest watch list (TBC has no ObjectiveTracker: 2.4.3 and 2.5.3 keep a QuestWatchFrame
-- of QuestWatchLine1..n that QuestWatch_Update fills, Interface/FrameXML/QuestLogFrame.lua). Blizzard's frame keeps running and stays
-- transparent (nothing of it is replaced or tainted); ours reads the same list after every QuestWatch_Update:
--   GetNumQuestWatches(), GetQuestIndexForWatch(i), GetQuestLogTitle(index) -> title, level, tag, isHeader, collapsed, isComplete, ...,
--   GetNumQuestLeaderBoards(index), GetQuestLogLeaderBoard(j, index) -> text, type, finished, GetQuestLogQuestText() -> description, objectives,
--   RemoveQuestWatch(index), QuestWatch_Update(); events QUEST_LOG_UPDATE, QUEST_WATCH_UPDATE.
-- Look (docs/forever-ref/video2/mat-shots/forever-objective-tracker-micromenu.png, 1.40625 px per unit): a 270 wide column, the "All Objectives" bar
-- with the red minimise button, the "Quests" bar with the gold - / + button, gold "[17] Title (Dungeon)" lines, white "- 10/20 Item" objectives,
-- finished ones grey with a green check, the quest text when a quest has no objectives.
local T = { WIDTH = 270, BOX_H = 160 }
AFUI.Tracker = T

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
-- Measured on the capture (units): bars, text column, line pitch 15.7 (12 + 3.7), 6.3 between quests.
local C = { headH = 36, secTop = 41, secH = 27, firstTop = 7, indent = 31, objIndent = 42, textW = 232, pitch = 15.7, blockGap = 6.3,
  titleSize = 12, bodySize = 12, headSize = 14, margin = 12, lineH = 12.2, zoneH = 18, barH = 7, barGap = 3 }
T.C = C
local GOLD, TITLE, BODY, DONE = { 1, 0.82, 0 }, { 0.75, 0.61, 0 }, { 0.8, 0.8, 0.8 }, { 0.6, 0.6, 0.6 }

local box = CreateFrame("Frame", "AFUI_ObjectiveTracker", UIParent) -- the Edit Mode system: a fixed box, the column hangs from its top
box:SetWidth(T.WIDTH); box:SetHeight(T.BOX_H)
box:SetFrameStrata("LOW")
box:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -122, -287) -- Presets.lua owns the real default (under the minimap, left of the right bars)
T.frame = box

---------------------------------------------------------------- pure helpers (specs)
-- GetQuestLogLeaderBoard text is "Deviate Hide: 10/20" on TBC, Forever shows "10/20 Deviate Hide".
function T.Objective(text)
  text = text or ""
  local name, count = text:match("^(.-):%s*(%-?%d+/%d+)$")
  if name and name ~= "" then return count .. " " .. name end
  return text
end

-- The third GetQuestLogTitle value is the tag string on 2.4.3 ("Elite", "Dungeon", ...); a group size (number) on later builds.
function T.Tag(raw, questID)
  local info = questID and _G.C_QuestLog and C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
  if type(info) == "table" and info.tagName then return info.tagName end
  if type(raw) == "string" and raw ~= "" then return raw end
  if type(raw) == "number" and raw > 1 then return raw >= 10 and "Raid" or raw >= 5 and "Dungeon" or "Group" end
end

-- "[17] Title (Dungeon)", "[24+] Title (Elite)": the "+" marks an elite.
function T.Title(title, level, tag)
  local out = title or ""
  if level and level > 0 then out = "[" .. level .. (tag == (_G.ELITE or "Elite") and "+" or "") .. "] " .. out end
  if tag then out = out .. " (" .. tag .. ")" end
  return out
end

-- A percentage objective ("Escort progress: 45%", or the client's progress-bar type) -> 0..100, else nil.
function T.Percent(text)
  local p = tonumber((text or ""):match("(%d+)%%"))
  return p and math.min(100, p) or nil
end

-- The zone header a log entry sits under (Forever 1.11 groups the tracker by zone).
local function zoneOf(index)
  for k = index - 1, 1, -1 do
    local title, _, _, isHeader = GetQuestLogTitle(k)
    if isHeader then return title end
  end
end

-- Zone groups in drawing order: the zone you stand in first, the others as they come; in a zone the quest selected in the log (the one you
-- are working on) first. With `zones` off: one group without a header. Pure: `here` is the current zone name, `selected` a log index.
function T.Group(entries, zones, here, selected)
  local groups, byZone = {}, {}
  for _, e in ipairs(entries) do
    local z = zones and e.zone or nil
    local g = byZone[z or 1]
    if not g then g = { zone = z, entries = {} }; byZone[z or 1] = g; groups[#groups + 1] = g end
    if selected and e.index == selected then table.insert(g.entries, 1, e) else g.entries[#g.entries + 1] = e end
  end
  if here then
    for i, g in ipairs(groups) do
      if i > 1 and g.zone == here then table.remove(groups, i); table.insert(groups, 1, g); break end
    end
  end
  return groups
end

-- Reads the client's watch list: { { index, title, lines = { { text, done, pct } }, desc, zone }, ... }. `describe(index)` supplies the quest text.
function T.Collect(describe)
  local out = {}
  local n = GetNumQuestWatches and GetNumQuestWatches() or 0
  for w = 1, n do
    local index = GetQuestIndexForWatch and GetQuestIndexForWatch(w)
    if index then
      local title, level, raw, isHeader, _, complete, _, questID = GetQuestLogTitle(index)
      if title and not isHeader then
        local e = { index = index, title = T.Title(title, level, T.Tag(raw, questID)), name = title, lines = {}, complete = complete and true or false, questID = questID, zone = zoneOf(index) }
        for j = 1, GetNumQuestLeaderBoards(index) or 0 do
          local text, kind, finished = GetQuestLogLeaderBoard(j, index)
          if text and text ~= "" then e.lines[#e.lines + 1] = { text = T.Objective(text), done = finished and true or false, pct = T.Percent(text) } end
        end
        if #e.lines == 0 and describe then e.desc = describe(index, title) end
        out[#out + 1] = e
      end
    end
  end
  return out
end

---------------------------------------------------------------- saved state (per character)
local function store()
  local d = _G.AztraForeverUICharDB
  if type(d) ~= "table" then return T end -- before the saved variables exist: lives on T for this session
  if type(d.tracker) ~= "table" then d.tracker = {} end
  return d.tracker
end
function T.IsCollapsed(which) return store()[which] and true or false end
function T.SetCollapsed(which, on) store()[which] = on and true or nil; T.Refresh() end
-- A zone header's fold, remembered by zone name in the same table (zones.<name> = true).
function T.ZoneCollapsed(zone) local z = store().zones; return z and z[zone] and true or false end
function T.SetZoneCollapsed(zone, on)
  local s = store()
  s.zones = s.zones or {}
  s.zones[zone] = on and true or nil
  T.Refresh()
end

---------------------------------------------------------------- drawing
local function Font(fs, size, color)
  fs:SetFont(FONT, size, "")
  fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
  if color then fs:SetTextColor(color[1], color[2], color[3]) end
  fs:SetJustifyH("LEFT")
end

-- A wide atlas drawn at `w` x `h` from its tiles (Media/Atlas.lua splits art wider than a texture page).
local function Bar(name, y, h)
  local tiles = AFUI_ATLAS_TILES and AFUI_ATLAS_TILES[name] or { name }
  local total = 0
  for _, t in ipairs(tiles) do total = total + AFUI_ATLAS[t][2] end
  local x, set = 0, {}
  for _, t in ipairs(tiles) do
    local tex = box:CreateTexture(nil, "BACKGROUND")
    local w = AFUI_ATLAS[t][2] * T.WIDTH / total
    AFUI.SetAtlas(tex, t)
    tex:SetWidth(w); tex:SetHeight(h)
    tex:SetPoint("TOPLEFT", box, "TOPLEFT", x, -y)
    x = x + w; set[#set + 1] = tex
  end
  return set
end
local function Show(set, on) for _, t in ipairs(set) do if on then t:Show() else t:Hide() end end end

local headBar = Bar("ui-questtracker-primary-objective-header-c60-2x", 0, C.headH)
local secBar = Bar("ui-questtracker-secondary-objective-header-c60-2x", C.secTop, C.secH)

local headText = box:CreateFontString(nil, "OVERLAY")
Font(headText, C.headSize, GOLD)
headText:SetPoint("LEFT", box, "TOPLEFT", 18, -C.headH / 2 + 1); headText:SetText(OBJECTIVES_TRACKER_LABEL or "All Objectives")
local secText = box:CreateFontString(nil, "OVERLAY")
Font(secText, C.headSize, GOLD)
secText:SetPoint("LEFT", box, "TOPLEFT", 18, -(C.secTop + C.secH / 2) + 3); secText:SetText(QUESTS_LABEL or "Quests")

local function ArtButton(size, x, y, normal, pushed, onClick)
  local b = CreateFrame("Button", nil, box)
  b:SetWidth(size); b:SetHeight(size)
  b:SetPoint("CENTER", box, "TOPLEFT", x, -y)
  b.normalArt, b.pushedArt = normal, pushed
  b:SetScript("OnClick", onClick)
  return b
end
function T.PaintButton(b, normal, pushed)
  AFUI.SetButtonAtlas(b, { normal, pushed, normal }, 0.35)
  if b.GetHighlightTexture and b:GetHighlightTexture() then b:GetHighlightTexture():SetBlendMode("ADD") end
end
local allButton = ArtButton(18, T.WIDTH - 10, C.headH / 2, nil, nil, function() T.SetCollapsed("all", not T.IsCollapsed("all")) end)
local secButton = ArtButton(16, T.WIDTH - 8, C.secTop + C.secH / 2 - 1, nil, nil, function() T.SetCollapsed("quests", not T.IsCollapsed("quests")) end)
T.allButton, T.secButton = allButton, secButton

-- One line of the client's font, measured on a probe: wrapped text is counted in whole lines of it, so nothing overlaps whatever
-- line height the client uses. The line pitch of the capture (15.7) is kept by adjusting the gap under each line.
local probe = box:CreateFontString(nil, "OVERLAY")
Font(probe, C.bodySize); probe:SetText("Ag"); probe:Hide()
function T.Natural()
  local one = probe:GetStringHeight()
  return one and one > 0 and one or C.lineH
end
function T.Gap() return math.max(0.5, C.pitch - T.Natural()) end
function T.TextHeight(fs)
  local one = T.Natural()
  return math.max(1, math.floor((fs:GetStringHeight() or one) / one + 0.5)) * one
end

local blocks = {}
local function Block(i)
  local b = blocks[i]
  if b then return b end
  b = { lines = {} }
  b.title = CreateFrame("Button", nil, box)
  b.title.afOverhang = true -- the column hangs below the Edit Mode box on purpose (the audit skips it)
  b.title.text = b.title:CreateFontString(nil, "OVERLAY")
  Font(b.title.text, C.titleSize, TITLE)
  b.title.text:SetPoint("TOPLEFT", b.title, "TOPLEFT", 0, 0)
  b.title.text:SetWidth(C.textW)
  b.title:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.title:SetScript("OnClick", function(self, button) T.Click(self.entry, button) end)
  b.title:SetScript("OnEnter", function(self)
    self.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]); T.Tooltip(self, self.entry)
  end)
  b.title:SetScript("OnLeave", function(self)
    self.text:SetTextColor(TITLE[1], TITLE[2], TITLE[3]); if GameTooltip then GameTooltip:Hide() end
  end)
  b.desc = box:CreateFontString(nil, "OVERLAY")
  Font(b.desc, C.bodySize, BODY)
  b.desc:SetWidth(C.textW - (C.objIndent - C.indent))
  blocks[i] = b
  return b
end
T.Block, T.blocks = Block, blocks
local function Line(b, j)
  local l = b.lines[j]
  if l then return l end
  l = {}
  l.dash = box:CreateFontString(nil, "OVERLAY"); Font(l.dash, C.bodySize, BODY); l.dash:SetText("-")
  l.text = box:CreateFontString(nil, "OVERLAY"); Font(l.text, C.bodySize, BODY)
  l.text:SetWidth(C.textW - (C.objIndent - C.indent))
  l.check = box:CreateTexture(nil, "ARTWORK"); AFUI.SetAtlas(l.check, "ui-questtracker-tracker-check-c60-2x"); l.check:SetWidth(17); l.check:SetHeight(17)
  l.barBack = box:CreateTexture(nil, "ARTWORK"); AFUI.SetColor(l.barBack, 0, 0, 0, 0.6)
  l.barFill = box:CreateTexture(nil, "OVERLAY"); AFUI.SetColor(l.barFill, 0.75, 0.61, 0, 1)
  b.lines[j] = l
  return l
end
local function HideBlock(b)
  b.title:Hide(); b.desc:Hide()
  for _, l in ipairs(b.lines) do l.dash:Hide(); l.text:Hide(); l.check:Hide(); l.barBack:Hide(); l.barFill:Hide() end
end

-- A zone header row: the fold arrow and the zone name, click folds / unfolds the zone (saved).
local zoneRows = {}
local function ZoneRow(i)
  local z = zoneRows[i]
  if z then return z end
  z = CreateFrame("Button", nil, box)
  z.afOverhang = true
  z.text = z:CreateFontString(nil, "OVERLAY"); Font(z.text, C.titleSize, GOLD)
  z.text:SetPoint("LEFT", z, "LEFT", C.indent, 0)
  z.arrow = z:CreateTexture(nil, "ARTWORK"); z.arrow:SetWidth(12); z.arrow:SetHeight(12)
  z.arrow:SetPoint("LEFT", z, "LEFT", C.indent - 17, 0)
  z:SetScript("OnClick", function(self) T.SetZoneCollapsed(self.zone, not T.ZoneCollapsed(self.zone)) end)
  zoneRows[i] = z
  return z
end
T.ZoneRow = ZoneRow

-- Room under the column before it would run into the bags bar / HUD tooltip (units of the box).
function T.Room()
  local top = box:GetTop()
  if not top then return 600 end
  local scale = box:GetEffectiveScale() or 1
  local low = 0
  for _, f in ipairs({ AFUI.BagBar, AFUI.HudTooltip }) do
    local ft = f and f.GetTop and f:GetTop()
    if ft and f:IsShown() then low = math.max(low, ft * (f:GetEffectiveScale() or 1)) end
  end
  return (top * scale - low) / scale - C.margin
end

local descCache = {}
local function describe(index, title)
  local hit = descCache[title]
  if hit then return hit ~= "" and hit or nil end
  if not (SelectQuestLogEntry and GetQuestLogQuestText) then return nil end
  local sel = GetQuestLogSelection and GetQuestLogSelection()
  SelectQuestLogEntry(index)
  local text, objectives = GetQuestLogQuestText()
  if sel and sel > 0 then SelectQuestLogEntry(sel) end
  local out = (objectives and objectives ~= "" and objectives) or text
  out = out ~= "" and out or nil
  descCache[title] = out or "" -- empty text is cached too: SelectQuestLogEntry raises QUEST_LOG_UPDATE, which would redraw (and select) again every frame
  return out
end

function T.Layout(entries)
  local all, quests = T.IsCollapsed("all"), T.IsCollapsed("quests")
  Show(secBar, not all); if all then secText:Hide(); secButton:Hide() else secText:Show(); secButton:Show() end
  T.PaintButton(allButton, all and "ui-questtrackerbutton-expand-all-c60-2x" or "ui-questtrackerbutton-collapse-all-c60-2x",
    all and "ui-questtrackerbutton-expand-all-pressed-c60-2x" or "ui-questtrackerbutton-collapse-all-pressed-c60-2x")
  T.PaintButton(secButton, quests and "ui-questtrackerbutton-secondary-expand-c60-2x" or "ui-questtrackerbutton-secondary-collapse-c60-2x",
    quests and "ui-questtrackerbutton-secondary-expand-pressed-c60-2x" or "ui-questtrackerbutton-secondary-collapse-pressed-c60-2x")
  for _, b in ipairs(blocks) do HideBlock(b) end
  for _, z in ipairs(zoneRows) do z:Hide() end
  T.height = C.headH
  if all then return end
  T.height = C.secTop + C.secH
  if quests then return end
  local y, room, used = C.secTop + C.secH + C.firstTop, T.Room(), 0
  local zones = AFUI.GetSetting("trackerZones", true) ~= false
  local here = _G.GetRealZoneText and GetRealZoneText() or nil
  local selected = GetQuestLogSelection and GetQuestLogSelection() or nil
  local list = {} -- the entries in drawing order, a zone header standing in front of its group
  for gi, g in ipairs(T.Group(entries, zones, here, selected)) do
    if g.zone then list[#list + 1] = { header = g.zone, gi = gi } end
    if not (g.zone and T.ZoneCollapsed(g.zone)) then for _, e in ipairs(g.entries) do list[#list + 1] = e end end
  end
  local n = 0
  for _, e in ipairs(list) do
    if e.header then
      local z = ZoneRow(e.gi)
      local folded = T.ZoneCollapsed(e.header)
      z.zone = e.header
      z.text:SetText(e.header)
      AFUI.SetAtlas(z.arrow, folded and "ui-questtrackerbutton-secondary-expand-c60-2x" or "ui-questtrackerbutton-secondary-collapse-c60-2x")
      z:ClearAllPoints(); z:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
      z:SetWidth(T.WIDTH - 20); z:SetHeight(C.zoneH)
      z:Show()
      y = y + C.zoneH
    else
    n = n + 1
    local i = n
    local b = Block(i)
    b.title.entry = e
    b.title.text:SetText(e.title)
    local h = T.TextHeight(b.title.text)
    local need = h + T.Gap()
    for _, l in ipairs(e.lines) do need = need + T.Natural() + T.Gap() + (l.pct and C.barH + C.barGap or 0) end
    if e.desc then need = need + T.Natural() * 4 end
    if y + need > room and i > 1 then break end -- the rest would run into the bags bar
    b.title:ClearAllPoints(); b.title:SetPoint("TOPLEFT", box, "TOPLEFT", C.indent, -y)
    b.title:SetWidth(math.min(b.title.text:GetStringWidth() + 2, C.textW)); b.title:SetHeight(h)
    b.title:Show()
    y = y + h + T.Gap()
    for j, ln in ipairs(e.lines) do
      local l = Line(b, j)
      l.text:SetText(ln.text)
      local color = ln.done and DONE or BODY
      l.text:SetTextColor(color[1], color[2], color[3]); l.dash:SetTextColor(color[1], color[2], color[3])
      local lh = T.TextHeight(l.text)
      l.text:ClearAllPoints(); l.text:SetPoint("TOPLEFT", box, "TOPLEFT", C.objIndent, -y)
      l.text:Show()
      if ln.done then
        l.dash:Hide()
        l.check:ClearAllPoints(); l.check:SetPoint("TOPLEFT", box, "TOPLEFT", C.indent - 11, -y + 3); l.check:Show()
      else
        l.check:Hide()
        l.dash:ClearAllPoints(); l.dash:SetPoint("TOPLEFT", box, "TOPLEFT", C.indent, -y); l.dash:Show()
      end
      y = y + lh + T.Gap()
      if ln.pct then -- a percentage objective: a bar under its text
        local w = C.textW - (C.objIndent - C.indent)
        l.barBack:ClearAllPoints(); l.barBack:SetPoint("TOPLEFT", box, "TOPLEFT", C.objIndent, -(y - T.Gap() + C.barGap))
        l.barBack:SetWidth(w); l.barBack:SetHeight(C.barH); l.barBack:Show()
        l.barFill:ClearAllPoints(); l.barFill:SetPoint("TOPLEFT", l.barBack, "TOPLEFT", 0, 0)
        l.barFill:SetWidth(math.max(1, w * ln.pct / 100)); l.barFill:SetHeight(C.barH)
        if ln.done then AFUI.SetColor(l.barFill, 0.2, 0.75, 0.2, 1) else AFUI.SetColor(l.barFill, TITLE[1], TITLE[2], TITLE[3], 1) end
        l.barFill:Show()
        y = y + C.barH + C.barGap
      else l.barBack:Hide(); l.barFill:Hide() end
    end
    if e.desc then
      b.desc:SetText(e.desc)
      b.desc:ClearAllPoints(); b.desc:SetPoint("TOPLEFT", box, "TOPLEFT", C.objIndent, -y)
      b.desc:Show()
      y = y + T.TextHeight(b.desc) + T.Gap()
    end
    y = y + C.blockGap
    used = used + 1
    end
  end
  T.height, T.shown = y, used
end

---------------------------------------------------------------- Questie's tracker (when it is on, Forever's stays off and inert)
-- Questie keeps its switch in Questie.db.profile.trackerEnabled (QuestieTracker:Enable / Disable flip it and reload the UI). Every read is guarded: Questie's
-- internals differ by version, and it may start before or after us. Not saved: derived live.
function T.QuestieTrackerOn()
  local ok, on = pcall(function()
    local q = _G.Questie
    local p = type(q) == "table" and type(q.db) == "table" and q.db.profile
    -- the frame only exists once Questie built its tracker, so it also proves the tracker is on when the db flag reads differently by version
    return (type(p) == "table" and p.trackerEnabled == true) or type(_G.Questie_BaseFrame) == "table"
  end)
  return ok and on == true
end
function T.Mode() return T.QuestieTrackerOn() and "questie" or "forever" end
function T.Inert() return T.inert == true end

local function giveBackBlizzard() -- stock again: Refresh only dimmed it
  if not T.dimmed then return end
  T.dimmed = nil
  for _, n in ipairs({ "QuestWatchFrame", "WatchFrame" }) do
    local f = _G[n]
    if f and f.SetAlpha then f:SetAlpha(1); if f.EnableMouse then f:EnableMouse(true) end end
  end
end

-- Follows the Questie switch: on = Forever's tracker hidden and inert, off = as before.
function T.Sync()
  local inert = T.QuestieTrackerOn()
  if inert == T.Inert() then return end
  T.inert = inert
  if inert then
    box:Hide(); T.visible = false
    giveBackBlizzard()
  else
    T.Refresh()
  end
end

-- hooks on Questie's own switch (once each) so toggling it in game follows at once; ADDON_LOADED / login / delayed checks cover the rest
local hooked = {}
function T.HookQuestie()
  pcall(function()
    local L = _G.QuestieLoader
    local mod = type(L) == "table" and L.ImportModule and L:ImportModule("QuestieTracker")
    if type(mod) ~= "table" then return end
    for _, fn in ipairs({ "Initialize", "Enable", "Disable" }) do
      if type(mod[fn]) == "function" and not hooked[fn] then
        hooked[fn] = true
        hooksecurefunc(mod, fn, function() T.Sync() end)
      end
    end
  end)
end

-- Quest ids (log index when the id is unknown) the client reports as watched; with Questie's tracker its IsQuestWatched replacement answers.
function T.WatchedIds()
  local out = {}
  if not (GetNumQuestLogEntries and IsQuestWatched) then return out end
  for i = 1, GetNumQuestLogEntries() or 0 do
    local title, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
    if title and not isHeader and IsQuestWatched(i) then out[#out + 1] = id or i end
  end
  return out
end

-- Safety net, once per session: Questie's tracker is on and quests are tracked, yet its frame is missing or hidden 3 s after the world loaded:
-- ask Questie to lay out again (QuestieTracker.Update; Enable would reload the UI, so never that). The outcome goes to the audit record.
function T.QuestieNet()
  if T.netDone then return end
  T.netDone = true
  local rec = { stamp = date and date("%Y-%m-%d %H:%M:%S") or "", action = "none" }
  pcall(function()
    local f = _G.Questie_BaseFrame
    rec.on, rec.frame, rec.shown, rec.tracked = T.QuestieTrackerOn(), f ~= nil, f and f:IsShown() and true or false, #T.WatchedIds()
    if not rec.on or rec.shown or rec.tracked == 0 then return end
    local L = _G.QuestieLoader
    local mod = type(L) == "table" and L.ImportModule and L:ImportModule("QuestieTracker")
    if type(mod) ~= "table" or type(mod.Update) ~= "function" then rec.action = "no QuestieTracker.Update"; return end
    local ok, err = pcall(mod.Update)
    rec.action = ok and "Update called" or ("Update failed: " .. tostring(err))
    f = _G.Questie_BaseFrame
    rec.shownAfter = f and f:IsShown() and true or false
  end)
  local d = _G.AztraForeverUIDB
  if type(d) == "table" then d.audit = type(d.audit) == "table" and d.audit or {}; d.audit.questieNet = rec end
  T.net = rec
end

---------------------------------------------------------------- refresh
-- Edit Mode with nothing tracked shows sample lines, so the box has something to move (Forever's preview).
local SAMPLE = { { title = "[20] Sample Quest", index = 0, name = "Sample Quest", lines = { { text = "0/10 Sample Objective", done = false } } } }
function T.Refresh()
  if T.busy or T.inert then return end
  T.busy = true
  local ok, err = pcall(function()
    local entries = T.Collect(describe)
    T.entries = entries
    local editing = AFUI.EditMode and AFUI.EditMode.IsOpen and AFUI.EditMode.IsOpen()
    if #entries == 0 and editing then entries = SAMPLE end
    local visible = #entries > 0 and not T.hidden
    if visible then T.Layout(entries); box:Show() else box:Hide() end
    T.visible = visible
    -- Blizzard's own list stays as it is, only invisible (QuestWatch_Update re-shows and resizes it)
    for _, n in ipairs({ "QuestWatchFrame", "WatchFrame" }) do
      local f = _G[n]
      if f and f.SetAlpha then f:SetAlpha(0); T.dimmed = true; if f.EnableMouse then f:EnableMouse(false) end end
    end
  end)
  T.busy = nil
  if not ok then geterrorhandler()(err) end
end

function T.SetHidden(on) T.hidden = on and true or false; T.Refresh() end

---------------------------------------------------------------- clicks and tooltip
function T.Click(e, button)
  if not e or not e.index or e.index == 0 then return end
  if IsShiftKeyDown() then
    RemoveQuestWatch(e.index)
    if QuestWatch_Update and not InCombatLockdown() then QuestWatch_Update() end -- the client's own QUEST_WATCH_UPDATE handler calls it as well; from here it would run tainted
    T.Refresh()
    if AFUI.MapQuestPins and AFUI.MapQuestPins.Refresh then AFUI.MapQuestPins.Refresh() end
    return
  end
  SelectQuestLogEntry(e.index)
  if AFUI.MapQuestPins and AFUI.MapQuestPins.Select then AFUI.MapQuestPins.Select(e.questID, e.index) end
  if AFUI.QuestLog and AFUI.QuestLog.Show then AFUI.QuestLog.Show() elseif ToggleQuestLog then ToggleQuestLog() end
end

function T.Tooltip(owner, e)
  if not (GameTooltip and e) then return end
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:AddLine(e.name or e.title, GOLD[1], GOLD[2], GOLD[3])
  if e.desc then GameTooltip:AddLine(e.desc, 1, 1, 1, true) end
  for _, l in ipairs(e.lines or {}) do
    local c = l.done and DONE or { 1, 1, 1 }
    GameTooltip:AddLine("- " .. l.text, c[1], c[2], c[3], true)
  end
  if e.questID and AFUI.GetSetting("tooltipIds", false) then GameTooltip:AddLine("QuestID: " .. e.questID, 0.6, 0.6, 0.6) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click: open the quest log   Shift-click: stop tracking", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

---------------------------------------------------------------- wiring
local dirty = false
-- events only mark the list dirty, one refresh per frame (an OnUpdate only runs on a shown frame, so the driver has a frame of its own)
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function() if dirty then dirty = false; T.Refresh() end end)
local function mark() if not T.inert then dirty = true end end
T.Mark = mark

---------------------------------------------------------------- auto-tracking (Forever: an accepted quest is watched at once)
-- Saved vars (AztraForeverUICharDB): questSeen[id] = the quest was handled once (tracked or refused), questUntracked[id] = the player unticked it.
-- A quest is auto-tracked exactly once, the first time it shows in the log (accept, or the login pass for quests accepted before this existed); after that the
-- watch state is the player's. The log index shifts, so everything is keyed by quest id. Pruned against the full log so a re-accepted quest is new again.
-- The client's limit (MAX_WATCHABLE_QUESTS) stays: a refused quest is simply not tracked (Blizzard behaviour); with Questie the result is read back after the call.
local function logEntries()
  local Q = AFUI.QuestLog
  if Q and Q.ReadAll then return Q.ReadAll() end -- also the quests of collapsed zones
  local out = {}
  for i = 1, GetNumQuestLogEntries and GetNumQuestLogEntries() or 0 do
    local title, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
    if title then out[#out + 1] = { index = i, questID = id, isHeader = isHeader and true or false, watched = IsQuestWatched and IsQuestWatched(i) and true or false } end
  end
  return out
end

function T.AutoTrack()
  if AFUI.GetSetting("autoTrackQuests", true) == false then return 0 end -- Settings > Tracker & Map
  local db = _G.AztraForeverUICharDB
  if T.inert or T.QuestieTrackerOn() or not (db and _G.AddQuestWatch and _G.IsQuestWatched) then return 0 end -- Questie's tracker on: Questie auto-tracks by its own setting
  db.questSeen, db.questUntracked = db.questSeen or {}, db.questUntracked or {}
  local entries, present, added, n = logEntries(), {}, 0, 0
  for _, e in ipairs(entries) do if not e.isHeader and e.questID then n = n + 1 end end
  if n == 0 then return 0 end -- the log has not loaded yet: nothing to judge
  T.autoBusy = true
  for _, e in ipairs(entries) do
    local id = e.questID
    if not e.isHeader and id then
      present[id] = true
      if not db.questSeen[id] then
        db.questSeen[id] = true
        local full = not (_G.Questie or _G.QuestieLoader) and GetNumQuestWatches and GetNumQuestWatches() >= (_G.MAX_WATCHABLE_QUESTS or 5)
        if not e.watched and not db.questUntracked[id] and not full then
          local idx = AFUI.QuestLog and AFUI.QuestLog.IndexOf and AFUI.QuestLog.IndexOf(id, e.index) or e.index
          AddQuestWatch(idx)
          if IsQuestWatched(idx) then added = added + 1 end
        end
      end
    end
  end
  for _, set in ipairs({ db.questSeen, db.questUntracked }) do
    for id in pairs(set) do if not present[id] then set[id] = nil end end
  end
  T.autoBusy = nil
  if added > 0 then
    if QuestWatch_Update and not InCombatLockdown() then QuestWatch_Update() end
    mark()
  end
  return added
end

-- Any RemoveQuestWatch that is not ours is the player's untick (our tracker, the panel, Blizzard's); AddQuestWatch lifts it. The client also removes the watch
-- of a quest it just dropped, whose index may now be another quest: only a quest that is in the log and unwatched counts.
function T.NoteWatch(index, tracked)
  local db = _G.AztraForeverUICharDB
  if T.inert or T.autoBusy or T.QuestieTrackerOn() or not db or not index then return end
  local title, _, _, isHeader, _, _, _, id = GetQuestLogTitle(index)
  if not title or isHeader or not id then return end
  db.questUntracked = db.questUntracked or {}
  if tracked then db.questUntracked[id] = nil
  elseif not (IsQuestWatched and IsQuestWatched(index)) then db.questUntracked[id] = true end
end

local function autoTrackSoon()
  -- Questie's own auto-track runs on the same event: a beat later we only add what is still missing
  if not (_G.C_Timer and C_Timer.After) then T.AutoTrack(); return end
  if T.autoPending then return end -- QUEST_LOG_UPDATE is frequent: one pass per beat
  T.autoPending = true
  C_Timer.After(0.5, function() T.autoPending = nil; T.AutoTrack() end)
end

function T.Setup()
  T.Sync(); T.HookQuestie()
  AFUI.On("ADDON_LOADED", function(_, addon) if addon == "Questie" then T.Sync(); T.HookQuestie() end end)
  if _G.C_Timer and C_Timer.After then
    for _, d in ipairs({ 1, 3, 8 }) do C_Timer.After(d, function() T.Sync(); T.HookQuestie() end) end -- Questie's db may come up after us
  end
  for _, ev in ipairs({ "QUEST_ACCEPTED", "QUEST_LOG_UPDATE" }) do AFUI.On(ev, autoTrackSoon) end
  AFUI.On("PLAYER_ENTERING_WORLD", function()
    if _G.C_Timer and C_Timer.After then C_Timer.After(4, T.AutoTrack); C_Timer.After(3, T.QuestieNet) end
  end)
  if type(_G.RemoveQuestWatch) == "function" then hooksecurefunc("RemoveQuestWatch", function(i) T.NoteWatch(i, false) end) end
  if type(_G.AddQuestWatch) == "function" then hooksecurefunc("AddQuestWatch", function(i) T.NoteWatch(i, true) end) end
  for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_REMOVED" }) do
    AFUI.On(ev, mark)
  end
  if type(_G.QuestWatch_Update) == "function" then hooksecurefunc("QuestWatch_Update", mark) end
  AFUI.OnSettingChanged("trackerZones", T.Refresh)
  local EM = AFUI.EditMode
  if EM then
    if EM.Open then hooksecurefunc(EM, "Open", T.Refresh) end
    if EM.Close then hooksecurefunc(EM, "Close", T.Refresh) end
  end
  T.Refresh()
end
AFUI.RegisterModule("Tracker", { OnLogin = T.Setup })
