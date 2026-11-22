-- Player, target, target-of-target, pet and party frames: a port of WoW: Forever's camelot unit frames
-- (docs/forever-ref/unitframes.md; `UF/` below = blizzard_unitframe/). Every offset is Forever's, converted to the
-- frame's TOPLEFT (y negative). "Show Portrait" off (ours; Forever has no such option) crops the portrait ring off
-- the same c60 art and keeps the bars where they are.
AFUI = AFUI or {}
AFUI.Units = {}

-- What differs between 2.4.3 and 2.5.3 for these frames.
local V
if AFUI.IS_243 then
  V = {
    textMode = function() return GetCVar("statusTextPercentage") == "1" and "PERCENT" or "NUMERIC" end,
    tapDenied = function(u) return UnitIsTapped(u) and not UnitIsTappedByPlayer(u) end,
    threat = function() end, -- no threat API before 3.0
    -- only your own auras carry a duration in 2.4.3; no caster or stealable flag
    auraInfo = function(_, _, _, duration) return duration ~= nil end,
    EVENTS = { "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE", "UNIT_HAPPINESS" },
    -- FrameXML CombatFeedback_* read the global `this` in 2.4.3
    feedback = function(fn, obj, ...) local old = this; this = obj; fn(...); this = old end,
  }
else
  V = {
    textMode = function() return GetCVar("statusTextDisplay") or "NUMERIC" end,
    tapDenied = function(u) return UnitIsTapDenied(u) end,
    threat = function(unit, mob)
      local s
      if mob then s = UnitThreatSituation(unit, mob) else s = UnitThreatSituation(unit) end
      if s and s > 0 then return GetThreatStatusColor(s) end
    end,
    auraInfo = function(unit, i, filter)
      local _, _, _, _, _, _, src, stealable, _, _, _, _, byPlayer = UnitAura(unit, i, filter)
      return src == "player" or src == "pet" or src == "vehicle", stealable, byPlayer
    end,
    EVENTS = { "UNIT_CONNECTION", "UNIT_THREAT_SITUATION_UPDATE" },
    feedback = function(fn, obj, ...) fn(obj, ...) end,
  }
end

local P = "ui-hud-unitframe-"
local KEYS = { "player", "target", "targettarget", "pet", "party1", "party2", "party3", "party4" }
local BLIZZARD = { "PlayerFrame", "TargetFrame", "TargetofTargetFrame", "PetFrame", "ComboFrame",
  "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" }
local DROPDOWN = { player = "PlayerFrameDropDown", target = "TargetFrameDropDown", pet = "PetFrameDropDown" }
local POWER = { [0] = "mana", "rage", "focus", "energy" } -- PowerBarColor atlasElementName (powerbarcolorutil.lua:18-21)
local BADGE_R = 19.5 -- the level circle (smallcircle) is 39 px
local BADGE_VIS = 15.5 -- its opaque disc (alpha >= 200, tools/preview/artbox.mjs): 4..35 of 39 px, so 4 px of padding ring the 31 px disc
-- Transparent texels at the { left, right } of each PvP sprite (alpha < 200 columns, artbox.mjs): the visible flag, not the texture box, touches the badge.
local FLAG_PAD = { ["smallcircle-horde"] = { 4, 3 }, ["smallcircle-alliance"] = { 3, 3 }, ["player-pvp-hordeicon"] = { 5, 7 },
  ["player-pvp-allianceicon"] = { 2, 6 }, ["player-pvp-ffaicon"] = { 2, 5 } }
local FLAG_OVERLAP = 0.5 -- the flag's inner edge reaches this far (u) into the badge's disc
local PARTY_GAP = 63 -- 53 high + PartyFrame spacing 10 (UF/shared/partyframe.lua:150-156)

-- Layouts. art/flash/status = { atlas, x, y }; hp/mp = { win = { x0, y0, x1, y1 } (the interior of the frame art, see paint), text = { centreX, y, leftX, rightX } };
-- name = { point, x, y, w, h, justifyH }; level = level-circle centre; crop = { left, width } of the art kept with the
-- portrait off. Sources: UF/mainline/playerframe.xml + camelot/playerframe.lua; targetframe.xml + camelot/targetframe.lua;
-- petframe.xml + camelot/petframe.lua; partyframetemplates.xml + camelot/partymemberframe.lua.
local SMALL = { w = 120, h = 49, type = "targetoftarget", crop = { 42, 78 }, portrait = { 5, -5, 37 },
  art = { "targetoftarget-portraiton", 0, 0 }, name = { "TOPLEFT", 44, -6, 68, 10, "CENTER" } }
