-- Pet, stance and possess bars (Blizzard's buttons, reparented), XP/rep bar, micro menu, bags and end caps.
-- Forever references below are files under tools/ref/interface/addons/ (see docs/forever-ref/micromenu-bags.md and
-- statusbar.md); TBC references are FrameXML: 2.4.3 = MOUZU/Blizzard-WoW-Interface 2.4.3/FrameXML,
-- 2.5.3 = Gethe/wow-ui-source tag 2.5.3 Interface/FrameXML (+ Interface_TBC/FrameXML).
local main = AFUI.Bars.main

-- Forever restacks the bottom bars when one of them shows or hides (UpdateActionBarLayout); the order of the stack is in Presets.lua.
local function Restack() if AFUI.RestackBars then AFUI.RestackBars() end end

-- What differs between the two clients for these bars.
local CLIENT = AFUI.IS_243 and {
  -- Micro buttons Forever has no counterpart for. 2.4.3 MainMenuBarMicroButtons.xml: Character, Spellbook, Talent,
  -- QuestLog, Socials, LFG, MainMenu, Help. Forever hides Help (mainline mainmenubarmicrobuttons.xml:314).
  hideMicro = { "HelpMicroButton" },
  -- Blizzard functions after which the micro row is laid out again (2.4.3 MainMenuBarMicroButtons.lua:126-134
  -- UpdateTalentButton re-anchors QuestLog to Talent).
  microHooks = { "UpdateMicroButtons", "UpdateTalentButton" },
} or {
  -- 2.5.3 MainMenuBarMicroButtons.lua:5-15 adds WorldMap, which SetLookingForGroupUIAvailable swaps with LFG
  -- (Interface_TBC/FrameXML/UIParent.lua:4669-4682). Forever has no map button.
  hideMicro = { "HelpMicroButton", "WorldMapMicroButton" },
  microHooks = { "UpdateMicroButtons", "SetLookingForGroupUIAvailable" },
}

local function Atlas(tex, name, useSize) if tex then AFUI.SetAtlas(tex, name, useSize) end end
local function Shown(r, on) if on then r:Show() else r:Hide() end end -- no SetShown on 2.4.3

---------------------------------------------------------------- XP / reputation bar
-- watched = { name, standing, min, max, value } (GetWatchedFactionInfo order on both clients) or nil.
function AFUI.StatusBarValues(level, maxLevel, xp, xpMax, rested, watched)
  if watched and watched[1] then return "rep", watched[5] - watched[3], watched[4] - watched[3] end
  if level >= maxLevel then return "hidden" end
  return "xp", xp, xpMax, math.min(xp + (rested or 0), xpMax)
end

-- Forever (camelot statustrackingbarconstants.lua:1-28, mainline statustrackingbar.xml:3-33,
-- statustrackingmanageroverrides.lua:42-117): a 17 px container with the frame art and 19 dividers over a
-- (width - 3) x 14 bar at BOTTOMLEFT 1,2. Only the highest-priority bar is shown (rep over XP).
local HEIGHT, ADJUST, SEGMENTS = 17, 3, 20
local REP_COLOR = { "red", "red", "orange", "yellow", "green", "green", "green", "green" } -- reputationbaroverrides.lua:2-12
local function XpArt(n) return "ui-hud-experiencebar-" .. n .. "-c60" end

-- Lay the wide atlas `name` across `width` x `height` at the BOTTOMLEFT of `parent`, showing only its first `frac`.
-- Media/Atlas.lua splits art wider than a texture page into tiles (AFUI_ATLAS_TILES): each tile is drawn side by side
-- at its share of the width and the one the value cuts through is cropped by texcoord, never squashed.
local function DrawTiled(texs, parent, layer, name, width, height, frac)
  local tiles = AFUI_ATLAS_TILES and AFUI_ATLAS_TILES[name] or { name }
  local total = 0
  for _, t in ipairs(tiles) do total = total + AFUI_ATLAS[t][2] end
  local x, cut = 0, width * frac
  for i, t in ipairs(tiles) do
    local e = AFUI_ATLAS[t]
    local tex = texs[i] or parent:CreateTexture(nil, layer)
    texs[i] = tex
    local w = e[2] * width / total
    local shown = math.min(w, cut - x)
    if shown > 0 then
      tex:SetTexture(e[1])
      tex:SetTexCoord(e[4], e[4] + (e[5] - e[4]) * shown / w, e[6], e[7])
      tex:ClearAllPoints(); tex:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, 0)
      tex:SetWidth(shown); tex:SetHeight(height)
      tex:Show()
    else
      tex:Hide()
    end
    x = x + w
  end
  for i = #tiles + 1, #texs do texs[i]:Hide() end
end

-- Two bars as in the video: the XP bar (Status Bar 1, kind "xp") along the bottom and the watched faction's reputation bar
-- (Status Bar 2, kind "rep") stacked right above it; the rep bar shows only while a faction is watched ("Show as Experience Bar"
-- in Forever, "Show as Experience Bar" / the watched faction in TBC) and XP stays on bar 1.
local function BuildStatusBar(frameName, kind)
local sb = { frame = CreateFrame("Frame", frameName, UIParent), kind = kind, art = {}, bg = {}, rested = {}, fill = {}, dividers = {} }
local f = sb.frame
f:SetWidth(571); f:SetHeight(HEIGHT)
f:HookScript("OnShow", Restack); f:HookScript("OnHide", Restack) -- the XP bar hides at the level cap
f:EnableMouse(true)
sb.bar = CreateFrame("Frame", nil, f) -- background, rested preview, fill
sb.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, ADJUST - 1)
sb.bar:SetWidth(571 - ADJUST); sb.bar:SetHeight(HEIGHT - ADJUST)
sb.over = CreateFrame("Frame", nil, f) -- frame art, dividers and text above the fill (Forever: container MEDIUM, bar LOW)
sb.over:SetAllPoints(f); sb.over:SetFrameLevel(f:GetFrameLevel() + 2)
for i = 1, SEGMENTS - 1 do -- StatusBarDividerTemplate 3x10 (statustrackingbartemplate.xml:48-56)
  local d = sb.over:CreateTexture(nil, "ARTWORK")
  d:SetWidth(3); d:SetHeight(10)
  Atlas(d, XpArt("divider"))
  sb.dividers[i] = d
end
-- OverlayFrame.Text: TextStatusBarText (FRIZQT 10 outline, white) at CENTER 0,1, hidden (statustrackingbartemplate.xml:34-44)
sb.label = sb.over:CreateFontString(nil, "OVERLAY")
sb.label:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
sb.label:SetTextColor(1, 1, 1)
sb.label:SetPoint("CENTER", sb.bar, "CENTER", 0, 1)
sb.label:Hide()
-- ExhaustionTick: 10x14 pip, Frame-Pip art, Pip-Mouseover highlight ADD (expbar.xml:20-36)
sb.pip = CreateFrame("Button", nil, sb.over)
sb.pip:SetWidth(10); sb.pip:SetHeight(14)
sb.pip.afui = { normal = sb.pip:CreateTexture(nil, "ARTWORK"), highlight = sb.pip:CreateTexture(nil, "HIGHLIGHT") }
sb.pip.afui.normal:SetAllPoints(sb.pip)
Atlas(sb.pip.afui.normal, XpArt("frame-pip"))
sb.pip.afui.highlight:SetPoint("CENTER", sb.pip, "CENTER")
Atlas(sb.pip.afui.highlight, XpArt("frame-pip-mouseover"), true)
sb.pip.afui.highlight:SetBlendMode("ADD")
sb.pip:Hide()

