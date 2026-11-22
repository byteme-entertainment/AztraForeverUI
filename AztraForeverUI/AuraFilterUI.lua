-- The Aura Filters window: /afui filters, Settings > General > Aura filters, and the "Filters..." button of Edit Mode > Party Frames.
-- Two pages. Filters: on the left WHERE (party buffs / party debuffs ...) with the mode, the list, this character's own list, the sort order and the extras; on the right the
-- active list (icon, name, id, order, priority, "mine only", colour, remove) and the ways to ADD to it: type a name (suggestions from your spellbook and the recently seen auras),
-- type an id, the auras of your target or of the unit under the mouse, the recently seen log, or drag a spell from the spellbook onto the list.
-- Display: icon size, corner, growth, swipe, time left, stack count and the borders of the buffs and debuffs, and the dispel highlight of the frame.
-- Built-in lists are read only (locked): "Copy to custom" makes an editable copy. Everything is our own frames: it opens in combat.
AFUI = AFUI or {}
local AF = AFUI.AuraFilters
if not AF then return end
local UI = {}
AF.UI = UI

UI.W, UI.H = 780, 632
UI.PANEL_Y, UI.PANEL_H = 96, 500
UI.LEFT_W, UI.RIGHT_X, UI.RIGHT_W = 232, 252, 516
UI.ROW_H, UI.ROWS, UI.LIST_W = 26, 8, 470
UI.GRID_COLS, UI.GRID_ROWS, UI.CELL = 16, 2, 30
UI.state = { ctx = "party", kind = "buffs", tab = "filters", pick = "typed" }
UI.PALETTE = { false, "ffd100", "ff4040", "40ff40", "40a0ff", "c060ff", "ffffff" } -- the colour button of an entry cycles through these (false = none)

local function K() return AFUI.WinKit end
local function W() return AFUI.EditModeWidgets end
local function Pk() return AFUI.Professions and AFUI.Professions.Kit end
local win, left, right, display
local rows, cells = {}, {}
local painting = false

---------------------------------------------------------------- the contexts shown on the left
function UI.Contexts()
  local out = {}
  for _, c in ipairs(AF.CONTEXTS) do
    if AF.available[c.key] then
      for _, kind in ipairs(AF.KINDS) do out[#out + 1] = { ctx = c.key, kind = kind, label = c.label .. " " .. kind } end
    end
  end
  return out
end
function UI.Select(ctx, kind, tab)
  local s = UI.state
  if ctx and AF.available[ctx] then s.ctx = ctx end
  if kind == "buffs" or kind == "debuffs" then s.kind = kind end
  if tab == "filters" or tab == "display" then s.tab = tab end
  UI.Refresh()
end

-- A name for the narrow dropdowns of the left column: cut with dots when it would not fit (the menu shows the whole name).
function UI.Clip(s, n)
  n = n or 15
  if #s <= n then return s end
  return s:sub(1, n - 3) .. "..."
end

local function say(msg, bad)
  if win and win.status then win.status:SetText((bad and "|cffff6060" or "|cff80ff80") .. msg .. "|r") end
end
UI.say = say
local function err(why) say(AF.ERRORS[why] or tostring(why), true) end

local function tip(frame, title, text)
  frame:HookScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if text then GameTooltip:AddLine(text, 1, 0.82, 0, true) end
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function at(f, parent, x, y) f:ClearAllPoints(); f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y); return f end
local function text(parent, template, str, x, y, w, h, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  if w then fs:SetWidth(w) end
  if h then fs:SetHeight(h) end
  fs:SetJustifyH(justify or "LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(h and h > 16 or false) end
  fs:SetText(str or "")
  return fs
end
local function panel(x, y, w, h)
  local p = CreateFrame("Frame", nil, win)
  p:SetFrameLevel(win:GetFrameLevel() + 1)
  p:SetWidth(w); p:SetHeight(h); at(p, win, x, y)
  K().panel(p)
  return p
end
local function button(parent, name, label, w, x, y, onClick, h)
  local b = W().RedButton(parent, name, label, w, h or 24, nil, 0, 0, onClick)
  at(b, parent, x, y)
  return b
end
local function enable(b, on) b.afOn = on and true or false; if on then b:Enable() else b:Disable() end end
local function box(parent, name, w, x, y, maxLetters, numeric)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetWidth(w); holder:SetHeight(22); at(holder, parent, x, y)
  local bg = holder:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(holder); AFUI.SetColor(bg, 0, 0, 0, 0.6)
  for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = holder:CreateTexture(nil, "BORDER")
    t:SetPoint(e[1], holder, e[1], 0, 0); t:SetPoint(e[2], holder, e[2], 0, 0)
    if e[3] then t:SetHeight(1) else t:SetWidth(1) end
    AFUI.SetColor(t, 0.55, 0.5, 0.42, 1)
  end
  local eb = CreateFrame("EditBox", name, holder)
  eb:SetAutoFocus(false); eb:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlight); eb:SetMaxLetters(maxLetters or 40)
  if numeric then eb:SetNumeric(true) end
  eb:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, -2); eb:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -6, 2)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  holder.edit = eb
  return holder
end

---------------------------------------------------------------- reading the state
local function current() local s = UI.state; return s.ctx, s.kind end
local function listName() return (AF.ActiveList(current())) end
local function listTable() local n = listName(); return n ~= "" and AF.GetList(n) or nil, n end
local function entries()
  local l = listTable()
  return l and l[UI.state.kind] or {}
end
local function editableList() local n = listName(); return n ~= "" and not AF.IsBuiltin(n) and n or nil end
UI.ActiveList, UI.Entries = listName, entries

