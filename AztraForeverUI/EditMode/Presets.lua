-- Forever's Modern and Classic Edit Mode presets as anchors on UIParent: { point, relPoint, x, y } puts the frame's
-- `point` at UIParent's `relPoint` plus (x, y). No screen size is baked in: Registry's EM.Resolve turns an anchor into
-- a centre offset against the LIVE UIParent size and the frame's size after its settings, when the frame is placed.
-- Source: tools/ref/interface/addons/blizzard_editmode/mainline/editmodepresetlayouts.lua (line numbers below), with the
-- `camelot/` constants (camelot/editmodepresetlayoutconstants.lua, which also defines BOTTOM_ACTION_BAR_DEFAULT_OFFSET_X
-- and ACTION_BARS_RELATIVE_TO_BASE_POSITIONING that the mainline presets and shared/editmodemanager.lua read) and the
-- positioning code in shared/editmodemanager.lua (UpdateBottomActionBarPositions 641-720, right bars 600-636).
-- Forever anchors many frames to other Forever frames; each chain is resolved to UIParent using our frame sizes
-- (main bar 562x45 = 12 icons x (45+2) - 2, right bars 45x562, stance 318x30, pet bar 378x36, possess 74x36, XP bar 571x17,
-- micro menu 194x40, bags 233x45 (268 with the key ring), player 232x100, target 232x100 (Forever's button sizes, art centred
-- in them), ToT/pet 120x49, party 120x53, cast bar 208x11).
-- Frames Forever anchors to something not in the reference (CompactRaidFrameManager) say so.
AFUI = AFUI or {}

local function A(point, relPoint, x, y, rel) return { point = point, relPoint = relPoint, x = x, y = y, rel = rel } end

-- Bottom bars that share one column stack upward (camelot UpdateBottomActionBarPositions): each starts the previous one's
-- height plus BOTTOM_ACTION_BARS_SPACER_Y (4) higher. Returns the y of every bar for `heights`, the first at y0.
function AFUI.StackBottom(y0, heights)
  local ys, y = {}, y0
  for i, h in ipairs(heights) do ys[i] = y; y = y + h + 4 end
  return ys
end
---------------------------------------------------------------- Forever's automatic bar positioning
-- The presets above hold the positions for the default layout (everything shown). Forever recomputes them whenever a bar shows or
-- hides (shared/editmodemanager.lua UpdateBottomActionBarPositions 641-720, UpdateRightActionBarPositions 600-636), for the bars that
-- are still in their default position only; a bar the player moved is left alone and does not count. EM.Resolve asks AFUI.AutoPlace[key]
-- for the live anchor (and scale) of those bars each time it places them; AFUI.RestackBars places them again after a change.
-- Bar slots in camelot GetBottomActionBars order; the bottom right bar (Bar3) is excluded from the stack increment, it sits beside.
local STACK = { "main", "statusbar", "statusbar2", "bottomright", "bottomleft", "stance", "pet", "possess" }
-- Modern (Mat's Forever screenshot, 2560x1440 at 1.40625 px per unit): three 12-button bars one above the other 4 apart, the XP bar on
-- its own along the bottom of the screen (not in the stack), the main bar 40 above the screen bottom. Anchors marked stack = "modern" use it.
local MODERN_STACK = { "main", "bottomleft", "bottomright", "stance", "pet", "possess" }
local MODERN_BASE_Y, MODERN_GAP = 45.5, 4 -- video3 f0001 (8x crops): the bar rows are 49 apart (button 45 + 4), the main bar 45.5 up with both status bars shown
local MODERN_SB_DOWN, MODERN_SB_UP = 3, 22 -- the two status bar heights of the Modern preset
local STACK_H = { main = 45, statusbar = 17, statusbar2 = 17, bottomright = 45, bottomleft = 45, stance = 30, pet = 36, possess = 36 }
local BASE_Y = 2 -- the main bar's bottom edge above the screen bottom (MAIN_ACTION_BAR_OFFSET_Y -4 below the micro menu's 6)
local SPACER = 4 -- BOTTOM_ACTION_BARS_SPACER_Y

