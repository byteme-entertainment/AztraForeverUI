-- "Use Raid-Style Party Frames" (Edit Mode > Party Frames): the party as the client's CompactPartyFrame / CompactUnitFrame (Blizzard_UnitFrame
-- shared/compactunitframe.lua, compactpartyframe.lua, compactraidgroup.lua), dressed like Forever's chat frames: each unit is a dark translucent
-- plate (dark brown, 0.62 alpha, like Forever's panels) in Forever's textured bronze frame; the class colour is the health bar alone (Raid-Bar-Hp-Fill) inset in the
-- plate on a dark empty background, name on top, status text under it (Dead / Ghost / Offline / AFK, or the Health Text option), with Display Power Bar the
-- power bar (Raid-Bar-Resource-*), buffs bottom right, debuffs bottom left, dispel icons top right, target and aggro outlines
-- (Raid-FrameHighlights), range fade, leader / master looter / raid target icons and, with Display Border, a bronze border round each unit's plate
-- (the DiamondMetal bronze edges and corner diamonds of the client's atlas, not the silver RaidBorder pieces), the plates 3 px apart.
-- Slots: you and party1-4, then (with Display Pets) your pet and partypet1-4, half as high (the client's mini frames).
-- Defaults are the client's raid profile: 72 x 36, class colours, border, no power bar, no pets, Group sort, no health text.
-- The 2.5.3 client ships the Interface\RaidFrame files; 2.4.3 has none of them and keeps flat fills.
-- Secure frames: sizes, anchors, units and shown state change out of combat only (AFUI.RunOutOfCombat); the drawing is always safe.
AFUI = AFUI or {}
local IS_243 = AFUI.IS_243
local CP = { frames = {}, preview = false, POWER_H = 4, MEMBERS = 5, INSET = 4, BAND = 2, OUT_OF_RANGE_ALPHA = 0.55,
  MAX_BUFFS = 8, MAX_DEBUFFS = 8, MAX_DISPEL = 3, -- the icon pools; how many show is the filter's "Max icons" (AuraFilters.lua, 3 by default)
  SORT = { "Group", "Alphabetical" }, HEALTH_TEXT = { "None", "Health Remaining", "Health Lost", "Percentage" },
  DEFAULTS = { useRaidStyle = false, frameWidth = 72, frameHeight = 36, sortBy = "Group", useHorizontal = false, displayBorder = true,
    displayPets = false, displayPowerBar = false, useClassColors = true, onlyDispellable = false, healthText = "None" } }
AFUI.CompactParty = CP
CP.settings = {}
for k, v in pairs(CP.DEFAULTS) do CP.settings[k] = v end

local R = "Interface\\RaidFrame\\"
local ART = not IS_243 and { hpFill = R .. "Raid-Bar-Hp-Fill", resFill = R .. "Raid-Bar-Resource-Fill",
  resBg = R .. "Raid-Bar-Resource-Background", highlights = R .. "Raid-FrameHighlights", debuff = R .. "Raid-Icon-Debuff" } or nil
CP.ART = ART
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Raid-FrameHighlights (128 x 128): the grey aggro outline on top, the yellow target outline under it (compactunitframe.xml, 70 x 34 of it each)
local AGGRO_COORDS, TARGET_COORDS = { 0.0078125, 0.5546875, 0.0078125, 0.2734375 }, { 0.0078125, 0.5546875, 0.2890625, 0.5546875 }
-- The fills are drawn by us inside the bar's window (the client's StatusBar stretches the whole sprite over the bar and, at a fractional UI scale
-- such as 1.245, blends the edge texels with their neighbours: streaks and a washed lower half). Windows are half a texel inside the sprite's
-- real content: Raid-Bar-Hp-Fill 32 x 32 (all of it), Raid-Bar-Resource-Fill 32 x 8 (rows 0-6; row 7 is empty).
local HALF = 0.5 / 32
local HP_Y, RES_Y = { HALF, 1 - HALF }, { 0.5 / 8, 6.5 / 8 }
local PLATE = { 0.1, 0.075, 0.05, 0.62 } -- Forever panels: a dark brown (Rock under the bronze frame), clearly there but still see-through
local FRIENDLY = { 0, 1, 0 } -- COMPACT_UNIT_FRAME_FRIENDLY_HEALTH_COLOR
local THREAT = { [1] = { 1, 1, 0.47 }, [2] = { 1, 0.6, 0 }, [3] = { 1, 0, 0 } }
local RAID_FILTER = IS_243 and 1 or "RAID" -- UnitDebuff's "only what you can dispel"

local SLOTS = { "player", "party1", "party2", "party3", "party4", "pet", "partypet1", "partypet2", "partypet3", "partypet4" }
local MENUS = { player = "PlayerFrameDropDown", pet = "PetFrameDropDown", party1 = "PartyMemberFrame1DropDown", party2 = "PartyMemberFrame2DropDown",
  party3 = "PartyMemberFrame3DropDown", party4 = "PartyMemberFrame4DropDown" }

function CP.IsOn() return CP.settings.useRaidStyle == true end

local function isPet(slot) return slot > CP.MEMBERS end
local function petHeight(s) return math.floor(s.frameHeight / 2) end -- the mini frame: 18 at the native 36
local function border(s) return s.displayBorder and not IS_243 end
local function gap(s) return border(s) and CP.Gap() or 0 end -- the dark line between the plates
local function margin(s) return border(s) and CP.Margin() or 0 end -- the frame's band round all of them

-- Width and height of the whole group (the frame's outer rectangle: the Edit Mode box) for settings `s` with `members` plates and `pets` mini plates
-- (the most there can be when left out): a column, or a row with the pets in a second row.
function CP.Size(s, members, pets)
  s = s or CP.settings
  members = members or CP.MEMBERS
  pets = s.displayPets and (pets or CP.MEMBERS) or 0
  local w, h, ph, g, m = s.frameWidth, s.frameHeight, petHeight(s), gap(s), margin(s)
  if s.useHorizontal then
    local cols = math.max(members, pets)
    return cols * w + (cols - 1) * g + 2 * m, h + (pets > 0 and ph + g or 0) + 2 * m
  end
  return w + 2 * m, members * h + pets * ph + (members + pets - 1) * g + 2 * m
end

local function setSize(fs, base)
  -- the client scales name and status with the frame (CompactUnitFrame ScaleFontString)
  local font, size, flags = fs:GetFont()
  if not font then return end
  fs.baseSize = fs.baseSize or size
  fs:SetFont(font, fs.baseSize * base, flags)
end

---------------------------------------------------------------- building
local function icon(parent, w, h, path)
  local t = parent:CreateTexture(nil, "OVERLAY")
  t:SetWidth(w); t:SetHeight(h); t:SetTexture(path); t:Hide()
  return t
end

-- One pooled aura icon: icon, swipe, stack count (bottom right), the time left (centre, when asked for) and the border (dispel colour, the entry's own colour or the highlight).
local function auraButton(parent)
  local b = CreateFrame("Frame", nil, parent)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(b)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate"); b.cd:SetAllPoints(b)
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall"); b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.time = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall"); b.time:SetPoint("TOP", b, "TOP", 0, -1)
  b.border = b:CreateTexture(nil, "OVERLAY"); b.border:SetAllPoints(b)
  b.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays"); b.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625); b.border:Hide()
  b:Hide()
  return b
end

-- The group's border (Display Border): ONE frame round all the plates, like a window: Forever's bronze DiamondMetal pieces of the atlas in their bronze
-- (-c60) twin: the top / left edge bands (bottom / right are the same bands mirrored: those c60 sprites are empty) and the diamond corner mirrored
-- into four. The band (20 texels, outline to outline) is CP.BAND screen pixels thick, the corner diamonds twice that, sitting inside the frame's
-- corners. The margin between the frame's outer edge and the plates is the band, so the frame's rectangle is exactly CP.Size.
local E_TOP, E_LEFT, E_CORNER = "_ui-frame-diamondmetal-edgetop-c60-2x", "!ui-frame-diamondmetal-edgeleft-c60-2x", "ui-frame-diamondmetal-cornertopleft-c60-2x"
local BAND_LO, BAND_HI = 22.5, 42.5 -- the band's rows / columns in the 128 texel edge sprites
local function atlasTex(b, name, layer, u0, u1, v0, v1, flipU, flipV)
  local e = AFUI_ATLAS and AFUI_ATLAS[name]
  if not e then return nil end
  local du, dv = (e[5] - e[4]) / (2 * e[2]), (e[7] - e[6]) / (2 * e[3]) -- a -2x sprite is 2 texels to the atlas pixel
  local ua, ub, va, vb = e[4] + du * u0, e[4] + du * u1, e[6] + dv * v0, e[6] + dv * v1
  if flipU then ua, ub = ub, ua end
  if flipV then va, vb = vb, va end
  local t = b:CreateTexture(nil, layer); t:SetTexture(e[1]); t:SetTexCoord(ua, ub, va, vb)
  return t
end
local function buildBorder(c)
  local b = CreateFrame("Frame", nil, c)
  b:SetAllPoints(c)
  b:SetFrameLevel(c:GetFrameLevel() + 8) -- over the plates: the corner diamonds reach into them
  b.pieces, b.studs = {}, {}
  b.pieces[1] = atlasTex(b, E_TOP, "ARTWORK", 4.5, 123.5, BAND_LO, BAND_HI)
  b.pieces[2] = atlasTex(b, E_TOP, "ARTWORK", 4.5, 123.5, BAND_LO, BAND_HI, false, true)
  b.pieces[3] = atlasTex(b, E_LEFT, "ARTWORK", BAND_LO, BAND_HI, 4.5, 123.5)
  b.pieces[4] = atlasTex(b, E_LEFT, "ARTWORK", BAND_LO, BAND_HI, 4.5, 123.5, true)
  for i = 1, 4 do b.studs[i] = atlasTex(b, E_CORNER, "OVERLAY", 0.5, 64.5, 0.5, 64.5, i == 2 or i == 4, i == 3 or i == 4) end
  b:Hide()
  return b
end

-- Screen pixels in one UI unit of the container: its effective scale times the screen height over the 768 the UI is laid out in.
local function physicalHeight()
  if GetPhysicalScreenSize then local _, h = GetPhysicalScreenSize(); if h and h > 0 then return h end end
  if GetCVar then
    local ok, win = pcall(GetCVar, "gxWindow")
    local ok2, res = pcall(GetCVar, (ok and win == "1") and "gxWindowedResolution" or "gxResolution")
    local h = ok2 and type(res) == "string" and tonumber(string.match(res, "x(%d+)"))
    if h and h > 0 then return h end
  end
  return 768
end
function CP.PxPerUnit()
  local c = CP.container
  local es = c and c.GetEffectiveScale and c:GetEffectiveScale() or 1
  if not es or es <= 0 then es = 1 end
  return es * physicalHeight() / 768
end
-- The band in whole pixels: 2 (a fractional scale such as 1.245 gives 2.49, rounded to 2; 3 from 1.25 up), the dark line between plates 1 px.
function CP.BandPx() return math.max(2, math.floor(CP.BAND * CP.PxPerUnit() + 0.5)) end
function CP.Margin() return CP.BandPx() / CP.PxPerUnit() end -- in UI units
function CP.Gap() return 1 / CP.PxPerUnit() end

function CP.FitBorder()
  local b = CP.border
  if not b or not b.pieces[1] then return end
  local ppu, tp = CP.PxPerUnit(), CP.BandPx()
  local T, C = tp / ppu, 2 * tp / ppu
  local P = b.pieces
  P[1]:ClearAllPoints(); P[1]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); P[1]:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0); P[1]:SetHeight(T)
  P[2]:ClearAllPoints(); P[2]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); P[2]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0); P[2]:SetHeight(T)
  P[3]:ClearAllPoints(); P[3]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); P[3]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); P[3]:SetWidth(T)
  P[4]:ClearAllPoints(); P[4]:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0); P[4]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0); P[4]:SetWidth(T)
  for i, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
    local t = b.studs[i]
    t:SetWidth(C); t:SetHeight(C); t:ClearAllPoints()
    t:SetPoint(corner, b, corner, 0, 0)
  end
