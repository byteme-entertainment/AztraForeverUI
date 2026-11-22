-- Forever's Professions windows: the "Professions" overview (K) and the crafting window (Blizzard's TradeSkillFrame / CraftFrame restyled).
-- Forever reference (tools/ref/interface/addons/): blizzard_professionsbook/camelot/blizzard_professionsbooktemplates.xml (the overview: two 664x142
-- primary cards, three 225x275 secondary cards, spell buttons, rank bars, unlearn X), blizzard_professions/camelot/blizzard_professionsframe.{xml,lua}
-- and blizzard_professionscrafting.{xml,lua} (ONE 673x594 frame, overview page + crafting page, side tabs at TOPRIGHT y -60, rank bar at
-- 110,-40, recipe list at 5,-72 / 304 wide, recipe pane 360 wide), blizzard_professionstemplates/blizzard_professionsrankbar.* (bar art),
-- ...recipelist.xml (header / recipe rows), look = docs/forever-ref/screens/windows/professions-*.png, profession-*.png.
-- Client facts (verified): 2.4.3 MOUZU/Blizzard-WoW-Interface 2.4.3/AddOns/Blizzard_TradeSkillUI + Blizzard_CraftUI (.xml/.lua) and 2.5.3
-- Gethe/wow-ui-source tag 2.5.3 Interface_TBC/AddOns/Blizzard_TradeSkillUI.xml + Blizzard_CraftUI (.xml/.lua) with Interface/AddOns/Blizzard_TradeSkillUI.lua:
-- both are load-on-demand, have TradeSkillFrame / CraftFrame with TRADE_SKILLS_DISPLAYED / CRAFTS_DISPLAYED (8) rows named TradeSkillSkill<i> /
-- Craft<i>, a StatusBar TradeSkillRankFrame / CraftRankFrame, a detail ScrollFrame (name, icon, requirements, reagents 1-8), no skill link button and
-- no recipe tracker. 2.4.3 has a search EditBox (TradeSkillFrameEditBox / CraftFrameEditBox), 2.5.3 does not. The professions themselves are
-- GetNumSkillLines / GetSkillLineInfo (no GetProfessions on either client).
AFUI = AFUI or {}
local P = {}
AFUI.Professions = P

local PLAIN = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\"
local FRAME_W, FRAME_H = 673, 594 -- ProfessionsFrame (blizzard_professions/camelot/blizzard_professionsframe.xml:15)
local ROCK_TINT = { 0.42, 0.37, 0.33 }
local WHITE_TEXT = { 1, 1, 1 }

