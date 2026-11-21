-- Floating damage and healing numbers of our own (setting "combatText", Settings > General, default OFF). They replace the client's scrolling combat text
-- while on: the two CVars floatingCombatTextCombatDamage / ...Healing are turned off (the player's values are kept and put back when this is switched off),
-- and the numbers are drawn here from the combat log (COMBAT_LOG_EVENT_UNFILTERED, read only, nothing protected is touched):
--   outgoing  your (and your pet's) damage and healing, rising on the right of the screen centre
--   incoming  damage you take and heals you receive, rising on the left
-- Look (BarGlow's): numbers with a dark outline; a crit is larger, pops in (1.6x down to 1x in 0.18 s), holds longer and gets a white-hot additive flash
-- behind it, drawn from the same UI-BarGlow sprite, that fades in 0.4 s. All motion is ease-out cubic.
-- Pooled: POOL frames made once (a text, a flash), one shared driver frame whose OnUpdate runs only while a number is on screen; an event takes a free
-- frame, or recycles the oldest when all are busy. No table is made per event.
--   AFUI.CombatText.Classify(sub, src, dst, me, pet, ...) -> lane ("out" | "in"), heal, amount, crit   (nil when the event shows nothing)
--   AFUI.CombatText.Spawn(lane, heal, amount, crit)         puts one number on screen
--   AFUI.CombatText.Debug(lane, heal, amount, crit, t)      draws one number frozen at time t (previews), no driver
AFUI = AFUI or {}
local C = {}
AFUI.CombatText = C

local ART = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\UI-BarGlow"
local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local POOL = 24
C.POOL = POOL
C.LANES = { out = { x = 110, y = 90 }, ["in"] = { x = -150, y = 40 } }
C.SLOTS = { -36, -18, 0, 18, 36 } -- a number's sideways offset cycles through these so neighbours do not stack
C.COLORS = { dmgOut = { 1, 0.85, 0.35 }, dmgIn = { 1, 0.3, 0.25 }, heal = { 0.3, 1, 0.4 } }
C.HOT = { 1, 0.93, 0.8 }
C.NORMAL = { dur = 0.9, rise = 55, size = 18 }
C.CRIT = { dur = 1.3, rise = 70, size = 28, pop = 0.18, flash = 0.4 }
C.CVARS = { "floatingCombatTextCombatDamage", "floatingCombatTextCombatHealing" }

local DAMAGE = { SWING_DAMAGE = 1, RANGE_DAMAGE = 4, SPELL_DAMAGE = 4, SPELL_PERIODIC_DAMAGE = 4, DAMAGE_SHIELD = 4 } -- index of the amount among the suffix params
local HEAL = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }

-- Sorts one combat log event: whose number it is, and how big. `...` are the suffix params (CLEU index 12 on). Damage layouts: swing amount 1 / crit 7,
-- spell and range amount 4 / crit 10; a heal has amount 4, overhealing 5, crit 7 (only what actually healed counts).
function C.Classify(sub, src, dst, me, pet, ...)
  local at = DAMAGE[sub]
  local heal = HEAL[sub]
  if not (at or heal) then return end
  local lane
  if dst and dst == me then lane = "in"
  elseif src and (src == me or (pet and src == pet)) then lane = "out"
  else return end
  local amount, crit
  if heal then
    amount = (select(4, ...) or 0) - (select(5, ...) or 0)
    crit = select(7, ...)
  else
    amount = select(at, ...)
    crit = select(at == 1 and 7 or 10, ...)
  end
  if type(amount) ~= "number" or amount <= 0 then return end
  return lane, heal and true or false, amount, (crit and crit ~= 0) and true or false
end

function C.Short(n) -- 1234 -> "1234", 12345 -> "12.3k"
  if n >= 100000 then return string.format("%dk", n / 1000) end
  if n >= 10000 then return string.format("%.1fk", n / 1000) end
  return string.format("%d", n)
end

local function ease(p) p = 1 - p; return 1 - p * p * p end

local items, nextSlot, cursor = {}, 0, 0
local active = 0
local driver = CreateFrame("Frame")
driver:Hide()

local function item(i)
  local it = items[i]
  if it then return it end
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetFrameStrata("HIGH"); f:SetWidth(120); f:SetHeight(30); f:EnableMouse(false)
  f.flash = f:CreateTexture(nil, "BACKGROUND")
  f.flash:SetTexture(ART); f.flash:SetTexCoord(0, 1, 0, 0.5); f.flash:SetBlendMode("ADD")
  f.flash:SetPoint("CENTER", f, "CENTER", 0, 0); f.flash:SetWidth(120); f.flash:SetHeight(26)
  f.text = f:CreateFontString(nil, "OVERLAY")
  f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.text:SetShadowColor(0, 0, 0, 1); f.text:SetShadowOffset(1, -1)
  f:Hide()
  it = { f = f, live = false }
  items[i] = it
  return it
end

-- draws `it` at age t
local function render(it, t)
  local p = it.m
  local f = it.f
  local k = t / p.dur
  if k > 1 then k = 1 end
  local s = 1
  if p.pop and t < p.pop then local q = 1 - t / p.pop; s = 1 + 0.6 * q * q end
  f:SetScale(s)
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", it.x / s, (it.y + p.rise * ease(k)) / s) -- the scale multiplies the offsets: divided back so the pop grows in place
  local a = 1
  if k > 0.55 then a = 1 - (k - 0.55) / 0.45 end
  f:SetAlpha(a)
  if p.pop then
    if t < p.flash then
      local q = 1 - t / p.flash
      f.flash:SetAlpha(0.9 * q * q); f.flash:Show()
    else f.flash:Hide() end
  end
end

local function stop(it)
  if not it.live then return end
  it.live = false; it.f:Hide()
  active = active - 1
  if active <= 0 then active = 0; driver:Hide() end
end

driver:SetScript("OnUpdate", function(_, dt)
  for i = 1, POOL do
    local it = items[i]
    if it and it.live then
      it.t = it.t + dt
      if it.t >= it.m.dur then stop(it) else render(it, it.t) end
    end
  end
end)

local function setup(it, lane, heal, amount, crit)
  local m = crit and C.CRIT or C.NORMAL
  local col = heal and C.COLORS.heal or (lane == "in" and C.COLORS.dmgIn or C.COLORS.dmgOut)
  local f = it.f
  nextSlot = nextSlot % #C.SLOTS + 1
  local l = C.LANES[lane]
  it.m, it.t, it.x, it.y = m, 0, l.x + C.SLOTS[nextSlot], l.y
  f.text:SetFont(FONT, m.size, "OUTLINE")
  f.text:SetText((heal and "+" or "") .. C.Short(amount) .. (crit and "!" or ""))
  f.text:SetTextColor(col[1], col[2], col[3])
  f.flash:SetVertexColor(crit and C.HOT[1] or col[1], crit and C.HOT[2] or col[2], crit and C.HOT[3] or col[3])
  if not crit then f.flash:Hide() end
  f:SetWidth(40 + #f.text:GetText() * m.size * 0.6); f.flash:SetWidth(f:GetWidth())
  f.flash:SetHeight(m.size + 8)
end

function C.Spawn(lane, heal, amount, crit)
  local it
  for i = 1, POOL do -- a free frame, else the oldest (round robin)
    local c = item(i)
    if not c.live then it = c; break end
  end
  if not it then cursor = cursor % POOL + 1; it = item(cursor); stop(it) end
  setup(it, lane, heal, amount, crit)
  it.live = true; active = active + 1
  render(it, 0); it.f:Show(); driver:Show()
end

local dbg = 0
function C.Debug(lane, heal, amount, crit, t, dx)
  dbg = dbg % POOL + 1
  local it = item(dbg)
  setup(it, lane, heal, amount, crit)
  it.x = C.LANES[lane].x + (dx or 0)
  it.live = false; render(it, t); it.f:Show()
end

function C.Active() return active end

---------------------------------------------------------------- the client's own numbers
-- On: turn the client's damage / healing text off (a copy would be shown twice). Off: put back what the player had. The values live in the character
-- db (combatTextCVars) so a /reload or a crash in between still restores them.
local function cvarGet(n) local ok, v = pcall(_G.GetCVar, n); if ok then return v end end
function C.SyncCVars(on)
  if type(_G.GetCVar) ~= "function" or type(_G.SetCVar) ~= "function" then return end
  local db = _G.AztraForeverUICharDB
  if type(db) ~= "table" then return end
  if on then
    db.combatTextCVars = db.combatTextCVars or {}
    for _, n in ipairs(C.CVARS) do
      local v = cvarGet(n)
      if v ~= nil then
        if db.combatTextCVars[n] == nil then db.combatTextCVars[n] = v end
        pcall(_G.SetCVar, n, "0")
      end
    end
  elseif db.combatTextCVars then
    for n, v in pairs(db.combatTextCVars) do pcall(_G.SetCVar, n, v) end
    db.combatTextCVars = nil
  end
end

---------------------------------------------------------------- wiring
local events = CreateFrame("Frame")
function C.OnLog(_, sub, _, src, _, _, _, dst, _, _, _, ...)
  local lane, heal, amount, crit = C.Classify(sub, src, dst, UnitGUID("player"), UnitGUID("pet"), ...)
  if lane then C.Spawn(lane, heal, amount, crit) end
end
events:SetScript("OnEvent", function(_, _, ...)
  if _G.CombatLogGetCurrentEventInfo then C.OnLog(CombatLogGetCurrentEventInfo())
  else C.OnLog(select(1, ...), select(2, ...), nil, select(3, ...), select(4, ...), select(5, ...), nil, select(6, ...), select(7, ...), select(8, ...), nil, select(9, ...)) end -- 2.4.3: no hideCaster / raid flags
end)

function C.Enabled() return AFUI.GetSetting("combatText", false) == true end

function C.Apply()
  local on = C.Enabled()
  if on then events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") else events:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED"); for i = 1, POOL do if items[i] then stop(items[i]) end end end
  C.SyncCVars(on)
  C.on = on
end

AFUI.OnSettingChanged("combatText", C.Apply)
AFUI.RegisterModule("CombatText", { OnLogin = C.Apply })
