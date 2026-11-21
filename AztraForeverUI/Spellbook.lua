-- Forever's Spellbook look on Blizzard's own SpellBookFrame (docs/forever-ref/spellbook.md).
-- Forever reference: tools/ref/interface/addons/blizzard_playerspells/{camelot,spellbook}/ (blizzard_spellbookframe.{lua,xml},
-- blizzard_spellbooktemplates.xml, blizzard_spellbookitem.{lua,xml}), look = docs/forever-ref/screens/windows/addonspellbookforever_*.png
-- (a real Forever capture: metal portrait frame, title, red X, square icon tabs with a gold glow, parchment book pages, "Page 1 / 1" with two
-- arrow buttons, a search box top right).
-- Client facts (verified): 2.4.3 MOUZU/Blizzard-WoW-Interface 2.4.3/FrameXML/SpellBookFrame.{xml,lua} and 2.5.3 Gethe/wow-ui-source tag 2.5.3
-- Interface/FrameXML/SpellBookFrame.{xml,lua}: SpellBookFrame 384x512 (hit rect insets 0,30,0,70), SpellButton1..12 (SpellButtonTemplate, a
-- CheckButton + SecureFrameTemplate, ids 1-6 left column and 7-12 right column), SpellBookSkillLineTab1..8 on the right edge,
-- SpellBookFrameTabButton1..3 (Spellbook / Pet), SpellBookPrevPageButton / NextPageButton / SpellBookPageText, SpellBookTitleText,
-- SpellBookCloseButton. 2.5.3 adds the SpellBookSpellIconsFrame / SpellBookSideTabsFrame / SpellBookPageNavigationFrame holders.
-- The spell buttons stay Blizzard's (click casts, drag to bars, shift-click link, autocast, cooldowns, passive / rank text): only their art,
-- size, position and text styling change, every move out of combat.
AFUI = AFUI or {}

local PLAIN = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\"
local ROCK_TINT = { 0.6, 0.54, 0.5 }
local BROWN = { 0.21, 0.11, 0.05 } -- the dark ink of Forever's parchment text (SPELLBOOK_FONT_COLOR, sampled from the capture)
local FADED = { 0.45, 0.3, 0.17 }

---------------------------------------------------------------- pure layout maths
local S = {}
AFUI.SpellbookLayout = S

S.BOOK_H = 698
S.BOOK_MAX, S.BOOK_MIN = 1148, 574 -- SpellBookFrame maximized (two pages) / minimized (one page) width (camelot playerspellsframe.xml)
S.WIN_H = 723 -- the capture: 1017 px at 1.40625 px per unit (+ the metal frame: 21 px title strip and 4 px bottom; 3 px at each side)
S.BOOK_X, S.BOOK_Y = 3, -21 -- book TOPLEFT in the window
S.ROWS_TOP = 169 -- the capture's first row (the heading and its divider sit above)
S.ROWS_TOP_R = 107 -- the right page of the two page book has no heading: its first row starts higher
S.ROW_STEP, S.COL_STEP = 70, 235 -- cell 220 x 60 + yPadding 10 / xPadding 15
S.VIEW_W = 448

function S.BookWidth(maximized) return maximized and S.BOOK_MAX or S.BOOK_MIN end
function S.WinWidth(maximized) return S.BookWidth(maximized) + 6 end

