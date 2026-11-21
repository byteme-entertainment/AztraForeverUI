-- The glow on a unit's health or power bar when the value moves, drawn from one soft sprite (Media\plain\UI-BarGlow, tools/bar-glow-art.mjs:
-- top half a "band", bottom half a "ramp"), all additive:
--   damage   a ghost chunk over the lost part (red-orange, brighter at its leading edge) that holds 0.10 s, then drains toward the new edge
--            (ease-out cubic, 0.4 s, fading in its last third); a thin white-hot flare at the new edge (0.3 s); a faint whole-bar pulse (0.2 s)
--   healing  a green band travels from the old edge to the new one (0.35 s, ease-out) leaving the healed part glowing, fading by 0.5 s
--   power    spending drains a shorter (0.3 s), dimmer ghost with a small flare in the power colour; gaining sends a soft shimmer band
-- Three textures per attached bar (made once: ghost / band / pulse), one shared driver frame whose OnUpdate runs only while a glow animates.
-- An event inside a running animation extends it (union of ranges, the larger strength, the clock restarts); a damage after a heal (or the
-- reverse) replaces it. The first update, a max change, a unit switch, a dead or offline unit and a hidden bar never glow. No table is made per event.
--   AFUI.BarGlow.Attach(bar, unitFn, kind, win)  bar: a frame (a StatusBar, or the frame the fill sits in); unitFn() -> unit token | nil;
--     kind "health" | "power"; win() -> x0, y0, x1, y1 = the fill's window from the bar's TOPLEFT (default: the whole bar). Idempotent per bar and kind.
--   AFUI.BarGlow.Flash(bar, r, g, b, strength [, kind])  glows the whole window by hand (strength 0..1)
--   AFUI.BarGlow.Detach(bar [, kind])
--   AFUI.BarGlow.Debug(bar, mode, t [, kind])  mode "drop" | "gain" | "spend" | "got": freezes the animation at t (0..1 of its length), no driver
-- The setting "barGlow" (Settings > General, default on) switches every glow off.
AFUI = AFUI or {}
local G = {}
AFUI.BarGlow = G

local ART = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\UI-BarGlow"
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- per mode: dur = whole animation, hold + drain (drop / spend: the ghost), travel (gain / got: the band), flare = flare life, pulse = pulse life,
-- fw = flare / band width in px, ga = ghost alpha at full strength, fa = flare / band alpha at full strength, k = strength per fraction of max
local M = {
  drop = { dur = 0.5, hold = 0.10, drain = 0.40, flare = 0.3, pulse = 0.2, fw = 10, ga = 0.85, fa = 0.9, pa = 0.12, k = 3, kind = "health" },
  gain = { dur = 0.5, travel = 0.35, fade = 0.15, fw = 16, ga = 0.7, fa = 0.7, pulse = 0.3, pa = 0.08, k = 2, kind = "health" },
  spend = { dur = 0.3, hold = 0.05, drain = 0.25, flare = 0.2, pulse = 0, fw = 5, ga = 0.45, fa = 0.55, pa = 0, k = 2, kind = "power" },
  got = { dur = 0.4, travel = 0.35, fade = 0.1, fw = 14, ga = 0.25, fa = 0.55, pulse = 0, pa = 0, k = 1.2, kind = "power" },
}
G.DUR = { drop = M.drop.dur, gain = M.gain.dur, spend = M.spend.dur, got = M.got.dur }
local MIN, GHOST_MIN = 0.04, 0.1 -- a change under MIN strength stays invisible; under GHOST_MIN only the flare shows
local RED, GREEN = { 1, 0.36, 0.1 }, { 0.3, 1, 0.4 }
local HOT = { 1, 0.93, 0.8 } -- the flare of a hit
local POWER = { [0] = { 0.2, 0.45, 1 }, { 1, 0.1, 0.1 }, { 1, 0.5, 0.25 }, { 1, 1, 0.3 } }

local attached = setmetatable({}, { __mode = "k" }) -- bar -> { health = a, power = a }
local lists = { health = {}, power = {} }
local active, nActive = {}, 0
local on = true
local driver = CreateFrame("Frame")
driver:Hide()

local function ease(p) p = 1 - p; return 1 - p * p * p end -- ease-out cubic, p 0..1

