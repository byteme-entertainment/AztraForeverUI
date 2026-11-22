-- Quick Keybind Mode (retail / Forever): /afui keybind, or the "Quick Keybind Mode" button of an action bar's Edit Mode window. Every action button gets a
-- purple highlight with its key; hover one and press a key (with Shift / Ctrl / Alt) to bind it, right-click it to unbind it, Escape or Cancel
-- throws the changes away, Okay saves them (SaveBindings). Out of combat only: SetBinding is protected, and combat ends the mode like Cancel.
-- Bindings go to the real names (ACTIONBUTTON1.., MULTIACTIONBAR1BUTTON1.., BONUSACTIONBUTTON, SHAPESHIFTBUTTON); Bindings.lua re-routes them to our buttons on UPDATE_BINDINGS.
AFUI = AFUI or {}
local QK = {}
AFUI.QuickKeybind = QK
QK.active, QK.dirty = false, false

local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true,
  UNKNOWN = true, CAPSLOCK = true, PRINTSCREEN = true }
local MOUSE = { MiddleButton = "BUTTON3", Button3 = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local BARS = { "main", "bottomleft", "bottomright", "right", "right2", "pet", "stance" }

local function say(msg) AFUI.Print("|cffffd200Quick Keybind:|r " .. msg) end

---------------------------------------------------------------- pure rules (specs)
-- A key press -> binding string in the client's order (ALT-CTRL-SHIFT-KEY); a lone modifier is no binding.
function QK.KeyString(key, shift, ctrl, alt)
  if type(key) ~= "string" or key == "" or MODIFIER_KEYS[key] or key == "ESCAPE" then return nil end
  return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. key
end

-- The binding command of a button of ours: action bars carry theirs (Bindings.lua), the pet and stance bars use the client's names.
function QK.CommandFor(b)
  if b.afuiBinding then return b.afuiBinding end
  local name = b:GetName() or ""
  local id = b:GetID()
  if name:find("^PetActionButton") then return "BONUSACTIONBUTTON" .. id end
  if name:find("^StanceButton") or name:find("^ShapeshiftButton") then return "SHAPESHIFTBUTTON" .. id end
end

local function commandName(cmd)
  return _G["BINDING_NAME_" .. cmd] or cmd
end

-- Binds `key` to `command`; the button's old keys go (one key per button, as in retail), another command holding `key` loses it.
-- Returns true, { unbound = "name" } or false, reason.
function QK.Bind(command, key)
  if InCombatLockdown() then return false, "combat" end
  if not (command and key and _G.SetBinding) then return false, "nothing to bind" end
  local out = {}
  local old = _G.GetBindingAction and GetBindingAction(key)
  if old and old ~= "" and old ~= command then out.unbound = commandName(old) end
  for _, k in ipairs({ GetBindingKey(command) }) do if k ~= key then SetBinding(k) end end
  if not SetBinding(key, command) then return false, "refused" end
  QK.dirty = true
  return true, out
end

function QK.Unbind(command)
  if InCombatLockdown() then return false, "combat" end
  if not (command and _G.SetBinding) then return false, "nothing to unbind" end
  local n = 0
  for _, k in ipairs({ GetBindingKey(command) }) do SetBinding(k); n = n + 1 end
  if n > 0 then QK.dirty = true end
  return n > 0
end

local function keyText(command)
  local k = GetBindingKey(command)
  return k and AFUI.HotkeyText(k) or ""
end

---------------------------------------------------------------- targets
-- Visible, bindable buttons of our bars (a button the Icons setting hid has no key).
function QK.Targets()
  local list = {}
  for _, key in ipairs(BARS) do
    local bar = AFUI.Bars and AFUI.Bars[key]
    if bar and bar.frame:IsShown() then
      for _, b in ipairs(bar.buttons) do
        if b:IsShown() and not b:GetAttribute("statehidden") and QK.CommandFor(b) then list[#list + 1] = b end
      end
    end
  end
  return list
end

---------------------------------------------------------------- overlays
local hover, overlays, dialog, keys = nil, {}, nil, nil

-- purple-blue on every button, gold on the one under the mouse; solid colours (SetColor), so no vertex colour is involved
local FILL, FILL_HOVER = { 0.5, 0.36, 1, 0.4 }, { 1, 0.82, 0.2, 0.55 }
local EDGE, EDGE_HOVER = { 0.66, 0.55, 1, 0.95 }, { 1, 0.82, 0.2, 1 }
local function refreshOverlay(o)
  local lit = hover == o
  local f, e = lit and FILL_HOVER or FILL, lit and EDGE_HOVER or EDGE
  AFUI.SetColor(o.fill, f[1], f[2], f[3], f[4])
  for _, t in ipairs(o.edges) do AFUI.SetColor(t, e[1], e[2], e[3], e[4]) end
  o.label:SetText(keyText(o.command))
end

local function refreshAll() for _, o in pairs(overlays) do refreshOverlay(o) end end

-- After a change: the real binding set is current, ours follows it (override bindings and the button's own hotkey text).
local function changed()
  if AFUI.UpdateBindings then AFUI.UpdateBindings() end
  refreshAll()
end

local function bindKey(o, key)
  local good, info = QK.Bind(o.command, key)
  if not good then
    if info == "combat" then QK.Exit(false) else say("Could not bind " .. AFUI.HotkeyText(key) .. ".") end
    return
  end
  if info.unbound then say(AFUI.HotkeyText(key) .. " was unbound from " .. info.unbound .. ".") end
  changed()
end

local function edge(o, p1, p2, w, h)
  local t = o:CreateTexture(nil, "OVERLAY")
  t:SetPoint(p1, o, p1, 0, 0); t:SetPoint(p2, o, p2, 0, 0)
  if w then t:SetWidth(w) end
  if h then t:SetHeight(h) end
  return t
end

local function buildOverlay(b)
  local o = CreateFrame("Button", nil, b)
  o:SetAllPoints(b)
  o:SetFrameStrata("HIGH")
  o:SetFrameLevel((b:GetFrameLevel() or 1) + 30)
  o:EnableMouse(true)
  o:RegisterForClicks("AnyUp")
  if o.EnableMouseWheel then o:EnableMouseWheel(true) end
  o.fill = o:CreateTexture(nil, "ARTWORK")
  o.fill:SetAllPoints(o)
  o.edges = { edge(o, "TOPLEFT", "TOPRIGHT", nil, 2), edge(o, "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2),
    edge(o, "TOPLEFT", "BOTTOMLEFT", 2, nil), edge(o, "TOPRIGHT", "BOTTOMRIGHT", 2, nil) }
  o.label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  o.label:SetPoint("CENTER", o, "CENTER", 0, 0)
  o.button, o.command = b, QK.CommandFor(b)
  o:SetScript("OnEnter", function(self)
    hover = self; refreshOverlay(self)
    if _G.GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(commandName(self.command))
      GameTooltip:AddLine("Press a key to bind it.", 1, 1, 1)
      GameTooltip:AddLine("Right-click to unbind.", 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  o:SetScript("OnLeave", function(self)
    if hover == self then hover = nil end
    refreshOverlay(self)
    if _G.GameTooltip then GameTooltip:Hide() end
  end)
  o:SetScript("OnClick", function(self, mouse)
    if mouse == "RightButton" then
      if QK.Unbind(self.command) then changed() end
    elseif MOUSE[mouse] then
      bindKey(self, QK.KeyString(MOUSE[mouse], IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown()))
    end
  end)
  o:SetScript("OnMouseWheel", function(self, delta)
    bindKey(self, QK.KeyString(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN", IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown()))
  end)
  return o
end

---------------------------------------------------------------- keyboard and dialog
local function onKey(_, key)
  if AFUI.IS_243 then key = arg1 end
  if key == "ESCAPE" then return QK.Cancel() end
  if not hover then return end
  local k = QK.KeyString(key, IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown())
  if k then bindKey(hover, k) end
end

local function buildDialog()
  local W = AFUI.EditModeWidgets
  dialog = W.Panel("AFUI_QuickKeybindDialog", 380, 150)
  dialog:SetPoint("TOP", UIParent, "TOP", 0, -90)
  dialog.Resize(380, 150)
  W.Label(dialog, "GameFontHighlightLarge", "Quick Keybind Mode", "TOP", dialog, "TOP", 0, -20)
  local help = W.Label(dialog, "GameFontHighlight", "Hover over an action button and press a key to bind it.\nRight-click a button to unbind it.", "TOP", dialog, "TOP", 0, -48)
  help:SetWidth(330); help:SetJustifyH("CENTER")
  if help.SetWordWrap then help:SetWordWrap(true) end
  dialog.okay = W.RedButton(dialog, "AFUI_QuickKeybindOkay", "Okay", 150, 28, "BOTTOMLEFT", 25, 18, function() QK.Okay() end)
  dialog.cancel = W.RedButton(dialog, "AFUI_QuickKeybindCancel", "Cancel", 150, 28, "BOTTOMRIGHT", -25, 18, function() QK.Cancel() end)
end

function QK.Enter()
  if QK.active then return true end
  if not AFUI.ModuleEnabled("actionbars") then say("Quick Keybind Mode works on Aztra's Forever UI's action bars: they are switched off in Settings > Windows."); return false end
  if InCombatLockdown() then
    say("Not available in combat.")
    return false
  end
  QK.active, QK.dirty, hover = true, false, nil
  for _, b in ipairs(QK.Targets()) do
    local o = overlays[b]
    if not o then o = buildOverlay(b); overlays[b] = o end
    o:Show(); refreshOverlay(o)
  end
  if not keys then
    keys = CreateFrame("Frame", "AFUI_QuickKeybindKeys", UIParent)
    keys:SetScript("OnKeyDown", onKey)
  end
  keys:EnableKeyboard(true)
  if keys.SetPropagateKeyboardInput then keys:SetPropagateKeyboardInput(false) end
  keys:Show()
  if not dialog then buildDialog() end
  dialog:Show()
  return true
end

local function leave()
  QK.active, hover = false, nil
  for _, o in pairs(overlays) do o:Hide() end
  if keys then keys:EnableKeyboard(false); keys:Hide() end
  if dialog then dialog:Hide() end
  if _G.GameTooltip then GameTooltip:Hide() end
end

-- Okay: the new keys are saved. Cancel (Escape, combat): the saved set comes back, which drops every change made in the mode.
function QK.Okay()
  if not QK.active then return end
  if QK.dirty and _G.SaveBindings and _G.GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
  QK.dirty = false
  leave()
end

local function revert()
  if _G.LoadBindings and _G.GetCurrentBindingSet then LoadBindings(GetCurrentBindingSet()) end
  if AFUI.UpdateBindings then AFUI.UpdateBindings() end
end

function QK.Cancel() QK.Exit(false) end

function QK.Exit(save)
  if not QK.active then return end
  if save then return QK.Okay() end
  local undo = QK.dirty
  QK.dirty = false
  leave()
  if undo then AFUI.RunOutOfCombat(revert) end -- in combat the revert waits for the fight to end
end

function QK.Overlay(b) return overlays[b] end
function QK.Toggle() if QK.active then QK.Cancel() else QK.Enter() end end

-- The Edit Mode button: the boxes would cover the buttons, so Edit Mode closes first (its unsaved edits stay, as when combat starts).
function QK.EnterFromEditMode()
  local EM = AFUI.EditMode
  if EM and EM.IsOpen and EM.IsOpen() then EM.Close(true) end
  return QK.Enter()
end

AFUI.On("PLAYER_REGEN_DISABLED", function() if QK.active then QK.Exit(false) end end)

-- Audit: every button the mode can bind carries a shown overlay (called while the mode is open).
function QK.Problems()
  local out = {}
  for _, b in ipairs(QK.Targets()) do
    local o = overlays[b]
    if not (o and o:IsShown()) then out[#out + 1] = (b:GetName() or "?") .. " has no Quick Keybind overlay" end
  end
  if dialog and not dialog:IsShown() then out[#out + 1] = "the Quick Keybind dialog is not shown" end
  return out
end