-- Forever opens the book minimized (one page, camelot SetMinimizedOnNextShow): Blizzard's buttons 1-12 are two columns by six rows (the
-- client's own ids put the first six spells down the left column, the next six down the right one: the capture's General tab reads that way).
-- Maximized (the open two sheet book): 24 spells per page, 12 on the left sheet and 12 on the right, each sheet two columns by six rows.
-- TAINT-SAFE PAGING (why it looks like this): the client's paging state (SPELLS_PER_PAGE, SPELLBOOK_PAGENUMBERS, SpellBookFrame.currentPage) is
-- never written, no Blizzard function is replaced, and no SpellButtonN / SpellButtonTemplate button is created or reparented: any of those
-- taints the book's own secure update code ("AztraForeverUI has been blocked from an action only available to the Blizzard UI").
-- Compact = Blizzard's own 12 buttons and its own paging, untouched. Expanded = Blizzard's 12 buttons and its two arrows are hidden (out of
-- combat) and 24 ADDON-OWNED SecureActionButtons (AFUISpellExtra1..24, children of our own container) draw the page from the same tab's slot
-- numbers (GetSpellTabInfo offset + our own page counter); our own arrows page in steps of 24. Returns page, column, row (0 based).
function S.Cell(i, maximized)
  local k = (i - 1) % 12
  if maximized then return i > 12 and 2 or 1, math.floor(k / 6), k % 6 end -- down the left column, then down the right one (like Blizzard's own ids 1-12)
  return 1, k % 2, math.floor(k / 2)
end

S.EXTRA = 24 -- spells per page of the open book (12 per sheet)
function S.PerPage(maximized) return maximized and S.EXTRA or 12 end
function S.NumPages(total, maximized) return math.max(1, math.ceil((total or 0) / S.PerPage(maximized))) end
function S.ClampPage(page, total, maximized) return math.min(math.max(page or 1, 1), S.NumPages(total, maximized)) end
-- first slot (absolute book index) and how many spells the page holds; a tab with no spells has count 0
function S.PageRange(offset, total, page, maximized)
  local per = S.PerPage(maximized)
  local first = (offset or 0) + (S.ClampPage(page, total, maximized) - 1) * per + 1
  return first, math.max(0, math.min(per, (offset or 0) + (total or 0) - first + 1))
end

-- TOPLEFT of the cell in book coordinates (y negative).
function S.Position(i, maximized)
  local page, col, row = S.Cell(i, maximized)
  local x0 = page == 1 and 85 or (S.BOOK_MAX - 50 - S.VIEW_W)
  return x0 + col * S.COL_STEP, -((page == 1 and S.ROWS_TOP or S.ROWS_TOP_R) + row * S.ROW_STEP)
end


function S.TabPos(i) return 73 + (i - 1) * 45, -37 end -- TOPLEFT of skill line tab i in the window

function S.PageText(cur, max)
  return string.format("Page %d/%d", cur or 1, math.max(max or 1, 1))
end

-- Part of the spell name, any case, no patterns. No text matches everything; a missing name matches nothing once there is text.
function S.Matches(name, text)
  if not text or text == "" then return true end
  if not name then return false end
  return string.find(string.lower(name), string.lower(text), 1, true) ~= nil
end

-- "Rank 3" -> 3; passives, talents and single-rank spells have no number.
function S.RankNumber(sub)
  local n = type(sub) == "string" and string.match(sub, "(%d+)")
  return n and tonumber(n) or nil
end


-- A window taller than the room below the panel line shrinks to fit (never grows).
function S.FitScale(h, screenH)
  local avail = screenH - 114 -- the panel manager puts a centred panel 104 px below the top
  if h <= avail then return 1 end
  return avail / h
end

---------------------------------------------------------------- the module
local Spellbook = {}
AFUI.Spellbook = Spellbook

local function setShown(o, on) if on then o:Show() else o:Hide() end end

local function atlasTex(parent, layer, name, w, h, sub)
  local t = parent:CreateTexture(nil, layer, nil, sub)
  AFUI.SetAtlas(t, name)
  if w then t:SetWidth(w); t:SetHeight(h) end
  return t
end

-- A wide atlas drawn as its tiles side by side across w x h (Media/Atlas.lua splits art wider than a texture page).
local function drawTiled(texs, parent, layer, name, x, y, w, h, crop) -- crop: share of the art's top left out (the mounts page starts below the tabs)
  local tiles = AFUI_ATLAS_TILES and AFUI_ATLAS_TILES[name] or { name }
  local total = 0
  for _, t in ipairs(tiles) do total = total + AFUI_ATLAS[t][2] end
  local cx = x
  for i, t in ipairs(tiles) do
    local e = AFUI_ATLAS[t]
    local tex = texs[i] or parent:CreateTexture(nil, layer)
    texs[i] = tex
    local tw = e[2] * w / total
    tex:SetTexture(e[1]); tex:SetTexCoord(e[4], e[5], e[6] + (e[7] - e[6]) * (crop or 0), e[7])
    tex:ClearAllPoints(); tex:SetPoint("TOPLEFT", parent, "TOPLEFT", cx, y)
    tex:SetWidth(tw); tex:SetHeight(h)
    cx = cx + tw
  end
end

S.DrawTiled = drawTiled

local VERTICAL = { ["!ui-frame-metal-edgeleft-c60-2x"] = true, ["!ui-frame-metal-edgeright-c60-2x"] = true }
local function skinChrome(win, w)
  win.pieces = win.pieces or {}
  for i, p in ipairs(AFUI.WorldMapPieces(w, S.WIN_H, true)) do
    local t = win.pieces[i]
    if not t then t = win:CreateTexture(nil, "OVERLAY"); win.pieces[i] = t end
    AFUI.SetAtlas(t, p.atlas)
    local e = AFUI_ATLAS and AFUI_ATLAS[string.lower(p.atlas)]
    if e and p.crop and p.crop < 1 then
      if VERTICAL[p.atlas] then t:SetTexCoord(e[4], e[5], e[6], e[6] + (e[7] - e[6]) * p.crop)
      else t:SetTexCoord(e[4], e[4] + (e[5] - e[4]) * p.crop, e[6], e[7]) end
    end
    t:SetWidth(p.w); t:SetHeight(p.h)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", win, "TOPLEFT", p.x, p.y)
    t:Show()
  end
  for i = #AFUI.WorldMapPieces(w, S.WIN_H, true) + 1, #win.pieces do win.pieces[i]:Hide() end
end

local function brown(fs, c, a) if fs then fs:SetTextColor(c[1], c[2], c[3], a or 1) end end

-- every Texture / FontString region of a frame, as a list
local function regionsOf(f)
  local out = {}
  if f.GetRegions then
    local n = select("#", f:GetRegions())
    for i = 1, n do out[i] = (select(i, f:GetRegions())) end
  end
  return out
end

local function maximized() return Spellbook.maximized and true or false end
Spellbook.max = maximized
-- Our own paged buttons draw the book when it is open, and also in the small book while "Hide Passives" is on: the visible spells are packed into the grid and the pages
-- re-counted (Blizzard's 12 buttons would leave holes where the passives were). drawnHide is the filter as last DRAWN (set out of combat only).
local function extrasOn() return maximized() or (Spellbook.drawnHide and true or false) end
Spellbook.extrasOn = extrasOn

local function slotOf(btn)
  if btn.slot then return btn.slot end -- our own extra buttons know their slot
  local ok, slot = pcall(function()
    if _G.SpellBook_GetSpellBookSlot then return _G.SpellBook_GetSpellBookSlot(btn) end
    if _G.SpellBook_GetSpellID then return _G.SpellBook_GetSpellID(btn:GetID()) end
  end)
  return ok and slot or nil
end

local function isPassive(btn)
  local slot = slotOf(btn)
  if not slot or not _G.IsPassiveSpell then return false end
  local ok, r = pcall(_G.IsPassiveSpell, slot, btn.book or _G.SpellBookFrame.bookType or "spell")
  return ok and r and true or false
end

---------------------------------------------------------------- one spell button
local function setupButton(btn)
  if btn.afSetup then return end
  btn.afSetup = true
  local name = btn:GetName()
  btn.afName = btn.afName or _G[name .. "SpellName"]
  btn.afSub = btn.afSub or _G[name .. "SubSpellName"]
  btn.afIcon = btn.afIcon or _G[name .. "IconTexture"]
  btn.afBack = atlasTex(btn, "BACKGROUND", "spellbook-item-backplate", 256, 64)
  btn.afBack:SetPoint("CENTER", btn, "CENTER", 95, -5)
  btn.afBack:SetAlpha(0.25)
  btn.afBorder = atlasTex(btn, "OVERLAY", "spellbook-item-iconframe-c60")
  btn.afShadow = atlasTex(btn, "BACKGROUND", "spellbook-item-iconframe-shadow")
  btn.afShadow:SetPoint("TOPLEFT", btn, "TOPLEFT", -12, 3); btn.afShadow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -8)
  btn:HookScript("OnEnter", function(self) self.afBack:SetAlpha(1) end)
  btn:HookScript("OnLeave", function(self) self.afBack:SetAlpha(0.25) end)
  -- Blizzard's slot plate and rounded quickslot border go; they come back through SetAlpha / SetVertexColor so those are reset each update
  local bg = _G[name .. "Background"]
  if bg then bg:Hide() end
  btn.afSlot = bg
  btn.afNormal = btn:GetNormalTexture()
end

local function styleButton(btn)
  setupButton(btn)
  local has = btn.afIcon and btn.afIcon:IsShown() and btn.afIcon:GetTexture() ~= nil
  if btn.afSlot then btn.afSlot:SetAlpha(0) end
  if btn.afNormal then btn.afNormal:SetAlpha(0) end
  local passive = has and isPassive(btn)
  -- icon 36 x 36 inside the frame, rounded corners cropped away
  if btn.afIcon then
    btn.afIcon:ClearAllPoints(); btn.afIcon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.afIcon:SetWidth(36); btn.afIcon:SetHeight(36)
    btn.afIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end
  -- Forever's art sets (blizzard_spellbookitem.lua ArtSet): Square for abilities (-11,1 / 1,-7), Circle for passives (flush)
  local b = btn.afBorder
  b:ClearAllPoints()
  if passive then
    AFUI.SetAtlas(b, "spellbook-passive-iconframe-c60")
    b:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0); b:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
  else
    AFUI.SetAtlas(b, "spellbook-item-iconframe-c60")
    b:SetPoint("TOPLEFT", btn, "TOPLEFT", -11, 1); b:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -7)
  end
  setShown(b, has); setShown(btn.afShadow, has and not passive); setShown(btn.afBack, has)
  -- text: 16 pt name over the rank, left aligned, dark ink (SystemFont_Large / Med1 in Forever's template)
  local n, sub = btn.afName, btn.afSub
  if n then
    n:SetFontObject(GameFontNormalLarge or GameFontNormal)
    n:SetWidth(168); n:SetJustifyH("LEFT")
    n:ClearAllPoints(); n:SetPoint("LEFT", btn, "RIGHT", 10, (sub and sub:IsShown() and sub:GetText() and sub:GetText() ~= "") and 8 or 0)
    brown(n, BROWN)
  end
  if sub then
    sub:SetFontObject(GameFontNormal); sub:SetWidth(168); sub:SetJustifyH("LEFT")
    sub:ClearAllPoints(); sub:SetPoint("TOPLEFT", n or btn, "BOTTOMLEFT", 0, -2)
    brown(sub, FADED)
  end
  -- search: spells that do not match fade
  -- the open book hides Blizzard's 12 buttons (alpha too, so a Blizzard re-show during combat stays invisible); our extras draw the page
  btn:SetAlpha(((Spellbook.drawnHide and passive) or (extrasOn() and not btn.afExtra)) and 0 or (S.Matches(n and n:GetText(), Spellbook.searchText) and 1 or 0.3))
end

---------------------------------------------------------------- skill line tabs (Forever's square icon tabs across the top)
local function styleTab(tab, i)
  if not tab then return end
  if not tab.afSetup then
    tab.afSetup = true
    for _, r in ipairs(regionsOf(tab)) do -- the old 64 x 64 tab plate
      if r.GetTexture and r:GetObjectType() == "Texture" and string.find(string.lower(tostring(r:GetTexture() or "")), "skilllinetab", 1, true) then r:Hide() end
    end
    tab.afFrame = atlasTex(tab, "OVERLAY", "spellbook-tab-frame-c60", 43, 38, 1)
    tab.afFrame:SetPoint("CENTER", tab, "CENTER", 0, 0)
    tab.afGlow = atlasTex(tab, "OVERLAY", "spellbook-tab-frame-glow-c60", 43, 38, 2)
    tab.afGlow:SetPoint("CENTER", tab, "CENTER", 0, 0)
    tab.afGrad = atlasTex(tab, "OVERLAY", "spellbook-tab-frame-glow-gradient-c60", 43, 38, 3)
    tab.afGrad:SetPoint("CENTER", tab, "CENTER", 0, 0); tab.afGrad:SetAlpha(0.6)
    tab:HookScript("OnClick", function() Spellbook.UpdateTabs() end)
    tab:HookScript("PreClick", function() Spellbook.blizzKey = nil end) -- a click on the client's own tab always shows that tab's first page
  end
  local ck = tab:GetCheckedTexture()
  if ck then ck:SetAlpha(0) end
  local icon = tab:GetNormalTexture()
  if icon then
    icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", tab, "TOPLEFT", 1, -1); icon:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end
  local on = tab:GetChecked() and true or false
  local ours = Spellbook.shownTab()
  if ours then on = (ours == i) end
  setShown(tab.afGlow, on); setShown(tab.afGrad, on)
end

-- the open book's own selection (the secure tab overlays move it in combat while the client's checked tab stays put); nil in the small book
function Spellbook.shownTab()
  if not extrasOn() then return nil end
  return tonumber(string.match(Spellbook.pageKey or "", "^spell(%d+)$"))
end

function Spellbook.UpdateTabs()
  for i = 1, 8 do styleTab(_G["SpellBookSkillLineTab" .. i], i) end
  -- the title and the portrait follow the book (spells: the first skill line's icon, like camelot's SetSpellBookPortrait)
  local w = Spellbook.win
  if not w then return end
  if _G.SpellBookTitleText and w.title then w.title:SetText(_G.SpellBookTitleText:GetText() or "Spellbook") end
  local heading
  local pet = _G.SpellBookFrame.bookType == "pet"
  if pet then heading = (UnitName and UnitName("pet")) or "Pet"
  else
    local ours = Spellbook.shownTab()
    if ours and GetSpellTabInfo then heading = GetSpellTabInfo(ours) end
    for i = 1, heading and 0 or 8 do
      local t = _G["SpellBookSkillLineTab" .. i]
      if t and t:IsShown() and t:GetChecked() and GetSpellTabInfo then heading = GetSpellTabInfo(i); break end
    end
  end
  w.header:SetText(heading or "")
end

---------------------------------------------------------------- Spellbook / Pet buttons: the page header's filter links (Forever's "All  Combined  Favorites" row)
local function styleBookTabs()
  local x = 380
  local count = 0 -- the capture's rogue has no pet book: a lone Spellbook link is not drawn
  for i = 1, 3 do local b = _G["SpellBookFrameTabButton" .. i]; if b and b:IsShown() then count = count + 1 end end
  for i = 1, 3 do
    local b = _G["SpellBookFrameTabButton" .. i]
    if b then
      b:SetAlpha(count >= 2 and 1 or 0)
      if not b.afSetup then
        b.afSetup = true
        b:SetNormalTexture(""); b:SetDisabledTexture(""); b:SetHighlightTexture("")
        for _, r in ipairs(regionsOf(b)) do if r:GetObjectType() == "Texture" then r:Hide() end end
        b.afLine = b:CreateTexture(nil, "OVERLAY"); b.afLine:SetHeight(2)
        b.afLine:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 2); b.afLine:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 2)
        AFUI.SetColor(b.afLine, BROWN[1], BROWN[2], BROWN[3], 1)
        b:SetHitRectInsets(0, 0, 0, 0)
      end
      local fs = b:GetFontString()
      if fs then fs:SetFontObject(GameFontNormalLarge or GameFontNormal); b:SetWidth((fs:GetStringWidth() or 60) + 8); b:SetHeight(24) end
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", _G.SpellBookFrame, "TOPLEFT", S.BOOK_X + x, S.BOOK_Y - 104)
      local selected = not b:IsEnabled() -- Blizzard disables the active tab
      if fs then if selected then brown(fs, BROWN) else brown(fs, FADED) end end
      setShown(b.afLine, selected)
      if b:IsShown() then x = x + (b:GetWidth() or 60) + 20 end
    end
  end
