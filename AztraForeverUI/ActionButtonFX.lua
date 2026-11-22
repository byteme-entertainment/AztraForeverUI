-- Action button effects, as retail / Forever show them: cooldown numbers, out of range / usable tints, the proc glow, and the
-- Show Hotkeys / Show Macro Names switches. Everything rides on the client's own updates (post-hooks, events, its range timer):
-- the only OnUpdate here is the cooldown number ticker, and it exists only while a cooldown with a number is running.
-- Settings (AFUI.GetSetting): cooldownNumbers, rangeTint, procGlow, showHotkeys, showMacroNames (all default true).
AFUI = AFUI or {}
local FX = {}
AFUI.FX = FX
FX.buttons = {} -- every attached button (action, pet, stance, possess)

local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local GCD_MAX = 2 -- the global cooldown is 1.5 s at most: a cooldown of 2 s or less gets no number

local function on(key)
  if key == "cooldownNumbers" and FX.external then return false end -- another addon (OmniCC) draws the numbers: ours stay off, nothing shows twice
  return AFUI.GetSetting(key) ~= false
end

---------------------------------------------------------------- pure rules (specs)
-- Remaining seconds -> text and colour. White; yellow for the last 5 s; whole seconds under a minute, then 3m, 2h, 1d (rounded up).
function FX.CooldownText(remaining)
  if type(remaining) ~= "number" or remaining ~= remaining or remaining <= 0 then return nil end
  local s = math.ceil(remaining)
  if s < 60 then
    if s <= 5 then return tostring(s), 1, 0.82, 0 end
    return tostring(s), 1, 1, 1
  end
  local m = math.ceil(s / 60)
  if m < 60 then return m .. "m", 1, 1, 1 end
  local h = math.ceil(s / 3600)
  if h < 24 then return h .. "h", 1, 1, 1 end
  return math.ceil(s / 86400) .. "d", 1, 1, 1
end

-- A real cooldown, not the global one: it has a start and lasts longer than the GCD.
function FX.IsReal(start, duration, enable)
  return type(start) == "number" and type(duration) == "number" and start > 0 and duration > GCD_MAX and enable ~= 0 and enable ~= false
end

function FX.FontSize(buttonSize) return math.max(math.floor((buttonSize or 36) * 0.4 + 0.5), 8) end

-- The icon colour of a button: out of range (red 0.8, 0.1, 0.1) over not enough resource (0.5, 0.5, 1) over unusable (0.4);
-- usable is white. rangeTint = the setting.
function FX.IconColor(outOfRange, usable, noMana, rangeTint)
  if outOfRange and rangeTint then return 0.8, 0.1, 0.1 end
  if usable then return 1, 1, 1 end
  if noMana then return 0.5, 0.5, 1 end
  return 0.4, 0.4, 0.4
end

-- A hotkey colour the client's range check chose: red = out of range (true), its light grey = in range (false), anything else = not a range answer (nil).
function FX.RangeFromColor(r, g, b)
  if r == 1 and g and g < 0.3 and b and b < 0.3 then return true end
  if r and r == g and g == b and r < 1 then return false end
end

---------------------------------------------------------------- what a button stands for
local function kindOf(name)
  if name:find("^PetActionButton") then return "pet" end
  if name:find("^StanceButton") or name:find("^ShapeshiftButton") then return "stance" end
  if name:find("^PossessButton") then return "possess" end
  return "action"
end

function FX.ActionOf(b)
  if type(_G.ActionButton_CalculateAction) == "function" and not AFUI.IS_243 then
    local ok, a = pcall(_G.ActionButton_CalculateAction, b)
    if ok and type(a) == "number" then return a end
  end
  return b.action or tonumber(b:GetAttribute("action"))
end

local function now() return GetTime() end