---------------------------------------------------------------- data (pure)
-- kind: primary / secondary; kit: the atlas kit name (Professions.GetAtlasKitSpecifier); main: a spell whose name is the skill's name (for other
-- locales); spells: what the overview shows as buttons ({ id, English name }, shown only when the spellbook has it); tab: the spell the side tab
-- casts (nil = no window to open); icon: the side tab / portrait icon.
local DEF = {
  ["Alchemy"] = { kind = "primary", kit = "alchemy", main = 2259, icon = "Trade_Alchemy", spells = { { 2259, "Alchemy" } } },
  ["Blacksmithing"] = { kind = "primary", kit = "blacksmithing", main = 2018, icon = "Trade_BlackSmithing", spells = { { 2018, "Blacksmithing" } } },
  ["Enchanting"] = { kind = "primary", kit = "enchanting", main = 7411, icon = "Trade_Engraving", spells = { { 7411, "Enchanting" }, { 13262, "Disenchant" } } },
  ["Engineering"] = { kind = "primary", kit = "engineering", main = 4036, icon = "Trade_Engineering", spells = { { 4036, "Engineering" } } },
  ["Herbalism"] = { kind = "primary", kit = "herbalism", icon = "Trade_Herbalism", spells = { { 2383, "Find Herbs" } }, noTab = true },
  ["Jewelcrafting"] = { kind = "primary", kit = "jewelcrafting", main = 25229, icon = "INV_Misc_Gem_01", spells = { { 25229, "Jewelcrafting" }, { 31252, "Prospecting" } } },
  ["Leatherworking"] = { kind = "primary", kit = "leatherworking", main = 2108, icon = "Trade_LeatherWorking", spells = { { 2108, "Leatherworking" } } },
  ["Mining"] = { kind = "primary", kit = "mining", icon = "Trade_Mining", spells = { { 2656, "Smelting" }, { 2580, "Find Minerals" } } },
  ["Skinning"] = { kind = "primary", kit = "skinning", icon = "INV_Misc_Pelt_Wolf_01", spells = {}, noTab = true },
  ["Tailoring"] = { kind = "primary", kit = "tailoring", main = 3908, icon = "Trade_Tailoring", spells = { { 3908, "Tailoring" } } },
  ["Cooking"] = { kind = "secondary", kit = "cooking", main = 2550, icon = "INV_Misc_Food_15", spells = { { 2550, "Cooking" } } },
  -- Forever lists Bait and Tackle first: the capture stacks Fishing above it (SpellButton1 is the bottom one)
  ["Fishing"] = { kind = "secondary", kit = "fishing", main = 7620, tab = 7620, icon = "Trade_Fishing", spells = { { 0, "Bait and Tackle" }, { 7620, "Fishing" } } },
  ["First Aid"] = { kind = "secondary", kit = "firstaid", main = 3273, icon = "Spell_Holy_SealOfSacrifice", spells = { { 3273, "First Aid" } } },
}
P.DEF = DEF
-- bars with their own fill art (the rest use Forever's default blue); card art exists for these primaries (the others use the generic card)
local FILL = { alchemy = 1, blacksmithing = 1, cooking = 1, enchanting = 1, engineering = 1, fishing = 1, herbalism = 1, jewelcrafting = 1, leatherworking = 1, mining = 1, skinning = 1, tailoring = 1 }
local FLARE = FILL
local CARD = { alchemy = 1, blacksmithing = 1, enchanting = 1, engineering = 1, herbalism = 1, leatherworking = 1, mining = 1, skinning = 1, tailoring = 1 }
local BACKGROUND = { alchemy = 1, blacksmithing = 1, cooking = 1, enchanting = 1, engineering = 1, firstaid = 1, leatherworking = 1, mining = 1, tailoring = 1 }
local SECONDARY_ORDER = { "First Aid", "Fishing", "Cooking" } -- GetProfessions: prof1, prof2, first aid, fishing, cooking (camelot RefreshRightTabs)

-- localized skill line name -> canonical key (spells whose name is the skill name); built lazily
local localized
local function canonical(name)
  if DEF[name] then return name end
  if not localized then
    localized = {}
    for key, d in pairs(DEF) do
      if d.main and GetSpellInfo then
        local n = GetSpellInfo(d.main)
        if n then localized[n] = key end
      end
    end
  end
  return localized[name]
end
P.Canonical = canonical

-- lines = { { name, header, rank, max, mod, abandonable, index }, ... } (GetSkillLineInfo order).
-- Returns { primary = { line, line }, cooking = line, fishing = line, firstaid = line }; each line carries .key.
function P.Classify(lines)
  local out = { primary = {} }
  for _, l in ipairs(lines) do
    local key = not l.header and canonical(l.name)
    local d = key and DEF[key]
    if d then
      l.key = key
      if d.kind == "primary" then
        if #out.primary < 2 then out.primary[#out.primary + 1] = l end
      else
        out[d.kit] = out[d.kit] or l
      end
    end
  end
  return out
end

-- Side tab order: first profession, second, first aid, fishing, cooking; only ones that open a window by a spell.
function P.TabList(c)
  local list = {}
  local function add(l) if l and not DEF[l.key].noTab then list[#list + 1] = l end end
  for _, l in ipairs(c.primary) do add(l) end
  for _, key in ipairs(SECONDARY_ORDER) do add(c[DEF[key].kit]) end
  return list
end

-- Blizzard's PROFESSION_RANKS (blizzard_professionsbook.lua:1-12): 75 Apprentice, 150 Journeyman, 225 Expert, 300 Artisan, 375 Master.
local RANKS = { { 75, "APPRENTICE", "Apprentice" }, { 150, "JOURNEYMAN", "Journeyman" }, { 225, "EXPERT", "Expert" }, { 300, "ARTISAN", "Artisan" }, { 375, "MASTER", "Master" } }
function P.RankTitle(max)
  local t = ""
  for _, r in ipairs(RANKS) do
    if max < r[1] then break end
    t = _G[r[2]] or r[3]
  end
  return t
end

-- Rank bar text (TRADESKILL_NAME_RANK / TRADESKILL_NAME_RANK_WITH_MODIFIER): "Tailoring 68/150", "Tailoring 68 (+5)/150".
function P.RankText(name, rank, max, mod)
  if mod and mod > 0 then return string.format("%s %d (+%d)/%d", name, rank, mod, max) end
  return string.format("%s %d/%d", name, rank, max)
end

-- Share of the bar that is full (0..1).
function P.Ratio(rank, max)
  if not max or max <= 0 then return 0 end
  return math.max(0, math.min(rank / max, 1))
end

-- Visible fill width of a bar (ProfessionsRankBarMixin:GetMaskWidth: width * progress + the mask's right offset), at most the fill's own width.
function P.FillWidth(ratio, barWidth, maskOffset, fillWidth)
  return math.max(0, math.min(barWidth * ratio + (maskOffset or 0), fillWidth))
end

function P.FillAtlas(kit) return "skillbar_fill_flipbook_" .. (FILL[kit] and kit or "tailoring") end -- Forever's default blue is a different strip: tailoring is the same blue
function P.FlareAtlas(kit) return FLARE[kit] and ("skillbar_flare_" .. kit) or nil end
function P.CardAtlas(kit, primary)
  if primary then return "profession-overview-card-" .. (CARD[kit] and (kit .. "-c60") or "c60") end
  return "profession-overview-card-generic-" .. kit .. "-c60"
end
function P.BackgroundAtlas(kit) return BACKGROUND[kit] and ("profession-background-card-" .. kit .. "-c60") or nil end

-- Recipe difficulty -> Forever's skill-up arrow (professions-icon-skill-*); trivial recipes and headers have none.
local DIFFICULTY = { optimal = "professions-icon-skill-high", medium = "professions-icon-skill-medium", easy = "professions-icon-skill-low" }
function P.DifficultyIcon(skillType) return DIFFICULTY[skillType] end

-- Recipe rows that fit under the list top: `height` px of list, `step` px per row.
function P.VisibleRows(height, step) return math.max(1, math.floor(height / step)) end

-- Spells to show for a profession: the ones the spellbook knows. known(name) -> rank text or nil. Returns { { name, rank, id }, ... }, at most `max`.
function P.SpellsFor(key, known, max)
  local out = {}
  local d = DEF[key]
  if not d then return out end
  for _, s in ipairs(d.spells) do
    local name = (s[1] > 0 and GetSpellInfo and GetSpellInfo(s[1])) or s[2]
    local rank = known(name)
    if rank then
      out[#out + 1] = { name = name, rank = rank, id = s[1] }
      if #out >= (max or 2) then break end
    end
  end
  return out
end

-- The window's side tab strip: overview first, then the professions. Returns the key of the selected tab (an overview page or a skill name).
function P.SelectedTab(overviewShown, openName)
  if overviewShown then return "overview" end
  return openName
end

---------------------------------------------------------------- skills and spells (client)
local linesCache, seen = nil, {}
-- Skill lines of GetSkillLineInfo, read once and kept until SKILL_LINES_CHANGED. The player's Skills tab is never touched (no Expand /
-- CollapseSkillHeader: that changed what the tab shows and fired SKILL_LINES_CHANGED again). A header the player collapsed hides its lines,
-- so those come from the last time the header was open (stale = true, no index: AbandonSkill needs a visible one).
-- shortcut: a header collapsed since before login has no memory, its professions read as not learned until it is opened once.
function P.ReadLines(fresh)
  if linesCache and not fresh then return linesCache end
  local lines, header, open = {}, nil, false
  for i = 1, GetNumSkillLines() do
    local name, isHeader, expanded, rank, _, mod, max, abandonable = GetSkillLineInfo(i)
    local l = { name = name, header = isHeader and true or false, rank = rank or 0, max = max or 0, mod = mod or 0, abandonable = abandonable, index = i }
    lines[#lines + 1] = l
    if isHeader then
      header, open = name, expanded and true or false
      if open then seen[name] = {} else
        for _, old in ipairs(seen[name] or {}) do lines[#lines + 1] = { name = old.name, header = false, rank = old.rank, max = old.max, mod = old.mod, stale = true } end
      end
    elseif header and open then
      seen[header][#seen[header] + 1] = l
    end
  end
  linesCache = lines
  return lines
end

-- name -> highest rank text of that spellbook spell ("" when it has none), index of that spell
local bookCache
local function book()
  if bookCache then return bookCache end
  bookCache = {}
  local i = 1
  while true do
    local n, r = AFUI.SpellBookName(i, "spell")
    if not n then break end
    bookCache[n] = { r or "", i }
    i = i + 1
  end
  return bookCache
end
local function known(name) local e = book()[name]; return e and e[1] end
function P.SpellIndex(name) local e = book()[name]; return e and e[2] end

---------------------------------------------------------------- small helpers
local function setShown(o, on) if on then o:Show() else o:Hide() end end
local function atlasTex(parent, layer, name, w, h)
  local t = parent:CreateTexture(nil, layer)
  AFUI.SetAtlas(t, name)
  if w then t:SetWidth(w); t:SetHeight(h or w) end
  return t
end
local function crop(t, name, frac, vertical) -- keep the first `frac` of an atlas (a shortened last tile of an edge, a bar fill)
  local e = AFUI_ATLAS and AFUI_ATLAS[string.lower(name)]
  if not e then return end
  if vertical then t:SetTexCoord(e[4], e[5], e[6], e[6] + (e[7] - e[6]) * frac)
  else t:SetTexCoord(e[4], e[4] + (e[5] - e[4]) * frac, e[6], e[7]) end
end
-- A Blizzard piece we do not use that the client's update functions Show() again every time (CraftFrame_Update shows the rank bar, its
-- borders, the filter drop down and the Have Materials box; TradeSkillFrame_OnShow does Hide / Show on both drop downs; the detail scroll bar
-- and its top / bottom caps come back with every detail update): one Hide is not enough. Frames move under a hidden parent (their Show then
-- draws nothing and keeps their state), regions get a Show hook that hides them again.
local limbo
local function banish(o)
  if not o or o.afBanished then return end
  o.afBanished = true
  if o.HookScript then
    limbo = limbo or CreateFrame("Frame", nil, UIParent)
    limbo:Hide()
    o:SetParent(limbo); o:Hide()
  else
    o:Hide()
    hooksecurefunc(o, "Show", function(self) self:Hide() end)
  end
end
P.Banish = banish

local function fontString(parent, layer, font, text)
  local f = parent:CreateFontString(nil, layer, font)
  if text then f:SetText(text) end
  return f
end

-- Forever's metal frame with the portrait corner (the Bags / World Map windows draw the same pieces).
local VERTICAL = { ["!ui-frame-metal-edgeleft-c60-2x"] = true, ["!ui-frame-metal-edgeright-c60-2x"] = true }
local function skin(chromeFrame, w, h)
  if chromeFrame.skinW == w and chromeFrame.skinH == h then return end
  chromeFrame.skinW, chromeFrame.skinH = w, h
  chromeFrame.pieces = chromeFrame.pieces or {}
  local pcs = AFUI.WorldMapPieces(w, h, true)
  for i, p in ipairs(pcs) do
    local t = chromeFrame.pieces[i]
    if not t then t = chromeFrame:CreateTexture(nil, "OVERLAY"); chromeFrame.pieces[i] = t end
    AFUI.SetAtlas(t, p.atlas)
    if p.crop and p.crop < 1 then crop(t, p.atlas, p.crop, VERTICAL[p.atlas]) end
    t:SetWidth(p.w); t:SetHeight(p.h)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", chromeFrame, "TOPLEFT", p.x, p.y)
    t:Show()
  end
  for i = #pcs + 1, #chromeFrame.pieces do chromeFrame.pieces[i]:Hide() end
end

-- Window chrome on `host` (our own frame or Blizzard's): stone fill, metal frame (above the content), labels layer (title) above the frame.
local function chrome(host, w, h)
  host:SetWidth(w); host:SetHeight(h)
  if not host.afChrome then
    local bg = host:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(PLAIN .. "UI-Background-Rock"); bg:SetVertexColor(ROCK_TINT[1], ROCK_TINT[2], ROCK_TINT[3])
    bg:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -21); bg:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)
    -- the 512 px stone repeats over the 673 x 594 window: tiled where the client can (2.5.3), else the texcoords repeat it (2.4.3 has no
    -- SetHorizTile / SetVertTile; the file is a power of two, like WorldMap.lua's Rock)
    if type(bg.SetHorizTile) == "function" and type(bg.SetVertTile) == "function" then bg:SetHorizTile(true); bg:SetVertTile(true)
    else bg:SetTexCoord(0, (w - 4) / 512, 0, (h - 23) / 512) end
    host.afBg = bg
    host.afPortrait = host:CreateTexture(nil, "ARTWORK")
    host.afPortrait:SetWidth(62); host.afPortrait:SetHeight(62); host.afPortrait:SetPoint("TOPLEFT", host, "TOPLEFT", -5, 7)
    host.afPortrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    AFUI.WindowPortrait(host, host.afPortrait)
    local c = CreateFrame("Frame", nil, host)
    c:SetAllPoints(host); c:SetFrameLevel(host:GetFrameLevel() + 10)
    host.afChrome = c
    local labels = CreateFrame("Frame", nil, host)
    labels:SetAllPoints(host); labels:SetFrameLevel(host:GetFrameLevel() + 25)
    host.afLabels = labels
  end
  skin(host.afChrome, w, h)
end

local function setPortrait(host, icon)
  host.afPortrait:SetTexture(AFUI.IconPath(icon))
end

-- Plain red X on the corner (Forever's close button), 28x28 at TOPRIGHT 0,3.
local function closeButton(btn, host)
  btn.afOverhang = true -- 3 px above the window edge on purpose (the audit skips it)
  btn:ClearAllPoints(); btn:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 3)
  btn:SetWidth(28); btn:SetHeight(28); btn:SetFrameLevel(host:GetFrameLevel() + 30)
  AFUI.SetButtonAtlas(btn, { "redbutton-exit", "redbutton-exit-pressed", "redbutton-highlight", "redbutton-exit-disabled" })
end

---------------------------------------------------------------- one window: one size, one spot
-- The overview, TradeSkillFrame and CraftFrame are pages of ONE Professions window: the same 673 x 594 frame at the same TOPLEFT (the saved spot
-- "professions" when the player moved it, else the left panel origin) with the same tab column, title and portrait.
local function origin() return AFUI.WinKit and AFUI.WinKit.ORIGIN or { x = 17, y = -116 } end

function P.Place(f)
  if InCombatLockdown() then return end -- the pages carry secure tabs
  f:SetWidth(FRAME_W); f:SetHeight(FRAME_H)
  if f.GetScale and f.SetScale and math.abs((f:GetScale() or 1) - 1) > 0.001 then f:SetScale(1) end -- one scale on every page (the client's frames may carry their own)
  if not (AFUI.WinKit and AFUI.WinKit.applyPos(f)) then
    local O = origin()
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", O.x, O.y)
  end
end

---------------------------------------------------------------- popup menu (chat link, filter)
-- entries: { text, title = true | checked = bool, func = fn, disabled = bool, color = {r,g,b} } -> a small dark list under `anchor`.
local popup
local function hidePopup() if popup then popup:Hide() end end
function P.ShowMenu(anchor, entries, point, relPoint, x, y)
  if not popup then
    popup = CreateFrame("Frame", "AFUI_ProfessionsMenu", UIParent)
    popup:SetFrameStrata("FULLSCREEN_DIALOG"); popup:EnableMouse(true); popup:SetClampedToScreen(true)
    popup.bg = popup:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(popup.bg, 0.03, 0.03, 0.03, 0.96); popup.bg:SetAllPoints(popup)
    popup.edge = popup:CreateTexture(nil, "BORDER"); AFUI.SetColor(popup.edge, 0.45, 0.37, 0.2, 1); popup.edge:SetPoint("TOPLEFT", popup, -1, 1); popup.edge:SetPoint("BOTTOMRIGHT", popup, 1, -1)
    popup.edge:SetDrawLayer("BACKGROUND", -1)
    popup.rows = {}
    popup:Hide()
    popup:SetScript("OnUpdate", function(self)
      if self:IsShown() and IsMouseButtonDown and IsMouseButtonDown("LeftButton") and not MouseIsOver(self) and not (self.anchor and MouseIsOver(self.anchor)) then self:Hide() end
    end)
    table.insert(UISpecialFrames, "AFUI_ProfessionsMenu")
  end
  if popup:IsShown() and popup.anchor == anchor then popup:Hide(); return end
  popup.anchor = anchor
  local w = 150
  for i, e in ipairs(entries) do
    local r = popup.rows[i]
    if not r then
      r = CreateFrame("Button", nil, popup)
      r:SetHeight(24)
      r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); r.text:SetPoint("LEFT", r, "LEFT", 14, 0); r.text:SetJustifyH("LEFT")
      r.check = r:CreateTexture(nil, "ARTWORK"); r.check:SetWidth(12); r.check:SetHeight(12); r.check:SetPoint("LEFT", r, "LEFT", 2, 0)
      r.check:SetTexture(PLAIN .. "UI-CheckBox-Check"); r.check:SetTexCoord(0, 1, 0, 1)
      r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(r); r.hl:SetBlendMode("ADD"); AFUI.SetColor(r.hl, 1, 0.82, 0, 0.18)
      r:SetScript("OnClick", function(self) if self.func then popup:Hide(); self.func() end end)
      popup.rows[i] = r
    end
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", popup, "TOPLEFT", 6, -6 - (i - 1) * 24); r:SetWidth(w)
    r.text:SetText(e.text); r.func = e.func
    local c = e.color or (e.title and { 1, 0.82, 0 }) or (e.disabled and { 0.5, 0.5, 0.5 }) or { 1, 1, 1 }
    r.text:SetTextColor(c[1], c[2], c[3])
    setShown(r.check, e.checked and true or false)
    if e.disabled or e.title then r:Disable() else r:Enable() end
    r:Show()
  end
  for i = #entries + 1, #popup.rows do popup.rows[i]:Hide() end
  popup:SetWidth(w + 12); popup:SetHeight(#entries * 24 + 12)
  popup:ClearAllPoints(); popup:SetPoint(point or "TOPLEFT", anchor, relPoint or "BOTTOMLEFT", x or 0, y or -2)
  popup:Show()
end

---------------------------------------------------------------- rank bar widget
-- ProfessionsRankBarTemplate: background, fill (the first frame of the profession's art, cut to the share), flare ADD at its end, frame, text.
local FLARE_W = 53
local function newBar(parent, o)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetWidth(o.width); bar:SetHeight(18)
  bar.o = o
  bar.bg = atlasTex(bar, "ARTWORK", o.bg); bar.bg:SetPoint("TOPLEFT", bar, "TOPLEFT"); bar.bg:SetWidth(o.width); bar.bg:SetHeight(o.bgHeight)
  bar.bg:SetDrawLayer("ARTWORK", 1)
  bar.fill = bar:CreateTexture(nil, "ARTWORK"); bar.fill:SetDrawLayer("ARTWORK", 2)
  bar.flare = bar:CreateTexture(nil, "ARTWORK"); bar.flare:SetDrawLayer("ARTWORK", 2); bar.flare:SetBlendMode("ADD")
  bar.flare:SetWidth(FLARE_W); bar.flare:SetHeight(16)
  -- the skill-up glow: a second flare (twice the light at the leading edge) and a soft wash over the fill, both only while the animation runs
  bar.spark = bar:CreateTexture(nil, "ARTWORK"); bar.spark:SetDrawLayer("ARTWORK", 2); bar.spark:SetBlendMode("ADD")
  bar.spark:SetWidth(FLARE_W); bar.spark:SetHeight(16); bar.spark:Hide()
  bar.sweep = bar:CreateTexture(nil, "ARTWORK"); bar.sweep:SetDrawLayer("ARTWORK", 2); bar.sweep:SetBlendMode("ADD")
  AFUI.SetColor(bar.sweep, 1, 0.9, 0.55, 1); bar.sweep:SetAllPoints(bar.fill); bar.sweep:SetAlpha(0); bar.sweep:Hide()
  bar.border = atlasTex(bar, "ARTWORK", o.border); bar.border:SetPoint("TOPLEFT", bar, "TOPLEFT"); bar.border:SetWidth(o.width); bar.border:SetHeight(o.borderHeight)
  bar.border:SetDrawLayer("ARTWORK", 3)
  local rank = CreateFrame("Frame", nil, bar)
  rank:SetFrameLevel(bar:GetFrameLevel() + 5); rank:SetPoint("LEFT", bar, "LEFT", 0, -3); rank:SetPoint("RIGHT", bar, "RIGHT", 0, -3); rank:SetHeight(18)
  bar.text = rank:CreateFontString(nil, "ARTWORK")
  bar.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
  bar.text:SetPoint("CENTER", rank, "CENTER", 0, 0)
  bar.text:SetTextColor(1, 1, 1)
  return bar
end

P.NewBar = newBar

-- Pure: the flare is FLARE_W wide, but a fill shorter than that has less room left of its end (the flare used to hang out of the bar's left
-- edge: orange / blue fragments beside the Cooking and Fishing bars). Returns the width to draw and the u fraction (0..1) of the art where
-- the shown part starts: a short fill shows only the right part of the flare, the part that touches the leading edge.
function P.FlareFit(vw, flareW)
  local w = math.max(0, math.min(flareW, vw))
  return w, 1 - w / flareW
end

-- Forever's skill-up (the bar flares and the fill climbs to the new rank): the shown rank eases toward the new one with the exponential step of the
-- shared scroll bar (WinKit.ScrollEase: cur + (target - cur) * (1 - e^(-dt * speed))), the glow fades out over GLOW seconds.
P.SKILLUP = { SPEED = 3.4, GLOW = 1.2, EPS = 0.02, WASH = 0.5 }
function P.EaseStep(cur, target, dt, speed, eps)
  local nxt = cur + (target - cur) * (1 - math.exp(-dt * speed))
  if math.abs(target - nxt) <= eps then return target, true end
  return nxt, false
end
function P.GlowAlpha(t, glow) -- 1 at the start, 0 at `glow` seconds (a quadratic fade: bright first, gone softly)
  if t >= glow then return 0 end
  local k = 1 - t / glow
  return k * k
end

-- Draws the bar at `rank` (the fill, the flare, and the glow while a skill-up runs).
local function paint(bar, rank)
  local o = bar.o
  local kit, max = bar.kit or "tailoring", bar.max or 0
  local ratio = P.Ratio(rank, max)
  -- the fill lives inside the frame art's opaque border (o.inset, measured on the art), cut to the share of the inner width
  local vw = AFUI.Bar.Place(bar.fill, bar, o.inset, ratio, P.FillAtlas(kit), o.border, { w = o.width, h = o.borderHeight, stretch = o.stretch })
  local flare = P.FlareAtlas(kit)
  local e = flare and AFUI_ATLAS and AFUI_ATLAS[flare]
  local w, u0 = P.FlareFit(vw, FLARE_W)
  local function light(t, on)
    if not (on and e and w > 0 and ratio < 1) then t:Hide(); return end
    AFUI.SetAtlas(t, flare)
    t:SetTexCoord(e[4] + (e[5] - e[4]) * u0, e[5], e[6], e[7])
    t:SetWidth(w)
    t:ClearAllPoints(); t:SetPoint("RIGHT", bar, "LEFT", o.inset[1] + vw + 1, -1)
    t:Show()
  end
  -- the glow is animation only: a static bar is just the fill
  light(bar.flare, bar.anim ~= nil)
  light(bar.spark, bar.anim ~= nil)
  if bar.anim and vw > 0 then bar.sweep:Show() else bar.sweep:Hide() end
end

local function skillUpTick(bar, dt)
  local a = bar.anim
  if not a then bar:SetScript("OnUpdate", nil); return end
  local S = P.SKILLUP
  a.t = a.t + (dt or 0)
  if not a.done then a.cur, a.done = P.EaseStep(a.cur, a.to, dt or 0, S.SPEED, S.EPS) end
  local glow = P.GlowAlpha(a.t, S.GLOW)
  if a.done and glow <= 0 then
    bar.anim = nil; bar.shownRank = a.to
    bar:SetScript("OnUpdate", nil)
    bar.sweep:SetAlpha(0)
    paint(bar, a.to)
    return
  end
  paint(bar, a.cur)
  bar.sweep:SetAlpha(glow * S.WASH); bar.spark:SetAlpha(glow); bar.flare:SetAlpha(glow)
end

local function stopSkillUp(bar)
  bar.anim = nil
  bar:SetScript("OnUpdate", nil)
  bar.sweep:SetAlpha(0)
end

-- The skill-up animation: from rank `old` to `new` (both of the bar's current cap). Also what `/afui skillup` plays.
function P.PlaySkillUp(bar, old, new)
  if not bar or not bar.sweep or type(old) ~= "number" or type(new) ~= "number" or new <= old then return false end
  bar.max = bar.max or math.max(new, 75)
  bar.anim = { cur = old, to = new, t = 0, done = false }
  bar:SetScript("OnUpdate", skillUpTick)
  paint(bar, old)
  bar.sweep:SetAlpha(P.SKILLUP.WASH); bar.spark:SetAlpha(1); bar.flare:SetAlpha(1)
  return true
end

-- Sets what the bar shows. `key` names the skill: when the SAME skill (same cap) shows a higher rank than the last time, the bar plays the skill-up
-- from the old rank to the new one instead of jumping (a hidden window just snaps).
function P.UpdateBar(bar, kit, rank, max, text, key)
  local same = key ~= nil and bar.skillKey == key and bar.max == max
  local prev = bar.shownRank
  bar.kit, bar.max, bar.skillKey = kit, max, key
  bar.text:SetText(text)
  if bar.anim then
    if rank >= bar.anim.cur and same then bar.anim.to = rank; bar.anim.done = false; return end
    stopSkillUp(bar)
  end
  if same and prev and rank > prev and bar:IsVisible() then
    P.PlaySkillUp(bar, prev, rank)
  else
    paint(bar, rank)
  end
  if not bar.anim then bar.shownRank = rank end
end

local OVERVIEW_BAR = { bg = "profession-progressbar-bg-c60", border = "profession-progressbar-frame-c60", bgHeight = 23, borderHeight = 23, inset = { 5, 4, 5, 4 }, stretch = true, width = 441 }
local SECONDARY_BAR = { bg = "profession-progressbar-bg-c60", border = "profession-progressbar-frame-c60", bgHeight = 23, borderHeight = 23, inset = { 3, 4, 3, 4 }, stretch = true, width = 190 }
local CRAFT_BAR = { bg = "professions-skillbar-bg", border = "professions-skillbar-frame", bgHeight = 29, borderHeight = 29, inset = { 6, 4, 6, 9 }, width = 451 }

---------------------------------------------------------------- spell buttons (secure)
-- type=spell attributes: a click casts the profession spell (the crafting window opens by the client). Created / changed out of combat only.
local function spellButtonTooltip(self)
  if not self.spell then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  local idx = P.SpellIndex(self.spell)
  if idx then AFUI.TooltipSpellBook(GameTooltip, idx, "spell") else GameTooltip:SetText(self.spell, 1, 1, 1) end
  GameTooltip:Show()
end

local function newSpellButton(parent)
  local b = CreateFrame("CheckButton", nil, parent, "SecureActionButtonTemplate")
  b:SetWidth(40); b:SetHeight(40)
  b:RegisterForClicks("LeftButtonUp"); b:RegisterForDrag("LeftButton")
  b:SetAttribute("type", "spell")
  b.icon = b:CreateTexture(nil, "BORDER")
  b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3); b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.frameArt = atlasTex(b, "OVERLAY", "profession-square-frame-c60-2x", 40, 40); b.frameArt:SetPoint("CENTER", b, "CENTER")
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
  b.label = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  b.label:SetPoint("LEFT", b, "RIGHT", 5, 7); b.label:SetJustifyH("LEFT"); b.label:SetWidth(100)
  b.sub = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  b.sub:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -1); b.sub:SetJustifyH("LEFT"); b.sub:SetTextColor(0.62, 0.6, 0.58)
  b:SetScript("OnEnter", spellButtonTooltip)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnDragStart", function(self) local i = P.SpellIndex(self.spell); if i then AFUI.PickupSpellBook(i, "spell") end end)
  b:SetScript("PreClick", function(self) self:SetChecked(false) end)
  return b
end

-- Sets what a spell button shows and casts (call out of combat).
local function setSpell(b, s)
  b.spell = s.name
  b:SetAttribute("spell", s.name)
  local _, _, icon = GetSpellInfo(s.name)
  AFUI.SetIcon(b.icon, icon, AFUI.IconPath(b.fallback))
  b.label:SetText(s.name)
  b.sub:SetText(s.rank or "")
  b:Show()
end

---------------------------------------------------------------- side tabs
local TAB_W, TAB_H = 55, 55 -- common-sidetab 55x60 art, height without the transparent 5 px (SidePanelTabButtonMixin.CalculateTabSizeBasedOnTabArt)
local MAX_TABS = 8

local function makeTab(host, prev)
  local t = CreateFrame("CheckButton", nil, host, "SecureActionButtonTemplate")
  t.afOverhang = true -- the side tab column hangs off the window's right edge on purpose (the audit skips it)
  t:SetWidth(TAB_W); t:SetHeight(TAB_H)
  t:RegisterForClicks("LeftButtonUp")
  t:SetFrameLevel(host:GetFrameLevel() + 20)
  t.bg = atlasTex(t, "BACKGROUND", "common-sidetab-c60", 55, 60); t.bg:SetPoint("CENTER", t, "CENTER")
  t.icon = t:CreateTexture(nil, "ARTWORK"); t.icon:SetWidth(38); t.icon:SetHeight(38); t.icon:SetPoint("CENTER", t, "CENTER", -4, 0)
  t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  t.sel = atlasTex(t, "OVERLAY", "common-sidetab-selected-c60", 55, 60); t.sel:SetPoint("CENTER", t, "CENTER"); t.sel:Hide()
  t:SetHighlightTexture("")
  AFUI.SetAtlas(t:GetHighlightTexture(), "common-sidetab-hover-c60"); t:GetHighlightTexture():ClearAllPoints()
  t:GetHighlightTexture():SetPoint("CENTER", t, "CENTER"); t:GetHighlightTexture():SetWidth(55); t:GetHighlightTexture():SetHeight(60)
  t:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.tip, 1, 1, 1); GameTooltip:Show()
  end)
  t:SetScript("OnLeave", function() GameTooltip:Hide() end)
  t:SetScript("PreClick", function(self) self:SetChecked(false) end)
  if prev then t:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2) else t:SetPoint("TOPLEFT", host, "TOPRIGHT", 0, -60) end
  return t
end

-- Tab strip of a window: tabs[1] is the overview (plain button action), the rest are secure profession tabs.
local function newTabs(host)
  local tabs = { host = host }
  tabs[1] = makeTab(host, nil)
  tabs[1]:SetAttribute("type", nil)
  tabs[1].icon:SetTexture("Interface\\Icons\\INV_Hammer_20")
  tabs[1].tip = PROFESSIONS_BUTTON or "Professions"
  tabs[1]:SetScript("OnClick", function() P.ShowOverview() end)
  tabs[1].kind = "overview"
  for i = 2, MAX_TABS do tabs[i] = makeTab(host, tabs[i - 1]); tabs[i].kind = "profession"; tabs[i]:Hide() end
  return tabs
end

local pendingTabs = {}
-- Fills the strip from the classified skills; selected = a skill name (the open profession) or "overview". Secure attribute changes wait for combat to end.
function P.UpdateTabs(tabs, list, selected)
  local function apply()
    for i = 2, MAX_TABS do
      local l = list[i - 1]
      local t = tabs[i]
      if l then
        local d = DEF[l.key]
        local all = P.SpellsFor(l.key, known, 9)
        local want = d.tab and GetSpellInfo(d.tab)
        local first = all[1]
        for _, s in ipairs(all) do if s.name == want then first = s end end
        t.skillName = l.name
        t.tip = l.name
        t.icon:SetTexture(AFUI.IconPath(d.icon))
        if first then t:SetAttribute("type", "spell"); t:SetAttribute("spell", first.name) end
        t:Show()
      else
        t:Hide()
      end
    end
  end
  tabs.list = list
  AFUI.RunOutOfCombat(apply)
  P.SelectTab(tabs, selected)
end

function P.SelectTab(tabs, selected)
  for i, t in ipairs(tabs) do
    local on = (i == 1 and selected == "overview") or (i > 1 and t.skillName ~= nil and t.skillName == selected)
    t:SetChecked(on)
    setShown(t.sel, on)
  end
end

---------------------------------------------------------------- overview window
-- The overview, TradeSkillFrame and CraftFrame carry secure children: the client blocks showing, hiding and moving them in combat.
local function combatRefused()
  if not InCombatLockdown() then return false end
  AFUI.Print("Aztra's Forever UI: the Professions window can't be opened or closed in combat.")
  return true
end

local overview
local lines, classified

local function unlearn(name)
  if not StaticPopupDialogs["AFUI_UNLEARN_SKILL"] then
    StaticPopupDialogs["AFUI_UNLEARN_SKILL"] = {
      text = UNLEARN_SKILL or "Are you sure you want to unlearn %s? You will lose all progress.",
      button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1,
      OnAccept = function(a, b) -- 2.4.3 passes (data), 2.5.3 passes (self, data)
        local data = type(a) == "string" and a or b
        for _, l in ipairs(P.ReadLines(true)) do
          if l.name == data and not l.header then
            if l.index then AbandonSkill(l.index) else AFUI.Print("Aztra's Forever UI: open this skill's header in the Skills tab first.") end
            break
          end
        end
      end,
    }
  end
  StaticPopup_Show("AFUI_UNLEARN_SKILL", name, nil, name)
end

local function newCard(parent, primary, index)
  local c = CreateFrame("Frame", nil, parent)
  c.primary = primary
  if primary then c:SetWidth(664); c:SetHeight(142) else c:SetWidth(225); c:SetHeight(275) end
  c.art = {}
  c.name = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if primary then c.name:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -24); c.name:SetJustifyH("LEFT")
  else c.name:SetPoint("TOP", c, "TOP", 0, -25) end
  c.missing = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.missing:SetJustifyH("LEFT"); c.missing:SetJustifyV("TOP")
  if primary then c.missing:SetPoint("CENTER", c, "CENTER"); c.missing:SetWidth(485) else c.missing:SetPoint("TOP", c.name, "BOTTOM", 5, -13); c.missing:SetWidth(175) end
  c.spells = {}
  for i = 1, primary and 2 or 4 do
    local b = newSpellButton(c)
    if primary then b:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 15, i == 1 and 60 or 10)
    elseif i == 1 then b:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 20, 25)
    else b:SetPoint("BOTTOM", c.spells[i - 1], "TOP", 0, 0) end
    c.spells[i] = b
  end
  c.bar = newBar(c, primary and OVERVIEW_BAR or SECONDARY_BAR)
  c.bar:SetFrameLevel(c:GetFrameLevel() + 3)
  if primary then
    c.bar:SetPoint("RIGHT", c, "RIGHT", -40, 0)
    c.unlearn = CreateFrame("Button", nil, c)
    c.unlearn:SetWidth(20); c.unlearn:SetHeight(20); c.unlearn:SetPoint("LEFT", c.bar, "RIGHT", 1, -4)
    AFUI.SetButtonAtlas(c.unlearn, { "profession-button-red-crossmark-c60", "profession-button-red-crossmark-pressed-c60" })
    c.unlearn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(UNLEARN_SKILL_TOOLTIP or "Unlearn", 1, 1, 1); GameTooltip:Show() end)
    c.unlearn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.unlearn:SetScript("OnClick", function(self) if c.skill then unlearn(c.skill) end end)
  else
    c.bar:SetPoint("TOP", c, "TOP", 0, -47)
  end
  return c