end

-- A bar's fill: our own texture in the bar's window, cropped to a fraction like the client's StatusBar and snapped to whole screen pixels.
local function addFill(bar, path, y)
  local t = bar:CreateTexture(nil, "ARTWORK")
  t:SetTexture(path)
  t:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0); t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  t.y = y
  bar.fill = t
  local native = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
  if native then native:SetAlpha(0) end -- the StatusBar keeps the value; what is seen is ours
  return t
end

function CP.SetFill(bar, frac, r, g, b)
  local t = bar.fill
  if not t then return end
  frac = math.max(0, math.min(1, frac or 0))
  local full = bar.fullWidth or bar:GetWidth() or 0
  local es = bar.GetEffectiveScale and bar:GetEffectiveScale() or 1
  if not es or es <= 0 then es = 1 end
  local w = full > 0 and math.floor(full * frac * es + 0.5) / es or 0
  if w <= 0 then t:Hide() return end
  t:SetWidth(w)
  t:SetTexCoord(HALF, HALF + (1 - 2 * HALF) * (w / full), t.y[1], t.y[2])
  if r then t:SetVertexColor(r, g, b) end
  t:Show()
end


local function build(i)
  local unit = SLOTS[i]
  local f = CreateFrame("Button", "AFUI_CompactParty" .. i, CP.container, "SecureUnitButtonTemplate")
  f.slot, f.realUnit, f.unit, f.mini = i, unit, unit, isPet(i)
  f:SetAttribute("unit", unit); f:SetAttribute("type1", "target"); f:SetAttribute("type2", "menu")
  f:RegisterForClicks("AnyUp")
  f:SetFrameStrata("LOW")
  f.menu = function()
    local menu = MENUS[f.realUnit] and _G[MENUS[f.realUnit]]
    if menu then ToggleDropDownMenu(1, nil, menu, f:GetName(), 47, 15) end
  end
  -- the plate: the chat window's dark translucent background, over the whole frame
  f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(f)
  AFUI.SetColor(f.bg, PLATE[1], PLATE[2], PLATE[3], ART and PLATE[4] or 0.55)
  f.health = CreateFrame("StatusBar", nil, f)
  f.health:SetFrameLevel(f:GetFrameLevel() + 1)
  f.health:SetStatusBarTexture(ART and ART.hpFill or WHITE)
  f.health:SetMinMaxValues(0, 1); f.health:SetValue(0)
  f.health.bg = f.health:CreateTexture(nil, "BACKGROUND"); f.health.bg:SetAllPoints(f.health) -- the missing health shows dark
  AFUI.SetColor(f.health.bg, 0, 0, 0, 0.5)
  if ART then addFill(f.health, ART.hpFill, HP_Y) end
  f.power =CreateFrame("StatusBar", nil, f)
  f.power:SetFrameLevel(f:GetFrameLevel() + 2)
  f.power:SetStatusBarTexture(ART and ART.resFill or WHITE)
  f.power:SetMinMaxValues(0, 1); f.power:SetValue(0)
  f.power.bg = f.power:CreateTexture(nil, "BACKGROUND"); f.power.bg:SetAllPoints(f.power)
  if ART then f.power.bg:SetTexture(ART.resBg); f.power.bg:SetTexCoord(0, 1, RES_Y[1], RES_Y[2]); addFill(f.power, ART.resFill, RES_Y) else AFUI.SetColor(f.power.bg, 0, 0, 0, 0.5) end
  local top = CreateFrame("Frame", nil, f)
  top:SetAllPoints(f); top:SetFrameLevel(f:GetFrameLevel() + 3)
  f.top = top
  f.name = top:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.name:SetJustifyH("LEFT"); if f.name.SetWordWrap then f.name:SetWordWrap(false) end
  f.status = top:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  f.status:SetJustifyH("CENTER")
  -- outlines: aggro (grey, coloured by the threat level), a dispellable debuff (coloured by its type), the target (yellow)
  f.aggro = top:CreateTexture(nil, "ARTWORK"); f.aggro:SetAllPoints(f)
  f.dispelGlow = top:CreateTexture(nil, "ARTWORK"); f.dispelGlow:SetAllPoints(f)
  f.selection = top:CreateTexture(nil, "OVERLAY"); f.selection:SetAllPoints(f)
  if ART then
    for _, t in ipairs({ f.aggro, f.dispelGlow }) do t:SetTexture(ART.highlights); t:SetTexCoord(unpack(AGGRO_COORDS)) end
    f.selection:SetTexture(ART.highlights); f.selection:SetTexCoord(unpack(TARGET_COORDS))
  else
    AFUI.SetColor(f.aggro, 1, 0, 0, 0.25); AFUI.SetColor(f.dispelGlow, 1, 1, 1, 0.2); AFUI.SetColor(f.selection, 1, 1, 0.6, 0.25)
  end
  f.aggro:Hide(); f.dispelGlow:Hide(); f.selection:Hide()
  f.leader = icon(top, 12, 12, "Interface\\GroupFrame\\UI-Group-LeaderIcon")
  f.looter = icon(top, 12, 12, "Interface\\GroupFrame\\UI-Group-MasterLooter")
  f.raidTarget = icon(top, 14, 14, "Interface\\TargetingFrame\\UI-RaidTargetingIcons")
  f.buffs, f.debuffs, f.dispel = {}, {}, {}
  f.auraLists = { f.buffs, f.debuffs, f.dispel }
  if not f.mini then -- the mini (pet) frames show no auras
    for n = 1, CP.MAX_BUFFS do f.buffs[n] = auraButton(top) end
    for n = 1, CP.MAX_DEBUFFS do f.debuffs[n] = auraButton(top) end
  end
  if ART then
    for n = 1, CP.MAX_DISPEL do f.dispel[n] = icon(top, 12, 12, ART.debuff .. "Magic") end
  end
  local BG = AFUI.BarGlow -- another module: a subtle glow when the unit loses or gains health / power
  if BG then
    BG.Attach(f.health, function() return f.unit end, "health")
    BG.Attach(f.power, function() return f.unit end, "power")
  end
  f:HookScript("OnEnter", function(self)
    GameTooltip_SetDefaultAnchor(GameTooltip, self); GameTooltip:SetUnit(self.unit)
  end)
  f:HookScript("OnLeave", function() GameTooltip:Hide() end)
  f:SetScript("OnShow", function(self) CP.Draw(self) end)
  CP.frames[i] = f
  return f
