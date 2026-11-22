-- Shared setup of the NPC windows (Merchant, Trainer, Mail, Auction House): Forever's metal portrait frame over the client's own frame (WinKit.window), red
-- buttons, bottom tabs, search boxes, check boxes, column headers, minimal scroll bars, dark plates behind list rows, the window movable and placed at Forever's
-- left-window origin. Nothing of Blizzard's is replaced: art is hidden / re-skinned with hooksecurefunc / HookScript, every click, drag, tooltip and update stays
-- the client's code (none of these frames is protected, but nothing here runs in combat anyway: AFUI.RunOutOfCombat).
-- A spec is plain data (frame names verified against Gethe/wow-ui-source tag 2.5.3 Interface_TBC / Interface FrameXML and the Blizzard_TrainerUI / Blizzard_AuctionUI addons):
--   frame, title (FontString name), close (button name), size = { w, h, cut } (+ size243), icon, npc (portrait shows the NPC), move (saved spot key),
--   hide / bare (frames whose own art goes / whose texture regions go), tabs, buttons, edits, checks, headers, dropdowns, scrolls, rows (names), plates.
AFUI = AFUI or {}
local N = {}
AFUI.NpcKit = N

local function g(name) return name and _G[name] end
N.KEYS = { "NineSlice", "Inset", "Bg", "TopTileStreaks", "PortraitContainer", "BtnCornerLeft", "BtnCornerRight", "ButtonBottomBorder" } -- ButtonFrameTemplate parts (2.5.3)

-- The size drawn for a client: spec.size, or spec.size243 on 2.4.3. Pure.
function N.SizeFor(spec, is243)
  return (is243 and spec.size243) or spec.size
end

-- "name1".."nameN" pairs of a numbered row family: { { "Prefix", n } } -> flat list. Pure.
function N.Numbered(prefix, n, suffix)
  local out = {}
  for i = 1, n do out[i] = prefix .. i .. (suffix or "") end
  return out
end

