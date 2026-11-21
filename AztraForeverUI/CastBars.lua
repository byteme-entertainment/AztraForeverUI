-- Player and target cast bars: a port of Forever's modern cast bar (docs/forever-ref/castbar.md; `CB/` below =
-- blizzard_uipanels_game/). OnUpdate runs only while a bar casts or fades.
AFUI = AFUI or {}
AFUI.CastBars = {}

-- notInterruptible is always false on both clients: 2.4.3 has none, and 2.5.3's UnitCastingInfo slot 8 is not trusted
-- (Blizzard's CastingBarFrame.lua:147-148 hard-codes it to false), so there is no uninterruptable look or shield.

local A = "ui-castingbar-"
-- Bar types: fill, full (at the end) and finish glow atlas, spark effect (CB/shared/castingbarframe.lua:26-85).
local TYPES = {
  standard = { "filling-standard", "full-standard", "full-glow-standard", fx = "glow" },
  channel = { "filling-channel", "full-channel", "full-glow-channel", fx = "shadow" },
  uninterruptable = { "uninterruptable", "uninterruptable", "full-glow-standard" },
  interrupted = { "interrupted", "interrupted", "full-glow-standard" },
}
-- Looks (SetLook, CB/shared/castingbarframe.lua:1022-1096) on the two templates (CB/mainline/castingbarframe.xml):
-- the player's CastingBarFrameTemplate (CLASSIC, or UNITFRAME when locked to the player frame) and the target's
-- SmallCastingBarFrameTemplate (SetLook never called). Insets are TOPLEFT x, y, BOTTOMRIGHT x, y.
local LOOK = {
  CLASSIC = { w = 208, h = 11, bg = { -1, 1, 1, -1 }, border = { -2, 2, 2, -2 }, spark = { 8, 20 }, textW = 185,
    text = { { "TOP", 0, -10 } }, plate = true, flashAnim = true, fx = true },
  UNITFRAME = { w = 150, h = 10, bg = { -1, 1, 1, -1 }, border = { -2, 2, 2, -2 }, spark = { 8, 20 },
    text = { { "TOPLEFT", 0, 3 }, { "TOPRIGHT", 0, 3 } }, icon = { 16, -5, 0 }, flashAnim = true },
  SMALL = { w = 150, h = 10, bg = { 0, 0, 0, 0 }, border = { -1, 2, 1, -2 }, spark = { 6, 16 },
    text = { { "TOPLEFT", 0, -8 }, { "TOPRIGHT", 0, -8 } }, plate = true, icon = { 20, -2, -5 }, shield = true },
}

-- startMS/endMS/nowMS in milliseconds. Returns fraction (0-1; a channel counts down) and seconds left.
function AFUI.CastProgress(startMS, endMS, nowMS, isChannel)
  local total = endMS - startMS
  if total <= 0 then return 1, 0 end
  local elapsed = math.min(math.max(nowMS - startMS, 0), total)
  local remaining = (total - elapsed) / 1000
  if isChannel then return remaining * 1000 / total, remaining end
  return elapsed / total, remaining
end

local artNames = {} -- art() runs every frame during a cast: build each name once
local function art(name)
  local n = artNames[name]
  if not n then n = AFUI_ATLAS[A .. name .. "-c60"] and A .. name .. "-c60" or A .. name; artNames[name] = n end
  return n
end
local function shown(r, on) if on then r:Show() else r:Hide() end end
local function inset(tex, f, i)
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", f, "TOPLEFT", i[1], i[2]); tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", i[3], i[4])
end