end

---------------------------------------------------------------- layout
-- A slot's place: members by their row (or column), the pets under the last member that is there (CP.petRow) or, horizontal, in a row under all.
function CP.Anchor(f)
  local s, g, m = CP.settings, gap(CP.settings), margin(CP.settings)
  local w, h, ph = s.frameWidth, s.frameHeight, petHeight(s)
  local x, y
  if not isPet(f.slot) then
    local n = f.slot - 1
    if s.useHorizontal then x, y = n * (w + g), 0 else x, y = 0, n * (h + g) end
  else
    local n = f.slot - CP.MEMBERS - 1
    if s.useHorizontal then x, y = n * (w + g), h + g else x, y = 0, (CP.petRow or CP.MEMBERS) * (h + g) + n * (ph + g) end
  end
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", CP.container, "TOPLEFT", m + x, -(m + y))
end

-- The group's rectangle (the frame's outer edge) round the plates that are there, and the band's pixel snap.
function CP.Resize()
  CP.FitBorder()
  local pw, ph = CP.Size(CP.settings, CP.shownMembers, CP.shownPets)
  CP.container:SetWidth(pw); CP.container:SetHeight(ph)
end

-- The aura icons of one frame: size, corner and growth direction from the Aura Filters window (AuraFilters.lua display options), scaled with the frame like the client's.
-- Defaults: 11 px buffs bottom right going left, debuffs bottom left going right.
local GROW = { Left = { -1, 0 }, Right = { 1, 0 }, Up = { 0, 1 }, Down = { 0, -1 } }
function CP.LayoutAuras(f, scale)
  local AF = AFUI.AuraFilters
  if not (AF and not f.mini) then return end
  local s = CP.settings
  scale = scale or math.min(s.frameHeight / 36, s.frameWidth / 72)
  local I = CP.INSET
  local lift = I + (s.displayPowerBar and CP.POWER_H + 1 or 0)
  for _, kind in ipairs(AF.KINDS) do
    local d, buttons = AF.Display("party", kind), f[kind]
    local corner = AF.CORNER[d.anchor] or "BOTTOMRIGHT"
    local size, g = d.size * scale, GROW[d.growth] or GROW.Left
    local top = corner:find("TOP") ~= nil
    local sx = corner:find("LEFT") and 1 or -1
    for n, b in ipairs(buttons) do
      b:SetWidth(size); b:SetHeight(size); b:ClearAllPoints()
      b:SetPoint(corner, f, corner, sx * I + g[1] * (n - 1) * size, (top and -I or 1 + lift) + g[2] * (n - 1) * size)
    end
  end
