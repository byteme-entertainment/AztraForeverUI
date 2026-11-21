-- Forever's nameplate as the recordings show it (video3 f0001/f0008, measured at 1.40625 px/u; Mat's client runs the Small size, 0.75 wide / 0.8 high):
-- the metal-rimmed bar art (ui-hud-cooldownmanager-bar-bg, 132 x 19) stretched 1.49 high, the SHADED health bar texture (ui-hud-cooldownmanager-bar:
-- a dark outline, a light top row, darker toward the bottom and the left, tinted by the reaction colour: nameplates.md) inside its trough, the name inside
-- the bar on the left, and a 23.5 x 24.5 level box (ui-hud-nameplates-levelindicator-rectangle) beside the art's right edge.
-- All art is the 2x sprites of Media/NameplateArt.lua (tools/nameplate-art.mjs, 2 px per unit). The selected plate is NOT a scaled frame (a scaled 1x sprite
-- goes soft): layout(s, k) sets every size, offset and font of the plate to its final value times k.
-- 2.5.3 skins C_NamePlate plates by unit token; 2.4.3 has no nameplate API, so plates are found among
-- WorldFrame's anonymous children and read from their own regions (docs/forever-ref/nameplates-port-report.md).
-- Our art is a child of the Blizzard plate frame, anchored to it: it moves with the plate on every frame, nothing is drawn from a
-- remembered screen position.
AFUI = AFUI or {}
local IS_243 = AFUI.IS_243

local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
  "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP" }

