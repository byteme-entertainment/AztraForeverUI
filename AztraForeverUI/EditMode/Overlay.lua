-- Edit Mode overlay: grid, a selection box over every registered system (Forever's EditModeSystemSelectionBaseTemplate,
-- docs/forever-ref/editmode.md section 1), drag with snap and red snap preview lines, closes itself in combat.
AFUI = AFUI or {}
local EM = AFUI.EditMode
local P = "editmode-actionbar-"
local CORNER = 16
local GROW = 8 -- the 16 px stroke is centred on the selection edge: the art reaches 8 px beyond it
-- Colours measured on Forever's frames (docs/forever-ref/screens/editmode): white lines at about a quarter of full strength, the
-- centre cross purple. Thickness 1.2 (EditModeGridLineTemplate).
local GRID_LINE, GRID_CENTER, GRID_THICKNESS = { 1, 1, 1, 0.3 }, { 0.62, 0.27, 0.72, 0.95 }, 1.2
local SNAP_LINE, SNAP_THICKNESS = { 1, 0, 0, 1 }, 1.5 -- MagnetismPreviewLineTemplate

local grid, gridLines, snapHolder, drag
local overlays, lines, snapLines, savedAlpha = {}, {}, {}, {}
local open = false

---------------------------------------------------------------- nine-slice from Forever's pieces
-- Atlas names carry `_`/`!` prefixes (they come from the art sheet's naming), so each piece keeps its own.
-- { atlas prefix+kind, flipX, flipY, anchors... } corners reuse one piece, mirrored.
local PIECES = {
  { "corner", 1, 1, { "TOPLEFT", "TOPLEFT" } }, { "corner", -1, 1, { "TOPRIGHT", "TOPRIGHT" } },
  { "corner", 1, -1, { "BOTTOMLEFT", "BOTTOMLEFT" } }, { "corner", -1, -1, { "BOTTOMRIGHT", "BOTTOMRIGHT" } },
  { "_edgetop", nil, nil, { "TOPLEFT", "TOPLEFT", CORNER, 0 }, { "TOPRIGHT", "TOPRIGHT", -CORNER, 0 }, h = CORNER },
  { "_edgebottom", nil, nil, { "BOTTOMLEFT", "BOTTOMLEFT", CORNER, 0 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -CORNER, 0 }, h = CORNER },
  { "!edgeleft", nil, nil, { "TOPLEFT", "TOPLEFT", 0, -CORNER }, { "BOTTOMLEFT", "BOTTOMLEFT", 0, CORNER }, w = CORNER },
  { "!edgeright", nil, nil, { "TOPRIGHT", "TOPRIGHT", 0, -CORNER }, { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, CORNER }, w = CORNER },
  -- Forever (editmodesystemtemplates.lua:3303-3314): centre from the top left corner's BOTTOMRIGHT + (-8, 8) to the bottom right corner's TOPLEFT + (8, -8) = the
  -- selection rectangle itself, inside the stroke (the grown frame minus GROW on every side).
  { "center", nil, nil, { "TOPLEFT", "TOPLEFT", GROW, -GROW }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -GROW, GROW } },
}

local function atlasName(state, piece)
  local prefix, kind = piece:match("^([_!]?)(.*)$")
  return prefix .. P .. state .. "-nineslice-" .. kind
end

local function paintNineSlice(box, state)
  for i, d in ipairs(PIECES) do
    local name = atlasName(state, d[1])
    AFUI.SetAtlas(box[i], name)
    local e = AFUI_ATLAS and AFUI_ATLAS[name:lower()]
    if e and d[2] then
      local l, r, t, b = e[4], e[5], e[6], e[7]
      if d[2] < 0 then l, r = r, l end
      if d[3] < 0 then t, b = b, t end
      box[i]:SetTexCoord(l, r, t, b)
    end
  end
end

