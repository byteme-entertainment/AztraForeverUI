-- Forever's tooltips (docs/forever-ref/video-notes/tooltips.md, measured on the capture): a near-black box (#0d0c15, ~95 % opaque) inside the retail
-- tooltip nine-slice border (atlas tooltip-nineslice-*: 7 px rounded corners, a 1 px line with a soft shadow on both sides; the line is white in the art
-- and takes the vertex colour: grey-gold #a38f6b, or the quality colour on an item), the default anchor in the bottom-right corner just above the bag bar.
-- Nothing is rebuilt: the client's tooltip frames keep every line. The client's own backdrop is cleared and the border is drawn by a child frame of our
-- own BEHIND the text (eight textures + the fill, no SetBackdrop), re-applied by hooks (HookScript / hooksecurefunc) on every show, size change and item.
-- Item tooltips also get the vendor "Sell Price" line when no merchant window is open (the client only prints it at a merchant).
AFUI = AFUI or {}
local T = {}
AFUI.Tooltips = T

local PLAIN = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\"

T.BG = { 0.051, 0.047, 0.082, 0.95 }
T.EDGE = { 0.639, 0.561, 0.42, 1 } -- video3 f0259: a 1.4 px line, outer #6c5c43 then #d0c0a7 (the two blend to #a38f6b at one unit)
T.BAR_H = 6 -- the unit health bar under the box: 8 px tall, bright green #15ee0b in the middle, darker toward its edges
T.BAR = { 0.08, 0.93, 0.04 }
T.NAMES = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
  "ItemRefShoppingTooltip3", "SmallTextTooltip" }

-- The nine-slice art: Tooltip-Border (64x64 file, the 16x64 sheet padded) holds the corners and the top / bottom edges, Tooltip-Sides (32x32, the 32x16 sheet
-- padded) the left / right edges. Rects are pixels of the file { file, size, x0, x1, y0, y1 }, read from the atlas members tooltip-nineslice-* (wago
-- UiTextureAtlasMember): corners 7x7, edges 16 wide (top / bottom) or 16 tall (left / right). The edges are uniform along their length, so the middle
-- of one is stretched instead of tiled.
local B, S = PLAIN .. "Tooltip-Border", PLAIN .. "Tooltip-Sides"
T.SLICE = 7 -- the corner size
T.OUTSET = 2 -- the art's line sits 2 px inside its outer edge: the frame reaches 2 px past the tooltip so the line lands on the tooltip's edge
T.FILL_INSET = 3 -- the fill starts under the line
T.ART = {
  TL = { B, 64, 1, 8, 37, 44 }, TR = { B, 64, 1, 8, 46, 53 }, BL = { B, 64, 1, 8, 19, 26 }, BR = { B, 64, 1, 8, 28, 35 },
  T = { B, 64, 4, 12, 10, 17 }, B = { B, 64, 4, 12, 1, 8 }, L = { S, 32, 1, 8, 4, 12 }, R = { S, 32, 10, 17, 4, 12 },
}
T.KEYS = { "TL", "TR", "BL", "BR", "T", "B", "L", "R" }

local function coords(a) return a[3] / a[2], a[4] / a[2], a[5] / a[2], a[6] / a[2] end
T.Coords = coords

-- Anchors of one piece, as { point, relativeTo ("host" or another piece), relativePoint, x, y } lists, and its size (nil = from the anchors).
function T.Layout()
  local s = T.SLICE
  return {
    TL = { w = s, h = s, { "TOPLEFT", "host", "TOPLEFT", 0, 0 } },
    TR = { w = s, h = s, { "TOPRIGHT", "host", "TOPRIGHT", 0, 0 } },
    BL = { w = s, h = s, { "BOTTOMLEFT", "host", "BOTTOMLEFT", 0, 0 } },
    BR = { w = s, h = s, { "BOTTOMRIGHT", "host", "BOTTOMRIGHT", 0, 0 } },
    T = { h = s, { "TOPLEFT", "TL", "TOPRIGHT", 0, 0 }, { "TOPRIGHT", "TR", "TOPLEFT", 0, 0 } },
    B = { h = s, { "BOTTOMLEFT", "BL", "BOTTOMRIGHT", 0, 0 }, { "BOTTOMRIGHT", "BR", "BOTTOMLEFT", 0, 0 } },
    L = { w = s, { "TOPLEFT", "TL", "BOTTOMLEFT", 0, 0 }, { "BOTTOMLEFT", "BL", "TOPLEFT", 0, 0 } },
    R = { w = s, { "TOPRIGHT", "TR", "BOTTOMRIGHT", 0, 0 }, { "BOTTOMRIGHT", "BR", "TOPRIGHT", 0, 0 } },
  }
