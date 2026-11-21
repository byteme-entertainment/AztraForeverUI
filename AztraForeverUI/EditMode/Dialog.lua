-- Edit Mode dialog, laid out like Forever's "HUD Edit Mode" (docs/forever-ref/screens/editmode, docs/forever-ref/editmode.md): layout
-- dropdown, Show Grid + spacing slider, Snap to Elements, Advanced Options, the account checkboxes (quick list or Frames / Combat /
-- Misc), Revert All Changes and Save; plus a settings window for the selected system built from its settingsSchema.
-- The data operations (Select, Save, Revert, Commit, DoDelete) hold no UI, so specs drive them directly; the frames are built the
-- first time Edit Mode opens. Name entry and confirmations use one frame of our own: StaticPopup sits in the DIALOG strata under
-- the overlays and its Lua API differs between 2.4.3 (`this`) and 2.5.3 (`self`).
AFUI = AFUI or {}
local D = {}
AFUI.EditModeDialog = D
local EM, Layouts, W = AFUI.EditMode, AFUI.Layouts, AFUI.EditModeWidgets

local ERRORS = {
  exists = "A layout with that name already exists.",
  ["empty name"] = "Please enter a name.",
  ["bad text"] = "That is not a layout code.",
  preset = "Presets cannot be changed. Copy one first.",
}

---------------------------------------------------------------- data
-- Forever's order: the presets, the account-wide layouts, then the character ones.
function D.Entries()
  local list, scope, name = {}, Layouts.GetPointer()
  local function add(s, n, text)
    list[#list + 1] = { scope = s, name = n, text = text or n, active = (s == scope and n == name) }
  end
  for _, n in ipairs(AFUI.PRESET_ORDER) do add("preset", n, n .. " (Preset)") end
  for _, n in ipairs(Layouts.Names("account")) do add("account", n) end
  for _, n in ipairs(Layouts.Names("char")) do add("char", n) end
  return list
end

local function activeText()
  for _, e in ipairs(D.Entries()) do if e.active then return e.text end end
  return ""
end

-- D.after: what to do once a name prompt opened by Save succeeds (close Edit Mode, switch layout). Cleared when the
-- prompt is cancelled, so it can never fire for a later, unrelated Commit.
D.after = nil

local function runAfter()
  local f = D.after
  D.after = nil
  if f then f() end
end

-- Switches without asking: the unsaved edits are dropped.
function D.Switch(scope, name)
  if not Layouts.SetActive(scope, name) then return false end
  Layouts.Apply((Layouts.GetActive()))
  D.Reload()
  return true
end

-- Returns true when switched, false when the layout does not exist, "pending" when the user is asked about unsaved
-- changes first (Forever: ShowRevertWarningDialog).
function D.Select(scope, name)
  if not Layouts.Get(scope, name) then return false end
  if not EM.dirty then return D.Switch(scope, name) end
  local _, current = Layouts.GetPointer()
  D.Ask({ title = "Unsaved Changes", message = "Save your changes to \"" .. current .. "\" before switching?",
    button1 = "Save & Switch", button3 = "Switch", button2 = "Cancel",
    onAccept = function() D.SaveThen(function() D.Switch(scope, name) end) end,
    onAlt = function() D.Switch(scope, name) end })
  return "pending"
end

-- Returns true when saved; on a preset it asks for a name to copy it to instead and returns false.
function D.Save()
  local scope, name = Layouts.GetPointer()
  if scope == "preset" then D.Prompt("savecopy"); return false end
  Layouts.Save(scope, name, { systems = EM.current.systems })
  EM.ClearDirty()
  D.Refresh()
  return true
end

-- Saves, then runs fn (straight away, or after the name prompt of a preset copy succeeds).
function D.SaveThen(fn)
  if D.Save() then fn() else D.after = fn end
end

function D.Revert()
  Layouts.Apply((Layouts.GetActive()))
  D.Reload()
end
EM.RevertChanges = function() Layouts.Apply((Layouts.GetActive())) end -- Overlay.Close; the dialog is closing

-- kind: "new" (from Modern), "copy" / "savecopy" (from the live layout, or from `from` = { scope, name }), "rename" (the active
-- one, or `from`), "import" (name, account, text).
function D.Commit(kind, name, account, from)
  name = Layouts.Trim(name)
  local scope = account and "account" or "char"
  local good, err
  if kind == "rename" then
    local s, n
    if from then s, n = from.scope, from.name else s, n = Layouts.GetPointer() end
    good, err = Layouts.Rename(s, n, name)
  elseif kind == "new" then
    good, err = Layouts.Create(name, scope, AFUI.PRESETS.Modern)
    if good then D.Select(scope, name) end
  elseif kind == "import" then
    good, err = Layouts.CreateFromText(name, scope, from)
    if good then D.Select(scope, name) end
  elseif from then -- a copy of another layout (the gear of a row): it becomes the active one
    good, err = Layouts.Create(name, scope, Layouts.Get(from.scope, from.name))
    if good then D.Select(scope, name) end
  else
    good, err = Layouts.Create(name, scope, { systems = EM.current.systems })
    if good then Layouts.SetActive(scope, name); EM.ClearDirty() end
  end
  if not good then return false, err end
  D.Refresh()
  runAfter()
  return true
end

-- The active layout, or scope / name.
function D.DoDelete(scope, name)
  if not scope then scope, name = Layouts.GetPointer() end
  if scope == "preset" then return false, "preset" end
  local activeScope, activeName = Layouts.GetPointer()
  Layouts.Delete(scope, name)
  if scope == activeScope and name == activeName then
    Layouts.Apply((Layouts.GetActive()))
    D.Reload()
  else
    D.Refresh()
  end
  return true
end

---------------------------------------------------------------- frames
local main, ask, settings, dropdown, buttons, gridCheck, snapCheck, advCheck, gridSlider, list, expander
local rows = {} -- rows[key][id] = { frame, height, refresh(value) }
local refreshing = false
local expanded = true -- the account checkboxes ("Collapse options" / "Expand options")

local MEDIUM = W.MEDIUM

local function enable(b, on) if on then b:Enable() else b:Disable() end end

---------------------------------------------------------------- ask frame (name entry / confirmation / import / share)
local askOpts

local function closeAsk() if ask then ask:Hide() end end

local function acceptAsk()
  local o = askOpts
  if not o then return end
  local good, err = true, nil
  if o.onAccept then
    good, err = o.onAccept(o.edit and ask.edit:GetText() or nil, not ask.account.checked, o.big and ask.big:GetText() or nil)
  end
  if good == false then
    ask.error:SetText(ERRORS[err] or tostring(err))
  elseif askOpts == o then -- onAccept may have opened another prompt (Save on a preset asks for a name): leave that one
    askOpts = nil; closeAsk()
  end
end

-- Forever disables the accept button of the name and import dialogs until a name (and, for Import, the text) is typed.
local function refreshAccept()
  local o = askOpts
  if not (o and o.edit) then return end
  local named = Layouts.Trim(ask.edit:GetText() or "") ~= ""
  local texted = not o.big or Layouts.Trim(ask.big:GetText() or "") ~= ""
  if named and texted then ask.ok:Enable() else ask.ok:Disable() end
  if o.hint then if (ask.big:GetText() or "") == "" then ask.hint:Show() else ask.hint:Hide() end end
end

local function altAsk()
  local o = askOpts
  askOpts = nil
  closeAsk()
  if o and o.onAlt then o.onAlt() end
end

local function cancelAsk()
  local o = askOpts
  askOpts = nil
  closeAsk()
  if o and o.onCancel then o.onCancel() end
end

-- A field of our own: dark box, thin light border, the EditBox inside.
local function editBox(parent, name, w, h, multi)
  local box = CreateFrame("Frame", nil, parent)
  box:SetWidth(w); box:SetHeight(h)
  local bg = box:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(box); AFUI.SetColor(bg, 0, 0, 0, 0.6)
  for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = box:CreateTexture(nil, "BORDER")
    t:SetPoint(e[1], box, e[1], 0, 0); t:SetPoint(e[2], box, e[2], 0, 0)
    if e[3] then t:SetHeight(1) else t:SetWidth(1) end
    AFUI.SetColor(t, 0.55, 0.5, 0.42, 1)
  end
  local eb = CreateFrame("EditBox", name, box)
  eb:SetAutoFocus(false)
  eb:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlight)
  eb:SetMaxLetters(0)
  if multi then
    eb:SetMultiLine(true)
    eb:SetWidth(w - 8)
  else
    eb:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -2); eb:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6, 2)
  end
  box.edit = eb
  return box, eb