-- Forever stretches the XP bar from the main bar's left edge under the micro menu and bags (the right cap covers the end).
-- shortcut: sized from the default composite (main bar + 4.5 + micro menu + 7 + bags) whenever the micro menu or bags
-- relayout; a bar moved or resized in Edit Mode keeps this width.
-- Modern (Mat's Forever): the bar sits on its own under the main bar, 32 wider than it (594 against 562 in his screenshot).
function sb.Resize()
  local cs = AFUI.EditMode and AFUI.EditMode.current.systems
  local c = cs and ((kind == "rep" and cs.statusbar2 and cs.statusbar2.width and cs.statusbar2) or cs.statusbar)
  local w
  if c and c.width then -- the "Status Bar 2" Width setting (0.5-1) of Forever's 1192 (video), never wider than the screen
    w = math.min(1192 * c.width, UIParent:GetWidth() or 1192)
  else
    w = main.frame:GetWidth() + 4.5 + AFUI.MicroMenu:GetWidth() + 7 + AFUI.BagBar:GetWidth()
  end
  f:SetWidth(w); sb.bar:SetWidth(w - ADJUST)
  DrawTiled(sb.art, sb.over, "BORDER", XpArt("frame"), w, HEIGHT, 1)
  DrawTiled(sb.bg, sb.bar, "BACKGROUND", XpArt("background"), w - ADJUST, HEIGHT - ADJUST, 1)
  for i, d in ipairs(sb.dividers) do -- PixelUtil.SetPoint at i * width / 20: whole pixels
    d:ClearAllPoints(); d:SetPoint("LEFT", f, "LEFT", math.floor(i * w / SEGMENTS + 0.5), 0)
  end
  if sb.mode then sb.Update() end
  if kind == "xp" and AFUI.StatusBar2 then AFUI.StatusBar2.Resize() end -- both bars share the width
end

-- Text shows while hovered or with the xpBarText CVar (statustrackingbar.lua:41-54).
local function ShowLabel() Shown(sb.label, sb.hover or GetCVar("xpBarText") == "1") end

function sb.Update()
  local watched = { GetWatchedFactionInfo() }
  local mode, value, max, restedValue = AFUI.StatusBarValues(UnitLevel("player"), MAX_PLAYER_LEVEL or 70,
    UnitXP("player"), UnitXPMax("player"), GetXPExhaustion(), kind == "rep" and watched[1] and watched or nil)
  if kind == "rep" and mode ~= "rep" then mode = "hidden" end -- no faction watched: the second bar is not there
  sb.mode = mode
  if mode == "hidden" then f:Hide(); return end
  f:Show()
  local w = sb.bar:GetWidth()
  local frac, fillArt, ratio = max > 0 and value / max or 0, nil, 0
  if mode == "xp" then
    -- expbaroverrides.lua:1-18: rested art while rested (rest state 1); XP_STATUS_BAR_TEXT "XP: %s/%s"
    fillArt = XpArt(GetRestState() == 1 and "fill-rested" or "fill-experience")
    sb.label:SetText((XP_STATUS_BAR_TEXT or "XP: %s/%s"):format(value, max))
    if restedValue > value and max > 0 then ratio = restedValue / max end
  else
    local name, standing = watched[1], watched[2]
    fillArt = XpArt("fill-reputation-faction-" .. (REP_COLOR[standing] or "green"))
    sb.label:SetText(standing == 8 and name or string.format("%s %d / %d", name, value, max)) -- exalted is capped
  end
  DrawTiled(sb.fill, sb.bar, "ARTWORK", fillArt, w, HEIGHT - ADJUST, frac)
  for _, t in ipairs(sb.fill) do t.afuiBar = { frame = sb.bar, inset = { 0, 0, 0, 0 } } end -- the preview checks the fill stays in the bar
  -- Rested preview: Fill-Prediction from 0 to the tick, 11 high; the pip hides within 1 % of either edge
  -- (expbar.xml:10-17, expbar.lua:125-162).
  DrawTiled(sb.rested, sb.bar, "BORDER", XpArt("fill-prediction"), w, 11, ratio)
  sb.pip:ClearAllPoints(); sb.pip:SetPoint("CENTER", sb.bar, "LEFT", ratio * w, 0)
  Shown(sb.pip, ratio >= 0.01 and ratio <= 0.99)
  ShowLabel()
end

-- Tooltip as Forever's ExhaustionToolTipText (expbaroverrides.lua:20-55): XP and the rest state.
local function XpTooltip(owner)
  if sb.mode ~= "xp" then return end
  local cur, max = UnitXP("player"), UnitXPMax("player")
  GameTooltip:SetOwner(owner, "ANCHOR_TOP")
  GameTooltip:SetText(string.format("%s %d / %d (%d%%)", XP or "XP", cur, max, max > 0 and math.ceil(cur / max * 100) or 0))
  local _, stateName, mult = GetRestState()
  if stateName and EXHAUST_TOOLTIP1 then GameTooltip:AddLine(EXHAUST_TOOLTIP1:format(stateName, mult * 100), 1, 1, 1) end
  GameTooltip:Show()
end
f:SetScript("OnEnter", function(self) sb.hover = true; ShowLabel(); XpTooltip(self) end)
f:SetScript("OnLeave", function() sb.hover = false; ShowLabel(); GameTooltip:Hide() end)
sb.pip:SetScript("OnEnter", XpTooltip)
sb.pip:SetScript("OnLeave", function() GameTooltip:Hide() end)
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION",
  "PLAYER_UPDATE_RESTING", "CVAR_UPDATE" }) do
  AFUI.On(e, sb.Update)
end
return sb
end

local sb = BuildStatusBar("AFUI_StatusBar", "xp")
AFUI.StatusBar = sb
local f = sb.frame
f:SetPoint("BOTTOM", main.frame, "TOP", 0, 2)
local sb2 = BuildStatusBar("AFUI_StatusBar2", "rep")
AFUI.StatusBar2 = sb2
sb2.frame:SetPoint("BOTTOM", f, "TOP", 0, 2)

---------------------------------------------------------------- end caps
-- Forever (camelot): 154x95 caps above the bar art (frame level 100), each its own Edit Mode system (docs/forever-ref/editmode.md
-- section 7). Until a layout places them: left RIGHT at the main bar's LEFT +30,+5, right LEFT at the bags' RIGHT -30,+5
-- (mainline editmodepresetlayouts.lua:628-652, camelot mainmenubarendcaps.xml).
local function capFrame(name)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetWidth(154); f:SetHeight(95)
  -- video3 f0001: the head lies OVER the bar's end button (buttons are main level + 1), under the page arrows (main level + 4)
  f:SetFrameLevel(main.frame:GetFrameLevel() + 3)
  return f, f:CreateTexture(nil, "OVERLAY")
end
local leftFrame, leftArt = capFrame("AFUI_EndCapLeft")
local rightFrame, rightArt = capFrame("AFUI_EndCapRight")
leftArt:SetAllPoints(leftFrame); rightArt:SetAllPoints(rightFrame)
AFUI.EndCaps = { left = leftArt, right = rightArt, leftFrame = leftFrame, rightFrame = rightFrame, hidden = {} }
function AFUI.EndCaps.Update()
  local art = "gryphon" -- camelot has one pair for both factions (docs/forever-ref/editmode.md section 7)
  AFUI.SetAtlas(AFUI.EndCaps.left, "ui-hud-actionbar-" .. art .. "-left")
  AFUI.SetAtlas(AFUI.EndCaps.right, "ui-hud-actionbar-" .. art .. "-right")
end
-- Shown while Edit Mode is open (even when hidden, so it can be edited), otherwise unless its Hide setting is on
-- (MainMenuBarEndCapMixin:UpdateVisibility).
function AFUI.EndCaps.Refresh()
  local editing = AFUI.EditMode and AFUI.EditMode.IsOpen and AFUI.EditMode.IsOpen()
  for side, frame in pairs({ left = leftFrame, right = rightFrame }) do
    -- "Hide Bar Art" on the main bar hides the caps too (MainActionBarMixin:UpdateEndCaps(self.hideBarArt))
    local artOff = main.settings and main.settings.hideBarArt
    if editing or (not AFUI.EndCaps.hidden[side] and not artOff) then frame:Show() else frame:Hide() end
  end