-- A frame covering the selection grown by GROW on every side, with the nine pieces on it. blend: "ADD" for the mouse-over layer.
local function buildNineSlice(parent, blend)
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", -GROW, GROW)
  f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", GROW, -GROW)
  local box = {}
  for i, d in ipairs(PIECES) do
    -- The fill is the selection rectangle (strokes straddle its edge), under the strokes.
    local tex = f:CreateTexture(nil, d[1] == "center" and "BACKGROUND" or "BORDER")
    if d[2] then tex:SetWidth(CORNER); tex:SetHeight(CORNER) end
    if d.h then tex:SetHeight(d.h) end
    if d.w then tex:SetWidth(d.w) end
    for n = 4, #d do
      local a = d[n]
      tex:SetPoint(a[1], f, a[2], a[3] or 0, a[4] or 0)
    end
    if blend then tex:SetBlendMode(blend) end
    box[i] = tex
  end
  return f, box
end

---------------------------------------------------------------- selection and dragging
-- EM.OnSelect(entry or nil), EM.OnOpen() and EM.OnClose() are filled in by Dialog.lua (settings window, layout dialog).
-- ShrinkUntilTruncate chain: big, as in the real frames (about 1.5 times the dialog title), then Medium and Small
local FONTS = { EM.FontName("AFUI_SelectionLabel", 24), EM.FontName("GameFontHighlightLarge"), EM.FontName("GameFontHighlightMedium"), "GameFontHighlightSmall" }

-- The label shows the system's name while selected and "Click to Edit" while only hovered (ShouldShowLabelText).
local function updateLabel(entry)
  local o = overlays[entry.key]
  local selected = EM.selected == entry
  if not (selected or o.hover) then o.label:Hide(); return end
  local w, h = EM.SelectionBox(entry)
  o.label:SetWidth(math.max(w - 8, 20))
  o.label:SetText(selected and entry.label or "Click to Edit")
  -- the label wraps in the box; the first font whose wrapped text fits the box height is used (ShrinkUntilTruncate)
  for i, font in ipairs(FONTS) do
    o.label:SetFontObject(_G[font])
    if i == #FONTS or (o.label:GetStringHeight() or 0) <= h - 8 then break end
  end
  o.label:Show()
end

local function selectEntry(entry)
  EM.selected = entry
  for key, o in pairs(overlays) do
    local state = entry and key == entry.key and "selected" or "highlight"
    paintNineSlice(o.box, state); paintNineSlice(o.over, state)
    o:SetFrameLevel(entry and key == entry.key and 1001 or 1000)
    updateLabel(EM.systems[key])
  end
  if EM.OnSelect then EM.OnSelect(entry) end
end

local function screenSize()
  return UIParent:GetWidth() or 1024, UIParent:GetHeight() or 768
end

-- Box over the frame while it is shown and sized; otherwise (hidden by setting, no layout yet) a box of the same size at the
-- saved position, so the system can still be seen and placed.
local function visible(entry)
  local w, h = EM.Size(entry.frame)
  if entry.frame:IsShown() and w > 1 and h > 1 then entry.lastW, entry.lastH = w, h; return true end
  return false
end

local function placeOverlay(entry)
  local o = overlays[entry.key]
  o:ClearAllPoints()
  local sel = entry.selection or { 0, 0, 0, 0 }
  if visible(entry) then
    o:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", sel[1], sel[2])
    o:SetPoint("BOTTOMRIGHT", entry.frame, "BOTTOMRIGHT", sel[3], sel[4])
  else
    local w, h, dx, dy = EM.SelectionBox(entry)
    local cur = EM.current.systems[entry.key]
    o:SetWidth(w); o:SetHeight(h)
    o:SetPoint("CENTER", UIParent, "CENTER", (cur.x or 0) + dx, (cur.y or 0) + dy)
  end
  updateLabel(entry)
end

-- A setting or position changed through the registry (settings window, layout switch): the box follows it.
function EM.RefreshOverlay(key)
  if open and overlays[key] then placeOverlay(EM.systems[key]) end
end
EM.Watch(function(key) EM.RefreshOverlay(key) end)

---------------------------------------------------------------- snap preview lines
local function hideSnapLines()
  for i = 1, #snapLines do snapLines[i]:Hide() end
end

