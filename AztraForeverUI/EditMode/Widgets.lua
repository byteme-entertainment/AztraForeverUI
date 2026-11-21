-- Edit Mode widgets drawn from Forever's own art (docs/forever-ref/screens/editmode): the DiamondMetal panel, three-slice red buttons
-- (128-RedButton), the minimal checkbox, the WowStyle1 dropdown with its menu, the minimal slider with steppers and the red X.
-- Blizzard's templates (UIPanelButtonTemplate, UIDropDownMenuTemplate, ...) look different on the TBC clients and cannot be drawn by the
-- offline preview, so every widget here is plain textures, font strings and buttons.
AFUI = AFUI or {}
local EM = AFUI.EditMode
local W = {}
AFUI.EditModeWidgets = W

W.MEDIUM = EM.FontName("GameFontHighlightMedium") -- 14, white
local function font(name) return _G[name] end

local function atlas(name) return AFUI_ATLAS and AFUI_ATLAS[string.lower(name)] end

---------------------------------------------------------------- small helpers
function W.Label(parent, template, text, point, rel, relPoint, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  fs:SetPoint(point, rel or parent, relPoint or point, x or 0, y or 0)
  fs:SetText(text or "")
  return fs
end

---------------------------------------------------------------- panel (DialogBorderTranslucentTemplate)
-- The DiamondMetal nine-slice (64 px atlas pieces drawn at half size) around a black 0.8 rectangle inset 7 px. 2.4.3 has no
-- nine-slice frames, so the pieces are plain textures and the edges are tiled by hand (atlas pieces cannot tile).
local DM = "ui-frame-diamondmetal-"
local PIECE = 32

local function tile(f, pool, i, name)
  local t = pool[i]
  if not t then t = f:CreateTexture(nil, "BORDER"); pool[i] = t end
  AFUI.SetAtlas(t, name)
  return t
end

local function layoutEdges(f, w, h)
  local function run(pool, name, horizontal, length, anchor)
    local e = atlas(name)
    local n = math.max(math.ceil((length - 2 * PIECE) / PIECE), 0)
    for i = 1, n do
      local t = tile(f, pool, i, name)
      local size = math.min(PIECE, length - 2 * PIECE - (i - 1) * PIECE)
      t:ClearAllPoints()
      t:SetWidth(horizontal and size or PIECE); t:SetHeight(horizontal and PIECE or size)
      local from = PIECE + (i - 1) * PIECE
      if horizontal then t:SetPoint(anchor .. "LEFT", f, anchor .. "LEFT", from, 0)
      else t:SetPoint("TOP" .. anchor, f, "TOP" .. anchor, 0, -from) end
      local frac = size / PIECE
      if e then
        if horizontal then t:SetTexCoord(e[4], e[4] + (e[5] - e[4]) * frac, e[6], e[7])
        else t:SetTexCoord(e[4], e[5], e[6], e[6] + (e[7] - e[6]) * frac) end
      end
      t:Show()
    end
    for i = n + 1, #pool do pool[i]:Hide() end
  end
  f.edges = f.edges or { top = {}, bottom = {}, left = {}, right = {} }
  run(f.edges.top, "_" .. DM .. "edgetop-c60-2x", true, w, "TOP")
  run(f.edges.bottom, "_" .. DM .. "edgebottom-c60-2x", true, w, "BOTTOM")
  run(f.edges.left, "!" .. DM .. "edgeleft-c60-2x", false, h, "LEFT")
  run(f.edges.right, "!" .. DM .. "edgeright-c60-2x", false, h, "RIGHT")
end

function W.Panel(name, w, h, opaque)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -7); bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -7, 7)
  AFUI.SetColor(bg, 0, 0, 0, opaque and 1 or 0.8) -- a window drawn over another must hide it
  f.bg = bg
  for _, c in ipairs({ { "topleft", "TOPLEFT" }, { "topright", "TOPRIGHT" }, { "bottomleft", "BOTTOMLEFT" }, { "bottomright", "BOTTOMRIGHT" } }) do
    local t = f:CreateTexture(nil, "BORDER")
    t:SetWidth(PIECE); t:SetHeight(PIECE); t:SetPoint(c[2], f, c[2], 0, 0)
    AFUI.SetAtlas(t, DM .. "corner" .. c[1] .. "-c60-2x")
  end
  function f.Resize(width, height)
    f:SetWidth(width); f:SetHeight(height)
    layoutEdges(f, width, height)
  end
  f.Resize(w, h)
  f:Hide()
  return f
