-- Forever's Reputation, Skills and PvP panes of the Character window. Forever puts every tab in the same two panes as the paper doll: the left pane (398 px,
-- General-BG stone) holds the list, the right pane (233 px, Stat-BG stone with the framedivider) the side pane with the detail of the selected row
-- (camelot reputationframe.xml / skillsframe.xml / characterframe.xml CharacterFrameSidePaneTemplate, build 1.60.1.70938). Forever's list is a ScrollBox of
-- 28 px collapsible headers and 30 px entries with a 160 px ColoredProgressBar (common-stat-bar) on the right, selected / hovered rows lit white.
-- The client's own ReputationFrame / SkillFrame / PVPFrame stay the tab state (ToggleCharacter shows them, their events keep running); their children
-- are parked on AFUI.Hidden and everything is drawn here from the client's API (TBC 2.5.3, Interface/FrameXML ReputationFrame / SkillFrame / PVPFrame):
--   GetNumFactions, GetFactionInfo(i) -> name, description, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep,
--   isWatched, isChild; Expand/CollapseFactionHeader, Get/SetSelectedFaction, FactionToggleAtWar, SetFactionInactive/Active, IsFactionInactive, SetWatchedFactionIndex.
--   GetNumSkillLines, GetSkillLineInfo(i) -> name, isHeader, isExpanded, rank, tempPoints, modifier, maxRank, isAbandonable, ..., description (13th);
--   Expand/CollapseSkillHeader, Get/SetSelectedSkill; the client's SkillDetailStatusBarUnlearnButton does the unlearning.
--   GetPVPSessionStats / GetPVPYesterdayStats / GetPVPLifetimeStats (kills first), GetArenaTeam(i) -> name, size, rating, played, wins, seasonPlayed, seasonWins,
--   playerPlayed, seasonPlayerPlayed, rank, playerRating, bgR, bgG, bgB, ...; ArenaTeamRoster, GetNumArenaTeamMembers(i, 1), GetArenaTeamRosterInfo(i, m) -> name, rank,
--   level, class, online, played, win, seasonPlayed, seasonWin, rating.
AFUI = AFUI or {}
local CP = {}
AFUI.CharacterPanes = CP

local PLAIN = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\"
local HEADER_H, ENTRY_H, SPACING, PAD = 28, 30, 3, 10 -- ScrollBox view: header / entry heights, element spacing, padding

---------------------------------------------------------------- pure logic (specs: tests/lua/characterpanes_spec.lua)
local FALLBACK_COLORS = { -- FACTION_BAR_COLORS of the client (FrameXML Constants.lua)
  [1] = { r = 0.55, g = 0, b = 0 }, [2] = { r = 0.7, g = 0.2, b = 0.05 }, [3] = { r = 0.75, g = 0.27, b = 0 }, [4] = { r = 0.9, g = 0.7, b = 0 },
  [5] = { r = 0, g = 0.6, b = 0.1 }, [6] = { r = 0, g = 0.6, b = 0.1 }, [7] = { r = 0, g = 0.6, b = 0.1 }, [8] = { r = 0, g = 0.6, b = 0.1 },
}
function CP.StandingColor(id)
  local c = (FACTION_BAR_COLORS and FACTION_BAR_COLORS[id]) or FALLBACK_COLORS[id] or FALLBACK_COLORS[4]
  return c.r, c.g, c.b
end

function CP.StandingLabel(id)
  local sex = UnitSex and UnitSex("player") or 2
  local t = _G["FACTION_STANDING_LABEL" .. tostring(id)]
  if type(GetText) == "function" then t = GetText("FACTION_STANDING_LABEL" .. tostring(id), sex) or t end
  return t or ""
end

-- Share of the current standing's span the bar shows; exalted (8) is a full bar.
function CP.RepRatio(value, min, max, standing)
  if standing == 8 then return 1 end
  local span = (max or 0) - (min or 0)
  if span <= 0 then return 0 end
  return math.max(0, math.min(1, ((value or 0) - min) / span))
end
function CP.RepProgress(value, min, max, standing)
  if standing == 8 then return nil end
  return "|cffffd100" .. CP.Commas((value or 0) - (min or 0)) .. "|r / " .. CP.Commas((max or 0) - (min or 0))
end
-- 1415 -> "1,415"
function CP.Commas(n)
  local s = tostring(math.floor(math.abs(n or 0)))
  s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (n or 0) < 0 and ("-" .. s) or s
end

function CP.ReadFactions()
  local out = {}
  if not GetNumFactions or not GetFactionInfo then return out end
  for i = 1, GetNumFactions() do
    local name, desc, standing, bmin, bmax, bval, atWar, canAtWar, isHeader, collapsed, hasRep, watched, isChild = GetFactionInfo(i)
    if name then
      out[#out + 1] = { kind = isHeader and "header" or "faction", index = i, name = name, description = desc, standing = standing, min = bmin, max = bmax, value = bval,
        atWar = atWar and true or false, canAtWar = canAtWar and true or false, collapsed = collapsed and true or false, watched = watched and true or false,
        child = isChild and true or false, hasRep = hasRep and true or false }
    end
  end
  return out
end

function CP.SkillText(rank, mod, max)
  if (max or 0) <= 1 then return "" end
  if (mod or 0) ~= 0 then return string.format("%d |cff20ff20(%+d)|r / %d", rank, mod, max) end
  return string.format("%d / %d", rank, max)
end
function CP.SkillRatio(rank, max)
  if not max or max <= 0 then return 0 end
  return math.max(0, math.min(1, rank / max))
end