end

-- Forever's name, import and unsaved-changes dialogs: DiamondMetal border, red buttons along the bottom (130x22 at BOTTOMLEFT /
-- BOTTOMRIGHT +-25,+25; the unsaved-changes one has Save & Proceed 160, Proceed 115 and Cancel 115).
local function buildAsk()
  ask = W.Panel("AFUI_EditModeAsk", 320, 150)
  ask:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  ask:SetFrameStrata("TOOLTIP") -- above the dialogs it was opened from
  ask.title = W.Label(ask, "GameFontHighlight", "", "TOP", ask, "TOP", 0, -20)
  ask.message = W.Label(ask, "GameFontHighlight", "", "TOP", ask, "TOP", 0, -25)
  ask.message:SetWidth(400)
  ask.bigLabel = W.Label(ask, "GameFontNormal", "", "TOPLEFT", ask, "TOPLEFT", 28, -48)
  ask.nameLabel = W.Label(ask, "GameFontNormal", "New Layout Name:", "TOPLEFT", ask, "TOPLEFT", 28, -48)
  ask.bigBox, ask.big = editBox(ask, "AFUI_EditModeAskText", 264, 170, true)
  ask.bigBox:SetPoint("TOPLEFT", ask, "TOPLEFT", 28, -64)
  ask.big:SetPoint("TOPLEFT", ask.bigBox, "TOPLEFT", 4, -4)
  ask.hint = W.Label(ask.bigBox, "GameFontDisable", "Paste layout code here...", "TOPLEFT", ask.bigBox, "TOPLEFT", 8, -6)
  ask.big:SetScript("OnTextChanged", refreshAccept)
  ask.editBox, ask.edit = editBox(ask, "AFUI_EditModeAskBox", 264, 24)
  ask.edit:SetScript("OnTextChanged", refreshAccept)
  ask.edit:SetScript("OnEnterPressed", acceptAsk)
  ask.edit:SetScript("OnEscapePressed", cancelAsk)
  ask.big:SetScript("OnEscapePressed", cancelAsk)
  ask.account = W.Check(ask, "AFUI_EditModeAskAccount", "Character Specific Layout")
  ask.error = W.Label(ask, "GameFontRedSmall", "", "BOTTOM", ask, "BOTTOM", 0, 58)
  ask.ok = W.RedButton(ask, "AFUI_EditModeAskOK", "Accept", 130, 22, "BOTTOMLEFT", 25, 25, acceptAsk)
  ask.alt = W.RedButton(ask, "AFUI_EditModeAskAlt", "", 115, 22, "BOTTOM", 22, 25, altAsk)
  ask.cancel = W.RedButton(ask, "AFUI_EditModeAskCancel", "Cancel", 130, 22, "BOTTOMRIGHT", -25, 25, cancelAsk)
