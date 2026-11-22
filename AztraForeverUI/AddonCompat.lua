-- Addon compatibility: what Aztra's Forever UI does when another addon is loaded. One registry of adapters, one report (/afui compat), one switchboard (AFUI.ModuleEnabled).
--
-- ADAPTER  AC.Register(name, { kind = "integrate" | "clash" | "info", addons = { "Name", "Prefix_*" }, ... })
--   addons   IsAddOnLoaded names; a trailing * matches every addon whose name starts with the prefix (Bagnon_*). Default { name }.
--   detect() optional: true when the addon is around by other means (a frame exists). `present` is the old name for it and still works.
--   apply()  integrate adapters: runs ONCE when the addon is first seen (login, or later for a late / load-on-demand addon: ADDON_LOADED, and once more at
--            PLAYER_ENTERING_WORLD), and again whenever AC.Apply() runs for an adapter with reapply = true. Must be minimal and idempotent, never touch the other
--            addon's own frames beyond what the adapter documents, and run out of combat (it is queued). undo() puts it back (specs and /reload do not need it).
--   groups   clash adapters: the takeover modules the addon also draws (ids of AC.GROUPS below); draws = "the bags" for the notice.
--   report() optional: returns (what we did: string, { extra lines }). A kind-based default is printed otherwise.
-- Every call into an adapter is pcall'd: a failure is reported ONCE per adapter and call through the error handler, never repeated, and never stops the others.
--
-- TAKEOVER SWITCHES  AFUI.ModuleEnabled(group) is read when a takeover module would start (Core.lua skips the OnLogin of the modules of a group that is off and calls
--   their OnYield, if any; Chat.lua asks from its ADDON_LOADED). The answer is decided once per session and kept: the player's choice (Settings > Compatibility,
--   AztraForeverUIDB.settings.useBags ...), else ON, except OFF when an addon that draws the same thing is loaded (so a fresh install never fights Bagnon or ElvUI).
--   A change takes effect after /reload. Nothing of the other addon is ever disabled by us.
--   The same switches carry the WINDOW SWITCHES of Settings > Windows (groups with window = true: useCharacter, useSpellbook ... useBuffs): the client's own window instead of ours,
--   never decided by a clashing addon (default ON, OFF for the beta mailbox and auction house: default = false), with the older restyle settings (legacy = "mailRestyle" ...) as
--   the initial choice. They are asked at login or later, never while the files load.
local AFUI = AFUI
local AC = {}
AFUI.AddonCompat = AC

AC.adapters, AC.byName = {}, {}
AC.decided, AC.why = {}, {}