-- No shield / uninterruptable state on either client: 2.4.3 has no notInterruptible return, and 2.5.3's
-- UnitCastingInfo slot 8 is not trusted (Blizzard's CastingBarFrame.lua:147-148 hard-codes notInterruptible = false).
-- Plate discovery differs per client: setup243 / setup253 below.

local W, INSET, CAST_H, CAST_TEXT_H, ICON = 148, 12, 5, 10, 10
-- Measured in f0001 (Ice Dog, unselected): rim row 1 to rim row 12 = 23 px = 16.4 u for 11 art rows -> 1.49 u per row; width 1:1 (127 px of rim = 178 px).
-- The fill (flat, 17 px = 12 u) covers art rows 3..10.8, the art's trough (rows 4..10 by alpha) plus one row above and 0.8 below.
local KY = 1.49
local FRAMED_W, FRAMED_H, BG_PAD = 120, 6 * KY, 4 -- the bar frame IS the trough window: 120 x 6 art rows
-- the fill reaches past the window into the dark rows (negative = outward); the bar texture's last pixel row (of 20) is transparent, so the rect runs FILL_TAIL lower
-- and the VISIBLE fill ends where the trough does
local FILL_TAIL = 1.45
local FILL_INSET = { 0, -1 * KY, -0.5, -0.8 * KY - FILL_TAIL } -- 0.5 right: the art's window is 241 px = 120.5 u wide
local FILL_GROW = { 0, 1 * KY, 0, 0.8 * KY }
local LEVEL_W, LEVEL_H, LEVEL_DX, LEVEL_DY = 23.5, 24.5, -2, 1.5 -- the level frame as measured side by side with f0001: 28 x 22 art squeezed to 23.5 x 24.5, 5 u from the bar rim, top level with it
local NAME_PAD, NAME_SIZE, LEVEL_FONT = 5, 11, 8 -- 14 and 10 times the Small vertical scale 0.8
local NP = {}
AFUI.Nameplates = NP
NP.TARGET_SCALE = 1.08 -- "Subtle" (default): the targeted plate is laid out 8% bigger; 1.17 (the recording: 1.15 wide, 1.2 high) read as giant on Mat's screen
local TARGET_SCALES = { off = 1, subtle = NP.TARGET_SCALE, large = 1.17 }
-- Target zoom: exponential ease (WinKit.ScrollEase style, framerate independent), ~99% done in 0.14 s in / 0.18 s out; the ring / overlay fade is linear, 0.1 s.
local ZOOM_IN, ZOOM_OUT, ZOOM_EPS, FADE_TIME = math.log(100) / 0.14, math.log(100) / 0.18, 0.0005, 0.1
function NP.ZoomStep(cur, goal, dt)
  local nxt = cur + (goal - cur) * (1 - math.exp(-dt * (goal > cur and ZOOM_IN or ZOOM_OUT)))
  return math.abs(goal - nxt) < ZOOM_EPS and goal or nxt
end
function NP.FadeStep(cur, goal, dt)
  local step = dt / FADE_TIME
  if goal > cur then return math.min(cur + step, goal) end
  return math.max(cur - step, goal)
end
-- the layout factor of the targeted plate, from the "nameplateTargetScale" setting (off / subtle / large)
function NP.TargetScale() return TARGET_SCALES[AFUI.GetSetting("nameplateTargetScale", "subtle")] or NP.TARGET_SCALE end
local DESELECTED = 0.34 -- non-target fills are 0.66 of the target's brightness (90,78,231 -> 60,54,153)
-- every friendly player plate in the recording (not class coloured): the right end of Ice Dog's bar measures 94,83,242 under the bar texture's 0.96 there, so the tint
local FRIEND_PLAYER = { 98 / 255, 86 / 255, 1 }
local PX = 2 -- sprite pixels per unit (Media/NameplateArt.lua)
local RING_CORNER = 6 -- units: a 12 px corner of the 2x ring sprite
local TEXEL = 0.5 / 512 -- the bar fill: half a texel in from its opaque edges, no bleed from the neighbour on the sheet (the rest of the art has transparent edges)
local ART_BAR, ART_BG, ART_SEL, ART_LV, ART_LVSEL, ART_SKULL = "np-bar", "np-bar-bg", "np-selected", "np-level", "np-level-selected", "np-skull"
local BAR_W = W - 2 * INSET
local NAME_W = FRAMED_W - NAME_PAD - 4 -- the trough less its padding
local PLATE_H = 25 + 14 + 10 + CAST_H + CAST_TEXT_H
local FONT = "Fonts\\FRIZQT__.TTF"
local TARGET, FOCUS = { 1, 1, 1 }, { 1, 0.49, 0.039 } -- camelot constants :30-31
-- UNIT_LEVEL_NON_ATTACKABLE is not in the pulled files. video3 f0001 (JPEG peaks 223,224,114 on "23", "31", "57": red = green, so pure yellow, not the
-- orange gold of TBC TargetFrame's 1, 0.82, 0; level 57 shows the same colour at level 24, so it is not a difficulty colour).
local NON_ATTACKABLE = { 1, 1, 0 }
local CLASSIFICATION = { elite = "nameplates-icon-elite-gold", worldboss = "nameplates-icon-elite-gold",
  rare = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star", rareelite = "nameplates-icon-elite-silver" }
local BORDER = "Interface\\Tooltips\\Nameplate-Border"
local CAST_COLOR, CHANNEL_COLOR = { 1, 0.7, 0 }, { 0.2, 0.9, 0.2 }

-- A solid rectangle (2.4.3 SetTexture(r, g, b, a), 2.5.3 SetColorTexture, through AFUI.SetColor).
local function solid(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer)
  AFUI.SetColor(t, r, g, b, a or 1)
  return t
end

-- One frame per plate: every texture and string below belongs to the plate frame itself, the child frames are only anchors
-- (and the cast OnUpdate). Neighbouring plates then stack as whole plates and never interleave (no torn bars, no name over
-- someone else's bar). The cast frame's regions are therefore shown and hidden by hand.
local function showCast(s, on)
  if on then s.cast:Show() else s.cast:Hide() end
  for _, r in ipairs(s.castRegions) do if on then r:Show() else r:Hide() end end
end

-- A selection ring cut in 9 (centre dropped) from its 2x sprite: the corners keep their drawn size, the edges only stretch along their length, so
-- the ring is as thick as the artist drew it however tall or wide the plate is (one stretched sprite made the top and bottom 1.66 times too thick and soft).
-- cpx = corner size in sprite pixels. Acts like one texture for Show / Hide / SetVertexColor.
local RING_PARTS = { "tl", "t", "tr", "l", "r", "bl", "b", "br" }
local function ring(f, layer, name, cpx)
  local e = AFUI_ATLAS[name]
  local r = { hidden = true, cpx = cpx, pieces = {} }
  local W, H = e[2], e[3]
  local xs, ys = { 0, cpx, W - cpx, W }, { 0, cpx, H - cpx, H } -- column / row edges in sprite pixels
  local at = { tl = { 1, 1 }, t = { 2, 1 }, tr = { 3, 1 }, l = { 1, 2 }, r = { 3, 2 }, bl = { 1, 3 }, b = { 2, 3 }, br = { 3, 3 } }
  for _, p in ipairs(RING_PARTS) do
    local t = f:CreateTexture(nil, layer)
    t:SetTexture(e[1])
    local c, rw = at[p][1], at[p][2]
    t:SetTexCoord(e[4] + (e[5] - e[4]) * xs[c] / W, e[4] + (e[5] - e[4]) * xs[c + 1] / W, e[6] + (e[7] - e[6]) * ys[rw] / H, e[6] + (e[7] - e[6]) * ys[rw + 1] / H)
    t:Hide()
    r.pieces[p] = t
  end
  r.pieces.tl.afuiAtlas = name
  function r:Show() self.hidden = false; for _, t in pairs(self.pieces) do t:Show() end end
  function r:Hide() self.hidden = true; for _, t in pairs(self.pieces) do t:Hide() end end
  function r:SetVertexColor(cr, cg, cb) for _, t in pairs(self.pieces) do t:SetVertexColor(cr, cg, cb) end end
  function r:SetAlpha(a) for _, t in pairs(self.pieces) do t:SetAlpha(a) end end
  -- the ring around `ref`: TOPLEFT at (l, t), BOTTOMRIGHT at (r, b) from the same corners of ref; the corner pieces are `corner` units square
  function r:Layout(ref, l, t, rr, b, corner)
    local p = self.pieces
    self.rect = { l, t, rr, b, corner }
    for _, k in ipairs(RING_PARTS) do p[k]:ClearAllPoints() end
    p.tl:SetWidth(corner); p.tl:SetHeight(corner); p.tl:SetPoint("TOPLEFT", ref, "TOPLEFT", l, t)
    p.tr:SetWidth(corner); p.tr:SetHeight(corner); p.tr:SetPoint("TOPRIGHT", ref, "TOPRIGHT", rr, t)
    p.bl:SetWidth(corner); p.bl:SetHeight(corner); p.bl:SetPoint("BOTTOMLEFT", ref, "BOTTOMLEFT", l, b)
    p.br:SetWidth(corner); p.br:SetHeight(corner); p.br:SetPoint("BOTTOMRIGHT", ref, "BOTTOMRIGHT", rr, b)
    p.t:SetPoint("TOPLEFT", p.tl, "TOPRIGHT", 0, 0); p.t:SetPoint("BOTTOMRIGHT", p.tr, "BOTTOMLEFT", 0, 0)
    p.l:SetPoint("TOPLEFT", p.tl, "BOTTOMLEFT", 0, 0); p.l:SetPoint("BOTTOMRIGHT", p.bl, "TOPRIGHT", 0, 0)
    p.r:SetPoint("TOPLEFT", p.tr, "BOTTOMLEFT", 0, 0); p.r:SetPoint("BOTTOMRIGHT", p.br, "TOPRIGHT", 0, 0)
    p.b:SetPoint("TOPLEFT", p.bl, "TOPRIGHT", 0, 0); p.b:SetPoint("BOTTOMRIGHT", p.br, "BOTTOMLEFT", 0, 0)
  end
  return r
end

local NO_INSET = { 0, 0, 0, 0 } -- the cast fill sits exactly in its frame
local setName, setHealth, layout, castTick

-- A 2x sprite drawn from its exact rectangle.
local function sprite(tex, name)
  AFUI.SetAtlas(tex, name)
  local e = AFUI_ATLAS[name]
  return e[2] / PX, e[3] / PX -- its size in units
end

local function build(host, raid)
  local s = { host = host, k = 1, z = 1, zGoal = 1, sel = 0, selGoal = 0, fresh = true } -- k: laid-out factor; z: zoom shown (frame scale while it moves)
  local f = CreateFrame("Frame", nil, host)
  f:SetPoint("CENTER", host, "CENTER", 0, 0)
  s.frame = f
  s.castBox = CreateFrame("Frame", nil, f)
  s.hp = CreateFrame("Frame", nil, f) -- the bar frame: the trough of the rim art, 120 x 6 rows; the rim art hangs off it (4 in, one row of rim above)
  s.fbg = f:CreateTexture(nil, "BACKGROUND"); s.bgW, s.bgH = sprite(s.fbg, ART_BG)
  -- shaded bar texture tinted by the reaction colour (the colour is the vertex colour), the dark overlay of plates that are not the target
  s.fill = f:CreateTexture(nil, "ARTWORK")
  s.deselected = solid(f, "OVERLAY", 0, 0, 0, DESELECTED)
  if AFUI.BarGlow then -- on the trough window, the box setHealth pins the fill to
    AFUI.BarGlow.Attach(s.hp, function() return s.unit end, "health", function()
      local k = s.k
      return 0, FILL_INSET[2] * k, FRAMED_W * k - FILL_INSET[3] * k, FRAMED_H * k - FILL_INSET[4] * k
    end)
  end
  -- selection ring, glued: Layout offsets put the ring sprite's interior window (tools/preview/artbox.mjs artWindow) exactly on the rim art's outer box (alpha >= 128), see ringGap in barcheck.mjs
  s.barSel = ring(f, "OVERLAY", ART_SEL, 12)

  -- level box: 23.5 x 24.5 beside the rim art, its top level with the rim
  s.level = CreateFrame("Frame", nil, f)
  s.lv = s.level
  s.flv = f:CreateTexture(nil, "BACKGROUND"); sprite(s.flv, ART_LV)
  s.levelSel = ring(f, "BACKGROUND", ART_LVSEL, 12)
  s.levelText = f:CreateFontString(nil, "OVERLAY")
  s.skull = f:CreateTexture(nil, "OVERLAY"); sprite(s.skull, ART_SKULL)

  -- the name inside the bar, left aligned, white, outlined, cut with "..." (unitframe.lua:768-780, camelot overrides)
  s.name = f:CreateFontString(nil, "OVERLAY")
  s.name:SetJustifyH("LEFT")
  if s.name.SetWordWrap then s.name:SetWordWrap(false) end

  -- raid icon (xml:186-194, unitframe.lua:845-860) left of the art; 2.4.3 passes Blizzard's own region
  if not raid then
    raid = f:CreateTexture(nil, "ARTWORK")
    raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
  end
  s.raid = raid
  s.class = f:CreateTexture(nil, "OVERLAY") -- classification x 0.8 (Small)
  s.class:Hide()

  -- cast bar under the health bar: black edge, dark back, solid fill, icon and spell name below
  local c = CreateFrame("Frame", nil, s.castBox)
  c:SetAllPoints(s.castBox); c:Hide()
  s.cast, c.skin = c, s
  s.castBar = CreateFrame("Frame", nil, c)
  s.cedge = solid(f, "BACKGROUND", 0, 0, 0, 1)
  local cbg = solid(f, "BACKGROUND", 0.12, 0.12, 0.12, 1)
  cbg:SetAllPoints(s.castBar)
  s.castFill = solid(f, "ARTWORK", 1, 0.7, 0)
  s.castIcon = f:CreateTexture(nil, "OVERLAY")
  s.shield = f:CreateTexture(nil, "OVERLAY")
  AFUI.SetAtlas(s.shield, "nameplates-InterruptShield")
  s.castText = f:CreateFontString(nil, "OVERLAY")
  s.castRegions = { s.cedge, cbg, s.castFill, s.castIcon, s.shield, s.castText }
  layout(s, 1)
  showCast(s, false)
  if AFUI.NameplateAuras then AFUI.NameplateAuras.Attach(s, s.fbg) end
  return s
end

-- Every size, offset and font of the plate at scale k (the selected plate is 1.17): nothing is scaled by the frame, so every sprite is drawn
-- from its 2x pixels at its final size and the text is laid out at its final size.
layout = function(s, k)
  s.k = k
  s.frame:SetWidth(W * k); s.frame:SetHeight(PLATE_H * k)
  s.castBox:SetHeight((CAST_H + CAST_TEXT_H) * k)
  s.castBox:ClearAllPoints()
  s.castBox:SetPoint("BOTTOMLEFT", s.frame, "BOTTOMLEFT", INSET * k, 0); s.castBox:SetPoint("BOTTOMRIGHT", s.frame, "BOTTOMRIGHT", -INSET * k, 0)
  local hp = s.hp
  hp:SetWidth(FRAMED_W * k); hp:SetHeight(FRAMED_H * k)
  hp:ClearAllPoints(); hp:SetPoint("BOTTOM", s.castBox, "TOP", 0, 5 * k)
  s.fbg:SetWidth(s.bgW * k); s.fbg:SetHeight(s.bgH * KY * k)
  s.fbg:ClearAllPoints(); s.fbg:SetPoint("TOPLEFT", hp, "TOPLEFT", -BG_PAD * k, BG_PAD * KY * k)
  s.deselected:ClearAllPoints()
  s.deselected:SetPoint("TOPLEFT", hp, "TOPLEFT", 0, KY * k); s.deselected:SetPoint("BOTTOMRIGHT", hp, "BOTTOMRIGHT", 0, -0.8 * KY * k)
  s.barSel:Layout(s.fbg, -2.5 * k, 1.255 * k, -0.5 * k, 4.205 * k, RING_CORNER * k) -- RING_HUG: the ring window = the rim art box

  local lv = s.level
  lv:SetWidth(LEVEL_W * k); lv:SetHeight(LEVEL_H * k)
  lv:ClearAllPoints(); lv:SetPoint("TOPLEFT", s.fbg, "TOPRIGHT", LEVEL_DX * k, LEVEL_DY * k)
  s.flv:ClearAllPoints(); s.flv:SetAllPoints(lv)
  s.levelSel:Layout(lv, -1.321 * k, 0.83 * k, 1.321 * k, -0.716 * k, RING_CORNER * k) -- RING_HUG
  s.levelText:SetFont(FONT, LEVEL_FONT * k, "OUTLINE"); s.levelText:ClearAllPoints(); s.levelText:SetPoint("CENTER", lv, "CENTER", 0, 0)
  s.skull:SetWidth(18 * k); s.skull:SetHeight(18 * k); s.skull:ClearAllPoints(); s.skull:SetPoint("CENTER", lv, "CENTER", 0, 0)

  s.name:SetFont(FONT, NAME_SIZE * k, "OUTLINE")
  s.name:SetWidth(NAME_W * k); s.name:SetHeight(14 * k) -- one fixed line: names are cut to it (setName), never wrapped
  s.name:ClearAllPoints(); s.name:SetPoint("LEFT", hp, "LEFT", NAME_PAD * k, 0)
  if s.text then AFUI.FitText(s.name, s.text, NAME_W * k) end

  local raid = s.raid
  raid:ClearAllPoints(); raid:SetWidth(22 * k); raid:SetHeight(22 * k); raid:SetPoint("RIGHT", s.fbg, "LEFT", 0, 0)
  s.class:SetWidth(16 * k); s.class:SetHeight(16 * k); s.class:ClearAllPoints(); s.class:SetPoint("RIGHT", raid, "LEFT", 0, 0)

  local cb = s.castBar
  cb:SetHeight(CAST_H * k); cb:ClearAllPoints()
  cb:SetPoint("BOTTOMLEFT", s.castBox, "BOTTOMLEFT", 0, ICON * k); cb:SetPoint("BOTTOMRIGHT", s.castBox, "BOTTOMRIGHT", 0, ICON * k)
  s.cedge:ClearAllPoints(); s.cedge:SetPoint("TOPLEFT", cb, "TOPLEFT", -k, k); s.cedge:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", k, -k)
  s.castFill:SetHeight(CAST_H * k); s.castFill:ClearAllPoints(); s.castFill:SetPoint("LEFT", cb, "LEFT", 0, 0)
  s.castIcon:SetWidth(ICON * k); s.castIcon:SetHeight(ICON * k); s.castIcon:ClearAllPoints(); s.castIcon:SetPoint("BOTTOMLEFT", s.castBox, "BOTTOMLEFT", 0, 0)
  s.shield:SetWidth(10 * k); s.shield:SetHeight(12 * k); s.shield:ClearAllPoints(); s.shield:SetPoint("RIGHT", s.castIcon, "RIGHT", 0, 0)
  s.castText:SetFont(FONT, CAST_TEXT_H * k, "OUTLINE"); s.castText:ClearAllPoints(); s.castText:SetPoint("LEFT", s.castIcon, "RIGHT", 2 * k, 0)
  if s.castName then AFUI.FitText(s.castText, s.castName, (BAR_W - ICON - 2) * k) end
  if s.hmax then setHealth(s, s.hcur, s.hmax) end
  if s.cast:IsShown() and s.startMS then castTick(s.cast) end
end

-- The name, cut with "..." to the trough width (a fixed one-line box does not wrap on either client).
setName = function(s, text)
  s.text = text or ""
  AFUI.FitText(s.name, s.text, NAME_W * s.k)
end

setHealth = function(s, cur, max)
  s.hcur, s.hmax = cur, max
  local frac = max > 0 and math.min(math.max(cur / max, 0), 1) or 0
  local k = s.k
  -- the fill is pinned inside the rim art's trough (the preview checks it against the art, barcheck.mjs); the shaded bar texture is cropped to the fraction
  AFUI.Bar.Place(s.fill, s.hp, { 0, FILL_INSET[2] * k, FILL_INSET[3] * k, FILL_INSET[4] * k }, frac, ART_BAR, nil,
    { w = FRAMED_W * k, fa = s.fbg, grow = { 0, FILL_GROW[2] * k, 0, FILL_GROW[4] * k } })
  if s.fill:IsShown() then
    local e = AFUI_ATLAS[ART_BAR]
    s.fill:SetTexCoord(e[4] + TEXEL, e[4] + TEXEL + (e[5] - e[4] - TEXEL) * frac, e[6] + TEXEL, e[7])
    if s.r then s.fill:SetVertexColor(s.r, s.g, s.b) end
  end
end

-- the colour is the tint of the shaded bar texture (the texture's own brightness stays under it, as in Forever)
local function setColors(s, r, g, b, nameGrey)
  s.r, s.g, s.b = r, g, b
  s.fill:SetVertexColor(r, g, b)
  s.nameR = nameGrey and 0.5 or 1
  s.name:SetTextColor(s.nameR, s.nameR, s.nameR)
end

local function setLevel(s, skull, text, r, g, b)
  if skull then s.skull:Show(); s.levelText:Hide() else s.skull:Hide(); s.levelText:Show() end
  s.levelText:SetText(text); s.levelText:SetTextColor(r, g, b)
end

-- Zoom: at rest (z == zGoal) the plate is laid out exactly at k = z with scale 1 (pixel-identical to the static layout); while it moves, the plate stays laid out at
-- k = 1 and the plate frame (anchored CENTER to the host, so it grows around its middle) is scaled by z: one uniform transform, no per-step relayout, no snapping sizes.
-- The aura row is counter-scaled so the icons do not grow with it.
local active, driver = {}, nil
local function applyZoom(s)
  local z = s.z
  if z == s.zGoal then
    if s.scaled then s.frame:SetScale(1); if s.auras then s.auras:SetScale(1) end; s.scaled = false end
    if s.k ~= z then layout(s, z) end
  else
    if s.k ~= 1 then layout(s, 1) end
    s.frame:SetScale(z); s.scaled = true
    if s.auras then s.auras:SetScale(1 / z) end
  end
end

-- selection fade: rings in, dark overlay out
local function applySel(s)
  local a = s.sel
  for _, t in ipairs({ s.barSel, s.levelSel }) do
    if a > 0 then t:Show(); t:SetAlpha(a) else t:Hide() end
  end
  if a < 1 then s.deselected:Show(); s.deselected:SetAlpha(1 - a) else s.deselected:Hide() end
end

-- a recycled / hidden plate starts again from rest: no animation left behind, the next setTarget lands without one
function NP.ResetZoom(s, z)
  active[s] = nil
  s.z, s.zGoal, s.fresh = z or 1, z or 1, z == nil
  if z == nil then s.sel, s.selGoal = 0, 0 end
  applyZoom(s); applySel(s)
end

-- the one shared driver: steps only the plates that are moving, and sleeps when none is
function NP.Step(dt)
  for s in pairs(active) do
    if s.host.IsShown and not s.host:IsShown() then NP.ResetZoom(s)
    else
      s.z = NP.ZoomStep(s.z, s.zGoal, dt); s.sel = NP.FadeStep(s.sel, s.selGoal, dt)
      applyZoom(s); applySel(s)
      if s.z == s.zGoal and s.sel == s.selGoal then active[s] = nil end
    end
  end
  if next(active) == nil and driver then driver:SetScript("OnUpdate", nil) end
end

local function activate(s)
  active[s] = true
  driver = driver or CreateFrame("Frame")
  driver:SetScript("OnUpdate", function(_, dt) NP.Step(dt) end)
end

-- healthbar.lua:90-116 + camelot level frame :55-71: atlas rings tinted white (target) / orange (focus), faded in and out; the selected plate zooms to TargetScale (animated)
local function setTarget(s, isTarget, isFocus)
  s.isTarget = isTarget
  local c = isTarget and TARGET or FOCUS
  local on = isTarget or isFocus
  if on then for _, t in ipairs({ s.barSel, s.levelSel }) do t:SetVertexColor(c[1], c[2], c[3]) end end
  s.selGoal, s.zGoal = on and 1 or 0, isTarget and NP.TargetScale() or 1
  if s.fresh then s.fresh, s.z, s.sel = nil, s.zGoal, s.selGoal; active[s] = nil end
  if s.z ~= s.zGoal or s.sel ~= s.selGoal then activate(s) end
  applyZoom(s); applySel(s)
end

castTick = function(c)
  local s = c.skin
  local frac, remaining = AFUI.CastProgress(s.startMS, s.endMS, GetTime() * 1000, s.channel)
  AFUI.Bar.Place(s.castFill, s.castBar, NO_INSET, frac, nil, nil, { w = BAR_W * s.k, rim = { tex = s.cedge, px = s.k } })
  if remaining <= 0 then c:SetScript("OnUpdate", nil); showCast(s, false) end
end

-- One handler for every cast event: show what the unit is casting now, or hide.
local function syncCast(s, unit)
  local name, icon, startMS, endMS, channel = AFUI.CastingInfo(unit)
  if not name then s.cast:SetScript("OnUpdate", nil); showCast(s, false); return end
  s.startMS, s.endMS, s.channel = startMS, endMS, channel
  local col = channel and CHANNEL_COLOR or CAST_COLOR
  AFUI.SetColor(s.castFill, col[1], col[2], col[3], 1)
  s.castIcon:SetTexture(icon)
  s.castIcon:Show(); s.shield:Hide()
  s.castName = name
  AFUI.FitText(s.castText, name, (BAR_W - ICON - 2) * s.k) -- the spell name stays under the bar
  showCast(s, true); s.shield:Hide(); s.cast:SetScript("OnUpdate", castTick); castTick(s.cast)
end

local skinFor -- unit -> skin, per client

---------------------------------------------------------------------------------------------- 2.5.3
local byUnit = {}

-- CUF:644-711 order (threat-colour CVar left out)
local function unitColor(u)
  if not UnitIsConnected(u) or (UnitIsDead(u) and not UnitIsPlayer(u)) then return 0.5, 0.5, 0.5 end
  if UnitIsPlayer(u) and UnitIsFriend("player", u) then return FRIEND_PLAYER[1], FRIEND_PLAYER[2], FRIEND_PLAYER[3] end
  if UnitIsTapDenied(u) then return 0.9, 0.9, 0.9 end
  if not UnitIsFriend("player", u) and UnitThreatSituation("player", u) then return 1, 0, 0 end
  return UnitSelectionColor(u, true)
end

local function health253(s)
  local u = s.unit
  local r, g, b = unitColor(u)
  setColors(s, r, g, b, UnitIsTapDenied(u) or (UnitIsDead(u) and not UnitIsPlayer(u)))
  setHealth(s, UnitHealth(u), UnitHealthMax(u))
end

local function refresh253(s)
  local u = s.unit
  health253(s)
  setName(s, UnitName(u))
  local level = UnitLevel(u)
  local r, g, b = unpack(NON_ATTACKABLE)
  setLevel(s, level <= 0, level, r, g, b) -- the video: a gold number in the level box, not coloured by difficulty
  if UnitCanAttack("player", u) then r, g, b = AFUI.LevelColor(level) end
  local idx = GetRaidTargetIndex(u)
  if idx then SetRaidTargetIconTexture(s.raid, idx); s.raid:Show() else s.raid:Hide() end
  local a = UnitCanAttack("player", u) and CLASSIFICATION[UnitClassification(u)]
  if a then AFUI.SetAtlas(s.class, a); s.class:Show() else s.class:Hide() end
  setTarget(s, UnitIsUnit(u, "target"), UnitIsUnit(u, "focus"))
  s.activeAura = true
  if AFUI.NameplateAuras then AFUI.NameplateAuras.Update(s, u) end
end

-- A protected plate frame cannot be hidden in combat (the client blocks it and names this addon): make it see-through instead.
local function hideUnitFrame(uf)
  if InCombatLockdown() and uf.IsProtected and uf:IsProtected() then uf:SetAlpha(0) else uf:Hide() end
end

-- NAME_PLATE_UNIT_ADDED fires the moment the client gives a unit a plate: the skin is built and filled in that handler.
local function added(_, unit)
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not plate then return end
  local s = plate.afuiSkin
  if not s then
    s = build(plate)
    plate.afuiSkin = s
    local uf = plate.UnitFrame
    if uf then hideUnitFrame(uf); uf:HookScript("OnShow", hideUnitFrame) end
  end
  if s.unit then byUnit[s.unit] = nil end
  s.unit, byUnit[unit] = unit, s
  NP.ResetZoom(s)
  refresh253(s)
  syncCast(s, unit)
end

local function setup253()
  skinFor = function(unit) return byUnit[unit] end
  AFUI.On("NAME_PLATE_UNIT_ADDED", added)
  AFUI.On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
    local s = byUnit[unit]
    if not s then return end
    byUnit[unit], s.unit = nil, nil
    s.cast:SetScript("OnUpdate", nil); showCast(s, false)
    s.activeAura = false
    NP.ResetZoom(s)
    if AFUI.NameplateAuras then AFUI.NameplateAuras.Clear(s) end
  end)
  AFUI.On("UNIT_AURA", function(_, unit) local s = byUnit[unit]; if s and AFUI.NameplateAuras then AFUI.NameplateAuras.OnAura(s, unit) end end)
  local function onUnit(fn) return function(_, unit) local s = byUnit[unit]; if s then fn(s) end end end
  for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do AFUI.On(e, onUnit(health253)) end
  for _, e in ipairs({ "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_THREAT_LIST_UPDATE",
    "UNIT_CLASSIFICATION_CHANGED", "UNIT_CONNECTION" }) do AFUI.On(e, onUnit(refresh253)) end
  local function all() for _, s in pairs(byUnit) do refresh253(s) end end
  for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "RAID_TARGET_UPDATE" }) do AFUI.On(e, all) end
  for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
    if plate.namePlateUnitToken then added(nil, plate.namePlateUnitToken) end
  end
end

---------------------------------------------------------------------------------------------- 2.4.3
-- Plate signature and region order from ShaguPlates (compat/tbc.lua NAMEPLATE_OBJECTORDER, modules/nameplates.lua
-- IsNamePlate) and ElvUI-TBC (modules/nameplates/nameplates.lua OnCreated): children = health, cast StatusBar;
-- regions = border, cast border, cast icon, glow, name, level, boss skull, raid icon.
local skins243, dirty, targetSkin = {}, 0, nil

local function isBorder(r) return r and r:GetObjectType() == "Texture" and r:GetTexture() == BORDER end
local function isPlate(f)
  if f:GetName() or not f.GetRegions then return false end
  local a, b = f:GetRegions()
  return isBorder(a) or isBorder(b) -- ShaguPlates checks the first region, ElvUI-TBC the second
end

-- ShaguPlates DisableObject: blank, don't hide (the client re-shows its own regions).
local function blank(o)
  local t = o:GetObjectType()
  if t == "Texture" then o:SetTexture(""); o:SetTexCoord(0, 0, 0, 0)
  elseif t == "FontString" then o:SetWidth(0.001)
  elseif t == "StatusBar" then o:SetStatusBarTexture("") end
end

local function refresh243(s)
  local bar = s.bar
  local _, max = bar:GetMinMaxValues()
  local r, g, b = bar:GetStatusBarColor()
  local tapped = math.abs(r - g) < 0.01 and math.abs(g - b) < 0.01 -- the client greys tapped mobs
  if tapped then r, g, b = 0.9, 0.9, 0.9 end
  local friendPlayer = r < 0.15 and g < 0.15 and b > 0.85 -- the client's blue player plate
  if friendPlayer then r, g, b = FRIEND_PLAYER[1], FRIEND_PLAYER[2], FRIEND_PLAYER[3] end
  -- no unit API: friendly plates are green (NPC) or blue (player), the rest (red, yellow, orange, grey) get the framed look
  setColors(s, r, g, b, tapped)
  setHealth(s, bar:GetValue(), max)
end

local function plateText(s)
  setName(s, s.blizzName:GetText())
  setLevel(s, s.blizzSkull:IsShown(), s.blizzLevel:GetText(), s.blizzLevel:GetTextColor())
end

local function skin243(plate)
  local regions = { plate:GetRegions() }
  local health, castbar = plate:GetChildren()
  local s = build(plate, regions[#regions])
  plate.afuiSkin = s
  s.bar = health
  local fonts = {}
  for i = 1, #regions - 1 do -- the raid icon (last) stays, re-anchored by build
    local r = regions[i]
    if r:GetObjectType() == "FontString" then fonts[#fonts + 1] = r end
    blank(r)
  end
  s.blizzName, s.blizzLevel, s.blizzSkull = fonts[1], fonts[2], regions[#regions - 1]
  blank(health); if castbar then blank(castbar) end
  health:HookScript("OnValueChanged", function() refresh243(s) end)
  plate:HookScript("OnShow", function() refresh243(s); plateText(s); dirty = 2 end)
  refresh243(s); plateText(s); setTarget(s, false)
  skins243[#skins243 + 1] = s
  dirty = 2
end

-- The client sets non-target plates' alpha below 1 while something is targeted (ShaguPlates, ElvUI-TBC). The client changes the
-- alpha a frame after the target does, so the check runs on two frames in a row.
local function retarget()
  dirty = dirty - 1
  local hasTarget = UnitExists("target")
  local new
  for _, s in ipairs(skins243) do
    local t = hasTarget and s.host:IsShown() and s.host:GetAlpha() > 0.99 or false
    if t then new = s end
    if t ~= s.isTarget then setTarget(s, t) end
  end
  if targetSkin and targetSkin ~= new then targetSkin.cast:SetScript("OnUpdate", nil); showCast(targetSkin, false) end
  targetSkin = new
  if new then syncCast(new, "target") end
  if AFUI.NameplateAuras then
    for _, s in ipairs(skins243) do
      if s == new then s.activeAura = true; AFUI.NameplateAuras.Update(s, "target") elseif s.activeAura then s.activeAura = false; AFUI.NameplateAuras.Clear(s) end
    end
  end
end

local function setup243()
  skinFor = function(unit) return unit == "target" and targetSkin or nil end
  local seen = 0
  local scanner = CreateFrame("Frame")
  scanner.isNameplateScanner = true
  -- Every frame: one GetNumChildren compare. A new plate is a new WorldFrame child, so it is skinned the frame it appears;
  -- the children are only listed when the count changed.
  scanner:SetScript("OnUpdate", function()
    local n = WorldFrame:GetNumChildren()
    if n ~= seen then
      local kids = { WorldFrame:GetChildren() }
      for i = seen + 1, n do
        local f = kids[i]
        if f and not f.afuiSkin and isPlate(f) then skin243(f) end
      end
      seen = n
    end
    if dirty > 0 then retarget() end
  end)
  AFUI.On("PLAYER_TARGET_CHANGED", function() dirty = 2 end)
  AFUI.On("UNIT_AURA", function(_, unit) if unit == "target" and targetSkin and AFUI.NameplateAuras then AFUI.NameplateAuras.OnAura(targetSkin, "target") end end)
end

function AFUI.SetupNameplates()
  if IS_243 then setup243() else setup253() end
  AFUI.OnSettingChanged("nameplateTargetScale", function() -- the plate under the target takes the new size at once
    for _, list in ipairs({ byUnit, skins243 }) do
      for _, s in pairs(list) do if s.isTarget then NP.ResetZoom(s, NP.TargetScale()) end end
    end
  end)
  for _, e in ipairs(CAST_EVENTS) do
    AFUI.On(e, function(_, unit) local s = skinFor(unit); if s then syncCast(s, unit) end end)
  end
end

AFUI.RegisterModule("Nameplates", { OnLogin = AFUI.SetupNameplates })
