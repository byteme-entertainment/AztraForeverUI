-- The debuffs YOU put on an enemy, in a row above its nameplate. Forever's aura item is 25 u scaled by the plate size (Small 0.75, nameplates.md),
-- drawn here as the target frame's icon: UI-Debuff-Overlays border coloured by debuff type, stack count bottom right, a tiny sweep, the time left on the icon.
-- 2.5.3: UnitAura(unit, i, "HARMFUL") answers (name, icon, count, debuffType, duration, expirationTime, source ...) (TargetFrame.lua of 2.5.3 reads
-- UnitDebuff the same way); a debuff is ours when its source is the player or the player's vehicle. 2.4.3 only gives your own debuffs a duration.
-- Everything is our own non-protected frames: nothing here touches Blizzard's (protected) plates, so it works in combat. Icons never take the mouse.
AFUI = AFUI or {}
local IS_243 = AFUI.IS_243
local A = { skins = {} }
AFUI.NameplateAuras = A

local SIZE, GAP, MAX, PER_ROW, ROW_GAP = 19, 2, 8, 5, 2
A.SIZE, A.GAP, A.MAX, A.PER_ROW = SIZE, GAP, MAX, PER_ROW
local THROTTLE, TICK = 0.1, 0.25

-- /afui npdebuffs; on by default
function A.Enabled() return not (AztraForeverUIDB and AztraForeverUIDB.npDebuffs == false) end

-- Your debuffs on `unit`, expiring first (permanent ones last), at most MAX.
function A.Collect(unit)
  local list = {}
  for i = 1, 40 do
    local name, icon, count, duration, expires, dtype, mine
    if IS_243 then
      name, icon, count, duration, expires, dtype = AFUI.UnitAura(unit, i, "HARMFUL")
      mine = duration ~= nil
    else
      local src
      name, icon, count, dtype, duration, expires, src = UnitAura(unit, i, "HARMFUL")
      mine = src == "player" or src == "vehicle"
    end
    if not name then break end
    if mine then list[#list + 1] = { icon = icon, count = count, duration = duration, expires = expires, dtype = dtype, i = i } end
  end
  local now = GetTime()
  local function left(a) return (a.duration and a.duration > 0 and a.expires) and a.expires - now or math.huge end
  table.sort(list, function(a, b)
    local la, lb = left(a), left(b)
    if la ~= lb then return la < lb end
    return a.i < b.i
  end)
  for i = #list, MAX + 1, -1 do list[i] = nil end
  return list
end

local function timeText(t)
  if t >= 3600 then return math.floor(t / 3600) .. "h" end
  if t >= 60 then return math.floor(t / 60) .. "m" end
  return tostring(math.max(math.floor(t + 0.5), 0))
end
A.TimeText = timeText

local function newIcon(row)
  local b = CreateFrame("Frame", nil, row)
  b:EnableMouse(false)
  b:SetWidth(SIZE); b:SetHeight(SIZE)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(b)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.cd = CreateFrame("Cooldown", nil, b); b.cd:SetAllPoints(b)
  if b.cd.SetReverse then b.cd:SetReverse(true) end
  b.cd:EnableMouse(false)
  b.border = b:CreateTexture(nil, "OVERLAY")
  b.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
  b.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
  b.border:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1); b.border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, 0)
  b.time = b:CreateFontString(nil, "OVERLAY")
  b.time:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE"); b.time:SetPoint("TOP", b, "TOP", 0, -1)
  return b
end