end
function AFUI.EndCaps.SetHidden(side, on)
  AFUI.EndCaps.hidden[side] = on and true or false
  AFUI.EndCaps.Refresh()
end

---------------------------------------------------------------- micro menu and bags
AFUI.MicroMenu = CreateFrame("Frame", "AFUI_MicroMenu", UIParent)
AFUI.BagBar = CreateFrame("Frame", "AFUI_BagBar", UIParent)
AFUI.EndCaps.leftFrame:SetPoint("RIGHT", main.frame, "LEFT", 30, 21)
AFUI.EndCaps.rightFrame:SetPoint("LEFT", AFUI.BagBar, "RIGHT", -30, 21)
-- Forever's row until Edit Mode places them: micro menu 4.5 right of the main bar, bags 7 right of the micro menu.
AFUI.MicroMenu:SetPoint("BOTTOMLEFT", main.frame, "BOTTOMRIGHT", 4.5, 0)
AFUI.BagBar:SetPoint("BOTTOMLEFT", AFUI.MicroMenu, "BOTTOMRIGHT", 7, 0)

-- UI-HUD-ActionBar-Frame as 9 textures (no 9-slice atlases on TBC): slice margins 16/20 texels = 8/10 display px
-- (UiTextureAtlasElementSliceData 26258). Spans the frame's TOPLEFT +x0,y0 to BOTTOMRIGHT +x1,y1.
local function NineSlice(frame, layer, x0, y0, x1, y1)
  local e, m, n = AFUI_ATLAS["ui-hud-actionbar-frame-c60-2x"], 8, 10
  local us = { e[4], e[4] + (e[5] - e[4]) * 2 * m / e[2], e[5] - (e[5] - e[4]) * 2 * m / e[2], e[5] } -- the margins are 16 / 20 texels of the 110 texel sprite (2 texels a display px)
  local vs = { e[6], e[6] + (e[7] - e[6]) * 2 * n / e[3], e[7] - (e[7] - e[6]) * 2 * n / e[3], e[7] }
  local cols = { { "LEFT", x0 }, { "LEFT", x0 + m }, { "RIGHT", x1 - m }, { "RIGHT", x1 } }
  local rows = { { "TOP", y0 }, { "TOP", y0 - n }, { "BOTTOM", y1 + n }, { "BOTTOM", y1 } }
  local texs = {}
  for j = 1, 3 do
    for i = 1, 3 do
      local t = frame:CreateTexture(nil, layer)
      t:SetTexture(e[1]); t:SetTexCoord(us[i], us[i + 1], vs[j], vs[j + 1])
      t:SetPoint("TOPLEFT", frame, rows[j][1] .. cols[i][1], cols[i][2], rows[j][2])
      t:SetPoint("BOTTOMRIGHT", frame, rows[j + 1][1] .. cols[i + 1][1], cols[i + 1][2], rows[j + 1][2])
      texs[#texs + 1] = t
    end
  end
  return texs
end

-- Only the main bar wears the frame art (mainline mainactionbar.xml BorderArt, TOPLEFT -6,6 / BOTTOMRIGHT 4,-5); bars 2 and 3 have none in Mat's capture.
main.BorderArt = NineSlice(main.frame, "BACKGROUND", -6, 6, 4, -5)

-- Main bar extras (mainline mainactionbar.xml / actionbuttonoverrides.lua / shared/mainactionbar.lua UpdateDividers): the wing
-- emblem behind empty slots (SlotArt; "Hide Bar Art" swaps it for the plain dark SlotBackground), 12 px dividers between the
-- buttons while the padding is the minimum, and the page number with its two arrows left of the bar (BOTTOMRIGHT of the bar's
-- BOTTOMLEFT -4,9; "Hide Bar Scrolling" hides them).
local mainDeco = CreateFrame("Frame", nil, main.frame)
mainDeco:SetAllPoints(main.frame); mainDeco:SetFrameLevel(main.frame:GetFrameLevel() + 3)
local mainDividers = {}
for i, b in ipairs(main.buttons) do
  b.slotArt = b:CreateTexture(nil, "BACKGROUND")
  b.slotArt:SetAllPoints(b); Atlas(b.slotArt, "ui-hud-actionbar-iconframe-slot")
  b.slotBack = b:CreateTexture(nil, "BACKGROUND")
  b.slotBack:SetAllPoints(b); Atlas(b.slotBack, "ui-hud-actionbar-iconframe-background")
  if i > 1 then
    local d = {}
    for _, p in ipairs({ { "top", "ui-hud-actionbar-frame-divider-threeslice-edgetop-c60" },
      { "mid", "!ui-hud-actionbar-frame-divider-threeslice-center-c60" },
      { "bottom", "ui-hud-actionbar-frame-divider-threeslice-edgebottom-c60" } }) do
      d[p[1]] = mainDeco:CreateTexture(nil, "OVERLAY")
      Atlas(d[p[1]], p[2])
    end
    d.top:SetWidth(12); d.top:SetHeight(15); d.bottom:SetWidth(12); d.bottom:SetHeight(15)
    d.top:SetPoint("TOPLEFT", b, "TOPLEFT", -7, 0)
    d.bottom:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -7, 0)
    d.mid:SetPoint("TOPLEFT", d.top, "BOTTOMLEFT"); d.mid:SetPoint("BOTTOMRIGHT", d.bottom, "TOPRIGHT")
    mainDividers[i] = d
  end
end
local page = CreateFrame("Frame", "AFUI_ActionBarPageNumber", main.frame)
page:SetWidth(17); page:SetHeight(34); page:SetFrameLevel(main.frame:GetFrameLevel() + 4)
page:SetPoint("BOTTOMRIGHT", main.frame, "BOTTOMLEFT", -4, 9)
main.page = page
page.text = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
page.text:SetPoint("CENTER", page, "CENTER", -1, 0)
local function PageButton(name, y, delta, art)
  -- Blizzard's own page change (ActionBar_PageUp / PageDown) is a protected call: a secure "actionbar" button makes it.
  local b = CreateFrame("Button", name, page, "SecureActionButtonTemplate")
  b:SetWidth(17); b:SetHeight(14); b:SetPoint("CENTER", page, "CENTER", 0, y)
  b:SetAttribute("type", "actionbar"); b:SetAttribute("action", delta)
  AFUI.SetButtonAtlas(b, { "ui-hud-actionbar-" .. art .. "-up", "ui-hud-actionbar-" .. art .. "-down",
    "ui-hud-actionbar-" .. art .. "-mouseover", "ui-hud-actionbar-" .. art .. "-disabled" })
  return b
end
page.up = PageButton("AFUI_ActionBarUpButton", 10, "increment", "pageuparrow")
page.down = PageButton("AFUI_ActionBarDownButton", -10, "decrement", "pagedownarrow")
local function UpdatePage() page.text:SetText(tostring(_G.CURRENT_ACTIONBAR_PAGE or 1)) end
AFUI.On("ACTIONBAR_PAGE_CHANGED", UpdatePage); AFUI.On("PLAYER_ENTERING_WORLD", UpdatePage)

-- The template's Icon is a BACKGROUND texture like the slot art, and the art is created later: the client draws same-layer regions in creation
-- order, so the wings covered every icon but a lucky one. The art therefore shows only while the slot is empty, and a filled slot always
-- gets its texture as the API gives it (no whitelist); a macro whose icon is not resolved yet shows the question mark until the next refresh.
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
function AFUI.RefreshSlot(b)
  local action = b.action or tonumber(b:GetAttribute("action"))
  local has = action and _G.HasAction and HasAction(action) and true or false
  local icon = _G[b:GetName() .. "Icon"]
  if has and icon then
    icon:SetTexture((_G.GetActionTexture and GetActionTexture(action)) or QUESTION); icon:Show()
  end
  local art = not main.settings.hideBarArt
  Shown(b.slotArt, art and not has); Shown(b.slotBack, not art and not has)