-- The client's number for the button's cooldown right now (start, duration, enable): GetActionCooldown for slots (items, macros, spells), the pet / form
-- calls for the others. Used when no client update was seen yet (login, a setting switched on).
function FX.ReadCooldown(b)
  local kind = b.afuiKind
  if kind == "action" then
    local a = FX.ActionOf(b)
    if a and _G.GetActionCooldown then return GetActionCooldown(a) end
  elseif kind == "pet" and _G.GetPetActionCooldown then return GetPetActionCooldown(b:GetID())
  elseif kind == "stance" and _G.GetShapeshiftFormCooldown then return GetShapeshiftFormCooldown(b:GetID()) end
end

---------------------------------------------------------------- cooldown numbers
local running, ticker, acc = {}, nil, 0
local TICK = 0.1

local function show(b, text, r, g, bl)
  local t = b.afuiFX.text
  if b.afuiShown ~= text then b.afuiShown = text; t:SetText(text) end
  t:SetTextColor(r, g, bl)
  t:Show()
end

local function stop(b)
  running[b] = nil
  b.afuiShown = nil
  if b.afuiFX then b.afuiFX.text:Hide() end
  if not next(running) and ticker then ticker:SetScript("OnUpdate", nil) end
end

local function refresh(b)
  local c = b.afuiCD
  if not (c and on("cooldownNumbers")) then return stop(b) end
  local text, r, g, bl = FX.CooldownText(c.start + c.duration - now())
  if not text then return stop(b) end
  local cd = b.afuiCooldown
  if cd and cd.IsShown and not cd:IsShown() then return stop(b) end -- the client cleared the sweep
  show(b, text, r, g, bl)
end

local function tick(_, elapsed)
  acc = acc + (elapsed or 0)
  if acc < TICK then return end
  acc = 0
  for b in pairs(running) do refresh(b) end
end

-- start / duration / enable as the client gives CooldownFrame_Set.
function FX.SetCooldown(b, start, duration, enable)
  if not b.afuiFX then return end
  if FX.IsReal(start, duration, enable) then b.afuiCD = { start = start, duration = duration } else b.afuiCD = nil end
  if not b.afuiCD or not on("cooldownNumbers") then return stop(b) end
  running[b] = true
  if ticker and not ticker:GetScript("OnUpdate") then ticker:SetScript("OnUpdate", tick) end -- only while something runs
  refresh(b)
end

function FX.IsRunning(b) return running[b] and true or false end
function FX.Ticker() return ticker end

---------------------------------------------------------------- tint
-- The client's range check answers through the hotkey colour (red when out of range, light grey when in), and the usable check
-- through ActionButton_UpdateUsable: both are hooked, nothing is polled here.
function FX.UpdateTint(b)
  if b.afuiKind ~= "action" then return end
  local icon = _G[b:GetName() .. "Icon"]
  local a = FX.ActionOf(b)
  if not (icon and a and _G.IsUsableAction and (not _G.HasAction or HasAction(a))) then return end
  local usable, noMana = IsUsableAction(a)
  icon:SetVertexColor(FX.IconColor(b.afuiOOR, usable, noMana, on("rangeTint")))
end

-- Called by the hotkey colour hook (ActionBars.lua SkinButton) with the colour the client just set.
function FX.RangeColor(b, r, g, bl)
  local oor = FX.RangeFromColor(r, g, bl)
  if oor == nil or oor == (b.afuiOOR or false) then return end
  b.afuiOOR = oor
  FX.UpdateTint(b)
end

---------------------------------------------------------------- proc glow
-- Retail's activation glow in Forever's own sprites: the white frame ring (ui-hud-actionbar-iconframe-border) tinted gold on the button, plus a larger halo of the
-- gold mouse-over ring, breathing at two speeds through AnimationGroups (2.4.3 has none: the rings just stay lit).
local function ring(parent, atlas, w, h, alpha, r, g, b)
  local t = parent:CreateTexture(nil, "OVERLAY")
  t:SetPoint("CENTER", parent, "CENTER", 0, 0)
  t:SetWidth(w); t:SetHeight(h)
  AFUI.SetAtlas(t, atlas)
  t:SetBlendMode("ADD")
  t:SetVertexColor(r, g, b)
  t:SetAlpha(alpha)
  return t