-- One row per plate skin, a child of the plate's own frame (so it scales and fades with it); icons are pooled in row.icons.
function A.Attach(s, anchor)
  local row = CreateFrame("Frame", nil, s.frame)
  row:EnableMouse(false)
  row:SetWidth(PER_ROW * (SIZE + GAP) - GAP); row:SetHeight(SIZE)
  row.icons, row.shown = {}, 0
  s.auras = row
  A.Place(s)
  A.skins[#A.skins + 1] = s
  return row
end

-- "Your debuffs sit": above the bar (default, rows grow upward) or below the cast bar (rows grow downward). The row hangs outward from a fixed edge of the plate,
-- so showing, hiding or adding a row never moves the health bar, the cast bar or the name.
function A.Place(s)
  local row = s.auras
  row.below = AFUI.GetSetting("nameplateAuraSide", "above") == "below"
  row:ClearAllPoints()
  if row.below then row:SetPoint("TOP", s.castBox, "BOTTOM", 0, -2) else row:SetPoint("BOTTOM", s.fbg, "TOP", 0, 4) end
  if s.auraUnit and row.shown > 0 then A.Update(s, s.auraUnit) end
end
function A.PlaceAll() for _, s in ipairs(A.skins) do A.Place(s) end end

local function refreshTimes(row)
  local now = GetTime()
  for i = 1, row.shown do
    local b = row.icons[i]
    if b.expires and b.duration and b.duration > 0 then
      local t = b.expires - now
      b.time:SetText(t > 0 and timeText(t) or "")
    else b.time:SetText("") end
  end
end

-- Lays the list out: rows of PER_ROW, each centred, the next row above.
function A.Update(s, unit)
  local row = s.auras
  if not row then return end
  s.auraT, s.auraDirty = GetTime(), false
  if unit then s.auraUnit = unit end
  local list = (unit and A.Enabled()) and A.Collect(unit) or {}
  local n = #list
  for i = 1, n do
    local b = row.icons[i]
    if not b then b = newIcon(row); row.icons[i] = b end
    local a = list[i]
    b.icon:SetTexture(a.icon)
    b.count:SetText(a.count and a.count > 1 and a.count or "")
    b.expires, b.duration = a.expires, a.duration
    if a.duration and a.duration > 0 and a.expires then AFUI.CooldownSet(b.cd, a.expires - a.duration, a.duration); b.cd:Show() else b.cd:Hide() end
    local c = DebuffTypeColor and (DebuffTypeColor[a.dtype or "none"] or DebuffTypeColor.none) or { r = 0.8, g = 0, b = 0 }
    b.border:SetVertexColor(c.r, c.g, c.b)
    local r, col = math.floor((i - 1) / PER_ROW), (i - 1) % PER_ROW
    local inRow = math.min(PER_ROW, n - r * PER_ROW)
    b:ClearAllPoints()
    local x = (PER_ROW - inRow) * (SIZE + GAP) / 2 + col * (SIZE + GAP)
    if row.below then b:SetPoint("TOPLEFT", row, "TOPLEFT", x, -r * (SIZE + ROW_GAP)) else b:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, r * (SIZE + ROW_GAP)) end
    b:Show()
  end
  for i = n + 1, row.shown do row.icons[i]:Hide() end
  row.shown = n
  refreshTimes(row)
  if n > 0 then row:Show() else row:Hide() end
end

-- UNIT_AURA for one unit: at most one rebuild per THROTTLE, the rest is flushed by the ticker.
local pending = {}
function A.OnAura(s, unit)
  if not s or not s.auras then return end
  if GetTime() - (s.auraT or -1) >= THROTTLE then A.Update(s, unit)
  else s.auraDirty, s.auraUnit = true, unit; pending[s] = true end
end

function A.Clear(s)
  if not s.auras then return end
  pending[s] = nil
  A.Update(s, nil)
end

function A.Setup()
  local t = CreateFrame("Frame")
  local acc = 0
  t:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < THROTTLE then return end
    for s in pairs(pending) do
      if s.auraDirty and s.auras and s.auraUnit then A.Update(s, s.auraUnit) end
      pending[s] = nil
    end
    if acc >= TICK then
      acc = 0
      for _, s in ipairs(A.skins) do
        if s.auras.shown > 0 and s.auras:IsShown() then refreshTimes(s.auras) end
      end
    end
  end)
end

-- /afui npdebuffs
function A.Toggle()
  AztraForeverUIDB = AztraForeverUIDB or { layouts = {} }
  AztraForeverUIDB.npDebuffs = not A.Enabled()
  AFUI.Print("Aztra's Forever UI: nameplate debuffs " .. (A.Enabled() and "on" or "off"))
  for _, s in ipairs(A.skins) do if s.auraUnit and s.activeAura then A.Update(s, s.auraUnit) end end
end

AFUI.RegisterModule("NameplateAuras", { OnLogin = A.Setup })