end

-- Sizes and anchors: out of combat only.
function CP.Layout()
  local s = CP.settings
  local w, h = s.frameWidth, s.frameHeight
  CP.Resize()
  local scale = math.min(h / 36, w / 72) -- the client's componentScale
  for _, f in ipairs(CP.frames) do
    local mini = f.mini
    local fh = mini and petHeight(s) or h
    f:SetWidth(w); f:SetHeight(fh)
    CP.Anchor(f)
    local power = s.displayPowerBar and not mini
    f.health:ClearAllPoints()
    local I = CP.INSET
    f.health:SetPoint("TOPLEFT", f, "TOPLEFT", I, -I); f.health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -I, I + (power and CP.POWER_H + 1 or 0))
    f.health.fullWidth, f.power.fullWidth = w - 2 * I, w - 2 * I
    f.power:ClearAllPoints()
    f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -1); f.power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -I, I)
    f.nameLeft = mini and 6 or I + 1
    f.name:ClearAllPoints(); f.name:SetPoint("TOPLEFT", f, "TOPLEFT", f.nameLeft, mini and 0 or 1 - I)
    f.name:SetPoint("TOPRIGHT", f, "TOPRIGHT", -I, mini and 0 or 1 - I)
    f.name:SetHeight(12)
    if mini then f.name:ClearAllPoints(); f.name:SetPoint("LEFT", f, "LEFT", 6, 1); f.name:SetPoint("RIGHT", f, "RIGHT", -I, 1) end
    setSize(f.name, scale); setSize(f.status, scale)
    f.status:ClearAllPoints()
    f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", I, fh / 3 - 2); f.status:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -I, fh / 3 - 2)
    f.status:SetHeight(12 * scale)
    f.leader:ClearAllPoints(); f.leader:SetPoint("TOPLEFT", f, "TOPLEFT", I, -I)
    f.looter:ClearAllPoints(); f.looter:SetPoint("TOPLEFT", f, "TOPLEFT", I, -I)
    f.raidTarget:ClearAllPoints(); f.raidTarget:SetPoint("RIGHT", f, "RIGHT", -I, 0)
    CP.LayoutAuras(f, scale)
    for n, t in ipairs(f.dispel) do -- top right, going left
      t:SetWidth(12 * scale); t:SetHeight(12 * scale); t:ClearAllPoints()
      t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -I - (n - 1) * 12 * scale, -I)
    end
  end