end

-- Fills a card: line = a classified skill line or nil (not learned).
local function fillCard(c, line, missingHeader, missingText, kit)
  local key = line and line.key
  local d = key and DEF[key]
  local useKit = d and d.kit or kit
  -- card art (tiled: the primary card is wider than a texture page)
  local atlas = P.CardAtlas(useKit or "", c.primary)
  if not c.art.name or c.art.name ~= atlas then
    c.art.name = atlas
    local tiles = AFUI_ATLAS_TILES and AFUI_ATLAS_TILES[atlas] or { atlas }
    local total = 0
    for _, t in ipairs(tiles) do total = total + (AFUI_ATLAS[t] and AFUI_ATLAS[t][2] or 0) end
    local x = 0
    for i, t in ipairs(tiles) do
      local tx = c.art[i] or c:CreateTexture(nil, "BACKGROUND")
      c.art[i] = tx
      AFUI.SetAtlas(tx, t)
      local w = AFUI_ATLAS[t] and AFUI_ATLAS[t][2] or c:GetWidth()
      tx:ClearAllPoints(); tx:SetPoint("TOPLEFT", c, "TOPLEFT", x, 0); tx:SetWidth(w * c:GetWidth() / total); tx:SetHeight(c:GetHeight())
      tx:Show()
      x = x + w * c:GetWidth() / total
    end
    for i = #tiles + 1, #c.art do c.art[i]:Hide() end
  end
  c.skill = line and line.name
  if line then
    c.name:SetText(c.primary and line.name or line.name)
    c.missing:Hide()
    c.bar:Show()
    P.UpdateBar(c.bar, d.kit, line.rank, line.max, P.RankText(line.name, line.rank, line.max, line.mod), line.name)
    if c.unlearn then c.unlearn:Show() end
    local list = P.SpellsFor(key, known, c.primary and 2 or 4)
    if c.primary then
      c.spells[1]:ClearAllPoints()
      if #list == 1 then c.spells[1]:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 15, 46) else c.spells[1]:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 15, 60) end
    end
    for i, b in ipairs(c.spells) do
      local s = list[i]
      if s then b.fallback = d.icon; setSpell(b, s) else b:Hide() end
    end
    -- the profession's own rank title under its first spell ("Journeyman"); the extras (Disenchant) have none
    -- the spell's own rank under its name ("Journeyman"); a profession spell without one shows the title of its cap
    for i, s in ipairs(list) do
      if s.rank == "" and s.name == (d.spells[1] and d.spells[1][1] > 0 and GetSpellInfo(d.spells[1][1])) then c.spells[i].sub:SetText(P.RankTitle(line.max)) end
    end
  else
    c.name:SetText("")
    c.missing:Show()
    c.missing:SetText(missingText or "")
    if not c.primary then c.name:SetText(missingHeader or "") end
    c.bar:Hide()
    if c.unlearn then c.unlearn:Hide() end
    for _, b in ipairs(c.spells) do b:Hide() end
  end