-- A dark plate (the Rock fill and a bronze rim, WinKit.panel) behind `anchor` (to `last`'s far corner when given), grown by l / t / r / b px. Child of `host` at the host's own level: above its stone,
-- below its children (list rows, their icons and texts).
function N.Plate(host, anchor, l, t, r, b, last)
  local K = AFUI.WinKit
  if not (host and anchor and K and K.panel) then return end
  local p = CreateFrame("Frame", nil, host)
  p:SetFrameLevel(host:GetFrameLevel())
  p:SetPoint("TOPLEFT", anchor, "TOPLEFT", -(l or 0), t or 0); p:SetPoint("BOTTOMRIGHT", last or anchor, "BOTTOMRIGHT", r or 0, -(b or 0))
  K.panel(p)
  return p
end

-- Hides the Blizzard art of `names` (texture regions only: texts, buttons and children keep working).
function N.Bare(names)
  local P = AFUI.Professions and AFUI.Professions.Kit
  if not P then return end
  for _, n in ipairs(names or {}) do local f = g(n); if f and f.GetRegions then P.hideRegions(f) end end
end

-- The Left / Middle / Right art pieces of a template button or row ("$parentLeft"...): alpha 0 (the client may show them again, alpha stays down). Highlights are left alone.
N.PIECES = { "Left", "Middle", "Right" }
function N.Strip(name)
  for _, s in ipairs(N.PIECES) do local t = g(name .. s); if t and t.SetAlpha then t:SetAlpha(0) end end
end

-- STRUCTURAL hiding (never by guessed names): everything a client frame draws or holds that is not ours and not on the allow-list goes, so a label, texture, container or slider whose
-- name we do not know cannot show through next to ours (the real 2.5.3 Send Mail page printed "To: To:" and two "Postage:" that way). o = {
--   keep = { name = true } controls we place (kept), keepText = { name = true } FontStrings that stay, fontsIn = { name = true } kept frames whose own FontString regions are swept too
--   (edit boxes carry their labels there; a table instead of true = { [N.Norm(text)] = true }: only the FontStrings with those texts go, every other FontString of the box stays), scrolls = { name = true } kept scroll frames (their unknown sliders go, or restyle when the scroll frame has no bar yet),
--   textures = true (the host's own texture regions go too), interactive = false turns OFF the default (an unlisted child that is or holds a button / check button / edit box / scroll frame ALWAYS stays: only pure decoration goes), children = false (leave child frames alone: window hosts whose chrome is ours), scrollX = gap of a restyled bar }.
-- Our own pieces (afOwn / afKeep / afLabel / AFUI_ names) always stay. Returns the report rows { name, kind, text, action } and stores them under the host's name (N.ReportLines).
N.sweeps = {}
function N.Norm(s) return (tostring(s or ""):lower():gsub("[%s:]+$", "")) end -- "Postage: " -> "postage"
local INPUT = { Button = true, CheckButton = true, EditBox = true, ScrollFrame = true }
function N.HasInput(f, depth)
  local k = f.GetObjectType and f:GetObjectType()
  if k == "Slider" then return false end -- a scroll bar's arrows are buttons, but a stray bar is exactly what goes
  if INPUT[k] then return true end
  if (depth or 0) < 6 and f.GetChildren then
    for _, c in ipairs({ f:GetChildren() }) do if N.HasInput(c, (depth or 0) + 1) then return true end end
  end
  return false
end
function N.Sweep(host, o)
  o = o or {}
  local keep, keepText, fontsIn, scrolls = o.keep or {}, o.keepText or {}, o.fontsIn or {}, o.scrolls or {}
  local out = {}
  if not host then return out end
  local function nm(x) return x.GetName and x:GetName() or nil end
  local function kind(x) return x.GetObjectType and x:GetObjectType() or "?" end
  -- the first sweep sees what the client built; whatever shows up later was made by the skin (WinKit's pieces): ours
  local first = not host.afSeen
  local seen = host.afSeen or {}
  host.afSeen = seen
  local function own(x, n) return x.afOwn or x.afKeep or x.afLabel or (n and (keep[n] or keepText[n] or n:sub(1, 5) == "AFUI_")) or (not first and not seen[x]) end
  local function note(x, action)
    seen[x] = true
    local t = x.GetText and x:GetText()
    out[#out + 1] = { name = nm(x) or "(unnamed)", kind = kind(x), text = type(t) == "string" and t or nil, action = action }
  end
  local function gone(x)
    if x.SetAlpha then x:SetAlpha(0) end
    if x.EnableMouse then x:EnableMouse(false) end
    if x.Hide then x:Hide() end
  end
  local function regions(f, textures, only)
    if not f.GetRegions then return end
    for _, r in ipairs({ f:GetRegions() }) do
      local k = kind(r)
      if only and k == "FontString" and not only[N.Norm(r.GetText and r:GetText())] then -- an edit box keeps every FontString that is not a label we identified
      elseif k == "FontString" or (textures and k == "Texture") then
        if own(r, nm(r)) then note(r, r.afLabel and "reused" or "kept") else gone(r); note(r, "hidden") end
      end
    end
  end
  local function sliders(sf)
    local have, loose = false, {}
    for _, c in ipairs({ sf:GetChildren() }) do
      local n = nm(c)
      if c.afBar then have = true; note(c, "kept") -- the client's bar, already ours (a model with our bar over it)
      elseif kind(c) == "Slider" or (n and n:find("ScrollBar")) then loose[#loose + 1] = c end
    end
    for _, c in ipairs(loose) do
      local K = AFUI.WinKit
      if not have and kind(c) == "Slider" and K and K.scroll and K.scroll(c, { x = o.scrollX }) then have = true; note(c, "restyled")
      else gone(c); note(c, "hidden") end
    end
  end
  regions(host, o.textures)
  if o.children ~= false and host.GetChildren then
    for _, c in ipairs({ host:GetChildren() }) do
      local n = nm(c)
      if own(c, n) then
        note(c, "kept")
        if n and fontsIn[n] then regions(c, false, type(fontsIn[n]) == "table" and fontsIn[n] or nil) end
        if n and scrolls[n] then sliders(c) end
      elseif o.interactive ~= false and N.HasInput(c) then note(c, "kept") -- an unlisted control (or a frame holding one) stays: a page whose control names are not all known must keep working
      else gone(c); note(c, "hidden") end
    end
  else -- a window host: its chrome is ours, but the scroll frames and edit boxes inside it still get their labels and sliders checked
    for n in pairs(scrolls) do local f = _G[n]; if f and f.GetChildren then sliders(f) end end
    for n, v in pairs(fontsIn) do local f = _G[n]; if f then regions(f, false, type(v) == "table" and v or nil) end end
  end
  N.sweeps[nm(host) or "?"] = out
  return out
end

-- The sweep rows of the hosts (names) as printable lines, one per thing: action, kind, name, text.
function N.ReportLines(hosts)
  local lines = {}
  for _, h in ipairs(hosts) do
    local rows = N.sweeps[h]
    if rows then
      lines[#lines + 1] = h .. ": " .. #rows .. " things looked at"
      for _, r in ipairs(rows) do lines[#lines + 1] = string.format("  %-8s %-10s %s%s", r.action, r.kind, r.name, r.text and (' "' .. r.text .. '"') or "") end
    else lines[#lines + 1] = h .. ": not skinned (nothing swept)" end
  end
  return lines
end

---------------------------------------------------------------- thin text boxes
-- ONE thin Forever field for every edit box of the NPC windows: the bank search box art (common-input, the box is 18 high, the art 3 px outside it). The client's own frame art of the box (the
-- Left / Middle / Right pieces of InputBoxTemplate, whatever else it draws as a texture: found structurally, every Texture region that is not ours) goes, or two borders double up and the box is
-- ~2x too heavy; the coin icons of a money input (a "...Money..." texture path) stay. The text, its selection highlight, the completion and the autocomplete are the client's: only the text colour
-- (white) and the insets are set. Nothing here touches an edit box's FontStrings.
N.EDIT_H, N.EDIT_PAD = 18, 3
local function isFrameArt(r)
  local n = r.GetName and r:GetName() or ""
  if n:find("Left$") or n:find("Middle$") or n:find("Right$") or n:find("Border") then return true end
  local p = r.GetTexture and r:GetTexture()
  if type(p) == "string" then return not p:lower():find("money") end
  return false -- a file id or nothing: unknown, stays (a coin icon never disappears)
end
function N.Edit(box)
  if not box or box.afThin then return end
  box.afThin = true
  local function atlas(name) local t = box:CreateTexture(nil, "BACKGROUND"); t.afOwn = true; AFUI.SetAtlas(t, name); return t end
  for _, r in ipairs({ box:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "Texture" and not r.afOwn and isFrameArt(r) then r:SetAlpha(0); if r.Hide then r:Hide() end end
  end
  local l = atlas("common-input-left"); l:SetPoint("TOPLEFT", box, "TOPLEFT", -4, N.EDIT_PAD); l:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -4, -N.EDIT_PAD); l:SetWidth(10)
  local r = atlas("common-input-left"); r:SetPoint("TOPRIGHT", box, "TOPRIGHT", 4, N.EDIT_PAD); r:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 4, -N.EDIT_PAD); r:SetWidth(10)
  local en = AFUI_ATLAS and AFUI_ATLAS["common-input-left"]; if en then r:SetTexCoord(en[5], en[4], en[6], en[7]) end -- the same cap turned over
  local m = atlas("common-input-middle"); m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  box:SetHeight(N.EDIT_H)
  if box.SetTextInsets then box:SetTextInsets(6, 6, 0, 0) end
  if box.SetTextColor then box:SetTextColor(1, 1, 1, 1) end
end

---------------------------------------------------------------- item slots
-- The empty slot of Forever's combined bags (the dark slot with the wing glyph and its metal border) behind EVERY item slot we skin. Bags.lua exports it as AFUI.Bags.EmptySlotTexture();
-- until that exists the atlas Bags.SkinSlot paints is used directly. The client's own icon, count, quality border and cooldown stay on top; only its slot frame art goes.
N.SLOT_ATLAS = "bags-item-slot64-c60-2x"
function N.EmptySlotTexture()
  local B = AFUI.Bags
  local a = B and B.EmptySlotTexture and B.EmptySlotTexture()
  if a == nil and B and B.EmptyArt then a = B.EmptyArt() end
  return a or N.SLOT_ATLAS
end
local function paintSlot(t)
  local a = N.EmptySlotTexture()
  if type(a) == "string" and AFUI_ATLAS and AFUI_ATLAS[a:lower()] then AFUI.SetAtlas(t, a)
  elseif a ~= nil then t:SetTexture(a); t:SetTexCoord(0, 1, 0, 1) end
end
-- The client sets its slot frame (a texture under Interface\Buttons) as the normal texture of an empty slot and the item's icon as that of a filled one: the frame goes, the icon stays.
function N.SlotUpdate(b)
  local nt = b and b.GetNormalTexture and b:GetNormalTexture()
  if not nt then return end
  local p = nt.GetTexture and nt:GetTexture()
  nt:SetAlpha((type(p) == "string" and p:lower():find("^interface[\\/]buttons")) and 0 or 1)
end
function N.Slot(name)
  local b = type(name) == "string" and g(name) or name
  if not b or b.afSlot or not b.CreateTexture then return end
  b.afSlot = true
  b.afSlotBG = b:CreateTexture(nil, "BACKGROUND"); b.afSlotBG.afOwn = true; b.afSlotBG:SetAllPoints(b)
  paintSlot(b.afSlotBG)
  N.SlotUpdate(b)
end

-- A title of our own for windows whose client title belongs to a child frame (Mail: Inbox / Send Mail; Auction: none). text = string or function.
function N.Title(f, text)
  if f.afTitle or not f.afLabels then return f.afTitle end
  local t = f.afLabels:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOP", f, "TOP", 0, -6)
  f.afTitle = t
  function f.afRetitle() t:SetText(type(text) == "function" and text() or text or "") end
  f.afRetitle()
  return t
end

-- Skins one window from its spec. Returns the frame (nil when the client has no such frame yet / WinKit is missing).
function N.Skin(spec)
  local f, K = g(spec.frame), AFUI.WinKit
  if not f or f.afNpc or not (K and K.window and AFUI.Professions) then return f end
  f.afNpc = true
  local sz = N.SizeFor(spec, AFUI.IS_243)
  K.window(f, { icon = spec.icon, title = spec.title, close = spec.close, cut = sz.cut, w = sz.w, h = sz.h, keys = N.KEYS, hide = spec.hide })
  if spec.before then spec.before(f) end -- a window that lays its own page out does it first: the scroll bars below read the final size of their lists
  N.Bare(spec.bare)
  if spec.tabs then K.tabs(f, spec.tabs, f.afWin.h, f.afWin.cut) end
  K.each(spec.buttons or {}, K.button)
  K.each(spec.edits or {}, N.Edit)
  K.each(spec.slots or {}, N.Slot)
  K.each(spec.checks or {}, K.check)
  K.each(spec.headers or {}, K.header)
  K.each(spec.dropdowns or {}, K.dropdown)
  K.each(spec.rows or {}, K.row)
  for _, s in ipairs(spec.scrolls or {}) do -- a name, or { name, gap right of the list } (negative = inside it)
    if type(s) == "table" then K.scroll(s[1], { x = s[2] }) else K.scroll(s, { x = spec.scrollX }) end
  end
  for _, n in ipairs(spec.strip or {}) do N.Strip(n) end
  if spec.npc then
    local function portrait() if f.afPortrait then AFUI.PortraitUnit(f.afPortrait, "npc") end end
    f:HookScript("OnShow", portrait)
    if f:IsShown() then portrait() end
  end
  if K.makeMovable and spec.move then K.makeMovable(f, nil, spec.move) end
  if AFUI.PanelAttrs and K.ORIGIN then
    AFUI.PanelAttrs(f, { width = f.afWin.w, height = f.afWin.h - f.afWin.cut, xoffset = K.ORIGIN.x, yoffset = K.ORIGIN.y })
  end
  if spec.after then spec.after(f) end
  return f
end