end

---------------------------------------------------------------- search box (Forever: the SpellSearchBox top right; here it fades the spells that do not match)
local function makeSearch(win)
  local e = CreateFrame("EditBox", "AFUI_SpellbookSearch", win, "InputBoxTemplate")
  e:SetAutoFocus(false); e:SetHeight(20); e:SetWidth(218); e:SetMaxLetters(40)
  for _, k in ipairs({ "Left", "Middle", "Right" }) do local t = _G["AFUI_SpellbookSearch" .. k]; if t then t:Hide() end end
  local l = atlasTex(e, "BACKGROUND", "common-input-left"); l:SetPoint("TOPLEFT", e, "TOPLEFT", -4, 3); l:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT", -4, -3); l:SetWidth(10)
  local r = atlasTex(e, "BACKGROUND", "common-input-left"); r:SetPoint("TOPRIGHT", e, "TOPRIGHT", 4, 3); r:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 4, -3); r:SetWidth(10)
  do local en = AFUI_ATLAS and AFUI_ATLAS["common-input-left"]; if en then r:SetTexCoord(en[5], en[4], en[6], en[7]) end end
  local m = atlasTex(e, "BACKGROUND", "common-input-middle"); m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  local mag = atlasTex(e, "OVERLAY", "common-search-magnifyingglass", 10, 10); mag:SetPoint("LEFT", e, "LEFT", 1, -1)
  e:SetTextInsets(16, 8, 0, 0)
  e.hint = e:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  e.hint:SetPoint("LEFT", e, "LEFT", 16, 0); e.hint:SetText(ENTER_SEARCH_TEXT or "Enter search text")
  e:SetScript("OnTextChanged", function(self)
    Spellbook.searchText = self:GetText()
    setShown(self.hint, Spellbook.searchText == "" and not self:HasFocus())
    Spellbook.UpdateButtons()
  end)
  e:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
  e:SetScript("OnEditFocusLost", function(self) setShown(self.hint, self:GetText() == "") end)
  return e
