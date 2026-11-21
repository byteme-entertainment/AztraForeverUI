-- The first-run helper: "Welcome to Aztra's Forever UI", shown once per character (AztraForeverUICharDB.wizardDone), later with /afui wizard or from the settings window.
--   1. UI scale: Forever draws its interface 1024 units tall (1820 x 1024 on a 2560 x 1440 screen). The client's UIParent is 768 / uiScale units tall whatever the resolution, so
--      the scale that gives 1024 is 768 / 1024 = 0.75 on every screen (the client allows 0.64 .. 1.0). One button sets it (useUiScale + uiScale), out of combat.
--   2. Nameplates: enemy plates on (our recommendation), friendly plates optional. Applied when Done is pressed. Only shown for a CVar this client has.
--   3. Addons that clash (another action bar or bag addon) are named, never disabled for the player.
-- Closing the window in any way counts as done. Nothing here is protected.
AFUI = AFUI or {}
local W = {}
AFUI.Wizard = W

W.W = 480
W.TITLE = "Welcome to Aztra's Forever UI"
W.TARGET_H, W.MIN_SCALE, W.MAX_SCALE = 1024, 0.64, 1.0
W.NAMEPLATE_CVARS = { enemies = "nameplateShowEnemies", friends = "nameplateShowFriends" }

local function say(msg) if AFUI.Print then AFUI.Print("|cffffd100Aztra's Forever UI|r: " .. msg) end end

---------------------------------------------------------------- pure
-- (screen width px, screen height px [, target UI height in units]) -> the uiScale to set, and the UIParent size in units that gives (width nil without a screen size).
-- UIParent is 768 / scale units tall; Forever's is 1024 tall (clamped to the 0.64 .. 1.0 the client accepts).
function W.RecommendedUIScale(screenW, screenH, targetH)
  targetH = tonumber(targetH) or W.TARGET_H
  local scale = 768 / targetH
  if scale < W.MIN_SCALE then scale = W.MIN_SCALE elseif scale > W.MAX_SCALE then scale = W.MAX_SCALE end
  scale = math.floor(scale * 100 + 0.5) / 100
  local unitsH = 768 / scale
  local unitsW = (tonumber(screenW) and tonumber(screenH) and screenH > 0) and unitsH * screenW / screenH or nil
  return scale, unitsW and math.floor(unitsW + 0.5) or nil, math.floor(unitsH + 0.5)
end
AFUI.RecommendedUIScale = W.RecommendedUIScale