end

local MISSING = {
  cooking = "Visit a trainer to learn cooking. Cooking allows you to prepare meals from raw ingredients that restore health and grant bonuses.",
  fishing = "Visit a trainer to learn fishing. Fishing lets you catch fish and other strange things from water. Fish can be cooked into delicious meals with the Cooking skill.",
  firstaid = "Visit a trainer to learn first aid. First Aid lets you heal yourself and others with bandages.",
}

function P.RefreshOverview()
  if not overview then return end
  -- the spell buttons and side tabs are secure: out of combat only (the queue keeps one copy of this function)
  if InCombatLockdown() then return AFUI.RunOutOfCombat(P.RefreshOverview) end
  lines = P.ReadLines()
  classified = P.Classify(lines)
  local c = overview.content
  fillCard(c.primary1, classified.primary[1], PROFESSIONS_FIRST_PROFESSION or "First Profession", PROFESSIONS_MISSING_PROFESSION or "You have not learned a profession. Visit a trainer to learn one.", nil)
  fillCard(c.primary2, classified.primary[2], PROFESSIONS_SECOND_PROFESSION or "Second Profession", PROFESSIONS_MISSING_PROFESSION or "You have not learned a profession. Visit a trainer to learn one.", nil)
  c.primary1.name:SetText(classified.primary[1] and classified.primary[1].name or "")
  c.primary2.name:SetText(classified.primary[2] and classified.primary[2].name or "")
  if not classified.primary[1] then c.primary1.name:SetText(PROFESSIONS_FIRST_PROFESSION or "First Profession"); c.primary1.missing:Show() end
  if not classified.primary[2] then c.primary2.name:SetText(PROFESSIONS_SECOND_PROFESSION or "Second Profession"); c.primary2.missing:Show() end
  fillCard(c.cooking, classified.cooking, "Cooking", PROFESSIONS_COOKING_MISSING or MISSING.cooking, "cooking")
  fillCard(c.fishing, classified.fishing, "Fishing", PROFESSIONS_FISHING_MISSING or MISSING.fishing, "fishing")
  fillCard(c.firstaid, classified.firstaid, "First Aid", PROFESSIONS_FIRST_AID_MISSING or MISSING.firstaid, "firstaid")
  P.UpdateTabs(overview.tabs, P.TabList(classified), "overview")