end

---------------------------------------------------------------- drawing
local function healthColor(f, unit)
  if CP.settings.useClassColors and UnitIsPlayer(unit) then
    local _, token = UnitClass(unit)
    local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
  end
  return FRIENDLY[1], FRIENDLY[2], FRIENDLY[3]
end

-- A client without the call has no AFK flag / group leader: those show nothing.
local function afk(unit) return UnitIsAFK and UnitIsAFK(unit) end
local function leaderOf(unit)
  local fn = UnitIsGroupLeader or UnitIsPartyLeader
  return fn and fn(unit)
end
local function looterOf(unit)
  if not GetLootMethod then return false end
  local method, party = GetLootMethod()
  if method ~= "master" or not party then return false end
  if party == 0 then return UnitIsUnit(unit, "player") end
  return UnitIsUnit(unit, "party" .. party)
end

local function healthText(unit, cur, max)
  local mode = CP.settings.healthText
  if mode == "Health Remaining" then return tostring(cur)
  elseif mode == "Health Lost" then return max - cur > 0 and ("-" .. (max - cur)) or ""
  elseif mode == "Percentage" and max > 0 then return math.ceil(100 * cur / max) .. "%" end
  return ""
end

-- Health, power, name, status text: drawing only, safe in combat.
function CP.DrawBars(f)
  local unit = f.unit
  if not UnitExists(unit) then return end
  local offline = not UnitIsConnected(unit)
  local cur, max = UnitHealth(unit), UnitHealthMax(unit)
  local dead = UnitIsDead(unit) or UnitIsGhost(unit) or (max > 0 and cur <= 0)
  f.health:SetMinMaxValues(0, max > 0 and max or 1)
  f.health:SetValue(offline and (max > 0 and max or 1) or cur)
  local hr, hg, hb = 0.5, 0.5, 0.5
  if not offline then hr, hg, hb = healthColor(f, unit) end
  f.health:SetStatusBarColor(hr, hg, hb)
  CP.SetFill(f.health, max > 0 and (offline and 1 or cur / max) or 0, hr, hg, hb)
  local name = (GetUnitName or UnitName)(unit, true) or ""
  f.name:SetText(name)
  if offline or (dead and not UnitIsPlayer(unit)) then f.name:SetVertexColor(0.5, 0.5, 0.5) else f.name:SetVertexColor(1, 1, 1) end
  local text = ""
  if f.mini then text = ""
  elseif offline then text = PLAYER_OFFLINE or "Offline"
  elseif dead then text = UnitIsGhost(unit) and (GHOST or "Ghost") or DEAD or "Dead"
  elseif afk(unit) then text = "AFK"
  else text = healthText(unit, cur, max) end
  f.status:SetText(text)
  local pcur, pmax = AFUI.UnitPower(unit)
  if CP.settings.displayPowerBar and not f.mini and pmax and pmax > 0 then
    local c = PowerBarColor and PowerBarColor[UnitPowerType(unit)] or { r = 0, g = 0, b = 1 }
    f.power:SetMinMaxValues(0, pmax); f.power:SetValue(offline and 0 or pcur)
    f.power:SetStatusBarColor(c.r, c.g, c.b)
    CP.SetFill(f.power, offline and 0 or pcur / pmax, c.r, c.g, c.b)
    f.power:Show()
  else
    f.power:Hide()
  end
end

-- Target outline and the aggro outline (UnitThreatSituation 1-3 in yellow / orange / red).
function CP.DrawHighlights(f)
  local unit = f.unit
  if CP.preview or not UnitExists(unit) or not UnitIsUnit(unit, "target") then f.selection:Hide() else f.selection:Show() end
  local status = not CP.preview and UnitThreatSituation and UnitThreatSituation(unit)
  if status and status > 0 then
    local c = (GetThreatStatusColor and { GetThreatStatusColor(status) }) or THREAT[status] or THREAT[1]
    f.aggro:SetVertexColor(c[1], c[2], c[3]); f.aggro:Show()
  else
    f.aggro:Hide()
  end
end