-- puts tex over x0..x1 (from the bar's TOPLEFT), y0..y1 (down), with alpha al; hides it when nothing is left to see
local function place(tex, bar, x0, x1, y0, y1, al)
  if al < 0.004 or x1 - x0 < 0.5 then tex:Hide(); return end
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", bar, "TOPLEFT", x0, -y0)
  tex:SetPoint("BOTTOMRIGHT", bar, "TOPLEFT", x1, -y1)
  tex:SetAlpha(al); tex:Show()
end

local function clear(a) a.ghost:Hide(); a.band:Hide(); a.pulse:Hide() end

local function stop(a)
  if not a.live then return end
  a.live = nil; clear(a)
  for i = 1, nActive do
    if active[i] == a then active[i] = active[nActive]; active[nActive] = nil; nActive = nActive - 1; break end
  end
  if nActive == 0 then driver:Hide() end
end

-- the ghost's far edge (0..1 of the window) at time t
local function ghostHi(a, m, t)
  if t <= m.hold then return a.hi end
  local p = (t - m.hold) / m.drain
  return a.lo + (a.hi - a.lo) * (1 - ease(p > 1 and 1 or p))
end

-- draws the animation of a at time t
local function render(a, t)
  local bar, m, s = a.bar, a.m, a.s
  local x0, y0, x1, y1 = 0, 0, bar:GetWidth() or 0, bar:GetHeight() or 0
  if a.win then x0, y0, x1, y1 = a.win() end
  local w = x1 - x0
  if w <= 0 then clear(a); return end
  local r, g, b = a.r, a.g, a.b
  local ghost, band, pulse = a.ghost, a.band, a.pulse
  local al
  if m.hold then -- drop / spend
    local hi = ghostHi(a, m, t)
    local p = (t - m.hold) / m.drain
    local f = 1
    if p > 2 / 3 then f = 1 - (p - 2 / 3) * 3; if f < 0 then f = 0 end end
    if s >= GHOST_MIN then
      ghost:SetVertexColor(r, g, b)
      place(ghost, bar, x0 + a.lo * w, x0 + hi * w, y0, y1, m.ga * s * f)
    else ghost:Hide() end
    local fp = t / m.flare
    local fw = m.fw
    al = fp < 1 and m.fa * (0.5 + 0.5 * s) * (1 - fp) * (1 - fp) or 0
    local fx = x0 + a.lo * w
    band:SetVertexColor(a.fr, a.fg, a.fb)
    place(band, bar, fx - fw / 2, fx + fw / 2, y0, y1, al)
  else -- gain / got
    local p = t / m.travel
    local e = ease(p > 1 and 1 or p)
    local edge = a.lo + (a.hi - a.lo) * e
    local f = 1
    if t > m.fade then f = 1 - (t - m.fade) / (m.dur - m.fade); if f < 0 then f = 0 end end
    ghost:SetVertexColor(r, g, b)
    place(ghost, bar, x0 + a.lo * w, x0 + edge * w, y0, y1, m.ga * s * f)
    local fw = m.fw
    al = p < 1 and m.fa * s * (1 - p * p) or 0
    local bx = x0 + edge * w
    band:SetVertexColor(a.fr, a.fg, a.fb)
    place(band, bar, bx - fw / 2, bx + fw / 2, y0, y1, al)
  end
  if m.pulse > 0 and t < m.pulse then
    pulse:SetVertexColor(r, g, b)
    place(pulse, bar, x0, x1, y0, y1, m.pa * s * (1 - t / m.pulse))
  else pulse:Hide() end
end

driver:SetScript("OnUpdate", function(_, dt)
  local i = 1
  while i <= nActive do
    local a = active[i]
    a.t = a.t + dt
    if a.t >= a.m.dur then stop(a) else render(a, a.t); i = i + 1 end
  end
end)

-- starts (or extends) the animation of mode on a: lo..hi the part of the window (0..1) that changed, s the strength 0..1
local function start(a, mode, lo, hi, s, r, g, b)
  local m = M[mode]
  if a.live then
    if a.m == m then -- same kind of event: the union of the ranges (the ghost counts from where it has drained to), the larger strength
      local left = a.s * (1 - a.t / m.dur)
      if left > s then s = left end
      local ohi = m.hold and ghostHi(a, m, a.t) or a.hi
      if a.lo < lo then lo = a.lo end
      if ohi > hi then hi = ohi end
    end
  end
  a.m, a.lo, a.hi, a.s, a.t = m, lo, hi, s > 1 and 1 or s, 0
  a.r, a.g, a.b = r, g, b
  if mode == "drop" then a.fr, a.fg, a.fb = HOT[1], HOT[2], HOT[3] -- the flare: white-hot after a hit, the colour lifted towards white otherwise
  else a.fr, a.fg, a.fb = (r + 1) / 2, (g + 1) / 2, (b + 1) / 2 end
  render(a, 0)
  if not a.live then
    a.live = true; nActive = nActive + 1; active[nActive] = a
    driver:Show()
  end
end

local function gone(unit)
  if UnitIsConnected and not UnitIsConnected(unit) then return true end
  return (UnitIsDeadOrGhost or UnitIsDead)(unit) and true or false
end

local function health(a, unit)
  local cur, max, guid = UnitHealth(unit), UnitHealthMax(unit), UnitGUID and UnitGUID(unit)
  local prev, pmax, pguid = a.cur, a.max, a.guid
  a.cur, a.max, a.guid = cur, max, guid
  if not prev or pguid ~= guid or pmax ~= max or max <= 0 or cur == prev or not on then return end
  if not a.bar:IsVisible() or gone(unit) then return end
  local d = (cur - prev) / max
  if d < 0 then
    if -d * M.drop.k >= MIN then start(a, "drop", cur / max, prev / max, -d * M.drop.k, RED[1], RED[2], RED[3]) end
  elseif d * M.gain.k >= MIN then start(a, "gain", prev / max, cur / max, d * M.gain.k, GREEN[1], GREEN[2], GREEN[3]) end
end

local function powerColor(ptype)
  local p = PowerBarColor and PowerBarColor[ptype] or POWER[ptype] or POWER[0]
  local r, g, b = p.r or p[1], p.g or p[2], p.b or p[3]
  return r + (1 - r) * 0.35, g + (1 - g) * 0.35, b + (1 - b) * 0.35 -- lifted towards white: additive pure blue is nearly black
end

local function power(a, unit)
  local cur, max = AFUI.UnitPower(unit)
  local ptype, guid = UnitPowerType(unit), UnitGUID and UnitGUID(unit)
  local prev, pmax, pguid, ptp = a.cur, a.max, a.guid, a.ptype
  a.cur, a.max, a.guid, a.ptype = cur, max, guid, ptype
  if not prev or not max or max <= 0 or pguid ~= guid or pmax ~= max or ptp ~= ptype or cur == prev or not on then return end
  if not a.bar:IsVisible() or gone(unit) then return end
  local d = (cur - prev) / max
  local r, g, b = powerColor(ptype)
  if d < 0 then
    if -d * M.spend.k >= MIN then start(a, "spend", cur / max, prev / max, -d * M.spend.k, r, g, b) end
  elseif d * M.got.k >= MIN then start(a, "got", prev / max, cur / max, d * M.got.k, r, g, b) end
end

function G.Attach(bar, unitFn, kind, win)
  if not (bar and bar.CreateTexture and lists[kind]) then return end
  local slot = attached[bar]
  if not slot then slot = {}; attached[bar] = slot end
  if slot[kind] then return slot[kind] end
  local function tex(path, l, r, t, b)
    local x = bar:CreateTexture(nil, "OVERLAY")
    x:SetTexture(path); x:SetBlendMode("ADD"); if l then x:SetTexCoord(l, r, t, b) end
    x:Hide()
    return x
  end
  local a = { bar = bar, fn = unitFn, kind = kind, win = win, t = 0, s = 0, lo = 0, hi = 1, m = M.drop, r = 1, g = 1, b = 1, fr = 1, fg = 1, fb = 1,
    ghost = tex(ART, 0, 1, 0.5, 1), band = tex(ART, 0, 1, 0, 0.5), pulse = tex(WHITE) } -- ramp (bottom half), band (top half), flat whole-bar pulse
  slot[kind] = a
  local l = lists[kind]; l[#l + 1] = a
  return a
end

function G.Detach(bar, kind)
  local slot = attached[bar]
  if not slot then return end
  for k, a in pairs(slot) do
    if not kind or k == kind then
      stop(a); clear(a)
      local l = lists[k]
      for i = 1, #l do if l[i] == a then table.remove(l, i); break end end
      slot[k] = nil
    end
  end
end

function G.Flash(bar, r, g, b, strength, kind)
  local slot = attached[bar]
  if not (slot and on) then return end
  for k, a in pairs(slot) do
    if not kind or k == kind then start(a, "gain", 0, 1, strength or 0.3, r, g, b) end
  end
end

-- preview hook: the animation of mode frozen at t (0..1 of its length), on the bar's health or power glow, no driver
function G.Debug(bar, mode, t)
  local m, slot = M[mode], attached[bar]
  local a = m and slot and slot[m.kind]
  if not a then return end
  stop(a)
  local r, g, b
  if mode == "drop" then r, g, b = RED[1], RED[2], RED[3]
  elseif mode == "gain" then r, g, b = GREEN[1], GREEN[2], GREEN[3]
  else r, g, b = powerColor(0) end
  local lo, hi = 0.5, 0.8
  if mode == "gain" or mode == "got" then lo, hi = 0.4, 0.7 end
  start(a, mode, lo, hi, 0.8, r, g, b)
  stop(a)
  render(a, t * m.dur)
end

local function dispatch(kind, fn)
  return function(_, unit)
    local l = lists[kind]
    for i = 1, #l do
      local a = l[i]
      local u = a.fn()
      if u and u == unit then fn(a, u) end
    end
  end
end

function G.Enabled() return on end

AFUI.RegisterModule("BarGlow", { OnLogin = function()
  local function read()
    on = AFUI.GetSetting("barGlow", true) ~= false
    if not on then for i = nActive, 1, -1 do stop(active[i]) end end
  end
  read()
  AFUI.OnSettingChanged("barGlow", read)
  for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do AFUI.On(e, dispatch("health", health)) end
  for _, e in ipairs(AFUI.POWER_EVENTS) do AFUI.On(e, dispatch("power", power)) end
end })