-- Addons that draw what ours draw: { addon, what it replaces }.
W.CLASHES = {
  { "Bartender4", "the action bars" }, { "Dominos", "the action bars" }, { "ElvUI", "most of the interface" }, { "Tukui", "most of the interface" },
  { "Bagnon", "the bags" }, { "ArkInventory", "the bags" }, { "AdiBags", "the bags" }, { "Baganator", "the bags" }, { "Combuctor", "the bags" }, { "OneBag3", "the bags" },
}
-- isLoaded(name) -> the clashes found: { { name, text } }.
function W.Conflicts(isLoaded)
  local out = {}
  for _, c in ipairs(W.CLASHES) do
    if isLoaded(c[1]) then
      out[#out + 1] = { name = c[1], text = c[1] .. " also replaces " .. c[2] .. " and clashes with ours. Turn one of them off in the AddOns list on the character screen; we never do it for you." }
    end
  end
  return out
end

-- Where each block goes (y down from the window's top) and the window height, for a friendly-plates row or not and n clashes.
function W.Layout(friends, n)
  local L, y = {}, 60 -- under the medallion
  L.intro = y; y = y + 38
  L.scaleTitle = y; y = y + 28
  L.scaleInfo = y; y = y + 50
  L.scaleButton = y; y = y + 28 + 14
  L.npTitle = y; y = y + 28
  L.npEnemies = y; y = y + 32
  if friends then L.npFriends = y; y = y + 32 end
  y = y + 8
  L.addTitle = y; y = y + 28
  L.addText = y; y = y + (n > 0 and n * 38 or 20) + 12
  L.done = y; y = y + 28 + 10
  L.credit = y; y = y + 14 + 10
  return L, y
end

function W.ShouldShow() local db = _G.AztraForeverUICharDB; return type(db) == "table" and not db.wizardDone end
function W.MarkDone() local db = _G.AztraForeverUICharDB; if type(db) == "table" then db.wizardDone = true end end

---------------------------------------------------------------- the client
-- The screen in physical pixels: GetPhysicalScreenSize where the client has it, else the resolution CVar ("2560x1440"; the windowed one when windowed).
function W.ScreenPixels()
  if type(_G.GetPhysicalScreenSize) == "function" then
    local ok, w, h = pcall(_G.GetPhysicalScreenSize)
    if ok and tonumber(w) and tonumber(h) and w > 0 and h > 0 then return w, h end
  end
  if type(_G.GetCVar) ~= "function" then return nil end
  local window = _G.GetCVar("gxWindow") == "1"
  local res = _G.GetCVar(window and "gxWindowedResolution" or "gxResolution")
  local a, b = tostring(res or ""):match("^(%d+)x(%d+)")
  if a then return tonumber(a), tonumber(b) end
end

local function cvarExists(name)
  if type(_G.GetCVar) ~= "function" then return false end
  local ok, v = pcall(_G.GetCVar, name)
  return ok and v ~= nil
end
function W.HasNameplateCVar(which) return cvarExists(W.NAMEPLATE_CVARS[which]) end

-- What the scale box shows: { screen = "2560 x 1440" | nil, now = "1820 x 1024", scale, unitsW, unitsH, same = already recommended }.
function W.ScaleState()
  local sw, sh = W.ScreenPixels()
  local scale, uw, uh = W.RecommendedUIScale(sw, sh)
  local nowW, nowH = UIParent:GetWidth(), UIParent:GetHeight()
  local nowScale = _G.GetCVar and _G.GetCVar("useUiScale") == "1" and tonumber(_G.GetCVar("uiScale")) or nil
  return {
    screen = sw and string.format("%d x %d", sw, sh) or nil,
    now = (nowW and nowH) and string.format("%d x %d", math.floor(nowW + 0.5), math.floor(nowH + 0.5)) or "?",
    nowScale = nowScale, scale = scale, unitsW = uw, unitsH = uh,
    same = nowScale ~= nil and math.abs(nowScale - scale) < 0.005,
  }
end

-- Sets useUiScale + uiScale (and the frame, which the client does not always follow at once). Out of combat only.
function W.ApplyScale()
  if InCombatLockdown and InCombatLockdown() then say("the UI scale cannot change in combat. Try again after the fight."); return false end
  local scale = W.RecommendedUIScale(W.ScreenPixels())
  if type(_G.SetCVar) ~= "function" then return false end
  _G.SetCVar("useUiScale", "1")
  _G.SetCVar("uiScale", tostring(scale))
  UIParent:SetScale(scale)
  say(string.format("UI scale set to %s. If a window looks off, type /reload.", tostring(scale)))
  W.Refresh()
  return true
end

-- Done: the nameplate choices go to the client (out of combat; otherwise when the fight ends).
function W.ApplyNameplates(enemies, friends)
  local function apply()
    if enemies ~= nil and W.HasNameplateCVar("enemies") then _G.SetCVar(W.NAMEPLATE_CVARS.enemies, enemies and "1" or "0") end
    if friends ~= nil and W.HasNameplateCVar("friends") then _G.SetCVar(W.NAMEPLATE_CVARS.friends, friends and "1" or "0") end
  end
  AFUI.RunOutOfCombat(apply)
end

---------------------------------------------------------------- the window
local win, t = nil, {}

local function tip(widget, title, text)
  widget:HookScript("OnEnter", function()
    if not GameTooltip then return end
    GameTooltip:SetOwner(widget, "ANCHOR_RIGHT"); GameTooltip:SetText(title, 1, 1, 1)
    if text then GameTooltip:AddLine(text, 1, 0.82, 0, true) end
    GameTooltip:Show()
  end)
  widget:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function block(parent, y, text, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -y); fs:SetWidth(W.W - 40); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
  fs:SetText(text)
  return fs
end
local function section(parent, y, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -y); fs:SetJustifyH("LEFT"); fs:SetText(text)
  local rule = parent:CreateTexture(nil, "ARTWORK"); AFUI.SetColor(rule, 0.45, 0.37, 0.2, 0.9)
  rule:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -(y + 22)); rule:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, -(y + 22)); rule:SetHeight(1)
  return fs
end

-- Fills the scale text and the button from the client's present state.
function W.Refresh()
  if not win then return end
  local s = W.ScaleState()
  local first = s.screen and ("Screen: " .. s.screen .. ". UI now: " .. s.now .. " units" .. (s.nowScale and string.format(" (scale %.2f)", s.nowScale) or "") .. ".")
    or ("UI now: " .. s.now .. " units.")
  local second = s.same and "That is already the size Forever's UI is built for."
    or string.format("Recommended: scale %s (%s units here), the size Forever's UI is built for.", tostring(s.scale),
      s.unitsW and (s.unitsW .. " x " .. s.unitsH) or ("1024 tall"))
  t.scaleInfo:SetText(first .. "\n" .. second)
  if s.same then t.apply:Disable(); t.apply:SetText("UI scale is set") else t.apply:Enable(); t.apply:SetText("Apply recommended UI scale") end
end

