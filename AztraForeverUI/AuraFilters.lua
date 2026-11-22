-- Aura filters for the raid-style party / raid frames (CompactParty.lua): which buffs and debuffs a frame shows, like ElvUI's filters but with a nicer way to build the lists.
--   AztraForeverUIDB.auraFilters = { v = 1,
--     lists = { [name] = { buffs = { entry, ... }, debuffs = { entry, ... } } },   -- the account wide library of the player's own lists
--     assignments = { party = { buffs = { mode, list, dispellable, noPermanent, maxMinutes, max, sort, boss }, debuffs = {...} }, raid = {...} },
--     display = { party = { buffs = { size, anchor, growth, swipe, timer, stacks, typeBorder, highlight }, debuffs = {...}, dispelHighlight = true } },
--     seen = { { id, name, icon, buff, src (the unit it was seen on), mine (cast by you) }, ... } }                                  -- "Recently seen auras", capped at SEEN_MAX
--   entry = { id = spellId | nil, name = "Rejuvenation" | nil, priority = 0-9, mine = true | nil, color = "rrggbb" | nil }
--   AztraForeverUICharDB.auraFilterList = { party = { buffs = "list name" } }: this character's own choice of list for a context / aura type.
-- The built-in lists live in this file (read only); a custom list may not take their names.
-- Spell identity: the spellId UnitBuff / UnitDebuff return (10th value on the 2.5.x client; the 2.4.3 client has none) and, always, the NAME: one spell has a different id per rank,
-- so an entry matches by id first and by its name second. The name is resolved with GetSpellInfo(id) (the client's language) and the stored English name is a second alias.
-- The engine allocates nothing per call: the compiled lists are cached until a list changes (AF.rev) and AF.Collect fills a caller-owned result whose records are reused.
AFUI = AFUI or {}
local IS_243 = AFUI.IS_243
local AF = { VERSION = 1, SEEN_MAX = 200, MAX_NAME = 32, MAX_LISTS = 40, MAX_ENTRIES = 300, MAX_ICONS = 8, HIGH = 5, rev = 1, logSeen = true }
AFUI.AuraFilters = AF

AF.MODES = { "All", "Only mine", "Only list", "All except list", "Mine + list" }
AF.SORTS = { "Priority", "Time left", "Mine first", "Aura order" }
AF.KINDS = { "buffs", "debuffs" }
AF.CONTEXTS = { { key = "party", label = "Party" }, { key = "raid", label = "Raid" } }
AF.CORNERS = { "Bottom Right", "Bottom Left", "Top Right", "Top Left" }
AF.GROWTHS = { "Left", "Right", "Up", "Down" }
local CORNER = { ["Bottom Right"] = "BOTTOMRIGHT", ["Bottom Left"] = "BOTTOMLEFT", ["Top Right"] = "TOPRIGHT", ["Top Left"] = "TOPLEFT" }
AF.CORNER = CORNER
local function oneOf(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end

local DEFAULT_ASSIGN = {
  buffs = { mode = "Only mine", list = "", dispellable = false, noPermanent = false, maxMinutes = 0, max = 3, sort = "Priority", boss = false },
  debuffs = { mode = "All", list = "", dispellable = false, noPermanent = false, maxMinutes = 0, max = 3, sort = "Priority", boss = false },
}
local DEFAULT_DISPLAY = {
  buffs = { size = 11, anchor = "Bottom Right", growth = "Left", swipe = true, timer = false, stacks = true, typeBorder = true, highlight = true },
  debuffs = { size = 11, anchor = "Bottom Left", growth = "Right", swipe = true, timer = false, stacks = true, typeBorder = true, highlight = true },
}
AF.DEFAULT_ASSIGN, AF.DEFAULT_DISPLAY = DEFAULT_ASSIGN, DEFAULT_DISPLAY
-- a raid layout is not part of this build (the raid frames are the client's own): its filters are stored and ready, the settings window offers them once a layout says it draws them
AF.available = { party = true, raid = false }

local function say(msg) if AFUI.Print then AFUI.Print("|cffffd100Aztra's Forever UI|r: " .. msg) end end
local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end
AF.Copy = copy

---------------------------------------------------------------- the built-in lists (starter lists: edit a copy freely)
-- id = the first rank's spell id (the name matches every rank). Ids only where they are certain; the rest by name (English client).
local function E(id, name, prio, mine) return { id = id, name = name, priority = prio, mine = mine } end
local B = {}
AF.BUILTIN_ORDER = { "Healer: Resto Druid HoTs", "Healer: Priest", "Healer: Shaman & Paladin", "Raid defensive cooldowns", "Raid utility buffs", "Raid debuffs (TBC bosses)" }
B["Healer: Resto Druid HoTs"] = { note = "Your own Rejuvenation, Regrowth and Lifebloom: use it with 'Only list' and other druids' HoTs stay hidden.",
  buffs = { E(33763, "Lifebloom", 3, true), E(774, "Rejuvenation", 2, true), E(8936, "Regrowth", 2, true), E(2893, "Abolish Poison", 1, true) } }
B["Healer: Priest"] = { note = "Your Renew, Prayer of Mending and Power Word: Shield, and who cannot take another shield.",
  buffs = { E(33076, "Prayer of Mending", 3, true), E(139, "Renew", 2, true), E(17, "Power Word: Shield", 2, true), E(6346, "Fear Ward", 1, true) },
  debuffs = { E(6788, "Weakened Soul", 1) } }
B["Healer: Shaman & Paladin"] = { note = "Earth Shield, and the blessings you cast. (Beacon of Light and Sacred Shield are not in The Burning Crusade.)",
  buffs = { E(974, "Earth Shield", 3, true), E(19977, "Blessing of Light", 2, true), E(20911, "Blessing of Sanctuary", 2, true), E(20217, "Blessing of Kings", 1, true),
    E(19742, "Blessing of Wisdom", 1, true), E(19740, "Blessing of Might", 1, true), E(1038, "Blessing of Salvation", 1, true) } }
B["Raid defensive cooldowns"] = { note = "Another player's big defensive: see when a tank uses Shield Wall or a paladin protects someone. Use it with 'Only list'.",
  buffs = { E(33206, "Pain Suppression", 5), E(1022, "Blessing of Protection", 5), E(6940, "Blessing of Sacrifice", 5), E(642, "Divine Shield", 5), E(498, "Divine Protection", 5),
    E(871, "Shield Wall", 5), E(12975, "Last Stand", 5), E(23920, "Spell Reflection", 4), E(2565, "Shield Block", 3), E(5277, "Evasion", 4), E(31224, "Cloak of Shadows", 4),
    E(22812, "Barkskin", 4), E(22842, "Frenzied Regeneration", 3), E(45438, "Ice Block", 5), E(19263, "Deterrence", 4), E(1044, "Blessing of Freedom", 3), E(19752, "Divine Intervention", 4) },
  debuffs = { E(25771, "Forbearance", 2) } }
B["Raid utility buffs"] = { note = "Bloodlust, Innervate, Power Infusion, Mana Tide and the like: what the raid should notice.",
  buffs = { E(2825, "Bloodlust", 5), E(32182, "Heroism", 5), E(29166, "Innervate", 4), E(10060, "Power Infusion", 4), E(nil, "Mana Tide", 3), E(nil, "Tranquil Air", 1),
    E(20707, "Soulstone Resurrection", 2), E(34477, "Misdirection", 2), E(6346, "Fear Ward", 1) } }
B["Raid debuffs (TBC bosses)"] = { note = "A starter list, edit freely (copy it first). Mostly by name, so only an English client matches those; ids are the ones that are certain.",
  debuffs = {
    -- Karazhan
    E(nil, "Enfeeble", 4), E(nil, "Sacrifice", 4), E(nil, "Flame Wreath", 5), E(nil, "Bellowing Roar", 3), E(nil, "Distracting Ash", 2), E(nil, "Garrote", 3), E(nil, "Holy Fire", 3), E(nil, "Blind", 3),
    -- Gruul's Lair, Magtheridon
    E(nil, "Stoned", 3), E(nil, "Cave In", 2), E(44032, "Mind Exhaustion", 3), E(nil, "Conflagration", 3), E(nil, "Burning Abyssal", 2),
    -- Serpentshrine Cavern
    E(37850, "Watery Grave", 5), E(38280, "Static Charge", 5), E(nil, "Entangle", 3), E(nil, "Toxic Spores", 4), E(nil, "Insidious Whisper", 4), E(nil, "Mark of Corruption", 3), E(nil, "Mark of Hydross", 3),
    -- Tempest Keep
    E(nil, "Flame Buffet", 2), E(nil, "Melt Armor", 3), E(nil, "Wrath of the Astromancer", 5), E(nil, "Burn", 3),
    -- Hyjal Summit
    E(nil, "Carrion Swarm", 3), E(nil, "Mark of Kaz'rogal", 4), E(nil, "Howl of Azgalor", 3), E(nil, "Doom", 5), E(nil, "Doomfire", 4), E(nil, "Grip of the Legion", 4), E(nil, "Air Burst", 3),
    -- Black Temple
    E(39837, "Impaling Spine", 5), E(40251, "Shadow of Death", 5), E(40869, "Fatal Attraction", 5), E(40932, "Agonizing Flames", 4), E(41917, "Parasitic Shadowfiend", 5), E(nil, "Dark Barrage", 4),
    E(nil, "Acidic Wound", 2), E(nil, "Aura of Suffering", 3), E(nil, "Bloodboil", 3), E(nil, "Shear", 2), E(nil, "Soul Drain", 2),
    -- Sunwell Plateau
    E(46394, "Burn", 4), E(nil, "Meteor Slash", 3), E(44866, "Spectral Blast", 5), E(45032, "Curse of Boundless Agony", 4), E(nil, "Encapsulate", 4), E(nil, "Noxious Fumes", 2),
    E(nil, "Dark Touched", 3), E(nil, "Fire Touched", 3), E(nil, "Soul Flay", 2), E(45641, "Fire Bloom", 5), E(nil, "Legion Lightning", 4) } }
AF.BUILTIN = B
function AF.IsBuiltin(name) return B[name] ~= nil end
for _, l in pairs(B) do l.buffs = l.buffs or {}; l.debuffs = l.debuffs or {}; l.builtin = true end

---------------------------------------------------------------- storage
local function charDB()
  if type(_G.AztraForeverUICharDB) ~= "table" then _G.AztraForeverUICharDB = {} end
  return _G.AztraForeverUICharDB
end

local function fixEntry(e)
  if type(e) ~= "table" then return nil end
  local id, name = tonumber(e.id), e.name
  if id and (id < 1 or id > 9999999 or id ~= math.floor(id)) then id = nil end
  if type(name) ~= "string" or name == "" or #name > 64 or name:find("[%c|]") then name = nil end
  if not (id or name) then return nil end
  local prio = tonumber(e.priority)
  prio = prio and math.max(0, math.min(9, math.floor(prio))) or nil
  local color = type(e.color) == "string" and e.color:match("^%x%x%x%x%x%x$") and e.color:lower() or nil
  return { id = id, name = name, priority = prio, mine = e.mine == true or nil, color = color }
end

-- Missing or damaged fields (an older save, a hand edited file) become defaults; idempotent.
local function normalize(t)
  if type(t.lists) ~= "table" then t.lists = {} end
  for name, l in pairs(t.lists) do
    if type(name) ~= "string" or B[name] or type(l) ~= "table" then t.lists[name] = nil
    else
      for _, kind in ipairs(AF.KINDS) do
        local out = {}
        if type(l[kind]) == "table" then for _, e in ipairs(l[kind]) do local f = fixEntry(e); if f and #out < AF.MAX_ENTRIES then out[#out + 1] = f end end end
        l[kind] = out
      end
    end
  end
  if type(t.assignments) ~= "table" then t.assignments = {} end
  if type(t.display) ~= "table" then t.display = {} end
  for _, c in ipairs(AF.CONTEXTS) do
    if type(t.assignments[c.key]) ~= "table" then t.assignments[c.key] = {} end
    if type(t.display[c.key]) ~= "table" then t.display[c.key] = {} end
    for _, kind in ipairs(AF.KINDS) do
      local a, d, da, dd = t.assignments[c.key][kind], t.display[c.key][kind], DEFAULT_ASSIGN[kind], DEFAULT_DISPLAY[kind]
      if type(a) ~= "table" then a = {}; t.assignments[c.key][kind] = a end
      if type(d) ~= "table" then d = {}; t.display[c.key][kind] = d end
      for k, v in pairs(da) do if type(a[k]) ~= type(v) then a[k] = v end end
      for k, v in pairs(dd) do if type(d[k]) ~= type(v) then d[k] = v end end
      if not oneOf(AF.MODES, a.mode) then a.mode = da.mode end
      if not oneOf(AF.SORTS, a.sort) then a.sort = da.sort end
      a.max = math.max(0, math.min(AF.MAX_ICONS, math.floor(a.max)))
      a.maxMinutes = math.max(0, math.min(600, math.floor(a.maxMinutes)))
      if not oneOf(AF.CORNERS, d.anchor) then d.anchor = dd.anchor end
      if not oneOf(AF.GROWTHS, d.growth) then d.growth = dd.growth end
      d.size = math.max(8, math.min(30, math.floor(d.size)))
    end
    if type(t.display[c.key].dispelHighlight) ~= "boolean" then t.display[c.key].dispelHighlight = true end
  end
  local seen = {}
  if type(t.seen) == "table" then
    for _, s in ipairs(t.seen) do
      if type(s) == "table" and #seen < AF.SEEN_MAX and (tonumber(s.id) or type(s.name) == "string") then
        seen[#seen + 1] = { id = tonumber(s.id), name = type(s.name) == "string" and s.name:sub(1, 64) or nil, icon = type(s.icon) == "string" and s.icon:sub(1, 128) or nil,
          buff = s.buff == true, src = type(s.src) == "string" and s.src:sub(1, 48) or nil, mine = s.mine == true or nil }
      end
    end
  end
  t.seen = seen
  t.v = AF.VERSION
end

-- The saved table, made complete on first use (the SavedVariables are not there while the files load: nothing here runs before the first caller asks).
function AF.DB()
  local d = _G.AztraForeverUIDB
  if type(d) ~= "table" then d = {}; _G.AztraForeverUIDB = d end
  local t = d.auraFilters
  if type(t) ~= "table" or t.v ~= AF.VERSION then
    if type(t) ~= "table" then t = {}; d.auraFilters = t end
    normalize(t)
    AF.rev = AF.rev + 1
  end
  return t
end
function AF.Touch() AF.rev = AF.rev + 1 end

---------------------------------------------------------------- lists
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function validName(name)
  name = trim(name)
  if name == "" then return nil, "empty name" end
  if #name > AF.MAX_NAME or name:find("[%c|]") then return nil, "bad name" end
  return name
end
local function findCustom(name)
  name = trim(name):lower()
  for k in pairs(AF.DB().lists) do if k:lower() == name then return k end end
end
local function findAny(name)
  name = trim(name):lower()
  for k in pairs(B) do if k:lower() == name then return k end end
  return findCustom(name)
end

-- Built-ins first (in their order), then the player's lists by name.
function AF.ListNames()
  local out = {}
  for _, n in ipairs(AF.BUILTIN_ORDER) do out[#out + 1] = n end
  local mine = {}
  for k in pairs(AF.DB().lists) do mine[#mine + 1] = k end
  table.sort(mine, function(a, b) return a:lower() < b:lower() end)
  for _, n in ipairs(mine) do out[#out + 1] = n end
  return out
end
function AF.GetList(name) if type(name) ~= "string" then return nil end; return B[name] or AF.DB().lists[name] end
function AF.CustomCount() local n = 0; for _ in pairs(AF.DB().lists) do n = n + 1 end; return n end

-- AF.OnChange(fn): fn() runs after every change of a list, an assignment or a display option (the frames redraw, the window repaints).
AF.listeners = {}
function AF.OnChange(fn) AF.listeners[#AF.listeners + 1] = fn end
local function afterChange()
  AF.Touch()
  for _, fn in ipairs(AF.listeners) do xpcall(fn, geterrorhandler()) end
end

function AF.CreateList(name)
  local n, err = validName(name)
  if not n then return false, err end
  if findAny(n) then return false, "exists" end
  if AF.CustomCount() >= AF.MAX_LISTS then return false, "too many" end
  AF.DB().lists[n] = { buffs = {}, debuffs = {} }
  afterChange()
  return true, n
end
-- A copy of any list (a built-in too) under a new name.
function AF.CopyList(from, to)
  local src = AF.GetList(from)
  if not src then return false, "missing" end
  local n, err = validName(to)
  if not n then return false, err end
  if findAny(n) then return false, "exists" end
  if AF.CustomCount() >= AF.MAX_LISTS then return false, "too many" end
  local l = { buffs = {}, debuffs = {} }
  for _, kind in ipairs(AF.KINDS) do for _, e in ipairs(src[kind]) do l[kind][#l[kind] + 1] = fixEntry(e) end end
  AF.DB().lists[n] = l
  afterChange()
  return true, n
end
function AF.RenameList(from, to)
  local old = findCustom(from)
  if not old then return false, AF.IsBuiltin(from) and "locked" or "missing" end
  local n, err = validName(to)
  if not n then return false, err end
  local clash = findAny(n)
  if clash and clash ~= old then return false, "exists" end
  local d = AF.DB()
  d.lists[n], d.lists[old] = d.lists[old], nil
  if n ~= old then
    for _, c in ipairs(AF.CONTEXTS) do
      for _, kind in ipairs(AF.KINDS) do
        if d.assignments[c.key][kind].list == old then d.assignments[c.key][kind].list = n end
        local o = charDB().auraFilterList
        if type(o) == "table" and type(o[c.key]) == "table" and o[c.key][kind] == old then o[c.key][kind] = n end
      end
    end
  end
  afterChange()
  return true, n
end
function AF.DeleteList(name)
  local n = findCustom(name)
  if not n then return false, AF.IsBuiltin(name) and "locked" or "missing" end
  local d = AF.DB()
  d.lists[n] = nil
  for _, c in ipairs(AF.CONTEXTS) do -- whatever used it shows everything again (mode and extras stay)
    for _, kind in ipairs(AF.KINDS) do
      if d.assignments[c.key][kind].list == n then d.assignments[c.key][kind].list = "" end
      local o = charDB().auraFilterList
      if type(o) == "table" and type(o[c.key]) == "table" and o[c.key][kind] == n then o[c.key][kind] = nil end
    end
  end
  afterChange()
  return true
end

-- Entries -------------------------------------------------------------------------------------------------------------
local function spellInfo(id)
  if not (id and GetSpellInfo) then return nil end
  local name, _, icon = GetSpellInfo(id)
  return name, icon
end
-- What to show for an entry: its name in the client's language (resolved from the id), else the stored one.
function AF.EntryName(e) local n = spellInfo(e.id); return n or e.name or (e.id and ("Spell " .. e.id)) or "?" end
function AF.EntryIcon(e) local _, i = spellInfo(e.id); return i or e.icon or "Interface\\Icons\\INV_Misc_QuestionMark" end

local function editable(listName)
  if B[listName] then return nil, "locked" end
  local l = AF.DB().lists[listName]
  if not l then return nil, "missing" end
  return l
end

local function sameEntry(a, b) return (a.id and b.id and a.id == b.id) or (a.name and b.name and a.name == b.name) end

-- spec = { id =, name =, priority =, mine =, color = }: a number id, a name, or both. A spell known by id gets its name stored too, a known name its id.
function AF.AddEntry(listName, kind, spec)
  local l, err = editable(listName)
  if not l then return false, err end
  if not oneOf(AF.KINDS, kind) then return false, "bad kind" end
  local e = fixEntry(spec)
  if not e then return false, "bad spell" end
  if e.id and not e.name then e.name = (spellInfo(e.id)) end
  if e.name and not e.id and GetSpellInfo then local _, _, _, _, _, _, sid = GetSpellInfo(e.name); if type(sid) == "number" and sid > 0 then e.id = sid end end
  for _, x in ipairs(l[kind]) do if sameEntry(x, e) then return false, "duplicate" end end
  if #l[kind] >= AF.MAX_ENTRIES then return false, "too many" end
  l[kind][#l[kind] + 1] = e
  afterChange()
  return true, e
end
function AF.RemoveEntry(listName, kind, index)
  local l, err = editable(listName)
  if not l then return false, err end
  if not (l[kind] and l[kind][index]) then return false, "missing" end
  table.remove(l[kind], index)
  afterChange()
  return true
end
-- Moves an entry up (delta -1) or down (+1) the list: the order is the tie break of the Priority sort.
function AF.MoveEntry(listName, kind, index, delta)
  local l, err = editable(listName)
  if not l then return false, err end
  local t = l[kind]
  local to = index + delta
  if not (t and t[index] and t[to]) then return false, "missing" end
  t[index], t[to] = t[to], t[index]
  afterChange()
  return true, to
end
-- field: "priority" (0-9), "mine" (boolean), "color" ("rrggbb" or nil)
function AF.SetEntry(listName, kind, index, field, value)
  local l, err = editable(listName)
  if not l then return false, err end
  local e = l[kind] and l[kind][index]
  if not e then return false, "missing" end
  if field == "priority" then
    value = tonumber(value)
    e.priority = value and math.max(0, math.min(9, math.floor(value))) or nil
  elseif field == "mine" then e.mine = value == true or nil
  elseif field == "color" then
    if value ~= nil and not (type(value) == "string" and value:match("^%x%x%x%x%x%x$")) then return false, "bad color" end
    e.color = value and value:lower() or nil
  else return false, "bad field" end
  afterChange()
  return true
end

---------------------------------------------------------------- assignments, the per character choice, the display options
function AF.Assignment(ctx, kind) return AF.DB().assignments[ctx][kind] end
function AF.Display(ctx, kind) return AF.DB().display[ctx][kind] end
function AF.DisplayOf(ctx) return AF.DB().display[ctx] end

-- A setting of an assignment (mode, list, dispellable, ...) with the value checked; false, why when it is not acceptable.
function AF.SetAssignment(ctx, kind, key, value)
  local a = AF.Assignment(ctx, kind)
  local d = DEFAULT_ASSIGN[kind]
  if not (a and d and d[key] ~= nil) then return false, "bad key" end
  if key == "mode" and not oneOf(AF.MODES, value) then return false, "bad value" end
  if key == "sort" and not oneOf(AF.SORTS, value) then return false, "bad value" end
  if key == "list" and not (value == "" or AF.GetList(value)) then return false, "missing" end
  if type(value) ~= type(d[key]) then return false, "bad value" end
  if key == "max" then value = math.max(0, math.min(AF.MAX_ICONS, math.floor(value))) end
  if key == "maxMinutes" then value = math.max(0, math.min(600, math.floor(value))) end
  a[key] = value
  afterChange()
  return true
end
function AF.SetDisplay(ctx, kind, key, value)
  local t = kind and AF.Display(ctx, kind) or AF.DisplayOf(ctx)
  local d = kind and DEFAULT_DISPLAY[kind] or { dispelHighlight = true }
  if not (t and d[key] ~= nil) or type(value) ~= type(d[key]) then return false, "bad value" end
  if key == "anchor" and not oneOf(AF.CORNERS, value) then return false, "bad value" end
  if key == "growth" and not oneOf(AF.GROWTHS, value) then return false, "bad value" end
  if key == "size" then value = math.max(8, math.min(30, math.floor(value))) end
  t[key] = value
  afterChange()
  return true
end

-- The list a context / aura type uses on THIS character: the character's own choice, else the account's assignment ("" = none).
function AF.ActiveList(ctx, kind)
  local o = charDB().auraFilterList
  local mine = type(o) == "table" and type(o[ctx]) == "table" and o[ctx][kind]
  if type(mine) == "string" and AF.GetList(mine) then return mine, true end
  local name = AF.Assignment(ctx, kind).list
  if name ~= "" and not AF.GetList(name) then name = "" end -- a list that was deleted
  return name, false
end
-- name nil / "" removes the override (the account's list applies again).
function AF.SetCharList(ctx, kind, name)
  local c = charDB()
  if name == nil or name == "" then
    if type(c.auraFilterList) == "table" and type(c.auraFilterList[ctx]) == "table" then c.auraFilterList[ctx][kind] = nil end
  else
    if not AF.GetList(name) then return false, "missing" end
    if type(c.auraFilterList) ~= "table" then c.auraFilterList = {} end
    if type(c.auraFilterList[ctx]) ~= "table" then c.auraFilterList[ctx] = {} end
    c.auraFilterList[ctx][kind] = name
  end
  afterChange()
  return true
end

---------------------------------------------------------------- dispel types of the player
-- The first rank's id of each dispel spell and what it removes; known by IsSpellKnown or by its name in the spellbook. A client that cannot tell falls back to the class.
local DISPELS = {
  { 527, "Magic" }, { 528, "Disease" }, { 552, "Disease" }, -- priest: Dispel Magic, Cure Disease, Abolish Disease
  { 1152, "Poison", "Disease" }, { 4987, "Magic", "Poison", "Disease" }, -- paladin: Purify, Cleanse
  { 526, "Poison" }, { 2870, "Disease" }, -- shaman: Cure Poison, Cure Disease
  { 8946, "Poison" }, { 2893, "Poison" }, { 2782, "Curse" }, -- druid: Cure Poison, Abolish Poison, Remove Curse
  { 475, "Curse" }, -- mage: Remove Curse
}
local CLASS_DISPEL = { PRIEST = { "Magic", "Disease" }, PALADIN = { "Magic", "Poison", "Disease" }, SHAMAN = { "Poison", "Disease" }, DRUID = { "Poison", "Curse" }, MAGE = { "Curse" } }
AF.dispel = { Magic = false, Curse = false, Poison = false, Disease = false }

-- The spellbook as { name = true } plus the list the picker suggests from; rebuilt when the spells change.
AF.book = {}
function AF.ScanSpellbook()
  local book, byName = {}, {}
  local nameFn = _G.GetSpellBookItemName or _G.GetSpellName
  local tabs = _G.GetNumSpellTabs and _G.GetNumSpellTabs() or 0
  if nameFn and _G.GetSpellTabInfo then
    for t = 1, tabs do
      local _, _, offset, count = _G.GetSpellTabInfo(t)
      for i = (offset or 0) + 1, (offset or 0) + (count or 0) do
        local name, _, sid = nameFn(i, "spell")
        if name and not byName[name] then
          byName[name] = true
          local icon = _G.GetSpellTexture and _G.GetSpellTexture(i, "spell")
          book[#book + 1] = { name = name, id = type(sid) == "number" and sid > 0 and sid or nil, icon = icon }
        end
      end
    end
  end
  AF.book, AF.bookNames = book, byName
  return book
end

function AF.ScanDispels()
  local d = AF.dispel
  d.Magic, d.Curse, d.Poison, d.Disease = false, false, false, false
  AF.ScanSpellbook()
  local sure = false
  for _, row in ipairs(DISPELS) do
    local known = _G.IsSpellKnown and _G.IsSpellKnown(row[1])
    if not known and AF.bookNames and _G.GetSpellInfo then local n = _G.GetSpellInfo(row[1]); known = n and AF.bookNames[n] end
    if known then for i = 2, #row do d[row[i]] = true end end
    if _G.IsSpellKnown or next(AF.bookNames or {}) then sure = true end
  end
  if not sure and _G.UnitClass then -- no way to ask the spellbook: the best the class can ever do
    local _, token = _G.UnitClass("player")
    for _, t in ipairs(CLASS_DISPEL[token] or {}) do d[t] = true end
  end
  AF.Touch()
  return d
end
-- Can the player dispel this debuff type ("Magic", "Curse", "Poison", "Disease")?
function AF.CanDispel(kind) return kind ~= nil and AF.dispel[kind] == true end

---------------------------------------------------------------- compiling a list for matching
local function compile(entries)
  local c = { byId = {}, byName = {}, n = #entries }
  for i, e in ipairs(entries) do
    local r = { entry = e, pos = i, prio = e.priority or 0, mine = e.mine }
    if e.color then r.cr, r.cg, r.cb = tonumber(e.color:sub(1, 2), 16) / 255, tonumber(e.color:sub(3, 4), 16) / 255, tonumber(e.color:sub(5, 6), 16) / 255 end
    if e.id and not c.byId[e.id] then c.byId[e.id] = r end
    local local_ = spellInfo(e.id)
    if local_ and not c.byName[local_] then c.byName[local_] = r end
    if e.name and not c.byName[e.name] then c.byName[e.name] = r end
  end
  return c
end

-- The rules of one context / aura type, resolved: same table every call until something changed (AF.rev).
local resolved = {}
function AF.Resolve(ctx, kind)
  local byCtx = resolved[ctx]
  if not byCtx then byCtx = {}; resolved[ctx] = byCtx end
  local cfg = byCtx[kind]
  if not cfg then cfg = {}; byCtx[kind] = cfg end
  if cfg.rev == AF.rev then return cfg end
  local a = AF.Assignment(ctx, kind)
  for k in pairs(DEFAULT_ASSIGN[kind]) do cfg[k] = a[k] end
  local name = AF.ActiveList(ctx, kind)
  cfg.list = name
  local l = name ~= "" and AF.GetList(name)
  cfg.compiled = l and compile(l[kind]) or nil
  cfg.hasList = l and true or false
  cfg.rev = AF.rev
  return cfg
end

---------------------------------------------------------------- the engine
-- Does record r pass cfg? r = { name, spellId, mine, kind, duration, boss } plus r.c (the list record it matched, set here). Pure: used by Collect and the specs.
function AF.Match(cfg, spellId, name)
  local c = cfg.compiled
  if not c then return nil end
  return (spellId and c.byId[spellId]) or (name and c.byName[name]) or nil
end

local function passes(cfg, r, debuff)
  local mine, c = r.mine, r.c
  if cfg.dispellable and debuff and not AF.CanDispel(r.kind) then return false end
  if cfg.noPermanent and not debuff and not (r.duration and r.duration > 0) then return false end
  if cfg.maxMinutes > 0 and r.duration and r.duration > cfg.maxMinutes * 60 then return false end
  if cfg.boss and r.boss then return true end
  local mode = cfg.mode
  if mode == "All" then return true end
  if mode == "Only mine" then return mine end
  local listed = c ~= nil and (not c.mine or mine)
  if mode == "Only list" then return listed end
  if mode == "All except list" then return not listed end
  if mode == "Mine + list" then return mine or listed end
  return true
end
AF.Passes = passes

-- a before b?
local function before(a, b, sort)
  if sort == "Time left" then
    if a.rem ~= b.rem then return a.rem < b.rem end
    if a.score ~= b.score then return a.score > b.score end
    return a.mine and not b.mine
  elseif sort == "Mine first" then
    if a.mine ~= b.mine then return a.mine and true or false end
    if a.score ~= b.score then return a.score > b.score end
    return a.rem < b.rem
  end
  if a.score ~= b.score then return a.score > b.score end
  if a.mine ~= b.mine then return a.mine and true or false end
  return a.rem < b.rem
end

local PERMANENT = 1e9
-- Fills out[1..n] (and out.n = n) with the auras of `unit` that pass cfg, sorted, at most cfg.max kept. The records of `out` are reused between calls: keep nothing of them.
-- A record: name, icon, count, kind (debuff type), duration, expires, mine, spellId, boss, rem (seconds left), score, c (the list record), hi (highlight), color.
-- filterArg: the client's own debuff filter (RAID = only what you can dispel), nil for all.
function AF.Collect(unit, debuff, cfg, out, filterArg)
  local fn = debuff and _G.UnitDebuff or _G.UnitBuff
  local n = 0
  out.n = 0
  if not fn then return 0 end
  local now = _G.GetTime and _G.GetTime() or 0
  local compiled = cfg.compiled
  local log = AF.logSeen
  for i = 1, 40 do
    local r = out[n + 1]
    if not r then r = {}; out[n + 1] = r end
    local name, tex, count, kind, duration, expires, mine, spellId, boss
    if IS_243 then
      local _
      name, _, tex, count, kind, duration, expires, mine = fn(unit, i, filterArg)
      mine = mine and mine ~= 0 or false
    else
      local caster, _
      name, tex, count, kind, duration, expires, caster, _, _, spellId, _, boss = fn(unit, i, filterArg)
      mine = caster == "player" or caster == "pet" or caster == "vehicle"
    end
    if not name then break end
    if type(spellId) ~= "number" then spellId = nil end
    r.name, r.icon, r.count, r.kind, r.duration, r.expires, r.mine, r.spellId, r.boss = name, tex, count, kind, duration, expires, mine, spellId, boss == true or boss == 1
    if log then AF.Seen(spellId, name, tex, not debuff, unit, mine) end
    local c = nil
    if compiled then c = (spellId and compiled.byId[spellId]) or compiled.byName[name] end
    r.c = c
    if passes(cfg, r, debuff) then
      r.rem = (duration and duration > 0 and expires and expires > 0) and (expires - now) or PERMANENT
      r.score = c and (c.prio * 1000 + 999 - math.min(c.pos, 999)) or -1
      r.hi = c ~= nil and (c.cr ~= nil or c.prio >= AF.HIGH)
      r.cr, r.cg, r.cb = nil, nil, nil
      if c and c.cr then r.cr, r.cg, r.cb = c.cr, c.cg, c.cb end
      n = n + 1
    end
  end
  local sort = cfg.sort
  if n > 1 and sort ~= "Aura order" then
    for i = 2, n do -- insertion sort: a few dozen records at most, nothing allocated
      local x, j = out[i], i - 1
      while j >= 1 and before(x, out[j], sort) do out[j + 1] = out[j]; j = j - 1 end
      out[j + 1] = x
    end
  end
  if n > cfg.max then n = cfg.max end
  out.n = n
  return n
end

---------------------------------------------------------------- recently seen auras
-- A rolling log (capped, de-duplicated by spell) of the auras seen on you and your group this session, saved with the account: the picker offers it as clickable icons.
local idx, idxFor = { buff = {}, debuff = {} }, nil
local function index(t)
  if idxFor == t.seen then return end
  idx.buff, idx.debuff, idxFor = {}, {}, t.seen
  for _, s in ipairs(t.seen) do (s.buff and idx.buff or idx.debuff)[s.id or s.name] = s end
end
function AF.Seen(spellId, name, icon, isBuff, unit, mine)
  local key = spellId or name
  if not key then return false end
  local t = AF.DB()
  index(t)
  local bucket = isBuff and idx.buff or idx.debuff
  if bucket[key] then return false end
  if type(name) ~= "string" or name:find("[%c|]") then return false end
  local src = _G.UnitName and _G.UnitName(unit) -- the unit it was seen ON
  local s = { id = spellId, name = name:sub(1, 64), icon = type(icon) == "string" and icon:sub(1, 128) or nil, buff = isBuff and true or false,
    src = type(src) == "string" and src:sub(1, 48) or nil, mine = mine and true or nil }
  t.seen[#t.seen + 1] = s
  bucket[key] = s
  while #t.seen > AF.SEEN_MAX do
    local old = table.remove(t.seen, 1)
    ;(old.buff and idx.buff or idx.debuff)[old.id or old.name] = nil
  end
  if AF.OnSeen then AF.OnSeen(s) end
  return true
end
function AF.SeenList() return AF.DB().seen end
function AF.ClearSeen() local t = AF.DB(); t.seen = {}; idxFor = nil end

---------------------------------------------------------------- what the picker suggests
-- Spells whose name starts with, or contains, `text` (case does not matter), from the spellbook then the recently seen auras: { name, id, icon, from = "spellbook" | "seen" }.
-- buff: true / false keeps only the seen auras of that kind (nil: both).
function AF.Suggest(text, max, buff)
  text = trim(text):lower()
  local out = {}
  if text == "" then return out end
  max = max or 12
  local have = {}
  local function consider(name, id, icon, from)
    if #out >= max or have[name] then return end
    local lname = name:lower()
    if lname:find(text, 1, true) then have[name] = true; out[#out + 1] = { name = name, id = id, icon = icon, from = from, rank = lname:sub(1, #text) == text and 0 or 1 } end
  end
  for _, b in ipairs(AF.book or {}) do consider(b.name, b.id, b.icon, "spellbook") end
  for _, s in ipairs(AF.DB().seen) do if s.name and (buff == nil or s.buff == buff) then consider(s.name, s.id, s.icon, "seen") end end
  table.sort(out, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.from ~= b.from then return a.from == "spellbook" end
    return a.name < b.name
  end)
  return out
end

-- The auras on a unit now as { name, id, icon, buff, mine }: the "Add target's auras" button.
function AF.UnitAuras(unit)
  local out = {}
  if not (unit and _G.UnitExists and _G.UnitExists(unit)) then return out end
  for _, debuff in ipairs({ false, true }) do
    local fn = debuff and _G.UnitDebuff or _G.UnitBuff
    for i = 1, 40 do
      local name, tex, spellId, caster
      if IS_243 then name, _, tex = fn(unit, i) else name, tex, _, _, _, _, caster, _, _, spellId = fn(unit, i) end
      if not name then break end
      out[#out + 1] = { name = name, icon = tex, id = type(spellId) == "number" and spellId or nil, buff = not debuff, mine = caster == "player" }
    end
  end
  return out
end

-- A spell dragged from the spellbook onto the cursor: { name, id, icon } and the cursor is cleared; nil when it holds something else.
function AF.FromCursor()
  if not _G.GetCursorInfo then return nil end
  local kind, a, b, c = _G.GetCursorInfo()
  if kind ~= "spell" then return nil end
  local name, id
  local nameFn = _G.GetSpellBookItemName or _G.GetSpellName
  if nameFn and type(a) == "number" then local n, _, sid = nameFn(a, b or "spell"); name, id = n, type(sid) == "number" and sid > 0 and sid or nil end
  if type(c) == "number" and c > 0 then id = c end
  if id and not name then name = (spellInfo(id)) end
  if not (name or id) then return nil end
  local icon = _G.GetSpellTexture and type(a) == "number" and _G.GetSpellTexture(a, b or "spell") or select(2, spellInfo(id))
  if _G.ClearCursor then _G.ClearCursor() end
  return { name = name, id = id, icon = icon }
end

---------------------------------------------------------------- export / import: AFUIF1:<checksum>:<base64 of the lines>
-- n<TAB>name  b|d<TAB>id<TAB>name<TAB>priority<TAB>mine<TAB>color (an entry of the list above it)   a|y<TAB>ctx<TAB>kind<TAB>key<TAB>value (an assignment / a display option)
local TAG = "AFUIF"
local MAX_TEXT, MAX_BODY, MAX_LINES = 262144, 196608, 6000
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64I = {}
for i = 1, 64 do B64I[B64:sub(i, i)] = i - 1 end
local function enc64(s)
  local P = AFUI.Profiles
  if P and P.B64Encode then return P.B64Encode(s) end
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1, c2, c3, c4 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1) .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end
local function dec64(s)
  local P = AFUI.Profiles
  if P and P.B64Decode then return P.B64Decode(s) end
  if #s % 4 ~= 0 or #s == 0 then return nil end
  local out = {}
  for i = 1, #s, 4 do
    local q, v = s:sub(i, i + 3), {}
    for j = 1, 4 do
      local ch = q:sub(j, j)
      if ch == "=" then if not (i + 3 == #s and j >= 3) then return nil end; v[j] = 0
      else v[j] = B64I[ch]; if not v[j] or (j > 1 and q:sub(j - 1, j - 1) == "=") then return nil end end
    end
    local n = v[1] * 262144 + v[2] * 4096 + v[3] * 64 + v[4]
    local chunk = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
    if q:sub(4, 4) == "=" then chunk = chunk:sub(1, q:sub(3, 3) == "=" and 1 or 2) end
    out[#out + 1] = chunk
  end
  return table.concat(out)
end
local function checksum(s) -- Adler-32: catches a damaged or cut off paste, it is no protection against a hand written string
  local a, b = 1, 0
  for i = 1, #s do a = (a + s:byte(i)) % 65521; b = (b + a) % 65521 end
  return string.format("%04x%04x", b, a)
end
local function encV(v)
  local t = type(v)
  if t == "boolean" then return v and "b1" or "b0" end
  if t == "number" and v == v and v ~= math.huge and v ~= -math.huge then return "n" .. string.format("%.14g", v) end
  if t == "string" and #v <= 64 and not v:find("[%c|\\]") then return "s" .. v end
end
local function decV(s)
  local k, rest = s:sub(1, 1), s:sub(2)
  if k == "b" then if rest == "1" then return true elseif rest == "0" then return false end return nil end
  if k == "n" then local v = rest:match("^%-?[%d%.]+$") and tonumber(rest); return v end
  if k == "s" and #rest <= 64 and not rest:find("[%c|\\]") then return rest end
end

-- data = { lists = { [name] = list }, assignments = {...}, display = {...} } (any part may be missing). Returns the text.
function AF.Serialize(data)
  local lines = {}
  local names = {}
  for k in pairs(data.lists or {}) do names[#names + 1] = k end
  table.sort(names)
  for _, name in ipairs(names) do
    lines[#lines + 1] = "n\t" .. name
    for _, kind in ipairs(AF.KINDS) do
      for _, e in ipairs(data.lists[name][kind] or {}) do
        lines[#lines + 1] = (kind == "buffs" and "b" or "d") .. "\t" .. (e.id or 0) .. "\t" .. (e.name or "") .. "\t" .. (e.priority or 0) .. "\t" .. (e.mine and 1 or 0) .. "\t" .. (e.color or "-")
      end
    end
  end
  for tag, src in pairs({ a = data.assignments, y = data.display }) do
    for _, c in ipairs(AF.CONTEXTS) do
      for _, kind in ipairs(AF.KINDS) do
        local t = src and src[c.key] and src[c.key][kind]
        if t then
          local keys = {}
          for k, v in pairs(t) do if encV(v) then keys[#keys + 1] = k end end
          table.sort(keys)
          for _, k in ipairs(keys) do lines[#lines + 1] = tag .. "\t" .. c.key .. "\t" .. kind .. "\t" .. k .. "\t" .. encV(t[k]) end
        end
      end
    end
  end
  local body = table.concat(lines, "\n")
  return TAG .. AF.VERSION .. ":" .. checksum(body) .. ":" .. enc64(body)
end

-- Strict reader: { lists, assignments, display } of plain checked values, or nil, why ("bad text", "version", "too big", "checksum", "bad data").
function AF.Deserialize(text)
  if type(text) ~= "string" then return nil, "bad text" end
  text = text:gsub("%s+", "")
  if #text > MAX_TEXT then return nil, "too big" end
  local ver, sum, payload = text:match("^" .. TAG .. "(%d+):(%x+):([%w%+/=]+)$")
  if not ver then return nil, "bad text" end
  if tonumber(ver) ~= AF.VERSION then return nil, "version" end
  if #sum ~= 8 then return nil, "bad text" end
  local body = dec64(payload)
  if not body then return nil, "bad text" end
  if #body > MAX_BODY then return nil, "too big" end
  if checksum(body) ~= sum:lower() then return nil, "checksum" end
  local out = { lists = {}, assignments = {}, display = {} }
  local cur, lines, nlists = nil, 0, 0
  for line in (body .. "\n"):gmatch("(.-)\n") do
    if line ~= "" then
      lines = lines + 1
      if lines > MAX_LINES then return nil, "too big" end
      local f = {}
      for part in (line .. "\t"):gmatch("(.-)\t") do f[#f + 1] = part end
      local tag = f[1]
      if tag == "n" and #f == 2 then
        local nm = validName(f[2])
        if not nm or out.lists[nm] then return nil, "bad data" end
        nlists = nlists + 1
        if nlists > AF.MAX_LISTS then return nil, "too big" end
        cur = { buffs = {}, debuffs = {} }
        out.lists[nm] = cur
      elseif (tag == "b" or tag == "d") and #f == 6 and cur then
        local id = tonumber(f[2])
        if not (f[4]:match("^%d$") and (f[5] == "0" or f[5] == "1") and (f[6] == "-" or f[6]:match("^%x%x%x%x%x%x$"))) then return nil, "bad data" end
        local e = fixEntry({ id = id and id > 0 and id or nil, name = f[3] ~= "" and f[3] or nil, priority = tonumber(f[4]), mine = f[5] == "1", color = f[6] ~= "-" and f[6] or nil })
        if not id or not e or (e.name or "") ~= f[3] or (e.id or 0) ~= (id or 0) then return nil, "bad data" end -- a name or an id the checker had to change is not ours
        local t = cur[tag == "b" and "buffs" or "debuffs"]
        if #t >= AF.MAX_ENTRIES then return nil, "too big" end
        t[#t + 1] = e
      elseif (tag == "a" or tag == "y") and #f == 5 then
        local ctx, kind, key, v = f[2], f[3], f[4], decV(f[5])
        local defaults = tag == "a" and DEFAULT_ASSIGN[kind] or DEFAULT_DISPLAY[kind]
        if not (defaults and defaults[key] ~= nil and (ctx == "party" or ctx == "raid") and type(v) == type(defaults[key])) then return nil, "bad data" end
        local dst = tag == "a" and out.assignments or out.display
        dst[ctx] = dst[ctx] or {}; dst[ctx][kind] = dst[ctx][kind] or {}
        dst[ctx][kind][key] = v
      else
        return nil, "bad data"
      end
    end
  end
  return out
end

function AF.Export(name)
  local l = AF.GetList(name)
  if not l then return nil, "missing" end
  return AF.Serialize({ lists = { [name] = l } })
end
-- Adds the lists of `text` to the library (a name that is taken gets " (2)" ...). Returns the names added, or false, why. rename: the name for a string that holds ONE list.
function AF.Import(text, rename)
  local data, why = AF.Deserialize(text)
  if not data then return false, why end
  local names = {}
  for k in pairs(data.lists) do names[#names + 1] = k end
  table.sort(names)
  if #names == 0 then return false, "bad data" end
  if #names == 1 and rename ~= nil and trim(rename) ~= "" then
    local n, e = validName(rename)
    if not n then return false, e end
    if n ~= names[1] then data.lists[n], data.lists[names[1]] = data.lists[names[1]], nil; names[1] = n end
  end
  if AF.CustomCount() + #names > AF.MAX_LISTS then return false, "too many" end
  local added = {}
  for _, name in ipairs(names) do
    local final, n = name, 1
    while findAny(final) do n = n + 1; final = name:sub(1, AF.MAX_NAME - #(" (" .. n .. ")")) .. " (" .. n .. ")" end
    AF.DB().lists[final] = data.lists[name]
    added[#added + 1] = final
  end
  afterChange()
  return added
end

---------------------------------------------------------------- profiles: the library travels with a profile
function AF.Snapshot()
  local t = AF.DB()
  return { lists = copy(t.lists), assignments = copy(t.assignments), display = copy(t.display) }
end
function AF.Restore(snap)
  if type(snap) ~= "table" then return false end
  local t = AF.DB()
  t.lists, t.assignments, t.display = copy(type(snap.lists) == "table" and snap.lists or {}), copy(type(snap.assignments) == "table" and snap.assignments or {}), copy(type(snap.display) == "table" and snap.display or {})
  t.v = nil -- normalised again: a profile from an older version lacks fields
  AF.DB()
  afterChange()
  return true
end
function AF.SnapshotText() return AF.Serialize(AF.Snapshot()) end
function AF.RestoreText(text)
  local data, why = AF.Deserialize(text)
  if not data then return false, why end
  return AF.Restore(data)
end

AF.ERRORS = {
  ["empty name"] = "Please enter a name.", ["bad name"] = "Use up to 32 characters, no | or control characters.", exists = "A list with that name already exists.",
  missing = "There is no such list.", locked = "That list is built in and read only: copy it first.", ["too many"] = "That is too many.", duplicate = "That spell is already in the list.",
  ["bad spell"] = "That is not a spell id or name.", ["bad text"] = "That is not an aura filter string.", version = "That string is from another version.",
  ["too big"] = "That text is too long.", checksum = "The string is damaged or cut off: copy it again.", ["bad data"] = "That string has data this version cannot read.",
}

---------------------------------------------------------------- start up, events, slash
AFUI.On("SPELLS_CHANGED", function() AF.ScanDispels() end)
AFUI.On("PLAYER_LOGIN", function() AF.DB(); AF.ScanDispels() end)
AFUI.On("LEARNED_SPELL_IN_TAB", function() AF.ScanDispels() end)

AFUI.Slash.Register("filters", function(rest)
  rest = tostring(rest or ""):lower()
  if rest == "list" then
    for _, c in ipairs(AF.CONTEXTS) do
      for _, kind in ipairs(AF.KINDS) do
        local a, name = AF.Assignment(c.key, kind), AF.ActiveList(c.key, kind)
        say(string.format("%s %s: %s, list '%s', up to %d, %s", c.label, kind, a.mode, name == "" and "none" or name, a.max, AF.available[c.key] and "drawn" or "no layout draws it yet"))
      end
    end
    return
  end
  if AF.UI and AF.UI.Open then AF.UI.Open() else say("the aura filter window is not part of this build.") end
end, "which buffs and debuffs the raid-style party frames show (opens the filter window; 'list' prints the settings)", "/afui filters [list]")
