-- WoW: Forever's Talents window: the three trees side by side on the class art, Unspent Talents box, tree headers,
-- square talent nodes with arrows, Search box. It re-skins Blizzard's PlayerTalentFrame (Blizzard_TalentUI, load on demand): the frame stays the
-- UI panel host (key N, ESC, HideUIPanel keep working), its own art and children are hidden, and every talent is drawn from the client's API.
-- Forever reference: tools/ref/interface/addons/blizzard_playerspells/camelot/classtalents/blizzard_classtalentsframe.{xml,lua} (tree headers at
-- 140 + 400 per tree, Talents-*-c60 art, search box + options dropdown, Unspent label + Talents-Square-Box), blizzard_sharedtalentui
-- (talents-node-square-* art sets, arrows), SpecializationVisuals (talent-background-<class>); look = docs/forever-ref/screens/windows/talents-inspect-tree.png.
-- Client facts (verified): the API is the same on 2.4.3 (MOUZU/Blizzard-WoW-Interface 2.4.3/FrameXML/TalentFrameBase.lua, AddOns/Blizzard_TalentUI/Blizzard_TalentUI.lua)
-- and 2.5.3 (Gethe/wow-ui-source tag 2.5.3 Interface_TBC/FrameXML/TalentFrameBase.lua, Interface_TBC/AddOns/Blizzard_TalentUI/Blizzard_TalentUI.lua):
-- GetNumTalentTabs(), GetTalentTabInfo(tab) -> name, icon, pointsSpent, background; GetNumTalents(tab); GetTalentInfo(tab, i) -> name, icon, tier, column,
-- rank, maxRank, isExceptional, meetsPrereq; GetTalentPrereqs(tab, i) -> tier, column, isLearnable (repeated); LearnTalent(tab, i) (unprotected);
-- UnitCharacterPoints("player") -> unspent points; GetTalentLink(tab, i); GameTooltip:SetTalent(tab, i); events CHARACTER_POINTS_CHANGED, SPELLS_CHANGED.
-- Neither client has dual spec and talents are learned on click: the capture's Primary / Secondary tabs and Apply Changes button are left out. The Inspect talents view (InspectTalentFrame, a tab
-- inside the small Inspect window) is not re-skinned.
AFUI = AFUI or {}

local Talents = {}
AFUI.Talents = Talents

