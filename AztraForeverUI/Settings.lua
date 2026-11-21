-- The "Aztra's Forever UI" settings window: /afui, /afui config, the Game Menu button and the gear in the Edit Mode dialog.
-- Forever's metal portrait frame (WinKit.window), the side tabs of its other windows (one per category), a scrolled two-column grid (label on the left, the control right-aligned in
-- a fixed column: Edit Mode's checkbox / dropdown / slider / red button), a tooltip on every option, "Defaults" (this page) and "Okay".
-- It never touches Blizzard's own option windows. Everything is our own frames: it opens in combat too.
--
-- HOW A MODULE OFFERS AN OPTION
--   Read it with AFUI.GetSetting("key", default) (Compat.lua). Asking marks the key "provided"; this panel lists an option only once its key was asked for (or its `requires`
--   says so), so an option whose feature is not in this build never shows. The options of the planned features are declared below (label, tooltip, default): a module only has to
--   read its key. To declare one more:
--     AFUI.Settings.Register{ category = "chat", key = "chatFoo", type = "check" | "dropdown" | "slider" | "button" | "text", label = "...", tooltip = "...", default = true,
--       values = { "a", { "b", "Shown label" } } (dropdown), min = 0, max = 1, step = 0.1, format = "%.1f" (slider), onClick = fn (button), text = "..." | fn, lines = n (text),
--       get = fn / set = fn (a value that lives elsewhere), requires = fn -> bool (visible when it says so, instead of the provided rule) }
--   and react to a change with AFUI.OnSettingChanged("chatFoo", function(value) ... end). Categories: general, profiles, actionbars, chat, tooltips, nameplates, tracker, about.
AFUI = AFUI or {}
local S = {}
AFUI.Settings = S

S.W, S.H = 640, 540
S.LIST_W, S.COL_W, S.GAP, S.ROW_H, S.ROW_GAP = 580, 285, 10, 34, 2
S.LIST_X, S.LIST_Y, S.LIST_BOTTOM = 20, -92, 56 -- the list's TOPLEFT in the window, and the strip under it (the Defaults / Okay buttons)
S.TAB_H, S.TAB_TOP, S.TAB_PITCH = 55, 60, 57 -- side tab height, first tab's distance from the window top, and the widest spacing (Forever's 57)
S.TITLE = "Aztra's Forever UI"
S.CATEGORIES = {
  { key = "general", label = "General", icon = "Trade_Engineering", desc = "Windows, layouts and the setup helper." },
  { key = "profiles", label = "Profiles", icon = "INV_Shirt_GuildTabard_01", desc = "Save, copy, switch, export and import the whole configuration." },
  { key = "actionbars", label = "Action Bars", icon = "INV_Shield_06", desc = "What the action buttons show." },
  { key = "chat", label = "Chat", icon = "INV_Misc_Note_01", desc = "How the chat window looks and what its text does." },
  { key = "tooltips", label = "Tooltips & Bags", icon = "INV_Misc_Gem_01", desc = "Tooltips, vendor helpers and the details on bag and gear slots." },
  { key = "nameplates", label = "Nameplates", icon = "Ability_Marksmanship", desc = "The plates over units in the world." },
  { key = "tracker", label = "Tracker & Map", icon = "INV_Misc_Map_01", desc = "Quests on the tracker and on the map." },
  { key = "about", label = "About", icon = "INV_Misc_Book_09", desc = "What this addon is and how to reach it." },
}
S.current = "general"

-- y (negative, from the window top) of side tab i of n: the usual 57 px pitch, squeezed when the column would run past the window bottom (8 px margin)
function S.TabY(i, n)
  n = n or #S.CATEGORIES
  local pitch = n > 1 and math.min(S.TAB_PITCH, math.floor((S.H - S.TAB_TOP - S.TAB_H - 8) / (n - 1))) or S.TAB_PITCH
  return -S.TAB_TOP - (i - 1) * pitch
end

local function K() return AFUI.WinKit end
local function P() return AFUI.Professions and AFUI.Professions.Kit end
local function EW() return AFUI.EditModeWidgets end
local function say(msg) if AFUI.Print then AFUI.Print("|cffffd100Aztra's Forever UI|r: " .. msg) end end
local function safe(fn, ...) if type(fn) == "function" then local n, a = select("#", ...), { ... }; return xpcall(function() return fn(unpack(a, 1, n)) end, geterrorhandler()) end end

