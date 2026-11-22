-- Shared pieces of the Social / Quest Log / Group Finder windows: Forever's metal portrait frame drawn over Blizzard's own frame (the frame keeps its
-- size, its children and every script: only art is hidden / re-skinned), red three-slice buttons, bottom tabs, dropdowns, column headers, inner
-- panels and list-row hovers. Built on Professions.Kit (the same chrome the Character / Professions windows use). Nothing here is protected.
AFUI = AFUI or {}
local K = {}
AFUI.WinKit = K

local function g(name) return name and _G[name] end
K.g = g
local function kit() return AFUI.Professions and AFUI.Professions.Kit end

---------------------------------------------------------------- pure
-- "Quests: 12/25" (QUEST_LOG_COUNT_TEMPLATE of Forever's cata questlogframe); over the cap the count is red.
function K.QuestCount(n, max)
  local c = n > max and "|cffff2020" or "|cffffffff"
  return string.format("%s%d|r/%d", "Quests: " .. c, n, max)
end

-- Names "Prefix1".."PrefixN" (the clients' numbered rows).
function K.Numbered(prefix, n, from)
  local out = {}
  for i = from or 1, n do out[#out + 1] = prefix .. i end
  return out
end

-- Tab art: the active tab is the one the client disabled (PanelTemplates_SelectTab disables it) or the one flagged by afActive.
function K.TabState(enabled, flagged)
  if flagged ~= nil then return flagged and "active" or "idle" end
  return enabled and "idle" or "active"
end

-- Where the first bottom tab goes: the TOPLEFT offset from the window's TOPLEFT. `h` = window height, `cut` = dead bottom strip of the old frame.
function K.TabOrigin(h, cut) return 14, -(h - (cut or 0)) + 2 end

---------------------------------------------------------------- window
-- A picture for a window / tab: an atlas name (a sprite inside a power-of-two page: its exact texcoords, trimmed by `inset` of its size) or a texture path.
function K.picture(tex, icon, inset)
  local e = AFUI_ATLAS and AFUI_ATLAS[string.lower(icon)]
  inset = inset or 0
  if not e then tex:SetTexture(icon); if inset > 0 then tex:SetTexCoord(inset, 1 - inset, inset, 1 - inset) end; return end
  local du, dv = (e[5] - e[4]) * inset, (e[7] - e[6]) * inset
  tex:SetTexture(e[1]); tex:SetTexCoord(e[4] + du, e[5] - du, e[6] + dv, e[7] - dv)
end
-- o = { icon = texture path, title = name of the title FontString, close = name of the close button, hide = { frame names whose art goes },
--       cut = px of the old frame below the metal frame (2.4.3's 512 px frames have 62 spare), w / h = size drawn (default: the frame's own) }
function K.window(frame, o)
  local P = kit()
  if not frame or frame.afWin or not P then return frame and frame.afWin end
  local w, h = o.w or frame:GetWidth(), o.h or frame:GetHeight()
  frame.afWin = { w = w, h = h, cut = o.cut or 0 }
  P.hideRegions(frame)
  for _, n in ipairs(o.hide or {}) do local f = g(n); if f and f.Hide then f:Hide() end end
  for _, k in ipairs(o.keys or {}) do local f = rawget(frame, k); if type(f) == "table" and f.Hide then f:Hide() end end -- ButtonFrameTemplate parts (2.5.3)
  -- chrome resizes the frame to the metal frame's height (h - cut), so the stone (anchored to the frame's bottom) and the hit rect already stop there
  P.chrome(frame, w, h - frame.afWin.cut, true)
  if o.icon then K.picture(frame.afPortrait, o.icon) end
  local title = g(o.title)
  if title then
    title:SetParent(frame.afLabels); title:ClearAllPoints(); title:SetPoint("TOP", frame, "TOP", 0, -6); title:SetFontObject(GameFontNormal)
  end
  local close = g(o.close)
  if close then P.closeButton(close, frame) end
  return frame.afWin
end

---------------------------------------------------------------- red button (Forever's 128-RedButton, three slices at the button's height)
-- The sprites are 128 px tall: left 114 wide, right 292 wide (red body, then the end cap), the centre a 64 px tile that fills the rest. We draw their half-size
-- copies (@half in tools/atlas-list.txt: the client's TGAs have no mipmaps, so a quarter-scale draw aliased the thin bevel and dulled it): 57 / 146 / 32 by 64.
-- At a button's height h every piece is scaled by h / 128 (ThreeSliceButtonMixin:UpdateScale), so the caps keep their proportions. Forever's UIPanelButtonTemplate
-- is 28 tall (Edit Mode docs: 220x28; the Add Friend capture measures 28 as well), so 28 is the default. A button too narrow for 114 + 292 pieces keeps the left
-- piece and shows only the last part of the right one (its cap), never a squashed copy. Drawing the right piece at the left piece's width squeezed its 292 px
-- into 20 and drew a doubled, cut end cap (Mat's Game Menu / Add Friend shots).
K.RED = { left = 57, right = 146, tall = 64, tile = 32, minRight = 28, height = 28 }
local SPRITE = { left = "128-redbutton-left@half", right = "128-redbutton-right@half", center = "_128-redbutton-center@half", hl = "128-redbutton-highlight@half" }
function K.RedSlices(w, h)
  local k = h / K.RED.tall
  local lw, rw = K.RED.left * k, K.RED.right * k
  if lw + rw > w then
    rw = w - lw
    local least = K.RED.minRight * k
    if rw < least then rw = least; lw = math.max(w - rw, 0) end -- very narrow: the left piece gives way too
    if lw + rw > w then rw = w - lw end
  end
  return lw, rw, rw / (K.RED.right * k) -- the fraction of the right sprite shown (its end)
end

K.PRESS = { 1, -1 } -- the label's offset while pressed (btn.afPress overrides it)
function K.sprite(piece, sfx) -- "-pressed" / "-disabled" sit before @half; the centre keeps its leading underscore
  local n = SPRITE[piece]
  return sfx == "" and n or (n:gsub("@half$", "") .. sfx .. "@half")
end

local function setAtlasEnd(tex, name, frac, left) -- the last (or first) `frac` of a sprite
  AFUI.SetAtlas(tex, name)
  local e = AFUI_ATLAS and AFUI_ATLAS[string.lower(name)]
  if e and frac and frac < 1 then
    local u = e[5] - e[4]
    if left then tex:SetTexCoord(e[4], e[4] + u * frac, e[6], e[7]) else tex:SetTexCoord(e[5] - u * frac, e[5], e[6], e[7]) end
  end
end

-- Hide every piece the client's own button template draws (Left / Middle / Right by key or name, any other texture region, the four state textures), so only our
-- slices show. Alpha stays 0 as well as Hide: the client's enable / disable code Shows its pieces again.
local function quiet(t) if t and t.SetAlpha then t:SetAlpha(0); if t.Hide then t:Hide() end end end
function K.strip(btn)
  local n = btn.GetName and btn:GetName()
  for _, s in ipairs({ "Left", "Middle", "Right", "Center" }) do
    local t = rawget(btn, s); if type(t) == "table" then quiet(t) end
    if n then quiet(g(n .. s)) end
  end
  for _, r in ipairs({ btn:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "Texture" and not r.afOwn then quiet(r) end
  end
  for _, set in ipairs({ "SetNormalTexture", "SetPushedTexture", "SetDisabledTexture", "SetHighlightTexture" }) do btn[set](btn, "") end
  for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do quiet(btn[get] and btn[get](btn)) end
end

function K.button(btn, w, h, white)
  local P = kit()
  if not btn or not P then return end
  if btn.afArt then if w then btn:SetWidth(w) end; return end
  K.strip(btn)
  if w then btn:SetWidth(w) end
  btn:SetHeight(h or K.RED.height)
  btn.afWhite = white
  local a = {}
  btn.afArt = a
  local function mk(layer, name) local t = P.atlasTex(btn, layer, name); t.afOwn = true; return t end
  a.l, a.r, a.tiles = mk("BACKGROUND", SPRITE.left), mk("BACKGROUND", SPRITE.right), {}
  a.hl = mk("HIGHLIGHT", SPRITE.hl); a.hl:SetAllPoints(btn); a.hl:SetBlendMode("ADD"); a.hl:SetAlpha(0.5)
  local state = { down = false, over = false }
  local function paint()
    local width, height = btn:GetWidth(), btn:GetHeight()
    if not width or width <= 0 then width = w or 96 end
    if not height or height <= 0 then height = h or K.RED.height end
    local lw, rw, frac = K.RedSlices(width, height)
    a.l:ClearAllPoints(); a.l:SetPoint("TOPLEFT", btn, "TOPLEFT"); a.l:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT"); a.l:SetWidth(lw)
    a.r:ClearAllPoints(); a.r:SetPoint("TOPRIGHT", btn, "TOPRIGHT"); a.r:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT"); a.r:SetWidth(rw)
    local enabled = btn:IsEnabled() and true or false
    local sfx = not enabled and "-disabled" or (state.down and "-pressed" or "")
    AFUI.SetAtlas(a.l, K.sprite("left", sfx)); setAtlasEnd(a.r, K.sprite("right", sfx), frac)
    -- the centre ("_" atlases tile horizontally) repeats at the same scale as the caps; stretching it made its border differ from theirs
    local tw, cw, n = K.RED.tile * height / K.RED.tall, width - lw - rw, 0
    if tw > 0 and cw > 0.01 then n = math.min(math.ceil(cw / tw - 0.001), 40) end
    for i = 1, math.max(n, #a.tiles) do
      local t = a.tiles[i]
      if i > n then if t then t:Hide() end
      else
        if not t then t = mk("BACKGROUND", SPRITE.center); a.tiles[i] = t end
        local x = (i - 1) * tw
        t:ClearAllPoints(); t:SetPoint("TOPLEFT", a.l, "TOPLEFT", lw + x, 0); t:SetPoint("BOTTOMLEFT", a.l, "BOTTOMLEFT", lw + x, 0)
        t:SetWidth(math.min(tw, cw - x)); t:Show()
        setAtlasEnd(t, K.sprite("center", sfx), math.min(1, (cw - x) / tw), true)
      end
    end
    a.c = a.tiles[1]
    a.state = sfx
    local t = type(btn.text) == "table" and btn.text or btn:GetFontString() -- Edit Mode's own buttons keep their label in .text
    if t then
      local press = btn.afPress or K.PRESS
      t:SetFontObject(not enabled and GameFontDisable or ((btn.afWhite or state.over) and GameFontHighlight or GameFontNormal))
      t:ClearAllPoints(); t:SetPoint("CENTER", btn, "CENTER", (state.down and enabled) and press[1] or 0, (state.down and enabled) and press[2] or 0)
    end
  end
  a.paint = paint
  paint()
  for _, fn in ipairs({ "Enable", "Disable", "SetEnabled", "SetWidth", "SetHeight", "SetSize" }) do
    if type(btn[fn]) == "function" then hooksecurefunc(btn, fn, paint) end
  end
  btn:HookScript("OnMouseDown", function() state.down = true; paint() end)
  btn:HookScript("OnMouseUp", function() state.down = false; paint() end)
  btn:HookScript("OnEnter", function() state.over = true; paint() end)
  btn:HookScript("OnLeave", function() state.over = false; state.down = false; paint() end)
  btn:HookScript("OnShow", function() K.strip(btn); paint() end) -- the template re-shows its own pieces on some enable / skin calls
end

---------------------------------------------------------------- bottom tabs
local tabs, sides = {}, {}
function K.refreshTabs()
  for _, t in ipairs(sides) do
    local on = K.TabState(t.btn:IsEnabled(), t.btn.afActive) == "active"
    if on then t.sel:Show() else t.sel:Hide() end
    t.btn:SetWidth(55); t.btn:SetAlpha(1)
  end
  for _, t in ipairs(tabs) do
    local active = K.TabState(t.btn:IsEnabled(), t.btn.afActive) == "active"
    local k = active and "activetab" or "tab"
    AFUI.SetAtlas(t.l, "uiframe-" .. k .. "-left"); AFUI.SetAtlas(t.r, "uiframe-" .. k .. "-right"); AFUI.SetAtlas(t.m, "_uiframe-" .. k .. "-center")
    local fs = t.btn:GetFontString()
    if fs then fs:SetFontObject(active and GameFontHighlight or GameFontNormal) end
    t.btn:SetAlpha(1)
  end
end

-- Re-skin the client's PanelTemplates tab buttons (names) and line them up under the window; the first at the TabOrigin.
function K.tabs(frame, names, h, cut, top, keep)
  local P = kit()
  if not P then return end
  local prev
  for _, n in ipairs(names) do
    local b = g(n)
    if b and not b.afTab then
      b.afTab = true
      for _, s in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
        local t = g(n .. s); if t then t:SetAlpha(0) end -- the client's SelectTab shows its own: alpha stays down
      end
      local hl = b:GetHighlightTexture(); if hl then hl:SetAlpha(0) end
      b:SetHeight(30)
      local t = { btn = b }
      t.l = P.atlasTex(b, "BACKGROUND", "uiframe-tab-left", 30, 30); t.r = P.atlasTex(b, "BACKGROUND", "uiframe-tab-right", 30, 30); t.m = P.atlasTex(b, "BACKGROUND", "_uiframe-tab-center")
      t.l:SetPoint("TOPLEFT", b, "TOPLEFT"); t.r:SetPoint("TOPRIGHT", b, "TOPRIGHT")
      t.m:SetPoint("TOPLEFT", t.l, "TOPRIGHT"); t.m:SetPoint("BOTTOMRIGHT", t.r, "BOTTOMLEFT")
      tabs[#tabs + 1] = t
      if not keep then b:SetFrameLevel(frame:GetFrameLevel() + 12) end
      local fs = b:GetFontString(); if fs then fs:ClearAllPoints(); fs:SetPoint("CENTER", b, "CENTER", 0, -1) end
    end
    if b and not keep then
      b:ClearAllPoints()
      if prev then b:SetPoint("LEFT", prev, "RIGHT", -2, 0)
      elseif top then b:SetPoint("TOPLEFT", frame, "TOPLEFT", top[1], top[2])
      else local x, y = K.TabOrigin(h, cut); b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y) end
      prev = b
    end
  end
  K.refreshTabs()
end

for _, fn in ipairs({ "PanelTemplates_SetTab", "PanelTemplates_UpdateTabs", "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab" }) do
  if type(_G[fn]) == "function" then hooksecurefunc(fn, function() K.refreshTabs() end) end
end

---------------------------------------------------------------- side tabs (Forever's window tab strip on the right edge, 55 px apart by 57)
function K.SideTabPos(index) return 0, -60 - (index - 1) * 57 end
-- Turn the client's own tab button into a side tab with an icon; selected = the client disabled it (PanelTemplates_SelectTab) or afActive.
function K.sideTab(btn, host, index, icon, tip)
  local P = kit()
  if not btn or btn.afSide or not P then return end
  btn.afSide = true
  local n = btn:GetName()
  for _, s in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do local t = g(n .. s); if t then t:SetAlpha(0) end end
  local hl = btn:GetHighlightTexture(); if hl then hl:SetAlpha(0) end
  if btn:GetFontString() then btn:SetText("") end -- the tab label (the tooltip carries the name); alpha alone left "Looking For Group" drawn beside the LFG tabs in the real client
  for _, fs in ipairs({ btn:GetFontString() or false, btn.Text or false, g(n .. "Text") or false }) do if type(fs) == "table" and fs.SetAlpha then fs:SetAlpha(0); fs:Hide() end end
  btn:SetWidth(55); btn:SetHeight(55); btn:SetFrameLevel(host:GetFrameLevel() + 20)
  local x, y = K.SideTabPos(index)
  btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", host, "TOPRIGHT", x, y)
  local t = { btn = btn }
  t.bg = P.atlasTex(btn, "BACKGROUND", "common-sidetab-c60", 55, 60); t.bg:SetPoint("CENTER", btn, "CENTER")
  t.icon = btn:CreateTexture(nil, "ARTWORK"); t.icon:SetWidth(38); t.icon:SetHeight(38); t.icon:SetPoint("CENTER", btn, "CENTER", -4, 0)
  K.picture(t.icon, icon, 0.07)
  t.sel = P.atlasTex(btn, "OVERLAY", "common-sidetab-selected-c60", 55, 60); t.sel:SetPoint("CENTER", btn, "CENTER"); t.sel:Hide()
  t.hover = P.atlasTex(btn, "HIGHLIGHT", "common-sidetab-hover-c60", 55, 60); t.hover:SetPoint("CENTER", btn, "CENTER")
  btn:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(tip, 1, 1, 1); GameTooltip:Show() end)
  btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
  sides[#sides + 1] = t
  K.refreshTabs()
end

-- The side tab's picture shape (common-sidetab-mask-c60: 45 x 44 inside the 55 x 60 plate, both right corners cut by 7 px): rows of the rectangle, one per
-- cut row so the diagonal is a 1 px staircase (a square icon poked out of the plate's corners).
K.TAB_ICON = { w = 45, h = 44, cut = 7, dx = -3 }
function K.ChamferRects(w, h, cut)
  local out = {}
  for i = 0, cut - 1 do out[#out + 1] = { 0, i, w - cut + i, i + 1 } end
  out[#out + 1] = { 0, cut, w, h - cut }
  for j = 0, cut - 1 do out[#out + 1] = { 0, h - cut + j, w - j - 1, h - cut + j + 1 } end
  return out
end
-- A picture of the side tab's shape on `btn`, centred like the plate; returns the logical texture (SetTexture / SetTexCoord / SetPortraitTexture-by-PortraitUnit work on it).
function K.tabIcon(btn, layer)
  local S = K.TAB_ICON
  local t = btn:CreateTexture(nil, layer or "ARTWORK")
  t:SetWidth(S.w); t:SetHeight(S.h); t:SetPoint("CENTER", btn, "CENTER", S.dx, 0)
  if AFUI.ClipTexture then AFUI.ClipTexture(btn, t, K.ChamferRects(S.w, S.h, S.cut), layer or "ARTWORK") end
  return t
end

---------------------------------------------------------------- dropdown (UIDropDownMenuTemplate)
-- A bar from an atlas piece without stretching its art: the two end caps keep their pixel size, only a flat sample of the middle is stretched. One texture over
-- the whole bar stretched the arrow and the bevel (the real client's dropdowns are wider than the preview's). Columns are pixels of the 97 px piece.
K.BAR = { atlas = "common-dropdown-b-button-c60", capL = 10, capR = 27, midA = 30, midB = 60 }
function K.BarCoords(e, from, to) -- u range of pixel columns from..to of atlas entry e = { file, w, h, u0, u1, v0, v1 }
  local u = (e[5] - e[4]) / e[2]
  return e[4] + from * u, e[4] + to * u, e[6], e[7]
end
function K.bar(parent, layer, o)
  local P = kit()
  o = o or K.BAR
  local e = AFUI_ATLAS and AFUI_ATLAS[string.lower(o.atlas)]
  local l, m, r = P.atlasTex(parent, layer, o.atlas), P.atlasTex(parent, layer, o.atlas), P.atlasTex(parent, layer, o.atlas)
  if e then
    l:SetTexCoord(K.BarCoords(e, 0, o.capL)); m:SetTexCoord(K.BarCoords(e, o.midA, o.midB)); r:SetTexCoord(K.BarCoords(e, e[2] - o.capR, e[2]))
  end
  l:SetWidth(o.capL); r:SetWidth(o.capR)
  return { l = l, m = m, r = r, place = function(_, host, x1, y1, x2, y2)
    l:SetPoint("TOPLEFT", host, "TOPLEFT", x1, y1); l:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", x1, y2)
    r:SetPoint("TOPRIGHT", host, "TOPRIGHT", x2, y1); r:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", x2, y2)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  end }
end
-- The client resizes Left / Middle / Right in UIDropDownMenu_SetWidth: they go invisible. The client's arrow button stays clickable but its square art goes
-- (the bar carries Forever's gold arrow).
function K.dropdown(dd)
  local P = kit()
  if not dd or dd.afDrop or not P then return end
  dd.afDrop = true
  local n = dd:GetName()
  for _, s in ipairs({ "Left", "Middle", "Right" }) do local t = g(n .. s); if t then t:SetAlpha(0) end end
  dd.afBar = K.bar(dd, "BACKGROUND")
  dd.afBar:place(dd, 16, -2, -16, 4)
  local btn = g(n .. "Button")
  if btn then
    for _, k in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
      local t = btn[k] and btn[k](btn)
      if t then t:SetAlpha(0) end
    end
  end
  local text = g(n .. "Text")
  if text then text:SetFontObject(GameFontNormalSmall) end
end

---------------------------------------------------------------- column header (WhoFrameColumnHeader1-4, GuildFrameColumnHeader1-4, LFMFrameColumnHeader1-4)
function K.header(btn)
  local P = kit()
  if not btn or btn.afHead or not P then return end
  btn.afHead = true
  local n = btn:GetName()
  for _, s in ipairs({ "Left", "Middle", "Right" }) do local t = g(n .. s); if t then t:SetAlpha(0) end end
  local bg = P.atlasTex(btn, "BACKGROUND", "profession-tab-c60")
  bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -1); bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 1)
  btn:SetHighlightTexture("")
  AFUI.SetButtonAtlas(btn, { nil, nil, "profession-tab-glow-c60" })
  local fs = btn:GetFontString(); if fs then fs:SetFontObject(GameFontNormal) end
end

---------------------------------------------------------------- inner panel (GuildInfoFrame, GuildMemberDetailFrame, popups ...)
function K.panel(f)
  if not f or f.afPanel then return end
  f.afPanel = true
  local P = kit()
  P.hideRegions(f)
  if f.SetBackdrop then f:SetBackdrop(nil) end
  -- The bronze rim is four 1 px rules on the BORDER layer over the Rock fill: a full-size colour behind the fill in the same layer was drawn
  -- over it by the 2.5.3 client (same-layer order is not creation order), which left the whole panel flat olive.
  for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local edge = f:CreateTexture(nil, "BORDER"); AFUI.SetColor(edge, 0.45, 0.37, 0.2, 1)
    edge:SetPoint(e[1], f, e[1], 0, 0); edge:SetPoint(e[2], f, e[2], 0, 0)
    if e[3] then edge:SetHeight(1) else edge:SetWidth(1) end
  end
  local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetTexture("Interface\\AddOns\\AztraForeverUI\\Media\\plain\\UI-Background-Rock")
  bg:SetVertexColor(P.ROCK_TINT[1], P.ROCK_TINT[2], P.ROCK_TINT[3]); bg:SetAllPoints(f)
  if not (type(bg.SetHorizTile) == "function") then bg:SetTexCoord(0, 0.6, 0, 0.6) end
end

---------------------------------------------------------------- checkbox (Forever's minimal box with the gold tick)
function K.check(cb)
  if not cb or cb.afCheck then return end
  cb.afCheck = true
  cb:SetNormalTexture(""); cb:SetPushedTexture(""); cb:SetDisabledTexture(""); cb:SetHighlightTexture("")
  AFUI.SetButtonAtlas(cb, { "checkbox-minimal", "checkbox-minimal", "checkbox-minimal", "checkbox-minimal" }, 0.5)
  cb:SetCheckedTexture("Interface\\AddOns\\AztraForeverUI\\Media\\plain\\UI-CheckBox-Check")
end

---------------------------------------------------------------- chat input
-- The chat input keeps the client's ornate frame art (UI-ChatInputBorder-Left2 / Mid2 / Right2) in every state, tinted bronze: Blizzard leaves the
-- frame silver when idle and swaps it for a plain outline (the focus art, coloured by chat type) while typing, so the focus art goes and the ornate
-- frame is put back (shown, full alpha, bronze) whenever the box is shown, focused, unfocused or recoloured.
K.BRONZE = { 0.85, 0.62, 0.32 }
local function bronzeEdit(box)
  local n = box:GetName()
  for _, k in ipairs({ "Left", "Mid", "Right" }) do
    local t = g(n .. k)
    if t then t:SetVertexColor(K.BRONZE[1], K.BRONZE[2], K.BRONZE[3]); t:SetAlpha(1); t:Show() end
  end
  for _, k in ipairs({ "FocusLeft", "FocusMid", "FocusRight" }) do local t = g(n .. k); if t then t:SetAlpha(0) end end
end
function K.chatEdit(box)
  if not box or box.afChatEdit then return false end
  box.afChatEdit = true
  bronzeEdit(box)
  for _, e in ipairs({ "OnShow", "OnEditFocusGained", "OnEditFocusLost" }) do box:HookScript(e, bronzeEdit) end
  if type(_G.ChatEdit_UpdateHeader) == "function" then hooksecurefunc("ChatEdit_UpdateHeader", function(eb) if eb == box then bronzeEdit(box) end end) end
  return true
end

---------------------------------------------------------------- search / text box
function K.edit(box)
  local P = kit()
  if not box or box.afEdit or not P then return end
  box.afEdit = true
  local n = box:GetName()
  for _, s in ipairs({ "Left", "Middle", "Right" }) do local t = g(n .. s); if t then t:SetAlpha(0) end end
  local l = P.atlasTex(box, "BACKGROUND", "common-search-border-left-c60"); l:SetPoint("TOPLEFT", box, "TOPLEFT", -4, 5); l:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -4, -5); l:SetWidth(8)
  local r = P.atlasTex(box, "BACKGROUND", "common-search-border-right-c60"); r:SetPoint("TOPRIGHT", box, "TOPRIGHT", 4, 5); r:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 4, -5); r:SetWidth(8)
  local m = P.atlasTex(box, "BACKGROUND", "common-search-border-middle-c60"); m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  box:SetTextInsets(8, 8, 0, 0)
end

---------------------------------------------------------------- list row hover (Forever's recipe row glow)
function K.row(btn)
  if not btn or btn.afRowSkin then return end
  btn.afRowSkin = true
  AFUI.SetButtonAtlas(btn, { nil, nil, "professions_recipe_hover" }, 0.5)
  local ht = btn:GetHighlightTexture()
  if ht then ht:ClearAllPoints(); ht:SetAllPoints(btn) end
end

---------------------------------------------------------------- scroll bar: Forever's minimal bar, ONE component for every list
-- Layout (top to bottom, all of the list's height): up chevron 17x11 | 2 px | track (8 px groove: 8 px cap, 1 px strip stretched, 8 px cap) with the thumb
-- inside it (8 px rounded cap, middle cut to the exact texel count, 8 px cap turned over) | 2 px | down chevron. The thumb never leaves the track: its
-- offset is 0..(track - length). Smooth scrolling: wheel / arrows / track clicks set a TARGET and an OnUpdate (attached only while it moves) eases the
-- shown offset to it; dragging the thumb is immediate.
K.SB = { W = 17, ARROW = 11, GAP = 2, CAP = 8, MIN_THUMB = 24, MARGIN = 1, SPEED = 18, MAX_TIME = 0.25, REPEAT_AFTER = 0.35, REPEAT_EVERY = 0.08 }
K.bars = {} -- every bar built (the audit walks it)

-- Thumb length and top offset (px) for scroll `value` of 0..max, `view` visible units in the same unit as max, over a track of `track` px.
-- `es` (the effective scale, optional): length and offset land on whole screen pixels and never add up to more than `track` (floored), so the thumb
-- stays strictly inside its track at fractional UI scales.
function K.ScrollThumb(value, max, view, track, minLen, es)
  if not (es and es > 0) then es = nil end
  local function snap(v) return es and math.floor(v * es + 0.5) / es or v end
  if es then track = math.floor(track * es + 1e-6) / es end
  if track <= 0 then return 0, 0 end
  minLen = math.min(minLen or K.SB.MIN_THUMB, track)
  if max <= 0 then return track, 0 end
  local len = math.min(track, math.max(minLen, snap(math.min(track, track * view / (view + max)))))
  local off = snap((track - len) * math.max(0, math.min(1, value / max)))
  return len, math.max(0, math.min(off, track - len))
end
-- The scroll value a thumb dragged to `off` px from the track top stands for.
function K.ScrollValue(off, len, track, max)
  local r = track - len
  if r <= 0 or max <= 0 then return 0 end
  return math.max(0, math.min(max, off / r * max))
end
-- One easing step (critically damped exponential): returns the new offset and whether it landed on the target.
function K.ScrollEase(cur, target, dt, eps)
  local nxt = cur + (target - cur) * (1 - math.exp(-dt * K.SB.SPEED))
  if math.abs(target - nxt) <= eps then return target, true end
  return nxt, false
end

local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
-- a sprite's texcoords pulled in half a texel at the sides (and the ends when `ends`): the atlas page packs its sprites edge to edge, so a
-- fractional UI scale samples the neighbour's texel into the edge otherwise
local function inset(t, name, ends, flipV)
  local a = AFUI_ATLAS and AFUI_ATLAS[name]
  if not a then return end
  local h = (a[5] - a[4]) / a[2] / 2
  local v = ends and (a[7] - a[6]) / a[3] / 2 or 0
  local top, bot = a[6] + v, a[7] - v
  if flipV then top, bot = bot, top end
  t:SetTexCoord(a[4] + h, a[5] - h, top, bot)
end
local function texW(name, d) local a = AFUI_ATLAS and AFUI_ATLAS[name]; return a and a[2] or d end

-- list = the frame the bar is flush with (top and bottom edge, 17 px wide at its right). m = the model:
--   get() offset, set(v), max() the range (offset units, 0 = fits), view() the visible extent (same units), step = units per wheel notch / arrow click,
--   page (default view - step), quantum (set() only takes multiples: Faux rows), integer, eps (settle distance, default 0.5 unit).
-- o = { parent, x = gap right of the list (3), place = function(bar) (own anchors), wheel = { extra frames }, smooth = false (no easing), alwaysShow }
function K.scrollbar(list, m, o)
  o = o or {}
  local SB = K.SB
  local function atlasTex(parent, layer, name, w, h)
    local t = parent:CreateTexture(nil, layer)
    if AFUI.SetAtlas then AFUI.SetAtlas(t, name) end
    if w then t:SetWidth(w); t:SetHeight(h or w) end
    return t
  end
  local bar = CreateFrame("Frame", nil, o.parent or list)
  bar:SetWidth(SB.W)
  if o.place then o.place(bar)
  else bar:SetPoint("TOPLEFT", list, "TOPRIGHT", o.x or 3, 0); bar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", o.x or 3, 0) end
  bar.afScrollbar, bar.list, bar.fit, bar.model, bar.cur, bar.target = true, list, o.fit or list, m, 0, 0
  K.bars[#K.bars + 1] = bar
  local smooth = o.smooth ~= false

  local function arrow(which)
    local b = CreateFrame("Button", nil, bar)
    b:SetWidth(SB.W); b:SetHeight(SB.ARROW)
    b:SetPoint(which == "top" and "TOP" or "BOTTOM", bar, which == "top" and "TOP" or "BOTTOM", 0, 0)
    local n = "minimal-scrollbar-arrow-" .. which
    AFUI.SetButtonAtlas(b, { n .. "-c60", n .. "-over-c60", n .. "-over-c60" }, 0.5)
    b.art = n .. "-c60"
    return b
  end
  local up, down = arrow("top"), arrow("bottom")
  local track = CreateFrame("Button", nil, bar)
  track:SetWidth(SB.W)
  track:SetPoint("TOP", bar, "TOP", 0, -(SB.ARROW + SB.GAP)); track:SetPoint("BOTTOM", bar, "BOTTOM", 0, SB.ARROW + SB.GAP)
  -- every width is the sprite's own texel width (8), never a guess: art given a different width is cropped or stretched
  local W = texW("minimal-scrollbar-thumb-middle-c60", SB.CAP)
  local tTop = atlasTex(track, "BACKGROUND", "minimal-scrollbar-track-top-c60", W, SB.CAP); tTop:SetPoint("TOP", track, "TOP"); inset(tTop, "minimal-scrollbar-track-top-c60", true)
  local tBot = atlasTex(track, "BACKGROUND", "minimal-scrollbar-track-bottom-c60", W, SB.CAP); tBot:SetPoint("BOTTOM", track, "BOTTOM"); inset(tBot, "minimal-scrollbar-track-bottom-c60", true)
  local tMid = atlasTex(track, "BACKGROUND", "!minimal-scrollbar-track-middle-c60"); tMid:SetWidth(W); inset(tMid, "!minimal-scrollbar-track-middle-c60")
  tMid:SetPoint("TOP", tTop, "BOTTOM"); tMid:SetPoint("BOTTOM", tBot, "TOP")
  local thumb = CreateFrame("Button", nil, track)
  thumb:SetWidth(W); thumb:SetHeight(SB.MIN_THUMB)
  local hTop = atlasTex(thumb, "ARTWORK", "minimal-scrollbar-thumb-top-c60", W, SB.CAP); hTop:SetPoint("TOP", thumb, "TOP"); inset(hTop, "minimal-scrollbar-thumb-top-c60", true)
  local hBot = atlasTex(thumb, "ARTWORK", "minimal-scrollbar-thumb-top-c60", W, SB.CAP); hBot:SetPoint("BOTTOM", thumb, "BOTTOM") -- the top cap turned over
  inset(hBot, "minimal-scrollbar-thumb-top-c60", true, true)
  local hMid = thumb:CreateTexture(nil, "ARTWORK"); hMid:SetWidth(W)
  hMid:SetPoint("TOP", hTop, "BOTTOM"); hMid:SetPoint("BOTTOM", hBot, "TOP")
  bar.up, bar.down, bar.track, bar.thumb = up, down, track, thumb
  bar.pieces = { tTop, tMid, tBot, hTop, hMid, hBot }

  -- the track's own height wins (what is drawn): the bar's / list's heights are only the fallback while the client has not laid it out yet
  local function height()
    local t, b = track:GetTop(), track:GetBottom()
    if type(t) == "number" and type(b) == "number" and t - b > 0 then return t - b + 2 * (SB.ARROW + SB.GAP) end
    local h = bar:GetHeight()
    if not h or h <= 0 then h = list:GetHeight() or 0 end
    return h
  end
  local function es() local s = track:GetEffectiveScale(); return type(s) == "number" and s > 0 and s or nil end
  -- the room the thumb has: the track less a margin at both ends, so it rests inside the groove, never on its rim or the chevron
  function bar:TrackLen() return math.max(0, height() - 2 * (SB.ARROW + SB.GAP) - 2 * SB.MARGIN) end
  function bar:Max() return math.max(0, m.max() or 0) end
  function bar:Eps() return m.eps or 0.5 end
  function bar:Step() return m.step or 20 end

  -- the middle of the thumb: its sprite cut to the exact texel count (1:1, never stretched), the lit sprite under the mouse
  local function paintThumb(len)
    local n = len - 2 * math.min(SB.CAP, len / 2)
    local a = AFUI_ATLAS and AFUI_ATLAS[bar.hot and "minimal-scrollbar-thumb-middle-over-c60" or "minimal-scrollbar-thumb-middle-c60"]
    if not a then return end
    hMid:SetTexture(a[1])
    local texels = math.min(a[3], (a[7] - a[6]) * 512) -- the sprite's first page part (508 of its 515 rows)
    local h = (a[5] - a[4]) / a[2] / 2
    hMid:SetTexCoord(a[4] + h, a[5] - h, a[6], a[6] + (a[7] - a[6]) * math.min(1, math.max(n, 1) / texels))
    hMid.afuiAtlas = bar.hot and "minimal-scrollbar-thumb-middle-over-c60" or "minimal-scrollbar-thumb-middle-c60"
  end

  function bar:Layout()
    local max, tl = self:Max(), self:TrackLen()
    local on = (max > 0 or o.alwaysShow) and tl > 0
    if on then self:Show() else self:Hide() end
    local len, off = K.ScrollThumb(self.cur, max, m.view() or 0, tl, nil, es())
    self.len, self.off = len, off
    local cap = math.max(math.min(SB.CAP, len / 2), 0.01) -- a thumb shorter than two caps: the caps share it
    hTop:SetHeight(cap); hBot:SetHeight(cap)
    local tcap = math.max(math.min(SB.CAP, (tl + 2 * SB.MARGIN) / 2), 0.01)
    tTop:SetHeight(tcap); tBot:SetHeight(tcap)
    thumb:SetHeight(math.max(len, 1)); thumb:ClearAllPoints(); thumb:SetPoint("TOP", track, "TOP", 0, -(off + SB.MARGIN))
    if max > 0 then thumb:Show() else thumb:Hide() end
    paintThumb(len)
    -- an arrow that cannot go further is grey (Forever's disabled chevron: the same sprite desaturated), all of them dim when the list fits
    local function chevron(b, off)
      local t = b:GetNormalTexture()
      if t and t.SetDesaturated then t:SetDesaturated(off) end
      b:SetAlpha(max <= 0 and 0.4 or (off and 0.8 or 1))
    end
    chevron(up, max <= 0 or self.cur <= 0.5); chevron(down, max <= 0 or self.cur >= max - 0.5)
  end

  function bar:Stop() if self.anim then self.anim = nil; self:SetScript("OnUpdate", nil) end end
  -- show / apply the offset: the model takes it rounded to its quantum
  function bar:Apply(v)
    local max = self:Max()
    self.cur = clamp(v, 0, max)
    local out = self.cur
    if m.quantum and m.quantum > 0 then out = math.floor(out / m.quantum + 0.5) * m.quantum end
    if m.integer then out = math.floor(out + 0.5) end
    out = clamp(out, 0, max)
    if out ~= self.applied then self.applied = out; self.busy = true; m.set(out); self.busy = false end
    self:Layout()
  end
  local function tick(_, dt)
    bar.t = bar.t + dt
    local cur, done = K.ScrollEase(bar.cur, bar.target, dt, bar:Eps())
    if bar.t >= SB.MAX_TIME then cur, done = bar.target, true end
    bar:Apply(cur)
    if done then bar:Stop() end
  end
  function bar:Settle() if self.anim then self:Stop(); self:Apply(self.target) end end
  -- jump = true: immediately (dragging, no easing)
  function bar:ScrollTo(v, jump)
    v = clamp(v, 0, self:Max())
    self.target = v
    if jump or not smooth or math.abs(v - self.cur) <= self:Eps() then self:Stop(); self:Apply(v); return end
    self.t = 0
    if not self.anim then self.anim = true; self:SetScript("OnUpdate", tick) end
  end
  function bar:ScrollBy(d) self:ScrollTo((self.anim and self.target or self.cur) + d) end
  function bar:Wheel(delta) if self:Max() > 0 then self:ScrollBy(-delta * self:Step()) end end
  function bar:Page(dir) self:ScrollBy(dir * (m.page or math.max((m.view() or 0) - self:Step(), self:Step()))) end
  -- the model changed under us (the client scrolled / re-laid its list): take its offset, drop the glide
  function bar:Refresh()
    local max = self:Max()
    if self.busy then self:Layout(); return end -- the model's own update after our set(): keep the (fractional) offset we show
    if self.anim then
      self.target = clamp(self.target, 0, max); self.cur = clamp(self.cur, 0, max)
      if self.target == self.cur then self:Stop() end
    else
      self.applied = nil
      local v = m.get() or 0
      self.cur = clamp(v, 0, max); self.target = self.cur
      if v > max then self:Apply(self.cur) end -- the content shrank under the offset: bring the list back inside its range
    end
    self:Layout()
  end
  function bar:OnModel() if not self.busy then self:Stop(); self:Refresh() end end
  -- a click on the track `off` px below its top: a page towards it (nothing when it lands on the thumb)
  function bar:TrackClick(off)
    off = off - SB.MARGIN
    if off < self.off then self:Page(-1) elseif off > self.off + self.len then self:Page(1) else return false end
    return true
  end

  -- hold to repeat (arrows, track): one action at once, then again every REPEAT_EVERY after REPEAT_AFTER
  local function hold(btn, fn)
    btn:SetScript("OnMouseDown", function(self)
      if bar:Max() <= 0 then return end
      fn(); self.held = -SB.REPEAT_AFTER
      self:SetScript("OnUpdate", function(s, dt)
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then s.held = nil; s:SetScript("OnUpdate", nil); return end
        s.held = s.held + dt
        if s.held >= SB.REPEAT_EVERY then s.held = s.held - SB.REPEAT_EVERY; fn() end
      end)
    end)
    local function release(self) self.held = nil; self:SetScript("OnUpdate", nil) end
    btn:SetScript("OnMouseUp", release); btn:SetScript("OnHide", release)
  end
  hold(up, function() bar:ScrollBy(-bar:Step()) end)
  hold(down, function() bar:ScrollBy(bar:Step()) end)
  local function cursorOff()
    if not (track.GetTop and track:GetTop() and GetCursorPosition) then return nil end
    return track:GetTop() - select(2, GetCursorPosition()) / track:GetEffectiveScale()
  end
  hold(track, function() local off = cursorOff(); if off then bar:TrackClick(off) end end)

  -- the thumb: dragged at once, no easing
  thumb:SetScript("OnEnter", function() bar.hot = true; paintThumb(bar.len or SB.MIN_THUMB) end)
  thumb:SetScript("OnLeave", function() if not bar.drag then bar.hot = false; paintThumb(bar.len or SB.MIN_THUMB) end end)
  thumb:SetScript("OnMouseDown", function(self)
    bar:Stop(); bar:Refresh()
    bar.drag = { y = select(2, GetCursorPosition()) / self:GetEffectiveScale(), off = bar.off }
    bar.hot = true; paintThumb(bar.len)
    self:SetScript("OnUpdate", function(s)
      if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then bar.drag = nil; s:SetScript("OnUpdate", nil); return end
      local dy = bar.drag.y - select(2, GetCursorPosition()) / s:GetEffectiveScale()
      bar:ScrollTo(K.ScrollValue(bar.drag.off + dy, bar.len, bar:TrackLen(), bar:Max()), true)
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self) bar.drag = nil; bar.hot = false; self:SetScript("OnUpdate", nil); paintThumb(bar.len) end)

  -- the wheel: over the list, the bar and any extra frame
  local function wheel(_, d) bar:Wheel(d) end
  for _, f in ipairs({ list, bar, unpack(o.wheel or {}) }) do
    if f.EnableMouseWheel then f:EnableMouseWheel(true) end
    f:SetScript("OnMouseWheel", wheel)
  end
  bar:SetScript("OnSizeChanged", function() bar:Layout() end)
  track:SetScript("OnSizeChanged", function() bar:Layout() end)
  bar:SetScript("OnShow", function() bar:Refresh() end)
  bar:SetScript("OnHide", function() bar:Settle() end)
  bar:Refresh()
  return bar
end

-- What is wrong with a SHOWN bar, nil when it is right (the in-game audit walks K.bars; the rects are real there): it must lie inside its `fit` frame's
-- height, its thumb inside its track, its arrows and track inside the bar, and every piece must have a size and a sprite.
function K.BarProblem(bar)
  local function scale(f) local s = f and f.GetEffectiveScale and f:GetEffectiveScale(); return type(s) == "number" and s > 0 and s or 1 end
  local tol = math.min(0.75, 0.5 / scale(bar)) -- half a screen pixel (the real scale is fractional: a pixel over is the visible fault)
  local function span(f)
    if not (f and f.GetTop and f.GetBottom) then return end
    local t, b = f:GetTop(), f:GetBottom()
    if type(t) == "number" and type(b) == "number" then return t, b end
  end
  local function within(f, host, what)
    local ft, fb, ht, hb = nil, nil, span(host)
    ft, fb = span(f)
    if ft and ht and (ft > ht + tol or fb < hb - tol) then
      return string.format("%s leaves its frame (%.1f..%.1f outside %.1f..%.1f)", what, fb, ft, hb, ht)
    end
  end
  local why = within(bar, bar.fit, "scroll bar") or within(bar.thumb, bar.track, "thumb") or within(bar.up, bar, "up arrow")
    or within(bar.down, bar, "down arrow") or within(bar.track, bar, "track")
  if why then return why end
  for i, t in ipairs(bar.pieces or {}) do
    local w, h = t:GetWidth(), t:GetHeight()
    if not (tonumber(w) and tonumber(h) and w > 0 and h > 0) then return "scroll bar piece " .. i .. " has no size" end
    if t.GetTexture and t:GetTexture() == nil and not t.afuiAtlas then return "scroll bar piece " .. i .. " has no art" end
    local a = t.afuiAtlas and AFUI_ATLAS and AFUI_ATLAS[t.afuiAtlas]
    if a and math.abs(w - a[2]) > 0.01 then
      return string.format("scroll bar piece %d is %.2f wide for a %d texel sprite (%s)", i, w, a[2], w < a[2] and "cuts its sides" or "stretched")
    end
  end
end

-- The bar of a client slider list (FauxScrollFrame, HybridScrollFrame, ScrollFrame template): the client's slider stays the MODEL (its value and range
-- are what the client's own scripts read and write, so rows keep updating through its official setters); only its art and input are replaced.
-- Faux sliders step by one row (valueStep = row height): the thumb glides while the rows tick over; Hybrid sliders take any pixel: true pixel easing.
function K.scroll(name, o)
  o = o or {}
  local sb = type(name) == "string" and g(name) or name
  if not sb or sb.afBar then return sb and sb.afBar end
  local list = o.list or (sb.GetParent and sb:GetParent())
  if not list then return end
  local function lo() return select(1, sb:GetMinMaxValues()) or 0 end
  local stepv = sb.GetValueStep and sb:GetValueStep() or 0
  local m = {
    get = function() return (sb:GetValue() or 0) - lo() end,
    set = function(v) sb:SetValue(v + lo()) end,
    max = function() return (select(2, sb:GetMinMaxValues()) or 0) - lo() end,
    view = function() return o.view and o.view() or list:GetHeight() or 0 end,
    step = o.step or sb.scrollStep or (stepv >= 1 and stepv * 2) or ((list.buttonHeight or 24) * 2),
    quantum = stepv >= 1 and stepv or nil,
  }
  sb.afBar = K.scrollbar(list, m, { x = o.x, wheel = o.wheel, parent = o.parent or list, place = o.place, alwaysShow = o.alwaysShow, smooth = o.smooth })
  local bar = sb.afBar
  -- the client's own bar: invisible and mouse-blind (its up / down buttons and thumb included), still the model
  sb:SetAlpha(0); if sb.EnableMouse then sb:EnableMouse(false) end
  local nm = sb:GetName()
  for _, s in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
    local b = nm and g(nm .. s); if b and b.EnableMouse then b:EnableMouse(false) end
  end
  if sb.HookScript then
    pcall(sb.HookScript, sb, "OnValueChanged", function() bar:OnModel() end)
    pcall(sb.HookScript, sb, "OnMinMaxChanged", function() bar:Refresh() end)
  end
  if type(hooksecurefunc) == "function" then
    pcall(hooksecurefunc, sb, "SetMinMaxValues", function() bar:Refresh() end)
    pcall(hooksecurefunc, sb, "SetValue", function() bar:OnModel() end)
  end
  return bar
end

-- Style every existing frame of `names` with `fn` (a frame one client lacks is skipped).
function K.each(names, fn)
  for _, n in ipairs(names) do local f = g(n); if f then fn(f) end end
end

---------------------------------------------------------------- left windows: one anchor, one at a time (video 3: Character, Friends, LFG ... all at 24 px / 160 px of a 2560x1440 capture, each closing the last)
K.ORIGIN = { x = 17, y = -116 } -- the TOPLEFT offset in UI units the panel manager gets (24 px / 160 px at the capture's 1.40625 scale)
K.LEFT_WINDOWS = { "CharacterFrame", "SpellBookFrame", "PlayerTalentFrame", "FriendsFrame", "LFGParentFrame", "QuestLogFrame", "TradeSkillFrame", "CraftFrame", "AFUI_ProfessionsFrame" }

-- Showing one of `names` hides the others (HideUIPanel keeps the panel manager's own list straight).
function K.closeOthers(self, names)
  for _, n in ipairs(names or K.LEFT_WINDOWS) do
    local o = g(n)
    if o and o ~= self and o.IsShown and o:IsShown() then
      if type(HideUIPanel) == "function" then HideUIPanel(o) else o:Hide() end
    end
  end
end
-- Frames a client loads later (the talent UI) are picked up on ADDON_LOADED.
-- The window switch of each left window (AddonCompat.lua): a window that is the client's own gets no hook of ours (opening ours still closes it).
K.WINDOW_GROUP = { CharacterFrame = "character", SpellBookFrame = "spellbook", PlayerTalentFrame = "talents", FriendsFrame = "social", LFGParentFrame = "lfg",
  QuestLogFrame = "map", TradeSkillFrame = "professions", CraftFrame = "professions", AFUI_ProfessionsFrame = "professions" }
function K.exclusive(names)
  names = names or K.LEFT_WINDOWS
  for _, n in ipairs(names) do
    local f = g(n)
    local group = K.WINDOW_GROUP[n]
    if f and f.HookScript and not f.afExclusive and (not group or AFUI.ModuleEnabled(group)) then
      f.afExclusive = true
      f:HookScript("OnShow", function(self) K.closeOthers(self, names) end)
    end
  end
end
---------------------------------------------------------------- movable windows
-- One mechanism for every window: drag the title strip with the left mouse button, the spot is kept per character in AztraForeverUICharDB.windowPos[key] =
-- { point, relPoint, x, y } (TOPLEFT of the window from UIParent's BOTTOMLEFT, in UIParent units) and put back every time the window is shown. The panel manager
-- (UIParent.lua UpdateUIPanelPositions) re-anchors panels on show and ignores IsMovable / user placed, so the spot is re-applied after it (hook), on OnShow and
-- once more one frame later (a window's own placer may run after our hook). Nothing here touches a protected frame in combat.
K.KEEP, K.BARH = 40, 22 -- px of the title bar that must stay on the screen
K.movables = {} -- key -> frame (the audit walks it)

-- Pure: the TOPLEFT (left, top from the screen's bottom left) of a w wide window pushed back so that `keep` px of its title bar (`bar` high) stay on screen.
function K.ClampPos(left, top, w, uiW, uiH, keep, bar)
  keep, bar = keep or K.KEEP, bar or K.BARH
  if left + w < keep then left = keep - w end
  if left > uiW - keep then left = uiW - keep end
  if top > uiH then top = uiH end
  if top < bar then top = bar end
  return left, top
end

local function posTable(create)
  local db = AztraForeverUICharDB
  if type(db) ~= "table" then return nil end
  if create and type(db.windowPos) ~= "table" then db.windowPos = {} end
  return db.windowPos
end
function K.SavedPos(key) local t = posTable(); return t and t[key] end

local function locked(frame) return frame.IsProtected and frame:IsProtected() and InCombatLockdown() end

function K.SavePos(frame)
  local left, top = frame:GetLeft(), frame:GetTop()
  local t = posTable(true)
  if not (left and top and t and frame.afMoveKey) then return end
  local s = frame:GetScale() or 1
  left, top = K.ClampPos(left * s, top * s, (frame:GetWidth() or 0) * s, UIParent:GetWidth(), UIParent:GetHeight())
  t[frame.afMoveKey] = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = left, y = top }
end

-- Puts the window where the player left it; false when it has no saved spot (or is being dragged / protected in combat).
function K.applyPos(frame)
  local p = frame.afMoveKey and K.SavedPos(frame.afMoveKey)
  if not (type(p) == "table" and type(p.x) == "number" and type(p.y) == "number") or frame.afMoving or locked(frame) then return false end
  local s = frame:GetScale() or 1
  local x, y = K.ClampPos(p.x, p.y, (frame:GetWidth() or 0) * s, UIParent:GetWidth(), UIParent:GetHeight())
  frame:ClearAllPoints()
  frame:SetPoint(p.point or "TOPLEFT", UIParent, p.relPoint or "BOTTOMLEFT", x / s, y / s)
  return true
end

local pending = {}
local settle = CreateFrame("Frame")
settle:SetScript("OnUpdate", function()
  for f in pairs(pending) do pending[f] = nil; if f:IsShown() then K.applyPos(f) end end
end)
local function reapply(frame) K.applyPos(frame); pending[frame] = true end
K.pending = pending

-- Back to the default spot: the window's own placer (afPlace), else its first anchor, else the panel manager; a plain window with none of those is re-shown.
function K.resetWindows()
  local t = posTable(); if t then for k in pairs(t) do t[k] = nil end end
  for _, f in pairs(K.movables) do
    if not locked(f) then
      local done = false
      if f.afPlace then f.afPlace(f); done = true
      elseif f.afHome then f:ClearAllPoints(); for _, p in ipairs(f.afHome) do f:SetPoint(unpack(p)) end; done = true end
      local panel = _G.UIPanelWindows and f.GetName and _G.UIPanelWindows[f:GetName()]
      if panel and type(_G.UpdateUIPanelPositions) == "function" and f:IsShown() then pcall(_G.UpdateUIPanelPositions, f); done = true end
      if not done and f:IsShown() then f:Hide(); f:Show() end
    end
  end
end

-- handles: a frame, a list of frames, or nil for the default title strip (58 px from the left, 62 from the right, 20 high). opts.place = fn(frame) putting it at its default spot.
function K.makeMovable(frame, handles, key, opts)
  key = key or (frame and frame.GetName and frame:GetName())
  if not frame or not key then return end
  if frame.afMoveKey then return frame end
  frame.afMoveKey = key
  frame.afPlace = opts and opts.place
  K.movables[key] = frame
  frame:SetMovable(true); frame:SetClampedToScreen(true)
  local n = frame.GetNumPoints and frame:GetNumPoints()
  if type(n) == "number" and n > 0 then
    frame.afHome = {}
    for i = 1, n do frame.afHome[i] = { frame:GetPoint(i) } end
  end
  if handles == nil then
    local h = CreateFrame("Frame", nil, frame)
    h:SetPoint("TOPLEFT", frame, "TOPLEFT", 58, 0); h:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -62, 0); h:SetHeight(20)
    h:SetFrameLevel(frame:GetFrameLevel() + 24)
    handles = { h }
  elseif type(handles.RegisterForDrag) == "function" then handles = { handles } end
  frame.afHandles = handles
  for _, h in ipairs(handles) do
    h:EnableMouse(true); h:RegisterForDrag("LeftButton")
    h:HookScript("OnDragStart", function()
      if locked(frame) or (InCombatLockdown and InCombatLockdown()) then return end -- windows carry secure children: no moving in combat
      frame:StartMoving(); frame.afMoving = true
    end)
    h:HookScript("OnDragStop", function()
      if not frame.afMoving then return end
      frame.afMoving = nil
      frame:StopMovingOrSizing()
      if frame.SetUserPlaced then frame:SetUserPlaced(false) end -- ours to remember, not the client's layout cache
      K.SavePos(frame); K.applyPos(frame)
    end)
    h:HookScript("OnMouseUp", function(self, button) -- Shift + double click: every window back to its default spot
      local shift = button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown()
      local t = GetTime()
      if shift and self.afLast and t - self.afLast < 0.4 then self.afLast = nil; K.resetWindows()
      else self.afLast = shift and t or nil end
    end)
  end
  frame:HookScript("OnShow", function() reapply(frame) end)
  if frame.IsShown and frame:IsShown() then reapply(frame) end
  return frame
end

if type(_G.UpdateUIPanelPositions) == "function" then
  hooksecurefunc("UpdateUIPanelPositions", function() for _, f in pairs(K.movables) do if f:IsShown() then reapply(f) end end end)
end

if AFUI.RegisterModule then
  AFUI.RegisterModule("WinKit", { OnLogin = function() K.exclusive() end })
  AFUI.On("ADDON_LOADED", function() K.exclusive() end)
end