end

-- Border colour: an item tooltip takes its quality colour (grey / common keep the Forever grey-gold), anything else the muted edge.
function T.EdgeColor(quality, r, g, b)
  if quality and quality >= 2 and r then return { r, g, b, 1 } end
  return T.EDGE
end

-- Our frame behind the text: the fill and the eight border pieces. Built once per tooltip.
function T.Build(tip)
  if tip.afBorder or not (tip.CreateTexture and _G.CreateFrame) then return tip.afBorder end
  local host = CreateFrame("Frame", nil, tip)
  host:SetPoint("TOPLEFT", tip, "TOPLEFT", -T.OUTSET, T.OUTSET)
  host:SetPoint("BOTTOMRIGHT", tip, "BOTTOMRIGHT", T.OUTSET, -T.OUTSET)
  host:EnableMouse(false)
  host.afOverhang = true -- reaches 2 px past the tooltip on purpose (the audit skips it)
  -- below the tooltip's own text (a child frame normally draws above its parent's regions)
  local lvl = tip.GetFrameLevel and tip:GetFrameLevel() or 1
  host:SetFrameLevel(lvl > 0 and lvl - 1 or 0)
  host.fill = host:CreateTexture(nil, "BACKGROUND")
  host.fill:SetPoint("TOPLEFT", host, "TOPLEFT", T.FILL_INSET, -T.FILL_INSET)
  host.fill:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -T.FILL_INSET, T.FILL_INSET)
  AFUI.SetColor(host.fill, T.BG[1], T.BG[2], T.BG[3], T.BG[4])
  host.pieces = {}
  local lay = T.Layout()
  for _, k in ipairs(T.KEYS) do
    local a, p = T.ART[k], host:CreateTexture(nil, "BORDER")
    p:SetTexture(a[1]); p:SetTexCoord(coords(a))
    local l = lay[k]
    for _, pt in ipairs(l) do p:SetPoint(pt[1], pt[2] == "host" and host or host.pieces[pt[2]], pt[3], pt[4], pt[5]) end
    if l.w then p:SetWidth(l.w) end
    if l.h then p:SetHeight(l.h) end
    host.pieces[k] = p
  end
  tip.afBorder = host
  return host
end

-- The client draws its own backdrop (BackdropTemplate on 2.5.3); it is cleared on every pass so only our frame shows.
local function clearBackdrop(tip)
  if tip.SetBackdrop then tip:SetBackdrop(nil) end
  local ns = rawget(tip, "NineSlice") -- a client that draws its tooltip with a NineSlice child instead
  if ns and ns.SetAlpha then ns:SetAlpha(0) end
end

local function skin(tip, edge)
  if not tip then return end
  clearBackdrop(tip)
  local host = T.Build(tip)
  if not host then return end
  local e = edge or T.EDGE
  for _, k in ipairs(T.KEYS) do host.pieces[k]:SetVertexColor(e[1], e[2], e[3], e[4] or 1) end
  host.edge = e
  host:Show()
end
T.Skin = skin

local function itemEdge(tip)
  local link
  if tip.GetItem then _, link = tip:GetItem() end
  if not link or not _G.GetItemInfo then return T.EDGE end
  local q = select(3, GetItemInfo(link))
  if q and _G.GetItemQualityColor then local r, g, b = GetItemQualityColor(q); return T.EdgeColor(q, r, g, b) end
  return T.EDGE
end