local function categoryIndex(key)
  for i, c in ipairs(S.CATEGORIES) do if c.key == key then return i end end
end

---------------------------------------------------------------- registry
local TYPES = { check = true, dropdown = true, slider = true, button = true, text = true }
S.entries = {}
local watched = {} -- keys whose changes refresh the open window

-- Adds (or replaces, same key / id) one option. false when it is malformed: a bad entry from another module must never break the panel.
function S.Register(o)
  if type(o) ~= "table" or not categoryIndex(o.category) then return false end
  o.type = o.type or "check"
  if not TYPES[o.type] then return false end
  local valued = o.type == "check" or o.type == "dropdown" or o.type == "slider"
  if valued and type(o.key) ~= "string" then return false end
  if o.type == "dropdown" and (type(o.values) ~= "table" or #o.values == 0) then return false end
  if o.type == "slider" and not (tonumber(o.min) and tonumber(o.max) and tonumber(o.step)) then return false end
  if o.type == "button" and type(o.onClick) ~= "function" then return false end
  if o.type ~= "text" and type(o.label) ~= "string" then return false end
  o.id = o.key or o.id or o.label
  if o.key and not watched[o.key] then -- a change made elsewhere (a slash command, Edit Mode) shows in the open window
    watched[o.key] = true
    AFUI.OnSettingChanged(o.key, function() S.Refresh() end)
  end
  for i, e in ipairs(S.entries) do
    if e.id == o.id then S.entries[i] = o; return true end
  end
  S.entries[#S.entries + 1] = o
  return true
end

-- Shown or not: `requires` decides when there is one; otherwise a valued option shows once its key was asked for; a button / text always shows.
function S.Visible(o)
  if o.requires then
    local ok, v = pcall(o.requires)
    return ok and v and true or false
  end
  if o.type == "button" or o.type == "text" then return true end
  return AFUI.SettingsProvided ~= nil and AFUI.SettingsProvided[o.key] == true
end

function S.Entries(category)
  local out = {}
  for _, o in ipairs(S.entries) do
    if o.category == category and S.Visible(o) then out[#out + 1] = o end
  end
  return out
end

-- The value of an option, read without providing its key.
function S.Value(o)
  if o.get then
    local ok, v = pcall(o.get)
    if ok and v ~= nil then return v end
    return o.default
  end
  return AFUI.PeekSetting(o.key, o.default)
end

function S.Set(o, value)
  if o.set then safe(o.set, value) else AFUI.SetSetting(o.key, value) end
  S.Refresh()
end

-- A dropdown's choices as { value, label }.
function S.Choices(o)
  local out = {}
  for _, v in ipairs(o.values or {}) do
    if type(v) == "table" then out[#out + 1] = { v[1], v[2] or tostring(v[1]) } else out[#out + 1] = { v, tostring(v) } end
  end
  return out
end

-- How a value reads in the UI ("On", the choice's label, a formatted number).
function S.Display(o, v)
  if o.type == "check" then return v and "On" or "Off" end
  if o.type == "dropdown" then
    for _, c in ipairs(S.Choices(o)) do if c[1] == v then return c[2] end end
    return tostring(v)
  end
  if o.type == "slider" then return string.format(o.format or "%d", tonumber(v) or 0) end
  return tostring(v)
end

-- "Defaults": every option of the page back to its default (a button / text has none). Returns how many changed.
function S.ResetCategory(category)
  local n = 0
  for _, o in ipairs(S.Entries(category)) do
    if o.type == "check" or o.type == "dropdown" or o.type == "slider" then
      if o.default ~= nil and S.Value(o) ~= o.default then S.Set(o, o.default); n = n + 1 end
    end
  end
  return n
end

---------------------------------------------------------------- layout (pure)
-- items = { { span = 1 | 2, h = height } } in order -> { { x, y, w, h } } (y down from the list's top) and the total height. Two columns; a full-row item starts a new row.
function S.Grid(items, colW, gap, rowGap)
  local out, y, col, rowH = {}, 0, 0, 0
  for i, it in ipairs(items) do
    local span = it.span == 2 and 2 or 1
    if span == 2 and col ~= 0 then y = y + rowH + rowGap; col, rowH = 0, 0 end
    out[i] = { x = col * (colW + gap), y = y, w = span == 2 and (2 * colW + gap) or colW, h = it.h }
    rowH = math.max(rowH, it.h)
    if span == 2 or col == 1 then y = y + rowH + rowGap; col, rowH = 0, 0 else col = 1 end
  end
  local total = col ~= 0 and (y + rowH) or (y - rowGap)
  return out, math.max(total, 0)
end

function S.ItemHeight(o)
  if o.type == "slider" then return 44 end
  if o.type == "text" then return (o.lines or 1) * 16 + 8 end
  return S.ROW_H
end
function S.Span(o) return (o.type == "slider" or o.type == "text") and 2 or 1 end

-- A label wider than the room beside its control is cut by the client: the room (px) a label has in a cell, and a conservative width of the text (7.2 px a character at 14).
function S.LabelRoom(o)
  if o.type == "check" then return S.COL_W - 8 - 44 end
  if o.type == "dropdown" then return S.COL_W - 8 - 146 end
  if o.type == "slider" then return 2 * S.COL_W + S.GAP - 8 - 300 end
  return S.COL_W - 16
end
function S.LabelWidth(o) return #(o.label or "") * 7.2 end

---------------------------------------------------------------- the planned options (a module only has to read its key)
local function def(o) S.Register(o) end

-- General: buttons for what already exists
def { category = "general", type = "button", id = "resetWindows", label = "Reset window positions",
  tooltip = "Puts every Aztra's Forever UI window back where it opens by default. The same as /afui resetwindows.",
  requires = function() return AFUI.WinKit ~= nil end,
  onClick = function() AFUI.WinKit.resetWindows(); say("window positions reset.") end }
def { category = "general", type = "button", id = "resetEditMode", label = "Reset Edit Mode layout to Modern",
  tooltip = "Switches this character to the Modern preset: every HUD element goes back to Forever's default place. Your saved layouts stay in the list.",
  requires = function() return AFUI.EditModeDialog ~= nil and AFUI.Layouts ~= nil end,
  onClick = function()
    if InCombatLockdown and InCombatLockdown() then say("not in combat."); return end
    if AFUI.EditModeDialog.Switch("preset", "Modern") then say("layout reset to Modern.") end
  end }
def { category = "general", type = "button", id = "openEditMode", label = "Open Edit Mode",
  tooltip = "Move, resize and save the HUD. The same as /editmode.",
  requires = function() return AFUI.EditMode ~= nil and AFUI.EditMode.Open ~= nil end,
  onClick = function() S.Close(); AFUI.EditMode.Open() end }
def { category = "general", type = "button", id = "wizard", label = "Run the setup wizard again",
  tooltip = "The first-run helper: the UI scale Forever is drawn at, nameplates and addons that clash. The same as /afui wizard.",
  requires = function() return AFUI.Wizard ~= nil end,
  onClick = function() AFUI.Wizard.Show() end }
def { category = "general", type = "button", id = "commands", label = "List the slash commands",
  tooltip = "Prints every /afui command in the chat window. The same as /afui help.",
  onClick = function() AFUI.Slash.Help() end }

-- Action bars (ActionBars / BarExtras)
def { category = "actionbars", key = "bagBarMode", type = "dropdown", label = "Bag bar", default = "full",
  values = { { "full", "Full row" }, { "single", "Single icon" }, { "hidden", "Hidden" } },
  tooltip = "Full row: the backpack and your four bags. Single icon: one backpack button that shows your free slots and opens or closes every bag. Hidden: no bag bar at all; the B key and your key bindings still open the bags." }
def { category = "actionbars", key = "cooldownNumbers", label = "Cooldown numbers", default = true,
  tooltip = "Shows the time left as a number on a button that is on cooldown." }
def { category = "actionbars", key = "showHotkeys", label = "Key bindings on buttons", default = true,
  tooltip = "Shows the key bound to each action button in its corner." }
def { category = "actionbars", key = "showMacroNames", label = "Macro names on buttons", default = true,
  tooltip = "Shows a macro's name along the bottom of its button." }
def { category = "actionbars", key = "rangeTint", label = "Tint buttons out of range", default = true,
  tooltip = "Turns the icon of an ability red when its target is out of range or it cannot be used." }
def { category = "actionbars", key = "procGlow", label = "Glow on procs", default = true,
  tooltip = "Lights the border of a button when its ability just became usable (a proc)." }

-- Chat
def { category = "chat", key = "chatTimestamps", type = "dropdown", label = "Chat timestamps", default = "none",
  values = { { "none", "None" }, "15:27", "15:27:32", "03:27 PM", "03:27:32 PM" },
  tooltip = "Puts the time in front of every chat line, in the format you pick. The 24 hour formats start at 15:27, the 12 hour ones carry AM / PM." }
def { category = "chat", key = "chatFade", label = "Fade the chat window", default = true,
  tooltip = "The chat text and its tabs fade out after a while without activity and come back when you hover the window or a message arrives." }
def { category = "chat", key = "chatCopyLinks", label = "Click a web link to copy it", default = true,
  tooltip = "A web address in chat becomes a link: click it to open a box with the address selected, ready for Ctrl+C." }
def { category = "chat", key = "chatStrip", label = "Show the chat tab strip", default = true,
  tooltip = "The row of chat tabs above the chat window." }

def { category = "chat", key = "chatKeepHistory", label = "Keep chat between sessions", default = true,
  tooltip = "The last lines of every chat window (not the combat log) come back after /reload or a new login. Turning it off also erases what was saved. /afui chatlog clear erases it too." }
def { category = "chat", key = "chatGuildInWindow", label = "Guild chat in chat window", default = false,
  tooltip = "Off: guild and officer chat only appear in the Guild & Communities window (J). On: they also show in the chat windows." }

-- Tooltips and bags
def { category = "tooltips", key = "tooltipSellPrice", label = "Vendor price in tooltips", default = true,
  tooltip = "Adds what a vendor pays for an item to its tooltip." }
def { category = "tooltips", key = "bagItemLevel", label = "Item level in the bags", default = true,
  tooltip = "Writes the item level of each piece of gear in the corner of its bag slot." }
def { category = "tooltips", key = "charItemLevel", label = "Item level on the character", default = true,
  tooltip = "Writes the item level of each equipped piece on its slot in the character window." }
def { category = "tooltips", key = "sellJunkButton", label = "Sell Junk button at vendors", default = true,
  tooltip = "Adds a button to the vendor window that sells every grey item in your bags at once." }
def { category = "tooltips", key = "autoSellJunk", label = "Sell junk automatically", default = false,
  tooltip = "Sells the grey items in your bags as soon as you open a vendor window. Off by default: it cannot be undone except by buying the items back." }
def { category = "tooltips", key = "bagNewGlow", label = "Glow on new items", default = true,
  tooltip = "Marks an item you just picked up with a glow in the bags until you move the mouse over it." }

def { category = "tooltips", key = "bagKeyring", label = "Show the keyring in the bags", default = true,
  tooltip = "In the combined bags window, shows your keys as a section at the end of the grid. The key button in the window's bottom strip does the same." }

-- Unit frames
def { category = "general", key = "barGlow", label = "Bar glow", default = true,
  tooltip = "A soft glow on the health and power bars of the unit frames, nameplates and party frames when health, mana, rage or energy changes. Off is the reduced-motion choice: no glow at all." }
def { category = "tooltips", key = "bagQuestMarker", label = "Quest item marker in the bags", default = true,
  tooltip = "Draws the quest border on the slot of every quest item, and an exclamation mark on one that starts a quest." }
def { category = "tooltips", key = "bagUpgradeArrow", label = "Upgrade arrow in the bags", default = true,
  tooltip = "Puts a green arrow on armor and weapons you can use whose item level is higher than what you wear in that slot. Rings and trinkets are compared with the weaker one." }
def { category = "tooltips", key = "bagAutoOpen", label = "Open bags automatically", default = true,
  tooltip = "Opens your bags when you talk to a vendor or open the bank, the mailbox, the auction house or a trade, and closes them again when that window closes. Bags you opened yourself stay open." }
def { category = "tooltips", key = "bagGroupCategory", label = "Group items by category", default = false,
  tooltip = "The Clean Up button sorts by category first: equipment, consumables, trade goods, quest, miscellaneous. After a clean up the combined bags window labels each group." }
def { category = "tooltips", key = "bagDontSell", label = "Don't sell marks (Alt-click)", default = true,
  tooltip = "Alt-click an item in your bags to lock it: a small lock appears and no junk selling, automatic or by button, ever sells it. Alt-click again to unlock. Off: the marks are hidden and ignored." }

-- Tooltip compare, item level and ids (Tooltips.lua), bag slots counter (Minimap.lua), tracker zones (Tracker.lua), combat text (CombatText.lua)
def { category = "tooltips", key = "tooltipCompareStats", label = "Compare stats with equipped", default = true,
  tooltip = "When the client shows the comparison tooltips (hold Shift over an item), the item's tooltip also lists what you would gain in green and lose in red against what you wear: stats, armor and weapon damage per second. Rings and trinkets are compared with both you wear, a two-hander with main hand and off hand together." }
def { category = "tooltips", key = "tooltipItemLevel", label = "Item level in tooltips", default = true,
  tooltip = "Adds an Item Level line to the tooltip of weapons and armor." }
def { category = "tooltips", key = "tooltipIds", label = "Show ItemID, SpellID and QuestID", default = false,
  tooltip = "Adds the numeric id to the tooltip of items, spells, buffs and quests. Useful for bug reports and for looking things up." }
def { category = "tooltips", key = "minimapBagSlots", label = "Free bag slots counter", default = false,
  tooltip = "A small free/total number above the bag bar. It turns red when three slots or fewer are left. Not shown with the single-icon bag bar, which has its own count." }
def { category = "tracker", key = "trackerZones", label = "Group quests by zone", default = true,
  tooltip = "The tracker groups quests under a zone header you can fold. The zone you are in comes first, and the quest selected in your quest log leads its zone. Off: one plain list." }
def { category = "general", key = "combatText", label = "Floating combat numbers", default = false,
  tooltip = "Damage and healing numbers drawn by this addon: yours on the right of the screen centre, what you take and receive on the left, crits larger with a flash. While on, the client's own damage and healing text is switched off (and put back when you turn this off)." }

-- Nameplates (the debuff row lives in NameplateAuras.lua, which keeps its own switch and the /afui npdebuffs command)
def { category = "nameplates", key = "npdebuffs", label = "Your debuffs on nameplates", default = true,
  tooltip = "Shows the debuffs you put on an enemy in a row above its nameplate. The same as /afui npdebuffs.",
  requires = function() return AFUI.NameplateAuras ~= nil end,
  get = function() return AFUI.NameplateAuras.Enabled() end,
  set = function(v) if AFUI.NameplateAuras.Enabled() ~= v then AFUI.NameplateAuras.Toggle() end end }
def { category = "nameplates", key = "nameplateTargetScale", type = "dropdown", label = "Target size", default = "subtle",
  values = { { "off", "Off" }, { "subtle", "Subtle" }, { "large", "Large" } },
  tooltip = "How much bigger the plate of your target is drawn. Off: the same size as the others. Subtle: a little bigger (8%). Large: 17% bigger.",
  requires = function() return AFUI.Nameplates ~= nil end }

-- Tracker and map
def { category = "tracker", key = "autoTrackQuests", label = "Track new quests automatically", default = true,
  tooltip = "A quest you accept is added to the quest tracker at once (once per quest: untick it and it stays off). Questie's own tracker has its own setting.",
  requires = function() return AFUI.Tracker ~= nil end }
def { category = "tracker", key = "mapQuestPins", label = "Tracked quests on the map", default = true,
  tooltip = "Draws a numbered pin on the world map for each quest you track.",
  requires = function() return AFUI.MapQuestPins ~= nil end }
def { category = "tracker", key = "mapZoomButtons", label = "Always show zoom buttons", default = false,
  tooltip = "Keeps the + and - buttons beside the minimap visible. Off: they appear only while the mouse is over the minimap." }

-- About
def { category = "about", type = "text", id = "aboutName", lines = 1,
  text = function() return "|cffffd100" .. S.TITLE .. "|r  " .. (S.Version() or "") end }
def { category = "about", type = "text", id = "aboutWhat", lines = 2,
  text = "Forever's default interface for the 2.5.3 client: the action bars, unit frames, nameplates, minimap, map, bags, chat, character, spellbook, talents and the other windows, drawn from Forever's own art." }
def { category = "about", type = "text", id = "aboutOptions", lines = 2,
  text = "Every option on the other pages takes effect at once. A page shows only the options this build can honour: a feature that is not part of it has none." }
def { category = "about", type = "text", id = "aboutCmds", lines = 2,
  text = "|cff66ccff/afui|r opens this window, |cff66ccff/afui help|r lists every slash command. Your window positions are kept per character." }

def { category = "about", type = "text", id = "aboutThanks", lines = 2,
  text = "|cffffd100Thank you for using and supporting Aztra's Forever UI.|r Made with love by Aztra." }
def { category = "about", type = "text", id = "aboutCrusader", lines = 2,
  text = "|cffffd100Version 0.91 Beta.|r This addon was specifically designed for |cff66ccffCrusader-Storm|r. Please report anything odd you find while testing." }
-- WoW cannot open a browser: a link button shows the url in a small box, Ctrl+C copies it.
S.LINKS = {
  { id = "Patreon", label = "Patreon", url = "https://www.patreon.com/cw/Aztra80synth" },
  { id = "Linktree", label = "Linktree (music)", url = "https://linktr.ee/aztrasynthwave" },
}
S.LINK_HINT = "Press Ctrl+C to copy, then paste in your browser"
function S.ShowLink(l)
  if AFUI.ChatQoL and AFUI.ChatQoL.OpenUrl then return AFUI.ChatQoL.OpenUrl(l.url, l.label, S.LINK_HINT) end
  say(l.label .. ": " .. l.url) -- no copy box in this build: the chat line can still be selected
end
for _, l in ipairs(S.LINKS) do
  def { category = "about", type = "button", id = "aboutLink" .. l.id, label = l.label, onClick = function() S.ShowLink(l) end,
    tooltip = l.url .. "\nClick to show the link, then press Ctrl+C to copy it." }
end
def { category = "about", type = "text", id = "aboutRights", lines = 3,
  text = "|cffbfbfbfAll rights reserved. (c) 2026 Aztra.\nWorld of Warcraft and Forever UI artwork are property of Blizzard Entertainment.|r" }

function S.Version()
  local meta = _G.GetAddOnMetadata
  local v = type(meta) == "function" and meta("AztraForeverUI", "Version")
  return v and ("version " .. v) or nil
end

---------------------------------------------------------------- the window
local win, list, content, sf, header, desc, emptyText
local cells = {} -- entry id -> its cell frame

local function tipOn(cell, o, widgets)
  local function show()
    if not GameTooltip then return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:SetText(o.label or "", 1, 1, 1)
    if o.tooltip then GameTooltip:AddLine(o.tooltip, 1, 0.82, 0, true) end
    if o.default ~= nil and o.type ~= "button" then GameTooltip:AddLine("Default: " .. S.Display(o, o.default), 0.55, 0.55, 0.55) end
    GameTooltip:Show()
  end
  local function hide() if GameTooltip then GameTooltip:Hide() end end
  for _, w in ipairs(widgets) do
    w:HookScript("OnEnter", show)
    w:HookScript("OnLeave", hide)
  end
end

local function newCell(o)
  local Wd = EW()
  local span = S.Span(o)
  local w = span == 2 and (2 * S.COL_W + S.GAP) or S.COL_W
  local cell = CreateFrame(o.type == "text" and "Frame" or "Button", nil, content) -- a text row takes no mouse
  cell:SetWidth(w); cell:SetHeight(S.ItemHeight(o))
  cell.entry = o
  if o.type ~= "text" then local hl = cell:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(cell); AFUI.SetColor(hl, 1, 1, 1, 0.05) end
  local function label(text, room)
    local fs = cell:CreateFontString(nil, "OVERLAY", Wd.MEDIUM)
    fs:SetPoint("LEFT", cell, "LEFT", 8, 0); fs:SetWidth(room); fs:SetHeight(18); fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    fs:SetText(text)
    return fs
  end
  local control
  if o.type == "check" then
    cell.label = label(o.label, S.LabelRoom(o))
    control = Wd.Check(cell, "AFUI_Setting_" .. o.id, "", function(on) S.Set(o, on) end)
    control:SetPoint("RIGHT", cell, "RIGHT", -6, 0)
    cell:SetScript("OnClick", function() if control.Click then control:Click() end end)
  elseif o.type == "dropdown" then
    cell.label = label(o.label, S.LabelRoom(o))
    control = Wd.Dropdown(cell, "AFUI_Setting_" .. o.id, 130)
    control:SetPoint("RIGHT", cell, "RIGHT", -16, 0)
    control.SetItems(function()
      local items, cur = {}, S.Value(o)
      for _, c in ipairs(S.Choices(o)) do
        items[#items + 1] = { text = c[2], checked = c[1] == cur, func = function() S.Set(o, c[1]) end }
      end
      return items
    end)
  elseif o.type == "slider" then
    cell.label = label(o.label, S.LabelRoom(o))
    control = Wd.Slider(cell, "AFUI_Setting_" .. o.id, 240, o.min, o.max, o.step)
    control:SetPoint("RIGHT", cell, "RIGHT", -62, 0)
    control:SetScript("OnValueChanged", function(self)
      if cell.painting or not self.enabled then return end
      local v = math.floor(self:GetValue() / o.step + 0.5) * o.step
      if v ~= S.Value(o) then S.Set(o, v) else self.value:SetText(S.Display(o, v)) end
    end)
  elseif o.type == "button" then
    control = Wd.RedButton(cell, "AFUI_Setting_" .. o.id, o.label, w - 16, 28, "CENTER", 0, 0, function() safe(o.onClick) end)
  else -- text
    local fs = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, -4); fs:SetWidth(w - 16); fs:SetJustifyH("LEFT"); fs:SetHeight((o.lines or 1) * 16)
    cell.text = fs
  end
  cell.control = control
  if control and o.type ~= "text" then tipOn(cell, o, { cell, control }) end
  cells[o.id] = cell
  return cell
end

local function paint(o)
  local cell = cells[o.id]
  if not cell then return end
  local v = S.Value(o)
  if o.type == "check" then cell.control:SetChecked(v and true or false)
  elseif o.type == "dropdown" then cell.control:SetText(S.Display(o, v))
  elseif o.type == "slider" then
    cell.painting = true
    cell.control:SetValue(tonumber(v) or o.min); cell.control.value:SetText(S.Display(o, v))
    cell.painting = false
  elseif o.type == "text" then
    local t = type(o.text) == "function" and o.text() or o.text
    cell.text:SetText(t or "")
  end
end

-- The values of every shown cell, re-read (after a click, "Defaults", a slash command or another module's change).
function S.Refresh()
  if not (win and win:IsShown()) then return end
  for _, o in ipairs(S.Entries(S.current)) do paint(o) end
end

-- The page: the cells of the current category in the grid, the scroll range and the empty message.
function S.Rebuild()
  if not win then return end
  local cat = S.CATEGORIES[categoryIndex(S.current)]
  header:SetText(cat.label); desc:SetText(cat.desc or "")
  for _, c in pairs(cells) do c:Hide() end
  local shown = S.Entries(S.current)
  local items = {}
  for i, o in ipairs(shown) do items[i] = { span = S.Span(o), h = S.ItemHeight(o) } end
  local pos, total = S.Grid(items, S.COL_W, S.GAP, S.ROW_GAP)
  for i, o in ipairs(shown) do
    local cell = cells[o.id] or newCell(o)
    local p = pos[i]
    cell:ClearAllPoints(); cell:SetPoint("TOPLEFT", content, "TOPLEFT", p.x, -p.y)
    cell:Show()
    paint(o)
  end
  content:SetHeight(math.max(total, 1))
  if #shown == 0 then emptyText:Show() else emptyText:Hide() end
  if S.bar then S.bar:Refresh() end
  sf:SetVerticalScroll(0)
  if S.bar then S.bar:Refresh() end
  for i, b in ipairs(S.tabs or {}) do b.afActive = S.CATEGORIES[i].key == S.current end
  if K() then K().refreshTabs() end
end

function S.Select(key)
  if not categoryIndex(key) then return false end
  S.current = key
  if win then S.Rebuild() end
  return true
end

local function build()
  if win then return win end
  local Kt, Wd, Pk = K(), EW(), P()
  if not (Kt and Wd and Pk and CreateFrame and UIParent) then return nil end
  local f = CreateFrame("Frame", "AFUI_SettingsFrame", UIParent)
  win = f
  f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true); f:EnableMouse(true); f:SetClampedToScreen(true); f:Hide()
  f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -90) -- where the Guild & Communities window opens: above the unit frames, clear of the buffs
  Kt.window(f, { icon = AFUI.IconPath("Trade_Engineering"), w = S.W, h = S.H })
  f.title = f.afLabels:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOP", f, "TOP", 0, -6); f.title:SetText(S.TITLE)
  local close = CreateFrame("Button", "AFUI_SettingsClose", f); Pk.closeButton(close, f)
  close:SetScript("OnClick", function() f:Hide() end)
  f.close = close
  Kt.makeMovable(f, nil, "settings")
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "AFUI_SettingsFrame") end

  -- the page title and its rule
  header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", f, "TOPLEFT", 68, -31); header:SetJustifyH("LEFT") -- right of the medallion
  local rule = f:CreateTexture(nil, "ARTWORK"); AFUI.SetColor(rule, 0.45, 0.37, 0.2, 0.9)
  rule:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -58); rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -58); rule:SetHeight(1)
  desc = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  desc:SetPoint("TOPLEFT", f, "TOPLEFT", S.LIST_X, -64); desc:SetWidth(S.LIST_W); desc:SetJustifyH("LEFT")

  -- the dark inset behind the list and its bar
  local inset = CreateFrame("Frame", nil, f)
  inset:SetFrameLevel(f:GetFrameLevel() + 1)
  inset:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -86); inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, S.LIST_BOTTOM - 4)
  Kt.panel(inset)
  f.inset = inset

  sf = CreateFrame("ScrollFrame", "AFUI_SettingsScroll", f)
  sf:SetFrameLevel(f:GetFrameLevel() + 2)
  sf:SetPoint("TOPLEFT", f, "TOPLEFT", S.LIST_X, S.LIST_Y)
  sf:SetWidth(S.LIST_W); sf:SetHeight(S.H + S.LIST_Y - S.LIST_BOTTOM)
  content = CreateFrame("Frame", nil, sf)
  content:SetWidth(S.LIST_W); content:SetHeight(1)
  sf:SetScrollChild(content)
  content:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0)
  sf:EnableMouseWheel(true)
  list = sf
  local function viewH() return sf:GetHeight() or 0 end
  S.bar = Kt.scrollbar(sf, {
    get = function() return sf:GetVerticalScroll() or 0 end,
    set = function(v) sf:SetVerticalScroll(v) end,
    max = function() return math.max((content:GetHeight() or 0) - viewH(), 0) end, view = viewH, step = S.ROW_H * 2,
  }, { x = 3, parent = f })

  emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  emptyText:SetPoint("CENTER", sf, "CENTER", 0, 0); emptyText:SetWidth(360); emptyText:SetJustifyH("CENTER")
  emptyText:SetText("Nothing to set on this page yet. Its options appear here as soon as this part of the UI offers them.")
  emptyText:Hide()

  -- the buttons under the list
  local defaults = Wd.RedButton(f, "AFUI_SettingsDefaults", "Defaults", 130, 28, "BOTTOMLEFT", 16, 14, function() S.ResetCategory(S.current) end)
  tipOn(defaults, { label = "Defaults", tooltip = "Puts every option of this page back to its default. Other pages stay as they are.", type = "button" }, { defaults })
  local okay = Wd.RedButton(f, "AFUI_SettingsOkay", "Okay", 130, 28, "BOTTOMRIGHT", -16, 14, function() f:Hide() end)
  f.defaults, f.okay = defaults, okay

  -- the side tabs, one per category
  S.tabs = {}
  for i, c in ipairs(S.CATEGORIES) do
    local b = CreateFrame("Button", "AFUI_SettingsTab" .. i, f)
    Kt.sideTab(b, f, i, AFUI.IconPath(c.icon), c.label)
    b:SetScript("OnClick", function() S.Select(c.key) end)
    S.tabs[i] = b
  end

  return f
