-- Version-difference layer: the only file that knows 2.4.3 from 2.5.3.
AFUI = AFUI or {}

local IS_243 = (GetBuildInfo()):sub(1, 4) == "2.4."
AFUI.IS_243 = IS_243

-- 2.4.3 has no global print (it arrived in 3.0); the default chat frame exists on both clients.
function AFUI.Print(msg) DEFAULT_CHAT_FRAME:AddMessage(msg) end

function AFUI.CreateBackdropFrame(name, parent)
  if IS_243 then return CreateFrame("Frame", name, parent) end
  return CreateFrame("Frame", name, parent, "BackdropTemplate")
end

---------------------------------------------------------------- settings
-- AztraForeverUIDB.settings (account wide, SavedVariables): the player's switches. A key the player never touched answers its default
-- (AFUI.SETTING_DEFAULTS, or the `default` argument). The settings panel builds on these two calls and WatchSettings.
AFUI.SETTING_DEFAULTS = { cooldownNumbers = true, showHotkeys = true, showMacroNames = true, rangeTint = true, procGlow = true }
local watchers = {}
function AFUI.WatchSettings(fn) watchers[#watchers + 1] = fn end

-- filter: "HELPFUL" or "HARMFUL". Returns name, icon, count, duration, expirationTime, debuffType.
if IS_243 then
  function AFUI.UnitAura(unit, index, filter)
    local name, icon, count, duration, timeLeft, debuffType
    if filter == "HARMFUL" then
      local _
      name, _, icon, count, debuffType, duration, timeLeft = UnitDebuff(unit, index)
    else
      local _
      name, _, icon, count, duration, timeLeft = UnitBuff(unit, index)
    end
    if not name then return end
    return name, icon, count, duration, duration and timeLeft and (GetTime() + timeLeft) or nil, debuffType
  end
else
  function AFUI.UnitAura(unit, index, filter)
    local name, icon, count, debuffType, duration, expirationTime = UnitAura(unit, index, filter)
    return name, icon, count, duration, expirationTime, debuffType
  end
end

-- Returns name, texture, startMS, endMS, isChannel; nil when not casting.
function AFUI.CastingInfo(unit)
  local name, a, b, c, d, e = UnitCastingInfo(unit)
  if name then
    if IS_243 then return name, c, d, e, false end -- name, rank, displayName, texture, start, end
    return name, b, c, d, false -- name, text, texture, start, end
  end
  name, a, b, c, d, e = UnitChannelInfo(unit)
  if not name then return end
  if IS_243 then return name, c, d, e, true end
  return name, b, c, d, true
end

function AFUI.ComboPoints()
  if IS_243 then return GetComboPoints() end
  return GetComboPoints("player", "target")
end

function AFUI.LevelColor(level)
  local c = (IS_243 and GetDifficultyColor or GetQuestDifficultyColor)(level)
  return c.r, c.g, c.b
end

if IS_243 then
  AFUI.POWER_EVENTS = { "UNIT_MANA", "UNIT_RAGE", "UNIT_ENERGY", "UNIT_FOCUS", "UNIT_MAXMANA",
    "UNIT_MAXRAGE", "UNIT_MAXENERGY", "UNIT_MAXFOCUS", "UNIT_DISPLAYPOWER" }
else
  AFUI.POWER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }
end

-- Abbreviated key text for a button's hotkey label.
function AFUI.BindingText(key)
  if IS_243 then return GetBindingText(key, "KEY_", 1) end
  return GetBindingText(key, 1)
end

-- Post-hook a FrameXML ActionButton_* function; fn gets the button (2.4.3 passes it as `this`).
function AFUI.HookActionButton(fname, fn)
  hooksecurefunc(fname, function(self) fn(IS_243 and this or self) end)
end

-- Paged secure action bar. The header must be created from AFUI.PAGED_HEADER_TEMPLATE and the
-- buttons (ActionBarButtonTemplate, ID 0 so they read the "action" attribute) parented to it.
AFUI.PAGED_HEADER_TEMPLATE = IS_243 and "SecureStateHeaderTemplate" or "SecureHandlerStateTemplate"