function CP.ReadSkills()
  local out = {}
  if not GetNumSkillLines or not GetSkillLineInfo then return out end
  for i = 1, GetNumSkillLines() do
    local name, isHeader, expanded, rank, temp, mod, max, abandonable, _, _, _, _, desc = GetSkillLineInfo(i)
    if name then
      if isHeader then out[#out + 1] = { kind = "header", index = i, name = name, collapsed = not expanded }
      else out[#out + 1] = { kind = "skill", index = i, name = name, rank = rank or 0, mod = mod or 0, max = max or 0, abandonable = abandonable and true or false, description = desc } end
    end
  end
  return out
end

-- Rows get their top offsets: padded top, 3 px apart.
function CP.Stack(rows)
  local y = PAD
  for _, r in ipairs(rows) do
    r.y, r.h = y, r.kind == "header" and HEADER_H or ENTRY_H
    y = y + r.h + SPACING
  end
  return rows, y + PAD - SPACING
end

function CP.ArenaLabel(i) return ({ "2v2", "3v3", "5v5" })[i] or "" end

local function first(fn, ...) if type(fn) == "function" then return fn(...) end end
function CP.HonorStats()
  local t, th = first(GetPVPSessionStats)
  local y, yh = first(GetPVPYesterdayStats)
  local l, _, rank = first(GetPVPLifetimeStats)
  return { today = t or 0, todayHonor = th or 0, yesterday = y or 0, yesterdayHonor = yh or 0, lifetime = l or 0, highestRank = rank or 0 }
end

-- Honor / arena points: the client's currency (2.5.3 PVPFrame reads C_CurrencyInfo, ids 1901 honor / 1900 arena) or the older calls.
function CP.Points(kind)
  local id = kind == "arena" and 1900 or 1901
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
    if ok and type(info) == "table" then return info.quantity or 0 end
  end
  local old = kind == "arena" and GetArenaCurrency or GetHonorCurrency
  if old then local v = old(); if type(v) == "number" then return v end end
  return 0
end

function CP.ReadTeam(i)
  local name, size, rating, played, won, sPlayed, sWon, pPlayed, sPPlayed, rank, pRating, r, g, b = first(GetArenaTeam, i)
  if not name or name == "" then return nil end
  return { index = i, name = name, size = size or 0, rating = rating or 0, played = played or 0, won = won or 0, lost = math.max((played or 0) - (won or 0), 0),
    seasonPlayed = sPlayed or 0, seasonWon = sWon or 0, playerPlayed = pPlayed or 0, rank = rank or 0, playerRating = pRating or 0, bg = { r or 0.2, g or 0.2, b or 0.2 } }
end

---------------------------------------------------------------- widgets
local function g(n) return _G[n] end

-- Three-piece horizontal stretch of an atlas (caps of `cap` texels, the middle stretches): the pieces and their frame-relative anchors.
local function stretch3(parent, layer, name, cap, h)
  local e = AFUI_ATLAS and AFUI_ATLAS[string.lower(name)]
  local out = {}
  if not e then return out end
  local du = (e[5] - e[4]) * cap / e[2]
  local function piece(u0, u1)
    local t = parent:CreateTexture(nil, layer); t:SetTexture(e[1]); t:SetTexCoord(u0, u1, e[6], e[7]); out[#out + 1] = t
    return t
  end
  local l, m, r = piece(e[4], e[4] + du), piece(e[4] + du, e[5] - du), piece(e[5] - du, e[5])
  l:SetPoint("TOPLEFT", parent, "TOPLEFT"); l:SetWidth(cap); l:SetHeight(h)
  r:SetPoint("TOPRIGHT", parent, "TOPRIGHT"); r:SetWidth(cap); r:SetHeight(h)
  m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  return out
end

-- The skill-bar frame sprite is 451 x 29 with transparent padding: its visible frame spans x 5-445, y 3-20 with a 1 px border, so the
-- fill lives at left 6, top 4, right 6, bottom 9 (insetting it 5 px from the sprite, as before, put it over the border on the real client).
local BAR_INSET = { 6, 4, 6, 9 }
local SKILL_GRADIENT = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\UI-Skillbar-Gradient"
local SKILL_L, SKILL_R = { 0.01, 0.16, 0.33 }, { 0.12, 0.29, 0.52 } -- skill fill: the capture's left / full-bar right end colours

-- ColoredProgressBar: track (common-stat-bar-BG look: the Professions skill bar), the coloured fill, the frame, the text over it.
local function newBar(parent, w, h)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetWidth(w); bar:SetHeight(h)
  stretch3(bar, "BACKGROUND", "professions-skillbar-bg", 8, h)
  bar.fill = bar:CreateTexture(nil, "ARTWORK")
  bar.sheen = bar:CreateTexture(nil, "ARTWORK"); bar.sheen:SetDrawLayer("ARTWORK", 2); AFUI.SetColor(bar.sheen, 1, 1, 1, 0.08)
  bar.sheen:SetPoint("TOPLEFT", bar.fill, "TOPLEFT"); bar.sheen:SetPoint("BOTTOMRIGHT", bar.fill, "RIGHT")
  stretch3(bar, "OVERLAY", "professions-skillbar-frame", 8, h)
  local over = CreateFrame("Frame", nil, bar); over:SetAllPoints(bar); over:SetFrameLevel(bar:GetFrameLevel() + 3)
  bar.text = over:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  bar.text:SetPoint("CENTER", bar, "CENTER", 0, 3) -- centred in the visible frame (y 3-20 of the 29 high box), not the padded box
  -- c2 (skills): the capture's fill runs dark navy at the left to a lighter blue at the right end (video3 f0023: #022855 -> #1f4a84).
  function bar.Set(ratio, r, gr, b, text, c2)
    local fw = AFUI.Bar.Place(bar.fill, bar, BAR_INSET, ratio, nil, "professions-skillbar-frame")
    if fw < 1 then bar.fill:Hide(); bar.sheen:Hide() else bar.sheen:Show() end
    if c2 then
      -- a real smooth gradient: the left `ratio` part of one 128 x 128 gradient image (tools/skill-gradient.mjs), so the colour at any point of the full bar is the same
      -- whatever the rank (the old fill was GRAD flat segments and showed as steps)
      if fw >= 1 then
        bar.fill:SetTexture(SKILL_GRADIENT); bar.fill:SetVertexColor(1, 1, 1, 1)
        bar.fill:SetTexCoord(0, math.max(0.004, math.min(1, ratio or 0)), 0, 1)
      end
    else
      bar.fill:SetTexCoord(0, 1, 0, 1)
      AFUI.SetColor(bar.fill, r * 0.68, gr * 0.68, b * 0.68, 1) -- the capture's rep fills are darker and flatter than the client's bar colours
    end
    AFUI.FitText(bar.text, text or "", w - 12) -- the text stays inside the frame
  end
  return bar
end

local function setShown(f, on) if on then f:Show() else f:Hide() end end

-- Forever's list header (capture): a flat dark-bronze plate, 1 px gold-brown outline with the corner pixels left out, lighter in its top half.
local function flatPlate(parent) -- textures of the row itself (a child frame would cover its text); returns { Show, Hide }
  local ts = {}
  local function rect(layer, r, gr, b, p1, x1, y1, p2, x2, y2)
    local t = parent:CreateTexture(nil, layer); AFUI.SetColor(t, r, gr, b, 1)
    t:SetPoint("TOPLEFT", parent, p1, x1, y1); t:SetPoint("BOTTOMRIGHT", parent, p2, x2, y2)
    ts[#ts + 1] = t
  end
  rect("BORDER", 0.17, 0.115, 0.07, "TOPLEFT", 1, -2, "RIGHT", -1, 0)
  rect("BORDER", 0.115, 0.075, 0.045, "LEFT", 1, 0, "BOTTOMRIGHT", -1, 2)
  rect("ARTWORK", 0.55, 0.45, 0.27, "TOPLEFT", 2, -1, "TOPRIGHT", -2, -2)
  rect("ARTWORK", 0.55, 0.45, 0.27, "BOTTOMLEFT", 2, 2, "BOTTOMRIGHT", -2, 1)
  rect("ARTWORK", 0.55, 0.45, 0.27, "TOPLEFT", 0, -3, "BOTTOMLEFT", 1, 3)
  rect("ARTWORK", 0.55, 0.45, 0.27, "TOPRIGHT", -1, -3, "BOTTOMRIGHT", 0, 3)
  return { Show = function() for _, t in ipairs(ts) do t:Show() end end, Hide = function() for _, t in ipairs(ts) do t:Hide() end end }
end
local function enable(f, on) if on then f:Enable() else f:Disable() end end

---------------------------------------------------------------- setup
function CP.Setup(env)
  if CP.built then return end
  CP.built = true
  local cf, win, base, atlasTexture, nineSlice = env.cf, env.win, env.base, env.atlasTexture, env.nineSlice
  local LEFT_W, RIGHT_W, TOP, H = env.LEFT_W, env.RIGHT_W, env.TOP, env.H
  local K = AFUI.WinKit

  local FRAMES = { rep = "ReputationFrame", skills = "SkillFrame", pvp = "PVPFrame", pet = "PetPaperDollFrame" }
  local current -- "rep" | "skills" | "pvp" | "pet" | nil
  local function which()
    for k, n in pairs(FRAMES) do local f = g(n); if f and f:IsShown() then return k end end
  end
  function CP.Active() return which() ~= nil end

  -- the client's own pages stay (tab state, events) but are invisible, empty of children and without a mouse
  for _, n in pairs(FRAMES) do
    local f = g(n)
    if f then
      f:SetAlpha(0)
      for _, c in ipairs({ f:GetChildren() }) do c:SetParent(AFUI.Hidden) end
    end
  end

  -- host: both panes' stone, drawn under the metal frame
  local host = CreateFrame("Frame", nil, win)
  host:SetAllPoints(win); host:SetFrameLevel(base + 3)
  local left = atlasTexture(host, "BACKGROUND", "ui-character-info-general-bg-c60")
  left:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, -TOP)
  local right = atlasTexture(host, "BACKGROUND", "ui-character-info-stat-bg-c60")
  right:SetPoint("TOPLEFT", cf, "TOPLEFT", LEFT_W, -TOP)
  right:SetHeight(H - TOP) -- the art is 383 px tall, the pane 464
  local divider = CreateFrame("Frame", nil, host)
  divider:SetFrameLevel(base + 12); divider:SetWidth(11); divider:SetHeight(H - TOP)
  divider:SetPoint("TOPLEFT", cf, "TOPLEFT", LEFT_W - 6, -TOP)
  do -- common-framedivider: 12 px caps, the middle tiles
    local e = AFUI_ATLAS and AFUI_ATLAS["common-framedivider-c60"]
    if e then
      local dv, total = e[7] - e[6], H - TOP
      local function piece(y, len, v0, v1)
        local t = divider:CreateTexture(nil, "OVERLAY"); t:SetTexture(e[1]); t:SetWidth(11); t:SetHeight(len)
        t:SetTexCoord(e[4], e[5], e[6] + dv * v0, e[6] + dv * v1); t:SetPoint("TOPLEFT", divider, "TOPLEFT", 0, -y)
      end
      piece(0, 12, 0, 12 / 50); piece(total - 12, 12, 38 / 50, 1)
      local y = 12
      while y < total - 12 do local len = math.min(26, total - 12 - y); piece(y, len, 12 / 50, (12 + len) / 50); y = y + len end
    end
  end

  local function pane() -- a frame over the stone for one tab's widgets
    local p = CreateFrame("Frame", nil, host)
    p:SetAllPoints(host); p:SetFrameLevel(base + 6); p:Hide()
    return p
  end
  local panes = { rep = pane(), skills = pane(), pvp = pane(), pet = pane() }

  local function line(parent, x, y, w) -- ScrollLine
    local t = atlasTexture(parent, "OVERLAY", "ui-character-info-scrollline-c60")
    t:SetWidth(w); t:SetPoint("TOP", cf, "TOPLEFT", x, -y)
    return t
  end

  ------------------------------------------------------------ side pane (title, subtitle, divider, description, rows, footer)
  local SIDE_W = RIGHT_W - 28 -- 16 px in, 12 px out
  local function newSide(parent)
    local s = { rows = {}, pool = {} }
    local f = CreateFrame("Frame", nil, parent)
    f:SetFrameLevel(base + 8)
    f:SetPoint("TOPLEFT", cf, "TOPLEFT", LEFT_W + 16, -(TOP + 14)); f:SetPoint("BOTTOMRIGHT", cf, "BOTTOMLEFT", LEFT_W + RIGHT_W - 12, 14)
    s.frame = f
    s.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    s.title:SetPoint("TOP", f, "TOP", 0, 0); s.title:SetWidth(SIDE_W); s.title:SetHeight(20)
    s.sub = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    s.sub:SetPoint("TOP", s.title, "BOTTOM", 0, -3); s.sub:SetWidth(SIDE_W)
    s.div = atlasTexture(f, "BORDER", "ui-character-info-scrollline-c60")
    s.div:SetPoint("TOP", s.sub, "BOTTOM", 0, -4)
    s.empty = f:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    s.empty:SetPoint("CENTER", f, "CENTER", 0, 30); s.empty:SetWidth(170)
    s.content = CreateFrame("Frame", nil, f)
    s.content:SetPoint("TOPLEFT", s.div, "BOTTOMLEFT", 8, -6); s.content:SetWidth(SIDE_W - 6); s.content:SetHeight(1)
    -- footer: where the checkboxes / buttons go (bottom up)
    s.footer = CreateFrame("Frame", nil, f)
    s.footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT"); s.footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT"); s.footer:SetHeight(108)
    return s
  end
  local function newSide_set(s, title, sub, color)
    s.title:SetText(title or ""); s.sub:SetText(sub or "")
    if color then s.title:SetTextColor(color[1], color[2], color[3]) else s.title:SetTextColor(1, 1, 1) end
    s.empty:SetText(""); s.div:Show(); s.content:Show()
  end
  local function sideEmpty(s, text)
    s.title:SetText(""); s.sub:SetText(""); s.div:Hide(); s.content:Hide(); s.empty:SetText(text or "")
  end
  -- rows under the divider: { cat = text } bar, { label, value, lc, vc } pair, { text, color } wrapped, { gap = px }; `y` is where they start
  local function sideRows(s, items, y)
    local used = 0
    local function get(i, kind)
      local r = s.pool[i]
      if r and r.kind == kind then return r end
      if r then r.f:Hide() end
      r = { kind = kind, f = CreateFrame("Frame", nil, s.content) }
      if kind == "cat" then
        r.f:SetHeight(28); r.f:SetWidth(SIDE_W - 6)
        local bg = atlasTexture(r.f, "BACKGROUND", "ui-character-info-title-c60"); bg:SetAllPoints(r.f)
        r.fs = r.f:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); r.fs:SetPoint("CENTER", r.f, "CENTER", 0, 1)
      elseif kind == "pair" then
        r.f:SetHeight(16); r.f:SetWidth(SIDE_W - 6)
        r.l = r.f:CreateFontString(nil, "ARTWORK", "GameFontNormal"); r.l:SetPoint("LEFT", r.f, "LEFT"); r.l:SetJustifyH("LEFT")
        r.v = r.f:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); r.v:SetPoint("RIGHT", r.f, "RIGHT"); r.v:SetJustifyH("RIGHT")
      else
        r.f:SetWidth(SIDE_W - 6)
        r.fs = r.f:CreateFontString(nil, "ARTWORK", "GameFontNormal"); r.fs:SetPoint("TOPLEFT", r.f, "TOPLEFT"); r.fs:SetWidth(SIDE_W - 6); r.fs:SetJustifyH("LEFT")
      end
      s.pool[i] = r
      return r
    end
    local yy = y or 0
    for i, it in ipairs(items) do
      local kind = it.cat and "cat" or it.label and "pair" or "text"
      local r = get(i, kind)
      r.f:ClearAllPoints(); r.f:SetPoint("TOPLEFT", s.content, "TOPLEFT", 0, -yy)
      if kind == "cat" then r.fs:SetText(it.cat); yy = yy + 28 + 2
      elseif kind == "pair" then
        r.l:SetText(it.label); r.v:SetText(it.value or "")
        local c = it.lc or { 1, 0.82, 0 }; r.l:SetTextColor(c[1], c[2], c[3])
        c = it.vc or { 1, 1, 1 }; r.v:SetTextColor(c[1], c[2], c[3])
        yy = yy + 16 + 2
      else
        r.fs:SetText(it.text or "")
        local c = it.color or { 1, 0.82, 0 }; r.fs:SetTextColor(c[1], c[2], c[3])
        local h = math.max(it.height or 0, math.min(r.fs:GetStringHeight() or 14, it.maxHeight or 400), 14)
        r.f:SetHeight(h); yy = yy + h + (it.gap or 4)
      end
      r.f:Show()
      used = i
    end
    for i = used + 1, #s.pool do s.pool[i].f:Hide() end
    return yy
  end

  ------------------------------------------------------------ the list rows (Forever's header / entry templates)
  local ROW_W = LEFT_W - 38 - 24 -- the capture: rows from x 24 to 360 (u), the scroll bar column at 383
  local function newRowFactory(onClick, onTip)
    return function(content)
      local f = CreateFrame("Button", nil, content)
      f.hl = f:CreateTexture(nil, "BACKGROUND"); f.hl:SetAllPoints(f); AFUI.SetColor(f.hl, 1, 1, 1, 0)
      f.hbg = flatPlate(f)
      f.state = atlasTexture(f, "ARTWORK", "common-button-list-minus-c60", 13, 13); f.state:SetPoint("RIGHT", f, "RIGHT", -12, 0)
      f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.name:SetJustifyH("LEFT")
      f.bar = newBar(f, 160, 29); f.bar:SetPoint("RIGHT", f, "RIGHT", -3, 0)
      f.mark = f:CreateTexture(nil, "OVERLAY"); f.mark:SetTexture(PLAIN .. "UI-CheckBox-Check"); f.mark:SetWidth(14); f.mark:SetHeight(14)
      f.mark:SetPoint("LEFT", f, "LEFT", 4, 0)
      f:SetScript("OnClick", function(self) if self.data then onClick(self.data) end end)
      f:SetScript("OnEnter", function(self) self.over = true; if self.Paint then self:Paint() end; if self.data and onTip then onTip(self, self.data) end end)
      f:SetScript("OnLeave", function(self) self.over = false; if self.Paint then self:Paint() end; GameTooltip:Hide() end)
      return f
    end
  end
  -- header: stone bar with the gold name and the plus / minus at the right; entry: name left, bar right, highlight when selected / hovered / at war
  local function fillRow(f, d, selected, paintEntry, nameX)
    f.data = d
    f:EnableMouse(true)
    local header = d.kind == "header"
    setShown(f.hbg, header); setShown(f.state, header); setShown(f.bar, not header)
    f.name:ClearAllPoints()
    if header then
      f.name:SetFontObject(GameFontNormal); f.name:SetPoint("LEFT", f, "LEFT", 10, 0); f.name:SetWidth(ROW_W - 40)
      f.name:SetTextColor(1, 0.82, 0); f.name:SetText(d.name)
      AFUI.SetAtlas(f.state, d.collapsed and "common-button-list-plus-c60" or "common-button-list-minus-c60", true)
      f.mark:Hide()
      f.Paint = function() f.hl:SetAlpha(0) end
    else
      f.name:SetFontObject(GameFontHighlight); f.name:SetPoint("LEFT", f, "LEFT", (nameX or 8) + (d.child and 6 or 0), 0); f.name:SetWidth(ROW_W - 190)
      f.name:SetTextColor(1, 1, 1); f.name:SetText(d.name)
      f.Paint = function()
        local sel = selected(d)
        if d.atWar then AFUI.SetColor(f.hl, 0.9, 0.1, 0.1, sel and 0.3 or 0.18)
        else AFUI.SetColor(f.hl, 1, 1, 1, sel and 0.2 or (f.over and 0.1 or 0)) end
      end
      paintEntry(f, d)
    end
    f.Paint()
  end

  local function selectedFaction(d) return GetSelectedFaction and GetSelectedFaction() == d.index end
  local function selectedSkill(d) return GetSelectedSkill and GetSelectedSkill() == d.index end

  ------------------------------------------------------------ Reputation
  local RepP = panes.rep
  local repList
  local repSide = newSide(RepP)
  local repChecks
  local function refreshRep()
    if current ~= "rep" then return end
    local rows = CP.ReadFactions()
    -- opening the tab with an empty detail pane reads as broken: select the first faction
    local sel = GetSelectedFaction and GetSelectedFaction() or 0
    local valid
    for _, r in ipairs(rows) do if r.index == sel and r.kind == "faction" then valid = r end end
    if not valid then
      for _, r in ipairs(rows) do if r.kind == "faction" then valid = r; if SetSelectedFaction then SetSelectedFaction(r.index) end; break end end
    end
    repList:SetRows(CP.Stack(rows))
    -- detail
    if not valid then sideEmpty(repSide, REPUTATION_DETAIL_SELECT_PROMPT or "Select a faction to see its details."); repChecks.frame:Hide(); repSide.bar:Hide(); return end
    local d = valid
    newSide_set(repSide, d.name, CP.StandingLabel(d.standing), nil)
    local r, gr, b = CP.StandingColor(d.standing)
    repSide.sub:SetTextColor(1, 1, 1)
    repSide.bar:Show(); repSide.bar.Set(CP.RepRatio(d.value, d.min, d.max, d.standing), r, gr, b, CP.RepProgress(d.value, d.min, d.max, d.standing))
    local y = 29 + 8
    y = sideRows(repSide, { { text = d.description or "", color = { 1, 1, 1 }, maxHeight = 180 } }, y)
    repChecks.frame:Show()
    repChecks.war:SetChecked(d.atWar); enable(repChecks.war, d.canAtWar)
    local inactive = IsFactionInactive and IsFactionInactive(d.index)
    repChecks.inactive:SetChecked(inactive and true or false); enable(repChecks.inactive, not d.atWar)
    repChecks.watch:SetChecked(d.watched)
    repChecks.war.label:SetTextColor(d.canAtWar and 1 or 0.5, d.canAtWar and 0.1 or 0.5, d.canAtWar and 0.1 or 0.5)
    repChecks.inactive.label:SetTextColor(d.atWar and 0.5 or 1, d.atWar and 0.5 or 0.82, d.atWar and 0.5 or 0)
  end
  repList = env.newList(RepP, "AFUI_ReputationList", {
    width = ROW_W,
    row = newRowFactory(function(d)
      if d.kind == "header" then
        local fn = d.collapsed and ExpandFactionHeader or CollapseFactionHeader
        if fn then fn(d.index) end
      elseif SetSelectedFaction then SetSelectedFaction(d.index) end
      CP.Refresh()
    end, function(row, d)
      if d.kind ~= "faction" then return end
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetText(d.name, 1, 1, 1)
      GameTooltip:AddLine(CP.StandingLabel(d.standing), CP.StandingColor(d.standing))
      local p = CP.RepProgress(d.value, d.min, d.max, d.standing)
      if p then GameTooltip:AddLine(p, 1, 1, 1) end
      GameTooltip:Show()
    end),
    fill = function(f, d)
      fillRow(f, d, selectedFaction, function(row, e)
        local r, gr, b = CP.StandingColor(e.standing)
        row.bar.Set(CP.RepRatio(e.value, e.min, e.max, e.standing), r, gr, b, CP.StandingLabel(e.standing))
        setShown(row.mark, e.watched)
        if e.watched then row.name:ClearAllPoints(); row.name:SetPoint("LEFT", row, "LEFT", 32, 0) end
      end, 14) -- the capture's faction names stand 20 px in from the header plate (f0018)
    end,
  })

  ------------------------------------------------------------ Skills
  local SkillP = panes.skills
  local skillList
  local skillSide = newSide(SkillP)
  local function refreshSkills()
    if current ~= "skills" then return end
    local rows = CP.ReadSkills()
    local sel = GetSelectedSkill and GetSelectedSkill() or 0
    local valid
    for _, r in ipairs(rows) do if r.index == sel and r.kind == "skill" then valid = r end end
    if not valid then
      for _, r in ipairs(rows) do if r.kind == "skill" then valid = r; if SetSelectedSkill then SetSelectedSkill(r.index) end; break end end
    end
    skillList:SetRows(CP.Stack(rows))
    if not valid then sideEmpty(skillSide, SKILL_DETAIL_SELECT_PROMPT or "Select a skill to see its details."); skillSide.bar:Hide(); skillSide.unlearn:Hide(); return end
    newSide_set(skillSide, valid.name, nil, nil)
    skillSide.bar:Show()
    skillSide.bar.Set(CP.SkillRatio(valid.rank, valid.max), SKILL_L[1], SKILL_L[2], SKILL_L[3], valid.max > 1 and CP.SkillText(valid.rank, valid.mod, valid.max) or "", SKILL_R)
    sideRows(skillSide, { { text = valid.description or "", color = { 1, 1, 1 }, maxHeight = 200 } }, 29 + 8)
    setShown(skillSide.unlearn, valid.abandonable)
  end
  skillList = env.newList(SkillP, "AFUI_SkillList", {
    width = ROW_W,
    row = newRowFactory(function(d)
      if d.kind == "header" then
        local fn = d.collapsed and ExpandSkillHeader or CollapseSkillHeader
        if fn then fn(d.index) end
      elseif SetSelectedSkill then SetSelectedSkill(d.index) end
      CP.Refresh()
    end, function(row, d)
      if d.kind ~= "skill" then return end
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetText(d.name, 1, 1, 1)
      if d.max > 1 then GameTooltip:AddLine(CP.SkillText(d.rank, d.mod, d.max), 1, 0.82, 0) end
      if d.description and d.description ~= "" then GameTooltip:AddLine(d.description, 1, 1, 1, true) end
      GameTooltip:Show()
    end),
    fill = function(f, d)
      fillRow(f, d, selectedSkill, function(row, e)
        row.bar.Set(CP.SkillRatio(e.rank, e.max), SKILL_L[1], SKILL_L[2], SKILL_L[3], CP.SkillText(e.rank, e.mod, e.max), SKILL_R)
        row.mark:Hide()
      end, 2) -- the capture's skill names start 2 px in; faction names 20 px (see Reputation)
    end,
  })

  ------------------------------------------------------------ list chrome shared by both lists: the scroll box, the two long lines, a title strip
  local function listChrome(p, list, title)
    list.sf:SetPoint("TOPLEFT", cf, "TOPLEFT", 22, -(TOP + 40)) -- video3 f0018 / f0023: header plates start 22 u in and are 336 u wide
    list.sf:SetPoint("BOTTOMRIGHT", cf, "TOPLEFT", LEFT_W - 40, -(H - 15))
    line(p, LEFT_W / 2, TOP + 40, LEFT_W - 40); line(p, LEFT_W / 2, H - 15, LEFT_W - 40)
    list.bar:SetFrameLevel(base + 9)
    list.bar:ClearAllPoints() -- the capture's scroll bar column stands 23 px right of the rows
    list.bar:SetPoint("TOPLEFT", list.sf, "TOPRIGHT", 13, 0); list.bar:SetPoint("BOTTOMLEFT", list.sf, "BOTTOMRIGHT", 13, 0) -- flush with the rows (the 17 u bar is centred on that column)
  end
  listChrome(RepP, repList, REPUTATION or "Reputation")
  listChrome(SkillP, skillList, SKILLS or "Skills")
  repList:SetActive(true); skillList:SetActive(true)

  -- the detail bars (180 x 29 under the divider) and the rep checkboxes
  for _, s in ipairs({ repSide, skillSide }) do
    s.bar = newBar(s.frame, 180, 29)
    s.bar:SetPoint("TOP", s.div, "BOTTOM", 0, -6)
  end
  local function repCheck(parent, y, text, onClick)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetWidth(26); cb:SetHeight(26); cb:SetPoint("TOPLEFT", parent, "TOPLEFT", -4, -y)
    if K then K.check(cb) end
    cb.label = cb:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0); cb.label:SetWidth(158); cb.label:SetJustifyH("LEFT"); cb.label:SetText(text)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return cb
  end
  do
    local fr = CreateFrame("Frame", nil, repSide.footer); fr:SetAllPoints(repSide.footer)
    repChecks = { frame = fr }
    repChecks.war = repCheck(fr, 0, AT_WAR or "At War", function() if FactionToggleAtWar then FactionToggleAtWar(GetSelectedFaction()); CP.Refresh() end end)
    repChecks.inactive = repCheck(fr, 28, "Move to Inactive", function(on)
      local i = GetSelectedFaction()
      local fn = on and SetFactionInactive or SetFactionActive
      if fn then fn(i); CP.Refresh() end
    end)
    repChecks.watch = repCheck(fr, 56, SHOW_FACTION_ON_MAINSCREEN or "Show as Experience Bar", function(on)
      if SetWatchedFactionIndex then SetWatchedFactionIndex(on and GetSelectedFaction() or 0); CP.Refresh() end
    end)
    repChecks.war.label:SetTextColor(1, 0.1, 0.1)
    for _, cb in pairs({ repChecks.war, repChecks.inactive, repChecks.watch }) do cb:SetHitRectInsets(0, -160, 0, 0) end
  end
  do -- unlearn: the client's own button does the work (it asks first)
    local b = CreateFrame("Button", nil, skillSide.footer, "UIPanelButtonTemplate")
    b:SetWidth(120); b:SetHeight(22); b:SetPoint("BOTTOM", skillSide.footer, "BOTTOM", 0, 6)
    b:SetText(UNLEARN_SKILL or "Unlearn")
    if K then K.button(b, 120) end
    b:SetScript("OnClick", function() local u = g("SkillDetailStatusBarUnlearnButton"); if u and u.Click then u:Click() end end)
    skillSide.unlearn = b
  end

  ------------------------------------------------------------ PvP (Honor, kills grid, arena teams; detail on the right)
  local PvP = panes.pvp
  local pvpSide = newSide(PvP)
  local selectedTeam
  local function header(y, textFn)
    local f = CreateFrame("Frame", nil, PvP)
    f:SetFrameLevel(base + 7); f:SetPoint("TOPLEFT", cf, "TOPLEFT", 8, -(TOP + y)); f:SetWidth(LEFT_W - 16); f:SetHeight(40)
    local bg = atlasTexture(f, "BACKGROUND", "ui-character-info-title-c60"); bg:SetAllPoints(f)
    f.text = f:CreateFontString(nil, "ARTWORK", "GameFontNormal"); f.text:SetPoint("CENTER", f, "CENTER", -10, 1)
    f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetWidth(20); f.icon:SetHeight(20); f.icon:SetPoint("LEFT", f.text, "RIGHT", 6, 0)
    return f
  end
  local honorHead, arenaHead = header(40, "honor"), header(170, "arena") -- under the collapse arrow's row (the capture: 42 units of header row)
  local faction = UnitFactionGroup and UnitFactionGroup("player") or "Alliance"
  honorHead.icon:SetTexture("Interface\\PVPFrame\\PVP-Currency-" .. faction)
  arenaHead.icon:SetTexture("Interface\\PVPFrame\\PVP-ArenaPoints-Icon")
  -- kills grid
  local grid = CreateFrame("Frame", nil, PvP)
  grid:SetFrameLevel(base + 7); grid:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, -(TOP + 84)); grid:SetWidth(LEFT_W - 28); grid:SetHeight(80)
  do
    local inner = nineSlice(grid, "BACKGROUND", "common-insideframe-c60", 53, 26)
    if inner.Place then inner.Place(grid, 0, 0, 0, 0) end
  end
  local cols = { { "today", TODAY or "Today", 150 }, { "yesterday", YESTERDAY or "Yesterday", 250 }, { "lifetime", LIFETIME or "Lifetime", 340 } }
  grid.vals = {}
  local killsLabel = grid:CreateFontString(nil, "ARTWORK", "GameFontNormal"); killsLabel:SetPoint("LEFT", grid, "LEFT", 22, -14); killsLabel:SetText(KILLS or "Kills")
  for _, c in ipairs(cols) do
    local h = grid:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall"); h:SetPoint("CENTER", grid, "TOPLEFT", c[3] - 14, -18); h:SetText(c[2]); h:SetTextColor(0.62, 0.6, 0.58)
    local v = grid:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge"); v:SetPoint("CENTER", grid, "TOPLEFT", c[3] - 14, -46)
    grid.vals[c[1]] = v
  end
  -- arena slots
  local slots = {}
  for i = 1, 3 do
    local s = CreateFrame("Button", nil, PvP)
    s:SetFrameLevel(base + 7); s:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, -(TOP + 214 + (i - 1) * 80)); s:SetWidth(LEFT_W - 28); s:SetHeight(74)
    s.bg = s:CreateTexture(nil, "BACKGROUND"); s.bg:SetAllPoints(s); AFUI.SetColor(s.bg, 0, 0, 0, 0.45)
    local frame = nineSlice(s, "OVERLAY", "common-insideframe-c60", 53, 26)
    if frame.Place then frame.Place(s, 0, 0, 0, 0) end
    s.flag = s:CreateTexture(nil, "ARTWORK"); s.flag:SetPoint("TOPLEFT", s, "TOPLEFT", 10, -10); s.flag:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 10, 10); s.flag:SetWidth(42)
    s.name = s:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge"); s.name:SetPoint("TOPLEFT", s, "TOPLEFT", 66, -9); s.name:SetJustifyH("LEFT"); s.name:SetWidth(LEFT_W - 130)
    s.rating = s:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); s.rating:SetPoint("TOPLEFT", s.name, "BOTTOMLEFT", 0, -6); s.rating:SetJustifyH("LEFT")
    s.record = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); s.record:SetPoint("TOPLEFT", s.rating, "BOTTOMLEFT", 0, -4); s.record:SetJustifyH("LEFT")
    s.size = s:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge"); s.size:SetPoint("CENTER", s, "CENTER", 0, 0)
    s.sel = s:CreateTexture(nil, "HIGHLIGHT"); s.sel:SetAllPoints(s); s.sel:SetBlendMode("ADD"); AFUI.SetColor(s.sel, 1, 0.82, 0, 0.12)
    s:SetScript("OnClick", function(self)
      if not self.team then return end
      selectedTeam = self.team.index
      if ArenaTeamRoster then ArenaTeamRoster(selectedTeam) end
      CP.Refresh()
    end)
    s.i = i
    slots[i] = s
  end
  local function refreshPvP()
    if current ~= "pvp" then return end
    honorHead.text:SetText("|cffffd100" .. (HONOR or "Honor") .. ":|r |cffffffff" .. CP.Points("honor") .. "|r")
    arenaHead.text:SetText("|cffffd100" .. (ARENA or "Arena") .. ":|r |cffffffff" .. CP.Points("arena") .. "|r")
    local st = CP.HonorStats()
    for k, v in pairs(grid.vals) do v:SetText(tostring(st[k])) end
    local picked
    for i, s in ipairs(slots) do
      local t = CP.ReadTeam(i)
      s.team = t
      setShown(s.name, t); setShown(s.rating, t); setShown(s.record, t); setShown(s.flag, t); setShown(s.size, not t)
      s:EnableMouse(t ~= nil); s.afNoClick = (t == nil)
      s.size:SetText("(" .. CP.ArenaLabel(i) .. ")")
      if t then
        s.name:SetText(t.name); s.rating:SetText("|cffffd100Rating|r " .. t.rating .. "   |cffffd100(" .. CP.ArenaLabel(i) .. ")|r")
        s.record:SetText(string.format("%d played  -  %d won  -  %d lost   (season %d / %d)", t.played, t.won, t.lost, t.seasonWon, t.seasonPlayed))
        AFUI.SetColor(s.flag, t.bg[1], t.bg[2], t.bg[3], 1)
        if selectedTeam == i then picked = t end
      end
    end
    local items = {}
    if picked then
      newSide_set(pvpSide, picked.name, CP.ArenaLabel(picked.index) .. "  -  " .. picked.rating, nil)
      items[#items + 1] = { cat = "This Week" }
      items[#items + 1] = { label = "Played", value = picked.played }; items[#items + 1] = { label = "Won", value = picked.won }; items[#items + 1] = { label = "Lost", value = picked.lost }
      items[#items + 1] = { cat = "Season" }
      items[#items + 1] = { label = "Played", value = picked.seasonPlayed }; items[#items + 1] = { label = "Won", value = picked.seasonWon }
      items[#items + 1] = { label = "My Rating", value = picked.playerRating }
      local n = GetNumArenaTeamMembers and GetNumArenaTeamMembers(picked.index, 1) or 0
      if n > 0 then
        items[#items + 1] = { cat = "Roster" }
        for m = 1, math.min(n, 10) do
          local name, _, _, _, online, _, _, _, _, rating = GetArenaTeamRosterInfo(picked.index, m)
          if name then items[#items + 1] = { label = name, value = rating, lc = online and { 1, 1, 1 } or { 0.5, 0.5, 0.5 } } end
        end
      end
    else
      newSide_set(pvpSide, HONOR or "Honor", nil, nil)
      items[#items + 1] = { cat = "Kills" }
      items[#items + 1] = { label = TODAY or "Today", value = st.today .. "  (" .. st.todayHonor .. ")" }
      items[#items + 1] = { label = YESTERDAY or "Yesterday", value = st.yesterday .. "  (" .. st.yesterdayHonor .. ")" }
      items[#items + 1] = { label = LIFETIME or "Lifetime", value = st.lifetime }
      items[#items + 1] = { text = "Select an arena team to see its record and roster.", color = { 0.62, 0.6, 0.58 }, gap = 8 }
    end
    sideRows(pvpSide, items, 0)
  end

  ------------------------------------------------------------ Pet (PetPane.lua draws it; the side pane and the bars are this file's)
  local petSide = newSide(panes.pet)
  local petPane = AFUI.PetPane and AFUI.PetPane.Build({ cf = cf, pane = panes.pet, base = base, LEFT_W = LEFT_W, TOP = TOP, atlasTexture = atlasTexture, nineSlice = nineSlice,
    newBar = newBar, side = petSide, setSide = newSide_set, rows = sideRows, sideEmpty = sideEmpty })
  local function refreshPet() if current == "pet" and petPane then petPane.Refresh() end end

  ------------------------------------------------------------ refresh / events
  function CP.Refresh()
    current = which()
    for k, p in pairs(panes) do setShown(p, k == current) end
    setShown(host, current ~= nil)
    local collapsed = env.IsCollapsed and env.IsCollapsed()
    for _, part in ipairs({ right, divider, repSide.frame, skillSide.frame, pvpSide.frame, petSide.frame }) do setShown(part, not collapsed) end
    refreshRep(); refreshSkills(); refreshPvP(); refreshPet()
  end
  function CP.Layout() if CP.built then CP.Refresh() end end
  function CP.SelectTeam(i) selectedTeam = i; CP.Refresh() end
  for _, n in pairs(FRAMES) do
    local f = g(n)
    if f and f.HookScript then f:HookScript("OnShow", CP.Refresh); f:HookScript("OnHide", CP.Refresh) end
  end
  for _, e in ipairs({ "UPDATE_FACTION", "SKILL_LINES_CHANGED", "ARENA_TEAM_UPDATE", "ARENA_TEAM_ROSTER_UPDATE", "PLAYER_PVP_KILLS_CHANGED", "PLAYER_PVP_RANK_CHANGED",
    "HONOR_CURRENCY_UPDATE", "CURRENCY_DISPLAY_UPDATE" }) do
    AFUI.On(e, function() if cf:IsShown() and current then CP.Refresh() end end)
  end
  CP.Refresh()
end