end

function S.Open(category)
  local f = build()
  if not f then return false end
  if category and categoryIndex(category) then S.current = category end
  f:Show()
  S.Rebuild() -- every time it opens: an option whose key was asked for meanwhile is there
  f:Raise()
  return true
end
function S.Close() if win then win:Hide() end end
function S.IsShown() return win ~= nil and win:IsShown() end
function S.Toggle() if S.IsShown() then S.Close() else S.Open() end end
function S.Frame() return win end

---------------------------------------------------------------- /afui config [page]
AFUI.Slash.Register("config", function(rest)
  local page = tostring(rest or ""):lower():gsub("%s", "")
  S.Open(categoryIndex(page) and page or nil)
end, "open this window (add a page: general, profiles, actionbars, chat, tooltips, nameplates, tracker, about)", "/afui [config]")
local function printLinks()
  say("links (the buttons on the About page open a box to copy them)")
  for _, l in ipairs(S.LINKS) do AFUI.Print("  |cff66ccff" .. l.label .. "|r  " .. l.url) end
end
AFUI.Slash.Register("about", printLinks, "print the author's links (Patreon, Linktree)", "/afui about")
AFUI.Slash.Register("links", printLinks, "same as /afui about", "/afui links")
AFUI.Slash.Info("/editmode", "move and resize the HUD")
AFUI.Slash.Info("/professions  /prof", "open the professions overview")