-- One red line per snapped target (MagnetismPreviewLines): along the target's edge or centre line; screen and grid targets
-- run the whole screen, a frame target spans both frames.
local function showSnapLines(list)
  if not snapHolder then
    snapHolder = CreateFrame("Frame", "AFUI_EditModeSnapLines", UIParent)
    snapHolder:SetFrameStrata("HIGH"); snapHolder:SetAllPoints(UIParent)
  end
  local w, h = screenSize()
  for i, l in ipairs(list) do
    local t = snapLines[i]
    if not t then t = snapHolder:CreateTexture(nil, "OVERLAY"); AFUI.SetColor(t, SNAP_LINE[1], SNAP_LINE[2], SNAP_LINE[3], 1); snapLines[i] = t end
    local lo, hi = l.lo, l.hi
    t:ClearAllPoints()
    if l.axis == "x" then
      lo, hi = lo or -h / 2, hi or h / 2
      t:SetWidth(SNAP_THICKNESS); t:SetHeight(hi - lo)
      t:SetPoint("CENTER", UIParent, "CENTER", l.pos, (lo + hi) / 2)
    else
      lo, hi = lo or -w / 2, hi or w / 2
      t:SetWidth(hi - lo); t:SetHeight(SNAP_THICKNESS)
      t:SetPoint("CENTER", UIParent, "CENTER", (lo + hi) / 2, l.pos)
    end
    t:Show()
  end
  for i = #list + 1, #snapLines do snapLines[i]:Hide() end
end

local function endDrag()
  if not drag then return end
  local d = drag
  drag = nil
  overlays[d.entry.key]:SetScript("OnUpdate", nil)
  hideSnapLines()
  if d.x ~= d.x0 or d.y ~= d.y0 then -- a click that never moved the mouse changes nothing (and leaves the layout saved)
    local x, y = EM.SnapPlacement(d.entry, d.x, d.y)
    EM.SetPosition(d.entry.key, x, y)
  end
  placeOverlay(d.entry)
end

local function startDrag(entry)
  if InCombatLockdown() then return end
  if drag then endDrag() end -- a lost mouse-up left the last drag running
  local cur = EM.Capture(entry)
  local cx, cy = GetCursorPosition()
  local es = UIParent:GetEffectiveScale() or 1
  local x0, y0 = cur.x or 0, cur.y or 0
  drag = { entry = entry, x = x0, y = y0, x0 = x0, y0 = y0 }
  overlays[entry.key]:SetScript("OnUpdate", function() -- runs only while dragging
    if InCombatLockdown() then return endDrag() end
    local mx, my = GetCursorPosition()
    drag.x, drag.y = x0 + (mx - cx) / es, y0 + (my - cy) / es
    EM.Place(entry, drag.x, drag.y)
    if not visible(entry) then -- a placeholder box has no frame to follow
      local c = EM.current.systems[entry.key]
      c.x, c.y = drag.x, drag.y
      placeOverlay(entry)
    end
    -- the preview shows where the box will snap to on release (Forever refreshes it every frame, snaps on drop)
    local _, _, list = EM.SnapPlacement(entry, drag.x, drag.y)
    showSnapLines(list)
  end)
end

---------------------------------------------------------------- frames
local function buildOverlay(entry)
  local o = CreateFrame("Frame", "AFUI_EditOverlay_" .. entry.key, UIParent)
  o:SetFrameStrata("DIALOG")
  o:SetFrameLevel(1000)
  o:EnableMouse(true)
  o.art, o.box = buildNineSlice(o)
  o.overFrame, o.over = buildNineSlice(o, "ADD") -- MouseOverHighlight: same art, ADD blend, alpha 0.4
  o.overFrame:SetAlpha(0.4); o.overFrame:Hide()
  paintNineSlice(o.box, "highlight"); paintNineSlice(o.over, "highlight")
  o.label = o:CreateFontString(nil, "OVERLAY", FONTS[1])
  o.label:SetPoint("CENTER", o, "CENTER", 0, 0)
  o.label:Hide()
  o:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then return end
    startDrag(entry); selectEntry(entry) -- the drag first: a settings error must never block it
  end)
  o:SetScript("OnMouseUp", function() endDrag() end)
  o:SetScript("OnEnter", function()
    o.hover = true; o.overFrame:Show(); updateLabel(entry)
    if EM.selected ~= entry and GameTooltip and GameTooltip.SetOwner then
      GameTooltip:SetOwner(o, "ANCHOR_CURSOR"); GameTooltip:SetText(entry.label); GameTooltip:Show()
    end
  end)
  o:SetScript("OnLeave", function()
    o.hover = nil; o.overFrame:Hide(); updateLabel(entry)
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
  end)
  o:Hide()
  return o