-- items = { { key, h, exclude }, ... } in stacking order, only the bars that count. Returns key -> y (bottom edge above the screen
-- bottom): the first at y0, each next one the previous y plus its height plus the spacer (an excluded bar adds nothing).
function AFUI.BottomStackY(y0, items, spacer)
  local ys, y = {}, y0
  for _, it in ipairs(items) do
    ys[it.key] = y
    if not it.exclude then y = y + it.h + (spacer or SPACER) end
  end
  return ys
end

local function isDefault(c) return c and (c.auto or (c.x == nil and c.anchor ~= nil)) end
-- Height of a system in UIParent units, or the default when its frame has no size yet.
local function span(key, default)
  local EM = AFUI.EditMode
  local e, c = EM.systems[key], EM.current.systems[key]
  local h = e and e.frame:GetHeight()
  if h and h >= 1 then return h * ((c and c.scale) or 1) end
  return default
end

-- Does the bar count in the stack? Forever: shown, and in its default position. Not registered (a copy flattened before login):
-- assume shown like the presets do.
local function counts(key)
  local EM = AFUI.EditMode
  local e = EM.systems[key]
  if not e then return key ~= "statusbar2" end -- the reputation bar is there only while a faction is watched
  if not (EM.IsEnabled(e) and e.frame:IsShown()) then return false end
  return isDefault(EM.current.systems[key])
end

