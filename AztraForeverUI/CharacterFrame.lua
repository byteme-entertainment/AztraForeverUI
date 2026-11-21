-- Forever's Character window (docs/forever-ref/screens/windows/character-panel-method.png): the client's own CharacterFrame / PaperDollFrame inside
-- Forever's Metal portrait frame (the one WorldMap.lua and Bags.lua draw): class icon in the ring, the character's name as the title, the red X,
-- the dark stone model pane (8 + 8 gear slots down both sides, 3 weapon slots and the ammo slot under the model, zoom / rotate buttons), and the
-- stat pane on the right (two tab icons, "Level N Class", a scrolling list of section bars and gold-label / white-value rows), the mode tabs on
-- the right edge. Nothing of Blizzard's is rebuilt: old art is hidden, slots / model / name / close button / tabs are re-anchored and re-skinned,
-- item clicks, drags, tooltips, the model, durability and the ammo slot stay the client's own (secure-free) code.
-- Forever's code (blizzard_uipanels_game/camelot/characterframe.xml + paperdollframe.xml, build 1.60.1.70938): CHARACTER_FRAME_WIDTH 631 x 484 (left pane 398,
-- right pane 233), slots 37 px 6 px apart at (24, -60) / (-20, -60) of the left pane, weapon row BOTTOM -40 / -60 (ammo) / +30, mode tabs
-- 55 px tall 2 px apart from (right edge, -30), model controls 5 x 32 px at the top, stat rows 23 px, section bars 40 px.
-- Frame names (verified against the 2.4.3 FrameXML mirror MOUZU/Blizzard-WoW-Interface 2.4.3/FrameXML/{CharacterFrame,PaperDollFrame}.xml/.lua and
-- Gethe/wow-ui-source tag 2.5.3 Interface_TBC/FrameXML/{CharacterFrame,PaperDollFrame}.xml/.lua - the two clients share them):
--   CharacterFrame (384x512 UI panel), CharacterFramePortrait, CharacterNameFrame / CharacterNameText, CharacterFrameCloseButton, CharacterFrameTab1..5,
--   PaperDollFrame (+ CharacterLevelText / CharacterTitleText / CharacterGuildText, PlayerTitleDropDown, CharacterAttributesFrame with PlayerStatFrameLeft1..6 /
--   Right1..6 and the two stat dropdowns, CharacterResistanceFrame), CharacterModelFrame (+ CharacterModelFrameRotateLeft/RightButton),
--   Character{Head,Neck,Shoulder,Back,Chest,Shirt,Tabard,Wrist,Hands,Waist,Legs,Feet,Finger0,Finger1,Trinket0,Trinket1,MainHand,SecondaryHand,Ranged}Slot,
--   CharacterAmmoSlot, ToggleCharacter(frameName) (PaperDollFrame / PetPaperDollFrame / ReputationFrame / SkillFrame / PVPFrame), HasPetUI().
AFUI = AFUI or {}

local PLAIN = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\"

local W, H = 631, 484 -- CHARACTER_FRAME_WIDTH / HEIGHT
local LEFT_W, RIGHT_W = 398, 233
local TOP = 20 -- the title area above both panes
local SLOT, GAP = 37, 6
local ROW_H, HEAD_H = 23, 40 -- stat row / section bar heights (CharacterStatFrameTemplate sizes)
local HEAD_BG = 62 -- the stone header of the stat pane (the two tab icons; the level line stands over the model pane)
local VIEW = { x = 10, top = HEAD_BG + 8, bottom = 30, w = 193 } -- the scroll box inside the right pane: x from its left, y below its top, margin above its bottom
local TAB_W, TAB_H, TAB_GAP = 55, 55, 2 -- mode tabs on the right edge

---------------------------------------------------------------- pure logic (specs: tests/lua/characterframe_spec.lua)
local CF = {}
AFUI.CharacterFrame = CF
CF.W, CF.H, CF.LEFT_W, CF.RIGHT_W, CF.TOP = W, H, LEFT_W, RIGHT_W, TOP

-- the collapse button of the capture (f0017, 1.405 px per unit): plate 20 x 19, centre 377 / 40 units from the window's top left, flat colours sampled from the frame
CF.COLLAPSE = { w = 24, h = 24, cx = 377, cy = -40, border = 1.4, cols = 6, triW = 6, triH = 9.6,
  face = { 0.115, 0.11, 0.125 }, inner = { 0.2, 0.19, 0.1 }, top = { 0.51, 0.49, 0.26 }, bottom = { 0.29, 0.28, 0.18 }, side = { 0.24, 0.23, 0.09 }, gold = { 0.82, 0.74, 0.08 } }

-- Race art behind the model: brightness of the grayscale scene (0.4 = 40 %) and the black vignette (alpha at the edge, fade size in units). Tune here.
CF.RACE_DIM = 0.4
CF.RACE_VIGNETTE = { bottom = 0.6, bottomH = 150, side = 0.45, sideW = 60 }

-- ScrollFader art (193 x 24) is transparent at its top and black at its bottom: the bottom fade uses it as drawn, the top fade flipped (dark at the very top).
function CF.FaderCoords(e, atTop)
  if atTop then return e[4], e[5], e[7], e[6] end
  return e[4], e[5], e[6], e[7]
end

local LEFT_SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist" }
local RIGHT_SLOTS = { "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1" }

-- Slot positions from the window's TOPLEFT (y negative): { x, y, w, h }. Weapons are BOTTOM-anchored by Forever (x -40 from the pane's centre, -60 with
-- an ammo slot, y +30), the ammo slot sits 19 px right of the ranged slot.
function CF.SlotLayout(ammo)
  local out = {}
  for i, n in ipairs(LEFT_SLOTS) do out["Character" .. n .. "Slot"] = { 24, -(TOP + 60 + (i - 1) * (SLOT + GAP)), SLOT, SLOT } end
  for i, n in ipairs(RIGHT_SLOTS) do out["Character" .. n .. "Slot"] = { LEFT_W - 20 - SLOT, -(TOP + 60 + (i - 1) * (SLOT + GAP)), SLOT, SLOT } end
  local x0 = LEFT_W / 2 + (ammo and -60 or -40) - SLOT / 2
  local y = -(H - 30 - SLOT)
  out.CharacterMainHandSlot = { x0, y, SLOT, SLOT }
  out.CharacterSecondaryHandSlot = { x0 + SLOT + GAP, y, SLOT, SLOT }
  out.CharacterRangedSlot = { x0 + 2 * (SLOT + GAP), y, SLOT, SLOT }
  out.CharacterAmmoSlot = { x0 + 2 * (SLOT + GAP) + SLOT + 19, y + (SLOT - 27) / 2 * -1, 27, 27 }
  return out
end

function CF.Size(collapsed) return collapsed and LEFT_W or W, H end

-- Scroll maths: offset (px) clamped into [0, total - view]; the thumb of a track.
function CF.ScrollClamp(offset, total, view) return math.max(0, math.min(offset, math.max(total - view, 0))) end
function CF.ScrollThumb(offset, total, view, track)
  if total <= view then return track, 0 end
  local h = math.max(24, track * view / total)
  return h, (track - h) * offset / (total - view)
end
-- the offset a thumb position stands for
function CF.ScrollFromThumb(y, total, view, track)
  local h = CF.ScrollThumb(0, total, view, track)
  if total <= view or track <= h then return 0 end
  return CF.ScrollClamp(y / (track - h) * (total - view), total, view)
end