local PLAIN = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\"
-- window units (the capture is 1.2 x these)
local TREE_W, SPACING, BUTTON, ROW1_Y = 400, 60, 40, 247
-- TBC trees have 9 to 11 tiers (the capture's rogue showed 7): the window is as tall as the deepest tier that holds a talent for the player's class.
-- Art box = last row centre + ART_PAD (the button ends 20 below its centre), window = art box + FOOT (just the metal frame's lower edge).
local BG_X, BG_Y, BG_W = 6, 80, 1204
local ART_PAD, FOOT = 30, 14
Talents.WIDTH = 1216
function Talents.Layout(tiers)
  tiers = math.max(7, math.min(11, tiers or 11))
  Talents.TIERS = tiers
  Talents.BG_H = ROW1_Y + (tiers - 1) * SPACING + ART_PAD - BG_Y
  Talents.ART_BOTTOM = BG_Y + Talents.BG_H
  Talents.HEIGHT = Talents.ART_BOTTOM + FOOT
end
Talents.Layout(11)
local TREE_CX = { 205, 608, 1011 } -- centres of the trees' 4 column grids from the window's left edge (the capture's columns are not equally wide)

---------------------------------------------------------------- pure logic
-- Window position of the centre of a node: tree 1..3, tier 1..7, column 1..4.
function Talents.NodeCenter(tree, tier, col)
  return TREE_CX[tree] + (col - 2.5) * SPACING, ROW1_Y + (tier - 1) * SPACING
end

-- "maxed" | "selectable" (can take a point now) | "partial" (ranked, nothing to spend) | "available" (open, no points) | "locked"
function Talents.NodeState(rank, maxRank, tierUnlocked, prereqsMet, points)
  if maxRank and maxRank > 0 and rank >= maxRank then return "maxed" end
  local open = tierUnlocked and prereqsMet
  if open and points > 0 then return "selectable" end
  if rank > 0 then return "partial" end
  if open then return "available" end
  return "locked"
end

function Talents.TierUnlocked(tier, pointsSpent) return (tier - 1) * 5 <= pointsSpent end

-- ... = tier, column, isLearnable triples of GetTalentPrereqs
function Talents.PrereqsMet(...)
  for i = 1, select("#", ...), 3 do
    if not select(i + 2, ...) then return false end
  end
  return true
end

-- Arrow from a prerequisite (fromTier, fromCol) into a talent (toTier, toCol). Tree relative (x from the tree centre, y down from the first
-- row's centre): segs = { { x1, y1, x2, y2 }, ... } axis aligned lines, head = { x, y, dir } where the arrow tip touches the talent.
function Talents.Edge(fromTier, fromCol, toTier, toCol)
  local half = BUTTON / 2
  local fx, fy = (fromCol - 2.5) * SPACING, (fromTier - 1) * SPACING
  local tx, ty = (toCol - 2.5) * SPACING, (toTier - 1) * SPACING
  if fromCol == toCol then
    return { segs = { { fx, fy + half, tx, ty - half } }, head = { x = tx, y = ty - half, dir = "down" } }
  elseif fromTier == toTier then
    local s = toCol > fromCol and 1 or -1
    return { segs = { { fx + s * half, fy, tx - s * half, ty } }, head = { x = tx - s * half, y = ty, dir = s > 0 and "right" or "left" } }
  end
  local s = toCol > fromCol and 1 or -1
  return { segs = { { fx + s * half, fy, tx, fy }, { tx, fy, tx, ty - half } }, head = { x = tx, y = ty - half, dir = "down" } }
end

-- Part of the name, any case, no patterns. An empty search matches nothing.
function Talents.Match(name, text)
  if not name or not text or text == "" then return false end
  return string.find(string.lower(name), string.lower(text), 1, true) ~= nil
end

-- list = { { name, rank, max, tab, index }, ... } -> { { text, tab, index, name }, ... } (at most 8)
function Talents.SearchResults(list, text, showRanks)
  local out = {}
  for _, t in ipairs(list) do
    if Talents.Match(t.name, text) then
      out[#out + 1] = { text = showRanks and (t.name .. " (" .. t.rank .. "/" .. t.max .. ")") or t.name, tab = t.tab, index = t.index, name = t.name }
      if #out == 8 then break end
    end
  end
  return out
end

-- The design size (1216 x 707) is the capture's 2560x1440 window: at the 1606 x 903 UI of a 1440p player that is 76% of the screen and its
-- bottom row ends on the action bars, so the window is drawn at most at MAXSCALE and always inside the screen minus a side margin and
-- BOTTOM_ROOM (top margin + the action bars below it).
Talents.MAXSCALE, Talents.BOTTOM_ROOM, Talents.SIDE_ROOM, Talents.TOP = 1.0, 190, 60, 36
function Talents.FitScale(uiW, uiH)
  return math.min(Talents.MAXSCALE, (uiH - Talents.BOTTOM_ROOM) / Talents.HEIGHT, (uiW - Talents.SIDE_ROOM) / Talents.WIDTH)
end

-- The class crest cell of the Classes sheet trimmed by a texel so a neighbour cell never bleeds in; WindowPortrait fills the ring opening with it.
function Talents.CrestCoords(c) return c[1] + 0.004, c[2] - 0.004, c[3] + 0.004, c[4] - 0.004 end

function Talents.PointsText(n) return tostring(n or 0) end

local CLASS_BG = { WARRIOR = "warrior", DRUID = "druid", SHAMAN = "shaman", ROGUE = "rogue", PRIEST = "priest", PALADIN = "paladin", MAGE = "mage",
  HUNTER = "hunter", WARLOCK = "warlock" }
function Talents.BackgroundFile(token)
  local c = CLASS_BG[token or ""]
  if not c then return nil end
  return PLAIN .. "talentbg-" .. c .. "-1", PLAIN .. "talentbg-" .. c .. "-2"
end

-- The client's own tree icon when it gives one (2.5.x can return nil or a file id the header cannot show); else the spec's icon.
local TAB_ICONS = {
  WARRIOR = { "Ability_Rogue_Eviscerate", "Ability_Warrior_InnerRage", "INV_Shield_06" },
  PALADIN = { "Spell_Holy_HolyBolt", "Spell_Holy_DevotionAura", "Spell_Holy_AuraOfLight" },
  HUNTER = { "Ability_Hunter_BeastTaming", "Ability_Marksmanship", "Ability_Hunter_SwiftStrike" },
  ROGUE = { "Ability_Rogue_Eviscerate", "Ability_BackStab", "Ability_Stealth" },
  PRIEST = { "Spell_Holy_WordFortitude", "Spell_Holy_HolyBolt", "Spell_Shadow_ShadowWordPain" },
  SHAMAN = { "Spell_Nature_Lightning", "Spell_Nature_LightningShield", "Spell_Nature_MagicImmunity" },
  MAGE = { "Spell_Holy_MagicalSentry", "Spell_Fire_FireBolt02", "Spell_Frost_FrostBolt02" },
  WARLOCK = { "Spell_Shadow_DeathCoil", "Spell_Shadow_Metamorphosis", "Spell_Shadow_RainOfFire" },
  DRUID = { "Spell_Nature_StarFall", "Ability_Racial_BearForm", "Spell_Nature_HealingTouch" },
}
function Talents.TabIcon(token, tab, icon)
  if icon and icon ~= "" then return icon end
  local f = TAB_ICONS[token or ""]
  return AFUI.IconPath(f and f[tab])
end

---------------------------------------------------------------- frames
local FRAME_COLORS = {
  maxed = { border = "talents-node-square-yellow", text = { 1, 0.82, 0 } },
  selectable = { border = "talents-node-square-green", text = { 0.1, 1, 0.1 } },
  partial = { border = "talents-node-square-yellow", text = { 1, 0.82, 0 } },
  available = { border = "talents-node-square-gray", text = { 0.6, 0.6, 0.6 } },
  locked = { border = "talents-node-square-gray", text = { 0.5, 0.5, 0.5 } },
}

local W = {} -- widgets
Talents.widgets = W
local showRanks = false

local function atlas(parent, layer, name, w, h)
  local t = parent:CreateTexture(nil, layer)
  AFUI.SetAtlas(t, name, not w) -- an unsized texture draws as the whole 512 px atlas page on the client
  if w then t:SetWidth(w); t:SetHeight(h) end
  return t
end

-- a tiled atlas (name__1, name__2 ...) laid left to right from `anchor`; returns total width
local function tiles(parent, layer, name, point, rel, relPoint, x, y)
  local list = AFUI_ATLAS_TILES and AFUI_ATLAS_TILES[name]
  local prev
  for _, n in ipairs(list or {}) do
    local e = AFUI_ATLAS[n]
    local t = atlas(parent, layer, n, e[2], e[3])
    if prev then t:SetPoint("LEFT", prev, "RIGHT") else t:SetPoint(point, rel, relPoint, x, y) end
    prev = t
  end
end

-- 9 textures from one atlas: slice margin m display px
local function nineSlice(parent, layer, name, m, tex)
  local e = AFUI_ATLAS[name]
  local sm = 40 -- slice margin in texels (UiTextureAtlasElementSliceData 340)
  local us = { e[4], e[4] + (e[5] - e[4]) * sm / e[2], e[5] - (e[5] - e[4]) * sm / e[2], e[5] }
  local vs = { e[6], e[6] + (e[7] - e[6]) * sm / e[3], e[7] - (e[7] - e[6]) * sm / e[3], e[7] }
  local cols = { { "LEFT", 0 }, { "LEFT", m }, { "RIGHT", -m }, { "RIGHT", 0 } }
  local rows = { { "TOP", 0 }, { "TOP", -m }, { "BOTTOM", m }, { "BOTTOM", 0 } }
  for j = 1, 3 do
    for i = 1, 3 do
      local t = parent:CreateTexture(nil, layer)
      t:SetTexture(e[1]); t:SetTexCoord(us[i], us[i + 1], vs[j], vs[j + 1])
      t:SetPoint("TOPLEFT", tex, rows[j][1] .. cols[i][1], cols[i][2], rows[j][2])
      t:SetPoint("BOTTOMRIGHT", tex, rows[j + 1][1] .. cols[i + 1][1], cols[i + 1][2], rows[j + 1][2])
    end
  end
end

local VERTICAL = { ["!ui-frame-metal-edgeleft-c60-2x"] = true, ["!ui-frame-metal-edgeright-c60-2x"] = true }
local function metalFrame(chrome, w, h)
  for _, p in ipairs(AFUI.WorldMapPieces(w, h, true)) do
    local t = atlas(chrome, "OVERLAY", p.atlas, p.w, p.h)
    local e = AFUI_ATLAS[p.atlas]
    if e and p.crop and p.crop < 1 then
      if VERTICAL[p.atlas] then t:SetTexCoord(e[4], e[5], e[6], e[6] + (e[7] - e[6]) * p.crop)
      else t:SetTexCoord(e[4], e[4] + (e[5] - e[4]) * p.crop, e[6], e[7]) end
    end
    t:SetPoint("TOPLEFT", chrome, "TOPLEFT", p.x, p.y)
  end
end

-- one metal frame per window height (its edge pieces are laid out for a fixed size); relayout() shows the one that fits
local function metalChrome(win, h)
  local chrome = CreateFrame("Frame", nil, win); chrome:SetFrameLevel(W.level + 20); chrome:SetAllPoints(win)
  metalFrame(chrome, Talents.WIDTH, h)
  return chrome
end

local function setShown(o, on) if on then o:Show() else o:Hide() end end

local function quiet(host)
  for _, r in ipairs({ host:GetRegions() }) do
    if r.IsObjectType and (r:IsObjectType("Texture") or r:IsObjectType("FontString")) then r:Hide() end
  end
  for _, c in ipairs({ host:GetChildren() }) do c:SetParent(AFUI.Hidden) end
end

local function makeNode(parent, tab, index)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(BUTTON); b:SetHeight(BUTTON)
  b.tab, b.index = tab, index
  b.shadow = atlas(b, "BACKGROUND", "talents-node-square-shadow", 78, 78); b.shadow:SetPoint("CENTER")
  b.shadow:SetAlpha(0.5)
  b.icon = b:CreateTexture(nil, "BORDER")
  b.icon:SetWidth(36); b.icon:SetHeight(36); b.icon:SetPoint("CENTER"); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.dim = b:CreateTexture(nil, "ARTWORK"); b.dim:SetWidth(36); b.dim:SetHeight(36); b.dim:SetPoint("CENTER")
  AFUI.SetColor(b.dim, 0, 0, 0, 0.55)
  b.border = atlas(b, "OVERLAY", "talents-node-square-gray", BUTTON, BUTTON); b.border:SetPoint("CENTER")
  b.glow = atlas(b, "BACKGROUND", "talents-node-square-greenglow", 84, 84); b.glow:SetPoint("CENTER"); b.glow:SetVertexColor(1, 0.82, 0); b.glow:SetBlendMode("ADD"); b.glow:Hide()
  -- the learn '+' and the rank digits sit on their own frame two levels above the button, so they are drawn over the border art
  b.top = CreateFrame("Frame", nil, b); b.top:SetAllPoints(b); b.top:SetFrameLevel(b:GetFrameLevel() + 2)
  b.plus = atlas(b.top, "OVERLAY", "talents-icon-learnableplus"); b.plus:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -3, -3); b.plus:Hide()
  b.rank = b.top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.rank:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 3)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); hl:SetBlendMode("ADD")
  hl:SetWidth(36); hl:SetHeight(36); hl:SetPoint("CENTER")
  b:SetScript("OnClick", function(self, button)
    if button ~= "LeftButton" then return end
    if IsModifiedClick and IsModifiedClick("CHATLINK") then
      local link = GetTalentLink and GetTalentLink(self.tab, self.index)
      if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
    else
      LearnTalent(self.tab, self.index)
    end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetTalent(self.tab, self.index)
    self.UpdateTooltip = function(s) GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetTalent(s.tab, s.index) end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

Talents.MakeNode = makeNode

local function line(parent, pool, i)
  local t = pool[i]
  if not t then t = parent:CreateTexture(nil, "ARTWORK"); pool[i] = t end
  return t
end

-- Draws one edge into the tree's texture pools.
local function drawEdge(tree, e, active, n)
  local r, g, b = 0.3, 0.29, 0.27
  if active then r, g, b = 1, 0.82, 0 end
  for _, s in ipairs(e.segs) do
    n.l = n.l + 1
    local t = line(tree.edges, tree.lines, n.l)
    AFUI.SetColor(t, r, g, b, 0.95)
    local x1, y1, x2, y2 = s[1], s[2], s[3], s[4]
    t:ClearAllPoints()
    if x1 == x2 then
      t:SetWidth(3); t:SetHeight(math.max(math.abs(y2 - y1), 1))
      t:SetPoint("TOP", tree.origin, "TOPLEFT", x1 + TREE_W / 2, -(ROW1_Y + math.min(y1, y2)))
    else
      t:SetWidth(math.max(math.abs(x2 - x1), 1)); t:SetHeight(3)
      t:SetPoint("LEFT", tree.origin, "TOPLEFT", math.min(x1, x2) + TREE_W / 2, -(ROW1_Y + y1))
    end
    t:Show()
  end
  n.h = n.h + 1
  local h = line(tree.edges, tree.heads, n.h)
  h:ClearAllPoints()
  if e.head.dir == "down" then
    AFUI.SetAtlas(h, active and "talents-arrow-head-yellow" or "talents-arrow-head-gray")
    h:SetWidth(14); h:SetHeight(12)
    h:SetPoint("BOTTOM", tree.origin, "TOPLEFT", e.head.x + TREE_W / 2, -(ROW1_Y + e.head.y))
  else
    AFUI.SetColor(h, r, g, b, 0.95)
    h:SetWidth(6); h:SetHeight(8)
    h:SetPoint("CENTER", tree.origin, "TOPLEFT", e.head.x + TREE_W / 2, -(ROW1_Y + e.head.y))
  end
  h:Show()
end

local function allTalents()
  local list = {}
  for tab = 1, (GetNumTalentTabs() or 0) do
    for i = 1, (GetNumTalents(tab) or 0) do
      local name, _, _, _, rank, max = GetTalentInfo(tab, i)
      list[#list + 1] = { name = name, rank = rank or 0, max = max or 0, tab = tab, index = i }
    end
  end
  return list
end

local function applySearch()
  local text = W.search and W.search:GetText() or ""
  for _, tree in ipairs(W.trees) do
    for _, b in pairs(tree.nodes) do setShown(b.glow, b:IsShown() and Talents.Match(b.name, text)) end
  end
end

local function showPreview()
  local text = W.search:GetText() or ""
  local res = Talents.SearchResults(allTalents(), text, showRanks)
  local p = W.preview
  for i = 1, 8 do
    local row = p.rows[i]
    if res[i] then
      row.data = res[i]; row.fs:SetText(res[i].text); row:Show()
    else row:Hide() end
  end
  p:SetHeight(#res * 16 + 8)
  setShown(p, #res > 0 and W.search:HasFocus())
end

-- Every shown talent button (Audit: none may leave the window).
function Talents.Buttons()
  local out = {}
  for _, tree in ipairs(W.trees or {}) do for _, b in pairs(tree.nodes) do if b:IsShown() then out[#out + 1] = b end end end
  return out
end

-- Deepest tier that holds a talent in any of the player's trees.
function Talents.DeepestTier()
  local deepest = 0
  for t = 1, GetNumTalentTabs() or 0 do
    for i = 1, GetNumTalents(t) or 0 do
      local tier = select(3, GetTalentInfo(t, i))
      if tier and tier > deepest then deepest = tier end
    end
  end
  return deepest
end

-- Resize everything that depends on the tier count (art, veil, art box, dividers, metal frame) and the host; no-op when the height is unchanged.
local function relayout()
  local deepest = Talents.DeepestTier()
  Talents.Layout(deepest > 0 and deepest or 11)
  local h = Talents.HEIGHT
  if not W.win or W.laidOut == h then return end
  W.laidOut = h
  for _, t in ipairs(W.art) do t:SetHeight(Talents.BG_H) end
  W.artBox:SetHeight(Talents.BG_H)
  for _, d in ipairs(W.dividers) do d:SetHeight(Talents.BG_H - 75) end
  W.chromes[h] = W.chromes[h] or metalChrome(W.win, h)
  for k, c in pairs(W.chromes) do setShown(c, k == h) end
  local host = _G.PlayerTalentFrame
  host:SetHeight(h)
  Talents.Reposition(host)
end

function Talents.Update()
  if not W.win then return end
  relayout()
  local points = UnitCharacterPoints and UnitCharacterPoints("player") or 0
  W.unspent:SetText(Talents.PointsText(points))
  local numTabs = GetNumTalentTabs() or 0
  for t = 1, 3 do
    local tree = W.trees[t]
    if t > numTabs then
      tree.header:Hide(); for _, b in pairs(tree.nodes) do b:Hide() end
    else
      local name, icon, spent = GetTalentTabInfo(t)
      spent = spent or 0
      tree.header:Show()
      tree.name:SetText(name or ""); tree.points:SetText(Talents.PointsText(spent)); tree.icon:SetTexture(Talents.TabIcon(select(2, UnitClass("player")), t, icon))
      for _, l in ipairs(tree.lines) do l:Hide() end
      for _, h in ipairs(tree.heads) do h:Hide() end
      local n = { l = 0, h = 0 }
      local count = GetNumTalents(t) or 0
      for i = 1, count do
        local tname, ticon, tier, col, rank, max, _, meets = GetTalentInfo(t, i)
        local b = tree.nodes[i] or makeNode(tree.grid, t, i)
        tree.nodes[i] = b
        local x, y = Talents.NodeCenter(t, tier or 1, col or 1)
        b:ClearAllPoints(); b:SetPoint("CENTER", W.win, "TOPLEFT", x, -y)
        b.name = tname
        b.icon:SetTexture(ticon)
        local pre = { GetTalentPrereqs(t, i) }
        local met = Talents.PrereqsMet(unpack(pre)) and (meets == nil or meets) and true or false
        local unlocked = Talents.TierUnlocked(tier, spent)
        local state = Talents.NodeState(rank or 0, max or 0, unlocked, met, points)
        local st = FRAME_COLORS[state]
        AFUI.SetAtlas(b.border, st.border)
        b.icon:SetDesaturated(state == "locked" or state == "available")
        setShown(b.dim, state == "locked")
        b.shadow:SetAlpha(state == "locked" and 0.25 or 0.5)
        if (rank or 0) > 0 or state == "selectable" then
          b.rank:SetText(rank or 0); b.rank:SetTextColor(st.text[1], st.text[2], st.text[3]); b.rank:Show()
        else b.rank:Hide() end
        setShown(b.plus, state == "selectable")
        b:Show()
        for k = 1, #pre, 3 do
          drawEdge(tree, Talents.Edge(pre[k], pre[k + 1], tier, col), met and unlocked and pre[k + 2], n)
        end
      end
      for i = count + 1, #tree.nodes do tree.nodes[i]:Hide() end
    end
  end
  applySearch()
end

local function reposition(host)
  local s = Talents.FitScale(UIParent:GetWidth(), UIParent:GetHeight())
  host:SetScale(s)
  local sw, sh = Talents.WIDTH * s, Talents.HEIGHT * s
  local x, y = math.max(8, (UIParent:GetWidth() - sw) / 2) / s, -Talents.TOP / s
  host:ClearAllPoints()
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
  -- the panel manager re-anchors a shown left panel from UIPanelWindows (2.5.3: 353 x 424, x -16): give it ours so it lands in the same place
  AFUI.PanelAttrs(host, { width = sw, height = sh, xoffset = x, yoffset = y, bottomClampOverride = -100000 })
  if AFUI.WinKit and host.afMoveKey then AFUI.WinKit.applyPos(host) end -- the player's own spot wins over the default
end

Talents.Reposition = reposition

local function makeSearch(win, level)
  local e = CreateFrame("EditBox", "AFUI_TalentsSearch", win, "InputBoxTemplate")
  e:SetAutoFocus(false); e:SetHeight(20); e:SetWidth(187); e:SetMaxLetters(30); e:SetFrameLevel(level)
  for _, k in ipairs({ "Left", "Middle", "Right" }) do local t = _G["AFUI_TalentsSearch" .. k]; if t then t:Hide() end end
  local bg = e:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(bg, 0, 0, 0, 0.85)
  bg:SetPoint("TOPLEFT", e, "TOPLEFT", -2, 0); bg:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 2, 0)
  local function edge(p1, p2, w, h, x, y, ...)
    local t = e:CreateTexture(nil, "BORDER"); AFUI.SetColor(t, 0.62, 0.52, 0.36, 1); t:SetPoint(p1, e, p1, -2, y); t:SetPoint(p2, e, p2, 2, y)
    t:SetHeight(1); return t
  end
  edge("TOPLEFT", "TOPRIGHT", nil, nil, 0, 0); edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, nil, 0, 0)
  local vl = e:CreateTexture(nil, "BORDER"); AFUI.SetColor(vl, 0.62, 0.52, 0.36, 1); vl:SetWidth(1); vl:SetPoint("TOPLEFT", e, "TOPLEFT", -2, 0); vl:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT", -2, 0)
  local vr = e:CreateTexture(nil, "BORDER"); AFUI.SetColor(vr, 0.62, 0.52, 0.36, 1); vr:SetWidth(1); vr:SetPoint("TOPRIGHT", e, "TOPRIGHT", 2, 0); vr:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 2, 0)
  local mag = atlas(e, "OVERLAY", "common-search-magnifyingglass", 11, 11); mag:SetPoint("LEFT", e, "LEFT", 3, -1)
  e:SetTextInsets(19, 8, 0, 0)
  e.hint = e:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  e.hint:SetPoint("LEFT", e, "LEFT", 19, 0); e.hint:SetText(SEARCH or "Search")
  e:SetScript("OnTextChanged", function(self)
    setShown(self.hint, self:GetText() == "" and not self:HasFocus())
    applySearch(); showPreview()
  end)
  e:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus(); W.preview:Hide() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus(); W.preview:Hide() end)
  e:SetScript("OnEditFocusGained", function(self) self.hint:Hide(); showPreview() end)
  e:SetScript("OnEditFocusLost", function(self) setShown(self.hint, self:GetText() == ""); W.preview:Hide() end)
  return e
end

function Talents.Build()
  local host = _G.PlayerTalentFrame
  if W.win or not host then return end
  local level = host:GetFrameLevel()
  quiet(host)
  host:SetWidth(Talents.WIDTH); host:SetHeight(Talents.HEIGHT)
  host:SetFrameStrata("HIGH") -- over the action bars and the minimap, like the bag windows
  local win = CreateFrame("Frame", "AFUI_TalentsWindow", host)
  win:SetAllPoints(host); win:SetFrameLevel(level + 1)
  W.win = win
  W.art, W.dividers, W.chromes = {}, {}, {}

  -- panel (the dark fill under tabs and search row), class art over the three trees
  local panel = win:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(panel, 0.1, 0.09, 0.085, 1)
  panel:SetPoint("TOPLEFT", win, "TOPLEFT", 2, -21); panel:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -2, 2)
  local _, token = UnitClass("player")
  local f1, f2 = Talents.BackgroundFile(token)
  if f1 then
    for i, f in ipairs({ f1, f2 }) do
      local t = win:CreateTexture(nil, "BORDER"); t:SetTexture(f)
      W.art[#W.art + 1] = t; t:SetWidth(BG_W / 2); t:SetHeight(Talents.BG_H); t:SetPoint("TOPLEFT", win, "TOPLEFT", BG_X + (i - 1) * BG_W / 2, -BG_Y)
    end
    -- the capture's tree art is muted (mean luma ~34 / 255 against the client art's ~40, far less saturated): a dark veil over the three pictures
    local veil = win:CreateTexture(nil, "BORDER"); AFUI.SetColor(veil, 0.03, 0.03, 0.03, 0.42)
    veil:SetPoint("TOPLEFT", win, "TOPLEFT", BG_X, -BG_Y); W.art[#W.art + 1] = veil; veil:SetWidth(BG_W); veil:SetHeight(Talents.BG_H)
  end
  local artBox = CreateFrame("Frame", nil, win); artBox:SetFrameLevel(level + 3)
  artBox:SetPoint("TOPLEFT", win, "TOPLEFT", BG_X, -BG_Y); artBox:SetWidth(BG_W); artBox:SetHeight(Talents.BG_H); W.artBox = artBox
  local border = artBox:CreateTexture(nil, "OVERLAY"); border:SetPoint("TOPLEFT", artBox, "TOPLEFT", -2, 4); border:SetPoint("BOTTOMRIGHT", artBox, "BOTTOMRIGHT", 2, -4)
  nineSlice(artBox, "OVERLAY", "talents-inner-frame-c60", 20, border)
  -- gold band under the title (Talents-divider-left/right: two halves meeting in the middle)
  -- the left half is laid out from its left end so it ends at the middle
  local lw = AFUI_ATLAS["talents-divider-left-c60__1"][2] + AFUI_ATLAS["talents-divider-left-c60__2"][2]
  tiles(artBox, "OVERLAY", "talents-divider-left-c60", "TOPLEFT", artBox, "TOP", -lw, 2)
  tiles(artBox, "OVERLAY", "talents-divider-right-c60", "TOPLEFT", artBox, "TOP", 0, 2)
  for i, x in ipairs({ 406, 810 }) do -- the capture's column separators
    local d = atlas(artBox, "OVERLAY", "talents-divider-vertical-c60", 2, Talents.BG_H - 75); W.dividers[#W.dividers + 1] = d
    d:SetPoint("TOPLEFT", win, "TOPLEFT", x - 1, -150)
  end

  -- trees: header (ring + icon + points badge + name + rule) and the node grid
  W.trees = {}
  for t = 1, 3 do
    local left = TREE_CX[t] - TREE_W / 2
    local tree = { nodes = {}, lines = {}, heads = {} }
    local hdr = CreateFrame("Frame", nil, win); hdr:SetFrameLevel(level + 8)
    hdr:SetWidth(TREE_W); hdr:SetHeight(100); hdr:SetPoint("TOPLEFT", win, "TOPLEFT", left, -(BG_Y + 20))
    tree.header = hdr
    local rule = atlas(hdr, "ARTWORK", "talents-small-divider-c60", 355, 64)
    rule:SetPoint("BOTTOM", win, "TOPLEFT", left + TREE_W / 2, -215)
    tree.icon = hdr:CreateTexture(nil, "BORDER"); tree.icon:SetWidth(32); tree.icon:SetHeight(32)
    tree.icon:SetPoint("CENTER", win, "TOPLEFT", left + 131, -171)
    tree.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local ring = atlas(hdr, "OVERLAY", "talents-main-ring-c60", 55, 55); ring:SetPoint("CENTER", tree.icon, "CENTER")
    local box = atlas(hdr, "OVERLAY", "talents-main-ring-box-c60", 24, 20); box:SetPoint("CENTER", tree.icon, "CENTER", 14, -12)
    box:SetVertexColor(0.35, 0.3, 0.25)
    tree.points = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal"); tree.points:SetPoint("CENTER", box, "CENTER", 0, 0)
    tree.name = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    tree.name:SetPoint("LEFT", tree.icon, "CENTER", 33, 0)
    local grid = CreateFrame("Frame", nil, win); grid:SetFrameLevel(level + 6); grid:SetAllPoints(win)
    tree.grid = grid
    tree.edges = CreateFrame("Frame", nil, win); tree.edges:SetFrameLevel(level + 5); tree.edges:SetAllPoints(win)
    -- tree.origin: where tree-relative x = -TREE_W / 2 maps to (x offsets above add TREE_W / 2)
    tree.origin = CreateFrame("Frame", nil, win); tree.origin:SetWidth(1); tree.origin:SetHeight(1)
    tree.origin:SetPoint("TOPLEFT", win, "TOPLEFT", TREE_CX[t] - TREE_W / 2, 0)
    W.trees[t] = tree
  end

  -- metal frame with the class emblem corner, title, red close button
  W.level = level
  W.chromes[Talents.HEIGHT] = metalChrome(win, Talents.HEIGHT); W.laidOut = Talents.HEIGHT
  local portrait = win:CreateTexture(nil, "ARTWORK")
  portrait:SetWidth(62); portrait:SetHeight(62); portrait:SetPoint("TOPLEFT", win, "TOPLEFT", -5, 7)
  AFUI.WindowPortrait(win, portrait) -- the round opening of the corner ring, cut into strips
  portrait:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
  local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token or ""]
  if c then portrait:SetTexCoord(Talents.CrestCoords(c)) end
  local labels = CreateFrame("Frame", nil, win); labels:SetFrameLevel(level + 25); labels:SetAllPoints(win)
  local title = labels:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", win, "TOP", 0, -6)
  title:SetText(TALENTS or "Talents")
  local drag = CreateFrame("Frame", nil, win); drag:SetFrameLevel(level + 21)
  drag:SetPoint("TOPLEFT", win, "TOPLEFT", 58, 0); drag:SetPoint("TOPRIGHT", win, "TOPRIGHT", -62, 0); drag:SetHeight(20)
  local close = CreateFrame("Button", nil, win)
  close:SetWidth(28); close:SetHeight(28); close:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 3); close:SetFrameLevel(level + 30)
  AFUI.SetButtonAtlas(close, { "redbutton-exit", "redbutton-exit-pressed", "redbutton-highlight", "redbutton-exit-disabled" })
  close:SetScript("OnClick", function() HideUIPanel(host) end)

  -- Unspent Talents
  local ub = CreateFrame("Frame", nil, win); ub:SetFrameLevel(level + 8); ub:SetAllPoints(win)
  local box = atlas(ub, "ARTWORK", "talents-square-box-c60", 125, 45); box:SetPoint("TOPRIGHT", win, "TOPRIGHT", -27, -82)
  local lab = ub:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lab:SetPoint("RIGHT", box, "RIGHT", -62, 0); lab:SetText(UNSPENT_POINTS or "Unspent Talents")
  W.unspent = ub:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  W.unspent:SetFont("Fonts\\FRIZQT__.TTF", 26); W.unspent:SetPoint("CENTER", box, "RIGHT", -33, 0)

  -- Search box + options dropdown, bottom left
  local sf = CreateFrame("Frame", nil, win); sf:SetFrameLevel(level + 10); sf:SetAllPoints(win)
  W.search = makeSearch(win, level + 12)
  W.search:SetPoint("TOPLEFT", win, "TOPLEFT", 996, -43)
  local dd = CreateFrame("Button", nil, win)
  dd:SetWidth(18); dd:SetHeight(18); dd:SetFrameLevel(level + 12); dd:SetPoint("LEFT", W.search, "RIGHT", 8, 0)
  AFUI.SetButtonAtlas(dd, { "common-dropdown-a-button", "common-dropdown-a-button-pressed", "common-dropdown-a-button-hover", "common-dropdown-a-button-disabled" }, 0.6)
  -- the results list (above the box) and the options menu (above the arrow)
  local p = CreateFrame("Frame", nil, win); p:SetFrameLevel(level + 40); p:SetWidth(220); p:SetHeight(20)
  p:SetPoint("TOPLEFT", W.search, "BOTTOMLEFT", 0, -4); p:Hide(); p.rows = {}
  local pbg = p:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(pbg, 0.05, 0.05, 0.05, 0.95); pbg:SetAllPoints(p)
  for i = 1, 8 do
    local r = CreateFrame("Button", nil, p)
    r:SetHeight(16); r:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -4 - (i - 1) * 16); r:SetPoint("TOPRIGHT", p, "TOPRIGHT", -4, -4 - (i - 1) * 16)
    r.fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.fs:SetPoint("LEFT", r, "LEFT", 2, 0)
    local h = r:CreateTexture(nil, "HIGHLIGHT"); AFUI.SetColor(h, 1, 1, 1, 0.15); h:SetAllPoints(r)
    r:SetScript("OnMouseDown", function(self)
      W.search:SetText(self.data.name); W.search:ClearFocus(); applySearch(); p:Hide()
    end)
    p.rows[i] = r
  end
  W.preview = p
  local menu = CreateFrame("Frame", nil, win); menu:SetFrameLevel(level + 40); menu:SetWidth(170); menu:SetHeight(26)
  menu:SetPoint("TOPRIGHT", dd, "BOTTOMRIGHT", 0, -4); menu:Hide()
  local mbg = menu:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(mbg, 0.05, 0.05, 0.05, 0.95); mbg:SetAllPoints(menu)
  local opt = CreateFrame("Button", nil, menu); opt:SetAllPoints(menu)
  local tick = atlas(opt, "OVERLAY", "checkmark-minimal", 14, 14); tick:SetPoint("LEFT", opt, "LEFT", 6, 0); tick:Hide()
  local ofs = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ofs:SetPoint("LEFT", opt, "LEFT", 24, 0); ofs:SetText("Show ranks in search")
  opt:SetScript("OnClick", function() showRanks = not showRanks; setShown(tick, showRanks) end)
  dd:SetScript("OnClick", function() setShown(menu, not menu:IsShown()) end)
  win:HookScript("OnHide", function() menu:Hide(); p:Hide() end)

  host:HookScript("OnShow", function() reposition(host); Talents.Update() end)
  reposition(host)
  if AFUI.WinKit then AFUI.WinKit.makeMovable(host, drag, "talents", { place = reposition }); reposition(host) end
  Talents.Update()
end

AFUI.On("ADDON_LOADED", function(_, addon) if addon == "Blizzard_TalentUI" then Talents.Build() end end)
AFUI.On("CHARACTER_POINTS_CHANGED", function() if W.win and _G.PlayerTalentFrame:IsShown() then Talents.Update() end end)
AFUI.On("SPELLS_CHANGED", function() if W.win and _G.PlayerTalentFrame:IsShown() then Talents.Update() end end)
for _, e in ipairs(AFUI.SCREEN_EVENTS or {}) do
  AFUI.On(e, function() if W.win then reposition(_G.PlayerTalentFrame) end end)
end
AFUI.RegisterModule("Talents", { OnLogin = function() if _G.PlayerTalentFrame then Talents.Build() end end })