-- Leader, master looter, raid target; the name makes room for the crown / bag.
function CP.DrawIcons(f)
  local unit = f.unit
  local lead, loot = not f.mini and leaderOf(unit), not f.mini and looterOf(unit)
  if lead then f.leader:Show() else f.leader:Hide() end
  if loot then f.looter:Show() else f.looter:Hide() end
  if lead and loot then f.looter:ClearAllPoints(); f.looter:SetPoint("LEFT", f.leader, "RIGHT", 0, 0)
  else f.looter:ClearAllPoints(); f.looter:SetPoint("TOPLEFT", f, "TOPLEFT", CP.INSET, -CP.INSET) end
  local off = (lead and 12 or 0) + (loot and 12 or 0)
  f.name:ClearAllPoints()
  if f.mini then f.name:SetPoint("LEFT", f, "LEFT", 6, 1); f.name:SetPoint("RIGHT", f, "RIGHT", -CP.INSET, 1)
  else
    f.name:SetPoint("TOPLEFT", f, "TOPLEFT", f.nameLeft + off, 1 - CP.INSET); f.name:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CP.INSET, 1 - CP.INSET)
  end
  local index = GetRaidTargetIndex and GetRaidTargetIndex(unit)
  if index and index > 0 then
    SetRaidTargetIconTexture(f.raidTarget, index); f.raidTarget:Show()
  else
    f.raidTarget:Hide()
  end
end

-- The auras (AuraFilters.lua decides which: the mode, the list, the extras, the order and how many; UnitBuff / UnitDebuff differ between the clients, it reads both).
-- Nothing is allocated here: the result tables, the dispel type list and the icons are reused. Drawing only: safe in combat.
local GOLD = { 1, 0.82, 0 }
local RESULT = { buffs = { n = 0 }, debuffs = { n = 0 } }
local KINDS_SEEN = {}

-- The time left as a number: a string is made only when the second changed.
local function stamp(b, now)
  local sec = math.floor(b.expires - now + 0.5)
  if sec == b.lastSec then return end
  b.lastSec = sec
  if sec <= 0 then b.time:SetText("") elseif sec >= 60 then b.time:SetText(math.floor(sec / 60) .. "m") else b.time:SetText(sec) end
end

local function setAura(b, r, d, debuff)
  b.icon:SetTexture(r.icon)
  local count = r.count
  if d.stacks and count and count > 1 then b.count:SetText(count); b.count:Show() else b.count:SetText(""); b.count:Hide() end
  local duration, expires = r.duration, r.expires
  local timed = duration and duration > 0 and expires and expires > 0
  if d.swipe and timed then
    local start = expires - duration
    if CooldownFrame_Set then CooldownFrame_Set(b.cd, start, duration, 1) elseif CooldownFrame_SetTimer then CooldownFrame_SetTimer(b.cd, start, duration, 1) end
    b.cd:Show()
  else
    b.cd:Hide()
  end
  if timed and d.timer then b.expires = expires; stamp(b, GetTime())
  else b.expires = nil; if b.lastSec then b.lastSec = nil; b.time:SetText("") end end
  -- the border: the entry's own colour, else a debuff's dispel colour, else the gold of a high priority entry
  local cr, cg, cb
  if r.cr then cr, cg, cb = r.cr, r.cg, r.cb
  elseif debuff and d.typeBorder then
    local c = DebuffTypeColor and (DebuffTypeColor[r.kind or "none"] or DebuffTypeColor.none) or nil
    if c then cr, cg, cb = c.r, c.g, c.b else cr, cg, cb = 0.8, 0, 0 end
  elseif d.highlight and r.hi then cr, cg, cb = GOLD[1], GOLD[2], GOLD[3] end
  if cr then b.border:SetVertexColor(cr, cg, cb); b.border:Show() else b.border:Hide() end
  b:Show()
end

-- The time left on the icons that show it, once a second (a string is made only when the second changed).
function CP.TickTimers()
  local now = GetTime()
  for _, f in ipairs(CP.frames) do
    if f:IsShown() and not f.mini then
      for _, list in ipairs(f.auraLists) do
        for n = 1, #list do
          local b = list[n]
          if b.expires and b:IsShown() then stamp(b, now) end
        end
      end
    end
  end
end

-- Buffs and debuffs through the filters (bottom right and bottom left unless the window says otherwise), and the dispellable types as icons top right plus the frame
-- outline in the first type's colour (what the client's own filter says you can dispel).
function CP.DrawAuras(f)
  f.auraDirty = false
  local unit = f.unit
  local lists = f.auraLists
  for l = 1, 3 do local list = lists[l]; for n = 1, #list do list[n]:Hide() end end
  f.dispelGlow:Hide()
  local AF = AFUI.AuraFilters
  if f.mini or not AF or not UnitExists(unit) or not UnitBuff then return end
  local D = AF.DisplayOf("party")
  local n = AF.Collect(unit, false, AF.Resolve("party", "buffs"), RESULT.buffs)
  for i = 1, n do setAura(f.buffs[i], RESULT.buffs[i], D.buffs, false) end
  n = AF.Collect(unit, true, AF.Resolve("party", "debuffs"), RESULT.debuffs, CP.settings.onlyDispellable and RAID_FILTER or nil)
  for i = 1, n do setAura(f.debuffs[i], RESULT.debuffs[i], D.debuffs, true) end
  n = 0
  for i = 1, 40 do
    local name, kind, _
    if IS_243 then name, _, _, _, kind = UnitDebuff(unit, i, RAID_FILTER) else name, _, _, kind = UnitDebuff(unit, i, RAID_FILTER) end
    if not name then break end
    if kind then
      local known = false
      for k = 1, n do if KINDS_SEEN[k] == kind then known = true; break end end
      if not known then
        n = n + 1; KINDS_SEEN[n] = kind
        if ART and f.dispel[n] then f.dispel[n]:SetTexture(ART.debuff .. kind); f.dispel[n]:Show() end
        if n == 1 and D.dispelHighlight then
          local c = DebuffTypeColor and DebuffTypeColor[kind]
          if c then f.dispelGlow:SetVertexColor(c.r, c.g, c.b); f.dispelGlow:Show() end
        end
      end
    end
  end
end

