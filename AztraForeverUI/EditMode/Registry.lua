-- Edit Mode registry: every movable system, its settings schema and its current (pending or applied) placement.
-- AFUI.EditMode.current is the live layout; Layouts.Apply fills it from the active saved layout, Dialog saves it back.
-- AFUI.EditMode.dirty is true while it differs from the saved one; dirtyKeys says which systems changed.
AFUI = AFUI or {}
local EM = { systems = {}, order = {}, current = { systems = {} }, dirtyKeys = {} }
AFUI.EditMode = EM

local function copy(t) local c = {}; for k, v in pairs(t or {}) do c[k] = v end; return c end

-- GameFontHighlightMedium (14, white) is not in the TBC clients' FrameXML: made here from GameFontHighlight when missing.
-- Returns the global name of a font object that exists.
function EM.FontName(name, size)
  if not size and _G[name] then return name end
  local mine = size and name or "AFUI_" .. name
  if not _G[mine] and CreateFont and GameFontHighlight then
    local f = CreateFont(mine)
    local file = GameFontHighlight:GetFont()
    f:SetFont(file, size or 14, ""); f:SetTextColor(1, 1, 1); f:SetShadowColor(0, 0, 0, 1); f:SetShadowOffset(1, -1)
  end
  return _G[mine] and mine or "GameFontHighlight"
end

local SCALE = { id = "scale", type = "slider", label = "Size", min = 0.25, max = 2.0, step = 0.05, percent = true }
-- the bars' own: Forever's "Icon Size" 50-200 % in steps of 10
local ICON_SIZE = { id = "scale", type = "slider", label = "Icon Size", min = 0.25, max = 2.0, step = 0.05, percent = true }

---------------------------------------------------------------- account settings (grid, snap)
-- Forever keeps these per account (ShowGrid, GridSpacing, EnableSnap). The range and default live in its C++: the real dialog shows
-- 100 with the thumb at 29% of the bar, so ours is 20..300 in steps of 10, default 100, snap on, grid shown.
local DEFAULTS = { showGrid = true, snap = true, gridSpacing = 100 }
EM.GRID_MIN, EM.GRID_MAX, EM.GRID_STEP = 20, 300, 10

-- The live settings table, repaired where the saved variables are missing or damaged.
function EM.Config()
  if type(AztraForeverUIDB) ~= "table" then AztraForeverUIDB = {} end
  local c = AztraForeverUIDB.editMode
  if type(c) ~= "table" then c = {}; AztraForeverUIDB.editMode = c end
  if type(c.showGrid) ~= "boolean" then c.showGrid = DEFAULTS.showGrid end
  if type(c.snap) ~= "boolean" then c.snap = DEFAULTS.snap end
  if type(c.gridSpacing) ~= "number" or c.gridSpacing ~= c.gridSpacing then c.gridSpacing = DEFAULTS.gridSpacing end
  c.gridSpacing = math.min(math.max(c.gridSpacing, EM.GRID_MIN), EM.GRID_MAX)
  if type(c.show) ~= "table" then c.show = {} end -- the account checkboxes (EM.GROUPS): ticked = true
  return c
end