end

local function buildOverview()
  local f = CreateFrame("Frame", "AFUI_ProfessionsFrame", UIParent)
  f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
  f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", origin().x, origin().y)
  f:Hide()
  chrome(f, FRAME_W, FRAME_H)
  f.afPortrait:SetTexture("Interface\\Icons\\INV_Hammer_20")
  f.title = f.afLabels:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOP", f, "TOP", 0, -6); f.title:SetText(PROFESSIONS_BUTTON or "Professions")
  local drag = CreateFrame("Frame", nil, f)
  drag:SetPoint("TOPLEFT", f, "TOPLEFT", 58, 0); drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, 0); drag:SetHeight(20); drag:EnableMouse(true)
  if AFUI.WinKit then AFUI.WinKit.makeMovable(f, drag, "professions", { place = P.Place }) end
  local close = CreateFrame("Button", nil, f)
  closeButton(close, f)
  close:SetScript("OnClick", function() if not combatRefused() then f:Hide() end end)
  -- the pages: ProfessionsContentFrame fills the frame; cards at 5,-41 and stacked (blizzard_professionsbooktemplates.xml:176-225)
  local content = CreateFrame("Frame", nil, f)
  content:SetAllPoints(f); content:SetFrameLevel(f:GetFrameLevel() + 2)
  f.content = content
  local p1 = newCard(content, true); p1:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -41)
  local p2 = newCard(content, true); p2:SetPoint("TOPLEFT", p1, "BOTTOMLEFT", 0, 5)
  local s1 = newCard(content, false); s1:SetPoint("TOPLEFT", p2, "BOTTOMLEFT", 0, 4)
  local s2 = newCard(content, false); s2:SetPoint("TOPLEFT", s1, "TOPRIGHT", -6, 0)
  local s3 = newCard(content, false); s3:SetPoint("TOPLEFT", s2, "TOPRIGHT", -6, 0)
  content.primary1, content.primary2, content.cooking, content.fishing, content.firstaid = p1, p2, s1, s2, s3
  f.tabs = newTabs(f)
  f:SetScript("OnShow", function(self) self:Raise(); P.RefreshOverview() end)
  f:SetScript("OnHide", function() StaticPopup_Hide("AFUI_UNLEARN_SKILL"); if P.OnHide then P.OnHide() end end)
  table.insert(UISpecialFrames, "AFUI_ProfessionsFrame")
  return f
end

---------------------------------------------------------------- opening, closing, toggling
local function craftingShown()
  return (_G.TradeSkillFrame and TradeSkillFrame:IsShown()) or (_G.CraftFrame and CraftFrame:IsShown())
end

local function closeCrafting()
  if _G.TradeSkillFrame and TradeSkillFrame:IsShown() then HideUIPanel(TradeSkillFrame) end
  if _G.CraftFrame and CraftFrame:IsShown() then HideUIPanel(CraftFrame) end
end

function P.ShowOverview()
  if not overview or combatRefused() then return end
  closeCrafting()
  overview:Show()
end

function P.Toggle()
  if not overview or combatRefused() then return end
  if overview:IsShown() then overview:Hide() else P.ShowOverview() end
end

-- a trade skill window opened (by a tab or a spell): the overview is the same window, so it steps aside
local function onCraftingShow()
  if overview and overview:IsShown() and not InCombatLockdown() then overview:Hide() end
end