end

---------------------------------------------------------------- red three-slice button (UIPanelButtonTemplate: 128-RedButton)
-- The art, the four states, the label colours and the minimum width are the shared AFUI.WinKit.button (the same one the Game Menu, Friends, Options, Group Finder
-- and Guild buttons use); this only builds the plain frame and its label. A press moves the label by (-2, -1) here.
function W.RedButton(parent, name, text, w, h, point, x, y, onClick)
  local b = CreateFrame("Button", name, parent)
  b:SetWidth(w); b:SetHeight(h)
  if point then b:SetPoint(point, parent, point, x or 0, y or 0) end
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.afPress = { -2, -1 }
  AFUI.WinKit.button(b, w, h)
  function b:SetText(t) b.text:SetText(t or "") end
  function b:GetText() return b.text:GetText() end
  if onClick then b:SetScript("OnClick", onClick) end
  b:SetText(text)
  return b
end

---------------------------------------------------------------- red X (UIPanelCloseButton)
function W.CloseButton(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(24); b:SetHeight(24)
  b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  b:SetFrameLevel((parent:GetFrameLevel() or 1) + 2)
  local art = b:CreateTexture(nil, "ARTWORK")
  art:SetAllPoints(b)
  AFUI.SetAtlas(art, "128-redbutton-exit")
  AFUI.SetButtonAtlas(b, { nil, nil, "128-redbutton-exit-highlight", nil }, 1)
  b:SetScript("OnMouseDown", function() AFUI.SetAtlas(art, "128-redbutton-exit-pressed") end)
  b:SetScript("OnMouseUp", function() AFUI.SetAtlas(art, "128-redbutton-exit") end)
  b:SetScript("OnClick", onClick)
  return b
end

---------------------------------------------------------------- checkbox (EditModeCheckButtonTemplate, minimal art)
-- 32x32 button with the 30x29 minimal box, the label 5 px to its right. c.checked mirrors the state (the client's GetChecked answers
-- 1 or nil on 2.4.3); the tick is a texture of ours, shown or hidden with it.
function W.Check(parent, name, text, onClick)
  local c = CreateFrame("CheckButton", name, parent)
  c:SetWidth(32); c:SetHeight(32)
  local box = c:CreateTexture(nil, "BACKGROUND")
  box:SetPoint("CENTER", c, "CENTER", 0, 0)
  AFUI.SetAtlas(box, "checkbox-minimal", true)
  local mark = c:CreateTexture(nil, "OVERLAY") -- the real frames show the classic gold tick (it overshoots the box) on the minimal box
  mark:SetAllPoints(c)
  mark:SetTexture("Interface\\AddOns\\AztraForeverUI\\Media\\plain\\UI-CheckBox-Check")
  mark:Hide()
  AFUI.SetButtonAtlas(c, { nil, nil, "checkbox-minimal", nil }, 0.5)
  c.label = c:CreateFontString(nil, "ARTWORK", W.MEDIUM)
  c.label:SetPoint("LEFT", c, "RIGHT", 5, 0)
  c.label:SetJustifyH("LEFT")
  c.label:SetText(text or "")
  c.checked = false
  local function paint()
    if c.checked then mark:Show() else mark:Hide() end
  end
  local nativeSet = c.SetChecked
  function c:SetChecked(v) nativeSet(self, v); c.checked = v and true or false; paint() end
  c:SetScript("OnClick", function()
    c.checked = c:GetChecked() and true or false
    paint()
    if onClick then onClick(c.checked) end
  end)
  return c
end

---------------------------------------------------------------- minimal slider with steppers (MinimalSliderWithSteppersTemplate)
-- The template's frame is `total` wide (300 for the grid spacing, 200 in the settings window): the bar (a 17 px track, a 20x19 thumb) is
-- inset 19 on each side, the steppers hang 4 px outside it and the value (gold) starts 25 px right of it. Place the returned slider
-- at the frame's left + 19 (s.INSET); it is total - 38 wide.
function W.Slider(parent, name, total, min, max, step)
  local s = CreateFrame("Slider", name, parent)
  s:SetOrientation("HORIZONTAL")
  s.INSET = 19
  s:SetWidth(total - 38); s:SetHeight(19)
  s:SetMinMaxValues(min, max); s:SetValueStep(step)
  s:EnableMouse(true)
  local function art(layer, name)
    local t = s:CreateTexture(nil, layer)
    AFUI.SetAtlas(t, name)
    return t
  end
  local left, mid, right = art("BACKGROUND", "minimal_sliderbar_left"), art("BACKGROUND", "_minimal_sliderbar_middle"), art("BACKGROUND", "minimal_sliderbar_right")
  left:SetWidth(11); left:SetHeight(17); right:SetWidth(11); right:SetHeight(17); mid:SetHeight(17)
  left:SetPoint("LEFT", s, "LEFT", 0, 0); right:SetPoint("RIGHT", s, "RIGHT", 0, 0)
  mid:SetPoint("LEFT", left, "RIGHT", 0, 0); mid:SetPoint("RIGHT", right, "LEFT", 0, 0)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local thumb = s:GetThumbTexture()
  if thumb then AFUI.SetAtlas(thumb, "minimal_sliderbar_button", true) end
  s.value = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  s.value:SetPoint("LEFT", s, "RIGHT", 25, 0)
  local function stepper(name, w, h, point, relPoint, x, dir)
    local b = CreateFrame("Button", nil, s)
    b:SetWidth(w); b:SetHeight(h); b:SetPoint(point, s, relPoint, x, 0)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints(b); AFUI.SetAtlas(t, name)
    b:SetScript("OnClick", function()
      if not s.enabled then return end
      s:SetValue(math.min(math.max(s:GetValue() + dir * step, min), max))
    end)
    return b
  end
  s.down = stepper("minimal_sliderbar_button_left", 11, 19, "RIGHT", "LEFT", -4, -1)
  s.up = stepper("minimal_sliderbar_button_right", 9, 18, "LEFT", "RIGHT", 4, 1)
  s.enabled = true
  function s.SetEnabledLook(on) -- disabled while its checkbox is off (the grid spacing)
    s.enabled = on
    s:EnableMouse(on)
    s:SetAlpha(on and 1 or 0.5)
  end
  return s
end

---------------------------------------------------------------- dropdown (WowStyle1DropdownTemplate) and its menu
-- The field: common-dropdown-textholder stretched over the 25 px frame (-8, +7 / +8, -9), the yellow arrow button at the right.
-- The menu: a dark list under it; rows are { text, checked, title, divider, func, gear, remove }.
local menu, catcher, rows = nil, nil, {}
local ROW_H = 22

local function closeMenu()
  if menu then menu:Hide() end
  if catcher then catcher:Hide() end
  if W.openDropdown then W.openDropdown.Paint(false); W.openDropdown = nil end
end
W.CloseMenu = closeMenu

local function buildMenu()
  catcher = CreateFrame("Button", "AFUI_EditModeMenuCatcher", UIParent)
  catcher:SetFrameStrata("TOOLTIP"); catcher:SetFrameLevel(1)
  catcher:SetAllPoints(UIParent)
  catcher:SetScript("OnClick", closeMenu)
  catcher:Hide()
  menu = CreateFrame("Frame", "AFUI_EditModeMenu", UIParent)
  menu:SetFrameStrata("TOOLTIP"); menu:SetFrameLevel(5)
  menu:EnableMouse(true)
  local bg = menu:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(menu); AFUI.SetColor(bg, 0.05, 0.05, 0.06, 0.96)
  for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", 1, 0 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 1, 0 }, { "TOPLEFT", "BOTTOMLEFT", 0, 1 }, { "TOPRIGHT", "BOTTOMRIGHT", 0, 1 } }) do
    local t = menu:CreateTexture(nil, "BORDER")
    t:SetPoint(e[1], menu, e[1], 0, 0); t:SetPoint(e[2], menu, e[2], 0, 0)
    if e[3] == 1 then t:SetHeight(1) else t:SetWidth(1) end
    AFUI.SetColor(t, 0.45, 0.36, 0.2, 1)
  end
  menu:Hide()
end

local function menuRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, menu)
  r:SetHeight(ROW_H)
  r.hl = r:CreateTexture(nil, "HIGHLIGHT")
  r.hl:SetAllPoints(r); r.hl:SetBlendMode("ADD"); AFUI.SetColor(r.hl, 1, 1, 1, 0.12)
  r.tick = r:CreateTexture(nil, "ARTWORK")
  r.tick:SetPoint("LEFT", r, "LEFT", 6, 0)
  AFUI.SetAtlas(r.tick, "common-dropdown-icon-radialtick-yellow", true)
  r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  r.text:SetPoint("LEFT", r, "LEFT", 28, 0)
  r.text:SetJustifyH("LEFT")
  r.line = r:CreateTexture(nil, "ARTWORK")
  r.line:SetHeight(1); r.line:SetPoint("LEFT", r, "LEFT", 6, 0); r.line:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  AFUI.SetColor(r.line, 0.5, 0.5, 0.5, 0.5)
  local function small(atlasName, dx)
    local b = CreateFrame("Button", nil, r)
    b:SetWidth(16); b:SetHeight(16); b:SetPoint("RIGHT", r, "RIGHT", dx, 0)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints(b); AFUI.SetAtlas(t, atlasName)
    b:Hide()
    return b
  end
  r.gear, r.remove = small("gear", -26), small("communities-icon-redx", -6)
  rows[i] = r
  return r