end
local function RefreshSlots() for _, b in ipairs(main.buttons) do AFUI.RefreshSlot(b) end end
if type(_G.ActionButton_Update) == "function" then
  AFUI.HookActionButton("ActionButton_Update", function(b) if b and b.slotArt then AFUI.RefreshSlot(b) end end)
end
for _, ev in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "UPDATE_BONUS_ACTIONBAR",
  "ACTIONBAR_PAGE_CHANGED" }) do AFUI.On(ev, RefreshSlots) end

function main.OnSettings(s)
  local art = not s.hideBarArt
  for _, t in ipairs(main.BorderArt) do Shown(t, art) end
  for i, b in ipairs(main.buttons) do
    AFUI.RefreshSlot(b)
    local d = mainDividers[i]
    local show = d and art and AFUI.ClampRows(s.numIcons or 12, s.numRows) == 1 and s.padding <= 2 and b:IsShown() and main.buttons[i - 1]:IsShown()
    if d then for _, t in pairs(d) do Shown(t, show) end end
  end
  Shown(page, not s.hideBarScrolling)
  UpdatePage()
  if AFUI.EndCaps and AFUI.EndCaps.Refresh then AFUI.EndCaps.Refresh() end
end
main.OnSettings(main.settings)

-- Micro menu (camelot mainmenubarmicromenu.xml): BorderArt -8,8 / 8,-8; BackgroundArt from the border's TOPLEFT -13,0
-- to its BOTTOMRIGHT 14,4. Both BACKGROUND, the panel created first so the 0.2 black wash draws on top of it (Forever's
-- order); the per-button frames are the buttons' own BACKGROUND, on child frames above both.
local mm = AFUI.MicroMenu
mm.BorderArt = NineSlice(mm, "BACKGROUND", -8, 8, 8, -8)
mm.BackgroundArt = mm:CreateTexture(nil, "BACKGROUND")
mm.BackgroundArt:SetPoint("TOPLEFT", mm, "TOPLEFT", -8 - 13, 8)
mm.BackgroundArt:SetPoint("BOTTOMRIGHT", mm, "BOTTOMRIGHT", 8 + 14, -8 + 4)
Atlas(mm.BackgroundArt, "ui-hud-actionbar-iconframe-background")

-- {global, Forever's texture family}. Order: camelot micromenucontaineroverrides.lua:2-21 (Character, Profession, Spellbook, Talent, Legacy,
-- QuestLog, Guild, LFD, ... MainMenu). Professions and PvP are buttons of ours (the client has none): Professions opens our overview window,
-- PvP the Character window's PvP tab (Forever's Legacy art, the shield, is theirs). Collections, Adventure Guide, Housing and Shop have no
-- TBC window and stay out.
local MICRO = {
  { "CharacterMicroButton" }, { "AFUI_ProfessionsMicroButton", "professions" }, { "SpellbookMicroButton", "spellbookabilities" },
  { "TalentMicroButton", "spectalents" }, { "AFUI_PVPMicroButton", "legacy" }, { "QuestLogMicroButton", "questlog" },
  { "SocialsMicroButton", "guildcommunities" }, { "LFGMicroButton", "groupfinder" }, { "MainMenuMicroButton", "gamemenu" },
}
-- MainMenuBarMicroButton 32x40 (mainmenubarmicrobuttons.xml:16-49); grid childXPadding -5 (mainmenubarmicromenu.xml:3).
local MICRO_W, MICRO_H, MICRO_PITCH = 32, 40, 27
-- The art names Forever draws: "-disable-" in every family but Legacy ("-disabled-").
local function MicroArt(family, state)
  if family == "legacy" and state == "disable" then state = "disabled" end
  return "ui-hud-micromenu-" .. family .. "-" .. state .. "-c60-2x"
end
mm:SetHeight(MICRO_H)

-- SetPushed / SetNormal (mainmenubarmicrobuttons.lua:471-490, character :645-671).
local function SetMicroState(b, pushed)
  local a = b.afui
  if a.pushed == pushed then return end -- 2.4.3 calls the character's SetPushed/SetNormal every frame
  a.pushed = pushed
  Shown(a.bg, not pushed); Shown(a.pushedBg, pushed)
  if a.family then
    local hl = b:GetHighlightTexture()
    Atlas(hl, MicroArt(a.family, pushed and "down" or "mouseover"))
    hl:SetBlendMode(pushed and "ADD" or "BLEND"); hl:SetAlpha(pushed and 0.5 or 1)
  else
    a.portrait:ClearAllPoints()
    a.portrait:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -7)
    a.portrait:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", pushed and -6 or -7, pushed and 5 or 7)
    Shown(a.pushedShadow, pushed)
  end
end
local function RefreshMicro(b) SetMicroState(b, b:GetButtonState() == "PUSHED") end

local function NewTexture(b, layer, atlas, x, y)
  local t = b:CreateTexture(nil, layer)
  t:SetPoint("CENTER", b, "CENTER", x or 0, y or 0)
  Atlas(t, atlas, true)
  return t
end

local function SkinMicro(b, family)
  b:SetWidth(MICRO_W); b:SetHeight(MICRO_H)
  b:SetHitRectInsets(0, 0, 0, 0) -- Blizzard's 29x58 buttons only take clicks below the top 18 px
  local a = { family = family }
  b.afui = a
  a.bg = NewTexture(b, "BACKGROUND", "ui-hud-micromenu-buttonbg-up-c60-2x")
  a.pushedBg = NewTexture(b, "BACKGROUND", "ui-hud-micromenu-buttonbg-down-c60-2x")
  local flash = _G[b:GetName() .. "Flash"] -- 2.5.3 only; MicroButtonPulse flashes it
  if flash then -- Forever's FlashBorder (mainmenubarmicrobuttons.xml:32)
    flash:ClearAllPoints(); flash:SetAllPoints(b)
    Atlas(flash, "ui-hud-micromenu-highlightalert-c60-2x"); flash:SetBlendMode("BLEND")
  end
  if family then
    for state, suffix in pairs({ Normal = "up", Pushed = "down", Disabled = "disable" }) do
      local get, art = b["Get" .. state .. "Texture"], MicroArt(family, suffix)
      Atlas(get(b), art)
      -- 2.5.3 MainMenuMicroButton's OnUpdate re-sets its file textures (MainMenuBarMicroButtons.xml:310-330).
      hooksecurefunc(b, "Set" .. state .. "Texture", function() Atlas(get(b), art) end)
    end
    -- The shadow is baked into the highlight, so the normal art hides while hovered (lua:451-467).
    b:HookScript("OnEnter", function(self) self:GetNormalTexture():SetAlpha(0) end)
    b:HookScript("OnLeave", function(self) self:GetNormalTexture():SetAlpha(1); RefreshMicro(self) end)
    b:HookScript("OnMouseDown", function(self) if self:IsEnabled() then SetMicroState(self, true) end end)
    b:HookScript("OnClick", RefreshMicro)
  else -- CharacterMicroButton (xml:51-94): no state art, a portrait over a shadow
    for _, t in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(), b:GetHighlightTexture(), b:GetDisabledTexture() }) do t:SetAlpha(0) end
    if MicroButtonPortrait then MicroButtonPortrait:Hide() end -- Blizzard's 18x25 portrait at TOP 0,-28
    a.shadow = NewTexture(b, "BORDER", "ui-hud-micromenu-portrait-shadow-2x")
    a.portrait = b:CreateTexture(nil, "ARTWORK") -- unmasked: TBC has no MaskTexture
    a.portrait:SetTexCoord(0.2, 0.8, 0.0666, 0.9)
    a.pushedShadow = NewTexture(b, "OVERLAY", "ui-hud-micromenu-portrait-down-2x", 1, -4)
    SetPortraitTexture(a.portrait, "player")
  end
  a.pushed = nil
  RefreshMicro(b)
end