---------------------------------------------------------------- crafting window (Blizzard's TradeSkillFrame / CraftFrame restyled)
local ROW_H = 22 -- recipe row pitch (headers 22 high bars; Forever's ScrollBox adds gaps around headers, a faux scroll list has one pitch)
local LIST_X, LIST_Y, LIST_W = 13, -107, 272
local PANE_X, PANE_Y, PANE_W, PANE_H = 311, -72, 360, FRAME_H - 72 - 5

-- Frame names per window. Both clients have all of them except where noted (optional ones are checked before use).
local DESC = {
  trade = {
    frame = "TradeSkillFrame", title = "TradeSkillFrameTitleText", portrait = "TradeSkillFramePortrait", close = "TradeSkillFrameCloseButton",
    rank = "TradeSkillRankFrame", list = "TradeSkillListScrollFrame", rows = "TradeSkillSkill", displayed = "TRADE_SKILLS_DISPLAYED", heightVar = "TRADE_SKILL_HEIGHT",
    update = "TradeSkillFrame_Update", highlight = "TradeSkillHighlightFrame", detail = "TradeSkillDetailScrollFrame", child = "TradeSkillDetailScrollChildFrame",
    name = "TradeSkillSkillName", icon = "TradeSkillSkillIcon", count = "TradeSkillSkillIconCount", requiresLabel = "TradeSkillRequirementLabel", requires = "TradeSkillRequirementText",
    cooldown = "TradeSkillSkillCooldown", reagentLabel = "TradeSkillReagentLabel", reagent = "TradeSkillReagent",
    create = "TradeSkillCreateButton", createAll = "TradeSkillCreateAllButton", cancel = "TradeSkillCancelButton", dec = "TradeSkillDecrementButton",
    inc = "TradeSkillIncrementButton", input = "TradeSkillInputBox", search = "TradeSkillFrameEditBox", available = "TradeSkillFrameAvailableFilterCheckButton",
    hide = { "TradeSkillFramePortrait", "TradeSkillHorizontalBarLeft", "TradeSkillExpandButtonFrame", "TradeSkillInvSlotDropDown", "TradeSkillSubClassDropDown",
      "TradeSkillFrameAvailableFilterCheckButton", "TradeSkillRankFrame", "TradeSkillSkillLineName", "TradeSkillDetailHeaderLeft",
      "TradeSkillDetailScrollFrameScrollBar", "TradeSkillDetailScrollFrameTop", "TradeSkillDetailScrollFrameBottom" },
    selection = function() return GetTradeSkillSelectionIndex() end,
    info = function(i) local n, t, num, exp = GetTradeSkillInfo(i); return n, t, num, exp end,
    skillLine = function() local n, r, m = GetTradeSkillLine(); return n, r, m end,
    describe = function(id) return GetTradeSkillDescription and GetTradeSkillDescription(id) end,
  },
  craft = {
    frame = "CraftFrame", title = "CraftFrameTitleText", portrait = "CraftFramePortrait", close = "CraftFrameCloseButton",
    rank = "CraftRankFrame", list = "CraftListScrollFrame", rows = "Craft", displayed = "CRAFTS_DISPLAYED", heightVar = "CRAFT_SKILL_HEIGHT",
    update = "CraftFrame_Update", highlight = "CraftHighlightFrame", detail = "CraftDetailScrollFrame", child = "CraftDetailScrollChildFrame",
    name = "CraftName", icon = "CraftIcon", count = "CraftIconCount", requires = "CraftRequirements", description = "CraftDescription",
    cooldown = "CraftCooldown", reagentLabel = "CraftReagentLabel", reagent = "CraftReagent",
    create = "CraftCreateButton", cancel = "CraftCancelButton", search = "CraftFrameEditBox", available = "CraftFrameAvailableFilterCheckButton",
    hide = { "CraftFramePortrait", "CraftHorizontalBarLeft", "CraftExpandButtonFrame", "CraftFrameFilterDropDown", "CraftFrameAvailableFilterCheckButton", "CraftRankFrame",
      "CraftSkillBorderLeft", "CraftSkillBorderRight", "CraftDetailHeaderLeft", "CraftCost", "CraftFramePointsLabel", "CraftFramePointsText",
      "CraftDetailScrollFrameScrollBar", "CraftDetailScrollFrameTop", "CraftDetailScrollFrameBottom" },
    selection = function() return GetCraftSelectionIndex() end,
    info = function(i) local n, sub, t, num, exp = GetCraftInfo(i); return n, t, num, exp end,
    skillLine = function() local n, r, m = GetCraftDisplaySkillLine(); return n, r, m end,
    describe = function(id) return nil end,
  },
}

local function g(name) return name and _G[name] end

local function hideRegions(frame)
  for _, r in ipairs({ frame:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "Texture" and not r.afKeep then r:Hide() end
  end
end

-- Forever's Filter button (the dark dropdown with the gold arrow).
local function newFilterButton(host)
  local b = CreateFrame("Button", nil, host)
  b:SetWidth(90); b:SetHeight(22); b:SetFrameLevel(host:GetFrameLevel() + 4)
  b.bg = atlasTex(b, "BACKGROUND", "common-dropdown-b-button-c60"); b.bg:SetPoint("TOPLEFT", b, -2, 2); b.bg:SetPoint("BOTTOMRIGHT", b, 2, -2)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.text:SetPoint("CENTER", b, "CENTER", -6, 1); b.text:SetText(FILTER or "Filter")
  b.arrow = b:CreateTexture(nil, "OVERLAY") -- the gold right-pointing arrow (the client's submenu arrow, gold-tinted)
  b.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow"); b.arrow:SetVertexColor(1, 0.82, 0)
  b.arrow:SetWidth(10); b.arrow:SetHeight(10); b.arrow:SetPoint("RIGHT", b, "RIGHT", -8, 0)
  b:SetHighlightTexture("")
  AFUI.SetAtlas(b:GetHighlightTexture(), "common-dropdown-b-button-hover-c60"); b:GetHighlightTexture():ClearAllPoints()
  b:GetHighlightTexture():SetPoint("TOPLEFT", b, -2, 2); b:GetHighlightTexture():SetPoint("BOTTOMRIGHT", b, 2, -2)
  return b
end

local function newSearch(host)
  local e = CreateFrame("EditBox", nil, host)
  e:SetAutoFocus(false); e:SetHeight(20); e:SetMaxLetters(40); e:SetFontObject("GameFontHighlightSmall")
  e:SetFrameLevel(host:GetFrameLevel() + 4)
  local l = atlasTex(e, "BACKGROUND", "common-search-border-left-c60"); l:SetPoint("TOPLEFT", e, "TOPLEFT", -4, 7); l:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT", -4, -7); l:SetWidth(8)
  local r = atlasTex(e, "BACKGROUND", "common-search-border-right-c60"); r:SetPoint("TOPRIGHT", e, "TOPRIGHT", 4, 7); r:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 4, -7); r:SetWidth(8)
  local m = atlasTex(e, "BACKGROUND", "common-search-border-middle-c60"); m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  e.mag = atlasTex(e, "OVERLAY", "common-search-magnifyingglass", 14, 14); e.mag:SetPoint("LEFT", e, "LEFT", 2, -1)
  e:SetTextInsets(20, 8, 0, 0)
  return e
end

-- Fits a client FontString into `width` (one line, or `lines` lines) with "...". The client re-sets the text on every update, so the full text is
-- remembered next to the cut one (fs.afFull / fs.afShort) and a second pass over our own cut text starts from the full one again.
function P.Fit(fs, width, lines)
  if not fs then return end
  local cur = fs:GetText() or ""
  if fs.afShort and fs.afShort == cur then cur = fs.afFull end
  if not (lines and lines > 1) then fs:SetWidth(width) end -- one line: the box is exactly the room there is
  local out = (lines and lines > 1) and AFUI.FitLines(fs, cur, width, lines) or AFUI.FitText(fs, cur, width)
  fs.afFull, fs.afShort = cur, (out ~= cur) and out or nil
  return out
end

-- A truncated row shows its full text in a tooltip.
local function rowTip(btn, text)
  if btn.afTip or not btn.HookScript then return end
  btn.afTip = true
  btn:HookScript("OnEnter", function(self)
    local fs = self:GetFontString()
    if fs and fs.afShort and GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(fs.afFull, 1, 1, 1); GameTooltip:Show() end
  end)
  btn:HookScript("OnLeave", function(self)
    local fs = self:GetFontString()
    if fs and fs.afShort and GameTooltip then GameTooltip:Hide() end
  end)
end

-- The crafting window's recipe rows: Forever's gold category bars with a minus / plus, the skill-up arrow by difficulty, the gold selection bar.
local function styleRow(btn, skillType, expanded, selected)
  if not btn.afRow then
    local r = {}
    r.header = atlasTex(btn, "BACKGROUND", "profession-tab-c60"); r.header:SetPoint("TOPLEFT", btn, "TOPLEFT"); r.header:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT")
    r.sign = atlasTex(btn, "OVERLAY", "common-button-list-minus-c60", 13, 4); r.sign:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
    r.arrow = atlasTex(btn, "OVERLAY", "professions-icon-skill-high", 13, 15); r.arrow:SetPoint("LEFT", btn, "LEFT", 12, -1)
    r.active = atlasTex(btn, "ARTWORK", "professions_recipe_active", LIST_W, 19); r.active:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.afRow = r
  end
  local r = btn.afRow
  local nt = btn:GetNormalTexture()
  if nt then nt:SetAlpha(0); nt:Hide() end
  local text = btn:GetFontString()
  if skillType == "header" then
    r.header:Show(); r.sign:Show(); r.arrow:Hide(); r.active:Hide()
    AFUI.SetAtlas(r.sign, expanded and "common-button-list-minus-c60" or "common-button-list-plus-c60")
    r.sign:SetWidth(13); r.sign:SetHeight(expanded and 4 or 13)
    btn:SetWidth(LIST_W)
    if text then text:SetFontObject(GameFontNormalLarge); text:ClearAllPoints(); text:SetPoint("LEFT", btn, "LEFT", 5, 0); text:SetJustifyH("LEFT"); text:SetTextColor(1, 0.82, 0) end
    AFUI.SetButtonAtlas(btn, { nil, nil, "profession-tab-glow-c60" })
  else
    r.header:Hide(); r.sign:Hide(); r.active:Hide()
    local ic = P.DifficultyIcon(skillType)
    if ic then AFUI.SetAtlas(r.arrow, ic); r.arrow:Show() else r.arrow:Hide() end
    setShown(r.active, selected)
    btn:SetWidth(LIST_W)
    if text then text:SetFontObject(GameFontHighlight); text:ClearAllPoints(); text:SetPoint("LEFT", btn, "LEFT", 26, 0); text:SetJustifyH("LEFT"); text:SetTextColor(WHITE_TEXT[1], WHITE_TEXT[2], WHITE_TEXT[3]) end
    AFUI.SetButtonAtlas(btn, { nil, nil, "professions_recipe_hover" }, 0.5)
  end
  btn:SetHeight(ROW_H)
  if text then -- headers: 5 px in, the plus / minus (13 wide, 10 from the edge) at the right; recipes: 26 px in, the scroll bar lies outside the list
    P.Fit(text, skillType == "header" and LIST_W - 5 - 10 - 13 - 6 or LIST_W - 26 - 8)
    rowTip(btn)
  end
  local ht = btn:GetHighlightTexture() -- the client's template anchors its 16 px plus-button glow at the left: stretch ours over the row
  if ht then ht:ClearAllPoints(); ht:SetAllPoints(btn) end
end

-- Skin one client scroll bar: the shared Forever bar (WinKit.scroll) takes its place; the slider stays the model.
local function skinScrollBar(sb, host, o)
  if sb and AFUI.WinKit then return AFUI.WinKit.scroll(sb, o) end
end

-- The recipe pane (right side): everything lives in the detail scroll child, re-anchored for a 360 wide pane.
local function layoutDetail(w)
  local d = w.d
  local scroll, child = g(d.detail), g(d.child)
  if not scroll or not child then return end
  scroll:ClearAllPoints(); scroll:SetPoint("TOPLEFT", w.frame, "TOPLEFT", PANE_X, PANE_Y); scroll:SetWidth(PANE_W); scroll:SetHeight(PANE_H - 40)
  child:SetWidth(PANE_W); child:SetHeight(PANE_H - 40)
  local sb = g(d.detail .. "ScrollBar")
  if sb then sb:Hide(); sb:SetAlpha(0) end
  for _, n in ipairs({ "Top", "Bottom", "Background" }) do local t = g(d.detail .. "Scroll" .. n) or g(d.detail .. n); if t and t.Hide then t:Hide() end end
  local icon = g(d.icon)
  if icon then
    icon:SetWidth(40); icon:SetHeight(40); icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", child, "TOPLEFT", 32, -29)
    if not icon.afRing then
      icon.afRing = atlasTex(icon, "OVERLAY", "profession-ring-frame-c60-2x", 64, 64); icon.afRing:SetPoint("CENTER", icon, "CENTER")
      icon.afRing:SetDrawLayer("OVERLAY", 3)
    end
    local nt = icon:GetNormalTexture()
    if nt then nt:ClearAllPoints(); nt:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1); nt:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1); nt:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    local nf = g(d.icon .. "NameFrame"); if nf then nf:Hide() end
  end
  local name = g(d.name)
  if name then
    name:SetFontObject(GameFontHighlightLarge); name:ClearAllPoints(); name:SetPoint("TOPLEFT", child, "TOPLEFT", 88, -30); name:SetWidth(225); name:SetJustifyH("LEFT")
  end
  local reqLabel, req = g(d.requiresLabel), g(d.requires)
  if reqLabel then reqLabel:ClearAllPoints(); reqLabel:SetPoint("TOPLEFT", name or child, name and "BOTTOMLEFT" or "TOPLEFT", 0, -2); reqLabel:SetFontObject(GameFontNormalSmall) end
  if req then
    req:ClearAllPoints()
    if reqLabel then req:SetPoint("TOPLEFT", reqLabel, "TOPRIGHT", 4, 0) else req:SetPoint("TOPLEFT", name or child, name and "BOTTOMLEFT" or "TOPLEFT", 0, -2) end
    req:SetFontObject(GameFontHighlightSmall); req:SetWidth(200)
  end
  local cd = g(d.cooldown)
  if cd then cd:ClearAllPoints(); cd:SetPoint("TOPLEFT", req or name, "BOTTOMLEFT", 0, -2) end
  local desc = g(d.description) or w.desc
  if desc then
    desc:ClearAllPoints(); desc:SetPoint("TOPLEFT", child, "TOPLEFT", 25, -93); desc:SetWidth(305); desc:SetJustifyH("LEFT"); desc:SetJustifyV("TOP")
    desc:SetFontObject(GameFontHighlight)
  end
  local label = g(d.reagentLabel)
  if label then
    label:SetFontObject(GameFontNormalSmall)
    label:ClearAllPoints(); label:SetPoint("TOPLEFT", desc or child, desc and "BOTTOMLEFT" or "TOPLEFT", 0, desc and -18 or -93)
  end
  for i = 1, 8 do
    local rb = g(d.reagent .. i)
    if rb then
      rb:ClearAllPoints(); rb:SetWidth(PANE_W - 50); rb:SetHeight(40)
      if i == 1 then rb:SetPoint("TOPLEFT", label or child, "BOTTOMLEFT", 0, -8) else rb:SetPoint("TOPLEFT", g(d.reagent .. (i - 1)), "BOTTOMLEFT", 0, -6) end
      local nf = g(d.reagent .. i .. "NameFrame"); if nf then nf:Hide() end
      local ic = g(d.reagent .. i .. "IconTexture")
      if ic then ic:ClearAllPoints(); ic:SetPoint("TOPLEFT", rb, "TOPLEFT", 3, -3); ic:SetWidth(34); ic:SetHeight(34); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
      local nt = rb:GetNormalTexture(); if nt then nt:SetAlpha(0) end
      if not rb.afFrame then
        rb.afFrame = atlasTex(rb, "OVERLAY", "profession-square-frame-c60-2x", 40, 40); rb.afFrame:SetPoint("TOPLEFT", rb, "TOPLEFT", 0, 0)
      end
      local nm, ct = g(d.reagent .. i .. "Name"), g(d.reagent .. i .. "Count")
      if nm then nm:ClearAllPoints(); nm:SetPoint("LEFT", rb, "LEFT", 48, 0); nm:SetWidth(PANE_W - 140); nm:SetJustifyH("LEFT"); nm:SetFontObject(GameFontHighlight) end
      if ct then ct:ClearAllPoints(); ct:SetPoint("BOTTOMRIGHT", rb, "TOPLEFT", 37, 5) end -- the stack count stays on the icon's corner
    end
  end
end

-- Reagent text: Forever prints "have/need Name" (Blizzard: count "have /need" on the icon and the name apart).
local function reagentText(w)
  local d = w.d
  for i = 1, 8 do
    local rb = g(d.reagent .. i)
    local nm, ct = g(d.reagent .. i .. "Name"), g(d.reagent .. i .. "Count")
    if rb and rb:IsShown() and nm and ct then
      local have, need = (ct:GetText() or ""):match("^(%S+)%s*/(%S+)")
      if have and need and not nm.afText then
        local name = nm:GetText() or ""
        nm.afText = true
        nm:SetText(have .. "/" .. need .. " " .. name)
        nm.afText = false
      end
      ct:SetText("")
    end
  end
end

local function updateWindow(w)
  local d = w.d
  local frame = w.frame
  if not frame:IsShown() then return end
  -- the frame never changes size between pages (whatever the client did to it since the last update)
  if not InCombatLockdown() and (math.abs((frame:GetWidth() or 0) - FRAME_W) > 0.5 or math.abs((frame:GetHeight() or 0) - FRAME_H) > 0.5) then
    frame:SetWidth(FRAME_W); frame:SetHeight(FRAME_H)
  end
  -- title, bar, chat link
  local name, rank, max = d.skillLine()
  if name then
    local key = canonical(name)
    local kit = key and DEF[key] and DEF[key].kit or "tailoring"
    P.UpdateBar(w.bar, kit, rank or 0, max or 0, P.RankText(name, rank or 0, max or 0, 0), name)
    w.bar:Show()
    setPortrait(frame, key and DEF[key] and DEF[key].icon)
    P.SelectTab(w.tabs, name)
    local bgName = P.BackgroundAtlas(kit)
    if bgName then AFUI.SetAtlas(w.paneArt, bgName); w.paneArt:Show() else w.paneArt:Hide() end
  else
    w.bar:Hide(); w.paneArt:Hide()
  end
  setShown(w.link, name ~= nil and type(GetTradeSkillListLink) == "function" and d == DESC.trade)
  local list = g(d.list)
  -- search is shown at any rank (2.4.3 hides it below 75, Forever never does)
  if not w.noSearch then w.search:Show() end
  -- rows
  local selected = d.selection()
  local offset = FauxScrollFrame_GetOffset(g(d.list))
  for i = 1, w.rows do
    local btn = g(d.rows .. i)
    if btn then
      if btn:IsShown() then
        local n, t, _, expanded = d.info(btn:GetID())
        if n then styleRow(btn, t, expanded, selected == btn:GetID() and t ~= "header") end
      end
    end
  end
  local hl = g(d.highlight); if hl then hl:Hide() end
  local desc = w.desc
  if desc then
    local text = selected and selected > 0 and d.describe(selected)
    desc:SetText(text or "")
  end
  reagentText(w)
  -- the detail pane: nothing runs past its 360 px
  P.Fit(g(d.name), 225, 2)
  local reqLabel, req = g(d.requiresLabel), g(d.requires)
  if req then P.Fit(req, PANE_W - 88 - 15 - (reqLabel and ((reqLabel:GetStringWidth() or 0) + 4) or 0)) end
  for i = 1, 8 do
    local nm = g(d.reagent .. i .. "Name")
    if nm then P.Fit(nm, PANE_W - 140, 2) end
  end
  local all = g(d.createAll)
  if all then -- Forever: "Create All [n]", n = how many of the selected recipe the bags allow
    all:SetText((CREATE_ALL or "Create All") .. " [" .. ((frame.numAvailable or 0) > 0 and frame.numAvailable or 0) .. "]")
  end
end

-- Anchors one window's controls (called once the Blizzard frame exists).
local function restyle(key)
  local d = DESC[key]
  local frame = g(d.frame)
  if not frame or P.windows[key] then return end
  local w = { d = d, frame = frame, key = key }
  P.windows[key] = w
  frame:SetHitRectInsets(0, 0, 0, 0)
  hideRegions(frame)
  for _, n in ipairs(d.hide) do banish(g(n)) end
  chrome(frame, FRAME_W, FRAME_H)
  -- the panel manager sizes and places a shown left panel from UIPanelWindows (these two frames have no width / offset there): give it ours so
  -- every page of the one Professions window lands on the same spot (the overview is not a panel and uses the same origin)
  local O = origin()
  AFUI.PanelAttrs(frame, { width = FRAME_W, height = FRAME_H, xoffset = O.x, yoffset = O.y })
  local title = g(d.title)
  if title then if title.SetParent then title:SetParent(frame.afLabels) end; title:ClearAllPoints(); title:SetPoint("TOP", frame, "TOP", 0, -6); title:SetFontObject(GameFontNormal) end
  local close = g(d.close)
  if close then closeButton(close, frame) end
  local cancel = g(d.cancel); if cancel then cancel:Hide(); cancel:SetAlpha(0) end
  if AFUI.WinKit then -- drag by the title strip; the spot is kept per window
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 58, 0); drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, 0); drag:SetHeight(20); drag:SetFrameLevel(frame:GetFrameLevel() + 26)
    AFUI.WinKit.makeMovable(frame, drag, "professions", { place = P.Place }) -- one saved spot for every page
  end
  -- rank bar and chat link
  w.bar = newBar(frame, CRAFT_BAR)
  w.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 110, -40); w.bar:SetFrameLevel(frame:GetFrameLevel() + 4)
  w.link = CreateFrame("Button", nil, frame)
  w.link:SetWidth(23); w.link:SetHeight(23); w.link:SetPoint("LEFT", w.bar, "RIGHT", -2, -4); w.link:SetFrameLevel(frame:GetFrameLevel() + 4)
  AFUI.SetButtonAtlas(w.link, { "profession-button-chat-c60", "profession-button-chat-pressed-c60" })
  w.link:SetHighlightTexture("")
  w.link:SetScript("OnClick", function(self)
    local link = GetTradeSkillListLink and GetTradeSkillListLink()
    if not link then return end
    local function post(chatType, channel) return function() SendChatMessage(link, chatType, nil, channel) end end
    local raid = AFUI.RaidSize() > 0
    local party = raid or (GetNumPartyMembers and GetNumPartyMembers() > 0) or (IsInGroup and IsInGroup()) or false -- 2.5.3 has no GetNumPartyMembers
    local entries = { { text = "Post in chat", title = true },
      { text = "Guild", func = post("GUILD"), disabled = not IsInGuild() }, { text = "Party", func = post("PARTY"), disabled = not party or raid },
      { text = "Raid", func = post("RAID"), disabled = not raid } }
    for i = 1, 10 do
      local id, cname = GetChannelName(i)
      if id and id > 0 and cname then entries[#entries + 1] = { text = cname, func = post("CHANNEL", id) } end
    end
    P.ShowMenu(self, entries, "TOPLEFT", "TOPRIGHT", 4, 0)
  end)
  w.link:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Post in chat", 1, 1, 1); GameTooltip:Show() end)
  w.link:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- list: panel behind it, search + filter above
  w.listPanel = CreateFrame("Frame", nil, frame); w.listPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -72); w.listPanel:SetWidth(304); w.listPanel:SetPoint("BOTTOM", frame, "BOTTOM", 0, 5)
  w.listPanel.bg = w.listPanel:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(w.listPanel.bg, 0, 0, 0, 0.18); w.listPanel.bg:SetAllPoints(w.listPanel)
  w.filter = newFilterButton(frame); w.filter:SetPoint("TOPRIGHT", w.listPanel, "TOPRIGHT", -8, -9)
  w.search = g(d.search) or newSearch(frame)
  if g(d.search) then -- the client's own box: keep its scripts, only re-skin
    local e = w.search
    hideRegions(e)
    for _, n in ipairs({ "Left", "Middle", "Right" }) do local t = g(d.search .. n); if t then t:Hide() end end
    e:SetFontObject("GameFontHighlightSmall")
    local l = atlasTex(e, "BACKGROUND", "common-search-border-left-c60"); l:SetPoint("TOPLEFT", e, "TOPLEFT", -4, 7); l:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT", -4, -7); l:SetWidth(8)
    local r = atlasTex(e, "BACKGROUND", "common-search-border-right-c60"); r:SetPoint("TOPRIGHT", e, "TOPRIGHT", 4, 7); r:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 4, -7); r:SetWidth(8)
    local m = atlasTex(e, "BACKGROUND", "common-search-border-middle-c60"); m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    e.mag = atlasTex(e, "OVERLAY", "common-search-magnifyingglass", 14, 14); e.mag:SetPoint("LEFT", e, "LEFT", 2, -1)
    e:SetTextInsets(20, 8, 0, 0)
    e:SetHeight(20); e:SetFrameLevel(frame:GetFrameLevel() + 4)
    local function tint(self) if self:GetText() == SEARCH then self:SetTextColor(0.5, 0.5, 0.5) else self:SetTextColor(1, 1, 1) end end
    e:HookScript("OnTextChanged", tint); e:HookScript("OnEditFocusLost", tint); e:HookScript("OnEditFocusGained", tint); e:HookScript("OnShow", tint)
  end
  if not g(d.search) then -- 2.5.3's windows have no search box: ours drives the item name filter when the client has one
    local setFilter = (key == "trade" and _G.SetTradeSkillItemNameFilter) or (key == "craft" and _G.SetCraftItemNameFilter)
    local e = w.search
    if type(setFilter) == "function" then
      e.hint = e:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); e.hint:SetPoint("LEFT", e, "LEFT", 20, 0); e.hint:SetText(SEARCH or "Search")
      e:SetScript("OnTextChanged", function(self) setShown(self.hint, self:GetText() == "" and not self:HasFocus()); setFilter(self:GetText()) end)
      e:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
      e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
      e:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
      e:SetScript("OnEditFocusLost", function(self) setShown(self.hint, self:GetText() == "") end)
    else
      e:Hide(); w.noSearch = true
    end
  end
  w.search:ClearAllPoints()
  w.search:SetPoint("TOPLEFT", w.listPanel, "TOPLEFT", 18, -9); w.search:SetPoint("RIGHT", w.filter, "LEFT", -6, 0)
  -- list rows
  local list = g(d.list)
  local rows = P.VisibleRows(FRAME_H - 5 - 107 - 0, ROW_H)
  w.rows = rows
  _G[d.displayed] = rows
  _G[d.heightVar] = ROW_H
  local function rowName(i) return d.rows .. i end
  for i = 1, rows do
    local b = g(rowName(i))
    if not b then
      b = CreateFrame("Button", rowName(i), frame, key == "trade" and "TradeSkillSkillButtonTemplate" or "CraftButtonTemplate")
      b:SetID(i)
    end
    b:ClearAllPoints()
    if i == 1 then b:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_X, LIST_Y) else b:SetPoint("TOPLEFT", g(rowName(i - 1)), "BOTTOMLEFT", 0, 0) end
    b:SetFrameLevel(frame:GetFrameLevel() + 4)
    b:SetWidth(LIST_W); b:SetHeight(ROW_H)
  end
  if list then
    list:ClearAllPoints(); list:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_X, LIST_Y); list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", LIST_X + LIST_W, 5)
    local lsb = g(d.list .. "ScrollBar")
    if lsb then
      lsb:ClearAllPoints(); lsb:SetPoint("TOPLEFT", list, "TOPRIGHT", 4, -12); lsb:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 4, 12)
      -- Forever's bar is always there (dimmed when the list fits and the client hides its frame): parented to the window, flush with the list
      skinScrollBar(lsb, frame, { parent = frame, alwaysShow = true, x = 5 })
    end
    hideRegions(list)
  end
  for _, n in ipairs({ "Top", "Bottom" }) do local t = g(d.list .. n); if t then t:Hide() end end
  -- the recipe pane: panel, background art, details
  w.pane = CreateFrame("Frame", nil, frame)
  w.pane:SetPoint("TOPLEFT", frame, "TOPLEFT", PANE_X, PANE_Y); w.pane:SetWidth(PANE_W); w.pane:SetHeight(PANE_H)
  w.pane.bg = w.pane:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(w.pane.bg, 0, 0, 0, 0.16); w.pane.bg:SetAllPoints(w.pane)
  w.paneArt = w.pane:CreateTexture(nil, "BACKGROUND"); w.paneArt:SetDrawLayer("BACKGROUND", 2)
  w.paneArt:SetWidth(360); w.paneArt:SetHeight(484); w.paneArt:SetPoint("BOTTOMRIGHT", w.pane, "BOTTOMRIGHT", 0, 0)
  local sheet = AFUI_ATLAS and AFUI_ATLAS["common-insideframe-c60"] -- the inset frame art (ornate corners), 9-sliced at 20 px
  if sheet then
    local m = 20
    local us = { sheet[4], sheet[4] + (sheet[5] - sheet[4]) * m / sheet[2], sheet[5] - (sheet[5] - sheet[4]) * m / sheet[2], sheet[5] }
    local vs = { sheet[6], sheet[6] + (sheet[7] - sheet[6]) * m / sheet[3], sheet[7] - (sheet[7] - sheet[6]) * m / sheet[3], sheet[7] }
    local cx, cy = { "LEFT", "LEFT", "RIGHT", "RIGHT" }, { "TOP", "TOP", "BOTTOM", "BOTTOM" }
    local ox, oy = { 0, m, -m, 0 }, { 0, -m, m, 0 }
    for j = 1, 3 do
      for i = 1, 3 do
        local t = w.pane:CreateTexture(nil, "BORDER")
        t:SetTexture(sheet[1]); t:SetTexCoord(us[i], us[i + 1], vs[j], vs[j + 1])
        t:SetPoint("TOPLEFT", w.pane, cy[j] .. cx[i], ox[i], oy[j])
        t:SetPoint("BOTTOMRIGHT", w.pane, cy[j + 1] .. cx[i + 1], ox[i + 1], oy[j + 1])
      end
    end
  end
  local child = g(d.child)
  if child and not g(d.description) then
    w.desc = child:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  end
  layoutDetail(w)
  -- create / create all / count (Forever's bottom row)
  local create, createAll, dec, inc, input = g(d.create), g(d.createAll), g(d.dec), g(d.inc), g(d.input)
  local function redButton(b, wid)
    if not b then return end
    local K = AFUI.WinKit
    if K then K.button(b, wid, 22) else b:SetWidth(wid); b:SetHeight(22) end
    b:SetFrameLevel(frame:GetFrameLevel() + 6)
  end
  redButton(create, 80); redButton(createAll, 100)
  if create then create:ClearAllPoints(); create:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 7) end
  if createAll then createAll:ClearAllPoints(); createAll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PANE_X + 4, 7) end
  if dec and input and inc then
    local function arrowButton(b, kind)
      b:SetWidth(22); b:SetHeight(22); b:SetFrameLevel(frame:GetFrameLevel() + 6)
      AFUI.SetButtonAtlas(b, { "profession-button-arrow-" .. kind .. "-c60", "profession-button-arrow-" .. kind .. "-pressed-c60", nil, "profession-button-arrow-" .. kind .. "-c60" })
      b:SetHighlightTexture("")
    end
    arrowButton(dec, "left"); arrowButton(inc, "right")
    hideRegions(input)
    for _, n in ipairs({ "Left", "Middle", "Right" }) do local t = g(d.input .. n); if t then t:Hide() end end
    input:SetFrameLevel(frame:GetFrameLevel() + 6); input:SetWidth(43); input:SetHeight(18)
    local box = atlasTex(input, "BACKGROUND", "profession-page-box-c60", 43, 18); box:SetAllPoints(input)
    input:SetJustifyH("CENTER"); input:SetFontObject("GameFontHighlightSmall")
    input:ClearAllPoints(); input:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PANE_X + 160, 9)
    dec:ClearAllPoints(); dec:SetPoint("RIGHT", input, "LEFT", -4, 0)
    inc:ClearAllPoints(); inc:SetPoint("LEFT", input, "RIGHT", 4, 0)
  end
  -- Filter menu: the client's own filters, one list (Forever's single Filter button)
  w.filter:SetScript("OnClick", function(self)
    local entries = {}
    local avail = g(d.available)
    if avail then
      entries[#entries + 1] = { text = CRAFT_IS_MAKEABLE or "Have Materials", checked = avail:GetChecked() and true or false, func = function()
        local on = not (avail:GetChecked() and true or false)
        avail:SetChecked(on and 1 or nil)
        if key == "trade" then TradeSkillOnlyShowMakeable(on) else CraftOnlyShowMakeable(on) end
        local sbv = g(d.list .. "ScrollBar"); if sbv then sbv:SetValue(0) end
        FauxScrollFrame_SetOffset(g(d.list), 0); _G[d.update]()
      end }
    end
    if key == "trade" then
      local subs = { GetTradeSkillSubClasses() }
      if #subs > 0 then
        entries[#entries + 1] = { text = "Subclass", title = true }
        local allOn = GetTradeSkillSubClassFilter(0)
        entries[#entries + 1] = { text = ALL_SUBCLASSES or "All Subclasses", checked = allOn and true or false, func = function()
          SetTradeSkillSubClassFilter(0, 1, 1); FauxScrollFrame_SetOffset(g(d.list), 0); TradeSkillFrame_Update()
        end }
        for i, nm in ipairs(subs) do
          entries[#entries + 1] = { text = nm, checked = (not allOn and GetTradeSkillSubClassFilter(i)) and true or false, func = function()
            SetTradeSkillSubClassFilter(i, 1, 1); SetTradeSkillInvSlotFilter(0, 1, 1); FauxScrollFrame_SetOffset(g(d.list), 0); TradeSkillFrame_Update()
          end }
        end
      end
      local slots = { GetTradeSkillInvSlots() }
      if #slots > 0 then
        entries[#entries + 1] = { text = "Slot", title = true }
        local allOn = GetTradeSkillInvSlotFilter(0)
        entries[#entries + 1] = { text = ALL_INVENTORY_SLOTS or "All Slots", checked = allOn and true or false, func = function()
          SetTradeSkillInvSlotFilter(0, 1, 1); FauxScrollFrame_SetOffset(g(d.list), 0); TradeSkillFrame_Update()
        end }
        for i, nm in ipairs(slots) do
          entries[#entries + 1] = { text = nm, checked = (not allOn and GetTradeSkillInvSlotFilter(i)) and true or false, func = function()
            SetTradeSkillInvSlotFilter(i, 1, 1); FauxScrollFrame_SetOffset(g(d.list), 0); TradeSkillFrame_Update()
          end }
        end
      end
    else
      local slots = { GetCraftSlots() }
      if #slots > 0 then
        entries[#entries + 1] = { text = "Slot", title = true }
        local allOn = GetCraftFilter(0)
        for i, nm in ipairs(slots) do
          entries[#entries + 1] = { text = _G[nm] or nm, checked = (not allOn and GetCraftFilter(i)) and true or false, func = function()
            SetCraftFilter(i); CraftFrame.selected = i
          end }
        end
      end
    end
    P.ShowMenu(self, entries, "TOPLEFT", "BOTTOMLEFT", 0, -2)
  end)
  w.tabs = newTabs(frame)
  w.tabs[1].tip = PROFESSIONS_BUTTON or "Professions"
  -- the client's own handlers keep running; ours follows each one
  hooksecurefunc(d.update, function() updateWindow(w) end)
  local setSel = key == "trade" and "TradeSkillFrame_SetSelection" or "CraftFrame_SetSelection"
  if type(_G[setSel]) == "function" then hooksecurefunc(setSel, function() updateWindow(w) end) end
  frame:HookScript("OnShow", function(self)
    if not InCombatLockdown() then P.Place(self); self:Raise() end
    if C_Timer and C_Timer.After then C_Timer.After(0, function() if self:IsShown() then P.Place(self) end end) end -- once more after the panel manager
    P.UpdateTabs(w.tabs, P.TabList(P.Classify(P.ReadLines())), nil)
    onCraftingShow()
    updateWindow(w)
  end)
  if frame:IsShown() then onCraftingShow(); updateWindow(w) end
end

P.windows = {}
-- The panel manager re-anchors a shown panel after OnShow: put every Professions page back on the shared geometry afterwards.
if type(_G.UpdateUIPanelPositions) == "function" then
  hooksecurefunc("UpdateUIPanelPositions", function()
    for _, w in pairs(P.windows) do if w.frame:IsShown() then P.Place(w.frame) end end
  end)
end
local function tryRestyle()
  if not AFUI.ModuleEnabled("professions") then return end -- the client's own trade skill / craft windows (Settings > Windows)
  for key, d in pairs(DESC) do
    if not P.windows[key] and _G[d.frame] and type(_G[d.update]) == "function" then
      xpcall(function() restyle(key) end, geterrorhandler())
    end
  end
end

---------------------------------------------------------------- bindings, slash, events
local keyOwner = CreateFrame("Frame")
local toggle = CreateFrame("Button", "AFUI_ProfessionsToggle", UIParent)
toggle:SetScript("OnClick", function() P.Toggle() end)

local function bindKey()
  AFUI.RunOutOfCombat(function()
    ClearOverrideBindings(keyOwner)
    SetOverrideBindingClick(keyOwner, false, "K", "AFUI_ProfessionsToggle")
  end)
end

SLASH_AFUIPROFESSIONS1 = "/professions"
SLASH_AFUIPROFESSIONS2 = "/prof"
SlashCmdList["AFUIPROFESSIONS"] = function()
  if not AFUI.ModuleEnabled("professions") then AFUI.Print("Aztra's Forever UI: the Professions window is switched off (Settings > Windows)."); return end
  P.Toggle()
end

function P.Setup()
  if overview then return end
  overview = buildOverview()
  P.overview = overview
  bindKey()
  tryRestyle()
end

AFUI.On("UPDATE_BINDINGS", function() if overview then bindKey() end end)
AFUI.On("ADDON_LOADED", function() tryRestyle() end)
local function refresh() bookCache = nil; if overview and overview:IsShown() then P.RefreshOverview() end end
-- a skill went up: every shown page re-reads its rank (the bar plays the skill-up when the same skill's rank is higher than the last one drawn)
local function refreshWindows() for _, w in pairs(P.windows) do if w.frame:IsShown() then updateWindow(w) end end end
AFUI.On("SKILL_LINES_CHANGED", function() linesCache = nil; refresh(); refreshWindows() end)
AFUI.On("CHAT_MSG_SKILL", function() linesCache = nil; refresh(); refreshWindows() end)

-- /afui skillup [ranks]: plays the skill-up on the bar you are looking at (the open page's bar, else the first overview card's), from `ranks` (5) below
-- its current rank up to it.
function P.DebugSkillUp(ranks)
  local bar
  for _, w in pairs(P.windows) do if w.frame:IsShown() and w.bar:IsShown() then bar = w.bar end end
  if not bar and overview and overview:IsShown() then
    for _, c in ipairs({ overview.content.primary1, overview.content.primary2, overview.content.cooking, overview.content.fishing, overview.content.firstaid }) do
      if not bar and c.bar:IsShown() then bar = c.bar end
    end
  end
  if not (bar and bar.shownRank) then AFUI.Print("Aztra's Forever UI: open the Professions window first."); return false end
  return P.PlaySkillUp(bar, math.max(0, bar.shownRank - (tonumber(ranks) or 5)), bar.shownRank)
end
AFUI.Slash.Register("skillup", P.DebugSkillUp, "plays the Professions skill-up animation on the open bar", "/afui skillup [ranks]")
AFUI.On("SPELLS_CHANGED", refresh)
AFUI.On("TRADE_SKILL_SHOW", function() onCraftingShow() end)
AFUI.On("CRAFT_SHOW", function() onCraftingShow() end)

-- the window pieces the Social / Quest Log / Group Finder skins (WinKit.lua) build on
P.Kit = { chrome = chrome, closeButton = closeButton, atlasTex = atlasTex, newSearch = newSearch, skinScrollBar = skinScrollBar, hideRegions = hideRegions, ROCK_TINT = ROCK_TINT }

AFUI.RegisterModule("Professions", { OnLogin = P.Setup })
