-- Buffs and Debuffs (Forever's Edit Mode system, measured from the recording docs/forever-ref/video3-notes/minimap-tracker.md):
-- icons 28 u, pitch 35 u, a thin light border, the time left under each icon ("37 s", "51 m", "2 h", gold from a minute on), buffs grow
-- left from the right edge (first aura rightmost) in rows of 11 that wrap downwards 45 u apart, debuffs follow in rows of 8 with the
-- border in the dispel colour and a dot of it in the top right corner, a gold triangle on the right collapses the row. Our own frames
-- over UnitAura (Blizzard's BuffFrame is killed); the box is BarExtras' AFUI_BuffAnchor, the Edit Mode system "Buffs and Debuffs".
AFUI = AFUI or {}

local ICON, PITCH, ROW, GAP = 28, 35, 45, 4 -- icon, column pitch, row pitch, gap between the buff and debuff blocks
local WRAP = { HELPFUL = 11, HARMFUL = 8 }
local EDGE = { 0.49, 0.55, 0.63 } -- the buff icon's frame
local ENCHANT = { 0.58, 0.2, 0.78 } -- UI-TempEnchant-Border purple
local WARN, FLASH, MIN_ALPHA = 31, 0.75, 0.3 -- BuffFrame.lua: under 31 s the button pulses between 30 % and full over 2 x 0.75 s
local GOLD, WHITE = { 1, 0.82, 0 }, { 1, 1, 1 }

-- "37 s", "51 m", "2 h", "3 d" (SecondsToTimeAbbrev: minutes, hours and days round up; the recording shows "60 s", so a minute counts as seconds) and its colour: white up to a minute, gold above.
function AFUI.AuraTime(seconds)
  if seconds >= 86400 then return string.format("%d d", math.ceil(seconds / 86400)), GOLD end
  if seconds >= 3600 then return string.format("%d h", math.ceil(seconds / 3600)), GOLD end
  if seconds > 60 then return string.format("%d m", math.ceil(seconds / 60)), GOLD end
  return string.format("%d s", math.floor(seconds)), WHITE
end

-- Offset of aura n from the block's top right corner: filled from the right, then the next row down.
function AFUI.AuraPoint(n, wrap)
  return -((n - 1) % wrap) * PITCH, -math.floor((n - 1) / wrap) * ROW
end

-- BuffFrame_OnUpdate's pulse: a triangle wave between MIN_ALPHA and 1, 0.75 s each way, only while under WARN seconds.
function AFUI.AuraAlpha(timeLeft, now)
  if not timeLeft or timeLeft >= WARN then return 1 end
  local p = (now % (2 * FLASH)) / FLASH
  if p > 1 then p = 2 - p end
  return MIN_ALPHA + (1 - MIN_ALPHA) * p
end

local box = AFUI.BuffAnchor
if not box then return end
local DB = function() return type(AztraForeverUICharDB) == "table" and AztraForeverUICharDB or {} end

-- The box is the room of the whole system (11 columns x 3 rows of buffs, 2 rows of debuffs): Edit Mode places it by its centre, so it must not change size.
box:SetWidth(WRAP.HELPFUL * PITCH + 14); box:SetHeight(3 * ROW + GAP + 2 * ROW)
local holder = CreateFrame("Frame", "AFUI_Buffs", box)
holder:SetAllPoints(box)
local pool = { HELPFUL = {}, HARMFUL = {} } -- buttons of each block, reused
AFUI.BuffPool = pool -- read by AnchorCompat.lua: the stand-ins of BuffButtonN / DebuffButtonN / TempEnchantN follow these
local rowsOf = { HELPFUL = 0, HARMFUL = 0 }
local dirty = true

local function tooltip(b)
  if b.sample then return end
  GameTooltip:SetOwner(b, "ANCHOR_BOTTOMLEFT")
  if b.enchant then GameTooltip:SetInventoryItem("player", b.enchant == 1 and 16 or 17)
  elseif b.filter == "HARMFUL" then GameTooltip:SetUnitDebuff("player", b.index)
  else GameTooltip:SetUnitBuff("player", b.index) end
end

-- Right click removes the buff (Blizzard's BuffButton_OnClick); weapon enchants through CancelItemTempEnchantment.
local function cancel(b)
  if b.sample then return end
  if b.enchant then return CancelItemTempEnchantment(b.enchant) end
  if b.filter == "HARMFUL" then return end
  if CancelUnitBuff then return CancelUnitBuff("player", b.index, "HELPFUL") end
  if CancelPlayerBuff and GetPlayerBuff then return CancelPlayerBuff((GetPlayerBuff(b.index, "HELPFUL"))) end
end

local function edge(b, point, w, h)
  local t = b:CreateTexture(nil, "OVERLAY")
  t:SetPoint(point, b, point, 0, 0)
  t:SetWidth(w); t:SetHeight(h)
  return t
end

local function newButton(filter)
  local b = CreateFrame("Button", nil, holder)
  b.filter = filter
  b:SetWidth(ICON); b:SetHeight(ICON)
  b:RegisterForClicks("RightButtonUp")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.edges = { edge(b, "TOPLEFT", ICON, 1), edge(b, "BOTTOMLEFT", ICON, 1), edge(b, "TOPLEFT", 1, ICON), edge(b, "TOPRIGHT", 1, ICON) }
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  b.time = b:CreateFontString(nil, "OVERLAY")
  b.time:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
  b.time:SetPoint("TOP", b, "BOTTOM", 0, -2)
  if filter == "HARMFUL" then
    b.dot = b:CreateTexture(nil, "OVERLAY") -- the dispel colour in the top right corner
    b.dot:SetWidth(7); b.dot:SetHeight(7); b.dot:SetPoint("CENTER", b, "TOPRIGHT", -2, -2)
  end
  b:SetScript("OnEnter", function(self) self.hover = true; tooltip(self) end)
  b:SetScript("OnLeave", function(self) self.hover = false; GameTooltip:Hide() end)
  b:SetScript("OnClick", cancel)
  return b
end

local function paint(b, r, g, bl)
  for _, t in ipairs(b.edges) do AFUI.SetColor(t, r, g, bl, 1) end
end

local UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
local function put(list, filter, i, a, y)
  local b = list[i]
  if not b then b = newButton(filter); list[i] = b end
  b.index, b.enchant, b.expires, b.sample = a.index, a.enchant, a.expires, a.sample
  AFUI.SetIcon(b.icon, a.icon, UNKNOWN) -- a path the client cannot resolve draws solid green: show the question mark
  b.count:SetText(a.count and a.count > 1 and a.count or "")
  local c = a.enchant and ENCHANT or filter == "HELPFUL" and EDGE or nil
  if not c then c = DebuffTypeColor and (DebuffTypeColor[a.dtype or "none"] or DebuffTypeColor.none) or { r = 0.8, g = 0, b = 0 }; c = { c.r, c.g, c.b } end
  paint(b, c[1], c[2], c[3])
  if b.dot then if a.dtype then AFUI.SetColor(b.dot, c[1], c[2], c[3], 1); b.dot:Show() else b.dot:Hide() end end
  local x, dy = AFUI.AuraPoint(i, WRAP[filter])
  b:ClearAllPoints()
  b:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -14 + x, y + dy)
  b:Show()
end

-- Edit Mode shows full sample rows (32 buffs, 16 debuffs, the times 60 s, 2 m, 3 m ... as the recording), like Blizzard's SwitchAuraDataProvider.
local SAMPLE = { "Spell_Holy_WordFortitude", "Spell_Nature_Regeneration", "Spell_Nature_Lightning", "Spell_Holy_HolyBolt", "Spell_Holy_SealOfWrath",
  "Spell_Fire_Fire", "Spell_Frost_FrostNova", "Spell_Shadow_ShadowWordPain" }
AFUI.AuraSampleIcons = SAMPLE
local DISPEL = { false, "Magic", "Curse", "Poison", "Disease" }
local function sample(filter)
  local list = {}
  for i = 1, filter == "HELPFUL" and 32 or 16 do
    list[i] = { sample = true, index = i, icon = AFUI.IconPath(SAMPLE[(i - 1) % #SAMPLE + 1]), expires = GetTime() + (i == 1 and 60 or i * 60 - 1),
      count = i == 3 and 3 or nil, dtype = filter == "HARMFUL" and DISPEL[(i - 1) % #DISPEL + 1] or nil }
  end
  return list
end

-- Weapon enchants first (rightmost, as TBC's TemporaryEnchantFrame), then the buffs; the same two-slot API on both clients.
local function collect(filter)
  local list = {}
  if filter == "HELPFUL" and GetWeaponEnchantInfo then
    -- 2.4.3 returns 6 values; the 2.5.3 client returns 8 (an enchant id after each hand's charges): reading it as 6 put a boolean where the off hand's time was
    local function pack(...) return { ... }, select("#", ...) end
    local t, n = pack(GetWeaponEnchantInfo())
    local mainOn, mainMs, mainCharges, offOn, offMs, offCharges
    if n >= 8 then mainOn, mainMs, mainCharges, offOn, offMs, offCharges = t[1], t[2], t[3], t[5], t[6], t[7]
    else mainOn, mainMs, mainCharges, offOn, offMs, offCharges = t[1], t[2], t[3], t[4], t[5], t[6] end
    local function add(slot, on, ms, charges)
      if on then
        list[#list + 1] = { enchant = slot, icon = GetInventoryItemTexture("player", slot == 1 and 16 or 17), count = charges,
          expires = GetTime() + (type(ms) == "number" and ms or 0) / 1000 }
      end
    end
    add(1, mainOn, mainMs, mainCharges); add(2, offOn, offMs, offCharges)
  end
  for i = 1, 40 do
    local name, icon, count, duration, expires, dtype = AFUI.UnitAura("player", i, filter)
    if not name then break end
    list[#list + 1] = { index = i, icon = icon, count = count, dtype = dtype, expires = (duration or 0) > 0 and expires or nil }
  end
  return list
end

function AFUI.RefreshBuffs()
  dirty = false
  local collapsed = DB().buffsCollapsed
  local y = 0
  for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
    local EM = AFUI.EditMode
    local list = collapsed and {} or (EM and EM.IsOpen and EM.IsOpen()) and sample(filter) or collect(filter)
    for i = 1, #list do put(pool[filter], filter, i, list[i], -y) end
    for i = #list + 1, #pool[filter] do pool[filter][i]:Hide() end -- an aura that ended goes at once
    rowsOf[filter] = math.ceil(#list / WRAP[filter])
    y = y + rowsOf[filter] * ROW + (filter == "HELPFUL" and rowsOf.HELPFUL > 0 and GAP or 0)
  end
end

-- The gold triangle: collapses the rows; the arrow turns around while they are folded away.
local arrow = CreateFrame("Button", "AFUI_BuffsToggle", holder)
arrow:SetWidth(14); arrow:SetHeight(18); arrow:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -6)
arrow.tex = arrow:CreateTexture(nil, "ARTWORK")
arrow.tex:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
arrow.tex:SetAllPoints(arrow)
function AFUI.SetBuffsCollapsed(on)
  DB().buffsCollapsed = on and true or nil
  if on then arrow.tex:SetTexCoord(1, 0, 0, 1) else arrow.tex:SetTexCoord(0, 1, 0, 1) end
  AFUI.RefreshBuffs()
end
arrow:SetScript("OnClick", function() AFUI.SetBuffsCollapsed(not DB().buffsCollapsed) end)

-- Time left and the pulse once a frame; a rescan on UNIT_AURA and four times a second (weapon enchants have no event of their own).
local scan = 0
local FILTERS = { "HELPFUL", "HARMFUL" }
holder:SetScript("OnUpdate", function(_, dt)
  scan = scan + dt
  if dirty or scan >= 0.25 then scan = 0; AFUI.RefreshBuffs() end
  local now, t = GetTime()
  for _, filter in ipairs(FILTERS) do
    for _, b in ipairs(pool[filter]) do
      if b:IsShown() then
        t = b.expires and b.expires - now or nil
        local key = t and math.ceil(math.max(t, 0)) or false -- the text only changes with the whole second: no string work on the frames in between
        if key ~= b.shownKey then
          b.shownKey = key
          local text, c = "", nil
          if t then text, c = AFUI.AuraTime(math.max(t, 0)) end
          b.shownText = text
          b.time:SetText(text); if c then b.time:SetTextColor(c[1], c[2], c[3]) end
        end
        b:SetAlpha(AFUI.AuraAlpha(t, now))
        if b.hover then tooltip(b) end
      end
    end
  end
end)
AFUI.On("UNIT_AURA", function(_, unit) if unit == "player" then dirty = true end end)
AFUI.On("PLAYER_AURAS_CHANGED", function() dirty = true end) -- 2.4.3
AFUI.On("UNIT_INVENTORY_CHANGED", function() dirty = true end)

AFUI.RegisterModule("Buffs", { OnLogin = function()
  AFUI.Kill(_G.BuffFrame); AFUI.Kill(_G.TemporaryEnchantFrame)
  AFUI.SetBuffsCollapsed(DB().buffsCollapsed)
end })