-- The unit tooltip's health bar sits directly UNDER the box, as wide as the box (the client keeps it inside the bottom edge).
local sbBack
function T.PlaceBar(tip)
  local sb = _G.GameTooltipStatusBar
  if tip ~= _G.GameTooltip or not sb then return end
  sb.afOverhang = true -- hangs under the box on purpose
  sb:ClearAllPoints()
  sb:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 0, 0); sb:SetPoint("TOPRIGHT", tip, "BOTTOMRIGHT", 0, 0)
  sb:SetHeight(T.BAR_H)
  if sb.SetStatusBarTexture then sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8") end
  if sb.SetStatusBarColor then sb:SetStatusBarColor(T.BAR[1], T.BAR[2], T.BAR[3]) end
  if not sbBack and sb.CreateTexture then
    sbBack = sb:CreateTexture(nil, "BACKGROUND")
    AFUI.SetColor(sbBack, 0.02, 0.02, 0.02, 0.9)
    sbBack:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0); sbBack:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
  end
end

---------------------------------------------------------------- vendor sell price
-- The stack the tooltip's owner shows: its Count text (bag, bank and character buttons all have "<name>Count"), else 1.
function T.StackCount(tip)
  local owner = tip.GetOwner and tip:GetOwner()
  local name = owner and owner.GetName and owner:GetName()
  local fs = name and _G[name .. "Count"]
  local n = fs and fs.GetText and (not fs.IsShown or fs:IsShown()) and tonumber(fs:GetText())
  return n and n > 0 and n or 1
end

function T.SellPrice(link, count)
  if not link or not _G.GetItemInfo then return end
  local price = select(11, GetItemInfo(link))
  if not price or price <= 0 then return end
  return price * (count or 1)
end

local function hasPriceLine(tip)
  local name = tip.GetName and tip:GetName()
  if not name or not tip.NumLines then return false end
  local word = _G.SELL_PRICE or "Sell Price"
  for i = 1, tip:NumLines() do
    local fs = _G[name .. "TextLeft" .. i]
    local t = fs and fs.GetText and fs:GetText()
    if t and string.find(t, word, 1, true) then return true end
  end
  return false
end

-- Adds "Sell Price: 12g 34s 56c" (coin icons) once per item: not at a merchant (the client prints its own there), not twice.
function T.AddSellPrice(tip)
  if not (AFUI.QoL and AFUI.QoL.Get("tooltipSellPrice")) or tip.afSellDone then return end
  if _G.MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then return end
  local link
  if tip.GetItem then _, link = tip:GetItem() end
  local total = T.SellPrice(link, T.StackCount(tip))
  if not total or hasPriceLine(tip) then return end
  tip.afSellDone = true
  tip:AddLine((_G.SELL_PRICE or "Sell Price") .. ": " .. AFUI.QoL.CoinText(total), 1, 1, 1)
  if tip.Show then tip:Show() end -- re-measure the box for the new line
end

---------------------------------------------------------------- compare with what you wear, item level, ids
-- The client shows the shopping tooltips (GameTooltip_ShowCompareItem) on Shift / "always compare": the same moment adds the stat difference to the
-- hovered tooltip, green better / red worse, against the equipped item (a ring or trinket against each of the two worn, a two-hander against
-- main hand + off hand together). Stats come from GetItemStats; a client without it (and the damage per second, which no API gives) is read from a
-- hidden scanning tooltip. Settings: tooltipCompareStats (on), tooltipItemLevel (on), tooltipIds (off: ItemID / SpellID / QuestID).
T.GREEN, T.RED, T.GREY = { 0.1, 1, 0.1 }, { 1, 0.2, 0.2 }, { 0.6, 0.6, 0.6 }
-- equip location -> groups of inventory slots; a group's stats are summed, each group is one comparison
T.SLOTS = {
  INVTYPE_HEAD = { { 1 } }, INVTYPE_NECK = { { 2 } }, INVTYPE_SHOULDER = { { 3 } }, INVTYPE_BODY = { { 4 } }, INVTYPE_CHEST = { { 5 } }, INVTYPE_ROBE = { { 5 } },
  INVTYPE_WAIST = { { 6 } }, INVTYPE_LEGS = { { 7 } }, INVTYPE_FEET = { { 8 } }, INVTYPE_WRIST = { { 9 } }, INVTYPE_HAND = { { 10 } },
  INVTYPE_FINGER = { { 11 }, { 12 } }, INVTYPE_TRINKET = { { 13 }, { 14 } }, INVTYPE_CLOAK = { { 15 } },
  INVTYPE_WEAPON = { { 16 }, { 17 } }, INVTYPE_2HWEAPON = { { 16, 17 } }, INVTYPE_WEAPONMAINHAND = { { 16 } },
  INVTYPE_WEAPONOFFHAND = { { 17 } }, INVTYPE_SHIELD = { { 17 } }, INVTYPE_HOLDABLE = { { 17 } },
  INVTYPE_RANGED = { { 18 } }, INVTYPE_RANGEDRIGHT = { { 18 } }, INVTYPE_THROWN = { { 18 } }, INVTYPE_RELIC = { { 18 } }, INVTYPE_TABARD = { { 19 } },
}