end

local function drawGrid()
  local w, h = screenSize()
  local spacing = EM.Config().gridSpacing
  local n = 0
  local function line(vertical, offset, centre)
    n = n + 1
    local t = lines[n]
    if not t then t = gridLines:CreateTexture(nil, "BACKGROUND"); lines[n] = t end
    t:ClearAllPoints()
    if vertical then
      t:SetWidth(GRID_THICKNESS); t:SetHeight(h); t:SetPoint("CENTER", UIParent, "CENTER", offset, 0)
    else
      t:SetWidth(w); t:SetHeight(GRID_THICKNESS); t:SetPoint("CENTER", UIParent, "CENTER", 0, offset)
    end
    local c = centre and GRID_CENTER or GRID_LINE
    AFUI.SetColor(t, c[1], c[2], c[3], c[4])
    t:Show()
  end
  -- centred on the screen, not anchored to a corner (EditModeManagerFrame.Grid)
  line(true, 0, true); line(false, 0, true)
  for i = 1, math.floor(w / spacing / 2) do line(true, i * spacing); line(true, -i * spacing) end
  for i = 1, math.floor(h / spacing / 2) do line(false, i * spacing); line(false, -i * spacing) end
  for i = n + 1, #lines do lines[i]:Hide() end
end

local function updateGrid()
  if not grid then return end
  if EM.Config().showGrid then drawGrid(); gridLines:Show() else gridLines:Hide() end
end
EM.WatchConfig(function(key) if key == "showGrid" or key == "gridSpacing" then updateGrid() end end)


local function buildGrid()
  grid = CreateFrame("Frame", "AFUI_EditModeGrid", UIParent)
  grid:SetFrameStrata("BACKGROUND")
  grid:SetAllPoints(UIParent)
  gridLines = CreateFrame("Frame", nil, grid)
  gridLines:SetAllPoints(grid)
  -- Esc hides the grid through UISpecialFrames. With unsaved changes Forever asks first (editmodemanager.lua:47-53):
  -- stay open and show the Save / Discard / Cancel prompt.
  grid:SetScript("OnHide", function()
    if open and EM.dirty and EM.RequestClose and not InCombatLockdown() then
      grid:Show()
      EM.RequestClose()
    else
      EM.Close()
    end
  end)
  if UISpecialFrames then table.insert(UISpecialFrames, "AFUI_EditModeGrid") end
end

---------------------------------------------------------------- open / close
function EM.IsOpen() return open end

-- Forever shows the player's own data in the frames that have no unit of their own (editmodemanager.lua:2006-2063).
-- The frames Forever shows with the player's data are the ones whose checkbox is ticked.
local PREVIEW_UNITS = { targetfocus = { "target", "targettarget" }, petframe = { "pet" }, party = { "party1", "party2", "party3", "party4" } }
local function previews(on)
  if AFUI.Units and AFUI.Units.SetPreview then
    local set = {}
    for group, keys in pairs(PREVIEW_UNITS) do
      if EM.IsShown(group) then for _, k in ipairs(keys) do set[k] = true end end
    end
    AFUI.Units.SetPreview(on, set)
  end
  if AFUI.EndCaps and AFUI.EndCaps.Refresh then AFUI.EndCaps.Refresh() end
end

-- A checkbox ticked or cleared while Edit Mode is open: the box comes or goes and the preview follows (out of combat only, like
-- the open itself: the frames are protected).
EM.WatchConfig(function(key)
  if key ~= "show" or not open or InCombatLockdown() then return end
  EM.RefreshEnabled()
  if AFUI.Units and AFUI.Units.SetPreview then AFUI.Units.SetPreview(false) end
  previews(true)
end)

function EM.Open()
  if InCombatLockdown() then
    UIErrorsFrame:AddMessage("Can't open Edit Mode in combat.", 1, 0.1, 0.1)
    return false
  end
  if open then return true end
  if not grid then buildGrid() end
  open = true
  previews(true)
  for _, key in ipairs(EM.order) do
    local entry = EM.systems[key]
    EM.Capture(entry) -- a frame without a layout at login gets its placement now
    -- a system that is switched off (an action bar disabled in Interface > Action Bars) or not ticked in the dialog has no box
    if EM.IsListed(entry) then
      if not overlays[key] then overlays[key] = buildOverlay(entry) end
      -- mouseover bars would be invisible; hidden frames still get their box, so they can be placed
      local a = entry.frame:GetAlpha()
      if a and a < 1 then savedAlpha[key] = a; entry.frame:SetAlpha(1) end
      placeOverlay(entry)
      overlays[key]:Show()
    end
  end
  selectEntry(nil)
  updateGrid()
  grid:Show()
  if EM.OnOpen then EM.OnOpen() end
  return true