end

local function place(frame, point, x, y)
  frame:ClearAllPoints(); frame:SetPoint(point, ask, point, x, y)
end

-- opts: title, message, edit (name field with `default`), account (the Character Specific Layout checkbox), big (a text area:
-- bigLabel, bigText), button1 / button2 / button3 (optional middle button), onAccept(name, account, text) -> false, err keeps it
-- open with the error; onCancel(); onAlt().
function D.Ask(opts)
  if not main then D.Build() end
  -- The dialog behind stays clickable: a prompt replaced by another one is cancelled (clears a pending close).
  if askOpts and askOpts ~= opts and askOpts.onCancel then
    local old = askOpts
    askOpts = nil
    old.onCancel()
  end
  askOpts = opts
  ask.title:SetText(opts.title or "")
  ask.message:SetText(opts.message or "")
  ask.error:SetText("")
  ask.ok:SetText(opts.button1 or "Accept"); ask.cancel:SetText(opts.button2 or "Cancel")
  ask.account:SetChecked(true)
  ask.ok:Enable()
  ask.hint:Hide()
  ask:ClearAllPoints()
  if opts.edit then ask:SetPoint("TOP", UIParent, "TOP", 0, -133) else ask:SetPoint("CENTER", UIParent, "CENTER", 0, 120) end -- the name / import dialogs open over the HUD dialog
  ask.bigLabel:Hide(); ask.bigBox:Hide(); ask.nameLabel:Hide(); ask.editBox:Hide(); ask.account:Hide(); ask.message:Hide(); ask.alt:Hide()
  local h
  if opts.big then -- import / share: Import Text, then the name
    h = opts.edit and 370 or 300
    ask.title:ClearAllPoints(); ask.title:SetPoint("TOP", ask, "TOP", 0, -20)
    ask.bigLabel:SetText(opts.bigLabel or ""); ask.bigLabel:Show()
    ask.bigBox:Show(); ask.big:SetText(opts.bigText or ""); ask.big:HighlightText(); if opts.bigText then ask.big:SetFocus() end
    if opts.edit then
      place(ask.nameLabel, "TOPLEFT", 28, -250); ask.nameLabel:Show()
      place(ask.editBox, "TOPLEFT", 28, -268); ask.editBox:Show()
      ask.edit:SetText(opts.default or "")
      refreshAccept()
    end
    if opts.account then place(ask.account, "TOPLEFT", 24, -302); ask.account:Show() end
    ask.ok:SetWidth(130); ask.cancel:SetWidth(130)
  elseif opts.edit then
    h = opts.account and 190 or 150
    ask.title:ClearAllPoints(); ask.title:SetPoint("TOP", ask, "TOP", 0, -20)
    place(ask.nameLabel, "TOPLEFT", 28, -48); ask.nameLabel:Show()
    place(ask.editBox, "TOPLEFT", 28, -66); ask.editBox:Show()
    ask.edit:SetText(opts.default or ""); ask.edit:SetFocus()
    if opts.account then place(ask.account, "TOPLEFT", 24, -92); ask.account:Show() end
    refreshAccept()
    ask.ok:SetWidth(130); ask.cancel:SetWidth(130)
  else -- a question: Save & Proceed / Proceed / Cancel
    h = 130
    ask.title:ClearAllPoints(); ask.title:SetPoint("TOP", ask, "TOP", 0, -25)
    ask.title:SetText(""); ask.message:SetText(opts.message or ""); ask.message:Show()
    if opts.button3 then
      ask.ok:SetWidth(160); ask.alt:SetText(opts.button3); ask.alt:Show(); ask.cancel:SetWidth(115)
    else
      ask.ok:SetWidth(130); ask.cancel:SetWidth(130)
    end
  end
  ask.Resize(opts.big and 320 or (opts.edit and 320 or 450), h)
  ask:Show()
end

local TITLES = { new = "New Layout", copy = "Copy Layout", rename = "Rename Layout", savecopy = "Save Layout", import = "Import Layout" }

-- kind: "new" (from Modern), "copy" / "savecopy", "rename"; `from` = { scope, name } when it is not the active layout.
function D.Prompt(kind, from)
  local _, name = Layouts.GetPointer()
  D.Ask({
    title = TITLES[kind], edit = true, default = kind == "rename" and (from and from.name or name) or "", account = kind ~= "rename",
    button1 = kind == "rename" and "Accept" or "Save",
    onAccept = function(text, account) return D.Commit(kind, text, account, from) end,
    onCancel = function() D.after = nil end,
  })
end

-- Forever's Import Layout dialog: the pasted text, a name, character-specific or account-wide.
function D.PromptImport()
  D.Ask({ title = "Import Layout", big = true, bigLabel = "Import Text:", hint = true, edit = true, account = true, button1 = "Import",
    onAccept = function(text, account, pasted) return D.Commit("import", text, account, pasted) end })
end