---------------------------------------------------------------- takeover groups
AC.GROUPS = {
  { id = "bags", key = "useBags", label = "Bags & Bank", modules = { "Bags", "Bank" },
    tip = "The combined bags window and the combined bank window." },
  { id = "actionbars", key = "useActionBars", label = "Action bars", modules = { "ActionBars", "ActionButtonFX", "BarExtras" },
    tip = "The action bars, pet and stance bars, XP bar, menu and bag buttons, end caps and the bar key bindings." },
  { id = "unitframes", key = "useUnitFrames", label = "Unit frames", modules = { "UnitFrames", "CastBars" },
    tip = "Player, target, target of target, pet and party member frames, and the cast bars." },
  { id = "party", key = "useParty", label = "Party frames", modules = { "CompactParty" },
    tip = "The raid-style party frames (Edit Mode > Party Frames > Use Raid-Style Party Frames)." },
  { id = "chat", key = "useChat", label = "Chat", modules = { "Chat", "ChatEditBronze", "ChatQoL" },
    tip = "The chat window skin and the chat extras: timestamps, copy, link boxes, history." },
  { id = "nameplates", key = "useNameplates", label = "Nameplates", modules = { "Nameplates", "NameplateAuras" },
    tip = "The plates over units in the world and the debuff row on them." },
  { id = "map", key = "useMap", label = "Map & quest log", modules = { "WorldMap", "QuestLog" },
    tip = "The world map window, the quest panel on it and the L key." },
  { id = "tooltips", key = "useTooltips", label = "Tooltips", modules = { "Tooltips" },
    tip = "The tooltip skin and the lines added to item and spell tooltips." },
  -- The window switches (Settings > Windows): one per Blizzard panel we restyle or replace. window = true keeps them off the Compatibility page (no addon clashes
  -- with them); default = false: a beta window, off until the player turns it on; legacy = the older setting, honoured until the new key is set.
  { id = "character", key = "useCharacter", label = "Character window", modules = { "CharacterFrame" }, window = true,
    tip = "The Character window (C): paper doll, Reputation, Skills, PvP and Pet panes, item levels and the side tabs." },
  { id = "spellbook", key = "useSpellbook", label = "Spellbook", modules = { "Spellbook" }, window = true,
    tip = "The Spellbook (P) with its pages, search, passives filter and the Mounts pane." },
  { id = "talents", key = "useTalents", label = "Talents", modules = { "Talents" }, window = true,
    tip = "The Talents window (N): the three trees, spent points and the talent search." },
  { id = "professions", key = "useProfessions", label = "Professions", modules = { "Professions" }, window = true,
    tip = "The Professions overview (K, /prof), its micro menu button and the restyled crafting windows (trade skills, Enchanting)." },
  { id = "tracker", key = "useTracker", label = "Objective tracker", modules = { "Tracker" }, window = true,
    tip = "The quest tracker under the minimap, with zones and automatic tracking." },
  { id = "social", key = "useSocial", label = "Friends, Who & Raid", modules = { "SocialFrame" }, window = true,
    tip = "The Social window: Friends, Ignore, Who and the Raid pages." },
  { id = "guild", key = "useGuild", label = "Guild windows", modules = { "GuildWindow", "GuildCommunities" }, window = true,
    tip = "The guild roster window (G) and Guild & Communities (J) with its chat." },
  { id = "lfg", key = "useLFG", label = "Group Finder", modules = { "GroupFinder" }, window = true,
    tip = "The Looking For Group window." },
  { id = "gamemenu", key = "useGameMenu", label = "Game menu (Esc)", modules = { "GameMenu" }, window = true,
    tip = "The Esc menu, with its Edit Mode and Aztra's Forever UI buttons. Off: type /afui to open these settings." },
  { id = "merchant", key = "useMerchant", label = "Vendor window", modules = { "MerchantFrame" }, window = true,
    tip = "The merchant window: buy, buy back and repair." },
  { id = "vendortools", key = "useVendorTools", label = "Sell Junk button", modules = { "VendorTools" }, window = true,
    tip = "The Sell Junk button on the vendor window and the automatic junk selling." },
  { id = "trainer", key = "useTrainer", label = "Trainer window", modules = { "TrainerFrame" }, window = true,
    tip = "The class and profession trainer window." },
  { id = "mail", key = "useMail", label = "Mailbox (beta)", modules = { "MailFrame" }, window = true, default = false, legacy = "mailRestyle",
    tip = "The mailbox: Inbox, Send Mail and the open letter. Still rough, so it starts off." },
  { id = "auction", key = "useAuction", label = "Auction house (beta)", modules = { "AuctionFrame" }, window = true, default = false, legacy = "auctionRestyle",
    tip = "The auction house. Still rough, so it starts off." },
  { id = "dialogs", key = "useDialogs", label = "Dialogs & dropdown menus", modules = { "Dialogs" }, window = true, legacy = "dialogsRestyle",
    tip = "The confirmation windows (Yes / No, name boxes) and the dropdown menus." },
  { id = "lootroll", key = "useLootRoll", label = "Loot roll windows", modules = { "LootRoll" }, window = true, legacy = "lootRollRestyle",
    tip = "The Need / Greed / Pass windows of group loot." },
  { id = "loot", key = "useLoot", label = "Loot window", modules = { "Loot" }, window = true,
    tip = "The window that lists what you can take from a corpse or chest." },
  { id = "minimap", key = "useMinimap", label = "Minimap", modules = { "Minimap" }, window = true,
    tip = "The round minimap with its ring, buttons, clock and coordinates." },
  { id = "buffs", key = "useBuffs", label = "Buffs & debuffs", modules = { "Buffs" }, window = true,
    tip = "The buff and debuff icons next to the minimap." },
}
-- The Windows page: its sections in order, each a list of group ids (the takeover switches of the Compatibility page appear here too, on the same keys).
AC.WINDOW_SECTIONS = {
  { "Character & spells", { "character", "spellbook", "talents", "professions" } },
  { "World & quests", { "map", "tracker" } },
  { "Social", { "social", "guild", "lfg" } },
  { "Bags & vendors", { "bags", "merchant", "vendortools", "trainer", "mail", "auction", "loot", "lootroll" } },
  { "Dialogs & menus", { "dialogs", "gamemenu" } },
  { "HUD", { "minimap", "buffs", "actionbars", "unitframes", "party", "nameplates", "chat", "tooltips" } },
}
-- "Use all Blizzard / Forever windows" sets every switch of the sections but the HUD one: the HUD pieces are not windows and keep their own choice.
function AC.BulkIds()
  local out = {}
  for _, sec in ipairs(AC.WINDOW_SECTIONS) do
    if sec[1] ~= "HUD" then for _, id in ipairs(sec[2]) do out[#out + 1] = id end end
  end
  return out
end
AC.groupById = {}
AFUI.ModuleGroup = AFUI.ModuleGroup or {}
for _, g in ipairs(AC.GROUPS) do
  AC.groupById[g.id] = g
  for _, m in ipairs(g.modules) do AFUI.ModuleGroup[m] = g.id end
end

---------------------------------------------------------------- detection
local function isLoaded(name) return IsAddOnLoaded and IsAddOnLoaded(name) and true or false end
local function g(n) return _G[n] end

-- Enabled in the AddOns list and loaded with the game (an addon that loads after ours is not "loaded" yet while our files run).
local function listed(n)
  if not _G.GetAddOnInfo then return false end
  local ok, name, _, _, loadable = pcall(GetAddOnInfo, n)
  if not (ok and name and loadable) then return false end
  if _G.IsAddOnLoadOnDemand and IsAddOnLoadOnDemand(n) then return false end
  return true
end

local function aliasHit(alias, pending)
  if alias:sub(-1) == "*" then
    local prefix = alias:sub(1, -2)
    for i = 1, (_G.GetNumAddOns and GetNumAddOns() or 0) do
      local n = GetAddOnInfo(i)
      if n and n:sub(1, #prefix) == prefix and (isLoaded(n) or (pending and listed(n))) then return n end
    end
    return nil
  end
  if isLoaded(alias) or (pending and listed(alias)) then return alias end
end

-- Reports one failure of an adapter once (per adapter and call name).
local function failed(a, what, err)
  a.state.errors = a.state.errors or {}
  if a.state.errors[what] then return end
  a.state.errors[what] = tostring(err)
  geterrorhandler()("AFUI compat: " .. a.name .. " " .. what .. ": " .. tostring(err))
end

-- Runs a.<what>(...) under pcall. Returns ok, result1, result2.
function AC.Run(a, what, ...)
  local fn = a[what]
  if type(fn) ~= "function" then return true end
  local ok, r1, r2 = pcall(fn, ...)
  if not ok then failed(a, what, r1); return false end
  return true, r1, r2
end

-- The name of the addon that makes this adapter "here" (nil when none). pending: count an addon that is enabled but has not loaded yet (our files run first).
function AC.Detect(a, pending)
  for _, alias in ipairs(a.addons) do
    local n = aliasHit(alias, pending)
    if n then return n end
  end
  local ok, r = AC.Run(a, "detect")
  if ok and r then return a.name end
end

---------------------------------------------------------------- registry
function AC.Register(name, a)
  if type(name) ~= "string" or type(a) ~= "table" then return false end
  a.name = name
  a.state = a.state or {}
  a.detect = a.detect or a.present
  a.addons = a.addons or (a.detect and {} or { name })
  a.kind = a.kind or ((a.apply or a.detect) and "integrate" or "info")
  if a.kind == "clash" then a.groups = a.groups or {} end
  if AC.byName[name] then
    for i, old in ipairs(AC.adapters) do if old == AC.byName[name] then AC.adapters[i] = a end end
  else
    AC.adapters[#AC.adapters + 1] = a
  end
  AC.byName[name] = a
  return true
end

local function clash(name, addons, groups, draws) AC.Register(name, { kind = "clash", addons = addons, groups = groups, draws = draws }) end
local function info(name, addons, extra)
  extra = extra or {}; extra.kind = "info"; extra.addons = addons
  AC.Register(name, extra)
end

---------------------------------------------------------------- the switches
function AC.Group(id) return AC.groupById[id] end

-- Loaded clash adapters that draw `group`.
function AC.ClashesFor(group, pending)
  local out = {}
  for _, a in ipairs(AC.adapters) do
    if a.kind == "clash" then
      for _, gid in ipairs(a.groups) do
        if gid == group and AC.Detect(a, pending) then out[#out + 1] = a.name end
      end
    end
  end
  return out
end

-- nil until the player chose. The older restyle settings (grp.legacy: mailRestyle, dialogsRestyle ...) count as the choice until the new key is set.
function AC.Explicit(group)
  local grp = AC.groupById[group]
  if not grp then return nil end
  local v = AFUI.PeekSetting(grp.key, nil)
  if v == nil and grp.legacy then v = AFUI.PeekSetting(grp.legacy, nil) end
  return v
end
function AC.Default(group, pending)
  local grp = AC.groupById[group]
  return #AC.ClashesFor(group, pending) == 0 and not (grp and grp.default == false)
end
-- What the switch says now (it applies after /reload): the choice, else the default.
function AC.Choice(group, pending)
  local v = AC.Explicit(group)
  if v == nil then return AC.Default(group, pending) end
  return v and true or false
end
function AC.SetChoice(group, on)
  local grp = AC.groupById[group]
  if grp then AFUI.SetSetting(grp.key, on and true or false) end
end

-- What this session does (decided on the first ask, then kept: a module cannot be half started). The window switches (group.window) are only ever asked at login or later:
-- the client loads the SavedVariables after our files ran (just before our ADDON_LOADED), so an answer given while the files load could not see the player's choice and would be
-- kept for the session: NO file may ask while it loads (tests/tools/real_order.test.mjs lists every ask made at file scope; Chat.lua asks from its ADDON_LOADED).
function AC.Enabled(group)
  local d = AC.decided[group]
  if d ~= nil then return d end
  local grp = AC.groupById[group]
  if not grp then return true end
  local pending = not AFUI.LoginStarted
  local v = AC.Explicit(group)
  if v == nil then
    local clashes = AC.ClashesFor(group, pending)
    v = AC.Default(group, pending)
    AC.why[group] = #clashes == 0 and "default" or ("default: " .. table.concat(clashes, ", ") .. " is loaded")
  else
    v = v and true or false
    AC.why[group] = "your choice"
  end
  AC.decided[group] = v
  return v
end
function AFUI.ModuleEnabled(group) return AC.Enabled(group) end

---------------------------------------------------------------- the clash notice (once per character)
local function joined(list, last)
  if #list <= 1 then return list[1] or "" end
  return table.concat(list, ", ", 1, #list - 1) .. " " .. last .. " " .. list[#list]
end

-- Prints the notice for the clashing addons not announced on this character yet (force: every clash, and a line when there is none). Returns the text or nil.
function AC.Notice(force)
  local db = _G.AztraForeverUICharDB
  if type(db) ~= "table" then return nil end
  local seen = type(db.compatNotice) == "table" and db.compatNotice or {}
  local list, names, yields = {}, {}, false
  for _, a in ipairs(AC.adapters) do
    if a.kind == "clash" and #a.groups > 0 and AC.Detect(a) then
      local undecided = false
      for _, gid in ipairs(a.groups) do
        if AC.Explicit(gid) == nil then undecided = true; if not AC.Enabled(gid) then yields = true end end
      end
      if force or (undecided and not seen[a.name]) then list[#list + 1] = a; names[#names + 1] = a.draws and (a.name .. " (" .. a.draws .. ")") or a.name end
    end
  end
  if #list == 0 then
    if force then AFUI.Print("|cffffd100Aztra's Forever UI|r: no addon that draws the same things as ours is loaded.") end
    return nil
  end
  local text
  if #list == 1 then
    text = list[1].name .. " is loaded; both draw " .. (list[1].draws or "the same things") .. "."
  else
    text = joined(names, "and") .. " are loaded; they draw some of the same things as Aztra's Forever UI."
  end
  if yields then text = text .. " Until you choose, ours stays off there." end
  text = "Aztra's Forever UI: " .. text .. " Open /afui > Compatibility to choose."
  AFUI.Print(text)
  db.compatNotice = seen
  for _, a in ipairs(list) do seen[a.name] = true end
  return text
end
function AC.ReshowNotice()
  local db = _G.AztraForeverUICharDB
  if type(db) == "table" then db.compatNotice = nil end
  return AC.Notice(true)
end

---------------------------------------------------------------- the adapters: clashes (a known addon draws the same thing as one of our takeover modules)
clash("Bartender4", { "Bartender4" }, { "actionbars" }, "the action bars")
clash("Dominos", { "Dominos" }, { "actionbars" }, "the action bars")
clash("Neuron", { "Neuron" }, { "actionbars" }, "the action bars")
local ALL = { "bags", "actionbars", "unitframes", "party", "chat", "nameplates", "tooltips" }
clash("ElvUI", { "ElvUI", "ElvUI_*" }, ALL, "most of the interface")
clash("Tukui", { "Tukui", "TukUI" }, ALL, "most of the interface")
clash("LUI", { "LUI" }, { "bags", "actionbars", "unitframes", "party", "chat", "tooltips" }, "most of the interface")
clash("Bagnon", { "Bagnon", "Bagnon_*" }, { "bags" }, "the bags")
clash("ArkInventory", { "ArkInventory" }, { "bags" }, "the bags")
clash("AdiBags", { "AdiBags" }, { "bags" }, "the bags")
clash("Baganator", { "Baganator" }, { "bags" }, "the bags")
clash("Combuctor", { "Combuctor" }, { "bags" }, "the bags")
clash("OneBag3", { "OneBag3" }, { "bags" }, "the bags")
info("BagBrother", { "BagBrother" }, { note = "data only: it stores bag contents and draws nothing" })
clash("Grid", { "Grid" }, { "party" }, "the party and raid frames")
clash("Grid2", { "Grid2" }, { "party" }, "the party and raid frames")
clash("VuhDo", { "VuhDo" }, { "party" }, "the party and raid frames")
clash("HealBot", { "HealBot", "Healbot" }, { "party" }, "the party and raid frames")
clash("ShadowedUnitFrames", { "ShadowedUnitFrames" }, { "unitframes", "party" }, "the unit frames")
clash("PitBull4", { "PitBull4" }, { "unitframes", "party" }, "the unit frames")
clash("ZPerl", { "ZPerl", "XPerl" }, { "unitframes", "party" }, "the unit frames")
clash("Luna", { "LunaUnitFrames", "Luna" }, { "unitframes", "party" }, "the unit frames")
clash("Prat", { "Prat-3.0", "Prat" }, { "chat" }, "the chat window")
clash("Chatter", { "Chatter" }, { "chat" }, "the chat window")
clash("Glass", { "Glass" }, { "chat" }, "the chat window")
clash("TidyPlates", { "TidyPlates" }, { "nameplates" }, "the nameplates")
clash("Plater", { "Plater" }, { "nameplates" }, "the nameplates")
clash("Kui_Nameplates", { "Kui_Nameplates", "KuiNameplates" }, { "nameplates" }, "the nameplates")
clash("Mapster", { "Mapster" }, { "map" }, "the world map")
clash("Cartographer", { "Cartographer", "Cartographer3" }, { "map" }, "the world map")
clash("TipTac", { "TipTac" }, { "tooltips" }, "the tooltips")
info("TitanPanel", { "Titan", "TitanPanel" }, { note = "an info bar at the screen edge: no clash" })
info("FuBar", { "FuBar" }, { note = "an info bar at the screen edge: no clash" })

---------------------------------------------------------------- state of a frame, for the report
local function nameOf(f) return f and f.GetName and f:GetName() or (f and "?") or "nil" end
local function num(v) return type(v) == "number" and (math.floor(v * 10 + 0.5) / 10) or v end

function AC.Describe(f)
  if not f then return { exists = false } end
  local d = { exists = true, shown = f:IsShown() and true or false, parent = f.GetParent and nameOf(f:GetParent()) or "?", anchors = {} }
  if f.IsVisible then d.visible = f:IsVisible() and true or false end
  d.strata, d.level, d.alpha, d.scale = f.GetFrameStrata and f:GetFrameStrata(), f.GetFrameLevel and f:GetFrameLevel(), f.GetAlpha and num(f:GetAlpha()), f.GetEffectiveScale and num(f:GetEffectiveScale())
  local n = f.GetNumPoints and f:GetNumPoints() or (f.points and #f.points) or 0
  for i = 1, n do
    local p, rel, rp, x, y = f:GetPoint(i)
    d.anchors[#d.anchors + 1] = tostring(p) .. "->" .. nameOf(rel) .. ":" .. tostring(rp) .. " " .. tostring(num(x)) .. "," .. tostring(num(y))
  end
  d.left, d.bottom, d.w, d.h = f.GetLeft and num(f:GetLeft()), f.GetBottom and num(f:GetBottom()), f.GetWidth and num(f:GetWidth()), f.GetHeight and num(f:GetHeight())
  return d
end

local function line(label, d)
  if not d.exists then return label .. ": does not exist" end
  return label .. ": shown=" .. tostring(d.shown) .. " visible=" .. tostring(d.visible) .. " parent=" .. tostring(d.parent) .. " " .. tostring(d.strata) .. "/" .. tostring(d.level)
    .. " alpha=" .. tostring(d.alpha) .. " scale=" .. tostring(d.scale) .. " left=" .. tostring(d.left) .. " bottom=" .. tostring(d.bottom) .. " " .. tostring(d.w) .. "x" .. tostring(d.h)
    .. " [" .. table.concat(d.anchors, " | ") .. "]"
end

---------------------------------------------------------------- Outfitter
-- The TBC-era Outfitter the tester runs (title bar "Outfitter 2.0.4") could not be found to read; cdmichaelb/Outfitter 3.0.4 (Outfitter.xml:578-1062, Outfitter.lua:1198-1201,
-- 6208, OutfitterMinimapButton.lua) is the nearest source, and a tester screenshot shows the same layout: OutfitterFrame is a child of OutfitterButtonFrame (child of
-- PaperDollFrame), TOPLEFT at the paper doll's TOPRIGHT (-34 in 3.0.4, about +3 in the screenshot) / -48, and its OnShow sets its frame level to PaperDollFrame's - 1,
-- so it is drawn UNDER our mode tabs (level base + 6) and our window. We anchor it past the tabs, lift it with its whole tree above everything of ours, and redo both
-- after every OnShow / open call of Outfitter and every size change of our window. Every name is tried, whatever exists is used.
local OUTFITTER_PANEL_X, OUTFITTER_PANEL_Y = 2, -48 -- past the mode tabs, Outfitter's own y
local OUTFITTER_BUTTON = { "TOPRIGHT", "BOTTOMRIGHT", -20, 2 } -- hangs from the window's bottom edge: free in the full and the collapsed window
local LIFT = 60 -- levels above our window: our own highest is +30 (the close button)
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local PANELS = { "OutfitterFrame" }
local BUTTONS = { "OutfitterButton" }
local ROOTS = { "OutfitterFrameTab1", "OutfitterFrameTab2", "OutfitterFrameTab3" } -- tabs that are not under the panel are lifted on their own
local OPENERS = { { "Outfitter", { "OpenUI", "ToggleUI", "ToggleOutfitterFrame", "ShowPanel" } },
  { false, { "Outfitter_Toggle", "Outfitter_Open", "Outfitter_OpenUI", "Outfitter_ToggleOutfitterFrame", "Outfitter_ShowPanel" } } }
local offsets = setmetatable({}, { __mode = "k" }) -- child level minus parent level, remembered the first time so a re-lift is idempotent

local function first(names) for _, n in ipairs(names) do local f = g(n); if f and f.SetPoint then return f end end end

-- f is at least at `level` (top) or exactly there (a child); its children keep their own distance above it.
local function lift(f, level, top)
  if not (f and f.GetFrameLevel and f.SetFrameLevel) then return end
  if not top or f:GetFrameLevel() < level then f:SetFrameLevel(level) end
  if f.GetChildren then
    for _, k in ipairs({ f:GetChildren() }) do
      if type(k) == "table" and k.GetFrameLevel then
        local off = offsets[k]
        if not off then off = math.max(1, k:GetFrameLevel() - f:GetFrameLevel()); offsets[k] = off end
        lift(k, f:GetFrameLevel() + off)
      end
    end
  end
end

local function raise(f, cf)
  local want, have = cf:GetFrameStrata(), f.GetFrameStrata and f:GetFrameStrata()
  if have and (STRATA[have] or 0) < (STRATA[want] or 0) then f:SetFrameStrata(want) end
  lift(f, cf:GetFrameLevel() + LIFT, true)
end

local function moveOutfitter()
  local cf = _G.CharacterFrame
  if not cf then return end
  local panel, button = first(PANELS), first(BUTTONS)
  if panel then
    local tabW = AFUI.CharacterFrame and AFUI.CharacterFrame.TAB_W or 55
    panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", cf, "TOPRIGHT", tabW + OUTFITTER_PANEL_X, OUTFITTER_PANEL_Y)
    local pe, ce = panel.GetEffectiveScale and panel:GetEffectiveScale(), cf.GetEffectiveScale and cf:GetEffectiveScale()
    if pe and ce and pe > 0 and math.abs(pe / ce - 1) > 0.01 then panel:SetScale(panel:GetScale() * ce / pe) end -- a panel outside the window's scale chain keeps its size next to it
    raise(panel, cf)
  end
  if button then
    button:ClearAllPoints(); button:SetPoint(OUTFITTER_BUTTON[1], cf, OUTFITTER_BUTTON[2], OUTFITTER_BUTTON[3], OUTFITTER_BUTTON[4])
    raise(button, cf)
  end
  for _, n in ipairs(ROOTS) do local t = g(n); if t and not (panel and t.GetParent and t:GetParent() == panel) then raise(t, cf) end end
  if AFUI.RaiseMinimapAddons then AFUI.RaiseMinimapAddons() end -- OutfitterMinimapButton hangs off MinimapBackdrop: Minimap.lua lifts it by name
end

-- Outfitter re-anchors / re-levels the panel in its own OnShow and open functions: ours runs after them (HookScript / hooksecurefunc), hooked once per frame / function.
local hooked = {}
local function reapply() AFUI.RunOutOfCombat(moveOutfitter) end
local function hookOutfitter()
  for _, f in ipairs({ first(PANELS) or false, first(BUTTONS) or false }) do
    if f and f.HookScript and not hooked[f] then hooked[f] = true; f:HookScript("OnShow", reapply) end
  end
  for _, set in ipairs(OPENERS) do
    local t = set[1] and g(set[1]) or _G
    if type(t) == "table" and hooksecurefunc then
      for _, fn in ipairs(set[2]) do
        local key = tostring(t) .. fn
        if type(t[fn]) == "function" and not hooked[key] then hooked[key] = true; pcall(hooksecurefunc, t, fn, reapply) end
      end
    end
  end
end

local OUTFITTER_FRAMES = { "OutfitterButtonFrame", "OutfitterButton", "OutfitterFrame", "OutfitterMainFrame", "OutfitterFrameTab1", "OutfitterFrameTab2", "OutfitterFrameTab3", "OutfitterSlotEnables", "OutfitterMinimapButton" }
AC.Register("Outfitter", {
  kind = "integrate", addons = { "Outfitter" }, reapply = true,
  detect = function() return g("OutfitterFrame") ~= nil end,
  apply = function() if AC.Enabled("character") then hookOutfitter(); moveOutfitter() end end, -- Blizzard's own Character window: Outfitter's panel stays where Outfitter puts it
  frames = OUTFITTER_FRAMES,
  report = function()
    local out = {}
    out[#out + 1] = line("CharacterFrame", AC.Describe(_G.CharacterFrame))
    out[#out + 1] = line("PaperDollFrame", AC.Describe(_G.PaperDollFrame))
    out[#out + 1] = line("AFUI_CharacterWindow", AC.Describe(_G.AFUI_CharacterWindow))
    out[#out + 1] = line("AFUI_CharacterModeTab1", AC.Describe(_G.AFUI_CharacterModeTab1))
    for _, n in ipairs(OUTFITTER_FRAMES) do out[#out + 1] = line(n, AC.Describe(_G[n])) end
    return "its panel is seated past our mode tabs and lifted above our window", out
  end,
})

---------------------------------------------------------------- ItemRack
-- ItemRack's minimap button (ItemRackMinimapFrame, ItemRack.xml) hangs off the Minimap / UIParent with its own strata: our ring is MEDIUM and would cover it. The Minimap.lua
-- raise list (AFUI.MinimapRaiseNames) lifts every name on it above the ring; we add the button's name. Its set-change popup and menus are its own frames: left alone.
local ITEMRACK_BUTTON = "ItemRackMinimapFrame"
local itemRackAdded
AC.Register("ItemRack", {
  kind = "integrate", addons = { "ItemRack" },
  apply = function()
    local list = AFUI.MinimapRaiseNames
    if not list then return end
    for _, n in ipairs(list) do if n == ITEMRACK_BUTTON then return end end
    list[#list + 1] = ITEMRACK_BUTTON; itemRackAdded = true
    if AFUI.RaiseMinimapAddons then AFUI.RaiseMinimapAddons() end
  end,
  undo = function()
    local list = AFUI.MinimapRaiseNames
    if not (list and itemRackAdded) then return end
    for i = #list, 1, -1 do if list[i] == ITEMRACK_BUTTON then table.remove(list, i) end end
    itemRackAdded = nil
  end,
  report = function()
    return "its minimap button is kept above our minimap ring; its menus and popups are not touched", { line(ITEMRACK_BUTTON, AC.Describe(_G[ITEMRACK_BUTTON])), line("AFUI_MinimapRing", AC.Describe(_G.AFUI_MinimapRing)) }
  end,
})

---------------------------------------------------------------- Pawn
-- Both addons only ever append lines to the item tooltip, in the order their OnTooltipSetItem hooks run. Which hook is first depends on when Pawn installs its own (its load, or
-- its login), so with Pawn around the Item Level / ID lines are added by one more hook of ours, installed a moment after the world loaded: after every hook any addon put on at
-- load or login. Pawn's lines keep their place and ours follow. A line is skipped when the tooltip already has the same text (Tooltips.lua), so nothing shows twice.
AC.Register("Pawn", {
  kind = "integrate", addons = { "Pawn" },
  apply = function() AC.AfterWorld(function() if AFUI.Tooltips and AFUI.Tooltips.DeferExtras then AFUI.Tooltips.DeferExtras(true) end end) end,
  undo = function() if AFUI.Tooltips and AFUI.Tooltips.DeferExtras then AFUI.Tooltips.DeferExtras(false) end end,
  report = function() return "our Item Level / ID lines are added after Pawn's; Pawn's lines are never touched" end,
})

---------------------------------------------------------------- Questie
-- Never touched: Questie_* frames. Forever's tracker follows Questie's own switch (Tracker.lua) and /afui questie explains what Questie's tracker does. When Questie loads late
-- (or its tracker is switched on later) the follow-up is run again here.
AC.Register("Questie", {
  kind = "integrate", addons = { "Questie" },
  apply = function()
    local T = AFUI.Tracker
    if T then
      if T.HookQuestie then T.HookQuestie() end
      if T.Sync then T.Sync() end
    end
  end,
  report = function()
    local T = AFUI.Tracker
    return "tracker: " .. ((T and T.Mode and T.Mode()) or "n/a") .. " (ours stays inert while Questie's is on); /afui questie says more"
  end,
})

---------------------------------------------------------------- OmniCC, Masque / ButtonFacade: the standard parts of an action button
-- Skinning and cooldown addons look for the standard children of an action button: Icon, Cooldown, Count, HotKey, Name, Border, NormalTexture, FloatingBG (the client's
-- template names them <button>Icon ... and our buttons keep that template). Missing ones are listed in the report; the fields other addons read (button.icon, .cooldown, .Count,
-- .HotKey, .Name, .Border, .NormalTexture, .FloatingBG) are filled in when absent.
local PARTS = { { "icon", "Icon" }, { "cooldown", "Cooldown" }, { "Count", "Count" }, { "HotKey", "HotKey" }, { "Name", "Name" }, { "Border", "Border" }, { "FloatingBG", "FloatingBG" } }
-- Returns the standard parts the button lacks (and fills the fields of those it has).
function AC.ButtonParts(b)
  local missing, name = {}, b.GetName and b:GetName()
  local function want(field, obj, label)
    -- the two decorations a skin addon only looks up are made (hidden, under their standard name) when the button lacks them; the rest cannot be made up
    if not obj and name and b.CreateTexture and (label == "Border" or label == "FloatingBG") then
      obj = b:CreateTexture(name .. label, label == "Border" and "OVERLAY" or "BACKGROUND")
      obj:Hide()
    end
    if obj then if rawget(b, field) == nil then b[field] = obj end else missing[#missing + 1] = label end
  end
  for _, p in ipairs(PARTS) do want(p[1], name and _G[name .. p[2]], p[2]) end
  want("NormalTexture", b.GetNormalTexture and b:GetNormalTexture(), "NormalTexture")
  return missing
end
-- every button of our bars: { button name, { missing } } for those that lack something
function AC.EnsureButtonParts()
  local out = {}
  for _, bar in pairs(AFUI.Bars or {}) do
    for _, b in ipairs(bar.buttons or {}) do
      local m = AC.ButtonParts(b)
      if #m > 0 then out[#out + 1] = { nameOf(b), m } end
    end
  end
  return out
end
local function partsReport()
  local missing = AC.EnsureButtonParts()
  if #missing == 0 then return nil end
  local lines = {}
  for _, e in ipairs(missing) do lines[#lines + 1] = e[1] .. " lacks " .. table.concat(e[2], ", ") end
  return lines
end

-- A button another addon already skinned: our own skinning must not run over it again (ActionBars.lua SkinButton asks). The flags are the ones Masque / ButtonFacade set.
function AFUI.IsExternallySkinned(b)
  return b ~= nil and (rawget(b, "__MSQ_Skinned") or rawget(b, "__MSQ_Enabled") or rawget(b, "__MSQ_NormalTexture") or rawget(b, "__bf_skinned")) and true or false
end

AC.Register("OmniCC", {
  kind = "integrate", addons = { "OmniCC" },
  apply = function()
    AC.EnsureButtonParts()
    if AFUI.FX and AFUI.FX.SetExternalNumbers then AFUI.FX.SetExternalNumbers(true) end
  end,
  undo = function() if AFUI.FX and AFUI.FX.SetExternalNumbers then AFUI.FX.SetExternalNumbers(false) end end,
  report = function() return "it draws the cooldown numbers on our buttons (ours are off, so nothing shows twice)", partsReport() end,
})
AC.Register("Masque", {
  kind = "integrate", addons = { "Masque", "ButtonFacade" },
  apply = function() AC.EnsureButtonParts() end,
  report = function() return "a button it skinned is not re-skinned by us", partsReport() end,
})

---------------------------------------------------------------- addons that only anchor to ours: reported, nothing changed
local function frameLines(names)
  local out = {}
  for _, n in ipairs(names) do local f = g(n); out[#out + 1] = n .. ": " .. (f and (f.IsShown and f:IsShown() and "shown" or "hidden") or "does not exist") end
  return out
end
local function nameplateReport()
  local C = _G.C_NamePlate
  if not (C and C.GetNamePlates) then return "this client has no C_NamePlate: nothing to anchor to, nothing to do" end
  local n, kept = 0, 0
  for _, plate in ipairs(C.GetNamePlates() or {}) do n = n + 1; if plate.UnitFrame then kept = kept + 1 end end
  return n .. " plates in view, " .. kept .. " keep the client's UnitFrame (hidden, never removed or renamed): boss mod timers find the plate frames where they expect them"
end
info("DBM", { "DBM-Core" }, { report = nameplateReport })
info("BigWigs", { "BigWigs" }, { report = nameplateReport })
local CHAT_NOTE = function() return "anchors to UIParent / the chat window; our chat window is ChatFrame1 at the place Edit Mode gives it. Nothing changed" end
info("Details", { "Details" }, { report = CHAT_NOTE })
info("Recount", { "Recount" }, { report = CHAT_NOTE })
info("Skada", { "Skada" }, { report = CHAT_NOTE })
info("WeakAuras", { "WeakAuras" }, { report = function()
  return "anchors to the unit frames, nameplates and bars; nothing changed here", frameLines({ "PlayerFrame", "TargetFrame", "AFUI_PlayerFrame", "AFUI_TargetFrame" }) end })

---------------------------------------------------------------- scan, apply
-- Runs fn a moment after the world loaded (every addon has run its login code by then), or now when that moment has passed. A failure is reported once.
AC.worldQueue = {}
local WORLD_DELAY = 1
function AC.AfterWorld(fn)
  local function go()
    local ok, err = pcall(fn)
    if not ok and not AC.worldError then AC.worldError = true; geterrorhandler()("AFUI compat: after world: " .. tostring(err)) end
  end
  if AC.worldDone then
    if _G.C_Timer and C_Timer.After then C_Timer.After(WORLD_DELAY, go) else go() end
  else
    AC.worldQueue[#AC.worldQueue + 1] = go
  end
end

-- Looks at every adapter: a newly seen addon (login, a late load, load on demand) gets its apply() once.
function AC.ApplyAdapter(a)
  if type(a.apply) ~= "function" then return end
  a.runner = a.runner or function() if AC.Run(a, "apply") then a.state.applied = true end end
  AFUI.RunOutOfCombat(a.runner)
end

function AC.Scan(why)
  for _, a in ipairs(AC.adapters) do
    local hit = AC.Detect(a)
    local was = a.state.hit
    a.state.hit = hit
    if hit and not was then
      a.state.since = why
      if why ~= "login" then a.state.late = true end
      AC.ApplyAdapter(a)
    end
  end
end

-- Adapters that move frames re-run on window shows and size changes (their apply is idempotent).
function AC.Apply()
  for _, a in ipairs(AC.adapters) do
    if a.reapply and a.state.hit then AC.ApplyAdapter(a) end
  end
end

-- Puts an adapter's change back (undo()).
function AC.Unapply(name)
  local a = AC.byName[name]
  if a then AC.Run(a, "undo"); a.state.applied = nil end
end

---------------------------------------------------------------- the report
local function version(a)
  local n = a.state.hit or (a.addons[1] or a.name):gsub("%*$", "")
  local v = _G.GetAddOnMetadata and select(2, pcall(GetAddOnMetadata, n, "Version"))
  return (type(v) == "string" and v ~= "") and v or "-"
end

local function whatWeDid(a)
  local ok, text, extra = AC.Run(a, "report")
  if ok and type(text) == "string" then return text, extra end
  if a.kind == "clash" then
    local parts = {}
    for _, gid in ipairs(a.groups) do
      local grp = AC.groupById[gid]
      if grp then
        local on = AC.Enabled(gid)
        parts[#parts + 1] = grp.label .. ": " .. (on and "ours" or "yielded to " .. a.name) .. " (" .. (AC.why[gid] or "default") .. ")"
      end
    end
    if a.state.late then parts[#parts + 1] = "loaded after login: a change shows after /reload" end
    return #parts > 0 and table.concat(parts, "; ") or "nothing to do", extra
  end
  if a.kind == "integrate" then return a.state.applied and "adjusted" or "nothing to adjust", extra end
  return a.note or "listed for the report, nothing to do", extra
end

-- Rows { name, version, state, kind, what, extra } for every adapter.
function AC.Rows()
  local rows = {}
  for _, a in ipairs(AC.adapters) do
    local here = a.state.hit and true or false
    local row = { name = a.name, loaded = here, state = here and "loaded" or "not loaded", kind = a.kind }
    if here then row.version = version(a); row.what, row.extra = whatWeDid(a) end
    rows[#rows + 1] = row
  end
  return rows
end

-- Returns { lines } and prints them (print_ false: only returns). Loaded addons get a row (addon | version | state | kind | what we did), then the takeover switches, then the
-- known addons that are not loaded, then the extra lines an adapter has (frame states).
function AC.Report(print_)
  local out = {}
  local function add(s) out[#out + 1] = s end
  local meta = _G.GetAddOnMetadata and GetAddOnMetadata("AztraForeverUI", "Version")
  add("AFUI compat" .. (meta and (" (Aztra's Forever UI " .. meta .. ")") or ""))
  local rows, extras, off = AC.Rows(), {}, {}
  local any = false
  for _, r in ipairs(rows) do
    if r.loaded then
      if not any then add("addon | version | state | kind | what we did"); any = true end
      add(r.name .. " | " .. r.version .. " | " .. r.state .. " | " .. r.kind .. " | " .. r.what)
      if type(r.extra) == "table" and #r.extra > 0 then extras[#extras + 1] = { r.name, r.extra } end
    else
      off[#off + 1] = r.name
    end
  end
  if not any then add("no known third-party addons loaded") end
  local sw, wsw = {}, {}
  for _, grp in ipairs(AC.GROUPS) do
    local list = grp.window and wsw or sw
    list[#list + 1] = grp.label .. " = " .. (AC.Enabled(grp.id) and "ours" or (grp.window and "the client's own" or "yielded")) .. ((AC.Choice(grp.id) ~= AC.Enabled(grp.id)) and " (changes after /reload)" or "")
  end
  add("Takeover switches: " .. table.concat(sw, ", "))
  add("Window switches (Settings > Windows): " .. table.concat(wsw, ", "))
  if #off > 0 then add("Known, not loaded: " .. table.concat(off, ", ")) end
  for _, e in ipairs(extras) do
    add(e[1] .. " details:")
    for _, l in ipairs(e[2]) do add("  " .. l) end
  end
  if print_ ~= false then for _, s in ipairs(out) do AFUI.Print(s) end end
  return out
end

-- The Compatibility page's two live lines. Detected: the loaded addons we know, clashes with what they draw; at most MAXLEN characters.
local MAXLEN = 200
function AC.DetectedText()
  local parts = {}
  for _, a in ipairs(AC.adapters) do
    if a.state.hit then
      parts[#parts + 1] = a.kind == "clash" and (a.name .. " (" .. (a.draws or "clash") .. ")") or a.name
    end
  end
  if #parts == 0 then return "No other addon that we know is loaded: nothing to choose." end
  local text = "Detected: " .. table.concat(parts, ", ")
  if #text > MAXLEN then text = text:sub(1, MAXLEN - 3):gsub("[, ]+[^, ]*$", "") .. "..." end
  return text
end
-- Switches that differ from what this session runs (they apply after a reload).
function AC.PendingText(windows) -- windows: the Windows page lists every switch, the Compatibility page only its own
  local waiting = {}
  for _, grp in ipairs(AC.GROUPS) do
    if (windows or not grp.window) and AC.Choice(grp.id) ~= AC.Enabled(grp.id) then waiting[#waiting + 1] = grp.label end
  end
  if #waiting == 0 then return "Changes to these switches apply after a reload." end
  local text = "Waiting for a reload: " .. table.concat(waiting, ", ") .. "."
  if windows and #text > 84 then text = "Waiting for a reload: " .. #waiting .. " switches changed." end -- the Windows page has one line for it
  return text
end

---------------------------------------------------------------- wiring
AFUI.RegisterModule("AddonCompat", {
  OnLogin = function()
    for _, grp in ipairs(AC.GROUPS) do AC.Enabled(grp.id) end -- every switch is decided now, from what is loaded at login, and kept for the session
    AC.Scan("login")
    AC.Notice()
    if _G.CharacterFrame and CharacterFrame.HookScript and AC.Enabled("character") then
      CharacterFrame:HookScript("OnShow", AC.Apply)
      CharacterFrame:HookScript("OnSizeChanged", AC.Apply) -- collapse / expand
    end
  end,
})
local function late(why) if AC.loggedIn then AC.Scan(why); AC.Apply() end end
AFUI.On("ADDON_LOADED", function() late("addon") end)
AFUI.On("PLAYER_LOGIN", function() AC.loggedIn = true end)
AFUI.On("PLAYER_ENTERING_WORLD", function() -- one more look: an addon that registers at PLAYER_LOGIN or loads on demand is here by now
  if AC.worldDone then return end
  AC.worldDone = true
  late("world")
  local q = AC.worldQueue
  AC.worldQueue = {}
  for _, go in ipairs(q) do
    if _G.C_Timer and C_Timer.After then C_Timer.After(WORLD_DELAY, go) else go() end
  end
end)
AFUI.On("UI_SCALE_CHANGED", function() if AC.loggedIn then AC.Apply() end end)
AFUI.On("DISPLAY_SIZE_CHANGED", function() if AC.loggedIn then AC.Apply() end end)

if AFUI.Slash and AFUI.Slash.Register then
  AFUI.Slash.Register("compat", function(rest)
    if tostring(rest or ""):lower():find("^notice") then AC.ReshowNotice() else AC.Report() end
  end, "which third-party addons are loaded and what we did about each, the takeover switches and frame states (paste it in a bug report); /afui compat notice shows the clash notice again", "/afui compat")
end