local function stackPlace(key)
  return function(cur, a)
    local modern = a.stack == "modern"
    local items = {}
    for _, k in ipairs(modern and MODERN_STACK or STACK) do
      if k == "main" or k == key or counts(k) then
        items[#items + 1] = { key = k, h = span(k, STACK_H[k]), exclude = not modern and k == "bottomright" }
      end
    end
    local y = AFUI.BottomStackY(modern and MODERN_BASE_Y or BASE_Y, items, modern and MODERN_GAP or nil)[key] or a.y
    -- Modern, video3 f0001: with a faction watched the XP bar (Status Bar 1) rides on the reputation bar (Status Bar 2, on the bottom edge);
    -- XP alone stays on the bottom.
    if modern and key == "statusbar" and counts("statusbar2") then y = MODERN_SB_UP
    elseif modern and key == "statusbar2" then y = MODERN_SB_DOWN end
    return { point = a.point, relPoint = a.relPoint, x = a.x, y = y, rel = a.rel }
  end
end

-- Right bars: Forever scales them to the space between the minimap cluster's bottom - 10 and the micro menu's top + 24 (the whole
-- of UIParent when the minimap was moved) and stacks them leftwards from RIGHT -5 / -77. At the preset's y that overflows the space
-- on a small screen (Forever's offset assumes a tall one), so the bar is also moved to stay inside the limits; our right bar 2 keeps
-- the 12 px gap (Forever: 5) so the selection art of the two does not overlap.
local RIGHT_GAP = 12
local function limits(sw, sh) -- the space above the bottom of the screen: bottom, top
  local EM = AFUI.EditMode
  local lo, hi = 0, sh
  local m, mc = EM.systems.minimap, EM.current.systems.minimap
  if m and isDefault(mc) then
    if mc.x == nil then EM.Resolve("minimap", mc, 1) end
    hi = sh / 2 + mc.y - span("minimap", 0) / 2 - 10
  end
  local u, uc = EM.systems.micromenu, EM.current.systems.micromenu
  if u and isDefault(uc) then
    if uc.x == nil then EM.Resolve("micromenu", uc, 1) end
    lo = sh / 2 + uc.y + span("micromenu", 0) / 2 + 24
  end
  local b, bc = EM.systems.bags, EM.current.systems.bags -- Modern stacks the bags above the micro menu
  if b and isDefault(bc) then
    if bc.x == nil then EM.Resolve("bags", bc, 1) end
    lo = math.max(lo, sh / 2 + bc.y + span("bags", 0) / 2 + 10)
  end
  return lo, math.max(hi, lo + 1)
end

local function rightPlace(key)
  return function(cur, a, sw, sh)
    local EM = AFUI.EditMode
    local first = EM.systems.right
    local lo, hi = limits(sw, sh)
    local barH = (first and first.frame:GetHeight() or 0) >= 1 and first.frame:GetHeight() or 562
    local user = cur.scale or 1
    local scale = barH * user > hi - lo and (hi - lo) / barH or user
    local x = a.x -- right 2's preset x already sits one bar width + gap left of the right bar
    if key == "right2" and not counts("right") then -- no bar to its right (off, or moved): it takes the first slot
      x = x + ((first and first.frame:GetWidth() or 0) >= 1 and first.frame:GetWidth() or 45) + RIGHT_GAP
    end
    local h = ((EM.systems[key] and EM.systems[key].frame:GetHeight() or 0) >= 1 and EM.systems[key].frame:GetHeight() or barH) * scale
    local y = math.min(math.max(a.y * scale, lo - sh / 2 + h / 2), hi - sh / 2 - h / 2)
    return { point = a.point, relPoint = a.relPoint, x = x * scale, y = y, rel = a.rel }, scale
  end
end

AFUI.AutoPlace = { right = rightPlace("right"), right2 = rightPlace("right2") }
for _, k in ipairs({ "statusbar", "statusbar2", "bottomright", "bottomleft", "stance", "pet", "possess" }) do AFUI.AutoPlace[k] = stackPlace(k) end

-- Places every automatic bar again (a bar was shown, hidden, toggled, resized). Out of combat only: the bars hold protected buttons.
local function restack()
  local EM = AFUI.EditMode
  if not (EM and EM.systems and AFUI.AutoPlace) then return end
  for key in pairs(AFUI.AutoPlace) do
    local e, c = EM.systems[key], EM.current.systems[key]
    if e and c and c.auto and c.anchor then
      EM.Place(e)
      if EM.RefreshOverlay then EM.RefreshOverlay(key) end
    end
  end
end
function AFUI.RestackBars() AFUI.RunOutOfCombat(restack) end

local function bar(anchor, vertical)
  return { anchor = anchor, scale = 1, numIcons = 12, numRows = 1, padding = 2, visibility = "always",
    alwaysShow = true, hideBarArt = false, hideBarScrolling = false, orientation = vertical and "Vertical" or "Horizontal" }
end
local function extra(anchor) return { anchor = anchor, scale = 1, numRows = 1, padding = 2, orientation = "Horizontal" } end
local function unit(anchor) return { anchor = anchor, scale = 1, showPortrait = true } end
local function plain(anchor) return { anchor = anchor, scale = 1 } end

-- Systems whose Forever anchor is the same in Modern and Classic (the Classic map reuses the Modern entries).
local function shared()
  local stack = AFUI.StackBottom(121, { 30, 36, 36 })
  return {
    -- mainline:21-40 MainBar BOTTOMRIGHT of MicroMenuContainer BOTTOMLEFT -4.5,-4 (MAIN_ACTION_BAR_*). The container is the
    -- micro menu (MICRO_MENU: BOTTOM/UIParent BOTTOM 116.5,6, Forever's full button set taken as 288 wide: left edge at 116.5-144 = -27.5 from the centre,
    -- bottom edge 6 up), so the bar's bottom-right corner is at x = -27.5 - 4.5 = -32, y = 6 - 4 = 2.
    main = bar(A("BOTTOMRIGHT", "BOTTOM", -32, 2)),
    -- The rest of the bottom area is positioned relative to the main bar's BOTTOMLEFT (ACTION_BARS_RELATIVE_TO_BASE_POSITIONING),
    -- stack Y starts at 0 and grows by height + BOTTOM_ACTION_BARS_SPACER_Y (4); the main bar's left edge is -32 - 562 = -594.
    -- Order (camelot GetBottomActionBars): main, XP bars, Bar3, Bar2, stance / pet / possess.
    -- Main bar adds 45 + 4 -> 49. statusbar (mainline:600-611, MainStatusTrackingBarContainer) sits there: y = 2 + 49.
    statusbar = { anchor = A("BOTTOMLEFT", "BOTTOM", -594, 51), scale = 1, width = 0.7 },
    -- the reputation bar stacks right above it while a faction is watched (AutoPlace counts it only then)
    statusbar2 = { anchor = A("BOTTOMLEFT", "BOTTOM", -594, 72), scale = 1, width = 0.7 },
    -- XP bar adds 17 + 4 -> 70. :62-81 Bar3 has bottomBarOffsetX 606 (ACTION_BAR_3_BOTTOM_BAR_OFFSET_X) and is excluded
    -- from the stack increment, so it sits beside bar 2: x = -594 + 606, y = 2 + 70.
    bottomright = bar(A("BOTTOMLEFT", "BOTTOM", 12, 72)),
    -- :42-60 Bar2 bottomBarOffsetX 22 (ACTION_BAR_2_BOTTOM_BAR_OFFSET_X): x = -594 + 22, same row; adds 45 + 4 -> 119.
    bottomleft = bar(A("BOTTOMLEFT", "BOTTOM", -572, 72)),
    -- :178-193 StanceBar bottomBarOffsetX 30 (BOTTOM_ACTION_BAR_DEFAULT_OFFSET_X): x = -594 + 30, y = 2 + 119.
    stance = extra(A("BOTTOMLEFT", "BOTTOM", -564, stack[1])),
    -- :195-211 PetActionBar and :213-229 PossessActionBar share the column: Forever stacks the ones that are shown, in this
    -- order, each above the last (editmodemanager.lua:700-716). Edit Mode shows all three, so the presets stack all three
    -- (stance 30 high, pet bar 36, possess 36) and they never overlap there.
    pet = extra(A("BOTTOMLEFT", "BOTTOM", -564, stack[2])),
    possess = extra(A("BOTTOMLEFT", "BOTTOM", -564, stack[3])),
    -- :570-583 MicroMenu BOTTOM/UIParent BOTTOM 116.5,6 (MICRO_MENU_ANCHOR_*). Forever's container holds buttons TBC has
    -- no window for (Professions, Collections, Adventure Guide, Shop); ours is 9 buttons at a 27 px pitch = 248 wide (Professions and PvP are ours; Collections and Shop have no TBC window).
    -- The main bar keeps Forever's spot and the micro menu keeps the 4.5 gap: left edge -32 + 4.5, centre + 124 = 96.5.
    micromenu = plain(A("BOTTOM", "BOTTOM", 96.5, 6)),
    -- :585-598 Bags BOTTOMLEFT of MicroMenuContainer BOTTOMRIGHT 7,-4 (BAGS_ANCHOR_*): micro right edge 96.5 + 124 = 220.5,
    -- so x = 227.5, y = 6 - 4 = 2.
    bags = plain(A("BOTTOMLEFT", "BOTTOM", 227.5, 2)),
    -- :83-100 RightBar1 RIGHT/UIParent RIGHT -5,-77 (right bar loop, editmodemanager.lua:613-630). Forever's bar is vertical
    -- (one column of 12): orientation Vertical, one column.
    right = bar(A("RIGHT", "RIGHT", -5, -77), true),
    -- :102-119 RightBar2: the loop moves it left by bar width 45 + 5 + padding 0 = 50 more. That leaves the two boxes' 8 px
    -- art overlapping, so ours keeps 12 px (45 + 12; 16 would push it into the bottom right bar on a 1365 screen): the two selection arts barely touch.
    right2 = bar(A("RIGHT", "RIGHT", -62, -77), true),
    -- end caps: x as ml:628-653 (RIGHT at the main bar LEFT +30, LEFT at the bags RIGHT -30); y 21 not +5: measured on the official video, the gryphon box bottom sits level with the bar bottom (see docs/forever-ref/bars-port-report.md).
    endcap_left = { anchor = A("RIGHT", "LEFT", 30, 21, "main"), scale = 1, hidden = false },
    endcap_right = { anchor = A("LEFT", "RIGHT", -30, 21, "bags"), scale = 1, hidden = false },
    -- The video: chat 349 x 215 in the bottom left corner (button column 35 wide), HUD tooltip box above the bags bar (11 from the
    -- right, 90 up), the buff row left of the minimap cluster (252 from the right, 3 down).
    chat = { anchor = A("BOTTOMLEFT", "BOTTOMLEFT", 35, 28), scale = 1, width = 349, height = 215 },
    hudtooltip = plain(A("BOTTOMRIGHT", "BOTTOMRIGHT", -108, 90)), -- left of the right bars (their art starts ~101 from the screen edge), above the bags bar
    buffs = plain(A("TOPRIGHT", "TOPRIGHT", -280, -3)), -- clear of the minimap cluster (275 wide)
    -- Objective tracker: Forever's TOPRIGHT -110,-275 is for its smaller minimap cluster; ours is 283 tall, so it hangs 4 under it,
    -- and its right edge stops 122 from the screen edge (left of the two right bars: 45 + 12 + 45 + 8 art + 12 air).
    tracker = plain(A("TOPRIGHT", "TOPRIGHT", -122, -287)),
    -- :393-407 Minimap TOPRIGHT/UIParent TOPRIGHT 0,0.
    minimap = plain(A("TOPRIGHT", "TOPRIGHT", 0, 0)),
    -- :292-315 (Classic :1092) Party TOPLEFT/CompactRaidFrameManager TOPRIGHT 0,-7. The manager is not in the reference;
    -- Blizzard's default is a 200 wide panel at TOPLEFT UIParent -182,-140 (from memory), so TOPRIGHT = (18, -140):
    -- party1 at (18, -147). party2-4 follow party1.
    party = unit(A("TOPLEFT", "TOPLEFT", 18, -147)),
  }
end

local function build(layout, over)
  for key, entry in pairs(over) do layout[key] = entry end
  return { systems = layout }
end

-- Modern = Mat's real Forever HUD (docs/forever-ref/screens/mat-forever, 2560x1440; his UIParent is 1820x1024 units, 1.40625 px per
-- unit, measured from the 12-button main bar: 562 units = 790 px). Positions are those measurements, anchored to the screen edges
-- they sit on (centre, bottom, right), so they follow Mat's 1365x768 (2.4.3) and 1606x903 (2.5.3) UIParents.
local function M(point, relPoint, x, y, rel) local a = A(point, relPoint, x, y, rel); a.stack = "modern"; return a end
local function modern()
  local stack = AFUI.BottomStackY(192.5, { { key = 1, h = 30 }, { key = 2, h = 36 }, { key = 3, h = 36 } }, MODERN_GAP) -- stance, pet, possess above the three bars
  return {
    -- Three 12-button bars centred, 2 apart (pitch 47), in Blizzard's order: Action Bar 1 (main) at the bottom, Action Bar 2 (bottomleft)
    -- right above it, Action Bar 3 (bottomright) above that; AFUI.AutoPlace re-stacks them when one is hidden.
    -- y = the bar's bottom edge above the screen bottom (the XP bar sits below).
    main = bar(M("BOTTOM", "BOTTOM", 0, 45.5)),
    bottomleft = bar(M("BOTTOM", "BOTTOM", 0, 94.5)),
    bottomright = bar(M("BOTTOM", "BOTTOM", 0, 143.5)),
    stance = extra(M("BOTTOMLEFT", "BOTTOM", -281, stack[1])),
    pet = extra(M("BOTTOMLEFT", "BOTTOM", -281, stack[2])),
    possess = extra(M("BOTTOMLEFT", "BOTTOM", -281, stack[3])),
    -- XP bar: thin, centred, on the very bottom of the screen (5 px up = 3 units), a little wider than the main bar.
    statusbar = { anchor = M("BOTTOM", "BOTTOM", 0, 3), scale = 1, width = 0.5 }, -- 50 % of the 1192 default: 596, the video's 593
    statusbar2 = { anchor = M("BOTTOM", "BOTTOM", 0, 22), scale = 1, width = 0.5 }, -- the reputation bar right above it (17 high + 2)
    -- Micro menu in the bottom right corner (art 3 units from the right, 6 up), the bags bar right above it.
    micromenu = plain(A("BOTTOMRIGHT", "BOTTOMRIGHT", -3, 6)),
    -- the video's bag cells are 52 px = 37 units, not 45: Mat's Forever has the Bags size at 80 %
    bags = { anchor = A("BOTTOMRIGHT", "TOPRIGHT", 3, 8, "micromenu"), scale = 0.8 }, -- 3 right (the screen edge): the plates end within a unit of each other (micro plate 8 past its buttons, the 80 % bag plate 4); the cells stand 8 above the micro buttons (Mat's capture forever-objective-tracker-micromenu.png, the plates overlap by 3)
    -- The video shows the gryphons by default; each is a hideable Edit Mode system. video3 f0001/f0018: full size (1.11 x the old 0.9),
    -- the head 30 over the bar's end button (the mainline +30 / -30); the real caps stand 12 px apart in height (left 6.5 under the bar's
    -- centre line, right 1.5 over it).
    endcap_left = { anchor = A("RIGHT", "LEFT", 30, -6.5, "main"), scale = 1, hidden = false },
    endcap_right = { anchor = A("LEFT", "RIGHT", -30, 1.5, "main"), scale = 1, hidden = false },
    -- video3 f0001: the buff row's gold triangle ends 262 from the screen edge; the chat is 363 x 226 beside its 35 wide button column
    -- (text from x 48 to 560 px, lines to 1403 px of 1440).
    buffs = plain(A("TOPRIGHT", "TOPRIGHT", -264, -3)),
    chat = { anchor = A("BOTTOMLEFT", "BOTTOMLEFT", 35, 28), scale = 1, width = 363, height = 226 },
    -- Player frame left of the middle above the bars: art 192 wide x 70 high (inside the 232x100 canvas), portrait centre 261 left of
    -- the middle, bottom of the art 274 above the screen bottom. Target mirrors it on the right.
    player = unit(A("BOTTOMRIGHT", "BOTTOM", -82, 263)),
    target = unit(A("BOTTOMLEFT", "BOTTOM", 82, 263)),
    -- Target of target: TOPRIGHT at the target frame's BOTTOMRIGHT +12,+10 (unitframe mainline/targetframe.xml:397-405).
    targettarget = unit(A("TOPRIGHT", "BOTTOM", 326, 273)),
    -- Pet frame: Mat's sits above the player frame, left of its middle (its portrait box at x -220, 361 up).
    pet_frame = unit(A("BOTTOMLEFT", "BOTTOM", -242, 337)),
    -- Player cast bar above the bar stack (the stance row tops out at 211), below the player frame.
    castbar_player = { anchor = A("BOTTOM", "BOTTOM", 0, 228.5), scale = 1, lockToPlayerFrame = false },
  }
end

AFUI.PRESETS = {
  Modern = build(shared(), modern()),
  Classic = build(shared(), {
    -- Classic :1049-1061 Player TOPLEFT/UIParent TOPLEFT 4,-4.
    player = unit(A("TOPLEFT", "TOPLEFT", 4, -4)),
    -- Classic :1063-1075 Target TOPLEFT/UIParent TOPLEFT 250,-4.
    target = unit(A("TOPLEFT", "TOPLEFT", 250, -4)),
    -- Target of target: TOPRIGHT at the target frame's BOTTOMRIGHT +12,+10: target right edge 250 + 232 = 482,
    -- bottom 4 + 100 = 104 down -> (494, -94).
    targettarget = unit(A("TOPRIGHT", "TOPLEFT", 494, -94)),
    -- Pet frame: as in Modern, TOP at the player frame's BOTTOM +30,+25 -> (4 + 116 + 30, -(4 + 100) + 25).
    pet_frame = unit(A("TOP", "TOPLEFT", 150, -79)),
    -- Classic reuses the Modern CastBar entry (:1046); the Classic preset locks the cast bar to the player frame (controller
    -- ruling). Position if unlocked: where the lock puts it, TOPRIGHT at the player frame's BOTTOMRIGHT -24,+12
    -- (unitframe shared/playerframe.lua:18-32) -> (4 + 232 - 24, -(4 + 100) + 12).
    castbar_player = { anchor = A("TOPRIGHT", "TOPLEFT", 212, -92), scale = 1, lockToPlayerFrame = true },
  }),
}
AFUI.PRESET_ORDER = { "Modern", "Classic" }