end

-- Opens the menu under `anchor`. items: see above (icon = an atlas drawn where the tick goes).
function W.OpenMenu(anchor, items, minWidth)
  if not menu then buildMenu() end
  local width, y = minWidth or 160, 5
  for _, it in ipairs(items) do
    if it.text then width = math.max(width, 28 + #it.text * 7.2 + (it.gear and 56 or 16)) end
  end
  local cursor = 0
  for i, it in ipairs(items) do
    local r = menuRow(i)
    cursor = i
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -y)
    r:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -y)
    r.line:Hide(); r.tick:Hide(); r.gear:Hide(); r.remove:Hide(); r.text:SetText("")
    local h = ROW_H
    if it.divider then
      h = 10; r.line:ClearAllPoints(); r.line:SetPoint("LEFT", r, "LEFT", 6, 0); r.line:SetPoint("RIGHT", r, "RIGHT", -6, 0); r.line:Show()
      r:EnableMouse(false)
    else
      r.text:SetText(it.text or "")
      r.text:SetFontObject(font(it.title and "GameFontNormal" or (it.disabled and "GameFontDisable" or "GameFontHighlight")))
      r.text:ClearAllPoints(); r.text:SetPoint("LEFT", r, "LEFT", it.title and 8 or 28, 0)
      if it.checked or it.icon then
        AFUI.SetAtlas(r.tick, it.icon or "common-dropdown-icon-radialtick-yellow", true)
        r.tick:Show()
      end
      r:EnableMouse(not it.title)
      r.func = it.func
      r:SetScript("OnClick", function()
        if it.disabled then return end
        closeMenu()
        if it.func then it.func() end
      end)
      r:SetScript("OnEnter", function() if it.gear then r.gear:Show() end; if it.remove then r.remove:Show() end end)
      r:SetScript("OnLeave", function()
        if not (MouseIsOver and MouseIsOver(r)) then r.gear:Hide(); r.remove:Hide() end
      end)
      if it.gear then
        r.gear:SetScript("OnClick", function() closeMenu(); it.gear(r) end)
        r.gear:SetScript("OnEnter", function() r.gear:Show(); r.remove:Show() end)
      end
      if it.remove then
        r.remove:SetScript("OnClick", function() closeMenu(); it.remove() end)
        r.remove:SetScript("OnEnter", function() r.gear:Show(); r.remove:Show() end)
      end
    end
    r:SetHeight(h)
    r:Show()
    y = y + h
  end
  for i = cursor + 1, #rows do rows[i]:Hide() end
  menu:SetWidth(width); menu:SetHeight(y + 5)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -4, -6)
  catcher:Show(); menu:Show()