-- Share Layout: the active layout as text to copy.
function D.PromptShare()
  local scope, name = Layouts.GetPointer()
  local text = Layouts.Export(scope, name)
  D.Ask({ title = "Share Layout", big = true, bigLabel = "Layout code (Ctrl+A, Ctrl+C):", bigText = text, button1 = "Close", button2 = "Close",
    onAccept = function() return true end })
end

function D.Delete(from)
  local scope, name
  if from then scope, name = from.scope, from.name else scope, name = Layouts.GetPointer() end
  if scope == "preset" then return end
  D.Ask({ title = "Delete Layout", message = "Delete \"" .. name .. "\"?", button1 = "Delete", button2 = "Cancel",
    onAccept = function() D.DoDelete(scope, name) end })
end

-- Done with unsaved changes: Save (a preset asks for a copy name first), Discard (Close reverts them) or Cancel (keep editing).
function D.RequestClose()
  if not EM.dirty or InCombatLockdown() then return EM.Close() end
  local _, name = Layouts.GetPointer()
  D.Ask({ title = "Unsaved Changes", message = "Save your changes to \"" .. name .. "\"?",
    button1 = "Save", button3 = "Discard", button2 = "Cancel",
    onAccept = function() D.SaveThen(EM.Close) end,
    onAlt = function() EM.Close() end })
end
EM.RequestClose = D.RequestClose