-- Our own micro buttons. Each has the click, the tooltip with its key (Forever: "Professions (K)") and the window whose visibility
-- is the pushed look (Forever locks a button pushed while its window is open: mainmenubarmicrobuttons.lua:471-490).
local EXTRA = {
  AFUI_ProfessionsMicroButton = {
    text = _G.PROFESSIONS_BUTTON or "Professions", key = function() return "K" end,
    click = function() if AFUI.Professions then AFUI.Professions.Toggle() end end,
    windows = function() return { AFUI.Professions and AFUI.Professions.overview, _G.TradeSkillFrame, _G.CraftFrame } end,
  },
  AFUI_PVPMicroButton = {
    text = _G.PVP or "PvP", key = function() return GetBindingKey and GetBindingKey("TOGGLECHARACTER4") end,
    click = function() if ToggleCharacter then ToggleCharacter("PVPFrame") end end,
    windows = function() return { _G.PVPFrame } end,
  },
}
local function ExtraOpen(def)
  for _, f in ipairs(def.windows()) do if f and f:IsShown() then return true end end
  return false
end
local function SyncExtra(b)
  local def = EXTRA[b:GetName()]
  if not def then return end
  if ExtraOpen(def) then b:SetButtonState("PUSHED", true) else b:SetButtonState("NORMAL") end
  if b.afui then RefreshMicro(b) end
end
local function SyncExtras() for name in pairs(EXTRA) do if _G[name] then SyncExtra(_G[name]) end end end
local function HookExtraWindows() -- windows made later (Blizzard_TradeSkillUI is load-on-demand, the overview is built at login)
  for name, def in pairs(EXTRA) do
    local b = _G[name]
    for _, f in ipairs(b and def.windows() or {}) do
      if not f.afuiMicroHooked and f.HookScript then
        f.afuiMicroHooked = true
        f:HookScript("OnShow", function() SyncExtra(b) end)
        f:HookScript("OnHide", function() SyncExtra(b) end)
      end
    end
  end