end

-- d.SetItems(fn): fn() returns the rows when the menu opens. d:SetText(text) shows the current choice.
-- Forever's dropdown field for windows that keep the client's own dropdown frame or a plain button (video 3 f0089 / f0134 / f0205: the dark textholder with a
-- gold boxed down arrow; WinKit's bar draws a right pointing plate). Same contract as WinKit K.bar: :place(host, left, top, right, bottom insets),
-- plus :state("hover" | "pressed" | "open" | nil) for the arrow.
function W.ForeverField(parent, layer)
  local e = atlas("common-dropdown-textholder")
  local capL, capR = 16, 19
  local p = {}
  for i = 1, 3 do p[i] = parent:CreateTexture(nil, layer or "BACKGROUND"); if e then p[i]:SetTexture(e[1]) end end
  if e then
    local du = (e[5] - e[4]) / e[2]
    p[1]:SetTexCoord(e[4], e[4] + du * capL, e[6], e[7]); p[2]:SetTexCoord(e[4] + du * capL, e[5] - du * capR, e[6], e[7]); p[3]:SetTexCoord(e[5] - du * capR, e[5], e[6], e[7])
  end
  local fieldH = e and e[3] or 41
  p[1]:SetWidth(capL); p[1]:SetHeight(fieldH); p[3]:SetWidth(capR); p[3]:SetHeight(fieldH)
  local arrow = parent:CreateTexture(nil, "OVERLAY")
  AFUI.SetAtlas(arrow, "common-dropdown-a-button", true)
  return {
    arrow = arrow, parts = p,
    place = function(_, host, x1, y1, x2, y2)
      p[1]:SetPoint("TOPLEFT", host, "TOPLEFT", x1 - 8, y1 + 8)
      p[3]:SetPoint("TOPRIGHT", host, "TOPRIGHT", x2 + 8, y1 + 8)
      p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT", 0, 0); p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT", 0, 0)
      arrow:SetPoint("RIGHT", host, "RIGHT", x2 + 1, (y1 + y2) / 2 - 1) -- centred on the body (insets y1 from the top, y2 from the bottom)
    end,
    state = function(_, s) AFUI.SetAtlas(arrow, "common-dropdown-a-button" .. (s and ("-" .. s) or ""), true) end,
    alpha = function(_, a) for i = 1, 3 do p[i]:SetAlpha(a) end; arrow:SetAlpha(a) end,
  }
