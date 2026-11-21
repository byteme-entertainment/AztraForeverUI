-- Main (paged) and four extra action bars built from Blizzard's ActionBarButtonTemplate.
local SIZE = 45 -- Forever's ActionButtonTemplate size

AFUI.PAGE_DRIVER = "[bar:2]2;[bar:3]3;[bar:4]4;[bar:5]5;[bar:6]6;[bonusbar:5]11;[bonusbar:1]7;[bonusbar:2]8;[bonusbar:3]9;[bonusbar:4]10;1"

function AFUI.ActionFor(page, i) return (page - 1) * 12 + i end

-- vertical (Forever's Orientation): the buttons fill a column from the top first and `rows` is the number of columns.
function AFUI.ClampRows(count, rows) return math.max(1, math.min(rows or 1, math.max(count, 1))) end -- 1..12, never above the icons

function AFUI.LayoutButtons(count, rows, size, padding, vertical)
  rows = AFUI.ClampRows(count, rows)
  local cols, step, points = math.ceil(count / rows), size + padding, {}
  for i = 1, count do
    if vertical then
      points[i] = { math.floor((i - 1) / cols) * step, -((i - 1) % cols) * step }
    else
      points[i] = { ((i - 1) % cols) * step, -math.floor((i - 1) / cols) * step }
    end
  end
  return points
end

-- Width and height of the block LayoutButtons draws.
function AFUI.LayoutSize(count, rows, size, padding, vertical)
  rows = AFUI.ClampRows(count, rows)
  local long, step = math.ceil(count / rows), size + padding
  if vertical then return rows * step - padding, long * step - padding end
  return long * step - padding, rows * step - padding
end

local DEFAULTS = { numIcons = 12, numRows = 1, padding = 2, visibility = "always", orientation = "Horizontal",
  alwaysShow = true, hideBarArt = false, hideBarScrolling = false }
-- page: the fixed action page of an extra bar (Blizzard's MultiBar pages).
local BARS = {
  { key = "main", name = "Main", page = 1, paged = true },
  { key = "bottomleft", name = "BottomLeft", page = 6 },
  { key = "bottomright", name = "BottomRight", page = 5 },
  { key = "right", name = "Right", page = 3 },
  { key = "right2", name = "Right2", page = 4 },
}

-- Shared with the pet/stance/possess bars (BarExtras.lua), which reuse Blizzard buttons of the same template family.
function AFUI.SkinButton(b, size)
  local name = b:GetName()
  b:SetWidth(size); b:SetHeight(size)
  -- FrameXML keeps re-setting the normal texture's file; hide it and draw Forever's frame on top.
  b:GetNormalTexture():SetAlpha(0)
  -- The frame sprite (46x45) shows its rim over 44x44 px with an interior window of x 2..41, y 3..41 (measured from the page pixels,
  -- tools/preview/artbox.mjs --window), so the icon is pinned to that window, not stretched over the whole button: a full-size icon
  -- stuck out of the rounded rim on the right and bottom. Insets are for a 45 button and scale with the size.
  local k = size / 45
  local icon = _G[name .. "Icon"]
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  icon:ClearAllPoints()
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2 * k, -3 * k)
  icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4 * k, 4 * k)
  -- Forever (actionbuttontemplate.xml, TextOverlayContainer): hotkey TOPRIGHT -5,-5, count BOTTOMRIGHT -5,5 (Blizzard's TBC template: -2,-3 / -2,2).
  local hk, ct = _G[name .. "HotKey"], _G[name .. "Count"]
  if hk then hk:ClearAllPoints(); hk:SetPoint("TOPRIGHT", b, "TOPRIGHT", -5, -5) end
  if ct then ct:ClearAllPoints(); ct:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -5, 5) end
  -- Forever's hotkey text is plain white; the TBC range check paints it light grey (red when out of range stays).
  if hk and not hk.afuiWhite then
    hk.afuiWhite = true
    -- a post-hook, not a replaced method: the client's range / usable code calls it and must not run our function (taint)
    hooksecurefunc(hk, "SetVertexColor", function(self, r, g, bl)
      if AFUI.FX then AFUI.FX.RangeColor(b, r, g, bl) end -- the client's range answer (red / light grey) also tints the icon (ActionButtonFX.lua)
      if r and r == g and g == bl and r < 1 then self:SetVertexColor(1, 1, 1) end -- LIGHTGRAY_FONT_COLOR
    end)
    hk:SetVertexColor(1, 1, 1)
  end
  -- the equipped-item border is drawn 62 on a 36 button (UI-ActionButton-Border): keep that ratio on ours
  local equipped = _G[name .. "Border"]
  if equipped then equipped:SetWidth(size * 62 / 36); equipped:SetHeight(size * 62 / 36) end
  local cd = _G[name .. "Cooldown"]
  cd:ClearAllPoints()
  cd:SetPoint("TOPLEFT", b, "TOPLEFT", 2 * k, -3 * k) -- the same window as the icon
  cd:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4 * k, 4 * k)
  local border = b:CreateTexture(nil, "ARTWORK")
  border:SetPoint("TOPLEFT", b, "TOPLEFT")
  border:SetWidth(size + 1); border:SetHeight(size)
  AFUI.SetAtlas(border, "ui-hud-actionbar-iconframe")
  -- state sprites are 46x45 like the frame: same TOPLEFT box (the template's SetAllPoints squeezed them onto the 45 square)
  for _, t in ipairs({ b:GetPushedTexture(), b:GetHighlightTexture(), b:GetCheckedTexture() }) do
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", b, "TOPLEFT"); t:SetWidth(size + 1); t:SetHeight(size)
  end
  AFUI.SetAtlas(b:GetPushedTexture(), "ui-hud-actionbar-iconframe-down")
  AFUI.SetAtlas(b:GetHighlightTexture(), "ui-hud-actionbar-iconframe-mouseover")
  AFUI.SetAtlas(b:GetCheckedTexture(), "ui-hud-actionbar-iconframe-mouseover")
  if AFUI.FX then AFUI.FX.Attach(b, size) end -- cooldown numbers, tints, proc glow, label switches
end

local function Layout(bar)
  local s = bar.settings
  local vertical = s.orientation == "Vertical"
  local points = AFUI.LayoutButtons(s.numIcons, s.numRows, SIZE, s.padding, vertical)
  for i, b in ipairs(bar.buttons) do
    local p = points[i]
    if p then
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", p[1], p[2])
      b:SetAttribute("statehidden", nil)
      local always = s.alwaysShow ~= false
      b:SetAttribute("showgrid", always and 1 or nil) -- "Always Show Buttons": empty slots stay visible
      local a = AFUI.FX and AFUI.FX.ActionOf(b)
      if always or not (a and _G.HasAction) or HasAction(a) then b:Show() else b:Hide() end -- off: an empty slot hides, the client shows it again once it fills
    else
      b:SetAttribute("statehidden", true) -- stops ActionButton_Update from showing it again
      b:Hide()
    end
  end
  local w, h = AFUI.LayoutSize(s.numIcons, s.numRows, SIZE, s.padding, vertical)
  bar.frame:SetWidth(w); bar.frame:SetHeight(h)
  bar.frame:SetAlpha(s.visibility == "mouseover" and 0 or 1)
end

local function Fade(bar)
  if bar.settings.visibility == "mouseover" then bar.frame:SetAlpha(MouseIsOver(bar.frame) and 1 or 0) end
end

AFUI.Bars = {}
for n, d in ipairs(BARS) do
  local frame = CreateFrame("Frame", "AFUI_" .. d.name .. "Bar", UIParent, d.paged and AFUI.PAGED_HEADER_TEMPLATE or nil)
  -- shortcut: stacked above the bottom edge until Edit Mode (Task 8) positions bars.
  frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 20 + (n - 1) * (SIZE + 6) + (n > 1 and 20 or 0)) -- gap for the XP bar
  local bar = { frame = frame, buttons = {}, settings = DEFAULTS }
  local show = function() frame:SetAlpha(1) end
  local fade = function() Fade(bar) end
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", show)
  frame:SetScript("OnLeave", fade)
  for i = 1, 12 do
    local b = CreateFrame("CheckButton", "AFUI_" .. d.name .. "Button" .. i, frame, "ActionBarButtonTemplate")
    AFUI.SkinButton(b, SIZE)
    b:SetAttribute("showgrid", 1) -- keep empty slots visible, as Forever does
    b:SetAttribute("action", AFUI.ActionFor(d.page, i))
    b:HookScript("OnEnter", show)
    b:HookScript("OnLeave", fade)
    bar.buttons[i] = b
  end
  if d.paged then AFUI.SetupPaging(frame, bar.buttons, AFUI.PAGE_DRIVER) end
  local layout = function() -- runs out of combat (RunOutOfCombat), so rebinding here is safe
    Layout(bar)
    if AFUI.UpdateBindings then AFUI.UpdateBindings() end -- the Icons setting may have hidden or shown buttons
  end
  function bar.ApplySettings(settings)
    bar.settings = settings
    AFUI.RunOutOfCombat(layout)
    if bar.OnSettings then bar.OnSettings(settings) end -- BarExtras: the main bar's art, dividers and page arrows
  end
  bar.ApplySettings(DEFAULTS)
  AFUI.Bars[d.key] = bar