end

local function pulse(frame, from, to, duration)
  local g = frame.CreateAnimationGroup and frame:CreateAnimationGroup()
  if not g then return end
  local a = g:CreateAnimation("Alpha")
  a:SetDuration(duration); a:SetOrder(1)
  if a.SetFromAlpha then a:SetFromAlpha(from); a:SetToAlpha(to) else a:SetChange(to - from) end
  g:SetLooping("BOUNCE")
  return g
end

local function buildGlow(b)
  local fx = b.afuiFX
  local w, h = b:GetWidth() or 36, b:GetHeight() or 36
  local glow = CreateFrame("Frame", nil, b)
  glow:SetAllPoints(b)
  glow:SetFrameLevel((fx:GetFrameLevel() or 1) + 1)
  local halo = CreateFrame("Frame", nil, glow)
  halo:SetPoint("CENTER", glow, "CENTER", 0, 0); halo:SetWidth(w * 1.22); halo:SetHeight(h * 1.22)
  local rings = { ring(halo, "ui-hud-actionbar-iconframe-mouseover", w * 1.22, h * 1.22, 0.9, 1, 1, 1) }
  local inner = CreateFrame("Frame", nil, glow)
  inner:SetAllPoints(glow)
  rings[2] = ring(inner, "ui-hud-actionbar-iconframe-border", w + 1, h, 1, 1, 0.82, 0.2)
  glow.rings = rings
  glow.anims = { pulse(inner, 1, 0.45, 0.55), pulse(halo, 1, 0.2, 0.8) } -- two speeds, so they never beat together
  glow:Hide()
  fx.glow = glow
end

function FX.SetGlow(b, lit)
  local fx = b.afuiFX
  if not fx then return end
  b.afuiProc = lit and true or false
  local want = b.afuiProc and on("procGlow")
  if want and not fx.glow then buildGlow(b) end
  local glow = fx.glow
  if not glow then return end
  if want then
    glow:Show()
    for _, g in ipairs(glow.anims) do if not g:IsPlaying() then g:Play() end end
  else
    for _, g in ipairs(glow.anims) do g:Stop() end
    glow:Hide()
  end
end

local function hideClientGlow(b) if b.overlay and b.overlay.SetAlpha then b.overlay:SetAlpha(0) end end -- the client's own yellow frame: ours replaces it

-- The proc spell of a slot lights the button: events carry the spell, buttons are matched by what their slot holds.
local function slotSpell(b)
  local a = FX.ActionOf(b)
  if not (a and _G.GetActionInfo) then return end
  local kind, id = GetActionInfo(a)
  if kind == "spell" then return id end
end

function FX.SyncGlow(b)
  if b.afuiKind ~= "action" then return end
  if not _G.IsSpellOverlayed then return FX.SetGlow(b, b.afuiProc) end -- no way to ask the client: the events decide, this only re-applies the setting
  local id = slotSpell(b)
  FX.SetGlow(b, id and IsSpellOverlayed(id) or false)
end

local function onProc(spellID, lit)
  for _, b in ipairs(FX.buttons) do
    if b.afuiKind == "action" and slotSpell(b) == spellID then FX.SetGlow(b, lit) end
  end
end

---------------------------------------------------------------- hotkey / macro name switches
-- Alpha, not Hide: the client re-shows and re-texts both labels on every update.
function FX.ApplyLabels(b)
  local name = b:GetName()
  local hk, nm = _G[name .. "HotKey"], _G[name .. "Name"]
  if hk then hk:SetAlpha(on("showHotkeys") and 1 or 0) end
  if nm then nm:SetAlpha(on("showMacroNames") and 1 or 0) end