local function build(key, unit)
  local b = { unit = unit, settings = { scale = 1, lockToPlayerFrame = false } }
  local f = CreateFrame("Frame", "AFUI_CastBar_" .. key, UIParent)
  f:Hide()
  b.frame = f
  local function tex(layer, atlas)
    local t = f:CreateTexture(nil, layer)
    if atlas then AFUI.SetAtlas(t, art(atlas)) end
    return t
  end
  b.textBorder = tex("BACKGROUND", "textbox")
  b.bg = tex("BACKGROUND", "background")
  b.fill = tex("BORDER")
  b.shield = tex("ARTWORK", "shield"); b.shield:SetWidth(29); b.shield:SetHeight(33)
  b.shield:SetPoint("TOPLEFT", f, "TOPLEFT", -27, 4); b.shield:Hide()
  b.icon = tex("ARTWORK"); b.icon:Hide()
  b.border = tex("ARTWORK", "frame")
  b.flash = tex("OVERLAY"); b.flash:SetBlendMode("ADD"); inset(b.flash, f, { -1, 1, 1, -1 }); b.flash:Hide()
  b.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- = SystemFont_Shadow_Small (white, shadow)
  b.spark = tex("OVERLAY", "pip")
  -- spark trails, masked to the bar in Forever: cropped at the bar's left edge here (CB/mainline/castingbarframe.xml:347-384)
  b.glow = tex("OVERLAY"); AFUI.SetAtlas(b.glow, "cast_standard_pipglow"); b.glow:SetBlendMode("ADD"); b.glow:SetHeight(12)
  b.glow:SetPoint("RIGHT", b.spark, "LEFT", 2, 0); b.glow:Hide()
  b.shadow = tex("OVERLAY"); AFUI.SetAtlas(b.shadow, "cast_channel_pipshadow"); b.shadow:SetHeight(11)
  b.shadow:SetPoint("RIGHT", b.spark, "LEFT", 1, 0); b.shadow:Hide()

  function b.setLook(name)
    local L = LOOK[name]
    b.look = L
    f:SetWidth(L.w); f:SetHeight(L.h)
    inset(b.bg, f, L.bg); inset(b.border, f, L.border); inset(b.textBorder, f, { 0, 0, 0, -12 })
    -- The bar is the INTERIOR of the border art: the sprite's window (x 3..211, y 3..13 of 213 x 15, measured from the page pixels)
    -- stretched with the border box. b.win = { x0, y0, x1, y1 } from the frame's TOPLEFT, y down.
    local e = AFUI_ATLAS[b.border.afuiAtlas]
    local bx0, by0, bx1, by1 = L.border[1], -L.border[2], L.w + L.border[3], L.h - L.border[4]
    local sx, sy = (bx1 - bx0) / e[2], (by1 - by0) / e[3]
    b.win = { bx0 + 3 * sx, by0 + 3 * sy, bx0 + 211 * sx, by0 + 13 * sy }
    shown(b.textBorder, L.plate)
    b.spark:SetWidth(L.spark[1]); b.spark:SetHeight(L.spark[2])
    b.text:ClearAllPoints()
    for _, p in ipairs(L.text) do b.text:SetPoint(p[1], f, p[1], p[2], p[3]) end
    b.text:SetWidth(L.textW or 0); b.text:SetHeight(16)
    if L.icon then
      b.icon:SetWidth(L.icon[1]); b.icon:SetHeight(L.icon[1])
      b.icon:ClearAllPoints(); b.icon:SetPoint("RIGHT", f, "LEFT", L.icon[2], L.icon[3])
    else b.icon:Hide() end
  end

  -- Crops a spark trail (width w, right edge `dx` right of the spark's left edge) to the bar.
  local function trail(t, name, w, dx, pos)
    local e, vis = AFUI_ATLAS[name], math.min(w, pos - b.look.spark[1] / 2 + dx)
    if not e or vis <= 0 then t:Hide(); return end
    t:SetWidth(vis); t:SetTexCoord(e[4] + (e[5] - e[4]) * (1 - vis / w), e[5], e[6], e[7]); t:Show()
  end

  local function paint(atlas, frac)
    local L, x0, y0, x1, y1 = b.look, unpack(b.win)
    -- exactly the interior of the border art (the preview checks it: barcheck.mjs); the spark rides the fill's end
    AFUI.Bar.Place(b.fill, f, { x0, y0, L.w - x1, L.h - y1 }, frac, atlas, nil, { w = L.w, fa = b.border })
    local pos = x0 + (x1 - x0) * frac
    b.spark:ClearAllPoints(); b.spark:SetPoint("CENTER", f, "LEFT", pos, L.h / 2 - (y0 + y1) / 2)
    local fx = b.spark:IsShown() and L.fx and TYPES[b.type].fx
    if fx == "glow" then trail(b.glow, "cast_standard_pipglow", 37, 2, pos) else b.glow:Hide() end
    if fx == "shadow" then trail(b.shadow, "cast_channel_pipshadow", 11, 1, pos) else b.shadow:Hide() end
  end

  local function progress()
    return AFUI.CastProgress(b.startMS, b.endMS, GetTime() * 1000, b.state == "channel")
  end

  local function idle()
    b.state = nil; f:SetScript("OnUpdate", nil); f:Hide()
  end

  -- Finish: FlashAnim (glow alpha 0 -> 1 in 0.2 s, player template only) and FadeOutAnim (alpha 1 -> 0 over 0.3 s
  -- after 0.2 s). Interrupt/fail: HoldFadeOutAnim (1 s, then 0.3 s) (CB/shared/castingbarframetemplates.xml:5-16).
  local function tick(_, dt)
    local s = b.state
    if s == "cast" or s == "channel" then
      local frac = progress()
      paint(art(TYPES[b.type][1]), frac)
      if (s == "cast" and frac >= 1) or (s == "channel" and frac <= 0) then b.stop() end
      return
    end
    b.timer = b.timer + dt
    local t = b.timer
    if s == "finish" then
      if b.look.flashAnim then b.flash:SetAlpha(math.min(t / 0.2, 1)) end
      if t >= 0.5 then return idle() end
      f:SetAlpha(t <= 0.2 and 1 or 1 - (t - 0.2) / 0.3)
    else
      if t >= 1.3 then return idle() end
      f:SetAlpha(t <= 1 and 1 or 1 - (t - 1) / 0.3)
    end
  end

  local function load()
    local name, texture, startMS, endMS, isChannel = AFUI.CastingInfo(unit)
    if not name then return false end
    b.startMS, b.endMS = startMS, endMS
    b.state = isChannel and "channel" or "cast"
    b.type = isChannel and "channel" or "standard"
    AFUI.FitText(b.text, name, b.look.textW or b.look.w); AFUI.SetIcon(b.icon, texture)
    return true
  end

  function b.start()
    if not load() then return idle() end
    shown(b.icon, b.look.icon); b.shield:Hide()
    b.spark:Show(); b.flash:Hide()
    f:SetAlpha(1); f:Show(); f:SetScript("OnUpdate", tick); tick(f, 0)
  end

  -- Success: the bar swaps to the full art, the spark goes, the glow flashes (castingbarframe.lua:470-528).
  function b.stop()
    if b.state ~= "cast" and b.state ~= "channel" then return end
    local frac = b.state == "cast" and 1 or progress()
    b.spark:Hide()
    paint(art(TYPES[b.type][2]), frac)
    AFUI.SetAtlas(b.flash, art(TYPES[b.type][3])); b.flash:SetAlpha(0); b.flash:Show()
    b.state, b.timer = "finish", 0
    f:SetScript("OnUpdate", tick)
  end

  -- Interrupted / failed art and text (castingbarframe.lua:541-573). The FX bar fills up and drops the spark
  -- (ApplyInterruptFilledState); the others keep the fill where it stopped. pip-red is not in Forever's atlas list.
  function b.interrupt(text)
    if b.state ~= "cast" and b.state ~= "channel" then return end
    local frac = progress()
    if b.look.fx then frac = 1; b.spark:Hide() end
    b.type = "interrupted"
    paint(art("interrupted"), frac)
    AFUI.FitText(b.text, text, b.look.textW or b.look.w)
    b.state, b.timer = "interrupted", 0
    f:SetScript("OnUpdate", tick)
  end

  function b.delayed() if b.state == "cast" or b.state == "channel" then load() end end

  function b.place()
    local s = b.settings
    local scale = s.scale or 1
    f:SetScale(scale)
    if key == "target" then -- TargetSpellBarMixin:AdjustPosition (blizzard_unitframe/mainline/targetframe.lua:830-855)
      local t = AFUI.Units and AFUI.Units.target
      if not t then return end
      f:ClearAllPoints()
      if not (t.settings and t.settings.buffsOnTop) and t.auraRows > (t.totShown and 2 or 0) then f:SetPoint("TOPLEFT", t.auras, "BOTTOMLEFT", 18, -10)
      else f:SetPoint("TOPLEFT", t.frame, "BOTTOMLEFT", 43, t.totShown and -46 or 5) end
      return
    end
    local locked = s.lockToPlayerFrame and AFUI_PlayerFrame
    b.setLook(locked and "UNITFRAME" or "CLASSIC")
    if locked then -- AnchorCastBarToPlayerFrame (blizzard_unitframe/shared/playerframe.lua:18-32)
      f:SetFrameStrata("LOW")
      f:ClearAllPoints(); f:SetPoint("TOPRIGHT", AFUI_PlayerFrame, "BOTTOMRIGHT", -24 / scale, 12 / scale)
    else
      f:SetFrameStrata("HIGH")
      f:ClearAllPoints(); f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200) -- edit mode then places it
    end
  end

  function b.ApplySettings(settings)
    for k, v in pairs(settings or {}) do b.settings[k] = v end
    b.place()
  end

  if key == "target" then b.setLook("SMALL"); f:SetFrameStrata("LOW") end
  return b