end

-- A system was switched on or off while Edit Mode is open (the action bar toggles): its box comes or goes.
function EM.RefreshEnabled()
  if not open then return end
  for _, key in ipairs(EM.order) do
    local entry, o = EM.systems[key], overlays[key]
    if EM.IsListed(entry) then
      if not o then o = buildOverlay(entry); overlays[key] = o end
      if not o:IsShown() then placeOverlay(entry); o:Show() end
    elseif o and o:IsShown() then
      if EM.selected == entry then selectEntry(nil) end
      o:Hide()
    end
  end
end

-- keepChanges (combat start): unsaved edits stay live and marked unsaved, instead of being reverted.
function EM.Close(keepChanges)
  if not open then return end
  open = false
  endDrag()
  for _, o in pairs(overlays) do o:Hide() end
  for key, a in pairs(savedAlpha) do EM.systems[key].frame:SetAlpha(a); savedAlpha[key] = nil end
  grid:Hide()
  EM.selected = nil
  previews(false)
  -- Forever's ExitEditMode reverts whatever was not saved (editmodemanager.lua:116-119); Dialog supplies the revert.
  if EM.dirty and EM.RevertChanges and not keepChanges then EM.RevertChanges() end
  if EM.OnClose then EM.OnClose() end
end

function EM.Toggle() if open then EM.Close() else EM.Open() end end

-- Pending changes already sit in EM.current and in RunOutOfCombat's queue; they apply when combat ends, and stay
-- unsaved (EM.dirty) for the next Open.
AFUI.On("PLAYER_REGEN_DISABLED", function() EM.Close(true) end)

SLASH_AFUIEDITMODE1 = "/editmode"
SlashCmdList = SlashCmdList or {}
SlashCmdList["AFUIEDITMODE"] = EM.Toggle

-- "Edit Mode" in the Esc menu, directly above Key Bindings. The menu buttons are chained by anchors on both clients.
local function addMenuButton()
  local keys = GameMenuButtonKeybindings
  if not (GameMenuFrame and keys) or EM.menuButton then return end
  if not AFUI.ModuleEnabled("gamemenu") then return end -- the client's own Esc menu stays as it is: Edit Mode opens with /editmode or from /afui
  local b = CreateFrame("Button", "AFUI_GameMenuButtonEditMode", GameMenuFrame, "GameMenuButtonTemplate")
  EM.menuButton = b
  b:SetText("Edit Mode")
  b:SetScript("OnClick", function()
    if HideUIPanel then HideUIPanel(GameMenuFrame) else GameMenuFrame:Hide() end
    EM.Open()
  end)
  if AFUI.GameMenu then AFUI.GameMenu.Adopt(b); return end -- GameMenu.lua lays the whole menu out (Forever's order)
  local point, rel, relPoint, x, y = keys:GetPoint(1)
  b:SetPoint(point, rel, relPoint, x, y)
  keys:ClearAllPoints()
  keys:SetPoint("TOP", b, "BOTTOM", 0, y or -1)
  local extra = keys:GetHeight() or 0
  GameMenuFrame:SetHeight(GameMenuFrame:GetHeight() + extra)
  -- 2.5.3 recomputes the height on every show (GameMenuFrame_UpdateVisibleButtons); add ours again after it.
  if GameMenuFrame_UpdateVisibleButtons then
    hooksecurefunc("GameMenuFrame_UpdateVisibleButtons", function()
      GameMenuFrame:SetHeight(GameMenuFrame:GetHeight() + extra)
    end)
  end
  b:SetScript("OnClick", function()
    if HideUIPanel then HideUIPanel(GameMenuFrame) else GameMenuFrame:Hide() end
    EM.Open()
  end)
end

AFUI.RegisterModule("EditModeOverlay", { OnLogin = addMenuButton })