local function pattern(tmpl, fallback) -- "(%s damage per second)" -> a Lua pattern with one capture
  return "^" .. (tmpl or fallback):gsub("[%(%)%.%-%+%?%*%[%]%^%$]", "%%%0"):gsub("%%s", "([%%d%%.,]+)") .. "$"
end

-- stats out of tooltip lines: "+5 Strength", "123 Armor", "(46.2 damage per second)" -> { label = value }
function T.ParseLines(lines)
  local out = {}
  local dps, armor = pattern(_G.DPS_TEMPLATE, "(%s damage per second)"), pattern(_G.ARMOR_TEMPLATE, "%s Armor")
  for _, t in ipairs(lines) do
    local v = t:match(dps)
    if v then out.DPS = tonumber((v:gsub(",", "."))) else
      v = t:match(armor)
      if v then out[_G.RESISTANCE0_NAME or "Armor"] = tonumber(v) else
        local n, label = t:match("^%+(%d+) (%a[%a ]*)$")
        if n then out[label] = tonumber(n) end
      end
    end
  end
  return out
end

local scan
function T.Scan(link)
  if not scan then
    if not _G.CreateFrame then return {} end
    scan = CreateFrame("GameTooltip", "AFUI_CompareScan", nil, "GameTooltipTemplate")
    if scan.SetOwner then scan:SetOwner(UIParent, "ANCHOR_NONE") end
  end
  if not (scan.SetHyperlink and scan.NumLines) then return {} end
  scan:ClearLines(); scan:SetHyperlink(link)
  local lines = {}
  for i = 2, scan:NumLines() do
    local fs = _G["AFUI_CompareScanTextLeft" .. i]
    local t = fs and fs.GetText and fs:GetText()
    if t then lines[#lines + 1] = t end
  end
  return lines
end

-- label -> value of one item (nil link: nothing)
function T.Stats(link)
  local out = {}
  if not link then return out end
  local lines = T.Scan(link)
  if _G.GetItemStats then
    for k, v in pairs(GetItemStats(link) or {}) do
      if type(v) == "number" and not tostring(k):find("^EMPTY_SOCKET") then out[type(_G[k]) == "string" and _G[k] or k] = v end
    end
    out.DPS = T.ParseLines(lines).DPS
  else
    out = T.ParseLines(lines)
  end
  return out
end

-- new minus old, as a list { label, delta } with the damage per second and armor first, the rest by name
function T.Diff(new, old)
  local keys, out = {}, {}
  for k in pairs(new) do keys[k] = true end
  for k in pairs(old) do keys[k] = true end
  for k in pairs(keys) do
    local d = (new[k] or 0) - (old[k] or 0)
    if math.abs(d) >= 0.05 then out[#out + 1] = { k, d } end
  end
  local armor = _G.RESISTANCE0_NAME or "Armor"
  local function rank(k) return k == "DPS" and 0 or k == armor and 1 or 2 end
  table.sort(out, function(a, b) if rank(a[1]) ~= rank(b[1]) then return rank(a[1]) < rank(b[1]) end return a[1] < b[1] end)
  return out
end

function T.DeltaText(label, d)
  local num = math.abs(d - math.floor(d + 0.5)) < 0.05 and string.format("%+d", math.floor(d + 0.5)) or string.format("%+.1f", d)
  return num .. " " .. (label == "DPS" and "Damage per second" or label)
end

local function sum(a, b) for k, v in pairs(b) do a[k] = (a[k] or 0) + v end return a end

-- Adds the difference lines for `link` to tip: one block per slot group that holds something. Returns the number of blocks.
function T.AddCompare(tip, link)
  if not AFUI.GetSetting("tooltipCompareStats", true) or tip.afCompareDone or not (link and _G.GetItemInfo and _G.GetInventoryItemLink) then return 0 end
  local _, _, _, ilvl, _, _, _, _, loc = GetItemInfo(link)
  local groups = loc and T.SLOTS[loc]
  if not groups or (_G.IsEquippedItem and IsEquippedItem(link)) then return 0 end
  local mine, n = T.Stats(link), 0
  for _, slots in ipairs(groups) do
    local old, first = {}, nil
    for _, slot in ipairs(slots) do
      local l = GetInventoryItemLink("player", slot)
      if l and slot == 17 and loc == "INVTYPE_WEAPON" then -- a one-hander is not weighed against a shield or a held item
        local wl = select(9, GetItemInfo(l))
        if wl ~= "INVTYPE_WEAPON" and wl ~= "INVTYPE_WEAPONOFFHAND" then l = nil end
      end
      if l then first = first or l; sum(old, T.Stats(l)) end
    end
    if first then
      n = n + 1
      local name, _, _, oldLevel = GetItemInfo(first)
      tip:AddLine(" ")
      tip:AddLine((_G.EQUIPPED or "Equipped") .. ": " .. (name or "?") .. (#slots > 1 and " + off hand" or ""), T.GREY[1], T.GREY[2], T.GREY[3])
      local rows = T.Diff(mine, old)
      if ilvl and oldLevel and ilvl ~= oldLevel then table.insert(rows, 1, { "Item Level", ilvl - oldLevel }) end
      if #rows == 0 then tip:AddLine("No difference", T.GREY[1], T.GREY[2], T.GREY[3]) end
      for _, r in ipairs(rows) do
        local c = r[2] > 0 and T.GREEN or T.RED
        tip:AddLine(T.DeltaText(r[1], r[2]), c[1], c[2], c[3])
      end
    end
  end
  if n > 0 then tip.afCompareDone = true; if tip.Show then tip:Show() end end
  return n
end

local function hasText(tip, word)
  local name = tip.GetName and tip:GetName()
  if not name or not tip.NumLines then return false end
  for i = 1, tip:NumLines() do
    local fs = _G[name .. "TextLeft" .. i]
    local t = fs and fs.GetText and fs:GetText()
    if t and string.find(t, word, 1, true) then return true end
  end
  return false
end

-- Item level (a line the TBC client does not print) and, when asked for, the ids. Once per tooltip fill (afExtraDone).
function T.AddExtras(tip, kind, id, link)
  if tip.afExtraDone then return end
  local added
  if kind == "item" and link and _G.GetItemInfo and AFUI.GetSetting("tooltipItemLevel", true) then
    local _, _, _, ilvl, _, _, _, _, loc = GetItemInfo(link)
    if ilvl and ilvl > 1 and loc and loc ~= "" and not hasText(tip, "Item Level") then
      tip:AddLine("Item Level " .. ilvl, 1, 1, 1); added = true
    end
  end
  if id and AFUI.GetSetting("tooltipIds", false) then
    local word = kind == "item" and "ItemID" or kind == "spell" and "SpellID" or kind == "quest" and "QuestID" or "ID"
    if not hasText(tip, word .. ":") then tip:AddLine(word .. ": " .. id, T.GREY[1], T.GREY[2], T.GREY[3]); added = true end
  end
  if added then tip.afExtraDone = true; if tip.Show then tip:Show() end end
end

-- "item:123:..." / "spell:123" / "quest:123:45" (a link or a hyperlink body) -> kind, id
function T.LinkId(link)
  link = tostring(link or "")
  local kind, id = link:match("|H(%a+):(%d+)")
  if not kind then kind, id = link:match("^(%a+):(%d+)") end
  return kind, id and tonumber(id)
end

local function hookIds(tip)
  if tip.HasScript and tip:HasScript("OnTooltipSetSpell") and tip.GetSpell then
    tip:HookScript("OnTooltipSetSpell", function(self) local _, id = self:GetSpell(); if id then T.AddExtras(self, "spell", id) end end)
  end
  if tip.SetHyperlink then
    hooksecurefunc(tip, "SetHyperlink", function(self, link)
      local kind, id = T.LinkId(link)
      if kind == "spell" or kind == "quest" then T.AddExtras(self, kind, id) end
    end)
  end
  for _, fn in ipairs({ "SetUnitAura", "SetUnitBuff", "SetUnitDebuff" }) do
    if tip == _G.GameTooltip and tip[fn] and _G.UnitAura then
      hooksecurefunc(tip, fn, function(self, unit, i, filter)
        local id = select(10, UnitAura(unit, i, filter or (fn == "SetUnitDebuff" and "HARMFUL" or fn == "SetUnitBuff" and "HELPFUL" or nil)))
        if id then T.AddExtras(self, "spell", id) end
      end)
    end
  end
end

-- Item Level / ids of an item tooltip. With deferExtras (Pawn is around, AddonCompat.lua) they are added by one more OnTooltipSetItem hook, put on after the other addons' hooks,
-- so lines other addons add keep their place and ours follow; the hook is inert otherwise. afExtraDone and the same-text check keep every line from showing twice.
local function itemExtras(self)
  local link; if self.GetItem then _, link = self:GetItem() end
  local _, id = T.LinkId(link)
  T.AddExtras(self, "item", id, link)
end
T.lateHooked = {}
function T.DeferExtras(on)
  if on and not AFUI.ModuleEnabled("tooltips") then return end -- our tooltip module is off: nothing of ours to add
  T.deferExtras = on and true or false
  if not on then return end
  for _, n in ipairs(T.NAMES) do
    local tip = _G[n]
    if tip and tip.HookScript and tip.HasScript and tip:HasScript("OnTooltipSetItem") and not T.lateHooked[tip] then
      T.lateHooked[tip] = true
      tip:HookScript("OnTooltipSetItem", function(self) if T.deferExtras then itemExtras(self) end end)
    end
  end
end

local done
local function setup()
  if done then return end
  done = true
  for _, n in ipairs(T.NAMES) do
    local tip = _G[n]
    if tip and tip.HookScript then
      skin(tip)
      tip:HookScript("OnShow", function(self) skin(self, itemEdge(self)); T.PlaceBar(self) end)
      tip:HookScript("OnSizeChanged", function(self) skin(self, self.afBorder and self.afBorder.edge) end)
      if tip == _G.GameTooltip and tip.HasScript and tip:HasScript("OnTooltipSetUnit") then tip:HookScript("OnTooltipSetUnit", T.PlaceBar) end
      if tip.HasScript and tip:HasScript("OnTooltipSetItem") then
        tip:HookScript("OnTooltipSetItem", function(self)
          skin(self, itemEdge(self)); T.AddSellPrice(self)
          if not T.deferExtras then itemExtras(self) end
        end)
      end
      hookIds(tip)
      if tip.HasScript and tip:HasScript("OnTooltipCleared") then
        tip:HookScript("OnTooltipCleared", function(self) self.afSellDone, self.afCompareDone, self.afExtraDone = nil, nil, nil end)
      end
    end
  end
  if type(_G.GameTooltip_ShowCompareItem) == "function" then
    hooksecurefunc("GameTooltip_ShowCompareItem", function(tip)
      tip = tip or _G.GameTooltip
      local link; if tip and tip.GetItem then _, link = tip:GetItem() end
      if link then T.AddCompare(tip, link) end
    end)
  end
  if type(_G.SharedTooltip_SetBackdropStyle) == "function" then
    hooksecurefunc("SharedTooltip_SetBackdropStyle", function(self) skin(self, self.afBorder and self.afBorder.edge) end)
  end
  -- the default anchor belongs to the HUD Tooltip box (BarExtras.lua), an Edit Mode system; one hook only
end

function T.Setup() setup() end
AFUI.RegisterModule("Tooltips", { OnLogin = T.Setup })