end
local function MakeExtraMicro(name)
  AFUI.extraMicro = AFUI.extraMicro or {}
  if AFUI.extraMicro[name] then return AFUI.extraMicro[name] end
  local def = EXTRA[name]
  local b = CreateFrame("Button", name, mm)
  AFUI.extraMicro[name] = b
  b:SetWidth(MICRO_W); b:SetHeight(MICRO_H)
  for _, state in ipairs({ "Normal", "Pushed", "Disabled", "Highlight" }) do b["Set" .. state .. "Texture"](b, "Interface\\Buttons\\WHITE8X8") end -- skinned below
  b:RegisterForClicks("LeftButtonUp")
  b:SetScript("OnClick", function() def.click() end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local key = def.key and def.key()
    GameTooltip:SetText(def.text .. (key and (" (" .. (GetBindingText and GetBindingText(key, "KEY_") or key) .. ")") or ""), 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return b
end
local function ExtraWindowsChanged() HookExtraWindows(); SyncExtras() end
AFUI.On("ADDON_LOADED", ExtraWindowsChanged)
AFUI.On("PLAYER_ENTERING_WORLD", ExtraWindowsChanged)

-- Latency bar on the game menu button (xml:344-367): 19x39 at BOTTOM 0,-2, tinted every 10 s (lua:28-29,1985-2027).
-- 2.5.3 has C_Timer: one timer per 10 s, nothing per frame. 2.4.3 has none, so its OnUpdate only counts down.
local perfWait, perfArmed = 0, false
local function TintLatency()
  local b = MainMenuMicroButton
  if not (b and b.afui and b.afui.perf) then perfArmed = false; mm:SetScript("OnUpdate", nil); return end -- nothing to tint: stop
  local latency = math.max(select(3, GetNetStats())) -- 2.4.3: one latency; 2.5.3: home and world
  local red, green = latency > 300 and 1 or 0, latency > 600 and 0 or 1
  b.afui.perf:SetVertexColor(red, green, 0)
  local interval = PERFORMANCEBAR_UPDATE_INTERVAL or 10
  if C_Timer and C_Timer.After then
    C_Timer.After(interval, TintLatency)
  else
    perfWait = interval
    mm:SetScript("OnUpdate", function(_, elapsed)
      perfWait = perfWait - (elapsed or 0)
      if perfWait <= 0 then TintLatency() end
    end)
  end
end
local function StartLatency()
  if perfArmed then return end
  perfArmed = true
  TintLatency()
end

local function LayoutMicro()
  local x = 0
  for _, d in ipairs(MICRO) do
    local b = _G[d[1]]
    if b and b:IsShown() then -- talents below level 10, LFG while unavailable on 2.5.3: no gap
      b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", mm, "BOTTOMLEFT", x, 0)
      x = x + MICRO_PITCH
    end
  end
  mm:SetWidth(math.max(x + MICRO_W - MICRO_PITCH, 1))
  sb.Resize()
end
local function OnMicroUpdate()
  LayoutMicro()
  SyncExtras()
  for _, d in ipairs(MICRO) do
    local b = _G[d[1]]
    if b and b.afui and d[2] then RefreshMicro(b) end
  end
end

-- Bags bar (camelot mainmenubarbagbuttons.xml:51-97, shared bagsbar.lua:24-183): backpack at the bar's RIGHT, every next
-- shown button RIGHT of the previous one's LEFT -2, a divider between neighbours, BorderArt -6,6 / 5,-5.
-- {global, size, frame art}; slot art from camelot mainmenubarbagbuttons.lua:1-45,217-219.
local BAGS = {
  { "MainMenuBarBackpackButton", 45, "ui-hud-actionbar-iconframe-bags-c60" },
  { "CharacterBag0Slot", 45, "ui-hud-actionbar-iconframe-bags-c60" }, { "CharacterBag1Slot", 45, "ui-hud-actionbar-iconframe-bags-c60" },
  { "CharacterBag2Slot", 45, "ui-hud-actionbar-iconframe-bags-c60" }, { "CharacterBag3Slot", 45, "ui-hud-actionbar-iconframe-bags-c60" },
  { "KeyRingButton", 33, "ui-hud-actionbar-iconframe-small-c60" },
}
local BAG_H, BAG_GAP = 45, 2
local bagBar = AFUI.BagBar
bagBar:SetHeight(BAG_H)
bagBar.BorderArt = NineSlice(bagBar, "BACKGROUND", -6, 6, 5, -5)
local deco = CreateFrame("Frame", nil, bagBar) -- dividers over the buttons
deco:SetAllPoints(bagBar); deco:SetFrameLevel(bagBar:GetFrameLevel() + 3)
bagBar.dividers = {}

-- HorizontalDividerTemplate: 12 wide, three-slice ui-hud-actionbar-frame-divider (blizzard_actionbar mainactionbar.xml:10-17).
local function Divider(i)
  local d = bagBar.dividers[i]
  if d then return d end
  d = {}
  for _, p in ipairs({ { "top", "ui-hud-actionbar-frame-divider-threeslice-edgetop-c60" },
    { "mid", "!ui-hud-actionbar-frame-divider-threeslice-center-c60" },
    { "bottom", "ui-hud-actionbar-frame-divider-threeslice-edgebottom-c60" } }) do
    d[p[1]] = deco:CreateTexture(nil, "OVERLAY")
    Atlas(d[p[1]], p[2])
  end
  d.top:SetWidth(12); d.top:SetHeight(15); d.bottom:SetWidth(12); d.bottom:SetHeight(15)
  bagBar.dividers[i] = d
  return d
end
local function PlaceDivider(d, b)
  d.top:ClearAllPoints(); d.top:SetPoint("TOPLEFT", b, "TOPRIGHT", -5, 0)
  d.bottom:ClearAllPoints(); d.bottom:SetPoint("BOTTOMLEFT", b, "BOTTOMRIGHT", -5, 0)
  d.mid:ClearAllPoints(); d.mid:SetPoint("TOPLEFT", d.top, "BOTTOMLEFT"); d.mid:SetPoint("BOTTOMRIGHT", d.bottom, "TOPRIGHT")
  for _, t in pairs(d) do t:Show() end
end

---------------------------------------------------------------- bag bar mode: the full row, one bag icon, or nothing
-- Setting "bagBarMode" (Settings window and the Bags system of Edit Mode): "full" (backpack + 4 bags + key ring), "single" (the backpack button alone, with the free
-- slots over every bag as its count; left click = B, right click = back to the full row) or "hidden" (no bar; B and the key bindings still open the bags).
AFUI.BAG_BAR_MODES = { full = "Full row", single = "Single icon", hidden = "Hidden" }
local BAG_SPACER = 30 -- what a hidden bar keeps, so the right end cap and the XP bar end where the bar's right edge was (Forever's cap sits 30 inside the bar)
function AFUI.BagBarMode()
  local m = AFUI.GetSetting and AFUI.GetSetting("bagBarMode", "full")
  return AFUI.BAG_BAR_MODES[m] and m or "full"
end
function AFUI.SetBagBarMode(mode)
  if AFUI.BAG_BAR_MODES[mode] and AFUI.SetSetting then AFUI.SetSetting("bagBarMode", mode) end
end

-- Swaps one script of a Blizzard button for ours, remembering the client's; fn nil puts the client's back.
local function SwapScript(b, name, fn)
  b.afuiOrig = b.afuiOrig or {}
  if fn then
    if b.afuiOrig[name] == nil then b.afuiOrig[name] = b:GetScript(name) or false end
    b:SetScript(name, fn)
  elseif b.afuiOrig[name] ~= nil then
    b:SetScript(name, b.afuiOrig[name] or nil)
    b.afuiOrig[name] = nil
  end
end

local function SingleTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText(BACKPACK_TOOLTIP or "Backpack", 1, 1, 1)
  local B = AFUI.Bags
  local info = B and B.Info and B.Info() or {}
  local free, total, used = B.Totals(info)
  GameTooltip:AddLine(used .. "/" .. total .. " slots used (" .. free .. " free)", 0.8, 0.8, 0.8)
  for _, e in ipairs(info) do GameTooltip:AddDoubleLine(e.name, (e.total - e.free) .. "/" .. e.total, 1, 1, 1, 1, 0.82, 0) end
  GameTooltip:AddLine("Left-click: open or close all bags", 0.5, 0.5, 0.5)
  GameTooltip:AddLine("Right-click: show every bag again", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

local function SingleClick(_, button)
  if CursorHasItem and CursorHasItem() then
    if PutItemInBackpack then PutItemInBackpack() end
  elseif button == "RightButton" then AFUI.SetBagBarMode("full")
  elseif ToggleAllBags then ToggleAllBags() end
end

-- The backpack's count in the single mode: the free slots over every carried bag (the client's own count leaves the specialty bags out).
function AFUI.UpdateBagCount()
  local b, B = _G.MainMenuBarBackpackButton, AFUI.Bags
  local fs = b and _G.MainMenuBarBackpackButtonCount
  if not fs or AFUI.BagBarMode() ~= "single" or not (B and B.Info) then return end
  local free = B.Totals(B.Info())
  fs:SetText(free); fs:Show()
end
AFUI.On("BAG_UPDATE", AFUI.UpdateBagCount)
if type(_G.MainMenuBarBackpackButton_UpdateFreeSlots) == "function" then hooksecurefunc("MainMenuBarBackpackButton_UpdateFreeSlots", AFUI.UpdateBagCount) end

local function LayoutBags()
  local mode = AFUI.BagBarMode()
  local combat = InCombatLockdown and InCombatLockdown()
  for _, t in ipairs(bagBar.BorderArt) do Shown(t, mode ~= "hidden") end
  if not combat then
    for _, d in ipairs(BAGS) do -- the buttons not in the mode go to the hidden frame (IsShown is then false: the row below skips them)
      local b = _G[d[1]]
      if b and b.afuiBag then
        local keep = mode == "full" or (mode == "single" and d[1] == "MainMenuBarBackpackButton")
        local want = keep and bagBar or AFUI.Hidden
        if b:GetParent() ~= want then b:SetParent(want) end
      end
    end
    local bp = _G.MainMenuBarBackpackButton
    if bp and bp.afuiBag then
      SwapScript(bp, "OnClick", mode == "single" and SingleClick or nil)
      SwapScript(bp, "OnEnter", mode == "single" and SingleTooltip or nil)
    end
    if bagBar.afuiMode ~= mode and mode ~= "single" and _G.MainMenuBarBackpackButton_UpdateFreeSlots then MainMenuBarBackpackButton_UpdateFreeSlots() end
    bagBar.afuiMode = mode
    -- the client hides the key ring button while no key is carried (MainMenuBar_UpdateKeyRing, which hooks LayoutBags): the bag bar always shows it
    local kr = _G.KeyRingButton
    if kr and kr.afuiBag and mode == "full" and not kr:IsShown() then kr:Show() end
  else
    AFUI.RunOutOfCombat(LayoutBags)
  end
  local prev, w, n = nil, 0, 0
  for _, d in ipairs(BAGS) do
    local b = _G[d[1]]
    if b and b:IsShown() and b:GetParent() == bagBar then -- IsShown ignores the parent: a button moved to the hidden frame is skipped here
      b:ClearAllPoints()
      if prev then
        b:SetPoint("RIGHT", prev, "LEFT", -BAG_GAP, 0)
        n = n + 1
        PlaceDivider(Divider(n), b)
        w = w + BAG_GAP
      else
        b:SetPoint("RIGHT", bagBar, "RIGHT")
      end
      w, prev = w + d[2], b
    end
  end
  for i = n + 1, #bagBar.dividers do for _, t in pairs(bagBar.dividers[i]) do t:Hide() end end
  bagBar:SetWidth(mode == "hidden" and BAG_SPACER or math.max(w, 1))
  sb.Resize()
end

local function SkinBag(b, width, art)
  local name = b:GetName()
  b:SetWidth(width); b:SetHeight(BAG_H)
  for _, t in ipairs({ b:GetNormalTexture(), b:GetPushedTexture() }) do -- normalAndPushedTextureWidth/Height: 46 (key ring 33) x 46
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", b, "TOPLEFT")
    t:SetWidth(width == 45 and 46 or width); t:SetHeight(width == 45 and 46 or 45) -- the key ring's frame art is 33x45
    Atlas(t, art)
  end
  local hl = b:GetHighlightTexture()
  hl:SetAllPoints(b); Atlas(hl, art); hl:SetBlendMode("ADD"); hl:SetAlpha(0.4)
  local checked = b.GetCheckedTexture and b:GetCheckedTexture() -- Forever's SlotHighlightTexture while the bag is open
  if checked then checked:SetAllPoints(b); Atlas(checked, art); checked:SetBlendMode("BLEND"); checked:SetAlpha(1) end
  local icon = _G[name .. "IconTexture"] -- the mask is MaskTexture-only; crop the icon border instead
  if icon then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  if icon and name == "MainMenuBarBackpackButton" then -- Forever's backpack icon is a plain file (FDID 7349174)
    icon:SetTexture("Interface\\AddOns\\AztraForeverUI\\Media\\chat\\ui-hud-actionbar-bag")
  end
  local count = _G[name .. "Count"]
  if count then -- backpack: free slots at CENTER 0,-10, NumberFontNormal; bags: BOTTOMRIGHT -2,2, NumberFontNormalSmall
    local backpack = name == "MainMenuBarBackpackButton"
    count:ClearAllPoints()
    if backpack then count:SetPoint("CENTER", b, "CENTER", 0, -10) else count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2) end
    count:SetFontObject(backpack and NumberFontNormal or NumberFontNormalSmall)
  end
  if name == "KeyRingButton" then -- camelot mainmenubarbagbuttons.lua:112-156; no MaskTexture on TBC, see micromenu-bags.md "port rule"
    -- The 27x40 plate has square corners the frame's rounded corners would not hide: inset it inside the frame's opaque
    -- border, below it (BORDER under the ARTWORK Normal texture), art by HasKey (Forever: KeyRingMixin:OnBagUpdate).
    local icon = b:CreateTexture(nil, "BORDER")
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4); icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 4)
    b.afui = { icon = icon }
    -- Always the key (Forever shows it once a key is held; here a character without one still sees the button), dimmed and grey until a key is carried.
    local function Update()
      local has = HasKey and HasKey() and true or false
      Atlas(icon, "ui-hud-actionbar-keyring-small-c60")
      icon:SetDesaturated(not has); icon:SetAlpha(has and 1 or 0.6)
      if bagBar.afuiMode == "full" and not b:IsShown() and not (InCombatLockdown and InCombatLockdown()) then b:Show(); LayoutBags() end
    end
    AFUI.On("BAG_UPDATE", Update)
    Update()
  end