end
-- A client dropdown frame (UIDropDownMenuTemplate) dressed with it after WinKit's own bar: that bar goes invisible, the client's arrow button keeps its clicks and
-- lights the new arrow.
function W.DressDropdown(dd)
  if not dd or dd.afField or not dd.GetName then return end
  dd.afField = true
  if dd.afBar then for _, k in ipairs({ "l", "m", "r" }) do if dd.afBar[k] then dd.afBar[k]:SetAlpha(0) end end end
  local f = W.ForeverField(dd, "BACKGROUND")
  f:place(dd, 16, -2, -16, 4)
  dd.afField = f
  local btn = _G[dd:GetName() .. "Button"]
  if btn and btn.HookScript then
    btn:HookScript("OnEnter", function() f:state("hover") end)
    btn:HookScript("OnLeave", function() f:state(nil) end)
    btn:HookScript("OnMouseDown", function() f:state("pressed") end)
    btn:HookScript("OnMouseUp", function() f:state(nil) end)
  end
end

function W.Dropdown(parent, name, width)
  local d = CreateFrame("Button", name, parent)
  d:SetWidth(width); d:SetHeight(25)
  -- the atlas has slice margins (left 16, right 19): the caps keep their size, the middle stretches
  local e = atlas("common-dropdown-textholder")
  local capL, capR, full = 16, 19, e and e[2] or 54
  local pieces = {}
  for i = 1, 3 do
    pieces[i] = d:CreateTexture(nil, "BACKGROUND")
    if e then pieces[i]:SetTexture(e[1]) end
  end
  if e then
    local du = (e[5] - e[4]) / full
    pieces[1]:SetTexCoord(e[4], e[4] + du * capL, e[6], e[7])
    pieces[2]:SetTexCoord(e[4] + du * capL, e[5] - du * capR, e[6], e[7])
    pieces[3]:SetTexCoord(e[5] - du * capR, e[5], e[6], e[7])
  end
  local fieldH = e and e[3] or 41
  pieces[1]:SetPoint("TOPLEFT", d, "TOPLEFT", -8, 7); pieces[1]:SetWidth(capL); pieces[1]:SetHeight(fieldH)
  pieces[3]:SetPoint("TOPRIGHT", d, "TOPRIGHT", 8, 7); pieces[3]:SetWidth(capR); pieces[3]:SetHeight(fieldH)
  pieces[2]:SetPoint("TOPLEFT", pieces[1], "TOPRIGHT", 0, 0); pieces[2]:SetPoint("BOTTOMRIGHT", pieces[3], "BOTTOMLEFT", 0, 0)
  local arrow = d:CreateTexture(nil, "OVERLAY")
  arrow:SetPoint("RIGHT", d, "RIGHT", 1, -3)
  AFUI.SetAtlas(arrow, "common-dropdown-a-button", true)
  d.label = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  d.label:SetPoint("LEFT", d, "LEFT", 8, 1)
  d.label:SetPoint("RIGHT", arrow, "LEFT", 0, 0)
  d.label:SetJustifyH("LEFT"); d.label:SetHeight(12)
  d.hover, d.open, d.pressed = false, false, false
  function d.Paint(open)
    if open ~= nil then d.open = open end
    local state = d.open and "-open" or (d.pressed and "-pressed" or (d.hover and "-hover" or ""))
    AFUI.SetAtlas(arrow, "common-dropdown-a-button" .. state, true)
  end
  function d:SetText(t) d.label:SetText(t or "") end
  function d:GetText() return d.label:GetText() end
  d.items = function() return {} end
  function d.SetItems(fn) d.items = fn end
  d:SetScript("OnEnter", function() d.hover = true; d.Paint() end)
  d:SetScript("OnLeave", function() d.hover = false; d.Paint() end)
  d:SetScript("OnMouseDown", function() d.pressed = true; d.Paint() end)
  d:SetScript("OnMouseUp", function() d.pressed = false; d.Paint() end)
  d:SetScript("OnClick", function()
    if W.openDropdown == d then return closeMenu() end
    closeMenu()
    W.openDropdown = d
    d.Paint(true)
    W.OpenMenu(d, d.items(), width + 16)
  end)
  d.Paint(false)
  return d
end
