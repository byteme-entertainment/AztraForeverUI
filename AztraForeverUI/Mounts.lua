-- Mounts tab of the Spellbook: every mount the character has learned, on any server (Crusader Storm has custom ones), as a grid of big icons.
-- Detection (nothing is hardcoded as the only source):
--   1. the companion API where the client has it: GetNumCompanions("MOUNT") / GetCompanionInfo("MOUNT", i) -> creatureID, creatureName, spellID, icon;
--   2. a scan of the whole spellbook (GetNumSpellTabs / GetSpellTabInfo, the client's own spell name / texture / id readers) for spells that are mounts:
--      the known table below (extend it with AFUI.Mounts.AddKnown), the icon (Ability_Mount_*) and the tooltip text ("Summons and dismisses a rideable",
--      "Increases ... speed" together with a mount word). Passive spells (the Riding skills) never count.
--   The two lists are merged and de-duplicated by spell id (by name when the client gives no id).
-- Mount ITEMS in bags are not listed: TBC mount items either teach the spell (then it is in the book) or are used straight from the bag, and no cheap,
-- reliable test tells those from other items.
-- Taint: a mount button is a SecureActionButton (type spell), so it works in combat. Its attributes, position and Show / Hide are only written out of
-- combat (AFUI.RunOutOfCombat); the panel around them, the tab, the search box and the stars are plain frames.
AFUI = AFUI or {}
local M = {}
AFUI.Mounts = M

local PLAIN = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\"
local BROWN = { 0.21, 0.11, 0.05 }
local FADED = { 0.45, 0.3, 0.17 }
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local TAB_ICON = "Interface\\Icons\\Ability_Mount_RidingHorse" -- the side tab is always the horse, whatever the first mount is

---------------------------------------------------------------- known mounts (spell id -> "ground" | "flying" | "both")
-- A seed so the list works offline; anything missing is found by the icon / text heuristics below.
M.KNOWN = {
  -- ground, class and racial
  [5784] = "ground", [23161] = "ground", [13819] = "ground", [23214] = "ground", [34769] = "ground", [34767] = "ground", [66906] = "ground",
  [8395] = "ground", [10873] = "ground", [17463] = "ground", [17481] = "ground", [18990] = "ground", [18991] = "ground", [23509] = "ground",
  [22717] = "ground", [22718] = "ground", [22719] = "ground", [22720] = "ground", [22721] = "ground", [22722] = "ground", [22723] = "ground", [22724] = "ground",
  [16055] = "ground", [16056] = "ground", [26656] = "ground", [30174] = "ground", [458] = "ground", [6648] = "ground", [470] = "ground",
  -- flying
  [32235] = "flying", [32239] = "flying", [32240] = "flying", [32242] = "flying", [32289] = "flying", [32290] = "flying", [32292] = "flying",
  [32243] = "flying", [32244] = "flying", [32245] = "flying", [32246] = "flying", [32295] = "flying", [32296] = "flying", [32297] = "flying",
  [37015] = "flying", [41513] = "flying", [41514] = "flying", [41515] = "flying", [41516] = "flying", [41517] = "flying", [41518] = "flying",
  [44744] = "flying", [43927] = "flying", [40192] = "flying", [46199] = "flying", [39803] = "flying", [33660] = "ground",
  -- shapeshift "mounts" of the druid are not in the list on purpose: they are forms, not summons
}
function M.AddKnown(spellID, kind) if type(spellID) == "number" then M.KNOWN[spellID] = kind or true end end

-- The Riding skills and similar passives: never mounts even if their text mentions speed.
local SKILL_IDS = { [33388] = true, [33391] = true, [34090] = true, [34091] = true, [33389] = true, [33392] = true, [54197] = true }
local FLY_NAME = { "gryphon", "wind rider", "windrider", "drake", "nether ray", "hippogryph", "netherwing", "phoenix", "proto", "flying", "flight", "dragonhawk", "wyvern" }

---------------------------------------------------------------- pure helpers
local function lower(s) return type(s) == "string" and string.lower(s) or "" end
local function has(s, part) return string.find(s, part, 1, true) ~= nil end

-- Is this tooltip text a mount's? (strong: it says so; medium: it raises speed and talks about riding / mounts / flying)
function M.TextIsMount(text)
  local t = lower(text)
  if t == "" then return false end
  if has(t, "summons and dismisses a rideable") or has(t, "rideable") then return true end
  if string.find(t, "increases [%a ]*speed") and (has(t, "mount") or has(t, "ride") or has(t, "flying") or has(t, "flight") or has(t, "steed")) then return true end
  return false
end

function M.IconIsMount(icon) return has(lower(icon), "ability_mount_") end

function M.IsRidingSkill(name, spellID)
  if spellID and SKILL_IDS[spellID] then return true end
  return string.find(lower(name), "riding$") ~= nil
end

-- "ground" / "flying" / "both" (nil when nothing says); the known table wins, then the text, then the name.
function M.KindOf(spellID, name, text)
  local k = spellID and M.KNOWN[spellID]
  if k == "ground" or k == "flying" or k == "both" then return k end
  local t, n = lower(text), lower(name)
  local fly = has(t, "flying") or has(t, "flight") or has(t, "fly ")
  local ground = has(t, "ground")
  if not fly then for _, w in ipairs(FLY_NAME) do if has(n, w) then fly = true; break end end end
  if fly and ground then return "both" end
  if fly then return "flying" end
  if ground then return "ground" end
  if t ~= "" then return "ground" end -- a rideable that never mentions flying
  return nil
end

-- Decide one spell. text is only asked for when the cheap tests have not decided (it can be a tooltip scan).
function M.Classify(spellID, name, icon, passive, textFn)
  if passive or M.IsRidingSkill(name, spellID) then return false end
  local text
  local function getText() if text == nil then text = textFn and textFn() or "" end; return text end
  if spellID and M.KNOWN[spellID] then return true, M.KindOf(spellID, name, "") end
  if M.IconIsMount(icon) then return true, M.KindOf(spellID, name, getText()) end
  if M.TextIsMount(getText()) then return true, M.KindOf(spellID, name, getText()) end
  return false
end

local function keyOf(e) return tostring(e.spellID or e.name) end
M.KeyOf = keyOf

-- Merge lists in priority order; the first entry of a spell id (or name) wins, later ones only add what it lacks.
function M.Merge(...)
  local out, seen = {}, {}
  for li = 1, select("#", ...) do
    for _, e in ipairs((select(li, ...)) or {}) do
      local k1, k2 = e.spellID and ("i" .. e.spellID), e.name and ("n" .. lower(e.name))
      local into = (k1 and seen[k1]) or (k2 and seen[k2])
      if into then
        for k, v in pairs(e) do if into[k] == nil then into[k] = v end end
      else
        local c = {}; for k, v in pairs(e) do c[k] = v end
        out[#out + 1] = c
        if k1 then seen[k1] = c end
        if k2 then seen[k2] = c end
      end
    end
  end
  return out
end

-- Favourites first, then by name.
function M.Sort(list, favs)
  favs = favs or {}
  table.sort(list, function(a, b)
    local fa, fb = favs[keyOf(a)] and 1 or 0, favs[keyOf(b)] and 1 or 0
    if fa ~= fb then return fa > fb end
    return lower(a.name) < lower(b.name)
  end)
  return list
end

-- Part of the name, any case, no patterns; no text matches everything.
function M.Matches(name, text)
  if not text or text == "" then return true end
  return has(lower(name), lower(text))
end

function M.Filter(list, text)
  local out = {}
  for _, e in ipairs(list) do if M.Matches(e.name, text) then out[#out + 1] = e end end
  return out
end

-- Random favourite (every mount when none is a favourite). Where flying works prefer flying mounts, elsewhere ground ones; the other kind
-- only when nothing else is left. rnd(n) -> 1..n (math.random by default).
function M.PickRandom(list, favs, flyable, rnd)
  favs = favs or {}
  local pool = {}
  for _, e in ipairs(list) do if favs[keyOf(e)] then pool[#pool + 1] = e end end
  if #pool == 0 then pool = list end
  local pref = {}
  for _, e in ipairs(pool) do
    local k = e.kind
    local fits = k == nil or k == "both" or (flyable and k == "flying") or (not flyable and k == "ground")
    if fits then pref[#pref + 1] = e end
  end
  if #pref > 0 then pool = pref end
  if #pool == 0 then return nil end
  return pool[(rnd or math.random)(#pool)]
end

-- Grid: columns by rows of cells for the closed / open book, and the page maths.
M.CELL_W, M.CELL_H, M.ROWS = 148, 98, 5
function M.Columns(maximized) return maximized and 6 or 3 end
function M.PerPage(maximized) return M.Columns(maximized) * M.ROWS end
function M.NumPages(total, maximized) return math.max(1, math.ceil((total or 0) / M.PerPage(maximized))) end
function M.ClampPage(page, total, maximized) return math.min(math.max(page or 1, 1), M.NumPages(total, maximized)) end
-- TOPLEFT of cell i (1 based on the page) in the grid, x centred in a panel of width w.
function M.CellPos(i, maximized, w)
  local cols = M.Columns(maximized)
  local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
  return (w - cols * M.CELL_W) / 2 + c * M.CELL_W, r * M.CELL_H
end

M.BADGE = { ground = "Ground", flying = "Flying", both = "Flying / Ground" }
function M.BadgeText(kind) return M.BADGE[kind] or "" end

---------------------------------------------------------------- reading the client
local function api(n) return _G[n] end

function M.HasBookAPI()
  return type(api("GetNumSpellTabs")) == "function" and type(api("GetSpellTabInfo")) == "function"
    and (type(api("GetSpellBookItemName")) == "function" or type(api("GetSpellName")) == "function")
end
function M.HasCompanionAPI() return type(api("GetNumCompanions")) == "function" and type(api("GetCompanionInfo")) == "function" end
function M.HasAPI() return M.HasBookAPI() or M.HasCompanionAPI() end

-- the spell id of a book slot (2.5.3 GetSpellBookItemInfo, older clients: the id inside GetSpellLink)
local function spellIDOf(slot)
  if type(api("GetSpellBookItemInfo")) == "function" then
    local ok, kind, id = pcall(api("GetSpellBookItemInfo"), slot, "spell")
    if ok and type(id) == "number" then return id end
    if ok and type(kind) == "number" then return kind end
  end
  if type(api("GetSpellLink")) == "function" then
    local ok, link = pcall(api("GetSpellLink"), slot, "spell")
    local id = ok and type(link) == "string" and string.match(link, "spell:(%d+)")
    if id then return tonumber(id) end
  end
end

local tip
local function tooltipText(slot)
  if not (api("CreateFrame") and api("UIParent")) then return "" end
  tip = tip or CreateFrame("GameTooltip", "AFUI_MountScanTip", nil, "GameTooltipTemplate")
  tip:SetOwner(UIParent, "ANCHOR_NONE"); tip:ClearLines()
  if not pcall(AFUI.TooltipSpellBook, tip, slot, "spell") then return "" end
  local parts = {}
  for i = 1, tip:NumLines() or 0 do
    local fs = _G["AFUI_MountScanTipTextLeft" .. i]
    local t = fs and fs:GetText()
    if t then parts[#parts + 1] = t end
  end
  return table.concat(parts, "\n")
end
M.SpellText = tooltipText -- specs replace it

local decided = {} -- spell key -> { isMount, kind }: a spell's nature never changes, so the tooltip is read once

function M.ReadCompanions()
  local out = {}
  if not M.HasCompanionAPI() then return out end
  for i = 1, (GetNumCompanions("MOUNT") or 0) do
    local creatureID, creatureName, spellID, icon = GetCompanionInfo("MOUNT", i)
    local name = creatureName
    if spellID and type(api("GetSpellInfo")) == "function" then name = GetSpellInfo(spellID) or name end
    if name then
      out[#out + 1] = { spellID = spellID, name = name, icon = icon, kind = M.KindOf(spellID, name, ""), companion = i }
    end
  end
  return out
end

function M.ReadBook()
  local out = {}
  if not M.HasBookAPI() then return out end
  for t = 1, GetNumSpellTabs() do
    local _, _, offset, num = GetSpellTabInfo(t)
    for slot = (offset or 0) + 1, (offset or 0) + (num or 0) do
      local name = AFUI.SpellBookName(slot, "spell")
      if name then
        local id = spellIDOf(slot)
        local ck = id and ("i" .. id) or ("n" .. name)
        local d = decided[ck]
        local icon = type(api("GetSpellTexture")) == "function" and GetSpellTexture(slot, "spell") or nil
        if not d then
          local passive = type(api("IsPassiveSpell")) == "function" and IsPassiveSpell(slot, "spell") or false
          local isMount, kind = M.Classify(id, name, icon, passive, function() return M.SpellText(slot, id) end)
          d = { isMount = isMount, kind = kind }
          decided[ck] = d
        end
        if d.isMount then out[#out + 1] = { spellID = id, name = name, icon = icon, kind = d.kind, slot = slot } end
      end
    end
  end
  return out
end

function M.Collect() return M.Merge(M.ReadCompanions(), M.ReadBook()) end

---------------------------------------------------------------- favourites (per account)
local function favTable()
  if type(AztraForeverUIDB) ~= "table" then return {} end
  AztraForeverUIDB.mounts = AztraForeverUIDB.mounts or {}
  AztraForeverUIDB.mounts.fav = AztraForeverUIDB.mounts.fav or {}
  return AztraForeverUIDB.mounts.fav
end
function M.IsFav(e) return favTable()[keyOf(e)] == true end
function M.ToggleFav(e)
  local f = favTable()
  local k = keyOf(e)
  if f[k] then f[k] = nil else f[k] = true end
  return f[k] == true
end

---------------------------------------------------------------- UI
local function setShown(o, on) if on then o:Show() else o:Hide() end end
local MAXCELLS = 30
local cells = {}
M.page = 1
M.searchText = ""

local function bookIsSpells() return not (_G.SpellBookFrame and _G.SpellBookFrame.bookType == "pet") end
local function isMax() return AFUI.Spellbook and AFUI.Spellbook.maximized and true or false end

local function visibleList()
  local all = M.list or {}
  return M.Sort(M.Filter(all, M.searchText), favTable())
end

local function tipFor(btn)
  local e = btn.entry
  if not e then return end
  GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
  local shown = false
  if e.slot then shown = pcall(AFUI.TooltipSpellBook, GameTooltip, e.slot, "spell") end
  if not shown and e.spellID and GameTooltip.SetHyperlink then shown = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. e.spellID) end
  if not shown then GameTooltip:SetText(e.name, 1, 1, 1) end
  GameTooltip:AddLine(M.IsFav(e) and "Favorite" or "Click the star to make this a favorite", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function link(e)
  local text
  if type(api("GetSpellLink")) == "function" then
    local ok, l = pcall(GetSpellLink, e.spellID or e.name)
    if ok and type(l) == "string" then text = l end
    if not text and e.slot then ok, l = pcall(GetSpellLink, e.slot, "spell"); if ok and type(l) == "string" then text = l end end
  end
  return text or e.name
end

local function pickup(e)
  if e.companion and type(api("PickupCompanion")) == "function" then return PickupCompanion("MOUNT", e.companion) end
  if e.slot then return AFUI.PickupSpellBook(e.slot, "spell") end
  if e.spellID and type(api("PickupSpell")) == "function" then return PickupSpell(e.spellID) end
end

local function makeCell(panel, i)
  local base = panel:GetFrameLevel()
  local b = CreateFrame("Button", "AFUI_MountButton" .. i, panel, "SecureActionButtonTemplate")
  b:SetWidth(M.CELL_W - 8); b:SetHeight(M.CELL_H - 6); b:SetFrameLevel(base + 1)
  b:RegisterForClicks("LeftButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetAttribute("type1", "spell")
  b:SetAttribute("shift-type1", "stop") -- shift-click links the spell instead of casting it
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); AFUI.SetColor(hl, 1, 0.82, 0, 0.16); hl:SetAllPoints(b)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetWidth(40); b.icon:SetHeight(40); b.icon:SetPoint("TOP", b, "TOP", 0, -8)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.frame = b:CreateTexture(nil, "OVERLAY")
  AFUI.SetAtlas(b.frame, "spellbook-item-iconframe-c60")
  b.frame:SetPoint("TOPLEFT", b.icon, "TOPLEFT", -13, 3); b.frame:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 3, -9) -- the book's own frame offsets (-11, 1 / 1, -7) around a 36 icon in a 40 button
  b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.name:SetPoint("TOP", b.icon, "BOTTOM", 0, -8); b.name:SetWidth(M.CELL_W - 18); b.name:SetHeight(28); b.name:SetJustifyH("CENTER")
  b.badge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.badge:SetPoint("TOP", b.name, "BOTTOM", 0, 0); b.badge:SetWidth(M.CELL_W - 18)
  b.name:SetTextColor(BROWN[1], BROWN[2], BROWN[3]); b.badge:SetTextColor(FADED[1], FADED[2], FADED[3])
  b:SetScript("OnEnter", tipFor)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnDragStart", function(self) if self.entry then pickup(self.entry) end end)
  b:HookScript("PreClick", function(self)
    if self.entry and IsShiftKeyDown and IsShiftKeyDown() and _G.ChatEdit_InsertLink then ChatEdit_InsertLink(link(self.entry)) end
  end)
  local star = CreateFrame("Button", nil, panel)
  star:SetWidth(18); star:SetHeight(18); star:SetFrameLevel(base + 4)
  star:SetPoint("TOPRIGHT", b, "TOPRIGHT", -4, -4)
  star.tex = star:CreateTexture(nil, "OVERLAY"); star.tex:SetAllPoints(star)
  local hlS = star:CreateTexture(nil, "HIGHLIGHT"); AFUI.SetColor(hlS, 1, 0.82, 0, 0.25); hlS:SetAllPoints(star)
  star:SetScript("OnClick", function()
    if not b.entry then return end
    M.ToggleFav(b.entry)
    M.Paint()
    AFUI.RunOutOfCombat(M.Fill) -- the order changes: the secure buttons are rewritten out of combat
  end)
  star:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(b.entry and M.IsFav(b.entry) and "Remove from favorites" or "Add to favorites", 1, 1, 1); GameTooltip:Show()
  end)
  star:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b.star = star
  return b
end

-- the parts that are plain art and text: safe in combat
function M.Paint()
  for _, b in ipairs(cells) do
    local e = b.entry
    if e then
      b.icon:SetTexture(e.icon or DEFAULT_ICON)
      b.name:SetText(e.name)
      b.badge:SetText(M.BadgeText(e.kind))
      AFUI.SetAtlas(b.star.tex, M.IsFav(e) and "tradeskills-star" or "tradeskills-star-off")
      b.star.tex:SetAlpha(M.IsFav(e) and 1 or 0.55)
    end
  end
end

-- (re)writes the grid from the list: out of combat (attributes, anchors and Show / Hide of secure buttons)
function M.Fill()
  local p = M.panel
  if not p then return end
  local max = isMax()
  local list = visibleList()
  M.shownList = list
  M.page = M.ClampPage(M.page, #list, max)
  local per = M.PerPage(max)
  local first = (M.page - 1) * per
  local w = p:GetWidth() or 0
  if w <= 0 then w = max and 1148 or 574 end
  for i, b in ipairs(cells) do
    local e = i <= per and list[first + i] or nil
    b.entry = e
    b:ClearAllPoints()
    if e then
      local x, y = M.CellPos(i, max, w)
      b:SetPoint("TOPLEFT", p, "TOPLEFT", x + 4, -(M.GRID_TOP + y))
      b:SetAttribute("type1", "spell")
      b:SetAttribute("spell", e.name)
      b:Show(); b.star:Show()
    else
      b:SetAttribute("spell", nil)
      b:Hide(); b.star:Hide()
    end
  end
  M.Paint()
  local total = #(M.list or {})
  p.count:SetText(total == 1 and "1 mount" or (total .. " mounts"))
  if total == 0 then p.empty:SetText("You have not learned any mounts yet.")
  elseif #list == 0 then p.empty:SetText("No mounts match your search.")
  else p.empty:SetText("") end
  p.pageText:SetText(string.format("Page %d/%d", M.page, M.NumPages(#list, max)))
  local np = M.NumPages(#list, max)
  p.prev:SetAlpha(M.page > 1 and 1 or 0.4); p.next:SetAlpha(M.page < np and 1 or 0.4)
  M.SetRandom()
end

-- Random Mount: the spell is chosen out of combat (here and again in PreClick); in combat the last pick is used.
function M.SetRandom()
  local p = M.panel
  if not p or InCombatLockdown() then return end
  local flyable = type(api("IsFlyableArea")) == "function" and IsFlyableArea() or false
  local e = M.PickRandom(M.list or {}, favTable(), flyable)
  p.random:SetAttribute("type1", "spell")
  p.random:SetAttribute("spell", e and e.name or nil)
  p.random.entry = e
  if e then p.random:Enable() else p.random:Disable() end
end

function M.Refresh()
  M.list = M.Collect()
  AFUI.RunOutOfCombat(M.Fill)
end

function M.MarkDirty()
  M.dirty = true
  if M.panel and M.panel:IsShown() then M.dirty = false; M.Refresh() end
end

function M.IsOpen() return M.panel ~= nil and M.panel:IsShown() end

function M.Close()
  if not M.panel then return end
  M.panel:Hide()
  if M.tab then M.tab.glow:Hide(); M.tab.grad:Hide(); M.tab:SetChecked(false) end
  local w = AFUI.Spellbook and AFUI.Spellbook.win
  if w then if w.search then w.search:Show() end; if w.filter then w.filter:Show() end end
  if AFUI.Spellbook and AFUI.Spellbook.UpdateTabs then AFUI.Spellbook.UpdateTabs() end
end

function M.Open()
  if not M.panel or not M.HasAPI() then return end
  M.dirty = false
  M.Refresh()
  M.panel:Show()
  M.tab.glow:Show(); M.tab.grad:Show(); M.tab:SetChecked(true)
  local w = AFUI.Spellbook and AFUI.Spellbook.win
  if w then if w.search then w.search:Hide() end; if w.filter then w.filter:Hide() end; if w.header then w.header:SetText("") end end
end

-- Where the tab sits: right after the last skill line tab (the same square plates).
local function tabPos()
  local n = 0
  for i = 1, 8 do local t = _G["SpellBookSkillLineTab" .. i]; if t and t:IsShown() then n = i end end
  local S = AFUI.SpellbookLayout
  return S.TabPos(n + 1)
end

function M.Layout()
  local f, p = _G.SpellBookFrame, M.panel
  if not (f and p) then return end
  if InCombatLockdown() then return AFUI.RunOutOfCombat(M.Layout) end -- the secure buttons are anchored here
  local S = AFUI.SpellbookLayout
  local max = isMax()
  local bw = S.BookWidth(max)
  p:ClearAllPoints(); p:SetPoint("TOPLEFT", f, "TOPLEFT", S.BOOK_X, S.BOOK_Y - M.TOP)
  p:SetWidth(bw); p:SetHeight(S.BOOK_H - M.TOP)
  -- the parchment: the book's page art with its top (the strip behind the tabs) cut off
  p.pageL, p.pageR = p.pageL or {}, p.pageR or {}
  local crop = M.TOP / S.BOOK_H
  if max then
    S.DrawTiled(p.pageL, p, "BACKGROUND", "spellbook-page-left-c60", 0, 0, bw / 2, S.BOOK_H - M.TOP, crop)
    S.DrawTiled(p.pageR, p, "BACKGROUND", "spellbook-page-right-c60", bw / 2, 0, bw / 2, S.BOOK_H - M.TOP, crop)
  else
    S.DrawTiled(p.pageL, p, "BACKGROUND", "spellbook-page-condensed-c60", 0, 0, bw, S.BOOK_H - M.TOP, crop)
  end
  for _, t in ipairs(p.pageR) do setShown(t, max) end
  p.title:ClearAllPoints(); p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 40, -16)
  p.count:ClearAllPoints(); p.count:SetPoint("TOPLEFT", p, "TOPLEFT", 40, -46); p.count:SetWidth(200); p.count:SetJustifyH("LEFT")
  p.search:ClearAllPoints(); p.search:SetPoint("TOPRIGHT", p, "TOPRIGHT", -(max and 70 or 56), -22)
  p.dismount:ClearAllPoints(); p.dismount:SetPoint("TOPRIGHT", p.search, "BOTTOMRIGHT", 4, -10)
  p.random:ClearAllPoints(); p.random:SetPoint("RIGHT", p.dismount, "LEFT", -6, 0)
  p.line:ClearAllPoints(); p.line:SetPoint("TOPLEFT", p, "TOPLEFT", 40, -(M.GRID_TOP - 6)); p.line:SetPoint("TOPRIGHT", p, "TOPRIGHT", -40, -(M.GRID_TOP - 6))
  p.next:ClearAllPoints(); p.next:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -(max and 60 or 50), 16)
  p.prev:ClearAllPoints(); p.prev:SetPoint("RIGHT", p.next, "LEFT", -16, 0)
  p.pageText:ClearAllPoints(); p.pageText:SetPoint("RIGHT", p.prev, "LEFT", -8, 0)
  p.empty:ClearAllPoints(); p.empty:SetPoint("CENTER", p, "CENTER", 0, 20)
  if M.tab then
    M.tab:ClearAllPoints(); M.tab:SetPoint("TOPLEFT", f, "TOPLEFT", tabPos())
    setShown(M.tab, M.HasAPI() and bookIsSpells())
  end
  AFUI.RunOutOfCombat(M.Fill)
end

-- The book redrew (tab, page, book type, spell change): keep the tab right and drop the panel when the pet book is open.
function M.OnBookRefresh()
  if not M.tab then return end
  setShown(M.tab, M.HasAPI() and bookIsSpells())
  M.tab:ClearAllPoints(); M.tab:SetPoint("TOPLEFT", _G.SpellBookFrame, "TOPLEFT", tabPos())
  if M.IsOpen() and not bookIsSpells() then M.Close() end
end

M.TOP = 50 -- the panel starts below the tab strip
M.GRID_TOP = 96

local function makeSearch(panel)
  local e = CreateFrame("EditBox", "AFUI_MountsSearch", panel, "InputBoxTemplate")
  e:SetAutoFocus(false); e:SetHeight(20); e:SetWidth(200); e:SetMaxLetters(40)
  if AFUI.WinKit and AFUI.WinKit.edit then AFUI.WinKit.edit(e) end
  e:SetTextInsets(8, 8, 0, 0)
  e.hint = e:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  e.hint:SetPoint("LEFT", e, "LEFT", 8, 0); e.hint:SetText(_G.ENTER_SEARCH_TEXT or "Enter search text")
  e:SetScript("OnTextChanged", function(self)
    M.searchText = self:GetText() or ""
    setShown(self.hint, M.searchText == "" and not self:HasFocus())
    M.page = 1
    AFUI.RunOutOfCombat(M.Fill)
  end)
  e:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
  e:SetScript("OnEditFocusLost", function(self) setShown(self.hint, self:GetText() == "") end)
  return e
end

local function redButton(parent, name, text, w)
  local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
  b:SetText(text); b:SetWidth(w); b:SetHeight(28)
  b:RegisterForClicks("LeftButtonUp")
  if AFUI.WinKit and AFUI.WinKit.button then AFUI.WinKit.button(b, w, 28) end
  return b
end

local function makeTab(f)
  local S = AFUI.SpellbookLayout
  local t = CreateFrame("CheckButton", "AFUI_SpellbookMountsTab", f)
  t:SetWidth(36); t:SetHeight(32)
  t.icon = t:CreateTexture(nil, "ARTWORK")
  t.icon:SetPoint("TOPLEFT", t, "TOPLEFT", 1, -1); t.icon:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -1, 1)
  t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93); t.icon:SetTexture(TAB_ICON)
  local function art(name, a)
    local x = t:CreateTexture(nil, "OVERLAY"); AFUI.SetAtlas(x, name); x:SetWidth(43); x:SetHeight(38); x:SetPoint("CENTER", t, "CENTER", 0, 0)
    if a then x:SetAlpha(a) end
    return x
  end
  t.frame = art("spellbook-tab-frame-c60")
  t.glow = art("spellbook-tab-frame-glow-c60"); t.grad = art("spellbook-tab-frame-glow-gradient-c60", 0.6)
  t.glow:Hide(); t.grad:Hide()
  local hl = t:CreateTexture(nil, "HIGHLIGHT"); AFUI.SetColor(hl, 1, 0.82, 0, 0.18); hl:SetAllPoints(t)
  t:SetScript("OnClick", function(self)
    if M.IsOpen() then M.Close() else M.Open() end
  end)
  t:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Mounts", 1, 1, 1); GameTooltip:Show() end)
  t:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return t
end

-- Called by Spellbook.lua once its window is built (out of combat).
function M.Attach(f)
  if M.panel or not f then return end
  local S = AFUI.SpellbookLayout
  local p = CreateFrame("Frame", "AFUI_MountsPanel", f)
  p:SetFrameLevel(f:GetFrameLevel() + 35) -- over the spell buttons, the page arrows and the page header; under nothing the player needs
  p:EnableMouse(true)
  p:Hide()
  M.panel = p
  p.title = p:CreateFontString(nil, "OVERLAY", _G.GameFontNormalHuge and "GameFontNormalHuge" or "GameFontNormalLarge")
  do local font = p.title:GetFont(); if font then p.title:SetFont(font, 24) end end
  p.title:SetText("Mounts"); p.title:SetTextColor(BROWN[1], BROWN[2], BROWN[3])
  p.count = p:CreateFontString(nil, "OVERLAY", "GameFontNormal"); p.count:SetTextColor(BROWN[1], BROWN[2], BROWN[3])
  p.line = p:CreateTexture(nil, "ARTWORK"); p.line:SetHeight(2); AFUI.SetColor(p.line, BROWN[1], BROWN[2], BROWN[3], 0.55)
  p.empty = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); p.empty:SetTextColor(FADED[1], FADED[2], FADED[3])
  p.search = makeSearch(p); p.search:SetFrameLevel(p:GetFrameLevel() + 3)
  p.random = redButton(p, "AFUI_MountsRandom", "Random Mount", 118); p.random:SetFrameLevel(p:GetFrameLevel() + 3)
  p.random:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Random Mount", 1, 1, 1)
    GameTooltip:AddLine("Summons one of your favorites (any mount if none is a favorite).", 0.8, 0.8, 0.8, true); GameTooltip:Show()
  end)
  p.random:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p.random:HookScript("PreClick", function() M.SetRandom() end) -- a new pick for every click (not possible in combat: the last pick is used)
  p.dismount = redButton(p, "AFUI_MountsDismount", "Dismount", 96); p.dismount:SetFrameLevel(p:GetFrameLevel() + 3)
  p.dismount:SetAttribute("type1", "macro"); p.dismount:SetAttribute("macrotext1", "/dismount")
  local function arrow(delta, kind)
    local b = CreateFrame("Button", nil, p)
    b:SetWidth(24); b:SetHeight(24); b:SetFrameLevel(p:GetFrameLevel() + 3)
    AFUI.SetButtonAtlas(b, { "profession-button-arrow-" .. kind .. "-c60", "profession-button-arrow-" .. kind .. "-pressed-c60", nil, "profession-button-arrow-" .. kind .. "-c60" })
    b:SetScript("OnClick", function()
      local np = M.NumPages(#(M.shownList or {}), isMax())
      local to = math.min(math.max(M.page + delta, 1), np)
      if to ~= M.page then M.page = to; AFUI.RunOutOfCombat(M.Fill) end
    end)
    return b
  end
  p.prev, p.next = arrow(-1, "left"), arrow(1, "right")
  p.pageText = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); p.pageText:SetTextColor(BROWN[1], BROWN[2], BROWN[3]); p.pageText:SetWidth(120); p.pageText:SetJustifyH("RIGHT")
  for i = 1, MAXCELLS do cells[i] = makeCell(p, i) end
  M.cells = cells
  M.tab = makeTab(f)
  -- another book tab, the pet book or closing the window ends the mounts page
  for i = 1, 8 do
    local t = _G["SpellBookSkillLineTab" .. i]
    if t and t.HookScript then t:HookScript("OnClick", function() M.Close() end) end
    local o = _G["AFUISpellTabOverlay" .. i] -- the secure overlays that switch tabs in combat
    if o and o.HookScript then o:HookScript("PostClick", function() M.Close() end) end
  end
  f:HookScript("OnHide", function() M.Close() end)
  M.Layout()
  M.Refresh()
end

for _, e in ipairs({ "SPELLS_CHANGED", "COMPANION_LEARNED", "COMPANION_UPDATE", "PLAYER_ENTERING_WORLD" }) do
  AFUI.On(e, function() M.MarkDirty() end)
end