end

function AFUI.SetupCastBars()
  for _, n in ipairs({ "CastingBarFrame", "TargetFrameSpellBar" }) do
    if _G[n] then AFUI.Kill(_G[n], n == "TargetFrameSpellBar") end
  end
  local bars = { player = build("player", "player"), target = build("target", "target") }
  AFUI.CastBars.player, AFUI.CastBars.target = bars.player, bars.target
  for _, b in pairs(bars) do b.place() end

  local function route(method, text)
    return function(_, unit)
      for _, b in pairs(bars) do if b.unit == unit then b[method](text) end end
    end
  end
  AFUI.On("UNIT_SPELLCAST_START", route("start")); AFUI.On("UNIT_SPELLCAST_CHANNEL_START", route("start"))
  AFUI.On("UNIT_SPELLCAST_STOP", route("stop")); AFUI.On("UNIT_SPELLCAST_CHANNEL_STOP", route("stop"))
  AFUI.On("UNIT_SPELLCAST_INTERRUPTED", route("interrupt", _G.INTERRUPTED or "Interrupted"))
  AFUI.On("UNIT_SPELLCAST_DELAYED", route("delayed")); AFUI.On("UNIT_SPELLCAST_CHANNEL_UPDATE", route("delayed"))
  AFUI.On("UNIT_SPELLCAST_FAILED", function(_, unit)
    -- FAILED also fires for spam-clicks while another cast is running; only show it when nothing is casting
    for _, b in pairs(bars) do
      if b.unit == unit and not AFUI.CastingInfo(unit) then b.interrupt(_G.FAILED or "Failed") end
    end
  end)
  AFUI.On("PLAYER_TARGET_CHANGED", function() bars.target.place(); bars.target.start() end)
end

AFUI.RegisterModule("CastBars", { OnLogin = AFUI.SetupCastBars })
