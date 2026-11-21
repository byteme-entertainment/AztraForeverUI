-- Forever world map window (docs/forever-ref/worldmap.md): the client's own map canvas inside Forever's Metal frame, windowed
-- (702 x 534 at the left panel position, portrait corner; the default) or maximized (fills the screen height, no portrait),
-- a 67 px title area with a centred gold title, a navbar-style strip holding the continent / zone dropdowns and Zoom Out,
-- the red 28x28 close and maximize / minimize buttons and a coordinates panel. The mode is kept in AztraForeverUICharDB.worldMapMaximized.
-- Neither client has a windowed map (2.5.3's Blizzard_WorldMap.lua has no Minimize / Maximize), so both modes scale the 1002 x 668
-- canvas with WorldMapFrame:SetScale; the chrome and the widgets get the inverse scale and keep their real pixel size. Nothing of Blizzard's is replaced: art is hidden, widgets are re-anchored
-- and re-skinned, clicks / zoom / quest and POI icons / dropdown menus stay the client's.
-- Frame names (verified against the 2.4.3 FrameXML mirror MOUZU/Blizzard-WoW-Interface 2.4.3/FrameXML/WorldMapFrame.xml and
-- Gethe/wow-ui-source tag 2.5.3 Interface_TBC/AddOns/Blizzard_WorldMap/Blizzard_WorldMap.xml):
--   both: WorldMapFrame (1024x768 layout), WorldMapContinentDropDown, WorldMapZoneDropDown, WorldMapZoneMinimapDropDown,
--         WorldMapZoomOutButton, WorldMapMagnifyingGlassButton, WorldMapFrameCloseButton
--   2.4.3: WorldMapPositioningGuide, WorldMapDetailFrame (1002x668 canvas), the old border = unnamed UI-WorldMap-* textures on WorldMapFrame
--   2.5.3: WorldMapFrame.ScrollContainer (canvas), WorldMapFrame.BorderFrame (holds the UI-WorldMap-* textures), BlackoutFrame
AFUI = AFUI or {}

local PLAIN = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\"
-- Real size of the plain files (they are padded to a square power of two for the 2.4.3 loader): the Rock fill was halved
-- from 1024, the navbar strip is 128 wide.
local ART = { ["UI-Background-Rock"] = { 512, 512 }, ["CS_HelpTextures_Tile"] = { 128, 512 } }

local TITLE, INSET_L, INSET_R, INSET_B = 67, 2, 3, 2 -- title area above the canvas, window margin around it
local NAV = { l = 10, lp = 66, t = 25, r = 53, h = 33 } -- navbar: x from the window's left (maximized, windowed with the portrait), y below its top, gap to its right end

-- Metal frame pieces for a window w x h (maximized layout, no portrait): every piece at texel size / 2, tiled edges in
-- 128 px units (atlas rectangles cannot tile). x / y are from the window's TOPLEFT (y negative downwards); crop < 1 cuts
-- the last unit of an edge. docs/forever-ref/worldmap.md §2.
function AFUI.WorldMapPieces(w, h, portrait)
  local out = {}
  local function add(atlas, x, y, pw, ph, crop) out[#out + 1] = { atlas = atlas, x = x, y = y, w = pw, h = ph, crop = crop } end
  local L, R, B = portrait and -13 or -12, w + 2 - 95, -(h + 8 - 100) -- corner x (left / right) and bottom-corner top y
  add(portrait and "ui-frame-portraitmetal-cornertopleft-c60-2x" or "ui-frame-metal-cornertopleft-c60-2x", L, 16, 95, 95)
  add("ui-frame-metal-cornertoprightdouble-c60-2x", R, 16, 95, 95)
  add("ui-frame-metal-cornerbottomleft-c60-2x", L, B, 95, 100)
  add("ui-frame-metal-cornerbottomright-c60-2x", R, B, 95, 100)
  local function row(atlas, y, ph)
    local x = L + 95
    while x < R do
      local len = math.min(128, R - x)
      add(atlas, x, y, len, ph, len < 128 and len / 128 or 1)
      x = x + len
    end
  end
  row("_ui-frame-metal-edgetop-c60-2x", 16, 95)
  row("_ui-frame-metal-edgebottom-c60-2x", B, 100)
  local function column(atlas, x)
    local y = 16 - 95
    while y > B do
      local len = math.min(128, y - B)
      add(atlas, x, y, 95, len, len < 128 and len / 128 or 1)
      y = y - len
    end
  end
  column("!ui-frame-metal-edgeleft-c60-2x", L)
  column("!ui-frame-metal-edgeright-c60-2x", R)
  return out
end

-- Forever's windowed map with its quest panel (docs/forever-ref/worldmap.md §1, checked against Mat's capture: canvas 697 x 465, panel 333 wide
-- flush against it, 3 px from the window's right edge): 1035 x 534 u, the same with the quest panel on or off. The panel is a 333 u column on the
-- window's right edge (QuestLog.lua); the breadcrumb stops 50 u (the tracking button's room) short of it. Hidden (frame 269 of the capture: the window keeps
-- its size, the map fills it) the 2.5.3 canvas is widened over the column: apply() widens the map frame, MapCoverLevels fits the client's zoom levels.
local WIN_W, WIN_H, PANEL_W = 1035, 534, 333

-- Window scale and position for a UIParent of uiw x uih: k = UI px per canvas unit (the canvas is 1002 x 668 units), x / y = the window's TOPLEFT,
-- extra = px the window is wider than its canvas (the map keeps its aspect; the rest is the column of the quest panel).
-- windowed: the left-panel anchor every Forever window shares (video 3: 24 / 160 px = 17 / 114 u from the top left), canvas 697 x 465 (smaller only on screens too small for it);
-- maximized: fills the screen height (16 px above for the corner pieces, 8 below), the same aspect, centred.
function AFUI.WorldMapGeometry(maximized, uiw, uih)
  if maximized then -- video 3 (f0177): the same frame without the portrait and the quest panel, full screen height, centred; the screen's black shows beside it
    local k = math.max(math.min((uih - TITLE - INSET_B) / 668, (uiw - INSET_L - INSET_R) / 1002), 0.3)
    local w, h = 1002 * k + INSET_L + INSET_R, 668 * k + TITLE + INSET_B
    return { k = k, x = math.max((uiw - w) / 2, 0), y = -math.max((uih - h) / 2, 0), extra = 0 }
  end
  local k = math.max(math.min((WIN_H - TITLE - INSET_B) / 668, (uih - 24 - TITLE - INSET_B) / 668), 0.3)
  local w = math.max(WIN_W, 1002 * k + INSET_L + INSET_R)
  local h = 668 * k + TITLE + INSET_B
  return { k = k, x = math.max(math.min(17, uiw - w), 0), y = -math.max(16, math.min(114, uih - h - 8)), extra = w - (1002 * k + INSET_L + INSET_R) }
end

-- The quest panel (QuestLog.lua) is shown by default; the choice is kept per character. QuestLog.lua replaces WorldMapPanelShow with the real show / hide.
function AFUI.WorldMapPanelOpen() return not (AztraForeverUICharDB and AztraForeverUICharDB.questPanelOpen == false) end
AFUI.WorldMapPanelHooks = {} -- QuestLog.lua and the toggle handle add their show / hide here
function AFUI.WorldMapPanelShow(on) for _, f in ipairs(AFUI.WorldMapPanelHooks) do f(on) end end
-- The panel is on screen: chosen and windowed (the maximized map has none).
function AFUI.WorldMapPanelVisible() return AFUI.WorldMapPanelOpen() and not (AztraForeverUICharDB and AztraForeverUICharDB.worldMapMaximized == true) end
AFUI.WORLDMAP = { PANEL_W = PANEL_W, TITLE = TITLE, NAV = NAV }

-- Cursor / player position as "45.2, 60.1" (percent of the map); unknown or off-map positions read "--".
function AFUI.MapCoordsText(x, y)
  if not x or not y or (x == 0 and y == 0) or x < 0 or x > 1 or y < 0 or y > 1 then return "--" end
  return string.format("%.1f, %.1f", x * 100, y * 100)
end

-- The plain "Player: 74.0, 45.5" line in the canvas' bottom-left corner.
function AFUI.PlayerCoordsText(px, py)
  if not px or not py or (px == 0 and py == 0) then return "Player: --" end
  return "Player: " .. string.format("%.1f, %.1f", px * 100, py * 100)
end

-- The navbar of the 2.5.3 map (Enum.UIMapType: Cosmic 0, World 1, Continent 2, Zone 3, anything deeper is a dungeon / micro map): World, Continent, Zone, from
-- the chain of parents of map `id`. `api` is C_Map (injectable for the spec). Crumb: { id, label, kind, menu (has a dropdown), current }.
local CRUMB_KIND = { [1] = "world", [2] = "continent", [3] = "zone" }
function AFUI.MapCrumbs(api, id)
  local chain, info, guard = {}, api.GetMapInfo(id), 0
  local cur = id
  while info and guard < 12 do
    guard = guard + 1
    if CRUMB_KIND[info.mapType] then table.insert(chain, 1, { id = cur, name = info.name, kind = CRUMB_KIND[info.mapType], parent = info.parentMapID }) end
    cur = info.parentMapID
    info = cur and api.GetMapInfo(cur)
  end
  local out = {}
  -- no World map above (Outland hangs off the Cosmic map): the World crumb goes to that parent, so it still navigates
  if #chain == 0 or chain[1].kind ~= "world" then
    local up = chain[1] and chain[1].parent
    out[1] = { id = up and up > 0 and up or nil, label = "World", kind = "world", menu = false }
  end
  for _, c in ipairs(chain) do
    out[#out + 1] = { id = c.id, label = c.kind == "world" and "World" or c.name, kind = c.kind, menu = c.kind ~= "world" }
  end
  for i, c in ipairs(out) do c.current = (i == #out) end
  return out
end

-- The dropdown of crumb `index`: every map of its kind under the crumb before it, by name; the crumb's own entry checked. World has none.
function AFUI.MapSiblings(api, crumbs, index)
  local c, parent = crumbs[index], crumbs[index - 1]
  if not c or not c.menu or not parent or not parent.id then return {} end
  local out = {}
  for _, m in ipairs(api.GetMapChildrenInfo(parent.id, c.kind == "continent" and 2 or 3, true) or {}) do
    out[#out + 1] = { id = m.mapID, name = m.name, checked = m.mapID == c.id }
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function atlasTexture(parent, layer, name, x, y, w, h, crop, vertical)
  local t = parent:CreateTexture(nil, layer)
  AFUI.SetAtlas(t, name)
  local e = AFUI_ATLAS and AFUI_ATLAS[string.lower(name)]
  if e and crop and crop < 1 then -- the shortened last unit of a tiled edge: keep the first `crop` of the texcoord range
    if vertical then t:SetTexCoord(e[4], e[5], e[6], e[6] + (e[7] - e[6]) * crop)
    else t:SetTexCoord(e[4], e[4] + (e[5] - e[4]) * crop, e[6], e[7]) end
  end
  t:SetWidth(w); t:SetHeight(h)
  return t
end

-- A frame border from one atlas cut into nine (the client slices art with a nine-slice margin; here the margin m is in the art's own pixels): corners at
-- natural size, edges stretched, the middle left empty. `layer` is the texture layer; returns the pieces.
function AFUI.NineSlice(frame, layer, name, m, inset)
  local e = AFUI_ATLAS and AFUI_ATLAS[string.lower(name)]
  if not e then return {} end
  inset = inset or 0
  local u0, u1, v0, v1 = e[4], e[5], e[6], e[7]
  local du, dv = (u1 - u0) * m / e[2], (v1 - v0) * m / e[3]
  local U, V = { u0, u0 + du, u1 - du, u1 }, { v0, v0 + dv, v1 - dv, v1 }
  local out = {}
  for row = 1, 3 do
    for col = 1, 3 do
      if not (row == 2 and col == 2) then
        local t = frame:CreateTexture(nil, layer)
        t:SetTexture(e[1]); t:SetTexCoord(U[col], U[col + 1], V[row], V[row + 1])
        local l, r, tp, bt = col == 1, col == 3, row == 1, row == 3
        if l then t:SetWidth(m) elseif r then t:SetWidth(m) end
        if tp then t:SetHeight(m) elseif bt then t:SetHeight(m) end
        if l and tp then t:SetPoint("TOPLEFT", frame, "TOPLEFT", -inset, inset)
        elseif r and tp then t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", inset, inset)
        elseif l and bt then t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -inset, -inset)
        elseif r and bt then t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", inset, -inset)
        elseif tp then t:SetPoint("TOPLEFT", frame, "TOPLEFT", m - inset, inset); t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -m + inset, inset)
        elseif bt then t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", m - inset, -inset); t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -m + inset, -inset)
        elseif l then t:SetPoint("TOPLEFT", frame, "TOPLEFT", -inset, -m + inset); t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -inset, m - inset)
        else t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", inset, -m + inset); t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", inset, m - inset) end
        out[#out + 1] = t
      end
    end
  end
  return out
end

-- The pieces are laid out in the window's TOPLEFT frame of reference; edges that tile along y are vertical.
local VERTICAL = { ["!ui-frame-metal-edgeleft-c60-2x"] = true, ["!ui-frame-metal-edgeright-c60-2x"] = true }

-- 2.4.3: unnamed regions of the old frame, found by the path of their art (GetTexture() answers the XML path) and the title text.
local function hideTextures(host)
  if not host or not host.GetRegions then return end
  for _, r in ipairs({ host:GetRegions() }) do
    if r.IsObjectType and r:IsObjectType("Texture") then
      local path = r:GetTexture()
      if type(path) == "string" and string.find(string.lower(path), "ui%-worldmap%-") then r:Hide() end
    elseif r.IsObjectType and r:IsObjectType("FontString") and r:GetText() == WORLD_MAP then r:Hide() end
  end
end

-- 2.5.3 (modern engine): GetTexture() answers a FileID number for XML art, so no path matches. Everything on BorderFrame (and the
-- pieces it holds: NineSlice, TitleContainer) is the old border and title, so every Texture and FontString region goes.
local function hideAllRegions(host)
  if not host or not host.GetRegions then return end
  for _, r in ipairs({ host:GetRegions() }) do
    if r.IsObjectType and (r:IsObjectType("Texture") or r:IsObjectType("FontString")) then r:Hide() end
  end
end
local function hideBorder(border)
  hideAllRegions(border)
  for _, k in ipairs({ "NineSlice", "TitleContainer" }) do
    local part = type(border[k]) == "table" and border[k] or nil
    hideAllRegions(part)
  end
  if type(border.TitleText) == "table" and border.TitleText.Hide then border.TitleText:Hide() end
end

-- Blizzard's own portrait art on the map frame. 2.5.3's WorldMapFrame has none (Blizzard_WorldMap.xml: no PortraitContainer), but a
-- PortraitFrameTemplate-style frame does, and sets it again from SetPortraitToAsset / SetPortraitToTexture / SetPortrait / OnShow: hide
-- every known key now and after each of those (hooksecurefunc only; nothing of Blizzard's is replaced). Windows overlay their own icon.
local PORTRAIT_KEYS = { "PortraitContainer", "portrait", "Portrait", "PortraitFrame" }
local PORTRAIT_SETTERS = { "SetPortraitToAsset", "SetPortraitToTexture", "SetPortraitTextureRaw", "SetPortrait" }
function AFUI.HidePortraitArt(frame)
  if not frame then return end
  local function hide()
    for _, host in ipairs({ frame, type(frame.BorderFrame) == "table" and frame.BorderFrame or false }) do
      if host then
        for _, k in ipairs(PORTRAIT_KEYS) do
          local p = host[k]
          if type(p) == "table" and p.Hide then
            p:Hide()
            if type(p.portrait) == "table" and p.portrait.Hide then p.portrait:Hide() end
          end
        end
      end
    end
    local n = frame.GetName and frame:GetName()
    local g = n and _G[n .. "Portrait"]
    if type(g) == "table" and g.Hide then g:Hide() end
  end
  hide()
  if frame.afPortraitHooked then return hide end
  frame.afPortraitHooked = true
  for _, fn in ipairs(PORTRAIT_SETTERS) do
    if type(frame[fn]) == "function" then hooksecurefunc(frame, fn, hide) end
  end
  if frame.HookScript then frame:HookScript("OnShow", hide) end
  return hide
end

-- Zoom of the client's canvas (MapCanvas_ScrollContainerMixin of 2.5.3: ZoomIn / ZoomOut step through scroll.zoomLevels, SetPanTarget,
-- IsAtMaxZoom / IsAtMinZoom; WorldMapFrame.xml switches the wheel off with a nop handler). Zoom levels come from the map's art layers; a map whose
-- layers give no range (the classic art) gets two extra steps of x1.5 on the same layer so the client's own pan / clip / pin scaling does the rest.
function AFUI.MapEnsureZoomLevels(scroll)
  local z = scroll and scroll.zoomLevels
  if type(z) ~= "table" or #z == 0 then return end
  if z[#z].scale < z[1].scale * 1.5 then
    for _ = 1, 2 do z[#z + 1] = { scale = z[#z].scale * 1.5, layerIndex = z[#z].layerIndex } end
  end
end
-- A canvas whose clip is wider (or taller) than the map's aspect: the client fits the base zoom to the SMALLER side (CreateZoomLevels: min(widthScale, heightScale)),
-- which leaves a bare strip beside the map. The quest panel's room is given to the canvas when the panel is hidden, so every zoom level is multiplied by the factor
-- that makes the map cover the clip (1 when the aspects agree, as with the panel shown). cw / ch = clip, lw / lh = the map art.
function AFUI.MapCoverFactor(cw, ch, lw, lh)
  if not (cw and ch and lw and lh) or cw <= 0 or ch <= 0 or lw <= 0 or lh <= 0 then return 1 end
  local a = (cw / ch) / (lw / lh)
  return math.max(a, 1 / a)
end
-- Called right after the client built its zoom levels (hooksecurefunc on CreateZoomLevels; ResetZoom follows it inside OnCanvasSizeChanged): once per level table.
-- refit = true re-measures a table already fitted (the clip was read before its resize settled) and answers whether the levels changed.
function AFUI.MapCoverLevels(scroll, refit)
  local z = scroll and scroll.zoomLevels
  if type(z) ~= "table" or #z == 0 or not scroll.GetWidth then return false end
  local fitted = scroll.afCovered == z
  if fitted and not refit then return false end
  local lw, lh
  local layers = _G.C_Map and C_Map.GetMapArtLayers and scroll.mapID and C_Map.GetMapArtLayers(scroll.mapID)
  if type(layers) == "table" and layers[1] then lw, lh = layers[1].layerWidth, layers[1].layerHeight
  elseif type(scroll.Child) == "table" then lw, lh = scroll.Child:GetWidth(), scroll.Child:GetHeight() end
  local f = AFUI.MapCoverFactor(scroll:GetWidth(), scroll:GetHeight(), lw, lh)
  if f <= 1.0001 then f = 1 end
  local r = f / (fitted and scroll.afCoverF or 1)
  scroll.afCovered, scroll.afCoverF = z, f
  if math.abs(r - 1) < 1e-6 then return false end
  for _, l in ipairs(z) do l.scale = l.scale * r end
  if scroll.baseScale then scroll.baseScale = scroll.baseScale * r end
  return true
end
-- The pan target is the CENTRE of the view in normalized canvas units. The client's own wheel handler clamps it to the scroll extents at the zoom step
-- it is going to (CalculateScrollExtentsAtScale); an unclamped target (a cursor near the map's edge) lets the scroll frame, which does not clamp its offset,
-- slide the canvas off its clip area for as long as the interpolation runs.
function AFUI.MapPanTarget(scroll, cx, cy)
  if type(scroll.GetCurrentZoomRange) == "function" and type(scroll.CalculateScrollExtentsAtScale) == "function" then
    local _, nextIn = scroll:GetCurrentZoomRange()
    local x0, x1, y0, y1
    if nextIn then x0, x1, y0, y1 = scroll:CalculateScrollExtentsAtScale(nextIn) end
    if y1 then
      cx = x0 <= x1 and math.max(x0, math.min(x1, cx)) or 0.5
      cy = y0 <= y1 and math.max(y0, math.min(y1, cy)) or 0.5
    end
  end
  return cx, cy
end
-- dir > 0 in towards the normalized cursor position cx, cy (the centre of the visible area when nil: the + button), dir < 0 out (the client re-centres);
-- false when the canvas cannot zoom. Like the client's handler it leaves the pan target alone while a zoom in is already running or at the limit.
function AFUI.MapZoom(scroll, dir, cx, cy)
  if not scroll or type(scroll.ZoomIn) ~= "function" or type(scroll.ZoomOut) ~= "function" then return false end
  AFUI.MapEnsureZoomLevels(scroll)
  if dir > 0 then
    local busy = (type(scroll.IsAtMaxZoom) == "function" and scroll:IsAtMaxZoom()) or (type(scroll.IsZoomingIn) == "function" and scroll:IsZoomingIn())
    if not busy then
      if not (cx and cy) and type(scroll.GetCurrentScrollX) == "function" then cx, cy = scroll:GetCurrentScrollX(), scroll:GetCurrentScrollY() end
      if cx and cy and type(scroll.SetPanTarget) == "function" then scroll:SetPanTarget(AFUI.MapPanTarget(scroll, cx, cy)) end
    end
    scroll:ZoomIn()
  else
    scroll:ZoomOut()
  end
  return true
end
-- While the canvas animates (zoom out shrinks the scale faster than the pan arrives) the view may leave the scroll extents of the current scale: put it back,
-- every frame the client moves it. Idle (scale and scroll at their targets) costs one comparison.
function AFUI.MapClampView(scroll)
  if type(scroll.CalculateScrollExtentsAtScale) ~= "function" or type(scroll.GetNormalizedHorizontalScroll) ~= "function" then return end
  if scroll.currentScale and scroll.currentScale == scroll.targetScale and scroll.currentScrollX == scroll.targetScrollX and scroll.currentScrollY == scroll.targetScrollY then return end
  local x0, x1, y0, y1 = scroll:CalculateScrollExtentsAtScale(scroll:GetCanvasScale())
  if x0 <= x1 then
    local v = scroll:GetNormalizedHorizontalScroll()
    local c = math.max(x0, math.min(x1, v))
    if math.abs(c - v) > 1e-7 then scroll:SetNormalizedHorizontalScroll(c); if scroll.currentScrollX then scroll.currentScrollX = c end end
  end
  if y0 <= y1 then
    local v = scroll:GetNormalizedVerticalScroll()
    local c = math.max(y0, math.min(y1, v))
    if math.abs(c - v) > 1e-7 then scroll:SetNormalizedVerticalScroll(c); if scroll.currentScrollY then scroll.currentScrollY = c end end
  end
end
-- The audit's check: the canvas must cover the clip area (a canvas smaller than the clip at minimum zoom is the client's letterbox, not a fault).
function AFUI.MapCoverProblem(scroll)
  if not (scroll and scroll.Child and scroll.GetHorizontalScroll and scroll.GetCanvasScale) then return end
  local sc, cw, ch, w, h = scroll:GetCanvasScale(), scroll.Child:GetWidth(), scroll.Child:GetHeight(), scroll:GetWidth(), scroll:GetHeight()
  local hs, vs, tol = scroll:GetHorizontalScroll(), scroll:GetVerticalScroll(), 2 / sc
  if cw * sc >= w - 2 and (hs < -tol or hs + w / sc > cw + tol) then return "map canvas does not cover the clip area (x offset " .. hs .. ", scale " .. sc .. ")" end
  if ch * sc >= h - 2 and (vs < -tol or vs + h / sc > ch + tol) then return "map canvas does not cover the clip area (y offset " .. vs .. ", scale " .. sc .. ")" end
end

-- Cursor on the canvas. The client's MapCanvasScrollControllerMixin:GetCursorPosition answers GetCursorPosition() / UIParent:GetEffectiveScale(), and
-- NormalizeUIPosition subtracts Child:GetLeft() / :GetTop() from it, which are in the map frame's own units: right only while the map frame's effective scale
-- is UIParent's. We scale the map frame (k), so the cursor was read in the wrong units and zone hover / click landed off the cursor (offset by the scale ratio,
-- growing with the distance from the screen's bottom-left corner). The cursor is read in the scroll container's own units instead.
function AFUI.MapCursorUnits(scroll, px, py)
  local s = scroll:GetEffectiveScale()
  if not s or s <= 0 then s = 1 end
  return px / s, py / s
end
function AFUI.MapInstallCursor(scroll)
  if type(scroll) ~= "table" or type(scroll.NormalizeUIPosition) ~= "function" then return false end
  scroll.GetCursorPosition = function(self) return AFUI.MapCursorUnits(self, GetCursorPosition()) end
  return true
end
-- The audit's check: the point at the centre of the clip area, through the client's own NormalizeUIPosition, against the geometry of where the canvas is drawn.
function AFUI.MapCursorProblem(scroll)
  if not (scroll and scroll.Child and scroll.NormalizeUIPosition and scroll.GetLeft and scroll.Child.GetLeft) then return end
  local es, ec = scroll:GetEffectiveScale(), scroll.Child:GetEffectiveScale()
  local l, b, w, h = scroll:GetLeft(), scroll:GetBottom(), scroll:GetWidth(), scroll:GetHeight()
  if not (l and b and w and h and es and ec and scroll.Child:GetLeft() and scroll.Child:GetTop()) then return end
  local px, py = (l + w / 2) * es, (b + h / 2) * es -- the clip's centre in screen pixels
  local real = _G.GetCursorPosition
  _G.GetCursorPosition = function() return px, py end -- the mouse is "at" that point for the client's own GetCursorPosition / NormalizeUIPosition
  local ok, nx, ny = pcall(function() return scroll:NormalizeUIPosition(scroll:GetCursorPosition()) end)
  _G.GetCursorPosition = real
  if not ok then return "cursor conversion failed: " .. tostring(nx) end
  local ex = (px - scroll.Child:GetLeft() * ec) / (scroll.Child:GetWidth() * ec)
  local ey = (scroll.Child:GetTop() * ec - py) / (scroll.Child:GetHeight() * ec)
  ex, ey = math.max(0, math.min(1, ex)), math.max(0, math.min(1, ey))
  if math.abs(nx - ex) > 0.01 or math.abs(ny - ey) > 0.01 then
    return string.format("cursor at the canvas centre reads %.3f, %.3f (the canvas is drawn at %.3f, %.3f)", nx, ny, ex, ey)
  end
end

-- The audit's panel check (the open 2.5.3 map): the quest panel agrees with the saved choice and the maximized map has none; panel hidden -> nothing of it is visible,
-- the canvas reaches the window's right margin and its map covers the clip at minimum zoom (no bare strip); panel shown -> it sits flush against the canvas.
function AFUI.MapPanelProblem()
  local wm, win, panel = _G.WorldMapFrame, AFUI.WorldMapWindow, _G.AFUI_QuestPanel
  local scroll = wm and wm.ScrollContainer
  if not (wm and wm.IsShown and wm:IsShown() and win and panel and scroll and type(scroll.Child) == "table" and scroll.GetRight and not _G.WorldMapDetailFrame) then return end
  local maxd = AztraForeverUICharDB ~= nil and AztraForeverUICharDB.worldMapMaximized == true
  local want = not maxd and AFUI.WorldMapPanelOpen()
  if (panel:IsShown() and true or false) ~= want then return "quest panel is " .. (panel:IsShown() and "shown" or "hidden") .. " but should be " .. (want and "shown" or "hidden") end
  if maxd then return end
  local function px(f, a) local v, s = f[a](f), f:GetEffectiveScale(); return v and s and v * s end
  local sr, wr, pl = px(scroll, "GetRight"), px(win, "GetRight"), px(panel, "GetLeft")
  if not (sr and wr) then return end
  if want then
    if pl and math.abs(pl - sr) > 2 then return string.format("quest panel is %.1f px from the canvas (should be flush)", pl - sr) end
  else
    if panel.IsVisible and panel:IsVisible() then return "quest panel region visible while the panel is hidden" end
    local inset = (AFUI.WorldMapCanvasRightInset and AFUI.WorldMapCanvasRightInset() or 0) * win:GetEffectiveScale() -- the window's units -> screen px
    if math.abs((wr - sr) - inset) > 2 then return string.format("canvas stops %.1f px short of the window's right margin (panel hidden)", (wr - sr) - inset) end
    if scroll.GetScaleForMinZoom and scroll.GetWidth then
      local m = scroll:GetScaleForMinZoom()
      if m and (scroll.Child:GetWidth() * m < scroll:GetWidth() - 1 or scroll.Child:GetHeight() * m < scroll:GetHeight() - 1) then return "map does not fill the canvas at minimum zoom (panel hidden)" end
    end
  end
end

-- Every map change we start (breadcrumb, dropdown, audit) goes through the client's own SetMapID, once: nothing for a missing id or the map that is
-- already shown (so a crumb clicked twice, or the current crumb, cannot restart the canvas), and a failing call leaves the error in AFUI.MapNavError.
function AFUI.MapNavigate(wm, id)
  AFUI.MapNavError = nil
  if type(id) ~= "number" or id <= 0 or not wm or type(wm.SetMapID) ~= "function" then return false end
  if type(wm.GetMapID) == "function" and wm:GetMapID() == id then return false end
  local ok, err = pcall(wm.SetMapID, wm, id)
  if not ok then AFUI.MapNavError = tostring(err) end
  return ok
end
-- A new map starts at the base zoom, centred (the client's own SetMapID does this through the canvas' ResetZoom; kept for the paths that skip it).
function AFUI.MapResetView(scroll)
  if scroll and type(scroll.ResetZoom) == "function" and type(scroll.zoomLevels) == "table" and #scroll.zoomLevels > 0 then pcall(scroll.ResetZoom, scroll) end
end
AFUI.MapChangedHooks = AFUI.MapChangedHooks or {} -- function(mapID) after every map change (the quest panel follows the zone)

-- The audit's navigation step (/afui audit): a child map and back through the same code as the breadcrumb. Returns the map ids seen and what went wrong:
-- { ids = { start, [parent,] child, parent, start }, problems = { text } }.
function AFUI.MapNavAudit()
  local wm, out = _G.WorldMapFrame, { ids = {}, problems = {} }
  local function bad(t) out.problems[#out.problems + 1] = t end
  local api = _G.C_Map
  if not (wm and wm.GetMapID and api and api.GetMapInfo and api.GetMapChildrenInfo and wm.SetMapID) then bad("no map API"); return out end
  local scroll = wm.ScrollContainer
  local function go(id, what)
    local ok, res = pcall(AFUI.MapNavigate, wm, id)
    local err = (not ok and res) or AFUI.MapNavError
    if err then bad(what .. ": Lua error " .. tostring(err)); return end
    local now = wm:GetMapID()
    out.ids[#out.ids + 1] = now
    if now ~= id then bad(what .. ": map is " .. tostring(now) .. ", expected " .. tostring(id)) end
    local crumbs = AFUI.MapCrumbsShown
    local last = crumbs and crumbs[#crumbs]
    if last and last.id ~= nil and last.id ~= now then bad(what .. ": breadcrumb shows map " .. tostring(last.id)) end
    if scroll and scroll.zoomLevels and scroll.targetScale and scroll.targetScale ~= scroll.zoomLevels[1].scale then bad(what .. ": zoom was not reset (" .. tostring(scroll.targetScale) .. ")") end
  end
  local start = wm:GetMapID()
  if not start then bad("no map chosen yet"); return out end
  out.ids[1] = start
  if scroll and AFUI.MapZoom then pcall(AFUI.MapZoom, scroll, 1) end -- zoomed in, to prove the new map starts at the base zoom
  local kids = api.GetMapChildrenInfo(start, 3, true)
  local target = kids and kids[1] and kids[1].mapID
  if not target then -- a zone: up to its parent and back down
    local info = api.GetMapInfo(start)
    local parent = info and info.parentMapID
    if not (parent and parent > 0) then bad("map " .. start .. " has neither children nor a parent"); return out end
    go(parent, "up to parent")
    target = start
  end
  go(target, "into child")
  local info = api.GetMapInfo(target)
  go(info and info.parentMapID, "back up")
  go(start, "back to start")
  return out
end

-- WowStyle1 dropdown look on top of Blizzard's UIDropDownMenu: its Left/Middle/Right art is hidden, a stretched
-- common-dropdown-textholder body and the common-dropdown-a-button arrow replace it; the menu itself is untouched.
local function skinDropDown(dd)
  if not dd then return end
  local n = dd:GetName()
  for _, k in ipairs({ "Left", "Middle", "Right" }) do local t = _G[n .. k]; if t then t:Hide() end end
  for _, r in ipairs({ dd:GetRegions() }) do -- the CONTINENT / ZONE captions above the 2.4.3 dropdowns
    if r.IsObjectType and r:IsObjectType("FontString") and r ~= _G[n .. "Text"] then r:Hide() end
  end
  local body = dd:CreateTexture(nil, "BACKGROUND")
  AFUI.SetAtlas(body, "common-dropdown-textholder")
  body:SetPoint("TOPLEFT", dd, "TOPLEFT", 8, 5); body:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", -8, -1)
  local button = _G[n .. "Button"]
  if button then
    AFUI.SetButtonAtlas(button, { "common-dropdown-a-button", "common-dropdown-a-button-pressed", "common-dropdown-a-button-hover",
      "common-dropdown-a-button-disabled" }, 0.6)
    button:SetWidth(27); button:SetHeight(27)
  end
end

local function setup()
  if AFUI.WorldMapWindow or not WorldMapFrame then return end
  local wm = WorldMapFrame
  local function child(k) local v = wm[k]; return type(v) == "table" and v or nil end -- parentKey children (2.5.3 only)
  local canvas, border, scroll = WorldMapDetailFrame, nil, nil -- 2.4.3 has the named detail frame
  if not canvas then border, scroll = child("BorderFrame"), child("ScrollContainer"); canvas = scroll end
  if not canvas then return end
  local base = wm:GetFrameLevel()

  -- Blizzard's old fullscreen border and title (unnamed regions; the 2.5.3 ones live on BorderFrame).
  if border then
    hideBorder(border)
    hideTextures(wm)
    -- the title is set again whenever the map changes (WorldMapFrame:SetTitle / PortraitFrameTemplate SetTitle): hide it again
    for _, host in ipairs({ border, wm }) do
      if type(host.SetTitle) == "function" then hooksecurefunc(host, "SetTitle", function() hideBorder(border) end) end
    end
  else
    hideTextures(wm)
  end
  AFUI.HidePortraitArt(wm)

  -- Everything that is Forever's chrome (not the client's map) is drawn at real pixel size: frames in `scaled` get 1 / k, k being how much
  -- the map frame is scaled. Regions follow their frame's scale, so no region of the map frame itself is ever used for chrome.
  local scaled = {}
  -- The window: the canvas plus Forever's title area above and thin margins around.
  local win = CreateFrame("Frame", "AFUI_WorldMapWindow", wm)
  win:SetPoint("TOPLEFT", canvas, "TOPLEFT", -INSET_L, TITLE)
  win:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", INSET_R, -INSET_B)
  win:SetFrameLevel(base + 20)
  AFUI.WorldMapWindow = win
  scaled[#scaled + 1] = win

  -- Behind the canvas: the Rock fill. It sits on a child frame of its own, at the map's level: on 2.4.3 a BACKGROUND region of the map
  -- frame would be drawn under the client's own black / positioning layers. Tiled like Forever's Bg (tiled both ways), at the file's own
  -- size: SetHorizTile / SetVertTile where the client has them, otherwise the texture coordinates repeat it (the file is a power of two).
  local rockFrame = CreateFrame("Frame", "AFUI_WorldMapRock", wm)
  rockFrame:SetFrameLevel(base)
  rockFrame:SetPoint("TOPLEFT", win, "TOPLEFT", 2, -21); rockFrame:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -2, 2)
  scaled[#scaled + 1] = rockFrame
  local rock = rockFrame:CreateTexture(nil, "BACKGROUND")
  rock:SetTexture(PLAIN .. "UI-Background-Rock")
  rock:SetAllPoints(rockFrame)
  local tiled = type(rock.SetHorizTile) == "function" and type(rock.SetVertTile) == "function"
  if tiled then rock:SetHorizTile(true); rock:SetVertTile(true) end

  -- The navbar strip (anchors set per mode), with inset rules left and right.
  local nav = CreateFrame("Frame", "AFUI_WorldMapNavBar", wm)
  nav:SetFrameLevel(base)
  scaled[#scaled + 1] = nav
  local navArt = {} -- the strip's art: hidden when maximized (the breadcrumb floats over the map)
  local strip = nav:CreateTexture(nil, "BACKGROUND")
  navArt[#navArt + 1] = strip
  local tile = ART.CS_HelpTextures_Tile
  strip:SetTexture(PLAIN .. "CS_HelpTextures_Tile")
  strip:SetTexCoord(0, tile[1] / 512, 0.1875, 0.2539)
  strip:SetAllPoints(nav)
  local sheen = nav:CreateTexture(nil, "BORDER")
  sheen:SetTexture(PLAIN .. "CS_HelpTextures_Tile")
  sheen:SetTexCoord(0, tile[1] / 512, 0.2578, 0.3242)
  sheen:SetAllPoints(nav)
  navArt[#navArt + 1] = sheen
  local function inset(name, point, x0, y0, iw, ih, tilesV, crop)
    local t = atlasTexture(nav, "ARTWORK", name, 0, 0, iw, ih, crop, tilesV)
    t:SetPoint(point, nav, point, x0, y0)
    navArt[#navArt + 1] = t
    return t
  end
  inset("!ui-frame-innerlefttile", "TOPLEFT", -3, 0, 3, NAV.h, true, NAV.h / 256)
  inset("!ui-frame-innerrighttile", "TOPRIGHT", 3, 0, 3, NAV.h, true, NAV.h / 256)
  inset("ui-frame-innerbotleftcorner", "BOTTOMLEFT", -3, -3, 6, 6)
  inset("ui-frame-innerbotright", "BOTTOMRIGHT", 3, -3, 6, 6)

  -- The chrome that depends on the window size (one set per mode and size, the others hidden): the dark rule under the title area, the
  -- navbar's bottom rule and the Metal frame over the canvas edge (the metal strips are 7 px wide, 4 px of them overlap the map like Forever's).
  local chromes = {}
  local function chrome(key, w, h, portrait)
    if chromes[key] then return chromes[key] end
    local c = CreateFrame("Frame", nil, win)
    c:SetFrameLevel(base + 20)
    c:SetPoint("TOPLEFT", win, "TOPLEFT"); c:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT")
    local x = 2
    while x < w - 2 do -- _UI-Frame-InnerTopTile, 256 x 3, under the title area (3 px above the canvas)
      local len = math.min(256, w - 2 - x)
      atlasTexture(c, "BORDER", "_ui-frame-innertoptile", 0, 0, len, 3, len / 256):SetPoint("TOPLEFT", c, "TOPLEFT", x, -(TITLE - 3))
      x = x + len
    end
    local rule = atlasTexture(c, "ARTWORK", "_ui-frame-innerbottile", 0, 0, 1, 3) -- stretched along the navbar: the breadcrumb is shorter while the quest panel is open
    rule:SetPoint("TOPLEFT", nav, "BOTTOMLEFT", 0, 0); rule:SetPoint("TOPRIGHT", nav, "BOTTOMRIGHT", 0, 0)
    for _, p in ipairs(AFUI.WorldMapPieces(w, h, portrait)) do
      atlasTexture(c, "OVERLAY", p.atlas, p.x, p.y, p.w, p.h, p.crop, VERTICAL[p.atlas]):SetPoint("TOPLEFT", c, "TOPLEFT", p.x, p.y)
    end
    chromes[key] = c
    return c
  end
  -- windowed only: the book portrait inside the corner's ring (the ring is part of the corner piece, drawn over it)
  local winOnly = {} -- widgets of the windowed layout only (tracking button, its badge)
  local panelOnly = {} -- the quest panel's handle and the drag strip: windowed only
  local portrait = win:CreateTexture(nil, "ARTWORK")
  portrait:SetTexture("Interface\\Icons\\INV_Misc_Book_09") -- Forever's medallion is a silver-blue book (f0162), not a map
  portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  portrait:SetWidth(62); portrait:SetHeight(62); portrait:SetPoint("TOPLEFT", win, "TOPLEFT", -5, 7)
  AFUI.WindowPortrait(win, portrait)
  local labels = CreateFrame("Frame", nil, win) -- above the metal frame pieces (frames draw over their parent's regions)
  labels:SetAllPoints(win); labels:SetFrameLevel(base + 25)
  AFUI.WorldMapLabels = labels
  local title = labels:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetText("Map & Quest Log")
  -- maximized only: the thin dark row over the map that carries the title, the breadcrumb and the buttons (36 px, the window's top edge)

  -- Title-area widgets, re-anchored on the navbar. The 2.4.3 captions are gone, so the dropdowns sit flush in the strip.
  -- 2.5.3: the client has no continent / zone dropdowns, so the breadcrumb (World, Continent v, Zone v) is built here from C_Map's hierarchy and
  -- WorldMapFrame:SetMapID; 2.4.3 keeps the client's dropdowns, re-skinned.
  local useCrumbs = type(_G.C_Map) == "table" and type(C_Map.GetMapInfo) == "function" and type(C_Map.GetMapChildrenInfo) == "function" and type(wm.SetMapID) == "function"
  local cont, zone = _G.WorldMapContinentDropDown, _G.WorldMapZoneDropDown
  local zoomOut = _G.WorldMapZoomOutButton
  if useCrumbs then
    for _, f in ipairs({ cont, zone, zoomOut, _G.WorldMapZoneMinimapDropDown }) do
      if f then f:SetAlpha(0); f:EnableMouse(false) end
    end
    cont, zone, zoomOut = nil, nil, nil
  end
  if zoomOut then
    local K = AFUI.WinKit
    if K then K.button(zoomOut, 60) end
    zoomOut:SetText("World")
    zoomOut:ClearAllPoints(); zoomOut:SetPoint("LEFT", nav, "LEFT", 4, 0); scaled[#scaled + 1] = zoomOut
  end
  if cont then cont:ClearAllPoints(); cont:SetPoint("LEFT", zoomOut or nav, zoomOut and "RIGHT" or "LEFT", zoomOut and -12 or -8, -1); skinDropDown(cont); scaled[#scaled + 1] = cont end
  if zone and cont then zone:ClearAllPoints(); zone:SetPoint("LEFT", cont, "RIGHT", -24, 0); skinDropDown(zone); scaled[#scaled + 1] = zone end
  -- 2.4.3: the old zoom-out magnifying glass hangs off the positioning guide, outside the re-laid-out window; it goes in a corner of the canvas.
  -- the old "click to zoom out" hint of both clients: Forever's breadcrumb replaces it
  local glass = _G.WorldMapMagnifyingGlassButton
  if glass then glass:SetAlpha(0); glass:EnableMouse(false); glass:ClearAllPoints(); glass:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8, -8) end
  local bgMini = _G.WorldMapZoneMinimapDropDown
  if bgMini and (zoomOut or zone) then
    bgMini:ClearAllPoints(); bgMini:SetPoint("LEFT", zone or zoomOut, "RIGHT", -6, -1); scaled[#scaled + 1] = bgMini
  end

  -- The breadcrumb (docs/forever-ref/worldmap.md §3, NavButtonTemplate of navigationbar.xml): the red Home button is a slice of CS_HelpTextures, the
  -- others the tiled dark button + the 21 px chevron tip, the current one with the red glow; Continent and Zone carry the gold arrow of their dropdown.
  local updateCrumbs
  local crumbBtns = {}
  if useCrumbs then
    local CS = PLAIN .. "CS_HelpTextures"
    local function cs(t, l, r, top, bottom) t:SetTexture(CS); t:SetTexCoord(l, r, top * 0.25, bottom * 0.25) end -- the file is 512 x 128, padded to 512 x 512
    local shown = {}
    local function newCrumb(i)
      local b = CreateFrame("Button", nil, nav)
      b:SetHeight(30)
      b.bg = b:CreateTexture(nil, "BACKGROUND")
      b.tip = b:CreateTexture(nil, "ARTWORK"); b.tip:SetWidth(21); b.tip:SetHeight(30); b.tip:SetPoint("LEFT", b, "RIGHT", 0, 0)
      cs(b.tip, 0.88867188, 0.92968750, 0.29687500, 0.53125000)
      b.sel = b:CreateTexture(nil, "ARTWORK"); b.sel:SetAllPoints(b); cs(b.sel, 0.00195313, 0.25195313, 0.375, 0.640625); b.sel:Hide()
      b.shadow = b:CreateTexture(nil, "OVERLAY"); b.shadow:SetTexture(PLAIN .. "ShadowOverlay-Left"); b.shadow:SetTexCoord(0, 1, 0, 8 / 64)
      b.shadow:SetWidth(30); b.shadow:SetHeight(30); b.shadow:SetPoint("LEFT", b, "LEFT", 0, 0); b.shadow:Hide()
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.text:SetJustifyH("LEFT")
      b:SetHighlightTexture(CS, "ADD")
      local ht = b:GetHighlightTexture()
      if ht then ht:SetTexCoord(0.00195313, 0.25195313, 0.65625 * 0.25, 0.92187500 * 0.25) end
      b.arrow = CreateFrame("Button", nil, b)
      b.arrow:SetWidth(22); b.arrow:SetHeight(30); b.arrow:SetPoint("RIGHT", b, "RIGHT", -2, 0)
      b.arrow.tex = b.arrow:CreateTexture(nil, "OVERLAY"); b.arrow.tex:SetWidth(12); b.arrow.tex:SetHeight(7); b.arrow.tex:SetPoint("CENTER", b.arrow, "CENTER", 0, -1)
      b.arrow.tex:SetTexture(CS) -- the gold right arrow turned down
      local u0, u1, v0, v1 = 0.67773438, 0.69335938, 0.7578125 * 0.25, 0.859375 * 0.25
      b.arrow.tex:SetTexCoord(u0, v1, u1, v1, u0, v0, u1, v0)
      b.arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
      b.arrow:SetScript("OnClick", function(self)
        local c = b.crumb
        if not (c and AFUI.EditModeWidgets) then return end
        local items = {}
        for _, m in ipairs(AFUI.MapSiblings(C_Map, shown, b.index)) do
          items[#items + 1] = { text = m.name, checked = m.checked, func = function() AFUI.MapNavigate(wm, m.id) end }
        end
        if #items > 0 then AFUI.EditModeWidgets.OpenMenu(b, items, 120) end
      end)
      b:SetScript("OnClick", function() local c = b.crumb; if c and c.id and not c.current then AFUI.MapNavigate(wm, c.id) end end)
      b.index = i
      crumbBtns[i] = b
      return b
    end
    local last
    updateCrumbs = function()
      local id = wm.GetMapID and wm:GetMapID()
      if not id or id == last then return end
      last = id
      shown = AFUI.MapCrumbs(C_Map, id)
      AFUI.MapCrumbsShown = shown
      local prev
      for i, c in ipairs(shown) do
        local b = crumbBtns[i] or newCrumb(i)
        b.crumb, b.index = c, i
        b:SetFrameLevel(base + 4 + (#shown - i))
        b.text:SetText(c.label)
        local tw = b.text:GetStringWidth() or 60
        b.text:ClearAllPoints()
        b.arrow:SetFrameLevel(b:GetFrameLevel() + 2)
        if i == 1 then -- Home: red, 128 wide at most (texcoords cut to the width)
          local w = math.min(128, tw + 50)
          b:SetWidth(w)
          b.bg:SetTexture(CS); b.bg:SetAllPoints(b)
          b.bg:SetTexCoord(0.703125 - (w / 128) * 0.25, 0.703125, 0.0078125 * 0.25, 0.2421875 * 0.25)
          b.bg:ClearAllPoints(); b.bg:SetAllPoints(b)
          b.tip:Hide(); b.shadow:Show(); b.sel:Hide()
          b.text:SetPoint("LEFT", b, "LEFT", 10, 0); b.text:SetPoint("RIGHT", b, "RIGHT", -30, 0)
          b.arrow:Hide()
        else
          b:SetWidth(tw + 20 + (c.menu and 24 or 10))
          b.bg:SetTexture(PLAIN .. "CS_HelpTextures_Tile"); b.bg:SetTexCoord(0, ART.CS_HelpTextures_Tile[1] / 512, 0.0625, 0.12109375)
          b.bg:ClearAllPoints(); b.bg:SetAllPoints(b)
          b.tip:Show(); b.shadow:Hide()
          if c.current then b.sel:Show() else b.sel:Hide() end
          b.text:SetPoint("LEFT", b, "LEFT", 20, 0)
          if c.menu then b.arrow:Show() else b.arrow:Hide() end
        end
        b:ClearAllPoints()
        if prev then b:SetPoint("LEFT", prev, "RIGHT", prev.crumb.kind == "world" and -15 or 6, 0) else b:SetPoint("LEFT", nav, "LEFT", 0, 0) end
        b:Show()
        prev = b
      end
      for i = #shown + 1, #crumbBtns do crumbBtns[i]:Hide() end
    end
  end

  -- The tracking options button (docs/forever-ref/worldmap.md §4: LEFT of the navbar's RIGHT +10, -2, the WowStyle1 arrow art) with Forever's red x
  -- badge; the badge clears the quest panel's search. Only when the client has the button.
  local track = _G.WorldMapTrackingOptionsButton
  if not track and type(wm.overlayFrames) == "table" then
    for _, f in ipairs(wm.overlayFrames) do
      local n = type(f) == "table" and f.GetName and f:GetName()
      if n and string.find(n, "TrackingOptions") then track = f; break end
    end
  end
  if track and track.SetPoint then
    track:ClearAllPoints(); track:SetPoint("LEFT", nav, "RIGHT", 10, -2); track:SetWidth(32); track:SetHeight(32)
    track:SetFrameLevel(base + 6)
    for _, r in ipairs({ track:GetRegions() }) do if r.Hide then r:Hide() end end
    for _, k in ipairs({ "Icon", "Background", "Border", "IconOverlay", "Button" }) do local t = track[k]; if type(t) == "table" and t.Hide then t:Hide() end end
    local art = track:CreateTexture(nil, "OVERLAY"); AFUI.SetAtlas(art, "common-dropdown-a-button", true); art:SetPoint("TOPLEFT", track, "TOPLEFT", 4, -6)
    AFUI.SetButtonAtlas(track, { nil, nil, "common-dropdown-a-button" }, 0.4)
    scaled[#scaled + 1] = track; winOnly[#winOnly + 1] = track
    local x = CreateFrame("Button", "AFUI_WorldMapClearFilters", wm)
    x:SetWidth(16); x:SetHeight(16); x:SetFrameLevel(base + 8); x:SetPoint("CENTER", track, "TOPRIGHT", -2, -4)
    AFUI.SetButtonAtlas(x, { "auctionhouse-ui-filter-redx", "auctionhouse-ui-filter-redx", "auctionhouse-ui-filter-redx" }, 0.4)
    x:SetScript("OnClick", function() if AFUI.QuestLog and AFUI.QuestLog.ClearSearch then AFUI.QuestLog.ClearSearch() end end)
    x:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Clear the quest search", 1, 1, 1); GameTooltip:Show() end)
    x:SetScript("OnLeave", function() GameTooltip:Hide() end)
    scaled[#scaled + 1] = x; winOnly[#winOnly + 1] = x
  end

  -- Red close button, 28x28 on the corner piece, and Forever's maximize (windowed) / minimize (maximized) button 1 px to its left.
  local expand, condense
  local close = _G.WorldMapFrameCloseButton
  if close then
    close:ClearAllPoints(); close:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 3)
    close:SetWidth(28); close:SetHeight(28); close:SetFrameLevel(base + 30)
    AFUI.SetButtonAtlas(close, { "redbutton-exit", "redbutton-exit-pressed", "redbutton-highlight", "redbutton-exit-disabled" })
    scaled[#scaled + 1] = close
    local function redButton(name, kind)
      local b = CreateFrame("Button", name, wm)
      b:SetWidth(28); b:SetHeight(28); b:SetFrameLevel(base + 30)
      b:SetPoint("RIGHT", close, "LEFT", -1, 0)
      AFUI.SetButtonAtlas(b, { "redbutton-" .. kind, "redbutton-" .. kind .. "-pressed", "redbutton-highlight", "redbutton-" .. kind .. "-disabled" })
      scaled[#scaled + 1] = b
      return b
    end
    expand, condense = redButton("AFUI_WorldMapMaximize", "expand"), redButton("AFUI_WorldMapMinimize", "condense")
  end

  -- The map frame's own mouse / keyboard capture (2.4.3: the frame covers the screen) only stays on while maximized, so the windowed
  -- map does not block the world behind it.
  local mouse0, keys0 = wm:IsMouseEnabled() and true or false, wm:IsKeyboardEnabled() and true or false
  local G -- current geometry
  -- 2.5.3: the canvas takes the quest panel's room when the panel is hidden (the window keeps its size): the map frame itself is widened (the canvas is anchored
  -- to it, so the client's OnSizeChanged -> OnCanvasSizeChanged rebuilds its zoom levels, which MapCoverLevels then fits to the wider clip).
  local canvasWide = scroll and not WorldMapDetailFrame
  local base0 = canvasWide and wm:GetWidth() or 0 -- the map frame's own width (1024)
  local extraNow = 0 -- px of the window right of the canvas that are not the canvas (the panel's column while the panel is shown)
  local moved = AztraForeverUICharDB and AztraForeverUICharDB.worldMapOffset
  if type(moved) ~= "table" or type(moved.x) ~= "number" or type(moved.y) ~= "number" then moved = { x = 0, y = 0 } end -- the window as the player dragged it (UI px, windowed only)
  local T, Il, Ir, Ib = TITLE, INSET_L, INSET_R, INSET_B -- the window's margins around the canvas: Forever's frame windowed, none when maximized
  local locate -- the "your location" button (2.5.3 canvas)
  local place -- puts the corner widgets of the mode (set below, needs G)
  local function isMax() return AztraForeverUICharDB ~= nil and AztraForeverUICharDB.worldMapMaximized == true end

  -- Where the map frame goes. 2.4.3: the frame covers UIParent, so the positioning guide (every map widget hangs off it) moves; 2.5.3: the
  -- frame itself (the UI panel manager anchors it again on every show, see the hooks below). Offsets are in the map frame's units (k px each).
  -- The canvas TOPLEFT sits at (11, -70) of the 2.5.3 frame and at the guide's TOP + (-502, -69) on 2.4.3; the window is 2 px left of and
  -- 67 px above it, in real pixels.
  local function reposition()
    if not G then return end
    local k = G.k
    local gx, gy = G.x + (G.maxd and 0 or moved.x), G.y + (G.maxd and 0 or moved.y)
    if scroll then
      wm:ClearAllPoints()
      wm:SetPoint("TOPLEFT", UIParent, "TOPLEFT", (gx + Il) / k - 11, (gy - T) / k + 70)
    elseif _G.WorldMapPositioningGuide then
      local guide = _G.WorldMapPositioningGuide
      guide:ClearAllPoints()
      guide:SetPoint("CENTER", wm, "CENTER", (gx - G.uiw / 2 + Il) / k + 502, (G.uih / 2 + gy - T) / k - 315)
    end
  end

  local function apply()
    local maxd = isMax()
    local uiw, uih = UIParent:GetWidth(), UIParent:GetHeight()
    G = AFUI.WorldMapGeometry(maxd, uiw, uih)
    G.uiw, G.uih, G.maxd = uiw, uih, maxd
    local k = G.k
    local cur = wm:GetEffectiveScale() / UIParent:GetEffectiveScale() -- UI px per map unit right now
    if cur > 0 then wm:SetScale(wm:GetScale() * k / cur) end
    for _, f in ipairs(scaled) do f:SetScale(1 / k) end
    T, Il, Ir, Ib = TITLE, INSET_L, INSET_R, INSET_B
    local w, h = 1002 * k + Il + Ir + G.extra, 668 * k + T + Ib
    local panelOn = not maxd and AFUI.WorldMapPanelOpen()
    G.w, G.h = w, h
    extraNow = (canvasWide and not panelOn) and 0 or G.extra -- hidden panel: the canvas is widened over its column, the window keeps its size
    if canvasWide and base0 > 0 then
      local want = base0 + (panelOn and 0 or G.extra / k)
      if math.abs(wm:GetWidth() - want) > 0.01 then
        wm:SetWidth(want)
        if type(wm.OnFrameSizeChanged) == "function" then pcall(wm.OnFrameSizeChanged, wm) end -- the client rebuilds its zoom levels for the new clip (the XML has no OnSizeChanged for it)
        if AFUI.MapCoverLevels(scroll, true) then AFUI.MapResetView(scroll) end
      end
    end
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", canvas, "TOPLEFT", -Il, T)
    win:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", Ir + extraNow, -Ib)
    for _, c in pairs(chromes) do c:Hide() end
    do -- the frame of either mode: the maximized one has no portrait, quest panel or panel handle
      local key = (maxd and "max" or "win") .. math.floor(w + 0.5) .. "x" .. math.floor(h + 0.5)
      chrome(key, w, h, not maxd):Show()
      if not tiled then
        local rw = ART["UI-Background-Rock"]
        rock:SetTexCoord(0, (w - 4) / rw[1], 0, (h - 23) / rw[2])
      end
      rockFrame:Show()
      if maxd then portrait:Hide() else portrait:Show() end
      for _, t in ipairs(navArt) do t:Show() end
      for _, f in ipairs(winOnly) do f:Show() end
      for _, f in ipairs(panelOnly) do if maxd then f:Hide() else f:Show() end end
    end
    -- the title container (docs §2: TOPLEFT +58, TOPRIGHT -24 of the frame, 20 high) the text centres in; the buttons take the right end
    title:ClearAllPoints(); title:SetJustifyH("CENTER")
    title:SetPoint("TOPLEFT", win, "TOPLEFT", maxd and 24 or 58, -6); title:SetPoint("TOPRIGHT", win, "TOPRIGHT", -24, -6)
    title:SetText(maxd and "Map" or "Map & Quest Log")
    nav:ClearAllPoints()
    nav:SetPoint("TOPLEFT", win, "TOPLEFT", maxd and NAV.l or NAV.lp, -NAV.t)
    nav:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", -(panelOn and PANEL_W + INSET_R + 50 or NAV.r), -(NAV.t + NAV.h))
    if close then
      close:ClearAllPoints(); close:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 3)
    end
    AFUI.WorldMapPanelShow(panelOn)
    if place then place() end
    -- the black screen behind the map: Forever has it only when maximized (2.4.3: the BlackoutWorld texture, 2.5.3: BlackoutFrame)
    local black = _G.BlackoutWorld or child("BlackoutFrame")
    if black then if maxd then black:Show() else black:Hide() end end
    wm:EnableMouse(maxd and mouse0 or false); wm:EnableKeyboard(maxd and keys0 or false)
    if expand then
      if maxd then expand:Hide(); condense:Show() else condense:Hide(); expand:Show() end
    end
    reposition()
  end
  AFUI.WorldMapApply = apply
  function AFUI.WorldMapSetMaximized(on)
    if AztraForeverUICharDB then AztraForeverUICharDB.worldMapMaximized = on and true or false end
    apply()
  end
  if expand then
    expand:SetScript("OnClick", function() AFUI.WorldMapSetMaximized(true) end)
    condense:SetScript("OnClick", function() AFUI.WorldMapSetMaximized(false) end)
  end
  wm:HookScript("OnShow", apply)
  AFUI.On("UI_SCALE_CHANGED", function() if wm:IsShown() then apply() end end)
  if scroll then
    for _, fn in ipairs({ "UpdateUIPanelPositions", "MaximizeUIPanel" }) do
      if type(_G[fn]) == "function" then hooksecurefunc(fn, function() if wm:IsShown() then reposition() end end) end
    end
  end
  apply()

  -- Forever's coordinates (video 3): "Cursor: 85.8, 73.1" (only while the cursor is over the map) above "Player: 40.6, 37.7" in the canvas' bottom-left corner.
  local plateHost = CreateFrame("Frame", nil, win)
  plateHost:SetAllPoints(win); plateHost:SetFrameLevel(base + 26)
  local you = plateHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  you:SetJustifyH("LEFT"); you:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", INSET_L + 64, INSET_B + 3)
  you:SetShadowColor(0, 0, 0, 1); you:SetShadowOffset(1, -1)
  local cursorTxt = plateHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cursorTxt:SetJustifyH("LEFT"); cursorTxt:SetShadowColor(0, 0, 0, 1); cursorTxt:SetShadowOffset(1, -1)
  AFUI.WorldMapCoords = { player = you, cursor = cursorTxt, title = title }
  -- the handle that folds the quest panel away (the window keeps its size): QuestCollapse-Hide / Show on the map's corner shadow, canvas BOTTOMRIGHT -2, +1
  local shadow = plateHost:CreateTexture(nil, "BACKGROUND"); AFUI.SetAtlas(shadow, "mapcornershadow-right", true)
  local toggle = CreateFrame("Button", "AFUI_WorldMapPanelToggle", plateHost)
  toggle:SetWidth(32); toggle:SetHeight(32)
  panelOnly[#panelOnly + 1] = toggle; panelOnly[#panelOnly + 1] = shadow
  shadow:SetPoint("BOTTOMRIGHT", toggle, "BOTTOMRIGHT", 2, -1)
  local function toggleTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText(AFUI.WorldMapPanelOpen() and "Hide Quest Log" or "Show Quest Log", 1, 1, 1); GameTooltip:Show()
  end
  toggle:SetScript("OnClick", function(self) AFUI.WorldMapSetPanel(not AFUI.WorldMapPanelOpen()); if GameTooltip:GetOwner() == self then toggleTip(self) end end) -- the tip follows the new state
  toggle:SetScript("OnEnter", toggleTip)
  toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Drag the windowed map by its title row (between the portrait and the buttons). reposition() adds the offset, so the UI panel manager cannot undo it; kept per character.
  local drag = CreateFrame("Button", "AFUI_WorldMapDrag", plateHost)
  drag:SetFrameLevel(base + 27)
  drag:SetPoint("TOPLEFT", win, "TOPLEFT", 58, -2); drag:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", -64, -NAV.t)
  panelOnly[#panelOnly + 1] = drag
  local function dragTo()
    local cx, cy = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    local lo, hi = G.uih - G.h, 16 -- the window's top stays on screen with its bottom
    moved.x = math.max(-G.x, math.min(G.uiw - G.w - G.x, cx / s - drag.from[1]))
    moved.y = math.max(-(math.max(lo, hi)) - G.y, math.min(-hi - G.y, cy / s - drag.from[2]))
    reposition()
  end
  drag:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or not G or G.maxd then return end
    local cx, cy = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    drag.from = { cx / s - moved.x, cy / s - moved.y }
  end)
  drag:SetScript("OnUpdate", function() if drag.from and G then dragTo() end end)
  drag:SetScript("OnMouseUp", function()
    if not drag.from then return end
    drag.from = nil
    if AztraForeverUICharDB then AztraForeverUICharDB.worldMapOffset = moved end
  end)
  function AFUI.WorldMapSetPanel(on)
    if AztraForeverUICharDB then AztraForeverUICharDB.questPanelOpen = on and true or false end
    apply()
  end
  -- the canvas' right inset inside the window: the margin plus, windowed, the column of the quest panel
  function AFUI.WorldMapCanvasRightInset() return Ir + extraNow end
  place = function()
    toggle:ClearAllPoints(); toggle:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -(AFUI.WorldMapCanvasRightInset() + 2), Ib + 1)
    you:ClearAllPoints(); you:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", isMax() and 10 or Il + 64, Ib + 3)
    cursorTxt:ClearAllPoints(); cursorTxt:SetPoint("BOTTOMLEFT", you, "TOPLEFT", 0, 2)
    if locate then locate:ClearAllPoints(); locate:SetPoint("TOPLEFT", win, "TOPLEFT", Il + 3, -(TITLE + 2)) end
  end
  table.insert(AFUI.WorldMapPanelHooks, function(on)
    AFUI.SetButtonAtlas(toggle, on and { "questcollapse-hide-down", "questcollapse-hide-up", "questcollapse-hide-up" } or { "questcollapse-show-down", "questcollapse-show-up", "questcollapse-show-up" }, 0.4)
  end)
  apply()
  -- Zoom (2.5.3 canvas only): the wheel over the map zooms towards the cursor (Forever has no zoom buttons). The gold ring at the canvas' top-left
  -- takes the map to the player's own zone.
  -- A map change, whoever starts it (the client's click / right click, the breadcrumb, the audit): fresh zoom and pan, the breadcrumb and the quest panel follow.
  local stamp
  local function mapChanged()
    local id = wm.GetMapID and wm:GetMapID()
    if id == stamp then return false end
    stamp = id
    if scroll and not WorldMapDetailFrame then AFUI.MapResetView(scroll) end
    if updateCrumbs then updateCrumbs() end
    for _, f in ipairs(AFUI.MapChangedHooks) do pcall(f, id) end
    return true
  end
  if type(wm.SetMapID) == "function" then hooksecurefunc(wm, "SetMapID", mapChanged) end
  if scroll and not WorldMapDetailFrame then
    AFUI.MapInstallCursor(scroll)
    -- every rebuild of the zoom levels (a new map, a resized clip) is fitted to cover the clip; the client's ResetZoom follows it
    if type(scroll.CreateZoomLevels) == "function" then hooksecurefunc(scroll, "CreateZoomLevels", function() AFUI.MapCoverLevels(scroll) end) end
    AFUI.MapCoverLevels(scroll)
    scroll:EnableMouseWheel(true)
    scroll:HookScript("OnMouseWheel", function(self, delta)
      local cx, cy
      if self.GetNormalizedCursorPosition then cx, cy = self:GetNormalizedCursorPosition() end
      AFUI.MapZoom(self, delta, cx, cy)
    end)
    -- no clamping on the frame the map changed (the new canvas has its own extents; the reset already put the view at its target)
    scroll:HookScript("OnUpdate", function(self)
      if not mapChanged() then AFUI.MapClampView(self) end
      if AFUI.MapQuestPins then AFUI.MapQuestPins.Layout() end
      if AFUI.MapQuestPins then AFUI.MapQuestPins.UpdateGroup() end
    end)
    -- The client's default mode pans first and zooms 100x slower ("translate faster than scale"), so the view sits at its new, off-centre position
    -- while the scale is still small (the canvas then lies beside the clip for seconds). Linear lerps scale and pan by the same fraction: the view stays inside the extents.
    if type(scroll.SetScalingMode) == "function" then scroll:SetScalingMode("SCALING_MODE_LINEAR") end
    locate = CreateFrame("Button", "AFUI_WorldMapLocate", plateHost)
    locate:SetWidth(26); locate:SetHeight(26)
    locate:SetNormalTexture(PLAIN .. "AFUI-Locator"); locate:SetPushedTexture(PLAIN .. "AFUI-Locator")
    locate:SetHighlightTexture(PLAIN .. "AFUI-Locator", "ADD")
    local pt = locate:GetPushedTexture(); if pt then pt:ClearAllPoints(); pt:SetPoint("TOPLEFT", locate, "TOPLEFT", 1, -1); pt:SetPoint("BOTTOMRIGHT", locate, "BOTTOMRIGHT", 1, -1) end
    local ht = locate:GetHighlightTexture(); if ht then ht:SetAlpha(0.35) end
    locate:SetScript("OnClick", function()
      local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
      if here then AFUI.MapNavigate(wm, here) end
    end)
    locate:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Show your location", 1, 1, 1); GameTooltip:Show() end)
    locate:SetScript("OnLeave", function() GameTooltip:Hide() end)
    place()
    if AFUI.MapQuestPins then AFUI.MapQuestPins.Setup(wm, scroll) end -- the tracked quests' points on the canvas (MapQuestPins.lua)
    if AFUI.MapCityLinks then AFUI.MapCityLinks.Setup() end -- clickable cities the client leaves dead (MapCityLinks.lua)
  end
  local wait = 1
  win:SetScript("OnUpdate", function(_, dt)
    wait = wait + dt
    if wait < 0.1 then return end
    wait = 0
    local px, py, cx, cy
    if scroll and not WorldMapDetailFrame then -- 2.5.3: the retail map canvas
      cx, cy = scroll:GetNormalizedCursorPosition()
      local mapID = C_Map and C_Map.GetPlayerMapPosition and wm.GetMapID and wm:GetMapID()
      if mapID then -- nil until a map is chosen (the first open)
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then px, py = pos:GetXY() end
      end
    else
      px, py = GetPlayerMapPosition("player")
      local mx, my = GetCursorPosition()
      local s = canvas:GetEffectiveScale()
      local left, top = canvas:GetLeft(), canvas:GetTop()
      if left and top and s and MouseIsOver(canvas) then cx, cy = (mx / s - left) / canvas:GetWidth(), (top - my / s) / canvas:GetHeight() end
    end
    if canvasWide and G and not G.maxd and not AFUI.WorldMapPanelOpen() and AFUI.MapCoverLevels(scroll, true) then AFUI.MapResetView(scroll) end -- widened canvas: levels measured on a stale clip
    if scroll and not WorldMapDetailFrame then AFUI.MapEnsureZoomLevels(scroll) end
    you:SetText(AFUI.PlayerCoordsText(px, py))
    if cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 and MouseIsOver and MouseIsOver(canvas) then
      cursorTxt:SetText("Cursor: " .. string.format("%.1f, %.1f", cx * 100, cy * 100)); cursorTxt:Show()
    else cursorTxt:Hide() end
    mapChanged()
    if updateCrumbs then updateCrumbs() end
  end)
  if updateCrumbs then wm:HookScript("OnShow", function() mapChanged(); updateCrumbs() end); updateCrumbs() end
end


AFUI.SetupWorldMap = setup
AFUI.RegisterModule("WorldMap", { OnLogin = setup })
-- 2.5.3 loads Blizzard_WorldMap on demand when the map was never opened.
AFUI.On("ADDON_LOADED", function(_, addon) if addon == "Blizzard_WorldMap" then setup() end end)