function AFUI.SetupPaging(header, buttons, driver)
  for i, b in ipairs(buttons) do b:SetAttribute("action", AFUI.ActionFor(1, i)) end
  if IS_243 then
    -- Driver -> "state-page" -> statemap "$input" -> header "state". On a click (and in
    -- ActionButton_CalculateAction) the child remaps its button to "p<state>" through the
    -- header's statebutton and reads "*action-p<state>". The header then sets "state-parent"
    -- on every child, whose OnAttributeChanged (ActionButton_UpdateAction) redraws the icon.
    local rules = {}
    for p = 1, 11 do
      rules[p] = p .. ":p" .. p
      for i, b in ipairs(buttons) do b:SetAttribute("*action-p" .. p, AFUI.ActionFor(p, i)) end
    end
    for _, b in ipairs(buttons) do
      b:SetAttribute("useparent-statebutton", true)
      header:SetAttribute("addchild", b)
    end
    header:SetAttribute("statebutton", table.concat(rules, ";"))
    header:SetAttribute("statemap-page", "$input")
  else
    for i, b in ipairs(buttons) do header:SetFrameRef("b" .. i, b) end
    -- Restricted code cannot call AFUI.ActionFor; this is the same formula.
    header:SetAttribute("_onstate-page", [[
      local page, i = tonumber(newstate) or 1, 1
      local b = self:GetFrameRef("b1")
      while b do
        b:SetAttribute("action", (page - 1) * 12 + i)
        i = i + 1
        b = self:GetFrameRef("b" .. i)
      end
    ]])
  end
  RegisterStateDriver(header, "page", driver)
end

-- Stance bar: 2.4.3 names the buttons ShapeshiftButtonN (and has a possess bar, PossessButtonN);
-- 2.5.3 renames them StanceButtonN and has no possess bar. `update` lists the Blizzard functions that
-- re-show/re-anchor the buttons (we post-hook them). Showing and hiding the bars is left to secure state drivers.
if IS_243 then
  AFUI.STANCE = { button = "ShapeshiftButton", frame = "ShapeshiftBarFrame",
    update = { "ShapeshiftBar_Update", "PossessBar_Update" } }
  AFUI.POSSESS = { button = "PossessButton", frame = "PossessBarFrame", count = 2 }
else
  AFUI.STANCE = { button = "StanceButton", frame = "StanceBarFrame", update = { "StanceBar_Update" } }
  AFUI.POSSESS = { count = 0 }
end

-- Unit frames: group/raid, combo and cooldown API differences.
if IS_243 then
  AFUI.GROUP_EVENTS = { "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE" }
  AFUI.COMBO_EVENT = "PLAYER_COMBO_POINTS"
  function AFUI.RaidSize() return GetNumRaidMembers() end
  function AFUI.IsLeader(unit)
    if unit == "player" then return IsPartyLeader() end
    return UnitIsPartyLeader(unit)
  end
  function AFUI.CooldownSet(cd, start, duration) CooldownFrame_SetTimer(cd, start, duration, 1) end
else
  AFUI.GROUP_EVENTS = { "GROUP_ROSTER_UPDATE" }
  AFUI.COMBO_EVENT = "UNIT_POWER_FREQUENT" -- player only; the handler filters the unit
  function AFUI.RaidSize() return IsInRaid() and GetNumGroupMembers() or 0 end
  function AFUI.IsLeader(unit) return UnitIsGroupLeader(unit) end
  function AFUI.CooldownSet(cd, start, duration) CooldownFrame_Set(cd, start, duration, true) end
end