local function build()
  if win then return win end
  local Kt, Wd, Pk = AFUI.WinKit, AFUI.EditModeWidgets, AFUI.Professions and AFUI.Professions.Kit
  if not (Kt and Wd and Pk and CreateFrame and UIParent) then return nil end
  local friends = W.HasNameplateCVar("friends")
  local conflicts = W.Conflicts(function(n) return IsAddOnLoaded(n) end)
  local L, h = W.Layout(friends, #conflicts)
  local f = CreateFrame("Frame", "AFUI_WizardFrame", UIParent)
  win = f
  f.layout, f.conflicts = L, conflicts
  f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true); f:EnableMouse(true); f:SetClampedToScreen(true); f:Hide()
  f:SetPoint("TOP", UIParent, "TOP", 0, -90) -- clear of the player frame above the bars
  Kt.window(f, { icon = AFUI.IconPath("Trade_Engineering"), w = W.W, h = h })
  f.title = f.afLabels:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOP", f, "TOP", 0, -6); f.title:SetText(W.TITLE)
  local close = CreateFrame("Button", "AFUI_WizardClose", f); Pk.closeButton(close, f)
  close:SetScript("OnClick", function() f:Hide() end)
  Kt.makeMovable(f, nil, "wizard")
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "AFUI_WizardFrame") end

  block(f, L.intro, "Let's set up a few things so the interface looks and plays like Forever's. You can come back to this any time with /afui wizard.")
  section(f, L.scaleTitle, "UI scale")
  t.scaleInfo = block(f, L.scaleInfo, "")
  t.apply = Wd.RedButton(f, "AFUI_WizardScale", "Apply recommended UI scale", 280, 28, nil, 0, 0, function() W.ApplyScale() end)
  t.apply:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -L.scaleButton)
  tip(t.apply, "Apply recommended UI scale", "Sets the scale that makes the UI 1024 units tall, the size Forever's interface is drawn at. It works on any screen resolution and cannot be done in combat.")

  section(f, L.npTitle, "Nameplates")
  t.enemies = Wd.Check(f, "AFUI_WizardEnemies", "Show enemy nameplates", function() end)
  t.enemies:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -L.npEnemies)
  t.enemies:SetChecked(true)
  tip(t.enemies, "Show enemy nameplates", "Puts a nameplate over every enemy in view. Recommended: the Forever plates and your debuff row are drawn there. Applied when you press Done.")
  if friends then
    t.friends = Wd.Check(f, "AFUI_WizardFriends", "Show friendly nameplates", function() end)
    t.friends:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -L.npFriends)
    t.friends:SetChecked(_G.GetCVar(W.NAMEPLATE_CVARS.friends) == "1")
    tip(t.friends, "Show friendly nameplates", "Puts a nameplate over friendly players and NPCs as well. Off keeps the screen quieter. Applied when you press Done.")
  end
  if not W.HasNameplateCVar("enemies") then t.enemies:Hide() end

  section(f, L.addTitle, "Other addons")
  if #conflicts == 0 then
    t.clash = block(f, L.addText, "No clashing action bar or bag addon is loaded.", "GameFontDisable")
  else
    local lines = {}
    for _, c in ipairs(conflicts) do lines[#lines + 1] = c.text end
    t.clash = block(f, L.addText, table.concat(lines, "\n"), "GameFontHighlight")
    t.clash:SetTextColor(1, 0.55, 0.2)
  end

  t.done = Wd.RedButton(f, "AFUI_WizardDone", "Done", 160, 28, nil, 0, 0, function() W.Done() end)
  t.done:SetPoint("TOP", f, "TOP", 0, -L.done)
  t.credit = block(f, L.credit, "Made with love by Aztra. All rights reserved. More links: /afui about", "GameFontDisableSmall")
  t.credit:SetWidth(W.W - 40); t.credit:SetJustifyH("CENTER")
  f:SetScript("OnHide", function() W.MarkDone() end)
  return f
end

function W.Done()
  if win then
    local enemies = t.enemies and t.enemies:IsShown() and (t.enemies.checked and true or false) or nil
    local friends = t.friends and (t.friends.checked and true or false) or nil
    W.ApplyNameplates(enemies, friends)
    win:Hide()
  end
end

function W.Show()
  local f = build()
  if not f then return false end
  f:Show(); W.Refresh(); f:Raise()
  return true
end
function W.Hide() if win then win:Hide() end end
function W.IsShown() return win ~= nil and win:IsShown() end
function W.Frame() return win end

AFUI.Slash.Register("wizard", function() W.Show() end, "run the first-time setup again (UI scale, nameplates, clashing addons)")

-- First login of a character: after the world has settled and out of combat.
AFUI.RegisterModule("Wizard", { OnLogin = function()
  if not W.ShouldShow() then return end
  local function go() AFUI.RunOutOfCombat(function() if W.ShouldShow() then W.Show() end end) end
  if _G.C_Timer and C_Timer.After then C_Timer.After(2, go) else go() end
end })
