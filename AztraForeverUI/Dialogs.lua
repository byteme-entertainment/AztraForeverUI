-- Forever's dialogs and dropdown menus: the StaticPopup confirmations (StaticPopup1..4) and the dropdown lists (DropDownList1..3) in the look of the Game Menu / tooltips.
-- SKIN ONLY: every client frame keeps its scripts, buttons, edit box, timeouts and Escape handling. Nothing here replaces, shows, hides or anchors a Blizzard
-- frame and no function of the client is called, so a popup shown in combat still works and a protected frame is never touched (only hooksecurefunc / HookScript).
--   Popups: the client's backdrop is cleared and the Forever dialog panel (EditModeWidgets.Panel, the Game Menu's metal frame) is drawn BEHIND the text; the buttons get
--           the red button art (WinKit.button), the edit box the Forever search-box art (WinKit.edit).
--   Dropdown lists: a dark box with a grey-gold rim (the tooltip colours) replaces the client's two backdrops (made transparent, not removed: the client recolours them),
--           the row highlight is Forever's recipe-row glow, check marks and submenu arrows are gold.
-- Setting "dialogsRestyle" (General page, default on); read once at login, so switching it off takes effect after /reload.
-- Names (2.4.3 / 2.5.3 FrameXML StaticPopup.xml / UIDropDownMenu.xml): StaticPopupN with NButton1..4, NEditBox, NWideEditBox, NAlertIcon; DropDownListN with
-- DropDownListNBackdrop / NMenuBackdrop and DropDownListNButtonM with Highlight / Check / UnCheck / ExpandArrow children.
AFUI = AFUI or {}
local D = {}
AFUI.Dialogs = D

D.POPUPS, D.LISTS = 4, 3
D.BG = { 0.051, 0.047, 0.082, 0.96 } -- the tooltip fill (Tooltips.lua T.BG)
D.RIM = { 0.639, 0.561, 0.42, 1 }    -- the tooltip line (T.EDGE), grey-gold
D.GOLD = { 1, 0.82, 0 }
D.HOVER = 0.5                         -- row highlight strength

local function g(n) return n and _G[n] end

function D.Enabled() return AFUI.GetSetting("dialogsRestyle", true) and true or false end

-- The client's own backdrop gone (the Tooltips way: BackdropTemplate on 2.5.3, a NineSlice child on later clients, none on 2.4.3).
local function clearBackdrop(f)
  if f.SetBackdrop then f:SetBackdrop(nil) end
  local ns = rawget(f, "NineSlice")
  if ns and ns.SetAlpha then ns:SetAlpha(0) end
end
D.ClearBackdrop = clearBackdrop