end

-- Each bag slot shows its own bag, read from the inventory slot it stands for (CharacterBagNSlot = container N + 1); an empty slot shows
-- Forever's empty slot art. Blizzard's own update (PaperDollItemSlotButton_Update) runs on the same events and is followed by ours.
function AFUI.RefreshBagIcons()
  for i = 0, 3 do
    local b = _G["CharacterBag" .. i .. "Slot"]
    local icon = b and _G[b:GetName() .. "IconTexture"]
    if icon then
      local inv = ContainerIDToInventoryID and ContainerIDToInventoryID(i + 1) or b:GetID()
      local tex = GetInventoryItemTexture and inv and GetInventoryItemTexture("player", inv)
      if tex then
        icon:SetTexture(tex); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); icon:SetVertexColor(1, 1, 1); icon:Show()
      else
        Atlas(icon, "ui-hud-actionbar-iconframe-slot-c60"); icon:SetVertexColor(1, 1, 1); icon:Show()
      end
    end
  end
end
for _, ev in ipairs({ "BAG_UPDATE", "UNIT_INVENTORY_CHANGED", "PLAYER_ENTERING_WORLD", "ITEM_LOCK_CHANGED" }) do AFUI.On(ev, AFUI.RefreshBagIcons) end

local function AdoptMicroAndBags()
  for _, n in ipairs(CLIENT.hideMicro) do
    if _G[n] then _G[n]:SetParent(AFUI.Hidden) end
  end
  AFUI.Kill(MainMenuBarPerformanceBarFrame) -- Blizzard's own latency bar; ours (below) is Forever's
  for _, d in ipairs(MICRO) do
    local b = EXTRA[d[1]] and MakeExtraMicro(d[1]) or _G[d[1]]
    if b and not b.afui then b:SetParent(mm); SkinMicro(b, d[2]) end
  end
  HookExtraWindows(); SyncExtras()
  local perfHost = MainMenuMicroButton
  if perfHost and perfHost.afui and not perfHost.afui.perf then
    -- Forever draws its own bar art over the button; the TBC file is a full 19x39 picture, which would cover the icon. On a frame
    -- one level under the button only the 2 px that hang below its edge show, which is the thin line Forever shows.
    local host = CreateFrame("Frame", nil, mm)
    host:SetFrameLevel(math.max(perfHost:GetFrameLevel() - 1, 0))
    host:SetAllPoints(perfHost)
    perfHost.afui.perfFrame = host
    local perf = host:CreateTexture(nil, "ARTWORK")
    perf:SetTexture("Interface\\MainMenuBar\\UI-MainMenuBar-PerformanceBar")
    perf:SetWidth(19); perf:SetHeight(39)
    perf:SetPoint("BOTTOM", perfHost, "BOTTOM", 0, -2)
    perfHost.afui.perf = perf
    StartLatency()
  end
  for _, d in ipairs(BAGS) do
    local b = _G[d[1]]
    if b and not b.afuiBag then b.afuiBag = true; b:SetParent(bagBar); SkinBag(b, d[2], d[3]) end
  end
  LayoutMicro(); LayoutBags(); AFUI.UpdateBagCount()
  AFUI.RefreshBagIcons()
end

---------------------------------------------------------------- pet, stance, possess
local EXTRAS = {
  { key = "pet", name = "Pet", prefix = "PetActionButton", count = 10, size = 36, old = "PetActionBarFrame",
    driver = "[pet]show;hide" },
  { key = "stance", name = "Stance", prefix = AFUI.STANCE.button, count = 10, size = 30, old = AFUI.STANCE.frame },
}
-- Stance and possess share a slot. The bars hold protected buttons, so secure drivers swap them in combat.
-- No possess bar where the client has none (2.5.3): no frame, so no Edit Mode system either.
if AFUI.POSSESS.count > 0 then
  EXTRAS[#EXTRAS + 1] = { key = "possess", name = "Possess", prefix = AFUI.POSSESS.button, count = AFUI.POSSESS.count,
    size = 36, old = AFUI.POSSESS.frame, driver = "[bonusbar:5]show;hide" }
end
local EXTRA_DEFAULTS = { numRows = 1, padding = 2, orientation = "Horizontal", hidden = false }

-- The visibility driver of an extra bar: "Hide Bar" wins (a plain secure 'hide', so form changes and pets cannot show it again); the stance
-- driver runs only for a class with forms (the form count changes when a form is learned, not in a fight). Out of combat only.
local STANCE_DRIVER = "[bonusbar:5]hide;show"
local function ApplyDriver(d)
  local bar = d.bar
  local want = d.driver
  if d.key == "stance" then want = GetNumShapeshiftForms() > 0 and STANCE_DRIVER or nil end
  if bar.settings.hidden and want then want = "hide" end -- a class without forms keeps no driver: never an empty bar
  if want == bar.driven then return end
  bar.driven = want
  if want then
    RegisterStateDriver(bar.frame, "visibility", want)
  else
    UnregisterStateDriver(bar.frame, "visibility")
  end
  if want == "hide" or not want then bar.frame:Hide() end
end

