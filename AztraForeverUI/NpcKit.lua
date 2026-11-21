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
  N.Bare(spec.bare)
  if spec.tabs then K.tabs(f, spec.tabs, f.afWin.h, f.afWin.cut) end
  K.each(spec.buttons or {}, K.button)
  K.each(spec.edits or {}, K.edit)
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