---------------------------------------------------------------- the list rows
local function paletteIndex(color)
  for i, c in ipairs(UI.PALETTE) do if (c or nil) == color then return i end end
  return 1
end
local function rgb(hex) return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 end

local function tinyButton(parent, w, h, x, label)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w); b:SetHeight(h)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(UI.ROW_H - h) / 2)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.label:SetPoint("CENTER", b, "CENTER", 0, 0); b.label:SetText(label or "")
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(b); AFUI.SetColor(hl, 1, 1, 1, 0.12)
  return b
end
local function arrow(parent, x, up)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(16); b:SetHeight(11)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(UI.ROW_H - 11) / 2)
  local n = "minimal-scrollbar-arrow-" .. (up and "top" or "bottom")
  AFUI.SetButtonAtlas(b, { n .. "-c60", n .. "-over-c60", n .. "-over-c60" }, 0.5)
  return b
end

-- Row x offsets (inside the 470 wide list): icon 4, name 32, id 214, mine 280, priority 322, colour 352, up 380, down 398, remove 424
local function row(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, UI.content)
  r:SetWidth(UI.LIST_W); r:SetHeight(UI.ROW_H)
  r:SetPoint("TOPLEFT", UI.content, "TOPLEFT", 0, -(i - 1) * UI.ROW_H)
  local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(r); AFUI.SetColor(hl, 1, 1, 1, 0.05)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetWidth(22); r.icon:SetHeight(22); r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -2)
  r.name = text(r, "GameFontHighlight", "", 32, 5, 176, 16)
  r.id = text(r, "GameFontDisable", "", 214, 6, 62, 14)
  r.mine = tinyButton(r, 38, 20, 280, "Mine")
  r.prio = tinyButton(r, 26, 20, 322, "P0")
  r.swatch = tinyButton(r, 20, 20, 352, "")
  r.swatch.tex = r.swatch:CreateTexture(nil, "ARTWORK"); r.swatch.tex:SetWidth(14); r.swatch.tex:SetHeight(14); r.swatch.tex:SetPoint("CENTER", r.swatch, "CENTER", 0, 0)
  r.up, r.down = arrow(r, 380, true), arrow(r, 398, false)
  r.remove = CreateFrame("Button", nil, r)
  r.remove:SetWidth(16); r.remove:SetHeight(16); r.remove:SetPoint("TOPLEFT", r, "TOPLEFT", 424, -5)
  local x = r.remove:CreateTexture(nil, "ARTWORK"); x:SetAllPoints(r.remove); AFUI.SetAtlas(x, "communities-icon-redx")
  AFUI.SetButtonAtlas(r.remove, { nil, nil, "communities-icon-redx", nil }, 0.6)
  r.lock = text(r, "GameFontDisable", "", 280, 6, 150, 14, "RIGHT")
  tip(r.mine, "Mine only", "Show this spell only when YOU cast it. Left off, it shows from anyone.")
  tip(r.prio, "Priority", "Higher priority icons come first; 5 and up are highlighted in gold. Left click: up, right click: down.")
  tip(r.swatch, "Highlight colour", "Click to cycle the colour of this entry's border.")
  tip(r.up, "Move up", "Earlier in the list: a tie breaker of the Priority sort.")
  tip(r.down, "Move down", nil)
  tip(r.remove, "Remove", nil)
  r.prio:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.mine:SetScript("OnClick", function() local e = r.entry; if e then AF.SetEntry(listName(), UI.state.kind, r.index, "mine", not e.mine); UI.Refresh() end end)
  r.prio:SetScript("OnClick", function(_, btn)
    local e = r.entry
    if not e then return end
    local p = (e.priority or 0) + (btn == "RightButton" and -1 or 1)
    AF.SetEntry(listName(), UI.state.kind, r.index, "priority", math.max(0, math.min(9, p)))
    UI.Refresh()
  end)
  r.swatch:SetScript("OnClick", function()
    local e = r.entry
    if not e then return end
    local i2 = paletteIndex(e.color) % #UI.PALETTE + 1
    AF.SetEntry(listName(), UI.state.kind, r.index, "color", UI.PALETTE[i2] or nil)
    UI.Refresh()
  end)
  r.up:SetScript("OnClick", function() AF.MoveEntry(listName(), UI.state.kind, r.index, -1); UI.Refresh() end)
  r.down:SetScript("OnClick", function() AF.MoveEntry(listName(), UI.state.kind, r.index, 1); UI.Refresh() end)
  r.remove:SetScript("OnClick", function()
    local e = r.entry
    local ok = AF.RemoveEntry(listName(), UI.state.kind, r.index)
    if ok and e then say("Removed " .. AF.EntryName(e) .. ".") end
    UI.Refresh()
  end)
  r:SetScript("OnEnter", function(self)
    local e = self.entry
    if not (e and GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(AF.EntryName(e), 1, 1, 1)
    GameTooltip:AddLine(e.id and ("Spell id " .. e.id) or "Matched by name only", 0.7, 0.7, 0.7)
    if e.name and e.id and e.name ~= AF.EntryName(e) then GameTooltip:AddLine("Also matches: " .. e.name, 0.7, 0.7, 0.7) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  r:SetScript("OnReceiveDrag", function() UI.DropCursor() end)
  r:SetScript("OnMouseUp", function() if GetCursorInfo and GetCursorInfo() then UI.DropCursor() end end)
  rows[i] = r
  return r
end

local function paintRow(i, e, locked)
  local r = row(i)
  r.entry, r.index = e, i
  r.icon:SetTexture(AF.EntryIcon(e))
  r.name:SetText(AF.EntryName(e))
  local hi = (e.priority or 0) >= AF.HIGH
  r.name:SetTextColor(hi and 1 or 1, hi and 0.82 or 1, hi and 0 or 1)
  r.id:SetText(e.id and tostring(e.id) or "by name")
  r.mine.label:SetText(e.mine and "|cffffd100Mine|r" or "|cff808080Mine|r")
  r.prio.label:SetText("P" .. (e.priority or 0))
  if e.color then local cr, cg, cb = rgb(e.color); AFUI.SetColor(r.swatch.tex, cr, cg, cb, 1) else AFUI.SetColor(r.swatch.tex, 0.25, 0.25, 0.25, 1) end
  for _, b in ipairs({ r.mine, r.prio, r.swatch, r.up, r.down, r.remove }) do if locked then b:Hide() else b:Show() end end
  if locked then r.lock:SetText("read only") else r.lock:SetText("") end
  r:Show()
end

---------------------------------------------------------------- the picker: suggestions, target, mouse-over, recently seen
local function addSpell(spec)
  local name = editableList()
  if not name then say("Pick or create a list of your own first (the built-in ones are read only).", true); return false end
  local ok, e = AF.AddEntry(name, UI.state.kind, spec)
  if not ok then err(e); return false end
  say("Added " .. AF.EntryName(e) .. " to " .. name .. ".")
  UI.Refresh()
  return true
end
UI.AddSpell = addSpell

function UI.DropCursor()
  local sp = AF.FromCursor()
  if not sp then return false end
  return addSpell({ id = sp.id, name = sp.name })
end

-- The spells the grid shows for the current pick mode: { name, id, icon, note }.
function UI.PickList()
  local mode, out = UI.state.pick, {}
  local want = UI.state.kind == "buffs"
  if mode == "typed" then
    local t = win and win.nameBox and win.nameBox.edit:GetText() or ""
    for _, s in ipairs(AF.Suggest(t, UI.GRID_COLS * UI.GRID_ROWS, want)) do out[#out + 1] = { name = s.name, id = s.id, icon = s.icon, note = s.from } end
  elseif mode == "target" or mode == "mouseover" then
    for _, a in ipairs(AF.UnitAuras(mode)) do
      if a.buff == want and #out < UI.GRID_COLS * UI.GRID_ROWS then out[#out + 1] = { name = a.name, id = a.id, icon = a.icon, note = (UnitName and UnitName(mode)) or mode } end
    end
  else -- seen
    local seen = AF.SeenList()
    for i = #seen, 1, -1 do
      local s = seen[i]
      if s.buff == want and #out < UI.GRID_COLS * UI.GRID_ROWS then out[#out + 1] = { name = s.name, id = s.id, icon = s.icon, note = s.src and ((s.mine and "yours, on " or "seen on ") .. s.src) or "seen" } end
    end
  end
  return out
end

local function cell(i)
  local c = cells[i]
  if c then return c end
  c = CreateFrame("Button", nil, UI.gridHost)
  c:SetWidth(UI.CELL - 2); c:SetHeight(UI.CELL - 2)
  local col, rw = (i - 1) % UI.GRID_COLS, math.floor((i - 1) / UI.GRID_COLS)
  c:SetPoint("TOPLEFT", UI.gridHost, "TOPLEFT", col * UI.CELL, -rw * UI.CELL)
  c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetAllPoints(c)
  local hl = c:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(c); hl:SetBlendMode("ADD"); AFUI.SetColor(hl, 1, 1, 1, 0.3)
  c:SetScript("OnClick", function(self) local s = self.spell; if s then addSpell({ id = s.id, name = s.name }) end end)
  c:SetScript("OnEnter", function(self)
    local s = self.spell
    if not (s and GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(s.name or "?", 1, 1, 1)
    GameTooltip:AddLine((s.id and ("Spell id " .. s.id) or "No spell id known (matched by name)") .. (s.note and ("  |cff9d9d9d" .. s.note .. "|r") or ""), 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Click to add to the list.", 1, 0.82, 0)
    GameTooltip:Show()
  end)
  c:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  cells[i] = c
  return c
end

function UI.PaintPicker()
  if not win then return end
  local list = UI.PickList()
  local n = UI.GRID_COLS * UI.GRID_ROWS
  for i = 1, n do
    local c = cell(i)
    local s = list[i]
    c.spell = s
    if s then c.icon:SetTexture(s.icon or AF.EntryIcon({ id = s.id })); c:Show() else c:Hide() end
  end
  local mode, caption = UI.state.pick, ""
  if mode == "typed" then caption = #list > 0 and "Suggestions from your spellbook and the auras seen. Click one to add it." or "Type a name to see suggestions, or pick a source above."
  elseif mode == "target" then caption = #list > 0 and "Auras on your target. Click one to add it." or "Your target has no " .. UI.state.kind .. " (or you have no target)."
  elseif mode == "mouseover" then caption = #list > 0 and "Auras on the unit under the mouse. Click one to add it." or "No unit under the mouse with " .. UI.state.kind .. "."
  else caption = #list > 0 and "Recently seen " .. UI.state.kind .. " on you and your group (newest first). Click one to add it." or "Nothing seen yet: auras appear here as you play in a group." end
  win.gridCaption:SetText(caption)
  for _, k in ipairs({ "target", "mouseover", "seen" }) do
    local b = win["pick_" .. k]
    if b then b.text:SetTextColor(mode == k and 1 or 0.7, mode == k and 0.82 or 0.7, mode == k and 0 or 0.7) end
  end
end

local function pick(mode)
  UI.state.pick = mode
  UI.PaintPicker()
end

local function addFromBoxes()
  local id = tonumber(win.idBox.edit:GetText())
  local nm = strtrim and strtrim(win.nameBox.edit:GetText() or "") or (win.nameBox.edit:GetText() or "")
  if id and id > 0 then
    if addSpell({ id = id }) then win.idBox.edit:SetText("") end
  elseif nm ~= "" then
    local first = AF.Suggest(nm, 1)[1]
    local spec = (first and first.name:lower() == nm:lower()) and { name = first.name, id = first.id } or { name = nm }
    if addSpell(spec) then win.nameBox.edit:SetText("") end
  else
    say("Type a spell name or an id first.", true)
  end
end

---------------------------------------------------------------- the list actions (new, duplicate, rename, delete, export, import)
local function popup(opts)
  local P = AFUI.Profiles
  if not (P and P.Popup) then say("The popup is not available in this build.", true); return end
  P.Popup(opts)
end
local function assignNew(name)
  local ctx, kind = current()
  AF.SetAssignment(ctx, kind, "list", name)
  if AF.ActiveList(ctx, kind) ~= name then AF.SetCharList(ctx, kind, nil) end
end
function UI.PromptNew()
  popup({ kind = "name", title = "New Aura List", nameLabel = "List name:", button1 = "Create", onAccept = function(name)
    local ok, n = AF.CreateList(name)
    if not ok then return false, n end
    assignNew(n); say("List '" .. n .. "' created and used here."); UI.Refresh(); return true
  end })
end
function UI.PromptCopy()
  local from = listName()
  if from == "" then return end
  popup({ kind = "name", title = AF.IsBuiltin(from) and "Copy to Custom" or "Duplicate List", nameLabel = "Name of the copy:", default = (AF.IsBuiltin(from) and "My " or "") .. from:gsub("^Healer: ", ""):sub(1, 24) .. (AF.IsBuiltin(from) and "" or " copy"),
    button1 = "Copy", onAccept = function(name)
      local ok, n = AF.CopyList(from, name)
      if not ok then return false, n end
      assignNew(n); say("Copied to '" .. n .. "', now used here."); UI.Refresh(); return true
    end })
end
function UI.PromptRename()
  local from = editableList()
  if not from then say("Built-in lists cannot be renamed: copy one first.", true); return end
  popup({ kind = "name", title = "Rename List", nameLabel = "New name:", default = from, button1 = "Rename", onAccept = function(name)
    local ok, n = AF.RenameList(from, name)
    if not ok then return false, n end
    say("Renamed to '" .. n .. "'."); UI.Refresh(); return true
  end })
end
function UI.PromptDelete()
  local from = editableList()
  if not from then say("Built-in lists cannot be deleted.", true); return end
  popup({ kind = "confirm", title = "Delete List", message = "Delete '" .. from .. "'?\nFrames that used it show everything again.", button1 = "Delete", onAccept = function()
    AF.DeleteList(from); say("Deleted '" .. from .. "'."); UI.Refresh(); return true
  end })
end
function UI.PromptExport()
  local from = listName()
  if from == "" then return end
  local str = AF.Export(from)
  if not str then return end
  popup({ kind = "export", title = "Export List", textLabel = "Copy this text (Ctrl+C) and share it:", text = str, button1 = "Close" })
end
function UI.PromptImport()
  popup({ kind = "import", title = "Import List", nameLabel = "Name for the list:", textLabel = "Paste an AFUIF1 string:", button1 = "Import", onAccept = function(name, str)
    local added, why = AF.Import(str, name)
    if not added then return false, why end
    assignNew(added[1]); say("Imported " .. table.concat(added, ", ") .. (#added > 1 and " (the first is used here)." or ".")); UI.Refresh(); return true
  end })
end

---------------------------------------------------------------- painting
function UI.PaintLeft()
  local ctx, kind = current()
  local ctxs = UI.Contexts()
  for i, b in ipairs(left.ctxButtons) do
    local c = ctxs[i]
    if c then
      b.ctx, b.kind = c.ctx, c.kind
      b.label:SetText(c.label)
      local sel = c.ctx == ctx and c.kind == kind
      b.label:SetTextColor(sel and 1 or 0.85, sel and 0.82 or 0.85, sel and 0 or 0.85)
      if sel then b.sel:Show() else b.sel:Hide() end
      b:Show()
    else b:Hide() end
  end
  local a = AF.Assignment(ctx, kind)
  local debuff = kind == "debuffs"
  painting = true
  left.mode:SetText(a.mode)
  left.list:SetText(UI.Clip(a.list ~= "" and AF.GetList(a.list) and a.list or "(none)"))
  local mine, isMine = AF.ActiveList(ctx, kind)
  left.char:SetText(isMine and UI.Clip(mine) or "(same as the list)")
  left.sort:SetText(a.sort)
  left.dispel:SetChecked(a.dispellable); left.permanent:SetChecked(a.noPermanent); left.boss:SetChecked(a.boss)
  if debuff then left.dispel:Show(); left.boss:Show(); left.permanent:Hide() else left.dispel:Hide(); left.boss:Hide(); left.permanent:Show() end
  left.max:SetValue(a.max); left.max.value:SetText(tostring(a.max))
  left.long:SetValue(a.maxMinutes); left.long.value:SetText(a.maxMinutes == 0 and "off" or (a.maxMinutes .. " min"))
  painting = false
  local needsList = a.mode == "Only list" or a.mode == "All except list" or a.mode == "Mine + list"
  left.hint:SetText(needsList and (a.list == "" and "|cffff8040Needs a list: see right|r" or "") or "")
end

function UI.PaintRight()
  local ctx, kind = current()
  local l, name = listTable()
  local locked = name ~= "" and AF.IsBuiltin(name)
  right.list:SetText(name ~= "" and name or "(none: show by mode only)")
  right.locked:SetText(locked and "|cffff9040Locked|r" or "")
  if locked then right.copyLocked:Show() else right.copyLocked:Hide() end
  enable(right.new, true); enable(right.dup, name ~= ""); enable(right.rename, name ~= "" and not locked); enable(right.delete, name ~= "" and not locked)
  enable(right.export, name ~= ""); enable(right.import, true)
  right.note:SetText(l and l.note or (name == "" and "Pick a list for these auras, or make a new one. The mode on the left decides how it is used." or ""))
  local list = l and l[kind] or {}
  for i, e in ipairs(list) do paintRow(i, e, locked) end
  for i = #list + 1, #rows do rows[i]:Hide() end
  UI.content:SetHeight(math.max(#list * UI.ROW_H, 1))
  right.empty:SetText(#list == 0 and (name == "" and "No list chosen." or ("No " .. kind .. " in this list yet: add one below, or drag a spell here.")) or "")
  right.count:SetText(string.format("%d %s", #list, kind))
  local canAdd = not locked and name ~= ""
  enable(right.add, canAdd)
  if UI.bar then UI.bar:Refresh() end
end

function UI.PaintDisplay()
  local ctx = UI.state.ctx
  painting = true
  for _, kind in ipairs(AF.KINDS) do
    local d, col = AF.Display(ctx, kind), display[kind]
    col.size:SetValue(d.size); col.size.value:SetText(tostring(d.size))
    col.anchor:SetText(d.anchor); col.growth:SetText(d.growth)
    col.swipe:SetChecked(d.swipe); col.timer:SetChecked(d.timer); col.stacks:SetChecked(d.stacks); col.typeBorder:SetChecked(d.typeBorder); col.highlight:SetChecked(d.highlight)
  end
  display.glow:SetChecked(AF.DisplayOf(ctx).dispelHighlight)
  painting = false
  local have = {}
  for _, t in ipairs({ "Magic", "Curse", "Poison", "Disease" }) do if AF.CanDispel(t) then have[#have + 1] = t end end
  display.known:SetText("You can dispel: " .. (#have > 0 and table.concat(have, ", ") or "nothing"))
end

function UI.Refresh()
  if not (win and win:IsShown()) then return end
  local filters = UI.state.tab == "filters"
  if filters then left:Show(); right:Show(); display:Hide() else left:Hide(); right:Hide(); display:Show() end
  win.tabFilters.text:SetTextColor(filters and 1 or 0.7, filters and 0.82 or 0.7, filters and 0 or 0.7)
  win.tabDisplay.text:SetTextColor(filters and 0.7 or 1, filters and 0.7 or 0.82, filters and 0.7 or 0)
  if filters then UI.PaintLeft(); UI.PaintRight(); UI.PaintPicker() else UI.PaintDisplay() end
end

---------------------------------------------------------------- building
local function dropdownRow(parent, name, caption, y, items)
  text(parent, "GameFontHighlight", caption, 12, y + 4, 70, 16)
  local d = W().Dropdown(parent, name, 124)
  d.label:SetWordWrap(false) -- a long list name is cut, not wrapped over two lines
  at(d, parent, 92, y)
  d.SetItems(items)
  return d
end
local function checkRow(parent, name, label, y, onClick, x)
  local c = W().Check(parent, name, label, function(on) if not painting then onClick(on) end end)
  at(c, parent, x or 6, y)
  return c
end
local function sliderRow(parent, name, caption, y, min, max, step, onChange, x, bar)
  text(parent, "GameFontHighlight", caption, x or 12, y, 200, 16)
  local s = W().Slider(parent, name, (bar or 96) + 38, min, max, step)
  at(s, parent, (x or 12) + 19, y + 22)
  s:SetScript("OnValueChanged", function(self)
    if painting then return end
    local v = math.floor(self:GetValue() / step + 0.5) * step
    onChange(v, s)
  end)
  return s
end

local function buildLeft()
  local ctx = function() return UI.state.ctx, UI.state.kind end
  left = panel(12, UI.PANEL_Y, UI.LEFT_W, UI.PANEL_H)
  text(left, "GameFontNormal", "Show on", 12, 10, 200, 16)
  left.ctxButtons = {}
  for i = 1, 4 do
    local b = CreateFrame("Button", "AFUI_AuraFiltersCtx" .. i, left)
    b:SetWidth(208); b:SetHeight(24); at(b, left, 12, 30 + (i - 1) * 26)
    b.sel = b:CreateTexture(nil, "BACKGROUND"); b.sel:SetAllPoints(b); AFUI.SetColor(b.sel, 0.45, 0.37, 0.2, 0.45)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(b); AFUI.SetColor(hl, 1, 1, 1, 0.06)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); b.label:SetPoint("LEFT", b, "LEFT", 8, 0)
    b:SetScript("OnClick", function(self) UI.Select(self.ctx, self.kind) end)
    left.ctxButtons[i] = b
  end
  if not AF.available.raid then
    text(left, "GameFontDisable", "Raid frames are the client's own: only the raid-style party frames use these filters.", 12, 86, 208, 44)
  end
  local rule = left:CreateTexture(nil, "ARTWORK"); AFUI.SetColor(rule, 0.45, 0.37, 0.2, 0.9)
  rule:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -138); rule:SetPoint("TOPRIGHT", left, "TOPRIGHT", -10, -138); rule:SetHeight(1)
  text(left, "GameFontNormal", "Rules", 12, 146, 200, 16)

  left.mode = dropdownRow(left, "AFUI_AuraFiltersMode", "Mode", 168, function()
    local items = {}
    for _, m in ipairs(AF.MODES) do items[#items + 1] = { text = m, checked = AF.Assignment(ctx()).mode == m, func = function() AF.SetAssignment(UI.state.ctx, UI.state.kind, "mode", m); UI.Refresh() end } end
    return items
  end)
  tip(left.mode, "Mode", "All: every aura. Only mine: what you cast. Only list: just the spells of the list. All except list: hide the list. Mine + list: your auras plus the list from anyone.")
  left.list = dropdownRow(left, "AFUI_AuraFiltersList", "List", 210, function()
    local items = { { text = "(none)", checked = AF.Assignment(ctx()).list == "", func = function() AF.SetAssignment(UI.state.ctx, UI.state.kind, "list", ""); UI.Refresh() end } }
    for _, n in ipairs(AF.ListNames()) do
      items[#items + 1] = { text = (AF.IsBuiltin(n) and "[lock] " or "") .. n, checked = AF.Assignment(ctx()).list == n, func = function() AF.SetAssignment(UI.state.ctx, UI.state.kind, "list", n); UI.Refresh() end }
    end
    return items
  end)
  tip(left.list, "List", "The list these frames use, on every character. Built-in lists are locked: copy one to change it.")
  left.char = dropdownRow(left, "AFUI_AuraFiltersChar", "Character", 252, function()
    local items = { { text = "(same as the list)", checked = not select(2, AF.ActiveList(ctx())), func = function() AF.SetCharList(UI.state.ctx, UI.state.kind, nil); UI.Refresh() end } }
    for _, n in ipairs(AF.ListNames()) do
      items[#items + 1] = { text = (AF.IsBuiltin(n) and "[lock] " or "") .. n, checked = AF.ActiveList(ctx()) == n and select(2, AF.ActiveList(ctx())), func = function() AF.SetCharList(UI.state.ctx, UI.state.kind, n); UI.Refresh() end }
    end
    return items
  end)
  tip(left.char, "This character's list", "Use a different list on this character only (a druid and a priest sharing one account, for instance).")
  left.sort = dropdownRow(left, "AFUI_AuraFiltersSort", "Sort", 294, function()
    local items = {}
    for _, m in ipairs(AF.SORTS) do items[#items + 1] = { text = m, checked = AF.Assignment(ctx()).sort == m, func = function() AF.SetAssignment(UI.state.ctx, UI.state.kind, "sort", m); UI.Refresh() end } end
    return items
  end)
  tip(left.sort, "Sort", "Priority: the entries' priority, then the list order, then yours first. Time left: the ones about to run out first. Mine first. Aura order: as the game lists them.")

  left.dispel = checkRow(left, "AFUI_AuraFiltersDispel", "Only dispellable", 336, function(on) AF.SetAssignment(UI.state.ctx, UI.state.kind, "dispellable", on); UI.Refresh() end)
  tip(left.dispel, "Only dispellable debuffs", "Shows only the debuff types you can remove (Magic, Curse, Poison, Disease), from your class and the dispel spells you know.")
  left.boss = checkRow(left, "AFUI_AuraFiltersBoss", "Boss debuffs always", 370, function(on) AF.SetAssignment(UI.state.ctx, UI.state.kind, "boss", on); UI.Refresh() end)
  tip(left.boss, "Boss debuffs always", "A debuff the game marks as a boss debuff is shown whatever the mode says (when the client tells).")
  left.permanent = checkRow(left, "AFUI_AuraFiltersPermanent", "Hide permanent buffs", 336, function(on) AF.SetAssignment(UI.state.ctx, UI.state.kind, "noPermanent", on); UI.Refresh() end)
  tip(left.permanent, "Hide permanent buffs", "Hides buffs with no duration: auras, stances, forms.")
  left.max = sliderRow(left, "AFUI_AuraFiltersMax", "Max icons", 408, 0, AF.MAX_ICONS, 1, function(v) AF.SetAssignment(UI.state.ctx, UI.state.kind, "max", v); UI.Refresh() end, 12, 96)
  left.long = sliderRow(left, "AFUI_AuraFiltersLong", "Hide longer than", 452, 0, 60, 5, function(v) AF.SetAssignment(UI.state.ctx, UI.state.kind, "maxMinutes", v); UI.Refresh() end, 12, 96)
  left.hint = text(left, "GameFontDisable", "", 64, 148, 160, 14)
end

local function buildRight()
  right = panel(UI.RIGHT_X, UI.PANEL_Y, UI.RIGHT_W, UI.PANEL_H)
  text(right, "GameFontNormal", "List", 12, 14, 40, 16)
  right.list = W().Dropdown(right, "AFUI_AuraFiltersListPick", 240)
  right.list.label:SetWordWrap(false)
  at(right.list, right, 64, 9)
  right.list.SetItems(function()
    local items = { { text = "(none: show by mode only)", checked = listName() == "", func = function() AF.SetAssignment(UI.state.ctx, UI.state.kind, "list", ""); UI.Refresh() end } }
    for _, n in ipairs(AF.ListNames()) do
      items[#items + 1] = { text = (AF.IsBuiltin(n) and "[lock] " or "") .. n, checked = listName() == n, func = function() AF.SetAssignment(UI.state.ctx, UI.state.kind, "list", n); UI.Refresh() end }
    end
    return items
  end)
  right.locked = text(right, "GameFontNormal", "", 326, 14, 50, 16)
  right.copyLocked = button(right, "AFUI_AuraFiltersCopyLocked", "Copy to custom", 124, 380, 10, function() UI.PromptCopy() end)
  local bw, gap = 76, 6
  right.new = button(right, "AFUI_AuraFiltersNew", "New", bw, 12, 48, function() UI.PromptNew() end)
  right.dup = button(right, "AFUI_AuraFiltersDup", "Duplicate", bw, 12 + (bw + gap), 48, function() UI.PromptCopy() end)
  right.rename = button(right, "AFUI_AuraFiltersRename", "Rename", bw, 12 + 2 * (bw + gap), 48, function() UI.PromptRename() end)
  right.delete = button(right, "AFUI_AuraFiltersDelete", "Delete", bw, 12 + 3 * (bw + gap), 48, function() UI.PromptDelete() end)
  right.export = button(right, "AFUI_AuraFiltersExport", "Export", bw, 12 + 4 * (bw + gap), 48, function() UI.PromptExport() end)
  right.import = button(right, "AFUI_AuraFiltersImport", "Import", bw, 12 + 5 * (bw + gap), 48, function() UI.PromptImport() end)
  right.note = text(right, "GameFontDisable", "", 12, 78, 492, 28)
  right.count = text(right, "GameFontNormal", "", 12, 108, 300, 14)

  local sf = CreateFrame("ScrollFrame", "AFUI_AuraFiltersScroll", right)
  sf:SetFrameLevel(right:GetFrameLevel() + 1)
  sf:SetWidth(UI.LIST_W); sf:SetHeight(UI.ROWS * UI.ROW_H); at(sf, right, 12, 126)
  UI.content = CreateFrame("Frame", nil, sf)
  UI.content:SetWidth(UI.LIST_W); UI.content:SetHeight(1)
  sf:SetScrollChild(UI.content)
  UI.content:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0)
  sf:EnableMouseWheel(true)
  UI.scroll = sf
  UI.bar = K().scrollbar(sf, {
    get = function() return sf:GetVerticalScroll() or 0 end, set = function(v) sf:SetVerticalScroll(v) end,
    max = function() return math.max((UI.content:GetHeight() or 0) - sf:GetHeight(), 0) end, view = function() return sf:GetHeight() or 0 end, step = UI.ROW_H * 2,
  }, { x = 3, parent = right })
  right.empty = text(right, "GameFontDisable", "", 24, 126 + 70, 440, 32, "CENTER")
  sf:SetScript("OnReceiveDrag", function() UI.DropCursor() end)

  local rule = right:CreateTexture(nil, "ARTWORK"); AFUI.SetColor(rule, 0.45, 0.37, 0.2, 0.9)
  rule:SetPoint("TOPLEFT", right, "TOPLEFT", 10, -342); rule:SetPoint("TOPRIGHT", right, "TOPRIGHT", -10, -342); rule:SetHeight(1)
  text(right, "GameFontNormal", "Add a spell", 12, 348, 120, 16)
  win.nameBox = box(right, "AFUI_AuraFiltersName", 250, 12, 366, 40)
  right.hintName = text(right, "GameFontDisable", "name", 18, 369, 80, 14)
  text(right, "GameFontHighlight", "or id", 272, 369, 40, 16)
  win.idBox = box(right, "AFUI_AuraFiltersId", 76, 314, 366, 8, true)
  right.add = button(right, "AFUI_AuraFiltersAdd", "Add", 92, 400, 365, addFromBoxes)
  win.nameBox.edit:SetScript("OnTextChanged", function(self)
    right.hintName:SetText((self:GetText() or "") == "" and "name" or "")
    UI.state.pick = "typed"; UI.PaintPicker()
  end)
  win.nameBox.edit:SetScript("OnEnterPressed", function() addFromBoxes() end)
  win.idBox.edit:SetScript("OnEnterPressed", function() addFromBoxes() end)
  tip(win.nameBox, "Spell name", "Type any part of a name: your spellbook and the auras seen are searched. Enter adds it.")
  tip(win.idBox, "Spell id", "A spell id (from a tooltip addon or a database) for an aura you know by number.")

  win.pick_target = button(right, "AFUI_AuraFiltersTarget", "Target's auras", 120, 12, 396, function() pick("target") end)
  win.pick_mouseover = button(right, "AFUI_AuraFiltersMouseover", "Mouse-over", 112, 138, 396, function() pick("mouseover") end)
  win.pick_seen = button(right, "AFUI_AuraFiltersSeen", "Recently seen", 126, 256, 396, function() pick("seen") end)
  text(right, "GameFontDisable", "or drag a spell here", 392, 392, 112, 30)
  win.gridCaption = text(right, "GameFontDisable", "", 12, 424, 492, 14)
  UI.gridHost = CreateFrame("Frame", nil, right)
  UI.gridHost:SetWidth(UI.GRID_COLS * UI.CELL); UI.gridHost:SetHeight(UI.GRID_ROWS * UI.CELL); at(UI.gridHost, right, 12, 440)
end

local function buildDisplay()
  display = panel(12, UI.PANEL_Y, UI.W - 24, UI.PANEL_H)
  local ctx = function() return UI.state.ctx end
  for ci, kind in ipairs(AF.KINDS) do
    local x = 20 + (ci - 1) * 372
    local col = {}
    display[kind] = col
    text(display, "GameFontNormalLarge", kind == "buffs" and "Buffs" or "Debuffs", x, 14, 200, 20)
    col.size = sliderRow(display, "AFUI_AuraDisplaySize" .. kind, "Icon size", 42, 8, 30, 1, function(v) AF.SetDisplay(ctx(), kind, "size", v) end, x, 160)
    local function dropRow(key, caption, y, options)
      text(display, "GameFontHighlight", caption, x, y + 4, 90, 16)
      local d = W().Dropdown(display, "AFUI_AuraDisplay" .. key .. kind, 180)
      d.label:SetWordWrap(false)
      at(d, display, x + 100, y)
      d.SetItems(function()
        local items = {}
        for _, o in ipairs(options) do items[#items + 1] = { text = o, checked = AF.Display(ctx(), kind)[key] == o, func = function() AF.SetDisplay(ctx(), kind, key, o) end } end
        return items
      end)
      return d
    end
    col.anchor = dropRow("anchor", "Corner", 106, AF.CORNERS)
    col.growth = dropRow("growth", "Grows", 150, AF.GROWTHS)
    local function chk(key, label, y, tooltip)
      local c = checkRow(display, "AFUI_AuraDisplay" .. key .. kind, label, y, function(on) AF.SetDisplay(ctx(), kind, key, on) end, x - 6)
      tip(c, label, tooltip)
      return c
    end
    col.swipe = chk("swipe", "Cooldown swipe", 188, "The clock sweep over the icon while the aura runs.")
    col.timer = chk("timer", "Time left as a number", 220, "Seconds (or minutes) left, in the middle of the icon.")
    col.stacks = chk("stacks", "Stack count", 252, "The number of stacks, bottom right of the icon.")
    col.typeBorder = chk("typeBorder", "Border by debuff type", 284, "Colours the icon's border like the client does: Magic blue, Curse purple, Poison green, Disease brown.")
    col.highlight = chk("highlight", "Highlight priority entries", 316, "Entries of priority 5 and up get a gold border. An entry's own colour always wins.")
  end
  local rule = display:CreateTexture(nil, "ARTWORK"); AFUI.SetColor(rule, 0.45, 0.37, 0.2, 0.9)
  rule:SetPoint("TOPLEFT", display, "TOPLEFT", 10, -360); rule:SetPoint("TOPRIGHT", display, "TOPRIGHT", -10, -360); rule:SetHeight(1)
  text(display, "GameFontNormalLarge", "Frame", 20, 370, 200, 20)
  display.glow = checkRow(display, "AFUI_AuraDisplayGlow", "Highlight the frame when I can dispel a debuff on it", 392, function(on) AF.SetDisplay(UI.state.ctx, nil, "dispelHighlight", on) end, 14)
  tip(display.glow, "Dispel highlight", "Outlines the whole frame in the debuff's colour when a debuff you can dispel is on that member.")
  display.known = text(display, "GameFontDisable", "", 20, 430, 700, 16)
  text(display, "GameFontDisable", "These options apply to the raid-style party frames (Edit Mode > Party Frames > Use Raid-Style Party Frames). Out of combat, they take effect at once.", 20, 454, 720, 30)
end

local function build()
  if win then return win end
  local Kt, Wd, Pkt = K(), W(), Pk()
  if not (Kt and Wd and Pkt and CreateFrame and UIParent) then return nil end
  local f = CreateFrame("Frame", "AFUI_AuraFilterFrame", UIParent)
  win = f
  f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true); f:EnableMouse(true); f:SetClampedToScreen(true); f:Hide()
  f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -60)
  Kt.window(f, { icon = AFUI.IconPath("INV_Misc_Spyglass_03"), w = UI.W, h = UI.H })
  f.title = f.afLabels:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOP", f, "TOP", 0, -6); f.title:SetText("Aura Filters")
  local close = CreateFrame("Button", "AFUI_AuraFilterClose", f); Pkt.closeButton(close, f)
  close:SetScript("OnClick", function() f:Hide() end)
  f.close = close
  Kt.makeMovable(f, nil, "aurafilters")
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "AFUI_AuraFilterFrame") end
  local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", f, "TOPLEFT", 68, -31); header:SetJustifyH("LEFT"); header:SetText("Raid-style frame auras")
  local rule = f:CreateTexture(nil, "ARTWORK"); AFUI.SetColor(rule, 0.45, 0.37, 0.2, 0.9)
  rule:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -58); rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -58); rule:SetHeight(1)
  f.tabFilters = button(f, "AFUI_AuraFiltersTabFilters", "Filters", 110, 16, 64, function() UI.Select(nil, nil, "filters") end)
  f.tabDisplay = button(f, "AFUI_AuraFiltersTabDisplay", "Display", 110, 132, 64, function() UI.Select(nil, nil, "display") end)
  f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.status:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -(UI.PANEL_Y + UI.PANEL_H + 8)); f.status:SetWidth(UI.W - 40); f.status:SetJustifyH("LEFT"); f.status:SetHeight(16)
  buildLeft(); buildRight(); buildDisplay()
  f:SetScript("OnShow", function() UI.Refresh() end)
  UI.win, UI.panels = f, { left = left, right = right, display = display }
  return f
end

function UI.Open(ctx, kind, tab)
  local f = build()
  if not f then AFUI.Print("Aztra's Forever UI: the aura filter window needs this build's window parts."); return false end
  local s = UI.state
  if ctx and AF.available[ctx] then s.ctx = ctx end
  if kind then s.kind = kind end
  if tab then s.tab = tab end
  AF.ScanDispels()
  f:Show(); f:Raise()
  UI.Refresh()
  return true
end
function UI.Close() if win then win:Hide() end end
function UI.Toggle() if win and win:IsShown() then win:Hide() else UI.Open() end end
function UI.Frame() return win end

-- A list changed (from a slash command, an import, the frames): the open window repaints.
AF.OnChange(function() UI.Refresh() end)
-- A new aura in the recently seen log while the picker shows it.
AF.OnSeen = function() if win and win:IsShown() and UI.state.pick == "seen" and UI.state.tab == "filters" then UI.PaintPicker() end end

---------------------------------------------------------------- where else it opens from
if AFUI.Settings and AFUI.Settings.Register then
  AFUI.Settings.Register({ category = "general", type = "button", id = "auraFilters", label = "Aura filters for party frames",
    tooltip = "Choose which buffs and debuffs the raid-style party frames show: only yours, only a list (your HoTs, a tank's cooldowns, a boss debuff), everything but a list. The same as /afui filters.",
    onClick = function() AFUI.Settings.Close(); UI.Open() end })
end
