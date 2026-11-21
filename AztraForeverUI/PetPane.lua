-- Forever-look Pet tab of the Character window (hunters, warlocks and any class the client gives a pet UI): the same two panes as the other tabs
-- (CharacterPanes.lua hosts it: stone, divider, the side pane's rows). The client's own PetPaperDollFrame stays the tab state (ToggleCharacter shows it).
-- Left pane: name plate with the pet's portrait, the model, level / family, happiness and its damage bonus (hunter pets), loyalty and training points
-- if the client has them, then experience, health and power bars. Right pane: attributes, melee (attack power, damage, armor) and the six resistances.
-- Pet API (TBC 2.4.3 / 2.5.3): UnitName / UnitLevel / UnitCreatureFamily("pet"), GetPetHappiness() -> happiness (1 unhappy, 2 content, 3 happy),
-- damagePercentage, loyaltyRate; GetPetExperience() -> current, max; GetPetTrainingPoints() -> total, spent; GetPetLoyalty() (loyalty name, where present);
-- UnitStat("pet", i) -> stat, effective, posBuff, negBuff; UnitArmor / UnitAttackPower / UnitDamage / UnitResistance("pet", ...). Every read is guarded:
-- a missing function or a nil answer leaves its row out, nothing errors.
AFUI = AFUI or {}
local P = {}
AFUI.PetPane = P

---------------------------------------------------------------- pure logic (specs: tests/lua/petpane_spec.lua)
P.PET_CLASSES = { HUNTER = true, WARLOCK = true }

-- Does the Character window get a Pet tab? Classes with pets, and anyone the client gives a pet UI (HasPetUI), but only while there is a pet.
function P.HasPetTab()
  local has = type(_G.HasPetUI) == "function" and _G.HasPetUI() and true or false
  if has then return true end
  local token = type(_G.UnitClass) == "function" and select(2, _G.UnitClass("player"))
  return P.PET_CLASSES[token or ""] == true and type(_G.UnitExists) == "function" and _G.UnitExists("pet") and true or false
end

function P.IsHunter() local t = type(_G.UnitClass) == "function" and select(2, _G.UnitClass("player")); return t == "HUNTER" end

-- 1250 -> "1,250"
function P.Commas(n)
  local s = tostring(math.floor(math.abs(n or 0)))
  s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (n or 0) < 0 and ("-" .. s) or s
end

-- The happy / content / unhappy face of the client's UI-PetHappiness sheet (PetPaperDollFrame.lua).
P.FACES = { [1] = { 0.375, 0.5625, 0, 0.359375 }, [2] = { 0.1875, 0.375, 0, 0.359375 }, [3] = { 0, 0.1875, 0, 0.359375 } }
P.HAPPINESS = {
  [1] = { text = "Unhappy", color = { 1, 0.2, 0.2 } },
  [2] = { text = "Content", color = { 1, 0.82, 0 } },
  [3] = { text = "Happy", color = { 0.2, 1, 0.2 } },
}
function P.HappinessInfo(happiness, damage, rate)
  local h = P.HAPPINESS[happiness]
  if not h then return nil end
  local text = _G["PET_HAPPINESS" .. tostring(happiness)] or h.text
  local out = { text = text, color = h.color, face = P.FACES[happiness] }
  if type(damage) == "number" then out.damage = string.format("%d%%", damage) end
  if type(rate) == "number" and rate ~= 0 then out.trend = rate > 0 and "Gaining loyalty" or "Losing loyalty" end
  return out
end

-- Stat value with the client's colours: green when buffs raise it, red when debuffs lower it.
function P.StatValue(stat, effective, pos, neg)
  local v = effective or stat
  if type(v) ~= "number" then return nil end
  local net = (pos or 0) + (neg or 0)
  local color = net > 0 and { 0.1, 1, 0.1 } or net < 0 and { 1, 0.1, 0.1 } or { 1, 1, 1 }
  return tostring(math.floor(v + 0.5)), color
end

P.STAT_NAMES = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
P.RESIST_NAMES = { "Holy Resistance", "Fire Resistance", "Nature Resistance", "Frost Resistance", "Shadow Resistance", "Arcane Resistance" }
local function statName(i) return _G["SPELL_STAT" .. i .. "_NAME"] or P.STAT_NAMES[i] end
local function resistName(i) return _G["RESISTANCE" .. i .. "_NAME"] or P.RESIST_NAMES[i] end

-- "Level 70 Wolf"
function P.LevelLine(level, family)
  local s = "Level " .. tostring(level or "?")
  if family and family ~= "" then s = s .. " " .. family end
  return s
end

function P.TrainingText(total, spent)
  if type(total) ~= "number" then return nil end
  return "Training Points: |cffffffff" .. (total - (spent or 0)) .. "|r / " .. total
end

function P.XPText(cur, max)
  if type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
  return P.Commas(cur) .. " / " .. P.Commas(max)
end

local function call(name, ...)
  local f = _G[name]
  if type(f) ~= "function" then return end
  local r = { pcall(f, ...) }
  if not r[1] then return end
  return unpack(r, 2)
end

-- Everything the pane shows, as plain data (nil fields are simply not drawn).
function P.Read()
  local d = {}
  d.exists = call("UnitExists", "pet") and true or false
  d.name = call("UnitName", "pet")
  d.level = call("UnitLevel", "pet")
  d.family = call("UnitCreatureFamily", "pet")
  d.hunter = P.IsHunter()
  if d.hunter then
    local h, dmg, rate = call("GetPetHappiness")
    d.happiness = P.HappinessInfo(h, dmg, rate)
    d.loyalty = call("GetPetLoyalty")
    if type(d.loyalty) ~= "string" or d.loyalty == "" then d.loyalty = nil end
    local total, spent = call("GetPetTrainingPoints")
    d.training = P.TrainingText(total, spent)
    d.xp = { call("GetPetExperience") }
  end
  d.hp, d.hpMax = call("UnitHealth", "pet"), call("UnitHealthMax", "pet")
  local ptype = call("UnitPowerType", "pet")
  d.powerType = ptype
  if AFUI.UnitPower then d.power, d.powerMax = call("UnitPower", "pet"), call("UnitPowerMax", "pet") end
  if d.power == nil and type(_G.UnitMana) == "function" then d.power, d.powerMax = call("UnitMana", "pet"), call("UnitManaMax", "pet") end
  d.stats = {}
  for i = 1, 5 do
    local stat, eff, pos, neg = call("UnitStat", "pet", i)
    local text, color = P.StatValue(stat, eff, pos, neg)
    if text then d.stats[#d.stats + 1] = { label = statName(i), value = text, vc = color } end
  end
  d.melee = {}
  local base, pos, neg = call("UnitAttackPower", "pet")
  if type(base) == "number" then
    local text, color = P.StatValue(nil, base + (pos or 0) + (neg or 0), pos, neg)
    d.melee[#d.melee + 1] = { label = "Attack Power", value = text, vc = color }
  end
  local lo, hi = call("UnitDamage", "pet")
  if type(lo) == "number" and type(hi) == "number" then
    d.melee[#d.melee + 1] = { label = "Damage", value = math.floor(lo + 0.5) .. " - " .. math.floor(hi + 0.5) }
  end
  local _, armor = call("UnitArmor", "pet")
  if type(armor) == "number" then d.melee[#d.melee + 1] = { label = "Armor", value = P.Commas(armor) } end
  d.resists = {}
  for i = 1, 6 do
    local _, total = call("UnitResistance", "pet", i)
    if type(total) == "number" then d.resists[#d.resists + 1] = { label = resistName(i), value = tostring(total) } end
  end
  return d
end

-- The right pane's rows (CharacterPanes' sideRows items).
function P.Items(d)
  local items = {}
  local function section(title, rows)
    if #rows == 0 then return end
    items[#items + 1] = { cat = title }
    for _, r in ipairs(rows) do items[#items + 1] = { label = r.label, value = r.value, vc = r.vc } end
  end
  section("Attributes", d.stats or {})
  section("Melee", d.melee or {})
  section("Resistances", d.resists or {})
  return items
end

---------------------------------------------------------------- the pane
-- env: pane (the tab's frame over the stone), side (CharacterPanes' side pane object), setSide(side, title, sub, color), rows(side, items, y), cf, base,
-- LEFT_W, TOP, atlasTexture, nineSlice, newBar. Returns { Refresh, Soon }.
function P.Build(env)
  local cf, pane, base, LEFT_W, TOP = env.cf, env.pane, env.base, env.LEFT_W, env.TOP
  local K = AFUI.WinKit
  local B = { }
  local function fs(parent, font, x, y, w, just)
    local f = parent:CreateFontString(nil, "ARTWORK", font)
    f:SetPoint("TOPLEFT", cf, "TOPLEFT", x, -y)
    if w then f:SetWidth(w) end
    f:SetJustifyH(just or "LEFT")
    return f
  end

  -- name plate with the portrait
  local plate = CreateFrame("Frame", nil, pane)
  plate:SetFrameLevel(base + 7); plate:SetPoint("TOPLEFT", cf, "TOPLEFT", 8, -(TOP + 40)); plate:SetWidth(LEFT_W - 16); plate:SetHeight(40)
  local bg = env.atlasTexture(plate, "BACKGROUND", "ui-character-info-title-c60"); bg:SetAllPoints(plate)
  B.portrait = plate:CreateTexture(nil, "ARTWORK"); B.portrait:SetWidth(32); B.portrait:SetHeight(32); B.portrait:SetPoint("LEFT", plate, "LEFT", 14, 0)
  B.name = plate:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge"); B.name:SetPoint("CENTER", plate, "CENTER", 0, 1)
  B.name:SetWidth(LEFT_W - 120)

  -- model box (left) and the facts (right)
  local box = CreateFrame("Frame", nil, pane)
  box:SetFrameLevel(base + 7); box:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, -(TOP + 88)); box:SetWidth(LEFT_W - 28); box:SetHeight(226)
  local back = box:CreateTexture(nil, "BACKGROUND"); back:SetAllPoints(box); AFUI.SetColor(back, 0, 0, 0, 0.45)
  local frame = env.nineSlice(box, "OVERLAY", "common-insideframe-c60", 53, 26)
  if frame.Place then frame.Place(box, 0, 0, 0, 0) end
  local okModel, model = pcall(CreateFrame, "PlayerModel", nil, box)
  if okModel and model then
    model:SetFrameLevel(base + 8); model:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6); model:SetWidth(168); model:SetHeight(214)
    B.model = model
  end
  local fx = 14 + 188
  B.level = fs(pane, "GameFontHighlightLarge", fx, TOP + 100, 170)
  B.happy = fs(pane, "GameFontNormalLarge", fx + 34, TOP + 140, 140)
  B.face = pane:CreateTexture(nil, "ARTWORK"); B.face:SetWidth(30); B.face:SetHeight(30); B.face:SetPoint("TOPLEFT", cf, "TOPLEFT", fx, -(TOP + 134))
  B.face:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
  B.damage = fs(pane, "GameFontHighlight", fx, TOP + 172, 170)
  B.trend = fs(pane, "GameFontDisable", fx, TOP + 192, 170)
  B.loyalty = fs(pane, "GameFontNormal", fx, TOP + 220, 170)
  B.training = fs(pane, "GameFontNormal", fx, TOP + 244, 170)
  B.empty = fs(pane, "GameFontDisable", 14, TOP + 190, LEFT_W - 28, "CENTER")

  -- bars: experience, health, power
  local function bar(y)
    local b = env.newBar(pane, LEFT_W - 40, 29)
    b:SetFrameLevel(base + 8); b:SetPoint("TOPLEFT", cf, "TOPLEFT", 20, -(TOP + y))
    return b
  end
  B.xp, B.hp, B.mp = bar(322), bar(358), bar(394)

  local function refresh()
    local d = P.Read()
    B.data = d
    local on = d.exists
    B.name:SetText(d.name or "")
    pcall(AFUI.PortraitUnit, B.portrait, "pet"); B.portrait:SetTexCoord(0.04, 0.96, 0.04, 0.96)
    if B.model then pcall(B.model.SetUnit, B.model, "pet") end
    B.level:SetText(on and P.LevelLine(d.level, d.family) or "")
    local h = d.happiness
    B.happy:SetText(h and h.text or ""); if h then B.happy:SetTextColor(h.color[1], h.color[2], h.color[3]); B.face:SetTexCoord(h.face[1], h.face[2], h.face[3], h.face[4]) end
    if h and h.damage then B.damage:SetText("Damage: |cffffffff" .. h.damage .. "|r") else B.damage:SetText("") end
    B.trend:SetText(h and h.trend or "")
    B.loyalty:SetText(d.loyalty and ("Loyalty: |cffffffff" .. d.loyalty .. "|r") or "")
    B.training:SetText(d.training or "")
    if h then B.face:Show() else B.face:Hide() end
    B.empty:SetText(on and "" or "You have no pet.")
    -- bars
    local xpText = d.xp and P.XPText(d.xp[1], d.xp[2])
    if xpText then B.xp:Show(); B.xp.Set(d.xp[1] / d.xp[2], 0.58, 0.27, 0.85, xpText) else B.xp:Hide() end
    if d.hpMax and d.hpMax > 0 then B.hp:Show(); B.hp.Set(d.hp / d.hpMax, 0.1, 0.85, 0.1, P.Commas(d.hp) .. " / " .. P.Commas(d.hpMax)) else B.hp:Hide() end
    if d.powerMax and d.powerMax > 0 then
      local c = _G.PowerBarColor and (_G.PowerBarColor[d.powerType or 0] or _G.PowerBarColor[0]) or { r = 0, g = 0, b = 1 }
      B.mp:Show(); B.mp.Set(d.power / d.powerMax, c.r, c.g, c.b, P.Commas(d.power) .. " / " .. P.Commas(d.powerMax))
    else B.mp:Hide() end
    -- the side pane
    if on then
      env.setSide(env.side, "Pet Stats", d.name, nil)
      env.rows(env.side, P.Items(d), 0)
    else
      env.sideEmpty(env.side, "You have no pet.")
    end
  end

  -- Events: a burst is coalesced into one refresh on the next frame (a one-shot OnUpdate that removes itself); nothing runs while idle.
  local pump, elapsed = CreateFrame("Frame", "AFUI_PetPanePump", pane), 0
  function B.Soon()
    if not cf:IsShown() or pump:GetScript("OnUpdate") then return end
    elapsed = 0
    pump:SetScript("OnUpdate", function(self, dt)
      elapsed = elapsed + dt
      if elapsed < 0.2 then return end
      self:SetScript("OnUpdate", nil)
      if cf:IsShown() and pane:IsShown() then refresh() end
    end)
  end
  B.Refresh = refresh
  for _, e in ipairs({ "UNIT_HAPPINESS", "UNIT_PET", "UNIT_PET_EXPERIENCE", "UNIT_PET_TRAINING_POINTS", "PET_UI_UPDATE", "UNIT_LEVEL", "UNIT_STATS", "UNIT_RESISTANCES",
    "UNIT_ATTACK_POWER", "UNIT_DAMAGE", "UNIT_AURA", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MANA", "UNIT_MAXMANA", "UNIT_POWER", "UNIT_FOCUS", "UNIT_PORTRAIT_UPDATE" }) do
    AFUI.On(e, function(_, unit) if unit == nil or unit == "pet" or (unit == "player" and e == "UNIT_PET") then B.Soon() end end)
  end
  P.pane = B
  return B
end
