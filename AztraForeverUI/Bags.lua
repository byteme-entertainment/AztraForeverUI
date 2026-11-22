-- Forever-style bag windows: one window per bag (4 columns) or one Combined Bags window (10 columns, every bag and the backpack in one
-- grid), switched by the "Combine Bags" setting (Edit Mode checkbox on the Bags system, or the button on every open bag window).
-- Forever reference: tools/ref/interface/addons/blizzard_uipanels_game/mainline/containerframe.{lua,xml} (ContainerFrameCombinedBags,
-- grid constants CONTAINER_WIDTH 178, ITEM_SPACING 5, 10 / 4 columns, BottomRightToTopLeft fill), camelot/containerframe.lua
-- look = docs/forever-ref/screens/bags/bank-window.jpg.
-- Client facts (verified): 2.4.3 MOUZU/Blizzard-WoW-Interface 2.4.3/FrameXML/ContainerFrame.{lua,xml} and 2.5.3 Gethe/wow-ui-source tag 2.5.3
-- Interface/FrameXML/ContainerFrame.{lua,xml}: both have global GetContainerItemInfo (texture, count, locked, quality, ...), GetContainerNumSlots,
-- GetContainerItemCooldown, no C_Container; ContainerFrameItemButtonTemplate buttons work from `self:GetParent():GetID()` (bag) and
-- `self:GetID()` (slot) - so every bag gets an invisible "holder" frame carrying the bag id and the real Blizzard template buttons are its
-- children: click, right-click use, split, drag, tooltip, sell and bank/mail/trade deposit all stay Blizzard's own (secure) code.
AFUI = AFUI or {}

local ITEM, SPACE = 37, 5
local function gap(kind) return kind == "combined" and 1 or SPACE end -- the video packs the inventory grid at a 38 pitch
local COLS = { bag = 4, backpack = 4, keyring = 4, combined = 10 }
local KEYRING = -2
local MAX_BAG = 4
local PLAIN = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\"
local ROCK_TINT = { 0.6, 0.54, 0.5 }

---------------------------------------------------------------- pure layout maths
local BagLayout = {}
AFUI.BagLayout = BagLayout

function BagLayout.Rows(total, columns) return math.ceil(total / columns) end

-- Forever's BottomRightToTopLeft grid: the first button goes bottom right, so a short row ends up at the TOP, right aligned.
-- index0 counts in reading order (slot 1 first). Returns column, row (0 based, from the top left).
function BagLayout.Cell(index0, total, columns)
  local pad = (columns - total % columns) % columns
  local i = index0 + pad
  return i % columns, math.floor(i / columns)
end

-- The combined window's key ring section: a thin separator and the "Keys" label (KEY_HEAD px), then the key slots in the same 10 column grid,
-- reading order from the left. n = key slots (0 = no section). Returns the section's height.
local KEY_HEAD = 18
local SEARCH_H = 28 -- the combined window's search strip under the title (Mat: it gets the backpack's search bar)
function BagLayout.KeySection(n)
  if not n or n <= 0 then return 0 end
  local rows = BagLayout.Rows(n, COLS.combined)
  return KEY_HEAD + rows * ITEM + (rows - 1) * gap("combined")
end

-- kind: "bag" (separate bag), "backpack" / "combined" (search box + money strip), "keyring". Returns width, height.
-- keySlots: key ring slots shown inside a combined window.
function BagLayout.WindowSize(kind, total, keySlots, labelH)
  local c = COLS[kind] or 4
  local rows = BagLayout.Rows(total, c)
  local w = c * ITEM + (c - 1) * gap(kind) + 15
  -- the combined window: title strip, search strip, grid, key ring section, footer
  local h = rows * ITEM + math.max(rows - 1, 0) * gap(kind) + (kind == "combined" and 79 + SEARCH_H or kind == "backpack" and 126 - SEARCH_H or 57)
  if kind == "combined" then h = h + BagLayout.KeySection(keySlots) + (labelH or 0) end
  return w, h
end

