-- Forever's Game Menu (Esc), docs/forever-ref/video-notes/gamemenu.md (frames 317-322): a near-black dialog with the bronze diamond-stud border of the Edit Mode
-- windows, the server logo straddling its top edge (it was a "Game Menu" plaque), red 192 x 28 u buttons in four groups:
--   System, Sound, Interface, Key Bindings, Shop  /  AddOns, Edit Mode, Aztra's Forever UI, Support, Macros  /  Log Out, Exit Game  /  Return to Game.
-- The client's own buttons are re-skinned and laid out again (their OnClick, secure paths and visibility rules stay Blizzard's). The options windows they open (Video / Sound /
-- Interface / Key Bindings) are the client's own and nothing of ours touches them. Edit Mode's button (EditMode/Overlay.lua) joins group two.
-- Button names (Classic client FrameXML GameMenuFrame.xml; not in the Gethe tag's 2.5.3 subset, every one is looked up defensively): GameMenuFrame,
-- GameMenuButtonStore / UIOptions / Addons / Help / Macros / Logout / Quit / Continue (shown), GameMenuButtonOptions / SoundOptions / Keybindings / Ratings /
-- WhatsNew (hidden); GameMenuFrame_UpdateVisibleButtons() (2.5.3) re-chains them and sets the height on every show.
AFUI = AFUI or {}
local G = {}
AFUI.GameMenu = G

-- Measured on Mat's 2560x1440 recording (video3 f0197, 1 u = 1.40625 px): panel 245 x 455, buttons 192 x 28 every 36 u, group gaps 20 u, first button 46 u (66 now, under the logo)
-- from the top, 33 u under the last one. Labels are 24 px (17 u).
G.W, G.BTN_W, G.BTN_H, G.PITCH, G.GROUP_GAP, G.TOP, G.BOTTOM = 245, 192, 28, 36, 20, 66, 33 -- TOP 46 in the recording + 20 u: the logo hangs 56 u into the panel
G.FONT, G.FONT_SIZE = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 17
AFUI.GameMenuOpen = false -- true while the menu is shown; AFUI.RegisterCallback("AFUI_GAMEMENU_STATE", function(event, open) ... end) hears every change
G.GROUPS = {
  { "GameMenuButtonOptions", "GameMenuButtonSoundOptions", "GameMenuButtonUIOptions", "GameMenuButtonKeybindings", "GameMenuButtonStore" },
  { "GameMenuButtonAddons", "AFUI_GameMenuButtonEditMode", "AFUI_GameMenuButtonSettings", "GameMenuButtonHelp", "GameMenuButtonMacros" },
  { "GameMenuButtonLogout", "GameMenuButtonQuit" },
  { "GameMenuButtonContinue" },
}
G.HIDDEN = { "GameMenuButtonRatings", "GameMenuButtonWhatsNew" }
G.TEXT = { GameMenuButtonStore = "Shop", GameMenuButtonHelp = "Support", GameMenuButtonQuit = "Exit Game", GameMenuButtonContinue = "Return to Game" }

-- Where every button goes: shown(name) says whether the client shows it. Returns { name = y } (TOP-relative, negative) and the panel height.
function G.Plan(shown)
  local out, y, first = {}, -G.TOP, true
  for _, group in ipairs(G.GROUPS) do
    local any
    for _, name in ipairs(group) do
      if shown(name) then
        if not any and not first then y = y - G.GROUP_GAP end
        out[name] = y; y = y - G.PITCH; any, first = true, false
      end
    end
  end
  return out, -y - (G.PITCH - G.BTN_H) + G.BOTTOM -- the last button's bottom edge plus the bottom padding
end

-- Addon-internal events (the WoW event frame refuses names it does not know): AFUI.RegisterCallback(event, fn), AFUI.FireCallback(event, ...).
if not AFUI.FireCallback then
  local subs = {}
  function AFUI.RegisterCallback(event, fn) subs[event] = subs[event] or {}; table.insert(subs[event], fn) end
  function AFUI.FireCallback(event, ...)
    for _, fn in ipairs(subs[event] or {}) do local n, a = select("#", ...), { ... }; xpcall(function() fn(event, unpack(a, 1, n)) end, geterrorhandler()) end
  end
end

local frame, panel
local function g(n) return _G[n] end

-- The micro menu and bag bar grey out while the menu is open (video f0197). They belong to BarExtras.lua, which is not touched: this only listens to the event.
local greyed = {}
local function grey(root, on)
  if not root then return end
  local function walk(f, depth)
    if f.GetRegions then
      for _, r in ipairs({ f:GetRegions() }) do
        if r.SetDesaturated and r.GetObjectType and r:GetObjectType() == "Texture" then
          if on then greyed[r] = true; r:SetDesaturated(true) elseif greyed[r] then greyed[r] = nil; r:SetDesaturated(false) end
        end
      end
    end
    if depth < 4 and f.GetChildren then for _, c in ipairs({ f:GetChildren() }) do walk(c, depth + 1) end end
  end
  walk(root, 0)
end
function G.Grey(on) grey(AFUI.MicroMenu, on); grey(AFUI.BagBar, on) end

function G.SetOpen(open)
  open = open and true or false
  if AFUI.GameMenuOpen == open then return end
  AFUI.GameMenuOpen = open
  AFUI.FireCallback("AFUI_GAMEMENU_STATE", open)
end
AFUI.RegisterCallback("AFUI_GAMEMENU_STATE", function(_, open) G.Grey(open) end)

-- The label is 17 u (24 px) and stays that size: the red button's paint() swaps font objects on every hover / press.
local function bigLabel(b)
  local t = b.GetFontString and b:GetFontString()
  if not t or t.afBig then return end
  t.afBig = true
  t:SetFont(G.FONT, G.FONT_SIZE, "")
  if t.SetFontObject then hooksecurefunc(t, "SetFontObject", function(self) self:SetFont(G.FONT, G.FONT_SIZE, "") end) end
end

function G.Layout()
  if not frame or not panel then return end
  local K = AFUI.WinKit
  for _, n in ipairs(G.HIDDEN) do local b = g(n); if b then b:Hide() end end
  local plan, h = G.Plan(function(n) local b = g(n); return b and b:IsShown() end)
  for name, y in pairs(plan) do
    local b = g(name)
    if K and not b.afArt then
      K.button(b, G.BTN_W, G.BTN_H, true)
      if b.afArt and b.afArt.hl then b.afArt.hl:SetAlpha(1) end -- hover: the full bright red (#e90003), not the 0.5 of the other windows
    end
    bigLabel(b)
    b:SetWidth(G.BTN_W); b:SetHeight(G.BTN_H)
    if G.TEXT[name] then b:SetText(G.TEXT[name]) end
    b:ClearAllPoints(); b:SetPoint("TOP", frame, "TOP", 0, y)
  end
  frame:SetWidth(G.W); frame:SetHeight(h)
  panel.Resize(G.W, h)
end

function G.Adopt(btn) -- the Edit Mode button
  btn.afGameMenu = true
  G.Layout()
end

-- The server logo (CRUSADER-STORM) straddling the top edge, replacing the old "Game Menu" plate: a crest over the menu, a third of its height inside the panel
-- (G.TOP leaves room under it). Two light effects, both additive and baked from the logo's own alpha (tools/crusader-logo.mjs; clients have no masks), so no light
-- ever lands outside the silhouette. Nothing is created per frame: the sheets are 4 x 4 frames of 128 px on one 512 texture, stepped by texcoords.
--  * Idle: a specular band crosses the logo (smoothstep eased, two neighbouring frames cross-faded), then a pause, forever, only while the menu is shown.
--  * Mouse over the logo (hit-tested on its un-zoomed rect, so the zoom never makes the edge flicker): the sweep fades out and stays off, a radial glow follows the cursor
--    (4 baked glows blended bilinearly, the position lagged, a little parallax), and the art zooms in with an overshoot; on leave the glow fades, the zoom eases back and
--    the sweep restarts after SWEEP_RESUME s.
G.LOGO_SIZE, G.LOGO_OVERLAP = 168, 56 -- 168 u square (the logo itself is ~161 u wide); 56 u (a third) hangs into the panel
G.SWEEP_GRID, G.SWEEP_FRAMES, G.SWEEP_PASS, G.SWEEP_PAUSE, G.SWEEP_LEAD = 4, 16, 1.6, 3.4, 1 -- seconds; LEAD = seconds from opening the menu to the first pass
G.SWEEP_FADE, G.SWEEP_RESUME = 0.12, 0.6 -- the light goes out in 0.12 s when the mouse arrives mid-pass; the sweep restarts 0.6 s after the mouse leaves
G.HOVER_ZOOM, G.ZOOM_IN, G.ZOOM_OUT = 1.12, 0.25, 0.3 -- the logo's scale on hover (ease-out-back, ~10 % overshoot of the 0.12), seconds in and out
G.GLOW_POINTS, G.GLOW_IN, G.GLOW_OUT, G.GLOW_FOLLOW, G.GLOW_PARALLAX = 4, 0.15, 0.25, 14, 4 -- baked glow grid; ramp seconds; follow speed (1/s); parallax in u at the edge
local sweepCoords = {}
for i = 0, G.SWEEP_FRAMES - 1 do
  local c, r, e = i % G.SWEEP_GRID, math.floor(i / G.SWEEP_GRID), 0.5 / 512 -- half a texel in: no bleed from the next frame
  sweepCoords[i] = { c / G.SWEEP_GRID + e, (c + 1) / G.SWEEP_GRID - e, r / G.SWEEP_GRID + e, (r + 1) / G.SWEEP_GRID - e }
end

-- Shows the sweep at frame position pos (0 .. FRAMES - 1, fractional: the two frames around it cross-faded) at strength a (0 .. 1), or nothing for nil.
function G.SetSweepPos(pos, a)
  local f = G.logo
  if not f then return end
  if not pos or a <= 0 then
    f.afSweepFrame = nil
    if f.afS1 then f.afS1 = nil; f.sweep:Hide(); f.sweep2:Hide() end
    return
  end
  local n = math.floor(pos)
  if n > G.SWEEP_FRAMES - 2 then n = G.SWEEP_FRAMES - 2 end
  local fr = pos - n
  f.afSweepFrame = math.floor(pos + 0.5) -- the nearest frame (the one with most of the light)
  if f.afS1 ~= n then
    local c, d = sweepCoords[n], sweepCoords[n + 1]
    f.sweep:SetTexCoord(c[1], c[2], c[3], c[4]); f.sweep2:SetTexCoord(d[1], d[2], d[3], d[4])
    f.afS1 = n; f.sweep:Show(); f.sweep2:Show()
  end
  f.sweep:SetAlpha((1 - fr) * a); f.sweep2:SetAlpha(fr * a)
end
-- Shows exactly sweep frame n (0-based), or nothing for nil.
function G.SetSweepFrame(n) G.SetSweepPos(n, 1) end

-- The clock: t seconds into the cycle (a pass of SWEEP_PASS s, smoothstep eased, then SWEEP_PAUSE s of no light).
function G.SweepPos(t)
  if t >= G.SWEEP_PASS then return nil end
  local u = t / G.SWEEP_PASS
  return u * u * (3 - 2 * u) * (G.SWEEP_FRAMES - 1)
end
function G.SweepAt(t)
  local p = G.SweepPos(t)
  return p and math.floor(p + 0.5)
end
-- Zoom easing: from -> to at progress p (0 .. 1); in = ease-out-back (overshoots, settles), out = ease-out-cubic. The endpoints are exact.
function G.ZoomAt(from, to, p, entering)
  if p >= 1 then return to end
  if p <= 0 then return from end
  local q = p - 1
  local e = entering and (1 + 2.70158 * q * q * q + 1.70158 * q * q) or (1 + q * q * q)
  return from + (to - from) * e
end
-- The cursor over a frame: (true, u, v) with u, v in 0 .. 1 from the left / top, or false. Replaced by the previews and specs.
function G.CursorUV(f)
  if not GetCursorPosition or not f.GetLeft then return false end
  local l, b = f:GetLeft(), f:GetBottom()
  if not l or not b then return false end
  local x, y = GetCursorPosition()
  if not x then return false end
  local s = f:GetEffectiveScale()
  local u, v = (x / s - l) / f:GetWidth(), (y / s - b) / f:GetHeight()
  if u < 0 or u > 1 or v < 0 or v > 1 then return false end
  return true, u, 1 - v
end

function G.SweepUpdate(f, dt)
  local fd = f.afSweepFade
  if f.afHover or f.afResume > 0 then -- stopped: a pass caught mid-way goes out quickly
    if fd > 0 then
      fd = fd - dt / G.SWEEP_FADE
      if fd < 0 then fd = 0 end
      f.afSweepFade = fd
      G.SetSweepPos(f.afSweepPos, fd)
    end
    return
  end
  local t = f.afSweepT + dt
  if t >= G.SWEEP_PASS + G.SWEEP_PAUSE then t = t - (G.SWEEP_PASS + G.SWEEP_PAUSE) end
  f.afSweepT = t
  local p = G.SweepPos(t)
  f.afSweepPos = p
  G.SetSweepPos(p, 1)
end

-- The glow at (afGu, afGv) with strength s: the 4 baked glows around it, weighted bilinearly (the weights add up to s, so the brightness stays even).
function G.DrawGlow(f, s)
  local P, g = G.GLOW_POINTS, f.glow
  local x, y = f.afGu * (P - 1), f.afGv * (P - 1)
  local i, j = math.floor(x), math.floor(y)
  if i > P - 2 then i = P - 2 end
  if j > P - 2 then j = P - 2 end
  local fu, fv = x - i, y - j
  if i ~= f.afGi or j ~= f.afGj then
    f.afGi, f.afGj = i, j
    for k = 1, 4 do
      local c = sweepCoords[(j + (k > 2 and 1 or 0)) * G.SWEEP_GRID + i + (k % 2 == 0 and 1 or 0)]
      g[k]:SetTexCoord(c[1], c[2], c[3], c[4])
    end
  end
  g[1]:SetAlpha((1 - fu) * (1 - fv) * s); g[2]:SetAlpha(fu * (1 - fv) * s); g[3]:SetAlpha((1 - fu) * fv * s); g[4]:SetAlpha(fu * fv * s)
  if not f.afGlowOn then f.afGlowOn = true; for k = 1, 4 do g[k]:Show() end end
  f.zoomer:SetPoint("CENTER", f, "CENTER", (f.afGu - 0.5) * G.GLOW_PARALLAX * s, (0.5 - f.afGv) * G.GLOW_PARALLAX * s) -- the art leans toward the light
end
function G.GlowOff(f)
  if not f.afGlowOn then return end
  f.afGlowOn = false
  for k = 1, 4 do f.glow[k]:Hide() end
  f.zoomer:SetPoint("CENTER", f, "CENTER", 0, 0)
end

-- One tick of the logo's state machine (dt seconds): hover from the cursor, then sweep, glow and zoom.
function G.LogoUpdate(f, dt)
  local hov, u, v = G.CursorUV(f)
  if hov ~= f.afHover then
    f.afHover = hov
    f.afZFrom, f.afZT = f.afZoom, 0
    f.afResume = G.SWEEP_RESUME
    if hov and f.afGlowI <= 0 then f.afGu, f.afGv = u, v end -- the glow is born under the cursor and then follows it
  end
  if hov then f.afTu, f.afTv = u, v
  elseif f.afResume > 0 then
    f.afResume = f.afResume - dt
    if f.afResume <= 0 then f.afResume, f.afSweepT, f.afSweepFade = 0, 0, 1 end -- the next pass starts from the beginning
  end
  G.SweepUpdate(f, dt)
  -- glow: intensity ramps in over GLOW_IN s, out over GLOW_OUT s; the position follows the cursor with a lag
  local gi = f.afGlowI
  if hov then gi = gi + dt / G.GLOW_IN; if gi > 1 then gi = 1 end
  elseif gi > 0 then gi = gi - dt / G.GLOW_OUT; if gi < 0 then gi = 0 end end
  f.afGlowI = gi
  if gi > 0 then
    local k = 1 - math.exp(-G.GLOW_FOLLOW * dt)
    local gu, gv = f.afGu + (f.afTu - f.afGu) * k, f.afGv + (f.afTv - f.afGv) * k
    f.afGu, f.afGv = gu < 0 and 0 or gu > 1 and 1 or gu, gv < 0 and 0 or gv > 1 and 1 or gv -- never leaves the logo's square
    G.DrawGlow(f, gi * gi * (3 - 2 * gi))
  else
    G.GlowOff(f)
  end
  -- zoom
  local zt = f.afZT
  if zt < 1 then
    zt = zt + dt / (hov and G.ZOOM_IN or G.ZOOM_OUT)
    if zt > 1 then zt = 1 end
    f.afZT = zt
    f.afZoom = G.ZoomAt(f.afZFrom, hov and G.HOVER_ZOOM or 1, zt, hov)
    f.zoomer:SetScale(f.afZoom)
  end
end

-- Back to the resting state (shown: the first pass in LEAD s; hidden: nothing lit, scaled or updating).
function G.LogoReset(f)
  f.afHover, f.afResume, f.afSweepFade, f.afSweepPos = false, 0, 1, nil
  f.afSweepT = G.SWEEP_PASS + G.SWEEP_PAUSE - G.SWEEP_LEAD
  f.afGlowI, f.afGu, f.afGv, f.afTu, f.afTv, f.afGi, f.afGj = 0, 0.5, 0.5, 0.5, 0.5, nil, nil
  f.afZoom, f.afZFrom, f.afZT = 1, 1, 1
  f.zoomer:SetScale(1)
  G.GlowOff(f)
  G.SetSweepPos(nil)
end

local function logoFrame(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetWidth(G.LOGO_SIZE); f:SetHeight(G.LOGO_SIZE)
  f:SetFrameLevel(parent:GetFrameLevel() + 4)
  f:SetPoint("CENTER", parent, "TOP", 0, G.LOGO_SIZE / 2 - G.LOGO_OVERLAP)
  -- f keeps its size: it is the hit rect. The art lives in a child scaled around its centre, so the zoom pushes nothing and nothing clips it.
  local z = CreateFrame("Frame", nil, f)
  z:SetWidth(G.LOGO_SIZE); z:SetHeight(G.LOGO_SIZE); z:SetPoint("CENTER", f, "CENTER", 0, 0)
  local t = z:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(z)
  t:SetTexture("Interface\\AddOns\\AztraForeverUI\\Media\\UI-GameMenu-Logo")
  local glow = {}
  for k = 1, 4 do
    local g = z:CreateTexture(nil, "OVERLAY"); g:SetAllPoints(z)
    g:SetTexture("Interface\\AddOns\\AztraForeverUI\\Media\\UI-GameMenu-Glow")
    g:SetBlendMode("ADD"); g:Hide()
    glow[k] = g
  end
  local s, s2 = z:CreateTexture(nil, "OVERLAY"), z:CreateTexture(nil, "OVERLAY")
  for _, x in ipairs({ s, s2 }) do
    x:SetAllPoints(z); x:SetTexture("Interface\\AddOns\\AztraForeverUI\\Media\\UI-GameMenu-Sweep"); x:SetBlendMode("ADD"); x:Hide()
  end
  f.art, f.sweep, f.sweep2, f.glow, f.zoomer, f.afOverhang = t, s, s2, glow, z, true -- the crest straddles the panel edge on purpose (the audit skips it)
  G.logo = f
  G.LogoReset(f)
  f:SetScript("OnShow", function(self)
    G.LogoReset(self)
    self:SetScript("OnUpdate", G.LogoUpdate)
  end)
  f:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil); G.LogoReset(self) end)
  if f:IsShown() and parent:IsShown() then f:GetScript("OnShow")(f) end
  return f
end

local function setup()
  frame = _G.GameMenuFrame
  local P, W = AFUI.Professions and AFUI.Professions.Kit, AFUI.EditModeWidgets
  if not frame or frame.afGM or not P or not W then return end
  frame.afGM = true
  P.hideRegions(frame)
  if frame.SetBackdrop then frame:SetBackdrop(nil) end
  panel = W.Panel(nil, G.W, 400)
  panel:SetParent(frame)
  panel:SetFrameStrata(frame:GetFrameStrata()); panel:SetFrameLevel(frame:GetFrameLevel())
  panel:EnableMouse(false); AFUI.SetColor(panel.bg, 0.03, 0.025, 0.02, 0.58) -- video3 f0197: the world shows through (the panel darkens it to ~0.5, not an opaque near-black)
  panel:ClearAllPoints(); panel:SetAllPoints(frame)
  panel:Show()
  if AFUI.Settings and not _G.AFUI_GameMenuButtonSettings then -- "Aztra's Forever UI": the addon's settings window, in the Edit Mode group
    local b = CreateFrame("Button", "AFUI_GameMenuButtonSettings", frame, "GameMenuButtonTemplate")
    b:SetText("Aztra's Forever UI")
    b:SetScript("OnClick", function()
      if HideUIPanel then HideUIPanel(frame) else frame:Hide() end
      AFUI.Settings.Open()
    end)
  end
  local crest = logoFrame(frame)
  if AFUI.WinKit then AFUI.WinKit.makeMovable(frame, crest, "gamemenu") end -- drag by the logo
  G.Layout()
  if type(GameMenuFrame_UpdateVisibleButtons) == "function" then hooksecurefunc("GameMenuFrame_UpdateVisibleButtons", G.Layout) end
  frame:HookScript("OnShow", function() G.Layout(); G.SetOpen(true) end)
  frame:HookScript("OnHide", function() G.SetOpen(false) end)
  if frame:IsShown() then G.SetOpen(true) end
end

G.Setup, G.LogoFrame = setup, logoFrame
AFUI.RegisterModule("GameMenu", { OnLogin = function() AFUI.RunOutOfCombat(setup) end })