for _, d in ipairs(EXTRAS) do
  local frame = CreateFrame("Frame", "AFUI_" .. d.name .. "Bar", UIParent)
  -- shortcut: above the stacked bars until Edit Mode (Task 8) positions them.
  if d.key == "pet" then
    frame:SetPoint("BOTTOMRIGHT", AFUI.Bars.right2.frame, "TOPRIGHT", 0, 8)
  else
    frame:SetPoint("BOTTOMLEFT", AFUI.Bars.right2.frame, "TOPLEFT", 0, 8)
  end
  local bar = { frame = frame, buttons = {}, settings = EXTRA_DEFAULTS }
  function bar.layout()
    local s = bar.settings
    local count, vertical = math.max(#bar.buttons, 1), s.orientation == "Vertical"
    local points = AFUI.LayoutButtons(count, s.numRows, d.size, s.padding, vertical)
    for i, b in ipairs(bar.buttons) do
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", frame, "TOPLEFT", points[i][1], points[i][2])
    end
    local w, h = AFUI.LayoutSize(count, s.numRows, d.size, s.padding, vertical)
    frame:SetWidth(w); frame:SetHeight(h)
  end
  function bar.ApplySettings(settings)
    bar.settings = settings
    AFUI.RunOutOfCombat(function() bar.layout(); ApplyDriver(d) end)
  end
  AFUI.Bars[d.key] = bar
  d.bar = bar
  frame:HookScript("OnShow", Restack); frame:HookScript("OnHide", Restack) -- the state drivers show and hide them
  if d.driver then bar.driven = d.driver; RegisterStateDriver(frame, "visibility", d.driver) end
  if d.key == "stance" then frame:Hide() end -- shown by its driver once the class has forms
end

local function UpdateStanceDriver() ApplyDriver(EXTRAS[2]) end

-- Blizzard re-anchors ShapeshiftButton1 for single-form classes and re-shows buttons; keep ours in place.
local function Relayout()
  AFUI.Bars.stance.layout()
  if AFUI.Bars.possess then AFUI.Bars.possess.layout() end
  UpdateStanceDriver()
end
local function OnStanceUpdate() AFUI.RunOutOfCombat(Relayout) end

local function AdoptExtras() -- protected buttons: reparent out of combat only
  for _, d in ipairs(EXTRAS) do
    local bar = d.bar
    if not bar.adopted and d.prefix then
      for i = 1, d.count do
        local b = _G[d.prefix .. i]
        if b then
          b:SetParent(bar.frame)
          AFUI.SkinButton(b, d.size)
          bar.buttons[#bar.buttons + 1] = b
        end
      end
      bar.adopted = true
    end
    if d.old and _G[d.old] then _G[d.old]:Hide() end -- hidden, not event-killed: Blizzard code still drives the buttons
    bar.layout()
  end
  UpdateStanceDriver()
end

-- Quest Log button: Blizzard's click shows QuestLogFrame, which only reaches our window through a hook; the button calls the L key's own
-- function instead (Forever's quest log is the map window with its quest panel) and is pushed while that window is open.
local function SyncQuestMicro()
  local b, Q = _G.QuestLogMicroButton, AFUI.QuestLog
  if not (b and b.afui and Q and Q.IsOpen) then return end
  if Q.IsOpen() then b:SetButtonState("PUSHED", true) else b:SetButtonState("NORMAL") end
  RefreshMicro(b)
end
local questMicroPanelHook
local function SetupQuestMicro()
  local b = _G.QuestLogMicroButton
  if not (b and b.afui and AFUI.QuestLog) then return end
  SwapScript(b, "OnClick", function() AFUI.QuestLog.Toggle(); SyncQuestMicro() end)
  local map = _G.WorldMapFrame
  if map and not map.afuiQuestMicro and map.HookScript then
    map.afuiQuestMicro = true
    map:HookScript("OnShow", SyncQuestMicro); map:HookScript("OnHide", SyncQuestMicro)
  end
  if AFUI.WorldMapPanelHooks and not questMicroPanelHook then
    questMicroPanelHook = true
    table.insert(AFUI.WorldMapPanelHooks, SyncQuestMicro)
  end
  SyncQuestMicro()
end
AFUI.On("ADDON_LOADED", SetupQuestMicro) -- Blizzard_WorldMap may load later

local hooked
function AFUI.SetupBarExtras()
  AFUI.RunOutOfCombat(AdoptExtras)
  AdoptMicroAndBags()
  AFUI.EndCaps.Update()
  sb.Update()
  if hooked then return end
  hooked = true
  local function hook(names, fn)
    for _, n in ipairs(names) do if _G[n] then hooksecurefunc(n, fn) end end
  end
  hook(AFUI.STANCE.update, OnStanceUpdate)
  hook(CLIENT.microHooks, OnMicroUpdate)
  hook(CLIENT.microHooks, SyncQuestMicro) -- UpdateMicroButtons resets the pushed state from QuestLogFrame
  SetupQuestMicro()
  hook({ "MainMenuBar_UpdateKeyRing" }, LayoutBags)
  AFUI.OnSettingChanged("bagBarMode", function() -- live: the row re-forms and the XP bar follows its width
    AFUI.RunOutOfCombat(function()
      LayoutBags(); AFUI.UpdateBagCount()
      if AFUI.Bags and AFUI.Bags.Refresh then AFUI.Bags.Refresh() end -- the open / closed look of the one icon
    end)
  end)
  hook({ "PaperDollItemSlotButton_Update", "BagSlotButton_UpdateChecked" }, AFUI.RefreshBagIcons)
  -- Both clients drive the character button's look through these (2.4.3 every frame from its OnUpdate).
  local char = CharacterMicroButton
  if char and char.afui then
    hook({ "CharacterMicroButton_SetPushed" }, function() SetMicroState(char, true) end)
    hook({ "CharacterMicroButton_SetNormal" }, function() SetMicroState(char, false) end)
  end
end

-- Blizzard keeps MicroButtonPortrait current; ours follows the same events (MainMenuBarMicroButtons.lua CharacterMicroButton_OnEvent).
local function UpdatePortrait(_, unit)
  local b = CharacterMicroButton
  if b and b.afui and b.afui.portrait and (not unit or unit == "player") then SetPortraitTexture(b.afui.portrait, "player") end
end
AFUI.On("UNIT_PORTRAIT_UPDATE", UpdatePortrait)
AFUI.On("PLAYER_ENTERING_WORLD", UpdatePortrait)

---------------------------------------------------------------- HUD Tooltip and buffs (Edit Mode systems of the video)
-- HUD Tooltip: unit, spell and item tooltips Blizzard anchors to the screen corner (GameTooltip_SetDefaultAnchor) sit in a box
-- above the bags bar, bottom right, that Edit Mode can move. Tooltips with an owner of their own (a bag slot, the minimap) stay.
local hudTip = CreateFrame("Frame", "AFUI_HudTooltip", UIParent)
hudTip:SetWidth(200); hudTip:SetHeight(90); hudTip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -11, 90)
AFUI.HudTooltip = hudTip
if type(_G.GameTooltip_SetDefaultAnchor) == "function" then
  hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip)
    if tooltip == GameTooltip then tooltip:ClearAllPoints(); tooltip:SetPoint("BOTTOMRIGHT", hudTip, "BOTTOMRIGHT", 0, 0) end
  end)
end

-- Buffs and Debuffs: one row of icons top right, left of the minimap cluster (the video: 5 icons of 30 with the timers in gold).
-- Blizzard anchors BuffFrame to MinimapCluster, which our cluster has moved: it hangs from this box instead.
local buffBox = CreateFrame("Frame", "AFUI_BuffAnchor", UIParent)
buffBox:SetWidth(300); buffBox:SetHeight(75); buffBox:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -280, -3)
AFUI.BuffAnchor = buffBox
function AFUI.PlaceBuffs()
  if not BuffFrame then return end
  BuffFrame:SetParent(buffBox)
  BuffFrame:ClearAllPoints(); BuffFrame:SetPoint("TOPRIGHT", buffBox, "TOPRIGHT", 0, 0)
end
AFUI.On("PLAYER_ENTERING_WORLD", function() AFUI.RunOutOfCombat(AFUI.PlaceBuffs) end)
-- the client re-anchors BuffFrame to the minimap cluster whenever it lays out the top frames
if type(_G.UIParent_UpdateTopFramePositions) == "function" then hooksecurefunc("UIParent_UpdateTopFramePositions", function() AFUI.RunOutOfCombat(AFUI.PlaceBuffs) end) end

AFUI.RegisterModule("BarExtras", { OnLogin = function() AFUI.SetupBarExtras(); AFUI.RunOutOfCombat(AFUI.PlaceBuffs) end })

-- /afui hidebar stance|pet|possess [on|off]: the same "Hide Bar" setting as Edit Mode (kept in the layout), for when the bar is in the way.
AFUI.Slash.Register("hidebar", function(rest)
  local key, flag = tostring(rest or ""):lower():match("^(%a+)%s*(%a*)$")
  local bar = key and AFUI.Bars[key]
  if not (bar and (key == "pet" or key == "stance" or key == "possess")) then AFUI.Print("/afui hidebar stance|pet|possess [on|off]"); return end
  local on = flag == "on" or (flag ~= "off" and not bar.settings.hidden)
  if AFUI.EditMode and AFUI.EditMode.SetSetting then AFUI.EditMode.SetSetting(key, "hidden", on)
  else local s = {}; for k, v in pairs(bar.settings) do s[k] = v end; s.hidden = on; bar.ApplySettings(s) end
  AFUI.Print(key .. " bar " .. (on and "hidden" or "shown"))
end, "hide or show the stance, pet or possess bar", "/afui hidebar stance|pet|possess [on|off]")