-- Flat row list { kind = "header" | "row", ... } with their top offsets; shaded rows are the odd ones of a section (statIndex % 2 == 1).
function CF.Flatten(sections)
  local rows, y = {}, 0
  for _, s in ipairs(sections) do
    if #s.rows > 0 then
      rows[#rows + 1] = { kind = "header", label = s.title, y = y, h = HEAD_H }
      y = y + HEAD_H
      for i, r in ipairs(s.rows) do
        rows[#rows + 1] = { kind = "row", label = r.label, value = r.value, tip = r.tip, icon = r.icon, shade = i % 2 == 1, y = y, h = ROW_H }
        y = y + ROW_H
      end
    end
  end
  return rows, y
end

function CF.QualityColor(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

-- "|cffffd100Level 21 Rogue|r": the capture's header line is gold all through (the class name is not coloured).
function CF.LevelLine(level, className)
  return "|cffffd100Level " .. tostring(level or 0) .. " " .. tostring(className or "") .. "|r"
end

-- The race pane art (DressUpFrame, 4 pieces 1..4); Scourge / unknown races fall back to the Orc art like the client's DressUpTexturePath.
function CF.BackgroundPath(raceFile)
  if type(DressUpTexturePath) == "function" then return DressUpTexturePath(raceFile) end
  return "Interface\\DressUpFrame\\DressUpBackground-" .. tostring(raceFile or "Orc")
end

-- a stat value coloured like the capture's buffed rows: green above base, red below
local function tinted(v, pos, neg)
  if (neg or 0) < 0 then return "|cffff2020" .. v .. "|r" elseif (pos or 0) > 0 then return "|cff20ff20" .. v .. "|r" end
  return v
end
local function pct(v) return string.format("%.1f%%", v or 0) end
local function num(v) return tostring(math.floor((v or 0) + 0.5)) end
local function call(name, ...)
  local f = _G[name]
  if type(f) == "function" then return f(...) end
end
local function combat(const) -- GetCombatRatingBonus(CR_*) -> percent; the constants are FrameXML globals
  local id = _G[const]
  if id and type(GetCombatRatingBonus) == "function" then return GetCombatRatingBonus(id) or 0 end
end
local function maxSpell(fn)
  local best
  for school = 2, 7 do
    local v = call(fn, school)
    if v and (not best or v > best) then best = v end
  end
  return best
end

-- Sections of the stat list { { title, rows = { { label, value, tip = { title, lines... } } } } }, only what the client's stat APIs answer.
function CF.StatSections()
  local out = {}
  local function section(title) local s = { title = title, rows = {} }; out[#out + 1] = s; return s end
  local function add(s, label, value, tip, ...)
    if value == nil then return end
    s.rows[#s.rows + 1] = { label = label, value = value, tip = tip and { title = tip, lines = { ... } } or nil }
  end
  local level = UnitLevel and UnitLevel("player") or 0

  local gen = section("General")
  if AFUI.ItemLevel and AFUI.QoL and AFUI.QoL.Get("charItemLevel") then -- "Item Level: 123", the average of the equipped gear (Bags.lua, AFUI.ItemLevel)
    local avg = AFUI.ItemLevel.EquippedAverage()
    add(gen, "Item Level", num(avg), "Item Level " .. num(avg), "The average item level of your equipped gear.")
  end
  local hp = call("UnitHealthMax", "player")
  if hp then add(gen, "Health", num(hp), "Health " .. num(hp), "Total health: you die when it reaches zero.") end
  local ptype, ptoken = call("UnitPowerType", "player")
  local pmax = call("UnitPowerMax", "player", ptype) or call("UnitManaMax", "player")
  local pname = ({ [0] = "Mana", [1] = "Rage", [2] = "Focus", [3] = "Energy" })[ptype or 0]
  if pmax and pname then add(gen, type(ptoken) == "string" and type(_G[ptoken]) == "string" and _G[ptoken] or pname, num(pmax), pname .. " " .. num(pmax), "The resource your abilities spend.") end
  local _, runSpeed = call("GetUnitSpeed", "player")
  if runSpeed then add(gen, "Movement Speed", math.floor(runSpeed / 7 * 100 + 0.5) .. "%", "Movement Speed", "How fast you run, compared to the base run speed of 7 yards per second.") end

  local attr = section("Primary Attributes")
  for i, n in ipairs({ "Strength", "Agility", "Stamina", "Intellect", "Spirit" }) do
    local stat, eff, pos, neg = call("UnitStat", "player", i)
    if eff then
      local v = tinted(num(eff), pos, neg)
      add(attr, n, v, n .. " " .. num(eff), _G["DEFAULT_STAT" .. i .. "_TOOLTIP"])
    end
  end

  local wp = section("Weapons")
  local minD, maxD, offMin, offMax = call("UnitDamage", "player")
  if minD then add(wp, "Main Hand", string.format("%d - %d", math.max(math.floor(minD), 1), math.max(math.ceil(maxD), 1)), "Main Hand Damage") end
  if offMin and call("OffhandHasWeapon") then add(wp, "Off Hand", string.format("%d - %d", math.max(math.floor(offMin), 1), math.max(math.ceil(offMax), 1)), "Off Hand Damage") end
  local rSpeed, rMin, rMax = call("UnitRangedDamage", "player")
  local hasRanged = rSpeed and rSpeed > 0 and rMin
  if hasRanged then add(wp, "Ranged", string.format("%d - %d", math.max(math.floor(rMin), 1), math.max(math.ceil(rMax), 1)), "Ranged Damage") end
  local ap, apPos, apNeg = call("UnitAttackPower", "player")
  if ap then add(wp, "Attack Power", tinted(num(ap + (apPos or 0) + (apNeg or 0)), apPos, apNeg), "Attack Power", "Increases damage with melee weapons.") end
  if hasRanged then
    local rap, rapPos, rapNeg = call("UnitRangedAttackPower", "player")
    if rap then add(wp, "Ranged Attack Power", tinted(num(rap + (rapPos or 0) + (rapNeg or 0)), rapPos, rapNeg), "Ranged Attack Power", "Increases damage with ranged weapons.") end
  end

  local mod = section("Modifiers")
  local hMelee, hRanged, hSpell = combat("CR_HIT_MELEE"), combat("CR_HIT_RANGED"), combat("CR_HIT_SPELL")
  if hMelee then
    hMelee = hMelee + (call("GetHitModifier") or 0)
    hSpell = (hSpell or 0) + (call("GetSpellHitModifier") or 0)
    add(mod, "Hit Chance", pct(math.max(hMelee, hRanged or 0, hSpell)), "Hit Chance " .. pct(math.max(hMelee, hRanged or 0, hSpell)),
      "Increases Melee hit chance by " .. pct(hMelee) .. ".", "Increases Ranged hit chance by " .. pct(hRanged or 0) .. ".", "Increases Spell hit chance by " .. pct(hSpell) .. ".")
  end
  local crit = call("GetCritChance")
  if crit then
    local rc, sc = call("GetRangedCritChance"), maxSpell("GetSpellCritChance")
    add(mod, "Critical Strike", pct(math.max(crit, rc or 0, sc or 0)), "Critical Strike Chance", "Melee " .. pct(crit), "Ranged " .. pct(rc or 0), "Spell " .. pct(sc or 0))
  end
  local haste = combat("CR_HASTE_MELEE")
  if haste then add(mod, "Haste", pct(haste), "Haste", "Increases attack and casting speed.") end
  local expertise = call("GetExpertise")
  if expertise and expertise > 0 then add(mod, "Expertise", num(expertise), "Expertise", "Reduces the chance your attacks are dodged or parried.") end
  local sd = maxSpell("GetSpellBonusDamage")
  if sd and sd > 0 then add(mod, "Spell Damage", num(sd), "Spell Damage", "Increases the damage of your spells.") end
  local sh = call("GetSpellBonusHealing")
  if sh and sh > 0 then add(mod, "Spell Healing", num(sh), "Spell Healing", "Increases the healing of your spells.") end
  if (call("UnitPowerType", "player") or 0) == 0 then
    local regen = call("GetManaRegen")
    if regen then add(mod, "Mana Regen", num(regen * 5), "Mana Regeneration", "Mana per 5 seconds while not casting.") end
  end

  local def = section("Defense")
  local _, armor, _, armorPos, armorNeg = call("UnitArmor", "player")
  if armor then add(def, "Armor", tinted(num(armor), armorPos, armorNeg), "Armor " .. num(armor), "Reduces physical damage taken.") end
  local dBase, dMod = call("UnitDefense", "player")
  if dBase then add(def, "Defense", num(dBase + (dMod or 0)) .. " / " .. level * 5, "Defense", "Reduces the chance to be hit and critically hit.") end
  local dodge = call("GetDodgeChance")
  if dodge then add(def, "Dodge", pct(dodge), "Dodge Chance", "Chance to dodge a melee attack.") end
  local parry = call("GetParryChance")
  if parry then add(def, "Parry", pct(parry), "Parry Chance", "Chance to parry a melee attack.") end
  local block = call("GetBlockChance")
  if block and block > 0 then add(def, "Block", pct(block), "Block Chance", "Chance to block with a shield.") end
  local resil = _G.CR_CRIT_TAKEN_MELEE and call("GetCombatRating", _G.CR_CRIT_TAKEN_MELEE)
  if resil and resil > 0 then add(def, "Resilience", num(resil), "Resilience", "Reduces the chance to be critically hit.") end

  local res = section("Resistances")
  for _, r in ipairs({ { 6, "Arcane" }, { 2, "Fire" }, { 4, "Frost" }, { 3, "Nature" }, { 5, "Shadow" } }) do
    local _, total = call("UnitResistance", "player", r[1])
    if total then
      add(res, r[2], num(total), r[2] .. " Resistance " .. num(total), "Reduces " .. r[2] .. " damage taken.")
      res.rows[#res.rows].icon = "ui-character-info-resistance-" .. string.lower(r[2]) .. "-c60"
    end
  end
  return out
end

---------------------------------------------------------------- the window
local function atlasTexture(parent, layer, name, w, h)
  local t = parent:CreateTexture(nil, layer)
  AFUI.SetAtlas(t, name, w == nil)
  if w then t:SetWidth(w); t:SetHeight(h) end
  return t
end

-- common-insideframe style stretch: 9 pieces, corners at texel size m (the atlas has slices of 53), edges and centre stretched.
local function nineSlice(parent, layer, name, m, px) -- m: corner size in texels, px: drawn corner size (default m; smaller for small boxes)
  px = px or m
  local e = AFUI_ATLAS and AFUI_ATLAS[string.lower(name)]
  if not e then return {} end
  local su, sv = (e[5] - e[4]) * m / e[2], (e[7] - e[6]) * m / e[3]
  local us = { e[4], e[4] + su, e[5] - su, e[5] }
  local vs = { e[6], e[6] + sv, e[7] - sv, e[7] }
  local pieces = {}
  for r = 1, 3 do
    for c = 1, 3 do
      local t = parent:CreateTexture(nil, layer)
      t:SetTexture(e[1]); t:SetTexCoord(us[c], us[c + 1], vs[r], vs[r + 1])
      pieces[#pieces + 1] = { t = t, r = r, c = c }
    end
  end
  -- Place(host, l, t, r, b): the frame's TOPLEFT (l, t) and BOTTOMRIGHT (r, b) offsets (WoW offsets: y up). Each piece is its cell's two corners,
  -- every boundary anchored to the nearer host edge so only the middle row / column stretches.
  function pieces.Place(host, l, t, r, b)
    local xs = { { "LEFT", l }, { "LEFT", l + px }, { "RIGHT", r - px }, { "RIGHT", r } }
    local ys = { { "TOP", t }, { "TOP", t - px }, { "BOTTOM", b + px }, { "BOTTOM", b } }
    for _, p in ipairs(pieces) do
      local a, z = xs[p.c], xs[p.c + 1]
      local c, d = ys[p.r], ys[p.r + 1]
      p.t:ClearAllPoints()
      p.t:SetPoint("TOPLEFT", host, c[1] .. a[1], a[2], c[2])
      p.t:SetPoint("BOTTOMRIGHT", host, d[1] .. z[1], z[2], d[2])
    end
  end
  return pieces
end

-- Old Blizzard art of a frame: every unnamed texture (and, when asked, text) region; 2.5.3 answers file ids for XML art so no path can be matched.
local function hideRegions(host, withText)
  if not host or not host.GetRegions then return end
  for _, r in ipairs({ host:GetRegions() }) do
    if r.IsObjectType then
      if r:IsObjectType("Texture") and not r:GetName() then r:Hide()
      elseif withText and r:IsObjectType("FontString") then r:Hide() end
    end
  end
end

local function setShown(f, on) if on then f:Show() else f:Hide() end end

-- A scrolling row list (ScrollFrame: both clients; the content child is moved by SetVerticalScroll). rows = CF.Flatten output.
-- o = { width, row = function(content) -> row frame, fill = function(frame, data) } lets the Reputation / Skills / PvP panes reuse the scroll box with their own rows.
local function newList(parent, name, o)
  o = o or {}
  local vw = o.width or VIEW.w
  local list = { rows = {}, offset = 0, total = 0, pool = {} }
  local sf = CreateFrame("ScrollFrame", name, parent)
  local content = CreateFrame("Frame", nil, sf)
  content:SetWidth(vw); content:SetHeight(1)
  sf:SetScrollChild(content)
  content:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0)
  sf:EnableMouseWheel(true)
  list.sf, list.content = sf, content

  -- the shared scroll bar (WinKit.scrollbar): flush with the rows, pixels are the unit, two rows a wheel notch, eased
  local function viewH() return sf:GetHeight() end
  list.bar = AFUI.WinKit.scrollbar(sf, {
    get = function() return list.offset end,
    set = function(v) list.offset = v; sf:SetVerticalScroll(v); if list.OnSync then list.OnSync() end end,
    max = function() return math.max(list.total - viewH(), 0) end, view = viewH, step = ROW_H * 2,
  }, { x = 1 })
  local function sync()
    list.offset = CF.ScrollClamp(list.offset, list.total, viewH())
    sf:SetVerticalScroll(list.offset)
    list.bar:Refresh()
    if list.OnSync then list.OnSync() end
  end
  list.Sync = sync
  function list:SetActive(on) self.active = on; setShown(sf, on); sync() end
  function list:ScrollBy(d) self.bar:ScrollBy(d) end
  sf:SetScript("OnSizeChanged", sync)

  local function row(i)
    local f = list.pool[i]
    if f then return f end
    if o.row then f = o.row(content); list.pool[i] = f; return f end
    f = CreateFrame("Button", nil, content)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.title = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    f.value = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.label:SetJustifyH("LEFT"); f.value:SetJustifyH("RIGHT")
    f.icon = f:CreateTexture(nil, "ARTWORK") -- the school icon of a resistance row
    f.icon:SetWidth(22); f.icon:SetHeight(22); f.icon:SetPoint("LEFT", f, "LEFT", 4, 0)
    f:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    local hl = f:GetHighlightTexture()
    if hl then hl:SetAlpha(0.3) end
    f:SetScript("OnEnter", function(self)
      if not self.data or not self.data.tip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.data.tip.title, 1, 1, 1)
      for _, l in ipairs(self.data.tip.lines) do GameTooltip:AddLine(l, 1, 0.82, 0, true) end
      GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnClick", function(self) if self.data and self.data.click then self.data.click() end end)
    list.pool[i] = f
    return f
  end
  function list:SetRows(rows, total)
    self.rows, self.total = rows, total
    content:SetHeight(math.max(total, 1))
    for i, d in ipairs(rows) do
      local f = row(i)
      f.data = d
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -d.y); f:SetWidth(vw); f:SetHeight(d.h)
      if o.fill then o.fill(f, d)
      elseif d.kind == "header" then
        AFUI.SetAtlas(f.bg, "ui-character-info-title-c60")
        f.bg:ClearAllPoints(); f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 0); f.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, 0); f.bg:Show()
        f.title:ClearAllPoints(); f.title:SetPoint("CENTER", f, "CENTER", 0, 1); f.title:SetText(d.label); f.title:Show()
        f.label:Hide(); f.value:Hide(); f.icon:Hide()
      else
        AFUI.SetAtlas(f.bg, "ui-character-info-line-bounce2-c60", true)
        f.bg:ClearAllPoints(); f.bg:SetPoint("CENTER", f, "CENTER"); setShown(f.bg, d.shade)
        f.title:Hide()
        if d.icon then AFUI.SetAtlas(f.icon, d.icon); f.icon:SetWidth(22); f.icon:SetHeight(22); f.icon:Show() else f.icon:Hide() end
        f.label:ClearAllPoints(); f.label:SetPoint("LEFT", f, "LEFT", d.icon and 33 or 11, 0); f.label:SetText(d.label and (d.label .. ":") or ""); f.label:Show()
        f.value:ClearAllPoints(); f.value:SetPoint("RIGHT", f, "RIGHT", -8, 0); f.value:SetText(d.value or ""); setShown(f.value, d.value ~= nil)
        if d.current then f.label:SetTextColor(1, 1, 1) else f.label:SetTextColor(1, 0.82, 0) end
      end
      if not o.fill then local on = d.kind ~= "header" and (d.tip ~= nil or d.click ~= nil); f:EnableMouse(on); f.afNoClick = not on end
      f:Show()
    end
    for i = #rows + 1, #self.pool do self.pool[i]:Hide() end
    sync()
  end
  return list
end

local SIDE_TABS = { -- mode tabs, top to bottom: Blizzard sub-frame, tooltip, icon (a path, or "portrait" / "pet")
  { "PaperDollFrame", CHARACTER or "Character", "portrait" },
  { "PetPaperDollFrame", PET or "Pet", "pet", needsPet = true },
  { "ReputationFrame", REPUTATION or "Reputation", PLAIN .. "INV_SideTab_Reputation2_c60" },
  { "SkillFrame", SKILLS or "Skills", PLAIN .. "Ability_Racial_JackofAllTrades" },
  { "PVPFrame", PLAYER_V_PLAYER or "Player vs. Player", "pvp" },
}
CF.SIDE_TABS = SIDE_TABS

local function setup()
  if AFUI.CharacterWindow or not CharacterFrame or not PaperDollFrame then return end
  local cf, pd = CharacterFrame, PaperDollFrame
  local base = cf:GetFrameLevel()
  local db = function() return AztraForeverUICharDB or {} end
  local function isCollapsed()
    local pet = _G.PetPaperDollFrame
    return db().characterCollapsed == true and (pd:IsShown() or (pet ~= nil and pet:IsShown()) or (AFUI.CharacterPanes and AFUI.CharacterPanes.Active())) or false
  end

  -- Blizzard's old frame art (unnamed textures of the frame and its sub-frames; the portrait is named and hidden below)
  hideRegions(cf, true)
  for _, k in ipairs({ "NineSlice", "Bg", "TopTileStreaks", "PortraitContainer", "TitleContainer", "Inset" }) do
    local part = type(cf[k]) == "table" and cf[k] or nil
    if part and part.Hide then part:Hide() end
  end
  if CharacterFramePortrait then CharacterFramePortrait:Hide() end
  hideRegions(pd, true)
  for _, n in ipairs({ "PetPaperDollFrame", "ReputationFrame", "SkillFrame", "PVPFrame" }) do hideRegions(_G[n]) end
  -- stat blocks, dropdowns and the resistance column of the old paper doll: Forever's stat list replaces them
  for _, n in ipairs({ "CharacterAttributesFrame", "CharacterResistanceFrame", "PlayerTitleDropDown", "PlayerStatFrameLeftDropDown", "PlayerStatFrameRightDropDown" }) do
    local f = _G[n]
    if f then f:SetParent(AFUI.Hidden); f:Hide() end
  end
  for _, n in ipairs({ "CharacterModelFrameRotateLeftButton", "CharacterModelFrameRotateRightButton" }) do if _G[n] then _G[n]:Hide() end end
  for i = 1, 5 do -- the bottom tabs: still there (the client's tab logic shows / hides them), but invisible and without a mouse
    local t = _G["CharacterFrameTab" .. i]
    if t then t:SetAlpha(0); t:EnableMouse(false) end
  end

  local win = CreateFrame("Frame", "AFUI_CharacterWindow", cf)
  win:SetAllPoints(cf)
  win:SetFrameLevel(base)
  AFUI.CharacterWindow = win

  -- The paper doll has no Rock fill (the two panes cover the window and the stat pane's header is translucent in the capture: the world shows
  -- through it; the title bar is the metal frame's own art). The other tabs (Blizzard's reputation / skills / PvP / pet pages) sit on the Rock
  -- like Forever's map and bag windows (Bg, TOPLEFT 2,-21 / BOTTOMRIGHT -2,2).
  local rock = win:CreateTexture(nil, "BACKGROUND")
  rock:SetTexture(PLAIN .. "UI-Background-Rock"); rock:SetVertexColor(0.6, 0.54, 0.5)
  rock:SetPoint("TOPLEFT", win, "TOPLEFT", 2, -21); rock:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -2, 2)

  -- metal frame pieces for the current width (one set per width, like WorldMap.lua)
  local chromes = {}
  local function chrome(w)
    if chromes[w] then return chromes[w] end
    local c = CreateFrame("Frame", nil, win)
    c:SetFrameLevel(base + 20)
    c:SetPoint("TOPLEFT", win, "TOPLEFT")
    c:SetWidth(w); c:SetHeight(H)
    local VERTICAL = { ["!ui-frame-metal-edgeleft-c60-2x"] = true, ["!ui-frame-metal-edgeright-c60-2x"] = true }
    for _, p in ipairs(AFUI.WorldMapPieces(w, H, true)) do
      local t = atlasTexture(c, "OVERLAY", p.atlas, p.w, p.h)
      local e = AFUI_ATLAS and AFUI_ATLAS[string.lower(p.atlas)]
      if e and p.crop and p.crop < 1 then
        if VERTICAL[p.atlas] then t:SetTexCoord(e[4], e[5], e[6], e[6] + (e[7] - e[6]) * p.crop)
        else t:SetTexCoord(e[4], e[4] + (e[5] - e[4]) * p.crop, e[6], e[7]) end
      end
      t:SetPoint("TOPLEFT", c, "TOPLEFT", p.x, p.y)
    end
    chromes[w] = c
    return c
  end

  -- the class icon in the ring, the title (the client's own name text) and the red X
  local _, classToken = UnitClass("player")
  local portrait = win:CreateTexture(nil, "ARTWORK")
  portrait:SetWidth(62); portrait:SetHeight(62); portrait:SetPoint("TOPLEFT", win, "TOPLEFT", -5, 7)
  AFUI.WindowPortrait(win, portrait)
  local function classIcon()
    if not pd:IsShown() then AFUI.PortraitUnit(portrait, "player"); portrait:SetTexCoord(0.04, 0.96, 0.04, 0.96); return end
    local co = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken or ""]
    if co then portrait:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"); portrait:SetTexCoord(co[1] + 0.004, co[2] - 0.004, co[3] + 0.004, co[4] - 0.004)
    else AFUI.PortraitUnit(portrait, "player"); portrait:SetTexCoord(0, 1, 0, 1) end
  end
  classIcon()
  local nameFrame, nameText = _G.CharacterNameFrame, _G.CharacterNameText
  if nameFrame and nameText then
    nameFrame:ClearAllPoints(); nameFrame:SetPoint("TOP", cf, "TOP", 17, -6)
    nameFrame:SetFrameLevel(base + 25)
    nameText:SetTextColor(1, 1, 1)
    cf:HookScript("OnShow", function() nameText:SetTextColor(1, 1, 1) end)
  end
  local tabTitle -- the other tabs' gold title in place of the character's white name
  if nameFrame and nameText then
    tabTitle = nameFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tabTitle:SetPoint("CENTER", nameText, "CENTER", 0, 0); tabTitle:Hide()
  end
  local close = _G.CharacterFrameCloseButton
  if close then
    close:ClearAllPoints(); close:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 0, 3)
    close:SetWidth(28); close:SetHeight(28); close:SetFrameLevel(base + 30)
    AFUI.SetButtonAtlas(close, { "redbutton-exit", "redbutton-exit-pressed", "redbutton-highlight", "redbutton-exit-disabled" })
  end
  if AFUI.WinKit then -- drag by the title strip (above the name frame), every tab
    local drag = CreateFrame("Frame", nil, cf)
    drag:SetPoint("TOPLEFT", cf, "TOPLEFT", 58, 0); drag:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -62, 0); drag:SetHeight(20); drag:SetFrameLevel(base + 26)
    AFUI.WinKit.makeMovable(cf, drag, "character")
  end

  ------------------------------------------------------------ the paper doll: panes, slots, model, stat list (everything a child of PaperDollFrame)
  local general = atlasTexture(pd, "BACKGROUND", "ui-character-info-general-bg-c60")
  general:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, -TOP)
  local rightHost = CreateFrame("Frame", nil, pd) -- the whole right pane, shown or collapsed away
  rightHost:SetPoint("TOPLEFT", cf, "TOPLEFT", LEFT_W, -TOP); rightHost:SetWidth(RIGHT_W); rightHost:SetHeight(H - TOP)
  local statBg = atlasTexture(rightHost, "BACKGROUND", "ui-character-info-stat-bg-c60")
  statBg:SetPoint("TOPLEFT", rightHost, "TOPLEFT"); statBg:SetPoint("BOTTOMRIGHT", rightHost, "BOTTOMRIGHT") -- stretched to the frame: no transparent strip at the bottom
  local stone = atlasTexture(rightHost, "ARTWORK", "ui-character-info-stat-stonebg-c60") -- the header behind the tab icons and the level line
  stone:SetPoint("TOPLEFT", rightHost, "TOPLEFT")
  local classBg = _G.RAID_CLASS_COLORS and classToken and atlasTexture(rightHost, "BORDER", "ui-character-info-" .. string.lower(classToken) .. "-bg-c60")
  if classBg then classBg:SetPoint("TOPLEFT", rightHost, "TOPLEFT", 0, -(HEAD_BG - 5)); classBg:SetPoint("BOTTOMRIGHT", rightHost, "BOTTOMRIGHT") end
  local divider = CreateFrame("Frame", nil, rightHost)
  divider:SetFrameLevel(base + 12); divider:SetPoint("TOPLEFT", rightHost, "TOPLEFT", -6, 0); divider:SetWidth(11); divider:SetHeight(H - TOP)
  do -- common-framedivider (11 x 50, slices 12 top / 12 bottom, the middle 26 px tile along the pane)
    local e = AFUI_ATLAS and AFUI_ATLAS["common-framedivider-c60"]
    if e then
      local function piece(y, len, v0, v1)
        local t = divider:CreateTexture(nil, "OVERLAY")
        t:SetTexture(e[1]); t:SetWidth(11); t:SetHeight(len)
        local dv = e[7] - e[6]
        t:SetTexCoord(e[4], e[5], e[6] + dv * v0, e[6] + dv * v1)
        t:SetPoint("TOPLEFT", divider, "TOPLEFT", 0, -y)
      end
      local total = H - TOP
      piece(0, 12, 0, 12 / 50); piece(total - 12, 12, 38 / 50, 1)
      local y = 12
      while y < total - 12 do
        local len = math.min(26, total - 12 - y)
        piece(y, len, 12 / 50, (12 + len) / 50)
        y = y + len
      end
    end
  end

  -- race art behind the model (DressUp pieces, desaturated, with the dark overlay at Forever's per-race alpha)
  local _, raceFile = UnitRace("player")
  local MODEL_TOP = TOP + 31 -- the capture: the race art starts 50 px under the window top, right under the level line
  local racePath = CF.BackgroundPath(raceFile)
  -- the four pieces of Forever's model pane (camelot paperdollframe.xml CharacterModelScene): x0, y0, x1, y1 from the window's TOPLEFT + texcoords
  for i, p in ipairs({
    { 0, MODEL_TOP, LEFT_W - 79, H - 129, 0.171875, 1, 0.0392156862745098, 1 },
    { LEFT_W - 80, MODEL_TOP, LEFT_W, H - 129, 0, 0.296875, 0.0392156862745098, 1 },
    { 0, H - 130, LEFT_W - 79, H, 0.171875, 1, 0, 0.62 },
    { LEFT_W - 80, H - 130, LEFT_W, H, 0, 0.296875, 0, 0.62 },
  }) do
    local t = pd:CreateTexture(nil, "BORDER")
    t:SetTexture(racePath .. i); t:SetTexCoord(p[5], p[6], p[7], p[8]); t:SetDesaturated(true)
    t:SetVertexColor(CF.RACE_DIM, CF.RACE_DIM, CF.RACE_DIM) -- the black and white scene is dimmed so the model stands out
    t:SetPoint("TOPLEFT", cf, "TOPLEFT", p[1], -p[2]); t:SetPoint("BOTTOMRIGHT", cf, "TOPLEFT", p[3], -p[4])
  end
  do -- vignette over the dimmed scene: black fades in from the bottom and from both sides (SetGradientAlpha: bottom colour first, as in the TBC client)
    local V = CF.RACE_VIGNETTE
    local function fade(orient, a0, a1, x0, y0, x1, y1)
      local t = pd:CreateTexture(nil, "BORDER"); AFUI.SetColor(t, 0, 0, 0, 1)
      t:SetPoint("TOPLEFT", cf, "TOPLEFT", x0, -y0); t:SetPoint("BOTTOMRIGHT", cf, "TOPLEFT", x1, -y1)
      if t.SetGradientAlpha then t:SetGradientAlpha(orient, 0, 0, 0, a0, 0, 0, 0, a1) end
    end
    fade("VERTICAL", V.bottom, 0, 0, H - V.bottomH, LEFT_W, H)
    fade("HORIZONTAL", V.side, 0, 0, MODEL_TOP, V.sideW, H)
    fade("HORIZONTAL", 0, V.side, LEFT_W - V.sideW, MODEL_TOP, LEFT_W, H)
  end
  local overlay = atlasTexture(pd, "BORDER", "ui-character-info-racebg-overlay-c60", LEFT_W, H - MODEL_TOP)
  overlay:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, -MODEL_TOP)
  overlay:SetAlpha(({ HUMAN = 1, DWARF = 0.93, NIGHTELF = 0.5, TROLL = 0.85, ORC = 0.75, SCOURGE = 0.2 })[string.upper(raceFile or "")] or 0.85)

  do -- the level line's stone band (video3 f0017: #34302a from 27 u to 56 u under the window top, a darker rule at its foot), drawn over the top of the race art
    local band = pd:CreateTexture(nil, "BORDER"); AFUI.SetColor(band, 0.2, 0.188, 0.165, 1)
    band:SetPoint("TOPLEFT", cf, "TOPLEFT", 3, -27); band:SetPoint("BOTTOMRIGHT", cf, "TOPLEFT", LEFT_W - 2, -56)
    local top = pd:CreateTexture(nil, "BORDER"); AFUI.SetColor(top, 0.15, 0.13, 0.115, 1)
    top:SetPoint("TOPLEFT", band, "TOPLEFT"); top:SetPoint("TOPRIGHT", band, "TOPRIGHT"); top:SetHeight(2)
    local foot = pd:CreateTexture(nil, "BORDER"); AFUI.SetColor(foot, 0.1, 0.095, 0.085, 1)
    foot:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT"); foot:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT"); foot:SetHeight(1)
  end

  -- the model: the client's PlayerModel between the slot columns
  local model = _G.CharacterModelFrame
  if model then
    model:ClearAllPoints()
    model:SetPoint("TOPLEFT", cf, "TOPLEFT", 62, -(TOP + 58))
    model:SetPoint("BOTTOMRIGHT", cf, "TOPLEFT", LEFT_W - 62, -(H - 6))
  end

  -- zoom / rotate / reset controls (ModelSceneControlFrameTemplate: 5 x 32 px, -6 px apart, dim until the mouse is over)
  local controls = CreateFrame("Frame", nil, pd)
  controls:SetWidth(5 * 32 - 4 * 6); controls:SetHeight(32)
  controls:SetPoint("TOP", cf, "TOPLEFT", LEFT_W / 2 + 1, -(TOP + 41))
  controls:SetFrameLevel(base + 10)
  local IDLE = 0.8 -- video3 f0017 / f0037: the five buttons are always on (a little dimmer than the hover), mouse nowhere near the model
  controls:SetAlpha(IDLE); controls:EnableMouse(true)
  controls:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
  controls:SetScript("OnLeave", function(self) self:SetAlpha(IDLE) end)
  if model and model.HookScript then
    model:HookScript("OnEnter", function() controls:SetAlpha(1) end)
    model:HookScript("OnLeave", function() controls:SetAlpha(IDLE) end)
  end
  local scale = 1
  local function zoom(d)
    if not model or not model.SetModelScale then return end
    scale = math.max(0.5, math.min(1.6, scale + d)); model:SetModelScale(scale)
  end
  local function ctl(i, icon, tip, fn)
    local b = CreateFrame("Button", nil, controls)
    b:SetWidth(32); b:SetHeight(32); b:SetPoint("LEFT", controls, "LEFT", (i - 1) * 26, 0)
    b:SetHitRectInsets(4, 4, 4, 4)
    b:RegisterForClicks("LeftButtonDown")
    AFUI.SetButtonAtlas(b, { "common-button-square-gray-up", "common-button-square-gray-down" })
    local ic = atlasTexture(b, "OVERLAY", icon, 16, 16); ic:SetPoint("CENTER")
    b:SetScript("OnMouseDown", function() ic:ClearAllPoints(); ic:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function() ic:ClearAllPoints(); ic:SetPoint("CENTER") end)
    b:SetScript("OnClick", fn)
    b:SetScript("OnEnter", function(self) controls:SetAlpha(1); GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(tip); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() controls:SetAlpha(IDLE); GameTooltip:Hide() end)
    return b
  end
  ctl(1, "common-icon-zoomin", "Zoom In", function() zoom(0.1) end)
  ctl(2, "common-icon-zoomout", "Zoom Out", function() zoom(-0.1) end)
  ctl(3, "common-icon-rotateleft", "Rotate Left", function() if Model_RotateLeft and model then Model_RotateLeft(model) end end)
  ctl(4, "common-icon-rotateright", "Rotate Right", function() if Model_RotateRight and model then Model_RotateRight(model) end end)
  ctl(5, "common-icon-undo", "Reset Camera", function()
    scale = 1
    if model then
      if model.SetModelScale then model:SetModelScale(1) end
      model.rotation = 0
      if model.SetRotation then model:SetRotation(0) end
    end
  end)

  -- slots: the client's buttons, re-anchored and re-skinned
  local slotButtons = {}
  local function layoutSlots()
    local lay = CF.SlotLayout(false) -- the capture's weapon row (ranged slot + ammo slot shown) stands at -40, not at the -60 of Forever's XML
    for name, p in pairs(lay) do
      local b = _G[name]
      if b then
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", cf, "TOPLEFT", p[1], p[2])
        b:SetWidth(p[3]); b:SetHeight(p[4])
      end
    end
  end
  local function skinSlot(name, small)
    local b = _G[name]
    if not b then return end
    if b.afSkinned then return end
    b.afSkinned = true
    b:SetNormalTexture("") -- the old Quickslot frame
    if small then hideRegions(b) end -- the ammo slot's own round frame art
    local bg = atlasTexture(b, "BACKGROUND", small and "ui-character-info-gearslotsmall-c60" or "ui-character-info-gearslot-c60")
    bg:SetPoint("CENTER", b, "CENTER")
    local icon = _G[name .. "IconTexture"]
    if icon then icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3); icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    local q = b:CreateTexture(nil, "OVERLAY"); q:SetTexture(PLAIN .. "WhiteIconFrame"); q:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3); q:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3); q:Hide()
    b.afQuality = q
    slotButtons[#slotButtons + 1] = b
  end
  for name in pairs(CF.SlotLayout(false)) do skinSlot(name, name == "CharacterAmmoSlot") end
  layoutSlots()
  do -- the orange arrow pointing from the ammo slot into the ranged slot (camelot paperdollframe.xml: right edge 6 px into the ammo slot)
    local ammo = _G.CharacterAmmoSlot
    if ammo then
      local arrow = atlasTexture(ammo, "OVERLAY", "ui-character-info-gearslot-arrow-c60", 26, 18)
      arrow:SetPoint("RIGHT", ammo, "LEFT", 6, 0)
    end
  end
  local function updateSlots()
    for _, b in ipairs(slotButtons) do
      local id = b:GetID()
      local link = id and id > 0 and GetInventoryItemLink and GetInventoryItemLink("player", id)
      local quality = link and select(3, GetItemInfo(link))
      if quality and quality > 1 then b.afQuality:SetVertexColor(CF.QualityColor(quality)); b.afQuality:Show() else b.afQuality:Hide() end
    end
  end

  ------------------------------------------------------------ the right pane: tab icons, level line, stat / title lists
  local tabs = {}
  local function paneTab(i, x, icon)
    local b = CreateFrame("Button", nil, rightHost)
    b:SetWidth(42); b:SetHeight(42); b:SetPoint("TOP", rightHost, "TOP", x, -9)
    local ic = b:CreateTexture(nil, "BACKGROUND"); ic:SetWidth(33); ic:SetHeight(33); ic:SetPoint("CENTER") -- inside the 4 px frame
    b.icon = ic
    icon(ic)
    local frame = atlasTexture(b, "BORDER", "ui-character-info-stattab-c60"); frame:SetPoint("CENTER")
    local sel = atlasTexture(b, "OVERLAY", "ui-character-info-stattab-selected-c60"); sel:SetPoint("CENTER")
    b.sel = sel
    b:SetScript("OnClick", function() CF.SetPane(i) end)
    tabs[i] = b
    return b
  end
  paneTab(1, -21, function(t) SetPortraitTexture(t, "player"); t:SetTexCoord(0.03, 0.97, 0.03, 0.97) end)
  paneTab(2, 21, function(t) t:SetTexture(PLAIN .. "INV_SideTab_Titles_c60"); t:SetTexCoord(0, 1, 0, 1) end)
  tabs[1]:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Character Stats"); GameTooltip:Show() end)
  tabs[2]:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(TITLES or "Titles"); GameTooltip:Show() end)
  for _, t in ipairs(tabs) do t:SetScript("OnLeave", function() GameTooltip:Hide() end) end

  -- "Level 21 Rogue": gold, centred in the first row of the model pane (the capture: 42 units under the window top, the collapse arrow at its end)
  local levelText = pd:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  levelText:SetPoint("CENTER", cf, "TOPLEFT", LEFT_W / 2, -42)
  local font, size = levelText:GetFont()
  if font then levelText:SetFont(font, size or 16, "OUTLINE") end

  local statList = newList(rightHost, "AFUI_CharacterStatList")
  statList.sf:SetPoint("TOPLEFT", rightHost, "TOPLEFT", VIEW.x, -VIEW.top)
  statList.sf:SetPoint("BOTTOMRIGHT", rightHost, "BOTTOMLEFT", VIEW.x + VIEW.w, VIEW.bottom)
  CF.StatList = statList
  local titleList = newList(rightHost, "AFUI_CharacterTitleList")
  titleList.sf:SetPoint("TOPLEFT", rightHost, "TOPLEFT", VIEW.x, -VIEW.top)
  titleList.sf:SetPoint("BOTTOMRIGHT", rightHost, "BOTTOMLEFT", VIEW.x + VIEW.w, VIEW.bottom)
  -- the inside frame around the list (common-insideframe, slices of 53) and the line under it
  local inside = CreateFrame("Frame", nil, rightHost)
  inside:SetFrameLevel(base + 8)
  inside:SetPoint("TOPLEFT", rightHost, "TOPLEFT", 0, -HEAD_BG); inside:SetPoint("BOTTOMRIGHT", rightHost, "BOTTOMRIGHT")
  local frameBorder = nineSlice(inside, "OVERLAY", "common-insideframe-c60", 53)
  if frameBorder.Place then frameBorder.Place(inside, 1, 1, -4, -2) end
  local line = atlasTexture(inside, "OVERLAY", "ui-character-info-scrollline-c60")
  line:SetPoint("TOP", statList.sf, "BOTTOM", 0, 0)
  -- rows fade out at both ends of the list (ScrollFader: black at the art's bottom, so flipped at the top)
  local fadeTop = atlasTexture(inside, "ARTWORK", "ui-character-info-scrollfader-c60")
  fadeTop:SetPoint("TOPLEFT", statList.sf, "TOPLEFT", 0, 0)
  local fadeBottom = atlasTexture(inside, "ARTWORK", "ui-character-info-scrollfader-c60")
  fadeBottom:SetPoint("BOTTOMLEFT", statList.sf, "BOTTOMLEFT", 0, 0)
  do
    local e = AFUI_ATLAS and AFUI_ATLAS["ui-character-info-scrollfader-c60"]
    if e then fadeTop:SetTexCoord(CF.FaderCoords(e, true)); fadeBottom:SetTexCoord(CF.FaderCoords(e, false)) end
  end

  local pane = 1
  -- the faders only show where rows are cut off: not over the first section bar of an unscrolled list
  local function fades()
    local l = pane == 1 and statList or titleList
    setShown(fadeTop, l.offset > 0)
    setShown(fadeBottom, l.offset < l.total - l.sf:GetHeight() - 1)
  end
  statList.OnSync, titleList.OnSync = fades, fades
  local function titleRows()
    local rows, y = {}, 0
    local current = call("GetCurrentTitle") or -1
    local function add(label, id)
      rows[#rows + 1] = { kind = "row", label = label, shade = #rows % 2 == 0, y = y, h = ROW_H, current = id == current,
        click = function() SetCurrentTitle(id); CF.Refresh() end }
      y = y + ROW_H
    end
    add(NONE or "None", -1)
    for i = 1, call("GetNumTitles") or 0 do
      local known = call("IsTitleKnown", i)
      if known == 1 or known == true then add(strtrim((call("GetTitleName", i) or "")), i) end
    end
    return rows, y
  end
  local function refreshStats()
    levelText:SetText(CF.LevelLine(UnitLevel("player"), UnitClass("player")))
    if not rightHost:IsShown() then return end
    for i, t in ipairs(tabs) do setShown(t.sel, i == pane) end
    local titles = call("PlayerTitleDropDown_IsTitleAvailable")
    local noTitles = titles ~= nil and not titles
    tabs[2].icon:SetDesaturated(noTitles and true or false)
    if noTitles and pane == 2 then pane = 1 end
    statList:SetActive(pane == 1); titleList:SetActive(pane == 2)
    if pane == 1 then statList:SetRows(CF.Flatten(CF.StatSections())) else titleList:SetRows(titleRows()) end
  end
  function CF.SetPane(i) pane = i; refreshStats() end
  CF.Refresh = refreshStats

  -- collapse: the arrow button on the left pane's top right folds the right pane away (window 398 wide). One button for every tab (Character, Pet, Reputation,
  -- Skills, PvP); the choice is remembered (characterCollapsed), the triangle points left while the pane is open and right while it is folded away.
  local pull = CreateFrame("Button", "AFUI_CharacterCollapse", win)
  -- the capture's collapse button (f0017): a 20 x 19 unit plate - 1.4 unit olive-gold border (brighter on top), near-black face - centred 377 / 42 units in
  -- from the window's top left, with a small gold triangle (6 x 9.6 units). Art: the pull-side atlas sprite (below).
  local K = CF.COLLAPSE
  pull:SetWidth(K.w); pull:SetHeight(K.h); pull:SetPoint("CENTER", cf, "TOPLEFT", K.cx, K.cy)
  pull:SetFrameLevel(base + 14)
  pull:RegisterForClicks("LeftButtonUp")
  do -- Forever's boxed arrow button (the dropdown arrow button: dark square, bronze rim, gold triangle) with the triangle pointing left while the stats are open (click to fold
    -- them away) and right while they are folded (click to open). The box and its drop shadow never move: tools/collapse-arrow.mjs cuts the sprite's triangle out and redraws only
    -- the triangle turned, one file per direction and state (turning the whole sprite put the shadow on the other side and looked like another button).
    local arrow = pull:CreateTexture(nil, "ARTWORK"); arrow:SetAllPoints(pull)
    arrow:SetTexCoord(0, 27 / 32, 0, 27 / 32) -- the 27 px sprite sits at the top left of a 32 px file
    local ART = { -- written out in full: the media check reads every path literal
      Left = { Normal = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\UI-CollapseArrow-Left-Normal", Hover = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\UI-CollapseArrow-Left-Hover",
        Pressed = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\UI-CollapseArrow-Left-Pressed" },
      Right = { Normal = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\UI-CollapseArrow-Right-Normal", Hover = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\UI-CollapseArrow-Right-Hover",
        Pressed = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\UI-CollapseArrow-Right-Pressed" } }
    function pull.SetPointing(left)
      local state = pull.pressed and "Pressed" or (pull.hot and "Hover" or "Normal")
      arrow:SetTexture(ART[left and "Left" or "Right"][state])
    end
    pull.SetPointing(true)
    local function press(down) pull.pressed = down; pull.SetPointing(not pull.pointRight) end
    pull:HookScript("OnMouseDown", function() press(true) end)
    pull:HookScript("OnMouseUp", function() press(false) end)
    pull:HookScript("OnEnter", function() pull.hot = true; pull.SetPointing(not pull.pointRight) end)
    pull:HookScript("OnLeave", function() pull.hot = false; press(false) end)
  end
  local function petShown() local f = _G.PetPaperDollFrame; return f ~= nil and f:IsShown() end

  local sideTabs = {}
  local function layoutWindow()
    local collapsed = isCollapsed()
    local w = CF.Size(collapsed)
    local O = AFUI.WinKit and AFUI.WinKit.ORIGIN or { x = 17, y = -116 }
    AFUI.PanelAttrs(cf, { width = w, height = H, xoffset = O.x, yoffset = O.y }) -- UIPanelWindows has 353 x 424 and the old art's -16 margin; Forever's windows all start at 17 / 114 units
    AFUI.RunOutOfCombat(function()
      if cf:GetWidth() == w and cf:GetHeight() == H then return end -- already that size: leave the panel manager alone
      cf:SetWidth(w); cf:SetHeight(H); cf:SetHitRectInsets(0, 0, 0, 0)
      if UpdateUIPanelPositions then UpdateUIPanelPositions(cf) end
    end)
    for k, c in pairs(chromes) do setShown(c, k == w) end
    chrome(w):Show()
    rock:SetTexCoord(0, (w - 4) / 512, 0, (H - 23) / 512) -- the 512 px file repeats (no tiling API on 2.4.3)
    local CP = AFUI.CharacterPanes
    setShown(rock, not pd:IsShown() and not (CP and CP.Active()))
    if tabTitle then -- white name on the paper doll, the tab's gold name elsewhere
      local on = pd:IsShown()
      nameText:SetAlpha(on and 1 or 0); setShown(tabTitle, not on)
      for _, def in ipairs(SIDE_TABS) do local f = _G[def[1]]; if f and f ~= pd and f:IsShown() then tabTitle:SetText(def[2]) end end
    end
    classIcon()
    setShown(pull, pd:IsShown() or petShown() or (CP and CP.Active()) or false)
    if CP then CP.Layout() end
    setShown(rightHost, not collapsed)
    pull.pointRight = collapsed and true or false -- the triangle points right while the right pane is folded away
    pull.SetPointing(not collapsed)
    refreshStats()
  end
  pull:SetScript("OnClick", function()
    if AztraForeverUICharDB then AztraForeverUICharDB.characterCollapsed = not AztraForeverUICharDB.characterCollapsed end
    layoutWindow()
  end)

  -- mode tabs on the right edge (55 px tall, 2 px apart, from the window's top right + (0, -30)); the client's own ToggleCharacter does the work
  local function tabIcon(t, spec)
    if spec == "portrait" then AFUI.PortraitUnit(t, "player"); t:SetTexCoord(0.03, 0.97, 0.03, 0.97)
    elseif spec == "pet" then AFUI.PortraitUnit(t, "pet"); t:SetTexCoord(0.03, 0.97, 0.03, 0.97)
    elseif spec == "pvp" then
      t:SetTexture(PLAIN .. (UnitFactionGroup("player") == "Alliance" and "INV_SideTab_Honor_Alliance_c60" or "INV_SideTab_Honor_Horde_c60")); t:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    else t:SetTexture(spec); t:SetTexCoord(0.06, 0.94, 0.06, 0.94) end -- the side tab icons are drawn for the plate; their own bevel is cropped
  end
  for i, def in ipairs(SIDE_TABS) do
    local b = CreateFrame("Button", "AFUI_CharacterModeTab" .. i, cf)
    b:SetWidth(TAB_W); b:SetHeight(TAB_H); b:SetFrameLevel(base + 6)
    local bg = atlasTexture(b, "BACKGROUND", "common-sidetab-c60"); bg:SetPoint("CENTER")
    local ic = AFUI.WinKit.tabIcon(b, "ARTWORK") -- the capture: the art fills the chamfered plate, clipped to its cut corners
    b.icon, b.spec = ic, def[3]
    local sel = atlasTexture(b, "OVERLAY", "common-sidetab-selected-c60"); sel:SetPoint("CENTER")
    local hl = atlasTexture(b, "HIGHLIGHT", "common-sidetab-hover-c60"); hl:SetPoint("CENTER")
    b.sel = sel
    b:SetScript("OnClick", function()
      local f = _G[def[1]]
      if ToggleCharacter and f and not f:IsShown() then ToggleCharacter(def[1], true) end -- 2.4.3's ToggleCharacter closes the window on the open tab
    end)
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(def[2]); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sideTabs[i] = b
  end
  local function layoutTabs()
    local prev
    for i, def in ipairs(SIDE_TABS) do
      local b = sideTabs[i]
      local frame = _G[def[1]]
      local hasPet = AFUI.PetPane and AFUI.PetPane.HasPetTab() or (HasPetUI and HasPetUI() and true) -- classes without pets never get the Pet tab
      local visible = frame ~= nil and (not def.needsPet or hasPet or (frame:IsShown()))
      setShown(b, visible)
      if visible then
        setShown(b.sel, frame:IsShown())
        b:ClearAllPoints()
        if prev then b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -TAB_GAP) else b:SetPoint("TOPLEFT", cf, "TOPRIGHT", 0, -30) end
        prev = b
      end
    end
  end

  -- sub-frames of the other tabs keep Blizzard's layout (their old art is hidden); they sit in the left part of the window
  local function fitSubFrames()
    for _, n in ipairs({ "PetPaperDollFrame" }) do -- Reputation / Skills / PvP are drawn by CharacterPanes.lua
      local f = _G[n]
      if f and f.SetScale then f:SetScale(0.9) end
    end
  end
  fitSubFrames()

  local function iconTabs()
    classIcon()
    SetPortraitTexture(tabs[1].icon, "player")
    for i, b in ipairs(sideTabs) do tabIcon(b.icon, b.spec) end
  end
  local function refreshAll()
    layoutSlots(); updateSlots(); layoutTabs(); iconTabs()
    refreshStats()
  end
  pd:HookScript("OnShow", function() layoutWindow(); refreshAll() end)
  pd:HookScript("OnHide", function() layoutWindow(); layoutTabs() end)
  cf:HookScript("OnShow", function() layoutWindow(); refreshAll() end)
  -- Events, not a timer: what the window shows is refreshed by the events the client's own paper doll uses (2.4.3 PaperDollFrame.lua:72-88,
  -- 2.5.3 Interface_TBC/FrameXML/PaperDollFrame.lua:68-84), for the player only. A burst (UNIT_AURA in combat) is coalesced: a one-shot
  -- throttled OnUpdate does the work once, then removes itself, so nothing runs while idle.
  local pump, todo, elapsed = CreateFrame("Frame", "AFUI_CharacterPump", cf), {}, 0
  local function later(what)
    if not cf:IsShown() then return end -- OnShow refreshes everything
    todo[what] = true
    if pump:GetScript("OnUpdate") then return end
    elapsed = 0
    pump:SetScript("OnUpdate", function(self, dt)
      elapsed = elapsed + dt
      if elapsed < 0.2 then return end
      self:SetScript("OnUpdate", nil)
      local t = todo; todo = {}
      if not cf:IsShown() then return end
      if t.slots then updateSlots() end
      if t.tabs then layoutTabs() end
      if t.stats then refreshStats() end
    end)
  end
  local STAT_EVENTS = { UNIT_STATS = 1, UNIT_LEVEL = 1, UNIT_AURA = 1, UNIT_RESISTANCES = 1, UNIT_DAMAGE = 1, UNIT_RANGEDDAMAGE = 1, UNIT_ATTACK_SPEED = 1,
    UNIT_ATTACK_POWER = 1, UNIT_RANGED_ATTACK_POWER = 1, UNIT_ATTACK = 1, UNIT_MAXHEALTH = 1, UNIT_INVENTORY_CHANGED = 1 }
  for e in pairs(STAT_EVENTS) do
    AFUI.On(e, function(_, unit)
      if unit ~= "player" then return end
      later("stats"); if e == "UNIT_INVENTORY_CHANGED" then later("slots") end
    end)
  end
  for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_DAMAGE_DONE_MODS", "COMBAT_RATING_UPDATE", "SKILL_LINES_CHANGED" }) do
    AFUI.On(e, function() later("stats"); if e == "PLAYER_EQUIPMENT_CHANGED" then later("slots") end end)
  end
  AFUI.On("UNIT_PET", function(_, unit) if unit == "player" then later("tabs") end end)
  AFUI.On("PET_UI_UPDATE", function() later("tabs") end)
  for _, def in ipairs(SIDE_TABS) do -- the tab marks follow whichever sub-frame is showing (the paper doll's own hooks are above)
    local sub = _G[def[1]]
    if sub ~= pd and sub and sub.HookScript then
      sub:HookScript("OnShow", function() layoutWindow(); layoutTabs() end); sub:HookScript("OnHide", function() layoutWindow(); layoutTabs() end)
    end
  end
  AFUI.On("UNIT_PORTRAIT_UPDATE", function() if cf:IsShown() then iconTabs() end end)
  if AFUI.CharacterPanes then -- the Reputation / Skills / PvP panes (CharacterPanes.lua)
    AFUI.CharacterPanes.Setup({ cf = cf, win = win, base = base, atlasTexture = atlasTexture, nineSlice = nineSlice, newList = newList, setShown = setShown,
      LEFT_W = LEFT_W, RIGHT_W = RIGHT_W, TOP = TOP, H = H, Relayout = function() layoutWindow() end, IsCollapsed = isCollapsed })
  end
  layoutWindow(); refreshAll()
end

AFUI.SetupCharacterFrame = setup
AFUI.RegisterModule("CharacterFrame", { OnLogin = function() AFUI.RunOutOfCombat(setup) end })