end

---------------------------------------------------------------- Interface > Action Bars toggles
-- Bottom left, bottom right, right and right 2 are shown only when the player enabled them, as in the stock client. Both clients
-- answer GetActionBarToggles() with the four checkboxes and MultiActionBar_Update (2.4.3 FrameXML MultiActionBars.lua:24-52,
-- Gethe/wow-ui-source 2.5.3 MultiActionBars.lua:48-57) shows or hides MultiBarBottomLeft / BottomRight / Right from SHOW_MULTI_ACTIONBAR_1-3
-- and MultiBarLeft (our right 2) only when SHOW_MULTI_ACTIONBAR_3 and _4 are both on. The client calls MultiActionBar_Update on
-- PLAYER_ENTERING_WORLD (UIParent.lua) and the options panel calls SetActionBarToggles when a box is ticked: both are hooked.
local set -- what SetActionBarToggles last got: GetActionBarToggles can lag behind the server (UIParent.lua notes it)
local function Toggles()
  if set then return unpack(set, 1, 4) end
  if GetActionBarToggles then return GetActionBarToggles() end
  return true, true, true, true
end
function AFUI.BarEnabled(key)
  local b1, b2, b3, b4 = Toggles()
  if key == "bottomleft" then return b1 and true or false end
  if key == "bottomright" then return b2 and true or false end
  if key == "right" then return b3 and true or false end
  if key == "right2" then return (b3 and b4) and true or false end
  return true