end

---------------------------------------------------------------- attach
function FX.Attach(b, size)
  if b.afuiFX then return end
  local name = b:GetName()
  if not name then return end
  b.afuiKind = kindOf(name)
  local cd = _G[name .. "Cooldown"]
  b.afuiCooldown = cd
  local fx = CreateFrame("Frame", nil, b)
  fx:SetAllPoints(b)
  fx:SetFrameLevel(((cd and cd:GetFrameLevel()) or b:GetFrameLevel() or 1) + 2)
  local text = fx:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  text:SetFont(FONT, FX.FontSize(size or b:GetWidth()), "OUTLINE")
  text:SetPoint("CENTER", b, "CENTER", 0, 0)
  text:Hide()
  fx.text = text
  b.afuiFX = fx
  if cd then
    cd.afuiButton = b
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end -- the client's own numbers would double ours
  end
  FX.buttons[#FX.buttons + 1] = b
  FX.ApplyLabels(b)
  if not ticker then ticker = CreateFrame("Frame") end
end

-- Everything again from the live client state (login, setting changes).
function FX.Refresh()
  for _, b in ipairs(FX.buttons) do
    FX.ApplyLabels(b)
    local start, duration, enable = FX.ReadCooldown(b)
    FX.SetCooldown(b, start, duration, enable)
    FX.UpdateTint(b)
    FX.SyncGlow(b)
  end
end

-- AddonCompat.lua (OmniCC): another addon draws the cooldown numbers on our buttons; ours stop, and come back when this is turned off.
function FX.SetExternalNumbers(v) FX.external = v and true or false; FX.Refresh() end

---------------------------------------------------------------- hooks
local function hookCooldown(fname)
  if type(_G[fname]) ~= "function" then return end
  hooksecurefunc(fname, function(cd, start, duration, enable)
    local b = type(cd) == "table" and cd.afuiButton
    if not b then return end
    if fname == "CooldownFrame_Clear" then start, duration = 0, 0 end
    FX.SetCooldown(b, start, duration, enable)
  end)
end
hookCooldown("CooldownFrame_SetTimer"); hookCooldown("CooldownFrame_Set"); hookCooldown("CooldownFrame_Clear")

local function hookButton(fname, fn)
  if type(_G[fname]) == "function" then AFUI.HookActionButton(fname, function(b) if b and b.afuiFX then fn(b) end end) end
end
hookButton("ActionButton_UpdateUsable", FX.UpdateTint)
hookButton("ActionButton_Update", function(b) FX.SyncGlow(b); FX.ApplyLabels(b) end)
hookButton("ActionButton_ShowOverlayGlow", function(b) hideClientGlow(b); FX.SetGlow(b, true) end)
hookButton("ActionButton_HideOverlayGlow", function(b) FX.SetGlow(b, false) end)

AFUI.On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(_, spellID) onProc(spellID, true) end)
AFUI.On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(_, spellID) onProc(spellID, false) end)
AFUI.On("PLAYER_ENTERING_WORLD", FX.Refresh)
AFUI.WatchSettings(function(key)
  if key == "cooldownNumbers" or key == "rangeTint" or key == "procGlow" or key == "showHotkeys" or key == "showMacroNames" then FX.Refresh() end
end)
AFUI.RegisterModule("ActionButtonFX", { OnLogin = FX.Refresh })

-- Audit: a number with no cooldown behind it, a glow the setting forbids.
function FX.Problems()
  local out = {}
  for _, b in ipairs(FX.buttons) do
    local fx, name = b.afuiFX, b:GetName() or "?"
    if fx.text:IsShown() and not running[b] then out[#out + 1] = name .. " shows a cooldown number but none runs" end
    if fx.glow and fx.glow:IsShown() and not (b.afuiProc and on("procGlow")) then out[#out + 1] = name .. " shows the proc glow without a proc" end
  end
  return out
end