end

-- The gold triangle after the search box: a small menu of ticked option "Hide Passives" (Forever's second one, grouping on flyouts, needs hiding Blizzard's secure buttons: not done; Blizzard's own "Show all ranks" checkbox handles ranks where the client has it).
local function makeFilter(win, level)
  local dd = CreateFrame("Button", nil, win)
  dd:SetWidth(19); dd:SetHeight(19); dd:SetFrameLevel(level)
  AFUI.SetButtonAtlas(dd, { "common-dropdown-a-button", "common-dropdown-a-button-pressed", "common-dropdown-a-button-hover", "common-dropdown-a-button-disabled" }, 0.6)
  local menu = CreateFrame("Frame", nil, win)
  menu:SetFrameLevel(level + 10); menu:SetWidth(150); menu:SetHeight(50); menu:SetPoint("TOPRIGHT", dd, "BOTTOMRIGHT", 0, -4); menu:Hide()
  local bg = menu:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(bg, 0.05, 0.05, 0.05, 0.95); bg:SetAllPoints(menu)
  local syncs = {}
  local function option(row, text, isOn, toggle)
    local opt = CreateFrame("Button", nil, menu)
    opt:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -(row - 1) * 25); opt:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, -(row - 1) * 25); opt:SetHeight(25)
    local hl = opt:CreateTexture(nil, "HIGHLIGHT"); AFUI.SetColor(hl, 1, 0.82, 0, 0.25); hl:SetAllPoints(opt)
    local tick = atlasTex(opt, "OVERLAY", "checkmark-minimal", 14, 14); tick:SetPoint("LEFT", opt, "LEFT", 6, 0)
    local fs = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); fs:SetPoint("LEFT", opt, "LEFT", 24, 0); fs:SetText(text)
    opt:SetScript("OnClick", function() toggle(); menu:Hide() end)
    syncs[#syncs + 1] = function() setShown(tick, isOn()) end
  end
  option(1, "Hide Passives", function() return Spellbook.hidePassives end, function()
    Spellbook.hidePassives = not Spellbook.hidePassives
    if type(AztraForeverUIDB) == "table" then AztraForeverUIDB.spellbook = AztraForeverUIDB.spellbook or {}; AztraForeverUIDB.spellbook.hidePassives = Spellbook.hidePassives end
    if InCombatLockdown() then Spellbook.Pending(true) end
    AFUI.RunOutOfCombat(function() Spellbook.SyncBook(); Spellbook.UpdateButtons() end) -- re-flows the pages; in combat the last layout stays until combat ends
  end)
  dd:SetScript("OnClick", function() for _, f in ipairs(syncs) do f() end; setShown(menu, not menu:IsShown()) end)
  win:HookScript("OnHide", function() menu:Hide() end)
  return dd
end

function Spellbook.UpdateButtons()
  for i = 1, 12 do local b = _G["SpellButton" .. i]; if b and b:IsShown() then styleButton(b) end end
  for _, b in ipairs(Spellbook.extras or {}) do if b.slot then styleButton(b) end end -- alpha / art only: safe in combat
end

---------------------------------------------------------------- the open book's own buttons (see the taint note at S.Cell)
local function bookType() return _G.SpellBookFrame and _G.SpellBookFrame.bookType or "spell" end

-- book, key, first slot offset, spell count of what the book shows now (the checked skill line tab, or the pet book)
local function activeRange()
  local book = bookType()
  if book == "pet" then
    local n = _G.HasPetSpells and _G.HasPetSpells()
    return book, "pet", 0, type(n) == "number" and n or 0
  end
  local tab = _G.SpellBookFrame and _G.SpellBookFrame.selectedSkillLine
  if not tab then
    for i = 1, 8 do local t = _G["SpellBookSkillLineTab" .. i]; if t and t:IsShown() and t:GetChecked() then tab = i; break end end
  end
  tab = tab or 1
  local offset, n = 0, 0
  if _G.GetSpellTabInfo then local _; _, _, offset, n = _G.GetSpellTabInfo(tab) end
  return book, book .. tab, offset or 0, n or 0
end

local function spellName(slot, book)
  if _G.GetSpellBookItemName then return _G.GetSpellBookItemName(slot, book) end
  if _G.GetSpellName then return _G.GetSpellName(slot, book) end
end

local function updateCooldown(b)
  if b.slot and _G.GetSpellCooldown then
    local start, dur = _G.GetSpellCooldown(b.slot, b.book)
    b.afCooldown:SetCooldown(start or 0, dur or 0)
  end
end

local function fillExtra(b, slot, book)
  local nm, sub = spellName(slot, book)
  if not nm then b.slot = nil; b:Hide(); return end
  b.slot, b.book = slot, book
  b.afIcon:SetTexture(_G.GetSpellTexture and _G.GetSpellTexture(slot, book)); b.afIcon:Show()
  b.afName:SetText(nm); b.afName:Show(); b.afSub:SetText(sub or ""); b.afSub:Show()
  local passive = _G.IsPassiveSpell and _G.IsPassiveSpell(slot, book)
  -- secure attributes are only written out of combat; "Name(Rank n)" only when the sub text really is a rank
  b:SetAttribute("type", (not passive) and "spell" or nil)
  b:SetAttribute("spell", (not passive) and ((sub and sub:find("%d")) and (nm .. "(" .. sub .. ")") or nm) or nil)
  updateCooldown(b)
  styleButton(b)
  b:Show()
end

local function emptyExtra(b)
  b.slot = nil
  b:SetAttribute("type", nil); b:SetAttribute("spell", nil)
  b:Hide()
end

local function makeExtra(parent, n)
  local name = "AFUISpellExtra" .. n
  local b = CreateFrame("CheckButton", name, parent, "SecureActionButtonTemplate")
  b.afExtra = true
  b:SetWidth(40); b:SetHeight(40)
  b.afIcon = b:CreateTexture(nil, "BORDER"); b.afIcon:SetAllPoints(b)
  b.afName = b:CreateFontString(name .. "SpellName", "ARTWORK", "GameFontNormal")
  b.afSub = b:CreateFontString(name .. "SubSpellName", "ARTWORK", "GameFontNormalSmall")
  b.afCooldown = CreateFrame("Cooldown", name .. "Cooldown", b, "CooldownFrameTemplate")
  b.afCooldown:SetAllPoints(b)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:RegisterForClicks("LeftButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self)
    local pick = _G.PickupSpellBookItem or _G.PickupSpell
    if self.slot and pick then pick(self.slot, self.book) end
  end)
  b:SetScript("OnEnter", function(self)
    if not self.slot then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetSpellBookItem then GameTooltip:SetSpellBookItem(self.slot, self.book) else GameTooltip:SetSpell(self.slot, self.book) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  setupButton(b)
  b:Hide()
  return b
end

---------------------------------------------------------------- the open book in combat
-- What the client forbids to addon code in combat is Show / Hide / SetAttribute / SetPoint / resize on protected frames (the 24 spell buttons are
-- ours and secure). So everything the open book needs in combat is built BEFORE combat and only switched by RESTRICTED SNIPPETS, which run in
-- the secure environment and may show / hide protected frames through frame references:
--   * one SecureHandlerBase PAGE CONTAINER per skill line tab and page (AFUISpellPage<n>), each holding its own 24 spell buttons (spell attributes
--     written out of combat by Rebuild); the current page is the one container that is shown;
--   * AFUISpellRoot (SecureHandlerState) keeps "key" (spell1.., pet), "page", "np_<key>" (page count), "max" and the frame refs "c_<key>_<page>";
--   * the two page arrows are SecureHandlerClick buttons: _onclick hides the shown container and shows the next one;
--   * the skill line tabs sit under a transparent SecureHandlerClick overlay that exists only in combat (root _onstate-combat shows them while the
--     book is open and in combat, hides them out of it): out of combat the client's own tabs work as before.
-- Insecure code only reads the attributes afterwards (OnAttributeChanged) to update unprotected art: "Page n/N", arrow dimming, the tab glow.
-- Things that stay queued until combat ends (a grey "in combat" hint shows): the compact / expanded switch (it resizes and re-anchors the window,
-- which carries protected buttons), rebuilding the pages after SPELLS_CHANGED, and the client's own Spellbook / Pet book tabs.
-- 2.4.3 has no secure handlers (no SecureHandlerSetFrameRef): there the paging simply waits for the end of combat.
local SNIP_PAGE = [[
local root = self:GetFrameRef("root")
local key, page = root:GetAttribute("key"), root:GetAttribute("page")
if not key or not page then return end
local np = root:GetAttribute("np_" .. key) or 1
local new = page + self:GetAttribute("delta")
if new < 1 or new > np then return end
local old, nu = root:GetFrameRef("c_" .. key .. "_" .. page), root:GetFrameRef("c_" .. key .. "_" .. new)
if old then old:Hide() end
if nu then nu:Show() end
root:SetAttribute("page", new)
]]
local SNIP_TAB = [[
local root = self:GetFrameRef("root")
local key = self:GetAttribute("tabkey")
local nu = root:GetFrameRef("c_" .. key .. "_1")
if not nu then return end
local ck, cp = root:GetAttribute("key"), root:GetAttribute("page")
local old = ck and cp and root:GetFrameRef("c_" .. ck .. "_" .. cp)
if old then old:Hide() end
nu:Show()
root:SetAttribute("key", key)
root:SetAttribute("page", 1)
]]
local SNIP_COMBAT = [[
local on = (newstate == "1") and self:GetAttribute("max") == 1
for i = 1, 8 do
  local o = self:GetFrameRef("ov" .. i)
  if o then
    if on and o:GetAttribute("live") == 1 then o:Show() else o:Hide() end
  end
end
]]
Spellbook.SNIPPETS = { page = SNIP_PAGE, tab = SNIP_TAB, combat = SNIP_COMBAT }

local function secure() return type(_G.SecureHandlerSetFrameRef) == "function" end

-- a transparent secure click button that runs `snippet` (arrows: delta -1 / +1)
function Spellbook.MakeArrow(parent, delta)
  local b = CreateFrame("Button", nil, parent, secure() and "SecureHandlerClickTemplate" or nil)
  if secure() then
    b:SetAttribute("delta", delta)
    b:SetAttribute("_onclick", SNIP_PAGE)
    _G.SecureHandlerSetFrameRef(b, "root", Spellbook.root)
  else
    b:SetScript("OnClick", function() Spellbook.ChangePage(delta) end)
  end
  return b
end

function Spellbook.MakeExtras(parent)
  local sec = secure()
  Spellbook.extras, Spellbook.pool, Spellbook.map, Spellbook.keys, Spellbook.overlays = {}, {}, {}, {}, {}
  local root = CreateFrame("Frame", "AFUISpellRoot", parent, sec and "SecureHandlerStateTemplate" or nil)
  root:SetAllPoints(parent)
  Spellbook.root = root
  root:HookScript("OnAttributeChanged", function() Spellbook.OnState() end)
  if sec then
    root:SetAttribute("_onstate-combat", SNIP_COMBAT)
    RegisterStateDriver(root, "combat", "[combat] 1; 0")
    for i = 1, 8 do
      local o = CreateFrame("Button", "AFUISpellTabOverlay" .. i, parent, "SecureHandlerClickTemplate")
      o:SetWidth(36); o:SetHeight(32); o:SetFrameLevel(parent:GetFrameLevel() + 31)
      o:SetPoint("TOPLEFT", parent, "TOPLEFT", S.TabPos(i))
      o:RegisterForClicks("LeftButtonUp")
      o:SetAttribute("tabkey", "spell" .. i); o:SetAttribute("live", 0)
      o:SetAttribute("_onclick", SNIP_TAB)
      _G.SecureHandlerSetFrameRef(o, "root", root); _G.SecureHandlerSetFrameRef(root, "ov" .. i, o)
      o:SetScript("OnEnter", function(self)
        local nm = _G.GetSpellTabInfo and _G.GetSpellTabInfo(i)
        if not nm then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(nm, 1, 1, 1); GameTooltip:Show()
      end)
      o:SetScript("OnLeave", function() GameTooltip:Hide() end)
      o:Hide()
      Spellbook.overlays[i] = o
    end
  end
  return Spellbook.extras
end

local function newContainer()
  local pool, parent = Spellbook.pool, Spellbook.root:GetParent()
  local c = { btn = {} }
  c.frame = CreateFrame("Frame", "AFUISpellPage" .. (#pool + 1), parent, secure() and "SecureHandlerBaseTemplate" or nil)
  c.frame:SetAllPoints(parent); c.frame:SetFrameLevel(parent:GetFrameLevel() + 3)
  c.frame:Hide()
  for i = 1, S.EXTRA do
    local b = makeExtra(c.frame, #Spellbook.extras + 1)
    c.btn[i] = b; Spellbook.extras[#Spellbook.extras + 1] = b
  end
  pool[#pool + 1] = c
  return c
end

-- { key, book, offset, total } for every skill line tab (and the pet book)
local function tabList()
  local list = {}
  if _G.GetSpellTabInfo then
    for t = 1, (_G.GetNumSpellTabs and _G.GetNumSpellTabs() or 8) do
      local name, _, offset, n = _G.GetSpellTabInfo(t)
      if not name then break end
      list[#list + 1] = { key = "spell" .. t, book = "spell", offset = offset or 0, total = n or 0 }
    end
  end
  local pn = _G.HasPetSpells and _G.HasPetSpells()
  if type(pn) == "number" and pn > 0 then list[#list + 1] = { key = "pet", book = "pet", offset = 0, total = pn } end
  return list
end

-- the book slots a tab shows, in order: every one, or without the passives while the filter is drawn
local function visibleSlots(t)
  local out = {}
  for slot = t.offset + 1, t.offset + t.total do
    local passive = false
    if Spellbook.drawnHide and _G.IsPassiveSpell then local good, r = pcall(_G.IsPassiveSpell, slot, t.book); passive = good and r and true or false end
    if not passive then out[#out + 1] = slot end
  end
  return out
end

-- every extra button on the cell of its number for the layout drawn (the small book's two columns or the open book's two sheets); out of combat only
local function placeExtras()
  local max, parent = maximized(), Spellbook.root and Spellbook.root:GetParent()
  if not parent then return end
  for _, c in ipairs(Spellbook.pool) do
    for i, b in ipairs(c.btn) do
      local x, y = S.Position(i, max)
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", parent, "TOPLEFT", S.BOOK_X + x, S.BOOK_Y + y)
    end
  end
end

-- (re)writes every page container from the client's spell lists; out of combat only (SetAttribute, Show, Hide, frame refs of protected frames)
function Spellbook.Rebuild()
  local list = tabList()
  local sig = {}
  for _, t in ipairs(list) do sig[#sig + 1] = t.key .. ":" .. t.offset .. ":" .. t.total end
  sig = table.concat(sig, ",") .. "|" .. (maximized() and "max" or "min") .. (Spellbook.drawnHide and "|nopassives" or "")
  if sig == Spellbook.sig and not Spellbook.dirty then return end
  Spellbook.sig, Spellbook.dirty = sig, false
  local root, used = Spellbook.root, 0
  local per = S.PerPage(maximized())
  for _, k in ipairs(Spellbook.keys) do root:SetAttribute("np_" .. k, nil) end
  Spellbook.keys, Spellbook.map = {}, {}
  for i = 1, 8 do if Spellbook.overlays[i] then Spellbook.overlays[i]:SetAttribute("live", 0) end end
  for _, t in ipairs(list) do
    local slots = visibleSlots(t)
    local pages = S.NumPages(#slots, maximized())
    Spellbook.keys[#Spellbook.keys + 1] = t.key
    root:SetAttribute("np_" .. t.key, pages)
    local ov = Spellbook.overlays[tonumber(string.match(t.key, "^spell(%d+)$") or 0)]
    if ov then ov:SetAttribute("live", 1) end
    for p = 1, pages do
      used = used + 1
      local c = Spellbook.pool[used] or newContainer()
      Spellbook.map[t.key .. "_" .. p] = c
      if secure() then _G.SecureHandlerSetFrameRef(root, "c_" .. t.key .. "_" .. p, c.frame) end
      for i = 1, S.EXTRA do
        local slot = i <= per and slots[(p - 1) * per + i]
        if slot then fillExtra(c.btn[i], slot, t.book) else emptyExtra(c.btn[i]) end
      end
    end
  end
  for j = used + 1, #Spellbook.pool do Spellbook.pool[j].frame:Hide() end
  placeExtras()
end

-- the buttons of one page (specs and callers that want "what the book shows")
function Spellbook.PageButtons(key, page)
  local c = Spellbook.map and Spellbook.map[(key or Spellbook.pageKey) .. "_" .. (page or Spellbook.page or 1)]
  return c and c.btn or {}
end

-- unprotected art that follows the secure state (runs in combat too: SetText / SetAlpha / SetShown on regions and plain frames only)
function Spellbook.OnState()
  local root = Spellbook.root
  if not root then return end
  local key, page = root:GetAttribute("key"), root:GetAttribute("page") or 1
  Spellbook.pageKey, Spellbook.page = key, page
  local win = Spellbook.win
  if not win then return end
  local np = key and root:GetAttribute("np_" .. key) or 1
  if win.prev then win.prev:SetAlpha(page <= 1 and 0.4 or 1); win.next:SetAlpha(page >= np and 0.4 or 1) end
  Spellbook.UpdatePageText(); Spellbook.UpdateTabs()
end

-- the subtle grey "in combat" hint while something waits for the end of combat
function Spellbook.Pending(on)
  local w = Spellbook.win
  if w and w.lock then setShown(w.lock, on and true or false) end
end

-- draws the open book's page (hides every page container in the small book); out of combat only
function Spellbook.UpdateExtras()
  local root = Spellbook.root
  if not root then return end
  local max = extrasOn()
  root:SetAttribute("max", max and 1 or 0)
  if max then Spellbook.Rebuild() end
  local _, key = activeRange()
  local cur = root:GetAttribute("key")
  -- the client's own tab moved (or the secure paging knows nothing yet): that tab's first page; otherwise keep the secure state (arrows, combat tabs)
  if key ~= Spellbook.blizzKey or not (cur and Spellbook.map[cur .. "_1"]) then cur = key; root:SetAttribute("key", key); root:SetAttribute("page", 1) end
  Spellbook.blizzKey = key
  local page = math.min(math.max(root:GetAttribute("page") or 1, 1), root:GetAttribute("np_" .. cur) or 1)
  if page ~= root:GetAttribute("page") then root:SetAttribute("page", page) end
  for k, c in pairs(Spellbook.map) do setShown(c.frame, max and k == cur .. "_" .. page) end
  local win = Spellbook.win
  if win and win.prev then setShown(win.prev, max); setShown(win.next, max) end
  Spellbook.OnState()
end

-- the open book hides Blizzard's 12 buttons and two arrows; the small book puts back what we hid (never what Blizzard hid itself)
function Spellbook.SyncBook()
  Spellbook.Pending(false)
  Spellbook.drawnHide = Spellbook.hidePassives and true or false
  local max = extrasOn()
  local list = {}
  for i = 1, 12 do list[#list + 1] = _G["SpellButton" .. i] end
  list[#list + 1] = _G.SpellBookPrevPageButton; list[#list + 1] = _G.SpellBookNextPageButton
  for _, b in ipairs(list) do
    if max then
      if b:IsShown() then b.afHid = true; b:Hide() end
    elseif b.afHid then b.afHid = nil; b:Show() end
  end
  Spellbook.UpdateExtras()
end

-- Insecure mirror of the arrows' snippet: the 2.4.3 arrows (no secure handlers) and the specs. Out of combat it moves now, in combat it waits.
local queuedDelta = 0
local function stepPages()
  local d, root = queuedDelta, Spellbook.root
  queuedDelta = 0
  if not root or not root:GetAttribute("key") then return end
  Spellbook.Pending(false)
  local key, page = root:GetAttribute("key"), root:GetAttribute("page") or 1
  local new = math.min(math.max(page + d, 1), key and root:GetAttribute("np_" .. key) or 1)
  if new == page then return end
  local old, nu = Spellbook.map[key .. "_" .. page], Spellbook.map[key .. "_" .. new]
  if old then old.frame:Hide() end
  if nu then nu.frame:Show() end
  root:SetAttribute("page", new); Spellbook.OnState()
end
function Spellbook.ChangePage(delta)
  queuedDelta = queuedDelta + delta
  if InCombatLockdown() then Spellbook.Pending(true) end
  AFUI.RunOutOfCombat(stepPages)
end

---------------------------------------------------------------- window

local function layout()
  local win, f = Spellbook.win, _G.SpellBookFrame
  local max = maximized()
  local bw, ww = S.BookWidth(max), S.WinWidth(max)
  f:SetWidth(ww); f:SetHeight(S.WIN_H)
  f:SetHitRectInsets(0, 0, 0, 0)
  local scale = S.FitScale(S.WIN_H, UIParent:GetHeight())
  f:SetScale(scale)
  -- the panel manager sizes and places the panel from these (UIPanelWindows has 424 high and the 16 px margin of the old art)
  local O = AFUI.WinKit and AFUI.WinKit.ORIGIN or { x = 17, y = -116 }
  -- the open book stands centred (native-spellbook-expanded-two-page: x 470-2110 of 2560, centre 1290); the compact book keeps the left panel column
  local x = O.x
  if max and UIParent.GetWidth then x = math.max(O.x, (UIParent:GetWidth() - ww * scale) / 2) end
  AFUI.PanelAttrs(f, { width = ww * scale, height = S.WIN_H * scale, xoffset = x / scale, yoffset = O.y / scale })
  -- chrome, rock and the book's pages for this width (minimized: one condensed page; maximized: the left and right pages)
  skinChrome(f, ww)
  win.rock:SetTexCoord(0, (ww - 4) / 512, 0, (S.WIN_H - 23) / 512)
  if max then
    drawTiled(win.pageL, f, "BORDER", "spellbook-page-left-c60", S.BOOK_X, S.BOOK_Y, bw / 2, S.BOOK_H)
    drawTiled(win.pageR, f, "BORDER", "spellbook-page-right-c60", S.BOOK_X + bw / 2, S.BOOK_Y, bw / 2, S.BOOK_H)
  else
    drawTiled(win.pageL, f, "BORDER", "spellbook-page-condensed-c60", S.BOOK_X, S.BOOK_Y, bw, S.BOOK_H)
  end
  for _, t in ipairs(win.pageL) do t:Show() end
  for _, t in ipairs(win.pageR) do setShown(t, max) end
  -- the maximize / minimize button of the corner (Forever's second red button)
  if max then AFUI.SetButtonAtlas(win.toggle, { "redbutton-condense", "redbutton-condense-pressed", "redbutton-highlight", "redbutton-condense-disabled" })
  else AFUI.SetButtonAtlas(win.toggle, { "redbutton-expand", "redbutton-expand-pressed", "redbutton-highlight", "redbutton-expand-disabled" }) end
  for i = 1, 12 do -- Blizzard's own 12 (the small book); our 24 per page sit in their containers, placed once when made
    local b = _G["SpellButton" .. i]
    if b then
      local x, y = S.Position(i, false)
      b:ClearAllPoints(); b:SetWidth(40); b:SetHeight(40)
      b:SetPoint("TOPLEFT", f, "TOPLEFT", S.BOOK_X + x, S.BOOK_Y + y)
    end
  end
  local shown = 0
  for i = 1, 8 do
    local t = _G["SpellBookSkillLineTab" .. i]
    if t then
      t:ClearAllPoints(); t:SetWidth(36); t:SetHeight(32)
      t:SetPoint("TOPLEFT", f, "TOPLEFT", S.TabPos(i))
      if t:IsShown() then shown = i end
    end
  end
  -- the search box fills the band to the right of the tabs
  -- the capture: search box ending 47 from the window's right edge (218 wide, 243 in the open book), the filter button after it
  win.search:ClearAllPoints(); win.search:SetPoint("TOPRIGHT", f, "TOPRIGHT", -47, -38)
  win.search:SetWidth(max and 243 or 218)
  if AFUI.Mounts then AFUI.Mounts.Layout() end
  win.filter:ClearAllPoints(); win.filter:SetPoint("LEFT", win.search, "RIGHT", 5, 0)
  -- paging: "Page 1 / 3" and the two arrow buttons at the book's bottom right (BOTTOMRIGHT -75, 40, spacing 8)
  local nextB, prevB = _G.SpellBookNextPageButton, _G.SpellBookPrevPageButton
  if nextB then nextB:ClearAllPoints(); nextB:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(3 + 82), 4 + 40) end -- native-spellbook-general: the arrows stand 40 u apart (centres), the pair 8 u left of the XML
  if prevB and nextB then prevB:ClearAllPoints(); prevB:SetPoint("RIGHT", nextB, "LEFT", -16, 0) end
  if win.prev and prevB then win.prev:ClearAllPoints(); win.prev:SetPoint("CENTER", prevB, "CENTER"); win.next:ClearAllPoints(); win.next:SetPoint("CENTER", nextB, "CENTER") end
  local ranks = _G.ShowAllSpellRanksCheckbox -- Blizzard's "show all ranks" checkbox (some builds): bottom left of the first page
  if ranks then ranks:ClearAllPoints(); ranks:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 90, 40) end
end

local function build()
  local f = _G.SpellBookFrame
  local win = {}
  Spellbook.win = win
  -- Blizzard's panel art (the old Spellbook-Icon and the four UI-SpellbookPanel pieces) goes; fontstrings are kept and restyled
  for _, r in ipairs(regionsOf(f)) do
    if r:GetObjectType() == "Texture" then r:Hide() end
  end
  if _G.SpellBookTitleText then _G.SpellBookTitleText:SetAlpha(0) end

  win.rock = f:CreateTexture(nil, "BACKGROUND"); win.rock:SetTexture(PLAIN .. "UI-Background-Rock"); win.rock:SetVertexColor(ROCK_TINT[1], ROCK_TINT[2], ROCK_TINT[3])
  win.rock:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -21); win.rock:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  win.pageL, win.pageR = {}, {}
  -- Forever's spellbook portrait is the closed brown book (the client's own Interface\Spellbook\Spellbook-Icon), cut to the ring like every window's
  win.portrait = f:CreateTexture(nil, "ARTWORK")
  win.portrait:SetWidth(62); win.portrait:SetHeight(62); win.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", -5, 7)
  AFUI.WindowPortrait(f, win.portrait)
  win.portrait:SetTexture("Interface\\Spellbook\\Spellbook-Icon")

  local tf = CreateFrame("Frame", nil, f); tf:SetAllPoints(f); tf:SetFrameLevel(f:GetFrameLevel() + 25) -- above the metal pieces
  win.title = tf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  win.title:SetPoint("TOP", f, "TOP", 11, -6); win.title:SetText("Spellbook")
  -- the page header: the skill line's name over Forever's divider
  win.header = tf:CreateFontString(nil, "OVERLAY", GameFontNormalHuge and "GameFontNormalHuge" or "GameFontNormalLarge")
  win.header:SetPoint("LEFT", f, "TOPLEFT", S.BOOK_X + 74, S.BOOK_Y - 106); win.header:SetJustifyH("LEFT")
  do local font = win.header:GetFont(); if font then win.header:SetFont(font, 24) end end -- the capture's heading is 24 units high
  brown(win.header, BROWN)
  win.divider = {}
  drawTiled(win.divider, tf, "OVERLAY", "spellbook-divider", S.BOOK_X + 53, S.BOOK_Y - 139, 481, 11)

  -- drag by the title strip; the spot is kept per character and put back after the panel manager has placed the panel
  local drag = CreateFrame("Frame", nil, f)
  drag:SetPoint("TOPLEFT", f, "TOPLEFT", 50, 0); drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -62, 0); drag:SetHeight(21)
  drag:SetFrameLevel(f:GetFrameLevel() + 24)
  if AFUI.WinKit then AFUI.WinKit.makeMovable(f, drag, "spellbook") end

  local close = _G.SpellBookCloseButton
  if close then
    close:ClearAllPoints(); close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 3)
    close:SetWidth(28); close:SetHeight(28); close:SetFrameLevel(f:GetFrameLevel() + 30)
    AFUI.SetButtonAtlas(close, { "redbutton-exit", "redbutton-exit-pressed", "redbutton-highlight", "redbutton-exit-disabled" })
  end
  local tg = CreateFrame("Button", nil, f)
  tg.afOverhang = true -- 3 px above the window edge like the close button on purpose (the audit skips it)
  tg:SetWidth(28); tg:SetHeight(28); tg:SetFrameLevel(f:GetFrameLevel() + 30)
  if close then tg:SetPoint("RIGHT", close, "LEFT", -1, 0) else tg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -29, 3) end
  tg:SetScript("OnClick", function() Spellbook.SetMaximized(not Spellbook.maximized) end)
  tg:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(Spellbook.maximized and "Compact View" or "Expanded View", 1, 1, 1)
    GameTooltip:Show()
  end)
  tg:SetScript("OnLeave", function() GameTooltip:Hide() end)
  win.toggle = tg

  local nextB, prevB, pageT = _G.SpellBookNextPageButton, _G.SpellBookPrevPageButton, _G.SpellBookPageText
  local function arrow(b, kind)
    b:SetFrameLevel(f:GetFrameLevel() + 30)
    for _, r in ipairs(regionsOf(b)) do if r:GetObjectType() == "FontString" then r:Hide() end end -- the "PREV" / "NEXT" captions are gone
    -- the capture's page buttons (native-spellbook-general): dark bevelled squares with a gold (enabled) / grey (end of the book) triangle, not the book's round arrows
    b:SetWidth(24); b:SetHeight(24)
    AFUI.SetButtonAtlas(b, { "profession-button-arrow-" .. kind .. "-c60", "profession-button-arrow-" .. kind .. "-pressed-c60", nil, "profession-button-arrow-" .. kind .. "-c60" })
    b:SetHighlightTexture("")
    local dis = b.GetDisabledTexture and b:GetDisabledTexture()
    if dis and dis.SetDesaturated then dis:SetDesaturated(true); dis:SetAlpha(0.6) end
  end
  if nextB then arrow(nextB, "right") end
  if prevB then arrow(prevB, "left") end
  -- the open book's own arrows (they step 24 spells; Blizzard's would step its own 12 page)
  Spellbook.MakeExtras(f)
  win.prev, win.next = Spellbook.MakeArrow(f, -1), Spellbook.MakeArrow(f, 1) -- secure click buttons: they also page in combat
  arrow(win.prev, "left"); arrow(win.next, "right")
  win.prev:Hide(); win.next:Hide()
  win.lock = tf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") -- subtle hint while something waits for the end of combat
  win.lock:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -250, 46); win.lock:SetText("in combat"); win.lock:Hide()
  if pageT and prevB then
    pageT:ClearAllPoints(); pageT:SetPoint("RIGHT", prevB, "LEFT", -6, 0); pageT:SetJustifyH("RIGHT"); pageT:SetWidth(120)
    pageT:SetFontObject(GameFontNormalLarge or GameFontNormal); brown(pageT, BROWN)
  end

  win.search = makeSearch(f)
  win.search:SetFrameLevel(f:GetFrameLevel() + 30)
  win.filter = makeFilter(f, f:GetFrameLevel() + 30)
  Spellbook.searchText = ""
  layout()
  if AFUI.Mounts then AFUI.Mounts.Attach(f) end
end


-- The switch resizes and re-anchors the window that carries the protected spell buttons, so in combat it waits (the grey hint shows) and the
-- book keeps its current mode; Spellbook.maximized is the mode that is really drawn.
local wantMax
local function applyMode()
  Spellbook.maximized = wantMax and true or false
  if type(AztraForeverUIDB) == "table" then
    AztraForeverUIDB.spellbook = AztraForeverUIDB.spellbook or {}
    AztraForeverUIDB.spellbook.maximized = Spellbook.maximized
  end
  if not Spellbook.win then return end
  if Spellbook.maximized then -- the open book starts on the page that holds what the small book showed
    local cur = _G.SpellBook_GetCurrentPage and _G.SpellBook_GetCurrentPage()
    local key = (select(2, activeRange()))
    Spellbook.root:SetAttribute("key", key); Spellbook.root:SetAttribute("page", cur and math.ceil(cur / 2) or 1); Spellbook.blizzKey = key
  end
  layout(); Spellbook.SyncBook(); Spellbook.UpdateButtons()
  if _G.UpdateUIPanelPositions and _G.SpellBookFrame:IsShown() then pcall(_G.UpdateUIPanelPositions, _G.SpellBookFrame) end -- the new width moves the other panels
end

function Spellbook.SetMaximized(on)
  wantMax = on and true or false
  if not Spellbook.win then return applyMode() end
  if InCombatLockdown() then Spellbook.Pending(true) end
  AFUI.RunOutOfCombat(applyMode)
end

function Spellbook.UpdatePageText()
  local pageT = _G.SpellBookPageText
  if not pageT then return end
  local cur, max
  if extrasOn() and Spellbook.root and Spellbook.pageKey then cur, max = Spellbook.page or 1, Spellbook.root:GetAttribute("np_" .. Spellbook.pageKey) or 1
  elseif _G.SpellBook_GetCurrentPage then cur, max = _G.SpellBook_GetCurrentPage() end
  if cur then pageT:SetText(S.PageText(cur, max)) end
end

local function refresh()
  local hideWaits = (Spellbook.hidePassives and true or false) ~= (Spellbook.drawnHide and true or false)
  if InCombatLockdown() and (hideWaits or (extrasOn() and (Spellbook.dirty or (select(2, activeRange())) ~= Spellbook.blizzKey))) then Spellbook.Pending(true) end
  AFUI.RunOutOfCombat(Spellbook.SyncBook)
  Spellbook.UpdateButtons()
  Spellbook.UpdateTabs()
  styleBookTabs()
  Spellbook.UpdatePageText()
  if AFUI.Mounts then AFUI.Mounts.OnBookRefresh() end
end

function Spellbook.Setup()
  if Spellbook.win or not _G.SpellBookFrame or not AFUI.WorldMapPieces then return end
  local saved = type(AztraForeverUIDB) == "table" and AztraForeverUIDB.spellbook
  Spellbook.maximized = type(saved) == "table" and saved.maximized == true
  Spellbook.hidePassives = type(saved) == "table" and saved.hidePassives == true
  AFUI.RunOutOfCombat(function()
    build()
    -- The area stays "left": the panel manager places left panels, and it never places a "center" one (UIParent.lua UpdateUIPanelPositions
    -- skips the SetPoint) while SpellBookFrame has no XML anchor, so a "center" book was shown with no position and never appeared.
    refresh()
  end)
  for _, fn in ipairs({ "SpellBookFrame_Update", "SpellBookFrame_UpdatePages", "SpellBookFrame_SetTabType", "SpellBookSkillLineTab_OnClick" }) do
    if _G[fn] then hooksecurefunc(fn, refresh) end
  end
  -- 2.5.3 passes the button, 2.4.3's handlers use the implicit `this`
  if _G.SpellButton_UpdateButton then
    hooksecurefunc("SpellButton_UpdateButton", function(b)
      b = type(b) == "table" and b or _G.this
      if type(b) == "table" and b.afSetup then styleButton(b) else Spellbook.UpdateButtons() end
    end)
  end
  _G.SpellBookFrame:HookScript("OnShow", function() refresh() end)
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("SPELL_UPDATE_COOLDOWN"); ev:RegisterEvent("SPELLS_CHANGED")
  ev:SetScript("OnEvent", function(_, event)
    if not Spellbook.extras then return end
    if event == "SPELLS_CHANGED" then
      Spellbook.dirty = true -- the pages are rewritten the next time out of combat
      if not _G.SpellBookFrame:IsShown() then return end
      if InCombatLockdown() and extrasOn() then Spellbook.Pending(true) end
      AFUI.RunOutOfCombat(Spellbook.SyncBook)
    elseif _G.SpellBookFrame:IsShown() then for _, b in ipairs(Spellbook.extras) do if b.slot and b:IsVisible() then updateCooldown(b) end end end
  end)
end

AFUI.RegisterModule("Spellbook", { OnLogin = Spellbook.Setup })