-- Events after which the screen may have a new size (resolution, UI scale). 2.4.3 FrameXML only uses
-- DISPLAY_SIZE_CHANGED (ContainerFrame.lua); 2.5.3 documents both (UIManagerDocumentation, VideoDocumentation).
AFUI.SCREEN_EVENTS = IS_243 and { "DISPLAY_SIZE_CHANGED" } or { "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }

-- 2.4.3's SetPortraitTexture is already round; 2.5.3's is square and needs the Forever circle mask.
function AFUI.RoundPortrait(frame, tex, maskFile)
  if IS_243 then return end
  local mask = frame:CreateMaskTexture()
  mask:SetAllPoints(tex)
  mask:SetTexture(maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  tex:AddMaskTexture(mask)
end

-- The window corner portraits, drawn as strips (see below): the 2.5.3 client does not apply our MaskTexture here (Mat's shots), and a square cannot fill a round ring (its
-- corners stick out over the world). The picture is drawn as horizontal strips whose widths follow a circle of radius PORTRAIT_R: the ring's band
-- (opaque from r 25.2 to 31 px around the centre, measured on ui-frame-portraitmetal-cornertopleft-c60-2x) covers the stair steps and the picture fills
-- the whole opening. `tex` stays the logical picture (size, anchors, Show/Hide, SetTexture, SetTexCoord keep working: they are mirrored onto the
-- strips; tex itself is drawn at alpha 0); a unit portrait goes through AFUI.PortraitUnit(tex, unit).
local PORTRAIT_CX, PORTRAIT_CY, PORTRAIT_R, PORTRAIT_STEP = 25, -22, 26.5, 4
-- Pure: the strips of a circle of radius r, { y0, y1, half } with y from the centre (down positive); half = the widest chord inside the strip.
function AFUI.PortraitStrips(r, step)
  local out, y = {}, -r
  while y < r - 0.01 do
    local y1 = math.min(y + step, r)
    local near = (y < 0 and y1 > 0) and 0 or math.min(math.abs(y), math.abs(y1))
    out[#out + 1] = { y, y1, math.sqrt(math.max(r * r - near * near, 0)) }
    y = y1
  end
  return out
end

function AFUI.WindowPortrait(frame, tex)
  frame.afPortraitTex = tex
  tex:SetWidth(2 * PORTRAIT_R); tex:SetHeight(2 * PORTRAIT_R); tex:ClearAllPoints()
  tex:SetPoint("CENTER", frame, "TOPLEFT", PORTRAIT_CX, PORTRAIT_CY)
  if tex.afStrips then return end
  local l, t, r, b = 0, 0, 1, 1
  local strips, defs = {}, AFUI.PortraitStrips(PORTRAIT_R, PORTRAIT_STEP)
  tex.afStrips = strips
  for i, d in ipairs(defs) do
    local s = frame:CreateTexture(nil, "ARTWORK")
    s:SetWidth(2 * d[3]); s:SetHeight(d[2] - d[1])
    s:SetPoint("TOPLEFT", frame, "TOPLEFT", PORTRAIT_CX - d[3], PORTRAIT_CY - d[1])
    strips[i] = s
  end
  local function coords() -- the picture's rectangle cut to each strip
    for i, d in ipairs(defs) do
      local u0, u1 = (PORTRAIT_R - d[3]) / (2 * PORTRAIT_R), (PORTRAIT_R + d[3]) / (2 * PORTRAIT_R)
      local v0, v1 = (d[1] + PORTRAIT_R) / (2 * PORTRAIT_R), (d[2] + PORTRAIT_R) / (2 * PORTRAIT_R)
      strips[i]:SetTexCoord(l + (r - l) * u0, l + (r - l) * u1, t + (b - t) * v0, t + (b - t) * v1)
    end
  end
  tex.afStripCoords = coords
  local function take(a, c, d, e, f) -- SetTexCoord's 4 value form (left, right, top, bottom) or its 8 value one (UL, LL, UR, LR)
    if f then l, t, r, b = a, c, f, e else l, r, t, b = a, c, d, e end
  end
  local function wrap(name, after)
    local orig = tex[name]
    if not orig then return end
    tex[name] = function(self, ...)
      local res = orig(self, ...)
      for _, s in ipairs(strips) do if s[name] then s[name](s, ...) end end
      if after then after(...) end
      return res
    end
  end
  wrap("SetTexture"); wrap("Show"); wrap("Hide"); wrap("SetShown"); wrap("SetDesaturated"); wrap("SetVertexColor")
  wrap("SetTexCoord", function(...) take(...); coords() end)
  local tx = tex.GetTexture and tex:GetTexture()
  if tex.GetTexCoord and tex:GetTexCoord() then take(tex:GetTexCoord()) end
  if tx then for _, s in ipairs(strips) do s:SetTexture(tx) end end
  coords()
  if tex.IsShown and not tex:IsShown() then for _, s in ipairs(strips) do s:Hide() end end
  tex:SetAlpha(0)
end

-- A picture clipped to a shape made of rectangles (no usable mask on 2.5.3, see WindowPortrait): rects = { { x0, y0, x1, y1 } } in pixels from the picture's top
-- left; each one draws its part of the picture. Same mirroring as WindowPortrait (tex stays the logical picture at alpha 0, PortraitUnit works on it).
function AFUI.ClipTexture(frame, tex, rects, layer)
  if tex.afStrips then return end
  local l, t, r, b = 0, 0, 1, 1
  local strips = {}
  tex.afStrips = strips
  for i, d in ipairs(rects) do
    local s = frame:CreateTexture(nil, layer or "ARTWORK")
    s:SetWidth(d[3] - d[1]); s:SetHeight(d[4] - d[2])
    s:SetPoint("TOPLEFT", tex, "TOPLEFT", d[1], -d[2])
    strips[i] = s
  end
  local function coords()
    local w, h = tex:GetWidth() or 1, tex:GetHeight() or 1
    if w <= 0 or h <= 0 then return end
    for i, d in ipairs(rects) do
      strips[i]:SetTexCoord(l + (r - l) * d[1] / w, l + (r - l) * d[3] / w, t + (b - t) * d[2] / h, t + (b - t) * d[4] / h)
    end
  end
  tex.afStripCoords = coords
  local function take(a, c, d, e, f)
    if f then l, t, r, b = a, c, f, e else l, r, t, b = a, c, d, e end
  end
  for _, name in ipairs({ "SetTexture", "Show", "Hide", "SetShown", "SetDesaturated", "SetVertexColor", "SetTexCoord" }) do
    local orig = tex[name]
    if orig then
      tex[name] = function(self, ...)
        local res = orig(self, ...)
        for _, s in ipairs(strips) do if s[name] then s[name](s, ...) end end
        if name == "SetTexCoord" then take(...); coords() end
        return res
      end
    end
  end
  coords()
  tex:SetAlpha(0)
end

-- A unit's portrait on a window portrait (or any texture): every strip gets it, the picture's own coordinates are kept.
function AFUI.PortraitUnit(tex, unit)
  SetPortraitTexture(tex, unit)
  if tex.afStrips then
    for _, s in ipairs(tex.afStrips) do SetPortraitTexture(s, unit) end
    tex.afStripCoords()
  end
end

-- Current/max of the unit's active power (2.4.3 only has UnitMana*).
if IS_243 then
  function AFUI.UnitPower(unit) return UnitMana(unit), UnitManaMax(unit) end
else
  function AFUI.UnitPower(unit) return UnitPower(unit), UnitPowerMax(unit) end
end

-- Solid colour fill: 2.4.3 only has SetTexture(r, g, b, a); 2.5.3 split it into SetColorTexture.
function AFUI.SetColor(texture, r, g, b, a)
  if IS_243 then texture:SetTexture(r, g, b, a) else texture:SetColorTexture(r, g, b, a) end
end

-- UIDropDownMenu_SetText / SetWidth swapped their argument order after 2.4.3.
function AFUI.DropDownSetText(frame, text)
  if IS_243 then UIDropDownMenu_SetText(text, frame) else UIDropDownMenu_SetText(frame, text) end
end
function AFUI.DropDownSetWidth(frame, width)
  if IS_243 then UIDropDownMenu_SetWidth(width, frame) else UIDropDownMenu_SetWidth(frame, width) end
end

-- Spellbook API: 2.4.3 FrameXML/SpellBookFrame.lua uses GetSpellName / PickupSpell(index, book) / GameTooltip:SetSpell(index, book);
-- 2.5.3's (Gethe/wow-ui-source 2.5.3 Interface/FrameXML/SpellBookFrame.lua) uses GetSpellBookItemName / PickupSpellBookItem /
-- GameTooltip:SetSpellBookItem. The new names win where a client has them. Returns name, subName (rank text).
-- Tells the panel manager (UIParent.lua, both clients) the real size and place of a left panel we re-skinned. UIPanelWindows still holds the old
-- 353 x 424 (width / height) and a -16 x offset (the margin of the old art) for CharacterFrame, SpellBookFrame and PlayerTalentFrame, and the
-- manager re-anchors the panel with them right after it is shown, overwriting any position the addon gave it.
-- t = { width, height, xoffset, yoffset, bottomClampOverride }; xoffset / yoffset are the wanted TOPLEFT offsets from UIParent's top left
-- (y negative = down; the manager adds its TOP_OFFSET to the attribute, so it is taken off here).
function AFUI.PanelAttrs(frame, t)
  if not (_G.SetUIPanelAttribute and frame) then return end
  pcall(function()
    local top = UIParent.GetAttribute and UIParent:GetAttribute("TOP_OFFSET") or -104
    for k, v in pairs(t) do
      if k == "yoffset" then v = v - top end
      _G.SetUIPanelAttribute(frame, k, v)
    end
  end)
end

function AFUI.SpellBookName(index, book)
  return (GetSpellBookItemName or GetSpellName)(index, book)
end
function AFUI.PickupSpellBook(index, book)
  return (PickupSpellBookItem or PickupSpell)(index, book)
end
function AFUI.TooltipSpellBook(tooltip, index, book)
  if tooltip.SetSpellBookItem then return tooltip:SetSpellBookItem(index, book) end
  return tooltip:SetSpell(index, book)
end

---------------------------------------------------------------- status bars and bar text
-- Every bar fill goes through AFUI.Bar.Place: the fill is pinned to the frame's INNER rect (inset = { left, top, right, bottom },
-- measured from the frame art's opaque border, not from the sprite's transparent padding) by two anchors, so its height can never
-- differ from the inner rect; its width is the inner width times the fraction and never more. The tag on the texture lets the
-- preview check it (tools/preview/render.mjs, "Bar fills outside their frame").
AFUI.Bar = {}

-- 0..1 from any value: nil, NaN, a max that is not above the min all give an empty bar.
function AFUI.Bar.Fraction(value, min, max)
  if type(value) ~= "number" or type(min) ~= "number" or type(max) ~= "number" then return 0 end
  if value ~= value or min ~= min or max ~= max or max <= min then return 0 end
  local f = (value - min) / (max - min)
  return f < 0 and 0 or f > 1 and 1 or f
end

-- tex: the fill; frame: the bar frame; inset: inner rect { l, t, r, b }; frac: 0..1; atlas: optional atlas name whose texcoords are
-- cropped to frac; art: optional frame-art atlas name (the preview checks the inset against the art's opaque border).
-- opt: { w = the frame's width when known (a frame sized by two anchors has no GetWidth until laid out), h = the height of the
-- box the inset is measured in when it is not the frame's height, stretch = the art is stretched to the frame,
-- fa = the texture that draws the frame art (its atlas name is texture.afuiAtlas, set by AFUI.SetAtlas): the preview measures the art's window from the page pixels and
-- requires the fill's visible box to equal it (tools/preview/barcheck.mjs; grow = { l, t, r, b } units the fill may extend past the window), rim = { tex = a solid edge, px } for frames drawn as a
-- plain edge (the window is the edge rect shrunk by px) }. Returns the fill width.
function AFUI.Bar.Place(tex, frame, inset, frac, atlas, art, opt)
  opt = opt or {}
  frac = (type(frac) == "number" and frac == frac) and (frac < 0 and 0 or frac > 1 and 1 or frac) or 0
  local l, t, r, b = inset[1], inset[2], inset[3], inset[4]
  local inner = (opt.w or frame:GetWidth() or 0) - l - r
  tex.afuiBar = { frame = frame, inset = inset, art = art, stretch = opt.stretch, h = opt.h, fill = atlas, frac = frac,
    fa = opt.fa, rim = opt.rim, grow = opt.grow }
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", frame, "TOPLEFT", l, -t)
  if opt.h then tex:SetHeight(math.max(opt.h - t - b, 0)) else tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", l, b) end
  local w = inner > 0 and inner * frac or 0
  if w <= 0 then tex:Hide(); return 0 end
  tex:SetWidth(w)
  local e = atlas and AFUI_ATLAS and AFUI_ATLAS[atlas]
  if e then tex:SetTexture(e[1]); tex:SetTexCoord(e[4], e[4] + (e[5] - e[4]) * frac, e[6], e[7]) end
  tex:Show()
  return w
end

-- Puts `text` in the FontString, cut to `width` with "..." (a fixed one-line strip: no wrapping, never wider than the strip).
-- Measured with GetStringWidth, so it holds on both clients whatever SetWordWrap does. Returns the shown text.
function AFUI.FitText(fs, text, width)
  text = text == nil and "" or tostring(text)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
  if fs.SetMaxLines then fs:SetMaxLines(1) end
  fs:SetText(text)
  if not width or width <= 0 or (fs:GetStringWidth() or 0) <= width then return text end
  local chars = {} -- UTF-8 characters: a cut never leaves half of one
  for c in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = c end
  local function cut(n) return (table.concat(chars, "", 1, n):gsub("%s+$", "")) .. "..." end
  local lo, hi = 0, #chars -- the most characters that still fit (the width grows with n)
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    fs:SetText(cut(mid))
    if (fs:GetStringWidth() or 0) <= width then lo = mid else hi = mid - 1 end
  end
  local out = cut(lo)
  fs:SetText(out)
  return out
end

-- Like FitText for a text that may wrap to `lines` lines of `width` (a window title): wrapped, cut with "..." once it needs more lines.
-- Measured with GetStringHeight against one line's height; a FontString without it falls back to one cut line.
function AFUI.FitLines(fs, text, width, lines)
  text = text == nil and "" or tostring(text)
  if not (fs.GetStringHeight and width and width > 0) then return AFUI.FitText(fs, text, width) end
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  fs:SetWidth(width)
  fs:SetText("A")
  local limit = (fs:GetStringHeight() or 0) * lines + 0.5
  fs:SetText(text)
  if (fs:GetStringHeight() or 0) <= limit then return text end
  local chars = {}
  for c in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = c end
  local function cut(n) return (table.concat(chars, "", 1, n):gsub("%s+$", "")) .. "..." end
  local lo, hi = 0, #chars
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    fs:SetText(cut(mid))
    if (fs:GetStringHeight() or 0) <= limit then lo = mid else hi = mid - 1 end
  end
  local out = cut(lo)
  fs:SetText(out)
  return out
end

-- Popups, dialogs and dropdown lists sit above every window of ours and the map (whose client strata can be FULLSCREEN): StaticPopup1..4 are DIALOG by
-- default, so a confirmation opened from the map (Abandon Quest) showed behind it. Raised on every show and after StaticPopup_Show; nothing here is protected.
AFUI.STRATA_ORDER = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local raised = {}
local function raise(f)
  if f.GetFrameStrata and (AFUI.STRATA_ORDER[f:GetFrameStrata()] or 0) < AFUI.STRATA_ORDER.FULLSCREEN_DIALOG then f:SetFrameStrata("FULLSCREEN_DIALOG") end
end
function AFUI.RaisePopups()
  for _, name in ipairs({ "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4", "DropDownList1", "DropDownList2", "DropDownList3", "QuestFrame", "GossipFrame" }) do
    local f = _G[name]
    if f then
      raise(f)
      if not raised[f] and f.HookScript then raised[f] = true; f:HookScript("OnShow", raise) end
    end
  end
end
AFUI.RaisePopups()
if _G.StaticPopup_Show then hooksecurefunc("StaticPopup_Show", AFUI.RaisePopups) end

---------------------------------------------------------------- icons
-- A path the client cannot resolve draws as a solid GREEN square, a missing file as a blank one. Every Interface\Icons name our own code writes as a literal
-- is listed here (lower case; confirmed against the file list of the game data) and kept in step with tests/lua/known_icons.txt by tests/tools/icons.test.mjs.
AFUI.ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
AFUI.KNOWN_ICONS = {}
for n in ([[ability_backstab ability_hunter_beasttaming ability_hunter_swiftstrike ability_marksmanship ability_mount_ridinghorse ability_racial_bearform ability_racial_jackofalltrades
ability_rogue_eviscerate ability_stealth ability_warrior_innerrage inv_hammer_20 inv_misc_book_09 inv_misc_food_15 inv_misc_gem_01 inv_misc_grouplooking
inv_misc_map_01 inv_misc_note_01 inv_misc_pelt_wolf_01 inv_misc_questionmark inv_misc_spyglass_03 inv_shield_06 inv_shirt_guildtabard_01 spell_fire_fire
spell_fire_firebolt02 spell_frost_frostbolt02 spell_frost_frostnova spell_holy_auraoflight spell_holy_devotionaura spell_holy_holybolt spell_holy_magicalsentry
spell_holy_sealofsacrifice spell_holy_sealofwrath spell_holy_wordfortitude spell_nature_healingtouch spell_nature_lightning spell_nature_lightningshield
spell_nature_magicimmunity spell_nature_regeneration spell_nature_starfall spell_shadow_deathcoil spell_shadow_metamorphosis spell_shadow_rainoffire
spell_shadow_shadowwordpain trade_alchemy trade_blacksmithing trade_engineering trade_engraving trade_fishing trade_herbalism trade_leatherworking
trade_mining trade_tailoring inv_misc_herb_07 inv_sword_27 inv_misc_gem_opal_01]]):gmatch("%S+") do AFUI.KNOWN_ICONS[n] = true end

-- Path of one of our own icon constants ("Spell_Fire_Fire"); a name that is not on the list gives the question mark instead of a green square.
function AFUI.IconPath(name)
  if type(name) == "string" and AFUI.KNOWN_ICONS[name:lower()] then return "Interface\\Icons\\" .. name end
  return AFUI.ICON_FALLBACK
end

-- SetTexture with a net: a nil / empty path (an API that returned no icon) or one the client reads back as nil shows `fallback` (default the question mark).
function AFUI.SetIcon(texture, path, fallback)
  if not texture then return end
  fallback = fallback or AFUI.ICON_FALLBACK
  if (type(path) ~= "string" and type(path) ~= "number") or path == "" then path = fallback end
  texture:SetTexture(path)
  if texture.GetTexture and texture:GetTexture() == nil then texture:SetTexture(fallback) end
end

---------------------------------------------------------------- settings (the one switchboard every module reads; the panel is Settings.lua)
-- AFUI.GetSetting(key, default): the character's override (AztraForeverUICharDB.settings[key]) wins over the account value (AztraForeverUIDB.settings[key]), then `default`.
-- Asking for a key also marks it "provided": the panel shows an option only once some module has asked for its key, so no option is ever dead.
-- AFUI.SetSetting(key, value [, scope]): scope nil writes where the key lives now (the character override if there is one, else the account); "char" makes / updates an
-- override; "account" writes the account value and drops the override; a nil value clears. AFUI.OnSettingChanged(key, fn): fn(value, key) when the EFFECTIVE value changes.
local settingAsked, settingDefaults, settingSubs = {}, {}, {}
AFUI.SettingsProvided = settingAsked

local function settingTable(db, create)
  if type(db) ~= "table" then return nil end
  if type(db.settings) ~= "table" then
    if not create then return nil end
    db.settings = {}
  end
  return db.settings
end
local function accountSettings(create)
  if create and type(_G.AztraForeverUIDB) ~= "table" then _G.AztraForeverUIDB = {} end -- SavedVariables are loaded before any addon file runs: this only fills a missing table
  return settingTable(_G.AztraForeverUIDB, create)
end
local function charSettings(create) return settingTable(_G.AztraForeverUICharDB, create) end

local function effective(key, default)
  local c, a = charSettings(), accountSettings()
  if c and c[key] ~= nil then return c[key] end
  if a and a[key] ~= nil then return a[key] end
  if default == nil then return AFUI.SETTING_DEFAULTS[key] end
  return default
end

function AFUI.GetSetting(key, default)
  if not settingAsked[key] then settingAsked[key] = true; settingDefaults[key] = default end
  return effective(key, default)
end
-- A module that wants its option shown before it first reads the key (or never reads it through GetSetting) says so.
function AFUI.ProvideSetting(key, default)
  if not settingAsked[key] then settingAsked[key] = true; settingDefaults[key] = default end
end
function AFUI.SettingDefault(key) return settingDefaults[key] end
-- The value without marking the key as provided (the settings panel reads through this, or its own reading would make every option "provided").
function AFUI.PeekSetting(key, default) return effective(key, default) end
function AFUI.HasCharSetting(key) local c = charSettings(); return c ~= nil and c[key] ~= nil end

function AFUI.OnSettingChanged(key, fn)
  if type(fn) ~= "function" then return end
  settingSubs[key] = settingSubs[key] or {}
  table.insert(settingSubs[key], fn)
end

function AFUI.SetSetting(key, value, scope)
  local before = effective(key, settingDefaults[key])
  local c = charSettings()
  if scope == "char" then
    c = charSettings(true)
    if c then c[key] = value end
  else
    local a = accountSettings(true)
    if scope == "account" then
      if c then c[key] = nil end
      if a then a[key] = value end
    elseif c and c[key] ~= nil then c[key] = value
    elseif a then a[key] = value end
  end
  local after = effective(key, settingDefaults[key])
  if after ~= before then
    for _, fn in ipairs(settingSubs[key] or {}) do xpcall(function() fn(after, key) end, geterrorhandler()) end
    for _, fn in ipairs(watchers) do xpcall(function() fn(key, after) end, geterrorhandler()) end
  end
  return after
end