-- "Group items by category": a gold label strip (LABEL_H) above the grid row where each category starts. cats[i] = category number (1..5) of the slot in
-- reading order, or false for a slot without one (empty, or inside a specialty bag). Labels only draw for a cleanly grouped bag (each category one run, in
-- ascending order, at least two of them), so an unsorted bag never shows a patchwork. Returns marks { { index, cat, row, col } } and the strip height in total.
local LABEL_H = 15
BagLayout.LABEL_H = LABEL_H
function BagLayout.GroupMarks(cats, total, cols)
  local marks, last = {}, nil
  for i = 1, total do
    local c = cats[i]
    if c and c ~= last then
      if last and c < last then return {}, 0 end
      last = c
      local col, row = BagLayout.Cell(i - 1, total, cols)
      marks[#marks + 1] = { index = i, cat = c, row = row, col = col }
    end
  end
  if #marks < 2 then return {}, 0 end
  local rows, n = {}, 0
  for _, m in ipairs(marks) do
    if not rows[m.row] then n = n + 1 end
    rows[m.row] = true
  end
  return marks, n * LABEL_H
end

-- label strips above or at this grid row (0 based): the grid row sits this many strips lower
function BagLayout.StripsThrough(marks, row)
  local seen, n = {}, 0
  for _, m in ipairs(marks) do
    if m.row <= row and not seen[m.row] then seen[m.row] = true; n = n + 1 end
  end
  return n
end

-- A window taller than the room above the stack's base (85 px) shrinks to fit.
function BagLayout.FitScale(h, screenH)
  local avail = screenH - 85 - 20
  if h <= avail then return 1 end
  return avail / h
end

-- sizes[bag] = slots. { { bag, slot }, ... }: backpack first, then bag 1..4, slots ascending.
function BagLayout.CombinedOrder(sizes)
  local out = {}
  for bag = 0, MAX_BAG do
    for slot = 1, sizes[bag] or 0 do out[#out + 1] = { bag, slot } end
  end
  return out
end

-- Forever's stack (CONTAINER_OFFSET_X -4, Y 85, spacing 8): windows are placed from the bottom right, each next one to the left of
-- the previous; one that no longer fits across starts a new row above the tallest of the row. sizes = { { w, h }, ... } (already
-- scaled). Returns { { x, y }, ... } as BOTTOMRIGHT offsets from the screen's bottom right (x negative).
function BagLayout.Stack(sizes, screenW, screenH)
  local out, used, rowBase, rowTall = {}, 4, 85, 0
  for i, s in ipairs(sizes) do
    if used > 4 and used + s[1] + 8 > screenW then used, rowBase, rowTall = 4, rowBase + rowTall + 8, 0 end
    out[i] = { x = -(used - 4) - 4, y = rowBase }
    used = used + s[1] + 8
    if s[2] > rowTall then rowTall = s[2] end
  end
  return out
end

---------------------------------------------------------------- what is open
-- Pure model (the frames just follow it). numSlots(bag) -> slots of a held bag (0 = none equipped). Windows: "combined" or the bag
-- ids 0..4 that are open, then the key ring (-2), which is always a window of its own (as in Forever on the PC).
local BagState = {}
BagState.__index = BagState
AFUI.BagState = BagState

function BagState.New(numSlots)
  return setmetatable({ numSlots = numSlots, combined = false, shown = false, open = {}, keyring = false }, BagState)
end

local function held(self, bag) return bag >= 0 and bag <= MAX_BAG and self.numSlots(bag) > 0 end

function BagState:Open(bag)
  if bag == KEYRING then self.keyring = true; return end
  if not held(self, bag) then return end
  if self.combined then self.shown = true else self.open[bag] = true end
end

function BagState:Close(bag)
  if bag == KEYRING then self.keyring = false; return end
  if self.combined then self.shown = false else self.open[bag] = nil end
end

function BagState:IsOpen(bag)
  if bag == KEYRING then return self.keyring end
  if not held(self, bag) then return false end
  if self.combined then return self.shown end
  return self.open[bag] == true
end

function BagState:Toggle(bag)
  if self:IsOpen(bag) then self:Close(bag) else self:Open(bag) end
end

function BagState:AnyBag()
  if self.combined then return self.shown end
  for bag = 0, MAX_BAG do if self.open[bag] and held(self, bag) then return true end end
  return false
end

-- Blizzard's OpenAllBags(forceOpen): everything open and not forced -> close all, else open every bag that exists.
function BagState:OpenAll(force)
  if self:AnyBag() and not force then self:CloseAll(); return end
  for bag = 0, MAX_BAG do self:Open(bag) end
end

function BagState:CloseAll()
  self.shown, self.open, self.keyring = false, {}, false
end

function BagState:SetCombined(on)
  on = on and true or false
  local any = self:AnyBag()
  self.combined, self.shown, self.open = on, false, {}
  self.keyring = false -- the key window folds into the section (or the section is gone): never carried across
  if any then for bag = 0, MAX_BAG do self:Open(bag) end end
end

function BagState:Windows()
  local out = {}
  if self.combined then
    if self.shown then out[1] = "combined" end
  else
    for bag = 0, MAX_BAG do if self.open[bag] and held(self, bag) then out[#out + 1] = bag end end
  end
  if self.keyring and not self.combined then out[#out + 1] = KEYRING end -- combined: the keys are a section of that window
  return out
end

---------------------------------------------------------------- search, money, setting
AFUI.BagSearch = {}
-- Part of the item name, or of `extra` (the item's lowercase type / quality / slot words, Bags.SearchExtra), any case, no patterns. No search matches
-- everything; an empty slot matches nothing once there is one.
function AFUI.BagSearch.Matches(name, text, extra)
  if not text or text == "" then return true end
  local t = string.lower(text)
  if name and string.find(string.lower(name), t, 1, true) then return true end
  return extra ~= nil and string.find(extra, t, 1, true) ~= nil
end

function AFUI.BagMoney(money)
  money = math.floor(money or 0)
  return math.floor(money / 10000), math.floor(money / 100) % 100, money % 100
end

local Bags = {}
AFUI.Bags = Bags
local function on(key) return AFUI.QoL and AFUI.QoL.Get(key) end

-- Per account (AztraForeverUIDB.bags.combine); a damaged value reads as off.
function Bags.IsCombined()
  local d = AztraForeverUIDB
  return type(d) == "table" and type(d.bags) == "table" and d.bags.combine == true
end

function Bags.SaveCombined(on)
  if type(AztraForeverUIDB) ~= "table" then AztraForeverUIDB = {} end
  if type(AztraForeverUIDB.bags) ~= "table" then AztraForeverUIDB.bags = {} end
  AztraForeverUIDB.bags.combine = on and true or false
end

-- The button's tooltip names what clicking it does (Mat: "activate one bag").
function Bags.ToggleTooltip(combined) return combined and "Separate Bags" or "Combine Bags" end
function Bags.ToggleHint(combined) return combined and "Go back to one window per bag." or "Activate one bag: every bag in a single window." end

---------------------------------------------------------------- frames
local state
local windows, holders, buttons = {}, {}, {}
Bags.searchText = ""

local function setShown(o, on) if on then o:Show() else o:Hide() end end

local function numSlots(bag)
  if bag == KEYRING then return (GetKeyRingSize and GetKeyRingSize()) or GetContainerNumSlots(KEYRING) or 0 end
  return GetContainerNumSlots(bag) or 0
end

-- the key ring section of the combined window: the setting is on and the key ring has slots (a character with no key ring size shows nothing)
local function keySlots()
  return (windows.combined and state and state.combined and (not AFUI.QoL or AFUI.QoL.Get("bagKeyring"))) and numSlots(KEYRING) or 0
end
function Bags.KeyringShown() return keySlots() > 0 end

local function sizes()
  local s = {}
  for bag = 0, MAX_BAG do s[bag] = numSlots(bag) end
  return s
end

-- Empty slot art: Forever's wing slot for EVERY empty slot (backpack, bags, specialty bags, key ring, combined window). Mat: no bag-family or keychain variants,
-- no per-bag icon in the combined window. The arguments stay for the callers.
function Bags.EmptyArt() return "bags-item-slot64-c60-2x" end

-- bag family flags of a held bag (0 = general); GetContainerNumFreeSlots returns free, family
function Bags.BagType(bag)
  if bag < 0 or not GetContainerNumFreeSlots then return 0 end
  local _, t = GetContainerNumFreeSlots(bag)
  return t or 0
end

-- Per carried bag { bag, name, free, total, family } (the backpack first; a bag slot with no bag is left out), and the sums over them: free, total, used.
function Bags.Info()
  local out = {}
  for bag = 0, MAX_BAG do
    local total = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
    if total > 0 then
      local free, family = GetContainerNumFreeSlots(bag)
      out[#out + 1] = { bag = bag, name = bag == 0 and (BACKPACK_TOOLTIP or "Backpack") or (GetBagName and GetBagName(bag)) or ("Bag " .. bag), free = free or 0, total = total, family = family or 0 }
    end
  end
  return out
end
function Bags.Totals(info)
  local free, total = 0, 0
  for _, e in ipairs(info) do free, total = free + e.free, total + e.total end
  return free, total, total - free
end

-- Currencies under the money: the ticked "Show on Backpack" ones (GetBackpackCurrencyInfo, up to 3), else honor (+ arena when held).
function Bags.Currencies()
  local out = {}
  if GetBackpackCurrencyInfo then
    for i = 1, 3 do
      local name, count, icon = GetBackpackCurrencyInfo(i)
      if name then out[#out + 1] = { count = count or 0, icon = icon } end
    end
    if #out > 0 then return out end
  end
  local CP = AFUI.CharacterPanes
  if CP and CP.Points then
    local faction = UnitFactionGroup and UnitFactionGroup("player") == "Horde" and "Horde" or "Alliance"
    out[1] = { count = CP.Points("honor"), icon = "Interface\\PVPFrame\\PVP-Currency-" .. faction }
    local arena = CP.Points("arena")
    if arena > 0 then out[2] = { count = arena, icon = "Interface\\PVPFrame\\PVP-ArenaPoints-Icon" } end
  end
  return out
end

---------------------------------------------------------------- categories, quest items, free slots by bag type, search words, Don't sell marks
-- "Group items by category": 1 equipment, 2 consumables, 3 trade goods (with gems and recipes), 4 quest, 5 miscellaneous. Indexed by the item class's rank in the
-- client's own class list (Sort.ClassRank, locale proof): Weapon, Armor, Container, Consumable, Trade Goods, Projectile, Quiver, Recipe, Gem, Misc, Quest, Key.
Bags.CATEGORY_LABELS = { "Equipment", "Consumables", "Trade Goods", "Quest", "Miscellaneous" }
local CAT_OF_RANK = { 1, 1, 5, 2, 3, 5, 5, 3, 3, 5, 4, 5 }
function Bags.Category(class, isQuest)
  if isQuest then return 4 end
  return CAT_OF_RANK[Bags.Sort.ClassRank(class)] or 5
end

-- isQuestItem, startsAQuest for a slot: the client's own call (2.5.x ContainerFrame), else the item's class "Quest" (English client only).
function Bags.QuestInfo(bag, slot, class)
  if _G.GetContainerItemQuestInfo and bag >= -1 then
    local isQuest, questId, active = GetContainerItemQuestInfo(bag, slot)
    return isQuest and true or false, (isQuest and questId and not active) and true or false
  end
  return class == "Quest", false
end

-- bag family bit (GetContainerNumFreeSlots' second value) -> name
local FAMILY = { [1] = "Quiver", [2] = "Ammo Pouch", [4] = "Soul Bag", [8] = "Leatherworking Bag", [16] = "Inscription Bag", [32] = "Herb Bag", [64] = "Enchanting Bag",
  [128] = "Engineering Bag", [256] = "Keyring", [512] = "Gem Bag", [1024] = "Mining Bag" }
function Bags.FamilyName(f)
  if not f or f == 0 then return "General" end
  return FAMILY[f] or "Specialty Bag"
end
-- Free and total slots per bag type from Bags.Info(): { { name, free, total } } with General first, then in bag order.
function Bags.FreeByType(info)
  local out, at = {}, {}
  local function row(f)
    local name = Bags.FamilyName(f)
    if not at[name] then at[name] = #out + 1; out[#out + 1] = { name = name, free = 0, total = 0 } end
    return out[at[name]]
  end
  row(0)
  for _, e in ipairs(info) do local r = row(e.family); r.free, r.total = r.free + e.free, r.total + e.total end
  if out[1].total == 0 then table.remove(out, 1) end
  return out
end

-- The words a search also matches besides the name: item class, subclass ("Potion"), quality names and colour ("epic", "purple") and the slot ("head").
-- Lowercase, cached per link (an item the client has not loaded yet is not cached).
local QUALITY_WORDS = { [0] = "poor grey gray junk", "common white", "uncommon green", "rare blue", "epic purple", "legendary orange", "artifact", "heirloom" }
local searchWords = {}
function Bags.SearchExtra(link)
  local c = searchWords[link]
  if c then return c end
  local name, _, q, _, _, class, sub, _, loc = GetItemInfo(link)
  if not name then return nil end
  q = q or 1
  c = string.lower(table.concat({ class or "", sub or "", QUALITY_WORDS[q] or "", _G["ITEM_QUALITY" .. q .. "_DESC"] or "", loc and loc ~= "" and (_G[loc] or "") or "" }, " "))
  searchWords[link] = c
  return c
end

-- Don't sell marks: per item id on the character (AztraForeverUICharDB.noSell). Alt-click on a bag slot toggles one; the junk selling skips them.
local NoSell = {}
Bags.NoSell = NoSell
function NoSell.Id(link) return link and tonumber(string.match(link, "item:(%d+)")) end
function NoSell.Is(link)
  local id, t = NoSell.Id(link), type(_G.AztraForeverUICharDB) == "table" and _G.AztraForeverUICharDB.noSell
  return on("bagDontSell") and id and type(t) == "table" and t[id] == true or false
end
function NoSell.Toggle(link)
  local id = NoSell.Id(link)
  if not id then return end
  if type(_G.AztraForeverUICharDB) ~= "table" then _G.AztraForeverUICharDB = {} end
  local d = _G.AztraForeverUICharDB
  if type(d.noSell) ~= "table" then d.noSell = {} end
  if d.noSell[id] then d.noSell[id] = nil else d.noSell[id] = true end
  return d.noSell[id] == true
end

---------------------------------------------------------------- sort (TBC has no SortBags: swap items with PickupContainerItem)
local Sort = {}
Bags.Sort = Sort

-- class rank: the client's own auction class order (locale proof), else English names; unknown classes sort after, by name
local CLASS_EN = { "Weapon", "Armor", "Container", "Consumable", "Trade Goods", "Projectile", "Quiver", "Recipe", "Gem", "Miscellaneous", "Quest", "Key" }
function Sort.ClassRank(class)
  local list = _G.GetAuctionItemClasses and { GetAuctionItemClasses() } or CLASS_EN
  for i, name in ipairs(list) do if name == class then return i end end
  for i, name in ipairs(CLASS_EN) do if name == class then return i end end
  return 50
end

-- Sort key of one item: type, then quality (best first), then name, then the bigger stack first. Same key = same item, so stacks stay side by side.
-- group (the "Group items by category" setting): the item's category number (Bags.Category) goes in front, so the bags read equipment, consumables,
-- trade goods, quest, miscellaneous and each group keeps the order above.
function Sort.Key(class, quality, name, count, group)
  return (group and (group .. "|") or "") .. string.format("%02d|%s|%d|%s|%04d", Sort.ClassRank(class), class or "", 9 - (quality or 1), name or "", 1000 - (count or 1))
end

-- true when the item family bits share a bit with the bag family bits (0 = general bag, takes everything)
local function share(a, b)
  a, b = a or 0, b or 0
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then return true end
    a, b = (a - a % 2) / 2, (b - b % 2) / 2
  end
  return false
end
function Sort.Fits(item, family)
  if not item or not item.key or not family or family == 0 then return true end
  return share(item.family, family)
end

-- items[i] = { key = string, family = item family bits } (or {} for an empty slot); families[i] = family bits of the bag slot i is in (0 / nil general).
-- Returns want[i] = the index of the item that belongs in slot i: specialty bags (quiver, soul bag, ...) take the first sorted items of their type, general slots the
-- rest in key order, empties last. An empty slot keeps its own place when it can. Pure.
function Sort.Target(items, families)
  local n, order = #items, {}
  for i = 1, n do if items[i].key then order[#order + 1] = i end end
  table.sort(order, function(a, b)
    local ka, kb = items[a].key, items[b].key
    if ka == kb then return a < b end
    return ka < kb
  end)
  local want, used = {}, {}
  for s = 1, n do
    if (families[s] or 0) ~= 0 then
      for _, idx in ipairs(order) do
        if not used[idx] and share(items[idx].family, families[s]) then want[s], used[idx] = idx, true; break end
      end
    end
  end
  local nextIdx = 1
  for s = 1, n do
    if (families[s] or 0) == 0 then
      while order[nextIdx] and used[order[nextIdx]] do nextIdx = nextIdx + 1 end
      local idx = order[nextIdx]
      if idx then want[s], used[idx] = idx, true end
    end
  end
  for _, idx in ipairs(order) do -- an item no bag type took (no general room): stays or takes any free slot it fits
    if not used[idx] then
      local slot = (not want[idx]) and idx
      if not slot then for s = 1, n do if not want[s] and Sort.Fits(items[idx], families[s]) then slot = s; break end end end
      if slot then want[slot], used[idx] = idx, true end
    end
  end
  local claimed = {} -- empties: an empty slot stays empty where it is, the rest fill what is left
  for s = 1, n do if not want[s] and not items[s].key then want[s], claimed[s] = s, true end end
  local spare = {}
  for s = 1, n do if not items[s].key and not claimed[s] then spare[#spare + 1] = s end end
  for s = 1, n do if not want[s] then want[s] = table.remove(spare, 1) or s end end
  return want
end

-- { { i, j }, ... } position swaps that turn the bags into Target. A swap is only made when the item that moves to the other slot fits that slot (a general item
-- cannot go into a quiver); a position that cannot be reached that way is left (a second run finishes it). Pure.
function Sort.Plan(items, families)
  families = families or {}
  local n = #items
  local want = Sort.Target(items, families)
  local cur, swaps = {}, {}
  for i = 1, n do cur[i] = i end
  local progress = true
  while progress do
    progress = false
    for i = 1, n do
      if cur[i] ~= want[i] then
        local j
        for k = 1, n do if cur[k] == want[i] then j = k; break end end
        if j and Sort.Fits(items[cur[i]], families[j]) then
          if items[cur[i]].key or items[cur[j]].key then swaps[#swaps + 1] = { i, j } end
          cur[i], cur[j] = cur[j], cur[i]
          progress = true
        end
      end
    end
  end
  return swaps
end

local function itemKey(bag, slot)
  local link = GetContainerItemLink(bag, slot)
  if not link then return nil end
  local name, _, quality, _, _, itype = GetItemInfo(link)
  local _, count = GetContainerItemInfo(bag, slot)
  local family = _G.GetItemFamily and GetItemFamily(link) or 0
  local group = on("bagGroupCategory") and Bags.Category(itype, Bags.QuestInfo(bag, slot, itype)) or nil
  return Sort.Key(itype, quality, name or link, count, group), link, type(family) == "number" and family or 0, count or 1, select(8, GetItemInfo(link))
end

-- Partial stacks of one item that fit into each other: { { from, to }, ... } (positions; the smaller stack is dropped on the bigger). items[i] = { id, count, max }.
-- Only a merge that empties the source is planned (the client's overflow rule is not relied on). Pure.
function Sort.Merges(items)
  local by, ids, out = {}, {}, {}
  for i, it in ipairs(items) do
    if it.id and it.max and it.max > 1 and (it.count or 1) < it.max then
      if not by[it.id] then by[it.id] = {}; ids[#ids + 1] = it.id end
      table.insert(by[it.id], { i = i, n = it.count or 1, max = it.max })
    end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local list = by[id]
    table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.i < b.i end)
    for k = #list, 2, -1 do -- smallest first, into the first bigger stack with room
      for d = 1, k - 1 do
        if list[d].n + list[k].n <= list[d].max then
          out[#out + 1] = { list[k].i, list[d].i }; list[d].n = list[d].n + list[k].n; break
        end
      end
    end
  end
  return out
end

-- Every slot of the carried bags in order, with the bag family it sits in: { bag, slot, family }.
function Sort.Slots()
  local out = {}
  for bag = 0, MAX_BAG do
    local fam = Bags.BagType(bag)
    for slot = 1, numSlots(bag) do out[#out + 1] = { bag, slot, fam } end
  end
  return out
end

local function snapshot(pos)
  local items, links, families = {}, {}, {}
  for i, p in ipairs(pos) do
    local key, link, family, count, max = itemKey(p[1], p[2])
    items[i] = { key = key, family = family, id = link and tonumber(string.match(link, "item:(%d+)")), count = count, max = max }
    links[i] = link or false; families[i] = p[3]
  end
  return items, links, families
end

local sorter = CreateFrame("Frame")
local run
local function stop(why) run = nil; sorter:SetScript("OnUpdate", nil); Sort.last = why; if Bags.UpdateAll then Bags.UpdateAll() end end
local function locked(p) local _, _, l = GetContainerItemInfo(p[1], p[2]); return l end
-- Picks the item of a up and drops it on b (a swap or a merge); false when the hand still holds something afterwards (the run is aborted).
local function move(a, b)
  PickupContainerItem(a[1], a[2]); PickupContainerItem(b[1], b[2]) -- the item of a lands in b; b's item (if any) is now in the hand
  if CursorHasItem and CursorHasItem() then PickupContainerItem(a[1], a[2]) end -- ... and goes to a
  if CursorHasItem and CursorHasItem() then if ClearCursor then ClearCursor() end; return false end
  return true
end
local function step(_, dt)
  if not run then return stop("idle") end
  run.t = run.t + dt
  if run.t > run.limit or InCombatLockdown() or (CursorHasItem and CursorHasItem()) then return stop("aborted") end
  if run.alive and not run.alive() then return stop("closed") end -- the bank closed: its slots cannot be moved any more
  run.wait = run.wait - dt
  if run.wait > 0 then return end
  local mv = run.moves[run.m]
  if mv then -- phase 1: merge partial stacks
    local a, b = run.pos[mv[1]], run.pos[mv[2]]
    if locked(a) or locked(b) then return end
    if (GetContainerItemLink(a[1], a[2]) or false) ~= run.links[mv[1]] or (GetContainerItemLink(b[1], b[2]) or false) ~= run.links[mv[2]] then return stop("changed") end
    if not move(a, b) then return stop("aborted") end
    run.links[mv[1]] = false
    run.m = run.m + 1; run.wait = 0.1
    return
  end
  if not run.swaps then -- phase 2: once the merges have settled (no slot locked), plan the order from what is really there
    for _, p in ipairs(run.pos) do if locked(p) then return end end
    local items, links, families = snapshot(run.pos)
    run.swaps, run.links, run.n = Sort.Plan(items, families), links, 1
    run.limit = run.t + 10 + #run.swaps
  end
  local sw = run.swaps[run.n]
  if not sw then return stop("done") end
  local a, b = run.pos[sw[1]], run.pos[sw[2]]
  if locked(a) or locked(b) then return end
  -- the bags changed under us (an item moved or was looted): the plan is stale
  if (GetContainerItemLink(a[1], a[2]) or false) ~= run.links[sw[1]] or (GetContainerItemLink(b[1], b[2]) or false) ~= run.links[sw[2]] then return stop("changed") end
  if not move(a, b) then return stop("aborted") end
  run.links[sw[1]], run.links[sw[2]] = run.links[sw[2]], run.links[sw[1]]
  run.n = run.n + 1; run.wait = 0.1
end

-- Cleans up the carried bags, or `slots` ({ bag, slot, family } in order, e.g. the bank's) when given; alive() (optional) must stay true or the run stops.
-- Returns true when a run started; false with Sort.last = "combat" / "cursor" / "nothing" / "busy" otherwise.
function Sort.Start(slots, alive)
  if run then Sort.last = "busy"; return false end
  if InCombatLockdown() then Sort.last = "combat"; return false end
  if CursorHasItem and CursorHasItem() then Sort.last = "cursor"; return false end
  if not (PickupContainerItem and GetContainerItemLink and GetItemInfo) then return false end
  local pos = slots or Sort.Slots()
  local items, links, families = snapshot(pos)
  local moves = Sort.Merges(items)
  local swaps = #moves == 0 and Sort.Plan(items, families) or nil -- with merges first, the order is planned after them
  if #moves == 0 and #swaps == 0 then Sort.last = "nothing"; return false end
  run = { pos = pos, links = links, moves = moves, m = 1, swaps = swaps, n = 1, t = 0, wait = 0, limit = 10 + #pos, alive = alive }
  sorter:SetScript("OnUpdate", step)
  return true
end
-- scope "bags" / "bank": only stops a run of that kind (closing the bags must not end a bank clean up, nor the other way round)
function Sort.Stop(why, scope) if run and (not scope or (scope == "bank") == (run.alive ~= nil)) then stop(why or "aborted") end end
function Sort.Running(scope) return run ~= nil and (not scope or (scope == "bank") == (run.alive ~= nil)) end
Sort.Step = step
AFUI.On("PLAYER_REGEN_DISABLED", function() Sort.Stop("aborted") end)

---------------------------------------------------------------- item level (gear only: bag slots, character slots, the average in the stats)
local IL = {}
AFUI.ItemLevel = IL
-- GetItemInfo returns itemLevel 4th and the equip slot 9th on both TBC clients. Bags, quivers, ammo, shirts and tabards carry no meaningful level.
IL.SKIP = { INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_AMMO = true, INVTYPE_TABARD = true, INVTYPE_BODY = true }
-- inventory slot ids that count in the average (shirt 4 and tabard 19 do not) and the button each one has on the Character window
IL.SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
IL.CHAR = { [1] = "CharacterHeadSlot", [2] = "CharacterNeckSlot", [3] = "CharacterShoulderSlot", [15] = "CharacterBackSlot", [5] = "CharacterChestSlot",
  [9] = "CharacterWristSlot", [10] = "CharacterHandsSlot", [6] = "CharacterWaistSlot", [7] = "CharacterLegsSlot", [8] = "CharacterFeetSlot",
  [11] = "CharacterFinger0Slot", [12] = "CharacterFinger1Slot", [13] = "CharacterTrinket0Slot", [14] = "CharacterTrinket1Slot",
  [16] = "CharacterMainHandSlot", [17] = "CharacterSecondaryHandSlot", [18] = "CharacterRangedSlot" }

-- link -> itemLevel, quality, equipLoc of a piece of gear that has a level; nil for everything else
function IL.Info(link)
  if not link or not _G.GetItemInfo then return end
  local _, _, quality, ilvl, _, _, _, _, equipLoc = GetItemInfo(link)
  if type(ilvl) ~= "number" or ilvl <= 0 or not equipLoc or equipLoc == "" or IL.SKIP[equipLoc] then return end
  return ilvl, quality or 1, equipLoc
end

function IL.Color(quality)
  local c = _G.ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

-- Average of the 17 gear slots (an empty slot counts 0; a two-hander counts twice, as in the offhand slot). info(slotId) -> itemLevel, equipLoc.
function IL.Average(info)
  local sum, n = 0, 0
  local mainLevel, mainLoc, offLevel
  for _, id in ipairs(IL.SLOTS) do
    local ilvl, loc = info(id)
    n = n + 1
    if ilvl then sum = sum + ilvl end
    if id == 16 then mainLevel, mainLoc = ilvl, loc elseif id == 17 then offLevel = ilvl end
  end
  if mainLevel and mainLoc == "INVTYPE_2HWEAPON" and not offLevel then sum = sum + mainLevel end
  return n > 0 and math.floor(sum / n) or 0
end

function IL.EquippedAverage()
  if not _G.GetInventoryItemLink then return 0 end
  return IL.Average(function(id) local ilvl, _, loc = IL.Info(GetInventoryItemLink("player", id)); return ilvl, loc end)
end

---------------------------------------------------------------- upgrade arrow: gear that beats what is worn in its slot (item level), if the character can use it
-- equip location -> the inventory slots it competes with (a ring or trinket must beat the weaker one)
IL.TARGET = { INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_HOLDABLE = { 17 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 } }
-- best armor type per class (1 cloth, 2 leather, 3 mail, 4 plate) and the level mail / plate comes at; weapon words per class (matched in the English sub type)
IL.ARMOR = { WARRIOR = { 4, 3, 40 }, PALADIN = { 4, 3, 40 }, HUNTER = { 3, 2, 40 }, SHAMAN = { 3, 2, 40 }, ROGUE = { 2 }, DRUID = { 2 }, PRIEST = { 1 }, MAGE = { 1 }, WARLOCK = { 1 } }
IL.WEAPONS = { WARRIOR = "axe mace sword dagger fist polearm staff bow crossbow gun thrown shield", PALADIN = "axe mace sword polearm shield",
  HUNTER = "axe sword dagger fist polearm staff bow crossbow gun thrown", ROGUE = "dagger fist mace sword axe bow crossbow gun thrown",
  PRIEST = "mace dagger staff wand", SHAMAN = "axe mace dagger fist staff shield", MAGE = "sword dagger staff wand", WARLOCK = "sword dagger staff wand",
  DRUID = "mace dagger fist polearm staff" }
local ARMOR_RANK = { cloth = 1, leather = 2, mail = 3, plate = 4 }
local RELIC = { idol = "DRUID", libram = "PALADIN", totem = "SHAMAN" } -- a relic is for one class only
local DUAL_WIELD = { WARRIOR = 1, ROGUE = 1, HUNTER = 1, SHAMAN = 40 } -- class -> level it dual wields at

local function dualWields()
  local cls = _G.UnitClass and select(2, UnitClass("player"))
  local at = cls and DUAL_WIELD[cls]
  if not at then return false end
  local level = _G.UnitLevel and UnitLevel("player")
  return not (level and level < at)
end

-- Can this character wear / wield it now? A type this table does not know (another language, rings) counts as usable.
function IL.CanUse(minLevel, class, sub, loc)
  local level = _G.UnitLevel and UnitLevel("player") or nil
  if type(minLevel) == "number" and level and minLevel > level then return false end
  local cls = _G.UnitClass and select(2, UnitClass("player"))
  if not cls or not sub or sub == "" then return true end
  sub = string.gsub(string.lower(sub), "staves", "staff")
  if loc == "INVTYPE_RELIC" then
    for word, c in pairs(RELIC) do if string.find(sub, word, 1, true) then return c == cls end end
    return true
  end
  if loc == "INVTYPE_WEAPONOFFHAND" and not dualWields() then return false end
  local rank = ARMOR_RANK[sub]
  if rank and loc ~= "INVTYPE_CLOAK" then
    local a = IL.ARMOR[cls]
    local max = a and ((a[3] and level and level < a[3]) and a[2] or a[1])
    return not max or rank <= max
  end
  local words = IL.WEAPONS[cls]
  if not words or (class == "Armor" and not string.find(sub, "shield", 1, true)) then return true end
  if loc == "INVTYPE_2HWEAPON" and (cls == "ROGUE" or ((cls == "PRIEST" or cls == "MAGE" or cls == "WARLOCK") and not string.find(sub, "staff", 1, true))) then return false end
  for w in string.gmatch(words, "%a+") do
    if string.find(sub, w, 1, true) and not (w == "bow" and string.find(sub, "crossbow", 1, true)) then return true end
  end
  return false
end

local worn -- slot -> item level of what is equipped (0 empty), read once after every equipment change
local wornLoc
local missing = {} -- itemID -> true: an item the client had not sent data for yet (GetItemInfo nil); GET_ITEM_INFO_RECEIVED redraws for it
local function itemKnown(link)
  if not link or GetItemInfo(link) then return true end
  local id = tonumber(string.match(link, "item:(%d+)"))
  if id then missing[id] = true end
  return false
end
IL.Known = itemKnown
-- false (nothing cached) while a worn item is still unknown: it would read as level 0 and every bag item would look like an upgrade
local function readWorn()
  if not _G.GetInventoryItemLink then worn, wornLoc = {}, {}; return true end
  local w, l = {}, {}
  for slot = 1, 18 do
    local link = GetInventoryItemLink("player", slot)
    if not itemKnown(link) then return false end
    local ilvl, _, loc = IL.Info(link)
    w[slot], l[slot] = ilvl or 0, loc
  end
  worn, wornLoc = w, l
  return true
end
function IL.ResetWorn() worn = nil end

-- Rule (simple on purpose): gear this character can use right now (level, armor type, weapon skill, relic class, dual wield, no red line in its
-- tooltip) whose item level is higher than the lowest item worn in the slots it competes for. An empty slot counts 0 (a first piece is an upgrade);
-- a ring / trinket is compared with the weaker one; a shield / off-hand is never one under a two-hander; a one-hander only meets the off-hand when
-- the class dual wields and that holds a weapon. Item data not known yet (bag item or worn item) shows no arrow.
function IL.Upgrade(link)
  local ilvl, _, loc = IL.Info(link)
  local slots = ilvl and IL.TARGET[loc]
  if not slots then itemKnown(link); return false end
  local _, _, _, _, minLevel, class, sub = GetItemInfo(link)
  if not IL.CanUse(minLevel, class, sub, loc) or Bags.Unusable(link) then return false end
  if not worn and not readWorn() then return false end
  local low
  for _, s in ipairs(slots) do
    local v = worn[s]
    if s == 17 and loc == "INVTYPE_WEAPON" and (not dualWields() or (wornLoc[17] ~= "INVTYPE_WEAPON" and wornLoc[17] ~= "INVTYPE_WEAPONOFFHAND")) then v = nil end -- no off-hand weapon to replace: only the main hand counts
    if s == 17 and loc ~= "INVTYPE_WEAPON" and wornLoc[16] == "INVTYPE_2HWEAPON" then return false end
    if v and (not low or v < low) then low = v end
  end
  return low ~= nil and ilvl > low
end
-- What changes the answer: worn gear, level, item data arriving. The open bags are drawn again.
local function redraw() IL.ResetWorn(); if Bags.state then Bags.UpdateAll() end end
AFUI.On("PLAYER_EQUIPMENT_CHANGED", redraw)
AFUI.On("UNIT_INVENTORY_CHANGED", function(_, unit) if unit == "player" then IL.ResetWorn() end end)
AFUI.On("PLAYER_LEVEL_UP", function() Bags.ClearUnusable(); redraw() end)
AFUI.On("GET_ITEM_INFO_RECEIVED", function(_, id)
  if id then
    if not missing[id] then return end
    missing[id] = nil
  else missing = {} end
  redraw()
end)

local function levelText(parent, point, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  local font = fs:GetFont()
  if font then fs:SetFont(font, 10, "OUTLINE") end
  fs:SetPoint(point, parent, point, x, y)
  return fs
end

-- Shows or hides the small coloured number on a slot button. where: "bag" (bottom left) or "char" (bottom centre).
function IL.Set(btn, link, where, enabled)
  local ilvl, quality
  if enabled then ilvl, quality = IL.Info(link) end
  local fs = btn.afItemLevel
  if not ilvl then if fs then fs:Hide() end; return end
  if not fs then
    fs = where == "char" and levelText(btn, "BOTTOM", 0, 2) or levelText(btn, "BOTTOMLEFT", 3, 2)
    btn.afItemLevel = fs
  end
  fs:SetText(ilvl); fs:SetTextColor(IL.Color(quality)); fs:Show()
end

function IL.UpdateSlot(btn)
  local id = btn and btn.GetID and btn:GetID()
  if not (id and IL.CHAR[id] and btn:GetName() == IL.CHAR[id]) then return end
  IL.Set(btn, _G.GetInventoryItemLink and GetInventoryItemLink("player", id), "char", on("charItemLevel"))
end

function IL.UpdateCharacter()
  for id, name in pairs(IL.CHAR) do
    local b = _G[name]
    if b then IL.UpdateSlot(b) end
  end
end

---------------------------------------------------------------- new items (TBC has no C_NewItems: our own set from BAG_UPDATE diffs)
-- An item is new when the total of its itemID in the bags went UP since the last look and it sits in a slot that did not hold it (or whose stack
-- grew). Moves, splits, merges, swaps and a sort keep the totals, so they never glow. A flagged slot stays flagged until it is moused over, its
-- window closes, or its item leaves it. Slot keys are "bag:slot"; the bank counts only while it is open.
local New = {}
Bags.New = New
New.flagged, New.prev, New.quietUntil = {}, nil, 0

function New.Key(bag, slot) return bag .. ":" .. slot end

-- snapshot = { slots = { key = { id, count } }, totals = { id = n }, bank = bool }
function New.Diff(prev, cur)
  local out = {}
  if not prev or prev.bank ~= cur.bank then return out end
  for key, c in pairs(cur.slots) do
    local p = prev.slots[key]
    if (cur.totals[c.id] or 0) > (prev.totals[c.id] or 0) and (not p or p.id ~= c.id or c.count > p.count) then out[#out + 1] = key end
  end
  table.sort(out)
  return out
end

function New.Read(bank)
  local s = { slots = {}, totals = {}, bank = bank and true or false }
  local bags = { 0, 1, 2, 3, 4 }
  if bank then bags[#bags + 1] = -1; for id = MAX_BAG + 1, MAX_BAG + (_G.NUM_BANKBAGSLOTS or 7) do bags[#bags + 1] = id end end
  for _, bag in ipairs(bags) do
    for slot = 1, numSlots(bag) do
      local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
      if link then
        local id = link:match("item:(%d+)") or link
        local _, count = GetContainerItemInfo(bag, slot)
        count = count or 1
        s.slots[New.Key(bag, slot)] = { id = id, count = count }
        s.totals[id] = (s.totals[id] or 0) + count
      end
    end
  end
  return s
end

function New.Scan(bank)
  if _G.CursorHasItem and CursorHasItem() then return end -- an item in the hand: the bags are in flux
  local cur = New.Read(bank)
  local fresh = {}
  if GetTime() >= New.quietUntil then for _, key in ipairs(New.Diff(New.prev, cur)) do fresh[key] = true end end
  for key in pairs(New.flagged) do -- the item left the slot (or another one took its place): no longer new there
    local c, p = cur.slots[key], New.prev and New.prev.slots[key]
    if not c or (p and p.id ~= c.id) then New.flagged[key] = nil end
  end
  for key in pairs(fresh) do New.flagged[key] = true end
  New.prev = cur
end

function New.Is(bag, slot) return New.flagged[New.Key(bag, slot)] == true end
function New.Clear(bag, slot) New.flagged[New.Key(bag, slot)] = nil end
function New.ClearBag(bag)
  local prefix = bag .. ":"
  for key in pairs(New.flagged) do if key:sub(1, #prefix) == prefix then New.flagged[key] = nil end end
end

-- The glow colour of Forever's slot (bags-glow-<quality>): poor / common white, then green, blue, purple, orange, artifact, heirloom.
local GLOW = { [0] = "bags-glow-white", "bags-glow-white", "bags-glow-green", "bags-glow-blue", "bags-glow-purple", "bags-glow-orange", "bags-glow-artifact", "bags-glow-heirloom" }
function Bags.GlowAtlas(quality) return GLOW[quality or 1] or "bags-glow-white" end

-- A looping alpha pulse (an AnimationGroup on the glow texture); the group is made once.
function Bags.PulseGlow(tex)
  if tex.afPulse == nil then
    tex.afPulse = false
    local g = tex.CreateAnimationGroup and tex:CreateAnimationGroup()
    if g then
      local a = g:CreateAnimation("Alpha")
      if a then
        if a.SetFromAlpha then a:SetFromAlpha(1); a:SetToAlpha(0.25) elseif a.SetChange then a:SetChange(-0.75) end
        a:SetDuration(0.8)
        if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
        g:SetLooping("BOUNCE")
        tex.afPulse = g
      end
    end
  end
  return tex.afPulse or nil
end

-- Shows the glow on a slot button (any window: bags, combined, bank): the item is flagged new and the setting is on.
function Bags.ApplyGlow(b, bag, slot, quality, hasItem)
  local show = hasItem and on("bagNewGlow") and (New.Is(bag, slot) or (C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot))) and true or false
  local g = b.newGlow
  if not g then return show end
  if show then
    AFUI.SetAtlas(g, Bags.GlowAtlas(quality)); g:Show()
    local p = Bags.PulseGlow(g)
    if p and not (p.IsPlaying and p:IsPlaying()) then p:Play() end
  else
    local p = g.afPulse
    if p and p.Stop then p:Stop() end
    g:Hide()
  end
  return show
end

-- Moused over = seen: the flag goes and the glow with it.
function Bags.HookSeen(b, bag, slot)
  if b.afSeenHooked or not b.HookScript then return end
  b.afSeenHooked = true
  b:HookScript("OnEnter", function(self)
    if New.Is(bag, slot) then New.Clear(bag, slot); Bags.ApplyGlow(self, bag, slot, nil, false) end
  end)
end

-- Alt-click marks an item "Don't sell" (or clears the mark). Alt is a modified click in the client, so the click picks nothing up; if the client did lift the item
-- anyway, it goes back. A line in the item tooltip says what the mark does. Hooks only: the client's own click and tooltip run untouched.
function Bags.HookDontSell(b)
  if b.afSellHooked or not b.HookScript then return end
  b.afSellHooked = true
  local function hint(self)
    if not on("bagDontSell") or not _G.GameTooltip then return end
    local link = GetContainerItemLink(self.bag, self.slot)
    if not link then return end
    if NoSell.Is(link) then GameTooltip:AddLine("Marked: never sold to a vendor. Alt-click to undo.", 0.9, 0.7, 0.2)
    elseif MerchantFrame and MerchantFrame:IsShown() then GameTooltip:AddLine("Alt-click: never sell this item.", 0.55, 0.55, 0.55) end
    GameTooltip:Show()
  end
  b:HookScript("PreClick", function(self) self.afHeld = _G.CursorHasItem and CursorHasItem() or false end)
  b:HookScript("OnClick", function(self, button)
    if button ~= "LeftButton" or not (_G.IsAltKeyDown and IsAltKeyDown()) or not on("bagDontSell") then return end
    local link = GetContainerItemLink(self.bag, self.slot)
    if not link then return end
    NoSell.Toggle(link)
    if not self.afHeld and _G.CursorHasItem and CursorHasItem() and not InCombatLockdown() and _G.ClearCursor then ClearCursor() end
    Bags.UpdateAll()
    local enter = GameTooltip.IsOwned and GameTooltip:IsOwned(self) and self:GetScript("OnEnter")
    if enter then enter(self); hint(self) end -- the tooltip shows the new state
  end)
  b:HookScript("OnEnter", hint)
end

local function atlasTexture(parent, layer, name, w, h, crop, vertical)
  local t = parent:CreateTexture(nil, layer)
  AFUI.SetAtlas(t, name)
  local e = AFUI_ATLAS and AFUI_ATLAS[string.lower(name)]
  if e and crop and crop < 1 then
    if vertical then t:SetTexCoord(e[4], e[5], e[6], e[6] + (e[7] - e[6]) * crop)
    else t:SetTexCoord(e[4], e[4] + (e[5] - e[4]) * crop, e[6], e[7]) end
  end
  if w then t:SetWidth(w); t:SetHeight(h) elseif e then t:SetWidth(e[2]); t:SetHeight(e[3]) end -- an unsized texture would draw as the whole atlas page
  return t
end

-- Forever's windowed Metal frame (docs/forever-ref/worldmap.md section 2): the world map's pieces with the portrait corner.
function AFUI.BagFramePieces(w, h, portrait) return AFUI.WorldMapPieces(w, h, portrait ~= false) end
local VERTICAL = { ["!ui-frame-metal-edgeleft-c60-2x"] = true, ["!ui-frame-metal-edgeright-c60-2x"] = true }

local function bagIcon(bag)
  if bag == 0 or bag == "combined" then return "Interface\\AddOns\\AztraForeverUI\\Media\\chat\\ui-hud-actionbar-bag" end
  if bag == KEYRING then return nil end
  return GetInventoryItemTexture and GetInventoryItemTexture("player", ContainerIDToInventoryID(bag)) or nil
end

local function bagTitle(key)
  if key == "combined" then return (UnitName("player") or "") .. "'s Inventory" end -- the video: "Azzi Darkwraith's Inventory"
  if key == KEYRING then return KEYRING_LABEL or "Keyring" end
  if key == 0 then return BACKPACK_TOOLTIP or "Backpack" end
  return GetBagName(key) or ("Bag " .. key)
end

local function holder(bag)
  local h = holders[bag]
  if not h then
    h = CreateFrame("Frame", "AFUI_BagHolder" .. (bag + 2), UIParent)
    h:SetID(bag)
    holders[bag] = h
    buttons[bag] = {}
  end
  return h
end

-- item info through the one global both TBC clients have (C_Container only as a guard for a later client)
local function itemInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo and not GetContainerItemInfo then
    local i = C_Container.GetContainerItemInfo(bag, slot)
    if i then return i.iconFileID, i.stackCount, i.isLocked, i.quality, i.isReadable end
    return
  end
  local tex, count, locked, quality, readable = GetContainerItemInfo(bag, slot)
  return tex, count, locked, quality, readable
end

local function qualityColor(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

---------------------------------------------------------------- junk grey-out and red unusable items
-- "Can't use" = a red line in the item's tooltip (required level, class, proficiency, armor type, skill), read once per link from a hidden tooltip.
-- Only a tooltip that has text is cached; an item the client has not sent yet is asked again when GET_ITEM_INFO_RECEIVED redraws. A level up or a
-- learned skill drops the cache. Lines: { r, g, b, text } for the left and right text of every line after the item name.
local scanTip
function Bags.ScanLines(link)
  if not (_G.CreateFrame and _G.UIParent) then return nil end
  if not scanTip then scanTip = CreateFrame("GameTooltip", "AFUI_BagScan", nil, "GameTooltipTemplate") end
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:ClearLines()
  scanTip:SetHyperlink(link)
  local n = scanTip:NumLines()
  if not n or n < 1 then return nil end
  local out = {}
  for i = 2, n do
    for _, side in ipairs({ "Left", "Right" }) do
      local fs = _G["AFUI_BagScanText" .. side .. i]
      local text = fs and fs:GetText()
      if text and text ~= "" then
        local r, g, b = fs:GetTextColor()
        out[#out + 1] = { r, g, b, text }
      end
    end
  end
  return out
end

local unusable = {}
function Bags.ClearUnusable() unusable = {} end
function Bags.Unusable(link)
  if not link then return false end
  local v = unusable[link]
  if v ~= nil then return v end
  local lines = Bags.ScanLines(link)
  if not lines then
    local id = tonumber(string.match(link, "item:(%d+)"))
    if id then missing[id] = true end -- the tooltip had nothing yet: ask again when the item data arrives
    return false
  end
  v = false
  for _, c in ipairs(lines) do
    if c[1] > 0.9 and c[2] < 0.2 and c[3] < 0.2 and not (_G.ITEM_SPELL_KNOWN and c[4] == _G.ITEM_SPELL_KNOWN) then v = true; break end -- "Already known" is red too but is not "can't use"
  end
  unusable[link] = v
  return v
end
AFUI.On("SKILL_LINES_CHANGED", Bags.ClearUnusable)

-- The icon of a slot: grey junk (a vendor pays for it) is desaturated and dimmed, unusable items turn red. Returns true for junk (the coin shows).
-- merchant: the vendor window's own slots take the red tint only.
local MERCHANT_BAG = -5 -- MerchantFrame.lua M.CONTAINER
function Bags.Tint(b, bag, link, quality, locked)
  local icon = b.icon
  if not icon then return false end
  local junk, red = false, false
  if link then
    itemKnown(link)
    local price = select(11, GetItemInfo(link))
    junk = bag ~= MERCHANT_BAG and on("bagGrayJunk") and quality == 0 and type(price) == "number" and price > 0 or false
    red = on("bagRedUnusable") and Bags.Unusable(link) or false
  end
  icon:SetDesaturated((locked or junk) and true or false)
  if red then icon:SetVertexColor(1, 0.1, 0.1) elseif junk then icon:SetVertexColor(0.7, 0.7, 0.7) else icon:SetVertexColor(1, 1, 1) end
  return junk
end

-- The small marks on a slot: the quest item border (and the "!" of an item that starts a quest), the green upgrade arrow, the Don't sell lock. Textures are made
-- the first time a slot needs one. Returns true when the item carries a Don't sell mark.
local QUEST_ART = "Interface\\ContainerFrame\\UI-Icon-QuestBorder"
local function mark(b, key, show, make)
  local t = b[key]
  if show and not t then t = make(b); b[key] = t end
  if t then setShown(t, show) end
end
function Bags.Marks(b, bag, slot, link)
  local quest, bang, up, locked = false, false, false, false
  if link then
    if on("bagQuestMarker") then
      local class = (not _G.GetContainerItemQuestInfo or bag < -1) and select(6, GetItemInfo(link)) or nil
      quest, bang = Bags.QuestInfo(bag, slot, class)
    end
    if on("bagUpgradeArrow") then up = IL.Upgrade(link) end
    locked = NoSell.Is(link)
  end
  mark(b, "questBorder", quest, function(f)
    local t = f:CreateTexture(nil, "OVERLAY"); t:SetTexture(QUEST_ART); t:SetAllPoints(f); return t
  end)
  mark(b, "questBang", bang, function(f)
    local t = f:CreateTexture(nil, "OVERLAY"); t:SetTexture("Interface\\ContainerFrame\\UI-Icon-QuestBang")
    t:SetWidth(12); t:SetHeight(14); t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2); return t
  end)
  mark(b, "upgrade", up, function(f)
    local t = atlasTexture(f, "OVERLAY", "bags-greenarrow", 14, 15); t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1); return t
  end)
  mark(b, "lock", locked, function(f)
    local t = f:CreateTexture(nil, "OVERLAY"); t:SetTexture("Interface\\Buttons\\LockButton-Locked-Up")
    t:SetWidth(13); t:SetHeight(13); t:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1); return t
  end)
  return locked
end

-- Category of every slot of a combined list ({ bag, slot } in reading order): false for an empty slot or one inside a specialty bag.
function Bags.SlotCategories(list)
  local out, fam = {}, {}
  for i, e in ipairs(list) do
    local bag, slot = e[1], e[2]
    if fam[bag] == nil then fam[bag] = Bags.BagType(bag) end
    local link = fam[bag] == 0 and GetContainerItemLink(bag, slot)
    if link then
      local class = select(6, GetItemInfo(link))
      out[i] = Bags.Category(class, Bags.QuestInfo(bag, slot, class))
    else out[i] = false end
  end
  return out
end

-- The gold labels of "Group items by category": a label and a thin line in the strip above the row where each group starts (strips are BagLayout.LABEL_H high).
function Bags.DrawCategoryLabels(win, marks, x0, y0, gridW)
  local pool = win.catLabels
  if not pool then pool = {}; win.catLabels = pool end
  local pitch = ITEM + gap("combined")
  for i, m in ipairs(marks) do
    local l = pool[i]
    if not l then
      l = { text = win.tf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), line = win.tf:CreateTexture(nil, "OVERLAY") }
      AFUI.SetColor(l.line, 0.75, 0.62, 0.35, 0.45); l.line:SetHeight(1)
      pool[i] = l
    end
    local x = x0 + m.col * pitch
    local top = y0 + m.row * pitch + BagLayout.StripsThrough(marks, m.row - 1) * BagLayout.LABEL_H -- the strip sits above the row, under any earlier strips
    l.text:SetText(Bags.CATEGORY_LABELS[m.cat])
    local tw = l.text.GetStringWidth and l.text:GetStringWidth() or 0
    if tw == 0 then tw = #Bags.CATEGORY_LABELS[m.cat] * 6 end
    l.text:ClearAllPoints(); l.text:SetPoint("TOPLEFT", win, "TOPLEFT", math.max(math.min(x, x0 + gridW - tw), x0), -(top + 1)); l.text:Show() -- a label that starts in the last columns pulls back to fit
    l.line:ClearAllPoints(); l.line:SetPoint("TOPLEFT", win, "TOPLEFT", x, -(top + BagLayout.LABEL_H - 3)); l.line:SetWidth(math.max(x0 + gridW - x, 1)); l.line:Show()
  end
  for i = #marks + 1, #pool do pool[i].text:Hide(); pool[i].line:Hide() end
end

-- "No results" in the middle of the combined grid when a search matches no item (a dim line, not a banner).
function Bags.UpdateResults()
  local win = windows.combined
  if not (win and win.noResults) then return end
  local any = false
  if Bags.searchText ~= "" then
    for bag = 0, MAX_BAG do
      for _, b in pairs(buttons[bag] or {}) do
        if b:IsShown() and b.hasItem and b.matched then any = true; break end
      end
      if any then break end
    end
  end
  setShown(win.noResults, Bags.searchText ~= "" and not any)
end

function Bags.UpdateButton(b)
  local bag, slot = b.bag, b.slot
  local tex, count, locked, quality, readable = itemInfo(bag, slot)
  b.locked, b.readable = locked, readable -- the template's own OnEnter / OnClick read these (2.4.3 ContainerFrame.lua:268, 2.5.3 :631)
  local icon = b.icon
  if tex then
    icon:SetTexture(tex); icon:Show()
  else
    icon:Hide()
  end
  AFUI.SetAtlas(b.bg, Bags.EmptyArt())
  SetItemButtonCount(b, tex and count or 0)
  if tex and quality and quality > 1 then
    b.quality:SetVertexColor(qualityColor(quality)); b.quality:Show()
  else
    b.quality:Hide()
  end
  local link = tex and GetContainerItemLink(bag, slot)
  Bags.ApplyGlow(b, bag, slot, quality, tex and true or false)
  IL.Set(b, link, "bag", on("bagItemLevel"))
  local marked = Bags.Marks(b, bag, slot, link)
  local junk = Bags.Tint(b, bag, link, quality, locked)
  -- the coin: any grey item a vendor pays for; with the option off, as before, grey items while a vendor is open
  setShown(b.junk, tex and not marked and (junk or (not on("bagGrayJunk") and quality == 0 and MerchantFrame and MerchantFrame:IsShown())) and true or false)
  local cd = _G[b:GetName() .. "Cooldown"]
  if cd then
    if tex then
      local start, duration, enable = GetContainerItemCooldown(bag, slot)
      AFUI.CooldownSet(cd, start or 0, (enable == 1) and duration or 0)
    else
      AFUI.CooldownSet(cd, 0, 0)
    end
  end
  b.hasItem = tex and 1 or nil
  local name = link and GetItemInfo(link)
  local text = Bags.searchText
  b.matched = AFUI.BagSearch.Matches(name, text, text ~= "" and link and Bags.SearchExtra(link) or nil)
  b:SetAlpha(b.matched and 1 or 0.25) -- non-matches dim (TBC has no bag search API)
end

local function newButton(bag, slot)
  local h = holder(bag)
  local name = "AFUI_BagItem" .. (bag + 2) .. "_" .. slot
  local b = CreateFrame("Button", name, h, "ContainerFrameItemButtonTemplate")
  b:SetID(slot); b:SetWidth(ITEM); b:SetHeight(ITEM)
  b.bag, b.slot = bag, slot
  b:SetNormalTexture("") -- the old Quickslot frame
  -- 2.5.3's template draws these glows shown; Blizzard hides them in ContainerFrame_Update (ContainerFrame.lua:579-582), which Forever replaces
  for _, k in ipairs({ "BattlepayItemTexture", "NewItemTexture" }) do if rawget(b, k) then b[k]:Hide() end end
  b.icon = _G[name .. "IconTexture"]
  b.icon:ClearAllPoints(); b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(b)
  b.quality = b:CreateTexture(nil, "OVERLAY"); b.quality:SetTexture(PLAIN .. "WhiteIconFrame"); b.quality:SetAllPoints(b); b.quality:Hide()
  b.newGlow = atlasTexture(b, "OVERLAY", "bags-glow-green", 39, 39); b.newGlow:SetPoint("CENTER"); b.newGlow:SetBlendMode("ADD"); b.newGlow:Hide()
  Bags.HookSeen(b, bag, slot)
  Bags.HookDontSell(b)
  b.indicator =atlasTexture(b, "OVERLAY", "bags-glow-white", 39, 39); b.indicator:SetPoint("CENTER"); b.indicator:SetBlendMode("ADD"); b.indicator:Hide()
  b.junk = atlasTexture(b, "OVERLAY", "bags-junkcoin"); b.junk:SetPoint("TOPLEFT", b, "TOPLEFT", 1, 0); b.junk:Hide()
  buttons[bag][slot] = b
  return b
end

local function button(bag, slot) return buttons[bag] and buttons[bag][slot] or newButton(bag, slot) end
-- For the bank window (Bank.lua): its bank bag slots (ids 5..11) are the same buttons as the bags' own, parented to the bank frame there.
Bags.Holder, Bags.Button = holder, button
function Bags.BagButtons(bag) return buttons[bag] or {} end

local function windowKind(key)
  if key == "combined" then return "combined" end
  if key == 0 then return "backpack" end
  if key == KEYRING then return "keyring" end
  return "bag"
end

local function slotList(key)
  if key == "combined" then return BagLayout.CombinedOrder(sizes()) end
  local out = {}
  for slot = 1, numSlots(key) do out[slot] = { key, slot } end
  return out
end

-- frame art for the window's size (pieces are pooled textures)
local function skin(win, w, h, portrait)
  if portrait == nil then portrait = win.key ~= "combined" end
  if win.skinW == w and win.skinH == h and win.skinP == portrait then return end
  win.skinW, win.skinH, win.skinP = w, h, portrait
  local pcs = AFUI.BagFramePieces(w, h, portrait) -- "<Name>'s Inventory" has no portrait ring (video)
  for i, p in ipairs(pcs) do
    local t = win.pieces[i]
    if not t then t = win:CreateTexture(nil, "OVERLAY"); win.pieces[i] = t end
    AFUI.SetAtlas(t, p.atlas)
    local e = AFUI_ATLAS and AFUI_ATLAS[string.lower(p.atlas)]
    if e then
      if p.crop and p.crop < 1 then
        if VERTICAL[p.atlas] then t:SetTexCoord(e[4], e[5], e[6], e[6] + (e[7] - e[6]) * p.crop)
        else t:SetTexCoord(e[4], e[4] + (e[5] - e[4]) * p.crop, e[6], e[7]) end
      end
    end
    t:SetWidth(p.w); t:SetHeight(p.h)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", win, "TOPLEFT", p.x, p.y)
    t:Show()
  end
  for i = #pcs + 1, #win.pieces do win.pieces[i]:Hide() end
end

-- The bag windows' chrome on any frame (the bank): the Rock fill, the grey footer strip under the money, and the metal frame pieces for a w x h window.
function Bags.Chrome(win, w, h, portrait)
  win.pieces = win.pieces or {}
  if not win.rock then
    local bg = win:CreateTexture(nil, "BACKGROUND"); bg:SetTexture(PLAIN .. "UI-Background-Rock"); bg:SetVertexColor(ROCK_TINT[1], ROCK_TINT[2], ROCK_TINT[3])
    bg:SetPoint("TOPLEFT", win, "TOPLEFT", 2, -21); bg:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -2, 2)
    win.rock = bg
    local foot = win:CreateTexture(nil, "BORDER"); AFUI.SetColor(foot, 0.1, 0.1, 0.11, 0.55)
    foot:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 3, 3); foot:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -3, 3); foot:SetHeight(30)
    win.footer = foot
  end
  skin(win, w, h, portrait)
  win.rock:SetTexCoord(0, (w - 4) / 512, 0, (h - 23) / 512)
end

-- One slot button of Forever's look (the bag windows and the bank share it): the client's frame art out, the wing slot behind, the icon inset, the
-- quality border, the new-item glow, the item level and the junk coin hooks.
function Bags.SkinSlot(b, size, bag, slot)
  b:SetNormalTexture("")
  local name = b:GetName()
  if size then b:SetWidth(size); b:SetHeight(size) end
  b.icon = b.icon or (name and _G[name .. "IconTexture"])
  if b.icon then
    b.icon:ClearAllPoints(); b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end
  if not b.bg then
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(b)
    b.quality = b:CreateTexture(nil, "OVERLAY"); b.quality:SetTexture(PLAIN .. "WhiteIconFrame"); b.quality:SetAllPoints(b); b.quality:Hide()
    b.newGlow = atlasTexture(b, "OVERLAY", "bags-glow-green", 39, 39); b.newGlow:SetPoint("CENTER"); b.newGlow:SetBlendMode("ADD"); b.newGlow:Hide()
  end
  AFUI.SetAtlas(b.bg, Bags.EmptyArt())
  Bags.HookSeen(b, bag, slot)
end

-- Quality border, glow and item level of a skinned slot for what it holds now (link nil = empty).
function Bags.PaintSlot(b, bag, slot, link, quality, hasItem)
  if hasItem and quality and quality > 1 then b.quality:SetVertexColor(qualityColor(quality)); b.quality:Show() else b.quality:Hide() end
  Bags.ApplyGlow(b, bag, slot, quality, hasItem)
  IL.Set(b, link, "bag", on("bagItemLevel"))
  local marked = Bags.Marks(b, bag, slot, hasItem and link or nil)
  local junk = Bags.Tint(b, bag, hasItem and link or nil, quality, false)
  mark(b, "junk", hasItem and junk and not marked, function(f)
    local t = atlasTexture(f, "OVERLAY", "bags-junkcoin"); t:SetPoint("TOPLEFT", f, "TOPLEFT", 1, 0); return t
  end)
end

-- Tooltip of the footer counter: the total, then the free slots of every bag type the character carries.
function Bags.FreeTooltip(owner)
  local info = Bags.Info()
  local free, total, used = Bags.Totals(info)
  GameTooltip:SetOwner(owner, "ANCHOR_TOP")
  GameTooltip:SetText(used .. "/" .. total .. " slots used", 1, 1, 1)
  GameTooltip:AddLine(free .. " free", 0.8, 0.8, 0.8)
  local rows = Bags.FreeByType(info)
  if #rows > 1 then
    for _, r in ipairs(rows) do GameTooltip:AddDoubleLine(r.name .. " slots free", r.free .. "/" .. r.total, 1, 1, 1, 1, 0.82, 0) end
  end
  GameTooltip:Show()
end

-- Footer centre of the combined window (video): the bag icon and "used/total" slots.
local function setCount(win, list)
  local used = 0
  for _, e in ipairs(list) do if GetContainerItemInfo(e[1], e[2]) then used = used + 1 end end
  win.count:SetText(used .. "/" .. #list)
end

local function setMoney(win)
  local g, s, c = AFUI.BagMoney(GetMoney())
  win.money.gold:SetText(g); win.money.silver:SetText(s); win.money.copper:SetText(c)
end

local function layout(key)
  local win = windows[key]
  local kind = windowKind(key)
  local list = slotList(key)
  local total = #list
  local cols = COLS[kind]
  local keyN = key == "combined" and keySlots() or 0
  local marks, labelH = {}, 0
  if key == "combined" and on("bagGroupCategory") then marks, labelH = BagLayout.GroupMarks(Bags.SlotCategories(list), total, cols) end
  local w, h = BagLayout.WindowSize(kind, total, keyN, labelH)
  local scale = BagLayout.FitScale(h, UIParent:GetHeight())
  win.scale = scale
  win:SetScale(scale); win:SetWidth(w); win:SetHeight(h)
  skin(win, w, h)
  win.rock:SetTexCoord(0, (w - 4) / 512, 0, (h - 23) / 512)
  win.title:SetWidth(w - 122); win.title:SetHeight(12); win.title:SetText(bagTitle(key))
  local pic = bagIcon(key)
  if pic then win.portrait:SetTexture(pic); win.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  else AFUI.SetAtlas(win.portrait, "ui-hud-actionbar-keyring-small-c60") end
  local extra = (kind == "backpack" or kind == "combined")
  setShown(win.portrait, key ~= "combined")
  setShown(win.search, kind == "combined") -- the search bar belongs to the combined window only (Mat)
  setShown(win.money, extra); setShown(win.footer, extra); setShown(win.count, key == "combined"); setShown(win.countIcon, key == "combined")
  setShown(win.countHit, key == "combined")
  if key == "combined" then setCount(win, list) end
  local gridW = cols * ITEM + (cols - 1) * gap(kind)
  local x0 = w - 7 - gridW
  local rows = BagLayout.Rows(total, cols)
  local y0 = h - (kind == "backpack" and 52 or extra and 29 or 9) - BagLayout.KeySection(keyN) - labelH - (rows * ITEM + math.max(rows - 1, 0) * gap(kind))
  -- every holder of this window follows it; buttons past the bag's size hide
  local bagsHere = (key == "combined") and { 0, 1, 2, 3, 4, KEYRING } or { key }
  for _, bag in ipairs(bagsHere) do
    local hd = holder(bag)
    hd:SetParent(win); hd:ClearAllPoints(); hd:SetAllPoints(win); hd:SetFrameLevel(win:GetFrameLevel() + 2)
    local n = bag == KEYRING and key == "combined" and keyN or numSlots(bag)
    for slot, b in pairs(buttons[bag]) do if slot > n then b:Hide() end end
  end
  if key == "combined" then
    local top = y0 + labelH + rows * ITEM + math.max(rows - 1, 0) * gap(kind) -- the main grid's bottom edge
    setShown(win.keySep, keyN > 0); setShown(win.keyLabel, keyN > 0)
    if keyN > 0 then
      win.keySep:ClearAllPoints(); win.keySep:SetPoint("TOPLEFT", win, "TOPLEFT", x0, -(top + 5)); win.keySep:SetWidth(gridW)
      win.keyLabel:ClearAllPoints(); win.keyLabel:SetPoint("TOPLEFT", win, "TOPLEFT", x0, -(top + 7))
      for slot = 1, keyN do
        local b = button(KEYRING, slot)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", win, "TOPLEFT", x0 + ((slot - 1) % cols) * (ITEM + gap(kind)), -(top + KEY_HEAD + math.floor((slot - 1) / cols) * (ITEM + gap(kind))))
        b:Show()
        Bags.UpdateButton(b)
      end
    end
    setShown(win.keyBtn, numSlots(KEYRING) > 0)
    win.keyBtn.Refresh()
  end
  for i, e in ipairs(list) do
    local b = button(e[1], e[2])
    local c, r = BagLayout.Cell(i - 1, total, cols)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", win, "TOPLEFT", x0 + c * (ITEM + gap(kind)), -(y0 + r * (ITEM + gap(kind)) + BagLayout.StripsThrough(marks, r) * BagLayout.LABEL_H))
    b:Show()
    Bags.UpdateButton(b)
  end
  if key == "combined" then
    Bags.DrawCategoryLabels(win, marks, x0, y0, gridW)
    Bags.UpdateResults()
  end
  if kind == "combined" then -- no portrait and the sort button sits in the footer: the box spans the window
    win.search:SetWidth(w - 18 - 12); win.search:ClearAllPoints()
    win.search:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -33)
  end
  setShown(win.sort, kind == "backpack" or kind == "combined"); setShown(win.currency, kind == "backpack")
  win.sort:ClearAllPoints()
  if kind == "combined" then win.sort:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 9, 5) else win.sort:SetPoint("TOPRIGHT", win, "TOPRIGHT", -9, -30) end
  win.money:ClearAllPoints()
  win.money:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -9, kind == "backpack" and 32 or 9)
  if extra then setMoney(win) end
  if kind == "backpack" then Bags.SetCurrency(win) end
  win.toggle.Refresh()
  return w * scale, h * scale
end

-- Stacks the windows of `keys` (dims = their scaled sizes) from the bottom right; hiddenOnly leaves a window that is showing where it is.
local function place(keys, dims, hiddenOnly)
  local pos = BagLayout.Stack(dims, UIParent:GetWidth(), UIParent:GetHeight())
  for i, key in ipairs(keys) do
    local win = windows[key]
    if not (win.moved or (hiddenOnly and win:IsShown()) or (AFUI.WinKit and win.afMoveKey and AFUI.WinKit.SavedPos(win.afMoveKey))) then
      win:ClearAllPoints()
      win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", pos[i].x / win.scale, pos[i].y / win.scale)
    end
  end
end

local function sizeSig()
  local t = { state.combined and "c" or "s", keySlots() }
  for bag = 0, MAX_BAG do t[#t + 1] = numSlots(bag) end
  return table.concat(t, ",")
end

local function stackWindows()
  local keys, dims = state:Windows(), {}
  local sig = sizeSig()
  for i, key in ipairs(keys) do
    local win = windows[key]
    win:Show()
    local w, h = layout(key)
    win.dim, win.builtFor, win.sig = { w, h }, state.combined, sig
    dims[i] = win.dim
  end
  place(keys, dims)
end

-- Combat-proof bags: item buttons are secure and cannot be moved, parented or resized in combat, so every window is laid out in advance (hidden), with
-- a default spot, and opening one in combat only Show()s the finished window. Runs at login, after a Combine change, when a bag's size changes and
-- after combat; a stale layout (a bag swapped meanwhile) is shown until the next layout out of combat.
function Bags.Prebuild()
  if not state then return end
  if InCombatLockdown() then AFUI.RunOutOfCombat(Bags.Prebuild); return end
  local sig, keys, dims = sizeSig(), {}, {}
  for _, key in ipairs(state.combined and { "combined" } or { 0, 1, 2, 3, 4, KEYRING }) do
    local win = windows[key]
    if win and (state.combined or numSlots(key) > 0) then
      if not win:IsShown() and (win.builtFor ~= state.combined or win.sig ~= sig) then
        local w, h = layout(key)
        win.dim, win.builtFor, win.sig = { w, h }, state.combined, sig
      end
      if win.dim then keys[#keys + 1] = key; dims[#dims + 1] = win.dim end
    end
  end
  place(keys, dims, true)
end

-- A window that is no longer open: hidden, its dragged spot forgotten, and its items count as seen (the new-item glow goes).
function Bags.CloseWindow(key, win)
  if win:IsShown() then
    if key == "combined" then for bag = 0, MAX_BAG do New.ClearBag(bag) end else New.ClearBag(key) end
  end
  win:Hide(); win.moved = nil
end

local function syncBarButtons()
  local function check(f, on) if f and f.SetChecked then f:SetChecked(on and 1 or nil) end end
  check(_G.MainMenuBarBackpackButton, (AFUI.BagBarMode and AFUI.BagBarMode() == "single") and state:AnyBag() or state:IsOpen(0)) -- the one icon stands for every bag
  for i = 1, MAX_BAG do check(_G["CharacterBag" .. (i - 1) .. "Slot"], state:IsOpen(i)) end
  check(_G.KeyRingButton, state.combined and (state:AnyBag() and Bags.KeyringShown()) or state:IsOpen(KEYRING))
end

-- The Clean Up button: one click sorts (out of combat, no item on the cursor), a click during a run stops it.
local CLEAN_SAY = { combat = "You can't clean up your bags in combat.", cursor = "Put the item on your cursor down first.", nothing = "Nothing to clean up in your bags." }
-- slots / alive: the bank's list and "the bank is still open" (Bank.lua); nothing = the carried bags.
function Bags.CleanUp(slots, alive)
  if Sort.Running() then Sort.Stop("aborted"); return end
  local started = Sort.Start(slots, alive)
  if not started and CLEAN_SAY[Sort.last] and AFUI.Print then AFUI.Print((string.gsub(CLEAN_SAY[Sort.last], "bags", alive and "bank" or "bags"))) end
  Bags.UpdateAll() -- the bank's "Sorting..." mark
end

function Bags.Refresh()
  if not state then return end
  if not state:AnyBag() then Sort.Stop("closed", "bags") end -- the bags closed: a clean up in progress stops
  if InCombatLockdown() then -- item buttons are secure: no layout / SetPoint in combat. The windows are plain frames: Show / Hide them, with the last layout
    local open = {}
    for _, key in ipairs(state:Windows()) do open[key] = true end
    for key, win in pairs(windows) do
      if not open[key] then Bags.CloseWindow(key, win)
      elseif win.builtFor == state.combined and win.dim then win:Show() end -- an unbuilt window waits for the end of combat
    end
    syncBarButtons()
    Bags.UpdateAll()
    AFUI.RunOutOfCombat(Bags.Refresh)
    return
  end
  local open = {}
  for _, key in ipairs(state:Windows()) do open[key] = true end
  for key, win in pairs(windows) do
    if not open[key] then Bags.CloseWindow(key, win) end
  end
  stackWindows()
  syncBarButtons()
end

-- Hide / show the key ring section of the combined window: the setting, so the button, the Settings checkbox and the bag bar's key stay in step.
function Bags.ToggleKeyringSection()
  AFUI.SetSetting("bagKeyring", not Bags.KeyringShown())
  if state then Bags.Refresh() end
end

function Bags.SetCombined(on, fromButton)
  on = on and true or false
  Bags.SaveCombined(on)
  local EM = AFUI.EditMode
  local cur = EM and EM.current and EM.current.systems and EM.current.systems.bags
  if cur then cur.combineBags = on end
  if not state or state.combined == on then return end
  if InCombatLockdown() then AFUI.RunOutOfCombat(function() Bags.SetCombined(on, fromButton) end); return end -- re-laying out secure buttons waits
  for _, win in pairs(windows) do win.moved = nil end
  state:SetCombined(on)
  Bags.Refresh()
  Bags.Prebuild()
end

function Bags.UpdateAll()
  for bag, list in pairs(buttons) do
    for _, b in pairs(list) do if b:IsShown() then Bags.UpdateButton(b) end end
  end
  if windows.combined and windows.combined:IsShown() then setCount(windows.combined, slotList("combined")); Bags.UpdateResults() end
  if Bags.Bank and Bags.Bank.Update then Bags.Bank.Update() end
end

function Bags.SetSearch(text)
  Bags.searchText = text or ""
  for _, win in pairs(windows) do
    if win.search and win.search:GetText() ~= Bags.searchText then win.search:SetText(Bags.searchText) end
    setShown(win.search.hint, Bags.searchText == "")
  end
  local bs = Bags.Bank and Bags.Bank.search -- the bank window's own box shows the same text
  if bs then
    if bs:GetText() ~= Bags.searchText then bs:SetText(Bags.searchText) end
    setShown(bs.hint, Bags.searchText == "")
  end
  Bags.UpdateAll()
end

local function makeSearch(win, id)
  local e = CreateFrame("EditBox", "AFUI_BagSearch" .. id, win, "InputBoxTemplate")
  e:SetAutoFocus(false); e:SetHeight(18); e:SetMaxLetters(30)
  for _, k in ipairs({ "Left", "Middle", "Right" }) do local t = _G["AFUI_BagSearch" .. id .. k]; if t then t:Hide() end end
  local l = atlasTexture(e, "BACKGROUND", "common-input-left"); l:SetPoint("TOPLEFT", e, "TOPLEFT", -4, 3); l:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT", -4, -3); l:SetWidth(10)
  local r = atlasTexture(e, "BACKGROUND", "common-input-left"); r:SetPoint("TOPRIGHT", e, "TOPRIGHT", 4, 3); r:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 4, -3); r:SetWidth(10)
  do local en = AFUI_ATLAS and AFUI_ATLAS["common-input-left"]; if en then r:SetTexCoord(en[5], en[4], en[6], en[7]) end end
  local m = atlasTexture(e, "BACKGROUND", "common-input-middle"); m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  local mag = atlasTexture(e, "OVERLAY", "common-search-magnifyingglass", 10, 10); mag:SetPoint("LEFT", e, "LEFT", 1, -1)
  e:SetTextInsets(16, 8, 0, 0)
  e.hint = e:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  e.hint:SetPoint("LEFT", e, "LEFT", 16, 0); e.hint:SetText(SEARCH or "Search")
  local clear = CreateFrame("Button", nil, e)
  clear:SetWidth(14); clear:SetHeight(14); clear:SetPoint("RIGHT", e, "RIGHT", -2, 0); clear:Hide()
  AFUI.SetButtonAtlas(clear, { "common-search-clearbutton", "common-search-clearbutton", "common-search-clearbutton" })
  clear:SetScript("OnClick", function() e:SetText(""); e:ClearFocus() end)
  e.clear = clear
  e:SetScript("OnTextChanged", function(self)
    setShown(clear, self:GetText() ~= "")
    if self:GetText() ~= Bags.searchText then Bags.SetSearch(self:GetText()) end
  end)
  e:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
  e:SetScript("OnEditFocusLost", function(self) setShown(self.hint, self:GetText() == "") end)
  return e
end

Bags.MakeSearch = makeSearch

local function makeMoney(win, id)
  local box = CreateFrame("Frame", "AFUI_BagMoney" .. id, win)
  box:SetWidth(168); box:SetHeight(17)
  box:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -9, 9)
  local l = atlasTexture(box, "BACKGROUND", "common-coinbox-left"); l:SetPoint("LEFT", box, "LEFT")
  local r = atlasTexture(box, "BACKGROUND", "common-coinbox-right"); r:SetPoint("RIGHT", box, "RIGHT")
  local c = atlasTexture(box, "BACKGROUND", "_common-coinbox-center"); c:SetPoint("TOPLEFT", l, "TOPRIGHT"); c:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  local prev = box
  for _, k in ipairs({ { "copper", "UI-CopperIcon" }, { "silver", "UI-SilverIcon" }, { "gold", "UI-GoldIcon" } }) do
    local ic = box:CreateTexture(nil, "ARTWORK")
    ic:SetTexture("Interface\\MoneyFrame\\" .. k[2]); ic:SetWidth(13); ic:SetHeight(13)
    ic:SetPoint("RIGHT", prev, prev == box and "RIGHT" or "LEFT", prev == box and -4 or -3, 0)
    local fs = box:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
    fs:SetPoint("RIGHT", ic, "LEFT", -1, 0); fs:SetJustifyH("RIGHT"); fs:SetWidth(34); fs:SetHeight(12)
    box[k[1]] = fs
    prev = fs
  end
  return box
end

-- the currency strip under the money: dark inset with a green outline (the capture), count then icon, right aligned
local function makeCurrency(win, id)
  local box = CreateFrame("Frame", "AFUI_BagCurrency" .. id, win)
  box:SetWidth(168); box:SetHeight(17)
  box:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -9, 9)
  local fill = box:CreateTexture(nil, "BACKGROUND"); fill:SetAllPoints(box); AFUI.SetColor(fill, 0.06, 0.07, 0.09, 0.9)
  local function edge(a, b, w, h)
    local t = box:CreateTexture(nil, "BORDER"); AFUI.SetColor(t, 0.18, 0.42, 0.16, 1)
    t:SetPoint(a, box, a); t:SetPoint(b, box, b)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
  end
  edge("TOPLEFT", "TOPRIGHT", nil, 1); edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1); edge("TOPLEFT", "BOTTOMLEFT", 1); edge("TOPRIGHT", "BOTTOMRIGHT", 1)
  box.items = {}
  for i = 1, 3 do
    local ic = box:CreateTexture(nil, "ARTWORK"); ic:SetWidth(13); ic:SetHeight(13)
    local fs = box:CreateFontString(nil, "ARTWORK", "NumberFontNormal"); fs:SetJustifyH("RIGHT")
    box.items[i] = { icon = ic, text = fs }
  end
  return box
end

function Bags.SetCurrency(win)
  local list = Bags.Currencies()
  local prev
  for i = 3, 1, -1 do -- the first listed sits leftmost, so lay out from the right
    local it, c = win.currency.items[i], list[i]
    if c then
      it.icon:ClearAllPoints(); it.icon:SetPoint("RIGHT", prev or win.currency, prev and "LEFT" or "RIGHT", prev and -10 or -4, 0)
      AFUI.SetIcon(it.icon, c.icon); it.icon:Show()
      it.text:ClearAllPoints(); it.text:SetPoint("RIGHT", it.icon, "LEFT", -1, 0); it.text:SetText(c.count); it.text:Show()
      prev = it.text
    else it.icon:Hide(); it.text:Hide() end
  end
end

local function makeWindow(key)
  local id = (key == "combined") and "Combined" or tostring(key + 2)
  local win = CreateFrame("Frame", "AFUI_BagWindow" .. id, UIParent)
  win:SetFrameStrata("HIGH"); win:SetToplevel(true); win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
  win:Hide()
  win.key, win.pieces = key, {}
  -- Forever's Bg: UI-Background-Rock tiled both ways (shareduipaneltemplates.xml ButtonFrameBaseTemplate, TOPLEFT 2,-21 / BOTTOMRIGHT -2,2),
  -- darkened to the bank capture's tone. The file is 512 px; no tiling API on 2.4.3, so the texcoords repeat it (set per size in layout).
  local bg = win:CreateTexture(nil, "BACKGROUND"); bg:SetTexture(PLAIN .. "UI-Background-Rock"); bg:SetVertexColor(ROCK_TINT[1], ROCK_TINT[2], ROCK_TINT[3])
  bg:SetPoint("TOPLEFT", win, "TOPLEFT", 2, -21); bg:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -2, 2)
  win.rock = bg
  local foot = win:CreateTexture(nil, "BORDER"); AFUI.SetColor(foot, 0.1, 0.1, 0.11, 0.55) -- the bank's grey footer strip under the money
  foot:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 3, 3); foot:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -3, 3); foot:SetHeight(30); foot:Hide()
  win.footer = foot
  win.portrait = win:CreateTexture(nil, "ARTWORK")
  AFUI.WindowPortrait(win, win.portrait)
  local tf = CreateFrame("Frame", nil, win); tf:SetAllPoints(win); tf:SetFrameLevel(win:GetFrameLevel() + 25) -- above the metal pieces
  win.title = tf:CreateFontString(nil, "OVERLAY", key == "combined" and "GameFontHighlight" or "GameFontNormal") -- the video: white
  win.title:SetPoint("TOP", win, "TOP", 0, -6)
  win.countIcon = tf:CreateTexture(nil, "OVERLAY")
  win.countIcon:SetTexture("Interface\\AddOns\\AztraForeverUI\\Media\\chat\\ui-hud-actionbar-bag"); win.countIcon:SetWidth(18); win.countIcon:SetHeight(18)
  win.count = tf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  win.count:SetPoint("BOTTOM", win, "BOTTOM", -30, 11); win.countIcon:SetPoint("RIGHT", win.count, "LEFT", -3, 0)
  win.tf = tf
  -- the counter's tooltip: free slots per bag type
  local ch = CreateFrame("Frame", nil, win)
  ch:SetFrameLevel(win:GetFrameLevel() + 30); ch:EnableMouse(true); ch:SetHeight(20)
  ch:SetPoint("LEFT", win.countIcon, "LEFT", -2, 0); ch:SetPoint("RIGHT", win.count, "RIGHT", 2, 0)
  ch:SetScript("OnEnter", function(self) Bags.FreeTooltip(self) end)
  ch:SetScript("OnLeave", function() GameTooltip:Hide() end)
  ch:Hide()
  win.countHit = ch
  win.noResults = tf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.noResults:SetText("No results"); win.noResults:SetPoint("CENTER", win, "CENTER", 0, 4); win.noResults:Hide()
  if key == "combined" then -- key ring section: separator, label, and the button in the bottom strip that hides / shows it
    win.keySep = tf:CreateTexture(nil, "OVERLAY"); AFUI.SetColor(win.keySep, 0.75, 0.62, 0.35, 0.45); win.keySep:SetHeight(1); win.keySep:Hide()
    win.keyLabel = tf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); win.keyLabel:SetText("Keys"); win.keyLabel:Hide()
    local kb = CreateFrame("Button", nil, win)
    kb:SetWidth(20); kb:SetHeight(20); kb:SetFrameLevel(win:GetFrameLevel() + 30)
    kb:SetPoint("RIGHT", win.countIcon, "LEFT", -8, 0)
    kb.icon = kb:CreateTexture(nil, "ARTWORK"); kb.icon:SetAllPoints(kb); AFUI.SetAtlas(kb.icon, "ui-hud-actionbar-keyring-small-c60")
    kb.Refresh = function() kb.icon:SetAlpha(Bags.KeyringShown() and 1 or 0.45) end
    kb:SetScript("OnClick", function() Bags.ToggleKeyringSection() end)
    kb:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(Bags.KeyringShown() and "Hide keyring" or "Show keyring", 1, 1, 1); GameTooltip:Show()
    end)
    kb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    kb:Hide()
    win.keyBtn = kb
  end
  -- drag by the title strip
  local drag = CreateFrame("Frame", nil, win)
  drag:SetPoint("TOPLEFT", win, "TOPLEFT", 58, 0); drag:SetPoint("TOPRIGHT", win, "TOPRIGHT", -62, 0); drag:SetHeight(20); drag:EnableMouse(true)
  drag:HookScript("OnDragStart", function() win.moved = true end)
  if AFUI.WinKit then AFUI.WinKit.makeMovable(win, drag, "bag" .. id, { place = function() win.moved = nil; Bags.Refresh() end }) end -- the spot is kept per character; stackWindows leaves a placed window alone
  local close = CreateFrame("Button", nil, win)
  close:SetWidth(28); close:SetHeight(28); close:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 3); close:SetFrameLevel(win:GetFrameLevel() + 30)
  AFUI.SetButtonAtlas(close, { "redbutton-exit", "redbutton-exit-pressed", "redbutton-highlight", "redbutton-exit-disabled" })
  close:SetScript("OnClick", function()
    if key == "combined" then state:CloseAll() else state:Close(key) end
    Bags.Refresh()
  end)
  -- Combine Bags: the second button of the corner (Forever's maximize slot), on every bag window
  local tg = CreateFrame("Button", nil, win)
  tg:SetWidth(28); tg:SetHeight(28); tg:SetPoint("RIGHT", close, "LEFT", -1, 0); tg:SetFrameLevel(win:GetFrameLevel() + 30)
  tg.Refresh = function()
    if state.combined then AFUI.SetButtonAtlas(tg, { "redbutton-expand", "redbutton-expand-pressed", "redbutton-highlight", "redbutton-expand-disabled" })
    else AFUI.SetButtonAtlas(tg, { "redbutton-condense", "redbutton-condense-pressed", "redbutton-highlight", "redbutton-condense-disabled" }) end
  end
  tg:SetScript("OnClick", function() Bags.SetCombined(not Bags.IsCombined(), true) end)
  tg:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(Bags.ToggleTooltip(state.combined), 1, 1, 1)
    GameTooltip:AddLine(Bags.ToggleHint(state.combined), nil, nil, nil, true)
    GameTooltip:Show()
  end)
  tg:SetScript("OnLeave", function() GameTooltip:Hide() end)
  win.toggle = tg
  win.search = makeSearch(win, id)
  win.money = makeMoney(win, id)
  win.currency = makeCurrency(win, id)
  -- sort / clean up (the gold button right of the search box); TBC has no SortBags, so Bags.Sort swaps items out of combat
  local sb = CreateFrame("Button", nil, win)
  sb:SetWidth(24); sb:SetHeight(24); sb:SetPoint("TOPRIGHT", win, "TOPRIGHT", -9, -30)
  AFUI.SetButtonAtlas(sb, { "bags-button-autosort-up", "bags-button-autosort-down", "bags-button-autosort-up" }, 0.4)
  sb:SetScript("OnClick", function() Bags.CleanUp() end)
  sb:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText(BAG_CLEANUP_BAGS or "Clean Up Bags", 1, 1, 1)
    GameTooltip:AddLine(Sort.Running() and "Click again to stop." or (on("bagGroupCategory") and "Sorts your bags by category, then type, quality and name." or "Sorts your bags by type, quality and name."), 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  sb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  win.sort = sb
  win.search:Hide(); win.money:Hide(); win.currency:Hide(); win.sort:Hide()
  windows[key] = win
  return win
end

---------------------------------------------------------------- Blizzard's open / close entry points
local orig = {}
local function mine(id) return type(id) == "number" and id >= KEYRING and id <= MAX_BAG and id ~= -1 end

local function override(name, fn)
  if type(_G[name]) ~= "function" then return end
  orig[name] = _G[name]
  _G[name] = fn
end

local function hookBagButtonHover()
  local function hover(btn, bag)
    if not btn then return end
    btn:HookScript("OnEnter", function() for _, b in pairs(buttons[bag] or {}) do setShown(b.indicator, state.combined and b:IsShown()) end end)
    btn:HookScript("OnLeave", function() for _, b in pairs(buttons[bag] or {}) do b.indicator:Hide() end end)
  end
  hover(_G.MainMenuBarBackpackButton, 0)
  for i = 1, MAX_BAG do hover(_G["CharacterBag" .. (i - 1) .. "Slot"], i) end
end

function Bags.Setup()
  if state then return end
  state = BagState.New(numSlots)
  state.combined = Bags.IsCombined()
  Bags.state = state
  for _, key in ipairs({ "combined", 0, 1, 2, 3, 4, KEYRING }) do makeWindow(key) end
  for bag = KEYRING, MAX_BAG do if bag ~= -1 then holder(bag) end end

  local function act(fn) return function(...) fn(...); Bags.Refresh() end end
  override("ToggleBackpack", act(function() state:Toggle(0) end))
  override("OpenBackpack", act(function() state:Open(0) end))
  override("CloseBackpack", act(function() state:Close(0) end))
  -- bank bag ids 5..11 while the bank shows them in its own combined window: Blizzard's separate windows are never opened (Bank.Owns)
  local function bankBag(id) return Bags.Bank and Bags.Bank.Owns and Bags.Bank.Owns(id) end
  override("ToggleBag", function(id)
    if bankBag(id) then return end
    if mine(id) then state:Toggle(id); Bags.Refresh() else orig.ToggleBag(id) end
  end)
  override("OpenBag", function(id)
    if bankBag(id) then return end
    if mine(id) then state:Open(id); Bags.Refresh() else orig.OpenBag(id) end
  end)
  override("CloseBag", function(id)
    if bankBag(id) then return end
    if mine(id) then state:Close(id); Bags.Refresh() else orig.CloseBag(id) end
  end)
  override("IsBagOpen", function(id)
    if bankBag(id) then return Bags.Bank.Shown() and id or nil end
    if mine(id) then return state:IsOpen(id) and id or nil end
    return orig.IsBagOpen(id)
  end)
  override("OpenAllBags", act(function(force) state:OpenAll(force) end))
  override("ToggleAllBags", act(function() state:OpenAll(false) end))
  override("CloseAllBags", function()
    state:CloseAll(); Bags.Refresh()
    if orig.CloseAllBags then orig.CloseAllBags() end -- bank bags are still Blizzard's windows
  end)
  override("ToggleKeyRing", act(function()
    if not state.combined then state:Toggle(KEYRING); return end
    if numSlots(KEYRING) == 0 then return end
    if not state:AnyBag() then -- closed bags: open them with the keys showing
      AFUI.SetSetting("bagKeyring", true); state:OpenAll(true)
    else AFUI.SetSetting("bagKeyring", not Bags.KeyringShown()) end
  end))

  -- safety net: if something still shows one of Blizzard's own held-bag frames, hide it
  for i = 1, 13 do
    local f = _G["ContainerFrame" .. i]
    if f and f.HookScript then
      f:HookScript("OnShow", function(self)
        local id = self:GetID()
        if id and ((id <= MAX_BAG and id >= KEYRING) or (bankBag(id) and not InCombatLockdown())) then self:Hide() end
      end)
    end
  end
  hookBagButtonHover()
  Bags.SetupItemLevel()
  Bags.Refresh()
  Bags.Prebuild()
end

-- Item level on the Character window's slots: the client's own slot update, the window showing, and the equipment events; the settings re-draw.
function Bags.SetupItemLevel()
  if _G.CharacterFrame and CharacterFrame.HookScript then CharacterFrame:HookScript("OnShow", IL.UpdateCharacter) end
  if type(_G.PaperDollItemSlotButton_Update) == "function" then hooksecurefunc("PaperDollItemSlotButton_Update", IL.UpdateSlot) end
  if AFUI.QoL then
    AFUI.QoL.Watch("charItemLevel", IL.UpdateCharacter)
    AFUI.QoL.Watch("bagItemLevel", Bags.UpdateAll)
    AFUI.QoL.Watch("bagNewGlow", Bags.UpdateAll)
    AFUI.QoL.Watch("bagKeyring", function() if state then Bags.Refresh() end end)
    AFUI.QoL.Watch("bagGroupCategory", function() if state then Bags.Refresh() end end)
    for _, k in ipairs({ "bagQuestMarker", "bagUpgradeArrow", "bagDontSell", "bagGrayJunk", "bagRedUnusable" }) do AFUI.QoL.Watch(k, Bags.UpdateAll) end
  end
  -- Settings.lua loads after this file, so the options are registered here (at login, when every file is in)
  if AFUI.Settings and AFUI.Settings.Register then
    AFUI.Settings.Register{ category = "tooltips", key = "bagGrayJunk", label = "Grey out junk items", default = true,
      tooltip = "Grey (poor quality) items that a vendor buys are dimmed in your bags and the bank and carry a small coin at the top left. Quest items with no sell price are left alone." }
    AFUI.Settings.Register{ category = "tooltips", key = "bagRedUnusable", label = "Red tint on unusable items", default = true,
      tooltip = "Items you cannot use or equip (a red line in their tooltip: level, class, armor type, weapon skill) get a red icon in your bags, the bank and the vendor window." }
  end
  if AFUI.ProvideSetting then AFUI.ProvideSetting("bagGrayJunk", true); AFUI.ProvideSetting("bagRedUnusable", true) end
  IL.UpdateCharacter()
end
AFUI.On("PLAYER_EQUIPMENT_CHANGED", function() IL.UpdateCharacter() end)
AFUI.On("UNIT_INVENTORY_CHANGED", function(_, unit) if unit == "player" then IL.UpdateCharacter() end end)

-- New-item tracking runs whether or not a bag is open: one scan on the frame after a burst of BAG_UPDATEs. Entering the world (login, reload, a
-- loading screen) re-bases it for 3 seconds so the bags filling up are not "new".
local scanner = CreateFrame("Frame")
local scanDirty
local function bankOpen() return _G.BankFrame and BankFrame.IsShown and BankFrame:IsShown() or false end
function Bags.ScheduleScan()
  if scanDirty then return end
  scanDirty = true
  scanner:SetScript("OnUpdate", function(self)
    self:SetScript("OnUpdate", nil)
    scanDirty = false
    New.Scan(bankOpen())
    if state then Bags.UpdateAll() end
  end)
end
AFUI.On("BAG_UPDATE", Bags.ScheduleScan)
AFUI.On("PLAYER_ENTERING_WORLD", function() New.quietUntil = GetTime() + 3; New.prev = nil; Bags.ScheduleScan() end)
AFUI.On("BANKFRAME_OPENED", function() New.quietUntil = GetTime() + 1; Bags.ScheduleScan() end)
AFUI.On("BANKFRAME_CLOSED", function() New.ClearBag(-1); for id = MAX_BAG + 1, MAX_BAG + (_G.NUM_BANKBAGSLOTS or 7) do New.ClearBag(id) end; Sort.Stop("closed", "bank"); Bags.ScheduleScan() end)

-- BAG_UPDATE fires in bursts (one per bag slot touched): mark dirty and lay out once on the next frame, then the OnUpdate removes itself.
local pending = CreateFrame("Frame")
local dirty
local function onBagChange()
  if not state then return end
  if #state:Windows() == 0 then Bags.Prebuild(); return end -- closed: keep the hidden layout current (a bag was swapped) for opening in combat
  if dirty then return end
  dirty = true
  pending:SetScript("OnUpdate", function(self)
    self:SetScript("OnUpdate", nil)
    dirty = false
    if state and #state:Windows() > 0 then Bags.Refresh() end
  end)
end
AFUI.On("BAG_UPDATE", onBagChange)
AFUI.On("UNIT_INVENTORY_CHANGED", function(_, unit) if unit == "player" then onBagChange() end end)
AFUI.On("ITEM_LOCK_CHANGED", function(_, bag, slot)
  local b = bag and buttons[bag] and slot and buttons[bag][slot]
  if b and b:IsShown() then Bags.UpdateButton(b) end
end)
AFUI.On("BAG_UPDATE_COOLDOWN", function() if state then Bags.UpdateAll() end end)
AFUI.On("MERCHANT_SHOW", function() if state then Bags.UpdateAll() end end)
AFUI.On("MERCHANT_CLOSED", function() if state then Bags.UpdateAll() end end)
local function currencyChanged()
  if state and windows[0] and windows[0]:IsShown() then Bags.SetCurrency(windows[0]) end
end
AFUI.On("CURRENCY_DISPLAY_UPDATE", currencyChanged)
AFUI.On("HONOR_CURRENCY_UPDATE", currencyChanged)
AFUI.On("PLAYER_MONEY", function()
  if not state then return end
  for _, win in pairs(windows) do if win:IsShown() and win.money:IsShown() then setMoney(win) end end
end)

---------------------------------------------------------------- open the bags with a vendor, the bank, the mail, the auction house or a trade
-- Only what this addon opened is closed again, and only when the last of those windows is gone. Bags the player already had open stay open.
local AUTO = { MERCHANT_SHOW = "merchant", BANKFRAME_OPENED = "bank", MAIL_SHOW = "mail", AUCTION_HOUSE_SHOW = "auction", TRADE_SHOW = "trade" }
local AUTO_KIND = { MERCHANT_CLOSED = "merchant", BANKFRAME_CLOSED = "bank", MAIL_CLOSED = "mail", AUCTION_HOUSE_CLOSED = "auction", TRADE_CLOSED = "trade" }
Bags.auto = { active = {}, opened = false }
function Bags.AutoOpen(kind)
  local a = Bags.auto
  a.active[kind] = true
  if not state or not on("bagAutoOpen") or state:AnyBag() then return end
  a.opened = true
  state:OpenAll(true); Bags.Refresh()
end
function Bags.AutoClose(kind)
  local a = Bags.auto
  a.active[kind] = nil
  if not state or not a.opened or next(a.active) then return end
  a.opened = false
  state:CloseAll(); Bags.Refresh()
end
for ev, kind in pairs(AUTO) do AFUI.On(ev, function() Bags.AutoOpen(kind) end) end
for ev, kind in pairs(AUTO_KIND) do AFUI.On(ev, function() Bags.AutoClose(kind) end) end

AFUI.RegisterModule("Bags", { OnLogin = Bags.Setup })