-- UNIT_AURA marks the frames of that unit and the next frame draws them once (CP.FlushAuras, from the container's OnUpdate): a raid-wide burst costs one pass per unit.
function CP.MarkAuras(unit)
  for _, f in ipairs(CP.frames) do
    if not unit or f.unit == unit or f.realUnit == unit then f.auraDirty = true; CP.auraPending = true end
  end
end
function CP.FlushAuras()
  if not CP.auraPending then return end
  CP.auraPending = false
  for _, f in ipairs(CP.frames) do if f.auraDirty then CP.DrawAuras(f) end end
end

-- Everything of one frame. Drawing only: safe in combat.
function CP.Draw(f)
  CP.DrawBars(f); CP.DrawHighlights(f); CP.DrawIcons(f); CP.DrawAuras(f)
end

function CP.DrawAll() for _, f in ipairs(CP.frames) do CP.Draw(f) end end

-- Out of range members fade (UnitInRange, alpha 0.55); not in Edit Mode, and a client without UnitInRange (2.4.3) never fades.
function CP.UpdateRange()
  for _, f in ipairs(CP.frames) do
    if f:IsShown() then
      local out = false
      if not CP.preview and UnitInRange and UnitExists(f.unit) and not UnitIsUnit(f.unit, "player") and not UnitIsUnit(f.unit, "pet") then
        local inRange, checked = UnitInRange(f.unit)
        out = checked and not inRange
      end
      f:SetAlpha(out and CP.OUT_OF_RANGE_ALPHA or 1)
    end
  end
end

---------------------------------------------------------------- shown state
-- The member units in slot order: Group keeps you, party1-4; Alphabetical sorts the ones that are there by name.
function CP.Order()
  local list = { "player", "party1", "party2", "party3", "party4" }
  if CP.settings.sortBy ~= "Alphabetical" or CP.preview or not UnitExists("party1") then return list end
  local have, rest = {}, {}
  for _, u in ipairs(list) do if UnitExists(u) then have[#have + 1] = u else rest[#rest + 1] = u end end
  table.sort(have, function(a, b)
    local x, y = string.lower(UnitName(a) or ""), string.lower(UnitName(b) or "")
    if x == y then return a < b end
    return x < y
  end)
  for _, u in ipairs(rest) do have[#have + 1] = u end
  return have
end

-- Which slots show: out of a raid, with the option on; you and your pet only while you are in a group; the others by their unit watch.
-- In Edit Mode (CP.preview) all of them show, those with no unit of their own with yours.
function CP.Refresh()
  if not CP.container then return end
  local s = CP.settings
  local on = CP.IsOn() and (CP.preview or AFUI.RaidSize() == 0)
  local order = CP.Order()
  local members = 0
  for i = 1, CP.MEMBERS do
    local f = CP.frames[i]
    f.realUnit = order[i]
    if f:GetAttribute("unit") ~= order[i] then f:SetAttribute("unit", order[i]) end
    if CP.preview or (UnitExists("party1") and UnitExists(order[i])) then members = members + 1 end
  end
  local pets = 0 -- the last pet slot that is there: the frame reaches down to it
  for n = 1, CP.MEMBERS do
    if CP.preview or UnitExists(SLOTS[CP.MEMBERS + n]) then pets = n end
  end
  CP.shownMembers, CP.shownPets = members > 0 and members or nil, pets > 0 and pets or nil
  if CP.petRow ~= members then
    CP.petRow = members
    for i = CP.MEMBERS + 1, #SLOTS do CP.Anchor(CP.frames[i]) end
  end
  for i, f in ipairs(CP.frames) do
    local pet = isPet(i)
    local want = on and (not pet or s.displayPets)
    local manual = i == 1 or i == CP.MEMBERS + 1 -- player and pet are always there: shown by hand while you are grouped
    if CP.preview then
      f.unit = UnitExists(f.realUnit) and f.realUnit or (pet and "pet" or "player")
    else
      f.unit = f.realUnit
    end
    if want and not CP.preview and not manual then
      if not f.watched then RegisterUnitWatch(f); f.watched = true end
    else
      if f.watched then UnregisterUnitWatch(f); f.watched = nil end
      local show = want and (CP.preview or (UnitExists("party1") and UnitExists(f.realUnit)))
      if show then f:Show() else f:Hide() end
    end
  end
  -- the group's frame (and the dark line between the plates) follows Display Border and grows / shrinks with the plates
  CP.Resize()
  local framed = on and border(s) and (CP.preview or members > 0)
  if CP.border then if framed then CP.border:Show() else CP.border:Hide() end end
  if CP.container.back then if framed then CP.container.back:Show() else CP.container.back:Hide() end end
  CP.DrawAll()
  CP.UpdateRange()
end

-- Settings from the Edit Mode layout (frameWidth ... and the frame scale); runs out of combat.
function CP.Apply(s)
  for k in pairs(CP.DEFAULTS) do
    if s[k] ~= nil then CP.settings[k] = s[k] end
  end
  CP.scale = s.scale or 1
  if not CP.container then return end -- Setup (login) draws them with these settings
  CP.container:SetScale(CP.scale)
  CP.Layout()
  if AFUI.Units and AFUI.Units.ApplyPartyVisibility then AFUI.Units.ApplyPartyVisibility() else CP.Refresh() end
end

-- Blizzard's own raid-style party frames (Interface option, CVar useCompactPartyFrames) draw over the party frames and cannot be moved or
-- resized in Edit Mode: the Edit Mode checkbox is the one switch, so the client's is turned off (out of combat) and said once.
function CP.NativeOff()
  if not (GetCVar and SetCVar) or InCombatLockdown() then return end
  local ok, v = pcall(GetCVar, "useCompactPartyFrames")
  if not (ok and (v == "1" or v == 1 or v == true)) then return end
  pcall(SetCVar, "useCompactPartyFrames", "0")
  if CP.told then return end
  CP.told = true
  AFUI.Print("Blizzard's raid-style party frames are off: use Edit Mode > Party Frames > Use Raid-Style Party Frames instead.")
end

function CP.Setup()
  local c = CreateFrame("Frame", "AFUI_CompactPartyFrame", UIParent)
  c:SetFrameStrata("LOW")
  CP.container = c
  c:SetScale(CP.scale or 1)
  local u1 = AFUI.Units and AFUI.Units.party1
  c:SetPoint("TOPLEFT", u1 and u1.frame or UIParent, "TOPLEFT", 0, 0)
  if ART then
    c.back = c:CreateTexture(nil, "BACKGROUND"); c.back:SetAllPoints(c) -- shows as the 1 px dark line between the plates
    AFUI.SetColor(c.back, 0, 0, 0, 0.75)
    CP.border = buildBorder(c)
  end
  for i = 1, #SLOTS do build(i) end
  CP.Layout()
  CP.Refresh()
  local function each(fn) return function(_, unit)
    for _, f in ipairs(CP.frames) do if not unit or f.unit == unit or f.realUnit == unit then fn(f) end end
  end end
  local bars = each(CP.DrawBars)
  AFUI.On("UNIT_HEALTH", bars); AFUI.On("UNIT_MAXHEALTH", bars)
  for _, e in ipairs(AFUI.POWER_EVENTS) do AFUI.On(e, bars) end
  AFUI.On("UNIT_NAME_UPDATE", function(e, unit) each(CP.Draw)(e, unit); if CP.settings.sortBy == "Alphabetical" then AFUI.RunOutOfCombat(CP.Refresh) end end)
  AFUI.On("UNIT_CONNECTION", each(CP.Draw)); AFUI.On("UNIT_FLAGS", each(CP.Draw)); AFUI.On("PLAYER_FLAGS_CHANGED", each(CP.Draw))
  AFUI.On("UNIT_AURA", function(_, unit) CP.MarkAuras(unit) end)
  local AF = AFUI.AuraFilters
  if AF then -- a list, assignment or display option changed: icons laid out again (out of combat) and every frame redrawn
    AF.OnChange(function()
      AFUI.RunOutOfCombat(function() for _, f in ipairs(CP.frames) do CP.LayoutAuras(f) end end)
      CP.MarkAuras(); CP.FlushAuras()
    end)
    AFUI.On("SPELLS_CHANGED", function() CP.MarkAuras() end)
  end
  AFUI.On("UNIT_THREAT_SITUATION_UPDATE", each(CP.DrawHighlights))
  AFUI.On("PLAYER_TARGET_CHANGED", function() for _, f in ipairs(CP.frames) do CP.DrawHighlights(f) end end)
  for _, e in ipairs({ "RAID_TARGET_UPDATE", "PARTY_LEADER_CHANGED", "PARTY_LOOT_METHOD_CHANGED" }) do
    AFUI.On(e, function() for _, f in ipairs(CP.frames) do CP.DrawIcons(f) end end)
  end
  AFUI.On("PARTY_MEMBER_ENABLE", each(CP.Draw)); AFUI.On("PARTY_MEMBER_DISABLE", each(CP.Draw))
  AFUI.On("UNIT_PET", function() AFUI.RunOutOfCombat(CP.Refresh) end)
  for _, e in ipairs(AFUI.GROUP_EVENTS) do AFUI.On(e, function() AFUI.RunOutOfCombat(CP.Refresh) end) end
  AFUI.On("PLAYER_ENTERING_WORLD", function() AFUI.RunOutOfCombat(CP.Refresh) end)
  for _, e in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do -- the band is whole pixels: it and the plates move with the scale
    AFUI.On(e, function() AFUI.RunOutOfCombat(function() CP.Layout(); CP.Refresh() end) end)
  end
  AFUI.On("CVAR_UPDATE", function() AFUI.RunOutOfCombat(CP.NativeOff) end)
  local acc = 0
  c:SetScript("OnUpdate", function(_, elapsed)
    if CP.auraPending then CP.FlushAuras() end
    acc = acc + elapsed
    if acc < 0.2 then return end
    acc = 0
    CP.UpdateRange()
    CP.TickTimers()
  end)
  CP.NativeOff()
end

AFUI.RegisterModule("CompactParty", { OnLogin = function() AFUI.RunOutOfCombat(CP.Setup) end })

-- /afui party: what is shown, for when the party looks doubled (paste it to Aztra).
AFUI.Slash.Register("party", function()
  local function b(v) return v and "1" or "0" end
  local old, new = {}, {}
  for i = 1, 4 do local f = AFUI.Units and AFUI.Units["party" .. i] and AFUI.Units["party" .. i].frame; old[i] = f and b(f:IsShown()) .. "/" .. string.format("%.1f", f:GetAlpha()) or "-" end
  for i, f in ipairs(CP.frames or {}) do new[i] = b(f:IsShown()) end
  local ok, cv = pcall(GetCVar, "useCompactPartyFrames")
  AFUI.Print("party: raidStyle=" .. tostring(CP.settings.useRaidStyle) .. " raidSize=" .. tostring(AFUI.RaidSize and AFUI.RaidSize()) .. " nativeCVar=" .. tostring(ok and cv)
    .. " old(shown/alpha)=" .. table.concat(old, ",") .. " compact(shown)=" .. table.concat(new, ",") .. " combat=" .. b(InCombatLockdown()))
end, "what the party frames are doing (for bug reports)", "/afui party")