end
local TOGGLED = { "bottomleft", "bottomright", "right", "right2" }

local function ApplyToggles() -- out of combat: the bars hold protected buttons
  for _, key in ipairs(TOGGLED) do
    local frame = AFUI.Bars[key].frame
    if AFUI.BarEnabled(key) then frame:Show() else frame:Hide() end
  end
  if AFUI.RestackBars then AFUI.RestackBars() end -- the bars above them in the stack follow
  if AFUI.EditMode and AFUI.EditMode.RefreshEnabled then AFUI.EditMode.RefreshEnabled() end -- Edit Mode open: boxes come and go
end
function AFUI.UpdateBarToggles() AFUI.RunOutOfCombat(ApplyToggles) end

local BLIZZARD = { "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "BonusActionBarFrame" }
local function KillBlizzard()
  for _, name in ipairs(BLIZZARD) do AFUI.Kill(_G[name]) end
  for i = 1, 12 do AFUI.Kill(_G["ActionButton" .. i]) end
end
AFUI.RegisterModule("ActionBars", { OnLogin = function()
  AFUI.RunOutOfCombat(KillBlizzard)
  if type(_G.MultiActionBar_Update) == "function" then hooksecurefunc("MultiActionBar_Update", AFUI.UpdateBarToggles) end
  if type(_G.SetActionBarToggles) == "function" then
    hooksecurefunc("SetActionBarToggles", function(...) set = { ... }; AFUI.UpdateBarToggles() end)
  end
  AFUI.UpdateBarToggles()
end })
AFUI.On("PLAYER_ENTERING_WORLD", function() set = nil; AFUI.UpdateBarToggles() end)