local configWatchers = {}
-- fn(key) runs after every SetConfig: Overlay redraws the grid, Dialog updates its widgets.
function EM.WatchConfig(fn) configWatchers[#configWatchers + 1] = fn end
function EM.SetConfig(key, value)
  local c = EM.Config()
  if key == "gridSpacing" then
    value = math.floor(value / EM.GRID_STEP + 0.5) * EM.GRID_STEP
    value = math.min(math.max(value, EM.GRID_MIN), EM.GRID_MAX)
  end
  c[key] = value
  for i = 1, #configWatchers do configWatchers[i](key) end
end

---------------------------------------------------------------- account checkboxes
-- Forever's "Target and Focus", "Party Frames", "Cast Bar", ... : systems that have no selection box (and no preview) until their
-- checkbox is ticked (defaultHideSelection). Only the groups of systems this addon has are listed. `basic` = also in the quick list.
EM.GROUPS = {
  { id = "targetfocus", text = "Target and Focus", section = "Frames", basic = true },
  { id = "petframe", text = "Pet Frame", section = "Frames" },
  { id = "party", text = "Party Frames", section = "Frames", basic = true },
  { id = "buffs", text = "Buffs and Debuffs", section = "Combat" },
  { id = "castbar", text = "Cast Bar", section = "Combat", basic = true },
  { id = "stancebar", text = "Stance Bar", section = "Combat" },
  { id = "petbar", text = "Pet Bar", section = "Combat" },
  { id = "possessbar", text = "Possess Bar", section = "Combat" },
  { id = "statusbar2", text = "Status Bar 2", section = "Misc" },
  { id = "hudtooltip", text = "HUD Tooltip", section = "Misc" },
  { id = "durability", text = "Equipment Durability", section = "Misc" },
  { id = "durationbars", text = "Duration Bars", section = "Misc" },
  { id = "raidwarnings", text = "Raid Warnings", section = "Misc" },
}
local SECTIONS = { "Frames", "Combat", "Misc" }

-- Boxes ticked in the video's list from the start (Buffs and Debuffs, Status Bar 2, HUD Tooltip) show until the player unticks them.
-- Target and Pet frames start ticked too, so they can be moved at once (their box shows the preview data).
local TICKED = { buffs = true, statusbar2 = true, hudtooltip = true, targetfocus = true, petframe = true, durability = true, raidwarnings = true }
function EM.IsShown(group)
  local v = EM.Config().show[group]
  if v == nil then return TICKED[group] == true end
  return v == true
end
function EM.SetShown(group, on)
  EM.Config().show[group] = on and true or false
  for i = 1, #configWatchers do configWatchers[i]("show", group) end
end

-- { { title, items = { { id, text }, ... } }, ... } of the groups that have a registered system. advanced = false: the quick list
-- (one untitled section); true: the sections Frames / Combat / Misc, the empty ones dropped.
function EM.GroupSections(advanced)
  local have = {}
  for _, e in pairs(EM.systems) do if e.group then have[e.group] = true end end
  local out = {}
  for _, title in ipairs(advanced and SECTIONS or { "" }) do
    local items = {}
    for _, g in ipairs(EM.GROUPS) do
      if have[g.id] and (advanced and g.section == title or (not advanced and g.basic)) then items[#items + 1] = { id = g.id, text = g.text } end
    end
    if #items > 0 then out[#out + 1] = { title = title, items = items } end
  end
  return out
end

-- Centre of `frame` as an offset from the UIParent centre, in UIParent units. nil until the frame has a layout.
function EM.CentreOffset(frame)
  local cx, cy = frame:GetCenter()
  local ux, uy = UIParent:GetCenter()
  if not (cx and ux) then return nil end
  local k = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  return cx * k - ux, cy * k - uy
end

-- Size of `frame` in UIParent units.
function EM.Size(frame)
  local s = frame:GetScale() or 1
  return (frame:GetWidth() or 1) * s, (frame:GetHeight() or 1) * s
end

function EM.Capture(entry)
  local cur = EM.current.systems[entry.key]
  if not cur then
    cur = copy(entry.defaults)
    cur.scale = cur.scale or entry.frame:GetScale() or 1
    EM.current.systems[entry.key] = cur
  end
  if cur.x == nil then cur.x, cur.y = EM.CentreOffset(entry.frame) end
  return cur
end

-- Fallback box for a frame with no size yet (hidden, not laid out): same as the overlay placeholder.
local FALLBACK_W, FALLBACK_H = 120, 40

-- Forever's selection box: the frame's rectangle with TOPLEFT / BOTTOMRIGHT moved by `selection` = { tlx, tly, brx, bry }
-- (docs/forever-ref/editmode.md section 1). Returns the box size and the offset of its centre from the frame's centre,
-- all in UIParent units. A frame with no size yet (hidden, never laid out) uses the last known one.
function EM.SelectionBox(entry)
  local w, h = EM.Size(entry.frame)
  if w < 1 or h < 1 then w, h = entry.lastW or FALLBACK_W, entry.lastH or FALLBACK_H end
  local s = entry.frame:GetScale() or 1
  local sel = entry.selection or { 0, 0, 0, 0 }
  return w + (sel[3] - sel[1]) * s, h + (sel[2] - sel[4]) * s, (sel[1] + sel[3]) / 2 * s, (sel[2] + sel[4]) / 2 * s
end

-- Where the frame goes when its box is dragged to (x, y) = the frame's centre: the box is snapped (to the screen, the grid
-- when shown, and the other systems' boxes) and kept on screen, then the frame follows by the same amount. Returns the
-- frame centre and the preview lines (AFUI.Snap).
function EM.SnapPlacement(entry, x, y)
  local cfg = EM.Config()
  local w, h, dx, dy = EM.SelectionBox(entry)
  local sw, sh = UIParent:GetWidth() or 1024, UIParent:GetHeight() or 768
  local others = { screen = { w = sw, h = sh } }
  local grid, threshold = 0, -1 -- -1: nothing snaps, the box is only kept on screen
  if cfg.snap then
    threshold = 8 / (UIParent:GetEffectiveScale() or 1)
    if cfg.showGrid then grid = cfg.gridSpacing end
    for _, key in ipairs(EM.order) do
      local o, cur = EM.systems[key], EM.current.systems[key]
      if o ~= entry and cur and cur.x and EM.IsListed(o) then
        local ow, oh, odx, ody = EM.SelectionBox(o)
        others[#others + 1] = { x = cur.x + odx, y = cur.y + ody, w = ow, h = oh }
      end
    end
  end
  local sx, sy, lines = AFUI.Snap({ x = x + dx, y = y + dy, w = w, h = h }, others, grid, threshold)
  return sx - dx, sy - dy, lines
end

-- Offset of the named anchor point from the centre of a w x h box (x right, y up).
local function pointOffset(point, w, h)
  local x, y = 0, 0
  if point:find("LEFT") then x = -w / 2 elseif point:find("RIGHT") then x = w / 2 end
  if point:find("TOP") then y = h / 2 elseif point:find("BOTTOM") then y = -h / 2 end
  return x, y
end

-- Turns a preset anchor ({ point, relPoint, x, y } on UIParent) into a centre offset against the LIVE screen size and the
-- frame's size after its settings, then keeps the box inside the screen (offsets saved on a bigger screen never load
-- off it). Writes cur.x / cur.y and drops cur.anchor. `key` may be unregistered (copying a preset before login).
--
-- A system in its default position (placed from a preset anchor, never dragged) has cur.auto = true. Those with an entry in
-- AFUI.AutoPlace (Presets.lua: the bottom stack and the right bars, Forever's automatic bar positioning) keep their anchor and are
-- worked out again every time they are placed: AutoPlace[key](cur, anchor, screenW, screenH) returns the anchor to use (the
-- bar's slot in the stack) and the scale the bar fits at (cur.autoScale, ignored once the player moves the system).
function EM.Resolve(key, cur, depth)
  local entry = EM.systems[key]
  local sw, sh = UIParent:GetWidth() or 1024, UIParent:GetHeight() or 768
  local a0 = cur.anchor
  local place = AFUI.AutoPlace and AFUI.AutoPlace[key]
  local fresh = a0 and (cur.x == nil or (cur.auto and place))
  local a = a0
  if fresh and type(place) == "function" then
    local placed, fit = place(cur, a0, sw, sh)
    a, cur.autoScale = placed or a0, fit
  elseif fresh then
    cur.autoScale = nil
  end
  if not fresh then cur.autoScale = nil end
  local scale = cur.autoScale or cur.scale or 1
  local w, h = 0, 0
  if entry then w, h = (entry.frame:GetWidth() or 0) * scale, (entry.frame:GetHeight() or 0) * scale end
  if w < 1 or h < 1 then w, h = entry and entry.lastW or FALLBACK_W, entry and entry.lastH or FALLBACK_H end
  if a and fresh then
    local rx, ry, rw, rh = 0, 0, sw, sh
    local rel = a.rel and EM.systems[a.rel]
    local relCur = rel and EM.current.systems[a.rel]
    if rel and relCur and (depth or 0) < 4 then -- anchored to another system (the end caps hang off the bars)
      if relCur.x == nil then EM.Resolve(a.rel, relCur, (depth or 0) + 1) end
      rx, ry = relCur.x or 0, relCur.y or 0
      rw, rh = (rel.frame:GetWidth() or 0) * (relCur.scale or 1), (rel.frame:GetHeight() or 0) * (relCur.scale or 1)
    end
    local ox, oy = pointOffset(a.relPoint, rw, rh)
    local fx, fy = pointOffset(a.point, w, h)
    cur.x, cur.y = rx + ox + a.x - fx, ry + oy + a.y - fy
    cur.auto = true
  end
  if not (place and cur.auto and a0) then cur.anchor = nil end
  if cur.x and cur.y then -- keep the selection box (not the whole frame) on screen
    local sel = entry and entry.selection or { 0, 0, 0, 0 }
    local bw, bh = w + (sel[3] - sel[1]) * scale, h + (sel[2] - sel[4]) * scale
    local dx, dy = (sel[1] + sel[3]) / 2 * scale, (sel[2] + sel[4]) / 2 * scale
    local x, y = AFUI.Snap({ x = cur.x + dx, y = cur.y + dy, w = bw, h = bh }, { screen = { w = sw, h = sh } }, 0, 0)
    cur.x, cur.y = x - dx, y - dy
  end
end

-- Anchors entry.frame by its centre at the stored offset (resolving a preset anchor first). Offsets are in UIParent
-- units, SetPoint wants the frame's own. x, y given explicitly (dragging) are used as they are.
function EM.Place(entry, x, y)
  local cur = EM.current.systems[entry.key]
  if x == nil then
    EM.Resolve(entry.key, cur)
    x, y = cur.x, cur.y
  end
  if not x then return end
  local scale = cur.autoScale or cur.scale or 1
  entry.frame:SetScale(scale)
  entry.frame:ClearAllPoints()
  entry.frame:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
end

-- def = { frame, label, settingsSchema, apply(entry), defaults, selection = { tlx, tly, brx, bry }, noScale }.
-- Every system gets a scale slider unless noScale.
function EM.Register(key, def)
  local entry = { key = key, frame = def.frame, label = def.label or key, defaults = def.defaults, selection = def.selection,
    enabled = def.enabled, group = def.group, keybind = def.keybind }
  -- the schema decides the order of the rows; a scale slider of its own (Icon Size, Frame Size) replaces the default one, put first
  local schema, hasScale = {}, false
  for _, s in ipairs(def.settingsSchema or {}) do
    if s.id == "scale" then hasScale = true end
    schema[#schema + 1] = s
  end
  if not def.noScale and not hasScale then
    local sc = copy(SCALE)
    sc.label = def.scaleLabel or sc.label
    table.insert(schema, 1, sc)
  end
  entry.settingsSchema = schema
  entry.run = function() -- stable identity, so RunOutOfCombat queues it once
    if def.apply then def.apply(entry) else EM.Place(entry) end
  end
  if not EM.systems[key] then EM.order[#EM.order + 1] = key end
  EM.systems[key] = entry
  EM.Capture(entry)
  return entry
end

function EM.ClearDirty() EM.dirty = false; EM.dirtyKeys = {} end

-- A system can be switched off outside Edit Mode (the action bars the player turned off in Interface > Action Bars): it has no
-- selection box, does not snap others and does not count in the bottom stack while it is.
function EM.IsEnabled(entry) return not entry.enabled or entry.enabled() end

-- Has a box in Edit Mode: enabled, and (for the systems Forever hides by default) its account checkbox is ticked.
function EM.IsListed(entry) return EM.IsEnabled(entry) and (not entry.group or EM.IsShown(entry.group)) end

-- fn(key, field) runs after every change made through SetPosition / SetSetting (the overlay and the dialog listen).
local watchers = {}
function EM.Watch(fn) watchers[#watchers + 1] = fn end

-- Writes the change to `current` straight away and applies it now, or after combat. Marks the layout unsaved.
local function change(key, field, value)
  local entry, cur = EM.systems[key], EM.current.systems[key]
  if field then cur[field] = value end
  EM.dirty = true
  EM.dirtyKeys[key] = true
  AFUI.RunOutOfCombat(entry.run)
  for i = 1, #watchers do watchers[i](key, field) end
end
function EM.SetPosition(key, x, y)
  local cur = EM.current.systems[key]
  cur.x, cur.y, cur.anchor, cur.auto, cur.autoScale = x, y, nil, nil, nil -- placed by the player: no longer automatic
  change(key)
end
function EM.SetSetting(key, id, value) change(key, id, value) end

-- "Reset To Default Position": enabled once the player moved the system (an automatic position keeps its preset anchor).
function EM.IsMoved(key)
  local cur = EM.current.systems[key]
  return cur ~= nil and cur.anchor == nil and cur.x ~= nil and not cur.auto
end

-- Back to the Modern preset's anchor (Forever's default position), placed again at once or after combat.
function EM.ResetPosition(key)
  local cur, base = EM.current.systems[key], AFUI.PRESETS and AFUI.PRESETS.Modern.systems[key]
  if not (cur and base and base.anchor) then return false end
  cur.anchor = {}
  for k, v in pairs(base.anchor) do cur.anchor[k] = v end
  cur.x, cur.y, cur.auto, cur.autoScale = nil, nil, nil, nil
  change(key)
  return true
end

---------------------------------------------------------------- wiring of the existing modules
-- Rows of the settings window as in the real one (Stance Bar: Orientation, # of Rows, Icon Size, Icon Padding); the right bars are
-- vertical in Forever's presets (one column).
local function bar(key, label, full, group)
  local b = AFUI.Bars[key]
  if not b then return end -- possess exists only where the client has the bar
  local schema = { { id = "orientation", type = "dropdown", label = "Orientation", options = { "Horizontal", "Vertical" } },
    { id = "numRows", type = "slider", label = "# of Rows", min = 1, max = 12, step = 1 } }
  if full then schema[#schema + 1] = { id = "numIcons", type = "slider", label = "# of Icons", min = 1, max = 12, step = 1 } end
  schema[#schema + 1] = ICON_SIZE
  schema[#schema + 1] = { id = "padding", type = "slider", label = "Icon Padding", min = 0, max = 10, step = 1 }
  if not full then schema[#schema + 1] = { id = "hidden", type = "checkbox", label = "Hide Bar" } end -- pet / stance / possess
  if full then
    schema[#schema + 1] = { id = "visibility", type = "dropdown", label = "Visible", options = { "always", "mouseover" } }
    schema[#schema + 1] = { id = "alwaysShow", type = "checkbox", label = "Always Show Buttons" }
    if key == "main" then -- the video's main bar: Hide Bar Art, Hide Bar Scrolling
      schema[#schema + 1] = { id = "hideBarArt", type = "checkbox", label = "Hide Bar Art" }
      schema[#schema + 1] = { id = "hideBarScrolling", type = "checkbox", label = "Hide Bar Scrolling" }
    end
  end
  EM.Register(key, { frame = b.frame, label = label, settingsSchema = schema, defaults = copy(b.settings), group = group, keybind = full,
    enabled = AFUI.BarEnabled and function() return AFUI.BarEnabled(key) end,
    apply = function(entry)
      local s = EM.current.systems[key]
      b.ApplySettings({ numIcons = s.numIcons, numRows = s.numRows, padding = s.padding, visibility = s.visibility,
        orientation = s.orientation, hidden = s.hidden, alwaysShow = s.alwaysShow, hideBarArt = s.hideBarArt, hideBarScrolling = s.hideBarScrolling })
      EM.Place(entry)
      if AFUI.RestackBars then AFUI.RestackBars() end -- the bars above this one follow its height
    end })
end

local function plain(key, label, frame, selection)
  if frame then EM.Register(key, { frame = frame, label = label, selection = selection }) end
end

-- Forever's selection insets { TOPLEFT x, y, BOTTOMRIGHT x, y } (docs/forever-ref/editmode.md section 1). Our unit frame
-- buttons are Forever's canvases (player and target 232x100 with the art inside, pet 120x49), so its insets apply as they are.
local BIG_UNIT = { 20, -16, -20, 18 }
local SMALL_UNIT = { 4, -3, -4, 6 }
local END_CAP = { left = { 26, -5, -34, 2 }, right = { 34, -5, -26, 2 } }

local PORTRAIT = { { id = "showPortrait", type = "checkbox", label = "Show Portrait" } }
-- With the portrait off the selection box shrinks to the visible body: the cut side moves to where UnitFrames crops the art
-- (the frame keeps its size and place, so the bars do not move). base = the insets with the portrait on.
function EM.FitUnitSelection(entry, geoKey, base, showPortrait)
  if not AFUI.UnitFrameGeometry then return end
  local g = AFUI.UnitFrameGeometry(geoKey, showPortrait)
  local sel = { base[1], base[2], base[3], base[4] }
  if g.off then
    local x, w, left = AFUI.ClosedEndRect(g)
    local reach = g.reach or (left and x or x + w) -- the level badge and PvP flag hang outside the cut edge
    if left then sel[1] = reach else sel[3] = -(g.w - reach) end
  end
  entry.selection = sel
  EM.RefreshOverlay(entry.key)
end

local function unit(key, unitKey, label, selection, group)
  local u = AFUI.Units and AFUI.Units[unitKey]
  if not u then return end
  EM.Register(key, { frame = u.frame, label = label, selection = selection, settingsSchema = PORTRAIT, scaleLabel = "Frame Size", group = group,
    defaults = { showPortrait = u.settings.showPortrait },
    apply = function(entry)
      local s = EM.current.systems[key]
      u.ApplySettings({ showPortrait = s.showPortrait, scale = s.scale })
      EM.FitUnitSelection(entry, unitKey, selection, s.showPortrait)
      EM.Place(entry)
    end })
  EM.FitUnitSelection(EM.systems[key], unitKey, selection, u.settings.showPortrait)
end

local PARTY_STRIDE = 63 -- party frames are 53 high, Forever spaces them 10 apart (unitframe shared/partyframe.lua:150-156)
local function party()
  local u1 = AFUI.Units and AFUI.Units.party1
  if not u1 then return end
  -- the box spans all four member frames (Forever's party frame is one container)
  -- Forever's order: the raid-style checkbox first; the portrait is ours (old style only), width / height / power bar / pets are the
  -- raid-style ones (Frame Width, Frame Height, Sort By, Use Horizontal Layout, Display Border, then the raid profile's own options). Defaults of a new character: the client's raid profile (CompactParty.lua).
  local function old(s) return not s.useRaidStyle end
  local function raid(s) return s.useRaidStyle end
  local CP = AFUI.CompactParty
  local defaults = { showPortrait = u1.settings.showPortrait }
  for k, v in pairs(CP and CP.DEFAULTS or {}) do defaults[k] = v end
  local scale = copy(SCALE); scale.label = "Frame Size"
  EM.Register("party", { frame = u1.frame, label = "Party Frames", selection = { 0, 0, 0, -3 * PARTY_STRIDE }, group = "party",
    settingsSchema = {
      { id = "useRaidStyle", type = "checkbox", label = "Use Raid-Style Party Frames", reshape = true },
      { id = "showPortrait", type = "checkbox", label = "Show Portrait", show = old },
      { id = "frameWidth", type = "slider", label = "Frame Width", min = 72, max = 144, step = 2, show = raid },
      { id = "frameHeight", type = "slider", label = "Frame Height", min = 36, max = 72, step = 2, show = raid },
      { id = "sortBy", type = "dropdown", label = "Sort By", options = CP and CP.SORT or { "Group" }, show = raid },
      { id = "useHorizontal", type = "checkbox", label = "Use Horizontal Layout", show = raid },
      { id = "displayBorder", type = "checkbox", label = "Display Border", show = raid },
      -- the client's raid profile options (its "Raid Frame Settings" window), in its order
      { id = "displayPets", type = "checkbox", label = "Display Pets", show = raid },
      { id = "displayPowerBar", type = "checkbox", label = "Display Power Bar", show = raid },
      { id = "useClassColors", type = "checkbox", label = "Use Class Colors", show = raid },
      { id = "onlyDispellable", type = "checkbox", label = "Display Only Dispellable Debuffs", show = raid },
      { id = "healthText", type = "dropdown", label = "Health Text", options = CP and CP.HEALTH_TEXT or { "None" }, show = raid },
      scale },
    defaults = defaults,
    apply = function(entry)
      local s = EM.current.systems.party
      for k, v in pairs(defaults) do if s[k] == nil then s[k] = v end end -- a layout saved before these settings existed
      if CP then CP.Apply(s) end
      if s.useRaidStyle and CP then
        local w, h = CP.Size(s) -- the box spans all raid-style rows, drawn from the old frame's corner
        entry.selection = { 0, 0, w - 120, -(h - 53) }
        EM.RefreshOverlay(entry.key)
      else
        EM.FitUnitSelection(entry, "party1", { 0, 0, 0, -3 * PARTY_STRIDE }, s.showPortrait)
      end
      EM.Place(entry)
      for i = 1, 4 do
        local u = AFUI.Units["party" .. i]
        u.ApplySettings({ showPortrait = s.showPortrait, scale = s.scale })
        if i > 1 then
          u.frame:ClearAllPoints()
          u.frame:SetPoint("TOPLEFT", u1.frame, "TOPLEFT", 0, -(i - 1) * PARTY_STRIDE)
        end
      end
    end })
end

-- Only the player's bar: the target bar always hangs under the target frame (Forever's AdjustPosition, CastBars.lua), so it
-- is not an Edit Mode system.
local function castbar()
  local b = AFUI.CastBars and AFUI.CastBars.player
  if not b then return end
  EM.Register("castbar_player", { frame = b.frame, label = "Cast Bar", group = "castbar", scaleLabel = "Bar Size", defaults = { scale = b.settings.scale, lockToPlayerFrame = b.settings.lockToPlayerFrame },
    settingsSchema = { { id = "lockToPlayerFrame", type = "checkbox", label = "Lock to Player Frame" } },
    apply = function(entry)
      local s = EM.current.systems.castbar_player
      b.ApplySettings({ scale = s.scale, lockToPlayerFrame = s.lockToPlayerFrame })
      -- locked: the player frame owns the position
      if s.lockToPlayerFrame then EM.Resolve("castbar_player", s) else EM.Place(entry) end
    end })
end

-- The gryphons are systems of their own (Forever's MainActionBarEndCap): movable, with one Hide setting.
local function endcap(key, side, label)
  local caps = AFUI.EndCaps
  local frame = caps and caps[side .. "Frame"]
  if not frame then return end
  EM.Register(key, { frame = frame, label = label, selection = END_CAP[side], scaleLabel = "Size",
    settingsSchema = { { id = "hidden", type = "checkbox", label = "Hidden" } }, defaults = { hidden = false },
    apply = function(entry)
      caps.SetHidden(side, EM.current.systems[key].hidden and true or false)
      EM.Place(entry)
    end })
end

-- A client frame the Edit Mode list of the recording names (Equipment Durability, Duration Bars, Raid Warnings): movable, no settings.
-- The client's own placement code (UIParent_ManageFramePositions) must leave it where the player put it.
local function blizz(key, label, name, group)
  local f = _G[name]
  if not f then return end
  f.ignoreFramePositionManager = true
  if _G.UIPARENT_MANAGED_FRAME_POSITIONS then _G.UIPARENT_MANAGED_FRAME_POSITIONS[name] = nil end
  EM.Register(key, { frame = f, label = label, noScale = true, group = group })
end

function EM.RegisterAll()
  bar("main", "Action Bar 1", true); bar("bottomleft", "Action Bar 2", true)
  bar("bottomright", "Action Bar 3", true); bar("right", "Action Bar 4", true); bar("right2", "Action Bar 5", true)
  bar("pet", "Pet Bar", false, "petbar"); bar("stance", "Stance Bar", false, "stancebar"); bar("possess", "Possess Bar", false, "possessbar")
  -- Two bars: the XP bar (always there) and the reputation bar above it (only while a faction is watched; its box is a placeholder
  -- otherwise). Each moves on its own; the second one's width follows the first until it has a Width of its own.
  for _, d in ipairs({ { "statusbar", AFUI.StatusBar, "Status Bar 1" }, { "statusbar2", AFUI.StatusBar2, "Status Bar 2", "statusbar2" } }) do
    local sbar = d[2]
    if sbar then
      EM.Register(d[1], { frame = sbar.frame, label = d[3], noScale = true, defaults = { width = 1 }, group = d[4],
        settingsSchema = { { id = "width", type = "slider", label = "Width", min = 0.5, max = 1, step = 0.05, percent = true } },
        apply = function(entry) EM.Place(entry); if sbar.Resize then sbar.Resize() end end })
    end
  end
  plain("micromenu", "Menu", AFUI.MicroMenu) -- the video's name for it
  if AFUI.HudTooltip then
    EM.Register("hudtooltip", { frame = AFUI.HudTooltip, label = "HUD Tooltip", noScale = true, group = "hudtooltip" })
  end
  if AFUI.BuffAnchor then
    EM.Register("buffs", { frame = AFUI.BuffAnchor, label = "Buffs and Debuffs", scaleLabel = "Icon Size", group = "buffs",
      apply = function(entry) EM.Place(entry) end })
  end
  if AFUI.Tracker then -- Forever's Objective Tracker: Size and Hidden (the column hangs from this box, Tracker.lua)
    EM.Register("tracker", { frame = AFUI.Tracker.frame, label = "Objective Tracker", defaults = { hidden = false },
      enabled = function() return not AFUI.Tracker.Inert() end, -- not listed while Questie's tracker is on
      settingsSchema = { { id = "hidden", type = "checkbox", label = "Hidden" } },
      apply = function(entry)
        AFUI.Tracker.SetHidden(EM.current.systems.tracker.hidden)
        EM.Place(entry)
      end })
  end
  local cf = _G.ChatFrame1
  if cf then -- Forever's Chat Frame: Width 349 / Height 215 in the video, in the bottom left corner
    EM.Register("chat", { frame = cf, label = "Chat Frame", noScale = true, defaults = { width = 349, height = 215 },
      settingsSchema = { { id = "width", type = "slider", label = "Width", min = 180, max = 600, step = 1 },
        { id = "height", type = "slider", label = "Height", min = 80, max = 400, step = 1 } },
      apply = function(entry)
        local s = EM.current.systems.chat
        AFUI.ChatManaged = true
        cf:SetWidth(s.width or 349); cf:SetHeight(s.height or 215)
        EM.Place(entry)
      end })
  end
  if AFUI.BagBar then -- Forever's Options > Combine Bags, kept per account by Bags.lua: the checkbox is a view of it
    local B = AFUI.Bags
    local MODES, MODE_KEYS = AFUI.BAG_BAR_MODES or {}, {}
    for k, label in pairs(MODES) do MODE_KEYS[label] = k end
    local function modeLabel() return MODES[AFUI.BagBarMode and AFUI.BagBarMode() or "full"] or "Full row" end
    EM.Register("bags", { frame = AFUI.BagBar, label = "Bags", settingsSchema = { { id = "combineBags", type = "checkbox", label = "Combine Bags" },
        { id = "barMode", type = "dropdown", label = "Bag Bar", options = { "Full row", "Single icon", "Hidden" } } },
      defaults = { combineBags = B and B.IsCombined() or false, barMode = "Full row" },
      apply = function(entry)
        -- Both are views of account settings: they read the setting back, except right after the player changed one here (change() applies first, then tells the
        -- watcher below, which writes the player's choice to the setting)
        if not (EM.dirtyKeys and EM.dirtyKeys.bags) then
          EM.current.systems.bags.combineBags = B and B.IsCombined() or false
          EM.current.systems.bags.barMode = modeLabel()
        end
        EM.Place(entry)
      end })
    EM.Watch(function(key, field)
      if key == "bags" and field == "combineBags" and B then B.SetCombined(EM.current.systems.bags.combineBags) end
      if key == "bags" and field == "barMode" and AFUI.SetBagBarMode then AFUI.SetBagBarMode(MODE_KEYS[EM.current.systems.bags.barMode]) end
    end)
    AFUI.OnSettingChanged("bagBarMode", function() -- changed in the Settings window: the open Edit Mode box follows
      local cur = EM.current and EM.current.systems and EM.current.systems.bags
      if cur then cur.barMode = modeLabel() end
    end)
  end
  endcap("endcap_left", "left", "End Cap (Left)"); endcap("endcap_right", "right", "End Cap (Right)")
  unit("player", "player", "Player Frame", BIG_UNIT); unit("target", "target", "Target Frame", BIG_UNIT, "targetfocus")
  unit("targettarget", "targettarget", "Target of Target", SMALL_UNIT, "targetfocus"); unit("pet_frame", "pet", "Pet Frame", SMALL_UNIT, "petframe")
  party()
  castbar()
  plain("minimap", "Minimap", AFUI.MinimapFrame)
  blizz("durability", "Equipment Durability", "DurabilityFrame", "durability")
  blizz("durationbars", "Duration Bars", "MirrorTimer1", "durationbars") -- breath / fatigue bars; the others hang under the first
  blizz("raidwarnings", "Raid Warnings", "RaidWarningFrame", "raidwarnings")
end

AFUI.RegisterModule("EditModeRegistry", { OnLogin = EM.RegisterAll })