local LAYOUT = {
  player = { w = 232, h = 100, type = "player", insets = { 6, 0, 4, 9 }, crop = { 67, 131 },
    portrait = { 24, -19, 60 }, art = { "player-portraiton", 17, -14.5 },
    flash = { "player-portraiton-incombat", 17, -14.5 }, status = { "player-portraiton-status", 17, -14 },
    name = { "CENTER", 149, -37, 116, 12, "CENTER" },
    hp = { win = { 89, 46.5, 208, 59.5 }, text = { 149, -53.5, 89, 209 } }, mp = { win = { 89, 63.5, 208, 70.5 }, text = { 149, -66, 89, 209 } },
    level = { 32.5, -73.5 }, leader = { 86, -10 }, pvp = { "TOP", "TOPLEFT", 22, -65, 0.8, w = 24 }, hitText = { "CENTER", 54, -50 } },
  target = { w = 232, h = 100, type = "target", insets = { 0, 5, 4, 9 }, crop = { 0, 130 }, zeroText = "",
    portrait = { 148, -19, 58 }, art = { "target-portraiton", 19, -16 }, rare = { "target-rare-portraiton", 20, -16.5, hp = { win = { 24, 40.5, 147, 58.5 } }, mp = { win = { 24, 61.5, 154, 69.5 } } },
    flash = { "target-portraiton-incombat", 19, -15.5 }, rep = { 15, -26 },
    name = { "TOPLEFT", 24, -30, 117, 12, "CENTER" },
    hp = { win = { 25, 45, 144, 58 }, text = { 84, -51.5, 23, 144 } }, mp = { win = { 25, 61, 144, 69 }, text = { 84, -65, 23, 144 } },
    level = { 199.5, -73.5 }, leader = { 131, -8 }, pvp = { "TOP", "TOPRIGHT", -24, -65, 0.8, w = 24 }, raid = { 177, -19 },
    dead = { 84, -51.5 }, auras = { 24, -75 }, combo = { 179, -46 }, tint = true },
  targettarget = setmetatable({ hp = { win = { 47, 20, 114, 28 } }, mp = { win = { 47, 31, 113, 36 } }, dead = { 80, -23 }, tint = true,
    totDebuffs = { { 124, -10 }, { 137, -10 }, { 124, -23 }, { 137, -23 } } }, { __index = SMALL }),
  pet = setmetatable({ insets = { 7, 66, 6, 7 },
    flash = { "targetoftarget-portraiton-incombat", 0, 0 }, status = { "targetoftarget-portraiton-status", 0, 0 },
    hp = { win = { 47, 20, 114, 28 }, text = { 80, -23, 45, 115 } }, mp = { win = { 47, 31, 113, 36 }, text = { 82.5, -33, 46, 119 } },
    smallAuras = { 48, -42 }, hitText = { "TOPLEFT", 5, -5 } }, { __index = SMALL }),
  party = { w = 120, h = 53, type = "party", crop = { 42, 78 }, portrait = { 7, -6, 37 }, art = { "party-portraiton", 1, -2 },
    flash = { "party-portraiton-incombat", 1, -1 }, status = { "party-portraiton-status", -1, -1 },
    name = { "TOPLEFT", 48, -7, 55, 12, "LEFT" },
    -- the status texts are 8 px high (the bars are 8 and 5) and stay inside the bar windows: 1 px in at both ends, 9 px between the rows
    hp = { win = { 48, 22, 115, 30 }, text = { 81.5, -26, 49, 114 } }, mp = { win = { 48, 33, 115, 38 }, text = { 81.5, -35.5, 49, 114 } },
    zeroText = "", dead = { 81.5, -26 }, disc = { 25.5, -24.5, 40 }, -- the offline plug: 40 px on the portrait
    leader = { 42, 10 }, pvp = { "CENTER", "TOPLEFT", 24, -68, 0.6, party = true, w = 44 }, smallAuras = { 48, -43 }, tint = true },
}
-- Elite/rare/boss art around the target portrait: atlas, TOPRIGHT offset (UF/camelot/targetframeutils.lua:9-19).
-- Forever has no portrait-off target frame, so with the portrait off the same dragon sprite is cut in three (head / body / tail, `cut` =
-- the sprite rows where the head ends and the tail starts; `inner` = the column where the body's inner edge runs, measured from the
-- sprite's pixels with tools/preview/measure-sprite.mjs) and wrapped round the right end of the frame instead of the portrait.
local BOSS = { elite = { "target-portraiton-boss-gold", 0, 1, cut = { 33, 72 }, inner = 70 },
  rare = { "target-portraiton-boss-rare-silver-winged", 8, -7, cut = { 26, 63 }, inner = 71 },
  worldboss = { "target-portraiton-boss-gold-winged", 11, -4, cut = { 30, 68 }, inner = 69 } }
BOSS.rareelite = BOSS.rare

-- The classification art class of a unit: UnitClassification (elite, rare, rareelite, worldboss; normal, trivial, minus have none);
-- a boss level (-1, the skull) on an elite or world boss is the gold winged one.
local function bossClass(unit)
  local c = UnitClassification(unit)
  if (c == "elite" or c == "worldboss") and UnitLevel(unit) == -1 then return "worldboss" end
  return c
end

-- The three pieces { x, y, rows from, rows to } (frame coordinates of the piece's TOPLEFT, y down negative; sprite rows) of a dragon `b` wrapped
-- round the closed right end of the portrait-off frame `g`: the arc's inner edge touches the frame's end, the head lies over the top
-- border (HEAD_IN px in), the tail under the bottom border, the body between them stretched to meet both.
local HEAD_IN, TAIL_BELOW, END_IN = 14, 5, 4
function AFUI.BossRectPieces(g, n, b)
  local e, art = AFUI_ATLAS[n], AFUI_ATLAS[g.art[1]]
  local x, w = AFUI.ClosedEndRect(g)
  local left = x + w - b.inner - END_IN -- the arc overlaps the frame end by END_IN px (the combo sockets sit on its body)
  local top, bottom = g.art[3], g.art[3] - art[3] -- the frame art's top and bottom edges
  local headY, tailY = top - HEAD_IN, bottom - TAIL_BELOW -- where the head's last row and the tail's last visible row (7 px up from the sprite's end) land
  local c1, c2 = b.cut[1], b.cut[2]
  local tailBottom = tailY - 7 -- the sprite's last row (its art ends 7 rows earlier)
  local tailTop = tailBottom + (e[3] - c2)
  return { { left, headY + c1, 0, c1 }, { left, headY, c1, c2 }, { left, tailTop, c2, e[3] }, w = e[2], bodyH = headY - tailTop }
end

function AFUI.BossRect(parts, f, g, n, b)
  local e, pcs = AFUI_ATLAS[n], AFUI.BossRectPieces(g, n, b)
  for i, t in ipairs(parts) do
    local p = pcs[i]
    local h = i == 2 and pcs.bodyH or p[4] - p[3]
    t:SetTexture(e[1])
    t:SetTexCoord(e[4], e[5], e[6] + (e[7] - e[6]) * p[3] / e[3], e[6] + (e[7] - e[6]) * p[4] / e[3])
    t:SetWidth(e[2]); t:SetHeight(h); t.afuiAtlas = n; t.rows = { p[3], p[4] }
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", f, "TOPLEFT", p[1], p[2])
    t:Show()
  end
end

-- The -c60 member Forever draws, when the atlas has one.
local function c60(name) return AFUI_ATLAS[name .. "-c60"] and name .. "-c60" or name end

function AFUI.UnitFrameGeometry(key, showPortrait)
  local L = LAYOUT[key:match("^party%d$") and "party" or key]
  local g = setmetatable({ off = showPortrait == false }, { __index = L })
  g.art = { c60(P .. L.art[1]), L.art[2], L.art[3] }
  if g.off then
    g.portrait = false
    local x, w, left = AFUI.ClosedEndRect(g)
    local edge = x and (left and x or x + w) or L.art[2] + (L.crop[1] > 0 and L.crop[1] or L.crop[2]) -- the outer edge of the closed end
    local dir = L.crop[1] > 0 and -1 or 1 -- the side the portrait was on: outward
    local reach = edge -- how far the frame's decorations reach outward (the Edit Mode box takes it in)
    if L.level then g.level = { edge, L.level[2] }; reach = edge + dir * BADGE_R end
    -- Everything that sat on the portrait ring follows the cut edge: the PvP flag goes beside the level badge on its outer side (same
    -- height as with the portrait), the raid mark is centred on the edge, the combo ring keeps its distance from the outer edge.
    local p = L.pvp
    if p then
      local s, half = p[5], p.w * p[5] / 2
      local cx = edge + dir * (half + 1)
      g.pvp = { p[1], "TOPLEFT", cx / s, p[4], s, party = p.party, w = p.w }
      -- the flag's visible inner edge touches the badge's disc (overlaps it by FLAG_OVERLAP), centred on the badge's height; the exact centre
      -- depends on the sprite's padding, so UpdateIcons finishes it (AFUI.FlagCentre). Party frames have no badge: the visible edge meets the cut edge.
      g.pvpIn = L.level and edge + dir * (BADGE_VIS - FLAG_OVERLAP) or edge
      g.pvpDir = dir
      if L.level then g.pvp = { "CENTER", "TOPLEFT", (g.pvpIn + dir * (p.w - 3) * s / 2) / s, L.level[2] / s, s, party = p.party, w = p.w } end
      cx = g.pvpIn + dir * (p.w - 3) * s -- the outer edge of the widest flag texture (3 transparent texels on the inner side at least)
      reach = dir < 0 and math.min(reach, cx) or math.max(reach, cx)
    end
    -- the offline plug sits beside the cut edge (28 px, 2 px clear of it)
    if L.type == "party" then g.disc = { edge - 16, L.disc[2], 28 }; reach = dir < 0 and math.min(reach, edge - 30) or math.max(reach, edge + 30) end
    g.reach = reach
    if L.raid then g.raid = { edge, L.raid[2] } end
    if L.combo then g.combo = { L.combo[1] + edge - (L.portrait[1] + L.portrait[3]), L.combo[2] } end
  end
  return g
end

-- Centre x (frame units) of the flag sprite `name` (atlas name without prefix) at `scale` when its visible inner edge sits on g.pvpIn.
function AFUI.FlagCentre(g, name, scale)
  local e = AFUI_ATLAS[c60(P .. name)]
  local pad = (FLAG_PAD[name] or { 0, 0 })[g.pvpDir < 0 and 2 or 1]
  return g.pvpIn + g.pvpDir * (e[2] / 2 - pad) * scale
end

-- The level orb's opaque disc as a box { x0, y0, x1, y1 } (frame units, y down), or nil on frames without one.
function AFUI.OrbRect(g)
  if not g.level then return end
  local cx, cy = g.level[1], -g.level[2]
  return cx - BADGE_VIS, cy - BADGE_VIS, cx + BADGE_VIS, cy + BADGE_VIS
end

-- The x span l, r of a bar window `win` a status text with anchors `t` may use: 1 px inside the window, and 1 px clear of the level orb
-- when the orb overlaps the window's rows (the orb is on the portrait side: left for the player, right for the target).
function AFUI.StatusTextSpan(g, t, win)
  local l, r = math.max(t[3], win[1] + 1), math.min(t[4], win[3] - 1)
  local o0, o1, o2, o3 = AFUI.OrbRect(g)
  if o0 and win[2] < o3 and win[4] > o1 then
    if (o0 + o2) / 2 < (win[1] + win[3]) / 2 then l = math.max(l, o2 + 1) else r = math.min(r, o0 - 1) end
  end
  return l, r
end

function AFUI.Fraction(cur, max)
  if not max or max <= 0 then return 0 end
  local f = (cur or 0) / max
  return f < 0 and 0 or f > 1 and 1 or f
end

local function breakUp(n) -- BreakUpLargeNumbers (2.4.3 has none)
  local s, k = tostring(math.floor(n)), 1
  while k > 0 do s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") end
  return s
end

-- Font size of a status text in a bar window `h` px high: the digits (0.72 of the size in FRIZQT) plus the 1 px outline fit the window, never
-- above the 10 px of Forever's TextStatusBarText nor below 6 (windows of 13 -> 10, 8 -> 9, 7 -> 8, 5 -> 6). The frame's scale scales bars
-- and text alike, so the fit holds at every scale and resolution.
function AFUI.StatusTextSize(h)
  return math.max(6, math.min(10, math.floor((h - 1) / 0.72)))
end

-- Forever's TextStatusBar text (blizzard_textstatusbar/textstatusbar.lua:101-209) for a statusTextDisplay mode.
-- Returns centre, left, right text; BOTH puts the percent left (health/mana only) and the value right.
function AFUI.StatusText(value, max, mode, percentOK)
  if not max or max <= 0 then return "" end
  local pct = math.ceil(value / max * 100) .. "%"
  if mode == "PERCENT" then return pct end
  if mode == "BOTH" then return "", percentOK and pct or "", breakUp(value) end
  return breakUp(value) .. " / " .. breakUp(max)
end

local function shown(region, on) if on then region:Show() else region:Hide() end end

-- Draws atlas `name` with its TOPLEFT at (x, y) of `f`, keeping only what lies between frame x `from` and `to`.
local function draw(tex, f, name, x, y, from, to)
  local e = AFUI_ATLAS[name]
  if not e then tex:Hide(); return end
  local l, r = math.max(0, (from or x) - x), math.min(e[2], (to or x + e[2]) - x)
  tex:SetTexture(e[1])
  tex:SetTexCoord(e[4] + (e[5] - e[4]) * l / e[2], e[4] + (e[5] - e[4]) * r / e[2], e[6], e[7])
  tex:SetWidth(r - l); tex:SetHeight(e[3]); tex.afuiAtlas = name
  tex:ClearAllPoints(); tex:SetPoint("TOPLEFT", f, "TOPLEFT", x + l, y)
  tex:Show()
end

-- Portrait off: the art is cut where the ring was, which leaves a chopped end. Instead the cut ends at the bars' window and the
-- end of the frame on the other side (the border width beyond the bars) is drawn again, mirrored, as the closed end. `cap` is the
-- texture for it; returns the x range of the art that is kept. Test hook: tex.closedEnd = { x, width }.
function AFUI.ClosedEndRect(g) -- x and width of the closed end, in frame coordinates
  local e = AFUI_ATLAS[g.art[1]]
  if not e then return end
  local hp, mp = g.hp.win, g.mp.win
  if g.crop[1] > 0 then -- the portrait was on the left
    local w = g.art[2] + e[2] - math.max(hp[3], mp[3])
    return math.min(hp[1], mp[1]) - w, w, true
  end
  return math.max(hp[3], mp[3]), math.min(hp[1], mp[1]) - g.art[2], false
end

function AFUI.ClosedEnd(cap, f, g)
  local e = AFUI_ATLAS[g.art[1]]
  if not e then cap:Hide(); return end
  local x, w, left = AFUI.ClosedEndRect(g)
  local u0, u1
  if left then u0, u1 = (e[2] - w) / e[2], 1 else u0, u1 = 0, w / e[2] end
  local ua, ub = e[4] + (e[5] - e[4]) * u0, e[4] + (e[5] - e[4]) * u1
  cap:SetTexture(e[1]); cap:SetTexCoord(ub, ua, e[6], e[7]) -- flipped
  cap:SetWidth(w); cap:SetHeight(e[3]); cap.afuiAtlas = g.art[1]; cap.closedEnd = { x, w }
  cap:ClearAllPoints(); cap:SetPoint("TOPLEFT", f, "TOPLEFT", x, g.art[3])
  cap:Show()
  if left then return x + w, nil end
  return nil, x
end

-- The visible box { x0, y0, x1, y1 } of each fill sprite: the sprites carry their own transparent padding (a 20 high health fill
-- shows 13 rows). Measured from the page pixels by `node tools/preview/fit-bars.mjs --fills`; tests/tools/fitbars.test.mjs keeps it true.
local FILL = {
  ["player-portraiton-bar-health"] = { 2, 4, 122, 17 },
  ["player-portraiton-bar-mana"] = { 2, 1, 122, 9 },
  ["player-portraiton-bar-rage"] = { 2, 1, 122, 9 },
  ["player-portraiton-bar-energy"] = { 2, 1, 122, 9 },
  ["player-portraiton-bar-focus"] = { 2, 1, 122, 9 },
  ["player-portraiton-bar-runicpower"] = { 2, 1, 122, 9 },
  ["target-portraiton-bar-health"] = { 3, 4, 123, 17 },
  ["target-portraiton-bar-mana"] = { 7, 1, 127, 9 },
  ["target-portraiton-bar-rage"] = { 7, 1, 127, 9 },
  ["target-portraiton-bar-energy"] = { 7, 1, 127, 9 },
  ["target-portraiton-bar-focus"] = { 7, 1, 127, 9 },
  ["target-portraiton-bar-runicpower"] = { 7, 1, 127, 9 },
  ["targetoftarget-portraiton-bar-health"] = { 0, 0, 69, 10 },
  ["targetoftarget-portraiton-bar-mana"] = { 3, 0, 71, 4 },
  ["targetoftarget-portraiton-bar-rage"] = { 3, 0, 71, 4 },
  ["targetoftarget-portraiton-bar-energy"] = { 3, 1, 71, 6 },
  ["targetoftarget-portraiton-bar-focus"] = { 3, 1, 71, 6 },
  ["targetoftarget-portraiton-bar-runicpower"] = { 1, 0, 69, 4 },
  ["party-portraiton-bar-health"] = { 0, 0, 69, 10 },
  ["party-portraiton-bar-mana"] = { 3, 1, 71, 6 },
  ["party-portraiton-bar-rage"] = { 3, 1, 71, 6 },
  ["party-portraiton-bar-energy"] = { 3, 1, 71, 6 },
  ["party-portraiton-bar-focus"] = { 3, 1, 71, 6 },
  ["party-portraiton-bar-runicpower"] = { 3, 1, 71, 6 },
}

-- A status bar: the bar atlas cropped to `frac` from the left (what a StatusBar does). `win` = { x0, y0, x1, y1 } is the INTERIOR of
-- the frame art (the window of the sprite, measured from its pixels, in frame coordinates from the TOPLEFT, y down): the sprite is
-- scaled and placed so that its visible box is exactly the window, whatever transparent padding it has.
local function paint(tex, f, name, win, frac, frameArt)
  local e = AFUI_ATLAS[name]
  if not e then tex:Hide(); return end
  local v = FILL[(name:sub(#P + 1):gsub("%-c60$", ""))] or { 0, 0, e[2], e[3] }
  local sx, sy = (win[3] - win[1]) / (v[3] - v[1]), (win[4] - win[2]) / (v[4] - v[2])
  local x, y, w, h = win[1] - v[1] * sx, win[2] - v[2] * sy, e[2] * sx, e[3] * sy
  AFUI.Bar.Place(tex, f, { x, y, (f:GetWidth() or 0) - x - w, (f:GetHeight() or 0) - y - h }, frac, name, nil, { fa = frameArt })
end

-- An atlas icon at `scale` (a Texture scale in Forever; offsets scale with it).
local function icon(tex, f, name, point, rel, x, y, scale)
  local e = AFUI_ATLAS[name]
  if not e then tex:Hide(); return end
  AFUI.SetAtlas(tex, name)
  tex:SetWidth(e[2] * scale); tex:SetHeight(e[3] * scale)
  tex:ClearAllPoints(); tex:SetPoint(point, f, rel, x * scale, y * scale)
  tex:Show()
end

-- Forever's 0.5 s alpha pulse (UF/mainline/playerframe.lua:211-230): ramps between lo/255 and 1 at `rate`/255 a second.
local function pulse(p, dt, lo, rate)
  local t = (p.t or 0) + dt
  if t > 0.5 then p.sign = -(p.sign or -1); t = t % 0.5 end
  p.t = t
  if p.sign == 1 then return (lo + t * rate) / 255 end
  return (255 - t * rate) / 255
end

-- Cell n of the rest flipbook: 6 columns x 7 rows (the flipbook animation 2.4.3 does not have).
local function restCell(tex, n)
  local e = AFUI_ATLAS[P .. "player-rest-flipbook"]
  local col, row, cw, ch = n % 6, math.floor(n / 6), (e[5] - e[4]) / 6, (e[7] - e[6]) / 7
  tex:SetTexCoord(e[4] + col * cw, e[4] + (col + 1) * cw, e[6] + row * ch, e[6] + (row + 1) * ch)
end

local function totShown() -- UF/mainline/targetframe.lua:907-931
  return UnitExists("targettarget") and not UnitIsUnit("player", "target") and UnitHealth("target") > 0
end

local function placeTargetCastBar()
  local cb = AFUI.CastBars and AFUI.CastBars.target
  if cb then cb.place() end
end

-- Aura buttons: target (UF/shared/targetframeaurabutton.xml), party/pet (UF/shared/partyframetemplates.xml:5-41),
-- target of target (UF/mainline/targetframe.xml:9-51).
local function newAura(parent, unit, filter, countX)
  local b = CreateFrame("Button", nil, parent)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(b)
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", countX, 0)
  b.cd = CreateFrame("Cooldown", nil, b); b.cd:SetPoint("CENTER", b, "CENTER", 0, -1)
  if b.cd.SetReverse then b.cd:SetReverse(true) end
  b.border = b:CreateTexture(nil, "OVERLAY")
  if filter == "HARMFUL" then
    b.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
    b.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    b.border:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1); b.border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
  else
    b.border:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Stealable"); b.border:SetBlendMode("ADD")
    b.border:SetWidth(24); b.border:SetHeight(24); b.border:SetPoint("CENTER", b, "CENTER", 0, 0)
  end
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    if filter == "HARMFUL" then GameTooltip:SetUnitDebuff(unit, self.auraIndex) else GameTooltip:SetUnitBuff(unit, self.auraIndex) end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function scan(unit, filter, max)
  local list = {}
  for i = 1, max do
    local name, tex, count, duration, expires, dtype = AFUI.UnitAura(unit, i, filter)
    if not name then break end
    local mine, stealable, byPlayer = V.auraInfo(unit, i, filter, duration)
    list[#list + 1] = { index = i, icon = tex, count = count, duration = duration, expires = expires, dtype = dtype,
      mine = mine, stealable = stealable, byPlayer = byPlayer }
  end
  return list
end

local function debuffColor(dtype)
  return DebuffTypeColor and (DebuffTypeColor[dtype or "none"] or DebuffTypeColor.none) or { r = 0.8, g = 0, b = 0 }
end

local function setAura(b, a, size, filter, steal)
  b.auraIndex = a.index
  b.icon:SetTexture(a.icon)
  b.count:SetText(a.count and a.count > 1 and a.count or "")
  b:SetWidth(size); b:SetHeight(size); b.cd:SetWidth(size); b.cd:SetHeight(size)
  if a.duration and a.duration > 0 and a.expires then AFUI.CooldownSet(b.cd, a.expires - a.duration, a.duration); b.cd:Show()
  else b.cd:Hide() end
  if filter == "HARMFUL" then
    local c = debuffColor(a.dtype); b.border:SetVertexColor(c.r, c.g, c.b); b.border:Show()
  else shown(b.border, steal and a.stealable) end
  b:Show()
end

local function build(key)
  local unit = key
  local u = { key = key, unit = unit, settings = { showPortrait = true, scale = 1, buffsOnTop = key == "target" }, pulse = {}, lowPulse = {} }
  local L = LAYOUT[key:match("^party%d$") and "party" or key]
  local name = "AFUI_" .. key:sub(1, 1):upper() .. key:sub(2) .. "Frame"
  local f = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
  u.frame = f
  f:SetAttribute("unit", unit); f:SetAttribute("type1", "target"); f:SetAttribute("type2", "menu")
  f:RegisterForClicks("AnyUp")
  f:SetFrameStrata("LOW")
  local dd = DROPDOWN[key] or (key:match("^party%d$") and "PartyMemberFrame" .. key:sub(6) .. "DropDown")
  f.menu = function()
    local menu = dd and _G[dd]
    if menu then ToggleDropDownMenu(1, nil, menu, name, key == "player" and 106 or key == "target" and 120 or 47, 15) end
  end

  -- Forever's layering without draw sublevels: art, name strip, glows on the button; the bars (StatusBar child frames
  -- in Forever) one frame level up; texts and icons (its "content" frames) above them.
  u.portrait = f:CreateTexture(nil, "BACKGROUND")
  AFUI.RoundPortrait(f, u.portrait, AFUI_ATLAS[P .. "player-portrait-mask"][1])
  u.art = f:CreateTexture(nil, "BORDER")
  u.cap = f:CreateTexture(nil, "BORDER") -- the closed end of the frame with the portrait off
  if L.rep then u.rep = f:CreateTexture(nil, "ARTWORK") end
  if key == "target" then
    u.boss = f:CreateTexture(nil, "ARTWORK")
    u.bossRect = { f:CreateTexture(nil, "ARTWORK"), f:CreateTexture(nil, "ARTWORK"), f:CreateTexture(nil, "ARTWORK") } -- head, body, tail
  end
  if L.flash then u.flash = f:CreateTexture(nil, "OVERLAY"); u.flash:Hide() end
  if L.status then
    u.status = f:CreateTexture(nil, "OVERLAY"); u.status:Hide()
    if key == "pet" then u.status:SetBlendMode("ADD") end
  end
  local bars, top = CreateFrame("Frame", nil, f), CreateFrame("Frame", nil, f)
  bars:SetAllPoints(f); bars:SetFrameLevel(f:GetFrameLevel() + 1)
  top:SetAllPoints(f); top:SetFrameLevel(f:GetFrameLevel() + 2)
  u.hpFill = bars:CreateTexture(nil, "ARTWORK")
  u.mpFill = bars:CreateTexture(nil, "ARTWORK")
  u.top = top
  if AFUI.BarGlow then -- the glow overlays sit in the bars frame, over the fills, on each fill's window (the geometry can change with the frame)
    local function win(kind) return function() local w = (u.rareBars or u.geo)[kind].win; return w[1], w[2], w[3], w[4] end end
    AFUI.BarGlow.Attach(bars, function() return unit end, "health", win("hp"))
    AFUI.BarGlow.Attach(bars, function() return unit end, "power", win("mp"))
  end
  u.ticker = CreateFrame("Frame", nil, f)

  local function text(font, layer) return top:CreateFontString(nil, layer or "OVERLAY", font) end
  u.name = text("GameFontNormalSmall")
  -- The status texts take their size from the bar window they sit in (AFUI.StatusTextSize), not from the client's TextStatusBarText font,
  -- which is larger than these bars in 2.5.3; they are centred on that window.
  local function barTexts(t, win)
    if not t then return end
    local s = { center = text("TextStatusBarText"), left = text("TextStatusBarText"), right = text("TextStatusBarText") }
    s.y, s.t, s.win = -(win[2] + win[4]) / 2, t, win
    s.size = AFUI.StatusTextSize(win[4] - win[2])
    for _, fs in pairs({ s.center, s.left, s.right }) do fs:SetFont("Fonts\\FRIZQT__.TTF", s.size, "OUTLINE") end
    return s
  end
  u.hpText, u.mpText = barTexts(L.hp.text, L.hp.win), barTexts(L.mp.text, L.mp.win)
  -- Anchored per geometry (the level orb moves with the portrait off): the texts keep clear of it, see AFUI.StatusTextSpan.
  local function placeTexts(g)
    for _, s in ipairs({ u.hpText or false, u.mpText or false }) do
      if s then
        local l, r = AFUI.StatusTextSpan(g, s.t, s.win)
        local moved = l ~= math.max(s.t[3], s.win[1] + 1) or r ~= math.min(s.t[4], s.win[3] - 1)
        for fs, pt in pairs({ [s.center] = { "CENTER", moved and (l + r) / 2 or s.t[1] }, [s.left] = { "LEFT", l }, [s.right] = { "RIGHT", r } }) do
          fs:ClearAllPoints(); fs:SetPoint(pt[1], f, "TOPLEFT", pt[2], s.y)
        end
        s.room = r - l -- the width the left and right texts share
      end
    end
  end
  if L.level then
    u.levelCircle = top:CreateTexture(nil, "ARTWORK")
    AFUI.SetAtlas(u.levelCircle, c60(P .. "smallcircle"), true)
    u.level = text(nil)
    u.level:SetFont("Fonts\\FRIZQT__.TTF", 14) -- WhiteLargeNumberFont (UF/camelot/playerframetemplates.xml:4)
    u.level:SetShadowColor(0, 0, 0); u.level:SetShadowOffset(1, -1)
    u.level:SetJustifyH("RIGHT")
  end
  if L.leader then
    u.leader = top:CreateTexture(nil, "OVERLAY")
    AFUI.SetAtlas(u.leader, P .. "player-group-leadericon", true)
    u.leader:SetPoint("TOPLEFT", f, "TOPLEFT", L.leader[1], L.leader[2]); u.leader:Hide()
  end
  if L.pvp then u.pvp = top:CreateTexture(nil, "OVERLAY"); u.pvp:Hide() end
  if L.dead then
    u.dead = text("GameFontNormalSmall"); u.dead:SetText(DEAD)
    u.dead:SetFont("Fonts\\FRIZQT__.TTF", u.hpText and u.hpText.size or 10, "OUTLINE")
    u.dead:SetPoint("CENTER", f, "TOPLEFT", L.dead[1], L.dead[2]); u.dead:Hide()
  end
  if L.hitText then
    u.hitText = text("NumberFontNormalHuge"); u.hitText:Hide()
    u.hitText:SetPoint(L.hitText[1], f, "TOPLEFT", L.hitText[2], L.hitText[3])
    if CombatFeedback_Initialize then V.feedback(CombatFeedback_Initialize, u.ticker, u.hitText, 30) end
  end

  if key == "player" then
    u.corner = top:CreateTexture(nil, "OVERLAY") -- UF/mainline/playerframe.xml:338-364
    AFUI.SetAtlas(u.corner, c60(P .. "player-portraiton-cornerembellishment"), true)
    u.corner:SetPoint("TOPLEFT", f, "TOPLEFT", 58.5, -53.5)
    u.attack = top:CreateTexture(nil, "OVERLAY")
    AFUI.SetAtlas(u.attack, P .. "player-combaticon", true)
    u.attack:SetPoint("TOPLEFT", f, "TOPLEFT", 64, -62); u.attack:Hide()
    u.rest = top:CreateTexture(nil, "ARTWORK") -- 30x30 flipbook in a 20x20 frame at 64,-6 (xml:390-410)
    u.rest:SetTexture(AFUI_ATLAS[P .. "player-rest-flipbook"][1]); restCell(u.rest, 0)
    u.rest:SetWidth(30); u.rest:SetHeight(30); u.rest:SetPoint("CENTER", f, "TOPLEFT", 74, -16); u.rest:Hide()
    u.pvpTimer = text("GameFontNormalSmall"); u.pvpTimer:SetPoint("RIGHT", u.pvp, "LEFT", 2, 0); u.pvpTimer:Hide()
    -- Raid group number: BOTTOMRIGHT at 210,-29, width = text + 40 (xml:431-461, mainline/playerframe.lua:533-556)
    local g = CreateFrame("Frame", nil, top)
    g:SetHeight(16); g:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", 210, -29); g:Hide()
    local gl, gr, gm = g:CreateTexture(nil, "BACKGROUND"), g:CreateTexture(nil, "BACKGROUND"), g:CreateTexture(nil, "BACKGROUND")
    AFUI.SetAtlas(gl, P .. "player-groupindicatorleft", true); gl:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
    AFUI.SetAtlas(gr, P .. "player-groupindicatorright", true); gr:SetPoint("TOPRIGHT", g, "TOPRIGHT", 0, 0)
    AFUI.SetAtlas(gm, "_" .. P .. "player-groupindicatormid", true)
    gm:SetPoint("LEFT", gl, "RIGHT", 0, 0); gm:SetPoint("RIGHT", gr, "LEFT", 0, 0)
    g.label = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    g.label:SetAlpha(0.7); g.label:SetPoint("LEFT", g, "LEFT", 20, 2)
    u.group = g
  elseif key == "target" then
    u.skull = top:CreateTexture(nil, "OVERLAY")
    AFUI.SetAtlas(u.skull, c60(P .. "target-highleveltarget_icon"), true); u.skull:Hide()
    u.raid = top:CreateTexture(nil, "OVERLAY")
    u.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    u.raid:SetWidth(26); u.raid:SetHeight(26); u.raid:SetPoint("CENTER", f, "TOPLEFT", L.raid[1], L.raid[2]); u.raid:Hide()
    u.auras = CreateFrame("Frame", nil, f)
    u.auras:SetWidth(122); u.auras:SetHeight(1)
    u.auras:SetPoint("TOPLEFT", f, "TOPLEFT", L.auras[1], L.auras[2])
    u.buffs, u.debuffs, u.auraRows, u.totShown = {}, {}, 0, false
    -- Combo points (UF/camelot/comboframe.lua): five 20 px points at scale 0.6 on a 66 radius circle round the portrait.
    local c = { frame = CreateFrame("Frame", nil, f) }
    c.frame:SetFrameStrata("MEDIUM"); c.frame:SetWidth(1); c.frame:SetHeight(1); c.frame:Hide()
    c.frame:SetPoint("CENTER", f, "TOPLEFT", L.combo[1], L.combo[2])
    for i = 1, 5 do
      local p = CreateFrame("Frame", nil, c.frame)
      p:SetWidth(20); p:SetHeight(20); p:SetScale(0.6)
      local function layer(atlas, lay, dy)
        local t = p:CreateTexture(nil, lay); AFUI.SetAtlas(t, c60(atlas), true); t:SetPoint("CENTER", p, "CENTER", 0, dy or 0); return t
      end
      layer("uf-roguecp-bg-shadow", "BACKGROUND", -4)
      p.inactive, p.lit = layer("uf-roguecp-bg-dis", "BACKGROUND"), layer("uf-roguecp-bg", "BORDER")
      p.icon = layer("uf-roguecp-icon-red", "ARTWORK")
      c[i] = p
    end
    u.combo = c
  elseif key == "pet" then
    u.happiness = top:CreateTexture(nil, "OVERLAY") -- TBC's PetFrameHappiness (not in Forever's files)
    u.happiness:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
    u.happiness:SetWidth(24); u.happiness:SetHeight(23); u.happiness:SetPoint("LEFT", f, "RIGHT", 0, -4); u.happiness:Hide()
  elseif L.type == "party" then
    u.disconnect = top:CreateTexture(nil, "OVERLAY")
    u.disconnect:SetTexture("Interface\\CharacterFrame\\Disconnect-Icon")
    u.disconnect:SetWidth(L.disc[3]); u.disconnect:SetHeight(L.disc[3]); u.disconnect:SetPoint("CENTER", f, "TOPLEFT", L.disc[1], L.disc[2]); u.disconnect:Hide()
  end
  if L.smallAuras or L.totDebuffs then u.debuffs = {} end

  -- Status text: shown with CVar statusText or while the mouse is over the frame (textstatusbar.lua:101-121).
  local function barText(t, value, max, percentOK)
    if not t then return end
    local c, l, r = "", "", ""
    if max > 0 and not u.offline and (u.hover or GetCVar("statusText") == "1") then
      if value == 0 and L.zeroText then c = L.zeroText else c, l, r = AFUI.StatusText(value, max, V.textMode(), percentOK) end
    end
    t.center:SetText(c); t.left:SetText(l or ""); t.right:SetText(r or "")
    -- never wider than the bar: the percentage goes first, then the maximum
    if (l or "") ~= "" and (r or "") ~= "" and t.left:GetStringWidth() + t.right:GetStringWidth() + 3 > t.room then t.left:SetText("") end
    if c ~= "" and t.center:GetStringWidth() > t.room then t.center:SetText(c:match("^(.-) / ") or c) end
  end

  function u.UpdateTint()
    local r, g, b = 1, 1, 1
    if key == "target" and not UnitPlayerControlled(unit) and V.tapDenied(unit) then r, g, b = 0.5, 0.5, 0.5 end
    if L.tint and UnitIsPlayer(unit) then
      local pct = AFUI.Fraction(UnitHealth(unit), UnitHealthMax(unit))
      if UnitIsDead(unit) then r, g, b = 0.35, 0.35, 0.35
      elseif UnitIsGhost(unit) then r, g, b = 0.2, 0.2, 0.75
      elseif pct > 0 and pct <= 0.2 then r, g, b = 1, 0, 0 end
      u.low = key == "target" and pct > 0 and pct <= 0.2 or nil -- target portrait pulses (targetframe.lua:598-620)
    else u.low = nil end
    u.portrait:SetVertexColor(r, g, b)
    if u.rep then
      if r == 0.5 then u.rep:SetVertexColor(0.5, 0.5, 0.5) else u.rep:SetVertexColor(UnitSelectionColor(unit)) end
    end
    if not u.low then u.portrait:SetAlpha(1) end
    u.Tick()
  end

  function u.UpdateHealth()
    local g = u.geo
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    local offline = L.type == "party" and not UnitIsConnected(unit)
    u.offline = offline or nil
    if offline then cur = UnitIsDead(unit) and 0 or max end -- partymemberframe.lua:746-762
    u.hpFill:SetDesaturated(offline)
    paint(u.hpFill, f, c60(P .. L.type .. "-portraiton-bar-health"), (u.rareBars or g).hp.win, AFUI.Fraction(cur, max), u.art)
    barText(u.hpText, cur, max, true)
    if u.dead then
      u.dead:SetText(UnitIsGhost(unit) and (GHOST or "Ghost") or DEAD)
      shown(u.dead, cur <= 0 and UnitIsConnected(unit))
    end
    if L.type == "party" then u.portrait:SetDesaturated(offline); shown(u.disconnect, offline) end
    u.UpdateTint()
  end

  function u.UpdatePower()
    local g = u.geo
    local cur, max = AFUI.UnitPower(unit)
    if L.type == "party" then u.offline = not UnitIsConnected(unit) or nil end
    if u.happiness then u.UpdateHappiness() end
    if not max or max <= 0 then u.mpFill:Hide(); barText(u.mpText, 0, 0); return end
    local ptype = UnitPowerType(unit)
    u.mpAtlas = c60(P .. L.type .. "-portraiton-bar-" .. (POWER[ptype] or "mana"))
    local dead = key == "player" and (UnitIsDead(unit) or UnitIsGhost(unit)) or false
    u.mpFill:SetDesaturated(dead); u.mpFill:SetAlpha(dead and 0.5 or 1)
    paint(u.mpFill, f, u.mpAtlas, (u.rareBars or g).mp.win, AFUI.Fraction(cur, max), u.art)
    barText(u.mpText, cur, max, ptype == 0)
  end

  function u.UpdatePortrait()
    if u.geo.portrait then SetPortraitTexture(u.portrait, unit) end
  end

  function u.UpdateLevel()
    if not u.level then return end
    local level = UnitLevel(unit)
    if key == "player" then u.level:SetTextColor(1, 1, 1); u.level:SetText(level); return end -- camelot/playerframe.lua:21
    if UnitIsCorpse(unit) or not level or level <= 0 then u.level:Hide(); u.skull:Show(); return end
    u.level:SetText(level); u.level:Show(); u.skull:Hide()
    if UnitCanAttack("player", unit) then u.level:SetTextColor(AFUI.LevelColor(level)) else u.level:SetTextColor(1, 0.82, 0) end
  end

  function u.SetName() -- one line, cut with "..." to the name strip
    AFUI.FitText(u.name, UnitName(unit) or "", u.geo and u.geo.name[4])
  end

  function u.UpdateInfo()
    u.SetName()
    u.UpdateLevel()
  end

  -- Frame art: classification for the target (UF/mainline/targetframe.lua:382-445), cropped with the portrait off.
  function u.UpdateArt()
    local g = u.geo
    local from, to
    if g.off then from = g.art[2] + g.crop[1]; to = from + g.crop[2] end
    local class = key == "target" and (u.preview and "elite" or bossClass(unit)) -- the Edit Mode preview shows the elite dragon
    local rare = (class == "rare" or class == "rareelite") and not g.off
    local a = rare and { L.rare[1], L.rare[2], L.rare[3] } or g.art
    u.rareBars = rare and L.rare or nil -- the rare frame has taller bar windows
    local artFrom, artTo = from, to
    if g.off then artFrom, artTo = AFUI.ClosedEnd(u.cap, f, g) end
    draw(u.art, f, c60(rare and P .. a[1] or a[1]), a[2], a[3], artFrom, artTo)
    if not g.off then u.cap:Hide() end
    if u.flash then draw(u.flash, f, c60(P .. L.flash[1]), L.flash[2], L.flash[3], from, to); u.UpdateThreat() end
    if u.status then
      local shownBefore = u.status:IsShown()
      draw(u.status, f, c60(P .. L.status[1]), L.status[2], L.status[3], from, to)
      shown(u.status, shownBefore)
    end
    if u.rep then draw(u.rep, f, c60(P .. "target-portraiton-type"), L.rep[1], L.rep[2], from, to) end
    if u.boss then
      local b = BOSS[class]
      local n = b and c60(P .. b[1])
      if b and AFUI_ATLAS[n] and not g.off then
        draw(u.boss, f, n, g.w + b[2] - AFUI_ATLAS[n][2], b[3])
      else u.boss:Hide() end
      if b and AFUI_ATLAS[n] and g.off then AFUI.BossRect(u.bossRect, f, g, n, b) else for _, t in ipairs(u.bossRect) do t:Hide() end end
    end
  end

  -- Threat glow (UF/mainline/unitframe.lua:1007-1027); TBC 2.4.3 has no threat API.
  function u.UpdateThreat()
    if not u.flash then return end
    local r, g, b
    if UnitExists(unit) and not UnitIsDead(unit) then
      if key == "target" then r, g, b = V.threat("player", unit) else r, g, b = V.threat(unit) end
    end
    if r then u.flash:SetVertexColor(r, g, b); u.flash:Show() else u.flash:Hide() end
  end

  function u.UpdateIcons()
    local g = u.geo
    if u.leader then shown(u.leader, AFUI.IsLeader(unit)) end
    if u.pvp then
      local n, faction = nil, UnitFactionGroup(unit)
      if UnitIsPVPFreeForAll(unit) then n = "player-pvp-ffaicon"
      elseif UnitIsPVP(unit) and (faction == "Horde" or faction == "Alliance") then
        n = L.pvp.party and "player-pvp-" .. faction:lower() .. "icon" or "smallcircle-" .. faction:lower()
      end
      if n then
        local pv = g.pvp
        local x = g.pvpIn and AFUI.FlagCentre(g, n, pv[5]) / pv[5] or pv[3]
        icon(u.pvp, f, c60(P .. n), pv[1], pv[2], x, pv[4], pv[5])
      else u.pvp:Hide() end
      if u.pvpTimer then -- remaining PvP flag time, not for FFA (camelot/playerframe.lua:43-48)
        u.pvpLeft = n and n ~= "player-pvp-ffaicon" and IsPVPTimerRunning() and GetPVPTimer() or nil
        shown(u.pvpTimer, u.pvpLeft)
        u.Tick()
      end
    end
    if u.raid then
      local idx = GetRaidTargetIndex(unit)
      if idx then SetRaidTargetIconTexture(u.raid, idx); u.raid:Show() else u.raid:Hide() end
    end
    if u.combo then u.UpdateCombo(true) end -- the circle starts higher while the PvP icon shows
    if g.off and u.corner then u.corner:Hide() end
  end

  -- Player status (UF/mainline/playerframe.lua:487-519) and pet attack mode (petframe.lua:118-160).
  function u.UpdateStatus()
    if key ~= "player" then return end
    local combat, resting = UnitAffectingCombat("player"), IsResting()
    if combat then u.status:SetVertexColor(1, 0, 0, 1) elseif resting then u.status:SetVertexColor(1, 0.88, 0.25, 1) end
    shown(u.status, combat or resting)
    shown(u.attack, combat and not u.geo.off); shown(u.corner, not combat and not u.geo.off); shown(u.rest, resting and not combat)
    u.Tick()
  end

  function u.UpdateGroup()
    if not u.group then return end
    u.group:Hide()
    local me = UnitName("player")
    for i = 1, AFUI.RaidSize() do
      local who, _, sub = GetRaidRosterInfo(i)
      if who == me then
        u.group.label:SetText(GROUP .. " " .. sub)
        u.group:SetWidth((u.group.label:GetStringWidth() or 0) + 40)
        u.group:Show()
        return
      end
    end
  end

  -- Combo points fill from the last point (UF/camelot/comboframe.lua:98-132).
  function u.UpdateCombo(instant)
    local c = u.combo
    local n = math.min(AFUI.ComboPoints() or 0, 5)
    local start = u.pvp:IsShown() and 2 or -10
    for i = 1, 5 do
      local p, a = c[i], math.rad(start + (i - 1) * 21)
      p:ClearAllPoints(); p:SetPoint("CENTER", c.frame, "CENTER", math.cos(a) * 66, math.sin(a) * 66)
      p.active = i >= 5 - n + 1
      shown(p.lit, p.active); shown(p.icon, p.active); shown(p.inactive, not p.active)
    end
    if n == 0 then c.frame:Hide()
    elseif instant then c.frame:SetAlpha(1); c.frame:Show()
    elseif not c.frame:IsShown() then UIFrameFadeIn(c.frame, 0.3) end
  end

  local HAPPY = { { 0.375, 0.5625 }, { 0.1875, 0.375 }, { 0, 0.1875 } }
  function u.UpdateHappiness()
    local h = HAPPY[GetPetHappiness() or 0]
    if h then u.happiness:SetTexCoord(h[1], h[2], 0, 0.359375); u.happiness:Show() else u.happiness:Hide() end
  end

  -- Target auras: flow layout, rows of 122 px (101 for two rows beside the target of target), 3 px apart;
  -- friendly: buffs then debuffs, hostile: debuffs first (UF/shared/targetframeauracontainer.lua, targetframeaurashared.lua).
  local function targetAuras()
    local friendly = UnitIsFriend("player", unit)
    local debuffs = {}
    for _, a in ipairs(scan(unit, "HARMFUL", 16)) do
      if a.mine or not a.byPlayer or friendly or UnitIsPlayer(unit) then debuffs[#debuffs + 1] = a end
    end
    local groups = { { scan(unit, "HELPFUL", 32), u.buffs, "HELPFUL" }, { debuffs, u.debuffs, "HARMFUL" } }
    if not friendly then groups[1], groups[2] = groups[2], groups[1] end
    local tot, steal = u.totShown, not UnitIsUnit("player", unit)
    -- "Buffs On Top" (Edit Mode, Mat's layout has it ticked): the block sits on the frame, its first line at the bottom and the lines
    -- growing up (container BOTTOMLEFT on the art's TOPLEFT +5, -6, targetframe.lua).
    local top = u.settings.buffsOnTop
    u.auras:ClearAllPoints()
    if top then u.auras:SetPoint("BOTTOMLEFT", f, "TOPLEFT", L.art[2] + 5, L.art[3] - 6)
    else u.auras:SetPoint("TOPLEFT", f, "TOPLEFT", L.auras[1], L.auras[2]) end
    local x, y, lineH, lines = 0, 0, 0, 0
    for _, grp in ipairs(groups) do
      local list, buttons, filter = grp[1], grp[2], grp[3]
      if #list > 0 and lineH > 0 then y = y - lineH - 3; x = 0; lineH = 0 end
      for i, a in ipairs(list) do
        local size = a.mine and 21 or 17
        if lineH == 0 then lines = lines + 1
        elseif x + size > ((tot and lines <= 2) and 101 or 122) then
          y = y - lineH - 3; x = 0; lineH = 0; lines = lines + 1
        end
        local b = buttons[i] or newAura(u.auras, unit, filter, 1)
        buttons[i] = b
        b:ClearAllPoints()
        if top then b:SetPoint("BOTTOMLEFT", u.auras, "BOTTOMLEFT", x, -y) else b:SetPoint("TOPLEFT", u.auras, "TOPLEFT", x, y) end
        setAura(b, a, size, filter, steal)
        x = x + size + 3
        if size > lineH then lineH = size end
      end
      for i = #list + 1, #buttons do buttons[i]:Hide() end
    end
    u.auraRows = lines
    u.auras:SetHeight(math.max(1, lineH - y))
    placeTargetCastBar()
  end

  -- Party/pet: up to 4 debuffs, 15 px, 2 apart; party status glow takes the first one's colour (shared/partymemberframe.lua).
  -- Target of target: 4 debuffs, 12 px, in a 2x2 block right of the frame.
  local function smallAuras()
    local list = scan(unit, "HARMFUL", 4)
    for i = 1, 4 do
      local a, b = list[i], u.debuffs[i]
      if a then
        if not b then
          b = newAura(f, unit, "HARMFUL", L.smallAuras and 5 or 1); u.debuffs[i] = b
          b:ClearAllPoints()
          if L.smallAuras then b:SetPoint("TOPLEFT", f, "TOPLEFT", L.smallAuras[1] + (i - 1) * 17, L.smallAuras[2])
          else b:SetPoint("TOPLEFT", f, "TOPLEFT", L.totDebuffs[i][1], L.totDebuffs[i][2]) end
        end
        setAura(b, a, L.smallAuras and 15 or 12, "HARMFUL")
      elseif b then b:Hide() end
    end
    if L.type == "party" then
      if list[1] then local c = debuffColor(list[1].dtype); u.status:SetVertexColor(c.r, c.g, c.b) end
      shown(u.status, list[1])
    end
  end

  function u.UpdateAuras()
    if u.buffs then targetAuras() elseif u.debuffs then smallAuras() end
  end

  -- One OnUpdate for the pulses, the rest flipbook, the PvP timer and hit text; set only while one of them runs.
  function u.OnTick(_, dt)
    if (key == "player" or key == "pet") and u.status:IsShown() then u.status:SetAlpha(pulse(u.pulse, dt, 55, 400)) end
    if u.low then u.portrait:SetAlpha(pulse(u.lowPulse, dt, 127, 256)) end
    if u.rest and u.rest:IsShown() then -- 42 frames, 1.5 s loop (playerframe.xml:390-410)
      u.restT = ((u.restT or 0) + dt) % 1.5
      restCell(u.rest, math.floor(u.restT / 1.5 * 42))
    end
    if u.pvpLeft then
      u.pvpLeft = u.pvpLeft - dt * 1000
      if u.pvpLeft < 0 then u.pvpLeft = nil; u.pvpTimer:Hide()
      else u.pvpTimer:SetFormattedText(SecondsToTimeAbbrev(math.floor(u.pvpLeft / 1000))) end
    end
    if u.feedbackLeft then
      V.feedback(CombatFeedback_OnUpdate, u.ticker, dt)
      u.feedbackLeft = u.feedbackLeft - dt
      if u.feedbackLeft <= 0 then u.feedbackLeft = nil; u.hitText:Hide() end
    end
    if not u.NeedsTick() then u.ticker:SetScript("OnUpdate", nil) end
  end
  function u.NeedsTick()
    return (key == "player" or key == "pet") and u.status:IsShown() or u.low or (u.rest and u.rest:IsShown())
      or u.pvpLeft or u.feedbackLeft
  end
  function u.Tick() u.ticker:SetScript("OnUpdate", u.NeedsTick() and u.OnTick or nil) end

  function u.OnCombat(action, flags, amount, school)
    if not (u.hitText and CombatFeedback_OnCombatEvent) then return end
    V.feedback(CombatFeedback_OnCombatEvent, u.ticker, action, flags, amount, school)
    u.feedbackLeft = 2 -- longer than COMBATFEEDBACK fade in + hold + fade out
    u.Tick()
  end

  function u.SetAttacking(on)
    if key ~= "pet" then return end
    u.status:SetVertexColor(1, 0, 0, 1); shown(u.status, on); u.Tick()
  end

  function u.Update()
    if not UnitExists(unit) then return end
    u.UpdateArt(); u.UpdateInfo(); u.UpdateHealth(); u.UpdatePower(); u.UpdatePortrait(); u.UpdateIcons()
    u.UpdateStatus(); u.UpdateGroup(); u.UpdateAuras()
    if u.combo then u.UpdateCombo(true) end
  end

  -- Geometry. Resizes a secure frame, so it only ever runs out of combat.
  function u.applyNow()
    local s = u.settings
    local g = AFUI.UnitFrameGeometry(key, s.showPortrait ~= false)
    u.geo = g
    f:SetWidth(g.w); f:SetHeight(g.h); f:SetScale(s.scale or 1)
    local ins = L.insets or { 0, 0, 0, 0 }
    f:SetHitRectInsets(ins[1], ins[2], ins[3], ins[4])
    local pr = g.portrait
    if pr then
      u.portrait:SetWidth(pr[3]); u.portrait:SetHeight(pr[3])
      u.portrait:ClearAllPoints(); u.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", pr[1], pr[2]); u.portrait:Show()
    else u.portrait:Hide() end
    local n = g.name
    u.name:ClearAllPoints(); u.name:SetPoint(n[1], f, "TOPLEFT", n[2], n[3])
    u.name:SetWidth(n[4]); u.name:SetHeight(n[5]); u.name:SetJustifyH(n[6])
    u.SetName() -- the strip may have changed width
    if u.rest then u.rest:ClearAllPoints(); u.rest:SetPoint("BOTTOM", u.name, "TOP", 0, -2) end -- zZz centred above the name
    if key == "pet" then u.name:SetJustifyV("BOTTOM") end
    if u.raid then u.raid:ClearAllPoints(); u.raid:SetPoint("CENTER", f, "TOPLEFT", (g.raid or L.raid)[1], L.raid[2]) end
    if u.combo then u.combo.frame:ClearAllPoints(); u.combo.frame:SetPoint("CENTER", f, "TOPLEFT", (g.combo or L.combo)[1], L.combo[2]) end
    if u.disconnect then
      local d = g.disc
      u.disconnect:SetWidth(d[3]); u.disconnect:SetHeight(d[3])
      u.disconnect:ClearAllPoints(); u.disconnect:SetPoint("CENTER", f, "TOPLEFT", d[1], d[2])
    end
    if u.levelCircle then
      u.levelCircle:ClearAllPoints(); u.levelCircle:SetPoint("CENTER", f, "TOPLEFT", g.level[1], g.level[2])
      u.level:ClearAllPoints(); u.level:SetPoint("CENTER", f, "TOPLEFT", g.level[1], g.level[2] - 0.5)
      if u.skull then u.skull:ClearAllPoints(); u.skull:SetPoint("CENTER", f, "TOPLEFT", g.level[1], g.level[2]) end
    end
    placeTexts(g)
    u.UpdateArt() -- drawn with or without a unit (edit mode shows empty frames)
    u.Update()
  end

  -- Edit Mode preview: the frame draws the player's own data (Forever forces the player's unit into the frames that have none,
  -- docs/forever-ref/editmode.md section 6). Drawing only, safe in combat; the secure side is AFUI.Units.SetPreview.
  function u.Preview(on)
    u.preview = on or nil
    unit = on and "player" or key
    u.unit = unit
    if on then
      f:SetAlpha(1)
      u.Update()
    else
      u.SetName() -- nothing stale for when the frame shows again
      u.Update() -- a real target must not keep the player's data (drawing only, safe in combat)
    end
  end

  function u.ApplySettings(settings)
    for k, v in pairs(settings or {}) do u.settings[k] = v end
    AFUI.RunOutOfCombat(u.applyNow)
  end

  f:SetScript("OnShow", function() u.Update() end)
  f:HookScript("OnEnter", function(self) -- UnitFrame_OnEnter: tooltip + status text
    u.hover = true; u.UpdateHealth(); u.UpdatePower()
    GameTooltip_SetDefaultAnchor(GameTooltip, self); GameTooltip:SetUnit(unit)
  end)
  f:HookScript("OnLeave", function()
    u.hover = nil; u.UpdateHealth(); u.UpdatePower(); GameTooltip:Hide()
  end)
  if key ~= "player" then RegisterUnitWatch(f) end
  AFUI.Units[key] = u
  return u
end

-- Target of target: polled (its unit has no events) every 0.2 s while shown; faded out when the target is you or dead.
local function totUpdate()
  local u, t = AFUI.Units.targettarget, AFUI.Units.target
  if u.preview then return end -- Edit Mode shows it with the player's data
  local on = totShown() and true or false
  u.frame:SetAlpha(on and 1 or 0)
  if t.totShown ~= on then t.totShown = on; t.UpdateAuras() end
  if on then u.Update() end
end

local PLACE = {
  player = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -20 },
  target = { "TOPLEFT", "UIParent", "TOPLEFT", 260, -20 },
  targettarget = { "TOPRIGHT", "AFUI_TargetFrame", "BOTTOMRIGHT", 12, 10 }, -- UF/mainline/targetframe.xml:397-405
  pet = { "TOP", "AFUI_PlayerFrame", "BOTTOM", 30, 25 }, -- PlayerBottomManagedFrameContainer (playerframe.xml:477-484)
  party1 = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -150 },
}
for i = 2, 4 do PLACE["party" .. i] = { "TOPLEFT", "AFUI_Party1Frame", "TOPLEFT", 0, -(i - 1) * PARTY_GAP } end

-- Edit Mode previews keep the party frames shown and unwatched; a group event must not undo that (hidePreview runs it again).
local previewing, previewSet
-- Party frames give way to the raid frames, and to the raid-style party frames (CompactParty.lua) while those are switched on.
local function applyPartyVisibility()
  local cp = AFUI.ModuleEnabled("party") and AFUI.CompactParty or nil -- raid-style party frames off (AddonCompat.lua): nothing of theirs is drawn or asked
  local compact = cp and cp.IsOn()
  local partyPreview = previewing and (not previewSet or previewSet.party1)
  if cp then cp.preview = partyPreview and true or false; cp.Refresh() end
  if not AFUI.Units.party1 then return end -- unit frames off: the party frames were never built
  if previewing and not compact and not partyPreview then return end
  local raid = AFUI.RaidSize() > 0
  for i = 1, 4 do
    local f = AFUI.Units["party" .. i].frame
    if not f.afGiveWay then -- something showed it again (a group change in combat, a late event): it gives way once more
      f.afGiveWay = true
      f:HookScript("OnShow", function(self)
        local c = AFUI.ModuleEnabled("party") and AFUI.CompactParty
        if c and c.IsOn() and not previewing then self:SetAlpha(0); AFUI.RunOutOfCombat(applyPartyVisibility) end
      end)
    end
    if compact or (raid and not previewing) then UnregisterUnitWatch(f); f:Hide()
    elseif previewing then UnregisterUnitWatch(f); f:Show(); f:SetAlpha(1)
    else RegisterUnitWatch(f); f:SetAlpha(1) end
  end
end
AFUI.Units.ApplyPartyVisibility = applyPartyVisibility

local function each(fn) for _, key in ipairs(KEYS) do fn(AFUI.Units[key]) end end

-- Edit Mode shows target, target of target, pet and party with the player's own data (u.Preview) and keeps them shown: their
-- unit watch comes off and they are Show()n. Those are protected calls, so they only run out of combat. Opening is refused in
-- combat; closing in combat restores the drawing at once, hides the empty shells by alpha, and puts the watches back after.
local function showPreview(set)
  previewing, previewSet = true, set
  each(function(u)
    if u.key == "player" then return end
    if not set or set[u.key] then UnregisterUnitWatch(u.frame); u.frame:Show() else RegisterUnitWatch(u.frame) end
  end)
  applyPartyVisibility() -- raid-style on: the four party frames go again, the raid-style ones show
end

local function hidePreview()
  previewing, previewSet = false, nil
  each(function(u)
    if u.key == "player" then return end
    u.pending = nil
    RegisterUnitWatch(u.frame)
    u.frame:SetAlpha(1)
  end)
  applyPartyVisibility()
  totUpdate()
  each(function(u) if u.key ~= "player" then u.Update() end end)
end

-- Frames waiting for their watch (closed in combat) show only while their unit exists.
local function settlePending()
  each(function(u) if u.pending then u.frame:SetAlpha(UnitExists(u.unit) and 1 or 0) end end)
end

-- set (optional): the unit keys that are previewed, the others stay as in the game (Forever's account checkboxes). Nil: all of them.
function AFUI.Units.SetPreview(on, set)
  if on and InCombatLockdown() then return end
  -- like Forever, only frames that have no unit of their own show the player
  each(function(u) if u.key ~= "player" then u.Preview(on and (not set or set[u.key]) and not UnitExists(u.key)) end end)
  if on then return AFUI.RunOutOfCombat(function() showPreview(set) end) end
  if InCombatLockdown() then
    each(function(u) if u.key ~= "player" then u.pending = true end end)
    settlePending()
  end
  AFUI.RunOutOfCombat(hidePreview)
end

local function onUnit(method)
  return function(_, unit, ...)
    local u = AFUI.Units[unit]
    if u and u[method] then u[method](...) end
    if unit == "player" then -- Edit Mode previews follow the player's changes too
      local rest = { ... }
      each(function(p) if p.preview and p[method] then p[method](unpack(rest)) end end)
    end
  end
end

local EXTRA = {
  UNIT_THREAT_SITUATION_UPDATE = function() each(function(u) u.UpdateThreat() end) end,
  UNIT_HAPPINESS = function() AFUI.Units.pet.UpdateHappiness() end,
}

-- Regions the client's unit frames draw (PlayerFrame/TargetFrame/PetFrame/PartyMemberFrame XML + .lua). The frames are killed, but their
-- Update functions Show these again, so each one is also held hidden: nothing of Blizzard's PvP flag, rest zZz, leader crown,
-- raid mark, combat swords or elite dragon may ever show next to ours.
local CLIENT_ART = { "PlayerPVPIcon", "PlayerPVPIconHitArea", "PlayerPVPTimerText", "PlayerAttackIcon", "PlayerAttackBackground",
  "PlayerRestIcon", "PlayerRestGlow", "PlayerAttackGlow", "PlayerStatusGlow", "PlayerStatusTexture", "PlayerFrameTexture",
  "PlayerFrameBackground", "PlayerFrameFlash", "PlayerFrameGroupIndicator", "PlayerLeaderIcon", "PlayerMasterIcon", "PlayerGuideIcon",
  "PlayerPortrait", "PlayerName", "PlayerLevelText", "PlayerHitIndicator",
  "TargetFrameTextureFramePVPIcon", "TargetFrameTextureFrameLeaderIcon", "TargetFrameTextureFrameRaidTargetIcon",
  "TargetFrameTextureFrameLevelText", "TargetFrameTextureFrameName", "TargetFrameTextureFrameDeadText",
  "TargetFrameTextureFrameTexture", "TargetFrameTextureFrameHealthBarText", "TargetFrameTextureFrameManaBarText",
  "TargetFrameNameBackground", "TargetFrameBackground", "TargetFrameFlash", "TargetFrameReputationColor", "TargetFramePortrait",
  "TargetFrameTextureFrameBossIcon", "TargetFrameTextureFrameGuideIcon",
  "PetFrameTexture", "PetFrameFlash", "PetFrameHappiness", "PetAttackModeTexture", "PetPortrait", "PetName", "PetFrameHealthBarText",
  "PetFrameManaBarText", "PetFrameBackground" }
for i = 1, 4 do
  local n = "PartyMemberFrame" .. i
  for _, s in ipairs({ "PVPIcon", "Leader", "MasterIcon", "GuideIcon", "Portrait", "Name", "Texture", "Flash", "Background", "Status",
    "NotPresentIcon", "VehicleTexture" }) do CLIENT_ART[#CLIENT_ART + 1] = n .. s end
end
AFUI.CLIENT_UNIT_ART = CLIENT_ART

local function holdHidden(r)
  if r.afHeld then return end
  r.afHeld = true
  local busy
  local function off()
    if busy then return end
    busy = true; r:SetAlpha(0); r:Hide(); busy = false
  end
  off()
  for _, m in ipairs({ "Show", "SetAlpha", "SetTexture", "SetAtlas" }) do
    if r[m] then hooksecurefunc(r, m, off) end
  end
end

local hookedFns = {}
function AFUI.HideClientUnitArt()
  for _, n in ipairs(CLIENT_ART) do if _G[n] and _G[n].Hide then holdHidden(_G[n]) end end
  for _, fn in ipairs({ "PlayerFrame_UpdatePvPStatus", "PlayerFrame_UpdateStatus", "PlayerFrame_UpdateRolesAssigned",
    "PlayerFrame_UpdateLevel", "TargetFrame_CheckFaction", "TargetFrame_CheckClassification", "TargetFrame_CheckLevel",
    "TargetFrame_UpdateRaidTargetIcon", "PartyMemberFrame_UpdatePvPStatus", "PartyMemberFrame_UpdateLeader",
    "PetFrame_Update" }) do
    if type(_G[fn]) == "function" and not hookedFns[fn] then
      hookedFns[fn] = true
      hooksecurefunc(fn, function() for _, n in ipairs(CLIENT_ART) do local r = _G[n]; if r and r.Hide then r:SetAlpha(0); r:Hide() end end end)
    end
  end
end

function AFUI.SetupUnitFrames()
  for _, key in ipairs(KEYS) do
    local u = build(key)
    local p = PLACE[key]
    u.frame:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4], p[5])
    u.applyNow()
  end
  for _, n in ipairs(BLIZZARD) do if _G[n] then AFUI.Kill(_G[n]) end end
  AFUI.HideClientUnitArt()
  applyPartyVisibility()

  local tot = AFUI.Units.targettarget.frame
  local elapsed = 0
  tot:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= 0.2 then elapsed = 0; totUpdate() end
  end)
  tot:HookScript("OnHide", function()
    local t = AFUI.Units.target
    if t.totShown then t.totShown = false; t.UpdateAuras() end
  end)

  AFUI.On("UNIT_HEALTH", onUnit("UpdateHealth")); AFUI.On("UNIT_MAXHEALTH", onUnit("UpdateHealth"))
  for _, e in ipairs(AFUI.POWER_EVENTS) do AFUI.On(e, onUnit("UpdatePower")) end
  AFUI.On("UNIT_AURA", onUnit("UpdateAuras"))
  AFUI.On("UNIT_PORTRAIT_UPDATE", onUnit("UpdatePortrait"))
  AFUI.On("UNIT_CLASSIFICATION_CHANGED", onUnit("UpdateArt")) -- a target turning elite / rare (the event is missing in 2.4.3: AFUI.On skips it)
  AFUI.On("UNIT_NAME_UPDATE", onUnit("UpdateInfo")); AFUI.On("UNIT_LEVEL", onUnit("UpdateInfo"))
  AFUI.On("UNIT_FACTION", onUnit("UpdateIcons")); AFUI.On("UNIT_FACTION", onUnit("UpdateTint"))
  AFUI.On("PLAYER_FLAGS_CHANGED", function() AFUI.Units.player.UpdateIcons() end)
  AFUI.On("UNIT_COMBAT", onUnit("OnCombat"))
  AFUI.On("PET_ATTACK_START", function() AFUI.Units.pet.SetAttacking(true) end)
  AFUI.On("PET_ATTACK_STOP", function() AFUI.Units.pet.SetAttacking(false) end)
  for _, e in ipairs(V.EVENTS) do
    AFUI.On(e, EXTRA[e] or function() each(function(u) if u.key:match("^party") then u.Update() end end) end)
  end
  AFUI.On("UNIT_PET", function() AFUI.Units.pet.Update(); settlePending() end)
  AFUI.On("UNIT_TARGET", function(_, unit) if unit == "target" then totUpdate() end end)
  AFUI.On("PLAYER_TARGET_CHANGED", function()
    AFUI.Units.target.Update(); totUpdate(); settlePending()
  end)
  AFUI.On(AFUI.COMBO_EVENT, function(_, unit)
    if unit == nil or unit == "player" then AFUI.Units.target.UpdateCombo() end
  end)
  AFUI.On("RAID_TARGET_UPDATE", function() AFUI.Units.target.UpdateIcons() end)
  AFUI.On("PARTY_LEADER_CHANGED", function() each(function(u) u.UpdateIcons() end) end)
  for _, e in ipairs(AFUI.GROUP_EVENTS) do
    AFUI.On(e, function()
      each(function(u) if u.key:match("^party") then u.Update() end end)
      AFUI.Units.player.UpdateGroup(); AFUI.Units.player.UpdateIcons()
      AFUI.RunOutOfCombat(applyPartyVisibility)
    end)
  end
  for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING" }) do
    AFUI.On(e, function() AFUI.Units.player.UpdateStatus() end)
  end
  AFUI.On("PLAYER_ENTERING_WORLD", function() each(function(u) u.Update() end) end)
end

AFUI.RegisterModule("UnitFrames", { OnLogin = function() AFUI.RunOutOfCombat(AFUI.SetupUnitFrames) end })