---------------------------------------------------------------- layout dropdown menu
-- Forever's menu: the preset layouts, the account ones, a "Character-specific" title and the character ones, then New Layout, Import
-- Layout and Share Layout. A preset row has a gear (copy it); a layout of your own has a gear (Copy / Rename) and a red X (delete).
function D.MenuItems()
  local items, last, sawChar = {}, nil, false
  for _, e in ipairs(D.Entries()) do
    if e.scope == "char" and not sawChar then sawChar = true; items[#items + 1] = { title = true, text = "Character-specific" } end
    if last and last ~= e.scope then items[#items + 1] = { divider = true } end
    last = e.scope
    local it = { text = e.text, checked = e.active, func = function() D.Select(e.scope, e.name) end }
    if e.scope == "preset" then
      it.gear = function(row) D.Prompt("copy", e) end
    else
      it.gear = function(row)
        W.OpenMenu(row, {
          { text = "Copy Layout", func = function() D.Prompt("copy", e) end },
          { text = "Rename Layout", func = function() D.Prompt("rename", e) end },
        }, 170)
      end
      it.remove = function() D.Delete(e) end
    end
    items[#items + 1] = it
  end
  items[#items + 1] = { divider = true }
  items[#items + 1] = { text = "New Layout", icon = "editmode-new-layout-plus", func = function() D.Prompt("new") end }
  items[#items + 1] = { text = "Import Layout", func = D.PromptImport }
  items[#items + 1] = { text = "Share Layout", func = D.PromptShare }
  return items
end

---------------------------------------------------------------- settings window rows
local function clean(v) return math.floor(v * 100 + 0.5) / 100 end

-- Row: 343x32 for a slider, label 100 wide at the left (GameFontHighlightMedium), the control 5 px right of it. Sliders hang 19
-- px inside their frame (see Widgets), dropdowns are 225 wide, a checkbox sits 5 px left of the row.
local ROW_H, LABEL_W = 32, 100

local function rowLabel(parent, text)
  local fs = W.Label(parent, MEDIUM, text, "TOPLEFT")
  fs:SetWidth(LABEL_W); fs:SetHeight(ROW_H); fs:SetJustifyH("LEFT")
  return fs
end

local function sliderRow(parent, key, def)
  local name = "AFUI_EditModeSlider_" .. key .. "_" .. def.id
  local caption = rowLabel(parent, def.label)
  local function shown(v) return def.percent and (math.floor(v * 100 + 0.5) .. "%") or (v == math.floor(v) and string.format("%d", v) or tostring(v)) end
  local s = W.Slider(parent, name, 200, def.min, def.max, def.step)
  s:SetScript("OnValueChanged", function()
    local v = clean(math.floor(s:GetValue() / def.step + 0.5) * def.step)
    s.value:SetText(shown(v))
    if not refreshing and EM.current.systems[key][def.id] ~= v then EM.SetSetting(key, def.id, v) end
  end)
  return { frame = s, caption = caption, height = ROW_H, dx = LABEL_W + 5 + s.INSET, dy = 6.5, wide = true,
    refresh = function(v) v = v or def.min; s:SetValue(v); s.value:SetText(shown(clean(v))) end }
end

local function checkRow(parent, key, def)
  local name = "AFUI_EditModeCheck_" .. key .. "_" .. def.id
  local c = W.Check(parent, name, def.label, function(on)
    if not refreshing then EM.SetSetting(key, def.id, on) end
  end)
  return { frame = c, height = ROW_H, dx = -5, refresh = function(v) c:SetChecked(v and true or false) end }
end

local function dropdownRow(parent, key, def)
  local name = "AFUI_EditModeDropDown_" .. key .. "_" .. def.id
  local dd = W.Dropdown(parent, name, 225)
  local caption = rowLabel(parent, def.label)
  dd.SetItems(function()
    local items = {}
    for _, option in ipairs(def.options) do
      items[#items + 1] = { text = option, checked = EM.current.systems[key][def.id] == option, func = function()
        EM.SetSetting(key, def.id, option)
        dd:SetText(option)
      end }
    end
    return items
  end)
  return { frame = dd, caption = caption, height = ROW_H, dx = LABEL_W + 5, dy = 3.5, wide = true,
    refresh = function(v) dd:SetText(v or def.options[1]) end }
end

local BUILDERS = { slider = sliderRow, checkbox = checkRow, dropdown = dropdownRow }

local function hideRows()
  for _, byId in pairs(rows) do
    for _, r in pairs(byId) do
      r.frame:Hide()
      if r.caption then r.caption:Hide() end
    end
  end
end

-- Forever's default spot of the settings dialog per system type (SetupSettingsDialogAnchor); it moves only when the selected
-- system changes type, and can be dragged.
local ANCHORS = {
  player = { "LEFT", "LEFT", 250, 0 }, target = { "RIGHT", "RIGHT", -250, 0 }, targettarget = { "RIGHT", "RIGHT", -250, 0 },
  party = { "TOPLEFT", "TOPLEFT", 200, -200 }, castbar_player = { "LEFT", "CENTER", 100, 0 },
}
local DEFAULT_ANCHOR = { "BOTTOMRIGHT", "BOTTOMRIGHT", -250, 200 }

-- Rectangles in UIParent pixels, y down: { left, top, right, bottom }. A frame placed by us is computed from its anchor (the
-- client only knows GetLeft once laid out); a frame the user dragged is asked.
local FX = { LEFT = 0, TOPLEFT = 0, BOTTOMLEFT = 0, CENTER = 0.5, TOP = 0.5, BOTTOM = 0.5 }
local FY = { TOP = 0, TOPLEFT = 0, TOPRIGHT = 0, CENTER = 0.5, LEFT = 0.5, RIGHT = 0.5 }
local function rectOf(f, spec)
  local w, h = f:GetWidth() or 0, f:GetHeight() or 0
  local uw, uh = UIParent:GetWidth() or 1024, UIParent:GetHeight() or 768
  local l = f.GetLeft and f:GetLeft()
  if l and f.GetTop and f:GetTop() then return l, uh - f:GetTop(), l + w, uh - f:GetTop() + h end
  local ux = (FX[spec[2]] or 1) * uw + spec[3]
  local uy = (FY[spec[2]] or 1) * uh - spec[4]
  local left, top = ux - (FX[spec[1]] or 1) * w, uy - (FY[spec[1]] or 1) * h
  return left, top, left + w, top + h
end
local MAIN_SPEC = { "TOP", "TOP", 0, -116 }

-- Keeps the settings window off the HUD Edit Mode dialog: when they overlap it moves beside the dialog (the side with room, else
-- under it) and stays on the screen. Both are semi-transparent art, so an overlap would draw their texts through each other.
function D.AvoidOverlap()
  if not (main and settings and settings:IsShown()) then return end
  local sl, st, sr, sb = rectOf(settings, settings.spec)
  local ml, mt, mr, mb = rectOf(main, MAIN_SPEC)
  local M = 8
  if sr <= ml or sl >= mr or sb <= mt or st >= mb then return end
  local uw, uh = UIParent:GetWidth() or 1024, UIParent:GetHeight() or 768
  local w, h = sr - sl, sb - st
  local x, y = mr + M, math.max(0, math.min(st, uh - h))
  if x + w > uw then x = ml - M - w end
  if x < 0 then x, y = math.max(0, math.min(sl, uw - w)), math.min(mb + M, math.max(0, uh - h)) end
  settings.spec = { "TOPLEFT", "TOPLEFT", x, -y }
  settings:ClearAllPoints()
  settings:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, -y)
end

-- The two windows' rectangles { left, top, right, bottom } (nil while the settings window is hidden); for the Audit and the specs.
function D.Rects()
  if not (main and settings and settings:IsShown()) then return end
  return { rectOf(main, MAIN_SPEC) }, { rectOf(settings, settings.spec) }
end

local function anchorSettings(key)
  local a = ANCHORS[key] or DEFAULT_ANCHOR
  if settings.anchorKind ~= a then -- same type: leave it where it is (or where the user dragged it)
    settings.anchorKind = a
    settings.spec = a
    settings:ClearAllPoints()
    settings:SetPoint(a[1], UIParent, a[2], a[3], a[4])
  end
end

-- The settings window's buttons work on the selected system only: Revert Changes while it has changes, Reset To Default Position
-- once it was moved.
local function updateRevert()
  if not (settings and settings.revert) then return end
  local e = EM.selected
  enable(settings.revert, e and EM.dirtyKeys[e.key] and true or false)
  enable(settings.reset, e ~= nil) -- always red in Forever, also on a frame nobody moved (video 3 f0205 / f0207 / f0213 / f0218)
end

function D.RevertSystem(key)
  Layouts.ApplySystem((Layouts.GetActive()), key)
  EM.dirtyKeys[key] = nil
  EM.dirty = next(EM.dirtyKeys) ~= nil
  D.Reload()
end

-- Shows the settings window for `entry`, one widget per schema entry, with the live values.
function D.ShowSettings(entry)
  if not settings then return end
  if not entry then settings:Hide(); return end
  local key = entry.key
  rows[key] = rows[key] or {}
  hideRows()
  settings.title:SetText(entry.label)
  local cur = EM.current.systems[key] or {}
  local y, wide = 43, false -- below the title (15 + 16 + 12)
  refreshing = true
  local built, err = pcall(function()
  for _, def in ipairs(entry.settingsSchema) do
    local build = BUILDERS[def.type]
    if build and (not def.show or def.show(cur)) then -- def.show: a row that depends on another setting (raid-style party frames)
      local row = rows[key][def.id]
      if not row then row = build(settings, key, def); rows[key][def.id] = row end
      row.frame:ClearAllPoints()
      row.frame:SetPoint("TOPLEFT", settings, "TOPLEFT", 20 + (row.dx or 0), -(y + (row.dy or 0)))
      if row.caption then
        row.caption:ClearAllPoints(); row.caption:SetPoint("TOPLEFT", settings, "TOPLEFT", 20, -y)
        row.caption:Show()
      end
      row.frame:Show()
      row.refresh(cur[def.id])
      wide = wide or row.wide
      y = y + row.height + 2
    end
  end
  end)
  refreshing = false -- never left stuck by a failing row builder
  if not built then error(err, 0) end
  y = y - 2
  -- Revert Changes 12 px under the rows, Reset To Default Position (a 330 wide extra button) 20 below it
  settings.revert:ClearAllPoints(); settings.revert:SetPoint("TOPLEFT", settings, "TOPLEFT", 20, -(y + 12))
  settings.reset:ClearAllPoints(); settings.reset:SetPoint("TOP", settings, "TOP", 0, -(y + 12 + 28 + 20))
  -- an action bar adds Forever's Quick Keybind Mode, a button of the same 330 under Reset To Default Position
  local keybind = entry.keybind and true or false
  settings.keybind:ClearAllPoints(); settings.keybind:SetPoint("TOP", settings, "TOP", 0, -(y + 12 + 28 + 20 + 28 + 12))
  if keybind then settings.keybind:Show() else settings.keybind:Hide() end
  settings.Resize((wide and 343 or 330) + 40, y + 12 + 28 + 20 + 28 + 24 + (keybind and 40 or 0))
  updateRevert()
  anchorSettings(key)
  settings:Show()
  D.AvoidOverlap()
end

---------------------------------------------------------------- main dialog
-- The account checkboxes: the quick list, or Frames / Combat / Misc with their titles, two columns of 225 x 32 cells.
local checks = {} -- by group id
local CELL_W, CELL_H = 225, 32
local LIST_X, LIST_W = 20, 470

local function groupCheck(g)
  local c = checks[g.id]
  if c then return c end
  c = W.Check(list, "AFUI_EditModeShow_" .. g.id, g.text, function(on) EM.SetShown(g.id, on) end)
  checks[g.id] = c
  return c
end

local function layoutList()
  local advanced = advCheck.checked and true or false
  for _, c in pairs(checks) do c:Hide() end
  for _, t in ipairs(list.titles) do t:Hide() end
  local y, nTitle = 0, 0
  for _, sec in ipairs(EM.GroupSections(advanced)) do
    if sec.title ~= "" then
      nTitle = nTitle + 1
      local t = list.titles[nTitle]
      if not t then t = W.Label(list, "GameFontNormalLarge", "", "LEFT"); list.titles[nTitle] = t end
      t:ClearAllPoints(); t:SetPoint("LEFT", list, "TOPLEFT", 5, -(y + CELL_H / 2))
      t:SetText(sec.title); t:Show()
      y = y + CELL_H
    end
    for i, item in ipairs(sec.items) do
      local c = groupCheck(item)
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", list, "TOPLEFT", ((i - 1) % 2) * CELL_W, -(y + math.floor((i - 1) / 2) * CELL_H))
      c:SetChecked(EM.IsShown(item.id)); c:Show()
    end
    y = y + math.ceil(#sec.items / 2) * CELL_H
  end
  list.height = y
  list:SetHeight(math.max(y, 1))
  return y
end

-- The dialog's height follows the list: 160 above it, the expander, the buttons.
local function layoutMain()
  local y = 0
  if expanded then
    y = layoutList()
    list:Show(); list.border:Show()
  else
    list:Hide(); list.border:Hide()
  end
  expander:ClearAllPoints()
  expander:SetPoint("TOP", main, "TOP", 0, -(160 + y + 13 - 11))
  expander.label:SetText(expanded and "Collapse options" or "Expand options")
  AFUI.SetAtlas(expander.arrow, expanded and "editmode-up-arrow" or "editmode-down-arrow", true)
  main.Resize(510, y + 239)
  D.AvoidOverlap() -- the dialog grew under the settings window
end

local function refreshChecks()
  for id, c in pairs(checks) do c:SetChecked(EM.IsShown(id)) end
end

-- Buttons and dropdown text: cheap, runs after every edit.
function D.Refresh()
  if not main then return end
  dropdown:SetText(activeText())
  enable(buttons.save, EM.dirty and true or false)
  enable(buttons.revert, EM.dirty and true or false)
  updateRevert()
end

-- The account settings widgets follow the saved values.
local function refreshConfig(key)
  if not main then return end
  local c = EM.Config()
  gridCheck:SetChecked(c.showGrid); snapCheck:SetChecked(c.snap)
  refreshing = true
  gridSlider:SetValue(c.gridSpacing)
  refreshing = false
  gridSlider.value:SetText(c.gridSpacing)
  gridSlider.SetEnabledLook(c.showGrid)
  if key == "show" then refreshChecks() end
end
EM.WatchConfig(refreshConfig)

-- After a layout change: also refill the settings window with the new values.
function D.Reload()
  D.Refresh()
  if main and EM.selected and settings and settings:IsShown() then D.ShowSettings(EM.selected) end
end
EM.Watch(function(key, field)
  D.Refresh()
  local e = EM.selected
  if field and e and e.key == key and settings and settings:IsShown() then -- a setting that shows or hides other rows
    for _, def in ipairs(e.settingsSchema) do
      if def.id == field and def.reshape then D.ShowSettings(e); break end
    end
  end
end)

local function nineSlice(parent, kit, inset)
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", -inset[1], inset[2]); f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", inset[1], -inset[2])
  local function piece(name, p1, p2, w, h)
    local t = f:CreateTexture(nil, "BORDER")
    t:SetPoint(p1[1], f, p1[2], p1[3] or 0, p1[4] or 0)
    if p2 then t:SetPoint(p2[1], f, p2[2], p2[3] or 0, p2[4] or 0) end
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    AFUI.SetAtlas(t, name)
    return t
  end
  local C = 32
  piece(kit .. "-cornertopleft", { "TOPLEFT", "TOPLEFT" }, nil, C, C)
  piece(kit .. "-cornertopright", { "TOPRIGHT", "TOPRIGHT" }, nil, C, C)
  piece(kit .. "-cornerbottomleft", { "BOTTOMLEFT", "BOTTOMLEFT" }, nil, C, C)
  piece(kit .. "-cornerbottomright", { "BOTTOMRIGHT", "BOTTOMRIGHT" }, nil, C, C)
  piece("_" .. kit .. "-edgetop", { "TOPLEFT", "TOPLEFT", C, 0 }, { "TOPRIGHT", "TOPRIGHT", -C, 0 }, nil, C)
  piece("_" .. kit .. "-edgebottom", { "BOTTOMLEFT", "BOTTOMLEFT", C, 0 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -C, 0 }, nil, C)
  piece("!" .. kit .. "-edgeleft", { "TOPLEFT", "TOPLEFT", 0, -C }, { "BOTTOMLEFT", "BOTTOMLEFT", 0, C }, C, nil)
  piece("!" .. kit .. "-edgeright", { "TOPRIGHT", "TOPRIGHT", 0, -C }, { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, C }, C, nil)
  return f
end

local HELP = "Move a system by dragging its box; click it to change its settings. Snapping, the grid and the layouts are above."

function D.Build()
  if main then return end
  main = W.Panel("AFUI_EditModeDialog", 510, 335)
  main:SetPoint("TOP", UIParent, "TOP", 0, -116) -- Forever: -100; the real frames sit 14 px lower on a 1080 screen
  main:SetMovable(true)
  main:RegisterForDrag("LeftButton")
  main:SetScript("OnDragStart", function() main:StartMoving() end)
  main:SetScript("OnDragStop", function() main:StopMovingOrSizing(); D.AvoidOverlap() end)
  -- the (i) button, as MainHelpPlateButton: a 64x64 button at TOPLEFT -20,+20 with Interface\common\help-i (46x46) in the middle and the
  -- client's minimap tracking ring around it (the ring file is 53 px of a 64 px sheet; drawn at 36 it is a 30 px ring)
  local help = CreateFrame("Button", "AFUI_EditModeHelp", main)
  help:SetWidth(64); help:SetHeight(64); help:SetPoint("TOPLEFT", main, "TOPLEFT", -20, 20)
  help:SetFrameLevel((main:GetFrameLevel() or 1) + 2)
  local helpArt = help:CreateTexture(nil, "BACKGROUND")
  helpArt:SetWidth(46); helpArt:SetHeight(46); helpArt:SetPoint("CENTER", help, "CENTER", 0, 0)
  helpArt:SetTexture("Interface\\AddOns\\AztraForeverUI\\Media\\plain\\help-i")
  local ring = help:CreateTexture(nil, "BORDER")
  ring:SetWidth(36); ring:SetHeight(36); ring:SetPoint("TOPLEFT", help, "CENTER", -14.9, 14.9)
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  help:SetScript("OnEnter", function() -- 2.4.3 passes no self
    if GameTooltip and GameTooltip.SetOwner then
      GameTooltip:SetOwner(help, "ANCHOR_RIGHT"); GameTooltip:SetText("HUD Edit Mode"); GameTooltip:AddLine(HELP, 1, 1, 1, true); GameTooltip:Show()
    end
  end)
  help:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
  W.CloseButton(main, function() EM.RequestClose() end)
  -- the gear beside the red X: the addon's settings window (Settings.lua), drawn with the quest panel's cog
  local gear = CreateFrame("Button", "AFUI_EditModeSettingsButton", main)
  gear:SetWidth(18); gear:SetHeight(19); gear:SetPoint("TOPRIGHT", main, "TOPRIGHT", -33, -6)
  gear:SetFrameLevel((main:GetFrameLevel() or 1) + 2)
  AFUI.SetButtonAtlas(gear, { "questlog-icon-setting", "questlog-icon-setting", "questlog-icon-setting" }, 0.6)
  gear:SetScript("OnClick", function() if AFUI.Settings then AFUI.Settings.Open() end end)
  gear:SetScript("OnEnter", function()
    if GameTooltip and GameTooltip.SetOwner then GameTooltip:SetOwner(gear, "ANCHOR_BOTTOM"); GameTooltip:SetText("Aztra's Forever UI settings", 1, 1, 1); GameTooltip:Show() end
  end)
  gear:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
  W.Label(main, "GameFontHighlightLarge", "HUD Edit Mode", "TOP", main, "TOP", 0, -15)
  dropdown = W.Dropdown(main, "AFUI_EditModeLayoutDropDown", 220)
  dropdown:SetPoint("TOPLEFT", main, "TOPLEFT", 25, -52)
  dropdown.SetItems(D.MenuItems)
  local layoutLabel = main:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  layoutLabel:SetWidth(96); layoutLabel:SetHeight(20); layoutLabel:SetJustifyH("LEFT")
  layoutLabel:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 0)
  layoutLabel:SetText("Layout:")
  -- Show Grid + spacing slider on one row (the slider frame starts where the 130 wide checkbox cell ends), Snap to Elements and
  -- Advanced Options below (the advanced one at the dialog's middle).
  gridCheck = W.Check(main, "AFUI_EditModeGridCheck", "Show Grid", function(on) EM.SetConfig("showGrid", on) end)
  gridCheck:SetPoint("TOPLEFT", main, "TOPLEFT", 20, -85)
  gridSlider = W.Slider(main, "AFUI_EditModeGridSlider", 300, EM.GRID_MIN, EM.GRID_MAX, EM.GRID_STEP)
  gridSlider:SetPoint("TOPLEFT", main, "TOPLEFT", 20 + 130 + gridSlider.INSET, -(85 + 16 - 9.5))
  gridSlider:SetScript("OnValueChanged", function()
    if refreshing or not gridSlider.enabled then return end
    local v = math.floor(gridSlider:GetValue() / EM.GRID_STEP + 0.5) * EM.GRID_STEP
    if v ~= EM.Config().gridSpacing then EM.SetConfig("gridSpacing", v) else gridSlider.value:SetText(v) end
  end)
  snapCheck = W.Check(main, "AFUI_EditModeSnapCheck", "Snap to Elements", function(on) EM.SetConfig("snap", on) end)
  snapCheck:SetPoint("TOPLEFT", main, "TOPLEFT", 20, -120)
  advCheck = W.Check(main, "AFUI_EditModeAdvancedCheck", "Advanced Options", function() layoutMain() end)
  advCheck:SetPoint("TOPLEFT", main, "TOP", 0, -120)
  -- the account checkboxes sit in a frame with the OptionsFrame border, 15 / 16 px outside it
  list = CreateFrame("Frame", "AFUI_EditModeAccountList", main)
  list:SetPoint("TOPLEFT", main, "TOPLEFT", LIST_X, -160)
  list:SetWidth(LIST_W); list:SetHeight(1)
  list.titles = {}
  list.border = nineSlice(list, "optionsframe-nineslice", { 16, 15 })
  expander = CreateFrame("Button", "AFUI_EditModeExpander", main)
  expander:SetWidth(200); expander:SetHeight(22)
  expander.label = expander:CreateFontString(nil, "ARTWORK", MEDIUM)
  expander.label:SetPoint("CENTER", expander, "CENTER", -6, 0)
  expander.arrow = expander:CreateTexture(nil, "ARTWORK")
  expander.arrow:SetPoint("LEFT", expander.label, "RIGHT", 4, 0)
  AFUI.SetAtlas(expander.arrow, "editmode-up-arrow", true)
  expander:SetScript("OnClick", function() expanded = not expanded; layoutMain() end)
  buttons = {
    save = W.RedButton(main, "AFUI_EditModeSave", "Save", 220, 28, "BOTTOMRIGHT", -15, 16, function() D.Save() end),
    revert = W.RedButton(main, "AFUI_EditModeRevert", "Revert All Changes", 220, 28, "BOTTOMLEFT", 15, 16, D.Revert),
  }
  refreshConfig()
  layoutMain()
  settings = W.Panel("AFUI_EditModeSettings", 383, 120, true) -- opaque on purpose (a spec guards it): over the dialog the two must not mix; Forever's is ~80% black (f0205)
  settings:SetFrameLevel((main:GetFrameLevel() or 1) + 40) -- above the dialog, before its children are made (they stack on the parent)
  settings:SetMovable(true)
  settings:RegisterForDrag("LeftButton")
  settings:SetScript("OnDragStart", function() settings:StartMoving() end)
  settings:SetScript("OnDragStop", function() settings:StopMovingOrSizing(); D.AvoidOverlap() end)
  W.CloseButton(settings, function() settings:Hide() end)
  settings.title = W.Label(settings, "GameFontHighlightLarge", "", "TOP", settings, "TOP", 0, -15)
  settings.revert = W.RedButton(settings, "AFUI_EditModeSystemRevert", "Revert Changes", 180, 28, "TOPLEFT", 20, -80, function()
    if EM.selected then D.RevertSystem(EM.selected.key) end
  end)
  settings.reset = W.RedButton(settings, "AFUI_EditModeSystemReset", "Reset To Default Position", 330, 28, "TOP", 0, -120, function()
    if EM.selected and EM.ResetPosition(EM.selected.key) then D.Reload() end
  end)
  settings.keybind = W.RedButton(settings, "AFUI_EditModeSystemKeybind", "Quick Keybind Mode", 330, 28, "TOP", 0, -160, function()
    if AFUI.QuickKeybind then AFUI.QuickKeybind.EnterFromEditMode() end
  end)
  buildAsk()
end

EM.OnOpen = function()
  D.Build(); main:Show(); D.Refresh(); refreshConfig("show"); layoutMain()
end
EM.OnClose = function()
  askOpts = nil; D.after = nil
  W.CloseMenu()
  if main then main:Hide(); ask:Hide(); settings:Hide() end
end
EM.OnSelect = function(entry) D.ShowSettings(entry) end