-- A dark box with a 1 px rim on a child frame of its own, BEHIND the frame's text (one level below it). Built once; returns it. Used by the dropdown lists and the loot roll frames.
function D.Rim(f)
  if not f or f.afRim then return f and f.afRim end
  if not (f.CreateTexture and _G.CreateFrame) then return end
  local host = CreateFrame("Frame", nil, f)
  host:SetAllPoints(f); host:EnableMouse(false)
  local lvl = f:GetFrameLevel() or 1
  host:SetFrameLevel(lvl > 0 and lvl - 1 or 0)
  host.fill = host:CreateTexture(nil, "BACKGROUND"); host.fill:SetAllPoints(host)
  AFUI.SetColor(host.fill, D.BG[1], D.BG[2], D.BG[3], D.BG[4])
  host.edges = {}
  for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = host:CreateTexture(nil, "BORDER"); AFUI.SetColor(t, D.RIM[1], D.RIM[2], D.RIM[3], D.RIM[4])
    t:SetPoint(e[1], host, e[1], 0, 0); t:SetPoint(e[2], host, e[2], 0, 0)
    if e[3] then t:SetHeight(1) else t:SetWidth(1) end
    host.edges[#host.edges + 1] = t
  end
  f.afRim = host
  return host
end

---------------------------------------------------------------- StaticPopup
local function panelFor(f)
  if f.afPanel then return f.afPanel end
  local W = AFUI.EditModeWidgets
  if not (W and W.Panel) then return D.Rim(f) end
  local p = W.Panel(nil, f:GetWidth() or 0, f:GetHeight() or 0)
  p:SetParent(f); p:SetFrameStrata(f:GetFrameStrata())
  local lvl = f:GetFrameLevel() or 1
  p:SetFrameLevel(lvl > 0 and lvl - 1 or 0) -- behind the popup's own text
  p:EnableMouse(false)
  AFUI.SetColor(p.bg, 0.03, 0.025, 0.02, 0.94)
  p:ClearAllPoints(); p:SetAllPoints(f); p:Show()
  f.afPanel = p
  return p
end

local function fit(f)
  local p = f.afPanel
  if p and p.Resize then p.Resize(f:GetWidth() or 0, f:GetHeight() or 0) end
end

-- One popup: the panel, the red buttons, the edit boxes. Idempotent; runs again on every show (the client reuses the four frames for every dialog).
function D.SkinPopup(i)
  local f = g("StaticPopup" .. i)
  if not f then return end
  if f.IsProtected and f:IsProtected() and InCombatLockdown() then return end -- never touch a protected frame in combat (a popup is not one; belt and braces)
  clearBackdrop(f)
  panelFor(f); fit(f)
  local K = AFUI.WinKit
  if K then
    for b = 1, 4 do
      local btn = g("StaticPopup" .. i .. "Button" .. b)
      if btn and not btn.afArt then K.button(btn, nil, (btn:GetHeight() or 0) > 0 and btn:GetHeight() or nil, true) end
    end
    for _, k in ipairs({ "EditBox", "WideEditBox" }) do K.edit(g("StaticPopup" .. i .. k)) end
  end
  if not f.afDlgHooked and f.HookScript then
    f.afDlgHooked = true
    f:HookScript("OnShow", function(self) D.SkinPopup(i) end)
    f:HookScript("OnSizeChanged", fit)
  end
end

---------------------------------------------------------------- dropdown lists
local function skinButton(b)
  if not b or b.afDlg then return end
  b.afDlg = true
  local n = b:GetName()
  local hl = g(n .. "Highlight")
  if hl then AFUI.SetAtlas(hl, "professions_recipe_hover"); hl:SetAlpha(D.HOVER) end
  for _, s in ipairs({ "Check", "UnCheck" }) do local t = g(n .. s); if t and t.SetVertexColor then t:SetVertexColor(D.GOLD[1], D.GOLD[2], D.GOLD[3]) end end
  local arrow = g(n .. "ExpandArrow")
  local nt = arrow and arrow.GetNormalTexture and arrow:GetNormalTexture()
  if nt and nt.SetVertexColor then nt:SetVertexColor(D.GOLD[1], D.GOLD[2], D.GOLD[3]) end
end

function D.SkinList(level)
  level = level or 1
  local list = g("DropDownList" .. level)
  if not list then return end
  local n = list:GetName()
  if not list.afDlg then
    list.afDlg = true
    for _, s in ipairs({ "Backdrop", "MenuBackdrop" }) do local b = g(n .. s); if b and b.SetAlpha then b:SetAlpha(0) end end
    D.Rim(list)
    if list.HookScript then list:HookScript("OnShow", function() D.SkinList(level) end) end
  end
  for i = 1, math.max(list.numButtons or 0, _G.UIDROPDOWNMENU_MAXBUTTONS or 0) do
    local b = g(n .. "Button" .. i)
    if not b then break end
    skinButton(b)
  end
end

---------------------------------------------------------------- setup
local done
function D.Setup()
  if done or not D.Enabled() then return end
  done = true
  for i = 1, D.POPUPS do D.SkinPopup(i) end
  for l = 1, D.LISTS do D.SkinList(l) end
  if type(_G.UIDropDownMenu_AddButton) == "function" then
    hooksecurefunc("UIDropDownMenu_AddButton", function(_, level) D.SkinList(level) end)
  end
end

if AFUI.Settings and AFUI.Settings.Register then
  AFUI.Settings.Register{ category = "general", key = "dialogsRestyle", type = "check", default = true, label = "Forever dialogs and menus",
    tooltip = "Draws the confirmation windows (Yes / No, name boxes) and the dropdown menus in the Forever look. Switching it off takes effect after /reload." }
end
AFUI.RegisterModule("Dialogs", { OnLogin = D.Setup })
