-- Diagnostic eyes for the developer (docs/audit.md). Loads last. Three jobs:
--   1. ERROR LOG: chains the previous error handler and records every Lua error in AztraForeverUIDB.audit.errors.
--   2. `/afui audit`: opens each window out of combat, one step at a time, measures what AFUI drew, takes a Screenshot(), closes it.
--      The result is AztraForeverUIDB.audit (steps, problems), written to disk on /reload or logout.
--   3. Detectors (fill past its frame, text wider than its box, buttons under the minimap ring, ...) that need only plain widget calls,
--      so the offline preview runs them too (tools/preview/audit.mjs).
-- Everything is pcall-wrapped, nothing here is protected, and the OnUpdate frame is hidden whenever no run is going.
AFUI = AFUI or {}
local A = {}
AFUI.Audit = A

local CAP_ERRORS, CAP_BYTES, CAP_FRAMES, CAP_PROBLEMS, TOL = 50, 200 * 1024, 60, 200, 0.5
local STRATA = { WORLD = 0, BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

local function r1(n) return math.floor(n * 10 + 0.5) / 10 end
local function cut(v, n) v = tostring(v); return #v > n and v:sub(1, n) or v end
local function now() return (time and time()) or (GetTime and GetTime()) or 0 end
local function stamp() return date and date("%Y-%m-%d %H:%M:%S") or tostring(now()) end
local function say(msg) if AFUI.Print then AFUI.Print("AFUI audit: " .. msg) end end

-- First return value of a widget method, nil when the method is missing or throws.
local function m(o, name, ...)
  local fn = o and o[name]
  if type(fn) ~= "function" then return end
  -- a forbidden / restricted frame (2.5.3 nameplate children) answers every call but IsForbidden with a client-side error that no pcall catches
  if name ~= "IsForbidden" and AFUI.MeasureBlocked and AFUI.MeasureBlocked(o) then return end
  local ok, a = pcall(fn, o, ...)
  if ok then return a end
end
-- All return values of a widget method as a list (GetChildren / GetRegions).
local function list(o, name)
  local fn = o and o[name]
  if type(fn) ~= "function" then return {} end
  if AFUI.MeasureBlocked and AFUI.MeasureBlocked(o) then return {} end
  local t = { pcall(fn, o) }
  if not table.remove(t, 1) then return {} end
  return t
end

---------------------------------------------------------------- error log
local SESSION, pend = now(), {} -- errors before the SavedVariables exist wait in `pend`

local function db()
  local d = _G.AztraForeverUIDB
  if type(d) ~= "table" then return end
  if type(d.audit) ~= "table" then d.audit = {} end
  if type(d.audit.errors) ~= "table" then d.audit.errors = {} end
  return d.audit
end

-- Adds one error to `into`: a repeated message only counts; past 50 distinct ones the oldest goes.
function A.Record(msg, stack, into, count)
  msg, stack = cut(msg, 300), cut(stack or "", 700)
  for i = 1, #into do
    local e = into[i]
    if e.msg == msg then e.count = e.count + (count or 1); e.last = stamp(); return e end
  end
  if #into >= CAP_ERRORS then table.remove(into, 1) end
  local e = { msg = msg, stack = stack, count = count or 1, first = stamp(), last = stamp(), s = SESSION }
  into[#into + 1] = e
  return e
end

local function errors()
  local a = db()
  if not a then return pend end
  for i = 1, #pend do local e = pend[i]; A.Record(e.msg, e.stack, a.errors, e.count) end
  pend = {}
  return a.errors
end

local previous = geterrorhandler and geterrorhandler()
local function handler(msg)
  pcall(function()
    local stack = (debugstack and debugstack(3, 12, 0)) or (debug and debug.traceback and debug.traceback("", 3)) or ""
    A.Record(msg, stack, errors())
  end)
  if previous then return select(2, pcall(previous, msg)) end
end
if seterrorhandler then seterrorhandler(handler) end
A.Handler = handler

---------------------------------------------------------------- geometry and visibility
local function visible(f)
  local v = m(f, "IsVisible")
  if v == nil then v = m(f, "IsShown") end
  return v and true or false
end

-- left, bottom, width, height in the frame's own scale (y up), nil when the widget has no rect yet.
local function geo(f)
  local l, b = m(f, "GetLeft"), m(f, "GetBottom")
  if type(l) ~= "number" or type(b) ~= "number" then return end
  local r, t = m(f, "GetRight"), m(f, "GetTop")
  local w = type(r) == "number" and r - l or tonumber(m(f, "GetWidth")) or 0
  local h = type(t) == "number" and t - b or tonumber(m(f, "GetHeight")) or 0
  return l, b, w, h
end

local function label(f, depth)
  local n = m(f, "GetName")
  if n then return n end
  depth = depth or 0
  local p = m(f, "GetParent")
  local own = (m(f, "GetObjectType") or "?")
  if depth > 4 or not p then return "?/" .. own end
  return label(p, depth + 1) .. "/" .. own
end

---------------------------------------------------------------- detectors (each returns a short text or nil)
-- A fill placed by AFUI.Bar.Place (tag tex.afuiBar = { frame, inset, h }) must lie inside its frame's inner rect.
function A.FillProblem(tex)
  local t = tex.afuiBar
  if type(t) ~= "table" or not t.frame then return end
  local l, b, w, h = geo(tex)
  local fl, fb, fw, fh = geo(t.frame)
  if not l or not fl then return end
  local ins, top = t.inset or { 0, 0, 0, 0 }, fb + fh
  local il, ir, it, ib = fl + ins[1], fl + fw - ins[3], top - ins[2], top - (t.h or fh) + ins[4]
  local over = {}
  if l < il - TOL then over[#over + 1] = r1(il - l) .. " left" end
  if l + w > ir + TOL then over[#over + 1] = r1(l + w - ir) .. " right" end
  if b + h > it + TOL then over[#over + 1] = r1(b + h - it) .. " above" end
  if b < ib - TOL then over[#over + 1] = r1(ib - b) .. " below" end
  if #over > 0 then return "fill exceeds its bar frame by " .. table.concat(over, ", ") .. " px" end
end

-- A shown texture that would draw a green / blank square: a path under Interface\Icons that is not on AFUI.KNOWN_ICONS (only when A.StrictIcons: in the game the
-- API hands over item and spell icons that are not on our list), or a solid colour (no texture) covering a frame named like Icon / Portrait. tex.afSolid opts out.
function A.IconProblem(tex, owner)
  local path = m(tex, "GetTexture")
  if type(path) == "string" then
    local name = path:match("^[Ii]nterface[\\/]+[Ii]cons[\\/]+([^\\/]+)$")
    if name and A.StrictIcons and AFUI.KNOWN_ICONS and not AFUI.KNOWN_ICONS[(name:gsub("%.%a+$", "")):lower()] then return "icon file not on the known list: " .. name end
  elseif path == nil and owner and not tex.afSolid then
    local on = m(owner, "GetName")
    if on and (on:find("Icon") or on:find("Portrait")) then
      local _, _, tw, th = geo(tex)
      local _, _, fw, fh = geo(owner)
      if tw and fw and fw > 0 and fh > 0 and tw >= fw * 0.6 and th >= fh * 0.6 then return "solid colour where the icon / portrait picture should be" end
    end
  end
end

-- A shown texture whose file is one of ours (Interface\AddOns\AztraForeverUI\Media\...): its path goes into `seen` (the stored "media" list, so the files can be
-- checked on disk afterwards: a missing, misspelled or non power-of-two file draws solid green), and it is a problem when the texcoords are unset, or when a page
-- file (Media\pageN, Media\lfg\lfg-pageN) is drawn whole (0..1: the sprite's own rectangle was never applied, so the whole sheet shows).
function A.MediaProblem(tex, seen)
  local path = m(tex, "GetTexture")
  if type(path) ~= "string" or not path:lower():find("aztraforeverui[\\/]+media[\\/]") then return end
  if seen then seen[path] = true end
  local c = list(tex, "GetTexCoord")
  if c[1] == nil then return "Media texture without texcoords: " .. path end
  local lo, hi = { 1, 1 }, { 0, 0 }
  for i, v in ipairs(c) do
    local axis = #c == 8 and (i % 2 == 1 and 1 or 2) or (i <= 2 and 1 or 2) -- 8 values: x, y pairs; 4 values: l, r, t, b
    if type(v) == "number" then lo[axis] = math.min(lo[axis], v); hi[axis] = math.max(hi[axis], v) end
  end
  local low = path:lower()
  if (low:find("[\\/]page%d+$") or low:find("[\\/]lfg%-page%d+$")) and hi[1] - lo[1] > 0.97 and hi[2] - lo[2] > 0.97 then
    return "page texture drawn whole (texcoords 0..1, no sprite rectangle): " .. path
  end
end

-- "overflow" when the text is wider than its box, "truncated" when AFUI.FitText cut it, else nil.
function A.StringProblem(fs)
  local txt = m(fs, "GetText")
  if type(txt) ~= "string" or txt == "" then return end
  local _, _, w = geo(fs)
  local sw = tonumber(m(fs, "GetStringWidth"))
  -- a wrapping string breaks into lines instead of overflowing (the client's GetStringWidth is the widest line), so only one-line strips count
  if sw and w and w > 0 and sw > w + TOL and not m(fs, "CanWordWrap") then return "overflow", "text '" .. cut(txt, 30) .. "' is " .. r1(sw) .. " px wide in a " .. r1(w) .. " px box" end
  if txt:sub(-3) == "..." then return "truncated", "text '" .. cut(txt, 30) .. "' is cut" end
end

-- Shown buttons that are not direct children of the window (Talents nodes live in a grid frame) must lie inside the window's rect (1 px).
function A.OutsideParentProblems(parent, kids)
  local out, pl, pb, pw, ph = {}, geo(parent)
  if not pl then return out end
  for _, k in ipairs(kids) do
    local l, b, w, h = geo(k)
    if l then
      local o = math.max(pl - l, l + w - (pl + pw), pb - b, b + h - (pb + ph))
      if o > 1 then out[#out + 1] = (m(k, "GetName") or "child") .. " sticks out of the window by " .. r1(o) .. " px" end
    end
  end
  return out
end

-- Column headers with a child control (the Who tab's Zone selector arrow): the child must lie inside its header and may not touch the next header.
-- cols = ordered list of header frames; kids = { [header index] = child frame }. Returns problem texts (tolerance 1 px).
function A.HeaderChildProblems(cols, kids)
  local out = {}
  for i, c in pairs(kids) do
    local h, nx = cols[i], cols[i + 1]
    local cl, cb, cw, ch = geo(c)
    local hl, hb, hw, hh = geo(h)
    if cl and hl then
      if cl < hl - TOL or cl + cw > hl + hw + TOL or cb < hb - TOL or cb + ch > hb + hh + TOL then out[#out + 1] = label(c) .. " sticks out of its column header" end
      if ch > hh + TOL then out[#out + 1] = label(c) .. " is taller than its column header" end
      local nl = nx and geo(nx)
      if nl and cl + cw > nl + TOL then out[#out + 1] = label(c) .. " overlaps the next column header by " .. r1(cl + cw - nl) .. " px" end
    end
  end
  return out
end

-- A button over the minimap must draw above the ring, or the ring covers it.
function A.StrataProblem(btn, ring)
  local bs, rs = STRATA[m(btn, "GetFrameStrata") or ""], STRATA[m(ring, "GetFrameStrata") or ""]
  if not bs or not rs then return end
  local bl, rl = m(btn, "GetFrameLevel") or 0, m(ring, "GetFrameLevel") or 0
  if bs < rs or (bs == rs and bl <= rl) then
    return "is under the minimap ring (" .. m(btn, "GetFrameStrata") .. "/" .. bl .. " vs " .. m(ring, "GetFrameStrata") .. "/" .. rl .. ")"
  end
end

local function overlap(a, b) -- a, b = { l, b, w, h }
  local w = math.min(a[1] + a[3], b[1] + b[3]) - math.max(a[1], b[1])
  local h = math.min(a[2] + a[4], b[2] + b[4]) - math.max(a[2], b[2])
  if w > 4 and h > 4 then return r1(w), r1(h) end
end

-- Interaction check for the social windows: a shown button must take the mouse, have a size and be the topmost clickable thing at its centre.
-- b / blockers entries = { f, name, mouse, w, h, cx, cy, rank } (rank = strata * 1000 + frame level; a higher rank is drawn on top); related(a, b) says
-- whether two frames are the same chain (a child over its own parent is fine). Returns the problem texts.
function A.ClickProblems(b, blockers, related)
  local out = {}
  if b.mouse == false then out[#out + 1] = "button ignores the mouse" end
  if (b.w or 0) <= 0 or (b.h or 0) <= 0 then out[#out + 1] = "button has no size" end
  if b.cx and b.cy and (b.w or 0) > 0 then
    for _, o in ipairs(blockers) do
      if o ~= b and o.f ~= b.f and o.cx and o.rank > b.rank and not related(b.f, o.f)
        and math.abs(b.cx - o.cx) * 2 <= o.w and math.abs(b.cy - o.cy) * 2 <= o.h then
        out[#out + 1] = "covered at its centre by " .. tostring(o.name); break
      end
    end
  end
  return out
end
local STRATA = { WORLD = 1, BACKGROUND = 2, LOW = 3, MEDIUM = 4, HIGH = 5, DIALOG = 6, FULLSCREEN = 7, FULLSCREEN_DIALOG = 8, TOOLTIP = 9 }
local function chain(a, b) -- b is a or one of its ancestors
  local p, d = a, 0
  while p and d < 30 do if p == b then return true end; p, d = m(p, "GetParent"), d + 1 end
end
local function related(a, b) return chain(a, b) or chain(b, a) end

-- A window's portrait ring (AFUI.WindowPortrait records the picture as frame.afPortraitTex) must show only our picture: any other shown
-- texture of the window's Blizzard ancestors (the map frame's own PortraitContainer ...) or their children inside the ring's box is a stray copy.
-- Returns the where-strings of the strays.
-- Our own art on a Blizzard frame (the paper doll's stone and race pictures are drawn by CharacterFrame.lua) is no stray.
local function ownArt(path) return type(path) == "string" and (path:find("AztraForeverUI", 1, true) or path:find("DressUpBackground", 1, true)) and true or false end
function A.PortraitStrays(win, owns)
  local out, tex = {}, win and win.afPortraitTex
  local l, b, w, h = geo(tex)
  if not l then return out end
  local ring = { l - 10, b - 10, w + 20, h + 20 }
  local seen, n = {}, 0
  local function scan(f, depth)
    if not f or seen[f] or n > 400 or m(f, "IsForbidden") then return end
    seen[f] = true; n = n + 1
    if owns(f) or not visible(f) then return end
    for _, g in ipairs(list(f, "GetRegions")) do
      if m(g, "GetObjectType") == "Texture" and visible(g) and (m(g, "GetAlpha") or 1) > 0 then
        local gl, gb, gw, gh = geo(g)
        if gl and gw > 0 and gh > 0 and (m(g, "GetTexture") ~= nil) and not ownArt(m(g, "GetTexture")) and overlap(ring, { gl, gb, gw, gh }) then out[#out + 1] = label(f) .. " (" .. tostring(m(g, "GetName") or m(g, "GetTexture")) .. ")" end
      end
    end
    if depth < 3 then for _, c in ipairs(list(f, "GetChildren")) do scan(c, depth + 1) end end
  end
  local p = m(win, "GetParent")
  while p and p ~= _G.UIParent do scan(p, 0); p = m(p, "GetParent") end
  return out
end

-- The client's MinimapBackdrop is the container of the minimap border art, which Minimap.lua banishes: it is larger than the map, but while it
-- draws no texture of its own (nothing shown with a picture) its size is invisible. Any other frame, or a backdrop that draws something, is still measured.
function A.BareBackdrop(f)
  if m(f, "GetName") ~= "MinimapBackdrop" then return false end
  for _, g in ipairs(list(f, "GetRegions")) do
    if m(g, "GetObjectType") == "Texture" and visible(g) and (m(g, "GetAlpha") or 1) > 0 and m(g, "GetTexture") ~= nil then return false end
  end
  return true
end

-- Screen-space rect { l, b, w, h } of a frame or texture (its own scale applied), nil without a rect.
local function srect(f)
  local l, b, w, h = geo(f)
  if not l then return end
  local s = tonumber(m(f, "GetEffectiveScale")) or 1
  return { l * s, b * s, w * s, h * s }
end
local function inside(r, x, y) return x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4] end
local function isAncestor(a, f) local p, d = m(f, "GetParent"), 0; while p and d < 30 do if p == a then return true end; p, d = m(p, "GetParent"), d + 1 end return false end

-- A red button of WinKit (btn.afArt) must show only its own slices: any other shown texture with art that sits over it is the client template's piece (a
-- doubled end cap), and two of our own slices must not overlap. Returns the problem text or nil.
function A.ButtonArtProblem(btn)
  if type(btn.afArt) ~= "table" then return end
  local br = srect(btn)
  if not br then return end
  local own, foreign = {}, {}
  for _, g in ipairs(list(btn, "GetRegions")) do
    if m(g, "GetObjectType") == "Texture" and visible(g) and (m(g, "GetAlpha") or 1) > 0 and m(g, "GetTexture") ~= nil then
      local layer = m(g, "GetDrawLayer")
      local r = srect(g)
      if r and layer ~= "HIGHLIGHT" and overlap(br, r) then
        if g.afOwn then own[#own + 1] = r else foreign[#foreign + 1] = r end
      end
    end
  end
  if #foreign > 0 then return "the client's own button art still shows (" .. #foreign .. " texture(s)) under our red button" end
  for i = 1, #own do
    for j = i + 1, #own do
      local w, h = overlap(own[i], own[j])
      if w and w > 1.5 and h > 4 then return "two slices of the red button overlap by " .. w .. " px" end
    end
  end
end

local CLICKABLE = { Button = true, CheckButton = true }
-- Can the player click this button? It must be mouse-enabled, have a size, and no other mouse-enabled frame of `pool` may sit over its centre in front of it
-- (a higher strata, or the same strata and a higher level: the front frame takes the click). `pool` = the frames the audit collected.
function A.InteractionProblem(btn, pool)
  if not CLICKABLE[m(btn, "GetObjectType") or ""] or not visible(btn) or (m(btn, "GetEffectiveAlpha") or m(btn, "GetAlpha") or 1) <= 0 then return end
  if m(btn, "IsMouseEnabled") == false then -- a row that is only a label on purpose (a header, an empty slot) says so with afNoClick
    if btn.afNoClick then return end
    return "is shown but not mouse-enabled"
  end
  local r = srect(btn)
  if not r then return end
  if r[3] <= 0 or r[4] <= 0 then return "is shown with zero size" end
  local ins = list(btn, "GetHitRectInsets")
  local x, y = r[1] + r[3] / 2 + ((tonumber(ins[1]) or 0) - (tonumber(ins[2]) or 0)) / 2, r[2] + r[4] / 2
  local bs, bl = STRATA[m(btn, "GetFrameStrata") or ""], m(btn, "GetFrameLevel") or 0
  for _, f in ipairs(pool or {}) do
    if f ~= btn and not isAncestor(f, btn) and not isAncestor(btn, f) and m(f, "IsMouseEnabled") and visible(f) and (m(f, "GetAlpha") or 1) > 0 and m(f, "GetObjectType") ~= "FontString" then
      local fr = srect(f)
      local fi = list(f, "GetHitRectInsets")
      if fr then
        fr = { fr[1] + (tonumber(fi[1]) or 0), fr[2] + (tonumber(fi[4]) or 0), fr[3] - (tonumber(fi[1]) or 0) - (tonumber(fi[2]) or 0), fr[4] - (tonumber(fi[3]) or 0) - (tonumber(fi[4]) or 0) }
      end
      local fs, fl = STRATA[m(f, "GetFrameStrata") or ""], m(f, "GetFrameLevel") or 0
      if fr and bs and fs and inside(fr, x, y) and (fs > bs or (fs == bs and fl > bl)) then
        return "is covered at its centre by " .. label(f) .. " (" .. (m(f, "GetFrameStrata") or "?") .. "/" .. fl .. " over " .. (m(btn, "GetFrameStrata") or "?") .. "/" .. bl .. ")"
      end
    end
  end
end

---------------------------------------------------------------- objective tracker and micro menu
-- parts = { column = {l,b,w,h} | nil, others = { { name, {l,b,w,h} }, ... }, micro = { { name, rect }, ... }, bags = { { name, rect }, ... },
-- microBar = rect, bagBar = rect }. Problems as text: the drawn tracker column must stay clear of the minimap, the right bars and the bags /
-- micro menu; no micro button may overlap a bag button; the bag bar ends where the micro menu ends (within 6 units).
function A.TrackerProblems(parts)
  local out = {}
  if parts.column then
    for _, o in ipairs(parts.others or {}) do
      local w, h = overlap(parts.column, o[2])
      if w then out[#out + 1] = "tracker overlaps " .. o[1] .. " by " .. ("%g"):format(w) .. "x" .. ("%g"):format(h) .. " px" end
    end
  end
  for _, mb in ipairs(parts.micro or {}) do
    for _, bb in ipairs(parts.bags or {}) do
      local w, h = overlap(mb[2], bb[2])
      if w then out[#out + 1] = mb[1] .. " overlaps " .. bb[1] .. " by " .. ("%g"):format(w) .. "x" .. ("%g"):format(h) .. " px" end
    end
  end
  -- Only the stacked default (full row right over the micro menu, both at their preset spot) lines up: a single icon / hidden bar is re-centred by Edit
  -- Mode, a bar the player moved is where he put it, and a preset with the bags beside the micro menu is not stacked (parts.bagsFree covers the first two).
  local stacked = parts.microBar and parts.bagBar and parts.bagBar[2] >= parts.microBar[2] + parts.microBar[4] - 10
  if stacked and not parts.bagsFree then
    local d = (parts.microBar[1] + parts.microBar[3]) - (parts.bagBar[1] + parts.bagBar[3])
    if math.abs(d) > 6 then out[#out + 1] = "bags bar ends " .. ("%g"):format(r1(d)) .. " px from the micro menu's right edge" end
  end
  return out
end

local MICRO_NAMES = { "CharacterMicroButton", "AFUI_ProfessionsMicroButton", "SpellbookMicroButton", "TalentMicroButton", "AFUI_PVPMicroButton",
  "QuestLogMicroButton", "SocialsMicroButton", "LFGMicroButton", "MainMenuMicroButton" }
local BAG_NAMES = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton" }

-- Reads the live frames into `parts` and appends click problems for every shown micro / bag / tracker button to `out`.
function A.TrackerParts(out)
  local parts, pool = { others = {}, micro = {}, bags = {} }, {}
  local T = AFUI.Tracker
  if T and T.frame and T.visible and visible(T.frame) then
    local r, s = srect(T.frame), tonumber(m(T.frame, "GetEffectiveScale")) or 1
    if r then parts.column = { r[1], r[2] + r[4] - (T.height or r[4] / s) * s, r[3], (T.height or r[4] / s) * s } end
    for _, b in ipairs(T.blocks or {}) do if b.title and visible(b.title) then pool[#pool + 1] = b.title end end
    for _, b in ipairs({ T.allButton, T.secButton }) do if b and visible(b) then pool[#pool + 1] = b end end
  end
  local function part(list, name)
    local f = _G[name]
    if f and visible(f) then local r = srect(f); if r then list[#list + 1] = { name, r }; pool[#pool + 1] = f end end
  end
  for _, n in ipairs(MICRO_NAMES) do part(parts.micro, n) end
  for _, n in ipairs(BAG_NAMES) do part(parts.bags, n) end
  local function bar(f, name) if f and visible(f) then local r = srect(f); if r then parts.others[#parts.others + 1] = { name, r }; return r end end end
  bar(AFUI.MinimapRing, "Minimap")
  for _, k in ipairs({ "right", "right2" }) do if AFUI.Bars and AFUI.Bars[k] then bar(AFUI.Bars[k].frame, "Right bar " .. k) end end
  parts.bagBar, parts.microBar = bar(AFUI.BagBar, "Bags bar"), bar(AFUI.MicroMenu, "Micro menu")
  local EM = AFUI.EditMode
  parts.bagsFree = (AFUI.BagBarMode and AFUI.BagBarMode() or "full") ~= "full"
    or (EM and EM.IsMoved and EM.current and (EM.IsMoved("bags") or EM.IsMoved("micromenu"))) and true or false
  if out then
    for _, f in ipairs(pool) do
      local why = A.InteractionProblem(f, pool)
      if why then out[#out + 1] = (m(f, "GetName") or "button") .. " " .. why end
    end
    for _, f in ipairs(pool) do -- every shown micro button must also pick up the mouse and have a size (a dead button)
      if m(f, "IsMouseEnabled") == false then out[#out + 1] = (m(f, "GetName") or "button") .. " ignores the mouse" end
    end
  end
  return parts
end

---------------------------------------------------------------- measuring
local ROOT_HUD = { "Minimap", "MinimapCluster", "ChatFrame1", "PlayerFrame", "TargetFrame", "ActionButton1", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MainMenuExpBar", "ReputationWatchBar" }
-- Every window the audit opens, for the headless preview (which keeps the scene's own windows open): the visible ones are measured.
A.WINDOWS = { "CharacterFrame", "SpellBookFrame", "PlayerTalentFrame", "AFUI_ProfessionsFrame", "TradeSkillFrame", "CraftFrame", "FriendsFrame", "AFUIGuildFrame", "AFUIGuildCommFrame",
  "LFGParentFrame", "WorldMapFrame", "QuestLogFrame", "GameMenuFrame", "AFUI_SettingsFrame", "AFUI_WizardFrame", "AFUI_EditModeDialog", "GameTooltip", "LootFrame" }

local function owned(f, memo)
  local p, d, trail = f, 0, {}
  while p and d < 25 do
    if memo[p] ~= nil then break end
    local n = m(p, "GetName")
    trail[#trail + 1] = p
    if n and (n:find("^AFUI") or n:find("^AztraForeverUI")) then
      for i = 1, #trail do memo[trail[i]] = true end
      return true
    end
    p, d = m(p, "GetParent"), d + 1
  end
  local v = p and memo[p] or false
  for i = 1, #trail do memo[trail[i]] = v end
  return v
end

local function resolve(r) return type(r) == "string" and _G[r] or r end

-- Pure: a window rect (left, bottom from the screen's bottom left, w, h, in screen units) against the screen and the top of the action bars (barTop units from the bottom).
function A.FitProblems(l, b, w, h, uiW, uiH, barTop)
  local out = {}
  if l < 0 or l + w > uiW or b + h > uiH then out[#out + 1] = "window leaves the screen" end
  if barTop and b < barTop then out[#out + 1] = "window bottom is on the action bars" end
  return out
end

-- Talents step: the window rect in screen units (frame scale applied) and the bar top (the 2.5.3 main bar top is 88 px of a 903 px UI).
function A.TalentsFit()
  local f = _G.PlayerTalentFrame
  if not (f and visible(f)) then return {} end
  local l, b, w, h = geo(f)
  if not l then return {} end
  local s = m(f, "GetScale") or 1
  local uiH = m(UIParent, "GetHeight") or 0
  return A.FitProblems(l * s, b * s, w * s, h * s, m(UIParent, "GetWidth") or 0, uiH, uiH * 88 / 903)
end

A.MOVABLE_STEPS = { Character = true, Spellbook = true, Talents = true, Professions = true, Social = true, Guild = true, ["Guild & Communities"] = true, GroupFinder = true, GameMenu = true, Settings = true, Wizard = true, Bags = true, Bank = true }

-- Every audited window root (a real window, not the HUD) must have the drag handle of WinKit.makeMovable; `names` are the step's roots.
function A.MovableProblems(names)
  local out = {}
  for _, r in ipairs(names or {}) do
    local f = resolve(r)
    if f and visible(f) and not f.afMoveKey and not (f.GetName and tostring(f:GetName()):find("^AFUI_%a*Bar")) then out[#out + 1] = (f.GetName and f:GetName() or "?") .. " has no movable handle" end
  end
  return out
end

-- Minimap buttons (LibDBIcon10_*, Minimap*) against the ring, appended to `out` as "name: text".
local function minimapProblems(out)
  local ring, seen = AFUI.MinimapRing, {}
  if not ring then return end
  local rg = { geo(ring) }
  for _, parent in ipairs({ _G.Minimap, _G.MinimapCluster, _G.UIParent }) do
    for _, c in ipairs(list(parent, "GetChildren")) do
      local n = m(c, "GetName")
      if n and not seen[c] and c ~= ring and n ~= "Minimap" and n ~= "MinimapCluster" and n ~= "MinimapBackdrop"
        and (n:find("^LibDBIcon10_") or n:find("^Mini[Mm]ap")) and visible(c) then
        seen[c] = true
        local b = { geo(c) }
        if b[1] and rg[1] and overlap(b, rg) then
          local why = A.StrataProblem(c, ring)
          if why then out[#out + 1] = n .. " " .. why end
        end
      end
    end
  end
end

-- Measures what is on screen now. roots: names or frames of the window(s) under test (their descendants are checked too, together with every
-- visible AFUI-owned frame). Returns { frames = {...}, suspects = {...}, problems = {...} }.
function A.Measure(step, roots)
  local rec, memo, todo, inTodo, isRoot, inWindow = { frames = {}, suspects = {}, problems = {} }, {}, {}, {}, {}, {}
  local media = {}
  local function bad(where, what)
    if #rec.problems < 60 then rec.problems[#rec.problems + 1] = cut(step .. "/" .. where .. ": " .. what, 200) end
  end
  local function add(f) if f and not inTodo[f] and #todo < 700 then inTodo[f] = true; todo[#todo + 1] = f end end
  local function descend(f, depth)
    if depth > 6 or #todo >= 700 then return end
    add(f); inWindow[f] = true
    for _, c in ipairs(list(f, "GetChildren")) do descend(c, depth + 1) end
  end
  pcall(function()
    local f, n = EnumerateFrames(), 0
    while f and n < 30000 do
      n = n + 1
      if not (f.IsForbidden and f:IsForbidden()) then pcall(function() if visible(f) and owned(f, memo) then add(f) end end) end
      f = EnumerateFrames(f)
    end
  end)
  for _, r in ipairs(roots or {}) do
    local f = resolve(r)
    if f and visible(f) then isRoot[f] = true; descend(f, 0) end
  end
  local wins = {}
  for _, f in ipairs(todo) do
    pcall(function()
      if not visible(f) then return end
      local name, l, b, w, h = m(f, "GetName"), geo(f)
      local where = label(f)
      if l and name and #rec.frames < CAP_FRAMES then
        rec.frames[#rec.frames + 1] = { n = name, l = r1(l), b = r1(b), w = r1(w), h = r1(h), s = m(f, "GetFrameStrata"), lv = m(f, "GetFrameLevel"), a = r1(m(f, "GetAlpha") or 1) }
      end
      -- AFUI_BuffAnchor is the invisible room reserved for the buff rows (Edit Mode box, no art of its own): Forever's windows draw over it on purpose.
      if l and name and m(f, "GetParent") == _G.UIParent and w >= 150 and h >= 100 and not name:find("Grid") and not name:find("EditOverlay") and name ~= "AFUI_BuffAnchor" then
        -- the rect that can be seen / clicked: the transparent margins of a frame (the unit frames' art insets) stay out of the overlap
        local ins = list(f, "GetHitRectInsets")
        local il, ir, it, ib = math.max(0, tonumber(ins[1]) or 0), math.max(0, tonumber(ins[2]) or 0), math.max(0, tonumber(ins[3]) or 0), math.max(0, tonumber(ins[4]) or 0)
        wins[#wins + 1] = { l + il, b + ib, w - il - ir, h - it - ib, name = name }
      end
      if f.afPortraitTex then
        for _, s in ipairs(A.PortraitStrays(f, function(x) return owned(x, memo) end)) do bad(where, "foreign texture inside the portrait ring: " .. s) end
      end
      local parent = m(f, "GetParent")
      -- a child hanging out of its window (tabs, close buttons and the chat button column hang out on purpose)
      if l and parent and isRoot[parent] and w > 0 and h > 0 and (m(f, "GetAlpha") or 1) > 0 and not f.afOverhang and not A.BareBackdrop(f) and not (name and (name:find("Tab") or name:find("CloseButton") or name:find("ButtonFrame") or name:find("^LibDBIcon10_"))) then
        local pl, pb, pw, ph = geo(parent)
        if pl then
          local out = math.max(pl - l, l + w - (pl + pw), pb - b, b + h - (pb + ph))
          if out > 1 then bad(where, "child sticks out of " .. label(parent) .. " by " .. r1(out) .. " px") end
        end
      end
      if inWindow[f] and CLICKABLE[m(f, "GetObjectType") or ""] then -- every shown button: clean red-button art, and a click that reaches it
        for _, why in ipairs({ A.InteractionProblem(f, todo) or "", A.ButtonArtProblem(f) or "" }) do if why ~= "" then bad(where, why) end end
      end
      for _, g in ipairs(list(f, "GetRegions")) do
        if visible(g) and (m(g, "GetAlpha") or 1) > 0 then
          local kind = m(g, "GetObjectType")
          if kind == "Texture" then
            local gl, _, gw, gh = geo(g)
            local fillWhy = g.afuiBar and A.FillProblem(g)
            if fillWhy then bad(where, fillWhy) end
            local iconWhy = A.IconProblem(g, f)
            if iconWhy then bad(where, iconWhy) end
            local mediaWhy = A.MediaProblem(g, media)
            if mediaWhy then bad(where, mediaWhy) end
            -- a frame with no rect of its own (no anchors: the client's FriendsDropDown host) is never drawn, so neither are its textures
            if not gl then if m(g, "GetTexture") ~= nil and l then bad(where, "shown texture has no rect (no anchors)") end
            elseif gw <= 0 or gh <= 0 then bad(where, "texture has zero or negative size " .. r1(gw) .. "x" .. r1(gh)) end
            if m(g, "GetTexture") == nil and #rec.suspects < 10 then rec.suspects[#rec.suspects + 1] = where end -- a solid colour also reads nil: low confidence
          elseif kind == "FontString" then
            local what, text = A.StringProblem(g)
            if what == "overflow" then bad(where, text) elseif what == "truncated" then rec.truncated = (rec.truncated or 0) + 1 end
          end
        end
      end
    end)
  end
  if step:find("^Social") or step:find("^Guild") or step:find("^GroupFinder") then
    local btns, blockers = {}, {}
    for _, f in ipairs(todo) do
      pcall(function()
        if not visible(f) or (m(f, "GetAlpha") or 1) <= 0 then return end
        local l, b, w, h = geo(f)
        local mouse = m(f, "IsMouseEnabled")
        local e = { f = f, name = label(f), mouse = mouse, w = w or 0, h = h or 0, cx = l and (l + w / 2), cy = b and (b + h / 2),
          rank = (STRATA[m(f, "GetFrameStrata") or "MEDIUM"] or 4) * 100000 + (m(f, "GetFrameLevel") or 0) }
        local kind = m(f, "GetObjectType")
        if (kind == "Button" or kind == "CheckButton") and e.name and not e.name:find("^%?") then btns[#btns + 1] = e end
        if mouse then blockers[#blockers + 1] = e end
      end)
    end
    for _, e in ipairs(btns) do
      for _, why in ipairs(A.ClickProblems(e, blockers, related)) do bad(e.name, why) end
    end
    rec.buttons = #btns
  end
  for i = 1, #wins do
    for j = i + 1, #wins do
      local w, h = overlap(wins[i], wins[j])
      if w and #rec.problems < 60 then bad(wins[i].name, "overlaps " .. wins[j].name .. " by " .. w .. "x" .. h .. " px") end
    end
  end
  if step == "Social/Who" and _G.WhoFrameColumnHeader2 and visible(_G.WhoFrameColumnHeader2) then
    local cols = {}
    for i = 1, 4 do cols[i] = _G["WhoFrameColumnHeader" .. i] end
    local kids = { [2] = _G.WhoFrameDropDownButton }
    if cols[4] then for _, p in ipairs(A.HeaderChildProblems(cols, kids)) do bad("WhoFrameColumnHeader2", p) end end
  end
  if AFUI.Talents and AFUI.Talents.Buttons and _G.PlayerTalentFrame and visible(_G.PlayerTalentFrame) then
    for _, p in ipairs(A.OutsideParentProblems(_G.PlayerTalentFrame, AFUI.Talents.Buttons())) do bad("PlayerTalentFrame", p) end
  end
  if step == "HUD" then
    local mm = {}
    pcall(minimapProblems, mm)
    for i = 1, #mm do bad("Minimap", mm[i]) end
    -- every action button: a filled slot (HasAction) must draw its icon, as given by GetActionTexture
    for _, key in ipairs({ "main", "bottomleft", "bottomright", "right", "right2" }) do
      local bar = AFUI.Bars and AFUI.Bars[key]
      for i, b in ipairs(bar and bar.buttons or {}) do
        local a = b.action or tonumber(b:GetAttribute("action"))
        if a and _G.HasAction and HasAction(a) and b:IsShown() then
          local icon = _G[b:GetName() .. "Icon"]
          local tex = _G.GetActionTexture and GetActionTexture(a)
          if not (icon and icon:IsShown() and (icon:GetAlpha() or 1) > 0 and icon:GetTexture()) then
            bad(b:GetName(), "slot " .. a .. " has an action (texture " .. tostring(tex) .. ") but its icon is not drawn")
          end
        end
      end
    end
    if AFUI.FX and AFUI.FX.Problems then for _, why in ipairs(AFUI.FX.Problems()) do bad("ActionButtonFX", why) end end
    for _, n in ipairs(AFUI.CLIENT_UNIT_ART or {}) do -- the client's own unit-frame art must never show next to ours
      local r = _G[n]
      if r and visible(r) and (tonumber(m(r, "GetAlpha")) or 1) > 0 then bad("client unit art " .. n, "still visible after the unit frames were built") end
    end
  end
  if step == "HUD/Tracker" then -- objective tracker, micro menu, bags bar: rects, overlaps, buttons clickable
    local clicks = {}
    local ok, parts = pcall(A.TrackerParts, clicks)
    if ok then
      for _, why in ipairs(A.TrackerProblems(parts)) do bad("Tracker", why) end
      for _, why in ipairs(clicks) do bad("MicroMenu", why) end
      rec.micro, rec.bags = #parts.micro, #parts.bags
      local T = AFUI.Tracker
      if T and T.Mode then
        local qf = _G.Questie_BaseFrame
        rec.trackerMode, rec.questieTracker = T.Mode(), T.QuestieTrackerOn()
        rec.questieBaseFrame = qf and qf.IsShown and qf:IsShown() and true or false
        pcall(function() rec.questieDiag = A.Questie() end)
      end
    end
  end
  if step == "Map" and AFUI.MapCoverProblem then
    local ok, why = pcall(function() return AFUI.MapCoverProblem(_G.WorldMapFrame and _G.WorldMapFrame.ScrollContainer) end)
    if ok and why then bad("WorldMapFrame.ScrollContainer", why) end
  end
  if step == "Map" and AFUI.MapCursorProblem then
    local ok, why = pcall(function() return AFUI.MapCursorProblem(_G.WorldMapFrame and _G.WorldMapFrame.ScrollContainer) end)
    if ok and why then bad("WorldMapFrame.ScrollContainer", why) end
  end
  if step == "Map" and AFUI.MapPanelProblem and AFUI.WorldMapSetPanel then
    -- the quest panel both ways, the saved choice last: hidden -> no panel region and the canvas fills its place; shown -> flush against the canvas
    local ok, err = pcall(function()
      local was = AFUI.WorldMapPanelOpen()
      for _, on in ipairs({ not was, was }) do
        AFUI.WorldMapSetPanel(on)
        local why = AFUI.MapPanelProblem()
        if why then bad("Map/QuestPanel " .. (on and "shown" or "hidden"), why) end
        rec["panel" .. (on and "On" or "Off")] = why == nil
      end
    end)
    if not ok then bad("Map/QuestPanel", "Lua error " .. tostring(err)) end
  end
  if step == "Map" and AFUI.MapQuestPins and _G.GetNumQuestLogEntries then
    -- track the first quest of the log, count the quest pins on the map (restored afterwards)
    local ok, err = pcall(function()
      local P = AFUI.MapQuestPins
      -- the client's watch state against the panel's ticks (they must match), and whether Questie is there
      local watched, ticked = #P.Watched(_G), 0
      for _, r in ipairs(AFUI.QuestLog and AFUI.QuestLog.Rows(AFUI.QuestLog.Read(), "") or {}) do
        if r.kind == "quest" and r.watched then ticked = ticked + 1 end
      end
      rec.questWatched, rec.questTicked, rec.questie = watched, ticked, P.Questie()
      local hidden = 0
      for _, e in ipairs(AFUI.QuestLog and AFUI.QuestLog.Read() or {}) do if e.isHeader and e.collapsed then hidden = hidden + 1 end end
      if watched ~= ticked and hidden == 0 then bad("quest ticks", string.format("client watches %d quests, the panel ticks %d", watched, ticked)) end
      for i = 1, GetNumQuestLogEntries() do
        local title, _, _, isHeader = GetQuestLogTitle(i)
        if title and not isHeader then
          local was = IsQuestWatched(i) and true or false
          if not was and AFUI.Tracker and AFUI.Tracker.QuestieTrackerOn() then return end -- never touch the watches Questie's tracker lives on
          if not was then AddQuestWatch(i) end
          local n = P.Refresh()
          local _, _, _, _, _, _, _, qid = GetQuestLogTitle(i)
          rec.questieIcons = P.Questie() and P.QuestieIcons({ qid }) or nil -- Questie draws on its own after the watch hook (may need a frame: a count of 0 is not proof)
          if not was then RemoveQuestWatch(i); P.Refresh() end
          rec.questPins, rec.questTracked = n, title
          rec.arrowSize, rec.arrowFound = P.arrowSize, P.FixArrow() -- UI units the player arrow is set to (nil: the client's unit pin was not found)
          local mid = _G.WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
          rec.questieOnMap = P.Questie() and P.QuestieIcons({ qid }, mid) or nil -- Questie's world-map icons of this quest on the shown map
          return
        end
      end
    end)
    if not ok then bad("quest pins", "Lua error " .. tostring(err)) end
  end
  if step == "Map/Navigation" and AFUI.MapNavAudit then
    local ok, res = pcall(AFUI.MapNavAudit)
    if not ok then bad("navigation", "Lua error " .. tostring(res))
    else
      rec.nav = res.ids
      for _, p in ipairs(res.problems) do bad("navigation", p) end
    end
  end
  -- every shown scroll bar (the shared WinKit bar): inside its list's height, thumb inside its track, every piece sized and drawn
  local K = AFUI.WinKit
  for _, b in ipairs(K and K.bars or {}) do
    if visible(b) then
      local ok, why = pcall(K.BarProblem, b)
      if ok and why then bad("scrollbar " .. label(b.list), why) end
    end
  end
  rec.media = {}
  for p in pairs(media) do rec.media[#rec.media + 1] = p end
  table.sort(rec.media)
  return rec
end

---------------------------------------------------------------- stored result
local function audit()
  local a = db()
  a.steps, a.problems, a.run = a.steps or {}, a.problems or {}, a.run or {}
  return a
end

function A.Reset()
  local a = db()
  if a then a.steps, a.problems, a.run, a.media = {}, {}, {}, {} end
  return a
end

local function size(t, d)
  if type(t) == "string" then return #t + 2 end
  if type(t) ~= "table" or (d or 0) > 8 then return 6 end
  local n = 0
  for k, v in pairs(t) do n = n + #tostring(k) + 4 + size(v, (d or 0) + 1) end
  return n
end
A.Size = size

-- Keeps the stored audit under CAP_BYTES: drops the frame lists (newest step first), then the long stacks.
function A.Trim(a)
  for i = #a.steps, 1, -1 do
    if size(a) <= CAP_BYTES then return end
    a.steps[i].frames = nil
  end
  for i = 1, #a.errors do if size(a) > CAP_BYTES then a.errors[i].stack = cut(a.errors[i].stack, 100) end end
  while #a.problems > 100 and size(a) > CAP_BYTES do table.remove(a.problems) end
end

-- Stores one measurement as step `name` (problems into audit.problems, deduped and capped).
function A.Store(name, rec, extra)
  local a = audit()
  local step = { n = #a.steps + 1, name = name, t = stamp(), frames = rec.frames, suspects = rec.suspects, truncated = rec.truncated, np = #rec.problems, nav = rec.nav }
  a.media = a.media or {} -- every file of ours that a shown texture used, over the whole run (post-hoc: check each exists and is a power of two)
  for _, p in ipairs(rec.media or {}) do a.media[p] = true end
  for k, v in pairs(extra or {}) do step[k] = v end
  a.steps[#a.steps + 1] = step
  local have = {}
  for i = 1, #a.problems do have[a.problems[i]] = true end
  for _, p in ipairs(rec.problems) do
    if #a.problems < CAP_PROBLEMS and not have[p] then a.problems[#a.problems + 1] = p; have[p] = true end
  end
  return step
end

-- One measurement of the screen as it is (the headless preview's entry point).
function A.MeasureNow(name, roots)
  if not db() then return end
  return A.Store(name, A.Measure(name, roots))
end

---------------------------------------------------------------- the staged run
local queue, qi, wait, running = {}, 1, 0, false
local timer = CreateFrame("Frame")
timer:Hide()

local function call(name, ...)
  local f = _G[name]
  if type(f) ~= "function" then return false end
  return pcall(f, ...)
end
local function hide(name) -- closes a window the way the player would
  local f = _G[name]
  if f and visible(f) then if type(_G.HideUIPanel) == "function" and pcall(HideUIPanel, f) and not visible(f) then return end; m(f, "Hide") end
end
local function charTab(sub)
  return function()
    if not _G.CharacterFrame then return "no CharacterFrame" end
    if type(_G.CharacterFrame_ShowSubFrame) == "function" then ShowUIPanel(CharacterFrame); CharacterFrame_ShowSubFrame(sub)
    elseif not call("ToggleCharacter", sub) then return "no ToggleCharacter" end
  end
end
local function learnedProfessions()
  local header
  for i = 1, (GetNumSkillLines and GetNumSkillLines() or 0) do
    local n, isHeader = GetSkillLineInfo(i)
    if isHeader then header = n elseif header == "Professions" or header == (TRADE_SKILLS or "") then return true end
  end
end

local function steps()
  local S = {}
  local function add(name, open, roots, close, check) S[#S + 1] = { name = name, open = open, roots = roots, close = close, check = check } end
  local function tab(i, sub) return function() if not call("ToggleFriendsFrame", i) then return "no ToggleFriendsFrame" end; if sub then call("FriendsFrame_ShowSubFrame", sub) end end end
  add("HUD", function() end, ROOT_HUD, function() end)
  add("HUD/Tracker", function() end, { "AFUI_ObjectiveTracker", "AFUI_MicroMenu", "AFUI_BagBar" }, function() end)
  add("Character/Paperdoll", charTab("PaperDollFrame"), { "CharacterFrame" })
  add("Character/Reputation", charTab("ReputationFrame"), { "CharacterFrame" })
  add("Character/Skills", charTab("SkillFrame"), { "CharacterFrame" })
  add("Character/PvP", charTab("PVPFrame"), { "CharacterFrame" })
  if _G.UnitExists and UnitExists("pet") then add("Character/Pet", charTab("PetPaperDollFrame"), { "CharacterFrame" }) end
  add("Spellbook", function() if not call("ToggleSpellBook", "spell") then return "no ToggleSpellBook" end end, { "SpellBookFrame", "AFUI_SpellbookWindow" })
  add("Talents", function() if not call("ToggleTalentFrame") then return "no ToggleTalentFrame" end end, { "PlayerTalentFrame" })
  add("Professions", function()
    if not learnedProfessions() then return "no professions learned" end
    if not (AFUI.Professions and AFUI.Professions.ShowOverview) then return "no AFUI.Professions" end
    AFUI.Professions.ShowOverview()
  end, { "AFUI_ProfessionsFrame" })
  add("Social/Friends", tab(1, "FriendsListFrame"), { "FriendsFrame" }, function() hide("FriendsFrame") end)
  add("Social/Ignore", tab(1, "IgnoreListFrame"), { "FriendsFrame" }, function() hide("FriendsFrame") end)
  add("Social/Who", tab(2, "WhoFrame"), { "FriendsFrame" }, function() hide("FriendsFrame") end)
  add("Social/Raid", tab(AFUI.IS_243 and 5 or 4, "RaidFrame"), { "FriendsFrame" }, function() hide("FriendsFrame") end)
  add("Guild", function()
    if not (IsInGuild and IsInGuild()) then return "not in a guild" end
    AFUI.GuildWindow.Open("alone")
  end, { "AFUIGuildFrame" }, function() if AFUI.GuildWindow then AFUI.GuildWindow.Hide() end end)
  for _, t in ipairs({ { "Chat", "chat" }, { "Roster", "roster" }, { "Info", "info" }, { "Log", "log" } }) do -- J, one step per page (its click / strata / art checks are the "Guild" ones)
    add("Guild & Communities/" .. t[1], function()
      local C = AFUI.GuildCommunities
      if not (C and C.Open) then return "no AFUI.GuildCommunities" end
      if not (IsInGuild and IsInGuild()) then return "not in a guild" end
      C.Open(); C.SetTab(t[2])
    end, { "AFUIGuildCommFrame" }, function() if AFUI.GuildCommunities then AFUI.GuildCommunities.Hide() end end)
  end
  add("GroupFinder/LFG", function() if not call("ToggleLFGParentFrame") then return "no ToggleLFGParentFrame" end end, { "LFGParentFrame" })
  add("GroupFinder/LFM", function()
    if not call("ToggleLFGParentFrame") then return "no ToggleLFGParentFrame" end
    m(_G.LFGParentFrameTab2, "Click")
  end, { "LFGParentFrame" })
  add("Map", function() if not call("ToggleWorldMap") then return "no ToggleWorldMap" end end, { "WorldMapFrame" })
  add("Map/Navigation", function()
    if not call("ToggleWorldMap") then return "no ToggleWorldMap" end
    if _G.WorldMapFrame and not visible(_G.WorldMapFrame) then call("ToggleWorldMap") end -- it was open: the first call closed it
  end, { "WorldMapFrame" })
  add("QuestLog", function()
    if AFUI.QuestLog and AFUI.QuestLog.Toggle then AFUI.QuestLog.Toggle() elseif not call("ToggleQuestLog") then return "no quest log" end
  end, { "WorldMapFrame", "QuestLogFrame" }, function() hide("WorldMapFrame"); hide("QuestLogFrame") end)
  -- Not ToggleGameMenu: it calls SpellStopCasting / SpellStopTargeting / ClearTarget, which Blizzard blocks (and pops the "disable addon" dialog) when an addon calls it.
  add("GameMenu", function()
    local m = _G.GameMenuFrame
    if not m then return "no GameMenuFrame" end
    if _G.ShowUIPanel then ShowUIPanel(m) else m:Show() end
  end, { "GameMenuFrame" })
  add("Chat/Strip", function() local q = AFUI.ChatQoL; if not (q and q.Strip()) then return "no chat strip" end; q.UpdateStrip() end, { "AFUI_ChatStrip", "ChatFrame1" }, function() end)
  add("Chat/Copy", function() if not (AFUI.ChatQoL and AFUI.ChatQoL.ShowCopy()) then return "no Copy Chat window" end end, { "AFUI_ChatCopyWindow" }, function() hide("AFUI_ChatCopyWindow") end)
  add("Chat/Link", function() if not (AFUI.ChatQoL and AFUI.ChatQoL.OpenUrl("https://www.example.com/aztra")) then return "no copy box" end end, { "AFUI_ChatCopyBox" }, function() hide("AFUI_ChatCopyBox") end)
  for _, c in ipairs(AFUI.Settings and AFUI.Settings.CATEGORIES or {}) do -- the addon's settings window, one step per page (clicks, strata, art, the drag handle)
    add("Settings/" .. c.label, function() AFUI.Settings.Open(c.key) end, { "AFUI_SettingsFrame" }, function() AFUI.Settings.Close() end)
  end
  add("Wizard", function() if not AFUI.Wizard then return "no AFUI.Wizard" end; AFUI.Wizard.Show() end, { "AFUI_WizardFrame" }, function() if AFUI.Wizard then AFUI.Wizard.Hide() end end)
  local combined
  add("Bags", function()
    combined = AFUI.Bags and AFUI.Bags.IsCombined and AFUI.Bags.IsCombined()
    if combined then AFUI.Bags.SetCombined(false) end
    call("OpenAllBags", true)
  end, { "AFUI_BagWindow2", "AFUI_BagWindow3", "AFUI_BagWindow4" }, function() call("CloseAllBags") end)
  add("Bags/Combined", function()
    if not (AFUI.Bags and AFUI.Bags.SetCombined) then return "no AFUI.Bags" end
    AFUI.Bags.SetCombined(true); call("OpenAllBags", true)
  end, { "AFUI_BagWindowCombined" }, function() call("CloseAllBags"); if AFUI.Bags and AFUI.Bags.SetCombined then AFUI.Bags.SetCombined(combined and true or false) end end)
  add("EditMode", function() if not (AFUI.EditMode and AFUI.EditMode.Open) then return "no AFUI.EditMode" end; AFUI.EditMode.Open() end,
    { "AFUI_EditModeDialog" }, function() if AFUI.EditMode and AFUI.EditMode.Close then AFUI.EditMode.Close(true) end end)
  add("EditMode/Settings", function() -- a system's settings window must not cover the HUD Edit Mode dialog
    local EM = AFUI.EditMode
    if not (EM and EM.Open and EM.systems and AFUI.EditModeDialog) then return "no AFUI.EditMode" end
    EM.Open()
    local e = EM.systems.player or select(2, next(EM.systems))
    if e and EM.OnSelect then EM.OnSelect(e) end
  end, { "AFUI_EditModeDialog", "AFUI_EditModeSettings" }, function() if AFUI.EditMode and AFUI.EditMode.Close then AFUI.EditMode.Close(true) end end,
  function()
    local m, s = AFUI.EditModeDialog.Rects()
    if m and s and s[1] < m[3] and m[1] < s[3] and s[2] < m[4] and m[2] < s[4] then
      return { string.format("settings window overlaps the Edit Mode dialog (%d,%d,%d,%d over %d,%d,%d,%d)", s[1], s[2], s[3], s[4], m[1], m[2], m[3], m[4]) }
    end
    return {}
  end)
  add("ActionBars/Keybind", function() -- Quick Keybind Mode: every bindable button wears its overlay, the Okay / Cancel dialog shows
    local Q = AFUI.QuickKeybind
    if not (Q and Q.Enter) then return "no AFUI.QuickKeybind" end
    if InCombatLockdown() then return "in combat" end
    Q.Enter()
  end, { "AFUI_QuickKeybindDialog" }, function() if AFUI.QuickKeybind then AFUI.QuickKeybind.Exit(false) end end,
  function() return AFUI.QuickKeybind.Problems() end)
  add("Tooltip/Item", function() -- the first item in the bags: border pieces, quality tint, the Sell Price line
    if not _G.GameTooltip then return "no GameTooltip" end
    for bag = 0, 4 do
      for slot = 1, (GetContainerNumSlots and GetContainerNumSlots(bag) or 0) do
        if GetContainerItemLink and GetContainerItemLink(bag, slot) then
          GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR"); GameTooltip:SetBagItem(bag, slot); GameTooltip:Show()
          return
        end
      end
    end
    return "no item in the bags"
  end, { "GameTooltip" }, function() m(_G.GameTooltip, "Hide") end)
  add("Bank", function() -- the bank window as the client shows it (no banker needed to see the skin)
    if not (_G.BankFrame and AFUI.Bank and AFUI.Bank.done) then return "no BankFrame skin" end
    if type(_G.ShowUIPanel) == "function" then ShowUIPanel(_G.BankFrame) else _G.BankFrame:Show() end
  end, { "BankFrame" }, function() hide("BankFrame") end)
  add("Merchant", function()
    if not (_G.MerchantFrame and visible(_G.MerchantFrame)) then return "no merchant open (talk to a vendor, then run the audit)" end
  end, { "MerchantFrame" }, function() end)
  add("Tooltip/Spell", function()
    local b = _G.ActionButton1
    if not (_G.GameTooltip and b) then return "no GameTooltip or ActionButton1" end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT"); GameTooltip:SetAction(m(b, "GetAttribute", "action") or b.action or 1); GameTooltip:Show()
  end, { "GameTooltip" }, function() m(_G.GameTooltip, "Hide") end)
  return S
end

local function finish(why)
  running = false
  timer:Hide()
  local a = db()
  if a then
    a.run.finished, a.run.aborted = stamp(), why
    A.Trim(a)
  end
  say(why and ("stopped: " .. why) or ("done, " .. (a and #a.steps or 0) .. " steps, " .. (a and #a.problems or 0) .. " problems. Type /reload to write the file."))
end

function A.Tick(dt)
  if not running then timer:Hide(); return end
  if InCombatLockdown and InCombatLockdown() then return finish("combat") end
  wait = wait - (dt or 0)
  if wait > 0 then return end
  local act = queue[qi]
  if not act then return finish() end
  qi = qi + 1
  local ok, err = pcall(act.fn)
  if not ok then local a = db(); if a then a.run.errors = (a.run.errors or 0) + 1 end; A.Record("audit step failed: " .. tostring(err), "", errors()) end
  wait = queue[qi] and queue[qi].delay or 0
end
timer:SetScript("OnUpdate", function(_, dt) A.Tick(dt) end)

-- Starts the staged run (shotsOnly: screenshots without measuring). opt.sync runs every action at once (tests, preview).
function A.Start(shotsOnly, opt)
  opt = opt or {}
  if running then say("a run is already going"); return false end
  if InCombatLockdown and InCombatLockdown() then say("not in combat, try again out of combat"); return false end
  local a = db()
  if not a then say("SavedVariables are not loaded yet"); return false end
  A.Reset()
  local shots = 0
  a.run = { started = stamp(), build = select(2, GetBuildInfo()), version = (GetBuildInfo()), mode = shotsOnly and "shots" or "audit" }
  if UIParent then a.run.scale, a.run.w, a.run.h = r1(m(UIParent, "GetEffectiveScale") or 1), r1(m(UIParent, "GetWidth") or 0), r1(m(UIParent, "GetHeight") or 0) end
  queue, qi, wait, running = {}, 1, 0, true
  for _, s in ipairs(steps()) do
    local st = { skipped = false }
    local function act(delay, fn) queue[#queue + 1] = { delay = delay, fn = fn } end
    act(0.2, function()
      local why = s.open()
      st.step = { n = #a.steps + 1, name = s.name, t = stamp() }
      if why then st.skipped = true; st.step.skipped = why; a.steps[#a.steps + 1] = st.step end
    end)
    act(0.7, function()
      if st.skipped then return end
      if shotsOnly then a.steps[#a.steps + 1] = st.step else
        local rec = A.Measure(s.name, s.roots)
        if s.check then for _, why in ipairs(s.check() or {}) do rec.problems[#rec.problems + 1] = cut(s.name .. ": " .. why, 200) end end
        if s.name == "Talents" then for _, why in ipairs(A.TalentsFit()) do rec.problems[#rec.problems + 1] = cut(s.name .. ": " .. why, 200) end end
        if A.MOVABLE_STEPS[s.name:match("^[^/]+")] then for _, why in ipairs(A.MovableProblems(s.roots)) do rec.problems[#rec.problems + 1] = cut(s.name .. ": " .. why, 200) end end
        local stored = A.Store(s.name, rec)
        st.step = stored
      end
      if pcall(Screenshot) then shots = shots + 1; st.step.shot = shots; a.run.shots = shots end
    end)
    act(0.5, function()
      if st.skipped then return end
      if s.close then s.close() else for _, r in ipairs(s.roots) do hide(r) end end
    end)
  end
  say("started, " .. #queue / 3 .. " steps. Stay out of combat; do not touch the windows.")
  if opt.sync then
    while running and qi <= #queue do wait = 0; A.Tick(0) end
    if running then wait = 0; A.Tick(0) end
  else
    timer:Show()
  end
  return true
end

function A.Report()
  local a = db()
  local p, e = a and a.problems or {}, a and a.errors or {}
  say(#(a and a.steps or {}) .. " steps, " .. #p .. " problems, " .. #e .. " errors")
  for i = 1, math.min(#p, 15) do say("  " .. p[i]) end
  for i = 1, math.min(#e, 5) do say("  ERROR x" .. e[i].count .. " " .. cut(e[i].msg, 160)) end
end

---------------------------------------------------------------- /afui questie
-- Why Questie's own tracker (Questie_BaseFrame) might not show: everything readable about it, in chat and in AztraForeverUIDB.audit.questie.
function A.Questie()
  local r, T, Q = {}, AFUI.Tracker, _G.Questie
  local qdb = type(Q) == "table" and type(Q.db) == "table" and Q.db or {}
  local p, c = qdb.profile or {}, qdb.char or {}
  r.loaded = Q ~= nil or _G.QuestieLoader ~= nil
  r.version = type(Q) == "table" and (Q.version or (Q.GetAddonVersionString and select(2, pcall(Q.GetAddonVersionString)))) or nil
  r.trackerEnabled, r.alwaysShowTracker, r.expanded = p.trackerEnabled, p.alwaysShowTracker, c.isTrackerExpanded
  r.mode = T and T.Mode and T.Mode() or "?"
  local L = _G.QuestieLoader
  local okm, mod = pcall(function() return type(L) == "table" and L.ImportModule and L:ImportModule("QuestieTracker") end)
  r.trackerStarted = okm and type(mod) == "table" and mod.started or nil
  r.watched = T and T.WatchedIds and #T.WatchedIds() or 0
  r.blizzWatches = GetNumQuestWatches and GetNumQuestWatches() or 0
  local f = _G.Questie_BaseFrame
  r.frame = f ~= nil
  r.overlaps = {}
  if f then
    r.shown, r.visible, r.alpha = m(f, "IsShown") and true or false, m(f, "IsVisible") and true or false, m(f, "GetAlpha")
    r.strata, r.level, r.scale = m(f, "GetFrameStrata"), m(f, "GetFrameLevel"), m(f, "GetEffectiveScale")
    local par = m(f, "GetParent"); r.parent = par and m(par, "GetName") or "?"
    local ok, a1, a2, a3, a4, a5 = pcall(f.GetPoint, f, 1)
    r.point = ok and a1 and (tostring(a1) .. " " .. tostring(type(a2) == "table" and m(a2, "GetName") or a2) .. " " .. tostring(a3) .. " " .. tostring(a4) .. " " .. tostring(a5)) or nil
    r.left, r.top, r.w, r.h = m(f, "GetLeft"), m(f, "GetTop"), m(f, "GetWidth"), m(f, "GetHeight")
    local u = _G.UIParent
    local ul, ur, ut, ub, rr, rb = m(u, "GetLeft"), m(u, "GetRight"), m(u, "GetTop"), m(u, "GetBottom"), m(f, "GetRight"), m(f, "GetBottom")
    if r.left and ul and rr and ur and r.top and ut and rb and ub then r.onScreen = rr > ul and r.left < ur and r.top > ub and rb < ut end
    local sr = srect(f)
    if sr then
      local cx, cy = sr[1] + sr[3] / 2, sr[2] + sr[4] / 2
      local rank = (STRATA[r.strata or "MEDIUM"] or 4) * 100000 + (r.level or 0)
      local best
      for _, g in ipairs(list(u, "GetChildren")) do -- the same rank rule as ClickProblems: a higher strata / level covering the centre
        local gr = g ~= f and not m(g, "IsForbidden") and visible(g) and srect(g)
        if gr and inside(gr, cx, cy) and (m(g, "GetAlpha") or 1) > 0 and not related(f, g) then
          local grank = (STRATA[m(g, "GetFrameStrata") or "MEDIUM"] or 4) * 100000 + (m(g, "GetFrameLevel") or 0)
          if grank > rank and (not best or grank > best[2]) then best = { label(g), grank } end
        end
      end
      r.coveredBy = best and best[1] or nil
      local function hit(g, name) local gr = g and visible(g) and srect(g); if gr and overlap(sr, gr) then r.overlaps[#r.overlaps + 1] = name end end
      for _, nm in ipairs({ "AFUI_ObjectiveTracker", "AFUI_MicroMenu", "AFUI_BagBar" }) do hit(_G[nm], nm) end
      for _, k in ipairs({ "right", "right2" }) do hit(AFUI.Bars and AFUI.Bars[k] and AFUI.Bars[k].frame, "right bar " .. k) end
      hit(AFUI.MinimapRing, "minimap")
    end
  end
  r.net = T and T.net and (tostring(T.net.action) .. (T.net.shownAfter ~= nil and (" shownAfter=" .. tostring(T.net.shownAfter)) or "")) or "not run"
  r.errors = {}
  local a = db()
  for _, e in ipairs(a and a.errors or {}) do
    if tostring(e.msg):find("Questie", 1, true) or tostring(e.stack):find("Questie", 1, true) then r.errors[#r.errors + 1] = "x" .. e.count .. " " .. cut(e.msg, 200) end
  end
  if a then a.questie = r end
  return r
end

function A.QuestieReport()
  local r = A.Questie()
  local function s(v) return tostring(v) end
  say("Questie loaded=" .. s(r.loaded) .. " version=" .. s(r.version) .. " trackerEnabled=" .. s(r.trackerEnabled) .. " alwaysShow=" .. s(r.alwaysShowTracker)
    .. " expanded=" .. s(r.expanded) .. " started=" .. s(r.trackerStarted))
  say("our tracker=" .. s(r.mode) .. " watched=" .. s(r.watched) .. " blizzWatches=" .. s(r.blizzWatches) .. " safety net: " .. s(r.net))
  if not r.frame then say("Questie_BaseFrame: does not exist")
  else
    say("Questie_BaseFrame shown=" .. s(r.shown) .. " visible=" .. s(r.visible) .. " alpha=" .. s(r.alpha) .. " " .. s(r.strata) .. "/" .. s(r.level)
      .. " scale=" .. s(r.scale) .. " parent=" .. s(r.parent) .. " point=" .. s(r.point))
    say("  left=" .. s(r.left) .. " top=" .. s(r.top) .. " w=" .. s(r.w) .. " h=" .. s(r.h) .. " onScreen=" .. s(r.onScreen)
      .. " coveredBy=" .. s(r.coveredBy) .. " overlaps=" .. table.concat(r.overlaps, ","))
  end
  say(#r.errors .. " Questie errors" .. (r.errors[1] and (": " .. r.errors[1]) or ""))
  return r
end

---------------------------------------------------------------- /afui report
-- One line with everything worth pasting into a bug report (version, client, last audit, errors, blocked actions, Questie), in the copy box.
-- shortcut: one line because the copy box's EditBox is single-line; fine for a report this size.
function A.BuildReport()
  local parts = {}
  local function add(s) parts[#parts + 1] = s end
  local gv = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ver, build = gv and gv("AztraForeverUI", "Version") or "?", select(2, GetBuildInfo())
  add("AFUI " .. tostring(ver) .. " client " .. tostring(build))
  local a = db()
  local p, all = a and a.problems or {}, a and a.errors or {}
  local e = {} -- the saved log keeps errors across sessions: only this session's are news
  for _, x in ipairs(all) do if x.s == SESSION then e[#e + 1] = x end end
  add("audit: " .. (a and #(a.steps or {}) or 0) .. " steps, " .. #p .. " problems, " .. #e .. " errors this session (" .. (#all - #e) .. " older)")
  for i = 1, math.min(#p, 12) do add("P" .. i .. " " .. cut(p[i], 110)) end
  for i = 1, math.min(#e, 3) do add("E" .. i .. " x" .. e[i].count .. " " .. cut(e[i].msg, 140)) end
  local T = AFUI.Taint and AFUI.Taint.log or {}
  add("blocked: " .. #T)
  for i = math.max(1, #T - 2), #T do add("B" .. i .. " " .. T[i].event .. " " .. T[i].func) end
  local q = A.Questie and A.Questie() or {}
  add("Questie loaded=" .. tostring(q.loaded) .. " shown=" .. tostring(q.shown) .. " onScreen=" .. tostring(q.onScreen))
  return table.concat(parts, " | ")
end

function A.ReportBox()
  local text = A.BuildReport()
  local C = AFUI.ChatQoL
  if C and C.OpenUrl then C.OpenUrl(text, "Bug report", "Press Ctrl+C, paste it to Aztra, then Esc") else say(text) end
  return text
end

-- /afui words (the router and /afui help are Core.lua's)
local Slash = AFUI.Slash
Slash.Register("audit", function(rest) if rest:lower() == "report" then A.Report() else A.Start(false) end end,
  "check every window one by one (add 'report' to print the last result)", "/afui audit [report]")
Slash.Register("shots", function() A.Start(true) end, "the audit, with a screenshot of each window")
Slash.Register("report", function() A.ReportBox() end, "one line to copy and paste when something is wrong (version, errors, blocked actions)", "/afui report")
Slash.Register("questie", function() A.QuestieReport() end, "why Questie's tracker might not show")
Slash.Register("npdebuffs", function() AFUI.NameplateAuras.Toggle() end, "turn your debuffs on enemy nameplates on or off")
Slash.Register("resetwindows", function() AFUI.WinKit.resetWindows(); say("Window positions reset.") end, "put every window back at its default spot")
Slash.Register("keybind", function() AFUI.QuickKeybind.Toggle() end, "Quick Keybind Mode: hover an action button and press a key")

AFUI.On("ADDON_LOADED", function(_, addon) if addon == "AztraForeverUI" then errors() end end) -- flush errors that came before the SavedVariables
AFUI.On("PLAYER_REGEN_DISABLED", function() if running then finish("combat") end end)

-- /afui focus: three seconds later, what the mouse is over (name, type, parent chain, strata/level). For "I cannot click that" reports.
Slash.Register("focus", function()
  say("Put the mouse on the thing you cannot click... 3 seconds.")
  C_Timer.After(3, function()
    local f = _G.GetMouseFocus and GetMouseFocus() or (_G.GetMouseFoci and GetMouseFoci()[1])
    local parts, n = {}, 0
    while f and n < 6 do
      parts[#parts + 1] = (f.GetName and f:GetName() or "?") .. "[" .. (f.GetObjectType and f:GetObjectType() or "?") .. " " .. tostring(f.GetFrameStrata and f:GetFrameStrata()) .. "/" .. tostring(f.GetFrameLevel and f:GetFrameLevel()) .. "]"
      f = f.GetParent and f:GetParent(); n = n + 1
    end
    say("focus: " .. (parts[1] and table.concat(parts, " < ") or "nothing"))
  end)
end, "which frame the mouse is over after 3 seconds (for 'I cannot click it' reports)", "/afui focus")

-- /afui maphit: three seconds later, where the client thinks the mouse is on the world map and which map that point opens, against where the
-- canvas is really drawn under the mouse. For "clicking that place on the map does nothing / opens the wrong map".
Slash.Register("maphit", function()
  say("Put the mouse on the place on the map... 3 seconds.")
  C_Timer.After(3, function()
    local wm = _G.WorldMapFrame
    local sc = wm and wm.ScrollContainer
    if not (sc and sc.GetNormalizedCursorPosition and sc.Child and C_Map and C_Map.GetMapInfoAtPosition) then say("maphit: no map canvas API"); return end
    local function at(x, y)
      local ok, info = pcall(C_Map.GetMapInfoAtPosition, wm:GetMapID(), x, y)
      return ok and info and (tostring(info.name) .. " #" .. tostring(info.mapID)) or "nothing"
    end
    local ok, nx, ny = pcall(sc.GetNormalizedCursorPosition, sc)
    if not ok then say("maphit: client cursor failed: " .. tostring(nx)); return end
    local cx, cy = GetCursorPosition()
    local ec, ch = sc.Child:GetEffectiveScale(), sc.Child
    local gx = (cx - ch:GetLeft() * ec) / (ch:GetWidth() * ec)
    local gy = (ch:GetTop() * ec - cy) / (ch:GetHeight() * ec)
    say(string.format("maphit: map #%s | client %.3f,%.3f -> %s | drawn %.3f,%.3f -> %s", tostring(wm:GetMapID()), nx or -1, ny or -1, at(nx, ny), gx, gy, at(gx, gy)))
    -- every child map (zones, cities) whose rectangle on this map holds the point, and how many children / links the map has: when the position API says
    -- "nothing" this shows whether the city is a child at all and where its rectangle is
    local id, hits, nkids = wm:GetMapID(), {}, 0
    local okc, kids = pcall(C_Map.GetMapChildrenInfo, id, nil, true)
    if okc and type(kids) == "table" then
      nkids = #kids
      for _, k in ipairs(kids) do
        local okr, l, r, t, b = pcall(C_Map.GetMapRectOnMap, k.mapID, id)
        if okr and l and r and t and b and nx >= math.min(l, r) and nx <= math.max(l, r) and ny >= math.min(t, b) and ny <= math.max(t, b) then
          hits[#hits + 1] = tostring(k.name) .. " #" .. tostring(k.mapID) .. " type" .. tostring(k.mapType)
        end
      end
    end
    local okl, links = pcall(function() return C_Map.GetMapLinksForMap and C_Map.GetMapLinksForMap(id) end)
    say("maphit: children " .. nkids .. ", links " .. ((okl and type(links) == "table") and #links or "?") .. ", children holding the point: " .. (hits[1] and table.concat(hits, "; ") or "none"))
    if okc and type(kids) == "table" then -- every child with its rectangle on this map (left right top bottom): where the city really is
      for _, k in ipairs(kids) do
        local okr, l, r, t, b = pcall(C_Map.GetMapRectOnMap, k.mapID, id)
        say(string.format("  child %s #%s type%s rect %s", tostring(k.name), tostring(k.mapID), tostring(k.mapType),
          (okr and l) and string.format("%.3f %.3f %.3f %.3f", l, r, t, b) or "none"))
      end
    end
  end)
end, "where the world map thinks the mouse is, and which map that opens (3 seconds delay)", "/afui maphit")

-- /afui bars: each action bar from the bottom up as the player sees it: our bar key, the client's frame and first button, its action slot, its first key, and where it is.
Slash.Register("bars", function()
  local rows = {
    { "main", "ActionButton1", "ACTIONBUTTON1" }, { "bottomleft", "MultiBarBottomLeftButton1", "MULTIACTIONBAR1BUTTON1" },
    { "bottomright", "MultiBarBottomRightButton1", "MULTIACTIONBAR2BUTTON1" }, { "right", "MultiBarRightButton1", "MULTIACTIONBAR3BUTTON1" },
    { "right2", "MultiBarLeftButton1", "MULTIACTIONBAR4BUTTON1" } }
  for _, r in ipairs(rows) do
    local bar = AFUI.Bars and AFUI.Bars[r[1]]
    local f = bar and bar.frame
    local b = _G[r[2]]
    local act = b and ((b.GetAttribute and b:GetAttribute("action")) or (ActionButton_GetPagedID and ActionButton_GetPagedID(b))) or "?"
    local key = GetBindingKey and GetBindingKey(r[3]) or "-"
    say(string.format("bar %s (%s): shown=%s x=%.0f y=%.0f action=%s key=%s", r[1], r[2], tostring(f and f:IsShown()), f and f:GetLeft() or -1, f and f:GetBottom() or -1, tostring(act), tostring(key)))
  end
end, "each action bar from the bottom up with its slot and first key (for bar order reports)", "/afui bars")
